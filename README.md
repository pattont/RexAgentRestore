# Rex Agent Restore

[![test](https://github.com/pattont/RexAgentRestore/actions/workflows/test.yml/badge.svg)](https://github.com/pattont/RexAgentRestore/actions/workflows/test.yml)

**Restart Rex and your agent chats come back.**

[Rex](https://www.superlogical.com/rex) restores your sessions, tabs, panes,
and scrollback after its server restarts, but each pane gets a fresh shell.
The Claude Code, Codex, or Grok Build chat that was running there is gone.

Rex Agent Restore puts it back. Each pane resumes the same chat, in the same
folder, as if Rex had never stopped. Nothing runs in the background.

## Install

```sh
brew tap pattont/rex-agent-restore https://github.com/pattont/RexAgentRestore
brew trust --formula pattont/rex-agent-restore/rex-agent-restore
brew install rex-agent-restore
rex-agent-restore install
```

Then open a new terminal tab.

- `brew trust` is how Homebrew 7 lets you install from a tap outside Homebrew.
- `rex-agent-restore install` does the setup that Homebrew isn't allowed to do
  in your home folder (see [What install changes](#what-install-changes)).
- **Using Codex?** Run `/hooks` in Codex once and approve the
  `rex-agent-restore` hook.

Requires macOS, Rex, zsh or bash, and at least one of Claude Code, Codex, or
Grok Build.

## How it works

```text
 agent starts a chat ──► hook saves { pane ID → agent, chat ID, folder }
 you quit the agent  ──► your prompt returns, the saved chat is deleted
 Rex restarts        ──► shell is killed mid-chat, the saved chat is kept
 Rex restores pane   ──► same pane ID, new shell finds the saved chat and runs:
                           claude --resume <id>
                           codex resume <id>
                           grok --resume <id>
```

1. **Save.** Each agent runs a `SessionStart` hook when a chat starts. The hook
   saves the chat ID and folder under the Rex pane's ID (`$REX_BLOCK`), in
   `~/.local/state/rex-agent-restore/`.
2. **Forget.** When you quit an agent normally, your shell's prompt comes back,
   and the shell integration deletes that pane's saved chat. When Rex shuts
   down, the shell dies with the agent, so the saved chat stays.
3. **Resume.** Rex keeps a pane's ID across restarts. When a restored pane's
   shell shows its first prompt and finds a saved chat, it resumes that chat in
   its folder and adds the command to your shell history.

Subagents, and agents started from inside another agent (such as a `claude -p`
run by a tool), never replace a pane's saved chat.

## What install changes

| File | Change |
| --- | --- |
| `~/.claude/settings.json` | adds a `SessionStart` hook |
| `~/.codex/hooks.json` | adds a `SessionStart` hook, and turns on `[features] hooks` in `config.toml` if needed |
| `~/.grok/hooks/rex-agent-restore.json` | new file with a `SessionStart` hook |
| `~/.zshrc` or `~/.bashrc` | one line that loads the shell integration |
| `~/.config/rex/init.lua` | three Rex palette actions |

- It only sets up the agents you have installed.
- It backs up every file first, as `<file>.bak-rex-agent-restore`.
- It adds its hooks alongside your existing ones and leaves those alone.
- Running it again changes nothing.
- Preview the changes with `rex-agent-restore install --dry-run`.
- Undo everything with `rex-agent-restore uninstall`.

## Use

There's nothing to do: restart Rex and your chats come back. The Rex command
palette has three actions for doing it by hand:

- **Resume Saved Agent Chats**: resume every saved chat whose pane is at a prompt
- **Resume Saved Agent Chat in This Pane**
- **Forget Saved Agent Chat for This Pane**

From the command line:

```text
rex-agent-restore list         show saved chats
rex-agent-restore resume       resume this pane's saved chat
rex-agent-restore resume-all   resume every saved chat whose pane is at a prompt
rex-agent-restore forget       forget this pane's saved chat (--all for every pane)
rex-agent-restore doctor       check the setup
```

## Settings

Put settings in `~/.config/rex-agent-restore/config`, one per line, or set them
as environment variables.

| Setting | Effect |
| --- | --- |
| `REX_AGENT_RESTORE_MODE=auto` | resume on its own (default) |
| `REX_AGENT_RESTORE_MODE=prompt` | type the resume command and wait for you to press Enter |
| `REX_AGENT_RESTORE_MODE=off` | do nothing; use the palette actions instead |
| `REX_AGENT_RESTORE_CLAUDE_ARGS="..."` | extra arguments for `claude --resume`, such as `--dangerously-skip-permissions` |
| `REX_AGENT_RESTORE_CODEX_ARGS="..."` | extra arguments for `codex resume` |
| `REX_AGENT_RESTORE_GROK_ARGS="..."` | extra arguments for `grok --resume` |
| `REX_AGENT_RESTORE_DISABLE=1` | stop saving chats |
| `REX_AGENT_RESTORE_DEBUG=1` | log hook decisions to `~/.local/state/rex-agent-restore/debug.log` |

To bind a key to a palette action, edit the `rar.setup(...)` line in
`~/.config/rex/init.lua`:

```lua
rar.setup({ bin = "/opt/homebrew/bin/rex-agent-restore", keys = { resume_all = "shift+cmd+r" } })
```

## Limits

- **Empty chats can't be resumed.** Claude Code doesn't save a chat until you
  send a message.
- **Startup flags aren't repeated.** The resume command doesn't include the flags
  you first started the agent with. Use the `*_ARGS` settings for flags you
  always want.
- **Grok Build** runs your hooks only in folders you've trusted.
- **Panes without a shell aren't resumed.** A pane that runs an agent directly
  (`rex run -- claude`) has no shell to resume the chat.

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

Inspired by [herdr](https://herdr.dev), which restores agent chats the same way.

## License

MIT
