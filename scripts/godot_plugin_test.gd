extends SceneTree

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
