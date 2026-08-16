#!/usr/bin/env python3
# Stops whichever container in SWITCH_GROUP is currently running and starts
# the requested one, since only one of them can own the display (DRM/KMS) at
# a time - Kodi and any kiosk browser app can't run simultaneously. Talks to
# the Docker Engine API over the mounted socket rather than shelling out to a
# `docker` CLI, since this image has none installed.
#
# "Currently running" is determined by asking the Engine API on every
# request rather than tracked in memory, so it stays correct even if this
# container itself restarts mid-session.

import http.client
import json
import os
import socket
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DOCKER_SOCK = "/var/run/docker.sock"
SWITCH_GROUP = [n.strip() for n in os.environ.get("SWITCH_GROUP", "").split(",") if n.strip()]
LISTEN_PORT = int(os.environ.get("PORT", "8099"))
STOP_TIMEOUT = int(os.environ.get("STOP_TIMEOUT", "10"))


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
        body = resp.read()
        return resp.status, body
    finally:
        conn.close()


def is_running(name):
    status, body = docker_request("GET", f"/containers/{name}/json")
    if status == 404:
        return False
    if status != 200:
        raise RuntimeError(f"inspect {name} failed: {status} {body!r}")
    return json.loads(body)["State"]["Running"]


def stop(name):
    status, body = docker_request(
        "POST", f"/containers/{name}/stop?t={STOP_TIMEOUT}", timeout=STOP_TIMEOUT + 10
    )
    if status not in (204, 304):  # 304 = already stopped
        raise RuntimeError(f"stop {name} failed: {status} {body!r}")


def start(name):
    status, body = docker_request("POST", f"/containers/{name}/start")
    if status not in (204, 304):  # 304 = already started
        raise RuntimeError(f"start {name} failed: {status} {body!r}")


def switch_to(target):
    if target not in SWITCH_GROUP:
        raise ValueError(f"{target!r} is not in SWITCH_GROUP ({SWITCH_GROUP})")
    for name in SWITCH_GROUP:
        if name != target and is_running(name):
            print(f"[switcher] stopping {name}", flush=True)
            stop(name)
    print(f"[switcher] starting {target}", flush=True)
    start(target)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        prefix = "/switch/"
        if not self.path.startswith(prefix):
            self.send_response(404)
            self.end_headers()
            return

        target = self.path[len(prefix):]
        try:
            switch_to(target)
        except ValueError as e:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(str(e).encode())
        except RuntimeError as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(str(e).encode())
        else:
            self.send_response(204)
            self.end_headers()

    def log_message(self, fmt, *args):
        print(f"[switcher] {self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    if not SWITCH_GROUP:
        sys.exit("SWITCH_GROUP env var must be set (comma-separated container names)")
    print(f"[switcher] listening on :{LISTEN_PORT}, group={SWITCH_GROUP}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler).serve_forever()
