pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.modules.bar
import qs.modules.components
import qs.modules.theme

StyledRect {
    id: root
    variant: "common"
    implicitHeight: Styling.fontSize(0) * 6
    radius: Styling.radius(0)
    enableBorder: false

    StyledText {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Styling.fontSize(0)
        text: "Live preview"
        color: Colors.overSurfaceVariant
        font.pixelSize: Styling.fontSize(-2)
    }
    StyledRect {
        id: preview
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Styling.fontSize(0)
        width: Math.min(parent.width - Styling.fontSize(0) * 2, content.implicitWidth + Styling.fontSize(0) * 2)
        height: Styling.fontSize(0) * 2.6
        variant: "pane"
        backgroundOpacity: BarAppearance.panelOpacity(false)
        radius: height / 2
        border.width: BarAppearance.polished ? 1 : 0
        border.color: BarAppearance.panelBorder(false)
        StyledRect {
            anchors.fill: parent
            variant: "transparent"
            enableBorder: false
            radius: preview.radius
            color: BarAppearance.panelTint(false)
        }
        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: Styling.fontSize(0)
            StyledText { text: "Desktop"; color: Colors.overBackground; font.pixelSize: Styling.fontSize(-1) }
            StyledRect {
                variant: "transparent"
                enableBorder: false
                color: BarAppearance.clockTint(false)
                radius: height / 2
                implicitWidth: clock.implicitWidth + Styling.fontSize(0)
                implicitHeight: Styling.fontSize(0) * 1.9
                StyledText {
                    id: clock
                    anchors.centerIn: parent
                    text: Config.bar?.use12hFormat ? "10:24 am" : "10:24"
                    color: Colors.overBackground
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(-1)
                    font.bold: true
                }
            }
            StyledText { text: Icons.speakerHigh; font.family: Icons.font; color: Colors.overBackground }
            StyledText { text: Icons.batteryFull; font.family: Icons.font; color: Colors.overBackground }
        }
    }
}
