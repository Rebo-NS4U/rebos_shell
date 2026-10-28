"""Verify the production blur shape follows nested motion and disappears cleanly."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class BackgroundBlurTest(unittest.TestCase):
    def test_nested_movement_transform_and_visibility(self):
        with tempfile.TemporaryDirectory(prefix="background-blur-") as temporary:
            package = Path(temporary)
            shutil.copy2(ROOT / "modules/components/BlurRegion.qml", package / "BlurRegion.qml")
            (package / "shell.qml").write_text('''import QtQuick
import QtTest
import Quickshell
ShellRoot {
 FloatingWindow {
  id: win; implicitWidth:800; implicitHeight:600; visible:true
  Item {
   id: ancestor; x:30; y:40; width:500; height:400
   transform: Translate { id: slide; y:0 }
   Rectangle {
    id: card; x:10; y:20; width:200; height:120; radius:16
    topLeftRadius:4
   }
  }
  BlurRegion { id: shape; target:card }
  Timer {interval:100;running:true;onTriggered:check.checkPanel()}
  TestCase {
   id: check; name:"BackgroundBlur"; when:false
   function checkPanel() {
    tryCompare(shape,"x",40); tryCompare(shape,"y",60);
    compare(shape.width,200); compare(shape.height,120);
    compare(shape.radius,16); compare(shape.topLeftRadius,4);
    ancestor.x=100; ancestor.y=80;
    tryCompare(shape,"x",110); tryCompare(shape,"y",100);
    slide.y=35;
    tryCompare(shape,"y",135);
    card.width=260;
    tryCompare(shape,"width",260);
    ancestor.visible=false;
    tryCompare(shape,"width",0); compare(shape.height,0);
    ancestor.visible=true;
    tryCompare(shape,"width",260);
    shape.enabled=false;
    compare(shape.width,0); compare(shape.height,0);
    shape.enabled=true;
    tryCompare(shape,"width",260);
    card.opacity=0;
    tryCompare(shape,"width",0);
    shape.target=null;
    compare(shape.width,0);
    console.log("PASS blur bounds follow ancestor movement, transforms, resize, visibility and disabling");
    Qt.quit();
   }
  }
 }
 Timer {interval:4000;running:true;onTriggered:Qt.exit(1)}
}''')
            runtime = package / "runtime"
            runtime.mkdir(mode=0o700)
            result = subprocess.run(
                ["qs", "-p", str(package), "--no-color"],
                env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", XDG_RUNTIME_DIR=str(runtime)),
                capture_output=True, text=True, timeout=8,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("PASS blur bounds follow ancestor movement", output)
            self.assertNotIn("FAIL!", output)


if __name__ == "__main__":
    unittest.main()
