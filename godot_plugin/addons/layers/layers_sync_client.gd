@tool
extends Node

signal epic_updated(payload: Dictionary)
signal sync_failed(message: String)
signal busy_changed(is_busy: bool)
signal agent_busy_changed(is_agent_busy: bool)
signal agent_bundle_received(agent_bundle: Dictionary, payload: Dictionary)
signal auth_completed(project_title: String)
signal auth_status_changed(waiting: bool, message: String)
signal update_available(local_ver: String, remote_ver: String)
signal update_check_finished(up_to_date: bool, local_ver: String, remote_ver: String)
signal update_ready_to_reload(new_ver: String, updated_gd_paths: PackedStringArray)
signal update_failed(message: String)

const DEFAULT_SYNC_BASE_URL := "https://us-central1-layers-b8a16.cloudfunctions.net/geminiProxy"
const DEFAULT_WEB_STUDIO_URL := "https://henrycgithub.github.io/LAYERS-Agentic/"
const CONFIG_DIR := "res://.layers"
const LINK_CFG_PATH := "res://.layers/link.cfg"
const CACHE_JSON_PATH := "res://.layers/epic_cache.json"
const PLUGIN_CFG_PATH := "res://addons/layers/plugin.cfg"
const UPDATE_TMP_ZIP_PATH := "res://.layers/plugin_update.zip"
const REMOTE_PLUGIN_CFG_URL := "https://raw.githubusercontent.com/HenryCGitHub/LAYERS-Agentic/main/godot_plugin/addons/layers/plugin.cfg"
const REMOTE_ZIP_PRIMARY_URL := "https://raw.githubusercontent.com/HenryCGitHub/LAYERS-Agentic/main/web/layers_godot_plugin.zip"
const REMOTE_ZIP_FALLBACK_URL := "https://henrycgithub.github.io/LAYERS-Agentic/layers_godot_plugin.zip"
const LOOPBACK_TIMEOUT_MSEC := 180000

var _http: HTTPRequest = null
var _agent_http: HTTPRequest = null
var _update_http: HTTPRequest = null

var _link_token: String = ""
var _sync_base_url: String = DEFAULT_SYNC_BASE_URL
var _is_busy: bool = false
var _agent_busy: bool = false
var _pending_requests: Array[Dictionary] = []

var _update_busy: bool = false
var _update_mode: String = ""
var _update_silent: bool = true
var _update_zip_attempt_idx: int = 0

var _auth_tcp: TCPServer = null
var _auth_port: int = 0
var _auth_state: String = ""
var _auth_started_msec: int = 0
var _auth_peers: Array[Dictionary] = []


func _ready() -> void:
	_ensure_http_nodes()
	load_config()


func _exit_tree() -> void:
	cancel_google_sign_in()


func _process(_delta: float) -> void:
	if _auth_tcp != null and _auth_tcp.is_listening():
		poll_loopback_auth()


func _ensure_http_nodes() -> void:
	if _http == null or not is_instance_valid(_http):
		_http = HTTPRequest.new()
		_http.timeout = 35.0
		add_child(_http)
		_http.request_completed.connect(_on_request_completed)

	if _agent_http == null or not is_instance_valid(_agent_http):
		_agent_http = HTTPRequest.new()
		_agent_http.timeout = 115.0
		add_child(_agent_http)
		_agent_http.request_completed.connect(_on_agent_http_completed)

	if _update_http == null or not is_instance_valid(_update_http):
		_update_http = HTTPRequest.new()
		_update_http.timeout = 30.0
		add_child(_update_http)
		_update_http.request_completed.connect(_on_update_http_completed)


func has_link_token() -> bool:
	return _link_token.begins_with("lyr_") and _link_token.length() >= 20


func get_link_token() -> String:
	return _link_token


func get_sync_base_url() -> String:
	return _sync_base_url


func is_busy() -> bool:
	return _is_busy or _agent_busy


func is_agent_busy() -> bool:
	return _agent_busy


func get_pending_request_count() -> int:
	return _pending_requests.size()


func clear_pending_requests() -> void:
	_pending_requests.clear()


func is_waiting_for_auth() -> bool:
	return _auth_tcp != null and _auth_tcp.is_listening()


func get_auth_port() -> int:
	return _auth_port


