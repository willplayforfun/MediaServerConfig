#!/usr/bin/env python3
# Simulates a remote button press for the local test harness by writing
# evdev input_event structs into the hub's FIFO (see compose.yml here).
#
# Usage: fake_remote.py <key> [hold_seconds]
#   key: home | back | enter | a numeric evdev code

import struct
import sys
import time

FIFO = "/remote/events"
KEYS = {"home": 172, "back": 158, "enter": 28}
EV_SYN, EV_KEY = 0, 1
EVENT = struct.Struct("llHHi")


def event(etype, code, value):
    now = time.time()
    return EVENT.pack(int(now), int((now % 1) * 1e6), etype, code, value)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__ or "usage: fake_remote.py <key> [hold_seconds]")
    key = sys.argv[1]
    code = int(key) if key.isdigit() else KEYS[key]
    hold = float(sys.argv[2]) if len(sys.argv) > 2 else 0.1
    with open(FIFO, "wb", buffering=0) as f:
        f.write(event(EV_KEY, code, 1) + event(EV_SYN, 0, 0))
        time.sleep(hold)
        f.write(event(EV_KEY, code, 0) + event(EV_SYN, 0, 0))
    print(f"pressed {key} (code {code}) for {hold}s")


if __name__ == "__main__":
    main()
