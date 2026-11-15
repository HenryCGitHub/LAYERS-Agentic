@tool
extends RefCounted

# Read-Only Editor Inspection, Error Reader, Jump-to-Line & Context Exporter
# for LAYERS Godot 4 Plugin (v3.0.0).

var _eval_cache: Dictionary = {}
var _eval_cache_epoch: int = 0
var _cached_base_ctrl_id: int = 0
var _cached_debugger_roots: Array[Node] = []
var _cached_editor_log_roots: Array[Node] = []


func invalidate_eval_cache() -> void:
	_eval_cache.clear()
	_eval_cache_epoch += 1


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
	var is_gate_passed := 1 if bool(feat.get("isPlaytestPassed", false)) else 0
	return "%d|%s|%s|%s|%d|%d|%d|%s|%s|%s" % [
		_eval_cache_epoch,
		feat_id,
		cp_id,
		primary_scene,
		scene_mtime,
		proj_mtime,
		is_gate_passed,
		arena_hint,
		";".join(sp_mtimes),
		tree_sig,
	]


# ---------------------------------------------------------------------------
# Open Scene / Script & Jump-to-Line
# ---------------------------------------------------------------------------

func open_res_path(editor_interface: EditorInterface, res_path: String, line_number: int = -1) -> String:
	if editor_interface == null:
		return "EditorInterface unavailable."
	var clean_path := res_path.strip_edges()
	if clean_path.ends_with(".tscn") or clean_path.ends_with(".scn"):
		if FileAccess.file_exists(clean_path):
			editor_interface.open_scene_from_path(clean_path)
			return ""
		return "%s does not exist yet — create it in Godot first." % clean_path
	if not FileAccess.file_exists(clean_path):
		return "%s does not exist yet — create it in Godot first." % clean_path
	var res: Resource = null
	if clean_path.ends_with(".gd"):
		var open_buffers := collect_open_script_editor_buffers(editor_interface)
		var cache_mode: ResourceLoader.CacheMode = (
			ResourceLoader.CACHE_MODE_REUSE if open_buffers.has(clean_path) else ResourceLoader.CACHE_MODE_REPLACE
		)
		res = ResourceLoader.load(clean_path, "Script", cache_mode)
	else:
		res = ResourceLoader.load(clean_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if res is Script:
		if line_number > 0:
			editor_interface.edit_script(res as Script, line_number, 0)
		else:
			editor_interface.edit_script(res as Script)
		if editor_interface.has_method("set_main_screen_editor"):
			editor_interface.set_main_screen_editor("Script")
	elif res != null:
		editor_interface.edit_resource(res)
	return ""


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
		var cand: String = String(prefix) + tok
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
	return targets[0] as Dictionary


# ---------------------------------------------------------------------------
# Live Console & Playtest Error Reader
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

		for raw_le in extra_logger_errors:
			append_err.call(String(raw_le))

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

	for raw_fe in read_recent_godot_log_errors(since_unix_sec, max_errors):
		append_err.call(String(raw_fe))

	if out.size() > max_errors:
		out = out.slice(out.size() - max_errors, out.size())
	return out


# ---------------------------------------------------------------------------
# Read-Only Feature Scene / Script Discovery
# ---------------------------------------------------------------------------

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
			if not rpath.is_empty() and not ("addons/layers/" in rpath):
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
		if not rp.is_empty() and not ("addons/layers/" in rp):
			attached[rp] = true
	return attached


func _scan_project_files_by_ext(root_dir: String, ext: String, cap: int = 80) -> PackedStringArray:
	var results := PackedStringArray()
	var start_dir := root_dir.strip_edges()
	if start_dir.is_empty():
		start_dir = "res://"
	elif start_dir != "res://" and start_dir != "user://":
		start_dir = start_dir.trim_suffix("/")
	var stack: Array[String] = [start_dir]
	while not stack.is_empty() and results.size() < cap:
		var dir_path: String = stack.pop_back()
		var da := DirAccess.open(dir_path)
		if da == null:
			continue
		da.list_dir_begin()
		var entry := da.get_next()
		while not entry.is_empty():
			if entry.begins_with(".") or entry == "addons":
				entry = da.get_next()
				continue
			var full := "%s/%s" % [dir_path, entry] if dir_path != "res://" else ("res://%s" % entry)
			if da.current_is_dir():
				stack.append(full)
			elif entry.to_lower().ends_with(ext):
				results.append(full)
				if results.size() >= cap:
					break
			entry = da.get_next()
		da.list_dir_end()
	results.sort()
	return results


func collect_project_scene_paths(root_dir: String = "res://", max_scenes: int = 120) -> PackedStringArray:
	return _scan_project_files_by_ext(root_dir, ".tscn", max_scenes)


func _derive_feature_stem(raw_title: String) -> String:
	var lower := raw_title.strip_edges().to_lower()
	var cleaned := ""
	var prev_sep := true
	for i in range(lower.length()):
		var ch := lower[i]
		var is_alnum := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		if is_alnum:
			cleaned += ch
			prev_sep = false
		elif not prev_sep:
			cleaned += "_"
			prev_sep = true
	return cleaned.trim_suffix("_")


func _normalize_match_token(word: String) -> String:
	var w := word.strip_edges().to_lower()
	if w.length() >= 4:
		if w.ends_with("ies"):
			w = w.substr(0, w.length() - 3) + "y"
		elif w.ends_with("s") and not w.ends_with("ss"):
			w = w.substr(0, w.length() - 1)
	return w


func _extract_feature_match_tokens(feat: Dictionary) -> PackedStringArray:
	var raw := String(feat.get("title", "")).strip_edges().to_lower()
	var stopwords := {
		"and": true,
		"the": true,
		"for": true,
		"with": true,
		"from": true,
		"into": true,
		"over": true,
		"under": true,
		"system": true,
		"systems": true,
		"feature": true,
		"features": true,
		"mechanic": true,
		"setup": true,
		"core": true,
		"basic": true,
		"game": true,
		"mode": true,
		"loop": true,
	}
	var cleaned := ""
	for i in range(raw.length()):
		var ch := raw[i]
		var is_alnum := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		cleaned += ch if is_alnum else " "
	var out := PackedStringArray()
	var seen := {}
	for part in cleaned.split(" ", false):
		var tok := _normalize_match_token(part)
		if tok.length() < 3 or stopwords.has(tok) or seen.has(tok):
			continue
		seen[tok] = true
		out.append(tok)
	return out


func _score_stem_match(file_stem: String, full_stem: String, tokens: PackedStringArray) -> int:
	var normalized_file_stem := file_stem.strip_edges().to_lower()
	if normalized_file_stem.is_empty():
		return 0
	if not full_stem.is_empty() and normalized_file_stem == full_stem:
		return 100
	var file_words := PackedStringArray()
	for chunk in normalized_file_stem.replace("-", "_").split("_", false):
		var nw := _normalize_match_token(chunk)
		if nw.length() >= 3:
			file_words.append(nw)
	var score := 0
	for tok in tokens:
		var exact_hit := false
		var prefix_hit := false
		for fw in file_words:
			if fw == tok:
				exact_hit = true
				break
			if tok.length() >= 4 and fw.length() >= 4 and (fw.begins_with(tok) or tok.begins_with(fw)):
				prefix_hit = true
		if exact_hit:
			score += 25
		elif prefix_hit:
			score += 12
	return score


func resolve_feature_paths(feat: Dictionary, arena_hint: String = "") -> Dictionary:
	var primary_scene := String(feat.get("primaryAsset", "")).strip_edges()
	if (not primary_scene.ends_with(".tscn") and not primary_scene.ends_with(".scn")) or not FileAccess.file_exists(primary_scene):
		primary_scene = ""
	var script_paths: Array[String] = []
	var seen_scripts := {}
	var add_script := func(candidate: String) -> void:
		var sp_str := candidate.strip_edges()
		if sp_str.begins_with("res://") and sp_str.ends_with(".gd") and not ("addons/layers/" in sp_str) and FileAccess.file_exists(sp_str) and not seen_scripts.has(sp_str):
			seen_scripts[sp_str] = true
			script_paths.append(sp_str)

	for sp in feat.get("scriptPaths", []):
		add_script.call(String(sp))

	var stem := _derive_feature_stem(String(feat.get("title", "")))
	var tokens := _extract_feature_match_tokens(feat)
	if primary_scene.is_empty() and (not stem.is_empty() or not tokens.is_empty()):
		var best_scene := ""
		var best_scene_score := 0
		for sc_raw in _scan_project_files_by_ext("res://", ".tscn", 80):
			var sc_path := String(sc_raw)
			var sc_stem := sc_path.get_file().get_basename().to_lower()
			var sc_score := _score_stem_match(sc_stem, stem, tokens)
			if sc_score > best_scene_score:
				best_scene_score = sc_score
				best_scene = sc_path
		if best_scene_score > 0:
			primary_scene = best_scene

	if not primary_scene.is_empty() and FileAccess.file_exists(primary_scene):
		var disk_scripts := _collect_tscn_script_paths_from_disk(primary_scene)
		for ds_raw in disk_scripts.keys():
			add_script.call(String(ds_raw))

	var scene_stem := primary_scene.get_file().get_basename().to_lower() if not primary_scene.is_empty() else ""
	if not stem.is_empty() or not scene_stem.is_empty() or not tokens.is_empty():
		var scored_scripts: Array[Dictionary] = []
		for gd_raw in _scan_project_files_by_ext("res://", ".gd", 80):
			var gd_path := String(gd_raw)
			if seen_scripts.has(gd_path):
				continue
			var gd_stem := gd_path.get_file().get_basename().to_lower()
			var sc := 0
			if not scene_stem.is_empty() and gd_stem == scene_stem:
				sc = 100
			else:
				sc = _score_stem_match(gd_stem, stem, tokens)
			if sc > 0:
				scored_scripts.append({"path": gd_path, "score": sc})
		scored_scripts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var sa := int(a.get("score", 0))
			var sb := int(b.get("score", 0))
			if sa != sb:
				return sa > sb
			return String(a.get("path", "")) < String(b.get("path", ""))
		)
		var match_cap := mini(scored_scripts.size(), 6)
		for i in range(match_cap):
			add_script.call(String(scored_scripts[i].get("path", "")))

	var resolved_arena := arena_hint.strip_edges()
	if resolved_arena.is_empty() or not FileAccess.file_exists(resolved_arena):
		resolved_arena = primary_scene

	return {
		"primary_scene": primary_scene,
		"arena_scene": resolved_arena,
		"script_paths": script_paths,
	}


