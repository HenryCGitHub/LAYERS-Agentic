---
name: layers-ship
description: Use whenever the user asks to push, deploy, or ship changes in LAYERS-Agentic across Cloud Functions, Git main, and local-build Web Studio GitHub Pages deployment.
---

# LAYERS Atomic Release Loop

Whenever the user asks to **push**, **deploy**, or **ship**, run these steps together in order so `main`, Cloud Functions, and GitHub Pages (`./scripts/deploy.sh`) stay synchronized.

## Steps

1. **Run Full Multi-Stack Check**:
   - `./scripts/verify_loop.sh`
   - Must exit `0` (`node --check`, `scripts/cloud_proxy_test.py`, `scripts/workflow_hook_test.py`, `dart analyze`, and full `flutter test`).
2. **Deploy Cloud Functions** *(if `functions/` changed)*:
   - Run `firebase deploy --only functions` (or `/Users/henry/.npm/_npx/7750544ccf494d8b/node_modules/.bin/firebase deploy --only functions`).
3. **Commit & Push**:
   - Stage intended changes, commit, and push `main` (`git push origin main`).
4. **Deploy Web Studio Right After Push** *(always run after pushing)*:
   - Immediately run `./scripts/deploy.sh` from repo root to build release Flutter Web locally and force-push `origin/gh-pages`.
5. **Reconcile Working Tree**:
   - Confirm CI run passes on GitHub (`gh run list`), `git status --short` is clean, and `./scripts/verify_loop.sh --fast` passes.
