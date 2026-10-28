import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.components
import qs.modules.theme
import qs.config
import "WallpaperColors.js" as WallpaperColors

ColumnLayout {
    id: root

    property list<string> paths: []
    property string directory: ""
    property string colorGroup: "all"
    property string sortOrder: "name"
    // Dynamic path keys require a JavaScript dictionary.
    property var colorIndex: ({})
    property string indexError: ""
    readonly property list<string> arrangedPaths: WallpaperColors.arrange(paths, colorIndex, colorGroup, sortOrder)
    readonly property bool indexing: indexProcess.running || indexDelay.running

    function focusColor() { colorSelector.forceActiveFocus(); }
    function focusSort() { sortSelector.forceActiveFocus(); }
    onPathsChanged: indexDelay.restart()
    onDirectoryChanged: indexDelay.restart()
    Component.onCompleted: indexDelay.restart()

    Timer {
        id: indexDelay
        interval: 350
        onTriggered: {
            if (!root.directory || root.paths.length === 0)
                return;
            if (indexProcess.running) {
                restart();
                return;
            }
            root.indexError = "";
            indexProcess.command = ["python3", decodeURIComponent(Qt.resolvedUrl("../../../../scripts/wallpaper_color_index.py").toString().replace("file://", "")), root.directory];
            indexProcess.running = true;
        }
    }

    Process {
        id: indexProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    Qt.callLater(() => {
                        root.indexError = result.error ?? "";
                        if (result.colors)
                            root.colorIndex = result.colors;
                    });
                } catch (error) {
                    root.indexError = "Could not read wallpaper colors.";
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.indexError = "Could not index wallpaper colors.";
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Styling.fontSize(-3)
        WallpaperChoice {
            id: colorSelector
            objectName: "wallpaper-color-filter"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            textRole: "label"
            valueRole: "value"
            model: [
                {label: "All colors", value: "all"},
                {label: "Red", value: "red"}, {label: "Orange", value: "orange"},
                {label: "Yellow", value: "yellow"}, {label: "Green", value: "green"},
                {label: "Cyan", value: "cyan"}, {label: "Blue", value: "blue"},
                {label: "Purple", value: "purple"}, {label: "Pink", value: "pink"},
                {label: "White", value: "white"}, {label: "Gray", value: "gray"},
                {label: "Black", value: "black"}, {label: "Unclassified", value: "unknown"}
            ]
            onActivated: root.colorGroup = currentValue
        }
        WallpaperChoice {
            id: sortSelector
            objectName: "wallpaper-color-sort"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            textRole: "label"
            valueRole: "value"
            model: [
                {label: "Sort: Name", value: "name"},
                {label: "Sort: Color", value: "color"},
                {label: "Dark → Light", value: "dark"},
                {label: "Light → Dark", value: "light"}
            ]
            onActivated: root.sortOrder = currentValue
        }
    }
    StyledText {
        Layout.fillWidth: true
        color: Colors.overSurfaceVariant
        font.pixelSize: Styling.fontSize(-2)
        text: root.indexError || (root.indexing ? "Finding wallpaper colors…" : root.arrangedPaths.length + " wallpapers · dominant color")
        elide: Text.ElideRight
    }
}
