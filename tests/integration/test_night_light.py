"""Exercise Night Light through real QML processes and a synthetic busctl."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which('qs'), 'Quickshell required')
class NightLightTest(unittest.TestCase):
    def run_scenario(self, saved_active, scenario):
        with tempfile.TemporaryDirectory(prefix='night-light-test-') as temporary:
            base = Path(temporary)
            package = base / 'qml'
            service_dir = package / 'modules/services'
            service_dir.mkdir(parents=True)
            shutil.copyfile(ROOT / 'modules/services/NightLightService.qml', service_dir / 'NightLightService.qml')
            (service_dir / 'StateService.qml').write_text('''pragma Singleton
import Quickshell
Singleton {
    signal stateLoaded()
    property bool initialized: true
    property var state: ({nightLight: %s, nightLightTemperature: 3800})
    function get(key, fallback) { return state[key] === undefined ? fallback : state[key]; }
    function set(key, value) { state[key] = value; }
}
''' % ('true' if saved_active else 'false'))
            binaries = base / 'bin'
            binaries.mkdir()
            fake = binaries / 'busctl'
            fake.write_text('''#!/usr/bin/python3
import os, sys, time
from pathlib import Path
state = Path(os.environ['NIGHT_LIGHT_TEST_STATE'])
if 'set-property' in sys.argv:
    time.sleep(0.05)
    value = sys.argv[-1]
    if value == '2600':
        print('Synthetic temperature write failure', file=sys.stderr)
        sys.exit(3)
    state.write_text(value)
else:
    print('q ' + (state.read_text() if state.exists() else '6500'))
''')
            fake.chmod(0o755)
            (package / 'shell.qml').write_text('''import QtQuick
import Quickshell
import qs.modules.services
ShellRoot {
    id: test
    property int stage: 0
    function check(value, message) {
        if (!value) { console.error('FAIL', message); Qt.exit(1); }
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error('FAIL timeout', test.stage, NightLightService.lastError); Qt.exit(1); } }
    Timer { interval: 15; running: true; repeat: true; onTriggered: {
        SCENARIO
    } }
}
'''.replace('SCENARIO', scenario))
            runtime = base / 'runtime'
            runtime.mkdir(mode=0o700)
            environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                               XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(base / 'cache'),
                               PATH=str(binaries) + os.pathsep + os.environ['PATH'],
                               NIGHT_LIGHT_TEST_STATE=str(base / 'temperature'))
            result = subprocess.run(['qs', '-p', str(package), '--no-color'], env=environment,
                                    capture_output=True, text=True, timeout=8)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-4000:])
            self.assertIn('PASS', output, output)
            for error in ('FAIL', 'TypeError', 'ReferenceError'):
                self.assertNotIn(error, output, output)

    def test_restore_enabled_temperature(self):
        self.run_scenario(True, '''
        if (NightLightService.available && NightLightService.currentTemperature === 3800) {
            check(NightLightService.active, 'saved enabled state applied to backend');
            console.log('PASS restore'); Qt.quit();
        }
''')

    def test_toggle_latest_temperature_and_failed_write(self):
        self.run_scenario(False, '''
        if (test.stage === 0 && NightLightService.available) {
            check(!NightLightService.active && NightLightService.currentTemperature === 6500, 'starts neutral');
            NightLightService.toggle();
            check(!NightLightService.active, 'does not claim success before backend confirms');
            NightLightService.setTemperature(3700);
            NightLightService.setTemperature(3800);
            test.stage = 1;
        } else if (test.stage === 1 && NightLightService.currentTemperature === 3800) {
            check(NightLightService.active && StateService.get('nightLight', false), 'latest request applied and saved');
            NightLightService.toggle(); test.stage = 2;
        } else if (test.stage === 2 && NightLightService.currentTemperature === 6500) {
            check(!NightLightService.active && NightLightService.temperature === 3800, 'off restores neutral and retains strength');
            NightLightService.toggle(); test.stage = 3;
        } else if (test.stage === 3 && NightLightService.currentTemperature === 3800) {
            NightLightService.setTemperature(2600); test.stage = 4;
        } else if (test.stage === 4 && NightLightService.lastWriteFailed && NightLightService.available) {
            check(NightLightService.currentTemperature === 3800, 'failed write preserves confirmed temperature');
            check(NightLightService.lastError.includes('Synthetic'), 'failed write remains reported');
            NightLightService.setTemperature(4100); test.stage = 5;
        } else if (test.stage === 5 && NightLightService.currentTemperature === 4100) {
            check(NightLightService.active && !NightLightService.lastError && !NightLightService.lastWriteFailed, 'next write recovers');
            console.log('PASS toggle, latest request, failure, recovery'); Qt.quit();
        }
''')


if __name__ == '__main__':
    unittest.main()
