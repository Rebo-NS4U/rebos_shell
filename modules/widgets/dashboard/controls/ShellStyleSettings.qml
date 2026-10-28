pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import "../../../theme/ShellStyles.js" as ShellStyles

ColumnLayout {
    id: root
    property string settingsSection: "style"
    spacing: 12

    StyledText {
        text: "Theme style"
        font.pixelSize: Styling.fontSize(4)
        font.bold: true
    }
    StyledText {
        Layout.fillWidth: true
        text: "Set backgrounds and colors for the shell and supported apps. Dithered also converts still wallpapers automatically."
        wrapMode: Text.WordWrap
        font.pixelSize: Styling.fontSize(-1)
        color: Colors.overSurfaceVariant
    }
    GridLayout {
        columns: root.width < Styling.fontSize(0) * 26 ? 1 : 2
        Layout.fillWidth: true
        columnSpacing: 10
        rowSpacing: 10
        Repeater {
            model: ShellStyles.styles
            delegate: Button {
                id: card
                required property var modelData
                objectName: "shell-style-" + modelData.id
                readonly property bool selected: Styling.shellStyle === modelData.id
                readonly property var sample: Styling.styleConfig(modelData.id, "bg")
                Layout.fillWidth: true
                implicitHeight: Styling.fontSize(0) * 14
                padding: 12
                onClicked: Config.theme.shellStyle = modelData.id
                background: StyledRect {
                    variant: card.hovered ? "focus" : "common"
                    radius: Styling.radius(-2)
                    border.width: card.selected || card.activeFocus ? 2 : 1
                    border.color: card.selected || card.activeFocus ? Colors.primary : Qt.alpha(Colors.outline, 0.3)
                }
                contentItem: ColumnLayout {
                    spacing: 8
                    StyledRect {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Styling.fontSize(0) * 5.5
                        variant: "bg"
                        styleOverride: card.modelData.id
                        enableBorder: false
                        radius: Styling.radius(-5)
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                StyledText { text: Icons.layout; font.family: Icons.font; color: Colors.primary }
                                Item { Layout.fillWidth: true }
                                StyledText { text: "10:24"; font.pixelSize: Styling.fontSize(-3); font.family: Config.theme.monoFont }
                                StyledText { text: Icons.bell; font.family: Icons.font; color: Colors.primary }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Repeater {
                                    model: [Colors.primary, Colors.secondary, Colors.tertiary]
                                    delegate: StyledRect {
                                        required property color modelData
                                        variant: "transparent"
                                        color: Qt.alpha(modelData, card.modelData.id === "colorful" ? 0.42 : 0.20)
                                        radius: Styling.radius(-6)
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        implicitHeight: Styling.fontSize(0) * 1.5
                                        enableBorder: false
                                    }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            text: card.modelData.label
                            font.pixelSize: Styling.fontSize(-1)
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        StyledText {
                            visible: card.selected
                            text: Icons.check
                            font.family: Icons.font
                            color: Colors.primary
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: card.modelData.description
                        wrapMode: Text.WordWrap
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                    }
                }
            }
        }
    }
    StyledRect {
        visible: Styling.shellStyle === "dithered"
        variant: "internalbg"
        Layout.fillWidth: true
        implicitHeight: ditherSettings.implicitHeight + 24
        ColumnLayout {
            id: ditherSettings
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            StyledText { text: "Shell dithering"; font.bold: true }
            StyledText { text: "Border style" }
            SettingsComboBox {
                objectName: "dither-border"
                Layout.fillWidth: true
                model: [{label: "Dithered edge", value: "band"},
                        {label: "Round dots", value: "dotted"}, {label: "Double line", value: "double"}]
                textRole: "label"
                valueRole: "value"
                currentIndex: Config.theme.ditherBorder === "dotted" ? 1
                    : Config.theme.ditherBorder === "double" ? 2 : 0
                onActivated: Config.theme.ditherBorder = currentValue
            }
            RowLayout {
                Layout.fillWidth: true
                StyledSlider {
                    id: strengthSlider
                    objectName: "dither-strength"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    stepSize: 0.01
                    snapMode: "always"
                    smoothDrag: false
                    property bool ready: false
                    readonly property real configValue: Config.theme.ditherStrength / 100
                    onConfigValueChanged: value = configValue
                    Component.onCompleted: { value = configValue; ready = true; }
                    onValueChanged: {
                        const strength = Math.round(value * 100);
                        if (ready && strength !== Config.theme.ditherStrength)
                            Config.theme.ditherStrength = strength;
                    }
                }
                StyledText {
                    text: Config.theme.ditherStrength + "%"
                    Layout.preferredWidth: Styling.fontSize(0) * 3
                    horizontalAlignment: Text.AlignRight
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                text: "Increase for larger, bolder dots on the bar, panels, menus, buttons and outlines. 20% keeps subtle panel dots; 0% removes shell texture and patterned outlines. Text stays crisp."
            }
            StyledText { text: "Wallpaper conversion"; font.bold: true }
            SettingsComboBox {
                objectName: "wallpaper-dither-strength"
                Layout.fillWidth: true
                model: [{label: "Normal · 24 colors", value: "normal"},
                        {label: "Strong · 6 colors", value: "strong"},
                        {label: "Intense · 4 colors", value: "intense"}]
                textRole: "label"
                valueRole: "value"
                currentIndex: Config.theme.wallpaperDitherStrength === "normal" ? 0
                    : Config.theme.wallpaperDitherStrength === "intense" ? 2 : 1
                onActivated: Config.theme.wallpaperDitherStrength = currentValue
            }
            SettingsComboBox {
                objectName: "dither-palette"
                Layout.fillWidth: true
                model: [ {label: "Keep photo colors", value: "original"},
                         {label: "Teal and orange", value: "teal-orange"},
                         {label: "Main color", value: "tint"} ]
                textRole: "label"
                valueRole: "value"
                currentIndex: Config.theme.ditherPalette === "tint" ? 2
                    : Config.theme.ditherPalette === "teal-orange" ? 1 : 0
                onActivated: Config.theme.ditherPalette = currentValue
            }
            WallpaperTintSwatches {
                visible: Config.theme.ditherPalette === "tint"
                Layout.fillWidth: true
            }
            RowLayout {
                visible: Config.theme.ditherPalette === "tint"
                Layout.fillWidth: true
                SettingsButton {
                    objectName: "dither-tint-picker"
                    text: "Choose main color"
                    onClicked: {
                        tintDialog.selectedColor = Config.theme.ditherTintColor;
                        tintDialog.open();
                    }
                    icon.name: "color-picker"
                }
                StyledRect {
                    variant: "common"
                    implicitWidth: Styling.fontSize(0) * 2
                    implicitHeight: implicitWidth
                    objectName: "dither-tint-preview"
                    fillColor: Config.theme.ditherTintColor
                    backgroundOpacity: 1
                }
                SettingsTextField {
                    objectName: "dither-tint-hex"
                    Layout.fillWidth: true
                    text: Config.theme.ditherTintColor
                    placeholderText: "#RRGGBB"
                    validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{6}/ }
                    onEditingFinished: {
                        if (acceptableInput) Config.theme.ditherTintColor = text.toLowerCase();
                        else text = Config.theme.ditherTintColor;
                    }
                }
            }
            ColorDialog {
                id: tintDialog
                title: "Wallpaper main color"
                onAccepted: Config.theme.ditherTintColor = selectedColor.toString().toLowerCase()
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                text: DitheredWallpapers.busy ? "Converting wallpaper…" :
                    "Still images convert locally into cached PNG copies. Originals and text stay intact. Videos and animated wallpapers keep their original appearance."
            }
            StyledText {
                visible: DitheredWallpapers.error !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Colors.error
                text: DitheredWallpapers.error
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: "Changes save automatically. Restart Zen and reopen apps that have not updated."
        wrapMode: Text.WordWrap
        font.pixelSize: Styling.fontSize(-1)
        color: Colors.overSurfaceVariant
    }
    StyledRect {
        variant: "internalbg"
        Layout.fillWidth: true
        implicitHeight: coverage.implicitHeight + 32
        ColumnLayout {
            id: coverage
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8
            StyledText { text: "App themes"; font.bold: true; color: Colors.primary }
            StyledText {
                Layout.fillWidth: true
                text: "Quickshell & Settings  ·  Zen  ·  Kitty & Fish  ·  Spotify  ·  VS Code  ·  Neovim  ·  GTK & Qt apps  ·  Vesktop  ·  Fuzzel & btop  ·  Sioyek"
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                text: "Each app applies the colors and transparency it supports."
                wrapMode: Text.WordWrap
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }
        }
    }

}
