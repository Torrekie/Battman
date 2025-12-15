#!/bin/bash
# Simple development server that builds, fixes search, and serves
# This replaces `mkdocs serve` to ensure search works correctly

set -e

SITE_DIR="site"
POST_BUILD_SCRIPT="post_build_fix_search.py"
PORT="${1:-8000}"

echo "🔨 Building documentation..."
mkdocs build

echo "🔍 Fixing search indices..."
python3 "$POST_BUILD_SCRIPT" "$SITE_DIR"

echo ""
echo "🌐 Serving at http://127.0.0.1:$PORT/"
echo "   Press Ctrl+C to stop"
echo ""

cd "$SITE_DIR"
python3 -m http.server "$PORT"

