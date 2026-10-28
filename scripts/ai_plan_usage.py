#!/usr/bin/env python3
"""Read Codex account quotas without inference; also expose a stdio MCP tool."""

import json
from contextlib import suppress
import os
import selectors
import signal
import shutil
import subprocess
import sys
import time


def read_usage():
    executable = shutil.which("codex")
    if not executable:
        return {"error": "Codex is not installed"}
    process = None
    try:
        process = subprocess.Popen(
            [executable, "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, start_new_session=True,
        )
        deadline = time.monotonic() + 20
        buffer = b""
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)

        def send(message):
            process.stdin.write((json.dumps(message) + "\n").encode())
            process.stdin.flush()

        def request(identifier, method, params):
            nonlocal buffer
            send({"id": identifier, "method": method, "params": params})
            while time.monotonic() < deadline:
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    try:
                        response = json.loads(line)
                    except (ValueError, UnicodeDecodeError):
                        continue
                    if response.get("id") == identifier and "method" not in response:
                        if "error" in response:
                            raise RuntimeError("Codex could not read plan usage; check your login and connection")
                        return response.get("result", {})
                if selector.select(max(0, deadline - time.monotonic())):
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        raise RuntimeError("Codex usage service stopped")
                    buffer += chunk
            raise TimeoutError("Plan usage check timed out")

        try:
            request(1, "initialize", {"clientInfo": {
                "name": "rebos_shell_usage", "title": "Assistant plan usage", "version": "1.0.0"
            }})
            send({"method": "initialized", "params": {}})
            result = request(2, "account/rateLimits/read", {})
        finally:
            selector.close()
        # Only quota fields leave the helper. No account identity or credentials.
        buckets = result.get("rateLimitsByLimitId") or {}
        if not buckets and result.get("rateLimits"):
            snapshot = result["rateLimits"]
            buckets = {snapshot.get("limitId") or "codex": snapshot}
        if not buckets:
            return {"error": "Plan usage is unavailable for this account"}
        limits = []
        for key, snapshot in buckets.items():
            if not isinstance(snapshot, dict):
                continue
            windows = []
            for kind in ("primary", "secondary"):
                window = snapshot.get(kind)
                if window and isinstance(window.get("usedPercent"), (int, float)):
                    windows.append({
                        "kind": kind, "usedPercent": window["usedPercent"],
                        "windowDurationMins": window.get("windowDurationMins"),
                        "resetsAt": window.get("resetsAt"),
                    })
            limits.append({"id": key, "name": snapshot.get("limitName") or key,
                           "plan": snapshot.get("planType"), "windows": windows})
        return {"limits": limits, "checkedAt": int(time.time()),
                "scope": "Shared Codex account quota, including other Codex clients"}
    except (OSError, RuntimeError, TimeoutError):
        return {"error": "Could not read plan usage; check Codex login and network access"}
    finally:
        if process is not None:
            with suppress(OSError):
                process.stdin.close()
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                with suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            process.stdout.close()


def serve_mcp():
    for line in sys.stdin:
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                raise ValueError("Expected a JSON object")
            if "id" not in request:
                continue
            method = request.get("method")
            error = None
            if method == "initialize":
                result = {"protocolVersion": request.get("params", {}).get("protocolVersion", "2024-11-05"),
                          "capabilities": {"tools": {}},
                          "serverInfo": {"name": "assistant-plan-usage", "version": "1.0.0"}}
            elif method == "ping":
                result = {}
            elif method == "tools/list":
                result = {"tools": [{"name": "check_plan_usage",
                    "description": "Check shared Codex plan quota usage percentages and reset times. Includes other Codex clients. Does not run inference.",
                    "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
                    "annotations": {"readOnlyHint": True, "destructiveHint": False}}]}
            elif method == "tools/call" and request.get("params", {}).get("name") == "check_plan_usage":
                usage = read_usage()
                result = {"content": [{"type": "text", "text": json.dumps(usage)}],
                          "isError": "error" in usage}
            else:
                error = {"code": -32601, "message": "Unknown method or tool"}
            response = {"jsonrpc": "2.0", "id": request["id"]}
            response["error" if error else "result"] = error or result
            print(json.dumps(response), flush=True)
        except (ValueError, TypeError):
            print(json.dumps({"jsonrpc": "2.0", "id": None,
                              "error": {"code": -32700, "message": "Invalid JSON request"}}), flush=True)


if __name__ == "__main__":
    if "--mcp" in sys.argv:
        serve_mcp()
    else:
        print(json.dumps(read_usage()))
