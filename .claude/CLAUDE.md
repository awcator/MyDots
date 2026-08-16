# Git Commits
- Never add "Co-Authored-By" lines to commit messages
- Never commit or push changes unless the user explicitly says to commit/push

# WhatsApp notifications
- A WhatsApp MCP server (name: `whatsapp`) with a `send_message` tool is available.
- ALWAYS send to the user's watch number. The recipient is baked into the `wa` binary (and the `send_message` tool) — do not pass a number, and never use "self"/"me" (those target the linked account, not the watch).
- When you need the user's intervention, ping them on WhatsApp via `send_message` (in addition to asking in the terminal). This includes: being blocked on a decision only they can make, needing confirmation or approval to proceed with something consequential, or a long-running/background task they asked about has finished.
- Reserve it for genuine "I need you at the keyboard" moments — don't ping for trivial or easily-reversed steps.
- Whenever a cron job, scheduled task, or `/loop` iteration fires or completes, you MUST send a WhatsApp message via `send_message` reporting it — include what ran and its output/result. This is a standing rule: do it automatically every single time, never skip it and never wait to be asked.
