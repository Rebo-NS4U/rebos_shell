#!/usr/bin/env python3
"""Manage Settings-created Niri rules without rewriting existing rules."""
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import uuid

from list_keybindings import collect, token_matches

MARKER = "// rebos_shell-rule: "


def fingerprint(text):
    return hashlib.sha256(text.encode()).hexdigest()


def render_rule(rule):
    app = rule.get("appId", "").strip()
    title = rule.get("title", "").strip()
    if not app and not title:
        raise ValueError("Enter an app ID or a title to match.")
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    match = "    match"
    # Literal matching is the default. Regex is an explicit advanced option.
    for field, value in (("app-id", app), ("title", title)):
        if value:
            expression = value if rule.get("regex", False) else "^" + re.escape(value) + "$"
            match += " " + field + "=" + quote(expression)
    lines = ["window-rule {", match]
    for field, key in (("floating", "open-floating"), ("maximized", "open-maximized"), ("fullscreen", "open-fullscreen")):
        value = rule.get(field, "inherit")
        if value not in ("inherit", "true", "false"):
            raise ValueError("Choose Inherit, Yes, or No for window behavior.")
        if value != "inherit":
            lines.append("    " + key + " " + value)
    workspace = rule.get("workspace", "").strip()
    if workspace:
        lines.append("    open-on-workspace " + quote(workspace))
    opacity = rule.get("opacity", "")
    radius = rule.get("radius", "")
    width = rule.get("width", "")
    for value, minimum, maximum, label, key in (
        (opacity, 0.0, 1.0, "Opacity", "opacity"),
        (radius, 0.0, 100.0, "Corner radius", "geometry-corner-radius"),
        (width, 5.0, 100.0, "Column width", "width"),
    ):
        if value != "" and value is not None:
            try:
                number = float(value)
            except (TypeError, ValueError):
                raise ValueError(label + " must be a number.")
            if not math.isfinite(number) or not minimum <= number <= maximum:
                raise ValueError(label + " must be between " + str(minimum) + " and " + str(maximum) + ".")
            if key == "width":
                lines.append("    default-column-width { proportion " + str(number / 100) + "; }")
            else:
                lines.append("    " + key + " " + str(number))
    if len(lines) == 2:
        raise ValueError("Choose at least one window behavior or appearance setting.")
    return "\n".join(lines + ["}"])


def read_managed(path):
    text = path.read_text() if path.exists() else ""
    rules = []
    for line in text.splitlines():
        if line.startswith(MARKER):
            rules.append(json.loads(line[len(MARKER):]))
    if text and not text.startswith("// Managed by rebos_shell Settings."):
        raise ValueError("The Settings rules file has been edited outside this app. Use a separate include for manual rules.")
    if text and text != serialize(rules):
        raise ValueError("The Settings rules file changed outside this app. Preserve your manual edits before saving here.")
    return text, rules


def serialize(rules):
    pieces = ["// Managed by rebos_shell Settings. Edit these rules in Settings → Window Rules.\n"]
    for rule in rules:
        pieces.append(MARKER + json.dumps(rule, ensure_ascii=False, sort_keys=True))
        if rule.get("enabled", True):
            pieces.append(render_rule(rule))
        pieces.append("")
    return "\n".join(pieces) + "\n"


def existing_rules(config_dir, managed_path):
    rules = []
    for filename in collect(config_dir)["files"]:
        path = Path(filename)
        if path.suffix != ".kdl" or path.resolve() == managed_path.resolve() or not path.exists():
            continue
        text = path.read_text()
        matches = token_matches(text)
        for i, token in enumerate(matches[:-1]):
            if token.group() != "window-rule" or matches[i + 1].group() != "{":
                continue
            depth = 1
            end = i + 2
            while end < len(matches) and depth:
                depth += (matches[end].group() == "{") - (matches[end].group() == "}")
                end += 1
            body = text[token.start():matches[end - 1].end()]
            match_lines = [line.strip() for line in body.splitlines() if line.strip().startswith(("match ", "exclude "))]
            rules.append({"name": " · ".join(match_lines) or "All windows", "body": body,
                          "source": filename, "managed": False, "enabled": True,
                          "start": token.start(), "end": matches[end - 1].end(),
                          "fingerprint": fingerprint(text)})
    return rules


