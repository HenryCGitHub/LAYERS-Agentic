@tool
extends RefCounted

# Compile probe, Playtest evaluation cache, editor log capture & wiring diagnostics
# for LAYERS Godot 4 Editor Plugin.

class _CompileProbeLogger extends Logger:
	var messages: PackedStringArray = PackedStringArray()

	static func format_entry(code: String, rationale: String, _file: String = "", line: int = 0) -> String:
		var c := code.strip_edges()
		var r := rationale.strip_edges()
		var body := r
		if body.is_empty():
			body = c
		elif not c.is_empty() and not (c.to_lower() in body.to_lower()):
			body = "%s: %s" % [c, body]
		if body.is_empty():
			body = "GDScript compile error"
		if line > 0 and not ("line %d" % line in body.to_lower()):
			body = "Line %d: %s" % [line, body]
		return body

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		_error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		var lower_file := file.to_lower()
		if not ("gdscript://" in lower_file or "gdscript://" in rationale.to_lower()):
			return
		var entry := format_entry(code, rationale, file, line)
		if not (entry in messages):
			messages.append(entry)




var _exec: Variant = null
var _eval_cache: Dictionary = {}
var _eval_cache_epoch: int = 0
var _cached_base_ctrl_id: int = 0
var _cached_debugger_roots: Array[Node] = []
var _cached_editor_log_roots: Array[Node] = []


func _init(exec_ref: Variant = null) -> void:
	_exec = exec_ref


func _scan_project_files_by_ext(root_dir: String, ext: String, cap: int = 80) -> PackedStringArray:
	if _exec != null:
		return _exec.call("_scan_project_files_by_ext", root_dir, ext, cap) as PackedStringArray
	return PackedStringArray()


func resolve_step_code_text(step: Dictionary) -> String:
	if _exec != null:
		return _exec.call("resolve_step_code_text", step) as String
	return String(step.get("code", step.get("gdscript", "")))


func resolve_effective_step_path(step: Dictionary, feat: Dictionary) -> String:
	if _exec != null:
		return _exec.call("resolve_effective_step_path", step, feat) as String
	return ""


func heal_empty_project_input_actions(feat: Dictionary = {}) -> int:
	if _exec != null:
		return _exec.call("heal_empty_project_input_actions", feat) as int
	return 0


func collect_project_scene_paths(root_dir: String = "res://", max_scenes: int = 120) -> PackedStringArray:
	if _exec != null:
		return _exec.call("collect_project_scene_paths", root_dir, max_scenes) as PackedStringArray
	return PackedStringArray()


func read_all_live_project_scripts(root_dir: String = "res://", editor_interface: EditorInterface = null) -> Dictionary:
	if _exec != null:
		return _exec.call("read_all_live_project_scripts", root_dir, editor_interface) as Dictionary
	return {}


func capture_input_map_snapshot() -> Dictionary:
	if _exec != null:
		return _exec.call("capture_input_map_snapshot") as Dictionary
	return {"ok": false, "actions": {}}


func _is_bogus_non_player_action_name(act_name: String) -> bool:
	if _exec != null:
		return _exec.call("_is_bogus_non_player_action_name", act_name) as bool
	return false


func _get_open_scene_roots_by_path(editor_interface: EditorInterface) -> Dictionary:
	if _exec != null:
		return _exec.call("_get_open_scene_roots_by_path", editor_interface) as Dictionary
	return {}


func _round_vec3(v: Vector3) -> Array:
	if _exec != null:
		return _exec.call("_round_vec3", v) as Array
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


func _round_vec2(v: Vector2) -> Array:
	if _exec != null:
		return _exec.call("_round_vec2", v) as Array
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


func format_compile_error_entry(code: String, rationale: String, file: String = "", line: int = 0) -> String:
	return _CompileProbeLogger.format_entry(code, rationale, file, line)


func _create_compile_probe_logger() -> _CompileProbeLogger:
	return _CompileProbeLogger.new()


func invalidate_eval_cache() -> void:
	_eval_cache.clear()
	_eval_cache_epoch += 1
	if _exec != null:
		_exec.call("_reset_healed_proj_mtime")


func _compute_live_tree_signature(root: Node) -> String:
	if root == null:
		return "none"
	var parts := PackedStringArray()
	var stack: Array[Node] = [root]
	var limit: int = 256
	while not stack.is_empty() and parts.size() < limit:
		var cur: Node = stack.pop_back()
		var scr_p := ""
		var scr: Variant = cur.get_script()
		if scr is Script:
			scr_p = String((scr as Script).resource_path)
		var grp_list := PackedStringArray()
		for g in cur.get_groups():
			var gs := String(g)
			if not gs.begins_with("_"):
				grp_list.append(gs)
		parts.append("%s:%s:%s:[%s]" % [cur.name, cur.get_class(), scr_p, ",".join(grp_list)])
		for ch in cur.get_children():
			stack.append(ch)
	return "|".join(parts)


func _build_eval_cache_key(
	feat: Dictionary,
	primary_scene: String,
	script_paths: Array,
	arena_hint: String,
	code_files_count: int,
	editor_root: Node
) -> String:
	var feat_id := String(feat.get("id", feat.get("title", "")))
	var cp_id := String(feat.get("checkpointId", ""))

	var scene_mtime: int = 0
	if not primary_scene.is_empty() and FileAccess.file_exists(primary_scene):
		scene_mtime = int(FileAccess.get_modified_time(primary_scene))
	var proj_mtime: int = 0
	if FileAccess.file_exists("res://project.godot"):
		proj_mtime = int(FileAccess.get_modified_time("res://project.godot"))

	var sp_mtimes := PackedStringArray()
	for sp_raw in script_paths:
		var sp := String(sp_raw)
		var mt: int = int(FileAccess.get_modified_time(sp)) if FileAccess.file_exists(sp) else -1
		sp_mtimes.append("%s=%d" % [sp, mt])

	var primary_open := editor_root != null and not primary_scene.is_empty() and editor_root.scene_file_path == primary_scene
	var tree_sig := _compute_live_tree_signature(editor_root) if primary_open else "closed"
	var has_built_flag := 1 if feat.has("isBuiltInGodot") else 0
	var is_built_remote := 1 if bool(feat.get("isBuiltInGodot", false)) else 0
	var is_gate_passed := 1 if bool(feat.get("isPlaytestPassed", false)) else 0
	return "%d|%s|%s|%s|%d|%d|%d|%d|%d|%d|%s|%s|%s" % [
		_eval_cache_epoch,
		feat_id,
		cp_id,
		primary_scene,
		scene_mtime,
		proj_mtime,
		code_files_count,
		has_built_flag,
		is_built_remote,
		is_gate_passed,
		arena_hint,
		";".join(sp_mtimes),
		tree_sig,
	]


