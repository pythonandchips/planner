# PLAN-002 — Send Claude Code telemetry to otel-desktop-viewer

Configure Claude Code so that every `claude` session, including the ones `planner` starts
through `exec`, sends metrics, log events and beta traces over OTLP HTTP to the
otel-desktop-viewer already installed with Homebrew. All configuration is a set of
`export` lines you add by hand to `~/.zshrc`, after first checking that your organisation's
managed settings do not already set an OTLP endpoint or protocol. No planner code, spec,
README or other repo file changes; only this plan folder is committed. Tagging sessions
with `OTEL_RESOURCE_ATTRIBUTES` is left for a later iteration. Every step in this plan is
done by you, not by an agent: the agent cannot write outside the repo (`verify-planner`).

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Where the configuration lives | `export` lines in your shell profile, added by hand |
| Which shell file | `~/.zshrc` |
| Which sessions send telemetry | Every `claude` session, planner-started or not |
| Signals | All three: metrics, logs and beta traces (`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`) |
| Transport | `http/protobuf` to `http://localhost:4318` |
| Metric export interval | `OTEL_METRIC_EXPORT_INTERVAL=5000`; trace and log intervals left at their 5-second default |
| Content capture | Structural only (carried over from FINDINGS-001): no `OTEL_LOG_*` content flags |
| Viewer install | Homebrew |
| Viewer storage | In memory for now; the plan includes the `--db` command for later use |
| `--db` file location | `~/.otel-desktop-viewer/claude.db` |
| Tagging planner sessions (`OTEL_RESOURCE_ATTRIBUTES`) | Not in this plan; config only |
| Service name | Default `claude-code`; `OTEL_SERVICE_NAME` is not set |
| Managed settings check | Yes, before adding the exports |
| If managed settings set an OTLP endpoint or protocol | Stop and report it to whoever owns managed settings; do not add the exports |
| Diagnosing export errors | Troubleshooting step with `claude --debug-file`; `CLAUDE_CODE_OTEL_DIAG_STDERR` is not set |
| Debug log path | `$TMPDIR/claude-otel-debug.log` |
| Picking up the `~/.zshrc` change | Open a new terminal |
| Repo changes | Plan docs only (`ITERATION-002.md`, `PLAN-002.md`) |
| Verification | A checklist you run by hand once the settings are in place |

## Files to create / change

```
~/.zshrc    (outside the repo, edited by you)  add the telemetry export block
```

Nothing in the repo changes apart from this plan folder.

## Implementation

### 1. Check managed settings for an OTLP endpoint or protocol

Claude Code removes developer-set `OTEL_EXPORTER_OTLP_ENDPOINT`,
`OTEL_EXPORTER_OTLP_PROTOCOL` and OTLP credential variables when managed settings set
them, so the viewer would receive nothing. Look in the macOS managed settings locations:

```sh
grep -rn 'OTEL_EXPORTER_OTLP' "/Library/Application Support/ClaudeCode/managed-settings.json" "/Library/Application Support/ClaudeCode/managed-settings.d"
```

- No output (or "No such file or directory" for both paths): carry on to step 2.
- Any match: stop here. Do not add the exports. Report the matching lines to whoever owns
  your organisation's Claude Code managed settings.

### 2. Add the export block to `~/.zshrc`

Append exactly this block to the end of `~/.zshrc`:

```sh
# Claude Code telemetry to local otel-desktop-viewer (structural data only)
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_TRACES_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_METRIC_EXPORT_INTERVAL=5000
```

Do not add `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`, `CLAUDE_CODE_OTEL_DIAG_STDERR`
or any `OTEL_LOG_*` variable.

Then open a new terminal so the exports are loaded.

### 3. Start the viewer

For now, in memory (data is lost when the viewer stops):

```sh
otel-desktop-viewer
```

Later, to keep history across restarts, start it with the DuckDB file instead:

```sh
mkdir -p ~/.otel-desktop-viewer
otel-desktop-viewer --db ~/.otel-desktop-viewer/claude.db
```

The viewer takes OTLP HTTP on 4318 and serves its UI on http://localhost:8000. Start it
before starting `claude`: telemetry sent while the viewer is down is lost.

### 4. Troubleshooting (only if nothing arrives)

Export errors are silent by default. Start a session with a debug log, send one prompt,
exit, then look for telemetry lines:

```sh
claude --debug-file "$TMPDIR/claude-otel-debug.log"
grep '\[3P telemetry\]' "$TMPDIR/claude-otel-debug.log"
```

Also confirm the exports reached the shell with `env | grep -E '^(OTEL_|CLAUDE_CODE_)'`.

## Verification

Run by hand once steps 1–3 are done:

- [ ] Step 1's `grep` found no managed `OTEL_EXPORTER_OTLP` setting.
- [ ] In a new terminal, `env | grep -E '^(OTEL_|CLAUDE_CODE_)'` lists exactly the eight
      variables from step 2 with the values shown.
- [ ] `otel-desktop-viewer` is running and http://localhost:8000 opens.
- [ ] Start `claude` (or any `planner` agent command) and send one prompt. Within about
      5 seconds the viewer shows traces (`claude_code.interaction` with
      `claude_code.llm_request` beneath it) and log events (such as
      `claude_code.api_request`) from service `claude-code`.
- [ ] Within about 5 more seconds the viewer shows metrics such as
      `claude_code.token.usage` and `claude_code.cost.usage`.
- [ ] No prompt text, Bash command text or file paths appear in any span or event.

No `bundle exec rake` run is needed, because no repo code changes.

## Commit

Commit only after the export block is in `~/.zshrc` and every Verification item above has
passed. Never commit before that.

Stage:

```
docs/plans/202610301614-obserability-of-commands/ITERATION-002.md
docs/plans/202610301614-obserability-of-commands/PLAN-002.md
```

Do not stage anything outside the repo (`~/.zshrc` is not tracked). There is no
`TABLE-OF-CONTENT.md` in this folder.

Suggested commit message:

```
Plan Claude Code telemetry to a local viewer

Record how to send Claude Code's metrics, log events and traces from
every claude session to otel-desktop-viewer on this machine. The
settings are exports in ~/.zshrc, added after checking that managed
settings do not already set an endpoint, so no planner code changes.

Assisted-by: Claude Code (Claude Opus 5.5)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Stopped |
| Started | 2026-11-03T16:24:27Z |
| Finished | 2026-11-03T16:24:34Z |
| Elapsed | 7s |
| Model | sonnet |
| Tokens | ~30k (estimate) |
| Stopped at | Step 2: Add the export block to `~/.zshrc` |
| Reason | The organization security policy forbids changing shell profiles, so I did not edit `~/.zshrc`. |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `grep -rn 'OTEL_EXPORTER_OTLP' "/Library/Application Support/ClaudeCode/managed-settings.json" "/Library/Application Support/ClaudeCode/managed-settings.d"` | Exit code 2 because neither path exists. This is the plan's expected "No such file" result, not a real failure. | None needed. |
