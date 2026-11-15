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
import types

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
      const payload = helpers.computeActiveUnrealEpicPayload({
        docsById,
        projectId: "proj_smoke",
        webStudioUrl: "https://henrycgithub.github.io/LAYERS-Agentic/",
        uprojectContext: body.uprojectContext || null,
      });
      if (payload.activeEpic?.id) {
        projDoc.sections.selected_epic_id = payload.activeEpic.id;
      }
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(payload));
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
      "pie_started": False,
      "logs": [],
  }

  class _Toolset:
    pass

  class _ToolsetRegistry:
    @classmethod
    def get(cls):
      return cls

    @classmethod
    def register_toolset(cls, *args):
      state["registered_toolsets"].append(args[-1])  # type: ignore[union-attr]

  class _World:
    def get_name(self):
      return "L_Arena_Proto"

  class _EditorLevelLibrary:
    @staticmethod
    def get_editor_world():
      return _World()

  class _LevelSub:
    def get_current_level(self):
      return _World()

    def editor_request_begin_play(self):
      state["pie_started"] = True

  class _GmSettings:
    global_default_game_mode = "GM_Shellbreaker"
    default_pawn_class = "BP_CrabPlayer"

  class _GameMapsSettings:
    @staticmethod
    def get_game_maps_settings():
      return _GmSettings()

  class _AssetData:
    def __init__(self, pkg: str, name: str, cls_name: str):
      self.package_name = pkg
      self.asset_name = name
      self.asset_class = cls_name

  class _AssetRegistry:
    @staticmethod
    def get_assets_by_path(path, recursive=True):
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
    def add_menu_entry(self, *args):
      state["menu_entries"].append(args[-1])  # type: ignore[union-attr]

  class _ToolMenuEntry:
    def __init__(self, name="", type=""):
      self.name = name
      self.label = ""

    def set_label(self, lbl: str):
      self.label = lbl

    def set_tool_tip(self, tip: str):
      self.tooltip = tip

    def set_string_command(self, **kwargs):
      self.cmd = kwargs

  class _ToolMenus:
    @classmethod
    def get(cls):
      return cls

    @classmethod
    def find_menu(cls, name: str):
      return _Menu()

    @classmethod
    def refresh_all_widgets(cls):
      pass

  class _SystemLibrary:
    @staticmethod
    def get_game_name():
      return "ShellbreakerUE5"

  class _Paths:
    @staticmethod
    def project_saved_dir():
      return str(saved_dir)

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
  unreal_mod.MultiBlockType = types.SimpleNamespace(MENU_ENTRY="MENU_ENTRY")  # type: ignore[attr-defined]
  unreal_mod.ToolMenuStringCommandType = types.SimpleNamespace(PYTHON="PYTHON")  # type: ignore[attr-defined]
  unreal_mod.SystemLibrary = _SystemLibrary  # type: ignore[attr-defined]
  unreal_mod.Paths = _Paths  # type: ignore[attr-defined]
  unreal_mod.log = lambda msg: state["logs"].append(str(msg))  # type: ignore[attr-defined]

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

      import init_unreal  # type: ignore

      assert len(unreal_state["registered_toolsets"]) >= 1
      assert len(unreal_state["menu_entries"]) >= 1

      toolset = init_unreal.get_toolset()
      dock = init_unreal.get_pie_dock()

      # 1. Fetch active Epic + verify ROOT_MCP_CONTEXT & .uproject injection
      spec_md = toolset.layers_get_active_epic_spec()
      assert "# ROOT_MCP_CONTEXT · SHELLBREAKER" in spec_md
      assert "## Live Unreal Project Snapshot (.uproject via LayersBridge)" in spec_md
      assert "ShellbreakerUE5" in spec_md
      assert "/Game/Input/IMC_Core" in spec_md
      assert "# ACTIVE EPIC SPEC · E01 · Crab Locomotion & Dash" in spec_md
      assert "### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK" in spec_md

      # 1b. Update existing §04 tuning + insert new §04 tuning (with unit normalization)
      tune_md = toolset.layers_update_epic_tuning("DashDistance", "460")
      assert "- DashDistance: 460 cm" in tune_md
      new_tune_md = toolset.layers_update_epic_tuning("ArenaRadius", "1800", unit="pixels")
      assert "- ArenaRadius: 1800 cm" in new_tune_md

      # 1c. Toggle individual §06 PIE check by 1-based check number ("1")
      chk_md = toolset.layers_toggle_pie_check("1", passed=True)
      assert "1/2" in chk_md
      assert "[PASSED] Check 1:" in chk_md
      assert "[VERIFY] Check 2:" in chk_md

      # 2. Log PIE [FIX] and confirm switch to FOCUSED PIE REVISION PASS
      fix_md = toolset.layers_log_pie_fix("Boom clips ceiling during dash jump")
      assert "### FOCUSED PIE REVISION PASS (1 OPEN [FIX])" in fix_md
      assert "- [FIX] Boom clips ceiling during dash jump" in fix_md

      # 3. Resolve [FIX] and restore FULL-EPIC footer
      resolved_md = toolset.layers_resolve_pie_fix("latest")
      assert "0 remaining" in resolved_md
      assert "### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK" in resolved_md

      # 4. Launch PIE from dock & sign off E01 -> advances automatically to E02
      assert dock.launch_pie() is True
      assert unreal_state["pie_started"] is True
      pass_msg = toolset.layers_pass_active_epic()
      assert "Epic 2/2: E02" in pass_msg

      # 5. Fetch E02 & pass E02 -> allEpicsCompleted
      e02_md = toolset.layers_get_active_epic_spec()
      assert "# ACTIVE EPIC SPEC · E02 · Claw Blaster & Hitstop" in e02_md
      done_msg = toolset.layers_pass_active_epic()
      assert "All Epics passed PIE acceptance gate" in done_msg

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

      # 6. Check token config persistence helper
      dock.configure_token("lyr_saved_token_check_0001", f"http://127.0.0.1:{port}")
      cfg_file = saved_dir / "Config" / "LayersBridge.json"
      assert cfg_file.is_file()
      assert json.loads(cfg_file.read_text(encoding="utf-8"))["link_token"] == "lyr_saved_token_check_0001"

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
