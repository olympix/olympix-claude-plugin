---
name: bug-pocer
description: >
  Use when the user wants Olympix BugPocer security analysis run fully automated via
  agent mode — handles the entire flow: scope review, validation, security questions
  (incl. follow-ups), scan, findings retrieval with verdicts, Q&A, and built-in
  PDF + PoC export, all driven programmatically. Always asks the user up front
  whether to scan the full repo or only the diff vs a git ref (diff mode).
  TRIGGER: "bug pocer", "bugpocer", "security analysis", "run bug-pocer", "exploit generation", "bug-pocer", "diff mode", "diff scan", "scan the diff"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill, AskUserQuestion
---

# BugPocer Security Analysis

Run Olympix BugPocer on a Foundry- or Hardhat-based Solidity repository fully automated via agent mode. The entire flow — scope review, validation items, security questions, scan, findings retrieval, and Q&A — is driven programmatically through JSONL.

**What this tool does:** deep security analysis that attempts to **confirm** exploitability and produce proof-of-concept exploit code (PoCs) for real vulnerabilities — going beyond static analysis's *suspected* findings. Each finding carries a verdict (true/false positive) and, where confirmed, a runnable PoC. Heaviest and slowest tool; each new session incurs backend scan cost.

**Where it fits in the flow:** `Static Analysis → Unit Tests → Mutation Tests → BugPocer (you are here) → Report`. Run last — it is the most expensive and benefits from the context the earlier steps surface.

