#!/usr/bin/env bats
#
# Tests for the rate_limits.five_hour -> Session (Line 2) gauge override (see
# the "rate_limits.five_hour override" block in the "# ---- ccusage
# integration ----" section of statusline.sh). seed_ccusage_cache (test_helper.bash)
# always produces a 1h-elapsed/4h-total active block, i.e. a deterministic
# ccusage-derived session_pct of 25% -> progress_bar renders "==--------"
# (2 filled / 8 empty at width 10). A fresh rate_limits.five_hour with
# used_percentage=70 renders "=======---" (7 filled / 3 empty) instead --
# distinguishable from the ccusage pattern, so a substring match proves which
# source won without needing to assert exact rh/rm minutes (clock-drift-prone,
# see golden_output.bats's own avoidance of exact time assertions).

load 'test_helper'

@test "rate_limits session override: fresh five_hour wins over the ccusage block estimate" {
  local resets_at=$(( $(date +%s) + 1800 ))
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","rate_limits":{"five_hour":{"used_percentage":70,"resets_at":'"$resets_at"'}}}'
  run run_statusline_with_cache "$json"

  [ "$status" -eq 0 ]
  [[ "$output" == *"=======---"* ]]
  [[ "$output" != *"==--------"* ]]
}

@test "rate_limits session override: stale (past) resets_at falls back to the ccusage estimate" {
  local resets_at=$(( $(date +%s) - 100 ))
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","rate_limits":{"five_hour":{"used_percentage":70,"resets_at":'"$resets_at"'}}}'
  run run_statusline_with_cache "$json"

  [ "$status" -eq 0 ]
  [[ "$output" == *"==--------"* ]]
  [[ "$output" != *"=======---"* ]]
}

@test "rate_limits session override: absent rate_limits leaves the ccusage estimate unchanged" {
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1"}'
  run run_statusline_with_cache "$json"

  [ "$status" -eq 0 ]
  [[ "$output" == *"==--------"* ]]
}

@test "rate_limits session override: no ccusage cache means Session still doesn't render, even with fresh rate_limits" {
  local resets_at=$(( $(date +%s) + 1800 ))
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","rate_limits":{"five_hour":{"used_percentage":70,"resets_at":'"$resets_at"'}}}'
  run run_statusline "$json"

  [ "$status" -eq 0 ]
  line2="$(sed -n '2p' <<<"$output")"
  [[ "$line2" != *"Session"* ]]
}

@test "rate_limits session override: fractional used_percentage rounds correctly without depending on printf locale parsing" {
  local resets_at=$(( $(date +%s) + 1800 ))
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","rate_limits":{"five_hour":{"used_percentage":91.5,"resets_at":'"$resets_at"'}}}'
  run run_statusline_with_cache "$json"

  [ "$status" -eq 0 ]
  # 91.5 rounds up to 92% -> floor(92*10/100) = 9 filled / 1 empty.
  [[ "$output" == *"=========-"* ]]
}

@test "rate_limits session override: non-numeric used_percentage/resets_at don't break Line 1 parsing" {
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","rate_limits":{"five_hour":{"used_percentage":{"raw":70,"rounded":70},"resets_at":"soon"}}}'
  run run_statusline_with_cache "$json"

  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"/tmp/proj"* ]]
  [[ "$line1" == *"Opus 4.6"* ]]
}

@test "rate_limits session override: resets_at far beyond the 5h window (e.g. a ms-vs-s unit mismatch) falls back to the ccusage estimate" {
  local resets_at=$(( ($(date +%s) + 1800) * 1000 ))
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","rate_limits":{"five_hour":{"used_percentage":70,"resets_at":'"$resets_at"'}}}'
  run run_statusline_with_cache "$json"

  [ "$status" -eq 0 ]
  [[ "$output" == *"==--------"* ]]
  [[ "$output" != *"=======---"* ]]
}
