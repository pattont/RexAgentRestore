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
out="$("$BIN" doctor 2>&1)"
check "doctor runs cleanly and says Codex still needs approval" '! echo "$out" | grep -q "unbound variable" && echo "$out" | grep -q "Codex: installed, but not approved yet" && echo "$out" | grep -q "and approve .Rex Agent Restore"' "$out"
check "codex hooks feature turned on" 'grep -A3 "^\[features\]" "$HOME/.codex/config.toml" | grep -q "^hooks = true"'
check "codex hook is never approved for you" '! grep -q "hooks.state" "$HOME/.codex/config.toml"'
check "install tells you to approve it in Codex" 'echo "$out" | grep -q "/hooks"' "$out"
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

echo "install: upgrading an existing hook"
rm -rf "$HOME"; mkdir -p "$HOME/.codex"
jq -n --arg old "'$BIN' hook codex" '{hooks: {SessionStart: [
  {hooks: [{type: "command", command: "first"}]},
  {hooks: [{type: "command", command: $old, timeout: 10}]},
  {hooks: [{type: "command", command: "added-later"}]} ]}}' > "$HOME/.codex/hooks.json"
"$BIN" install --agents codex --no-shell --no-rex >/dev/null 2>&1
check "codex hook is named in /hooks (statusMessage)" 'jq -e ".hooks.SessionStart[1].hooks[0].statusMessage | startswith(\"Rex Agent Restore\")" "$HOME/.codex/hooks.json" >/dev/null'
check "an older hook is updated where it is, not moved or duplicated" '[ "$(jq -c "[.hooks.SessionStart[].hooks[0].command | sub(\".*/\"; \"\")]" "$HOME/.codex/hooks.json")" = "[\"first\",\"rex-agent-restore'"'"' hook codex\",\"added-later\"]" ]' "$(jq -c . "$HOME/.codex/hooks.json")"

echo "install: every agent"
rm -rf "$HOME"; mkdir -p "$HOME"
for d in .claude .codex .grok .gemini .copilot .cursor .factory .gemini/config .config/devin .kimi-code .qoder .qwen .letta .config/opencode .pi/agent .omp/agent .config/kilo; do mkdir -p "$HOME/$d"; done
echo '{"theme":"dark"}' > "$HOME/.gemini/settings.json"
echo '{"version":1,"hooks":{"sessionStart":[{"command":"other"}]}}' > "$HOME/.cursor/hooks.json"
echo '{"SessionStart":[{"hooks":[{"type":"command","command":"other"}]}]}' > "$HOME/.factory/hooks.json"
echo '{"other-hook":{"SessionStart":[{"type":"command","command":"x"}]}}' > "$HOME/.gemini/config/hooks.json"
printf 'default_model = "k2"\n' > "$HOME/.kimi-code/config.toml"
for f in "$HOME/.gemini/settings.json" "$HOME/.cursor/hooks.json" "$HOME/.factory/hooks.json" "$HOME/.gemini/config/hooks.json" "$HOME/.kimi-code/config.toml"; do cp "$f" "$f.orig"; done
out="$("$BIN" install --no-shell --no-rex 2>&1)"
check "install finds all 17 agents" '[ "$(echo "$out" | grep -c "^  [A-Za-z]")" -ge 17 ]' "$out"
check "gemini: hook with matcher and ms timeout" 'jq -e ".theme == \"dark\" and .hooks.SessionStart[0].matcher == \"*\" and .hooks.SessionStart[0].hooks[0].timeout == 5000 and (.hooks.SessionStart[0].hooks[0].command | endswith(\"hook gemini\"))" "$HOME/.gemini/settings.json" >/dev/null'
check "copilot: own hook file with bash key" 'jq -e ".version == 1 and (.hooks.SessionStart[0].bash | endswith(\"hook copilot\"))" "$HOME/.copilot/hooks/rex-agent-restore.json" >/dev/null'
check "cursor: flat sessionStart entry added after others" 'jq -e ".version == 1 and .hooks.sessionStart[0].command == \"other\" and (.hooks.sessionStart[1].command | endswith(\"hook cursor\"))" "$HOME/.cursor/hooks.json" >/dev/null'
check "droid: uses hooks.json when it exists" 'jq -e "(.SessionStart[1].hooks[0].command | endswith(\"hook droid\"))" "$HOME/.factory/hooks.json" >/dev/null && [ ! -e "$HOME/.factory/settings.json" ]'
check "antigravity: named entry with SessionStart and PreInvocation" 'jq -e "has(\"other-hook\") and (.\"rex-agent-restore\".SessionStart[0].command | endswith(\"hook antigravity\")) and (.\"rex-agent-restore\".PreInvocation | length) == 1" "$HOME/.gemini/config/hooks.json" >/dev/null'
check "devin: hook in config.json" 'jq -e ".hooks.SessionStart[0].hooks[0].command | endswith(\"hook devin\")" "$HOME/.config/devin/config.json" >/dev/null'
check "kimi: TOML hook with only the allowed keys" 'grep -q "^\[\[hooks\]\]$" "$HOME/.kimi-code/config.toml" && grep -q "^event = \"SessionStart\"$" "$HOME/.kimi-code/config.toml" && grep -q "^command = \"'"'"'.*hook kimi\"$" "$HOME/.kimi-code/config.toml" && grep -q "^default_model" "$HOME/.kimi-code/config.toml"' "$(cat "$HOME/.kimi-code/config.toml")"
check "qoder, qwen: hooks in settings.json" 'jq -e ".hooks.SessionStart[0].hooks[0].command | endswith(\"hook qoder\")" "$HOME/.qoder/settings.json" >/dev/null && jq -e ".hooks.SessionStart[0].hooks[0].command | endswith(\"hook qwen\")" "$HOME/.qwen/settings.json" >/dev/null'
check "letta: quiet hook with ms timeout" 'jq -e ".hooks.SessionStart[0].hooks[0] | .quiet == true and .timeout == 10000" "$HOME/.letta/settings.json" >/dev/null'
check "plugins written with this program's path" 'grep -qF "\"$BIN\"" "$HOME/.config/opencode/plugins/rex-agent-restore/tui.js" && grep -qF "\"$BIN\"" "$HOME/.pi/agent/extensions/rex-agent-restore.ts" && grep -qF "\"$BIN\"" "$HOME/.omp/agent/extensions/rex-agent-restore-omp.ts" && grep -qF "\"$BIN\"" "$HOME/.config/kilo/plugin/rex-agent-restore.js" && ! grep -rq __REX_AGENT_RESTORE_BIN__ "$HOME/.config" "$HOME/.pi" "$HOME/.omp"'
if command -v node >/dev/null 2>&1; then
  check "plugins are valid JavaScript" 'node --check "$HOME/.config/opencode/plugins/rex-agent-restore/tui.js" && node --check "$HOME/.config/kilo/plugin/rex-agent-restore.js"'
