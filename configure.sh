#!/bin/bash
# claude-statusline configure - per-user CLI/TUI settings for statusline.sh
# Repository: https://github.com/ahngbeom/claude-statusline
#
# Persists settings to ~/.claude/statusline.conf (KEY=VALUE, overridable via
# STATUSLINE_CONFIG_FILE), which statusline.sh reads at startup. An env var
# that is already set always wins over whatever is in this file -- see the
# "user config file" section in statusline.sh.
#
# Non-interactive:
#   configure.sh list                    Show all keys, effective value, source
#   configure.sh get <KEY>
#   configure.sh set <KEY> <VALUE>
#   configure.sh unset <KEY>             Remove KEY, reverting it to its default
#   configure.sh reset [-y|--yes]        Remove the whole config file
#   configure.sh path                    Print the config file path
#
# Interactive: run with no arguments for a category-based menu.

set -u

# ---- config file location (same rule as statusline.sh) ----
_config_file() {
  printf '%s' "${STATUSLINE_CONFIG_FILE:-$HOME/.claude/statusline.conf}"
}

_statusline_bin() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s' "$dir/statusline.sh"
}

# ---- key registry ----
# Every recognized key, grouped the same way as the interactive menu.
ALL_KEYS="NO_COLOR STATUSLINE_UNICODE STATUSLINE_COMPACT STATUSLINE_COMPACT_WIDTH \
STATUSLINE_HIDE_COST STATUSLINE_MAX_CONTEXT \
STATUSLINE_SHOW_GIT STATUSLINE_SHOW_GIT_STATUS STATUSLINE_SHOW_CC_VERSION STATUSLINE_SHOW_OUTPUT_STYLE STATUSLINE_SHOW_MEM \
STATUSLINE_SHOW_SESSION STATUSLINE_SHOW_CACHE STATUSLINE_SHOW_SPEED \
STATUSLINE_SHOW_TODAY STATUSLINE_SHOW_WEEK STATUSLINE_SHOW_MONTH"

# presence: statusline.sh checks -z/-n on the raw value, so "on" must be a
#   non-empty value (we always write "1") and "off" must be key absence (we
#   delete the line) -- writing "0" would NOT disable these in statusline.sh.
# tristate: STATUSLINE_COMPACT accepts an explicit 1/0 in addition to "auto"
#   (delete the key, reverting to $COLUMNS-based detection).
# numeric: plain non-negative integers.
# bool: the new STATUSLINE_SHOW_* switches -- value-based, default is "1".
_key_type() {
  case "$1" in
    NO_COLOR|STATUSLINE_UNICODE|STATUSLINE_HIDE_COST) echo presence ;;
    STATUSLINE_COMPACT) echo tristate ;;
    STATUSLINE_COMPACT_WIDTH|STATUSLINE_MAX_CONTEXT) echo numeric ;;
    STATUSLINE_SHOW_GIT|STATUSLINE_SHOW_GIT_STATUS|STATUSLINE_SHOW_CC_VERSION|STATUSLINE_SHOW_OUTPUT_STYLE|STATUSLINE_SHOW_MEM|\
    STATUSLINE_SHOW_SESSION|STATUSLINE_SHOW_CACHE|STATUSLINE_SHOW_SPEED|\
    STATUSLINE_SHOW_TODAY|STATUSLINE_SHOW_WEEK|STATUSLINE_SHOW_MONTH) echo bool ;;
    *) echo "" ;;
  esac
}

_key_default() {
  case "$1" in
    NO_COLOR|STATUSLINE_UNICODE|STATUSLINE_HIDE_COST) echo 0 ;;
    STATUSLINE_COMPACT) echo auto ;;
    STATUSLINE_COMPACT_WIDTH) echo 80 ;;
    STATUSLINE_MAX_CONTEXT) echo "(model-based)" ;;
    *) echo 1 ;;
  esac
}

