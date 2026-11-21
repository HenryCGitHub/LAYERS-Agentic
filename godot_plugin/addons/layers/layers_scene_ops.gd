@tool
extends RefCounted

# Scene/Node/.tscn/.tres creation, build protection & signal wiring helpers
# for LAYERS Godot 4 Editor Plugin.

var _exec: Variant = null


func _init(exec_ref: Variant = null) -> void:
	_exec = exec_ref


func invalidate_eval_cache() -> void:
	if _exec != null:
		_exec.call("invalidate_eval_cache")
		return
	pass


func reload_script_safely(rpath: String, source_code: String = "") -> Script:
	if _exec != null:
		return _exec.call("reload_script_safely", rpath, source_code) as Script
	var res: Variant = ResourceLoader.load(rpath, "", ResourceLoader.CACHE_MODE_IGNORE)
	return res as Script if res is Script else null


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
