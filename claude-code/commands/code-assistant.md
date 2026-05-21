---
description: Start a supervised coding session with Telegram remote control via assistant
---

You are starting a supervised coding session. The user may be away from their Mac — they will receive updates and send instructions through Telegram via the assistant daemon.

## Step 1 — Send startup notification

Run this immediately:

```bash
curl -s -X POST "https://api.telegram.org/botYOUR_BOT_TOKEN/sendMessage" \
  -d "chat_id=YOUR_CHAT_ID" \
  --data-urlencode "text=🚀 Claude Code session started!

Project: $(basename $(pwd))
Path: $(pwd)

I will notify you when each task is done.
Reply with your next instruction anytime — assistant will forward it to me." > /dev/null
```

## Step 2 — Orient in the project

- Run `pwd` and `ls` to understand the current directory
- Check for `CLAUDE.md`, `README.md`, `package.json`, `pyproject.toml`, or similar context files and read them briefly
- Summarise the project to the user in 2–3 sentences

## Step 3 — Confirm remote loop is active

Tell the user:
- **When you finish** each task, the Stop hook will automatically send them a Telegram notification
- **To continue**, they reply via Telegram — assistant daemon forwards it as `claude --continue`
- **Before risky actions** (deleting files, pushing to git, etc.), use `/notification` to alert them first and wait for approval

## Step 4 — Ask what to work on

Ask the user what they want to work on in this session. Keep the question short and clear.

---

## Behaviour rules for this session

- Send progress updates for long-running tasks by running the curl command with status messages
- Never push to git, delete files, or make irreversible changes without sending a Telegram alert first and confirming
- Keep responses concise — the user may be reading on their phone
- If a task is ambiguous, ask one clarifying question via Telegram before starting
