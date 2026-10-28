"""Run Bluetooth lifecycle through real QML and synthetic CLI processes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell required")
class BluetoothServiceTest(unittest.TestCase):
    def test_actions_and_discovery(self):
        with tempfile.TemporaryDirectory(prefix="bluetooth-service-") as temporary:
            base = Path(temporary)
            package = base / "package"
            shutil.copytree(ROOT / "tests/fixtures/bluetooth", package)
            for name in ("BluetoothService.qml", "BluetoothDevice.qml"):
                source = Path(os.environ.get("BT_SERVICE_SOURCE", ROOT / "modules/services"))
                shutil.copyfile(source / name, package / "modules/services" / name)
            binaries = base / "bin"
            binaries.mkdir()
            shutil.copyfile(package / "bluetoothctl", binaries / "bluetoothctl")
            (binaries / "bluetoothctl").chmod(0o755)
            shutil.copyfile(package / "bluetoothctl", binaries / "rfkill")
            (binaries / "rfkill").chmod(0o755)
            # Exercise QML's pairing helper boundary without touching real devices.
            (binaries / "python3").write_text(
                f'#!{sys.executable}\nimport os, sys\n'
                'if not sys.argv[1].endswith("/scripts/bluetooth_pair.py"):\n'
                f'    os.execv({sys.executable!r}, [{sys.executable!r}] + sys.argv[1:])\n'
                'assert sys.argv[1].endswith("/scripts/bluetooth_pair.py"), sys.argv\n'
                f'os.execv({sys.executable!r}, [{sys.executable!r}, '
                f'{str(binaries / "bluetoothctl")!r}, "pair", sys.argv[2]])\n')
            (binaries / "python3").chmod(0o755)
            # Simulate continuous advertisements: updates must not be starved by
            # restarting the debounce timer on every incoming BlueZ signal.
            (binaries / "gdbus").write_text(
                f'#!{sys.executable}\nimport time\n'
                'for _ in range(150):\n'
                '    print("PropertiesChanged", flush=True)\n'
                '    time.sleep(0.02)\n')
            (binaries / "gdbus").chmod(0o755)
            state = base / "state.json"
            state.write_text(json.dumps({"powered": False, "blocked": True, "devices": {
                "AA:00:00:00:00:01": {"name": "Headphones", "paired": True, "trusted": True, "connected": False},
                "AA:00:00:00:00:02": {"name": "Speaker", "paired": False, "trusted": False, "connected": False},
            }}))
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                               XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(base / "cache"),
                               BT_TEST_STATE=str(state), PATH=str(binaries) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["qs", "-p", str(package), "--no-color"], env=environment,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("FAIL", output, output)
            self.assertNotIn("TypeError", output, output)
            self.assertIn("PASS Bluetooth actions and discovery", output, output)


if __name__ == "__main__":
    unittest.main()
