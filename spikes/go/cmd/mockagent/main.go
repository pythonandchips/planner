// Command mockagent is a tiny ACP agent for tests and GUI demos. It speaks
// newline-delimited JSON-RPC 2.0 on stdio, written by hand (not with the SDK)
// so the client is checked against the wire format.
//
// Each first prompt in a session: streams a few message chunks, starts a tool
// call, asks session/request_permission, finishes the tool call according to
// the answer, then ends the turn with a plain-text question. Later prompts in
// the same session echo the reply and end the turn without a question.
//
// Prompts containing "noperm" skip the permission request.
// MOCK_DELAY_MS sets a delay between streamed updates (default 0).
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

type msg struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   json.RawMessage `json:"error,omitempty"`
}

var (
	outMu   sync.Mutex
	out     = bufio.NewWriter(os.Stdout)
	waitMu  sync.Mutex
	waiters = map[string]chan msg{}
	nextReq = 1000
	delay   time.Duration

	sessMu   sync.Mutex
	turns    = map[string]int{}
	cancels  = map[string]chan struct{}{}
	sessions = 0
)

func send(v any) {
	b, _ := json.Marshal(v)
	outMu.Lock()
	out.Write(b)
	out.WriteByte('\n')
	out.Flush()
	outMu.Unlock()
}

func reply(id json.RawMessage, result any) {
	send(map[string]any{"jsonrpc": "2.0", "id": id, "result": result})
}

func notify(sid string, update map[string]any) {
	send(map[string]any{"jsonrpc": "2.0", "method": "session/update",
		"params": map[string]any{"sessionId": sid, "update": update}})
	if delay > 0 {
		time.Sleep(delay)
	}
}

func chunk(sid, text string) {
	notify(sid, map[string]any{"sessionUpdate": "agent_message_chunk",
		"content": map[string]any{"type": "text", "text": text}})
}

func request(method string, params any) msg {
	waitMu.Lock()
	nextReq++
	id := strconv.Itoa(nextReq)
	ch := make(chan msg, 1)
	waiters[id] = ch
	waitMu.Unlock()
	send(map[string]any{"jsonrpc": "2.0", "id": nextReqID(id), "method": method, "params": params})
	return <-ch
}

func nextReqID(id string) int { n, _ := strconv.Atoi(id); return n }

func main() {
	if ms, err := strconv.Atoi(os.Getenv("MOCK_DELAY_MS")); err == nil {
		delay = time.Duration(ms) * time.Millisecond
	}
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 1024*1024), 16*1024*1024)
	for in.Scan() {
		var m msg
		if err := json.Unmarshal(in.Bytes(), &m); err != nil {
			fmt.Fprintln(os.Stderr, "mockagent: bad json:", err)
			continue
		}
		if m.Method == "" { // response to one of our requests
			waitMu.Lock()
			ch := waiters[strings.Trim(string(m.ID), `"`)]
			delete(waiters, strings.Trim(string(m.ID), `"`))
			waitMu.Unlock()
			if ch != nil {
				ch <- m
			}
			continue
		}
		switch m.Method {
		case "initialize":
			reply(m.ID, map[string]any{"protocolVersion": 1, "agentCapabilities": map[string]any{}, "authMethods": []any{}})
		case "session/new":
			sessMu.Lock()
			sessions++
			sid := fmt.Sprintf("mock-%d", sessions)
			sessMu.Unlock()
			reply(m.ID, map[string]any{"sessionId": sid})
		case "session/prompt":
			go prompt(m)
		case "session/cancel":
			var p struct {
				SessionID string `json:"sessionId"`
			}
			json.Unmarshal(m.Params, &p)
			sessMu.Lock()
			if c, ok := cancels[p.SessionID]; ok {
				close(c)
				delete(cancels, p.SessionID)
			}
			sessMu.Unlock()
		default:
			if len(m.ID) > 0 {
				send(map[string]any{"jsonrpc": "2.0", "id": m.ID,
					"error": map[string]any{"code": -32601, "message": "method not found: " + m.Method}})
			}
		}
	}
}

func prompt(m msg) {
	var p struct {
		SessionID string `json:"sessionId"`
		Prompt    []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"prompt"`
	}
	json.Unmarshal(m.Params, &p)
	text := ""
	for _, b := range p.Prompt {
		text += b.Text
	}
	sid := p.SessionID
	sessMu.Lock()
	turns[sid]++
	turn := turns[sid]
	cancel := make(chan struct{})
	cancels[sid] = cancel
	sessMu.Unlock()
	cancelled := func() bool {
		select {
		case <-cancel:
			return true
		default:
			return false
		}
	}
	done := func(reason string) {
		sessMu.Lock()
		delete(cancels, sid)
		sessMu.Unlock()
		reply(m.ID, map[string]any{"stopReason": reason})
	}

	if turn > 1 {
		chunk(sid, "Thanks. You said: ")
		chunk(sid, "*"+strings.TrimSpace(text)+"*")
		chunk(sid, ". I'll write that into the plan.")
		done("end_turn")
		return
	}

	for _, part := range []string{"I'll look at ", "the plan folder ", "first.\n\n"} {
		if cancelled() {
			done("cancelled")
			return
		}
		chunk(sid, part)
	}
	notify(sid, map[string]any{"sessionUpdate": "tool_call", "toolCallId": "call-1",
		"title": "Edit `docs/plans/ITERATION-001.md`", "kind": "edit", "status": "pending"})

	outcome := "allowed"
	if !strings.Contains(text, "noperm") {
		resp := request("session/request_permission", map[string]any{
			"sessionId": sid,
			"toolCall":  map[string]any{"toolCallId": "call-1", "title": "Edit `docs/plans/ITERATION-001.md`"},
			"options": []map[string]any{
				{"optionId": "allow", "name": "Allow", "kind": "allow_once"},
				{"optionId": "always", "name": "Always allow edits", "kind": "allow_always"},
				{"optionId": "reject", "name": "Reject", "kind": "reject_once"},
			},
		})
		var r struct {
			Outcome struct {
				Outcome  string `json:"outcome"`
				OptionID string `json:"optionId"`
			} `json:"outcome"`
		}
		json.Unmarshal(resp.Result, &r)
		switch {
		case r.Outcome.Outcome == "cancelled":
			done("cancelled")
			return
		case r.Outcome.OptionID == "reject":
			outcome = "rejected"
		}
	}
	status := "completed"
	if outcome == "rejected" {
		status = "failed"
	}
	notify(sid, map[string]any{"sessionUpdate": "tool_call_update", "toolCallId": "call-1", "status": status})
	chunk(sid, "The edit was "+outcome+".\n\n")
	chunk(sid, "Should I also split the work into **two iterations**, ")
	chunk(sid, "or keep it as one?")
	done("end_turn")
}
