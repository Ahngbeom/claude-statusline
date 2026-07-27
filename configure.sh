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
# Interactive: run with no arguments. On a real terminal this opens a full
# arrow-key TUI (↑↓ move, ←→ adjust, Enter/Space edit, r/R reset, q quit)
# with a "Live Preview" panel pinned at the top, always showing statusline.sh
# rendered with your current settings. Piped/non-interactive input (or
# `configure.sh menu` explicitly) falls back to a simpler numbered menu.

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
STATUSLINE_HIDE_COST STATUSLINE_MAX_CONTEXT STATUSLINE_SEP_CHAR \
STATUSLINE_SHOW_GIT STATUSLINE_SHOW_GIT_STATUS STATUSLINE_SHOW_CC_VERSION STATUSLINE_SHOW_OUTPUT_STYLE STATUSLINE_SHOW_MEM \
STATUSLINE_SHOW_SESSION STATUSLINE_SHOW_CACHE STATUSLINE_SHOW_SPEED \
STATUSLINE_SHOW_TODAY STATUSLINE_SHOW_WEEK STATUSLINE_SHOW_MONTH \
STATUSLINE_COLOR_DIR STATUSLINE_COLOR_MODEL STATUSLINE_COLOR_GIT STATUSLINE_COLOR_CC_VERSION STATUSLINE_COLOR_OUTPUT_STYLE \
STATUSLINE_COLOR_SEP STATUSLINE_COLOR_CACHE STATUSLINE_COLOR_TODAY STATUSLINE_COLOR_WEEK STATUSLINE_COLOR_MONTH \
STATUSLINE_COLOR_CTX_OK STATUSLINE_COLOR_CTX_WARN STATUSLINE_COLOR_CTX_CRIT \
STATUSLINE_COLOR_SESSION_OK STATUSLINE_COLOR_SESSION_WARN STATUSLINE_COLOR_SESSION_CRIT \
STATUSLINE_COLOR_MEM_OK STATUSLINE_COLOR_MEM_WARN STATUSLINE_COLOR_MEM_CRIT \
STATUSLINE_ICON_DIR STATUSLINE_ICON_CONTEXT STATUSLINE_ICON_COST STATUSLINE_ICON_CACHE STATUSLINE_ICON_MEM \
STATUSLINE_THRESHOLD_CTX_WARN STATUSLINE_THRESHOLD_CTX_CRIT \
STATUSLINE_THRESHOLD_MEM_WARN STATUSLINE_THRESHOLD_MEM_CRIT \
STATUSLINE_THRESHOLD_SESSION_WARN STATUSLINE_THRESHOLD_SESSION_CRIT"

# ---- category registry (single source of truth for both the light menu's
# numbered groups and the full TUI's flat scrollable list -- see run_menu()
# and _tui_build_rows() below) ----
# Each entry is "Title|KEY1 KEY2 KEY3 ...". Order here is the order shown in
# both UIs.
CATEGORY_DEFS=(
  "Colors & bar style|NO_COLOR STATUSLINE_UNICODE STATUSLINE_SEP_CHAR"
  "Compact mode|STATUSLINE_COMPACT STATUSLINE_COMPACT_WIDTH"
  "Cost & context|STATUSLINE_HIDE_COST STATUSLINE_MAX_CONTEXT"
  "Line 1 fields (git, cc version, output style, memory)|STATUSLINE_SHOW_GIT STATUSLINE_SHOW_GIT_STATUS STATUSLINE_SHOW_CC_VERSION STATUSLINE_SHOW_OUTPUT_STYLE STATUSLINE_SHOW_MEM"
  "Line 2 fields (session, cache, speed)|STATUSLINE_SHOW_SESSION STATUSLINE_SHOW_CACHE STATUSLINE_SHOW_SPEED"
  "Line 3 fields (today, week, month)|STATUSLINE_SHOW_TODAY STATUSLINE_SHOW_WEEK STATUSLINE_SHOW_MONTH"
  "Line 1 colors (dir, model, git, cc version, output style)|STATUSLINE_COLOR_DIR STATUSLINE_COLOR_MODEL STATUSLINE_COLOR_GIT STATUSLINE_COLOR_CC_VERSION STATUSLINE_COLOR_OUTPUT_STYLE"
  "Context colors & thresholds|STATUSLINE_COLOR_CTX_OK STATUSLINE_COLOR_CTX_WARN STATUSLINE_COLOR_CTX_CRIT STATUSLINE_THRESHOLD_CTX_WARN STATUSLINE_THRESHOLD_CTX_CRIT"
  "Session colors & thresholds|STATUSLINE_COLOR_SESSION_OK STATUSLINE_COLOR_SESSION_WARN STATUSLINE_COLOR_SESSION_CRIT STATUSLINE_THRESHOLD_SESSION_WARN STATUSLINE_THRESHOLD_SESSION_CRIT"
  "Memory colors & thresholds|STATUSLINE_COLOR_MEM_OK STATUSLINE_COLOR_MEM_WARN STATUSLINE_COLOR_MEM_CRIT STATUSLINE_THRESHOLD_MEM_WARN STATUSLINE_THRESHOLD_MEM_CRIT"
  "Other element colors (separator, cache, today, week, month)|STATUSLINE_COLOR_SEP STATUSLINE_COLOR_CACHE STATUSLINE_COLOR_TODAY STATUSLINE_COLOR_WEEK STATUSLINE_COLOR_MONTH"
  "Icons|STATUSLINE_ICON_DIR STATUSLINE_ICON_CONTEXT STATUSLINE_ICON_COST STATUSLINE_ICON_CACHE STATUSLINE_ICON_MEM"
)

