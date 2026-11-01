#!/usr/bin/env bash
# Unit tests: install/uninstall, hook decisions, resume commands.
# Runs in a throwaway HOME. Needs bash, jq, and zsh.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/rex-agent-restore"
tmp_root="${RAR_TEST_TMP:-${TMPDIR:-/tmp}}"
# Normalize the path (no trailing slash, no symlinks) so it matches what
# shells report as the working directory.
T="$(cd "$(mktemp -d "${tmp_root%/}/rar-unit.XXXXXX")" && pwd -P)"
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

# Isolate everything from the real machine.
export HOME="$T/home"
mkdir -p "$HOME"
unset ZDOTDIR XDG_CONFIG_HOME XDG_STATE_HOME CLAUDE_CONFIG_DIR CODEX_HOME GROK_HOME REX_CONFIG
unset REX_AGENT_RESTORE_MODE REX_AGENT_RESTORE_DISABLE GROK_SESSION_ID CODEX_THREAD_ID
export SHELL=/bin/zsh
export REX_AGENT_RESTORE_STATE_DIR="$T/state"
export REX_AGENT_RESTORE_CONFIG="$T/config"
export _REX_AGENT_RESTORE_STOP_PID=$$
STATE="$REX_AGENT_RESTORE_STATE_DIR/panes"

# Fake agent binaries: symlinks to bash, so `ps` shows the agent's name.
mkdir -p "$T/agents"
for a in claude codex grok-1.0.67-macos-aarch64 node; do ln -s /bin/bash "$T/agents/$a"; done

# run_hook AGENT_PROCESS HINT JSON [ENV...]: run the hook the way an agent does,
# from inside a process named AGENT_PROCESS.
run_hook() {
  local proc="$1" hint="$2" json="$3"
  shift 3
  env "$@" "$T/agents/$proc" -c 'printf "%s" "$1" | /bin/sh -c "\"$2\" hook $3"; true' _ "$json" "$BIN" "$hint"
}

echo "install"
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.grok"
cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "existing-claude-hook" } ] }
    ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "stop-hook" } ] } ]
  }
}
EOF
cat > "$HOME/.codex/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "codex-existing" } ] } ] } }
EOF
printf 'model = "gpt"\n\n[features]\nmulti_agent = true\n' > "$HOME/.codex/config.toml"
echo '# my zshrc' > "$HOME/.zshrc"
cp "$HOME/.claude/settings.json" "$T/claude.orig"
cp "$HOME/.codex/hooks.json" "$T/codex.orig"

out="$("$BIN" install 2>&1)"
check "install succeeds" '[ $? -eq 0 ]' "$out"
check "claude hook appended after the existing one" \
  '[ "$(jq -r ".hooks.SessionStart | map(.hooks[].command) | join(\",\")" "$HOME/.claude/settings.json")" = "existing-claude-hook,'"'"'$BIN'"'"' hook claude" ]'
check "other claude settings kept" '[ "$(jq -r .model "$HOME/.claude/settings.json")" = opus ] && [ "$(jq -r ".hooks.Stop[0].hooks[0].command" "$HOME/.claude/settings.json")" = stop-hook ]'
check "codex hook appended" '[ "$(jq -r ".hooks.SessionStart | length" "$HOME/.codex/hooks.json")" = 2 ] && jq -e ".hooks.SessionStart[1].hooks[0].command | endswith(\"hook codex\")" "$HOME/.codex/hooks.json" >/dev/null'
check "codex hooks feature turned on" 'grep -A3 "^\[features\]" "$HOME/.codex/config.toml" | grep -q "^hooks = true"'
check "codex config kept" 'grep -q "^multi_agent = true" "$HOME/.codex/config.toml" && grep -q "^model = \"gpt\"" "$HOME/.codex/config.toml"'
check "grok hook file written" 'jq -e ".hooks.SessionStart[0].hooks[0].command | endswith(\"hook grok\")" "$HOME/.grok/hooks/rex-agent-restore.json" >/dev/null'
check "zshrc sources the integration" 'grep -q "rex-agent-restore.zsh" "$HOME/.zshrc" && head -1 "$HOME/.zshrc" | grep -q "my zshrc"'
check "rex module linked" '[ -L "$HOME/.config/rex/rex_agent_restore.lua" ] && [ -f "$HOME/.config/rex/rex_agent_restore.lua" ]'
check "rex init.lua calls setup" 'grep -q "rar.setup" "$HOME/.config/rex/init.lua"'
if command -v rex >/dev/null 2>&1; then
  out="$(REX_CONFIG="$HOME/.config/rex/init.lua" rex config check 2>&1)"
  check "rex accepts the config and finds 3 actions" 'echo "$out" | grep -q "^actions: 3$"' "$out"
