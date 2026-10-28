"""Load every Settings tab and exercise section cards without host services."""
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
class SettingsLayoutTest(unittest.TestCase):
    def test_tabs_cards_search_and_resizing(self):
        with tempfile.TemporaryDirectory(prefix='settings-layout-') as directory:
            root = Path(directory)
            shutil.copytree(ROOT / 'modules', root / 'modules')
            colors = (ROOT / 'modules/theme/Colors.qml').read_text()
            names = json.loads(re.search(r'availableColorNames: (\[.*?\])', colors).group(1))
            defaults = dict(re.findall(r'property color (\w+): "(#[0-9a-fA-F]{6})"', colors))
            (root / 'modules/theme/Colors.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {property list<string> availableColorNames: ' + json.dumps(names) + ';' + ''.join('property color ' + name + ': ' + json.dumps(defaults.get(name, '#cccccc')) + ';' for name in names) + 'property color warning: "#f0cc88"; property color success: "#88ccaa";}')
            stubs = {
                'globals/GlobalStates': 'property QtObject wallpaperManager: null; property int settingsCurrentTab: 0; property bool settingsNewWindowRuleRequested: false',
                'services/NiriService': 'property var focusedMonitor: null; property var lastExternalFocusedClient: null; property var rawOutputs: ({})',
                'services/NetworkService': 'property list<QtObject> friendlyWifiNetworks: []; property bool wifiConnecting: false; property bool wifiEnabled: false; property bool wifiScanning: false; property bool isUpdating: false; property string wifiStatus: "disabled"; property int toggleCalls: 0; function rescanWifi() {} function enableWifi(value) { toggleCalls++; wifiEnabled=value; wifiStatus=value ? "connected" : "disabled"; }',
                'services/BluetoothService': 'property list<QtObject> friendlyDeviceList: []; property bool enabled: false; property bool discovering: false; property bool isUpdating: false; property string lastError: ""; property int toggleCalls: 0; function updateDevices() {} function stopDiscovery() {} function setEnabled(value, discover) {toggleCalls++; enabled=value;} function startDiscovery() {}',
                'services/Audio': 'property QtObject sink: null; property QtObject source: null; property list<QtObject> inputDevices: []; property list<QtObject> outputDevices: []; property list<QtObject> inputAppNodes: []; property list<QtObject> outputAppNodes: []; property bool protectionEnabled: true; property bool protectionTriggered: false; function friendlyDeviceName(node) {return "Audio device";} function appNodeDisplayName(node) {return "App";}',
                'services/Ai': 'property QtObject activeSession: QtObject {property list<var> models: []; property string currentAgentId: ""; property bool sessionReady: false; property string currentSessionModelId: ""; property string currentModeId: "";}'
            }
            for name, properties in stubs.items():
                (root / ('modules/' + name + '.qml')).write_text('pragma Singleton\nimport QtQuick\nQtObject {' + properties + '}')
            for name in ['config', 'assets', 'version']:
                (root / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())
            scripts = root / 'scripts'
            scripts.mkdir()
            # Only read models are used; mutations must never be tested here.
            (scripts / 'display_settings.py').write_text('import json\nprint(json.dumps({"ok":True,"outputs":[]}))')
            shortcut = {'key': 'Super+Return', 'action': 'Open terminal', 'group': 'Desktop', 'editable': True}
            (scripts / 'list_keybindings.py').write_text('print(' + repr(json.dumps({'bindings': [shortcut], 'files': [], 'error': ''})) + ')')
            (scripts / 'window_rules.py').write_text('import json\nprint(json.dumps({"ok":True,"rules":[],"fingerprint":"test","path":""}))')
            binaries = root / 'bin'
            binaries.mkdir()
            outputs = {'TEST-1': {'make': 'Test', 'model': 'Monitor', 'current_mode': 0,
                       'modes': [{'width': 1920, 'height': 1080, 'refresh_rate': 60000, 'is_preferred': True}],
                       'logical': {'x': 0, 'y': 0, 'scale': 1, 'transform': 'normal'}}}
            niri = binaries / 'niri'
            niri.write_text('#!/usr/bin/env python3\nprint(' + repr(json.dumps(outputs)) + ')\n')
            niri.chmod(0o755)
            fonts = root / '.local/share/fonts'
            fonts.parent.mkdir(parents=True)
            if (Path.home() / '.local/share/fonts').is_dir():
                fonts.symlink_to(Path.home() / '.local/share/fonts', target_is_directory=True)
            (root / 'runtime').mkdir(mode=0o700)
            (root / 'shell.qml').write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.config
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.widgets.dashboard.controls
ShellRoot {
 Window {id: win; visible: true; width: 1100; height: 900
  StyledRect {id: page; anchors.fill: parent; variant: "bg"
   SettingsTab {id: tabs; anchors.fill: parent; anchors.margins: 16}
  }
  SettingsComboBox {id: choice; visible: false; x: 300; y: 180; width: 300; z: 20; model: ["First", "Second"]}
  SignalSpy {id: choiceActivated; target: choice; signalName: "activated"}
  TestCase {id: test; when: false
   function test_pages() {
    tryCompare(Config, "initialLoadComplete", true, 5000);
    const loader = findChild(tabs,"settings-panel-loader");
    verify(loader !== null);
    for (const section of [0,1,2,3,4,5,6,7,8,9]) {
     console.log("CHECK_TAB",section);
     GlobalStates.settingsCurrentTab=section;
     tryCompare(tabs,"currentSection",section);
     tryCompare(loader,"status",Loader.Ready,5000);
     verify(loader.item !== null,"Tab "+section+" loads");
     verify(loader.item.width > 0); verify(loader.item.height > 0);
     wait(100);
     console.log("LOADED_TAB",section,loader.source,loader.item.width);
     if (section === 0 || section === 1) {
      const service = section === 0 ? NetworkService : BluetoothService;
      console.log("TOGGLE_BEFORE",service.toggleCalls);
      compare(service.toggleCalls,0,"Loading Settings must not toggle a device");
      const toggle = findChild(loader.item,"settings-page-toggle");
      verify(toggle !== null);
      toggle.forceActiveFocus(); keyClick(Qt.Key_Space);
      console.log("TOGGLE_AFTER",service.toggleCalls);
      compare(service.toggleCalls,1,"Keyboard switch activation reaches the service");
     }
     if (section === 4 || section === 5 || section === 6) {
      const ids = section === 4 ? ["blur","motion","general","shadow","colors","variants"] : section === 5 ? ["weather","performance","system"] : ["bar","sidebar","lockscreen","system"];
      for (const id of ids) {
       console.log("CHECK_CARD",section,id);
       const card=findChild(loader.item,"settings-section-"+id);
       verify(card !== null); verify(card.description.length > 0);
       card.forceActiveFocus(); keyClick(Qt.Key_Space);
       tryCompare(loader.item,"currentSection",id);
       wait(50);
       if (section === 4 && id === "motion" && Quickshell.env("SETTINGS_PREVIEW_DIR")) {
        wait(250);
        page.grabToImage(function(result) {result.saveToFile(Quickshell.env("SETTINGS_PREVIEW_DIR")+"/appearance-motion.png");});
        wait(100);
       }
       loader.item.currentSection="";
      }
     }
     if (section === 7) {
      tryVerify(function() {return loader.item.bindings.length === 1;},1000);
      compare(loader.item.errorMessage,"");
      loader.item.beginEdit(loader.item.bindings[0]);
      const editor=findChild(loader.item,"shortcut-editor-input");
      verify(editor !== null); compare(editor.text,"Super+Return");
      loader.item.editingBinding=null;
     }
     if (section === 8) {
      loader.item.newRule();
      tryCompare(loader.item.editor,"visible",true);
      const field=findChild(loader.item.editor,"rule-app-input");
      verify(field !== null); verify(field.visible);
      loader.item.editor.close();
     }
     if (Quickshell.env("SETTINGS_PREVIEW_DIR")) {
      wait(250);
      page.grabToImage(function(result) { result.saveToFile(Quickshell.env("SETTINGS_PREVIEW_DIR")+"/settings-"+section+".png"); });
      wait(100);
     }
     win.width=700; wait(50);
     verify(loader.item.width > 0,"Tab stays visible in narrow windows");
     win.width=1100;
    }
    // Search should use the new plain names and still dispatch subsections.
    console.log("CHECK_SEARCH");
    tabs.searchQuery="Theme style"; wait(200);
    compare(tabs.currentSection,4);
    tryCompare(loader,"status",Loader.Ready,5000);
    tryCompare(loader.item,"currentSection","style");
    tabs.searchQuery="";
    tabs.searchQuery="Motion"; wait(200);
    compare(tabs.currentSection,4);
    tryCompare(loader.item,"currentSection","motion");
    tabs.searchQuery="";
    // Check both the string and object models used by Display and rule dialogs.
    choice.visible=true;
    for (const objects of [false,true]) {
     choice.model=objects ? [{label:"First"},{label:"Second"}] : ["First","Second"];
     choice.textRole=objects ? "label" : "";
     choice.currentIndex=0;
     choiceActivated.clear();
     choice.popup.open();
     tryVerify(function() {return choice.popup.contentItem.itemAtIndex(1) !== null;},1000);
     const option=choice.popup.contentItem.itemAtIndex(1);
     mouseClick(option,option.width/2,option.height/2);
     tryCompare(choice,"currentIndex",1);
     compare(choiceActivated.count,1);
     compare(choice.displayText,"Second");
    }
    console.log("SETTINGS_LAYOUT_PASS"); Qt.quit();
   }
  }
  Timer {interval: 700; running: true; onTriggered: { try {test.test_pages();} catch(error) {console.error("Settings check failed",error); Qt.exit(1);} }}
  Timer {interval: 25000; running: true; onTriggered: Qt.exit(1)}
 }
}''')
            platform = 'wayland' if os.environ.get('SETTINGS_PREVIEW_DIR') else 'offscreen'
            environment = dict(os.environ, HOME=str(root), PATH=str(binaries) + os.pathsep + os.environ['PATH'], XDG_CONFIG_HOME=str(root / '.config'),
                               XDG_CACHE_HOME=str(root / '.cache'),
                               XDG_RUNTIME_DIR=os.environ['XDG_RUNTIME_DIR'] if platform == 'wayland' else str(root / 'runtime'),
                               QT_QPA_PLATFORM=platform, QT_QPA_PLATFORMTHEME='',
                               DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent',
                               DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent')
            result = subprocess.run(['qs', '-p', str(root), '--no-color'], env=environment,
                                    capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SETTINGS_LAYOUT_PASS', output)
            self.assertNotIn('FAIL!', output)
            self.assertNotIn('TypeError', output)
            self.assertNotIn('Binding loop', output)


if __name__ == '__main__':
    unittest.main()
