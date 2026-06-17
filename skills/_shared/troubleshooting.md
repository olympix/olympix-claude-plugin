# Troubleshooting Reference

## Contract Name vs File Name

The actual `contract` declaration name inside a `.sol` file may differ from the file name. Always read the file to confirm.

The Olympix CLI uses the string passed to `OlympixUnitTest("...")` to locate the contract — if it doesn't match the real declaration name, generation fails with `Contract '...' not found`.

## Stack-Too-Deep Under viaIR

When `forge coverage --ir-minimum` fails with stack-too-deep:

1. **Identify the offending contract** from the Yul error (variable names hint at which contract/library)
2. **Trace the import chain** — find which contracts import the offending one (directly or transitively)
3. **If ALL or most critical contracts depend on the offending contract** → HARD STOP
4. **If only SOME contracts depend on it** → exclude those, replace with next-best candidates

**Key insight:** `src` in `foundry.toml` controls what gets compiled. If `src = "contracts"`, forge compiles ALL contracts under viaIR. If `src = "src"` (or the original value), forge only compiles what tests transitively import. Changing `src` can INTRODUCE stack-too-deep errors. Keep the original `src` value.

## `forge test --via-ir` is NOT a Prerequisite for Mutation Tests

The Olympix CLI handles viaIR compilation server-side. Only `forge build` (basic compilation) is required locally.

## Abstract Contracts and Libraries

- Abstract contracts and libraries cannot be passed to `OlympixUnitTest("X")` — the CLI will fail with `Contract 'X' not found`
- Find a concrete contract that inherits from the abstract one, or use a mock
- Libraries can't be instantiated — find a contract that uses the library instead

## Assembly-Based Governance

Many DeFi contracts use custom governance with assembly-based storage slots (not OpenZeppelin Ownable). The `onlyGovernor` modifier blocks `initialize()` unless the caller is the governor.

**Fix:** Use `vm.store()` to set the governance storage slot before calling `initialize()`. Find the slot by reading the Governable contract (often `keccak256("ProjectName.governor")` or similar).

## Constructor Validation Against External Contracts

When a constructor validates external contract state (e.g., `require(pool.token0() == weth)`), create inline mock contracts that return the expected values from their view functions.

## Solidity Version Conflicts

- Check `foundry.toml` for `solc_version`
- Scan `pragma solidity` across contracts to find the most common version
- Use the broadest caret pragma that covers all imported contracts (e.g., `^0.8.25` covers both `0.8.25` exact and `^0.8.28`)
- Very old pragmas (e.g., `^0.4.18`) are incompatible with `^0.8.x` test files — exclude those contracts
