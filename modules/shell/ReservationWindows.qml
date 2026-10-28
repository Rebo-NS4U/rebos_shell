import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config

Item {
    id: root

    required property ShellScreen screen

    property bool barEnabled: true
    property int barSize: 0
    property int barOuterMargin: 0
    property string barPosition: "top"

    Item {
        id: noInputRegion
        width: 0
        height: 0
        visible: false
    }

    PanelWindow {
        screen: root.screen
        visible: true
        implicitHeight: Math.max(1, exclusiveZone)
        color: "transparent"
        anchors {
            left: true
            right: true
            top: true
        }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "rebos_shell:reservation:top"

        exclusiveZone: Config.barReady && root.barEnabled && root.barPosition === "top"
            && ((Config.bar?.style ?? "default") !== "island" || (Config.bar?.pinned ?? false))
            ? root.barSize + root.barOuterMargin
            : 0
        exclusionMode: exclusiveZone > 0 ? ExclusionMode.Normal : ExclusionMode.Ignore

        mask: Region {
            item: noInputRegion
        }
    }

    PanelWindow {
        screen: root.screen
        visible: true
        implicitHeight: Math.max(1, exclusiveZone)
        color: "transparent"
        anchors {
            left: true
            right: true
            bottom: true
        }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "rebos_shell:reservation:bottom"

        exclusiveZone: Config.barReady && root.barEnabled && root.barPosition === "bottom"
            && ((Config.bar?.style ?? "default") !== "island" || (Config.bar?.pinned ?? false))
            ? root.barSize + root.barOuterMargin
            : 0
        exclusionMode: exclusiveZone > 0 ? ExclusionMode.Normal : ExclusionMode.Ignore

        mask: Region {
            item: noInputRegion
        }
    }

}
