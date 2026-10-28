pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

ColumnLayout {
    id: root
    spacing: 8
    readonly property var info: SystemResources.windowInfo
    readonly property var windowData: info.window ?? ({})
    readonly property var processData: info.process ?? ({})
    RowLayout {
        Layout.fillWidth: true
        MetricAction { text: "← All stats"; onClicked: SystemResources.detailMetric = "" }
        Item { Layout.fillWidth: true }
        MetricAction { text: "Pick another window"; enabled: !SystemResources.windowActionBusy && !SystemResources.pickingWindow; onClicked: SystemResources.pickWindow() }
    }
    StyledText { text: "Window information"; font.bold: true }
    RowLayout {
        Layout.fillWidth: true
        visible: !!root.info.window && !SystemResources.pickingWindow
        enabled: !SystemResources.windowActionBusy && !SystemResources.windowKilled
        spacing: 6
        MetricAction { text: "Close window"; onClicked: SystemResources.controlWindow("close") }
        MetricAction {
            text: "Terminate"
            enabled: !!root.processData.start
            onClicked: SystemResources.controlWindow("terminate")
        }
        MetricAction {
            text: "Force kill"
            enabled: !!root.processData.start
            onClicked: SystemResources.controlWindow("kill")
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: !!root.info.window && !SystemResources.pickingWindow
        text: "Terminate and Force kill affect the app process and may close its other windows."
        font.pixelSize: Styling.fontSize(-3)
        color: Colors.overSurfaceVariant
        wrapMode: Text.Wrap
    }
    StyledText {
        Layout.fillWidth: true
        visible: SystemResources.windowActionBusy || SystemResources.windowActionMessage !== ""
        text: SystemResources.windowActionBusy ? "Sending action…" : SystemResources.windowActionMessage
        font.pixelSize: Styling.fontSize(-2)
        wrapMode: Text.Wrap
    }
    ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(330, details.implicitHeight)
        contentWidth: availableWidth
        clip: true
        TextArea {
            id: details
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            color: Colors.overBackground
            font.family: Config.theme.font
            renderType: TextEdit.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.pixelSize: Styling.fontSize(-2)
            background: Item { }
            text: {
                if (SystemResources.pickingWindow) return "Click a window on your screen. Escape cancels.";
                if (root.info.error) return root.info.error;
                if (!root.info.window) return "Choose Pick window to inspect an application.";
                const w = root.windowData;
                const p = root.processData;
                const lines = ["Title: " + (w.title ?? "Untitled"), "App: " + (w.app_id ?? "Unknown"), "Window ID: " + w.id,
                    "PID: " + (w.pid ?? "Unavailable"), "PPID: " + (p.ppid ?? "Unavailable"),
                    "Process: " + (p.name ?? "Unavailable"), "Executable: " + (p.exe ?? "Unavailable"),
                    "Memory at selection: " + (p.ram !== undefined ? (p.ram / 1024 / 1024).toFixed(1) + " MiB" : "Unavailable"),
                    "Workspace ID: " + (w.workspace_id ?? "Unavailable"),
                    "Focused: " + (w.is_focused ? "Yes" : "No"), "Floating: " + (w.is_floating ? "Yes" : "No")];
                if (w.layout?.window_size) lines.push("Size: " + w.layout.window_size.join(" × "));
                if (root.info.process_note) lines.push(root.info.process_note);
                return lines.join("\n\n");
            }
        }
    }
}
