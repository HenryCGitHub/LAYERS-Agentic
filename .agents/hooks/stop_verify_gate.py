#!/usr/bin/env python3
"""Antigravity Stop hook enforcing multi-stack verification on dirty code."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

REPO_ROOT = Path(__file__).resolve().parents[2]
VERIFIED_HASH_FILE = Path("/tmp/layers_verified_state.sha256")
WATCHED_PREFIXES = (
    "lib/",
    "test/",
    "functions/",
    "godot_plugin/",
    "scripts/",
    "web/layers_godot_plugin.zip",
    "pubspec.yaml",
)


def _run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
  return subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)


def _is_watched(rel_path: str) -> bool:
  return any(rel_path == p or rel_path.startswith(p) for p in WATCHED_PREFIXES)


def compute_code_state(repo_root: Path) -> tuple[bool, str]:
  head_proc = _run(["git", "rev-parse", "HEAD"], repo_root)
  head_sha = head_proc.stdout.strip() if head_proc.returncode == 0 else "NO_HEAD"
  status_proc = _run(
      ["git", "status", "--porcelain", "--untracked-files=all"], repo_root
  )
  if status_proc.returncode != 0:
    return False, head_sha

  watched_entries: list[tuple[str, str]] = []
  for raw_line in status_proc.stdout.splitlines():
    if len(raw_line) < 4:
      continue
    code = raw_line[:2]
    path_part = raw_line[3:].strip().strip('"')
    paths = [p.strip().strip('"') for p in path_part.split(" -> ")]
    if any(_is_watched(p) for p in paths):
      for p in paths:
        if _is_watched(p):
          watched_entries.append((code, p))

  if not watched_entries:
    return False, head_sha

  hasher = hashlib.sha256()
  hasher.update(head_sha.encode("utf-8"))
  for code, rel_path in sorted(set(watched_entries)):
    hasher.update(f"\n{code}:{rel_path}:".encode("utf-8"))
    target = repo_root / rel_path
    if target.is_file():
      hasher.update(target.read_bytes())
    else:
      hasher.update(b"__MISSING_OR_DIR__")
  return True, hasher.hexdigest()


def _breaker_path(conversation_id: str) -> Path:
  safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", conversation_id or "default")
  return Path(f"/tmp/layers_stop_breaker_{safe}.json")


def _load_breaker(path: Path) -> dict:
  if not path.is_file():
    return {}
  try:
    data = json.loads(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}
  except (OSError, json.JSONDecodeError):
    return {}


def main() -> int:
  if "--stamp" in sys.argv:
    _, digest = compute_code_state(REPO_ROOT)
    VERIFIED_HASH_FILE.write_text(digest, encoding="utf-8")
    print(digest)
    return 0

  if "--print-state" in sys.argv:
    dirty, digest = compute_code_state(REPO_ROOT)
    print(f"{dirty}:{digest}")
    return 0

  raw = sys.stdin.read().strip()
  if not raw:
    print(json.dumps({"decision": "allow"}))
    return 0

  try:
    payload = json.loads(raw)
  except json.JSONDecodeError:
    print(json.dumps({"decision": "allow"}))
    return 0

  if not isinstance(payload, dict):
    print(json.dumps({"decision": "allow"}))
    return 0

  if payload.get("terminationReason") != "NO_TOOL_CALL" or not payload.get(
      "fullyIdle", True
  ):
    print(json.dumps({"decision": "allow"}))
    return 0

  has_dirty_code, digest = compute_code_state(REPO_ROOT)
  if not has_dirty_code:
    print(json.dumps({"decision": "allow"}))
    return 0

  if VERIFIED_HASH_FILE.is_file():
    if VERIFIED_HASH_FILE.read_text(encoding="utf-8").strip() == digest:
      print(json.dumps({"decision": "allow"}))
      return 0

  conv_id = str(payload.get("conversationId", "default"))
  b_path = _breaker_path(conv_id)
  breaker = _load_breaker(b_path)
  if breaker.get("digest") == digest and int(breaker.get("count", 0)) >= 3:
    print(json.dumps({"decision": "allow"}))
    return 0

  verify_script = REPO_ROOT / "scripts" / "verify_loop.sh"
  try:
    proc = subprocess.run(
        [str(verify_script), "--fast"],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        timeout=110,
    )
  except subprocess.TimeoutExpired:
    print(
        json.dumps({
            "decision": "continue",
            "reason": (
                "Stop-gate verification timed out after 110s while running "
                "./scripts/verify_loop.sh --fast."
            ),
        })
    )
    return 0

  if proc.returncode == 0:
    if b_path.is_file():
      b_path.unlink(missing_ok=True)
    VERIFIED_HASH_FILE.write_text(digest, encoding="utf-8")
    print(json.dumps({"decision": "allow"}))
    return 0

  next_count = (
      int(breaker.get("count", 0)) + 1 if breaker.get("digest") == digest else 1
  )
  b_path.write_text(
      json.dumps({"digest": digest, "count": next_count}), encoding="utf-8"
  )
  combined = "\n".join(p for p in (proc.stdout, proc.stderr) if p).strip()
  tail = combined[-1800:] if len(combined) > 1800 else combined
  print(
      json.dumps({
          "decision": "continue",
          "reason": (
              "Stop-gate verification failed (./scripts/verify_loop.sh --fast). "
              f"Fix these issues before finishing:\n{tail}"
          ),
      })
  )
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
