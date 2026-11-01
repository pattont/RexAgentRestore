// rex-agent-restore: tell Rex which omp session runs in this pane.
// Install as ~/.omp/agent/extensions/rex-agent-restore.ts (agent dir: $PI_CODING_AGENT_DIR,
// else ~/$PI_CONFIG_DIR/agent, else ~/.omp/agent). Managed by rex-agent-restore.
import { spawn } from "node:child_process";

const BIN = "__REX_AGENT_RESTORE_BIN__";
let last = "";

function report(ctx: any, source: string): void {
  try {
    if (ctx?.agent?.kind === "sub") return; // subagents, /tan clones
    if (ctx?.hasUI === false) return; // print/JSON/RPC mode
    const sm = ctx?.sessionManager;
    const session = sm?.getSessionFile?.() || sm?.getSessionId?.() || "";
    if (!session || session === last) return;
    last = session;
    const child = spawn(BIN, ["hook", "omp"], {
      detached: true,
      stdio: ["pipe", "ignore", "ignore"],
    });
    child.on("error", () => {});
    child.stdin?.on("error", () => {});
    child.stdin?.end(
      JSON.stringify({
        hook_event_name: "SessionStart",
        session_id: session,
        cwd: ctx?.cwd || sm?.getCwd?.() || process.cwd(),
        source,
      }),
    );
    child.unref();
  } catch {}
}

export default function (pi: any) {
  if (!process.env.REX_BLOCK) return;
  pi.on("session_start", (_e: any, ctx: any) => report(ctx, "startup"));
  // /new, /resume, fork: event.reason is "new" | "resume" | "fork".
  pi.on("session_switch", (e: any, ctx: any) => report(ctx, String(e?.reason || "resume")));
  // /branch, fork-at-entry and /btw promotion move to a new session file.
  pi.on("session_branch", (e: any, ctx: any) => report(ctx, String(e?.reason || "branch")));
}
