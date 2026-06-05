---
description: Send a Telegram alert before performing risky or irreversible actions
---

Use this before any action that is risky, irreversible, or requires user approval — such as deleting files, pushing to git, making API calls, or running destructive commands.

## Step 1 — Send Telegram alert

```bash
source ~/.claude/hooks/config.sh 2>/dev/null
curl -s -X POST "https://api.telegram.org/bot${ASSISTANT_TOKEN}/sendMessage" \
  -d "chat_id=${ASSISTANT_CHAT_ID}" \
  --data-urlencode "text=⚠️ Claude Code needs your approval!

Action: [WHAT YOU ARE ABOUT TO DO]
Risk: [WHY IT MATTERS / WHAT COULD GO WRONG]

Reply YES to proceed or NO to cancel." > /dev/null
```

Replace `[WHAT YOU ARE ABOUT TO DO]` and `[WHY IT MATTERS]` with specifics every time.

## Step 2 — Wait for reply

Tell the user in chat what you are waiting for, then pause and do NOT proceed.

When the user replies via Telegram, the assistant daemon forwards it to Claude Code as `claude --continue "YES"` (or whatever they send). Wait for that continuation before acting.
