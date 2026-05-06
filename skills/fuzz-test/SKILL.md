---
name: fuzz-test
description: >
  Prepares a Foundry-based Solidity repo for Olympix fuzz test generation.
  Verifies the repo builds, identifies the top 3 most critical contracts,
  then runs olympix generate-fuzz-tests. Agent mode is NOT supported for fuzz tests.
  TRIGGER: "fuzz tests", "fuzz test", "generate fuzz tests", "fuzzing", "fuzz-test"
tools: Read, Glob, Grep, Bash, Agent
---

# Fuzz Test Generation

Prepare a Foundry-based Solidity repository for Olympix fuzz test generation by verifying the repo builds, selecting the top 3 most critical contracts, and running the generator.

**Important:** Agent mode (`--agent`) is NOT supported for fuzz test generation. This tool runs in TUI/standard mode only. Results arrive via email.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication.

### Step 1: Verify Repository Builds

Read and follow `skills/_shared/forge-setup.md`.

### Step 2: Identify Top 3 Most Critical Contracts

Read `skills/_shared/contract-selection.md` for the full criteria. Select only the **top 3**.

List the selected contracts with their file paths relative to the repo root before proceeding.

### Step 3: Run Olympix Fuzz Test Generator

Build the command using `-p` flags for each contract path:

```bash
olympix generate-fuzz-tests -w . -p src/Contract1.sol -p src/Contract2.sol -p src/Contract3.sol
```

**Rules:**
- Use the **file path** (not the contract name) for each `-p` argument
- Paths should be relative to the repo root
- Maximum 3 contracts per run
- Do NOT use `--agent` — it will error with "Agent mode is not supported for generate-fuzz-tests yet."

Report the session ID and output to the user. Results arrive via email — ask the user to check their inbox.

**Note:** Unlike mutation tests and unit tests, fuzz test results cannot be retrieved via agent mode. The user must check their email for results.
