#!/usr/bin/env python3
"""A tiny ACP agent for testing PlannerDesk without network or API keys.

Speaks newline-delimited JSON-RPC 2.0 over stdio. On the first prompt of a
session it streams a message, starts a tool call, asks for permission, then
finishes the tool call and ends the turn with a plain-text question (the way
Claude asks the user something). On later prompts it echoes the reply and
ends the turn.

If the first prompt contains "[gates]" it instead acts as an MCP client of
the planner gate server passed in session/new.mcpServers (spawning its stdio
command, like Claude Code): initialize, tools/list, then tools/call for
ask_user, confirm_start, check_in and ask_commit, with an AskUserQuestion-
style elicitation/create in between. Each answer is echoed as a chunk.

Environment:
  MOCK_ACP_DELAY  seconds to sleep between chunks (default 0.02)
"""
import json
import os
import subprocess
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


def request_client(method, params):
    """Sends an agent->client request and blocks until the client answers."""
    global next_id
    rid = next_id
    next_id += 1
    send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
    while True:
        msg = sys.stdin.readline()
        if not msg:
            sys.exit(0)
        msg = json.loads(msg)
        if msg.get("id") == rid and "method" not in msg:
            return msg.get("result")
        backlog.append(msg)


class McpClient:
    """Spawns the stdio MCP server from session/new.mcpServers the way
    Claude Code does, and speaks MCP JSON-RPC to it."""

    def __init__(self, server):
        env = dict(os.environ)
        for e in server.get("env", []):
            env[e["name"]] = e["value"]
        self.proc = subprocess.Popen([server["command"]] + server.get("args", []),
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     env=env, text=True, bufsize=1)
        self.next = 1

    def call(self, method, params=None):
        mid = self.next
        self.next += 1
        self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": mid, "method": method,
                                          "params": params or {}}) + "\n")
        self.proc.stdin.flush()
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("MCP server closed")
            msg = json.loads(line)
            if msg.get("id") == mid:
                return msg

    def notify(self, method):
        self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method}) + "\n")
        self.proc.stdin.flush()

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=5)


def gate_call(session_id, mcp, n, tool, arguments):
    """One gate tool call, reported the way the Claude adapter reports MCP
    tools: tool_call (pending) with _meta.claudeCode.toolName, then
    tool_call_update completed once the tools/call returns."""
    call_id = f"gate_{n}"
    update(session_id, {"sessionUpdate": "tool_call", "toolCallId": call_id,
                        "title": f"mcp__planner__{tool}", "kind": "other", "status": "pending",
                        "rawInput": arguments,
                        "_meta": {"claudeCode": {"toolName": f"mcp__planner__{tool}"}}})
    reply = mcp.call("tools/call", {"name": tool, "arguments": arguments})
    text = reply["result"]["content"][0]["text"]
    update(session_id, {"sessionUpdate": "tool_call_update", "toolCallId": call_id,
                        "status": "completed",
                        "_meta": {"claudeCode": {"toolName": f"mcp__planner__{tool}"}}})
    chunk(session_id, f"{tool} -> {text}\n")
    return reply


def gates_turn(session_id):
    """Exercises every gate, plus an AskUserQuestion-style elicitation."""
    servers = sessions[session_id].get("mcpServers") or []
    server = next((s for s in servers if s.get("name") == "planner" and "command" in s), None)
    if server is None:
        chunk(session_id, "No planner MCP server was passed.")
        return
    mcp = McpClient(server)
    init = mcp.call("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                   "clientInfo": {"name": "mock-agent", "version": "0"}})
    mcp.notify("notifications/initialized")
    tools = mcp.call("tools/list")["result"]["tools"]
    chunk(session_id, f"MCP {init['result']['serverInfo']['name']} tools: "
                      f"{','.join(t['name'] for t in tools)}\n")
    gate_call(session_id, mcp, 1, "ask_user", {"questions": [
        {"id": "scope", "text": "Which repos are in scope?", "choices": ["planner", "all"]},
        {"id": "deadline", "text": "Any deadline?"}]})
    # AskUserQuestion as the Claude adapter bridges it (elicitation.js).
    update(session_id, {"sessionUpdate": "tool_call", "toolCallId": "ask_1", "title": "AskUserQuestion",
                        "kind": "other", "status": "pending",
                        "_meta": {"claudeCode": {"toolName": "AskUserQuestion"}}})
    result = request_client("elicitation/create", {
        "mode": "form", "sessionId": session_id, "toolCallId": "ask_1",
        "message": "Which framework?",
        "requestedSchema": {"type": "object", "properties": {
            "question_0": {"type": "string", "title": "Framework",
                           "oneOf": [{"const": "SwiftUI", "title": "SwiftUI", "description": "Native"},
                                     {"const": "AppKit", "title": "AppKit"}]},
            "question_0_custom": {"type": "string", "title": "Other"}}}})
    update(session_id, {"sessionUpdate": "tool_call_update", "toolCallId": "ask_1", "status": "completed"})
    chunk(session_id, f"elicitation -> {json.dumps(result, sort_keys=True)}\n")
    gate_call(session_id, mcp, 2, "confirm_start", {"brief": "Build **the** thing."})
    gate_call(session_id, mcp, 3, "check_in", {"summary": "Found X.",
                                               "recommendations": ["Use Y (finding 1)"],
                                               "next_steps": ["Look at A", "Look at B"]})
    gate_call(session_id, mcp, 4, "ask_commit", {})
    bad = mcp.call("tools/call", {"name": "check_in", "arguments": {}})
    chunk(session_id, f"bad args isError={bad['result']['isError']}\n")
    mcp.close()
    chunk(session_id, "Gates done.")


def first_turn(session_id, prompt_text):
    if "[gates]" in prompt_text:
        gates_turn(session_id)
        return
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
        sessions[sid] = {"turns": 0, "cwd": params.get("cwd"),
                         "mcpServers": params.get("mcpServers"), "meta": params.get("_meta")}
        log(f"session/new mcpServers={json.dumps(params.get('mcpServers'))} _meta={json.dumps(params.get('_meta'))}")
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
