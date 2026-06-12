---
name: fuzz-test
description: >
  Use when the user wants Olympix fuzz test generation prepared and dispatched for a
  Foundry-based Solidity repo — verifies the repo builds, identifies the top 3 most
  critical contracts, then runs olympix generate-fuzz-tests. Agent mode is NOT
  supported for fuzz tests.
  TRIGGER: "fuzz tests", "fuzz test", "generate fuzz tests", "fuzzing", "fuzz-test"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill
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

Read and follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md`.

**If it fails:** initialize the repo per the README. **HARD STOP** if it cannot be fixed — the repo must compile for fuzz test generation.

### Step 2: Identify Top 3 Most Critical Contracts

Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/contract-selection.md` for the full criteria. Select only the **top 3**.

List the selected contracts with their file paths relative to the repo root before proceeding.

### Step 3: Run Olympix Fuzz Test Generator

Build the command using `-p` flags for each contract path:

```bash
olympix generate-fuzz-tests -w . -p src/Contract1.sol -p src/Contract2.sol -p src/Contract3.sol
```

**Options:**
- `-w .` — workspace directory (paths resolve relative to this)
- `-p <path>` — contract file to fuzz (repeat once per contract, max 3)

**Rules:**
- Use the **file path** (not the contract name) for each `-p` argument
- Paths should be relative to the repo root
- Maximum 3 contracts per run
- Do NOT use `--agent` — it will error with "Agent mode is not supported for generate-fuzz-tests yet."

Report the session ID and output to the user. Results arrive via email — ask the user to check their inbox. When the result email needs to be located later (by the user or any mail tooling), search by the **session ID (UUID)** — never by date or subject, which are ambiguous across runs.

**If `op`/auth fails:** re-run the `auth` skill, then retry the command.

## Important Notes

- **Agent mode is NOT supported** for fuzz test generation — never pass `--agent`. This tool runs in TUI/standard mode only.
- **Results arrive via email only.** Unlike mutation tests and unit tests, fuzz test results cannot be retrieved programmatically. The user must check their inbox.
- **Maximum 3 contracts per run** — select only the top 3 most critical contracts.

## Common Issues

| Problem | Solution |
|---------|----------|
| `forge build` fails | Install deps per README; HARD STOP if unfixable |
| `olympix` not found | CLI not installed — HARD STOP, install from https://olympix.github.io/installation/ |
| `--agent` error about unsupported mode | Remove `--agent` — fuzz tests run in standard mode only |
| Contract path wrong | Verify the path exists with `ls`; use relative path from repo root |
| `op`/auth fails | Re-run the `auth` skill, then retry the command |
