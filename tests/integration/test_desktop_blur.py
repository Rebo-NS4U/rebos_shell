"""Exercise real settings clicks, persistence and validated Niri output."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('desktop_blur', ROOT / 'scripts/desktop_blur.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class BlurFailureTest(unittest.TestCase):
    def test_rejected_config_preserves_last_good_file(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'blur.kdl'
            target.write_text('last good configuration')
            with patch.object(backend.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'rejected')):
                with self.assertRaisesRegex(RuntimeError, 'rejected'):
                    backend.apply('light', target)
            self.assertEqual(target.read_text(), 'last good configuration')
            self.assertEqual(list(target.parent.iterdir()), [target])
            with self.assertRaises(ValueError):
                backend.apply('invalid', target)
            self.assertEqual(target.read_text(), 'last good configuration')


@unittest.skipUnless(shutil.which('qs') and shutil.which('niri'), 'Quickshell and Niri required')
class DesktopBlurTest(unittest.TestCase):
    def test_settings_apply_and_survive_new_process(self):
        with tempfile.TemporaryDirectory(prefix='desktop-blur-test-') as temporary:
            package = Path(temporary)
            shutil.copytree(ROOT / 'modules', package / 'modules')
            for name in ('config', 'assets', 'version', 'scripts'):
                (package / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())
            colors = (ROOT / 'modules/theme/Colors.qml').read_text()
            names = json.loads(re.search(r'availableColorNames: (\[.*?\])', colors).group(1))
            (package / 'modules/theme/Colors.qml').write_text(
                'pragma Singleton\nimport QtQuick\nQtObject {property list<string> availableColorNames: '
                + json.dumps(names) + ';' + ''.join('property color ' + name + ': "'
                + ('white' if name.startswith('over') else '#252525') + '";' for name in names) + '}')
            config = package / '.config/rebos_shell/config'
            config.mkdir(parents=True)
            for source in (ROOT / 'assets/presets/rebos_shell Default').glob('*.json'):
                shutil.copy2(source, config / source.name)
            (package / 'runtime').mkdir(mode=0o700)
            (package / 'shell.qml').write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.config
import qs.modules.services
import qs.modules.widgets.dashboard.controls
ShellRoot {
 Window { visible: true; width: 800; height: 850
  BlurSettings {id: settings; width: 760}
  TestCase { id: test; when: false
   function runChecks() {
    tryCompare(Config, "initialLoadComplete", true, 5000);
    if (Quickshell.env("BLUR_VERIFY_ONLY") === "1") {
     compare(Config.performance.desktopBlur, "off");
     tryCompare(DesktopBlur, "appliedMode", "off", 5000);
     verify(findChild(settings, "desktop-blur-off").selected);
    } else {
     compare(Config.performance.desktopBlur, "medium");
     for (const mode of ["medium", "light", "shell", "off", "medium", "off"]) {
      const card = findChild(settings, "desktop-blur-" + mode); verify(card !== null);
      mouseClick(card, card.width / 2, card.height / 2);
      compare(Config.performance.desktopBlur, mode);
      tryCompare(DesktopBlur, "appliedMode", mode, 5000);
      compare(DesktopBlur.error, ""); verify(card.selected);
      for (const other of ["medium", "light", "shell", "off"])
       compare(findChild(settings, "desktop-blur-" + other).selected, other === mode);
     }
     // Last selection wins even when changed before an earlier apply completes.
     Config.performance.desktopBlur = "light";
     wait(130);
     Config.performance.desktopBlur = "medium";
     Config.performance.desktopBlur = "off";
     tryCompare(DesktopBlur, "busy", false, 5000);
     tryCompare(DesktopBlur, "appliedMode", "off", 5000);
     wait(400);
    }
    console.log("DESKTOP_BLUR_PASS"); Qt.quit();
   }
  }
  Timer {interval: 500; running: true; onTriggered: {
   try {test.runChecks();} catch(error) {console.error(error); Qt.exit(1);}
  }}
  Timer {interval: 20000; running: true; onTriggered: Qt.exit(1)}
 }
}''')
            environment = dict(os.environ, HOME=str(package), XDG_CONFIG_HOME=str(package / '.config'),
                               XDG_CACHE_HOME=str(package / '.cache'), XDG_RUNTIME_DIR=str(package / 'runtime'),
                               QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            for verify in ('0', '1'):
                result = subprocess.run(['qs', '-p', str(package), '--no-color'],
                                        env=dict(environment, BLUR_VERIFY_ONLY=verify), capture_output=True, text=True, timeout=25)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertIn('DESKTOP_BLUR_PASS', output)
                self.assertNotIn('FAIL!', output)
                self.assertNotIn('TypeError', output)
                self.assertEqual(json.loads((config / 'performance.json').read_text())['desktopBlur'], 'off')
                self.assertEqual((package / '.cache/rebos_shell/niri-blur.kdl').read_text(), backend.render('off'))


if __name__ == '__main__':
    unittest.main()
