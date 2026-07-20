#!/usr/bin/env bats
#
# End-to-end tests for the STATUSLINE_SHOW_* per-line display toggles (see
# CLAUDE.md's "사용자 설정 파일" section and README "Per-line Display
# Toggles"). Mirrors golden_output.bats/golden_compact_mode.bats
# conventions: isolated HOME, NO_COLOR=1 so assertions don't need to match
# ANSI codes. Session/Cache/Speed/Today/Week/Month toggles need a seeded
# ccusage cache (run_statusline_with_cache) to have anything to hide in the
# first place; Git/Mem/CC version/Output style toggles don't.

load 'test_helper'

JSON='{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","version":"1.2.3","output_style":{"name":"concise"},"context_window":{"total_input_tokens":45000,"context_window_size":200000},"cost":{"total_cost_usd":0.42}}'

# Builds a throwaway repo on branch "feature-x", matching golden_git_status.bats's
# convention of testing against real git plumbing rather than a mock.
setup_git_repo() {
  local base="$1"
  git init --quiet -b feature-x "$base/work"
  git -C "$base/work" config user.email "test@example.com"
  git -C "$base/work" config user.name "Test"
  echo "one" >"$base/work/file.txt"
  git -C "$base/work" add file.txt
  git -C "$base/work" commit --quiet -m "initial"
}

@test "golden: default (no SHOW_* set) renders cc_version, output_style, and all of Line 3" {
  run run_statusline_with_cache "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"v1.2.3"* ]]
  [[ "$line1" == *"concise"* ]]
  line3="$(sed -n '3p' <<<"$output")"
  [[ "$line3" == *"Today"* ]]
  [[ "$line3" == *"Week"* ]]
  [[ "$line3" == *"Month"* ]]
}

@test "golden: STATUSLINE_SHOW_CC_VERSION=0 hides the CLI version but keeps output style" {
  run run_statusline_with_cache "$JSON" STATUSLINE_SHOW_CC_VERSION=0
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" != *"v1.2.3"* ]]
  [[ "$line1" == *"concise"* ]]
}

@test "golden: STATUSLINE_SHOW_OUTPUT_STYLE=0 hides the output style but keeps the CLI version" {
  run run_statusline_with_cache "$JSON" STATUSLINE_SHOW_OUTPUT_STYLE=0
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"v1.2.3"* ]]
  [[ "$line1" != *"concise"* ]]
}

@test "golden: STATUSLINE_SHOW_MEM=0 hides the Mem indicator" {
  run run_statusline "$JSON" STATUSLINE_SHOW_MEM=0
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" != *"Mem"* ]]
}

@test "golden: default (no SHOW_MEM set) still renders Mem in the full layout" {
  run run_statusline "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"Mem"* ]]
}

@test "golden: STATUSLINE_SHOW_GIT=0 hides the whole git segment" {
  base="$(mktemp -d)"
  setup_git_repo "$base"

  run run_statusline_in "$base/work" "$JSON" STATUSLINE_SHOW_GIT=0
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" != *"feature-x"* ]]

  rm -rf "$base"
}

@test "golden: default (no SHOW_GIT set) renders the branch name" {
  base="$(mktemp -d)"
  setup_git_repo "$base"

  run run_statusline_in "$base/work" "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"feature-x"* ]]

  rm -rf "$base"
}

@test "golden: STATUSLINE_SHOW_GIT_STATUS=0 keeps the branch name but hides the dirty marker" {
  base="$(mktemp -d)"
  setup_git_repo "$base"
  echo "uncommitted change" >>"$base/work/file.txt"

  run run_statusline_in "$base/work" "$JSON" STATUSLINE_SHOW_GIT_STATUS=0
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"feature-x"* ]]
  [[ "$line1" != *"feature-x*"* ]]

  rm -rf "$base"
}

@test "golden: default (no SHOW_GIT_STATUS set) still shows the dirty marker" {
  base="$(mktemp -d)"
  setup_git_repo "$base"
  echo "uncommitted change" >>"$base/work/file.txt"

  run run_statusline_in "$base/work" "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"feature-x*"* ]]

  rm -rf "$base"
}

