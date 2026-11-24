#!/usr/bin/env python3
"""Checks surviving .agents hooks, layers-ship skill, discover_signals.py, and CI parity."""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

REPO_ROOT = Path(__file__).resolve().parents[1]
HOOKS_JSON_PATH = REPO_ROOT / ".agents" / "hooks.json"
PRE_TOOL_GUARD_PATH = REPO_ROOT / ".agents" / "hooks" / "pre_tool_guard.py"
STOP_VERIFY_GATE_PATH = REPO_ROOT / ".agents" / "hooks" / "stop_verify_gate.py"
DISCOVER_PATH = REPO_ROOT / "scripts" / "discover_signals.py"


def _run_hook_script(script_path: Path, payload: dict) -> dict:
  env = dict(os.environ)
  env["PYTHONDONTWRITEBYTECODE"] = "1"
  proc = subprocess.run(
      [sys.executable, str(script_path)],
      cwd=str(REPO_ROOT),
      input=json.dumps(payload),
      capture_output=True,
      text=True,
      timeout=15,
      env=env,
  )
  assert proc.returncode == 0, f"{script_path.name} failed ({proc.returncode}): {proc.stderr}"
  return json.loads(proc.stdout.strip() or "{}")


def _check_frontmatter(path: Path, expected_name: str) -> None:
  assert path.is_file(), f"Missing skill file: {path}"
  text = path.read_text(encoding="utf-8")
  m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
  assert m, f"Missing YAML frontmatter in {path}"
  fm = m.group(1)
  assert re.search(rf"^name:\s*{re.escape(expected_name)}\s*$", fm, re.MULTILINE), (
      f"Frontmatter name mismatch in {path}"
  )
  assert re.search(r"^description:\s*\S+", fm, re.MULTILINE), (
      f"Missing description in {path}"
  )


def _verify_hooks_and_skills() -> None:
  assert HOOKS_JSON_PATH.is_file(), f"Missing hooks config: {HOOKS_JSON_PATH}"
  raw_hooks_text = HOOKS_JSON_PATH.read_text(encoding="utf-8")
  assert "auto_gg_hook" not in raw_hooks_text, "Legacy auto_gg_hook still referenced in hooks.json"
  cfg = json.loads(raw_hooks_text)
  assert isinstance(cfg, dict), f"Invalid hooks.json object: {type(cfg)}"
  assert set(cfg.keys()) == {"external-project-write-guard", "goal-verify-stop-gate"}, (
      f"Unexpected hook groups in hooks.json: {sorted(cfg.keys())}"
  )

  legacy_hook = REPO_ROOT / ".agents" / "hooks" / "auto_gg_hook.py"
  assert not legacy_hook.exists(), f"Legacy hook still exists: {legacy_hook}"

  for retired_skill in ("auto-goal", "auto-grill", "auto-gg", "sea"):
    retired_dir = REPO_ROOT / ".agents" / "skills" / retired_skill
    assert not retired_dir.exists(), f"Retired skill directory still exists: {retired_dir}"

  _check_frontmatter(REPO_ROOT / ".agents" / "skills" / "layers-ship" / "SKILL.md", "layers-ship")


def _verify_discover_signals() -> None:
  assert DISCOVER_PATH.is_file(), f"Missing signal script: {DISCOVER_PATH}"

  env = dict(os.environ)
  env["PYTHONDONTWRITEBYTECODE"] = "1"
  proc = subprocess.run(
      [sys.executable, str(DISCOVER_PATH), "--no-test", "workbench"],
      cwd=str(REPO_ROOT),
      capture_output=True,
      text=True,
      timeout=20,
      env=env,
  )
  assert proc.returncode == 0, f"discover_signals.py failed: {proc.stderr}"
  report = json.loads(proc.stdout)
  assert report.get("focus") == "workbench", f"Unexpected focus: {report.get('focus')}"
  assert isinstance(report.get("focusMatches"), list) and len(report["focusMatches"]) > 0, (
      "Expected non-empty focusMatches for 'workbench'"
  )
  assert "pluginVersion" not in report and "zipParityOk" not in report, (
      f"Removed plugin fields should not appear in report: {report.keys()}"
  )
  assert isinstance(report.get("cloudProxyTest"), dict), "Expected cloudProxyTest dict"
  assert isinstance(report.get("monolithHotspots"), list), "Expected monolithHotspots list"
  assert isinstance(report.get("untestedModules"), list), "Expected untestedModules list"
  assert isinstance(report.get("leakageHits"), list), "Expected leakageHits list"
  assert report.get("leakageHits") == [], (
      f"Unexpected non-Unreal leakage in lib/: {report.get('leakageHits')}"
  )

  spec = importlib.util.spec_from_file_location("discover_signals_mod", DISCOVER_PATH)
  assert spec is not None and spec.loader is not None
  discover_mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(discover_mod)
  for bad_sample in (
      "res://scenes/arena.tscn",
      "@export var move_speed",
      "Godot 4 CharacterBody3D",
      "InputMap",
  ):
    assert discover_mod.LEAKAGE_PATTERN.search(bad_sample), (
        f"Expected LEAKAGE_PATTERN to match: {bad_sample!r}"
    )
  for clean_sample in (
      "/Game/Blueprints/BP_Player.uasset",
      "last_godot_sync_ms",
  ):
    assert discover_mod.LEAKAGE_PATTERN.search(clean_sample) is None, (
        f"Unexpected LEAKAGE_PATTERN false positive: {clean_sample!r}"
    )

  proc_audit = subprocess.run(
      [sys.executable, str(DISCOVER_PATH), "--no-test", "audit codebase"],
      cwd=str(REPO_ROOT),
      capture_output=True,
      text=True,
      timeout=20,
      env=env,
  )
  assert proc_audit.returncode == 0, f"discover_signals.py audit failed: {proc_audit.stderr}"
  audit_report = json.loads(proc_audit.stdout)
  assert all("node_modules/" not in p for p in audit_report.get("focusMatches", [])), (
      f"Unexpected node_modules focusMatches: {audit_report.get('focusMatches')}"
  )
  untested = set(audit_report.get("untestedModules", []))
  for covered_part in (
      "lib/providers/workbench_storage_mixin.dart",
      "lib/utils/markdown_exporter_stub.dart",
      "lib/models/unreal_architecture_mode.dart",
  ):
    assert covered_part not in untested, f"Expected transitive export module covered: {covered_part}"


