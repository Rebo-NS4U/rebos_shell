pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.theme
import qs.modules.components

Item {
    id: root
    property int maxContentWidth: 760
    readonly property real layoutSpacing: Styling.fontSize(-3)
    property list<var> bindings: []
    property list<string> watchedFiles: []
    property string searchQuery: ""
    property string errorMessage: ""
    property bool refreshPending: false
    property var editingBinding: null
    property string editMessage: ""
    property bool editFailed: false
    property string saveRequest: ""
    property bool addingBinding: false

    function addBinding(): void {
        if (writer.running || !newShortcut.text.trim() || !newCommand.text.trim())
            return;
        saveRequest = JSON.stringify({operation: "add", key: newShortcut.text,
            command: newCommand.text, name: newName.text});
        editMessage = "";
        writer.running = true;
    }

    function beginEdit(binding): void {
        if (writer.running)
            return;
        editingBinding = binding;
        addingBinding = false;
        editMessage = "";
        shortcutInput.text = binding.key;
        shortcutInput.forceActiveFocus();
        shortcutInput.selectAll();
    }

    function saveEdit(): void {
        if (!editingBinding || writer.running || !shortcutInput.text.trim())
            return;
        saveRequest = JSON.stringify({binding: editingBinding, key: shortcutInput.text});
        editMessage = "";
        writer.running = true;
    }
    readonly property list<var> filteredBindings: bindings.filter(binding => {
        const text = (binding.key + " " + binding.action + " " + binding.group).toLowerCase();
        return searchQuery.toLowerCase().trim().split(/\s+/).every(word => text.includes(word));
    })

    function refresh(): void {
        if (reader.running) {
            refreshPending = true;
            return;
        }
        reader.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: writer
        command: ["python3", Quickshell.shellPath("scripts/edit_keybinding.py")]
        stdinEnabled: true
        onStarted: write(root.saveRequest + "\n")
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.editFailed = !result.ok;
                    root.editMessage = result.ok ? result.message : result.error;
                    if (result.ok) {
                        if (root.addingBinding) {
                            root.addingBinding = false;
                            newShortcut.clear();
                            newCommand.clear();
                            newName.clear();
                        }
                        root.editingBinding = null;
                        root.refresh();
                    }
                } catch (error) {
                    root.editFailed = true;
                    root.editMessage = "Could not save the shortcut. Refresh the list and try again.";
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.saveRequest = "";
            if (exitCode !== 0) {
                root.editFailed = true;
                root.editMessage = "Could not save the shortcut. Refresh the list and try again.";
            }
        }
    }

    Process {
        id: reader
        command: ["python3", Quickshell.shellPath("scripts/list_keybindings.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.bindings = result.bindings;
                    root.errorMessage = result.error;
                    // Keep FileView watchers alive across refreshes.
                    if (JSON.stringify(root.watchedFiles) !== JSON.stringify(result.files))
                        root.watchedFiles = result.files;
                } catch (error) {
                    root.errorMessage = "Could not read shortcuts. Try refreshing the list.";
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.errorMessage = "Could not read shortcuts. Try refreshing the list.";
            if (root.refreshPending) {
                root.refreshPending = false;
                refreshTimer.restart();
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 150
        onTriggered: root.refresh()
    }
    Repeater {
        model: root.watchedFiles
        delegate: Item {
            required property string modelData
            FileView {
                path: modelData
                preload: true
                watchChanges: true
                onFileChanged: {
                    reload();
                    refreshTimer.restart();
                }
            }
        }
    }

    component Caption: StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
        color: Colors.overSurfaceVariant
    }

    component Action: SettingsButton {}

    ColumnLayout {
        width: Math.min(root.width, root.maxContentWidth)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: root.layoutSpacing

        PanelTitlebar {
            Layout.fillWidth: true
            title: "Keyboard shortcuts"
            description: "Add and change keyboard shortcuts."
            statusText: reader.running ? "Loading…" : root.bindings.length + (root.bindings.length === 1 ? " shortcut" : " shortcuts")
            actions: [{
                icon: Icons.sync,
                tooltip: "Refresh shortcuts",
                enabled: !reader.running,
                onClicked: function () { root.refresh(); }
            }]
        }
        SettingsGroup {
            title: "Find a shortcut"
        Caption {
            text: "Super is the Windows key. Desktop shortcuts work everywhere; terminal shortcuts work in Kitty."
        }
        Caption {
            text: "Select Edit to change a shortcut. Its action stays the same."
        }
        SearchInput {
            Layout.fillWidth: true
            placeholderText: "Find an action or shortcut…"
            onSearchTextChanged: text => root.searchQuery = text
        }
        }

        SettingsGroup {
            title: "Add keybind"
            description: "Launch an app or run a command with a desktop shortcut."
            Action {
                objectName: "shortcut-add-open"
                visible: !root.addingBinding
                text: "Add keybind"
                enabled: !writer.running
                onClicked: {
                    root.editingBinding = null;
                    root.editMessage = "";
                    root.addingBinding = true;
                    newShortcut.forceActiveFocus();
                }
            }
            ColumnLayout {
                visible: root.addingBinding
                Layout.fillWidth: true
                spacing: root.layoutSpacing / 2
                RowLayout {
                    Layout.fillWidth: true
                    SettingsTextField {
                        id: newShortcut
                        objectName: "shortcut-add-key"
                        Layout.fillWidth: true
                        enabled: !writer.running
                        placeholderText: "Shortcut, e.g. Super+Shift+K"
                        onAccepted: newCommand.forceActiveFocus()
                    }
                    SettingsTextField {
                        id: newName
                        objectName: "shortcut-add-name"
                        Layout.fillWidth: true
                        enabled: !writer.running
                        placeholderText: "Name (optional)"
                        maximumLength: 100
                    }
                }
                SettingsTextField {
                    id: newCommand
                    objectName: "shortcut-add-command"
                    Layout.fillWidth: true
                    enabled: !writer.running
                    placeholderText: "Command, e.g. kitty or firefox"
                    maximumLength: 4096
                    onAccepted: root.addBinding()
                }
                Caption { text: "Use + between modifiers and the key, e.g. Super+Shift+K. The command runs when you press the shortcut." }
                RowLayout {
                    Action {
                        objectName: "shortcut-add-save"
                        text: writer.running ? "Saving…" : "Save keybind"
                        enabled: !writer.running && !!newShortcut.text.trim() && !!newCommand.text.trim()
                        onClicked: root.addBinding()
                    }
                    Action {
                        text: "Cancel"
                        enabled: !writer.running
                        onClicked: {
                            root.addingBinding = false;
                            root.editMessage = "";
                        }
                    }
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: editorLayout.implicitHeight + root.layoutSpacing * 2
            visible: root.editingBinding !== null
            variant: "pane"
            ColumnLayout {
                id: editorLayout
                anchors.fill: parent
                anchors.margins: root.layoutSpacing
                spacing: root.layoutSpacing / 2
                Caption {
                    text: (root.editingBinding?.action ?? "") + " · " + (root.editingBinding?.group ?? "")
                    color: Colors.overSurface
                    font.bold: true
                }
                RowLayout {
                    SettingsTextField {
                        id: shortcutInput
                        objectName: "shortcut-editor-input"
                        Layout.fillWidth: true
                        enabled: !writer.running
                        placeholderText: "Super+Shift+A"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        color: Colors.overSurface
                        placeholderTextColor: Colors.overSurfaceVariant
                        selectionColor: Colors.primary
                        selectedTextColor: Colors.overPrimary

                        onAccepted: root.saveEdit()
                    }
                    Action {
                        objectName: "shortcut-editor-save"
                        text: writer.running ? "Saving…" : "Save"
                        enabled: !writer.running && !!shortcutInput.text.trim()
                        onClicked: root.saveEdit()
                    }
                    Action {
                        text: "Cancel"
                        enabled: !writer.running
                        onClicked: {
                            root.editingBinding = null;
                            root.editMessage = "";
                        }
                    }
                }
                Caption { text: "Type modifiers separated by +, then a key name. Examples: Super+Shift+A, Ctrl+Shift+F, Alt+Return. Use 'plus' for the + key." }
            }
        }
        Caption {
            visible: root.editMessage !== ""
            text: root.editMessage
            color: root.editFailed ? Colors.error : Colors.primary
        }
        Caption {
            visible: root.errorMessage !== ""
            text: root.errorMessage
            color: Colors.error
        }
        Caption {
            visible: !reader.running && root.filteredBindings.length === 0
            text: root.bindings.length > 0 ? "No matching shortcuts." : "No configured shortcuts found."
        }

        ListView {
            id: shortcutList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 12
            model: root.filteredBindings
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            ScrollBar.vertical: ScrollBar {}

            delegate: StyledRect {
                id: row
                required property var modelData
                width: shortcutList.width
                implicitHeight: rowLayout.implicitHeight + 32
                variant: hover.hovered ? "focus" : "pane"
                border.width: 1
                border.color: Qt.alpha(Colors.outline, 0.3)
                radius: Styling.radius(-2)

                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.layoutSpacing / 4
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.action
                            wrapMode: Text.WordWrap
                            color: Colors.overSurface
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                        }
                        Caption {
                            text: row.modelData.group
                            font.pixelSize: Styling.fontSize(-2)
                        }
                    }
                    StyledText {
                        Layout.maximumWidth: shortcutList.width * 0.4
                        text: row.modelData.key
                        wrapMode: Text.WrapAnywhere
                        horizontalAlignment: Text.AlignRight
                        color: Colors.primary
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.bold: true
                    }
                    Action {
                        text: "Edit"
                        enabled: !writer.running && (row.modelData.editable ?? false)
                        onClicked: root.beginEdit(row.modelData)
                    }
                }
                HoverHandler { id: hover }
                StyledToolTip {
                    show: hover.hovered
                    tooltipText: row.modelData.source ?? ""
                }
            }
        }
    }
}
