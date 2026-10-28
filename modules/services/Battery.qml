pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Services.UPower
import qs.modules.theme

Singleton {
    id: root

    readonly property UPowerDevice primaryDevice: UPower.displayDevice

    readonly property bool available: primaryDevice !== null && primaryDevice.type === UPowerDevice.Battery
    readonly property real percentage: available ? (primaryDevice.percentage * 100) : 0
    readonly property bool isCharging: available && primaryDevice.state === UPowerDevice.Charging
    readonly property bool isPluggedIn: available && !UPower.onBattery
    readonly property real percent: percentage
    readonly property bool charging: isPluggedIn
    readonly property int chargeState: available ? primaryDevice.state : UPowerDevice.Unknown
    property int lastBatteryAlertThreshold: 0

    // Add some helpful descriptive properties if needed
    readonly property string timeToEmpty: available && primaryDevice.timeToEmpty > 0 ? formatTime(primaryDevice.timeToEmpty) : ""
    readonly property string timeToFull: available && primaryDevice.timeToFull > 0 ? formatTime(primaryDevice.timeToFull) : ""

    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    function getBatteryIcon() {
        if (!available) return Icons.batteryEmpty;
        if (isPluggedIn) return Icons.batteryCharging;
        
        const pct = percentage;
        if (pct > 75) return Icons.batteryFull;
        if (pct > 50) return Icons.batteryHigh;
        if (pct > 25) return Icons.batteryMedium;
        if (pct > 5) return Icons.batteryLow;
        return Icons.batteryEmpty;
    }

    // Interpolated charge color: red (<=15%) through green (>=85%).
    // Shared by the default bar indicator and the island.
    function statusColor() {
        if (!root.available)
            return Colors.overBackground;
        const pct = root.percentage;
        if (pct <= 15)
            return Colors.red;
        if (pct >= 85)
            return Colors.green;
        const ratio = (pct - 15) / (85 - 15);
        return Qt.rgba(Colors.red.r + (Colors.green.r - Colors.red.r) * ratio, Colors.red.g + (Colors.green.g - Colors.red.g) * ratio, Colors.red.b + (Colors.green.b - Colors.red.b) * ratio, 1);
    }

    function evaluateBatteryAlert() {
        if (!available || isPluggedIn) {
            lastBatteryAlertThreshold = 0;
            clearBatteryAlert();
            return;
        }

        // Rearm only after recovery, so noisy readings cannot repeat a warning.
        if (percentage > 22) {
            lastBatteryAlertThreshold = 0;
            clearBatteryAlert();
            return;
        }

        const threshold = percentage <= 2 ? 2 : percentage <= 5 ? 5 : percentage <= 10 ? 10 : percentage <= 20 ? 20 : 0;
        if (threshold === 0 || (lastBatteryAlertThreshold !== 0 && threshold >= lastBatteryAlertThreshold)) {
            return;
        }

        sendBatteryAlert(threshold, Math.round(percentage));
        lastBatteryAlertThreshold = threshold;
    }

    function clearBatteryAlert() {
        const ids = Notifications.list.filter(notif => notif && notif.replaceKey === "battery-low-alert").map(notif => notif.id);
        if (ids.length > 0)
            Notifications.discardNotifications(ids);
    }

    function sendBatteryAlert(threshold, roundedPercentage) {
        const isCritical = threshold <= 5;
        const title = threshold <= 2 ? "Critical battery" : threshold <= 5 ? "Battery almost empty" : threshold <= 10 ? "Very low battery" : "Low battery";
        const advice = threshold <= 2 ? "Plug in now. Save your work immediately; power may run out at any moment."
            : threshold <= 5 ? "Connect your charger now and save your work."
            : threshold <= 10 ? "Connect your charger soon. Power saver can help you last longer."
            : "Consider connecting your charger or enabling power saver.";
        const remaining = timeToEmpty !== "" ? " About " + timeToEmpty + " remaining." : "";
        const actions = [];
        if (PowerProfile.currentProfile !== "power-saver")
            actions.push({ "identifier": "enable-power-saver", "text": "Enable power saver" });
        actions.push({ "identifier": "dismiss", "text": "Dismiss" });

        Notifications.notifyInternal({
            "appName": "Battery",
            "appIcon": isCritical ? "battery-empty-symbolic" : "battery-caution-symbolic",
            "summary": title + " · " + roundedPercentage + "%",
            "body": advice + remaining,
            "urgency": isCritical ? NotificationUrgency.Critical : NotificationUrgency.Normal,
            "historyPriority": 100,
            "replaceKey": "battery-low-alert",
            // Negative intervals keep critical warnings visible until dismissed.
            "expireTimeout": isCritical ? -1 : (threshold <= 10 ? 15000 : 10000),
            "actions": actions,
            "actionHandlers": {
                "enable-power-saver": function () {
                    PowerProfile.setProfile("power-saver");
                },
                "dismiss": function (id) {
                    Notifications.discardNotification(id);
                }
            }
        });
    }

    Connections {
        target: root

        function onPercentageChanged() {
            Qt.callLater(root.evaluateBatteryAlert);
        }

        function onIsPluggedInChanged() {
            Qt.callLater(root.evaluateBatteryAlert);
        }

        function onAvailableChanged() {
            Qt.callLater(root.evaluateBatteryAlert);
        }
    }

    Component.onCompleted: Qt.callLater(root.evaluateBatteryAlert)
}
