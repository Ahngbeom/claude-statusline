# shellcheck shell=bash disable=SC2034 # GIT_PS1_* are read by __git_ps1
# Source from ~/.bashrc or ~/.zshrc: adds " (branch status) !MR" to the prompt,
# via git's own __git_ps1 and claude-statusline's git-mr (if on PATH).
# GIT_PROMPT_MR=0 hides the MR/PR segment.

for __gp in \
  /usr/lib/git-core/git-sh-prompt \
  /opt/homebrew/etc/bash_completion.d/git-prompt.sh \
  /usr/local/etc/bash_completion.d/git-prompt.sh \
  /Library/Developer/CommandLineTools/usr/share/git-core/git-prompt.sh \
  /Applications/Xcode.app/Contents/Developer/usr/share/git-core/git-prompt.sh
do
  # shellcheck source=/dev/null
  [ -r "$__gp" ] && { . "$__gp"; break; }
done
unset __gp
type __git_ps1 >/dev/null 2>&1 || return 0

GIT_PS1_SHOWDIRTYSTATE=1
GIT_PS1_SHOWSTASHSTATE=1
GIT_PS1_SHOWUNTRACKEDFILES=1
GIT_PS1_SHOWUPSTREAM=auto
GIT_PS1_SHOWCOLORHINTS=1

if [ -n "$BASH_VERSION" ]; then
  # Captured once: after the first prompt, PS1 already contains the git segment.
  if [ -z "${__git_prompt_pre+x}" ]; then
    __git_prompt_pre=${PS1%'\$ '}
  fi
  __git_prompt_cmd() {
    local mr=''
    [ "${GIT_PROMPT_MR:-1}" = 0 ] || mr=$(git-mr --segment=bash 2>/dev/null)
    __git_ps1 "$__git_prompt_pre" "${mr:+ $mr}"'\$ ' ' (%s)'
  }
  case ";$PROMPT_COMMAND;" in
    *";__git_prompt_cmd;"*) ;;
    *) PROMPT_COMMAND="__git_prompt_cmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
  esac
elif [ -n "$ZSH_VERSION" ]; then
  setopt PROMPT_SUBST
  autoload -Uz add-zsh-hook
  : "${__git_prompt_pre:=%B%F{green}%n@%m%f%b:%B%F{blue}%~%f%b}"
  __git_prompt_cmd() {
    local mr=''
    [ "${GIT_PROMPT_MR:-1}" = 0 ] || mr=$(git-mr --segment=zsh 2>/dev/null)
    __git_ps1 "$__git_prompt_pre" "${mr:+ $mr}"'%# ' ' (%s)'
  }
  add-zsh-hook precmd __git_prompt_cmd
fi
