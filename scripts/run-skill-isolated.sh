#!/bin/bash
# Olympix Claude Plugin — Isolated Skill Test Harness (#2)
#
# Runs the plugin's skills against a throwaway Foundry repo using a sandboxed
# Claude Code config, so NOTHING touches your live ~/.claude setup:
#   - CLAUDE_CONFIG_DIR points at a fresh temp dir   → no live settings/hooks/CLAUDE.md
#   - claude --plugin-dir <this plugin>              → loads ONLY this plugin, session-scoped
#   - a copied fixture Foundry repo                  → deterministic scope, hermetic build
#
# This isolates the SKILLS + plugin. To also isolate the BACKEND, set the
# relevant OLYMPIX env vars to point at a different backend if needed, and
# export them before running this script.
#
# Run with -h/--help for usage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

CONFIG_DIR=""
WORKSPACE=""
FIXTURE="$PLUGIN_DIR/fixtures/vuln-foundry"
KEEP=0
DO_BUILD=1
CLAUDE_ARGS=()
CREATED_CONFIG=0
CREATED_WORKSPACE=0

usage() {
    cat <<'USAGE'
Olympix Claude Plugin — Isolated Skill Test Harness

Runs the plugin's skills against a throwaway Foundry repo using a sandboxed
Claude Code config, so NOTHING touches your live ~/.claude setup:
  - CLAUDE_CONFIG_DIR points at a fresh temp dir   → no live settings/hooks/CLAUDE.md
  - claude --plugin-dir <this plugin>              → loads ONLY this plugin, session-scoped
  - a copied fixture Foundry repo                  → deterministic scope, hermetic build

This isolates the SKILLS + plugin. To also isolate the BACKEND, set the
relevant OLYMPIX env vars to point at a different backend if needed.

Usage:
  scripts/run-skill-isolated.sh [-c CONFIG_DIR] [-w WORKSPACE] [-f FIXTURE] [--keep] [-- <extra claude args>]

  -c CONFIG_DIR   sandbox CLAUDE_CONFIG_DIR (default: a fresh mktemp dir)
  -w WORKSPACE    workspace to run in (default: a fresh copy of the fixture)
  -f FIXTURE      fixture repo to copy when -w is not given (default: fixtures/vuln-foundry)
  --keep          do not delete the sandbox on exit (for inspection)
  --no-build      skip the `forge build` sanity check
  -- ARGS...      everything after -- is passed verbatim to `claude`

Only directories CREATED by this script are deleted on exit; paths you pass
via -c/-w are never removed.

Examples:
  scripts/run-skill-isolated.sh                       # interactive, fresh sandbox
  scripts/run-skill-isolated.sh -- -p "/bug-pocer"    # headless: drive the bug-pocer skill
  scripts/run-skill-isolated.sh --keep -c /tmp/opix-sbx
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c) [[ $# -ge 2 ]] || { echo -e "${RED}Missing value for $1${NC}"; exit 1; }
            CONFIG_DIR="$2"; shift 2 ;;
        -w) [[ $# -ge 2 ]] || { echo -e "${RED}Missing value for $1${NC}"; exit 1; }
            WORKSPACE="$2"; shift 2 ;;
        -f) [[ $# -ge 2 ]] || { echo -e "${RED}Missing value for $1${NC}"; exit 1; }
            FIXTURE="$2"; shift 2 ;;
        --keep) KEEP=1; shift ;;
        --no-build) DO_BUILD=0; shift ;;
        --) shift; CLAUDE_ARGS=("$@"); break ;;
        -h|--help) usage; exit 0 ;;
        *) echo -e "${RED}Unknown arg: $1${NC}"; exit 1 ;;
    esac
done

# ─── Prerequisites ───
command -v claude >/dev/null || { echo -e "${RED}ERROR${NC} — 'claude' CLI not found in PATH."; exit 1; }
command -v olympix >/dev/null || echo -e "${YELLOW}WARN${NC} — 'olympix' CLI not found; skills needing it will fail."
command -v forge   >/dev/null || { echo -e "${RED}ERROR${NC} — 'forge' not found; install Foundry."; exit 1; }

cleanup() {
    # Only ever delete directories this script created itself (mktemp branches).
    # User-supplied -c/-w paths are NEVER removed.
    if [[ "$KEEP" -eq 1 ]]; then
        echo -e "${YELLOW}Sandbox kept:${NC} config=$CONFIG_DIR workspace=$WORKSPACE"
    else
        [[ "$CREATED_CONFIG" -eq 1 ]] && rm -rf "$CONFIG_DIR" 2>/dev/null || true
        [[ "$CREATED_WORKSPACE" -eq 1 ]] && rm -rf "$WORKSPACE" 2>/dev/null || true
    fi
}
# Installed BEFORE the first mktemp so early failures don't leak temp dirs
# (CREATED_* flags default 0, so cleanup is a no-op until dirs are created).
trap cleanup EXIT

# ─── Sandbox config dir (isolates from ~/.claude) ───
if [[ -z "$CONFIG_DIR" ]]; then
    CONFIG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/olympix-skill-config.XXXXXX")"
    CREATED_CONFIG=1
fi
mkdir -p "$CONFIG_DIR"

# ─── Sandbox workspace (fresh copy of the fixture) ───
if [[ -z "$WORKSPACE" ]]; then
    [[ -d "$FIXTURE" ]] || { echo -e "${RED}ERROR${NC} — fixture not found: $FIXTURE"; exit 1; }
    WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/olympix-skill-workspace.XXXXXX")"
    cp -R "$FIXTURE/." "$WORKSPACE/"
    CREATED_WORKSPACE=1
fi

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Olympix Plugin — Isolated Skill Test${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "  plugin    : ${GREEN}$PLUGIN_DIR${NC}"
echo -e "  config    : ${GREEN}$CONFIG_DIR${NC}  (CLAUDE_CONFIG_DIR — live ~/.claude untouched)"
echo -e "  workspace : ${GREEN}$WORKSPACE${NC}"
echo ""

# ─── Hermetic build sanity check ───
if [[ "$DO_BUILD" -eq 1 ]]; then
    echo -e "${GREEN}forge build${NC} (fixture sanity check)…"
    ( cd "$WORKSPACE" && forge build >/dev/null ) \
        && echo -e "  ${GREEN}build ok${NC}\n" \
        || { echo -e "  ${RED}build failed${NC} — fixture is broken, aborting."; exit 1; }
fi

# ─── Launch claude in the sandbox ───
# CLAUDE_CONFIG_DIR  → all config/state lands in the sandbox, not ~/.claude
# --plugin-dir       → load ONLY this plugin, for this session
echo -e "${GREEN}Launching claude${NC} (CLAUDE_CONFIG_DIR set, plugin session-scoped)…"
echo -e "${YELLOW}>${NC} claude --plugin-dir \"$PLUGIN_DIR\" ${CLAUDE_ARGS[*]:-}"
echo ""

# Not exec'd: we want the cleanup trap to fire after the session ends so the
# sandbox is removed (unless --keep). claude still inherits the TTY for interactive use.
cd "$WORKSPACE"
CLAUDE_CONFIG_DIR="$CONFIG_DIR" claude --plugin-dir "$PLUGIN_DIR" ${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"}
exit $?
