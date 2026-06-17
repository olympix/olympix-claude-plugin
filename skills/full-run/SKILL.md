---
name: full-run
description: >
  Use when the user wants a full Olympix security analysis — static analysis,
  unit tests, mutation tests, and BugPocer. The long-running
  tools run as BACKGROUND agents so the user can keep chatting with you while they
  run; you report as each finishes plus a periodic heartbeat.
  TRIGGER: "full run", "full-run", "run everything", "full scan", "run all tools"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill, Agent, AskUserQuestion
---

# Full Run (background)

`full-run` is the **orchestrator** — it does not contain tool logic of its own. It runs the fast setup once, then drives each underlying tool skill (`static-analysis`, `unit-test`, `mutation-test`, `bug-pocer`) in the right order, dispatching the long-running ones as **background agents** so the user can keep talking to you while the scans run. You stay free to chat, relay updates as each tool finishes, and post a periodic heartbeat.

## The tools, and what each one does

Present this plainly to the user whenever you ask which tools to run — do NOT use internal jargon ("kill score", "agent dispatch") without explaining it.

```
  Static Analysis  →   Unit Tests   →  Mutation Tests  →   BugPocer    →   Report
  ───────────────      ──────────       ────────────       ─────────       ──────
  find suspected       generate         measure how        deep scan →     assemble
  vulnerabilities      tests + raise    well tests catch    confirmed       all results
  (100+ detectors)     code coverage    real bugs           exploits/PoCs   into a report
  seconds, sync        async job        async job           async job
```

- **Static Analysis** — fast scanner (100+ detectors: reentrancy, access control, arithmetic…). Flags *suspected* issues in seconds. Cheapest, run first.
- **Unit Tests** — generates Foundry/Hardhat unit tests for the most critical contracts and reports the coverage gained.
- **Mutation Tests** — injects small bugs ("mutants") into the code and checks whether the test suite catches them. The **kill score** = % of injected bugs the tests caught; a low score means weak tests.
- **BugPocer** — deep security analysis that attempts to **confirm** exploitability and produce proof-of-concept exploits. Heaviest and slowest; incurs backend scan cost.

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

