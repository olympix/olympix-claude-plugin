---
name: full-run
description: >
  Full Olympix security analysis — runs all tools in sequence: static analysis,
  mutation tests, fuzz tests, unit tests, then prompts for BugPocer.
  Monitors results via Gmail, assembles a final report in
  olympix-results/report.md matching the PDF deliverable format.
  TRIGGER: "full run", "full-run", "run everything", "full scan", "run all tools"
tools: Read, Glob, Grep, Bash, Agent, Skill
---

# Full Run

Run the full Olympix security analysis suite on a Foundry-based Solidity repository: static analysis, mutation tests, fuzz tests, unit tests, and BugPocer preparation — all in one go.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## Process

### Step 0: Verify Olympix Authentication

Follow the `auth` skill to check authentication and automate login via Gmail if needed. If Gmail MCP is not connected, fall back to asking the user to run `! olympix login -e email` manually.

This is checked once here — individual skills do not need to re-check.

### Step 1: Verify Repository Builds

```bash
forge build
```

**If it fails:** initialize the repo per the README (install deps, fix remappings, etc.). This is a shared prerequisite for all tools — fix it once here.

**If it cannot be fixed:** **HARD STOP.** None of the tools can run without a compiling repo.

### Step 2: Run Static Analysis

Invoke the `static-analysis` skill workflow:

1. Run: `olympix analyze -f json -o .`
2. Convert JSON results to `olympix-results/olympix-static.md`
3. Record finding counts by severity

This runs **synchronously** — wait for results before proceeding.

### Step 3: Run Mutation Tests

Invoke the `mutation-test` skill workflow:

1. Identify the top 10 most critical contracts (exclude interfaces, libraries, abstract contracts)
2. Run: `olympix generate-mutation-tests -p path1 -p path2 ... -p path10`
3. Record the **session ID** and **contract list**

### Step 4: Run Fuzz Tests

Invoke the `fuzz-test` skill workflow:

1. From the same analysis, pick the top 3 most critical contracts
2. Run: `olympix generate-fuzz-tests -p path1 -p path2 -p path3`
3. Record the **session ID** and **contract list**

### Step 5: Run Unit Tests

Invoke the `unit-test` skill workflow:

1. Verify `forge coverage --ir-minimum --allow-failure` passes
2. If stack-too-deep: triage (localized vs repo-wide). Exclude affected contracts.
3. Detect solc version, create `test/OpixUnitTests.sol` and up to 10 test template files
4. Verify coverage still passes after adding files
5. Add setUp functions, verify again
6. Run: `olympix generate-unit-tests -ca`
7. Record the **session ID** and **contract list**

**If unit tests hit a repo-wide stack-too-deep on coverage:** skip this step, note it in the summary, and continue to Step 6.

### Step 6: Summary & Start Monitoring

Present a summary table to the user with all results so far:

```
## Olympix Full Run Summary

| Tool | Session ID | Contracts / Findings | Status |
|------|-----------|----------------------|--------|
| Static Analysis | — | {X} critical, {Y} high, {Z} medium, ... | Complete (see olympix-results/olympix-static.md) |
| Mutation Tests | {id} | Contract1, Contract2, ... | Started |
| Fuzz Tests | {id} | Contract1, Contract2, Contract3 | Started |
| Unit Tests | {id} | Contract1, Contract2, ... | Started |

Monitoring for results. Report will be assembled automatically when all sessions complete.
BugPocer available for interactive analysis: `! olympix bug-pocer`
```

### Step 7: Monitor Results & Assemble Report

**If Gmail MCP is connected:** start a monitoring loop that checks Gmail every 15 minutes for each session ID. Use the `/loop` skill:

```
/loop 15m Check Gmail for Olympix results by searching each session ID: `from:olympix {mutation_id}`, `from:olympix {fuzz_id}`, `from:olympix {unit_id}`. For each result found, report the tool type and key metrics. When ALL sessions have results, STOP the loop and immediately invoke the assemble-report skill to generate olympix-results/report.md.
```

**If Gmail MCP is NOT connected:** tell the user to check their email for results. List the session IDs so they know what to look for. Ask them to let you know when all results are in so you can assemble the report.

**Always search by session ID** — it's a UUID, guaranteed unique. Never filter by date or subject.

**Sessions to watch:**

| Session ID | Tool |
|-----------|------|
| {mutation_id} | Mutation Tests |
| {fuzz_id} | Fuzz Tests |
| {unit_id} | Unit Tests |

**Key metrics to extract from each result:**
- **Unit tests:** "X new tests generated across Y test contracts"
- **Mutation tests:** "Overall Score: X% (Y killed / Z mutants)"
- **Fuzz tests:** "Relevant Test Cases / Exploit Test Cases" counts per contract

**When all results are in, automatically invoke `assemble-report`** to:

1. Create `olympix-results/` directory structure
2. Collect static analysis, mutation, unit test, and fuzz test results
3. Generate `olympix-results/report.md` — the final deliverable in markdown

The report follows the same structure as the Olympix PDF deliverable: Table of Contents, Mutation Testing, Unit Testing, Fuzz Testing, BugPoCer Scan Report, and Static Analysis.

**Do NOT wait for BugPocer.** The report is assembled as soon as the async sessions (mutation, fuzz, unit tests) complete. BugPocer is marked as "Not run — run `! olympix bug-pocer` for interactive analysis" in the report. The user can re-run `assemble-report` later to include BugPocer results.

## Key Rules

- **Do the codebase analysis ONCE** — identify all critical contracts in Step 3, then reuse that analysis for Steps 4 and 5. Don't re-analyze the codebase for each tool.
- **Contract selection overlaps are fine** — the top 3 for fuzz tests will be a subset of the top 10 for mutation tests. The unit test contracts may differ due to stack-too-deep exclusions.
- **Don't stop on partial failure** — if one tool fails (e.g. unit tests hit stack-too-deep), note it and continue with the others.

## Quick Reference

| Step | Skill | Gate | Max Contracts |
|------|-------|------|---------------|
| 0 | auth | Token check (Gmail MCP optional) | — |
| 1 | — | `forge build` | — |
| 2 | static-analysis | `forge build` | all (auto-detected) |
| 3 | mutation-test | `forge build` | 10 |
| 4 | fuzz-test | `forge build` | 3 |
| 5 | unit-test | `forge coverage --ir-minimum --allow-failure` | 10 |
| 6 | bug-pocer | Inform user (manual, not a blocker) | all (auto-detected) |
| 7 | assemble-report | Auto — when async sessions complete | — |