def listing(config_dir):
    path = config_dir / "niri/rebos_shell-window-rules.kdl"
    text, managed = read_managed(path)
    return {"ok": True, "fingerprint": fingerprint(text), "path": str(path),
            "rules": [dict(rule, managed=True, body=render_rule(rule)) for rule in managed]
                + existing_rules(config_dir, path)}


def write_validated(path, original, candidate):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, suffix=".kdl", prefix=".window-rules-check-", delete=False) as stream:
            stream.write(candidate)
            temporary = Path(stream.name)
        checked = subprocess.run(["niri", "validate", "-c", str(temporary)], capture_output=True, timeout=15)
        if checked.returncode:
            raise ValueError("Niri rejected this rule. Check your match expressions and values.")
        latest = path.read_text() if path.exists() else ""
        if latest != original:
            raise ValueError("The rules changed while saving. Refresh and try again.")
        if original:
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".window-rules-backup-", delete=False) as backup:
                backup.write(original.encode())
        target = path.resolve()
        os.chmod(temporary, stat.S_IMODE(target.stat().st_mode) if target.exists() else 0o600)
        os.replace(temporary, target)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def delete_existing(request, config_dir):
    selected = request.get("binding", {})
    path = config_dir / "niri/rebos_shell-window-rules.kdl"
    binding = next((rule for rule in existing_rules(config_dir, path)
                    if rule["source"] == selected.get("source")
                    and rule["start"] == selected.get("start")
                    and rule["end"] == selected.get("end")
                    and rule["fingerprint"] == selected.get("fingerprint")), None)
    if not binding:
        raise ValueError("This config rule changed. Refresh the list before deleting.")
    target = Path(binding["source"]).resolve(strict=True)
    original = target.read_text()
    if fingerprint(original) != binding["fingerprint"]:
        raise ValueError("This config rule changed. Refresh the list before deleting.")
    candidate = original[:binding["start"]] + original[binding["end"]:]
    write_validated(target, original, candidate)
    result = listing(config_dir)
    result["message"] = "Config rule deleted. A backup was saved beside its original file."
    return result


def update(request, config_dir):
    path = config_dir / "niri/rebos_shell-window-rules.kdl"
    original, rules = read_managed(path)
    if request.get("fingerprint") != fingerprint(original):
        raise ValueError("The rules changed. Refresh the list before saving.")
    operation = request.get("op")
    if operation == "delete":
        rule_id = request.get("id")
        if not any(rule["id"] == rule_id for rule in rules):
            raise ValueError("This rule no longer exists. Refresh the list.")
        rules = [rule for rule in rules if rule["id"] != rule_id]
    elif operation == "save":
        raw = request.get("rule", {})
        rule = {key: raw.get(key, default) for key, default in {
            "name": "", "appId": "", "title": "", "regex": False, "enabled": True,
            "floating": "inherit", "maximized": "inherit", "fullscreen": "inherit",
            "workspace": "", "opacity": "", "radius": "", "width": ""
        }.items()}
        for key in ("name", "appId", "title", "workspace"):
            if not isinstance(rule[key], str) or len(rule[key]) > 2048:
                raise ValueError("Rule names and matches must be text under 2048 characters.")
        rule["name"] = rule["name"].strip() or rule["appId"] or "Window rule"
        rule["id"] = raw.get("id") or uuid.uuid4().hex
        render_rule(rule)
        if raw.get("id") and not any(old["id"] == rule["id"] for old in rules):
            raise ValueError("This rule no longer exists. Refresh the list.")
        rules = [rule if old["id"] == rule["id"] else old for old in rules] if raw.get("id") else rules + [rule]
    else:
        raise ValueError("Unknown rule operation.")
    candidate = serialize(rules)
    write_validated(path, original, candidate)
    result = listing(config_dir)
    result["message"] = "Rule saved. Opening behavior applies the next time a matching window opens." if operation == "save" else "Rule deleted."
    return result


if __name__ == "__main__":
    try:
        config_dir = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
        request = json.loads(sys.stdin.readline()) if len(sys.argv) > 1 and sys.argv[1] == "edit" else {"op": "list"}
        result = (listing(config_dir) if request["op"] == "list"
                  else delete_existing(request, config_dir) if request["op"] == "delete-existing"
                  else update(request, config_dir))
    except (ValueError, KeyError, TypeError) as error:
        result = {"ok": False, "error": str(error)}
    except (OSError, subprocess.SubprocessError):
        result = {"ok": False, "error": "Could not read, validate, or save window rules."}
    print(json.dumps(result))