# presence: statusline.sh checks -z/-n on the raw value, so "on" must be a
#   non-empty value (we always write "1") and "off" must be key absence (we
#   delete the line) -- writing "0" would NOT disable these in statusline.sh.
# tristate: STATUSLINE_COMPACT accepts an explicit 1/0 in addition to "auto"
#   (delete the key, reverting to $COLUMNS-based detection).
# numeric: plain non-negative integers.
# bool: the new STATUSLINE_SHOW_* switches -- value-based, default is "1".
# color256: a raw xterm 256-color code (0-255), used directly in a
#   \033[38;5;<n>m escape by statusline.sh -- see _resolve_color() there.
# text: an arbitrary short string (icon glyph or separator char) -- any value
#   is accepted, since statusline.sh only ever interpolates it as a printf
#   %s argument (never part of a format string), so there's no injection
#   surface to validate against.
# percent: a color-threshold cutoff, 0-100.
_key_type() {
  case "$1" in
    NO_COLOR|STATUSLINE_UNICODE|STATUSLINE_HIDE_COST) echo presence ;;
    STATUSLINE_COMPACT) echo tristate ;;
    STATUSLINE_COMPACT_WIDTH|STATUSLINE_MAX_CONTEXT) echo numeric ;;
    STATUSLINE_SHOW_GIT|STATUSLINE_SHOW_GIT_STATUS|STATUSLINE_SHOW_CC_VERSION|STATUSLINE_SHOW_OUTPUT_STYLE|STATUSLINE_SHOW_MEM|\
    STATUSLINE_SHOW_SESSION|STATUSLINE_SHOW_CACHE|STATUSLINE_SHOW_SPEED|\
    STATUSLINE_SHOW_TODAY|STATUSLINE_SHOW_WEEK|STATUSLINE_SHOW_MONTH) echo bool ;;
    STATUSLINE_COLOR_DIR|STATUSLINE_COLOR_MODEL|STATUSLINE_COLOR_GIT|STATUSLINE_COLOR_CC_VERSION|STATUSLINE_COLOR_OUTPUT_STYLE|\
    STATUSLINE_COLOR_SEP|STATUSLINE_COLOR_CACHE|STATUSLINE_COLOR_TODAY|STATUSLINE_COLOR_WEEK|STATUSLINE_COLOR_MONTH|\
    STATUSLINE_COLOR_CTX_OK|STATUSLINE_COLOR_CTX_WARN|STATUSLINE_COLOR_CTX_CRIT|\
    STATUSLINE_COLOR_SESSION_OK|STATUSLINE_COLOR_SESSION_WARN|STATUSLINE_COLOR_SESSION_CRIT|\
    STATUSLINE_COLOR_MEM_OK|STATUSLINE_COLOR_MEM_WARN|STATUSLINE_COLOR_MEM_CRIT) echo color256 ;;
    STATUSLINE_ICON_DIR|STATUSLINE_ICON_CONTEXT|STATUSLINE_ICON_COST|STATUSLINE_ICON_CACHE|STATUSLINE_ICON_MEM|\
    STATUSLINE_SEP_CHAR) echo text ;;
    STATUSLINE_THRESHOLD_CTX_WARN|STATUSLINE_THRESHOLD_CTX_CRIT|\
    STATUSLINE_THRESHOLD_MEM_WARN|STATUSLINE_THRESHOLD_MEM_CRIT|\
    STATUSLINE_THRESHOLD_SESSION_WARN|STATUSLINE_THRESHOLD_SESSION_CRIT) echo percent ;;
    *) echo "" ;;
  esac
}

