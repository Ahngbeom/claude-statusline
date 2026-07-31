#!/bin/bash
# claude-statusline - A detailed statusline for Claude Code CLI
# Repository: https://github.com/ahngbeom/claude-statusline
# Version: 1.11.0
# License: MIT
#
# Features:
#   Line 1: Directory + Git branch (dirty */ahead-behind ↑↓) │ Model, CLI version, Output style,
#           session launch flags (⌘ -c / plan / bypass ...)
#   Line 2: Context usage (▰▱ bar) │ Session time + tokens │ Cache + Speed
#   Line 3: Daily │ Weekly │ Monthly usage and costs
#   Compact mode: auto-shrinks the above on narrow terminals (see STATUSLINE_COMPACT below)
#   Per-user customization: sibling configure.sh CLI/TUI persists settings to
#   ~/.claude/statusline.conf, including per-element colors/icons/thresholds/
#   separator (see "Changes (v1.9.0)" below)
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
#   STATUSLINE_COMPACT=1/0      Force compact layout on/off, overriding $COLUMNS
#   STATUSLINE_COMPACT_WIDTH=<n> Compact-mode auto-trigger threshold (default 80)
#   STATUSLINE_CONFIG_FILE=<path> Override the ~/.claude/statusline.conf path
#   STATUSLINE_SHOW_GIT=1/0          Line 1 git branch segment (default 1)
#   STATUSLINE_SHOW_GIT_STATUS=1/0   Dirty(*)/ahead-behind(↑↓) markers only (default 1)
#   STATUSLINE_SHOW_CC_VERSION=1/0   Line 1 CLI version (default 1)
#   STATUSLINE_SHOW_OUTPUT_STYLE=1/0 Line 1 output style (default 1)
#   STATUSLINE_SHOW_MEM=1/0          Line 1 memory indicator (default 1)
#   STATUSLINE_SHOW_SESSION_CMD=1/0  Line 1 session launch flags (default 1)
#   STATUSLINE_SESSION_CMD=<cmd>     Override the auto-detected launch command
#                                    (e.g. "claude -c"); still filtered by the
#                                    same flag whitelist, never printed as-is
#   STATUSLINE_SHOW_SESSION=1/0      Line 2 Session segment (default 1)
#   STATUSLINE_SHOW_CACHE=1/0        Line 2 cache hit rate (default 1)
#   STATUSLINE_SHOW_SPEED=1/0        Line 2 tokens/min (default 1)
#   STATUSLINE_SHOW_TODAY=1/0        Line 3 Today (default 1)
#   STATUSLINE_SHOW_WEEK=1/0         Line 3 Week (default 1)
#   STATUSLINE_SHOW_MONTH=1/0        Line 3 Month (default 1)
#   STATUSLINE_SEP_CHAR=<str>        Separator character, all lines (default │)
#   STATUSLINE_COLOR_DIR/_MODEL/_GIT/_CC_VERSION/_OUTPUT_STYLE/_SEP/_CACHE/
#     _TODAY/_WEEK/_MONTH=<0-255>    Per-element 256-color code override
#   STATUSLINE_COLOR_CTX_OK/_WARN/_CRIT=<0-255>       Context bar 3-tier colors
#   STATUSLINE_COLOR_SESSION_OK/_WARN/_CRIT=<0-255>   Session 3-tier colors
#   STATUSLINE_COLOR_MEM_OK/_WARN/_CRIT=<0-255>       Mem indicator 3-tier colors
#   STATUSLINE_ICON_DIR/_CONTEXT/_COST/_CACHE/_MEM=<str> Per-element icon override
#   STATUSLINE_THRESHOLD_CTX_WARN/_CRIT=<0-100>       Context remaining % cutoffs (default 40/20)
#   STATUSLINE_THRESHOLD_MEM_WARN/_CRIT=<0-100>       Memory used % cutoffs (default 60/80)
#   STATUSLINE_THRESHOLD_SESSION_WARN/_CRIT=<0-100>   Session remaining % cutoffs (default 25/10)
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

# Changes (v1.6.0):
#   - Line 2 Session pct/remaining-time now prefer rate_limits.five_hour
#     (server-measured used_percentage/resets_at) over the ccusage active
#     block's startTime/usageLimitResetTime when fresh (resets_at still in
#     the future). ccusage's block is a floating anchor keyed off the first
#     activity timestamp after a >5h-idle gap, so it can drift from the
#     server's real rolling 5h window -- the same gap cc-menutor's reset-
#     anchor auto-sync works around by reading rate-limits-cache.json
#     secondhand. This script already receives rate_limits firsthand via
#     stdin, so it now uses it directly instead of only forwarding it.
#     ccusage remains the source for tot_tokens/cost_usd/tpm/cache_hit_rate
#     (rate_limits has no equivalent) and Session still requires an active
#     ccusage block to render at all -- absent/stale rate_limits silently
#     falls back to the ccusage estimate, unchanged from prior versions.

# Changes (v1.6.1):
#   - Fixed a locale bug: printf '%.2f'/'%.0f' both parse AND render through
#     LC_NUMERIC, so under a comma-decimal locale (e.g. de_DE.UTF-8) they
#     failed to parse jq-emitted "12.34"-style strings ("invalid number"),
#     silently substituting 0. Replaced with pure-bash round_money() (cents,
#     used for Session/Today/Week/Month costs) and round_half_up_int()
#     (whole numbers, used for the rate_limits session % override and the
#     tokens/min burn rate) -- both always produce period-decimal output
#     regardless of locale.
#   - rate_limits.five_hour.used_percentage/resets_at are now type-checked
#     in the parsing jq call (must be a JSON number); a malformed shape no
#     longer risks breaking Line 1 parsing.
#   - rate_limits.five_hour session override is now upper-bounded to 6h
#     (5h window + 1h buffer): guards against a resets_at unit mismatch
#     (e.g. milliseconds instead of seconds) or clock skew rendering an
#     absurd remaining time instead of silently falling back to ccusage.

# Changes (v1.7.0):
#   - Added a compact layout for narrow terminals (e.g. tablet/mobile-style
#     portrait split panes): Line 1 drops cc_version/output_style/Mem and
#     shows the directory basename only, Line 2 drops the "Context" label
#     word and uses a narrower progress bar, Line 3 collapses Session +
#     Today/Week/Month/Cache/Speed down to "Sess <cost> <time> │ Today
#     <cost>" only.
#   - Auto-triggered when $COLUMNS is below STATUSLINE_COMPACT_WIDTH
#     (default 80); STATUSLINE_COMPACT=1/0 forces the mode regardless of
#     width. $COLUMNS/$LINES are set by Claude Code >= v2.1.153 right before
#     running this script (not part of the stdin JSON) -- on older Claude
#     Code, or when $COLUMNS is unset/non-numeric, this silently falls back
#     to the existing full layout (same graceful-degradation contract as
#     everything else in this script).

