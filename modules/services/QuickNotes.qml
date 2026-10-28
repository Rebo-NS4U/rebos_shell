pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/Documents/Quick Notes.md"
    property string text: ""
    property string screenName: ""
    property bool visible: false
    property bool ready: false
    property bool dirty: false
    property bool saving: false
    property string pendingText: ""
    property string error: ""

    function toggle() {
        if (visible) {
            close();
            return;
        }
        screenName = NiriService.focusedMonitor?.name || Quickshell.screens[0]?.name || "";
        visible = true;
    }

    function close() {
        save();
        visible = false;
    }

    function edit(value: string) {
        if (!ready || text === value)
            return;
        text = value;
        dirty = true;
        debounce.restart();
    }

    function save() {
        debounce.stop();
        if (!ready || !dirty || saving)
            return;
        error = "";
        saving = true;
        pendingText = text;
        file.setText(pendingText);
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: root.save()
    }

    FileView {
        id: file
        path: root.path
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (!root.ready) {
                root.text = file.text();
                root.ready = true;
            }
        }
        onLoadFailed: error => {
            root.ready = error === FileViewError.FileNotFound;
            root.error = root.ready ? "" : "Could not read notes. Check file permissions.";
        }
        onSaved: {
            root.saving = false;
            root.dirty = root.text !== root.pendingText;
            if (root.dirty)
                root.save();
        }
        onSaveFailed: error => {
            root.saving = false;
            root.error = "Could not save notes. Press Ctrl+S to retry.";
        }
    }

    Component.onDestruction: {
        save();
        file.waitForJob();
    }
}
