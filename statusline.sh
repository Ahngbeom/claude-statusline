#!/bin/bash
# claude-statusline - A detailed statusline for Claude Code CLI
# Repository: https://github.com/ahngbeom/claude-statusline
# Version: 1.5.0
# License: MIT
#
# Features:
#   Line 1: Directory + Git branch (dirty */ahead-behind ↑↓) │ Model, CLI version, Output style
#   Line 2: Context usage (▰▱ bar) │ Session time + tokens │ Cache + Speed
#   Line 3: Daily │ Weekly │ Monthly usage and costs
#
# Requirements:
#   - jq (required): JSON parsing
#   - ccusage (recommended): Usage statistics via https://github.com/anthropics/ccusage
#
# Environment variables:
#   STATUSLINE_UNICODE=1        Use ▰▱ block chars (may misalign in some terminals)
#   NO_COLOR=1                  Disable ANSI colors
#   STATUSLINE_MAX_CONTEXT=<n>  Override JSONL-fallback context window size
#   STATUSLINE_HIDE_COST=1      Hide session cost (Line 2) and all of Line 3
#
# Performance notes (v1.1.0):
#   - All color codes are pre-computed variables (no subshell forks)
#   - jq calls are consolidated (single call per JSON source)
#   - to_epoch() uses GNU date first on Linux (no python3 fallback)
#   - npx synchronous call removed; cache miss shows placeholder
#   - Background ccusage calls run in parallel
#   - format_tokens/progress_bar use pure bash (no awk/tr)
#
# Changes (v1.3.0):
#   - context_window from stdin JSON (Claude Code >= v17.2.0) as primary context source
#   - Eliminates JSONL tail reading when context_window is available (file I/O removed)
#   - Session cost from stdin cost.total_cost_usd now displayed in Line 2
#   - transcript_path from stdin used in JSONL fallback (no manual path construction)
#   - Removed cost_per_hour dead code from blocks extraction
#
# Changes (v1.3.3):
#   - JSONL fallback now adds cache_creation_input_tokens to the context-used sum
#     (previously underestimated context after a fresh cache write)
#   - get_max_context() recognizes 1M-context model variants (e.g. "Opus 4.7 [1m]",
#     "Sonnet ... 1M context") and reports 1000000 instead of 200000
#
# Changes (v1.3.4):
#   - get_max_context() 1M-context pattern tightened to "[1m]"/"[1M]" (previous
#     bare "1M"/"1m" substrings could false-positive on unrelated model names)
#   - context_remaining_pct clamped to 0 (stdin/JSONL paths) to avoid negative
#     percentages when used tokens exceed the reported window size
#
# Changes (v1.3.5):
#   - Added bats-core test suite (tests/) and shellcheck CI, catching:
#     * get_max_context(): "Claude 3 Haiku" was shadowed by the generic
#       "Haiku" pattern above it and never matched (same bug class as 1M)
#     * unused session_txt/fmt_time_hm() dead code (an unnecessary date
#       subprocess fork on every render with an active ccusage session)
#   - STATUSLINE_MAX_CONTEXT=<tokens> env var overrides the JSONL-fallback
#     context window size, for models get_max_context() doesn't recognize yet
#   - Removed a redundant duplicate progress_bar() call for the session bar
#
# Changes (v1.4.0):
#   - Line 1 git branch now shows a dirty indicator ("*" when git status
#     --porcelain is non-empty) and ahead/behind counts vs. upstream
#     ("↑N"/"↓N", omitted when there's nothing to report or no upstream)
#   - STATUSLINE_HIDE_COST=1 hides session cost (Line 2) and all of Line 3
#     (Today/Week/Month), for orgs that don't want cost shown in the terminal
#
# Changes (v1.4.1):
#   - git branch/dirty/ahead-behind lookups and the JSONL context fallback are
#     now bounded by a 2s timeout (with_timeout helper), fixing intermittent
#     long statusline hangs caused by a stuck .git/index.lock or slow disk
#   - Reduced per-render subprocess forks: $OSTYPE-based platform detection,
#     printf|jq -> herestring, $(printf ...) -> printf -v, $(date +%s) ->
#     $EPOCHSECONDS (bash 5+), $(cat) -> read builtin, sed chain -> pure bash

