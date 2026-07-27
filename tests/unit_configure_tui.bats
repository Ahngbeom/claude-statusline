#!/usr/bin/env bats
#
# Tests for the pure-logic pieces of configure.sh's full TUI (run_full_tui(),
# see "full TUI (arrow-key navigable, pinned live preview)" in configure.sh)
# that don't require a real pty: _read_key()'s escape-sequence parsing (it
# only calls `read`, never `stty`) and _tui_build_rows()'s CATEGORY_DEFS ->
# _TUI_ROWS conversion. The raw-mode/alternate-screen interactive loop itself
# needs a real terminal and isn't covered by automated tests here -- see the
# manual verification checklist in the implementation plan. Bare
# `configure.sh` and `configure.sh menu` continue to exercise run_menu() (the
# light/fallback path) under bats, since piped stdin is never a tty --
# covered by tests/unit_configure_menu.bats, unchanged by this feature.

load 'test_helper'

# Extracts a top-level function or array-literal definition out of
# configure.sh by exact start/end line match, for testing in isolation
# without sourcing (and thereby running) the whole script.
_extract() {
  sed -n "/^$1\$/,/^$2\$/p" "$CONFIGURE_SH"
}

# Feeds $2 (a printf %b-escaped byte sequence) to _read_key() and prints the
# resulting $REPLY.
_read_key_with() {
  local fn
  fn="$(_extract '_read_key() {' '}')"
  printf '%b' "$1" | bash -c "$fn"$'\n''_read_key; printf "%s" "$REPLY"'
}

@test "_read_key: arrow keys resolve to UP/DOWN/LEFT/RIGHT" {
  [ "$(_read_key_with '\033[A')" = "UP" ]
  [ "$(_read_key_with '\033[B')" = "DOWN" ]
  [ "$(_read_key_with '\033[D')" = "LEFT" ]
  [ "$(_read_key_with '\033[C')" = "RIGHT" ]
}

@test "_read_key: page up/down escape sequences resolve to PGUP/PGDN" {
  [ "$(_read_key_with '\033[5~')" = "PGUP" ]
  [ "$(_read_key_with '\033[6~')" = "PGDN" ]
}

@test "_read_key: carriage return resolves to ENTER" {
  [ "$(_read_key_with '\r')" = "ENTER" ]
}

@test "_read_key: a plain character resolves to CHAR:<c>" {
  [ "$(_read_key_with 'x')" = "CHAR:x" ]
  [ "$(_read_key_with 'q')" = "CHAR:q" ]
}

@test "_read_key: space resolves to a literal CHAR: with a trailing space" {
  [ "$(_read_key_with ' ')" = "CHAR: " ]
}

@test "_read_key: EOF (no input at all) resolves to EOF, not a spin" {
  local fn
  fn="$(_extract '_read_key() {' '}')"
  run bash -c "$fn"$'\n''_read_key; printf "%s" "$REPLY"' < /dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "EOF" ]
}

@test "_read_key: a lone Esc with no follow-up bytes resolves to ESC" {
  # Takes ~1s: bash 3.2 (macOS stock bash) only accepts an integer `read -t`
  # timeout, confirmed by direct testing -- see the NOTE in configure.sh.
  [ "$(_read_key_with '\033')" = "ESC" ]
}

_tui_rows_snapshot() {
  local defs fn
  defs="$(_extract 'CATEGORY_DEFS=(' ')')"
  fn="$(_extract '_tui_build_rows() {' '}')"
  bash -c "$defs"$'\n'"$fn"$'\n''_tui_build_rows; printf "%s\n" "${_TUI_ROWS[@]}"'
}

@test "_tui_build_rows: produces one H: row per category and one K: row per key" {
  run _tui_rows_snapshot
  [ "$status" -eq 0 ]
  local headers keys
  headers=$(grep -c '^H:' <<<"$output")
  keys=$(grep -c '^K:' <<<"$output")
  [ "$headers" -eq 12 ]
  [ "$keys" -eq 48 ]
}

@test "_tui_build_rows: the first row is a header and the second is its first key" {
  run _tui_rows_snapshot
  [ "$status" -eq 0 ]
  local first second
  first=$(sed -n '1p' <<<"$output")
  second=$(sed -n '2p' <<<"$output")
  [ "$first" = "H:Colors & bar style" ]
  [ "$second" = "K:NO_COLOR" ]
}

@test "_tui_build_rows: every K: row names a key configure.sh actually recognizes" {
  run _tui_rows_snapshot
  [ "$status" -eq 0 ]
  local line key
  while IFS= read -r line; do
    case "$line" in
      K:*)
        key="${line#K:}"
        run bash "$CONFIGURE_SH" get "$key"
        [ "$status" -eq 0 ]
        ;;
    esac
  done <<<"$output"
}

configure_sh() {
  bash "$CONFIGURE_SH" "$@"
}

@test "menu: 'configure.sh menu' is the explicit escape hatch to the light menu" {
  run bash -c 'printf "0\n" | bash "$0" menu' "$CONFIGURE_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Live Preview"* ]]
  [[ "$output" == *"claude-statusline configure"* ]]
}
