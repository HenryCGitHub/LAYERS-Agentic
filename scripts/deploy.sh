#!/usr/bin/env bash
set -e

# ==============================================================================
# LAYERS-Agentic Local Web Build & Deploy Script
# Compiles Flutter web locally and pushes directly to the gh-pages branch.
# ==============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== [1/4] Checking prerequisites ==="
if ! command -v flutter &> /dev/null; then
    echo "Error: flutter CLI not found in PATH." >&2
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "Error: git CLI not found in PATH." >&2
    exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
CURRENT_COMMIT=$(git rev-parse --short HEAD)
echo "Deploying from: $CURRENT_BRANCH ($CURRENT_COMMIT)"

echo "=== [2/4] Compiling Flutter Web locally ==="
BUILD_ARGS=(
    "web"
    "--release"
    "--base-href" "/LAYERS-Agentic/"
    "--no-web-resources-cdn"
)

if [ -n "$GEMINI_API_KEY" ]; then
    echo "Injecting GEMINI_API_KEY from environment..."
    BUILD_ARGS+=("--dart-define=GEMINI_API_KEY=$GEMINI_API_KEY")
else
    echo "Notice: GEMINI_API_KEY not set in environment."
fi

flutter build "${BUILD_ARGS[@]}"

if [ ! -d "build/web" ]; then
    echo "Error: build/web was not generated." >&2
    exit 1
fi

touch "build/web/.nojekyll"

echo "=== [3/4] Preparing gh-pages branch deployment ==="
WORKTREE_DIR=$(mktemp -d -t layers_agentic_deploy_XXXXXX)

cleanup() {
    if [ -d "$WORKTREE_DIR" ]; then
        git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
    fi
}
trap cleanup EXIT

if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
    git fetch origin gh-pages
    git worktree add -B gh-pages "$WORKTREE_DIR" origin/gh-pages
else
    git worktree add --detach "$WORKTREE_DIR"
    (cd "$WORKTREE_DIR" && git checkout --orphan gh-pages)
fi

# Clean previous build files from worktree except .git
find "$WORKTREE_DIR" -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} +

# Copy new build files
rsync -a --exclude='.git' build/web/ "$WORKTREE_DIR/"

echo "=== [4/4] Committing and pushing to origin/gh-pages ==="
cd "$WORKTREE_DIR"
git add -A

if git rev-parse --verify HEAD >/dev/null 2>&1 && git diff-index --quiet HEAD --; then
    echo "No changes detected. gh-pages is already up to date."
else
    git commit -m "Deploy: ${CURRENT_COMMIT} ($(date -u +'%Y-%m-%d %H:%M:%S UTC'))"
    git push -u origin gh-pages
    echo "Successfully published to origin/gh-pages!"
fi

cd "$PROJECT_ROOT"
echo "=== Deployment complete! ==="
echo "Live URL: https://henrycgithub.github.io/LAYERS-Agentic/"
