#!/bin/bash
# notify_hook.sh — called by Claude Code Notification hook
# Sends a Telegram message when Claude Code is waiting for input.

CONFIG="$(dirname "$0")/config.sh"
if [ -f "$CONFIG" ]; then
  source "$CONFIG"
fi

TOKEN="${ASSISTANT_TOKEN:-}"
CHAT_ID="${ASSISTANT_CHAT_ID:-}"

if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo "[assistant] notify_hook: ASSISTANT_TOKEN or ASSISTANT_CHAT_ID not set." >&2
  echo "   Fix: run bash claude-code/install.sh --sync-config from the claude-remote repo." >&2
  exit 0
fi

curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  --data-urlencode "text=🔔 Claude Code is waiting for you — switch back when ready." \
  > /dev/null
