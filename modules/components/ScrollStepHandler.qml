import QtQuick

// Accumulate high-resolution wheel events instead of treating every tiny
// trackpad movement as a complete mouse-wheel notch.
WheelHandler {
    id: root

    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    property real remainder: 0
    signal stepped(int steps)

    function accumulate(delta: real): void {
        if (delta === 0)
            return;
        if (remainder * delta < 0)
            remainder = 0;
        remainder += delta;
        const steps = Math.trunc(remainder);
        remainder -= steps;
        resetTimer.restart();
        if (steps !== 0)
            stepped(steps);
    }

    onWheel: event => {
        // Vertical controls must not react to incidental horizontal swipes.
        const delta = event.pixelDelta.y !== 0
            ? event.pixelDelta.y / 40 : event.angleDelta.y / 120;
        accumulate(delta);
        event.accepted = true;
    }

    property Timer resetTimer: Timer {
        interval: 250
        onTriggered: root.remainder = 0
    }
}
