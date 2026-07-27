#!/usr/bin/env bats
#
# Tests for STATUSLINE_ICON_*/STATUSLINE_SEP_CHAR overrides (see "icon
# overrides"/"separator character override" in statusline.sh). Plaintext
# assertions, so the usual NO_COLOR=1 run_statusline helper is fine here.

load 'test_helper'

JSON='{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"},"context_window":{"total_input_tokens":45000,"context_window_size":200000}}'

@test "icon: STATUSLINE_ICON_DIR replaces the default 📂 prefix on Line 1" {
  run run_statusline "$JSON" STATUSLINE_ICON_DIR=🚀
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == 🚀* ]]
  [[ "$line1" != 📂* ]]
}

@test "icon: STATUSLINE_ICON_CONTEXT replaces the default 🧠 prefix on Line 2" {
  run run_statusline "$JSON" STATUSLINE_ICON_CONTEXT=⚡
  [ "$status" -eq 0 ]
  line2="$(sed -n '2p' <<<"$output")"
  [[ "$line2" == ⚡* ]]
}

@test "icon: STATUSLINE_ICON_CACHE replaces the default 🗄 prefix on the cache-hit-rate segment" {
  run run_statusline_with_cache "$JSON" STATUSLINE_ICON_CACHE=📊
  [ "$status" -eq 0 ]
  line2="$(sed -n '2p' <<<"$output")"
  [[ "$line2" == *📊* ]]
  [[ "$line2" != *🗄* ]]
}

@test "icon: STATUSLINE_ICON_COST replaces the default 💰 prefix on Line 3" {
  run run_statusline_with_cache "$JSON" STATUSLINE_ICON_COST=💵
  [ "$status" -eq 0 ]
  line3="$(sed -n '3p' <<<"$output")"
  [[ "$line3" == 💵* ]]
}

@test "icon: STATUSLINE_ICON_MEM replaces the default 💻 prefix on the Mem indicator" {
  run run_statusline "$JSON" STATUSLINE_ICON_MEM=🔋
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  [[ "$line1" == *🔋* ]]
  [[ "$line1" != *💻* ]]
}

@test "icon: default icons render unchanged when no override is set" {
  run run_statusline "$JSON"
  [ "$status" -eq 0 ]
  line1="$(sed -n '1p' <<<"$output")"
  line2="$(sed -n '2p' <<<"$output")"
  [[ "$line1" == 📂* ]]
  [[ "$line2" == 🧠* ]]
}

@test "separator: STATUSLINE_SEP_CHAR replaces │ everywhere it appears" {
  run run_statusline "$JSON" STATUSLINE_SEP_CHAR="::"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::"* ]]
  [[ "$output" != *"│"* ]]
}

@test "separator: default separator is │ when no override is set" {
  run run_statusline "$JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│"* ]]
}
