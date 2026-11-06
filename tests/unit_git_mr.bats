#!/usr/bin/env bats
#
# bin/git-mr against fake glab/gh binaries (first on PATH) that answer from
# fixture files (applying gh's -q filter) and log every call, in a throwaway repo with a fake remote.
# XDG_CACHE_HOME isolates the record cache.
#
# Fixtures: glab project lookup -> project.json, MR list of project N ->
# list.N.json, MR detail -> mr.json; gh repo view -> repo.json, PR list of
# HOST/OWNER/REPO -> prs.HOST_OWNER_REPO.json. Missing lists answer [].

load 'test_helper'

GIT_MR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/git-mr"

setup() {
  T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/bin"
  cat >"$T/bin/glab" <<EOF
#!/bin/bash
echo "\$*" >>"$T/glab.log"
[ -f "$T/glab.rc" ] && exit "\$(cat "$T/glab.rc")"
url=\${!#}
case "\$url" in
  */merge_requests\?*) p=\${url#projects/}; cat "$T/list.\${p%%/*}.json" 2>/dev/null || echo '[]' ;;
  */merge_requests/*)  cat "$T/mr.json" ;;
  projects/*)          cat "$T/project.json" ;;
esac
EOF
  cat >"$T/bin/gh" <<EOF
#!/bin/bash
echo "\$*" >>"$T/gh.log"
case "\$*" in
  "repo view"*) jq -r "\${!#}" "$T/repo.json" ;;
  "pr list -R "*) r=\${4//\//_}; cat "$T/prs.\$r.json" 2>/dev/null || echo '[]' ;;
esac
EOF
  chmod +x "$T/bin/glab" "$T/bin/gh"
  echo '{"id":5,"forked_from_project":null}' >"$T/project.json"
  echo '{"parent":null}' >"$T/repo.json"
  git init --quiet -b feat/x "$T/repo"
  git -C "$T/repo" remote add origin https://git.example.com/grp/sub/proj.git
  git -C "$T/repo" config user.email "test@example.com"
  git -C "$T/repo" config user.name "Test"
  export XDG_CACHE_HOME="$T/cache" PATH="$T/bin:$PATH"
}

gitlab_mr() {
  echo '[{"iid":7,"source_project_id":5}]' >"$T/list.5.json"
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
  grep -q 'projects/grp%2Fsub%2Fproj$' "$T/glab.log"
  grep -q 'projects/5/merge_requests?state=opened&source_branch=feat%2Fx' "$T/glab.log"
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
  echo '[]' >"$T/list.5.json"
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
  echo '[{"number":12,"url":"https://github.com/o/r/pull/12","isDraft":false,"reviewDecision":"APPROVED","headRepositoryOwner":{"login":"o"},"statusCheckRollup":[{"conclusion":"SUCCESS"},{"conclusion":"FAILURE"}]}]' >"$T/prs.github.com_o_r.json"
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

@test "git-mr: a GitLab fork's MR is found in the upstream project" {
  echo '{"id":5,"forked_from_project":{"id":1}}' >"$T/project.json"
  echo '[{"iid":3,"source_project_id":99},{"iid":9,"source_project_id":5}]' >"$T/list.1.json"
  gitlab_mr '{"iid":9}'
  rm -f "$T/list.5.json"
  run record
  [ "$(cut -f2 <<<"$output")" = 9 ]
  grep -q 'projects/1/merge_requests/9$' "$T/glab.log"
}

@test "git-mr: a GitHub fork's PR is found in the parent repo, ignoring other forks' same-named branches" {
  git -C "$T/repo" remote set-url origin https://github.com/Me/r.git
  echo '{"parent":{"owner":{"login":"up"},"name":"r"}}' >"$T/repo.json"
  echo '[{"number":40,"url":"https://github.com/up/r/pull/40","isDraft":false,"reviewDecision":"","headRepositoryOwner":{"login":"someone"},"statusCheckRollup":[]},
         {"number":41,"url":"https://github.com/up/r/pull/41","isDraft":false,"reviewDecision":"","headRepositoryOwner":{"login":"me"},"statusCheckRollup":[]}]' >"$T/prs.github.com_up_r.json"
  run record
  [ "$output" = $'pr\t41\thttps://github.com/up/r/pull/41\tpending\t\thttps://github.com/up/r/pull/41/checks' ]
}

@test "git-mr: a PR without any checks keeps an empty pipeline field" {
  git -C "$T/repo" remote set-url origin git@github.com:o/r.git
  echo '[{"number":12,"url":"https://github.com/o/r/pull/12","isDraft":false,"reviewDecision":"","headRepositoryOwner":{"login":"o"},"statusCheckRollup":[]}]' >"$T/prs.github.com_o_r.json"
  cd "$T/repo"
  run env GIT_MR_LINKS=0 "$GIT_MR"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"pending  pipeline:none" ]]
  run env GIT_MR_LINKS=0 "$GIT_MR" --segment
  [ "$output" = $'\033[33m#12\033[0m' ]
}

# The segment ends up in PS1, which bash (promptvars) and zsh (PROMPT_SUBST)
# expand again on every prompt: API- or cache-supplied text must not be able
# to run commands there.
evil_mr() {
  gitlab_mr "{\"web_url\":\"https://git.example.com/x\$(touch $T/pwned-mr)\",
              \"head_pipeline\":{\"status\":\"success\",\"web_url\":\"https://git.example.com/p\`touch $T/pwned-pipe\`\"}}"
  record >/dev/null
}

@test "security: --segment drops URLs carrying shell syntax instead of linking them" {
  evil_mr
  run "$GIT_MR" --segment=bash "$T/repo"
  [ "$status" -eq 0 ]
  [[ "$output" != *'$('* ]] || false
  [[ "$output" != *'`'* ]] || false
  [ "$output" = $'\\[\033[32m\\]!7\\[\033[0m\\] \\[\033[32m\\]✔\\[\033[0m\\]' ]
}

@test "security: an evil URL does not execute when bash expands the segment as PS1" {
  evil_mr
  seg=$("$GIT_MR" --segment=bash "$T/repo")
  # An interactive bash draws the prompt (promptvars on) before reading the next line.
  printf 'PS1=%q\necho drawn\n' "$seg" | bash --norc -i >/dev/null 2>&1
  [ ! -e "$T/pwned-mr" ]
  [ ! -e "$T/pwned-pipe" ]
}

@test "security: an evil URL does not execute when zsh expands the segment with PROMPT_SUBST" {
  command -v zsh >/dev/null || skip "zsh not installed"
  evil_mr
  "$GIT_MR" --segment=zsh "$T/repo" >"$T/seg"
  # print -P runs PROMPT_SUBST command substitution like a real prompt; ${(%)p} does not
  zsh -fc 'setopt PROMPT_SUBST; p=$(<"$1"); print -P -- "$p" >/dev/null' _ "$T/seg"
  [ ! -e "$T/pwned-mr" ]
  [ ! -e "$T/pwned-pipe" ]
}

@test "security: a non-numeric MR/PR number from the cache prints no segment" {
  gitlab_mr '{}'
  record >/dev/null
  cache_file=$(ls "$XDG_CACHE_HOME/git-mr/" | grep -v lock | head -1)
  printf 'mr\t7$(id)\thttps://git.example.com/m\tok\t\t\n' >"$XDG_CACHE_HOME/git-mr/$cache_file"
  run "$GIT_MR" --segment=bash "$T/repo"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "security: --url / --open refuse a URL that is not plain http(s)" {
  gitlab_mr '{"web_url":"file:///Applications/Calculator.app"}'
  cd "$T/repo"
  run "$GIT_MR" --url
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a plain http(s) URL"* ]] || false
  [[ "$output" != *"file://"* ]] || false
}
