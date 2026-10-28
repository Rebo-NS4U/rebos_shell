import QtQuick
import QtQuick.Controls
import qs.config
import qs.modules.components
import qs.modules.theme

Button {
    id: root
    implicitHeight: Math.max(Styling.fontSize(0) * 3, implicitContentHeight + padding * 2)
    padding: 12
    font.family: Config.theme.font
    font.pixelSize: Styling.fontSize(-1)
    background: StyledRect {
        variant: root.hovered || root.down ? "focus" : "common"
        radius: Styling.radius(-4)
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Colors.primary : Qt.alpha(Colors.outline, 0.3)
    }
    contentItem: StyledText {
        text: root.text
        color: root.enabled ? Colors.overSurface : Colors.overSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font: root.font
    }
}
