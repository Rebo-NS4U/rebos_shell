pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.modules.bar
import qs.modules.components
import qs.modules.services
import qs.modules.theme

Item {
    id: root
    required property Item bar
    property bool showBackground: true
    // Even indicator dimensions share a pixel center at every workspace width.
    readonly property int workspaceHeight: 2 * Math.round(Styling.fontSize(0) * 1.85 / 2)
    readonly property int workspaceGap: Math.max(1, Math.round(Styling.fontSize(0) / 7))
    readonly property var visibleWorkspaces: NiriService.workspacesForOutput(root.bar.screen.name)

    // Keep workspace buttons stable across window and focus updates.
    ListModel {
        id: workspaceModel
    }

    function reconcileIds(model: ListModel, ids: list<int>, role: string): void {
        for (let index = model.count - 1; index >= 0; index--) {
            if (!ids.includes(model.get(index)[role]))
                model.remove(index);
        }
        for (let index = 0; index < ids.length; index++) {
            let existingIndex = index;
            while (existingIndex < model.count && model.get(existingIndex)[role] !== ids[index])
                existingIndex++;
            if (existingIndex === model.count) {
                const entry = {};
                entry[role] = ids[index];
                model.insert(index, entry);
            } else if (existingIndex !== index) {
                model.move(existingIndex, index, 1);
            }
        }
    }

    function syncWorkspaces(): void {
        reconcileIds(workspaceModel, root.visibleWorkspaces.map(workspace => workspace.id), "workspaceId");
    }

    // Timers are destroyed with the delegate during native hot reload;
    // queued Qt.callLater callbacks can otherwise outlive their QML context.
    Timer {
        id: workspaceSync
        interval: 0
        onTriggered: root.syncWorkspaces()
    }
    onVisibleWorkspacesChanged: workspaceSync.restart()
    Component.onCompleted: syncWorkspaces()

    implicitWidth: workspaceRow.implicitWidth + root.workspaceGap * 3
    implicitHeight: root.workspaceHeight + root.workspaceGap * 3

    StyledRect {
        visible: root.showBackground
        anchors.fill: parent
        variant: "bg"
        radius: Styling.radius(7)
        enableShadow: false
    }

    RowLayout {
        id: workspaceRow
        anchors.centerIn: parent
        spacing: root.workspaceGap

        Repeater {
            model: workspaceModel

            Item {
                id: workspaceButton
                required property int workspaceId
                objectName: "workspace-" + workspaceId
                readonly property var workspace: root.visibleWorkspaces.find(workspace => workspace.id === workspaceId) ?? null
                readonly property bool active: workspace?.active ?? false
                readonly property var windows: NiriService.windowsForWorkspace(workspaceId)
                readonly property bool occupied: windows.length > 0
                readonly property int dotSize: Math.max(4, 2 * Math.round(root.workspaceHeight / 10))
                ListModel { id: windowModel }
                Timer {
                    id: windowSync
                    interval: 0
                    onTriggered: root.reconcileIds(windowModel, workspaceButton.windows.map(window => window.id), "windowId")
                }
                onWindowsChanged: windowSync.restart()
                Component.onCompleted: windowSync.restart()
                readonly property string displayName: workspace?.isNamed ? workspace.name : String(workspace?.idx ?? workspaceId)
                Layout.preferredWidth: Math.max(root.workspaceHeight, windowDots.implicitWidth + root.workspaceGap * 6)
                Layout.preferredHeight: root.workspaceHeight
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    objectName: "workspace-dot-" + workspaceButton.workspaceId
                    anchors.centerIn: parent
                    anchors.alignWhenCentered: false
                    visible: !workspaceButton.occupied
                    width: workspaceButton.dotSize
                    height: width
                    radius: width / 2
                    // Shape distinguishes empty spaces without dimming their centerline.
                    color: "transparent"
                    border.color: BarAppearance.foregroundColor
                    border.width: Math.max(1, Math.round(width / 6))
                }

                Row {
                    id: windowDots
                    anchors.centerIn: parent
                    anchors.alignWhenCentered: false
                    spacing: root.workspaceGap * 2

                    Repeater {
                        model: windowModel
                        Rectangle {
                            id: windowDot
                            required property int windowId
                            objectName: "window-dot-" + windowId
                            width: workspaceButton.dotSize
                            height: width
                            radius: width / 2
                            color: BarAppearance.foregroundColor
                            property bool entered: false
                            Timer {
                                running: true
                                interval: 0
                                onTriggered: windowDot.entered = true
                            }
                            opacity: entered ? 1 : 0
                            Behavior on opacity {
                                enabled: Config.animDuration > 0
                                NumberAnimation { duration: Math.min(Config.animDuration, 150) }
                            }
                        }
                    }
                }

                Rectangle {
                    objectName: "workspace-underline-" + workspaceButton.workspaceId
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.alignWhenCentered: false
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.workspaceGap
                    width: 2 * Math.round(root.workspaceHeight / 5)
                    height: Math.max(2, Math.round(Styling.fontSize(0) / 7))
                    radius: height / 2
                    color: BarAppearance.foregroundColor
                    opacity: workspaceButton.active ? 1 : 0
                    Behavior on opacity {
                        enabled: Config.animDuration > 0
                        NumberAnimation { duration: Math.min(Config.animDuration, 150) }
                    }
                }

                MouseArea {
                    id: workspaceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NiriService.focusWorkspace(workspaceButton.workspaceId)
                }

                StyledToolTip {
                    show: workspaceMouse.containsMouse
                    tooltipText: workspaceButton.displayName + " · " + (workspaceButton.occupied
                        ? workspaceButton.windows.length + (workspaceButton.windows.length === 1 ? " window" : " windows") : "Empty")
                }
            }
        }
    }

    ScrollStepHandler {
        onStepped: steps => {
            NiriService.runNiriAction([steps < 0 ? "focus-workspace-down" : "focus-workspace-up"]);
        }
    }
}
