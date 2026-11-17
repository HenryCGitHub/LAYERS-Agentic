#!/usr/bin/env python3
"""Fast repository signal collector for /auto-goal and /auto-gg discovery."""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

REPO_ROOT = Path(__file__).resolve().parents[4]
TODO_PATTERN = re.compile(r"\b(?:TODO|FIXME)\b")
WARNING_PATTERN = re.compile(r"(?:AssertionError|Error:|Traceback|FAIL)")
UNREAL_LEAKAGE_PATTERN = re.compile(
    r"(?:\.uasset\b|\.uproject\b|\bACharacter\b|\bAActor\b|\bUBoxComponent\b|\bUMG\b|(?<!Concept\s)(?<!section\s)\bBlueprints?\b|\b1\s*UU\b|\bcm/s\b)"
)
UNREAL_LEAKAGE_ALLOWLIST = {
    "lib/utils/godot_spec_guard.dart",
    "lib/constants/text_style_guide.dart",
}


def _run(
    cmd: list[str],
    cwd: Path,
    timeout: int = 10,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
  return subprocess.run(
      cmd,
      cwd=str(cwd),
      capture_output=True,
      text=True,
      timeout=timeout,
      env=env,
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
  cfg_path = REPO_ROOT / "godot_plugin" / "addons" / "layers" / "plugin.cfg"
  if not cfg_path.is_file():
    return ""
  try:
    text = cfg_path.read_text(encoding="utf-8")
    m = re.search(r'^version\s*=\s*"([^"]+)"', text, re.M)
    return m.group(1).strip() if m else ""
  except Exception:
    return ""


def _check_zip_parity() -> bool:
  src_dir = REPO_ROOT / "godot_plugin" / "addons" / "layers"
  zip_path = REPO_ROOT / "web" / "layers_godot_plugin.zip"
  if not src_dir.is_dir() or not zip_path.is_file():
    return False
  expected: dict[str, str] = {}
  base_root = REPO_ROOT / "godot_plugin"
  for base, dirs, files in os.walk(src_dir):
    dirs[:] = [d for d in dirs if d != "__pycache__"]
    for name in files:
      if name == ".DS_Store" or name.endswith(".uid") or name.endswith(".pyc"):
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
        if (
            "/__pycache__/" in name
            or os.path.basename(name) == ".DS_Store"
            or name.endswith(".uid")
            or name.endswith(".pyc")
        ):
          continue
        actual[name] = hashlib.sha256(zf.read(info)).hexdigest()
  except Exception:
    return False
  return expected == actual


def _run_godot_cloud_test() -> dict[str, object]:
  test_script = REPO_ROOT / "scripts" / "godot_cloud_test.py"
  if not test_script.is_file():
    return {
        "ok": False,
        "skipped": True,
        "warningsAndErrors": ["scripts/godot_cloud_test.py unavailable."],
    }

  try:
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    proc = _run(
        [sys.executable, str(test_script)],
        REPO_ROOT,
        timeout=25,
        env=env,
    )
    combined = f"{proc.stdout}\n{proc.stderr}"
    lines = [line for line in combined.splitlines() if line.strip()]
    warnings_and_errors = [
        line for line in lines if WARNING_PATTERN.search(line)
    ][:12]
    ok = proc.returncode == 0 and "GODOT_CLOUD_TEST_OK" in proc.stdout
    return {
        "ok": ok,
        "warningsAndErrors": warnings_and_errors,
    }
  except Exception as exc:
    return {
        "ok": False,
        "warningsAndErrors": [f"Godot cloud test exception: {exc}"],
    }


def _iter_source_files(roots: list[Path], suffixes: tuple[str, ...]) -> list[Path]:
  results: list[Path] = []
  for root in roots:
    if root.is_file():
      if root.suffix in suffixes:
        results.append(root)
    elif root.is_dir():
      for fpath in sorted(root.rglob("*")):
        if not fpath.is_file() or "__pycache__" in fpath.parts:
          continue
        if fpath.suffix in suffixes:
          results.append(fpath)
  return results


def _scan_focus_matches(focus: str, limit: int = 8) -> list[str]:
  if not focus.strip():
    return []
  tokens = [
      tok.lower()
      for tok in re.split(r"[^A-Za-z0-9_]+", focus)
      if len(tok) >= 2
  ]
  if not tokens:
    return []

  candidates = _iter_source_files(
      [
          REPO_ROOT / "lib",
          REPO_ROOT / "godot_plugin" / "addons" / "layers",
          REPO_ROOT / "functions",
          REPO_ROOT / "test",
      ],
      (".dart", ".gd", ".cfg", ".py", ".js", ".md"),
  )
  scored: list[tuple[int, str]] = []
  for fpath in candidates:
    rel = fpath.relative_to(REPO_ROOT).as_posix()
    rel_lower = rel.lower()
    score = sum(3 for tok in tokens if tok in rel_lower)
    if score == 0:
      try:
        content_lower = fpath.read_text(encoding="utf-8", errors="replace").lower()
      except OSError:
        continue
      score = sum(1 for tok in tokens if tok in content_lower)
    if score > 0:
      scored.append((score, rel))

  scored.sort(key=lambda item: (-item[0], item[1]))
  return [rel for _, rel in scored[:limit]]


def _scan_monolith_hotspots(min_lines: int = 350, limit: int = 6) -> list[dict[str, object]]:
  candidates = _iter_source_files(
      [
          REPO_ROOT / "lib",
          REPO_ROOT / "functions" / "index.js",
          REPO_ROOT / "godot_plugin" / "addons" / "layers",
      ],
      (".dart", ".js", ".gd"),
  )
  hotspots: list[dict[str, object]] = []
  for fpath in candidates:
    try:
      line_count = len(fpath.read_text(encoding="utf-8", errors="replace").splitlines())
    except OSError:
      continue
    if line_count >= min_lines:
      hotspots.append({
          "path": fpath.relative_to(REPO_ROOT).as_posix(),
          "lines": line_count,
      })
  hotspots.sort(key=lambda item: (-int(item["lines"]), str(item["path"])))
  return hotspots[:limit]


def _scan_untested_modules() -> list[str]:
  test_corpus_parts: list[str] = []
  for tf in _iter_source_files(
      [
          REPO_ROOT / "test",
          REPO_ROOT / "scripts" / "godot_cloud_test.py",
          REPO_ROOT / "scripts" / "godot_plugin_test.gd",
      ],
      (".dart", ".py", ".gd"),
  ):
    try:
      test_corpus_parts.append(tf.read_text(encoding="utf-8", errors="replace"))
    except OSError:
      continue
  test_corpus = "\n".join(test_corpus_parts)

  modules: list[Path] = []
  for fpath in _iter_source_files([REPO_ROOT / "lib"], (".dart",)):
    if fpath.name.endswith(".g.dart") or fpath.name.endswith(".freezed.dart"):
      continue
    modules.append(fpath)

  gd_dir = REPO_ROOT / "godot_plugin" / "addons" / "layers"
  for fpath in _iter_source_files([gd_dir], (".gd",)):
    modules.append(fpath)

  untested: list[str] = []
  for fpath in modules:
    stem = fpath.stem
    if not re.search(rf"\b{re.escape(stem)}\b", test_corpus):
      untested.append(fpath.relative_to(REPO_ROOT).as_posix())
  return sorted(untested)


def _scan_unreal_leakage(limit: int = 20) -> list[str]:
  hits: list[str] = []
  candidates = _iter_source_files(
      [REPO_ROOT / "lib", REPO_ROOT / "godot_plugin"],
      (".dart", ".gd", ".cfg", ".md", ".txt"),
  )
  for fpath in candidates:
    rel = fpath.relative_to(REPO_ROOT).as_posix()
    if rel in UNREAL_LEAKAGE_ALLOWLIST:
      continue
    try:
      lines = fpath.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
      continue
    for lineno, line in enumerate(lines, start=1):
      if UNREAL_LEAKAGE_PATTERN.search(line):
        hits.append(f"{rel}:{lineno}: {line.strip()[:140]}")
        if len(hits) >= limit:
          return hits
  return hits


def _scan_todo_markers(limit: int = 15) -> list[str]:
  markers: list[str] = []
  candidates = _iter_source_files(
      [
          REPO_ROOT / "godot_plugin" / "addons" / "layers",
          REPO_ROOT / "functions" / "index.js",
          REPO_ROOT / "lib",
      ],
      (".gd", ".cfg", ".js", ".dart", ".md"),
  )
  for fpath in candidates:
    try:
      lines = fpath.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
      continue
    for lineno, line in enumerate(lines, start=1):
      if TODO_PATTERN.search(line):
        rel = fpath.relative_to(REPO_ROOT).as_posix()
        markers.append(f"{rel}:{lineno}: {line.strip()[:140]}")
        if len(markers) >= limit:
          return markers
  return markers


def main() -> int:
  raw_args = sys.argv[1:]
  skip_tests = "--no-test" in raw_args
  focus = " ".join(arg for arg in raw_args if arg != "--no-test").strip()

  godot_cloud_test = (
      {"ok": True, "skipped": True, "warningsAndErrors": []}
      if skip_tests
      else _run_godot_cloud_test()
  )

  report = {
      "focus": focus,
      "focusMatches": _scan_focus_matches(focus),
      "recentCommits": _git_lines(["log", "-n", "6", "--oneline"]),
      "dirtyFiles": _git_lines(["status", "--short"]),
      "pluginVersion": _read_plugin_version(),
      "zipParityOk": _check_zip_parity(),
      "godotCloudTest": godot_cloud_test,
      "monolithHotspots": _scan_monolith_hotspots(),
      "untestedModules": _scan_untested_modules(),
      "unrealLeakageHits": _scan_unreal_leakage(),
      "todoMarkers": _scan_todo_markers(15),
  }
  print(json.dumps(report, indent=2))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
