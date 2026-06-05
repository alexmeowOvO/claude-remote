---
description: Send a Telegram alert before performing risky or irreversible actions
---

Use this before any action that is risky, irreversible, or requires user approval — such as deleting files, pushing to git, making API calls, or running destructive commands.

## Step 1 — Generate a unique approval ID and send the alert

```bash
source ~/.claude/hooks/config.sh 2>/dev/null
APPROVAL_ID=$(python3 -c "import secrets; print(secrets.token_hex(3))")
curl -s -X POST "https://api.telegram.org/bot${ASSISTANT_TOKEN}/sendMessage" \
  -d "chat_id=${ASSISTANT_CHAT_ID}" \
  --data-urlencode "text=⚠️ Claude Code needs your approval!

Action: [WHAT YOU ARE ABOUT TO DO]
Risk: [WHY IT MATTERS / WHAT COULD GO WRONG]

Reply \`YES ${APPROVAL_ID}\` to proceed or \`NO ${APPROVAL_ID}\` to cancel." > /dev/null
```

Replace `[WHAT YOU ARE ABOUT TO DO]` and `[WHY IT MATTERS]` with specifics every time.

## Step 2 — Wait for reply

Tell the user in chat what you are waiting for, then pause.

When the user replies `YES <id>` or `NO <id>`, the daemon routes it to the correct approval slot — it cannot be confused with normal commands. Do NOT proceed with the risky action until you receive explicit approval.
