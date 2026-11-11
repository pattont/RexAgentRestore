# rex-agent-restore: bash integration.
#
# Source this from ~/.bashrc (`rex-agent-restore install --shell bash` does it
# for you). It does nothing outside Rex. See rex-agent-restore.zsh for how it
# works; this file does the same thing with PROMPT_COMMAND.

[[ $- == *i* ]] || return 0
[[ -n ${REX_BLOCK-} ]] || return 0
[[ -n ${_rex_agent_restore_loaded-} ]] && return 0
_rex_agent_restore_loaded=1

_rex_agent_restore_first=1
_rex_agent_restore_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/bin/rex-agent-restore"
[[ -x $_rex_agent_restore_bin ]] || _rex_agent_restore_bin=rex-agent-restore
_rex_agent_restore_file="${REX_AGENT_RESTORE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rex-agent-restore}/panes/${REX_BLOCK#block:}.json"

if [[ ${_REX_AGENT_RESTORE_OWNER-} == "$REX_BLOCK" ]]; then
  _rex_agent_restore_nested=1
else
  _rex_agent_restore_nested=0
  export _REX_AGENT_RESTORE_OWNER=$REX_BLOCK
fi
export REX_AGENT_RESTORE_SHELL_TOKEN="$$-$RANDOM$RANDOM-$(date +%s)"

# Killed by a hang-up (Rex shut down), SIGTERM or SIGKILL (the Mac logging out
# or restarting) rather than quit: keep the chat. See rex-agent-restore.zsh.
_rex_agent_restore_killed() {
  (( $1 == 129 || $1 == 137 || $1 == 143 ))
}

_rex_agent_restore_run() {
  local plan mode desc cmd st
  plan=$("$_rex_agent_restore_bin" restore-plan 2>/dev/null) || return 0
  mode=$(printf '%s\n' "$plan" | sed -n 1p)
  desc=$(printf '%s\n' "$plan" | sed -n 2p)
  cmd=$(printf '%s\n' "$plan" | sed -n 3p)
  [[ -n $cmd ]] || return 0

  case $mode in
    off) return 0 ;;
    prompt)
      printf 'rex-agent-restore: to resume this pane'"'"'s chat, run:\n  %s\n' "$cmd"
      history -s -- "$cmd"
      return 0
      ;;
  esac

  printf '\033[90mrex-agent-restore: %s\033[0m\n' "$desc"
  history -s -- "$cmd"
  eval "$cmd"
  st=$?
  _rex_agent_restore_killed $st || command rm -f -- "$_rex_agent_restore_file"
  return 0
}

_rex_agent_restore_prompt() {
  local st=$?
  if [[ -e $_rex_agent_restore_file ]]; then
    local body
    body=$(<"$_rex_agent_restore_file")
    if [[ -n $REX_AGENT_RESTORE_SHELL_TOKEN && $body == *"\"shell_token\":\"$REX_AGENT_RESTORE_SHELL_TOKEN\""* ]]; then
      _rex_agent_restore_killed $st || command rm -f -- "$_rex_agent_restore_file"
    elif (( _rex_agent_restore_first && ! _rex_agent_restore_nested )); then
      _rex_agent_restore_first=0
      _rex_agent_restore_run
    fi
  fi
  _rex_agent_restore_first=0
  return $st
}

PROMPT_COMMAND="_rex_agent_restore_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
