@tool
extends RefCounted

# Coordinator facade for Hierarchy-aware Scene, InputMap, Signal, and GDScript execution
# in LAYERS Godot 4 Editor Plugin (v4.2.0+).

const READONLY_TOOLS_PATH := "res://addons/layers/layers_readonly_tools.gd"
const SCRIPT_INPUT_OPS_PATH := "res://addons/layers/layers_script_input_ops.gd"
const SCENE_OPS_PATH := "res://addons/layers/layers_scene_ops.gd"
const PROJECT_DIAGNOSTICS_PATH := "res://addons/layers/layers_project_diagnostics.gd"

var _readonly_tools: RefCounted = null
var _script_input_ops: RefCounted = null
var _scene_ops: RefCounted = null
var _diagnostics: RefCounted = null


func _load_fresh_module(res_path: String) -> Script:
	if not FileAccess.file_exists(res_path):
		return null
	var disk_code: String = FileAccess.get_file_as_string(res_path)
	if disk_code.strip_edges().is_empty():
		return null
	if ResourceLoader.has_cached(res_path):
		var cached: Variant = ResourceLoader.load(res_path)
		if cached is GDScript:
			var cached_gds: GDScript = cached as GDScript
			cached_gds.source_code = disk_code
			if cached_gds.reload(true) == OK:
				return cached_gds
	var fresh: Variant = ResourceLoader.load(res_path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
	if fresh is GDScript:
		return fresh as Script
	var fallback: Variant = load(res_path)
	return fallback as Script if fallback is Script else null


func _init() -> void:
	var ro_scr: Script = _load_fresh_module(READONLY_TOOLS_PATH)
	if ro_scr != null:
		_readonly_tools = ro_scr.new(self)
	var sio_scr: Script = _load_fresh_module(SCRIPT_INPUT_OPS_PATH)
	if sio_scr != null:
		_script_input_ops = sio_scr.new(self)
	var sc_scr: Script = _load_fresh_module(SCENE_OPS_PATH)
	if sc_scr != null:
		_scene_ops = sc_scr.new(self)
	var diag_scr: Script = _load_fresh_module(PROJECT_DIAGNOSTICS_PATH)
	if diag_scr != null:
		_diagnostics = diag_scr.new(self)


func _reset_healed_proj_mtime() -> void:
	if _script_input_ops != null:
		_script_input_ops.call("reset_healed_proj_mtime")


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


func format_compile_error_entry(code: String, rationale: String, file: String = "", line: int = 0) -> String:
	return _diagnostics.call("format_compile_error_entry", code, rationale, file, line) as String



func invalidate_eval_cache() -> void:
	_diagnostics.call("invalidate_eval_cache")


func _compute_live_tree_signature(root: Node) -> String:
	return _diagnostics.call("_compute_live_tree_signature", root) as String


func _build_eval_cache_key( feat: Dictionary, primary_scene: String, script_paths: Array, arena_hint: String, code_files_count: int, editor_root: Node ) -> String:
	return _diagnostics.call("_build_eval_cache_key", feat, primary_scene, script_paths, arena_hint, code_files_count, editor_root) as String


func resolve_effective_step_path(step: Dictionary, feat: Dictionary) -> String:
	return _script_input_ops.call("resolve_effective_step_path", step, feat) as String


func _find_mentioned_existing_gd(step: Dictionary) -> String:
	return _script_input_ops.call("_find_mentioned_existing_gd", step) as String


func _is_non_gdscript_diagram_line(line: String) -> bool:
	return _script_input_ops.call("_is_non_gdscript_diagram_line", line) as bool


func is_likely_gdscript_snippet(raw_text: String) -> bool:
	return _script_input_ops.call("is_likely_gdscript_snippet", raw_text) as bool


func resolve_step_code_text(step: Dictionary) -> String:
	return _script_input_ops.call("resolve_step_code_text", step) as String


func strip_diff_prefixes(raw: String) -> String:
	return _script_input_ops.call("strip_diff_prefixes", raw) as String


func _parse_vector3_literal(raw: String) -> Variant:
	return _scene_ops.call("_parse_vector3_literal", raw)


func _parse_vector2_literal(raw: String) -> Variant:
	return _scene_ops.call("_parse_vector2_literal", raw)


func parse_input_specs(step: Dictionary) -> Array:
	return _script_input_ops.call("parse_input_specs", step) as Array


func open_res_path(editor_interface: EditorInterface, res_path: String, line_number: int = -1) -> String:
	return _script_input_ops.call("open_res_path", editor_interface, res_path, line_number) as String


func _resolve_issue_file_candidate( raw_token: String, known_by_file: Dictionary, scanned_by_file: Dictionary ) -> String:
	return _diagnostics.call("_resolve_issue_file_candidate", raw_token, known_by_file, scanned_by_file) as String


func extract_issue_jump_targets( issue_items: Array, known_paths: PackedStringArray = PackedStringArray() ) -> Array:
	return _diagnostics.call("extract_issue_jump_targets", issue_items, known_paths) as Array


func extract_issue_jump_target( issue_text: String, known_paths: PackedStringArray = PackedStringArray() ) -> Dictionary:
	return _diagnostics.call("extract_issue_jump_target", issue_text, known_paths) as Dictionary


func _resolve_node_by_rel_path(root: Node, rel_path: String) -> Node:
	return _scene_ops.call("_resolve_node_by_rel_path", root, rel_path) as Node


func _find_node_recursive(root: Node, target_name: String) -> Node:
	return _scene_ops.call("_find_node_recursive", root, target_name) as Node


func _find_instanced_scene_node(root: Node, scene_path: String) -> Node:
	return _scene_ops.call("_find_instanced_scene_node", root, scene_path) as Node


func _has_real_input_binding(act_name: String, setting_key: String) -> bool:
	return _script_input_ops.call("_has_real_input_binding", act_name, setting_key) as bool


func _match_single_input_token(raw_tok: String) -> InputEvent:
	return _script_input_ops.call("_match_single_input_token", raw_tok) as InputEvent


func _build_input_event_for_label(key_label: String) -> InputEvent:
	return _script_input_ops.call("_build_input_event_for_label", key_label) as InputEvent


func _infer_default_input_event_for_action(act_name: String) -> InputEvent:
	return _script_input_ops.call("_infer_default_input_event_for_action", act_name) as InputEvent


func _is_bogus_non_player_action_name(act_name: String) -> bool:
	return _script_input_ops.call("_is_bogus_non_player_action_name", act_name) as bool


func apply_input_ops(input_ops: Array) -> int:
	return _script_input_ops.call("apply_input_ops", input_ops) as int


func register_missing_script_input_actions(script_contents: Array) -> int:
	return _script_input_ops.call("register_missing_script_input_actions", script_contents) as int


func heal_empty_project_input_actions(feat: Dictionary = {}) -> int:
	return _script_input_ops.call("heal_empty_project_input_actions", feat) as int


func reload_script_safely(rpath: String, source_code: String = "") -> Script:
	return _script_input_ops.call("reload_script_safely", rpath, source_code) as Script


func sanitize_null_script_exports(scene_root: Node) -> int:
	return _script_input_ops.call("sanitize_null_script_exports", scene_root) as int


func _project_prefers_2d(arena_hint: String = "", dimension_hint: String = "") -> bool:
	return _scene_ops.call("_project_prefers_2d", arena_hint, dimension_hint) as bool


func infer_scene_root_type(scene_path: String, root_type_hint: String = "", arena_hint: String = "", dimension_hint: String = "") -> String:
	return _scene_ops.call("infer_scene_root_type", scene_path, root_type_hint, arena_hint, dimension_hint) as String


func _should_upgrade_root_type(cur_root: Node, desired_type: String) -> bool:
	return _scene_ops.call("_should_upgrade_root_type", cur_root, desired_type) as bool


func _clear_owner_for_root(node: Node, target_owner: Node) -> void:
	_scene_ops.call("_clear_owner_for_root", node, target_owner)


func _unset_subtree_owners(node: Node) -> void:
	_scene_ops.call("_unset_subtree_owners", node)


func _reown_subtree(node: Node, old_owner: Node, new_owner: Node) -> void:
	_scene_ops.call("_reown_subtree", node, old_owner, new_owner)


func upgrade_scene_root_type_on_disk( scene_path: String, desired_type: String, editor_interface: EditorInterface = null ) -> bool:
	return _scene_ops.call("upgrade_scene_root_type_on_disk", scene_path, desired_type, editor_interface) as bool


func ensure_scene_exists_and_open( editor_interface: EditorInterface, scene_path: String, root_type_hint: String = "", root_name_hint: String = "", arena_hint: String = "", dimension_hint: String = "" ) -> Node:
	return _scene_ops.call("ensure_scene_exists_and_open", editor_interface, scene_path, root_type_hint, root_name_hint, arena_hint, dimension_hint) as Node


func ensure_main_scene_configured(arena_scene: String, fallback_scene: String = "") -> bool:
	return _scene_ops.call("ensure_main_scene_configured", arena_scene, fallback_scene) as bool


func ensure_project_file_logging() -> void:
	_diagnostics.call("ensure_project_file_logging")


func _is_ignored_godot_error_noise(text: String) -> bool:
	return _diagnostics.call("_is_ignored_godot_error_noise", text) as bool


func _is_debugger_errors_tree(err_tree: Tree, dbg_root: Node) -> bool:
	return _diagnostics.call("_is_debugger_errors_tree", err_tree, dbg_root) as bool


func read_recent_godot_log_errors(since_unix_sec: float = 0.0, max_errors: int = 3) -> Array:
	return _diagnostics.call("read_recent_godot_log_errors", since_unix_sec, max_errors) as Array


func _get_editor_error_ui_roots(base_control: Node) -> Dictionary:
	return _diagnostics.call("_get_editor_error_ui_roots", base_control) as Dictionary


func read_editor_and_playtest_errors( base_control: Node, extra_logger_errors: Array = [], ignored_signatures: Dictionary = {}, since_unix_sec: float = 0.0, max_errors: int = 3, warning_icon: Texture2D = null ) -> Array:
	return _diagnostics.call("read_editor_and_playtest_errors", base_control, extra_logger_errors, ignored_signatures, since_unix_sec, max_errors, warning_icon) as Array


func _is_abstract_subresource_class(cls_name: String) -> bool:
	return _scene_ops.call("_is_abstract_subresource_class", cls_name) as bool


func _apply_material_dict_to_node(node: Node, mat_props: Dictionary) -> bool:
	return _scene_ops.call("_apply_material_dict_to_node", node, mat_props) as bool


func _coerce_prop_value(val: Variant, prop_name: String = "") -> Variant:
	return _scene_ops.call("_coerce_prop_value", val, prop_name)


func _is_physics_or_rig_node(node: Node, node_type_hint: String = "", node_name_hint: String = "") -> bool:
	return _scene_ops.call("_is_physics_or_rig_node", node, node_type_hint, node_name_hint) as bool


func _has_custom_asset_resource(res: Variant) -> bool:
	return _scene_ops.call("_has_custom_asset_resource", res) as bool


func _is_instanced_scene_node(scene_root: Node, node: Node) -> bool:
	return _scene_ops.call("_is_instanced_scene_node", scene_root, node) as bool


func _is_internal_instanced_child(scene_root: Node, node: Node) -> bool:
	return _scene_ops.call("_is_internal_instanced_child", scene_root, node) as bool


func _is_hand_tuned_collision_prop(node: Node, prop_name: String) -> bool:
	return _scene_ops.call("_is_hand_tuned_collision_prop", node, prop_name) as bool


func _sync_existing_node_from_spec( node: Node, sp: Dictionary, preserve_existing_visuals: bool = false ) -> bool:
	return _scene_ops.call("_sync_existing_node_from_spec", node, sp, preserve_existing_visuals) as bool


func extract_script_extends(code: String) -> String:
	return _scene_ops.call("extract_script_extends", code) as String


func can_attach_script_to_node(node: Node, code_or_res_path: String) -> bool:
	return _scene_ops.call("can_attach_script_to_node", node, code_or_res_path) as bool


func detach_incompatible_scripts(scene_root: Node) -> PackedStringArray:
	return _scene_ops.call("detach_incompatible_scripts", scene_root) as PackedStringArray


func check_gdscript_compiles(code: String) -> Dictionary:
	return _diagnostics.call("check_gdscript_compiles", code) as Dictionary


func _script_defines_method(node: Node, method_name: String) -> bool:
	return _scene_ops.call("_script_defines_method", node, method_name) as bool


func _split_top_level_csv(raw: String) -> PackedStringArray:
	return _scene_ops.call("_split_top_level_csv", raw) as PackedStringArray


func _read_node_script_source(node: Node) -> String:
	return _scene_ops.call("_read_node_script_source", node) as String


func _extract_balanced_paren_inner(src: String, start_after_open_paren: int) -> String:
	return _scene_ops.call("_extract_balanced_paren_inner", src, start_after_open_paren) as String


func _get_signal_arity(src_node: Node, sig_name: String) -> int:
	return _scene_ops.call("_get_signal_arity", src_node, sig_name) as int


func _get_method_arity_range(tgt_node: Node, method_name: String) -> Vector2i:
	return _scene_ops.call("_get_method_arity_range", tgt_node, method_name) as Vector2i


func _resolve_signal_receiver_node(scene_root: Node, src_node: Node, target_hint: String, method_name: String) -> Node:
	return _scene_ops.call("_resolve_signal_receiver_node", scene_root, src_node, target_hint, method_name) as Node


func _disconnect_invalid_self_signal(src_node: Node, sig_name: String, method_name: String) -> bool:
	return _scene_ops.call("_disconnect_invalid_self_signal", src_node, sig_name, method_name) as bool


func _connect_single_signal_safe( scene_root: Node, src_hint: String, sig_name: String, target_hint: String, method_name: String ) -> Dictionary:
	return _scene_ops.call("_connect_single_signal_safe", scene_root, src_hint, sig_name, target_hint, method_name) as Dictionary


func resolve_feature_paths(feat: Dictionary, code_files: Dictionary = {}, arena_hint: String = "") -> Dictionary:
	return _diagnostics.call("resolve_feature_paths", feat, code_files, arena_hint) as Dictionary


func _collect_attached_script_paths(root_node: Node) -> Dictionary:
	return _diagnostics.call("_collect_attached_script_paths", root_node) as Dictionary


func _collect_tscn_script_paths_from_disk(scene_path: String) -> Dictionary:
	return _diagnostics.call("_collect_tscn_script_paths_from_disk", scene_path) as Dictionary


func evaluate_feature( feat: Dictionary, editor_interface: EditorInterface, code_files: Dictionary = {}, arena_hint: String = "" ) -> Dictionary:
	return _diagnostics.call("evaluate_feature", feat, editor_interface, code_files, arena_hint) as Dictionary


func _leading_indent(line: String) -> String:
	return _script_input_ops.call("_leading_indent", line) as String


func _reindent_patch_line(line: String, find_base: String, target_base: String, space_unit: int) -> String:
	return _script_input_ops.call("_reindent_patch_line", line, find_base, target_base, space_unit) as String


func apply_script_patches(existing_text: String, patches: Array) -> Dictionary:
	return _script_input_ops.call("apply_script_patches", existing_text, patches) as Dictionary


func _escape_regex_literal(raw: String) -> String:
	return _script_input_ops.call("_escape_regex_literal", raw) as String


func _script_declares_export_var(script_text: String, var_name: String) -> bool:
	return _script_input_ops.call("_script_declares_export_var", script_text, var_name) as bool


func find_dropped_preserved_exports(existing_text: String, next_text: String, preserve_exports: Array) -> PackedStringArray:
	return _script_input_ops.call("find_dropped_preserved_exports", existing_text, next_text, preserve_exports) as PackedStringArray


func _resolve_op_node(scene_root: Node, rel_or_name: String) -> Node:
	return _scene_ops.call("_resolve_op_node", scene_root, rel_or_name) as Node


func _apply_groups_to_node(node: Node, raw_groups: Variant) -> int:
	return _scene_ops.call("_apply_groups_to_node", node, raw_groups) as int


func _load_or_create_disk_scene_root( scene_path: String, root_type_hint: String = "", root_name_hint: String = "", arena_hint: String = "", dimension_hint: String = "" ) -> Node:
	return _scene_ops.call("_load_or_create_disk_scene_root", scene_path, root_type_hint, root_name_hint, arena_hint, dimension_hint) as Node


func _save_disk_scene_root(scene_root: Node, scene_path: String) -> bool:
	return _scene_ops.call("_save_disk_scene_root", scene_root, scene_path) as bool


func apply_scene_ops_to_root( scene_root: Node, ops: Array, warnings: PackedStringArray = PackedStringArray(), preserve_existing_visuals: bool = false ) -> int:
	return _scene_ops.call("apply_scene_ops_to_root", scene_root, ops, warnings, preserve_existing_visuals) as int


func _scan_project_files_by_ext(root_dir: String, ext: String, cap: int = 80) -> PackedStringArray:
	return _script_input_ops.call("_scan_project_files_by_ext", root_dir, ext, cap) as PackedStringArray


func collect_project_scene_paths(root_dir: String = "res://", max_scenes: int = 120) -> PackedStringArray:
	return _script_input_ops.call("collect_project_scene_paths", root_dir, max_scenes) as PackedStringArray


func merge_script_buffer_overrides(disk_scripts: Dictionary, buffer_overrides: Dictionary) -> Dictionary:
	return _script_input_ops.call("merge_script_buffer_overrides", disk_scripts, buffer_overrides) as Dictionary


func collect_open_script_editor_buffers(editor_interface: EditorInterface) -> Dictionary:
	return _script_input_ops.call("collect_open_script_editor_buffers", editor_interface) as Dictionary


func _sync_open_script_editor_after_disk_write( editor_interface: EditorInterface, res_path: String, new_text: String ) -> void:
	_script_input_ops.call("_sync_open_script_editor_after_disk_write", editor_interface, res_path, new_text)


func _reload_open_script_editors(editor_interface: EditorInterface) -> void:
	_script_input_ops.call("_reload_open_script_editors", editor_interface)


func read_live_script_text(res_path: String, editor_interface: EditorInterface = null) -> String:
	return _script_input_ops.call("read_live_script_text", res_path, editor_interface) as String


func read_all_live_project_scripts(root_dir: String = "res://", editor_interface: EditorInterface = null) -> Dictionary:
	return _script_input_ops.call("read_all_live_project_scripts", root_dir, editor_interface) as Dictionary


func read_scoped_project_scripts( priority_paths: Array = [], root_dir: String = "res://", editor_interface: EditorInterface = null, max_scripts: int = 16 ) -> Dictionary:
	return _script_input_ops.call("read_scoped_project_scripts", priority_paths, root_dir, editor_interface, max_scripts) as Dictionary


func _get_open_scene_roots_by_path(editor_interface: EditorInterface) -> Dictionary:
	return _scene_ops.call("_get_open_scene_roots_by_path", editor_interface) as Dictionary


func _round_vec3(v: Vector3) -> Array:
	return _scene_ops.call("_round_vec3", v) as Array


func _round_vec2(v: Vector2) -> Array:
	return _scene_ops.call("_round_vec2", v) as Array


func _snapshot_node_tree(root: Node, limit_nodes: int = 140) -> Array:
	return _scene_ops.call("_snapshot_node_tree", root, limit_nodes) as Array


func _describe_input_event(ev: InputEvent) -> String:
	return _script_input_ops.call("_describe_input_event", ev) as String


func capture_input_map_snapshot() -> Dictionary:
	return _script_input_ops.call("capture_input_map_snapshot") as Dictionary


func _strip_gd_comment(line: String) -> String:
	return _diagnostics.call("_strip_gd_comment", line) as String


func _script_has_standalone_root_rotation(src: String) -> bool:
	return _diagnostics.call("_script_has_standalone_root_rotation", src) as bool


func _detect_rotated_visual_child(src: String) -> Dictionary:
	return _diagnostics.call("_detect_rotated_visual_child", src) as Dictionary


func _is_non_player_entity_script(script_path: String, src: String) -> bool:
	return _diagnostics.call("_is_non_player_entity_script", script_path, src) as bool


func _detect_silent_take_damage(src: String) -> bool:
	return _diagnostics.call("_detect_silent_take_damage", src) as bool


func diagnose_project_combat_and_wiring( scene_paths: Array = [], live_scripts: Dictionary = {}, editor_interface: EditorInterface = null ) -> PackedStringArray:
	return _diagnostics.call("diagnose_project_combat_and_wiring", scene_paths, live_scripts, editor_interface) as PackedStringArray


func verify_built_feature_integrity( editor_interface: EditorInterface, feat: Dictionary, code_files: Dictionary = {}, arena_hint: String = "" ) -> Dictionary:
	return _diagnostics.call("verify_built_feature_integrity", editor_interface, feat, code_files, arena_hint) as Dictionary


func capture_rich_scene_snapshot(editor_interface: EditorInterface, extra_scene_paths: PackedStringArray = PackedStringArray()) -> Dictionary:
	return _scene_ops.call("capture_rich_scene_snapshot", editor_interface, extra_scene_paths) as Dictionary


func _ensure_dir_for_res_path(res_path: String) -> void:
	_scene_ops.call("_ensure_dir_for_res_path", res_path)


func _format_tuning_literal_for_type(raw_val: String, unit_str: String, type_hint: String) -> Dictionary:
	return _script_input_ops.call("_format_tuning_literal_for_type", raw_val, unit_str, type_hint) as Dictionary


func _node_has_script_property(node: Node, prop_key: String) -> bool:
	return _script_input_ops.call("_node_has_script_property", node, prop_key) as bool


func apply_live_export_tuning( editor_interface: EditorInterface, key: String, raw_value: String, unit: String = "", preferred_scene: String = "" ) -> Dictionary:
	return _script_input_ops.call("apply_live_export_tuning", editor_interface, key, raw_value, unit, preferred_scene) as Dictionary


func _extract_quoted_attr(header_line: String, attr_name: String) -> String:
	return _readonly_tools.call("_extract_quoted_attr", header_line, attr_name) as String


func _validate_readonly_res_path(raw_path: String, allow_root_dir: bool = false) -> Dictionary:
	return _readonly_tools.call("_validate_readonly_res_path", raw_path, allow_root_dir) as Dictionary


func _collect_readonly_files(root_dir: String, ext_filter: String = "", cap: int = 80) -> Dictionary:
	return _readonly_tools.call("_collect_readonly_files", root_dir, ext_filter, cap) as Dictionary


func tool_list_project_files(args: Dictionary) -> Dictionary:
	return _readonly_tools.call("tool_list_project_files", args) as Dictionary


func tool_grep_project_text(args: Dictionary, editor_interface: Variant = null) -> Dictionary:
	return _readonly_tools.call("tool_grep_project_text", args, editor_interface) as Dictionary


func tool_read_script_slice(args: Dictionary, editor_interface: Variant = null) -> Dictionary:
	return _readonly_tools.call("tool_read_script_slice", args, editor_interface) as Dictionary


func tool_inspect_scene_tree(args: Dictionary, editor_interface: Variant = null) -> Dictionary:
	return _readonly_tools.call("tool_inspect_scene_tree", args, editor_interface) as Dictionary


func tool_read_autoloads_and_layers(_args: Dictionary = {}) -> Dictionary:
	return _readonly_tools.call("tool_read_autoloads_and_layers", _args) as Dictionary


func tool_inspect_tres_resource(args: Dictionary) -> Dictionary:
	return _readonly_tools.call("tool_inspect_tres_resource", args) as Dictionary


func execute_agent_tool_call(tool_call: Dictionary, editor_interface: Variant = null) -> Dictionary:
	return _readonly_tools.call("execute_agent_tool_call", tool_call, editor_interface) as Dictionary
