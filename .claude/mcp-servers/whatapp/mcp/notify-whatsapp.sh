#!/usr/bin/env bash
# Send a context-rich WhatsApp ping when Claude Code needs the user's attention
# or has gone idle waiting for them.
# Called from the Notification hook in ~/.claude/settings.json, which pipes the
# hook input JSON on stdin (session_id, cwd, message, title, notification_type,
# transcript_path, ...).
#
# Usage: notify-whatsapp.sh ["override message"]
#   With no argument it parses stdin and builds a type-aware message.

set -uo pipefail

input="$(cat)"
override="${1:-}"

if [ -n "$override" ]; then
  msg="$override"
else
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
  transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
  ntype="$(printf '%s' "$input" | jq -r '.notification_type // empty' 2>/dev/null)"
  nmessage="$(printf '%s' "$input" | jq -r '.message // empty' 2>/dev/null)"
  ntitle="$(printf '%s' "$input" | jq -r '.title // empty' 2>/dev/null)"

  # Human-friendly project label from the working directory.
  project="${cwd##*/}"
  project="${project#-}"
  [ -z "$project" ] && project="unknown"

  # Short session id for disambiguation.
  short_id=""
  [ -n "$session_id" ] && short_id="${session_id%%-*}"

  # Best-effort "what was going on": last assistant text or tool call.
  activity=""
  if [ -n "$transcript_path" ] && [ -r "$transcript_path" ]; then
    activity="$(tail -80 "$transcript_path" 2>/dev/null \
      | jq -r 'select(.message.role=="assistant") | .message.content[]? | if .type=="text" then .text elif .type=="tool_use" then "🔧 " + (.name // "tool") else empty end' 2>/dev/null \
      | grep -v '^$' | tail -1 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ *//; s/ *$//' | cut -c1-120)"
  fi

  case "$ntype" in
    idle_prompt)
      msg="⏳ Claude Code is idle — waiting for you
📁 $project"
      ;;
    permission_prompt)
      msg="🔔 Claude Code needs your attention
📁 $project"
      [ -n "$ntitle" ] && msg="$msg
📍 $ntitle"
      ;;
    *)
      msg="🔔 Claude Code: ${nmessage:-needs your attention}
📁 $project"
      ;;
  esac

  [ -n "$activity" ] && msg="$msg
💬 $activity"
  [ -n "$short_id" ] && msg="$msg
#${short_id}"
fi

# The `wa` CLI reads whatsapp.db relative to its working directory.
cd ~/.claude/mcp-servers/whatapp || exit 0
./wa send "$msg" >/dev/null 2>&1
