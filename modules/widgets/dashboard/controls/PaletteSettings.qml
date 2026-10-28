pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.modules.globals
import qs.modules.services
import qs.modules.theme
import qs.modules.components
import "../../../theme/PaletteSchemes.js" as PaletteSchemes

ColumnLayout {
    id: root
    property string settingsSection: "colors"
    readonly property PanelWindow manager: GlobalStates.wallpaperManager
    readonly property bool busy: manager?.paletteBusy ?? false
    readonly property string preset: manager?.activeColorPreset ?? ""
    spacing: 12

    component Caption: Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
        color: Colors.overSurfaceVariant
    }

    component Action: Button {
        id: button
        property bool selected: false
        implicitHeight: 38
        Layout.fillWidth: true
        background: StyledRect {
            variant: button.selected ? "primary" : (button.hovered ? "focus" : "common")
        }
        contentItem: Text {
            text: button.text
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            color: button.selected ? Colors.overPrimary : Colors.overSurface
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    Text {
        text: "Wallpaper colors"
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(1)
        font.bold: true
        color: Colors.overSurface
    }
    Caption {
        text: "Matugen creates one palette for the desktop and your apps. Neutral is subtle; Tonal spot and Vibrant bring out more wallpaper color."
    }
    Caption {
        text: root.manager ? "Current wallpaper: " + (root.manager.currentWallpaper.split("/").pop() || "None selected") : "Wallpaper controls are not ready yet."
    }
    RowLayout {
        Action {
            text: "Dark"
            selected: !Config.theme.lightMode
            onClicked: Config.theme.lightMode = false
        }
        Action {
            text: "Light"
            selected: Config.theme.lightMode
            onClicked: Config.theme.lightMode = true
        }
        Action {
            text: "OLED blacks"
            selected: Config.oledMode
            enabled: !Config.theme.lightMode
            onClicked: Config.theme.oledMode = !Config.theme.oledMode
        }
    }
    Caption { text: "Wallpaper scheme" }
    ComboBox {
        id: schemeSelector
        Layout.fillWidth: true
        enabled: root.manager !== null
        model: PaletteSchemes.schemes
        textRole: "label"
        valueRole: "id"
        currentIndex: PaletteSchemes.schemes.findIndex(scheme => scheme.id === (root.manager?.currentMatugenScheme ?? "scheme-tonal-spot"))
        palette.button: Colors.surface
        palette.buttonText: Colors.overSurface
        palette.base: Colors.surface
        palette.text: Colors.overSurface
        palette.highlight: Colors.primary
        palette.highlightedText: Colors.overPrimary
        onActivated: root.manager.setMatugenScheme(currentValue)
    }
    Caption {
        visible: root.preset !== ""
        text: "Preset active: " + root.preset + ". Choose a wallpaper scheme to resume wallpaper colors."
    }
    RowLayout {
        Action {
            text: root.busy ? "Generating…" : "Regenerate colors"
            enabled: root.manager !== null && !root.busy && root.preset === "" && !!root.manager.currentWallpaper
            onClicked: root.manager.runMatugenForCurrentWallpaper()
        }
        Action {
            text: "Choose wallpaper / preset"
            onClicked: {
                GlobalStates.settingsWindowVisible = false;
                GlobalShortcuts.toggleWallpapers();
            }
        }
    }
    Caption {
        visible: !!root.manager?.paletteError
        text: root.manager?.paletteError ?? ""
        color: Colors.error
    }
    RowLayout {
        Repeater {
            model: ["background", "surface", "primary", "secondary", "tertiary", "overSurface"]
            delegate: StyledRect {
                id: paletteSwatch
                variant: "common"
                required property string modelData
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Styling.radius(-4)
                fillColor: Colors[modelData]
                backgroundOpacity: 1
                StyledToolTip {
                    show: hover.hovered
                    tooltipText: paletteSwatch.modelData + ": " + paletteSwatch.fillColor
                }
                HoverHandler { id: hover }
            }
        }
    }
    Caption { text: "Background opacity: " + Math.round(Config.theme.srBg.opacity * 100) + "%" }
    Slider {
        Layout.fillWidth: true
        from: 0.2
        to: 1
        stepSize: 0.05
        value: Config.theme.srBg.opacity
        onMoved: Config.theme.srBg.opacity = value
        palette.highlight: Colors.primary
        palette.button: Colors.overSurface
    }
    Caption {
        text: "Opacity applies to supported app backgrounds. The islands bar keeps its transparent outer background."
    }
    Text {
        text: "Connected apps"
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(0)
        font.bold: true
        color: Colors.overSurface
    }
    Caption {
        text: "Updates live: QuickShell, Niri borders, Kitty, fish, fuzzy search, GTK and VS Code. Spotify refreshes through Spicetify after setup."
    }
    Caption {
        text: "Reopen Zen after a palette change. Fuzzel and btop use new colors on launch; some Qt and KDE apps need reopening."
    }
    Action {
        text: "Refresh app themes"
        onClicked: {
            Colors.refreshApps();
            refreshNotice.restart();
        }
    }
    Caption {
        visible: refreshNotice.running
        text: "Refreshing apps with the current palette."
    }
    Timer { id: refreshNotice; interval: 3000 }
    Caption {
        text: "Terminal search: Ctrl+R for history, Ctrl+T for files, Alt+C for folders, Shift+Tab for fuzzy completion, and Ctrl+Shift+F for Kitty scrollback."
    }
}
