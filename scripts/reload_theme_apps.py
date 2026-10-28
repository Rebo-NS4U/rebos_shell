#!/usr/bin/env python3
"""Refresh running apps after all theme writers finish; never start closed apps."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from apply_desktop_palette import write
from apply_app_palette import zen_profiles


def fingerprint(paths):
    digest = hashlib.sha256()
    for path in sorted(paths):
        if path.is_file():
            digest.update(str(path).encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def processes(proc=Path('/proc')):
    """Only consider this user's top-level app processes, never renderer children."""
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != os.getuid():
                continue
            args = [os.fsdecode(arg) for arg in (entry / 'cmdline').read_bytes().split(b'\0') if arg]
            if not args or any(arg.startswith(('--type=', '-contentproc')) for arg in args):
                continue
            executable = (entry / 'exe').resolve(strict=True)
            name = executable.name.lower()
            if name in ('zen', 'zen-bin', 'spotify', 'btop'):
                yield int(entry.name), name, executable, args
        except (OSError, ValueError):
            continue


def restart(pid, executable, args, browser=False):
    # A pidfd avoids accidentally signalling a reused PID. Never force-kill an
    # app that refuses to close, and wait for it to release its profile lock.
    import select
    try:
        fd = os.pidfd_open(pid)
    except ProcessLookupError:
        return True
    try:
        signal.pidfd_send_signal(fd, signal.SIGTERM)
        poller = select.poll()
        poller.register(fd, select.POLLIN)
        if not poller.poll(10000):
            print(json.dumps({'error': executable.name + ' did not exit; restart skipped'}), file=sys.stderr)
            return False
    finally:
        os.close(fd)
    command = [str(executable), *args[1:]]
    if browser and '--restore-last-session' not in command:
        command.append('--restore-last-session')
    subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return True


def refresh(home):
    cache = home / '.cache/rebos_shell'
    state = cache / 'app-theme-reload.json'
    paths = {
        'zen': [profile / 'chrome/rebos_shell.css' for profile in zen_profiles(home)],
        'spotify': list((home / '.config/spicetify/Themes/rebos_shell').glob('*')),
        'btop': [home / '.config/btop/themes/rebos_shell.theme'],
        'qt': [home / '.config/kdeglobals', home / '.config/qt5ct/colors/rebos_shell.conf',
               home / '.config/qt6ct/colors/rebos_shell.conf'],
    }
    current = {name: fingerprint(files) for name, files in paths.items()}
    try:
        previous = json.loads(state.read_text())
    except (OSError, ValueError):
        previous = current  # First run establishes a baseline without closing apps.
    changed = {name for name in current if previous.get(name) != current[name]}
    failed = set()
    if 'qt' in changed:
        try:
            result = subprocess.run(['gdbus', 'emit', '--session', '--object-path', '/KGlobalSettings',
                                    '--signal', 'org.kde.KGlobalSettings.notifyChange', '0', '0'],
                                    capture_output=True, timeout=5)
            if result.returncode:
                failed.add('qt')
        except (OSError, subprocess.TimeoutExpired):
            failed.add('qt')
    for pid, name, executable, args in processes():
        group = 'zen' if name in ('zen', 'zen-bin') else name
        if group not in changed:
            continue
        try:
            if group == 'btop':
                # btop's documented handler reloads both configuration and theme.
                fd = os.pidfd_open(pid)
                try:
                    signal.pidfd_send_signal(fd, signal.SIGUSR2)
                finally:
                    os.close(fd)
            elif not restart(pid, executable, args, browser=group == 'zen'):
                failed.add(group)
        except ProcessLookupError:
            pass
        except OSError as error:
            failed.add(group)
            print(json.dumps({'error': group + ': ' + str(error)}), file=sys.stderr)
    for group in failed:
        current[group] = previous.get(group, '')
    write(state, json.dumps(current, indent=2) + '\n')
    write(cache / 'app-theme-reload-status.json', json.dumps({
        'updated_at': time.time(), 'changed': sorted(changed), 'failed': sorted(failed)
    }) + '\n')
    return not failed


if __name__ == '__main__':
    try:
        sys.exit(0 if refresh(Path.home()) else 1)
    except (OSError, ValueError) as error:
        print(json.dumps({'error': str(error)}), file=sys.stderr)
        sys.exit(1)
