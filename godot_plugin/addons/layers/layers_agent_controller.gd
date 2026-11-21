@tool
extends RefCounted

# Cloud Gemini multi_turn_v1 agent loop, compact project manifest, error logger & Playtest CTA state
# for LAYERS Godot 4 Editor Dock.

const MAX_AGENT_TURNS := 6
const MAX_AUTO_HEAL_ATTEMPTS := 3


class _LayersEditorLogger extends Logger:
	var _mutex := Mutex.new()
	var _entries: Array[Dictionary] = []

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type == 1:
			return
		var raw_msg: String = rationale if not rationale.strip_edges().is_empty() else code
		var combined: String = ("%s (%s:%d in %s)" % [raw_msg.strip_edges(), file, line, function]).strip_edges()
		var lower: String = combined.to_lower()
		if (
			"addons/layers/" in lower or
			"gdscript://" in lower or
			"progress_dialog.cpp" in lower or
			"editoricons" in lower or
			"vulkan" in lower or
			"orphan string" in lower or
			raw_msg.strip_edges().is_empty()
		):
			return
		var prefix: String = "SCRIPT ERROR: " if error_type == 2 else "ERROR: "
		var formatted: String = (prefix + combined).left(340)
		var now_unix: float = Time.get_unix_time_from_system()
		_mutex.lock()
		if _entries.size() >= 24:
			_entries.pop_front()
		_entries.append({ "ts": now_unix, "msg": formatted })
		_mutex.unlock()

	func snapshot_errors(since_unix: float = 0.0) -> Array[String]:
		var out: Array[String] = []
		_mutex.lock()
		for item in _entries:
			var ts: float = float(item.get("ts", 0.0))
			if since_unix <= 0.0 or ts >= since_unix:
				out.append(str(item.get("msg", "")))
		_mutex.unlock()
		return out

	func clear() -> void:
		_mutex.lock()
		_entries.clear()
		_mutex.unlock()

	func inject(msg: String) -> void:
		var clean: String = msg.strip_edges().left(340)
		if clean.is_empty():
			return
		_mutex.lock()
		if _entries.size() >= 24:
			_entries.pop_front()
		_entries.append({ "ts": Time.get_unix_time_from_system() + 1.0, "msg": clean })
		_mutex.unlock()



var _dock: Variant = null


func _init(dock_ref: Variant = null) -> void:
	_dock = dock_ref


func create_editor_logger() -> Logger:
	return _LayersEditorLogger.new()


func _dock_as_editor_interface() -> EditorInterface:
	return _dock.call("_as_editor_interface") as EditorInterface if _dock != null else null


func _dock_as_undo_redo() -> EditorUndoRedoManager:
	return _dock.call("_as_undo_redo") as EditorUndoRedoManager if _dock != null else null


func _dock_collect_live_context() -> Dictionary:
	return _dock.call("_collect_live_context") as Dictionary if _dock != null else {}


func _dock_on_agent_busy_changed(busy: bool) -> void:
	if _dock != null:
		_dock.call("_on_agent_busy_changed", busy)


func _dock_refresh_ui() -> void:
	if _dock != null:
		_dock.call("_refresh_ui")


func _dock_set_status(msg: String, is_err: bool) -> void:
	if _dock != null:
		_dock.call("_set_status", msg, is_err)


func _extract_tscn_paths_from_text(raw_text: String) -> PackedStringArray:
	var out := PackedStringArray()
	if raw_text.strip_edges().is_empty():
		return out
	var rx := RegEx.new()
	rx.compile("res://[A-Za-z0-9_./-]+\\.tscn")
	for m in rx.search_all(raw_text):
		var p: String = m.get_string(0).strip_edges()
		if not p.is_empty() and not (p in out):
			out.append(p)
	return out


