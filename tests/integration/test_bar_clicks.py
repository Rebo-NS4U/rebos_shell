"""Exercise bar menu/shortcut mappings with real offscreen pointer events."""
from pathlib import Path
import tempfile,shutil,os,subprocess
src=Path(__file__).resolve().parents[2]
import unittest

@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class BarClicksTest(unittest.TestCase):
    def test_menu_and_shortcut_buttons(self):
        with tempfile.TemporaryDirectory(prefix='bar-clicks-') as d:
         p=Path(d)
         def write(name,text):
          f=p/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text)
         for f in ['modules/bar/island/IslandStatusIcons.qml','modules/components/ScrollStepHandler.qml']:
          dest=p/f;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy(src/f,dest)
         write('modules/bar/BarSymbol.qml','import QtQuick\nItem {property string symbol;property real size:18;property color color;implicitWidth:size;implicitHeight:size}')
         write('modules/theme/Icons.qml','pragma Singleton\nimport QtQuick\nQtObject {property string speakerSlash: "x";property string speakerNone: "0";property string speakerLow: "1";property string speakerHigh: "2";}')
         write('modules/bar/BarAppearance.qml','pragma Singleton\nimport QtQuick\nQtObject {readonly property color foregroundColor: "white"}')
         write('config/Config.qml','pragma Singleton\nimport QtQuick\nQtObject {property int animDuration: 0}')
         write('modules/theme/Colors.qml','pragma Singleton\nimport QtQuick\nQtObject {property color primary: "cyan"; property color overBackground: "white"; property color overSurfaceVariant: "gray"; property color error: "red";}')
         write('modules/theme/Styling.qml','pragma Singleton\nimport QtQuick\nQtObject {function radius(n) {return 10;}}')
         write('modules/components/StyledRect.qml','import QtQuick\nRectangle {property string variant: ""}')
         write('modules/components/StyledToolTip.qml','import QtQuick\nItem {property bool show: false;property string tooltipText: "";property string description: "";}')
         for icon,props in [('DynamicSunIcon','property real value: 0'),('DynamicVolumeIcon','property real value: 0;property bool muted: false'),('DynamicBatteryIcon','property int percent: 0;property bool charging: false')]:
          write('modules/components/'+icon+'.qml','import QtQuick\nItem {property int size: 18;property color color;property bool animated: false;'+props+'}')
         write('modules/services/Audio.qml','pragma Singleton\nimport QtQuick\nQtObject {property QtObject sink: QtObject {property QtObject audio: QtObject {property real volume: 0.4;property bool muted: false}}}')
         write('modules/services/Brightness.qml','pragma Singleton\nimport QtQuick\nQtObject {property bool syncBrightness: false;function getMonitorForScreen(s) {return null;}}')
         write('modules/services/Battery.qml','pragma Singleton\nimport QtQuick\nQtObject {property bool available: false;property int percent: 70;property bool charging: false}')
         write('modules/services/NightLightService.qml','pragma Singleton\nimport QtQuick\nQtObject {property bool active: false;function toggle() {active = !active;}}')
         write('shell.qml','''import QtQuick
        import QtQuick.Window
        import QtTest
        import Quickshell
        import qs.modules.bar.island
        import qs.modules.services
        ShellRoot {
         Window {id: win;visible:true;width:320;height:100
          Item {id: bar;property int islandHeight:36;property QtObject screen: QtObject {};property string opened:"";function expand(mode) {opened=mode;}}
          IslandStatusIcons {id: icons;bar:bar}
          TestCase {id: test;name:"clicks";when:windowShown
           function find(item,name) {if(item.objectName===name)return item;for(const c of item.children??[]){const f=find(c,name);if(f)return f;}return null;}
           function test_actions() {
            const volume=find(icons,"bar-volume");verify(volume!==null);
            mouseClick(volume,volume.width/2,volume.height/2,Qt.LeftButton);
            compare(bar.opened,"sound");compare(Audio.sink.audio.muted,false);
            bar.opened="";
            mouseClick(volume,volume.width/2,volume.height/2,Qt.RightButton);
            compare(Audio.sink.audio.muted,true);compare(bar.opened,"");
            const brightness=find(icons,"bar-brightness");
            mouseClick(brightness,brightness.width/2,brightness.height/2,Qt.LeftButton);
            compare(bar.opened,"dashboard");compare(NightLightService.active,false);
            mouseClick(brightness,brightness.width/2,brightness.height/2,Qt.RightButton);
            compare(NightLightService.active,true);
            console.log("PASS left-click menus and right-click shortcuts through real pointer events");
            Qt.quit();
           }
          }
         }
         Timer {interval:200;running:true;onTriggered:test.test_actions()}
         Timer {interval:4000;running:true;onTriggered:Qt.exit(1)}
        }''')
         runtime=p/'runtime';runtime.mkdir(mode=0o700)
         r=subprocess.run(['qs','-p',str(p),'--no-color'],env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QPA_PLATFORMTHEME='',XDG_RUNTIME_DIR=str(runtime)),capture_output=True,text=True,timeout=7)
         output=r.stdout+r.stderr
         self.assertEqual(r.returncode, 0, output)
         self.assertIn("PASS left-click menus and right-click shortcuts", output)

if __name__ == "__main__":
    unittest.main()
