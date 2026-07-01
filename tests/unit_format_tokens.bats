#!/usr/bin/env bats

load 'test_helper'

setup() {
  load_fn format_tokens
}

@test "format_tokens: passes through small numbers unchanged" {
  run format_tokens 42
  [ "$status" -eq 0 ]
  [ "$output" = "42" ]
}

@test "format_tokens: formats thousands with one decimal and K suffix" {
  run format_tokens 45200
  [ "$output" = "45.2K" ]
}

@test "format_tokens: formats millions with two decimals and M suffix" {
  run format_tokens 1234567
  [ "$output" = "1.23M" ]
}

@test "format_tokens: passes through non-numeric input unchanged" {
  run format_tokens "abc"
  [ "$output" = "abc" ]
}