func _resolve_play_scene_path() -> String:
	var candidates := PackedStringArray()
	if not _dock._last_built_scene_path.strip_edges().is_empty():
		candidates.append(_dock._last_built_scene_path.strip_edges())
	var arena_scene: String = str(_dock._payload.get("arenaScenePath", "")).strip_edges()
	if not arena_scene.is_empty():
		candidates.append(arena_scene)
	var epic: Dictionary = _get_active_epic()
	if not epic.is_empty():
		for own_path in _collect_epic_ownership_paths(epic):
			if str(own_path).ends_with(".tscn"):
				candidates.append(str(own_path))
		for sp in _extract_tscn_paths_from_text(str(epic.get("levelStaging", ""))):
			candidates.append(sp)
		var links_v: Variant = epic.get("links", [])
		if typeof(links_v) == TYPE_ARRAY:
			for lk in (links_v as Array):
				for sp2 in _extract_tscn_paths_from_text(str(lk)):
					candidates.append(sp2)
	var main_sc: String = str(ProjectSettings.get_setting("application/run/main_scene", "")).strip_edges()
	if not main_sc.is_empty():
		candidates.append(main_sc)
	if _dock.editor_interface != null and _dock.editor_interface.has_method("get_edited_scene_root"):
		var ed_raw: Variant = _dock.editor_interface.call("get_edited_scene_root")
		if ed_raw != null and ed_raw is Node:
			var ed_path: String = String((ed_raw as Node).scene_file_path).strip_edges()
			if not ed_path.is_empty():
				candidates.append(ed_path)
	if _dock._executor != null and _dock._executor.has_method("collect_project_scene_paths"):
		var proj_raw: Variant = _dock._executor.call("collect_project_scene_paths", "res://", 8)
		if typeof(proj_raw) == TYPE_ARRAY or typeof(proj_raw) == TYPE_PACKED_STRING_ARRAY:
			for ps in proj_raw:
				candidates.append(str(ps).strip_edges())
	for c in candidates:
		if not c.is_empty() and c.ends_with(".tscn") and FileAccess.file_exists(c):
			return c
	return ""


func _collect_recent_errors() -> Array[String]:
	var errs: Array[String] = []
	var logger_errs: Array[String] = []
	if _dock._logger != null:
		logger_errs = _dock._logger.snapshot_errors(_dock._errors_cleared_unix)
		for le in logger_errs:
			_dock._ignored_error_signatures.erase(le)
			if not errs.has(le):
				errs.append(le)
	var base_ctrl: Node = null
	if _dock.editor_interface != null and _dock.editor_interface.has_method("get_base_control"):
		var bc_raw: Variant = _dock.editor_interface.call("get_base_control")
		if bc_raw is Node:
			base_ctrl = bc_raw as Node
	if _dock._executor != null and (base_ctrl != null or not logger_errs.is_empty()):
		var ed_raw: Variant = _dock._executor.call(
			"read_editor_and_playtest_errors",
			base_ctrl,
			logger_errs,
			_dock._ignored_error_signatures,
			_dock._errors_cleared_unix,
			5
		)
		if typeof(ed_raw) == TYPE_ARRAY or typeof(ed_raw) == TYPE_PACKED_STRING_ARRAY:
			for e in ed_raw:
				var es: String = str(e).strip_edges()
				if not es.is_empty() and not _dock._ignored_error_signatures.has(es) and not errs.has(es):
					errs.append(es)
	return errs


func _acknowledge_resolved_errors() -> void:
	var cur_errs: Array[String] = _collect_recent_errors()
	for e in cur_errs:
		_dock._ignored_error_signatures[e] = true
	_dock._errors_cleared_unix = Time.get_unix_time_from_system()
	if _dock._logger != null:
		_dock._logger.clear()


func clear_captured_errors() -> void:
	_acknowledge_resolved_errors()
	_dock_refresh_ui()
	_dock_set_status("Cleared captured errors.", false)


func inject_test_error(msg: String) -> void:
	var clean: String = msg.strip_edges().left(340)
	if clean.is_empty():
		return
	if _dock._logger == null:
		_dock._logger = _LayersEditorLogger.new()
	_dock._ignored_error_signatures.erase(clean)
	_dock._logger.inject(clean)
	_dock_refresh_ui()


func _get_active_epic() -> Dictionary:
	var ep_v: Variant = _dock._payload.get("activeEpic", {})
	if typeof(ep_v) == TYPE_DICTIONARY:
		return ep_v as Dictionary
	return {}


func _get_active_feature() -> Dictionary:
	var feat_v: Variant = _dock._payload.get("activeFeature", null)
	if typeof(feat_v) == TYPE_DICTIONARY:
		return feat_v as Dictionary
	return {}


func _is_active_feature_locked() -> bool:
	var feat: Dictionary = _get_active_feature()
	if feat.is_empty():
		return false
	if bool(feat.get("isLockedBaseline", false)):
		return true
	var fid: String = str(feat.get("id", ""))
	var feats_v: Variant = _dock._payload.get("activeEpicFeatures", [])
	if typeof(feats_v) == TYPE_ARRAY:
		for fv in (feats_v as Array):
			if typeof(fv) == TYPE_DICTIONARY and str((fv as Dictionary).get("id", "")) == fid:
				return bool((fv as Dictionary).get("isLockedBaseline", false))
	return false


