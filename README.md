# Olympix Claude Plugin

Olympix is a smart contract security analysis platform that runs static analysis with 100+ vulnerability detectors, generates mutation tests and unit tests, and produces proof-of-concept exploits via BugPocer. This plugin lets you run all Olympix tools directly from Claude Code using agent mode for fully automated JSONL interaction.

## Prerequisites

- **Olympix CLI** -- verify with `olympix version`. Install from [olympix.github.io/installation](https://olympix.github.io/installation/)
- **Foundry/Forge** -- verify with `forge --version`. Install from [getfoundry.sh](https://getfoundry.sh)
- **Claude Code** -- the AI coding assistant this plugin extends

## Installation

### Recommended: install from GitHub

This repo is a self-hosting Claude Code plugin marketplace. Inside Claude Code, run:

```
/plugin marketplace add olympix/olympix-claude-plugin
/plugin install olympix@olympix
```

Then restart Claude Code. That's it — no clone or setup script needed.

> The `olympix/olympix-claude-plugin` shorthand only resolves once the repo is **public**. While it is private, use one of the options below.

### Private / pre-release sharing

The repo self-hosts its `.claude-plugin/marketplace.json`, so you don't need it to be public — you only need the code on the machine, or git access to it.

**If you have GitHub access to the private repo** — use the full git URL so your credentials apply:

```
/plugin marketplace add git@github.com:olympix/olympix-claude-plugin.git
/plugin install olympix@olympix
```

**If you were sent a clone or zip** (no GitHub access needed) — point the marketplace at the local folder:

```bash
git clone <repo-url>          # or unzip what you were sent
```
```
/plugin marketplace add /absolute/path/to/olympix-claude-plugin
/plugin install olympix@olympix
```

Restart Claude Code. Both paths end at the same `olympix@olympix` enable key.

### Fallback: setup script (local clone)

If you can't use the marketplace flow (e.g. air-gapped or developing the plugin itself):

```bash
git clone https://github.com/olympix/olympix-claude-plugin.git
olympix-claude-plugin/scripts/setup.sh
```

The setup script checks prerequisites, creates a local marketplace wrapper, registers the plugin with Claude Code, and adds CLI permissions. Restart Claude Code after running it.

It offers two scopes:

- **Global** — registers the plugin for all projects (`~/.claude/settings.json`). Run it from anywhere.
- **Workspace** — registers the plugin only for the current directory (writes `$PWD/.claude/settings.local.json`). **Run the script from the target project directory** (e.g. `cd ~/my-foundry-project && /path/to/olympix-claude-plugin/scripts/setup.sh`), not from the plugin checkout.

### Manual install

1. Clone this repo
2. Add to your Claude Code settings (`~/.claude/settings.json`), pointing the marketplace at your clone (it ships its own `.claude-plugin/marketplace.json`):
   ```json
   {
     "enabledPlugins": { "olympix@olympix": true },
     "extraKnownMarketplaces": {
       "olympix": {
         "source": { "source": "directory", "path": "/absolute/path/to/olympix-claude-plugin" }
       }
     },
     "permissions": {
       "allow": ["Bash(olympix:*)", "Bash(forge:*)"]
     }
   }
   ```

3. Restart Claude Code.

## Usage

Open Claude Code inside a Foundry or Hardhat project directory and run:

```
/olympix:full-run
```

`full-run` is an **orchestrator**: it runs the fast setup once, then drives each tool skill in order. The recommended SDLC flow:

```
  Static Analysis  →   Unit Tests   →  Mutation Tests  →   BugPocer    →   Report
  find suspected       generate         score how well      confirm         assemble
  vulnerabilities      tests + raise    tests catch real    exploits +      all results
  (100+ detectors)     coverage         bugs (kill score)   produce PoCs
```

This will:
1. Check CLI authentication (login if needed)
2. Detect the project type and run `forge build` (Foundry) or `npx hardhat compile` (Hardhat) to verify it compiles
3. Run static analysis, save findings, and offer to triage them against the source
4. Generate unit tests with coverage scaffolding
5. Generate mutation tests for the top 10 most critical contracts
6. Run BugPocer security analysis (fully automated)
7. Wait for async results (mutation/unit/BugPocer run as background agents) and download them directly
8. Assemble all results into `olympix-results/report.md`

## Available skills

| Skill | Description |
|-------|-------------|
| `olympix:full-run` | Run all Olympix tools on a Foundry or Hardhat repo |
| `olympix:static-analysis` | Run vulnerability scanner |
| `olympix:mutation-test` | Generate mutation tests for top 10 contracts |
| `olympix:unit-test` | Generate unit tests with coverage scaffolding |
| `olympix:bug-pocer` | Run BugPocer security analysis (fully automated) |
| `olympix:assemble-report` | Collect results into `olympix-results/report.md` |
| `olympix:auth` | Check/refresh CLI authentication |

## How results work

- **Static analysis** runs synchronously — results are immediate.
- **Mutation tests and unit tests** dispatch async jobs. Results are downloaded directly via agent mode when complete — no need to check email.
- **BugPocer** runs fully automated via agent mode — scope review, validation, questions, scan, and findings retrieval all happen programmatically.

All results auto-persist to `.opix/agent/` inside the workspace directory.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `olympix` not found | Install CLI: https://olympix.github.io/installation/ |
| Auth expired | Log in from a **separate terminal** (or before starting Claude Code) with `olympix login` (interactive — enter the emailed code; do **not** run it via `!`) |
| `forge build` fails | Install dependencies per project README |
| Stack-too-deep | Some contracts incompatible with unit test coverage mode |
| `--agent` flag rejected / unknown option | Olympix CLI too old — run `olympix update` |
