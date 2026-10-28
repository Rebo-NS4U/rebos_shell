"""Exercise the persistent assistant at Unix-socket, process and real QML boundaries."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
BRIDGE = ROOT / "scripts/ai_bridge.py"

FAKE_AGENT = r'''
import json, os, sys, threading, time
from pathlib import Path
log = Path(sys.argv[1])
def emit(message):
    print(json.dumps(message), flush=True)
def update(kind, **values):
    emit({"method": "session/update", "params": {"sessionId": "persisted-session",
         "update": dict(sessionUpdate=kind, **values)}})
prompt_id = None
for line in sys.stdin:
    request = json.loads(line)
    with log.open("a") as handle:
        handle.write(json.dumps({"pid": os.getpid(), "method": request.get("method"), "id": request.get("id")}) + "\n")
    method = request.get("method")
    if method == "initialize":
        if request.get("params"):
            assert request["params"]["clientCapabilities"]["elicitation"]["form"] == {}
        emit({"id": request["id"], "result": {"protocolVersion": 1,
             "agentCapabilities": {}, "authMethods": [{"id": "chat-gpt"}]}})
    elif method == "authenticate":
        emit({"id": request["id"], "result": {}})
    elif method == "session/new":
        emit({"id": request["id"], "result": {"sessionId": "persisted-session",
             "models": {"currentModelId": "test-model", "availableModels": [{"modelId": "test-model", "name": "Test model"}]}}})
    elif method == "session/prompt":
        prompt_id = request["id"]
        if request["params"]["prompt"][0].get("text") == "ask questions":
            update("plan", entries=[{"content": "Inspect", "status": "completed"}, {"content": "Apply preference", "status": "in_progress"}])
            emit({"id": "question-1", "method": "elicitation/create", "params": {
                "mode": "form", "sessionId": "persisted-session", "message": "Which approach?",
                "requestedSchema": {"type": "object", "required": ["approach", "note"], "properties": {
                    "approach": {"type": "string", "title": "Approach", "oneOf": [{"const": "small", "title": "Small"}, {"const": "large", "title": "Large"}]},
                    "note": {"type": "string", "title": "Note"}}}}})
            continue
        update("agent_message_chunk", content={"type": "text", "text": "Started"})
        def continue_turn():
            time.sleep(0.6)
            update("agent_message_chunk", content={"type": "text", "text": " while detached"})
            emit({"id": "permission-1", "method": "session/request_permission", "params": {
                "sessionId": "persisted-session", "toolCall": {"toolCallId": "tool-1", "title": "Test action", "status": "pending"},
                "options": [{"optionId": "yes", "kind": "allow_once"}, {"optionId": "no", "kind": "reject_once"}]}})
        threading.Thread(target=continue_turn, daemon=True).start()
    elif request.get("id") == "permission-1":
        assert request["result"]["outcome"]["optionId"] == "yes"
        update("tool_call_update", toolCallId="tool-1", status="completed")
        update("agent_message_chunk", messageId="final", content={"type": "text", "text": "Finished"})
        emit({"id": prompt_id, "result": {"stopReason": "end_turn"}})
    elif request.get("id") == "question-1":
        assert request["result"] == {"action": "accept", "content": {"approach": "small", "note": "Keep the sidebar"}}
        update("plan", entries=[{"content": "Inspect", "status": "completed"}, {"content": "Apply preference", "status": "completed"}])
        update("agent_message_chunk", content={"type": "text", "text": "Finished"})
        emit({"id": prompt_id, "result": {"stopReason": "end_turn"}})
    elif method == "session/cancel":
        emit({"id": prompt_id, "result": {"stopReason": "cancelled"}})
'''


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="assistant-bridge-test-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.path = self.base / "runtime/acp.sock"
        self.fake = self.base / "fake_agent.py"
        self.fake.write_text(FAKE_AGENT)
        self.log = self.base / "agent-events.jsonl"
        self.server = subprocess.Popen([sys.executable, str(BRIDGE), "--server", "--socket", str(self.path)],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(self.stop_server)
        for _ in range(100):
            if self.path.exists():
                break
            if self.server.poll() is not None:
                self.fail(self.server.communicate())
            time.sleep(0.02)
        self.assertTrue(self.path.exists())

    def stop_server(self):
        if self.server.poll() is None:
            self.server.terminate()
        output, errors = self.server.communicate(timeout=12)
        self.assertNotIn("Traceback", errors, errors)

    def connect(self):
        connection = socket.socket(socket.AF_UNIX)
        connection.settimeout(4)
        connection.connect(str(self.path))
        stream = connection.makefile("rwb", buffering=0)
        self.addCleanup(connection.close)
        self.addCleanup(stream.close)
        self.send(stream, {"bridge": "attach", "cwd": str(self.base),
                           "command": [sys.executable, str(self.fake), str(self.log)]})
        return connection, stream, self.read(stream)

    def send(self, stream, value):
        stream.write((json.dumps(value) + "\n").encode())

    def read(self, stream):
        return json.loads(stream.readline())

    def test_checkpoint_replay_reset_and_explicit_stop(self):
        connection, stream, attached = self.connect()
        self.assertEqual(attached, {"bridge": "attached", "state": None, "seq": 0})
        self.send(stream, {"bridge": "send", "seq": 0, "state": {"marker": "pending-initialize"},
                           "message": {"id": 1, "method": "initialize"}})
        event = self.read(stream)
        self.assertEqual(event["message"]["id"], 1)
        stream.close()
        connection.close()
        _, stream, attached = self.connect()
        self.assertEqual(attached["state"], {"marker": "pending-initialize"})
        self.assertEqual(self.read(stream), event)
        self.send(stream, {"bridge": "checkpoint", "seq": event["seq"], "state": {"marker": "initialized"}})
        # Sending a reset on the same ordered stream also verifies the checkpoint
        # has reached the daemon before checking its new, empty state.
        first_pid = json.loads(self.log.read_text().splitlines()[0])["pid"]
        self.send(stream, {"bridge": "reset"})
        self.assertEqual(self.read(stream), {"bridge": "attached", "state": None, "seq": 0})
        with self.assertRaises(ProcessLookupError):
            os.kill(first_pid, 0)
        stopped = subprocess.run([sys.executable, str(BRIDGE), "--stop", "--socket", str(self.path)],
                                 capture_output=True, text=True, timeout=8)
        self.assertEqual(stopped.returncode, 0, stopped.stderr)
        self.assertEqual(stream.readline(), b"")

    @unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
    def test_real_qml_restart_during_turn_and_pending_permission(self):
        self.run_qml_restart("permission")

    @unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
    def test_real_qml_restart_with_question_draft_and_activity(self):
        self.run_qml_restart("question")

    def run_qml_restart(self, mode):
        package = self.base / "qml"
        (package / "modules/services").mkdir(parents=True)
        (package / "config").mkdir()
        (package / "scripts").mkdir()
        fixture = ROOT / "tests/fixtures/ai_sidebar"
        shutil.copytree(fixture / "modules/globals", package / "modules/globals")
        shutil.copyfile(fixture / "modules/services/Notifications.qml", package / "modules/services/Notifications.qml")
        shutil.copyfile(fixture / "modules/services/StateService.qml", package / "modules/services/StateService.qml")
        shutil.copyfile(ROOT / "modules/services/AiQuestions.js", package / "modules/services/AiQuestions.js")
        shutil.copyfile(BRIDGE, package / "scripts/ai_bridge.py")
        source_path = Path(os.environ.get("REBOS_TEST_AI_SOURCE", ROOT / "modules/services/AiSession.qml"))
        source = source_path.read_text()
        self.assertIn('agentProcess.command = ["python3", bridgeScript];', source)
        source = source.replace('agentProcess.command = ["python3", bridgeScript];',
                                'agentProcess.command = ["python3", bridgeScript, "--no-start", "--socket", ' + json.dumps(str(self.path)) + '];')
        source = source.replace('command: ["python3", root.bridgeScript, "--stop", "--channel", root.channelId]',
                                'command: ["python3", root.bridgeScript, "--stop", "--socket", ' + json.dumps(str(self.path)) + ']')
        (package / "modules/services/AiSession.qml").write_text(source)
        shutil.copyfile(ROOT / "modules/services/Ai.qml", package / "modules/services/Ai.qml")
        if mode == "question":
            for relative in ("modules/sidebar/AssistantQuestions.qml", "modules/sidebar/AssistantActivity.qml",
                             "modules/theme/Motion.qml", "modules/components/StyledRect.qml", "modules/theme/Colors.qml", "modules/theme/Styling.qml"):
                target = package / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                origin = ROOT if relative.startswith(("modules/sidebar", "modules/components")) or relative == "modules/theme/Motion.qml" else fixture
                shutil.copyfile(origin / relative, target)
        command = json.dumps([sys.executable, str(self.fake), str(self.log)])
        (package / "config/Config.qml").write_text('''
pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool aiReady: true
    property int animDuration: 0
    property var theme: ({font: "sans-serif"})
    function resolveColor(value) { return value || "transparent"; }
    property QtObject ai: QtObject {
        property bool enabled: true
        property string defaultAgent: "codex"
        property string workingDirectory: %s
        property var agents: [{id: "codex", name: "Test", command: %s}]
    }
}
''' % (json.dumps(str(self.base)), command))
        shell = '''import QtQuick
import Quickshell
import qs.modules.services
import qs.config
ShellRoot {
    id: test
    property bool sent: false
    property bool approved: false
    function check(condition, message) {
        if (!condition) { console.error("FAIL", message); Qt.exit(1); }
    }
    Component.onCompleted: Ai.activeSession.chatDir = %s
    Timer { interval: 6000; running: true; onTriggered: { console.error("FAIL timeout", Ai.activeSession.statusText, Ai.sessionEnabled, Ai.sessions.length, Ai.activeSession.bootstrapped, Ai.activeSession.bridgeAttached, Ai.activeSession.sessionReady, JSON.stringify(Ai.activeSession.pendingRpc)); Qt.exit(1); } }
    Timer { interval: 25; running: true; repeat: true; onTriggered: { SCENARIO } }
}
''' % json.dumps(str(self.base / "chats"))
        first = '''
            if (Ai.activeSession.sessionReady && !test.sent) { test.sent = true; Ai.activeSession.sendMessage("keep working", []); }
            if (Ai.activeSession.currentChat.some(m => m.role === "assistant" && m.content === "Started")) {
                console.log("PASS first menu detached during turn"); Qt.quit();
            }
'''
        second = '''
            if (!Ai.activeSession.bridgeAttached || !Ai.activeSession.sessionReady) return;
            test.check(Ai.activeSession.currentSessionId === "persisted-session", "same session");
            test.check(Ai.activeSession.currentSessionModelId === "test-model", "same model");
            if (!test.approved && Ai.activeSession.pendingPermissions["permission-1"]) {
                test.check(Ai.activeSession.isBusy, "turn remains busy while awaiting approval");
                test.check(Ai.activeSession.currentChat.filter(m => m.role === "user").length === 1, "one user prompt");
                let text = Ai.activeSession.currentChat.filter(m => m.role === "assistant").map(m => m.content).join("");
                test.check(text === "Started while detached", "replay without lost or duplicate chunks: " + JSON.stringify(Ai.activeSession.currentChat));
                let index = Ai.activeSession.currentChat.findIndex(m => m.permissionRequestId === "permission-1");
                test.check(index >= 0 && Ai.activeSession.currentChat[index].functionPending, "approval restored");
                test.approved = true;
                Ai.activeSession.approveCommand(index);
            }
            if (test.approved && !Ai.activeSession.isBusy && Ai.activeSession.currentChat.some(m => m.content.endsWith("Finished"))) {
                test.check(Object.keys(Ai.activeSession.pendingPermissions).length === 0, "permission cleared");
                console.log("PASS reattached same turn and completed after permission");
                Config.ai.enabled = false;
                finish.start();
            }
'''
        second_shell = shell.replace("SCENARIO", second).replace('    Timer { interval: 6000;',
            '    Timer { id: finish; interval: 400; onTriggered: Qt.quit() }\n    Timer { interval: 6000;')
        first_shell = shell.replace("SCENARIO", first)
        if mode == "question":
            shell = shell.replace("import qs.config", "import qs.config\nimport qs.modules.sidebar")
            shell = shell.replace("    property bool sent: false", '''
    Window {
        visible: true; width: 340; height: 700
        Column { width: 320
            AssistantActivity { id: activity; width: parent.width }
            AssistantQuestions { id: questions; width: parent.width }
        }
    }
    function findNamed(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) {
            let result = findNamed(child, name);
            if (result) return result;
        }
        return null;
    }
    property bool sent: false''')
            first_question = '''
            if (Ai.activeSession.sessionReady && !test.sent) { test.sent = true; Ai.activeSession.sendMessage("ask questions", []); }
            if (Ai.activeSession.questionRequests.length > 0 && !test.approved) {
                let choice = findNamed(questions, "questionChoice_approach_small");
                let note = findNamed(questions, "questionInput_note");
                if (!choice || !note) return;
                test.approved = true;
                choice.clicked();
                note.text = "Keep the sidebar"; note.textEdited();
                Ai.activeSession.checkpointBridge();
                detach.start();
            }
'''
            first_shell = shell.replace("SCENARIO", first_question).replace('    Timer { interval: 6000;',
                '    Timer { id: detach; interval: 150; onTriggered: { console.log("PASS first menu detached with draft"); Qt.quit(); } }\n    Timer { interval: 6000;')
            second_question = '''
            if (!Ai.activeSession.bridgeAttached || !Ai.activeSession.sessionReady) return;
            if (Ai.activeSession.questionRequests.length > 0 && !test.approved) {
                let note = findNamed(questions, "questionInput_note");
                let submit = findNamed(questions, "questionSubmit");
                if (!note || !submit) return;
                test.check(note.text === "Keep the sidebar" && Ai.activeSession.questionDrafts["question-1"].approach === "small", "draft restored in real menu");
                test.check(Ai.activeSession.taskPlan.length === 2 && activity.completed === 1, "activity restored with draft");
                test.check(Ai.activeSession.currentSessionId === "persisted-session", "same question session");
                test.approved = true;
                submit.clicked();
            }
            if (test.approved && !Ai.activeSession.isBusy && Ai.activeSession.currentChat.some(m => m.content.endsWith("Finished"))) {
                test.check(Ai.activeSession.questionRequests.length === 0 && activity.completed === 2, "answer completes task and segments");
                console.log("PASS reattached question, draft, and activity");
                Config.ai.enabled = false;
                finish.start();
            }
'''
            second_shell = shell.replace("SCENARIO", second_question).replace('    Timer { interval: 6000;',
                '    Timer { id: finish; interval: 400; onTriggered: Qt.quit() }\n    Timer { interval: 6000;')
        runtime = self.base / "qml-runtime"
        runtime.mkdir(mode=0o700)
        environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                           XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(self.base / "cache"))
        for code, expected in [(first_shell, "PASS first menu"),
                               (second_shell, "PASS reattached")]:
            (package / "shell.qml").write_text(code)
            result = subprocess.run(["qs", "-p", str(package), "--no-color"], env=environment,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-5000:])
            self.assertNotIn("FAIL", output, output)
            self.assertNotIn("TypeError", output, output)
            self.assertIn(expected, output, output)
            if expected.startswith("PASS first"):
                time.sleep(0.8)  # Agent must continue while no QML process exists.
        records = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(len({record["pid"] for record in records}), 1, records)
        self.assertEqual([r["method"] for r in records].count("initialize"), 1, records)
        self.assertEqual([r["method"] for r in records].count("session/prompt"), 1, records)
        self.assertNotIn("session/cancel", [r["method"] for r in records], records)
        with self.assertRaises(ProcessLookupError):
            os.kill(records[0]["pid"], 0)  # Explicit disable still stops the backend.


if __name__ == "__main__":
    unittest.main()
