"""Unreal Engine ModelContextProtocol (`ToolsetRegistry`) exposure for LAYERS."""

from __future__ import annotations

import re
from typing import Any

from layers_project_probe import probe_uproject_context
from layers_sync_client import LayersSyncClient

try:
  import unreal as _unreal  # type: ignore

  _ToolsetBase = (
      getattr(_unreal, "ToolsetDefinition", None)
      or getattr(_unreal, "Toolset", None)
      or object
  )
except Exception:
  _unreal = None
  _ToolsetBase = object

_ACTIVE_TOOLSET: "LayersToolset | None" = None


def _normalize_key_token(raw: str) -> str:
  return re.sub(r"[^a-z0-9]+", "", str(raw or "").lower())


def _infer_tuning_type_tag(value: str, unit: str, target_engine: str) -> str:
  is_ue6 = str(target_engine or "").strip() == "ue6Verse"
  clean_val = str(value or "").strip().lower()
  clean_unit = str(unit or "").strip().lower()
  if clean_unit in ("bool", "boolean") or clean_val in ("true", "false"):
    return "logic" if is_ue6 else "bool"
  if clean_unit == "count" and re.fullmatch(r"-?\d+", clean_val):
    return "int" if is_ue6 else "int32"
  return "float"


def _format_mutation_receipt(
    summary: str,
    res: dict[str, Any],
    *,
    updated_tuning_key: str = "",
) -> str:
  """Builds a compact delta receipt for Unreal Assistant without re-echoing ROOT_MCP_CONTEXT."""
  active = res.get("activeEpic") or {}
  code = str(active.get("code") or "E01").strip() or "E01"
  title = str(active.get("title") or "Active Epic").strip()
  ver = str(active.get("releaseVersion") or res.get("releaseVersion") or "v0.1").strip()
  target_engine = str(res.get("targetEngine") or "ue5Mcp").strip()
  lines = [
      summary.strip(),
      f"# ACTIVE EPIC SPEC · {code} · {title} ({ver})",
  ]
  if updated_tuning_key:
    target_token = _normalize_key_token(updated_tuning_key)
    for item in active.get("tuning") or []:
      if not isinstance(item, dict):
        continue
      k = str(item.get("key") or "").strip()
      if _normalize_key_token(k) == target_token:
        val = str(item.get("value") or "0").strip()
        unit = str(item.get("unit") or "").strip()
        suffix = f" {unit}" if unit else ""
        prop_type = _infer_tuning_type_tag(val, unit, target_engine)
        lines.append(f"- {k}: {val}{suffix} [{prop_type}]")
  for idx, chk in enumerate(active.get("checks") or []):
    if not isinstance(chk, dict):
      continue
    tag = "[PASSED]" if chk.get("passed") else "[VERIFY]"
    lines.append(f"  {tag} Check {idx + 1}: {str(chk.get('text') or '').strip()}")
  open_fixes = [
      f for f in (active.get("openFixes") or [])
      if isinstance(f, dict) and str(f.get("text") or "").strip()
  ]
  if open_fixes:
    for fx in open_fixes:
      fx_id = str(fx.get("id") or "").strip()
      id_tag = f" (id: {fx_id})" if fx_id else ""
      lines.append(f"- [FIX] {str(fx.get('text') or '').strip()}{id_tag}")
    lines.append(f"### FOCUSED PIE REVISION PASS ({len(open_fixes)} OPEN [FIX])")
  else:
    lines.append("### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK")
  return "\n".join(lines).strip()


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
    return _format_mutation_receipt(
        (
            f"Logged PIE [FIX] on {active.get('code', '')} · {active.get('title', '')} "
            f"({open_count} open)."
        ),
        res,
    )

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
    return _format_mutation_receipt(
        f"Resolved PIE [FIX] on {active.get('code', '')} ({open_count} remaining).",
        res,
    )

  def layers_toggle_pie_check(
      self,
      check_id: str,
      passed: bool = True,
      epic_id: str = "",
  ) -> str:
    """Marks a `§06` PIE acceptance check passed or unverified on the Epic."""
    clean_id = str(check_id or "").strip()
    if not clean_id:
      return "LAYERS Error: check_id cannot be empty."
    res = self.sync_client.post_epic_update(
        "toggle_check",
        epic_id=epic_id,
        checkId=clean_id,
        passed=bool(passed),
    )
    if not res.get("ok"):
      return f"LAYERS Error: {res.get('error', 'Failed to toggle PIE check.')}"
    active = res.get("activeEpic") or {}
    checks = active.get("checks") or []
    passed_count = sum(1 for c in checks if c.get("passed"))
    return _format_mutation_receipt(
        (
            f"Updated PIE Check ({passed_count}/{len(checks)} passed) on "
            f"{active.get('code', '')} · {active.get('title', '')}."
        ),
        res,
    )

  def layers_update_epic_tuning(
      self,
      key: str,
      value: Any,
      unit: str = "",
      epic_id: str = "",
  ) -> str:
    """Updates or inserts a `§04` spatial/exposed tuning parameter on the Epic."""
    clean_key = "" if key is None else str(key).strip()
    clean_val = "" if value is None else str(value).strip()
    if not clean_key or clean_val == "":
      return "LAYERS Error: key and value cannot be empty."
    res = self.sync_client.post_epic_update(
        "update_tuning",
        epic_id=epic_id,
        key=clean_key,
        value=clean_val,
        unit=str(unit or "").strip(),
    )
    if not res.get("ok"):
      return f"LAYERS Error: {res.get('error', 'Failed to update Epic tuning.')}"
    active = res.get("activeEpic") or {}
    return _format_mutation_receipt(
        (
            f"Updated §04 Tuning `{clean_key}` = `{clean_val}` on "
            f"{active.get('code', '')} · {active.get('title', '')}."
        ),
        res,
        updated_tuning_key=clean_key,
    )

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

  def layers_reopen_epic(self, epic_id: str = "") -> str:
    """Reopens an Epic by document ID or code (e.g. `E01`) for fresh PIE verification."""
    res = self.sync_client.post_epic_update(
        "reopen_epic",
        epic_id=str(epic_id or "").strip(),
    )
    if not res.get("ok"):
      return f"LAYERS Error: {res.get('error', 'Failed to reopen Epic.')}"
    active = res.get("activeEpic") or {}
    md = str(res.get("mcpPayloadMarkdown") or "").strip()
    return (
        f"Reopened {active.get('code', '')} · {active.get('title', '')} for PIE verification.\n\n{md}"
    ).strip()


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


def layers_toggle_pie_check(
    check_id: str,
    passed: bool = True,
    epic_id: str = "",
) -> str:
  return get_registered_toolset().layers_toggle_pie_check(
      check_id,
      passed=passed,
      epic_id=epic_id,
  )


def layers_update_epic_tuning(
    key: str,
    value: Any,
    unit: str = "",
    epic_id: str = "",
) -> str:
  return get_registered_toolset().layers_update_epic_tuning(
      key,
      value,
      unit=unit,
      epic_id=epic_id,
  )


def layers_pass_active_epic(epic_id: str = "") -> str:
  return get_registered_toolset().layers_pass_active_epic(epic_id=epic_id)


def layers_reopen_epic(epic_id: str = "") -> str:
  return get_registered_toolset().layers_reopen_epic(epic_id=epic_id)
