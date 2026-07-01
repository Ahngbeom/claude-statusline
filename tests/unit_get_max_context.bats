#!/usr/bin/env bats

load 'test_helper'

setup() {
  load_fn get_max_context
}

@test "get_max_context: [1m]/[1M] bracket notation returns 1000000" {
  run get_max_context "Opus 4.7 [1m]"
  [ "$output" = "1000000" ]
  run get_max_context "Sonnet 4.7 [1M]"
  [ "$output" = "1000000" ]
}

@test "get_max_context: '1M context' / '1m context' suffix returns 1000000" {
  run get_max_context "Opus 4.7 1M context"
  [ "$output" = "1000000" ]
}

@test "get_max_context: bare '1M' substring (no brackets, no 'context' suffix) does not false-positive (regression for v1.3.4 fix)" {
  run get_max_context "Opus 4.7 1M"
  [ "$output" = "200000" ]
}

@test "get_max_context: Claude 3 Haiku returns 100000, not shadowed by the generic Haiku pattern (regression)" {
  run get_max_context "Claude 3 Haiku"
  [ "$output" = "100000" ]
  run get_max_context "claude 3 haiku"
  [ "$output" = "100000" ]
}

@test "get_max_context: Haiku 3.5/4 return 200000" {
  run get_max_context "Haiku 3.5"
  [ "$output" = "200000" ]
  run get_max_context "Haiku 4"
  [ "$output" = "200000" ]
}

@test "get_max_context: Opus/Sonnet return 200000" {
  run get_max_context "Opus 4.6"
  [ "$output" = "200000" ]
  run get_max_context "Sonnet 4.5"
  [ "$output" = "200000" ]
}

@test "get_max_context: unknown model defaults to 200000" {
  run get_max_context "Some Future Model"
  [ "$output" = "200000" ]
}
