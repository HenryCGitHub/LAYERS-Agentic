#!/usr/bin/env python3
"""Fast repository signal collector for /auto-goal and /auto-gg discovery."""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import json
import os
from pathlib import Path
import re
import subprocess

REPO_ROOT = Path(__file__).resolve().parents[4]
TODO_PATTERN = re.compile(r"\b(?:TODO|FIXME)\b")
WARNING_PATTERN = re.compile(r"(?:AssertionError|Error:|Traceback|FAIL)")
EXCLUDED_DIR_NAMES = {
    "__pycache__",
    "node_modules",
    ".dart_tool",
    "build",
    ".git",
    ".firebase",
    "ios",
    "android",
    "macos",
    "linux",
    "windows",
}
PART_OF_RE = re.compile(r"^\s*part\s+of\s+['\"]([^'\"]+\.dart)['\"]\s*;", re.MULTILINE)
CONDITIONAL_DART_RE = re.compile(
    r"(?:import|export)\s+['\"]([^'\"]+\.dart)['\"][^;]*?\bif\s*\([^)]+\)\s*['\"]([^'\"]+\.dart)['\"]",
    re.DOTALL,
)
IMPORT_DART_RE = re.compile(r"(?:import|export)\s+['\"]([^'\"]+\.dart)['\"]", re.MULTILINE)


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


def _run_cloud_proxy_test() -> dict[str, object]:
  test_script = REPO_ROOT / "scripts" / "cloud_proxy_test.py"
  if not test_script.is_file():
    return {
        "ok": False,
        "skipped": True,
        "warningsAndErrors": ["scripts/cloud_proxy_test.py unavailable."],
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
    ok = proc.returncode == 0 and "CLOUD_PROXY_TEST_OK" in proc.stdout
    return {
        "ok": ok,
        "warningsAndErrors": warnings_and_errors,
    }
  except Exception as exc:
    return {
        "ok": False,
        "warningsAndErrors": [f"Cloud proxy test exception: {exc}"],
    }


def _iter_source_files(roots: list[Path], suffixes: tuple[str, ...]) -> list[Path]:
  results: list[Path] = []
  for root in roots:
    if root.is_file():
      if root.suffix in suffixes:
        results.append(root)
    elif root.is_dir():
      for base, dirs, files in os.walk(root):
        dirs[:] = sorted(
            d for d in dirs if d not in EXCLUDED_DIR_NAMES and not d.startswith(".")
        )
        for name in sorted(files):
          fpath = Path(base) / name
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
          REPO_ROOT / "functions",
          REPO_ROOT / "test",
          REPO_ROOT / "scripts",
      ],
      (".dart", ".py", ".js", ".md"),
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
          REPO_ROOT / "functions",
      ],
      (".dart", ".js"),
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
          REPO_ROOT / "scripts" / "cloud_proxy_test.py",
      ],
      (".dart", ".py"),
  ):
    try:
      test_corpus_parts.append(tf.read_text(encoding="utf-8", errors="replace"))
    except OSError:
      continue
  test_corpus = "\n".join(test_corpus_parts)

  modules: list[Path] = []
  dart_lib_files = _iter_source_files([REPO_ROOT / "lib"], (".dart",))
  parent_paths: dict[Path, set[Path]] = {}
  conditional_gateways: set[Path] = set()
  for fpath in dart_lib_files:
    if fpath.name.endswith(".g.dart") or fpath.name.endswith(".freezed.dart"):
      continue
    modules.append(fpath)
    try:
      text = fpath.read_text(encoding="utf-8", errors="replace")
    except OSError:
      continue
    resolved = fpath.resolve()
    for m in PART_OF_RE.finditer(text):
      target = (fpath.parent / m.group(1)).resolve()
      if target.is_file():
        parent_paths.setdefault(resolved, set()).add(target)
    for m in CONDITIONAL_DART_RE.finditer(text):
      conditional_gateways.add(resolved)
      for rel_target in (m.group(1), m.group(2)):
        target = (fpath.parent / rel_target).resolve()
        if target.is_file():
          parent_paths.setdefault(target, set()).add(resolved)

  if conditional_gateways:
    for fpath in dart_lib_files:
      try:
        text = fpath.read_text(encoding="utf-8", errors="replace")
      except OSError:
        continue
      resolved = fpath.resolve()
      for m in IMPORT_DART_RE.finditer(text):
        target = (fpath.parent / m.group(1)).resolve()
        if target in conditional_gateways and target != resolved:
          parent_paths.setdefault(target, set()).add(resolved)

  def _related_stems(fpath: Path) -> set[str]:
    stems = {fpath.stem}
    seen_paths = {fpath.resolve()}
    queue = [fpath.resolve()]
    while queue:
      cur = queue.pop()
      for p in parent_paths.get(cur, ()):
        stems.add(p.stem)
        if p not in seen_paths:
          seen_paths.add(p)
          queue.append(p)
    return stems

  untested: list[str] = []
  for fpath in modules:
    stems = _related_stems(fpath)
    if not any(re.search(rf"\b{re.escape(stem)}\b", test_corpus) for stem in stems):
      untested.append(fpath.relative_to(REPO_ROOT).as_posix())
  return sorted(untested)


def _scan_todo_markers(limit: int = 15) -> list[str]:
  markers: list[str] = []
  candidates = _iter_source_files(
      [
          REPO_ROOT / "functions",
          REPO_ROOT / "lib",
      ],
      (".js", ".dart", ".md"),
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

  cloud_proxy_test = (
      {"ok": True, "skipped": True, "warningsAndErrors": []}
      if skip_tests
      else _run_cloud_proxy_test()
  )

  report = {
      "focus": focus,
      "focusMatches": _scan_focus_matches(focus),
      "recentCommits": _git_lines(["log", "-n", "6", "--oneline"]),
      "dirtyFiles": _git_lines(["status", "--short"]),
      "cloudProxyTest": cloud_proxy_test,
      "monolithHotspots": _scan_monolith_hotspots(),
      "untestedModules": _scan_untested_modules(),
      "leakageHits": [],
      "todoMarkers": _scan_todo_markers(15),
  }
  print(json.dumps(report, indent=2))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
