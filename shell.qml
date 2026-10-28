//@ pragma UseQApplication
//@ pragma ShellId rebos_shell
//@ pragma DataDir $BASE/rebos_shell
//@ pragma StateDir $BASE/rebos_shell

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.services
import qs.modules.lockscreen
import qs.modules.globals
import qs.modules.shell
import qs.modules.shell.osd
import qs.modules.widgets.dashboard.wallpapers
import qs.modules.widgets.config
import qs.config

ShellRoot {
    id: root

    AnimeMenu {}

    // Keep the inherited wallpaper owner: it also provides the wallpaper
    // manager used by the lockscreen.
    Variants {
        model: Quickshell.screens

        Loader {
            id: wallpaperLoader
            active: true
            required property ShellScreen modelData
            sourceComponent: Wallpaper {
                screen: wallpaperLoader.modelData
            }
        }
    }

    // The shell owns one panel per configured screen. Transient UI such as the
    // run menu is rendered inside this same panel instead of separate windows.
    Variants {
        model: Quickshell.screens

        Item {
            id: screenShellContainer
            required property ShellScreen modelData

            UnifiedShellPanel {
                id: unifiedPanel
                targetScreen: screenShellContainer.modelData
            }

            // Exclusive zone reservations
            ReservationWindows {
                screen: screenShellContainer.modelData

                // Keep exclusive zone even during niri overview so tiled
                // windows do not reflow. Bar is only hidden visually.
                barEnabled: unifiedPanel.barEnabled
                barSize: unifiedPanel.barTargetHeight
                barOuterMargin: unifiedPanel.barOuterMargin
                barPosition: Config.bar?.position ?? "top"

            }

            // Volume / mic / brightness OSD for keyboard media keys (standard bar only; island bar embeds its own OSD)
            LockKeyOSD {
                targetScreen: screenShellContainer.modelData
            }

            Loader {
                active: Config.barReady ? (Config.bar?.style ?? "default") !== "island" : false
                sourceComponent: OSD {
                    targetScreen: screenShellContainer.modelData
                }
            }
        }
    }

    // Secure WlSessionLock lockscreen
    WlSessionLock {
        id: sessionLock
        locked: GlobalStates.lockscreenVisible

        // Surface auto-created per screen. Defer animation until the protocol
        // confirms niri has locked every output.
        LockScreen {
            lockSecure: sessionLock.secure
        }
    }

    // Toasts are hosted inside UnifiedShellPanel (NotificationToastStack) so
    // they receive clicks. NotificationServer still loads via service init.

    // Settings floating window (lazy — only while open).
    Loader {
        id: settingsWindowLoader
        active: GlobalStates.settingsWindowVisible
        sourceComponent: SettingsWindow {}
    }

    // Initialize only the services needed by the bar, run menu, and lockscreen.
    QtObject {
        id: serviceInitializer

        Component.onCompleted: {
            Qt.callLater(() => {
                let _ = GlobalShortcuts.appId;
                _ = LockscreenService.prepActive;
                // Keep compositor + OSD services hot for overview hide and media keys.
                _ = NiriService.overviewOpen;
                _ = DesktopBlur.appliedMode;
                _ = Audio.value;
                _ = AudioFormat.connected;
                _ = Brightness.monitors;
                // Own org.freedesktop.Notifications and load history early.
                _ = Notifications.appNameList;
                _ = StateService.initialized;
                // Assistant sessions belong to the separate assistant application.
            });
        }

    }
}
