---
name: bug-pocer
description: >
  Prepares a Foundry-based Solidity repo for Olympix BugPocer security analysis.
  Verifies the repo builds, then launches the interactive bug-pocer session.
  BugPocer requires user interaction (TUI) — Claude prepares the repo and
  hands off to the user for the interactive session.
  TRIGGER: "bug pocer", "bugpocer", "security analysis", "run bug-pocer", "exploit generation", "bug-pocer"
tools: Read, Glob, Grep, Bash, Agent
---

# BugPocer Security Analysis

Prepare a Foundry-based Solidity repository for Olympix BugPocer security analysis by verifying the repo builds and launching the interactive session.

## Prerequisites

- Foundry (`forge`) installed
- `olympix` CLI installed and authenticated
- Working directory is the root of a Foundry project

## Important: BugPocer is Interactive

BugPocer is a **TUI-based interactive security analysis tool**. It requires user interaction at multiple stages:

1. **Scope review** — review and modify which files/contracts to analyze
2. **Project context validation** — validate AI-generated project context (requires keyboard input)
3. **Question/answer loop** — interact with the BugPocer AI agent
4. **Session menu** — view findings, generate reports

**Claude cannot drive the TUI.** The role of this skill is to prepare the repo so the user can run bug-pocer themselves. After preparation, instruct the user to run the command interactively via `!`.

## Process

### Step 0: Verify Olympix Authentication

Follow the `auth` skill to check authentication and automate login via Gmail if needed. If Gmail MCP is not connected, fall back to asking the user to run `! olympix login -e email` manually.

### Step 1: Verify Repository Builds

Run forge build to check the repo compiles:

```bash
forge build
```

**If it succeeds:** proceed to Step 3.

**If it fails:** go to Step 2.

**If it cannot be fixed:** **HARD STOP.** The repo must compile for BugPocer.

### Step 2: Initialize Repository

If forge build failed due to missing dependencies or configuration:

1. Read the project's README for setup instructions
2. Run the recommended initialization steps (e.g., `forge install`, `npm install --legacy-peer-deps`, `git submodule update --init --recursive`)
3. If there's a `remappings.txt` or the `foundry.toml` references remappings, verify they resolve
4. Re-run `forge build`
5. If it fails for other reasons → attempt to resolve, but do not spend more than 2 attempts before asking the user for help

### Step 3: Hand Off to User

The repo is ready. Instruct the user to run the BugPocer session interactively.

**Run BugPocer:**
```
! olympix bug-pocer
```

**With explicit workspace path:**
```
! olympix bug-pocer -w /path/to/repo
```

Tell the user:
> "The repo builds successfully. Run `! olympix bug-pocer` to start the interactive BugPocer session."

## CLI Options

| Flag | Long | Description |
|------|------|-------------|
| `-w` | `--workspace-path` | Root project directory (defaults to cwd) |

## Quick Reference

| Step | Command / Action | Gate |
|------|-----------------|------|
| 1 | `forge build` | Must compile |
| 2 | Init repo per README | Only if Step 1 fails |
| 3 | Tell user to run `! olympix bug-pocer` | User-driven |

## Common Issues

| Problem | Solution |
|---------|----------|
| `forge build` fails with missing imports | Install deps per README (`forge install`, `npm install --legacy-peer-deps`, etc.) |
| TUI doesn't render properly | Make sure terminal supports ANSI escape codes; don't run via pipe or redirection |
| Want fully non-interactive mode | Not currently supported — BugPocer requires interactive input for scope review, context validation, and Q&A |
