#!/usr/bin/env bats
#
# Tests for configure.sh's non-interactive CLI subcommands (list/get/set/
# unset/reset/path). Each test gets a fresh STATUSLINE_CONFIG_FILE path
# (not pre-created -- configure.sh creates it atomically on first write),
# isolated from the developer's real ~/.claude/statusline.conf.

load 'test_helper'

setup() {
  CFG_TMPDIR="$(mktemp -d)"
  export STATUSLINE_CONFIG_FILE="$CFG_TMPDIR/statusline.conf"
}

teardown() {
  rm -rf "$CFG_TMPDIR"
}

configure_sh() {
  bash "$CONFIGURE_SH" "$@"
}

@test "configure: get on an unset key returns its default" {
  run configure_sh get STATUSLINE_SHOW_MEM
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "configure: get on an unknown key fails" {
  run configure_sh get NOT_A_REAL_KEY
  [ "$status" -ne 0 ]
}

@test "configure: set on an unknown key fails without touching the config file" {
  run configure_sh set NOT_A_REAL_KEY 1
  [ "$status" -ne 0 ]
  [ ! -f "$STATUSLINE_CONFIG_FILE" ]
}

@test "configure: set on a bool key persists and get reflects it" {
  run configure_sh set STATUSLINE_SHOW_WEEK 0
  [ "$status" -eq 0 ]
  run configure_sh get STATUSLINE_SHOW_WEEK
  [ "$output" = "0" ]
  grep -q '^STATUSLINE_SHOW_WEEK=0$' "$STATUSLINE_CONFIG_FILE"
}

@test "configure: the session-cmd keys round-trip through set/get/unset" {
  run configure_sh set STATUSLINE_SHOW_SESSION_CMD 0
  [ "$status" -eq 0 ]
  # `text` type: a value with spaces has to persist verbatim on one line, so
  # statusline.sh's IFS='=' read reconstructs the whole command string.
  run configure_sh set STATUSLINE_SESSION_CMD 'claude -c --permission-mode plan'
  [ "$status" -eq 0 ]
  grep -q '^STATUSLINE_SESSION_CMD=claude -c --permission-mode plan$' "$STATUSLINE_CONFIG_FILE"
  run configure_sh get STATUSLINE_SESSION_CMD
  [ "$output" = "claude -c --permission-mode plan" ]

  run configure_sh unset STATUSLINE_SESSION_CMD
  [ "$status" -eq 0 ]
  run configure_sh get STATUSLINE_SHOW_SESSION_CMD
  [ "$output" = "0" ]
}

@test "configure: every color/icon key has a real default, not the catch-all 1" {
  # _key_default() ends in `*) echo 1`, which is right for the bool SHOW_*
  # switches but silently swallows a newly added color/icon key -- that
  # regression shipped once and was only caught by eyeballing `list` output.
  # Keys are classified off their own description text so this stays correct
  # as keys are added.
  run configure_sh list
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    case "$line" in
      KEY*|'') continue ;;
    esac
    local key value desc
    key="${line%% *}"
    value="$(awk '{print $2}' <<<"$line")"
    desc="${line#*default  }"
    case "$desc" in
      "256-color code:"*)
        [[ "$value" =~ ^[0-9]+$ ]] || { echo "$key default '$value' is not numeric"; return 1; }
        [ "$value" -ge 0 ] && [ "$value" -le 255 ] \
          || { echo "$key default '$value' out of 0-255"; return 1; }
        # 1 is a legal color code but no element actually defaults to it, so it
        # is the fingerprint of the catch-all leaking through.
        [ "$value" != "1" ] || { echo "$key default looks like the catch-all"; return 1; }
        ;;
      "Icon:"*)
        [ "$value" != "1" ] && [ "$value" != "0" ] \
          || { echo "$key icon default looks like the catch-all"; return 1; }
        ;;
    esac
  done <<<"$output"
}

@test "configure: the new session-cmd keys report their documented defaults" {
  run configure_sh get STATUSLINE_SHOW_SESSION_CMD
  [ "$output" = "1" ]
  run configure_sh get STATUSLINE_COLOR_SESSION_CMD
  [ "$output" = "245" ]
  run configure_sh get STATUSLINE_ICON_SESSION_CMD
  [ "$output" = "⌘" ]
  run configure_sh get STATUSLINE_SESSION_CMD
  [ "$output" = "(auto-detected)" ]
}

@test "configure: list includes every new session-cmd key" {
  run configure_sh list
  [ "$status" -eq 0 ]
  for key in STATUSLINE_SHOW_SESSION_CMD STATUSLINE_SESSION_CMD \
             STATUSLINE_COLOR_SESSION_CMD STATUSLINE_ICON_SESSION_CMD; do
    [[ "$output" == *"$key"* ]]
  done
}

@test "configure: set on a bool key rejects an invalid value" {
  run configure_sh set STATUSLINE_SHOW_WEEK maybe
  [ "$status" -ne 0 ]
}

@test "configure: set on a numeric key rejects a non-numeric value" {
  run configure_sh set STATUSLINE_COMPACT_WIDTH wide
  [ "$status" -ne 0 ]
}

@test "configure: set on a numeric key persists" {
  run configure_sh set STATUSLINE_COMPACT_WIDTH 100
  [ "$status" -eq 0 ]
  run configure_sh get STATUSLINE_COMPACT_WIDTH
  [ "$output" = "100" ]
}

@test "configure: presence key 'on' writes an explicit 1 line" {
  run configure_sh set NO_COLOR 1
  [ "$status" -eq 0 ]
  grep -q '^NO_COLOR=1$' "$STATUSLINE_CONFIG_FILE"
}

