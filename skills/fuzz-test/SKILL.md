---
name: fuzz-test
description: >
  Prepares a Foundry-based Solidity repo for Olympix fuzz test generation.
  Verifies the repo builds, identifies the top 3 most critical contracts,
  then runs olympix generate-fuzz-tests with their paths.
  No file generation needed — only verification and contract selection.
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

Follow the `auth` skill to check authentication and automate login via Gmail if needed. If Gmail MCP is not connected, fall back to asking the user to run `! olympix login -e email` manually.

### Step 1: Verify Repository Builds

Run forge build to check the repo compiles:

```bash
forge build
```

**If it succeeds:** proceed to Step 3.

**If it fails:** go to Step 2.

**If it cannot be fixed:** **HARD STOP.** The repo must compile for fuzz test generation.

### Step 2: Initialize Repository

If forge build failed due to missing dependencies or configuration:

1. Read the project's README for setup instructions
2. Run the recommended initialization steps (e.g., `forge install`, `npm install --legacy-peer-deps`, `git submodule update --init --recursive`)
3. If there's a `remappings.txt` or the `foundry.toml` references remappings, verify they resolve
4. Re-run `forge build`
5. If it fails for other reasons → attempt to resolve, but do not spend more than 2 attempts before asking the user for help

### Step 3: Identify Top 3 Most Critical Contracts

Analyze the codebase and select the **3 most critical** contracts for fuzz testing. **Exclude interfaces, libraries, and abstract contracts that have no standalone logic.**

**Always read each candidate .sol file** to confirm the actual `contract` declaration name — it may differ from the file name.

**Criticality ranking criteria (highest to lowest):**
1. **Fund custody** — contracts that hold or transfer tokens/ETH (staking, vaults, treasuries)
2. **Token contracts** — ERC20/ERC721/OFT implementations, wrapped tokens
3. **Access control hubs** — factories, registries, managers with admin functions
4. **Bridge/cross-chain** — adapters, messengers, cross-chain token contracts
5. **Reward/distribution** — reward calculators, airdrop, vesting
6. **Core logic** — main protocol contracts with complex state transitions

List the selected contracts with their file paths relative to the repo root before proceeding.

### Step 4: Run Olympix Fuzz Test Generator

Build the command using `-p` flags for each contract path:

```bash
olympix generate-fuzz-tests -p contracts/path/to/Contract1.sol -p contracts/path/to/Contract2.sol -p contracts/path/to/Contract3.sol
```

**Rules:**
- Use the **file path** (not the contract name) for each `-p` argument
- Paths should be relative to the repo root
- Maximum 3 contracts per run

Report the session ID and output to the user.

## Quick Reference

| Step | Command / Action | Gate |
|------|-----------------|------|
| 1 | `forge build` | Must compile |
| 2 | Init repo per README | Only if Step 1 fails |
| 3 | Identify top 3 contracts | — |
| 4 | `olympix generate-fuzz-tests -p ... -p ... -p ...` | Final output |

## Common Issues

| Problem | Solution |
|---------|----------|
| `forge build` fails with missing imports | Install deps per README (`forge install`, `npm install --legacy-peer-deps`, etc.) |
| Versioned import paths (e.g. `@openzeppelin/contracts@5.0.2/`) | Add remapping: `@openzeppelin/contracts@5.0.2/=node_modules/@openzeppelin/contracts/` |
| npm deps have peer conflicts | Use `npm install --legacy-peer-deps`; install transitive deps manually if needed |
| Contract path wrong | Verify the path exists with `ls`; use relative path from repo root |
