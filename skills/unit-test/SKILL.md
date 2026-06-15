---
name: unit-test
description: >
  Use when the user wants Olympix unit test generation prepared and run for a
  Foundry- or Hardhat-based Solidity repo — verifies forge coverage compatibility, scaffolds the
  OlympixUnitTest base contract and test files for the top 10 most critical contracts,
  adds setup functions, dispatches olympix generate-unit-tests via agent mode, then
  waits for results and retrieves coverage data.
  TRIGGER: "scaffold tests", "unit test", "generate unit tests", "opix tests", "test generation setup", "unit-test"
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Skill, AskUserQuestion
---

# Unit Test Generation

Prepare a Foundry- or Hardhat-based Solidity repository for Olympix unit test generation by scaffolding test templates, verifying forge coverage compatibility, and running the generator via agent mode.

## Prerequisites

- Foundry (`forge`) or Hardhat (`npx hardhat`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry or Hardhat project

## CLI Capability Check

This skill requires agent mode (`--agent`); older Olympix CLIs do not support it. Probe first:

```bash
if ! command -v olympix >/dev/null 2>&1 && [ ! -x "$HOME/.opix/bin/olympix" ]; then echo NOT_INSTALLED;
elif olympix generate-unit-tests --help 2>&1 | grep -q -- --agent; then echo AGENT_MODE; else echo LEGACY_CLI; fi
```

If `NOT_INSTALLED`, **HARD STOP** — tell the user to install the Olympix CLI from https://olympix.github.io/installation/ and rerun this skill.

If `LEGACY_CLI` (the `--agent` flag is rejected), the CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe. **HARD STOP** if the CLI still lacks `--agent`.

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication.

### Step 1: Verify Coverage Compatibility

Olympix supports Foundry and Hardhat repos (the CLI auto-detects). Pick the **coverage command for this repo** by project type — it is reused at every coverage checkpoint below:

- **Foundry** (`foundry.toml`): `forge coverage --ir-minimum --allow-failure`
- **Hardhat** (`hardhat.config.*`, no `foundry.toml`): `npx hardhat coverage` (requires the `solidity-coverage` plugin; install per the project's README if missing)

```bash
# Foundry
forge coverage --ir-minimum --allow-failure
# Hardhat
npx hardhat coverage
```

> **Substitution note:** Steps 6, 8, and 9 below show the Foundry commands (`forge coverage`, `forge test`) and the Foundry scaffold pattern (`OlympixUnitTest`, `.t.sol`). On a Hardhat repo, run the coverage command above in place of every `forge coverage --ir-minimum --allow-failure`. The stack-too-deep triage is **Foundry-specific** — Hardhat repos that compile under `npx hardhat compile` do not hit it.

**If it succeeds:** proceed to Step 2.

**If it fails with build/dependency errors:** read and follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md`, then retry.

**If it fails with "stack too deep" (Foundry):** read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/troubleshooting.md` for the stack-too-deep triage process. Determine if the problem is localized or repo-wide.

> **HARD STOP (repo-wide stack-too-deep):**
> Do NOT proceed. Do NOT create test files. Do NOT run the generator. Tell the user the repo is incompatible with unit test generation.

### Step 2: Detect Test Directory and Solidity Version

**Test directory:** Check `foundry.toml` for the `test` key. Default is `test/` if not specified. Use whatever the project has configured.

**Solidity version:**
1. Check `foundry.toml` for a `solc_version` setting
2. If not set, scan `pragma solidity` across contracts:
   ```bash
   grep -r "pragma solidity" contracts/ src/ --include="*.sol" | head -20
   ```
3. Use the most common pragma version. If there's a mix, prefer the caret version that covers the most contracts.

Record as `{TEST_DIR}` and `{SOLC_PRAGMA}`.

### Step 3: Create Base Test Contract

Create `{TEST_DIR}/OpixUnitTests.sol`:

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity {SOLC_PRAGMA};

import "forge-std/Test.sol";

//Olympix Test Generation
abstract contract OlympixUnitTest is Test {
    constructor(string memory name_) {}
}
```

### Step 4: Identify Top 10 Most Critical Contracts

Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/contract-selection.md` for the full criteria.

Additional rules for unit tests:
- **Exclude contracts that transitively import a stack-too-deep offender** (identified in Step 1)
- **Only select CONCRETE contracts.** The Olympix CLI fails with `Contract 'X' not found` for abstract contracts or libraries. Find a concrete inheritor or mock instead.
- **Maximum 10 test files total.** If existing Opix test files exist from a prior run, count those first.

List the selected contracts with their import paths before creating files.

### Step 5: Create Test Template Files

For each selected contract, create `{TEST_DIR}/Opix{ContractName}Test.t.sol`:

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity {SOLC_PRAGMA};

import {OlympixUnitTest} from "{TEST_DIR}/OpixUnitTests.sol";
import {{ContractName}} from "{contract_import_path}";

//Olympix Test Generation
contract Olympix{ContractName}UnitTest is OlympixUnitTest("{ContractName}") {
}
```

**CRITICAL rules:**
- The string in `OlympixUnitTest("...")` must be the **actual `contract` declaration name** inside the .sol file (not the file name)
- Do NOT add a constructor, setUp, imports, or state variables at this step
- Do NOT deviate from the inheritance pattern

**Common mistakes that BREAK generation:**
```solidity
// WRONG — missing contract name string
contract OpixFooTest is OlympixUnitTest {

// WRONG — added constructor
contract OlympixFooUnitTest is OlympixUnitTest("Foo") {
    constructor(string memory name_) {}
}

// CORRECT
contract OlympixFooUnitTest is OlympixUnitTest("Foo") {
}
```

### Step 6: Verify Forge Coverage (Checkpoint)

```bash
forge coverage --ir-minimum --allow-failure
```

**If it fails:** diagnose. Common issues:
- Import path wrong → fix the import
- Contract name mismatch → read file for actual `contract` declaration
- Stack-too-deep from a newly added test → remove it, replace with next-best candidate

**Do not proceed until coverage runs without compilation errors.**

### Step 7: Add Setup Functions

For each test contract, add a `setUp()` function that deploys and initializes the contract with working dependencies.

#### 7a. Research Existing Test Infrastructure

Before writing setUp, study the repo:
1. **Existing Foundry tests** (`*.t.sol`) — copy deployment patterns from existing setUp functions
2. **Deploy scripts** (`script/*.s.sol`) — real deployment order, constructor args, initialization params
3. **Mock contracts** (`contracts/mocks/`, `test/mocks/`, `src/test/`) — reuse these
4. **JS/TS fixtures** (Hardhat repos) — `_fixture.js`, `test/helpers/`, `deploy/` scripts show constructor args
5. **Deploy migrations** (`deploy/`, `migrations/`) — initialization order

#### 7b. Handle Governance/Access Control

Many DeFi contracts use custom governance with assembly-based storage slots:

```solidity
// For assembly-stored governance:
bytes32 internal constant GOVERNOR_SLOT = 0x7bea1389...;
function _setGovernor(address target, address governor) internal {
    vm.store(target, GOVERNOR_SLOT, bytes32(uint256(uint160(governor))));
}

// For OpenZeppelin Ownable:
vm.startPrank(admin);
target = new MyContract();
vm.stopPrank();
```

#### 7c. Deploy Dependencies First

Follow this order:
1. Mock tokens (ERC20s)
2. Vault/Core contracts
3. Oracle/Price feeds
4. Strategy contracts
5. Peripheral contracts (harvesters, drippers)

#### 7d. Create Minimal Mocks for External Protocols

When a contract interacts with external protocols, create minimal inline mocks that implement only the interface methods needed for constructor/setUp:

```solidity
contract MockPool {
    address public token0;
    address public token1;
    constructor(address _t0, address _t1) { token0 = _t0; token1 = _t1; }
}
```

#### 7e. Guidelines

- Prefer existing mocks from the repo over writing new ones
- Use `vm.store()` for governance storage slots
- Use `vm.startPrank`/`vm.stopPrank` for deployer/governor context
- Use `deal()` to fund addresses
- If a contract is too complex to set up, leave a partial setup with a TODO comment

### Step 8: Add Example Test Functions

A scaffold with `setUp()` but zero test functions produces zero generated tests. The generator uses existing tests as few-shot examples. No examples means no output.

**Add 2-4 concrete example test functions per scaffold:**

- **1 happy-path / state-mutation test** — call main function, assert on state
- **1 revert test with `vm.expectRevert`** — shows the revert pattern
- **1 access-control / branch test** (if applicable) — `vm.prank(unauthorized)` + expected revert

**Naming:** prefix with `test_example_` so they're visually distinct from generated output.

**Example:**
```solidity
function test_example_deposit() public {
    uint256 before = vault.totalDeposits();
    vm.prank(user);
    vault.deposit(100e18);
    assertEq(vault.totalDeposits(), before + 100e18);
}

function test_example_depositRevertsWhenPaused() public {
    vm.prank(admin);
    vault.pause();
    vm.prank(user);
    vm.expectRevert("Paused");
    vault.deposit(100e18);
}

function test_example_unauthorizedPauseReverts() public {
    vm.prank(address(0xDEAD));
    vm.expectRevert();
    vault.pause();
}
```

**Verify before proceeding:**
```bash
forge test --match-test 'test_example_'
```
All example tests MUST pass.

### Step 9: Verify Forge Coverage (Final Check)

```bash
forge coverage --ir-minimum --allow-failure
```

If it fails after adding setUp functions, simplify the setUp that caused the failure.

### Step 10: List Available Contracts (Optional Verification)

Before dispatching, verify the CLI sees the contracts:

```bash
olympix generate-unit-tests -w . --list --agent
```

Output: `{"event":"list_contracts","data":{"contracts":[{"index":1,"name":"...","path":"..."}]}}`

Verify the contracts you scaffolded appear in the list. The file is also saved to `.opix/agent/unit-tests/contracts.json`.

### Step 11: Name the Session

Name the session so the user can find it later in `olympix` (`olympix sessions`, the TUI session lists). Pick a suggested default from the repo identity:

```bash
org_repo=$(git remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')
short_sha=$(git rev-parse --short HEAD 2>/dev/null)
if [ -n "$org_repo" ] && [ -n "$short_sha" ]; then echo "${org_repo}@${short_sha}"; else basename "$(pwd)"; fi
```

**Ask the user to confirm or change it**, presenting the suggested default (use `AskUserQuestion` with the suggested default as the first option, or a plain prompt that states the suggestion). The user may accept the suggestion or supply their own. Record the confirmed name as `{SESSION_TITLE}`.

### Step 12: Dispatch Unit Test Generation

Pass the confirmed session name in `data.title`:

```bash
printf '{"action":"new_session","data":{"title":"{SESSION_TITLE}"}}\n{"action":"disconnect"}\n' \
  | olympix generate-unit-tests -w . -p src/Contract1.sol --agent
```

**Do NOT send `confirm_all` here** — it is not a valid action after dispatch. Sending it triggers an `error` event that skips the disconnect acknowledgment and the EOF safety delay, which can kill the just-dispatched job. The correct sequence is exactly `new_session` then `disconnect` (same as mutation tests).

**Expected JSONL output:**
```
{"event":"sessions_list","data":{"sessions":[...]},"actions":["new_session","connect_session","disconnect"]}
{"event":"results_ready","data":{"type":"unit_test","session_id":"<uuid>","message":"unit test generation started. Check email for results."},"actions":["disconnect"]}
```

Record the **session_id**.

**Options:**
- `--agent` — agent mode, JSONL stdin/stdout (required for this skill)
- `-w .` — workspace directory (paths resolve relative to this)
- `-p <path>` — suppresses the interactive `file_selection` prompt (repeat per contract)
- `-ca` — do NOT bother: it is a **no-op in agent mode** (it only affects the interactive TUI confirmation flow)

**Rules:**
- In agent mode, `-p` does **NOT** filter which contracts get tests — generation always covers **every scaffold that inherits `OlympixUnitTest`**. Its real effect is suppressing the `file_selection` prompt so the dispatch runs unattended. Still pass your scaffold paths for clarity.
- Scaffold at most 10 test files (Step 4) — that is what bounds the run, not `-p`

**If the dispatch errors or no `results_ready` arrives:** re-check authentication (run the `auth` skill) and that each `-p` path exists, then retry.

### Step 13: Wait for Completion

> **Poll in a blocking, in-turn loop — do not background the poll and end your turn.** If you are running as a dispatched subagent you are **not** re-invoked: backgrounding a `sleep`/poll and exiting silently drops the results (the session completes backend-side but nothing is retrieved). Wait between polls in-turn (the `Monitor` tool or a foreground loop) until terminal, then go straight to Step 14.

Poll the session status periodically (every ~90 seconds) until `Completed` or `Failed`:

```bash
olympix sessions --agent
```

Look for the session ID in the `unit_tests` array. Status will be `InProgress` → `Completed` or `Failed`.

**If status is `Failed`:** stop polling and go to Step 14 to read the `error_message`.

### Step 14: Retrieve Results

When status is `Completed`, reconnect:

```bash
printf '{"action":"connect_session","data":{"session_id":"<id>"}}\n{"action":"disconnect"}\n' \
  | olympix unit-testing --agent
```

**Expected output includes:**
```
{"event":"sessions_list","data":{"sessions":[...]},"actions":["new_session","connect_session","disconnect"]}
{"event":"unit_test_results","data":{"session_id":"<id>","total_files":1,"successful_files":1,"branches_coverage":74.4,"test_files":[{"subject_contract":"...","subject_path":"...","test_contract":"...","test_path":"...","has_new_tests":true,"coverage_before":71.8,"coverage_after":74.4,"passed":13,"failed":0}]}}
```

Results also auto-persist to `.opix/agent/unit-tests/results.json`. Note: at dispatch time this file contains only the dispatch receipt; the full results are written to it at this retrieval step.

**If status is `Failed`:** The session includes an `error_message` field.

### Step 15: Save Results and Report

Parse results and save to `olympix-results/unit_test/unit_test_results.md`:

```markdown
# Unit Test Results

**Session ID:** {id}
**Total Files:** {total_files} | **Successful:** {successful_files}
**Branches Coverage:** {branches_coverage}%

## Per-File Results

| Contract | Test File | Coverage Before | Coverage After | Passed | Failed |
|----------|-----------|----------------|----------------|--------|--------|
| ... | ... | ...% | ...% | ... | ... |
```

Tell the user:
- Coverage improvements per contract
- Total tests generated and pass rate
- Results saved in `olympix-results/unit_test/unit_test_results.md`

## Quick Reference

| Step | Command / Action | Gate |
|------|-----------------|------|
| 0 | Run `auth` skill | Must be authenticated |
| 1 | `forge coverage --ir-minimum --allow-failure` | HARD STOP on repo-wide stack-too-deep |
| 2 | Detect `{TEST_DIR}` and `{SOLC_PRAGMA}` | — |
| 3 | Create `{TEST_DIR}/OpixUnitTests.sol` | — |
| 4 | Identify top 10 concrete contracts | Concrete contracts only |
| 5 | Create `Opix{Contract}Test.t.sol` templates | Exact inheritance pattern |
| 6 | `forge coverage --ir-minimum --allow-failure` | Must compile |
| 7 | Add `setUp()` functions | — |
| 8 | Add 2-4 `test_example_` functions | All must pass |
| 9 | `forge coverage --ir-minimum --allow-failure` | Must compile |
| 10 | `olympix generate-unit-tests -w . --list --agent` | Contracts appear in list |
| 11 | Suggest a session name; ask the user to confirm/change it | Record `{SESSION_TITLE}` |
| 12 | `printf '{"action":"new_session","data":{"title":"{SESSION_TITLE}"}}\n{"action":"disconnect"}\n' \| olympix generate-unit-tests -w . -p ... --agent` | Record session_id |
| 13 | Poll `olympix sessions --agent` | Until `Completed`/`Failed` |
| 14 | `olympix unit-testing --agent` (connect_session) | Retrieve results |
| 15 | Save results + report to user | — |

## Important Notes

- **Session naming:** Always name the session and ask the user to confirm or change it, suggesting a sensible default (repo identity `<org>/<repo>@<short-sha>` from git, falling back to the repo folder name). Pass the confirmed name in the `new_session` action's `data.title`. Older CLIs ignore the title and keep the default name (`<org>/<repo>@<short-sha>` or a timestamp) — if naming has no effect, suggest `olympix update`.
- **Never state or imply an expected scan duration**, and never call a long scan abnormal (e.g. "running longer than typical (~17 min)"). Report phase/state only — "still running", "scanning", "done", "failed". The `~90 second` poll cadence is an internal mechanic; do not present it to the user as an ETA.

## Common Issues

| Problem | Solution |
|---------|----------|
| `--agent` flag rejected | CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe |
| Repo-wide stack-too-deep under coverage | HARD STOP — do not create files or dispatch |
| `Contract 'X' not found` | Abstract/library scaffolded — use a concrete inheritor or mock |
| Zero tests generated | Scaffold had no `test_example_` functions — add 2-4 and re-dispatch |
| Example tests fail | Fix setUp/mocks until `forge test --match-test 'test_example_'` passes |
| Session status `Failed` | Read `error_message` from the results event |
