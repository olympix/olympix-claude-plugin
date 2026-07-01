---
name: fuzz-test
description: >
  Use when the user wants Olympix fuzz test generation run on a Foundry- or Hardhat-based
  Solidity repo via agent mode — verifies the repo builds, selects the most critical
  contracts, dispatches the fuzz job, waits for completion, then reconnects to retrieve
  the results summary and (optionally) a PDF report.
  TRIGGER: "fuzz tests", "fuzz test", "generate fuzz tests", "fuzzing", "fuzz-test"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill, AskUserQuestion
---

# Fuzz Test Generation

Run Olympix fuzz test generation on a Foundry- or Hardhat-based Solidity repository using agent mode: verify the repo builds, select the most critical contracts, dispatch the job, wait for completion, then reconnect to retrieve results.

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
elif olympix connect-fuzz-session --help >/dev/null 2>&1; then echo AGENT_MODE; else echo LEGACY_CLI; fi
```

If `NOT_INSTALLED`, **HARD STOP** — tell the user to install the Olympix CLI from https://olympix.github.io/installation/ and rerun this skill.

If `LEGACY_CLI` (no `connect-fuzz-session` command), the CLI predates fuzz agent mode — tell the user to run `olympix update`, then re-probe. **HARD STOP** if it still lacks the command.

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

**Poll using the exact loop in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/poll-session.md` — do NOT write your own.** Set `SESSION_ID` to the recorded id and `ARRAY_KEY="fuzz_tests"`. The loop matches on `id`, reads `status`, and breaks on `Completed`/`Failed` using plain string equality.

**If status is `Failed`:** stop polling and go to Step 5 to read the failure.

### Step 5: Retrieve Results (+ optional PDF report)

When status is `Completed`, reconnect with the session id to pull results. Include `generate_report` to also produce the PDF; drop it for the summary only:

```bash
printf '{"action":"generate_report"}\n{"action":"disconnect"}\n' \
  | olympix connect-fuzz-session -s <session-id> --agent
```

**Expected output:**
```
{"event":"fuzz_test_results","data":{"session_id":"<id>","contracts":3,"strategies":5,"test_cases":42,"exploit_test_cases":2},"actions":["generate_report","disconnect"]}
{"event":"pdf_generated","data":{"session_id":"<id>","pdf_path":"<path>"}}
```

The `fuzz_test_results` payload is a **summary** (counts of contracts, strategies, test cases, and exploit test cases) — the full per-test detail lives in the emailed report and the generated PDF.

- Results auto-persist to `.opix/agent/fuzz-tests/results.json` in the workspace.
- If `generate_report` was sent, the PDF is written to disk and its path reported in `pdf_generated`.
- **No results yet** (`results_ready` instead of `fuzz_test_results`): the run is still finishing — wait and re-poll Step 4.

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

PDF report: {pdf_path}   <!-- only if generate_report was sent -->
Full per-test detail is in the emailed report and the PDF.
```

If a PDF was generated, also copy/note it under `olympix-results/fuzz_test/`.

### Step 7: Report to User

Tell the user:
- How many contracts were fuzzed and how many **exploit test cases** were found (these are the ones that matter — they reproduce a broken invariant)
- Where the PDF report was saved (if generated)
- That full detail is in the emailed report / PDF
- Results saved in `olympix-results/fuzz_test/fuzz_results.md`

If `exploit_test_cases > 0`, flag it clearly — those are candidate vulnerabilities worth reviewing.

## Quick Reference

| Step | Command / Action | Gate |
|------|-----------------|------|
| 0 | Run `auth` skill | Must be authenticated |
| 1 | Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md` | `forge build` must pass |
| 2 | Identify top 3 contracts (plugin convention — fuzz is heavy) | Concrete contracts only |
| 3 | `printf '{"action":"disconnect"}\n' \| olympix generate-fuzz-tests -w . -p ... --agent` | Record session_id from `completed` |
| 4 | Poll `olympix sessions --agent` (`ARRAY_KEY="fuzz_tests"`) | Until `Completed`/`Failed` |
| 5 | `olympix connect-fuzz-session -s <id> --agent` (`generate_report` + `disconnect`) | Retrieve results + PDF |
| 6 | Save `olympix-results/fuzz_test/fuzz_results.md` | — |
| 7 | Report to user | — |

## Important Notes

- **Sessions are auto-named** from the repo identity — there is no stdin title action for fuzz dispatch (unlike unit/mutation). Find them later with `olympix sessions --agent` or `olympix list-fuzz-sessions --agent`.
- **Never state or imply an expected scan duration**, and never call a long run abnormal. Report phase/state only — "still running", "scanning", "done", "failed". The poll cadence is an internal mechanic; do not present it as an ETA. Fuzzing is heavier than mutation/unit tests, so it can legitimately run a while.
- **Results also arrive by email.** The agent-mode summary is the counts; the emailed report and PDF hold the full detail.

## Common Issues

| Problem | Solution |
|---------|----------|
| `error` event: tool "isn't enabled for your account" / "private alpha" | Account lacks the fuzz feature flag — HARD STOP, tell the user to contact contact@olympix.ai. Do NOT retry |
| `forge build` fails | Install deps per README; HARD STOP if unfixable |
| `connect-fuzz-session` command missing | CLI predates fuzz agent mode — tell the user to run `olympix update`, then re-probe |
| Contract path wrong | Verify the path exists with `ls`; use relative path from repo root |
| Session status `Failed` | Reconnect and read the failure message (often a `forge` compilation error) |
| `results_ready` instead of `fuzz_test_results` | Run not finished — wait and re-poll |
| `op`/auth fails on dispatch | Re-run the `auth` skill, then retry the command |
