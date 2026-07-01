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
# NO_COLOR=1 so assertions don't need to match ANSI escape codes. Extra
# NAME=value arguments (e.g. STATUSLINE_MAX_CONTEXT=1000000) are exported
# into the subprocess environment.
run_statusline() {
  local json="$1"; shift
  local tmp_home
  tmp_home="$(mktemp -d)"
  ( cd "$tmp_home" && printf '%s' "$json" | HOME="$tmp_home" NO_COLOR=1 env "$@" bash "$STATUSLINE_SH" )
  local status=$?
  rm -rf "$tmp_home"
  return "$status"
}

# Like run_statusline, but runs inside a caller-provided directory instead of
# a fresh empty tmpdir. Used by git-status tests that need a real repo (HOME
# is still isolated so ccusage cache/background jobs stay sandboxed).
run_statusline_in() {
  local dir="$1" json="$2"; shift 2
  local tmp_home
  tmp_home="$(mktemp -d)"
  ( cd "$dir" && printf '%s' "$json" | HOME="$tmp_home" NO_COLOR=1 env "$@" bash "$STATUSLINE_SH" )
  local status=$?
  rm -rf "$tmp_home"
  return "$status"
}

# Replaces the volatile "Mem NN%" segment (real system memory usage) with a
# fixed placeholder so golden-output assertions can use exact string equality.
normalize_mem() {
  sed -E 's/Mem [0-9]+%/Mem NN%/' <<<"$1"
}

# Seeds $1/.claude/stats-cache.json with a synthetic active ccusage block
# plus daily/weekly/monthly totals, so golden tests can exercise the
# Session/Line 3 rendering paths without a real ccusage install.
seed_ccusage_cache() {
  local home_dir="$1"
  mkdir -p "$home_dir/.claude"
  local now start end start_iso end_iso
  now=$(date +%s)
  start=$(( now - 3600 ))
  end=$(( now + 10800 ))
  start_iso=$(date -u -r "$start" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "@$start" +"%Y-%m-%dT%H:%M:%SZ")
  end_iso=$(date -u -r "$end" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "@$end" +"%Y-%m-%dT%H:%M:%SZ")
  cat >"$home_dir/.claude/stats-cache.json" <<EOF
{"timestamp": $now, "blocks": {"blocks": [{"isActive": true, "costUSD": 12.34, "totalTokens": 500000, "burnRate": {"tokensPerMinute": 1000}, "tokenCounts": {"cacheReadInputTokens": 800, "cacheCreationInputTokens": 200}, "startTime": "$start_iso", "usageLimitResetTime": "$end_iso"}]}, "daily": {"daily": [{"totalTokens": 900000, "totalCost": 4.32}]}, "weekly": {"weekly": [{"totalTokens": 2000000, "totalCost": 9.5}]}, "monthly": {"monthly": [{"totalTokens": 5000000, "totalCost": 22.1}]}}
EOF
}

# Like run_statusline, but pre-seeds the isolated HOME with a synthetic
# ccusage cache (see seed_ccusage_cache) so Session/Line 3 render.
run_statusline_with_cache() {
  local json="$1"; shift
  local tmp_home
  tmp_home="$(mktemp -d)"
  seed_ccusage_cache "$tmp_home"
  ( cd "$tmp_home" && printf '%s' "$json" | HOME="$tmp_home" NO_COLOR=1 env "$@" bash "$STATUSLINE_SH" )
  local status=$?
  rm -rf "$tmp_home"
  return "$status"
}
