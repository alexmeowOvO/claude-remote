#!/bin/bash
# stop_notify.sh — called by Claude Code Stop hook when a task finishes
# Sends a Telegram message so you can reply with the next instruction remotely

# Load credentials from config (installed alongside this hook)
CONFIG="$(dirname "$0")/config.sh"
if [ -f "$CONFIG" ]; then
  source "$CONFIG"
fi

# Fall back to env vars if config not found
TOKEN="${ASSISTANT_TOKEN:-}"
CHAT_ID="${ASSISTANT_CHAT_ID:-}"

if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo "[assistant] stop_notify: ASSISTANT_TOKEN or ASSISTANT_CHAT_ID not set — skipping notification" >&2
  exit 0
fi

API="https://api.telegram.org/bot${TOKEN}"

# Read the JSON payload from stdin (Claude Code passes session info here)
INPUT=$(cat)

# Send notification
curl -s -X POST "${API}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  --data-urlencode "text=✅ Claude Code finished!

Reply with your next instruction and I'll continue working.
Or say 'done' if the task is complete." > /dev/null