fi
check "backup made" '[ -f "$HOME/.claude/settings.json.bak-rex-agent-restore" ]'

cp "$HOME/.claude/settings.json" "$T/claude.1"; cp "$HOME/.codex/hooks.json" "$T/codex.1"
cp "$HOME/.zshrc" "$T/zshrc.1"; cp "$HOME/.codex/config.toml" "$T/toml.1"; cp "$HOME/.config/rex/init.lua" "$T/init.1"
"$BIN" install >/dev/null 2>&1
check "install is idempotent" 'cmp -s "$T/claude.1" "$HOME/.claude/settings.json" && cmp -s "$T/codex.1" "$HOME/.codex/hooks.json" && cmp -s "$T/zshrc.1" "$HOME/.zshrc" && cmp -s "$T/toml.1" "$HOME/.codex/config.toml" && cmp -s "$T/init.1" "$HOME/.config/rex/init.lua"'

# A moved program path replaces the old hook instead of adding a second one.
REX_AGENT_RESTORE_BIN=/elsewhere/rex-agent-restore "$BIN" install >/dev/null 2>&1
check "reinstall from a new path replaces the hook" '[ "$(jq "[.hooks.SessionStart[].hooks[] | select(.command | test(\"hook claude\"))] | length" "$HOME/.claude/settings.json")" = 1 ] && grep -q /elsewhere/ "$HOME/.claude/settings.json"'
"$BIN" install >/dev/null 2>&1

# Symlinked dotfiles stay symlinks.
mkdir -p "$T/dotfiles"; mv "$HOME/.zshrc" "$T/dotfiles/zshrc"; ln -s "$T/dotfiles/zshrc" "$HOME/.zshrc"
"$BIN" uninstall >/dev/null 2>&1
check "uninstall keeps a symlinked zshrc a symlink" '[ -L "$HOME/.zshrc" ]'
check "uninstall removes the zsh block" '! grep -q rex-agent-restore "$HOME/.zshrc"'
check "uninstall restores claude settings" '[ "$(jq -S . "$T/claude.orig")" = "$(jq -S . "$HOME/.claude/settings.json")" ]'
check "uninstall restores codex hooks" '[ "$(jq -S . "$T/codex.orig")" = "$(jq -S . "$HOME/.codex/hooks.json")" ]'
check "uninstall removes grok hook" '[ ! -e "$HOME/.grok/hooks/rex-agent-restore.json" ]'
check "uninstall removes rex block and link" '! grep -q rex-agent-restore "$HOME/.config/rex/init.lua" && [ ! -e "$HOME/.config/rex/rex_agent_restore.lua" ]'

rm -rf "$HOME"; mkdir -p "$HOME"
"$BIN" install --agents claude --no-shell --no-rex >/dev/null 2>&1
check "install creates a missing settings file" 'jq -e ".hooks.SessionStart[0].hooks[0].command" "$HOME/.claude/settings.json" >/dev/null'
check "--no-shell leaves zshrc alone" '[ ! -e "$HOME/.zshrc" ]'

rm -rf "$HOME"; mkdir -p "$HOME/.codex"
printf '[features]\nhooks = false\n' > "$HOME/.codex/config.toml"
out="$("$BIN" install --agents codex --no-shell --no-rex 2>&1)"
check "codex hooks=false is reported, not changed" 'echo "$out" | grep -q warning && grep -q "hooks = false" "$HOME/.codex/config.toml"'

