#!/bin/bash
# Olympix Claude Plugin — Isolated Skill Test Harness (#2)
#
# Runs the plugin's skills against a throwaway Foundry repo using a sandboxed
# Claude Code config, so NOTHING touches your live ~/.claude setup:
#   - CLAUDE_CONFIG_DIR points at a fresh temp dir   → no live settings/hooks/CLAUDE.md
#   - claude --plugin-dir <this plugin>              → loads ONLY this plugin, session-scoped
#   - a copied fixture Foundry repo                  → deterministic scope, hermetic build
#
# This isolates the SKILLS + plugin. To also isolate the BACKEND (so scans don't
# hit dev/prod), point the olympix CLI at a per-branch backend first via the
# internal `new-dotnet-branch` skill, then run this with that env exported.
#
# Usage:
#   scripts/run-skill-isolated.sh [-c CONFIG_DIR] [-w WORKSPACE] [-f FIXTURE] [--keep] [-- <extra claude args>]
#
#   -c CONFIG_DIR   sandbox CLAUDE_CONFIG_DIR (default: a fresh mktemp dir)
#   -w WORKSPACE    workspace to run in (default: a fresh copy of the fixture)
#   -f FIXTURE      fixture repo to copy when -w is not given (default: fixtures/vuln-foundry)
#   --keep          do not delete the sandbox on exit (for inspection)
#   --no-build      skip the `forge build` sanity check
#   -- ARGS...      everything after -- is passed verbatim to `claude`
#
# Examples:
#   scripts/run-skill-isolated.sh                       # interactive, fresh sandbox
#   scripts/run-skill-isolated.sh -- -p "/bug-pocer"    # headless: drive the bug-pocer skill
#   scripts/run-skill-isolated.sh --keep -c /tmp/opix-sbx
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

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c) CONFIG_DIR="$2"; shift 2 ;;
        -w) WORKSPACE="$2"; shift 2 ;;
        -f) FIXTURE="$2"; shift 2 ;;
        --keep) KEEP=1; shift ;;
        --no-build) DO_BUILD=0; shift ;;
        --) shift; CLAUDE_ARGS=("$@"); break ;;
        -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
        *) echo -e "${RED}Unknown arg: $1${NC}"; exit 1 ;;
    esac
done

# ─── Prerequisites ───
command -v claude >/dev/null || { echo -e "${RED}ERROR${NC} — 'claude' CLI not found in PATH."; exit 1; }
command -v olympix >/dev/null || echo -e "${YELLOW}WARN${NC} — 'olympix' CLI not found; skills needing it will fail."
command -v forge   >/dev/null || { echo -e "${RED}ERROR${NC} — 'forge' not found; install Foundry."; exit 1; }

# ─── Sandbox config dir (isolates from ~/.claude) ───
if [[ -z "$CONFIG_DIR" ]]; then
    CONFIG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/olympix-skill-config.XXXXXX")"
fi
mkdir -p "$CONFIG_DIR"

# ─── Sandbox workspace (fresh copy of the fixture) ───
if [[ -z "$WORKSPACE" ]]; then
    [[ -d "$FIXTURE" ]] || { echo -e "${RED}ERROR${NC} — fixture not found: $FIXTURE"; exit 1; }
    WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/olympix-skill-workspace.XXXXXX")"
    cp -R "$FIXTURE/." "$WORKSPACE/"
fi

cleanup() {
    if [[ "$KEEP" -eq 1 ]]; then
        echo -e "${YELLOW}Sandbox kept:${NC} config=$CONFIG_DIR workspace=$WORKSPACE"
    else
        rm -rf "$CONFIG_DIR" "$WORKSPACE" 2>/dev/null || true
    fi
}
trap cleanup EXIT

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
CLAUDE_CONFIG_DIR="$CONFIG_DIR" claude --plugin-dir "$PLUGIN_DIR" "${CLAUDE_ARGS[@]}"
exit $?
