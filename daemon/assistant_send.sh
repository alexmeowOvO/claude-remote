#!/bin/bash
# Usage: assistant_send.sh "Your message here"
# Sends a message to your Telegram chat via the assistant bot.
#
# Requires config.sh in the same directory (or set ASSISTANT_TOKEN + ASSISTANT_CHAT_ID).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

if [ $# -lt 1 ]; then
    echo "Usage: $0 \"Your message here\"" >&2
    exit 1
fi

MESSAGE="$1"
curl -s -X POST "${ASSISTANT_API}/sendMessage" \
    -d "chat_id=${ASSISTANT_CHAT_ID}" \
    --data-urlencode "text=${MESSAGE}" \
    > /dev/null
