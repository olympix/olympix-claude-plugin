---
name: bug-pocer
description: >
  Prepares a Foundry-based Solidity repo for Olympix BugPocer security analysis.
  Verifies the repo builds, then hands off to the user for the interactive TUI session.
  TRIGGER: "bug pocer", "bugpocer", "security analysis", "run bug-pocer", "exploit generation", "bug-pocer"
tools: Read, Glob, Grep, Bash, Agent
---

# BugPocer Security Analysis

Prepare a Foundry-based Solidity repository for Olympix BugPocer and hand off to the user for the interactive session.

## Important: BugPocer is Interactive

BugPocer is a TUI-based interactive tool. It requires user interaction for scope review, context validation, and Q&A. Claude cannot drive the TUI — this skill prepares the repo so the user can run it.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## Process

### Step 0: Verify Olympix Authentication

Run the `auth` skill to check authentication.

### Step 1: Verify Repository Builds

Read and follow `skills/_shared/forge-setup.md`.

### Step 2: Hand Off to User

The repo is ready. Tell the user:

> The repo builds successfully. Run `! olympix bug-pocer` to start the interactive BugPocer session.

**With explicit workspace path:**
```
! olympix bug-pocer -w /path/to/repo
```

## CLI Options

| Flag | Description |
|------|-------------|
| `-w`, `--workspace-path` | Root project directory (defaults to cwd) |