_key_description() {
  case "$1" in
    NO_COLOR) echo "Disable ANSI colors" ;;
    STATUSLINE_UNICODE) echo "Use unicode block chars (▰▱) for progress bars" ;;
    STATUSLINE_COMPACT) echo "Force compact layout on/off (auto = \$COLUMNS-based)" ;;
    STATUSLINE_COMPACT_WIDTH) echo "Column width threshold that triggers compact mode" ;;
    STATUSLINE_HIDE_COST) echo "Hide session cost (Line 2) and all of Line 3" ;;
    STATUSLINE_MAX_CONTEXT) echo "Override JSONL-fallback context window size (tokens)" ;;
    STATUSLINE_SHOW_GIT) echo "Line 1: git branch segment" ;;
    STATUSLINE_SHOW_GIT_STATUS) echo "Line 1: dirty(*)/ahead-behind(up/down) markers" ;;
    STATUSLINE_SHOW_CC_VERSION) echo "Line 1: Claude Code CLI version" ;;
    STATUSLINE_SHOW_OUTPUT_STYLE) echo "Line 1: output style name" ;;
    STATUSLINE_SHOW_MEM) echo "Line 1: memory usage indicator" ;;
    STATUSLINE_SHOW_SESSION) echo "Line 2: Session tokens/cost/time/bar" ;;
    STATUSLINE_SHOW_CACHE) echo "Line 2: cache hit rate" ;;
    STATUSLINE_SHOW_SPEED) echo "Line 2: tokens/min burn rate" ;;
    STATUSLINE_SHOW_TODAY) echo "Line 3: Today usage" ;;
    STATUSLINE_SHOW_WEEK) echo "Line 3: Week usage" ;;
    STATUSLINE_SHOW_MONTH) echo "Line 3: Month usage" ;;
    *) echo "" ;;
  esac
}

# ---- config file read/write (atomic, mktemp + mv, same pattern as
# statusline.sh's stats-cache.json/rate-limits-cache.json writers) ----
_ensure_config_dir() {
  local dir
  dir="$(dirname "$(_config_file)")"
  [ -d "$dir" ] || mkdir -p "$dir"
}

# Prints every line of the config file except an existing "KEY=..." line for $1.
_config_lines_without_key() {
  local key="$1" file line
  file="$(_config_file)"
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$key="*) continue ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$file"
}

_read_config_value() {
  local key="$1" file line
  file="$(_config_file)"
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$key="*) printf '%s' "${line#"$key"=}"; return 0 ;;
    esac
  done < "$file"
  return 1
}

_write_config_value() {
  local key="$1" value="$2" file tmp is_new=0
  file="$(_config_file)"
  _ensure_config_dir
  [ -f "$file" ] || is_new=1
  tmp=$(mktemp "$file.XXXXXX") || return 1
  {
    if [ "$is_new" -eq 1 ]; then
      printf '# claude-statusline per-user config -- managed by configure.sh\n'
      printf '# Edit via: configure.sh set <KEY> <VALUE> (or configure.sh with no args for the menu)\n'
    fi
    _config_lines_without_key "$key"
    printf '%s=%s\n' "$key" "$value"
  } > "$tmp"
  mv "$tmp" "$file"
}

_delete_config_value() {
  local key="$1" file tmp
  file="$(_config_file)"
  [ -f "$file" ] || return 0
  tmp=$(mktemp "$file.XXXXXX") || return 1
  _config_lines_without_key "$key" > "$tmp"
  mv "$tmp" "$file"
}

# ---- effective value/source (env > config file > default) ----
_effective_value() {
  local key="$1" v
  if [ -n "${!key+x}" ]; then
    printf '%s' "${!key}"
    return
  fi
  if v=$(_read_config_value "$key"); then
    printf '%s' "$v"
    return
  fi
  _key_default "$key"
}

_effective_source() {
  local key="$1"
  if [ -n "${!key+x}" ]; then
    echo "env"
  elif _read_config_value "$key" >/dev/null; then
    echo "config"
  else
    echo "default"
  fi
}

# Normalizes a raw CLI/menu value for $key's type; prints the canonical form
# on stdout and returns 0, or returns 1 for an invalid value. "auto" is only
# valid for tristate keys and is handled by the caller (it means: delete the
# key rather than write a value).
_validate_value() {
  local key="$1" type="$2" value="$3"
  case "$type" in
    presence|bool)
      case "$value" in
        1|on|On|ON|true|True|TRUE|yes|Yes|YES) echo 1 ;;
        0|off|Off|OFF|false|False|FALSE|no|No|NO) echo 0 ;;
        *) return 1 ;;
      esac
      ;;
    tristate)
      case "$value" in
        1|on|On|ON|true|yes) echo 1 ;;
        0|off|Off|OFF|false|no) echo 0 ;;
        auto|Auto|AUTO) echo auto ;;
        *) return 1 ;;
      esac
      ;;
    numeric)
      [[ "$value" =~ ^[0-9]+$ ]] && echo "$value" || return 1
      ;;
    *) return 1 ;;
  esac
}

