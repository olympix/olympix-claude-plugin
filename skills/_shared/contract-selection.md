# Contract Selection Criteria

## Rules

- **Exclude** interfaces, libraries, and abstract contracts that have no standalone logic.
- **Always read each candidate .sol file** to confirm the actual `contract` declaration name — it may differ from the file name (e.g., `FooWithFeature.sol` may declare `contract Foo`).
- Verify with `grep "^contract \|^abstract contract \|^library " path/to/Contract.sol` before selecting.

## Criticality Ranking (highest to lowest)

1. **Fund custody** — contracts that hold or transfer tokens/ETH (staking, vaults, treasuries)
2. **Token contracts** — ERC20/ERC721/OFT implementations, wrapped tokens
3. **Core protocol logic** — main protocol contracts with complex state transitions
4. **Access control hubs** — factories, registries, managers with admin functions
5. **Bridge/cross-chain** — adapters, messengers, cross-chain token contracts
6. **Reward/distribution** — reward calculators, airdrop, vesting
7. **Account abstraction** — smart accounts, wallets
8. **Governance** — voting, proposals, timelocks
9. **Utility contracts** — helpers with non-trivial logic
10. **Oracle/price feeds** — data providers
11. **Configuration** — initializers, parameter contracts

## Limits

| Tool | Max Contracts |
|------|---------------|
| Mutation tests | 10 (plugin convention — the CLI itself accepts up to 100 `-p` paths) |
| Unit tests | 10 (test files total, including pre-existing Opix files) |
