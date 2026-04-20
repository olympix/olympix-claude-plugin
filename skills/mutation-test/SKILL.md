---
name: mutation-test
description: >
  Prepares a Foundry-based Solidity repo for Olympix mutation test generation.
  Verifies the repo builds, identifies the top 10 most critical contracts,
  then runs olympix generate-mutation-tests with their paths.
  TRIGGER: "mutation tests", "mutation test", "generate mutation tests", "mutant testing", "mutation-test"
tools: Read, Glob, Grep, Bash, Agent
---

# Mutation Test Generation

Prepare a Foundry-based Solidity repository for Olympix mutation test generation by verifying the repo builds, selecting the top 10 most critical contracts, and running the generator.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication.

### Step 1: Verify Repository Builds

Read and follow `skills/_shared/forge-setup.md`.

**NOTE:** `forge test --via-ir` is NOT required. The Olympix CLI handles viaIR compilation server-side. You only need basic `forge build` to pass locally.

### Step 2: Identify Top 10 Most Critical Contracts

Read `skills/_shared/contract-selection.md` for the full criteria.

Select the 10 most critical contracts. List the selected contracts with their file paths relative to the repo root before proceeding.

### Step 3: Run Olympix Mutation Test Generator

Build the command using `-p` flags for each contract path:

```bash
olympix generate-mutation-tests -p contracts/path/to/Contract1.sol -p contracts/path/to/Contract2.sol -p contracts/path/to/Contract3.sol ...
```

**Rules:**
- Use the **file path** (not the contract name) for each `-p` argument
- Paths should be relative to the repo root
- Maximum 10 contracts per run

Report the session ID and output to the user. Results arrive via email — ask the user to check their inbox.