func get_auth_state() -> String:
	return _auth_state


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LINK_CFG_PATH) == OK:
		var tok_raw: Variant = cfg.get_value("layers", "link_token", "")
		_link_token = str(tok_raw).strip_edges()
		var url_raw: Variant = cfg.get_value("layers", "sync_base_url", DEFAULT_SYNC_BASE_URL)
		var saved_url: String = str(url_raw).strip_edges()
		if not saved_url.is_empty():
			_sync_base_url = saved_url.trim_suffix("/")
	else:
		_link_token = ""
		_sync_base_url = DEFAULT_SYNC_BASE_URL


func save_link_token(token: String, base_url: String = DEFAULT_SYNC_BASE_URL) -> void:
	_ensure_layers_dir()
	_link_token = token.strip_edges()
	var clean_url: String = base_url.strip_edges().trim_suffix("/")
	if not clean_url.is_empty():
		_sync_base_url = clean_url
	var cfg := ConfigFile.new()
	cfg.set_value("layers", "link_token", _link_token)
	cfg.set_value("layers", "sync_base_url", _sync_base_url)
	cfg.save(LINK_CFG_PATH)


func clear_link_token() -> void:
	_link_token = ""
	_pending_requests.clear()
	if FileAccess.file_exists(LINK_CFG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LINK_CFG_PATH))
	if FileAccess.file_exists(CACHE_JSON_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_JSON_PATH))


func load_cached_epic() -> Dictionary:
	if not FileAccess.file_exists(CACHE_JSON_PATH):
		return {}
	var file: FileAccess = FileAccess.open(CACHE_JSON_PATH, FileAccess.READ)
	if file == null:
		return {}
	var raw_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {}


func save_cached_epic(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	_write_cache(payload)


func _write_cache(payload: Dictionary) -> void:
	_ensure_layers_dir()
	var file: FileAccess = FileAccess.open(CACHE_JSON_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload))
		file.close()