_key_default() {
  case "$1" in
    NO_COLOR|STATUSLINE_UNICODE|STATUSLINE_HIDE_COST) echo 0 ;;
    STATUSLINE_COMPACT) echo auto ;;
    STATUSLINE_COMPACT_WIDTH) echo 80 ;;
    STATUSLINE_MAX_CONTEXT) echo "(model-based)" ;;
    STATUSLINE_SEP_CHAR) echo "│" ;;
    STATUSLINE_COLOR_DIR) echo 117 ;;
    STATUSLINE_COLOR_MODEL) echo 147 ;;
    STATUSLINE_COLOR_GIT) echo 150 ;;
    STATUSLINE_COLOR_CC_VERSION) echo 249 ;;
    STATUSLINE_COLOR_OUTPUT_STYLE) echo 245 ;;
    STATUSLINE_COLOR_SEP) echo 240 ;;
    STATUSLINE_COLOR_CACHE) echo 120 ;;
    STATUSLINE_COLOR_TODAY) echo 153 ;;
    STATUSLINE_COLOR_WEEK) echo 183 ;;
    STATUSLINE_COLOR_MONTH) echo 216 ;;
    STATUSLINE_COLOR_CTX_OK) echo 158 ;;
    STATUSLINE_COLOR_CTX_WARN) echo 215 ;;
    STATUSLINE_COLOR_CTX_CRIT) echo 203 ;;
    STATUSLINE_COLOR_SESSION_OK) echo 194 ;;
    STATUSLINE_COLOR_SESSION_WARN) echo 228 ;;
    STATUSLINE_COLOR_SESSION_CRIT) echo 210 ;;
    STATUSLINE_COLOR_MEM_OK) echo 120 ;;
    STATUSLINE_COLOR_MEM_WARN) echo 220 ;;
    STATUSLINE_COLOR_MEM_CRIT) echo 196 ;;
    STATUSLINE_ICON_DIR) echo "📂" ;;
    STATUSLINE_ICON_CONTEXT) echo "🧠" ;;
    STATUSLINE_ICON_COST) echo "💰" ;;
    STATUSLINE_ICON_CACHE) echo "🗄" ;;
    STATUSLINE_ICON_MEM) echo "💻" ;;
    STATUSLINE_THRESHOLD_CTX_WARN) echo 40 ;;
    STATUSLINE_THRESHOLD_CTX_CRIT) echo 20 ;;
    STATUSLINE_THRESHOLD_MEM_WARN) echo 60 ;;
    STATUSLINE_THRESHOLD_MEM_CRIT) echo 80 ;;
    STATUSLINE_THRESHOLD_SESSION_WARN) echo 25 ;;
    STATUSLINE_THRESHOLD_SESSION_CRIT) echo 10 ;;
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
    STATUSLINE_SEP_CHAR) echo "Separator character between segments (all lines)" ;;
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
    STATUSLINE_COLOR_DIR) echo "256-color code: Line 1 directory" ;;
    STATUSLINE_COLOR_MODEL) echo "256-color code: Line 1 model name" ;;
    STATUSLINE_COLOR_GIT) echo "256-color code: Line 1 git branch" ;;
    STATUSLINE_COLOR_CC_VERSION) echo "256-color code: Line 1 CLI version" ;;
    STATUSLINE_COLOR_OUTPUT_STYLE) echo "256-color code: Line 1 output style" ;;
    STATUSLINE_COLOR_SEP) echo "256-color code: separator character (all lines)" ;;
    STATUSLINE_COLOR_CACHE) echo "256-color code: Line 2 cache hit rate / tokens-per-min" ;;
    STATUSLINE_COLOR_TODAY) echo "256-color code: Line 3 Today" ;;
    STATUSLINE_COLOR_WEEK) echo "256-color code: Line 3 Week" ;;
    STATUSLINE_COLOR_MONTH) echo "256-color code: Line 3 Month" ;;
    STATUSLINE_COLOR_CTX_OK) echo "256-color code: context bar, above the warn threshold" ;;
    STATUSLINE_COLOR_CTX_WARN) echo "256-color code: context bar, at/below the warn threshold" ;;
    STATUSLINE_COLOR_CTX_CRIT) echo "256-color code: context bar, at/below the crit threshold" ;;
    STATUSLINE_COLOR_SESSION_OK) echo "256-color code: Session segment, above the warn threshold" ;;
    STATUSLINE_COLOR_SESSION_WARN) echo "256-color code: Session segment, at/below the warn threshold" ;;
    STATUSLINE_COLOR_SESSION_CRIT) echo "256-color code: Session segment, at/below the crit threshold" ;;
    STATUSLINE_COLOR_MEM_OK) echo "256-color code: Mem indicator, below the warn threshold" ;;
    STATUSLINE_COLOR_MEM_WARN) echo "256-color code: Mem indicator, at/above the warn threshold" ;;
    STATUSLINE_COLOR_MEM_CRIT) echo "256-color code: Mem indicator, at/above the crit threshold" ;;
    STATUSLINE_ICON_DIR) echo "Icon: Line 1 directory prefix" ;;
    STATUSLINE_ICON_CONTEXT) echo "Icon: Line 2 context segment prefix" ;;
    STATUSLINE_ICON_COST) echo "Icon: Line 3 (and compact Line 3) cost segment prefix" ;;
    STATUSLINE_ICON_CACHE) echo "Icon: Line 2 cache hit rate prefix" ;;
    STATUSLINE_ICON_MEM) echo "Icon: Line 1 memory indicator prefix" ;;
    STATUSLINE_THRESHOLD_CTX_WARN) echo "Context remaining % at/below which the bar turns warn-colored" ;;
    STATUSLINE_THRESHOLD_CTX_CRIT) echo "Context remaining % at/below which the bar turns crit-colored" ;;
    STATUSLINE_THRESHOLD_MEM_WARN) echo "Memory used % at/above which Mem turns warn-colored" ;;
    STATUSLINE_THRESHOLD_MEM_CRIT) echo "Memory used % at/above which Mem turns crit-colored" ;;
    STATUSLINE_THRESHOLD_SESSION_WARN) echo "Session remaining % at/below which Session turns warn-colored" ;;
    STATUSLINE_THRESHOLD_SESSION_CRIT) echo "Session remaining % at/below which Session turns crit-colored" ;;
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
    color256)
      [[ "$value" =~ ^[0-9]{1,3}$ ]] && [ "$value" -le 255 ] && echo "$value" || return 1
      ;;
    percent)
      [[ "$value" =~ ^[0-9]{1,3}$ ]] && [ "$value" -le 100 ] && echo "$value" || return 1
      ;;
    text)
      printf '%s' "$value"
      ;;
    *) return 1 ;;
  esac
}

