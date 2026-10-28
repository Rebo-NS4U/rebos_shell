#!/usr/bin/env python3
"""Unprivileged process samples. No command lines or environments are collected."""
import json
import signal
import os
from pathlib import Path
import subprocess
import sys
import time


class ProcessMonitor:
    def __init__(self, proc=Path('/proc')):
        self.proc = proc
        self.previous = {}
        self.timestamp = None
        self.ticks = os.sysconf('SC_CLK_TCK')
        self.page_size = os.sysconf('SC_PAGE_SIZE')

    def snapshot(self, pid):
        base = self.proc / str(pid)
        stat = (base / 'stat').read_text()
        end = stat.rfind(')')
        fields = stat[end + 2:].split()
        row = dict(pid=int(pid), ppid=int(fields[1]), name=stat[stat.find('(') + 1:end],
                   start=int(fields[19]), ticks=int(fields[11]) + int(fields[12]),
                   ram=max(0, int(fields[21])) * self.page_size,
                   read=0, write=0, io_available=False, sockets=0, gpu={})
        try:
            values = dict(line.split(':', 1) for line in (base / 'io').read_text().splitlines())
            row.update(read=int(values['read_bytes']), write=int(values['write_bytes']), io_available=True)
        except (OSError, ValueError, KeyError):
            pass
        clients = set()
        try:
            for fd in (base / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                    if target.startswith('socket:'):
                        row['sockets'] += 1
                    if not target.startswith('/dev/dri/'):
                        continue
                    info = (base / 'fdinfo' / fd.name).read_text()
                    values = dict(line.split(':', 1) for line in info.splitlines() if ':' in line)
                    device = values.get('drm-pdev', '').strip()
                    client = (device, values.get('drm-client-id', fd.name).strip())
                    if not device or client in clients:
                        continue
                    clients.add(client)
                    counters = [int(v.strip().split()[0]) for k, v in values.items()
                                if k.startswith('drm-engine-') and v.strip().endswith(' ns')]
                    if not counters:
                        continue
                    engines = sum(counters)
                    row['gpu'][device] = row['gpu'].get(device, 0) + engines
                except (OSError, ValueError):
                    continue
        except OSError:
            pass
        return row

    def sample(self):
        now = time.monotonic()
        elapsed = now - self.timestamp if self.timestamp is not None else None
        current = {}
        rows = []
        for base in self.proc.iterdir():
            if not base.name.isdigit():
                continue
            try:
                row = self.snapshot(base.name)
            except (OSError, ValueError, IndexError):
                continue
            current[row['pid']] = row
            old = self.previous.get(row['pid'])
            valid = elapsed and old and old['start'] == row['start']
            result = {key: row[key] for key in ('pid', 'ppid', 'name', 'ram', 'sockets', 'io_available')}
            result['cpu'] = max(0, (row['ticks'] - old['ticks']) / self.ticks / elapsed * 100) if valid else 0
            result['disk'] = max(0, row['read'] + row['write'] - old['read'] - old['write']) / elapsed if valid and old['io_available'] and row['io_available'] else 0
            result['gpu'] = {dev: max(0, ns - old['gpu'].get(dev, ns)) / (elapsed * 1e9) * 100 if valid else 0
                             for dev, ns in row['gpu'].items()}
            rows.append(result)
        self.previous, self.timestamp = current, now
        return rows


def pick_window():
    try:
        picked = subprocess.run(['niri', 'msg', '-j', 'pick-window'], capture_output=True, text=True, timeout=120)
        if picked.returncode:
            return {'error': 'Window selection cancelled or unavailable.'}
        window = json.loads(picked.stdout)
        if not window:
            return {'error': 'Window selection cancelled.'}
        result = {'window': window}
        pid = window.get('pid')
        if pid:
            try:
                monitor = ProcessMonitor()
                row = monitor.snapshot(pid)
                result['process'] = {key: row[key] for key in ('pid', 'ppid', 'name', 'ram', 'start')}
                result['process']['exe'] = os.readlink(f'/proc/{pid}/exe')
            except (OSError, ValueError, IndexError):
                result['process_note'] = 'Process exited or its details are unavailable.'
        return result
    except subprocess.TimeoutExpired:
        return {'error': 'Window selection timed out.'}
    except (OSError, ValueError, TypeError):
        return {'error': 'Could not read window information.'}


def window_action(action, window_id, pid, start):
    """Act only on the selected window and the same process incarnation."""
    if action not in ('close', 'terminate', 'kill'):
        return {'error': 'Unknown window action.'}
    try:
        window_id, pid = int(window_id), int(pid)
        listed = subprocess.run(['niri', 'msg', '-j', 'windows'], capture_output=True, text=True, timeout=5, check=True)
        window = next((w for w in json.loads(listed.stdout) if w['id'] == window_id), None)
        if window is None or (window.get('pid') or 0) != pid:
            return {'error': 'That window has closed or changed. Pick a window again.'}
        if action == 'close':
            subprocess.run(['niri', 'msg', 'action', 'close-window', '--id', str(window_id)],
                           capture_output=True, text=True, timeout=5, check=True)
            return {'message': 'Close requested.'}
        if pid <= 1 or not start:
            return {'error': 'Process information is unavailable. Pick the window again.'}
        # Open a stable process handle before checking identity, so PID reuse
        # cannot redirect a signal after verification.
        fd = os.pidfd_open(pid)
        try:
            if ProcessMonitor().snapshot(pid)['start'] != int(start):
                return {'error': 'The process has changed. Pick the window again.'}
            signal.pidfd_send_signal(fd, signal.SIGTERM if action == 'terminate' else signal.SIGKILL)
        finally:
            os.close(fd)
        return {'message': 'Termination requested.' if action == 'terminate' else 'Force kill sent.',
                'killed': action == 'kill'}
    except ProcessLookupError:
        return {'error': 'The process has already exited.'}
    except PermissionError:
        return {'error': 'You do not have permission to control this process.'}
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return {'error': 'Could not control this window. Pick it again and retry.'}


if __name__ == '__main__':
    if len(sys.argv) == 6 and sys.argv[1] == '--window-action':
        print(json.dumps(window_action(*sys.argv[2:])), flush=True)
    elif '--pick-window' in sys.argv:
        print(json.dumps(pick_window()), flush=True)
    else:
        monitor = ProcessMonitor()
        try:
            while True:
                print(json.dumps(monitor.sample()), flush=True)
                time.sleep(1)
        except (BrokenPipeError, KeyboardInterrupt):
            pass