# Changes (v1.5.0):
#   - stdin rate_limits (five_hour/seven_day server-measured usage % and
#     reset epoch, when Claude Code provides it) is now forwarded as-is to
#     ~/.claude/rate-limits-cache.json via the existing single jq call (no
#     extra subprocess fork) -- a side-channel for external tools (e.g.
#     cc-menutor's reset anchor auto-sync) to read the server's real 5h/7d
#     reset time instead of guessing from local activity gaps. Not rendered
#     by this script itself. Skipped (not overwritten) when rate_limits is
#     absent/empty this render, so a transient gap doesn't clobber a still-
#     good previous value. uninstall.sh / scripts/preuninstall.sh now also
#     remove this cache file.

# Reads all of stdin without forking `cat`: read -d '' consumes up to EOF
# (no NUL byte appears in JSON input) and populates $input directly.
IFS= read -r -d '' input

# ---- pre-computed color variables (no subshell forks) ----
if [ -z "$NO_COLOR" ]; then
  _dir=$'\033[38;5;117m'      # sky blue
  _model=$'\033[38;5;147m'    # light purple
  _version=$'\033[38;5;180m'  # soft yellow
  _ccver=$'\033[38;5;249m'    # light gray
  _style=$'\033[38;5;245m'    # gray
  _git=$'\033[38;5;150m'      # soft green
  _usage=$'\033[38;5;189m'    # lavender
  _cost=$'\033[38;5;222m'     # light gold
  _burn=$'\033[38;5;220m'     # bright gold
  _cache=$'\033[38;5;120m'    # light green
  _today=$'\033[38;5;153m'    # light blue
  _week=$'\033[38;5;183m'     # light pink
  _month=$'\033[38;5;216m'    # light coral
  _ctx=$'\033[1;37m'          # default white (context - updated dynamically)
  _sep=$'\033[38;5;240m'      # dim gray separator
  _rst=$'\033[0m'
  _mem_ok=$'\033[38;5;120m'   # green (< 60%)
  _mem_warn=$'\033[38;5;220m' # yellow (≥ 60%)
  _mem_crit=$'\033[38;5;196m' # red (≥ 80%)
else
  _dir="" _model="" _version="" _ccver="" _style="" _git=""
  _usage="" _cost="" _burn="" _cache="" _today="" _week="" _month=""
  _ctx="" _sep="" _rst=""
  _mem_ok="" _mem_warn="" _mem_crit=""
fi

# ---- progress bar characters (ASCII-safe default) ----
if [ -n "$STATUSLINE_UNICODE" ]; then
  _bar_fill="▰"; _bar_empty="▱"
else
  _bar_fill="="; _bar_empty="-"
fi

# ---- time helpers ----
# $OSTYPE is a bash builtin (zero fork) and never changes for the life of
# the machine, so for the two officially supported platforms we pick the
# date/stat flavor directly instead of forking date/stat on every single
# render just to probe which syntax they understand. Uncommon platforms
# (freebsd, msys, cygwin, ...) still get the old probe-based detection,
# since we can't assume GNU/BSD semantics there.
case "$OSTYPE" in
  darwin*)
    if command -v gdate >/dev/null 2>&1; then
      to_epoch() { gdate -d "$1" +%s; }
    else
      to_epoch() { date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "${1/Z/+0000}" +%s; }
    fi
    _file_mtime() { stat -f %m "$1" 2>/dev/null; }
    ;;
  linux*)
    to_epoch() { date -d "$1" +%s; }
    _file_mtime() { stat -c %Y "$1" 2>/dev/null; }
    ;;
  *)
    if date -d "2024-01-01T00:00:00Z" +%s >/dev/null 2>&1; then
      to_epoch() { date -d "$1" +%s; }
    elif command -v gdate >/dev/null 2>&1 && gdate -d "2024-01-01T00:00:00Z" +%s >/dev/null 2>&1; then
      to_epoch() { gdate -d "$1" +%s; }
    elif date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "2024-01-01T00:00:00+0000" +%s >/dev/null 2>&1; then
      to_epoch() { date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "${1/Z/+0000}" +%s; }
    else
      to_epoch() { python3 -c "import sys,datetime; s=sys.argv[1].replace('Z','+00:00'); print(int(datetime.datetime.fromisoformat(s).timestamp()))" "$1"; }
    fi
    if stat -f %m / >/dev/null 2>&1; then
      _file_mtime() { stat -f %m "$1" 2>/dev/null; }
    else
      _file_mtime() { stat -c %Y "$1" 2>/dev/null; }
    fi
    ;;
esac

