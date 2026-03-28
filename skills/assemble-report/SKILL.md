---
name: assemble-report
description: >
  Assembles all Olympix tool results into an olympix-results directory with
  a final markdown report. Collects static analysis, mutation tests, unit tests,
  fuzz tests, and BugPocer findings into a structured deliverable.
  Downloads attachments from Gmail if MCP is connected.
  Use after all Olympix tools have completed.
  TRIGGER: "assemble report", "final report", "olympix report", "collect results", "deliverable"
tools: Read, Glob, Grep, Bash, Agent
---

# Assemble Olympix Report

Collect all Olympix tool results into a structured `olympix-results/` directory with a final markdown report mirroring the PDF deliverable format.

## Prerequisites

- All Olympix tools have completed (static analysis, mutation, fuzz, unit tests)
- BugPocer session completed (if run — this is optional/manual)
- Working directory is the root of the Foundry project

## Output Structure

```
olympix-results/
├── report.md                    # Final combined report (markdown)
├── olympix-static.md            # Static analysis results
├── mutation_testing/
│   ├── mutation_results.md      # Mutation test summary
│   └── *.t.sol                  # Quick-fix test files (from email attachments)
├── unit_test_gen/
│   ├── unit_test_results.md     # Unit test summary
│   └── *.t.sol                  # Generated test files (from email attachments)
├── fuzz_testing/
│   ├── fuzz_results.md          # Fuzz test summary
│   └── *.t.sol                  # Fuzz test files (from email attachments)
└── bugpocer/
    ├── bugpocer_findings.md     # BugPocer findings (if available)
    └── pocs/
        └── *.t.sol              # PoC files (if available)
```

## Process

### Step 1: Create Directory Structure

```bash
mkdir -p olympix-results/{mutation_testing,unit_test_gen,fuzz_testing,bugpocer/pocs}
```

### Step 2: Verify Static Analysis

Check if `olympix-results/olympix-static.md` exists (the `static-analysis` skill writes directly to this path).

If it doesn't exist, check for the JSON output file (`code_analysis_*.json`) and generate it, or run the `static-analysis` skill.

### Step 3: Collect Results

There are two paths depending on whether Gmail MCP is available:

---

**Path A — With Gmail MCP:**

For each completed session, search Gmail by session ID (guaranteed unique — never filter by date or subject):

```
from:olympix {session_id}
```

Use `gmail_read_message` to get the full email body and attachment list. Extract all metrics from the email body (see below).

**Gmail MCP can read email bodies and list attachments but CANNOT download attachment files.** After extracting metrics, ask the user to download the attachments:

> "I've extracted all the metrics from your result emails. Please download the email attachments and save them to:
>
> **Unit test email** (session {id}):
> - `.t.sol` files -> `olympix-results/unit_test_gen/`
> - `mutation_tests.csv` -> `olympix-results/unit_test_gen/`
>
> **Mutation test email** (session {id}):
> - `mutation_tests.csv` -> `olympix-results/mutation_testing/`
> - Any `.t.sol` quick-fix files -> `olympix-results/mutation_testing/`
>
> **Fuzz test email** (session {id}):
> - `fuzz_tests.zip` -> `olympix-results/fuzz_testing/` (unzip after saving)"

---

**Path B — Without Gmail MCP:**

Ask the user to provide the results:

> "I need the results from your Olympix sessions. For each session, please:
> 1. Forward or paste the result email content so I can extract metrics
> 2. Download and save the attachments:
>    - Unit test `.t.sol` files + `mutation_tests.csv` -> `olympix-results/unit_test_gen/`
>    - Mutation test `mutation_tests.csv` + `.t.sol` quick-fixes -> `olympix-results/mutation_testing/`
>    - Fuzz test `fuzz_tests.zip` -> `olympix-results/fuzz_testing/` (unzip after saving)"

For any metrics the user provides, parse them and populate the corresponding `*_results.md` files. For any not provided, mark as "Results pending" in the report.

---

**Expected attachments by tool:**

| Tool | Attachments | Save to |
|------|------------|---------|
| Unit Tests | `*.t.sol` (per contract), `mutation_tests.csv` | `olympix-results/unit_test_gen/` |
| Mutation Tests | `mutation_tests.csv`, `*.t.sol` (quick-fixes) | `olympix-results/mutation_testing/` |
| Fuzz Tests | `fuzz_tests.zip` | `olympix-results/fuzz_testing/` (unzip) |

**Metrics to extract from email bodies (both paths):**

**Mutation Tests:**
- Overall Score: X% (Y killed / Z total mutants)
- With Quick Fixes: X%
- Per-file breakdown (file, score, with-quick-fixes score)
- Session ID and duration
- Save summary to `olympix-results/mutation_testing/mutation_results.md`

**Unit Tests:**
- Quick Summary: X new tests generated across Y test contracts
- Average coverage improvement: X% lines, Y% branches
- Per-file coverage table (file, before tests/lines/branches, after, improvement)
- Mutation test results after generated unit tests (if included)
- Save summary to `olympix-results/unit_test_gen/unit_test_results.md`

