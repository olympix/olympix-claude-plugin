---
name: static-analysis
description: >
  Use when the user wants Olympix static analysis run on a Foundry- or Hardhat-based Solidity
  repo — runs in agent mode, verifies the repo builds first, returns findings
  synchronously via JSONL, and saves them to olympix-results/olympix-static.md.
  TRIGGER: "static analysis", "analyze", "run analyzer", "vulnerability scan", "olympix analyze"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill, AskUserQuestion
---

# Static Analysis

Run Olympix static analysis on a Foundry- or Hardhat-based Solidity repository and save the results to `olympix-results/olympix-static.md`.

**What this tool does:** fast pattern + dataflow scan with 100+ vulnerability detectors (reentrancy, access control, arithmetic, etc.). Runs in seconds, synchronously. It flags *suspected* issues — it does not confirm exploitability (that is BugPocer's job).

**Where it fits in the flow:** `Static Analysis (you are here) → Unit Tests → Mutation Tests → BugPocer → Report`. Static is the recommended **first** step — cheapest, fastest, surfaces obvious issues before the heavier tools.

## Prerequisites

- Foundry (`forge`) or Hardhat (`npx hardhat`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry or Hardhat project

## CLI Capability Check

This skill requires agent mode (`--agent`); older Olympix CLIs do not support it. Probe first:

```bash
if ! command -v olympix >/dev/null 2>&1 && [ ! -x "$HOME/.opix/bin/olympix" ]; then echo NOT_INSTALLED;
elif olympix analyze --help 2>&1 | grep -q -- --agent; then echo AGENT_MODE; else echo LEGACY_CLI; fi
```

If `NOT_INSTALLED`, **HARD STOP** — tell the user to install the Olympix CLI from https://olympix.github.io/installation/ and rerun this skill.

If `LEGACY_CLI` (the `--agent` flag is rejected), the CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe. **HARD STOP** if the CLI still lacks `--agent`.

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication.

### Step 1: Verify Repository Builds

Read and follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md`.

**If it fails:** initialize the repo per the README. **HARD STOP** if it cannot be fixed.

### Step 2: Run Static Analysis

```bash
mkdir -p olympix-results
olympix analyze -w . --agent
```

This runs the analyzer in agent mode.

**Options:**
- `--agent` — agent mode, single-line JSONL output (required for this skill)
- `-w .` — workspace directory (current directory)
- `-p <path>` — restrict analysis to a specific directory (can repeat)

Output is a single JSONL line:

```json
{"event":"findings_ready","data":{"findings":[{"id":"...","title":"<vulnerability-slug>","severity":"High","description":"...","affected_code":"...","file_path":"...","line_number":0}]}}
```

Each finding may carry: `id`, `title`, `severity`, `description`, `affected_code`, `file_path`, `line_number`. Only `title`, `description`, `file_path`, and `line_number` are guaranteed.

**Field semantics on the agent path:**
- `title` is the **vulnerability slug** (e.g. `reentrancy-eth`) — there is no separate detector field.
- `severity` is `Low`, `Medium`, or `High`, derived from the detector metadata by slug (unknown slugs default to `Medium`). The field is **omitted from the JSON** when the metadata fetch fails (it is null and null fields are not serialized) — and older CLIs never emit it. Handle its absence gracefully.
- `affected_code` is the highlighted source excerpt — **but the dev agent build does NOT emit it.** When findings carry only `description`/`file_path`/`line_number`/`severity`/`title`, there is no source excerpt. Degrade gracefully: omit the "Affected code" block entirely rather than printing an empty fence, and pull the snippet from the file at `file_path:line_number` yourself only if the user later asks.
- **Verdict-noise fields — NEVER surface these to the user.** The shared finding payload carries `bugpocer_verdict`, `user_verdict`, `effective_verdict` (all `"n/a"`) and `confidence_score` (`0`). They are meaningless for static analysis. Drop them silently — do NOT mention them, do NOT say you "ignored verdict noise", do NOT reference BugPocer at all in a static-analysis run. The user should never see the word "verdict" come out of static analysis.

**If the workspace has no Solidity files**, the CLI emits an `error` event whose message starts with `No Solidity files found in workspace` — match on that prefix; there are two variants:
```json
{"event":"error","data":{"message":"No Solidity files found in workspace"}}
```
(the common empty-workspace path), or
```json
{"event":"error","data":{"message":"No Solidity files found in workspace — aborting analysis"}}
```
(a post-upload edge case). Exit code 1. Report this to the user.

**Using -p for specific paths:**
```bash
olympix analyze -w . -p src/core --agent
```

### Step 3: Save Results to olympix-results/olympix-static.md

Parse the JSONL output and convert findings to a readable markdown summary at `olympix-results/olympix-static.md`:

Group and count findings by `severity` when the field is present; within each severity group, sub-group by vulnerability slug (the `title` field). When `severity` is absent (older CLI, or the metadata fetch failed), fall back to grouping by slug only — do NOT invent severity values or a detector field.

```markdown
# Olympix Static Analysis Results

**Date:** {date}
**Repo:** {repo name}
**Commit:** {commit hash}

## Summary

- Total findings: {count}
- By severity (when present): High: {count} · Medium: {count} · Low: {count}
- {vulnerability slug}: {count}
- (one line per vulnerability slug)

## Findings

### {vulnerability slug}

#### {file path}:{line}

- **Description:** {description}
- **Affected code:** *(include this block ONLY when `affected_code` is present — the dev agent build omits it; never print an empty fence)*

  ```solidity
  {affected_code}
  ```

---
(repeat for each finding, grouped by vulnerability slug)
```

**Severity:** when findings carry a `severity` field, add severity counts to the Summary and prefix finding headings with the severity. When the field is absent from the JSON (older CLI, or the metadata fetch failed), skip severity in the report rather than inventing values. The legacy `olympix analyze -f json -o .` fallback also includes a `Severity` field per finding — use it the same way.

**Fallback:** If agent mode output is not parseable, run without `--agent`:
```bash
olympix analyze -f json -o .
```
and parse the JSON file.

### Step 4: Report to User

Tell the user:
- How many findings, broken down by severity (when present) and by vulnerability type
- That full results are saved in `olympix-results/olympix-static.md`
- Highlight the most impactful findings (e.g. reentrancy, access control, fund-loss vectors)

Do NOT mention verdict fields, confidence scores, or BugPocer here — see the field semantics above.

### Step 5: Offer to Triage the Findings

Static analysis flags *suspected* issues; it does not confirm them. Right after reporting, **proactively ask the user** (use `AskUserQuestion`) whether they want you to triage the findings — read each flagged location against the actual source, mark likely true vs false positives, and prioritize what to fix first.

- **"Yes, triage them"** — for each finding (start with the highest-severity cluster), open `file_path:line_number`, read the surrounding code, and classify it as likely-real / likely-false-positive / needs-deeper-review with a one-line reason. Group by file so concentrated clusters (e.g. many reentrancy hits in one contract) are obvious.
- **"No, just the list"** — stop here; the saved report is the deliverable.

Make this offer every run — it is the natural next step after a scan, and the whole point of running the analyzer.

## CLI Options

| Flag | Description |
|------|-------------|
| `--agent` | Agent mode — JSONL output (required for this skill) |
| `-w <path>` | Workspace directory (defaults to cwd) |
| `-p <path>` | Specific directory to analyze (can repeat) |
| `-f json` | JSON output format (non-agent fallback) |
| `-f sarif` | SARIF output format (non-agent fallback) |
| `-o <path>` | Output directory (for json/sarif, non-agent) |
| `-ail` | Enable AI layer to prune findings |
| `-aic <level>` | AI confidence threshold (high/medium/low) |
| `--no-<vuln-id>` | Ignore specific vulnerability type |

## Quick Reference

| Step | Command / Action | Gate |
|------|-----------------|------|
| 0 | Run `auth` skill | Must be authenticated |
| 1 | Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/forge-setup.md` | Must compile |
| 2 | `olympix analyze -w . --agent` | Synchronous — waits for results |
| 3 | Parse JSONL → `olympix-results/olympix-static.md` | — |
| 4 | Report summary to user (no verdict/BugPocer talk) | — |
| 5 | Offer to triage findings against source (`AskUserQuestion`) | Always offer |

## Common Issues

| Problem | Solution |
|---------|----------|
| `forge build` fails | Install deps per README; HARD STOP if unfixable |
| `--agent` flag rejected | CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe |
| No Solidity files in workspace | CLI emits `error` event whose message starts with `"No Solidity files found in workspace"` (one variant appends `— aborting analysis`), exit code 1 — report to user |
| Agent-mode output not parseable | Fall back to `olympix analyze -f json -o .` and parse the JSON file |
| Too many low-severity findings | Use `-ail` to enable AI pruning, or `-aic medium` to hide low-confidence findings |
