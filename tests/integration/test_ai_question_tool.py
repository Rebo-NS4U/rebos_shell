"""Verify the actual stdio MCP helper waits for explicit card answers."""
import json
from pathlib import Path
import subprocess
import sys
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ai_questions.py"


class QuestionToolTest(unittest.TestCase):
    def exchange(self, action="accept", capabilities=None):
        messages = [
            {"id": 1, "method": "initialize", "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": capabilities if capabilities is not None else {"elicitation": {"form": {}}}}},
            {"id": 2, "method": "tools/list"},
            {"id": 3, "method": "tools/call", "params": {
                "name": "ask_user_question", "arguments": {
                    "question": "Which appearance?", "options": ["Subtle (Recommended)", "Colorful"]}}},
            {"id": 4, "method": "ping"},
            {"id": "question-1", "result": {"action": action, "content": {
                "answer": "Something else", "details": "Keep the existing appearance"}}},
        ]
        process = subprocess.run([sys.executable, str(SCRIPT)],
                                 input="".join(json.dumps(m) + "\n" for m in messages),
                                 capture_output=True, text=True, timeout=5, check=True)
        self.assertEqual(process.stderr, "")
        return [json.loads(line) for line in process.stdout.splitlines()]

    def test_question_answer_and_ping(self):
        messages = self.exchange()
        self.assertEqual(messages[1]["result"]["tools"][0]["name"], "ask_user_question")
        card = messages[2]
        self.assertEqual(card["method"], "elicitation/create")
        self.assertEqual(card["params"]["requestedSchema"]["properties"]["answer"]["enum"],
                         ["Subtle (Recommended)", "Colorful", "Something else"])
        self.assertEqual(messages[3], {"jsonrpc": "2.0", "id": 4, "result": {}})
        self.assertEqual(messages[4]["id"], 3)
        answer = json.loads(messages[4]["result"]["content"][0]["text"])
        self.assertEqual(answer["content"]["details"], "Keep the existing appearance")

    def test_decline_and_cancel(self):
        for action in ("decline", "cancel"):
            answer = json.loads(self.exchange(action)[-1]["result"]["content"][0]["text"])
            self.assertEqual(answer, {"action": action, "content": None})

    def test_unsupported_client(self):
        messages = self.exchange(capabilities={})
        self.assertTrue(messages[2]["result"]["isError"])
        self.assertFalse(any(m.get("method") == "elicitation/create" for m in messages))


if __name__ == "__main__":
    unittest.main()
