---
name: assemble-report
description: >
  Use when the user wants all Olympix tool results assembled into an olympix-results
  directory with a final markdown report — collects static analysis, mutation tests,
  unit tests, fuzz tests, and BugPocer findings into a structured deliverable.
  Results can be downloaded directly via agent mode or provided manually.
  TRIGGER: "assemble report", "final report", "olympix report", "collect results", "deliverable"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill
---

# Assemble Olympix Report

Collect all Olympix tool results into a structured `olympix-results/` directory with a final markdown report.

## Prerequisites

- Static analysis has been run (should already be in `olympix-results/olympix-static.md`)
- Working directory is the root of the Foundry project

## CLI Capability Check

Downloading results requires agent mode (`--agent`); older Olympix CLIs do not support it. Probe first:

```bash
olympix sessions --help 2>&1 | grep -q -- --agent && echo AGENT_MODE || echo LEGACY_CLI
```

If `LEGACY_CLI` (the `--agent` flag is rejected), the CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe. **HARD STOP** if the CLI still lacks `--agent`.

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

Identify the sessions that are done — the "done" status differs **per array**:

| Array | Done status | Failure status |
|-------|-------------|----------------|
| `unit_tests` | `Completed` | `Failed` |
| `mutation_tests` | `Completed` | `Failed` |
| `bug_pocer` | `InitialScanCompleted` | — (Killed sessions are not retrievable) |

BugPocer sessions **never** reach `Completed` — `InitialScanCompleted` is their terminal "ready" state.

**If no sessions are returned:** re-check authentication (run the `auth` skill), then retry. If still empty, the tools were never run from this machine — note affected sections as "Not run" in the report.

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

Returns `findings_ready` event with findings array. Each finding: `id`, `title`, `severity`, `description`, `affected_code`, `file_path`, `line_number`, plus the verdict/PoC fields: `bugpocer_verdict`, `user_verdict`, `user_verdict_reason`, `effective_verdict`, `confidence_score`, `poc_summary`, `poc_content`. Report verdicts by `effective_verdict`, distinguishing BugPocer's automated call from human review (`user_verdict` = `unreviewed` until a human sets it).

Also available at `.opix/agent/<session-id>/findings.json`.

Parse and save to `olympix-results/bugpocer_pocs/findings.md` — the same path the `bug-pocer` skill writes, so re-assembly overwrites rather than duplicates.

#### 3e. Fuzz Test Results (Manual Only)

Fuzz tests do NOT support agent mode. If fuzz tests were run, ask the user to provide results from their email:

> Fuzz test results can't be downloaded automatically. Please paste or forward the result email so I can extract metrics, or save attachments to `olympix-results/fuzz_test/`.

**Determinism rule when an email is searched** (by the user, or via any mail tooling available): locate the result email by the **session ID (UUID)** — it is guaranteed unique. Never search by date or subject; both are ambiguous across runs.

### Step 4: Handle Missing Results

For any tool that wasn't run or has no completed sessions:

- **No sessions found:** Mark as "Not run" in the report
- **Sessions still InProgress:** Poll `olympix sessions --agent` and wait, or mark as "In progress" and offer to check later
- **Failed sessions:** Include the error message in the report. Note: `olympix sessions --agent` does NOT populate `error_message` — to get it, reconnect via `olympix mutation-testing --agent` / `olympix unit-testing --agent`: the `sessions_list` event emitted there carries `error_message` per session, and connecting to a Failed session returns a `results_ready` event whose message is `"Generation failed: <error>"`

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

## Quick Reference

| Step | Action |
|------|--------|
| 1 | Create `olympix-results/` directory structure |
| 2 | Verify `olympix-static.md` exists (else run `static-analysis`) |
| 3 | Download mutation/unit/BugPocer results via `olympix sessions --agent` + `connect_session` |
| 4 | Handle missing/in-progress/failed sessions |
| 5 | Generate `olympix-results/report.md` |
| 6 | Report to user |

## Common Issues

| Problem | Solution |
|---------|----------|
| `olympix sessions --agent` returns nothing | Re-run the `auth` skill; if still empty, mark sections "Not run" |
| Session still `InProgress` | Poll and wait, or mark "In progress" and offer to re-assemble later |
| Session `Failed` | `olympix sessions --agent` does not carry `error_message` — get it from the `sessions_list` event during `mutation-testing`/`unit-testing --agent` retrieval, or from the `results_ready` "Generation failed: ..." message |
| `--agent` flag rejected | CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe |
| Fuzz tests have no agent-mode results | Ask the user to paste/forward the email or save attachments to `olympix-results/fuzz_test/` |
| Static analysis not run | Run `static-analysis` skill first or skip the section |
| BugPocer not run | Mark as "Not run" — it's optional |
