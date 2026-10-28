"""Exercise pin/unpin on the real sidebar and native assistant window."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.modules.services
import qs.modules.sidebar
import qs.modules.globals
ShellRoot {
    id: test
    property int stage: 0
    property Item originalPage: null
    function check(ok, message) {
        if (!ok) { console.error("FAIL", message); Qt.exit(1); }
    }
    AssistantWindow { id: tiledWindow; targetScreen: Quickshell.screens[0] }
    Window {
        title: "Assistant input regression"
        visible: true
        width: 1280; height: 800
        Loader {
            id: host
            anchors.fill: parent
            sourceComponent: AssistantSidebar {
                id: sidebar
                targetScreen: Quickshell.screens[0]
                tiled: GlobalStates.assistantPinned
                parent: tiled ? tiledWindow.contentItem : host
            }
        }
    }
    TestCase {
        id: inputTest
        parent: host
        when: false
        function checkTyping(view) {
            const input = view.currentPage.input;
            for (const busy of [false, true]) {
                Ai.activeSession.agentTurnActive = busy;
                view.wantsFocus = false;
                input.focus = false;
                input.text = "";
                mouseClick(input, 20, input.height / 2);
                compare(view.wantsFocus, true, "first click requests keyboard focus");
                tryCompare(input, "activeFocus", true);
                keyClick(Qt.Key_X);
                compare(input.text, "x", "first click permits typing");
            }
            Ai.activeSession.agentTurnActive = false;
            input.text = "unsent draft";
        }
    }
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            const view = host.item;
            switch (test.stage++) {
            case 0:
                test.originalPage = view.currentPage;
                try { inputTest.checkTyping(view); }
                catch (error) { console.error("Input check failed", error); Qt.exit(1); }
                view.currentPage.input.text = "unsent draft";
                GlobalStates.assistantWidth = 450;
                view.windowFocused = false;
                view.wantsFocus = false;
                GlobalStates.toggleAssistant();
                test.check(!GlobalStates.assistantVisible, "one shortcut closes unfocused sidebar");
                GlobalStates.toggleAssistant();
                test.check(view.parent === host, "initial sidebar parent");
                break;
            case 1:
                test.check(GlobalStates.assistantVisible, "one shortcut reopens sidebar");
                test.findPin(view).clicked();
                break;
            case 2:
                test.check(tiledWindow.visible, "pin opens native window");
                test.check(view.parent === tiledWindow.contentItem, "view moved into window");
                test.check(view.currentPage === test.originalPage, "same chat page");
                test.check(view.currentPage.input.text === "unsent draft", "draft retained");
                test.check(Math.abs(view.hitbox.width - tiledWindow.contentItem.width) < 1, "chat fills tile");
                test.check(!view.resizeHitbox.visible, "sidebar resize handle hidden");
                test.check(GlobalStates.assistantWidth === 450, "tile leaves saved sidebar width alone");
                console.log("TILED");
                break;
            case 3:
                test.findPin(view).clicked();
                break;
            case 4:
                test.check(!tiledWindow.visible && GlobalStates.assistantVisible, "unpin returns to open sidebar");
                test.check(view.parent === host && view.currentPage === test.originalPage, "same view returns");
                test.check(view.currentPage.input.text === "unsent draft", "draft returns");
                GlobalStates.assistantPinned = true;
                break;
            case 5:
                view.windowFocused = false;
                view.wantsFocus = false;
                GlobalStates.toggleAssistant();
                test.check(!GlobalStates.assistantVisible, "one shortcut closes unfocused tile");
                break;
            case 6:
                test.check(!tiledWindow.visible, "hide unmaps tile");
                GlobalStates.toggleAssistant();
                break;
            case 7:
                test.check(tiledWindow.visible, "reopen restores tile");
                tiledWindow.closed();
                break;
            case 8:
                test.check(!GlobalStates.assistantVisible && !tiledWindow.visible, "native close hides assistant");
                console.log("PASS pin unpin draft resize hide reopen close");
                Qt.quit();
            }
        }
    }
    function findPin(item) {
        if (item.objectName === "assistantPinButton") return item;
        for (const child of item.children || []) {
            const found = findPin(child);
            if (found) return found;
        }
        return null;
    }
}
'''

@unittest.skipUnless(shutil.which("qs"), "Quickshell required")
class AiTilingTest(unittest.TestCase):
    def test_pin_unpin_retains_view_and_draft(self):
        live = os.environ.get("ASSISTANT_TILING_LIVE") == "1"
        with tempfile.TemporaryDirectory(prefix="assistant-tiling-") as temporary:
            base = Path(temporary)
            package = base / "qml"
            shutil.copytree(ROOT / "tests/fixtures/ai_sidebar", package)
            for relative in (
                "modules/services/Ai.qml", "modules/services/AiSession.qml", "modules/services/AiQuestions.js",
                "modules/sidebar/AssistantSidebar.qml", "modules/sidebar/AssistantWindow.qml",
                "modules/sidebar/AssistantActivity.qml", "modules/sidebar/AssistantQuestions.qml",
                "modules/sidebar/AssistantModelPicker.qml", "modules/sidebar/CodeBlock.qml",
                "modules/theme/Motion.qml", "modules/components/StyledRect.qml",
                "modules/components/StyledToolTip.qml", "modules/components/StyledText.qml",
            ):
                target = package / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            (package / "shell.qml").write_text(SHELL)
            # Exercise the production visibility transition with isolated services.
            production = (Path.home() / "code/rebos-assistant/modules/globals/GlobalStates.qml").read_text()
            start = production.index("    function toggleAssistant() {")
            end = production.index("    function hideAssistant()", start)
            globals_path = package / "modules/globals/GlobalStates.qml"
            fixture = globals_path.read_text()
            fixture_start = fixture.index("    function toggleAssistant() {")
            fixture_end = fixture.index("    function hideAssistant()", fixture_start)
            globals_path.write_text("import qs.modules.services\n" + fixture[:fixture_start] + production[start:end] + fixture[fixture_end:])
            (package / "modules/services/NiriService.qml").write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property var focusedMonitor: null
    property var focusedClient: null
    property QtObject clients: QtObject { property var values: [] }
    function focusWindow(id) {}
}
''')
            config = package / "config/Config.qml"
            config.write_text(config.read_text().replace("property bool enabled: false", "property bool enabled: false\n        property bool sidebarPinnedOnStartup: false"))
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM="wayland" if live else "offscreen", QT_QPA_PLATFORMTHEME="",
                       XDG_CACHE_HOME=str(base / "cache"))
            if not live:
                env["XDG_RUNTIME_DIR"] = str(runtime)
            with (base / "output").open("w+") as output:
                process = subprocess.Popen(["qs", "-p", str(package), "--no-color"], env=env, stdout=output, stderr=output)
                seen = []
                input_focused = False
                try:
                    deadline = time.monotonic() + 10
                    while process.poll() is None and time.monotonic() < deadline:
                        if live:
                            windows = json.loads(subprocess.check_output(["niri", "msg", "-j", "windows"], text=True))
                            seen.extend(w for w in windows if w["title"] == "rebos_shell Assistant")
                            if not input_focused:
                                for window in windows:
                                    if window["title"] == "Assistant input regression":
                                        subprocess.run(["niri", "msg", "action", "focus-window", "--id", str(window["id"])], check=True, capture_output=True)
                                        input_focused = True
                                        break
                        time.sleep(0.05)
                    self.assertIsNotNone(process.poll(), "QML test timed out")
                finally:
                    if process.poll() is None:
                        process.kill()
                    process.wait()
                output.seek(0)
                log = output.read()
            self.assertEqual(process.returncode, 0, log[-5000:])
            self.assertIn("PASS pin unpin draft resize hide reopen close", log)
            self.assertNotIn("FAIL", log)
            if live:
                self.assertTrue(seen, "Compositor never saw assistant as a native window")
                self.assertTrue(all(not w["is_floating"] for w in seen), seen)

if __name__ == "__main__":
    unittest.main()
