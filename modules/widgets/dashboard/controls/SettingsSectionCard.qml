pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.components
import qs.modules.theme

Button {
    id: root
    property string description: ""
    property string glyph: ""
    property bool selected: false
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    implicitHeight: Math.max(Styling.fontSize(0) * 9, contentItem.implicitHeight + padding * 2)
    padding: 16
    hoverEnabled: true
    background: StyledRect {
        variant: root.hovered || root.down ? "focus" : "common"
        radius: Styling.radius(-2)
        border.width: root.activeFocus || root.selected ? 2 : 1
        border.color: root.activeFocus || root.selected ? Colors.primary : Qt.alpha(Colors.outline, 0.3)
    }
    contentItem: ColumnLayout {
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                visible: root.glyph.length > 0
                text: root.glyph
                font.family: Icons.font
                font.pixelSize: Styling.fontSize(6)
                color: Colors.primary
            }
            StyledText {
                Layout.fillWidth: true
                text: root.text
                font.bold: true
                wrapMode: Text.WordWrap
            }
            StyledText { text: Icons.caretRight; font.family: Icons.font; color: Colors.overSurfaceVariant }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.description
            wrapMode: Text.WordWrap
            color: Colors.overSurfaceVariant
            font.pixelSize: Styling.fontSize(-1)
        }
    }
}