# Changes (v1.8.0):
#   - Added a per-user config file: ~/.claude/statusline.conf (KEY=VALUE,
#     overridable via STATUSLINE_CONFIG_FILE) is parsed at startup and used
#     to seed any of the 17 recognized settings that aren't already set as
#     an env var -- env vars always win. Parsed line-by-line into an
#     allowlist (never `source`d, so a malformed/tampered file can't run
#     arbitrary shell), costs zero subprocess forks. Written by the new
#     sibling configure.sh CLI/TUI (see repo root), which lets a user
#     persist their preferences interactively instead of exporting env vars
#     in their shell profile every session.
#   - Added 11 new STATUSLINE_SHOW_*=1/0 toggles (default 1/shown) for
#     finer-grained control over which segments render, on top of the
#     existing STATUSLINE_HIDE_COST blanket switch: STATUSLINE_SHOW_GIT,
#     STATUSLINE_SHOW_GIT_STATUS (dirty/ahead-behind only, branch name
#     still controlled by SHOW_GIT), STATUSLINE_SHOW_CC_VERSION,
#     STATUSLINE_SHOW_OUTPUT_STYLE, STATUSLINE_SHOW_MEM, STATUSLINE_SHOW_SESSION,
#     STATUSLINE_SHOW_CACHE, STATUSLINE_SHOW_SPEED, STATUSLINE_SHOW_TODAY,
#     STATUSLINE_SHOW_WEEK, STATUSLINE_SHOW_MONTH.
#   - Disabling a segment also skips the subprocess(es) that computed it,
#     consistent with this script's existing subprocess-minimization
#     principle: SHOW_GIT=0 skips the git plumbing entirely, SHOW_MEM=0
#     skips get_mem_usage() (as does compact mode, which never renders Mem
#     regardless), and update_cache_background() now skips the
#     `ccusage daily/weekly/monthly` calls individually when their matching
#     SHOW_TODAY/WEEK/MONTH is 0 (and skips the background update entirely
#     when none of Session/Cache/Speed/Today/Week/Month are enabled).
#     `ccusage blocks` itself always still runs when the background update
#     runs at all, since its result also gates whether daily/weekly/monthly
#     get persisted to the cache file.

# Changes (v1.9.0):
#   - Per-element color customization: 19 new STATUSLINE_COLOR_*=<0-255>
#     settings (see "Environment variables" above) override the raw
#     xterm-256 code used for each rendered element, including the 3-tier
#     colors for the context bar, Session segment, and Mem indicator.
#     Resolved once at startup via a new _resolve_color() helper (plain
#     printf -v, zero subprocess forks even across 19 calls); an
#     out-of-range or non-numeric override silently falls back to the
#     existing hardcoded default, same graceful-degradation contract as
#     everywhere else in this script. NO_COLOR=1 still disables all color
#     output regardless of any STATUSLINE_COLOR_* override.
#   - Per-element icon customization: 5 new STATUSLINE_ICON_*=<str> settings
#     replace the 📂/🧠/💰/🗄/💻 prefixes.
#   - Color-threshold customization: 6 new STATUSLINE_THRESHOLD_*=<0-100>
#     settings override the cutoffs that pick which 3-tier color renders
#     (context remaining %, memory used %, session remaining %) -- previously
#     hardcoded 20/40, 60/80, 10/25.
#   - Separator customization: STATUSLINE_SEP_CHAR=<str> replaces the │
#     character used between segments on every line (default unchanged).
#   - All 31 new settings are persistable via the sibling configure.sh
#     CLI/TUI (three new value types: color256, text, percent) and via
#     ~/.claude/statusline.conf, matched by STATUSLINE_COLOR_*/
#     STATUSLINE_ICON_*/STATUSLINE_THRESHOLD_*/STATUSLINE_SEP_CHAR
#     prefix-glob case arms in the config-file allowlist rather than
#     enumerating all 31 keys -- printf -v still only ever assigns into a
#     valid bash identifier, so this doesn't change the "never eval/source
#     the config file" safety property.
#   - Removed _version/_usage/_cost/_burn color variables: dead code left
#     over from an earlier design, confirmed unused by every rendering path
#     (same cleanup principle as v1.3.5's session_txt/fmt_time_hm() removal).

# Changes (v1.9.1):
#   - configure.sh's interactive menu (run with no arguments) now redraws
#     with an always-current "Live Preview" panel on top -- statusline.sh
#     rendered with your current settings -- both on every screen and again
#     immediately after any value you change, instead of requiring a
#     separate "Preview statusline" menu action to see the effect. No
#     statusline.sh behavior changes; this is a configure.sh-only UX change,
#     logged here since the project keeps a single changelog rather than a
#     separate CHANGELOG.md (see CLAUDE.md "Versioning & Release").
#   - The screen-clear between redraws only fires when stdout is a real
#     terminal ([ -t 1 ]) -- piped/redirected output (including scripting
#     and test harnesses) never sees the escape sequence.
#   - Fixed a latent infinite-loop bug in configure.sh's menu: hitting EOF
#     (Ctrl-D, or stdin running out) at the "> " prompt left the loop
#     spinning forever re-reading an already-closed stdin instead of
#     exiting, since the read failure's empty result fell through to the
#     "unknown choice" branch rather than being treated as exit.

# Changes (v1.10.0):
#   - configure.sh's interactive entry point (run with no arguments) now
#     opens a full arrow-key TUI when stdout/stdin are a real terminal: a
#     single scrollable list of every setting (headers per category, cursor
#     skips them) navigated with Up/Down/PgUp/PgDn, Enter/Space to
#     toggle/edit, Left/Right to nudge color256/percent values by 1, r/R to
#     reset one field/everything, q/Esc to quit. The "Live Preview" panel
#     from v1.9.1 is now pinned at a fixed position at the top of the screen
#     (alternate screen buffer) instead of scrolling away as prompts
#     accumulate below it -- addresses user-reported feedback that the v1.9.1
#     panel was hard to keep track of once you changed more than one setting
#     in a category, and that there was no way to navigate without typing
#     numbers.
#   - Piped/non-interactive stdin (scripts, CI, the bats test suite) and the
#     explicit `configure.sh menu` subcommand both still get the v1.9.1
#     numbered-menu flow unchanged -- same graceful-degradation contract as
#     NO_COLOR/STATUSLINE_COMPACT elsewhere in this project. Raw terminal
#     mode is only ever entered when there's a real pty to use it on.
#   - Pure navigation (Up/Down/PgUp/PgDn) never re-invokes statusline.sh --
#     only a committed value change does, and the full-frame redraw reuses
#     the last rendered preview text otherwise. Arrow-key repeats don't spawn
#     a fresh jq/git/ccusage-cache-read subprocess chain per keypress.
#   - Ctrl-C/SIGTERM during the TUI are caught by a trap that restores the
#     terminal (cooked mode, cursor visible, alternate screen buffer exited)
#     before the process exits, so an abrupt exit can't leave the terminal
#     in a broken state. Verified against a real pty (via `script`), not
#     just unit-testable pieces -- see the implementation notes for what was
#     and wasn't covered by the automated test suite.
#   - No new external dependency: terminal control is raw ANSI/CSI escape
#     sequences (same convention as statusline.sh's own hand-written color
#     codes) plus `stty`, not `tput`/`dialog`/`whiptail`/`fzf`.

