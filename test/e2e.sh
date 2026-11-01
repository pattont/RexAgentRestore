#!/usr/bin/env bash
# End-to-end test against a real, throwaway Rex server.
#
# Starts a separate Rex server with its own socket and state, runs fake agents
# in its panes, restarts the server, and checks that the chats come back.
# Your own Rex server and sessions are not touched.
#
# The server's socket path must be short (Unix sockets allow ~104 bytes), so
# RAR_TEST_DIR defaults to a directory under /tmp.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/rex-agent-restore"
command -v rex >/dev/null || { echo "rex not found; skipping e2e"; exit 0; }
command -v zsh >/dev/null || { echo "zsh not found; skipping e2e"; exit 0; }

D="${RAR_TEST_DIR:-$(mktemp -d /tmp/rar-e2e.XXXXXX)}"
mkdir -p "$D"
SOCK="unix://$D/s"
LOG="$D/agents.log"
SERVER_PID=""

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

R() { rex -S "$SOCK" --autostart=false "$@"; }

start_server() {
  # Detach the server (double fork) so it isn't a child of whatever runs the
  # tests. Otherwise an agent running the tests would look like the parent of
  # every fake agent, and the hook would rightly ignore them as nested.
  ( env -u REX_SERVER -u REX_SESSION -u REX_BLOCK -u REX_CLIENT -u _REX_AGENT_RESTORE_OWNER \
    -u REX_AGENT_RESTORE_SHELL_TOKEN -u _REX_AGENT_RESTORE_STOP_PID \
    ZDOTDIR="$D/zdot" REX_AGENT_RESTORE_DEBUG=1 REX_SERVER="$SOCK" \
    REX_AGENT_RESTORE_STATE_DIR="$D/state" \
    REX_AGENT_RESTORE_CONFIG="$D/config" \
    RAR_LOG="$LOG" RAR_BIN="$BIN" RAR_D="$D" \
    rex server run --listen "$SOCK" --state-dir "$D/rexstate" --config "$D/rexcfg/init.lua" \
    >> "$D/server.log" 2>&1 < /dev/null & )
  local i
  for i in $(seq 1 50); do
    if R ls >/dev/null 2>&1; then
      SERVER_PID="$(R whoami --json 2>/dev/null | jq -r '.pid // empty')"
      return 0
    fi
    sleep 0.1
  done
  echo "test server didn't start; see $D/server.log"
  exit 1
}

stop_server() {
  R server stop >/dev/null 2>&1
  local i
  for i in $(seq 1 50); do
    kill -0 "$SERVER_PID" 2>/dev/null || return 0
    sleep 0.1
  done
  kill "$SERVER_PID" 2>/dev/null
}

cleanup() {
  [ -n "$SERVER_PID" ] && stop_server
  [ -z "${RAR_TEST_KEEP:-}" ] && rm -rf "$D"
}
trap cleanup EXIT

# wait_for SECONDS COMMAND...: poll until COMMAND succeeds.
wait_for() {
  local secs="$1" i
  shift
  for i in $(seq 1 $((secs * 10))); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}
screen_has() { R capture -s "$SID" -b "$1" --trim --unwrap 2>/dev/null | grep -qF -- "$2"; }
log_has() { grep -qF -- "$1" "$LOG" 2>/dev/null; }
rec() { printf '%s/state/panes/%s.json' "$D" "${1#block:}"; }
fg_name() { R block call -s "$SID" -b "$1" process 2>/dev/null | jq -r '.foreground.name // empty'; }
chat_id() { jq -r .chat_id "$(rec "$1")" 2>/dev/null; }
at_prompt() { [ "$(fg_name "$1")" = zsh ]; }

# --- fixtures

mkdir -p "$D/zdot" "$D/fakebin" "$D/agents" "$D/proj dir" "$D/rexcfg"
: > "$LOG"
ln -sf /bin/bash "$D/agents/claude"
ln -sf /bin/bash "$D/agents/codex"

# Fake agent: records how it was started, runs the SessionStart hook like a
# real agent, then waits for Enter.
cat > "$D/fake-agent.sh" <<'EOF'
name=$1; shift
case "$name:${1:-}" in
  claude:--resume|codex:resume) id=$2; echo "$name resumed $id" >> "$RAR_LOG" ;;
  *) id="$name-$RANDOM$RANDOM"; echo "$name started $id" >> "$RAR_LOG" ;;
esac
printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s","source":"startup"}' "$id" "$PWD" |
  /bin/sh -c "'$RAR_BIN' hook $name"
echo "FAKE $name READY $id"
IFS= read -r line
exit 0
EOF
for a in claude codex; do
  printf '#!/bin/sh\nexec "%s/agents/%s" "%s/fake-agent.sh" %s "$@"\n' "$D" "$a" "$D" "$a" > "$D/fakebin/$a"
  chmod +x "$D/fakebin/$a"
