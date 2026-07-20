#!/usr/bin/env bats

load 'test_helper'

setup() {
  load_fn is_compact_mode
}

@test "is_compact_mode: COLUMNS below default 80 threshold triggers compact" {
  run is_compact_mode "79" "" ""
  [ "$output" = "1" ]
}

@test "is_compact_mode: COLUMNS at/above default 80 threshold stays full" {
  run is_compact_mode "80" "" ""
  [ "$output" = "0" ]
  run is_compact_mode "120" "" ""
  [ "$output" = "0" ]
}

@test "is_compact_mode: COLUMNS unset or non-numeric falls back to full (graceful degradation)" {
  run is_compact_mode "" "" ""
  [ "$output" = "0" ]
  run is_compact_mode "not-a-number" "" ""
  [ "$output" = "0" ]
}

@test "is_compact_mode: STATUSLINE_COMPACT=1 forces compact regardless of width" {
  run is_compact_mode "200" "1" ""
  [ "$output" = "1" ]
  run is_compact_mode "" "1" ""
  [ "$output" = "1" ]
}

@test "is_compact_mode: STATUSLINE_COMPACT=0 forces full regardless of width" {
  run is_compact_mode "20" "0" ""
  [ "$output" = "0" ]
}

@test "is_compact_mode: STATUSLINE_COMPACT_WIDTH overrides the default threshold" {
  run is_compact_mode "90" "" "100"
  [ "$output" = "1" ]
  run is_compact_mode "90" "" "50"
  [ "$output" = "0" ]
}

@test "is_compact_mode: non-numeric STATUSLINE_COMPACT_WIDTH falls back to default 80" {
  run is_compact_mode "70" "" "bogus"
  [ "$output" = "1" ]
  run is_compact_mode "90" "" "bogus"
  [ "$output" = "0" ]
}