# Changes (v1.10.1):
#   - Fixed severe flicker/stutter in configure.sh's v1.10.0 full TUI,
#     reported after real-world use. Two causes, both fixed:
#     1. Every redraw did a full-screen clear (`\033[2J`) followed by ~20
#        separate printf/echo calls -- each its own write(2) -- leaving a
#        visible blank-flash-then-partial-repaint on every keypress. Now a
#        single frame string is built via pure concatenation and written
#        with exactly one `printf` call; `\033[H` (home, no clear) plus a
#        per-line `\033[K` (clear-to-end-of-line) and a trailing `\033[J`
#        (clear-to-end-of-screen) replace the full clear.
#     2. Every redraw re-resolved every visible row's value/description via
#        _effective_value()/_key_description() (each a subshell fork) even
#        on pure cursor movement -- with a ~12-row viewport that's up to
#        ~36 forks per single arrow-key press. A new _tui_row_text[] cache
#        (see _tui_refresh_row()/_tui_refresh_all_rows()) now holds each
#        row's rendered text, recomputed only when that row's underlying
#        value actually changes, not on every render -- pure navigation is
#        now fork-free for row rendering. Confirmed by direct testing that
#        bash 3.2 (macOS stock bash) rejects `printf -v "arr[$idx]"`
#        (array-subscript target) -- plain `arr[$idx]=value` assignment
#        works fine and is used instead.
#   - The config file path shown in the TUI header is now resolved once at
#     startup instead of forked via $(_config_file) on every redraw.
#   - No behavior change to what's displayed or how editing works -- purely
#     a rendering/performance fix, re-verified against a real pty (Ctrl-C
#     recovery, value-change/preview-refresh correctness, no `\033[2J` in
#     the output stream).

# Changes (v1.10.2):
#   - Security fix (P1, flagged by an automated PR #6 review): a tampered
#     ~/.claude/statusline.conf line whose key looked like an array
#     subscript -- e.g. `STATUSLINE_COLOR_DIR[$(some command)]=196` --
#     matched the v1.9.0 prefix-glob allowlist arm (glob `*` matches
#     `[...]` too) and could execute the embedded command on every
#     statusline render. The review flagged `printf -v` as the trigger;
#     direct testing (bash -x tracing) found the actual trigger one line
#     earlier: `${!_cfg_key+x}` (indirect parameter expansion) evaluates
#     array-subscript command substitutions when resolving what looks like
#     an array reference, and it reproduces on every bash version tested
#     including 3.2 (macOS stock bash) -- this is not the same
#     bash-version-dependent gap printf -v's own array-target support is.
#     Fixed by rejecting any key containing a character outside
#     [A-Za-z0-9_] as the first thing done with it in that arm, before
#     `_cfg_key` is used in any expansion at all. The exact-match keys
#     enumerated separately above were never affected (a `case` exact match
#     can't match a string containing `[...]` in the first place, so a
#     malicious key never reaches their body).

# Changes (v1.11.0):
#   - Line 1 now shows which CLI flags this session was started with, e.g.
#     "⌘ -c plan effort:high". Motivation: with several sessions open there
#     was nothing on screen to tell a fresh session from a `claude -c` one,
#     or to flag a window running with --dangerously-skip-permissions.
#   - The data is NOT in the stdin JSON. Claude Code builds the statusLine
#     payload by spreading its shared hook helper with no arguments, so
#     `permission_mode` comes out undefined and is dropped, and no CLI
#     argument is forwarded at all (verified against the v2.1.220 binary and
#     the documented full schema). So this reads the argv of the nearest
#     ancestor `claude` process instead -- our own parent -- walking up at
#     most 3 levels to get past any intermediate shell.
#   - Cost: zero forks on Linux (/proc/<pid>/cmdline read in pure bash),
#     normally one `ps` fork on macOS/BSD (a single call returns the parent's
#     argv and the grandparent pid together). Skipped entirely in compact
#     mode and when STATUSLINE_SHOW_SESSION_CMD=0 -- the work is skipped, not
#     just the render, same rule as STATUSLINE_SHOW_MEM.
#   - Rendering is a flag whitelist, not a pass-through. Real argv carries
#     --append-system-prompt <hundreds of chars>, --mcp-config <path that may
#     embed a token> and --agents <json>; those render as +sysprompt/+mcp/
#     +agents with the value dropped. Values that ARE shown
#     (--permission-mode/--effort/--agent/--teammate-mode) must match
#     [A-Za-z0-9._-]{1,20} or the value is dropped and only the flag name
#     renders, so an argv carrying an ANSI escape or newline can't corrupt
#     Line 1. Output is deduped and hard-capped at 40 chars.
#   - Caveat: this is *launch* argv, so --permission-mode here is the startup
#     value and does not follow a mid-session Shift+Tab change. The live
#     value isn't in stdin either, and the transcript JSONL's
#     {"type":"permission-mode"} records carry no timestamp, so tail-scanning
#     for "the latest one" isn't trustworthy enough to build on.
#   - New settings: STATUSLINE_SHOW_SESSION_CMD (default 1),
#     STATUSLINE_SESSION_CMD (override the detected command -- an escape
#     hatch for wrapper/multiplexer process chains the ancestor walk can't
#     reach; it feeds the same whitelist, so it is not a way to print
#     arbitrary text), STATUSLINE_COLOR_SESSION_CMD, STATUSLINE_ICON_SESSION_CMD.

# Reads all of stdin without forking `cat`: read -d '' consumes up to EOF
# (no NUL byte appears in JSON input) and populates $input directly.
IFS= read -r -d '' input