@test "configure: presence key 'off' deletes the line rather than writing 0" {
  run configure_sh set NO_COLOR 1
  run configure_sh set NO_COLOR 0
  [ "$status" -eq 0 ]
  ! grep -q '^NO_COLOR=' "$STATUSLINE_CONFIG_FILE"
}

@test "configure: tristate key accepts 'auto' and deletes the line" {
  run configure_sh set STATUSLINE_COMPACT 1
  run configure_sh set STATUSLINE_COMPACT auto
  [ "$status" -eq 0 ]
  ! grep -q '^STATUSLINE_COMPACT=' "$STATUSLINE_CONFIG_FILE"
  run configure_sh get STATUSLINE_COMPACT
  [ "$output" = "auto" ]
}

@test "configure: an env var override is reflected as the effective value and source" {
  configure_sh set STATUSLINE_SHOW_WEEK 0

  run env STATUSLINE_SHOW_WEEK=1 bash "$CONFIGURE_SH" get STATUSLINE_SHOW_WEEK
  [ "$output" = "1" ]

  run env STATUSLINE_SHOW_WEEK=1 bash "$CONFIGURE_SH" list
  [[ "$output" == *"STATUSLINE_SHOW_WEEK"*"1"*"env"* ]]
}

@test "configure: unset reverts a key to its default" {
  run configure_sh set STATUSLINE_SHOW_WEEK 0
  run configure_sh unset STATUSLINE_SHOW_WEEK
  [ "$status" -eq 0 ]
  run configure_sh get STATUSLINE_SHOW_WEEK
  [ "$output" = "1" ]
}

@test "configure: list shows every recognized key with a source" {
  run configure_sh list
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUSLINE_SHOW_GIT"* ]]
  [[ "$output" == *"STATUSLINE_SHOW_MONTH"* ]]
  [[ "$output" == *"default"* ]]
}

@test "configure: path prints the resolved config file path" {
  run configure_sh path
  [ "$status" -eq 0 ]
  [ "$output" = "$STATUSLINE_CONFIG_FILE" ]
}

@test "configure: reset -y removes the whole config file" {
  run configure_sh set STATUSLINE_SHOW_WEEK 0
  [ -f "$STATUSLINE_CONFIG_FILE" ]
  run configure_sh reset -y
  [ "$status" -eq 0 ]
  [ ! -f "$STATUSLINE_CONFIG_FILE" ]
}

@test "configure: set requires a value" {
  run configure_sh set STATUSLINE_SHOW_WEEK
  [ "$status" -ne 0 ]
}

@test "configure: an unknown subcommand exits non-zero" {
  run configure_sh bogus-subcommand
  [ "$status" -ne 0 ]
}

@test "configure: set on a color256 key persists an in-range value" {
  run configure_sh set STATUSLINE_COLOR_DIR 196
  [ "$status" -eq 0 ]
  run configure_sh get STATUSLINE_COLOR_DIR
  [ "$output" = "196" ]
}

@test "configure: set on a color256 key rejects a value above 255" {
  run configure_sh set STATUSLINE_COLOR_DIR 256
  [ "$status" -ne 0 ]
}

@test "configure: set on a color256 key rejects a non-numeric value" {
  run configure_sh set STATUSLINE_COLOR_DIR purple
  [ "$status" -ne 0 ]
}

@test "configure: set on a percent key persists an in-range value" {
  run configure_sh set STATUSLINE_THRESHOLD_MEM_WARN 50
  [ "$status" -eq 0 ]
  run configure_sh get STATUSLINE_THRESHOLD_MEM_WARN
  [ "$output" = "50" ]
}

@test "configure: set on a percent key rejects a value above 100" {
  run configure_sh set STATUSLINE_THRESHOLD_MEM_WARN 101
  [ "$status" -ne 0 ]
}

@test "configure: set on a text key accepts and persists an emoji value" {
  run configure_sh set STATUSLINE_ICON_DIR 🚀
  [ "$status" -eq 0 ]
  run configure_sh get STATUSLINE_ICON_DIR
  [ "$output" = "🚀" ]
}

@test "configure: set on a text key accepts a multi-character separator string" {
  run configure_sh set STATUSLINE_SEP_CHAR "::"
  [ "$status" -eq 0 ]
  run configure_sh get STATUSLINE_SEP_CHAR
  [ "$output" = "::" ]
}

@test "configure: the 'default' keyword resets a color256 key instead of being validated as a value" {
  configure_sh set STATUSLINE_COLOR_DIR 196
  run configure_sh set STATUSLINE_COLOR_DIR default
  [ "$status" -eq 0 ]
  ! grep -q '^STATUSLINE_COLOR_DIR=' "$STATUSLINE_CONFIG_FILE"
  run configure_sh get STATUSLINE_COLOR_DIR
  [ "$output" = "117" ]
}

@test "configure: the 'reset' keyword resets a text key" {
  configure_sh set STATUSLINE_ICON_DIR 🚀
  run configure_sh set STATUSLINE_ICON_DIR reset
  [ "$status" -eq 0 ]
  run configure_sh get STATUSLINE_ICON_DIR
  [ "$output" = "📂" ]
}

@test "configure: list shows the new color/icon/threshold keys" {
  run configure_sh list
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUSLINE_COLOR_DIR"* ]]
  [[ "$output" == *"STATUSLINE_ICON_MEM"* ]]
  [[ "$output" == *"STATUSLINE_THRESHOLD_SESSION_CRIT"* ]]
  [[ "$output" == *"STATUSLINE_SEP_CHAR"* ]]
}
