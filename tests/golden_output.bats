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
