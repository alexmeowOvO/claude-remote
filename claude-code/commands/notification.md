---
description: Send a Telegram alert before performing risky or irreversible actions
---

Use this before any action that is risky, irreversible, or requires user approval — such as deleting files, pushing to git, making API calls, or running destructive commands.

## Step 1 — Gate the action through the approval script

```bash
bash ~/.claude/hooks/assistant_ask.sh "[WHAT YOU ARE ABOUT TO DO] — proceed?" 120
```

- Returns exit code `0` if approved, `1` if denied or timed out.
- The script sends a `YES <id>` / `NO <id>` prompt, and the daemon routes the reply mechanically — no ambiguity with normal commands.

## Step 2 — Act on the result

```bash
if bash ~/.claude/hooks/assistant_ask.sh "[DESCRIBE THE ACTION]?" 120; then
  echo "Approved — proceeding."
  # ... your risky command here ...
else
  echo "Denied or timed out — cancelled."
fi
```

## Notes

- The daemon must be running for approvals to be routed. If it is not running, the script will time out and return denied (safe default).
- Replace `[DESCRIBE THE ACTION]` with a specific, plain-English description every time — the user reads this on their phone.
