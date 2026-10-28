"""Exercise bar appearance controls with real QML, pointer events and file persistence.

Palette/compositor backends are stubbed so this never changes the live desktop.
"""
import unittest
from pathlib import Path
import tempfile, os, shutil, subprocess
src=Path(__file__).resolve().parents[2]

@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class BarAppearanceSettingsTest(unittest.TestCase):
 def test_controls_and_persistence(self):
  with tempfile.TemporaryDirectory(prefix='bar-settings-check-') as d:
   p=Path(d)
   shutil.copytree(src/'modules',p/'modules')
   import re
   colors=(src/'modules/theme/Colors.qml').read_text()
   names=re.search(r'availableColorNames: (\[.*?\])',colors).group(1)
   import json
   (p/'modules/theme/Colors.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {property list<string> availableColorNames: '+names+';'+''.join('property color '+n+': "'+('white' if n.startswith('over') else '#ac8866' if n.startswith('primary') else '#181818')+'";' for n in json.loads(names))+'}')
   (p/'modules/services/NiriService.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var focusedMonitor: null }')
   for name in ['config','assets','version']:
    (p/name).symlink_to(src/name,target_is_directory=(src/name).is_dir())
   conf=p/'xdg/rebos_shell/config';conf.mkdir(parents=True)
   for f in (src/'assets/presets/rebos_shell Default').glob('*.json'):shutil.copy(f,conf/f.name)
   (conf/'bar.json').write_text(json.dumps({'position':'top','style':'island','pinned':True,'use12hFormat':True}))
   (p/'shell.qml').write_text('''import QtQuick
  import QtQuick.Window
  import QtTest
  import Quickshell
  import qs.config
  import qs.modules.bar
  import qs.modules.widgets.dashboard.controls
  ShellRoot {
   Window {id: win; visible: true; width: 900; height: 1300
    ShellPanel {id: panel; anchors.fill: parent; currentSection: "bar"}
    TestCase {id: test; name: "BarAppearance"; when: false
     function test_controls() {
      tryCompare(Config, "initialLoadComplete", true, 10000);
      Config.bar.style = "island";
      wait(200);
      compare(Config.bar.islandOpacity,80);
      compare(Config.bar.islandAccent,55);
      const opacity = findChild(panel,"bar-opacity-control");
      const accent = findChild(panel,"bar-accent-control");
      verify(opacity !== null); verify(accent !== null);
      mouseClick(opacity, opacity.width * 0.5, opacity.height / 2);
      wait(150);
      verify(Math.abs(Config.bar.islandOpacity - 60) < 5, "opacity = " + Config.bar.islandOpacity);
      mouseClick(accent, accent.width * 0.3, accent.height / 2);
      wait(150);
      verify(Math.abs(Config.bar.islandAccent - 30) < 5, "accent = " + Config.bar.islandAccent);
      const savedOpacity=Config.bar.islandOpacity, savedAccent=Config.bar.islandAccent;
      const classic=findChild(panel,"bar-appearance-classic"); mouseClick(classic,classic.width/2,classic.height/2);
      compare(Config.bar.islandAppearance,"classic"); compare(BarAppearance.panelOpacity(false),1);
      verify(!findChild(panel,"bar-opacity").visible);
      wait(150); const glass=findChild(panel,"bar-appearance-glass"); mouseClick(glass,glass.width/2,glass.height/2);
      tryCompare(Config.bar,"islandAppearance","glass");
      compare(Config.bar.islandOpacity,savedOpacity); compare(Config.bar.islandAccent,savedAccent);
      Config.bar.islandOpacity=75;
      wait(50);
      verify(Math.abs(opacity.value - 0.6875) < 0.01);
      const pinned=Config.bar.pinned;
      wait(150); const reset=findChild(panel,"bar-appearance-reset"); mouseClick(reset,reset.width/2,reset.height/2);
      tryCompare(Config.bar,"islandOpacity",80); tryCompare(Config.bar,"islandAccent",55);
      compare(Config.bar.islandAppearance,"glass"); compare(Config.bar.pinned,pinned);
      wait(250);
      Config.bar.islandOpacity = 67;
      Config.bar.islandAccent = 42;
      Config.bar.islandAppearance = "classic";
      wait(250);
      console.log("BAR_SETTINGS_PASS");
      Qt.quit();
     }
    }
    Timer {interval: 1000; running: true; onTriggered: test.test_controls()}
    Timer {interval: 10000; running: true; onTriggered: Qt.exit(1)}
   }
  }''')
   runtime=p/'runtime'; runtime.mkdir(mode=0o700)
   env={**os.environ,'XDG_RUNTIME_DIR':str(runtime),'QT_QPA_PLATFORMTHEME':'','QT_QPA_PLATFORM':'offscreen','XDG_CONFIG_HOME':str(p/'xdg'),'XDG_CACHE_HOME':str(p/'cache')}
   r=subprocess.run(['qs','-p',str(p),'--no-color'],env=env,capture_output=True,text=True,timeout=15)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr)
   self.assertIn('BAR_SETTINGS_PASS',r.stdout+r.stderr)
   saved=json.loads((conf/'bar.json').read_text())
   self.assertEqual((saved['islandAppearance'],saved['islandOpacity'],saved['islandAccent']),('classic',67,42))
   self.assertTrue(saved['pinned'])
   self.assertTrue(saved['use12hFormat'])
   (p/'shell.qml').write_text("""import QtQuick
import QtTest
import Quickshell
import qs.config
import qs.modules.bar
ShellRoot {
 TestCase {
  id: test
  when: false
  function checkReload() {
   tryCompare(Config, "initialLoadComplete", true, 5000);
   compare(Config.bar.islandAppearance, "classic");
   compare(Config.bar.islandOpacity, 67);
   compare(Config.bar.islandAccent, 42);
   compare(BarAppearance.panelOpacity(false), 1);
   Config.bar.islandAppearance = "glass";
   compare(BarAppearance.panelOpacity(false), 0.67);
   console.log("BAR_RELOAD_PASS");
   Qt.quit();
  }
 }
 Timer {interval: 500; running: true; onTriggered: test.checkReload()}
 Timer {interval: 7000; running: true; onTriggered: Qt.exit(1)}
}""")
   r=subprocess.run(['qs','-p',str(p),'--no-color'],env=env,capture_output=True,text=True,timeout=10)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr)
   self.assertIn('BAR_RELOAD_PASS',r.stdout+r.stderr)

if __name__ == "__main__":
 unittest.main()
