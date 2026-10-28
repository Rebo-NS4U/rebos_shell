#!/usr/bin/env python3
"""Validate and persist a connected display's settings in its Niri output block."""
import json
import math
import os
from pathlib import Path
import subprocess
import sys

from list_keybindings import collect, token_matches, unquote
from window_rules import write_validated

TRANSFORMS = ("normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270")
MANAGED = {"mode", "scale", "transform", "position"}


def output_blocks(text):
    tokens = token_matches(text)
    depth = 0
    for index, token in enumerate(tokens):
        if depth == 0 and token.group() == "output" and index + 2 < len(tokens) and tokens[index + 2].group() == "{":
            end, level = index + 3, 1
            while end < len(tokens) and level:
                level += (tokens[end].group() == "{") - (tokens[end].group() == "}")
                end += 1
            if level:
                raise ValueError("Unclosed output configuration.")
            yield unquote(tokens[index + 1].group()), tokens[index + 2].end(), tokens[end - 1].start()
        depth += (token.group() == "{") - (token.group() == "}")


def replace_settings(body, settings):
    tokens = token_matches(body)
    removals = []
    depth = 0
    for index, token in enumerate(tokens):
        if depth == 0 and token.group() in MANAGED:
            end = index + 1
            while end < len(tokens) and tokens[end].group() not in (";", "\n"):
                end += 1
            removals.append((token.start(), tokens[end].end() if end < len(tokens) else len(body)))
        depth += (token.group() == "{") - (token.group() == "}")
    for start, end in reversed(removals):
        body = body[:start] + body[end:]
    return body.rstrip() + "\n" + settings + "\n"


def save(request, config_dir, outputs):
    name = request.get("name")
    output = outputs.get(name)
    if not output or output.get("current_mode") is None:
        raise ValueError("This display is no longer active. Refresh and try again.")
    mode = request.get("mode")
    modes = {f'{m["width"]}x{m["height"]}@{m["refresh_rate"] / 1000:.3f}' for m in output["modes"]}
    if mode not in modes:
        raise ValueError("Choose a mode supported by this display.")
    scale = float(request.get("scale", 0))
    if not math.isfinite(scale) or not 0.5 <= scale <= 4:
        raise ValueError("Scale must be between 50% and 400%.")
    transform = request.get("transform")
    if transform not in TRANSFORMS:
        raise ValueError("Choose a valid rotation.")
    x, y = int(request["x"]), int(request["y"])
    if any(abs(value) > 100000 for value in (x, y)):
        raise ValueError("Position must be between -100000 and 100000.")
    settings = f'    mode {json.dumps(mode)}\n    scale {scale:g}\n    transform {json.dumps(transform)}\n    position x={x} y={y}'
    matches = []
    for filename in collect(config_dir)["files"]:
        path = Path(filename)
        if not path.exists() or path.suffix != ".kdl":
            continue
        text = path.read_text()
        for selector, start, end in output_blocks(text):
            # Niri accepts either connector names or make/model/serial selectors.
            identity = " ".join(str(output.get(key) or "Unknown") for key in ("make", "model", "serial"))
            if selector in (name, identity):
                matches.append((path, text, start, end))
    if len(matches) > 1:
        raise ValueError("This display has multiple output blocks. Consolidate them before saving here.")
    if matches:
        path, original, start, end = matches[0]
        candidate = original[:start] + replace_settings(original[start:end], settings) + original[end:]
    else:
        path = config_dir / "niri/config.kdl"
        original = path.read_text()
        candidate = original.rstrip() + f'\n\noutput {json.dumps(name)} {{\n{settings}\n}}\n'
    write_validated(path, original, candidate)
    return {"ok": True, "message": "Display settings saved and applied. A backup was saved beside the config."}


def main():
    try:
        request = json.loads(sys.stdin.readline())
        result = subprocess.run(["niri", "msg", "--json", "outputs"], capture_output=True, text=True, timeout=10)
        if result.returncode:
            raise ValueError("Could not contact Niri. Try again from your desktop session.")
        config_dir = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        response = save(request, config_dir, json.loads(result.stdout))
    except (ValueError, TypeError, KeyError, OSError, subprocess.SubprocessError) as error:
        response = {"ok": False, "error": str(error)}
    print(json.dumps(response))


if __name__ == "__main__":
    main()
