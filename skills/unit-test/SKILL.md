---
name: unit-test
description: >
  Scaffolds Olympix unit test templates for a Foundry-based Solidity repo.
  Verifies forge coverage compatibility, creates OpixUnitTests base contract and
  test files for the top 10 most critical contracts, adds setup functions, then
  runs olympix generate-unit-tests. Use when preparing a repo for Olympix unit
  test generation.
  TRIGGER: "scaffold tests", "unit test", "generate unit tests", "opix tests", "test generation setup", "unit-test"
tools: Read, Glob, Grep, Bash, Agent
---

# Unit Test Generation

Prepare a Foundry-based Solidity repository for Olympix unit test generation by scaffolding test templates, verifying forge coverage compatibility, and running the generator.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## Process

### Step 0: Verify Olympix Authentication

Follow the `auth` skill to check authentication and automate login via Gmail if needed. If Gmail MCP is not connected, fall back to asking the user to run `! olympix login -e email` manually.

### Step 1: Verify Forge Coverage Compatibility

Run forge coverage to check the repo is set up correctly:

```bash
forge coverage --ir-minimum --allow-failure
```

**If it succeeds:** proceed to Step 3.

**If it fails with build/dependency errors:** go to Step 2.

**If it fails with "stack too deep" even with `--ir-minimum --allow-failure`:** This may be a **repo-wide** or **localized** problem. Determine which:

1. **Identify the offending contract** from the Yul error (variable names in the error trace hint at which contract/library, e.g. `var_remainingBalanceOwnerThreshold` -> `ValidatorMessages`)
2. **Trace the import chain** — find which contracts import the offending one (directly or transitively)
3. **If ALL or most critical contracts depend on the offending contract** -> **HARD STOP.** The repo is incompatible.
4. **If only SOME contracts depend on it** -> those contracts cannot have test scaffolds. Exclude them from the top 10, replace with the next most critical contracts that don't pull in the offending code, and proceed.

After excluding, re-run `forge coverage --ir-minimum --allow-failure` to confirm the problem is resolved before proceeding.

> **HARD STOP rules (when the problem is repo-wide):**
>
> - Do NOT check if `forge build` works — irrelevant. Coverage requires viaIR; build does not.
> - Do NOT proceed with "just scaffolding" — the generated tests cannot be validated without coverage.
> - Do NOT reason that "the stack-too-deep only affects coverage mode" — coverage mode IS the requirement.
> - Do NOT create any test files, setUp functions, or run the generator.
>
> The only valid next action is to tell the user: "This repo has a stack-too-deep error under `forge coverage --ir-minimum --allow-failure`. Olympix unit test generation requires working coverage. No further steps can be taken."

**Key lesson: `src` in foundry.toml controls what gets compiled.** If `src = "contracts"`, forge compiles ALL contracts under viaIR including ones no test imports. If `src = "src"` (or a non-existent/empty dir), forge only compiles what tests transitively import. This distinction matters — changing `src` to include all contracts can INTRODUCE stack-too-deep errors that weren't there before. Prefer keeping the original `src` value and letting test imports drive compilation.

### Step 2: Initialize Repository

If forge coverage failed due to missing dependencies or configuration:

1. Read the project's README for setup instructions
2. Run the recommended initialization steps (e.g., `forge install`, `npm install`, `git submodule update --init --recursive`)
3. If there's a `remappings.txt` or the `foundry.toml` references remappings, verify they resolve
4. Re-run `forge coverage --ir-minimum --allow-failure`
5. If it still fails with "stack too deep" -> follow the localized-vs-repo-wide triage from Step 1
6. If it fails for other reasons -> attempt to resolve, but do not spend more than 2 attempts before asking the user for help

### Step 3: Detect Solidity Version

Determine the pragma version to use for test files:

1. Check `foundry.toml` for a `solc_version` setting
2. If not set, scan `pragma solidity` across contracts:
   ```bash
   grep -r "pragma solidity" contracts/ src/ --include="*.sol" | head -20
   ```
3. Use the **most common** pragma version found in the in-scope contracts
4. If there's a mix (e.g., `^0.8.28` and `0.8.25`), prefer the caret version that covers the most contracts

Record this as `{SOLC_PRAGMA}` for use in templates.

### Step 4: Create Base Test Contract

