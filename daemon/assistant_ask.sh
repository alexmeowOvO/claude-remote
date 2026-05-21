#!/bin/bash
# Usage: assistant_ask.sh "Question?" [timeout_seconds]
# Sends a yes/no question to Telegram and blocks until a reply.
# Returns 0 (approved) or 1 (denied / timeout).
#
# IMPORTANT: If the assistant daemon is running, it will consume the first
# "getUpdates" response. This script polls independently so there is
# a race condition — the daemon may eat the reply before we see it.
# For reliable approval-gating, use the daemon's built-in `run <secret> <cmd>`
# flow instead of this script while the daemon is active.
#
# Requires config.sh in the same directory (or set ASSISTANT_TOKEN + ASSISTANT_CHAT_ID).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

if [ $# -lt 1 ]; then
    echo "Usage: $0 \"Your question?\" [timeout_seconds]" >&2
    exit 1
fi

QUESTION="$1"
TIMEOUT="${2:-120}"

# Ask prefix — daemon ignores messages starting with this to avoid racing
ASK_PREFIX="[ASK]"

# Send the question
curl -s -X POST "${ASSISTANT_API}/sendMessage" \
    -d "chat_id=${ASSISTANT_CHAT_ID}" \
    --data-urlencode "text=❓ ${QUESTION}

Reply ${ASK_PREFIX} YES to approve, ${ASK_PREFIX} NO to cancel (${TIMEOUT}s)" > /dev/null

# Get current update_id offset
LAST_ID=$(curl -s "${ASSISTANT_API}/getUpdates?limit=1&offset=-1" | python3 -c "
import json,sys
data=json.load(sys.stdin)
if data.get('result'):
    print(data['result'][-1]['update_id'] + 1)
else:
    print(0)
")

START=$(date +%s)
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        curl -s -X POST "${ASSISTANT_API}/sendMessage" \
            -d "chat_id=${ASSISTANT_CHAT_ID}" \
            --data-urlencode "text=⏰ Request timed out." > /dev/null
        exit 1
    fi

    UPDATES=$(curl -s "${ASSISTANT_API}/getUpdates?offset=${LAST_ID}&timeout=10")
    REPLY=$(echo "$UPDATES" | python3 -c "
import json,sys
data = json.load(sys.stdin)
for u in data.get('result', []):
    txt = u.get('message', {}).get('text', '').strip().lower()
    # Only match replies prefixed with ASK_PREFIX
    prefix = '${ASK_PREFIX}'.lower()
    if txt.startswith(prefix):
        answer = txt[len(prefix):].strip()
        print(str(u['update_id'] + 1) + ':' + answer)
        break
" 2>/dev/null)

    if [ -n "$REPLY" ]; then
        LAST_ID="${REPLY%%:*}"
        ANSWER="${REPLY#*:}"
        case "$ANSWER" in
            yes|y|ok|approve)
                curl -s -X POST "${ASSISTANT_API}/sendMessage" \
                    -d "chat_id=${ASSISTANT_CHAT_ID}" \
                    --data-urlencode "text=✅ Approved — proceeding." > /dev/null
                exit 0
                ;;
            *)
                curl -s -X POST "${ASSISTANT_API}/sendMessage" \
                    -d "chat_id=${ASSISTANT_CHAT_ID}" \
                    --data-urlencode "text=❌ Denied — cancelled." > /dev/null
                exit 1
                ;;
        esac
    fi
done
