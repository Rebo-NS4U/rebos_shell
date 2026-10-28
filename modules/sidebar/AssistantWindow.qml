import QtQuick
import Quickshell
import qs.modules.globals
import qs.modules.services

FloatingWindow {
    id: root

    required property ShellScreen targetScreen
    screen: targetScreen
    title: "rebos_shell Assistant"
    readonly property bool compositorFocused: NiriService.focusedClient?.title === root.title
    implicitWidth: GlobalStates.assistantWidth
    implicitHeight: targetScreen.height
    minimumSize: Qt.size(300, 320)
    color: "transparent"
    visible: GlobalStates.assistantAvailable
        && GlobalStates.assistantVisible
        && GlobalStates.assistantPinned
        && targetScreen.name === GlobalStates.assistantScreenName

    onClosed: GlobalStates.hideAssistant()

    Connections {
        target: GlobalStates
        function onAssistantFocusRequested(wasAlreadyOpen) {
            if (!root.visible) return;
            for (const client of NiriService.clients.values) {
                if (client.title === root.title) {
                    NiriService.focusWindow(client.id);
                    break;
                }
            }
        }
    }
}