func evaluate_feature(
	feat: Dictionary,
	editor_interface: EditorInterface,
	arena_hint: String = ""
) -> Dictionary:
	var paths := resolve_feature_paths(feat, arena_hint)
	var primary_scene := String(paths.get("primary_scene", ""))
	var arena_scene := String(paths.get("arena_scene", ""))
	var script_paths: Array = paths.get("script_paths", [])
	var editor_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
	var cache_key := _build_eval_cache_key(feat, primary_scene, script_paths, arena_hint, editor_root)
	if _eval_cache.has(cache_key):
		var cached_raw: Variant = _eval_cache[cache_key]
		if typeof(cached_raw) == TYPE_DICTIONARY:
			return (cached_raw as Dictionary).duplicate(true)

	var primary_open := editor_root != null and not primary_scene.is_empty() and editor_root.scene_file_path == primary_scene
	if primary_open:
		var attached_open := _collect_attached_script_paths(editor_root)
		for att_raw in attached_open.keys():
			var att := String(att_raw).strip_edges()
			if att.begins_with("res://") and att.ends_with(".gd") and not (att in script_paths):
				script_paths.append(att)

	var existing_scripts: Array[String] = []
	for sp_raw in script_paths:
		var sp_str := String(sp_raw).strip_edges()
		if sp_str.begins_with("res://") and sp_str.ends_with(".gd") and FileAccess.file_exists(sp_str):
			if not (sp_str in existing_scripts):
				existing_scripts.append(sp_str)

	var result := {
		"primary_scene": primary_scene if (not primary_scene.is_empty() and FileAccess.file_exists(primary_scene)) else "",
		"arena_scene": arena_scene,
		"script_paths": existing_scripts,
	}
	if _eval_cache.size() >= 64:
		_eval_cache.clear()
	_eval_cache[cache_key] = result.duplicate(true)
	return result


