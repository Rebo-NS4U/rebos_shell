pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services
import qs.modules.components
import qs.modules.bar.island
import qs.modules.theme

CircularBarMeter {
    id: root

    readonly property var audioDevice: Audio.source?.audio ?? null

    value: audioDevice?.volume ?? 0
    icon: audioDevice?.muted ? Icons.micSlash : Icons.mic
    progressColor: audioDevice?.muted ? Colors.outline : Styling.srItem("overprimary")
    tooltipText: (audioDevice?.muted ? "Muted " : "Microphone ") + Math.round(value * 100) + "%"

    tooltipDescription: "Scroll to adjust · Click for controls · Right-click to mute"

    onAdjusted: newValue => {
        if (audioDevice)
            audioDevice.volume = newValue;
    }

    onActivated: controlPopup.toggle()

    onSecondaryActivated: {
        if (audioDevice)
            audioDevice.muted = !audioDevice.muted;
    }
    BarPopup {
        id: controlPopup
        anchorItem: root
        contentWidth: panel.implicitWidth
        contentHeight: panel.implicitHeight
        IslandMicPanel {
            id: panel
            width: implicitWidth
            height: implicitHeight
            onBackRequested: controlPopup.close()
        }
    }
}
