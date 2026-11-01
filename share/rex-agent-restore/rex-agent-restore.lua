-- rex-agent-restore: Rex actions for saved agent chats.
--
-- `rex-agent-restore install` links this file into ~/.config/rex and adds
-- these lines to init.lua:
--
--   local ok_rar, rar = pcall(require, "rex_agent_restore")
--   if ok_rar and type(rar) == "table" then rar.setup({ bin = "/opt/homebrew/bin/rex-agent-restore" }) end
--
-- setup() options:
--   bin   path to the rex-agent-restore program (default: found on PATH)
--   keys  table of key bindings, for example
--         { resume_all = "shift+cmd+r", resume_pane = nil, forget_pane = nil }

local M = {}

function M.setup(opts)
  opts = opts or {}
  local bin = opts.bin or "rex-agent-restore"

  local function run(args)
    local argv = { bin }
    for _, a in ipairs(args) do
      argv[#argv + 1] = a
    end
    local r, err = rex.exec(argv, { timeout = 25 })
    if r == nil then
      error(err, 0)
    end
    if not r.ok then
      local msg = r.stderr
      if msg == nil or msg == "" then
        msg = r.stdout
      end
      error(msg, 0)
    end
    return { output = r.stdout }
  end

  local function pane_args(ctx, cmd)
    if ctx.block_id == nil then
      error("no pane is focused", 0)
    end
    local args = { cmd, "--block", ctx.block_id }
    if ctx.session_id ~= nil and cmd == "resume" then
      args[#args + 1] = "--session"
      args[#args + 1] = ctx.session_id
    end
    return args
  end

  rex.action({
    name = "agent_restore_resume_all",
    title = "Resume Saved Agent Chats",
    description = "Resume every saved Claude Code, Codex, or Grok chat whose pane is at a shell prompt.",
    category = "Agent Restore",
    keywords = "claude codex grok agent chat restore resume",
    run = function(ctx, args)
      return run({ "resume-all" })
    end,
  })

  rex.action({
    name = "agent_restore_resume_pane",
    title = "Resume Saved Agent Chat in This Pane",
    description = "Resume the chat that was running in the focused pane.",
    category = "Agent Restore",
    keywords = "claude codex grok agent chat restore resume",
    run = function(ctx, args)
      return run(pane_args(ctx, "resume"))
    end,
  })

  rex.action({
    name = "agent_restore_forget_pane",
    title = "Forget Saved Agent Chat for This Pane",
    description = "Stop this pane from resuming its saved chat.",
    category = "Agent Restore",
    keywords = "claude codex grok agent chat forget",
    run = function(ctx, args)
      local a = pane_args(ctx, "forget")
      -- forget takes the pane ID as a plain argument.
      return run({ "forget", a[3] })
    end,
  })

  local keys = opts.keys or {}
  if keys.resume_all then
    rex.bind(keys.resume_all, "agent_restore_resume_all")
  end
  if keys.resume_pane then
    rex.bind(keys.resume_pane, "agent_restore_resume_pane")
  end
  if keys.forget_pane then
    rex.bind(keys.forget_pane, "agent_restore_forget_pane")
  end
end

return M