# Case-insensitive "reset to default" keyword, accepted by cmd_set/_prompt_toggle
# in addition to each type's own values (e.g. tristate's "auto", presence's "0")
# -- those existing type-specific reset spellings are left untouched, this is
# just a uniform alias that works for every type, including the new
# color256/text/percent ones that have no other reset spelling of their own.
_is_reset_keyword() {
  case "$1" in
    default|Default|DEFAULT|reset|Reset|RESET) return 0 ;;
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
  if _is_reset_keyword "$raw"; then
    _delete_config_value "$key"
    echo "configure.sh: $key -> $(_effective_value "$key") (default)"
    return
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

# Mock stdin JSON shared by cmd_preview and the live-preview panel below --
# same synthetic session (Opus 4.6, 45K/200K context, $0.42 cost) so both
# show identical numbers, just in different framings.
_preview_json() {
  printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Opus 4.6"},"version":"1.0.44","output_style":{"name":"explanatory"},"context_window":{"total_input_tokens":45000,"context_window_size":200000},"cost":{"total_cost_usd":0.42}}' "$PWD"
}

cmd_preview() {
  local bin
  bin="$(_statusline_bin)"
  if [ ! -f "$bin" ]; then
    echo "configure.sh: statusline.sh not found next to configure.sh ($bin)" >&2
    return 1
  fi
  _preview_json | bash "$bin"
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

# Clears the screen only when stdout is a real terminal ([ -t 1 ]) -- piped/
# redirected output (including bats' `run` capture) never sees the escape
# sequence, so callers don't need to strip ANSI to assert on menu output.
# Raw CSI codes, no `tput` subprocess -- same convention as statusline.sh's
# own hand-written \033[...m color codes.
_clear_screen() {
  [ -t 1 ] && printf '\033[H\033[2J'
}

# Renders a framed, always-current statusline.sh preview -- called at the top
# of every run_menu() screen redraw and again right after any value change,
# so the effect of an edit is visible immediately instead of requiring a
# separate "Preview statusline" menu action. Fixed-width divider rather than
# a content-fitted box border: measuring on-screen width through ANSI color
# codes and wide emoji glyphs is a separate, harder problem this doesn't need
# to solve. Silently no-ops if statusline.sh is missing (unlike cmd_preview's
# explicit error) since this redraws every loop iteration -- an error here
# would spam every screen instead of failing once.
_render_preview_panel() {
  local bin
  bin="$(_statusline_bin)"
  [ -f "$bin" ] || return 0
  printf -- '──────────────────────────── Live Preview ────────────────────────────\n'
  _preview_json | bash "$bin"
  printf -- '────────────────────────────────────────────────────────────────────\n'
}

_prompt_toggle() {
  local key="$1" type cur ans norm changed=0
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
    color256)
      read -r -p "    new 256-color code 0-255, 'default'=reset (Enter=skip): " ans
      ;;
    percent)
      read -r -p "    new percent 0-100, 'default'=reset (Enter=skip): " ans
      ;;
    text)
      read -r -p "    new text, 'default'=reset (Enter=skip): " ans
      ;;
  esac
  [ -z "$ans" ] && return 0
  if [ "$type" = "tristate" ] && { [ "$ans" = "a" ] || [ "$ans" = "auto" ]; }; then
    _delete_config_value "$key"
    echo "    -> auto"
    changed=1
  elif _is_reset_keyword "$ans"; then
    _delete_config_value "$key"
    echo "    -> $(_effective_value "$key") (default)"
    changed=1
  elif ! norm="$(_validate_value "$key" "$type" "$ans")"; then
    echo "    invalid value, skipped"
  else
    if [ "$type" = "presence" ] && [ "$norm" = "0" ]; then
      _delete_config_value "$key"
    else
      _write_config_value "$key" "$norm"
    fi
    echo "    -> $(_effective_value "$key")"
    changed=1
  fi
  [ "$changed" -eq 1 ] && _render_preview_panel
}

_menu_group() {
  local k
  for k in "$@"; do
    _prompt_toggle "$k"
  done
}

