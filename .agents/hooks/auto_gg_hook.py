#!/usr/bin/env python3
"""Antigravity lifecycle hook driving /auto-goal, /auto-grill & /auto-gg workflows."""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse
import json
import os
from pathlib import Path
import re

STOP_RE = re.compile(
    r"(?:^\s*(?:/stop|stop|pause|done|quit|cancel|exit)\s*[.!]?\s*$|"
    r"\b(?:stop|pause|exit|end|quit|disable)\s+(?:auto[\s_-]*(?:gg|goal|grill)|loop)\b)",
    re.IGNORECASE,
)
SLASH_TRIGGER_RE = re.compile(
    r"^\s*/auto[-_]?(gg|goal|grill)\b(.*)$",
    re.IGNORECASE | re.DOTALL,
)
BARE_TRIGGER_RE = re.compile(
    r"^\s*auto[\s_-]*(gg|goal|grill)\b(?:\s+([A-Za-z]+))?(.*)$",
    re.IGNORECASE | re.DOTALL,
)
ACTION_TRIGGER_RE = re.compile(
    r"\b(?:start|run|begin|launch|kick\s*off|resume|continue)\s+auto[\s_-]*(gg|goal|grill)\b(.*)$",
    re.IGNORECASE | re.DOTALL,
)
CONVERSATIONAL_FOLLOWERS = {
    "should",
    "would",
    "could",
    "can",
    "is",
    "was",
    "are",
    "were",
    "will",
    "might",
    "must",
    "need",
    "needs",
    "has",
    "have",
    "had",
    "does",
    "did",
    "do",
}
HYPOTHETICAL_PREFIX_RE = re.compile(
    r"(?:should\s+we|if\s+we|how\s+to|when\s+you|why|whether)\s+$",
    re.IGNORECASE,
)


def _default_state() -> dict:
  return {
      "active": False,
      "mode": "gg",
      "phase": "idle",
      "round": 0,
      "focus": "",
      "lastSeenInput": "",
      "injectedRound": 0,
      "grillRetries": 0,
      "planExitRetries": 0,
      "handoffRetries": 0,
  }


def _start_phase_for_mode(mode: str) -> str:
  if mode == "goal":
    return "discovering"
  if mode == "grill":
    return "grilling_ux"
  return "select_goal"


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


def _clean_focus(raw: str) -> str:
  return re.sub(r"^[\s:,-]+", "", raw).strip()


def _parse_start_trigger(text: str) -> tuple[str, str] | None:
  m_slash = SLASH_TRIGGER_RE.match(text)
  if m_slash:
    return m_slash.group(1).lower(), _clean_focus(m_slash.group(2))

  if text.rstrip().endswith("?"):
    return None

  m_bare = BARE_TRIGGER_RE.match(text)
  if m_bare:
    follower = (m_bare.group(2) or "").lower()
    if follower in CONVERSATIONAL_FOLLOWERS:
      return None
    tail = f"{m_bare.group(2) or ''} {m_bare.group(3) or ''}"
    return m_bare.group(1).lower(), _clean_focus(tail)

  m_action = ACTION_TRIGGER_RE.search(text)
  if m_action:
    prefix = text[: m_action.start()]
    if HYPOTHETICAL_PREFIX_RE.search(prefix):
      return None
    return m_action.group(1).lower(), _clean_focus(m_action.group(2))

  return None


