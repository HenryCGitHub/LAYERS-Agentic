"""In-editor Unreal Split Play-Toolbar UI (`[ ⚡ Build E01 | E01 · 1/3 ✓ ▾ ]`) & PIE Gate controller."""

from __future__ import annotations

from collections import deque
import json
import shutil
import subprocess
import sys
import threading
from typing import Any, Callable
import webbrowser

from layers_project_probe import (
    clear_pie_errors,
    invalidate_uproject_context_cache,
    probe_uproject_context,
)
from layers_sync_client import LayersSyncClient

_MAIN_THREAD_QUEUE: deque[Callable[[], None]] = deque()
_QUEUE_LOCK = threading.Lock()
_SLATE_TICK_HANDLE: Any = None
_SLATE_TICK_UNREAL_ID: int | None = None


def drain_main_thread_tasks(max_tasks: int = 64) -> int:
  """Drains queued UI/log callables safely on Unreal's Slate main thread."""
  if threading.current_thread() is not threading.main_thread():
    return 0
  ran = 0
  while ran < max_tasks:
    with _QUEUE_LOCK:
      if not _MAIN_THREAD_QUEUE:
        break
      fn = _MAIN_THREAD_QUEUE.popleft()
    ran += 1
    try:
      fn()
    except Exception:
      pass
  return ran


def ensure_slate_tick_registered() -> bool:
  """Registers a single Slate post-tick callback to flush queued game-thread work."""
  global _SLATE_TICK_HANDLE, _SLATE_TICK_UNREAL_ID
  if threading.current_thread() is not threading.main_thread():
    return False
  try:
    import unreal  # type: ignore

    unreal_id = id(unreal)
    if _SLATE_TICK_HANDLE is not None and _SLATE_TICK_UNREAL_ID == unreal_id:
      return True
    reg_fn = getattr(unreal, "register_slate_post_tick_callback", None)
    if callable(reg_fn):
      _SLATE_TICK_HANDLE = reg_fn(lambda _dt: drain_main_thread_tasks())
      _SLATE_TICK_UNREAL_ID = unreal_id
      return _SLATE_TICK_HANDLE is not None
  except Exception:
    pass
  return False


def run_on_game_thread(fn: Callable[[], Any]) -> bool:
  """Executes `fn` immediately on the main thread, or queues it for the next Slate tick."""
  if threading.current_thread() is threading.main_thread():
    ensure_slate_tick_registered()
    fn()
    return True
  with _QUEUE_LOCK:
    _MAIN_THREAD_QUEUE.append(fn)
  return False


def _copy_to_os_clipboard(text: str) -> bool:
  """Copies prompt text to OS clipboard cleanly on macOS, Windows, and Linux."""
  commands: list[list[str]] = []
  if sys.platform == "darwin":
    commands.append(["pbcopy"])
  elif sys.platform.startswith("win"):
    commands.append(["clip"])
  else:
    commands.extend([
        ["wl-copy"],
        ["xclip", "-selection", "clipboard"],
        ["xsel", "--clipboard", "--input"],
    ])
  for cmd in commands:
    if shutil.which(cmd[0]) is None:
      continue
    try:
      subprocess.run(
          cmd,
          input=text,
          text=True,
          encoding="utf-8",
          timeout=3,
          check=True,
          creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
      )
      return True
    except Exception:
      continue
  return False


def _unreal_log(message: str) -> None:
  def _emit() -> None:
    try:
      import unreal  # type: ignore

      log_fn = getattr(unreal, "log", None)
      if callable(log_fn):
        log_fn(message)
    except Exception:
      pass

  run_on_game_thread(_emit)


