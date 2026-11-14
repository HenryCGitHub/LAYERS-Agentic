@tool
extends Node

signal epic_updated(payload: Dictionary)
signal sync_failed(message: String)
signal busy_changed(is_busy: bool)
signal agent_bundle_received(agent_bundle: Dictionary, payload: Dictionary)
signal scripts_synced(synced_count: int)
signal update_available(local_ver: String, remote_ver: String)
signal update_check_finished(up_to_date: bool, local_ver: String, remote_ver: String)
signal update_ready_to_reload(new_ver: String, updated_gd_paths: PackedStringArray)
signal update_failed(message: String)

var _agent_http: HTTPRequest = null
var _agent_busy: bool = false

const DEFAULT_SYNC_BASE_URL := "https://us-central1-layers-b8a16.cloudfunctions.net/geminiProxy"
const CONFIG_DIR := "res://.layers"
const LINK_CFG_PATH := "res://.layers/link.cfg"
const CACHE_JSON_PATH := "res://.layers/epic_cache.json"
const PLUGIN_CFG_PATH := "res://addons/layers/plugin.cfg"
const UPDATE_TMP_ZIP_PATH := "res://.layers/plugin_update.zip"
const REMOTE_PLUGIN_CFG_URL := "https://raw.githubusercontent.com/HenryCGitHub/LAYERS-Agentic/main/godot_plugin/addons/layers/plugin.cfg"
const REMOTE_ZIP_PRIMARY_URL := "https://raw.githubusercontent.com/HenryCGitHub/LAYERS-Agentic/main/web/layers_godot_plugin.zip"
const REMOTE_ZIP_FALLBACK_URL := "https://henrycgithub.github.io/LAYERS-Agentic/layers_godot_plugin.zip"

var _http: HTTPRequest
var _update_http: HTTPRequest
var _script_sync_http: HTTPRequest
var _link_token: String = ""
var _sync_base_url: String = DEFAULT_SYNC_BASE_URL
var _is_busy: bool = false
var _pending_request: Dictionary = {}
var _active_request_kind: String = ""
var _update_busy: bool = false
var _update_mode: String = ""
var _update_silent: bool = true
var _update_zip_attempt_idx: int = 0
var _latest_known_remote_ver: String = ""
var _script_sync_busy: bool = false
var _pending_live_scripts: Dictionary = {}
var _script_sync_in_flight: Dictionary = {}


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 65.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	_update_http = HTTPRequest.new()
	_update_http.timeout = 30.0
	add_child(_update_http)
	_update_http.request_completed.connect(_on_update_http_completed)

	_script_sync_http = HTTPRequest.new()
	_script_sync_http.timeout = 20.0
	add_child(_script_sync_http)
	_script_sync_http.request_completed.connect(_on_script_sync_http_completed)

	load_config()


func has_link_token() -> bool:
	return _link_token.begins_with("lyr_") and _link_token.length() >= 20


func get_link_token() -> String:
	return _link_token


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LINK_CFG_PATH) == OK:
		_link_token = str(cfg.get_value("layers", "link_token", "")).strip_edges()
		var saved_url := str(cfg.get_value("layers", "sync_base_url", DEFAULT_SYNC_BASE_URL)).strip_edges()
		if not saved_url.is_empty():
			_sync_base_url = saved_url.trim_suffix("/")
	else:
		_link_token = ""
		_sync_base_url = DEFAULT_SYNC_BASE_URL


func save_link_token(token: String, base_url: String = DEFAULT_SYNC_BASE_URL) -> void:
	_ensure_layers_dir()
	_link_token = token.strip_edges()
	var clean_url := base_url.strip_edges().trim_suffix("/")
	if not clean_url.is_empty():
		_sync_base_url = clean_url
	var cfg := ConfigFile.new()
	cfg.set_value("layers", "link_token", _link_token)
	cfg.set_value("layers", "sync_base_url", _sync_base_url)
	cfg.save(LINK_CFG_PATH)


func clear_link_token() -> void:
	_link_token = ""
	_pending_request = {}
	if FileAccess.file_exists(LINK_CFG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LINK_CFG_PATH))
	if FileAccess.file_exists(CACHE_JSON_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_JSON_PATH))


