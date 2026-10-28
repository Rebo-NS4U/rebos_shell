#!/usr/bin/python3
"""Request desktop approval and authenticate one administrator command."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reason", required=True, help="Why administrator access is needed")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("provide a command after --")
    askpass = Path(__file__).resolve().with_name("assistant_sudo_askpass.sh")
    if not askpass.is_file() or not os.access(askpass, os.X_OK):
        sys.stderr.write("The administrator password helper is unavailable.\n")
        return 1
    if not os.environ.get("WAYLAND_DISPLAY") and not os.environ.get("DISPLAY"):
        sys.stderr.write("No desktop display is available. Request execution outside the sandbox first.\n")
        return 1
    # This confirmation is required even when sudo has cached authentication.
    result = subprocess.run([
        "/usr/bin/python3", str(askpass.with_name("assistant_sudo_dialog.py")), "approve",
        "--reason", args.reason, "--command", shlex.join(command),
        "--directory", os.getcwd(),
    ], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    if result.returncode != 0:
        sys.stderr.write("Administrator command cancelled or desktop prompt unavailable. Nothing was run.\n")
        return 1
    environment = dict(os.environ, SUDO_ASKPASS=str(askpass))
    # -k ignores cached credentials for this invocation. Password stdout travels
    # only from the askpass child to sudo, never through this process or chat.
    return subprocess.run(["/usr/bin/sudo", "-A", "-k", "--", *command],
                          env=environment).returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except OSError as error:
        sys.stderr.write("Could not open the administrator prompt: " + str(error) + "\n")
        sys.exit(1)
