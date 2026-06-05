#!/bin/bash
# Usage: assistant_send.sh "Your message here"
# Sends a message to your Telegram chat via the assistant bot.
#
# Requires config.sh in the same directory (or set ASSISTANT_TOKEN + ASSISTANT_CHAT_ID).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "${SCRIPT_DIR}/config.sh" ]; then
  echo "❌ config.sh not found at ${SCRIPT_DIR}/config.sh" >&2
  echo "   Copy config.example.sh to config.sh and fill in your credentials." >&2
  exit 1
fi
source "${SCRIPT_DIR}/config.sh"

if [ $# -lt 1 ]; then
    echo "Usage: $0 \"Your message here\"" >&2
    exit 1
fi

MESSAGE="$*"
curl -s -X POST "https://api.telegram.org/bot${ASSISTANT_TOKEN}/sendMessage" \
    -d "chat_id=${ASSISTANT_CHAT_ID}" \
    --data-urlencode "text=${MESSAGE}" \
    > /dev/null
