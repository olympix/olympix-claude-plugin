# Forge Setup (Shared Prerequisites)

## Verify Repository Builds

```bash
forge build
```

**If it succeeds:** proceed to the next step.

**If it fails with dependency errors:** initialize the repository (see below).

**If it cannot be fixed after 2 attempts:** **HARD STOP.** Ask the user for help.

## Initialize Repository

If `forge build` failed due to missing dependencies or configuration:

1. Read the project's README for setup instructions
2. Run the recommended initialization steps (e.g., `forge install`, `npm install --legacy-peer-deps`, `git submodule update --init --recursive`)
3. If there's a `remappings.txt` or the `foundry.toml` references remappings, verify they resolve
4. Re-run `forge build`
5. If it still fails, attempt to resolve but do not spend more than 2 attempts before asking the user for help

## Common Build Issues

| Problem | Solution |
|---------|----------|
| Missing imports | Install deps per README (`forge install`, `npm install --legacy-peer-deps`, etc.) |
| Versioned import paths (e.g. `@openzeppelin/contracts@5.0.2/`) | Add remapping: `@openzeppelin/contracts@5.0.2/=node_modules/@openzeppelin/contracts/` |
| npm peer conflicts | Use `npm install --legacy-peer-deps`; install transitive deps manually if needed |
| Hardhat project with no `foundry.toml` | Create one: set `src = "contracts"`, `libs = ["node_modules", "lib"]`, add remappings. Install `forge-std` with `forge install foundry-rs/forge-std --no-git` |
