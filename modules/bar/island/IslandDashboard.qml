pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.modules.bar.systray
import qs.config

Item {
    id: root
    objectName: "islandDashboard"

    property date currentDate: new Date()

    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        onTriggered: root.currentDate = new Date()
    }

    implicitWidth: 420
    implicitHeight: mainColumn.implicitHeight + 28

    signal openPower()
    signal openSound()
    signal openMic()
    signal openWifi()
    signal openBluetooth()
    signal openStats()
    signal openAlerts()
    signal openWallpapers()
    signal openBattery()
    signal openWeather()
    signal openMedia()
    signal openCalendar()

    property ShellScreen screen: null

    readonly property var currentMonitor: {
        if (root.screen)
            return Brightness.getMonitorForScreen(root.screen);
        const focused = NiriService.focusedMonitor;
        if (focused)
            return Brightness.getMonitorForScreen(focused);
        return Brightness.monitors.length > 0 ? Brightness.monitors[0] : null;
    }
    readonly property real brightnessVal: currentMonitor?.brightness ?? 0.5

    function setBrightness(val: real) {
        if (Brightness.syncBrightness) {
            for (let i = 0; i < Brightness.monitors.length; i++) {
                const m = Brightness.monitors[i];
                if (m?.ready) m.setBrightness(val);
            }
        } else if (currentMonitor?.ready) {
            currentMonitor.setBrightness(val);
        }
    }

    readonly property bool audioMuted: Audio.sink?.audio?.muted ?? false
    readonly property real audioVolume: Audio.sink?.audio?.volume ?? 0.0

    Component.onCompleted: {
        NetworkService.update();
        BluetoothService.updateStatus();
    }

    onVisibleChanged: {
        if (visible) {
            root.currentDate = new Date();
            NetworkService.update();
            BluetoothService.updateStatus();
        }
    }

    readonly property bool wifiConnected: NetworkService.wifiConnected
    readonly property string wifiSsid: NetworkService.activeSsid
    readonly property bool btConnected: BluetoothService.enabled && BluetoothService.connected
    readonly property string btDeviceName: {
        if (!btConnected) return "Bluetooth";
        if (BluetoothService.firstConnectedDeviceName) {
            return BluetoothService.firstConnectedDeviceName;
        }
        const list = BluetoothService.friendlyDeviceList;
        if (list) {
            for (let i = 0; i < list.length; i++) {
                if (list[i]?.connected && list[i]?.name) return list[i].name;
            }
        }
        return "Connected";
    }

    readonly property int alertsCount: {
        if (Notifications.silent) return 0;
        let count = 0;
        const list = Notifications.appNameList;
        for (let i = 0; i < list.length; i++) {
            const grp = Notifications.groupsByAppName[list[i]];
            if (grp?.notifications)
                count += grp.notifications.length;
        }
        return count;
    }

    // Dismiss open popup dropdown when clicking on empty space in the dashboard
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: {
            FocusGrabManager.clearTopGrab();
            Visibilities.closeActiveBarPopup();
        }
    }

    ColumnLayout {
        id: mainColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 14
        spacing: 10

        // ═══════════════════════════════════════════════════════════════
        // HEADER: CLOCK, WEATHER & UTILITIES
        // ═══════════════════════════════════════════════════════════════
        StyledRect {
            objectName: "dashboardOverview"
            Layout.fillWidth: true
            implicitHeight: Math.max(clockDateCol.implicitHeight, 54) + 28
            variant: "pane"
            radius: Styling.radius(4)
            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                Item {
                    id: clockDateBtn
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: clockDateCol.implicitHeight
                    scale: clockDateMouse.pressed ? 0.94 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: clockDateMouse.pressed ? Motion.press : Motion.feedback
                            easing.type: Motion.feedbackCurve
                            easing.overshoot: 1.4
                        }
                    }

                    ColumnLayout {
                        id: clockDateCol
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        StyledText {
                            id: clockText
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            text: Qt.formatTime(root.currentDate, Config.bar?.use12hFormat ? "h:mm ap" : "HH:mm")
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(14)
                            font.bold: true
                            color: clockDateMouse.containsMouse ? Colors.primary : Colors.overBackground

                            Behavior on color {
                                ColorAnimation { duration: Motion.feedback }
                            }
                        }

                        StyledText {
                            id: dateText
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            text: Qt.formatDate(root.currentDate, "dddd, d MMM")
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            color: clockDateMouse.containsMouse ? (Colors.primaryFixed ?? Colors.primary) : Colors.overSurfaceVariant
                            Layout.maximumWidth: clockDateBtn.width
                            elide: Text.ElideRight

                            Behavior on color {
                                ColorAnimation { duration: Motion.feedback }
                            }
                        }
                    }

                    MouseArea {
                        id: clockDateMouse
                        objectName: "dashboardClock"
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openCalendar()
                    }

                    StyledToolTip {
                        show: clockDateMouse.containsMouse
                        tooltipText: "Calendar & Time"
                    }
                }

                // Weather card
                StyledRect {
                    implicitHeight: 54
                    implicitWidth: weatherRow.implicitWidth + 24
                    radius: Styling.radius(3)
                    variant: weatherMouse.containsMouse ? "focus" : "internalbg"
                    scale: weatherMouse.pressed ? 0.92 : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: weatherMouse.pressed ? Motion.press : Motion.feedback
                            easing.type: Motion.feedbackCurve
                        }
                    }

                    RowLayout {
                        id: weatherRow
                        anchors.centerIn: parent
                        spacing: 6

                        StyledText {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            text: WeatherService.weatherSymbol || Icons.sun
                            font.family: Icons.font
                            font.pixelSize: Styling.fontSize(8)
                            color: Colors.yellow
                        }

                        StyledText {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            text: WeatherService.dataAvailable
                                ? Math.round(WeatherService.currentTemp) + "°" + Config.weather.unit
                                : "--°" + Config.weather.unit
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(3)
                            font.bold: true
                            color: weatherMouse.containsMouse ? Colors.primary : Colors.overBackground
                        }
                    }

                    MouseArea {
                        id: weatherMouse
                        objectName: "dashboardWeather"
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                WeatherService.updateWeather();
                            else
                                root.openWeather();
                        }
                    }
                    StyledToolTip {
                        show: weatherMouse.containsMouse
                        tooltipText: "Weather"
                        description: "Click for forecast · Right-click to refresh"
                    }
                }

            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Alerts / Notifications button
            StyledRect {
                implicitHeight: 36
                Layout.fillWidth: true
                Layout.minimumWidth: alertsRow.implicitWidth + 20
                radius: Styling.radius(2)
                variant: alertsMouse.containsMouse ? "focus" : "internalbg"
                scale: alertsMouse.pressed ? 0.92 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: alertsMouse.pressed ? Motion.press : Motion.feedback
                        easing.type: Motion.feedbackCurve
                    }
                }

                RowLayout {
                    id: alertsRow
                    anchors.centerIn: parent
                    spacing: 6

                    StyledText {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        text: Notifications.silent ? Icons.bellZ : Icons.bell
                        font.family: Icons.font
                        font.pixelSize: 15
                        color: Notifications.silent ? Colors.primary : Colors.overBackground
                    }

                    StyledText {
                        text: "Alerts"
                        font.pixelSize: Styling.fontSize(-1)
                    }

                    StyledRect {
                        visible: root.alertsCount > 0
                        implicitWidth: alertBadgeText.implicitWidth + 8
                        implicitHeight: 16
                        radius: 8
                        variant: "primary"

                        StyledText {
                            id: alertBadgeText
                            anchors.centerIn: parent
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            text: root.alertsCount > 99 ? "99+" : String(root.alertsCount)
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(-4)
                            font.bold: true
                            color: Colors.overPrimary
                        }
                    }
                }

                MouseArea {
                    id: alertsMouse
                    objectName: "dashboardAlerts"
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openAlerts()
                }
            }

            // Settings button
            StyledRect {
                implicitHeight: 36
                Layout.fillWidth: true
                Layout.minimumWidth: settingsLabel.implicitWidth + 44
                radius: Styling.radius(2)
                variant: settingsMouse.containsMouse ? "focus" : "internalbg"
                scale: settingsMouse.pressed ? 0.92 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: settingsMouse.pressed ? Motion.press : Motion.feedback
                        easing.type: Motion.feedbackCurve
                    }
                }

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    text: Icons.gear
                    font.family: Icons.font
                    font.pixelSize: 15
                    color: Colors.overBackground
                }

                StyledText {
                    id: settingsLabel
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 10
                    text: "Settings"
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overBackground
                }

                MouseArea {
                    id: settingsMouse
                    objectName: "dashboardSettings"
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Visibilities.closeActiveBarPopup();
                        GlobalStates.settingsWindowVisible = true;
                    }
                }
            }

            // Power Menu trigger button
            StyledRect {
                implicitHeight: 36
                Layout.fillWidth: true
                Layout.minimumWidth: powerLabel.implicitWidth + 44
                radius: Styling.radius(2)
                variant: powerMouse.containsMouse ? "error" : "internalbg"
                scale: powerMouse.pressed ? 0.92 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: powerMouse.pressed ? Motion.press : Motion.feedback
                        easing.type: Motion.feedbackCurve
                    }
                }

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 2
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    text: Icons.shutdown
                    font.family: Icons.font
                    font.pixelSize: 15
                    color: powerMouse.containsMouse ? Colors.overError : Colors.red
                }

                StyledText {
                    id: powerLabel
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 10
                    text: "Power"
                    font.pixelSize: Styling.fontSize(-1)
                    color: powerMouse.containsMouse ? Colors.overError : Colors.overBackground
                }

                MouseArea {
                    id: powerMouse
                    objectName: "dashboardPower"
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openPower()
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // CONNECTIONS: WI-FI & BLUETOOTH
        // ═══════════════════════════════════════════════════════════════
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // 1. Wi-Fi Capsule
            StyledRect {
                id: wifiCapsule
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: Styling.radius(3)
                readonly property bool isHovered: wifiMouse.containsMouse || wifiIconMouse.containsMouse
                variant: NetworkService.wifiEnabled ? (isHovered ? "primaryfocus" : "primary") : (isHovered ? "focus" : "internalbg")
                scale: (wifiMouse.pressed || wifiIconMouse.pressed) ? 0.94 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: (wifiMouse.pressed || wifiIconMouse.pressed) ? Motion.press : Motion.feedback
                        easing.type: (wifiMouse.pressed || wifiIconMouse.pressed) ? Easing.OutQuad : Motion.enterCurve
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    // Both halves open the menu; right-click toggles Wi-Fi.
                    Item {
                        implicitWidth: 26
                        implicitHeight: 26
                        Layout.alignment: Qt.AlignVCenter

                        StyledText {
                            anchors.centerIn: parent
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            text: {
                                if (!NetworkService.wifiEnabled) return Icons.wifiOff;
                                if (NetworkService.vpnConnected) return Icons.vpnKey;
                                return root.wifiConnected ? NetworkService.wifiIconForStrength(NetworkService.networkStrength) : Icons.wifiHigh;
                            }
                            font.family: Icons.font
                            font.pixelSize: 22
                            color: NetworkService.wifiEnabled ? Colors.overPrimary : Colors.overBackground
                        }

                        MouseArea {
                            id: wifiIconMouse
                            objectName: "dashboardWifiIcon"
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    Visibilities.closeActiveBarPopup();
                                    NetworkService.toggleWifi();
                                } else {
                                    root.openWifi();
                                }
                            }
                        }

                        StyledToolTip {
                            show: wifiIconMouse.containsMouse
                            tooltipText: "Wi-Fi"
                            description: "Click for networks · Right-click to toggle Wi-Fi"
                        }
                    }

                    // Middle: Divider
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 22
                        Layout.alignment: Qt.AlignVCenter
                        color: NetworkService.wifiEnabled ? Styling.withOpacity(Colors.overPrimary, 0.18) : Styling.withOpacity(Colors.overSurface, 0.15)
                    }

                    // Right: Text (click opens Wi-Fi panel)
                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 3
                            StyledText {
                                text: "Wi-Fi"
                                font.pixelSize: Styling.fontSize(-2)
                                color: NetworkService.wifiEnabled ? Colors.overPrimary : Colors.overSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferFullHinting
                                text: root.wifiConnected ? root.wifiSsid : (NetworkService.wifiConnecting ? "Connecting..." : (NetworkService.wifiEnabled ? "Wi-Fi" : "Wi-Fi Off"))
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.bold: true
                                color: NetworkService.wifiEnabled ? Colors.overPrimary : Colors.overBackground
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: wifiMouse
                            objectName: "dashboardWifiMouse"
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    NetworkService.toggleWifi();
                                else
                                    root.openWifi();
                            }
                        }

                        StyledToolTip {
                            show: wifiMouse.containsMouse
                            tooltipText: root.wifiConnected ? (NetworkService.vpnConnected ? (root.wifiSsid + " (VPN: " + (NetworkService.vpnName || "Active") + ")") : root.wifiSsid) : "Open Wi-Fi Settings"
                        }
                    }
                }
            }

            // 2. Bluetooth Capsule
            StyledRect {
                id: btCapsule
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: Styling.radius(3)
                readonly property bool isHovered: btMouse.containsMouse || btIconMouse.containsMouse
                variant: BluetoothService.enabled ? (isHovered ? "primaryfocus" : "primary") : (isHovered ? "focus" : "internalbg")
                scale: (btMouse.pressed || btIconMouse.pressed) ? 0.94 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: (btMouse.pressed || btIconMouse.pressed) ? Motion.press : Motion.feedback
                        easing.type: (btMouse.pressed || btIconMouse.pressed) ? Easing.OutQuad : Motion.enterCurve
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    // Both halves open the menu; right-click toggles Bluetooth.
                    Item {
                        implicitWidth: 26
                        implicitHeight: 26
                        Layout.alignment: Qt.AlignVCenter

                        StyledText {
                            anchors.centerIn: parent
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            text: root.btConnected ? Icons.bluetoothConnected : (BluetoothService.enabled ? Icons.bluetooth : Icons.bluetoothOff)
                            font.family: Icons.font
                            font.pixelSize: 22
                            color: BluetoothService.enabled ? Colors.overPrimary : Colors.overBackground
                        }

                        MouseArea {
                            id: btIconMouse
                            objectName: "dashboardBluetoothIcon"
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    Visibilities.closeActiveBarPopup();
                                    BluetoothService.toggle();
                                } else {
                                    root.openBluetooth();
                                }
                            }
                        }
                        StyledToolTip {
                            show: btIconMouse.containsMouse
                            tooltipText: "Bluetooth"
                            description: "Click for devices · Right-click to toggle Bluetooth"
                        }

                    }

                    // Middle: Divider
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 22
                        Layout.alignment: Qt.AlignVCenter
                        color: BluetoothService.enabled ? Styling.withOpacity(Colors.overPrimary, 0.18) : Styling.withOpacity(Colors.overSurface, 0.15)
                    }

                    // Right: Text (click opens Bluetooth panel)
                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 3
                            StyledText {
                                text: "Bluetooth"
                                font.pixelSize: Styling.fontSize(-2)
                                color: BluetoothService.enabled ? Colors.overPrimary : Colors.overSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferFullHinting
                                text: root.btConnected ? root.btDeviceName : (BluetoothService.enabled ? "Bluetooth" : "Bluetooth Off")
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.bold: true
                                color: BluetoothService.enabled ? Colors.overPrimary : Colors.overBackground
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: btMouse
                            objectName: "dashboardBluetoothMouse"
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    BluetoothService.toggle();
                                else
                                    root.openBluetooth();
                            }
                        }
                        StyledToolTip {
                            show: btMouse.containsMouse
                            tooltipText: "Bluetooth"
                            description: "Click for devices · Right-click to toggle Bluetooth"
                        }

                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // QUICK CONTROLS
        // ═══════════════════════════════════════════════════════════════
        GridLayout {
            id: quickTilesRow
            Layout.fillWidth: true
            columns: 3
            readonly property real tileButtonSize: Styling.fontSize(0) * 2.7
            columnSpacing: 8
            rowSpacing: 8

            // 1. Sound (Vol)
            StyledRect {
                objectName: "dashboardShortcut0"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                implicitHeight: tileContent0.implicitHeight + 16
                radius: Styling.radius(3)
                variant: shortcutMouse0.containsMouse ? "focus" : "internalbg"

                ColumnLayout {
                    id: tileContent0
                    z: 1
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    IslandGaugeButton {
                        id: shortcutControl0
                        objectName: "dashboardSoundGauge"
                        Layout.alignment: Qt.AlignHCenter
                        buttonSize: quickTilesRow.tileButtonSize
                        showArc: true
                        value: root.audioMuted ? 0 : root.audioVolume
                        arcColor: root.audioMuted ? Colors.outlineVariant : Colors.primary
                        icon: root.audioMuted ? Icons.speakerSlash : (root.audioVolume > 0.5 ? Icons.speakerHigh : (root.audioVolume > 0 ? Icons.speakerLow : Icons.speakerSlash))
                        iconColor: root.audioMuted ? Colors.error : Colors.overBackground
                        tooltipText: (root.audioMuted ? "Muted " : "Volume ") + Math.round(root.audioVolume * 100) + "%"
                        tooltipDescription: "Click for sound · Right-click to mute"
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                Audio.toggleMute();
                            } else {
                                root.openSound();
                            }
                        }
                        onWheelScrolled: (delta) => {
                            if (delta > 0) Audio.incrementVolume();
                            else Audio.decrementVolume();
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "Sound"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.audioMuted ? "Muted" : Math.round(root.audioVolume * 100) + "%"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.overSurfaceVariant
                    }
                }

                MouseArea {
                    id: shortcutMouse0
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => shortcutControl0.clicked(mouse)
                    onWheel: wheel => shortcutControl0.wheelScrolled(wheel.angleDelta.y)
                }
            }

            // 2. Microphone
            StyledRect {
                objectName: "dashboardShortcut1"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                implicitHeight: tileContent1.implicitHeight + 16
                radius: Styling.radius(3)
                variant: shortcutMouse1.containsMouse ? "focus" : "internalbg"

                ColumnLayout {
                    id: tileContent1
                    z: 1
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    IslandGaugeButton {
                        id: shortcutControl1
                        objectName: "dashboardMicrophoneGauge"
                        Layout.alignment: Qt.AlignHCenter
                        buttonSize: quickTilesRow.tileButtonSize
                        readonly property bool micMuted: Audio.source?.audio?.muted ?? false
                        readonly property real micVol: Audio.source?.audio?.volume ?? 0.0
                        showArc: true
                        value: micMuted ? 0 : micVol
                        arcColor: micMuted ? Colors.outlineVariant : Colors.primary
                        icon: micMuted ? Icons.micSlash : Icons.mic
                        iconColor: micMuted ? Colors.error : Colors.overBackground
                        tooltipText: (micMuted ? "Mic Muted " : "Mic ") + Math.round(micVol * 100) + "%"
                        tooltipDescription: "Click for microphone · Right-click to mute"
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                Audio.toggleMicMute();
                            } else {
                                root.openMic();
                            }
                        }
                        onWheelScrolled: (delta) => {
                            if (delta > 0) Audio.setMicVolume(Math.min(1.0, micVol + 0.05));
                            else Audio.setMicVolume(Math.max(0, micVol - 0.05));
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "Microphone"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: (Audio.source?.audio?.muted ?? false) ? "Muted" : "Ready"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.overSurfaceVariant
                    }
                }

                MouseArea {
                    id: shortcutMouse1
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => shortcutControl1.clicked(mouse)
                    onWheel: wheel => shortcutControl1.wheelScrolled(wheel.angleDelta.y)
                }
            }

            // 3. Battery
            StyledRect {
                objectName: "dashboardShortcut2"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                implicitHeight: tileContent2.implicitHeight + 16
                radius: Styling.radius(3)
                variant: shortcutMouse2.containsMouse ? "focus" : "internalbg"

                ColumnLayout {
                    id: tileContent2
                    z: 1
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    IslandGaugeButton {
                        id: shortcutControl2
                        objectName: "dashboardBatteryGauge"
                        Layout.alignment: Qt.AlignHCenter
                        buttonSize: quickTilesRow.tileButtonSize
                        showArc: Battery.available
                        value: Battery.available ? (Battery.percentage / 100) : 0
                        arcColor: Battery.statusColor()
                        icon: Battery.isPluggedIn ? Icons.plug : Battery.getBatteryIcon()
                        iconColor: Battery.isPluggedIn ? Colors.primary : (Battery.percentage <= 20 ? Colors.error : Colors.overBackground)
                        tooltipText: Battery.available ? `${Battery.percentage}%${Battery.isPluggedIn ? " (Charging)" : ""}` : "No Battery"
                        onClicked: (mouse) => root.openBattery()
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "Battery"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: Battery.available ? Battery.percentage + "%" + (Battery.isPluggedIn ? " · Charging" : "") : "Unavailable"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.overSurfaceVariant
                    }
                }

                MouseArea {
                    id: shortcutMouse2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => shortcutControl2.clicked(mouse)
                    onWheel: wheel => shortcutControl2.wheelScrolled(wheel.angleDelta.y)
                }
            }

            // 4. Do Not Disturb
            StyledRect {
                objectName: "dashboardShortcut3"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                implicitHeight: tileContent3.implicitHeight + 16
                radius: Styling.radius(3)
                variant: shortcutMouse3.containsMouse ? "focus" : "internalbg"

                ColumnLayout {
                    id: tileContent3
                    z: 1
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    IslandGaugeButton {
                        id: shortcutControl3
                        objectName: "dashboardDoNotDisturbGauge"
                        Layout.alignment: Qt.AlignHCenter
                        buttonSize: quickTilesRow.tileButtonSize
                        active: Notifications.silent
                        icon: Notifications.silent ? Icons.bellSlash : Icons.bell
                        iconColor: Notifications.silent ? Colors.overPrimary : Colors.overBackground
                        tooltipText: Notifications.silent ? "Do Not Disturb: On" : "Do Not Disturb: Off"
                        tooltipDescription: "Click for notifications · Right-click to toggle Do Not Disturb"
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                Visibilities.closeActiveBarPopup();
                                Notifications.toggleSilent();
                            } else {
                                root.openAlerts();
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "Quiet mode"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: Notifications.silent ? "On" : "Off"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.overSurfaceVariant
                    }
                }

                MouseArea {
                    id: shortcutMouse3
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => shortcutControl3.clicked(mouse)
                    onWheel: wheel => shortcutControl3.wheelScrolled(wheel.angleDelta.y)
                }
            }

            // 5. Sysmonitor / Stats
            StyledRect {
                objectName: "dashboardShortcut4"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                implicitHeight: tileContent4.implicitHeight + 16
                radius: Styling.radius(3)
                variant: shortcutMouse4.containsMouse ? "focus" : "internalbg"

                ColumnLayout {
                    id: tileContent4
                    z: 1
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    IslandGaugeButton {
                        id: shortcutControl4
                        objectName: "dashboardSystemGauge"
                        Layout.alignment: Qt.AlignHCenter
                        buttonSize: quickTilesRow.tileButtonSize
                        icon: Icons.cpu
                        tooltipText: "System Monitor"
                        onClicked: (mouse) => root.openStats()
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "System"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "Performance"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.overSurfaceVariant
                    }
                }

                MouseArea {
                    id: shortcutMouse4
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => shortcutControl4.clicked(mouse)
                    onWheel: wheel => shortcutControl4.wheelScrolled(wheel.angleDelta.y)
                }
            }

            // 6. Wallpapers
            StyledRect {
                objectName: "dashboardShortcut5"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                implicitHeight: tileContent5.implicitHeight + 16
                radius: Styling.radius(3)
                variant: shortcutMouse5.containsMouse ? "focus" : "internalbg"

                ColumnLayout {
                    id: tileContent5
                    z: 1
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    IslandGaugeButton {
                        id: shortcutControl5
                        objectName: "dashboardWallpapersGauge"
                        Layout.alignment: Qt.AlignHCenter
                        buttonSize: quickTilesRow.tileButtonSize
                        icon: Icons.image
                        tooltipText: "Wallpapers"
                        onClicked: (mouse) => root.openWallpapers()
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "Wallpapers"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "Appearance"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.overSurfaceVariant
                    }
                }

                MouseArea {
                    id: shortcutMouse5
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => shortcutControl5.clicked(mouse)
                    onWheel: wheel => shortcutControl5.wheelScrolled(wheel.angleDelta.y)
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // DISPLAY: BRIGHTNESS & NIGHT LIGHT
        // ═══════════════════════════════════════════════════════════════
        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: Styling.radius(2)
            variant: "internalbg"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 10

                // Sun icon
                DynamicSunIcon {
                    size: 20
                    value: brightSlider.value
                    color: Colors.overBackground
                    Layout.alignment: Qt.AlignVCenter
                }

                // Brightness slider
                StyledSlider {
                    id: brightSlider
                    objectName: "dashboardBrightness"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    value: root.brightnessVal
                    onValueChanged: {
                        if (Math.abs(value - root.brightnessVal) > 0.01) {
                            root.setBrightness(value);
                        }
                    }
                }

                // Brightness percentage
                StyledText {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    Layout.preferredWidth: 38
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.brightnessVal * 100) + "%"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(-1)
                    font.bold: true
                    color: Colors.overBackground
                }

                // Divider
                Separator {
                    vert: true
                    Layout.preferredHeight: 20
                }

                // Night Light scrollable strength toggle
                StyledRect {
                    id: nightLightPill
                    implicitHeight: 30
                    implicitWidth: 72
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: 72
                    radius: Styling.radius(2)
                    variant: NightLightService.active ? "primary" : (nlMouse.containsMouse ? "focus" : "common")

                    RowLayout {
                        id: nlContentRow
                        anchors.centerIn: parent
                        spacing: 5

                        StyledText {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            text: Icons.moon
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: NightLightService.active ? Colors.overPrimary : Colors.overBackground
                        }

                        StyledText {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignHCenter
                            text: NightLightService.active
                                ? Math.round((1.0 - NightLightService.normalizedTemperature) * 100) + "%"
                                : "Night"
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(-2)
                            font.bold: true
                            color: NightLightService.active ? Colors.overPrimary : Colors.overSurfaceVariant
                        }
                    }

                    MouseArea {
                        id: nlMouse
                        objectName: "dashboardNightLight"
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Visibilities.closeActiveBarPopup();
                            NightLightService.toggle();
                        }
                        onWheel: wheel => {
                            if (!NightLightService.desiredActive) {
                                NightLightService.toggle();
                            }
                            const step = 100;
                            const delta = wheel.angleDelta.y > 0 ? -step : step;
                            NightLightService.setTemperature(NightLightService.temperature + delta);
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // MEDIA PLAYER
        // ═══════════════════════════════════════════════════════════════
        IslandMediaCard {
            objectName: "dashboardMedia"
            Layout.fillWidth: true
            Layout.preferredHeight: 88
            onExpandRequested: root.openMedia()
        }

        // ═══════════════════════════════════════════════════════════════
        // SYSTEM TRAY
        // ═══════════════════════════════════════════════════════════════
        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: Styling.radius(2)
            variant: "internalbg"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                StyledText {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    text: "Background apps"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                SysTray {
                    enableShadow: false
                    startRadius: 4
                    endRadius: 4
                }
            }
        }
    }
}
