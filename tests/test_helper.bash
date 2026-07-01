#!/usr/bin/env bash
# Shared helpers for statusline.sh bats tests.

STATUSLINE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/statusline.sh"
# shellcheck disable=SC2034 # used by .bats files that `load` this helper
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures" && pwd)"

# Sources a single top-level function definition from statusline.sh into the
# current shell, without executing the script's top-level logic (which
# blocks reading stdin). Only works for functions whose closing brace sits
# alone on its own line — true for every helper function in statusline.sh.
load_fn() {
  eval "$(sed -n '/^'"${1}"'() {$/,/^}$/p' "$STATUSLINE_SH")"
}

# Runs statusline.sh as a real subprocess with an isolated HOME (so the
# developer's real ~/.claude/stats-cache.json is never touched) and a
# non-git cwd (so git branch detection is deterministic). Always sets
# NO_COLOR=1 so assertions don't need to match ANSI escape codes.
run_statusline() {
  local json="$1"
  local tmp_home
  tmp_home="$(mktemp -d)"
  ( cd "$tmp_home" && printf '%s' "$json" | HOME="$tmp_home" NO_COLOR=1 bash "$STATUSLINE_SH" )
  local status=$?
  rm -rf "$tmp_home"
  return "$status"
}

# Replaces the volatile "Mem NN%" segment (real system memory usage) with a
# fixed placeholder so golden-output assertions can use exact string equality.
normalize_mem() {
  sed -E 's/Mem [0-9]+%/Mem NN%/' <<<"$1"
}