> **⛔ REQUIRED FIRST ACTION — do not skip:** before launching the CLI, you MUST ask the user whether to run a **full-repo scan** or a **diff scan** (only code changed vs a git ref). See [Step 1.5](#step-15-choose-scan-mode--full-repo-or-diff). The launch command in Step 2 differs based on the answer — launching without asking is a bug.
>
> **Exception — dispatched/background agent (e.g. from `full-run`):** if you are running as a background agent with no interactive user, do NOT ask anything. Use the scan mode handed to you by the caller (default: **full**), and never block on a question — a background agent has no user to prompt. The "ask the user" rule applies only to interactive runs.

## Prerequisites

- Foundry (`forge`) or Hardhat (`npx hardhat`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry or Hardhat project

## CLI Capability Check

This skill requires agent mode (`--agent`); older Olympix CLIs do not support it. Probe first:

```bash
if ! command -v olympix >/dev/null 2>&1 && [ ! -x "$HOME/.opix/bin/olympix" ]; then echo NOT_INSTALLED;
elif olympix bug-pocer --help 2>&1 | grep -q -- --agent; then echo AGENT_MODE; else echo LEGACY_CLI; fi
```

If `NOT_INSTALLED`, **HARD STOP** — tell the user to install the Olympix CLI from https://olympix.github.io/installation/ and rerun this skill.

If `LEGACY_CLI` (the `--agent` flag is rejected), the CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe. **HARD STOP** if the CLI still lacks `--agent`.

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication.

### Step 1: Verify Repository Builds

Read and follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md`.

### Step 1.5: Choose Scan Mode — Full Repo or Diff  ⛔ REQUIRED, ASK BEFORE STEP 2

**This is mandatory and easy to forget — do it before any CLI launch.** BugPocer can scan the **entire repo** or only the **code that changed** versus a git ref (diff mode — faster, focused on a branch/PR).

> **Skip this question entirely if you are a dispatched/background agent (no interactive user, e.g. from `full-run`):** use the scan mode the caller gave you (default **full**) and go straight to Step 2. Never call `AskUserQuestion` with no user — it blocks the whole run.

For interactive runs, **ask the user which they want** with `AskUserQuestion` (do not assume full; do not skip) before starting the session:

- **Full run** (default) — analyze all in-scope contracts.
- **Diff mode** — analyze only code changed versus a base git ref. Ask for the **base ref** (commit/branch/tag — e.g. `main`, `origin/main`, a commit SHA). Optionally a **target ref** (must be the currently checked-out commit / `HEAD`; defaults to the working tree).

This choice only changes the launch command in Step 2:

- Full run: `olympix bug-pocer -w . --agent`
- Diff mode: `olympix bug-pocer -w . --agent --diff-base <ref> [--diff-target <ref>]`

Add `--rebuild-context` (`-rc`) to either command to force a fresh context build and skip the `context_cache_review` prompt (Step 3b′) — the CLI reuses a cached context by default.

**Diff-mode behavior:**
- The diff defines scan scope — BugPocer analyzes only the changed code. The scope-review event still appears; the diff narrows what is ultimately analyzed.
- **An empty or unresolvable diff aborts the session** — if nothing changed versus the base, the CLI reports it and exits *before* scope review. Pick a base with real changes.
- `--diff-target` must be the checked-out `HEAD`. A dirty working tree is compared against the working tree (committed line numbers may shift); omit `--diff-target` to diff against the working tree.
- `--diff-target` without `--diff-base` is an error.

### Step 2: Start BugPocer Session

> **Checkpoint before launching (interactive runs only):** have you asked the user full-repo vs diff (Step 1.5)? If not, stop and ask now — the launch command below depends on the answer (diff mode appends `--diff-base`). **Dispatched/background agents skip this** — use the mode the caller passed (default full) and launch.

The BugPocer flow is stateful and interactive via stdin/stdout JSONL, and it must be driven across **multiple separate Bash calls** — you cannot hold one long-lived interactive process open inside a single tool call. Drive it with a background process whose stdin is a FIFO and whose stdout goes to a log file:

```bash
# 1. Create a FIFO for the CLI's stdin
rm -f .opix-bp-in && mkfifo .opix-bp-in
```

Then hold the FIFO's write end open so each per-action write does not deliver EOF to the CLI when the writer closes. **Launch the holder via a `run_in_background` Bash call** (or `nohup`/`setsid`) — a plain `&` job may be reaped when its foreground Bash call ends — and capture its PID to a file (job specs like `%1` do NOT survive across Bash calls):

```bash
# 2. Run this entire snippet in a run_in_background Bash call:
echo $$ > .opix-bp-holder.pid
exec sleep 3600 > .opix-bp-in
```

(`exec` keeps the holder on the recorded PID. Non-background equivalent: `nohup sh -c 'echo $$ > .opix-bp-holder.pid; exec sleep 3600 > .opix-bp-in' >/dev/null 2>&1 &`.)

Then start the CLI with another `run_in_background` Bash call, stdin attached to the FIFO, stdout redirected to a log:

```bash
olympix bug-pocer -w . --agent < .opix-bp-in > .opix-bp-events.log 2>&1
# Diff mode (per Step 1.5): append the diff flags —
# olympix bug-pocer -w . --agent --diff-base <ref> [--diff-target <ref>] < .opix-bp-in > .opix-bp-events.log 2>&1
```

Drive each exchange in its own Bash call:

```bash
# Read any NEW events since your last check (track the line count)
tail -n +<last_seen_line + 1> .opix-bp-events.log

# Liveness check BEFORE writing: holder alive AND the CLI background task still running
kill -0 "$(cat .opix-bp-holder.pid)" 2>/dev/null || echo "HOLDER GONE — relaunch it before writing"

# Send exactly one JSON action into the FIFO — ALWAYS via a 5s write watchdog:
# if the CLI has exited, a FIFO write blocks forever (no reader). Do NOT use
# `timeout` here — it does not exist on stock macOS; perl ships everywhere:
perl -e 'alarm 5; open(my $f, ">", ".opix-bp-in") or die "open failed: $!"; print $f "$ARGV[0]\n"' '{"action":"confirm_all"}'
```

(On Linux or where coreutils is installed, GNU `timeout` — `gtimeout` from `brew install coreutils` on macOS — is an equivalent watchdog: `timeout 5 sh -c 'printf '\''{"action":"confirm_all"}\n'\'' > .opix-bp-in'`.)

**Before each write**, check the log for new events and confirm the CLI is still running (the background CLI task has not exited / the log does not end in a terminal `error` or completion event). If the watchdog write times out (perl exits with status 142 after ~5s), the CLI is gone — read the log to see why instead of retrying the write.

Repeat: read new events from the log → decide → write the next action into the FIFO.

**300-second input timeout:** the CLI waits at most **300 seconds** for each stdin answer. If you exceed it between answers, the CLI emits `{"event":"error","data":{"message":"Timeout waiting for input"}}`. Newer CLIs re-emit the pending event on timeout instead of aborting, but do not rely on that — stay under 300s per answer.

**Cleanup:** when the flow ends (`validation_submitted` or after `disconnect`), kill the holder by PID and remove the FIFO:

```bash
kill "$(cat .opix-bp-holder.pid)" 2>/dev/null
rm -f .opix-bp-in .opix-bp-holder.pid
```

(Use the PID file — job specs like `%1` don't survive across Bash calls.)

### Step 3: New Session Flow

Before driving the flow, **name the session** so the user can find it later in `olympix` (`olympix sessions`, the TUI session lists). Pick a suggested default from the repo identity:

```bash
# Portable repo identity — NO `sed -E`: BSD/macOS sed rejects the non-greedy `+?`
# with "RE error: repetition-operator operand invalid". Use POSIX parameter expansion.
url=$(git remote get-url origin 2>/dev/null); url=${url%.git}; org_repo=""
short_sha=$(git rev-parse --short HEAD 2>/dev/null)
if [ -n "$url" ]; then repo=${url##*/}; rest=${url%/*}; org=${rest##*[:/]}; org_repo="$org/$repo"; fi
if [ -n "$org_repo" ] && [ -n "$short_sha" ]; then echo "${org_repo}@${short_sha}"; else basename "$(pwd)"; fi
```

**Ask the user to confirm or change it**, presenting the suggested default (use `AskUserQuestion` with the suggested default as the first option, or a plain prompt that states the suggestion). The user may accept the suggestion or supply their own. Record the confirmed name as `{SESSION_TITLE}` and pass it in the `new_session` action's `data.title` below.

> **Dispatched/background agent (e.g. from `full-run`):** do NOT ask — you have no user to prompt (same rule as the scan-mode question in Step 1.5). Use the session name passed to you **verbatim** as `{SESSION_TITLE}`. Never call `AskUserQuestion`; it blocks the whole run.

The flow proceeds through these stages:

#### 3a. Sessions List
First event is `sessions_list` showing existing sessions.
```json
{"event":"sessions_list","data":{"sessions":[...]},"actions":["new_session","connect_session","disconnect"]}
```

Send `new_session` (carrying the confirmed title) to start a new session, or `connect_session` with a session ID to reconnect:
```json
{"action":"new_session","data":{"title":"{SESSION_TITLE}"}}
```

#### 3b′. Context Cache Review (conditional)
Emitted **only** when a prior validated context for this exact or similar codebase exists (a previous scan of this repo persisted one). It arrives after `new_session`, before scope review. If no cache exists, this event is skipped.
```json
{"event":"context_cache_review","data":{"match_type":"exact","source_session_id":"<uuid>","cached_at":"2026-07-01T12:00:00Z","overlap_percent":92.5,"changed_files":["src/Vault.sol"],"summary":{"project_type":"Lending","description":"...","patterns":8,"invariants":12,"security_assumptions":5}},"actions":["reuse_context","rebuild_context","disconnect"]}
```

- `match_type` is `"exact"` (identical file fingerprint) or `"partial"` (`overlap_percent` / `changed_files` populated for partial only).
- Send `reuse_context` (default — faster, cheaper, reuses the already-validated context) or `rebuild_context` (force a fresh build, e.g. after a major refactor the fingerprint didn't catch).
```json
{"action":"reuse_context"}
```
- **Dispatched/background agents: send `reuse_context` and never block** (same non-blocking rule as Steps 1.5 / 3 / 10). If the driver ignores the event or stdin closes, the CLI defaults to reuse — the pre-existing behavior.
- To decide at launch instead, pass `--rebuild-context` on the launch command (Step 1.5); it forces a rebuild and this event is not emitted.

#### 3b. Scope Review
```json
{"event":"scope_review","data":{"contracts":[{"name":"Vault","file":"src/Vault.sol","functions":[{"name":"deposit","visibility":"public"}]}],"libraries":[...]},"actions":["select_scope","confirm_all","disconnect"]}
```

The `data` payload has only `contracts` and `libraries` (there is no top-level `functions` array) — functions are nested per contract/library as `{name, file, functions: [{name, visibility}]}`.

Send `confirm_all` to include everything, or `select_scope` with exclusions:
```json
{"action":"select_scope","data":{"exclude_contracts":["ContractA"]}}
```

#### 3c. Build Check (conditional)
If the server's build check failed for the uploaded repo, this arrives BEFORE validation items:
```json
{"event":"build_check_failed","data":{"session_id":"<uuid>","build_command":"forge build","error_excerpt":"..."},"actions":["continue","kill_session","disconnect"]}
```

A failing build degrades scan quality and PoC generation. If the failure looks fixable (missing
remappings, stale lockfile), prefer `kill_session`, fix the build locally, and start a new session.
Send `continue` only when the user wants to proceed anyway. `kill_session` is acknowledged by a
`session_killed` event, after which the CLI exits. This event does not appear when the build check
passed.

#### 3d. Validation Items
After scope confirmation, a `progress` event announces the session ID, then validation items arrive one at a time:
```json
{"event":"validation_item","data":{"key":"...","name":"...","confidence":70,"content":"...","current":1,"total":11},"actions":["confirm_item","reject_item","select_option","disconnect"]}
```

For each item, send `confirm_item` to accept or `reject_item` to reject.

#### 3e. Security Questions

**Do NOT blindly skip these.** They calibrate the scan. Answer each from the repo you already
read — **both the code AND its documentation**: contracts, roles, external integrations,
upgradeability, economic assumptions, *plus* the repo's own `CLAUDE.md`/`AGENTS.md`, `README`,
anything under `docs/`, a whitepaper if present, and inline NatSpec. If you have not read those
docs yet, read them before answering — they state design intent the code alone does not.

**Trust-model / governance / access-control questions especially:** the documentation defines
the intended trust model; the code does not. A role that in code "can do X immediately with no
timelock" is **not** automatically untrusted. If the docs describe the owner/governance/guardian
as trusted (e.g. `Ownable2Step`, a multisig, a timelock, "intentionally small / trusted
governance"), answer **trusted**. Only mark such a role untrusted when the docs say so. When docs
and code conflict on *intent*, the docs' stated trust model wins — do NOT answer "identity not
finalized / not evidenced in the repo" for a role the docs describe as trusted (that mislabels
design intent as a finding). **If code and docs together still do not determine a role's trust
level, do NOT guess and do NOT default to untrusted — escalate to the user** via `AskUserQuestion`
(rule 3 below). A dispatched/background agent has no user, so it falls back per the
background-agent note instead.

After all validation items, security questions arrive one at a time:
```json
{"event":"security_question","data":{"question_id":"...","category":"AccessControl","question_text":"...","suggested_answers":[{"id":"a1","label":"...","value":"...","show_follow_up_ids":["f1"]}],"is_follow_up":false,"parent_question_id":null,"current":1,"total":13},"actions":["select_answer","custom_answer","skip_question","disconnect"]}
```

Deterministic answering rule, in order:
1. If a `suggested_answers` option matches what the code **and docs** show → `select_answer` with `{"answer_id":"<id>"}`.
2. Else if you know the answer from the code **or docs** but no option fits → `custom_answer` with `{"answer":"<text>"}`.
3. Else — the repo genuinely does not determine it — **ask the user** via `AskUserQuestion`, then answer the CLI from their reply. Do this for **every** unknown, required or not. Do NOT `skip_question` just because the code is silent. See "Escalating unknowns" below.

**Escalating unknowns to the user:** put the `question_text` as the `AskUserQuestion` question and map each `suggested_answers` entry to an option (option label = its `label`); the user can also pick "Other" to supply free text. Translate their reply back to a CLI action — `select_answer` `{"answer_id":"<id>"}` if they chose a suggested option, else `custom_answer` `{"answer":"<their text>"}`. **Write that action immediately after they reply:** the CLI's 300s stdin timeout (Step 2) keeps ticking while you wait on the user — a single ask left unanswered past 300s makes the CLI emit `{"event":"error","data":{"message":"Timeout waiting for input"}}`. When several unknowns arrive close together, batch up to 4 into one `AskUserQuestion` call to cut round-trips, but each pending CLI question must still be answered inside its own 300s window.

> **Dispatched/background agent (e.g. from `full-run`):** do NOT ask — there is no user to prompt (same rule as Steps 1.5, 3, 10). Fall back to the old behavior: `skip_question` when the repo does not determine it and `is_required` is false; otherwise `custom_answer` with your best read of the code **and the repo's docs** (the trust-model/documentation-precedence rule above applies here too — a role the docs describe as trusted is trusted). Never call `AskUserQuestion`; it blocks the whole run.

**Follow-up questions (`is_follow_up: true`):** selecting an answer whose `show_follow_up_ids` is
non-empty causes the CLI to emit one or more follow-up `security_question` events (linked by
`parent_question_id`) BEFORE the next top-level question. Answer them the same way — same actions.
Do not treat a follow-up as the next top-level question; `current`/`total` reset to the follow-up batch.

#### 3f. Additional Documentation
```json
{"event":"additional_docs_prompt","actions":["submit_docs","skip_docs","disconnect"]}
```

Send `skip_docs` or `submit_docs` with notes/links:
```json
{"action":"submit_docs","data":{"notes":"Token uses rebasing","links":["https://docs.example.com"]}}
```

#### 3g. Submission
```json
{"event":"validation_submitted","data":{"session_id":"<uuid>"}}
```

CLI exits with code 0. The backend scan starts processing.

### Step 4: Wait for Scan Completion (poll in the foreground)

The scan runs **asynchronously** on the backend — once `validation_submitted` arrives the bug-pocer
CLI has already exited, so do NOT hold that subprocess open waiting for an answer. You poll separately
with `olympix sessions --agent`.

**Poll using the exact loop in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/poll-session.md` — do NOT write your own.** Set `SESSION_ID` to the recorded id and `ARRAY_KEY="bug_pocer"`. The loop matches on `id`, reads `status`, and breaks on `InitialScanCompleted` (BugPocer never reports `Completed`) or `Killed`, using plain string equality (a hand-rolled `case "$ST"` with escaped quotes never matches and hangs the run for ~1 hour).

Each call to that loop blocks ~7 min in the **foreground** and prints the status; if it is not
terminal, run the same call again (the loop file explains the re-run rule, and the one main-loop-only
exception for keeping a direct user's chat free). Do NOT background the loop and re-read its log every
few seconds — that spins and spams "still running" — and do not narrate each poll. Do not tell the
user how long it should take or call a long scan abnormal — scans routinely take much longer than expected.

### Step 5: Retrieve Findings

Reconnect to the completed session. If you only need the findings, a one-shot pipe is enough:

```bash
printf '{"action":"disconnect"}\n' \
  | olympix connect-bp-session -s <session-id> -w <workspace-path> --agent
```

Or via the `bug-pocer` command:
```bash
printf '{"action":"connect_session","data":{"session_id":"<id>"}}\n{"action":"disconnect"}\n' \
  | olympix bug-pocer -w <path> --agent
```

If you intend to continue with Q&A, PDF export, or PoC export (Steps 6-8), reconnect using the **FIFO driver from Step 2** instead (`olympix connect-bp-session -s <id> -w . --agent < .opix-bp-in > .opix-bp-events.log 2>&1`), so you can keep sending actions interactively.

**Expected output:**
```
{"event":"progress","data":{"message":"Connected to session <id>. Fetching findings..."}}
{"event":"findings_ready","data":{"session_id":"<id>","findings":[...]},"actions":["ask_question","generate_pdf","save_pocs","save_findings_md","disconnect"]}
```

Each finding carries:

| Field | Meaning |
|-------|---------|
| `id`, `title`, `severity`, `description`, `file_path`, `line_number` | finding basics |
| `affected_code` | the PoC/exploit code excerpt |
| `bugpocer_verdict` | BugPocer's automated call: `true_positive` / `false_positive` |
| `user_verdict` | the human reviewer's override: `true_positive` / `false_positive` / `unreviewed` |
| `user_verdict_reason` | text reason if a human set a verdict (else null) |
| `effective_verdict` | `user_verdict` if set, else `bugpocer_verdict` — use this as the final call |
| `confidence_score` | BugPocer confidence (int) |
| `poc_summary`, `poc_content` | PoC summary + full exploit source |

Findings auto-persist to `.opix/agent/<session-id>/findings.json`.

**Artifact files download automatically on retrieval (default behavior).** As soon as `findings_ready`
arrives, the CLI writes — using the CLI default filter (true positives + unverified; false positives
excluded) — the local artifact files to disk and emits `pocs_saved` + `findings_saved` events:
- **PoC exploit code**, one file per finding, under `pocs_<session-id>/` (real PoC code, not the summary).
- **Split markdown reports**: `true_positives_<id>_<ts>.md` and `unverified_<id>_<ts>.md` in the working directory.

No action is needed to get these — they are on disk after `findings_ready`. The `save_pocs` and
`save_findings_md` actions (Steps 8 / 8.5) remain available only to **re-export** them. The PDF
(Step 7) is NOT auto-generated — it is a heavier backend call, so request it explicitly when wanted.

### Step 6: Q&A Loop (Optional)

After receiving findings, ask questions about them:

```json
{"action":"ask_question","data":{"question":"What is the most critical finding?"}}
```

Flow: `progress` "Question sent" → `qa_waiting` → `question_answered` with `answer` field. Wait for
`question_answered` using the recipe in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/wait-for-event.md`
(`WANT='"event":"question_answered"'`, foreground, re-run on `WAIT_TIMEOUT`; do NOT background it).

After `question_answered`, the valid actions are only `ask_question`, `fetch_findings`, and `disconnect` — `generate_pdf` and `save_pocs` are NOT accepted here; send `fetch_findings` to re-enter `findings_ready` first, then export.

Q&A exchanges auto-persist to `.opix/agent/<session-id>/qa.json`.

Send `disconnect` when done.

**Reporting verdicts (TP/FP):** answer from the verdict fields, and ALWAYS distinguish the two sources:
- "BugPocer verdict" = `bugpocer_verdict`.
- "User verdict" = `user_verdict` (`unreviewed` means no human has reviewed it yet).
- **Never answer "none" just because `user_verdict` is `unreviewed`.** If asked "what were the TP/FPs",
  report by `effective_verdict`, and state explicitly whether each is a human verdict or BugPocer's
  unreviewed call. Example: "3 TP / 2 FP per BugPocer (unreviewed); 0 reviewed by a user."

### Step 7: Export PDF report (built-in)

Use BugPocer's own PDF generator instead of hand-rolling one. After `findings_ready`, send:

```json
{"action":"generate_pdf"}
```

Then wait for the result with the exact recipe in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/wait-for-event.md`,
setting `WANT='"event":"pdf_generated"'` — a bounded FOREGROUND wait, re-run on `WAIT_TIMEOUT`; do NOT
background it or hand-roll a wait (PDF generation is heavy and slow, so it may take several windows).
Success event: `{"event":"pdf_generated","data":{"session_id":"<id>","pdf_path":"<abs-path>"}}`.
On `WAIT_ERROR` (an `error` event) report it and continue. Move/copy the file into `olympix-results/` if desired.

### Step 8: Re-export PoCs (built-in, optional)

PoCs are already written automatically on retrieval (see Step 5). Use this action only to **re-export**
them. Export every finding's proof-of-concept to disk via the built-in exporter. Send:

```json
{"action":"save_pocs"}
```

Then wait with the `${CLAUDE_PLUGIN_ROOT}/skills/_shared/wait-for-event.md` recipe, `WANT='"event":"pocs_saved"'`
(foreground, re-run on `WAIT_TIMEOUT`; never background). Success event:
`{"event":"pocs_saved","data":{"session_id":"<id>","saved_count":N,"output_path":"<dir>"}}`.
This writes one PoC file per finding (named by unit + vulnerability). Report the count and path.

PoC export applies the **CLI default filter** (true positives + unverified, all severities; false
positives excluded) — same selection as the TUI's "Save PoCs" default.

### Step 8.5: Re-export split findings markdown (built-in, optional)

The split markdown reports (`true_positives_<id>_<ts>.md`, `unverified_<id>_<ts>.md`) are already
written automatically on retrieval (see Step 5). Use this action only to **re-export** them — the
same files the TUI's "Save Findings md" produces, using the same CLI default filter (true positives +
unverified; false positives excluded). Send:

```json
{"action":"save_findings_md"}
```

Then wait with the `${CLAUDE_PLUGIN_ROOT}/skills/_shared/wait-for-event.md` recipe, `WANT='"event":"findings_saved"'`
(foreground, re-run on `WAIT_TIMEOUT`; never background). Success event:
`{"event":"findings_saved","data":{"session_id":"<id>","files":[{"category":"True Positives","count":N,"path":"<abs-path>"},...]}}`.
On `WAIT_ERROR` (e.g. no findings match the default filter) report it and continue.
Move/copy the files into `olympix-results/` if desired.

### Step 9: Save Results

Also persist a human-readable summary to `olympix-results/bugpocer_pocs/findings.md` (this exact path — the `assemble-report` skill reads it):

```markdown
# BugPocer Findings

**Session ID:** {id}
**Total Findings:** {count}

## [Severity] Finding Title

- **File:** {file_path}:{line_number}
- **Verdict:** {effective_verdict}  (BugPocer: {bugpocer_verdict} · User: {user_verdict})
- **Confidence:** {confidence_score}
- **Description:** {description}
- **PoC:** {poc_summary}

---
(repeat for each finding, ordered by severity)
```

### Step 10: Report to User

Tell the user:
- How many findings by severity AND by verdict (BugPocer vs user-reviewed)
- Highlight Critical and High findings with brief descriptions
- PDF saved at `pdf_path`; PoCs saved at `output_path`; summary in `olympix-results/bugpocer_pocs/`

Then **proactively offer to triage the findings** (use `AskUserQuestion`) — this is the standard closing step after every tool run:

- **"Yes, triage them"** — for each finding (start with Critical/High), open `file_path:line_number`, read the source against the PoC, and confirm or challenge the `effective_verdict` (true vs false positive) with a one-line reason. Prioritize what to fix first. You can also drive the built-in Q&A loop (Step 6) for deeper questions.
- **"No, just the findings"** — stop; the saved report + PoCs are the deliverable.

Make this offer every run.

> **Dispatched/background agent (e.g. from `full-run`):** do NOT make this offer — you have no user to prompt and it would block. Just return your results to the orchestrator; it offers triage to the user once you report back.

## Important Notes

- **Session naming:** Always name the session and ask the user to confirm or change it, suggesting a sensible default (repo identity `<org>/<repo>@<short-sha>` from git, falling back to the repo folder name). Pass the confirmed name in the `new_session` action's `data.title`. Older CLIs ignore the title and keep the default name (`<org>/<repo>@<short-sha>` or a timestamp) — if naming has no effect, suggest `olympix update`.
- **Never state or imply an expected scan duration**, and never call a long scan abnormal (e.g. "running longer than typical (~17 min)"). Report phase/state only — "still running", "scanning", "done", "failed".
- **Cost warning:** Each new BugPocer session triggers LLM calls on the backend. Avoid creating unnecessary sessions.
- **Cross-mode safety:** After agent-mode submission, `pending_validation_payload` is NULL in the database — no stale state for TUI mode.
- **Reconnecting:** Use `connect-bp-session -s <id>` or `bug-pocer` → `connect_session` action to reconnect to any existing session.
- **Killing a session:** `olympix kill-bp-session -s <session-id> --agent` emits
  `{"event":"session_killed","data":{"session_id":"<id>","was_running":true|false}}` and exits —
  `was_running: false` means the session was not running or had already completed.
- **Killed sessions:** Reconnecting to a Killed session does NOT return findings. The CLI emits an `error` event — `"Failed to retrieve session data. Session may be Killed or inaccessible."` — and exits, or times out with `"Timed out connecting to session '<id>'. Session may be Killed, expired, or unreachable."`. Report this to the user instead of retrying.
- **PDF/PoC export are post-findings actions:** `generate_pdf` and `save_pocs` are only valid after a
  `findings_ready` event (i.e. on a completed session). They re-emit the same action set so you can chain them.
- **Verdicts are two independent fields:** `bugpocer_verdict` (automated) and `user_verdict` (human override,
  `unreviewed` until set). Always report both; collapse to `effective_verdict` only for a single final call.
- **Security questions are not optional noise:** answer them from the repo. When the repo is silent, ask the user (interactive runs) rather than skipping — skipping degrades scan quality. Background/dispatched agents have no user, so they skip non-required unknowns instead.

## Common Issues

| Problem | Solution |
|---------|----------|
| `--agent` flag rejected | CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe |
| `Timeout waiting for input` error | You exceeded the 300s stdin timeout between answers — reconnect and answer faster |
| CLI exits as soon as you echo an action | The FIFO write end closed (EOF) — make sure the `sleep 3600 > .opix-bp-in` holder is still running (`kill -0 "$(cat .opix-bp-holder.pid)"`); relaunch it via `run_in_background` if it was reaped |
| A FIFO write hangs / times out | The CLI exited (no reader on the FIFO) — that's why every write goes through the 5s watchdog (`perl -e 'alarm 5; open(my $f, ">", ".opix-bp-in") or die; print $f "$ARGV[0]\n"' '{"action":"..."}'`, or GNU `timeout 5` on Linux/brew); read `.opix-bp-events.log` to see why the CLI stopped |
| Reconnect errors with "Session may be Killed..." | The session is Killed/expired — start a new session; do not retry the reconnect |
| Diff mode exits before scope review | Empty/unresolvable diff — nothing changed vs `--diff-base`, or the ref is invalid. Pick a base ref with real changes, or run full mode |
| `--diff-target requires --diff-base` | You passed `--diff-target` alone — supply `--diff-base <ref>` too, or drop `--diff-target` to diff against the working tree |
