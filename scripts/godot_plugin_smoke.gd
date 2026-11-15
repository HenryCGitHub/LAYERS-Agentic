extends SceneTree

const SMOKE_SCENE_PATH := "res://scenes/smoke_arena.tscn"
const SMOKE_SCRIPT_PATH := "res://scripts/smoke_player.gd"
const CONFIG_PATH := "res://.layers/link_config.cfg"
const CACHE_PATH := "res://.layers/cached_epic.json"

var _created_dirs: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var ok: bool = _run_smoke_suite()
	_cleanup_smoke_files()
	if not ok:
		quit(1)
		return
	print("GODOT_SMOKE_OK")
	quit(0)


func _fail(msg: String) -> void:
	printerr("SMOKE_FAIL: ", msg)


func _ensure_res_dir(res_dir: String) -> void:
	var abs_dir: String = ProjectSettings.globalize_path(res_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		var err: int = DirAccess.make_dir_recursive_absolute(abs_dir)
		if err == OK:
			_created_dirs.append(res_dir)


func _write_smoke_fixtures() -> bool:
	_ensure_res_dir("res://scenes")
	_ensure_res_dir("res://scripts")

	var f_gd: FileAccess = FileAccess.open(SMOKE_SCRIPT_PATH, FileAccess.WRITE)
	if f_gd == null:
		_fail("Failed to write temporary smoke script.")
		return false
	f_gd.store_string("extends CharacterBody3D\n\nfunc _ready() -> void:\n\tpass\n")
	f_gd.flush()
	f_gd.close()

	var root: Node3D = Node3D.new()
	root.name = "SmokeArena"
	var body: CharacterBody3D = CharacterBody3D.new()
	body.name = "Player"
	root.add_child(body)
	body.owner = root
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	body.add_child(col)
	col.owner = root
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	body.add_child(cam)
	cam.owner = root

	var packed: PackedScene = PackedScene.new()
	var pack_err: int = packed.pack(root)
	root.free()
	if pack_err != OK:
		_fail("Failed to pack smoke_arena.tscn.")
		return false
	var save_err: int = ResourceSaver.save(packed, SMOKE_SCENE_PATH)
	if save_err != OK:
		_fail("Failed to save smoke_arena.tscn.")
		return false
	return true


func _cleanup_smoke_files() -> void:
	for p in [SMOKE_SCENE_PATH, SMOKE_SCRIPT_PATH, CONFIG_PATH, CACHE_PATH]:
		var abs_p: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)
	for d in ["res://.layers", "res://scenes", "res://scripts"]:
		var abs_d: String = ProjectSettings.globalize_path(d)
		if DirAccess.dir_exists_absolute(abs_d):
			var da: DirAccess = DirAccess.open(abs_d)
			if da != null:
				da.list_dir_begin()
				var first: String = da.get_next()
				while first == "." or first == "..":
					first = da.get_next()
				da.list_dir_end()
				if first.is_empty():
					DirAccess.remove_absolute(abs_d)


func _collect_buttons_by_text(node: Node, needle: String, out: Array[Button]) -> void:
	if node is Button:
		var b: Button = node as Button
		if b.text.find(needle) != -1:
			out.append(b)
	for ch in node.get_children():
		if ch is Node:
			_collect_buttons_by_text(ch as Node, needle, out)


func _collect_checkboxes(node: Node, out: Array[CheckBox]) -> void:
	if node is CheckBox:
		out.append(node as CheckBox)
	for ch in node.get_children():
		if ch is Node:
			_collect_checkboxes(ch as Node, out)


func _collect_labels_text(node: Node, out: PackedStringArray) -> void:
	if node is Label:
		out.append((node as Label).text)
	for ch in node.get_children():
		if ch is Node:
			_collect_labels_text(ch as Node, out)