func load_cached_epic() -> Dictionary:
	if not FileAccess.file_exists(CACHE_JSON_PATH):
		return {}
	var file := FileAccess.open(CACHE_JSON_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func fetch_active_epic() -> void:
	if not has_link_token():
		return
	_dispatch_or_queue({
		"kind": "get_epic",
		"method": HTTPClient.METHOD_GET,
		"path": "/godotLink/epic",
		"body": "",
	})


func toggle_step(feature_id: String, checkpoint_id: String, step_id: String, completed: bool) -> void:
	if not has_link_token():
		return
	_dispatch_or_queue({
		"kind": "update",
		"method": HTTPClient.METHOD_POST,
		"path": "/godotLink/update",
		"body": JSON.stringify({
			"featureId": feature_id,
			"checkpointId": checkpoint_id,
			"action": "toggle_step",
			"stepId": step_id,
			"completed": completed,
		}),
	})


func set_playtest_passed(feature_id: String, checkpoint_id: String, passed: bool) -> void:
	if not has_link_token():
		return
	_dispatch_or_queue({
		"kind": "update",
		"method": HTTPClient.METHOD_POST,
		"path": "/godotLink/update",
		"body": JSON.stringify({
			"featureId": feature_id,
			"checkpointId": checkpoint_id,
			"action": "set_playtest",
			"passed": passed,
		}),
	})


func diagnose_fix(
	feature_id: String,
	checkpoint_id: String,
	issue: String,
	scene_snapshot: String,
	scripts_snapshot: String
) -> void:
	if not has_link_token():
		return
	_dispatch_or_queue({
		"kind": "update",
		"method": HTTPClient.METHOD_POST,
		"path": "/godotLink/update",
		"body": JSON.stringify({
			"featureId": feature_id,
			"checkpointId": checkpoint_id,
			"action": "diagnose_fix",
			"issue": issue,
			"sceneSnapshot": scene_snapshot,
			"scriptsSnapshot": scripts_snapshot,
		}),
	})


func _ensure_layers_dir() -> void:
	var abs_dir := ProjectSettings.globalize_path(CONFIG_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var gdignore_path := "%s/.gdignore" % CONFIG_DIR
	if not FileAccess.file_exists(gdignore_path):
		var f_gd := FileAccess.open(gdignore_path, FileAccess.WRITE)
		if f_gd != null:
			f_gd.store_string("")
	var gitignore_path := "%s/.gitignore" % CONFIG_DIR
	if not FileAccess.file_exists(gitignore_path):
		var f_git := FileAccess.open(gitignore_path, FileAccess.WRITE)
		if f_git != null:
			f_git.store_string("*\n")


func _dispatch_or_queue(req: Dictionary) -> void:
	if _http == null:
		return
	if _is_busy:
		# Prioritize updates over background GET refreshes
		if req.get("kind") == "update" or _pending_request.is_empty():
			_pending_request = req
		return
	_start_request(req)


func _start_request(req: Dictionary) -> void:
	_is_busy = true
	_active_request_kind = str(req.get("kind", ""))
	busy_changed.emit(true)

	var url := "%s%s" % [_sync_base_url, str(req.get("path", ""))]
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % _link_token,
		"Content-Type: application/json",
	])
	var method := int(req.get("method", HTTPClient.METHOD_GET))
	var body := str(req.get("body", ""))

	var err := _http.request(url, headers, method, body)
	if err != OK:
		_is_busy = false
		_active_request_kind = ""
		busy_changed.emit(false)
		sync_failed.emit("HTTP request failed (%s)" % error_string(err))


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_busy = false
	busy_changed.emit(false)

	var text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)

	if result != HTTPRequest.RESULT_SUCCESS:
		sync_failed.emit("Offline or network error (%d)" % result)
	elif response_code < 200 or response_code >= 300:
		var err_msg := "Sync error (%d)" % response_code
		if typeof(parsed) == TYPE_DICTIONARY:
			var err_obj = parsed.get("error", {})
			if typeof(err_obj) == TYPE_DICTIONARY and err_obj.has("message"):
				err_msg = str(err_obj["message"])
		sync_failed.emit(err_msg)
	elif typeof(parsed) == TYPE_DICTIONARY and parsed.get("ok", false) == true:
		_write_cache(parsed)
		if parsed.has("agentBundle") and typeof(parsed.get("agentBundle")) == TYPE_DICTIONARY:
			agent_bundle_received.emit(parsed.get("agentBundle"), parsed)
		epic_updated.emit(parsed)
	else:
		sync_failed.emit("Unexpected sync response.")

	if not _pending_request.is_empty():
		var next_req := _pending_request
		_pending_request = {}
		_start_request(next_req)


func _write_cache(payload: Dictionary) -> void:
	_ensure_layers_dir()
	var file := FileAccess.open(CACHE_JSON_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload))


func get_local_plugin_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PLUGIN_CFG_PATH) == OK:
		var ver := str(cfg.get_value("plugin", "version", "0.0.0")).strip_edges()
		if not ver.is_empty():
			return ver
	return "0.0.0"


