#!/usr/bin/python3
"""Request desktop approval and authenticate one administrator command."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess
import sys


def desktop_environment():
    """Recover login-session display settings without relaxing OS permissions."""
    environment = dict(os.environ)
    runtime = Path("/run/user") / str(os.getuid())
    if not environment.get("XDG_RUNTIME_DIR") and runtime.is_dir():
        environment["XDG_RUNTIME_DIR"] = str(runtime)
    try:
        result = subprocess.run(
            ["/usr/bin/systemctl", "--user", "show-environment"],
            env=environment, stdin=subprocess.DEVNULL, capture_output=True,
            text=True, timeout=3,
        )
        if result.returncode == 0:
            allowed = {"DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY",
                       "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"}
            for line in result.stdout.splitlines():
                key, separator, value = line.partition("=")
                if separator and key in allowed and value:
                    environment[key] = value
    except (OSError, subprocess.TimeoutExpired):
        pass  # A denied user bus is not permission to escape a sandbox.
    return environment


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
    environment = desktop_environment()
    if not environment.get("WAYLAND_DISPLAY") and not environment.get("DISPLAY"):
        sys.stderr.write("No desktop display is available. Request the execution tool's supported "
                         "approval to run this helper outside the sandbox. If unavailable or "
                         "rejected, provide the exact command for the user to run.\n")
        return 1
    # This confirmation is required even when sudo has cached authentication.
    result = subprocess.run([
        "/usr/bin/python3", str(askpass.with_name("assistant_sudo_dialog.py")), "approve",
        "--reason", args.reason, "--command", shlex.join(command),
        "--directory", os.getcwd(),
    ], env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    if result.returncode != 0:
        if result.returncode == 2:
            sys.stderr.write("Desktop access is unavailable. Request the execution tool's supported "
                             "approval to run this helper outside the sandbox. If unavailable or "
                             "rejected, provide the exact command for the user to run. Nothing was run.\n")
        else:
            sys.stderr.write("Administrator command cancelled or desktop prompt unavailable. Nothing was run.\n")
        return 1
    environment["SUDO_ASKPASS"] = str(askpass)
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
