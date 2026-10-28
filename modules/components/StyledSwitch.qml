pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config
import qs.modules.theme

Switch {
    id: root
    background: null
    indicator: Rectangle {
        implicitWidth: Styling.fontSize(0) * 2.85
        implicitHeight: Styling.fontSize(0) * 1.43
        x: root.leftPadding
        y: root.height / 2 - height / 2
        radius: height / 2
        color: root.checked ? Colors.primary : Colors.surfaceBright
        border.color: root.activeFocus ? Colors.primary : (root.checked ? Colors.primary : Colors.outline)
        border.width: root.activeFocus ? 2 : 1
        opacity: root.enabled ? 1 : 0.5
        Behavior on color {
            enabled: Config.animDuration > 0
            ColorAnimation { duration: Motion.feedback }
        }
        Rectangle {
            x: root.checked ? parent.width - width - 2 : 2
            y: 2
            width: parent.height - 4
            height: width
            radius: width / 2
            color: root.checked ? Colors.overPrimary : Colors.overSurfaceVariant
            Behavior on x {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Motion.feedback; easing.type: Easing.OutCubic }
            }
        }
    }
}