func _get_active_target() -> Dictionary:
	var feat: Dictionary = _get_active_feature()
	return feat if not feat.is_empty() else _get_active_epic()


func _get_active_target_code() -> String:
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		return str(feat.get("code", "F01"))
	var epic: Dictionary = _get_active_epic()
	return str(epic.get("code", "E01"))


func _get_active_target_checks() -> Array:
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		var eff_v: Variant = feat.get("effectiveChecks", null)
		if typeof(eff_v) == TYPE_ARRAY and not (eff_v as Array).is_empty():
			return eff_v as Array
		var fchk_v: Variant = feat.get("checks", [])
		return fchk_v as Array if typeof(fchk_v) == TYPE_ARRAY else []
	var epic: Dictionary = _get_active_epic()
	var echk_v: Variant = epic.get("checks", [])
	return echk_v as Array if typeof(echk_v) == TYPE_ARRAY else []


func _get_active_target_open_fixes_count() -> int:
	var target: Dictionary = _get_active_target()
	var raw_open: Variant = target.get("openFixes", null)
	if typeof(raw_open) == TYPE_ARRAY:
		return (raw_open as Array).size()
	return int(target.get("openFixesCount", 0))


func _get_active_target_is_passed() -> bool:
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		if _is_active_feature_locked():
			return true
		if feat.has("isPassed"):
			return bool(feat.get("isPassed", false))
		return str(feat.get("status", "")).strip_edges().to_lower() == "passed" and _get_active_target_open_fixes_count() == 0
	var epic: Dictionary = _get_active_epic()
	return bool(epic.get("isPassed", false))


func _collect_epic_ownership_paths(epic: Dictionary) -> Array:
	var paths := []
	var add_res := func(raw_p: String) -> void:
		var clean: String = raw_p.strip_edges()
		if not clean.is_empty() and not paths.has(clean):
			paths.append(clean)
	var own_v: Variant = epic.get("sceneOwnership", [])
	if typeof(own_v) == TYPE_ARRAY:
		for ov in (own_v as Array):
			if typeof(ov) == TYPE_DICTIONARY:
				add_res.call(str((ov as Dictionary).get("path", "")))
			else:
				add_res.call(str(ov))
	var res_rx := RegEx.new()
	res_rx.compile("res://[A-Za-z0-9_./-]+")
	for src in [str(epic.get("levelStaging", "")), str(_dock._payload.get("arenaScenePath", ""))]:
		for m in res_rx.search_all(src):
			add_res.call(m.get_string())
	var links_v: Variant = epic.get("links", [])
	if typeof(links_v) == TYPE_ARRAY:
		for lk in (links_v as Array):
			for m2 in res_rx.search_all(str(lk)):
				add_res.call(m2.get_string())
	return paths


func _get_active_epic_open_fixes_count(epic: Dictionary) -> int:
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		return _get_active_target_open_fixes_count()
	var raw_open: Variant = epic.get("openFixes", null)
	if typeof(raw_open) == TYPE_ARRAY:
		return (raw_open as Array).size()
	return int(epic.get("openFixesCount", 0))


func _sync_active_epic_summary_counts() -> void:
	var epic: Dictionary = _get_active_epic()
	if epic.is_empty():
		return
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		var fid: String = str(feat.get("id", ""))
		var f_open: int = _get_active_target_open_fixes_count()
		feat["openFixesCount"] = f_open
		var f_checks: Array = _get_active_target_checks()
		var f_passed: int = 0
		for cv in f_checks:
			if typeof(cv) == TYPE_DICTIONARY and bool((cv as Dictionary).get("passed", false)):
				f_passed += 1
		feat["passedChecksCount"] = f_passed
		var feats_v: Variant = _dock._payload.get("activeEpicFeatures", [])
		if typeof(feats_v) == TYPE_ARRAY:
			for fv in (feats_v as Array):
				if typeof(fv) == TYPE_DICTIONARY and str((fv as Dictionary).get("id", "")) == fid:
					var fsum: Dictionary = fv as Dictionary
					fsum["openFixesCount"] = f_open
					fsum["passedChecksCount"] = f_passed
					fsum["isPassed"] = _get_active_target_is_passed()
		return

	var active_id: String = str(epic.get("id", ""))
	var open_fixes: int = _get_active_epic_open_fixes_count(epic)
	epic["openFixesCount"] = open_fixes
	var checks_raw: Variant = epic.get("checks", [])
	var checks: Array = checks_raw as Array if typeof(checks_raw) == TYPE_ARRAY else []
	var passed_count: int = 0
	for cv in checks:
		if typeof(cv) == TYPE_DICTIONARY and bool((cv as Dictionary).get("passed", false)):
			passed_count += 1
	epic["passedChecksCount"] = passed_count
	var summary_v: Variant = _dock._payload.get("releaseEpicsSummary", [])
	if typeof(summary_v) == TYPE_ARRAY:
		for sv in (summary_v as Array):
			if typeof(sv) == TYPE_DICTIONARY and str((sv as Dictionary).get("id", "")) == active_id:
				var sd: Dictionary = sv as Dictionary
				sd["openFixesCount"] = open_fixes
				sd["passedChecksCount"] = passed_count
				sd["isPassed"] = bool(epic.get("isPassed", false))


