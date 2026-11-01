"""Exercise the real Settings window lifecycle without touching desktop state."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell required")
class SettingsWindowTest(unittest.TestCase):
    def test_open_close_reopen_and_workspace_placement(self):
        with tempfile.TemporaryDirectory(prefix="settings-window-test-") as directory:
            root = Path(directory)

            def write(path, content):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content)

            target = root / "modules/widgets/config/SettingsWindow.qml"
            target.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / "modules/widgets/config/SettingsWindow.qml", target)
            write("modules/components/StyledRect.qml",
                  'import QtQuick\nRectangle { property string variant; color: "#222222" }')
            write("modules/widgets/dashboard/controls/SettingsTab.qml", "import QtQuick\nItem {}")
            write("modules/globals/GlobalStates.qml", '''pragma Singleton
import QtQuick
QtObject {
    property bool settingsWindowVisible: false
    property string settingsTargetScreenName: ""
    property int settingsTargetWorkspaceId: 2
}
''')
            write("modules/services/NiriService.qml", '''pragma Singleton
import QtQuick
QtObject {
    property var focusedMonitor: null
    property var focusedWorkspace: ({id: 2})
    property var clients: ({values: []})
    property int moved: 0
    property int focused: 0
    function moveWindowToWorkspace(id, workspace, focus) { moved = workspace; }
    function focusWindow(id) { focused = id; }
}
''')
            write("modules/theme/Styling.qml", 'pragma Singleton\nimport QtQuick\nQtObject { function radius(offset) { return 16 + offset; } }')
            write("config/Placeholder.qml", "import QtQuick\nQtObject {}")
            write("shell.qml", '''import QtQuick
import QtTest
import Quickshell
import qs.modules.widgets.config
import qs.modules.globals
import qs.modules.services
ShellRoot {
    SettingsWindow { id: settings }
    TestCase {
        id: test
        when: false
        function exercise() {
            compare(settings.visible, false);
            GlobalStates.settingsTargetScreenName = Quickshell.screens[0].name;
            GlobalStates.settingsWindowVisible = true;
            tryCompare(settings, "visible", true);
            wait(100);
            compare(GlobalStates.settingsWindowVisible, true);
            NiriService.clients = {values: [{id: 42, title: settings.title, workspace: {id: 1}}]};
            verify(settings.placeOnTargetWorkspace());
            compare(NiriService.moved, 2);
            compare(NiriService.focused, 42);
            // A compositor/user close must clear state and allow reopening.
            settings.visible = false;
            tryCompare(GlobalStates, "settingsWindowVisible", false);
            GlobalStates.settingsWindowVisible = true;
            tryCompare(settings, "visible", true);
            wait(100);
            compare(GlobalStates.settingsWindowVisible, true);
            GlobalStates.settingsWindowVisible = false;
            tryCompare(settings, "visible", false);
            GlobalStates.settingsWindowVisible = true;
            tryCompare(settings, "visible", true);
            console.log("PASS settings open, close, reopen and placement");
            Qt.quit();
        }
    }
    Timer { interval: 100; running: true; onTriggered: test.exercise() }
    Timer { interval: 5000; running: true; onTriggered: Qt.exit(1) }
}
''')
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                               XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(root / "cache"))
            result = subprocess.run(["qs", "-p", str(root), "--no-color"],
                                    env=environment, capture_output=True, text=True, timeout=8)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("PASS settings open, close, reopen and placement", output)
            for error in ("FAIL!", "TypeError", "ReferenceError", "Binding loop"):
                self.assertNotIn(error, output)


if __name__ == "__main__":
    unittest.main()
