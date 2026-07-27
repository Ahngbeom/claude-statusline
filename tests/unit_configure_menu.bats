#!/usr/bin/env bats
#
# Tests for configure.sh's interactive "light TUI" (run_menu(), invoked with
# no subcommand): a category menu redrawn with an always-current "Live
# Preview" panel on top (see "_render_preview_panel"/"_clear_screen" in
# configure.sh). Driven via piped stdin -- read -p's prompt text isn't
# written anywhere when stdin isn't a tty (verified manually), so assertions
# only need to match the script's own echo output, not prompt text.

load 'test_helper'

setup() {
  CFG_TMPDIR="$(mktemp -d)"
  # HOME is isolated too (not just STATUSLINE_CONFIG_FILE): the Live Preview
  # panel shells out to the real statusline.sh. Pre-seeding a fresh ccusage
  # cache (see seed_ccusage_cache in test_helper.bash) guarantees read_cache
  # hits so statusline.sh's update_cache_background() never runs -- if it
  # did, its background `ccusage ...` subshell would inherit this process's
  # stdout/stderr and, if ccusage blocks on something (e.g. no network in a
  # sandboxed test environment -- reproduced manually: orphaned `ccusage`
  # processes kept running long after their invoking test was killed), bats'
  # `run` (a command-substitution capture) hangs waiting for that lingering
  # process to close the pipe, even though the foreground command already
  # finished. Plain foreground execution doesn't hit this (no EOF wait), so
  # it doesn't reproduce outside of `run` -- same isolation rule as
  # run_statusline_with_cache() in test_helper.bash.
  export HOME="$CFG_TMPDIR"
  export STATUSLINE_CONFIG_FILE="$CFG_TMPDIR/statusline.conf"
  seed_ccusage_cache "$CFG_TMPDIR"
}

teardown() {
  rm -rf "$CFG_TMPDIR"
}

menu_with_input() {
  # %b (not %s): expands the \n escapes embedded in the caller's plain
  # double-quoted "1\n1\n\n\n0\n" literals into real newlines for read -p.
  cd "$CFG_TMPDIR" && printf '%b' "$1" | bash "$CONFIGURE_SH"
}

@test "menu: running with no args shows the Live Preview panel and exits cleanly on 0" {
  run menu_with_input "0\n"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Live Preview"* ]]
  [[ "$output" == *"claude-statusline configure"* ]]
}

@test "menu: changing a value inside a category persists it and redraws the preview panel" {
  # top menu -> 1 (Colors & bar style) -> NO_COLOR=1 -> skip UNICODE -> skip
  # SEP_CHAR -> back at top menu -> 0 (exit)
  run menu_with_input "1\n1\n\n\n0\n"
  [ "$status" -eq 0 ]
  grep -q '^NO_COLOR=1$' "$STATUSLINE_CONFIG_FILE"
  # one screen before the edit, one right after the edit, one on return to
  # the top menu before exiting -- three redraws total.
  preview_count=$(grep -c "Live Preview" <<<"$output")
  [ "$preview_count" -ge 3 ]
}

@test "menu: an invalid value is skipped without an extra preview redraw" {
  # top menu -> 3 (Cost & context) -> STATUSLINE_HIDE_COST: skip -> STATUSLINE_MAX_CONTEXT: invalid -> back at top -> 0
  run menu_with_input "3\n\nnot-a-number\n0\n"
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid value, skipped"* ]]
  [ ! -f "$STATUSLINE_CONFIG_FILE" ]
  # only the initial screen and the final screen redraw -- no mid-group
  # redraw for the rejected value.
  preview_count=$(grep -c "Live Preview" <<<"$output")
  [ "$preview_count" -eq 2 ]
}

@test "menu: no clear-screen escape sequence is emitted when stdout is piped" {
  run menu_with_input "0\n"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033[2J'* ]]
}

@test "menu: cmd_preview's own output format is unaffected by the panel framing" {
  run configure_sh preview
  [ "$status" -eq 0 ]
  [[ "$output" != *"Live Preview"* ]]
  [[ "$output" != *"────"* ]]
}

configure_sh() {
  bash "$CONFIGURE_SH" "$@"
}
