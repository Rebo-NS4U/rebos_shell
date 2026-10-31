"""Verify panel lifetime and launcher navigation using the production QML hosts."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell required")
class ReleaseResourceTest(unittest.TestCase):
    def test_lazy_panels_and_launcher_selection(self):
        with tempfile.TemporaryDirectory(prefix="enclosure-release-") as temporary:
            package = Path(temporary)
            shutil.copytree(ROOT / "modules", package / "modules")
            for name in ("config", "assets", "version"):
                (package / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())

            def write(path, value):
                (package / path).write_text(value)

            names = json.loads(re.search(r"availableColorNames: (\[.*?\])", (ROOT / "modules/theme/Colors.qml").read_text()).group(1))
            write("modules/theme/Colors.qml", "pragma Singleton\nimport QtQuick\nQtObject {property list<string> availableColorNames: " + json.dumps(names) + ";" + "".join("property color " + n + ': "' + ("white" if n.startswith("over") else "#252525") + '";' for n in names) + "}")
            stubs = {
                "AppSearch": '''signal listChanged(); function invalidateCache() {}
function getAllApps() {let rows=[]; for(let i=0;i<15;i++) rows.push({id:"app"+i,name:"App "+i,icon:"",comment:"",execString:"",categories:[],runInTerminal:false,execute:()=>{}}); return rows;}
function fuzzyQuery(text) {return text === "none" ? [] : getAllApps().slice(0,3);}''',
                "UsageTracker": 'signal usageDataReady(); function recordUsage(id) {}',
                "Visibilities": '''property string currentActiveModule: ""; property QtObject activeBarPopup: null
function registerIsland(name, item) {} function unregisterIsland(name) {} function closeActiveBarPopup() {}
function setActiveModule(name) {currentActiveModule=name;}''',
                "NiriService": '''property QtObject focusedMonitor: null; property QtObject focusedClient: null
property QtObject focusedWorkspace: null; property var clients: []; property var workspaces: []
property list<string> fullscreenOutputs: []; property bool overviewOpen: false; function windowsForWorkspace(id) {return [];}''',
                "Notifications": '''property bool silent: true; property list<string> appNameList: []; property var groupsByAppName: ({})
property var popupList: []; function toggleSilent() {silent=!silent;}''',
                "MprisController": '''property QtObject activePlayer: null; property bool isPlaying: false
property real length: 0; property real progress: 0; property string trackTitle: ""''',
                "Audio": 'property QtObject sink: null; signal volumeChanged(real volume); signal micVolumeChanged(real volume)',
                "Battery": '''property real percentage: 70; property bool isPluggedIn: false; property int chargeState: 0
function statusColor() {return "white";} function getBatteryIcon() {return "B";}''',
                "SuspendManager": 'property bool isSuspending: false',
                "Brightness": 'property bool syncBrightness: false; signal brightnessChanged(real value)',
                "NetworkService": 'function update() {}',
                "BluetoothService": 'function updateStatus() {}',
                "FocusGrabManager": 'function clearTopGrab() {}',
            }
            for name, body in stubs.items():
                write(f"modules/services/{name}.qml", "pragma Singleton\nimport QtQuick\nQtObject {" + body + "}")
            write("modules/globals/GlobalStates.qml", '''pragma Singleton
import QtQuick
QtObject {property string launcherMode: "apps"; property string launcherSearchText: ""; property int launcherSelectedIndex: -1
property bool islandOpen: false; property bool islandLauncherOpen: false; property bool islandStatsOpen: false
function clearLauncherState() {launcherSearchText="";launcherSelectedIndex=-1;} function clearProjectPickerState() {}}
''')
            write("modules/widgets/projects/ProjectPickerView.qml", '''import QtQuick
Item {signal modeSwitchRequested(); function focusSearchInput() {forceActiveFocus();}}
''')
            # Hardware panels are counted stand-ins; exercise the real IslandBar
            # loaders, geometry, transitions and signal routing without device I/O.
            source = (ROOT / "modules/bar/layouts/IslandBar.qml").read_text()
            panels = re.findall(r"sourceComponent: (Island\w+) \{", source)
            signals = " ".join("signal " + name[0].lower() + name[1:] + "();" for name in sorted(set(re.findall(r"on(\w+):", source))) if name.startswith("Open") or name in ("BackRequested", "ActionTriggered"))
            for name in set(panels):
                write(f"modules/bar/island/{name}.qml", "import QtQuick\nimport Quickshell\nItem {implicitHeight: 240; property ShellScreen screen; " + signals + "}")
            for name in ("IslandStatusIcons", "IslandOsdBanner", "IslandNotificationBanner"):
                write(f"modules/bar/island/{name}.qml", '''import QtQuick
Item {implicitHeight: 60; property Item bar; property string indicator; property real value; property bool muted; property QtObject activeNotif: null; signal dismissRequested();}
''')
            write("modules/bar/workspaces/RebosTaskbar.qml", "import QtQuick\nItem {property string screenName; property bool compact; property int maxVisible; property bool useStyledBackground; property bool fillHeight; property Item bar; property bool flat; property bool showBackground;}")
            config = package / "xdg/rebos_shell/config"
            config.mkdir(parents=True)
            for path in (ROOT / "assets/presets/rebos_shell Default").glob("*.json"):
                shutil.copy(path, config / path.name)
            write("shell.qml", '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.config
import qs.modules.bar.layouts
import qs.modules.widgets.launcher
import qs.modules.globals
ShellRoot {
 Window {visible: true; width: 900; height: 800
  IslandBar {id: island; screen: Quickshell.screens[0]}
  LauncherView {id: launcher; y: 400; width: 480; height: 368}
  TestCase {id: test; when: false
   function loaders(item) {let all=[]; for(const child of item.children??[]) {if(child.objectName.startsWith("island-content-")) all.push(child); all=all.concat(loaders(child));} return all;}
   function test_release() {
    tryCompare(Config,"initialLoadComplete",true,5000);
    Config.theme.animDuration=180;
    const hosts=[...new Set(loaders(island))];
    
    compare(hosts.length,14,"all expandable content has a lazy host");
    for(const host of hosts) compare(host.item,null,"closed content is absent");
    for(const mode of ["dashboard","power","sound","mic","wifi","bluetooth","stats","alerts","wallpapers","battery","weather","media","calendar","apps","projects"]) {
     island.expand(mode);
     tryVerify(()=>hosts.filter(h=>h.item!==null).length===1,600);
     verify(island.targetHeight>0,"content supplies geometry");
     wait(200);
     island.collapse();
     // Content survives exit, and reversal restores a usable panel.
     verify(hosts.some(h=>h.item!==null));
     wait(20); island.expand(mode); wait(220);
     verify(hosts.some(h=>h.item!==null));
     island.collapse();
     tryVerify(()=>hosts.every(h=>h.item===null),600);
    }
    Config.theme.animDuration=0;
    island.expand("calendar"); verify(hosts.some(h=>h.item!==null));
    island.collapse(); tryVerify(()=>hosts.every(h=>h.item===null),100);
    GlobalStates.launcherMode="apps";
    launcher.visible=true;
    const search=findChild(launcher,"launcher-search");
    const results=findChild(launcher,"launcher-results");
    tryCompare(results,"count",15,1000);
    GlobalStates.launcherSelectedIndex=-1;
    search.focusInput();
    keyClick(Qt.Key_Down); compare(GlobalStates.launcherSelectedIndex,0); compare(results.currentIndex,0);
    keyClick(Qt.Key_Down); compare(GlobalStates.launcherSelectedIndex,1); compare(results.currentIndex,1);
    keyClick(Qt.Key_Up); compare(GlobalStates.launcherSelectedIndex,0); compare(results.currentIndex,0);
    keyClick(Qt.Key_Up); compare(GlobalStates.launcherSelectedIndex,-1); compare(results.currentIndex,-1);
    search.text="app"; tryCompare(results,"count",3); compare(results.currentIndex,0);
    keyClick(Qt.Key_End); compare(results.currentIndex,2);
    search.text="none"; tryCompare(results,"count",0); compare(GlobalStates.launcherSelectedIndex,-1);
    search.text=""; tryCompare(results,"count",15); compare(results.currentIndex,-1);
    keyClick(Qt.Key_Down); compare(results.currentIndex,0);
    console.log("RELEASE_RESOURCES_PASS"); Qt.quit();
   }
  }
  Timer {interval: 600; running: true; onTriggered: {try {test.test_release();} catch(e) {console.error(e);Qt.exit(1);}}}
  Timer {interval: 25000; running: true; onTriggered: Qt.exit(1)}
 }
}''')
            runtime = package / "runtime"
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QPA_PLATFORMTHEME="", XDG_CONFIG_HOME=str(package / "xdg"), XDG_CACHE_HOME=str(package / "cache"))
            result = subprocess.run(["qs", "-p", str(package), "--no-color"], env=env, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("RELEASE_RESOURCES_PASS", output)
            for error in ("TypeError:", "ReferenceError:", "Binding loop", "Cannot assign", "Unable to assign"):
                self.assertNotIn(error, output)


if __name__ == "__main__":
    unittest.main()
