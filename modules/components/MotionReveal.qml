pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

// Keep painted content alive during exit; input follows the logical state.
// Animate from the current progress so a quick reversal never jumps.
Item {
    id: root
    property bool open: false
    property real direction: -1
    property bool horizontal: false
    property real progress: open ? 1 : 0
    visible: open || progress > 0
    enabled: open
    opacity: progress
    transform: Translate {
        x: root.horizontal ? root.direction * Motion.offset * (1 - root.progress) : 0
        y: root.horizontal ? 0 : root.direction * Motion.offset * (1 - root.progress)
    }
    Behavior on progress {
        enabled: Motion.enabled
        NumberAnimation {
            id: transition
            duration: root.open ? Motion.enter : Motion.exit
            easing.type: root.open ? Motion.enterCurve : Motion.exitCurve
        }
    }
    Connections {
        target: Motion
        function onEnabledChanged() {
            if (!Motion.enabled) {
                transition.stop();
                // Disabling a Behavior can leave the last painted value behind.
                // Refresh the binding so Off also settles an interrupted reveal.
                root.progress = Qt.binding(() => root.open ? 1 : 0);
            }
        }
    }
}
