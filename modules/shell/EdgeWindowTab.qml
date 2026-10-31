pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.theme

// One step per pointer entry. Staying on the tab never walks through windows.
Item {
    id: root

    property bool leftSide: false
    readonly property real unit: Styling.fontSize(0)
    readonly property bool engaged: hover.containsMouse && visible && enabled
    property real lift: engaged ? 1 : 0
    signal activated()

    width: unit * 1.4
    height: unit * 5.1

    Behavior on lift {
        NumberAnimation {
            duration: Motion.enabled ? Motion.enter : 0
            easing.type: Easing.OutBack
            easing.overshoot: 1.4
        }
    }

    // A painted indicator, with a wider stationary target around it. Moving
    // the bar never moves the hover boundary or causes another activation.
    Rectangle {
        objectName: "edge-home-indicator"
        width: root.unit * 0.28
        height: root.unit * 4.2
        radius: width / 2
        color: Colors.primary
        opacity: 0.65 + root.lift * 0.3
        x: root.leftSide ? 0 : root.width - width
        anchors.verticalCenter: parent.verticalCenter
        transform: [
            Translate { x: (root.leftSide ? 1 : -1) * root.unit * 0.3 * root.lift },
            Scale { origin.x: root.unit * 0.14; origin.y: root.unit * 2.1; yScale: 1 + root.lift * 0.06 }
        ]
    }

    MouseArea {
        id: hover
        objectName: "edge-window-hover"
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
        Accessible.name: root.leftSide ? "Previous window: hover to switch" : "Next window: hover to switch"
        onEntered: dwell.restart()
        onExited: dwell.stop()
        onCanceled: dwell.stop()
    }

    Timer {
        id: dwell
        interval: 180
        repeat: false
        onTriggered: {
            if (root.visible && root.enabled && hover.containsMouse)
                root.activated();
        }
    }

    onVisibleChanged: { if (!visible) dwell.stop(); }
    onEnabledChanged: { if (!enabled) dwell.stop(); }
}
