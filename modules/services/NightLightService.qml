pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property int minTemperature: 2500
    readonly property int maxTemperature: 6500
    property int temperature: 4500
    property int currentTemperature: maxTemperature
    property bool active: false
    property bool desiredActive: false
    property bool available: false
    property string lastError: ""
    property bool lastWriteFailed: false
    property bool restored: false
    property int pendingTemperature: -1
    readonly property real normalizedTemperature: (temperature - minTemperature) / (maxTemperature - minTemperature)

    function clampTemperature(value) {
        return Math.max(minTemperature, Math.min(maxTemperature, Math.round(value / 100) * 100));
    }

    function setTemperature(value) {
        root.temperature = clampTemperature(value);
        if (StateService.initialized)
            StateService.set("nightLightTemperature", root.temperature);
        if (root.desiredActive)
            applyTemperature(root.temperature);
    }

    function setTemperatureFromNormalized(value) {
        setTemperature(minTemperature + Math.max(0, Math.min(1, value)) * (maxTemperature - minTemperature));
    }

    function applyTemperature(value) {
        const next = clampTemperature(value);
        if (setTemperatureProcess.running || queryTemperatureProcess.running) {
            root.pendingTemperature = next;
            return;
        }
        root.pendingTemperature = -1;
        setTemperatureProcess.command = ["busctl", "--user", "set-property", "rs.wl-gammarelay", "/", "rs.wl.gammarelay", "Temperature", "q", String(next)];
        setTemperatureProcess.running = true;
    }

    function toggle() {
        root.desiredActive = !root.desiredActive;
        applyTemperature(root.desiredActive ? root.temperature : maxTemperature);
    }

    function syncState() {
        if (!queryTemperatureProcess.running && !setTemperatureProcess.running)
            queryTemperatureProcess.running = true;
    }

    function continuePending() {
        if (root.pendingTemperature >= 0) {
            const next = root.pendingTemperature;
            root.pendingTemperature = -1;
            Qt.callLater(() => root.applyTemperature(next));
        } else {
            Qt.callLater(root.syncState);
        }
    }

    function restoreState() {
        if (restored || !StateService.initialized)
            return;
        restored = true;
        temperature = clampTemperature(StateService.get("nightLightTemperature", temperature));
        desiredActive = StateService.get("nightLight", false);
        applyTemperature(desiredActive ? temperature : maxTemperature);
    }

    Process {
        id: queryTemperatureProcess
        command: ["busctl", "--user", "get-property", "rs.wl-gammarelay", "/", "rs.wl.gammarelay", "Temperature"]
        stdout: StdioCollector { id: queryOutput }
        stderr: StdioCollector { id: queryError }
        onExited: exitCode => {
            const match = queryOutput.text.match(/^q\s+(\d+)\s*$/);
            root.available = exitCode === 0 && match !== null;
            if (root.available) {
                root.currentTemperature = Number(match[1]);
                root.active = root.currentTemperature < root.maxTemperature - 50;
                if (!root.lastWriteFailed)
                    root.lastError = "";
                if (root.pendingTemperature < 0) {
                    root.desiredActive = root.active;
                    if (StateService.initialized)
                        StateService.set("nightLight", root.active);
                }
            } else {
                root.active = false;
                root.lastError = queryError.text.trim() || "Night Light backend is unavailable";
            }
            if (root.pendingTemperature >= 0)
                root.continuePending();
        }
    }

    Process {
        id: setTemperatureProcess
        stderr: StdioCollector { id: setError }
        onExited: exitCode => {
            root.lastWriteFailed = exitCode !== 0;
            if (exitCode !== 0) {
                root.lastError = setError.text.trim() || "Could not change display temperature";
                root.available = false;
                root.desiredActive = root.active;
                console.warn("Night Light:", root.lastError);
            } else {
                root.lastError = "";
            }
            root.continuePending();
        }
    }

    Connections {
        target: StateService
        function onStateLoaded() { root.restoreState(); }
    }

    Timer {
        interval: 10000
        running: root.restored
        repeat: true
        onTriggered: root.syncState()
    }

    Component.onCompleted: Qt.callLater(root.restoreState)
}