out="$("$BIN" install --dry-run --agents claude 2>&1)"
check "dry run changes nothing" '[ ! -e "$HOME/.claude/settings.json" ] && [ ! -e "$HOME/.zshrc" ]'

echo "hook"
B1=block:01a1aaaa-0000-7000-8000-000000000001
F1="$STATE/01a1aaaa-0000-7000-8000-000000000001.json"
CWD="$T/my proj's \"dir\""
mkdir -p "$CWD"
json() { jq -cn --arg e "$1" --arg s "$2" --arg c "$CWD" --arg src "${3:-startup}" '{hook_event_name:$e, session_id:$s, cwd:$c, source:$src}'; }

out="$(run_hook claude claude "$(json SessionStart abc-1)" REX_BLOCK=$B1 REX_SESSION=session:s1 REX_SERVER=unix:///x REX_AGENT_RESTORE_SHELL_TOKEN=tok1)"
check "hook prints nothing" '[ -z "$out" ]' "$out"
check "claude chat recorded" '[ "$(jq -r .agent "$F1")/$(jq -r .chat_id "$F1")" = claude/abc-1 ]'
check "record keeps pane, session, server, token, folder" '[ "$(jq -r "[.block_id,.rex_session,.rex_server,.shell_token,.cwd]|join(\"|\")" "$F1")" = "$B1|session:s1|unix:///x|tok1|$CWD" ]'
check "record is compact JSON with the token pattern the shell looks for" 'grep -q "\"shell_token\":\"tok1\"" "$F1"'

run_hook claude claude "$(json SessionStart abc-2 clear)" REX_BLOCK=$B1 REX_AGENT_RESTORE_SHELL_TOKEN=tok1
check "a new chat in the same pane replaces the record" '[ "$(jq -r .chat_id "$F1")" = abc-2 ]'

run_hook claude claude "$(json Stop abc-3)" REX_BLOCK=$B1
check "other events are ignored" '[ "$(jq -r .chat_id "$F1")" = abc-2 ]'

run_hook claude claude "$(jq -cn '{hook_event_name:"SessionStart", session_id:"sub-1", agent_id:"a1"}')" REX_BLOCK=$B1
check "subagents are ignored" '[ "$(jq -r .chat_id "$F1")" = abc-2 ]'

# claude -> shell -> claude -p (an agent started by another agent's tool)
env REX_BLOCK=$B1 "$T/agents/claude" -c '"$1" -c "printf \"%s\" \"\$1\" | /bin/sh -c \"\\\"\$2\\\" hook claude\"; true" _ "$2" "$3"; true' _ "$T/agents/claude" "$(json SessionStart nested-1)" "$BIN"
check "nested agents are ignored" '[ "$(jq -r .chat_id "$F1")" = abc-2 ]'

rm -f "$F1"
run_hook grok-1.0.67-macos-aarch64 claude "$(jq -cn --arg c "$CWD" '{hookEventName:"session_start", sessionId:"payload-id", cwd:$c}')" REX_BLOCK=$B1 GROK_SESSION_ID=grok-env-id
check "grok running a Claude-settings hook is recorded as grok" '[ "$(jq -r .agent "$F1")" = grok ]'
check "grok uses GROK_SESSION_ID" '[ "$(jq -r .chat_id "$F1")" = grok-env-id ]'

rm -f "$F1"
run_hook codex codex "$(json SessionStart codex-1)" REX_BLOCK=$B1 CODEX_THREAD_ID=other-thread
check "codex chat started inside another codex chat is ignored" '[ ! -e "$F1" ]'
run_hook codex codex "$(json SessionStart codex-1)" REX_BLOCK=$B1 CODEX_THREAD_ID=codex-1
check "codex chat recorded" '[ "$(jq -r .agent "$F1")/$(jq -r .chat_id "$F1")" = codex/codex-1 ]'

