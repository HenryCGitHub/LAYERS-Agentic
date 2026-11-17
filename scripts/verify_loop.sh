#!/usr/bin/env bash
set -euo pipefail

FAST_MODE=0
FIX_ZIP=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST_MODE=1 ;;
    --fix-zip) FIX_ZIP=1 ;;
    *)
      echo "Unknown flag: $arg" >&2
      echo "Usage: $0 [--fast] [--fix-zip]" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== [1/4] Cloud Functions syntax check ==="
node --check functions/index.js

echo "=== [2/4] Godot 4 plugin zip byte-parity check ==="
check_zip_parity() {
  python3 - "$ROOT_DIR" <<'PY'
import hashlib
import os
import sys
import zipfile

root = sys.argv[1]
src_dir = os.path.join(root, "godot_plugin", "addons", "layers")
zip_path = os.path.join(root, "web", "layers_godot_plugin.zip")
if not os.path.isdir(src_dir):
  print(f"MISSING plugin dir: {src_dir}", file=sys.stderr)
  sys.exit(1)
if not os.path.isfile(zip_path):
  print(f"MISSING zip: {zip_path}", file=sys.stderr)
  sys.exit(1)

expected = {}
for base, dirs, files in os.walk(src_dir):
  dirs[:] = [d for d in dirs if d != "__pycache__"]
  for name in files:
    if name in (".DS_Store",) or name.endswith(".uid") or name.endswith(".pyc"):
      continue
    full = os.path.join(base, name)
    rel = os.path.relpath(full, os.path.join(root, "godot_plugin")).replace(os.sep, "/")
    with open(full, "rb") as fh:
      expected[rel] = hashlib.sha256(fh.read()).hexdigest()

actual = {}
with zipfile.ZipFile(zip_path, "r") as zf:
  for info in zf.infolist():
    if info.is_dir():
      continue
    name = info.filename.replace("\\", "/")
    if "/__pycache__/" in name or os.path.basename(name) in (".DS_Store",) or name.endswith(".uid") or name.endswith(".pyc"):
      continue
    actual[name] = hashlib.sha256(zf.read(info)).hexdigest()

if expected != actual:
  missing = sorted(set(expected) - set(actual))
  extra = sorted(set(actual) - set(expected))
  changed = sorted(k for k in set(expected) & set(actual) if expected[k] != actual[k])
  print(
      f"Godot plugin zip out of sync! missing={missing} extra={extra} changed={changed}",
      file=sys.stderr,
  )
  sys.exit(1)
PY
}

if ! check_zip_parity; then
  if [ "$FIX_ZIP" -eq 1 ]; then
    echo "Rebuilding web/layers_godot_plugin.zip..."
    (cd "$ROOT_DIR/godot_plugin" && rm -f ../web/layers_godot_plugin.zip && zip -rq ../web/layers_godot_plugin.zip addons/layers -x "*/.DS_Store" "*.uid" "*/__pycache__/*" "*.pyc")
    check_zip_parity
  else
    echo "Run ./scripts/verify_loop.sh --fix-zip to rebuild web/layers_godot_plugin.zip." >&2
    exit 1
  fi
fi

echo "=== [3/4] Headless Godot 4.7.2, Cloud Function & Workflow Hook tests ==="
GODOT_EXEC="${GODOT_BIN:-}"
if [ -z "$GODOT_EXEC" ] && [ -x "/Users/henry/Godot/Editors/4.7.2-stable/Godot.app/Contents/MacOS/Godot" ]; then
  GODOT_EXEC="/Users/henry/Godot/Editors/4.7.2-stable/Godot.app/Contents/MacOS/Godot"
elif [ -z "$GODOT_EXEC" ] && command -v godot >/dev/null 2>&1; then
  GODOT_EXEC="$(command -v godot)"
fi

if [ -n "$GODOT_EXEC" ]; then
  TMP_GODOT="$(mktemp -d)"
  trap 'rm -rf "$TMP_GODOT"' EXIT
  cat >"$TMP_GODOT/project.godot" <<'EOF'
config_version=5

[application]
config/name="LAYERS Plugin Test"
EOF
  cp -R "$ROOT_DIR/godot_plugin/addons" "$TMP_GODOT/addons"
  "$GODOT_EXEC" --headless --path "$TMP_GODOT" --script "$ROOT_DIR/scripts/godot_plugin_test.gd"
else
  echo "SKIP headless Godot binary check (Godot binary not found)." >&2
fi
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT_DIR/scripts/godot_cloud_test.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT_DIR/scripts/workflow_hook_test.py"

echo "=== [4/4] Dart analyze & Flutter tests ==="
dart analyze
if [ "$FAST_MODE" -eq 1 ]; then
  RUN_FULL_FLUTTER=0
  while IFS= read -r status_line; do
    rel_path="${status_line:3}"
    rel_path="${rel_path##* -> }"
    rel_path="${rel_path%\"}"
    rel_path="${rel_path#\"}"
    if [[ "$rel_path" == pubspec.* ]]; then
      RUN_FULL_FLUTTER=1
      break
    fi
    if [[ "$rel_path" == lib/* || "$rel_path" == test/* ]]; then
      if [[ "$rel_path" != "lib/providers/workbench_godot_mixin.dart" && "$rel_path" != "test/godot_spec_studio_test.dart" ]]; then
        RUN_FULL_FLUTTER=1
        break
      fi
    fi
  done < <(git status --porcelain --untracked-files=all)

  if [ "$RUN_FULL_FLUTTER" -eq 1 ]; then
    flutter test
  else
    flutter test test/godot_spec_studio_test.dart
  fi
else
  flutter test
fi

python3 "$ROOT_DIR/.agents/hooks/stop_verify_gate.py" --stamp >/dev/null
echo "=== verify_loop.sh PASSED ==="
