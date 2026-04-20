---
name: static-analysis
description: >
  Runs Olympix static analysis on a Foundry-based Solidity repo and saves
  the results to olympix-results/olympix-static.md. Verifies the repo builds first.
  Returns findings synchronously (not async like other Olympix tools).
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
olympix analyze -f json -o .
```

This runs the analyzer and outputs a JSON results file to the current directory.

**Options:**
- `-f json` — JSON output format (parseable)
- `-o .` — output to current directory
- `-ail` / `--ai-layer` — enable AI pruning of findings (optional, add if user requests)

### Step 3: Save Results to olympix-results/olympix-static.md

Read the JSON output file and convert it to a readable markdown summary at `olympix-results/olympix-static.md`:

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
- **Recommendation:** {recommendation}

---
(repeat for each finding, grouped by severity)
```

If the JSON output is not available or the format is unexpected, fall back to running:
```bash
olympix analyze 2>&1 | tee olympix-static-raw.txt
```
and save the raw tree output, then convert it to markdown manually.

### Step 4: Report to User

Tell the user:
- How many findings by severity
- That full results are saved in `olympix-results/olympix-static.md`
- Highlight any Critical or High findings

## CLI Options

| Flag | Description |
|------|-------------|
| `-f json` | JSON output format |
| `-f sarif` | SARIF output format |
| `-f tree` | Tree output (default, terminal) |
| `-o <path>` | Output directory (for json/sarif) |
| `-p <path>` | Specific directory to analyze (can repeat) |
| `-ail` | Enable AI layer to prune findings |
| `-aic <level>` | AI confidence threshold (high/medium/low) |
| `--no-<vuln-id>` | Ignore specific vulnerability type |