func _parse_semver_parts(raw_ver: String) -> PackedInt32Array:
	var clean := raw_ver.strip_edges().trim_prefix("v").trim_prefix("V")
	var core := clean.split("-", false, 1)[0].split("+", false, 1)[0]
	var segs := core.split(".", false)
	var out := PackedInt32Array()
	for s in segs:
		var t := s.strip_edges()
		out.append(t.to_int() if t.is_valid_int() else 0)
	return out


func _is_newer_version(local_ver: String, remote_ver: String) -> bool:
	var loc := _parse_semver_parts(local_ver)
	var rem := _parse_semver_parts(remote_ver)
	if rem.is_empty():
		return false
	var max_len := maxi(loc.size(), rem.size())
	for i in range(max_len):
		var l_val := loc[i] if i < loc.size() else 0
		var r_val := rem[i] if i < rem.size() else 0
		if r_val > l_val:
			return true
		if r_val < l_val:
			return false
	return false


func check_for_plugin_update(silent: bool = true) -> void:
	if _update_http == null or _update_busy:
		return
	_update_busy = true
	_update_mode = "check"
	_update_silent = silent
	var url := "%s?t=%d" % [REMOTE_PLUGIN_CFG_URL, int(Time.get_unix_time_from_system() * 1000.0)]
	var headers := PackedStringArray([
		"Cache-Control: no-cache",
		"Pragma: no-cache",
	])
	var err := _update_http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_update_busy = false
		_update_mode = ""
		if not _update_silent:
			update_failed.emit("Could not check GitHub for plugin updates (%s)." % error_string(err))


func _get_remote_zip_urls() -> PackedStringArray:
	return PackedStringArray([
		REMOTE_ZIP_PRIMARY_URL,
		REMOTE_ZIP_FALLBACK_URL,
	])


func download_and_apply_plugin_update() -> void:
	if _update_http == null or _update_busy:
		return
	_update_busy = true
	_update_mode = "download"
	_update_silent = false
	_update_zip_attempt_idx = 0
	_start_zip_download_attempt(0)


func _start_zip_download_attempt(idx: int) -> void:
	var zip_urls: PackedStringArray = _get_remote_zip_urls()
	if idx < 0 or idx >= zip_urls.size():
		_update_busy = false
		_update_mode = ""
		update_failed.emit("Failed to download plugin update archive.")
		return
	var base_url: String = zip_urls[idx]
	var url := "%s?t=%d" % [base_url, int(Time.get_unix_time_from_system() * 1000.0)]
	var headers := PackedStringArray([
		"Cache-Control: no-cache",
		"Pragma: no-cache",
	])
	var err := _update_http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		if idx + 1 < zip_urls.size():
			_update_zip_attempt_idx = idx + 1
			_start_zip_download_attempt(_update_zip_attempt_idx)
		else:
			_update_busy = false
			_update_mode = ""
			update_failed.emit("Failed to download plugin update archive (%s)." % error_string(err))


func _on_update_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var mode := _update_mode
	if mode == "check":
		_update_busy = false
		_update_mode = ""
		if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
			if not _update_silent:
				update_failed.emit("Could not check GitHub for plugin updates.")
			return
		var cfg := ConfigFile.new()
		var text := body.get_string_from_utf8()
		if cfg.parse(text) != OK:
			if not _update_silent:
				update_failed.emit("Could not check GitHub for plugin updates.")
			return
		var remote_ver := str(cfg.get_value("plugin", "version", "")).strip_edges()
		var local_ver := get_local_plugin_version()
		if remote_ver.is_empty():
			if not _update_silent:
				update_failed.emit("Could not check GitHub for plugin updates.")
			return
		_latest_known_remote_ver = remote_ver
		if _is_newer_version(local_ver, remote_ver):
			update_available.emit(local_ver, remote_ver)
			update_check_finished.emit(false, local_ver, remote_ver)
		else:
			update_check_finished.emit(true, local_ver, remote_ver)
		return

	if mode == "download":
		var zip_urls: PackedStringArray = _get_remote_zip_urls()
		if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300 or body.size() < 200:
			if _update_zip_attempt_idx + 1 < zip_urls.size():
				_update_zip_attempt_idx += 1
				_start_zip_download_attempt(_update_zip_attempt_idx)
			else:
				_update_busy = false
				_update_mode = ""
				update_failed.emit("Failed to download plugin update archive.")
			return
		_apply_downloaded_zip_bytes(body)


