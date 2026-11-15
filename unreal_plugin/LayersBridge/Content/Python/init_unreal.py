"""Unreal Engine PythonScriptPlugin startup entrypoint for `LayersBridge`."""

from __future__ import annotations

from layers_pie_dock import LayersPieGateDock, register_pie_gate_menu
from layers_sync_client import LayersSyncClient
from layers_toolset import LayersToolset, register_layers_toolset

_SYNC_CLIENT: LayersSyncClient | None = None
_TOOLSET: LayersToolset | None = None
_PIE_DOCK: LayersPieGateDock | None = None


def bootstrap() -> tuple[LayersSyncClient, LayersToolset, LayersPieGateDock]:
  global _SYNC_CLIENT, _TOOLSET, _PIE_DOCK
  _SYNC_CLIENT = LayersSyncClient()
  _TOOLSET = register_layers_toolset(sync_client=_SYNC_CLIENT)
  _PIE_DOCK = LayersPieGateDock(sync_client=_SYNC_CLIENT)
  register_pie_gate_menu(_PIE_DOCK)
  try:
    import unreal  # type: ignore

    log_fn = getattr(unreal, "log", None)
    if callable(log_fn):
      log_fn(
          "LogLayersBridge: Registered LayersToolset (4 MCP tools) + LAYERS PIE Gate."
      )
  except Exception:
    pass
  return _SYNC_CLIENT, _TOOLSET, _PIE_DOCK


def get_sync_client() -> LayersSyncClient:
  if _SYNC_CLIENT is None:
    bootstrap()
  assert _SYNC_CLIENT is not None
  return _SYNC_CLIENT


def get_toolset() -> LayersToolset:
  if _TOOLSET is None:
    bootstrap()
  assert _TOOLSET is not None
  return _TOOLSET


def get_pie_dock() -> LayersPieGateDock:
  if _PIE_DOCK is None:
    bootstrap()
  assert _PIE_DOCK is not None
  return _PIE_DOCK


def open_pie_gate_log() -> str:
  dock = get_pie_dock()
  dock.sync_now()
  summary = dock.render_dock_summary_text()
  try:
    import unreal  # type: ignore

    log_fn = getattr(unreal, "log", None)
    if callable(log_fn):
      log_fn(summary)
  except Exception:
    pass
  return summary


bootstrap()
