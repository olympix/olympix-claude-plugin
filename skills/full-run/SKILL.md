---
name: full-run
description: >
  Full Olympix security analysis — runs all tools in sequence: static analysis,
  mutation tests, fuzz tests, unit tests, then prompts for BugPocer.
  Assembles a final report from available results.
  TRIGGER: "full run", "full-run", "run everything", "full scan", "run all tools"
tools: Read, Glob, Grep, Bash, Agent, Skill
---

# Full Run

Run the full Olympix security analysis suite on a Foundry-based Solidity repository: static analysis, mutation tests, fuzz tests, unit tests, and BugPocer preparation.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication. This is checked once here — individual skills do not need to re-check.

### Step 1: Verify Repository Builds

Read and follow `skills/_shared/forge-setup.md`. This is a shared prerequisite for all tools — fix it once here.

### Step 2: Run Static Analysis

Invoke the `static-analysis` skill workflow:

1. Run: `olympix analyze -f json -o .`
2. Convert JSON results to `olympix-results/olympix-static.md`
3. Record finding counts by severity

This runs **synchronously** — wait for results before proceeding.

### Step 3: Run Mutation Tests

Invoke the `mutation-test` skill workflow:

1. Identify the top 10 most critical contracts (read `skills/_shared/contract-selection.md`)
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
3. Detect solc version, create base contract and up to 10 test template files
4. Verify coverage still passes after adding files
5. Add setUp functions and example tests, verify again
6. Run: `olympix generate-unit-tests -ca`
7. Record the **session ID** and **contract list**

**If unit tests hit a repo-wide stack-too-deep on coverage:** skip this step, note it in the summary, and continue.

### Step 6: Summary

Present a summary table to the user:

```
## Olympix Full Run Summary

| Tool | Session ID | Contracts / Findings | Status |
|------|-----------|----------------------|--------|
| Static Analysis | — | {X} critical, {Y} high, {Z} medium, ... | Complete (see olympix-results/olympix-static.md) |
| Mutation Tests | {id} | Contract1, Contract2, ... | Started (check email) |
| Fuzz Tests | {id} | Contract1, Contract2, Contract3 | Started (check email) |
| Unit Tests | {id} | Contract1, Contract2, ... | Started (check email) |
```

Tell the user:
- Static analysis results are ready in `olympix-results/olympix-static.md`
- Mutation, fuzz, and unit test results will arrive via email (list session IDs)
- When results arrive, run `/olympix:assemble-report` to generate the final report
- BugPocer is available for interactive analysis: `! olympix bug-pocer`

## Key Rules

- **Do the codebase analysis ONCE** — identify all critical contracts in Step 3, then reuse that analysis for Steps 4 and 5.
- **Contract selection overlaps are fine** — the top 3 for fuzz tests will be a subset of the top 10 for mutation tests.
- **Don't stop on partial failure** — if one tool fails, note it and continue with the others.
