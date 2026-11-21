@tool
extends RefCounted

# Read-only project/scene/script inspection tools for multi_turn_v1 Cloud Agent
# in LAYERS Godot 4 Editor Plugin.

const _READONLY_AGENT_TOOLS := {
	"list_project_files": true,
	"grep_project_text": true,
	"read_script_slice": true,
	"inspect_scene_tree": true,
	"read_autoloads_and_layers": true,
	"inspect_tres_resource": true,
}

var _exec: Variant = null


func _init(exec_ref: Variant = null) -> void:
	_exec = exec_ref


func read_live_script_text(res_path: String, editor_interface: EditorInterface = null) -> String:
	if _exec != null:
		return _exec.call("read_live_script_text", res_path, editor_interface) as String
	if FileAccess.file_exists(res_path):
		return FileAccess.get_file_as_string(res_path)
	return ""


func _get_open_scene_roots_by_path(editor_interface: EditorInterface) -> Dictionary:
	if _exec != null:
		return _exec.call("_get_open_scene_roots_by_path", editor_interface) as Dictionary
	return {}


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
