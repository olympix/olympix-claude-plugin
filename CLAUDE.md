# CLAUDE.md

Olympix is a smart contract security platform. This plugin runs its tools from Claude Code using the `--agent` flag for structured JSONL interaction.

## Skills

| Skill | When to use |
|-------|-------------|
| `olympix:full-run` | User wants a complete security analysis of a Foundry or Hardhat repo |
| `olympix:static-analysis` | Run vulnerability scanner only |
| `olympix:mutation-test` | Generate mutation tests (top 10 contracts by criticality) |
| `olympix:unit-test` | Generate unit tests with coverage scaffolding |
| `olympix:bug-pocer` | Run BugPocer security analysis (fully automated via agent mode) |
| `olympix:assemble-report` | Collect all results into olympix-results/report.md |
| `olympix:auth` | Check or refresh CLI authentication |

## Key rules

- Always verify the repo compiles before running any Olympix tool — `forge build` (Foundry) or `npx hardhat compile` (Hardhat). The CLI auto-detects the project type; see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md`.
- All tools use `--agent` flag for structured JSONL output on stdout.
- Input is sent as JSONL on stdin (actions like `confirm_all`, `disconnect`, etc.).
- Contract selection follows the canonical criticality ranking in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/contract-selection.md` — read it rather than improvising a ranking.
- Top 10 contracts for mutation/unit tests (plugin convention; CLI hard limits differ per tool: mutation tests accept up to 100, unit tests at most 10).
- Results persist automatically to `.opix/agent/` inside the workspace (`-w` path).
- Additional formatted output goes to `olympix-results/` in the project root.
- BugPocer runs fully automated via agent mode — no user handoff needed.
- Consistent casing: "BugPocer" (not "BugPoCer"). Exception: CLI-generated artifacts keep their original casing (e.g. the exported PDF `BugPoCer_Scan_Report*.pdf` and its "BugPoCer ... Report" headings) — do not rename them.
- The `OlympixUnitTest("ContractName")` annotation string must match the actual `contract` declaration name, not the file name.
- CLI commands use `olympix <subcommand>` directly. No aliases or prefixes.
- Static analysis runs synchronously. Unit and mutation test generation dispatch async jobs — poll session status with `olympix sessions --agent`; when a session completes, retrieve results via `olympix unit-testing --agent` or `olympix mutation-testing --agent` (`connect_session`).

## Agent mode protocol

All supported commands use `--agent` for JSONL communication:

- **Events** (CLI → agent): `{"event":"<type>","data":{...},"actions":[...]}`
- **Actions** (agent → CLI): `{"action":"<type>","data":{...}}`
- Common actions: `confirm_all`, `disconnect`, `new_session`, `connect_session`, `select_files`, `select_scope`, `select_option`, `select_answer`, `confirm_item`, `skip_question`, `skip_docs`, `ask_question`

## Output structure

```
.opix/agent/                   — auto-persisted by CLI (in workspace dir)
  bug-pocer/sessions.json      — BP session list
  <session-id>/findings.json   — BP findings
  <session-id>/qa.json         — BP Q&A exchanges
  unit-tests/sessions.json     — UT session list
  unit-tests/contracts.json    — UT available contracts
  unit-tests/results.json      — dispatch receipt at dispatch; full UT results (coverage) written at retrieval
  mutation-tests/sessions.json — MT session list
  mutation-tests/results.json  — dispatch receipt at dispatch; full MT results (kill scores) written at retrieval

olympix-results/               — formatted reports (created by skills)
  olympix-static.md            — static analysis findings
  mutation_test/               — mutation test metrics and reports
  unit_test/                   — unit test coverage and reports
  bugpocer_pocs/               — BugPocer exploit PoCs
  report.md                    — assembled final report
```