func _apply_downloaded_zip_bytes(zip_bytes: PackedByteArray) -> void:
	_ensure_layers_dir()
	var tmp_file := FileAccess.open(UPDATE_TMP_ZIP_PATH, FileAccess.WRITE)
	if tmp_file == null:
		_update_busy = false
		_update_mode = ""
		update_failed.emit("Could not write temporary plugin update archive.")
		return
	tmp_file.store_buffer(zip_bytes)
	tmp_file.close()

	var tmp_abs := ProjectSettings.globalize_path(UPDATE_TMP_ZIP_PATH)
	var reader := ZIPReader.new()
	if reader.open(tmp_abs) != OK:
		DirAccess.remove_absolute(tmp_abs)
		_update_busy = false
		_update_mode = ""
		update_failed.emit("Downloaded plugin archive is invalid.")
		return

	var files: PackedStringArray = reader.get_files()
	var required_entries := PackedStringArray([
		"addons/layers/plugin.cfg",
		"addons/layers/layers_plugin.gd",
		"addons/layers/layers_dock.gd",
		"addons/layers/layers_sync_client.gd",
		"addons/layers/layers_step_executor.gd",
	])
	for req in required_entries:
		if not files.has(req) or reader.read_file(req).size() <= 0:
			reader.close()
			DirAccess.remove_absolute(tmp_abs)
			_update_busy = false
			_update_mode = ""
			update_failed.emit("Plugin archive missing required file: %s" % req)
			return

	var updated_gd_paths := PackedStringArray()
	for entry in files:
		if not entry.begins_with("addons/layers/"):
			continue
		if entry.ends_with("/"):
			continue
		if ".." in entry:
			continue
		var data := reader.read_file(entry)
		var dest_res := "res://" + entry
		var dest_dir_abs := ProjectSettings.globalize_path(dest_res.get_base_dir())
		if not DirAccess.dir_exists_absolute(dest_dir_abs):
			DirAccess.make_dir_recursive_absolute(dest_dir_abs)
		var out_f := FileAccess.open(dest_res, FileAccess.WRITE)
		if out_f == null:
			reader.close()
			DirAccess.remove_absolute(tmp_abs)
			_update_busy = false
			_update_mode = ""
			update_failed.emit("Failed to write %s during update." % dest_res)
			return
		out_f.store_buffer(data)
		out_f.close()
		if dest_res.ends_with(".gd"):
			updated_gd_paths.append(dest_res)

	reader.close()
	DirAccess.remove_absolute(tmp_abs)

	_update_busy = false
	_update_mode = ""
	var new_ver := get_local_plugin_version()
	update_ready_to_reload.emit(new_ver, updated_gd_paths)


func _ensure_agent_http() -> void:
	if _agent_http != null and is_instance_valid(_agent_http):
		return
	_agent_http = HTTPRequest.new()
	_agent_http.timeout = 65.0
	add_child(_agent_http)
	_agent_http.request_completed.connect(_on_agent_http_completed)


func is_agent_busy() -> bool:
	return _agent_busy


func build_feature(
	feature_id: String,
	checkpoint_id: String,
	scene_snapshot: Variant,
	live_scripts: Dictionary,
	arena_scene_path: String = "",
	feature_scene_path: String = ""
) -> void:
	_post_agent_update({
		"action": "build_feature",
		"featureId": feature_id,
		"checkpointId": checkpoint_id,
		"sceneSnapshot": scene_snapshot,
		"liveScripts": live_scripts,
		"arenaScenePath": arena_scene_path,
		"featureScenePath": feature_scene_path,
	})


func direct_agent(
	feature_id: String,
	checkpoint_id: String,
	prompt_text: String,
	scene_snapshot: Variant,
	live_scripts: Dictionary,
	arena_scene_path: String = "",
	feature_scene_path: String = "",
	error_text: String = ""
) -> void:
	_post_agent_update({
		"action": "direct_agent",
		"featureId": feature_id,
		"checkpointId": checkpoint_id,
		"prompt": prompt_text,
		"errorText": error_text,
		"sceneSnapshot": scene_snapshot,
		"liveScripts": live_scripts,
		"arenaScenePath": arena_scene_path,
		"featureScenePath": feature_scene_path,
	})


func complete_feature_steps(feature_id: String, checkpoint_id: String) -> void:
	_post_agent_update({
		"action": "complete_feature_steps",
		"featureId": feature_id,
		"checkpointId": checkpoint_id,
	})


