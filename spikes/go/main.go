// Command planner-desktop is a Fyne spike of a desktop front end for planner:
// browse plan folders across several repos, edit ITERATION files, and run
// explore/plan/run agent sessions over ACP side by side.
//
//	go run . [-agent "cmd args..."] /path/to/parent-folder
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
)

// DefaultAgent is Zed's (now agentclientprotocol's) Claude Code ACP adapter.
// The package was renamed from @zed-industries/claude-code-acp and then
// @zed-industries/claude-agent-acp; both old names are deprecated on npm.
const DefaultAgent = "npx -y @agentclientprotocol/claude-agent-acp"

func main() {
	agentFlag := flag.String("agent", "", "agent command speaking ACP on stdio (default $PLANNER_AGENT or "+DefaultAgent+")")
	flag.Parse()
	parent := "."
	if flag.NArg() > 0 {
		parent = flag.Arg(0)
	}
	agent := *agentFlag
	if agent == "" {
		agent = os.Getenv("PLANNER_AGENT")
	}
	if agent == "" {
		agent = DefaultAgent
	}

	a := app.NewWithID("dev.pythonandchips.planner.spike")
	w := a.NewWindow("Planner")
	ui, err := newUI(a, w, parent, strings.Fields(agent))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	w.SetContent(ui.build())
	w.SetMainMenu(ui.menu())
	w.Resize(fyne.NewSize(1280, 820))
	w.SetOnClosed(ui.closeAll)
	w.ShowAndRun()
}
