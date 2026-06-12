---
name: static-analysis
description: >
  Use when the user wants Olympix static analysis run on a Foundry-based Solidity
  repo — runs in agent mode, verifies the repo builds first, returns findings
  synchronously via JSONL, and saves them to olympix-results/olympix-static.md.
  TRIGGER: "static analysis", "analyze", "run analyzer", "vulnerability scan", "olympix analyze"
allowed-tools: Read, Glob, Grep, Bash, Write, Skill
---

# Static Analysis

Run Olympix static analysis on a Foundry-based Solidity repository and save the results to `olympix-results/olympix-static.md`.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## CLI Capability Check

This skill requires agent mode (`--agent`); older Olympix CLIs do not support it. Probe first:

```bash
olympix analyze --help 2>&1 | grep -q -- --agent && echo AGENT_MODE || echo LEGACY_CLI
```

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

Each finding has: `id`, `title`, `severity`, `description`, `affected_code`, `file_path`, `line_number`.

**Field semantics on the agent path:**
- `title` is the **vulnerability slug** (e.g. `reentrancy-eth`) — there is no separate detector field.
- `severity` is `Low`, `Medium`, or `High`, derived from the detector metadata by slug (unknown slugs default to `Medium`). The field is **omitted from the JSON** when the metadata fetch fails (it is null and null fields are not serialized) — and older CLIs never emit it. Handle its absence gracefully.
- `affected_code` is the highlighted source excerpt for the finding.
- The shared finding payload also carries **default verdict noise that does NOT apply to static analysis** — `bugpocer_verdict`, `user_verdict`, and `effective_verdict` are `"n/a"` and `confidence_score` is `0` for every static-analysis finding. Ignore these fields here; they are only meaningful for BugPocer.

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
- **Affected code:**

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
| 4 | Report summary to user | — |

## Common Issues

| Problem | Solution |
|---------|----------|
| `forge build` fails | Install deps per README; HARD STOP if unfixable |
| `--agent` flag rejected | CLI is pre-agent-mode — tell the user to run `olympix update`, then re-probe |
| No Solidity files in workspace | CLI emits `error` event whose message starts with `"No Solidity files found in workspace"` (one variant appends `— aborting analysis`), exit code 1 — report to user |
| Agent-mode output not parseable | Fall back to `olympix analyze -f json -o .` and parse the JSON file |
| Too many low-severity findings | Use `-ail` to enable AI pruning, or `-aic medium` to hide low-confidence findings |
