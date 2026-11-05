#!/bin/bash
# claude-statusline npm postinstall script
# Copies statusline.sh to ~/.claude/ and configures settings.json

set -e

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
STATUSLINE_FILE="$CLAUDE_DIR/statusline.sh"
CONFIGURE_FILE="$CLAUDE_DIR/configure.sh"
# shellcheck disable=SC2088 # literal ~ on purpose: Claude Code expands it
STATUSLINE_CMD="~/.claude/statusline.sh"

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

# A ~/.claude/statusline.sh that claude-statusline did not install is the
# user's own script: keep a copy instead of silently replacing it.
if [ -f "$STATUSLINE_FILE" ] && ! head -n 2 "$STATUSLINE_FILE" | grep -q '^# claude-statusline - '; then
  BACKUP_FILE="$STATUSLINE_FILE.backup-$(date +%Y%m%d-%H%M%S)"
  cp -p "$STATUSLINE_FILE" "$BACKUP_FILE"
  echo "claude-statusline: existing $STATUSLINE_FILE was not installed by claude-statusline; saved it as $BACKUP_FILE"
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
    # Claude Code reads only statusLine; the lowercase statusline key is a dead legacy entry.
    jq --arg cmd "$STATUSLINE_CMD" 'del(.statusline) | .statusLine = ((if (.statusLine | type) == "object" then .statusLine else {} end) + {type: "command", command: $cmd})' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  else
    jq -n --arg cmd "$STATUSLINE_CMD" '{statusLine: {type: "command", command: $cmd}}' > "$SETTINGS_FILE"
  fi
  echo "claude-statusline: configured $SETTINGS_FILE"
else
  echo "claude-statusline: WARNING - jq not found, please manually add '\"statusLine\": {\"type\": \"command\", \"command\": \"~/.claude/statusline.sh\"}' to $SETTINGS_FILE"
fi

echo "claude-statusline: restart Claude Code to activate"
