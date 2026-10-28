pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.bar
import qs.modules.services
import qs.modules.theme
import qs.modules.components
import qs.config

RowLayout {
    id: root

    required property Item bar

    Layout.alignment: Qt.AlignVCenter
    spacing: 2

    readonly property string iconFont: "Material Symbols Rounded"

    // ═══════════════════════════════════════════════════════════════
    // 1. BRIGHTNESS DYNAMIC ICON (7 Granular States)
    // ═══════════════════════════════════════════════════════════════
    Item {
        id: brightBtn
        objectName: "bar-brightness"
        implicitWidth: root.bar.islandHeight - 4
        implicitHeight: root.bar.islandHeight - 4
        Layout.alignment: Qt.AlignVCenter

        readonly property var currentMonitor: Brightness.getMonitorForScreen(root.bar.screen)
        readonly property real brightnessVal: currentMonitor?.brightness ?? 0.5

        readonly property string iconGlyph: {
            if (brightnessVal <= 0.08) return "nightlight";
            if (brightnessVal <= 0.22) return "brightness_low";
            if (brightnessVal <= 0.40) return "brightness_medium";
            if (brightnessVal <= 0.58) return "brightness_high";
            if (brightnessVal <= 0.76) return "brightness_7";
            if (brightnessVal <= 0.90) return "sunny";
            return "light_mode";
        }

        readonly property color iconColor: BarAppearance.iconColor

        StyledRect {
            anchors.fill: parent
            radius: height / 2
            variant: "focus"
            opacity: brightMouse.containsMouse ? 1 : 0
            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Math.min(Config.animDuration, 150); easing.type: Easing.OutCubic }
            }
            scale: brightMouse.pressed ? 0.92 : 1.0
            Behavior on scale {
                NumberAnimation {
                    duration: Config.animDuration > 0 ? Math.min(Config.animDuration, brightMouse.pressed ? 80 : 160) : 0
                    easing.type: Easing.OutCubic
                }
            }
        }

        DynamicSunIcon {
            anchors.centerIn: parent
            size: 18
            value: brightBtn.brightnessVal
            color: brightBtn.iconColor
            animated: true
        }

        ScrollStepHandler {
            onStepped: steps => {
                const delta = steps * 0.05;
                const newVal = Math.max(0.05, Math.min(1.0, brightBtn.brightnessVal + delta));
                if (Brightness.syncBrightness) {
                    for (let i = 0; i < Brightness.monitors.length; i++) {
                        const m = Brightness.monitors[i];
                        if (m?.ready) m.setBrightness(newVal);
                    }
                } else if (brightBtn.currentMonitor?.ready) {
                    brightBtn.currentMonitor.setBrightness(newVal);
                }
            }
        }

        MouseArea {
            id: brightMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    NightLightService.toggle();
                else
                    root.bar.expand("dashboard");
            }
        }

        StyledToolTip {
            show: brightMouse.containsMouse
            tooltipText: "Brightness " + Math.round(brightBtn.brightnessVal * 100) + "%"
            description: "Scroll to adjust · Click for controls · Right-click for night light"
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // 2. VOLUME DYNAMIC ICON (6 Granular States)
    // ═══════════════════════════════════════════════════════════════
    Item {
        id: volBtn
        objectName: "bar-volume"
        implicitWidth: root.bar.islandHeight - 4
        implicitHeight: root.bar.islandHeight - 4
        Layout.alignment: Qt.AlignVCenter

        readonly property var audioDevice: Audio.sink?.audio ?? null
        readonly property real volumeVal: audioDevice?.volume ?? 0
        readonly property bool isMuted: audioDevice?.muted ?? false

        readonly property string iconGlyph: {
            if (isMuted) return "volume_off";
            if (volumeVal < 0.01) return "volume_mute";
            if (volumeVal < 0.33) return "volume_mute";
            if (volumeVal < 0.66) return "volume_down";
            return "volume_up";
        }

        readonly property color iconColor: BarAppearance.iconColor

        StyledRect {
            anchors.fill: parent
            radius: height / 2
            variant: "focus"
            opacity: volMouse.containsMouse ? 1 : 0
            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Math.min(Config.animDuration, 150); easing.type: Easing.OutCubic }
            }
            scale: volMouse.pressed ? 0.92 : 1.0
            Behavior on scale {
                NumberAnimation {
                    duration: Config.animDuration > 0 ? Math.min(Config.animDuration, volMouse.pressed ? 80 : 160) : 0
                    easing.type: Easing.OutCubic
                }
            }
        }

        BarSymbol {
            anchors.centerIn: parent
            size: 18
            symbol: volBtn.isMuted ? Icons.speakerSlash : (volBtn.volumeVal < 0.01 ? Icons.speakerNone : (volBtn.volumeVal <= 0.5 ? Icons.speakerLow : Icons.speakerHigh))
            color: volBtn.iconColor
        }

        ScrollStepHandler {
            onStepped: steps => {
                if (volBtn.audioDevice) {
                    const delta = steps * 0.05;
                    volBtn.audioDevice.volume = Math.max(0.0, Math.min(1.0, volBtn.volumeVal + delta));
                }
            }
        }

        MouseArea {
            id: volMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton) {
                    root.bar.expand("sound");
                } else {
                    if (volBtn.audioDevice) {
                        volBtn.audioDevice.muted = !volBtn.audioDevice.muted;
                    }
                }
            }
        }

        StyledToolTip {
            show: volMouse.containsMouse
            tooltipText: (volBtn.isMuted ? "Muted " : "Volume ") + Math.round(volBtn.volumeVal * 100) + "%"
            description: "Scroll to adjust · Click for sound · Right-click to mute"
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // 3. BATTERY DYNAMIC ICON (Plug Icon on Charging + 9 Levels)
    // ═══════════════════════════════════════════════════════════════
    Item {
        id: batBtn
        visible: Battery.available
        implicitWidth: root.bar.islandHeight - 4
        implicitHeight: root.bar.islandHeight - 4
        Layout.alignment: Qt.AlignVCenter

        readonly property int percent: Battery.percent
        readonly property bool charging: Battery.charging

        readonly property color iconColor: BarAppearance.iconColor

        StyledRect {
            anchors.fill: parent
            radius: height / 2
            variant: "focus"
            opacity: batMouse.containsMouse ? 1 : 0
            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation { duration: Math.min(Config.animDuration, 150); easing.type: Easing.OutCubic }
            }
            scale: batMouse.pressed ? 0.92 : 1.0
            Behavior on scale {
                NumberAnimation {
                    duration: Config.animDuration > 0 ? Math.min(Config.animDuration, batMouse.pressed ? 80 : 160) : 0
                    easing.type: Easing.OutCubic
                }
            }
        }

        DynamicBatteryIcon {
            anchors.centerIn: parent
            size: 18
            percent: batBtn.percent
            charging: batBtn.charging
            color: batBtn.iconColor
            animated: true
        }

        MouseArea {
            id: batMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.bar.expand("battery")
        }

        StyledToolTip {
            show: batMouse.containsMouse
            tooltipText: `${batBtn.percent}%${batBtn.charging ? " (Charging)" : ""}`
            description: "Click for battery and power"
        }
    }
}
