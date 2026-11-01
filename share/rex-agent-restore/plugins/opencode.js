// rex-agent-restore: tell Rex which OpenCode session this pane's TUI shows.
// One TUI-only module for both OpenCode lines:
//   V2 (2.x): discovered as ~/.config/opencode/plugins/rex-agent-restore/tui.js
//             (or listed in cli.json "plugins"); calls setup(context).
//   V1 (1.x): listed in tui.json(c) "plugin"; calls tui(api).
// It runs in the TUI process, which inherits this pane's REX_BLOCK. Server-side
// plugins don't: V2's shared background service serves every pane.
// Managed by rex-agent-restore.
import { spawn } from "node:child_process";

const BIN = "__REX_AGENT_RESTORE_BIN__";
const POLL_MS = 1000;

function report(session, cwd, source) {
  try {
    const child = spawn(BIN, ["hook", "opencode"], {
      detached: true,
      stdio: ["pipe", "ignore", "ignore"],
    });
    child.on("error", () => {});
    child.stdin?.on("error", () => {});
    child.stdin?.end(
      JSON.stringify({ hook_event_name: "SessionStart", session_id: session, cwd, source }),
    );
    child.unref();
  } catch {}
}

// Calls current() every POLL_MS; reports each new root session it returns.
// There is no route-change event, so polling is the portable way.
function watch(current) {
  let last;
  const tick = () => {
    try {
      const found = current();
      if (!found || found.id === last) return;
      report(found.id, found.cwd || process.cwd(), last === undefined ? "startup" : "resume");
      last = found.id;
    } catch {}
  };
  tick();
  const timer = setInterval(tick, POLL_MS);
  timer.unref?.();
  return () => clearInterval(timer);
}

// V1: api.route.current = { name: "session", params: { sessionID } };
// api.state.session.get(id) -> { id, parentID?, directory }.
function v1(api) {
  return watch(() => {
    const route = api.route.current;
    let id = route?.name === "session" ? route.params?.sessionID : undefined;
    let info = id ? api.state.session.get(id) : undefined;
    for (let i = 0; info?.parentID && i < 32; i++) {
      id = info.parentID; // a subagent's chat: report its root session
      info = api.state.session.get(id);
    }
    return id && info ? { id, cwd: info.directory } : undefined;
  });
}

// V2: api.ui.router.current() = { type: "session", sessionID };
// api.data.session.root(id), .get(id) -> { location: { directory } }.
function v2(api) {
  return watch(() => {
    const route = api.ui.router.current();
    if (route?.type !== "session" || !route.sessionID) return undefined;
    const id = api.data.session.root(route.sessionID) || route.sessionID;
    const info = api.data.session.get(id);
    if (!info) return undefined; // not loaded yet; try again next tick
    return { id, cwd: info.location?.directory || api.location?.directory };
  });
}

export default {
  id: "rex-agent-restore",
  setup(api) {
    if (!process.env.REX_BLOCK) return;
    try {
      return v2(api);
    } catch {}
  },
  async tui(api) {
    if (!process.env.REX_BLOCK) return;
    try {
      const stop = v1(api);
      api.lifecycle?.onDispose?.(stop);
    } catch {}
  },
};
