#!/bin/bash
# claude-statusline - A detailed statusline for Claude Code CLI
# Repository: https://github.com/ahngbeom/claude-statusline
# Version: 1.1.0
# License: MIT
#
# Features:
#   Line 1: Directory + Git branch │ Model, CLI version, Output style
#   Line 2: Context usage (▰▱ bar) │ Session time + tokens │ Cache + Speed
#   Line 3: Daily │ Weekly │ Monthly usage and costs
#
# Requirements:
#   - jq (required): JSON parsing
#   - ccusage (recommended): Usage statistics via https://github.com/anthropics/ccusage
#
# Performance notes (v1.1.0):
#   - All color codes are pre-computed variables (no subshell forks)
#   - jq calls are consolidated (single call per JSON source)
#   - to_epoch() uses GNU date first on Linux (no python3 fallback)
#   - npx synchronous call removed; cache miss shows placeholder
#   - Background ccusage calls run in parallel
#   - format_tokens/progress_bar use pure bash (no awk/tr)

input=$(cat)

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
else
  _dir="" _model="" _version="" _ccver="" _style="" _git=""
  _usage="" _cost="" _burn="" _cache="" _today="" _week="" _month=""
  _ctx="" _sep="" _rst=""
fi

# ---- time helpers ----
# Platform detection for to_epoch (one-time cost at startup, avoids per-call fork failures)
if date -d "2024-01-01T00:00:00Z" +%s >/dev/null 2>&1; then
  to_epoch() { date -d "$1" +%s; }
elif command -v gdate >/dev/null 2>&1 && gdate -d "2024-01-01T00:00:00Z" +%s >/dev/null 2>&1; then
  to_epoch() { gdate -d "$1" +%s; }
elif date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "2024-01-01T00:00:00+0000" +%s >/dev/null 2>&1; then
  to_epoch() { date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "${1/Z/+0000}" +%s; }
else
  to_epoch() { python3 -c "import sys,datetime; s=sys.argv[1].replace('Z','+00:00'); print(int(datetime.datetime.fromisoformat(s).timestamp()))" "$1"; }
fi

fmt_time_hm() {
  local epoch="$1"
  if date -r 0 +%s >/dev/null 2>&1; then date -r "$epoch" +"%H:%M"; else date -d "@$epoch" +"%H:%M"; fi
}

# ---- pure bash progress bar (no tr subprocess) ----
progress_bar() {
  local pct="${1:-0}" width="${2:-10}"
  [[ "$pct" =~ ^[0-9]+$ ]] || pct=0; ((pct<0))&&pct=0; ((pct>100))&&pct=100
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar="" i
  for ((i=0; i<filled; i++)); do bar+="▰"; done
  for ((i=0; i<empty; i++)); do bar+="▱"; done
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

# ---- cache helpers for ccusage data ----
CACHE_FILE="$HOME/.claude/stats-cache.json"
LOCK_DIR="$CACHE_FILE.lock"
CACHE_TTL=60  # 60 seconds

read_cache() {
  # Clean up stale lock (> 2 minutes old) left by crashed processes
  if [ -d "$LOCK_DIR" ]; then
    local lock_mtime lock_age
    lock_mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0)
    lock_age=$(( $(date +%s) - lock_mtime ))
    if [ "$lock_age" -gt 120 ]; then
      rm -rf "$LOCK_DIR"
    fi
  fi
  if [ -f "$CACHE_FILE" ]; then
    local file_mtime file_age
    file_mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    file_age=$(( $(date +%s) - file_mtime ))
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
    # mkdir atomic lock: exit immediately if another update is already running
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0

    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir" "$LOCK_DIR"' EXIT

    local today_date
    today_date=$(date +%Y%m%d)

    # Detect timeout command (not available on all macOS installs without coreutils)
    local _to=""
    command -v timeout >/dev/null 2>&1 && _to="timeout 30"

    # Run all 4 ccusage commands in parallel with optional 30s timeout
    $_to $_ccusage_cmd blocks --json  >"$tmpdir/blocks"  2>/dev/null &
    $_to $_ccusage_cmd daily  --json --since "$today_date" >"$tmpdir/daily"  2>/dev/null &
    $_to $_ccusage_cmd weekly --json >"$tmpdir/weekly"  2>/dev/null &
    $_to $_ccusage_cmd monthly --json >"$tmpdir/monthly" 2>/dev/null &
    wait

    local blocks daily weekly monthly
    blocks=$(<"$tmpdir/blocks")
    daily=$(<"$tmpdir/daily")
    weekly=$(<"$tmpdir/weekly")
    monthly=$(<"$tmpdir/monthly")

    # Atomic write: write to temp file then rename (prevents partial reads by concurrent sessions)
    if [ -n "$blocks" ]; then
      local _tmp_cache
      _tmp_cache=$(mktemp "$CACHE_FILE.XXXXXX")
      trap 'rm -rf "$tmpdir" "$LOCK_DIR" "$_tmp_cache"' EXIT
      if jq -n \
        --argjson ts "$(date +%s)" \
        --argjson blocks "$blocks" \
        --argjson daily "${daily:-null}" \
        --argjson weekly "${weekly:-null}" \
        --argjson monthly "${monthly:-null}" \
        '{timestamp: $ts, blocks: $blocks, daily: $daily, weekly: $weekly, monthly: $monthly}' \
        > "$_tmp_cache" 2>/dev/null; then
        mv "$_tmp_cache" "$CACHE_FILE"
      else
        rm -f "$_tmp_cache"
      fi
    fi
    # trap EXIT cleans up $tmpdir and $LOCK_DIR
  ) &
}

