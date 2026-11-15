"""Unreal Engine ModelContextProtocol (`ToolsetRegistry`) exposure for LAYERS."""

from __future__ import annotations

from typing import Any

from layers_project_probe import probe_uproject_context
from layers_sync_client import LayersSyncClient

try:
  import unreal as _unreal  # type: ignore

  _ToolsetBase = getattr(_unreal, "Toolset", object)
except Exception:
  _unreal = None
  _ToolsetBase = object

_ACTIVE_TOOLSET: "LayersToolset | None" = None


class LayersToolset(_ToolsetBase):  # type: ignore[misc]
  """Registers LAYERS Spec & PIE Acceptance Gate tools inside Unreal MCP."""

  toolset_name = "layers"

  def __init__(self, sync_client: LayersSyncClient | None = None) -> None:
    try:
      super().__init__()
    except Exception:
      pass
    self.sync_client = sync_client or LayersSyncClient()

  def layers_get_active_epic_spec(self) -> str:
    """Returns canonical `ROOT_MCP_CONTEXT` + Active Epic Spec + live `.uproject` snapshot."""
    uproj = probe_uproject_context()
    res = self.sync_client.fetch_active_epic(uproject_context=uproj)
    if not res.get("ok"):
      return f"LAYERS Error: {res.get('error', 'Failed to fetch active Epic spec.')}"
    markdown = str(res.get("mcpPayloadMarkdown") or "").strip()
    if markdown:
      return markdown
    active_epic = res.get("activeEpic") or {}
    return (
        f"# ACTIVE EPIC SPEC · {active_epic.get('code', 'E00')} · "
        f"{active_epic.get('title', 'No Active Epic')}"
    )

  def layers_log_pie_fix(self, fix_text: str, epic_id: str = "") -> str:
    """Appends a new unresolved PIE `[FIX]` item on the active Epic."""
    clean = str(fix_text or "").strip()
    if not clean:
      return "LAYERS Error: fix_text cannot be empty."
    uproj = probe_uproject_context()
    res = self.sync_client.post_epic_update(
        "log_fix",
        epic_id=epic_id,
        fixText=clean,
        uprojectContext=uproj,
    )
    if not res.get("ok"):
      return f"LAYERS Error: {res.get('error', 'Failed to log PIE fix.')}"
    active = res.get("activeEpic") or {}
    open_count = int(active.get("openFixesCount", 0) or 0)
    md = str(res.get("mcpPayloadMarkdown") or "").strip()
    return (
        f"Logged PIE [FIX] on {active.get('code', '')} · {active.get('title', '')} "
        f"({open_count} open).\n\n{md}"
    ).strip()

  def layers_resolve_pie_fix(self, fix_id: str, epic_id: str = "") -> str:
    """Marks a PIE `[FIX]` resolved on the active Epic."""
    res = self.sync_client.post_epic_update(
        "resolve_fix",
        epic_id=epic_id,
        fixId=str(fix_id or "latest").strip(),
    )
    if not res.get("ok"):
      return f"LAYERS Error: {res.get('error', 'Failed to resolve PIE fix.')}"
    active = res.get("activeEpic") or {}
    open_count = int(active.get("openFixesCount", 0) or 0)
    md = str(res.get("mcpPayloadMarkdown") or "").strip()
    return (
        f"Resolved PIE [FIX] on {active.get('code', '')} ({open_count} remaining).\n\n{md}"
    ).strip()

  def layers_pass_active_epic(self, epic_id: str = "") -> str:
    """Signs off all checks/fixes on the active Epic and advances to the next Epic."""
    res = self.sync_client.post_epic_update("pass_epic", epic_id=epic_id)
    if not res.get("ok"):
      return f"LAYERS Error: {res.get('error', 'Failed to pass Epic.')}"
    if res.get("allEpicsCompleted"):
      return (
          f"Release {res.get('releaseVersion', '')} complete! "
          "All Epics passed PIE acceptance gate. Plan the next release in LAYERS Web Studio."
      )
    nxt = res.get("activeEpic") or {}
    return (
        f"Passed! Advanced to Epic {res.get('epicPosition', 0)}/{res.get('totalEpics', 0)}: "
        f"{nxt.get('code', '')} · {nxt.get('title', '')}"
    )


def register_layers_toolset(
    sync_client: LayersSyncClient | None = None,
) -> LayersToolset:
  global _ACTIVE_TOOLSET
  toolset = LayersToolset(sync_client=sync_client)
  _ACTIVE_TOOLSET = toolset

  if _unreal is not None:
    registry_cls = getattr(_unreal, "ToolsetRegistry", None)
    if registry_cls is not None:
      registry = (
          registry_cls.get()
          if hasattr(registry_cls, "get")
          else registry_cls
      )
      for method_name in (
          "register_toolset",
          "add_toolset",
          "register",
      ):
        fn = getattr(registry, method_name, None)
        if callable(fn):
          try:
            fn(toolset)
          except TypeError:
            try:
              fn("layers", toolset)
            except Exception:
              pass
          break
  return toolset


def get_registered_toolset() -> LayersToolset:
  global _ACTIVE_TOOLSET
  if _ACTIVE_TOOLSET is None:
    _ACTIVE_TOOLSET = LayersToolset()
  return _ACTIVE_TOOLSET


def layers_get_active_epic_spec() -> str:
  return get_registered_toolset().layers_get_active_epic_spec()


def layers_log_pie_fix(fix_text: str, epic_id: str = "") -> str:
  return get_registered_toolset().layers_log_pie_fix(fix_text, epic_id=epic_id)


def layers_resolve_pie_fix(fix_id: str, epic_id: str = "") -> str:
  return get_registered_toolset().layers_resolve_pie_fix(fix_id, epic_id=epic_id)


def layers_pass_active_epic(epic_id: str = "") -> str:
  return get_registered_toolset().layers_pass_active_epic(epic_id=epic_id)
