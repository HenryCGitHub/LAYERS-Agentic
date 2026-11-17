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
          "LogLayersBridge: Registered LayersToolset (7 MCP tools) + Split Play-Toolbar UI."
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


def trigger_toolbar_primary_action() -> dict[str, object]:
  """Runs the `[ ⚡ Build E01 | ▾ ]` left toolbar button action cleanly."""
  return get_pie_dock().trigger_primary_toolbar_action()


def build_active_epic(
    agent_cli: str | None = None,
    background: bool = True,
) -> dict[str, object]:
  """Syncs .uproject + active Epic and launches the configured AI agent or clipboard handoff."""
  return get_pie_dock().build_active_epic(
      agent_cli=agent_cli,
      background=background,
  )


def sign_in_with_google(web_studio_url: str | None = None) -> dict[str, object]:
  """Starts browser loopback Google Sign-In handoff for this `.uproject`."""
  return get_pie_dock().start_browser_sign_in(web_studio_url=web_studio_url)


def sign_out_layers() -> str:
  """Unlinks this `.uproject` from its saved LAYERS Cloud Sync credential."""
  return get_pie_dock().sign_out_project()


bootstrap()