Determine the test directory (usually `test/`). Create the base contract:

**`test/OpixUnitTests.sol`:**
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity {SOLC_PRAGMA};

import "forge-std/Test.sol";

//Olympix Test Generation
abstract contract OlympixUnitTest is Test {
    constructor(string memory name_) {}
}
```

### Step 5: Identify Top 10 Most Critical Contracts

Analyze the codebase and select the 10 most critical contracts to generate tests for. **Exclude interfaces, libraries, abstract contracts, and contracts that transitively import a stack-too-deep offender (identified in Step 1).**

**CRITICAL: The Olympix CLI requires CONCRETE contracts.** Libraries and abstract contracts cannot be passed to `OlympixUnitTest("...")` — the CLI will fail with `Contract 'X' not found`. If a critical contract is abstract or a library:
- Find a **concrete contract** that inherits from it (e.g., `OETHHarvesterSimple` instead of `AbstractHarvester`)
- Or find a **mock** in the repo (e.g., `MockVault` instead of `VaultCore` if VaultCore is abstract)
- Always verify with `grep "^contract \|^abstract contract \|^library " path/to/Contract.sol` before selecting

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

List the selected contracts with their import paths before creating files.

**IMPORTANT: Maximum 10 test files total.** The Olympix CLI enforces a limit of 10 test files per `generate-unit-tests` run. If the repo already has existing Opix test files (e.g. from a prior run), count those first and only create enough new ones to reach 10 total. Drop the least critical candidates if needed.

### Step 6: Create Test Template Files

For each selected contract, create a test file following **THIS EXACT PATTERN — NO DEVIATIONS:**

**`test/Opix{ContractName}Test.t.sol`:**
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity {SOLC_PRAGMA};

import {OlympixUnitTest} from "test/OpixUnitTests.sol";
import {{ContractName}} from "{contract_import_path}";

//Olympix Test Generation
contract Olympix{ContractName}UnitTest is OlympixUnitTest("{ContractName}") {
}
```

> **CRITICAL — the Olympix CLI uses the string in `OlympixUnitTest("...")` to find the contract.**
>
> - The test contract MUST extend `OlympixUnitTest("{ContractName}")` — NOT `OlympixUnitTest` without the string, NOT `OpixUnitTests` directly, NOT `Test` directly.
> - Do NOT add a constructor to the test contract. Only the base `OpixUnitTests.sol` has one.
> - Do NOT add setUp functions, imports, state variables, or any other code at this step. Only the bare template above.
> - Do NOT rename the pattern or use a different inheritance structure.
>
> **If the test does not pass the contract name string to `OlympixUnitTest("...")`, the Olympix CLI will fail.**

**Common mistakes that BREAK generation:**
```solidity
// WRONG — missing contract name string
contract OpixRHTokenTest is OpixUnitTests {

// WRONG — wrong base contract name
contract OpixRHTokenTest is OlympixUnitTest {

// WRONG — added constructor (only base has this)
contract OlympixRHTokenUnitTest is OlympixUnitTest("RHToken") {
    constructor(string memory name_) {}
}

// CORRECT
contract OlympixRHTokenUnitTest is OlympixUnitTest("RHToken") {
}
```

**Naming rules:**
- File: `Opix{ContractName}Test.t.sol`
- Contract: `Olympix{ContractName}UnitTest`
- String in `OlympixUnitTest("...")`: must be the **actual `contract` declaration name** inside the .sol file, NOT the file name. These can differ (e.g. `KiteOFTWithPausable.sol` declares `contract Kite`). The Olympix CLI uses this string to locate the contract — if it doesn't match, generation fails with `Contract '...' not found`.

**Always read the target .sol file** to confirm the contract name before writing the test.

### Step 7: Verify Forge Coverage (Checkpoint)

Run forge coverage again to ensure the new test files don't break compilation:

```bash
forge coverage --ir-minimum --allow-failure
```

**If it fails:** diagnose the issue. Common problems:
- Import path wrong -> fix the import
- Contract name doesn't match file name -> read the file to find the actual `contract Foo` declaration
- Solc version mismatch -> adjust pragma
- Missing constructor args for inherited contracts -> the test template may need adjustment
- **Stack-too-deep from a newly added test** -> that test transitively imports an offending contract. Remove it, replace with next-best candidate, re-run
- Remove any test file that causes unresolvable compilation errors and note it for the user

