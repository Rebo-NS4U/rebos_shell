pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.theme

Item {
    id: root

    required property ShellScreen screen

    readonly property var screenVisibilities: Visibilities.getForScreen(screen.name)
    readonly property bool open: (Config.bar?.style !== "island") && (screenVisibilities ? screenVisibilities.launcher : false)
    readonly property Item blurTarget: menuCard
    readonly property Item hitbox: open ? cardReveal : null
    property PanelWindow barPanel: Visibilities.getBarPanelForScreen(screen.name)
    readonly property int contentPadding: 8
    readonly property int edgeGap: 8
    readonly property bool bottomEdge: (Config.bar?.position ?? "top") === "bottom"
    readonly property real barClearance: {
        if (!barPanel || !barPanel.barEnabled)
            return edgeGap;
        return (barPanel.totalBarHeight > 0 ? barPanel.totalBarHeight : (barPanel.barTargetHeight + barPanel.barOuterMargin)) + edgeGap;
    }

    onOpenChanged: {
        if (open) {
            GlobalStates.clearLauncherState();
            GlobalStates.clearProjectPickerState();
            Qt.callLater(() => {
                if (root.open && launcherLoader.item)
                    launcherLoader.item.forceActiveFocus();
            });
        }
    }

    Item {
        id: edgeRegion

        x: 0
        y: root.bottomEdge ? 0 : root.barClearance
        width: root.width
        height: Math.max(0, root.height - root.barClearance)
        clip: true

        MotionReveal {
            id: cardReveal
            objectName: "launcher-motion"

            open: root.open
            direction: root.bottomEdge ? 1 : -1
            width: launcherLoader.item ? launcherLoader.item.implicitWidth + root.contentPadding * 2 : 0
            height: (launcherLoader.item
                ? launcherLoader.item.implicitHeight + root.contentPadding * 2
                : 0)
            x: Math.round((edgeRegion.width - width) / 2)
            y: root.bottomEdge ? edgeRegion.height - height : 0
            clip: true

            StyledRect {
                id: menuCard

                variant: "popup"
                enableShadow: false
                radius: Styling.radius(8)
                width: cardReveal.width
                height: launcherLoader.item
                    ? launcherLoader.item.implicitHeight + root.contentPadding * 2
                    : 0
                y: root.bottomEdge ? cardReveal.height - height : 0

                Loader {
                    id: launcherLoader
                    anchors.fill: parent
                    anchors.margins: root.contentPadding
                    // Keep loaded so open/close does not hitch on first paint.
                    active: true
                    sourceComponent: Component {
                        LauncherView {}
                    }

                    onLoaded: {
                        if (root.open)
                            Qt.callLater(() => item.forceActiveFocus());
                    }
                }
            }
        }
    }
}
