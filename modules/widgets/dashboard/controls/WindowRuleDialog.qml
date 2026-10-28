pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.theme

Dialog {
    id: root
    parent: Overlay.overlay
    modal: true
    closePolicy: Popup.CloseOnEscape
    width: Math.min(Styling.fontSize(0) * 44, (parent?.width ?? 900) - Styling.fontSize(0) * 2)
    height: Math.min(Styling.fontSize(0) * 43, (parent?.height ?? 650) - Styling.fontSize(0) * 2)
    x: ((parent?.width ?? width) - width) / 2
    y: ((parent?.height ?? height) - height) / 2
    padding: Styling.fontSize(0)
    background: StyledRect { variant: "popup" }
    property string ruleId: ""
    property bool ruleEnabled: true
    property bool busy: false
    property string errorMessage: ""
    signal saveRequested(var rule)

    function choiceIndex(value): int {
        return value === "true" ? 1 : value === "false" ? 2 : 0;
    }
    function choiceValue(index): string {
        return index === 1 ? "true" : index === 2 ? "false" : "inherit";
    }
    function edit(rule): void {
        ruleId = rule.id || "";
        ruleEnabled = rule.enabled ?? true;
        nameInput.text = rule.name || rule.appId || "New window rule";
        appInput.text = rule.appId || "";
        titleInput.text = rule.title || "";
        matchTitle.checked = ruleId !== "" && !!rule.title;
        regexInput.checked = rule.regex ?? false;
        floatingInput.currentIndex = choiceIndex(rule.floating);
        maximizedInput.currentIndex = choiceIndex(rule.maximized);
        fullscreenInput.currentIndex = choiceIndex(rule.fullscreen);
        workspaceInput.text = rule.workspace || "";
        opacityInput.text = String(rule.opacity ?? "");
        radiusInput.text = String(rule.radius ?? "");
        widthInput.text = String(rule.width ?? "");
        errorMessage = "";
        open();
    }

    function save(): void {
        if (busy) return;
        saveRequested({id: ruleId, name: nameInput.text, appId: appInput.text,
            title: matchTitle.checked ? titleInput.text : "", regex: regexInput.checked,
            enabled: ruleEnabled, floating: choiceValue(floatingInput.currentIndex),
            maximized: choiceValue(maximizedInput.currentIndex), fullscreen: choiceValue(fullscreenInput.currentIndex),
            workspace: workspaceInput.text, opacity: opacityInput.text, radius: radiusInput.text,
            width: widthInput.text});
    }

    component Caption: StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Colors.overSurfaceVariant
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
    }
    component Field: SettingsTextField { Layout.fillWidth: true }
    component Choice: SettingsComboBox {
        Layout.fillWidth: true
        model: ["Inherit", "Yes", "No"]
    }
    component Check: StyledSwitch {
        palette.windowText: Colors.overSurface
        palette.highlight: Colors.primary
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
    }
    component Action: SettingsButton {}

    contentItem: ColumnLayout {
        spacing: Styling.fontSize(-3)
        Caption {
            text: root.ruleId ? "Edit window rule" : "New window rule"
            font.bold: true
            font.pixelSize: Styling.fontSize(2)
            color: Colors.overSurface
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: parent.width
                spacing: Styling.fontSize(-4)
                enabled: !root.busy
                Caption { text: "Rule name" }
                Field { id: nameInput; objectName: "rule-name-input" }
                Caption { text: "Match app ID" }
                Field { id: appInput; objectName: "rule-app-input"; placeholderText: "For example: kitty" }
                Check { id: matchTitle; objectName: "rule-match-title"; text: "Also match the window title" }
                Field { id: titleInput; objectName: "rule-title-input"; enabled: matchTitle.checked; placeholderText: "Window title" }
                Caption { text: "The app and title are filled from your last focused app. Leave title matching off to cover every window of that app." }
                Check { id: regexInput; text: "Treat app ID and title as regular expressions" }
                RowLayout {
                    ColumnLayout { Layout.fillWidth: true; Caption { text: "Open floating" } Choice { id: floatingInput; objectName: "rule-floating-input" } }
                    ColumnLayout { Layout.fillWidth: true; Caption { text: "Open maximized" } Choice { id: maximizedInput } }
                    ColumnLayout { Layout.fillWidth: true; Caption { text: "Open fullscreen" } Choice { id: fullscreenInput } }
                }
                Caption { text: "Open on workspace (optional)" }
                Field { id: workspaceInput; placeholderText: "For example: dev, web, chat, media" }
                RowLayout {
                    ColumnLayout { Layout.fillWidth: true; Caption { text: "Opacity (0–1)" } Field { id: opacityInput; placeholderText: "Inherit" } }
                    ColumnLayout { Layout.fillWidth: true; Caption { text: "Corners (px)" } Field { id: radiusInput; placeholderText: "Inherit" } }
                    ColumnLayout { Layout.fillWidth: true; Caption { text: "Column width (%)" } Field { id: widthInput; placeholderText: "Inherit" } }
                }
                Caption { text: "Blank values and Inherit keep your existing rules. Opening behavior takes effect on new windows." }
            }
        }
        Caption { visible: !!root.errorMessage; text: root.errorMessage; color: Colors.error }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            Action { text: "Cancel"; enabled: !root.busy; onClicked: root.close() }
            Action { objectName: "rule-save-button"; text: root.busy ? "Saving…" : "Save rule"; enabled: !root.busy; onClicked: root.save() }
        }
    }
}
