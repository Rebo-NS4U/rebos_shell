pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

Item {
    id: root
    objectName: "display-settings-panel"
    property int maxContentWidth: 760
    property string selectedName: ""
    property string message: ""
    property bool failed: false
    property string requestText: ""
    property list<var> outputs: []
    readonly property var selectedOutput: outputs.find(output => output.name === selectedName) ?? null
    readonly property list<string> transforms: ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"]
    readonly property list<var> modes: (selectedOutput?.modes ?? []).map(mode => ({
        value: mode.width + "x" + mode.height + "@" + (mode.refresh_rate / 1000).toFixed(3),
        label: mode.width + " × " + mode.height + " · " + (mode.refresh_rate / 1000).toFixed(2) + " Hz" + (mode.is_preferred ? " (recommended)" : "")
    }))

    function refresh(): void {
        if (!reader.running && !writer.running) reader.running = true;
    }
    function editSelected(): void {
        const output = selectedOutput;
        if (!output) return;
        modeChoice.currentIndex = output.current_mode ?? -1;
        scaleInput.text = String(Math.round((output.logical?.scale ?? 1) * 100));
        rotationChoice.currentIndex = Math.max(0, transforms.indexOf(output.logical?.transform ?? "normal"));
        xInput.text = String(output.logical?.x ?? 0);
        yInput.text = String(output.logical?.y ?? 0);
    }
    function apply(): void {
        if (writer.running || reader.running || !selectedOutput) return;
        requestText = JSON.stringify({name: selectedName, mode: modes[modeChoice.currentIndex]?.value ?? "",
            scale: Number(scaleInput.text) / 100, transform: transforms[rotationChoice.currentIndex],
            x: Number(xInput.text), y: Number(yInput.text)});
        message = "";
        writer.running = true;
    }
    onSelectedNameChanged: editSelected()
    Component.onCompleted: refresh()

    Process {
        id: reader
        command: ["niri", "msg", "--json", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.outputs = Object.keys(data).map(name => Object.assign({}, data[name], {name: name}));
                    if (!root.outputs.some(output => output.name === root.selectedName))
                        root.selectedName = root.outputs[0]?.name ?? "";
                    root.editSelected();
                } catch (error) {
                    root.failed = true;
                    root.message = "Could not read displays. Try Refresh.";
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) { root.failed = true; root.message = "Could not contact Niri. Try Refresh."; }
        }
    }
    Process {
        id: writer
        command: ["python3", Quickshell.shellPath("scripts/display_settings.py")]
        stdinEnabled: true
        onStarted: write(root.requestText + "\n")
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.failed = !result.ok;
                    root.message = result.ok ? result.message : result.error;
                } catch (error) {
                    root.failed = true;
                    root.message = "Could not save display settings.";
                }
            }
        }
        onExited: (code, status) => {
            root.requestText = "";
            if (code !== 0) { root.failed = true; root.message = "Could not save display settings."; }
            else refreshTimer.restart();
        }
    }
    Timer { id: refreshTimer; interval: 500; onTriggered: root.refresh() }
    Connections {
        target: NiriService
        function onRawOutputsChanged() { refreshTimer.restart(); }
    }

    component Caption: StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-1)
        color: Colors.overSurfaceVariant
    }
    component Choice: SettingsComboBox {
        Layout.fillWidth: true
    }
    component Input: SettingsTextField { Layout.fillWidth: true }
    ColumnLayout {
        width: Math.min(root.width, root.maxContentWidth)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: Styling.fontSize(-3)
        PanelTitlebar {
            title: "Display"
            description: "Set monitor resolution, scale, rotation and position."
            statusText: reader.running ? "Loading…" : root.outputs.length + " connected"
            actions: [{icon: Icons.sync, tooltip: "Refresh displays", enabled: !reader.running && !writer.running,
                onClicked: function () { root.refresh(); }}]
        }
        Caption {
            visible: root.outputs.length === 0 && !reader.running
            text: "No connected displays found."
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: parent.width
                spacing: Styling.fontSize(-3)
                enabled: !writer.running && !reader.running && root.outputs.length > 0
                SettingsGroup {
                    title: "Monitor"
                Choice {
                    id: monitorChoice
                    objectName: "display-monitor"
                    model: root.outputs.map(output => output.name + " · " + (output.model || output.make || "Display"))
                    currentIndex: root.outputs.findIndex(output => output.name === root.selectedName)
                    onActivated: root.selectedName = root.outputs[currentIndex].name
                }
                Caption {
                    text: root.selectedOutput?.current_mode === null ? "This display is disabled. Enable it in your Niri configuration to edit its settings." : "Choose a resolution and refresh rate supported by your monitor."
                }
                }
                SettingsGroup {
                    title: "Size and position"
                    enabled: root.selectedOutput?.current_mode !== null
                    Caption { text: "Resolution & refresh rate" }
                    Choice { id: modeChoice; objectName: "display-mode"; model: root.modes; textRole: "label" }
                    Caption { text: "Scale (%) · higher values make text and controls larger" }
                    Input { id: scaleInput; objectName: "display-scale"; validator: IntValidator { bottom: 50; top: 400 } }
                    Caption { text: "Rotation" }
                    Choice {
                        id: rotationChoice
                        objectName: "display-rotation"
                        model: ["Normal", "90°", "180°", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"]
                    }
                    Caption { text: "Position · logical pixels from the top left of your desktop" }
                    RowLayout {
                        Layout.fillWidth: true
                        Caption { text: "X"; Layout.fillWidth: false }
                        Input { id: xInput; objectName: "display-x"; validator: IntValidator { bottom: -100000; top: 100000 } }
                        Caption { text: "Y"; Layout.fillWidth: false }
                        Input { id: yInput; objectName: "display-y"; validator: IntValidator { bottom: -100000; top: 100000 } }
                    }
                    Caption { text: "For side-by-side monitors, place the second monitor at the first monitor’s scaled width. Changes are saved for future sessions." }
                    SettingsButton {
                        id: applyButton
                        objectName: "display-apply"
                        text: writer.running ? "Applying…" : "Apply display settings"
                        enabled: modeChoice.currentIndex >= 0 && scaleInput.acceptableInput && xInput.acceptableInput && yInput.acceptableInput


                        onClicked: root.apply()
                    }
                }
            }
        }
        Caption { visible: root.message !== ""; text: root.message; color: root.failed ? Colors.error : Colors.primary }
    }
}
