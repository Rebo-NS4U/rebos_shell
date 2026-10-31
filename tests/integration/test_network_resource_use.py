"""Check idle network work and live events through the real QML service."""
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
class NetworkResourceTest(unittest.TestCase):
    def test_idle_queries_use_cache_and_events_and_scan_still_work(self):
        with tempfile.TemporaryDirectory(prefix="network-resource-") as temporary:
            base = Path(temporary)
            package = base / "qml"
            services = package / "modules/services"
            services.mkdir(parents=True)
            for name in ("NetworkService.qml", "WifiAccessPoint.qml"):
                shutil.copy2(ROOT / "modules/services" / name, services / name)
            shutil.copy2(ROOT / "tests/fixtures/bluetooth/modules/services/SuspendManager.qml",
                         services / "SuspendManager.qml")
            for module, name, properties in (
                ("globals", "GlobalStates", "property bool dashboardOpen: false"),
                ("theme", "Icons", 'property string wifiHigh: "wifi"; property string wifiMedium: "wifi"; property string wifiLow: "wifi"; property string wifiNone: "wifi"; property string wifiOff: "off"'),
            ):
                folder = package / "modules" / module
                folder.mkdir()
                (folder / (name + ".qml")).write_text(
                    "pragma Singleton\nimport Quickshell\nSingleton { " + properties + " }\n")
            binaries = base / "bin"
            binaries.mkdir()
            fake = binaries / "nmcli"
            fake.write_text(f"#!{sys.executable}\n" + r'''
import json, os, sys, time
from pathlib import Path
base = Path(os.environ['NETWORK_TEST_BASE'])
args = sys.argv[1:]
with (base / 'calls').open('a') as log:
    log.write(json.dumps(args) + '\n')
if args == ['monitor']:
    time.sleep(1)
    (base / 'disconnected').touch()
    print('device: disconnected', flush=True)
    time.sleep(60)
elif args == ['radio', 'wifi']:
    print('enabled')
elif args == ['-t', '-f', 'TYPE,STATE,CONNECTION', 'd', 'status']:
    print('wifi:disconnected:' if (base / 'disconnected').exists() else 'wifi:connected:Test')
elif args == ['-t', '-f', 'CONNECTIVITY', 'g']:
    print('full')
elif args and args[0] == '-g':
    print(('no' if (base / 'disconnected').exists() else 'yes') + ':80:5200:Test:AA\\:BB\\:CC\\:DD\\:EE\\:FF:WPA2')
''')
            fake.chmod(0o755)
            (package / "shell.qml").write_text('''
import QtQuick
import Quickshell
import qs.modules.services
import qs.modules.globals
ShellRoot {
    property string networkState: NetworkService.wifiStatus
    function check(value, label) {
        if (!value) { console.error("FAIL", label); Qt.exit(1); }
    }
    Timer { interval: 700; running: true; onTriggered: {
        check(NetworkService.wifiStatus === "connected", "initial connected state");
    } }
    Timer { interval: 1800; running: true; onTriggered: {
        check(NetworkService.wifiStatus === "disconnected", "event update while controls closed");
    } }
    Timer { interval: 4000; running: true; onTriggered: {
        NetworkService.rescanWifi();
    } }
    Timer { interval: 4800; running: true; onTriggered: {
        check(!NetworkService.wifiScanning, "explicit scan finishes");
        GlobalStates.dashboardOpen = true;
    } }
    Timer { interval: 7800; running: true; onTriggered: {
        console.log("PASS network events and explicit scan"); Qt.exit(0);
    } }
}
''')
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                       XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(base / "cache"),
                       NETWORK_TEST_BASE=str(base), PATH=str(binaries) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["qs", "-n", "-p", str(package)], env=env,
                                    capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("PASS network events and explicit scan", output)
            self.assertNotIn("TypeError", output)
            calls = [json.loads(line) for line in (base / "calls").read_text().splitlines()]
            queries = [call for call in calls if call and call[0] == "-g"]
            # Initial state, monitor event, explicit scan, then one open-controls poll.
            self.assertEqual(len(queries), 4, calls)
            self.assertTrue(all(call[-2:] == ["--rescan", "no"] for call in queries), calls)
            self.assertIn(["dev", "wifi", "list", "--rescan", "yes"], calls)


if __name__ == "__main__":
    unittest.main()
