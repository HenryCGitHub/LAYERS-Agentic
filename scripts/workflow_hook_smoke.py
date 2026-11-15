#!/usr/bin/env python3
"""Smoke test verifying composable Auto-Goal, Auto-Grill & 2-Step Auto-GG workflows."""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

REPO_ROOT = Path(__file__).resolve().parents[1]
HOOK_PATH = REPO_ROOT / ".agents" / "hooks" / "auto_gg_hook.py"
DISCOVER_PATH = REPO_ROOT / ".agents" / "skills" / "auto-goal" / "scripts" / "discover_signals.py"


def _run_hook(
    event: str,
    payload: dict,
    *,
    force_dirty: str = "0",
) -> dict:
  env = dict(os.environ)
  env["PYTHONDONTWRITEBYTECODE"] = "1"
  env["LAYERS_HOOK_FORCE_DIRTY"] = force_dirty
  proc = subprocess.run(
      [sys.executable, str(HOOK_PATH), "--event", event],
      cwd=str(REPO_ROOT),
      input=json.dumps(payload),
      capture_output=True,
      text=True,
      timeout=15,
      env=env,
  )
  assert proc.returncode == 0, f"Hook {event} failed ({proc.returncode}): {proc.stderr}"
  return json.loads(proc.stdout.strip() or "{}")


def _load_state(tmp_dir: Path) -> dict:
  state_file = tmp_dir / "auto_gg_state.json"
  if not state_file.is_file():
    return {"active": False, "phase": "idle"}
  return json.loads(state_file.read_text(encoding="utf-8"))


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


def _verify_skills_and_discovery() -> None:
  _check_frontmatter(REPO_ROOT / ".agents" / "skills" / "auto-goal" / "SKILL.md", "auto-goal")
  _check_frontmatter(REPO_ROOT / ".agents" / "skills" / "auto-grill" / "SKILL.md", "auto-grill")
  _check_frontmatter(REPO_ROOT / ".agents" / "skills" / "auto-gg" / "SKILL.md", "auto-gg")

  legacy_discover = REPO_ROOT / ".agents" / "skills" / "auto-gg" / "scripts" / "discover_signals.py"
  assert not legacy_discover.exists(), f"Duplicate discover script still exists: {legacy_discover}"
  assert DISCOVER_PATH.is_file(), f"Missing unified discover script: {DISCOVER_PATH}"

  env = dict(os.environ)
  env["PYTHONDONTWRITEBYTECODE"] = "1"
  proc = subprocess.run(
      [sys.executable, str(DISCOVER_PATH), "--no-smoke", "unreal"],
      cwd=str(REPO_ROOT),
      capture_output=True,
      text=True,
      timeout=20,
      env=env,
  )
  assert proc.returncode == 0, f"discover_signals.py failed: {proc.stderr}"
  report = json.loads(proc.stdout)
  assert report.get("focus") == "unreal", f"Unexpected focus: {report.get('focus')}"
  assert isinstance(report.get("focusMatches"), list) and len(report["focusMatches"]) > 0, (
      "Expected non-empty focusMatches for 'unreal'"
  )
  assert report.get("pluginVersion") == "1.0.0", f"Unexpected pluginVersion: {report.get('pluginVersion')}"
  assert report.get("zipParityOk") is True, "Expected zipParityOk is True"
  assert isinstance(report.get("monolithHotspots"), list), "Expected monolithHotspots list"
  assert isinstance(report.get("untestedModules"), list), "Expected untestedModules list"
  assert report.get("godotLeakageHits") == [], f"Unexpected godotLeakageHits: {report.get('godotLeakageHits')}"


