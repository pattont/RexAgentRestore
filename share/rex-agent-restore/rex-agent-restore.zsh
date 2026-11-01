# rex-agent-restore: zsh integration.
#
# Source this from ~/.zshrc (`rex-agent-restore install` does it for you).
# It does nothing outside Rex and costs one file check per prompt.
#
# - Every agent started from this shell is tagged with a per-shell token.
# - When the prompt comes back and the pane's saved chat carries this shell's
#   token, the agent has exited normally, so the saved chat is deleted.
# - On the first prompt of a pane Rex restored, the saved chat carries an
#   older shell's token, so the chat is resumed.

[[ -o interactive ]] || return 0
[[ -n ${REX_BLOCK-} ]] || return 0
(( ${+_rex_agent_restore_loaded} )) && return 0
typeset -g _rex_agent_restore_loaded=1

zmodload zsh/datetime 2>/dev/null

typeset -g _rex_agent_restore_first=1
typeset -g _rex_agent_restore_bin=${${(%):-%x}:a:h:h:h}/bin/rex-agent-restore
[[ -x $_rex_agent_restore_bin ]] || _rex_agent_restore_bin=rex-agent-restore
typeset -g _rex_agent_restore_file="${REX_AGENT_RESTORE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/rex-agent-restore}/panes/${REX_BLOCK#block:}.json"

# A shell started inside another shell in the same pane (running `zsh` by
# hand, for example) must not resume the pane's chat.
if [[ ${_REX_AGENT_RESTORE_OWNER-} == $REX_BLOCK ]]; then
  typeset -g _rex_agent_restore_nested=1
else
  typeset -g _rex_agent_restore_nested=0
  export _REX_AGENT_RESTORE_OWNER=$REX_BLOCK
fi
export REX_AGENT_RESTORE_SHELL_TOKEN="$$-$RANDOM$RANDOM-${EPOCHSECONDS:-0}"

_rex_agent_restore_run() {
  local plan mode desc cmd rest st
  plan=$("$_rex_agent_restore_bin" restore-plan 2>/dev/null) || return 0
  mode=${plan%%$'\n'*}
  rest=${plan#*$'\n'}
  desc=${rest%%$'\n'*}
  cmd=${rest#*$'\n'}
  [[ -n $cmd && $cmd != $plan ]] || return 0

  case $mode in
    off)
      return 0
      ;;
    prompt)
      print -r -- "rex-agent-restore: press Enter to resume this pane's chat, or clear the line to skip."
      print -z -- "$cmd"
      return 0
      ;;
  esac

  print -P -- "%F{8}rex-agent-restore: ${desc//\%/%%}%f"
  print -s -- "$cmd"
  eval "$cmd"
  st=$?
  # The chat had its chance. Keep it only if the agent was hung up on,
  # which is what happens when Rex shuts down.
  (( st == 129 )) || command rm -f -- "$_rex_agent_restore_file"
  return 0
}

_rex_agent_restore_precmd() {
  local st=$?
  if [[ -e $_rex_agent_restore_file ]]; then
    local body
    body=$(<"$_rex_agent_restore_file")
    if [[ -n $REX_AGENT_RESTORE_SHELL_TOKEN && $body == *"\"shell_token\":\"$REX_AGENT_RESTORE_SHELL_TOKEN\""* ]]; then
      # An agent started from this shell has exited.
      (( st == 129 )) || command rm -f -- "$_rex_agent_restore_file"
    elif (( _rex_agent_restore_first && ! _rex_agent_restore_nested )); then
      _rex_agent_restore_first=0
      _rex_agent_restore_run
    fi
  fi
  _rex_agent_restore_first=0
  return $st
}

typeset -ga precmd_functions
precmd_functions+=(_rex_agent_restore_precmd)
