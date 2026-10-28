import QtQuick
import Quickshell
import qs.modules.services

ShellRoot {
    property int step: 0
    property BluetoothDevice pairedDevice
    property BluetoothDevice newDevice

    function check(condition, message) {
        if (!condition) {
            console.error("FAIL", message, "enabled", BluetoothService.enabled,
                          "scanning", BluetoothService.discovering, "error", BluetoothService.lastError);
            Qt.quit();
        }
    }

    Timer {
        interval: 400
        running: true
        repeat: true
        onTriggered: {
            step++;
            if (step === 1) {
                check(!BluetoothService.enabled, "initial power state");
                BluetoothService.setEnabled(true, true);
            } else if (step === 2) {
                check(BluetoothService.enabled && BluetoothService.discovering, "scan follows power-on and stays alive");
            } else if (step === 4) {
                check(!BluetoothService.discovering, "scan exit resets discovering");
                check(BluetoothService.devices.length === 2, "known and discovered devices listed");
                pairedDevice = BluetoothService.devices.find(d => d.name === "Headphones");
                newDevice = BluetoothService.devices.find(d => d.name === "Speaker");
                check(pairedDevice.paired && pairedDevice.trusted, "real paired/trusted metadata");
                check(!newDevice.paired && !newDevice.trusted, "discovered device is not paired");
                pairedDevice.connect();
            } else if (step === 6) {
                check(pairedDevice.connected && !pairedDevice.connecting, "trusted connection resolves");
                check(pairedDevice.battery === 0 && pairedDevice.batteryAvailable, "zero percent battery");
                check(BluetoothService.connectedDevices === 1, "connected summary refreshed");
                pairedDevice.disconnect();
                newDevice.connect();
            } else if (step === 8) {
                check(!pairedDevice.connected, "disconnect refreshed");
                check(newDevice.paired && newDevice.trusted && newDevice.connected,
                      "pair then trust then connect: " + newDevice.paired + "/" + newDevice.trusted + "/" + newDevice.connected);
                BluetoothService.connectDevice("FAIL").catch(error => {});
            } else if (step === 10) {
                check(!BluetoothService.isUpdating && BluetoothService.lastError.includes("test failure"), "failed action clears busy and reports error");
                newDevice.forget();
            } else if (step === 12) {
                check(BluetoothService.devices.length === 1, "forgotten device removed");
                BluetoothService.startDiscovery();
            } else if (step === 13) {
                BluetoothService.stopDiscovery();
            } else if (step === 14) {
                check(!BluetoothService.discovering, "scan cancellation clears state");
                console.log("PASS Bluetooth actions and discovery");
                Qt.quit();
            }
        }
    }
}
