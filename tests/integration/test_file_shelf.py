"""Real Qt URI drops, shelf actions, persistence and file-reference safety."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("file_shelf", ROOT / "scripts/file_shelf.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class ShelfFilesTest(unittest.TestCase):
    def test_local_paths_duplicates_and_unsupported_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            file = root / "café #1 $(touch nope).txt"
            file.write_text("original contents")
            folder = root / "folder"
            folder.mkdir()
            os.mkfifo(root / "pipe")
            result = helper.describe([file.as_uri(), file.as_uri(), folder.as_uri(),
                                      file.as_uri().replace("file:///", "file://localhost/"),
                                      "https://example.com/file", "file://remote/etc/passwd",
                                      (root / "missing").as_uri(), (root / "pipe").as_uri(),
                                      "file:///tmp/%00", 1])
            self.assertEqual([row["path"] for row in result["entries"]], [str(file), str(folder)])
            self.assertEqual(result["rejected"], 6)
            self.assertTrue(result["entries"][1]["directory"])
            self.assertEqual(file.read_text(), "original contents")
            self.assertFalse((root / "nope").exists())


@unittest.skipUnless(shutil.which("qs") and shutil.which("c++"), "Quickshell and Qt development tools required")
class ShelfQmlTest(unittest.TestCase):
    def test_native_qt_drops_actions_and_reload(self):
        with tempfile.TemporaryDirectory(prefix="file-shelf-") as directory:
            root = Path(directory)
            shutil.copytree(ROOT / "modules", root / "modules")
            for name in ("config", "assets", "version"):
                (root / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())
            (root / "scripts").mkdir()
            shutil.copy(ROOT / "scripts/file_shelf.py", root / "scripts/file_shelf.py")
            palette = (ROOT / "modules/theme/Colors.qml").read_text()
            names = json.loads(re.search(r"availableColorNames: (\[.*?\])", palette).group(1))
            (root / "modules/theme/Colors.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject {property list<string> availableColorNames: " + json.dumps(names) + ";" + "".join("property color " + name + ': "' + ("white" if name.startswith("over") else "#28232c") + '";' for name in names) + "}")
            (root / "modules/services/NiriService.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject {property var focusedMonitor: null}')
            (root / "modules/globals/GlobalStates.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject {property var wallpaperManager: null; property bool lockscreenVisible: false}')
            service = root / "modules/services/FileShelf.qml"
            service.write_text(service.read_text().replace('Quickshell.statePath("file-shelf.json")', 'Quickshell.env("SHELF_TEST_STATE")'))
            config = root / "xdg/rebos_shell/config"
            config.mkdir(parents=True)
            for source in (ROOT / "assets/presets/rebos_shell Default").glob("*.json"):
                shutil.copy(source, config / source.name)
            file = root / "hello # café.txt"
            file.write_text("original")
            folder = root / "folder"
            folder.mkdir()
            state = root / "shelf.json"
            plugin = root / "ShelfTest"
            plugin.mkdir()
            source = ROOT / "tests/fixtures/file_shelf/dropinjector.cpp"
            flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "Qt6Quick", "Qt6Qml", "Qt6Gui"], text=True).split()
            subprocess.run(["/usr/lib/qt6/moc", *[flag for flag in flags if flag.startswith(("-I", "-D"))], str(source), "-o", str(plugin / "dropinjector.moc")], check=True)
            subprocess.run(["c++", "-std=c++17", "-shared", "-fPIC", str(source), "-I" + str(plugin), "-o", str(plugin / "libshelftest.so"), *flags], check=True, capture_output=True)
            (plugin / "qmldir").write_text("module ShelfTest\nplugin shelftest\n")
            runtime = root / "runtime"
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, HOME=str(root), QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QPA_PLATFORMTHEME="", QML_IMPORT_PATH=str(root), XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(root / "xdg"), XDG_CACHE_HOME=str(root / "cache"), SHELF_TEST_STATE=str(state), SHELF_TEST_URI=file.as_uri(), SHELF_TEST_FOLDER=folder.as_uri())
            (root / "shell.qml").write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.config
import qs.modules.services
import qs.modules.globals
import qs.modules.widgets.fileshelf
import ShelfTest 1.0
ShellRoot {
 Window {visible: true; width: 850; height: 800
  FileShelfPanel {id: shelf; anchors.fill: parent; screen: Quickshell.screens[0]}
  DropInjector {id: injector}
  TestCase {id: test; when: false
   function test_shelf() {
    tryCompare(Config,"initialLoadComplete",true,5000);
    tryCompare(FileShelf,"ready",true,3000);
    Config.theme.animDuration=0;
    const uri=Quickshell.env("SHELF_TEST_URI");
    const folder=Quickshell.env("SHELF_TEST_FOLDER");
    const handle=findChild(shelf,"file-shelf-handle");
    verify(handle !== null); verify(shelf.handleHitbox !== null); compare(shelf.shelfHitbox,null);
    const trigger=findChild(shelf,"file-shelf-trigger");
    compare(handle.visible,false);
    mouseMove(trigger,1,trigger.height/2); wait(100); compare(shelf.open,false);
    verify(injector.enter(trigger,[uri],Qt.CopyAction));
    tryCompare(shelf,"open",true,1000); compare(handle.visible,true);
    injector.leave(trigger); tryCompare(shelf,"open",false,600); compare(handle.visible,false);
    verify(!injector.enter(trigger,["https://example.com/file"],Qt.CopyAction));
    wait(250); compare(shelf.open,false); injector.leave(trigger);
    let result=injector.drop(trigger,[uri],Qt.CopyAction|Qt.MoveAction);
    verify(result.entered); verify(result.accepted); compare(result.action,Qt.CopyAction);
    tryCompare(FileShelf,"count",1,3000);
    tryCompare(shelf,"open",false,1000); compare(handle.visible,false);
    FileShelf.open(Quickshell.screens[0].name); compare(shelf.open,true);
    result=injector.drop(handle,[uri,folder],Qt.CopyAction);
    verify(result.accepted); tryCompare(FileShelf,"count",2,3000); tryCompare(FileShelf,"busy",false,3000);
    // A source offering only Move is rejected; originals must stay in place.
    result=injector.drop(handle,[uri],Qt.MoveAction); verify(!result.entered); verify(!result.accepted);
    result=injector.drop(handle,["https://example.com/file"],Qt.CopyAction); verify(!result.accepted);
    compare(FileShelf.count,2);
    const card=findChild(shelf,"shelf-file-card"); verify(card !== null);
    compare(card.Drag.supportedActions,Qt.CopyAction);
    compare(card.Drag.mimeData["text/uri-list"],uri+"\\r\\n");
    verify(card.fileName.indexOf("café") >= 0);
    FileShelf.dragging=true;
    FileShelf.clear(); FileShelf.close(); FileShelf.remove(uri);
    compare(FileShelf.count,2); compare(FileShelf.visible,true);
    FileShelf.dragging=false;
    mouseClick(findChild(shelf,"shelf-close")); compare(shelf.open,false); compare(FileShelf.count,2);
    compare(handle.visible,false);
    FileShelf.toggle(Quickshell.screens[0].name);
    tryCompare(shelf,"open",true); compare(FileShelf.count,2);
    FileShelf.remove(folder); compare(FileShelf.count,1);
    GlobalStates.lockscreenVisible=true; compare(shelf.visible,false); compare(shelf.handleHitbox,null);
    GlobalStates.lockscreenVisible=false;
    FileShelf.open("other-screen"); compare(shelf.open,false);
    FileShelf.open(Quickshell.screens[0].name); compare(shelf.open,true);
    FileShelf.clear(); compare(FileShelf.count,0);
    FileShelf.addUrls([uri]);
    FileShelf.clear(); // Late metadata from the cleared batch must not return.
    tryCompare(FileShelf,"busy",false,3000); wait(100); compare(FileShelf.count,0);
    FileShelf.addUrls([uri]); tryCompare(FileShelf,"count",1,3000);
    wait(400); verify(!FileShelf.saving); verify(!FileShelf.error);
    console.log("FILE_SHELF_PASS"); Qt.quit();
   }
  }
  Timer {interval: 700; running: true; onTriggered: {try {test.test_shelf();} catch(error) {console.error("Shelf check failed",error); Qt.exit(1);}}}
  Timer {interval: 15000; running: true; onTriggered: Qt.exit(1)}
 }
}''')

            def run(marker):
                result = subprocess.run(["qs", "-p", str(root), "--no-color"], env=env, capture_output=True, text=True, timeout=20)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertIn(marker, output)
                for error in ("TypeError:", "ReferenceError:", "Failed to load configuration", "Binding loop"):
                    self.assertNotIn(error, output)

            run("FILE_SHELF_PASS")
            self.assertEqual(json.loads(state.read_text()), [file.as_uri()])
            self.assertEqual(file.read_text(), "original")
            self.assertTrue(folder.is_dir())
            (root / "shell.qml").write_text('''import QtQuick
import QtTest
import Quickshell
import qs.modules.services
ShellRoot {
 TestCase {id: test; when: false
  function test_reload() {
   tryCompare(FileShelf,"ready",true,3000);
   tryCompare(FileShelf,"busy",false,3000);
   tryCompare(FileShelf,"count",1,3000);
   compare(FileShelf.files.get(0).uri,Quickshell.env("SHELF_TEST_URI"));
   FileShelf.clear(); wait(400);
   console.log("FILE_SHELF_RELOAD_PASS"); Qt.quit();
  }
 }
 Timer {interval: 500; running: true; onTriggered: {try {test.test_reload();} catch(error) {console.error(error); Qt.exit(1);}}}
}''')
            run("FILE_SHELF_RELOAD_PASS")
            self.assertEqual(json.loads(state.read_text()), [])
            self.assertEqual(file.read_text(), "original")


if __name__ == "__main__":
    unittest.main()
