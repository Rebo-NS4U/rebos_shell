#!/usr/bin/env python3
"""Change one shortcut token, preserving the action and surrounding config."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

from list_keybindings import collect


MODIFIERS = {"ctrl": "Ctrl", "control": "Ctrl", "shift": "Shift",
             "alt": "Alt", "super": "Super", "mod": "Super", "win": "Super",
             "meta": "Super", "mod4": "Super"}
KEY_ALIASES = {"enter": "Return", "esc": "Escape", "pgup": "Page_Up",
               "pgdown": "Page_Down", ".": "period", ",": "comma",
               "-": "minus", "=": "equal", "/": "slash", "`": "grave"}


def normalize_key(value, group):
    value = value.strip()
    if not value or len(value) > 100 or not re.fullmatch(r"[A-Za-z0-9_+.,/`=\-]+", value):
        raise ValueError("Use a shortcut such as Super+Shift+A or Ctrl+Shift+F.")
    parts = value.split("+")
    if not parts[-1]:
        raise ValueError("Name the plus key 'plus', for example Ctrl+plus.")
    modifiers = []
    for part in parts[:-1]:
        mod = MODIFIERS.get(part.lower())
        if not mod or mod in modifiers:
            raise ValueError("Use Ctrl, Shift, Alt, or Super once each.")
        modifiers.append(mod)
    modifiers.sort()
    key = KEY_ALIASES.get(parts[-1].lower(), parts[-1])
    if group == "Desktop · Niri":
        modifiers = ["Mod" if m == "Super" else m for m in modifiers]
    elif len(key) == 1:
        key = key.lower()
    return "+".join(modifiers + [key])


def equivalent(value, group):
    try:
        return normalize_key(value, group).lower()
    except ValueError:
        return value.lower()


def save(request, config_dir):
    selected = request.get("binding", {})
    data = collect(config_dir)
    binding = next((row for row in data["bindings"]
                    if row["source"] == selected.get("source")
                    and row["start"] == selected.get("start")
                    and row["rawKey"] == selected.get("rawKey")
                    and row["fingerprint"] == selected.get("fingerprint")), None)
    if not binding:
        raise ValueError("This configuration changed. Refresh the list and select the shortcut again.")
    if not binding["editable"]:
        raise ValueError("This mapping needs to be edited in its configuration file.")
    new_key = normalize_key(request.get("key", ""), binding["group"])
    if equivalent(new_key, binding["group"]) == equivalent(binding["rawKey"], binding["group"]):
        return {"ok": True, "message": "Shortcut unchanged."}
    for row in data["bindings"]:
        if row["group"] == binding["group"] and row != binding:
            if equivalent(row["rawKey"], row["group"]) == equivalent(new_key, binding["group"]):
                raise ValueError("That shortcut is already assigned to " + row["action"] + ".")
    target = Path(binding["source"]).resolve(strict=True)
    original = target.read_text()
    if hashlib.sha256(original.encode()).hexdigest() != binding["fingerprint"]:
        raise ValueError("This configuration changed. Refresh the list before saving.")
    replacement = json.dumps(new_key) if original[binding["start"]] == '"' else new_key
    candidate = original[:binding["start"]] + replacement + original[binding["end"]:]
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, prefix=".keybinding-check-", suffix=target.suffix, delete=False) as stream:
            stream.write(candidate)
            temporary = Path(stream.name)
        if binding["group"] == "Desktop · Niri":
            checked = subprocess.run(["niri", "validate", "-c", str(temporary)], capture_output=True, timeout=15)
        else:
            # Kitty's own parser recognizes its key names and modifier aliases.
            code = "import sys; from kitty.options.utils import parse_shortcut; k=parse_shortcut(sys.stdin.readline().strip()); sys.exit(0 if k.key else 1)"
            checked = subprocess.run(["kitty", "+runpy", code], input=new_key + "\n", text=True, capture_output=True, timeout=15)
        if checked.returncode != 0:
            raise ValueError("That key combination is not valid for " + ("Niri" if binding["group"] == "Desktop · Niri" else "Kitty") + ". Check the key name and try again.")
        if target.read_text() != original:
            raise ValueError("This configuration changed while saving. Refresh and try again.")
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix="." + target.name + ".keybindings-backup-", delete=False) as backup:
            backup.write(original.encode())
            backup_path = backup.name
        os.chmod(temporary, stat.S_IMODE(target.stat().st_mode))
        os.replace(temporary, target)
        temporary = None
        message = "Shortcut saved. Niri applies it automatically."
        if binding["group"] == "Terminal · Kitty":
            try:
                reloaded = subprocess.run(["pkill", "-SIGUSR1", "-x", "kitty"], capture_output=True, timeout=5)
                message = "Shortcut saved and Kitty configuration reloaded." if reloaded.returncode == 0 else "Shortcut saved. Kitty will use it when opened."
            except (OSError, subprocess.SubprocessError):
                message = "Shortcut saved. Open a new Kitty window to load it."
        return {"ok": True, "message": message, "backup": backup_path}
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        request = json.loads(sys.stdin.readline())
        config_dir = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
        result = save(request, config_dir)
    except ValueError as error:
        result = {"ok": False, "error": str(error)}
    except (OSError, subprocess.SubprocessError):
        result = {"ok": False, "error": "Could not validate or save this shortcut. Check that its configuration file is writable."}
    print(json.dumps(result))
