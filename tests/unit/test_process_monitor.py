"""Process counter deltas, tricky stat names, PID reuse, and selection outcomes."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess
import sys
import signal

PATH = Path(__file__).resolve().parents[2] / 'scripts/process_monitor.py'
SPEC = importlib.util.spec_from_file_location('process_monitor', PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProcessMonitorTest(unittest.TestCase):
    def test_proc_parsing_deltas_and_pid_reuse(self):
        with tempfile.TemporaryDirectory() as temp:
            proc = Path(temp)
            base = proc / '123'
            base.mkdir()
            (base/'fd').mkdir()
            (base/'fdinfo').mkdir()
            (base/'fd'/'4').symlink_to('/dev/dri/renderD128')
            (base/'fd'/'5').symlink_to('/dev/dri/renderD128')
            (base/'fd'/'6').symlink_to('socket:[42]')
            def write(ticks, start, io_bytes, gpu_ns):
                values=['0']*22
                values[0]='S'; values[1]='99'; values[11]=str(ticks)
                values[19]=str(start); values[21]='20'
                (base/'stat').write_text('123 (name with ) parens) '+' '.join(values))
                (base/'io').write_text(f'read_bytes: {io_bytes}\nwrite_bytes: 0\n')
                for fd in ('4','5'):
                    (base/'fdinfo'/fd).write_text(f'drm-client-id: 8\ndrm-pdev: 0000:01:00.0\ndrm-engine-render: {gpu_ns} ns\n')
            m=MODULE.ProcessMonitor(proc)
            write(100,1000,1000,1000000000)
            with patch.object(MODULE.time,'monotonic',return_value=1): first=m.sample()[0]
            self.assertEqual(first['cpu'],0)
            self.assertEqual(first['name'],'name with ) parens')
            self.assertEqual(first['ppid'],99)
            self.assertEqual(first['sockets'],1)
            write(100+m.ticks,1000,3048,1500000000)
            with patch.object(MODULE.time,'monotonic',return_value=2): row=m.sample()[0]
            self.assertEqual(row['cpu'],100)
            self.assertEqual(row['disk'],2048)
            self.assertEqual(row['gpu']['0000:01:00.0'],50)  # duplicated fd must not double-count
            write(9000,2000,40000,9000000000)
            with patch.object(MODULE.time,'monotonic',return_value=3): reused=m.sample()[0]
            self.assertEqual(reused['cpu'],0)
            self.assertEqual(reused['disk'],0)
            self.assertEqual(reused['gpu']['0000:01:00.0'],0)
            (base/'io').unlink()
            with patch.object(MODULE.time,'monotonic',return_value=4): restricted=m.sample()[0]
            self.assertFalse(restricted['io_available'])
            self.assertEqual(restricted['disk'],0)

    def test_window_selection_results(self):
        window={'id':1,'pid':os.getpid(),'title':'Example','app_id':'test'}
        with patch.object(MODULE.subprocess,'run',return_value=subprocess.CompletedProcess([],0,json.dumps(window),'')):
            result=MODULE.pick_window()
        self.assertEqual(result['window'],window)
        self.assertEqual(result['process']['ppid'],os.getppid())
        self.assertTrue(result['process']['exe'])
        for output in ('null','bad json'):
            with patch.object(MODULE.subprocess,'run',return_value=subprocess.CompletedProcess([],0,output,'')):
                self.assertIn('error',MODULE.pick_window())
        with patch.object(MODULE.subprocess,'run',side_effect=subprocess.TimeoutExpired('niri',120)):
            self.assertIn('error',MODULE.pick_window())

    def test_window_actions_target_disposable_processes(self):
        # Signals are delivered only to children created by this test.
        for action, expected in [('terminate', signal.SIGTERM), ('kill', signal.SIGKILL)]:
            child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
            try:
                start = MODULE.ProcessMonitor().snapshot(child.pid)['start']
                listed = subprocess.CompletedProcess([], 0, json.dumps([{'id': 77, 'pid': child.pid}]), '')
                with patch.object(MODULE.subprocess, 'run', return_value=listed):
                    stale = MODULE.window_action(action, 77, child.pid, start + 1)
                    self.assertIn('error', stale)
                    self.assertIsNone(child.poll())
                    wrong = MODULE.window_action(action, 88, child.pid, start)
                    self.assertIn('error', wrong)
                    self.assertIsNone(child.poll())
                    result = MODULE.window_action(action, 77, child.pid, start)
                self.assertIn('message', result, result)
                self.assertEqual(child.wait(timeout=3), -expected)
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()

    def test_close_uses_selected_window_id(self):
        listed = subprocess.CompletedProcess([], 0, '[{"id":77,"pid":123}]', '')
        closed = subprocess.CompletedProcess([], 0, '', '')
        with patch.object(MODULE.subprocess, 'run', side_effect=[listed, closed]) as run:
            result = MODULE.window_action('close', 77, 123, '')
        self.assertIn('message', result)
        self.assertEqual(run.call_args.args[0], ['niri', 'msg', 'action', 'close-window', '--id', '77'])
        with patch.object(MODULE.subprocess, 'run', return_value=listed), patch.object(MODULE.os, 'pidfd_open', side_effect=PermissionError):
            self.assertIn('permission', MODULE.window_action('kill', 77, 123, 99)['error'])

if __name__=='__main__':
    unittest.main()
