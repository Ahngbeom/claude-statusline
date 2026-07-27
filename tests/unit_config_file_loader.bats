#!/usr/bin/env bats
#
# Tests for statusline.sh's "user config file" loader (see the "# ---- user
# config file" section and CLAUDE.md's "사용자 설정 파일" section): reads
# ~/.claude/statusline.conf (KEY=VALUE), only assigns allowlisted keys, and
# always lets an already-set env var win over the config file value.

load 'test_helper'

JSON='{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"}}'
JSON_WITH_VERSION='{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"},"version":"1.2.3"}'

@test "config file: a recognized key is applied when no env var is set" {
  run run_statusline_with_config "$JSON" "STATUSLINE_SHOW_MEM=0"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" != *"Mem"* ]]
}

@test "config file: an already-set env var wins over the config file value" {
  run run_statusline_with_config "$JSON" "STATUSLINE_SHOW_MEM=0" STATUSLINE_SHOW_MEM=1
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"Mem"* ]]
}

@test "config file: comment lines and blank lines are ignored, real keys still apply" {
  local config
  config="$(printf '# a comment\n\nSTATUSLINE_SHOW_CC_VERSION=0\n')"
  run run_statusline_with_config "$JSON_WITH_VERSION" "$config"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" != *"v1.2.3"* ]]
}

@test "config file: an unknown key is silently ignored (not exported, no crash)" {
  run run_statusline_with_config "$JSON" "SOME_RANDOM_KEY=danger"
  [ "$status" -eq 0 ]
  [[ "$output" != *"danger"* ]]
}

@test "config file: multiple recognized keys are all applied" {
  local config
  config="$(printf 'STATUSLINE_SHOW_MEM=0\nSTATUSLINE_COMPACT_WIDTH=200\n')"
  run run_statusline_with_config "$JSON" "$config" COLUMNS=100
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" != *"Mem"* ]]
  # STATUSLINE_COMPACT_WIDTH=200 > COLUMNS=100 -> compact layout triggers
  [ "$line1" = "📂 myapp  │ Opus 4.6" ]
}

@test "config file: absent file falls back to full defaults (no crash)" {
  run run_statusline "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"Mem"* ]]
}

@test "config file: a STATUSLINE_COLOR_* key is applied via the prefix-glob allowlist arm" {
  run run_statusline_colored_with_config "$JSON" "STATUSLINE_COLOR_DIR=196"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;196m'* ]]
}

@test "config file: a STATUSLINE_ICON_* key is applied via the prefix-glob allowlist arm" {
  run run_statusline_with_config "$JSON" "STATUSLINE_ICON_DIR=🚀"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == 🚀* ]]
}

@test "config file: STATUSLINE_SEP_CHAR is applied via the allowlist" {
  run run_statusline_with_config "$JSON" "STATUSLINE_SEP_CHAR=::"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::"* ]]
}
