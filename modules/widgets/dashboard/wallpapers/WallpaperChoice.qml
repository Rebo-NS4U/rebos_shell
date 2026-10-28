import QtQuick
import QtQuick.Controls
import qs.modules.components
import qs.modules.theme
import qs.config

// Match the inset, rounded controls used by wallpaper mode and scheme selectors.
ComboBox {
    id: control

    implicitHeight: 48
    implicitWidth: 180
    leftPadding: 12
    rightPadding: 32
    topPadding: 4
    bottomPadding: 4
    font.family: Config.theme.font
    font.pixelSize: Config.theme.fontSize

    background: StyledRect {
        variant: control.activeFocus ? "focus" : "pane"
        radius: Styling.radius(4)

        StyledRect {
            anchors.fill: parent
            anchors.margins: 4
            variant: "common"
            color: Colors.surfaceContainerLow
            radius: Styling.radius(0)
        }
    }

    contentItem: StyledText {
        text: control.displayText
        color: Colors.overSurface
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: StyledText {
        x: control.width - width - 12
        y: (control.height - height) / 2
        text: Icons.caretDown
        color: Colors.overSurface
        font.family: Icons.font
        font.pixelSize: Styling.fontSize(0)
    }

    delegate: ItemDelegate {
        id: choice
        required property int index
        required property var modelData
        width: control.popup.width - control.popup.leftPadding - control.popup.rightPadding
        height: 38
        highlighted: control.highlightedIndex === index
        hoverEnabled: true

        background: StyledRect {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            variant: choice.highlighted || choice.hovered ? "primary" : "transparent"
            radius: Styling.radius(-14)
        }
        contentItem: StyledText {
            text: choice.modelData[control.textRole] ?? ""
            color: choice.highlighted || choice.hovered ? Styling.srItem("primary") : Colors.overSurface
            font.family: control.font.family
            font.pixelSize: control.font.pixelSize
            font.weight: choice.highlighted || choice.hovered ? Font.Bold : Font.Normal
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    popup: Popup {
        y: control.height + 4
        width: control.width
        padding: 4
        implicitHeight: Math.min(320, popupList.contentHeight) + topPadding + bottomPadding

        background: StyledRect {
            variant: "popup"
            radius: Styling.radius(-12)
        }
        contentItem: ListView {
            id: popupList
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        onOpened: popupList.positionViewAtIndex(control.currentIndex, ListView.Contain)
    }
}
