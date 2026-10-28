"""Exercise reload dispatch, changed-file detection, and real process replacement."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import reload_theme_apps as reload


class ThemeReloadTest(unittest.TestCase):
    def test_only_changed_running_apps_reload(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            spotify = home / '.config/spicetify/Themes/rebos_shell/color.ini'
            spotify.parent.mkdir(parents=True)
            spotify.write_text('first')
            btop = home / '.config/btop/themes/rebos_shell.theme'
            btop.parent.mkdir(parents=True)
            btop.write_text('first')
            apps = [(101, 'spotify', Path('/opt/spotify/spotify'), ['spotify']),
                    (102, 'btop', Path('/usr/bin/btop'), ['btop'])]
            with patch.object(reload, 'processes', return_value=apps), \
                 patch.object(reload, 'restart', return_value=True) as restart, \
                 patch.object(os, 'pidfd_open', return_value=42), \
                 patch.object(signal, 'pidfd_send_signal') as send, \
                 patch.object(os, 'close'):
                self.assertTrue(reload.refresh(home))
                restart.assert_not_called()
                send.assert_not_called()
                spotify.write_text('second')
                btop.write_text('second')
                self.assertTrue(reload.refresh(home))
                restart.assert_called_once_with(101, Path('/opt/spotify/spotify'), ['spotify'], browser=False)
                send.assert_called_once_with(42, signal.SIGUSR2)
                reload.refresh(home)
                self.assertEqual(restart.call_count, 1)
                # Failure retains the old fingerprint, allowing a later retry.
                spotify.write_text('third')
                restart.return_value = False
                self.assertFalse(reload.refresh(home))
                restart.return_value = True
                self.assertTrue(reload.refresh(home))
                self.assertEqual(restart.call_count, 3)
                status = json.loads((home / '.cache/rebos_shell/app-theme-reload-status.json').read_text())
                self.assertEqual(status['failed'], [])

    def test_closed_apps_stay_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with patch.object(reload, 'processes', return_value=[]), \
                 patch.object(reload, 'restart') as restart:
                reload.refresh(home)
                theme = home / '.config/spicetify/Themes/rebos_shell/user.css'
                theme.parent.mkdir(parents=True)
                theme.write_text('new colors')
                self.assertTrue(reload.refresh(home))
                restart.assert_not_called()

    def test_restart_waits_for_exit_and_restores_browser_session(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / 'restarted'
            # Start a real disposable app, then replace it with the same argv.
            # The replacement records the browser restoration argument.
            program = ("import sys,time; from pathlib import Path; "
                       "Path(sys.argv[1]).write_text(' '.join(sys.argv[2:])); time.sleep(30)")
            process = subprocess.Popen([sys.executable, '-c', program, str(marker)])
            spawned = []
            real_popen = subprocess.Popen

            def spawn(*args, **kwargs):
                child = real_popen(*args, **kwargs)
                spawned.append(child)
                return child

            try:
                with patch.object(reload.subprocess, 'Popen', side_effect=spawn) as launch:
                    self.assertTrue(reload.restart(process.pid, Path(sys.executable),
                                                   [sys.executable, '-c', program, str(marker)], browser=True))
                    self.assertEqual(launch.call_args.args[0][-1], '--restore-last-session')
                    self.assertEqual(len(spawned), 1)
            finally:
                process.wait(timeout=5)
                for child in spawned:
                    child.terminate()
                    child.wait(timeout=5)



if __name__ == '__main__':
    unittest.main()
