"""Exercise model switching and search in real QML with synthetic ACP replies."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

SCENARIO = r'''
import QtQuick
import Quickshell
import qs.modules.services
import qs.modules.sidebar
ShellRoot {
    id: test
    readonly property var sent: Ai.activeSession.syntheticEnvelope
    function check(condition, message) {
        if (!condition) { console.error("FAIL", message); Qt.exit(1); }
    }
    function findNamed(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) {
            let found = findNamed(child, name);
            if (found) return found;
        }
        return null;
    }
    Window {
        visible: true
        width: 340; height: 500
        AssistantModelPicker { id: picker; width: 320; expanded: true }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {

            Ai.activeSession.sessionReady = true;
            Ai.activeSession.currentSessionId = "synthetic-session";
            Ai.activeSession.updateSessionConfiguration({configOptions: [{id: "model", category: "model", currentValue: "first", options: [
                {value: "first", name: "First model", description: "Everyday tasks"},
                {value: "second", name: "Second model", description: "Complex tasks"}
            ]}]});
            check(Ai.activeSession.sessionModelName === "First model", "friendly current name");
            Ai.activeSession.agentTurnActive = true;
            Ai.activeSession.setSessionModel("second");
            check(!Ai.activeSession.switchingSessionModel && !sent.method, "busy turn must block model change");
            Ai.activeSession.agentTurnActive = false;
            Ai.activeSession.setSessionModel("second");
            check(sent.method === "session/set_config_option" && sent.params.value === "second", "config RPC selection");
            check(Ai.activeSession.switchingSessionModel && Ai.activeSession.currentSessionModelId === "first", "wait for acknowledgement");
            Ai.activeSession.handleResponse({id: sent.id, error: {message: "Unavailable"}});
            check(!Ai.activeSession.switchingSessionModel && Ai.activeSession.currentSessionModelId === "first" && Ai.activeSession.modelSwitchError.includes("Unavailable"), "failed switch retains current model");
            Ai.activeSession.setSessionModel("second");
            Ai.activeSession.handleResponse({id: sent.id, result: {}});
            check(!Ai.activeSession.switchingSessionModel && Ai.activeSession.currentSessionModelId === "second" && !Ai.activeSession.modelSwitchError, "successful switch");
            Ai.activeSession.sessionConfigOptions = [];
            Ai.activeSession.setSessionModel("first");
            check(sent.method === "session/set_model", "legacy model RPC");
            Ai.activeSession.handleResponse({id: sent.id, result: {}});
            check(Ai.activeSession.currentSessionModelId === "first", "legacy acknowledgement");
            Ai.activeSession.syntheticTransportWorks = false;
            Ai.activeSession.setSessionModel("second");
            check(!Ai.activeSession.switchingSessionModel && Ai.activeSession.modelSwitchError.length > 0, "disconnected transport cleanup");
            picker.expanded = true;
            let search = findNamed(picker, "assistantModelSearch");
            check(search !== null, "search field exists");
            search.text = "complex";
            check(picker.filteredModels.length === 1 && picker.filteredModels[0].modelId === "second", "search matches descriptions");
            search.text = "missing";
            check(picker.filteredModels.length === 0, "empty search result");
            search.text = "";
            check(picker.filteredModels.length === 2, "clear search restores models");
            console.log("PASS model picker selection and search");
            Qt.quit();
        }
    }
}
'''

@unittest.skipUnless(shutil.which("qs"), "Quickshell required")
class AiModelPickerTest(unittest.TestCase):
    def test_selection_and_search(self):
        with tempfile.TemporaryDirectory(prefix="ai-model-picker-") as temporary:
            base = Path(temporary)
            package = base / "package"
            shutil.copytree(ROOT / "tests/fixtures/ai_sidebar", package)
            fixture_shell = package / "shell.qml"
            fixture_shell.write_text(fixture_shell.read_text().replace("Ai.", "Ai.activeSession."))
            for relative in ("modules/services/Ai.qml", "modules/services/AiSession.qml", "modules/sidebar/AssistantModelPicker.qml",
                             "modules/theme/Motion.qml", "modules/components/StyledRect.qml", "modules/components/StyledToolTip.qml", "modules/components/StyledText.qml",
                             "modules/services/AiQuestions.js",
                             "modules/sidebar/AssistantActivity.qml",
                             "modules/sidebar/AssistantQuestions.qml"):
                target = package / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            service = package / "modules/services/AiSession.qml"
            source = service.read_text()
            start = source.index("    function sendEnvelope(envelope) {")
            end = source.index("    function sendRequest(", start)
            # Substitute only process I/O; keep actual request/config/reply handling.
            source = source[:start] + """    property var syntheticEnvelope: ({})
    property bool syntheticTransportWorks: true
    function sendEnvelope(envelope) {
        syntheticEnvelope = envelope;
        return syntheticTransportWorks;
    }

""" + source[end:]
            service.write_text(source)
            (package / "shell.qml").write_text(SCENARIO)
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                               XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(base / "cache"))
            result = subprocess.run(["qs", "-p", str(package), "--no-color"], env=environment,
                                    capture_output=True, text=True, timeout=8)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-4000:])
            self.assertNotIn("FAIL", output)
            self.assertNotIn("TypeError", output)
            self.assertIn("PASS model picker selection and search", output)

if __name__ == "__main__":
    unittest.main()
