"""Test the real shell content stacking with a sidebar behind an open menu."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class PanelOutsideClickTest(unittest.TestCase):
    def test_outside_click_dismisses_above_sidebar(self):
        source = Path(os.environ.get("BAR_PANEL_SOURCE", ROOT / "modules/shell/UnifiedShellPanel.qml")).read_text()
        full_screen_input = next(line for line in source.splitlines() if "readonly property bool needsFullScreenInput:" in line)
        # Use the actual content tree and MouseArea stacking. Replace native
        # Wayland window setup with an offscreen Window for pointer injection.
        start = min(source.index("    Item {\n        id: visualContent"), source.index("    MouseArea {\n        id: backdropArea") if "    MouseArea {\n        id: backdropArea" in source else len(source))
        content = source[start:source.rfind("}")]
        with tempfile.TemporaryDirectory(prefix="panel-outside-") as temporary:
            package = Path(temporary)

            def write(relative, text):
                target = package / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)

            write("modules/bar/BarContent.qml", '''import QtQuick
Item {
 id: root; objectName: "bar-content"; property var screen
 property bool islandActive: true; property bool dashboardInputActive: false
 function collapseIsland() { islandActive = false; }
 MouseArea { objectName: "menu"; width:300; height:200; x:100; onClicked: {} }
}''')
            write("modules/sidebar/AssistantSidebar.qml", '''import QtQuick
Item {
 id: root; objectName: "sidebar"; anchors.fill: parent
 property var targetScreen; property bool tiled:false; property bool windowFocused:true; property bool active:true; property bool wantsFocus:true
 property int clicks:0
 MouseArea { anchors.fill:parent; onClicked:root.clicks++ }
}''')
            write("modules/widgets/launcher/RunMenuHost.qml", "import QtQuick\nItem {property var screen;property Item barPanel;property bool open:false}")
            write("modules/widgets/fileshelf/FileShelfPanel.qml", "import QtQuick\nItem {property var screen;property bool open:false}")
            write("modules/widgets/notes/NotesPopup.qml", "import QtQuick\nItem {property var screen;property bool open:false}")
            write("modules/widgets/powermenu/PowerMenuHost.qml", "import QtQuick\nItem {property Item panel}")
            write("modules/notifications/NotificationToastStack.qml", "import QtQuick\nItem {}")
            for name, properties in {
                "Visibilities": 'function setActiveModule(name) {} function closeActiveBarPopup() {}',
                "FocusGrabManager": 'property bool hasActiveGrab:false; function clearTopGrab() {}',
                "QuickNotes": 'function close() {}',
                "SystemResources": 'property bool keepMonitorOpen:false',
            }.items():
                write(f"modules/services/{name}.qml", f"pragma Singleton\nimport QtQuick\nQtObject {{{properties}}}")
            write("modules/globals/GlobalStates.qml", "pragma Singleton\nimport QtQuick\nQtObject {property bool assistantAvailable:true;property bool assistantPinned:false}")
            write("shell.qml", '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.modules.bar
import qs.modules.sidebar
import qs.modules.services
import qs.modules.globals
import qs.modules.widgets.launcher
import qs.modules.widgets.fileshelf
import qs.modules.widgets.notes
import qs.modules.widgets.powermenu
import qs.modules.notifications
ShellRoot {
 Window {id:win;visible:true;width:800;height:600
  Item {
   id:unifiedPanel;anchors.fill:parent
   property var targetScreen:Quickshell.screens[0]
   property bool barEnabled:true
   property string barPosition:"top"
   property int barTargetHeight:36
   property int barOuterMargin:0
   readonly property Item assistantSidebar:assistantSidebarLoader.item
''' + full_screen_input + "\n" + content + '''
  }
  TestCase {id:test;name:"outside";when:windowShown;
   function find(item,name) {if(item.objectName===name)return item;for(const c of item.children??[]){const f=find(c,name);if(f)return f;}return null;}
   function checkClicks() {
    const bar=find(unifiedPanel,"bar-content");
    const sidebar=find(unifiedPanel,"sidebar");
    verify(bar!==null);verify(sidebar!==null);
    mouseClick(win.contentItem,150,100,Qt.LeftButton);
    compare(bar.islandActive,true,"inside menu stays open");
    for(const button of [Qt.LeftButton,Qt.RightButton,Qt.MiddleButton]) {
     bar.islandActive=true;
     mouseClick(win.contentItem,600,350,button);
     compare(bar.islandActive,false,"outside dismisses above sidebar");
     compare(sidebar.clicks,0,"dismissal click does not activate sidebar");
    }
    mouseClick(win.contentItem,600,350,Qt.LeftButton);
    compare(sidebar.clicks,1,"sidebar works after dismissal");
    bar.islandActive=true;
    SystemResources.keepMonitorOpen=true;
    for(const button of [Qt.LeftButton,Qt.RightButton,Qt.MiddleButton]) {
     mouseClick(win.contentItem,600,350,button);
     compare(bar.islandActive,true,"window inspector stays open on outside clicks");
    }
    compare(sidebar.clicks,2,"outside left click reaches underlying sidebar while inspector stays open");
    SystemResources.keepMonitorOpen=false;
    mouseClick(win.contentItem,600,350,Qt.LeftButton);
    compare(bar.islandActive,false,"normal dismissal restored after leaving inspector");
    console.log("PASS inside/outside clicks, all mouse buttons, sidebar stacking and restored input");
    Qt.quit();
   }
  }
  Timer {interval:150;running:true;onTriggered:test.checkClicks()}
  Timer {interval:2000;running:true;onTriggered:Qt.exit(1)}
 }
}''')
            runtime = package / "runtime"
            runtime.mkdir(mode=0o700)
            result = subprocess.run(
                ["qs", "-p", str(package), "--no-color"],
                env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", XDG_RUNTIME_DIR=str(runtime)),
                capture_output=True, text=True, timeout=5,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("PASS inside/outside clicks", output)


if __name__ == "__main__":
    unittest.main()