func _ensure_layers_dir() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(CONFIG_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var gdignore_path := "%s/.gdignore" % CONFIG_DIR
	if not FileAccess.file_exists(gdignore_path):
		var f_gd: FileAccess = FileAccess.open(gdignore_path, FileAccess.WRITE)
		if f_gd != null:
			f_gd.store_string("")
			f_gd.close()
	var gitignore_path := "%s/.gitignore" % CONFIG_DIR
	if not FileAccess.file_exists(gitignore_path):
		var f_git: FileAccess = FileAccess.open(gitignore_path, FileAccess.WRITE)
		if f_git != null:
			f_git.store_string("*\n")
			f_git.close()


func start_google_sign_in(
	project_name: String,
	web_studio_url: String = DEFAULT_WEB_STUDIO_URL,
	open_browser: bool = true
) -> Dictionary:
	cancel_google_sign_in()
	randomize()
	var srv := TCPServer.new()
	var chosen_port: int = 0
	for _attempt in range(24):
		var candidate: int = 49200 + (randi() % 10000)
		if srv.listen(candidate, "127.0.0.1") == OK:
			chosen_port = candidate
			break
	if chosen_port <= 0:
		auth_status_changed.emit(false, "Could not bind local loopback port for Google Sign-In.")
		return {"ok": false, "error": "Could not bind 127.0.0.1 loopback port."}

	_auth_tcp = srv
	_auth_port = chosen_port
	_auth_state = "%08x%08x" % [randi(), randi()]
	_auth_started_msec = Time.get_ticks_msec()
	_auth_peers.clear()

	var clean_base: String = web_studio_url.strip_edges()
	if clean_base.is_empty():
		clean_base = DEFAULT_WEB_STUDIO_URL
	if not clean_base.ends_with("/"):
		clean_base += "/"
	var clean_name: String = project_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "GodotProject"
	var auth_url: String = "%s?godot_auth=1&port=%d&state=%s&project_name=%s" % [
		clean_base,
		_auth_port,
		_auth_state.uri_encode(),
		clean_name.uri_encode(),
	]

	auth_status_changed.emit(true, "Waiting for Google Sign-In in browser (127.0.0.1:%d)..." % _auth_port)
	if open_browser:
		OS.shell_open(auth_url)

	return {
		"ok": true,
		"port": _auth_port,
		"state": _auth_state,
		"url": auth_url,
	}


func cancel_google_sign_in() -> void:
	for p_item in _auth_peers:
		var peer_v: Variant = p_item.get("peer", null)
		if peer_v is StreamPeerTCP:
			(peer_v as StreamPeerTCP).disconnect_from_host()
	_auth_peers.clear()
	if _auth_tcp != null:
		_auth_tcp.stop()
		_auth_tcp = null
	var was_waiting: bool = not _auth_state.is_empty()
	_auth_port = 0
	_auth_state = ""
	_auth_started_msec = 0
	if was_waiting:
		auth_status_changed.emit(false, "Google Sign-In canceled.")


func poll_loopback_auth() -> void:
	if _auth_tcp == null or not _auth_tcp.is_listening():
		return
	var now_msec: int = Time.get_ticks_msec()
	if _auth_started_msec > 0 and now_msec - _auth_started_msec > LOOPBACK_TIMEOUT_MSEC:
		cancel_google_sign_in()
		auth_status_changed.emit(false, "Google Sign-In timed out. Click ⚡ Sign in with Google to retry.")
		return

	while _auth_tcp.is_connection_available():
		var incoming: StreamPeerTCP = _auth_tcp.take_connection()
		if incoming != null:
			_auth_peers.append({
				"peer": incoming,
				"buf": "",
				"started_msec": now_msec,
			})

	var idx: int = _auth_peers.size() - 1
	while idx >= 0:
		var item: Dictionary = _auth_peers[idx]
		var peer: StreamPeerTCP = item.get("peer", null) as StreamPeerTCP
		if peer == null:
			_auth_peers.remove_at(idx)
			idx -= 1
			continue
		peer.poll()
		var status: int = peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			peer.disconnect_from_host()
			_auth_peers.remove_at(idx)
			idx -= 1
			continue
		var avail: int = peer.get_available_bytes()
		if avail > 0:
			var got: Array = peer.get_data(avail)
			if got.size() >= 2 and int(got[0]) == OK:
				var bytes: PackedByteArray = got[1] as PackedByteArray
				item["buf"] = str(item.get("buf", "")) + bytes.get_string_from_utf8()
		var buf_str: String = str(item.get("buf", ""))
		if "\r\n\r\n" in buf_str or "\n\n" in buf_str:
			if idx < _auth_peers.size():
				_auth_peers.remove_at(idx)
			var handled_ok: bool = _handle_loopback_http_request(peer, buf_str)
			if handled_ok:
				return
		elif now_msec - int(item.get("started_msec", now_msec)) > 5000:
			peer.disconnect_from_host()
			_auth_peers.remove_at(idx)
		idx -= 1


func _handle_loopback_http_request(peer: StreamPeerTCP, raw_http: String) -> bool:
	var first_line: String = raw_http.split("\n", false, 1)[0].strip_edges()
	var parts: PackedStringArray = first_line.split(" ", false)
	if parts.size() < 2:
		_send_loopback_response(peer, 400, "text/plain", "Bad Request")
		return false

	if parts[0].strip_edges().to_upper() == "OPTIONS":
		_send_loopback_response(peer, 204, "text/plain", "")
		return false

	var req_target: String = parts[1].strip_edges()
	var q_pos: int = req_target.find("?")
	var req_path: String = req_target.substr(0, q_pos) if q_pos >= 0 else req_target
	var query_str: String = req_target.substr(q_pos + 1) if q_pos >= 0 else ""

	if req_path == "/favicon.ico":
		_send_loopback_response(peer, 204, "text/plain", "")
		return false

	var params: Dictionary = _parse_query_string(query_str)
	var state_val: String = str(params.get("state", "")).strip_edges()
	var token_val: String = str(params.get("token", "")).strip_edges()
	var proj_val: String = str(params.get("project", "")).strip_edges()

	if state_val != _auth_state or not (token_val.begins_with("lyr_") and token_val.length() >= 20):
		_send_loopback_response(peer, 400, "text/plain", "Invalid state or Godot Link Token.")
		return false

	save_link_token(token_val, _sync_base_url)
	var html := "<!doctype html><html><body style=\"font-family:sans-serif;background:#0f172a;color:#e2e8f0;padding:32px\"><h2>LAYERS Connected to Godot 4</h2><p>Linked project: <strong>%s</strong></p><p>You can close this tab and return to Godot Editor.</p></body></html>" % [
		proj_val.xml_escape() if not proj_val.is_empty() else "Godot 4"
	]
	_send_loopback_response(peer, 200, "text/html", html)

	if _auth_tcp != null:
		_auth_tcp.stop()
		_auth_tcp = null
	_auth_port = 0
	_auth_state = ""
	_auth_started_msec = 0
	for p_item in _auth_peers:
		var other_peer: Variant = p_item.get("peer", null)
		if other_peer is StreamPeerTCP and other_peer != peer:
			(other_peer as StreamPeerTCP).disconnect_from_host()
	_auth_peers.clear()

	auth_status_changed.emit(false, "Connected to %s" % (proj_val if not proj_val.is_empty() else "LAYERS"))
	auth_completed.emit(proj_val)
	return true


func _send_loopback_response(peer: StreamPeerTCP, status_code: int, content_type: String, body_text: String) -> void:
	var reason := "OK"
	if status_code == 400:
		reason = "Bad Request"
	elif status_code == 204:
		reason = "No Content"
	var body_bytes: PackedByteArray = body_text.to_utf8_buffer()
	var header := "HTTP/1.1 %d %s\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: %s; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
		status_code,
		reason,
		content_type,
		body_bytes.size(),
	]
	var full_bytes: PackedByteArray = header.to_utf8_buffer()
	full_bytes.append_array(body_bytes)
	peer.put_data(full_bytes)
	peer.disconnect_from_host()


