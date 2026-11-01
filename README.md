# Rex Agent Restore

[![test](https://github.com/pattont/RexAgentRestore/actions/workflows/test.yml/badge.svg)](https://github.com/pattont/RexAgentRestore/actions/workflows/test.yml)

**Restart Rex and your agent chats come back.**

[Rex](https://www.superlogical.com/rex) restores your sessions, tabs, panes,
and scrollback after its server restarts, but each pane gets a fresh shell.
The coding agent chat that was running there is gone.

Rex Agent Restore puts it back. Each pane resumes the same chat, in the same
folder, as if Rex had never stopped. It works with 17 coding agents, and
nothing runs in the background.

## Install

```sh
brew tap pattont/rex-agent-restore https://github.com/pattont/RexAgentRestore
brew trust --formula pattont/rex-agent-restore/rex-agent-restore
brew install rex-agent-restore
rex-agent-restore install
```

Then open a new terminal tab.

- `brew trust` is how Homebrew 7 lets you install from a tap outside Homebrew.
- `rex-agent-restore install` finds the agents you have and sets each one up
  (see [What it touches](#what-it-touches)).
- **Using Codex?** Codex runs a new hook only after you approve it. Run `/hooks`
  in Codex once and approve `rex-agent-restore`.

### Before your first restart

Chats that were already open when you installed haven't been saved yet. Save
them:

```sh
rex-agent-restore capture
```

### Coming from herdr

Recreate your herdr workspaces in Rex, with the same tabs and splits, and every
agent pane resuming its chat:

```sh
rex-agent-restore import-herdr --dry-run   # see what it would create
herdr server stop                          # so no chat runs in two places
rex-agent-restore import-herdr
```

It skips workspaces it has already imported.

## Supported agents

| Agent | How it hooks in | Resumes with |
| --- | --- | --- |
| Claude Code | `SessionStart` hook | `claude --resume <id>` |
| Codex | `SessionStart` hook (approve once in `/hooks`) | `codex resume <id>` |
| OpenCode 2.x | TUI plugin | `opencode --session <id>` |
| Grok Build | `SessionStart` hook | `grok --resume <id>` |
| Gemini CLI | `SessionStart` hook | `gemini --resume <id>` |
| GitHub Copilot CLI | `SessionStart` hook | `copilot --resume=<id>` |
| Cursor Agent | `sessionStart` hook | `cursor-agent --resume <id>` |
| Factory Droid | `SessionStart` hook | `droid --resume <id>` |
| Antigravity CLI | `SessionStart` and `PreInvocation` hooks | `agy --conversation <id>` |
| Devin CLI | `SessionStart` hook | `devin --resume <id>` |
| Kimi Code | `SessionStart` hook | `kimi --session <id>` |
| Qoder CLI | `SessionStart` hook | `qoder --resume <id>` |
| Qwen Code | `SessionStart` hook | `qwen --resume <id>` |
| Letta Code | `SessionStart` hook | `letta --conversation <id>` |
| pi | extension | `pi --session <file>` |
| oh-my-pi | extension | `omp --resume=<file>` |
| Kilo Code CLI | plugin | `kilo --session <id>` |

**How well each one is tested:**
- **Against the real agent** (save, restart, resume): Claude Code and OpenCode.
- **Every agent:** automated tests check its hook file format and its event
  fields, built from that agent's own documentation and source.

If an agent doesn't come back for you, please
[open an issue](https://github.com/pattont/RexAgentRestore/issues) with the
output of `REX_AGENT_RESTORE_DEBUG=1`.

**Not supported yet:**
- **Hermes Agent:** runs every chat in one shared background process, so a chat
  can't be tied to its pane.
- **MastraCode:** its hooks don't reliably report the chat ID.

## How it works

```text
 agent starts a chat ──► hook saves { pane ID → agent, chat ID, folder }
 you quit the agent  ──► your prompt returns, the saved chat is deleted
 Rex restarts        ──► shell is killed mid-chat, the saved chat is kept
 Rex restores pane   ──► same pane ID, new shell finds the saved chat and
                          runs the agent's resume command in that folder
```

1. **Save.** When an agent starts or switches chats, its hook (or plugin) runs
   `rex-agent-restore hook`. That saves the chat ID and folder under the Rex
   pane's ID (`$REX_BLOCK`), in `~/.local/state/rex-agent-restore/`.
2. **Forget.** When you quit an agent normally, your shell's prompt comes back,
   and the shell integration deletes that pane's saved chat. When Rex shuts
   down, the shell dies with the agent, so the saved chat stays.
3. **Resume.** Rex keeps a pane's ID across restarts. When a restored pane's
   shell shows its first prompt and finds a saved chat, it runs the agent's
   resume command in the chat's folder and adds it to your shell history.

The hook works out which agent is really running from the process tree. So:
- Subagents never replace a pane's saved chat.
- Agents started from inside another agent never do either, such as a
  `claude -p` run by a tool.
- Agents that also run Claude Code's hooks (Grok, Cursor and others) are saved
  under their own name.

## What it touches

| File | Change |
| --- | --- |
| Each agent's hook settings (see the table above) | adds one hook entry, next to your existing hooks |
| A plugin folder, for OpenCode, pi, oh-my-pi and Kilo | adds one file, `rex-agent-restore` |
| `~/.zshrc` or `~/.bashrc` | one line that loads the shell integration |
| `~/.config/rex/init.lua` | three Rex palette actions |

- **It never approves a hook for you.** Agents that ask you to trust or approve
  hooks, such as Codex, Gemini and Grok, still ask.
- **Your files are backed up first**, as `<file>.bak-rex-agent-restore`.
- **Other hooks are left alone.** Running `install` again changes nothing.
- **It makes no network calls.** Saved chats are small JSON files in
  `~/.local/state/rex-agent-restore/`, readable only by you.
- **`capture` and `import-herdr` only read** other tools' files: Claude Code's
  per-process session files, Codex's thread database, and herdr's
  `session.json`.
- **You can preview and undo:** `rex-agent-restore install --dry-run` shows
  every change, and `rex-agent-restore uninstall` removes all of it.

## Use

There's nothing to do: restart Rex and your chats come back. The Rex command
palette has three actions for doing it by hand:

- **Resume Saved Agent Chats**: resume every saved chat whose pane is at a prompt
- **Resume Saved Agent Chat in This Pane**
- **Forget Saved Agent Chat for This Pane**

From the command line:

```text
rex-agent-restore list           show saved chats
rex-agent-restore capture        save the chats of agents running right now
rex-agent-restore import-herdr   recreate herdr's workspaces in Rex
rex-agent-restore resume         resume this pane's saved chat
rex-agent-restore resume-all     resume every saved chat whose pane is at a prompt
rex-agent-restore forget         forget this pane's saved chat (--all for every pane)
rex-agent-restore doctor         check the setup
```

## Settings

Put settings in `~/.config/rex-agent-restore/config`, one per line, or set them
as environment variables.

| Setting | Effect |
| --- | --- |
| `REX_AGENT_RESTORE_MODE=auto` | resume on its own (default) |
| `REX_AGENT_RESTORE_MODE=prompt` | type the resume command and wait for you to press Enter |
| `REX_AGENT_RESTORE_MODE=off` | do nothing; use the palette actions instead |
| `REX_AGENT_RESTORE_<AGENT>_ARGS="..."` | extra arguments for that agent's resume command, e.g. `REX_AGENT_RESTORE_CLAUDE_ARGS="--dangerously-skip-permissions"` |
| `REX_AGENT_RESTORE_DISABLE=1` | stop saving chats |
| `REX_AGENT_RESTORE_DEBUG=1` | log hook decisions to `~/.local/state/rex-agent-restore/debug.log` |

To bind a key to a palette action, edit the `rar.setup(...)` line in
`~/.config/rex/init.lua`:

```lua
rar.setup({ bin = "/opt/homebrew/bin/rex-agent-restore", keys = { resume_all = "shift+cmd+r" } })
```

## Limits

- **Empty chats can't be resumed.** Most agents don't save a chat until you
  send a message.
- **Startup flags aren't repeated.** The resume command doesn't include the flags
  you first started the agent with. Use the `*_ARGS` settings for flags you
  always want.
- **Some agents only run hooks in trusted folders**, such as Gemini CLI and Grok
  Build. Chats in folders you haven't trusted aren't saved.
- **Panes without a shell aren't resumed.** A pane that runs an agent directly
  (`rex run -- claude`) has no shell to resume the chat.
- **Plugins load when the agent starts.** Restart OpenCode, pi, oh-my-pi or Kilo
  after installing.

## Uninstall

```sh
rex-agent-restore uninstall
brew uninstall rex-agent-restore
```

## Development

```sh
make test       # unit tests, in a throwaway HOME
make test-e2e   # starts a separate, throwaway Rex server, restarts it, checks chats come back
```

The end-to-end test uses its own socket and state folder, so your Rex server and
sessions aren't touched. Release with `scripts/release.sh <version>`, which tags,
pushes, and updates the formula's URL and checksum.

Inspired by [herdr](https://herdr.dev), which restores agent chats the same way,
and [herdr2rex](https://github.com/tornikegomareli/herdr2rex), which showed how
to rebuild herdr workspaces in Rex.

## License

MIT