run_menu() {
  local choice i n
  n=${#CATEGORY_DEFS[@]}
  while true; do
    _clear_screen
    _render_preview_panel
    echo ""
    echo "claude-statusline configure  (config: $(_config_file))"
    for ((i = 0; i < n; i++)); do
      printf '%3d) %s\n' "$((i + 1))" "${CATEGORY_DEFS[$i]%%|*}"
    done
    printf '%3d) List all settings\n' "$((n + 1))"
    printf '%3d) Preview statusline\n' "$((n + 2))"
    printf '%3d) Reset all to defaults\n' "$((n + 3))"
    echo "  0) Exit"
    # `|| break`: on EOF (Ctrl-D, or piped input running out) `read` returns
    # non-zero and leaves choice empty -- without this, that empty choice
    # falls through to the `*)` branch below and the loop spins forever
    # re-reading an already-closed stdin instead of exiting.
    read -r -p "> " choice || break
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$n" ]; then
      # shellcheck disable=SC2086 # intentional word-splitting: space-separated key list
      _menu_group ${CATEGORY_DEFS[$((choice - 1))]#*|}
    elif [ "$choice" = "$((n + 1))" ]; then
      cmd_list
    elif [ "$choice" = "$((n + 2))" ]; then
      cmd_preview
    elif [ "$choice" = "$((n + 3))" ]; then
      cmd_reset
    elif [ "$choice" = "0" ]; then
      break
    else
      echo "unknown choice: $choice"
    fi
  done
}

# ---- full TUI (arrow-key navigable, pinned live preview) ----
# Only meaningfully usable with a real pty (raw terminal mode + alternate
# screen buffer), so it's gated on _is_tty() and falls back to run_menu()
# above otherwise -- same "diminished but working" contract as NO_COLOR/
# STATUSLINE_COMPACT elsewhere in this project. run_menu() itself stays the
# non-interactive/scripting-safe fallback (also what bats exercises, since
# piped stdin is never a tty) and the explicit escape hatch via
# `configure.sh menu`.
_is_tty() { [ -t 0 ] && [ -t 1 ]; }

# _TUI_ROWS: flat list built from CATEGORY_DEFS, one entry per screen row --
# "H:<title>" for a non-selectable category header, "K:<KEY>" for a
# selectable setting. The cursor only ever lands on K: rows.
_tui_build_rows() {
  _TUI_ROWS=()
  local i n keys k
  n=${#CATEGORY_DEFS[@]}
  for ((i = 0; i < n; i++)); do
    _TUI_ROWS+=("H:${CATEGORY_DEFS[$i]%%|*}")
    keys="${CATEGORY_DEFS[$i]#*|}"
    for k in $keys; do
      _TUI_ROWS+=("K:$k")
    done
  done
}

_tui_is_selectable() { [ "${_TUI_ROWS[$1]:0:2}" = "K:" ]; }

_tui_first_selectable() {
  local i total=${#_TUI_ROWS[@]}
  for ((i = 0; i < total; i++)); do
    if _tui_is_selectable "$i"; then
      printf '%d' "$i"
      return 0
    fi
  done
  printf '%d' -1
  return 1
}

_tui_current_key() { printf '%s' "${_TUI_ROWS[$_tui_cursor]#K:}"; }

# Moves the cursor one selectable row in the given direction (1 or -1),
# skipping header rows; clamps at the ends (no wraparound).
_tui_step() {
  local step="$1" next=$_tui_cursor total=${#_TUI_ROWS[@]}
  while :; do
    next=$((next + step))
    [ "$next" -lt 0 ] && return 0
    [ "$next" -ge "$total" ] && return 0
    if _tui_is_selectable "$next"; then
      _tui_cursor=$next
      return 0
    fi
  done
}

# Terminal size, queried once per redraw (stty, not tput -- already required
# for raw-mode toggling below, so this introduces no new subprocess kind).
# Falls back to a conservative 24x80 if stty size fails for any reason.
_tui_term_size() {
  local rc
  rc="$(stty size 2>/dev/null)"
  if [[ "$rc" =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
    _TERM_ROWS="${BASH_REMATCH[1]}"
    _TERM_COLS="${BASH_REMATCH[2]}"
  else
    _TERM_ROWS=24
    _TERM_COLS=80
  fi
}

# Fixed reserve for everything around the scrollable list: 1 preview divider
# + 3 preview content lines (padded/truncated to exactly 3, see _tui_render)
# + 1 preview divider + 1 blank + 1 header + 1 blank + 1 blank + 1 footer,
# plus a 1-line safety margin.
_tui_viewport_rows() {
  local rows=$((_TERM_ROWS - 11))
  [ "$rows" -lt 3 ] && rows=3
  printf '%d' "$rows"
}

_tui_fix_scroll() {
  local vp total=${#_TUI_ROWS[@]} bottom max_top
  vp=$(_tui_viewport_rows)
  [ "$_tui_cursor" -lt "$_tui_scroll_top" ] && _tui_scroll_top=$_tui_cursor
  bottom=$((_tui_scroll_top + vp - 1))
  [ "$_tui_cursor" -gt "$bottom" ] && _tui_scroll_top=$((_tui_cursor - vp + 1))
  max_top=$((total - vp))
  [ "$max_top" -lt 0 ] && max_top=0
  [ "$_tui_scroll_top" -gt "$max_top" ] && _tui_scroll_top=$max_top
  [ "$_tui_scroll_top" -lt 0 ] && _tui_scroll_top=0
}

# _tui_row_text[idx] caches the rendered content of _TUI_ROWS[idx] (just the
# text -- highlight/bold styling is applied fresh at render time in
# _tui_render below, since that's a free string-concat, not a fork). Only
# recomputed when that row's underlying value actually changes (see the
# call sites in _tui_cycle/_tui_nudge/_tui_edit_via_prompt/
# _tui_reset_current/_tui_reset_all below) -- NOT on every render, which is
# what makes pure cursor movement (Up/Down/PgUp/PgDn) fork-free. Before this
# cache existed, _tui_render() called _effective_value()/_key_description()
# (each a subshell fork) for every visible row on every single keypress --
# with a ~12-row viewport that's ~36 forks per arrow-key press, the main
# cause of reported stutter/lag.
#
# Plain array-index assignment (_tui_row_text[$idx]=...), not
# `printf -v "arr[$idx]"` -- confirmed by direct testing that bash 3.2
# (macOS stock bash) rejects printf -v with an array-subscript target
# ("not a valid identifier"); ordinary `arr[$idx]=value` assignment doesn't
# have that restriction. The $(...) calls below still fork, same as before
# -- caching doesn't eliminate that cost, it just moves it from "every
# frame" to "only when this row's value changes", which is what actually
# matters for feel.
_tui_refresh_row() {
  local idx="$1"
  local row="${_TUI_ROWS[$idx]}" kind rest
  kind="${row:0:1}"
  rest="${row#??}"
  if [ "$kind" = "H" ]; then
    _tui_row_text[idx]="--- $rest ---"
  else
    local val desc
    val="$(_effective_value "$rest")"
    desc="$(_key_description "$rest")"
    _tui_row_text[idx]="$(printf '%-30s %-14s %s' "$rest" "$val" "$desc")"
  fi
}

_tui_refresh_all_rows() {
  local i total=${#_TUI_ROWS[@]}
  for ((i = 0; i < total; i++)); do
    _tui_refresh_row "$i"
  done
}

# Buffered single-write redraw: the whole frame is built into $frame first
# (pure string concatenation, no forks) and written with exactly one
# `printf` call at the end, instead of ~20 separate printf/echo calls each
# doing their own write(2). `\033[H` repositions the cursor without
# clearing; each line ends with `\033[K` (clear-to-end-of-line) so a
# shorter new line overwrites a longer old one in place, and a trailing
# `\033[J` (clear-to-end-of-screen) mops up if this frame has fewer total
# lines than the last one (e.g. after a resize). No `\033[2J` full-screen
# clear anywhere -- that was the other main source of the reported
# flicker: a full clear followed by many small writes leaves a visible
# blank-then-repaint flash on every single keypress.
#
# The preview panel only re-renders statusline.sh when _tui_dirty=1 (set by
# an actual value change, never by pure navigation) -- arrow-key spam must
# not spawn a fresh jq/git/ccusage-cache-read subprocess chain on every
# keypress, consistent with this project's subprocess-minimization
# principle. Padded/truncated to exactly 3 content lines regardless of how
# many lines statusline.sh actually printed (e.g. no active ccusage session
# renders fewer lines) so the layout never jumps around.
_tui_render() {
  if [ "$_tui_dirty" -eq 1 ]; then
    _tui_last_preview="$(_preview_json | bash "$(_statusline_bin)" 2>/dev/null)"
    _tui_dirty=0
  fi
  _tui_term_size
  local vp total end idx kind li=0 line frame
  local plines=()
  while IFS= read -r line; do
    plines+=("$line")
  done <<<"$_tui_last_preview"

  frame=$'\033[H'
  frame+='──────────────────────────── Live Preview ────────────────────────────'$'\033[K\n'
  for ((li = 0; li < 3; li++)); do
    frame+="${plines[$li]:-}"$'\033[K\n'
  done
  frame+='────────────────────────────────────────────────────────────────────'$'\033[K\n'
  frame+=$'\033[K\n'
  frame+="claude-statusline configure  (config: ${_tui_config_path})"$'\033[K\n'
  frame+=$'\033[K\n'
  vp=$(_tui_viewport_rows)
  total=${#_TUI_ROWS[@]}
  end=$((_tui_scroll_top + vp))
  [ "$end" -gt "$total" ] && end=$total
  for ((idx = _tui_scroll_top; idx < end; idx++)); do
    kind="${_TUI_ROWS[$idx]:0:1}"
    if [ "$kind" = "H" ]; then
      frame+=$'\033[1m'"${_tui_row_text[$idx]}"$'\033[0m\033[K\n'
    elif [ "$idx" -eq "$_tui_cursor" ]; then
      frame+=$'\033[7m> '"${_tui_row_text[$idx]}"$'\033[0m\033[K\n'
    else
      frame+="  ${_tui_row_text[$idx]}"$'\033[K\n'
    fi
  done
  frame+=$'\033[K\n'
  frame+='↑↓ move   ←→ adjust   Enter/Space edit   r reset field   R reset all   q quit'$'\033[K'
  frame+=$'\033[J'
  printf '%s' "$frame"
}

# Reads one key (or one escape sequence) with the terminal already in cbreak
# mode; sets $REPLY the same way bash's own `read` (no -v) does. Doesn't
# itself touch stty/raw-mode, so the escape-sequence parsing below is unit
# testable via plain piped bytes even without a real pty (see
# tests/unit_configure_tui.bats) -- only _tui_enter()/_tui_edit_via_prompt()
# etc. need an actual terminal.
# NOTE on timeouts: bash 3.2 (macOS's stock /bin/bash -- verified against
# the actual system bash, not a Homebrew override) only accepts an INTEGER
# `read -t` timeout ("invalid timeout specification" on e.g. `-t 0.05`,
# confirmed by direct testing), so the escape-sequence follow-up reads below
# use `-t 1` rather than a sub-second value. This means a genuine lone Esc
# keypress (used as an alternate quit key) takes up to ~1s to resolve while
# `read` waits to see whether more bytes follow -- an accepted tradeoff for
# working correctly on stock macOS bash. Arrow/PgUp/PgDn sequences are
# unaffected: a real terminal sends all their bytes together, so the
# follow-up reads succeed immediately without ever hitting the timeout.
#
# NOTE on Enter: `read -n1` silently strips a bare newline byte to an empty
# string rather than storing it (confirmed by direct testing: piping a
# lone \n gives k="" with a *successful* exit status, not $'\n') -- this is
# `read`'s own line-delimiter handling, not specific to -n. A raw \r (which
# terminals normally send for Enter) is NOT stripped, and _tui_enter() below
# disables -icrnl precisely so \r reaches here undisturbed instead of being
# translated to \n at the tty layer first. The "successful read, empty k"
# branch is still handled as ENTER (not EOF) as a defensive fallback in case
# some terminal/multiplexer still delivers \n.
_read_key() {
  local k rc=0
  IFS= read -rsn1 k || rc=$?
  if [ "$rc" -ne 0 ] && [ -z "$k" ]; then
    REPLY=EOF
    return
  elif [ -z "$k" ]; then
    REPLY=ENTER
    return
  fi
  case "$k" in
    $'\033')
      local k2="" k3=""
      IFS= read -rsn1 -t 1 k2
      if [ "$k2" = "[" ]; then
        IFS= read -rsn1 -t 1 k3
        case "$k3" in
          A) REPLY=UP ;;
          B) REPLY=DOWN ;;
          C) REPLY=RIGHT ;;
          D) REPLY=LEFT ;;
          5)
            IFS= read -rsn1 -t 1 _
            REPLY=PGUP
            ;;
          6)
            IFS= read -rsn1 -t 1 _
            REPLY=PGDN
            ;;
          *) REPLY=ESC ;;
        esac
      else
        REPLY=ESC
      fi
      ;;
    $'\r' | $'\n') REPLY=ENTER ;;
    *) REPLY="CHAR:$k" ;;
  esac
}

