"""Pure-stdlib HTTP Cloud Sync client for LAYERS LayersBridge (.uplugin)."""

from __future__ import annotations

import json
import os
from pathlib import Path
import ssl
import threading
from typing import Any, Callable
import urllib.error
import urllib.request

DEFAULT_SYNC_BASE_URL = (
    "https://us-central1-layers-b8a16.cloudfunctions.net/geminiProxy"
)

_CANDIDATE_CA_PATHS = (
    "/etc/ssl/cert.pem",
    "/etc/ssl/certs/ca-certificates.crt",
    "/etc/pki/tls/certs/ca-bundle.crt",
    "/etc/ssl/ca-bundle.pem",
)


def _build_ssl_context() -> ssl.SSLContext:
  """Builds an SSLContext with certifi/OS CA bundle fallback for macOS & Linux UE Python."""
  ctx = ssl.create_default_context()
  paths = ssl.get_default_verify_paths()
  has_default_ca = bool(
      (paths.cafile and Path(paths.cafile).is_file())
      or (paths.capath and Path(paths.capath).is_dir())
  )
  if has_default_ca:
    return ctx

  try:
    import certifi  # type: ignore

    ca_bundle = str(certifi.where() or "").strip()
    if ca_bundle and Path(ca_bundle).is_file():
      ctx.load_verify_locations(cafile=ca_bundle)
      return ctx
  except Exception:
    pass

  for candidate in _CANDIDATE_CA_PATHS:
    if Path(candidate).is_file():
      try:
        ctx.load_verify_locations(cafile=candidate)
        return ctx
      except Exception:
        continue
  return ctx


_CACHED_SAVED_DIR: Path | None = None
_CACHED_UNREAL_ID: int | None = None


def _try_unreal_saved_dir() -> Path | None:
  global _CACHED_SAVED_DIR, _CACHED_UNREAL_ID
  if threading.current_thread() is not threading.main_thread():
    return _CACHED_SAVED_DIR
  try:
    import unreal  # type: ignore

    unreal_id = id(unreal)
    paths_cls = getattr(unreal, "Paths", None)
    if paths_cls and hasattr(paths_cls, "project_saved_dir"):
      raw = str(paths_cls.project_saved_dir() or "").strip()
      if raw:
        _CACHED_SAVED_DIR = Path(raw)
        _CACHED_UNREAL_ID = unreal_id
        return _CACHED_SAVED_DIR
    if _CACHED_UNREAL_ID != unreal_id:
      _CACHED_SAVED_DIR = None
      _CACHED_UNREAL_ID = unreal_id
  except Exception:
    pass
  return _CACHED_SAVED_DIR if threading.current_thread() is threading.main_thread() else None


def resolve_config_path(config_path: str | Path | None = None) -> Path:
  if config_path:
    return Path(config_path)
  env_path = os.environ.get("LAYERS_CONFIG_PATH", "").strip()
  if env_path:
    return Path(env_path)
  saved_dir = _try_unreal_saved_dir()
  if saved_dir is not None:
    return saved_dir / "Config" / "LayersBridge.json"
  return Path.cwd() / "Saved" / "Config" / "LayersBridge.json"


def load_bridge_config(
    config_path: str | Path | None = None,
) -> dict[str, str]:
  cfg: dict[str, str] = {
      "link_token": "",
      "sync_base_url": DEFAULT_SYNC_BASE_URL,
      "agent_cli": "auto",
  }
  target = resolve_config_path(config_path)
  if target.is_file():
    try:
      data = json.loads(target.read_text(encoding="utf-8"))
      if isinstance(data, dict):
        if data.get("link_token"):
          cfg["link_token"] = str(data["link_token"]).strip()
        if data.get("sync_base_url"):
          cfg["sync_base_url"] = (
              str(data["sync_base_url"]).strip().rstrip("/")
          )
        if data.get("agent_cli"):
          cfg["agent_cli"] = str(data["agent_cli"]).strip().lower() or "auto"
    except Exception:
      pass

  env_token = os.environ.get("LAYERS_LINK_TOKEN", "").strip()
  if env_token:
    cfg["link_token"] = env_token
  env_url = os.environ.get("LAYERS_SYNC_URL", "").strip()
  if env_url:
    cfg["sync_base_url"] = env_url.rstrip("/")
  env_agent = os.environ.get("LAYERS_AGENT_CLI", "").strip().lower()
  if env_agent:
    cfg["agent_cli"] = env_agent
  return cfg


def save_bridge_config(
    link_token: str,
    sync_base_url: str = DEFAULT_SYNC_BASE_URL,
    config_path: str | Path | None = None,
    agent_cli: str = "auto",
) -> Path:
  target = resolve_config_path(config_path)
  target.parent.mkdir(parents=True, exist_ok=True)
  payload = {
      "link_token": str(link_token or "").strip(),
      "sync_base_url": (
          str(sync_base_url or DEFAULT_SYNC_BASE_URL).strip().rstrip("/")
      ),
      "agent_cli": str(agent_cli or "auto").strip().lower() or "auto",
  }
  target.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
  return target


