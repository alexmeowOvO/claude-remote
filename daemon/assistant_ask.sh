#!/bin/bash
# Usage: assistant_ask.sh "Question?" [timeout_seconds]
# Returns 0 (yes) or 1 (no/timeout)
# Only accepts replies from ASSISTANT_CHAT_ID (filters by chat_id).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

QUESTION="$1"
TIMEOUT="${2:-120}"
API="https://api.telegram.org/bot${ASSISTANT_TOKEN}"

# Send the question
curl -s -X POST "${API}/sendMessage" \
  -d "chat_id=${ASSISTANT_CHAT_ID}" \
  --data-urlencode "text=❓ ${QUESTION}

Reply YES to approve, NO to cancel (${TIMEOUT}s timeout)" > /dev/null

# Get current update_id offset (skip any pre-existing messages)
LAST_ID=$(curl -s "${API}/getUpdates?limit=1&offset=-1" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data['result']:
    print(data['result'][-1]['update_id'] + 1)
else:
    print(0)
")

START=$(date +%s)
while true; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    curl -s -X POST "${API}/sendMessage" \
      -d "chat_id=${ASSISTANT_CHAT_ID}" \
      --data-urlencode "text=⏰ Request timed out." > /dev/null
    exit 1
  fi

  UPDATES=$(curl -s "${API}/getUpdates?offset=${LAST_ID}&timeout=10")

  # Filter by chat_id (E: reject replies from anyone else)
  REPLY=$(echo "$UPDATES" | python3 -c "
import json, sys
CHAT_ID = int('${ASSISTANT_CHAT_ID}')
data = json.load(sys.stdin)
for u in data.get('result', []):
    msg = u.get('message', {})
    if msg.get('chat', {}).get('id') != CHAT_ID:
        # advance past foreign messages but don't act on them
        print(str(u['update_id'] + 1) + ':__skip__')
        break
    txt = msg.get('text', '').strip().lower()
    print(str(u['update_id'] + 1) + ':' + txt)
    break
" 2>/dev/null)

  if [ -n "$REPLY" ]; then
    LAST_ID="${REPLY%%:*}"
    ANSWER="${REPLY#*:}"
    if [ "$ANSWER" = "__skip__" ]; then
      continue
    fi
    if [[ "$ANSWER" == "yes" || "$ANSWER" == "y" || "$ANSWER" == "ok" || "$ANSWER" == "approve" ]]; then
      curl -s -X POST "${API}/sendMessage" \
        -d "chat_id=${ASSISTANT_CHAT_ID}" \
        --data-urlencode "text=✅ Approved — proceeding." > /dev/null
      exit 0
    else
      curl -s -X POST "${API}/sendMessage" \
        -d "chat_id=${ASSISTANT_CHAT_ID}" \
        --data-urlencode "text=❌ Denied — cancelled." > /dev/null
      exit 1
    fi
  fi
done
