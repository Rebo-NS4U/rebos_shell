import QtQuick
import qs.modules.theme

QtObject {
    property var dynamicItems: []

    readonly property var staticItems: [
        { label: "Display", keywords: "monitor screen resolution refresh rate hz scale scaling rotation orientation position layout", section: 9, subSection: "", subLabel: "", icon: Icons.layout, isIcon: true },
        { label: "Network", keywords: "internet wifi connection ethernet ip", section: 0, subSection: "", subLabel: "", icon: Icons.wifiHigh, isIcon: true },
        { label: "Bluetooth", keywords: "devices pairing connect", section: 1, subSection: "", subLabel: "", icon: Icons.bluetooth, isIcon: true },
        { label: "Sound", keywords: "sound volume output input mic speaker", section: 2, subSection: "", subLabel: "", icon: Icons.faders, isIcon: true },
        { label: "Assistant", keywords: "assistant agent acp codex enable disable", section: 3, subSection: "", subLabel: "", icon: Icons.robot, isIcon: true },

        { label: "Appearance", keywords: "theme appearance look style customize", section: 4, subSection: "", subLabel: "Appearance", icon: Icons.paintBrush, isIcon: true },
        { label: "Theme style", keywords: "theme zen spotify kitty vscode neovim gtk qt apps appearance transparent opaque tinted glass quiet dark colorful preset transparency assistant launcher menus notifications custom", section: 4, subSection: "style", subLabel: "Appearance > Theme style", icon: Icons.paintBrush, isIcon: true },
        { label: "Fonts and corners", keywords: "wallpaper icons font roundness", section: 4, subSection: "general", subLabel: "Appearance > Fonts and corners", icon: Icons.paintBrush, isIcon: true },
        { label: "Motion", keywords: "animation animations movement speed duration smooth quick reduced off transitions", section: 4, subSection: "motion", subLabel: "Appearance > Motion", icon: Icons.lightning, isIcon: true },
        { label: "Blur", keywords: "gpu graphics performance video glass lighter shell panels off full blur", section: 4, subSection: "blur", subLabel: "Appearance > Blur", icon: Icons.drop, isIcon: true },
        { label: "Shadows", keywords: "opacity blur offset color", section: 4, subSection: "shadow", subLabel: "Appearance > Shadow", icon: Icons.drop, isIcon: true },
        { label: "Colors", keywords: "matugen wallpaper scheme palette oled light dark kitty fish spotify zen vscode opacity refresh", section: 4, subSection: "colors", subLabel: "Appearance > Colors", icon: Icons.palette, isIcon: true },

        { label: "Backgrounds and borders", keywords: "variant gradient border halftone shell colors", section: 4, subSection: "variants", subLabel: "Appearance > Backgrounds and borders", icon: Icons.palette, isIcon: true },

        { label: "System", keywords: "hardware info resources cpu ram weather performance", section: 5, subSection: "", subLabel: "System", icon: Icons.circuitry, isIcon: true },
        { label: "Weather", keywords: "location temperature celsius fahrenheit", section: 5, subSection: "weather", subLabel: "System > Weather", icon: Icons.mapPin, isIcon: true },
        { label: "Effects", keywords: "performance animations preview effects dashboard", section: 5, subSection: "performance", subLabel: "System > Effects", icon: Icons.lightning, isIcon: true },
        { label: "Storage", keywords: "cpu ram memory disk usage monitor", section: 5, subSection: "system", subLabel: "System > Storage", icon: Icons.circuitry, isIcon: true },

        { label: "Shell", keywords: "bar sidebar lockscreen settings", section: 6, subSection: "", subLabel: "Shell", icon: Icons.gear, isIcon: true },
        { label: "Bar", keywords: "panel taskbar clock player screen glass classic appearance transparency opacity accent reset", section: 6, subSection: "bar", subLabel: "Shell > Bar", icon: Icons.layout, isIcon: true },
        { label: "Lock screen", keywords: "lock screen password login position", section: 6, subSection: "lockscreen", subLabel: "Shell > Lock screen", icon: Icons.lock, isIcon: true },
        { label: "About", keywords: "about sponsor version", section: 6, subSection: "system", subLabel: "Shell > About", icon: Icons.circuitry, isIcon: true },
        { label: "Assistant panel", keywords: "ai sidebar enable disable width position pinned", section: 6, subSection: "sidebar", subLabel: "Shell > Assistant panel", icon: Icons.robot, isIcon: true },
        { label: "Keyboard shortcuts", keywords: "keyboard shortcuts hotkeys binds super windows niri kitty terminal launcher workspace screenshot volume brightness", section: 7, subSection: "", subLabel: "", icon: Icons.keyboard, isIcon: true },
        { label: "Window rules", keywords: "niri focused app match title floating fullscreen maximized opacity corners radius workspace width", section: 8, subSection: "", subLabel: "", icon: Icons.layout, isIcon: true }
    ]

    property var items: staticItems.concat(dynamicItems)

    function addDynamicItems(newItems) {
        let currentLabels = new Set(items.map(item => item.section + ":" + item.label));
        let uniqueNew = [];

        for (let i = 0; i < newItems.length; i++) {
            let item = newItems[i];
            let key = item.section + ":" + item.label;
            if (!currentLabels.has(key)) {
                uniqueNew.push(item);
                currentLabels.add(key);
            }
        }

        if (uniqueNew.length > 0) {
            dynamicItems = dynamicItems.concat(uniqueNew);
        }
    }
}
