@tool
extends Node

signal epic_updated(payload: Dictionary)
signal sync_failed(message: String)
signal busy_changed(is_busy: bool)

const DEFAULT_SYNC_BASE_URL := "https://us-central1-layers-b8a16.cloudfunctions.net/geminiProxy"
const CONFIG_DIR := "res://.layers"
const LINK_CFG_PATH := "res://.layers/link.cfg"
const CACHE_JSON_PATH := "res://.layers/epic_cache.json"

var _http: HTTPRequest
var _link_token: String = ""
var _sync_base_url: String = DEFAULT_SYNC_BASE_URL
var _is_busy: bool = false
var _pending_request: Dictionary = {}
var _active_request_kind: String = ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
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