class LayersSyncClient:
  """Handles 2-way `/unrealLink/epic` and `/unrealLink/update` requests."""

  def __init__(
      self,
      link_token: str | None = None,
      sync_base_url: str | None = None,
      config_path: str | Path | None = None,
      timeout_seconds: float = 20.0,
      agent_cli: str | None = None,
      on_payload_changed: Callable[[], None] | None = None,
  ) -> None:
    self.config_path = config_path
    self.timeout_seconds = timeout_seconds
    self.last_payload: dict[str, Any] | None = None
    self._override_token = link_token
    self._override_url = sync_base_url
    self._override_agent_cli = agent_cli
    self.link_token = ""
    self.sync_base_url = DEFAULT_SYNC_BASE_URL
    self.agent_cli = "auto"
    self.on_payload_changed = on_payload_changed
    self.reload_config()

  def _notify_payload_changed(self) -> None:
    cb = self.on_payload_changed
    if cb is not None:
      try:
        cb()
      except Exception:
        pass

  def reload_config(self) -> dict[str, str]:
    prev_token = self.link_token
    prev_url = self.sync_base_url
    cfg = load_bridge_config(self.config_path)
    self.link_token = (
        str(self._override_token).strip()
        if self._override_token is not None
        else cfg["link_token"]
    )
    self.sync_base_url = (
        str(self._override_url).strip().rstrip("/")
        if self._override_url is not None
        else cfg["sync_base_url"]
    )
    self.agent_cli = (
        str(self._override_agent_cli).strip().lower() or "auto"
        if self._override_agent_cli is not None
        else cfg["agent_cli"]
    )
    if (self.link_token, self.sync_base_url) != (prev_token, prev_url):
      self.last_payload = None
      self._notify_payload_changed()
    return {
        "link_token": self.link_token,
        "sync_base_url": self.sync_base_url,
        "agent_cli": self.agent_cli,
    }

  def configure(
      self,
      link_token: str,
      sync_base_url: str | None = None,
      persist: bool = True,
      agent_cli: str | None = None,
  ) -> Path | None:
    prev_token = self.link_token
    prev_url = self.sync_base_url
    self._override_token = str(link_token or "").strip()
    self.link_token = self._override_token
    if sync_base_url is not None:
      cleaned_url = str(sync_base_url).strip().rstrip("/")
      self._override_url = cleaned_url or DEFAULT_SYNC_BASE_URL
      self.sync_base_url = self._override_url
    if agent_cli is not None:
      cleaned_agent = str(agent_cli).strip().lower() or "auto"
      self._override_agent_cli = cleaned_agent
      self.agent_cli = cleaned_agent
    if (self.link_token, self.sync_base_url) != (prev_token, prev_url):
      self.last_payload = None
      self._notify_payload_changed()
    if persist:
      return save_bridge_config(
          self.link_token,
          self.sync_base_url,
          config_path=self.config_path,
          agent_cli=self.agent_cli,
      )
    return None

  def _request_json(
      self,
      route: str,
      method: str = "GET",
      body: dict[str, Any] | None = None,
  ) -> dict[str, Any]:
    if not self.link_token:
      self.reload_config()
    if not self.link_token:
      return {
          "ok": False,
          "error": (
              "LayersBridge is not linked yet. Paste your `lyr_...` token "
              "from LAYERS Web Studio (`Connect Unreal MCP`)."
          ),
      }

    url = f"{self.sync_base_url.rstrip('/')}/{route.lstrip('/')}"
    headers = {
        "Authorization": f"Bearer {self.link_token}",
        "Accept": "application/json",
    }
    raw_body: bytes | None = None
    if body is not None:
      headers["Content-Type"] = "application/json"
      raw_body = json.dumps(body).encode("utf-8")

    req = urllib.request.Request(
        url=url,
        data=raw_body,
        headers=headers,
        method=method.upper(),
    )
    ssl_ctx = _build_ssl_context() if url.lower().startswith("https://") else None
    try:
      with urllib.request.urlopen(
          req,
          timeout=self.timeout_seconds,
          context=ssl_ctx,
      ) as resp:
        text = resp.read().decode("utf-8", errors="replace")
        parsed = json.loads(text) if text.strip() else {}
        if isinstance(parsed, dict):
          if parsed.get("ok"):
            self.last_payload = parsed
            self._notify_payload_changed()
          return parsed
        return {"ok": False, "error": "Unexpected non-object Cloud response."}
    except urllib.error.HTTPError as exc:
      err_body = exc.read().decode("utf-8", errors="replace")
      message = f"HTTP {exc.code}"
      try:
        parsed_err = json.loads(err_body)
        if isinstance(parsed_err, dict):
          err_obj = parsed_err.get("error")
          if isinstance(err_obj, dict) and err_obj.get("message"):
            message = f"HTTP {exc.code}: {err_obj['message']}"
      except Exception:
        if err_body.strip():
          message = f"HTTP {exc.code}: {err_body.strip()[:240]}"
      return {"ok": False, "error": message}
    except Exception as exc:
      return {"ok": False, "error": f"LayersBridge network error: {exc}"}

  def fetch_active_epic(
      self,
      uproject_context: dict[str, Any] | None = None,
  ) -> dict[str, Any]:
    if uproject_context is not None:
      return self._request_json(
          "/unrealLink/epic",
          method="POST",
          body={"uprojectContext": uproject_context},
      )
    return self._request_json("/unrealLink/epic", method="GET")

  def post_epic_update(
      self,
      action: str,
      epic_id: str = "",
      **fields: Any,
  ) -> dict[str, Any]:
    target_epic_id = str(epic_id or "").strip()
    payload: dict[str, Any] = {"action": action}
    if target_epic_id:
      payload["epicId"] = target_epic_id
    for key, val in fields.items():
      if val is not None:
        payload[key] = val
    return self._request_json("/unrealLink/update", method="POST", body=payload)
