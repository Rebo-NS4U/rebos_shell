pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.globals
import qs.modules.services
import qs.config
import Quickshell.Io
import "../theme/ShellStyles.js" as ShellStyles

Singleton {
    id: root

    readonly property string appId: "rebos_shell"
    readonly property string ipcRuntimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    // High-performance Pipe Listener (Daemon mode)
    Process {
        id: pipeListener
        command: ["bash", "-c", 'set -euo pipefail; pipe="$1/rebos_shell_ipc_$UID.pipe"; rm -f -- "$pipe"; mkfifo -m 600 -- "$pipe"; exec tail -f -- "$pipe"', "rebos-shell-ipc", root.ipcRuntimeDir]
        running: true
        
        stdout: SplitParser {
            onRead: data => {
                const cmd = data.trim();
                if (cmd !== "") {
                    root.run(cmd);
                }
            }
        }
    }

    function run(command) {
        console.log("IPC run command received:", command);
        const barAccentPrefix = "bar-accent ";
        if (command.startsWith(barAccentPrefix)) {
            const strength = Number(command.slice(barAccentPrefix.length));
            if (Config.barReady && Number.isInteger(strength) && strength >= 0 && strength <= 100)
                Config.bar.islandAccent = strength;
            else
                console.warn("Ignoring invalid bar accent strength:", command);
            return;
        }
        if (command !== "notes" && QuickNotes.visible)
            QuickNotes.close();
        switch (command) {
            case "file-shelf":
            case "shelf":
                FileShelf.toggle("");
                break;
            case "notes":
                if (!QuickNotes.visible)
                    Visibilities.clearAll();
                QuickNotes.toggle();
                break;
            case "launcher": toggleLauncher(); break;
            case "projects":
            case "project-picker":
            case "projectpicker":
                toggleProjects();
                break;
            case "assistant":
            case "dashboard-assistant":
                toggleAssistant();
                break;
            case "system-monitor":
            case "stats":
            case "resources":
                Visibilities.toggleSystemMonitorForActive();
                break;
            case "wallpaper":
            case "wallpapers":
                toggleWallpapers();
                break;
            case "powermenu":
            case "power":
                Visibilities.togglePowerMenuForActive();
                break;
            case "alerts":
            case "notifications":
                toggleAlerts();
                break;
            case "dashboard": toggleDashboard(); break;
            case "sound":
            case "audio":
                Visibilities.setActiveModule("sound");
                break;
            case "mic":
            case "microphone":
                Visibilities.setActiveModule("mic");
                break;
            case "wifi":
            case "network":
                Visibilities.setActiveModule("wifi");
                break;
            case "bluetooth":
                Visibilities.setActiveModule("bluetooth");
                break;
            case "battery":
            case "powerprofile":
                Visibilities.setActiveModule("battery");
                break;
            case "weather":
                Visibilities.setActiveModule("weather");
                break;
            case "calendar":
            case "datetime":
                Visibilities.setActiveModule("calendar");
                break;
            case "lockscreen": LockscreenService.lock(); break;
            case "config":
            case "settings":
            case "dashboard-controls":
                toggleSettings();
                break;
            case "appearance":
                if (!GlobalStates.settingsWindowVisible)
                    toggleSettings();
                GlobalStates.settingsCurrentTab = 4;
                break;
            case "new-window-rule":
                if (!GlobalStates.settingsWindowVisible)
                    toggleSettings();
                GlobalStates.settingsCurrentTab = 8;
                GlobalStates.settingsNewWindowRuleRequested = true;
                break;
            default: console.warn("Unknown IPC command:", command);
        }
    }

    property IpcHandler ipcHandler: IpcHandler {
        target: "rebos_shell"

        function run(command: string) {
            root.run(command);
        }

        function wallpaper(path: string, mode: string): bool {
            const manager = GlobalStates.wallpaperManager;
            if (!manager || !path || manager.supportedWallpaperModes.indexOf(mode) === -1)
                return false;
            manager.setWallpaperMode(mode);
            manager.setWallpaper(path);
            return true;
        }

        function themeStyle(style: string): bool {
            if (!ShellStyles.styles.some(entry => entry.id === style)) return false;
            Config.theme.shellStyle = style;
            return true;
        }

        function borderStyle(style: string): bool {
            if (["band", "dotted", "double"].indexOf(style) === -1) return false;
            Config.theme.ditherBorder = style;
            return true;
        }

        function wallpaperDitherStrength(strength: string): bool {
            if (["normal", "strong", "intense"].indexOf(strength) === -1) return false;
            Config.theme.wallpaperDitherStrength = strength;
            return true;
        }

        function themeStatus(): string {
            const manager = GlobalStates.wallpaperManager;
            return JSON.stringify({style: Config.theme.shellStyle,
                ditherPalette: Config.theme.ditherPalette,
                border: Config.theme.ditherBorder,
                wallpaperStrength: Config.theme.wallpaperDitherStrength,
                wallpaper: manager?.currentWallpaper ?? "",
                renderedWallpaper: manager?.renderedWallpaper ?? "",
                themeColorSource: manager ? manager.getColorSource(manager.currentWallpaper) : "",
                converting: DitheredWallpapers.busy,
                error: DitheredWallpapers.error});
        }
    }

    function toggleLauncher() {
        if ((Config.bar?.style ?? "default") === "island") {
            const island = Visibilities.getIslandForActive();
            if (island) {
                if (island.isExpanded && island.currentMode === "apps") {
                    island.collapse();
                } else {
                    GlobalStates.launcherMode = "apps";
                    GlobalStates.clearLauncherState();
                    island.expand("apps");
                }
                return;
            }
        }

        const isActive = Visibilities.currentActiveModule === "launcher"
            && GlobalStates.launcherMode === "apps";
        if (isActive) {
            Visibilities.setActiveModule("");
        } else {
            GlobalStates.launcherMode = "apps";
            GlobalStates.clearLauncherState();
            Visibilities.setActiveModule("launcher");
        }
    }

    function toggleProjects() {
        if ((Config.bar?.style ?? "default") === "island") {
            const island = Visibilities.getIslandForActive();
            if (island) {
                if (island.isExpanded && island.currentMode === "projects") {
                    island.collapse();
                } else {
                    GlobalStates.launcherMode = "projects";
                    GlobalStates.clearProjectPickerState();
                    island.expand("projects");
                }
                return;
            }
        }

        const isActive = Visibilities.currentActiveModule === "launcher"
            && GlobalStates.launcherMode === "projects";
        if (isActive) {
            Visibilities.setActiveModule("");
        } else {
            GlobalStates.launcherMode = "projects";
            GlobalStates.clearProjectPickerState();
            Visibilities.setActiveModule("launcher");
        }
    }

    function toggleWallpapers() {
        if ((Config.bar?.style ?? "default") === "island") {
            const island = Visibilities.getIslandForActive();
            if (island) {
                if (island.isExpanded && island.currentMode === "wallpapers") {
                    island.collapse();
                } else {
                    Visibilities.clearAll();
                    Visibilities.currentActiveModule = "wallpapers";
                    island.expand("wallpapers");
                }
                return;
            }
        }

        const controller = Visibilities.getDashboardControllerForActive();
        if (!controller) {
            console.warn("GlobalShortcuts: no dashboard controller registered for the focused monitor");
            return;
        }
        controller.toggleWallpapers();
    }

    function toggleAlerts() {
        if ((Config.bar?.style ?? "default") === "island") {
            const island = Visibilities.getIslandForActive();
            if (island) {
                if (island.isExpanded && island.currentMode === "alerts") {
                    island.collapse();
                } else {
                    Visibilities.clearAll();
                    Visibilities.currentActiveModule = "alerts";
                    island.expand("alerts");
                }
                return;
            }
        }
        Visibilities.setActiveModule("alerts");
    }

    function toggleDashboard() {
        if ((Config.bar?.style ?? "default") === "island") {
            const island = Visibilities.getIslandForActive();
            if (island) {
                if (island.isExpanded && island.currentMode === "dashboard") {
                    island.collapse();
                } else {
                    Visibilities.clearAll();
                    Visibilities.currentActiveModule = "dashboard";
                    island.expand("dashboard");
                }
                return;
            }
        }

        const controller = Visibilities.getDashboardControllerForActive();
        if (!controller) {
            console.warn("GlobalShortcuts: no dashboard controller registered for the focused monitor");
            return;
        }
        controller.toggleCenterMenu();
    }

    function toggleSettings(screenName) {
        const willOpen = !GlobalStates.settingsWindowVisible;
        if (willOpen) {
            const targetMonitor = screenName
                ? NiriService.monitorFor(screenName)
                : NiriService.focusedMonitor;
            GlobalStates.settingsTargetWorkspaceId =
                targetMonitor?.activeWorkspace?.id
                || NiriService.focusedMonitor?.activeWorkspace?.id
                || NiriService.focusedWorkspace?.id
                || 0;
            GlobalStates.settingsTargetScreenName =
                targetMonitor?.name || NiriService.focusedMonitor?.name || "";
            // Close bar popups / run menu under the settings window.
            Visibilities.closeActiveBarPopup();
            Visibilities.setActiveModule("");
        }
        GlobalStates.settingsWindowVisible = willOpen;
    }

    function toggleAssistant() {
        if (!GlobalStates.assistantAvailable) {
            GlobalStates.hideAssistant();
            return;
        }
        GlobalStates.toggleAssistant();
    }
}
