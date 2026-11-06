#!/usr/bin/env bats
#
# shell/git-prompt.sh sourced into zsh, outside a git repo, with the PR/MR
# segment off. Skips without zsh or git's git-sh-prompt (exit 3 below).

GIT_PROMPT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/shell/git-prompt.sh"

setup() {
  command -v zsh >/dev/null || skip "zsh not installed"
  cd "$BATS_TEST_TMPDIR" || return
}

# $1 = zsh code run before sourcing; prints PS1 after one precmd.
zsh_ps1() {
  # shellcheck disable=SC2016 # expanded by zsh, not here
  zsh -fc "GIT_PROMPT_MR=0; $1"'
    . "$0"
    (( $+functions[__git_ps1] )) || exit 3
    __git_prompt_cmd
    print -r -- "$PS1"' "$GIT_PROMPT"
}

@test "zsh: default base prompt keeps the whole user@host:dir string" {
  run zsh_ps1 ''
  [ "$status" -ne 3 ] || skip "git-sh-prompt not found"
  [ "$status" -eq 0 ]
  [ "$output" = '%B%F{green}%n@%m%f%b:%B%F{blue}%~%f%b%# ' ]
}

@test "zsh: a base prompt set before sourcing is kept" {
  run zsh_ps1 "__git_prompt_pre='%m:%~'"
  [ "$status" -ne 3 ] || skip "git-sh-prompt not found"
  [ "$status" -eq 0 ]
  [ "$output" = '%m:%~%# ' ]
}
