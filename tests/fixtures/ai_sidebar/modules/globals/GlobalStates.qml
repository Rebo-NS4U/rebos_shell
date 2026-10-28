import Quickshell
pragma Singleton

Singleton {
    property bool assistantAvailable: true
    property bool assistantVisible: true
    property bool assistantPinned: false
    property string assistantScreenName: Quickshell.screens[0].name
    property string assistantPosition: "right"
    property int assistantWidth: 450

    signal assistantFocusRequested(bool wasAlreadyOpen)

    function toggleAssistant() {
        if (assistantVisible) {
            hideAssistant();
        } else {
            assistantVisible = true;
            assistantFocusRequested(false);
        }
    }

    function hideAssistant() {
        assistantVisible = false;
    }

}
