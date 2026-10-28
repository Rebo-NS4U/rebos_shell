import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.components
import qs.modules.services
import qs.modules.theme
import qs.config

ColumnLayout {
    id: root
    spacing: 8
    property bool expanded: false
    readonly property bool canSwitch: Ai.activeSession.sessionReady && !Ai.activeSession.isBusy && !Ai.activeSession.switchingSessionModel
    readonly property var filteredModels: {
        const query = search.text.trim().toLowerCase();
        return Ai.activeSession.sessionModels.filter(choice => !query ||
            ((choice.name || "") + " " + (choice.modelId || "") + " " + (choice.description || "")).toLowerCase().includes(query));
    }
    onVisibleChanged: { if (!visible) expanded = false; }

    Button {
        id: toggle
        objectName: "assistantModelButton"
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        padding: 10
        Accessible.name: "Choose AI model: " + Ai.activeSession.sessionModelName
        background: StyledRect {
            variant: toggle.hovered || root.expanded ? "focus" : "internalbg"
            radius: Styling.radius(8)
            border.color: Qt.alpha(Colors.primary, 0.25)
            border.width: 1
        }
        contentItem: RowLayout {
            spacing: 8
            Text {
                text: "Model"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.outline
            }
            Text {
                Layout.fillWidth: true
                text: Ai.activeSession.switchingSessionModel ? "Switching…" : Ai.activeSession.sessionModelName
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                font.weight: Font.DemiBold
                color: Colors.overSurface
                elide: Text.ElideRight
            }
            Text {
                text: root.expanded ? "▴" : "▾"
                color: Colors.primary
                font.pixelSize: Styling.fontSize(2)
            }
        }
        StyledToolTip {
            show: parent.hovered
            tooltipText: "Choose the model for this conversation"
        }
        onClicked: {
            root.expanded = !root.expanded;
            if (root.expanded) search.text = "";
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: choices.implicitHeight + 20
        visible: root.expanded
        variant: "internalbg"
        radius: Styling.radius(8)
        ColumnLayout {
            id: choices
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: Ai.activeSession.isBusy ? "You can change models after this reply finishes."
                    : Ai.activeSession.switchingSessionModel ? "Applying your selection…"
                    : "Choose a model for your next message"
                wrapMode: Text.WordWrap
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.outline
            }
            TextField {
                id: search
                objectName: "assistantModelSearch"
                Layout.fillWidth: true
                visible: Ai.activeSession.sessionModels.length > 0
                placeholderText: "Search models…"
                color: Colors.overSurface
                placeholderTextColor: Colors.outline
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                selectByMouse: true
                background: StyledRect {
                    variant: "common"
                    radius: Styling.radius(4)
                    border.width: 1
                    border.color: Qt.alpha(Colors.primary, search.activeFocus ? 0.6 : 0.2)
                }
                Keys.onEscapePressed: root.expanded = false
            }
            ListView {
                id: modelList
                objectName: "assistantModelList"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(220, contentHeight)
                clip: true
                spacing: 4
                model: root.filteredModels
                ScrollBar.vertical: ScrollBar {}
                delegate: Button {
                    id: modelButton
                    required property var modelData
                    width: modelList.width
                    height: modelTexts.implicitHeight + 20
                    padding: 10
                    enabled: root.canSwitch
                    readonly property bool selected: modelData.modelId === Ai.activeSession.currentSessionModelId
                    Accessible.name: (modelData.name || modelData.modelId) + (selected ? ", current model" : "")
                    background: StyledRect {
                        variant: modelButton.selected ? "focus" : modelButton.hovered ? "common" : "transparent"
                        radius: Styling.radius(4)
                        border.width: modelButton.selected ? 1 : 0
                        border.color: Qt.alpha(Colors.primary, 0.4)
                    }
                    contentItem: RowLayout {
                        spacing: 8
                        ColumnLayout {
                            id: modelTexts
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: modelButton.modelData.name || modelButton.modelData.modelId
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overSurface
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: modelButton.modelData.description || ""
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-3)
                                color: Colors.outline
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            text: modelButton.selected ? "✓" : ""
                            color: Colors.primary
                            font.pixelSize: Styling.fontSize(1)
                        }
                    }
                    onClicked: {
                        if (selected) root.expanded = false;
                        else Ai.activeSession.setSessionModel(modelData.modelId);
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: root.filteredModels.length === 0
                text: Ai.activeSession.sessionModels.length > 0 ? "No models match your search."
                    : !Ai.activeSession.sessionReady ? "Connect to load your available models."
                    : "This agent does not offer model choices."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.outline
                wrapMode: Text.WordWrap
            }
            Button {
                Layout.fillWidth: true
                visible: !Ai.activeSession.sessionReady
                enabled: !Ai.activeSession.isBusy && !Ai.activeSession.statusText
                text: Ai.activeSession.statusText || "Load models"
                onClicked: Ai.activeSession.ensureConnection({
                    kind: Ai.activeSession.currentSessionId ? "load" : "new",
                    sessionId: Ai.activeSession.currentSessionId,
                    cwd: Ai.activeSession.currentChatCwd
                })
            }
            Text {
                Layout.fillWidth: true
                visible: Ai.activeSession.modelSwitchError.length > 0
                text: Ai.activeSession.modelSwitchError
                color: Colors.error
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                wrapMode: Text.WordWrap
            }
        }
    }
    Connections {
        target: Ai.activeSession
        function onSwitchingSessionModelChanged() {
            if (!Ai.activeSession.switchingSessionModel && !Ai.activeSession.modelSwitchError) root.expanded = false;
        }
    }
}
