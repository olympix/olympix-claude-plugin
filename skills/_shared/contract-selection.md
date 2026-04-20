# Contract Selection Criteria

## Rules

- **Exclude** interfaces, libraries, and abstract contracts that have no standalone logic.
- **Always read each candidate .sol file** to confirm the actual `contract` declaration name — it may differ from the file name (e.g., `FooWithFeature.sol` may declare `contract Foo`).
- Verify with `grep "^contract \|^abstract contract \|^library " path/to/Contract.sol` before selecting.

## Criticality Ranking (highest to lowest)

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

## Limits

| Tool | Max Contracts |
|------|---------------|
| Mutation tests | 10 |
| Fuzz tests | 3 |
| Unit tests | 10 |
