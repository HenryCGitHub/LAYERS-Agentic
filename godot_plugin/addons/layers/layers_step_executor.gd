@tool
extends RefCounted

# Hierarchy-aware Scene, InputMap, Signal, and GDScript Step Engine
# for LAYERS Godot 4 Editor Plugin (v2.7.2+).

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


var _eval_cache: Dictionary = {}


func format_compile_error_entry(code: String, rationale: String, file: String = "", line: int = 0) -> String:
	return _CompileProbeLogger.format_entry(code, rationale, file, line)


func _create_compile_probe_logger() -> _CompileProbeLogger:
	return _CompileProbeLogger.new()
var _eval_cache_epoch: int = 0
var _cached_base_ctrl_id: int = 0
var _cached_debugger_roots: Array[Node] = []
var _cached_editor_log_roots: Array[Node] = []
var _last_healed_proj_mtime: int = -1


func invalidate_eval_cache() -> void:
	_eval_cache.clear()
	_eval_cache_epoch += 1
	_last_healed_proj_mtime = -1


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


func resolve_effective_step_path(step: Dictionary, feat: Dictionary) -> String:
	var p: String = str(step.get("stepPath", "")).strip_edges()
	if p.begins_with("res://"):
		if p.ends_with(".gd") and not FileAccess.file_exists(p):
			var hinted_gd: String = _find_mentioned_existing_gd(step)
			if not hinted_gd.is_empty():
				return hinted_gd
		return p
	return str(feat.get("primaryAsset", "")).strip_edges()


func _find_mentioned_existing_gd(step: Dictionary) -> String:
	var combined: String = "%s\n%s\n%s" % [
		str(step.get("locationLabel", "")),
		str(step.get("instruction", "")),
		str(step.get("verifyResult", "")),
	]
	var re := RegEx.new()
	re.compile("([a-zA-Z0-9_]+\\.gd)")
	var matches: Array[RegExMatch] = re.search_all(combined)
	for m in matches:
		var fname: String = m.get_string(1)
		if fname.is_empty():
			continue
		var candidates := PackedStringArray([
			"res://scripts/%s" % fname,
			"res://%s" % fname,
		])
		for cand in candidates:
			if FileAccess.file_exists(cand):
				return cand
	return ""


# ---------------------------------------------------------------------------
# GDScript Diff Stripping & Surgical Hunk Merging
# ---------------------------------------------------------------------------

func _is_non_gdscript_diagram_line(line: String) -> bool:
	var t: String = line.strip_edges()
	if t.is_empty():
		return false
	if "──►" in t or "─►" in t:
		return true
	if t.begins_with("|") and t.ends_with("|") and t.count("|") >= 2:
		return true
	var diag_re := RegEx.new()
	diag_re.compile("^\\[[^\\]]+\\]\\s*(?:-->|->)\\s*\\[")
	return diag_re.search(t) != null


func is_likely_gdscript_snippet(raw_text: String) -> bool:
	var clean: String = strip_diff_prefixes(raw_text).strip_edges()
	if clean.is_empty():
		return false
	for raw_line in clean.split("\n"):
		var t: String = raw_line.strip_edges()
		if t.is_empty() or t.begins_with("#") or _is_non_gdscript_diagram_line(raw_line):
			continue
		if (
			t.begins_with("extends ") or t.begins_with("class_name ") or
			t.begins_with("@tool") or t.begins_with("@icon") or
			t.begins_with("@export") or t.begins_with("@onready") or
			t.begins_with("signal ") or t.begins_with("enum ") or
			t.begins_with("const ") or t.begins_with("static func ") or
			t.begins_with("func ") or t.begins_with("var ") or
			t.begins_with("if ") or t.begins_with("elif ") or
			t.begins_with("else:") or t.begins_with("for ") or
			t.begins_with("while ") or t.begins_with("match ") or
			t == "pass" or t.begins_with("return") or t.begins_with("await ")
		):
			return true
		if ":= " in t or " = " in t or "+=" in t or "-=" in t or ".connect(" in t or ".emit(" in t or "$" in t:
			return true
	return false


func resolve_step_code_text(step: Dictionary) -> String:
	var patch_raw: Variant = step.get("scriptPatch", null)
	if typeof(patch_raw) == TYPE_DICTIONARY:
		var patch_dict: Dictionary = patch_raw
		var rep_raw: String = str(patch_dict.get("replaceBlock", "")).strip_edges()
		if not rep_raw.is_empty() and is_likely_gdscript_snippet(rep_raw):
			return strip_diff_prefixes(rep_raw)
	var snip: String = str(step.get("codeSnippet", "")).strip_edges()
	if snip.is_empty() or not is_likely_gdscript_snippet(snip):
		return ""
	return strip_diff_prefixes(snip)


func strip_diff_prefixes(raw: String) -> String:
	var lines: PackedStringArray = raw.split("\n")
	var out: PackedStringArray = []
	for line in lines:
		if line.begins_with("+ "):
			out.append(line.substr(2))
		elif line == "+":
			out.append("")
		elif line.begins_with("+") and not line.begins_with("++"):
			out.append(line.substr(1))
		else:
			out.append(line)
	return "\n".join(out).strip_edges()


# ---------------------------------------------------------------------------
# Vector Literal Parsers
# ---------------------------------------------------------------------------

func _parse_vector3_literal(raw: String) -> Variant:
	var re := RegEx.new()
	re.compile("\\(\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*,\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*,\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*\\)")
	var m: RegExMatch = re.search(raw)
	if m == null:
		return null
	return Vector3(
		m.get_string(1).to_float(),
		m.get_string(2).to_float(),
		m.get_string(3).to_float()
	)


func _parse_vector2_literal(raw: String) -> Variant:
	if "Vector3" in raw:
		return null
	var re := RegEx.new()
	re.compile("\\(\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*,\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*\\)")
	var m: RegExMatch = re.search(raw)
	if m == null:
		return null
	return Vector2(
		m.get_string(1).to_float(),
		m.get_string(2).to_float()
	)


# ---------------------------------------------------------------------------
# InputMap Parsers
# ---------------------------------------------------------------------------

func parse_input_specs(step: Dictionary) -> Array:
	var specs: Array = []
	var seen: Dictionary = {}
	var area2: String = str(step.get("area2Inspector", "")).strip_edges()
	var instr: String = str(step.get("instruction", "")).strip_edges()

	# Match `move_forward (W)` or `Add dash action (Space)`
	var text_scan: String = "%s\n%s" % [area2, instr]
	var pair_re := RegEx.new()
	pair_re.compile("\\b([a-z][a-z0-9_]{1,28})\\s+(?:action\\s+)?\\(([A-Za-z0-9_ ]{1,16})\\)")
	var matches: Array[RegExMatch] = pair_re.search_all(text_scan)
	for m in matches:
		var act2: String = m.get_string(1).strip_edges()
		var key2: String = m.get_string(2).strip_edges()
		if act2 == "action" or act2 == "in" or act2 == "at":
			continue
		if not seen.has(act2):
			seen[act2] = true
			specs.append({"action": act2, "keyLabel": key2})

	return specs


