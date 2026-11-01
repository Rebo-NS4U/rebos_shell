pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2

    // Hosts may keep this panel loaded while hidden; refresh the device list
    // (no discovery) each time it is shown, after the host's reveal settles.
    onVisibleChanged: {
        if (visible) {
            updateTimer.restart();
        } else {
            updateTimer.stop();
            BluetoothService.stopDiscovery();
        }
    }
    Component.onCompleted: {
        if (visible)
            updateTimer.restart();
    }

    Timer {
        id: updateTimer
        interval: Motion.expandDuration
        onTriggered: {
            if (BluetoothService.enabled)
                BluetoothService.updateDevices();
        }
    }

    Component.onDestruction: {
        BluetoothService.stopDiscovery();
    }

    BluetoothPairingPrompt {
        id: pairingPrompt
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.contentWidth
    }

    // Keep the code visible even when the device list is scrolled.
    ListView {
        id: deviceList
        anchors.fill: parent
        anchors.topMargin: pairingPrompt.visible ? pairingPrompt.implicitHeight + 12 : 0
        clip: true
        spacing: 4
        cacheBuffer: 1000
        reuseItems: true

        model: BluetoothService.deviceModel

        header: Item {
            width: deviceList.width
            height: titlebar.height + 8 + (errorText.visible ? errorText.implicitHeight + 8 : 0)

            StyledText {
                id: errorText
                anchors.top: titlebar.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.contentWidth
                visible: BluetoothService.lastError.length > 0
                text: BluetoothService.lastError
                color: Colors.error
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            PanelTitlebar {
                id: titlebar
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                title: "Bluetooth"
                showToggle: true
                toggleChecked: BluetoothService.enabled

                actions: [
                    {
                        icon: Icons.popOpen,
                        tooltip: "Open Blueman",
                        onClicked: function () {
                            Quickshell.execDetached(["blueman-manager"]);
                        }
                    },
                    {
                        icon: Icons.sync,
                        tooltip: "Scan for devices",
                        enabled: BluetoothService.enabled,
                        loading: BluetoothService.discovering || BluetoothService.isUpdating,
                        onClicked: function () {
                            BluetoothService.startDiscovery();
                        }
                    }
                ]

                onToggleChanged: checked => {
                    BluetoothService.setEnabled(checked, checked);
                }
            }
        }

        delegate: Item {
            id: delegateRoot
            required property var device
            width: deviceList.width
            height: deviceItem.height

            BluetoothDeviceItem {
                id: deviceItem
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                device: delegateRoot.device
            }
        }

        // Empty state
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            anchors.centerIn: parent
            visible: deviceList.count === 0 && !BluetoothService.discovering
            text: BluetoothService.enabled ? "No devices found" : "Bluetooth is disabled"
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color: Colors.overSurfaceVariant
        }
    }
}
