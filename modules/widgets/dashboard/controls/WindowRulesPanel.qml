pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.modules.globals

Item {
    id: root
    objectName: "window-rules-panel"
    property int maxContentWidth: 760
    property list<var> rules: []
    property string fingerprint: ""
    property string filePath: ""
    property string message: ""
    property bool failed: false
    property string requestText: ""
    property string searchText: ""
    property var deleteBinding: null
    readonly property WindowRuleDialog editor: ruleDialog
    readonly property bool busy: reader.running || writer.running
    readonly property list<var> filteredRules: rules.filter(rule =>
        (rule.name + " " + (rule.appId || "") + " " + (rule.title || "")).toLowerCase().includes(searchText.toLowerCase()))

    function loadResult(text): bool {
        try {
            const result = JSON.parse(text);
            const previouslyFailed = failed;
            failed = !result.ok;
            message = result.ok ? (result.message ?? (previouslyFailed ? "" : message)) : result.error;
            if (result.ok) {
                rules = result.rules;
                fingerprint = result.fingerprint;
                filePath = result.path;
            }
            return result.ok;
        } catch (error) {
            failed = true;
            message = "Could not load window rules.";
            return false;
        }
    }
    function submit(request): void {
        if (busy) return;
        request.fingerprint = fingerprint;
        requestText = JSON.stringify(request);
        message = "";
        writer.running = true;
    }
    function newRule(): void {
        const client = NiriService.lastExternalFocusedClient;
        ruleDialog.edit({name: client?.appId || "New window rule", appId: client?.appId || "",
            title: client?.title || ""});
    }
    function openPendingRule(): void {
        if (visible && width > 0 && GlobalStates.settingsNewWindowRuleRequested) {
            GlobalStates.settingsNewWindowRuleRequested = false;
            newRule();
        }
    }
    Component.onCompleted: {
        reader.running = true;
        Qt.callLater(root.openPendingRule);
    }
    onVisibleChanged: Qt.callLater(root.openPendingRule)
    Connections {
        target: GlobalStates
        function onSettingsNewWindowRuleRequestedChanged() { Qt.callLater(root.openPendingRule); }
    }

    Process {
        id: reader
        command: ["python3", Quickshell.shellPath("scripts/window_rules.py")]
        stdout: StdioCollector { onStreamFinished: root.loadResult(text) }
        onExited: (code, status) => {
            if (code !== 0) { root.failed = true; root.message = "Could not load window rules."; }
        }
    }
    Process {
        id: writer
        command: ["python3", Quickshell.shellPath("scripts/window_rules.py"), "edit"]
        stdinEnabled: true
        onStarted: write(root.requestText + "\n")
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.loadResult(text))
                    ruleDialog.close();
                else
                    ruleDialog.errorMessage = root.message;
            }
        }
        onExited: (code, status) => {
            root.requestText = "";
            if (code !== 0) {
                root.failed = true;
                root.message = "Could not save window rules.";
                ruleDialog.errorMessage = root.message;
            }
        }
    }
    FileView {
        path: root.filePath
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reloadTimer.restart()
    }
    Timer {
        id: reloadTimer
        interval: 200
        onTriggered: { if (!root.busy) reader.running = true; else restart(); }
    }

    component Caption: StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Colors.overSurfaceVariant
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
    }
    component Action: SettingsButton {}

    ColumnLayout {
        width: Math.min(root.width, root.maxContentWidth)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: Styling.fontSize(-3)
        PanelTitlebar {
            title: "Window rules"
            description: "Set how windows open and appear."
            statusText: root.busy ? "Loading…" : root.rules.length + (root.rules.length === 1 ? " rule" : " rules")
            actions: [{icon: Icons.sync, tooltip: "Refresh rules", enabled: !root.busy,
                onClicked: function () { reader.running = true; }}]
        }
        SettingsGroup {
            title: "Find or add a rule"
        Caption { text: "Add rules for the last app you used. These rules override the defaults." }
        Action { Layout.fillWidth: true; text: "Add window rule"; enabled: !root.busy; onClicked: root.newRule() }
        SearchInput { Layout.fillWidth: true; placeholderText: "Search rules…"; onSearchTextChanged: text => root.searchText = text }
        }

        Caption { visible: !!root.message; text: root.message; color: root.failed ? Colors.error : Colors.primary }
        ListView {
            id: ruleList
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.filteredRules
            clip: true
            spacing: 12
            reuseItems: true
            ScrollBar.vertical: ScrollBar {}
            delegate: StyledRect {
                id: row
                required property var modelData
                width: ruleList.width
                implicitHeight: rowLayout.implicitHeight + Styling.fontSize(0) * 2
                variant: "pane"
                border.width: 1
                border.color: Qt.alpha(Colors.outline, 0.3)
                ColumnLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.margins: Styling.fontSize(0)
                    Caption { text: row.modelData.name; color: Colors.overSurface; font.bold: true }
                    Caption { text: row.modelData.managed ? (row.modelData.appId || row.modelData.title) : "Existing config rule"; elide: Text.ElideRight; maximumLineCount: 2 }
                    RowLayout {
                        StyledSwitch {
                            visible: row.modelData.managed
                            text: "Enabled"
                            checked: row.modelData.enabled
                            enabled: !root.busy
                            palette.windowText: Colors.overSurface
                            palette.highlight: Colors.primary
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            onClicked: {
                                root.submit({op: "save", rule: Object.assign({}, row.modelData, {enabled: checked})});
                                checked = Qt.binding(() => row.modelData.enabled);
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Action {
                            text: row.modelData.managed ? "Edit" : "View"
                            enabled: !root.busy
                            onClicked: {
                                if (row.modelData.managed) ruleDialog.edit(row.modelData);
                                else { configPreview.text = row.modelData.body; previewDialog.open(); }
                            }
                        }
                        Action {
                            objectName: "delete-window-rule-button"
                            text: "Delete"
                            enabled: !root.busy
                            onClicked: { root.deleteBinding = row.modelData; deleteDialog.open(); }
                        }
                    }
                }
            }
        }
    }
    WindowRuleDialog {
        id: ruleDialog
        objectName: "window-rule-editor"
        busy: root.busy
        onSaveRequested: rule => root.submit({op: "save", rule: rule})
    }
    Dialog {
        id: deleteDialog
        objectName: "delete-window-rule-dialog"
        parent: Overlay.overlay
        modal: true
        anchors.centerIn: parent
        title: "Delete this window rule?"
        palette.windowText: Colors.overSurface
        palette.buttonText: Colors.overSurface
        standardButtons: Dialog.Yes | Dialog.No
        background: StyledRect { variant: "popup" }
        contentItem: Caption { text: root.deleteBinding?.name ?? "" }
        onAccepted: {
            if (root.deleteBinding?.managed)
                root.submit({op: "delete", id: root.deleteBinding.id});
            else if (root.deleteBinding)
                root.submit({op: "delete-existing", binding: root.deleteBinding});
        }
    }
    Dialog {
        id: previewDialog
        parent: Overlay.overlay
        modal: true
        width: Math.min(root.width, Styling.fontSize(0) * 45)
        height: Math.min(root.height, Styling.fontSize(0) * 35)
        anchors.centerIn: parent
        background: StyledRect { variant: "popup" }
        standardButtons: Dialog.Close
        palette.buttonText: Colors.overSurface
        contentItem: ScrollView {
            clip: true
            TextArea {
                id: configPreview
                readOnly: true
                wrapMode: TextEdit.Wrap
                color: Colors.overSurface
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.monoFontSize(-1)
                background: StyledRect { variant: "internalbg" }
            }
        }
    }
}
