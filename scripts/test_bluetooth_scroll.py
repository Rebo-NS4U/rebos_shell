"""Exercise the production Bluetooth list updater against a real Qt ListView."""
import os
from pathlib import Path
import re
import subprocess
import tempfile


source = (Path(__file__).resolve().parents[1] / "modules/services/BluetoothService.qml").read_text()
update = re.search(r"    function updateFriendlyList\(\) \{.*?\n    }", source, re.S)
assert update, "Bluetooth list updater missing"
pair_device = re.search(r"    function pairDevice\(.*?\n    }", source, re.S)
clear_pairing = re.search(r"    function clearPairingPrompt\(.*?\n    }", source, re.S)
assert pair_device and clear_pairing, "Bluetooth pairing handlers missing"
network = (Path(__file__).resolve().parents[1] / "modules/services/NetworkService.qml").read_text()
process = re.search(r"    Component \{\n        id: asyncProcessComp.*?\n    }", network, re.S)
run_async = re.search(r"    function runAsync\(.*?\n    }", network, re.S)
assert process and run_async, "Network process runner missing"

qml = r'''
import QtQuick
import QtTest

TestCase {
    id: root
    name: "BluetoothScroll"
    when: windowShown
    width: 400
    height: 240
    property var devices: []
    property var friendlyDeviceList: []
    property string pairingAddress: ""
    property string pairingCode: ""
    property int pairingEntered: 0
    property var outputHandler
    property var resolvePairing
    property var rejectPairing
    function runAction(command, onOutput) {
        outputHandler = onOutput;
        return new Promise((resolve, reject) => {
            resolvePairing = resolve;
            rejectPairing = reject;
        });
    }
    __PAIR_DEVICE__
    __CLEAR_PAIRING__
    ListModel { id: deviceListModel; dynamicRoles: true }
    Component {
        id: deviceFactory
        QtObject {
            property string name
            property bool connected: false
            property bool paired: false
        }
    }
    ListView {
        id: view
        anchors.fill: parent
        model: deviceListModel
        spacing: 6
        delegate: Item {
            required property var device
            width: 400
            height: 40
            property bool expanded: false
        }
    }
    __UPDATE__
    function addDevice(name) {
        const device = deviceFactory.createObject(root, {name: name});
        devices.push(device);
        updateFriendlyList();
        view.forceLayout();
        return device;
    }
    function test_scanPreservesViewport() {
        for (let i = 0; i < 40; i++)
            addDevice("Device " + String(i).padStart(2, "0"));
        view.positionViewAtIndex(20, ListView.Beginning);
        view.forceLayout();
        const row = view.itemAt(10, view.contentY + 10);
        verify(row !== null);
        const device = row.device;
        row.expanded = true;
        const offset = row.mapToItem(view, 0, 0).y;

        // Discoveries both before and after the visible rows must not reset them.
        addDevice("AAA new device");
        addDevice("ZZZ new device");
        wait(30);
        compare(row.device, device);
        compare(row.expanded, true);
        fuzzyCompare(row.mapToItem(view, 0, 0).y, offset, 1);
        compare(view.itemAt(10, view.contentY + 10), row);

        // A paired device changes sort position through a row move.
        devices[30].paired = true;
        updateFriendlyList();
        view.forceLayout();
        wait(30);
        compare(view.itemAt(10, view.contentY + 10), row);
        compare(row.expanded, true);

        const removed = devices.shift();
        updateFriendlyList();
        view.forceLayout();
        removed.destroy();
        wait(30);
        compare(view.itemAt(10, view.contentY + 10), row);
        compare(deviceListModel.count, devices.length);
        for (let i = 0; i < deviceListModel.count; i++)
            compare(deviceListModel.get(i).device, friendlyDeviceList[i]);
    }
    function test_pairingCodeStream() {
        let completed = false;
        pairDevice("AA:BB:CC:DD:EE:FF").then(() => { completed = true; });
        outputHandler('{"event":"keyboard-code","code":"000042","entered":0}');
        compare(pairingCode, "000042");
        outputHandler('{"event":"keyboard-code","code":"000042","entered":3}');
        compare(pairingEntered, 3);
        outputHandler('{"event":"clear-code"}');
        compare(pairingCode, "");
        resolvePairing("paired");
        tryVerify(() => completed);
        compare(pairingAddress, "");
        compare(pairingEntered, 0);

        let failed = false;
        pairDevice("AA:BB:CC:DD:EE:FF").catch(() => { failed = true; });
        outputHandler('{"event":"keyboard-code","code":"000042","entered":1}');
        rejectPairing("Timed out");
        tryVerify(() => failed);
        compare(pairingAddress, "");
        compare(pairingCode, "");
        compare(pairingEntered, 0);
    }
}
'''.replace("__UPDATE__", update.group(0)).replace("__PAIR_DEVICE__", pair_device.group(0)).replace("__CLEAR_PAIRING__", clear_pairing.group(0)).replace("__ASYNC_PROCESS__", process.group(0)).replace("__RUN_ASYNC__", run_async.group(0))

with tempfile.TemporaryDirectory(prefix="bluetooth-scroll-") as directory:
    test_file = Path(directory) / "tst_bluetooth_scroll.qml"
    test_file.write_text(qml)
    private_environment = {**os.environ, "QT_QPA_PLATFORM": "offscreen",
                           "QT_QPA_PLATFORMTHEME": "basic", "QT_QUICK_CONTROLS_STYLE": "Basic",
                           "WAYLAND_DISPLAY": "", "NIRI_SOCKET": ""}
    for variable in ("XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        path = Path(directory) / variable
        path.mkdir(mode=0o700)
        private_environment[variable] = str(path)
    result = subprocess.run(
        ["dbus-run-session", "--", "/usr/lib/qt6/bin/qmltestrunner", "-input", str(test_file)],
        env=private_environment,
        check=False,
    )
    if result.returncode:
        raise SystemExit(result.returncode)
    # Quickshell embeds its Io plugin, so exercise Process with its own runtime.
    process_test = Path(directory) / "shell.qml"
    process_test.write_text(r'''
import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    id: root
    __ASYNC_PROCESS__
    __RUN_ASYNC__
    Component.onCompleted: {
        runAsync(["python3", "-c", "import sys; print(sys.stdin.read(), end='')"], {}, 'fixture $ "quote"\n')
            .then(output => {
                console.log(output === 'fixture $ "quote"' ? "PASS_STDIN" : "FAIL_STDIN");
                Qt.quit();
            }, error => { console.log("FAIL_STDIN", error); Qt.quit(); });
    }
}
'''.replace("__ASYNC_PROCESS__", process.group(0)).replace("__RUN_ASYNC__", run_async.group(0)))
    result = subprocess.run(
        ["dbus-run-session", "--", "qs", "-p", str(process_test)],
        env=private_environment, capture_output=True, text=True, timeout=15,
    )
    output = result.stdout + result.stderr
    if result.returncode or "PASS_STDIN" not in output:
        print(output)
        raise SystemExit(1)
    print("PASS: NetworkService process sends password input through stdin")