func open_res_path(editor_interface: EditorInterface, res_path: String, line_number: int = -1) -> String:
	if editor_interface == null:
		return "EditorInterface unavailable."
	var clean_path := res_path.strip_edges()
	if clean_path.ends_with(".tscn") or clean_path.ends_with(".scn"):
		if FileAccess.file_exists(clean_path):
			editor_interface.open_scene_from_path(clean_path)
			return ""
		return "%s does not exist yet — click Build Feature in Godot." % clean_path
	if not FileAccess.file_exists(clean_path):
		return "%s does not exist yet — click Build Feature in Godot." % clean_path
	var res: Resource = null
	if clean_path.ends_with(".gd"):
		var open_buffers := collect_open_script_editor_buffers(editor_interface)
		res = ResourceLoader.load(clean_path, "Script", ResourceLoader.CACHE_MODE_REUSE) if open_buffers.has(clean_path) else reload_script_safely(clean_path)
	else:
		res = ResourceLoader.load(clean_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if res is Script:
		if line_number > 0:
			editor_interface.edit_script(res as Script, line_number)
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

func _resolve_node_by_rel_path(root: Node, rel_path: String) -> Node:
	if root == null:
		return null
	if rel_path == "." or rel_path.is_empty():
		return root
	var by_path: Node = root.get_node_or_null(NodePath(rel_path))
	if by_path != null:
		return by_path
	var parts: PackedStringArray = rel_path.split("/", false)
	if not parts.is_empty():
		return _find_node_recursive(root, parts[parts.size() - 1])
	return null


func _find_node_recursive(root: Node, target_name: String) -> Node:
	if root == null or target_name.is_empty():
		return null
	if root.name.to_lower() == target_name.to_lower():
		return root
	for child in root.get_children():
		var found: Node = _find_node_recursive(child, target_name)
		if found != null:
			return found
	return null


func _find_instanced_scene_node(root: Node, scene_path: String) -> Node:
	if root == null or scene_path.is_empty():
		return null
	for child in root.get_children():
		if child.scene_file_path == scene_path:
			return child
		var deeper: Node = _find_instanced_scene_node(child, scene_path)
		if deeper != null:
			return deeper
	return null


func _has_real_input_binding(act_name: String, setting_key: String) -> bool:
	if ProjectSettings.has_setting(setting_key):
		var val: Variant = ProjectSettings.get_setting(setting_key)
		if typeof(val) == TYPE_DICTIONARY:
			var d: Dictionary = val
			var evs: Variant = d.get("events", [])
			if typeof(evs) == TYPE_ARRAY and not (evs as Array).is_empty():
				return true
	if InputMap.has_action(act_name) and not InputMap.action_get_events(act_name).is_empty():
		return true
	return false


func _match_single_input_token(raw_tok: String) -> InputEvent:
	var k: String = raw_tok.strip_edges().to_upper()
	while "  " in k:
		k = k.replace("  ", " ")
	if k.is_empty():
		return null
	if (
		k == "LMB" or k == "MOUSE LEFT" or k == "LEFT CLICK" or
		k == "LEFT MOUSE" or k == "LEFT MOUSE BUTTON" or k == "MOUSE BUTTON LEFT" or
		k == "MOUSE 1" or k == "MB1" or k == "PRIMARY CLICK"
	):
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		return mb
	if (
		k == "RMB" or k == "MOUSE RIGHT" or k == "RIGHT CLICK" or
		k == "RIGHT MOUSE" or k == "RIGHT MOUSE BUTTON" or k == "MOUSE BUTTON RIGHT" or
		k == "MOUSE 2" or k == "MB2" or k == "SECONDARY CLICK"
	):
		var mb2 := InputEventMouseButton.new()
		mb2.button_index = MOUSE_BUTTON_RIGHT
		return mb2
	if (
		k == "MMB" or k == "MOUSE MIDDLE" or k == "MIDDLE CLICK" or
		k == "MIDDLE MOUSE" or k == "MIDDLE MOUSE BUTTON" or k == "MOUSE BUTTON MIDDLE" or
		k == "MOUSE 3" or k == "MB3"
	):
		var mb3 := InputEventMouseButton.new()
		mb3.button_index = MOUSE_BUTTON_MIDDLE
		return mb3
	if k == "WHEEL UP" or k == "MOUSE WHEEL UP" or k == "SCROLL UP":
		var mw_up := InputEventMouseButton.new()
		mw_up.button_index = MOUSE_BUTTON_WHEEL_UP
		return mw_up
	if k == "WHEEL DOWN" or k == "MOUSE WHEEL DOWN" or k == "SCROLL DOWN":
		var mw_dn := InputEventMouseButton.new()
		mw_dn.button_index = MOUSE_BUTTON_WHEEL_DOWN
		return mw_dn

	var keycode: Key = KEY_NONE
	match k:
		"W":
			keycode = KEY_W
		"A":
			keycode = KEY_A
		"S":
			keycode = KEY_S
		"D":
			keycode = KEY_D
		"E":
			keycode = KEY_E
		"Q":
			keycode = KEY_Q
		"F":
			keycode = KEY_F
		"R":
			keycode = KEY_R
		"G":
			keycode = KEY_G
		"C":
			keycode = KEY_C
		"V":
			keycode = KEY_V
		"SPACE", "SPACEBAR", "SPACE BAR":
			keycode = KEY_SPACE
		"SHIFT", "LEFT SHIFT":
			keycode = KEY_SHIFT
		"CTRL", "CONTROL", "LEFT CTRL":
			keycode = KEY_CTRL
		"ALT", "LEFT ALT":
			keycode = KEY_ALT
		"ESC", "ESCAPE":
			keycode = KEY_ESCAPE
		"ENTER", "RETURN":
			keycode = KEY_ENTER
		"TAB":
			keycode = KEY_TAB
		"UP", "ARROW UP", "UP ARROW":
			keycode = KEY_UP
		"DOWN", "ARROW DOWN", "DOWN ARROW":
			keycode = KEY_DOWN
		"LEFT", "ARROW LEFT", "LEFT ARROW":
			keycode = KEY_LEFT
		"RIGHT", "ARROW RIGHT", "RIGHT ARROW":
			keycode = KEY_RIGHT
		_:
			keycode = OS.find_keycode_from_string(k)

	if keycode == KEY_NONE:
		return null
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	return ev


func _build_input_event_for_label(key_label: String) -> InputEvent:
	var direct := _match_single_input_token(key_label)
	if direct != null:
		return direct
	var normalized := key_label.replace("(", "/").replace(")", "/").replace("|", "/").replace(",", "/")
	for part in normalized.split("/", false):
		var ev := _match_single_input_token(part)
		if ev != null:
			return ev
	return null


func _infer_default_input_event_for_action(act_name: String) -> InputEvent:
	var a := act_name.strip_edges().to_lower()
	if a.is_empty():
		return null
	if "reload" in a:
		return _match_single_input_token("R")
	if "heavy" in a or "slam" in a or "special" in a or "ultimate" in a or "skill" in a or "ability" in a:
		return _match_single_input_token("Q")
	if "crouch" in a or "slide" in a or "duck" in a:
		return _match_single_input_token("CTRL")
	if "heal" in a or "potion" in a or "item" in a:
		return _match_single_input_token("F")
	if "inventory" in a or "map" in a or "score" in a or "tab" in a:
		return _match_single_input_token("TAB")
	if "strike" in a or "attack" in a or "fire" in a or "shoot" in a or "claw" in a or "slash" in a or "punch" in a or "primary" in a:
		return _match_single_input_token("LMB")
	if "parry" in a or "block" in a or "guard" in a or "aim" in a or "secondary" in a:
		return _match_single_input_token("RMB")
	if "dash" in a or "dodge" in a or "evade" in a or "sprint" in a:
		return _match_single_input_token("SHIFT")
	if "jump" in a:
		return _match_single_input_token("SPACE")
	if "interact" in a or "pickup" in a or a == "use":
		return _match_single_input_token("E")
	if "pause" in a or "menu" in a or "cancel" in a:
		return _match_single_input_token("ESC")
	if "forward" in a or "move_up" in a or a.ends_with("_up") or a == "up":
		return _match_single_input_token("W")
	if "back" in a or "move_down" in a or a.ends_with("_down") or a == "down":
		return _match_single_input_token("S")
	if "left" in a:
		return _match_single_input_token("A")
	if "right" in a:
		return _match_single_input_token("D")
	return null


func _is_bogus_non_player_action_name(act_name: String) -> bool:
	var a: String = act_name.strip_edges().to_lower()
	if a.is_empty():
		return true
	if "player" in a:
		return false
	if a.begins_with("enemy_") or a.begins_with("spawner_") or a.begins_with("wave_"):
		return true
	if a.ends_with("_action"):
		for non_player_tok in ["enemy", "spawner", "wave", "arena", "hud", "panel", "totem", "draft", "camera", "boss", "mob", "hazard"]:
			if non_player_tok in a:
				return true
	return false


func apply_input_ops(input_ops: Array) -> int:
	if input_ops.is_empty():
		return 0
	var changed: int = 0
	for raw_op in input_ops:
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = raw_op
		var act := String(op.get("action", "")).strip_edges()
		if act.is_empty() or act.begins_with("ui_"):
			continue
		var setting_key := "input/%s" % act
		var op_kind := String(op.get("op", "")).strip_edges().to_lower()
		var should_remove: bool = bool(op.get("remove", false)) or op_kind == "remove_action"
		if should_remove:
			var removed_any := false
			if ProjectSettings.has_setting(setting_key):
				ProjectSettings.set_setting(setting_key, null)
				removed_any = true
			if InputMap.has_action(act):
				InputMap.erase_action(act)
				removed_any = true
			if removed_any:
				changed += 1
			continue
		if _is_bogus_non_player_action_name(act):
			continue
		var overwrite: bool = bool(op.get("overwrite", false))
		var keys_raw: Variant = op.get("keys", [])
		var key_list: Array = keys_raw if typeof(keys_raw) == TYPE_ARRAY else [keys_raw]
		var events: Array = []
		for k_raw in key_list:
			var k_str := String(k_raw).strip_edges()
			if k_str.is_empty():
				continue
			var ev := _build_input_event_for_label(k_str)
			if ev != null:
				events.append(ev)
		if events.is_empty():
			var fallback_ev := _infer_default_input_event_for_action(act)
			if fallback_ev != null:
				events.append(fallback_ev)
		if not events.is_empty() and (overwrite or not _has_real_input_binding(act, setting_key)):
			ProjectSettings.set_setting(setting_key, {"deadzone": 0.2, "events": events})
			changed += 1
	if changed > 0:
		ProjectSettings.save()
		InputMap.load_from_project_settings()
		invalidate_eval_cache()
	return changed


func register_missing_script_input_actions(script_contents: Array) -> int:
	if script_contents.is_empty():
		return 0
	var rx_single := RegEx.new()
	rx_single.compile("(?:Input\\.(?:is_action_pressed|is_action_just_pressed|is_action_just_released|get_action_strength)|event\\.is_action(?:_pressed|_released)?)\\s*\\(\\s*[\"']([A-Za-z0-9_.:/-]+)[\"']")
	var rx_vec := RegEx.new()
	rx_vec.compile("Input\\.get_vector\\s*\\(\\s*[\"']([A-Za-z0-9_.:/-]+)[\"']\\s*,\\s*[\"']([A-Za-z0-9_.:/-]+)[\"']\\s*,\\s*[\"']([A-Za-z0-9_.:/-]+)[\"']\\s*,\\s*[\"']([A-Za-z0-9_.:/-]+)[\"']")
	var rx_axis := RegEx.new()
	rx_axis.compile("Input\\.get_axis\\s*\\(\\s*[\"']([A-Za-z0-9_.:/-]+)[\"']\\s*,\\s*[\"']([A-Za-z0-9_.:/-]+)[\"']")

	var discovered := {}
	for src_raw in script_contents:
		var src := String(src_raw)
		if src.is_empty():
			continue
		for m in rx_single.search_all(src):
			var act := m.get_string(1).strip_edges()
			if not act.is_empty():
				discovered[act] = true
		for mv in rx_vec.search_all(src):
			for gi in range(1, 5):
				var vact := mv.get_string(gi).strip_edges()
				if not vact.is_empty():
					discovered[vact] = true
		for ma in rx_axis.search_all(src):
			for ga in range(1, 3):
				var aact := ma.get_string(ga).strip_edges()
				if not aact.is_empty():
					discovered[aact] = true

	var added: int = 0
	for act_key in discovered.keys():
		var act := String(act_key)
		if act.is_empty() or act.begins_with("ui_") or _is_bogus_non_player_action_name(act):
			continue
		var setting_key := "input/%s" % act
		if _has_real_input_binding(act, setting_key):
			continue
		var ev := _infer_default_input_event_for_action(act)
		if ev != null:
			ProjectSettings.set_setting(setting_key, {"deadzone": 0.2, "events": [ev]})
			added += 1
	if added > 0:
		ProjectSettings.save()
		InputMap.load_from_project_settings()
		invalidate_eval_cache()
	return added


func heal_empty_project_input_actions(feat: Dictionary = {}) -> int:
	var key_hints := {}
	for st in feat.get("steps", []):
		for inp in parse_input_specs(st):
			var act := String(inp.get("action", "")).strip_edges()
			var kl := String(inp.get("keyLabel", "")).strip_edges()
			if not act.is_empty() and not kl.is_empty():
				key_hints[act] = kl

	var proj_mtime: int = int(FileAccess.get_modified_time("res://project.godot")) if FileAccess.file_exists("res://project.godot") else 0
	if key_hints.is_empty() and proj_mtime == _last_healed_proj_mtime:
		return 0

	var healed := 0
	for p_raw in ProjectSettings.get_property_list():
		var p_info: Dictionary = p_raw
		var pname := String(p_info.get("name", ""))
		if not pname.begins_with("input/") or pname.begins_with("input/ui_"):
			continue
		var act := pname.substr("input/".length())
		if _is_bogus_non_player_action_name(act) or _has_real_input_binding(act, pname):
			continue
		var hint_lbl := String(key_hints.get(act, ""))
		var ev: InputEvent = _build_input_event_for_label(hint_lbl)
		if ev == null:
			ev = _infer_default_input_event_for_action(act)
		if ev != null:
			ProjectSettings.set_setting(pname, {"deadzone": 0.2, "events": [ev]})
			healed += 1

	if healed > 0:
		ProjectSettings.save()
		InputMap.load_from_project_settings()
	_last_healed_proj_mtime = int(FileAccess.get_modified_time("res://project.godot")) if FileAccess.file_exists("res://project.godot") else proj_mtime
	return healed


func reload_script_safely(rpath: String, source_code: String = "") -> Script:
	if rpath.is_empty() or not FileAccess.file_exists(rpath):
		return null
	var code := source_code
	if code.is_empty():
		var rf := FileAccess.open(rpath, FileAccess.READ)
		if rf != null:
			code = rf.get_as_text()
			rf.close()
	var existing: Variant = ResourceLoader.load(rpath)
	if existing is GDScript:
		var gd_scr: GDScript = existing as GDScript
		if not code.is_empty():
			gd_scr.source_code = code
		gd_scr.reload(true)
		return gd_scr
	var fallback: Variant = ResourceLoader.load(rpath, "Script", ResourceLoader.CACHE_MODE_REPLACE)
	return fallback as Script if fallback is Script else null


func sanitize_null_script_exports(scene_root: Node) -> int:
	if scene_root == null:
		return 0
	var fixed := 0
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		var scr: Variant = cur.get_script()
		if scr is Script:
			var sc_obj: Script = scr as Script
			for p_raw in sc_obj.get_script_property_list():
				var p_info: Dictionary = p_raw
				var pname := String(p_info.get("name", ""))
				if pname.is_empty():
					continue
				var pusage := int(p_info.get("usage", 0))
				if (pusage & PROPERTY_USAGE_STORAGE) == 0:
					continue
				var ptype := int(p_info.get("type", TYPE_NIL))
				if not (
					ptype == TYPE_BOOL or ptype == TYPE_INT or ptype == TYPE_FLOAT or
					ptype == TYPE_STRING or ptype == TYPE_NODE_PATH or
					ptype == TYPE_VECTOR2 or ptype == TYPE_VECTOR2I or
					ptype == TYPE_VECTOR3 or ptype == TYPE_VECTOR3I or ptype == TYPE_COLOR
				):
					continue
				if cur.get(pname) == null:
					var restored: Variant = sc_obj.get_property_default_value(pname)
					if restored == null:
						match ptype:
							TYPE_BOOL:
								restored = false
							TYPE_INT:
								restored = 0
							TYPE_FLOAT:
								restored = 0.0
							TYPE_STRING:
								restored = ""
							TYPE_NODE_PATH:
								restored = NodePath("")
							TYPE_VECTOR2:
								restored = Vector2.ZERO
							TYPE_VECTOR2I:
								restored = Vector2i.ZERO
							TYPE_VECTOR3:
								restored = Vector3.ZERO
							TYPE_VECTOR3I:
								restored = Vector3i.ZERO
							TYPE_COLOR:
								restored = Color.WHITE
					cur.set(pname, restored)
					fixed += 1
		for ch in cur.get_children():
			stack.append(ch)
	return fixed


func _project_prefers_2d(arena_hint: String = "", dimension_hint: String = "") -> bool:
	var dim := dimension_hint.strip_edges().to_lower()
	if dim == "dim2d" or dim == "2d":
		return true
	if dim == "dim3d" or dim == "3d":
		return false
	var candidates := PackedStringArray()
	var main_sc := String(ProjectSettings.get_setting("application/run/main_scene", "")).strip_edges()
	if not main_sc.is_empty():
		candidates.append(main_sc)
	if not arena_hint.is_empty():
		candidates.append(arena_hint)
	for c in candidates:
		if FileAccess.file_exists(c):
			var fa := FileAccess.open(c, FileAccess.READ)
			if fa != null:
				var head := fa.get_as_text().left(400)
				fa.close()
				if "type=\"Node2D\"" in head or "type=\"CharacterBody2D\"" in head or "type=\"Control\"" in head:
					if not ("type=\"Node3D\"" in head or "type=\"CharacterBody3D\"" in head):
						return true
	return false


func infer_scene_root_type(scene_path: String, root_type_hint: String = "", arena_hint: String = "", dimension_hint: String = "") -> String:
	var hint := root_type_hint.strip_edges()
	if not hint.is_empty() and ClassDB.class_exists(hint) and ClassDB.can_instantiate(hint) and ClassDB.is_parent_class(hint, "Node"):
		return hint
	var lower_file := scene_path.get_file().get_basename().to_lower()
	if "panel" in lower_file or "hud" in lower_file or "menu" in lower_file or "overlay" in lower_file or "draft" in lower_file or "dialog" in lower_file or "shop" in lower_file or "modal" in lower_file or lower_file.ends_with("_ui") or lower_file.begins_with("ui_"):
		return "CanvasLayer"
	var is_2d := _project_prefers_2d(arena_hint, dimension_hint)
	if "player" in lower_file or "enemy" in lower_file or "crab" in lower_file or "boss" in lower_file or "mob" in lower_file or "npc" in lower_file:
		return "CharacterBody2D" if is_2d else "CharacterBody3D"
	return "Node2D" if is_2d else "Node3D"


func _should_upgrade_root_type(cur_root: Node, desired_type: String) -> bool:
	if cur_root == null or desired_type.is_empty():
		return false
	if not ClassDB.class_exists(desired_type) or not ClassDB.can_instantiate(desired_type) or not ClassDB.is_parent_class(desired_type, "Node"):
		return false
	var cur_cls := cur_root.get_class()
	if cur_cls == desired_type or ClassDB.is_parent_class(cur_cls, desired_type):
		return false
	if cur_cls == "Node" or cur_cls == "Node3D" or cur_cls == "Node2D":
		return true
	if (desired_type == "CanvasLayer" or desired_type == "Control") and (cur_root is Node3D):
		return true
	return false


func _clear_owner_for_root(node: Node, target_owner: Node) -> void:
	for ch in node.get_children():
		if ch.owner == target_owner:
			ch.owner = null
		_clear_owner_for_root(ch, target_owner)


func _unset_subtree_owners(node: Node) -> void:
	if node == null:
		return
	node.owner = null
	for ch in node.get_children():
		_unset_subtree_owners(ch)


func _reown_subtree(node: Node, old_owner: Node, new_owner: Node) -> void:
	for ch in node.get_children():
		if ch.owner == null or ch.owner == old_owner:
			ch.owner = new_owner
		_reown_subtree(ch, old_owner, new_owner)


func upgrade_scene_root_type_on_disk(
	scene_path: String,
	desired_type: String,
	editor_interface: EditorInterface = null
) -> bool:
	if not scene_path.ends_with(".tscn") or not FileAccess.file_exists(scene_path):
		return false
	var ps := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if ps == null:
		return false
	var old_root := ps.instantiate()
	if old_root == null:
		return false
	if not _should_upgrade_root_type(old_root, desired_type):
		old_root.free()
		return false
	var new_root := ClassDB.instantiate(desired_type) as Node
	if new_root == null:
		old_root.free()
		return false
	new_root.name = old_root.name
	if old_root is Node3D and new_root is Node3D:
		(new_root as Node3D).transform = (old_root as Node3D).transform
	elif old_root is Node2D and new_root is Node2D:
		(new_root as Node2D).transform = (old_root as Node2D).transform
	for grp in old_root.get_groups():
		var gs := String(grp)
		if not gs.begins_with("_"):
			new_root.add_to_group(gs, true)
	var old_scr: Variant = old_root.get_script()
	if old_scr is Script:
		var scr_path := String((old_scr as Script).resource_path)
		if not scr_path.is_empty() and can_attach_script_to_node(new_root, scr_path):
			new_root.set_script(old_scr)
	_clear_owner_for_root(old_root, old_root)
	var children := old_root.get_children()
	for ch in children:
		old_root.remove_child(ch)
		new_root.add_child(ch)
	_reown_subtree(new_root, old_root, new_root)
	var packed := PackedScene.new()
	var saved_ok := false
	if packed.pack(new_root) == OK:
		_ensure_dir_for_res_path(scene_path)
		if ResourceSaver.save(packed, scene_path) == OK:
			saved_ok = true
	old_root.free()
	new_root.free()
	if saved_ok:
		invalidate_eval_cache()
		if editor_interface != null:
			var ed_root := editor_interface.get_edited_scene_root()
			if ed_root != null and ed_root.scene_file_path == scene_path:
				if editor_interface.has_method("reload_scene_from_path"):
					editor_interface.call("reload_scene_from_path", scene_path)
				else:
					editor_interface.open_scene_from_path(scene_path)
	return saved_ok


func ensure_scene_exists_and_open(
	editor_interface: EditorInterface,
	scene_path: String,
	root_type_hint: String = "",
	root_name_hint: String = "",
	arena_hint: String = "",
	dimension_hint: String = ""
) -> Node:
	if scene_path.ends_with(".tscn"):
		if not FileAccess.file_exists(scene_path):
			var rnode := _load_or_create_disk_scene_root(scene_path, root_type_hint, root_name_hint, arena_hint, dimension_hint)
			if rnode != null:
				_save_disk_scene_root(rnode, scene_path)
				rnode.free()
				invalidate_eval_cache()
		elif not root_type_hint.strip_edges().is_empty():
			upgrade_scene_root_type_on_disk(scene_path, root_type_hint.strip_edges(), editor_interface)
	if editor_interface != null:
		if scene_path.ends_with(".tscn") and FileAccess.file_exists(scene_path):
			var cur: Node = editor_interface.get_edited_scene_root()
			if cur == null or cur.scene_file_path != scene_path:
				editor_interface.open_scene_from_path(scene_path)
		return editor_interface.get_edited_scene_root()
	return null


func ensure_main_scene_configured(arena_scene: String, fallback_scene: String = "") -> bool:
	var cur_main := String(ProjectSettings.get_setting("application/run/main_scene", "")).strip_edges()
	var resolved_exists := false
	if not cur_main.is_empty():
		if FileAccess.file_exists(cur_main) or ResourceLoader.exists(cur_main):
			resolved_exists = true
	if resolved_exists:
		return false
	var chosen := ""
	if not arena_scene.is_empty() and FileAccess.file_exists(arena_scene):
		chosen = arena_scene
	elif not fallback_scene.is_empty() and FileAccess.file_exists(fallback_scene):
		chosen = fallback_scene
	if chosen.is_empty():
		return false
	ProjectSettings.set_setting("application/run/main_scene", chosen)
	ProjectSettings.save()
	return true


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


func _is_abstract_subresource_class(cls_name: String) -> bool:
	return cls_name in PackedStringArray([
		"Shape3D", "Shape2D", "Mesh", "Material", "Texture", "Texture2D", "Resource"
	])


func _apply_material_dict_to_node(node: Node, mat_props: Dictionary) -> bool:
	if node == null or mat_props.is_empty():
		return false
	if node is CanvasItem:
		var ci := node as CanvasItem
		var col_val: Variant = mat_props.get("color", mat_props.get("albedo_color", mat_props.get("modulate", null)))
		if col_val != null:
			var c: Variant = _coerce_prop_value(col_val, "color")
			if c is Color:
				if node is ColorRect or node is Polygon2D:
					node.set("color", c)
				else:
					ci.modulate = c
				return true
		return false
	if node is CSGShape3D:
		var cs := node as CSGShape3D
		var cmat := cs.material as StandardMaterial3D
		var cchanged := false
		if cmat == null or not cmat.resource_path.is_empty():
			cmat = (cmat.duplicate() as StandardMaterial3D) if cmat != null else StandardMaterial3D.new()
			cmat.resource_path = ""
			cs.material = cmat
			cchanged = true
		for k in mat_props.keys():
			var val: Variant = _coerce_prop_value(mat_props[k], String(k))
			if typeof(cmat.get(k)) != typeof(val) or cmat.get(k) != val:
				cmat.set(k, val)
				cchanged = true
		return cchanged
	if not (node is GeometryInstance3D):
		return false
	var gi := node as GeometryInstance3D
	var mat := gi.material_override as StandardMaterial3D
	var changed := false
	if mat == null or not mat.resource_path.is_empty():
		mat = (mat.duplicate() as StandardMaterial3D) if mat != null else StandardMaterial3D.new()
		mat.resource_path = ""
		gi.material_override = mat
		changed = true
	for k in mat_props.keys():
		var val: Variant = _coerce_prop_value(mat_props[k], String(k))
		if typeof(mat.get(k)) != typeof(val) or mat.get(k) != val:
			mat.set(k, val)
			changed = true
	return changed


func _coerce_prop_value(val: Variant, prop_name: String = "") -> Variant:
	if typeof(val) == TYPE_DICTIONARY:
		if val.has("r") and val.has("g") and val.has("b"):
			return Color(float(val.get("r", 1.0)), float(val.get("g", 1.0)), float(val.get("b", 1.0)), float(val.get("a", 1.0)))
		if val.has("x") and val.has("y") and val.has("z"):
			return Vector3(float(val.get("x", 0.0)), float(val.get("y", 0.0)), float(val.get("z", 0.0)))
		if val.has("x") and val.has("y"):
			return Vector2(float(val.get("x", 0.0)), float(val.get("y", 0.0)))
	if typeof(val) == TYPE_STRING:
		var s := String(val).strip_edges()
		if prop_name.to_lower().ends_with("path") and s.begins_with("res://"):
			return s
		if s.begins_with("res://") and ResourceLoader.exists(s):
			return ResourceLoader.load(s, "", ResourceLoader.CACHE_MODE_REUSE)
		if s.begins_with("#") and (s.length() == 7 or s.length() == 9):
			return Color.from_string(s, Color.WHITE)
		var v3 := _parse_vector3_literal(s)
		if typeof(v3) == TYPE_VECTOR3:
			return v3
		var v2 := _parse_vector2_literal(s)
		if typeof(v2) == TYPE_VECTOR2:
			return v2
		var sl := s.to_lower()
		if sl == "true":
			return true
		if sl == "false":
			return false
		if s.is_valid_int():
			return s.to_int()
		if s.is_valid_float():
			return s.to_float()
	if (prop_name == "size" or prop_name == "position" or prop_name == "rotation_degrees" or prop_name == "rotation" or prop_name == "scale" or prop_name == "target_position" or prop_name == "global_position") and typeof(val) == TYPE_ARRAY:
		var arr: Array = val
		if arr.size() == 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
		if arr.size() == 2:
			return Vector2(float(arr[0]), float(arr[1]))
	if (prop_name == "color" or prop_name == "albedo_color" or prop_name == "emission" or prop_name == "modulate" or prop_name == "self_modulate") and typeof(val) == TYPE_ARRAY:
		var carr: Array = val
		if carr.size() >= 3:
			return Color(float(carr[0]), float(carr[1]), float(carr[2]), float(carr[3]) if carr.size() >= 4 else 1.0)
	return val


func _is_physics_or_rig_node(node: Node, node_type_hint: String = "", node_name_hint: String = "") -> bool:
	var cls: String = node.get_class() if node != null else node_type_hint.strip_edges()
	var nm: String = (String(node.name) if node != null else node_name_hint).to_lower()
	for phys_cls in ["Area3D", "Area2D", "CollisionShape3D", "CollisionShape2D", "CollisionPolygon3D", "CollisionPolygon2D", "RayCast3D", "RayCast2D", "ShapeCast3D", "ShapeCast2D", "Marker3D", "Marker2D"]:
		if cls == phys_cls:
			return true
	for tok in ["pivot", "hitbox", "hurtbox", "strike", "attack", "muzzle", "spawn", "collider"]:
		if tok in nm:
			return true
	return false


func _has_custom_asset_resource(res: Variant) -> bool:
	if res is Resource:
		var rp: String = (res as Resource).resource_path.strip_edges().to_lower()
		return rp.begins_with("res://")
	return false


func _is_instanced_scene_node(scene_root: Node, node: Node) -> bool:
	if node == null or node == scene_root:
		return false
	var cur: Node = node
	while cur != null and cur != scene_root:
		if not cur.scene_file_path.strip_edges().is_empty():
			return true
		cur = cur.get_parent()
	return false


func _is_internal_instanced_child(scene_root: Node, node: Node) -> bool:
	if node == null or node == scene_root:
		return false
	var cur: Node = node.get_parent()
	while cur != null and cur != scene_root:
		if not cur.scene_file_path.strip_edges().is_empty():
			return true
		cur = cur.get_parent()
	return false


func _is_hand_tuned_collision_prop(node: Node, prop_name: String) -> bool:
	if node == null or (prop_name != "collision_layer" and prop_name != "collision_mask"):
		return false
	if not (prop_name in node):
		return false
	return int(node.get(prop_name)) != 1


func _sync_existing_node_from_spec(
	node: Node,
	sp: Dictionary,
	preserve_existing_visuals: bool = false
) -> bool:
	if node == null:
		return false
	var changed := false
	var sr_cls := String(sp.get("subResourceClass", ""))
	var sr_props: Dictionary = sp.get("subResourceProps", {})
	if not sr_cls.is_empty() and ClassDB.class_exists(sr_cls) and not _is_abstract_subresource_class(sr_cls):
		if node is CollisionShape3D or node is CollisionShape2D:
			var cur_shape: Variant = node.get("shape")
			if cur_shape == null or cur_shape.get_class() != sr_cls:
				var new_shape: Variant = ClassDB.instantiate(sr_cls)
				if new_shape != null:
					for k in sr_props.keys():
						new_shape.set(k, _coerce_prop_value(sr_props[k], String(k)))
					node.set("shape", new_shape)
					changed = true
			elif not sr_props.is_empty():
				var dup_shape: Resource = (cur_shape as Resource).duplicate()
				var shape_dirty := false
				for k in sr_props.keys():
					var cv: Variant = _coerce_prop_value(sr_props[k], String(k))
					if dup_shape.get(k) != cv:
						dup_shape.set(k, cv)
						shape_dirty = true
				if shape_dirty:
					node.set("shape", dup_shape)
					changed = true
		elif node is MeshInstance3D:
			var cur_mesh: Variant = node.get("mesh")
			if not (preserve_existing_visuals and cur_mesh != null):
				if cur_mesh == null or cur_mesh.get_class() != sr_cls:
					var new_mesh: Variant = ClassDB.instantiate(sr_cls)
					if new_mesh != null:
						for k in sr_props.keys():
							new_mesh.set(k, _coerce_prop_value(sr_props[k], String(k)))
						node.set("mesh", new_mesh)
						changed = true
				elif not sr_props.is_empty():
					for k in sr_props.keys():
						var cv: Variant = _coerce_prop_value(sr_props[k], String(k))
						if cur_mesh.get(k) != cv:
							cur_mesh.set(k, cv)
							changed = true

	var mat_props: Dictionary = sp.get("materialProps", {})
	if not mat_props.is_empty():
		var skip_mat := false
		if preserve_existing_visuals:
			if node is GeometryInstance3D and (node as GeometryInstance3D).material_override != null:
				skip_mat = true
			elif node is CSGShape3D and node.get("material") != null:
				skip_mat = true
		if not skip_mat and _apply_material_dict_to_node(node, mat_props):
			changed = true

	var visual_transform_keys: Array[String] = [
		"position",
		"rotation",
		"rotation_degrees",
		"scale",
		"transform",
		"global_position",
		"global_transform",
		"global_rotation",
	]
	var props: Dictionary = sp.get("props", {})
	for pk in props.keys():
		var pk_str := String(pk)
		var pv: Variant = _coerce_prop_value(props[pk], pk_str)
		if preserve_existing_visuals:
			if (pk_str in visual_transform_keys) and not _is_physics_or_rig_node(node):
				continue
			if pk_str == "mesh" and node is MeshInstance3D and (_has_custom_asset_resource(node.get("mesh")) or node.get("mesh") != null):
				continue
			if (node is Sprite2D or node is Sprite3D) and pk_str == "texture" and node.get("texture") != null:
				continue
			if pk_str == "material_override" and node is GeometryInstance3D and (node as GeometryInstance3D).material_override != null:
				continue
			if pk_str == "material" and node is CSGShape3D and node.get("material") != null:
				continue
			if _is_hand_tuned_collision_prop(node, pk_str) and int(pv) != int(node.get(pk_str)):
				continue
		if node.get(pk) != pv:
			node.set(pk, pv)
			changed = true
	return changed


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


func can_attach_script_to_node(node: Node, code_or_res_path: String) -> bool:
	if node == null:
		return false
	var code := code_or_res_path
	if code.begins_with("res://"):
		if not FileAccess.file_exists(code):
			return true
		var f := FileAccess.open(code, FileAccess.READ)
		if f == null:
			return true
		code = f.get_as_text()
		f.close()
	var req_cls := extract_script_extends(code)
	if req_cls.is_empty():
		return true
	var node_cls := node.get_class()
	if node_cls == req_cls:
		return true
	if ClassDB.class_exists(node_cls) and ClassDB.class_exists(req_cls):
		return ClassDB.is_parent_class(node_cls, req_cls)
	return false


func detach_incompatible_scripts(scene_root: Node) -> PackedStringArray:
	var detached := PackedStringArray()
	if scene_root == null:
		return detached
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		var scr: Variant = cur.get_script()
		if scr == null:
			scr = cur.get("script")
		if scr is Script:
			var spath := String((scr as Script).resource_path)
			var code := String((scr as Script).source_code)
			if code.is_empty() and not spath.is_empty() and FileAccess.file_exists(spath):
				var f := FileAccess.open(spath, FileAccess.READ)
				if f != null:
					code = f.get_as_text()
					f.close()
			if not code.is_empty() and not can_attach_script_to_node(cur, code):
				cur.set_script(null)
				cur.set("script", null)
				detached.append("%s (%s)" % [cur.name, spath.get_file()])
		for ch in cur.get_children():
			stack.append(ch)
	return detached


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


func _script_defines_method(node: Node, method_name: String) -> bool:
	if node == null or method_name.is_empty():
		return false
	if node.has_method(method_name):
		return true
	var scr: Variant = node.get_script()
	if scr is Script:
		var src := String((scr as Script).source_code)
		if src.is_empty() and not String((scr as Script).resource_path).is_empty():
			var f := FileAccess.open(String((scr as Script).resource_path), FileAccess.READ)
			if f != null:
				src = f.get_as_text()
				f.close()
		if ("func %s(" % method_name) in src:
			return true
	return false


func _split_top_level_csv(raw: String) -> PackedStringArray:
	var out := PackedStringArray()
	var buf: String = ""
	var depth: int = 0
	for ch_idx in range(raw.length()):
		var c: String = raw[ch_idx]
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth = maxi(0, depth - 1)
		if c == "," and depth == 0:
			var part: String = buf.strip_edges()
			if not part.is_empty():
				out.append(part)
			buf = ""
		else:
			buf += c
	var tail: String = buf.strip_edges()
	if not tail.is_empty():
		out.append(tail)
	return out


func _read_node_script_source(node: Node) -> String:
	if node == null:
		return ""
	var scr: Variant = node.get_script()
	if not (scr is Script):
		return ""
	var src: String = String((scr as Script).source_code)
	var rpath: String = String((scr as Script).resource_path)
	if src.is_empty() and not rpath.is_empty() and FileAccess.file_exists(rpath):
		var fa := FileAccess.open(rpath, FileAccess.READ)
		if fa != null:
			src = fa.get_as_text()
			fa.close()
	return src


func _extract_balanced_paren_inner(src: String, start_after_open_paren: int) -> String:
	var depth: int = 1
	var end_pos: int = start_after_open_paren
	while end_pos < src.length() and depth > 0:
		var c: String = src[end_pos]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth == 0:
				return src.substr(start_after_open_paren, end_pos - start_after_open_paren)
		end_pos += 1
	return ""


func _get_signal_arity(src_node: Node, sig_name: String) -> int:
	if src_node == null or sig_name.is_empty():
		return -1
	var src: String = _read_node_script_source(src_node)
	if not src.is_empty():
		var sig_re := RegEx.new()
		sig_re.compile("(?m)^\\s*signal\\s+%s\\s*(\\()?" % sig_name)
		var m: RegExMatch = sig_re.search(src)
		if m != null:
			if m.get_string(1) == "(":
				var inner: String = _extract_balanced_paren_inner(src, m.get_end()).strip_edges()
				return 0 if inner.is_empty() else _split_top_level_csv(inner).size()
			return 0
	for s_raw in src_node.get_signal_list():
		var s_dict: Dictionary = s_raw
		if String(s_dict.get("name", "")) == sig_name:
			var args_raw: Variant = s_dict.get("args", [])
			if typeof(args_raw) == TYPE_ARRAY:
				return (args_raw as Array).size()
	return -1


func _get_method_arity_range(tgt_node: Node, method_name: String) -> Vector2i:
	if tgt_node == null or method_name.is_empty():
		return Vector2i(-1, -1)
	var src: String = _read_node_script_source(tgt_node)
	if not src.is_empty():
		var fn_re := RegEx.new()
		fn_re.compile("(?m)^\\s*(?:static\\s+)?func\\s+%s\\s*\\(" % method_name)
		var m: RegExMatch = fn_re.search(src)
		if m != null:
			var inner: String = _extract_balanced_paren_inner(src, m.get_end()).strip_edges()
			if inner.is_empty():
				return Vector2i(0, 0)
			var params: PackedStringArray = _split_top_level_csv(inner)
			var min_args: int = 0
			for p in params:
				if not ("=" in p):
					min_args += 1
			return Vector2i(min_args, params.size())
	for m_raw in tgt_node.get_method_list():
		var m_dict: Dictionary = m_raw
		if String(m_dict.get("name", "")) == method_name:
			var args_raw: Variant = m_dict.get("args", [])
			var def_raw: Variant = m_dict.get("default_args", [])
			var max_a: int = (args_raw as Array).size() if typeof(args_raw) == TYPE_ARRAY else 0
			var def_a: int = (def_raw as Array).size() if typeof(def_raw) == TYPE_ARRAY else 0
			return Vector2i(maxi(0, max_a - def_a), max_a)
	return Vector2i(-1, -1)


func _resolve_signal_receiver_node(scene_root: Node, src_node: Node, target_hint: String, method_name: String) -> Node:
	if scene_root == null or method_name.is_empty():
		return null
	var clean_hint: String = target_hint.strip_edges()
	if not clean_hint.is_empty() and clean_hint != ".":
		var hinted: Node = _resolve_node_by_rel_path(scene_root, clean_hint)
		if hinted == null:
			hinted = _find_node_recursive(scene_root, clean_hint)
		if hinted == null and clean_hint == scene_root.name:
			hinted = scene_root
		if hinted == null:
			return null
		if hinted == src_node and not _script_defines_method(hinted, method_name):
			return null
		if _script_defines_method(hinted, method_name) or ClassDB.class_has_method(hinted.get_class(), method_name):
			return hinted
		return null
	if _script_defines_method(scene_root, method_name):
		return scene_root
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur != src_node and _script_defines_method(cur, method_name):
			return cur
		for ch in cur.get_children():
			stack.append(ch)
	return null


func _disconnect_invalid_self_signal(src_node: Node, sig_name: String, method_name: String) -> bool:
	if src_node == null or not src_node.has_signal(sig_name):
		return false
	var removed := false
	for conn in src_node.get_signal_connection_list(sig_name):
		var cdict: Dictionary = conn
		var cb: Callable = cdict.get("callable", Callable())
		var tgt: Object = cb.get_object()
		var cb_method := String(cb.get_method())
		if tgt == src_node and cb_method == method_name and (not cb.is_valid() or not _script_defines_method(src_node, method_name)):
			src_node.disconnect(sig_name, cb)
			removed = true
	return removed


func _connect_single_signal_safe(
	scene_root: Node,
	src_hint: String,
	sig_name: String,
	target_hint: String,
	method_name: String
) -> Dictionary:
	if scene_root == null or sig_name.is_empty() or method_name.is_empty():
		return { "ok": false, "reason": "Missing signal parameters." }
	var src_node: Node = _resolve_node_by_rel_path(scene_root, src_hint)
	if src_node == null:
		src_node = _find_node_recursive(scene_root, src_hint)
	if src_node == null and (src_hint.is_empty() or src_hint == "." or src_hint == scene_root.name):
		src_node = scene_root
	if src_node == null or not src_node.has_signal(sig_name):
		return { "ok": false, "reason": "Signal source %s.%s not found." % [src_hint, sig_name] }

	_disconnect_invalid_self_signal(src_node, sig_name, method_name)

	var tgt_node := _resolve_signal_receiver_node(scene_root, src_node, target_hint, method_name)
	if tgt_node == null:
		return { "ok": false, "reason": "Signal receiver not found for %s." % method_name }
	if not _script_defines_method(tgt_node, method_name) and not ClassDB.class_has_method(tgt_node.get_class(), method_name):
		return { "ok": false, "reason": "%s does not define method %s." % [tgt_node.name, method_name] }

	var sig_arity: int = _get_signal_arity(src_node, sig_name)
	var arity_range: Vector2i = _get_method_arity_range(tgt_node, method_name)
	var unbind_count: int = 0
	if sig_arity >= 0 and arity_range.x >= 0:
		if sig_arity < arity_range.x:
			return { "ok": false, "reason": "Signal %s.%s passes %d arg(s) but %s.%s requires %d." % [src_node.name, sig_name, sig_arity, tgt_node.name, method_name, arity_range.x] }
		if sig_arity > arity_range.y:
			unbind_count = sig_arity - arity_range.y

	var base_cb := Callable(tgt_node, method_name)
	var cb: Callable = base_cb.unbind(unbind_count) if unbind_count > 0 else base_cb
	if src_node.is_connected(sig_name, cb):
		return { "ok": true, "changed": false, "detail": "%s.%s -> %s.%s" % [src_node.name, sig_name, tgt_node.name, method_name] }
	for conn_raw in src_node.get_signal_connection_list(sig_name):
		var conn: Dictionary = conn_raw
		var old_cb: Callable = conn.get("callable", Callable())
		var old_method: String = String(old_cb.get_method())
		if old_cb.get_object() == tgt_node and (old_method == method_name or (("::" + method_name) in str(old_cb))):
			src_node.disconnect(sig_name, old_cb)
	var err := src_node.connect(sig_name, cb, Object.CONNECT_PERSIST)
	if err != OK:
		return { "ok": false, "reason": "Connect %s.%s failed (%d)." % [src_node.name, sig_name, err] }
	return { "ok": true, "changed": true, "detail": "%s.%s -> %s.%s" % [src_node.name, sig_name, tgt_node.name, method_name] }


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


func capture_bundle_snapshot(
	editor_interface: EditorInterface,
	bundle: Dictionary,
	preferred_scene: String = ""
) -> Dictionary:
	var candidate_paths := {"res://project.godot": true}
	var initial_open_scene := ""
	if editor_interface != null and editor_interface.get_edited_scene_root() != null:
		initial_open_scene = String(editor_interface.get_edited_scene_root().scene_file_path).strip_edges()
		if initial_open_scene.begins_with("res://"):
			candidate_paths[initial_open_scene] = true
			if FileAccess.file_exists(initial_open_scene) and editor_interface.has_method("save_scene"):
				editor_interface.call("save_scene")
	for p_raw in [preferred_scene, bundle.get("arenaScenePath", ""), bundle.get("epicScenePath", ""), bundle.get("featureScenePath", "")]:
		var ps_str := String(p_raw).strip_edges()
		if ps_str.begins_with("res://"):
			candidate_paths[ps_str] = true
	var raw_su: Variant = bundle.get("scriptUpdates", [])
	if typeof(raw_su) == TYPE_ARRAY:
		for item in (raw_su as Array):
			if typeof(item) == TYPE_DICTIONARY:
				var d: Dictionary = item
				for k in ["resPath", "scenePath"]:
					var vp := String(d.get(k, "")).strip_edges()
					if vp.begins_with("res://"):
						candidate_paths[vp] = true
	var raw_ops: Variant = bundle.get("sceneOps", [])
	if typeof(raw_ops) == TYPE_ARRAY:
		for op_raw in (raw_ops as Array):
			if typeof(op_raw) == TYPE_DICTIONARY:
				var opd: Dictionary = op_raw
				for k in ["scenePath", "scriptPath", "instancePath"]:
					var vp := String(opd.get(k, "")).strip_edges()
					if vp.begins_with("res://"):
						candidate_paths[vp] = true

	var open_buffers := collect_open_script_editor_buffers(editor_interface)
	var files := {}
	for rp_raw in candidate_paths.keys():
		var rp := String(rp_raw).strip_edges()
		if not rp.begins_with("res://"):
			continue
		if open_buffers.has(rp):
			files[rp] = {"existed": FileAccess.file_exists(rp), "content": String(open_buffers[rp])}
		elif FileAccess.file_exists(rp):
			files[rp] = {"existed": true, "content": FileAccess.get_file_as_string(rp)}
		else:
			files[rp] = {"existed": false, "content": ""}

	var input_actions := {}
	for act_sn in InputMap.get_actions():
		var act_name := String(act_sn)
		if not act_name.begins_with("ui_"):
			input_actions[act_name] = InputMap.action_get_events(act_sn).duplicate()

	var project_inputs := {}
	for p_raw in ProjectSettings.get_property_list():
		if typeof(p_raw) != TYPE_DICTIONARY:
			continue
		var pname := String((p_raw as Dictionary).get("name", ""))
		if not pname.begins_with("input/") or pname.begins_with("input/ui_"):
			continue
		var pval: Variant = ProjectSettings.get_setting(pname)
		project_inputs[pname] = pval.duplicate(true) if typeof(pval) == TYPE_DICTIONARY else pval

	var prev_main_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	return {
		"files": files,
		"input_actions": input_actions,
		"project_inputs": project_inputs,
		"initial_open_scene": initial_open_scene,
		"prev_main_scene": prev_main_scene,
	}


func restore_bundle_snapshot(
	editor_interface: EditorInterface,
	snapshot: Dictionary
) -> Dictionary:
	if snapshot.is_empty():
		return {"ok": false, "restored_count": 0, "restored_scripts": PackedStringArray(), "removed_scripts": PackedStringArray()}

	var files: Dictionary = snapshot.get("files", {}) if typeof(snapshot.get("files", null)) == TYPE_DICTIONARY else {}
	var ordered_paths := PackedStringArray()
	var scene_tail := PackedStringArray()
	var other_tail := PackedStringArray()
	var has_project_cfg := false
	for rp_raw in files.keys():
		var rp := String(rp_raw).strip_edges()
		if rp == "res://project.godot":
			has_project_cfg = true
		elif rp.ends_with(".gd"):
			ordered_paths.append(rp)
		elif rp.ends_with(".tscn"):
			scene_tail.append(rp)
		else:
			other_tail.append(rp)
	for rp in scene_tail:
		ordered_paths.append(rp)
	for rp in other_tail:
		ordered_paths.append(rp)

	var restored_count := 0
	var restored_scenes := PackedStringArray()
	var removed_scenes := PackedStringArray()
	var restored_scripts := PackedStringArray()
	var removed_scripts := PackedStringArray()
	for rp in ordered_paths:
		var raw_entry: Variant = files.get(rp, null)
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		if bool(entry.get("existed", false)):
			_ensure_dir_for_res_path(rp)
			var content := String(entry.get("content", ""))
			var fw := FileAccess.open(rp, FileAccess.WRITE)
			if fw != null:
				fw.store_string(content)
				fw.close()
				restored_count += 1
				if rp.ends_with(".gd"):
					reload_script_safely(rp, content)
					_sync_open_script_editor_after_disk_write(editor_interface, rp, content)
					restored_scripts.append(rp)
				elif rp.ends_with(".tscn"):
					restored_scenes.append(rp)
		else:
			if rp.ends_with(".gd") and not (rp in removed_scripts):
				removed_scripts.append(rp)
			if FileAccess.file_exists(rp):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(rp))
				restored_count += 1
				if rp.ends_with(".tscn"):
					removed_scenes.append(rp)

	var saved_inputs: Dictionary = snapshot.get("input_actions", {}) if typeof(snapshot.get("input_actions", null)) == TYPE_DICTIONARY else {}
	var saved_proj_inputs: Dictionary = snapshot.get("project_inputs", {}) if typeof(snapshot.get("project_inputs", null)) == TYPE_DICTIONARY else {}
	var proj_inputs_to_clear := PackedStringArray()
	for p_raw in ProjectSettings.get_property_list():
		if typeof(p_raw) != TYPE_DICTIONARY:
			continue
		var pname := String((p_raw as Dictionary).get("name", ""))
		if not pname.begins_with("input/") or pname.begins_with("input/ui_"):
			continue
		var act_suffix := pname.substr("input/".length())
		if not saved_proj_inputs.has(pname) and not saved_inputs.has(act_suffix):
			proj_inputs_to_clear.append(pname)
	for pname in proj_inputs_to_clear:
		ProjectSettings.set_setting(pname, null)
	for pk_raw in saved_proj_inputs.keys():
		var pk := String(pk_raw)
		var pv: Variant = saved_proj_inputs[pk_raw]
		ProjectSettings.set_setting(pk, pv.duplicate(true) if typeof(pv) == TYPE_DICTIONARY else pv)

	var to_erase := PackedStringArray()
	for act_sn in InputMap.get_actions():
		var act_name := String(act_sn)
		if not act_name.begins_with("ui_") and not saved_inputs.has(act_name):
			to_erase.append(act_name)
	for act_name in to_erase:
		InputMap.erase_action(StringName(act_name))
	for act_raw in saved_inputs.keys():
		var act_name := String(act_raw)
		var act_sn := StringName(act_name)
		if not InputMap.has_action(act_sn):
			InputMap.add_action(act_sn)
		InputMap.action_erase_events(act_sn)
		var ev_list_raw: Variant = saved_inputs[act_raw]
		if typeof(ev_list_raw) == TYPE_ARRAY:
			for ev in (ev_list_raw as Array):
				if ev is InputEvent:
					InputMap.action_add_event(act_sn, ev)

	var prev_main_scene := String(snapshot.get("prev_main_scene", "")).strip_edges()
	ProjectSettings.set_setting("application/run/main_scene", prev_main_scene)
	ProjectSettings.save()
	InputMap.load_from_project_settings()

	if has_project_cfg:
		var proj_entry_raw: Variant = files.get("res://project.godot", null)
		if typeof(proj_entry_raw) == TYPE_DICTIONARY and bool((proj_entry_raw as Dictionary).get("existed", false)):
			var proj_fw := FileAccess.open("res://project.godot", FileAccess.WRITE)
			if proj_fw != null:
				proj_fw.store_string(String((proj_entry_raw as Dictionary).get("content", "")))
				proj_fw.close()
				restored_count += 1

	if editor_interface != null:
		if not restored_scripts.is_empty():
			_reload_open_script_editors(editor_interface)
		if editor_interface.get_resource_filesystem() != null:
			editor_interface.get_resource_filesystem().scan()
		for sc in restored_scenes:
			if FileAccess.file_exists(sc) and editor_interface.has_method("reload_scene_from_path"):
				editor_interface.call("reload_scene_from_path", sc)
		var init_sc := String(snapshot.get("initial_open_scene", "")).strip_edges()
		if not init_sc.is_empty() and FileAccess.file_exists(init_sc):
			editor_interface.open_scene_from_path(init_sc)
		else:
			var cur_ed := editor_interface.get_edited_scene_root()
			if cur_ed != null and (cur_ed.scene_file_path in removed_scenes) and not prev_main_scene.is_empty() and FileAccess.file_exists(prev_main_scene):
				editor_interface.open_scene_from_path(prev_main_scene)

	invalidate_eval_cache()
	return {"ok": true, "restored_count": restored_count, "restored_scripts": restored_scripts, "removed_scripts": removed_scripts}