done

cat > "$D/zdot/.zshrc" <<EOF
PROMPT='rar%# '
path=("$D/fakebin" \$path)
source "$ROOT/share/rex-agent-restore/rex-agent-restore.zsh"
EOF

# The Rex config the installer would write, plus the module link.
ln -sf "$ROOT/share/rex-agent-restore/rex-agent-restore.lua" "$D/rexcfg/rex_agent_restore.lua"
cat > "$D/rexcfg/init.lua" <<EOF
-- >>> rex-agent-restore >>>
local ok_rar, rar = pcall(require, "rex_agent_restore")
if ok_rar and type(rar) == "table" then rar.setup({ bin = "$BIN" }) end
-- <<< rex-agent-restore <<<
EOF

echo "e2e (test server at $D)"
start_server
out="$(R new e2e -c "$D/proj dir" --json)"
SID="$(printf '%s' "$out" | jq -r .session_id)"
B1="$(printf '%s' "$out" | jq -r '.initial_windows[0].block_ids[0]')"
check "pane shell is ready" 'wait_for 10 screen_has "$B1" "rar%"' "$(R capture -s "$SID" -b "$B1" --trim 2>&1 | tail -5)"
R send -s "$SID" -b "$B1" 'echo "ENV:$ZDOTDIR:${REX_AGENT_RESTORE_SHELL_TOKEN:+token}"'$'\r'
check "pane gets the test environment and the integration" 'wait_for 5 screen_has "$B1" "ENV:$D/zdot:token"' "$(R capture -s "$SID" -b "$B1" --trim | tail -5)"

check "Rex loaded the plugin actions" 'R actions 2>/dev/null | grep -q agent_restore_resume_all' "$(R actions 2>&1 | head -20)"

# 1. A chat that's quit normally is forgotten.
R send -s "$SID" -b "$B1" 'claude'$'\r'
check "agent starts and saves its chat" 'wait_for 10 test -s "$(rec "$B1")"' "$(date -u +%T) $(R capture -s "$SID" -b "$B1" --trim --unwrap | tail -4)"
first="$(chat_id "$B1")"
R send -s "$SID" -b "$B1" $'\r'
check "quitting the agent forgets the chat" 'wait_for 5 test ! -e "$(rec "$B1")"'

# 2. A chat cut off by a server restart comes back.
R send -s "$SID" -b "$B1" 'claude'$'\r'
wait_for 5 test -s "$(rec "$B1")"
c1="$(chat_id "$B1")"
B2="$(R split -s "$SID" -b "$B1" --focus=false --json | jq -r '.block_ids[0]')"
wait_for 10 screen_has "$B2" "rar%"
R send -s "$SID" -b "$B2" 'codex'$'\r'
check "second pane saves a codex chat" 'wait_for 5 test -s "$(rec "$B2")"'
c2="$(chat_id "$B2")"

stop_server
check "saved chats survive the server stopping" '[ -s "$(rec "$B1")" ] && [ -s "$(rec "$B2")" ]'
start_server
check "claude chat resumes after restart" 'wait_for 15 log_has "claude resumed $c1"' "$(cat "$LOG")"
check "codex chat resumes after restart" 'wait_for 15 log_has "codex resumed $c2"' "$(cat "$LOG")"
check "resumed agent is running in the pane" 'wait_for 5 screen_has "$B1" "FAKE claude READY $c1"' "$(R capture -s "$SID" -b "$B1" --trim | tail -5)"
check "resumed agent runs in the saved folder" '[ "$(R block call -s "$SID" -b "$B1" process | jq -r .foreground.cwd)" = "$D/proj dir" ]'
R send -s "$SID" -b "$B1" $'\r'
R send -s "$SID" -b "$B2" $'\r'
check "quitting a resumed agent forgets it" 'wait_for 5 test ! -e "$(rec "$B1")" && wait_for 5 test ! -e "$(rec "$B2")"'
check "the first chat was never resumed" '[ -n "$first" ] && ! log_has "resumed $first"'

# 3. Prompt mode types the command and waits for Enter.
echo 'REX_AGENT_RESTORE_MODE=prompt' > "$D/config"
wait_for 5 at_prompt "$B1"
R send -s "$SID" -b "$B1" 'claude'$'\r'
wait_for 5 test -s "$(rec "$B1")"
c3="$(chat_id "$B1")"
stop_server
start_server
check "prompt mode puts the resume command on the command line" "wait_for 10 screen_has \"\$B1\" \"claude --resume '\$c3'\"" "$(R capture -s "$SID" -b "$B1" --trim | tail -5)"
check "prompt mode doesn't run it by itself" '! log_has "claude resumed $c3"'
R send -s "$SID" -b "$B1" $'\r'
check "pressing Enter resumes it" 'wait_for 5 log_has "claude resumed $c3"'
R send -s "$SID" -b "$B1" $'\r'
wait_for 5 at_prompt "$B1"