func _parse_query_string(qs: String) -> Dictionary:
	var out: Dictionary = {}
	if qs.is_empty():
		return out
	for seg in qs.split("&", false):
		var eq: int = seg.find("=")
		if eq < 0:
			out[seg.replace("+", " ").uri_decode()] = ""
		else:
			var k: String = seg.substr(0, eq).replace("+", " ").uri_decode()
			var v: String = seg.substr(eq + 1).replace("+", " ").uri_decode()
			out[k] = v
	return out


func fetch_active_epic(live_context: Dictionary = {}, preferred_epic_id: String = "", preferred_feature_id: String = "") -> void:
	if not has_link_token() or _agent_busy:
		return
	_ensure_http_nodes()
	var body_dict: Dictionary = {}
	if not live_context.is_empty():
		body_dict["godotContext"] = live_context
	if not preferred_epic_id.strip_edges().is_empty():
		body_dict["epicId"] = preferred_epic_id.strip_edges()
	if not preferred_feature_id.strip_edges().is_empty():
		body_dict["featureId"] = preferred_feature_id.strip_edges()
	_dispatch_or_queue({
		"kind": "get_epic",
		"method": HTTPClient.METHOD_POST,
		"path": "/godotLink/epic",
		"body": JSON.stringify(body_dict),
	})


func push_epic_mutation(payload_dict: Dictionary, live_context: Dictionary = {}) -> void:
	if not has_link_token():
		return
	_ensure_http_nodes()
	var body: Dictionary = payload_dict.duplicate(true)
	if not live_context.is_empty() and not body.has("godotContext"):
		body["godotContext"] = live_context
	_dispatch_or_queue({
		"kind": "update",
		"method": HTTPClient.METHOD_POST,
		"path": "/godotLink/update",
		"body": JSON.stringify(body),
	})


func run_epic_agent(
	action: String,
	epic_id: String,
	scene_snapshot: Variant,
	live_scripts: Dictionary,
	live_context: Dictionary,
	arena_scene_path: String = "",
	epic_scene_path: String = "",
	prompt_text: String = "",
	error_text: String = "",
	input_map_snapshot: Dictionary = {},
	project_diagnostics: Array = [],
	feature_id: String = ""
) -> void:
	if not has_link_token():
		sync_failed.emit("Connect Godot 4 to LAYERS first.")
		return
	if _agent_busy:
		return
	_ensure_http_nodes()

	var payload := {
		"action": action,
		"epicId": epic_id,
		"sceneSnapshot": scene_snapshot,
		"liveScripts": live_scripts,
		"godotContext": live_context,
		"arenaScenePath": arena_scene_path,
		"epicScenePath": epic_scene_path,
	}
	if not feature_id.strip_edges().is_empty():
		payload["featureId"] = feature_id.strip_edges()
	if not prompt_text.strip_edges().is_empty():
		payload["prompt"] = prompt_text.strip_edges()
	if not error_text.strip_edges().is_empty():
		payload["errorText"] = error_text.strip_edges()
	if not input_map_snapshot.is_empty():
		payload["inputMapSnapshot"] = input_map_snapshot
	if not project_diagnostics.is_empty():
		payload["projectDiagnostics"] = project_diagnostics

	_agent_busy = true
	_emit_busy_state()

	var url := "%s/godotLink/update" % _sync_base_url
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % _link_token,
		"Content-Type: application/json",
	])
	var err: int = _agent_http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_agent_busy = false
		_emit_busy_state()
		sync_failed.emit("Agent HTTP request failed (%s)" % error_string(err))


