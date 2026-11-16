#!/usr/bin/env python3
"""Smoke test verifying pure-Python `LayersBridge` + Cloud Functions Unreal MCP bridge."""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import types
import urllib.request

REPO_ROOT = Path(__file__).resolve().parents[1]
PLUGIN_ROOT = REPO_ROOT / "unreal_plugin" / "LayersBridge"
PYTHON_DIR = PLUGIN_ROOT / "Content" / "Python"

TEST_TOKEN = "lyr_smoke_test_token_0123456789abcdef"

NODE_HARNESS_JS = r"""
const http = require("http");
const helpers = require("./functions/index.js")._testHelpers;

const expectedHash = helpers.hashLinkToken(process.env.SMOKE_TOKEN);
const docsById = new Map();

const rootSpec = {
  sparkPrompt: "3D crab shooter on destructible sand castle beaches",
  gameTitle: "SHELLBREAKER",
  targetEngine: "ue5Mcp",
  pitch: "Pilot an armored hermit crab clearing tidepool waves across modular sand fortresses.",
  coreLoop: [
    "Skitter & Aim -> position around cover",
    "Shell Blast -> shatter enemy armor",
    "Grab Pearls -> upgrade shell cannons"
  ],
  cameraContract: "SpringArm 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLag 9.0",
  characterScale: "ACharacter CapsuleRadius 42 cm · HalfHeight 92 cm · MaxWalkSpeed 620 cm/s",
  inputContract: "Enhanced Input (IMC_Core + IA_Move / IA_Aim / IA_Primary)",
  assetPolicy: "Prototype Greybox Primitives (Engine/BasicShapes) + Debug Materials",
  feelChoiceId: "heavy",
  pillars: ["Readable Chaos: Clear telegraph colors before explosions"],
  tradeOffs: [{ prefer: "Snappy arcade grip", avoid: "Sluggish crab drift" }],
  outOfScope: ["No multiplayer matchmaking in v0.1"]
};

function makeEpicDoc(id, code, title, lifecycle, goal, checks) {
  const spec = {
    id,
    code,
    lineageKey: code.toLowerCase(),
    title,
    releaseVersion: "v0.1",
    lifecycle,
    goal,
    links: ["BP_CrabPlayer -> IMC_Core"],
    outOfScope: ["No water caustics shader in v0.1"],
    controls: [
      { action: "IA_Move", trigger: "Triggered (Hold)", rule: "Planar XZ velocity clamped to MaxWalkSpeed" },
      { action: "IA_Dash", trigger: "Started (Press)", rule: "Burst 1400 cm/s for 0.18 s on cooldown" }
    ],
    states: ["Idle <-> Moving -> Dashing"],
    interrupts: ["HitReaction cancels Dash cleanly"],
    tuning: [
      { key: "MaxWalkSpeed", value: "620", unit: "cm/s" },
      { key: "DashDistance", value: "420", unit: "cm" }
    ],
    feedback: ["Niagara sand burst at crab feet on dash"],
    levelStaging: "L_Arena_Proto -> Spawn BP_CrabPlayer + 2 BP_TargetDummy actors",
    checks,
    fixes: [],
    baselineSummary: [],
    upgradeDeltas: [],
    copilotUpgrades: []
  };
  return {
    id,
    title,
    tier: "epic",
    parentId: "rel_v01",
    isCompleted: lifecycle === "stable",
    subtasks: checks.map((c) => ({ id: c.id, text: c.text, completed: c.passed })),
    sections: {
      code,
      lineage_key: code.toLowerCase(),
      release_version: "v0.1",
      lifecycle,
      goal,
      epic_spec_json: JSON.stringify(spec),
    },
  };
}

docsById.set("proj_smoke", {
  id: "proj_smoke",
  title: "SHELLBREAKER",
  tier: "project",
  childrenIds: ["rel_v01"],
  sections: {
    concept_blueprint_json: JSON.stringify(rootSpec),
    active_release_id: "rel_v01",
    selected_epic_id: "epic_01",
  },
});

docsById.set("rel_v01", {
  id: "rel_v01",
  title: "v0.1 · Prototype",
  tier: "release",
  parentId: "proj_smoke",
  childrenIds: ["epic_01", "epic_02"],
  sections: { release_version: "v0.1" },
});

docsById.set(
  "epic_01",
  makeEpicDoc(
    "epic_01",
    "E01",
    "Crab Locomotion & Dash",
    "active",
    "Crisp 8-way planar crab run, cursor aim rotation, and i-frame dash burst.",
    [
      { id: "chk_1", text: "IA_Move steers crab cleanly across L_Arena_Proto", passed: false },
      { id: "chk_2", text: "IA_Dash lunges 420 cm without clipping walls", passed: false }
    ]
  )
);

docsById.set(
  "epic_02",
  makeEpicDoc(
    "epic_02",
    "E02",
    "Claw Blaster & Hitstop",
    "queued",
    "Projectile pellet volley with destructible sand pillar hitstop feedback.",
    [
      { id: "chk_2_1", text: "IA_Primary spawns pellets at 1800 cm/s toward cursor ray", passed: false }
    ]
  )
);

const server = http.createServer((req, res) => {
  const auth = String(req.headers.authorization || "");
  const rawToken = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (helpers.hashLinkToken(rawToken) !== expectedHash) {
    res.writeHead(401, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: { code: 401, message: "Unauthorized token" } }));
    return;
  }

  let bodyRaw = "";
  req.on("data", (chunk) => { bodyRaw += chunk; });
  req.on("end", () => {
    const body = bodyRaw ? JSON.parse(bodyRaw) : {};
    const urlPath = (req.url || "/").split("?")[0];
    const projDoc = docsById.get("proj_smoke");

    if (urlPath === "/unrealLink/epic") {
      const uprojectContext = body.uprojectContext || null;
      if (uprojectContext) {
        projDoc.sections.unreal_live_context_json = JSON.stringify(uprojectContext);
      }
      const payload = helpers.computeActiveUnrealEpicPayload({
        docsById,
        projectId: "proj_smoke",
        webStudioUrl: "https://henrycgithub.github.io/LAYERS-Agentic/",
        uprojectContext,
      });
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(payload));
      return;
    }

    if (urlPath === "/unrealLink/update") {
      const action = String(body.action || "");
      if (!helpers.UNREAL_UPDATE_VALID_ACTIONS || !helpers.UNREAL_UPDATE_VALID_ACTIONS.has(action)) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: { code: 400, message: `Invalid action: ${action}` } }));
        return;
      }
      let targetEpicId = String(body.epicId || "").trim();
      if (action !== "sync_uproject") {
        targetEpicId = helpers.resolveTargetEpicDocIdJs({
          docsById,
          projectId: "proj_smoke",
          requestedEpicId: targetEpicId,
          action,
        });
      }
      if (action !== "sync_uproject") {
        const epicDoc = docsById.get(targetEpicId);
        if (!epicDoc) {
          res.writeHead(404, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: { code: 404, message: "Epic not found" } }));
          return;
        }
        const mutated = helpers.applyUnrealEpicMutationJs({
          epicDoc,
          action,
          body,
          nowMs: Date.now(),
        });
        epicDoc.sections = mutated.sections;
        epicDoc.subtasks = mutated.subtasks;
        epicDoc.isCompleted = mutated.isCompleted;
        if (action === "pass_epic") {
          projDoc.sections.selected_epic_id = "";
        } else {
          projDoc.sections.selected_epic_id = targetEpicId;
        }
      }
      const isInPlaceMutation = action !== "pass_epic" && action !== "sync_uproject";
      const payload = helpers.computeActiveUnrealEpicPayload({
        docsById,
        projectId: "proj_smoke",
        webStudioUrl: "https://henrycgithub.github.io/LAYERS-Agentic/",
        uprojectContext: body.uprojectContext || null,
        preferredEpicId: isInPlaceMutation ? targetEpicId : "",
      });
      if (payload.activeEpic?.id) {
        projDoc.sections.selected_epic_id = payload.activeEpic.id;
      }
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(payload));
      return;
    }

    if (urlPath === "/_test/web_studio_reopen_e01") {
      const ep01 = docsById.get("epic_01");
      const mut = helpers.applyUnrealEpicMutationJs({
        epicDoc: ep01,
        action: "reopen_epic",
        body: {},
        nowMs: Date.now(),
      });
      ep01.sections = mut.sections;
      ep01.subtasks = mut.subtasks;
      ep01.isCompleted = mut.isCompleted;
      projDoc.sections.selected_epic_id = "epic_01";
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
      return;
    }

    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: { code: 404, message: "Unknown route" } }));
  });
});

server.listen(0, "127.0.0.1", () => {
  console.log(`SMOKE_PORT=${server.address().port}`);
});
"""