func sync_live_scripts(live_scripts: Dictionary) -> void:
	if not has_link_token() or live_scripts.is_empty():
		return
	for raw_path in live_scripts.keys():
		var p := str(raw_path).strip_edges()
		if p.begins_with("res://") and p.ends_with(".gd"):
			var code := str(live_scripts[raw_path])
			if not code.strip_edges().is_empty():
				_pending_live_scripts[p] = code
	if _pending_live_scripts.is_empty():
		return
	if _script_sync_busy:
		return
	_flush_pending_script_sync()


func _flush_pending_script_sync() -> void:
	if _script_sync_busy or _pending_live_scripts.is_empty() or not has_link_token():
		return
	if _script_sync_http == null:
		return
	_script_sync_in_flight = _pending_live_scripts.duplicate()
	_pending_live_scripts.clear()
	_script_sync_busy = true

	var url := "%s/godotLink/update" % _sync_base_url.trim_suffix("/")
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _link_token,
	])
	var body_str := JSON.stringify({
		"action": "sync_scripts",
		"scripts": _script_sync_in_flight,
	})
	var err := _script_sync_http.request(url, headers, HTTPClient.METHOD_POST, body_str)
	if err != OK:
		_script_sync_busy = false
		_script_sync_in_flight.clear()


func _on_script_sync_http_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_script_sync_busy = false
	var synced_snapshot: Dictionary = _script_sync_in_flight.duplicate()
	_script_sync_in_flight.clear()

	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY and parsed.get("ok", false) == true:
			_update_cached_code_files(synced_snapshot)
			scripts_synced.emit(int(parsed.get("syncedCount", synced_snapshot.size())))

	if not _pending_live_scripts.is_empty():
		_flush_pending_script_sync()


func _update_cached_code_files(live_scripts: Dictionary) -> void:
	if live_scripts.is_empty():
		return
	var cached := load_cached_epic()
	if cached.is_empty():
		return
	var code_files_raw: Variant = cached.get("codeFiles", [])
	var code_files: Array = code_files_raw if typeof(code_files_raw) == TYPE_ARRAY else []
	var by_path := {}
	for i in range(code_files.size()):
		var cf: Variant = code_files[i]
		if typeof(cf) == TYPE_DICTIONARY:
			var rp := str(cf.get("resPath", cf.get("path", ""))).strip_edges()
			if not rp.is_empty():
				by_path[rp] = i
	for rp_raw in live_scripts.keys():
		var rp := str(rp_raw).strip_edges()
		var content := str(live_scripts[rp_raw])
		if by_path.has(rp):
			var idx: int = int(by_path[rp])
			var existing: Dictionary = code_files[idx]
			existing["content"] = content
			code_files[idx] = existing
		else:
			code_files.append({
				"resPath": rp,
				"title": rp.get_file(),
				"language": "gdscript",
				"content": content,
			})
	cached["codeFiles"] = code_files
	_write_cache(cached)


func _post_agent_update(payload_body: Dictionary) -> void:
	if _link_token.is_empty():
		sync_failed.emit("Link token not configured. Open Settings to paste your Project Link Token.")
		return
	if _agent_busy:
		sync_failed.emit("Agent is already applying a change. Please wait a moment.")
		return
	_ensure_agent_http()
	_agent_busy = true
	busy_changed.emit(true)

	var url := "%s/godotLink/update" % _sync_base_url.trim_suffix("/")
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _link_token,
	])
	var json_str := JSON.stringify(payload_body)
	var err := _agent_http.request(url, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		_agent_busy = false
		busy_changed.emit(_is_busy)
		sync_failed.emit("Failed to send Agent request (HTTPRequest error %d)." % err)


func _on_agent_http_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_agent_busy = false
	busy_changed.emit(_is_busy)
	if result != HTTPRequest.RESULT_SUCCESS:
		sync_failed.emit("Network error communicating with LAYERS Agent (code %d)." % result)
		return
	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if response_code < 200 or response_code >= 300:
		var err_msg := "Agent request failed (HTTP %d)." % response_code
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
			var err_obj: Variant = parsed.get("error")
			if typeof(err_obj) == TYPE_DICTIONARY:
				err_msg = String(err_obj.get("message", err_msg))
			elif typeof(err_obj) == TYPE_STRING:
				err_msg = String(err_obj)
		sync_failed.emit(err_msg)
		return
	if typeof(parsed) == TYPE_DICTIONARY and parsed.get("ok", false) == true:
		_write_cache(parsed)
		if parsed.has("agentBundle") and typeof(parsed.get("agentBundle")) == TYPE_DICTIONARY:
			agent_bundle_received.emit(parsed.get("agentBundle"), parsed)
		epic_updated.emit(parsed)
	else:
		sync_failed.emit("Unexpected Agent response from LAYERS Cloud.")
