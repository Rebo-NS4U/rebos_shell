import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.components
import qs.modules.services
import qs.modules.theme
import qs.config

StyledRect {
    id: root
    property AiSession session: Ai.activeSession
    objectName: "assistantActivity"
    property bool expanded: true
    property string selectedKey: ""
    function entryKey(entry, index) {
        return entry.id ? "tool:" + entry.id : "plan:" + index + ":" + entry.content;
    }
    readonly property var selectedEntry: {
        let entries = root.session.activitySegments;
        for (let i = 0; i < entries.length; i++) {
            if (entryKey(entries[i], i) === selectedKey)
                return entries[i];
        }
        return null;
    }
    Connections {
        target: Ai
        function onActiveSessionChanged() { root.selectedKey = ""; }
    }
    readonly property int completed: root.session.activitySegments.filter(step => step.status === "completed").length
    readonly property int activeStep: {
        let entries = root.session.activitySegments;
        let active = entries.findIndex(step => step.status === "in_progress");
        if (active < 0)
            active = entries.findIndex(step => step.status === "pending");
        return active >= 0 ? active : entries.length - 1;
    }
    function followActiveStep() {
        Qt.callLater(function() {
            let row = stepRepeater.itemAt(root.activeStep);
            if (!row || stepsView.moving || !root.expanded || root.selectedKey)
                return;
            let top = row.y;
            let bottom = top + Math.min(row.height, stepsView.height);
            let target = stepsView.contentY;
            if (top < target)
                target = top;
            else if (bottom > target + stepsView.height)
                target = bottom - stepsView.height;
            stepsView.contentY = Math.max(0, Math.min(target, stepsView.contentHeight - stepsView.height));
        });
    }
    onActiveStepChanged: followActiveStep()
    onExpandedChanged: followActiveStep()
    function revealSelection() {
        Qt.callLater(function() {
            if (!root.selectedKey) return;
            let entries = root.session.activitySegments;
            let index = entries.findIndex((entry, i) => root.entryKey(entry, i) === root.selectedKey);
            let row = stepRepeater.itemAt(index);
            if (row) stepsView.contentY = Math.max(0, Math.min(row.y, stepsView.contentHeight - stepsView.height));
        });
    }
    onSelectedKeyChanged: { if (!selectedKey) followActiveStep(); else revealSelection(); }
    Connections {
        target: Ai.activeSession
        function onActivitySegmentsChanged() { root.followActiveStep(); }
    }
    visible: root.session.isBusy || root.session.activitySegments.length > 0 || root.session.taskPlanMarkdown.length > 0
    implicitHeight: content.implicitHeight + 16
    variant: "internalbg"
    radius: Styling.radius(8)
    border.width: 1
    border.color: Qt.alpha(Colors.primary, 0.18)

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        spacing: 6

        Button {
            id: toggle
            objectName: "assistantActivityToggle"
            Layout.fillWidth: true
            padding: 4
            background: Item {}
            Accessible.name: "Toggle assistant activity"
            onClicked: root.expanded = !root.expanded
            contentItem: RowLayout {
                Text {
                    text: "Activity"
                    color: Colors.overSurface
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: root.session.activitySegments.length > 0
                        ? root.completed + " of " + root.session.activitySegments.length + " finished"
                        : "Getting started…"
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    horizontalAlignment: Text.AlignRight
                }
                Text { text: root.expanded ? "▴" : "▾"; color: Colors.primary }
            }
        }

        Text {
            objectName: "assistantActivityTask"
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            text: root.session.activityText(root.session.activityTask)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Colors.overSurface
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            font.weight: Font.DemiBold
            lineHeight: 1.2
        }

        Text {
            objectName: "assistantActivityProgress"
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            visible: text.length > 0
            text: root.session.activityText(root.session.activityProgress)
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Colors.overSurface
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            lineHeight: 1.2
        }

        Flickable {
            id: stepsView
            objectName: "assistantActivityScroll"
            visible: root.expanded
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(root.selectedKey ? 320 : 128, steps.implicitHeight)
            contentWidth: width
            contentHeight: steps.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: root.followActiveStep()
            onHeightChanged: root.followActiveStep()
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: steps
                width: stepsView.width
                spacing: 7
                Repeater {
                    id: stepRepeater
                    model: root.session.activitySegments
                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 4
                        Button {
                            id: activityButton
                            readonly property string entryKey: root.entryKey(modelData, index)
                            readonly property bool selected: root.selectedKey === entryKey
                            objectName: "assistantActivityRow_" + index
                            Layout.fillWidth: true
                            padding: 5
                            hoverEnabled: true
                            Accessible.name: (!modelData.id ? root.session.activityText(modelData.content) : root.session.activitySentence(modelData)) + (selected ? ". Hide details" : ". Show details")
                            onClicked: root.selectedKey = selected ? "" : entryKey
                            background: StyledRect {
                                variant: "internalbg"
                                radius: Styling.radius(6)
                                color: Qt.alpha(Colors.primary, activityButton.selected ? 0.13 : activityButton.hovered ? 0.07 : 0)
                                border.width: activityButton.activeFocus ? 1 : 0
                                border.color: Colors.primary
                            }
                            contentItem: RowLayout {
                                spacing: 8
                                Text {
                                    Layout.alignment: Qt.AlignTop
                                    text: modelData.status === "completed" ? "✓" : String(index + 1) + "."
                                    color: modelData.status === "in_progress" ? Colors.primary : Colors.outline
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: !modelData.id
                                        ? root.session.activityText(modelData.content || "Work on the next step.")
                                        : root.session.activitySentence(modelData)
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                                    color: modelData.status === "in_progress" ? Colors.overSurface : Colors.outline
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    lineHeight: 1.2
                                }
                                Text {
                                    Layout.alignment: Qt.AlignTop
                                    text: ({completed: "Done", in_progress: "Working", pending: "Up next", failed: "Needs attention", stopped: "Stopped"})[modelData.status] || "Waiting"
                                    color: modelData.status === "in_progress" ? Colors.primary : Colors.outline
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                }
                                Text {
                                    text: activityButton.selected ? "▴" : "▾"
                                    color: Colors.primary
                                    font.pixelSize: Styling.fontSize(-1)
                                }
                            }
                        }
                        Loader {
                            Layout.fillWidth: true
                            active: activityButton.selected
                            visible: active
                            sourceComponent: Component {
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Changes, commands and output"
                                            color: Colors.overSurface
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                            font.weight: Font.DemiBold
                                        }
                                        Button {
                                            objectName: "assistantActivityCloseDetails"
                                            text: "Close"
                                            flat: true
                                            Accessible.name: "Close activity details"
                                            onClicked: root.selectedKey = ""
                                            contentItem: Text {
                                                text: parent.text
                                                color: Colors.primary
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(-1)
                                            }
                                            background: Item {}
                                        }
                                    }

                                    Flickable {
                                        id: detailsView
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.min(200, detailsText.implicitHeight)
                                        contentWidth: width
                                        contentHeight: detailsText.implicitHeight
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        ScrollBar.vertical: ScrollBar {}
                                        Connections {
                                            target: root
                                            function onSelectedKeyChanged() { detailsView.contentY = 0; }
                                        }
                                        TextEdit {
                                            id: detailsText
                                            objectName: "assistantActivityExplanation"
                                            width: detailsView.width
                                            text: root.session.activityExplanation(root.selectedEntry, root.selectedEntry !== null && !root.selectedEntry.id)
                                            textFormat: Text.PlainText
                                            wrapMode: TextEdit.Wrap
                                            readOnly: true
                                            selectByMouse: true
                                            color: Colors.overSurface
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.session.taskPlanMarkdown.length > 0
                    text: root.session.taskPlanMarkdown
                    textFormat: Text.MarkdownText
                    wrapMode: Text.WordWrap
                    color: Colors.overSurface
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                }
            }
        }


    }
}
