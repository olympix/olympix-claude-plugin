# Olympix Claude Plugin

Olympix is a smart contract security analysis platform that runs static analysis with 100+ vulnerability detectors, generates mutation tests, fuzz tests, and unit tests, and produces proof-of-concept exploits via BugPocer. This plugin lets you run all Olympix tools directly from Claude Code using agent mode for fully automated JSONL interaction.

## Prerequisites

- **Olympix CLI** -- verify with `olympix --version`. Install from [docs.olympix.ai/cli](https://docs.olympix.ai/cli)
- **Foundry/Forge** -- verify with `forge --version`. Install from [getfoundry.sh](https://getfoundry.sh)
- **Claude Code** -- the AI coding assistant this plugin extends

## Installation

### Quick start

```bash
git clone https://github.com/olympix/olympix-claude-plugin.git
cd olympix-claude-plugin
scripts/setup.sh
```

The setup script checks prerequisites, creates a marketplace wrapper, registers the plugin with Claude Code, and adds CLI permissions. Restart Claude Code after running it.

### Manual install

1. Clone this repo
2. Create a marketplace wrapper (sibling directory):
   ```bash
   PLUGIN_DIR="$(pwd)/olympix-claude-plugin"
   MARKETPLACE_DIR="$(pwd)/olympix-plugin-marketplace"

   mkdir -p "$MARKETPLACE_DIR/.claude-plugin"
   ln -s "$PLUGIN_DIR" "$MARKETPLACE_DIR/olympix-claude-plugin"

   cat > "$MARKETPLACE_DIR/.claude-plugin/marketplace.json" << 'EOF'
   {
     "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
     "name": "olympix",
     "description": "Olympix smart contract security tools for Claude Code",
     "owner": { "name": "Olympix", "email": "engineering@olympix.ai" },
     "plugins": [
       {
         "name": "olympix-claude-plugin",
         "description": "Run Olympix security tools from Claude Code",
         "source": "./olympix-claude-plugin",
         "category": "development"
       }
     ]
   }
   EOF
   ```

3. Add to your Claude Code settings (`~/.claude/settings.json`):
   ```json
   {
     "enabledPlugins": { "olympix-claude-plugin@olympix": true },
     "extraKnownMarketplaces": {
       "olympix": {
         "source": { "source": "directory", "path": "/absolute/path/to/olympix-plugin-marketplace" }
       }
     },
     "permissions": {
       "allow": ["Bash(olympix:*)", "Bash(forge:*)"]
     }
   }
   ```

4. Restart Claude Code.

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
5. Generate unit tests with coverage scaffolding
6. Run BugPocer security analysis (fully automated)
7. Optionally generate fuzz tests for the top 3 most critical contracts
8. Wait for async results and download them directly
9. Assemble all results into `olympix-results/report.md`

## Available skills

| Skill | Description |
|-------|-------------|
| `olympix:full-run` | Run all Olympix tools on a Foundry repo |
| `olympix:static-analysis` | Run vulnerability scanner |
| `olympix:mutation-test` | Generate mutation tests for top 10 contracts |
| `olympix:fuzz-test` | Generate fuzz tests for top 3 contracts |
| `olympix:unit-test` | Generate unit tests with coverage scaffolding |
| `olympix:bug-pocer` | Run BugPocer security analysis (fully automated) |
| `olympix:assemble-report` | Collect results into `olympix-results/report.md` |
| `olympix:auth` | Check/refresh CLI authentication |

## How results work

- **Static analysis** runs synchronously — results are immediate.
- **Mutation tests and unit tests** dispatch async jobs. Results are downloaded directly via agent mode when complete — no need to check email.
- **BugPocer** runs fully automated via agent mode — scope review, validation, questions, scan, and findings retrieval all happen programmatically.
- **Fuzz tests** are the only tool that does NOT support agent mode. Results arrive via email.

All results auto-persist to `.opix/agent/` inside the workspace directory.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `olympix` not found | Install CLI: https://docs.olympix.ai/cli |
| Auth expired | Run `olympix:auth` or `! olympix login -e your@email.com` |
| `forge build` fails | Install dependencies per project README |
| Stack-too-deep | Some contracts incompatible with unit test coverage mode |
| Fuzz `--agent` error | Agent mode not supported for fuzz tests — run without `--agent` |
