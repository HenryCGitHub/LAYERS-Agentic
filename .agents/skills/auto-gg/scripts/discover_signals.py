#!/usr/bin/env python3
"""Fast signal collector for /auto-gg automated goal discovery."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

REPO_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_GODOT_BIN = Path(
    "/Users/henry/Godot/Editors/4.7.2-stable/Godot.app/Contents/MacOS/Godot"
)
TODO_PATTERN = re.compile(r"\b(?:TODO|FIXME)\b")
WARNING_PATTERN = re.compile(r"(?:WARNING:|ERROR:|SCRIPT ERROR:)")


def _run(cmd: list[str], cwd: Path, timeout: int = 10) -> subprocess.CompletedProcess[str]:
  return subprocess.run(
      cmd,
      cwd=str(cwd),
      capture_output=True,
      text=True,
      timeout=timeout,
  )


def _git_lines(args: list[str]) -> list[str]:
  try:
    proc = _run(["git", *args], REPO_ROOT, timeout=5)
    if proc.returncode != 0:
      return []
    return [line.rstrip() for line in proc.stdout.splitlines() if line.strip()]
  except Exception:
    return []


def _read_plugin_version() -> str:
  cfg = REPO_ROOT / "godot_plugin" / "addons" / "layers" / "plugin.cfg"
  if not cfg.is_file():
    return ""
  for line in cfg.read_text(encoding="utf-8", errors="replace").splitlines():
    m = re.match(r'^\s*version\s*=\s*"([^"]+)"', line)
    if m:
      return m.group(1).strip()
  return ""


def _check_zip_parity() -> bool:
  src_dir = REPO_ROOT / "godot_plugin" / "addons" / "layers"
  zip_path = REPO_ROOT / "web" / "layers_godot_plugin.zip"
  if not src_dir.is_dir() or not zip_path.is_file():
    return False
  expected: dict[str, str] = {}
  base_root = REPO_ROOT / "godot_plugin"
  for base, _, files in os.walk(src_dir):
    for name in files:
      if name == ".DS_Store":
        continue
      full = Path(base) / name
      rel = full.relative_to(base_root).as_posix()
      expected[rel] = hashlib.sha256(full.read_bytes()).hexdigest()

  actual: dict[str, str] = {}
  try:
    with zipfile.ZipFile(zip_path, "r") as zf:
      for info in zf.infolist():
        if info.is_dir():
          continue
        name = info.filename.replace("\\", "/")
        if os.path.basename(name) == ".DS_Store":
          continue
        actual[name] = hashlib.sha256(zf.read(info)).hexdigest()
  except Exception:
    return False
  return expected == actual


def _find_godot_binary() -> str:
  env_bin = os.environ.get("GODOT_BIN", "").strip()
  if env_bin and os.access(env_bin, os.X_OK):
    return env_bin
  if DEFAULT_GODOT_BIN.is_file() and os.access(DEFAULT_GODOT_BIN, os.X_OK):
    return str(DEFAULT_GODOT_BIN)
  which_bin = shutil.which("godot")
  return which_bin or ""


def _run_godot_smoke() -> dict[str, object]:
  godot_bin = _find_godot_binary()
  smoke_script = REPO_ROOT / "scripts" / "godot_plugin_smoke.gd"
  addons_src = REPO_ROOT / "godot_plugin" / "addons"
  if not godot_bin or not smoke_script.is_file() or not addons_src.is_dir():
    return {
        "ok": False,
        "skipped": True,
        "warningsAndErrors": ["Godot binary or smoke script unavailable."],
    }

  tmp_dir = Path(tempfile.mkdtemp(prefix="layers_discover_"))
  try:
    (tmp_dir / "project.godot").write_text(
        'config_version=5\n\n[application]\nconfig/name="LAYERS Smoke"\n',
        encoding="utf-8",
    )
    shutil.copytree(addons_src, tmp_dir / "addons")
    proc = _run(
        [godot_bin, "--headless", "--path", str(tmp_dir), "--script", str(smoke_script)],
        REPO_ROOT,
        timeout=25,
    )
    combined = f"{proc.stdout}\n{proc.stderr}"
    lines = combined.splitlines()
    warnings_and_errors: list[str] = []
    seen_indices: set[int] = set()
    for idx, line in enumerate(lines):
      if WARNING_PATTERN.search(line):
        start = idx
        end = min(len(lines), idx + 3)
        block = [
            lines[k]
            for k in range(start, end)
            if k not in seen_indices and lines[k].strip()
        ]
        for k in range(start, end):
          seen_indices.add(k)
        if block:
          warnings_and_errors.append("\n".join(block))
    ok = proc.returncode == 0 and "GODOT_SMOKE_OK" in proc.stdout
    return {
        "ok": ok,
        "warningsAndErrors": warnings_and_errors[:12],
    }
  except Exception as exc:
    return {
        "ok": False,
        "warningsAndErrors": [f"Headless Godot smoke exception: {exc}"],
    }
  finally:
    shutil.rmtree(tmp_dir, ignore_errors=True)


def _scan_todo_markers(limit: int = 15) -> list[str]:
  markers: list[str] = []
  targets = [
      REPO_ROOT / "godot_plugin" / "addons" / "layers",
      REPO_ROOT / "functions" / "index.js",
      REPO_ROOT / "lib",
  ]
  for target in targets:
    if len(markers) >= limit:
      break
    files = [target] if target.is_file() else sorted(target.rglob("*")) if target.is_dir() else []
    for fpath in files:
      if not fpath.is_file():
        continue
      if fpath.suffix not in (".gd", ".js", ".dart", ".cfg", ".md"):
        continue
      try:
        text = fpath.read_text(encoding="utf-8", errors="replace")
      except OSError:
        continue
      for lineno, line in enumerate(text.splitlines(), start=1):
        if TODO_PATTERN.search(line):
          rel = fpath.relative_to(REPO_ROOT).as_posix()
          markers.append(f"{rel}:{lineno}: {line.strip()[:140]}")
          if len(markers) >= limit:
            return markers
  return markers


def main() -> int:
  focus = " ".join(sys.argv[1:]).strip()
  report = {
      "focus": focus,
      "recentCommits": _git_lines(["log", "-n", "6", "--oneline"]),
      "dirtyFiles": _git_lines(["status", "--short"]),
      "pluginVersion": _read_plugin_version(),
      "zipParityOk": _check_zip_parity(),
      "godotSmoke": _run_godot_smoke(),
      "todoMarkers": _scan_todo_markers(15),
  }
  print(json.dumps(report, indent=2))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
