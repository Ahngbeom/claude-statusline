#!/usr/bin/env bats
# Unit tests for _format_session_cmd / _sc_sanitize (statusline.sh, see the
# "session invocation (CLI argv)" section). These cover the whole whitelist
# and value-sanitizing logic without touching the process tree, so they behave
# identically on macOS (ps path) and Linux CI (/proc path).

load test_helper

setup() {
  load_fn _sc_sanitize
  load_fn _format_session_cmd
}

@test "no whitelisted flag renders nothing (plain \`claude\`)" {
  _format_session_cmd claude
  [ "$REPLY" = "" ]
}

@test "empty argv renders nothing" {
  _format_session_cmd
  [ "$REPLY" = "" ]
}

@test "-c and --continue both render as -c" {
  _format_session_cmd claude -c
  [ "$REPLY" = "-c" ]
  _format_session_cmd claude --continue
  [ "$REPLY" = "-c" ]
}

@test "--resume renders the fact but never the session UUID" {
  _format_session_cmd claude --resume 550e8400-e29b-41d4-a716-446655440000
  [ "$REPLY" = "resume" ]
}

@test "-r short form renders as resume" {
  _format_session_cmd claude -r
  [ "$REPLY" = "resume" ]
}

@test "--permission-mode renders the mode name itself" {
  _format_session_cmd claude --permission-mode plan
  [ "$REPLY" = "plan" ]
  _format_session_cmd claude --permission-mode acceptEdits
  [ "$REPLY" = "acceptEdits" ]
}

@test "--dangerously-skip-permissions renders as bypass" {
  _format_session_cmd claude --dangerously-skip-permissions
  [ "$REPLY" = "bypass" ]
}

@test "--effort/--agent/--teammate-mode render flag:value" {
  _format_session_cmd claude --effort high --agent reviewer --teammate-mode auto
  [ "$REPLY" = "effort:high agent:reviewer teammate:auto" ]
}

@test "--append-system-prompt never leaks the prompt text" {
  _format_session_cmd claude --append-system-prompt You are a long prompt with spaces
  [ "$REPLY" = "+sysprompt" ]
}

@test "--append-system-prompt leaks nothing when the value is one argv token" {
  # Linux /proc gives NUL-separated argv, so a spacey value stays a single
  # token -- it must still be dropped, not rendered.
  _format_session_cmd claude --append-system-prompt "You are Claude Code running inside cmux"
  [ "$REPLY" = "+sysprompt" ]
}

@test "--mcp-config/--settings render presence but never the path" {
  _format_session_cmd claude --mcp-config /path/with/token.json --settings /etc/secret.json
  [ "$REPLY" = "+mcp +settings" ]
}

@test "--agents never leaks the JSON blob" {
  _format_session_cmd claude --agents '{"reviewer":{"prompt":"secret"}}'
  [ "$REPLY" = "+agents" ]
}

@test "a value carrying an ANSI escape is dropped, keeping the bare flag" {
  _format_session_cmd claude --effort $'\033[31mred'
  [ "$REPLY" = "effort" ]
  [[ "$REPLY" != *$'\033'* ]]
}

@test "a value carrying a newline is dropped, keeping the bare flag" {
  _format_session_cmd claude --agent $'evil\nname'
  [ "$REPLY" = "agent" ]
}

@test "an over-long value is dropped, keeping the bare flag" {
  _format_session_cmd claude --permission-mode aaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "$REPLY" = "perm" ]
}

@test "a missing trailing value keeps the bare flag" {
  _format_session_cmd claude --effort
  [ "$REPLY" = "effort" ]
}

@test "repeated and equivalent flags render once, in first-seen order" {
  _format_session_cmd claude -c --continue --add-dir /a --add-dir /b
  [ "$REPLY" = "-c +dir" ]
}

@test "unrecognized flags are skipped (model/session-id/name/positional)" {
  _format_session_cmd claude --model opus --session-id abc --name mysession "write me a test"
  [ "$REPLY" = "" ]
}

@test "output is capped at 40 chars with an ellipsis" {
  _format_session_cmd claude -c --resume --fork-session --bare --worktree \
    --permission-mode acceptEdits --effort xhigh --agent reviewer \
    --teammate-mode auto --add-dir /a --mcp-config /b --settings /c
  [ "${#REPLY}" -le 40 ]
  [[ "$REPLY" == *… ]]
}

@test "regression: real cmux/Orca argv renders only the safe parts" {
  _format_session_cmd /Users/me/.local/bin/claude --teammate-mode auto \
    --append-system-prompt You are Claude Code running inside cmux, started with cmux claude-teams
  [ "$REPLY" = "teammate:auto +sysprompt" ]
}

@test "_sc_sanitize accepts plain tokens and rejects everything else" {
  _sc_sanitize "acceptEdits"; [ "$_sc_val" = "acceptEdits" ]
  _sc_sanitize "gpt-4.1_x"; [ "$_sc_val" = "gpt-4.1_x" ]
  _sc_sanitize ""; [ "$_sc_val" = "" ]
  _sc_sanitize "has space"; [ "$_sc_val" = "" ]
  _sc_sanitize 'semi;colon'; [ "$_sc_val" = "" ]
  _sc_sanitize '$(id)'; [ "$_sc_val" = "" ]
  _sc_sanitize "way-too-long-value-here"; [ "$_sc_val" = "" ]
}
