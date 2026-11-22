#!/usr/bin/env python3
"""PreToolUse hook blocking writes to external user game project directories."""

import json
import os
import sys

sys.dont_write_bytecode = True

EXTERNAL_GAME_PROJECT_ROOTS = (
    "/Users/henry/Documents/Unreal Projects/",
    "/Users/henry/Unreal/",
    "/Users/henry/Godot/Projects/",
)


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

  if any(target_path.startswith(root) for root in EXTERNAL_GAME_PROJECT_ROOTS):
    print(
        json.dumps({
            "decision": "deny",
            "reason": (
                "External user game project files are read-only. "
                "Modify LAYERS-Agentic workspace files instead."
            ),
        })
    )
    return 0

  print(json.dumps({"decision": "allow"}))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
