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