# ---- CLI subcommands ----
cmd_list() {
  local key
  printf '%-30s %-14s %-8s %s\n' "KEY" "VALUE" "SOURCE" "DESCRIPTION"
  for key in $ALL_KEYS; do
    printf '%-30s %-14s %-8s %s\n' "$key" "$(_effective_value "$key")" "$(_effective_source "$key")" "$(_key_description "$key")"
  done
}

cmd_get() {
  local key="${1:-}"
  if [ -z "$key" ] || [ -z "$(_key_type "$key")" ]; then
    echo "configure.sh: unknown key '$key' (see 'configure.sh list')" >&2
    return 1
  fi
  _effective_value "$key"
  echo
}

cmd_set() {
  local key="${1:-}" raw="${2:-}" type norm
  type="$(_key_type "$key")"
  if [ -z "$type" ]; then
    echo "configure.sh: unknown key '$key' (see 'configure.sh list')" >&2
    return 1
  fi
  if [ -z "$raw" ]; then
    echo "configure.sh: usage: configure.sh set $key <VALUE>" >&2
    return 1
  fi
  if ! norm="$(_validate_value "$key" "$type" "$raw")"; then
    echo "configure.sh: invalid value '$raw' for $key (type: $type)" >&2
    return 1
  fi
  if [ "$type" = "tristate" ] && [ "$norm" = "auto" ]; then
    _delete_config_value "$key"
  elif [ "$type" = "presence" ] && [ "$norm" = "0" ]; then
    _delete_config_value "$key"
  else
    _write_config_value "$key" "$norm"
  fi
  echo "configure.sh: $key -> $(_effective_value "$key")"
}

cmd_unset() {
  local key="${1:-}"
  if [ -z "$key" ] || [ -z "$(_key_type "$key")" ]; then
    echo "configure.sh: unknown key '$key' (see 'configure.sh list')" >&2
    return 1
  fi
  _delete_config_value "$key"
  echo "configure.sh: $key reset to default ($(_effective_value "$key"))"
}

cmd_reset() {
  local flag="${1:-}" file
  file="$(_config_file)"
  if [ "$flag" != "-y" ] && [ "$flag" != "--yes" ]; then
    local ans
    read -r -p "configure.sh: remove all settings in $file? [y/N] " ans
    case "$ans" in
      y|Y|yes|Yes) : ;;
      *) echo "configure.sh: aborted"; return 1 ;;
    esac
  fi
  [ -f "$file" ] && rm -f "$file"
  echo "configure.sh: removed $file (all settings back to defaults)"
}

cmd_path() {
  _config_file
  echo
}

cmd_preview() {
  local bin json
  bin="$(_statusline_bin)"
  if [ ! -f "$bin" ]; then
    echo "configure.sh: statusline.sh not found next to configure.sh ($bin)" >&2
    return 1
  fi
  json='{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Opus 4.6"},"version":"1.0.44","output_style":{"name":"explanatory"},"context_window":{"total_input_tokens":45000,"context_window_size":200000},"cost":{"total_cost_usd":0.42}}'
  printf '%s' "$json" | bash "$bin"
}