def _validate_uplugin() -> None:
  uplugin_path = PLUGIN_ROOT / "LayersBridge.uplugin"
  assert uplugin_path.is_file(), f"Missing {uplugin_path}"
  data = json.loads(uplugin_path.read_text(encoding="utf-8"))
  assert data.get("Modules") == [], f"Expected pure-Python Modules=[], got {data.get('Modules')}"
  assert data.get("CanContainContent") is True
  plugins = {p["Name"]: p for p in data.get("Plugins", [])}
  assert plugins.get("PythonScriptPlugin", {}).get("Enabled") is True
  assert "ModelContextProtocol" in plugins


def _install_mock_unreal(saved_dir: Path) -> dict[str, object]:
  state: dict[str, object] = {
      "registered_toolsets": [],
      "menu_entries": [],
      "menus_by_name": {},
      "console_commands": [],
      "pie_started": False,
      "logs": [],
      "thread_violations": [],
      "slate_tick_callbacks": [],
  }

  def _assert_game_thread(api_name: str) -> None:
    if threading.current_thread() is not threading.main_thread():
      state["thread_violations"].append(api_name)  # type: ignore[union-attr]
      raise RuntimeError(f"Unreal API {api_name} called off game thread")

  class _Toolset:
    pass

  class _ToolsetRegistry:
    @classmethod
    def get(cls):
      return cls

    @classmethod
    def register_toolset(cls, *args):
      _assert_game_thread("ToolsetRegistry.register_toolset")
      state["registered_toolsets"].append(args[-1])  # type: ignore[union-attr]

  class _World:
    def get_name(self):
      return "L_Arena_Proto"

  class _EditorLevelLibrary:
    @staticmethod
    def get_editor_world():
      _assert_game_thread("EditorLevelLibrary.get_editor_world")
      return _World()

  class _LevelSub:
    def get_current_level(self):
      _assert_game_thread("LevelEditorSubsystem.get_current_level")
      return _World()

    def editor_request_begin_play(self):
      _assert_game_thread("LevelEditorSubsystem.editor_request_begin_play")
      state["pie_started"] = True

  class _GmSettings:
    global_default_game_mode = "GM_Shellbreaker"
    default_pawn_class = "BP_CrabPlayer"

  class _GameMapsSettings:
    @staticmethod
    def get_game_maps_settings():
      _assert_game_thread("GameMapsSettings.get_game_maps_settings")
      return _GmSettings()

  class _AssetData:
    def __init__(self, pkg: str, name: str, cls_name: str):
      self.package_name = pkg
      self.asset_name = name
      self.asset_class = cls_name

  class _AssetRegistry:
    @staticmethod
    def get_assets_by_path(path, recursive=True):
      _assert_game_thread("AssetRegistry.get_assets_by_path")
      return [
          _AssetData("/Game/Input/IMC_Core", "IMC_Core", "InputMappingContext"),
          _AssetData("/Game/Input/IA_Move", "IA_Move", "InputAction"),
          _AssetData("/Game/Input/IA_Dash", "IA_Dash", "InputAction"),
      ]

  class _AssetRegistryHelpers:
    @staticmethod
    def get_asset_registry():
      return _AssetRegistry()

  class _Menu:
    def __init__(self, name: str):
      self.name = name
      self.entries: dict[str, object] = {}

    def find_or_add_section(self, section_name: str):
      return self

    def add_menu_entry(self, *args):
      entry = args[-1]
      entry_name = getattr(entry, "name", "")
      if entry_name:
        self.entries[entry_name] = entry
      state["menu_entries"].append(entry)  # type: ignore[union-attr]

  class _ToolMenuEntry:
    def __init__(self, name="", type=""):
      self.name = name
      self.type = type
      self.label = ""
      self.tooltip = ""
      self.cmd = {}

    def set_label(self, lbl: str):
      self.label = lbl

    def set_tool_tip(self, tip: str):
      self.tooltip = tip

    def set_string_command(self, **kwargs):
      self.cmd = kwargs

  class _ToolMenus:
    @classmethod
    def _ensure_menu(cls, name: str) -> _Menu:
      menus = state["menus_by_name"]  # type: ignore[assignment]
      if name not in menus:
        menus[name] = _Menu(name)
      return menus[name]  # type: ignore[return-value]

    @classmethod
    def get(cls):
      _assert_game_thread("ToolMenus.get")
      return cls

    @classmethod
    def find_menu(cls, name: str):
      _assert_game_thread("ToolMenus.find_menu")
      return cls._ensure_menu(name)

    @classmethod
    def extend_menu(cls, name: str):
      _assert_game_thread("ToolMenus.extend_menu")
      return cls._ensure_menu(name)

    @classmethod
    def register_menu(cls, name: str, *args, **kwargs):
      _assert_game_thread("ToolMenus.register_menu")
      return cls._ensure_menu(name)

    @classmethod
    def refresh_all_widgets(cls):
      _assert_game_thread("ToolMenus.refresh_all_widgets")

  class _SystemLibrary:
    @staticmethod
    def get_game_name():
      _assert_game_thread("SystemLibrary.get_game_name")
      return "ShellbreakerUE5"

    @staticmethod
    def execute_console_command(world, command, specific_player=None):
      _assert_game_thread("SystemLibrary.execute_console_command")
      state["console_commands"].append(str(command))  # type: ignore[union-attr]

  class _Paths:
    @staticmethod
    def project_saved_dir():
      _assert_game_thread("Paths.project_saved_dir")
      return str(saved_dir)

  def _log_fn(msg: object) -> None:
    _assert_game_thread("unreal.log")
    state["logs"].append(str(msg))  # type: ignore[union-attr]

  def _register_slate_post_tick(cb: object) -> object:
    _assert_game_thread("unreal.register_slate_post_tick_callback")
    state["slate_tick_callbacks"].append(cb)  # type: ignore[union-attr]
    return object()

  unreal_mod = types.ModuleType("unreal")
  unreal_mod.Toolset = _Toolset  # type: ignore[attr-defined]
  unreal_mod.ToolsetRegistry = _ToolsetRegistry  # type: ignore[attr-defined]
  unreal_mod.EditorLevelLibrary = _EditorLevelLibrary  # type: ignore[attr-defined]
  unreal_mod.LevelEditorSubsystem = _LevelSub  # type: ignore[attr-defined]
  unreal_mod.get_editor_subsystem = lambda cls: cls()  # type: ignore[attr-defined]
  unreal_mod.GameMapsSettings = _GameMapsSettings  # type: ignore[attr-defined]
  unreal_mod.AssetRegistryHelpers = _AssetRegistryHelpers  # type: ignore[attr-defined]
  unreal_mod.ToolMenus = _ToolMenus  # type: ignore[attr-defined]
  unreal_mod.ToolMenuEntry = _ToolMenuEntry  # type: ignore[attr-defined]
  unreal_mod.MultiBlockType = types.SimpleNamespace(  # type: ignore[attr-defined]
      MENU_ENTRY="MENU_ENTRY",
      TOOL_BAR_BUTTON="TOOL_BAR_BUTTON",
      TOOL_BAR_COMBO_BUTTON="TOOL_BAR_COMBO_BUTTON",
  )
  unreal_mod.ToolMenuStringCommandType = types.SimpleNamespace(PYTHON="PYTHON")  # type: ignore[attr-defined]
  unreal_mod.SystemLibrary = _SystemLibrary  # type: ignore[attr-defined]
  unreal_mod.Paths = _Paths  # type: ignore[attr-defined]
  unreal_mod.log = _log_fn  # type: ignore[attr-defined]
  unreal_mod.register_slate_post_tick_callback = _register_slate_post_tick  # type: ignore[attr-defined]

  sys.modules["unreal"] = unreal_mod
  return state