func _dispatch_or_queue(req: Dictionary) -> void:
	if _is_busy:
		var kind: String = str(req.get("kind", "")).strip_edges()
		if kind == "get_epic":
			for i in range(_pending_requests.size() - 1, -1, -1):
				var existing: Dictionary = _pending_requests[i]
				if str(existing.get("kind", "")) == "get_epic":
					_pending_requests.remove_at(i)
			_pending_requests.append(req)
		elif _pending_requests.size() < 32:
			_pending_requests.append(req)
		return
	if _http == null:
		return
	_start_request(req)


func _emit_busy_state() -> void:
	busy_changed.emit(_is_busy or _agent_busy)
	agent_busy_changed.emit(_agent_busy)


func _start_request(req: Dictionary) -> void:
	_is_busy = true
	_emit_busy_state()

	var url := "%s%s" % [_sync_base_url, str(req.get("path", ""))]
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % _link_token,
		"Content-Type: application/json",
	])
	var method := int(req.get("method", HTTPClient.METHOD_POST))
	var body := str(req.get("body", ""))

	var err: int = _http.request(url, headers, method, body)
	if err != OK:
		_is_busy = false
		_emit_busy_state()
		sync_failed.emit("HTTP request failed (%s)" % error_string(err))


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_busy = false
	_emit_busy_state()

	var text: String = body.get_string_from_utf8()
	var parsed_raw: Variant = JSON.parse_string(text)

	if result != HTTPRequest.RESULT_SUCCESS:
		sync_failed.emit("Offline or network error (%d)" % result)
	elif response_code < 200 or response_code >= 300:
		var err_msg: String = _extract_error_message(parsed_raw, "Sync error (%d)" % response_code)
		sync_failed.emit(err_msg)
	elif typeof(parsed_raw) == TYPE_DICTIONARY:
		var parsed: Dictionary = parsed_raw as Dictionary
		if bool(parsed.get("ok", false)):
			if not _agent_busy and _pending_requests.is_empty():
				_write_cache(parsed)
				epic_updated.emit(parsed)
		else:
			sync_failed.emit("Unexpected sync response.")
	else:
		sync_failed.emit("Unexpected sync response.")

	if not _pending_requests.is_empty():
		var next_raw: Variant = _pending_requests.pop_front()
		if typeof(next_raw) == TYPE_DICTIONARY:
			var next_req: Dictionary = next_raw as Dictionary
			_start_request(next_req)


func _on_agent_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_agent_busy = false
	_emit_busy_state()

	var text: String = body.get_string_from_utf8()
	var parsed_raw: Variant = JSON.parse_string(text)

	if result != HTTPRequest.RESULT_SUCCESS:
		sync_failed.emit("Cloud Gemini agent timed out or offline (%d)." % result)
		return
	if response_code < 200 or response_code >= 300:
		var err_msg: String = _extract_error_message(parsed_raw, "Agent error (%d)" % response_code)
		sync_failed.emit(err_msg)
		return
	if typeof(parsed_raw) != TYPE_DICTIONARY:
		sync_failed.emit("Unexpected Cloud Gemini response.")
		return

	var parsed: Dictionary = parsed_raw as Dictionary
	if not bool(parsed.get("ok", false)):
		sync_failed.emit(_extract_error_message(parsed, "Cloud Gemini build failed."))
		return

	var bundle_v: Variant = parsed.get("agentBundle", {})
	var bundle: Dictionary = bundle_v as Dictionary if typeof(bundle_v) == TYPE_DICTIONARY else {}
	_write_cache(parsed)
	epic_updated.emit(parsed)
	agent_bundle_received.emit(bundle, parsed)


func _extract_error_message(parsed_raw: Variant, fallback: String) -> String:
	if typeof(parsed_raw) == TYPE_DICTIONARY:
		var d: Dictionary = parsed_raw as Dictionary
		var err_v: Variant = d.get("error", {})
		if typeof(err_v) == TYPE_DICTIONARY:
			var ed: Dictionary = err_v as Dictionary
			var msg: String = str(ed.get("message", "")).strip_edges()
			if not msg.is_empty():
				return msg
	return fallback


func get_local_plugin_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PLUGIN_CFG_PATH) == OK:
		var ver_raw: Variant = cfg.get_value("plugin", "version", "0.0.0")
		var ver: String = str(ver_raw).strip_edges()
		if not ver.is_empty():
			return ver
	return "0.0.0"