func compute_primary_cta_state() -> Dictionary:
	var epic: Dictionary = _get_active_epic()
	if epic.is_empty():
		return {"mode": "sync", "text": "↻ Sync Specs", "issue_count": 0}
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty() and _is_active_feature_locked():
		var intro_ver: String = str(feat.get("introducedIn", "v0.1"))
		return {"mode": "locked", "text": "🔒 Baseline Locked (%s)" % intro_ver, "issue_count": 0}
	var tcode: String = _get_active_target_code()
	var open_fixes: int = _get_active_target_open_fixes_count()
	var errs: Array[String] = _collect_recent_errors()
	var issue_count: int = open_fixes + errs.size()
	var checks: Array = _get_active_target_checks()
	var passed_count: int = 0
	if not checks.is_empty():
		for cv in checks:
			if typeof(cv) == TYPE_DICTIONARY and bool((cv as Dictionary).get("passed", false)):
				passed_count += 1
	else:
		passed_count = int(_get_active_target().get("passedChecksCount", 0))
	var is_passed: bool = _get_active_target_is_passed()

	if issue_count > 0:
		return {"mode": "fix", "text": "🔧 Fix %s (%d)" % [tcode, issue_count], "issue_count": issue_count}
	if not is_passed and not checks.is_empty() and passed_count >= checks.size():
		return {"mode": "pass", "text": "✓ Pass %s →" % tcode, "issue_count": 0}
	return {
		"mode": "build",
		"text": ("⚡ Rebuild %s" % tcode) if is_passed else ("⚡ Build %s" % tcode),
		"issue_count": 0,
	}


func _build_compact_project_manifest(
	epic: Dictionary,
	arena_scene: String,
	live_ctx: Dictionary,
	ed_int: EditorInterface
) -> Dictionary:
	var scene_files_v: Variant = live_ctx.get("scene_files", [])
	var scene_files: Array = scene_files_v as Array if (typeof(scene_files_v) == TYPE_ARRAY or typeof(scene_files_v) == TYPE_PACKED_STRING_ARRAY) else []
	var script_files_v: Variant = live_ctx.get("script_files", [])
	var script_files: Array = script_files_v as Array if (typeof(script_files_v) == TYPE_ARRAY or typeof(script_files_v) == TYPE_PACKED_STRING_ARRAY) else []
	var input_actions_v: Variant = live_ctx.get("input_actions", [])
	var input_actions: Array = input_actions_v as Array if (typeof(input_actions_v) == TYPE_ARRAY or typeof(input_actions_v) == TYPE_PACKED_STRING_ARRAY) else []
	var resource_files: Array = []
	if _dock._executor != null and _dock._executor.has_method("tool_list_project_files"):
		var tres_raw: Variant = _dock._executor.call("tool_list_project_files", {"dir": "res://", "ext": ".tres", "cap": 40})
		var tres_res: Dictionary = tres_raw as Dictionary if typeof(tres_raw) == TYPE_DICTIONARY else {}
		if bool(tres_res.get("ok", false)):
			var tres_arr_v: Variant = tres_res.get("files", [])
			if typeof(tres_arr_v) == TYPE_ARRAY or typeof(tres_arr_v) == TYPE_PACKED_STRING_ARRAY:
				resource_files = Array(tres_arr_v)
	var autoloads: Dictionary = {}
	var layer_names: Dictionary = {}
	if _dock._executor != null and _dock._executor.has_method("tool_read_autoloads_and_layers"):
		var proj_cfg_raw: Variant = _dock._executor.call("tool_read_autoloads_and_layers", {})
		var proj_cfg_res: Dictionary = proj_cfg_raw as Dictionary if typeof(proj_cfg_raw) == TYPE_DICTIONARY else {}
		if bool(proj_cfg_res.get("ok", false)):
			var auto_v: Variant = proj_cfg_res.get("autoloads", {})
			if typeof(auto_v) == TYPE_DICTIONARY:
				autoloads = (auto_v as Dictionary).duplicate(true)
			var layer_v: Variant = proj_cfg_res.get("layerNames", {})
			if typeof(layer_v) == TYPE_DICTIONARY:
				layer_names = (layer_v as Dictionary).duplicate(true)
	var manifest: Dictionary = {
		"sceneFiles": Array(scene_files).slice(0, 60),
		"scriptFiles": Array(script_files).slice(0, 60),
		"resourceFiles": resource_files.slice(0, 40),
		"inputActions": Array(input_actions),
		"autoloads": autoloads,
		"layerNames": layer_names,
		"ownershipPaths": _collect_epic_ownership_paths(epic),
		"activeScenePath": arena_scene,
	}
	if _dock._executor != null and FileAccess.file_exists(arena_scene) and _dock._executor.has_method("tool_inspect_scene_tree"):
		var tree_raw: Variant = _dock._executor.call("tool_inspect_scene_tree", {"path": arena_scene, "limitNodes": 60}, ed_int)
		var tree_res: Dictionary = tree_raw as Dictionary if typeof(tree_raw) == TYPE_DICTIONARY else {}
		if bool(tree_res.get("ok", false)):
			manifest["activeSceneSummary"] = {
				"path": arena_scene,
				"baseScenePath": str(tree_res.get("baseScenePath", "")),
				"nodes": tree_res.get("nodes", []),
			}
	return manifest