fi
out="$("$BIN" install --no-shell --no-rex 2>&1)"
check "every agent install is idempotent" '[ "$(echo "$out" | grep -c "already set up")" -ge 17 ]' "$out"
"$BIN" uninstall >/dev/null 2>&1
for f in "$HOME/.gemini/settings.json" "$HOME/.cursor/hooks.json" "$HOME/.factory/hooks.json" "$HOME/.gemini/config/hooks.json"; do
  check "uninstall restores $(basename "$(dirname "$f")")/$(basename "$f")" '[ "$(jq -S . "$f.orig")" = "$(jq -S . "$f")" ]' "$(cat "$f")"
done
check "uninstall restores kimi config" 'cmp -s "$HOME/.kimi-code/config.toml.orig" "$HOME/.kimi-code/config.toml"' "$(cat "$HOME/.kimi-code/config.toml")"
check "uninstall removes plugins and own files" '[ ! -e "$HOME/.config/opencode/plugins/rex-agent-restore" ] && [ ! -e "$HOME/.pi/agent/extensions/rex-agent-restore.ts" ] && [ ! -e "$HOME/.copilot/hooks/rex-agent-restore.json" ]'
check "nothing of ours is left anywhere" '! grep -rlE "rex-agent-restore.? hook" "$HOME" --include="*.json" --include="*.toml" --exclude="*.bak-rex-agent-restore" 2>/dev/null | grep -q .'
rm -rf "$HOME"; mkdir -p "$HOME"
out="$("$BIN" install --agents pi --no-shell --no-rex 2>&1)"
check "plugins skip agents whose folder doesn't exist" 'echo "$out" | grep -q "doesn.t exist yet" && [ ! -e "$HOME/.pi" ]' "$out"

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
cat > "$T/nested.sh" <<'EOF'
# $1 inner agent, $2 event json, $3 bin
/bin/sh -c '"$0" -c "printf \"%s\" \"\$0\" | /bin/sh -c \"\\\"\$1\\\" hook claude\"; true" "$1" "$2"; true' "$1" "$2" "$3"
EOF
env REX_BLOCK=$B1 "$T/agents/claude" "$T/nested.sh" "$T/agents/claude" "$(json SessionStart nested-1)" "$BIN"
# A launcher that starts a copy of itself counts as one agent.
env REX_BLOCK=$B1 "$T/agents/claude" -c '"$1" -c "printf \"%s\" \"\$0\" | /bin/sh -c \"\\\"\$1\\\" hook claude\"; true" "$2" "$3"; true' _ "$T/agents/claude" "$(json SessionStart launcher-1)" "$BIN"
check "an agent's launcher and the agent count once" '[ "$(jq -r .chat_id "$F1")" = launcher-1 ]'
run_hook claude claude "$(json SessionStart abc-2 clear)" REX_BLOCK=$B1 REX_AGENT_RESTORE_SHELL_TOKEN=tok1
env REX_BLOCK=$B1 "$T/agents/claude" "$T/nested.sh" "$T/agents/claude" "$(json SessionStart nested-1)" "$BIN"
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

