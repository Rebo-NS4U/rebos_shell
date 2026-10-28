pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

SettingsGroup {
    id: root
    title: "Desktop blur"
    description: "Choose where glass blur appears. Less blur can reduce GPU use during video playback. Changes apply immediately."
    GridLayout {
        Layout.fillWidth: true
        columns: root.width < Styling.fontSize(0) * 30 ? 1 : 2
        columnSpacing: 12
        rowSpacing: 12
        Repeater {
            model: [
                {mode: "light", label: "Lighter glass", detail: "Softer blur across apps and shell panels, with fewer blur passes."},
                {mode: "shell", label: "Shell panels only", detail: "Keep blur on the bar and shell menus. Remove blur from app windows."},
                {mode: "off", label: "Blur off", detail: "Remove blur everywhere for the lowest blur rendering cost. Transparency stays as configured."},
                {mode: "medium", label: "Full glass", detail: "The original medium blur across apps and shell panels."}
            ]
            delegate: SettingsSectionCard {
                required property var modelData
                objectName: "desktop-blur-" + modelData.mode
                text: modelData.label
                description: modelData.detail
                selected: Config.performance.desktopBlur === modelData.mode
                onClicked: Config.performance.desktopBlur = modelData.mode
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: DesktopBlur.error || (DesktopBlur.busy ? "Applying blur settings…" : "Your selection is saved automatically.")
        color: DesktopBlur.error ? Colors.error : Colors.overSurfaceVariant
        font.pixelSize: Styling.fontSize(-1)
    }
}