func _leading_indent(line: String) -> String:
	var idx: int = 0
	var line_len: int = line.length()
	while idx < line_len:
		var ch: String = line.substr(idx, 1)
		if ch != "\t" and ch != " ":
			break
		idx += 1
	return line.substr(0, idx)


func _reindent_patch_line(line: String, find_base: String, target_base: String, space_unit: int) -> String:
	if line.strip_edges().is_empty():
		return ""
	var rel: String = line
	if not find_base.is_empty() and line.begins_with(find_base):
		rel = line.substr(find_base.length())
	elif not target_base.is_empty() and target_base != find_base:
		var line_ws: String = _leading_indent(line)
		var common_len: int = mini(line_ws.length(), find_base.length())
		rel = line.substr(common_len)
	if not target_base.is_empty() and target_base.begins_with("\t"):
		var rel_ws: String = _leading_indent(rel)
		if rel_ws.begins_with(" "):
			var unit: int = maxi(space_unit, 2)
			var tab_cnt: int = int(ceil(float(rel_ws.length()) / float(unit)))
			rel = "\t".repeat(tab_cnt) + rel.substr(rel_ws.length())
	return target_base + rel


func apply_script_patches(existing_text: String, patches: Array) -> Dictionary:
	var current: String = existing_text.replace("\r\n", "\n")
	var applied_count: int = 0
	for patch_idx in range(patches.size()):
		var p_raw: Variant = patches[patch_idx]
		if typeof(p_raw) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_raw as Dictionary
		var find_str: String = String(p.get("find", p.get("search", p.get("old", "")))).replace("\r\n", "\n")
		var replace_str: String = String(p.get("replace", p.get("replacement", p.get("new", "")))).replace("\r\n", "\n")
		if find_str.is_empty():
			continue

		# Pass 1: exact substring match
		var exact_idx: int = current.find(find_str)
		if exact_idx >= 0:
			current = current.substr(0, exact_idx) + replace_str + current.substr(exact_idx + find_str.length())
			applied_count += 1
			continue

		# Pass 2: indentation-tolerant line-block fallback
		var find_trimmed_nl: String = find_str.trim_suffix("\n")
		var replace_trimmed_nl: String = replace_str.trim_suffix("\n")
		var cur_lines: PackedStringArray = current.split("\n")
		var find_lines: PackedStringArray = find_trimmed_nl.split("\n")
		if find_lines.is_empty():
			continue
		var match_start: int = -1
		var max_start: int = cur_lines.size() - find_lines.size()
		for start in range(max_start + 1):
			var all_match: bool = true
			for j in range(find_lines.size()):
				if cur_lines[start + j].strip_edges() != find_lines[j].strip_edges():
					all_match = false
					break
			if all_match:
				match_start = start
				break

		if match_start < 0:
			var preview: String = find_lines[0].strip_edges().left(80)
			return {
				"ok": false,
				"content": existing_text,
				"applied": applied_count,
				"error": "PATCH MISMATCH at patch #%d: could not locate '%s'" % [patch_idx + 1, preview],
			}

		var find_base: String = _leading_indent(find_lines[0])
		var target_base: String = _leading_indent(cur_lines[match_start])
		var space_unit: int = 4
		if find_base.begins_with(" "):
			space_unit = find_base.length()
		var replace_lines: PackedStringArray = replace_trimmed_nl.split("\n")
		var adjusted := PackedStringArray()
		for rl in replace_lines:
			if find_base == target_base:
				adjusted.append(rl)
			else:
				adjusted.append(_reindent_patch_line(rl, find_base, target_base, space_unit))

		var rebuilt := PackedStringArray()
		for i in range(match_start):
			rebuilt.append(cur_lines[i])
		for adj in adjusted:
			rebuilt.append(adj)
		for i in range(match_start + find_lines.size(), cur_lines.size()):
			rebuilt.append(cur_lines[i])
		current = "\n".join(rebuilt)
		applied_count += 1

	return {
		"ok": true,
		"content": current,
		"applied": applied_count,
		"error": "",
	}