# $EPOCHSECONDS (bash 5.0+ builtin, zero fork) is used inline as
# ${EPOCHSECONDS:-$(date +%s)} everywhere "current epoch" is needed, so
# `date` only forks as a fallback. macOS's system /bin/bash is permanently
# 3.2.57 (Apple won't ship a GPLv3 bash), so this only pays off on Linux/WSL
# where /bin/bash is typically 5.x; it's a no-op regression there since the
# fallback is identical to the prior unconditional `date +%s` call.

# ---- subprocess timeout guard ----
# Bounds worst-case wall time of external calls (git, jq-on-JSONL) that can
# stall on large/contended repos or slow disks, so a single slow subprocess
# never blocks the whole statusline render indefinitely.
_timeout_bin=""
if command -v timeout >/dev/null 2>&1; then
  _timeout_bin="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  _timeout_bin="gtimeout"   # macOS + `brew install coreutils`
fi

with_timeout() {
  local secs="$1"; shift
  if [ -n "$_timeout_bin" ]; then
    "$_timeout_bin" "$secs" "$@"
    return
  fi
  # Neither timeout nor gtimeout available: pure-bash fallback.
  "$@" &
  local pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null ) &
  local watcher=$!
  wait "$pid" 2>/dev/null
  local status=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  return "$status"
}

# ---- pure bash progress bar (no tr subprocess) ----
progress_bar() {
  local pct="${1:-0}" width="${2:-10}"
  [[ "$pct" =~ ^[0-9]+$ ]] || pct=0; ((pct<0))&&pct=0; ((pct>100))&&pct=100
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar="" i
  for ((i=0; i<filled; i++)); do bar+="$_bar_fill"; done
  for ((i=0; i<empty; i++)); do bar+="$_bar_empty"; done
  printf '%s' "$bar"
}

# ---- pure bash format_tokens (no awk subprocess) ----
format_tokens() {
  local num="$1"
  if [[ "$num" =~ ^[0-9]+$ ]]; then
    if [ "$num" -ge 1000000 ]; then
      local whole=$((num / 1000000)) frac=$(( (num % 1000000) / 10000 ))
      printf '%d.%02dM' "$whole" "$frac"
    elif [ "$num" -ge 1000 ]; then
      local whole=$((num / 1000)) frac=$(( (num % 1000) / 100 ))
      printf '%d.%01dK' "$whole" "$frac"
    else
      printf '%s' "$num"
    fi
  else
    printf '%s' "$num"
  fi
}

num_or_zero() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo 0; }

