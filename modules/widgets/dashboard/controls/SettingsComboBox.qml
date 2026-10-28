pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config
import qs.modules.components
import qs.modules.theme

ComboBox {
    id: root
    implicitHeight: Styling.fontSize(0) * 3
    leftPadding: 12
    rightPadding: 36
    font.family: Config.theme.font
    font.pixelSize: Styling.fontSize(-1)
    background: StyledRect {
        variant: root.hovered ? "focus" : "internalbg"
        radius: Styling.radius(-4)
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Colors.primary : Qt.alpha(Colors.outline, 0.3)
    }
    contentItem: StyledText {
        text: root.displayText
        color: root.enabled ? Colors.overSurface : Colors.overSurfaceVariant
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font: root.font
    }
    indicator: StyledText {
        x: root.width - width - 12
        anchors.verticalCenter: parent.verticalCenter
        text: Icons.caretDown
        font.family: Icons.font
        color: Colors.overSurfaceVariant
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: root.width - 12
        implicitHeight: Math.max(Styling.fontSize(0) * 3, implicitContentHeight + padding * 2)
        padding: 12
        highlighted: root.highlightedIndex === index
        contentItem: StyledText {
            text: root.textRole ? String(option.modelData[root.textRole] ?? "") : String(option.modelData)
            elide: Text.ElideRight
            color: Colors.overSurface
        }
        background: StyledRect { variant: option.highlighted ? "focus" : "common"; radius: Styling.radius(-4) }
    }
    popup: Popup {
        y: root.height + 6
        width: root.width
        padding: 6
        implicitHeight: Math.min(contentItem.implicitHeight + padding * 2, Styling.fontSize(0) * 20)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: StyledRect { variant: "popup"; radius: Styling.radius(-2) }
    }
}
