"""Exercise question cards, schema validation and activity in real offscreen QML."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

SCENARIO = r'''
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.modules.services
import qs.modules.sidebar
import qs.modules.globals
ShellRoot {
    function check(condition, message) {
        if (!condition) { console.error("FAIL", message); Qt.exit(1); }
    }
    function findNamed(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) {
            let result = findNamed(child, name);
            if (result) return result;
        }
        return null;
    }
    Window {
        id: window
        visible: true
        width: 340; height: 720
        Column {
            width: 320
            AssistantActivity { id: activity; width: parent.width }
            AssistantQuestions { id: questions; width: parent.width }
        }
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            Ai.activeSession.bridgeAttached = true;
            Ai.activeSession.startInitialization();
            check(Ai.activeSession.syntheticEnvelope.params.clientCapabilities.elicitation.form !== undefined, "form capability advertised");
            check(Ai.activeSession.syntheticEnvelope.params.clientCapabilities.plan !== undefined, "plan capability advertised");
            Ai.activeSession.currentChatId = "";
            Ai.activeSession.currentSessionId = "test-session";
            Ai.activeSession.currentChat = [{role: "user", content: "Do the work"}];
            check(Ai.activeSession.activityTask === "Do the work", "overall task falls back to user request");
            Ai.activeSession.currentChat = Ai.activeSession.currentChat.concat([{role: "assistant", content: "I’ll make the activity panel easier to follow. Here are the steps."}]);
            check(Ai.activeSession.activityTask === "I’ll make the activity panel easier to follow.", "overall task uses descriptive public summary");
            check(Ai.activeSession.activityProgress === "", "opening summary is not repeated as progress");
            Ai.activeSession.currentChat = Ai.activeSession.currentChat.concat([{role: "assistant", content: "The panel hides useful explanations. I’ll move progress into the visible panel."}]);
            check(findNamed(activity, "assistantActivityProgress").text.includes("hides useful explanations"), "public progress is visible without expansion");
            Ai.activeSession.handleSessionUpdate({update: {sessionUpdate: "agent_thought_chunk", content: {type: "text", text: "Private reasoning must stay out of activity"}}});
            check(!Ai.activeSession.activityProgress.includes("Private reasoning"), "progress excludes thought text");
            check(Ai.activeSession.activitySentence({content: "Find the activity panel and its data source", kind: "search"}) === "Find the activity panel and its data source.", "specific human-readable action is preserved");
            check(Ai.activeSession.activitySentence({content: "Check AssistantActivity.qml for layout and syntax errors", kind: "execute"}).includes("the activity panel"), "visible titles use the feature name");
            let searchSummary = Ai.activeSession.activitySentence({content: "functions.exec", kind: "execute", rawInput: {cmd: "rg activity modules/services/AiSession.qml"}, purpose: "Find where tool rows get their labels."});
            check(searchSummary.includes("Search the assistant session") && !searchSummary.includes(".qml") && searchSummary.includes("tool rows get their labels"), "raw command becomes specific target and purpose");
            let testSummary = Ai.activeSession.activitySentence({content: "functions.exec", rawInput: {cmd: "python -m unittest tests/integration/test_ai_questions.py"}, purpose: "Verify detailed activity rows and inline changes."});
            check(testSummary.includes("assistant question checks") && !testSummary.includes(".py") && testSummary.includes("automatic checks") && testSummary.includes("inline changes"), "test summary names the check and its purpose");
            Ai.activeSession.recordActivity({toolCallId: "summary-snapshot", title: "functions.exec", kind: "execute", rawInput: {cmd: "cat modules/services/AiSession.qml"}, status: "in_progress"});
            let snapshot = Ai.activeSession.activityLog.find(entry => entry.id === "summary-snapshot");
            Ai.activeSession.recordActivity({toolCallId: "summary-snapshot", status: "completed"});
            let finished = Ai.activeSession.activityLog.find(entry => entry.id === "summary-snapshot");
            check(finished.purpose === snapshot.purpose && finished.rawInput.cmd.includes("AiSession.qml"), "completion retains the original action context");
            Ai.activeSession.activityLog = [];
            Ai.activeSession.agentTurnActive = true;
            Ai.activeSession.handleSessionUpdate({sessionId: "test-session", update: {sessionUpdate: "plan", entries: [
                {content: "Inspect the setup", status: "completed"},
                {content: "Make the change", status: "in_progress"},
                {content: "Check it works", status: "pending"}
            ]}});
            Ai.activeSession.upsertToolCall({toolCallId: "read", title: "Read configuration", status: "completed"});
            check(Ai.activeSession.taskPlan.length === 3 && Ai.activeSession.activityLog.length === 1 && activity.completed === 1, "segmented plan and tool progress");
            check(activity.visible && activity.height < 230, "compact visible activity panel");
            findNamed(activity, "assistantActivityToggle").clicked();
            check(!activity.expanded, "activity collapses");
            findNamed(activity, "assistantActivityToggle").clicked();
            findNamed(activity, "assistantActivityRow_1").clicked();
            check(activity.selectedEntry.content === "Make the change", "plan row opens details");
            check(findNamed(activity, "assistantActivityExplanation").text.includes("No changes or command output"), "plan details show only reported technical information");
            Ai.activeSession.upsertToolCall({toolCallId: "edit", title: "Improve activity task headings", kind: "edit", status: "completed", rawInput: {patch: "-old heading\n+descriptive heading"}});
            check(findNamed(activity, "assistantActivityExplanation").text.includes("descriptive heading"), "plan expands to actual changes associated with its active step");
            check(findNamed(activity, "assistantActivityExplanation").parent.parent.parent.parent.parent.objectName !== "assistantActivity", "details live inside the selected row");
            findNamed(activity, "assistantActivityCloseDetails").clicked();
            check(activity.selectedEntry === null, "details close");
            Ai.activeSession.activityLog = Ai.activeSession.activityLog.filter(entry => entry.id !== "edit");
            Ai.activeSession.handleAcpLine(JSON.stringify({id: "ask", method: "elicitation/create", params: {
                mode: "form", sessionId: "test-session", message: "Choose an approach",
                requestedSchema: {type: "object", required: ["approach", "name", "count", "confirm", "tags"], properties: {
                    approach: {type: "string", title: "Approach", oneOf: [{const: "small", title: "Small change", description: "Keep it focused"}, {const: "large", title: "Large change"}]},
                    name: {type: "string", title: "Name", minLength: 2},
                    count: {type: "integer", title: "Count", minimum: 0, maximum: 3},
                    confirm: {type: "boolean", title: "Confirm"},
                    tags: {type: "array", title: "Tags", minItems: 1, items: {type: "string", enum: ["one", "two"]}},
                    private: {type: "string", title: "Private", _meta: {codex: {isSecret: true}}}
                }}
            }}));
            check(Ai.activeSession.questionRequests.length === 1 && Ai.activeSession.statusText === "Waiting for your answer…", "question pauses for input");
            check(Notifications.list.length === 1 && Notifications.list[0].summary === "Assistant needs your answer", "question sends desktop notification while menu is open");
            let sent = Notifications.sentCount;
            Ai.syncQuestionNotifications();
            check(Notifications.sentCount === sent, "unchanged pending question does not notify twice");
            GlobalStates.hideAssistant();
            Notifications.list[0].actionHandlers.answer();
            check(GlobalStates.assistantVisible, "Answer opens closed assistant");
            next.start();
        }
    }
    Timer {
        id: next; interval: 50
        onTriggered: {
            check(findNamed(questions, "questionSubmit") !== null, "answer card rendered");
            check(Ai.activeSession.questionFields(Ai.activeSession.questionRequests[0]).length === 6, "schema fields normalized");
            let previous = JSON.stringify(Ai.activeSession.syntheticEnvelope);
            findNamed(questions, "questionSubmit").clicked();
            check(JSON.stringify(Ai.activeSession.syntheticEnvelope) === previous && !!Ai.activeSession.questionErrors.ask, "required answer validation: " + JSON.stringify(Ai.activeSession.syntheticEnvelope) + " " + JSON.stringify(Ai.activeSession.questionErrors));
            findNamed(questions, "questionChoice_approach_small").clicked();
            check(Ai.activeSession.questionDrafts.ask.approach === "small" && Ai.activeSession.questionRequests.length === 1, "selection waits for explicit submission");
            let name = findNamed(questions, "questionInput_name");
            name.text = "Rebo"; name.textEdited();
            let count = findNamed(questions, "questionInput_count");
            count.text = "4"; count.textEdited();
            findNamed(questions, "questionChoice_confirm_false").clicked();
            findNamed(questions, "questionChoice_tags_two").clicked();
            findNamed(questions, "questionSubmit").clicked();
            check(Ai.activeSession.questionRequests.length === 1 && Ai.activeSession.questionErrors.ask.includes("range"), "numeric bounds checked");
            count.text = "0"; count.textEdited();
            let secret = findNamed(questions, "questionInput_private");
            check(secret.echoMode === TextInput.Password, "private input masked");
            secret.text = "synthetic-private-value"; secret.textEdited();
            let snapshot = JSON.parse(JSON.stringify(Ai.activeSession.bridgeState()));
            check(snapshot.questionDrafts.ask.name === "Rebo" && snapshot.questionRequests.length === 1 && snapshot.taskPlan.length === 3, "questions, drafts and segments checkpointed");
            Ai.activeSession.questionRequests = [];
            Ai.activeSession.questionDrafts = {};
            Ai.activeSession.taskPlan = [];
            Ai.activeSession.handleBridgeLine(JSON.stringify({bridge: "attached", seq: 8, state: snapshot}));
            check(Ai.activeSession.questionDrafts.ask.name === "Rebo" && Ai.activeSession.taskPlan.length === 3, "checkpoint restores question and activity");
            finish.start();
        }
    }
    Timer {
        id: finish; interval: 50
        onTriggered: {
            findNamed(questions, "questionSubmit").clicked();
            let response = Ai.activeSession.syntheticEnvelope;
            check(response.id === "ask" && response.result.action === "accept", "ACP question response");
            check(response.result.content.approach === "small" && response.result.content.name === "Rebo", "choices and typed text sent");
            check(response.result.content.count === 0 && response.result.content.confirm === false && response.result.content.tags[0] === "two", "typed scalar and multi-select values");
            check(Ai.activeSession.questionRequests.length === 0 && Object.keys(Ai.activeSession.questionDrafts).length === 0, "submitted question and draft cleared");
            check(Notifications.list.length === 0, "answer removes notification");
            check(!JSON.stringify(Ai.activeSession.currentChat).includes("synthetic-private-value") && JSON.stringify(Ai.activeSession.currentChat).includes("[private answer]"), "private answers excluded from chat history");
            let question = {mode: "form", requestedSchema: {properties: {name: {type: "string"}}}};
            Ai.activeSession.handleQuestionRequest("decline", question);
            Ai.activeSession.answerQuestion("decline", "decline");
            check(Ai.activeSession.syntheticEnvelope.result.action === "decline", "decline supported");
            Ai.activeSession.handleQuestionRequest("cancel", question);
            Ai.activeSession.answerQuestion("cancel", "cancel");
            check(Ai.activeSession.syntheticEnvelope.result.action === "cancel", "cancel supported");
            Ai.activeSession.handleQuestionRequest("expired", question);
            Ai.activeSession.handleAgentRequest({method: "$/cancel_request", params: {requestId: "expired"}});
            check(Ai.activeSession.questionRequests.length === 0, "expired questions dismissed");
            Ai.activeSession.handleQuestionRequest("email", {mode: "form", requestedSchema: {properties: {email: {type: "string", format: "email"}}}});
            Ai.activeSession.setQuestionAnswer("email", "email", "invalid");
            check(!Ai.activeSession.answerQuestion("email", "accept"), "invalid format rejected");
            Ai.activeSession.setQuestionAnswer("email", "email", "test@example.com");
            check(Ai.activeSession.answerQuestion("email", "accept"), "valid format accepted");
            Ai.activeSession.handleQuestionRequest("stop", question);
            Ai.activeSession.cancelGeneration(true);
            check(Ai.activeSession.questionRequests.length === 0 && Ai.activeSession.taskPlan[1].status === "stopped", "Stop cancels questions and active steps");
            Ai.activeSession.taskPlan = [];
            check(Ai.activeSession.activitySegments.length === 1, "tool activity fallback");
            Ai.activeSession.upsertToolCall({toolCallId: "read", kind: "read", title: "Read configuration", status: "in_progress", rawInput: {command: "cat settings.qml"}, content: [{type: "content", content: {type: "text", text: "Current settings"}}]});
            inspectActivity.start();
        }
    }
    Timer {
        id: inspectActivity; interval: 50
        onTriggered: {
            findNamed(activity, "assistantActivityRow_0").clicked();
            check(activity.selectedEntry.id === "read", "tool row opens details");
            let detail = findNamed(activity, "assistantActivityExplanation");
            check(!detail.text.includes("Inspect existing files") && detail.text.includes("cat settings.qml") && detail.text.includes("Current settings"), "expanded details contain command and output without generic explanation");
            Ai.activeSession.upsertToolCall({toolCallId: "read", status: "completed", content: [{type: "content", content: {type: "text", text: "Read complete"}}]});
            check(activity.selectedEntry.id === "read" && findNamed(activity, "assistantActivityExplanation").text.includes("Read complete"), "selection survives live updates and details refresh");
            findNamed(activity, "assistantActivityRow_0").clicked();
            check(activity.selectedEntry === null, "click again closes details");
            // Restore with a queued local batch, then replay an acknowledged
            // frame. Neither copy may be appended to the checkpoint again.
            Ai.activeSession.currentChat = [{role: "assistant", content: "Hello"}];
            Ai.activeSession.activeAssistantIndex = 0;
            let restored = Ai.activeSession.bridgeState();
            Ai.activeSession.queueAssistantText({messageId: "", content: {type: "text", text: " stale"}});
            Ai.activeSession.handleBridgeLine(JSON.stringify({bridge: "attached", seq: 40, state: restored}));
            Ai.activeSession.flushAssistantText();
            let event = {bridge: "acp", seq: 41, message: {method: "session/update", params: {
                update: {sessionUpdate: "agent_message_chunk", content: {type: "text", text: " again"}}
            }}};
            Ai.activeSession.handleBridgeLine(JSON.stringify(event));
            Ai.activeSession.handleBridgeLine(JSON.stringify(event));
            Ai.activeSession.flushAssistantText();
            check(Ai.activeSession.currentChat[0].content === "Hello again", "checkpoint and replay do not duplicate text");
            Ai.activeSession.queueAssistantText({content: {type: "text", text: " again"}});
            Ai.activeSession.flushAssistantText();
            check(Ai.activeSession.currentChat[0].content === "Hello again again", "intentional repeated words are preserved");
            Ai.activeSession.handleSessionUpdate({update: {sessionUpdate: "agent_thought_chunk", messageId: "thought-a", content: {type: "text", text: "Checking "}}});
            Ai.activeSession.handleSessionUpdate({update: {sessionUpdate: "agent_thought_chunk", messageId: "thought-a", content: {type: "text", text: "the settings."}}});
            check(Ai.activeSession.statusText === "Checking the settings.", "thinking chunks form readable sentences");
            Ai.activeSession.handleSessionUpdate({update: {sessionUpdate: "agent_thought_chunk", messageId: "thought-b", content: {type: "text", text: "Next step."}}});
            check(Ai.activeSession.statusText === "Next step.", "new thought starts a fresh paragraph");
            check(Ai.activeSession.activitySentence({content: "functions.exec rg config", kind: "execute"}).startsWith("Search the project files for matching code and settings."), "plain English activity");
            Ai.activeSession.taskPlan = Array.from({length: 14}, (_, i) => ({content: "Complete task number " + (i + 1), status: i === 11 ? "in_progress" : i < 11 ? "completed" : "pending"}));
            verifyScroll.start();
        }
    }
    Timer {
        id: verifyScroll; interval: 100
        onTriggered: {
            let scroll = findNamed(activity, "assistantActivityScroll");
            check(activity.activeStep === 11 && scroll.contentY > 0, "activity scroll follows the active task");
            Ai.activeSession.taskPlan = Ai.activeSession.taskPlan.map((step, i) => ({content: step.content, status: i === 1 ? "in_progress" : "pending"}));
            verifyReturn.start();
        }
    }
    Timer {
        id: verifyReturn; interval: 100
        onTriggered: {
            check(activity.activeStep === 1 && findNamed(activity, "assistantActivityScroll").contentY < 100, "activity follows a step moving back up");
            Ai.activeSession.authenticated = true;
            Ai.activeSession.pendingSessionAction = {kind: "new", cwd: "/tmp"};
            Ai.activeSession.performSessionAction();
            let servers = Ai.activeSession.syntheticEnvelope.params.mcpServers;
            check(servers.some(server => server.name === "assistant_questions" && server.args[0].endsWith("ai_questions.py")), "question tool supplied to sessions");
            check(Ai.activeSession.questionToolNegotiated && Ai.activeSession.bridgeState().questionToolNegotiated, "question tool upgrade checkpointed");
            Ai.activeSession.sessionReady = true;
            Ai.activeSession.queuedPrompt = {text: "Adjust my theme", attachments: []};
            Ai.activeSession.dispatchQueuedPrompt();
            let prompt = Ai.activeSession.syntheticEnvelope.params.prompt;
            check(prompt[0].text === "Adjust my theme" && prompt.some(block => (block.text || "").includes("ask_user_question")), "user prompt preserved with proactive question guidance");
            console.log("PASS question UI, typed answers, validation, activity, and restore");
            Qt.quit();
        }
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error("FAIL timeout"); Qt.exit(1); } }
}
'''


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class QuestionsTest(unittest.TestCase):
    def test_questions_and_activity(self):
        with tempfile.TemporaryDirectory(prefix="assistant-questions-test-") as temporary:
            base = Path(temporary)
            package = base / "qml"
            shutil.copytree(ROOT / "tests/fixtures/ai_sidebar", package)
            fixture_shell = package / "shell.qml"
            fixture_shell.write_text(fixture_shell.read_text().replace("Ai.", "Ai.activeSession."))
            for relative in ("modules/services/Ai.qml", "modules/services/AiSession.qml", "modules/services/AiQuestions.js",
                             "modules/sidebar/AssistantQuestions.qml", "modules/sidebar/AssistantActivity.qml",
                             "modules/theme/Motion.qml", "modules/components/StyledRect.qml"):
                target = package / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            service = package / "modules/services/AiSession.qml"
            source = service.read_text()
            start = source.index("    function sendEnvelope(envelope) {")
            end = source.index("    function sendRequest(", start)
            source = source[:start] + '''    property var syntheticEnvelope: ({})
    function sendEnvelope(envelope) {
        syntheticEnvelope = envelope;
        return true;
    }

''' + source[end:]
            service.write_text(source)
            (package / "shell.qml").write_text(SCENARIO)
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                               XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(base / "cache"))
            result = subprocess.run(["qs", "-p", str(package), "--no-color"], env=environment,
                                    capture_output=True, text=True, timeout=8)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-6000:])
            self.assertNotIn("FAIL", output, output)
            self.assertNotIn("TypeError", output, output)
            self.assertNotIn("ReferenceError", output, output)
            self.assertIn("PASS question UI", output, output)


if __name__ == "__main__":
    unittest.main()
