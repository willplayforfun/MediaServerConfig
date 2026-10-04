#!/usr/bin/env python3
# TV hub: serves the launcher page, switches apps (only one can own the
# display, so launching one stops the rest via the Docker socket), reads the
# remote from evdev, and sleeps/wakes the display by blanking the console.
# The current app is always read from Docker, never tracked in memory, so it
# stays correct across a hub restart.

import fcntl
import glob
import http.client
import json
import os
import socket
import struct
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DOCKER_SOCK = "/var/run/docker.sock"
PORT = int(os.environ.get("PORT", "8099"))
STOP_TIMEOUT = int(os.environ.get("STOP_TIMEOUT", "10"))
HOME_APP = "home"

# Blanking acts on the foreground VT, so any VT device works.
CONSOLE_TTY = os.environ.get("CONSOLE_TTY", "/dev/tty1")
# The host's /proc/asound, to check for playing audio before an idle sleep.
ASOUND_DIR = os.environ.get("ASOUND_DIR", "/host/asound")

HOME_IDLE = float(os.environ.get("HOME_IDLE_MINUTES", "10")) * 60
APP_IDLE = float(os.environ.get("APP_IDLE_MINUTES", "240")) * 60
LONG_PRESS = float(os.environ.get("LONG_PRESS_SECONDS", "1.5"))
# "home" or "sleep" (dark until a key is pressed).
BOOT_STATE = os.environ.get("BOOT_STATE", "home")

# Tile label and colour. Unlisted apps get a plain tile with their name.
APP_META = {
    "youtube": {"label": "YouTube", "color": "#ff0033"},
    "jellyfin": {"label": "Jellyfin", "color": "#8e5cf7"},
    "steam": {"label": "Steam", "color": "#1a9fff"},
}

# Common remote key names. Any other key can be given by its evtest code.
KEY_CODES = {
    "KEY_ESC": 1, "KEY_ENTER": 28, "KEY_HOME": 102, "KEY_UP": 103,
    "KEY_LEFT": 105, "KEY_RIGHT": 106, "KEY_DOWN": 108, "KEY_POWER": 116,
    "KEY_COMPOSE": 127, "KEY_MENU": 139, "KEY_SLEEP": 142, "KEY_BACK": 158,
    "KEY_CONFIG": 171, "KEY_HOMEPAGE": 172, "KEY_EXIT": 174,
    "KEY_SEARCH": 217, "KEY_SELECT": 353, "KEY_CONTEXT_MENU": 438,
}

EV_KEY, EV_REL, EV_ABS = 1, 2, 3
INPUT_EVENT = struct.Struct("llHHi")  # struct input_event on 64-bit

TIOCLINUX = 0x541C
TIOCL_UNBLANKSCREEN = 4
TIOCL_BLANKSCREEN = 14


def log(msg):
    print(f"[tv-hub] {msg}", flush=True)


def parse_apps(spec):
    """'home=tv-home,youtube=tv-youtube' -> {'home': 'tv-home', ...} (ordered)."""
    apps = {}
    for item in spec.split(","):
        if "=" in item:
            name, container = item.split("=", 1)
            apps[name.strip()] = container.strip()
    return apps


def parse_key(spec, var):
    spec = spec.strip()
    if not spec:
        return None
    if spec.isdigit():
        return int(spec)
    if spec in KEY_CODES:
        return KEY_CODES[spec]
    sys.exit(f"{var}={spec!r} isn't a known key name - use the numeric code evtest prints instead")


APPS = parse_apps(os.environ.get("APPS", ""))
HOME_KEY = parse_key(os.environ.get("HOME_KEY", "KEY_HOMEPAGE"), "HOME_KEY")
SLEEP_KEY = parse_key(os.environ.get("SLEEP_KEY", ""), "SLEEP_KEY")
REMOTE_DEVICES = [d.strip() for d in os.environ.get("REMOTE_DEVICES", "").split(",") if d.strip()]


# ── Docker Engine API ──────────────────────────────────────────────────────

class DockerSocketConnection(http.client.HTTPConnection):
    """HTTPConnection over the Docker Engine API's unix socket instead of TCP."""

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(DOCKER_SOCK)


def docker_request(method, path, timeout=30):
    conn = DockerSocketConnection("localhost", timeout=timeout)
    try:
        conn.request(method, path)
        resp = conn.getresponse()
        return resp.status, resp.read()
    finally:
        conn.close()