**Do not proceed until coverage runs without compilation errors.**

### Step 8: Add Setup Functions

For each test contract, add a `setUp()` function that **actually deploys and initializes the contract with working dependencies**. A good setUp makes the difference between useful generated tests and useless ones.

#### 8a. Research the Existing Test Setup

Before writing setUp, **study the repo's existing test infrastructure** to understand how contracts are deployed:

1. **Check for existing Foundry tests**: Look for `*.t.sol` files with setUp patterns. These are the most directly reusable — copy deployment patterns from existing setUp functions.
2. **Check for Foundry deploy scripts**: Look in `script/` for `*.s.sol` files. These show the real deployment order, constructor args, and initialization params.
3. **Check for mock contracts**: Look in `contracts/mocks/`, `test/mocks/`, `src/test/`. Existing mocks are gold — they handle interface requirements correctly.
4. **Check for JS/TS test fixtures** (Hardhat/mixed repos): If the repo has a Hardhat setup alongside Foundry (or was converted from Hardhat), look for `_fixture.js`, `_fixture-*.js`, `test/helpers/`, `deploy/` scripts. These show constructor args, initialization params, and dependency chains even though they're in JS.
5. **Check deploy scripts**: `deploy/`, `migrations/` — these show the real deployment order and initialization params regardless of framework.

#### 8b. Handle Governance/Access Control Patterns

Many DeFi contracts use custom governance with assembly-based storage slots (not OpenZeppelin Ownable). The `onlyGovernor` modifier blocks `initialize()` unless the caller is the governor.

