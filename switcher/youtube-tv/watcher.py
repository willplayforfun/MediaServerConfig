#!/usr/bin/env python3
# Watches the remote's input device for one dedicated button and tells the
# switcher to bring Kodi back when it's pressed - this is the only way back
# to Kodi, since this container otherwise just sits fullscreen on
# youtube.com/tv with no window manager to escape.
#
# REMOTE_DEVICE and RETURN_KEY are placeholders until the real remote is on
# hand: run `evtest` (or `python3 -m evdev.evtest`) against the remote's
# /dev/input/eventN to find both the device path and the exact key name its
# dedicated button sends, then set them via environment variables in
# switcher/compose.yml.

import os
import sys
import urllib.request

from evdev import InputDevice, categorize, ecodes, list_devices

REMOTE_DEVICE = os.environ.get("REMOTE_DEVICE")  # e.g. /dev/input/event4
RETURN_KEY = os.environ.get("RETURN_KEY", "KEY_HOMEPAGE")
SWITCHER_URL = os.environ.get("SWITCHER_URL", "http://switcher:8099/switch/kodi")


def find_device():
    if REMOTE_DEVICE:
        return InputDevice(REMOTE_DEVICE)
    for path in list_devices():
        dev = InputDevice(path)
        if "keyboard" in dev.name.lower() or "remote" in dev.name.lower():
            return dev
    sys.exit("[watcher] no candidate input device found; set REMOTE_DEVICE explicitly")


def matches_return_key(key):
    codes = key.keycode if isinstance(key.keycode, list) else [key.keycode]
    return RETURN_KEY in codes


def switch_to_kodi():
    try:
        urllib.request.urlopen(urllib.request.Request(SWITCHER_URL, method="POST"))
    except OSError as e:
        print(f"[watcher] failed to reach switcher: {e}", file=sys.stderr, flush=True)


def main():
    dev = find_device()
    print(f"[watcher] watching {dev.path} ({dev.name}) for {RETURN_KEY}", flush=True)
    for event in dev.read_loop():
        if event.type != ecodes.EV_KEY:
            continue
        key = categorize(event)
        if key.keystate == key.key_down and matches_return_key(key):
            print("[watcher] return key pressed, switching to kodi", flush=True)
            switch_to_kodi()


if __name__ == "__main__":
    main()
