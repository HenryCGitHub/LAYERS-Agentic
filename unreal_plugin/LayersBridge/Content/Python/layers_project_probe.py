"""Live `.uproject` metadata probe for Unreal Engine Editor sessions."""

from __future__ import annotations

import os
from pathlib import Path
import threading
import time
from typing import Any

_MAX_ASSET_SCAN = 2500
_MAX_VERSE_FILE_SCAN = 1000
_PROBE_CACHE_TTL_SEC = 2.0
_SKIP_CONTENT_DIRS = {
    "__ExternalActors__",
    "__ExternalObjects__",
    "Collections",
    "Developers",
}

_RECENT_PIE_ERRORS: list[str] = []
_LAST_MAIN_THREAD_CONTEXT: dict[str, Any] | None = None
_LAST_PROBE_TS: float = 0.0
_LAST_UNREAL_MOD_ID: int | None = None


def invalidate_uproject_context_cache() -> None:
  global _LAST_MAIN_THREAD_CONTEXT, _LAST_PROBE_TS, _LAST_UNREAL_MOD_ID
  _LAST_MAIN_THREAD_CONTEXT = None
  _LAST_PROBE_TS = 0.0
  _LAST_UNREAL_MOD_ID = None


def _empty_context() -> dict[str, Any]:
  return {
      "project_name": "",
      "current_level": "",
      "game_mode": "",
      "default_pawn": "",
      "input_assets": [],
      "blueprint_assets": [],
      "data_assets": [],
      "widget_assets": [],
      "level_assets": [],
      "verse_files": [],
      "recent_errors": list(_RECENT_PIE_ERRORS[-6:]),
  }


def _clone_context(src: dict[str, Any]) -> dict[str, Any]:
  return {
      "project_name": str(src.get("project_name", "")),
      "current_level": str(src.get("current_level", "")),
      "game_mode": str(src.get("game_mode", "")),
      "default_pawn": str(src.get("default_pawn", "")),
      "input_assets": list(src.get("input_assets", [])),
      "blueprint_assets": list(src.get("blueprint_assets", [])),
      "data_assets": list(src.get("data_assets", [])),
      "widget_assets": list(src.get("widget_assets", [])),
      "level_assets": list(src.get("level_assets", [])),
      "verse_files": list(src.get("verse_files", [])),
      "recent_errors": list(_RECENT_PIE_ERRORS[-6:]),
  }


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


def probe_uproject_context(
    *,
    force_refresh: bool = False,
    max_age_seconds: float = _PROBE_CACHE_TTL_SEC,
) -> dict[str, Any]:
  """Inspects running Unreal Editor state without modifying project assets."""
  global _LAST_MAIN_THREAD_CONTEXT, _LAST_PROBE_TS, _LAST_UNREAL_MOD_ID
  context = _empty_context()

  if threading.current_thread() is not threading.main_thread():
    if _LAST_MAIN_THREAD_CONTEXT is not None:
      return _clone_context(_LAST_MAIN_THREAD_CONTEXT)
    return context

  try:
    import unreal  # type: ignore
  except Exception:
    return context

  if (
      not force_refresh
      and _LAST_MAIN_THREAD_CONTEXT is not None
      and _LAST_UNREAL_MOD_ID == id(unreal)
      and (time.monotonic() - _LAST_PROBE_TS) < max(0.0, float(max_age_seconds))
  ):
    return _clone_context(_LAST_MAIN_THREAD_CONTEXT)

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

  # 4. Bounded `/Game` Asset Categorization (Input, Widgets, DataAssets, Levels, Blueprints)
  reg_helpers = getattr(unreal, "AssetRegistryHelpers", None)
  if reg_helpers and hasattr(reg_helpers, "get_asset_registry"):
    registry = _safe_call(reg_helpers.get_asset_registry, None)
    if registry and hasattr(registry, "get_assets_by_path"):
      assets = _safe_call(
          lambda: registry.get_assets_by_path("/Game", recursive=True), []
      )
      found_inputs: list[str] = []
      found_blueprints: list[str] = []
      found_data: list[str] = []
      found_widgets: list[str] = []
      found_levels: list[str] = []
      seen: set[str] = set()

      for idx, asset in enumerate(assets or []):
        if idx >= _MAX_ASSET_SCAN:
          break
        if (
            len(found_inputs) >= 12
            and len(found_widgets) >= 8
            and len(found_data) >= 8
            and len(found_levels) >= 6
            and len(found_blueprints) >= 12
        ):
          break

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
        label = pkg or asset_name
        if not label or label in seen:
          continue

        is_input = (
            "InputAction" in cls_name
            or "InputMappingContext" in cls_name
            or asset_name.startswith("IA_")
            or asset_name.startswith("IMC_")
        )
        is_widget = (
            "WidgetBlueprint" in cls_name
            or "UserWidget" in cls_name
            or asset_name.startswith("WBP_")
            or asset_name.startswith("UMG_")
        )
        is_data = (
            "DataAsset" in cls_name
            or "PrimaryDataAsset" in cls_name
            or "DataTable" in cls_name
            or asset_name.startswith("DA_")
            or asset_name.startswith("DT_")
        )
        is_level = (
            cls_name in ("World", "Level")
            or "World" in cls_name
            or asset_name.startswith(("L_", "LVL_", "Map_"))
        )
        is_blueprint = "Blueprint" in cls_name or asset_name.startswith(
            ("BP_", "GM_", "GS_", "PC_", "PS_", "AIC_", "BPI_", "AC_")
        )

        if is_input and len(found_inputs) < 12:
          seen.add(label)
          found_inputs.append(label)
        elif is_widget and len(found_widgets) < 8:
          seen.add(label)
          found_widgets.append(label)
        elif is_data and len(found_data) < 8:
          seen.add(label)
          found_data.append(label)
        elif is_level and len(found_levels) < 6:
          seen.add(label)
          found_levels.append(label)
        elif is_blueprint and len(found_blueprints) < 12:
          seen.add(label)
          found_blueprints.append(label)

      context["input_assets"] = found_inputs
      context["blueprint_assets"] = found_blueprints
      context["data_assets"] = found_data
      context["widget_assets"] = found_widgets
      context["level_assets"] = found_levels

  # 5. Existing `.verse` scripts under Content/ (pruning OFPA folders)
  paths_cls = getattr(unreal, "Paths", None)
  if paths_cls and hasattr(paths_cls, "project_content_dir"):
    raw_content_dir = str(
        _safe_call(paths_cls.project_content_dir, "") or ""
    ).strip()
    if raw_content_dir:
      content_root = Path(raw_content_dir)
      if content_root.is_dir():
        found_verse: list[str] = []
        scanned_files = 0
        for root, dirs, files in os.walk(content_root):
          dirs[:] = sorted(
              d for d in dirs if not d.startswith(".") and d not in _SKIP_CONTENT_DIRS
          )
          for fname in sorted(files):
            scanned_files += 1
            if scanned_files > _MAX_VERSE_FILE_SCAN or len(found_verse) >= 8:
              dirs[:] = []
              break
            if fname.endswith(".verse"):
              rel_posix = (Path(root) / fname).relative_to(content_root).as_posix()
              found_verse.append(f"Content/{rel_posix}")
          if scanned_files > _MAX_VERSE_FILE_SCAN or len(found_verse) >= 8:
            break
        context["verse_files"] = found_verse

  _LAST_MAIN_THREAD_CONTEXT = _clone_context(context)
  _LAST_PROBE_TS = time.monotonic()
  _LAST_UNREAL_MOD_ID = id(unreal)
  return _clone_context(context)
