#!/usr/bin/env bats
#
# End-to-end tests: run the real statusline.sh as a subprocess against a
# fixed stdin JSON and assert on the printed lines. HOME is isolated per-run
# (see test_helper.bash) so ccusage cache/background jobs never touch the
# developer's real ~/.claude, and cwd is a fresh non-git tmpdir so git
# branch detection is deterministic. The one remaining non-deterministic
# field (system memory %) is normalized before comparison. Since there is
# no ccusage cache in the fresh HOME, Session/Line 3 never appear (matches
# the documented graceful-degradation behavior).

load 'test_helper'

@test "golden: context_window from stdin renders Line 1 + Context part, no Line 3 (graceful degradation)" {
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","version":"1.2.3","output_style":{"name":"concise"},"context_window":{"total_input_tokens":45000,"context_window_size":200000},"cost":{"total_cost_usd":0.42}}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]

  line1="$(normalize_mem "$(sed -n '1p' <<<"$output")")"
  [ "$line1" = "📂 /tmp/proj  │ Opus 4.6  v1.2.3  concise  │ 💻 Mem NN%" ]

  line2="$(sed -n '2p' <<<"$output")"
  [ "$line2" = "🧠 Context 45.0K/200.0K ===============----- 78%" ]

  # No ccusage cache present in the fresh HOME -> no Line 3
  line3="$(sed -n '3p' <<<"$output")"
  [ -z "$line3" ]
}

@test "golden: used tokens exceeding window size clamp remaining% to 0 (regression for v1.3.4 fix)" {
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","context_window":{"total_input_tokens":250000,"context_window_size":200000}}'
  run run_statusline "$json"
  [ "$status" -eq 0 ]

  line2="$(sed -n '2p' <<<"$output")"
  [ "$line2" = "🧠 Context 250.0K/200.0K -------------------- 0%" ]
}

@test "golden: JSONL fallback sums input+cache_read+cache_creation tokens (regression for v1.3.3 fix)" {
  transcript="$FIXTURES_DIR/session_cache_creation.jsonl"
  json="{\"workspace\":{\"current_dir\":\"/tmp/proj\"},\"model\":{\"display_name\":\"Sonnet 4.5\"},\"session_id\":\"sess-2\",\"transcript_path\":\"$transcript\"}"
  run run_statusline "$json"
  [ "$status" -eq 0 ]

  # 50000 + 30000 + 25000 = 105000 used of 200000 max -> 48% remaining
  line2="$(sed -n '2p' <<<"$output")"
  [ "$line2" = "🧠 Context 105.0K/200.0K =========----------- 48%" ]
}

@test "golden: JSONL fallback locates the session file via manual path construction when transcript_path is absent" {
  # Regression test for the sed-chain -> pure bash rewrite of the
  # session-file path construction (no transcript_path in stdin, so
  # statusline.sh must build ~/.claude/projects/-{encoded-dir}/{session}.jsonl
  # itself). No existing test exercised this branch before.
  tmp_home="$(mktemp -d)"
  session_dir="$tmp_home/.claude/projects/-tmp-proj"
  mkdir -p "$session_dir"
  cp "$FIXTURES_DIR/session_cache_creation.jsonl" "$session_dir/sess-manual.jsonl"

  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Sonnet 4.5"},"session_id":"sess-manual"}'
  run bash -c 'cd "$1" && printf "%s" "$2" | HOME="$1" NO_COLOR=1 bash "$3"' _ "$tmp_home" "$json" "$STATUSLINE_SH"
  [ "$status" -eq 0 ]

  # Same fixture/expectation as the transcript_path-based JSONL fallback test:
  # 50000 + 30000 + 25000 = 105000 used of 200000 max -> 48% remaining
  line2="$(sed -n '2p' <<<"$output")"
  [ "$line2" = "🧠 Context 105.0K/200.0K =========----------- 48%" ]

  rm -rf "$tmp_home"
}

@test "golden: STATUSLINE_MAX_CONTEXT overrides the JSONL fallback window size" {
  transcript="$FIXTURES_DIR/session_cache_creation.jsonl"
  json="{\"workspace\":{\"current_dir\":\"/tmp/proj\"},\"model\":{\"display_name\":\"Sonnet 4.5\"},\"session_id\":\"sess-2\",\"transcript_path\":\"$transcript\"}"
  run run_statusline "$json" STATUSLINE_MAX_CONTEXT=1000000
  [ "$status" -eq 0 ]

  # 105000 used of the overridden 1,000,000 max -> 90% remaining
  line2="$(sed -n '2p' <<<"$output")"
  [ "$line2" = "🧠 Context 105.0K/1.00M ==================-- 90%" ]
}

@test "golden: with an active ccusage session, cost/Line 3 render by default" {
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","context_window":{"total_input_tokens":45000,"context_window_size":200000},"cost":{"total_cost_usd":0.42}}'
  run run_statusline_with_cache "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\$0.42"* ]]
  line3="$(sed -n '3p' <<<"$output")"
  [ -n "$line3" ]
}

@test "golden: STATUSLINE_HIDE_COST=1 hides session cost and all of Line 3" {
  json='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","context_window":{"total_input_tokens":45000,"context_window_size":200000},"cost":{"total_cost_usd":0.42}}'
  run run_statusline_with_cache "$json" STATUSLINE_HIDE_COST=1
  [ "$status" -eq 0 ]

  # No "$" cost anywhere in the output, and no Line 3 at all
  [[ "$output" != *'$'* ]]
  line3="$(sed -n '3p' <<<"$output")"
  [ -z "$line3" ]
}
