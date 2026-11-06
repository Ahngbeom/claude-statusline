#!/usr/bin/env bats
#
# End-to-end tests for the "last change" deltas on Line 2 (context +N tokens,
# session cost +$N). Each test renders several times against ONE persistent
# HOME, because the delta is computed against per-session state the previous
# render left in ~/.claude/statusline-state/.

load 'test_helper'

setup() {
  TEST_HOME="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_HOME"
}

render() {
  local json="$1"; shift
  ( cd "$TEST_HOME" && printf '%s' "$json" | HOME="$TEST_HOME" NO_COLOR=1 STATUSLINE_SHOW_SESSION_CMD=0 env "$@" bash "$STATUSLINE_SH" )
}

ctx_json() {
  # $1 = context tokens, $2 = session id (default sess-1), $3 = cost (optional)
  local cost=""
  [ -n "$3" ] && cost=',"cost":{"total_cost_usd":'"$3"'}'
  printf '{"workspace":{"current_dir":"/tmp/p"},"model":{"display_name":"Opus 4.6"},"session_id":"%s","context_window":{"total_input_tokens":%s,"context_window_size":200000}%s}' "${2:-sess-1}" "$1" "$cost"
}

line2_of() { sed -n '2p' <<<"$1"; }

# Like ctx_json, plus a prompt_id ($4) -- the per-user-prompt grouping key.
prompt_json() {
  local cost=""
  [ -n "$3" ] && cost=',"cost":{"total_cost_usd":'"$3"'}'
  printf '{"workspace":{"current_dir":"/tmp/p"},"model":{"display_name":"Opus 4.6"},"session_id":"%s","prompt_id":"%s","context_window":{"total_input_tokens":%s,"context_window_size":200000}%s}' "${2:-sess-1}" "$4" "$1" "$cost"
}

@test "golden: the first render of a session shows no delta" {
  run render "$(ctx_json 45000)"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"78%" ]]
}

@test "golden: a context increase shows +N after the percentage" {
  render "$(ctx_json 45000)" >/dev/null
  run render "$(ctx_json 49200)"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"76% +4.2K" ]]
}

@test "golden: the delta persists across re-renders with no change (refreshInterval ticks)" {
  render "$(ctx_json 45000)" >/dev/null
  render "$(ctx_json 49200)" >/dev/null
  run render "$(ctx_json 49200)"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"76% +4.2K" ]]
}

@test "golden: a context drop (e.g. after /compact) shows -N" {
  render "$(ctx_json 49200)" >/dev/null
  run render "$(ctx_json 10000)"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"95% -39.2K" ]]
}

@test "golden: deltas are tracked per session id" {
  render "$(ctx_json 45000 sess-a)" >/dev/null
  render "$(ctx_json 90000 sess-b)" >/dev/null
  run render "$(ctx_json 46000 sess-a)"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"77% +1.0K" ]]
}

@test "golden: a session cost increase shows +\$N next to the session cost" {
  seed_ccusage_cache "$TEST_HOME"
  render "$(ctx_json 45000 sess-1 0.42)" >/dev/null
  run render "$(ctx_json 45000 sess-1 0.47)"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"Session 500.0K \$0.47 +\$0.05  "* ]]
}

@test "golden: a sub-cent cost change shows no cost delta" {
  seed_ccusage_cache "$TEST_HOME"
  render "$(ctx_json 45000 sess-1 0.420)" >/dev/null
  run render "$(ctx_json 45000 sess-1 0.421)"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" != *"+\$"* ]]
}

@test "golden: STATUSLINE_HIDE_COST=1 hides the cost delta with the cost" {
  seed_ccusage_cache "$TEST_HOME"
  render "$(ctx_json 45000 sess-1 0.42)" STATUSLINE_HIDE_COST=1 >/dev/null
  run render "$(ctx_json 45000 sess-1 0.47)" STATUSLINE_HIDE_COST=1
  [ "$status" -eq 0 ]
  [[ "$output" != *"+\$"* ]]
}

@test "golden: STATUSLINE_SHOW_DELTA=0 hides deltas and writes no state" {
  render "$(ctx_json 45000)" STATUSLINE_SHOW_DELTA=0 >/dev/null
  run render "$(ctx_json 49200)" STATUSLINE_SHOW_DELTA=0
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"76%" ]]
  [ ! -e "$TEST_HOME/.claude/statusline-state" ]
}

@test "golden: compact mode renders no delta" {
  render "$(ctx_json 45000)" STATUSLINE_COMPACT=1 >/dev/null
  run render "$(ctx_json 49200)" STATUSLINE_COMPACT=1
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"76%" ]]
}

@test "security: a session id with path characters writes no state" {
  render "$(ctx_json 45000 '../../evil')" >/dev/null
  run render "$(ctx_json 49200 '../../evil')"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"76%" ]]
  [ ! -e "$TEST_HOME/evil" ]
  [ -z "$(ls -A "$TEST_HOME/.claude/statusline-state" 2>/dev/null)" ]
}

@test "golden: a corrupt state file is ignored and then replaced" {
  mkdir -p "$TEST_HOME/.claude/statusline-state"
  printf 'garbage $(touch %s/pwned)\n' "$TEST_HOME" > "$TEST_HOME/.claude/statusline-state/sess-1"
  run render "$(ctx_json 49200)"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"76%" ]]
  [ ! -e "$TEST_HOME/pwned" ]
  run render "$(ctx_json 50200)"
  [[ "$(line2_of "$output")" == *"75% +1.0K" ]]
}

@test "golden: with prompt_id, every step of one prompt accumulates into one delta" {
  render "$(ctx_json 40000)" >/dev/null                  # session start, before any prompt
  run render "$(prompt_json 45000 sess-1 '' p1)"
  [[ "$(line2_of "$output")" == *"78% +5.0K" ]]           # first render already includes step 1
  run render "$(prompt_json 49200 sess-1 '' p1)"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"76% +9.2K" ]]           # step 2 adds on, not +4.2K
}

@test "golden: a new prompt_id measures from the previous prompt's last value" {
  render "$(prompt_json 45000 sess-1 '' p1)" >/dev/null
  render "$(prompt_json 49200 sess-1 '' p1)" >/dev/null
  run render "$(prompt_json 50200 sess-1 '' p2)"
  [[ "$(line2_of "$output")" == *"75% +1.0K" ]]
  run render "$(prompt_json 50200 sess-1 '' p2)"          # idle re-render keeps it
  [[ "$(line2_of "$output")" == *"75% +1.0K" ]]
}

@test "golden: with prompt_id, the cost delta covers the whole prompt" {
  seed_ccusage_cache "$TEST_HOME"
  render "$(ctx_json 45000 sess-1 0.40)" >/dev/null
  render "$(prompt_json 46000 sess-1 0.45 p1)" >/dev/null
  run render "$(prompt_json 47000 sess-1 0.52 p1)"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"Session 500.0K \$0.52 +\$0.12  "* ]]
}

@test "golden: a prompt_id with unexpected characters falls back to per-step deltas" {
  render "$(prompt_json 45000 sess-1 '' 'p1 x')" >/dev/null
  render "$(prompt_json 46000 sess-1 '' 'p1 x')" >/dev/null
  run render "$(prompt_json 48000 sess-1 '' 'p1 x')"
  [ "$status" -eq 0 ]
  [[ "$(line2_of "$output")" == *"76% +2.0K" ]]
}
