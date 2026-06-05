#!/bin/bash
# do_push.command — push current branch to origin/main.
# Only removes index.lock (safe); never touches MERGE_HEAD.
cd "$(dirname "$0")"
rm -f .git/index.lock 2>/dev/null
git push origin main
echo ""
echo "✅ Done!"
read -p "Press Enter to close..."
