---
name: fuzz-test
description: >
  Use when the user wants Olympix fuzz test generation run on a Foundry- or Hardhat-based
  Solidity repo via agent mode — verifies the repo builds, selects the most critical
  contracts, dispatches the fuzz job, waits for completion, then reconnects to retrieve
  the results summary, the generated test files and (optionally) a PDF report. Can also stop
  a running fuzz session.
  TRIGGER: "fuzz tests", "fuzz test", "generate fuzz tests", "fuzzing", "fuzz-test",
  "kill fuzz session", "stop fuzz", "cancel fuzz"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill, AskUserQuestion
---

# Fuzz Test Generation

Run Olympix fuzz test generation on a Foundry- or Hardhat-based Solidity repository using agent mode: verify the repo builds, select the most critical contracts, dispatch the job, wait for completion, then reconnect to retrieve results and the generated test files.

**What this tool does:** explores contract behavior with generated sequences of function calls (guided by symbolic execution and attack strategies such as reentrancy, forced-revert DoS, and AMM spot-price manipulation) to find inputs and call orderings that break invariants or trigger exploits. Unlike mutation testing (which scores *your* tests), fuzzing hunts for *bugs* in the contract itself.

**Where it fits in the flow:** `Static Analysis → Unit Tests → Mutation Tests → Fuzz Tests (you are here) → BugPocer → Report`. Fuzzing is compute-heavy, so it runs as a dispatch-and-reconnect job, not synchronously.

## Prerequisites

