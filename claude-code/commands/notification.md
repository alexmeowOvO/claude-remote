---
description: Send a Telegram alert before performing risky or irreversible actions
---

Use this before any action that is risky, irreversible, or requires user approval — such as deleting files, pushing to git, making API calls, or running destructive commands.

Run exactly this pattern — one call, one approval, one branch:

```bash
if bash ~/.claude/hooks/assistant_ask.sh "[DESCRIBE THE EXACT ACTION]?" 120; then
  echo "Approved — proceeding."
  # ... your risky command here ...
else
  echo "Denied or timed out — cancelled."
fi
```

- Replace `[DESCRIBE THE EXACT ACTION]` with a specific plain-English description. The user reads this on their phone.
- Returns exit `0` if approved, `1` if denied or timed out (safe default).
- The daemon must be running. If it is not, the script exits `1` immediately with a Telegram warning.
- Do NOT call `assistant_ask.sh` twice for the same action — it will send two Telegram prompts.
