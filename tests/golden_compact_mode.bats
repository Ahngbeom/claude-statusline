#!/usr/bin/env bats
#
# End-to-end tests for the compact layout (see README "Compact Mode" and
# CLAUDE.md's "compact mode 감지" section). Mirrors golden_output.bats's
# conventions: isolated HOME, non-git tmpdir (unless a real repo is needed),
# NO_COLOR=1 so assertions don't need to match ANSI codes.

load 'test_helper'

JSON='{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"},"session_id":"sess-1","version":"1.2.3","output_style":{"name":"concise"},"context_window":{"total_input_tokens":45000,"context_window_size":200000},"cost":{"total_cost_usd":0.42}}'

@test "golden: COLUMNS below the default 80 threshold triggers compact mode" {
  run run_statusline "$JSON" COLUMNS=40
  [ "$status" -eq 0 ]

  line1="$(sed -n '1p' <<<"$output")"
  # basename only, no cc_version/output_style/Mem
  [ "$line1" = "📂 myapp  │ Opus 4.6" ]

  line2="$(sed -n '2p' <<<"$output")"
  # No "Context" label word, 8-wide bar instead of 20-wide
  [ "$line2" = "🧠 45.0K/200.0K ======-- 78%" ]
}

@test "golden: COLUMNS at/above the default 80 threshold keeps the full layout (no regression)" {
  run run_statusline "$JSON" COLUMNS=120
  [ "$status" -eq 0 ]

  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"/tmp/proj/myapp"* ]]
  [[ "$line1" == *"v1.2.3"* ]]
  [[ "$line1" == *"concise"* ]]

  line2="$(sed -n '2p' <<<"$output")"
  [[ "$line2" == *"Context 45.0K/200.0K"* ]]
}

@test "golden: COLUMNS unset keeps the full layout (backward compatibility)" {
  run run_statusline "$JSON"
  [ "$status" -eq 0 ]

  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"/tmp/proj/myapp"* ]]
  [[ "$line1" == *"v1.2.3"* ]]
}

@test "golden: STATUSLINE_COMPACT=1 forces compact mode regardless of a wide COLUMNS" {
  run run_statusline "$JSON" COLUMNS=200 STATUSLINE_COMPACT=1
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [ "$line1" = "📂 myapp  │ Opus 4.6" ]
}

@test "golden: STATUSLINE_COMPACT=0 forces the full layout regardless of a narrow COLUMNS" {
  run run_statusline "$JSON" COLUMNS=30 STATUSLINE_COMPACT=0
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *"/tmp/proj/myapp"* ]]
  [[ "$line1" == *"v1.2.3"* ]]
}

@test "golden: STATUSLINE_COMPACT_WIDTH overrides the default threshold" {
  run run_statusline "$JSON" COLUMNS=90 STATUSLINE_COMPACT_WIDTH=100
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [ "$line1" = "📂 myapp  │ Opus 4.6" ]
}

@test "golden: compact mode Line 3 collapses to Sess <cost> <time> │ Today <cost>, no tokens/Week/Month/cache" {
  run run_statusline_with_cache "$JSON" COLUMNS=40
  [ "$status" -eq 0 ]

  line3="$(sed -n '3p' <<<"$output")"
  # seed_ccusage_cache fixture: session costUSD=12.34, daily totalCost=4.32
  [[ "$line3" == 💰*'Sess $12.34'* ]]
  [[ "$line3" == *'Today $4.32'* ]]
  [[ "$line3" != *'Week'* ]]
  [[ "$line3" != *'Month'* ]]
  [[ "$line3" != *'🗄'* ]]
  # 500.0K is the seeded session token count -- must not leak into compact Line 3
  [[ "$line3" != *'500.0K'* ]]
}

@test "golden: compact mode + STATUSLINE_HIDE_COST=1 hides Today entirely and drops cost from Sess" {
  run run_statusline_with_cache "$JSON" COLUMNS=40 STATUSLINE_HIDE_COST=1
  [ "$status" -eq 0 ]

  [[ "$output" != *'$'* ]]
  line3="$(sed -n '3p' <<<"$output")"
  [[ "$line3" != *'Today'* ]]
}

@test "golden: compact mode Line 1 includes git branch with dirty/ahead-behind markers" {
  base="$(mktemp -d)"
  git init --quiet --bare "$base/origin.git"
  git init --quiet -b main "$base/work"
  git -C "$base/work" config user.email "test@example.com"
  git -C "$base/work" config user.name "Test"
  git -C "$base/work" remote add origin "$base/origin.git"
  echo "one" >"$base/work/file.txt"
  git -C "$base/work" add file.txt
  git -C "$base/work" commit --quiet -m "initial"
  git -C "$base/work" push --quiet -u origin main
  echo "uncommitted" >>"$base/work/file.txt"

  run run_statusline_in "$base/work" '{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"}}' COLUMNS=40
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [ "$line1" = "📂 myapp  main*  │ Opus 4.6" ]

  rm -rf "$base"
}