- Foundry (`forge`) or Hardhat (`npx hardhat`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry or Hardhat project

## CLI Capability Check

Fuzz agent mode requires a recent CLI. Do **not** probe with `--help | grep -- --agent` — the `--agent` flag is printed for every command even on CLIs that do not support fuzz agent mode. Probe for the fuzz-session commands instead, which only exist on capable builds:

```bash
if ! command -v olympix >/dev/null 2>&1 && [ ! -x "$HOME/.opix/bin/olympix" ]; then echo NOT_INSTALLED;
elif olympix kill-fuzz-session --help >/dev/null 2>&1; then echo AGENT_MODE_WITH_KILL;
elif olympix connect-fuzz-session --help >/dev/null 2>&1; then echo AGENT_MODE; else echo LEGACY_CLI; fi
```

If `NOT_INSTALLED`, **HARD STOP** — tell the user to install the Olympix CLI from https://olympix.github.io/installation/ and rerun this skill.

If `LEGACY_CLI` (no `connect-fuzz-session` command), the CLI predates fuzz agent mode — tell the user to run `olympix update`, then re-probe. **HARD STOP** if it still lacks the command.

If `AGENT_MODE` (no `kill-fuzz-session` command), everything in this skill works **except** "Stopping a Run" below — that CLI cannot kill a dispatched run. Continue normally; only mention `olympix update` if the user asks to stop one.

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication.

### Step 1: Verify Repository Builds

Read and follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md`.

**If it fails:** initialize the repo per the README. **HARD STOP** if `forge build` cannot be made to pass.

**NOTE:** `forge test --via-ir` is NOT required. The Olympix CLI handles viaIR compilation server-side. You only need basic `forge build` to pass locally.

### Step 2: Identify the Most Critical Contracts

Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/contract-selection.md` for the full criteria.

Select the **top 3** most critical contracts. Fuzzing is compute-heavy per contract (it explores many call sequences), so the plugin default is 3 — fewer than the 10 used for mutation/unit tests. List the selected contracts with their file paths relative to the repo root before proceeding. The user may ask for more or fewer.

### Step 3: Dispatch the Fuzz Job

Fuzzing dispatches directly from the `-p` file arguments — there is **no** `new_session` / `select_files` handshake and no stdin session title (fuzz sessions are auto-named from the repo). Pipe a single `disconnect` so stdin closes cleanly after dispatch:

```bash
printf '{"action":"disconnect"}\n' \
  | olympix generate-fuzz-tests -w . -p src/Contract1.sol -p src/Contract2.sol -p src/Contract3.sol --agent
```

**Expected JSONL output:**
```
{"event":"progress","data":{"message":"Fuzz test generation started. Session <uuid>. ..."}}
{"event":"completed","data":{"type":"fuzz_test","session_id":"<uuid>","message":"Fuzz generation started; results pending."}}
```

Record the **session_id** from the `completed` event (`data.session_id`).

**Options:**
- `--agent` — agent mode, JSONL stdin/stdout (required for this skill)
- `-w .` — workspace directory (paths resolve relative to this)
- `-p <path>` — contract file to fuzz (repeat once per contract; use the **file path**, not the contract name, relative to `-w`)
- `-cm path|branch` — coverage mode: `path` explores every branch combination; `branch` covers all branches with the fewest paths (optional)
- `-cl <n>` — chain length: sequential calls per exploration (default 2; higher = deeper but much slower) (optional)
- `--no-<strategy>` — disable a specific attack strategy (optional)

**If the account is not entitled to fuzzing:** the CLI emits a terminal error event and exits — e.g. `{"event":"error","data":{"message":"This tool isn't enabled for your account yet — contact contact@olympix.ai to enable it."}}` (older builds may word it as "private alpha"). This is a **feature gate**, not a transient failure. **HARD STOP** — tell the user fuzzing is not enabled for their account and to contact contact@olympix.ai to enable it. Do **not** retry, re-auth, or fall back; retrying will just re-emit the same error. The gate fires at the server auth handshake, before any billable work, so nothing was dispatched.

**If the dispatch errors otherwise or no `completed` arrives:** re-check authentication (run the `auth` skill) and that each `-p` path exists, then retry.

### Step 4: Wait for Completion

**Poll using the exact loop in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/poll-session.md` — do NOT write your own.** Set `SESSION_ID` to the recorded id and `ARRAY_KEY="fuzz_tests"`. The loop matches on `id`, reads `status`, and breaks on `Completed`/`Failed`/`Killed` using plain string equality.

**If status is `Failed`:** stop polling and go to Step 5 to read the failure.

**If status is `Killed`:** the run was stopped (see "Stopping a Run"). It is terminal and has no results — report it and stop. Do **not** reconnect or re-dispatch.

**If the user asks to stop the run while you are polling:** go to "Stopping a Run" — do not just abandon the poll. Abandoning it leaves the job burning compute server-side.

### Step 5: Retrieve Results (+ generated test files, optional PDF report)

When status is `Completed`, reconnect with the session id to pull results. Include `generate_report` to also produce the PDF; drop it for the summary only:

```bash
printf '{"action":"generate_report"}\n{"action":"disconnect"}\n' \
  | olympix connect-fuzz-session -s <session-id> --agent
```

**Expected output:**
```
{"event":"fuzz_tests_downloaded","data":{"session_id":"<id>","saved_count":7,"output_path":"<dir>","files":["...t.sol"]},"actions":["download_tests","generate_report","disconnect"]}
{"event":"fuzz_test_results","data":{"session_id":"<id>","contracts":3,"strategies":5,"test_cases":42,"exploit_test_cases":2,"tests_path":"<dir>","tests_file_count":7},"actions":["download_tests","generate_report","disconnect"]}
{"event":"pdf_generated","data":{"session_id":"<id>","pdf_path":"<path>"}}
```

The `fuzz_test_results` payload is a **summary** (counts of contracts, strategies, test cases, and exploit test cases) — the full per-test detail lives in the generated test files, the emailed report and the PDF.

**The generated test files download automatically on reconnect (default behavior).** Before
`fuzz_test_results` is emitted, the CLI pulls the generated `.t.sol` sources — the same files the
completion email attaches as a zip — into `fuzz_tests_<session-id>/` in the working directory and
emits `fuzz_tests_downloaded` (`saved_count`, `output_path`, `files`). The same path/count is echoed
on `fuzz_test_results` as `tests_path` / `tests_file_count`. No action is needed to get them; the
`download_tests` action only **re-downloads** them.

- Results auto-persist to `.opix/agent/fuzz-tests/results.json` in the workspace.
- If `generate_report` was sent, the PDF is written to disk and its path reported in `pdf_generated`.
- **No `fuzz_tests_downloaded` and no `tests_path`:** either the CLI predates the feature (tell the
  user to run `olympix update`) or the session has no stored test files — the CLI says which in a
  `progress` event. Continue either way; the results summary and PDF are unaffected.
- **No results yet** (`results_ready` instead of `fuzz_test_results`): the run is still finishing — wait and re-poll Step 4.

To re-download the test files later without re-reading results, send `download_tests` on a reconnect:

```bash
printf '{"action":"download_tests"}\n{"action":"disconnect"}\n' \
  | olympix connect-fuzz-session -s <session-id> --agent
```

### Step 6: Save Results to olympix-results/

Save a summary to `olympix-results/fuzz_test/fuzz_results.md`:

```markdown
# Fuzz Test Results

**Session ID:** {session_id}

| Metric | Count |
|--------|-------|
| Contracts fuzzed | {contracts} |
| Attack strategies | {strategies} |
| Test cases generated | {test_cases} |
| Exploit test cases | {exploit_test_cases} |
| Generated test files | {tests_file_count} |

Generated test files: {tests_path}   <!-- only if the download succeeded -->
PDF report: {pdf_path}   <!-- only if generate_report was sent -->
Full per-test detail is in the generated test files, the emailed report and the PDF.
```

Copy the downloaded test files from `tests_path` into `olympix-results/fuzz_test/tests/` so the
deliverable is self-contained (skip if the download did not happen). If a PDF was generated, also
copy/note it under `olympix-results/fuzz_test/`.

### Step 7: Report to User

Tell the user:
- How many contracts were fuzzed and how many **exploit test cases** were found (these are the ones that matter — they reproduce a broken invariant)
- How many generated test files were downloaded and where they landed (`tests_path`, copied under `olympix-results/fuzz_test/tests/`)
- Where the PDF report was saved (if generated)
- That full detail is in the generated test files, the emailed report and the PDF
- Results saved in `olympix-results/fuzz_test/fuzz_results.md`

If `exploit_test_cases > 0`, flag it clearly — those are candidate vulnerabilities worth reviewing.

## Stopping a Run

Fuzzing is the heaviest tool here, so a mis-scoped run is worth stopping rather than waiting out. Killing
is **permanent and destroys results** — confirm with the user before doing it, and never kill one on your
own initiative.

```bash
olympix kill-fuzz-session -s <session-id> --agent
```

**Expected output:**
```
{"event":"session_killed","data":{"session_id":"<id>","was_running":true}}
```

- `was_running: true` — the run was stopped and its compute released.
- `was_running: false` — nothing to stop; it had already finished, failed, or been killed. This is not an
  error, and killing again is safe.

After a kill the session is terminal and reports `Killed` in `olympix sessions --agent`. There are **no
results** — reconnecting returns an `error` event, not `fuzz_test_results`:

```
{"event":"error","data":{"message":"Server error: This run was killed — no results are available."}}
```

Report that to the user rather than retrying. To try again, dispatch a fresh run from Step 3 — there is
no resume, and no test files are downloaded for a killed session.

Killing needs the session id, so if it was never recorded, find it with `olympix sessions --agent` (under
`fuzz_tests`) before killing.

## Quick Reference

| Step | Command / Action | Gate |
|------|-----------------|------|
| 0 | Run `auth` skill | Must be authenticated |
| 1 | Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md` | `forge build` must pass |
| 2 | Identify top 3 contracts (plugin convention — fuzz is heavy) | Concrete contracts only |
| 3 | `printf '{"action":"disconnect"}\n' \| olympix generate-fuzz-tests -w . -p ... --agent` | Record session_id from `completed` |
| 4 | Poll `olympix sessions --agent` (`ARRAY_KEY="fuzz_tests"`) | Until `Completed`/`Failed`/`Killed` |
| — | `olympix kill-fuzz-session -s <id> --agent` (only if the user asks to stop) | Confirm first — permanent, results lost |
| 5 | `olympix connect-fuzz-session -s <id> --agent` (`generate_report` + `disconnect`) | Retrieve results + auto-downloaded test files + PDF |
| 6 | Save `olympix-results/fuzz_test/fuzz_results.md` + copy test files to `tests/` | — |
| 7 | Report to user | — |

## Important Notes

- **Sessions are auto-named** from the repo identity — there is no stdin title action for fuzz dispatch (unlike unit/mutation). Find them later with `olympix sessions --agent` or `olympix list-fuzz-sessions --agent`.
- **A run can be stopped** — see "Stopping a Run". Killing is permanent and results are lost, so only do it when the user asks.
- **Never state or imply an expected scan duration**, and never call a long run abnormal. Report phase/state only — "still running", "scanning", "done", "failed". The poll cadence is an internal mechanic; do not present it as an ETA. Fuzzing is heavier than mutation/unit tests, so it can legitimately run a while.
- **Results also arrive by email.** The agent-mode summary is the counts; the generated test files, the emailed report and the PDF hold the full detail.
- **The generated test sources are no longer email-only** — they download automatically on reconnect into `fuzz_tests_<session-id>/`, and `download_tests` re-downloads them on demand. This needs a CLI with the `download_tests` action; older builds simply emit no `fuzz_tests_downloaded` event.

## Common Issues

| Problem | Solution |
|---------|----------|
| `error` event: tool "isn't enabled for your account" / "private alpha" | Account lacks the fuzz feature flag — HARD STOP, tell the user to contact contact@olympix.ai. Do NOT retry |
| `forge build` fails | Install deps per README; HARD STOP if unfixable |
| `connect-fuzz-session` command missing | CLI predates fuzz agent mode — tell the user to run `olympix update`, then re-probe |
| Contract path wrong | Verify the path exists with `ls`; use relative path from repo root |
| Session status `Failed` | Reconnect and read the failure message (often a `forge` compilation error) |
| `results_ready` instead of `fuzz_test_results` | Run not finished — wait and re-poll |
| No `fuzz_tests_downloaded` event / no `tests_path` | CLI predates the test-file download (run `olympix update`) or the session has no stored files — the `progress` event says which. Not fatal; continue with the summary/PDF |
| `download_tests` returns an `error` event | Session has no stored test files, or the download timed out — retry once; the emailed zip remains the fallback |
| Session status `Killed` | The run was stopped — terminal, no results. Dispatch a fresh run; there is no resume |
| `kill-fuzz-session` command missing | CLI predates fuzz kill — tell the user to run `olympix update` |
| Kill returns `was_running: false` | Already terminal — nothing was stopped. Not an error |
| `op`/auth fails on dispatch | Re-run the `auth` skill, then retry the command |
