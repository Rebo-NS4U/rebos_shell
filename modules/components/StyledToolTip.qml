pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import qs.config
import qs.modules.theme
import qs.modules.components

Basic.ToolTip {
    id: root
    objectName: "styled-tooltip"
    property string tooltipText: ""
    property string description: ""
    property bool show: false

    // Keep hover hints inside the shell surface, independent of the desktop control style.
    popupType: Popup.Item
    text: tooltipText
    delay: 1000
    timeout: -1
    visible: show && (tooltipText.trim().length > 0 || description.trim().length > 0)

    background: StyledRect {
        objectName: "styled-tooltip-background"
        variant: "popup"
        radius: Styling.radius(-8)
    }

    contentItem: ColumnLayout {
        spacing: 0

        StyledText {
            text: root.tooltipText
            visible: root.tooltipText.trim().length > 0
            color: Colors.overBackground
            font.pixelSize: Config.theme.fontSize
            font.weight: Font.Bold
            font.family: Config.theme.font
        }

        StyledText {
            text: root.description
            visible: root.description.trim().length > 0
            color: Colors.overBackground
            font.pixelSize: Config.theme.fontSize - 2
            font.family: Config.theme.font
        }
    }
}
