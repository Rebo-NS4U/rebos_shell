import QtQuick
import QtQuick.Layouts
import qs.modules.components
import qs.modules.services
import qs.modules.theme

ColumnLayout {
    visible: BluetoothService.pairingCode.length > 0
    spacing: 4

    StyledText {
        Layout.fillWidth: true
        text: "Type this code on " + BluetoothService.pairingDeviceName + ", then press Enter:"
        wrapMode: Text.Wrap
    }

    StyledText {
        Layout.fillWidth: true
        text: BluetoothService.pairingCode
        font.pixelSize: Styling.fontSize(10)
        font.bold: true
        color: Styling.srItem("overprimary")
        horizontalAlignment: Text.AlignHCenter
    }

    StyledText {
        Layout.fillWidth: true
        visible: BluetoothService.pairingEntered > 0
        text: Math.min(BluetoothService.pairingEntered, BluetoothService.pairingCode.length)
            + " of " + BluetoothService.pairingCode.length + " digits entered"
        horizontalAlignment: Text.AlignHCenter
    }
}
