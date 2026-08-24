#!/usr/bin/env bash
# Send a WhatsApp ping when a /loop iteration, cron job, or scheduled task fires.
# Called from the PostToolUse hook for ScheduleWakeup|CronCreate in ~/.claude/settings.json.
#
# The hook feeds the tool-call JSON on stdin; we read tool_name + tool_input.

set -uo pipefail

input="$(cat)"

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"

msg=""
case "$tool" in
  ScheduleWakeup)
    stop="$(printf '%s' "$input" | jq -r '.tool_input.stop // false')"
    if [ "$stop" = "true" ]; then
      msg="🛑 Loop ended"
    else
      msg="🔄 Loop iteration done — next wakeup scheduled"
    fi
    ;;
  CronCreate)
    cron="$(printf '%s' "$input" | jq -r '.tool_input.cron // empty')"
    msg="⏰ Scheduled task created (${cron})"
    ;;
esac

if [ -n "$msg" ]; then
  # The `wa` CLI reads whatsapp.db relative to its working directory.
  cd ~/.claude/mcp-servers/whatapp || exit 0
  ./wa send "$msg" >/dev/null 2>&1
fi