# Saves the current stty state and switches to cbreak mode (no echo, no
# line-buffering, no CR->NL translation) plus the alternate screen buffer
# and a hidden cursor. -icrnl matters: without it the tty layer translates
# an incoming \r (what a terminal normally sends for Enter) into \n before
# _read_key() ever sees it, which `read -n1` then silently strips to an
# empty string (see the NOTE above _read_key). ISIG is left enabled (only
# -echo -icanon -icrnl are toggled), so Ctrl-C still raises SIGINT and
# reaches the INT trap registered by run_full_tui() -- that's the safety net
# that guarantees the terminal is restored even on an abrupt exit. Returns 1
# (without changing anything the caller needs to undo) if stty/raw-mode
# setup fails for any reason, so run_full_tui() can fall back to run_menu()
# instead of leaving the user stuck in a half-broken terminal state.
_tui_enter() {
  _saved_stty="$(stty -g 2>/dev/null)" || return 1
  stty -echo -icanon -icrnl min 1 time 0 2>/dev/null || return 1
  printf '\033[?1049h\033[?25l'
  return 0
}

# Idempotent by design (safe to call more than once, e.g. once from the INT/
# TERM trap and again from the normal EXIT trap) -- restores line-buffered/
# echoed input, shows the cursor, and leaves the alternate screen buffer.
_tui_cleanup() {
  # shellcheck disable=SC2086 # stty -g's output must be word-split to restore (both BSD and GNU stty)
  [ -n "${_saved_stty:-}" ] && stty $_saved_stty 2>/dev/null
  printf '\033[?25h\033[?1049l'
}

