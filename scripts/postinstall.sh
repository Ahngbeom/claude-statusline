#!/bin/bash
# claude-statusline npm postinstall script
# Copies statusline.sh to ~/.claude/ and configures settings.json

set -e

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
STATUSLINE_FILE="$CLAUDE_DIR/statusline.sh"
CONFIGURE_FILE="$CLAUDE_DIR/configure.sh"

# Resolve package root (scripts/ -> package root)
PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$PACKAGE_DIR/statusline.sh"
CONFIGURE_SOURCE_FILE="$PACKAGE_DIR/configure.sh"

if [ ! -f "$SOURCE_FILE" ]; then
  echo "claude-statusline: ERROR - statusline.sh not found in package"
  exit 1
fi

# Create ~/.claude/ if needed
if [ ! -d "$CLAUDE_DIR" ]; then
  mkdir -p "$CLAUDE_DIR"
  echo "claude-statusline: created $CLAUDE_DIR"
fi

# Copy statusline.sh
cp "$SOURCE_FILE" "$STATUSLINE_FILE"
chmod +x "$STATUSLINE_FILE"
echo "claude-statusline: installed $STATUSLINE_FILE"

# Copy configure.sh (per-user settings CLI/TUI)
if [ -f "$CONFIGURE_SOURCE_FILE" ]; then
  cp "$CONFIGURE_SOURCE_FILE" "$CONFIGURE_FILE"
  chmod +x "$CONFIGURE_FILE"
  echo "claude-statusline: installed $CONFIGURE_FILE"
fi

# Update settings.json
if command -v jq &>/dev/null; then
  if [ -f "$SETTINGS_FILE" ]; then
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
    trap 'rm -f "$SETTINGS_FILE.tmp"' EXIT
    jq '.statusline = "~/.claude/statusline.sh"' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  else
    echo '{"statusline": "~/.claude/statusline.sh"}' | jq '.' > "$SETTINGS_FILE"
  fi
  echo "claude-statusline: configured $SETTINGS_FILE"
else
  echo "claude-statusline: WARNING - jq not found, please manually add '\"statusline\": \"~/.claude/statusline.sh\"' to $SETTINGS_FILE"
fi

echo "claude-statusline: restart Claude Code to activate"
