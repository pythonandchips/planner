#!/bin/bash
# Runs the headless probe against the real Claude adapter.
#   scripts/probe-gates.sh gates        ask_user (2 questions) + AskUserQuestion, answers after $PROBE_DELAY (default 75 s)
#   scripts/probe-gates.sh permission   tries to trigger a real session/request_permission
# The agent runs in .build/probe-cwd, a scratch dir. Output: the full ACP/MCP trace on stdout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$ROOT/.build/swiftc/acp-probe"
AGENT="${AGENT:-npx -y @agentclientprotocol/claude-agent-acp}"
mkdir -p "$ROOT/.build/probe-cwd"
cd "$ROOT/.build/probe-cwd"

case "${1:-gates}" in
gates)
    export PROBE_DELAY="${PROBE_DELAY:-75}"
    exec "$PROBE" "$AGENT" 'This is a test of a GUI client. Do exactly these two steps and nothing else: 1) Call the tool mcp__planner__ask_user once with two questions: {"id":"color","text":"Favourite colour?","choices":["red","blue"]} and {"id":"name","text":"What should I call you?"}. 2) Then use the AskUserQuestion tool once with one question "Which framework?" offering the options SwiftUI and AppKit. Then reply with one line repeating all three answers.'
    ;;
flow)
    export PROBE_DELAY=1
    exec "$PROBE" "$AGENT" 'This is a test of a GUI client. Do not read or write files. 1) Call mcp__planner__confirm_start with brief "Test brief: **check the gates**". 2) Only if its result is exactly "Make it so", call mcp__planner__check_in with summary "All gates reachable.", recommendations ["Use MCP gates (finding 1)"] and next_steps ["Try HTTP", "Try FIFO"]. 3) Then call mcp__planner__ask_commit with context "nothing to stage". Finally reply with one line quoting the three tool results verbatim.'
    ;;
permission)
    export PROBE_DELAY=1
    export PROBE_META='{"claudeCode":{"options":{"settings":{"permissions":{"ask":["Bash(touch:*)","Bash(touch *)"]}}}}}'
    export PROBE_MODE="${PROBE_MODE:-default}"
    exec "$PROBE" "$AGENT" 'This is a test of a GUI client. Run exactly this one Bash command and nothing else: touch probe-file.txt . Then reply with one word: done.'
    ;;
*) echo "usage: $0 [gates|permission]" >&2; exit 2 ;;
esac
