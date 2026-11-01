# Rex Agent Restore

When the [Rex](https://www.superlogical.com/rex) server restarts, it brings back
your sessions, tabs, panes, folders, and scrollback, but each pane starts a
fresh shell. Any Claude Code, Codex, or Grok Build chat that was running there
is gone.

**Rex Agent Restore brings those chats back.** After a restart, each pane that
had an agent running resumes the same chat, in the same folder, as if Rex had
never stopped.

Nothing runs in the background. The agents save their own chat IDs when a
chat starts, and your shell resumes the chat when Rex restores the pane.

## Install

```sh
brew tap pattont/rex-agent-restore https://github.com/pattont/RexAgentRestore
brew install rex-agent-restore
rex-agent-restore install
```

Then open a new terminal, or run `exec $SHELL`.

Homebrew can't change files in your home folder, so the last command does the
setup:

| Where | What it adds |
| --- | --- |
| `~/.claude/settings.json` | a `SessionStart` hook for Claude Code |
| `~/.codex/hooks.json` | a `SessionStart` hook for Codex (and turns on `[features] hooks` in `~/.codex/config.toml` if it's off) |
| `~/.grok/hooks/rex-agent-restore.json` | a `SessionStart` hook for Grok Build |
| `~/.zshrc` (or `~/.bashrc`) | one line that loads the shell integration |
| `~/.config/rex/init.lua` | three Rex actions (see below) |

It only sets up agents you have installed. Every file is backed up first (as
`<file>.bak-rex-agent-restore`). Your other hooks stay as they are, and
running `install` again changes nothing. To see the changes without making
them, run `rex-agent-restore install --dry-run`.

**Codex:** Codex asks you to approve new hooks. After installing, run `/hooks`
in Codex once and approve the `rex-agent-restore` hook.

**Grok Build:** Grok runs your hooks only in folders you've trusted.

## How it works

1. **Saving the chat.** When an agent starts or resumes a chat, its
   `SessionStart` hook runs `rex-agent-restore hook`. The hook reads the chat ID
   and folder, and saves them under the Rex pane's ID (`$REX_BLOCK`) in
   `~/.local/state/rex-agent-restore/panes/`.
2. **Forgetting finished chats.** When you quit an agent and your prompt comes
   back, the shell integration deletes that pane's saved chat. When Rex shuts
   down, the shell is killed too, so the prompt never comes back and the saved
   chat stays.
3. **Resuming.** Rex keeps a pane's ID across restarts. When a restored pane's
   shell shows its first prompt and finds a saved chat for its pane, it runs:

   | Agent | Command |
   | --- | --- |
   | Claude Code | `claude --resume <id>` |
   | Codex | `codex resume <id>` |
   | Grok Build | `grok --resume <id>` |

   It runs the command in the chat's folder and adds it to your shell history.

The hook ignores subagents and agents started from inside another agent, such
as a `claude -p` run by a tool. Those never take over the pane's saved chat.

## Rex actions

Find these in the Rex command palette:

- **Resume Saved Agent Chats**: resume every saved chat whose pane is at a
  shell prompt.
- **Resume Saved Agent Chat in This Pane**
- **Forget Saved Agent Chat for This Pane**

To bind keys, edit the `rar.setup(...)` line in `~/.config/rex/init.lua`:

```lua
rar.setup({ bin = "/opt/homebrew/bin/rex-agent-restore", keys = { resume_all = "shift+cmd+r" } })
```

## Settings

Put settings in `~/.config/rex-agent-restore/config`, one per line, or set them
in your environment:

```sh
# auto (default): resume by itself
# prompt: type the resume command for you and wait for Enter
# off: do nothing; use the Rex action instead
REX_AGENT_RESTORE_MODE=auto

# Extra arguments for each resume command
REX_AGENT_RESTORE_CLAUDE_ARGS="--dangerously-skip-permissions"
REX_AGENT_RESTORE_CODEX_ARGS=""
REX_AGENT_RESTORE_GROK_ARGS=""

# Stop saving chats
REX_AGENT_RESTORE_DISABLE=1

# Log the hook's decisions to ~/.local/state/rex-agent-restore/debug.log
REX_AGENT_RESTORE_DEBUG=1
```

## Commands

```text
rex-agent-restore install      set everything up
rex-agent-restore uninstall    undo it
rex-agent-restore doctor       check the setup
rex-agent-restore list         show saved chats
rex-agent-restore resume       resume this pane's saved chat
rex-agent-restore resume-all   resume every saved chat whose pane is at a prompt
rex-agent-restore forget       forget this pane's saved chat (or --all)
rex-agent-restore prune        forget chats for panes that were closed
```

## Limits

- Supports zsh and bash.
- A chat with no messages has nothing to resume. Claude Code doesn't save a chat
  until you send something.
- The resume command doesn't repeat the flags you first started the agent with.
  Use the `*_ARGS` settings for flags you always want.
- Panes that run an agent directly, without a shell (for example
  `rex run -- claude`), aren't resumed.

## Uninstall

```sh
rex-agent-restore uninstall
brew uninstall rex-agent-restore
```

## Development

```sh
make test       # unit tests in a throwaway HOME
make test-e2e   # starts a separate, throwaway Rex server and restarts it
```

The end-to-end test uses its own socket and state folder, so your Rex server
and sessions aren't touched.

To cut a release: `scripts/release.sh 0.1.1`. It tags the version, pushes the
tag, and updates the formula's URL and checksum.

The idea comes from [herdr](https://herdr.dev), which restores agent chats the
same way.

## License

MIT
