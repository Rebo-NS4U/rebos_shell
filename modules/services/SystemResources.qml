pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.globals
pragma ComponentBehavior: Bound

/**
 * System resource monitoring service
 * Optimized to be lightweight and avoid waking up dGPUs.
 */
Singleton {
    id: root

    property string detailMetric: ""
    property string detailTitle: ""
    property list<var> processes: []
    property list<string> gpuPciIds: []
    property var windowInfo: ({})
    property bool pickingWindow: false
    property string pickerOutput: ""
    property bool windowActionBusy: false
    property bool windowKilled: false
    property string windowActionMessage: ""
    property string windowActionOutput: ""

    function controlWindow(action: string) {
        if (windowActionBusy || pickingWindow || windowKilled || !windowInfo.window) return;
        const w = windowInfo.window;
        windowActionMessage = "";
        windowActionOutput = "";
        windowActionProcess.command = ["python3", Quickshell.shellDir + "/scripts/process_monitor.py", "--window-action",
            action, String(w.id), String(w.pid ?? 0), String(windowInfo.process?.start ?? "")];
        windowActionBusy = true;
        windowActionProcess.running = true;
    }

    Process {
        id: windowActionProcess
        stdout: StdioCollector { onStreamFinished: root.windowActionOutput = text }
        onExited: {
            try {
                const result = JSON.parse(root.windowActionOutput);
                root.windowActionMessage = result.error ?? result.message ?? "Action finished.";
                root.windowKilled = result.killed ?? false;
            } catch (e) { root.windowActionMessage = "Could not control this window."; }
            root.windowActionBusy = false;
        }
    }

    readonly property bool keepMonitorOpen: GlobalStates.systemMonitorOpen && (pickingWindow || detailMetric === "window")

    function showProcesses(metric: string, title: string) {
        detailTitle = title;
        detailMetric = metric;
    }

    function pickWindow() {
        if (pickingWindow || windowActionBusy) return;
        windowKilled = false;
        windowActionMessage = "";
        pickingWindow = true;
        windowInfo = ({});
        detailMetric = "window";
        detailTitle = "Window information";
        pickerOutput = "";
        pickerDelay.restart();
    }

    Timer {
        id: pickerDelay
        interval: 350
        onTriggered: windowPicker.running = true
    }

    Process {
        id: windowPicker
        command: ["python3", Quickshell.shellDir + "/scripts/process_monitor.py", "--pick-window"]
        stdout: StdioCollector { onStreamFinished: root.pickerOutput = text }
        onExited: {
            try { root.windowInfo = JSON.parse(root.pickerOutput); }
            catch (e) { root.windowInfo = ({error: "Could not read window information."}); }
            root.pickingWindow = false;
        }
    }

    Process {
        command: ["python3", Quickshell.shellDir + "/scripts/process_monitor.py"]
        running: GlobalStates.systemMonitorOpen && root.detailMetric !== "" && root.detailMetric !== "window"
        stdout: SplitParser {
            onRead: data => {
                try {
                    const rows = JSON.parse(data);
                    Qt.callLater(() => { root.processes = rows; });
                } catch (e) { console.warn("Process monitor: invalid sample"); }
            }
        }
    }

    // CPU metrics
    property real cpuUsage: 0.0
    property string cpuModel: ""
    property int cpuTemp: -1
    property real cpuFrequency: 0

    // RAM metrics
    property real ramUsage: 0.0
    property real ramTotal: 0
    property real ramUsed: 0
    property real ramAvailable: 0

    // GPU metrics
    property var gpuUsages: []
    property var gpuVendors: []
    property var gpuNames: []
    property var gpuDrivers: []
    property int gpuCount: 0
    property bool gpuDetected: false
    property var gpuTemps: []
    property var gpuVramUsed: []
    property var gpuVramTotal: []
    property var gpuClockMhz: []
    
    // Legacy single GPU properties
    property real gpuUsage: gpuUsages.length > 0 ? gpuUsages[0] : 0.0
    property string gpuVendor: gpuVendors.length > 0 ? gpuVendors[0] : "unknown"
    property int gpuTemp: gpuTemps.length > 0 ? gpuTemps[0] : -1

    // Disk metrics
    property var diskUsage: ({})
    property var diskUsed: ({})
    property var diskTotal: ({})
    property var diskTypes: ({})
    property var validDisks: []

    // Network throughput in bytes per second
    property real networkDownloadSpeed: 0
    property real networkUploadSpeed: 0

    // Update interval
    property int updateInterval: 1000

    // Unified monitor process.
    // Resource-efficient: only runs while the bar monitor popup is open.
    // Optimized GPU polling avoids waking dGPUs.
    property Process monitorProcess: Process {
        id: monitorProcess
        running: (GlobalStates.systemMonitorOpen || GlobalStates.islandStatsOpen) && root.validDisks.length > 0
        
        command: {
            let cmd = ["python3", Quickshell.shellDir + "/scripts/system_monitor.py", root.updateInterval.toString()];
            return cmd.concat(root.validDisks);
        }
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    const stats = JSON.parse(data);
                    
                    // Static info (received once at start)
                    if (stats.static) {
                        root.cpuModel = stats.static.cpu_model || root.cpuModel;
                        root.gpuNames = stats.static.gpu_names || [];
                        root.gpuPciIds = stats.static.gpu_pci_ids || [];
                        root.gpuVendors = stats.static.gpu_vendors || [];
                        root.gpuDrivers = stats.static.gpu_drivers || [];
                        root.gpuCount = stats.static.gpu_count || 0;
                        root.gpuDetected = root.gpuCount > 0;
                        root.diskTypes = stats.static.disk_types || {};
                        return;
                    }

                    // Update metrics
                    if (stats.cpu) {
                        root.cpuUsage = stats.cpu.usage;
                        root.cpuTemp = stats.cpu.temp;
                        root.cpuFrequency = stats.cpu.frequency || 0;
                    }
                    
                    if (stats.ram) {
                        root.ramUsage = stats.ram.usage;
                        root.ramTotal = stats.ram.total;
                        root.ramUsed = stats.ram.used;
                        root.ramAvailable = stats.ram.available;
                    }
                    
                    if (stats.disk) {
                        root.diskUsage = stats.disk.usage || {};
                        root.diskUsed = stats.disk.used || {};
                        root.diskTotal = stats.disk.total || {};
                    }

                    if (stats.network) {
                        root.networkDownloadSpeed = stats.network.download || 0;
                        root.networkUploadSpeed = stats.network.upload || 0;
                    }
                    
                    if (stats.gpu) {
                        root.gpuUsages = stats.gpu.usages;
                        root.gpuTemps = stats.gpu.temps;
                        root.gpuDrivers = stats.gpu.drivers || root.gpuDrivers;
                        root.gpuVramUsed = stats.gpu.vram_used || [];
                        root.gpuVramTotal = stats.gpu.vram_total || [];
                        root.gpuClockMhz = stats.gpu.clock_mhz || [];
                    }
                } catch (e) {
                    console.warn("SystemResources: Failed to parse monitor data: " + e);
                }
            }
        }
    }

    Component.onCompleted: validateDisks()

    Connections {
        target: Config.system
        function onDisksChanged() { root.validateDisks(); }
    }

    property bool configReady: Config.initialLoadComplete
    onConfigReadyChanged: if (configReady) validateDisks()

    onValidDisksChanged: if (monitorProcess.running) restartMonitor()
    onUpdateIntervalChanged: if (monitorProcess.running) restartMonitor()

    function restartMonitor() {
        monitorProcess.running = false;
        Qt.callLater(() => { monitorProcess.running = true; });
    }

    function validateDisks() {
        const configuredDisks = Config.system.disks || ["/"];
        let newValidDisks = [];
        for (let i = 0; i < configuredDisks.length; i++) {
            const disk = configuredDisks[i];
            if (disk && typeof disk === 'string' && disk.trim() !== '') {
                newValidDisks.push(disk.trim());
            }
        }
        if (newValidDisks.length === 0) newValidDisks = ["/"];
        validDisks = newValidDisks;
    }

}