def _build_pre_invocation_message(state: dict) -> str:
  mode = str(state.get("mode", "gg"))
  cur_round = int(state.get("round", 1))
  focus = str(state.get("focus", "")).strip()
  focus_clause = f" (Focus: {focus})" if focus else ""
  discover_arg = f" {focus}" if focus else ""

  if mode == "goal":
    return (
        f"[Auto-Goal Active — Round {cur_round}{focus_clause}] "
        "Follow `.agents/skills/auto-goal/SKILL.md`: "
        "1) Run `PYTHONDONTWRITEBYTECODE=1 python3 "
        f".agents/skills/auto-goal/scripts/discover_signals.py{discover_arg}` "
        "and inspect top candidate files; "
        "2) Auto-lock the #1 safest high-impact 3-part Goal Contract "
        "(call `ask_question` ONLY if a real UX fork exists); "
        "3) Execute `Red -> ./scripts/verify_loop.sh -> Commit` and call "
        f"`enter_plan_mode(reason='[round-complete] ...')` to launch Round {cur_round + 1}."
    )

  if mode == "grill":
    return (
        f"[Auto-Grill Active{focus_clause}] "
        "Follow `.agents/skills/auto-grill/SKILL.md`: "
        "1) Skip `discover_signals.py` and inspect affected files directly; "
        "2) Call `ask_question` with 1-3 genuine UX/scope forks (`(Recommended)` first, "
        "or skip if zero UX ambiguity); "
        "3) Lock the 3-part Goal Contract, run `./scripts/verify_loop.sh` == 0, and stop cleanly."
    )

  return (
      f"[Auto GG Active — Round {cur_round}{focus_clause}] "
      "Follow `.agents/skills/auto-gg/SKILL.md`: "
      "Step 1 (`select_goal`): Run `PYTHONDONTWRITEBYTECODE=1 python3 "
      f".agents/skills/auto-goal/scripts/discover_signals.py{discover_arg}` "
      "and call `ask_question` with ONLY 1 Goal Choice question (`(Recommended)` first); "
      "Step 2 (`grill_chosen`): apply `.agents/skills/auto-grill/SKILL.md` strictly to the "
      "chosen goal (skip `ask_question` if zero UX ambiguity); "
      "Step 3 & 4: execute `Red -> ./scripts/verify_loop.sh -> Commit` and call "
      f"`enter_plan_mode(reason='[round-complete] ...')` for Round {cur_round + 1}."
  )


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

    parsed = _parse_start_trigger(last_input)
    if parsed is not None:
      mode, focus = parsed
      was_same_active = bool(state.get("active", False)) and state.get("mode") == mode
      prev_round = int(state.get("round", 0))
      state["active"] = True
      state["mode"] = mode
      state["phase"] = _start_phase_for_mode(mode)
      state["round"] = max(1, prev_round + 1) if was_same_active else 1
      state["focus"] = focus
      state["injectedRound"] = 0
      state["grillRetries"] = 0
      state["planExitRetries"] = 0
      state["handoffRetries"] = 0
      _save_state(state_path, state)
    elif state.get("active") or state_path.is_file():
      _save_state(state_path, state)

  mode = str(state.get("mode", "gg"))
  cur_round = int(state.get("round", 1))
  if (
      state.get("active")
      and state.get("phase") == _start_phase_for_mode(mode)
      and int(state.get("injectedRound", 0)) != cur_round
  ):
    state["injectedRound"] = cur_round
    _save_state(state_path, state)
    msg = _build_pre_invocation_message(state)
    return {
        "injectSteps": [
            {"systemMessage": {"systemMessage": msg}},
        ]
    }

  return {}


def _has_unverified_watched_dirty_code() -> bool:
  override = os.environ.get("LAYERS_HOOK_FORCE_DIRTY", "").strip()
  if override == "1":
    return True
  if override == "0":
    return False

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