# Temporarily drops back to cooked mode (echo + cursor visible) to reuse
# _prompt_toggle()'s existing read -p/validate/write flow unchanged, instead
# of re-implementing value validation for the full TUI. Always pauses for
# an explicit Enter afterward so the user has time to read _prompt_toggle's
# own confirmation ("-> value") or rejection ("invalid value, skipped")
# message before the next full-frame redraw overwrites it.
_tui_edit_via_prompt() {
  local key="$1"
  # shellcheck disable=SC2086 # see _tui_cleanup
  stty $_saved_stty 2>/dev/null
  printf '\033[?25h\033[2J\033[H'
  _prompt_toggle "$key"
  read -r -p "  (press Enter to continue) " _
  stty -echo -icanon min 1 time 0 2>/dev/null
  printf '\033[?25l'
  _tui_refresh_row "$_tui_cursor"
  _tui_dirty=1
}

# Cycles presence/bool/tristate values in place -- no sub-prompt needed,
# unlike the numeric/color/text types which route through
# _tui_edit_via_prompt above.
_tui_cycle() {
  local key="$1" type cur
  type="$(_key_type "$key")"
  cur="$(_effective_value "$key")"
  case "$type" in
    presence)
      if [ "$cur" = "1" ]; then _delete_config_value "$key"; else _write_config_value "$key" "1"; fi
      ;;
    bool)
      if [ "$cur" = "1" ]; then _write_config_value "$key" "0"; else _write_config_value "$key" "1"; fi
      ;;
    tristate)
      case "$cur" in
        1) _write_config_value "$key" "0" ;;
        0) _delete_config_value "$key" ;; # -> auto
        *) _write_config_value "$key" "1" ;; # auto -> 1
      esac
      ;;
    *) return ;;
  esac
  _tui_refresh_row "$_tui_cursor"
  _tui_dirty=1
}

