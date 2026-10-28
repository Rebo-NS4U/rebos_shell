pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.components
import qs.modules.services
import qs.modules.theme

CircularBarMeter {
    id: root

    readonly property var currentMonitor: Brightness.getMonitorForScreen(bar.screen)

    value: currentMonitor?.brightness ?? 0.5
    icon: Icons.sun
    progressColor: Styling.srItem("overprimary")
    tooltipText: "Brightness " + Math.round(value * 100) + "%"
    clickEnabled: true
    tooltipDescription: "Scroll to adjust · Click for controls · Right-click for night light"
    onActivated: brightnessPopup.toggle()
    onSecondaryActivated: NightLightService.toggle()

    BarPopup {
        id: brightnessPopup
        anchorItem: root
        contentWidth: controls.implicitWidth
        contentHeight: controls.implicitHeight
        ColumnLayout {
            id: controls
            width: implicitWidth
            spacing: Styling.fontSize(0)
            StyledText { text: "Brightness · " + Math.round(root.value * 100) + "%" }
            StyledSlider {
                Layout.preferredWidth: Styling.fontSize(0) * 18
                Layout.preferredHeight: Styling.fontSize(0) * 1.5
                size: Styling.fontSize(0) * 18
                value: root.value
                onValueChanged: {
                    if (Math.abs(value - root.value) > 0.01)
                        root.adjusted(Math.max(0.05, value));
                }
            }
        }
    }

    onAdjusted: newValue => {
        if (Brightness.syncBrightness) {
            for (let i = 0; i < Brightness.monitors.length; i++) {
                const monitor = Brightness.monitors[i];
                if (monitor?.ready)
                    monitor.setBrightness(newValue);
            }
        } else if (currentMonitor?.ready) {
            currentMonitor.setBrightness(newValue);
        }
    }
}