def _reset_retries(state: dict) -> None:
  state["grillRetries"] = 0
  state["planExitRetries"] = 0
  state["handoffRetries"] = 0


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

  mode = str(state.get("mode", "gg"))
  phase = str(state.get("phase", "idle"))

  if name == "ask_question" or "questions" in args:
    if err:
      state["active"] = False
      state["phase"] = "idle"
    elif mode == "gg" and phase == "select_goal":
      state["phase"] = "grill_chosen"
      _reset_retries(state)
    else:
      state["phase"] = "answered"
      _reset_retries(state)
    _save_state(state_path, state)
  elif name == "exit_plan_mode" or ("plan" in args and name != "enter_plan_mode"):
    state["phase"] = "building"
    _reset_retries(state)
    _save_state(state_path, state)
  elif name == "enter_plan_mode":
    reason = str(args.get("reason", ""))
    is_round_complete = "[round-complete]" in reason.lower()
    if not is_round_complete and _has_unverified_watched_dirty_code():
      state["phase"] = "reviewing"
      state["planExitRetries"] = 0
      _save_state(state_path, state)
    elif mode == "grill":
      if is_round_complete:
        state["active"] = False
        state["phase"] = "idle"
      else:
        state["phase"] = "answered"
        _reset_retries(state)
      _save_state(state_path, state)
    elif phase in ("building", "answered", "grill_chosen", "reviewing"):
      state["round"] = int(state.get("round", 1)) + 1
      state["phase"] = _start_phase_for_mode(mode)
      state["injectedRound"] = 0
      _reset_retries(state)
      _save_state(state_path, state)

  return {}


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

  mode = str(state.get("mode", "gg"))
  cur_round = int(state.get("round", 1))
  phase = str(state.get("phase", "idle"))

  if mode == "grill":
    if phase == "building":
      state["active"] = False
      state["phase"] = "idle"
      _save_state(state_path, state)
      return {"decision": "allow"}
    if phase == "grilling_ux" and int(state.get("grillRetries", 0)) < 1:
      state["grillRetries"] = 1
      _save_state(state_path, state)
      return {
          "decision": "continue",
          "reason": (
              "[Auto-Grill] Inspect affected files and call `ask_question` with "
              "1-3 genuine UX/scope forks (`(Recommended)` first), or call "
              "`exit_plan_mode` if zero UX ambiguity exists."
          ),
      }
    if phase in ("answered", "reviewing") and int(state.get("planExitRetries", 0)) < 1:
      state["planExitRetries"] = 1
      _save_state(state_path, state)
      return {
          "decision": "continue",
          "reason": (
              "[Auto-Grill] Call `exit_plan_mode` now to implement and verify "
              "the locked Goal Contract."
          ),
      }
    return {"decision": "allow"}

  if mode == "goal":
    if (
        phase in ("discovering", "answered", "reviewing")
        and int(state.get("planExitRetries", 0)) < 1
    ):
      state["planExitRetries"] = 1
      _save_state(state_path, state)
      return {
          "decision": "continue",
          "reason": (
              f"[Auto-Goal — Round {cur_round}] Lock the #1 safest Goal Contract "
              "and call `exit_plan_mode` (or `ask_question` only if a UX fork exists)."
          ),
      }
    if phase == "building" and int(state.get("handoffRetries", 0)) < 1:
      next_round = cur_round + 1
      state["round"] = next_round
      state["phase"] = "discovering"
      state["injectedRound"] = 0
      _reset_retries(state)
      state["handoffRetries"] = 1
      _save_state(state_path, state)
      return {
          "decision": "continue",
          "reason": (
              f"[Auto-Goal — Advance to Round {next_round}] Previous goal verified! "
              "Call `enter_plan_mode(reason='[round-complete] ...')` (if in execution mode) "
              f"or run `discover_signals.py` to launch Round {next_round}."
          ),
      }
    return {"decision": "allow"}

  # mode == "gg"
  if phase == "select_goal" and int(state.get("grillRetries", 0)) < 1:
    state["grillRetries"] = 1
    _save_state(state_path, state)
    return {
        "decision": "continue",
        "reason": (
            f"[Auto GG — Round {cur_round}] Call `ask_question` with ONLY 1 "
            f"Goal Choice question for Round {cur_round} (`(Recommended)` first)."
        ),
    }

  if (
      phase in ("grill_chosen", "answered", "reviewing")
      and int(state.get("planExitRetries", 0)) < 1
  ):
    state["planExitRetries"] = 1
    _save_state(state_path, state)
    return {
        "decision": "continue",
        "reason": (
            f"[Auto GG — Round {cur_round}] Grill the chosen goal via `ask_question` "
            "(if a genuine UX fork exists) or call `exit_plan_mode` now to build "
            f"Round {cur_round}."
        ),
    }

  if phase == "building" and int(state.get("handoffRetries", 0)) < 1:
    next_round = cur_round + 1
    state["round"] = next_round
    state["phase"] = "select_goal"
    state["injectedRound"] = 0
    _reset_retries(state)
    state["handoffRetries"] = 1
    _save_state(state_path, state)
    return {
        "decision": "continue",
        "reason": (
            f"[Auto GG — Advance to Round {next_round}] Previous goal is verified! "
            "Call `enter_plan_mode(reason='[round-complete] ...')` (if in execution mode) "
            f"or run `discover_signals.py` to start Round {next_round}'s Goal Choice."
        ),
    }

  return {"decision": "allow"}


def main() -> int:
  parser = argparse.ArgumentParser(description="Unified Auto-Goal / Auto-Grill / Auto GG hook")
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