# 4. Off mode leaves it to the Rex action.
echo 'REX_AGENT_RESTORE_MODE=off' > "$D/config"
R send -s "$SID" -b "$B1" 'claude'$'\r'
wait_for 5 test -s "$(rec "$B1")"
c4="$(chat_id "$B1")"
stop_server
start_server
wait_for 10 screen_has "$B1" "rar%"
sleep 1
check "off mode doesn't resume" '! log_has "claude resumed $c4" && [ -e "$(rec "$B1")" ]'
out="$(R do agent_restore_resume_all --json 2>&1)"
check "the Rex action resumes it" 'wait_for 5 log_has "claude resumed $c4"' "$out"
R send -s "$SID" -b "$B1" $'\r'
check "and it's forgotten after quitting" 'wait_for 5 test ! -e "$(rec "$B1")"'

# 5. Panes that are closed get pruned.
rm -f "$D/config"
wait_for 5 at_prompt "$B2"
R send -s "$SID" -b "$B2" 'codex'$'\r'
wait_for 5 test -s "$(rec "$B2")"
R block close -s "$SID" "$B2" >/dev/null 2>&1
sleep 0.5
out="$(REX_AGENT_RESTORE_STATE_DIR="$D/state" "$BIN" prune 2>&1)"
check "prune forgets chats for closed panes" '[ ! -e "$(rec "$B2")" ]'

# 6. Importing herdr workspaces.
mkdir -p "$D/herdr-proj"
cat > "$D/herdr-session.json" <<EOF
{ "version": 3, "active": 0, "selected": 0,
  "workspaces": [ { "id": "w9", "custom_name": null, "identity_cwd": "$D/herdr-proj", "active_tab": 0,
    "tabs": [
      { "custom_name": "Two panes", "zoomed": false, "focused": 1, "root_pane": 1,
        "layout": { "Split": { "direction": "Horizontal", "ratio": 0.6, "first": { "Pane": 1 }, "second": { "Pane": 2 } } },
        "panes": { "1": { "cwd": "$D/herdr-proj", "label": "Fix the thing",
                          "agent_session": { "source": "herdr:claude", "agent": "claude", "kind": "id", "value": "h-claude-1" } },
                   "2": { "cwd": "$D/herdr-proj" } } },
      { "custom_name": null, "zoomed": false, "focused": 3, "root_pane": 3,
        "layout": { "Pane": 3 },
        "panes": { "3": { "cwd": "$D/herdr-proj",
                          "agent_session": { "source": "herdr:codex", "agent": "codex", "kind": "id", "value": "h-codex-1" } } } } ] } ] }
EOF
imp() { REX_SERVER="$SOCK" REX_AGENT_RESTORE_STATE_DIR="$D/state" "$BIN" import-herdr --file "$D/herdr-session.json" --force "$@" 2>&1; }
out="$(imp --dry-run)"
check "import dry run lists the panes" 'echo "$out" | grep -q "claude --resume '"'"'h-claude-1'"'"'" && echo "$out" | grep -q "(shell)"' "$out"
check "import dry run creates nothing" '! R ls --json | jq -e ".sessions[] | select(.label == \"herdr-proj\")" >/dev/null'
out="$(imp)"
HS="$(R ls --json | jq -r '.sessions[] | select(.label == "herdr-proj") | .session_id')"
check "import creates a Rex session named after the workspace" '[ -n "$HS" ]' "$out"
check "imported chats are resumed" 'wait_for 15 log_has "claude resumed h-claude-1" && wait_for 15 log_has "codex resumed h-codex-1"' "$out
$(cat "$LOG")"
check "import keeps tabs and splits" '[ "$(R session inspect "$HS" --json | jq "[.windows[]] | length")" = 2 ] && [ "$(R block ls -s "$HS" --json | jq ".blocks | length")" = 3 ]'
saved_chats() { cat "$D"/state/panes/*.json 2>/dev/null | jq -r .chat_id | sort | tr '\n' ' '; }
check "imported chats are saved for the next restart" 'wait_for 10 sh -c "cat \"$D\"/state/panes/*.json | grep -q h-claude-1 && cat \"$D\"/state/panes/*.json | grep -q h-codex-1"' "$(saved_chats)"
out="$(imp)"
check "importing again skips the workspace" 'echo "$out" | grep -q "already imported"' "$out"
: > "$LOG"
stop_server
start_server
check "imported chats come back after a restart" 'wait_for 15 log_has "claude resumed h-claude-1" && wait_for 15 log_has "codex resumed h-codex-1"' "$(cat "$LOG")"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
