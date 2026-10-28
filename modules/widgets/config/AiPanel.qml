import QtQuick
import Quickshell
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config
import qs.modules.widgets.dashboard.controls

Item {
    id: root

    property int maxContentWidth: 760
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: Math.max(0, (width - contentWidth) / 2)

    Flickable {
        anchors.fill: parent
        contentHeight: contentColumn.implicitHeight + 40
        clip: true
        bottomMargin: 40

        ColumnLayout {
            id: contentColumn
            width: root.contentWidth
            x: root.sideMargin
            spacing: 12

            PanelTitlebar {
                title: "Assistant"
                description: "Independent assistant app and working folder."
            }

            StyledText {
                Layout.fillWidth: true
                text: "Uses your existing Codex login."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.outline
                wrapMode: Text.Wrap
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 64
                variant: "common"
                radius: Styling.radius(-2)
                border.width: 1
                border.color: Qt.alpha(Colors.outline, 0.3)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Enable assistant"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(1)
                            font.weight: Font.Bold
                            color: Colors.overSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "Start the assistant when needed."
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.outline
                            wrapMode: Text.Wrap
                        }
                    }

                    StyledSwitch {
                        id: aiEnabledSwitch
                        checked: Config.ai.enabled ?? true
                        onToggled: Config.ai.enabled = checked


                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !(Config.ai.enabled ?? true)
                text: "AI is disabled. Codex will not start."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.outline
                wrapMode: Text.Wrap
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: workingDirectoryColumn.implicitHeight + 32
                variant: "common"
                radius: Styling.radius(-2)
                border.width: 1
                border.color: Qt.alpha(Colors.outline, 0.3)
                enabled: Config.ai.enabled ?? true
                opacity: enabled ? 1 : 0.5

                ColumnLayout {
                    id: workingDirectoryColumn
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    StyledText {
                        text: "Working folder"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(1)
                        font.weight: Font.Bold
                        color: Colors.overSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "New chats start in this folder. Leave empty to use your home folder."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.outline
                        wrapMode: Text.Wrap
                    }

                    SettingsTextField {
                        id: workingDirectoryInput
                        Layout.fillWidth: true
                        text: Config.ai && Config.ai.workingDirectory ? Config.ai.workingDirectory : ""
                        placeholderText: "~/code/project"
                        color: Colors.overSurface
                        font.family: Config.theme.font
                        onEditingFinished: {
                            if (Config.ai && Config.ai.workingDirectory !== text)
                                Config.setAiWorkingDirectory(text);
                        }


                    }
                }
            }

            SettingsButton {
                text: "Open assistant"
                enabled: Config.ai.enabled ?? true
                onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/rebos-assistant"])
            }
        }
    }
}
