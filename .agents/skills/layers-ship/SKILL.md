---
name: layers-ship
description: Use when preparing to ship verified changes in LAYERS-Agentic across Cloud Functions, Git main, and Web Studio GitHub Pages deployment.
---

# LAYERS Atomic Release Loop

Execute these checks in order so `main`, Cloud Functions, and GitHub Pages stay byte-synchronized.

## Steps

1. **Run Full Multi-Stack Verification**:
   - `./scripts/verify_loop.sh --fix-zip`
   - Must exit `0` (`node --check`, `web/layers_godot_plugin.zip` parity, `godot_plugin_test.gd`, `scripts/godot_cloud_test.py`, `dart analyze`, and full `flutter test`).
2. **Deploy Cloud Functions** *(if `functions/` changed)*:
   - Run `firebase deploy --only functions` (or `/Users/henry/.npm/_npx/7750544ccf494d8b/node_modules/.bin/firebase deploy --only functions`).
3. **Commit & Push `main`**:
   - Stage intended changes including updated `web/layers_godot_plugin.zip`, commit, and `git push origin main`.
4. **Deploy Web Studio** *(if `lib/`, `web/`, or `godot_plugin/` changed)*:
   - Run `./scripts/deploy.sh` from repo root.
5. **Reconcile Working Tree**:
   - `./scripts/deploy.sh` re-zips `web/layers_godot_plugin.zip` with fresh timestamps; verify `git status --short`, run `git checkout -- web/layers_godot_plugin.zip` if only timestamps changed, and confirm `./scripts/verify_loop.sh --fast` passes.
