pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 760
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    property bool showOutput: true  // true = output, false = input

    // Scrollable content - fills entire width for scroll/drag
    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: contentColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: contentColumn
            width: flickable.width
            spacing: 8

            // Header wrapper
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titlebar.height

                PanelTitlebar {
                    id: titlebar
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    title: "Sound"
            description: "Choose audio devices and adjust volume."

                    actions: [
                        {
                            icon: Audio.protectionEnabled ? Icons.shieldCheck : Icons.shield,
                            tooltip: Audio.protectionEnabled ? "Volume protection enabled" : "Volume protection disabled",
                            onClicked: function () {
                                Audio.setProtectionEnabled(!Audio.protectionEnabled);
                            }
                        },
                        {
                            icon: Icons.popOpen,
                            tooltip: "Open PipeWire Volume Control",
                            onClicked: function () {
                                Quickshell.execDetached(["pavucontrol"]);
                            }
                        }
                    ]


                }
            }

            // Content wrapper - centered
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: innerContent.implicitHeight

                ColumnLayout {
                    id: innerContent
                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    GridLayout {
                        Layout.fillWidth: true
                        columns: root.contentWidth < Styling.fontSize(0) * 30 ? 1 : 2
                        columnSpacing: 12
                        rowSpacing: 12
                        SettingsSectionCard {
                            text: "Output"
                            description: "Speakers and headphones."
                            glyph: Icons.speakerHigh
                            selected: root.showOutput
                            onClicked: root.showOutput = true
                        }
                        SettingsSectionCard {
                            text: "Input"
                            description: "Microphones and recording."
                            glyph: Icons.mic
                            selected: !root.showOutput
                            onClicked: root.showOutput = false
                        }
                    }

                    // Section: Devices
                    StyledText {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        text: root.showOutput ? "Output Device" : "Input Device"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overSurfaceVariant
                    }

                    // Device list
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: root.showOutput ? Audio.outputDevices : Audio.inputDevices

                            delegate: AudioDeviceItem {
                                required property var modelData
                                Layout.fillWidth: true
                                node: modelData
                                isOutput: root.showOutput
                                isSelected: (root.showOutput ? Audio.sink : Audio.source) === modelData
                            }
                        }
                    }

                    // Separator
                    Separator {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 2
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                    }

                    // Section: Volume Mixer
                    StyledText {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        text: "Volume Mixer"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overSurfaceVariant
                    }

                    // Main volume control
                    AudioVolumeEntry {
                        Layout.fillWidth: true
                        node: root.showOutput ? Audio.sink : Audio.source
                        icon: root.showOutput ? Icons.speakerHigh : Icons.mic
                        isMainDevice: true
                    }

                    // App volume controls
                    Repeater {
                        model: root.showOutput ? Audio.outputAppNodes : Audio.inputAppNodes

                        delegate: AudioVolumeEntry {
                            required property var modelData
                            Layout.fillWidth: true
                            node: modelData
                            isMainDevice: false
                        }
                    }

                    // Empty state for apps
                    StyledText {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        visible: (root.showOutput ? Audio.outputAppNodes : Audio.inputAppNodes).length === 0
                        text: "No applications using audio"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.outline
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 16
                    }
                }
            }
        }
    }
}