func _trigger_epic_agent(action: String, extra_error_text: String = "") -> void:
	if _dock._sync_client == null or _dock._executor == null:
		return
	var epic: Dictionary = _get_active_epic()
	if epic.is_empty():
		return
	var feat: Dictionary = _get_active_feature()
	var feature_id: String = str(feat.get("id", ""))
	var epic_id: String = str(epic.get("id", ""))
	var dim_str: String = str(_dock._payload.get("dimension", "dim3d")).strip_edges().to_lower()
	var default_arena: String = "res://scenes/arena_2d.tscn" if dim_str == "dim2d" else "res://scenes/arena_3d.tscn"
	var arena_scene: String = str(_dock._payload.get("arenaScenePath", "")).strip_edges()
	if arena_scene.is_empty():
		arena_scene = _resolve_play_scene_path()
	if arena_scene.is_empty():
		arena_scene = default_arena
	var live_ctx: Dictionary = _dock_collect_live_context()

	var ed_int: EditorInterface = _dock_as_editor_interface()
	var ownership_paths: Array = _collect_epic_ownership_paths(epic)
	var diag_scenes: Array = []
	var extra_scenes := PackedStringArray()
	var add_scene_cand := func(raw_s: String) -> void:
		var cs: String = raw_s.strip_edges()
		if not cs.is_empty() and cs.ends_with(".tscn") and not (cs in extra_scenes):
			extra_scenes.append(cs)
			diag_scenes.append(cs)
	for cand in [arena_scene, _resolve_play_scene_path()]:
		add_scene_cand.call(str(cand))
	for own_p in ownership_paths:
		add_scene_cand.call(str(own_p))

	var manifest: Dictionary = _build_compact_project_manifest(epic, arena_scene, live_ctx, ed_int)
	var input_v: Variant = _dock._executor.call("capture_input_map_snapshot")
	var input_snap: Dictionary = input_v as Dictionary if typeof(input_v) == TYPE_DICTIONARY else {}
	var diag_v: Variant = _dock._executor.call("diagnose_project_combat_and_wiring", diag_scenes, {}, ed_int)
	var diag_arr: Array = diag_v as Array if (typeof(diag_v) == TYPE_ARRAY or typeof(diag_v) == TYPE_PACKED_STRING_ARRAY) else []

	var errs: Array[String] = _collect_recent_errors()
	if not extra_error_text.strip_edges().is_empty():
		errs.append(extra_error_text.strip_edges())
	var target: Dictionary = _get_active_target()
	var open_fixes_v: Variant = target.get("openFixes", [])
	var prompt_parts := PackedStringArray()
	if typeof(open_fixes_v) == TYPE_ARRAY:
		for fx_raw in (open_fixes_v as Array):
			if typeof(fx_raw) == TYPE_DICTIONARY:
				var fxt: String = str((fx_raw as Dictionary).get("text", "")).strip_edges()
				if not fxt.is_empty():
					prompt_parts.append("[FIX] " + fxt)

	_dock._pending_build_preferred_scene = arena_scene
	_dock._agent_session = {
		"active": true,
		"cancelled": false,
		"action": action,
		"epic_id": epic_id,
		"feature_id": feature_id,
		"target_code": _get_active_target_code(),
		"arena_scene": arena_scene,
		"prompt_text": "\n".join(prompt_parts),
		"error_text": "\n".join(errs),
		"live_context": live_ctx,
		"project_manifest": manifest,
		"input_map_snapshot": input_snap,
		"project_diagnostics": diag_arr,
		"tool_history": [],
		"turn_index": 1,
		"max_turns": MAX_AGENT_TURNS,
		"tool_reads_count": 0,
		"steps_used": 0,
	}
	_dock_on_agent_busy_changed(true)
	_dispatch_agent_turn()