echo "hook: other agents"
for a in gemini-node letta agy cursor-agent node; do :; done
ln -s /bin/bash "$T/agents/letta"; ln -s /bin/bash "$T/agents/agy"; ln -s /bin/bash "$T/agents/cursor-agent"
rm -f "$F1"
# Gemini runs under node; it's recognized from its command line.
env REX_BLOCK=$B1 "$T/agents/node" -c 'printf "%s" "$1" | /bin/sh -c "\"$2\" hook gemini"; true' /x/@google/gemini-cli/dist/index.js "$(json SessionStart gem-1)" "$BIN"
check "gemini under node is recognized" '[ "$(jq -r .agent "$F1")/$(jq -r .chat_id "$F1")" = gemini/gem-1 ]'
rm -f "$F1"
run_hook letta letta "$(jq -cn --arg c "$CWD" '{event_type:"SessionStart", agent_id:"agent-7", conversation_id:"conv-9", working_directory:$c}')" REX_BLOCK=$B1
check "letta: agent_id isn't treated as a subagent; conversation recorded" '[ "$(jq -r .chat_id "$F1")" = conv-9 ] && [ "$(jq -r .cwd "$F1")" = "$CWD" ]'
run_hook letta letta "$(jq -cn '{event_type:"SessionStart", agent_id:"agent-7", conversation_id:"default"}')" REX_BLOCK=$B1
check "letta: default conversation keeps its agent" '[ "$(jq -r .chat_id "$F1")" = default:agent-7 ]'
check "letta: resume uses --conversation default --agent" '[ "$(REX_BLOCK=$B1 "$BIN" resume-command | sed "s/.* && //")" = "letta --conversation default --agent '"'"'agent-7'"'"'" ]'
rm -f "$F1"
out="$(run_hook agy antigravity "$(jq -cn --arg c "$CWD" '{conversationId:"agy-1", workspacePaths:[$c]}')" REX_BLOCK=$B1)"
check "antigravity: hook prints {} as required" '[ "$out" = "{}" ]' "$out"
check "antigravity: conversation and workspace recorded" '[ "$(jq -r .chat_id "$F1")" = agy-1 ] && [ "$(jq -r .cwd "$F1")" = "$CWD" ]'
run_hook agy antigravity "$(jq -cn '{hookEventName:"PreInvocation", conversationId:"agy-2"}')" REX_BLOCK=$B1 >/dev/null
check "antigravity: PreInvocation updates the conversation" '[ "$(jq -r .chat_id "$F1")" = agy-2 ]'
rm -f "$F1"
run_hook cursor-agent cursor "$(jq -cn --arg c "$CWD" '{hook_event_name:"sessionStart", session_id:"cur-1", workspace_roots:[$c], is_background_agent:true}')" REX_BLOCK=$B1
check "cursor: background agents are ignored" '[ ! -e "$F1" ]'
run_hook cursor-agent cursor "$(jq -cn --arg c "$CWD" '{hook_event_name:"sessionStart", session_id:"cur-1", workspace_roots:[$c]}')" REX_BLOCK=$B1
check "cursor: chat recorded with its workspace" '[ "$(jq -r .chat_id "$F1")" = cur-1 ] && [ "$(jq -r .cwd "$F1")" = "$CWD" ]'
rm -f "$F1"
run_hook node cursor "$(json sessionStart ide-1)" REX_BLOCK=$B1
check "cursor: the Cursor app's hooks are ignored" '[ ! -e "$F1" ]'
run_hook claude gemini "$(json SessionStart mismatch)" REX_BLOCK=$B1
check "an agent's hook inside a different agent is ignored" '[ ! -e "$F1" ]'

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