# ---------------------------------------------------------------------------
# Read-Only Script Buffers, Scene Tree Snapshot & Copy Context Exporter
# ---------------------------------------------------------------------------

func merge_script_buffer_overrides(disk_scripts: Dictionary, buffer_overrides: Dictionary) -> Dictionary:
	var out: Dictionary = disk_scripts.duplicate()
	for raw_p in buffer_overrides.keys():
		var sp := String(raw_p).strip_edges()
		if not sp.begins_with("res://") or not sp.ends_with(".gd"):
			continue
		if sp.begins_with("res://addons/") or ("/addons/" in sp):
			continue
		var txt := String(buffer_overrides[raw_p])
		if not txt.strip_edges().is_empty():
			out[sp] = txt.left(65536)
	return out


func collect_open_script_editor_buffers(editor_interface: EditorInterface) -> Dictionary:
	var out := {}
	if editor_interface == null or not editor_interface.has_method("get_script_editor"):
		return out
	var script_ed: Variant = editor_interface.get_script_editor()
	if script_ed == null:
		return out
	if not script_ed.has_method("get_open_scripts") or not script_ed.has_method("get_open_script_editors"):
		return out
	var open_scripts: Array = script_ed.get_open_scripts()
	var open_editors: Array = script_ed.get_open_script_editors()
	var count: int = mini(open_scripts.size(), open_editors.size())
	for i in range(count):
		var scr_v: Variant = open_scripts[i]
		var ed_v: Variant = open_editors[i]
		if not (scr_v is Script) or ed_v == null:
			continue
		var rpath := String((scr_v as Script).resource_path).strip_edges()
		if not rpath.begins_with("res://") or not rpath.ends_with(".gd"):
			continue
		if rpath.begins_with("res://addons/") or ("/addons/" in rpath):
			continue
		if not ed_v.has_method("get_base_editor"):
			continue
		var base_ed: Variant = ed_v.get_base_editor()
		if base_ed != null and base_ed.has_method("get_text"):
			var txt := String(base_ed.call("get_text"))
			if not txt.strip_edges().is_empty():
				out[rpath] = txt.left(65536)
	return out


func read_live_script_text(res_path: String, editor_interface: EditorInterface = null) -> String:
	var clean_path := res_path.strip_edges()
	if not clean_path.begins_with("res://") or not clean_path.ends_with(".gd"):
		return ""
	var open_buffers := collect_open_script_editor_buffers(editor_interface)
	if open_buffers.has(clean_path):
		return String(open_buffers[clean_path])
	if FileAccess.file_exists(clean_path):
		var txt := FileAccess.get_file_as_string(clean_path)
		if not txt.strip_edges().is_empty():
			return txt.left(65536)
	return ""