func _dispatch_agent_turn() -> void:
	if _dock._sync_client == null or _dock._agent_session.is_empty():
		return
	if not bool(_dock._agent_session.get("active", false)) or bool(_dock._agent_session.get("cancelled", false)):
		return
	var cur_turn: int = int(_dock._agent_session.get("turn_index", 1))
	var max_t: int = int(_dock._agent_session.get("max_turns", MAX_AGENT_TURNS))
	var action: String = str(_dock._agent_session.get("action", "build_feature"))
	var target_code: String = str(_dock._agent_session.get("target_code", _get_active_target_code()))
	var is_fix: bool = action == "fix_epic" or action == "fix_feature"
	_dock_set_status(
		"Step %d/%d: %s %s via Cloud Gemini..." % [cur_turn, max_t, "Fixing" if is_fix else "Building", target_code],
		false
	)
	var manifest_v: Variant = _dock._agent_session.get("project_manifest", {})
	var manifest: Dictionary = manifest_v as Dictionary if typeof(manifest_v) == TYPE_DICTIONARY else {}
	var history_v: Variant = _dock._agent_session.get("tool_history", [])
	var history: Array = history_v as Array if typeof(history_v) == TYPE_ARRAY else []
	var live_ctx_v: Variant = _dock._agent_session.get("live_context", {})
	var live_ctx: Dictionary = live_ctx_v as Dictionary if typeof(live_ctx_v) == TYPE_DICTIONARY else {}
	var arena_scene: String = str(_dock._agent_session.get("arena_scene", ""))
	var input_v: Variant = _dock._agent_session.get("input_map_snapshot", {})
	var input_snap: Dictionary = input_v as Dictionary if typeof(input_v) == TYPE_DICTIONARY else {}
	var diag_v: Variant = _dock._agent_session.get("project_diagnostics", [])
	var diag_arr: Array = diag_v as Array if typeof(diag_v) == TYPE_ARRAY else []
	_dock._sync_client.call(
		"run_epic_agent_step",
		action,
		str(_dock._agent_session.get("epic_id", "")),
		manifest,
		history,
		cur_turn,
		max_t,
		live_ctx,
		arena_scene,
		arena_scene,
		str(_dock._agent_session.get("prompt_text", "")),
		str(_dock._agent_session.get("error_text", "")),
		input_snap,
		diag_arr,
		str(_dock._agent_session.get("feature_id", ""))
	)


