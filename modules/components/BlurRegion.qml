pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell

// Blur follows painted geometry, independently of the window's input mask.
// Refresh with rendered frames: Region.item only watches the item's own bounds,
// so it misses slides/transforms on ancestors. Stable bounds schedule no work.
Region {
    id: root
    property Item target: null
    property bool enabled: true
    radius: target?.radius ?? 0
    topLeftRadius: target?.topLeftRadius ?? radius
    topRightRadius: target?.topRightRadius ?? radius
    bottomLeftRadius: target?.bottomLeftRadius ?? radius
    bottomRightRadius: target?.bottomRightRadius ?? radius

    function updateGeometry() {
        if (!enabled || !target || !target.visible || target.opacity <= 0) {
            width = 0;
            height = 0;
            return;
        }
        const origin = target.mapToItem(null, 0, 0);
        const extent = target.mapToItem(null, target.width, target.height);
        x = Math.floor(origin.x);
        y = Math.floor(origin.y);
        width = Math.max(0, Math.ceil(extent.x) - x);
        height = Math.max(0, Math.ceil(extent.y) - y);
    }
    onTargetChanged: Qt.callLater(updateGeometry)
    onEnabledChanged: updateGeometry()
    Component.onCompleted: Qt.callLater(updateGeometry)

    property Connections frameConnection: Connections {
        target: root.target?.Window.window ?? null
        function onAfterAnimating() { root.updateGeometry(); }
    }
}
