# Olympix Claude Plugin

Olympix is a smart contract security analysis platform that runs static analysis with 100+ vulnerability detectors, generates mutation tests, fuzz tests, and unit tests, and produces proof-of-concept exploits via BugPocer. This plugin lets you run all Olympix tools directly from Claude Code.

## Prerequisites

- **Olympix CLI** -- verify with `olympix --version`. Install from [docs.olympix.ai/cli](https://docs.olympix.ai/cli)
- **Foundry/Forge** -- verify with `forge --version`. Install from [getfoundry.sh](https://getfoundry.sh)
- **Claude Code** -- the AI coding assistant this plugin extends

## Installation

### Quick start

```bash
cd olympix-claude-plugin
scripts/setup.sh
```

The setup script checks prerequisites, registers the plugin with Claude Code, and adds CLI permissions.

### Manual install

1. Clone this repo
2. Create a marketplace wrapper (sibling directory):
   ```bash
   mkdir -p /path/to/olympix-plugin-marketplace/.claude-plugin
   ln -s /path/to/olympix-claude-plugin /path/to/olympix-plugin-marketplace/olympix-claude-plugin
   ```
   Add a `marketplace.json` in the `.claude-plugin/` directory (see `scripts/setup.sh` for the full content).

3. Add to your Claude Code settings (`~/.claude/settings.json`):
   ```json
   {
     "enabledPlugins": { "olympix-claude-plugin@olympix": true },
     "extraKnownMarketplaces": {
       "olympix": {
         "source": { "source": "directory", "path": "/path/to/olympix-plugin-marketplace" }
       }
     },
     "permissions": {
       "allow": ["Bash(olympix:*)", "Bash(forge:*)"]
     }
   }
   ```

## Usage

Open Claude Code inside a Foundry project directory and run:

```
/olympix:full-run
```

This will:
1. Check CLI authentication (login if needed)
2. Run `forge build` to verify the project compiles
3. Run static analysis and save findings
4. Generate mutation tests for the top 10 most critical contracts
5. Generate fuzz tests for the top 3 most critical contracts
6. Generate unit tests with coverage scaffolding
7. Prompt for BugPocer interactive session
8. Assemble all results into `olympix-results/report.md`

## Available skills

| Skill | Description |
|-------|-------------|
| `olympix:full-run` | Run all Olympix tools on a Foundry repo |
| `olympix:static-analysis` | Run vulnerability scanner |
| `olympix:mutation-test` | Generate mutation tests for top 10 contracts |
| `olympix:fuzz-test` | Generate fuzz tests for top 3 contracts |
| `olympix:unit-test` | Generate unit tests with coverage scaffolding |
| `olympix:bug-pocer` | Launch BugPocer interactive security analysis |
| `olympix:assemble-report` | Collect results into `olympix-results/report.md` |
| `olympix:auth` | Check/refresh CLI authentication |

## How results work

- **Static analysis** runs synchronously — results are immediate.
- **Mutation tests, fuzz tests, and unit tests** are async — results arrive via email. Check your inbox for session results and use `/olympix:assemble-report` to compile the final report.
- **BugPocer** is interactive — run `! olympix bug-pocer` for the TUI session.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `olympix` not found | Install CLI: https://docs.olympix.ai/cli |
| Auth expired | Run `olympix:auth` or `! olympix login -e your@email.com` |
| `forge build` fails | Install dependencies per project README |
| Stack-too-deep | Some contracts incompatible with unit test coverage mode |
| No email results | Check spam; async tools send results via email |
