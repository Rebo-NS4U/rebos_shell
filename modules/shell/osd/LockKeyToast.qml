pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.config

Item {
    id: root

    property bool shown: false
    implicitWidth: Math.round(Styling.fontSize(0) * 22.5)
    implicitHeight: Math.round(Styling.fontSize(0) * 5.4)
    opacity: shown ? 1 : 0
    visible: opacity > 0
    transform: Translate { y: root.shown ? 0 : root.height * 0.15
        Behavior on y { NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutCubic } }
    }
    Behavior on opacity { NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutCubic } }

    StyledRect {
        anchors.fill: parent
        variant: "popup"
        radius: Styling.radius(20)
        border.width: 1
        border.color: KeyboardLocks.lastEnabled ? Colors.primary : Colors.outline

        RowLayout {
            anchors.fill: parent
            anchors.margins: (Styling.fontSize(0) * 12 / 14)
            spacing: (Styling.fontSize(0) * 12 / 14)

            StyledRect {
                variant: "internalbg"
                Layout.preferredWidth: (Styling.fontSize(0) * 44 / 14)
                Layout.preferredHeight: (Styling.fontSize(0) * 42 / 14)
                radius: Styling.radius(12)
                Text {
                    anchors.centerIn: parent
                    text: KeyboardLocks.keycap
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(KeyboardLocks.lastKey === "num" ? 2 : 8)
                    font.bold: true
                    color: KeyboardLocks.lastEnabled ? Colors.primary : Colors.overBackground
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: (Styling.fontSize(0) * 3 / 14)
                Text {
                    text: KeyboardLocks.label
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(1)
                    font.bold: true
                    color: Colors.overBackground
                }
                Text {
                    text: KeyboardLocks.description
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.overBackground
                    opacity: 0.72
                }
            }

            StyledRect {
                variant: "internalbg"
                Layout.preferredWidth: (Styling.fontSize(0) * 40 / 14)
                Layout.preferredHeight: (Styling.fontSize(0) * 26 / 14)
                radius: Styling.radius(8)
                Text {
                    anchors.centerIn: parent
                    text: KeyboardLocks.lastEnabled ? "ON" : "OFF"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    font.bold: true
                    color: KeyboardLocks.lastEnabled ? Colors.primary : Colors.overBackground
                }
            }
        }
    }
}
