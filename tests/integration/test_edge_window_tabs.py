"""Exercise hover navigation with real Qt pointer events."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SRC = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class EdgeWindowTabsTest(unittest.TestCase):
    def test_hover_selects_real_neighbor_without_refocusing_monitor(self):
        with tempfile.TemporaryDirectory(prefix="edge-window-targets-") as directory:
            root = Path(directory)

            def write(name, content):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
                return path

            for name in ["modules/shell/EdgeWindowTab.qml", "modules/services/NiriService.qml"]:
                write(name, (SRC / name).read_text())
            write("modules/theme/Styling.qml", '''pragma Singleton
import QtQuick
QtObject { function fontSize(n) { return 14+n; } function radius(n) { return 8; } }
''')
            write("modules/theme/Motion.qml", '''pragma Singleton
import QtQuick
QtObject { property bool enabled: true; property int enter: 255; property int exit: 180 }
''')
            write("modules/theme/Colors.qml", '''pragma Singleton
import QtQuick
QtObject { property color primary: "cyan"; property color overBackground: "white" }
''')
            write("modules/components/StyledRect.qml", "import QtQuick\nRectangle { property string variant }")
            write("modules/components/StyledText.qml", "import QtQuick\nText {}")
            fake = write("bin/niri", '''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:3] == ["msg", "action"]:
    with open(os.environ["EDGE_ACTION_LOG"], "a") as log:
        log.write(json.dumps(sys.argv[3:]) + "\\n")
elif sys.argv[-1] == "overview-state":
    print('{"is_open": false}')
elif sys.argv[-1] == "outputs":
    print('{}')
''')
            fake.chmod(0o755)
            write("shell.qml", '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.modules.shell
import qs.modules.services
ShellRoot {
    Window {
        id: win; visible: true; width: 320; height: 240
        EdgeWindowTab {
            id: left; x: 2; y: 80; leftSide: true
            visible: NiriService.adjacentColumnWindowId("DP-1", true) >= 0
            onActivated: NiriService.focusAdjacentColumn("DP-1", true)
        }
        EdgeWindowTab {
            id: right; x: 298; y: 80
            visible: NiriService.adjacentColumnWindowId("DP-1", false) >= 0
            onActivated: NiriService.focusAdjacentColumn("DP-1", false)
        }
        TestCase {
            id: test; name: "EdgeWindowTargets"; when: false
            function window(id, workspace, column, row, recent, floating) {
                return {id: id, workspace_id: workspace, is_floating: !!floating,
                    is_focused: false, focus_timestamp: {secs: recent || 0, nanos: 0},
                    layout: {pos_in_scrolling_layout: [column, row]}};
            }
            function test_navigation() {
                NiriService.rawWorkspaces = [
                    {id: 1, idx: 1, output: "DP-1", is_active: true, active_window_id: 11},
                    {id: 2, idx: 2, output: "DP-1", is_active: false, active_window_id: 21},
                    {id: 3, idx: 3, output: "HDMI-A-1", is_active: true, active_window_id: 31}];
                NiriService.rawWindows = [window(10,1,1,1), window(11,1,2,1),
                    window(12,1,3,1,1), window(13,1,3,2,5), window(14,1,3,1,9,true),
                    window(21,2,3,1), window(31,3,1,1), window(32,3,2,1)];
                NiriService.rebuildState(); wait(20);
                compare(NiriService.focusedClient, null); // A layer can own keyboard focus.
                compare(NiriService.adjacentColumnWindowId("DP-1", true), 10);
                compare(NiriService.adjacentColumnWindowId("DP-1", false), 13);
                verify(left.visible && right.visible);
                mouseMove(right, 8, 25); wait(350);
                NiriService.handleEvent({WorkspaceActiveWindowChanged: {workspace_id: 1, active_window_id: 13}});
                wait(20); verify(!right.visible); verify(left.visible);
                mouseMove(left, 8, 25); wait(350);
                NiriService.handleEvent({WorkspaceActiveWindowChanged: {workspace_id: 1, active_window_id: 10}});
                wait(20); verify(!left.visible); verify(right.visible);
                NiriService.focusAdjacentColumn("DP-1", true); // Boundary: no command.
                NiriService.focusAdjacentColumn("HDMI-A-1", false); wait(200);
                NiriService.rawWindows = [window(10,1,1,1), window(21,2,3,1)];
                NiriService.rebuildState(); wait(20);
                verify(!left.visible && !right.visible); // Never crosses desktops.
                compare(NiriService.adjacentColumnWindowId("missing", false), -1);
                console.log("PASS actual hover-to-window commands, boundaries, layer focus, outputs and desktops");
                Qt.quit();
            }
        }
    }
    Timer { interval: 200; running: true; onTriggered: test.test_navigation() }
    Timer { interval: 5000; running: true; onTriggered: Qt.exit(1) }
}
''')
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            log = root / "actions.jsonl"
            result = subprocess.run(
                ["qs", "-p", str(root), "--no-color"],
                env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                         XDG_RUNTIME_DIR=str(runtime), PATH=str(root / "bin") + os.pathsep + os.environ["PATH"],
                         EDGE_ACTION_LOG=str(log)),
                capture_output=True, text=True, timeout=8,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("QtQuickTest::fail", output)
            self.assertIn("PASS actual hover-to-window commands", output)
            import json
            self.assertEqual([json.loads(line) for line in log.read_text().splitlines()], [
                ["focus-window", "--id", "13"], ["focus-window", "--id", "11"],
                ["focus-window", "--id", "32"],
            ])

    def test_hover_once_per_entry_and_cancellation(self):
        with tempfile.TemporaryDirectory(prefix="edge-window-tabs-") as directory:
            root = Path(directory)

            def write(name, content):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)

            source = "modules/shell/EdgeWindowTab.qml"
            write(source, (SRC / source).read_text())
            write("modules/theme/Styling.qml", '''pragma Singleton
import QtQuick
QtObject { function fontSize(n) { return 14+n; } function radius(n) { return 8; } }
''')
            write("modules/theme/Motion.qml", '''pragma Singleton
import QtQuick
QtObject { property bool enabled: true; property int enter: 255; property int exit: 180 }
''')
            write("modules/theme/Colors.qml", '''pragma Singleton
import QtQuick
QtObject { property color primary: "cyan"; property color overBackground: "white" }
''')
            write("modules/components/StyledRect.qml", '''import QtQuick
Rectangle { property string variant }
''')
            write("modules/components/StyledText.qml", "import QtQuick\nText {}")
            write("shell.qml", '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.modules.shell
ShellRoot {
    Window {
        id: win; visible: true; width: 320; height: 240
        property int previous: 0
        property int next: 0
        EdgeWindowTab { id: left; x: 2; y: 80; leftSide: true; onActivated: win.previous++ }
        EdgeWindowTab { id: right; x: 298; y: 80; onActivated: win.next++ }
        TestCase {
            id: test; name: "EdgeWindowTabs"; when: false
            function test_hover() {
                mouseMove(win.contentItem, 160, 120);
                mouseMove(left, 8, 25); wait(70);
                mouseMove(win.contentItem, 160, 120); wait(250);
                compare(win.previous, 0); // Passing over must not switch.
                mouseMove(left, 8, 25); wait(160);
                verify(left.lift > 1); // The home indicator bounces past its resting position.
                fuzzyCompare(left.width, 14 * 1.4, 0.001); // Its hit target stays stationary.
                wait(200); compare(win.previous, 1);
                fuzzyCompare(left.lift, 1, 0.001);
                wait(500); compare(win.previous, 1); // No repeated switching.
                mouseMove(win.contentItem, 160, 120);
                mouseMove(left, 8, 25); wait(250);
                compare(win.previous, 2); // Leaving rearms the tab.
                mouseMove(right, 8, 25); wait(250);
                compare(win.next, 1); compare(win.previous, 2);
                mouseMove(win.contentItem, 160, 120);
                mouseMove(right, 8, 25); wait(70);
                right.enabled = false; wait(250);
                compare(win.next, 1); // Disabling cancels a pending switch.
                right.enabled = true;
                mouseMove(win.contentItem, 160, 120);
                mouseMove(right, 8, 25); wait(70);
                right.visible = false; wait(350);
                fuzzyCompare(right.lift, 0, 0.001);
                compare(win.next, 1); // Hiding also cancels it.
                console.log("PASS hover once, reentry, both directions, cancellation");
                Qt.quit();
            }
        }
    }
    Timer { interval: 200; running: true; onTriggered: test.test_hover() }
    Timer { interval: 6000; running: true; onTriggered: Qt.exit(1) }
}
''')
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            result = subprocess.run(
                ["qs", "-p", str(root), "--no-color"],
                env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                         XDG_RUNTIME_DIR=str(runtime)),
                capture_output=True, text=True, timeout=9,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("QtQuickTest::fail", output)
            self.assertIn("PASS hover once, reentry, both directions, cancellation", output)


if __name__ == "__main__":
    unittest.main()