# ---- parse input with single jq call ----
if command -v jq >/dev/null 2>&1; then
  _has_jq=1
  IFS=$'\x1f' read -r current_dir model_name session_id cc_version output_style < <(
    printf '%s' "$input" | jq -r '[
      (.workspace.current_dir // .cwd // "unknown"),
      (.model.display_name // "Claude"),
      (.session_id // ""),
      (.version // ""),
      (.output_style.name // "")
    ] | join("\u001f")' 2>/dev/null
  )
  current_dir="${current_dir//$HOME/~}"
else
  _has_jq=0
  current_dir="unknown"
  model_name="Claude"
  session_id=""
  cc_version=""
  output_style=""
fi

# ---- git ----
git_branch=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git branch --show-current 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
fi

# ---- context window calculation ----
context_pct=""
context_used_tokens=""
context_max_tokens=""
context_remaining_pct=""

get_max_context() {
  case "$1" in
    *"Opus 4"*|*"opus 4"*|*"Opus"*|*"opus"*)       echo "200000" ;;
    *"Sonnet 4"*|*"sonnet 4"*|*"Sonnet 3.5"*|*"sonnet 3.5"*|*"Sonnet"*|*"sonnet"*) echo "200000" ;;
    *"Haiku 3.5"*|*"haiku 3.5"*|*"Haiku 4"*|*"haiku 4"*|*"Haiku"*|*"haiku"*)       echo "200000" ;;
    *"Claude 3 Haiku"*|*"claude 3 haiku"*) echo "100000" ;;
    *) echo "200000" ;;
  esac
}

if [ -n "$session_id" ] && [ "$_has_jq" -eq 1 ]; then
  MAX_CONTEXT=$(get_max_context "$model_name")

  # Convert current dir to session file path
  project_dir=$(echo "$current_dir" | sed "s|~|$HOME|g" | sed 's|/|-|g' | sed 's|^-||')
  session_file="$HOME/.claude/projects/-${project_dir}/${session_id}.jsonl"

  if [ -f "$session_file" ]; then
    latest_tokens=$(tail -20 "$session_file" | jq -r 'select(.message.usage) | .message.usage | ((.input_tokens // 0) + (.cache_read_input_tokens // 0))' 2>/dev/null | tail -1)

    if [ -n "$latest_tokens" ] && [ "$latest_tokens" -gt 0 ] 2>/dev/null; then
      context_used_tokens="$latest_tokens"
      context_max_tokens="$MAX_CONTEXT"
      context_used_pct=$(( latest_tokens * 100 / MAX_CONTEXT ))
      context_remaining_pct=$(( 100 - context_used_pct ))

      # Set context color based on remaining percentage
      if [ -z "$NO_COLOR" ]; then
        if [ "$context_remaining_pct" -le 20 ]; then
          _ctx=$'\033[38;5;203m'    # coral red
        elif [ "$context_remaining_pct" -le 40 ]; then
          _ctx=$'\033[38;5;215m'    # peach
        else
          _ctx=$'\033[38;5;158m'    # mint green
        fi
      fi

      context_pct="${context_remaining_pct}%"
    fi
  fi
fi

# ---- ccusage integration ----
session_txt=""; session_pct=0; session_bar=""
cost_usd=""; cost_per_hour=""; tpm=""; tot_tokens=""
today_tokens=""; today_cost=""
week_tokens=""; week_cost=""
month_tokens=""; month_cost=""
cache_hit_rate=""
rh=""; rm_val=""

