import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.components
import qs.modules.services
import qs.modules.theme
import qs.config

Column {
    id: root
    property AiSession session: Ai.activeSession
    objectName: "assistantQuestions"
    spacing: 12

    component SecondaryButton: Button {
        id: control
        padding: 10
        background: StyledRect {
            variant: control.hovered ? "focus" : "common"
            radius: Styling.radius(4)
        }
        contentItem: Text {
            text: control.text
            color: Colors.overSurface
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    Repeater {
        model: root.session.questionRequests.length
        delegate: StyledRect {
            id: card
            required property int index
            readonly property var request: root.session.questionRequests[index] || ({})
            readonly property var draft: root.session.questionDrafts[String(request.requestId)] || ({})
            width: root.width
            implicitHeight: form.implicitHeight + 24
            variant: "internalbg"
            radius: Styling.radius(8)
            border.width: 1
            border.color: Qt.alpha(Colors.primary, 0.4)

            ColumnLayout {
                id: form
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: (card.request.agent || "Assistant") + " has a question"
                    color: Colors.primary
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: card.request.message || ""
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Colors.overSurface
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                }
                Repeater {
                    model: root.session.questionFields(card.request)
                    delegate: ColumnLayout {
                        id: field
                        required property var modelData
                        readonly property var value: card.draft[modelData.key]
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: field.modelData.title + (field.modelData.required ? " *" : "")
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            color: Colors.overSurface
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: field.modelData.description.length > 0
                            text: field.modelData.description
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                        }
                        Repeater {
                            model: field.modelData.type === "boolean"
                                ? [{value: true, label: "Yes"}, {value: false, label: "No"}]
                                : field.modelData.choices
                            delegate: Button {
                                id: choice
                                required property var modelData
                                Layout.fillWidth: true
                                padding: 10
                                enabled: root.session.bridgeAttached
                                readonly property bool selected: field.modelData.type === "array"
                                    ? Array.isArray(field.value) && field.value.includes(modelData.value)
                                    : field.value === modelData.value
                                objectName: "questionChoice_" + field.modelData.key + "_" + String(modelData.value)
                                Accessible.name: modelData.label + (selected ? ", selected" : "")
                                onClicked: {
                                    let value = modelData.value;
                                    if (field.modelData.type === "array") {
                                        let values = Array.isArray(field.value) ? Array.from(field.value) : [];
                                        value = selected ? values.filter(item => item !== modelData.value) : values.concat([modelData.value]);
                                    }
                                    root.session.setQuestionAnswer(card.request.requestId, field.modelData.key, value);
                                }
                                background: StyledRect {
                                    variant: choice.selected ? "focus" : choice.hovered ? "common" : "pane"
                                    radius: Styling.radius(4)
                                    border.width: choice.selected ? 1 : 0
                                    border.color: Qt.alpha(Colors.primary, 0.6)
                                }
                                contentItem: ColumnLayout {
                                    spacing: 3
                                    Text {
                                        Layout.fillWidth: true
                                        text: (choice.selected ? "● " : "○ ") + choice.modelData.label
                                        textFormat: Text.PlainText
                                        wrapMode: Text.WordWrap
                                        color: Colors.overSurface
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: !!choice.modelData.description
                                        text: choice.modelData.description || ""
                                        textFormat: Text.PlainText
                                        wrapMode: Text.WordWrap
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-2)
                                    }
                                }
                            }
                        }
                        TextField {
                            id: answer
                            objectName: "questionInput_" + field.modelData.key
                            Layout.fillWidth: true
                            visible: field.modelData.choices.length === 0 && field.modelData.type !== "boolean" && field.modelData.type !== "array"
                            enabled: root.session.bridgeAttached
                            text: field.value === undefined ? "" : String(field.value)
                            placeholderText: field.modelData.required ? "Your answer…" : "Optional answer…"
                            placeholderTextColor: Colors.outline
                            color: Colors.overSurface
                            echoMode: field.modelData.secret ? TextInput.Password : TextInput.Normal
                            selectByMouse: true
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            onTextEdited: root.session.setQuestionAnswer(card.request.requestId, field.modelData.key, text)
                            background: StyledRect {
                                variant: "common"
                                radius: Styling.radius(4)
                                border.width: 1
                                border.color: Qt.alpha(Colors.primary, answer.activeFocus ? 0.6 : 0.2)
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: !!root.session.questionErrors[String(card.request.requestId)]
                    text: root.session.questionErrors[String(card.request.requestId)] || ""
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Colors.overError
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    SecondaryButton {
                        objectName: "questionDecline"
                        text: "Decline"
                        enabled: root.session.bridgeAttached
                        onClicked: root.session.answerQuestion(card.request.requestId, "decline")
                    }
                    SecondaryButton {
                        objectName: "questionCancel"
                        text: "Cancel"
                        enabled: root.session.bridgeAttached
                        onClicked: root.session.answerQuestion(card.request.requestId, "cancel")
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        id: submit
                        padding: 10
                        objectName: "questionSubmit"
                        text: "Send answer"
                        enabled: root.session.bridgeAttached
                        onClicked: root.session.answerQuestion(card.request.requestId, "accept")
                        background: StyledRect {
                            variant: submit.hovered ? "focus" : "primary"
                            radius: Styling.radius(4)
                        }
                        contentItem: Text {
                            text: submit.text
                            color: Styling.srItem("overprimary")
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