def _verify_non_trigger_guards() -> None:
  with tempfile.TemporaryDirectory() as td:
    tmp_dir = Path(td)
    for phrase in (
        "auto goal should loop continuously",
        "should we design separate auto goal and auto grill?",
        "is auto gg working well right now?",
    ):
      out = _run_hook("pre_invocation", {"artifactDirectoryPath": str(tmp_dir), "lastUserInput": phrase})
      st = _load_state(tmp_dir)
      assert not st.get("active"), f"False trigger on conversational phrase: {phrase!r} -> {st}"
      assert out == {}, f"Expected no injectSteps on non-trigger: {out}"

    # Explicit slash command WITH trailing question mark MUST still trigger
    out = _run_hook(
        "pre_invocation",
        {
            "artifactDirectoryPath": str(tmp_dir),
            "lastUserInput": "/auto-grill should we place button left or right?",
        },
    )
    st = _load_state(tmp_dir)
    assert st.get("active") is True and st.get("mode") == "grill", (
        f"Expected /auto-grill with ? to activate mode=='grill', got: {st}"
    )
    assert "injectSteps" in out, "Expected injectSteps for /auto-grill"


def _verify_auto_goal_continuous() -> None:
  with tempfile.TemporaryDirectory() as td:
    tmp_dir = Path(td)
    out = _run_hook(
        "pre_invocation",
        {"artifactDirectoryPath": str(tmp_dir), "lastUserInput": "/auto-goal unreal bridge"},
    )
    st = _load_state(tmp_dir)
    assert st.get("active") is True and st.get("mode") == "goal", st
    assert st.get("phase") == "discovering" and st.get("round") == 1, st
    assert "injectSteps" in out, out

    _run_hook(
        "post_tool",
        {"artifactDirectoryPath": str(tmp_dir), "toolCall": {"name": "exit_plan_mode", "args": {"plan": "do"}}},
    )
    st = _load_state(tmp_dir)
    assert st.get("phase") == "building", st

    # Mid-round review due when dirty code present and no [round-complete] marker
    _run_hook(
        "post_tool",
        {
            "artifactDirectoryPath": str(tmp_dir),
            "toolCall": {"name": "enter_plan_mode", "args": {"reason": "30 step review"}},
        },
        force_dirty="1",
    )
    st = _load_state(tmp_dir)
    assert st.get("phase") == "reviewing" and st.get("round") == 1, st

    _run_hook(
        "post_tool",
        {"artifactDirectoryPath": str(tmp_dir), "toolCall": {"name": "exit_plan_mode", "args": {"plan": "resume"}}},
    )
    st = _load_state(tmp_dir)
    assert st.get("phase") == "building", st

    # Round completion handoff advances to Round 2
    _run_hook(
        "post_tool",
        {
            "artifactDirectoryPath": str(tmp_dir),
            "toolCall": {"name": "enter_plan_mode", "args": {"reason": "[round-complete] Shipped bridge test"}},
        },
        force_dirty="0",
    )
    st = _load_state(tmp_dir)
    assert st.get("phase") == "discovering" and st.get("round") == 2, st

    out2 = _run_hook(
        "pre_invocation",
        {"artifactDirectoryPath": str(tmp_dir), "lastUserInput": "/auto-goal unreal bridge"},
    )
    msg2 = out2["injectSteps"][0]["systemMessage"]["systemMessage"]
    assert "Round 2" in msg2, f"Expected Round 2 prompt injection, got: {msg2}"

    # Explicit stop ends loop
    _run_hook(
        "pre_invocation",
        {"artifactDirectoryPath": str(tmp_dir), "lastUserInput": "stop auto goal"},
    )
    st = _load_state(tmp_dir)
    assert st.get("active") is False and st.get("phase") == "idle", st


def _verify_auto_grill_single_pass() -> None:
  with tempfile.TemporaryDirectory() as td:
    tmp_dir = Path(td)
    out = _run_hook(
        "pre_invocation",
        {"artifactDirectoryPath": str(tmp_dir), "lastUserInput": "/auto-grill refine Stage 2 header"},
    )
    st = _load_state(tmp_dir)
    assert st.get("active") is True and st.get("mode") == "grill", st
    assert st.get("phase") == "grilling_ux" and st.get("round") == 1, st
    assert "injectSteps" in out, out

    _run_hook(
        "post_tool",
        {"artifactDirectoryPath": str(tmp_dir), "toolCall": {"name": "ask_question", "args": {"questions": []}}},
    )
    st = _load_state(tmp_dir)
    assert st.get("phase") == "answered", st

    _run_hook(
        "post_tool",
        {"artifactDirectoryPath": str(tmp_dir), "toolCall": {"name": "exit_plan_mode", "args": {"plan": "build"}}},
    )
    st = _load_state(tmp_dir)
    assert st.get("phase") == "building", st

    stop_out = _run_hook(
        "stop",
        {"artifactDirectoryPath": str(tmp_dir), "terminationReason": "NO_TOOL_CALL", "fullyIdle": True},
        force_dirty="0",
    )
    assert stop_out.get("decision") == "allow", stop_out
    st = _load_state(tmp_dir)
    assert st.get("active") is False and st.get("phase") == "idle", st