func _resolve_issue_file_candidate(
	raw_token: String,
	known_by_file: Dictionary,
	scanned_by_file: Dictionary
) -> String:
	var tok := raw_token.strip_edges()
	if tok.is_empty():
		return ""
	if tok.begins_with("res://"):
		if "addons/layers/" in tok:
			return ""
		return tok
	var lower := tok.to_lower()
	if known_by_file.has(lower):
		return String(known_by_file[lower])
	if scanned_by_file.has(lower):
		return String(scanned_by_file[lower])
	for prefix in ["res://scripts/", "res://scenes/", "res://"]:
		var cand := String(prefix) + tok
		if FileAccess.file_exists(cand):
			return cand
	return ""


func extract_issue_jump_targets(
	issue_items: Array,
	known_paths: PackedStringArray = PackedStringArray()
) -> Array:
	var known_by_file := {}
	for kp_raw in known_paths:
		var kp := String(kp_raw).strip_edges()
		if kp.begins_with("res://") and not ("addons/layers/" in kp):
			known_by_file[kp.get_file().to_lower()] = kp

	var scanned_by_file := {}
	var scanned_project := false
	var ensure_scanned := func() -> void:
		if scanned_project:
			return
		scanned_project = true
		for gd_p in _scan_project_files_by_ext("res://", ".gd", 60):
			scanned_by_file[String(gd_p).get_file().to_lower()] = String(gd_p)
		for sc_p in _scan_project_files_by_ext("res://", ".tscn", 80):
			scanned_by_file[String(sc_p).get_file().to_lower()] = String(sc_p)

	var rx_res := RegEx.new()
	rx_res.compile("(res://[A-Za-z0-9_./-]+\\.(?:gd|tscn))(?::(\\d+)|\\s*\\(\\s*(\\d+)\\s*\\)|\\s*[:\\-]\\s*[Ll]ine\\s+(\\d+))?")
	var rx_bare := RegEx.new()
	rx_bare.compile("\\b([A-Za-z0-9_-]+\\.(?:gd|tscn))(?::(\\d+)|\\s*\\(\\s*(\\d+)\\s*\\)|\\s*[:\\-]\\s*[Ll]ine\\s+(\\d+))?")

	var targets_by_path := {}
	var ordered_paths := PackedStringArray()
	var record_target := func(resolved_path: String, line_num: int) -> void:
		if resolved_path.is_empty() or "addons/layers/" in resolved_path:
			return
		if not targets_by_path.has(resolved_path):
			targets_by_path[resolved_path] = []
			ordered_paths.append(resolved_path)
		var line_bucket: Array = targets_by_path[resolved_path]
		if line_num > 0:
			line_bucket.erase(0)
			if not (line_num in line_bucket):
				line_bucket.append(line_num)
		elif line_bucket.is_empty():
			line_bucket.append(0)

	for raw_item in issue_items:
		var text := String(raw_item).strip_edges()
		if text.is_empty():
			continue
		for m in rx_res.search_all(text):
			var rp := m.get_string(1).strip_edges()
			var ln_str := ""
			for gi in range(2, 5):
				var gs := m.get_string(gi).strip_edges()
				if not gs.is_empty():
					ln_str = gs
					break
			var ln_val := ln_str.to_int() if (not ln_str.is_empty() and rp.ends_with(".gd")) else 0
			record_target.call(rp, ln_val)
		for mb in rx_bare.search_all(text):
			var fname := mb.get_string(1).strip_edges()
			if fname.is_empty():
				continue
			ensure_scanned.call()
			var resolved := _resolve_issue_file_candidate(fname, known_by_file, scanned_by_file)
			if resolved.is_empty():
				continue
			var ln_b := ""
			for gi in range(2, 5):
				var gs := mb.get_string(gi).strip_edges()
				if not gs.is_empty():
					ln_b = gs
					break
			var ln_b_val := ln_b.to_int() if (not ln_b.is_empty() and resolved.ends_with(".gd")) else 0
			record_target.call(resolved, ln_b_val)

	var out: Array = []
	for p in ordered_paths:
		var bucket: Array = targets_by_path.get(p, [0])
		for ln in bucket:
			var ln_i := int(ln)
			var lbl := ("%s:%d" % [p.get_file(), ln_i]) if ln_i > 0 else p.get_file()
			out.append({
				"path": p,
				"line": ln_i,
				"label": lbl,
			})
			if out.size() >= 12:
				return out
	return out


