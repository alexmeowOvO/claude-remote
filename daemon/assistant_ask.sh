#!/bin/bash
# Usage: assistant_ask.sh "Question?" [timeout_seconds]
# Returns 0 (yes) or 1 (no/timeout)
#
# Approval flow (daemon is the ONLY Telegram consumer):
#   1. Generate a unique ID and create a sentinel file the daemon recognises.
#   2. Send the question via Telegram with YES <id> / NO <id> instructions.
#   3. Poll the result file that the daemon writes when it routes the reply.
#   4. Clean up sentinel and result files.
#
# The daemon's _try_route_approval() writes the result — no second poller,
# no race condition.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

QUESTION="$1"
TIMEOUT="${2:-120}"
API="https://api.telegram.org/bot${ASSISTANT_TOKEN}"

# Generate unique approval ID
APPROVAL_ID=$(python3 -c "import secrets; print(secrets.token_hex(3))")
SENTINEL="/tmp/assistant_ask_${APPROVAL_ID}"
RESULT_FILE="${SENTINEL}.result"

# Check daemon is running — result file will never appear without it
if ! pgrep -f "assistant_daemon.py" > /dev/null 2>&1; then
  echo "[assistant_ask] WARNING: daemon is not running. Approval will time out." >&2
  curl -s -X POST "${API}/sendMessage" \
    -d "chat_id=${ASSISTANT_CHAT_ID}" \
    --data-urlencode "text=⚠️ Approval requested but the assistant daemon is not running — cannot process reply. Start the daemon and try again." > /dev/null
  exit 1
fi

# Create sentinel so daemon knows this ID belongs to a shell approval
touch "$SENTINEL"
trap 'rm -f "$SENTINEL" "$RESULT_FILE"' EXIT

# Send the question
curl -s -X POST "${API}/sendMessage" \
  -d "chat_id=${ASSISTANT_CHAT_ID}" \
  --data-urlencode "text=❓ ${QUESTION}

Reply \`YES ${APPROVAL_ID}\` to approve or \`NO ${APPROVAL_ID}\` to cancel (${TIMEOUT}s timeout)." > /dev/null

# Poll for the result file written by the daemon
START=$(date +%s)
while true; do
  if [ -f "$RESULT_FILE" ]; then
    ANSWER=$(cat "$RESULT_FILE")
    if [ "$ANSWER" = "YES" ]; then
      exit 0
    else
      exit 1
    fi
  fi

  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    curl -s -X POST "${API}/sendMessage" \
      -d "chat_id=${ASSISTANT_CHAT_ID}" \
      --data-urlencode "text=⏰ Approval \`${APPROVAL_ID}\` timed out — cancelled." > /dev/null
    exit 1
  fi

  sleep 2
done
