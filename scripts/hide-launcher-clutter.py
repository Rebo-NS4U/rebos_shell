#!/usr/bin/env python3
"""Hide selected developer/test launcher entries without uninstalling apps.

Run with python3 scripts/hide-launcher-clutter.py. Overrides live under
$XDG_DATA_HOME/applications (normally ~/.local/share/applications).
"""

import os
from pathlib import Path
import re


DESKTOP_IDS = (
    "assistant.desktop",  # Qt documentation viewer, not rebos-assistant
    "designer.desktop",
    "linguist.desktop",
    "qdbusviewer.desktop",
    "cmake-gui.desktop",
    "lstopo.desktop",
    "qv4l2.desktop",
    "qvidcap.desktop",
    "xgps.desktop",
    "xgpsspeed.desktop",
    "scrcpy-console.desktop",
)


def main():
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    roots = [data_home, *(Path(p) for p in data_dirs.split(":") if p)]
    destination = data_home / "applications"
    destination.mkdir(parents=True, exist_ok=True)

    for desktop_id in DESKTOP_IDS:
        source = next((root / "applications" / desktop_id for root in roots
                       if (root / "applications" / desktop_id).is_file()), None)
        if source is None:
            print(f"Not installed: {desktop_id}")
            continue

        original = source.read_text()
        section = re.search(r"^\[Desktop Entry\][ \t]*\r?$", original, re.M)
        if section is None:
            raise ValueError(f"Missing Desktop Entry group: {source}")
        start = section.end()
        next_group = re.search(r"^\[", original[start:], re.M)
        end = start + next_group.start() if next_group else len(original)
        entry = original[start:end]
        if re.search(r"^NoDisplay=", entry, re.M):
            entry = re.sub(r"^NoDisplay=.*$", "NoDisplay=true", entry, flags=re.M)
        else:
            entry = "\nNoDisplay=true" + entry
        updated = original[:start] + entry + original[end:]
        target = destination / desktop_id
        if not target.exists() or target.read_text() != updated:
            target.write_text(updated)
        print(f"Hidden: {desktop_id}")


if __name__ == "__main__":
    main()
