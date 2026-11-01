// rex-agent-restore: tell Rex which pi session runs in this pane.
// Install as ~/.pi/agent/extensions/rex-agent-restore.ts
// (or $PI_CODING_AGENT_DIR/extensions/). Managed by rex-agent-restore.
import { spawn } from "node:child_process";

const BIN = "__REX_AGENT_RESTORE_BIN__";

function report(session: string, cwd: string, source: string): void {
  try {
    const child = spawn(BIN, ["hook", "pi"], {
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

export default function (pi: any) {
  if (!process.env.REX_BLOCK) return;
  // Fires at startup and again after /new, /resume, /fork, /clone and /reload,
  // each time with the replacement session's context.
  pi.on("session_start", (event: any, ctx: any) => {
    try {
      if (ctx?.hasUI === false) return; // print/JSON mode: not an interactive chat
      const sm = ctx?.sessionManager;
      // The file path resumes reliably with `pi --session <path>`, even before
      // pi has written it (pi creates the file on the first message).
      const session = sm?.getSessionFile?.() || "";
      if (!session) return; // --no-session
      report(session, ctx?.cwd || sm?.getCwd?.() || process.cwd(), String(event?.reason || "startup"));
    } catch {}
  });
}
