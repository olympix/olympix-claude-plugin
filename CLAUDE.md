# CLAUDE.md

Olympix is a smart contract security platform. This plugin runs its tools from Claude Code using the `--agent` flag for structured JSONL interaction.

## Skills

| Skill | When to use |
|-------|-------------|
| `olympix:full-run` | User wants a complete security analysis of a Foundry repo |
| `olympix:static-analysis` | Run vulnerability scanner only |
| `olympix:mutation-test` | Generate mutation tests (top 10 contracts by criticality) |
| `olympix:fuzz-test` | Generate fuzz tests (top 3 contracts by criticality) |
| `olympix:unit-test` | Generate unit tests with coverage scaffolding |
| `olympix:bug-pocer` | Run BugPocer security analysis (fully automated via agent mode) |
| `olympix:assemble-report` | Collect all results into olympix-results/report.md |
| `olympix:auth` | Check or refresh CLI authentication |

## Key rules

- Always verify `forge build` succeeds before running any Olympix tool.
- All tools use `--agent` flag for structured JSONL output on stdout.
- Input is sent as JSONL on stdin (actions like `confirm_all`, `disconnect`, etc.).
- Contract selection uses criticality ranking: fund custody > token transfers > access control > state management > view/utility.
- Maximum 10 contracts for mutation/unit tests, 3 for fuzz tests.
- Results persist automatically to `.opix/agent/` inside the workspace (`-w` path).
- Additional formatted output goes to `olympix-results/` in the project root.
- BugPocer runs fully automated via agent mode — no user handoff needed.
- Consistent casing: "BugPocer" (not "BugPoCer").
- The `OlympixUnitTest("ContractName")` annotation string must match the actual `contract` declaration name, not the file name.
- CLI commands use `olympix <subcommand>` directly. No aliases or prefixes.
- Static analysis runs synchronously. Unit and mutation test generation dispatch async jobs — poll session status via `olympix unit-testing --agent` or `olympix mutation-testing --agent` to retrieve results when complete.
- Fuzz test generation does NOT support `--agent` mode. It runs in TUI mode only.

## Agent mode protocol

All supported commands use `--agent` for JSONL communication:

- **Events** (CLI → agent): `{"event":"<type>","data":{...},"actions":[...]}`
- **Actions** (agent → CLI): `{"action":"<type>","data":{...}}`
- Common actions: `confirm_all`, `disconnect`, `new_session`, `connect_session`, `select_contracts`, `confirm_item`, `skip_question`, `skip_docs`, `ask_question`

## Output structure

```
.opix/agent/                   — auto-persisted by CLI (in workspace dir)
  bug-pocer/sessions.json      — BP session list
  <session-id>/findings.json   — BP findings
  <session-id>/qa.json         — BP Q&A exchanges
  unit-tests/sessions.json     — UT session list
  unit-tests/contracts.json    — UT available contracts
  unit-tests/results.json      — UT results with coverage
  mutation-tests/sessions.json — MT session list
  mutation-tests/results.json  — MT results with kill scores

olympix-results/               — formatted reports (created by skills)
  olympix-static.md            — static analysis findings
  mutation_test/               — mutation test metrics and reports
  fuzz_test/                   — fuzz test reports
  unit_test/                   — unit test coverage and reports
  bugpocer_pocs/               — BugPocer exploit PoCs
  report.md                    — assembled final report
```