print_help() {
  cat <<'EOF'
configure.sh - per-user settings for claude-statusline

Usage:
  configure.sh                  Interactive menu
  configure.sh list             Show all keys, effective value, source
  configure.sh get <KEY>
  configure.sh set <KEY> <VALUE>
  configure.sh unset <KEY>      Remove KEY (revert to default)
  configure.sh reset [-y]       Remove the whole config file
  configure.sh path             Print the config file path
  configure.sh help             Show this help
EOF
}

# ---- interactive TUI (pure bash, no external deps) ----
_prompt_toggle() {
  local key="$1" type cur ans norm
  type="$(_key_type "$key")"
  cur="$(_effective_value "$key")"
  echo "  $key  [current: $cur]  -- $(_key_description "$key")"
  case "$type" in
    presence|bool)
      read -r -p "    1=on 0=off (Enter=skip): " ans
      ;;
    tristate)
      read -r -p "    1=on 0=off a=auto (Enter=skip): " ans
      ;;
    numeric)
      read -r -p "    new value (Enter=skip): " ans
      ;;
  esac
  [ -z "$ans" ] && return 0
  if [ "$type" = "tristate" ] && { [ "$ans" = "a" ] || [ "$ans" = "auto" ]; }; then
    _delete_config_value "$key"
    echo "    -> auto"
    return 0
  fi
  if ! norm="$(_validate_value "$key" "$type" "$ans")"; then
    echo "    invalid value, skipped"
    return 0
  fi
  if [ "$type" = "presence" ] && [ "$norm" = "0" ]; then
    _delete_config_value "$key"
  else
    _write_config_value "$key" "$norm"
  fi
  echo "    -> $(_effective_value "$key")"
}

_menu_group() {
  local k
  for k in "$@"; do
    _prompt_toggle "$k"
  done
}

run_menu() {
  local choice
  while true; do
    echo ""
    echo "claude-statusline configure  (config: $(_config_file))"
    echo "  1) Colors & bar style"
    echo "  2) Compact mode"
    echo "  3) Cost & context"
    echo "  4) Line 1 fields (git, cc version, output style, memory)"
    echo "  5) Line 2 fields (session, cache, speed)"
    echo "  6) Line 3 fields (today, week, month)"
    echo "  7) List all settings"
    echo "  8) Preview statusline"
    echo "  9) Reset all to defaults"
    echo "  0) Exit"
    read -r -p "> " choice
    case "$choice" in
      1) _menu_group NO_COLOR STATUSLINE_UNICODE ;;
      2) _menu_group STATUSLINE_COMPACT STATUSLINE_COMPACT_WIDTH ;;
      3) _menu_group STATUSLINE_HIDE_COST STATUSLINE_MAX_CONTEXT ;;
      4) _menu_group STATUSLINE_SHOW_GIT STATUSLINE_SHOW_GIT_STATUS STATUSLINE_SHOW_CC_VERSION STATUSLINE_SHOW_OUTPUT_STYLE STATUSLINE_SHOW_MEM ;;
      5) _menu_group STATUSLINE_SHOW_SESSION STATUSLINE_SHOW_CACHE STATUSLINE_SHOW_SPEED ;;
      6) _menu_group STATUSLINE_SHOW_TODAY STATUSLINE_SHOW_WEEK STATUSLINE_SHOW_MONTH ;;
      7) cmd_list ;;
      8) cmd_preview ;;
      9) cmd_reset ;;
      0) break ;;
      *) echo "unknown choice: $choice" ;;
    esac
  done
}

main() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    list) cmd_list ;;
    get) cmd_get "$@" ;;
    set) cmd_set "$@" ;;
    unset) cmd_unset "$@" ;;
    reset) cmd_reset "$@" ;;
    path) cmd_path ;;
    preview) cmd_preview ;;
    ""|menu) run_menu ;;
    -h|--help|help) print_help ;;
    *)
      echo "configure.sh: unknown subcommand '$sub'" >&2
      print_help >&2
      exit 1
      ;;
  esac
}

main "$@"
