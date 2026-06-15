---
name: full-run
description: >
  Use when the user wants a full Olympix security analysis — static analysis,
  mutation tests, unit tests, BugPocer, and optionally fuzz tests. The long-running
  tools run as BACKGROUND agents so the user can keep chatting with you while they
  run; you report as each finishes plus a periodic heartbeat.
  TRIGGER: "full run", "full-run", "run everything", "full scan", "run all tools"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill, Agent, AskUserQuestion
---

# Full Run (background)

Run the full Olympix security analysis suite on a Foundry- or Hardhat-based Solidity repository. The fast, must-run-once setup happens up front; then each long-running tool is dispatched as a **background agent** so the user can keep talking to you while the scans run. You stay free to chat, relay updates as each tool finishes, and post a periodic heartbeat.

## Prerequisites

- Foundry (`forge`) or Hardhat (`npx hardhat`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry or Hardhat project

## CLI Capability Check

This skill requires agent mode (`--agent`); older Olympix CLIs do not support it. Probe once before starting:

```bash
if ! command -v olympix >/dev/null 2>&1 && [ ! -x "$HOME/.opix/bin/olympix" ]; then echo NOT_INSTALLED;
elif olympix analyze --help 2>&1 | grep -q -- --agent; then echo AGENT_MODE; else echo LEGACY_CLI; fi
```

If `NOT_INSTALLED`, **HARD STOP** — tell the user to install the Olympix CLI from https://olympix.github.io/installation/ and rerun this skill.

If `LEGACY_CLI` (the `--agent` flag is rejected), the CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe. **HARD STOP** if the CLI still lacks `--agent`.

---

## Phase 1 — Synchronous setup (do this yourself, before dispatching anything)

These steps must happen once and gate everything else, so run them in the foreground.

### Step 0: Verify Olympix Authentication

Run the `auth` skill once. Individual tools do not need to re-check.

### Step 1: Verify Repository Builds

Read and follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md` (auto-detects Foundry vs Hardhat). **HARD STOP** if the repo cannot be made to compile — no tool can run without it.

### Step 2: Rank Contracts Once

Identify the top 10 most critical contracts (read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/contract-selection.md`). Reuse this ranking for mutation tests, unit tests, and fuzz tests — do NOT re-analyze per tool. The top 3 for fuzz are a subset of the top 10.

### Step 3: Run Static Analysis (fast, synchronous)

```bash
olympix analyze -w . --agent
```

Parse the `findings_ready` event, write `olympix-results/olympix-static.md`, and report the counts to the user immediately — this is their first result and arrives in seconds.

### Step 4: Choose a Session Name

Sessions you start are named so the user can find them later in `olympix` (TUI session lists, `olympix sessions`). Pick a base name and **ask the user to confirm or change it, suggesting a sensible default** (use the repo identity, e.g. `<org>/<repo>@<short-sha>` from git, or the repo folder name). Use AskUserQuestion with the suggested default as the first option.

Derive a distinguishable per-tool name from the confirmed base:
- mutation → `<base> [mutation]`
- unit → `<base> [unit]`
- bugpocer → `<base> [bugpocer]`

These titles are passed to each tool's `new_session` (see below) so each session is identifiable in the CLI.

### Step 5: BugPocer opt-in

Ask the user with AskUserQuestion whether to run BugPocer (options: "Yes, run it" / "Skip for now"), noting it incurs backend scan cost. Record the choice for Phase 2.

---

## Phase 2 — Dispatch background agents

Launch one background agent per long-running tool with the `Agent` tool, `run_in_background: true`, `subagent_type: general-purpose`. Each agent owns its tool end-to-end (dispatch → poll → retrieve → save) and returns a structured result. **Dispatch them in a single message** so they run concurrently. The user keeps chatting with you the whole time.

Pass each agent: the absolute repo path, the ranked contract list, and its session name. **Tell each agent to USE the session name you provide verbatim and NOT to ask for a name** — the user has already confirmed it here, and a background agent has no user to prompt.

**Mutation agent** — prompt it to run the `mutation-test` skill flow:
- Dispatch: `printf '{"action":"new_session","data":{"title":"<base> [mutation]"}}\n{"action":"disconnect"}\n' | olympix generate-mutation-tests -w . -p path1 -p path2 ... --agent`
- Record the session ID from `results_ready`, poll `olympix sessions --agent` until `Completed`/`Failed`, retrieve via `olympix mutation-testing --agent`, save to `olympix-results/mutation_test/`.
- Return: session ID, name, kill score (killed/total), status, output path.