func _escape_regex_literal(raw: String) -> String:
	var escaped := ""
	var specials := "\\.^$*+?()[]{}|"
	for i in range(raw.length()):
		var ch: String = raw.substr(i, 1)
		if ch in specials:
			escaped += "\\" + ch
		else:
			escaped += ch
	return escaped


func _script_declares_export_var(script_text: String, var_name: String) -> bool:
	var clean: String = var_name.strip_edges()
	if clean.is_empty():
		return false
	var rx := RegEx.new()
	var pat: String = "(?m)^[ \\t]*@export(?:_[a-z_]+)?(?:\\([^)]*\\))?[ \\t]+var[ \\t]+%s(?![A-Za-z0-9_])" % _escape_regex_literal(clean)
	if rx.compile(pat) != OK:
		return false
	return rx.search(script_text) != null


func find_dropped_preserved_exports(existing_text: String, next_text: String, preserve_exports: Array) -> PackedStringArray:
	var dropped := PackedStringArray()
	if existing_text.is_empty() or preserve_exports.is_empty():
		return dropped
	for raw_key in preserve_exports:
		var key: String = String(raw_key).strip_edges()
		if key.is_empty():
			continue
		if _script_declares_export_var(existing_text, key) and not _script_declares_export_var(next_text, key):
			if not dropped.has(key):
				dropped.append(key)
	return dropped


