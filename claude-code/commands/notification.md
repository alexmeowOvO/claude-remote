---
description: Send a Telegram alert before performing risky or irreversible actions
---

Use this before any action that is risky, irreversible, or requires user approval — such as deleting files, pushing to git, making API calls, or running destructive commands.

## Step 1 — Send Telegram alert

```bash
curl -s -X POST "https://api.telegram.org/botYOUR_BOT_TOKEN/sendMessage" \
  -d "chat_id=YOUR_CHAT_ID" \
  --data-urlencode "text=⚠️ Claude Code needs your approval!

Action: [WHAT YOU ARE ABOUT TO DO]
Risk: [WHY IT MATTERS / WHAT COULD GO WRONG]

Reply YES to proceed, NO to cancel, or give alternative instructions." > /dev/null
```

Replace `[WHAT YOU ARE ABOUT TO DO]` and `[WHY IT MATTERS]` with specifics every time.

## Step 2 — Wait for reply

After sending, tell the user in chat what you are waiting for. Then pause and wait for them to continue the session with their decision via Telegram or directly in the chat.

Do NOT proceed with the risky action until you receive explicit approval.
