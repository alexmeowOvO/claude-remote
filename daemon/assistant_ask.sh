#!/bin/bash
# Usage: assistant_ask.sh "Question?" [timeout_seconds]
# Returns 0 (yes) or 1 (no/timeout)
#
# Uses the daemon's unique-ID approval protocol: sends "YES <id>" / "NO <id>"
# so replies cannot be confused with normal daemon commands.
# If the daemon is running, it will consume the reply via _try_route_approval().
# If used standalone (daemon not running), this script polls directly.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

QUESTION="$1"
TIMEOUT="${2:-120}"
API="https://api.telegram.org/bot${ASSISTANT_TOKEN}"

# Generate a unique approval ID (6 hex chars)
APPROVAL_ID=$(python3 -c "import secrets; print(secrets.token_hex(3))")

# Send the question with the unique ID embedded in the reply instructions
curl -s -X POST "${API}/sendMessage" \
  -d "chat_id=${ASSISTANT_CHAT_ID}" \
  --data-urlencode "text=❓ ${QUESTION}

Reply \`YES ${APPROVAL_ID}\` to approve or \`NO ${APPROVAL_ID}\` to cancel (${TIMEOUT}s timeout)." > /dev/null

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
      --data-urlencode "text=⏰ Approval \`${APPROVAL_ID}\` timed out — cancelled." > /dev/null
    exit 1
  fi

  UPDATES=$(curl -s "${API}/getUpdates?offset=${LAST_ID}&timeout=10")

  # Only accept "YES <id>" or "NO <id>" from the correct chat_id
  REPLY=$(echo "$UPDATES" | python3 -c "
import json, sys
CHAT_ID = int('${ASSISTANT_CHAT_ID}')
APPROVAL_ID = '${APPROVAL_ID}'
data = json.load(sys.stdin)
for u in data.get('result', []):
    msg = u.get('message', {})
    next_id = str(u['update_id'] + 1)
    if msg.get('chat', {}).get('id') != CHAT_ID:
        print(next_id + ':__skip__')
        break
    parts = msg.get('text', '').strip().split()
    if len(parts) == 2 and parts[0].upper() in ('YES', 'NO') and parts[1].lower() == APPROVAL_ID:
        print(next_id + ':' + parts[0].upper())
        break
    # Not our reply — skip past it
    print(next_id + ':__skip__')
    break
" 2>/dev/null)

  if [ -n "$REPLY" ]; then
    LAST_ID="${REPLY%%:*}"
    ANSWER="${REPLY#*:}"
    if [ "$ANSWER" = "__skip__" ]; then
      continue
    fi
    if [ "$ANSWER" = "YES" ]; then
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
