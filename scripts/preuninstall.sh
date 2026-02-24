#!/bin/bash
# claude-statusline npm preuninstall script
# Removes statusline.sh, cache, and cleans settings.json

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
STATUSLINE_FILE="$CLAUDE_DIR/statusline.sh"
CACHE_FILE="$CLAUDE_DIR/stats-cache.json"

# Remove statusline.sh
if [ -f "$STATUSLINE_FILE" ]; then
  rm "$STATUSLINE_FILE"
  echo "claude-statusline: removed $STATUSLINE_FILE"
else
  echo "claude-statusline: statusline.sh not found (already removed?)"
fi

# Remove cache file
if [ -f "$CACHE_FILE" ]; then
  rm "$CACHE_FILE"
  echo "claude-statusline: removed $CACHE_FILE"
fi

# Remove statusline setting from settings.json
if [ -f "$SETTINGS_FILE" ]; then
  if command -v jq &>/dev/null; then
    trap 'rm -f "$SETTINGS_FILE.tmp"' EXIT
    jq 'del(.statusline)' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    echo "claude-statusline: cleaned $SETTINGS_FILE"
  else
    echo "claude-statusline: WARNING - jq not found, please manually remove 'statusline' from $SETTINGS_FILE"
  fi
fi

echo "claude-statusline: restart Claude Code to apply changes"
