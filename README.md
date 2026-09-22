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
6. Run BugPocer security analysis (automated by default; optional strict review)
7. Wait for async results (mutation/unit/BugPocer run as background agents) and download them directly
8. Assemble all results into `olympix-results/report.md`

### Mutation timeout

For a long test suite, ask: "Run mutation tests with a 3600-second timeout per mutant."
The plugin passes `--timeout 3600` (or `-t 3600`) to `olympix generate-mutation-tests --agent`, including when requested through `full-run`. This controls the test-suite runtime per mutant, not total job duration. Explicit values are 10–3600 seconds; the standard default is 1200 seconds (20 minutes), with configuration/runner minimums described in the [mutation-test skill](skills/mutation-test/SKILL.md).

Unit-test generation currently has no equivalent per-run timeout override. Increasing a Bash/polling timeout only changes how long the agent waits.

### Environment files

Ask: "Run mutation tests using `.env.testing`" or "Run BugPocer against the diff from main using `.env.testing`."
The plugin uses `--include-dot-env --env-file .env.testing`. To send the workspace's default `.env`, use `--include-dot-env` (short form: **`-env`**, one dash). There is no `--env` flag, and `--env-file` alone does not enable upload.

These options send the selected file's contents to the Olympix backend, for example to provide RPC URLs/API keys for fork testing. They work for mutation tests, unit tests, and BugPocer, including diff scans and strict review. `full-run` carries the requested file choice to the applicable tools. Upload is off by default. See [environment-file guidance](skills/_shared/environment-files.md).

### BugPocer strict mode

Ask: **"Run BugPocer in strict mode: validate every answer with me before submitting it."**
Or: **"Can you validate answers in the validation step with me, before submitting them?"**
Both enable the same optional review workflow, also supported in `full-run`:

- The agent shows each validation item and proposed decision, then waits for your approval or correction.
- Every security answer and follow-up requires your approval, even when the answer seems clear from the repo.
- Before submitting validation and starting the scan, the agent asks you to approve the reviewed answer summary and documentation choice.

Strict mode rebuilds cached context so validation is presented for review, and keeps setup in the main conversation. Timeouts or background execution never authorize automatic answers. This is a plugin instruction, not an `olympix --strict` flag. Without a request for strict review, the existing automated workflow remains the default. See [strict validation review](skills/bug-pocer/references/strict-validation.md).

## Available skills

| Skill | Description |
|-------|-------------|
| `olympix:full-run` | Run all Olympix tools on a Foundry or Hardhat repo |
| `olympix:static-analysis` | Run vulnerability scanner |
| `olympix:mutation-test` | Generate mutation tests for top 10 contracts |
| `olympix:fuzz-test` | Generate fuzz tests for top 3 contracts (run on demand; not part of `full-run`). Can also stop a running fuzz session |
| `olympix:unit-test` | Generate unit tests with coverage scaffolding |
| `olympix:bug-pocer` | Run BugPocer security analysis (automated by default; optional strict review) |
| `olympix:assemble-report` | Collect results into `olympix-results/report.md` |
| `olympix:auth` | Check/refresh CLI authentication |

## How results work

- **Static analysis** runs synchronously — results are immediate.
- **Mutation tests and unit tests** dispatch async jobs. Results are downloaded directly via agent mode when complete — no need to check email.
- **BugPocer** runs via agent mode — scope review, validation, questions, scan, and findings retrieval happen programmatically, with user approval before answers/submission when strict mode is requested.

All results auto-persist to `.opix/agent/` inside the workspace directory.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `olympix` not found | Install CLI: https://olympix.github.io/installation/ |
| Auth expired | Log in from a **separate terminal** (or before starting Claude Code) with `olympix login` (interactive — enter the emailed code; do **not** run it via `!`) |
| `forge build` fails | Install dependencies per project README |
| Stack-too-deep | Some contracts incompatible with unit test coverage mode |
| `--agent` flag rejected / unknown option | Olympix CLI too old — run `olympix update` |
