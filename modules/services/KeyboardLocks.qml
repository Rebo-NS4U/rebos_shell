pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool capsLock: false
    property bool numLock: false
    property bool scrollLock: false
    property string lastKey: "caps"
    property bool lastEnabled: false
    property bool toastVisible: false
    property string toastScreenName: ""
    property list<string> availableKeys: []
    readonly property string label: lastKey === "caps" ? "Caps Lock" : lastKey === "num" ? "Num Lock" : "Scroll Lock"
    readonly property string keycap: lastKey === "caps" ? "Aa" : lastKey === "num" ? "123" : "↕"
    readonly property string description: lastKey === "caps"
        ? (lastEnabled ? "Uppercase letters" : "Lowercase letters")
        : lastKey === "num" ? (lastEnabled ? "Number pad enabled" : "Navigation keys enabled")
        : (lastEnabled ? "Scrolling locked" : "Scrolling unlocked")

    signal lockChanged(string key, bool enabled)

    function acceptSnapshot(event) {
        const states = event?.states;
        if (!states || typeof states !== "object")
            return;
        availableKeys = Object.keys(states).filter(key => ["caps", "num", "scroll"].includes(key));
        capsLock = states.caps === true;
        numLock = states.num === true;
        scrollLock = states.scroll === true;
        for (const key of event.changed || []) {
            if (!availableKeys.includes(key))
                continue;
            lastKey = key;
            lastEnabled = states[key] === true;
            toastScreenName = NiriService.focusedMonitor?.name || Quickshell.screens[0]?.name || "";
            toastVisible = true;
            hideTimer.restart();
            lockChanged(key, lastEnabled);
        }
    }

    Timer {
        id: hideTimer
        interval: 1600
        onTriggered: root.toastVisible = false
    }

    Process {
        id: monitor
        command: ["python3", Qt.resolvedUrl("../../scripts/lock_key_monitor.py").toString().replace(/^file:\/\//, "")]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try { root.acceptSnapshot(JSON.parse(data)); }
                catch (error) { console.warn("Invalid keyboard lock state"); }
            }
        }
        onExited: {
            root.toastVisible = false;
            retryTimer.restart();
        }
    }

    Timer {
        id: retryTimer
        interval: 3000
        onTriggered: monitor.running = true
    }
}
