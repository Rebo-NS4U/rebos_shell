pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.config

ColumnLayout {
    id: root
    property string title: ""
    property string description: ""
    property string statusText: ""
    property color statusColor: Styling.srItem("overprimary")
    property bool showToggle: false
    property bool toggleChecked: false

    // Action buttons configuration
    // Each action: { icon: "...", tooltip: "...", onClicked: function, enabled: true, loading: false }
    property list<var> actions: []

    // Custom content slot (appears between spacer and actions)
    default property alias customContent: customContentContainer.data

    signal toggleChanged(bool checked)

    readonly property int horizontalMargin: 12
    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    spacing: 8
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: Styling.fontSize(0) * 3.5
        spacing: 8
        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: implicitWidth
            Layout.minimumWidth: 0
            leftPadding: root.horizontalMargin
            text: root.title
            font.pixelSize: Styling.fontSize(6)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        StyledText {
            visible: root.statusText.length > 0
            Layout.maximumWidth: implicitWidth
            Layout.minimumWidth: 0
            Layout.fillWidth: true
            text: root.statusText
            font.pixelSize: Styling.fontSize(-2)
            color: root.statusColor
            elide: Text.ElideRight
        }
        Item { Layout.fillWidth: true }
        Item {
            id: customContentContainer
            Layout.preferredWidth: childrenRect.width
            Layout.preferredHeight: childrenRect.height
            visible: children.length > 0
        }
        Repeater {
            model: root.actions
            delegate: Button {
                id: actionButton
                required property var modelData
                required property int index
                readonly property bool isLoading: modelData.loading ?? false
                implicitWidth: Styling.fontSize(0) * 2.5
                implicitHeight: implicitWidth
                enabled: (modelData.enabled ?? true) && !isLoading
                background: StyledRect {
                    variant: actionButton.hovered ? "focus" : "common"
                    radius: Styling.radius(-4)
                }
                contentItem: StyledText {
                    text: actionButton.modelData.icon || ""
                    font.family: Icons.font
                    font.pixelSize: Styling.fontSize(2)
                    color: actionButton.enabled ? Colors.overSurface : Colors.outline
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    RotationAnimation on rotation {
                        running: actionButton.isLoading
                        from: 0; to: 360
                        duration: Math.max(1, Config.animDuration * 4)
                        loops: Animation.Infinite
                    }
                }
                onClicked: { if (modelData.onClicked) modelData.onClicked(); }
                StyledToolTip {
                    show: actionButton.hovered && (actionButton.modelData.tooltip || "").length > 0
                    tooltipText: actionButton.modelData.tooltip || ""
                }
            }
        }
        StyledSwitch {
            objectName: "settings-page-toggle"
            visible: root.showToggle
            checked: root.toggleChecked
            onToggled: root.toggleChanged(checked)
        }
        Item { Layout.preferredWidth: root.horizontalMargin }
    }
    StyledText {
        visible: root.description.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: root.horizontalMargin
        Layout.rightMargin: root.horizontalMargin
        Layout.bottomMargin: 12
        text: root.description
        wrapMode: Text.WordWrap
        color: Colors.overSurfaceVariant
        font.pixelSize: Styling.fontSize(-1)
    }
}
