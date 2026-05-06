---
name: static-analysis
description: >
  Runs Olympix static analysis on a Foundry-based Solidity repo using agent mode
  and saves the results to olympix-results/olympix-static.md. Verifies the repo builds first.
  Returns findings synchronously via JSONL.
  TRIGGER: "static analysis", "analyze", "run analyzer", "vulnerability scan", "olympix analyze"
tools: Read, Glob, Grep, Bash
---

# Static Analysis

Run Olympix static analysis on a Foundry-based Solidity repository and save the results to `olympix-results/olympix-static.md`.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication.

### Step 1: Verify Repository Builds

Read and follow `skills/_shared/forge-setup.md`.

### Step 2: Run Static Analysis

```bash
mkdir -p olympix-results
olympix analyze -w . --agent
```

This runs the analyzer in agent mode. Output is a single JSONL line:

```json
{"event":"findings_ready","data":{"findings":[{"id":"...","title":"...","description":"...","file_path":"...","line_number":0}]}}
```

Each finding has: `id`, `title`, `description`, `file_path`, `line_number`.

**If the workspace has no Solidity files**, the CLI emits:
```json
{"event":"error","data":{"message":"No Solidity files found in workspace"}}
```
Exit code 1. Report this to the user.

**Using -p for specific paths:**
```bash
olympix analyze -w . -p src/core --agent
```

### Step 3: Save Results to olympix-results/olympix-static.md

Parse the JSONL output and convert findings to a readable markdown summary at `olympix-results/olympix-static.md`:

```markdown
# Olympix Static Analysis Results

**Date:** {date}
**Repo:** {repo name}
**Commit:** {commit hash}

## Summary

- Critical: {count}
- High: {count}
- Medium: {count}
- Low: {count}
- Informational: {count}

## Findings

### {severity}: {finding title}

- **File:** {file path}:{line}
- **Detector:** {detector id}
- **Description:** {description}

---
(repeat for each finding, grouped by severity)
```

**Fallback:** If agent mode output is not parseable, run without `--agent`:
```bash
olympix analyze -f json -o .
```
and parse the JSON file.

### Step 4: Report to User

Tell the user:
- How many findings by severity
- That full results are saved in `olympix-results/olympix-static.md`
- Highlight any Critical or High findings

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
