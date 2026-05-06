---
name: assemble-report
description: >
  Assembles all Olympix tool results into an olympix-results directory with
  a final markdown report. Collects static analysis, mutation tests, unit tests,
  fuzz tests, and BugPocer findings into a structured deliverable.
  Results can be downloaded directly via agent mode or provided manually.
  TRIGGER: "assemble report", "final report", "olympix report", "collect results", "deliverable"
tools: Read, Glob, Grep, Bash, Agent
---

# Assemble Olympix Report

Collect all Olympix tool results into a structured `olympix-results/` directory with a final markdown report.

## Prerequisites

- Static analysis has been run (should already be in `olympix-results/olympix-static.md`)
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
    └── findings.md              # BugPocer findings
```

## Process

### Step 1: Create Directory Structure

```bash
mkdir -p olympix-results/{mutation_test,unit_test,fuzz_test,bugpocer_pocs}
```

### Step 2: Verify Static Analysis

Check if `olympix-results/olympix-static.md` exists. If not, run the `static-analysis` skill.

### Step 3: Collect Results — Download via Agent Mode

Results from mutation tests, unit tests, and BugPocer can be **downloaded directly** via agent mode. No need to wait for emails.

#### 3a. Check Available Sessions

```bash
olympix sessions --agent
```

This returns all sessions across services:
```json
{"event":"all_sessions","data":{"bug_pocer":[...],"unit_tests":[...],"mutation_tests":[...]}}
```

Identify `Completed` sessions to download results from.

#### 3b. Download Mutation Test Results

```bash
printf '{"action":"connect_session","data":{"session_id":"<id>"}}\n{"action":"disconnect"}\n' \
  | olympix mutation-testing --agent
```

Returns `mutation_test_results` event with: `total_mutations`, `killed`, `survived`, `score_percentage`, and per-mutation details.

Also available at `.opix/agent/mutation-tests/results.json`.

Parse and save to `olympix-results/mutation_test/mutation_results.md`.

#### 3c. Download Unit Test Results

```bash
printf '{"action":"connect_session","data":{"session_id":"<id>"}}\n{"action":"disconnect"}\n' \
  | olympix unit-testing --agent
```

Returns `unit_test_results` event with: `total_files`, `successful_files`, `branches_coverage`, and per-file coverage data.

Also available at `.opix/agent/unit-tests/results.json`.

Parse and save to `olympix-results/unit_test/unit_test_results.md`.

#### 3d. Download BugPocer Findings

```bash
printf '{"action":"disconnect"}\n' \
  | olympix connect-bp-session -s <session-id> -w . --agent
```

Returns `findings_ready` event with findings array. Each finding: `id`, `title`, `severity`, `description`, `affected_code`, `file_path`, `line_number`.

Also available at `.opix/agent/<session-id>/findings.json`.

Parse and save to `olympix-results/bugpocer_pocs/findings.md`.

#### 3e. Fuzz Test Results (Manual Only)

Fuzz tests do NOT support agent mode. If fuzz tests were run, ask the user to provide results from their email:

> Fuzz test results can't be downloaded automatically. Please paste or forward the result email so I can extract metrics, or save attachments to `olympix-results/fuzz_test/`.

### Step 4: Handle Missing Results

For any tool that wasn't run or has no completed sessions:

- **No sessions found:** Mark as "Not run" in the report
- **Sessions still InProgress:** Poll `olympix sessions --agent` and wait, or mark as "In progress" and offer to check later
- **Failed sessions:** Include the error message in the report

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
- Static Analysis

---

## Mutation Testing

### Mutation Test Results

**Overall Score:** X% (Y killed / Z total mutants)

| File | Line | Original | Mutated | Killed | Broken Tests |
|------|------|----------|---------|--------|-------------|
| ... | ... | ... | ... | Yes/No | test1(), test2() |

**Session ID:** {id}

### Mutation Files

[Link to mutation_test/ directory]

---

## Unit Testing

### Unit Test Results

**Total Files:** X | **Successful:** Y
**Branches Coverage:** Z%

| Contract | Test File | Coverage Before | Coverage After | Passed | Failed |
|----------|-----------|----------------|----------------|--------|--------|
| ... | ... | ...% | ...% | ... | ... |

### Unit Testing Files

[Link to unit_test/ directory]

---

## Fuzz Testing

| Contract | Attack Strategy | Paths | Feasible | Infeasible | Test Cases | Exploits |
|----------|----------------|-------|----------|------------|------------|----------|
| ... | ... | ... | ... | ... | ... | ... |

### Fuzz Testing Files

[Link to fuzz_test/ directory]

---

## BugPocer Scan Report

### [Severity] finding_name

**File:** file_path:line_number
**Description:** Full description.

(Repeat for each finding, ordered by severity: Critical > High > Medium > Low)

---

## Static Analysis

[Content from olympix-static.md]
```

### Step 6: Report to User

Tell the user:
- Report generated at `olympix-results/report.md`
- Any missing sections and how to fill them
- Suggest reviewing the report before sharing
