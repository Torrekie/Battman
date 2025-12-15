#!/bin/bash
# Deploy built documentation to GitHub Pages
# This script builds the docs, fixes search indices, and pushes to battman-docs.github.io

set -e

# Configuration
REPO_URL="${GITHUB_REPO_URL:-https://github.com/battman-docs/battman-docs.github.io.git}"
SITE_DIR="site"
TEMP_DIR=".deploy_temp"
BRANCH="main"

# Allow override via environment variable or use SSH if available
if [ -z "$GITHUB_REPO_URL" ]; then
    # Try SSH first (more common for authenticated users)
    if git ls-remote "git@github.com:battman-docs/battman-docs.github.io.git" &>/dev/null; then
        REPO_URL="git@github.com:battman-docs/battman-docs.github.io.git"
        echo "ℹ️  Using SSH URL (set GITHUB_REPO_URL to override)"
    fi
fi

echo "🚀 Deploying documentation to GitHub Pages..."
echo ""

# Check if git is available
if ! command -v git &> /dev/null; then
    echo "❌ git is not installed"
    exit 1
fi

# Build the documentation
echo "🔨 Building documentation..."
mkdocs build

# Fix search indices
echo "🔍 Fixing search indices..."
python3 post_build_fix_search.py "$SITE_DIR"

# Verify search indices
echo ""
echo "✅ Verifying search indices..."
if [ -f "$SITE_DIR/search/search_index.json" ]; then
    ROOT_COUNT=$(python3 -c "import json; r=json.load(open('$SITE_DIR/search/search_index.json')); print(len(r.get('docs', [])))")
    echo "   Root index: $ROOT_COUNT docs"
fi
if [ -f "$SITE_DIR/zh/search/search_index.json" ]; then
    ZH_COUNT=$(python3 -c "import json; z=json.load(open('$SITE_DIR/zh/search/search_index.json')); print(len(z.get('docs', [])))")
    echo "   Chinese index: $ZH_COUNT docs"
fi

# Clean up temp directory if it exists
if [ -d "$TEMP_DIR" ]; then
    echo ""
    echo "🧹 Cleaning up previous deployment temp directory..."
    rm -rf "$TEMP_DIR"
fi

# Clone the repository
echo ""
echo "📥 Cloning repository..."
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TEMP_DIR" || {
    echo "⚠️  Branch $BRANCH not found, trying to create it..."
    git clone --depth 1 "$REPO_URL" "$TEMP_DIR"
    cd "$TEMP_DIR"
    git checkout -b "$BRANCH" || git checkout -b "$BRANCH" 2>/dev/null || true
    cd ..
}

# Copy built site to temp directory
echo "📦 Copying built site..."
cd "$TEMP_DIR"

# Remove all files except .git
find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

# Copy site contents
cp -r ../"$SITE_DIR"/* .

# Add .nojekyll to prevent Jekyll processing
touch .nojekyll

# Commit and push
echo ""
echo "📝 Committing changes..."
git add -A

# Check if there are changes to commit
if git diff --staged --quiet; then
    echo "ℹ️  No changes to deploy"
    cd ..
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Get commit message
COMMIT_MSG="${1:-Update documentation $(date +'%Y-%m-%d %H:%M:%S')}"

git commit -m "$COMMIT_MSG" || {
    echo "⚠️  Nothing to commit (site is up to date)"
    cd ..
    rm -rf "$TEMP_DIR"
    exit 0
}

echo ""
echo "🚀 Pushing to GitHub..."
git push origin "$BRANCH"

# Clean up
cd ..
rm -rf "$TEMP_DIR"

echo ""
echo "✅ Deployment complete!"
echo "   Documentation will be available at: https://battman-docs.github.io/"
echo "   (It may take a few minutes for GitHub Pages to update)"