func read_all_live_project_scripts(root_dir: String = "res://", editor_interface: EditorInterface = null) -> Dictionary:
	var out := {}
	for sp_raw in _scan_project_files_by_ext(root_dir, ".gd", 40):
		var sp := String(sp_raw)
		var f := FileAccess.open(sp, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			if not txt.strip_edges().is_empty():
				out[sp] = txt.left(65536)
	return merge_script_buffer_overrides(out, collect_open_script_editor_buffers(editor_interface))


func _get_open_scene_roots_by_path(editor_interface: EditorInterface) -> Dictionary:
	var roots := {}
	if editor_interface == null:
		return roots
	if editor_interface.has_method("get_open_scene_roots"):
		var raw_open: Variant = editor_interface.call("get_open_scene_roots")
		if typeof(raw_open) == TYPE_ARRAY:
			for r_v in (raw_open as Array):
				if r_v is Node and is_instance_valid(r_v):
					var r_node := r_v as Node
					var rp := r_node.scene_file_path if not r_node.scene_file_path.is_empty() else String(r_node.name)
					if not rp.is_empty():
						roots[rp] = r_node
	var edited_root: Node = editor_interface.get_edited_scene_root()
	if edited_root != null and is_instance_valid(edited_root):
		var ep := edited_root.scene_file_path if not edited_root.scene_file_path.is_empty() else String(edited_root.name)
		if not ep.is_empty():
			roots[ep] = edited_root
	return roots


func _round_vec3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


func _round_vec2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]


func extract_script_extends(code: String) -> String:
	for line in code.split("\n"):
		var t := line.strip_edges()
		if t.is_empty() or t.begins_with("#"):
			continue
		if t.begins_with("extends "):
			var cls := t.substr("extends ".length()).strip_edges()
			var space_i := cls.find(" ")
			if space_i > 0:
				cls = cls.substr(0, space_i).strip_edges()
			var tab_i := cls.find("\t")
			if tab_i > 0:
				cls = cls.substr(0, tab_i).strip_edges()
			return cls
	return ""


func _snapshot_node_tree(root: Node, limit_nodes: int = 140) -> Array:
	var out: Array = []
	if root == null:
		return out
	var queue: Array[Node] = [root]
	while not queue.is_empty() and out.size() < limit_nodes:
		var cur: Node = queue.pop_front()
		var rel := "." if cur == root else String(root.get_path_to(cur))
		var scr_path := ""
		var scr_extends := ""
		var scr: Variant = cur.get_script()
		if scr is Script:
			scr_path = String((scr as Script).resource_path)
			scr_extends = extract_script_extends(String((scr as Script).source_code))
		var entry := {
			"path": rel,
			"name": cur.name,
			"class": cur.get_class(),
		}
		if not scr_path.is_empty():
			entry["script"] = scr_path
		if not scr_extends.is_empty():
			entry["scriptExtends"] = scr_extends
		if cur is Node3D:
			var n3: Node3D = cur as Node3D
			entry["position"] = _round_vec3(n3.position)
			if not n3.rotation_degrees.is_zero_approx():
				entry["rotationDegrees"] = _round_vec3(n3.rotation_degrees)
			if not n3.scale.is_equal_approx(Vector3.ONE):
				entry["scale"] = _round_vec3(n3.scale)
		elif cur is Node2D:
			var n2: Node2D = cur as Node2D
			entry["position"] = _round_vec2(n2.position)
			if not is_zero_approx(n2.rotation_degrees):
				entry["rotationDegrees"] = snappedf(n2.rotation_degrees, 0.01)
			if not n2.scale.is_equal_approx(Vector2.ONE):
				entry["scale"] = _round_vec2(n2.scale)
		if cur is CollisionObject3D or cur is CollisionObject2D:
			entry["collisionLayer"] = int(cur.get("collision_layer"))
			entry["collisionMask"] = int(cur.get("collision_mask"))
		if cur is CollisionShape3D or cur is CollisionShape2D:
			var shp: Variant = cur.get("shape")
			entry["shape"] = shp.get_class() if shp != null else "<EMPTY>"
			if bool(cur.get("disabled")):
				entry["disabled"] = true
			if shp is BoxShape3D:
				entry["shapeProps"] = { "size": _round_vec3((shp as BoxShape3D).size) }
			elif shp is SphereShape3D:
				entry["shapeProps"] = { "radius": snappedf((shp as SphereShape3D).radius, 0.01) }
			elif shp is CapsuleShape3D:
				var c3: CapsuleShape3D = shp as CapsuleShape3D
				entry["shapeProps"] = { "radius": snappedf(c3.radius, 0.01), "height": snappedf(c3.height, 0.01) }
			elif shp is CylinderShape3D:
				var y3: CylinderShape3D = shp as CylinderShape3D
				entry["shapeProps"] = { "radius": snappedf(y3.radius, 0.01), "height": snappedf(y3.height, 0.01) }
			elif shp is RectangleShape2D:
				entry["shapeProps"] = { "size": _round_vec2((shp as RectangleShape2D).size) }
			elif shp is CircleShape2D:
				entry["shapeProps"] = { "radius": snappedf((shp as CircleShape2D).radius, 0.01) }
			elif shp is CapsuleShape2D:
				var c2: CapsuleShape2D = shp as CapsuleShape2D
				entry["shapeProps"] = { "radius": snappedf(c2.radius, 0.01), "height": snappedf(c2.height, 0.01) }
		elif cur is MeshInstance3D:
			var msh: Variant = cur.get("mesh")
			entry["mesh"] = msh.get_class() if msh != null else "<EMPTY>"
		elif cur is Area3D or cur is Area2D:
			entry["monitoring"] = bool(cur.get("monitoring"))
			entry["monitorable"] = bool(cur.get("monitorable"))
		elif cur is RayCast3D:
			var r3: RayCast3D = cur as RayCast3D
			entry["enabled"] = r3.enabled
			entry["targetPosition"] = _round_vec3(r3.target_position)
		elif cur is RayCast2D:
			var r2: RayCast2D = cur as RayCast2D
			entry["enabled"] = r2.enabled
			entry["targetPosition"] = _round_vec2(r2.target_position)
		elif cur is Timer:
			entry["wait_time"] = cur.get("wait_time")
			entry["one_shot"] = cur.get("one_shot")
		var grps: Array = []
		for grp in cur.get_groups():
			var gs := String(grp)
			if not gs.begins_with("_"):
				grps.append(gs)
		if not grps.is_empty():
			entry["groups"] = grps
		if cur != root and not cur.scene_file_path.is_empty():
			entry["sceneFilePath"] = cur.scene_file_path
		var sigs: Array = []
		for sig_info in cur.get_signal_list():
			var sname := String(sig_info.get("name", ""))
			for conn in cur.get_signal_connection_list(sname):
				var cb: Callable = conn.get("callable", Callable())
				if cb.is_valid():
					var tgt := cb.get_object()
					if tgt is Node:
						sigs.append("%s->%s.%s" % [sname, (tgt as Node).name, String(cb.get_method())])
		if not sigs.is_empty():
			entry["signals"] = sigs
		out.append(entry)
		for ch in cur.get_children():
			queue.append(ch)
	return out


