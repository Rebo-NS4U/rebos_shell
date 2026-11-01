import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string address: ""
    property string name: "Unknown"
    property string icon: "bluetooth"
    property bool paired: false
    property bool connected: false
    property bool trusted: false
    property int battery: -1
    property bool batteryAvailable: battery >= 0
    property bool connecting: false
    property real lastInfoRefresh: 0
    property bool infoRefreshing: false

    signal infoUpdated()

    function connect() {
        if (connecting) return;
        connecting = true;
        const pairing = paired ? Promise.resolve() : BluetoothService.pairDevice(address);
        return pairing.then(() => {
            return trusted ? Promise.resolve() : BluetoothService.trustDevice(address);
        }).then(() => BluetoothService.connectDevice(address)).then(() => {
            connecting = false;
            updateInfo();
        }, error => {
            // The shared service exposes the failure in both Bluetooth panels.
            connecting = false;
            updateInfo();
        });
    }

    function updateInfo() {
        if (infoRefreshing) return;
        infoRefreshing = true;
        lastInfoRefresh = Date.now();
        return BluetoothService.runAsync(["bluetoothctl", "info", address]).then(text => {
            infoRefreshing = false;
            Qt.callLater(() => {
                root.battery = -1;
                const lines = text.split("\n");
                for (const line of lines) {
                    const trimmed = line.trim();
                    if (trimmed.startsWith("Paired:")) {
                        root.paired = trimmed.includes("yes");
                    } else if (trimmed.startsWith("Connected:")) {
                        root.connected = trimmed.includes("yes");
                        if (root.connected) root.connecting = false;
                    } else if (trimmed.startsWith("Trusted:")) {
                        root.trusted = trimmed.includes("yes");
                    } else if (trimmed.startsWith("Icon:")) {
                        root.icon = trimmed.split(":")[1]?.trim() || "bluetooth";
                    } else if (trimmed.startsWith("Battery Percentage:")) {
                        const match = trimmed.match(/\((\d+)\)/);
                        if (match) {
                            root.battery = parseInt(match[1], 10);
                        }
                    }
                }
                root.infoUpdated();
            });
        }).catch(e => {
            infoRefreshing = false;
            console.error(`Failed to get info for ${address}: ${e}`);
        });
    }

    function disconnect() {
        BluetoothService.disconnectDevice(address).catch(error => {});
    }

    function pair() {
        BluetoothService.pairDevice(address).catch(error => {});
    }

    function trust() {
        BluetoothService.trustDevice(address).catch(error => {});
    }

    function forget() {
        BluetoothService.removeDevice(address).catch(error => {});
    }
}
