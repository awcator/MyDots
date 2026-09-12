#!/usr/bin/env bash
# Repeated WhatsApp reminders while Claude Code sits idle waiting for the user.
#
# Schedule: 20m, 35m, 40m = text; then call every 3m.
#
# Three modes, all called from hooks in ~/.claude/settings.json:
#   (no args)        Foreground — called by the Notification/idle_prompt hook.
#                    Reads the hook JSON on stdin, stashes session context, kills
#                    any previous loop *for this session*, and relaunches a
#                    detached --loop.
#   --loop <dir>     Background — the reminder loop (texts then voice calls).
#   --stop           Foreground — called by the UserPromptSubmit hook.

set -uo pipefail

STATE_BASE=/tmp/cc-idle-reminder

# state_dir maps a session_id to a per-session state directory. Keeping state
# per-session (rather than one shared /tmp/cc-idle-reminder) is what stops
# concurrent Claude Code sessions from clobbering each other: a UserPromptSubmit
# in one session must not kill the idle loop of another session.
state_dir() {
  local sid="${1:-}"
  [ -z "$sid" ] && sid="default"
  sid="${sid//[^a-zA-Z0-9._-]/_}"
  printf '%s/%s' "$STATE_BASE" "$sid"
}

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

send() {
  local msg="$1"
  ~/bin/wa send "$msg" >/dev/null 2>&1
}

# last_activity extracts a short phrase describing what Claude was last doing,
# from the tail of the session transcript.
last_activity() {
  local t="$1"
  [ -n "$t" ] && [ -r "$t" ] || { printf ''; return; }
  tail -80 "$t" 2>/dev/null \
    | jq -r 'select(.message.role=="assistant") | .message.content[]?
        | if .type=="text" then .text
          elif .type=="tool_use" then "using the " + (.name // "tool") + " tool"
          else empty end' 2>/dev/null \
    | grep -v '^$' | tail -1 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ *//; s/ *$//' | cut -c1-140
}

# call_escalation places a WhatsApp voice call speaking dynamic TTS content.
call_escalation() {
  local project="$1" transcript="$2"
  local activity; activity="$(last_activity "$transcript")"
  local text
  if [ -n "$activity" ]; then
    text="Claude Code is idle and waiting for you in project ${project}. It was last ${activity}. Please check your terminal."
  else
    text="Claude Code is idle and waiting for you in project ${project}. Please check your terminal."
  fi
  local mp3="/tmp/cc-idle-tts.mp3"
  local voice="${TTS_VOICE:-en-US-AriaNeural}"
  if ~/.claude/mcp-servers/whatapp/tts-venv/bin/edge-tts \
      --voice "$voice" --text "$text" --write-media "$mp3" >/dev/null 2>&1 \
      && [ -s "$mp3" ]; then
    ~/bin/wa call "$mp3" >/dev/null 2>&1
  else
    ~/bin/wa call >/dev/null 2>&1
  fi
  rm -f "$mp3"
}

cleanup_and_exit() {
  [ $# -gt 0 ] && log "$*"
  rm -rf "$d" 2>/dev/null
  exit 0
}

read_hook_input() {
  input="$(cat 2>/dev/null)"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  d="$(state_dir "$session_id")"
}

kill_existing_loop() {
  if [ -f "$d/pid" ]; then kill "$(cat "$d/pid")" 2>/dev/null || true; fi
}

case "${1:-}" in
  --stop)
    read_hook_input
    kill_existing_loop
    cleanup_and_exit
    ;;

  --loop)
    d="${2:-}"
    if [ -z "$d" ]; then
      echo "idle-reminder --loop: missing state dir" >&2
      exit 1
    fi
    LOG_FILE="$d/log"
    echo "$$" > "$d/pid"

    project="unknown"
    short_id=""
    transcript=""
    claude_pid=""
    [ -f "$d/env" ] && source "$d/env"

    log "loop start pid=$$ project=$project"

    # Fixed schedule: gap (seconds) between reminders, and the action for each.
    # Cumulative texts at 20m, 35m, 40m; after that, call every 3m.
    delays=(1200 900 300)
    actions=(text text text)
    idx=0
    elapsed=0

    while :; do
      if [ "$idx" -lt "${#delays[@]}" ]; then
        delay="${delays[$idx]}"
        action="${actions[$idx]}"
      else
        delay=180
        action=call
      fi

      left="$delay"
      while [ "$left" -gt 0 ]; do
        if [ -n "$claude_pid" ] && ! kill -0 "$claude_pid" 2>/dev/null; then
          cleanup_and_exit "Claude parent process ($claude_pid) is dead — exiting"
        fi
        sleep 5
        left=$((left - 5))
      done

      elapsed=$((elapsed + delay))
      total_mins=$((elapsed / 60))

      if [ "$action" = "call" ]; then
        log "escalating to call (elapsed ${elapsed}s)"
        call_escalation "$project" "$transcript"
      else
        msg="⏰ Away ~${total_mins}m — Claude Code is idle
📁 $project"
        [ -n "$short_id" ] && msg="$msg
#$short_id"
        log "send text (elapsed ${elapsed}s)"
        send "$msg"
      fi
      idx=$((idx + 1))
    done
    ;;

  *)  # foreground (hook) mode
    read_hook_input
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
    transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
    project="${cwd##*/}"; project="${project#-}"; [ -z "$project" ] && project="unknown"
    short_id=""; [ -n "$session_id" ] && short_id="${session_id%%-*}"

    mkdir -p "$d"

    current_pid=$PPID
    claude_pid=""
    for i in {1..5}; do
      [ -z "$current_pid" ] || [ "$current_pid" -eq 1 ] && break
      comm=$(ps -p "$current_pid" -o comm= 2>/dev/null || true)
      if [[ "$comm" == *"node"* ]] || [[ "$comm" == *"claude"* ]]; then
        claude_pid="$current_pid"
        break
      fi
      current_pid=$(ps -p "$current_pid" -o ppid= 2>/dev/null | tr -d ' ' || true)
    done

    cat <<EOF > "$d/env"
project="$project"
short_id="$short_id"
transcript="$transcript_path"
claude_pid="$claude_pid"
EOF

    # Kill any previous loop *for this session* and relaunch detached.
    kill_existing_loop
    setsid nohup "$0" --loop "$d" </dev/null >/dev/null 2>&1 &
    exit 0
    ;;
esac
