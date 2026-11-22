---
name: layers-ship
description: Use when preparing to ship verified changes in LAYERS-Agentic across Cloud Functions, Git main, and Web Studio GitHub Pages deployment.
---

# LAYERS Atomic Release Loop

Execute these checks in order so `main`, Cloud Functions, and GitHub Pages stay byte-synchronized.

## Steps

1. **Run Full Multi-Stack Check**:
   - `./scripts/verify_loop.sh`
   - Must exit `0` (`node --check`, `scripts/cloud_proxy_test.py`, `scripts/workflow_hook_test.py`, `dart analyze`, and full `flutter test`).
2. **Deploy Cloud Functions** *(if `functions/` changed)*:
   - Run `firebase deploy --only functions` (or `/Users/henry/.npm/_npx/7750544ccf494d8b/node_modules/.bin/firebase deploy --only functions`).
3. **Commit & Push**:
   - Stage intended changes, commit, and push the active branch.
4. **Deploy Web Studio** *(if `lib/` or `web/` changed)*:
   - Run `./scripts/deploy.sh` from repo root.
5. **Reconcile Working Tree**:
   - Confirm `git status --short` is clean and `./scripts/verify_loop.sh --fast` passes.