# ---- memory usage percentage ----
get_mem_usage() {
  # macOS: vm_stat + sysctl (matches Activity Monitor's "Memory Used")
  if command -v vm_stat >/dev/null 2>&1 && command -v sysctl >/dev/null 2>&1; then
    local total_bytes page_size total_pages
    { read -r total_bytes; read -r page_size; } < <(sysctl -n hw.memsize hw.pagesize 2>/dev/null)
    if [[ "$total_bytes" =~ ^[0-9]+$ ]] && [[ "$page_size" =~ ^[0-9]+$ ]] && [ "$page_size" -gt 0 ]; then
      total_pages=$((total_bytes / page_size))
      # Single awk call: extract free + speculative + file-backed (= available)
      local used_pct
      used_pct=$(vm_stat 2>/dev/null | awk -v tp="$total_pages" '
        /Pages free:/        { f=$NF+0 }
        /Pages speculative:/ { s=$NF+0 }
        /File-backed pages:/ { fb=$NF+0 }
        END { if(tp>0) printf "%d", (tp-f-s-fb)*100/tp }
      ')
      if [[ "$used_pct" =~ ^[0-9]+$ ]]; then
        echo "$used_pct"
        return
      fi
    fi
  fi
  # Linux: /proc/meminfo
  if [ -f /proc/meminfo ]; then
    local total avail
    total=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
    if [[ "$total" =~ ^[0-9]+$ ]] && [[ "$avail" =~ ^[0-9]+$ ]] && [ "$total" -gt 0 ]; then
      echo $(( (total - avail) * 100 / total ))
      return
    fi
  fi
  echo ""
}

# ---- cache helpers for ccusage data ----
CACHE_FILE="$HOME/.claude/stats-cache.json"
LOCK_DIR="$CACHE_FILE.lock"
CACHE_TTL=60  # 60 seconds

cleanup_stale_lock() {
  [ -d "$LOCK_DIR" ] || return 0
  local lock_mtime lock_age
  lock_mtime=$(_file_mtime "$LOCK_DIR")
  [ -n "$lock_mtime" ] || return 0  # stat 실패 시 안전하게 skip
  lock_age=$(( ${EPOCHSECONDS:-$(date +%s)} - lock_mtime ))
  [ "$lock_age" -gt 120 ] && rm -rf "$LOCK_DIR"
}

read_cache() {
  if [ -f "$CACHE_FILE" ]; then
    local file_mtime file_age
    file_mtime=$(_file_mtime "$CACHE_FILE")
    [ -n "$file_mtime" ] || return 1  # stat 실패 → 캐시 무효
    file_age=$(( ${EPOCHSECONDS:-$(date +%s)} - file_mtime ))
    if [ "$file_age" -lt "$CACHE_TTL" ]; then
      cat "$CACHE_FILE"
      return 0
    fi
  fi
  return 1
}

# Resolve ccusage command once
_ccusage_cmd=""
if command -v ccusage >/dev/null 2>&1; then
  _ccusage_cmd="ccusage"
elif command -v npx >/dev/null 2>&1; then
  _ccusage_cmd="npx --prefer-offline ccusage@latest"
fi

update_cache_background() {
  [ -z "$_ccusage_cmd" ] && return
  (
    # Exclusive lock: skip silently if another update is in progress
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0

    local tmpdir _tmp_cache=""
    tmpdir=$(mktemp -d) || { rm -rf "$LOCK_DIR"; exit 1; }
    trap 'rm -rf "$tmpdir" "$LOCK_DIR" ${_tmp_cache:+"$_tmp_cache"}' EXIT

    local today_date
    today_date=$(date +%Y%m%d)

    # Optional timeout (reuses the timeout/gtimeout resolution from above)
    local _to=""
    [ -n "$_timeout_bin" ] && _to="$_timeout_bin 30"

    # shellcheck disable=SC2086 # $_to/$_ccusage_cmd hold multi-word commands; intentionally unquoted
    $_to $_ccusage_cmd blocks --json  >"$tmpdir/blocks"  2>/dev/null &
    # shellcheck disable=SC2086
    $_to $_ccusage_cmd daily  --json --since "$today_date" >"$tmpdir/daily"  2>/dev/null &
    # shellcheck disable=SC2086
    $_to $_ccusage_cmd weekly --json >"$tmpdir/weekly"  2>/dev/null &
    # shellcheck disable=SC2086
    $_to $_ccusage_cmd monthly --json >"$tmpdir/monthly" 2>/dev/null &
    wait

    local blocks daily weekly monthly
    blocks=$(<"$tmpdir/blocks")
    [ -z "$blocks" ] && exit 0

    daily=$(<"$tmpdir/daily")
    weekly=$(<"$tmpdir/weekly")
    monthly=$(<"$tmpdir/monthly")

    # Atomic write: temp file in same directory ensures rename(2) atomicity
    _tmp_cache=$(mktemp "$CACHE_FILE.XXXXXX")
    if jq -n \
      --argjson ts "${EPOCHSECONDS:-$(date +%s)}" \
      --argjson blocks "$blocks" \
      --argjson daily "${daily:-null}" \
      --argjson weekly "${weekly:-null}" \
      --argjson monthly "${monthly:-null}" \
      '{timestamp: $ts, blocks: $blocks, daily: $daily, weekly: $weekly, monthly: $monthly}' \
      > "$_tmp_cache" 2>/dev/null; then
      mv "$_tmp_cache" "$CACHE_FILE"
      _tmp_cache=""  # mv 성공 후 trap에서 삭제 불필요
    fi
  ) &
}

# ---- parse input with single jq call ----
if command -v jq >/dev/null 2>&1; then
  _has_jq=1
  IFS=$'\x1f' read -r current_dir model_name session_id cc_version output_style \
    ctx_input_tokens ctx_window_size \
    session_cost_usd transcript_path rate_limits_json < <(
    jq -r '[
      (.workspace.current_dir // .cwd // "unknown"),
      (.model.display_name // "Claude"),
      (.session_id // ""),
      (.version // ""),
      (.output_style.name // ""),
      (.context_window.total_input_tokens // ""),
      (.context_window.context_window_size // ""),
      (.cost.total_cost_usd // ""),
      (.transcript_path // ""),
      (.rate_limits // {} | tostring)
    ] | join("\u001f")' 2>/dev/null <<< "$input"
  )
  current_dir="${current_dir//$HOME/~}"
else
  _has_jq=0
  current_dir="unknown"
  model_name="Claude"
  session_id=""
  cc_version=""
  output_style=""
  rate_limits_json=""
fi

# ---- rate limits cache (side-channel output for external consumers, e.g.
# cc-menutor's reset anchor auto-sync) ----
# Claude Code passes rate_limits.five_hour/seven_day (server-measured usage %
# and reset epoch) to statusLine scripts but never persists it itself. We
# forward the object as-is (no reshaping needed -- the consumer's schema
# matches Claude Code's stdin field names 1:1) so any tool can read the
# server's real reset time instead of guessing from local activity gaps.
# Skipped (not overwritten) when rate_limits is absent/empty this render
# (e.g. API-key users, before the session's first API response, or no jq) --
# staleness is the consumer's job (it checks resets_at against now), so an
# absent render shouldn't blow away a still-good previous value.
if [ -n "$rate_limits_json" ] && [ "$rate_limits_json" != "{}" ] && [ "$rate_limits_json" != "null" ]; then
  _rl_cache="$HOME/.claude/rate-limits-cache.json"
  _tmp_rl=$(mktemp "$_rl_cache.XXXXXX" 2>/dev/null)
  if [ -n "$_tmp_rl" ] && printf '%s' "$rate_limits_json" > "$_tmp_rl" 2>/dev/null; then
    mv "$_tmp_rl" "$_rl_cache"
  else
    rm -f "$_tmp_rl"
  fi
fi

# ---- git ----
# All git plumbing is gathered in one function and run under a single
# timeout, instead of guarding each call, to avoid multiplying subprocess
# count. A stuck index.lock / slow filesystem degrades to no branch shown
# (same graceful-degradation contract as the rest of this section).
_gather_git_info() {
  git rev-parse --git-dir >/dev/null 2>&1 || return
  local branch dirty="" behind="" ahead=""
  branch=$(git branch --show-current 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  [ -n "$branch" ] && [ -n "$(git status --porcelain 2>/dev/null)" ] && dirty="1"
  read -r behind ahead < <(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
  printf '%s\x1f%s\x1f%s\x1f%s' "$branch" "$dirty" "$behind" "$ahead"
}
# Real `timeout`/`gtimeout` exec their target directly, so a plain shell
# function name isn't runnable under it — route through `bash -c` with the
# function exported so both the real-binary and pure-bash fallback paths
# in with_timeout() can find and run it.
export -f _gather_git_info

git_branch=""
IFS=$'\x1f' read -r _gb _gdirty git_behind git_ahead < <(with_timeout 2 bash -c _gather_git_info)
if [ -n "$_gb" ]; then
  git_branch="$_gb"
  [ -n "$_gdirty" ] && git_branch="${git_branch}*"
  git_ahead_behind=""
  [[ "$git_ahead" =~ ^[0-9]+$ ]] && [ "$git_ahead" -gt 0 ] && git_ahead_behind="${git_ahead_behind}↑${git_ahead}"
  [[ "$git_behind" =~ ^[0-9]+$ ]] && [ "$git_behind" -gt 0 ] && git_ahead_behind="${git_ahead_behind}↓${git_behind}"
  [ -n "$git_ahead_behind" ] && git_branch="${git_branch} ${git_ahead_behind}"
fi

# ---- memory usage ----
mem_pct=$(get_mem_usage)

# ---- context window calculation ----
context_pct=""
context_used_tokens=""
context_max_tokens=""
context_remaining_pct=""

get_max_context() {
  case "$1" in
    *"[1m]"*|*"[1M]"*|*"1M context"*|*"1m context"*) echo "1000000" ;;
    *"Opus 4"*|*"opus 4"*|*"Opus"*|*"opus"*)       echo "200000" ;;
    *"Sonnet 4"*|*"sonnet 4"*|*"Sonnet 3.5"*|*"sonnet 3.5"*|*"Sonnet"*|*"sonnet"*) echo "200000" ;;
    *"Claude 3 Haiku"*|*"claude 3 haiku"*) echo "100000" ;;
    *"Haiku 3.5"*|*"haiku 3.5"*|*"Haiku 4"*|*"haiku 4"*|*"Haiku"*|*"haiku"*)       echo "200000" ;;
    *) echo "200000" ;;
  esac
}

_set_context_color() {
  local remaining_pct="$1"
  [ -n "$NO_COLOR" ] && return
  if [ "$remaining_pct" -le 20 ]; then
    _ctx=$'\033[38;5;203m'    # coral red
  elif [ "$remaining_pct" -le 40 ]; then
    _ctx=$'\033[38;5;215m'    # peach
  else
    _ctx=$'\033[38;5;158m'    # mint green
  fi
}

if [[ "$ctx_window_size" =~ ^[0-9]+$ ]] && [ "$ctx_window_size" -gt 0 ] 2>/dev/null; then
  # Primary: use context_window from stdin (Claude Code >= v17.2.0)
  ctx_tokens="${ctx_input_tokens:-0}"
  if [[ "$ctx_tokens" =~ ^[0-9]+$ ]]; then
    context_used_tokens="$ctx_tokens"
    context_max_tokens="$ctx_window_size"
    context_used_pct=$(( ctx_tokens * 100 / ctx_window_size ))
    context_remaining_pct=$(( 100 - context_used_pct ))
    (( context_remaining_pct < 0 )) && context_remaining_pct=0
    _set_context_color "$context_remaining_pct"
    context_pct="${context_remaining_pct}%"
  fi
elif [ -n "$session_id" ] && [ "$_has_jq" -eq 1 ]; then
  # Fallback: read session JSONL (older Claude Code without context_window)
  if [[ "$STATUSLINE_MAX_CONTEXT" =~ ^[0-9]+$ ]]; then
    MAX_CONTEXT="$STATUSLINE_MAX_CONTEXT"
  else
    MAX_CONTEXT=$(get_max_context "$model_name")
  fi

  # Prefer transcript_path from stdin; fall back to manual path construction
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    session_file="$transcript_path"
  else
    project_dir="${current_dir//\~/$HOME}"
    project_dir="${project_dir//\//-}"
    project_dir="${project_dir#-}"
    session_file="$HOME/.claude/projects/-${project_dir}/${session_id}.jsonl"
  fi

  if [ -f "$session_file" ]; then
    # shellcheck disable=SC2016 # single quotes intentional: $1 expands inside the inner `bash -c`, not here
    latest_tokens=$(with_timeout 2 bash -c \
      'tail -20 "$1" | jq -r "select(.message.usage) | .message.usage | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))" 2>/dev/null | tail -1' \
      _ "$session_file")

    if [ -n "$latest_tokens" ] && [ "$latest_tokens" -gt 0 ] 2>/dev/null; then
      context_used_tokens="$latest_tokens"
      context_max_tokens="$MAX_CONTEXT"
      context_used_pct=$(( latest_tokens * 100 / MAX_CONTEXT ))
      context_remaining_pct=$(( 100 - context_used_pct ))
      (( context_remaining_pct < 0 )) && context_remaining_pct=0
      _set_context_color "$context_remaining_pct"
      context_pct="${context_remaining_pct}%"
    fi
  fi
fi

# ---- ccusage integration ----
session_pct=0; session_bar=""
cost_usd=""; tpm=""; tot_tokens=""
today_tokens=""; today_cost=""
week_tokens=""; week_cost=""
month_tokens=""; month_cost=""
cache_hit_rate=""
rh=""; rm_val=""

if [ "$_has_jq" -eq 1 ]; then
  cached_data=""
  cleanup_stale_lock
  if cached_data=$(read_cache); then
    # Cache hit - extract all fields with single jq call
    IFS=$'\t' read -r blocks_output daily_output weekly_output monthly_output < <(
      jq -r '[
        (.blocks | tostring),
        (.daily | tostring),
        (.weekly | tostring),
        (.monthly | tostring)
      ] | @tsv' 2>/dev/null <<< "$cached_data"
    )
  else
    # Cache miss - NO synchronous npx call; trigger background update only
    blocks_output=""
    daily_output=""
    weekly_output=""
    monthly_output=""
    update_cache_background
  fi

  if [ -n "$blocks_output" ] && [ "$blocks_output" != "null" ]; then
    # Extract active block and all fields with single jq call
    IFS=$'\t' read -r cost_usd tot_tokens tpm cache_read cache_creation reset_time_str start_time_str < <(
      jq -r '
        (.blocks[] | select(.isActive == true)) |
        [
          (.costUSD // ""),
          (.totalTokens // ""),
          (.burnRate.tokensPerMinute // ""),
          (.tokenCounts.cacheReadInputTokens // 0),
          (.tokenCounts.cacheCreationInputTokens // 0),
          (.usageLimitResetTime // .endTime // ""),
          (.startTime // "")
        ] | @tsv' 2>/dev/null <<< "$blocks_output" | head -n1
    )

    # Cache hit rate calculation
    cache_read=$(num_or_zero "$cache_read")
    cache_creation=$(num_or_zero "$cache_creation")
    total_cache=$((cache_read + cache_creation))
    if [ "$total_cache" -gt 0 ]; then
      cache_hit_rate=$((cache_read * 100 / total_cache))
    fi

    # Session time calculation
    if [ -n "$reset_time_str" ] && [ -n "$start_time_str" ]; then
      start_sec=$(to_epoch "$start_time_str"); end_sec=$(to_epoch "$reset_time_str"); now_sec=${EPOCHSECONDS:-$(date +%s)}
      total=$(( end_sec - start_sec )); (( total<1 )) && total=1
      elapsed=$(( now_sec - start_sec )); (( elapsed<0 ))&&elapsed=0; (( elapsed>total ))&&elapsed=$total
      session_pct=$(( elapsed * 100 / total ))
      remaining=$(( end_sec - now_sec )); (( remaining<0 )) && remaining=0
      rh=$(( remaining / 3600 )); rm_val=$(( (remaining % 3600) / 60 ))
      session_bar=$(progress_bar "$session_pct" 10)
    fi
  fi

  # Daily/Weekly/Monthly - extract with single jq calls
  if [ -n "$daily_output" ] && [ "$daily_output" != "null" ]; then
    IFS=$'\t' read -r today_tokens today_cost < <(
      jq -r '[(.daily[0].totalTokens // ""), (.daily[0].totalCost // "")] | @tsv' 2>/dev/null <<< "$daily_output"
    )
  fi

  if [ -n "$weekly_output" ] && [ "$weekly_output" != "null" ]; then
    IFS=$'\t' read -r week_tokens week_cost < <(
      jq -r '[(.weekly[-1].totalTokens // ""), (.weekly[-1].totalCost // "")] | @tsv' 2>/dev/null <<< "$weekly_output"
    )
  fi

  if [ -n "$monthly_output" ] && [ "$monthly_output" != "null" ]; then
    IFS=$'\t' read -r month_tokens month_cost < <(
      jq -r '[(.monthly[-1].totalTokens // ""), (.monthly[-1].totalCost // "")] | @tsv' 2>/dev/null <<< "$monthly_output"
    )
  fi
fi

# ---- session color (computed after session_pct is known) ----
_session=""
if [ -z "$NO_COLOR" ]; then
  rem_pct=$(( 100 - session_pct ))
  if   (( rem_pct <= 10 )); then _session=$'\033[38;5;210m'   # light pink
  elif (( rem_pct <= 25 )); then _session=$'\033[38;5;228m'   # light yellow
  else                           _session=$'\033[38;5;194m'   # light green
  fi
fi

# ---- render statusline ----
# Line 1: 📂 dir  branch │ model  cc_ver  style
printf '📂 %s%s%s' "$_dir" "$current_dir" "$_rst"
if [ -n "$git_branch" ]; then
  printf '  %s%s%s' "$_git" "$git_branch" "$_rst"
fi
printf '  %s│%s' "$_sep" "$_rst"
printf ' %s%s%s' "$_model" "$model_name" "$_rst"
if [ -n "$cc_version" ] && [ "$cc_version" != "null" ]; then
  printf '  %sv%s%s' "$_ccver" "$cc_version" "$_rst"
fi
if [ -n "$output_style" ] && [ "$output_style" != "null" ]; then
  printf '  %s%s%s' "$_style" "$output_style" "$_rst"
fi
if [[ "$mem_pct" =~ ^[0-9]+$ ]]; then
  if [ "$mem_pct" -ge 80 ]; then
    _mem_color="$_mem_crit"
  elif [ "$mem_pct" -ge 60 ]; then
    _mem_color="$_mem_warn"
  else
    _mem_color="$_mem_ok"
  fi
  printf '  %s│%s %s💻 Mem %d%%%s' "$_sep" "$_rst" "$_mem_color" "$mem_pct" "$_rst"
fi

# Line 2: 🧠 Context ... │ Session ... │ 🗄 cache  speed
# Build each section independently, then join with │ separators
ctx_part=""
if [ -n "$context_pct" ] && [ -n "$context_used_tokens" ]; then
  context_bar=$(progress_bar "$context_remaining_pct" 20)
  used_formatted=$(format_tokens "$context_used_tokens")
  max_formatted=$(format_tokens "$context_max_tokens")
  ctx_part="🧠 ${_ctx}Context ${used_formatted}/${max_formatted} ${context_bar} ${context_remaining_pct}%${_rst}"
else
  ctx_part="🧠 ${_ctx}Context ···${_rst}"
fi

sess_part=""
if [ -n "$tot_tokens" ] && [[ "$tot_tokens" =~ ^[0-9]+$ ]]; then
  tot_formatted=$(format_tokens "$tot_tokens")
  # Session cost: prefer stdin cost.total_cost_usd (real-time), fallback to ccusage blocks cost_usd
  _sess_cost=""
  if [ -z "$STATUSLINE_HIDE_COST" ]; then
    if [[ "$session_cost_usd" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      printf -v _sess_cost_num '$%.2f' "$session_cost_usd"
      _sess_cost=" $_sess_cost_num"
    elif [[ "$cost_usd" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      printf -v _sess_cost_num '$%.2f' "$cost_usd"
      _sess_cost=" $_sess_cost_num"
    fi
  fi
  if [ -n "$rh" ] || [ -n "$rm_val" ]; then
    sess_part="${_session}Session ${tot_formatted}${_sess_cost}  ${rh}h ${rm_val}m ${session_bar}${_rst}"
  else
    sess_part="${_session}Session ${tot_formatted}${_sess_cost}${_rst}"
  fi
fi

meta_part=""
if [ -n "$cache_hit_rate" ] && [[ "$cache_hit_rate" =~ ^[0-9]+$ ]]; then
  meta_part="🗄 ${_cache}${cache_hit_rate}%${_rst}"
fi
if [ -n "$tpm" ] && [[ "$tpm" =~ ^[0-9.]+$ ]]; then
  printf -v tpm_int '%.0f' "$tpm"
  tpm_formatted=$(format_tokens "$tpm_int")
  if [ -n "$meta_part" ]; then
    meta_part="${meta_part}  ${_cache}${tpm_formatted}/m${_rst}"
  else
    meta_part="${_cache}${tpm_formatted}/m${_rst}"
  fi
fi

# Assemble line2
line2="$ctx_part"
if [ -n "$sess_part" ]; then
  line2="${line2}  ${_sep}│${_rst} ${sess_part}"
fi
if [ -n "$meta_part" ]; then
  line2="${line2}  ${_sep}│${_rst} ${meta_part}"
fi

# Line 3: 💰 Today ... │ Week ... │ Month ...
line3=""
if [ -z "$STATUSLINE_HIDE_COST" ]; then
  if [ -n "$today_tokens" ] && [[ "$today_tokens" =~ ^[0-9]+$ ]]; then
    today_tokens_formatted=$(format_tokens "$today_tokens")
    if [ -n "$today_cost" ] && [[ "$today_cost" =~ ^[0-9.]+$ ]]; then
      printf -v today_cost_formatted '%.2f' "$today_cost"
      line3="💰 ${_today}Today ${today_tokens_formatted}  \$${today_cost_formatted}${_rst}"
    else
      line3="💰 ${_today}Today ${today_tokens_formatted}${_rst}"
    fi
  fi

  if [ -n "$week_tokens" ] && [[ "$week_tokens" =~ ^[0-9]+$ ]]; then
    week_tokens_formatted=$(format_tokens "$week_tokens")
    if [ -n "$week_cost" ] && [[ "$week_cost" =~ ^[0-9.]+$ ]]; then
      printf -v week_cost_formatted '%.2f' "$week_cost"
      week_part="${_week}Week ${week_tokens_formatted}  \$${week_cost_formatted}${_rst}"
    else
      week_part="${_week}Week ${week_tokens_formatted}${_rst}"
    fi
    if [ -n "$line3" ]; then line3="${line3}  ${_sep}│${_rst} ${week_part}"; else line3="${week_part}"; fi
  fi

  if [ -n "$month_tokens" ] && [[ "$month_tokens" =~ ^[0-9]+$ ]]; then
    month_tokens_formatted=$(format_tokens "$month_tokens")
    if [ -n "$month_cost" ] && [[ "$month_cost" =~ ^[0-9.]+$ ]]; then
      printf -v month_cost_formatted '%.2f' "$month_cost"
      month_part="${_month}Month ${month_tokens_formatted}  \$${month_cost_formatted}${_rst}"
    else
      month_part="${_month}Month ${month_tokens_formatted}${_rst}"
    fi
    if [ -n "$line3" ]; then line3="${line3}  ${_sep}│${_rst} ${month_part}"; else line3="${month_part}"; fi
  fi
fi

# Print lines
if [ -n "$line2" ]; then
  printf '\n%s' "$line2"
fi
if [ -n "$line3" ]; then
  printf '\n%s' "$line3"
fi
printf '\n'
