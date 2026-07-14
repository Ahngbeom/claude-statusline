#!/usr/bin/env bats
#
# Tests for the rate_limits -> ~/.claude/rate-limits-cache.json side-channel
# write (see the "# ---- rate limits cache" section in statusline.sh). These
# use a local isolated-HOME helper instead of test_helper.bash's
# run_statusline, because these tests need to inspect
# $HOME/.claude/rate-limits-cache.json *after* the run, and run_statusline
# tears down its tmp HOME before returning.

load 'test_helper'

# Runs statusline.sh with an isolated HOME (same isolation as
# test_helper.bash's run_statusline -- fresh non-git cwd, NO_COLOR=1) but
# leaves the HOME directory in place for inspection via $RL_TMP_HOME. The
# teardown() hook below removes it after each test.
#
# Pre-creates $RL_TMP_HOME/.claude, matching seed_ccusage_cache's convention:
# in real usage ~/.claude always exists (statusline.sh itself lives there),
# but a fresh mktemp -d does not, and mktemp(1) can't create a temp file
# inside a parent directory that doesn't exist yet.
run_statusline_keep_home() {
  local json="$1"
  RL_TMP_HOME="$(mktemp -d)"
  mkdir -p "$RL_TMP_HOME/.claude"
  ( cd "$RL_TMP_HOME" && printf '%s' "$json" | HOME="$RL_TMP_HOME" NO_COLOR=1 bash "$STATUSLINE_SH" ) > /dev/null
}

teardown() {
  [ -n "$RL_TMP_HOME" ] && rm -rf "$RL_TMP_HOME"
}

@test "rate limits cache: rate_limits present is written verbatim" {
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}'
  run_statusline_keep_home "$json"

  [ -f "$RL_TMP_HOME/.claude/rate-limits-cache.json" ]
  cached="$(cat "$RL_TMP_HOME/.claude/rate-limits-cache.json")"
  [ "$cached" = '{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}' ]
}

@test "rate limits cache: absent rate_limits does not create the file" {
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1"}'
  run_statusline_keep_home "$json"

  [ ! -f "$RL_TMP_HOME/.claude/rate-limits-cache.json" ]
}

@test "rate limits cache: absent rate_limits preserves an existing cache file (no clobber on a transient gap)" {
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1"}'
  RL_TMP_HOME="$(mktemp -d)"
  mkdir -p "$RL_TMP_HOME/.claude"
  echo '{"five_hour":{"used_percentage":1,"resets_at":9999999999}}' > "$RL_TMP_HOME/.claude/rate-limits-cache.json"

  ( cd "$RL_TMP_HOME" && printf '%s' "$json" | HOME="$RL_TMP_HOME" NO_COLOR=1 bash "$STATUSLINE_SH" ) > /dev/null

  cached="$(cat "$RL_TMP_HOME/.claude/rate-limits-cache.json")"
  [ "$cached" = '{"five_hour":{"used_percentage":1,"resets_at":9999999999}}' ]
}

@test "rate limits cache: partial rate_limits (five_hour only, no seven_day) is written as-is" {
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","rate_limits":{"five_hour":{"used_percentage":10,"resets_at":1700000000}}}'
  run_statusline_keep_home "$json"

  cached="$(cat "$RL_TMP_HOME/.claude/rate-limits-cache.json")"
  [ "$cached" = '{"five_hour":{"used_percentage":10,"resets_at":1700000000}}' ]
}