class LayersPieGateDock:
  """Split Play-Toolbar + active-Epic PIE playtest controller inside Unreal Editor."""

  def __init__(self, sync_client: LayersSyncClient | None = None) -> None:
    self.sync_client = sync_client or LayersSyncClient()
    if self.sync_client.on_payload_changed is None:
      self.sync_client.on_payload_changed = lambda: refresh_toolbar_widgets(self)
    self.last_status_message: str = ""
    self.is_building: bool = False
    self.build_logs: list[str] = []
    self.cli_runner: Callable[[list[str], str], tuple[int, str]] | None = None
    self._active_build_thread: threading.Thread | None = None
    ensure_slate_tick_registered()

  @property
  def last_payload(self) -> dict[str, Any] | None:
    return self.sync_client.last_payload

  def _record_build_log(self, line: str) -> None:
    clean = str(line or "").rstrip()
    if not clean:
      return
    self.build_logs.append(clean)
    if len(self.build_logs) > 80:
      del self.build_logs[:-80]
    _unreal_log(f"LogLayersBridge: {clean}")

  def configure_token(
      self,
      link_token: str,
      sync_base_url: str | None = None,
      agent_cli: str | None = None,
  ) -> str:
    prev_token = str(self.sync_client.link_token or "").strip()
    path = self.sync_client.configure(
        link_token=link_token,
        sync_base_url=sync_base_url,
        agent_cli=agent_cli,
        persist=True,
    )
    if str(self.sync_client.link_token or "").strip() != prev_token:
      clear_pie_errors()
      invalidate_uproject_context_cache(clear_fallback=True)
    self.last_status_message = f"Saved LayersBridge token config -> {path}"
    refresh_toolbar_widgets(self)
    return self.last_status_message

  def compute_primary_toolbar_action(self) -> dict[str, str]:
    """Computes label, mode, and tooltip for the left half of `[ ⚡ Build E01 | ▾ ]`."""
    if not str(self.sync_client.link_token or "").strip():
      return {
          "mode": "unlinked",
          "label": "⚡ Link LAYERS",
          "tooltip": (
              "Set your lyr_... Sync Token via "
              "init_unreal.get_pie_dock().configure_token(\"lyr_...\")"
          ),
      }
    if self.is_building:
      active = (self.last_payload or {}).get("activeEpic") or {}
      code = str(active.get("code") or "Epic").strip() or "Epic"
      return {
          "mode": "building",
          "label": f"⏳ Building {code}…",
          "tooltip": "AI agent is synthesizing this Epic via Unreal MCP (:8000).",
      }
    payload = self.last_payload
    if not payload or not payload.get("ok"):
      return {
          "mode": "build",
          "label": "⚡ Sync & Build",
          "tooltip": "Sync active LAYERS Epic and dispatch Unreal MCP build.",
      }
    if payload.get("allEpicsCompleted"):
      return {
          "mode": "complete",
          "label": "✓ Release Complete",
          "tooltip": "All Epics passed PIE gate! Open LAYERS Web Studio for next release.",
      }
    active = payload.get("activeEpic") or {}
    code = str(active.get("code") or "E01").strip() or "E01"
    title = str(active.get("title") or "").strip()
    fixes = active.get("openFixes") or []
    checks = active.get("checks") or []
    all_checks_passed = bool(checks) and all(bool(c.get("passed")) for c in checks)
    if fixes:
      return {
          "mode": "fix",
          "label": f"🔧 Fix {code} ({len(fixes)})",
          "tooltip": f"Dispatch Focused PIE Revision Pass for {len(fixes)} open [FIX] on {code}.",
      }
    if all_checks_passed:
      return {
          "mode": "pass",
          "label": f"✓ Pass {code} →",
          "tooltip": f"All {len(checks)} PIE checks passed! Click to pass {code} & advance.",
      }
    return {
        "mode": "build",
        "label": f"⚡ Build {code}",
        "tooltip": f"Trigger Unreal MCP build for {code} · {title}.",
    }

  def compute_gate_combo_label(self) -> str:
    """Computes label for the right caret half of `[ ⚡ Build E01 | E01 · 1/3 ✓ ▾ ]`."""
    if not str(self.sync_client.link_token or "").strip():
      return "LAYERS · Unlinked"
    payload = self.last_payload
    if not payload or not payload.get("ok"):
      return "LAYERS Gate"
    if payload.get("allEpicsCompleted"):
      return "✓ All Passed"
    active = payload.get("activeEpic") or {}
    code = str(active.get("code") or "E01").strip() or "E01"
    checks = active.get("checks") or []
    passed = sum(1 for c in checks if c.get("passed"))
    fixes = active.get("openFixes") or []
    base = f"{code} · {passed}/{len(checks)} ✓"
    return f"{base} · {len(fixes)} FIX" if fixes else base

  def build_agent_prompt(self) -> str:
    payload = self.last_payload or {}
    active = payload.get("activeEpic") or {}
    code = str(active.get("code") or "E01").strip() or "E01"
    title = str(active.get("title") or "Active Epic").strip()
    ver = str(active.get("releaseVersion") or payload.get("releaseVersion") or "v0.1").strip() or "v0.1"
    target_engine = str(payload.get("targetEngine") or "ue5Mcp").strip()
    arch_label = (
        "UE6 Verse"
        if target_engine == "ue6Verse"
        else "UE 5.9 Blueprint + DataAsset"
    )
    level_staging = str(active.get("levelStaging") or "").strip()
    level_clause = f"Target Test Level: {level_staging}. " if level_staging else ""
    fixes = active.get("openFixes") or []
    if fixes:
      formatted_fixes: list[str] = []
      for f in fixes:
        if not isinstance(f, dict):
          continue
        txt = str(f.get("text") or "").strip()
        if not txt:
          continue
        fid = str(f.get("id") or "").strip()
        formatted_fixes.append(f"{txt} (id: {fid})" if fid else txt)
      fix_list = "; ".join(formatted_fixes)
      return (
          f"In Unreal MCP (http://127.0.0.1:8000/mcp), call "
          f"layers_get_active_epic_spec right now and execute the "
          f"FOCUSED PIE REVISION PASS for {code} ({title}, {ver}, {arch_label}). "
          f"{level_clause}"
          f"Open [FIX] items: {fix_list}. Apply targeted fixes, verify in PIE, "
          f"and report via layers_resolve_pie_fix and layers_toggle_pie_check. "
          f"Do not call layers_pass_active_epic (leave final sign-off for human PIE review)."
      )
    return (
        f"In Unreal MCP (http://127.0.0.1:8000/mcp), call "
        f"layers_get_active_epic_spec right now and execute the "
        f"FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK for {code} ({title}, {ver}, {arch_label}). "
        f"{level_clause}"
        f"Implement §01-§06 matching ROOT_MCP_CONTEXT, expose all §04 tuning variables, "
        f"and report PIE verification via layers_toggle_pie_check. "
        f"Do not call layers_pass_active_epic (leave final sign-off for human PIE review)."
    )

  def _start_unreal_mcp_server_if_available(self) -> None:
    def _start() -> None:
      try:
        import unreal  # type: ignore

        sys_lib = getattr(unreal, "SystemLibrary", None)
        exec_fn = getattr(sys_lib, "execute_console_command", None) if sys_lib else None
        if callable(exec_fn):
          world = None
          ed_lib = getattr(unreal, "EditorLevelLibrary", None)
          if ed_lib and hasattr(ed_lib, "get_editor_world"):
            world = ed_lib.get_editor_world()
          exec_fn(world, "ModelContextProtocol.StartServer")
      except Exception:
        pass

    run_on_game_thread(_start)

  def _resolve_cli_command(
      self,
      prompt: str,
      preferred: str | None = None,
  ) -> tuple[str, list[str]] | None:
    mode = (preferred or self.sync_client.agent_cli or "auto").strip().lower()
    if mode in ("clipboard", "assistant", "none"):
      return None

    builders: dict[str, Callable[[str], list[str]]] = {
        "claude": lambda exe: [exe, "-p", prompt],
        "codex": lambda exe: [exe, "exec", prompt],
        "gemini": lambda exe: [exe, "-p", prompt],
    }
    candidates = list(builders.keys()) if mode == "auto" else [mode]
    if self.cli_runner is not None:
      for name in candidates:
        if name in builders:
          return name, builders[name](name)
    for name in candidates:
      if name not in builders:
        continue
      resolved = shutil.which(name)
      if resolved:
        return name, builders[name](resolved)
    return None

  def build_active_epic(
      self,
      agent_cli: str | None = None,
      background: bool = True,
  ) -> dict[str, Any]:
    """Syncs active Epic + .uproject context and dispatches Unreal MCP build/fix."""
    if self.is_building:
      return {
          "ok": True,
          "mode": "building",
          "message": "Build already in progress.",
          "logs": list(self.build_logs[-10:]),
      }
    self._start_unreal_mcp_server_if_available()
    res = self.sync_now()
    if not res.get("ok"):
      return res
    if res.get("allEpicsCompleted"):
      return {
          "ok": True,
          "mode": "complete",
          "message": "All Epics passed PIE acceptance gate.",
      }

    prompt = self.build_agent_prompt()
    resolved = self._resolve_cli_command(prompt, preferred=agent_cli)
    if resolved is None:
      copied = _copy_to_os_clipboard(prompt)
      self.last_status_message = (
          "Build prompt copied to clipboard — paste (Cmd/Ctrl+V) in Unreal Assistant."
          if copied
          else "Build prompt ready in Output Log — paste into Unreal Assistant."
      )
      self._record_build_log(self.last_status_message)
      self._record_build_log(f"Prompt: {prompt}")
      refresh_toolbar_widgets(self)
      return {
          "ok": True,
          "mode": "clipboard_handoff",
          "copied": copied,
          "prompt": prompt,
      }

    agent_name, cmd = resolved

    def _run_worker() -> None:
      self.is_building = True
      self._record_build_log(f"Dispatching {agent_name} against http://127.0.0.1:8000/mcp...")
      refresh_toolbar_widgets(self)
      try:
        if self.cli_runner is not None:
          code, output = self.cli_runner(cmd, prompt)
        else:
          proc = subprocess.run(
              cmd,
              stdin=subprocess.DEVNULL,
              capture_output=True,
              text=True,
              encoding="utf-8",
              errors="replace",
              timeout=600,
              creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
          )
          code = proc.returncode
          output = (proc.stdout or "") + (f"\n{proc.stderr}" if proc.stderr else "")
        for line in str(output or "").splitlines()[:20]:
          self._record_build_log(line)
        self.last_status_message = f"{agent_name} exited with status {code}."
      except Exception as exc:
        self.last_status_message = f"{agent_name} dispatch error: {exc}"
        self._record_build_log(self.last_status_message)
      finally:
        self.is_building = False
        ctx = probe_uproject_context(force_refresh=True)
        self.sync_client.fetch_active_epic(uproject_context=ctx)
        if threading.current_thread() is not threading.main_thread():
          run_on_game_thread(invalidate_uproject_context_cache)
        refresh_toolbar_widgets(self)

    if background:
      self.is_building = True
      refresh_toolbar_widgets(self)
      worker = threading.Thread(target=_run_worker, daemon=True)
      self._active_build_thread = worker
      worker.start()
    else:
      self._active_build_thread = None
      _run_worker()

    return {
        "ok": True,
        "mode": "cli_agent",
        "agent": agent_name,
        "prompt": prompt,
    }

  def trigger_primary_toolbar_action(self) -> dict[str, Any]:
    """Executes the left button of `[ ⚡ Build E01 | ▾ ]` based on current gate state."""
    action = self.compute_primary_toolbar_action()
    mode = action["mode"]
    if mode == "unlinked":
      _unreal_log(f"LogLayersBridge: {action['tooltip']}")
      self.open_web_studio()
      return {"ok": False, "mode": "unlinked", "error": action["tooltip"]}
    if mode == "building":
      _unreal_log("LogLayersBridge: Build in progress...")
      return {"ok": True, "mode": "building", "logs": list(self.build_logs[-10:])}
    if mode == "complete":
      url = self.open_web_studio()
      return {"ok": True, "mode": "complete", "webStudioUrl": url}
    if mode == "pass":
      res = self.pass_epic()
      return {"ok": bool(res.get("ok")), "mode": "passed", "result": res}
    return self.build_active_epic()

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
    refresh_toolbar_widgets(self)
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

  def toggle_check(
      self,
      check_id: str,
      passed: bool | None = None,
      epic_id: str = "",
  ) -> dict[str, Any]:
    clean_id = str(check_id or "").strip()
    if not clean_id:
      return {"ok": False, "error": "check_id cannot be empty."}
    kwargs: dict[str, Any] = {"checkId": clean_id}
    if passed is not None:
      kwargs["passed"] = bool(passed)
    res = self.sync_client.post_epic_update(
        "toggle_check",
        epic_id=epic_id,
        **kwargs,
    )
    refresh_toolbar_widgets(self)
    return res

  def flag_fix(self, fix_text: str, epic_id: str = "") -> dict[str, Any]:
    clean = str(fix_text or "").strip()
    if not clean:
      return {"ok": False, "error": "fix_text cannot be empty."}
    ctx = probe_uproject_context()
    res = self.sync_client.post_epic_update(
        "log_fix",
        epic_id=epic_id,
        fixText=clean,
        uprojectContext=ctx,
    )
    refresh_toolbar_widgets(self)
    return res

  def resolve_fix(self, fix_id: str, epic_id: str = "") -> dict[str, Any]:
    res = self.sync_client.post_epic_update(
        "resolve_fix",
        epic_id=epic_id,
        fixId=str(fix_id or "latest").strip(),
    )
    refresh_toolbar_widgets(self)
    return res

  def update_tuning(
      self,
      key: str,
      value: Any,
      unit: str = "",
      epic_id: str = "",
  ) -> dict[str, Any]:
    clean_key = "" if key is None else str(key).strip()
    clean_val = "" if value is None else str(value).strip()
    if not clean_key or clean_val == "":
      return {"ok": False, "error": "key and value cannot be empty."}
    res = self.sync_client.post_epic_update(
        "update_tuning",
        epic_id=epic_id,
        key=clean_key,
        value=clean_val,
        unit=str(unit or "").strip(),
    )
    refresh_toolbar_widgets(self)
    return res

  def pass_epic(self, epic_id: str = "") -> dict[str, Any]:
    res = self.sync_client.post_epic_update("pass_epic", epic_id=epic_id)
    if res.get("ok"):
      clear_pie_errors()
      invalidate_uproject_context_cache()
    refresh_toolbar_widgets(self)
    return res

  def reopen_epic(self, epic_id: str = "") -> dict[str, Any]:
    res = self.sync_client.post_epic_update(
        "reopen_epic",
        epic_id=str(epic_id or "").strip(),
    )
    refresh_toolbar_widgets(self)
    return res

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
    done_tag = " [ALL EPICS PASSED ✓]" if payload.get("allEpicsCompleted") else ""
    lines = [
        f"LAYERS PIE Gate · {payload.get('releaseVersion', '')} · "
        f"Epic {payload.get('epicPosition', 0)}/{payload.get('totalEpics', 0)}{done_tag}",
        f"{active.get('code', 'E00')} · {active.get('title', 'Epic')} "
        f"({passed}/{len(checks)} Checks, {len(fixes)} Open [FIX])",
    ]
    beat = str(active.get("coreLoopBeat") or "").strip()
    if beat:
      lines.append(f"Core Loop Beat: {beat}")
    lines.extend([
        f"Goal: {active.get('goal', '')}",
        f"Web Studio: {payload.get('webStudioUrl', '')}",
    ])
    for delta in active.get("upgradeDeltas") or []:
      clean_delta = str(delta or "").strip().lstrip("+").strip()
      if clean_delta:
        lines.append(f"  +{clean_delta}")
    for chk in checks:
      mark = "[x]" if chk.get("passed") else "[ ]"
      lines.append(f"  {mark} {chk.get('text', '')}")
    for fx in fixes:
      lines.append(f"  [FIX] {fx.get('text', '')}")
    return "\n".join(lines)


