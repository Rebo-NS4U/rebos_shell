pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.components
import qs.modules.theme

StyledRect {
    id: root
    required property string text
    signal clicked()
    implicitHeight: label.implicitHeight + 16
    implicitWidth: label.implicitWidth + 24
    variant: mouse.containsMouse ? "focus" : "common"
    radius: Styling.radius(2)
    opacity: enabled ? 1 : 0.45
    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: Styling.fontSize(-2)
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
