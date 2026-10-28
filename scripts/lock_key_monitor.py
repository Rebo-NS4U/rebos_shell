#!/usr/bin/env python3
"""Watch keyboard LED state through readable sysfs files, without reading keys."""

import json
from pathlib import Path
import time


KEYS = {"capslock": "caps", "numlock": "num", "scrolllock": "scroll"}


def read_leds(directory=Path("/sys/class/leds")):
    snapshot = {}
    for path in sorted(directory.glob("*::*lock")):
        key = KEYS.get(path.name.rsplit(":", 1)[-1])
        if key:
            try:
                snapshot[str(path)] = (key, int((path / "brightness").read_text().strip()) > 0)
            except (OSError, ValueError):
                pass
    return snapshot


class LockState:
    def __init__(self):
        self.previous = {}
        self.states = {}

    def update(self, snapshot):
        changes = []
        available = sorted({value[0] for value in snapshot.values()})
        for key in available:
            readings = [value for value in snapshot.values() if value[0] == key]
            changed = [value[1] for path, value in snapshot.items()
                       if value[0] == key and path in self.previous and value != self.previous[path]]
            if key not in self.states:
                self.states[key] = sum(value[1] for value in readings) > len(readings) / 2
            elif changed:
                value = sum(changed) > len(changed) / 2
                if value != self.states[key]:
                    self.states[key] = value
                    changes.append(key)
        self.previous = snapshot
        self.states = {key: self.states[key] for key in available}
        return {"states": dict(self.states), "changed": changes}


def main():
    state = LockState()
    previous = None
    while True:
        event = state.update(read_leds())
        if event != previous:
            print(json.dumps(event), flush=True)
            previous = event
        time.sleep(0.15)


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
