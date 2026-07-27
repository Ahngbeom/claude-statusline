#!/usr/bin/env bats
#
# Tests for per-element STATUSLINE_COLOR_*/STATUSLINE_THRESHOLD_* overrides
# (see "# ---- pre-computed color variables" in statusline.sh). These assert
# on actual ANSI escape codes, so they use run_statusline_colored (does NOT
# force NO_COLOR=1) instead of the usual run_statusline helper.

load 'test_helper'

JSON='{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"}}'
JSON_WITH_CTX='{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"},"context_window":{"total_input_tokens":45000,"context_window_size":200000}}'

@test "color: STATUSLINE_COLOR_DIR overrides the directory segment's 256-color code" {
  run run_statusline_colored "$JSON" STATUSLINE_COLOR_DIR=196
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;196m'* ]]
  [[ "$output" != *$'\033[38;5;117m'* ]]
}

@test "color: an out-of-range STATUSLINE_COLOR_DIR silently falls back to the default 117" {
  run run_statusline_colored "$JSON" STATUSLINE_COLOR_DIR=999
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;117m'* ]]
}

@test "color: a non-numeric STATUSLINE_COLOR_MODEL silently falls back to the default 147" {
  run run_statusline_colored "$JSON" STATUSLINE_COLOR_MODEL=purple
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;147m'* ]]
}

@test "color: NO_COLOR=1 disables color output even with a STATUSLINE_COLOR_* override set" {
  run run_statusline "$JSON" STATUSLINE_COLOR_DIR=196
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033[38;5;196m'* ]]
  [[ "$output" != *$'\033['* ]]
}

@test "threshold: STATUSLINE_THRESHOLD_CTX_WARN widened to 90 turns a 78%-remaining context bar warn-colored" {
  run run_statusline_colored "$JSON_WITH_CTX" STATUSLINE_THRESHOLD_CTX_WARN=90
  [ "$status" -eq 0 ]
  # default context_used=45000/200000 -> remaining 78%; with warn threshold
  # raised to 90, 78 <= 90 now selects the warn tier (default color 215)
  # instead of the default ok tier (default color 158).
  [[ "$output" == *$'\033[38;5;215m'* ]]
}

@test "threshold: default STATUSLINE_THRESHOLD_CTX_WARN (40) leaves a 78%-remaining context bar ok-colored" {
  run run_statusline_colored "$JSON_WITH_CTX"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;158m'* ]]
}

@test "threshold: STATUSLINE_THRESHOLD_MEM_CRIT=0 forces the Mem indicator into the crit color regardless of actual system memory usage" {
  run run_statusline_colored "$JSON" STATUSLINE_THRESHOLD_MEM_CRIT=0 STATUSLINE_THRESHOLD_MEM_WARN=0
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;196m'* ]]
}

@test "threshold: STATUSLINE_THRESHOLD_MEM_WARN=101 keeps the Mem indicator ok-colored regardless of actual system memory usage" {
  run run_statusline_colored "$JSON" STATUSLINE_THRESHOLD_MEM_WARN=101 STATUSLINE_THRESHOLD_MEM_CRIT=101
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;120m'* ]]
  [[ "$output" != *$'\033[38;5;196m'* ]]
  [[ "$output" != *$'\033[38;5;220m'* ]]
}

@test "threshold: STATUSLINE_THRESHOLD_SESSION_WARN widened to 80 turns a 75%-remaining session warn-colored" {
  run run_statusline_colored_with_cache "$JSON" STATUSLINE_THRESHOLD_SESSION_WARN=80
  [ "$status" -eq 0 ]
  # seed_ccusage_cache's fixed block (1h elapsed of a 4h window) leaves 75%
  # remaining; with warn raised to 80, 75 <= 80 selects the warn tier
  # (default color 228) instead of the default ok tier (default color 194).
  [[ "$output" == *$'\033[38;5;228m'* ]]
}

@test "threshold: default STATUSLINE_THRESHOLD_SESSION_WARN (25) leaves a 75%-remaining session ok-colored" {
  run run_statusline_colored_with_cache "$JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;194m'* ]]
}

@test "color: STATUSLINE_COLOR_CTX_CRIT overrides the crit-tier context bar color" {
  run run_statusline_colored "$JSON_WITH_CTX" STATUSLINE_THRESHOLD_CTX_WARN=90 STATUSLINE_THRESHOLD_CTX_CRIT=90 STATUSLINE_COLOR_CTX_CRIT=201
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;201m'* ]]
}
