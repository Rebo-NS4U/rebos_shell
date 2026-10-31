#!/usr/bin/env python3
"""Read configured Niri and Kitty shortcuts without executing their commands."""
import json
import hashlib
import os
from pathlib import Path
import re
import shlex


def token_matches(text):
    # Preserve quoted strings while ignoring KDL comments and whitespace.
    pattern = r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*|[{};\n]|[^\s{};="]+|='
    return [m for m in re.finditer(pattern, text, re.S)
            if not m.group().startswith(("//", "/*"))]


def tokens(text):
    return [m.group() for m in token_matches(text)]


def unquote(value):
    return json.loads(value) if value.startswith('"') else value


def describe_niri(body):
    command = body[0] if body else ""
    args = [unquote(t) for t in body[1:] if t not in (";", "\n")]
    if command == "spawn" and args[:3] == ["qs", "ipc", "call"]:
        labels = {
            ("audio", "increment"): "Increase volume",
            ("audio", "decrement"): "Decrease volume",
            ("audio", "toggleMute"): "Toggle audio mute",
            ("audio", "toggleMicMute"): "Toggle microphone mute",
            ("brightness", "increment"): "Increase brightness",
            ("brightness", "decrement"): "Decrease brightness",
        }
        return labels.get(tuple(args[3:5]), "Open shell control")
    if command in ("spawn", "spawn-sh"):
        # Never display arbitrary command arguments (they may contain private data).
        return "Run custom command"
    label = command.replace("-", " ").capitalize()
    if command in ("focus-workspace", "move-column-to-workspace") and args:
        label += ": " + args[0]
    if command in ("set-column-width", "set-window-height") and args:
        label += ": " + args[0]
    return label


def binding_identity(value):
    parts = value.lower().split("+")
    aliases = {"super": "mod", "mod4": "mod", "control": "ctrl"}
    return tuple(sorted(aliases.get(part, part) for part in parts[:-1])) + (parts[-1],)


def collect(config_dir, include_disabled=False):
    rows, files, errors = [], [], []
    visited = set()

    def read(path):
        path = path.expanduser().absolute()
        if path in visited:
            return None
        visited.add(path)
        files.append(str(path))
        try:
            return path.read_text()
        except FileNotFoundError:
            return None
        except OSError:
            errors.append("Could not read " + path.name)
            return None

    def niri(path):
        text = read(path)
        if text is None:
            return
        matches = token_matches(text)
        ts = [m.group() for m in matches]
        fingerprint = hashlib.sha256(text.encode()).hexdigest()
        i = 0
        while i < len(ts) - 1:
            # Includes are positional: later declarations override earlier keys.
            if ts[i] == "include":
                end = i + 1
                while end < len(ts) and ts[end] not in ("\n", ";", "{"):
                    if ts[end].startswith('"'):
                        included = Path(unquote(ts[end])).expanduser()
                        niri(included if included.is_absolute() else path.parent / included)
                        break
                    end += 1
            if ts[i:i + 2] != ["binds", "{"]:
                i += 1
                continue
            i += 2
            while i < len(ts) and ts[i] != "}":
                if ts[i] in ("\n", ";"):
                    i += 1
                    continue
                key_match = matches[i]
                key = unquote(ts[i])
                i += 1
                attributes = []
                while i < len(ts) and ts[i] not in ("{", "}"):
                    attributes.append(ts[i])
                    i += 1
                if i == len(ts) or ts[i] != "{":
                    break
                i += 1
                body, depth = [], 1
                while i < len(ts) and depth:
                    if ts[i] == "{":
                        depth += 1
                    elif ts[i] == "}":
                        depth -= 1
                    if depth:
                        body.append(ts[i])
                    i += 1
                title = ""
                for j in range(len(attributes) - 2):
                    if attributes[j:j + 2] == ["hotkey-overlay-title", "="] and attributes[j + 2] != "null":
                        title = unquote(attributes[j + 2]).strip()
                body = [t for t in body if t != "\n"]
                rows[:] = [row for row in rows if not (
                    row["group"] == "Desktop · Niri"
                    and binding_identity(row["rawKey"]) == binding_identity(key))]
                disabled = not body or body == ["spawn", '"/usr/bin/true"', ";"]
                if disabled and not include_disabled:
                    continue
                rows.append({"key": key.replace("Mod+", "Super+"),
                             "action": title or describe_niri(body),
                             "group": "Desktop · Niri", "source": str(path),
                             "rawKey": key, "start": key_match.start(), "end": key_match.end(),
                             "declarationEnd": matches[i - 1].end(), "disabled": disabled,
                             "fingerprint": fingerprint, "editable": True})
            i += 1

    def kitty(path):
        text = read(path)
        if text is None:
            return
        labels = {
            "paste_from_clipboard": "Paste from clipboard",
            "copy_to_clipboard": "Copy selection",
            "search_scrollback": "Search terminal history",
            "show_scrollback": "Open terminal history",
            "show_last_command_output": "Show last command output",
            "launch": "Open terminal window",
        }
        offset = 0
        fingerprint = hashlib.sha256(text.encode()).hexdigest()
        for raw_line in text.splitlines(keepends=True):
            line = raw_line.rstrip("\r\n")
            line_start = offset
            offset += len(raw_line)
            directive = line.split(None, 1)
            if directive and directive[0] == "include" and len(directive) == 2:
                filename = directive[1].strip()
                if filename.startswith(('"', "'")):
                    try:
                        filename, = shlex.split(filename, comments=True)
                    except ValueError:
                        continue
                included = Path(os.path.expandvars(filename)).expanduser()
                pattern = included if included.is_absolute() else path.parent / included
                import glob
                for filename in sorted(glob.glob(str(pattern))):
                    kitty(Path(filename))
                continue
            try:
                parts = shlex.split(line, comments=True)
            except ValueError:
                continue
            if not parts:
                continue
            if parts[0] == "map" and len(parts) >= 3 and not parts[1].startswith("--"):
                key, action = parts[1:3]
                if action == "scroll_to_prompt":
                    label = "Previous command prompt" if parts[3:] == ["-1"] else "Next command prompt"
                elif action == "kitten" and parts[3:] == ["hints"]:
                    label = "Open URL hints"
                elif action == "change_font_size":
                    label = {"+1.0": "Increase font size", "-1.0": "Decrease font size", "0": "Reset font size"}.get(parts[-1], "Change font size")
                else:
                    label = labels.get(action, action.replace("_", " ").capitalize())
                # Later Kitty maps override earlier maps of the same key.
                rows[:] = [r for r in rows if not (r["group"] == "Terminal · Kitty" and binding_identity(r["rawKey"]) == binding_identity(key))]
                match = re.match(r"\s*map\s+(\S+)", line)
                editable = bool(match and match.group(1) == key)
                if action == "no_op" and not include_disabled:
                    continue
                rows.append({"key": "+".join(k.capitalize() for k in key.split("+")),
                             "action": label, "group": "Terminal · Kitty", "source": str(path),
                             "rawKey": key, "start": line_start + match.start(1),
                             "end": line_start + match.end(1), "fingerprint": fingerprint,
                             "editable": editable})

    niri(config_dir / "niri/config.kdl")
    kitty(config_dir / "kitty/kitty.conf")
    return {"bindings": rows, "files": files, "error": "; ".join(errors)}


if __name__ == "__main__":
    try:
        print(json.dumps(collect(Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))))))
    except Exception:
        print(json.dumps({"bindings": [], "files": [], "error": "Could not load shortcuts from the configuration files."}))
