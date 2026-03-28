# Olympix Claude Plugin

Olympix is a smart contract security analysis platform that runs static analysis with 100+ vulnerability detectors, generates mutation tests, fuzz tests, and unit tests, and produces proof-of-concept exploits via BugPocer. This plugin lets you run all Olympix tools directly from Claude Code.

## Prerequisites

- **Olympix CLI** -- verify with `olympix --version`. Install from [docs.olympix.ai/cli](https://docs.olympix.ai/cli)
- **Foundry/Forge** -- verify with `forge --version`. Install from [getfoundry.sh](https://getfoundry.sh)
- **Claude Code** -- the AI coding assistant this plugin extends

## Installation

### Quick start (recommended)

```bash
cd olympix-claude-plugin
scripts/setup.sh
```

The setup wizard checks prerequisites, optionally configures your email, registers the plugin with Claude Code, and adds CLI permissions.

### Manual install

1. Clone this repo alongside your Foundry projects
2. Register the marketplace:
   ```bash
   claude plugins marketplace add /path/to/parent-directory
   ```
3. Install the plugin:
   ```bash
   claude plugins install olympix-claude-plugin@olympix --scope local
   ```

### CLI-bundled (coming soon)

```bash
olympix setup-plugin
```

## Quick start

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

## Optional: Gmail MCP

Connecting Gmail MCP enhances several skills with automation:

- **Login**: Reads verification codes from your inbox automatically
- **Result monitoring**: Detects when async tools (mutation/fuzz/unit tests) complete
- **Report assembly**: Pulls result attachments directly from email

### How to connect

Run `/mcp` in Claude Code and connect `claude.ai Gmail`.

### Without Gmail MCP

All features fall back to manual workflows:
- You enter verification codes yourself during login
- You check your email for results and provide metrics to Claude
- You copy result files manually for report assembly

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `olympix` not found | Install CLI: https://docs.olympix.ai/cli |
| Auth expired | Run `olympix:auth` or `! olympix login -e your@email.com` |
| `forge build` fails | Install dependencies per project README |
| Stack-too-deep | Some contracts incompatible with unit test coverage mode |
| No email results | Check spam; async tools (mutation/fuzz/unit) send results via email |
