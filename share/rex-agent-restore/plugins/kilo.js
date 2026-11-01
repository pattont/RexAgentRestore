// rex-agent-restore: tell Rex which Kilo session runs in this pane.
// Install as ~/.config/kilo/plugin/rex-agent-restore.js (auto-loaded; no config entry).
// Managed by rex-agent-restore.
import { spawn } from "node:child_process";

const BIN = "__REX_AGENT_RESTORE_BIN__";

function report(session, cwd, source) {
  try {
    const child = spawn(BIN, ["hook", "kilo"], {
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

const server = async ({ directory }) => {
  // Only the server Kilo's TUI embeds for this pane. A shared `kilo daemon`
  // or `kilo serve` (VS Code) has some other process's environment.
  if (!process.env.REX_BLOCK || process.env.KILO_PROCESS_ROLE !== "worker") return {};
  const parents = new Map(); // child session id -> parent id
  const dirs = new Map();
  let last;
  const root = (id) => {
    for (let i = 0; parents.has(id) && i < 32; i++) id = parents.get(id);
    return id;
  };
  const note = (id, source) => {
    if (!id || id === last) return;
    last = id;
    report(id, dirs.get(id) || directory || process.cwd(), source);
  };
  return {
    event: async ({ event }) => {
      try {
        const info = event?.properties?.info;
        if (event?.type !== "session.created" || !info?.id) return;
        if (info.directory) dirs.set(info.id, info.directory);
        if (info.parentID) parents.set(info.id, info.parentID);
        else note(info.id, "startup");
      } catch {}
    },
    // The user sent a prompt: catches sessions opened with --session, /sessions, etc.
    "chat.message": async (input) => {
      try {
        note(root(input?.sessionID), "resume");
      } catch {}
    },
  };
};

export default { id: "rex-agent-restore", server };