func _run_smoke_suite() -> bool:
	# 1. Compile-check all 4 addon GDScripts cleanly with CACHE_MODE_REPLACE
	var plugin_scr: Variant = ResourceLoader.load(
		"res://addons/layers/layers_plugin.gd", "", ResourceLoader.CACHE_MODE_REPLACE
	)
	var sync_scr: Variant = ResourceLoader.load(
		"res://addons/layers/layers_sync_client.gd", "", ResourceLoader.CACHE_MODE_REPLACE
	)
	var exec_scr: Variant = ResourceLoader.load(
		"res://addons/layers/layers_step_executor.gd", "", ResourceLoader.CACHE_MODE_REPLACE
	)
	var dock_scr: Variant = ResourceLoader.load(
		"res://addons/layers/layers_dock.gd", "", ResourceLoader.CACHE_MODE_REPLACE
	)
	if plugin_scr == null or sync_scr == null or exec_scr == null or dock_scr == null:
		_fail("One or more addon GDScripts failed to load.")
		return false

	if not _write_smoke_fixtures():
		return false

	# 2. Verify read-only inspector & context helper (layers_step_executor.gd v3.0.0)
	var exec: Variant = exec_scr.new()
	if exec == null:
		_fail("Failed to instantiate layers_step_executor.gd.")
		return false

	var feat_probe: Dictionary = {
		"id": "f_smoke_1",
		"title": "Smoke Player",
		"goal": "Move around arena smoothly with camera follow",
		"primaryAsset": SMOKE_SCENE_PATH,
		"scriptPaths": [SMOKE_SCRIPT_PATH],
		"coveredScope": ["WASD movement", "Jump impulse"],
		"tuningParams": ["move_speed = 8.0 m/s", "jump_impulse = 6.5 m/s"],
		"edgeCases": [
			{
				"index": 0,
				"rawText": "[STATE GUARD] Clamp sprint speed",
				"text": "Clamp sprint speed",
				"signedOff": false,
			},
			{
				"index": 1,
				"rawText": "[STATE GUARD] Reset jump on floor",
				"text": "Reset jump on floor",
				"signedOff": true,
			},
		],
		"openIssues": [
			{
				"id": "iss_1",
				"text": "%s:3 Player slides down ramp" % SMOKE_SCRIPT_PATH,
			}
		],
		"doneWhen": "F6 -> player moves cleanly with 0 console errors",
		"checkpointId": "cp_1",
		"isPlaytestPassed": false,
		"isCompleted": false,
	}

	var paths: Dictionary = exec.call("resolve_feature_paths", feat_probe, SMOKE_SCENE_PATH)
	if str(paths.get("primary_scene", "")) != SMOKE_SCENE_PATH:
		_fail("resolve_feature_paths missed primary_scene: %s" % str(paths))
		return false
	var resolved_scripts: Variant = paths.get("script_paths", PackedStringArray())
	if not (SMOKE_SCRIPT_PATH in resolved_scripts):
		_fail("resolve_feature_paths missed smoke_player.gd.")
		return false

	var eval_res: Dictionary = exec.call("evaluate_feature", feat_probe, null, SMOKE_SCENE_PATH)
	if str(eval_res.get("primary_scene", "")) != SMOKE_SCENE_PATH:
		_fail("evaluate_feature missed primary_scene.")
		return false
	var cache_before: Dictionary = exec.get("_eval_cache")
	if cache_before.is_empty():
		_fail("evaluate_feature did not populate _eval_cache.")
		return false
	exec.call("invalidate_eval_cache")
	var cache_after: Dictionary = exec.get("_eval_cache")
	if not cache_after.is_empty():
		_fail("invalidate_eval_cache did not clear _eval_cache.")
		return false

	var merged: Dictionary = exec.call(
		"merge_script_buffer_overrides",
		{SMOKE_SCRIPT_PATH: "# disk"},
		{SMOKE_SCRIPT_PATH: "# unsaved"}
	)
	if str(merged.get(SMOKE_SCRIPT_PATH, "")) != "# unsaved":
		_fail("merge_script_buffer_overrides did not prefer live buffer.")
		return false

	var scene_snap: Dictionary = exec.call(
		"capture_rich_scene_snapshot", null, PackedStringArray([SMOKE_SCENE_PATH])
	)
	var scene_snap_json: String = JSON.stringify(scene_snap)
	if scene_snap_json.find("CharacterBody3D") == -1 or scene_snap_json.find("CollisionShape3D") == -1:
		_fail("capture_rich_scene_snapshot missed scene hierarchy nodes: %s" % scene_snap_json)
		return false

	var input_snap: Dictionary = exec.call("capture_input_map_snapshot")
	if typeof(input_snap) != TYPE_DICTIONARY:
		_fail("capture_input_map_snapshot did not return Dictionary.")
		return false

	if not bool(exec.call("_is_ignored_godot_error_noise", "ERROR: progress_dialog.cpp: already open")):
		_fail("_is_ignored_godot_error_noise failed to filter editor noise.")
		return false
	if bool(exec.call("_is_ignored_godot_error_noise", "SCRIPT ERROR: Invalid get index 'hp' on base: Nil")):
		_fail("_is_ignored_godot_error_noise wrongly ignored real script error.")
		return false

	var jump_target: Dictionary = exec.call(
		"extract_issue_jump_target",
		"%s:3 Player slides down ramp" % SMOKE_SCRIPT_PATH,
		[SMOKE_SCRIPT_PATH]
	)
	if str(jump_target.get("path", "")) != SMOKE_SCRIPT_PATH or int(jump_target.get("line", -1)) != 3:
		_fail("extract_issue_jump_target failed: %s" % str(jump_target))
		return false

	var md: String = exec.call(
		"format_feature_context_markdown",
		feat_probe,
		{SMOKE_SCRIPT_PATH: "extends CharacterBody3D\n"},
		scene_snap,
		input_snap,
		["SCRIPT ERROR: Test error"]
	)
	for required_md in [
		"Smoke Player",
		"Goal:",
		"Tuning Variables",
		"move_speed = 8.0 m/s",
		"Playtest Guards",
		"[ ] Clamp sprint speed",
		"[x] Reset jump on floor",
		"Open Playtest Issues",
		"Player slides down ramp",
		"Done When",
		SMOKE_SCRIPT_PATH,
		"CharacterBody3D",
	]:
		if md.find(required_md) == -1:
			_fail("format_feature_context_markdown missing '%s'" % required_md)
			return false

	# 3. Verify 2-way Sync Client v3.0.0 surface + offline cache roundtrip
	var sync: Variant = sync_scr.new()
	if sync == null:
		_fail("Failed to instantiate layers_sync_client.gd.")
		return false
	for required_method in [
		"fetch_active_epic",
		"set_playtest_passed",
		"toggle_guard",
		"log_playtest_issue",
		"resolve_playtest_issue",
		"save_cached_epic",
		"load_cached_epic",
		"check_for_plugin_update",
		"download_and_apply_plugin_update",
	]:
		if not sync.has_method(required_method):
			sync.free()
			_fail("layers_sync_client missing method: %s" % required_method)
			return false
	for removed_method in [
		"build_feature",
		"direct_agent",
		"sync_live_scripts",
		"set_feature_built",
		"has_active_agent_request",
		"cancel_agent_request",
	]:
		if sync.has_method(removed_method):
			sync.free()
			_fail("layers_sync_client still exposes removed method: %s" % removed_method)
			return false

	var sample_payload: Dictionary = {
		"ok": true,
		"projectTitle": "Smoke Test Game",
		"releaseVersion": "v0.1",
		"epicPosition": 1,
		"totalEpics": 1,
		"arenaScenePath": SMOKE_SCENE_PATH,
		"activeEpic": {
			"id": "ep_1",
			"code": "E01",
			"title": "Movement",
			"features": [feat_probe],
		},
	}
	sync.call("save_cached_epic", sample_payload)
	var loaded_cache: Dictionary = sync.call("load_cached_epic")
	if str(loaded_cache.get("projectTitle", "")) != "Smoke Test Game":
		sync.free()
		_fail("load_cached_epic roundtrip mismatch: %s" % str(loaded_cache))
		return false
	sync.free()

	# 4. Verify Pure Spec, Playtest & 2-Way Dock UI (layers_dock.gd v3.0.0)
	var dock: Variant = dock_scr.new()
	if dock == null:
		_fail("Failed to instantiate layers_dock.gd.")
		return false
	dock.set("_executor", exec)
	dock.set("_payload", sample_payload)
	dock.call("_build_ui")

	var footer_box: Variant = dock.get("_footer_box")
	if footer_box == null:
		dock.free()
		_fail("_build_ui did not create _footer_box.")
		return false

	dock.call("_render_active_feature_workspace", feat_probe)

	# Gate button must always stay unlocked/visible even when not passed & guards unchecked
	if not bool((footer_box as Control).visible):
		dock.free()
		_fail("_footer_box hidden on unpassed feature.")
		return false
	var cta_btn: Button = dock.get("_primary_cta_btn") as Button
	if cta_btn == null or cta_btn.disabled or cta_btn.text.find("Playtest Passed") == -1:
		dock.free()
		_fail("Primary CTA button invalid on unpassed feature.")
		return false

	# Playtest guards render as CheckBox items, and Tuning Variables render inline
	var body_container: Node = dock.get("_body_container") as Node
	var guard_boxes: Array[CheckBox] = []
	_collect_checkboxes(body_container, guard_boxes)
	if guard_boxes.size() != 2:
		dock.free()
		_fail("Expected 2 CheckBox guards, got %d" % guard_boxes.size())
		return false

	var label_texts := PackedStringArray()
	_collect_labels_text(body_container, label_texts)
	var all_labels_joined: String = "\n".join(label_texts)
	if all_labels_joined.find("Tuning Variables") == -1 or all_labels_joined.find("move_speed = 8.0 m/s") == -1:
		dock.free()
		_fail("Expected Tuning Variables rendered inline in Godot Dock: %s" % all_labels_joined)
		return false

	# Resolve button exists for open [FIX] issue
	var resolve_btns: Array[Button] = []
	_collect_buttons_by_text(body_container, "Resolve", resolve_btns)
	if resolve_btns.is_empty():
		dock.free()
		_fail("Expected 'Resolve' button for open [FIX] issue.")
		return false

	# Optimistic local guard toggle, issue log, issue resolve, 1-click pass & reopen gate
	dock.call("_on_guard_toggled", true, feat_probe, 0, "[STATE GUARD] Clamp sprint speed")
	var guards_arr: Array = feat_probe.get("edgeCases", [])
	if not bool((guards_arr[0] as Dictionary).get("signedOff", false)):
		dock.free()
		_fail("_on_guard_toggled failed to update signedOff state.")
		return false

	dock.call("_submit_log_issue", feat_probe, "Jump sticks on ceiling")
	var issues_after_log: Array = feat_probe.get("openIssues", [])
	if issues_after_log.size() != 2:
		dock.free()
		_fail("_submit_log_issue did not append optimistic issue.")
		return false
	var guards_after_log: Array = feat_probe.get("edgeCases", [])
	if guards_after_log.size() != 3:
		dock.free()
		_fail("_submit_log_issue did not append [PLAYTEST GUARD] entry to edgeCases.")
		return false

	dock.call("_on_resolve_issue_pressed", feat_probe, "iss_1")
	var issues_after_resolve: Array = feat_probe.get("openIssues", [])
	if issues_after_resolve.size() != 1:
		dock.free()
		_fail("_on_resolve_issue_pressed did not remove iss_1.")
		return false

	var sync_probe: Variant = sync_scr.new()
	dock.set("_sync", sync_probe)
	dock.call("_on_primary_cta_pressed")
	if not bool(feat_probe.get("isPlaytestPassed", false)):
		sync_probe.free()
		dock.free()
		_fail("_on_primary_cta_pressed did not mark isPlaytestPassed=true.")
		return false
	var issues_after_pass: Array = feat_probe.get("openIssues", [])
	if not issues_after_pass.is_empty():
		sync_probe.free()
		dock.free()
		_fail("_on_primary_cta_pressed did not clear openIssues.")
		return false
	for g_pass in (feat_probe.get("edgeCases", []) as Array):
		if typeof(g_pass) == TYPE_DICTIONARY and not bool((g_pass as Dictionary).get("signedOff", false)):
			sync_probe.free()
			dock.free()
			_fail("_on_primary_cta_pressed did not sign off all edgeCases.")
			return false

	dock.call("_on_reopen_gate_pressed", feat_probe)
	if bool(feat_probe.get("isPlaytestPassed", true)):
		sync_probe.free()
		dock.free()
		_fail("_on_reopen_gate_pressed did not clear isPlaytestPassed.")
		return false
	var issues_after_reopen: Array = feat_probe.get("openIssues", [])
	if not issues_after_reopen.is_empty():
		sync_probe.free()
		dock.free()
		_fail("_on_reopen_gate_pressed resurrected resolved openIssues.")
		return false
	for g_reopen in (feat_probe.get("edgeCases", []) as Array):
		if typeof(g_reopen) == TYPE_DICTIONARY and not bool((g_reopen as Dictionary).get("signedOff", false)):
			sync_probe.free()
			dock.free()
			_fail("_on_reopen_gate_pressed unexpectedly wiped signedOff guards.")
			return false
	sync_probe.free()
	dock.set("_sync", null)

	dock.call("on_editor_scene_saved", SMOKE_SCENE_PATH)

	# Verify Open Scene & Open Script helpers handle single & multi paths cleanly
	var row_probe: HBoxContainer = HBoxContainer.new()
	dock.call(
		"_maybe_add_open_scene_button",
		row_probe,
		PackedStringArray([SMOKE_SCENE_PATH, "res://scenes/other.tscn"]),
		SMOKE_SCENE_PATH
	)
	dock.call(
		"_maybe_add_open_script_button",
		row_probe,
		PackedStringArray([SMOKE_SCRIPT_PATH])
	)
	if row_probe.get_child_count() != 2:
		row_probe.free()
		dock.free()
		_fail("Expected Open Scene (2) + Open Script buttons.")
		return false
	row_probe.free()

	# 5. Smart keyword real-file discovery & Web deep-link + Queued status parity
	var ai_fake_feat: Dictionary = {
		"id": "f_ai_fake",
		"title": "Player Movement & Dash",
		"primaryAsset": "res://scenes/fake_ai_player.tscn",
		"scriptPaths": ["res://scripts/fake_ai_player.gd"],
	}
	var smart_paths: Dictionary = exec.call("resolve_feature_paths", ai_fake_feat, SMOKE_SCENE_PATH)
	if not str(smart_paths.get("primary_scene", "")).is_empty():
		dock.free()
		_fail("resolve_feature_paths kept missing AI scene: %s" % str(smart_paths))
		return false
	var smart_scripts: Array = smart_paths.get("script_paths", [])
	if smart_scripts.has("res://scripts/fake_ai_player.gd") or not smart_scripts.has(SMOKE_SCRIPT_PATH):
		dock.free()
		_fail("resolve_feature_paths failed smart keyword discovery: %s" % str(smart_paths))
		return false

	var unmatched_feat: Dictionary = {
		"id": "f_unmatched",
		"title": "Inventory Crafting",
		"primaryAsset": "res://scenes/missing_inventory.tscn",
		"scriptPaths": ["res://scripts/missing_inventory.gd"],
	}
	var unmatched_paths: Dictionary = exec.call("resolve_feature_paths", unmatched_feat, SMOKE_SCENE_PATH)
	if not str(unmatched_paths.get("primary_scene", "")).is_empty() or not (unmatched_paths.get("script_paths", []) as Array).is_empty():
		dock.free()
		_fail("Expected unmatched feature to return empty scene/script paths cleanly: %s" % str(unmatched_paths))
		return false
	if str(unmatched_paths.get("arena_scene", "")) != SMOKE_SCENE_PATH:
		dock.free()
		_fail("Expected unmatched feature to preserve existing arena_scene.")
		return false

	var deep_link: String = str(dock.call("build_web_studio_deep_link", "https://henrycgithub.github.io/LAYERS-Agentic/", "proj_abc", "feat_xyz"))
	if deep_link != "https://henrycgithub.github.io/LAYERS-Agentic/?project=proj_abc&feature=feat_xyz":
		dock.free()
		_fail("build_web_studio_deep_link mismatch: %s" % deep_link)
		return false

	var queued_feat: Dictionary = {
		"id": "f_queued",
		"title": "Queued Loot Pickup",
		"goal": "Pick up loot crystals cleanly",
		"edgeCases": [
			{"index": 0, "rawText": "[STATE GUARD] Magnetize within 2m", "text": "Magnetize within 2m", "signedOff": false}
		],
		"openIssues": [],
		"isPlaytestPassed": false,
		"isCompleted": false,
	}
	dock.call("_render_active_feature_workspace", queued_feat)
	var queued_labels := PackedStringArray()
	_collect_labels_text(body_container, queued_labels)
	if not ("\n".join(queued_labels)).contains("Queued"):
		dock.free()
		_fail("Expected untouched feature in Godot Dock to render 'Queued' status: %s" % ("\n".join(queued_labels)))
		return false

	dock.free()
	return true
