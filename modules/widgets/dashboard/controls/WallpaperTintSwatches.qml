pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.config
import qs.modules.components
import qs.modules.globals
import qs.modules.theme

ColumnLayout {
    id: root
    objectName: "wallpaper-tint-swatches"
    property string source: GlobalStates.wallpaperManager?.currentWallpaper ?? ""
    property string processingSource: ""
    property list<string> colors: []
    property string error: ""

    onSourceChanged: {
        colors = [];
        error = "";
        refresh.restart();
    }
    Component.onCompleted: refresh.restart()
    Timer {
        id: refresh
        interval: 100
        onTriggered: {
            if (worker.running || !root.source) return;
            root.processingSource = root.source;
            worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl(
                "../../../../scripts/dither_wallpaper.py").toString().replace("file://", "")),
                root.processingSource, "--swatches"];
            worker.running = true;
        }
    }
    Process {
        id: worker
        stdout: StdioCollector { id: response }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            if (root.processingSource !== root.source) {
                refresh.restart();
                return;
            }
            let result = {};
            try { result = JSON.parse(response.text); } catch (_) {}
            Qt.callLater(() => {
                if (root.processingSource !== root.source) return;
                root.colors = code === 0 ? (result.colors ?? []) : [];
                root.error = code === 0 ? "" : "Could not sample this wallpaper. Choose a custom color below.";
            });
        }
    }
    StyledText {
        text: "Colors from original wallpaper"
        font.pixelSize: Styling.fontSize(-1)
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: root.colors
            delegate: Button {
                id: swatch
                hoverEnabled: true
                required property string modelData
                objectName: "wallpaper-tint-" + modelData
                implicitWidth: Styling.fontSize(0) * 2.5
                implicitHeight: implicitWidth
                Accessible.name: "Tint wallpaper " + modelData
                StyledToolTip {
                    show: swatch.hovered
                    tooltipText: swatch.modelData
                }
                onClicked: Config.theme.ditherTintColor = modelData
                background: StyledRect {
                    variant: "common"
                    objectName: "swatch-fill"
                    fillColor: swatch.modelData
                    backgroundOpacity: 1
                    border.width: swatch.activeFocus || Config.theme.ditherTintColor === swatch.modelData ? 3 : 1
                    border.color: Colors.overSurface
                }
            }
        }
    }
    StyledText {
        visible: worker.running || root.error !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Styling.fontSize(-2)
        color: Colors.overSurfaceVariant
        text: worker.running ? "Sampling wallpaper colors…" : root.error
    }
}
