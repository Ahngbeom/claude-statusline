#!/bin/bash
# claude-statusline installer
# Repository: https://github.com/ahngbeom/claude-statusline

set -e

REPO="ahngbeom/claude-statusline"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
STATUSLINE_FILE="$CLAUDE_DIR/statusline.sh"
CONFIGURE_FILE="$CLAUDE_DIR/configure.sh"

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
  echo -e "${CYAN}║${NC}       ${BLUE}claude-statusline${NC} installer                     ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}       A detailed statusline for Claude Code          ${CYAN}║${NC}"
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

print_error() {
  echo -e "${RED}✗${NC} $1"
}

# Check dependencies
check_deps() {
  print_step "Checking dependencies..."

  if ! command -v jq &>/dev/null; then
    print_error "jq is required but not installed."
    echo ""
    echo "  Install jq:"
    echo "    - macOS:  brew install jq"
    echo "    - Ubuntu: sudo apt install jq"
    echo "    - Fedora: sudo dnf install jq"
    echo ""
    exit 1
  fi
  print_success "jq found"

  if ! command -v curl &>/dev/null; then
    print_error "curl is required but not installed."
    exit 1
  fi
  print_success "curl found"

  # Optional: Check for ccusage
  if command -v ccusage &>/dev/null || command -v npx &>/dev/null; then
    print_success "ccusage support available (usage statistics will be shown)"
  else
    print_warning "ccusage not found (usage statistics will be limited)"
    echo "         Install with: npm install -g ccusage"
  fi
}

# Create Claude directory if it doesn't exist
create_claude_dir() {
  print_step "Creating Claude directory..."

  if [ ! -d "$CLAUDE_DIR" ]; then
    mkdir -p "$CLAUDE_DIR"
    print_success "Created $CLAUDE_DIR"
  else
    print_success "Directory exists: $CLAUDE_DIR"
  fi
}

# Download statusline.sh
download_statusline() {
  print_step "Downloading statusline.sh..."

  curl -fsSL "https://raw.githubusercontent.com/$REPO/main/statusline.sh" \
    -o "$STATUSLINE_FILE"
  chmod +x "$STATUSLINE_FILE"

  print_success "Downloaded to $STATUSLINE_FILE"
}

# Download configure.sh (per-user settings CLI/TUI)
download_configure() {
  print_step "Downloading configure.sh..."

  curl -fsSL "https://raw.githubusercontent.com/$REPO/main/configure.sh" \
    -o "$CONFIGURE_FILE"
  chmod +x "$CONFIGURE_FILE"

  print_success "Downloaded to $CONFIGURE_FILE"
}

# Update settings.json
update_settings() {
  print_step "Updating Claude Code settings..."

  if [ -f "$SETTINGS_FILE" ]; then
    # Backup existing settings
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"

    # Add or update statusline setting
    trap 'rm -f "$SETTINGS_FILE.tmp"' EXIT
    jq '.statusline = "~/.claude/statusline.sh"' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

    print_success "Updated $SETTINGS_FILE"
    print_success "Backup saved to $SETTINGS_FILE.backup"
  else
    # Create new settings file
    echo '{"statusline": "~/.claude/statusline.sh"}' | jq '.' > "$SETTINGS_FILE"
    print_success "Created $SETTINGS_FILE"
  fi
}

# Print completion message
print_completion() {
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║${NC}       Installation completed successfully!            ${GREEN}║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "  Statusline features (3-line compact layout):"
  echo "    📂 Directory + Git branch │ Model, Version, Style"
  echo "    🧠 Context ▰▱ bar │ Session time + tokens │ Cache + Speed"
  echo "    💰 Today │ Week │ Month usage & costs"
  echo ""
  echo -e "  ${YELLOW}Restart Claude Code to see the statusline.${NC}"
  echo ""
  echo "  Customize what's shown: ~/.claude/configure.sh"
  echo ""
  echo "  To uninstall:"
  echo "    curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
  echo ""
}

# Main
main() {
  print_header
  check_deps
  create_claude_dir
  download_statusline
  download_configure
  update_settings
  print_completion
}

main
