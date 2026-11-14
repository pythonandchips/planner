// Command acpcli runs one ACP turn through the session package without the
// GUI, printing the transcript. Permission requests are answered with the
// first reject option (or the first option if none rejects) so it is safe to
// point at a real agent.
//
//	go run ./cmd/acpcli -cwd /some/repo -agent "npx -y @agentclientprotocol/claude-agent-acp" "prompt"
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"planner-desktop-spike/session"
)

func main() {
	agent := flag.String("agent", "npx -y @agentclientprotocol/claude-agent-acp", "agent command")
	cwd := flag.String("cwd", ".", "session working directory")
	timeout := flag.Duration("timeout", 3*time.Minute, "overall timeout")
	flag.Parse()
	prompt := strings.Join(flag.Args(), " ")
	if prompt == "" {
		prompt = "Reply with one short sentence, then ask me one short question."
	}

	changed := make(chan struct{}, 1)
	s := session.New(session.Config{Command: strings.Fields(*agent), Cwd: *cwd, Title: "cli"}, func() {
		select {
		case changed <- struct{}{}:
		default:
		}
	})
	defer s.Close()
	start := time.Now()
	if err := s.Start(prompt); err != nil {
		dump(s)
		fmt.Fprintln(os.Stderr, "start:", err)
		os.Exit(1)
	}
	fmt.Printf("[session started after %s]\n", time.Since(start).Round(time.Millisecond))
	deadline := time.After(*timeout)
	for {
		select {
		case <-changed:
		case <-deadline:
			dump(s)
			fmt.Fprintln(os.Stderr, "timeout")
			os.Exit(1)
		}
		if i := s.PendingPermission(); i >= 0 {
			e := s.Snapshot().Entries[i]
			pick := e.Options[0]
			for _, o := range e.Options {
				if strings.HasPrefix(o.Kind, "reject") {
					pick = o
					break
				}
			}
			fmt.Printf("[permission %q: choosing %q]\n", e.Text, pick.Name)
			_ = s.ResolvePermission(i, pick.ID)
		}
		st := s.Snapshot().Status
		if st == session.StatusAwaitingInput || st == session.StatusQuestion || st == session.StatusError || st == session.StatusExited {
			fmt.Printf("[turn ended after %s: %s]\n", time.Since(start).Round(time.Millisecond), st)
			dump(s)
			return
		}
	}
}

func dump(s *session.Session) {
	snap := s.Snapshot()
	for _, e := range snap.Entries {
		switch e.Kind {
		case session.EntryTool:
			fmt.Printf("%-10s %s [%s]\n", e.Kind, e.Text, e.ToolStatus)
		case session.EntryPermission:
			fmt.Printf("%-10s %s -> %s\n", e.Kind, e.Text, e.Chosen)
		default:
			q := ""
			if e.Question {
				q = " (question)"
			}
			fmt.Printf("%-10s%s %s\n", e.Kind, q, strings.TrimSpace(e.Text))
		}
	}
	if snap.Stderr != "" {
		lines := strings.Split(strings.TrimSpace(snap.Stderr), "\n")
		if len(lines) > 15 {
			lines = lines[len(lines)-15:]
		}
		fmt.Println("--- agent stderr (tail) ---")
		fmt.Println(strings.Join(lines, "\n"))
	}
}