rm -f "$F1"
run_hook node claude "$(json SessionStart via-node)" REX_BLOCK=$B1
check "unknown process name falls back to the hook's agent" '[ "$(jq -r .agent "$F1")" = claude ]'

rm -f "$F1"
run_hook claude claude "$(json SessionStart outside)" REX_BLOCK=
check "outside Rex nothing is recorded" '[ ! -e "$F1" ]'
run_hook claude claude "not json" REX_BLOCK=$B1
check "bad input is ignored" '[ ! -e "$F1" ]'
run_hook claude claude "$(json SessionStart x)" REX_BLOCK=block:../../etc
check "unsafe pane IDs are ignored" '[ -z "$(ls "$STATE" 2>/dev/null)" ]'
echo 'REX_AGENT_RESTORE_DISABLE=1' > "$REX_AGENT_RESTORE_CONFIG"
run_hook claude claude "$(json SessionStart disabled)" REX_BLOCK=$B1
check "REX_AGENT_RESTORE_DISABLE in the config file turns recording off" '[ ! -e "$F1" ]'
rm -f "$REX_AGENT_RESTORE_CONFIG"

echo "resume commands"
mkdir -p "$T/fakebin"
for a in claude codex grok; do printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/$a"; chmod +x "$T/fakebin/$a"; done
export PATH="$T/fakebin:$PATH"
run_hook claude claude "$(json SessionStart "id'with quote")" REX_BLOCK=$B1
cmd="$(REX_BLOCK=$B1 "$BIN" resume-command)"
check "resume command survives quotes in the folder and ID" '[ "$(eval "printf \"%s\\n\" $(printf "%s" "$cmd" | sed "s/^cd -- //; s/ && claude --resume / /")" | tr "\n" "|")" = "$CWD|id'"'"'with quote|" ]' "$cmd"
REX_AGENT_RESTORE_CLAUDE_ARGS='--model opus'
cmd="$(REX_BLOCK=$B1 REX_AGENT_RESTORE_CLAUDE_ARGS='--model opus' "$BIN" resume-command)"
check "extra resume arguments are added" 'case "$cmd" in *" --model opus") true ;; *) false ;; esac' "$cmd"
plan="$(REX_BLOCK=$B1 "$BIN" restore-plan)"
check "restore plan has mode, description, command" '[ "$(printf "%s\n" "$plan" | sed -n 1p)" = auto ] && printf "%s\n" "$plan" | sed -n 3p | grep -q "claude --resume"'
plan="$(REX_BLOCK=$B1 REX_AGENT_RESTORE_MODE=prompt "$BIN" restore-plan)"
check "restore plan reports prompt mode" '[ "$(printf "%s\n" "$plan" | sed -n 1p)" = prompt ]'
run_hook codex codex "$(json SessionStart cx)" REX_BLOCK=$B1
check "codex resume command" '[ "$(REX_BLOCK=$B1 "$BIN" resume-command | sed "s/.* && //")" = "codex resume '"'"'cx'"'"'" ]'
run_hook grok-1.0.67-macos-aarch64 grok "$(json SessionStart gx)" REX_BLOCK=$B1
check "grok resume command" '[ "$(REX_BLOCK=$B1 "$BIN" resume-command | sed "s/.* && //")" = "grok --resume '"'"'gx'"'"'" ]'
rm -f "$T/fakebin/grok"
check "no plan when the agent isn't installed" '! REX_BLOCK=$B1 PATH="$T/fakebin:/usr/bin:/bin" "$BIN" restore-plan >/dev/null 2>&1'

echo "list and forget"
out="$("$BIN" list)"
check "list shows the chat" 'echo "$out" | grep -q gx'
check "list --json is an array" '[ "$("$BIN" list --json | jq length)" = 1 ]'
"$BIN" forget 00000001 >/dev/null
check "forget accepts a short pane ID" '[ ! -e "$F1" ]'