func _on_agent_step_received(agent_step: Dictionary, payload_resp: Dictionary) -> void:
	if not bool(_dock._agent_session.get("active", false)) or bool(_dock._agent_session.get("cancelled", false)):
		return
	var cur_turn: int = int(_dock._agent_session.get("turn_index", 1))
	var max_t: int = int(_dock._agent_session.get("max_turns", MAX_AGENT_TURNS))
	_dock._agent_session["steps_used"] = int(_dock._agent_session.get("steps_used", 0)) + 1

	var step_type: String = str(agent_step.get("type", "")).strip_edges().to_lower()
	var raw_calls_v: Variant = agent_step.get("toolCalls", agent_step.get("tool_calls", []))
	var raw_calls: Array = raw_calls_v as Array if typeof(raw_calls_v) == TYPE_ARRAY else []

	if step_type == "tool_calls" and not raw_calls.is_empty() and cur_turn < max_t:
		var history_v: Variant = _dock._agent_session.get("tool_history", [])
		var history: Array = history_v as Array if typeof(history_v) == TYPE_ARRAY else []
		var inspected_labels: PackedStringArray = PackedStringArray()
		var cap: int = mini(raw_calls.size(), 4)
		for i: int in range(cap):
			if not bool(_dock._agent_session.get("active", false)) or bool(_dock._agent_session.get("cancelled", false)):
				return
			var call_v: Variant = raw_calls[i]
			if typeof(call_v) != TYPE_DICTIONARY:
				continue
			var call_dict: Dictionary = call_v as Dictionary
			var tool_name: String = str(call_dict.get("tool", call_dict.get("name", ""))).strip_edges()
			var raw_args_v: Variant = call_dict.get("args", call_dict.get("arguments", {}))
			var args_dict: Dictionary = raw_args_v as Dictionary if typeof(raw_args_v) == TYPE_DICTIONARY else {}
			var res_raw: Variant = _dock._executor.call("execute_agent_tool_call", {
				"tool": tool_name,
				"args": args_dict,
			}, _dock.editor_interface) if _dock._executor != null else {"ok": false, "error": "Missing executor."}
			var res_dict: Dictionary = res_raw as Dictionary if typeof(res_raw) == TYPE_DICTIONARY else {"ok": false, "error": "Invalid tool response."}
			history.append({
				"turn": cur_turn,
				"tool": tool_name,
				"args": args_dict,
				"result": res_dict,
			})
			_dock._agent_session["tool_reads_count"] = int(_dock._agent_session.get("tool_reads_count", 0)) + 1
			var lbl_path: String = str(args_dict.get("path", args_dict.get("query", args_dict.get("dir", tool_name)))).get_file()
			if lbl_path.is_empty():
				lbl_path = tool_name
			if not (lbl_path in inspected_labels):
				inspected_labels.append(lbl_path)
		_dock._agent_session["tool_history"] = history
		if not bool(_dock._agent_session.get("active", false)) or bool(_dock._agent_session.get("cancelled", false)):
			return
		_dock._agent_session["turn_index"] = cur_turn + 1
		var inspected_txt: String = ", ".join(inspected_labels) if not inspected_labels.is_empty() else "project"
		_dock_set_status("Step %d/%d: Inspected %s — planning next step..." % [cur_turn + 1, max_t, inspected_txt], false)
		_dispatch_agent_turn()
		return

	var bundle_v: Variant = agent_step.get("bundle", {})
	var bundle: Dictionary = bundle_v as Dictionary if typeof(bundle_v) == TYPE_DICTIONARY else {}
	if bundle.is_empty() and typeof(payload_resp.get("agentBundle", null)) == TYPE_DICTIONARY:
		bundle = payload_resp.get("agentBundle") as Dictionary
	_dock._agent_session["active"] = false
	_dock_on_agent_busy_changed(false)
	_apply_final_agent_bundle(bundle, payload_resp)


func _on_cancel_agent_pressed() -> void:
	_dock._agent_session["cancelled"] = true
	_dock._agent_session["active"] = false
	_dock._auto_heal_count = 0
	if _dock._sync_client != null and _dock._sync_client.has_method("cancel_agent_request"):
		_dock._sync_client.call("cancel_agent_request")
	_dock_on_agent_busy_changed(false)
	_dock_set_status("Cancelled Cloud Gemini run (no files modified).", false)
	_dock_refresh_ui()


func _on_agent_bundle_received(agent_bundle: Dictionary, payload_resp: Dictionary) -> void:
	_dock._agent_session["active"] = false
	_dock_on_agent_busy_changed(false)
	_apply_final_agent_bundle(agent_bundle, payload_resp)


func format_agent_completion_summary(agent_bundle: Dictionary, res: Dictionary, session_override: Dictionary = {}) -> String:
	var sess: Dictionary = session_override if not session_override.is_empty() else (_dock._agent_session as Dictionary if _dock != null else {})
	var action: String = str(sess.get("action", agent_bundle.get("mode", "build_feature"))).strip_edges().to_lower()
	var verb: String = "Fixed" if (action == "fix_feature" or action == "fix_epic") else "Built"
	var target_code: String = str(sess.get("target_code", "")).strip_edges()
	if target_code.is_empty():
		target_code = _get_active_target_code()
	var steps_used: int = maxi(1, int(sess.get("steps_used", 0)))
	var step_lbl: String = "1 step" if steps_used == 1 else "%d steps" % steps_used
	var reads_count: int = maxi(0, int(sess.get("tool_reads_count", 0)))

	var patch_count: int = 0
	var su_v: Variant = agent_bundle.get("scriptUpdates", [])
	if typeof(su_v) == TYPE_ARRAY:
		for raw_su: Variant in (su_v as Array):
			if typeof(raw_su) == TYPE_DICTIONARY:
				var p_v: Variant = (raw_su as Dictionary).get("patches", [])
				if typeof(p_v) == TYPE_ARRAY:
					patch_count += (p_v as Array).size()

	var applied_scripts_v: Variant = res.get("applied_scripts", [])
	var applied_scripts_count: int = (applied_scripts_v as Array).size() if (typeof(applied_scripts_v) == TYPE_ARRAY or typeof(applied_scripts_v) == TYPE_PACKED_STRING_ARRAY) else 0
	var applied_ops: int = maxi(0, int(res.get("applied_ops", 0)))

	var details: PackedStringArray = PackedStringArray()
	if reads_count > 0:
		details.append("1 read" if reads_count == 1 else "%d reads" % reads_count)
	if patch_count > 0:
		details.append("1 patch" if patch_count == 1 else "%d patches" % patch_count)
	elif applied_scripts_count > 0:
		details.append("1 script" if applied_scripts_count == 1 else "%d scripts" % applied_scripts_count)
	if applied_ops > 0:
		details.append("1 scene op" if applied_ops == 1 else "%d scene ops" % applied_ops)

	if details.is_empty():
		return str(res.get("summary", agent_bundle.get("summary", "%s %s in %s" % [verb, target_code, step_lbl])))
	return "%s %s in %s (%s)" % [verb, target_code, step_lbl, ", ".join(details)]