func extract_issue_jump_target(
	issue_text: String,
	known_paths: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var targets := extract_issue_jump_targets([issue_text], known_paths)
	if targets.is_empty():
		return {}
	return targets[0]


# ---------------------------------------------------------------------------
# Internal Helpers
# ---------------------------------------------------------------------------


func ensure_project_file_logging() -> void:
	if not bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging", false)):
		ProjectSettings.set_setting("debug/file_logging/enable_file_logging", true)
		ProjectSettings.save()


func _is_ignored_godot_error_noise(text: String) -> bool:
	var lower := text.to_lower()
	return (
		"addons/layers/" in lower or
		"gdscript://" in lower or
		"progress_dialog.cpp" in lower or
		"editoricons" in lower or
		"vulkan" in lower or
		"orphan string" in lower
	)


func _is_debugger_errors_tree(err_tree: Tree, dbg_root: Node) -> bool:
	if err_tree == null or err_tree.columns != 2:
		return false
	for conn_raw in err_tree.get_signal_connection_list("item_selected"):
		var conn: Dictionary = conn_raw
		if "_error_selected" in str(conn.get("callable", "")):
			return true
	if "error" in err_tree.name.to_lower():
		return true
	var cur: Node = err_tree.get_parent()
	while cur != null and cur != dbg_root:
		if "error" in cur.name.to_lower():
			return true
		for ch in cur.get_children():
			if ch is Button and (ch as Button).text.strip_edges() == "Expand All":
				return true
		cur = cur.get_parent()
	return false


func read_recent_godot_log_errors(since_unix_sec: float = 0.0, max_errors: int = 3) -> Array:
	var log_path := String(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")).strip_edges()
	if log_path.is_empty() or not FileAccess.file_exists(log_path):
		return []
	if since_unix_sec > 0.0 and float(FileAccess.get_modified_time(log_path)) < since_unix_sec:
		return []
	var f := FileAccess.open(log_path, FileAccess.READ)
	if f == null:
		return []
	var file_len := f.get_length()
	if file_len > 16384:
		f.seek(file_len - 16384)
	var raw_text := f.get_as_text()
	f.close()

	var lines := raw_text.replace("\r\n", "\n").split("\n")
	var out: Array = []
	var seen := {}
	for i in range(lines.size() - 1, -1, -1):
		var ln := lines[i].strip_edges()
		if ln.is_empty() or _is_ignored_godot_error_noise(ln):
			continue
		var is_err := ("SCRIPT ERROR:" in ln) or ("Parse Error:" in ln) or ln.begins_with("ERROR:")
		if not is_err:
			continue
		var entry := ln
		if i + 1 < lines.size():
			var next_ln := lines[i + 1].strip_edges()
			if next_ln.begins_with("at:"):
				entry = "%s (%s)" % [ln, next_ln]
		if not seen.has(entry):
			seen[entry] = true
			out.append(entry)
			if out.size() >= max_errors:
				break
	out.reverse()
	return out


func _get_editor_error_ui_roots(base_control: Node) -> Dictionary:
	if base_control == null or not is_instance_valid(base_control):
		_cached_base_ctrl_id = 0
		_cached_debugger_roots.clear()
		_cached_editor_log_roots.clear()
		return { "debugger_roots": _cached_debugger_roots, "editor_log_roots": _cached_editor_log_roots }
	var ctrl_id: int = base_control.get_instance_id()
	var cache_valid: bool = (ctrl_id == _cached_base_ctrl_id) and not (_cached_debugger_roots.is_empty() and _cached_editor_log_roots.is_empty())
	if cache_valid:
		for dn in _cached_debugger_roots:
			if not is_instance_valid(dn):
				cache_valid = false
				break
	if cache_valid:
		for ln in _cached_editor_log_roots:
			if not is_instance_valid(ln):
				cache_valid = false
				break
	if not cache_valid:
		_cached_base_ctrl_id = ctrl_id
		_cached_debugger_roots.clear()
		_cached_editor_log_roots.clear()
		var stack: Array[Node] = [base_control]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			var cls := cur.get_class()
			var nm := String(cur.name)
			if cls == "ScriptEditorDebugger" or "ScriptEditorDebugger" in nm:
				_cached_debugger_roots.append(cur)
			elif cls == "EditorLog" or "EditorLog" in nm:
				_cached_editor_log_roots.append(cur)
			for ch in cur.get_children():
				stack.append(ch)
	return {
		"debugger_roots": _cached_debugger_roots,
		"editor_log_roots": _cached_editor_log_roots,
	}


func read_editor_and_playtest_errors(
	base_control: Node,
	extra_logger_errors: Array = [],
	ignored_signatures: Dictionary = {},
	since_unix_sec: float = 0.0,
	max_errors: int = 3,
	warning_icon: Texture2D = null
) -> Array:
	var out: Array = []
	var seen := {}

	var append_err := func(raw_msg: String) -> void:
		var msg := raw_msg.strip_edges().left(340)
		if msg.is_empty() or _is_ignored_godot_error_noise(msg) or ignored_signatures.has(msg) or seen.has(msg):
			return
		seen[msg] = true
		out.append(msg)

	# 1. Live Godot Editor Debugger -> Errors Tree (ScriptEditorDebugger)
	if base_control != null:
		var ui_roots: Dictionary = _get_editor_error_ui_roots(base_control)
		var debugger_roots: Array = ui_roots.get("debugger_roots", [])
		var editor_log_roots: Array = ui_roots.get("editor_log_roots", [])

		for dbg_raw in debugger_roots:
			var dbg: Node = dbg_raw as Node
			if dbg == null:
				continue
			var t_stack: Array[Node] = [dbg]
			while not t_stack.is_empty():
				var tn: Node = t_stack.pop_back()
				if tn is Tree and _is_debugger_errors_tree(tn as Tree, dbg):
					var err_tree: Tree = tn as Tree
					var root_item: TreeItem = err_tree.get_root()
					if root_item != null:
						var item: TreeItem = root_item.get_first_child()
						while item != null:
							var is_warn := (warning_icon != null and item.get_icon(0) == warning_icon)
							var col0 := item.get_text(0).strip_edges()
							var col1 := item.get_text(1).strip_edges()
							if col0.begins_with("W ") or "[warning]" in col0.to_lower():
								is_warn = true
							var sub_parts := PackedStringArray()
							var sub: TreeItem = item.get_first_child()
							while sub != null:
								var s0 := sub.get_text(0).strip_edges()
								var s1 := sub.get_text(1).strip_edges()
								var combined_sub := ("%s %s" % [s0, s1]).strip_edges()
								if "warning>" in combined_sub.to_lower():
									is_warn = true
								if not combined_sub.is_empty() and not ("<c++ source>" in combined_sub.to_lower()):
									sub_parts.append(combined_sub)
								sub = sub.get_next()
							if not is_warn:
								var head := ("%s %s" % [col0, col1]).strip_edges()
								if not sub_parts.is_empty():
									head = ("%s — %s" % [head, " | ".join(sub_parts)]).strip_edges()
								append_err.call(head)
							item = item.get_next()
				else:
					for ch2 in tn.get_children():
						t_stack.append(ch2)

		# 2. Live OS.add_logger ring buffer passed from layers_dock.gd
		for raw_le in extra_logger_errors:
			append_err.call(String(raw_le))

		# 3. EditorLog RichTextLabel tail (compile-time Parse Errors printed to Output)
		for elog_raw in editor_log_roots:
			var elog: Node = elog_raw as Node
			if elog == null:
				continue
			var l_stack: Array[Node] = [elog]
			while not l_stack.is_empty():
				var ln_node: Node = l_stack.pop_back()
				if ln_node is RichTextLabel:
					var parsed := (ln_node as RichTextLabel).get_parsed_text()
					if parsed.length() > 8192:
						parsed = parsed.right(8192)
					var e_lines := parsed.replace("\r\n", "\n").split("\n")
					for li in range(e_lines.size()):
						var eln := e_lines[li].strip_edges()
						if eln.is_empty() or _is_ignored_godot_error_noise(eln):
							continue
						var is_e := ("SCRIPT ERROR:" in eln) or ("Parse Error:" in eln) or eln.begins_with("ERROR:")
						if not is_e:
							continue
						var full_e := eln
						if li + 1 < e_lines.size():
							var nxt := e_lines[li + 1].strip_edges()
							if nxt.begins_with("at:"):
								full_e = "%s (%s)" % [eln, nxt]
						append_err.call(full_e)
				else:
					for ch3 in ln_node.get_children():
						l_stack.append(ch3)
	else:
		for raw_le in extra_logger_errors:
			append_err.call(String(raw_le))

	# 4. Fallback: user://logs/godot.log
	for raw_fe in read_recent_godot_log_errors(since_unix_sec, max_errors):
		append_err.call(String(raw_fe))

	if out.size() > max_errors:
		out = out.slice(out.size() - max_errors, out.size())
	return out


func check_gdscript_compiles(code: String) -> Dictionary:
	var trimmed := code.strip_edges()
	if trimmed.is_empty():
		return { "ok": false, "error": "Empty GDScript." }
	var scr := GDScript.new()
	scr.source_code = code
	var probe_logger: _CompileProbeLogger = null
	var logger_attached := false
	if ClassDB.class_exists("Logger") and OS.has_method("add_logger") and OS.has_method("remove_logger"):
		probe_logger = _CompileProbeLogger.new()
		OS.add_logger(probe_logger)
		logger_attached = true
	var err := scr.reload(true)
	if logger_attached:
		OS.remove_logger(probe_logger)
	var err_msg := ""
	if err != OK:
		if probe_logger != null and not probe_logger.messages.is_empty():
			err_msg = " | ".join(probe_logger.messages)
		else:
			err_msg = "GDScript compile check failed (code %d)." % err
	return {
		"ok": err == OK,
		"error_code": err,
		"error": err_msg,
	}


func resolve_feature_paths(feat: Dictionary, code_files: Dictionary = {}, arena_hint: String = "") -> Dictionary:
	var primary_scene := String(feat.get("primaryAsset", "")).strip_edges()
	var script_paths: Array[String] = []
	var seen_scripts := {}
	for sp in feat.get("scriptPaths", []):
		var sp_str := String(sp).strip_edges()
		if sp_str.ends_with(".gd") and not seen_scripts.has(sp_str):
			seen_scripts[sp_str] = true
			script_paths.append(sp_str)

	var steps: Array = feat.get("steps", [])
	for st in steps:
		var rp := String(st.get("stepPath", st.get("resPath", ""))).strip_edges()
		if rp.ends_with(".tscn") and primary_scene.is_empty():
			primary_scene = rp
		elif rp.ends_with(".gd") and not seen_scripts.has(rp):
			seen_scripts[rp] = true
			script_paths.append(rp)
		var snippet := resolve_step_code_text(st)
		var eff := resolve_effective_step_path(st, feat)
		if eff.ends_with(".gd") and not seen_scripts.has(eff):
			seen_scripts[eff] = true
			script_paths.append(eff)
		if snippet.length() > 0:
			var regex := RegEx.new()
			regex.compile("res://[A-Za-z0-9_./-]+\\.gd")
			for m in regex.search_all(snippet):
				var mp := m.get_string()
				if not seen_scripts.has(mp):
					seen_scripts[mp] = true
					script_paths.append(mp)

	# Include any code_files key matching script_paths stem or non-empty when primary scene name shares stem.
	var scene_stem := primary_scene.get_file().get_basename().to_lower()
	for cf_path in code_files.keys():
		var cfp := String(cf_path)
		if cfp.ends_with(".gd") and not seen_scripts.has(cfp):
			if cfp.get_file().get_basename().to_lower() == scene_stem:
				seen_scripts[cfp] = true
				script_paths.append(cfp)

	return {
		"primary_scene": primary_scene,
		"arena_scene": arena_hint if not arena_hint.is_empty() else primary_scene,
		"script_paths": script_paths,
	}


func _collect_attached_script_paths(root_node: Node) -> Dictionary:
	var attached := {}
	if root_node == null:
		return attached
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		var scr: Variant = cur.get_script()
		if scr is Script:
			var rpath := String((scr as Script).resource_path).strip_edges()
			if not rpath.is_empty():
				attached[rpath] = true
		for ch in cur.get_children():
			stack.append(ch)
	return attached


func _collect_tscn_script_paths_from_disk(scene_path: String) -> Dictionary:
	var attached := {}
	if scene_path.is_empty() or not FileAccess.file_exists(scene_path):
		return attached
	var txt := FileAccess.get_file_as_string(scene_path)
	var rx := RegEx.new()
	if rx.compile('path="(res://[^"]+\\.gd)"') != OK:
		return attached
	for m in rx.search_all(txt):
		var rp := m.get_string(1).strip_edges()
		if not rp.is_empty():
			attached[rp] = true
	return attached


func evaluate_feature(
	feat: Dictionary,
	editor_interface: EditorInterface,
	code_files: Dictionary = {},
	arena_hint: String = ""
) -> Dictionary:
	var paths := resolve_feature_paths(feat, code_files, arena_hint)
	var primary_scene := String(paths.get("primary_scene", ""))
	var arena_scene := String(paths.get("arena_scene", ""))
	var script_paths: Array = paths.get("script_paths", [])
	var editor_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
	var cache_key := _build_eval_cache_key(feat, primary_scene, script_paths, arena_hint, code_files.size(), editor_root)
	if _eval_cache.has(cache_key):
		var cached_raw: Variant = _eval_cache[cache_key]
		if typeof(cached_raw) == TYPE_DICTIONARY:
			return (cached_raw as Dictionary).duplicate(true)

	var healed_inputs := heal_empty_project_input_actions(feat)
	if healed_inputs > 0:
		cache_key = _build_eval_cache_key(feat, primary_scene, script_paths, arena_hint, code_files.size(), editor_root)

	var primary_open := editor_root != null and not primary_scene.is_empty() and editor_root.scene_file_path == primary_scene
	var attached_in_scene: Dictionary = (
		_collect_attached_script_paths(editor_root)
		if primary_open
		else _collect_tscn_script_paths_from_disk(primary_scene)
	)
	var valid_scripts := {}
	var filtered_scripts: Array[String] = []
	for spath in script_paths:
		var sp_str := String(spath)
		var exists := FileAccess.file_exists(sp_str)
		var valid := false
		if exists:
			var f := FileAccess.open(sp_str, FileAccess.READ)
			if f != null:
				var txt := f.get_as_text()
				f.close()
				valid = not txt.strip_edges().is_empty() and check_gdscript_compiles(txt).get("ok", false)
		if valid:
			valid_scripts[sp_str] = true

	var scene_stem := primary_scene.get_file().get_basename().to_lower()
	for spath in script_paths:
		var sp_str := String(spath)
		var is_valid := bool(valid_scripts.get(sp_str, false))
		var is_ghost := (
			not is_valid and
			not valid_scripts.is_empty() and
			not attached_in_scene.has(sp_str) and
			sp_str.get_file().get_basename().to_lower() != scene_stem
		)
		if is_ghost:
			continue
		filtered_scripts.append(sp_str)

	for att_sp in attached_in_scene.keys():
		var asp := String(att_sp)
		if not (asp in filtered_scripts) and FileAccess.file_exists(asp):
			filtered_scripts.append(asp)
			if valid_scripts.is_empty():
				var fa := FileAccess.open(asp, FileAccess.READ)
				if fa != null:
					var atxt := fa.get_as_text()
					fa.close()
					if not atxt.strip_edges().is_empty() and check_gdscript_compiles(atxt).get("ok", false):
						valid_scripts[asp] = true

	var arena_ok := arena_scene.is_empty() or FileAccess.file_exists(arena_scene)
	var any_script_ok := valid_scripts.size() > 0
	var has_remote_flag := feat.has("isBuiltInGodot")
	var is_built_remote := bool(feat.get("isBuiltInGodot", false))
	var is_gate_passed := bool(feat.get("isPlaytestPassed", false))
	var unbuilt_remote_checkpoint := has_remote_flag and not is_built_remote and not is_gate_passed

	var disk_artifacts_ok := (
		(not primary_scene.is_empty() and FileAccess.file_exists(primary_scene) and (filtered_scripts.is_empty() or any_script_ok)) or
		(primary_scene.is_empty() and not filtered_scripts.is_empty() and any_script_ok) or
		(primary_scene.is_empty() and filtered_scripts.is_empty() and is_built_remote and arena_ok)
	)
	var has_built_artifacts := false if unbuilt_remote_checkpoint else (is_gate_passed or disk_artifacts_ok)

	var result := {
		"all_ready": has_built_artifacts,
		"has_built_artifacts": has_built_artifacts,
		"primary_scene": primary_scene,
		"arena_scene": String(paths.get("arena_scene", "")),
		"script_paths": filtered_scripts,
	}
	if _eval_cache.size() >= 64:
		_eval_cache.clear()
	_eval_cache[cache_key] = result.duplicate(true)
	return result


func _strip_gd_comment(line: String) -> String:
	var hash_i := line.find("#")
	return line.substr(0, hash_i) if hash_i >= 0 else line


func _script_has_standalone_root_rotation(src: String) -> bool:
	for raw_line in src.split("\n"):
		var clean := _strip_gd_comment(raw_line).strip_edges()
		if clean.is_empty():
			continue
		if (
			clean.begins_with("rotation.y =") or clean.begins_with("rotation.y=") or
			clean.begins_with("rotation =") or clean.begins_with("rotation=") or
			clean.begins_with("global_rotation.y =") or clean.begins_with("rotate_y(") or
			clean.begins_with("look_at(") or clean.begins_with("self.rotation")
		):
			return true
	return false


func _detect_rotated_visual_child(src: String) -> Dictionary:
	if _script_has_standalone_root_rotation(src):
		return {}
	var onready_map := {}
	var rx_onready := RegEx.new()
	rx_onready.compile("@onready\\s+var\\s+([A-Za-z_][A-Za-z0-9_]*)[^=\\n]*=\\s*(?:\\$([A-Za-z0-9_/]+)|get_node(?:_or_null)?\\([\"']([A-Za-z0-9_/]+)[\"']\\))")
	for m in rx_onready.search_all(src):
		var vname := m.get_string(1).strip_edges()
		var npath := m.get_string(2).strip_edges()
		if npath.is_empty():
			npath = m.get_string(3).strip_edges()
		if not vname.is_empty() and not npath.is_empty():
			onready_map[vname] = npath

	var rx_var_rot := RegEx.new()
	rx_var_rot.compile("\\b([A-Za-z_][A-Za-z0-9_]*)\\.rotation(?:\\.y)?\\s*=")
	var rx_dollar_rot := RegEx.new()
	rx_dollar_rot.compile("\\$([A-Za-z0-9_/]+)\\.rotation(?:\\.y)?\\s*=")
	for raw_line in src.split("\n"):
		var clean := _strip_gd_comment(raw_line).strip_edges()
		if clean.is_empty():
			continue
		var md := rx_dollar_rot.search(clean)
		if md != null:
			var np := md.get_string(1).strip_edges()
			if "visual" in np.to_lower() or "rig" in np.to_lower() or "model" in np.to_lower() or "mesh" in np.to_lower() or "sprite" in np.to_lower():
				return { "varName": "$" + np, "nodePath": np }
		var mv := rx_var_rot.search(clean)
		if mv != null:
			var vn := mv.get_string(1).strip_edges()
			if vn == "self":
				continue
			if onready_map.has(vn):
				var np2 := String(onready_map[vn])
				var np_l := np2.to_lower()
				if "visual" in np_l or "rig" in np_l or "model" in np_l or "mesh" in np_l or "sprite" in np_l:
					return { "varName": vn, "nodePath": np2 }
	return {}


func _is_non_player_entity_script(script_path: String, src: String) -> bool:
	var fname := script_path.get_file().get_basename().to_lower()
	if "player" in fname or "camera" in fname:
		return false
	for tok in ["enemy", "spawner", "wave", "boss", "mob", "hazard", "turret", "totem", "arena", "draft", "hud"]:
		if tok in fname:
			return true
	if "add_to_group(\"enemies\")" in src or "add_to_group(\"enemy\")" in src:
		return true
	return false


func _detect_silent_take_damage(src: String) -> bool:
	var lines := src.split("\n")
	var start_idx := -1
	for i in range(lines.size()):
		var trimmed := lines[i].strip_edges()
		if trimmed.begins_with("func take_damage("):
			start_idx = i
			break
	if start_idx == -1:
		return false
	var body_parts := PackedStringArray()
	for j in range(start_idx + 1, lines.size()):
		var ln := lines[j]
		var trimmed := ln.strip_edges()
		if not trimmed.is_empty() and not ln.begins_with("\t") and not ln.begins_with(" "):
			break
		body_parts.append(_strip_gd_comment(ln).to_lower())
	var body_lower := "\n".join(body_parts)
	if body_lower.strip_edges().is_empty():
		return true
	for sig_tok in [
		"material", "modulate", "albedo", "emission", "tween", "flash",
		"hit_flash", "particle", "velocity", "knockback", "health_changed",
		"damaged", "emit", "print(", "audio", "sfx", "shake"
	]:
		if sig_tok in body_lower:
			return false
	return true


func diagnose_project_combat_and_wiring(
	scene_paths: Array = [],
	live_scripts: Dictionary = {},
	editor_interface: EditorInterface = null
) -> PackedStringArray:
	var findings := PackedStringArray()
	var seen_findings := {}
	var append_finding := func(msg: String) -> void:
		var clean := msg.strip_edges()
		if not clean.is_empty() and not seen_findings.has(clean):
			seen_findings[clean] = true
			findings.append(clean)

	var scenes_to_check := PackedStringArray()
	if scene_paths.is_empty():
		scenes_to_check = collect_project_scene_paths("res://", 16)
	else:
		for raw_sp in scene_paths:
			var sp := String(raw_sp).strip_edges()
			if not sp.is_empty() and sp.ends_with(".tscn") and not (sp in scenes_to_check):
				scenes_to_check.append(sp)

	var scripts_map: Dictionary = live_scripts.duplicate() if not live_scripts.is_empty() else read_all_live_project_scripts("res://", editor_interface)

	# 1. InputMap key collision audit & non-player Input.* polling check
	var input_map := capture_input_map_snapshot()
	var key_to_actions := {}
	for act_key in input_map.keys():
		var act := String(act_key)
		var labels: Variant = input_map[act]
		if typeof(labels) != TYPE_ARRAY:
			continue
		for lbl_raw in (labels as Array):
			var lbl := String(lbl_raw).strip_edges()
			if lbl.is_empty():
				continue
			if not key_to_actions.has(lbl):
				key_to_actions[lbl] = []
			var bucket: Array = key_to_actions[lbl]
			if not (act in bucket):
				bucket.append(act)

	for lbl_key in key_to_actions.keys():
		var acts: Array = key_to_actions[lbl_key]
		if acts.size() < 2:
			continue
		for a_idx in range(acts.size()):
			var a_name := String(acts[a_idx])
			if not _is_bogus_non_player_action_name(a_name) and not a_name.ends_with("_action"):
				continue
			var others := PackedStringArray()
			for b_idx in range(acts.size()):
				if b_idx != a_idx:
					others.append(String(acts[b_idx]))
			if not others.is_empty():
				append_finding.call(
					"[INPUT COLLISION] Input action '%s' shares [%s] with %s in project.godot — pressing %s triggers both simultaneously." % [
						a_name, String(lbl_key), ", ".join(others), String(lbl_key)
					]
				)

	var rx_inp := RegEx.new()
	rx_inp.compile("(?:Input\\.(?:is_action_pressed|is_action_just_pressed|is_action_just_released|get_action_strength)|event\\.is_action(?:_pressed|_released)?)\\s*\\(\\s*[\"']([A-Za-z0-9_.:/-]+)[\"']")
	var rx_atan2_pos := RegEx.new()
	rx_atan2_pos.compile("atan2\\s*\\(\\s*[A-Za-z_][A-Za-z0-9_.]*\\.x\\s*,\\s*[A-Za-z_][A-Za-z0-9_.]*\\.z\\s*\\)")
	var rx_neg_basis_z := RegEx.new()
	rx_neg_basis_z.compile("-\\s*(?:global_transform|transform|visual_rig\\.global_transform)\\.basis\\.z\\b")
	var rx_look_at := RegEx.new()
	rx_look_at.compile("\\blook_at\\s*\\(")
	var rx_pos_basis_motion := RegEx.new()
	rx_pos_basis_motion.compile("(?:velocity|impulse|dir|forward|move)\\s*[+*]?=\\s*(?:global_transform|transform)\\.basis\\.z\\b")
	var rx_monitoring_on := RegEx.new()
	rx_monitoring_on.compile("\\.monitoring\\s*=\\s*true|set_deferred\\s*\\(\\s*[\"']monitoring[\"']\\s*,\\s*true\\s*\\)")
	var rx_range_export := RegEx.new()
	rx_range_export.compile("@export\\s+var\\s+(strike_?[Rr]ange|attack_?[Rr]ange|melee_?[Rr]ange|hit_?[Rr]ange)\\s*(?::\\s*float)?\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)")

	for sp_key in scripts_map.keys():
		var sp := String(sp_key)
		var src := String(scripts_map[sp])
		var active_lines := PackedStringArray()
		for raw_l in src.split("\n"):
			var cl := _strip_gd_comment(raw_l)
			if not cl.strip_edges().is_empty():
				active_lines.append(cl)
		var active_src := "\n".join(active_lines)

		if _is_non_player_entity_script(sp, active_src):
			for mi in rx_inp.search_all(active_src):
				var polled_act := mi.get_string(1).strip_edges()
				if not polled_act.is_empty() and not polled_act.begins_with("ui_"):
					append_finding.call(
						"[NON-PLAYER INPUT] %s polls Input action '%s' on a non-player script — player input will hijack enemy/spawner state." % [
							sp.get_file(), polled_act
						]
					)

		var uses_atan2_pos := rx_atan2_pos.search(active_src) != null
		var uses_neg_basis := rx_neg_basis_z.search(active_src) != null
		var uses_look_at := rx_look_at.search(active_src) != null
		var uses_pos_basis := rx_pos_basis_motion.search(active_src) != null
		if uses_atan2_pos and uses_neg_basis and not uses_look_at:
			append_finding.call(
				"[3D BASIS FLIP] %s orients yaw with atan2(x, z) (+Z forward) but applies velocity/impulse along -basis.z (moves 180 deg backwards away from target)." % sp.get_file()
			)
		elif uses_look_at and not uses_atan2_pos and uses_pos_basis and not uses_neg_basis:
			append_finding.call(
				"[3D BASIS FLIP] %s orients with look_at() (-Z forward) but moves along +basis.z (moves backwards away from target)." % sp.get_file()
			)

		if rx_monitoring_on.search(active_src) != null and ("body_entered" in active_src):
			if not ("get_overlapping_bodies" in active_src) and not ("get_overlapping_areas" in active_src):
				append_finding.call(
					"[HITBOX OVERLAP] %s enables hitbox monitoring=true dynamically without checking get_overlapping_bodies() — targets already overlapping at attack start can be missed." % sp.get_file()
				)

		if _detect_silent_take_damage(src):
			append_finding.call(
				"[SILENT HIT FEEDBACK] %s take_damage() changes HP with zero visible hit flash, knockback, or signal feedback." % sp.get_file()
			)

	# 2. Instanced Scene Transform, Pivot, Reach & Collision Layer/Mask Audit
	var scene_roots: Array[Dictionary] = []
	var temp_roots: Array[Node] = []
	var open_roots := _get_open_scene_roots_by_path(editor_interface)
	var all_char_layers: int = 0

	for sc_path in scenes_to_check:
		var sroot: Node = null
		if open_roots.has(sc_path):
			sroot = open_roots[sc_path] as Node
		elif ResourceLoader.exists(sc_path):
			var ps := ResourceLoader.load(sc_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			if ps != null:
				sroot = ps.instantiate()
				if sroot != null:
					temp_roots.append(sroot)
		if sroot == null:
			continue
		scene_roots.append({ "path": sc_path, "root": sroot })
		if sroot is CharacterBody3D or sroot is CharacterBody2D:
			all_char_layers |= int(sroot.get("collision_layer"))

	var rx_combat_area := RegEx.new()
	rx_combat_area.compile("(?i)(hitbox|strike|attack|claw|slash|bite|melee|weapon|muzzle)")
	var rx_onready_node := RegEx.new()
	rx_onready_node.compile("(?m)^[ \\t]*@onready\\s+var\\s+\\w+[^=\\n]*=\\s*\\$([A-Za-z0-9_/]+)")

	for item in scene_roots:
		var sc_path := String(item["path"])
		var sroot: Node = item["root"] as Node
		var root_scr_path := ""
		var root_src := ""
		var scr: Variant = sroot.get_script()
		if scr is Script:
			root_scr_path = String((scr as Script).resource_path).strip_edges()
			if not root_scr_path.is_empty() and scripts_map.has(root_scr_path):
				root_src = String(scripts_map[root_scr_path])
			elif not root_scr_path.is_empty() and FileAccess.file_exists(root_scr_path):
				var fa := FileAccess.open(root_scr_path, FileAccess.READ)
				if fa != null:
					root_src = fa.get_as_text()
					fa.close()
			else:
				root_src = String((scr as Script).source_code)

		var root_active_lines := PackedStringArray()
		for rl in root_src.split("\n"):
			var cl2 := _strip_gd_comment(rl)
			if not cl2.strip_edges().is_empty():
				root_active_lines.append(cl2)
		var root_active_src := "\n".join(root_active_lines)

		var rig_info := _detect_rotated_visual_child(root_src) if not root_src.is_empty() else {}
		var rig_var := String(rig_info.get("varName", ""))
		var rig_node_path := String(rig_info.get("nodePath", ""))
		var rig_leaf := rig_node_path.get_file()
		var range_match := rx_range_export.search(root_src)
		var attack_range_name := range_match.get_string(1) if range_match != null else ""
		var attack_range_val := range_match.get_string(2).to_float() if range_match != null else 0.0
		var root_atan2_pos := rx_atan2_pos.search(root_active_src) != null and rx_look_at.search(root_active_src) == null

		var stack: Array[Node] = [sroot]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			for ch in cur.get_children():
				stack.append(ch)
			var rel_cur := "." if cur == sroot else String(sroot.get_path_to(cur))
			if cur is CollisionShape3D or cur is CollisionShape2D:
				if cur.get("shape") == null:
					append_finding.call("[EMPTY COLLISION SHAPE] %s :: CollisionShape '%s' has no shape assigned." % [sc_path.get_file(), rel_cur])
			var cur_scr_v: Variant = cur.get_script()
			if cur_scr_v is Script:
				var cur_scr := cur_scr_v as Script
				var cur_scr_p := String(cur_scr.resource_path).strip_edges()
				var cur_scr_txt := ""
				if not cur_scr_p.is_empty() and scripts_map.has(cur_scr_p):
					cur_scr_txt = String(scripts_map[cur_scr_p])
				elif not cur_scr_p.is_empty() and FileAccess.file_exists(cur_scr_p):
					var f_on := FileAccess.open(cur_scr_p, FileAccess.READ)
					if f_on != null:
						cur_scr_txt = f_on.get_as_text()
						f_on.close()
				if cur_scr_txt.is_empty():
					cur_scr_txt = String(cur_scr.source_code)
				if not cur_scr_txt.is_empty():
					for m_on in rx_onready_node.search_all(cur_scr_txt):
						var node_ref := m_on.get_string(1).strip_edges()
						if not node_ref.is_empty() and cur.get_node_or_null(node_ref) == null:
							var scr_lbl := cur_scr_p.get_file() if not cur_scr_p.is_empty() else String(cur.name)
							append_finding.call("[MISSING @ONREADY NODE] %s :: %s references missing child $%s on '%s'." % [sc_path.get_file(), scr_lbl, node_ref, rel_cur])
			if not (cur is Area3D or cur is Area2D):
				continue
			var rel_area_path := String(sroot.get_path_to(cur))
			if rx_combat_area.search(rel_area_path) == null:
				continue

			# Find child CollisionShape
			var cs_node: Node = null
			for ach in cur.get_children():
				if ach is CollisionShape3D or ach is CollisionShape2D:
					cs_node = ach
					break

			if cur is Area3D:
				var area_rel_pos := Vector3.ZERO
				var walk: Node = cur
				while walk != null and walk != sroot:
					if walk is Node3D:
						area_rel_pos += (walk as Node3D).position
					walk = walk.get_parent()
				var child_pos := (cs_node as Node3D).position if cs_node is Node3D else Vector3.ZERO
				var shape_total_pos := area_rel_pos + child_pos
				var area_horiz := Vector2(area_rel_pos.x, area_rel_pos.z).length()
				var child_horiz := Vector2(child_pos.x, child_pos.z).length()
				var total_horiz := Vector2(shape_total_pos.x, shape_total_pos.z).length()

				if area_horiz >= 0.45 and child_horiz >= 0.45 and total_horiz < 0.35:
					append_finding.call(
						"[HITBOX OFFSET CANCELLED] %s: '%s' position %s + child '%s' position %s cancel horizontally to %.2fm (centered on owner body instead of forward)." % [
							sc_path.get_file(), rel_area_path, str(_round_vec3(area_rel_pos)), cs_node.name, str(_round_vec3(child_pos)), total_horiz
						]
					)
				elif root_atan2_pos and shape_total_pos.z < -0.25 and total_horiz >= 0.35:
					append_finding.call(
						"[HITBOX FACING SIGN] %s rotates +Z forward (atan2), but hitbox '%s' is offset behind at z=%.2fm." % [
							sc_path.get_file(), rel_area_path, shape_total_pos.z
						]
					)

				if not rig_node_path.is_empty():
					var under_rig := (
						rel_area_path == rig_node_path or
						rel_area_path.begins_with(rig_node_path + "/") or
						(not rig_leaf.is_empty() and ((rig_leaf + "/") in rel_area_path))
					)
					var syncs_rig_rot := false
					if not rig_var.is_empty():
						var rig_tok: String = rig_var.substr(1) if rig_var.begins_with("$") else rig_var
						var rx_pivot_sync := RegEx.new()
						rx_pivot_sync.compile("(?:pivot|hitbox|attack|strike|muzzle)[A-Za-z0-9_]*\\.rotation(?:\\.y)?\\s*=[^\\n]*\\b" + rig_tok + "\\b")
						syncs_rig_rot = rx_pivot_sync.search(root_active_src) != null
					if not under_rig and not syncs_rig_rot:
						var label_scr := root_scr_path.get_file() if not root_scr_path.is_empty() else sc_path.get_file()
						append_finding.call(
							"[UNROTATED HITBOX PIVOT] %s rotates '%s' instead of root, but '%s' is a sibling outside '%s' and never inherits facing rotation." % [
								label_scr, rig_node_path, rel_area_path, rig_node_path
							]
						)

				if attack_range_val > 0.0 and cs_node is CollisionShape3D and (cs_node as CollisionShape3D).shape != null:
					var sh3: Shape3D = (cs_node as CollisionShape3D).shape
					var half_ext: float = 0.5
					if sh3 is BoxShape3D:
						var bsz: Vector3 = (sh3 as BoxShape3D).size
						half_ext = 0.5 * maxf(bsz.x, bsz.z)
					elif sh3 is SphereShape3D:
						half_ext = (sh3 as SphereShape3D).radius
					elif sh3 is CapsuleShape3D:
						half_ext = (sh3 as CapsuleShape3D).radius
					elif sh3 is CylinderShape3D:
						half_ext = (sh3 as CylinderShape3D).radius
					var front_reach: float = total_horiz + half_ext
					var has_bad_back_lunge := rx_neg_basis_z.search(root_active_src) != null
					var has_forward_lunge := ("lunge" in root_active_src.to_lower() or "dash" in root_active_src.to_lower()) and not has_bad_back_lunge
					if attack_range_val > front_reach + 0.55 and not has_forward_lunge:
						append_finding.call(
							"[HITBOX REACH GAP] %s attacks at %s=%.2fm, while '%s' only reaches %.2fm from root." % [
								sc_path.get_file(), attack_range_name, attack_range_val, rel_area_path, front_reach
							]
						)

			elif cur is Area2D and cs_node is CollisionShape2D:
				var area_rel_2d := Vector2.ZERO
				var walk2: Node = cur
				while walk2 != null and walk2 != sroot:
					if walk2 is Node2D:
						area_rel_2d += (walk2 as Node2D).position
					walk2 = walk2.get_parent()
				var child_pos_2d := (cs_node as Node2D).position
				var total_2d := area_rel_2d + child_pos_2d
				if area_rel_2d.length() >= 12.0 and child_pos_2d.length() >= 12.0 and total_2d.length() < 8.0:
					append_finding.call(
						"[HITBOX OFFSET CANCELLED] %s: '%s' %s + '%s' %s cancel out to %.1fpx." % [
							sc_path.get_file(), rel_area_path, str(_round_vec2(area_rel_2d)), cs_node.name, str(_round_vec2(child_pos_2d)), total_2d.length()
						]
					)

			if all_char_layers != 0:
				var amask: int = int(cur.get("collision_mask"))
				if (amask & all_char_layers) == 0:
					append_finding.call(
						"[COLLISION MASK MISMATCH] %s '%s' collision_mask=%d misses CharacterBody collision_layer bits (%d)." % [
							sc_path.get_file(), rel_area_path, amask, all_char_layers
						]
					)

	for tr in temp_roots:
		if is_instance_valid(tr):
			tr.free()
	return findings


func verify_built_feature_integrity(
	editor_interface: EditorInterface,
	feat: Dictionary,
	code_files: Dictionary = {},
	arena_hint: String = ""
) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var paths := resolve_feature_paths(feat, code_files, arena_hint)
	var primary_scene := String(paths.get("primary_scene", "")).strip_edges()
	var checked_scripts := {}
	var live_scripts := read_all_live_project_scripts("res://", editor_interface)

	for sp_raw in paths.get("script_paths", []):
		var sp := String(sp_raw).strip_edges()
		if sp.is_empty() or checked_scripts.has(sp):
			continue
		var txt := String(live_scripts.get(sp, ""))
		if txt.is_empty() and FileAccess.file_exists(sp):
			txt = FileAccess.get_file_as_string(sp)
		if txt.strip_edges().is_empty():
			continue
		checked_scripts[sp] = true
		var chk := check_gdscript_compiles(txt)
		if not bool(chk.get("ok", false)):
			errors.append("%s: %s" % [sp.get_file(), String(chk.get("error", "compile failed"))])

	var rx_gd_ref := RegEx.new()
	rx_gd_ref.compile("res://[^\"'\\s]+\\.gd")
	for sc_ref in [primary_scene, arena_hint]:
		var clean_sc := String(sc_ref).strip_edges()
		if clean_sc.is_empty() or not FileAccess.file_exists(clean_sc):
			continue
		var tscn_txt := FileAccess.get_file_as_string(clean_sc)
		for gm in rx_gd_ref.search_all(tscn_txt):
			var sp2 := gm.get_string(0).strip_edges()
			if sp2.is_empty() or checked_scripts.has(sp2) or sp2.begins_with("res://addons/"):
				continue
			var src2 := String(live_scripts.get(sp2, ""))
			if src2.is_empty() and FileAccess.file_exists(sp2):
				src2 = FileAccess.get_file_as_string(sp2)
			if not src2.strip_edges().is_empty():
				checked_scripts[sp2] = true
				var chk2 := check_gdscript_compiles(src2)
				if not bool(chk2.get("ok", false)):
					errors.append("%s: %s" % [sp2.get_file(), String(chk2.get("error", "compile failed"))])

	var open_roots := _get_open_scene_roots_by_path(editor_interface)
	var ed_open_root: Node = open_roots.get(primary_scene, null) as Node if not primary_scene.is_empty() else null
	if ed_open_root != null:
		var root_scr_v: Variant = ed_open_root.get_script()
		if root_scr_v is Script:
			var sp3 := String((root_scr_v as Script).resource_path).strip_edges()
			if not sp3.is_empty() and not checked_scripts.has(sp3):
				var src3 := String(live_scripts.get(sp3, (root_scr_v as Script).source_code))
				if not src3.strip_edges().is_empty():
					checked_scripts[sp3] = true
					var chk3 := check_gdscript_compiles(src3)
					if not bool(chk3.get("ok", false)):
						errors.append("%s: %s" % [sp3.get_file(), String(chk3.get("error", "compile failed"))])

	var diag_scenes: Array = []
	for sc_cand in [primary_scene, arena_hint]:
		var cs := String(sc_cand).strip_edges()
		if not cs.is_empty() and cs.ends_with(".tscn") and not (cs in diag_scenes):
			diag_scenes.append(cs)
	for proj_sc in collect_project_scene_paths("res://", 120):
		if not (proj_sc in diag_scenes):
			diag_scenes.append(proj_sc)
	var feat_diags := diagnose_project_combat_and_wiring(
		diag_scenes,
		live_scripts,
		editor_interface
	)
	var p_file := primary_scene.get_file()
	var is_relevant_fn := func(msg: String) -> bool:
		if not p_file.is_empty() and (p_file in msg):
			return true
		for ck in checked_scripts.keys():
			if String(ck).get_file() in msg:
				return true
		return false
	for diag_msg in feat_diags:
		var critical := (
			diag_msg.begins_with("[3D BASIS FLIP]") or
			diag_msg.begins_with("[HITBOX OFFSET CANCELLED]") or
			diag_msg.begins_with("[UNROTATED HITBOX PIVOT]") or
			diag_msg.begins_with("[NON-PLAYER INPUT]") or
			diag_msg.begins_with("[COLLISION MASK MISMATCH]") or
			diag_msg.begins_with("[INPUT COLLISION]") or
			diag_msg.begins_with("[MISSING @ONREADY NODE]") or
			diag_msg.begins_with("[EMPTY COLLISION SHAPE]")
		)
		if critical and (is_relevant_fn.call(diag_msg) or diag_msg.begins_with("[INPUT COLLISION]")):
			if not (diag_msg in errors):
				errors.append(diag_msg)
		elif not (diag_msg in warnings):
			warnings.append(diag_msg)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"project_diagnostics": feat_diags,
	}
