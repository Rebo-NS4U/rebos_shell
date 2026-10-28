pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.modules.theme

Item {
    id: root
    required property ShellScreen screen
    readonly property bool open: QuickNotes.visible && QuickNotes.screenName === screen.name
        && !GlobalStates.lockscreenVisible
    readonly property Item blurTarget: reveal.visible ? card : null
    readonly property Item hitbox: open ? card : null
    readonly property real unit: Styling.fontSize(0)
    readonly property color statusColor: QuickNotes.error ? Colors.error
        : QuickNotes.dirty || QuickNotes.saving ? Colors.tertiary : Colors.primary
    visible: open || reveal.progress > 0



    onOpenChanged: {
        if (open)
            Qt.callLater(() => editor.forceActiveFocus());
    }

    MotionReveal {
        id: reveal
        open: root.open
        anchors.centerIn: parent
        width: Math.min(root.width - root.unit * 3, root.unit * 42)
        height: Math.min(root.height - root.unit * 6, root.unit * 32)

        StyledRect {
            id: card
            anchors.fill: parent
            variant: "popup"
            border.color: Qt.alpha(Colors.primary, 0.28)
            border.width: 1
            radius: Styling.radius(4)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.unit * 1.4
                spacing: root.unit

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.unit * 0.8

                    StyledRect {
                        implicitWidth: root.unit * 3.2
                        implicitHeight: implicitWidth
                        variant: "common"
                        color: Qt.alpha(Colors.primary, 0.14)
                        radius: Styling.radius(0)
                        StyledText {
                            anchors.centerIn: parent
                            text: Icons.notepad
                            font.family: Icons.font
                            font.pixelSize: Styling.fontSize(10)
                            color: Colors.primary
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.unit * 0.2
                        StyledText {
                            text: "Quick notes"
                            font.pixelSize: Styling.fontSize(3)
                            font.bold: true
                        }
                        StyledText {
                            text: "A little space for your thoughts"
                            color: Colors.overSurfaceVariant
                            font.pixelSize: Styling.fontSize(-2)
                        }
                    }
                    NotesAction {
                        glyph: Icons.check
                        label: "Save notes · Ctrl+S"
                        enabled: QuickNotes.ready && !QuickNotes.saving
                        onClicked: { QuickNotes.save(); editor.forceActiveFocus(); }
                    }
                    NotesAction {
                        glyph: Icons.cancel
                        label: "Close · Esc"
                        onClicked: QuickNotes.close()
                    }
                }

                StyledRect {
                    variant: "common"
                    radius: Styling.radius(0)
                    border.width: 1
                    border.color: Qt.alpha(Colors.primary, editor.activeFocus ? 0.35 : 0.12)
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ScrollView {
                        id: scroll
                        anchors.fill: parent
                        anchors.margins: root.unit
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            contentItem: StyledRect {
                                implicitWidth: root.unit * 0.25
                                variant: "common"
                                color: Qt.alpha(Colors.primary, parent.pressed ? 0.8 : 0.4)
                                radius: Styling.radius(0)
                            }
                            background: null
                        }

                        TextArea {
                            id: editor
                            text: QuickNotes.text
                            readOnly: !QuickNotes.ready
                            placeholderText: QuickNotes.ready ? "Write something down…" : "Loading notes…"
                            color: Colors.overBackground
                            placeholderTextColor: Qt.alpha(Colors.overSurfaceVariant, 0.65)
                            selectionColor: Colors.primary
                            selectedTextColor: Colors.overPrimary
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            selectByMouse: true
                            renderType: Text.NativeRendering
                            leftPadding: root.unit * 0.3
                            rightPadding: root.unit * 0.3
                            topPadding: root.unit * 0.3
                            bottomPadding: root.unit
                            background: null
                            onTextChanged: QuickNotes.edit(text)
                            Keys.onEscapePressed: event => {
                                QuickNotes.close();
                                event.accepted = true;
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                                    QuickNotes.save();
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.unit * 0.5
                    StyledText {
                        text: QuickNotes.error ? Icons.alert
                            : QuickNotes.dirty || QuickNotes.saving ? Icons.edit : Icons.check
                        font.family: Icons.font
                        color: root.statusColor
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: QuickNotes.error || (QuickNotes.saving ? "Saving…"
                            : QuickNotes.dirty ? "Unsaved changes" : "All notes saved")
                        color: root.statusColor
                        font.pixelSize: Styling.fontSize(-2)
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        visible: !QuickNotes.error
                        text: "ESC to close"
                        color: Colors.overSurfaceVariant
                        font.pixelSize: Styling.fontSize(-2)
                    }
                }
            }
        }
    }

}