func capture_rich_scene_snapshot(editor_interface: EditorInterface, extra_scene_paths: PackedStringArray = PackedStringArray()) -> Dictionary:
	var scenes := {}
	var open_roots := _get_open_scene_roots_by_path(editor_interface)
	for ep_key in open_roots.keys():
		var ep := String(ep_key)
		var open_r: Node = open_roots[ep_key] as Node
		if open_r != null:
			scenes[ep] = {
				"isOpenInEditor": true,
				"nodes": _snapshot_node_tree(open_r),
			}
	for p in extra_scene_paths:
		var sp := String(p).strip_edges()
		if sp.is_empty() or scenes.has(sp) or not ResourceLoader.exists(sp):
			continue
		var ps := ResourceLoader.load(sp, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if ps != null:
			var inst := ps.instantiate()
			if inst != null:
				scenes[sp] = {
					"isOpenInEditor": false,
					"nodes": _snapshot_node_tree(inst),
				}
				inst.free()
	return { "scenes": scenes }


func _describe_input_event(ev: InputEvent) -> String:
	if ev == null:
		return ""
	var prefix := ""
	if ev is InputEventWithModifiers:
		var mods := ev as InputEventWithModifiers
		if mods.ctrl_pressed:
			prefix += "Ctrl+"
		if mods.shift_pressed:
			prefix += "Shift+"
		if mods.alt_pressed:
			prefix += "Alt+"
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		var b_lbl := ""
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				b_lbl = "LMB"
			MOUSE_BUTTON_RIGHT:
				b_lbl = "RMB"
			MOUSE_BUTTON_MIDDLE:
				b_lbl = "MMB"
			MOUSE_BUTTON_WHEEL_UP:
				b_lbl = "WheelUp"
			MOUSE_BUTTON_WHEEL_DOWN:
				b_lbl = "WheelDown"
			_:
				b_lbl = "Mouse%d" % int(mb.button_index)
		return prefix + b_lbl
	if ev is InputEventKey:
		var ke := ev as InputEventKey
		var kc: Key = ke.physical_keycode if ke.physical_keycode != KEY_NONE else (ke.keycode if ke.keycode != KEY_NONE else ke.key_label)
		var kl := OS.get_keycode_string(kc).strip_edges()
		return (prefix + kl) if not kl.is_empty() else ""
	return ev.as_text().strip_edges()


func capture_input_map_snapshot() -> Dictionary:
	var out := {}
	for p_raw in ProjectSettings.get_property_list():
		if typeof(p_raw) != TYPE_DICTIONARY:
			continue
		var pname := String((p_raw as Dictionary).get("name", ""))
		if not pname.begins_with("input/") or pname.begins_with("input/ui_"):
			continue
		var act := pname.substr("input/".length()).strip_edges()
		if act.is_empty():
			continue
		var labels := []
		var raw_val: Variant = ProjectSettings.get_setting(pname)
		if typeof(raw_val) == TYPE_DICTIONARY:
			var evs: Variant = (raw_val as Dictionary).get("events", [])
			if typeof(evs) == TYPE_ARRAY:
				for ev_raw in (evs as Array):
					if ev_raw is InputEvent:
						var desc := _describe_input_event(ev_raw as InputEvent)
						if not desc.is_empty() and not (desc in labels):
							labels.append(desc)
		out[act] = labels
	return out


func _strip_scope_bullet_prefix(raw: String) -> String:
	var s: String = raw.strip_edges()
	if s.begins_with("•"):
		s = s.substr(1).strip_edges()
	elif s.begins_with("- ") or s.begins_with("* "):
		s = s.substr(2).strip_edges()
	return s


func _normalize_causal_arrow(raw: String) -> String:
	return raw.replace(" -> ", " → ").replace("-> ", " → ").replace(" ->", " → ").replace("->", " → ").strip_edges()


func parse_structured_scope_fields(raw_text: String) -> Dictionary:
	var lines: PackedStringArray = raw_text.replace("\r\n", "\n").split("\n")
	var section: String = "goal"
	var goal_lines := PackedStringArray()
	var in_scope_lines := PackedStringArray()
	var done_lines := PackedStringArray()

	for raw_line in lines:
		var trimmed: String = raw_line.strip_edges()
		if trimmed.is_empty():
			continue
		var colon_idx: int = trimmed.find(":")
		if colon_idx != -1:
			var hdr: String = trimmed.substr(0, colon_idx).strip_edges().to_lower()
			var rest: String = trimmed.substr(colon_idx + 1).strip_edges()
			if hdr == "goal":
				section = "goal"
				if not rest.is_empty():
					goal_lines.append(rest)
				continue
			elif hdr == "in scope" or (hdr.begins_with("in scope (") and hdr.ends_with(")")):
				section = "in_scope"
				var b_rest: String = _strip_scope_bullet_prefix(rest)
				if not b_rest.is_empty():
					in_scope_lines.append(b_rest)
				continue
			elif hdr == "out of scope" or hdr == "exclusions" or hdr.begins_with("out of scope (") or hdr.begins_with("exclusions ("):
				section = "out_of_scope"
				continue
			elif hdr == "done when" or hdr == "playtest gate" or hdr == "end goal":
				section = "done_when"
				if not rest.is_empty():
					done_lines.append(rest)
				continue

		if section == "goal":
			if (trimmed.begins_with("•") or trimmed.begins_with("- ") or trimmed.begins_with("* ")) and not goal_lines.is_empty():
				section = "in_scope"
				var b_line: String = _strip_scope_bullet_prefix(trimmed)
				if not b_line.is_empty():
					in_scope_lines.append(b_line)
			else:
				goal_lines.append(trimmed)
		elif section == "in_scope":
			var bullet: String = _strip_scope_bullet_prefix(trimmed)
			if not bullet.is_empty():
				in_scope_lines.append(bullet)
		elif section == "out_of_scope":
			continue
		else:
			var done_part: String = _strip_scope_bullet_prefix(trimmed)
			if not done_part.is_empty():
				done_lines.append(done_part)

	return {
		"goal": " ".join(goal_lines).strip_edges(),
		"in_scope": in_scope_lines,
		"done_when": _normalize_causal_arrow(" ".join(done_lines).strip_edges()),
	}


func dedupe_scope_items(raw_items: Variant, max_items: int = 6) -> PackedStringArray:
	if typeof(raw_items) != TYPE_ARRAY and typeof(raw_items) != TYPE_PACKED_STRING_ARRAY:
		return PackedStringArray()
	var out: Array[String] = []
	var key_to_idx: Dictionary = {}
	for raw_entry in raw_items:
		var clean: String = _strip_scope_bullet_prefix(str(raw_entry))
		if clean.is_empty():
			continue
		var norm_key: String = clean.trim_prefix("+").strip_edges().to_lower()
		if norm_key.is_empty():
			continue
		if key_to_idx.has(norm_key):
			var existing_idx: int = int(key_to_idx[norm_key])
			if clean.begins_with("+") and not out[existing_idx].begins_with("+"):
				out[existing_idx] = clean
			continue
		if out.size() >= max_items:
			continue
		key_to_idx[norm_key] = out.size()
		out.append(clean)
	return PackedStringArray(out)


func resolve_clean_feature_spec(feat: Dictionary, release_ver: String = "v0.1") -> Dictionary:
	var feat_title: String = str(feat.get("title", "Feature")).strip_edges()
	var parsed: Dictionary = parse_structured_scope_fields(str(feat.get("goal", "")))
	var clean_goal: String = str(parsed.get("goal", "")).strip_edges()

	var scope_items: PackedStringArray = dedupe_scope_items(feat.get("coveredScope", feat.get("inScope", [])), 6)
	if scope_items.is_empty():
		var parsed_in_scope: PackedStringArray = parsed.get("in_scope", PackedStringArray())
		if not release_ver.is_empty() and release_ver != "v0.1":
			var plus_only: Array[String] = []
			for item in parsed_in_scope:
				if item.begins_with("+"):
					plus_only.append(item)
			scope_items = dedupe_scope_items(plus_only, 6) if not plus_only.is_empty() else dedupe_scope_items(parsed_in_scope, 6)
		else:
			scope_items = dedupe_scope_items(parsed_in_scope, 6)

	var has_plus_delta: bool = false
	for si in scope_items:
		if si.begins_with("+"):
			has_plus_delta = true
			break
	var scope_header: String = ("In Scope (%s)" % release_ver) if (not release_ver.is_empty() and release_ver != "v0.1" and has_plus_delta) else "In Scope"

	var raw_done: String = str(feat.get("doneWhen", feat.get("playtestCriteria", ""))).strip_edges()
	var lower_done: String = raw_done.to_lower()
	if lower_done.begins_with("done when:"):
		raw_done = raw_done.substr("done when:".length()).strip_edges()
	elif lower_done.begins_with("playtest:"):
		raw_done = raw_done.substr("playtest:".length()).strip_edges()
	raw_done = _normalize_causal_arrow(raw_done)
	var clean_lower_done: String = raw_done.to_lower()
	var is_generic_done: bool = (
		raw_done.is_empty() or
		raw_done.begins_with("+") or
		clean_lower_done.begins_with("press f6 and verify ") or
		clean_lower_done.begins_with("verify stage deliverables and checklist criteria")
	)
	var parsed_done: String = str(parsed.get("done_when", "")).strip_edges()
	if is_generic_done and not parsed_done.is_empty():
		raw_done = parsed_done
	elif is_generic_done:
		raw_done = "Press F6 and verify %s works with 0 console errors." % (feat_title if not feat_title.is_empty() else "this feature")

	return {
		"goal": clean_goal,
		"scope_items": scope_items,
		"scope_header": scope_header,
		"done_when": raw_done,
	}


func format_feature_context_markdown(
	feat: Dictionary,
	live_scripts: Dictionary,
	scene_snap: Dictionary,
	input_map_snap: Dictionary,
	recent_errors: Array = [],
	project_ctx: Dictionary = {}
) -> String:
	var out := PackedStringArray()
	out.append("## LAYERS Godot Context")

	var proj_title: String = str(project_ctx.get("projectTitle", "")).strip_edges()
	var rel_ver: String = str(project_ctx.get("releaseVersion", feat.get("releaseVersion", ""))).strip_edges()
	var epic_code: String = str(project_ctx.get("epicCode", "")).strip_edges()
	var epic_title: String = str(project_ctx.get("epicTitle", "")).strip_edges()
	var pillars: PackedStringArray = dedupe_scope_items(project_ctx.get("designPillars", []), 6)
	var tradeoffs: PackedStringArray = dedupe_scope_items(project_ctx.get("tradeOffs", []), 6)
	if not proj_title.is_empty() or not epic_title.is_empty() or not pillars.is_empty() or not tradeoffs.is_empty():
		out.append("")
		out.append("### Project & Epic Context")
		if not proj_title.is_empty():
			out.append("- Project: %s%s" % [proj_title, (" (%s)" % rel_ver) if not rel_ver.is_empty() else ""])
		if not epic_title.is_empty():
			var epic_prefix := ("%s · " % epic_code) if not epic_code.is_empty() else ""
			out.append("- Active Epic: %s%s" % [epic_prefix, epic_title])
		if not pillars.is_empty():
			out.append("- Design Pillars: %s" % " · ".join(pillars))
		if not tradeoffs.is_empty():
			out.append("- Trade-Offs: %s" % " · ".join(tradeoffs))

	var feat_title: String = str(feat.get("title", "")).strip_edges()
	var clean_spec: Dictionary = resolve_clean_feature_spec(feat, rel_ver)
	var feat_goal: String = str(clean_spec.get("goal", "")).strip_edges()
	var covered_items: PackedStringArray = clean_spec.get("scope_items", PackedStringArray())
	var guards_raw: Variant = feat.get("edgeCases", [])
	var issues_raw: Variant = feat.get("openIssues", [])
	var done_when: String = str(clean_spec.get("done_when", "")).strip_edges()

	if not feat_title.is_empty() or not feat_goal.is_empty() or not done_when.is_empty():
		out.append("")
		out.append("### Active Feature")
		if not feat_title.is_empty():
			out.append("- Title: %s" % feat_title)
		if not feat_goal.is_empty() and feat_goal != feat_title:
			out.append("- Goal: %s" % feat_goal)
		if not covered_items.is_empty():
			out.append("- In Scope:")
			for ci in covered_items:
				out.append("  - %s" % ci)
		var tuning_raw: Variant = feat.get("tuningParams", [])
		if typeof(tuning_raw) == TYPE_ARRAY or typeof(tuning_raw) == TYPE_PACKED_STRING_ARRAY:
			var tuning_lines := PackedStringArray()
			for t_item in tuning_raw:
				var ts := str(t_item).strip_edges()
				if not ts.is_empty():
					tuning_lines.append(ts)
			if not tuning_lines.is_empty():
				out.append("- Tuning Variables:")
				for tl in tuning_lines:
					out.append("  - %s" % tl)
		var sibling_raw: Variant = project_ctx.get("siblingTuning", [])
		if typeof(sibling_raw) == TYPE_ARRAY:
			var sibling_lines := PackedStringArray()
			for sib_entry in (sibling_raw as Array):
				if typeof(sib_entry) != TYPE_DICTIONARY:
					continue
				var sd: Dictionary = sib_entry
				var sib_title: String = str(sd.get("title", "")).strip_edges()
				var params_raw: Variant = sd.get("tuningParams", [])
				var param_parts := PackedStringArray()
				if typeof(params_raw) == TYPE_ARRAY or typeof(params_raw) == TYPE_PACKED_STRING_ARRAY:
					for p_item in params_raw:
						var ps := str(p_item).strip_edges()
						if not ps.is_empty():
							param_parts.append(ps)
				if not sib_title.is_empty() and not param_parts.is_empty():
					sibling_lines.append("  - %s: %s" % [sib_title, ", ".join(param_parts)])
			if not sibling_lines.is_empty():
				out.append("- Sibling Epic Tuning Variables (Reuse Exact Identifiers):")
				for sl in sibling_lines:
					out.append(sl)
		if typeof(guards_raw) == TYPE_ARRAY:
			var guard_lines := PackedStringArray()
			for g_raw in (guards_raw as Array):
				if typeof(g_raw) == TYPE_DICTIONARY:
					var gd: Dictionary = g_raw
					var gt := str(gd.get("text", gd.get("rawText", ""))).strip_edges()
					if not gt.is_empty():
						guard_lines.append("  - [%s] %s" % ["x" if bool(gd.get("signedOff", false)) else " ", gt])
				else:
					var gs := str(g_raw).strip_edges()
					if not gs.is_empty():
						guard_lines.append("  - [ ] %s" % gs)
			if not guard_lines.is_empty():
				out.append("- Playtest Guards:")
				for gl in guard_lines:
					out.append(gl)
		if typeof(issues_raw) == TYPE_ARRAY:
			var issue_lines := PackedStringArray()
			for i_raw in (issues_raw as Array):
				var it_txt := ""
				if typeof(i_raw) == TYPE_DICTIONARY:
					it_txt = str((i_raw as Dictionary).get("text", "")).strip_edges()
				else:
					it_txt = str(i_raw).strip_edges()
				if not it_txt.is_empty():
					issue_lines.append("  - [FIX] %s" % it_txt)
			if not issue_lines.is_empty():
				out.append("- Open Playtest Issues:")
				for il in issue_lines:
					out.append(il)
		if not done_when.is_empty():
			out.append("- Done When: %s" % done_when)

	var scenes_raw: Variant = scene_snap.get("scenes", {})
	if typeof(scenes_raw) == TYPE_DICTIONARY and not (scenes_raw as Dictionary).is_empty():
		var scenes_dict: Dictionary = scenes_raw
		var scene_keys: Array = scenes_dict.keys()
		scene_keys.sort()
		out.append("")
		out.append("### Scenes (%d)" % scene_keys.size())
		for sk_raw in scene_keys:
			var spath: String = str(sk_raw)
			var sinfo_raw: Variant = scenes_dict.get(sk_raw, {})
			var is_open: bool = false
			var nodes_arr: Array = []
			if typeof(sinfo_raw) == TYPE_DICTIONARY:
				var sinfo: Dictionary = sinfo_raw
				is_open = bool(sinfo.get("isOpenInEditor", false))
				var nraw: Variant = sinfo.get("nodes", [])
				if typeof(nraw) == TYPE_ARRAY:
					nodes_arr = nraw
			out.append("- `%s`%s (%d nodes)" % [spath, " [open]" if is_open else "", nodes_arr.size()])
			for n_raw in nodes_arr.slice(0, 24):
				if typeof(n_raw) == TYPE_DICTIONARY:
					var nd: Dictionary = n_raw
					var npath: String = str(nd.get("path", nd.get("name", "")))
					var ntype: String = str(nd.get("class", nd.get("type", "")))
					var nscr: String = str(nd.get("script", ""))
					var extra: String = " (`%s`)" % nscr if not nscr.is_empty() else ""
					var ngrps_raw: Variant = nd.get("groups", [])
					if typeof(ngrps_raw) == TYPE_ARRAY and not (ngrps_raw as Array).is_empty():
						var g_packed := PackedStringArray()
						for gr in (ngrps_raw as Array):
							var gs := str(gr).strip_edges()
							if not gs.is_empty():
								g_packed.append(gs)
						if not g_packed.is_empty():
							extra += " [groups: %s]" % ", ".join(g_packed)
					out.append("  - `%s` : %s%s" % [npath, ntype, extra])
				else:
					out.append("  - %s" % str(n_raw))

	if not input_map_snap.is_empty():
		var act_keys: Array = input_map_snap.keys()
		act_keys.sort()
		out.append("")
		out.append("### InputMap Actions (%d)" % act_keys.size())
		for ak_raw in act_keys:
			var act_name: String = str(ak_raw)
			var raw_keys: Variant = input_map_snap.get(ak_raw, [])
			var packed_keys := PackedStringArray()
			if typeof(raw_keys) == TYPE_ARRAY or typeof(raw_keys) == TYPE_PACKED_STRING_ARRAY:
				for rk in raw_keys:
					packed_keys.append(str(rk))
			out.append("- `%s`: %s" % [act_name, ", ".join(packed_keys) if not packed_keys.is_empty() else "(unbound)"])

	var err_lines := PackedStringArray()
	for e_raw in recent_errors:
		var es: String = str(e_raw).strip_edges()
		if not es.is_empty():
			err_lines.append(es)
	if not err_lines.is_empty():
		out.append("")
		out.append("### Recent Godot Errors (%d)" % err_lines.size())
		for es in err_lines.slice(0, 12):
			out.append("- %s" % es)

	if not live_scripts.is_empty():
		var skeys: Array = live_scripts.keys()
		skeys.sort()
		out.append("")
		out.append("### Project Scripts (%d)" % skeys.size())
		var char_budget: int = 18000
		for sp_raw in skeys:
			var spath: String = str(sp_raw)
			var src: String = str(live_scripts.get(sp_raw, ""))
			out.append("")
			out.append("#### `%s`" % spath)
			if char_budget >= src.length() + 64:
				out.append("```gdscript")
				out.append(src.strip_edges())
				out.append("```")
				char_budget -= src.length()
			else:
				var line_cnt: int = src.split("\n").size()
				out.append("(%d lines, truncated to keep clipboard concise)" % line_cnt)

	return "\n".join(out).strip_edges() + "\n"
