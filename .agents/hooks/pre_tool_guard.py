#!/usr/bin/env python3
"""PreToolUse hook blocking writes to external user Godot game files."""

import json
import os
import sys

EXTERNAL_GODOT_ROOT = "/Users/henry/Godot/Projects/"


def _extract_target_path(args: dict) -> str:
  for key in ("Path", "path", "TargetFile", "targetFile", "file_path"):
    val = args.get(key)
    if isinstance(val, str) and val.strip():
      return os.path.abspath(os.path.expanduser(val.strip()))
  return ""


def main() -> int:
  raw = sys.stdin.read().strip()
  if not raw:
    print(json.dumps({"decision": "allow"}))
    return 0

  try:
    payload = json.loads(raw)
  except json.JSONDecodeError:
    print(json.dumps({"decision": "allow"}))
    return 0

  tool_call = payload.get("toolCall") if isinstance(payload, dict) else {}
  args = tool_call.get("args") if isinstance(tool_call, dict) else {}
  target_path = _extract_target_path(args if isinstance(args, dict) else {})

  if target_path.startswith(EXTERNAL_GODOT_ROOT) and "/addons/layers/" not in f"{target_path}/":
    print(
        json.dumps({
            "decision": "deny",
            "reason": (
                "External user Godot project game files under "
                "/Users/henry/Godot/Projects/ are read-only. "
                "Fix LAYERS plugin/agent code instead "
                "(syncing addons/layers/ is allowed)."
            ),
        })
    )
    return 0

  print(json.dumps({"decision": "allow"}))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
