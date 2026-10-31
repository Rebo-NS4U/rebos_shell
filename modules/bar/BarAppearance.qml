pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.modules.theme
import "../../config/defaults/bar.js" as BarDefaults

Singleton {
    id: root
    readonly property color foregroundColor: Colors.overBackground
    readonly property color activeWorkspaceOutline: foregroundColor
    readonly property bool polished: (Config.bar?.islandAppearance ?? BarDefaults.data.islandAppearance) === "glass"
    readonly property real opacity: Math.max(20, Math.min(100, Config.bar?.islandOpacity ?? BarDefaults.data.islandOpacity)) / 100
    readonly property real accent: Math.max(0, Math.min(100, Config.bar?.islandAccent ?? BarDefaults.data.islandAccent)) / 100

    function panelOpacity(expanded: bool): real {
        return Styling.shellStyle === "quiet" || Styling.shellStyle === "dithered" ? 1 : (polished ? (expanded ? Math.max(0.94, opacity) : opacity) : 1);
    }
    function panelTint(expanded: bool): color {
        return Qt.alpha(Colors.primary, accent * 0.28);
    }
    function panelBorder(expanded: bool): color {
        return Styling.shellStyle === "quiet" || Styling.shellStyle === "dithered" ? Config.resolveColor(Styling.getStyledRectConfig("popup").border[0]) : Qt.alpha(Colors.primary, polished ? accent * (expanded ? 0.33 : 0.44) : 0);
    }
    function clockTint(hovered: bool): color {
        return Qt.alpha(Colors.primary, polished ? accent * (hovered ? 0.29 : 0.145) : 0);
    }
    function reset(): void {
        Config.bar.islandAppearance = BarDefaults.data.islandAppearance;
        Config.bar.islandOpacity = BarDefaults.data.islandOpacity;
        Config.bar.islandAccent = BarDefaults.data.islandAccent;
    }
}
