#!/bin/bash
# Olympix Claude Plugin — Setup Script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Olympix Claude Plugin Setup${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ─── Step 1: Check Prerequisites ───

echo -e "${GREEN}Step 1: Check Prerequisites${NC}"
echo ""

# Check Olympix CLI
if command -v olympix &>/dev/null; then
    OLYMPIX_VERSION=$(olympix --version 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}[installed]${NC} olympix CLI ($OLYMPIX_VERSION)"
elif [ -x "$HOME/.opix/bin/olympix" ]; then
    OLYMPIX_VERSION=$("$HOME/.opix/bin/olympix" --version 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}[installed]${NC} olympix CLI ($OLYMPIX_VERSION) at ~/.opix/bin/olympix"
else
    echo -e "  ${YELLOW}[not installed]${NC} olympix CLI"
    echo -e "  Install from: ${CYAN}https://docs.olympix.ai/cli${NC}"
fi

# Check Forge
if command -v forge &>/dev/null; then
    FORGE_VERSION=$(forge --version 2>/dev/null | head -1 || echo "unknown")
    echo -e "  ${GREEN}[installed]${NC} forge ($FORGE_VERSION)"
else
    echo -e "  ${YELLOW}[not installed]${NC} forge (Foundry)"
    echo -e "  Install from: ${CYAN}https://getfoundry.sh${NC}"
fi

echo ""

# ─── Step 2: Register Plugin with Claude Code ───

echo -e "${GREEN}Step 2: Plugin Registration${NC}"
echo ""

# Check that claude CLI is available
if ! command -v claude &>/dev/null; then
    echo -e "  ${RED}ERROR${NC} — 'claude' CLI not found in PATH."
    echo "  Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code/overview"
    exit 1
fi

# Determine install scope
echo "  Where should the plugin be registered?"
echo ""
echo "    1. Global    — all projects (~/.claude/settings.json)"
echo "    2. Workspace — this workspace only (.claude/settings.local.json)"
echo ""
read -p "  Choice [1]: " INSTALL_SCOPE
case ${INSTALL_SCOPE:-1} in
    1) INSTALL_MODE="global" ;;
    2) INSTALL_MODE="workspace" ;;
    *) INSTALL_MODE="global" ;;
esac
echo -e "  ${GREEN}OK${NC} — $INSTALL_MODE install"
echo ""

# Determine settings file
if [ "$INSTALL_MODE" = "global" ]; then
    SETTINGS_FILE="$HOME/.claude/settings.json"
else
    SETTINGS_FILE="$(pwd)/.claude/settings.local.json"
fi

# Create a marketplace wrapper around the plugin directory
MARKETPLACE_DIR="${PLUGIN_DIR%/*}/olympix-plugin-marketplace"
mkdir -p "$MARKETPLACE_DIR/.claude-plugin"
ln -sfn "$PLUGIN_DIR" "$MARKETPLACE_DIR/olympix-claude-plugin"

cat > "$MARKETPLACE_DIR/.claude-plugin/marketplace.json" << MKJSON
{
  "\$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "olympix",
  "description": "Olympix smart contract security tools for Claude Code",
  "owner": { "name": "Olympix", "email": "engineering@olympix.ai" },
  "plugins": [
    {
      "name": "olympix-claude-plugin",
      "description": "Run Olympix security tools from Claude Code",
      "source": "./olympix-claude-plugin",
      "category": "development"
    }
  ]
}
MKJSON

echo "  Registering marketplace..."

# Add plugin path to settings
mkdir -p "$(dirname "$SETTINGS_FILE")"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

if command -v jq &>/dev/null; then
    tmp_file=$(mktemp)
    jq --arg mp_path "$MARKETPLACE_DIR" '
      .enabledPlugins["olympix-claude-plugin@olympix"] = true |
      .extraKnownMarketplaces.olympix = {
        "source": { "source": "directory", "path": $mp_path }
      }
    ' "$SETTINGS_FILE" > "$tmp_file" && mv "$tmp_file" "$SETTINGS_FILE"
    echo -e "  ${GREEN}OK${NC} — plugin registered in $(basename "$SETTINGS_FILE")"
else
    echo -e "  ${YELLOW}WARN${NC} — jq not installed, cannot update settings automatically"
    echo "  Add the following to $SETTINGS_FILE:"
    echo ""
    echo "    \"enabledPlugins\": { \"olympix-claude-plugin@olympix\": true },"
    echo "    \"extraKnownMarketplaces\": { \"olympix\": { \"source\": { \"source\": \"directory\", \"path\": \"$MARKETPLACE_DIR\" } } }"
fi

echo ""

# ─── Step 3: Add CLI Permissions ───

echo -e "${GREEN}Step 3: CLI Permissions${NC}"
echo ""

OLYMPIX_PERMISSIONS=(
    'Bash(olympix:*)'
    'Bash(forge:*)'
)

if command -v jq &>/dev/null; then
    ADDED=0
    for perm in "${OLYMPIX_PERMISSIONS[@]}"; do
        if ! jq -e --arg p "$perm" '.permissions.allow // [] | index($p)' "$SETTINGS_FILE" &>/dev/null; then
            tmp_file=$(mktemp)
            jq --arg p "$perm" '.permissions.allow //= [] | .permissions.allow += [$p]' "$SETTINGS_FILE" > "$tmp_file" && mv "$tmp_file" "$SETTINGS_FILE"
            ADDED=$((ADDED + 1))
        fi
    done
    if [ "$ADDED" -gt 0 ]; then
        echo -e "  ${GREEN}OK${NC} — added $ADDED permission(s) to $(basename "$SETTINGS_FILE")"
    else
        echo -e "  ${GREEN}OK${NC} — all permissions already present"
    fi
else
    echo -e "  ${YELLOW}WARN${NC} — jq not installed, cannot update settings automatically"
    echo "  Manually add these to $SETTINGS_FILE under permissions.allow:"
    for perm in "${OLYMPIX_PERMISSIONS[@]}"; do
        echo "    \"$perm\""
    done
fi

echo ""

# ─── Done ───

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Setup Complete!${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "Restart Claude Code to activate the plugin."
echo ""
echo -e "${GREEN}Quick start:${NC}"
echo "  Open Claude Code in a Foundry project and run:"
echo -e "  ${CYAN}/olympix:full-run${NC}"
echo ""
echo "Available skills:"
echo "  olympix:full-run          — Run all Olympix tools on a Foundry repo"
echo "  olympix:static-analysis   — Run vulnerability scanner"
echo "  olympix:mutation-test     — Generate mutation tests for top 10 contracts"
echo "  olympix:fuzz-test         — Generate fuzz tests for top 3 contracts"
echo "  olympix:unit-test         — Generate unit tests with coverage scaffolding"
echo "  olympix:bug-pocer         — Launch BugPocer interactive security analysis"
echo "  olympix:assemble-report   — Collect results into olympix-results/report.md"
echo "  olympix:auth              — Check/refresh CLI authentication"
echo ""