def _make_tool_menu_entry(
    unreal_mod: Any,
    *,
    name: str,
    block_type_attr: str,
    label: str,
    tooltip: str,
    py_command: str,
) -> Any | None:
  entry_cls = getattr(unreal_mod, "ToolMenuEntry", None)
  if entry_cls is None:
    return None
  block_enum = getattr(unreal_mod, "MultiBlockType", None)
  block_type = getattr(block_enum, block_type_attr, block_type_attr)
  entry = entry_cls(name=name, type=block_type)
  if hasattr(entry, "set_label"):
    entry.set_label(label)
  if hasattr(entry, "set_tool_tip"):
    entry.set_tool_tip(tooltip)
  if hasattr(entry, "set_string_command"):
    try:
      cmd_enum = getattr(unreal_mod, "ToolMenuStringCommandType", None)
      entry.set_string_command(
          type=getattr(cmd_enum, "PYTHON", "PYTHON"),
          custom_type="",
          string=py_command,
      )
    except Exception:
      pass
  return entry


def _add_entry_safe(menu: Any, section_name: str, entry: Any) -> None:
  if menu is None or entry is None:
    return
  if hasattr(menu, "find_or_add_section"):
    try:
      section = menu.find_or_add_section(section_name)
      if hasattr(section, "add_entry"):
        section.add_entry(entry)
        return
    except Exception:
      pass
  if hasattr(menu, "add_menu_entry"):
    try:
      menu.add_menu_entry(section_name, entry)
    except TypeError:
      menu.add_menu_entry(entry)


