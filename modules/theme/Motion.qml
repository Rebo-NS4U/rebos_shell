pragma Singleton
import QtQuick
import Quickshell
import qs.config

// All timings scale from the existing, persisted Appearance motion control.
Singleton {
    readonly property int base: Math.max(0, Config.animDuration)
    readonly property bool enabled: base > 0
    readonly property int enter: Math.round(base * 0.85)
    readonly property int exit: Math.round(base * 0.60)
    readonly property int resize: Math.round(base * 0.60)
    readonly property int feedback: Math.round(base * 0.40)
    readonly property int press: Math.round(base * 0.25)
    readonly property int contentIn: Math.round(base * 0.55)
    readonly property int contentOut: Math.round(base * 0.22)
    readonly property int enterCurve: Easing.OutCubic
    readonly property int exitCurve: Easing.InOutCubic
    readonly property int feedbackCurve: Easing.OutCubic
    readonly property real offset: enabled ? 8 : 0
}
