#!/usr/bin/env bats
#
# Line 1 PR/MR segment, fed by the stdin `pr` object Claude Code sends
# (number/url/review_state, plus kind=mr for GitLab), and the optional
# pipeline mark from a `git-mr` on PATH (faked here).

load 'test_helper'

MR_JSON='{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"},"pr":{"number":289,"url":"https://git.example.com/g/p/-/merge_requests/289","review_state":"approved","kind":"mr"}}'

pr_json() {
  jq -cn --argjson pr "$1" '{workspace:{current_dir:"/tmp/proj"},model:{display_name:"Opus 4.6"},pr:$pr}'
}

# A fake git-mr whose --cached prints the given TSV record.
fake_git_mr() {
  local dir="$1" record="$2"
  mkdir -p "$dir"
  printf '#!/bin/bash\n[ "$1" = --cached ] && printf "%%b" %q\n' "$record" >"$dir/git-mr"
  chmod +x "$dir/git-mr"
}

line1() { sed -n '1p' <<<"$output"; }

@test "golden: a GitLab merge request renders as !N after the directory" {
  run run_statusline "$MR_JSON" STATUSLINE_HYPERLINKS=0
  [ "$status" -eq 0 ]
  [[ "$(line1)" == *"/tmp/proj  !289  │ Opus 4.6"* ]]
}

@test "golden: a GitHub pull request (no kind) renders as #N" {
  run run_statusline "$(pr_json '{"number":12,"url":"https://github.com/o/r/pull/12","review_state":"changes_requested"}')" STATUSLINE_HYPERLINKS=0
  [ "$status" -eq 0 ]
  [[ "$(line1)" == *"/tmp/proj  #12  │"* ]]
}

@test "golden: a draft is labelled draft" {
  run run_statusline "$(pr_json '{"number":12,"url":"https://github.com/o/r/pull/12","review_state":"draft"}')" STATUSLINE_HYPERLINKS=0
  [[ "$(line1)" == *"  #12 draft  │"* ]]
}

@test "golden: no pr object, no segment" {
  run run_statusline '{"workspace":{"current_dir":"/tmp/proj"},"model":{"display_name":"Opus 4.6"}}'
  [[ "$(line1)" == *"/tmp/proj  │ Opus 4.6"* ]]
}

@test "golden: STATUSLINE_SHOW_PR=0 hides the segment" {
  run run_statusline "$MR_JSON" STATUSLINE_SHOW_PR=0
  [[ "$(line1)" == *"/tmp/proj  │ Opus 4.6"* ]]
}

@test "golden: the number is an OSC 8 link to the PR/MR by default" {
  run run_statusline "$MR_JSON"
  [[ "$(line1)" == *$'\033]8;;https://git.example.com/g/p/-/merge_requests/289\a!289\033]8;;\a'* ]]
}

@test "golden: a URL with terminal control characters is not linked" {
  run run_statusline "$(pr_json '{"number":5,"url":"https://evil.example/\u001b]0;pwned\u0007","review_state":"pending"}')"
  [[ "$(line1)" == *"  #5  │"* ]]
  [[ "$output" != *pwned* ]]
}

@test "golden: a non-numeric PR number renders nothing" {
  run run_statusline "$(pr_json '{"number":"12; echo hi","url":"https://github.com/o/r/pull/12"}')"
  [[ "$(line1)" == *"/tmp/proj  │ Opus 4.6"* ]]
}

@test "golden: compact mode keeps the PR/MR number" {
  run run_statusline "$MR_JSON" STATUSLINE_HYPERLINKS=0 STATUSLINE_COMPACT=1
  [[ "$(line1)" == *"proj  !289  │"* ]]
}

@test "golden: review state picks the PR color (approved = PR_OK, overridable)" {
  run run_statusline_colored "$MR_JSON" STATUSLINE_HYPERLINKS=0 STATUSLINE_SHOW_SESSION_CMD=0
  [[ "$(line1)" == *$'\033[38;5;114m!289\033[0m'* ]]
  run run_statusline_colored "$MR_JSON" STATUSLINE_HYPERLINKS=0 STATUSLINE_COLOR_PR_OK=46
  [[ "$(line1)" == *$'\033[38;5;46m!289\033[0m'* ]]
}

@test "golden: git-mr's cached pipeline state is appended for the same MR" {
  fake_git_mr "$BATS_TEST_TMPDIR/bin" 'mr\t289\thttps://x/289\tok\tsuccess\thttps://git.example.com/g/p/-/pipelines/9'
  run run_statusline "$MR_JSON" STATUSLINE_HYPERLINKS=0 "PATH=$BATS_TEST_TMPDIR/bin:$PATH"
  [[ "$(line1)" == *"  !289 ✔  │"* ]]
}

@test "golden: the pipeline mark links to the pipeline" {
  fake_git_mr "$BATS_TEST_TMPDIR/bin" 'mr\t289\thttps://x/289\tok\tfailed\thttps://git.example.com/g/p/-/pipelines/9'
  run run_statusline "$MR_JSON" "PATH=$BATS_TEST_TMPDIR/bin:$PATH"
  [[ "$(line1)" == *$'\033]8;;https://git.example.com/g/p/-/pipelines/9\a✘\033]8;;\a'* ]]
}

@test "golden: a git-mr record for a different PR/MR is ignored" {
  fake_git_mr "$BATS_TEST_TMPDIR/bin" 'mr\t288\thttps://x/288\tok\tsuccess\thttps://x/p/1'
  run run_statusline "$MR_JSON" STATUSLINE_HYPERLINKS=0 "PATH=$BATS_TEST_TMPDIR/bin:$PATH"
  [[ "$(line1)" == *"  !289  │"* ]]

  fake_git_mr "$BATS_TEST_TMPDIR/bin" 'pr\t289\thttps://x/289\tok\tsuccess\thttps://x/p/1'
  run run_statusline "$MR_JSON" STATUSLINE_HYPERLINKS=0 "PATH=$BATS_TEST_TMPDIR/bin:$PATH"
  [[ "$(line1)" == *"  !289  │"* ]]
}

@test "golden: a git-mr record with no pipeline adds no mark" {
  fake_git_mr "$BATS_TEST_TMPDIR/bin" 'mr\t289\thttps://x/289\tok\t\thttps://x/checks'
  run run_statusline "$MR_JSON" STATUSLINE_HYPERLINKS=0 "PATH=$BATS_TEST_TMPDIR/bin:$PATH"
  [[ "$(line1)" == *"  !289  │"* ]]
}
