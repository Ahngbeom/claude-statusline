#!/bin/bash
# claude-statusline uninstaller
# Repository: https://github.com/ahngbeom/claude-statusline

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
STATUSLINE_FILE="$CLAUDE_DIR/statusline.sh"
CONFIGURE_FILE="$CLAUDE_DIR/configure.sh"
CACHE_FILE="$CLAUDE_DIR/stats-cache.json"
RATE_LIMITS_CACHE_FILE="$CLAUDE_DIR/rate-limits-cache.json"
CONFIG_FILE="$CLAUDE_DIR/statusline.conf"
# shellcheck disable=SC2088 # literal ~ on purpose: Claude Code expands it
STATUSLINE_CMD="~/.claude/statusline.sh"
KEEP_STATUSLINE_SETTING=""
STATE_DIR="$CLAUDE_DIR/statusline-state"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}       ${BLUE}claude-statusline${NC} uninstaller                   ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_step() {
  echo -e "${BLUE}==>${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}!${NC} $1"
}

# Remove statusline.sh
remove_statusline() {
  print_step "Removing statusline.sh..."

  if [ -f "$STATUSLINE_FILE" ] && ! head -n 2 "$STATUSLINE_FILE" | grep -q '^# claude-statusline - '; then
    KEEP_STATUSLINE_SETTING=1
    print_warning "Kept $STATUSLINE_FILE (not installed by claude-statusline)"
  elif [ -f "$STATUSLINE_FILE" ]; then
    rm "$STATUSLINE_FILE"
    print_success "Removed $STATUSLINE_FILE"
  else
    print_warning "statusline.sh not found (already removed?)"
  fi

  if [ -f "$CONFIGURE_FILE" ]; then
    rm "$CONFIGURE_FILE"
    print_success "Removed $CONFIGURE_FILE"
  else
    print_warning "configure.sh not found (already removed?)"
  fi
}

# Remove cache file
remove_cache() {
  print_step "Removing cache file..."

  if [ -f "$CACHE_FILE" ]; then
    rm "$CACHE_FILE"
    print_success "Removed $CACHE_FILE"
  else
    print_warning "Cache file not found"
  fi

  if [ -f "$RATE_LIMITS_CACHE_FILE" ]; then
    rm "$RATE_LIMITS_CACHE_FILE"
    print_success "Removed $RATE_LIMITS_CACHE_FILE"
  else
    print_warning "Rate limits cache file not found"
  fi

  if [ -f "$CONFIG_FILE" ]; then
    rm "$CONFIG_FILE"
    print_success "Removed $CONFIG_FILE"
  else
    print_warning "Config file not found"
  fi

  if [ -d "$STATE_DIR" ]; then
    rm -f "$STATE_DIR"/*
    rmdir "$STATE_DIR" 2>/dev/null
    print_success "Removed $STATE_DIR"
  fi
}

# Update settings.json
update_settings() {
  print_step "Updating Claude Code settings..."

  if [ -f "$SETTINGS_FILE" ]; then
    if command -v jq &>/dev/null; then
      trap 'rm -f "$SETTINGS_FILE.tmp"' EXIT
      if jq --arg cmd "$STATUSLINE_CMD" --arg abs "$STATUSLINE_FILE" --arg keep "$KEEP_STATUSLINE_SETTING" \
        'del(.statusline) | if $keep == "" and (.statusLine | type) == "object" and (.statusLine.command == $cmd or .statusLine.command == $abs) then del(.statusLine) else . end' \
        "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" 2>/dev/null; then
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        print_success "Removed statusline setting from $SETTINGS_FILE"
      else
        rm -f "$SETTINGS_FILE.tmp"
        print_warning "Failed to update $SETTINGS_FILE - please manually remove the 'statusLine' key"
      fi
    else
      print_warning "jq not found, please manually remove 'statusLine' from $SETTINGS_FILE"
    fi
  else
    print_warning "Settings file not found"
  fi
}

# Print completion message
print_completion() {
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC}       Uninstallation completed successfully!         ${GREEN}║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${YELLOW}Restart Claude Code to apply changes.${NC}"
  echo ""
  echo "  To reinstall:"
  echo "    curl -fsSL https://raw.githubusercontent.com/ahngbeom/claude-statusline/main/install.sh | bash"
  echo ""
}

# Main
main() {
  print_header
  remove_statusline
  remove_cache
  update_settings
  print_completion
}

main