func apply_agent_bundle(
	editor_interface: EditorInterface,
	undo_redo: EditorUndoRedoManager,
	bundle: Dictionary,
	preferred_scene: String = ""
) -> Dictionary:
	var applied_scripts := PackedStringArray()
	var written_script_contents: Array = []
	var warnings := PackedStringArray()
	var compile_errors := PackedStringArray()
	var failed_script_updates: Dictionary = {}
	var applied_ops := 0
	var root_type_hints := {}
	var initial_open_scene := ""
	if editor_interface != null and editor_interface.get_edited_scene_root() != null:
		initial_open_scene = editor_interface.get_edited_scene_root().scene_file_path

	var preserve_exports_raw: Variant = bundle.get("preserveExports", [])
	var preserve_exports: Array = preserve_exports_raw as Array if typeof(preserve_exports_raw) == TYPE_ARRAY else []

	# 1. Compile-verify, patch-apply & guard preserved @export vars before writing scripts.
	for raw_u in bundle.get("scriptUpdates", []):
		if typeof(raw_u) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = raw_u as Dictionary
		var rpath := String(u.get("resPath", "")).strip_edges()
		if rpath.is_empty():
			continue
		var patches_raw: Variant = u.get("patches", [])
		var patches: Array = patches_raw as Array if typeof(patches_raw) == TYPE_ARRAY else []
		var existing_text: String = read_live_script_text(rpath, editor_interface)
		var content := ""
		if not patches.is_empty():
			if existing_text.strip_edges().is_empty():
				var fallback_content := strip_diff_prefixes(String(u.get("content", "")))
				if not fallback_content.is_empty():
					content = fallback_content
				else:
					var missing_err: String = "%s: PATCH MISMATCH — target file does not exist on disk" % rpath
					warnings.append(missing_err)
					compile_errors.append(missing_err)
					failed_script_updates[rpath] = ""
					continue
			else:
				var patch_res: Dictionary = apply_script_patches(existing_text, patches)
				if not bool(patch_res.get("ok", false)):
					var pm_err: String = "%s: %s" % [rpath, String(patch_res.get("error", "PATCH MISMATCH"))]
					warnings.append(pm_err)
					compile_errors.append(pm_err)
					failed_script_updates[rpath] = existing_text
					continue
				content = String(patch_res.get("content", "")).strip_edges(false, true)
		else:
			content = strip_diff_prefixes(String(u.get("content", "")))

		if content.is_empty():
			continue

		if not existing_text.is_empty() and not preserve_exports.is_empty():
			var dropped: PackedStringArray = find_dropped_preserved_exports(existing_text, content, preserve_exports)
			if not dropped.is_empty():
				var reg_err: String = "SIBLING REGRESSION in %s: removed preserved @export var(s): %s" % [rpath, ", ".join(dropped)]
				warnings.append(reg_err)
				compile_errors.append(reg_err)
				failed_script_updates[rpath] = content
				continue

		var chk := check_gdscript_compiles(content)
		if not bool(chk.get("ok", false)):
			var err_msg: String = String(chk.get("error", "compile error"))
			warnings.append("Skipped %s: %s" % [rpath.get_file(), err_msg])
			compile_errors.append("%s: %s" % [rpath, err_msg])
			failed_script_updates[rpath] = content
			continue
		_ensure_dir_for_res_path(rpath)
		var f := FileAccess.open(rpath, FileAccess.WRITE)
		if f == null:
			warnings.append("Could not write %s." % rpath)
			continue
		f.store_string(content + "\n")
		f.close()
		reload_script_safely(rpath, content + "\n")
		_sync_open_script_editor_after_disk_write(editor_interface, rpath, content + "\n")
		applied_scripts.append(rpath)
		written_script_contents.append(content)
		var uspath := String(u.get("scenePath", "")).strip_edges()
		var uattach := String(u.get("attachTo", "")).strip_edges()
		if not uspath.is_empty() and (uattach == "." or uattach == uspath.get_file().get_basename().to_pascal_case()):
			var ext_cls := extract_script_extends(content)
			if not ext_cls.is_empty():
				root_type_hints[uspath] = ext_cls

	# 1b. Apply explicit inputOps and auto-register any Input.is_action_* discovered in scripts.
	if editor_interface != null and not applied_scripts.is_empty():
		_reload_open_script_editors(editor_interface)
	var input_ops_raw: Variant = bundle.get("inputOps", [])
	if typeof(input_ops_raw) == TYPE_ARRAY:
		applied_ops += apply_input_ops(input_ops_raw)
	applied_ops += register_missing_script_input_actions(written_script_contents)

	# 2. Group sceneOps by scenePath and execute safely.
	var ops_by_scene := {}
	var arena_hint := String(bundle.get("arenaScenePath", "")).strip_edges()
	var dim_hint := String(bundle.get("dimension", "")).strip_edges().to_lower()
	var default_scene := preferred_scene.strip_edges()
	if default_scene.is_empty():
		default_scene = String(bundle.get("epicScenePath", "")).strip_edges()
	if default_scene.is_empty():
		default_scene = arena_hint
	if default_scene.is_empty():
		default_scene = initial_open_scene.strip_edges()
	if default_scene.is_empty():
		default_scene = "res://scenes/arena_2d.tscn" if dim_hint == "dim2d" else "res://scenes/arena_3d.tscn"
	for raw_op in bundle.get("sceneOps", []):
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op_dict: Dictionary = raw_op
		var spath := String(op_dict.get("scenePath", default_scene)).strip_edges()
		if spath.is_empty():
			spath = default_scene
		if not ops_by_scene.has(spath):
			ops_by_scene[spath] = []
		ops_by_scene[spath].append(op_dict)
		var op_kind := String(op_dict.get("op", "")).strip_edges().to_lower()
		if op_kind == "attach_script" and String(op_dict.get("nodePath", ".")) == ".":
			var sp_att := String(op_dict.get("scriptPath", "")).strip_edges()
			if FileAccess.file_exists(sp_att):
				var fa := FileAccess.open(sp_att, FileAccess.READ)
				if fa != null:
					var ext2 := extract_script_extends(fa.get_as_text())
					fa.close()
					if not ext2.is_empty():
						root_type_hints[spath] = ext2
		elif op_kind == "ensure_node":
			var pp := String(op_dict.get("parentPath", ".")).strip_edges()
			var np := String(op_dict.get("nodePath", "")).strip_edges()
			var nn := String(op_dict.get("nodeName", "")).strip_edges()
			var nt := String(op_dict.get("nodeType", "")).strip_edges()
			var scene_stem := spath.get_file().get_basename().to_pascal_case()
			if not nt.is_empty() and (pp.is_empty() or np == "." or (pp == "." and nn == scene_stem)):
				root_type_hints[spath] = nt

	var mode_lower := String(bundle.get("mode", "")).strip_edges().to_lower()
	var preserve_visuals := mode_lower == "build_feature" or mode_lower == "build_epic"
	for spath_key in ops_by_scene.keys():
		var spath_str := String(spath_key)
		var scene_ops: Array = ops_by_scene[spath_str]
		var target_root: Node = null
		var loaded_on_disk := false
		var rhint := String(root_type_hints.get(spath_str, ""))
		if editor_interface != null:
			target_root = ensure_scene_exists_and_open(editor_interface, spath_str, rhint, "", arena_hint, dim_hint)
		else:
			target_root = _load_or_create_disk_scene_root(spath_str, rhint, "", arena_hint, dim_hint)
			loaded_on_disk = target_root != null
		if target_root == null:
			warnings.append("Could not open scene %s for sceneOps." % spath_str)
			continue
		detach_incompatible_scripts(target_root)
		applied_ops += apply_scene_ops_to_root(target_root, scene_ops, warnings, preserve_visuals)
		sanitize_null_script_exports(target_root)
		if editor_interface != null:
			editor_interface.save_scene()
		elif loaded_on_disk:
			_save_disk_scene_root(target_root, spath_str)
			target_root.free()

	# Also attach scriptUpdates that specify attachTo + scenePath if not already handled in sceneOps.
	for raw_u in bundle.get("scriptUpdates", []):
		if typeof(raw_u) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = raw_u
		var rpath := String(u.get("resPath", "")).strip_edges()
		if failed_script_updates.has(rpath):
			continue
		var attach_to := String(u.get("attachTo", "")).strip_edges()
		var spath := String(u.get("scenePath", default_scene)).strip_edges()
		if rpath.is_empty() or attach_to.is_empty() or spath.is_empty() or not FileAccess.file_exists(rpath):
			continue
		var sroot: Node = null
		var sroot_on_disk := false
		var shint := String(root_type_hints.get(spath, ""))
		if editor_interface != null:
			sroot = ensure_scene_exists_and_open(editor_interface, spath, shint, "", arena_hint, dim_hint)
		else:
			sroot = _load_or_create_disk_scene_root(spath, shint, "", arena_hint, dim_hint)
			sroot_on_disk = sroot != null
		if sroot == null:
			continue
		var tnode: Node = sroot if (attach_to == "." or attach_to == sroot.name) else _resolve_node_by_rel_path(sroot, attach_to)
		if tnode == null:
			tnode = _find_node_recursive(sroot, attach_to)
		if tnode != null and can_attach_script_to_node(tnode, rpath):
			var scr_res: Script = reload_script_safely(rpath)
			if scr_res != null and tnode.get_script() != scr_res:
				tnode.set_script(scr_res)
				sanitize_null_script_exports(sroot)
				if editor_interface != null:
					editor_interface.save_scene()
				elif sroot_on_disk:
					_save_disk_scene_root(sroot, spath)
				applied_ops += 1
		if sroot_on_disk and sroot != null:
			sroot.free()

	heal_empty_project_input_actions()
	ensure_main_scene_configured(arena_hint, default_scene)

	# Restore primary Epic scene tab (or original scene tab) after multi-scene edits.
	var restore_scene := preferred_scene.strip_edges()
	if restore_scene.is_empty():
		restore_scene = String(bundle.get("epicScenePath", "")).strip_edges()
	if restore_scene.is_empty():
		restore_scene = String(bundle.get("featureScenePath", "")).strip_edges()
	if restore_scene.is_empty():
		restore_scene = initial_open_scene
	if editor_interface != null and not restore_scene.is_empty() and FileAccess.file_exists(restore_scene):
		var cur_ed := editor_interface.get_edited_scene_root()
		if cur_ed == null or cur_ed.scene_file_path != restore_scene:
			editor_interface.open_scene_from_path(restore_scene)

	invalidate_eval_cache()
	var summary := String(bundle.get("summary", "")).strip_edges()
	if summary.is_empty():
		summary = "Updated %d script(s), %d scene op(s)." % [applied_scripts.size(), applied_ops]
	var has_hard_failure: bool = (not compile_errors.is_empty()) and applied_scripts.is_empty() and applied_ops == 0
	return {
		"ok": (not has_hard_failure) and (warnings.is_empty() or applied_scripts.size() > 0 or applied_ops > 0),
		"summary": summary,
		"applied_scripts": applied_scripts,
		"applied_ops": applied_ops,
		"warnings": warnings,
		"compile_errors": compile_errors,
		"failed_script_updates": failed_script_updates,
	}


func _resolve_op_node(scene_root: Node, rel_or_name: String) -> Node:
	if scene_root == null:
		return null
	var p := rel_or_name.strip_edges()
	if p.is_empty() or p == "." or p == scene_root.name:
		return scene_root
	var by_rel := _resolve_node_by_rel_path(scene_root, p)
	if by_rel != null:
		return by_rel
	return _find_node_recursive(scene_root, p.get_file())


