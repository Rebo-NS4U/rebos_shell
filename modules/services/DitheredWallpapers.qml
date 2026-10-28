pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root
    readonly property bool active: Config.theme.shellStyle === "dithered"
    readonly property string palette: Config.theme.ditherPalette
    readonly property string tint: palette === "tint" ? Config.theme.ditherTintColor.toLowerCase() : ""
    readonly property string strength: Config.theme.wallpaperDitherStrength
    readonly property bool busy: worker.running || pending.length > 0
    property string error: ""
    property list<string> pending: []
    property string processing: ""
    property string processingPalette: ""
    property string processingTint: ""
    property string processingStrength: ""
    // Dictionaries keyed by palette + strength + original path; originals remain saved
    // in the gallery, so changing styles always restores the original.
    property var outputs: ({})
    property var failures: ({})
    signal finished(string path)

    function key(path: string): string { return palette + ":" + strength + ":" + tint + ":" + path; }
    function source(path: string): string {
        return active ? (outputs[key(path)] ?? path) : path;
    }
    function waiting(path: string): bool {
        return active && supported(path) && !outputs[key(path)] && !failures[key(path)];
    }
    function supported(path: string): bool {
        return /\.(png|jpe?g|webp|bmp|tiff?|avif)$/i.test(path);
    }
    function request(path: string): void {
        if (!active || !supported(path) || pending.indexOf(path) !== -1 ||
                (processing === path && processingPalette === palette && processingStrength === strength && processingTint === tint)) return;
        pending = pending.concat([path]);
        Qt.callLater(startNext);
    }
    function startNext(): void {
        if (worker.running || !pending.length) return;
        if (!active) { pending = []; return; }
        processing = pending[0];
        processingPalette = palette;
        processingStrength = strength;
        processingTint = tint;
        pending = pending.slice(1);
        error = "";
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl(
            "../../scripts/dither_wallpaper.py").toString().replace("file://", "")),
            processing, "--palette", processingPalette, "--strength", processingStrength,
            "--tint", processingTint || Config.theme.ditherTintColor];
        worker.running = true;
    }

    Process {
        id: worker
        stdout: StdioCollector { id: response }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            const path = root.processing;
            const cacheKey = root.processingPalette + ":" + root.processingStrength + ":" + root.processingTint + ":" + path;
            let result = {};
            try { result = JSON.parse(response.text); } catch (_) {}
            if (code === 0 && result.path) {
                root.outputs = Object.assign({}, root.outputs, {[cacheKey]: result.path});
            } else {
                root.error = result.error ?? "Wallpaper conversion failed; using the original image.";
                root.failures = Object.assign({}, root.failures, {[cacheKey]: true});
            }
            root.processing = "";
            Qt.callLater(() => { root.finished(path); root.startNext(); });
        }
    }
}
