#!/usr/bin/env bats
#
# STATUSLINE_THEME presets (see "# ---- theme presets" in statusline.sh):
# a theme fills only keys left unset by the env and the config file.

load 'test_helper'

JSON='{"workspace":{"current_dir":"/tmp/proj/myapp"},"model":{"display_name":"Opus 4.6"},"context_window":{"total_input_tokens":45000,"context_window_size":200000}}'

@test "theme: space sets its colors, icons and separator" {
  run run_statusline_colored "$JSON" STATUSLINE_THEME=space
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;147m/tmp/proj/myapp'* ]]
  [[ "$output" == *"✧"* ]]
  [[ "$output" == *"⋆"* ]]
  [[ "$output" == *"☾"* ]]
  [[ "$output" != *"📂"* ]]
  [[ "$output" != *"│"* ]]
}

@test "theme: an individual STATUSLINE_COLOR_* env var beats the theme" {
  run run_statusline_colored "$JSON" STATUSLINE_THEME=space STATUSLINE_COLOR_DIR=196
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;196m/tmp/proj/myapp'* ]]
  [[ "$output" != *$'\033[38;5;147m/tmp/proj/myapp'* ]]
}

@test "theme: an individual icon in the config file beats the theme" {
  run run_statusline_with_config "$JSON" 'STATUSLINE_ICON_DIR=D' STATUSLINE_THEME=space
  [ "$status" -eq 0 ]
  [[ "$output" == *"D /tmp/proj/myapp"* ]]
  [[ "$output" != *"✧"* ]]
}

@test "theme: STATUSLINE_THEME from the config file applies" {
  run run_statusline_colored_with_config "$JSON" 'STATUSLINE_THEME=space'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;147m/tmp/proj/myapp'* ]]
  [[ "$output" == *"✧"* ]]
}

@test "theme: an env STATUSLINE_THEME beats the config file" {
  run run_statusline_with_config "$JSON" 'STATUSLINE_THEME=space' STATUSLINE_THEME=default
  [ "$status" -eq 0 ]
  [[ "$output" == *"📂"* ]]
  [[ "$output" != *"✧"* ]]
}

@test "theme: an unknown name keeps the defaults" {
  run run_statusline_colored "$JSON" STATUSLINE_THEME=nope
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;117m/tmp/proj/myapp'* ]]
  [[ "$output" == *"📂"* ]]
  [[ "$output" == *"│"* ]]
}

@test "theme: NO_COLOR keeps the theme's icons and drops its colors" {
  run run_statusline "$JSON" STATUSLINE_THEME=space
  [ "$status" -eq 0 ]
  [[ "$output" == *"✧ /tmp/proj/myapp"* ]]
  [[ "$output" != *$'\033['* ]]
}
