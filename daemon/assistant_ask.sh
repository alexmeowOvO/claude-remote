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

# Private directory — world-writable /tmp is unsafe for approval sentinels
APPROVAL_DIR="/tmp/claude-remote-${UID}"
PID_FILE="${APPROVAL_DIR}/daemon.pid"
HEARTBEAT_FILE="${APPROVAL_DIR}/daemon.heartbeat"
HEARTBEAT_MAX_AGE=120  # seconds — must match daemon's _HEARTBEAT_MAX_AGE (generous enough for API backoff)

# If the directory already exists, verify ownership BEFORE attempting chmod.
# If another user pre-created it, chmod would fail under set -e before
# we can print a useful error message.
if [ -d "$APPROVAL_DIR" ]; then
  DIR_OWNER=$(python3 -c "import os; print(os.stat('$APPROVAL_DIR').st_uid)")
  if [ "$DIR_OWNER" != "$(id -u)" ]; then
    echo "[assistant_ask] ERROR: $APPROVAL_DIR is owned by UID $DIR_OWNER, expected $(id -u). Possible pre-creation attack. Aborting." >&2
    exit 1
  fi
fi

# Safe to create/fix now — we own any existing directory
mkdir -p "$APPROVAL_DIR"
chmod 0700 "$APPROVAL_DIR"

# Generate unique approval ID
APPROVAL_ID=$(python3 -c "import secrets; print(secrets.token_hex(3))")
SENTINEL="${APPROVAL_DIR}/ask_${APPROVAL_ID}"
RESULT_FILE="${SENTINEL}.result"

# Check daemon is running via PID file + heartbeat.
# PID alone is insufficient — macOS can reuse PIDs after a crash.
# The heartbeat file is updated every poll cycle; a stale one means the
# process holding the PID is not our daemon.
_daemon_running() {
  [ -f "$PID_FILE" ] || return 1
  local pid
  pid=$(cat "$PID_FILE" 2>/dev/null) || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1

  # Verify heartbeat is recent — guards against PID reuse after crash
  [ -f "$HEARTBEAT_FILE" ] || return 1
  local age
  age=$(python3 -c "
import time, sys
try:
    ts = float(open('$HEARTBEAT_FILE').read())
    print(int(time.time() - ts))
except Exception:
    print(9999)
")
  [ "$age" -lt "$HEARTBEAT_MAX_AGE" ]
}

if ! _daemon_running; then
  echo "[assistant_ask] WARNING: daemon is not running (no valid PID file at $PID_FILE)." >&2
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
