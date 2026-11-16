"""Live `.uproject` metadata probe for Unreal Engine Editor sessions."""

from __future__ import annotations

from pathlib import Path
import threading
from typing import Any

_RECENT_PIE_ERRORS: list[str] = []
_LAST_MAIN_THREAD_CONTEXT: dict[str, Any] | None = None


def record_pie_error(message: str) -> None:
  clean = str(message or "").strip()
  if not clean:
    return
  _RECENT_PIE_ERRORS.append(clean)
  if len(_RECENT_PIE_ERRORS) > 12:
    del _RECENT_PIE_ERRORS[:-12]


def clear_pie_errors() -> None:
  _RECENT_PIE_ERRORS.clear()


def _safe_call(fn, default=None):
  try:
    return fn()
  except Exception:
    return default


def _read_prop(obj: Any, attr_name: str, fallback: str = "") -> str:
  if obj is None:
    return fallback
  val = getattr(obj, attr_name, None)
  if val is None and hasattr(obj, "get_editor_property"):
    val = _safe_call(lambda: obj.get_editor_property(attr_name), None)
  if callable(val):
    val = _safe_call(val, None)
  if val is None:
    return fallback
  if hasattr(val, "get_name"):
    name = _safe_call(val.get_name, None)
    if name:
      return str(name)
  return str(val).strip() or fallback


def probe_uproject_context() -> dict[str, Any]:
  """Inspects running Unreal Editor state without modifying project assets."""
  global _LAST_MAIN_THREAD_CONTEXT
  context: dict[str, Any] = {
      "project_name": "",
      "current_level": "",
      "game_mode": "",
      "default_pawn": "",
      "input_assets": [],
      "recent_errors": list(_RECENT_PIE_ERRORS[-6:]),
  }

  if threading.current_thread() is not threading.main_thread():
    if _LAST_MAIN_THREAD_CONTEXT is not None:
      return {
          **_LAST_MAIN_THREAD_CONTEXT,
          "input_assets": list(_LAST_MAIN_THREAD_CONTEXT.get("input_assets", [])),
          "recent_errors": list(_RECENT_PIE_ERRORS[-6:]),
      }
    return context

  try:
    import unreal  # type: ignore
  except Exception:
    return context

  # 1. Project Name
  sys_lib = getattr(unreal, "SystemLibrary", None)
  if sys_lib and hasattr(sys_lib, "get_game_name"):
    context["project_name"] = str(_safe_call(sys_lib.get_game_name, "") or "")
  if not context["project_name"]:
    paths_cls = getattr(unreal, "Paths", None)
    if paths_cls and hasattr(paths_cls, "get_project_file_path"):
      uproj = str(_safe_call(paths_cls.get_project_file_path, "") or "")
      if uproj:
        context["project_name"] = Path(uproj).stem

  # 2. Current Open Level
  level_name = ""
  get_sub = getattr(unreal, "get_editor_subsystem", None)
  level_sub_cls = getattr(unreal, "LevelEditorSubsystem", None)
  if callable(get_sub) and level_sub_cls is not None:
    level_sub = _safe_call(lambda: get_sub(level_sub_cls), None)
    if level_sub and hasattr(level_sub, "get_current_level"):
      lvl = _safe_call(level_sub.get_current_level, None)
      level_name = _read_prop(lvl, "get_outer", "") or _read_prop(lvl, "name", "")
  if not level_name:
    ed_lib = getattr(unreal, "EditorLevelLibrary", None)
    if ed_lib and hasattr(ed_lib, "get_editor_world"):
      world = _safe_call(ed_lib.get_editor_world, None)
      if world and hasattr(world, "get_name"):
        level_name = str(_safe_call(world.get_name, "") or "")
  context["current_level"] = level_name

  # 3. GameMode & DefaultPawnClass
  gm_settings_cls = getattr(unreal, "GameMapsSettings", None)
  if gm_settings_cls:
    gm_settings = (
        _safe_call(gm_settings_cls.get_game_maps_settings, None)
        if hasattr(gm_settings_cls, "get_game_maps_settings")
        else None
    )
    if gm_settings is not None:
      context["game_mode"] = _read_prop(
          gm_settings, "global_default_game_mode", ""
      )
      context["default_pawn"] = _read_prop(gm_settings, "default_pawn_class", "")

  # 4. Existing Enhanced Input Assets (`IMC_*` / `IA_*`) under `/Game`
  reg_helpers = getattr(unreal, "AssetRegistryHelpers", None)
  if reg_helpers and hasattr(reg_helpers, "get_asset_registry"):
    registry = _safe_call(reg_helpers.get_asset_registry, None)
    if registry and hasattr(registry, "get_assets_by_path"):
      assets = _safe_call(
          lambda: registry.get_assets_by_path("/Game", recursive=True), []
      )
      found_inputs: list[str] = []
      seen: set[str] = set()
      for asset in assets or []:
        pkg = str(
            getattr(asset, "package_name", "")
            or getattr(asset, "object_path", "")
            or ""
        ).strip()
        asset_name = str(getattr(asset, "asset_name", "") or "").strip()
        cls_path = getattr(asset, "asset_class_path", None)
        cls_name = str(
            getattr(cls_path, "asset_name", "")
            or getattr(asset, "asset_class", "")
            or ""
        ).strip()
        is_input = (
            "InputAction" in cls_name
            or "InputMappingContext" in cls_name
            or asset_name.startswith("IA_")
            or asset_name.startswith("IMC_")
        )
        label = pkg or asset_name
        if is_input and label and label not in seen:
          seen.add(label)
          found_inputs.append(label)
          if len(found_inputs) >= 16:
            break
      context["input_assets"] = found_inputs

  _LAST_MAIN_THREAD_CONTEXT = {
      **context,
      "input_assets": list(context["input_assets"]),
      "recent_errors": list(context["recent_errors"]),
  }
  return context
