#!/usr/bin/env bats
#
# End-to-end rendering of the effort / thinking / fast-mode label that
# follows the model name on Line 1 (stdin effort.level, thinking.enabled,
# fast_mode).

load test_helper

json_with() {
  printf '{"workspace":{"current_dir":"/tmp/test"},"model":{"display_name":"%s"},"session_id":"s","version":"2.1.300","output_style":{"name":"default"}%s}' "$1" "$2"
}

ALL_ON="$(json_with 'Opus 5.5' ',"effort":{"level":"high"},"thinking":{"enabled":true},"fast_mode":true')"

@test "golden: effort, thinking and fast render in parentheses after the model" {
  run run_statusline "$ALL_ON"
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Opus 5.5 (high, thinking, fast)  v2.1.300"* ]]
}

@test "golden: effort alone renders as (level)" {
  run run_statusline "$(json_with 'Opus 5.5' ',"effort":{"level":"xhigh"},"thinking":{"enabled":false},"fast_mode":false')"
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Opus 5.5 (xhigh)  v2.1.300"* ]]
}

@test "golden: a model without effort support still shows thinking" {
  run run_statusline "$(json_with 'Haiku 4.5' ',"thinking":{"enabled":true}')"
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Haiku 4.5 (thinking)  v2.1.300"* ]]
}

@test "golden: no effort and thinking/fast off leaves the bare model name" {
  run run_statusline "$(json_with 'Opus 5.5' ',"thinking":{"enabled":false},"fast_mode":false')"
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Opus 5.5  v2.1.300"* ]]
}

@test "golden: compact layout keeps only the effort level" {
  run run_statusline "$ALL_ON" STATUSLINE_COMPACT=1
  [ "$status" -eq 0 ]
  line1="$(head -1 <<<"$output")"
  [[ "$line1" == *"Opus 5.5 (high)"* ]]
  [[ "$line1" != *"thinking"* ]]
  [[ "$line1" != *"fast"* ]]
}

@test "golden: STATUSLINE_SHOW_EFFORT=0 hides the whole label" {
  run run_statusline "$ALL_ON" STATUSLINE_SHOW_EFFORT=0
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Opus 5.5  v2.1.300"* ]]
}

@test "golden: STATUSLINE_SHOW_EFFORT=0 from the config file is honored" {
  run run_statusline_with_config "$ALL_ON" "STATUSLINE_SHOW_EFFORT=0"
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Opus 5.5  v2.1.300"* ]]
}

@test "golden: the live level replaces the launch-time effort:<v> in the session cmd" {
  run run_statusline "$ALL_ON" STATUSLINE_SHOW_SESSION_CMD=1 \
    STATUSLINE_SESSION_CMD='claude -c --effort low'
  [ "$status" -eq 0 ]
  line1="$(head -1 <<<"$output")"
  [[ "$line1" == *"(high, thinking, fast)"* ]]
  [[ "$line1" == *"⌘ -c"* ]]
  [[ "$line1" != *"effort:low"* ]]
}

@test "golden: the launch-time effort:<v> stays when stdin has no effort level" {
  run run_statusline "$(json_with 'Opus 5.5' '')" STATUSLINE_SHOW_SESSION_CMD=1 \
    STATUSLINE_SESSION_CMD='claude -c --effort low'
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"⌘ -c effort:low"* ]]
}

@test "golden: the launch-time effort:<v> stays when the label is turned off" {
  run run_statusline "$ALL_ON" STATUSLINE_SHOW_EFFORT=0 STATUSLINE_SHOW_SESSION_CMD=1 \
    STATUSLINE_SESSION_CMD='claude -c --effort low'
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"⌘ -c effort:low"* ]]
}

