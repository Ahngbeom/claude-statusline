#!/usr/bin/env bats
#
# bin/git-mr against fake glab/gh binaries (first on PATH) that answer from
# fixture files and log every call, in a throwaway repo with a fake remote.
# XDG_CACHE_HOME isolates the record cache.

load 'test_helper'

GIT_MR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/git-mr"

setup() {
  T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/bin"
  for tool in glab gh; do
    cat >"$T/bin/$tool" <<EOF
#!/bin/bash
echo "\$*" >>"$T/$tool.log"
[ -f "$T/$tool.rc" ] && exit "\$(cat "$T/$tool.rc")"
case "\$*" in
  *"merge_requests?"*) cat "$T/list.json" ;;
  *merge_requests/*)   cat "$T/mr.json" ;;
  *)                   cat "$T/gh.json" ;;
esac
EOF
    chmod +x "$T/bin/$tool"
  done
  git init --quiet -b feat/x "$T/repo"
  git -C "$T/repo" remote add origin https://git.example.com/grp/sub/proj.git
  export XDG_CACHE_HOME="$T/cache" PATH="$T/bin:$PATH"
}

gitlab_mr() {
  echo '[{"iid":7}]' >"$T/list.json"
  jq -n --argjson extra "$1" '{iid:7, web_url:"https://git.example.com/grp/sub/proj/-/merge_requests/7", draft:false,
    detailed_merge_status:"mergeable", has_conflicts:false,
    head_pipeline:{status:"success", web_url:"https://git.example.com/grp/sub/proj/-/pipelines/3"}} + $extra' >"$T/mr.json"
}

record() { "$GIT_MR" --refresh "$T/repo"; }

@test "git-mr: mergeable GitLab MR with a green pipeline" {
  gitlab_mr '{}'
  run record
  [ "$status" -eq 0 ]
  [ "$output" = $'mr\t7\thttps://git.example.com/grp/sub/proj/-/merge_requests/7\tok\tsuccess\thttps://git.example.com/grp/sub/proj/-/pipelines/3' ]
  grep -q 'projects/grp%2Fsub%2Fproj/merge_requests?state=opened&source_branch=feat%2Fx' "$T/glab.log"
  grep -q -- '--hostname git.example.com' "$T/glab.log"
}

@test "git-mr: GitLab states map to draft / bad / pending, pipelines to failed / running / canceled" {
  gitlab_mr '{"draft":true}';                                                        run record; [ "$(cut -f4,5 <<<"$output")" = $'draft\tsuccess' ]
  gitlab_mr '{"detailed_merge_status":"need_rebase","head_pipeline":{"status":"failed"}}'; run record; [ "$(cut -f4,5 <<<"$output")" = $'bad\tfailed' ]
  gitlab_mr '{"has_conflicts":true}';                                                run record; [ "$(cut -f4 <<<"$output")" = bad ]
  gitlab_mr '{"detailed_merge_status":"ci_still_running","head_pipeline":{"status":"pending"}}'; run record; [ "$(cut -f4,5 <<<"$output")" = $'pending\trunning' ]
  gitlab_mr '{"head_pipeline":{"status":"skipped"}}';                                run record; [ "$(cut -f5 <<<"$output")" = canceled ]
  gitlab_mr '{"head_pipeline":null}';                                                run record; [ "$(cut -f5,6 <<<"$output")" = $'\t' ]
}

@test "git-mr: no open MR gives an empty record, and git mr says so" {
  echo '[]' >"$T/list.json"
  run record
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cd "$T/repo"
  run "$GIT_MR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no open merge request for feat/x on git.example.com/grp/sub/proj"* ]]
}

@test "git-mr: GitHub remote goes through gh; review and checks are rolled up" {
  git -C "$T/repo" remote set-url origin git@github.com:o/r.git
  echo '[{"number":12,"url":"https://github.com/o/r/pull/12","isDraft":false,"reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"},{"conclusion":"FAILURE"}]}]' >"$T/gh.json"
  run record
  [ "$output" = $'pr\t12\thttps://github.com/o/r/pull/12\tok\tfailed\thttps://github.com/o/r/pull/12/checks' ]
  grep -q -- '-R github.com/o/r --head feat/x --state open' "$T/gh.log"
  [ ! -f "$T/glab.log" ]
}

@test "git-mr: a fresh cache is served without calling the API" {
  gitlab_mr '{}'
  record >/dev/null
  rm -f "$T/glab.log"
  run "$GIT_MR" --cached "$T/repo"
  [ "$(cut -f2 <<<"$output")" = 7 ]
  [ ! -f "$T/glab.log" ]
}

@test "git-mr: a failed lookup keeps the last record" {
  gitlab_mr '{}'
  record >/dev/null
  echo 1 >"$T/glab.rc"
  run record
  [ "$(cut -f2 <<<"$output")" = 7 ]
}

@test "git-mr: the MR is looked up by the upstream branch name, not the local one" {
  gitlab_mr '{}'
  git -C "$T/repo" commit --quiet --allow-empty -m init
  git -C "$T/repo" update-ref refs/remotes/origin/feat/remote-x HEAD
  git -C "$T/repo" config branch.feat/x.remote origin
  git -C "$T/repo" config branch.feat/x.merge refs/heads/feat/remote-x
  record >/dev/null
  grep -q 'source_branch=feat%2Fremote-x' "$T/glab.log"
}

@test "git-mr: --segment is colored and linked; =bash wraps escapes as zero-width" {
  gitlab_mr '{}'
  record >/dev/null
  run "$GIT_MR" --segment "$T/repo"
  [ "$output" = $'\033[32m\033]8;;https://git.example.com/grp/sub/proj/-/merge_requests/7\a!7\033]8;;\a\033[0m \033[32m\033]8;;https://git.example.com/grp/sub/proj/-/pipelines/3\a✔\033]8;;\a\033[0m' ]
  run env GIT_MR_LINKS=0 "$GIT_MR" --segment=bash "$T/repo"
  [ "$output" = $'\\[\033[32m\\]!7\\[\033[0m\\] \\[\033[32m\\]✔\\[\033[0m\\]' ]
}

@test "git-mr: outside a repo it prints nothing and succeeds" {
  run "$GIT_MR" --cached "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