**Fuzz Tests:**
- Per-contract table: Contract, Attack Strategy, Paths, Feasible, Infeasible, Relevant Test Cases, Exploit Test Cases
- Elapsed time
- Save summary to `olympix-results/fuzz_testing/fuzz_results.md`

**If Gmail MCP is NOT available:** ask the user to manually provide the result emails or copy files into the directories. Note which sections are incomplete.

### Step 4: Collect BugPocer Results (if available)

Check if BugPocer output exists in the workspace:

```bash
ls -la bugpocer_pocs/ 2>/dev/null
ls -la *BugPoCer*.pdf 2>/dev/null
ls -la test/poc/ 2>/dev/null
```

If found, copy PoC files and any BugPocer findings to `olympix-results/bugpocer/`.

If the user has run BugPocer and has findings, extract them into `bugpocer_findings.md` with the format:

```markdown
## [Severity] finding_name

**Unit Name:** function_name
**Location:** file_path, function/contract
**Description:** Full description with code references
**PoC Summary:** test/poc/filename.t.sol — description of what the PoC demonstrates
```

If BugPocer was not run, note it in the report as "Not run — requires interactive session."

### Step 5: Generate Final Report

Create `olympix-results/report.md` following this structure:

```markdown
# {project_name}

## Table of Contents

- Mutation Testing
  - [Mutation Files](#mutation-files)
- Unit Testing
  - [Unit Testing Files](#unit-testing-files)
- Fuzz Testing
  - [Fuzz Testing Files](#fuzz-testing-files)
- BugPoCer Scan Report
  - [Severity] finding_name (for each finding)
  - [BugPocer PDF](#bugpocer-pdf)
  - [BugPoCer PoCs](#bugpocer-pocs)
- Static Analysis

---

## Mutation Testing

### Mutation Test Results Ready

**Overall Score:** X% (Y killed / Z total mutants)
**With Quick Fixes:** X% (N additional mutations killed by generated tests)

| File | Score | With Quick Fixes |
|------|-------|-----------------|
| Contract1.sol | X% | Y% |
| Contract2.sol | X% | Y% |

**Session ID:** {id}
**Duration:** Xm Ys

### Mutation Files

[Link to mutation_testing/ directory]

---

## Unit Testing

### Unit Test Results Ready

**Quick Summary:** X new tests generated across Y test contracts
**Average coverage improvement:** X% lines, Y% branches

#### Coverage Improvements

| File | Before | After | Improvement |
|------|--------|-------|-------------|
| Contract1.t.sol | 0 tests, 0% lines, 0% branches | N tests, X% lines, Y% branches | +N, +X%, +Y% |

#### Mutation Test Results (After Generated Unit Tests)

**Overall Score:** X% (Y killed / Z total mutants)

| File | Score |
|------|-------|
| Contract1.sol | X% |

### Unit Testing Files

[Link to unit_test_gen/ directory]

---

## Fuzz Testing

| Contract | Attack Strategy | Paths | Feasible Paths | Infeasible Paths | Relevant Test Cases | Exploit Test Cases |
|----------|----------------|-------|---------------|-----------------|--------------------|--------------------|
| Contract1.sol | Strategy | N | N | N | N | N |

**Elapsed Time:** X hours Y minutes Z seconds

### Fuzz Testing Files

[Link to fuzz_testing/ directory]

---

## BugPoCer Scan Report

### [Severity] finding_name

**Unit Name:** function_name
**Location:** file_path, contract — function/scope
**Description:** Full description with inline code references.
**PoC Summary:** `test/poc/filename.t.sol` — description of the PoC.

(Repeat for each finding, ordered by severity: Critical > High > Medium > Low)

### BugPocer PDF

[Link to PDF if available]

### BugPoCer PoCs

[Link to bugpocer/pocs/ directory]

---

## Static Analysis

[Content from olympix-static.md]
```

### Step 6: Report to User

Tell the user:
- Report generated at `olympix-results/report.md`
- Directory structure with all collected files
- Any missing sections (e.g., BugPocer not run, Gmail not connected)
- Suggest reviewing the report before sharing with the client

## Quick Reference

| Step | Action |
|------|--------|
| 1 | Create `olympix-results/` directory structure |
| 2 | Copy `olympix-static.md` |
| 3 | Extract metrics from Gmail result emails (if MCP available) |
| 4 | Collect BugPocer findings and PoCs (if available) |
| 5 | Generate `olympix-results/report.md` |
| 6 | Report to user |

## Common Issues

| Problem | Solution |
|---------|----------|
| Gmail MCP not connected | Ask user to provide result emails or copy files manually |
| BugPocer not run | Mark as "Not run" in report — it's optional/manual |
| Missing email attachments | Gmail MCP can read bodies and list attachments but CANNOT download files. Ask user to download from Gmail and save to the correct `olympix-results/` subdirectory |
| Static analysis not run | Run `static-analysis` skill first or skip section |
| Some sessions still running | Note as "Pending" in report, re-run assembly later |