**Unit agent** — prompt it to run the `unit-test` skill flow in full (coverage check, scaffold up to 10 templates, example tests, verify), then:
- Dispatch: `printf '{"action":"new_session","data":{"title":"<base> [unit]"}}\n{"action":"disconnect"}\n' | olympix generate-unit-tests -w . -p <paths> --agent` (do NOT send `confirm_all` — it is invalid after dispatch and can kill the job).
- Record the session ID, poll until `Completed`/`Failed`, retrieve via `olympix unit-testing --agent`, save to `olympix-results/unit_test/`.
- Return: session ID, name, coverage, test count, status, output path. If a repo-wide stack-too-deep blocks coverage, return that as the status instead of dispatching.

**BugPocer agent** (only if the user opted in) — prompt it to run the `bug-pocer` skill flow:
- Start the session through the FIFO driver, passing the name in `new_session`: `{"action":"new_session","data":{"title":"<base> [bugpocer]"}}`.
- Confirm scope + validation items; answer security questions from the repo per the bug-pocer skill's deterministic rule (do NOT blindly skip them); skip docs.
- Poll until `InitialScanCompleted` (BugPocer never reports `Completed`), retrieve findings via `connect-bp-session`, save to `olympix-results/bugpocer_pocs/`.
- Return: session ID, name, finding counts by severity/verdict, status, output path.

After dispatching, tell the user: which agents are running, the session names, and that they can keep chatting — you'll report as each finishes.

### Arm the heartbeat

Start a background heartbeat so you wake periodically even when nothing has changed:

```bash
# run_in_background: true
sleep 900
```

When this `sleep` completes it re-invokes you. Post a heartbeat (see protocol) and, if any agent is still running, arm another `sleep 900`. Stop arming once all agents have returned.

---

## Phase 3 — Monitoring protocol (while the user chats with you)

- **An agent finishes (or fails):** immediately relay a one-line result — tool, session name, key metric, where saved. On failure, capture the reason and continue; never abort the other agents.
- **The heartbeat `sleep` finishes:** post a status line per still-running agent in phase terms ("mutation: still running", "unit: done", "bugpocer: scanning"), then re-arm `sleep 900` if anything is still running.
- **The user asks "status":** summarize the latest known state of every agent from what you have.
- **All agents returned:** present the final summary (Step 6), then stop — do not arm another heartbeat.

### Reporting rules — DO NOT editorialize about time

- **Never state or imply an expected duration, and never call a long scan abnormal.** Scans routinely take much longer than any number you might guess. Do NOT say things like "running longer than typical (~17 min)", "this usually takes X minutes", "taking longer than expected", or "almost done". You have no basis for these and they are routinely wrong.
- Describe **phase/state only**: "still running", "scanning", "retrieving results", "done", "failed: <reason>". That is all the user needs.
- Polling cadence inside an agent is an internal mechanic — do not surface it or narrate per-poll.

---

## Step 6: Final Summary

Once every dispatched agent has returned:

```
## Olympix Full Run Summary

| Tool | Session (name / id) | Results | Status |
|------|---------------------|---------|--------|
| Static Analysis | — | {X} high, {Y} medium, {Z} low | Complete |
| Mutation Tests | {name} / {id} | {score}% kill score ({killed}/{total}) | Complete |
| Unit Tests | {name} / {id} | {coverage}% coverage, {passed} tests | Complete |
| BugPocer | {name} / {id or —} | {N} findings ({H} high, {M} medium, ...) | InitialScanCompleted / Skipped |
| Fuzz Tests | {name} / {id} | — | Started (check email) |
```

Tell the user:
- All results (except fuzz) are saved in `olympix-results/`
- Run `/olympix:assemble-report` to compile the final report
- Fuzz test results (if run) arrive via email

## Step 7: Fuzz Tests (optional, after the rest)

Ask the user if they want fuzz tests. If yes, from the same top-10 ranking take the top 3 and run (fuzz has **no** agent mode — results are email-only, so this is a quick foreground dispatch, not a background agent):

```bash
olympix generate-fuzz-tests -w . -p path1 -p path2 -p path3
```

Record the session ID; tell the user results arrive via email only.

## Important Notes

- **Setup is synchronous, tools are background.** Phase 1 (auth, build, ranking, static analysis, naming, opt-in) is done by you in the foreground; only the long-running tools fan out to background agents.
- **Dispatch the background agents in one message** so they run concurrently against separate backend sessions.
- **Name every session** and pass the title in `new_session` so the user can find them in the CLI later; always ask the user, suggesting a default.
- **Never claim or judge durations** — see the reporting rules above.
- **Don't stop on partial failure** — note a failed tool and continue with the others.
- **Fuzz tests are email-only** — they do NOT support `--agent`.

## Common Issues

| Problem | Solution |
|---------|----------|
| `--agent` flag rejected | CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe |
| One tool fails mid-run | Relay the failure, keep the other agents running — do not abort |
| Older CLI ignores the session name | Session naming in agent mode needs a current CLI; the run still works, the session just keeps the default name. Suggest `olympix update`. |