# Left/Right quick-adjust: only for color256 (0-255) and percent (0-100) --
# both small, naturally-steppable ranges. "numeric" keys (STATUSLINE_MAX_
# CONTEXT, STATUSLINE_COMPACT_WIDTH) can be arbitrarily large and are meant
# to be typed exactly, so they (and text keys) only go through Enter ->
# _tui_edit_via_prompt, same as before.
_tui_nudge() {
  local key="$1" delta="$2" type cur new hi
  type="$(_key_type "$key")"
  case "$type" in
    color256) hi=255 ;;
    percent) hi=100 ;;
    *) return ;;
  esac
  cur="$(_effective_value "$key")"
  [[ "$cur" =~ ^[0-9]+$ ]] || cur=0
  new=$((cur + delta))
  [ "$new" -lt 0 ] && new=0
  [ "$new" -gt "$hi" ] && new=$hi
  _write_config_value "$key" "$new"
  _tui_refresh_row "$_tui_cursor"
  _tui_dirty=1
}

_tui_activate_current() {
  local key type
  key="$(_tui_current_key)"
  type="$(_key_type "$key")"
  case "$type" in
    presence | bool | tristate) _tui_cycle "$key" ;;
    *) _tui_edit_via_prompt "$key" ;;
  esac
}

_tui_reset_current() {
  _delete_config_value "$(_tui_current_key)"
  _tui_refresh_row "$_tui_cursor"
  _tui_dirty=1
}

# Reuses cmd_reset()'s existing y/N confirmation flow (same cooked-mode
# dance as _tui_edit_via_prompt above).
_tui_reset_all() {
  # shellcheck disable=SC2086 # see _tui_cleanup
  stty $_saved_stty 2>/dev/null
  printf '\033[?25h\033[2J\033[H'
  cmd_reset
  read -r -p "  (press Enter to continue) " _
  stty -echo -icanon min 1 time 0 2>/dev/null
  printf '\033[?25l'
  _tui_refresh_all_rows
  _tui_dirty=1
}

run_full_tui() {
  _tui_build_rows
  _tui_row_text=()
  _tui_refresh_all_rows
  _tui_cursor="$(_tui_first_selectable)"
  if [ "$_tui_cursor" -lt 0 ]; then
    echo "configure.sh: no settings to show" >&2
    return 1
  fi
  # Cached once: the config file path never changes for the life of this
  # process, so recomputing it every _tui_render() call (a fork, via
  # $(_config_file)) would be pure per-frame waste.
  _tui_config_path="$(_config_file)"
  if ! _tui_enter; then
    echo "configure.sh: couldn't enter raw terminal mode, falling back to the menu" >&2
    run_menu
    return
  fi
  # EXIT covers normal loop exit (q/Esc/EOF, see below); INT/TERM must both
  # clean up AND stop execution immediately (a plain trap doesn't stop the
  # script on its own), hence the explicit exit 130 there. _tui_cleanup is
  # idempotent, so firing twice (INT trap, then the EXIT trap it triggers)
  # is harmless.
  trap _tui_cleanup EXIT
  trap '_tui_cleanup; exit 130' INT TERM

  _tui_scroll_top=0
  _tui_last_preview=""
  _tui_dirty=1
  local vp
  # _tui_term_size sets $_TERM_ROWS/$_TERM_COLS, read by _tui_viewport_rows()
  # (via _tui_fix_scroll below) -- must run once here before the loop, since
  # _tui_render() (the other place it's called, for resize handling) doesn't
  # run until *after* the loop's first _tui_fix_scroll call. Skipping this
  # was an unbound-variable error under `set -u` on the very first frame
  # (caught via real-pty testing with `script`, not by the non-tty-only bats
  # suite -- see the manual-verification note in the implementation plan).
  _tui_term_size

  while true; do
    _tui_fix_scroll
    _tui_render
    _read_key
    case "$REPLY" in
      UP) _tui_step -1 ;;
      DOWN) _tui_step 1 ;;
      PGUP)
        vp=$(_tui_viewport_rows)
        for ((_i = 0; _i < vp; _i++)); do _tui_step -1; done
        ;;
      PGDN)
        vp=$(_tui_viewport_rows)
        for ((_i = 0; _i < vp; _i++)); do _tui_step 1; done
        ;;
      LEFT) _tui_nudge "$(_tui_current_key)" -1 ;;
      RIGHT) _tui_nudge "$(_tui_current_key)" 1 ;;
      ENTER) _tui_activate_current ;;
      "CHAR: ") _tui_activate_current ;;
      CHAR:r) _tui_reset_current ;;
      CHAR:R) _tui_reset_all ;;
      CHAR:q | CHAR:Q | ESC | EOF) break ;;
      *) : ;;
    esac
  done

  _tui_cleanup
  trap - EXIT INT TERM
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
    "") if _is_tty; then run_full_tui; else run_menu; fi ;;
    menu) run_menu ;;
    -h|--help|help) print_help ;;
    *)
      echo "configure.sh: unknown subcommand '$sub'" >&2
      print_help >&2
      exit 1
      ;;
  esac
}

main "$@"