echo "zsh integration"
if command -v zsh >/dev/null 2>&1; then
  ZS="$ROOT/share/rex-agent-restore/rex-agent-restore.zsh"
  mkdir -p "$STATE"
  # A record from an earlier shell, as Rex leaves it after a restart.
  jq -cn --arg b $B1 --arg c "$CWD" '{block_id:$b, agent:"claude", chat_id:"old-chat", cwd:$c, shell_token:"old-shell"}' > "$F1"
  printf '#!/bin/sh\necho "fake claude $*" >> "%s"\nexit 0\n' "$T/agent.log" > "$T/fakebin/claude"
  out="$(cd "$T" && REX_BLOCK=$B1 _REX_AGENT_RESTORE_OWNER= zsh -f -i -c "source '$ZS'; _rex_agent_restore_precmd; print -r -- \"pwd=\$PWD\"" 2>&1)"
  check "first prompt resumes the saved chat" 'grep -q "fake claude --resume old-chat" "$T/agent.log"' "$out"
  check "resume runs in the saved folder" 'echo "$out" | grep -qF "pwd=$CWD"' "$out"
  check "record is forgotten after the resumed agent exits" '[ ! -e "$F1" ]'

  : > "$T/agent.log"
  jq -cn --arg b $B1 '{block_id:$b, agent:"claude", chat_id:"old-chat", cwd:"/", shell_token:"old-shell"}' > "$F1"
  REX_BLOCK=$B1 _REX_AGENT_RESTORE_OWNER=$B1 zsh -f -i -c "source '$ZS'; _rex_agent_restore_precmd" >/dev/null 2>&1
  check "a nested shell in the same pane doesn't resume" '[ ! -s "$T/agent.log" ] && [ -e "$F1" ]'

  REX_BLOCK=$B1 _REX_AGENT_RESTORE_OWNER= REX_AGENT_RESTORE_MODE=off zsh -f -i -c "source '$ZS'; _rex_agent_restore_precmd" >/dev/null 2>&1
  check "off mode doesn't resume and keeps the record" '[ ! -s "$T/agent.log" ] && [ -e "$F1" ]'

  # A record written by an agent started from this same shell is removed at
  # the next prompt.
  out="$(REX_BLOCK=$B1 _REX_AGENT_RESTORE_OWNER= zsh -f -i -c "source '$ZS'; _rex_agent_restore_first=0; jq -cn --arg t \"\$REX_AGENT_RESTORE_SHELL_TOKEN\" '{shell_token:\$t}' > '$F1'; true; _rex_agent_restore_precmd; [[ -e '$F1' ]] && print kept || print removed" 2>&1)"
  check "agent that exited normally is forgotten at the prompt" '[ "$out" = removed ]' "$out"
  out="$(REX_BLOCK=$B1 _REX_AGENT_RESTORE_OWNER= zsh -f -i -c "source '$ZS'; _rex_agent_restore_first=0; jq -cn --arg t \"\$REX_AGENT_RESTORE_SHELL_TOKEN\" '{shell_token:\$t}' > '$F1'; (exit 129); _rex_agent_restore_precmd; [[ -e '$F1' ]] && print kept || print removed" 2>&1)"
  check "agent that was hung up on is kept" '[ "$out" = kept ]' "$out"
  out="$(REX_BLOCK= zsh -f -i -c "source '$ZS'; print \${+functions[_rex_agent_restore_precmd]}" 2>&1)"
  check "outside Rex the integration does nothing" '[ "$out" = 0 ]' "$out"
else
  echo "  skip (zsh not found)"
fi

echo "bash integration"
BS="$ROOT/share/rex-agent-restore/rex-agent-restore.bash"
: > "$T/agent.log"
jq -cn --arg b $B1 --arg c "$CWD" '{block_id:$b, agent:"claude", chat_id:"bash-chat", cwd:$c, shell_token:"old-shell"}' > "$F1"
REX_BLOCK=$B1 _REX_AGENT_RESTORE_OWNER= bash --norc -i -c "source '$BS'; _rex_agent_restore_prompt" >/dev/null 2>&1
check "bash: first prompt resumes the saved chat" 'grep -q "fake claude --resume bash-chat" "$T/agent.log"'
check "bash: record forgotten after exit" '[ ! -e "$F1" ]'

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
