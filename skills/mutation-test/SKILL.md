---
name: mutation-test
description: >
  Prepares a Foundry-based Solidity repo for Olympix mutation test generation.
  Verifies the repo builds, identifies the top 10 most critical contracts,
  then runs olympix generate-mutation-tests with their paths.
  No file generation needed — only verification and contract selection.
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

Follow the `auth` skill to check authentication and automate login via Gmail if needed. If Gmail MCP is not connected, fall back to asking the user to run `! olympix login -e email` manually.

### Step 1: Verify Repository Builds

Run forge build to check the repo compiles:

```bash
forge build
```

**If it succeeds:** proceed to Step 3.

**If it fails with dependency errors:** go to Step 2.

**NOTE: `forge test --via-ir` is NOT required.** The Olympix CLI handles viaIR compilation server-side. You only need basic `forge build` to pass locally to confirm the source code and dependencies are valid. A repo that fails `forge test --via-ir` locally due to stack-too-deep can still successfully generate mutation tests via the Olympix CLI.

### Step 2: Initialize Repository

If forge build failed due to missing dependencies or configuration:

1. Read the project's README for setup instructions
2. Run the recommended initialization steps (e.g., `forge install`, `npm install --legacy-peer-deps`, `git submodule update --init --recursive`)
3. If there's a `remappings.txt` or the `foundry.toml` references remappings, verify they resolve
4. Re-run `forge build`
5. If it fails for other reasons → attempt to resolve, but do not spend more than 2 attempts before asking the user for help

### Step 3: Identify Top 10 Most Critical Contracts

Analyze the codebase and select the 10 most critical contracts for mutation testing. **Exclude interfaces, libraries, and abstract contracts that have no standalone logic.**

**Always read each candidate .sol file** to confirm the actual `contract` declaration name — it may differ from the file name (e.g. `KiteOFTWithPausable.sol` declares `contract Kite`).

**Criticality ranking criteria (highest to lowest):**
1. **Fund custody** — contracts that hold or transfer tokens/ETH (staking, vaults, treasuries)
2. **Token contracts** — ERC20/ERC721/OFT implementations, wrapped tokens
3. **Access control hubs** — factories, registries, managers with admin functions
4. **Bridge/cross-chain** — adapters, messengers, cross-chain token contracts
5. **Reward/distribution** — reward calculators, airdrop, vesting
6. **Account abstraction** — smart accounts, wallets
7. **Governance** — voting, proposals, timelocks
8. **Utility contracts** — helpers with non-trivial logic
9. **Oracle/price feeds** — data providers
10. **Configuration** — initializers, parameter contracts

List the selected contracts with their file paths relative to the repo root before proceeding.

### Step 4: Run Olympix Mutation Test Generator

Build the command using `-p` flags for each contract path:

```bash
olympix generate-mutation-tests -p contracts/path/to/Contract1.sol -p contracts/path/to/Contract2.sol -p contracts/path/to/Contract3.sol ...
```

**Rules:**
- Use the **file path** (not the contract name) for each `-p` argument
- Paths should be relative to the repo root
- Maximum 10 contracts per run

Report the session ID and output to the user.

## Quick Reference

| Step | Command / Action | Gate |
|------|-----------------|------|
| 1 | `forge build` | Must compile |
| 2 | Init repo per README | Only if Step 1 fails |
| 3 | Identify top 10 contracts | — |
| 4 | `olympix generate-mutation-tests -p ... -p ...` | Final output |

## Common Issues

| Problem | Solution |
|---------|----------|
| `forge build` fails with missing imports | Install deps per README (`forge install`, `npm install --legacy-peer-deps`, etc.) |
| Versioned import paths (e.g. `@openzeppelin/contracts@5.0.2/`) | Add remapping: `@openzeppelin/contracts@5.0.2/=node_modules/@openzeppelin/contracts/` |
| npm deps have peer conflicts | Use `npm install --legacy-peer-deps`; install transitive deps manually if needed |
| Contract path wrong | Verify the path exists with `ls`; use relative path from repo root |

## Troubleshooting Log

Real-world issues encountered during skill usage, logged for future reference.

### DeFi Saver (defisaver-v3-contracts) — 2026-03-25

**Repo characteristics:** 938 Solidity files, `src = 'contracts'`, solc 0.8.24, optimizer enabled with 10000 runs.

**Key finding: `forge test --via-ir` is NOT a prerequisite.** Despite `forge test --via-ir` failing with stack-too-deep locally (Yul error referencing `var_tokenAddr`, expression 133900), the Olympix CLI successfully accepted the mutation test generation request. The CLI handles viaIR compilation server-side.

**What we originally got wrong:** The skill initially gated on `forge test --via-ir` passing locally. This would have incorrectly blocked mutation test generation for this 938-file repo. The actual gate is just `forge build` — confirm the source code and deps are valid.

**Result:** Session `acab03b5-61d1-481b-8318-56db37eeb3a9` started successfully with 10 contracts selected.