@test "golden: STATUSLINE_SHOW_SESSION=0 removes the Session segment from Line 2" {
  run run_statusline_with_cache "$JSON" STATUSLINE_SHOW_SESSION=0
  [ "$status" -eq 0 ]
  line2="$(sed -n '2p' <<<"$output")"
  [[ "$line2" != *"Session"* ]]
}

@test "golden: STATUSLINE_SHOW_CACHE=0 hides cache hit rate but keeps speed" {
  run run_statusline_with_cache "$JSON" STATUSLINE_SHOW_CACHE=0
  [ "$status" -eq 0 ]
  line2="$(sed -n '2p' <<<"$output")"
  [[ "$line2" != *"🗄"* ]]
  [[ "$line2" == *"/m"* ]]
}

@test "golden: STATUSLINE_SHOW_SPEED=0 hides speed but keeps cache hit rate" {
  run run_statusline_with_cache "$JSON" STATUSLINE_SHOW_SPEED=0
  [ "$status" -eq 0 ]
  line2="$(sed -n '2p' <<<"$output")"
  [[ "$line2" == *"🗄"* ]]
  [[ "$line2" != *"/m"* ]]
}

@test "golden: STATUSLINE_SHOW_TODAY=0 removes Today but keeps Week/Month" {
  run run_statusline_with_cache "$JSON" STATUSLINE_SHOW_TODAY=0
  [ "$status" -eq 0 ]
  line3="$(sed -n '3p' <<<"$output")"
  [[ "$line3" != *"Today"* ]]
  [[ "$line3" == *"Week"* ]]
  [[ "$line3" == *"Month"* ]]
}

@test "golden: STATUSLINE_SHOW_WEEK=0 removes Week but keeps Today/Month" {
  run run_statusline_with_cache "$JSON" STATUSLINE_SHOW_WEEK=0
  [ "$status" -eq 0 ]
  line3="$(sed -n '3p' <<<"$output")"
  [[ "$line3" == *"Today"* ]]
  [[ "$line3" != *"Week"* ]]
  [[ "$line3" == *"Month"* ]]
}

@test "golden: STATUSLINE_SHOW_MONTH=0 removes Month but keeps Today/Week" {
  run run_statusline_with_cache "$JSON" STATUSLINE_SHOW_MONTH=0
  [ "$status" -eq 0 ]
  line3="$(sed -n '3p' <<<"$output")"
  [[ "$line3" == *"Today"* ]]
  [[ "$line3" == *"Week"* ]]
  [[ "$line3" != *"Month"* ]]
}

@test "golden: STATUSLINE_SHOW_TODAY=0 in compact mode hides Today too" {
  run run_statusline_with_cache "$JSON" COLUMNS=40 STATUSLINE_SHOW_TODAY=0
  [ "$status" -eq 0 ]
  line3="$(sed -n '3p' <<<"$output")"
  [[ "$line3" != *"Today"* ]]
}

@test "golden: STATUSLINE_SHOW_SESSION=0 in compact mode hides Sess too" {
  run run_statusline_with_cache "$JSON" COLUMNS=40 STATUSLINE_SHOW_SESSION=0
  [ "$status" -eq 0 ]
  line3="$(sed -n '3p' <<<"$output")"
  [[ "$line3" != *"Sess"* ]]
}

@test "golden: STATUSLINE_HIDE_COST=1 still hides all of Line 3 regardless of SHOW_* toggles" {
  run run_statusline_with_cache "$JSON" STATUSLINE_HIDE_COST=1 STATUSLINE_SHOW_TODAY=1 STATUSLINE_SHOW_WEEK=1 STATUSLINE_SHOW_MONTH=1
  [ "$status" -eq 0 ]
  [[ "$output" != *"Today"* ]]
  [[ "$output" != *"Week"* ]]
  [[ "$output" != *"Month"* ]]
}