@test "golden: an effort level outside [a-z0-9_-] is dropped, not rendered" {
  run run_statusline "$(json_with 'Opus 5.5' ',"effort":{"level":"\u001b[31mred"}')"
  [ "$status" -eq 0 ]
  line1="$(head -1 <<<"$output")"
  [[ "$line1" == *"Opus 5.5  v2.1.300"* ]]
  [[ "$line1" != *$'\033'* ]]
}

@test "golden: non-object effort/thinking values don't shift the other fields" {
  run run_statusline "$(json_with 'Opus 5.5' ',"effort":"high","thinking":"yes","fast_mode":"true"')"
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Opus 5.5  v2.1.300  default"* ]]
}

# ---- STATUSLINE_SHOW_TURN_EFFORT (transcript tail) ----

asst() {
  printf '{"parentUuid":"p","isSidechain":%s,"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]},"effort":"%s","perTurnEffort":"%s"}' \
    "${2:-false}" "${3:-hi}" "$1" "$1"
}

json_with_transcript() {
  json_with 'Opus 5.5' ',"effort":{"level":"high"},"thinking":{"enabled":true},"transcript_path":"'"$1"'"'
}

@test "golden: turn effort is opt-in and off by default" {
  t="$BATS_TEST_TMPDIR/t.jsonl"
  asst xhigh >"$t"
  run run_statusline "$(json_with_transcript "$t")"
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Opus 5.5 (high, thinking)  v2.1.300"* ]]
}

@test "golden: STATUSLINE_SHOW_TURN_EFFORT=1 adds turn:<v> when the last response ran higher" {
  t="$BATS_TEST_TMPDIR/t.jsonl"
  { asst high; echo; asst xhigh; echo; echo '{"type":"last-prompt"}'; echo '{"type":"mode","mode":"normal"}'; } >"$t"
  run run_statusline "$(json_with_transcript "$t")" STATUSLINE_SHOW_TURN_EFFORT=1
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Opus 5.5 (high, turn:xhigh, thinking)  v2.1.300"* ]]
}

@test "golden: turn effort equal to the session level is not repeated" {
  t="$BATS_TEST_TMPDIR/t.jsonl"
  { asst xhigh; echo; asst high; echo; } >"$t"
  run run_statusline "$(json_with_transcript "$t")" STATUSLINE_SHOW_TURN_EFFORT=1
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Opus 5.5 (high, thinking)  v2.1.300"* ]]
}

@test "golden: sidechain responses don't count as the main conversation's turn" {
  t="$BATS_TEST_TMPDIR/t.jsonl"
  { asst high; echo; asst max true; echo; } >"$t"
  run run_statusline "$(json_with_transcript "$t")" STATUSLINE_SHOW_TURN_EFFORT=1
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" != *"turn:"* ]]
}

@test "golden: a perTurnEffort string inside message text is not mistaken for the field" {
  t="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' '{"type":"assistant","isSidechain":false,"message":{"content":[{"type":"text","text":"{\"perTurnEffort\":\"max\"}"}]}}' >"$t"
  run run_statusline "$(json_with_transcript "$t")" STATUSLINE_SHOW_TURN_EFFORT=1
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" != *"turn:"* ]]
}

@test "golden: compact layout leaves turn effort out" {
  t="$BATS_TEST_TMPDIR/t.jsonl"
  asst xhigh >"$t"
  run run_statusline "$(json_with_transcript "$t")" STATUSLINE_SHOW_TURN_EFFORT=1 STATUSLINE_COMPACT=1
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" != *"turn:"* ]]
}

@test "golden: a missing transcript file renders without turn effort" {
  run run_statusline "$(json_with_transcript "$BATS_TEST_TMPDIR/nope.jsonl")" STATUSLINE_SHOW_TURN_EFFORT=1
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"Opus 5.5 (high, thinking)  v2.1.300"* ]]
}

@test "golden: STATUSLINE_SHOW_TURN_EFFORT=1 from the config file is honored" {
  t="$BATS_TEST_TMPDIR/t.jsonl"
  asst xhigh >"$t"
  run run_statusline_with_config "$(json_with_transcript "$t")" "STATUSLINE_SHOW_TURN_EFFORT=1"
  [ "$status" -eq 0 ]
  [[ "$(head -1 <<<"$output")" == *"(high, turn:xhigh, thinking)"* ]]
}
