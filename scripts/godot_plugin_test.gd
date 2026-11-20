extends SceneTree


class _MockEditorInterface extends RefCounted:
	var base_ctrl: Control = Control.new()
	var edited_root: Node = null
	var played_scene: String = ""
	var saved_count: int = 0

	func get_base_control() -> Control:
		return base_ctrl

	func get_edited_scene_root() -> Node:
		return edited_root

	func save_scene() -> void:
		saved_count += 1

	func play_custom_scene(p: String) -> void:
		played_scene = p

	func get_resource_filesystem() -> Variant:
		return null


func _init() -> void:
	call_deferred("_run_test")


func _write_text(res_path: String, content: String) -> bool:
	var dir_abs: String = ProjectSettings.globalize_path(res_path.get_base_dir())
	if not DirAccess.dir_exists_absolute(dir_abs):
		DirAccess.make_dir_recursive_absolute(dir_abs)
	var f: FileAccess = FileAccess.open(res_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(content)
	f.close()
	return true


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	quit(1)


func _run_test() -> void:
	# 1. Strict Godot 4.7.2 load/compile check across all plugin scripts
	var plugin_scripts: PackedStringArray = PackedStringArray([
		"res://addons/layers/layers_step_executor.gd",
		"res://addons/layers/layers_sync_client.gd",
		"res://addons/layers/layers_dock.gd",
		"res://addons/layers/layers_plugin.gd",
	])
	for sp in plugin_scripts:
		var scr: Variant = ResourceLoader.load(sp, "", ResourceLoader.CACHE_MODE_IGNORE)
		if scr == null or not (scr is GDScript):
			_fail("Could not load plugin script %s" % sp)
			return
		var gds := scr as GDScript
		if not sp.ends_with("layers_plugin.gd") and not gds.can_instantiate():
			_fail("Plugin script cannot instantiate: %s" % sp)
			return

	var exec_scr: GDScript = ResourceLoader.load("res://addons/layers/layers_step_executor.gd", "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	var exec: RefCounted = exec_scr.new()
	if exec == null:
		_fail("Could not instantiate layers_step_executor.gd")
		return

	var sync_scr: GDScript = ResourceLoader.load("res://addons/layers/layers_sync_client.gd", "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	var sync_client: Node = sync_scr.new() as Node
	if sync_client == null:
		_fail("Could not instantiate layers_sync_client.gd")
		return
	get_root().add_child(sync_client)

	var dock_scr: GDScript = ResourceLoader.load("res://addons/layers/layers_dock.gd", "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	var dock: Control = dock_scr.new() as Control
	if dock == null:
		_fail("Could not instantiate layers_dock.gd")
		return
	get_root().add_child(dock)

	# 2. Test TCPServer Google Sign-In Loopback (400 bad state -> 200 valid state & token)
	var auth_info_v: Variant = sync_client.call("start_google_sign_in", "TestProject", "https://example.com/", false)
	var auth_info: Dictionary = auth_info_v as Dictionary if typeof(auth_info_v) == TYPE_DICTIONARY else {}
	if not bool(auth_info.get("ok", false)):
		_fail("start_google_sign_in failed: %s" % str(auth_info))
		return
	var auth_port: int = int(auth_info.get("port", 0))
	var auth_state: String = str(auth_info.get("state", ""))
	if auth_port <= 0 or auth_state.is_empty():
		_fail("Invalid loopback auth port/state.")
		return

	var bad_resp: String = await _send_loopback_http(sync_client, auth_port, "/callback?state=wrong_state&token=lyr_test_1234567890123456&project=Bad")
	if not ("400" in bad_resp):
		_fail("Expected 400 on bad state callback, got: %s" % bad_resp)
		return
	if bool(sync_client.call("has_link_token")):
		_fail("Token must NOT be saved on invalid state callback.")
		return

	var valid_token := "lyr_test_token_abcdef1234567890"
	var ok_resp: String = await _send_loopback_http(sync_client, auth_port, "/callback?state=%s&token=%s&project=TestGame" % [auth_state, valid_token])
	if not ("200" in ok_resp):
		_fail("Expected 200 on valid loopback callback, got: %s" % ok_resp)
		return
	if str(sync_client.call("get_link_token")) != valid_token:
		_fail("Expected link token to persist after loopback 200.")
		return
	sync_client.call("clear_link_token")

	# 3. Test 3D build_epic bundle application + InputMap + SceneTree root verification
	var player3d_code := """extends CharacterBody3D

@export var move_speed: float = 6.4

func _physics_process(_delta: float) -> void:
\tvar dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
\tvelocity.x = dir.x * move_speed
\tvelocity.z = dir.y * move_speed
\tmove_and_slide()
"""
	var bundle_3d := {
		"mode": "build_epic",
		"dimension": "dim3d",
		"summary": "Built test 3D player epic",
		"arenaScenePath": "res://scenes/test_3d.tscn",
		"epicScenePath": "res://scenes/test_3d.tscn",
		"scriptUpdates": [
			{
				"resPath": "res://scripts/test_player_3d.gd",
				"attachTo": "Player",
				"scenePath": "res://scenes/test_3d.tscn",
				"language": "gdscript",
				"content": player3d_code,
			},
		],
		"sceneOps": [
			{"op": "ensure_node", "scenePath": "res://scenes/test_3d.tscn", "parentPath": ".", "nodeName": "Test3D", "nodeType": "Node3D"},
			{"op": "ensure_node", "scenePath": "res://scenes/test_3d.tscn", "parentPath": ".", "nodeName": "Player", "nodeType": "CharacterBody3D"},
			{"op": "attach_script", "scenePath": "res://scenes/test_3d.tscn", "nodePath": "Player", "scriptPath": "res://scripts/test_player_3d.gd"},
		],
		"inputOps": [
			{"action": "move_left", "keys": ["A"], "overwrite": true},
			{"action": "move_right", "keys": ["D"], "overwrite": true},
		],
	}
	var res3d_v: Variant = exec.call("apply_agent_bundle", null, null, bundle_3d, "res://scenes/test_3d.tscn")
	var res3d: Dictionary = res3d_v as Dictionary if typeof(res3d_v) == TYPE_DICTIONARY else {}
	if not bool(res3d.get("ok", false)) or not FileAccess.file_exists("res://scenes/test_3d.tscn"):
		_fail("3D apply_agent_bundle failed: %s" % str(res3d))
		return
	var ps3d: PackedScene = ResourceLoader.load("res://scenes/test_3d.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps3d == null:
		_fail("Could not load generated 3D scene.")
		return
	var root3d: Node = ps3d.instantiate()
	var pnode3d: Node = root3d.get_node_or_null("Player")
	if not (root3d is Node3D) or not (pnode3d is CharacterBody3D):
		root3d.free()
		_fail("3D scene structure mismatch.")
		return
	root3d.free()

	# 4. Test 2D build_epic bundle application
	var player2d_code := """extends CharacterBody2D

@export var move_speed: float = 240.0

func _physics_process(_delta: float) -> void:
\tvar dir: float = Input.get_axis("move_left", "move_right")
\tvelocity.x = dir * move_speed
\tmove_and_slide()
"""
	var bundle_2d := {
		"mode": "build_epic",
		"dimension": "dim2d",
		"summary": "Built test 2D player epic",
		"arenaScenePath": "res://scenes/test_2d.tscn",
		"epicScenePath": "res://scenes/test_2d.tscn",
		"scriptUpdates": [
			{
				"resPath": "res://scripts/test_player_2d.gd",
				"attachTo": ".",
				"scenePath": "res://scenes/test_2d.tscn",
				"language": "gdscript",
				"content": player2d_code,
			},
		],
		"sceneOps": [
			{"op": "ensure_node", "scenePath": "res://scenes/test_2d.tscn", "parentPath": ".", "nodeName": "TestPlayer2D", "nodeType": "CharacterBody2D"},
			{"op": "attach_script", "scenePath": "res://scenes/test_2d.tscn", "nodePath": ".", "scriptPath": "res://scripts/test_player_2d.gd"},
		],
		"inputOps": [],
	}
	var res2d_v: Variant = exec.call("apply_agent_bundle", null, null, bundle_2d, "res://scenes/test_2d.tscn")
	var res2d: Dictionary = res2d_v as Dictionary if typeof(res2d_v) == TYPE_DICTIONARY else {}
	if not bool(res2d.get("ok", false)) or not FileAccess.file_exists("res://scenes/test_2d.tscn"):
		_fail("2D apply_agent_bundle failed: %s" % str(res2d))
		return
	var ps2d: PackedScene = ResourceLoader.load("res://scenes/test_2d.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps2d == null:
		_fail("Could not load generated 2D scene.")
		return
	var root2d: Node = ps2d.instantiate()
	if not (root2d is CharacterBody2D):
		root2d.free()
		_fail("2D scene root expected CharacterBody2D.")
		return
	root2d.free()

	# 5. Test collect_godot_project_context static helper
	var live_ctx_v: Variant = exec_scr.collect_godot_project_context(null, ["SCRIPT ERROR: test line"])
	var live_ctx: Dictionary = live_ctx_v as Dictionary if typeof(live_ctx_v) == TYPE_DICTIONARY else {}
	var sfiles_v: Variant = live_ctx.get("scene_files", [])
	var gfiles_v: Variant = live_ctx.get("script_files", [])
	if typeof(sfiles_v) != TYPE_ARRAY or not (sfiles_v as Array).has("res://scenes/test_3d.tscn"):
		_fail("collect_godot_project_context missing scene_files: %s" % str(live_ctx))
		return
	if typeof(gfiles_v) != TYPE_ARRAY or not (gfiles_v as Array).has("res://scripts/test_player_2d.gd"):
		_fail("collect_godot_project_context missing script_files: %s" % str(live_ctx))
		return

	# 6. Test FIFO mutation queue & get_epic deduplication on sync_client
	sync_client.call("save_link_token", "lyr_test_queue_token_1234567890")
	sync_client.set("_is_busy", true)
	sync_client.call("push_epic_mutation", {"action": "toggle_check", "checkId": "c1", "passed": true})
	sync_client.call("push_epic_mutation", {"action": "toggle_check", "checkId": "c2", "passed": true})
	sync_client.call("push_epic_mutation", {"action": "update_tuning", "key": "move_speed", "value": "8.0"})
	if int(sync_client.call("get_pending_request_count")) != 3:
		_fail("Expected 3 queued mutations in FIFO queue, got: %s" % str(sync_client.call("get_pending_request_count")))
		return
	sync_client.call("fetch_active_epic", {}, "e01")
	sync_client.call("fetch_active_epic", {}, "e02")
	if int(sync_client.call("get_pending_request_count")) != 4:
		_fail("Expected get_epic deduplication to keep 4 pending requests, got: %s" % str(sync_client.call("get_pending_request_count")))
		return
	sync_client.set("_is_busy", false)
	sync_client.call("clear_pending_requests")
	sync_client.call("clear_link_token")

	# 7. Test live @export tuning updates in both 3D (m/s) and 2D (px/s)
	var tune3d_v: Variant = exec.call("apply_live_export_tuning", null, "move_speed", "9.25", "m/s", "res://scenes/test_3d.tscn")
	var tune3d: Dictionary = tune3d_v as Dictionary if typeof(tune3d_v) == TYPE_DICTIONARY else {}
	if not bool(tune3d.get("ok", false)):
		_fail("3D apply_live_export_tuning failed: %s" % str(tune3d))
		return
	var txt3d_after: String = FileAccess.get_file_as_string("res://scripts/test_player_3d.gd")
	if not ("@export var move_speed: float = 9.25" in txt3d_after):
		_fail("3D script missing updated @export move_speed=9.25: %s" % txt3d_after)
		return
	var ps3d_tuned: PackedScene = ResourceLoader.load("res://scenes/test_3d.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps3d_tuned == null:
		_fail("Could not reload 3D scene after tuning.")
		return
	var root3d_tuned: Node = ps3d_tuned.instantiate()
	var pnode3d_tuned: Node = root3d_tuned.get_node_or_null("Player")
	if pnode3d_tuned == null or absf(float(pnode3d_tuned.get("move_speed")) - 9.25) >= 0.001:
		var got3d: Variant = pnode3d_tuned.get("move_speed") if pnode3d_tuned != null else null
		root3d_tuned.free()
		_fail("3D scene node move_speed expected 9.25, got: %s" % str(got3d))
		return
	root3d_tuned.free()

	var tune2d_v: Variant = exec.call("apply_live_export_tuning", null, "move_speed", "310", "px/s", "res://scenes/test_2d.tscn")
	var tune2d: Dictionary = tune2d_v as Dictionary if typeof(tune2d_v) == TYPE_DICTIONARY else {}
	if not bool(tune2d.get("ok", false)):
		_fail("2D apply_live_export_tuning failed: %s" % str(tune2d))
		return
	var ps2d_tuned: PackedScene = ResourceLoader.load("res://scenes/test_2d.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps2d_tuned == null:
		_fail("Could not reload 2D scene after tuning.")
		return
	var root2d_tuned: Node = ps2d_tuned.instantiate()
	if absf(float(root2d_tuned.get("move_speed")) - 310.0) >= 0.001:
		var got2d: Variant = root2d_tuned.get("move_speed")
		root2d_tuned.free()
		_fail("2D scene root move_speed expected 310.0, got: %s" % str(got2d))
		return
	root2d_tuned.free()

	# 8. Test 4-Step Dock Flow & Primary CTA State Machine
	var mock_editor := _MockEditorInterface.new()
	dock.editor_interface = mock_editor
	var dock_sync: Node = dock.get("_sync_client") as Node
	dock_sync.call("save_link_token", "lyr_test_dock_flow_1234567890")
	dock_sync.set("_is_busy", true)

	var test_payload := {
		"ok": true,
		"projectTitle": "Shellbreaker",
		"dimension": "dim3d",
		"releaseVersion": "v0.1",
		"epicPosition": 1,
		"totalEpics": 2,
		"arenaScenePath": "res://scenes/test_3d.tscn",
		"releaseEpicsSummary": [
			{"id": "epic_e01", "code": "E01", "title": "Player Movement", "isPassed": false, "openFixesCount": 0},
			{"id": "epic_e02", "code": "E02", "title": "Claw Dash", "isPassed": false, "openFixesCount": 0},
		],
		"activeEpic": {
			"id": "epic_e01",
			"code": "E01",
			"title": "Player Movement",
			"goal": "Move across the test arena smoothly.",
			"isPassed": false,
			"openFixes": [],
			"openFixesCount": 0,
			"passedChecksCount": 0,
			"checks": [
				{"id": "c1", "text": "Hold WASD -> Moves smoothly", "passed": false},
				{"id": "c2", "text": "Collide wall -> Slides cleanly", "passed": false},
			],
			"tuning": [
				{"key": "move_speed", "value": "9.25", "unit": "m/s"},
			],
		},
	}
	dock.call("_on_epic_updated", test_payload)

	var cta1_v: Variant = dock.call("compute_primary_cta_state")
	var cta1: Dictionary = cta1_v as Dictionary if typeof(cta1_v) == TYPE_DICTIONARY else {}
	if str(cta1.get("mode", "")) != "build" or str(cta1.get("text", "")) != "⚡ Build E01":
		_fail("Expected build CTA '⚡ Build E01', got: %s" % str(cta1))
		return

	var fix_id: String = str(dock.call("log_epic_fix_text", "Claw dash clips corner"))
	if fix_id.is_empty():
		_fail("Expected non-empty fix_id from log_epic_fix_text.")
		return
	var cta2_v: Variant = dock.call("compute_primary_cta_state")
	var cta2: Dictionary = cta2_v as Dictionary if typeof(cta2_v) == TYPE_DICTIONARY else {}
	if str(cta2.get("mode", "")) != "fix" or int(cta2.get("issue_count", 0)) != 1 or str(cta2.get("text", "")) != "🔧 Fix E01 (1)":
		_fail("Expected fix CTA with count 1, got: %s" % str(cta2))
		return

	dock.call("inject_test_error", "SCRIPT ERROR: test crash (res://scripts/test_player_3d.gd:9 in _physics_process)")
	var cta3_v: Variant = dock.call("compute_primary_cta_state")
	var cta3: Dictionary = cta3_v as Dictionary if typeof(cta3_v) == TYPE_DICTIONARY else {}
	if str(cta3.get("mode", "")) != "fix" or int(cta3.get("issue_count", 0)) != 2 or str(cta3.get("text", "")) != "🔧 Fix E01 (2)":
		_fail("Expected fix CTA with count 2, got: %s" % str(cta3))
		return

	dock.call("_on_agent_bundle_received", bundle_3d, test_payload)
	var errs_after_build: Variant = dock.call("_collect_recent_errors")
	if typeof(errs_after_build) != TYPE_ARRAY or not (errs_after_build as Array).is_empty():
		_fail("Expected captured errors cleared after clean agent bundle, got: %s" % str(errs_after_build))
		return
	var undo_btn_v: Variant = dock.get("_undo_btn")
	if undo_btn_v is Button and (undo_btn_v as Button).disabled:
		_fail("Expected Undo button enabled after _on_agent_bundle_received.")
		return
	var cta4_v: Variant = dock.call("compute_primary_cta_state")
	var cta4: Dictionary = cta4_v as Dictionary if typeof(cta4_v) == TYPE_DICTIONARY else {}
	if str(cta4.get("text", "")) != "🔧 Fix E01 (1)":
		_fail("Expected CTA '🔧 Fix E01 (1)' for remaining [FIX], got: %s" % str(cta4))
		return

	dock.call("resolve_epic_fix_by_id", fix_id)
	var cta5_v: Variant = dock.call("compute_primary_cta_state")
	var cta5: Dictionary = cta5_v as Dictionary if typeof(cta5_v) == TYPE_DICTIONARY else {}
	if str(cta5.get("mode", "")) != "build" or str(cta5.get("text", "")) != "⚡ Build E01":
		_fail("Expected CTA back to '⚡ Build E01' after resolving [FIX], got: %s" % str(cta5))
		return

	dock.call("toggle_epic_check_by_id", "c1", true)
	dock.call("toggle_epic_check_by_id", "c2", true)
	var cta6_v: Variant = dock.call("compute_primary_cta_state")
	var cta6: Dictionary = cta6_v as Dictionary if typeof(cta6_v) == TYPE_DICTIONARY else {}
	if str(cta6.get("mode", "")) != "pass" or str(cta6.get("text", "")) != "✓ Pass E01 →":
		_fail("Expected pass CTA '✓ Pass E01 →', got: %s" % str(cta6))
		return

	dock.call("inject_test_error", "SCRIPT ERROR: late error while checks passed")
	var cta7_v: Variant = dock.call("compute_primary_cta_state")
	var cta7: Dictionary = cta7_v as Dictionary if typeof(cta7_v) == TYPE_DICTIONARY else {}
	if str(cta7.get("text", "")) != "🔧 Fix E01 (1)":
		_fail("Expected runtime error to override pass CTA, got: %s" % str(cta7))
		return

	dock.call("clear_captured_errors")
	var cta8_v: Variant = dock.call("compute_primary_cta_state")
	var cta8: Dictionary = cta8_v as Dictionary if typeof(cta8_v) == TYPE_DICTIONARY else {}
	if str(cta8.get("text", "")) != "✓ Pass E01 →":
		_fail("Expected pass CTA restored after clear_captured_errors, got: %s" % str(cta8))
		return

	dock.call("_on_play_pressed")
	if mock_editor.played_scene != "res://scenes/test_3d.tscn":
		_fail("Expected _on_play_pressed to launch 'res://scenes/test_3d.tscn', got: '%s'" % mock_editor.played_scene)
		return

	dock.call("_on_undo_pressed")
	if undo_btn_v is Button and not (undo_btn_v as Button).disabled:
		_fail("Expected Undo button disabled after _on_undo_pressed.")
		return

	dock_sync.set("_is_busy", false)
	dock_sync.call("clear_pending_requests")
	dock_sync.call("clear_link_token")
	mock_editor.base_ctrl.free()

	# 9. Test fresh hot-reload when cached script has a pending queue_free instance
	var hot_path := "res://tmp_hot_dock.gd"
	if not _write_text(hot_path, "@tool\nextends VBoxContainer\nvar editor_interface: Variant = null\n"):
		_fail("Could not write temporary hot dock script.")
		return
	var old_scr: GDScript = load(hot_path) as GDScript
	var old_dock: Control = old_scr.new() as Control
	get_root().add_child(old_dock)
	_write_text(hot_path, "@tool\nextends VBoxContainer\nvar editor_interface: Variant = null\nvar undo_redo: Variant = null\n")
	old_dock.queue_free()

	var plugin_scr: GDScript = ResourceLoader.load("res://addons/layers/layers_plugin.gd", "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	var reloaded_scr_v: Variant = plugin_scr.call("load_fresh_script", hot_path)
	if not (reloaded_scr_v is GDScript):
		_fail("load_fresh_script returned invalid script for %s" % hot_path)
		return
	var reloaded_gds: GDScript = reloaded_scr_v as GDScript
	var reloaded_inst: Control = reloaded_gds.new() as Control
	if reloaded_inst == null:
		_fail("Expected Control instance from reloaded hot dock script.")
		return
	if not ("undo_redo" in reloaded_inst):
		reloaded_inst.free()
		_fail("Reloaded hot dock instance missing 'undo_redo' property.")
		return
	reloaded_inst.free()

	# 10. Test targeted .gd patches, whitespace fallback, sibling @export guard & scoped liveScripts
	var base_scoped_code := "extends CharacterBody3D\n\n@export var move_speed: float = 6.4\n\nfunc _physics_process(_delta: float) -> void:\n\tmove_and_slide()\n"
	if not _write_text("res://scripts/scoped_player.gd", base_scoped_code):
		_fail("Could not write res://scripts/scoped_player.gd.")
		return
	var scoped_tscn := "[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"Script\" path=\"res://scripts/scoped_player.gd\" id=\"1_sp\"]\n\n[node name=\"ScopedArena\" type=\"Node3D\"]\nscript = ExtResource(\"1_sp\")\n"
	if not _write_text("res://scenes/scoped_arena.tscn", scoped_tscn):
		_fail("Could not write res://scenes/scoped_arena.tscn.")
		return
	_write_text("res://scripts/aaa_filler_1.gd", "extends Node\n")
	_write_text("res://scripts/aaa_filler_2.gd", "extends Node\n")
	_write_text("res://scripts/aaa_filler_3.gd", "extends Node\n")

	# 10a. Exact patch match in apply_agent_bundle + compile verification
	var patch_bundle := {
		"mode": "build_feature",
		"dimension": "dim3d",
		"preserveExports": ["move_speed"],
		"scriptUpdates": [
			{
				"resPath": "res://scripts/scoped_player.gd",
				"patches": [
					{
						"find": "@export var move_speed: float = 6.4",
						"replace": "@export var move_speed: float = 6.4\n@export var dash_distance: float = 4.0",
					},
					{
						"find": "func _physics_process(_delta: float) -> void:\n\tmove_and_slide()",
						"replace": "func _physics_process(_delta: float) -> void:\n\tif Input.is_action_just_pressed(\"ui_accept\"):\n\t\tvelocity.x = dash_distance\n\tmove_and_slide()",
					},
				],
			},
		],
		"sceneOps": [],
		"inputOps": [],
	}
	var patch_res_v: Variant = exec.call("apply_agent_bundle", null, null, patch_bundle, "res://scenes/scoped_arena.tscn")
	var patch_res: Dictionary = patch_res_v as Dictionary if typeof(patch_res_v) == TYPE_DICTIONARY else {}
	if not bool(patch_res.get("ok", false)):
		_fail("10a targeted patch apply_agent_bundle failed: %s" % str(patch_res))
		return
	var applied_list: Variant = patch_res.get("applied_scripts", [])
	if typeof(applied_list) != TYPE_PACKED_STRING_ARRAY and typeof(applied_list) != TYPE_ARRAY:
		_fail("10a invalid applied_scripts: %s" % str(patch_res))
		return
	if not ("res://scripts/scoped_player.gd" in applied_list):
		_fail("10a expected res://scripts/scoped_player.gd in applied_scripts: %s" % str(applied_list))
		return
	var patched_disk: String = FileAccess.get_file_as_string("res://scripts/scoped_player.gd")
	if not ("@export var move_speed: float = 6.4" in patched_disk) or not ("@export var dash_distance: float = 4.0" in patched_disk):
		_fail("10a missing preserved/added @export vars on disk: %s" % patched_disk)
		return
	var compile_patched: Dictionary = exec.call("check_gdscript_compiles", patched_disk) as Dictionary
	if not bool(compile_patched.get("ok", false)):
		_fail("10a patched script did not compile: %s" % str(compile_patched))
		return

	# 10b. Whitespace/indentation-tolerant patch fallback (spaces in find -> tab-indented script)
	var ws_res_v: Variant = exec.call("apply_script_patches", patched_disk, [
		{
			"find": "    if Input.is_action_just_pressed(\"ui_accept\"):\n        velocity.x = dash_distance\n    move_and_slide()",
			"replace": "    if Input.is_action_just_pressed(\"ui_accept\"):\n        velocity.x = dash_distance * 1.2\n    move_and_slide()",
		},
	])
	var ws_res: Dictionary = ws_res_v as Dictionary if typeof(ws_res_v) == TYPE_DICTIONARY else {}
	if not bool(ws_res.get("ok", false)):
		_fail("10b whitespace fallback apply_script_patches failed: %s" % str(ws_res))
		return
	var ws_content: String = str(ws_res.get("content", ""))
	if not ("\tvelocity.x = dash_distance * 1.2" in ws_content):
		_fail("10b expected re-indented tab block, got: %s" % ws_content)
		return
	var compile_ws: Dictionary = exec.call("check_gdscript_compiles", ws_content) as Dictionary
	if not bool(compile_ws.get("ok", false)):
		_fail("10b whitespace-fallback output failed compile: %s" % str(compile_ws))
		return

	# 10c. Missing patch anchor fails cleanly without touching disk
	var miss_bundle := {
		"mode": "build_feature",
		"dimension": "dim3d",
		"scriptUpdates": [
			{
				"resPath": "res://scripts/scoped_player.gd",
				"patches": [{ "find": "func nonexistent_anchor():", "replace": "pass" }],
			},
		],
	}
	var miss_res_v: Variant = exec.call("apply_agent_bundle", null, null, miss_bundle, "res://scenes/scoped_arena.tscn")
	var miss_res: Dictionary = miss_res_v as Dictionary if typeof(miss_res_v) == TYPE_DICTIONARY else {}
	if bool(miss_res.get("ok", true)):
		_fail("10c expected ok == false on PATCH MISMATCH: %s" % str(miss_res))
		return
	var miss_errs_str: String = " ".join(miss_res.get("compile_errors", PackedStringArray()))
	if not ("PATCH MISMATCH" in miss_errs_str):
		_fail("10c expected PATCH MISMATCH in compile_errors, got: %s" % str(miss_res))
		return
	if FileAccess.get_file_as_string("res://scripts/scoped_player.gd") != patched_disk:
		_fail("10c file on disk should be unchanged after PATCH MISMATCH.")
		return

	# 10d. Sibling @export preservation guard blocks destructive content replacement
	var reg_bundle := {
		"mode": "build_feature",
		"dimension": "dim3d",
		"preserveExports": ["move_speed"],
		"scriptUpdates": [
			{
				"resPath": "res://scripts/scoped_player.gd",
				"content": "extends CharacterBody3D\n@export var dash_distance: float = 4.0\nfunc _ready() -> void:\n\tpass\n",
			},
		],
	}
	var reg_res_v: Variant = exec.call("apply_agent_bundle", null, null, reg_bundle, "res://scenes/scoped_arena.tscn")
	var reg_res: Dictionary = reg_res_v as Dictionary if typeof(reg_res_v) == TYPE_DICTIONARY else {}
	if bool(reg_res.get("ok", true)):
		_fail("10d expected ok == false on SIBLING REGRESSION: %s" % str(reg_res))
		return
	var reg_errs_str: String = " ".join(reg_res.get("compile_errors", PackedStringArray()))
	if not ("SIBLING REGRESSION" in reg_errs_str) or not ("move_speed" in reg_errs_str):
		_fail("10d expected SIBLING REGRESSION + move_speed in compile_errors: %s" % str(reg_res))
		return
	if FileAccess.get_file_as_string("res://scripts/scoped_player.gd") != patched_disk:
		_fail("10d file on disk must be unchanged after SIBLING REGRESSION.")
		return

	# 10e. read_scoped_project_scripts prioritizes sceneOwnership scripts ahead of aaa_filler_* scripts
	var scoped_v: Variant = exec.call("read_scoped_project_scripts", ["res://scenes/scoped_arena.tscn"], "res://", null, 2)
	var scoped_dict: Dictionary = scoped_v as Dictionary if typeof(scoped_v) == TYPE_DICTIONARY else {}
	if scoped_dict.size() > 2 or not scoped_dict.has("res://scripts/scoped_player.gd"):
		_fail("10e expected <= 2 scripts prioritizing res://scripts/scoped_player.gd, got keys: %s" % str(scoped_dict.keys()))
		return
	var scoped_keys: Array = scoped_dict.keys()
	if scoped_keys.is_empty() or str(scoped_keys[0]) != "res://scripts/scoped_player.gd":
		_fail("10e expected first scoped key to be res://scripts/scoped_player.gd, got: %s" % str(scoped_keys))
		return

	# 11. Test 4-tier Feature Dock Flow & locked [v0.1] baseline guard
	var mock_ed_4t := _MockEditorInterface.new()
	dock.editor_interface = mock_ed_4t
	dock_sync.save_link_token("lyr_test_dock_4t_1234567890")
	dock_sync.set("_is_busy", true)
	dock_sync.call("clear_pending_requests")

	var payload_4t := {
		"ok": true,
		"projectTitle": "Shellbreaker 4T",
		"dimension": "dim3d",
		"releaseVersion": "v0.2",
		"epicPosition": 1,
		"totalEpics": 2,
		"arenaScenePath": "res://scenes/scoped_arena.tscn",
		"releaseEpicsSummary": [
			{"id": "epic_e01", "code": "E01", "title": "Player Movement", "isPassed": false, "openFixesCount": 0, "featuresCount": 2, "passedFeaturesCount": 1},
		],
		"activeEpicFeatures": [
			{"id": "f01", "code": "F01", "title": "8-Way Walk", "introducedIn": "v0.1", "status": "passed", "isLockedBaseline": true, "isPassed": true, "openFixesCount": 0},
			{"id": "f02", "code": "F02", "title": "Armored Claw Dash", "introducedIn": "v0.1", "status": "active", "isLockedBaseline": false, "isPassed": false, "openFixesCount": 0},
		],
		"activeEpic": {
			"id": "epic_e01",
			"code": "E01",
			"title": "Player Movement",
			"goal": "Own locomotion and dash.",
			"isPassed": false,
			"sceneOwnership": [
				{"path": "res://scenes/scoped_arena.tscn", "role": "Arena room"},
				{"path": "res://scripts/scoped_player.gd", "role": "Player movement"},
			],
			"openFixes": [],
			"openFixesCount": 0,
			"checks": [],
			"tuning": [],
		},
		"activeFeature": {
			"id": "f02",
			"code": "F02",
			"title": "Armored Claw Dash",
			"introducedIn": "v0.1",
			"sliceTime": "60 min",
			"status": "active",
			"isLockedBaseline": false,
			"isPassed": false,
			"goal": "Forward 4 m commitment dash.",
			"releaseDelta": "+ Refund dash on armor break",
			"tuning": [
				{"key": "dash_distance", "value": "4.0", "unit": "m"},
			],
			"checks": [
				{"id": "f02_c1", "text": "Tap Space -> Dashes 4 m", "passed": false},
			],
			"effectiveChecks": [
				{"id": "f02_c1", "text": "Tap Space -> Dashes 4 m", "passed": false},
			],
			"openFixes": [],
			"openFixesCount": 0,
		},
	}
	dock.call("_on_epic_updated", payload_4t)

	var feat_sel_v: Variant = dock.get("_feature_selector")
	if not (feat_sel_v is OptionButton):
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected _feature_selector OptionButton on dock.")
		return
	var feat_sel := feat_sel_v as OptionButton
	if not feat_sel.visible or feat_sel.item_count != 2:
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected visible _feature_selector with 2 items, visible=%s count=%d" % [str(feat_sel.visible), feat_sel.item_count])
		return
	var sel_fid: String = str(feat_sel.get_item_metadata(feat_sel.selected))
	if sel_fid != "f02":
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected selected feature metadata 'f02', got '%s'" % sel_fid)
		return

	var cta_f02_v: Variant = dock.call("compute_primary_cta_state")
	var cta_f02: Dictionary = cta_f02_v as Dictionary if typeof(cta_f02_v) == TYPE_DICTIONARY else {}
	if str(cta_f02.get("mode", "")) != "build" or str(cta_f02.get("text", "")) != "⚡ Build F02":
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected Feature CTA '⚡ Build F02', got: %s" % str(cta_f02))
		return

	var f02_fix_id: String = str(dock.call("log_epic_fix_text", "Dash clips pillar"))
	if f02_fix_id.is_empty():
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected non-empty f02_fix_id.")
		return
	var cta_f02_fix: Dictionary = dock.call("compute_primary_cta_state") as Dictionary
	if str(cta_f02_fix.get("mode", "")) != "fix" or str(cta_f02_fix.get("text", "")) != "🔧 Fix F02 (1)":
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected Feature fix CTA '🔧 Fix F02 (1)', got: %s" % str(cta_f02_fix))
		return
	var pending_v: Variant = dock_sync.get("_pending_requests")
	var pending_arr: Array = pending_v as Array if typeof(pending_v) == TYPE_ARRAY else []
	if pending_arr.is_empty() or not ("\"featureId\":\"f02\"" in str((pending_arr[pending_arr.size() - 1] as Dictionary).get("body", ""))):
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected queued log_fix mutation to contain featureId f02: %s" % str(pending_arr))
		return

	dock.call("resolve_epic_fix_by_id", f02_fix_id)
	var cta_f02_res: Dictionary = dock.call("compute_primary_cta_state") as Dictionary
	if str(cta_f02_res.get("mode", "")) != "build" or str(cta_f02_res.get("text", "")) != "⚡ Build F02":
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected Feature CTA restored to '⚡ Build F02', got: %s" % str(cta_f02_res))
		return

	dock.call("toggle_epic_check_by_id", "f02_c1", true)
	var cta_f02_pass: Dictionary = dock.call("compute_primary_cta_state") as Dictionary
	if str(cta_f02_pass.get("mode", "")) != "pass" or str(cta_f02_pass.get("text", "")) != "✓ Pass F02 →":
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected Feature pass CTA '✓ Pass F02 →', got: %s" % str(cta_f02_pass))
		return

	# Locked [v0.1] baseline guard on f01
	var locked_payload := payload_4t.duplicate(true)
	locked_payload["activeFeature"] = {
		"id": "f01",
		"code": "F01",
		"title": "8-Way Walk",
		"introducedIn": "v0.1",
		"status": "passed",
		"isLockedBaseline": true,
		"isPassed": true,
		"goal": "Baseline walk.",
		"tuning": [{"key": "move_speed", "value": "6.4", "unit": "m/s"}],
		"checks": [{"id": "f01_c1", "text": "Walks smoothly", "passed": true}],
		"effectiveChecks": [{"id": "f01_c1", "text": "Walks smoothly", "passed": true}],
		"openFixes": [],
		"openFixesCount": 0,
	}
	dock.call("_on_epic_updated", locked_payload)
	var cta_locked: Dictionary = dock.call("compute_primary_cta_state") as Dictionary
	if str(cta_locked.get("mode", "")) != "locked":
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected 'locked' CTA mode on baseline f01, got: %s" % str(cta_locked))
		return
	if not str(dock.call("log_epic_fix_text", "Blocked on baseline")).is_empty():
		mock_ed_4t.base_ctrl.free()
		_fail("11. Expected log_epic_fix_text to reject mutation on locked baseline f01.")
		return

	dock_sync.set("_is_busy", false)
	dock_sync.call("clear_pending_requests")
	dock_sync.call("clear_link_token")

	# Test 12: Read-only project introspection tools & security dispatcher
	if true:
		var t12_cleanup: Callable = func() -> void:
			var t12_root_dir: String = "res://layers_tool_test"
			var t12_stack: Array[String] = [t12_root_dir]
			var t12_dirs: Array[String] = []
			while not t12_stack.is_empty():
				var t12_cur: String = t12_stack.pop_back()
				var t12_da: DirAccess = DirAccess.open(t12_cur)
				if t12_da == null:
					continue
				t12_dirs.append(t12_cur)
				t12_da.list_dir_begin()
				while true:
					var t12_item: String = t12_da.get_next()
					if t12_item.is_empty():
						break
					if t12_item == "." or t12_item == "..":
						continue
					var t12_full: String = t12_cur + "/" + t12_item
					if t12_da.current_is_dir():
						t12_stack.append(t12_full)
					else:
						DirAccess.remove_absolute(ProjectSettings.globalize_path(t12_full))
				t12_da.list_dir_end()
			t12_dirs.reverse()
			for t12_d: String in t12_dirs:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(t12_d))

		t12_cleanup.call()
		var t12_bus_lines: PackedStringArray = PackedStringArray([
			"extends Node",
			"",
			"signal hit_landed(amount: int)",
			"@export var max_combo: int = 3",
			"",
			"var current_combo: int = 0",
			"",
			"func register_hit(amount: int) -> void:",
			"\tcurrent_combo = mini(current_combo + 1, max_combo)",
			"\thit_landed.emit(amount)",
			"",
			"func reset_combo() -> void:",
			"\tcurrent_combo = 0",
			"",
			"func get_combo() -> int:",
			"\treturn current_combo",
			"",
			"# end combat_bus",
		])
		if not _write_text("res://layers_tool_test/combat_bus.gd", "\n".join(t12_bus_lines) + "\n"):
			t12_cleanup.call()
			_fail("Test12: failed to write combat_bus.gd fixture")

		var t12_tres_text: String = "[gd_resource type=\"Resource\" script_class=\"WeaponStats\" format=3]\n\n[resource]\ndamage = 35\ncooldown = 0.4\n"
		if not _write_text("res://layers_tool_test/weapon_stats.tres", t12_tres_text):
			t12_cleanup.call()
			_fail("Test12: failed to write weapon_stats.tres fixture")

		var t12_child_root: Node3D = Node3D.new()
		t12_child_root.name = "ChildProp"
		var t12_child_pack: PackedScene = PackedScene.new()
		t12_child_pack.pack(t12_child_root)
		var t12_child_save_err: int = ResourceSaver.save(t12_child_pack, "res://layers_tool_test/child_prop.tscn")
		t12_child_root.free()
		if t12_child_save_err != OK:
			t12_cleanup.call()
			_fail("Test12: failed to save child_prop.tscn fixture")

		var t12_loaded_child_pack: PackedScene = ResourceLoader.load("res://layers_tool_test/child_prop.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if t12_loaded_child_pack == null:
			t12_cleanup.call()
			_fail("Test12: failed to reload child_prop.tscn fixture")
		var t12_arena_root: Node3D = Node3D.new()
		t12_arena_root.name = "BossArena"
		var t12_pillar: Node = t12_loaded_child_pack.instantiate()
		t12_pillar.name = "PillarProp"
		t12_arena_root.add_child(t12_pillar)
		t12_pillar.owner = t12_arena_root
		var t12_boss_body: CharacterBody3D = CharacterBody3D.new()
		t12_boss_body.name = "BossBody"
		t12_boss_body.collision_layer = 4
		t12_arena_root.add_child(t12_boss_body)
		t12_boss_body.owner = t12_arena_root
		var t12_arena_pack: PackedScene = PackedScene.new()
		t12_arena_pack.pack(t12_arena_root)
		var t12_arena_save_err: int = ResourceSaver.save(t12_arena_pack, "res://layers_tool_test/boss_arena.tscn")
		t12_arena_root.free()
		if t12_arena_save_err != OK:
			t12_cleanup.call()
			_fail("Test12: failed to save boss_arena.tscn fixture")

		# (1) list_project_files includes test fixtures and excludes addons/
		var t12_list_raw: Variant = exec.call("execute_agent_tool_call", {
			"tool": "list_project_files",
			"args": {"dir": "res://layers_tool_test"},
		}, mock_ed_4t)
		var t12_list_res: Dictionary = t12_list_raw if typeof(t12_list_raw) == TYPE_DICTIONARY else {}
		if not bool(t12_list_res.get("ok", false)):
			t12_cleanup.call()
			_fail("Test12(1): list_project_files failed: " + str(t12_list_res))
		var t12_files: Array = t12_list_res.get("files", []) as Array if typeof(t12_list_res.get("files")) == TYPE_ARRAY else []
		if not t12_files.has("res://layers_tool_test/combat_bus.gd") or not t12_files.has("res://layers_tool_test/boss_arena.tscn") or not t12_files.has("res://layers_tool_test/weapon_stats.tres"):
			t12_cleanup.call()
			_fail("Test12(1): list_project_files missing fixture files: " + str(t12_files))
		var t12_root_list_raw: Variant = exec.call("execute_agent_tool_call", {
			"tool": "list_project_files",
			"args": {"dir": "res://"},
		}, mock_ed_4t)
		var t12_root_list_res: Dictionary = t12_root_list_raw if typeof(t12_root_list_raw) == TYPE_DICTIONARY else {}
		var t12_root_files: Array = t12_root_list_res.get("files", []) as Array if typeof(t12_root_list_res.get("files")) == TYPE_ARRAY else []
		for t12_rf: Variant in t12_root_files:
			if "addons/" in str(t12_rf):
				t12_cleanup.call()
				_fail("Test12(1): list_project_files leaked addons file: " + str(t12_rf))

		# (2) grep_project_text finds hit_landed
		var t12_grep_raw: Variant = exec.call("execute_agent_tool_call", {
			"tool": "grep_project_text",
			"args": {"query": "hit_landed", "dir": "res://layers_tool_test"},
		}, mock_ed_4t)
		var t12_grep_res: Dictionary = t12_grep_raw if typeof(t12_grep_raw) == TYPE_DICTIONARY else {}
		var t12_matches: Array = t12_grep_res.get("matches", []) as Array if typeof(t12_grep_res.get("matches")) == TYPE_ARRAY else []
		if not bool(t12_grep_res.get("ok", false)) or t12_matches.is_empty():
			t12_cleanup.call()
			_fail("Test12(2): grep_project_text expected hit_landed match: " + str(t12_grep_res))
		var t12_first_match: Dictionary = t12_matches[0] if typeof(t12_matches[0]) == TYPE_DICTIONARY else {}
		if str(t12_first_match.get("path", "")) != "res://layers_tool_test/combat_bus.gd" or not ("hit_landed" in str(t12_first_match.get("text", ""))):
			t12_cleanup.call()
			_fail("Test12(2): unexpected grep match: " + str(t12_first_match))

		# (3) read_script_slice lines 1..5
		var t12_slice_raw: Variant = exec.call("execute_agent_tool_call", {
			"tool": "read_script_slice",
			"args": {"path": "res://layers_tool_test/combat_bus.gd", "startLine": 1, "endLine": 5},
		}, mock_ed_4t)
		var t12_slice_res: Dictionary = t12_slice_raw if typeof(t12_slice_raw) == TYPE_DICTIONARY else {}
		if not bool(t12_slice_res.get("ok", false)) or not bool(t12_slice_res.get("truncated", false)) or not ("signal hit_landed" in str(t12_slice_res.get("content", ""))):
			t12_cleanup.call()
			_fail("Test12(3): read_script_slice failed: " + str(t12_slice_res))

		# (4) path security rejects addons, traversal, and host paths
		for t12_bad_path: String in [
			"res://addons/layers/layers_dock.gd",
			"res://../outside.gd",
			"/etc/passwd",
		]:
			var t12_sec_raw: Variant = exec.call("execute_agent_tool_call", {
				"tool": "read_script_slice",
				"args": {"path": t12_bad_path, "startLine": 1, "endLine": 10},
			}, mock_ed_4t)
			var t12_sec_res: Dictionary = t12_sec_raw if typeof(t12_sec_raw) == TYPE_DICTIONARY else {}
			if bool(t12_sec_res.get("ok", false)):
				t12_cleanup.call()
				_fail("Test12(4): expected security rejection for " + t12_bad_path)

		# (5) inspect_scene_tree on boss_arena.tscn
		var t12_scene_raw: Variant = exec.call("execute_agent_tool_call", {
			"tool": "inspect_scene_tree",
			"args": {"path": "res://layers_tool_test/boss_arena.tscn"},
		}, mock_ed_4t)
		var t12_scene_res: Dictionary = t12_scene_raw if typeof(t12_scene_raw) == TYPE_DICTIONARY else {}
		if not bool(t12_scene_res.get("ok", false)):
			t12_cleanup.call()
			_fail("Test12(5): inspect_scene_tree failed: " + str(t12_scene_res))
		var t12_nodes: Array = t12_scene_res.get("nodes", []) as Array if typeof(t12_scene_res.get("nodes")) == TYPE_ARRAY else []
		var t12_saw_pillar_inst: bool = false
		var t12_saw_boss_layer: bool = false
		for t12_nv: Variant in t12_nodes:
			if typeof(t12_nv) != TYPE_DICTIONARY:
				continue
			var t12_nd: Dictionary = t12_nv
			if str(t12_nd.get("name", "")) == "PillarProp" and bool(t12_nd.get("isInstancedScene", false)):
				t12_saw_pillar_inst = true
			if str(t12_nd.get("name", "")) == "BossBody" and int(t12_nd.get("collisionLayer", -1)) == 4:
				t12_saw_boss_layer = true
		if not t12_saw_pillar_inst or not t12_saw_boss_layer:
			t12_cleanup.call()
			_fail("Test12(5): missing PillarProp isInstancedScene or BossBody collisionLayer=4: " + str(t12_nodes))

		# (6) read_autoloads_and_layers
		var t12_proj_raw: Variant = exec.call("execute_agent_tool_call", {
			"tool": "read_autoloads_and_layers",
			"args": {},
		}, mock_ed_4t)
		var t12_proj_res: Dictionary = t12_proj_raw if typeof(t12_proj_raw) == TYPE_DICTIONARY else {}
		if not bool(t12_proj_res.get("ok", false)) or typeof(t12_proj_res.get("autoloads")) != TYPE_DICTIONARY or typeof(t12_proj_res.get("layerNames")) != TYPE_DICTIONARY:
			t12_cleanup.call()
			_fail("Test12(6): read_autoloads_and_layers failed: " + str(t12_proj_res))

		# (7) inspect_tres_resource on weapon_stats.tres
		var t12_tres_raw: Variant = exec.call("execute_agent_tool_call", {
			"tool": "inspect_tres_resource",
			"args": {"path": "res://layers_tool_test/weapon_stats.tres"},
		}, mock_ed_4t)
		var t12_tres_res: Dictionary = t12_tres_raw if typeof(t12_tres_raw) == TYPE_DICTIONARY else {}
		var t12_props: Dictionary = t12_tres_res.get("properties", {}) as Dictionary if typeof(t12_tres_res.get("properties")) == TYPE_DICTIONARY else {}
		if not bool(t12_tres_res.get("ok", false)) or str(t12_tres_res.get("resourceType", "")) != "Resource" or str(t12_tres_res.get("scriptClass", "")) != "WeaponStats" or str(t12_props.get("damage", "")) != "35":
			t12_cleanup.call()
			_fail("Test12(7): inspect_tres_resource failed: " + str(t12_tres_res))

		# (8) disallowed tool delete_file rejected without deleting anything
		var t12_deny_raw: Variant = exec.call("execute_agent_tool_call", {
			"tool": "delete_file",
			"args": {"path": "res://layers_tool_test/combat_bus.gd"},
		}, mock_ed_4t)
		var t12_deny_res: Dictionary = t12_deny_raw if typeof(t12_deny_raw) == TYPE_DICTIONARY else {}
		if bool(t12_deny_res.get("ok", false)) or not FileAccess.file_exists("res://layers_tool_test/combat_bus.gd"):
			t12_cleanup.call()
			_fail("Test12(8): disallowed tool delete_file should be rejected")

		t12_cleanup.call()

	# Test 13: Multi-turn 6-turn orchestrator, Cancel button, compact manifest & 3x auto-repair
	if true:
		dock_sync.save_link_token("lyr_test_dock_mt_1234567890")
		dock_sync.set("_is_busy", false)
		dock_sync.call("clear_pending_requests")
		dock.call("_on_epic_updated", payload_4t)
		dock.set("_last_bundle_snapshot", {})
		dock.set("_auto_heal_count", 0)

		var t13_requests: Array[Dictionary] = []
		dock_sync.set("_agent_transport_override", func(req_payload: Dictionary) -> void:
			t13_requests.append(req_payload.duplicate(true))
		)
		var t13_make_resp: Callable = func(step_dict: Dictionary, turn_idx: int) -> String:
			var resp: Dictionary = payload_4t.duplicate(true)
			resp["agentProtocol"] = "multi_turn_v1"
			resp["turnIndex"] = turn_idx
			resp["maxTurns"] = 6
			resp["agentStep"] = step_dict
			if str(step_dict.get("type", "")) == "final_bundle":
				resp["agentBundle"] = step_dict.get("bundle", {})
			return JSON.stringify(resp)

		var t13_cancel_v: Variant = dock.get("_cancel_agent_btn")
		if not (t13_cancel_v is Button):
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected _cancel_agent_btn Button on dock")
			return
		var t13_cancel_btn: Button = t13_cancel_v as Button
		var t13_cta_btn: Button = dock.get("_primary_cta_btn") as Button
		if t13_cancel_btn.visible:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: _cancel_agent_btn should start hidden")
			return

		# Turn 1: Trigger build_feature -> compact manifest, no 16 liveScripts, no undo snapshot yet
		dock.call("_trigger_epic_agent", "build_feature")
		if not t13_cancel_btn.visible or not t13_cta_btn.disabled:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected cancel visible and primary CTA disabled during run")
			return
		if t13_requests.size() != 1:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected 1 Turn-1 request, got %d" % t13_requests.size())
			return
		var t13_r0: Dictionary = t13_requests[0]
		var t13_man: Dictionary = t13_r0.get("projectManifest", {}) as Dictionary if typeof(t13_r0.get("projectManifest")) == TYPE_DICTIONARY else {}
		var t13_ls_v: Variant = t13_r0.get("liveScripts", {})
		var t13_ls: Dictionary = t13_ls_v as Dictionary if typeof(t13_ls_v) == TYPE_DICTIONARY else {}
		if str(t13_r0.get("agentProtocol", "")) != "multi_turn_v1" or int(t13_r0.get("turnIndex", 0)) != 1 or int(t13_r0.get("maxTurns", 0)) != 6:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: unexpected Turn-1 protocol metadata: %s" % str(t13_r0))
			return
		if t13_man.is_empty() or not t13_man.has("sceneFiles") or not t13_man.has("scriptFiles") or not t13_man.has("ownershipPaths") or not t13_man.has("activeScenePath"):
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: missing compact projectManifest fields: %s" % str(t13_man))
			return
		var t13_th0: Array = t13_r0.get("toolHistory", ["bad"]) as Array if typeof(t13_r0.get("toolHistory")) == TYPE_ARRAY else ["bad"]
		if not t13_th0.is_empty() or not t13_ls.is_empty():
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected empty toolHistory & empty liveScripts on Turn 1")
			return
		if not (dock.get("_last_bundle_snapshot") as Dictionary).is_empty():
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: Undo snapshot should not be captured before final_bundle")
			return

		# Simulate Turn 1 Cloud tool_calls response -> runs read_script_slice locally & dispatches Turn 2
		var t13_step1: Dictionary = {
			"type": "tool_calls",
			"thought": "Read scoped player script",
			"toolCalls": [
				{
					"tool": "read_script_slice",
					"args": {"path": "res://scripts/scoped_player.gd", "startLine": 1, "endLine": 25},
				},
			],
		}
		dock_sync.call("_on_agent_http_completed", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), t13_make_resp.call(t13_step1, 1).to_utf8_buffer())
		if t13_requests.size() != 2:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected Turn-2 dispatch after tool_calls, requests=%d" % t13_requests.size())
			return
		var t13_r1: Dictionary = t13_requests[1]
		var t13_th1: Array = t13_r1.get("toolHistory", []) as Array if typeof(t13_r1.get("toolHistory")) == TYPE_ARRAY else []
		if int(t13_r1.get("turnIndex", 0)) != 2 or t13_th1.size() != 1:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected turnIndex=2 and 1 toolHistory entry, got %s" % str(t13_r1))
			return
		var t13_th1_entry: Dictionary = t13_th1[0] as Dictionary if typeof(t13_th1[0]) == TYPE_DICTIONARY else {}
		var t13_th1_res: Dictionary = t13_th1_entry.get("result", {}) as Dictionary if typeof(t13_th1_entry.get("result")) == TYPE_DICTIONARY else {}
		if str(t13_th1_entry.get("tool", "")) != "read_script_slice" or not bool(t13_th1_res.get("ok", false)) or not ("move_speed" in str(t13_th1_res.get("content", ""))):
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: unexpected Turn-2 toolHistory result: %s" % str(t13_th1_entry))
			return
		if not t13_cancel_btn.visible or not (dock.get("_last_bundle_snapshot") as Dictionary).is_empty():
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected cancel still visible & Undo snapshot still empty during discovery")
			return

		# Simulate Turn 2 Cloud final_bundle response -> Undo snapshot captured, targeted patch applied
		var t13_cur_src: String = FileAccess.get_file_as_string("res://scripts/scoped_player.gd")
		var t13_anchor: String = ""
		for t13_ln: String in t13_cur_src.split("\n"):
			if "move_speed" in t13_ln and t13_ln.strip_edges().begins_with("@export"):
				t13_anchor = t13_ln
				break
		if t13_anchor.is_empty():
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: missing @export move_speed anchor in scoped_player.gd")
			return
		var t13_step2: Dictionary = {
			"type": "final_bundle",
			"thought": "Patch chain_dash_cooldown",
			"bundle": {
				"mode": "build_feature",
				"summary": "Built F02 dash",
				"dimension": "dim3d",
				"preserveExports": ["move_speed"],
				"scriptUpdates": [
					{
						"resPath": "res://scripts/scoped_player.gd",
						"patches": [
							{
								"find": t13_anchor,
								"replace": t13_anchor + "\n@export var chain_dash_cooldown: float = 0.6",
							},
						],
					},
				],
			},
		}
		dock_sync.call("_on_agent_http_completed", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), t13_make_resp.call(t13_step2, 2).to_utf8_buffer())
		var t13_after_src: String = FileAccess.get_file_as_string("res://scripts/scoped_player.gd")
		if (dock.get("_last_bundle_snapshot") as Dictionary).is_empty():
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected Undo snapshot captured right before final_bundle apply")
			return
		if not ("chain_dash_cooldown" in t13_after_src) or not ("move_speed" in t13_after_src):
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected both move_speed and chain_dash_cooldown in patched scoped_player.gd")
			return
		if t13_cancel_btn.visible or t13_cta_btn.disabled:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected cancel hidden & CTA re-enabled after final_bundle")
			return

		# Cancel mid-discovery ignores late final_bundle responses
		var t13_before_cancel: String = FileAccess.get_file_as_string("res://scripts/scoped_player.gd")
		dock.call("_trigger_epic_agent", "build_feature")
		if not t13_cancel_btn.visible:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: cancel button should be visible after starting cancel test run")
			return
		dock.call("_on_cancel_agent_pressed")
		if t13_cancel_btn.visible or bool(dock_sync.call("is_agent_busy")) or t13_cta_btn.disabled:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: cancel must clear busy state and restore CTA")
			return
		var t13_late_step: Dictionary = {
			"type": "final_bundle",
			"thought": "Late response after cancel",
			"bundle": {
				"mode": "build_feature",
				"summary": "Should be ignored",
				"dimension": "dim3d",
				"scriptUpdates": [
					{
						"resPath": "res://scripts/scoped_player.gd",
						"content": "extends CharacterBody3D\n# OVERWRITTEN_AFTER_CANCEL\n",
					},
				],
			},
		}
		dock_sync.call("_on_agent_http_completed", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), t13_make_resp.call(t13_late_step, 1).to_utf8_buffer())
		if FileAccess.get_file_as_string("res://scripts/scoped_player.gd") != t13_before_cancel:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: late final_bundle after Cancel must be ignored")
			return

		# Up to 3 compile/patch auto-repair attempts, then stops
		t13_requests.clear()
		dock.set("_auto_heal_count", 0)
		dock.call("_trigger_epic_agent", "build_feature")
		if t13_requests.size() != 1:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: expected 1 request at start of auto-heal test")
			return
		var t13_bad_step: Dictionary = {
			"type": "final_bundle",
			"thought": "Bad patch trigger",
			"bundle": {
				"mode": "build_feature",
				"summary": "Fails patch match",
				"dimension": "dim3d",
				"scriptUpdates": [
					{
						"resPath": "res://scripts/scoped_player.gd",
						"patches": [
							{"find": "NONEXISTENT_LINE_FOR_T13", "replace": "NOOP"},
						],
					},
				],
			},
		}
		var t13_bad_bytes: PackedByteArray = t13_make_resp.call(t13_bad_step, 1).to_utf8_buffer()
		dock_sync.call("_on_agent_http_completed", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), t13_bad_bytes)
		if int(dock.get("_auto_heal_count")) != 1 or t13_requests.size() != 2 or str(t13_requests[1].get("action", "")) != "fix_feature" or not ("PATCH MISMATCH" in str(t13_requests[1].get("errorText", ""))):
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: auto-heal attempt 1 failed: count=%s reqs=%s" % [str(dock.get("_auto_heal_count")), str(t13_requests)])
			return
		dock_sync.call("_on_agent_http_completed", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), t13_bad_bytes)
		if int(dock.get("_auto_heal_count")) != 2 or t13_requests.size() != 3:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: auto-heal attempt 2 failed: count=%s reqs=%d" % [str(dock.get("_auto_heal_count")), t13_requests.size()])
			return
		dock_sync.call("_on_agent_http_completed", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), t13_bad_bytes)
		if int(dock.get("_auto_heal_count")) != 3 or t13_requests.size() != 4:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: auto-heal attempt 3 failed: count=%s reqs=%d" % [str(dock.get("_auto_heal_count")), t13_requests.size()])
			return
		dock_sync.call("_on_agent_http_completed", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), t13_bad_bytes)
		if int(dock.get("_auto_heal_count")) != 0 or t13_requests.size() != 4 or t13_cancel_btn.visible:
			dock_sync.set("_agent_transport_override", Callable())
			mock_ed_4t.base_ctrl.free()
			_fail("Test13: auto-heal must stop after 3 attempts: count=%s reqs=%d cancel_vis=%s" % [str(dock.get("_auto_heal_count")), t13_requests.size(), str(t13_cancel_btn.visible)])
			return

		dock_sync.set("_agent_transport_override", Callable())
		dock_sync.set("_is_busy", false)
		dock_sync.call("clear_pending_requests")
		dock_sync.call("clear_link_token")
		dock.set("_last_bundle_snapshot", {})

	# Test 14: Autoload/layer manifest injection + instanced/custom-asset/collision guards
	if true:
		# 14a: Turn-1 projectManifest includes autoloads & layerNames from project.godot
		var t14_orig_project_godot: String = FileAccess.get_file_as_string("res://project.godot")
		var t14_cleanup_guard_dir: Callable = func() -> void:
			var t14_stack: Array[String] = ["res://layers_guard_test"]
			var t14_dirs: Array[String] = []
			while not t14_stack.is_empty():
				var t14_cur: String = t14_stack.pop_back()
				var t14_da: DirAccess = DirAccess.open(t14_cur)
				if t14_da == null:
					continue
				t14_dirs.append(t14_cur)
				t14_da.list_dir_begin()
				while true:
					var t14_item: String = t14_da.get_next()
					if t14_item.is_empty():
						break
					if t14_item == "." or t14_item == "..":
						continue
					var t14_full: String = t14_cur + "/" + t14_item
					if t14_da.current_is_dir():
						t14_stack.append(t14_full)
					else:
						DirAccess.remove_absolute(ProjectSettings.globalize_path(t14_full))
				t14_da.list_dir_end()
			t14_dirs.reverse()
			for t14_d: String in t14_dirs:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(t14_d))

		var t14_restore_env: Callable = func() -> void:
			if not t14_orig_project_godot.is_empty():
				_write_text("res://project.godot", t14_orig_project_godot)
			dock.call("_on_cancel_agent_pressed")
			dock_sync.set("_agent_transport_override", Callable())
			dock_sync.set("_is_busy", false)
			dock_sync.call("clear_pending_requests")
			dock_sync.call("clear_link_token")
			t14_cleanup_guard_dir.call()

		var t14_extra_cfg: String = "\n[autoload]\nGameBus=\"*res://scripts/scoped_player.gd\"\n\n[layer_names]\n3d_physics/layer_1=\"World\"\n3d_physics/layer_3=\"Enemy\"\n"
		if not _write_text("res://project.godot", t14_orig_project_godot + t14_extra_cfg):
			t14_restore_env.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14a: failed to write augmented project.godot")
			return

		dock_sync.save_link_token("lyr_test_dock_r4_1234567890")
		dock_sync.set("_is_busy", false)
		dock_sync.call("clear_pending_requests")
		dock.call("_on_epic_updated", payload_4t)
		var t14_requests: Array[Dictionary] = []
		dock_sync.set("_agent_transport_override", func(req_payload: Dictionary) -> void:
			t14_requests.append(req_payload.duplicate(true))
		)
		dock.call("_trigger_epic_agent", "build_feature")
		if t14_requests.size() != 1:
			t14_restore_env.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14a: expected 1 Turn-1 request, got %d" % t14_requests.size())
			return
		var t14_man: Dictionary = t14_requests[0].get("projectManifest", {}) as Dictionary if typeof(t14_requests[0].get("projectManifest")) == TYPE_DICTIONARY else {}
		var t14_auto: Dictionary = t14_man.get("autoloads", {}) as Dictionary if typeof(t14_man.get("autoloads")) == TYPE_DICTIONARY else {}
		var t14_layers: Dictionary = t14_man.get("layerNames", {}) as Dictionary if typeof(t14_man.get("layerNames")) == TYPE_DICTIONARY else {}
		if str(t14_auto.get("GameBus", "")) != "res://scripts/scoped_player.gd" or str(t14_layers.get("3d_physics/layer_3", "")) != "Enemy":
			t14_restore_env.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14a: expected autoloads.GameBus and layerNames in projectManifest, got: %s" % str(t14_man))
			return
		t14_restore_env.call()

		# 14b: Automatic scene override, custom asset & hand-tuned collision protection
		var t14_dir_abs: String = ProjectSettings.globalize_path("res://layers_guard_test")
		DirAccess.make_dir_recursive_absolute(t14_dir_abs)

		var t14_mat := StandardMaterial3D.new()
		t14_mat.albedo_color = Color(0.2, 0.8, 0.9, 1.0)
		var t14_mat_err: int = ResourceSaver.save(t14_mat, "res://layers_guard_test/custom_chrome.tres")
		var t14_mesh := CylinderMesh.new()
		var t14_mesh_err: int = ResourceSaver.save(t14_mesh, "res://layers_guard_test/custom_mesh.tres")
		if t14_mat_err != OK or t14_mesh_err != OK:
			t14_cleanup_guard_dir.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14b: failed to save custom .tres asset fixtures")
			return

		var t14_prop_root := Node3D.new()
		t14_prop_root.name = "PropPillar"
		var t14_prop_mesh := MeshInstance3D.new()
		t14_prop_mesh.name = "PropMesh"
		t14_prop_mesh.visible = true
		t14_prop_root.add_child(t14_prop_mesh)
		t14_prop_mesh.owner = t14_prop_root
		var t14_prop_pack := PackedScene.new()
		t14_prop_pack.pack(t14_prop_root)
		var t14_prop_save_err: int = ResourceSaver.save(t14_prop_pack, "res://layers_guard_test/prop_pillar.tscn")
		t14_prop_root.free()
		if t14_prop_save_err != OK:
			t14_cleanup_guard_dir.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14b: failed to save prop_pillar.tscn fixture")
			return

		var t14_loaded_mat: Material = ResourceLoader.load("res://layers_guard_test/custom_chrome.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Material
		var t14_loaded_mesh: Mesh = ResourceLoader.load("res://layers_guard_test/custom_mesh.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as Mesh
		var t14_loaded_prop: PackedScene = ResourceLoader.load("res://layers_guard_test/prop_pillar.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if t14_loaded_mat == null or t14_loaded_mesh == null or t14_loaded_prop == null:
			t14_cleanup_guard_dir.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14b: failed to reload fixtures")
			return

		var t14_root := Node3D.new()
		t14_root.name = "BossRoom"

		var t14_pillar_inst: Node3D = t14_loaded_prop.instantiate() as Node3D
		t14_pillar_inst.name = "PillarInst"
		t14_pillar_inst.position = Vector3(3.0, 0.0, 2.0)
		t14_root.add_child(t14_pillar_inst)

		var t14_hero_art := MeshInstance3D.new()
		t14_hero_art.name = "HeroArt"
		t14_hero_art.mesh = t14_loaded_mesh
		t14_hero_art.material_override = t14_loaded_mat
		t14_root.add_child(t14_hero_art)

		var t14_boss_body := CharacterBody3D.new()
		t14_boss_body.name = "BossBody"
		t14_boss_body.collision_layer = 4
		t14_boss_body.collision_mask = 6
		t14_root.add_child(t14_boss_body)

		var t14_default_body := CharacterBody3D.new()
		t14_default_body.name = "DefaultBody"
		t14_default_body.collision_layer = 1
		t14_default_body.collision_mask = 1
		t14_root.add_child(t14_default_body)

		var t14_build_ops: Array = [
			{"op": "remove_node", "nodePath": "PillarInst"},
			{"op": "reparent_node", "nodePath": "PillarInst", "newParentPath": "BossBody"},
			{"op": "set_property", "nodePath": "PillarInst", "properties": {"position": [0.0, 0.0, 0.0]}},
			{"op": "set_property", "nodePath": "PillarInst/PropMesh", "properties": {"visible": false}},
			{"op": "ensure_node", "parentPath": ".", "nodeName": "HeroArt", "nodeType": "MeshInstance3D", "subResourceClass": "BoxMesh", "subResourceProps": {"size": [1.0, 1.0, 1.0]}},
			{"op": "set_property", "nodePath": "HeroArt", "properties": {"material_override": {"albedo_color": [1.0, 0.0, 0.0, 1.0]}}},
			{"op": "set_property", "nodePath": "BossBody", "properties": {"collision_layer": 1, "collision_mask": 1}},
			{"op": "set_property", "nodePath": "DefaultBody", "properties": {"collision_layer": 2}},
		]
		exec.call("apply_scene_ops_to_root", t14_root, t14_build_ops, PackedStringArray(), true)

		var t14_pillar_after: Node = t14_root.get_node_or_null("PillarInst")
		var t14_pmesh_after: Node = t14_root.get_node_or_null("PillarInst/PropMesh")
		if t14_pillar_after == null or t14_pillar_after.get_parent() != t14_root or not (t14_pillar_after as Node3D).position.is_equal_approx(Vector3(3.0, 0.0, 2.0)):
			t14_root.free()
			t14_cleanup_guard_dir.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14b: instanced scene PillarInst must not be removed, reparented, or moved on build pass")
			return
		if t14_pmesh_after == null or not (t14_pmesh_after as MeshInstance3D).visible:
			t14_root.free()
			t14_cleanup_guard_dir.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14b: internal instanced child PillarInst/PropMesh must not be mutated on build pass")
			return
		if t14_hero_art.mesh == null or t14_hero_art.mesh.resource_path != "res://layers_guard_test/custom_mesh.tres" or t14_hero_art.material_override == null or t14_hero_art.material_override.resource_path != "res://layers_guard_test/custom_chrome.tres":
			t14_root.free()
			t14_cleanup_guard_dir.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14b: HeroArt custom .tres mesh/material_override must be protected on build pass")
			return
		if t14_boss_body.collision_layer != 4 or t14_boss_body.collision_mask != 6 or t14_default_body.collision_layer != 2:
			t14_root.free()
			t14_cleanup_guard_dir.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14b: BossBody hand-tuned collision should stay (4,6) and DefaultBody should update to 2, got boss=(%d,%d) def=%d" % [t14_boss_body.collision_layer, t14_boss_body.collision_mask, t14_default_body.collision_layer])
			return

		# Explicit fix pass (preserve_existing_visuals = false) CAN update collision_layer & material_override
		var t14_fix_ops: Array = [
			{"op": "set_property", "nodePath": "BossBody", "properties": {"collision_layer": 8}},
			{"op": "set_property", "nodePath": "HeroArt", "properties": {"material_override": {"albedo_color": [1.0, 0.2, 0.2, 1.0]}}},
		]
		exec.call("apply_scene_ops_to_root", t14_root, t14_fix_ops, PackedStringArray(), false)
		if t14_boss_body.collision_layer != 8 or t14_hero_art.material_override == null or t14_hero_art.material_override.resource_path == "res://layers_guard_test/custom_chrome.tres":
			t14_root.free()
			t14_cleanup_guard_dir.call()
			mock_ed_4t.base_ctrl.free()
			_fail("Test14b: fix pass (preserve_existing_visuals=false) must allow explicit collision & material updates")
			return

		t14_root.free()
		t14_cleanup_guard_dir.call()

	mock_ed_4t.base_ctrl.free()

	print("GODOT_PLUGIN_TEST_OK")
	quit(0)


func _send_loopback_http(sync_client: Node, port: int, target_path: String) -> String:
	var peer := StreamPeerTCP.new()
	var err: int = peer.connect_to_host("127.0.0.1", port)
	if err != OK:
		return "CONNECT_ERR_%d" % err
	var connected: bool = false
	for _i in range(60):
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			connected = true
			break
		OS.delay_msec(5)
	if not connected:
		peer.disconnect_from_host()
		return "CONNECT_TIMEOUT"

	var req_str := "GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n" % [target_path, port]
	peer.put_data(req_str.to_utf8_buffer())

	var resp_buf := ""
	for _j in range(80):
		sync_client.call("poll_loopback_auth")
		peer.poll()
		var avail: int = peer.get_available_bytes()
		if avail > 0:
			var got: Array = peer.get_data(avail)
			if got.size() >= 2 and int(got[0]) == OK:
				resp_buf += (got[1] as PackedByteArray).get_string_from_utf8()
		if "\r\n\r\n" in resp_buf and peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		if "HTTP/1.1" in resp_buf and (resp_buf.ends_with("</html>") or "Invalid" in resp_buf):
			break
		OS.delay_msec(5)

	peer.disconnect_from_host()
	return resp_buf
