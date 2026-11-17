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
