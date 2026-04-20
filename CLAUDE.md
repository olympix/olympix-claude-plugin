# CLAUDE.md

Olympix is a smart contract security platform. This plugin runs its tools from Claude Code.

## Skills

| Skill | When to use |
|-------|-------------|
| `olympix:full-run` | User wants a complete security analysis of a Foundry repo |
| `olympix:static-analysis` | Run vulnerability scanner only |
| `olympix:mutation-test` | Generate mutation tests (top 10 contracts by criticality) |
| `olympix:fuzz-test` | Generate fuzz tests (top 3 contracts by criticality) |
| `olympix:unit-test` | Generate unit tests with coverage scaffolding |
| `olympix:bug-pocer` | Launch interactive BugPocer session |
| `olympix:assemble-report` | Collect all results into olympix-results/report.md |
| `olympix:auth` | Check or refresh CLI authentication |

## Key rules

- Always verify `forge build` succeeds before running any Olympix tool.
- Contract selection uses criticality ranking: fund custody > token transfers > access control > state management > view/utility.
- Maximum 10 contracts for mutation/unit tests, 3 for fuzz tests.
- All output goes to `olympix-results/` in the project root.
- BugPocer is interactive (TUI). Claude prepares the repo and hands off to the user with `! olympix bug-pocer`.
- Consistent casing: "BugPocer" (not "BugPoCer").
- The `OlympixUnitTest("ContractName")` annotation string must match the actual `contract` declaration name, not the file name.
- CLI commands use `olympix <subcommand>` directly. No aliases or prefixes.
- Static analysis runs synchronously. Mutation, fuzz, and unit test generation are async — results arrive via email. Ask the user to check email and provide results manually.

## Output structure

```
olympix-results/
  olympix-static.md        — static analysis findings
  mutation_test/           — mutation test metrics and reports
  fuzz_test/              — fuzz test reports
  unit_test/             — unit test coverage and reports
  bugpocer_pocs/          — BugPocer exploit PoCs
  report.md                — assembled final report
```
