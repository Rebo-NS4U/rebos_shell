pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.theme

SettingsGroup {
    id: root
    title: "Motion"
    description: "Gentle panel transitions and quick feedback across the shell. Off makes transitions immediate."

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [ { label: "Smooth", ms: 300 }, { label: "Quick", ms: 180 }, { label: "Off", ms: 0 } ]
            delegate: SettingsButton {
                required property var modelData
                objectName: "motion-" + modelData.label.toLowerCase()
                Layout.fillWidth: true
                text: modelData.label
                checkable: true
                checked: Config.theme.animDuration === modelData.ms
                onClicked: Config.theme.animDuration = modelData.ms
                background: StyledRect {
                    variant: parent.checked || parent.hovered ? "focus" : "common"
                    radius: Styling.radius(-4)
                    border.width: parent.checked || parent.activeFocus ? 2 : 1
                    border.color: parent.checked || parent.activeFocus ? Colors.primary : Qt.alpha(Colors.outline, 0.3)
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        StyledText { text: "Duration" }
        StyledSlider {
            id: durationSlider
            objectName: "motion-duration"
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            tooltipText: Math.round(value * 1000) + " ms"
            stepSize: 0.01
            snapMode: "always"
            smoothDrag: false
            property bool ready: false
            readonly property real configValue: Config.theme.animDuration / 1000
            onConfigValueChanged: value = configValue
            Component.onCompleted: { value = configValue; ready = true; }
            onValueChanged: {
                const duration = Math.round(value * 1000);
                if (ready && duration !== Config.theme.animDuration)
                    Config.theme.animDuration = duration;
            }
        }
        StyledText {
            text: Motion.enabled ? Config.theme.animDuration + " ms" : "Off"
            Layout.preferredWidth: Styling.fontSize(0) * 4.5
            horizontalAlignment: Text.AlignRight
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: "Opening, closing, selection and button timings scale together."
        wrapMode: Text.WordWrap
        color: Colors.overSurfaceVariant
        font.pixelSize: Styling.fontSize(-1)
    }
}
