"""Exercise actual QML transitions, pointer input, launcher reversal and persistence.

Hardware services and palette generation are isolated from the live desktop.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class ShellMotionTest(unittest.TestCase):
    def test_transitions_controls_and_persistence(self):
        with tempfile.TemporaryDirectory(prefix="shell-motion-") as directory:
            package = Path(directory)
            shutil.copytree(ROOT / "modules", package / "modules")
            for name in ("config", "assets", "version"):
                (package / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())

            def write(name, value):
                (package / name).write_text(value)

            colors = (ROOT / "modules/theme/Colors.qml").read_text()
            names = json.loads(re.search(r"availableColorNames: (\[.*?\])", colors).group(1))
            write("modules/theme/Colors.qml", "pragma Singleton\nimport QtQuick\nQtObject {property list<string> availableColorNames: " + json.dumps(names) + ";" + "".join("property color " + name + ': "' + ("white" if name.startswith("over") else "#252525") + '";' for name in names) + "}")
            write("modules/services/NiriService.qml", 'pragma Singleton\nimport QtQuick\nQtObject {property var focusedMonitor: null}')
            write("modules/services/Visibilities.qml", '''pragma Singleton
import QtQuick
QtObject {
 id: root
 property QtObject state: QtObject {property bool launcher: false}
 function getForScreen(name) {return state;}
 function getBarPanelForScreen(name) {return null;}
}''')
            write("modules/globals/GlobalStates.qml", '''pragma Singleton
import QtQuick
QtObject {
 property var wallpaperManager: null
 property int appResets: 0
 property int projectResets: 0
 function clearLauncherState() {appResets++;}
 function clearProjectPickerState() {projectResets++;}
}''')
            write("modules/widgets/launcher/LauncherView.qml", 'import QtQuick\nItem {implicitWidth: 300; implicitHeight: 200}')
            config = package / "xdg/rebos_shell/config"
            config.mkdir(parents=True)
            for source in (ROOT / "assets/presets/rebos_shell Default").glob("*.json"):
                shutil.copy(source, config / source.name)
            runtime = package / "runtime"
            runtime.mkdir(mode=0o700)
            environment = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QPA_PLATFORMTHEME="", XDG_CONFIG_HOME=str(package / "xdg"), XDG_CACHE_HOME=str(package / "cache"))
            write("shell.qml", '''import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtTest
import Quickshell
import qs.config
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.modules.widgets.launcher
import qs.modules.widgets.dashboard.controls
ShellRoot {
 Window {visible: true; width: 800; height: 700
  MotionSettings {id: settings; width: 700}
  MotionReveal {id: reveal; x: 30; y: 300; width: 160; height: 60
   MouseArea {id: target; anchors.fill: parent; property int clicks: 0; onClicked: clicks++}
  }
  RunMenuHost {id: launcher; anchors.fill: parent; screen: Quickshell.screens[0]}
  TestCase {id: test; when: false
   function test_motion() {
    tryCompare(Config, "initialLoadComplete", true, 5000);
    Config.bar.style = "default";
    Config.theme.animDuration = 300;
    compare(Motion.enter, 255); compare(Motion.exit, 180);
    reveal.open = true;
    tryVerify(() => reveal.progress > 0 && reveal.progress < 1, 150);
    verify(reveal.visible); verify(reveal.enabled);
    const starting = reveal.progress;
    reveal.open = false;
    verify(reveal.progress >= starting - 0.05, "Reversing should preserve the painted position");
    verify(!reveal.enabled); verify(reveal.visible);
    mouseClick(target, 20, 20); compare(target.clicks, 0);
    wait(35); reveal.open = true;
    tryCompare(reveal, "progress", 1, 600);
    mouseClick(target, 20, 20); compare(target.clicks, 1);
    reveal.open = false;
    tryCompare(reveal, "visible", false, 500);

    // The same reveal drives the real launcher host, including bottom placement.
    const card = findChild(launcher, "launcher-motion"); verify(card !== null);
    for (const edge of ["top", "bottom"]) {
     Config.bar.position = edge;
     Visibilities.state.launcher = true;
     tryCompare(card, "progress", 1, 600);
     compare(card.direction, edge === "bottom" ? 1 : -1);
     verify(launcher.hitbox !== null);
     Visibilities.state.launcher = false;
     compare(launcher.hitbox, null); verify(card.visible); verify(!card.enabled);
     wait(35); Visibilities.state.launcher = true;
     tryCompare(card, "progress", 1, 600);
     Visibilities.state.launcher = false;
     tryCompare(card, "visible", false, 500);
    }
    compare(GlobalStates.appResets, 4); compare(GlobalStates.projectResets, 4);

    // Changing settings must not replay startup animations or lose persistence.
    const quick = findChild(settings, "motion-quick");
    mouseClick(quick, quick.width / 2, quick.height / 2);
    compare(Config.theme.animDuration, 180); compare(Motion.enter, 153);
    const slider = findChild(settings, "motion-duration");
    slider.value = 0.23;
    compare(Config.theme.animDuration, 230);
    const off = findChild(settings, "motion-off");
    mouseClick(off, off.width / 2, off.height / 2);
    compare(Config.theme.animDuration, 0);
    for (const value of [Motion.enter, Motion.exit, Motion.resize, Motion.feedback, Motion.press, Motion.contentIn, Motion.contentOut]) compare(value, 0);
    reveal.open = true; compare(reveal.progress, 1);
    reveal.open = false; compare(reveal.progress, 0); verify(!reveal.visible);
    Visibilities.state.launcher = true; compare(card.progress, 1);
    Visibilities.state.launcher = false; compare(card.progress, 0);

    Config.theme.animDuration = 300;
    reveal.open = true;
    tryVerify(() => reveal.progress > 0 && reveal.progress < 1, 150);
    Config.theme.animDuration = 0;
    tryCompare(reveal, "progress", 1, 80);
    reveal.open = false; compare(reveal.progress, 0);
    wait(200);
    console.log("SHELL_MOTION_PASS"); Qt.quit();
   }
  }
  Timer {interval: 700; running: true; onTriggered: {try {test.test_motion();} catch(error) {console.error("Motion check failed", error); Qt.exit(1);}}}
  Timer {interval: 15000; running: true; onTriggered: Qt.exit(1)}
 }
}''')

            def run(marker):
                result = subprocess.run(["qs", "-p", str(package), "--no-color"], env=environment, capture_output=True, text=True, timeout=20)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertIn(marker, output)
                for failure in ("FAIL!", "TypeError:", "ReferenceError:", "Failed to load configuration", "Binding loop"):
                    self.assertNotIn(failure, output)

            run("SHELL_MOTION_PASS")
            self.assertEqual(json.loads((config / "theme.json").read_text())["animDuration"], 0)
            write("shell.qml", '''import QtQuick
import QtTest
import Quickshell
import qs.config
import qs.modules.theme
ShellRoot {
 TestCase {id: test; when: false
  function test_reload() {
   tryCompare(Config, "initialLoadComplete", true, 5000);
   compare(Config.theme.animDuration, 0); compare(Motion.enabled, false);
   console.log("SHELL_MOTION_RELOAD_PASS"); Qt.quit();
  }
 }
 Timer {interval: 500; running: true; onTriggered: test.test_reload()}
 Timer {interval: 8000; running: true; onTriggered: Qt.exit(1)}
}''')
            run("SHELL_MOTION_RELOAD_PASS")


if __name__ == "__main__":
    unittest.main()
