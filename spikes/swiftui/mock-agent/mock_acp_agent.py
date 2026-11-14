#!/usr/bin/env python3
"""A tiny ACP agent for testing PlannerDesk without network or API keys.

Speaks newline-delimited JSON-RPC 2.0 over stdio. On the first prompt of a
session it streams a message, starts a tool call, asks for permission, then
finishes the tool call and ends the turn with a plain-text question (the way
Claude asks the user something). On later prompts it echoes the reply and
ends the turn.

Environment:
  MOCK_ACP_DELAY  seconds to sleep between chunks (default 0.02)
"""
import json
import os
import sys
import time

DELAY = float(os.environ.get("MOCK_ACP_DELAY", "0.02"))
next_id = 1000
sessions = {}
backlog = []  # messages read while waiting for a specific response


def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def log(text):
    sys.stderr.write(f"mock-agent: {text}\n")
    sys.stderr.flush()


def read_message():
    if backlog:
        return backlog.pop(0)
    line = sys.stdin.readline()
    if not line:
        return None
    return json.loads(line)


def update(session_id, payload):
    send({"jsonrpc": "2.0", "method": "session/update",
          "params": {"sessionId": session_id, "update": payload}})
    time.sleep(DELAY)


def chunk(session_id, text):
    update(session_id, {"sessionUpdate": "agent_message_chunk",
                        "content": {"type": "text", "text": text}})


def request_permission(session_id, tool_call_id, title):
    """Sends session/request_permission and blocks until the client answers.
    Anything else that arrives meanwhile (e.g. session/cancel) is kept."""
    global next_id
    rid = next_id
    next_id += 1
    send({"jsonrpc": "2.0", "id": rid, "method": "session/request_permission",
          "params": {
              "sessionId": session_id,
              "toolCall": {"toolCallId": tool_call_id, "title": title},
              "options": [
                  {"optionId": "allow-once", "name": "Allow once", "kind": "allow_once"},
                  {"optionId": "allow-always", "name": "Always allow", "kind": "allow_always"},
                  {"optionId": "reject-once", "name": "Reject", "kind": "reject_once"},
              ]}})
    while True:
        msg = sys.stdin.readline()
        if not msg:
            sys.exit(0)
        msg = json.loads(msg)
        if msg.get("id") == rid and "method" not in msg:
            outcome = msg.get("result", {}).get("outcome", {})
            return outcome.get("optionId") if outcome.get("outcome") == "selected" else None
        backlog.append(msg)


def first_turn(session_id, prompt_text):
    for piece in ["I'll look at ", "the plan folder ", "first.\n\n"]:
        chunk(session_id, piece)
    update(session_id, {"sessionUpdate": "agent_thought_chunk",
                        "content": {"type": "text", "text": "Need to edit ITERATION file."}})
    update(session_id, {"sessionUpdate": "plan", "entries": [
        {"content": "Read ITERATION-001.md", "status": "completed", "priority": "high"},
        {"content": "Edit notes", "status": "in_progress", "priority": "medium"},
    ]})
    update(session_id, {"sessionUpdate": "tool_call", "toolCallId": "call_1",
                        "title": "Edit docs/plans/notes.md", "kind": "edit",
                        "status": "pending"})
    choice = request_permission(session_id, "call_1", "Edit docs/plans/notes.md")
    if choice and choice.startswith("allow"):
        update(session_id, {"sessionUpdate": "tool_call_update", "toolCallId": "call_1",
                            "status": "completed",
                            "content": [{"type": "content",
                                         "content": {"type": "text", "text": "Wrote 3 lines"}}]})
        chunk(session_id, "Done editing. ")
    else:
        update(session_id, {"sessionUpdate": "tool_call_update", "toolCallId": "call_1",
                            "status": "failed"})
        chunk(session_id, "Okay, I left the file alone. ")
    chunk(session_id, "Which approach do you prefer: A or B?")


def handle(msg):
    method = msg.get("method")
    mid = msg.get("id")
    params = msg.get("params", {})
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": 1,
            "agentCapabilities": {"loadSession": False,
                                  "promptCapabilities": {"image": False}},
            "authMethods": []}})
    elif method == "session/new":
        sid = f"sess_{len(sessions) + 1}"
        sessions[sid] = {"turns": 0, "cwd": params.get("cwd")}
        send({"jsonrpc": "2.0", "id": mid, "result": {"sessionId": sid}})
    elif method == "session/prompt":
        sid = params["sessionId"]
        text = "".join(b.get("text", "") for b in params.get("prompt", []))
        state = sessions[sid]
        state["turns"] += 1
        if state["turns"] == 1:
            first_turn(sid, text)
        else:
            chunk(sid, f"You said: {text}. ")
            chunk(sid, "All done.")
        send({"jsonrpc": "2.0", "id": mid, "result": {"stopReason": "end_turn"}})
    elif method == "session/cancel":
        log("cancel received")
    elif mid is not None and method is not None:
        send({"jsonrpc": "2.0", "id": mid,
              "error": {"code": -32601, "message": f"Method not found: {method}"}})


def main():
    log("started")
    while True:
        msg = read_message()
        if msg is None:
            break
        handle(msg)


if __name__ == "__main__":
    main()
