"""Exercise the clock dashboard with isolated services and real pointer events."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which('qs'), 'Quickshell required')
class ClockDashboardTest(unittest.TestCase):
    def test_layout_and_actions(self):
        with tempfile.TemporaryDirectory(prefix='clock-dashboard-') as directory:
            root = Path(directory)
            shutil.copytree(ROOT / 'modules', root / 'modules')
            for name in ['config', 'assets', 'version']:
                (root / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())
            fonts = Path.home() / '.local/share/fonts'
            if fonts.is_dir():
                target = root / '.local/share/fonts'
                target.parent.mkdir(parents=True)
                target.symlink_to(fonts, target_is_directory=True)
            colors = (ROOT / 'modules/theme/Colors.qml').read_text()
            names = json.loads(re.search(r'availableColorNames: (\[.*?\])', colors).group(1))
            (root / 'modules/theme/Colors.qml').write_text(
                'pragma Singleton\nimport QtQuick\nQtObject {property list<string> availableColorNames: '
                + json.dumps(names) + ';' + ''.join('property color ' + name + ': "'
                + ('#dddddd' if name.startswith('over') else '#72bdcc' if name.startswith('primary') else '#202a2d')
                + '";' for name in names) + '}')
            stubs = {
                'Audio': '''property QtObject sink: QtObject {property QtObject audio: QtObject {property real volume: 0.4; property bool muted: false}}
property QtObject source: QtObject {property QtObject audio: QtObject {property real volume: 0.5; property bool muted: false}}
function toggleMute() {sink.audio.muted=!sink.audio.muted;} function toggleMicMute() {source.audio.muted=!source.audio.muted;}
function incrementVolume() {sink.audio.volume+=0.05;} function decrementVolume() {sink.audio.volume-=0.05;} function setMicVolume(v) {source.audio.volume=v;}''',
                'NetworkService': '''property bool wifiEnabled: true; property bool wifiConnected: true; property bool wifiConnecting: false;
property bool vpnConnected: false; property string vpnName: ""; property string activeSsid: "A long network name for layout verification";
property int networkStrength: 90; function wifiIconForStrength(v) {return "W";} function update() {} function toggleWifi() {wifiEnabled=!wifiEnabled;}''',
                'BluetoothService': '''property bool enabled: true; property bool connected: true; property string firstConnectedDeviceName: "Long Bluetooth device name";
property list<var> friendlyDeviceList: []; function updateStatus() {} function toggle() {enabled=!enabled;}''',
                'Brightness': '''property bool syncBrightness: false; property QtObject monitor: QtObject {property bool ready: true; property real brightness: 0.5; function setBrightness(v) {brightness=v;}}
property list<QtObject> monitors: [monitor]; function getMonitorForScreen(s) {return monitor;}''',
                'Battery': '''property bool available: true; property int percentage: 72; property bool isPluggedIn: false;
function statusColor() {return "cyan";} function getBatteryIcon() {return "B";}''',
                'NightLightService': '''property bool active: false; property bool desiredActive: active; property real normalizedTemperature: 0.5; property int temperature: 4500;
function toggle() {active=!active;} function setTemperature(v) {temperature=v;}''',
                'Notifications': '''property bool silent: false; property list<string> appNameList: []; property var groupsByAppName: ({}); function toggleSilent() {silent=!silent;}''',
                'WeatherService': '''property bool dataAvailable: false; property string weatherSymbol: ""; property real currentTemp: 20; property int refreshCalls: 0; function updateWeather() {refreshCalls++;}''',
                'NiriService': 'property var focusedMonitor: null;',
                'MprisController': 'property QtObject activePlayer: null; property bool isPlaying: false; function previous() {} function next() {} function togglePlaying() {}',
                'Visibilities': 'function closeActiveBarPopup() {}',
                'FocusGrabManager': 'function clearTopGrab() {}',
            }
            for name, properties in stubs.items():
                (root / f'modules/services/{name}.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {' + properties + '}')
            (root / 'modules/globals/GlobalStates.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {property bool settingsWindowVisible: false; property QtObject wallpaperManager: null;}')
            (root / 'shell.qml').write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.config
import qs.modules.bar.island
import qs.modules.services
import qs.modules.globals
ShellRoot {
 Window {id: win; title: "Clock dashboard verification"; visible: true; width: 420; height: 760; color: "#131b1e"
  IslandDashboard {id: panel; width: parent.width; height: implicitHeight
   property string opened: ""
   onOpenCalendar: opened="calendar"
   onOpenWeather: opened="weather"
   onOpenAlerts: opened="alerts"
   onOpenPower: opened="power"
   onOpenWifi: opened="wifi"
   onOpenBluetooth: opened="bluetooth"
   onOpenSound: opened="sound"
   onOpenMic: opened="mic"
   onOpenBattery: opened="battery"
   onOpenStats: opened="stats"
   onOpenWallpapers: opened="wallpapers"
   onOpenMedia: opened="media"
  }
  TestCase {id: test; when: false
   function click(name, button) {
    const item=findChild(panel,name); verify(item!==null,name);
    verify(item.width>0 && item.height>0,name+" has a target");
    mouseClick(item,item.width/2,item.height/2,button || Qt.LeftButton);
   }
   function test_dashboard() {
    tryCompare(Config,"initialLoadComplete",true,5000);
    Config.theme.shellStyle="dithered";
    Notifications.appNameList=["Test"];
    Notifications.groupsByAppName=({Test:{notifications:new Array(120)}});
    compare(panel.alertsCount,120);
    wait(200);
    for (const width of [420,360]) {
     win.width=width; wait(100);
     verify(panel.implicitHeight<720,"fits short desktop");
     panel.grabToImage(result => result.saveToFile(Qt.resolvedUrl("dashboard-"+width+".png").toString().replace("file://", "")));
     wait(150);
     for (const pair of [["Clock", "calendar"], ["Weather", "weather"], ["Alerts", "alerts"], ["Power", "power"], ["WifiMouse", "wifi"], ["BluetoothMouse", "bluetooth"], ["SoundGauge", "sound"], ["MicrophoneGauge", "mic"], ["BatteryGauge", "battery"], ["DoNotDisturbGauge", "alerts"], ["SystemGauge", "stats"], ["WallpapersGauge", "wallpapers"]]) {
      panel.opened=""; click("dashboard"+pair[0]); compare(panel.opened,pair[1]);
      const target=findChild(panel,"dashboard"+pair[0]);
      const point=target.mapToItem(panel,0,0);
      verify(point.x>=-1 && point.x+target.width<=panel.width+1,pair[0]+" fits width");
     }
    }
    // Card corners and captions forward the same actions as their icons.
    for (const pair of [[0,"sound"],[1,"mic"],[2,"battery"],[3,"alerts"],[4,"stats"],[5,"wallpapers"]]) {
     const card=findChild(panel,"dashboardShortcut"+pair[0]);
     panel.opened=""; mouseClick(card,3,3); compare(panel.opened,pair[1]);
     panel.opened=""; mouseClick(card,card.width/2,card.height-10); compare(panel.opened,pair[1]);
     const origin=card.mapToItem(panel,0,0);
     verify(origin.y+card.height<=panel.implicitHeight,"card fits height");
    }
    const soundCard=findChild(panel,"dashboardShortcut0");
    mouseClick(soundCard,3,3,Qt.RightButton); compare(Audio.sink.audio.muted,true);
    mouseClick(soundCard,3,3,Qt.RightButton); compare(Audio.sink.audio.muted,false);
    mouseWheel(soundCard,3,3,0,120); compare(Audio.sink.audio.volume,0.45);
    mouseWheel(soundCard,3,3,0,-120); compare(Audio.sink.audio.volume,0.4);
    // The longer 12-hour clock also stays clear of the weather target.
    Config.bar.use12hFormat=true;
    panel.currentDate=new Date(2026,9,29,12,59,0);
    wait(50);
    const clock=findChild(panel,"dashboardClock");
    const weather=findChild(panel,"dashboardWeather");
    const clockOrigin=clock.mapToItem(panel,0,0);
    const weatherOrigin=weather.mapToItem(panel,0,0);
    verify(clockOrigin.x+clock.width<weatherOrigin.x,"header targets do not overlap");
    panel.grabToImage(result => result.saveToFile(Qt.resolvedUrl("dashboard-12h.png").toString().replace("file://", "")));
    wait(150);
    Config.bar.use12hFormat=false;
    for (const pair of [["dashboardWifiIcon","wifi"],["dashboardBluetoothIcon","bluetooth"]]) {
     panel.opened=""; click(pair[0]); compare(panel.opened,pair[1]);
    }
    const media=findChild(panel,"dashboardMedia");
    panel.opened=""; mouseClick(media,50,30); compare(panel.opened,"media");
    click("dashboardWeather",Qt.RightButton); compare(WeatherService.refreshCalls,1);
    click("dashboardNightLight"); compare(NightLightService.active,true);
    const brightness=findChild(panel,"dashboardBrightness");
    mouseClick(brightness,brightness.width*0.75,brightness.height/2);
    verify(Brightness.monitor.brightness>0.5,"brightness drag reaches monitor");
    const volume=findChild(panel,"dashboardSoundGauge");
    mouseWheel(volume,volume.width/2,volume.height/2,0,120);
    compare(Audio.sink.audio.volume,0.45);
    panel.opened=""; click("dashboardWifiMouse",Qt.RightButton); compare(NetworkService.wifiEnabled,false); compare(panel.opened,"");
    click("dashboardBluetoothMouse",Qt.RightButton); compare(BluetoothService.enabled,false);
    click("dashboardSoundGauge",Qt.RightButton); compare(Audio.sink.audio.muted,true);
    click("dashboardMicrophoneGauge",Qt.RightButton); compare(Audio.source.audio.muted,true);
    click("dashboardDoNotDisturbGauge",Qt.RightButton); compare(Notifications.silent,true);
    click("dashboardSettings"); compare(GlobalStates.settingsWindowVisible,true);
    WeatherService.dataAvailable=true;
    Battery.available=false;
    NetworkService.activeSsid="";
    wait(100);
    const preview=Qt.resolvedUrl("dashboard.png").toString().replace("file://", "");
    panel.grabToImage(result => result.saveToFile(preview));
    wait(200);
    console.log("CLOCK_DASHBOARD_PASS"); Qt.quit();
   }
  }
  Timer {interval: 700; running: true; onTriggered: {try {test.test_dashboard();} catch(error) {console.error(error); Qt.exit(1);}}}
  Timer {interval: 12000; running: true; onTriggered: Qt.exit(1)}
 }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            preview = os.environ.get('CLOCK_PREVIEW_DIR')
            environment = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / '.config'),
                               XDG_CACHE_HOME=str(root / '.cache'), XDG_RUNTIME_DIR=str(runtime),
                               QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                               DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent',
                               DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent')
            if preview:
                environment.update(QT_QPA_PLATFORM='wayland', XDG_RUNTIME_DIR=os.environ['XDG_RUNTIME_DIR'])
            result = subprocess.run(['qs', '-p', str(root), '--no-color'], env=environment,
                                    capture_output=True, text=True, timeout=18)
            output = result.stdout + result.stderr
            if preview:
                Path(preview).mkdir(parents=True, exist_ok=True)
                for image in root.glob('dashboard*.png'):
                    shutil.copy(image, Path(preview) / image.name)
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('CLOCK_DASHBOARD_PASS', output)
            for error in ['FAIL!', 'TypeError', 'ReferenceError', 'Binding loop']:
                self.assertNotIn(error, output)


if __name__ == '__main__':
    unittest.main()
