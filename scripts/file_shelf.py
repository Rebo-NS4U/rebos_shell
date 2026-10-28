#!/usr/bin/env python3
"""Read one JSON URI batch from stdin and describe existing local files.

This helper never modifies files. Shelf entries are references, not copies.
"""
import json
import mimetypes
import os
from pathlib import Path
import stat
import sys
from urllib.parse import unquote, urlsplit

MAX_FILES = 64


def describe(values):
    entries, seen, rejected = [], set(), 0
    for value in values[:256]:
        try:
            if not isinstance(value, str) or len(value) > 16384:
                raise ValueError("Invalid URI")
            uri = urlsplit(value)
            if uri.scheme != "file" or uri.netloc not in ("", "localhost") or uri.query or uri.fragment:
                raise ValueError("Local files only")
            path = unquote(uri.path, errors="strict")
            if not path.startswith("/") or "\0" in path:
                raise ValueError("Invalid path")
            path = os.path.abspath(path)
            info = os.stat(path)
            directory = stat.S_ISDIR(info.st_mode)
            if not directory and not stat.S_ISREG(info.st_mode):
                raise ValueError("Unsupported file")
            normalized = Path(path).as_uri()
            if normalized in seen:
                continue
            seen.add(normalized)
            mime = mimetypes.guess_type(path)[0] or "application/octet-stream"
            preview = mime in {"image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp", "image/avif"}
            entries.append({"uri": normalized, "path": path, "name": Path(path).name or path,
                            "directory": directory, "preview": preview and not directory,
                            "size": info.st_size if not directory else 0})
            if len(entries) >= MAX_FILES:
                break
        except (ValueError, OSError, UnicodeError):
            rejected += 1
    return {"entries": entries, "rejected": rejected}


def main():
    try:
        values = json.loads(sys.stdin.readline(1048576))
        if not isinstance(values, list):
            raise ValueError("Expected a URI list")
        print(json.dumps(describe(values)), flush=True)
    except (ValueError, TypeError):
        print(json.dumps({"entries": [], "error": "Could not read the dropped files."}), flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