def _verify_pre_tool_guard() -> None:
  assert PRE_TOOL_GUARD_PATH.is_file(), f"Missing hook: {PRE_TOOL_GUARD_PATH}"
  for blocked_path in (
      "/Users/henry/Documents/Unreal Projects/MyGame/Content/Test.uasset",
      "/Users/henry/Godot/Projects/Demo/player.gd",
  ):
    out = _run_hook_script(PRE_TOOL_GUARD_PATH, {"toolCall": {"args": {"Path": blocked_path}}})
    assert out.get("decision") == "deny", f"Expected deny for {blocked_path}: {out}"

  allowed = _run_hook_script(
      PRE_TOOL_GUARD_PATH,
      {"toolCall": {"args": {"Path": str(REPO_ROOT / "lib" / "main.dart")}}},
  )
  assert allowed.get("decision") == "allow", f"Expected allow for workspace file: {allowed}"


def _verify_stop_verify_gate() -> None:
  assert STOP_VERIFY_GATE_PATH.is_file(), f"Missing hook: {STOP_VERIFY_GATE_PATH}"
  env = dict(os.environ)
  env["PYTHONDONTWRITEBYTECODE"] = "1"
  proc = subprocess.run(
      [sys.executable, str(STOP_VERIFY_GATE_PATH), "--print-state"],
      cwd=str(REPO_ROOT),
      capture_output=True,
      text=True,
      timeout=15,
      env=env,
  )
  assert proc.returncode == 0, f"stop_verify_gate.py --print-state failed: {proc.stderr}"
  state_line = proc.stdout.strip()
  assert re.match(r"^(True|False):[0-9a-f]+$", state_line), (
      f"Unexpected stop_verify_gate --print-state output: {state_line!r}"
  )

  non_idle = _run_hook_script(
      STOP_VERIFY_GATE_PATH,
      {"terminationReason": "TOOL_CALL", "fullyIdle": False},
  )
  assert non_idle.get("decision") == "allow", f"Expected allow when not fullyIdle: {non_idle}"


def _verify_ci_workflow() -> None:
  ci_yml = REPO_ROOT / ".github" / "workflows" / "ci.yml"
  legacy_deploy_yml = REPO_ROOT / ".github" / "workflows" / "deploy.yml"
  assert ci_yml.is_file(), f"Missing CI workflow: {ci_yml}"
  assert not legacy_deploy_yml.exists(), f"Legacy deploy workflow should be removed: {legacy_deploy_yml}"
  content = ci_yml.read_text(encoding="utf-8")
  lower_content = content.lower()
  for forbidden_token in ("layers_godot_plugin", "godot_plugin", "actions-gh-pages", "gh-pages"):
    assert forbidden_token not in lower_content, (
        f"Forbidden token {forbidden_token!r} present in {ci_yml}"
    )
  for required_entry in (
      "contents: read",
      "cloud_proxy_test.py",
      "workflow_hook_test.py",
      "dart analyze",
      "flutter test",
  ):
    assert required_entry in content, (
        f"Missing required CI entry {required_entry!r} in {ci_yml}"
    )


def main() -> int:
  _verify_hooks_and_skills()
  _verify_discover_signals()
  _verify_pre_tool_guard()
  _verify_stop_verify_gate()
  _verify_ci_workflow()
  print("WORKFLOW_HOOK_TEST_OK")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
