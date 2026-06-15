# Build Setup (Shared Prerequisites)

Olympix supports both **Foundry** and **Hardhat** projects — the CLI auto-detects the
project type, so tool invocation is identical either way. Only the local compile gate
differs: detect the project type, then build with the matching tool.

## Detect Project Type

| Marker at repo root | Type | Build command |
|---------------------|------|---------------|
| `foundry.toml` | Foundry | `forge build` |
| `hardhat.config.js` / `.ts` / `.cjs` / `.mjs` | Hardhat | `npx hardhat compile` (or the project's own script, e.g. `npm run compile` / `npm run build`) |
| Both present | Foundry-first | Prefer `forge build`; fall back to `npx hardhat compile` if forge cannot be made to pass |

## Verify Repository Builds

Foundry:

```bash
forge build
```

Hardhat:

```bash
npx hardhat compile
```

**If it succeeds:** proceed to the next step.

**If it fails with dependency errors:** initialize the repository (see below).

**If it cannot be fixed after 2 attempts:** **HARD STOP.** Ask the user for help.

## Initialize Repository

If the build failed due to missing dependencies or configuration:

1. Read the project's README for setup instructions
2. Run the recommended initialization steps:
   - Foundry: `forge install`, `git submodule update --init --recursive`
   - Hardhat: `npm install` / `npm ci` / `npm install --legacy-peer-deps` (or `yarn` / `pnpm install`)
3. Foundry only — if there's a `remappings.txt` or the `foundry.toml` references remappings, verify they resolve
4. Re-run the matching build command (`forge build` or `npx hardhat compile`)
5. If it still fails, attempt to resolve but do not spend more than 2 attempts before asking the user for help

## Common Build Issues

| Problem | Solution |
|---------|----------|
| Missing imports | Install deps per README (`forge install`, `npm install --legacy-peer-deps`, etc.) |
| Versioned import paths (e.g. `@openzeppelin/contracts@5.0.2/`) | Add remapping: `@openzeppelin/contracts@5.0.2/=node_modules/@openzeppelin/contracts/` |
| npm peer conflicts | Use `npm install --legacy-peer-deps`; install transitive deps manually if needed |
| Hardhat project (`hardhat.config.*`, no `foundry.toml`) | Build it natively — `npx hardhat compile`. Olympix supports Hardhat; do NOT scaffold a `foundry.toml`. |
| `npx hardhat compile` fails on missing toolchain | Install the configured compiler/plugins per README; Hardhat downloads the solc version from `hardhat.config` on first compile |
