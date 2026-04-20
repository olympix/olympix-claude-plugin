---
name: assemble-report
description: >
  Assembles all Olympix tool results into an olympix-results directory with
  a final markdown report. Collects static analysis, mutation tests, unit tests,
  fuzz tests, and BugPocer findings into a structured deliverable.
  Use after all Olympix tools have completed for an assignment.
  TRIGGER: "assemble report", "final report", "olympix report", "collect results", "deliverable"
tools: Read, Glob, Grep, Bash, Agent
---

# Assemble Olympix Report

Collect all Olympix tool results into a structured `olympix-results/` directory with a final markdown report.

## Prerequisites

- Static analysis has been run (synchronous — should already be in `olympix-results/olympix-static.md`)
- Async tools (mutation, fuzz, unit tests) have completed and user has the result emails
- Working directory is the root of the Foundry project

## Output Structure

```
olympix-results/
├── report.md                    # Final combined report (markdown)
├── olympix-static.md            # Static analysis results
├── mutation_test/
│   ├── mutation_results.md      # Mutation test summary
│   └── *.t.sol                  # Quick-fix test files
├── unit_test/
│   ├── unit_test_results.md     # Unit test summary
│   └── *.t.sol                  # Generated test files
├── fuzz_test/
│   ├── fuzz_results.md          # Fuzz test summary
│   └── *.t.sol                  # Fuzz test files
└── bugpocer_pocs/
    ├── full-run/
    │   ├── BugPocer_Scan_Report*.pdf
    │   └── *.t.sol
    └── scoped-run/
        ├── BugPocer_Scan_Report*.pdf
        └── *.t.sol
```

## Process

### Step 1: Create Directory Structure

```bash
mkdir -p olympix-results/{mutation_test,unit_test,fuzz_test,bugpocer_pocs/full-run,bugpocer_pocs/scoped-run}
```

### Step 2: Verify Static Analysis

Check if `olympix-results/olympix-static.md` exists. If not, check for the JSON output file (`code_analysis_*.json`) and generate it, or run the `static-analysis` skill.

### Step 3: Collect Async Results

Ask the user to provide results from their Olympix sessions:

> I need the results from your Olympix sessions. For each session, please:
> 1. Forward or paste the result email content so I can extract metrics
> 2. Download and save the attachments:
>    - Unit test `.t.sol` files + `mutation_tests.csv` → `olympix-results/unit_test/`
>    - Mutation test `mutation_tests.csv` + `.t.sol` quick-fixes → `olympix-results/mutation_test/`
>    - Fuzz test `fuzz_tests.zip` → `olympix-results/fuzz_test/` (unzip after saving)

For any metrics the user provides, parse them and populate the corresponding `*_results.md` files. For any not provided, mark as "Results pending" in the report.

**Metrics to extract from email bodies:**

**Mutation Tests:**
- Overall Score: X% (Y killed / Z total mutants)
- With Quick Fixes: X%
- Per-file breakdown (file, score, with-quick-fixes score)
- Session ID and duration
- Save to `olympix-results/mutation_test/mutation_results.md`

**Unit Tests:**
- Quick Summary: X new tests generated across Y test contracts
- Average coverage improvement: X% lines, Y% branches
- Per-file coverage table
- Save to `olympix-results/unit_test/unit_test_results.md`

**Fuzz Tests:**
- Per-contract table: Contract, Attack Strategy, Paths, Feasible, Infeasible, Relevant Test Cases, Exploit Test Cases
- Elapsed time
- Save to `olympix-results/fuzz_test/fuzz_results.md`

### Step 4: Collect BugPocer Results (if available)

Check if BugPocer output exists:

```bash
ls -la bugpocer_pocs/ 2>/dev/null
ls -la *BugPocer*.pdf 2>/dev/null
ls -la test/poc/ 2>/dev/null
```

If found, copy PoC files and findings to `olympix-results/bugpocer_pocs/full-run/`.

If not run, note it in the report as "Not run — requires interactive session."

### Step 5: Generate Final Report

Create `olympix-results/report.md`:

```markdown
# {project_name}

## Table of Contents

- Mutation Testing
  - [Mutation Files](#mutation-files)
- Unit Testing
  - [Unit Testing Files](#unit-testing-files)
- Fuzz Testing
  - [Fuzz Testing Files](#fuzz-testing-files)
- BugPocer Scan Report
  - [Severity] finding_name (for each finding)
  - [BugPocer PDF](#bugpocer-pdf)
  - [BugPocer PoCs](#bugpocer-pocs)
- Static Analysis

---

## Mutation Testing

### Mutation Test Results

**Overall Score:** X% (Y killed / Z total mutants)
**With Quick Fixes:** X%

| File | Score | With Quick Fixes |
|------|-------|-----------------|
| Contract1.sol | X% | Y% |

**Session ID:** {id}
**Duration:** Xm Ys

### Mutation Files

[Link to mutation_test/ directory]

---

## Unit Testing

### Unit Test Results

**Quick Summary:** X new tests generated across Y test contracts
**Average coverage improvement:** X% lines, Y% branches

#### Coverage Improvements

| File | Before | After | Improvement |
|------|--------|-------|-------------|
| Contract1.t.sol | 0 tests, 0% lines, 0% branches | N tests, X% lines, Y% branches | +N, +X%, +Y% |

### Unit Testing Files

[Link to unit_test/ directory]

---

## Fuzz Testing

| Contract | Attack Strategy | Paths | Feasible | Infeasible | Relevant Test Cases | Exploit Test Cases |
|----------|----------------|-------|----------|------------|--------------------|--------------------|
| Contract1.sol | Strategy | N | N | N | N | N |

**Elapsed Time:** X hours Y minutes Z seconds

### Fuzz Testing Files

[Link to fuzz_test/ directory]

---

## BugPocer Scan Report

### [Severity] finding_name

**Unit Name:** function_name
**Location:** file_path, contract — function/scope
**Description:** Full description with inline code references.
**PoC Summary:** `test/poc/filename.t.sol` — description of the PoC.

(Repeat for each finding, ordered by severity: Critical > High > Medium > Low)

### BugPocer PDF

[Link to PDF if available]

### BugPocer PoCs

[Link to bugpocer_pocs/full-run/ directory]

---

## Static Analysis

[Content from olympix-static.md]
```

### Step 6: Report to User

Tell the user:
- Report generated at `olympix-results/report.md`
- Any missing sections and how to fill them
- Suggest reviewing the report before sharing
