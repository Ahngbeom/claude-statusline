#!/usr/bin/env bats

load 'test_helper'

setup() {
  load_fn round_half_up_int
}

@test "round_half_up_int: integer input passes through unchanged" {
  run round_half_up_int 5
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "round_half_up_int: first decimal digit < 5 truncates" {
  run round_half_up_int "4.49"
  [ "$output" = "4" ]
}

@test "round_half_up_int: first decimal digit >= 5 rounds up" {
  run round_half_up_int "4.51"
  [ "$output" = "5" ]
}

@test "round_half_up_int: exactly .5 rounds up (half-up, not banker's rounding)" {
  run round_half_up_int "91.5"
  [ "$output" = "92" ]
}

@test "round_half_up_int: rounding carries into the whole part at the .99/100 boundary" {
  run round_half_up_int "99.5"
  [ "$output" = "100" ]
}

@test "round_half_up_int: zero input" {
  run round_half_up_int 0
  [ "$output" = "0" ]
}
