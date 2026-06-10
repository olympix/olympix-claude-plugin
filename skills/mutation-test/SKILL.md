---
name: mutation-test
description: >
  Runs Olympix mutation test generation on a Foundry-based Solidity repo using agent mode.
  Verifies the repo builds, identifies the top 10 most critical contracts,
  dispatches the job, waits for completion, and retrieves results with kill scores.
  TRIGGER: "mutation tests", "mutation test", "generate mutation tests", "mutant testing", "mutation-test"
tools: Read, Glob, Grep, Bash, Agent
---

# Mutation Test Generation

Run Olympix mutation test generation on a Foundry-based Solidity repository using agent mode: verify the repo builds, select the top 10 most critical contracts, dispatch the job, wait for completion, and retrieve results.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication.

### Step 1: Verify Repository Builds

Read and follow `skills/_shared/forge-setup.md`.

**If it fails:** initialize the repo per the README. **HARD STOP** if `forge build` cannot be made to pass.

**NOTE:** `forge test --via-ir` is NOT required. The Olympix CLI handles viaIR compilation server-side. You only need basic `forge build` to pass locally. A repo that fails `forge test --via-ir` locally due to stack-too-deep can still successfully generate mutation tests via the Olympix CLI.

### Step 2: Identify Top 10 Most Critical Contracts

Read `skills/_shared/contract-selection.md` for the full criteria.

Select the 10 most critical contracts. List the selected contracts with their file paths relative to the repo root before proceeding.

### Step 3: Dispatch Mutation Test Job

Use agent mode with `-p` flags for each contract path. The flow goes through a `sessions_list` first, then `new_session` to dispatch:

```bash
printf '{"action":"new_session"}\n{"action":"disconnect"}\n' \
  | olympix generate-mutation-tests -w . -p src/Contract1.sol -p src/Contract2.sol --agent
```

**Expected JSONL output:**
```
{"event":"sessions_list","data":{"sessions":[...]},"actions":["new_session","connect_session","disconnect"]}
{"event":"results_ready","data":{"type":"mutation_test","session_id":"<uuid>","message":"mutation test generation started. Check email for results."},"actions":["disconnect"]}
```

Record the **session_id** from the `results_ready` event.

**Options:**
- `--agent` — agent mode, JSONL stdin/stdout (required for this skill)
- `-w .` — workspace directory (paths resolve relative to this)
- `-p <path>` — contract file to mutate (repeat once per contract)

**Rules:**
- Use the **file path** (not the contract name) for each `-p` argument
- Paths should be relative to the repo root (resolved relative to `-w` workspace)
- Maximum 10 contracts per run

**If the dispatch errors or no `results_ready` arrives:** re-check authentication (run the `auth` skill) and that each `-p` path exists, then retry.

### Step 4: Wait for Completion

Poll the session status periodically (every ~90 seconds) until it shows `Completed` or `Failed`:

```bash
olympix sessions --agent
```

Look for the session ID in the `mutation_tests` array. Status will be `InProgress` → `Completed` or `Failed`.

**If status is `Failed`:** stop polling and go to Step 5 to read the `error_message`.

### Step 5: Retrieve Results

When status is `Completed`, reconnect to download results:

```bash
printf '{"action":"connect_session","data":{"session_id":"<id>"}}\n{"action":"disconnect"}\n' \
  | olympix mutation-testing --agent
```

**Expected output includes:**
```
{"event":"sessions_list","data":{"sessions":[...]},"actions":["new_session","connect_session","disconnect"]}
{"event":"mutation_test_results","data":{"session_id":"<id>","total_mutations":35,"killed":25,"survived":10,"score_percentage":71,"mutations":[...]}}
```

Each mutation in the `mutations` array has: `file`, `line`, `original`, `mutated`, `killed` (bool), `broken_tests` (array).

Results also auto-persist to `.opix/agent/mutation-tests/results.json` in the workspace.

**If status is `Failed`:** The session will include an `error_message` field explaining the failure (e.g., `forge test` compilation error).

### Step 6: Save Results to olympix-results/

Parse the mutation test results and save to `olympix-results/mutation_test/mutation_results.md`:

```markdown
# Mutation Test Results

**Session ID:** {id}
**Overall Score:** {score_percentage}% ({killed} killed / {total_mutations} total)

## Per-File Breakdown

| File | Line | Original | Mutated | Killed | Broken Tests |
|------|------|----------|---------|--------|-------------|
| ... | ... | ... | ... | Yes/No | test1(), test2() |
```

### Step 7: Report to User

Tell the user:
- Mutation score percentage
- How many mutations killed vs survived
- Which surviving mutations represent real coverage gaps
- Results saved in `olympix-results/mutation_test/mutation_results.md`

## Quick Reference

| Step | Command / Action | Gate |
|------|-----------------|------|
| 0 | Run `auth` skill | Must be authenticated |
| 1 | Follow `skills/_shared/forge-setup.md` | `forge build` must pass |
| 2 | Identify top 10 contracts | Concrete contracts only |
| 3 | `olympix generate-mutation-tests -w . -p ... --agent` | Record session_id |
| 4 | Poll `olympix sessions --agent` | Until `Completed`/`Failed` |
| 5 | `olympix mutation-testing --agent` (connect_session) | Retrieve results |
| 6 | Save `olympix-results/mutation_test/mutation_results.md` | — |
| 7 | Report to user | — |

## Common Issues

| Problem | Solution |
|---------|----------|
| `forge build` fails | Install deps per README; HARD STOP if unfixable |
| Contract path wrong | Verify the path exists with `ls`; use relative path from repo root |
| Session status `Failed` | Read `error_message` (often a `forge test` compilation error) |
| `op`/auth fails on dispatch | Re-run the `auth` skill, then retry the command |
