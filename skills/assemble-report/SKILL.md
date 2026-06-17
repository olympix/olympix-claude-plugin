---
name: assemble-report
description: >
  Use when the user wants all Olympix tool results assembled into an olympix-results
  directory with a final markdown report — collects static analysis, mutation tests,
  unit tests, and BugPocer findings into a structured deliverable.
  Results can be downloaded directly via agent mode or provided manually.
  TRIGGER: "assemble report", "final report", "olympix report", "collect results", "deliverable"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill
---

# Assemble Olympix Report

Collect all Olympix tool results into a structured `olympix-results/` directory with a final markdown report.

## Prerequisites

- Static analysis has been run (should already be in `olympix-results/olympix-static.md`)
- Working directory is the root of the Foundry or Hardhat project

## CLI Capability Check

Downloading results requires agent mode (`--agent`); older Olympix CLIs do not support it. Probe first:

```bash
if ! command -v olympix >/dev/null 2>&1 && [ ! -x "$HOME/.opix/bin/olympix" ]; then echo NOT_INSTALLED;
elif olympix sessions --help 2>&1 | grep -q -- --agent; then echo AGENT_MODE; else echo LEGACY_CLI; fi
```

If `NOT_INSTALLED`, **HARD STOP** — tell the user to install the Olympix CLI from https://olympix.github.io/installation/ and rerun this skill.

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
└── bugpocer_pocs/
    └── findings.md              # BugPocer findings
```

## Process

### Step 1: Create Directory Structure

```bash
mkdir -p olympix-results/{mutation_test,unit_test,bugpocer_pocs}
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

Returns `mutation_test_results` event with: `total_mutations`, `killed`, `survived`, `score_percentage`, and per-mutation details. Connecting also writes `mutation-test-results-<session-id>.csv` into the workspace automatically — copy it into `olympix-results/mutation_test/` for the deliverable.

Also available at `.opix/agent/mutation-tests/results.json`.

Parse and save to `olympix-results/mutation_test/mutation_results.md`.

#### 3c. Download Unit Test Results

```bash
printf '{"action":"connect_session","data":{"session_id":"<id>"}}\n{"action":"disconnect"}\n' \
  | olympix unit-testing --agent
```

Returns `unit_test_results` event with: `total_files`, `successful_files`, `branches_coverage`, and per-file coverage data. Connecting also writes every generated `.t.sol` test file into the workspace automatically (at each file's `test_path`) — copy them into `olympix-results/unit_test/` for the deliverable.

Also available at `.opix/agent/unit-tests/results.json`.

Parse and save to `olympix-results/unit_test/unit_test_results.md`.

#### 3d. Download BugPocer Findings

```bash
printf '{"action":"disconnect"}\n' \
  | olympix connect-bp-session -s <session-id> -w . --agent
```

Returns `findings_ready` event with findings array. Each finding: `id`, `title`, `severity`, `description`, `affected_code`, `file_path`, `line_number`, plus the verdict/PoC fields: `bugpocer_verdict`, `user_verdict`, `user_verdict_reason`, `effective_verdict`, `confidence_score`, `poc_summary`, `poc_content`. Report verdicts by `effective_verdict`, distinguishing BugPocer's automated call from human review (`user_verdict` = `unreviewed` until a human sets it).

Also available at `.opix/agent/<session-id>/findings.json`. Connecting also auto-writes the artifact files (PoC exploit code under `pocs_<session-id>/` and the split `true_positives_*.md` / `unverified_*.md` reports, CLI default filter) — copy them into `olympix-results/bugpocer_pocs/`.

Parse and save to `olympix-results/bugpocer_pocs/findings.md` — the same path the `bug-pocer` skill writes, so re-assembly overwrites rather than duplicates.

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
| Static analysis not run | Run `static-analysis` skill first or skip the section |
| BugPocer not run | Mark as "Not run" — it's optional |
