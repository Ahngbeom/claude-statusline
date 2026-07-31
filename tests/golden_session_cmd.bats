#!/usr/bin/env bats
# End-to-end rendering of the Line 1 session-invocation segment.
#
# argv is injected via STATUSLINE_SESSION_CMD rather than by faking the
# process tree: statusline.sh reads /proc on Linux and falls back to `ps`
# elsewhere, so a PATH-shimmed `ps` would be silently bypassed on CI. The
# override feeds the exact same _format_session_cmd whitelist the auto-detect
# path feeds, so these tests cover the real rendering contract.

load test_helper

JSON='{"workspace":{"current_dir":"/tmp/test"},"model":{"display_name":"Opus 5"},"session_id":"s","version":"2.1.220","output_style":{"name":"explanatory"}}'

@test "golden: session cmd segment renders after the output style" {
  run run_statusline "$JSON" STATUSLINE_SHOW_SESSION_CMD=1 \
    STATUSLINE_SESSION_CMD='claude -c --permission-mode plan'
  [ "$status" -eq 0 ]
  line1="$(head -1 <<<"$output")"
  [[ "$line1" == *"explanatory  ⌘ -c plan"* ]]
}

@test "golden: the segment sits before the Mem indicator, not after it" {
  run run_statusline "$JSON" STATUSLINE_SHOW_SESSION_CMD=1 STATUSLINE_SHOW_MEM=1 \
    STATUSLINE_SESSION_CMD='claude -c'
  [ "$status" -eq 0 ]
  line1="$(head -1 <<<"$output")"
  if [[ "$line1" == *Mem* ]]; then
    [[ "${line1%%Mem*}" == *"⌘ -c"* ]]
  fi
}

@test "golden: STATUSLINE_SHOW_SESSION_CMD=0 hides the segment" {
  # Compared against the no-argv baseline rather than grepping for flag names:
  # the output style "explanatory" literally contains "plan", so a substring
  # assertion on the mode name would be a false positive.
  run run_statusline "$JSON" STATUSLINE_SHOW_SESSION_CMD=0 \
    STATUSLINE_SESSION_CMD='claude -c --permission-mode plan'
  [ "$status" -eq 0 ]
  [[ "$output" != *"⌘"* ]]
  hidden="$(head -1 <<<"$output")"

  run run_statusline "$JSON" STATUSLINE_SHOW_SESSION_CMD=0
  [ "$status" -eq 0 ]
  baseline="$(head -1 <<<"$output")"

  [ "$(normalize_mem "$hidden")" = "$(normalize_mem "$baseline")" ]
}

@test "golden: compact mode omits the segment" {
  run run_statusline "$JSON" STATUSLINE_SHOW_SESSION_CMD=1 STATUSLINE_COMPACT=1 \
    STATUSLINE_SESSION_CMD='claude -c --permission-mode plan'
  [ "$status" -eq 0 ]
  [[ "$output" != *"⌘"* ]]
}

@test "golden: argv with no whitelisted flag leaves Line 1 untouched" {
  run run_statusline "$JSON" STATUSLINE_SHOW_SESSION_CMD=1 STATUSLINE_SESSION_CMD='claude'
  [ "$status" -eq 0 ]
  with_cmd="$(head -1 <<<"$output")"

  run run_statusline "$JSON" STATUSLINE_SHOW_SESSION_CMD=0
  [ "$status" -eq 0 ]
  without_cmd="$(head -1 <<<"$output")"

  [ "$(normalize_mem "$with_cmd")" = "$(normalize_mem "$without_cmd")" ]
}

@test "golden: STATUSLINE_ICON_SESSION_CMD overrides the prefix glyph" {
  run run_statusline "$JSON" STATUSLINE_SHOW_SESSION_CMD=1 \
    STATUSLINE_ICON_SESSION_CMD='%' STATUSLINE_SESSION_CMD='claude -c'
  [ "$status" -eq 0 ]
  [[ "$output" == *"% -c"* ]]
  [[ "$output" != *"⌘"* ]]
}

@test "golden: a secret-bearing argv never reaches the rendered output" {
  run run_statusline "$JSON" STATUSLINE_SHOW_SESSION_CMD=1 \
    STATUSLINE_SESSION_CMD='claude --permission-mode plan --append-system-prompt hunter2 --mcp-config /tmp/tok3n.json'
  [ "$status" -eq 0 ]
  [[ "$output" == *"⌘ plan +sysprompt +mcp"* ]]
  [[ "$output" != *hunter2* ]]
  [[ "$output" != *tok3n* ]]
}

@test "golden: STATUSLINE_COLOR_SESSION_CMD applies a 256-color escape" {
  run run_statusline_colored "$JSON" STATUSLINE_SHOW_SESSION_CMD=1 \
    STATUSLINE_COLOR_SESSION_CMD=196 STATUSLINE_SESSION_CMD='claude -c'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;196m⌘ -c'* ]]
}

@test "golden: the segment is configurable from the config file too" {
  # `-u STATUSLINE_SHOW_SESSION_CMD` is passed through to the helper's `env`
  # call to drop the suite-wide default (see test_helper.bash), so the config
  # file -- not an env var -- is what turns the segment on here.
  run run_statusline_with_config "$JSON" \
    "STATUSLINE_SHOW_SESSION_CMD=1
STATUSLINE_SESSION_CMD=claude --permission-mode plan" \
    -u STATUSLINE_SHOW_SESSION_CMD
  [ "$status" -eq 0 ]
  [[ "$output" == *"⌘ plan"* ]]
}