def refresh_toolbar_widgets(dock: LayersPieGateDock) -> bool:
  """Refreshes the `[ ⚡ Build E01 | E01 · 1/3 ✓ ▾ ]` Split Play-Toolbar pair."""
  if threading.current_thread() is not threading.main_thread():
    run_on_game_thread(lambda: refresh_toolbar_widgets(dock))
    return True
  ensure_slate_tick_registered()
  try:
    import unreal  # type: ignore

    tool_menus_cls = getattr(unreal, "ToolMenus", None)
    if tool_menus_cls is None or not hasattr(tool_menus_cls, "get"):
      return False
    menus = tool_menus_cls.get()
    if menus is None:
      return False

    toolbar_name = "LevelEditor.LevelEditorToolBar.PlayToolBar"
    toolbar = (
        menus.extend_menu(toolbar_name)
        if hasattr(menus, "extend_menu")
        else menus.find_menu(toolbar_name)
    )
    if toolbar is None:
      toolbar_name = "LevelEditor.LevelEditorToolBar.User"
      toolbar = (
          menus.extend_menu(toolbar_name)
          if hasattr(menus, "extend_menu")
          else menus.find_menu(toolbar_name)
      )
    if toolbar is None:
      return False

    primary = dock.compute_primary_toolbar_action()
    combo_label = dock.compute_gate_combo_label()

    primary_entry = _make_tool_menu_entry(
        unreal,
        name="LayersPrimaryAction",
        block_type_attr="TOOL_BAR_BUTTON",
        label=primary["label"],
        tooltip=primary["tooltip"],
        py_command="import init_unreal; init_unreal.trigger_toolbar_primary_action()",
    )
    combo_entry = _make_tool_menu_entry(
        unreal,
        name="LayersPieGateCombo",
        block_type_attr="TOOL_BAR_COMBO_BUTTON",
        label=combo_label,
        tooltip="Open LAYERS PIE Checks, [FIX] Queue, Tuning & Token Menu",
        py_command="import init_unreal; init_unreal.open_pie_gate_log()",
    )
    _add_entry_safe(toolbar, "LayersBridge", primary_entry)
    _add_entry_safe(toolbar, "LayersBridge", combo_entry)

    # Populate native ToolMenus submenu with dynamic PIE checks & quick actions
    if hasattr(menus, "register_menu"):
      submenu_name = f"{toolbar_name}.LayersPieGateCombo"
      if hasattr(menus, "remove_menu"):
        try:
          menus.remove_menu(submenu_name)
        except Exception:
          pass
      submenu = menus.register_menu(submenu_name)
      if submenu is not None:
        if hasattr(submenu, "entries") and isinstance(submenu.entries, dict):
          submenu.entries.clear()
        _add_entry_safe(
            submenu,
            "Actions",
            _make_tool_menu_entry(
                unreal,
                name="LayersMenuBuild",
                block_type_attr="MENU_ENTRY",
                label=primary["label"],
                tooltip=primary["tooltip"],
                py_command="import init_unreal; init_unreal.trigger_toolbar_primary_action()",
            ),
        )
        _add_entry_safe(
            submenu,
            "Actions",
            _make_tool_menu_entry(
                unreal,
                name="LayersMenuPlayPie",
                block_type_attr="MENU_ENTRY",
                label="▶ Launch PIE",
                tooltip="Start Unreal Play-In-Editor session cleanly",
                py_command="import init_unreal; init_unreal.get_pie_dock().launch_pie()",
            ),
        )

        payload = dock.last_payload
        if payload and payload.get("ok") and not payload.get("allEpicsCompleted"):
          active = payload.get("activeEpic") or {}
          code = str(active.get("code") or "E01").strip() or "E01"
          checks = active.get("checks") or []
          for idx, chk in enumerate(checks):
            chk_id = str(chk.get("id") or (idx + 1))
            chk_text = str(chk.get("text") or "").strip()[:64]
            mark = "x" if chk.get("passed") else " "
            _add_entry_safe(
                submenu,
                "PieChecks",
                _make_tool_menu_entry(
                    unreal,
                    name=f"LayersCheck_{idx + 1}",
                    block_type_attr="MENU_ENTRY",
                    label=f"[{mark}] Check {idx + 1}: {chk_text}",
                    tooltip=f"Toggle §06 PIE Check {idx + 1} on {code}",
                    py_command=(
                        "import init_unreal; "
                        f"init_unreal.get_pie_dock().toggle_check({json.dumps(chk_id)})"
                    ),
                ),
            )
          _add_entry_safe(
              submenu,
              "Actions",
              _make_tool_menu_entry(
                  unreal,
                  name="LayersMenuPass",
                  block_type_attr="MENU_ENTRY",
                  label=f"✓ Pass {code} & Advance →",
                  tooltip=f"Mark {code} passed & advance to next Epic",
                  py_command="import init_unreal; init_unreal.get_pie_dock().pass_epic()",
              ),
          )

        _add_entry_safe(
            submenu,
            "Actions",
            _make_tool_menu_entry(
                unreal,
                name="LayersMenuSync",
                block_type_attr="MENU_ENTRY",
                label="↻ Sync .uproject & Pull Active Epic",
                tooltip="Push live .uproject snapshot and pull latest LAYERS Epic",
                py_command="import init_unreal; init_unreal.open_pie_gate_log()",
            ),
        )
        _add_entry_safe(
            submenu,
            "Actions",
            _make_tool_menu_entry(
                unreal,
                name="LayersMenuWeb",
                block_type_attr="MENU_ENTRY",
                label="↗ Open LAYERS Web Studio",
                tooltip="Open LAYERS Web Studio in your browser",
                py_command="import init_unreal; init_unreal.get_pie_dock().open_web_studio()",
            ),
        )

    if hasattr(menus, "refresh_all_widgets"):
      menus.refresh_all_widgets()
    return True
  except Exception:
    return False


def register_pie_gate_menu(dock: LayersPieGateDock) -> bool:
  """Registers Split Play-Toolbar pair + `Window -> LAYERS PIE Gate` inside Unreal ToolMenus."""
  registered_toolbar = refresh_toolbar_widgets(dock)
  try:
    import unreal  # type: ignore

    tool_menus_cls = getattr(unreal, "ToolMenus", None)
    if tool_menus_cls is None or not hasattr(tool_menus_cls, "get"):
      return registered_toolbar
    menus = tool_menus_cls.get()
    if menus is None:
      return registered_toolbar
    menu = menus.find_menu("LevelEditor.MainMenu.Window")
    if menu is None:
      return registered_toolbar

    entry = _make_tool_menu_entry(
        unreal,
        name="LayersPieGate",
        block_type_attr="MENU_ENTRY",
        label="LAYERS PIE Gate",
        tooltip="Sync Active LAYERS Epic Spec & PIE Acceptance Gate",
        py_command="import init_unreal; init_unreal.open_pie_gate_log()",
    )
    _add_entry_safe(menu, "WindowLayout", entry)
    if hasattr(menus, "refresh_all_widgets"):
      menus.refresh_all_widgets()
    return True
  except Exception:
    return registered_toolbar
