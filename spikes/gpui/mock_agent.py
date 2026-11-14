#!/usr/bin/env python3
"""A tiny ACP agent for tests and demos. Speaks JSON-RPC 2.0 over stdio.

First prompt: streams text, starts a tool call, asks permission, finishes the
tool call, then ends the turn with a plain-text question.
Later prompts: echoes the reply and ends the turn.

Set MOCK_AGENT_DELAY (seconds, default 0) to slow streaming down for demos.
"""
import json
import os
import sys
import time

DELAY = float(os.environ.get("MOCK_AGENT_DELAY", "0"))
pending = []  # messages read while waiting for a specific response
next_id = 1000
turns = 0


def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def read():
    if pending:
        return pending.pop(0)
    line = sys.stdin.readline()
    if not line:
        sys.exit(0)
    return json.loads(line)


def update(session_id, upd):
    send({"jsonrpc": "2.0", "method": "session/update",
          "params": {"sessionId": session_id, "update": upd}})
    if DELAY:
        time.sleep(DELAY)


def chunk(session_id, text):
    update(session_id, {"sessionUpdate": "agent_message_chunk",
                        "content": {"type": "text", "text": text}})


def request_permission(session_id, tool_call_id, title):
    global next_id
    next_id += 1
    rid = next_id
    send({"jsonrpc": "2.0", "id": rid, "method": "session/request_permission",
          "params": {"sessionId": session_id,
                     "toolCall": {"toolCallId": tool_call_id, "title": title},
                     "options": [
                         {"optionId": "allow", "name": "Allow once", "kind": "allow_once"},
                         {"optionId": "allow-always", "name": "Always allow", "kind": "allow_always"},
                         {"optionId": "reject", "name": "Reject", "kind": "reject_once"},
                     ]}})
    while True:
        msg = read()
        if msg.get("id") == rid and "method" not in msg:
            return msg.get("result", {}).get("outcome", {})
        pending.append(msg)


def handle_prompt(msg):
    global turns
    turns += 1
    params = msg["params"]
    sid = params["sessionId"]
    text = "".join(b.get("text", "") for b in params.get("prompt", []))
    if turns == 1:
        for piece in ["Reading ", "the plan ", "folder.\n\n"]:
            chunk(sid, piece)
        update(sid, {"sessionUpdate": "tool_call", "toolCallId": "call-1",
                     "title": "Write ITERATION-002.md", "kind": "edit", "status": "pending"})
        outcome = request_permission(sid, "call-1", "Write ITERATION-002.md")
        allowed = outcome.get("outcome") == "selected" and outcome.get("optionId", "").startswith("allow")
        update(sid, {"sessionUpdate": "tool_call_update", "toolCallId": "call-1",
                     "status": "completed" if allowed else "failed"})
        chunk(sid, "Permission: %s.\n\n" % (outcome.get("optionId") or outcome.get("outcome")))
        chunk(sid, "**Question:** should the next iteration cover the reply box?")
    else:
        chunk(sid, "You said: %s" % text)
    send({"jsonrpc": "2.0", "id": msg["id"], "result": {"stopReason": "end_turn"}})


def main():
    while True:
        msg = read()
        method = msg.get("method")
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": msg["id"], "result": {
                "protocolVersion": 1,
                "agentCapabilities": {},
                "authMethods": [],
                "agentInfo": {"name": "mock-agent", "version": "0.0.1"}}})
        elif method == "session/new":
            send({"jsonrpc": "2.0", "id": msg["id"], "result": {"sessionId": "mock-session"}})
        elif method == "session/prompt":
            handle_prompt(msg)
        elif method == "session/cancel":
            pass
        elif "id" in msg and method:
            send({"jsonrpc": "2.0", "id": msg["id"],
                  "error": {"code": -32601, "message": "method not found: %s" % method}})


if __name__ == "__main__":
    main()
