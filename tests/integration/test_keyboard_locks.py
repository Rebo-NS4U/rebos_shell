"""Check actual sysfs-style LED changes and silent startup/hotplug behavior."""
import importlib.util
from pathlib import Path
import tempfile
import os
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("lock_key_monitor", ROOT / "scripts/lock_key_monitor.py")
monitor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(monitor)


class KeyboardLocksTest(unittest.TestCase):
    def test_state_changes_and_stale_secondary_keyboard(self):
        with tempfile.TemporaryDirectory(prefix="keyboard-led-test-") as temporary:
            directory = Path(temporary)
            for device in ("input2", "input5"):
                for key in ("capslock", "numlock", "scrolllock"):
                    path = directory / (device + "::" + key)
                    path.mkdir()
                    (path / "brightness").write_text("1" if key == "numlock" else "0")
            state = monitor.LockState()
            initial = state.update(monitor.read_leds(directory))
            self.assertEqual(initial, {"states": {"caps": False, "num": True, "scroll": False}, "changed": []})
            caps = directory / "input2::capslock/brightness"
            caps.write_text("1")
            self.assertEqual(state.update(monitor.read_leds(directory))["changed"], ["caps"])
            caps.write_text("0")
            self.assertFalse(state.update(monitor.read_leds(directory))["states"]["caps"])
            # A new device should not create an on-screen key press.
            extra = directory / "input9::capslock"
            extra.mkdir()
            (extra / "brightness").write_text("1")
            self.assertEqual(state.update(monitor.read_leds(directory))["changed"], [])
            (extra / "brightness").unlink()
            self.assertEqual(state.update(monitor.read_leds(directory))["changed"], [])

    def test_missing_and_invalid_files(self):
        with tempfile.TemporaryDirectory(prefix="keyboard-led-test-") as temporary:
            directory = Path(temporary)
            path = directory / "input2::capslock"
            path.mkdir()
            (path / "brightness").write_text("unavailable")
            self.assertEqual(monitor.read_leds(directory), {})
            self.assertEqual(monitor.LockState().update({}), {"states": {}, "changed": []})


@unittest.skipUnless(shutil.which("qs"), "Quickshell required")
class KeyboardLockUiTest(unittest.TestCase):
    def test_toast_state_and_timeout(self):
        with tempfile.TemporaryDirectory(prefix="keyboard-toast-test-") as temporary:
            base = Path(temporary)
            package = base / "qml"
            shutil.copytree(ROOT / "tests/fixtures/ai_sidebar", package)
            for relative in ("modules/services/KeyboardLocks.qml", "modules/shell/osd/LockKeyToast.qml", "modules/shell/osd/LockKeyOSD.qml", "modules/components/StyledRect.qml"):
                target = package / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            (package / "modules/services/NiriService.qml").write_text('pragma Singleton\nimport Quickshell\nSingleton { property var focusedMonitor: null }')
            globals_file = package / "modules/globals/GlobalStates.qml"
            globals_file.write_text(globals_file.read_text().replace("Singleton {", "Singleton {\n    property bool lockscreenVisible: false"))
            # Offscreen Qt has no layer-shell backend. Retain the production
            # visibility binding and child hierarchy in a normal Qt window.
            # BackgroundEffect attaches to native Quickshell windows only; blur
            # geometry has its own production-component integration test.
            host = package / "modules/shell/osd/LockKeyOSD.qml"
            host_source = host.read_text().replace("PanelWindow {", "Window {").replace("implicitHeight:", "height:")
            host.write_text("\n".join(line for line in host_source.splitlines()
                if not line.strip().startswith(("screen:", "anchors.bottom: true", "anchors.left: true",
                    "anchors.right: true", "exclusionMode:", "WlrLayershell.", "mask:", "BackgroundEffect."))))
            # Exercise the real service logic without a second hardware monitor.
            service = package / "modules/services/KeyboardLocks.qml"
            service.write_text(service.read_text().replace('running: true', 'running: false'))
            (package / "shell.qml").write_text(r'''import QtQuick
import Quickshell
import qs.modules.services
import qs.modules.shell.osd
ShellRoot {
    function check(ok, message) { if (!ok) { console.error("FAIL", message); Qt.exit(1); } }
    LockKeyOSD { id: osd; targetScreen: Quickshell.screens[0] }
    Window {
        visible: true; width: 500; height: 200; color: "#171920"
        LockKeyToast { id: toast; anchors.centerIn: parent; shown: KeyboardLocks.toastVisible }
    }
    Timer {
        interval: 50; running: true
        onTriggered: {
            KeyboardLocks.acceptSnapshot({states: {caps: false, num: true, scroll: false}, changed: []});
            check(!KeyboardLocks.toastVisible && KeyboardLocks.numLock && !osd.visible, "startup is silent");
            KeyboardLocks.acceptSnapshot({states: {caps: true, num: true, scroll: false}, changed: ["caps"]});
            check(KeyboardLocks.toastVisible && KeyboardLocks.label === "Caps Lock" && KeyboardLocks.lastEnabled, "Caps Lock on");
            check(toast.visible && toast.width < 400 && toast.height < 100, "compact card rendered");
            check(osd.visible, "hidden popup window opens on a lock change");
            KeyboardLocks.acceptSnapshot({states: {caps: false, num: true, scroll: false}, changed: ["caps"]});
            check(KeyboardLocks.description === "Lowercase letters" && !KeyboardLocks.lastEnabled, "Caps Lock off replaces card");
            KeyboardLocks.acceptSnapshot({states: {caps: false, num: false, scroll: false}, changed: ["num"]});
            check(KeyboardLocks.label === "Num Lock" && KeyboardLocks.description === "Navigation keys enabled", "Num Lock feedback");
            KeyboardLocks.acceptSnapshot({states: {caps: false, num: false, scroll: true}, changed: ["scroll"]});
            check(KeyboardLocks.label === "Scroll Lock" && KeyboardLocks.description === "Scrolling locked", "Scroll Lock feedback");
            finish.start();
        }
    }
    Timer { id: finish; interval: 1750; onTriggered: {
        check(!KeyboardLocks.toastVisible && !toast.visible && !osd.visible, "toast and popup window close after fading");
        console.log("PASS lock key toast"); Qt.quit();
    } }
    Timer { interval: 4000; running: true; onTriggered: Qt.exit(1) }
}
''')
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            result = subprocess.run(["qs", "-p", str(package), "--no-color"],
                env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", XDG_RUNTIME_DIR=str(runtime)),
                capture_output=True, text=True, timeout=6)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-5000:])
            self.assertIn("PASS lock key toast", output)
            for error in ("TypeError", "ReferenceError", "is not a type", "FAIL"):
                self.assertNotIn(error, output)


if __name__ == "__main__":
    unittest.main()
