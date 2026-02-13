#!/bin/bash
# claude-statusline npm postinstall script
# Copies statusline.sh to ~/.claude/ and configures settings.json

set -e

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
STATUSLINE_FILE="$CLAUDE_DIR/statusline.sh"

# Resolve package root (scripts/ -> package root)
PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FILE="$PACKAGE_DIR/statusline.sh"

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

# Update settings.json
if command -v jq &>/dev/null; then
  if [ -f "$SETTINGS_FILE" ]; then
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"
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
