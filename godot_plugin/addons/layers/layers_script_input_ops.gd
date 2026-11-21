@tool
extends RefCounted

# GDScript patching, @export preservation, live tuning & InputMap operations
# for LAYERS Godot 4 Editor Plugin.

var _exec: Variant = null
var _last_healed_proj_mtime: int = -1


func _init(exec_ref: Variant = null) -> void:
	_exec = exec_ref


func reset_healed_proj_mtime() -> void:
	_last_healed_proj_mtime = -1


func invalidate_eval_cache() -> void:
	if _exec != null:
		_exec.call("invalidate_eval_cache")
		return
	pass


func check_gdscript_compiles(code: String) -> Dictionary:
	if _exec != null:
		return _exec.call("check_gdscript_compiles", code) as Dictionary
	var g := GDScript.new()
	g.source_code = code
	var err: int = g.reload(false)
	return {"ok": err == OK, "errors": [] if err == OK else ["GDScript compile error (%d)" % err]}


func _ensure_dir_for_res_path(res_path: String) -> void:
	if _exec != null:
		_exec.call("_ensure_dir_for_res_path", res_path)
		return
	var abs_d := ProjectSettings.globalize_path(res_path.get_base_dir())
	if not abs_d.is_empty() and not DirAccess.dir_exists_absolute(abs_d):
		DirAccess.make_dir_recursive_absolute(abs_d)


func _get_open_scene_roots_by_path(editor_interface: EditorInterface) -> Dictionary:
	if _exec != null:
		return _exec.call("_get_open_scene_roots_by_path", editor_interface) as Dictionary
	return {}


func _save_disk_scene_root(scene_root: Node, scene_path: String) -> bool:
	if _exec != null:
		return _exec.call("_save_disk_scene_root", scene_root, scene_path) as bool
	return false


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