def main() -> int:
  _validate_uplugin()

  node_env = dict(os.environ)
  node_env["GCLOUD_PROJECT"] = "layers-b8a16"
  node_env["SMOKE_TOKEN"] = TEST_TOKEN
  proc = subprocess.Popen(
      ["node", "-e", NODE_HARNESS_JS],
      cwd=str(REPO_ROOT),
      env=node_env,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      text=True,
  )

  try:
    assert proc.stdout is not None
    port_line = ""
    while True:
      line = proc.stdout.readline()
      if not line:
        stderr = proc.stderr.read() if proc.stderr else ""
        raise RuntimeError(f"Smoke Node server exited unexpectedly: {stderr}")
      if line.startswith("SMOKE_PORT="):
        port_line = line.strip()
        break
    port = int(port_line.split("=", 1)[1])

    with tempfile.TemporaryDirectory(prefix="layers_ue_smoke_") as tmp_dir:
      saved_dir = Path(tmp_dir) / "Saved"
      unreal_state = _install_mock_unreal(saved_dir)

      os.environ["LAYERS_LINK_TOKEN"] = TEST_TOKEN
      os.environ["LAYERS_SYNC_URL"] = f"http://127.0.0.1:{port}"
      sys.path.insert(0, str(PYTHON_DIR))

      import ssl
      import init_unreal  # type: ignore
      from layers_sync_client import _build_ssl_context  # type: ignore

      ssl_ctx = _build_ssl_context()
      assert ssl_ctx.verify_mode == ssl.CERT_REQUIRED

      assert len(unreal_state["registered_toolsets"]) >= 1
      assert len(unreal_state["menu_entries"]) >= 1
      play_tb = unreal_state["menus_by_name"].get(  # type: ignore[union-attr]
          "LevelEditor.LevelEditorToolBar.PlayToolBar"
      )
      assert play_tb is not None, "Expected PlayToolBar registration"
      assert "LayersPrimaryAction" in play_tb.entries
      assert "LayersPieGateCombo" in play_tb.entries
      assert play_tb.entries["LayersPrimaryAction"].type == "TOOL_BAR_BUTTON"
      assert play_tb.entries["LayersPieGateCombo"].type == "TOOL_BAR_COMBO_BUTTON"

      toolset = init_unreal.get_toolset()
      dock = init_unreal.get_pie_dock()

      # 1. Fetch active Epic + verify ROOT_MCP_CONTEXT, Core Feel & .uproject injection
      spec_md = toolset.layers_get_active_epic_spec()
      assert "# ROOT_MCP_CONTEXT · SHELLBREAKER" in spec_md
      assert "- Core Feel: Heavy Deliberate" in spec_md, spec_md
      assert "## Live Unreal Project Snapshot (.uproject via LayersBridge)" in spec_md
      assert "ShellbreakerUE5" in spec_md
      assert "/Game/Input/IMC_Core" in spec_md
      assert "# ACTIVE EPIC SPEC · E01 · Crab Locomotion & Dash" in spec_md
      assert "### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK" in spec_md

      # 1a. Verify Split Play-Toolbar default Build state & CLI / clipboard dispatch
      primary_action = dock.compute_primary_toolbar_action()
      assert primary_action["mode"] == "build", primary_action
      assert primary_action["label"] == "⚡ Build E01", primary_action
      assert dock.compute_gate_combo_label() == "E01 · 0/2 ✓"

      captured_builds: list[tuple[list[str], str]] = []
      dock.cli_runner = lambda cmd, prompt: (
          captured_builds.append((cmd, prompt)) or (0, "Synthesized E01 cleanly")
      )
      try:
        build_res = init_unreal.build_active_epic(background=False)
        assert build_res.get("ok") is True, build_res
        assert build_res.get("mode") == "cli_agent", build_res
        assert "ModelContextProtocol.StartServer" in unreal_state["console_commands"]
        assert "layers_get_active_epic_spec" in captured_builds[-1][1]
        assert "FULL-EPIC AUTONOMOUS BUILD" in captured_builds[-1][1]
        handoff_res = dock.build_active_epic(agent_cli="clipboard", background=False)
        assert handoff_res.get("mode") == "clipboard_handoff", handoff_res
      finally:
        dock.cli_runner = None

      # 1a-bg. Background CLI build & off-thread MCP call must marshal all unreal.* calls to Slate ticks
      worker_started = threading.Event()
      allow_finish = threading.Event()

      def _bg_cli_runner(cmd: list[str], prompt: str) -> tuple[int, str]:
        captured_builds.append((cmd, prompt))
        worker_started.set()
        assert allow_finish.wait(timeout=5), "Timed out waiting for allow_finish"
        return 0, "Synthesized E01 bg"

      dock.cli_runner = _bg_cli_runner
      try:
        bg_res = init_unreal.build_active_epic(background=True)
        assert bg_res.get("ok") is True and bg_res.get("mode") == "cli_agent", bg_res
        assert worker_started.wait(timeout=3), "Background CLI worker did not start"
        assert play_tb.entries["LayersPrimaryAction"].label == "⏳ Building E01…", (
            play_tb.entries["LayersPrimaryAction"].label
        )
        builds_before_dup = len(captured_builds)
        dup_res = init_unreal.build_active_epic(background=True)
        assert dup_res.get("mode") == "building", dup_res
        assert len(captured_builds) == builds_before_dup
        allow_finish.set()
        assert dock._active_build_thread is not None
        dock._active_build_thread.join(timeout=5)
        assert not dock._active_build_thread.is_alive(), "Build thread did not join"
      finally:
        allow_finish.set()
        dock.cli_runner = None

      assert unreal_state["thread_violations"] == [], unreal_state["thread_violations"]
      assert unreal_state["slate_tick_callbacks"], "Expected Slate post-tick callback registration"
      for cb in list(unreal_state["slate_tick_callbacks"]):  # type: ignore[arg-type]
        cb(0.016)
      assert play_tb.entries["LayersPrimaryAction"].label == "⚡ Build E01", (
          play_tb.entries["LayersPrimaryAction"].label
      )
      assert any("Synthesized E01 bg" in msg for msg in unreal_state["logs"]), unreal_state["logs"]
      bg_md = str((dock.last_payload or {}).get("mcpPayloadMarkdown") or "")
      assert "ShellbreakerUE5" in bg_md and "/Game/Input/IMC_Core" in bg_md, bg_md

      # Off-thread MCP toolset call must also preserve cached .uproject snapshot & avoid thread violations
      mcp_holder: list[str] = []

      def _off_thread_mcp() -> None:
        mcp_holder.append(toolset.layers_get_active_epic_spec())

      mcp_thread = threading.Thread(target=_off_thread_mcp)
      mcp_thread.start()
      mcp_thread.join(timeout=5)
      assert not mcp_thread.is_alive()
      for cb in list(unreal_state["slate_tick_callbacks"]):  # type: ignore[arg-type]
        cb(0.016)
      assert unreal_state["thread_violations"] == [], unreal_state["thread_violations"]
      assert mcp_holder and "ShellbreakerUE5" in mcp_holder[0] and "/Game/Input/IMC_Core" in mcp_holder[0]

      # 1b. Update existing §04 tuning + insert new §04 tuning (with unit normalization)
      tune_md = toolset.layers_update_epic_tuning("DashDistance", "460")
      assert "- DashDistance: 460 cm" in tune_md
      new_tune_md = toolset.layers_update_epic_tuning("ArenaRadius", "1800", unit="pixels")
      assert "- ArenaRadius: 1800 cm" in new_tune_md
      slide_tune_md = toolset.layers_update_epic_tuning("SlideSpeed", "900", unit="pixels/s")
      assert "- SlideSpeed: 900 cm/s" in slide_tune_md, slide_tune_md
      zero_tune_md = toolset.layers_update_epic_tuning("CameraLag", 0)  # type: ignore[arg-type]
      assert "- CameraLag: 0 count" in zero_tune_md, zero_tune_md
      zero_dock_res = dock.update_tuning("WarmupDelay", 0.0, "s")  # type: ignore[arg-type]
      assert zero_dock_res.get("ok") is True and "- WarmupDelay: 0.0 s" in str(
          zero_dock_res.get("mcpPayloadMarkdown") or ""
      ), zero_dock_res

      # 1c. Toggle individual §06 PIE checks (including final check) without jumping off E01
      chk_md = toolset.layers_toggle_pie_check("1", passed=True)
      assert "1/2" in chk_md, chk_md
      assert "[PASSED] Check 1:" in chk_md, chk_md
      assert "[VERIFY] Check 2:" in chk_md, chk_md
      assert play_tb.entries["LayersPieGateCombo"].label == "E01 · 1/2 ✓", (
          play_tb.entries["LayersPieGateCombo"].label
      )
      combo_menu = unreal_state["menus_by_name"].get(  # type: ignore[union-attr]
          "LevelEditor.LevelEditorToolBar.PlayToolBar.LayersPieGateCombo"
      )
      assert combo_menu is not None
      assert "LayersMenuPlayPie" in combo_menu.entries
      assert "LayersMenuPass" in combo_menu.entries
      assert "LayersCheck_1" in combo_menu.entries
      assert "[x] Check 1:" in combo_menu.entries["LayersCheck_1"].label
      assert "LayersCheck_2" in combo_menu.entries
      assert "[ ] Check 2:" in combo_menu.entries["LayersCheck_2"].label

      chk2_md = toolset.layers_toggle_pie_check("2", passed=True)
      assert "2/2 passed) on E01" in chk2_md, chk2_md
      assert "# ACTIVE EPIC SPEC · E01" in chk2_md, chk2_md

      # 2. Log 2 PIE [FIX] items and confirm switch to FOCUSED PIE REVISION PASS + live toolbar Fix label
      fix_md = toolset.layers_log_pie_fix("Boom clips ceiling during dash jump")
      assert "### FOCUSED PIE REVISION PASS (1 OPEN [FIX])" in fix_md
      assert "- [FIX] Boom clips ceiling during dash jump" in fix_md
      assert dock.compute_primary_toolbar_action()["mode"] == "fix"
      assert dock.compute_primary_toolbar_action()["label"] == "🔧 Fix E01 (1)"
      assert play_tb.entries["LayersPrimaryAction"].label == "🔧 Fix E01 (1)"

      fix2_md = toolset.layers_log_pie_fix("Dash trail flickers on slope")
      assert "### FOCUSED PIE REVISION PASS (2 OPEN [FIX])" in fix2_md
      assert dock.compute_primary_toolbar_action()["label"] == "🔧 Fix E01 (2)"

      # 3. Resolve "latest" -> resolves #2 (newest) first, keeping older #1 open; then resolves #1
      resolved_latest = toolset.layers_resolve_pie_fix("latest")
      assert "1 remaining" in resolved_latest, resolved_latest
      assert "- [FIX] Boom clips ceiling during dash jump" in resolved_latest
      assert "- [FIX] Dash trail flickers on slope" not in resolved_latest
      resolved_md = toolset.layers_resolve_pie_fix("latest")
      assert "Resolved PIE [FIX] on E01" in resolved_md, resolved_md
      assert "0 remaining" in resolved_md
      assert "### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK" in resolved_md
      assert dock.compute_primary_toolbar_action()["mode"] == "pass"
      assert dock.compute_primary_toolbar_action()["label"] == "✓ Pass E01 →"

      # 4. Launch PIE from dock & sign off E01 via primary toolbar -> advances cleanly to Build E02
      assert dock.launch_pie() is True
      assert unreal_state["pie_started"] is True
      pass_res = init_unreal.trigger_toolbar_primary_action()
      assert pass_res.get("ok") is True and pass_res.get("mode") == "passed", pass_res
      assert dock.compute_primary_toolbar_action()["label"] == "⚡ Build E02"

      # 5. Fetch E02, check its Check 1 -> stale E01 LayersCheck_2 cleared; stays uncompleted until Pass E02 ✓
      e02_md = toolset.layers_get_active_epic_spec()
      assert "# ACTIVE EPIC SPEC · E02 · Claw Blaster & Hitstop" in e02_md
      assert "[VERIFY] Check 1:" in e02_md, e02_md
      assert "LayersCheck_1" in combo_menu.entries
      assert "LayersCheck_2" not in combo_menu.entries, combo_menu.entries
      toolset.layers_toggle_pie_check("1", passed=True)
      assert dock.last_payload is not None
      assert dock.last_payload.get("allEpicsCompleted") is False, dock.last_payload
      assert dock.compute_primary_toolbar_action()["mode"] == "pass"
      assert dock.compute_primary_toolbar_action()["label"] == "✓ Pass E02 →"
      done_msg = toolset.layers_pass_active_epic()
      assert "All Epics passed PIE acceptance gate" in done_msg
      assert (dock.last_payload or {}).get("allEpicsCompleted") is True

      # 5b. Reopen E01 by Epic code ("E01"), update tuning via dock, and re-pass E01
      reopen_md = toolset.layers_reopen_epic("E01")
      assert "Reopened E01" in reopen_md
      assert "# ACTIVE EPIC SPEC · E01 · Crab Locomotion & Dash" in reopen_md
      assert "[VERIFY] Check 1:" in reopen_md
      dock_tune = dock.update_tuning("MaxWalkSpeed", "650", "cm/s")
      assert dock_tune.get("ok") is True
      assert "- MaxWalkSpeed: 650 cm/s" in str(dock_tune.get("mcpPayloadMarkdown") or "")
      repass_res = dock.pass_epic()
      assert repass_res.get("allEpicsCompleted") is True

      # 5c. Reopen v0.2 upgrading Epic preserves locked v0.1 baseline checks & restores upgrading lifecycle
      reopen_v02_js = r"""
      process.env.GCLOUD_PROJECT = 'layers-b8a16';
      const { _testHelpers: h } = require('./functions/index.js');
      const v02Doc = {
        id: 'ep_v02_up',
        sections: {
          code: 'E01',
          lineage_key: 'e01',
          release_version: 'v0.2',
          lifecycle: 'stable',
          epic_spec_json: JSON.stringify({
            id: 'ep_v02_up',
            code: 'E01',
            lineageKey: 'e01',
            title: 'Movement',
            releaseVersion: 'v0.2',
            lifecycle: 'stable',
            goal: 'Jump + Dash',
            upgradeDeltas: ['+55ms Hit-Stop'],
            checks: [
              { id: 'c1', text: 'v0.1 base walk passes', passed: true },
              { id: 'ep_v02_up_delta_1', text: 'Verify v0.2 delta: 55ms Hit-Stop', passed: true }
            ]
          })
        }
      };
      const out = h.applyUnrealEpicMutationJs({ epicDoc: v02Doc, action: 'reopen_epic', body: {}, nowMs: 1234 });
      if (out.epicSpec.lifecycle !== 'upgrading') throw new Error('Expected upgrading, got ' + out.epicSpec.lifecycle);
      if (out.epicSpec.checks[0].passed !== true) throw new Error('Expected baseline check to remain passed');
      if (out.epicSpec.checks[1].passed !== false) throw new Error('Expected delta check to reset to false');
      if (out.isCompleted !== false) throw new Error('Expected isCompleted false');
      const e10 = h.parseEpicSpecJs({}, 9);
      if (e10.code !== 'E10') throw new Error('Expected E10 padding, got ' + e10.code);

      // 5c-1. Toggling all checks to true keeps active lifecycle & isCompleted === false until explicit pass_epic
      const activeDoc = {
        id: 'ep_active_gate',
        sections: {
          code: 'E01',
          lineage_key: 'e01',
          release_version: 'v0.1',
          lifecycle: 'active',
          epic_spec_json: JSON.stringify({
            id: 'ep_active_gate',
            code: 'E01',
            lineageKey: 'e01',
            title: 'Movement',
            releaseVersion: 'v0.1',
            lifecycle: 'active',
            goal: 'Move cleanly',
            checks: [{ id: 'c1', text: 'Move test', passed: false }]
          })
        }
      };
      const chkOut = h.applyUnrealEpicMutationJs({ epicDoc: activeDoc, action: 'toggle_check', body: { checkId: 'c1', passed: true }, nowMs: 1235 });
      if (chkOut.epicSpec.lifecycle !== 'active') throw new Error('Expected active before pass_epic, got ' + chkOut.epicSpec.lifecycle);
      if (chkOut.isCompleted !== false) throw new Error('Expected isCompleted false before pass_epic');
      const passOut = h.applyUnrealEpicMutationJs({ epicDoc: { id: 'ep_active_gate', sections: chkOut.sections }, action: 'pass_epic', body: {}, nowMs: 1236 });
      if (passOut.epicSpec.lifecycle !== 'stable' || passOut.isCompleted !== true) throw new Error('Expected stable + isCompleted true after pass_epic');

      // 5c-2. Unchecking a check on a stable v0.2 doc demotes lifecycle to upgrading & isCompleted === false
      const unchkOut = h.applyUnrealEpicMutationJs({ epicDoc: v02Doc, action: 'toggle_check', body: { checkId: 'c1', passed: false }, nowMs: 1237 });
      if (unchkOut.epicSpec.lifecycle !== 'upgrading') throw new Error('Expected upgrading demotion on uncheck, got ' + unchkOut.epicSpec.lifecycle);
      if (unchkOut.isCompleted !== false) throw new Error('Expected isCompleted false after uncheck');

      // 5c-3. resolveTargetEpicDocIdJs ignores stale v0.1 selected_epic_id when active_release_id is v0.2
      const crossDocs = new Map();
      crossDocs.set('proj_x', {
        id: 'proj_x',
        tier: 'project',
        childrenIds: ['rel_v01', 'rel_v02'],
        sections: { active_release_id: 'rel_v02', selected_epic_id: 'rel_v01_ep1' }
      });
      crossDocs.set('rel_v01', { id: 'rel_v01', tier: 'release', parentId: 'proj_x', childrenIds: ['rel_v01_ep1'], sections: { release_version: 'v0.1' } });
      crossDocs.set('rel_v02', { id: 'rel_v02', tier: 'release', parentId: 'proj_x', childrenIds: ['rel_v02_ep1'], sections: { release_version: 'v0.2' } });
      crossDocs.set('rel_v01_ep1', { id: 'rel_v01_ep1', tier: 'epic', parentId: 'rel_v01', sections: { code: 'E01', lifecycle: 'active' } });
      crossDocs.set('rel_v02_ep1', { id: 'rel_v02_ep1', tier: 'epic', parentId: 'rel_v02', sections: { code: 'E01', lifecycle: 'queued' } });
      const resolvedId = h.resolveTargetEpicDocIdJs({ docsById: crossDocs, projectId: 'proj_x', requestedEpicId: '' });
      if (resolvedId !== 'rel_v02_ep1') throw new Error('Expected rel_v02_ep1, got ' + resolvedId);

      // 5c-4. v0.3 renderServerUnrealMcpPayloadJs emits Locked Baseline & reopen_epic keeps v0.2 checks passed
      const v03Doc = {
        id: 'ep_v03_up',
        sections: {
          code: 'E01',
          lineage_key: 'e01',
          release_version: 'v0.3',
          lifecycle: 'stable',
          epic_spec_json: JSON.stringify({
            id: 'ep_v03_up',
            code: 'E01',
            lineageKey: 'e01',
            title: 'Movement',
            releaseVersion: 'v0.3',
            lifecycle: 'stable',
            goal: 'Jump + Dash',
            baselineSummary: ['v0.2: +55ms Hit-Stop'],
            upgradeDeltas: ['+Dash echo'],
            checks: [
              { id: 'ep_v03_base_2', text: 'Verify v0.2 delta: 55ms Hit-Stop', passed: true },
              { id: 'ep_v03_delta_1', text: 'Verify v0.3 delta: Dash echo', passed: true }
            ]
          })
        }
      };
      const v03Md = h.renderServerUnrealMcpPayloadJs({
        rootSpec: { normalizedTitle: 'T', targetEngine: 'ue5Mcp', pitch: 'P' },
        epicSpec: h.parseEpicSpecJs(v03Doc)
      });
      if (!v03Md.includes('- Locked Baseline: v0.2: +55ms Hit-Stop')) {
        throw new Error('Expected Locked Baseline in v0.3 payload');
      }
      const v03Reopen = h.applyUnrealEpicMutationJs({ epicDoc: v03Doc, action: 'reopen_epic', body: {}, nowMs: 2000 });
      if (v03Reopen.epicSpec.checks[0].passed !== true) {
        throw new Error('Expected v0.2 locked check to remain passed on v0.3 reopen');
      }
      if (v03Reopen.epicSpec.checks[1].passed !== false) {
        throw new Error('Expected v0.3 delta check to reset on v0.3 reopen');
      }
      const delCheck = h.computeActiveUnrealEpicPayload({ docsById: crossDocs, projectId: 'proj_deleted' });
      if (delCheck.ok !== false) {
        throw new Error('Expected ok: false when linked projectId was deleted');
      }
      """
      reopen_proc = subprocess.run(["node", "-e", reopen_v02_js], cwd=str(REPO_ROOT), capture_output=True, text=True, timeout=10)
      assert reopen_proc.returncode == 0, f"v0.2 reopen check failed: {reopen_proc.stderr}"

      # 5d. Web Studio reopens E01 server-side while dock.last_payload still holds E02:
      #     dock.flag_fix() must omit stale epicId, hit E01, and inject fresh .uproject PIE errors
      from layers_project_probe import clear_pie_errors, record_pie_error  # type: ignore

      req = urllib.request.Request(
          url=f"http://127.0.0.1:{port}/_test/web_studio_reopen_e01",
          data=b"{}",
          headers={"Authorization": f"Bearer {TEST_TOKEN}"},
          method="POST",
      )
      with urllib.request.urlopen(req, timeout=5) as resp:
        assert resp.status == 200

      record_pie_error("LogBlueprintUserMessages: Warning: Dash trace missed ramp")
      try:
        fix_res = dock.flag_fix("Dash trace missed ramp")
        assert fix_res.get("ok") is True, fix_res
        assert (fix_res.get("activeEpic") or {}).get("code") == "E01", fix_res
        assert "LogBlueprintUserMessages: Warning: Dash trace missed ramp" in str(
            fix_res.get("mcpPayloadMarkdown") or ""
        )
      finally:
        clear_pie_errors()

      assert dock.flag_fix("   ").get("ok") is False
      assert dock.toggle_check("").get("ok") is False
      assert dock.update_tuning("", "100").get("ok") is False

      dock.resolve_fix("latest")
      final_pass = dock.pass_epic()
      assert final_pass.get("allEpicsCompleted") is True
      assert "[ALL EPICS PASSED ✓]" in dock.render_dock_summary_text()

      # 6. Check token + agent_cli persistence helper & stale last_payload reset on token change
      dock.configure_token(
          "lyr_saved_token_check_0001",
          f"http://127.0.0.1:{port}",
          agent_cli="claude",
      )
      assert dock.last_payload is None
      assert "SHELLBREAKER" not in dock.render_dock_summary_text()
      cfg_file = saved_dir / "Config" / "LayersBridge.json"
      assert cfg_file.is_file()
      cfg_data = json.loads(cfg_file.read_text(encoding="utf-8"))
      assert cfg_data["link_token"] == "lyr_saved_token_check_0001"
      assert cfg_data["agent_cli"] == "claude"
      dock.configure_token("lyr_saved_token_check_0002")
      cfg_data_2 = json.loads(cfg_file.read_text(encoding="utf-8"))
      assert cfg_data_2["link_token"] == "lyr_saved_token_check_0002"
      assert cfg_data_2["sync_base_url"] == f"http://127.0.0.1:{port}", cfg_data_2
      assert cfg_data_2["agent_cli"] == "claude", cfg_data_2

    print("UNREAL_SMOKE_OK")
    return 0
  finally:
    proc.terminate()
    try:
      proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
      proc.kill()


if __name__ == "__main__":
  raise SystemExit(main())
