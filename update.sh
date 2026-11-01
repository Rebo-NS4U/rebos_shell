#!/usr/bin/env bash
# Standalone, preference-preserving GitHub updater. No installer or sudo calls.
set -euo pipefail
command -v git >/dev/null || { echo 'Git is required.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 is required.' >&2; exit 1; }
export REBOS_UPDATE_SCRIPT_DIR
REBOS_UPDATE_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 - "$@" <<'PY'
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile


def git(*args, **kwargs):
    return subprocess.check_output(["git", *map(str, args)], **kwargs)


def main():
    parser = argparse.ArgumentParser(prog="update.sh", description=(
        "Update an existing rebos_shell checkout; back up changed files and leave "
        "saved preferences, state, cache, and unrelated local files untouched."))
    parser.add_argument("--path", default=os.environ["REBOS_UPDATE_SCRIPT_DIR"],
                        help="existing shell checkout (default: this script's directory)")
    parser.add_argument("--repo", default=os.environ.get(
        "REBOS_SHELL_REPO_URL", "https://github.com/Rebo-NS4U/rebos_shell.git"))
    parser.add_argument("--branch", default="HEAD", help="remote branch (default: remote default branch)")
    parser.add_argument("--check", action="store_true", help="preview changes without replacing files")
    args = parser.parse_args()
    target = Path(args.path).expanduser().resolve()
    if not (target / "shell.qml").is_file() or not (target / "cli.sh").is_file():
        parser.error("--path must be an existing rebos_shell checkout")
    root = Path(git("-C", target, "rev-parse", "--show-toplevel").decode().strip()).resolve()
    if target != root:
        parser.error("the shell must be the root of its own Git checkout")
    gitdir = Path(git("-C", target, "rev-parse", "--absolute-git-dir").decode().strip())
    update_lock = (gitdir / "rebos-shell-update.lock").open("a")
    try:
        fcntl.flock(update_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.error("another shell update is running for this checkout")
    # Do not allow code updates to cover the user's separate saved data trees.
    for env, fallback in (("XDG_CONFIG_HOME", ".config"), ("XDG_STATE_HOME", ".local/state"),
                          ("XDG_DATA_HOME", ".local/share"), ("XDG_CACHE_HOME", ".cache")):
        saved = (Path(os.environ.get(env, str(Path.home() / fallback))) / "rebos_shell").resolve()
        if saved == target or target in saved.parents or saved in target.parents:
            parser.error("the checkout must be separate from rebos_shell's saved user data")
    if git("-C", target, "ls-files", "-u"):
        parser.error("resolve the current Git merge conflicts before updating")
    old = git("-C", target, "rev-parse", "HEAD").decode().strip()
    print("Fetching the requested shell version…", flush=True)
    git("-C", target, "fetch", "--no-tags", "--", args.repo, args.branch)
    new = git("-C", target, "rev-parse", "FETCH_HEAD^{commit}").decode().strip()
    tree = {}
    for entry in git("-C", target, "ls-tree", "-rz", "--full-tree", new).split(b"\0"):
        if not entry:
            continue
        meta, name = entry.split(b"\t", 1)
        mode, kind, _ = meta.split()
        if kind != b"blob":
            parser.error("submodules are not supported by this updater")
        tree[os.fsdecode(name)] = mode
    if not {"shell.qml", "cli.sh", "config/Config.qml"}.issubset(tree):
        parser.error("the fetched version is not a rebos_shell source tree")
    tracked = {os.fsdecode(p) for p in git("-C", target, "ls-files", "-z").split(b"\0") if p}
    tracked.update(os.fsdecode(p) for p in git(
        "-C", target, "ls-tree", "-rz", "--name-only", old).split(b"\0") if p)
    with tempfile.TemporaryDirectory(prefix="rebos-shell-update-") as tmp:
        stage = Path(tmp) / "source"
        stage.mkdir()
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(tmp) / "index"))
        git("-C", target, "read-tree", new, env=env)
        git("-C", target, "checkout-index", "--all", f"--prefix={stage}/", env=env)
        changed = []
        removed = []
        for name in sorted(tracked | tree.keys()):
            dest = target / name
            # Refuse directory/file collisions and symlink ancestors before touching anything.
            for parent in dest.parents:
                if parent == target:
                    break
                if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
                    parser.error(f"move the conflicting parent out of the checkout first: {parent}")
            exists = os.path.lexists(dest)
            if exists and dest.is_dir() and not dest.is_symlink():
                parser.error(f"move the conflicting directory out of the checkout first: {dest}")
            if exists and not (dest.is_file() or dest.is_symlink()):
                parser.error(f"unsupported file type: {dest}")
            if name not in tree:
                if exists:
                    removed.append(name)
                continue
            src = stage / name
            if src.is_symlink():
                same = dest.is_symlink() and os.readlink(dest) == os.readlink(src)
            else:
                same = (exists and not dest.is_symlink()
                        and dest.read_bytes() == src.read_bytes()
                        and bool(dest.stat().st_mode & stat.S_IXUSR)
                        == bool(src.stat().st_mode & stat.S_IXUSR))
            if not same:
                changed.append(name)
        print(f"{len(changed)} files to add/replace; {len(removed)} obsolete tracked files to remove.")
        for name in changed + removed:
            print(f"  {'remove' if name in removed else 'update'}: {name}")
        if args.check:
            print("Preview complete. Shell files and preferences were not changed.")
            return
        if not changed and not removed and old == new:
            print("Already up to date. Preferences preserved.")
            return
        # Back up only existing files that will actually change, plus recovery metadata.
        backup_root = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
        backup_root = backup_root / "rebos_shell/backups"
        backup_root.mkdir(parents=True, exist_ok=True, mode=0o700)
        backup = Path(tempfile.mkdtemp(prefix="update-", dir=backup_root))
        print(f"Backup: {backup}", flush=True)
        for name in changed + removed:
            src = target / name
            if os.path.lexists(src):
                dest = backup / "files" / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dest, follow_symlinks=False)
        if (gitdir / "index").exists():
            shutil.copy2(gitdir / "index", backup / "git-index")
        (backup / "manifest.json").write_text(json.dumps({
            "checkout": str(target), "previous_commit": old, "new_commit": new,
            "updated": changed, "removed": removed,
            "added": [n for n in changed if not os.path.lexists(target / n)],
        }, indent=2) + "\n")
        # Copy only changed files. Atomic per-file replacement also avoids writing
        # through an existing symlink or leaving a half-written QML file on reload.
        for name in changed:
            dest = target / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            fd, temporary = tempfile.mkstemp(prefix=".rebos-update-", dir=dest.parent)
            os.close(fd)
            try:
                os.unlink(temporary)
                shutil.copy2(stage / name, temporary, follow_symlinks=False)
                os.replace(temporary, dest)
            finally:
                if os.path.lexists(temporary):
                    os.unlink(temporary)
        for name in removed:
            (target / name).unlink()
        # Update Git's index and branch without rewriting unchanged worktree files.
        git("-C", target, "read-tree", "--reset", new)
        git("-C", target, "update-ref", "-m", "rebos_shell preference-preserving update", "HEAD", new, old)
        print(f"Updated to {new[:12]}. Preferences preserved; no services restarted.")


try:
    main()
except (OSError, subprocess.CalledProcessError) as error:
    print(f"Update failed: {error}. Any backup already printed above is retained.", file=sys.stderr)
    sys.exit(1)
PY
