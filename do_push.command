#!/bin/bash
cd "$(dirname "$0")"
rm -f .git/index.lock .git/MERGE_HEAD 2>/dev/null
git push origin main
echo ""
echo "✅ Done!"
read -p "Press Enter to close..."
