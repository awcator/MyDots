#!/bin/bash
# Mirror Claude Code bash commands + output to a tmux pane
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

INPUT=$(cat)
[ -z "$TMUX" ] && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# Unique per claude session
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID=$$
SID_SHORT="${SESSION_ID:0:8}"

# No truncation — show full output
OUTPUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null)
STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exitCode // "?"' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.tool_input.workdir // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD=$(pwd)

# Shorten home dir to ~
CWD_SHORT="${CWD/#$HOME/\~}"

LOGFILE="/tmp/claude-mirror-log-${SID_SHORT}"
LOCKFILE="/tmp/claude-mirror-lock-${SID_SHORT}"
PANEFILE="/tmp/claude-mirror-pane-${SID_SHORT}"

# Use a lock to prevent race condition
exec 9>"$LOCKFILE"
flock -n 9 || { sleep 0.5; exec 9>"$LOCKFILE"; flock 9; }

# Check if mirror pane exists
PANE_ID=""
if [ -f "$PANEFILE" ]; then
    PANE_ID=$(cat "$PANEFILE")
    if ! tmux list-panes -s -F '#{pane_id}' 2>/dev/null | grep -q "^${PANE_ID}$"; then
        PANE_ID=""
        rm -f "$PANEFILE"
    fi
fi

if [ -z "$PANE_ID" ]; then
    [ ! -f "$LOGFILE" ] && > "$LOGFILE"

    TAIL_CMD="export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; printf '=== Claude Mirror [${SID_SHORT}] ===\n\n'; while true; do tail -f $LOGFILE; sleep 0.5; done"

    # Find Claude's pane by walking up the process tree
    CLAUDE_PANE=""
    WALK_PID=$$
    while [ "$WALK_PID" -gt 1 ] 2>/dev/null; do
        CLAUDE_PANE=$(tmux list-panes -s -F '#{pane_id} #{pane_pid}' 2>/dev/null | \
            awk -v pid="$WALK_PID" '$2 == pid {print $1; exit}')
        [ -n "$CLAUDE_PANE" ] && break
        WALK_PID=$(ps -o ppid= -p "$WALK_PID" 2>/dev/null | tr -d ' ')
    done
    [ -z "$CLAUDE_PANE" ] && CLAUDE_PANE="$TMUX_PANE"

    # Split Claude's own pane to the right — stays within Claude's row
    PANE_ID=$(tmux split-window -h -l 45% -d -t "$CLAUDE_PANE" -P -F '#{pane_id}' "$TAIL_CMD")

    # Set mirror pane title
    tmux select-pane -t "$PANE_ID" -T "🤖 Claude Mirror [${SID_SHORT}]"

    echo "$PANE_ID" > "$PANEFILE"
    sleep 0.3
fi

exec 9>&-

# Build PS1-style prompt: ┌─[awcator@awcatorzbook]─[~/path]
# └──╼ $ command
{
    # Auto-scroll marker for long outputs
    printf '\n'

    # PS1 line 1: ┌─[user@host]─[cwd]
    printf '\033[0;31m┌─\033[0m'
    printf '[\033[0;39mawcator\033[01;33m@\033[01;96mawcatorzbook\033[0;31m]'
    printf '─[\033[0;32m%s\033[0;31m]\033[0m\n' "$CWD_SHORT"

    # PS1 line 2: └──╼ $ command
    if [ "$EXIT_CODE" != "0" ] && [ "$EXIT_CODE" != "?" ]; then
        printf '\033[0;31m└──╼ \033[0m\033[01;33m$\033[0m '
        printf '\033[1;33m%s\033[0m  \033[1;31m[exit %s]\033[0m\n' "$CMD" "$EXIT_CODE"
    else
        printf '\033[0;31m└──╼ \033[0m\033[01;33m$\033[0m '
        printf '\033[1;33m%s\033[0m\n' "$CMD"
    fi

    # Stdout
    if [ -n "$OUTPUT" ]; then
        printf '%s\n' "$OUTPUT"
    fi

    # Stderr in red
    if [ -n "$STDERR" ]; then
        printf '\033[1;31m%s\033[0m\n' "$STDERR"
    fi

    printf '\033[2m────────────────────────────────\033[0m\n'
} >> "$LOGFILE"
