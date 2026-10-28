import QtQuick
import Quickshell
pragma Singleton

Singleton {
    property bool aiReady: false
    property int animDuration: 0
    property var theme: ({
        "font": "sans-serif"
    })
    property QtObject ai

    ai: QtObject {
        property bool enabled: false
        property int sidebarWidth: 450
    }

    function resolveColor(c) {
        return c || "transparent";
    }

}
