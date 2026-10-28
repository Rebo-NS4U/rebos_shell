"""Check the helper at its app-server and MCP subprocess boundaries."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/ai_plan_usage.py"


class PlanUsageTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ai-plan-usage-")
        self.addCleanup(self.temporary.cleanup)
        directory = Path(self.temporary.name)
        executable = directory / "codex"
        executable.write_text(f"#!{sys.executable}\n" + '''
import json, sys
for line in sys.stdin:
    request = json.loads(line)
    if request["method"] == "initialize":
        result = {}
    elif request["method"] == "initialized":
        continue
    elif request["method"] == "account/rateLimits/read":
        result = {"rateLimitsByLimitId": {"codex": {
            "primary": {"usedPercent": 0, "windowDurationMins": 300, "resetsAt": 2000000000},
            "secondary": {"usedPercent": 83, "windowDurationMins": 10080, "resetsAt": 2000500000},
            "private": "must-not-escape"
        }, "other": {"primary": None, "secondary": None}},
        "private": "must-not-escape"}
    else:
        raise SystemExit("Unexpected request")
    print(json.dumps({"method": "account/updated", "params": {}}), flush=True)
    response = json.dumps({"id": request["id"], "result": result}) + "\\n"
    # Split a line across writes, as real stdio streams can do.
    sys.stdout.write(response[:20]); sys.stdout.flush()
    sys.stdout.write(response[20:]); sys.stdout.flush()
''')
        executable.chmod(0o700)
        self.environment = dict(os.environ, PATH=str(directory))

    def run_helper(self, *arguments, input_text=None):
        return subprocess.run([sys.executable, str(SCRIPT), *arguments],
                              input=input_text, capture_output=True, text=True,
                              env=self.environment, timeout=5, check=True)

    def test_quota_windows_and_private_fields(self):
        result = self.run_helper()
        usage = json.loads(result.stdout)
        self.assertNotIn("must-not-escape", result.stdout)
        windows = usage["limits"][0]["windows"]
        self.assertEqual([window["usedPercent"] for window in windows], [0, 83])
        self.assertEqual(windows[1]["windowDurationMins"], 10080)
        self.assertEqual(windows[0]["resetsAt"], 2000000000)
        self.assertIn("other Codex clients", usage["scope"])

    def test_missing_codex_returns_json_error(self):
        self.environment["PATH"] = ""
        self.assertEqual(json.loads(self.run_helper().stdout), {"error": "Codex is not installed"})

    def test_mcp_discovery_call_and_unknown_method(self):
        requests = [
            {"id": 1, "method": "initialize", "params": {"protocolVersion": "2025-03-26"}},
            {"method": "notifications/initialized"},
            {"id": 2, "method": "tools/list"},
            {"id": 3, "method": "tools/call", "params": {"name": "check_plan_usage", "arguments": {}}},
            {"id": 4, "method": "unknown"},
        ]
        result = self.run_helper("--mcp", input_text="".join(json.dumps(r) + "\n" for r in requests))
        responses = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(responses), 4)
        self.assertEqual(responses[0]["result"]["protocolVersion"], "2025-03-26")
        self.assertEqual(responses[1]["result"]["tools"][0]["name"], "check_plan_usage")
        self.assertFalse(responses[2]["result"]["isError"])
        self.assertIn("limits", json.loads(responses[2]["result"]["content"][0]["text"]))
        self.assertEqual(responses[3]["error"]["code"], -32601)


if __name__ == "__main__":
    unittest.main()
