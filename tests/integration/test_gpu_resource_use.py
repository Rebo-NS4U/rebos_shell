"""Verify hidden GPU controls stop spawning status queries."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell required")
class GpuResourceTest(unittest.TestCase):
    def test_polling_only_while_controls_visible_and_awake(self):
        with tempfile.TemporaryDirectory(prefix="gpu-resources-") as directory:
            package = Path(directory)
            services = package / "modules/services"
            services.mkdir(parents=True)
            shutil.copy2(ROOT / "modules/services/GpuService.qml", services / "GpuService.qml")
            (services / "SuspendManager.qml").write_text("pragma Singleton\nimport Quickshell\nSingleton {property bool isSuspending:false}")
            globals_dir = package / "modules/globals"
            globals_dir.mkdir()
            (globals_dir / "GlobalStates.qml").write_text("pragma Singleton\nimport Quickshell\nSingleton {property bool dashboardOpen:false;property bool settingsWindowVisible:false}")
            binaries = package / "bin"
            binaries.mkdir()
            fake = binaries / "bash"
            fake.write_text(f"#!{sys.executable}\n" + '''import os
from pathlib import Path
with Path(os.environ['GPU_CALLS']).open('a') as log: log.write('status\\n')
print('amdgpu')
''')
            fake.chmod(0o755)
            probe = binaries / "sh"
            probe.write_text("#!/bin/sh\nexit 1\n")
            probe.chmod(0o755)
            (package / "shell.qml").write_text('''import QtQuick
import Quickshell
import qs.modules.services
import qs.modules.globals
ShellRoot {
 property string driver: GpuService.driver
 Timer {interval: 5500;running:true;onTriggered: {
  if(GpuService.driver!=="amdgpu") Qt.exit(1);
  GlobalStates.dashboardOpen=true;
 }}
 Timer {interval: 6000;running:true;onTriggered: {
  GlobalStates.dashboardOpen=false;
  GlobalStates.settingsWindowVisible=true;
 }}
 Timer {interval: 6500;running:true;onTriggered: SuspendManager.isSuspending=true}
 Timer {interval: 12000;running:true;onTriggered: {console.log("GPU_IDLE_PASS"); Qt.quit();}}
}''')
            runtime = package / "runtime"
            runtime.mkdir(mode=0o700)
            calls = package / "calls"
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(package / "cache"), GPU_CALLS=str(calls), PATH=str(binaries) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["qs", "-p", str(package)], env=env, capture_output=True, text=True, timeout=16)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("GPU_IDLE_PASS", output)
            self.assertNotIn("ReferenceError", output)
            # Startup, dashboard open, settings open. No hidden or suspended polls.
            self.assertEqual(calls.read_text().splitlines(), ["status"] * 3, output)


if __name__ == "__main__":
    unittest.main()
