#!/usr/bin/env bash
set -euo pipefail

FAST_MODE=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST_MODE=1 ;;
    --fix-zip) ;;
    *)
      echo "Unknown flag: $arg" >&2
      echo "Usage: $0 [--fast]" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== [1/3] Cloud Functions syntax check ==="
for js_file in functions/*.js; do
  node --check "$js_file"
done

echo "=== [2/3] Cloud Proxy & Workflow Hook tests ==="
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT_DIR/scripts/cloud_proxy_test.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT_DIR/scripts/workflow_hook_test.py"

echo "=== [3/3] Dart analyze & Flutter tests ==="
dart analyze
if [ "$FAST_MODE" -eq 1 ]; then
  RUN_FULL_FLUTTER=0
  while IFS= read -r status_line; do
    rel_path="${status_line:3}"
    rel_path="${rel_path##* -> }"
    rel_path="${rel_path%\"}"
    rel_path="${rel_path#\"}"
    if [[ "$rel_path" == pubspec.* || "$rel_path" == lib/* || "$rel_path" == test/* ]]; then
      RUN_FULL_FLUTTER=1
      break
    fi
  done < <(git status --porcelain --untracked-files=all)

  if [ "$RUN_FULL_FLUTTER" -eq 1 ]; then
    flutter test
  else
    flutter test test/unreal_spec_studio_test.dart
  fi
else
  flutter test
fi

python3 "$ROOT_DIR/.agents/hooks/stop_verify_gate.py" --stamp >/dev/null
echo "=== verify_loop.sh PASSED ==="
