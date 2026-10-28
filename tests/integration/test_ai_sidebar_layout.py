"""Exercise real chat layout and streaming without connecting to an AI agent."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required for the layout regression")
class AiSidebarLayoutTest(unittest.TestCase):
    def test_scrolled_chat_keeps_event_loop_responsive(self):
        self.run_scenario("history", 14)

    def test_long_reply_with_busy_footer_keeps_event_loop_responsive(self):
        self.run_scenario("long_reply", 7)

    def test_collapsed_tool_output_is_not_laid_out(self):
        self.run_scenario("tool_output", 2)

    def run_scenario(self, scenario, message_count):
        # Real clipping containers are essential: replacing StyledRect with a
        # plain Rectangle hides the bubble-width/implicitWidth layout cycle.
        with tempfile.TemporaryDirectory(prefix="ai-sidebar-layout-") as temporary:
            package = Path(temporary) / "package"
            shutil.copytree(ROOT / "tests/fixtures/ai_sidebar", package)
            fixture_shell = package / "shell.qml"
            fixture_shell.write_text(fixture_shell.read_text().replace("Ai.", "Ai.activeSession."))
            if scenario == "tool_output":
                source = fixture_shell.read_text()
                source = source.replace('console.log("LOADED messages",', '''Ai.activeSession.currentChat = [
                    {role: "user", content: "Check output"},
                    {role: "function", content: "large command output\\n".repeat(10000)}
                ];
                console.log("LOADED messages",''', 1)
                source = source.replace('if (test.beats < 10) {', '''if (test.scenario === "tool_output") {
                    let raw = findNamed(sidebar, "toolResultText");
                    let editor = findNamed(sidebar, "bubbleContentText");
                    let body = findNamed(sidebar, "messageBody");
                    // Find the tool row rather than the user row.
                    let page = sidebar.currentPage;
                    let row = findNamed(sidebar, "assistantMessage_" + page.session.channelId + "_1");
                    raw = findNamed(row, "toolResultText");
                    editor = findNamed(row, "bubbleContentText");
                    body = findNamed(row, "messageBody");
                    if (raw.text.length || editor.text.length || body.segments.length) {
                        console.error("FAIL hidden output was laid out"); Qt.exit(1); return;
                    }
                    row.toolExpanded = true;
                    Qt.callLater(() => {
                        if (raw.text !== page.session.currentChat[1].content) {
                            console.error("FAIL expanded output missing"); Qt.exit(1); return;
                        }
                        row.toolExpanded = false;
                        Qt.callLater(() => {
                            if (raw.text.length) { Qt.exit(1); return; }
                            console.log("PASS hidden output stays unloaded; expand and collapse retain data");
                            console.log("PASS UI responsive", test.beats); Qt.quit();
                        });
                    });
                    return;
                }
                if (test.beats < 10) {''', 1)
                fixture_shell.write_text(source)
            for relative in (
                "modules/services/Ai.qml", "modules/services/AiSession.qml",
                "modules/services/AiQuestions.js",
                "modules/sidebar/AssistantSidebar.qml",
                "modules/sidebar/AssistantActivity.qml",
                "modules/sidebar/AssistantQuestions.qml",
                "modules/sidebar/AssistantModelPicker.qml",
                "modules/sidebar/CodeBlock.qml",
                "modules/theme/Motion.qml", "modules/components/StyledRect.qml", "modules/components/StyledToolTip.qml", "modules/components/StyledText.qml",
            ):
                target = package / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)

            runtime = Path(temporary) / "runtime"
            runtime.mkdir(mode=0o700)
            environment = dict(os.environ)
            environment.update(
                AI_LAYOUT_SCENARIO=scenario,
                QT_QPA_PLATFORM="offscreen",
                QT_QPA_PLATFORMTHEME="",
                XDG_RUNTIME_DIR=str(runtime),
                XDG_CACHE_HOME=str(Path(temporary) / "cache"),
            )
            try:
                result = subprocess.run(
                    ["qs", "-p", str(package), "--no-color"],
                    env=environment,
                    capture_output=True,
                    text=True,
                    timeout=8,
                )
            except subprocess.TimeoutExpired:
                self.fail("Chat layout blocked the event loop; its 3-second timer never finished")
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output[-4000:])
            self.assertIn(f"LOADED messages {message_count}", output)
            self.assertIn("PASS UI responsive", output)


if __name__ == "__main__":
    unittest.main()
