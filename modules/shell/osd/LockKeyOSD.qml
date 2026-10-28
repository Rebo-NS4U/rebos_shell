pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland._BackgroundEffect
import Quickshell.Wayland
import qs.modules.services
import qs.modules.globals
import qs.modules.components
import qs.modules.theme

PanelWindow {
    id: root
    property ShellScreen targetScreen
    screen: targetScreen
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "rebos_shell:keyboard-locks"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    BackgroundEffect.blurRegion: BlurRegion { target: toast; radius: Styling.radius(20) }

    mask: Region {}
    implicitHeight: toast.implicitHeight + (Styling.fontSize(0) * 10)
    // A child's effective visibility is false while this window is hidden.
    // Read the requested state/animation instead so the window can open.
    visible: (toast.shown || toast.opacity > 0) && !GlobalStates.lockscreenVisible

    LockKeyToast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: (Styling.fontSize(0) * 10)
        shown: KeyboardLocks.toastVisible && KeyboardLocks.toastScreenName === root.targetScreen?.name
    }
}