# ---- user config file (per-user customization via configure.sh) ----
# ~/.claude/statusline.conf holds KEY=VALUE persisted settings written by the
# sibling configure.sh CLI/TUI, so users don't have to export env vars in
# their shell profile every session. Deliberately NOT `source`d (that would
# eval arbitrary shell) -- parsed line-by-line and only assigned into an
# allowlisted set of known keys via printf -v, same "validate before use"
# posture as every other external-input path in this script. An env var that
# is already set always wins over the config file (${!key+x} tests presence,
# not truthiness, so an explicitly empty env var still counts as "set").
STATUSLINE_CONFIG_FILE="${STATUSLINE_CONFIG_FILE:-$HOME/.claude/statusline.conf}"
if [ -f "$STATUSLINE_CONFIG_FILE" ]; then
  while IFS='=' read -r _cfg_key _cfg_val; do
    [ -z "$_cfg_key" ] && continue
    case "$_cfg_key" in
      \#*) continue ;;
      NO_COLOR|STATUSLINE_UNICODE|STATUSLINE_HIDE_COST|STATUSLINE_COMPACT|STATUSLINE_COMPACT_WIDTH|STATUSLINE_MAX_CONTEXT|\
      STATUSLINE_SHOW_GIT|STATUSLINE_SHOW_GIT_STATUS|STATUSLINE_SHOW_CC_VERSION|STATUSLINE_SHOW_OUTPUT_STYLE|STATUSLINE_SHOW_MEM|\
      STATUSLINE_SHOW_SESSION_CMD|STATUSLINE_SESSION_CMD|\
      STATUSLINE_SHOW_SESSION|STATUSLINE_SHOW_CACHE|STATUSLINE_SHOW_SPEED|STATUSLINE_SHOW_TODAY|STATUSLINE_SHOW_WEEK|STATUSLINE_SHOW_MONTH)
        [ -n "${!_cfg_key+x}" ] && continue
        printf -v "$_cfg_key" '%s' "$_cfg_val"
        ;;
      # Prefix-glob match instead of enumerating every key (there are 31) --
      # unlike the exact-match keys above, a glob's `*` matches ANY
      # characters, including `[...]`. A tampered config line like
      #   STATUSLINE_COLOR_DIR[$(some command)]=196
      # matches this pattern with _cfg_key literally containing the array
      # subscript text. The vulnerable step turned out NOT to be the
      # printf -v below (confirmed by direct testing) -- it's
      # `${!_cfg_key+x}` right after: bash's indirect-parameter-expansion
      # (`${!name}`/`${!name+word}`) evaluates `name` as an array reference
      # when it looks like one, and evaluates any command substitution
      # inside that subscript as part of doing so, in EVERY bash version
      # tested (3.2 included -- this is not the same bash-version-dependent
      # gap `printf -v`'s array-target support is). So the very first use of
      # `$_cfg_key` in this arm -- the `${!_cfg_key+x}` presence check --
      # already executes attacker-controlled commands, before printf -v is
      # ever reached. Reported by an automated PR review (which flagged
      # printf -v; testing traced the actual trigger one line earlier).
      # Fixed by rejecting any key containing a character outside
      # [A-Za-z0-9_] as the FIRST thing in this arm, before `_cfg_key` is
      # used in any expansion context, indirect or otherwise -- the prefix
      # already guarantees these can only ever be STATUSLINE_COLOR_*/
      # ICON_*/THRESHOLD_*/SEP_CHAR names, so this can't collide with
      # something like PATH or IFS either.
      STATUSLINE_COLOR_*|STATUSLINE_ICON_*|STATUSLINE_THRESHOLD_*|STATUSLINE_SEP_CHAR)
        case "$_cfg_key" in
          *[!A-Za-z0-9_]*) continue ;;
        esac
        [ -n "${!_cfg_key+x}" ] && continue
        printf -v "$_cfg_key" '%s' "$_cfg_val"
        ;;
      *) continue ;;
    esac
  done < "$STATUSLINE_CONFIG_FILE"
fi
unset _cfg_key _cfg_val

# ---- pre-computed color variables (no subshell forks) ----
# _resolve_color: sets $REPLY to OVERRIDE (a STATUSLINE_COLOR_* value, 0-255)
# if it's a valid 256-color code, else DEFAULT (same "REPLY" convention as
# bash's own `read` builtin). No command substitution, so this costs zero
# subprocess forks even called 19x below -- same "validate before use"
# posture as the config-file loader above. REPLY is assigned unconditionally
# every call, immediately consumed by the caller, never read stale.
_resolve_color() {
  local __override="$1" __default="$2"
  if [[ "$__override" =~ ^[0-9]{1,3}$ ]] && [ "$__override" -le 255 ]; then
    REPLY="$__override"
  else
    REPLY="$__default"
  fi
}

if [ -z "$NO_COLOR" ]; then
  _resolve_color "$STATUSLINE_COLOR_DIR" 117;                  _dir=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_MODEL" 147;                _model=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_GIT" 150;                  _git=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_CC_VERSION" 249;           _ccver=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_OUTPUT_STYLE" 245;         _style=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_SESSION_CMD" 245;          _cmd=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_SEP" 240;                  _sep=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_CACHE" 120;                _cache=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_TODAY" 153;                _today=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_WEEK" 183;                 _week=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_MONTH" 216;                _month=$'\033[38;5;'"${REPLY}m"
  _ctx=$'\033[1;37m'          # default white (context - updated dynamically)
  _rst=$'\033[0m'
  # 3-tier color sets: the dynamic *_color()/inline blocks below pick one of
  # these per render instead of a hardcoded escape sequence.
  _resolve_color "$STATUSLINE_COLOR_CTX_OK" 158;               _ctx_ok=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_CTX_WARN" 215;             _ctx_warn=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_CTX_CRIT" 203;             _ctx_crit=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_SESSION_OK" 194;           _session_ok=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_SESSION_WARN" 228;         _session_warn=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_SESSION_CRIT" 210;         _session_crit=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_MEM_OK" 120;               _mem_ok=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_MEM_WARN" 220;             _mem_warn=$'\033[38;5;'"${REPLY}m"
  _resolve_color "$STATUSLINE_COLOR_MEM_CRIT" 196;             _mem_crit=$'\033[38;5;'"${REPLY}m"
else
  _dir="" _model="" _ccver="" _style="" _git="" _cmd=""
  _cache="" _today="" _week="" _month=""
  _ctx="" _sep="" _rst=""
  _ctx_ok="" _ctx_warn="" _ctx_crit=""
  _session_ok="" _session_warn="" _session_crit=""
  _mem_ok="" _mem_warn="" _mem_crit=""
fi

# ---- icon overrides (plain parameter expansion, zero forks) ----
_icon_dir="${STATUSLINE_ICON_DIR:-📂}"
_icon_ctx="${STATUSLINE_ICON_CONTEXT:-🧠}"
_icon_cost="${STATUSLINE_ICON_COST:-💰}"
_icon_cache="${STATUSLINE_ICON_CACHE:-🗄}"
_icon_mem="${STATUSLINE_ICON_MEM:-💻}"
_icon_session_cmd="${STATUSLINE_ICON_SESSION_CMD:-⌘}"

# ---- separator character override ----
_sep_char="${STATUSLINE_SEP_CHAR:-│}"

# ---- color-threshold overrides (validated once, used by the dynamic color
# blocks below instead of hardcoded 20/40/60/80/10/25) ----
_th_ctx_warn="${STATUSLINE_THRESHOLD_CTX_WARN:-40}"
[[ "$_th_ctx_warn" =~ ^[0-9]+$ ]] || _th_ctx_warn=40
_th_ctx_crit="${STATUSLINE_THRESHOLD_CTX_CRIT:-20}"
[[ "$_th_ctx_crit" =~ ^[0-9]+$ ]] || _th_ctx_crit=20
_th_mem_warn="${STATUSLINE_THRESHOLD_MEM_WARN:-60}"
[[ "$_th_mem_warn" =~ ^[0-9]+$ ]] || _th_mem_warn=60
_th_mem_crit="${STATUSLINE_THRESHOLD_MEM_CRIT:-80}"
[[ "$_th_mem_crit" =~ ^[0-9]+$ ]] || _th_mem_crit=80
_th_session_warn="${STATUSLINE_THRESHOLD_SESSION_WARN:-25}"
[[ "$_th_session_warn" =~ ^[0-9]+$ ]] || _th_session_warn=25
_th_session_crit="${STATUSLINE_THRESHOLD_SESSION_CRIT:-10}"
[[ "$_th_session_crit" =~ ^[0-9]+$ ]] || _th_session_crit=10

# ---- progress bar characters (ASCII-safe default) ----
if [ -n "$STATUSLINE_UNICODE" ]; then
  _bar_fill="▰"; _bar_empty="▱"
else
  _bar_fill="="; _bar_empty="-"
fi

