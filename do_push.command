#!/bin/bash
# do_push.command — push current branch to origin/main.
# Only removes index.lock (safe); never touches MERGE_HEAD.
set -euo pipefail
cd "$(dirname "$0")"
rm -f .git/index.lock 2>/dev/null
if git push origin main; then
  echo ""
  echo "✅ Done!"
else
  echo ""
  echo "❌ Push failed — check output above."
  read -p "Press Enter to close..."
  exit 1
fi
read -p "Press Enter to close..."
