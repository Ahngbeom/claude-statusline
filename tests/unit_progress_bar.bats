#!/usr/bin/env bats

load 'test_helper'

setup() {
  _bar_fill="="
  _bar_empty="-"
  load_fn progress_bar
}

@test "progress_bar: 0% is fully empty" {
  run progress_bar 0 10
  [ "$output" = "----------" ]
}

@test "progress_bar: 100% is fully filled" {
  run progress_bar 100 10
  [ "$output" = "==========" ]
}

@test "progress_bar: 77% of width 20 fills 15 of 20 chars" {
  run progress_bar 77 20
  expected="$(printf '=%.0s' $(seq 1 15))$(printf -- '-%.0s' $(seq 1 5))"
  [ "$output" = "$expected" ]
}

@test "progress_bar: clamps percentages above 100" {
  run progress_bar 150 10
  [ "$output" = "==========" ]
}

@test "progress_bar: clamps negative percentages to 0" {
  run progress_bar -5 10
  [ "$output" = "----------" ]
}

@test "progress_bar: non-numeric percentage defaults to 0" {
  run progress_bar "abc" 10
  [ "$output" = "----------" ]
}
