#!/usr/bin/env bats

load 'test_helper'

setup() {
  load_fn round_money
}

@test "round_money: integer input gets .00 appended" {
  run round_money 5
  [ "$status" -eq 0 ]
  [ "$output" = "5.00" ]
}

@test "round_money: single fractional digit is zero-padded, not rounded" {
  run round_money "4.3"
  [ "$output" = "4.30" ]
}

@test "round_money: third decimal digit >= 5 rounds the cents up" {
  run round_money "12.345"
  [ "$output" = "12.35" ]
}

@test "round_money: third decimal digit < 5 truncates the cents" {
  run round_money "12.344"
  [ "$output" = "12.34" ]
}

@test "round_money: rounding carries into the whole part at the .99/.100 boundary" {
  run round_money "0.999"
  [ "$output" = "1.00" ]
}

@test "round_money: exact two-decimal input passes through unchanged" {
  run round_money "12.34"
  [ "$output" = "12.34" ]
}
