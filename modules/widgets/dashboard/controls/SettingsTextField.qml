import QtQuick
import QtQuick.Controls
import qs.config
import qs.modules.components
import qs.modules.theme

TextField {
    id: root
    implicitHeight: Styling.fontSize(0) * 3
    padding: 12
    font.family: Config.theme.font
    font.pixelSize: Styling.fontSize(0)
    color: Colors.overSurface
    placeholderTextColor: Colors.overSurfaceVariant
    selectionColor: Colors.primary
    selectedTextColor: Colors.overPrimary
    selectByMouse: true
    background: StyledRect {
        variant: "internalbg"
        radius: Styling.radius(-4)
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Colors.primary : Qt.alpha(Colors.outline, 0.3)
    }
}
