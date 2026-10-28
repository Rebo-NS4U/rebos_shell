import QtQuick
import qs.config
import qs.modules.components
import qs.modules.theme

Item {
    id: root

    default property alias content: contentContainer.data

    readonly property real bgOpacity: Styling.shellStyle === "dithered"
        ? Styling.getStyledRectConfig("barbg").opacity : Config.theme.srBarBg.opacity
    readonly property bool backgroundVisible: Styling.shellStyle === "dithered"
        ? bgOpacity > 0 : Config.showBackground
    readonly property int padding: bgOpacity < 0.01 ? 0 : 4
    readonly property int outerMargin: 4

    StyledRect {
        anchors.fill: parent
        variant: "barbg"
        visible: root.backgroundVisible
        radius: Styling.radius(0)
        enableBorder: true
        enableShadow: false
    }

    Item {
        id: contentContainer
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
