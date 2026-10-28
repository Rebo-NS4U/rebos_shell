"""Run two real QML sessions against independent synthetic ACP daemons."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

from test_ai_bridge import FAKE_AGENT

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell required")
class SessionsTest(unittest.TestCase):
    def test_parallel_sessions_switch_stop_and_reattach(self):
        with tempfile.TemporaryDirectory(prefix="assistant-sessions-") as temporary:
            base = Path(temporary)
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                       XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(base / "cache"))
            fake = base / "agent.py"
            fake.write_text(FAKE_AGENT.replace(
                '        assert request["result"]["outcome"]["optionId"] == "yes"',
                '        if request["result"]["outcome"]["outcome"] == "cancelled": continue\n        assert request["result"]["outcome"]["optionId"] == "yes"'))
            log = base / "agent.jsonl"
            package = base / "qml"
            shutil.copytree(ROOT / "tests/fixtures/ai_sidebar", package)
            for relative in ("modules/services/Ai.qml", "modules/services/AiSession.qml",
                             "modules/services/AiQuestions.js", "scripts/ai_bridge.py",
                             "modules/sidebar/AssistantSidebar.qml", "modules/sidebar/AssistantActivity.qml",
                             "modules/sidebar/AssistantQuestions.qml", "modules/sidebar/AssistantModelPicker.qml",
                             "modules/sidebar/CodeBlock.qml", "modules/theme/Motion.qml", "modules/components/StyledRect.qml", "modules/components/StyledToolTip.qml", "modules/components/StyledText.qml"):
                target = package / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            service = package / "modules/services/AiSession.qml"
            service.write_text(service.read_text().replace(
                'agentProcess.command = ["python3", bridgeScript];',
                'agentProcess.command = ["python3", bridgeScript, "--no-start"];'))
            config = package / "config/Config.qml"
            source = config.read_text().replace('aiReady: false', 'aiReady: true').replace('enabled: false', 'enabled: true')
            source = source.replace('property int sidebarWidth: 450', '''property int sidebarWidth: 450
        property string defaultAgent: "codex"
        property string workingDirectory: %s
        property var agents: [{id: "codex", name: "Test", command: %s}]''' % (
                    json.dumps(str(base)), json.dumps([sys.executable, str(fake), str(log)])))
            config.write_text(source)
            # Persist a fixed list through the fixture so a fresh QML process
            # discovers both existing background channels without spawning work.
            state = package / "modules/services/StateService.qml"
            state.write_text(state.read_text().replace('return v;', '''if (k === "assistantSessionChannels") return ["default", "second"];
        return v;'''))
            servers = []
            try:
                for channel in ("default", "second"):
                    server = subprocess.Popen([sys.executable, str(ROOT / "scripts/ai_bridge.py"),
                                               "--server", "--channel", channel], env=env,
                                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    servers.append(server)
                for _ in range(100):
                    if (runtime / "rebos-assistant/acp.sock").exists() and (runtime / "rebos-assistant/acp-second.sock").exists():
                        break
                    time.sleep(.02)
                shell = r'''
import QtQuick
import Quickshell
import qs.modules.services
import qs.modules.sidebar
import qs.config
import qs.modules.globals
ShellRoot {
    id: test
    property int stage: 0
    property AiSession first: Ai
    property AiSession second: null
    function check(value, message) {
        if (!value) { console.error("FAIL", message); Qt.exit(1); }
    }
    Window { visible: true; width: 500; height: 800
        AssistantSidebar { anchors.fill: parent; targetScreen: Quickshell.screens[0] }
    }
    Timer { interval: 8000; running: true; onTriggered: { console.error("FAIL timeout", test.first.sessionEnabled, test.first.bootstrapped, test.first.bridgeAttached, test.first.sessionReady, JSON.stringify(test.first.pendingRpc), test.stage, test.first.statusText, test.second?.statusText, JSON.stringify(test.first.pendingPermissions), test.second?.questionRequests.length, JSON.stringify(test.first.currentChat)); Qt.exit(1); } }
    Timer { interval: 30; running: true; repeat: true; onTriggered: {
        if (Ai.sessions.length !== 2) return;
        test.second = Ai.sessions[1];
        test.first.chatDir = CHATDIR;
        test.second.chatDir = CHATDIR;
        SCENARIO
    } }
}
'''.replace('CHATDIR', json.dumps(str(base / "chats")))
                first = r'''
        if (test.stage === 0 && test.first.sessionReady && test.second.sessionReady) {
            test.stage = 1;
            test.first.inputDraft = "first draft";
            test.first.sendMessage("keep working", []);
            Ai.selectSession(test.second);
            test.second.inputDraft = "second draft";
            test.second.sendMessage("ask questions", []);
        }
        if (test.stage === 1 && test.first.pendingPermissions["permission-1"] && test.second.questionRequests.length) {
            check(test.first.isBusy && test.second.isBusy, "both turns active");
            check(test.first.currentChatId !== test.second.currentChatId, "independent history files");
            Ai.selectSession(test.first);
            check(Ai.activeSession.inputDraft === "first draft", "first draft preserved");
            check(Notifications.list.length === 1, "background session question notifies");
            GlobalStates.hideAssistant();
            Notifications.list[0].actionHandlers.answer();
            check(Ai.activeSession === test.second && GlobalStates.assistantVisible, "Answer opens correct background chat");
            Ai.selectSession(test.second);
            check(Ai.activeSession.inputDraft === "second draft", "second draft preserved");
            test.second.setQuestionAnswer("question-1", "approach", "small");
            test.second.setQuestionAnswer("question-1", "note", "Keep the sidebar");
            test.first.checkpointBridge(); test.second.checkpointBridge();
            test.stage = 2;
            detach.start();
        }
'''
                second = r'''
        if (test.stage === 0 && test.first.bridgeAttached && test.second.bridgeAttached
            && test.first.pendingPermissions["permission-1"] && test.second.questionRequests.length) {
            test.stage = 1;
            check(test.first.inputDraft === "first draft" && test.second.inputDraft === "second draft", "drafts survive reload");
            check(test.second.questionDrafts["question-1"].note === "Keep the sidebar", "question stays in its chat");
            Ai.selectSession(test.first);
            test.first.cancelGeneration(true);
            check(test.second.isBusy && test.second.questionRequests.length === 1, "stopping first leaves second running");
            Ai.selectSession(test.second);
            test.second.answerQuestion("question-1", "accept");
        }
        if (test.stage === 1 && !test.second.isBusy && test.second.currentChat.some(m => m.content.endsWith("Finished"))) {
            test.stage = 2;
            Ai.closeSession(test.second);
            check(Ai.sessions.length === 1 && Ai.activeSession === Ai, "close selects remaining chat");
            Config.ai.enabled = false;
            finish.start();
        }
'''
                for scenario, marker in ((first, "PASS two concurrent"), (second, "PASS isolated stop")):
                    code = shell.replace('SCENARIO', scenario)
                    if scenario == first:
                        code = code.replace('    Timer { interval: 8000;',
                            '    Timer { id: detach; interval: 200; onTriggered: { console.log("PASS two concurrent chats detached"); Qt.quit(); } }\n    Timer { interval: 8000;')
                    if scenario == second:
                        code = code.replace('    Timer { interval: 8000;',
                            '    Timer { id: finish; interval: 700; onTriggered: { console.log("PASS isolated stop and close"); Qt.quit(); } }\n    Timer { interval: 8000;')
                    (package / "shell.qml").write_text(code)
                    result = subprocess.run(['qs', '-p', str(package), '--no-color'], env=env,
                                            capture_output=True, text=True, timeout=12)
                    output = result.stdout + result.stderr
                    self.assertEqual(result.returncode, 0, output[-6000:])
                    self.assertIn(marker, output, output)
                    for error in ('FAIL', 'TypeError', 'ReferenceError', 'Binding loop'):
                        self.assertNotIn(error, output, output)
                records = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual(len({record['pid'] for record in records}), 2)
                self.assertEqual(sum(record['method'] == 'session/prompt' for record in records), 2)
                self.assertEqual(sum(record['method'] == 'initialize' for record in records), 2)
                self.assertEqual(sum(record['method'] == 'session/cancel' for record in records), 1)
            finally:
                for server in servers:
                    server.terminate()
                    _, errors = server.communicate(timeout=12)
                    self.assertNotIn('Traceback', errors)


if __name__ == '__main__':
    unittest.main()