# ---- compact mode detection ----
# Claude Code >= v2.1.153 sets $COLUMNS/$LINES to the real terminal size
# before running this script (stdout is captured, so tput/ioctl-based width
# detection can't see it -- see README "Compact mode"). On older Claude Code
# (or manual testing), $COLUMNS is unset/non-numeric and we fall back to the
# full layout, unchanged. STATUSLINE_COMPACT=1/0 forces the mode regardless
# of width; STATUSLINE_COMPACT_WIDTH overrides the default 80-col threshold.
#
# NOTE: this function is stateless and always judges the *current* $COLUMNS
# correctly -- but it only runs when Claude Code re-invokes this script.
# Per Claude Code's docs, that happens on a new assistant message, /compact
# finishing, a permission-mode change, or a vim-mode toggle (+ an optional
# refreshInterval timer in settings.json) -- a bare terminal resize with no
# other trigger is NOT in that list, so mid-session resizing can visibly lag
# behind $COLUMNS until the next trigger fires (confirmed by manual testing).
# That lag is a Claude Code host-app scheduling property, not a bug in this
# function -- see README "Compact Mode" for the refreshInterval workaround.
is_compact_mode() {
  local cols="$1" compact_env="$2" width_env="$3" threshold
  case "$compact_env" in
    1) echo 1; return ;;
    0) echo 0; return ;;
  esac
  threshold="${width_env:-80}"
  [[ "$threshold" =~ ^[0-9]+$ ]] || threshold=80
  if [[ "$cols" =~ ^[0-9]+$ ]] && [ "$cols" -lt "$threshold" ]; then
    echo 1
  else
    echo 0
  fi
}
_compact=$(is_compact_mode "${COLUMNS:-}" "${STATUSLINE_COMPACT:-}" "${STATUSLINE_COMPACT_WIDTH:-}")

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

# ---- pure bash money rounding (no printf '%f' locale dependency) ----
# printf '%.2f' parses AND renders through LC_NUMERIC, so under a
# comma-decimal locale (e.g. de_DE.UTF-8) it fails to parse a jq-emitted
# "12.34" string ("invalid number"), silently substituting 0 and printing
# it back with a comma. This rounds half-up using only integer arithmetic
# and string slicing (same technique as format_tokens() above), so the
# result is always period-decimal regardless of locale.
round_money() {
  local num="$1" whole cents next
  whole="${num%%.*}"
  cents="000"; [[ "$num" == *.* ]] && cents="${num#*.}000"
  next="${cents:2:1}"; cents="${cents:0:2}"
  cents=$((10#$cents))
  [ "$next" -ge 5 ] && cents=$((cents + 1))
  if [ "$cents" -ge 100 ]; then cents=0; whole=$((whole + 1)); fi
  printf '%d.%02d' "$whole" "$cents"
}

# ---- pure bash integer rounding (no printf '%.0f' locale dependency) ----
# Same locale hazard as round_money() above, for callers that only need a
# rounded whole number (session %, tokens/min) rather than two decimals.
round_half_up_int() {
  local num="$1" whole frac1
  whole="${num%%.*}"
  frac1="0"; [[ "$num" == *.* ]] && frac1="${num#*.}" && frac1="${frac1:0:1}"
  [ "$frac1" -ge 5 ] && whole=$((whole + 1))
  printf '%d' "$whole"
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

# ---- session invocation (CLI argv) ----
# Which flags this session was started with (`claude -c`, `--permission-mode
# plan`, `--dangerously-skip-permissions`, ...) is NOT available in the stdin
# JSON: Claude Code builds the statusLine payload by spreading the shared hook
# helper with no arguments, so `permission_mode` comes out undefined and is
# dropped, and no CLI argument is forwarded at all (confirmed against the
# v2.1.220 binary and the documented full schema). The one place the
# information does exist is the argv of the `claude` process itself -- which
# is our own parent -- and argv is immutable for the process lifetime, so it
# is an exact record of how the session was launched.
#
# Trade-off to keep in mind: because it is *launch* argv, `--permission-mode`
# here is the startup value. Toggling the mode mid-session (Shift+Tab) does
# not change argv, so this segment does not follow it. The live value isn't in
# stdin either; the transcript JSONL's {"type":"permission-mode"} records
# carry no timestamp, so tail-scanning them for "the latest one" isn't
# trustworthy enough to build on.

# Sets _sc_val to $1 when it is a short, plain [A-Za-z0-9._-] token that is
# safe to render verbatim, and to "" otherwise. argv is external input (it can
# come from a wrapper, a shell alias, or STATUSLINE_SESSION_CMD), and a value
# carrying an ANSI escape or a newline would corrupt Line 1 -- so anything
# outside the character class is dropped whole rather than escaped in place,
# the same "validate before use, never sanitize in place" posture as the
# config-file loader above.
_sc_sanitize() {
  _sc_val=""
  local v="${1-}"
  # Every early exit is `return 0`: "no usable value" is a normal outcome
  # reported through _sc_val, not an error -- a bare `return` would inherit
  # the failing test's status and abort any caller running under `set -e`.
  [ -n "$v" ] || return 0
  [ "${#v}" -le 20 ] || return 0
  case "$v" in *[!A-Za-z0-9._-]*) return 0 ;; esac
  _sc_val="$v"
}

# Sets REPLY to a compact rendering of the session-defining flags in the argv
# passed as "$@" (REPLY convention matches _resolve_color above: no command
# substitution, so no fork). Deliberately a whitelist, not a pass-through:
# real-world argv carries `--append-system-prompt <hundreds of chars>`,
# `--mcp-config <path that may embed a token>` and `--agents <json>`, none of
# which belong on a status line. Anything unrecognized -- including the
# positional prompt, --model (already rendered as the model name) and
# --session-id -- is skipped, and an argv with no whitelisted flag at all
# (plain `claude`) yields "" so the segment disappears entirely instead of
# rendering an empty label.
_format_session_cmd() {
  REPLY=""
  local tok label out="" seen=""
  while [ "$#" -gt 0 ]; do
    tok="$1"; shift
    label=""
    case "$tok" in
      -c|--continue)                  label="-c" ;;
      # The session id that may follow --resume is a UUID: too long for Line 1
      # and already exposed as session_id, so only the fact is rendered.
      -r|--resume)                    label="resume" ;;
      --fork-session)                 label="fork" ;;
      --dangerously-skip-permissions) label="bypass" ;;
      --bare)                         label="bare" ;;
      --worktree)                     label="wt" ;;
      --add-dir)                      label="+dir" ;;
      # Flags whose value is a path, a prompt or a JSON blob: the presence is
      # useful, the value must never reach the screen.
      --settings)                     label="+settings" ;;
      --mcp-config)                   label="+mcp" ;;
      --agents)                       label="+agents" ;;
      --system-prompt|--system-prompt-file|\
      --append-system-prompt|--append-system-prompt-file)
                                      label="+sysprompt" ;;
      -d|--debug|--verbose)           label="debug" ;;
      # Flags worth showing with their value, when the value passes
      # _sc_sanitize; otherwise the bare flag name still records that it was
      # used.
      --permission-mode)              _sc_sanitize "${1-}"; label="${_sc_val:-perm}" ;;
      --effort)                       _sc_sanitize "${1-}"; label="effort${_sc_val:+:$_sc_val}" ;;
      --agent)                        _sc_sanitize "${1-}"; label="agent${_sc_val:+:$_sc_val}" ;;
      --teammate-mode)                _sc_sanitize "${1-}"; label="teammate${_sc_val:+:$_sc_val}" ;;
    esac
    [ -n "$label" ] || continue
    # First-occurrence-wins dedup (a flag repeated on the command line, or two
    # spellings of the same one like -c/--continue, renders once).
    case "$seen" in
      *" $label "*) continue ;;
    esac
    seen="$seen $label "
    out="${out:+$out }$label"
  done
  # Hard cap so a long wrapper invocation can't push Line 1 into a wrap.
  [ "${#out}" -le 40 ] || out="${out:0:39}…"
  REPLY="$out"
}

