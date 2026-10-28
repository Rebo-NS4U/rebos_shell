pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property int limit: 64
    property alias files: entries
    readonly property int count: entries.count
    property bool visible: false
    property string screenName: ""
    property bool dragging: false
    property bool ready: false
    property bool busy: false
    property string error: ""
    property string statePath: Quickshell.statePath("file-shelf.json")
    property list<string> pending: []
    property list<string> job: []
    property int generation: 0
    property int jobGeneration: 0
    property bool dirty: false
    property bool saving: false
    property string savingText: ""

    ListModel { id: entries }

    function open(name: string) {
        screenName = name || NiriService.focusedMonitor?.name || Quickshell.screens[0]?.name || "";
        visible = true;
    }
    function toggle(name: string) {
        const target = name || NiriService.focusedMonitor?.name || Quickshell.screens[0]?.name || "";
        if (visible && screenName === target) close();
        else open(target);
    }
    function close() { if (!dragging) visible = false; }

    function addUrls(urls: list<string>) {
        error = "";
        pending = pending.concat(urls).slice(0, 256);
        startNext();
    }
    function startNext() {
        if (!ready || busy || pending.length === 0) return;
        job = pending;
        pending = [];
        jobGeneration = generation;
        busy = true;
        inspect.running = true;
    }
    function applyResult(text: string, revision: int) {
        if (revision !== generation) return;
        try {
            const result = JSON.parse(text);
            if (result.error) { error = result.error; return; }
            for (const entry of result.entries || []) {
                let duplicate = false;
                for (let i = 0; i < entries.count; i++) {
                    if (entries.get(i).uri === entry.uri) { duplicate = true; break; }
                }
                if (duplicate) continue;
                if (entries.count >= limit) { error = "The shelf holds up to 64 files. Remove a card to make room."; break; }
                entries.append(entry);
            }
            if (result.rejected > 0) error = "Some items are missing or are not local files.";
            changed();
        } catch (_) { error = "Could not read the dropped files."; }
    }
    function remove(uri: string) {
        if (dragging) return;
        for (let i = 0; i < entries.count; i++) {
            if (entries.get(i).uri === uri) { entries.remove(i); changed(); return; }
        }
    }
    function clear() {
        if (dragging) return;
        generation++;
        pending = [];
        entries.clear();
        error = "";
        changed();
    }
    function serialized(): string {
        const urls = [];
        for (let i = 0; i < entries.count; i++) urls.push(entries.get(i).uri);
        return JSON.stringify(urls);
    }
    function changed() { dirty = true; saveTimer.restart(); }
    function save() {
        if (!ready || !dirty || saving) return;
        savingText = serialized();
        saving = true;
        stored.setText(savingText);
    }

    Process {
        id: inspect
        command: ["python3", Qt.resolvedUrl("../../scripts/file_shelf.py").toString().replace("file://", "")]
        stdinEnabled: true
        onStarted: write(JSON.stringify(root.job) + "\n")
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const result = text;
                const revision = root.jobGeneration;
                Qt.callLater(() => root.applyResult(result, revision));
            }
        }
        onExited: (code, status) => {
            root.busy = false;
            if (code !== 0 && root.jobGeneration === root.generation)
                root.error = "Could not read the dropped files.";
            Qt.callLater(root.startNext);
        }
    }
    Timer { id: saveTimer; interval: 200; onTriggered: root.save() }
    FileView {
        id: stored
        path: root.statePath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (root.ready) return;
            try {
                const saved = JSON.parse(text());
                if (!Array.isArray(saved)) throw new Error("Invalid shelf");
                root.pending = saved.filter(uri => typeof uri === "string").concat(root.pending).slice(0, 256);
            } catch (_) { root.error = "Could not restore the previous shelf."; }
            root.ready = true;
            root.startNext();
        }
        onLoadFailed: error => {
            root.ready = true;
            if (error !== FileViewError.FileNotFound)
                root.error = "Could not read the saved shelf.";
            root.startNext();
        }
        onSaved: {
            root.saving = false;
            root.dirty = root.serialized() !== root.savingText;
            if (root.dirty) root.save();
        }
        onSaveFailed: {
            root.saving = false;
            root.error = "Could not save the shelf. Your files are still here.";
        }
    }
    Component.onDestruction: { save(); stored.waitForJob(); }
}
