#!/usr/bin/env python3
"""Expose answerable shell question cards through MCP form elicitation."""

import json
import sys


TOOL = {
    "name": "ask_user_question",
    "description": (
        "Ask the user a focused question in the shell assistant's answerable card. "
        "Use proactively when a meaningful preference, scope choice, or missing detail "
        "could change the result. Ask early, offer 2–3 clear choices when useful, put "
        "the recommended choice first, and wait for the answer. Do not ask for routine "
        "permission, repeat answered questions, collect secrets, or invent busywork."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "question": {"type": "string", "minLength": 1, "maxLength": 2000},
            "options": {"type": "array", "items": {"type": "string", "minLength": 1},
                        "minItems": 2, "maxItems": 4, "uniqueItems": True},
        },
        "required": ["question"], "additionalProperties": False,
    },
    "annotations": {"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False},
}


def question_schema(arguments):
    if not isinstance(arguments, dict) or set(arguments) - {"question", "options"}:
        raise ValueError("Expected question and optional options")
    question = arguments.get("question")
    if not isinstance(question, str) or not question.strip() or len(question) > 2000:
        raise ValueError("Provide a nonempty question of at most 2000 characters")
    options = arguments.get("options")
    if options is not None and (
        not isinstance(options, list) or not 2 <= len(options) <= 4
        or any(not isinstance(option, str) or not option.strip() for option in options)
        or len(set(options)) != len(options)
    ):
        raise ValueError("Provide 2–4 distinct, nonempty choices")
    answer = {"type": "string", "title": "Your answer", "minLength": 1}
    properties = {"answer": answer}
    if options:
        answer["enum"] = options + ["Something else"] if "Something else" not in options else options
        properties["details"] = {"type": "string", "title": "Your own answer or extra details (optional)"}
    return question, {"type": "object", "properties": properties, "required": ["answer"]}


def serve():
    pending = {}
    counter = 0
    supports_forms = False

    def send(message):
        print(json.dumps({"jsonrpc": "2.0", **message}), flush=True)

    def result(identifier, value):
        send({"id": identifier, "result": value})

    def tool_result(identifier, value, error=False):
        result(identifier, {"content": [{"type": "text", "text": json.dumps(value)}], "isError": error})

    for line in sys.stdin:
        try:
            message = json.loads(line)
            if not isinstance(message, dict):
                raise ValueError("Expected a JSON object")
        except ValueError:
            send({"id": None, "error": {"code": -32700, "message": "Invalid JSON request"}})
            continue
        identifier = message.get("id")
        if "method" not in message:
            waiting = pending.pop(identifier, None)
            if waiting is not None:
                response = message.get("result") or {}
                action = response.get("action", "cancel")
                tool_result(waiting, {"action": action, "content": response.get("content") if action == "accept" else None}, "error" in message)
            continue
        method = message["method"]
        params = message.get("params") or {}
        if method == "notifications/cancelled":
            for request_id, call_id in list(pending.items()):
                if call_id == params.get("requestId"):
                    del pending[request_id]
                    send({"method": "notifications/cancelled", "params": {"requestId": request_id}})
            continue
        if "id" not in message:
            continue
        if method == "initialize":
            supports_forms = "form" in params.get("capabilities", {}).get("elicitation", {})
            result(identifier, {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                                "capabilities": {"tools": {}},
                                "serverInfo": {"name": "assistant-questions", "version": "1.0.0"}})
        elif method == "ping":
            result(identifier, {})
        elif method == "tools/list":
            result(identifier, {"tools": [TOOL]})
        elif method == "tools/call" and params.get("name") == TOOL["name"]:
            try:
                if not supports_forms:
                    raise ValueError("This client cannot show question cards. Ask the question in chat instead.")
                question, schema = question_schema(params.get("arguments", {}))
            except ValueError as error:
                tool_result(identifier, {"error": str(error)}, True)
                continue
            counter += 1
            request_id = "question-" + str(counter)
            pending[request_id] = identifier
            send({"id": request_id, "method": "elicitation/create", "params": {
                "mode": "form", "message": question, "requestedSchema": schema,
            }})
        else:
            send({"id": identifier, "error": {"code": -32601, "message": "Unknown method or tool"}})


if __name__ == "__main__":
    serve()