func _parse_semver_parts(raw_ver: String) -> PackedInt32Array:
	var clean: String = raw_ver.strip_edges().trim_prefix("v").trim_prefix("V")
	var core: String = clean.split("-", false, 1)[0].split("+", false, 1)[0]
	var segs: PackedStringArray = core.split(".", false)
	var out := PackedInt32Array()
	for s in segs:
		var t: String = s.strip_edges()
		out.append(t.to_int() if t.is_valid_int() else 0)
	return out


func _is_newer_version(local_ver: String, remote_ver: String) -> bool:
	var loc: PackedInt32Array = _parse_semver_parts(local_ver)
	var rem: PackedInt32Array = _parse_semver_parts(remote_ver)
	if rem.is_empty():
		return false
	var max_len: int = maxi(loc.size(), rem.size())
	for i in range(max_len):
		var l_val: int = loc[i] if i < loc.size() else 0
		var r_val: int = rem[i] if i < rem.size() else 0
		if r_val > l_val:
			return true
		if r_val < l_val:
			return false
	return false


func check_for_plugin_update(silent: bool = true) -> void:
	_ensure_http_nodes()
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
	var err: int = _update_http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_update_busy = false
		_update_mode = ""
		if not _update_silent:
			update_failed.emit("Could not check GitHub for plugin updates (%s)." % error_string(err))


func download_and_apply_plugin_update() -> void:
	_ensure_http_nodes()
	if _update_http == null or _update_busy:
		return
	_update_busy = true
	_update_mode = "download"
	_update_silent = false
	_update_zip_attempt_idx = 0
	_start_zip_download_attempt(0)


func _start_zip_download_attempt(idx: int) -> void:
	var zip_urls := PackedStringArray([REMOTE_ZIP_PRIMARY_URL, REMOTE_ZIP_FALLBACK_URL])
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
	var err: int = _update_http.request(url, headers, HTTPClient.METHOD_GET)
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
		var text: String = body.get_string_from_utf8()
		if cfg.parse(text) != OK:
			if not _update_silent:
				update_failed.emit("Could not parse remote plugin version.")
			return
		var remote_raw: Variant = cfg.get_value("plugin", "version", "")
		var remote_ver: String = str(remote_raw).strip_edges()
		var local_ver: String = get_local_plugin_version()
		if remote_ver.is_empty():
			if not _update_silent:
				update_failed.emit("Remote plugin version is empty.")
			return
		if _is_newer_version(local_ver, remote_ver):
			update_available.emit(local_ver, remote_ver)
			update_check_finished.emit(false, local_ver, remote_ver)
		else:
			update_check_finished.emit(true, local_ver, remote_ver)
		return

	if mode == "download":
		var zip_urls := PackedStringArray([REMOTE_ZIP_PRIMARY_URL, REMOTE_ZIP_FALLBACK_URL])
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
	var tmp_file: FileAccess = FileAccess.open(UPDATE_TMP_ZIP_PATH, FileAccess.WRITE)
	if tmp_file == null:
		_update_busy = false
		_update_mode = ""
		update_failed.emit("Could not write temporary plugin update archive.")
		return
	tmp_file.store_buffer(zip_bytes)
	tmp_file.close()

	var tmp_abs: String = ProjectSettings.globalize_path(UPDATE_TMP_ZIP_PATH)
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
		if not entry.begins_with("addons/layers/") or entry.ends_with("/") or ".." in entry:
			continue
		var data: PackedByteArray = reader.read_file(entry)
		var dest_res: String = "res://" + entry
		var dest_dir_abs: String = ProjectSettings.globalize_path(dest_res.get_base_dir())
		if not DirAccess.dir_exists_absolute(dest_dir_abs):
			DirAccess.make_dir_recursive_absolute(dest_dir_abs)
		var out_f: FileAccess = FileAccess.open(dest_res, FileAccess.WRITE)
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
			if ResourceLoader.has_cached(dest_res):
				var cached_v: Variant = ResourceLoader.load(dest_res)
				if cached_v is GDScript:
					var cached_gds: GDScript = cached_v as GDScript
					cached_gds.source_code = data.get_string_from_utf8()
					cached_gds.reload(true)

	reader.close()
	DirAccess.remove_absolute(tmp_abs)

	_update_busy = false
	_update_mode = ""
	var new_ver: String = get_local_plugin_version()
	update_ready_to_reload.emit(new_ver, updated_gd_paths)
