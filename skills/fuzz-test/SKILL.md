---
name: fuzz-test
description: >
  Prepares a Foundry-based Solidity repo for Olympix fuzz test generation.
  Verifies the repo builds, identifies the top 3 most critical contracts,
  then runs olympix generate-fuzz-tests with their paths.
  TRIGGER: "fuzz tests", "fuzz test", "generate fuzz tests", "fuzzing", "fuzz-test"
tools: Read, Glob, Grep, Bash, Agent
---

# Fuzz Test Generation

Prepare a Foundry-based Solidity repository for Olympix fuzz test generation by verifying the repo builds, selecting the top 3 most critical contracts, and running the generator.

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
olympix generate-fuzz-tests -p contracts/path/to/Contract1.sol -p contracts/path/to/Contract2.sol -p contracts/path/to/Contract3.sol
```

**Rules:**
- Use the **file path** (not the contract name) for each `-p` argument
- Paths should be relative to the repo root
- Maximum 3 contracts per run

Report the session ID and output to the user. Results arrive via email — ask the user to check their inbox.