def is_running(container):
    status, body = docker_request("GET", f"/containers/{container}/json")
    if status == 404:
        return False
    if status != 200:
        raise RuntimeError(f"inspect {container} failed: {status} {body!r}")
    return json.loads(body)["State"]["Running"]


def stop(container):
    status, body = docker_request(
        "POST", f"/containers/{container}/stop?t={STOP_TIMEOUT}", timeout=STOP_TIMEOUT + 10
    )
    if status not in (204, 304):  # 304 = already stopped
        raise RuntimeError(f"stop {container} failed: {status} {body!r}")


def start(container):
    status, body = docker_request("POST", f"/containers/{container}/start")
    if status == 404:
        raise RuntimeError(
            f"container {container} doesn't exist - re-run env-setup.sh to create the TV app containers"
        )
    if status not in (204, 304):  # 304 = already started
        raise RuntimeError(f"start {container} failed: {status} {body!r}")


# ── Console blanking & audio activity ──────────────────────────────────────

def console(subcode):
    # Same ioctl `setterm --blank force|poke` uses. Needs CAP_SYS_ADMIN, since
    # the console isn't this process's controlling tty.
    try:
        fd = os.open(CONSOLE_TTY, os.O_RDWR | os.O_NOCTTY)
        try:
            fcntl.ioctl(fd, TIOCLINUX, bytes([subcode]))
        finally:
            os.close(fd)
    except OSError as e:
        log(f"console ioctl {subcode} on {CONSOLE_TTY} failed: {e}")


def audio_playing():
    for status in glob.glob(f"{ASOUND_DIR}/card*/pcm*p/sub*/status"):
        try:
            with open(status) as f:
                if "state: RUNNING" in f.read():
                    return True
        except OSError:
            pass
    return False


# ── Hub state ──────────────────────────────────────────────────────────────

class Hub:
    def __init__(self):
        # Re-entrant: the idle loop holds it while calling launch()/sleep().
        self.lock = threading.RLock()
        self.asleep = False
        self.last_input = time.monotonic()
        self.home_down_at = None
        self.swallow_release = None

    def touch(self):
        self.last_input = time.monotonic()

    def current_app(self):
        for name, container in APPS.items():
            if is_running(container):
                return name
        return None

    def launch(self, app):
        if app not in APPS:
            raise ValueError(f"unknown app {app!r} (known: {', '.join(APPS)})")
        with self.lock:
            if self.asleep:
                console(TIOCL_UNBLANKSCREEN)
            for name, container in APPS.items():
                if name != app and is_running(container):
                    log(f"stopping {container}")
                    stop(container)
            log(f"starting {APPS[app]}")
            start(APPS[app])
            self.asleep = False
            self.touch()

    def sleep(self):
        with self.lock:
            for container in APPS.values():
                if is_running(container):
                    log(f"stopping {container}")
                    stop(container)
            # Stop first: when the last DRM client exits, the kernel restores
            # the console, which would turn the display back on.
            console(TIOCL_BLANKSCREEN)
            self.asleep = True
            log("asleep - display off")

    def on_key(self, code, value):
        if value == 1:  # key down
            if self.asleep:
                # Any key wakes. Ignore its release so a Home press that
                # woke the display isn't also handled as a Home press.
                self.swallow_release = code
                log("key pressed while asleep - waking")
                self.launch(HOME_APP)
            elif code == HOME_KEY:
                self.home_down_at = time.monotonic()
            elif SLEEP_KEY is not None and code == SLEEP_KEY:
                self.sleep()
        elif value == 0:  # key up
            if code == self.swallow_release:
                self.swallow_release = None
            elif code == HOME_KEY and self.home_down_at is not None:
                held = time.monotonic() - self.home_down_at
                self.home_down_at = None
                if held >= LONG_PRESS:
                    self.sleep()
                else:
                    self.launch(HOME_APP)

    def idle_check(self):
        with self.lock:
            if self.asleep:
                return
            current = self.current_app()
            if current is None:
                # The app on screen exited on its own (e.g. a stream ended).
                log("nothing on screen - returning to the launcher")
                self.launch(HOME_APP)
                return
            idle = time.monotonic() - self.last_input
            if current == HOME_APP:
                if idle >= HOME_IDLE:
                    log(f"launcher idle {idle / 60:.0f} min - sleeping")
                    self.sleep()
            elif idle >= APP_IDLE and not audio_playing():
                log(f"{current} idle {idle / 60:.0f} min with no audio - sleeping")
                self.sleep()