Identify the top 10 most critical contracts (read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/contract-selection.md`). Reuse this ranking for unit tests and mutation tests — do NOT re-analyze per tool.

### Step 3: Run Static Analysis (fast, synchronous)

```bash
olympix analyze -w . --agent
```

Parse the `findings_ready` event, write `olympix-results/olympix-static.md`, and report the counts to the user immediately — this is their first result and arrives in seconds. Drop the verdict-noise fields silently (no "verdict"/BugPocer talk in static output — see the `static-analysis` skill). Then **offer to triage the static findings** against the source: you can do this while the background agents (dispatched next) run, so it costs the user no extra wait.

### Step 4: Choose a Session Name

Sessions you start are named so the user can find them later in `olympix` (TUI session lists, `olympix sessions`). Pick a base name and **ask the user to confirm or change it, suggesting a sensible default** (use the repo identity, e.g. `<org>/<repo>@<short-sha>` from git, or the repo folder name). Use AskUserQuestion with the suggested default as the first option.

Derive a distinguishable per-tool name from the confirmed base:
- mutation → `<base> [mutation]`
- unit → `<base> [unit]`
- bugpocer → `<base> [bugpocer]`

These titles are passed to each tool's `new_session` (see below) so each session is identifiable in the CLI.

### Step 5: BugPocer opt-in (and scan mode)

Ask the user with AskUserQuestion whether to run BugPocer (options: "Yes, run it" / "Skip for now"), noting it incurs backend scan cost. Record the choice for Phase 2.

**If they opt in, ask the scan mode now too** (full-repo vs diff) with AskUserQuestion, and if diff, the base ref — because the background BugPocer agent has no user to prompt. Decide it here while the user is present and pass the answer to the agent. Default: **full**. Record `{BUGPOCER_SCAN_MODE}` (full, or `diff --diff-base <ref>`).

---

## Phase 2 — Dispatch background agents

Launch one background agent per long-running tool with the `Agent` tool, `run_in_background: true`, `subagent_type: general-purpose`. Each agent owns its tool end-to-end (dispatch → poll → retrieve → save) and returns a structured result.

> **⛔ ALL agents dispatch in ONE message, simultaneously, in the background.** Put every `Agent` call (mutation, unit, and BugPocer if opted in) in a **single response** with `run_in_background: true`. Do NOT run any tool's flow in the foreground. Do NOT wait for one agent before dispatching the next. **In particular, BugPocer's interactive setup (scope → validation → security questions → submit) runs INSIDE its own background agent — never drive it from the main loop.** The whole point: the user keeps chatting with you while all tools run concurrently. If you find yourself "waiting for BugPocer" before the others start, you've done it wrong — fan them all out at once.

Pass each agent: the absolute repo path, the ranked contract list, and its session name. **Tell each agent to USE the session name you provide verbatim and NOT to ask for a name** — the user has already confirmed it here, and a background agent has no user to prompt.

> **Background agents must NEVER call `AskUserQuestion` — for anything.** They have no user. That means: do not ask for a session name (use the one passed), do not ask BugPocer scan mode (use `{BUGPOCER_SCAN_MODE}`), and do **not** make the end-of-run "offer to triage" that each tool skill describes — triage is the orchestrator's job here (Phase 3), done once the agent reports back. The agent's only output is its structured result.

**Mutation agent** — prompt it to run the `mutation-test` skill flow. **Skip its Steps 0–2 (auth, build, ranking) — Phase 1 already did them; use the ranked contract list passed to you, do not re-rank. Do not offer triage at the end — just return results.**
- Dispatch: `printf '{"action":"new_session","data":{"title":"<base> [mutation]"}}\n{"action":"disconnect"}\n' | olympix generate-mutation-tests -w . -p path1 -p path2 ... --agent`
- Record the session ID from `results_ready`, poll `olympix sessions --agent` until `Completed`/`Failed`, retrieve via `olympix mutation-testing --agent`, save to `olympix-results/mutation_test/`.
- Return: session ID, name, kill score (killed/total), status, output path.

**Unit agent** — prompt it to run the `unit-test` skill flow (skip auth — Phase 1 did it; use the ranked contract list passed to you; do not offer triage at the end). It still does the local scaffolding work: coverage check, scaffold up to 10 templates, example tests, verify. Then:
- Dispatch: `printf '{"action":"new_session","data":{"title":"<base> [unit]"}}\n{"action":"disconnect"}\n' | olympix generate-unit-tests -w . -p <paths> --agent` (do NOT send `confirm_all` — it is invalid after dispatch and can kill the job).
- Record the session ID, poll until `Completed`/`Failed`, retrieve via `olympix unit-testing --agent`, save to `olympix-results/unit_test/`.
- Return: session ID, name, coverage, test count, status, output path. If a repo-wide stack-too-deep blocks coverage, return that as the status instead of dispatching.

**BugPocer agent** (only if the user opted in) — prompt it to run the `bug-pocer` skill flow:
- **Run FULLY NON-INTERACTIVELY — you are a background agent with NO user. Do NOT call `AskUserQuestion` for anything (scan mode, session name, scope, docs). Use the scan mode passed to you (`{BUGPOCER_SCAN_MODE}`, default full) and the session name verbatim. Never block on a question.** The bug-pocer skill's "ask full-vs-diff" gate explicitly exempts dispatched/background agents — skip it.
- Start the session through the FIFO driver, passing the name in `new_session`: `{"action":"new_session","data":{"title":"<base> [bugpocer]"}}`. For diff mode, append `--diff-base <ref>` to the launch command per `{BUGPOCER_SCAN_MODE}`.
- Confirm scope + validation items; answer security questions from the repo per the bug-pocer skill's deterministic rule (do NOT blindly skip them); skip docs — all without prompting any user.
- Poll until `InitialScanCompleted` (BugPocer never reports `Completed`), retrieve findings via `connect-bp-session` (PoCs + split markdown download automatically on retrieval), save to `olympix-results/bugpocer_pocs/`.
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

- **An agent finishes (or fails):** immediately relay a one-line result — tool, session name, key metric, where saved. On failure, capture the reason and continue; never abort the other agents. Then **offer to triage that tool's results** (the standard closing step every tool does on its own): static → findings vs source, unit → coverage gaps, mutation → surviving mutants, BugPocer → verdicts vs source. The saved files in `olympix-results/` are enough to triage without re-running anything — and you can triage one tool while others are still running.
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
| Unit Tests | {name} / {id} | {coverage}% coverage, {passed} tests | Complete |
| Mutation Tests | {name} / {id} | {score}% kill score ({killed}/{total}) | Complete |
| BugPocer | {name} / {id or —} | {N} findings ({H} high, {M} medium, ...) | InitialScanCompleted / Skipped |
```

Tell the user:
- All results are saved in `olympix-results/`
- Run `/olympix:assemble-report` to compile the final report

## Important Notes

- **Setup is synchronous, tools are background.** Phase 1 (auth, build, ranking, static analysis, naming, opt-in) is done by you in the foreground; only the long-running tools fan out to background agents.
- **Dispatch the background agents in one message** so they run concurrently against separate backend sessions.
- **Name every session** and pass the title in `new_session` so the user can find them in the CLI later; always ask the user, suggesting a default.
- **Never claim or judge durations** — see the reporting rules above.
- **Don't stop on partial failure** — note a failed tool and continue with the others.

## Common Issues

| Problem | Solution |
|---------|----------|
| `--agent` flag rejected | CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe |
| One tool fails mid-run | Relay the failure, keep the other agents running — do not abort |
| Older CLI ignores the session name | Session naming in agent mode needs a current CLI; the run still works, the session just keeps the default name. Suggest `olympix update`. |