# Sets the _session_argv array to the argv of the nearest ancestor `claude`
# process, or leaves it empty when none is found within 3 levels (which is
# also the graceful-degradation path for unusual wrapper/multiplexer process
# chains -- STATUSLINE_SESSION_CMD is the escape hatch there).
_gather_session_argv() {
  _session_argv=()
  # Explicit override: skip process probing entirely. Still goes through the
  # same _format_session_cmd whitelist as auto-detected argv, so this is an
  # input to the same filter, not a way to print arbitrary text.
  if [ -n "$STATUSLINE_SESSION_CMD" ]; then
    read -r -a _session_argv <<< "$STATUSLINE_SESSION_CMD"
    return
  fi
  local pid="$PPID" depth=0 ppid tok statline rest arg0
  local -a cur=()
  while [ "$depth" -lt 3 ] && [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ]; do
    depth=$((depth + 1))
    cur=(); ppid=""
    if [ -r "/proc/$pid/cmdline" ]; then
      # Linux: NUL-separated argv read in pure bash -- zero forks, and values
      # containing spaces stay intact as single tokens.
      while IFS= read -r -d '' tok; do cur+=("$tok"); done < "/proc/$pid/cmdline"
      if [ -r "/proc/$pid/stat" ]; then
        read -r statline < "/proc/$pid/stat"
        # Field 2 (comm) is parenthesized and can itself contain spaces and
        # parens, so cut past the last ") " before splitting: ppid is then the
        # second field of the remainder (first is state).
        statline="${statline##*') '}"
        rest="${statline#* }"
        ppid="${rest%% *}"
      fi
    else
      # macOS/BSD: a single `ps` yields the parent's argv and the grandparent
      # pid together, so the whole walk normally costs one fork. `args=` is
      # space-joined, so a value that itself contains spaces splits into extra
      # tokens -- those just fail the whitelist in _format_session_cmd and are
      # dropped, degrading to less information rather than to wrong output.
      # No with_timeout wrapper: this is a single-pid lookup (and wrapping it
      # would cost the extra fork this design is avoiding), same call as the
      # unguarded vm_stat/sysctl in get_mem_usage above.
      read -r ppid rest < <(ps -o ppid=,args= -p "$pid" 2>/dev/null) || return 0
      read -r -a cur <<< "$rest"
    fi
    [ "${#cur[@]}" -gt 0 ] || return 0
    arg0="${cur[0]##*/}"
    # Match on arg0 only. A looser "argv mentions claude" test would match the
    # intermediate shell that runs this very script (~/.claude/statusline.sh)
    # and stop the walk one level early on an argv with no session flags.
    case "$arg0" in
      claude) _session_argv=("${cur[@]}"); return ;;
      node|bun|deno)
        # npm-style install: `node .../@anthropic-ai/claude-code/cli.js ...`
        case "${cur[*]}" in
          *claude-code*|*claude/cli.js*) _session_argv=("${cur[@]}"); return ;;
        esac
        ;;
    esac
    pid="$ppid"
  done
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
  # Nothing that reads this cache is enabled -- skip the whole background
  # fetch instead of spending 4 ccusage subprocesses on unused data.
  if [ "${STATUSLINE_SHOW_SESSION:-1}" = "0" ] && [ "${STATUSLINE_SHOW_CACHE:-1}" = "0" ] \
     && [ "${STATUSLINE_SHOW_SPEED:-1}" = "0" ] && [ "${STATUSLINE_SHOW_TODAY:-1}" = "0" ] \
     && [ "${STATUSLINE_SHOW_WEEK:-1}" = "0" ] && [ "${STATUSLINE_SHOW_MONTH:-1}" = "0" ]; then
    return
  fi
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

    # blocks feeds Session/Cache/Speed *and* gates the whole cache write
    # below (daily/weekly/monthly are only persisted alongside a successful
    # blocks fetch), so it always runs whenever this function didn't return
    # early above. daily/weekly/monthly are each independently skippable.
    # shellcheck disable=SC2086 # $_to/$_ccusage_cmd hold multi-word commands; intentionally unquoted
    $_to $_ccusage_cmd blocks --json  >"$tmpdir/blocks"  2>/dev/null &
    if [ "${STATUSLINE_SHOW_TODAY:-1}" != "0" ]; then
      # shellcheck disable=SC2086
      $_to $_ccusage_cmd daily  --json --since "$today_date" >"$tmpdir/daily"  2>/dev/null &
    else
      : >"$tmpdir/daily"
    fi
    if [ "${STATUSLINE_SHOW_WEEK:-1}" != "0" ]; then
      # shellcheck disable=SC2086
      $_to $_ccusage_cmd weekly --json >"$tmpdir/weekly"  2>/dev/null &
    else
      : >"$tmpdir/weekly"
    fi
    if [ "${STATUSLINE_SHOW_MONTH:-1}" != "0" ]; then
      # shellcheck disable=SC2086
      $_to $_ccusage_cmd monthly --json >"$tmpdir/monthly" 2>/dev/null &
    else
      : >"$tmpdir/monthly"
    fi
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
    session_cost_usd transcript_path rate_limits_json rl5h_pct rl5h_reset < <(
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
      (.rate_limits // {} | tostring),
      (.rate_limits.five_hour.used_percentage as $u | if ($u|type)=="number" then $u else "" end),
      (.rate_limits.five_hour.resets_at as $r | if ($r|type)=="number" then $r else "" end)
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
  rl5h_pct=""
  rl5h_reset=""
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
if [ "${STATUSLINE_SHOW_GIT:-1}" != "0" ]; then
  IFS=$'\x1f' read -r _gb _gdirty git_behind git_ahead < <(with_timeout 2 bash -c _gather_git_info)
  if [ -n "$_gb" ]; then
    git_branch="$_gb"
    if [ "${STATUSLINE_SHOW_GIT_STATUS:-1}" != "0" ]; then
      [ -n "$_gdirty" ] && git_branch="${git_branch}*"
      git_ahead_behind=""
      [[ "$git_ahead" =~ ^[0-9]+$ ]] && [ "$git_ahead" -gt 0 ] && git_ahead_behind="${git_ahead_behind}↑${git_ahead}"
      [[ "$git_behind" =~ ^[0-9]+$ ]] && [ "$git_behind" -gt 0 ] && git_ahead_behind="${git_ahead_behind}↓${git_behind}"
      [ -n "$git_ahead_behind" ] && git_branch="${git_branch} ${git_ahead_behind}"
    fi
  fi
fi

# ---- memory usage ----
# Compact layout never renders Mem, so skip the vm_stat/proc-meminfo call
# there too, not just when STATUSLINE_SHOW_MEM=0 disables it explicitly.
mem_pct=""
if [ "$_compact" -eq 0 ] && [ "${STATUSLINE_SHOW_MEM:-1}" != "0" ]; then
  mem_pct=$(get_mem_usage)
fi

# ---- session invocation ----
# Same skip-the-work-not-just-the-render rule as Mem above: the compact layout
# doesn't render this segment, so the ancestor walk (one `ps` fork on
# macOS/BSD, zero on Linux) never happens on a narrow terminal either.
_session_cmd=""
if [ "$_compact" -eq 0 ] && [ "${STATUSLINE_SHOW_SESSION_CMD:-1}" != "0" ]; then
  _gather_session_argv
  if [ "${#_session_argv[@]}" -gt 0 ]; then
    _format_session_cmd "${_session_argv[@]}"
    _session_cmd="$REPLY"
  fi
fi

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
  if [ "$remaining_pct" -le "$_th_ctx_crit" ]; then
    _ctx="$_ctx_crit"    # coral red
  elif [ "$remaining_pct" -le "$_th_ctx_warn" ]; then
    _ctx="$_ctx_warn"    # peach
  else
    _ctx="$_ctx_ok"      # mint green
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
now_sec=${EPOCHSECONDS:-$(date +%s)}

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
      start_sec=$(to_epoch "$start_time_str"); end_sec=$(to_epoch "$reset_time_str")
      total=$(( end_sec - start_sec )); (( total<1 )) && total=1
      elapsed=$(( now_sec - start_sec )); (( elapsed<0 ))&&elapsed=0; (( elapsed>total ))&&elapsed=$total
      session_pct=$(( elapsed * 100 / total ))
      remaining=$(( end_sec - now_sec )); (( remaining<0 )) && remaining=0
      rh=$(( remaining / 3600 )); rm_val=$(( (remaining % 3600) / 60 ))
      session_bar=$(progress_bar "$session_pct" 10)
    fi
  fi

  # rate_limits.five_hour override: Claude Code's server-measured usage % and
  # reset epoch (stdin, Pro/Max subscribers only) take priority over the
  # ccusage block estimate above when fresh -- ccusage's block is a floating
  # anchor keyed off the first activity timestamp in a >5h-idle gap, so it can
  # drift from the server's real rolling 5h window (see CLAUDE.md "Usage
  # counter semantics"). Only overrides session_pct/rh/rm_val/session_bar;
  # tot_tokens/cost_usd/tpm/cache_hit_rate have no rate_limits equivalent and
  # are left as ccusage reported them. Stale (resets_at in the past, or
  # absent -- e.g. API-key users, pre-first-response) silently keeps the
  # ccusage-derived numbers above, same as session_cost_usd's stdin-over-
  # ccusage precedence elsewhere in this script.
  # Upper-bounded to 6h (5h window + 1h buffer): guards against a resets_at
  # unit mismatch (e.g. milliseconds instead of seconds) or clock skew
  # rendering an absurd remaining time instead of silently falling back.
  if [[ "$rl5h_reset" =~ ^[0-9]+$ ]] && [ "$rl5h_reset" -gt "$now_sec" ] \
     && [ "$(( rl5h_reset - now_sec ))" -le 21600 ] \
     && [[ "$rl5h_pct" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    # Round rl5h_pct via round_half_up_int() rather than `printf '%.0f'`,
    # which misparses "." as a decimal point under LC_NUMERIC locales that
    # use a comma (e.g. de_DE.UTF-8), silently producing session_pct=0.
    session_pct=$(round_half_up_int "$rl5h_pct")
    (( session_pct < 0 )) && session_pct=0
    (( session_pct > 100 )) && session_pct=100
    remaining=$(( rl5h_reset - now_sec ))
    rh=$(( remaining / 3600 )); rm_val=$(( (remaining % 3600) / 60 ))
    session_bar=$(progress_bar "$session_pct" 10)
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
  if   (( rem_pct <= _th_session_crit )); then _session="$_session_crit"   # light pink
  elif (( rem_pct <= _th_session_warn )); then _session="$_session_warn"   # light yellow
  else                                         _session="$_session_ok"     # light green
  fi
fi

# ---- render statusline ----
_ctx_bar_width=$(( _compact ? 8 : 20 ))

if [ "$_compact" -eq 1 ]; then
  # Compact layout for narrow terminals (see README "Compact mode"):
  # Line 1 drops cc_version/output_style/Mem and shows the dir basename only.
  # Line 2 drops the "Context" label word and uses a narrower bar.
  # Line 3 collapses Session+Today/Week/Month/Cache/Speed down to
  # "Sess <cost> <time>  │  Today <cost>" -- token counts, the session bar,
  # Week/Month and cache/speed are all omitted.
  printf '%s %s%s%s' "$_icon_dir" "$_dir" "${current_dir##*/}" "$_rst"
  if [ -n "$git_branch" ]; then
    printf '  %s%s%s' "$_git" "$git_branch" "$_rst"
  fi
  printf '  %s%s%s' "$_sep" "$_sep_char" "$_rst"
  printf ' %s%s%s' "$_model" "$model_name" "$_rst"

  # Line 2: 🧠 used/max bar pct%
  ctx_part=""
  if [ -n "$context_pct" ] && [ -n "$context_used_tokens" ]; then
    context_bar=$(progress_bar "$context_remaining_pct" "$_ctx_bar_width")
    used_formatted=$(format_tokens "$context_used_tokens")
    max_formatted=$(format_tokens "$context_max_tokens")
    ctx_part="${_icon_ctx} ${_ctx}${used_formatted}/${max_formatted} ${context_bar} ${context_remaining_pct}%${_rst}"
  else
    ctx_part="${_icon_ctx} ${_ctx}···${_rst}"
  fi
  line2="$ctx_part"

  # Line 3: 💰 Sess <cost> <time>  │  Today <cost>
  sess_part=""
  if [ "${STATUSLINE_SHOW_SESSION:-1}" != "0" ] && [ -n "$tot_tokens" ] && [[ "$tot_tokens" =~ ^[0-9]+$ ]]; then
    _sess_cost=""
    if [ -z "$STATUSLINE_HIDE_COST" ]; then
      if [[ "$session_cost_usd" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        _sess_cost=" \$$(round_money "$session_cost_usd")"
      elif [[ "$cost_usd" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        _sess_cost=" \$$(round_money "$cost_usd")"
      fi
    fi
    _sess_time=""
    if [ -n "$rh" ] || [ -n "$rm_val" ]; then
      _sess_time=" ${rh}h ${rm_val}m"
    fi
    if [ -n "$_sess_cost" ] || [ -n "$_sess_time" ]; then
      sess_part="${_session}Sess${_sess_cost}${_sess_time}${_rst}"
    fi
  fi

  today_part=""
  if [ -z "$STATUSLINE_HIDE_COST" ] && [ "${STATUSLINE_SHOW_TODAY:-1}" != "0" ] \
     && [ -n "$today_cost" ] && [[ "$today_cost" =~ ^[0-9.]+$ ]]; then
    today_cost_formatted=$(round_money "$today_cost")
    today_part="${_today}Today \$${today_cost_formatted}${_rst}"
  fi

  line3=""
  if [ -n "$sess_part" ]; then
    line3="${_icon_cost} ${sess_part}"
  fi
  if [ -n "$today_part" ]; then
    if [ -n "$line3" ]; then
      line3="${line3}  ${_sep}${_sep_char}${_rst} ${today_part}"
    else
      line3="${_icon_cost} ${today_part}"
    fi
  fi
else
  # Line 1: 📂 dir  branch │ model  cc_ver  style
  printf '%s %s%s%s' "$_icon_dir" "$_dir" "$current_dir" "$_rst"
  if [ -n "$git_branch" ]; then
    printf '  %s%s%s' "$_git" "$git_branch" "$_rst"
  fi
  printf '  %s%s%s' "$_sep" "$_sep_char" "$_rst"
  printf ' %s%s%s' "$_model" "$model_name" "$_rst"
  if [ "${STATUSLINE_SHOW_CC_VERSION:-1}" != "0" ] && [ -n "$cc_version" ] && [ "$cc_version" != "null" ]; then
    printf '  %sv%s%s' "$_ccver" "$cc_version" "$_rst"
  fi
  if [ "${STATUSLINE_SHOW_OUTPUT_STYLE:-1}" != "0" ] && [ -n "$output_style" ] && [ "$output_style" != "null" ]; then
    printf '  %s%s%s' "$_style" "$output_style" "$_rst"
  fi
  if [ -n "$_session_cmd" ]; then
    printf '  %s%s %s%s' "$_cmd" "$_icon_session_cmd" "$_session_cmd" "$_rst"
  fi
  if [[ "$mem_pct" =~ ^[0-9]+$ ]]; then
    if [ "$mem_pct" -ge "$_th_mem_crit" ]; then
      _mem_color="$_mem_crit"
    elif [ "$mem_pct" -ge "$_th_mem_warn" ]; then
      _mem_color="$_mem_warn"
    else
      _mem_color="$_mem_ok"
    fi
    printf '  %s%s%s %s%s Mem %d%%%s' "$_sep" "$_sep_char" "$_rst" "$_mem_color" "$_icon_mem" "$mem_pct" "$_rst"
  fi

  # Line 2: 🧠 Context ... │ Session ... │ 🗄 cache  speed
  # Build each section independently, then join with │ separators
  ctx_part=""
  if [ -n "$context_pct" ] && [ -n "$context_used_tokens" ]; then
    context_bar=$(progress_bar "$context_remaining_pct" "$_ctx_bar_width")
    used_formatted=$(format_tokens "$context_used_tokens")
    max_formatted=$(format_tokens "$context_max_tokens")
    ctx_part="${_icon_ctx} ${_ctx}Context ${used_formatted}/${max_formatted} ${context_bar} ${context_remaining_pct}%${_rst}"
  else
    ctx_part="${_icon_ctx} ${_ctx}Context ···${_rst}"
  fi

  sess_part=""
  if [ "${STATUSLINE_SHOW_SESSION:-1}" != "0" ] && [ -n "$tot_tokens" ] && [[ "$tot_tokens" =~ ^[0-9]+$ ]]; then
    tot_formatted=$(format_tokens "$tot_tokens")
    # Session cost: prefer stdin cost.total_cost_usd (real-time), fallback to ccusage blocks cost_usd
    _sess_cost=""
    if [ -z "$STATUSLINE_HIDE_COST" ]; then
      if [[ "$session_cost_usd" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        _sess_cost_num="\$$(round_money "$session_cost_usd")"
        _sess_cost=" $_sess_cost_num"
      elif [[ "$cost_usd" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        _sess_cost_num="\$$(round_money "$cost_usd")"
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
  if [ "${STATUSLINE_SHOW_CACHE:-1}" != "0" ] && [ -n "$cache_hit_rate" ] && [[ "$cache_hit_rate" =~ ^[0-9]+$ ]]; then
    meta_part="${_icon_cache} ${_cache}${cache_hit_rate}%${_rst}"
  fi
  if [ "${STATUSLINE_SHOW_SPEED:-1}" != "0" ] && [ -n "$tpm" ] && [[ "$tpm" =~ ^[0-9.]+$ ]]; then
    # Round via round_half_up_int() rather than `printf '%.0f'` -- see
    # round_money() above for why printf's %f conversion is locale-unsafe here.
    tpm_int=$(round_half_up_int "$tpm")
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
    line2="${line2}  ${_sep}${_sep_char}${_rst} ${sess_part}"
  fi
  if [ -n "$meta_part" ]; then
    line2="${line2}  ${_sep}${_sep_char}${_rst} ${meta_part}"
  fi

  # Line 3: 💰 Today ... │ Week ... │ Month ...
  line3=""
  if [ -z "$STATUSLINE_HIDE_COST" ]; then
    if [ "${STATUSLINE_SHOW_TODAY:-1}" != "0" ] && [ -n "$today_tokens" ] && [[ "$today_tokens" =~ ^[0-9]+$ ]]; then
      today_tokens_formatted=$(format_tokens "$today_tokens")
      if [ -n "$today_cost" ] && [[ "$today_cost" =~ ^[0-9.]+$ ]]; then
        today_cost_formatted=$(round_money "$today_cost")
        line3="${_icon_cost} ${_today}Today ${today_tokens_formatted}  \$${today_cost_formatted}${_rst}"
      else
        line3="${_icon_cost} ${_today}Today ${today_tokens_formatted}${_rst}"
      fi
    fi

    if [ "${STATUSLINE_SHOW_WEEK:-1}" != "0" ] && [ -n "$week_tokens" ] && [[ "$week_tokens" =~ ^[0-9]+$ ]]; then
      week_tokens_formatted=$(format_tokens "$week_tokens")
      if [ -n "$week_cost" ] && [[ "$week_cost" =~ ^[0-9.]+$ ]]; then
        week_cost_formatted=$(round_money "$week_cost")
        week_part="${_week}Week ${week_tokens_formatted}  \$${week_cost_formatted}${_rst}"
      else
        week_part="${_week}Week ${week_tokens_formatted}${_rst}"
      fi
      if [ -n "$line3" ]; then line3="${line3}  ${_sep}${_sep_char}${_rst} ${week_part}"; else line3="${week_part}"; fi
    fi

    if [ "${STATUSLINE_SHOW_MONTH:-1}" != "0" ] && [ -n "$month_tokens" ] && [[ "$month_tokens" =~ ^[0-9]+$ ]]; then
      month_tokens_formatted=$(format_tokens "$month_tokens")
      if [ -n "$month_cost" ] && [[ "$month_cost" =~ ^[0-9.]+$ ]]; then
        month_cost_formatted=$(round_money "$month_cost")
        month_part="${_month}Month ${month_tokens_formatted}  \$${month_cost_formatted}${_rst}"
      else
        month_part="${_month}Month ${month_tokens_formatted}${_rst}"
      fi
      if [ -n "$line3" ]; then line3="${line3}  ${_sep}${_sep_char}${_rst} ${month_part}"; else line3="${month_part}"; fi
    fi
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
