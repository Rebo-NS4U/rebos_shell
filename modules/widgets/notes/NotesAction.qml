pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.components
import qs.modules.theme

Button {
    id: action
    readonly property real unit: Styling.fontSize(0)
    required property string glyph
    required property string label
    implicitWidth: action.unit * 2.5
    implicitHeight: implicitWidth
    hoverEnabled: true
    Accessible.name: label
    scale: pressed ? 0.93 : 1
    background: StyledRect {
        variant: action.hovered || action.activeFocus ? "focus" : "common"
        radius: Styling.radius(0)
        border.width: action.activeFocus ? 1 : 0
        border.color: Colors.primary
    }
    contentItem: StyledText {
        text: action.glyph
        font.family: Icons.font
        font.pixelSize: Styling.fontSize(3)
        color: action.hovered || action.activeFocus ? Colors.primary : Colors.overSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    StyledToolTip {
        show: action.hovered
        tooltipText: action.label
    }
}