if [ "$_has_jq" -eq 1 ]; then
  cached_data=""
  if cached_data=$(read_cache); then
    # Cache hit - extract all fields with single jq call
    IFS=$'\t' read -r blocks_output daily_output weekly_output monthly_output < <(
      printf '%s' "$cached_data" | jq -r '[
        (.blocks | tostring),
        (.daily | tostring),
        (.weekly | tostring),
        (.monthly | tostring)
      ] | @tsv' 2>/dev/null
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
    IFS=$'\t' read -r cost_usd cost_per_hour tot_tokens tpm cache_read cache_creation reset_time_str start_time_str < <(
      printf '%s' "$blocks_output" | jq -r '
        (.blocks[] | select(.isActive == true)) |
        [
          (.costUSD // ""),
          (.burnRate.costPerHour // ""),
          (.totalTokens // ""),
          (.burnRate.tokensPerMinute // ""),
          (.tokenCounts.cacheReadInputTokens // 0),
          (.tokenCounts.cacheCreationInputTokens // 0),
          (.usageLimitResetTime // .endTime // ""),
          (.startTime // "")
        ] | @tsv' 2>/dev/null | head -n1
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
      start_sec=$(to_epoch "$start_time_str"); end_sec=$(to_epoch "$reset_time_str"); now_sec=$(date +%s)
      total=$(( end_sec - start_sec )); (( total<1 )) && total=1
      elapsed=$(( now_sec - start_sec )); (( elapsed<0 ))&&elapsed=0; (( elapsed>total ))&&elapsed=$total
      session_pct=$(( elapsed * 100 / total ))
      remaining=$(( end_sec - now_sec )); (( remaining<0 )) && remaining=0
      rh=$(( remaining / 3600 )); rm_val=$(( (remaining % 3600) / 60 ))
      end_hm=$(fmt_time_hm "$end_sec")
      session_txt="$(printf '%dh %dm until reset at %s (%d%%)' "$rh" "$rm_val" "$end_hm" "$session_pct")"
      session_bar=$(progress_bar "$session_pct" 10)
    fi
  fi

  # Daily/Weekly/Monthly - extract with single jq calls
  if [ -n "$daily_output" ] && [ "$daily_output" != "null" ]; then
    IFS=$'\t' read -r today_tokens today_cost < <(
      printf '%s' "$daily_output" | jq -r '[(.daily[0].totalTokens // ""), (.daily[0].totalCost // "")] | @tsv' 2>/dev/null
    )
  fi

  if [ -n "$weekly_output" ] && [ "$weekly_output" != "null" ]; then
    IFS=$'\t' read -r week_tokens week_cost < <(
      printf '%s' "$weekly_output" | jq -r '[(.weekly[-1].totalTokens // ""), (.weekly[-1].totalCost // "")] | @tsv' 2>/dev/null
    )
  fi

  if [ -n "$monthly_output" ] && [ "$monthly_output" != "null" ]; then
    IFS=$'\t' read -r month_tokens month_cost < <(
      printf '%s' "$monthly_output" | jq -r '[(.monthly[-1].totalTokens // ""), (.monthly[-1].totalCost // "")] | @tsv' 2>/dev/null
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
  if [ -n "$rh" ] || [ -n "$rm_val" ]; then
    session_bar=$(progress_bar "$session_pct" 10)
    sess_part="${_session}Session ${tot_formatted}  ${rh}h ${rm_val}m ${session_bar}${_rst}"
  else
    sess_part="${_session}Session ${tot_formatted}${_rst}"
  fi
fi

meta_part=""
if [ -n "$cache_hit_rate" ] && [[ "$cache_hit_rate" =~ ^[0-9]+$ ]]; then
  meta_part="🗄 ${_cache}${cache_hit_rate}%${_rst}"
fi
if [ -n "$tpm" ] && [[ "$tpm" =~ ^[0-9.]+$ ]]; then
  tpm_int=$(printf '%.0f' "$tpm")
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
if [ -n "$today_tokens" ] && [[ "$today_tokens" =~ ^[0-9]+$ ]]; then
  today_tokens_formatted=$(format_tokens "$today_tokens")
  if [ -n "$today_cost" ] && [[ "$today_cost" =~ ^[0-9.]+$ ]]; then
    today_cost_formatted=$(printf '%.2f' "$today_cost")
    line3="💰 ${_today}Today ${today_tokens_formatted}  \$${today_cost_formatted}${_rst}"
  else
    line3="💰 ${_today}Today ${today_tokens_formatted}${_rst}"
  fi
fi

if [ -n "$week_tokens" ] && [[ "$week_tokens" =~ ^[0-9]+$ ]]; then
  week_tokens_formatted=$(format_tokens "$week_tokens")
  if [ -n "$week_cost" ] && [[ "$week_cost" =~ ^[0-9.]+$ ]]; then
    week_cost_formatted=$(printf '%.2f' "$week_cost")
    week_part="${_week}Week ${week_tokens_formatted}  \$${week_cost_formatted}${_rst}"
  else
    week_part="${_week}Week ${week_tokens_formatted}${_rst}"
  fi
  if [ -n "$line3" ]; then line3="${line3}  ${_sep}│${_rst} ${week_part}"; else line3="${week_part}"; fi
fi

if [ -n "$month_tokens" ] && [[ "$month_tokens" =~ ^[0-9]+$ ]]; then
  month_tokens_formatted=$(format_tokens "$month_tokens")
  if [ -n "$month_cost" ] && [[ "$month_cost" =~ ^[0-9.]+$ ]]; then
    month_cost_formatted=$(printf '%.2f' "$month_cost")
    month_part="${_month}Month ${month_tokens_formatted}  \$${month_cost_formatted}${_rst}"
  else
    month_part="${_month}Month ${month_tokens_formatted}${_rst}"
  fi
  if [ -n "$line3" ]; then line3="${line3}  ${_sep}│${_rst} ${month_part}"; else line3="${month_part}"; fi
fi

# Print lines
if [ -n "$line2" ]; then
  printf '\n%s' "$line2"
fi
if [ -n "$line3" ]; then
  printf '\n%s' "$line3"
fi
printf '\n'
