#!/usr/bin/env python3
"""Antigravity lifecycle hook driving continuous /auto-gg (Auto GG) rounds."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

STOP_RE = re.compile(
    r"(?:^\s*(?:/stop|stop|pause|done|quit|cancel|exit)\s*[.!]?\s*$|"
    r"\b(?:stop|pause|exit|end|quit|disable)\s+auto[\s_-]*gg\b)",
    re.IGNORECASE,
)
STARTS_TRIGGER_RE = re.compile(
    r"^\s*(?:/auto[-_]?gg|auto[\s_-]*gg)\b",
    re.IGNORECASE,
)
ACTION_TRIGGER_RE = re.compile(
    r"\b(?:start|run|begin|launch|kick\s*off|do|resume|continue)\s+auto[\s_-]*gg\b",
    re.IGNORECASE,
)
FOCUS_RE = re.compile(
    r"(?:/auto[-_]?gg|auto[\s_-]*gg)\b[:\s-]*(.*)$",
    re.IGNORECASE | re.DOTALL,
)


def _default_state() -> dict:
  return {
      "active": False,
      "phase": "idle",
      "round": 0,
      "focus": "",
      "lastSeenInput": "",
      "injectedRound": 0,
      "handoffRetries": 0,
  }


def _resolve_state_path(payload: dict) -> Path:
  art_dir = str(payload.get("artifactDirectoryPath", "")).strip()
  if art_dir:
    return Path(art_dir) / "auto_gg_state.json"
  conv_id = str(payload.get("conversationId", "default")).strip() or "default"
  safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", conv_id)
  return Path(f"/tmp/layers_auto_gg_{safe}.json")


def _load_state(path: Path) -> dict:
  state = _default_state()
  if not path.is_file():
    return state
  try:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(raw, dict):
      state.update(raw)
  except (OSError, json.JSONDecodeError):
    pass
  return state


def _save_state(path: Path, state: dict) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(json.dumps(state, indent=2), encoding="utf-8")


def _extract_focus(text: str) -> str:
  m = FOCUS_RE.search(text)
  if not m:
    return ""
  return re.sub(r"^[\s:,-]+", "", m.group(1)).strip()


def _is_start_trigger(text: str) -> bool:
  if STARTS_TRIGGER_RE.match(text):
    return True
  is_question = text.rstrip().endswith("?")
  if ACTION_TRIGGER_RE.search(text) and not is_question:
    return True
  return False


def _handle_pre_invocation(payload: dict) -> dict:
  state_path = _resolve_state_path(payload)
  state = _load_state(state_path)
  last_input = str(payload.get("lastUserInput", "")).strip()

  if last_input and last_input != state.get("lastSeenInput", ""):
    state["lastSeenInput"] = last_input
    if STOP_RE.search(last_input):
      state["active"] = False
      state["phase"] = "idle"
      _save_state(state_path, state)
      return {}
    if _is_start_trigger(last_input):
      was_active = bool(state.get("active", False))
      prev_round = int(state.get("round", 0))
      state["active"] = True
      state["phase"] = "grilling"
      state["round"] = max(1, prev_round + 1) if was_active else 1
      state["focus"] = _extract_focus(last_input)
      state["injectedRound"] = 0
      state["handoffRetries"] = 0
      _save_state(state_path, state)
    elif state.get("active") or state_path.is_file():
      _save_state(state_path, state)

  cur_round = int(state.get("round", 1))
  if (
      state.get("active")
      and state.get("phase") == "grilling"
      and int(state.get("injectedRound", 0)) != cur_round
  ):
    state["injectedRound"] = cur_round
    _save_state(state_path, state)
    focus = str(state.get("focus", "")).strip()
    focus_clause = f" (Focus: {focus})" if focus else ""
    msg = (
        f"[Auto GG Active — Round {cur_round}{focus_clause}] "
        "Follow `.agents/skills/auto-gg/SKILL.md`: "
        "1) Run `python3 .agents/skills/auto-gg/scripts/discover_signals.py` "
        "and inspect candidate files to discover the top concrete LAYERS Goal(s); "
        "2) Call `ask_question` to grill the user on Goal choice + 1-2 UX/scope "
        "forks (`(Recommended)` first); "
        "3) After answers arrive, execute & verify (`./scripts/verify_loop.sh` == 0), "
        f"commit to `main`, and call `enter_plan_mode` so Round {cur_round + 1} "
        "automatically discovers and grills the next goal."
    )
    return {
        "injectSteps": [
            {"systemMessage": {"systemMessage": msg}},
        ]
    }

  return {}


def _handle_post_tool(payload: dict) -> dict:
  state_path = _resolve_state_path(payload)
  state = _load_state(state_path)
  if not state.get("active"):
    return {}

  tool_call = payload.get("toolCall")
  if not isinstance(tool_call, dict):
    tool_call = {}
  name = str(tool_call.get("name", "")).lower()
  args = tool_call.get("args")
  if not isinstance(args, dict):
    args = {}
  err = str(payload.get("error", "")).strip()

  if name == "ask_question" or "questions" in args:
    if err:
      state["active"] = False
      state["phase"] = "idle"
    else:
      state["phase"] = "answered"
      state["handoffRetries"] = 0
    _save_state(state_path, state)
  elif name == "exit_plan_mode" or ("plan" in args and name != "enter_plan_mode"):
    state["phase"] = "building"
    state["handoffRetries"] = 0
    _save_state(state_path, state)
  elif name == "enter_plan_mode":
    if state.get("phase") in ("building", "answered"):
      state["round"] = int(state.get("round", 1)) + 1
      state["phase"] = "grilling"
      state["injectedRound"] = 0
      state["handoffRetries"] = 0
      _save_state(state_path, state)

  return {}


def _has_unverified_watched_dirty_code() -> bool:
  hooks_dir = Path(__file__).resolve().parent
  if str(hooks_dir) not in sys.path:
    sys.path.insert(0, str(hooks_dir))
  import stop_verify_gate  # type: ignore

  has_dirty, digest = stop_verify_gate.compute_code_state(stop_verify_gate.REPO_ROOT)
  if not has_dirty:
    return False
  vfile = stop_verify_gate.VERIFIED_HASH_FILE
  if not vfile.is_file():
    return True
  try:
    return vfile.read_text(encoding="utf-8").strip() != digest
  except OSError:
    return True


def _handle_stop(payload: dict) -> dict:
  if payload.get("terminationReason") != "NO_TOOL_CALL" or not payload.get(
      "fullyIdle", True
  ):
    return {"decision": "allow"}

  state_path = _resolve_state_path(payload)
  state = _load_state(state_path)
  if not state.get("active"):
    return {"decision": "allow"}

  if _has_unverified_watched_dirty_code():
    return {"decision": "allow"}

  if state.get("phase") in ("building", "answered") and int(
      state.get("handoffRetries", 0)
  ) < 1:
    next_round = int(state.get("round", 1)) + 1
    state["round"] = next_round
    state["phase"] = "grilling"
    state["injectedRound"] = 0
    state["handoffRetries"] = 1
    _save_state(state_path, state)
    return {
        "decision": "continue",
        "reason": (
            f"[Auto GG — Advance to Round {next_round}] Previous goal is verified! "
            "Call `enter_plan_mode` (if in execution mode) or run "
            "`python3 .agents/skills/auto-gg/scripts/discover_signals.py` and "
            f"call `ask_question` to launch Round {next_round}'s Goal + Grill."
        ),
    }

  return {"decision": "allow"}


def main() -> int:
  parser = argparse.ArgumentParser(description="Auto GG lifecycle hook")
  parser.add_argument(
      "--event",
      required=True,
      choices=("pre_invocation", "post_tool", "stop"),
  )
  args = parser.parse_args()

  fallback = {"decision": "allow"} if args.event == "stop" else {}
  raw = sys.stdin.read().strip()
  if not raw:
    print(json.dumps(fallback))
    return 0

  try:
    payload = json.loads(raw)
  except json.JSONDecodeError:
    print(json.dumps(fallback))
    return 0

  if not isinstance(payload, dict):
    print(json.dumps(fallback))
    return 0

  try:
    if args.event == "pre_invocation":
      out = _handle_pre_invocation(payload)
    elif args.event == "post_tool":
      out = _handle_post_tool(payload)
    else:
      out = _handle_stop(payload)
  except Exception:
    out = fallback

  print(json.dumps(out))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