func _apply_groups_to_node(node: Node, raw_groups: Variant) -> int:
	if node == null or typeof(raw_groups) != TYPE_ARRAY:
		return 0
	var added := 0
	for g_raw in (raw_groups as Array):
		var g := String(g_raw).strip_edges()
		if not g.is_empty() and not node.is_in_group(g):
			node.add_to_group(g, true)
			added += 1
	return added


func _load_or_create_disk_scene_root(
	scene_path: String,
	root_type_hint: String = "",
	root_name_hint: String = "",
	arena_hint: String = "",
	dimension_hint: String = ""
) -> Node:
	var clean_path := scene_path.strip_edges()
	if clean_path.is_empty() or not clean_path.ends_with(".tscn"):
		return null
	if FileAccess.file_exists(clean_path) or ResourceLoader.exists(clean_path):
		var ps := ResourceLoader.load(clean_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if ps != null:
			return ps.instantiate()
	var cls_name := infer_scene_root_type(clean_path, root_type_hint, arena_hint, dimension_hint)
	if not ClassDB.class_exists(cls_name) or not ClassDB.can_instantiate(cls_name):
		cls_name = "Node3D"
	var inst := ClassDB.instantiate(cls_name)
	if not (inst is Node):
		if inst is Object:
			(inst as Object).free()
		return null
	var root := inst as Node
	var rname := root_name_hint.strip_edges()
	if rname.is_empty():
		rname = clean_path.get_file().get_basename().to_pascal_case()
	if rname.is_empty():
		rname = "SceneRoot"
	root.name = rname
	return root


func _save_disk_scene_root(scene_root: Node, scene_path: String) -> bool:
	if scene_root == null or scene_path.strip_edges().is_empty():
		return false
	var stack: Array[Node] = []
	for ch in scene_root.get_children():
		stack.append(ch)
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur.owner == null:
			cur.owner = scene_root
		if cur.scene_file_path.is_empty():
			for gch in cur.get_children():
				stack.append(gch)
	_ensure_dir_for_res_path(scene_path)
	var ps := PackedScene.new()
	if ps.pack(scene_root) != OK:
		return false
	return ResourceSaver.save(ps, scene_path) == OK


func apply_scene_ops_to_root(
	scene_root: Node,
	ops: Array,
	warnings: PackedStringArray = PackedStringArray(),
	preserve_existing_visuals: bool = false
) -> int:
	if scene_root == null:
		return 0
	var visual_transform_keys: Array[String] = [
		"position",
		"rotation",
		"rotation_degrees",
		"scale",
		"transform",
		"global_position",
		"global_transform",
		"global_rotation",
	]
	var count := 0
	for raw_op in ops:
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op_dict: Dictionary = raw_op
		var op := String(op_dict.get("op", "")).strip_edges().to_lower()
		if op == "detach_script":
			var np := String(op_dict.get("nodePath", "."))
			var node := _resolve_op_node(scene_root, np)
			if node != null and preserve_existing_visuals and _is_internal_instanced_child(scene_root, node):
				warnings.append("Protected internal instanced child %s from detach_script." % np)
				continue
			if node != null and node.get_script() != null:
				node.set_script(null)
				count += 1
		elif op == "attach_script":
			var np := String(op_dict.get("nodePath", "."))
			var spath := String(op_dict.get("scriptPath", "")).strip_edges()
			var node := _resolve_op_node(scene_root, np)
			if node != null and preserve_existing_visuals and _is_internal_instanced_child(scene_root, node):
				warnings.append("Protected internal instanced child %s from attach_script." % np)
				continue
			if node == null or spath.is_empty() or not FileAccess.file_exists(spath):
				warnings.append("attach_script skipped (%s -> %s)." % [spath, np])
				continue
			if not can_attach_script_to_node(node, spath):
				warnings.append("Blocked incompatible script %s on %s (%s)." % [spath.get_file(), node.name, node.get_class()])
				continue
			var scr_res: Script = reload_script_safely(spath)
			if scr_res != null:
				node.set_script(scr_res)
				count += 1
		elif op == "ensure_node":
			var node_name := String(op_dict.get("nodeName", "")).strip_edges()
			var parent_p := String(op_dict.get("parentPath", ".")).strip_edges()
			var np_hint := String(op_dict.get("nodePath", "")).strip_edges()
			var node_type := String(op_dict.get("nodeType", "Node")).strip_edges()
			var is_root_op := parent_p.is_empty() or np_hint == "." or (parent_p == "." and node_name == scene_root.name)
			var node: Node = null
			var created_new := false
			if is_root_op:
				node = scene_root
			else:
				if node_name.is_empty():
					continue
				var parent := _resolve_op_node(scene_root, parent_p)
				if parent == null:
					parent = scene_root
				node = parent.get_node_or_null(node_name)
				if node == null and parent != scene_root:
					var root_direct: Node = scene_root.get_node_or_null(NodePath(node_name))
					if root_direct != null and root_direct != parent and not root_direct.is_ancestor_of(parent):
						if node_type.is_empty() or node_type == "Node" or root_direct.get_class() == node_type or root_direct.is_class(node_type):
							if root_direct.get_parent() != null:
								root_direct.get_parent().remove_child(root_direct)
							_unset_subtree_owners(root_direct)
							parent.add_child(root_direct)
							if parent != scene_root and parent.owner == null:
								parent.owner = scene_root
							root_direct.owner = scene_root
							_reown_subtree(root_direct, null, scene_root)
							node = root_direct
							count += 1
				if node == null:
					if not ClassDB.class_exists(node_type) or not ClassDB.can_instantiate(node_type):
						node_type = "Node"
					node = ClassDB.instantiate(node_type) as Node
					if node == null:
						continue
					node.name = node_name
					parent.add_child(node)
					node.owner = scene_root
					created_new = true
					count += 1
			if not created_new and preserve_existing_visuals and _is_internal_instanced_child(scene_root, node):
				warnings.append("Protected internal instanced child %s from ensure_node." % node.name)
				continue
			var sr_cls := String(op_dict.get("subResourceClass", "")).strip_edges()
			var sr_props: Dictionary = op_dict.get("subResourceProps", {})
			var fake_sp := {
				"subResourceClass": sr_cls,
				"subResourceProps": sr_props,
				"props": op_dict.get("properties", {}),
			}
			if _sync_existing_node_from_spec(node, fake_sp, preserve_existing_visuals and not created_new):
				count += 1
			var attach_sp := String(op_dict.get("scriptPath", "")).strip_edges()
			if not attach_sp.is_empty() and FileAccess.file_exists(attach_sp) and can_attach_script_to_node(node, attach_sp):
				var sres: Script = reload_script_safely(attach_sp)
				if sres != null:
					node.set_script(sres)
					count += 1
			count += _apply_groups_to_node(node, op_dict.get("groups", []))
		elif op == "reparent_node":
			var np_src := String(op_dict.get("nodePath", op_dict.get("nodeName", ""))).strip_edges()
			var dst_p := String(op_dict.get("newParentPath", op_dict.get("parentPath", "."))).strip_edges()
			var src_node := _resolve_op_node(scene_root, np_src)
			var dst_parent := _resolve_op_node(scene_root, dst_p)
			if src_node == null or dst_parent == null:
				warnings.append("reparent_node target not found (%s -> %s)." % [np_src, dst_p])
				continue
			if preserve_existing_visuals and _is_instanced_scene_node(scene_root, src_node):
				warnings.append("Protected instanced scene node %s from reparent_node." % np_src)
				continue
			if src_node != scene_root and src_node != dst_parent and not src_node.is_ancestor_of(dst_parent) and src_node.get_parent() != dst_parent:
				if src_node.get_parent() != null:
					src_node.get_parent().remove_child(src_node)
				_unset_subtree_owners(src_node)
				dst_parent.add_child(src_node)
				if dst_parent != scene_root and dst_parent.owner == null:
					dst_parent.owner = scene_root
				src_node.owner = scene_root
				_reown_subtree(src_node, null, scene_root)
				count += 1
			var rp_props: Variant = op_dict.get("properties", {})
			if typeof(rp_props) == TYPE_DICTIONARY and not (rp_props as Dictionary).is_empty():
				if _sync_existing_node_from_spec(src_node, {"props": rp_props}, false):
					count += 1
		elif op == "set_property":
			var np := String(op_dict.get("nodePath", "."))
			var node := _resolve_op_node(scene_root, np)
			if node == null:
				warnings.append("set_property node not found: %s" % np)
				continue
			if preserve_existing_visuals and _is_internal_instanced_child(scene_root, node):
				warnings.append("Protected internal instanced child %s from set_property." % np)
				continue
			var sr_cls2 := String(op_dict.get("subResourceClass", "")).strip_edges()
			var sr_props2: Dictionary = op_dict.get("subResourceProps", {})
			if not sr_cls2.is_empty() or not sr_props2.is_empty():
				if sr_cls2.is_empty() and (node is CollisionShape3D or node is CollisionShape2D) and node.get("shape") != null:
					sr_cls2 = (node.get("shape") as Object).get_class()
				if _sync_existing_node_from_spec(node, {"subResourceClass": sr_cls2, "subResourceProps": sr_props2, "props": {}}, preserve_existing_visuals):
					count += 1
			var props: Dictionary = op_dict.get("properties", {})
			for pk in props.keys():
				var pk_str := String(pk)
				if preserve_existing_visuals:
					if (pk_str in visual_transform_keys) and (_is_instanced_scene_node(scene_root, node) or not _is_physics_or_rig_node(node)):
						continue
					if pk_str == "mesh" and node is MeshInstance3D and (_has_custom_asset_resource(node.get("mesh")) or node.get("mesh") != null):
						continue
					if pk_str == "material_override" and node is GeometryInstance3D and (node as GeometryInstance3D).material_override != null:
						continue
					if pk_str == "material" and node is CSGShape3D and node.get("material") != null:
						continue
					if pk_str == "texture" and (node is Sprite2D or node is Sprite3D) and node.get("texture") != null:
						continue
					if _is_hand_tuned_collision_prop(node, pk_str):
						var next_col: int = int(_coerce_prop_value(props[pk], pk_str))
						if next_col != int(node.get(pk_str)):
							continue
				var raw_v: Variant = props[pk]
				if (node is CollisionShape3D or node is CollisionShape2D) and (pk_str == "size" or pk_str == "radius" or pk_str == "height" or pk_str == "length"):
					var sh_obj: Variant = node.get("shape")
					if sh_obj is Resource:
						var dup_sh: Resource = (sh_obj as Resource).duplicate()
						dup_sh.set(pk_str, _coerce_prop_value(raw_v, pk_str))
						node.set("shape", dup_sh)
						count += 1
						continue
				if (pk_str == "material" or pk_str == "material_override") and typeof(raw_v) == TYPE_DICTIONARY:
					_apply_material_dict_to_node(node, raw_v)
				else:
					node.set(pk_str, _coerce_prop_value(raw_v, pk_str))
				count += 1
		elif op == "add_to_group":
			var np := String(op_dict.get("nodePath", "."))
			var node := _resolve_op_node(scene_root, np)
			if node == null:
				warnings.append("add_to_group node not found: %s" % np)
				continue
			var grp_list := []
			var single_g := String(op_dict.get("groupName", op_dict.get("group", ""))).strip_edges()
			if not single_g.is_empty():
				grp_list.append(single_g)
			var raw_gs: Variant = op_dict.get("groups", [])
			if typeof(raw_gs) == TYPE_ARRAY:
				for g in (raw_gs as Array):
					grp_list.append(g)
			count += _apply_groups_to_node(node, grp_list)
		elif op == "connect_signal":
			var src_p := String(op_dict.get("sourcePath", "."))
			var sig_n := String(op_dict.get("signalName", ""))
			var tgt_p := String(op_dict.get("targetPath", "."))
			var meth_n := String(op_dict.get("methodName", ""))
			var sres := _connect_single_signal_safe(scene_root, src_p, sig_n, tgt_p, meth_n)
			if bool(sres.get("ok", false)):
				count += 1
			else:
				warnings.append(String(sres.get("reason", "Signal connection skipped.")))
		elif op == "instance_scene":
			var ipath := String(op_dict.get("instancePath", "")).strip_edges()
			if ipath.is_empty() or not ResourceLoader.exists(ipath):
				warnings.append("instance_scene missing scene: %s" % ipath)
				continue
			var existing := _find_instanced_scene_node(scene_root, ipath)
			var was_existing := (existing != null)
			var inst_node: Node = existing
			if inst_node == null:
				var pscene: PackedScene = ResourceLoader.load(ipath, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
				if pscene == null:
					continue
				inst_node = pscene.instantiate()
				if inst_node == null:
					continue
				var nname := String(op_dict.get("nodeName", "")).strip_edges()
				if not nname.is_empty():
					inst_node.name = nname
				var parent := _resolve_op_node(scene_root, String(op_dict.get("parentPath", ".")))
				if parent == null:
					parent = scene_root
				parent.add_child(inst_node)
				inst_node.owner = scene_root
				count += 1
			var props: Dictionary = op_dict.get("properties", {})
			for pk in props.keys():
				var pk_str := String(pk)
				if preserve_existing_visuals and was_existing and (pk_str in visual_transform_keys):
					continue
				inst_node.set(pk_str, _coerce_prop_value(props[pk], pk_str))
				count += 1
			count += _apply_groups_to_node(inst_node, op_dict.get("groups", []))
		elif op == "remove_node":
			var np := String(op_dict.get("nodePath", "")).strip_edges()
			var node := _resolve_op_node(scene_root, np)
			if node != null and node != scene_root:
				if preserve_existing_visuals and _is_instanced_scene_node(scene_root, node):
					warnings.append("Protected instanced scene node %s from remove_node." % np)
					continue
				if node.get_parent() != null:
					node.get_parent().remove_child(node)
				node.queue_free()
				count += 1
	return count


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


func _sync_open_script_editor_after_disk_write(
	editor_interface: EditorInterface,
	res_path: String,
	new_text: String
) -> void:
	if editor_interface == null or res_path.is_empty() or not editor_interface.has_method("get_script_editor"):
		return
	var script_ed: Variant = editor_interface.get_script_editor()
	if script_ed == null or not script_ed.has_method("get_open_scripts") or not script_ed.has_method("get_open_script_editors"):
		return
	var open_scripts: Array = script_ed.get_open_scripts()
	var open_editors: Array = script_ed.get_open_script_editors()
	var count: int = mini(open_scripts.size(), open_editors.size())
	for i in range(count):
		var scr_v: Variant = open_scripts[i]
		if not (scr_v is Script):
			continue
		if String((scr_v as Script).resource_path).strip_edges() != res_path:
			continue
		var ed_v: Variant = open_editors[i]
		if ed_v != null and ed_v.has_method("get_base_editor"):
			var base_ed: Variant = ed_v.get_base_editor()
			if base_ed != null and base_ed.has_method("set_text"):
				base_ed.call("set_text", new_text)
				if base_ed.has_method("tag_saved_version"):
					base_ed.call("tag_saved_version")


func _reload_open_script_editors(editor_interface: EditorInterface) -> void:
	if editor_interface == null or not editor_interface.has_method("get_script_editor"):
		return
	var script_ed: Variant = editor_interface.get_script_editor()
	if script_ed != null and script_ed.has_method("reload_open_files"):
		script_ed.call("reload_open_files")


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


func read_scoped_project_scripts(
	priority_paths: Array = [],
	root_dir: String = "res://",
	editor_interface: EditorInterface = null,
	max_scripts: int = 16
) -> Dictionary:
	var cap: int = maxi(max_scripts, 1)
	var open_buffers: Dictionary = collect_open_script_editor_buffers(editor_interface)
	var ordered_paths: Array[String] = []
	var seen: Dictionary = {}

	var enqueue_gd := func(raw_p: String) -> void:
		var sp: String = raw_p.strip_edges()
		if not sp.begins_with("res://") or not sp.ends_with(".gd"):
			return
		if sp.begins_with("res://addons/") or ("/addons/" in sp):
			return
		if not seen.has(sp):
			seen[sp] = true
			ordered_paths.append(sp)

	var gd_in_tscn_rx := RegEx.new()
	gd_in_tscn_rx.compile("res://[^\\s\"']+\\.gd")

	for raw_pri in priority_paths:
		var p_str: String = String(raw_pri).strip_edges()
		if p_str.is_empty():
			continue
		if p_str.ends_with(".gd"):
			enqueue_gd.call(p_str)
		elif p_str.ends_with(".tscn") and FileAccess.file_exists(p_str):
			var tscn_txt: String = FileAccess.get_file_as_string(p_str)
			for m in gd_in_tscn_rx.search_all(tscn_txt):
				enqueue_gd.call(m.get_string())

	for open_k in open_buffers.keys():
		enqueue_gd.call(String(open_k))

	for scanned_raw in _scan_project_files_by_ext(root_dir, ".gd", maxi(cap * 3, 40)):
		enqueue_gd.call(String(scanned_raw))

	var out := {}
	for sp in ordered_paths:
		if out.size() >= cap:
			break
		if open_buffers.has(sp):
			out[sp] = String(open_buffers[sp]).left(65536)
			continue
		if FileAccess.file_exists(sp):
			var txt: String = FileAccess.get_file_as_string(sp)
			if not txt.strip_edges().is_empty():
				out[sp] = txt.left(65536)
	return out


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


func _ensure_dir_for_res_path(res_path: String) -> void:
	var dir_path: String = res_path.get_base_dir()
	if dir_path.is_empty():
		return
	var abs_dir: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)


static func _scan_project_files_by_ext_static(ext: String, cap: int = 16) -> PackedStringArray:
	var results := PackedStringArray()
	var stack: Array[String] = ["res://"]
	while not stack.is_empty() and results.size() < cap:
		var dir_path: String = stack.pop_back()
		var da: DirAccess = DirAccess.open(dir_path)
		if da == null:
			continue
		da.list_dir_begin()
		var entry: String = da.get_next()
		while not entry.is_empty():
			if entry.begins_with(".") or entry == "addons":
				entry = da.get_next()
				continue
			var full: String = "%s/%s" % [dir_path, entry] if dir_path != "res://" else ("res://%s" % entry)
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


static func collect_godot_project_context(editor_interface: Variant = null, recent_errors: Array = []) -> Dictionary:
	var proj_name: String = str(ProjectSettings.get_setting("application/config/name", "")).strip_edges()
	if proj_name.is_empty():
		var abs_root: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
		proj_name = abs_root.get_file()
	if proj_name.is_empty():
		proj_name = "GodotProject"

	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", "")).strip_edges()
	if main_scene.is_empty() and editor_interface != null and editor_interface.has_method("get_edited_scene_root"):
		var ed_root: Variant = editor_interface.call("get_edited_scene_root")
		if ed_root != null and ed_root is Node:
			var sfp: String = String((ed_root as Node).scene_file_path).strip_edges()
			if not sfp.is_empty():
				main_scene = sfp

	var input_actions: Array[String] = []
	var custom_actions: Array[String] = []
	for act_sn in InputMap.get_actions():
		var act_str: String = String(act_sn).strip_edges()
		if act_str.is_empty() or act_str.begins_with("ui_"):
			continue
		custom_actions.append(act_str)
	custom_actions.sort()
	for a in custom_actions.slice(0, 16):
		input_actions.append(a)

	var scene_files: Array[String] = []
	for sf in _scan_project_files_by_ext_static(".tscn", 12):
		scene_files.append(sf)

	var script_files: Array[String] = []
	for gdf in _scan_project_files_by_ext_static(".gd", 14):
		script_files.append(gdf)

	var resource_files: Array[String] = []
	for rf in _scan_project_files_by_ext_static(".tres", 8):
		resource_files.append(rf)

	var clean_errors: Array[String] = []
	for err_raw in recent_errors:
		var es: String = str(err_raw).strip_edges()
		if not es.is_empty() and not clean_errors.has(es):
			clean_errors.append(es)
			if clean_errors.size() >= 8:
				break

	return {
		"project_name": proj_name,
		"main_scene": main_scene,
		"input_actions": input_actions,
		"scene_files": scene_files,
		"script_files": script_files,
		"resource_files": resource_files,
		"recent_errors": clean_errors,
	}


func _format_tuning_literal_for_type(raw_val: String, unit_str: String, type_hint: String) -> Dictionary:
	var clean_v: String = raw_val.strip_edges()
	var val_lower: String = clean_v.to_lower()
	var unit_lower: String = unit_str.strip_edges().to_lower()
	var th_lower: String = type_hint.strip_edges().to_lower()
	if th_lower == "bool" or unit_lower == "bool" or unit_lower == "boolean" or val_lower == "true" or val_lower == "false":
		var bval: bool = (val_lower == "true" or val_lower == "1")
		return {"ok": true, "literal": "true" if bval else "false", "typed": bval}
	if th_lower == "int" or (unit_lower == "count" and clean_v.is_valid_int()):
		if not clean_v.is_valid_float():
			return {"ok": false, "literal": "", "typed": null}
		var ival: int = int(roundf(clean_v.to_float()))
		return {"ok": true, "literal": str(ival), "typed": ival}
	if not clean_v.is_valid_float():
		return {"ok": false, "literal": "", "typed": null}
	var fval: float = clean_v.to_float()
	var flit: String = clean_v if ("." in clean_v or "e" in val_lower) else ("%s.0" % str(int(fval)))
	return {"ok": true, "literal": flit, "typed": fval}


func _node_has_script_property(node: Node, prop_key: String) -> bool:
	if node == null or prop_key.is_empty():
		return false
	var scr_v: Variant = node.get_script()
	if not (scr_v is Script):
		return false
	for p_raw in (scr_v as Script).get_script_property_list():
		if typeof(p_raw) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = p_raw as Dictionary
		if String(pd.get("name", "")) == prop_key:
			return true
	return false


func apply_live_export_tuning(
	editor_interface: EditorInterface,
	key: String,
	raw_value: String,
	unit: String = "",
	preferred_scene: String = ""
) -> Dictionary:
	var updated_scripts := PackedStringArray()
	var updated_scenes := PackedStringArray()
	var clean_key: String = key.strip_edges()
	var key_rx := RegEx.new()
	key_rx.compile("^[a-zA-Z_][a-zA-Z0-9_]*$")
	if key_rx.search(clean_key) == null:
		return {
			"ok": false,
			"updated_scripts": updated_scripts,
			"updated_scenes": updated_scenes,
		}

	var clean_val: String = raw_value.strip_edges()
	var clean_unit: String = unit.strip_edges()
	var exp_rx := RegEx.new()
	exp_rx.compile("(?m)^([ \\t]*@export(?:_[a-z_]+(?:\\([^)]*\\))?)?[ \\t]+var[ \\t]+" + clean_key + "\\b[ \\t]*(?::[ \\t]*([A-Za-z0-9_]+))?[ \\t]*:?=[ \\t]*)([^#\\r\\n]+?)([ \\t]*(?:#.*)?)$")

	var live_scripts: Dictionary = read_all_live_project_scripts("res://", editor_interface)
	for sp_raw in live_scripts.keys():
		var sp: String = String(sp_raw).strip_edges()
		var src: String = String(live_scripts.get(sp_raw, ""))
		if sp.is_empty() or src.is_empty():
			continue
		var m: RegExMatch = exp_rx.search(src)
		if m == null:
			continue
		var type_hint: String = m.get_string(2).strip_edges()
		var fmt: Dictionary = _format_tuning_literal_for_type(clean_val, clean_unit, type_hint)
		if not bool(fmt.get("ok", false)):
			continue
		var replacement: String = m.get_string(1) + String(fmt.get("literal", "")) + m.get_string(4)
		var new_src: String = src.substr(0, m.get_start()) + replacement + src.substr(m.get_end())
		if not bool(check_gdscript_compiles(new_src).get("ok", false)):
			continue
		var write_src: String = new_src if new_src.ends_with("\n") else (new_src + "\n")
		_ensure_dir_for_res_path(sp)
		var fw := FileAccess.open(sp, FileAccess.WRITE)
		if fw == null:
			continue
		fw.store_string(write_src)
		fw.close()
		reload_script_safely(sp, write_src)
		_sync_open_script_editor_after_disk_write(editor_interface, sp, write_src)
		updated_scripts.append(sp)

	if editor_interface != null and not updated_scripts.is_empty():
		_reload_open_script_editors(editor_interface)

	var fmt_any: Dictionary = _format_tuning_literal_for_type(clean_val, clean_unit, "")
	if bool(fmt_any.get("ok", false)):
		var typed_val: Variant = fmt_any.get("typed", null)
		var visited_scenes := {}
		var open_roots: Dictionary = _get_open_scene_roots_by_path(editor_interface)
		var edited_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
		for ep_raw in open_roots.keys():
			var ep: String = String(ep_raw).strip_edges()
			var open_r: Node = open_roots.get(ep_raw, null) as Node
			if open_r == null:
				continue
			if not ep.is_empty():
				visited_scenes[ep] = true
			var dirty_open := false
			var ostack: Array[Node] = [open_r]
			while not ostack.is_empty():
				var cur: Node = ostack.pop_back()
				var scr_v: Variant = cur.get_script()
				if scr_v is Script:
					var scr_p: String = String((scr_v as Script).resource_path).strip_edges()
					if updated_scripts.has(scr_p) or _node_has_script_property(cur, clean_key):
						if cur.get(clean_key) != typed_val:
							cur.set(clean_key, typed_val)
							dirty_open = true
				for ch in cur.get_children():
					ostack.append(ch)
			if dirty_open:
				if editor_interface != null and open_r == edited_root and editor_interface.has_method("save_scene"):
					editor_interface.call("save_scene")
				elif not ep.is_empty():
					_save_disk_scene_root(open_r, ep)
				if not ep.is_empty() and not (ep in updated_scenes):
					updated_scenes.append(ep)

		var candidate_scenes := PackedStringArray()
		for cand_raw in [preferred_scene, String(ProjectSettings.get_setting("application/run/main_scene", ""))]:
			var cp: String = String(cand_raw).strip_edges()
			if cp.begins_with("res://") and cp.ends_with(".tscn") and not (cp in candidate_scenes):
				candidate_scenes.append(cp)
		for proj_sc in collect_project_scene_paths("res://", 16):
			if not (proj_sc in candidate_scenes):
				candidate_scenes.append(proj_sc)

		for sc_p in candidate_scenes:
			if visited_scenes.has(sc_p) or not FileAccess.file_exists(sc_p):
				continue
			visited_scenes[sc_p] = true
			var ps: PackedScene = ResourceLoader.load(sc_p, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			if ps == null:
				continue
			var sroot: Node = ps.instantiate()
			if sroot == null:
				continue
			var dirty_disk := false
			var dstack: Array[Node] = [sroot]
			while not dstack.is_empty():
				var cur_d: Node = dstack.pop_back()
				var scr_dv: Variant = cur_d.get_script()
				if scr_dv is Script:
					var scr_dp: String = String((scr_dv as Script).resource_path).strip_edges()
					if updated_scripts.has(scr_dp) or _node_has_script_property(cur_d, clean_key):
						if cur_d.get(clean_key) != typed_val:
							cur_d.set(clean_key, typed_val)
							dirty_disk = true
				for ch_d in cur_d.get_children():
					dstack.append(ch_d)
			if dirty_disk:
				if _save_disk_scene_root(sroot, sc_p) and not (sc_p in updated_scenes):
					updated_scenes.append(sc_p)
			sroot.free()

	if not updated_scripts.is_empty() or not updated_scenes.is_empty():
		invalidate_eval_cache()
	return {
		"ok": not updated_scripts.is_empty() or not updated_scenes.is_empty(),
		"updated_scripts": updated_scripts,
		"updated_scenes": updated_scenes,
	}


const _READONLY_AGENT_TOOLS := {
	"list_project_files": true,
	"grep_project_text": true,
	"read_script_slice": true,
	"inspect_scene_tree": true,
	"read_autoloads_and_layers": true,
	"inspect_tres_resource": true,
}


static func _extract_quoted_attr(header_line: String, attr_name: String) -> String:
	var needle: String = attr_name + "=\""
	var idx: int = header_line.find(needle)
	if idx < 0:
		return ""
	var val_start: int = idx + needle.length()
	var val_end: int = header_line.find("\"", val_start)
	if val_end < 0:
		return ""
	return header_line.substr(val_start, val_end - val_start)


func _validate_readonly_res_path(raw_path: String, allow_root_dir: bool = false) -> Dictionary:
	var p: String = raw_path.strip_edges().replace("\\", "/")
	if p.is_empty():
		return {"ok": false, "error": "Path cannot be empty."}
	if not p.begins_with("res://"):
		return {"ok": false, "error": "Only res:// project paths are allowed."}
	while p.length() > 6 and p.ends_with("/"):
		p = p.substr(0, p.length() - 1)
	var rel: String = p.substr(6)
	if rel.is_empty():
		if allow_root_dir:
			return {"ok": true, "path": "res://"}
		return {"ok": false, "error": "File path required (got res:// root)."}
	if ".." in rel:
		return {"ok": false, "error": "Path traversal ('..') is forbidden."}
	var segments: PackedStringArray = rel.split("/", false)
	for seg: String in segments:
		if seg == "." or seg == ".." or seg.begins_with("."):
			return {"ok": false, "error": "Hidden or relative path segments are forbidden."}
	if segments.size() > 0 and segments[0].to_lower() == "addons":
		return {"ok": false, "error": "Access to res://addons/ is forbidden."}
	return {"ok": true, "path": "res://" + "/".join(segments)}


func _collect_readonly_files(root_dir: String, ext_filter: String = "", cap: int = 80) -> Dictionary:
	var normalized_ext: String = ext_filter.strip_edges().to_lower()
	if not normalized_ext.is_empty() and not normalized_ext.begins_with("."):
		normalized_ext = "." + normalized_ext
	var collected: Array[String] = []
	var queue: Array[String] = [root_dir]
	var scan_limit: int = maxi(cap * 4, 256)
	var saw_more: bool = false
	while not queue.is_empty():
		var cur_dir: String = queue.pop_front()
		var da: DirAccess = DirAccess.open(cur_dir)
		if da == null:
			continue
		var subdirs: Array[String] = []
		var dir_files: Array[String] = []
		da.list_dir_begin()
		while true:
			var item: String = da.get_next()
			if item.is_empty():
				break
			if item == "." or item == ".." or item.begins_with("."):
				continue
			if da.current_is_dir():
				if item.to_lower() == "addons":
					continue
				var sub_path: String = (cur_dir + item) if cur_dir == "res://" else (cur_dir + "/" + item)
				subdirs.append(sub_path)
			else:
				var lower_item: String = item.to_lower()
				if lower_item.ends_with(".uid") or lower_item.ends_with(".import") or lower_item.ends_with(".pyc") or lower_item.ends_with(".tmp"):
					continue
				if not normalized_ext.is_empty() and not lower_item.ends_with(normalized_ext):
					continue
				var file_path: String = (cur_dir + item) if cur_dir == "res://" else (cur_dir + "/" + item)
				dir_files.append(file_path)
		da.list_dir_end()
		subdirs.sort()
		dir_files.sort()
		for sd: String in subdirs:
			queue.append(sd)
		for fp: String in dir_files:
			collected.append(fp)
			if collected.size() >= scan_limit:
				saw_more = true
				break
		if saw_more:
			break
	collected.sort()
	var truncated: bool = saw_more or collected.size() > cap
	if collected.size() > cap:
		collected = collected.slice(0, cap)
	return {"files": collected, "truncated": truncated}


func tool_list_project_files(args: Dictionary) -> Dictionary:
	var raw_dir: String = str(args.get("dir", args.get("path", "res://"))).strip_edges()
	if raw_dir.is_empty():
		raw_dir = "res://"
	var v: Dictionary = _validate_readonly_res_path(raw_dir, true)
	if not bool(v.get("ok", false)):
		return {"ok": false, "tool": "list_project_files", "error": str(v.get("error", "Invalid directory."))}
	var target_dir: String = str(v.get("path", "res://"))
	if DirAccess.open(target_dir) == null:
		return {"ok": false, "tool": "list_project_files", "error": "Directory not found: " + target_dir}
	var ext_filter: String = str(args.get("ext", "")).strip_edges()
	var cap: int = clampi(int(args.get("cap", 80)), 1, 200)
	var scanned: Dictionary = _collect_readonly_files(target_dir, ext_filter, cap)
	var files: Array[String] = scanned.get("files", []) as Array[String]
	return {
		"ok": true,
		"tool": "list_project_files",
		"dir": target_dir,
		"files": files,
		"count": files.size(),
		"truncated": bool(scanned.get("truncated", false)),
	}


func tool_grep_project_text(args: Dictionary, editor_interface: Variant = null) -> Dictionary:
	var query: String = str(args.get("query", ""))
	if query.strip_edges().is_empty():
		return {"ok": false, "tool": "grep_project_text", "error": "Query cannot be empty."}
	var raw_dir: String = str(args.get("dir", "res://")).strip_edges()
	if raw_dir.is_empty():
		raw_dir = "res://"
	var v: Dictionary = _validate_readonly_res_path(raw_dir, true)
	if not bool(v.get("ok", false)):
		return {"ok": false, "tool": "grep_project_text", "error": str(v.get("error", "Invalid directory."))}
	var target_dir: String = str(v.get("path", "res://"))
	if DirAccess.open(target_dir) == null:
		return {"ok": false, "tool": "grep_project_text", "error": "Directory not found: " + target_dir}
	var ext_filter: String = str(args.get("ext", "")).strip_edges()
	var case_sensitive: bool = bool(args.get("caseSensitive", false))
	var max_matches: int = clampi(int(args.get("maxMatches", 25)), 1, 80)
	var scanned: Dictionary = _collect_readonly_files(target_dir, ext_filter, 200)
	var files: Array[String] = scanned.get("files", []) as Array[String]
	var ed: EditorInterface = editor_interface as EditorInterface if editor_interface is EditorInterface else null
	var matches: Array[Dictionary] = []
	var truncated: bool = false
	var text_exts: Array[String] = [".gd", ".tscn", ".tres", ".cfg", ".godot", ".shader", ".gdshader", ".json", ".txt", ".md"]
	for fp: String in files:
		var lower_fp: String = fp.to_lower()
		var is_searchable: bool = false
		for te: String in text_exts:
			if lower_fp.ends_with(te):
				is_searchable = true
				break
		if not is_searchable:
			continue
		var content: String = ""
		if lower_fp.ends_with(".gd"):
			content = read_live_script_text(fp, ed)
		elif FileAccess.file_exists(fp):
			content = FileAccess.get_file_as_string(fp)
		if content.is_empty():
			continue
		var lines: PackedStringArray = content.split("\n")
		for idx: int in range(lines.size()):
			var line_text: String = lines[idx]
			var hit: bool = line_text.contains(query) if case_sensitive else line_text.containsn(query)
			if hit:
				matches.append({
					"path": fp,
					"line": idx + 1,
					"text": line_text.strip_edges().substr(0, 220),
				})
				if matches.size() >= max_matches:
					truncated = true
					break
		if truncated:
			break
	return {
		"ok": true,
		"tool": "grep_project_text",
		"query": query,
		"dir": target_dir,
		"matches": matches,
		"truncated": truncated,
	}


func tool_read_script_slice(args: Dictionary, editor_interface: Variant = null) -> Dictionary:
	var raw_path: String = str(args.get("path", "")).strip_edges()
	var v: Dictionary = _validate_readonly_res_path(raw_path, false)
	if not bool(v.get("ok", false)):
		return {"ok": false, "tool": "read_script_slice", "error": str(v.get("error", "Invalid path."))}
	var clean_path: String = str(v.get("path", ""))
	var ed: EditorInterface = editor_interface as EditorInterface if editor_interface is EditorInterface else null
	var text: String = ""
	if clean_path.to_lower().ends_with(".gd"):
		text = read_live_script_text(clean_path, ed)
	if text.is_empty():
		if not FileAccess.file_exists(clean_path):
			return {"ok": false, "tool": "read_script_slice", "error": "File not found: " + clean_path}
		text = FileAccess.get_file_as_string(clean_path)
	var lines: PackedStringArray = text.split("\n")
	if lines.size() > 1 and lines[lines.size() - 1].is_empty():
		lines = lines.slice(0, lines.size() - 1)
	var total_lines: int = lines.size()
	if total_lines == 0:
		return {
			"ok": true,
			"tool": "read_script_slice",
			"path": clean_path,
			"startLine": 1,
			"endLine": 0,
			"totalLines": 0,
			"truncated": false,
			"content": "",
		}
	var start_line: int = maxi(1, int(args.get("startLine", args.get("start_line", 1))))
	var req_end: int = int(args.get("endLine", args.get("end_line", start_line + 119)))
	if req_end < start_line:
		req_end = start_line
	if req_end - start_line + 1 > 200:
		req_end = start_line + 199
	start_line = clampi(start_line, 1, total_lines)
	var end_line: int = clampi(req_end, start_line, total_lines)
	var slice_lines: PackedStringArray = lines.slice(start_line - 1, end_line)
	return {
		"ok": true,
		"tool": "read_script_slice",
		"path": clean_path,
		"startLine": start_line,
		"endLine": end_line,
		"totalLines": total_lines,
		"truncated": start_line > 1 or end_line < total_lines,
		"content": "\n".join(slice_lines),
	}


func tool_inspect_scene_tree(args: Dictionary, editor_interface: Variant = null) -> Dictionary:
	var raw_path: String = str(args.get("path", "")).strip_edges()
	var v: Dictionary = _validate_readonly_res_path(raw_path, false)
	if not bool(v.get("ok", false)):
		return {"ok": false, "tool": "inspect_scene_tree", "error": str(v.get("error", "Invalid path."))}
	var clean_path: String = str(v.get("path", ""))
	if not clean_path.to_lower().ends_with(".tscn") and not clean_path.to_lower().ends_with(".scn"):
		return {"ok": false, "tool": "inspect_scene_tree", "error": "Expected a .tscn or .scn file."}
	if not FileAccess.file_exists(clean_path):
		return {"ok": false, "tool": "inspect_scene_tree", "error": "Scene file not found: " + clean_path}

	var base_scene_path: String = ""
	if clean_path.to_lower().ends_with(".tscn"):
		var tscn_text: String = FileAccess.get_file_as_string(clean_path)
		var ext_scenes: Dictionary = {}
		var saw_first_node: bool = false
		for raw_line: String in tscn_text.split("\n"):
			var trimmed: String = raw_line.strip_edges()
			if trimmed.begins_with("[ext_resource "):
				if _extract_quoted_attr(trimmed, "type") == "PackedScene":
					var ext_id: String = _extract_quoted_attr(trimmed, "id")
					var ext_path: String = _extract_quoted_attr(trimmed, "path")
					if not ext_id.is_empty() and not ext_path.is_empty():
						ext_scenes[ext_id] = ext_path
			elif trimmed.begins_with("[node ") and not saw_first_node:
				saw_first_node = true
				if _extract_quoted_attr(trimmed, "parent").is_empty():
					var inst_token_idx: int = trimmed.find("instance=ExtResource(\"")
					if inst_token_idx >= 0:
						var id_start: int = inst_token_idx + 22
						var id_end: int = trimmed.find("\"", id_start)
						if id_end > id_start:
							var ref_id: String = trimmed.substr(id_start, id_end - id_start)
							base_scene_path = str(ext_scenes.get(ref_id, ""))

	var ed: EditorInterface = editor_interface as EditorInterface if editor_interface is EditorInterface else null
	var root: Node = null
	var owns_root: bool = false
	if ed != null:
		var open_roots: Dictionary = _get_open_scene_roots_by_path(ed)
		if open_roots.has(clean_path):
			var open_val: Variant = open_roots.get(clean_path)
			if open_val is Node:
				root = open_val as Node
	if root == null:
		var loaded_res: Resource = ResourceLoader.load(clean_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var packed: PackedScene = loaded_res as PackedScene
		if packed == null:
			return {"ok": false, "tool": "inspect_scene_tree", "error": "Failed to load PackedScene: " + clean_path}
		root = packed.instantiate()
		owns_root = true
	if root == null:
		return {"ok": false, "tool": "inspect_scene_tree", "error": "Failed to instantiate scene: " + clean_path}

	var limit_nodes: int = clampi(int(args.get("limitNodes", 140)), 1, 300)
	var nodes: Array[Dictionary] = []
	var stack: Array[Node] = [root]
	var truncated: bool = false
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if nodes.size() >= limit_nodes:
			truncated = true
			break
		var node_path: String = "." if cur == root else str(root.get_path_to(cur))
		var scr: Script = cur.get_script() as Script
		var scr_path: String = scr.resource_path if scr != null else ""
		var inst_file: String = cur.scene_file_path
		var is_instanced: bool = (cur != root) and not inst_file.is_empty()
		var entry: Dictionary = {
			"path": node_path,
			"name": str(cur.name),
			"class": cur.get_class(),
			"isInstancedScene": is_instanced,
		}
		if not scr_path.is_empty():
			entry["script"] = scr_path
		if is_instanced:
			entry["sceneFilePath"] = inst_file
		if "collision_layer" in cur:
			entry["collisionLayer"] = int(cur.get("collision_layer"))
			entry["collisionMask"] = int(cur.get("collision_mask"))
		nodes.append(entry)
		var child_count: int = cur.get_child_count()
		for i: int in range(child_count - 1, -1, -1):
			stack.append(cur.get_child(i))

	if owns_root and is_instance_valid(root):
		root.free()

	return {
		"ok": true,
		"tool": "inspect_scene_tree",
		"path": clean_path,
		"baseScenePath": base_scene_path,
		"nodeCount": nodes.size(),
		"truncated": truncated,
		"nodes": nodes,
	}


func tool_read_autoloads_and_layers(_args: Dictionary = {}) -> Dictionary:
	var autoloads: Dictionary = {}
	var layer_names: Dictionary = {}
	if FileAccess.file_exists("res://project.godot"):
		var cfg: ConfigFile = ConfigFile.new()
		if cfg.load("res://project.godot") == OK:
			if cfg.has_section("autoload"):
				for key: String in cfg.get_section_keys("autoload"):
					var raw_val: String = str(cfg.get_value("autoload", key, "")).strip_edges()
					if raw_val.begins_with("*"):
						raw_val = raw_val.substr(1)
					autoloads[key] = raw_val
			if cfg.has_section("layer_names"):
				for key: String in cfg.get_section_keys("layer_names"):
					layer_names[key] = str(cfg.get_value("layer_names", key, ""))
	return {
		"ok": true,
		"tool": "read_autoloads_and_layers",
		"autoloads": autoloads,
		"layerNames": layer_names,
	}


func tool_inspect_tres_resource(args: Dictionary) -> Dictionary:
	var raw_path: String = str(args.get("path", "")).strip_edges()
	var v: Dictionary = _validate_readonly_res_path(raw_path, false)
	if not bool(v.get("ok", false)):
		return {"ok": false, "tool": "inspect_tres_resource", "error": str(v.get("error", "Invalid path."))}
	var clean_path: String = str(v.get("path", ""))
	if not clean_path.to_lower().ends_with(".tres"):
		return {"ok": false, "tool": "inspect_tres_resource", "error": "Expected a .tres resource file."}
	if not FileAccess.file_exists(clean_path):
		return {"ok": false, "tool": "inspect_tres_resource", "error": "Resource file not found: " + clean_path}

	var text: String = FileAccess.get_file_as_string(clean_path)
	var resource_type: String = ""
	var script_class: String = ""
	var script_path: String = ""
	var ext_scripts: Dictionary = {}
	var properties: Dictionary = {}
	var section: String = ""
	for raw_line: String in text.split("\n"):
		var trimmed: String = raw_line.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with(";"):
			continue
		if trimmed.begins_with("[gd_resource "):
			resource_type = _extract_quoted_attr(trimmed, "type")
			script_class = _extract_quoted_attr(trimmed, "script_class")
			section = ""
		elif trimmed.begins_with("[ext_resource "):
			if _extract_quoted_attr(trimmed, "type") == "Script":
				var ext_id: String = _extract_quoted_attr(trimmed, "id")
				var ext_p: String = _extract_quoted_attr(trimmed, "path")
				if not ext_id.is_empty() and not ext_p.is_empty():
					ext_scripts[ext_id] = ext_p
			section = ""
		elif trimmed.begins_with("["):
			section = "resource" if trimmed == "[resource]" else ""
		elif section == "resource":
			var eq_idx: int = trimmed.find("=")
			if eq_idx > 0:
				var prop_key: String = trimmed.substr(0, eq_idx).strip_edges()
				var prop_val: String = trimmed.substr(eq_idx + 1).strip_edges()
				if prop_key == "script":
					var ext_tok: int = prop_val.find("ExtResource(\"")
					if ext_tok >= 0:
						var id_s: int = ext_tok + 13
						var id_e: int = prop_val.find("\"", id_s)
						if id_e > id_s:
							script_path = str(ext_scripts.get(prop_val.substr(id_s, id_e - id_s), ""))
				if properties.size() < 40:
					properties[prop_key] = prop_val.substr(0, 160)

	return {
		"ok": true,
		"tool": "inspect_tres_resource",
		"path": clean_path,
		"resourceType": resource_type,
		"scriptClass": script_class,
		"scriptPath": script_path,
		"properties": properties,
	}


func execute_agent_tool_call(tool_call: Dictionary, editor_interface: Variant = null) -> Dictionary:
	var tool_name: String = str(tool_call.get("tool", tool_call.get("name", ""))).strip_edges()
	if not _READONLY_AGENT_TOOLS.has(tool_name):
		return {
			"ok": false,
			"tool": tool_name,
			"error": "Tool not allowed (read-only allowlist only): " + tool_name,
		}
	var raw_args: Variant = tool_call.get("args", tool_call.get("arguments", {}))
	var args: Dictionary = raw_args if typeof(raw_args) == TYPE_DICTIONARY else {}
	match tool_name:
		"list_project_files":
			return tool_list_project_files(args)
		"grep_project_text":
			return tool_grep_project_text(args, editor_interface)
		"read_script_slice":
			return tool_read_script_slice(args, editor_interface)
		"inspect_scene_tree":
			return tool_inspect_scene_tree(args, editor_interface)
		"read_autoloads_and_layers":
			return tool_read_autoloads_and_layers(args)
		"inspect_tres_resource":
			return tool_inspect_tres_resource(args)
	return {"ok": false, "tool": tool_name, "error": "Unknown tool: " + tool_name}


