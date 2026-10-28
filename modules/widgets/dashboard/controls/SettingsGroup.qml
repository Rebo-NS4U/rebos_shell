pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.components
import qs.modules.theme

StyledRect {
    id: root
    property string title: ""
    property string description: ""
    default property alias content: body.data
    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 32
    variant: "common"
    radius: Styling.radius(-2)
    border.width: 1
    border.color: Qt.alpha(Colors.outline, 0.3)
    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 12
        StyledText { visible: root.title.length > 0; text: root.title; font.bold: true }
        StyledText {
            visible: root.description.length > 0
            Layout.fillWidth: true
            text: root.description
            wrapMode: Text.WordWrap
            color: Colors.overSurfaceVariant
            font.pixelSize: Styling.fontSize(-1)
        }
        ColumnLayout { id: body; Layout.fillWidth: true; spacing: 12 }
    }
}
