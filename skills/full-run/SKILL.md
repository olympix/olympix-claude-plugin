---
name: full-run
description: >
  Use when the user wants a full Olympix security analysis — runs all tools in
  sequence: static analysis, mutation tests, unit tests, BugPocer, and optionally
  fuzz tests. Uses agent mode for all supported tools. Retrieves results directly.
  TRIGGER: "full run", "full-run", "run everything", "full scan", "run all tools"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill, AskUserQuestion
---

# Full Run

Run the full Olympix security analysis suite on a Foundry-based Solidity repository: static analysis, mutation tests, unit tests, BugPocer, and optionally fuzz tests. All supported tools use agent mode for automated JSONL interaction.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## CLI Capability Check

This skill requires agent mode (`--agent`); older Olympix CLIs do not support it. Probe once before starting:

```bash
olympix analyze --help 2>&1 | grep -q -- --agent && echo AGENT_MODE || echo LEGACY_CLI
```

If `LEGACY_CLI` (the `--agent` flag is rejected), the CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe. **HARD STOP** if the CLI still lacks `--agent`.

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication. This is checked once here — individual skills do not need to re-check.

### Step 1: Verify Repository Builds

Read and follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md`. This is a shared prerequisite for all tools — fix it once here.

**If it fails:** initialize the repo per the README. **HARD STOP** if `forge build` cannot be made to pass — none of the tools can run without it.

### Step 2: Run Static Analysis

Invoke the `static-analysis` skill workflow:

1. Run: `olympix analyze -w . --agent`
2. Parse JSONL `findings_ready` event
3. Convert findings to `olympix-results/olympix-static.md`
4. Record finding counts by severity

This runs **synchronously** — wait for results before proceeding.

### Step 3: Run Mutation Tests

Invoke the `mutation-test` skill workflow:

1. Identify the top 10 most critical contracts (read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/contract-selection.md`)
2. Dispatch: `printf '{"action":"new_session"}\n{"action":"disconnect"}\n' | olympix generate-mutation-tests -w . -p path1 -p path2 ... --agent`
3. Record the **session ID** from `results_ready` event

### Step 4: Run Unit Tests

Invoke the `unit-test` skill workflow:

1. Verify `forge coverage --ir-minimum --allow-failure` passes
2. If stack-too-deep: triage (localized vs repo-wide). Exclude affected contracts.
3. Detect solc version, create base contract and up to 10 test template files
4. Verify coverage still passes after adding files
5. Add setUp functions and example tests, verify again
6. Dispatch: `printf '{"action":"new_session"}\n{"action":"disconnect"}\n' | olympix generate-unit-tests -w . -p <paths> --agent`
   (do NOT send `confirm_all` — it is invalid after dispatch and can kill the dispatched job; `-ca` is a no-op in agent mode)
7. Record the **session ID**

**If unit tests hit a repo-wide stack-too-deep on coverage:** skip this step, note it in the summary, and continue.

### Step 5: Wait for Mutation + Unit Test Results

Poll `olympix sessions --agent` every ~90 seconds until both sessions show `Completed` or `Failed`. Then retrieve results.

**If either session is `Failed`:** capture its `error_message`, note it in the Step 8 summary, and continue with the other results — do not abort the run.

**Mutation test results:**
```bash
printf '{"action":"connect_session","data":{"session_id":"<mt-id>"}}\n{"action":"disconnect"}\n' \
  | olympix mutation-testing --agent
```

**Unit test results:**
```bash
printf '{"action":"connect_session","data":{"session_id":"<ut-id>"}}\n{"action":"disconnect"}\n' \
  | olympix unit-testing --agent
```

Save results to `olympix-results/mutation_test/` and `olympix-results/unit_test/`.

### Step 6: Run BugPocer (opt-in)

**Before launching, ask the user with AskUserQuestion whether to run BugPocer** (options: "Yes, run it" / "Skip for now"), citing the cost warning: each new BugPocer session triggers LLM calls on the backend and incurs scan cost. **If skipped:** note it in the Step 8 summary and continue.

If the user opts in, invoke the `bug-pocer` skill workflow:

1. Start session via the background-process + FIFO driver (see bug-pocer SKILL.md for full flow)
2. Confirm scope and validation items; answer security questions from the repo per the bug-pocer skill's deterministic rule (do NOT blindly skip them); skip docs
3. Wait for scan completion (poll `olympix sessions --agent`). BugPocer's terminal status is **`InitialScanCompleted`** — it never shows `Completed` (`Completed`/`Failed` apply only to the `unit_tests`/`mutation_tests` arrays)
4. Retrieve findings via `connect-bp-session`
5. Save findings to `olympix-results/bugpocer_pocs/`

### Step 7: Fuzz Tests (Optional)

Ask the user if they want fuzz tests. If yes:

1. From the same contract analysis, pick the top 3 most critical contracts
2. Run: `olympix generate-fuzz-tests -w . -p path1 -p path2 -p path3`
3. Record the **session ID**

**Note:** Fuzz tests do NOT support `--agent` mode. Results arrive via email only.

### Step 8: Summary

Present a summary table to the user:

```
## Olympix Full Run Summary

| Tool | Session ID | Results | Status |
|------|-----------|---------|--------|
| Static Analysis | — | {X} high, {Y} medium, {Z} low | Complete |
| Mutation Tests | {id} | {score}% kill score ({killed}/{total}) | Complete |
| Unit Tests | {id} | {coverage}% coverage, {passed} tests | Complete |
| BugPocer | {id or —} | {N} findings ({H} high, {M} medium, ...) | InitialScanCompleted / Skipped |
| Fuzz Tests | {id} | — | Started (check email) |
```

Tell the user:
- All results (except fuzz) are retrieved and saved in `olympix-results/`
- Run `/olympix:assemble-report` to compile the final report
- Fuzz test results (if run) will arrive via email

## Quick Reference

| Step | Tool | Command / Action | Mode |
|------|------|-----------------|------|
| 0 | Auth | Run `auth` skill (once) | — |
| 1 | Build | Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md` (once) | HARD STOP if unfixable |
| 2 | Static Analysis | `olympix analyze -w . --agent` | Synchronous |
| 3 | Mutation Tests | `olympix generate-mutation-tests -w . -p ... --agent` | Async — record session_id |
| 4 | Unit Tests | `printf '{"action":"new_session"}\n{"action":"disconnect"}\n' \| olympix generate-unit-tests -w . -p ... --agent` | Async — record session_id |
| 5 | Wait + retrieve | Poll `olympix sessions --agent`, then `mutation-testing` / `unit-testing` | — |
| 6 | BugPocer | AskUserQuestion opt-in (cost), then `bug-pocer` skill workflow | Async — poll until `InitialScanCompleted` |
| 7 | Fuzz Tests (opt.) | `olympix generate-fuzz-tests -w . -p ...` | NO `--agent`, email only |
| 8 | Summary | Present table + next steps | — |

## Important Notes

- **Do the codebase analysis ONCE** — identify all critical contracts in Step 3, then reuse that analysis for Steps 4 and 7.
- **Contract selection overlaps are fine** — the top 3 for fuzz tests will be a subset of the top 10 for mutation tests.
- **Don't stop on partial failure** — if one tool fails, note it and continue with the others.
- **Wait for results** — do not mark mutation/unit test steps as done until results are actually retrieved.
- **Fuzz tests are email-only** — they do NOT support `--agent`; results never come back programmatically.

## Common Issues

| Problem | Solution |
|---------|----------|
| `--agent` flag rejected | CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe |
| One tool fails mid-run | Note the failure and continue with the remaining tools — do not abort |