**Pattern: Assembly-stored governance (e.g., Origin Protocol's `Governable.sol`):**
```solidity
// Add helper to base test contract:
bytes32 internal constant GOVERNOR_SLOT =
    0x7bea13895fa79d2831e0a9e28edede30099005a50d652d8957cf8a607ee6ca4a;

function _setGovernor(address target, address governor) internal {
    vm.store(target, GOVERNOR_SLOT, bytes32(uint256(uint160(governor))));
}
```

**Pattern: OpenZeppelin Ownable:**
```solidity
// Deploy with the right msg.sender
vm.startPrank(admin);
target = new MyContract();
vm.stopPrank();
```

**Pattern: Initializable + Governance (e.g., proxy-based contracts):**
```solidity
target = new MyContract(constructorArgs);
_setGovernor(address(target), governor);
vm.prank(governor);
target.initialize(initArgs);
```

#### 8c. Deploy Dependencies First

Most contracts need other contracts deployed first. Follow this order:

1. **Mock tokens** (ERC20s) — deploy these first since everything depends on them
2. **Vault/Core contracts** — deploy and initialize
3. **Oracle/Price feeds** — deploy with reasonable default prices
4. **Strategy contracts** — deploy with references to vault, tokens, and protocol mocks
5. **Peripheral contracts** (harvesters, drippers) — deploy last

#### 8d. Create Minimal Mock Contracts for External Protocols

When a contract interacts with external protocols (Curve, Uniswap, Aerodrome, etc.), create **minimal inline mocks** in the test file that implement only the interface methods the constructor/setUp needs:

```solidity
// Minimal mock for an AMM pool — just enough for constructor validation
contract MockPool {
    address public token0;
    address public token1;
    constructor(address _t0, address _t1) { token0 = _t0; token1 = _t1; }
    function getReserves() external pure returns (uint256, uint256, uint256) {
        return (1000e18, 1000e18, block.timestamp);
    }
}
```

**Key principles for inline mocks:**
- Only implement functions called during constructor + initialize + setUp
- Return reasonable non-zero values (1e18 for prices, 1000e18 for reserves)
- If a constructor does `require(pool.token0() == weth)`, the mock must return the right address

#### 8e. Full Example (Complex DeFi Protocol)

```solidity
contract OlympixVaultCoreUnitTest is OlympixUnitTest("VaultCore") {
    MockVault public vault;   // Concrete mock that inherits VaultAdmin > VaultCore
    MockWETH public weth;
    OUSD public oToken;

    address public governor = address(0x1);
    address public strategist = address(0x2);
    address public user = address(0x3);

    function setUp() public {
        // 1. Deploy tokens
        weth = new MockWETH();

        // 2. Deploy vault (uses existing MockVault from contracts/mocks/)
        vault = new MockVault(address(weth));
        _setGovernor(address(vault), governor);

        // 3. Deploy and link token
        oToken = new OUSD();
        _setGovernor(address(oToken), governor);

        // 4. Initialize everything as governor
        vm.startPrank(governor);
        vault.initialize(address(oToken));
        vault.unpauseCapital();
        vault.setStrategistAddr(strategist);
        oToken.initialize(address(vault), 1e18);
        vm.stopPrank();

        // 5. Fund test user
        weth.mint(10000 ether);
        weth.transfer(user, 1000 ether);
        vm.prank(user);
        weth.approve(address(vault), type(uint256).max);
    }
}
```

#### 8f. Guidelines

- **Prefer existing mocks** from `contracts/mocks/` over writing new ones — they handle edge cases
- Use `vm.store()` to set governance storage slots when the contract uses assembly-based access control
- Use `vm.startPrank` / `vm.stopPrank` for deployer/governor context
- Use `deal()` to fund addresses that need ETH/tokens
- For struct constructor args, import the parent contract and use fully qualified names (e.g., `InitializableAbstractStrategy.BaseStrategyConfig({...})`)
- For contracts that validate constructor args (e.g., `require(pool.token0() == weth)`), ensure mocks return the expected values
- **Test that setUp doesn't revert** by running `forge coverage --ir-minimum --allow-failure` after adding setUp functions
- If a contract is too complex to set up without extensive mocking, add a comment `// TODO: requires mock contracts for full setup` and leave a simpler partial setup

### Step 9: Verify Forge Coverage (Final Check)

Run forge coverage one more time:

```bash
forge coverage --ir-minimum --allow-failure
```

**If it fails after adding setUp functions:** simplify the setUp that caused the failure. Comment out complex parts rather than removing the entire file.

### Step 10: Run Olympix Unit Test Generator

Once forge coverage passes cleanly:

```bash
olympix generate-unit-tests -ca
```

This runs the unit test generator against all contracts (`-ca`).

Report the output to the user.

## Quick Reference

| Step | Command / Action | Gate |
|------|-----------------|------|
| 1 | `forge coverage --ir-minimum --allow-failure` | Must pass (or fixable) |
| 2 | Init repo per README | Only if Step 1 fails |
| 3 | Detect `{SOLC_PRAGMA}` | — |
| 4 | Create `test/OpixUnitTests.sol` | — |
| 5 | Identify top 10 contracts | — |
| 6 | Create 10 test templates | — |
| 7 | `forge coverage --ir-minimum --allow-failure` | Must compile cleanly |
| 8 | Add `setUp()` functions | — |
| 9 | `forge coverage --ir-minimum --allow-failure` | Must compile cleanly |
| 10 | `olympix generate-unit-tests -ca` | Final output |

## Common Issues

| Problem | Solution |
|---------|----------|
| "stack too deep" — all contracts affected | **HARD STOP** — repo is incompatible. Do not scaffold, do not check `forge build`, do not proceed in any way. |
| "stack too deep" — localized to specific contracts | Identify offending contract from Yul error, trace import chain, exclude affected tests, replace with next-best candidates |
| Changing `src` in foundry.toml introduces stack-too-deep | Don't change `src` to include all contracts. Keep original value — let test imports drive what gets compiled under viaIR |
| Contract name != file name (e.g. `Kite` in `KiteOFTWithPausable.sol`) | Read the file to find the actual `contract` declaration name; use that in the import |
| Import path not found | Check `remappings.txt` and `foundry.toml` lib paths |
| npm deps have peer conflicts | Use `npm install --legacy-peer-deps`; install transitive deps manually if needed (e.g. `@layerzerolabs/oapp-evm` -> `@layerzerolabs/lz-evm-protocol-v2`) |
| Versioned import paths (e.g. `@openzeppelin/contracts@5.0.2/`) | Add remapping: `@openzeppelin/contracts@5.0.2/=node_modules/@openzeppelin/contracts/` |
| Solc version conflict between contracts | Use the broadest caret pragma that covers all imported contracts (e.g. `^0.8.25` covers both `0.8.25` exact and `^0.8.28`) |
| `Contract 'X' not found` from olympix CLI | The string in `OlympixUnitTest("X")` doesn't match the actual `contract` name in the .sol file. Read the file and use the real name. |
| `Too many test files selected (N). Maximum allowed is 10` | Remove the least critical test file(s) to stay at 10 total |
| setUp too complex | Leave partial setup with TODO comments |
| Contract needs constructor args you can't determine | Use zero/empty defaults, add TODO comment |
| Abstract contract passed to `OlympixUnitTest("X")` | CLI will fail. Find a concrete contract that inherits from it, or a mock (e.g., `MockVault` for `VaultCore`). Verify with `grep "^contract \|^abstract contract \|^library "` |
| Library passed to `OlympixUnitTest("X")` | Libraries can't be instantiated. Find a contract that uses the library, or replace with a different contract |
| `onlyGovernor` blocks `initialize()` | Use `vm.store()` to set the governance storage slot before calling initialize. Find the slot by reading the Governable contract (often `keccak256("OUSD.governor")` or similar) |
| Constructor validates external contract state (e.g., `require(pool.token0() == weth)`) | Create inline mock contracts that return the expected values from their view functions |
| pnpm/npm install fails with SSH key errors for GitHub dependencies | Remove the SSH-only deps from `package.json` if they're JS tools not needed for Solidity compilation (e.g., `ssv-scanner`, `ssv-keys`). Restore after install |
| Hardhat project with no `foundry.toml` | Create one: set `src = "contracts"`, `libs = ["node_modules", "lib"]`, add remappings for `@openzeppelin/`, `@chainlink/`, etc. Install `forge-std` with `forge install foundry-rs/forge-std --no-git`. Enable `via_ir = true` if stack-too-deep |
| Test generator Docker fails with "Undeclared identifier" on coverage | The contract compiles with optimizer but fails without it (coverage disables optimizer). Variables declared in modifiers may not be visible in function bodies without optimizer. This is a known test-generator limitation — exclude the affected contract |

## Troubleshooting Log

Real-world issues encountered during skill usage, logged for future reference.

### Kite Protocol (contracts-external) — 2026-03-25

**Repo characteristics:** Mixed pragma versions (`0.8.25` exact for validator-manager, `^0.8.28` for aa/airdrop, `^0.8.0` for token, `^0.4.18` for WKITE). Dependencies via npm (not forge install). Versioned import paths (`@openzeppelin/contracts@5.0.2/`).

**Issues hit and resolutions:**

1. **Missing dependencies** — `foundry.toml` had `libs = ["lib"]` but deps were in `node_modules/`. Fixed by adding `node_modules` to libs and creating `remappings.txt` with entries for `@openzeppelin/contracts@5.0.2/`, `@layerzerolabs/`, `@account-abstraction/`.

2. **Transitive npm deps missing** — `@layerzerolabs/oft-evm` needed `@layerzerolabs/oapp-evm` which needed `@layerzerolabs/lz-evm-protocol-v2`. Had to install each manually.

3. **npm peer conflicts** — Required `--legacy-peer-deps` flag.

4. **Pragma mismatch** — Initial tests used `^0.8.28` but validator-manager contracts use exact `0.8.25`. Fixed by using `^0.8.25` for all test files.

5. **WKITE incompatible** — `pragma solidity ^0.4.18` cannot coexist with `^0.8.x` test files. Replaced with `GokiteAccountFactory`.

6. **Contract name != file name** — `KiteOFTWithPausable.sol` declares `contract Kite`, not `contract KiteOFTWithPausable`. Import failed until fixed.

7. **Localized stack-too-deep** — `ValidatorMessages.sol` (a library with complex byte packing) caused Yul stack-too-deep under viaIR. It was pulled in transitively by `StakingManager` and `ValidatorManager`. Removed tests for `KiteStakingManager`, `StakingManager`, `ValidatorManager`; replaced with `Subnet`, `SubnetRegistry`, `TokenCallbackHandler`.

8. **`src` in foundry.toml** — Changing from `src = "src"` to `src = "contracts"` forced ALL contracts to compile under viaIR, triggering the stack-too-deep. Reverting to `src = "src"` meant only test-imported contracts compiled, avoiding the issue.

9. **Constructor string must match contract name** — `OlympixUnitTest("KiteOFTWithPausable")` failed because the file `KiteOFTWithPausable.sol` declares `contract Kite`. Fixed by changing to `OlympixUnitTest("Kite")`. The Olympix CLI uses this string to find the contract.

10. **Max 10 test files** — The Olympix CLI enforces a hard limit of 10 test files per run. We had 11 (1 pre-existing + 10 new). Removed the least critical (`TokenCallbackHandler`) to fit under the limit.

### Origin Dollar (origin-dollar) — 2026-03-26

**Repo characteristics:** Hardhat-based project (no Foundry), pnpm workspace, Solidity 0.8.28, extensive mock contracts in `contracts/mocks/`, proxy pattern with assembly-based governance (`Governable.sol`), multi-chain (Ethereum, Base, Sonic, Plume). Complex DeFi protocol with vaults, AMO strategies (Curve, Aerodrome, SwapX), harvesters, drippers, and cross-chain CCTP bridges.

**Issues hit and resolutions:**

1. **Hardhat-to-Foundry conversion** — No `foundry.toml` existed. Created one with `src = "contracts"`, `libs = ["node_modules", "lib"]`, `solc_version = "0.8.28"`, `via_ir = true`, and remappings for `@openzeppelin/`, `@chainlink/contracts-ccip/`, `@layerzerolabs/`, `hardhat/`, `forge-std/`. Installed `forge-std` via `forge install foundry-rs/forge-std --no-git`.

2. **pnpm install SSH failures** — Two dependencies (`ssv-scanner`, `ssv-keys`) used `github:` SSH URLs that failed without SSH keys. Removed both from `package.json` (they're JS tools, not needed for Solidity compilation), ran `pnpm install --ignore-workspace --no-frozen-lockfile`, then restored `package.json` via `git checkout`.

3. **Stack-too-deep without `via_ir`** — `forge build` failed without `via_ir = true`. Added it to `foundry.toml`. This worked for `forge build` and `forge coverage --ir-minimum`, but the test-generator Docker container (which runs its own forge) had issues (see #8).

4. **Abstract contracts and libraries selected as test targets** — Initial contract analysis picked `AbstractHarvester` (abstract), `AbstractCCTPIntegrator` (abstract), and `BeaconProofsLib` (library). The Olympix CLI fails with `Contract 'X' not found` for these. Replaced with concrete implementations: `OETHHarvesterSimple`, `CrossChainRemoteStrategy`, `Dripper`.

5. **Assembly-based governance blocks initialize()** — Origin uses `Governable.sol` with `keccak256("OUSD.governor")` stored via assembly at slot `0x7bea13895fa79d2831e0a9e28edede30099005a50d652d8957cf8a607ee6ca4a`. Added `_setGovernor()` helper to base test contract using `vm.store()`.

6. **Constructor validation against external contracts** — AMO strategies validate constructor args against pool contracts (e.g., `require(ICLPool(_clPool).token0() == _wethAddress)`). Required creating inline mock contracts that return the expected addresses from their view functions.

7. **Rich setUp using existing mocks** — The repo had excellent mocks in `contracts/mocks/` (`MockVault`, `MockWETH`, `MockUSDC`, `MockOracleRouter`, `CCTPMessageTransmitterMock`, `CCTPTokenMessengerMock`, `MockERC4626Vault`). Studied the JS test fixtures (`_fixture.js`, `_fixture-base.js`, `_fixture-sonic.js`) and deploy scripts to understand initialization order and constructor args. This produced setUp functions that actually deploy and initialize contracts with working dependencies.

8. **Test-generator Docker failure: `CurveAMOStrategy.sol` undeclared identifier** — The `improvePoolBalance` modifier declares `int256 diffBefore` which is used in function bodies via the `_` placeholder. This compiles with optimizer enabled but fails without optimizer (which `forge coverage` uses for accurate source maps). The test-generator Docker container runs a nightly forge that: (a) runs coverage without `--ir-minimum`, gets stack-too-deep; (b) retries with `--ir-minimum`, but stderr contains a nightly forge warning that the error-parsing code treats as a failure; (c) falls back to the non-ir path again, hitting the `diffBefore` compilation error. This is a known test-generator bug — the nightly forge warning poisons the stderr check.

9. **Base test contract naming** — The Olympix CLI expects the base contract to be named `OlympixUnitTest` (not `OpixUnitTests`). The file can be named anything but the contract declaration must be `abstract contract OlympixUnitTest is Test`.
