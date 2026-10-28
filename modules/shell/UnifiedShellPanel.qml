import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Wayland._BackgroundEffect
import qs.modules.bar
import qs.modules.services
import qs.modules.globals
import qs.modules.components
import qs.modules.widgets.launcher
import qs.modules.widgets.fileshelf
import qs.modules.widgets.notes
import qs.modules.widgets.powermenu
import qs.modules.notifications
import qs.config

PanelWindow {
    id: unifiedPanel

    required property ShellScreen targetScreen
    screen: targetScreen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    WlrLayershell.keyboardFocus: {
        if (notesPopup.open || runMenu.open)
            return WlrKeyboardFocus.Exclusive;
        if (SystemResources.keepMonitorOpen)
            return WlrKeyboardFocus.OnDemand;
        if (barContent.islandActive)
            return WlrKeyboardFocus.Exclusive;
        // Bar popups are child surfaces of this panel. The parent layer must
        // request keyboard focus or input continues to the client underneath.
        if (barContent.timerInputActive || barContent.dashboardInputActive)
            return WlrKeyboardFocus.Exclusive;
        if (fileShelf.open) return WlrKeyboardFocus.OnDemand;
        return WlrKeyboardFocus.None;
    }
    WlrLayershell.namespace: "rebos_shell"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    // Menus temporarily receive outside clicks so they can be dismissed.
    readonly property bool needsFullScreenInput: notesPopup.open || runMenu.open || ((!SystemResources.keepMonitorOpen) && (barContent.dashboardInputActive || barContent.islandActive)) || FocusGrabManager.hasActiveGrab

    readonly property bool barEnabled: {
        if (!Config.barReady) return false;
        const list = Config.bar.screenList;
        return (!list || list.length === 0 || list.indexOf(targetScreen.name) !== -1);
    }

    readonly property alias barTargetHeight: barContent.barTargetHeight
    readonly property alias barOuterMargin: barContent.baseOuterMargin
    readonly property alias totalBarHeight: barContent.totalBarHeight
    readonly property string barPosition: Config.bar?.position ?? "top"


    Component.onCompleted: {
        Visibilities.registerBarPanel(screen.name, unifiedPanel);
    }

    Component.onDestruction: {
        Visibilities.unregisterBarPanel(screen.name);
    }

    // Only the painted panels request blur; outside-click input stays separate.
    // Strength is shared with application windows through Niri's global blur.
    BackgroundEffect.blurRegion: Region {
        regions: [
            barContent.backgroundBlur,
            launcherBlur,
            notesBlur,
            shelfBlur,
            toastStack.backgroundBlur
        ]
    }


    BlurRegion { id: launcherBlur; target: runMenu.blurTarget }
    BlurRegion { id: notesBlur; target: notesPopup.blurTarget }
    BlurRegion { id: shelfBlur; target: fileShelf.blurTarget }

    // Full-screen mask item (used when modules/popups are open)
    Item {
        id: fullScreenMask
        anchors.fill: parent
    }

    // Capture the full screen only while the run menu or a bar popup is open.
    // Toast stack must be in the mask or the full-screen transparent panel
    // swallows clicks meant for the X / dismiss controls.
    mask: Region {
        // Full-screen capture when any module/popup is open
        item: unifiedPanel.needsFullScreenInput ? fullScreenMask : null
        regions: [
            Region { item: fileShelf.handleHitbox },
            Region { item: fileShelf.shelfHitbox },
            Region {
                item: barContent.visible ? barContent.barHitbox : null
            },
            Region {
                item: barContent.dashboardHitbox
            },
            Region {
                item: runMenu.hitbox
            },
            Region {
                item: toastStack.hitbox
            }
        ]
    }

    // Close the run menu when its focus grab is cleared.
    FocusGrab {
        id: focusGrab
        windows: [unifiedPanel]
        active: runMenu.open || notesPopup.open

        onCleared: {
            if (notesPopup.open)
                QuickNotes.close();
            Visibilities.setActiveModule("");
        }
    }

    Item {
        id: visualContent
        anchors.fill: parent

        MouseArea {
            id: backdropArea
            anchors.fill: parent
            visible: unifiedPanel.needsFullScreenInput
            // Outside clicks dismiss the open surface.
            z: 50
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            onClicked: {
                if (notesPopup.open)
                    QuickNotes.close();
                FocusGrabManager.clearTopGrab();
                if (runMenu.open)
                    Visibilities.setActiveModule("");
                if (barContent.dashboardInputActive)
                    Visibilities.closeActiveBarPopup();
                if (barContent.islandActive)
                    barContent.collapseIsland();

            }

        }

        BarContent {
            id: barContent
            anchors.fill: parent
            screen: unifiedPanel.targetScreen
            z: 100
            visible: unifiedPanel.barEnabled
        }

        // Notification toasts live on this panel so they share the bar's
        // input surface (separate layer windows were unclickable under niri).
        NotificationToastStack {
            id: toastStack
        }

        // Power menu host (no bar icon — Super+X / IPC only).
        PowerMenuHost {
            id: powerMenuHost
            panel: unifiedPanel
            z: 300
        }

        // Detached popup; it never joins the screen edge or reserves space.
        RunMenuHost {
            id: runMenu
            anchors.fill: parent
            screen: unifiedPanel.targetScreen
            barPanel: unifiedPanel
            z: 200
        }

        FileShelfPanel {
            id: fileShelf
            anchors.fill: parent
            screen: unifiedPanel.targetScreen
            z: 250
        }

        NotesPopup {
            id: notesPopup
            anchors.fill: parent
            screen: unifiedPanel.targetScreen
            z: 400
        }

    }
}