HUB = Hub()


# ── Remote input ───────────────────────────────────────────────────────────

def watch_device(path, retry, active):
    """Reads one evdev node. With retry, reopens forever (explicit devices that
    may be unplugged); otherwise exits on error and lets discovery re-add it."""
    while True:
        try:
            with open(path, "rb", buffering=0) as f:
                log(f"watching {path}")
                while True:
                    data = f.read(INPUT_EVENT.size)
                    if len(data) < INPUT_EVENT.size:
                        break
                    _sec, _usec, etype, code, value = INPUT_EVENT.unpack(data)
                    if etype in (EV_REL, EV_ABS):
                        HUB.touch()  # pointer motion is activity, but doesn't wake
                    elif etype == EV_KEY:
                        HUB.touch()
                        try:
                            HUB.on_key(code, value)
                        except Exception as e:
                            log(f"key handling failed: {e}")
        except OSError as e:
            log(f"{path}: {e}")
        if not retry:
            active.discard(path)
            return
        time.sleep(5)


def start_input_watchers():
    active = set()
    if REMOTE_DEVICES:
        for path in REMOTE_DEVICES:
            threading.Thread(target=watch_device, args=(path, True, active), daemon=True).start()
        return

    # No devices configured: watch every input device, picking up ones
    # plugged in later (e.g. the remote's USB dongle).
    def discover():
        while True:
            for path in sorted(glob.glob("/dev/input/event*")):
                if path not in active:
                    active.add(path)
                    threading.Thread(
                        target=watch_device, args=(path, False, active), daemon=True
                    ).start()
            time.sleep(10)

    threading.Thread(target=discover, daemon=True).start()


def idle_loop():
    while True:
        time.sleep(20)
        try:
            HUB.idle_check()
        except Exception as e:
            log(f"idle check failed: {e}")


# ── HTTP: launcher page + API ──────────────────────────────────────────────

def launcher_html():
    tiles = []
    for name in APPS:
        if name == HOME_APP:
            continue
        meta = APP_META.get(name, {})
        tiles.append({"id": name, "label": meta.get("label", name), "color": meta.get("color", "#888")})
    with open(os.path.join(os.path.dirname(__file__), "launcher.html"), encoding="utf-8") as f:
        page = f.read()
    return page.replace("/*TILES*/[]", json.dumps(tiles))


class Handler(BaseHTTPRequestHandler):
    def send(self, status, body=b"", content_type="text/plain; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/":
            self.send(200, launcher_html().encode(), "text/html; charset=utf-8")
        elif self.path == "/api/state":
            with HUB.lock:
                state = {"asleep": HUB.asleep, "current": HUB.current_app(), "apps": list(APPS)}
            self.send(200, json.dumps(state).encode(), "application/json")
        else:
            self.send(404)

    def do_POST(self):
        try:
            if self.path.startswith("/launch/"):
                HUB.launch(self.path[len("/launch/"):])
            elif self.path == "/sleep":
                HUB.sleep()
            else:
                self.send(404)
                return
        except ValueError as e:
            self.send(400, str(e).encode())
        except RuntimeError as e:
            log(str(e))
            self.send(502, str(e).encode())
        else:
            self.send(204)

    def log_message(self, fmt, *args):
        log(f"{self.address_string()} {fmt % args}")


def main():
    if HOME_APP not in APPS:
        sys.exit("APPS must include home=<container> (e.g. APPS=home=tv-home,youtube=tv-youtube)")
    log(f"apps={APPS} home_key={HOME_KEY} sleep_key={SLEEP_KEY} "
        f"devices={REMOTE_DEVICES or 'all'} idle(home/app)={HOME_IDLE / 60:.0f}/{APP_IDLE / 60:.0f} min")

    # Adopt whatever is already on screen (the hub itself restarted);
    # otherwise apply BOOT_STATE.
    try:
        if HUB.current_app() is None:
            if BOOT_STATE == "sleep":
                HUB.sleep()
            else:
                HUB.launch(HOME_APP)
    except Exception as e:
        log(f"initial launch failed: {e}")

    start_input_watchers()
    threading.Thread(target=idle_loop, daemon=True).start()
    log(f"listening on :{PORT}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
