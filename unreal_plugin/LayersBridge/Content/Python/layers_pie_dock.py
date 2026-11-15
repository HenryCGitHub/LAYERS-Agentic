"""Slim in-editor Unreal PIE Sign-Off Dock & `Window -> LAYERS PIE Gate` menu."""

from __future__ import annotations

from typing import Any
import webbrowser

from layers_project_probe import probe_uproject_context
from layers_sync_client import DEFAULT_SYNC_BASE_URL, LayersSyncClient


class LayersPieGateDock:
  """Single active-Epic PIE playtest sign-off controller inside Unreal Editor."""

  def __init__(self, sync_client: LayersSyncClient | None = None) -> None:
    self.sync_client = sync_client or LayersSyncClient()
    self.last_status_message: str = ""

  @property
  def last_payload(self) -> dict[str, Any] | None:
    return self.sync_client.last_payload

  def configure_token(
      self,
      link_token: str,
      sync_base_url: str = DEFAULT_SYNC_BASE_URL,
  ) -> str:
    path = self.sync_client.configure(
        link_token=link_token,
        sync_base_url=sync_base_url,
        persist=True,
    )
    self.last_status_message = f"Saved LayersBridge token config -> {path}"
    return self.last_status_message

  def sync_now(self) -> dict[str, Any]:
    ctx = probe_uproject_context()
    res = self.sync_client.fetch_active_epic(uproject_context=ctx)
    if res.get("ok"):
      active = res.get("activeEpic") or {}
      self.last_status_message = (
          f"Synced {active.get('code', 'E00')} · {active.get('title', '')} "
          f"({res.get('releaseVersion', '')})"
      )
    else:
      self.last_status_message = str(res.get("error") or "Sync failed.")
    return res

  def launch_pie(self) -> bool:
    try:
      import unreal  # type: ignore

      get_sub = getattr(unreal, "get_editor_subsystem", None)
      level_sub_cls = getattr(unreal, "LevelEditorSubsystem", None)
      if callable(get_sub) and level_sub_cls is not None:
        sub = get_sub(level_sub_cls)
        if sub and hasattr(sub, "editor_request_begin_play"):
          sub.editor_request_begin_play()
          self.last_status_message = "Started Unreal PIE session."
          return True
    except Exception as exc:
      self.last_status_message = f"PIE launch failed: {exc}"
    return False

  def toggle_check(self, check_id: str, passed: bool | None = None) -> dict[str, Any]:
    kwargs: dict[str, Any] = {"checkId": check_id}
    if passed is not None:
      kwargs["passed"] = bool(passed)
    return self.sync_client.post_epic_update("toggle_check", **kwargs)

  def flag_fix(self, fix_text: str) -> dict[str, Any]:
    return self.sync_client.post_epic_update(
        "log_fix",
        fixText=str(fix_text or "").strip(),
    )

  def resolve_fix(self, fix_id: str) -> dict[str, Any]:
    return self.sync_client.post_epic_update(
        "resolve_fix",
        fixId=str(fix_id or "latest").strip(),
    )

  def pass_epic(self) -> dict[str, Any]:
    return self.sync_client.post_epic_update("pass_epic")

  def open_web_studio(self) -> str:
    url = str(
        (self.last_payload or {}).get("webStudioUrl")
        or "https://henrycgithub.github.io/LAYERS-Agentic/"
    ).strip()
    try:
      webbrowser.open(url)
    except Exception:
      pass
    return url

  def render_dock_summary_text(self) -> str:
    payload = self.last_payload
    if not payload or not payload.get("ok"):
      return self.last_status_message or "LAYERS PIE Gate: Not synced yet."
    active = payload.get("activeEpic") or {}
    checks = active.get("checks") or []
    passed = sum(1 for c in checks if c.get("passed"))
    fixes = active.get("openFixes") or []
    lines = [
        f"LAYERS PIE Gate · {payload.get('releaseVersion', '')} · "
        f"Epic {payload.get('epicPosition', 0)}/{payload.get('totalEpics', 0)}",
        f"{active.get('code', 'E00')} · {active.get('title', 'Epic')} "
        f"({passed}/{len(checks)} Checks, {len(fixes)} Open [FIX])",
        f"Goal: {active.get('goal', '')}",
        f"Web Studio: {payload.get('webStudioUrl', '')}",
    ]
    for chk in checks:
      mark = "[x]" if chk.get("passed") else "[ ]"
      lines.append(f"  {mark} {chk.get('text', '')}")
    for fx in fixes:
      lines.append(f"  [FIX] {fx.get('text', '')}")
    return "\n".join(lines)


def register_pie_gate_menu(dock: LayersPieGateDock) -> bool:
  """Adds `Window -> LAYERS PIE Gate` entry into Unreal's ToolMenus."""
  try:
    import unreal  # type: ignore

    tool_menus_cls = getattr(unreal, "ToolMenus", None)
    if tool_menus_cls is None or not hasattr(tool_menus_cls, "get"):
      return False
    menus = tool_menus_cls.get()
    if menus is None:
      return False
    menu = menus.find_menu("LevelEditor.MainMenu.Window")
    if menu is None:
      return False

    entry_cls = getattr(unreal, "ToolMenuEntry", None)
    if entry_cls is not None:
      entry = entry_cls(
          name="LayersPieGate",
          type=getattr(
              getattr(unreal, "MultiBlockType", None),
              "MENU_ENTRY",
              "MENU_ENTRY",
          ),
      )
      if hasattr(entry, "set_label"):
        entry.set_label("LAYERS PIE Gate")
      if hasattr(entry, "set_tool_tip"):
        entry.set_tool_tip(
            "Sync Active LAYERS Epic Spec & PIE Acceptance Gate"
        )
      if hasattr(entry, "set_string_command"):
        try:
          entry.set_string_command(
              type=getattr(
                  getattr(unreal, "ToolMenuStringCommandType", None),
                  "PYTHON",
                  "PYTHON",
              ),
              custom_type="",
              string="import init_unreal; init_unreal.open_pie_gate_log()",
          )
        except Exception:
          pass
      if hasattr(menu, "add_menu_entry"):
        try:
          menu.add_menu_entry("WindowLayout", entry)
        except TypeError:
          menu.add_menu_entry(entry)
    if hasattr(menus, "refresh_all_widgets"):
      menus.refresh_all_widgets()
    return True
  except Exception:
    return False
