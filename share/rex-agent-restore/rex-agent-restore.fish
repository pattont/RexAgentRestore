# rex-agent-restore: fish integration (fish 3.5 or later).
#
# `rex-agent-restore install --shell fish` writes a conf.d file that sources
# this one. It does nothing outside Rex. It works like rex-agent-restore.zsh,
# except for how the resume command is run; see _rex_agent_restore_run.
#
# - Every agent started from this shell is tagged with a per-shell token.
# - When the prompt comes back and the pane's saved chat carries this shell's
#   token, the agent has exited normally, so the saved chat is deleted.
# - On the first prompt of a pane Rex restored, the saved chat carries an
#   older shell's token, so the chat is resumed.
#
# TODO: this is the third copy (with the zsh and bash files) of the
# forget-or-resume logic: the killed exit codes, the shell_token match and the
# state file path. Move it into a `rex-agent-restore` subcommand before adding
# a fourth shell, and keep only how each shell runs the plan here.

status is-interactive; or return 0
test -n "$REX_BLOCK"; or return 0
# The `path` builtin below is new in fish 3.5.
contains path (builtin -n); or return 0
set -q _rex_agent_restore_loaded; and return 0
set -g _rex_agent_restore_loaded 1

set -g _rex_agent_restore_first 1
set -g _rex_agent_restore_status 0
# Set when Rex was asked to type the resume command into the pane.
set -g _rex_agent_restore_resumed 0

# Installed as share/rex-agent-restore/rex-agent-restore.fish: the program is
# in ../../bin. Otherwise use the one on PATH.
set -g _rex_agent_restore_bin (path resolve (status filename) | path dirname | path dirname | path dirname)/bin/rex-agent-restore
test -x $_rex_agent_restore_bin; or set _rex_agent_restore_bin rex-agent-restore

set -l state_dir $HOME/.local/state/rex-agent-restore
test -n "$XDG_STATE_HOME"; and set state_dir $XDG_STATE_HOME/rex-agent-restore
test -n "$REX_AGENT_RESTORE_STATE_DIR"; and set state_dir $REX_AGENT_RESTORE_STATE_DIR
set -g _rex_agent_restore_file $state_dir/panes/(string replace -r '^block:' '' -- $REX_BLOCK).json

# A shell started inside another shell in the same pane (running `fish` by
# hand, for example) must not resume the pane's chat.
if test "$_REX_AGENT_RESTORE_OWNER" = "$REX_BLOCK"
    set -g _rex_agent_restore_nested 1
else
    set -g _rex_agent_restore_nested 0
    set -gx _REX_AGENT_RESTORE_OWNER $REX_BLOCK
end
set -gx REX_AGENT_RESTORE_SHELL_TOKEN "$fish_pid-"(random)(random)"-"(date +%s)

# Killed by a hang-up (Rex shut down), SIGTERM or SIGKILL (the Mac logging out
# or restarting) rather than quit: keep the chat. See rex-agent-restore.zsh.
function _rex_agent_restore_killed
    contains -- $argv[1] 129 137 143
end

function _rex_agent_restore_postexec --on-event fish_postexec
    # fish_prompt handlers don't see the last command's status, so keep it.
    set -g _rex_agent_restore_status $status
    # This check stays here, not in the prompt handler: pressing Enter on an
    # empty line fires fish_prompt without fish_postexec, and that must not
    # count as the resume command having run.
    if test $_rex_agent_restore_resumed = 1
        # That was the resume command. The chat had its chance: keep it only
        # if the agent was killed.
        set -g _rex_agent_restore_resumed 0
        _rex_agent_restore_killed $_rex_agent_restore_status
        or command rm -f -- $_rex_agent_restore_file
    end
end

# Auto mode types the resume command into this pane through Rex, so it runs
# like any command you type: as its own job, in normal terminal modes, and
# into history. The zsh integration runs it from the prompt hook instead, but
# in fish that leaves it in fish's process group with the terminal still set
# up for the line editor. `commandline -f execute` from the hook would be the
# fish way, but it panics fish 4.9 when the command exits
# (https://github.com/fish-shell/fish-shell/issues/13104), and skipping
# fish's prompt query to avoid that leaves the execute waiting for a keypress.
function _rex_agent_restore_run
    set -l plan ("$_rex_agent_restore_bin" restore-plan 2>/dev/null); or return 0
    set -l mode $plan[1]
    set -l desc $plan[2]
    set -l cmd $plan[3]
    test -n "$cmd"; or return 0

    switch $mode
        case off
            return 0
        case prompt
            echo "rex-agent-restore: press Enter to resume this pane's chat, or clear the line to skip."
            commandline -r -- $cmd
            return 0
    end

    set_color brblack
    echo "rex-agent-restore: $desc"
    set_color normal
    if command rex --autostart=false send -b $REX_BLOCK -- $cmd\r >/dev/null 2>&1
        set -g _rex_agent_restore_resumed 1
    else
        echo "rex-agent-restore: couldn't reach Rex. Press Enter to resume, or clear the line to skip."
        commandline -r -- $cmd
    end
end

function _rex_agent_restore_prompt --on-event fish_prompt
    set -l st $_rex_agent_restore_status
    set -g _rex_agent_restore_status 0
    if test -e $_rex_agent_restore_file
        set -l body (string collect < $_rex_agent_restore_file)
        if test -n "$REX_AGENT_RESTORE_SHELL_TOKEN"; and string match -q -- "*\"shell_token\":\"$REX_AGENT_RESTORE_SHELL_TOKEN\"*" $body
            # An agent started from this shell has exited.
            _rex_agent_restore_killed $st; or command rm -f -- $_rex_agent_restore_file
        else if test $_rex_agent_restore_first = 1; and test $_rex_agent_restore_nested = 0
            _rex_agent_restore_run
        end
    end
    set -g _rex_agent_restore_first 0
end
