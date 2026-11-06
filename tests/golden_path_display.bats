#!/usr/bin/env bats
#
# End-to-end tests for the Line 1 directory segment: long-path abbreviation
# (STATUSLINE_PATH_MAX), the project_dir anchor, the anchored ~ substitution,
# and the opt-in OSC 8 file:// link (STATUSLINE_PATH_LINK).

load 'test_helper'

LONG_JSON='{"workspace":{"current_dir":"/srv/work/mobidoc/mobidoc-server/src/main/java/us/api","project_dir":"/srv/work/mobidoc/mobidoc-server"},"model":{"display_name":"Opus 4.6"}}'

setup() {
  TEST_HOME="$(mktemp -d)"
}

teardown() {
  # A detached ccusage refresh (npx exists on CI) may still be writing here.
  rm -rf "$TEST_HOME" 2>/dev/null || true
}

# Runs statusline.sh with HOME=$TEST_HOME so a test can build stdin paths
# under (or next to) the same HOME the script sees.
run_with_home() {
  local json="$1"; shift
  ( cd "$TEST_HOME" && printf '%s' "$json" | HOME="$TEST_HOME" NO_COLOR=1 STATUSLINE_SHOW_SESSION_CMD=0 STATUSLINE_SHOW_MEM=0 HOSTNAME=testhost env "$@" bash "$STATUSLINE_SH" )
}

line1_of() { sed -n '1p' <<<"$1"; }

@test "golden: a short path renders unchanged" {
  run run_statusline '{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"}}' STATUSLINE_SHOW_MEM=0
  [ "$status" -eq 0 ]
  [ "$(line1_of "$output")" = "📂 /tmp/proj/myapp  │ Opus 4.6" ]
}

@test "golden: a long path is abbreviated to the default 32 chars, keeping project_dir whole" {
  run run_statusline "$LONG_JSON" STATUSLINE_SHOW_MEM=0
  [ "$status" -eq 0 ]
  [ "$(line1_of "$output")" = "📂 …/mobidoc-server/s/m/j/u/api  │ Opus 4.6" ]
}

@test "golden: STATUSLINE_PATH_MAX=0 disables abbreviation" {
  run run_statusline "$LONG_JSON" STATUSLINE_PATH_MAX=0
  [ "$status" -eq 0 ]
  [[ "$(line1_of "$output")" == "📂 /srv/work/mobidoc/mobidoc-server/src/main/java/us/api  │"* ]]
}

@test "golden: STATUSLINE_PATH_MAX is read from statusline.conf" {
  run run_statusline_with_config "$LONG_JSON" "STATUSLINE_PATH_MAX=0"
  [ "$status" -eq 0 ]
  [[ "$(line1_of "$output")" == *"/srv/work/mobidoc/mobidoc-server/src/main/java/us/api"* ]]
}

@test "golden: compact mode still shows the basename only" {
  run run_statusline "$LONG_JSON" STATUSLINE_COMPACT=1
  [ "$status" -eq 0 ]
  [ "$(line1_of "$output")" = "📂 api  │ Opus 4.6" ]
}

@test "golden: \$HOME is shown as ~" {
  run run_with_home '{"workspace":{"current_dir":"'"$TEST_HOME"'/proj"},"model":{"display_name":"Opus 4.6"}}'
  [ "$status" -eq 0 ]
  [ "$(line1_of "$output")" = "📂 ~/proj  │ Opus 4.6" ]
}

@test "regression: a sibling dir sharing the \$HOME prefix is not turned into ~" {
  run run_with_home '{"workspace":{"current_dir":"'"$TEST_HOME"'x/proj"},"model":{"display_name":"Opus 4.6"}}' STATUSLINE_PATH_MAX=0
  [ "$status" -eq 0 ]
  [ "$(line1_of "$output")" = "📂 ${TEST_HOME}x/proj  │ Opus 4.6" ]
}

@test "regression: JSONL fallback finds the session file for a dir name containing ~" {
  local dir="$TEST_HOME/my~dir" encoded
  encoded="${dir//\//-}"; encoded="${encoded#-}"
  mkdir -p "$TEST_HOME/.claude/projects/-$encoded"
  cp "$FIXTURES_DIR/session_cache_creation.jsonl" "$TEST_HOME/.claude/projects/-$encoded/sess-1.jsonl"
  run run_with_home '{"workspace":{"current_dir":"'"$dir"'"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1"}'
  [ "$status" -eq 0 ]
  [[ "$(sed -n '2p' <<<"$output")" != *"Context ···"* ]]
}

@test "golden: STATUSLINE_PATH_LINK unset emits no OSC 8 sequence" {
  run run_with_home '{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033]8;'* ]]
}

@test "golden: STATUSLINE_PATH_LINK=1 wraps the dir in an OSC 8 file:// link" {
  run run_with_home '{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"}}' STATUSLINE_PATH_LINK=1
  [ "$status" -eq 0 ]
  [ "$(line1_of "$output")" = "📂 "$'\033]8;;file://testhost/tmp/proj/myapp\a'"/tmp/proj/myapp"$'\033]8;;\a'"  │ Opus 4.6" ]
}

@test "golden: the link targets the full raw path even when the text is abbreviated" {
  run run_with_home "$LONG_JSON" STATUSLINE_PATH_LINK=1
  [ "$status" -eq 0 ]
  [[ "$(line1_of "$output")" == *$'\033]8;;file://testhost/srv/work/mobidoc/mobidoc-server/src/main/java/us/api\a'"…/mobidoc-server/s/m/j/u/api"$'\033]8;;\a'* ]]
}

@test "golden: the link targets the real path, not the ~ form" {
  run run_with_home '{"workspace":{"current_dir":"'"$TEST_HOME"'/proj"},"model":{"display_name":"Opus 4.6"}}' STATUSLINE_PATH_LINK=1
  [ "$status" -eq 0 ]
  [[ "$(line1_of "$output")" == *"file://testhost${TEST_HOME}/proj"$'\a'"~/proj"* ]]
}

@test "golden: compact mode links the basename too" {
  run run_with_home "$LONG_JSON" STATUSLINE_PATH_LINK=1 STATUSLINE_COMPACT=1
  [ "$status" -eq 0 ]
  [ "$(line1_of "$output")" = "📂 "$'\033]8;;file://testhost/srv/work/mobidoc/mobidoc-server/src/main/java/us/api\a'"api"$'\033]8;;\a'"  │ Opus 4.6" ]
}

@test "golden: no link is emitted for a non-absolute dir (e.g. missing workspace)" {
  run run_with_home '{"model":{"display_name":"Opus 4.6"}}' STATUSLINE_PATH_LINK=1
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033]8;'* ]]
}