func _format_agent_completion_summary(agent_bundle: Dictionary, res: Dictionary, session_override: Dictionary = {}) -> String:
	return format_agent_completion_summary(agent_bundle, res, session_override)


func _apply_final_agent_bundle(agent_bundle: Dictionary, _payload_resp: Dictionary) -> void:
	if _dock._executor == null or agent_bundle.is_empty():
		_dock._auto_heal_count = 0
		_dock_set_status("Cloud Gemini returned empty bundle.", true)
		_dock_refresh_ui()
		return

	var ed_int: EditorInterface = _dock_as_editor_interface()
	var snap_v: Variant = _dock._executor.call(
		"capture_bundle_snapshot",
		ed_int,
		agent_bundle,
		_dock._pending_build_preferred_scene
	)
	if typeof(snap_v) == TYPE_DICTIONARY:
		_dock._last_bundle_snapshot = snap_v as Dictionary
		if _dock._undo_btn != null:
			_dock._undo_btn.disabled = _dock._last_bundle_snapshot.is_empty()

	var res_v: Variant = _dock._executor.call(
		"apply_agent_bundle",
		ed_int,
		_dock_as_undo_redo(),
		agent_bundle,
		_dock._pending_build_preferred_scene
	)
	var res: Dictionary = res_v as Dictionary if typeof(res_v) == TYPE_DICTIONARY else {}

	for cand_path in [agent_bundle.get("epicScenePath", ""), agent_bundle.get("arenaScenePath", ""), _dock._pending_build_preferred_scene]:
		var cp: String = str(cand_path).strip_edges()
		if not cp.is_empty() and cp.ends_with(".tscn") and FileAccess.file_exists(cp):
			_dock._last_built_scene_path = cp
			break

	if ed_int != null:
		var rfs: Variant = ed_int.get_resource_filesystem()
		if rfs != null and rfs.has_method("scan"):
			rfs.call("scan")

	var compile_errs_v: Variant = res.get("compile_errors", PackedStringArray())
	var compile_errs: PackedStringArray = compile_errs_v as PackedStringArray if (typeof(compile_errs_v) == TYPE_PACKED_STRING_ARRAY or typeof(compile_errs_v) == TYPE_ARRAY) else PackedStringArray()
	if not compile_errs.is_empty() and _dock._auto_heal_count < MAX_AUTO_HEAL_ATTEMPTS:
		_dock._auto_heal_count = int(_dock._auto_heal_count) + 1
		var joined_err: String = "\n".join(compile_errs)
		var heal_action: String = "fix_feature" if not _get_active_feature().is_empty() else "fix_epic"
		_dock_set_status("Auto-repair %d/%d: fixing compile/patch error..." % [_dock._auto_heal_count, MAX_AUTO_HEAL_ATTEMPTS], true)
		_trigger_epic_agent(heal_action, joined_err)
		return

	_dock._auto_heal_count = 0
	var summary: String = _format_agent_completion_summary(agent_bundle, res)
	if not compile_errs.is_empty():
		_dock_set_status("Applied with compile warning: %s" % compile_errs[0], true)
	else:
		_acknowledge_resolved_errors()
		var epic: Dictionary = _get_active_epic()
		if _get_active_epic_open_fixes_count(epic) > 0:
			_dock_set_status("%s — press ▶ Play, then click ✓ on resolved [FIX] items." % summary, false)
		else:
			_dock_set_status(summary, false)
	_dock_refresh_ui()