def _verify_auto_gg_two_step() -> None:
  # Branch A: select_goal -> grill_chosen -> answered -> building -> Round 2
  with tempfile.TemporaryDirectory() as td:
    tmp_dir = Path(td)
    _run_hook(
        "pre_invocation",
        {"artifactDirectoryPath": str(tmp_dir), "lastUserInput": "/auto-gg stage 2"},
    )
    st = _load_state(tmp_dir)
    assert st.get("active") is True and st.get("mode") == "gg", st
    assert st.get("phase") == "select_goal" and st.get("round") == 1, st

    # 1st ask_question (Goal choice) -> grill_chosen
    _run_hook(
        "post_tool",
        {"artifactDirectoryPath": str(tmp_dir), "toolCall": {"name": "ask_question", "args": {"questions": []}}},
    )
    st = _load_state(tmp_dir)
    assert st.get("phase") == "grill_chosen", st

    # 2nd ask_question (UX fork on chosen goal) -> answered
    _run_hook(
        "post_tool",
        {"artifactDirectoryPath": str(tmp_dir), "toolCall": {"name": "ask_question", "args": {"questions": []}}},
    )
    st = _load_state(tmp_dir)
    assert st.get("phase") == "answered", st

    _run_hook(
        "post_tool",
        {"artifactDirectoryPath": str(tmp_dir), "toolCall": {"name": "exit_plan_mode", "args": {"plan": "run"}}},
    )
    st = _load_state(tmp_dir)
    assert st.get("phase") == "building", st

    _run_hook(
        "post_tool",
        {
            "artifactDirectoryPath": str(tmp_dir),
            "toolCall": {"name": "enter_plan_mode", "args": {"reason": "[round-complete] done"}},
        },
        force_dirty="0",
    )
    st = _load_state(tmp_dir)
    assert st.get("phase") == "select_goal" and st.get("round") == 2, st

  # Branch B: zero UX ambiguity -> exit_plan_mode directly from grill_chosen
  with tempfile.TemporaryDirectory() as td:
    tmp_dir = Path(td)
    _run_hook(
        "pre_invocation",
        {"artifactDirectoryPath": str(tmp_dir), "lastUserInput": "Auto GG"},
    )
    _run_hook(
        "post_tool",
        {"artifactDirectoryPath": str(tmp_dir), "toolCall": {"name": "ask_question", "args": {"questions": []}}},
    )
    assert _load_state(tmp_dir).get("phase") == "grill_chosen"

    _run_hook(
        "post_tool",
        {"artifactDirectoryPath": str(tmp_dir), "toolCall": {"name": "exit_plan_mode", "args": {"plan": "direct"}}},
    )
    assert _load_state(tmp_dir).get("phase") == "building"

  # Cancel ask_question resets active=False, phase="idle"
  with tempfile.TemporaryDirectory() as td:
    tmp_dir = Path(td)
    _run_hook(
        "pre_invocation",
        {"artifactDirectoryPath": str(tmp_dir), "lastUserInput": "/auto-gg"},
    )
    _run_hook(
        "post_tool",
        {
            "artifactDirectoryPath": str(tmp_dir),
            "toolCall": {"name": "ask_question", "args": {"questions": []}},
            "error": "User canceled",
        },
    )
    st = _load_state(tmp_dir)
    assert st.get("active") is False and st.get("phase") == "idle", st


def main() -> int:
  _verify_skills_and_discovery()
  _verify_non_trigger_guards()
  _verify_auto_goal_continuous()
  _verify_auto_grill_single_pass()
  _verify_auto_gg_two_step()
  print("WORKFLOW_SMOKE_OK")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
