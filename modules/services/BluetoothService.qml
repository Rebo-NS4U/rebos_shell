pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals

Singleton {
    id: root

    property bool enabled: false
    readonly property bool discovering: scanProcess.running
    property bool connected: false
    property int connectedDevices: 0
    property string firstConnectedDeviceName: ""
    
    readonly property list<BluetoothDevice> devices: []
    
    // Cached sorted device list - only updates when devices change
    property list<BluetoothDevice> friendlyDeviceList: []

    // Incremental row changes preserve delegates and the ListView viewport.
    property alias deviceModel: deviceListModel
    ListModel {
        id: deviceListModel
        dynamicRoles: true
    }
    
    // Queue for batching updateInfo calls
    property list<BluetoothDevice> pendingInfoUpdates: []
    property bool isProcessingInfoQueue: false
    readonly property bool isUpdating: pendingActions > 0
    property int pendingActions: 0
    property string lastError: ""
    property string pairingAddress: ""
    property string pairingCode: ""
    property int pairingEntered: 0
    readonly property string pairingDeviceName: {
        const device = devices.find(item => item.address === pairingAddress);
        return device ? device.name : "keyboard";
    }
    property bool wasEnabledBeforeSleep: false

    Connections {
        id: suspendConnections
        target: SuspendManager
        function onPreparingForSleep() {
            root.wasEnabledBeforeSleep = root.enabled;
            if (discovering) {
                root.stopDiscovery();
            }

            infoQueueTimer.stop();
            root.isProcessingInfoQueue = false;
        }
        function onWakingUp() {
            // Re-sync status after wake
            wakeSyncTimer.restart();

            // Restore state if it was enabled
            if (root.wasEnabledBeforeSleep) {
                root.setEnabled(true, false);
            }
        }
    }

    Timer {
        id: wakeSyncTimer
        interval: 3000
        repeat: false
        onTriggered: {
            root.updateStatus();
            if (root.enabled) {
                root.updateDevices();
            }
        }
    }

    function updateFriendlyList() {
        const sorted = [...devices].sort((a, b) => {
            // Connected devices first
            if (a.connected && !b.connected) return -1;
            if (!a.connected && b.connected) return 1;
            // Then paired devices
            if (a.paired && !b.paired) return -1;
            if (!a.paired && b.paired) return 1;
            // Then by name
            return (a.name || "").localeCompare(b.name || "");
        });
        if (sorted.length !== friendlyDeviceList.length || sorted.some((item, i) => item !== friendlyDeviceList[i]))
            friendlyDeviceList = sorted;

        for (let i = deviceListModel.count - 1; i >= 0; i--) {
            if (sorted.indexOf(deviceListModel.get(i).device) === -1)
                deviceListModel.remove(i);
        }
        for (let i = 0; i < sorted.length; i++) {
            if (i < deviceListModel.count && deviceListModel.get(i).device === sorted[i])
                continue;
            let existingIndex = -1;
            for (let j = i + 1; j < deviceListModel.count; j++) {
                if (deviceListModel.get(j).device === sorted[i]) {
                    existingIndex = j;
                    break;
                }
            }
            if (existingIndex >= 0)
                deviceListModel.move(existingIndex, i, 1);
            else
                deviceListModel.insert(i, { device: sorted[i] });
        }
    }

    function onDeviceInfoUpdated(): void {
        updateFriendlyList();
    }

    // Batch process info updates with delay between each
    function queueInfoUpdate(device: BluetoothDevice) {
        if (pendingInfoUpdates.indexOf(device) === -1) {
            pendingInfoUpdates.push(device);
        }
        if (!isProcessingInfoQueue) {
            processNextInfoUpdate();
        }
    }

    function processNextInfoUpdate() {
        if (pendingInfoUpdates.length === 0) {
            isProcessingInfoQueue = false;
            updateFriendlyList();
            return;
        }
        
        isProcessingInfoQueue = true;
        const device = pendingInfoUpdates.shift();
        if (device) {
            device.updateInfo();
        }
        // Process next after a small delay
        infoQueueTimer.restart();
    }

    Timer {
        id: infoQueueTimer
        interval: 50  // 50ms between each info request
        running: false
        repeat: false
        onTriggered: {
            if (!SuspendManager.isSuspending) {
                root.processNextInfoUpdate();
            }
        }
    }

    Component {
        id: asyncProcessComp
        Process {
            id: internalProc
            property var resolve
            property var reject
            property var onOutput
            property string buffer: ""
            property string errorBuffer: ""
            
            stdout: SplitParser {
                onRead: data => {
                    internalProc.buffer += data + "\n";
                    if (internalProc.onOutput) internalProc.onOutput(data);
                }
            }
            
            stderr: SplitParser {
                onRead: data => internalProc.errorBuffer += data + "\n"
            }
            
            onExited: (exitCode, exitStatus) => {
                if (exitCode === 0) resolve(buffer.trim());
                else reject(errorBuffer.trim() || buffer.trim() || `Process exited with code ${exitCode}`);
                destroy();
            }
        }
    }

    function runAsync(command, environment = {}, onOutput = null) {
        return new Promise((resolve, reject) => {
            const proc = asyncProcessComp.createObject(root, {
                command: command,
                environment: Object.assign({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" }, environment),
                resolve: resolve,
                reject: reject,
                onOutput: onOutput
            });
            proc.running = true;
        });
    }

    function runAction(command, onOutput = null): var {
        pendingActions++;
        lastError = "";
        return runAsync(command, {}, onOutput).then(result => {
            pendingActions--;
            updateDevices();
            return result;
        }, error => {
            pendingActions--;
            lastError = String(error);
            throw error;
        });
    }

    // Start discovery only after the adapter has finished powering on.
    function setEnabled(value: bool, scanAfterPowerOn: bool): void {
        if (SuspendManager.isSuspending || isUpdating) return;
        if (!value) stopDiscovery();
        // A software rfkill block must be cleared before BlueZ can power on.
        // Powering off stays within BlueZ so other radios are unaffected.
        const unblock = value
            ? runAction(["rfkill", "unblock", "bluetooth"])
            : Promise.resolve();
        unblock.then(() => runAction(["bluetoothctl", "power", value ? "on" : "off"])).then(() => {
            enabled = value;
            if (value && scanAfterPowerOn) startDiscovery();
        }).catch(error => {});
    }

    function toggle(): void {
        setEnabled(!enabled, false);
    }

    function startDiscovery(): void {
        if (!enabled || SuspendManager.isSuspending) return;
        if (scanProcess.running) return;
        lastError = "";
        scanProcess.errorBuffer = "";
        scanProcess.running = true;
    }

    function stopDiscovery(): void {
        // BlueZ discovery belongs to its requesting client. Ending that client
        // releases only our session, without interfering with other scanners.
        scanProcess.running = false;
    }

    Process {
        id: scanProcess
        command: ["bluetoothctl", "--timeout", "15", "scan", "on"]
        environment: ({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" })
        property string errorBuffer: ""
        stdout: SplitParser {
            onRead: data => {
                if (data.includes("Failed") || data.includes("not available"))
                    scanProcess.errorBuffer += data + "\n";
                if (data.includes("Device ")) root.updateDevices();
            }
        }
        stderr: SplitParser {
            onRead: data => scanProcess.errorBuffer += data + "\n"
        }
        onExited: (code, status) => {
            if (scanProcess.errorBuffer.trim())
                root.lastError = scanProcess.errorBuffer.trim();
            else if (code !== 0 && status === 0)
                root.lastError = "Bluetooth discovery failed (" + code + ")";
            root.updateDevices();
        }
    }

    function connectDevice(address: string): var {
        return runAction(["bluetoothctl", "connect", address]);
    }

    function disconnectDevice(address: string): var {
        return runAction(["bluetoothctl", "disconnect", address]);
    }

    function pairDevice(address: string): var {
        if (pairingAddress) return Promise.reject("Another device is already pairing");
        pairingAddress = address;
        pairingCode = "";
        pairingEntered = 0;
        return runAction(["python3", Qt.resolvedUrl("../../scripts/bluetooth_pair.py").toString().replace(/^file:\/\//, ""), address], data => {
            try {
                const event = JSON.parse(data);
                if (event.event === "keyboard-code") {
                    root.pairingCode = String(event.code);
                    root.pairingEntered = event.entered || 0;
                } else if (event.event === "clear-code") {
                    root.pairingCode = "";
                }
            } catch (error) { console.warn("Bluetooth pairing output:", data); }
        }).then(result => {
            root.clearPairingPrompt();
            return result;
        }, error => {
            root.clearPairingPrompt();
            throw error;
        });
    }

    function clearPairingPrompt() {
        pairingAddress = "";
        pairingCode = "";
        pairingEntered = 0;
    }

    function trustDevice(address: string): var {
        return runAction(["bluetoothctl", "trust", address]);
    }

    function removeDevice(address: string): var {
        return runAction(["bluetoothctl", "remove", address]);
    }

    property bool _isUpdatingProcess: false
    property bool _hasPendingUpdate: false

    Timer {
        id: updateDebouncer
        interval: 100
        repeat: false
        onTriggered: root.performUpdate()
    }

    function updateStatus() {
        // Continuous advertisements must not postpone the update indefinitely.
        if (!updateDebouncer.running) updateDebouncer.start();
    }

    function updateDevices() {
        updateStatus();
    }

    function performUpdate() {
        if (_isUpdatingProcess) {
            _hasPendingUpdate = true;
            return;
        }
        _isUpdatingProcess = true;
        _hasPendingUpdate = false;
        checkStatusProcess.buffer = "";
        checkStatusProcess.running = true;
    }

    // Live DBus signal monitor: instant response when devices connect/disconnect or adapter power changes
    Process {
        id: dbusMonitorProcess
        command: ["stdbuf", "-oL", "gdbus", "monitor", "--system", "-d", "org.bluez"]
        running: !SuspendManager.isSuspending
        stdout: SplitParser {
            onRead: (data) => {
                if (data && (data.includes("Connected") || data.includes("Powered") || data.includes("PropertiesChanged") || data.includes("InterfacesAdded") || data.includes("InterfacesRemoved"))) {
                    root.updateStatus();
                }
            }
        }
    }

    // D-Bus handles changes; retain a slower idle fallback.
    Timer {
        id: updateTimer
        interval: !dbusMonitorProcess.running || GlobalStates.dashboardOpen || root.discovering || root.isUpdating ? 2500 : 15000
        running: !SuspendManager.isSuspending
        repeat: true
        onTriggered: {
            root.updateStatus();
        }
    }

    // Unified single-process status and device extraction (atomic read in ~25ms)
    Process {
        id: checkStatusProcess
        command: ["bash", "-c", "bluetoothctl show | grep -q 'Powered: yes' && echo 'powered' || echo 'off'; echo '---'; bluetoothctl devices Connected; echo '---'; bluetoothctl devices"]
        running: false
        property string buffer: ""
        environment: ({
            LANG: "C.UTF-8",
            LC_ALL: "C.UTF-8"
        })
        stdout: SplitParser {
            onRead: (data) => {
                checkStatusProcess.buffer += data + "\n";
            }
        }
        onExited: (code) => {
            const text = checkStatusProcess.buffer.trim();
            checkStatusProcess.buffer = "";

            try {
                if (code !== 0 || !text)
                    return;

                const parts = text.split("---");
                const powerPart = (parts[0] || "").trim();
                root.enabled = (powerPart === "powered");

                if (!root.enabled) {
                    root.connected = false;
                    root.connectedDevices = 0;
                    root.firstConnectedDeviceName = "";
                    for (let i = 0; i < root.devices.length; i++) {
                        const dev = root.devices[i];
                        if (dev) dev.connected = false;
                    }
                    root.updateFriendlyList();
                    return;
                }

                // Part 1: Connected devices
                const connectedLines = parts.length > 1
                    ? parts[1].trim().split("\n").filter(l => l.startsWith("Device "))
                    : [];
                const connectedMacs = new Set();
                let firstConnectedName = "";

                for (let i = 0; i < connectedLines.length; i++) {
                    const devParts = connectedLines[i].split(" ");
                    if (devParts.length > 1) {
                        connectedMacs.add(devParts[1]);
                        if (!firstConnectedName) {
                            firstConnectedName = devParts.slice(2).join(" ") || "Connected";
                        }
                    }
                }

                root.connectedDevices = connectedMacs.size;
                root.connected = connectedMacs.size > 0;
                root.firstConnectedDeviceName = firstConnectedName;

                // Part 2: All paired/known devices
                const deviceLines = parts.length > 2
                    ? parts[2].trim().split("\n").filter(l => l.startsWith("Device "))
                    : [];
                const deviceDataList = [];

                for (let i = 0; i < deviceLines.length; i++) {
                    const line = deviceLines[i];
                    const partsDev = line.split(" ");
                    if (partsDev.length < 2) continue;
                    const addr = partsDev[1];
                    deviceDataList.push({
                        address: addr,
                        name: partsDev.slice(2).join(" ") || "Unknown",
                        connected: connectedMacs.has(addr)
                    });
                }

                const rDevices = root.devices;

                // 1. Remove gone devices
                for (let i = rDevices.length - 1; i >= 0; i--) {
                    const rd = rDevices[i];
                    if (!deviceDataList.find(d => d.address === rd.address)) {
                        root.pendingInfoUpdates = root.pendingInfoUpdates.filter(device => device !== rd);
                        rDevices.splice(i, 1);
                        rd.destroy();
                    }
                }

                // 2. Add or update devices
                for (let i = 0; i < deviceDataList.length; i++) {
                    const data = deviceDataList[i];
                    const existing = rDevices.find(d => d.address === data.address);
                    if (existing) {
                        if (existing.name !== data.name) {
                            existing.name = data.name;
                        }
                        const connectionChanged = existing.connected !== data.connected;
                        existing.connected = data.connected;
                        if (connectionChanged || (data.connected && Date.now() - existing.lastInfoRefresh >= 60000)) {
                            root.queueInfoUpdate(existing);
                        }
                    } else {
                        const newDevice = deviceComp.createObject(root, {
                            address: data.address,
                            name: data.name,
                            connected: data.connected
                        });
                        newDevice.infoUpdated.connect(root.onDeviceInfoUpdated);
                        rDevices.push(newDevice);
                        root.queueInfoUpdate(newDevice);
                    }
                }

                root.updateFriendlyList();
            } catch (e) {
                console.warn("BluetoothService: Error parsing bluetooth status:", e);
            } finally {
                root._isUpdatingProcess = false;
                if (root._hasPendingUpdate) {
                    root._hasPendingUpdate = false;
                    root.performUpdate();
                }
            }
        }
    }

    Component {
        id: deviceComp
        BluetoothDevice {}
    }

    Component.onCompleted: initialize()

    property bool _initialized: false

    function initialize() {
        if (_initialized) return;
        _initialized = true;
        updateStatus();
    }
}
