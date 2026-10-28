#!/usr/bin/env python3
"""Capture a frozen desktop shell's thread stacks without restarting it."""

import datetime
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys


def capture(command, timeout=15):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        return result.stdout + result.stderr
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        return output + "\nDiagnostic command timed out.\n"


def main():
    for command in ("gdb", "ps", "pgrep", "journalctl"):
        if not shutil.which(command):
            sys.exit(f"Missing diagnostic dependency: {command}")

    uid = int(os.environ.get("SUDO_UID", os.getuid()))
    user = pwd.getpwuid(uid)
    if os.geteuid() != 0:
        sys.exit("Run with sudo so the debugger can attach under the system's ptrace policy.")

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    directory = Path(user.pw_dir) / ".local/state/rebos_shell/diagnostics" / f"hang-{stamp}"
    created = [path for path in (directory, *directory.parents) if not path.exists()]
    directory.mkdir(parents=True, mode=0o700)
    for path in created:
        os.chown(path, user.pw_uid, user.pw_gid)

    def save(name, text):
        path = directory / name
        path.write_text(text)
        path.chmod(0o600)
        os.chown(path, user.pw_uid, user.pw_gid)

    # Deliberately omit command arguments, environment variables, and locals.
    save("processes.txt", capture([
        "ps", "-u", str(uid), "-L", "-o",
        "pid,tid,ppid,stat,pcpu,pmem,comm,wchan:32",
    ]))
    save("kernel.txt", capture(["journalctl", "-b", "-k", "--no-pager", "-n", "100"]))
    matches = capture(["pgrep", "-u", str(uid), "-x", "quickshell|qs|niri"])
    pids = [line for line in matches.splitlines() if line.isdigit()]
    if not pids:
        save("status.txt", "No Quickshell or Niri process found for this user.\n")

    for pid in pids[:8]:
        print(f"Capturing threads for process {pid}…", flush=True)
        save(f"threads-{pid}.txt", capture([
            "gdb", "--nx", "--batch", "--quiet",
            "-ex", "set pagination off",
            "-ex", "set debuginfod enabled off",
            "-ex", "set print frame-arguments none",
            "-ex", f"attach {pid}",
            "-ex", "thread apply all bt 40",
            "-ex", "detach",
        ]))

    print(f"Saved diagnostic files to {directory}")
    print("The shell and compositor were not restarted. Return to the conversation after capture.")


if __name__ == "__main__":
    main()
