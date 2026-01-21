#!/bin/bash
# claude-statusline uninstaller
# Repository: https://github.com/ahngbeom/claude-statusline

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
STATUSLINE_FILE="$CLAUDE_DIR/statusline.sh"
CACHE_FILE="$CLAUDE_DIR/stats-cache.json"

# Colors
RED='\033[0;31m'
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

  if [ -f "$STATUSLINE_FILE" ]; then
    rm "$STATUSLINE_FILE"
    print_success "Removed $STATUSLINE_FILE"
  else
    print_warning "statusline.sh not found (already removed?)"
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
}

# Update settings.json
update_settings() {
  print_step "Updating Claude Code settings..."

  if [ -f "$SETTINGS_FILE" ]; then
    if command -v jq &>/dev/null; then
      # Remove statusline setting
      jq 'del(.statusline)' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
      mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      print_success "Removed statusline setting from $SETTINGS_FILE"
    else
      print_warning "jq not found, please manually remove 'statusline' from $SETTINGS_FILE"
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
