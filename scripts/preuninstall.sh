#!/bin/bash
# claude-statusline npm preuninstall script
# Removes statusline.sh, cache, and cleans settings.json

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

# Remove statusline.sh, unless it is the user's own script
if [ -f "$STATUSLINE_FILE" ] && ! head -n 2 "$STATUSLINE_FILE" | grep -q '^# claude-statusline - '; then
  KEEP_STATUSLINE_SETTING=1
  echo "claude-statusline: kept $STATUSLINE_FILE (not installed by claude-statusline)"
elif [ -f "$STATUSLINE_FILE" ]; then
  rm "$STATUSLINE_FILE"
  echo "claude-statusline: removed $STATUSLINE_FILE"
else
  echo "claude-statusline: statusline.sh not found (already removed?)"
fi

# Remove configure.sh
if [ -f "$CONFIGURE_FILE" ]; then
  rm "$CONFIGURE_FILE"
  echo "claude-statusline: removed $CONFIGURE_FILE"
fi

# Remove cache file
if [ -f "$CACHE_FILE" ]; then
  rm "$CACHE_FILE"
  echo "claude-statusline: removed $CACHE_FILE"
fi

if [ -f "$RATE_LIMITS_CACHE_FILE" ]; then
  rm "$RATE_LIMITS_CACHE_FILE"
  echo "claude-statusline: removed $RATE_LIMITS_CACHE_FILE"
fi

if [ -f "$CONFIG_FILE" ]; then
  rm "$CONFIG_FILE"
  echo "claude-statusline: removed $CONFIG_FILE"
fi

if [ -d "$STATE_DIR" ]; then
  rm -f "$STATE_DIR"/*
  rmdir "$STATE_DIR" 2>/dev/null
  echo "claude-statusline: removed $STATE_DIR"
fi

# Remove statusline setting from settings.json
if [ -f "$SETTINGS_FILE" ]; then
  if command -v jq &>/dev/null; then
    trap 'rm -f "$SETTINGS_FILE.tmp"' EXIT
    if jq --arg cmd "$STATUSLINE_CMD" --arg abs "$STATUSLINE_FILE" --arg keep "$KEEP_STATUSLINE_SETTING" \
      'del(.statusline) | if $keep == "" and (.statusLine | type) == "object" and (.statusLine.command == $cmd or .statusLine.command == $abs) then del(.statusLine) else . end' \
      "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" 2>/dev/null; then
      mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      echo "claude-statusline: cleaned $SETTINGS_FILE"
    else
      rm -f "$SETTINGS_FILE.tmp"
      echo "claude-statusline: WARNING - failed to update $SETTINGS_FILE"
    fi
  else
    echo "claude-statusline: WARNING - jq not found, please manually remove 'statusLine' from $SETTINGS_FILE"
  fi
fi

echo "claude-statusline: restart Claude Code to apply changes"
