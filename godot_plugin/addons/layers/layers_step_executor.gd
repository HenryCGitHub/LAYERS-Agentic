@tool
extends RefCounted

# Hierarchy-aware Scene, InputMap, Inspector, Signal, and GDScript Step Engine
# for LAYERS Godot 4 Editor Plugin (v2.3.0+).


func resolve_effective_step_path(step: Dictionary, feat: Dictionary, scene_root: Node = null) -> String:
	var p: String = str(step.get("stepPath", "")).strip_edges()
	if p.begins_with("res://"):
		if p.ends_with(".gd") and not FileAccess.file_exists(p):
			var hinted_gd: String = _find_mentioned_existing_gd(step, scene_root)
			if not hinted_gd.is_empty():
				return hinted_gd
		return p
	var primary: String = str(feat.get("primaryAsset", "")).strip_edges()
	if primary.begins_with("res://"):
		return primary
	return "res://scenes/main.tscn"


func _find_mentioned_existing_gd(step: Dictionary, scene_root: Node) -> String:
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
		if scene_root != null:
			var scr_node: Node = _find_node_by_script_filename(scene_root, fname)
			if scr_node != null:
				var scr: Variant = scr_node.get_script()
				if scr is Script:
					return (scr as Script).resource_path
		for cand in candidates:
			if FileAccess.file_exists(cand):
				return cand
	return ""


func _find_node_by_script_filename(root: Node, fname: String) -> Node:
	if root == null:
		return null
	var scr: Variant = root.get_script()
	if scr is Script and (scr as Script).resource_path.get_file() == fname:
		return root
	for child in root.get_children():
		var found: Node = _find_node_by_script_filename(child, fname)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# GDScript Diff Stripping & Surgical Hunk Merging
# ---------------------------------------------------------------------------

func resolve_step_code_text(step: Dictionary) -> String:
	var patch_raw: Variant = step.get("scriptPatch", null)
	if typeof(patch_raw) == TYPE_DICTIONARY:
		var patch_dict: Dictionary = patch_raw
		var rep: String = str(patch_dict.get("replaceBlock", "")).strip_edges()
		if not rep.is_empty():
			return strip_diff_prefixes(rep)
	var snip: String = str(step.get("codeSnippet", "")).strip_edges()
	return strip_diff_prefixes(snip)


func _raw_step_snippet(step: Dictionary) -> String:
	var patch_raw: Variant = step.get("scriptPatch", null)
	if typeof(patch_raw) == TYPE_DICTIONARY:
		var patch_dict: Dictionary = patch_raw
		var rep: String = str(patch_dict.get("replaceBlock", "")).strip_edges()
		if not rep.is_empty():
			return rep
	return str(step.get("codeSnippet", "")).strip_edges()


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


func _has_diff_markers(raw: String) -> bool:
	for line in raw.split("\n"):
		if line.begins_with("+ ") or line == "+":
			return true
	return false


func is_step_code_present(disk_text: String, step: Dictionary) -> bool:
	var clean_disk: String = disk_text.replace("\r\n", "\n")
	var raw: String = _raw_step_snippet(step)
	if raw.is_empty():
		return true

	var target_lines: PackedStringArray = []
	if _has_diff_markers(raw):
		for line in raw.split("\n"):
			if line.begins_with("+ "):
				target_lines.append(line.substr(2))
	else:
		for line in strip_diff_prefixes(raw).split("\n"):
			target_lines.append(line)

	var sig_checks: int = 0
	for raw_l in target_lines:
		var trimmed: String = raw_l.strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#") or trimmed.begins_with("extends ") or trimmed.begins_with("class_name "):
			continue
		if trimmed == "pass" or trimmed == "return":
			continue
		sig_checks += 1
		if trimmed.begins_with("@export var ") or trimmed.begins_with("@onready var ") or trimmed.begins_with("var ") or trimmed.begins_with("const ") or trimmed.begins_with("signal "):
			var decl_head: String = _extract_decl_head(trimmed)
			if not decl_head.is_empty():
				if not (decl_head in clean_disk):
					return false
				continue
		if trimmed.begins_with("func "):
			var fn_head: String = trimmed.split("(", false, 1)[0].strip_edges()
			if not (fn_head in clean_disk):
				return false
			continue
		if not (_normalize_ws(trimmed) in _normalize_ws(clean_disk)):
			return false

	return sig_checks > 0 or (_normalize_ws(strip_diff_prefixes(raw)) in _normalize_ws(clean_disk))


func _extract_decl_head(trimmed: String) -> String:
	var eq_idx: int = trimmed.find("=")
	var head: String = trimmed.substr(0, eq_idx).strip_edges() if eq_idx > 0 else trimmed
	var col_idx: int = head.find(":")
	if col_idx > 0:
		head = head.substr(0, col_idx).strip_edges()
	return head


func _normalize_ws(text: String) -> String:
	var lines: PackedStringArray = []
	for line in text.replace("\r\n", "\n").split("\n"):
		var t: String = line.strip_edges()
		if not t.is_empty():
			lines.append(t)
	return "\n".join(lines)


func merge_step_code_into_existing(existing_text: String, raw_snippet: String, fallback_extends: String = "Node") -> String:
	var current: String = existing_text.replace("\r\n", "\n")
	if current.strip_edges().is_empty():
		var clean_new: String = strip_diff_prefixes(raw_snippet)
		if not ("extends " in clean_new) and not ("class_name " in clean_new):
			clean_new = "extends %s\n\n%s" % [fallback_extends, clean_new]
		return clean_new.strip_edges() + "\n"

	if not _has_diff_markers(raw_snippet):
		var clean_plain: String = strip_diff_prefixes(raw_snippet)
		if clean_plain.is_empty():
			return current
		if clean_plain.begins_with("extends ") or clean_plain.begins_with("class_name "):
			if is_step_code_present(current, {"codeSnippet": raw_snippet}):
				return current
			# Extract declarations / functions not yet in existing
			var split_lines: PackedStringArray = clean_plain.split("\n")
			var body_without_header: PackedStringArray = []
			for l in split_lines:
				if l.begins_with("extends ") or l.begins_with("class_name "):
					continue
				body_without_header.append(l)
			var additions: String = "\n".join(body_without_header).strip_edges()
			if not additions.is_empty() and not (additions in current):
				return current.strip_edges() + "\n\n" + additions + "\n"
			return current
		if not (clean_plain in current):
			return current.strip_edges() + "\n\n" + clean_plain + "\n"
		return current

	# Parse interleaved context + added hunks from `+ ` diff
	var lines: PackedStringArray = raw_snippet.replace("\r\n", "\n").split("\n")
	var hunks: Array = []
	var i: int = 0
	while i < lines.size():
		var line: String = lines[i]
		if line.begins_with("+ ") or line == "+":
			var before_ctx: PackedStringArray = []
			var j: int = i - 1
			while j >= 0 and not lines[j].begins_with("+ ") and lines[j] != "+":
				var trimmed_prev: String = lines[j].strip_edges()
				if not trimmed_prev.is_empty() and not trimmed_prev.begins_with("#"):
					before_ctx.insert(0, lines[j])
					if before_ctx.size() >= 2:
						break
				j -= 1

			var added: PackedStringArray = []
			while i < lines.size() and (lines[i].begins_with("+ ") or lines[i] == "+"):
				added.append(lines[i].substr(2) if lines[i].begins_with("+ ") else "")
				i += 1

			var after_ctx: PackedStringArray = []
			var k: int = i
			while k < lines.size() and not lines[k].begins_with("+ ") and lines[k] != "+":
				var trimmed_next: String = lines[k].strip_edges()
				if not trimmed_next.is_empty() and not trimmed_next.begins_with("#"):
					after_ctx.append(lines[k])
					break
				k += 1

			hunks.append({
				"before": before_ctx,
				"added": added,
				"after": after_ctx,
			})
		else:
			i += 1

	for h_raw in hunks:
		var h: Dictionary = h_raw
		var added_lines: PackedStringArray = h.get("added", PackedStringArray())
		var added_block: String = "\n".join(added_lines).strip_edges(false, true)
		if added_block.strip_edges().is_empty():
			continue
		if _is_block_present(current, added_lines):
			continue

		var before_ctx: PackedStringArray = h.get("before", PackedStringArray())
		var after_ctx: PackedStringArray = h.get("after", PackedStringArray())
		current = _insert_hunk_by_context(current, before_ctx, added_lines, after_ctx)

	return current.strip_edges() + "\n"


func _is_block_present(disk_text: String, added_lines: PackedStringArray) -> bool:
	var dummy_step: Dictionary = {"codeSnippet": "\n".join(added_lines)}
	return is_step_code_present(disk_text, dummy_step)


func _insert_hunk_by_context(
	current: String,
	before_ctx: PackedStringArray,
	added_lines: PackedStringArray,
	after_ctx: PackedStringArray
) -> String:
	var cur_lines: PackedStringArray = current.split("\n")
	var block_str: String = "\n".join(added_lines)

	# 1. Try matching the last before_ctx line
	if not before_ctx.is_empty():
		var anchor_before: String = before_ctx[before_ctx.size() - 1].strip_edges()
		if not anchor_before.is_empty() and not anchor_before.begins_with("extends "):
			for idx in range(cur_lines.size()):
				if cur_lines[idx].strip_edges() == anchor_before:
					# Prefer insertion before `after_ctx` if present shortly after `idx`
					if not after_ctx.is_empty():
						var anchor_after: String = after_ctx[0].strip_edges()
						for k in range(idx + 1, mini(cur_lines.size(), idx + 12)):
							if cur_lines[k].strip_edges() == anchor_after:
								return _splice_lines_at(cur_lines, k, added_lines)
					# Also check if next line is an indented body block and after_ctx wasn't matched:
					# if anchor_before is `func ...:` with body following, append at end of block? No, usually line-after.
					return _splice_lines_at(cur_lines, idx + 1, added_lines)

	# 2. Try matching after_ctx line alone (insert right above it)
	if not after_ctx.is_empty():
		var anchor_after2: String = after_ctx[0].strip_edges()
		if not anchor_after2.is_empty():
			for idx in range(cur_lines.size()):
				if cur_lines[idx].strip_edges() == anchor_after2:
					return _splice_lines_at(cur_lines, idx, added_lines)

	# 3. Classify declaration hunk (`@export` / `@onready` / `var` / `const` / `signal`) vs method hunk
	var first_non_empty: String = ""
	for l in added_lines:
		var t: String = l.strip_edges()
		if not t.is_empty():
			first_non_empty = t
			break

	var is_top_decl: bool = (
		first_non_empty.begins_with("@export")
		or first_non_empty.begins_with("@onready")
		or first_non_empty.begins_with("var ")
		or first_non_empty.begins_with("const ")
		or first_non_empty.begins_with("signal ")
	) and not added_lines[0].begins_with("\t") and not added_lines[0].begins_with("    ")

	if is_top_decl:
		# Insert right before first `func ` if one exists, otherwise after `extends` header
		for idx in range(cur_lines.size()):
			if cur_lines[idx].strip_edges().begins_with("func "):
				var insert_arr := PackedStringArray()
				for l in added_lines:
					insert_arr.append(l)
				insert_arr.append("")
				return _splice_lines_at(cur_lines, idx, insert_arr)
		var after_ext: int = 0
		for idx in range(cur_lines.size()):
			var st: String = cur_lines[idx].strip_edges()
			if st.begins_with("extends ") or st.begins_with("class_name "):
				after_ext = idx + 1
				break
		return _splice_lines_at(cur_lines, after_ext, added_lines)

	# 4. Fallback: append at bottom
	return current.strip_edges() + "\n\n" + block_str


func _splice_lines_at(lines: PackedStringArray, insert_at: int, inserted: PackedStringArray) -> String:
	var out := PackedStringArray()
	for idx in range(lines.size()):
		if idx == insert_at:
			for ins in inserted:
				out.append(ins)
		out.append(lines[idx])
	if insert_at >= lines.size():
		for ins in inserted:
			out.append(ins)
	return "\n".join(out)


# ---------------------------------------------------------------------------
# Hierarchy-Aware Scene Parser & Pipe-Table Enrichment
# ---------------------------------------------------------------------------

func parse_scene_node_specs(step: Dictionary) -> Array:
	var specs: Array = []
	var seen_paths: Dictionary = {}
	var area1: String = str(step.get("area1Hierarchy", "")).strip_edges()

	if not area1.is_empty():
		var stack: Array = []
		var raw_lines: PackedStringArray = area1.replace("\r\n", "\n").split("\n")
		for raw_line in raw_lines:
			var line: String = raw_line.strip_edges(false, true)
			if line.strip_edges().is_empty():
				continue
			var first_alpha: int = _find_first_ident_col(line)
			if first_alpha < 0:
				continue
			var clean: String = line.substr(first_alpha).strip_edges()

			while not stack.is_empty():
				var top: Dictionary = stack[stack.size() - 1]
				if int(top.get("col", 0)) >= first_alpha:
					stack.pop_back()
				else:
					break

			var parsed: Dictionary = _parse_node_line(clean)
			var node_name: String = str(parsed.get("name", ""))
			if node_name.is_empty():
				continue

			var is_root: bool = stack.is_empty() and specs.is_empty()
			var parent_path: String = ""
			var rel_path: String = "."
			var depth: int = stack.size()

			if not is_root:
				if stack.is_empty():
					parent_path = "."
					rel_path = node_name
					depth = 1
				else:
					var parent_entry: Dictionary = stack[stack.size() - 1]
					parent_path = str(parent_entry.get("path", "."))
					rel_path = node_name if parent_path == "." else "%s/%s" % [parent_path, node_name]
					depth = stack.size()

			if seen_paths.has(rel_path):
				continue
			seen_paths[rel_path] = true

			var node_class: String = str(parsed.get("nodeClass", "Node3D"))
			var sub_res: String = str(parsed.get("subResourceClass", ""))
			var companion_mesh: String = str(parsed.get("companionMeshClass", ""))
			var spec: Dictionary = {
				"name": node_name,
				"path": rel_path,
				"parentPath": parent_path,
				"depth": depth,
				"isRoot": is_root,
				"type": node_class,
				"subResourceClass": sub_res,
				"companionMeshClass": companion_mesh,
				"displayType": str(parsed.get("displayType", node_class)),
				"props": {},
				"subProps": {},
				"attachScript": "",
			}
			specs.append(spec)
			stack.append({"col": first_alpha, "path": rel_path})

	if specs.is_empty():
		var combined_fb: String = "%s\n%s\n%s" % [
			str(step.get("title", "")),
			str(step.get("instruction", "")),
			str(step.get("codeSnippet", "")),
		]
		var re := RegEx.new()
		re.compile("\\b([A-Z][A-Za-z0-9_]{2,32})\\s*(?:\\(|>)\\s*([A-Z][A-Za-z0-9_]*3D|[A-Z][A-Za-z0-9_]*2D|Timer|Control|Node|CanvasLayer|RigidBody[23]D|CharacterBody[23]D|StaticBody[23]D|Area[23]D|CollisionShape[23]D|Marker[23]D|RayCast[23]D|AudioStreamPlayer(?:[23]D)?|AnimationPlayer|Panel|Label|Button)")
		var matches: Array[RegExMatch] = re.search_all(combined_fb)
		for m in matches:
			var n_name: String = m.get_string(1)
			var n_type: String = m.get_string(2)
			var p_rel: String = "." if specs.is_empty() else n_name
			if seen_paths.has(p_rel):
				continue
			seen_paths[p_rel] = true
			specs.append({
				"name": n_name,
				"path": p_rel,
				"parentPath": "" if specs.is_empty() else ".",
				"depth": 0 if specs.is_empty() else 1,
				"isRoot": specs.is_empty(),
				"type": n_type,
				"subResourceClass": "",
				"companionMeshClass": "",
				"displayType": n_type,
				"props": {},
				"subProps": {},
				"attachScript": "",
			})

	_enrich_scene_specs_from_tables(specs, step)
	return specs


func _find_first_ident_col(line: String) -> int:
	for idx in range(line.length()):
		var ch: int = line.unicode_at(idx)
		if (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or (ch >= 48 and ch <= 57) or ch == 95:
			return idx
	return -1


func _parse_node_line(clean: String) -> Dictionary:
	var node_name: String = clean
	var meta: String = ""
	var paren_open: int = clean.find("(")
	var paren_close: int = clean.find(")", paren_open + 1)
	if paren_open > 0 and paren_close > paren_open:
		node_name = clean.substr(0, paren_open).strip_edges()
		meta = clean.substr(paren_open + 1, paren_close - paren_open - 1).strip_edges()
	elif ">" in clean:
		var parts: PackedStringArray = clean.split(">", false, 1)
		node_name = parts[0].strip_edges()
		if parts.size() > 1:
			meta = parts[1].strip_edges()

	node_name = node_name.split(" ", false, 1)[0].strip_edges()
	if node_name.is_empty():
		return {}

	var node_class: String = ""
	var sub_res: String = ""
	var companion_mesh: String = ""
	var display_type: String = ""

	# Compound shorthand: e.g. RockNorth (CollisionShape3D + MeshInstance3D)
	if "+" in meta:
		var segs: PackedStringArray = meta.split("+", false)
		var has_col: bool = false
		var has_mesh: bool = false
		for s in segs:
			var t: String = s.strip_edges().split(" ", false, 1)[0]
			if "CollisionShape3D" in t:
				has_col = true
			elif "MeshInstance3D" in t:
				has_mesh = true
			elif ClassDB.class_exists(t) and ClassDB.is_parent_class(t, "Shape3D"):
				has_col = true
				sub_res = t
			elif ClassDB.class_exists(t) and ClassDB.is_parent_class(t, "Mesh"):
				has_mesh = true
				companion_mesh = t
		if has_col:
			node_class = "CollisionShape3D"
			if sub_res.is_empty():
				sub_res = "BoxShape3D"
			if has_mesh and companion_mesh.is_empty():
				companion_mesh = "BoxMesh"
			display_type = "%s + %s" % [sub_res, companion_mesh] if has_mesh else sub_res
	elif not meta.is_empty():
		var meta_tok: String = meta.split(" ", false, 1)[0].strip_edges()
		if ClassDB.class_exists(meta_tok):
			if ClassDB.is_parent_class(meta_tok, "Node"):
				node_class = meta_tok
				display_type = meta_tok
			elif ClassDB.is_parent_class(meta_tok, "Shape3D"):
				node_class = "CollisionShape3D"
				sub_res = meta_tok
				display_type = meta_tok
			elif ClassDB.is_parent_class(meta_tok, "Shape2D"):
				node_class = "CollisionShape2D"
				sub_res = meta_tok
				display_type = meta_tok
			elif ClassDB.is_parent_class(meta_tok, "Mesh"):
				node_class = "MeshInstance3D"
				sub_res = meta_tok
				display_type = meta_tok

	if node_class.is_empty():
		node_class = resolve_node_class(node_name)
	if display_type.is_empty():
		display_type = sub_res if not sub_res.is_empty() else node_class

	return {
		"name": node_name,
		"nodeClass": node_class,
		"subResourceClass": sub_res,
		"companionMeshClass": companion_mesh,
		"displayType": display_type,
	}


func resolve_node_class(node_name: String) -> String:
	# Check Godot ClassDB BEFORE heuristics so DirectionalLight3D, SpringArm3D, etc. keep real classes.
	if ClassDB.class_exists(node_name) and ClassDB.is_parent_class(node_name, "Node"):
		return node_name
	var lower: String = node_name.to_lower()
	if "timer" in lower or "cooldown" in lower:
		return "Timer"
	if "spring" in lower and "arm" in lower:
		return "SpringArm3D"
	if "mesh" in lower or "plane" in lower:
		return "MeshInstance3D"
	if "shape" in lower or "collider" in lower:
		return "CollisionShape3D"
	if "zone" in lower or "area" in lower or "hitbox" in lower or "trigger" in lower or "boundary" in lower:
		return "Area3D"
	if "floor" in lower or "wall" in lower or "ground" in lower or "perimeter" in lower:
		return "StaticBody3D"
	if "marker" in lower or "spawn" in lower:
		return "Marker3D"
	if "light" in lower:
		return "DirectionalLight3D"
	if "camera" in lower:
		return "Camera3D"
	if "player" in lower:
		return "CharacterBody3D"
	return "Node3D"


func _enrich_scene_specs_from_tables(specs: Array, step: Dictionary) -> void:
	if specs.is_empty():
		return
	var code: String = str(step.get("codeSnippet", "")).strip_edges()
	var area2: String = str(step.get("area2Inspector", "")).strip_edges()
	var instr: String = str(step.get("instruction", "")).strip_edges()

	# 1. Pipe-table rows: | Node (Type) | Prop1 / Prop2 | Val1 / Val2 |
	for raw_line in code.replace("\r\n", "\n").split("\n"):
		var line: String = raw_line.strip_edges()
		if not line.begins_with("|"):
			continue
		var cols: PackedStringArray = line.split("|", false)
		if cols.size() < 3:
			continue
		var target_col: String = cols[0].strip_edges()
		var prop_col: String = cols[1].strip_edges()
		var val_col: String = cols[2].strip_edges()
		if target_col.is_empty() or target_col.begins_with("-") or target_col.begins_with(":"):
			continue
		var tl: String = target_col.to_lower()
		if tl.begins_with("node") or "input map" in tl:
			continue

		var matched_spec: Dictionary = _match_spec_for_table_target(specs, target_col)
		if matched_spec.is_empty():
			continue

		_apply_paired_prop_values(matched_spec, prop_col, val_col)

	# 2. area2Inspector segments (pipe-delimited)
	if not area2.is_empty():
		var shared_radius: float = -1.0
		var shared_height: float = -1.0
		for seg_raw in area2.split("|"):
			var seg: String = seg_raw.strip_edges()
			if seg.is_empty() or not (":" in seg):
				continue
			var kv: PackedStringArray = seg.split(":", false, 1)
			var lhs: String = kv[0].strip_edges()
			var rhs: String = kv[1].strip_edges()
			if "radius" in rhs.to_lower():
				var rad_val: float = _extract_named_float(rhs, "radius")
				if rad_val > 0.0:
					shared_radius = rad_val
			if "height" in rhs.to_lower():
				var h_val: float = _extract_named_float(rhs, "height")
				if h_val > 0.0:
					shared_height = h_val
			if "." in lhs:
				var dp: PackedStringArray = lhs.split(".", false, 1)
				var sp_dot: Dictionary = _match_spec_for_table_target(specs, dp[0].strip_edges())
				if not sp_dot.is_empty():
					_assign_single_prop(sp_dot, dp[1].strip_edges(), rhs)
			else:
				var sp_lhs: Dictionary = _match_spec_for_table_target(specs, lhs)
				if not sp_lhs.is_empty():
					_assign_rhs_clauses(sp_lhs, rhs)
				elif "CylinderMesh" in lhs or "CylinderShape3D" in lhs or "BoxShape3D" in lhs or "CapsuleShape3D" in lhs or "BoxMesh" in lhs:
					for sp_any in specs:
						var s_dict: Dictionary = sp_any
						if str(s_dict.get("subResourceClass", "")) == lhs or lhs in str(s_dict.get("displayType", "")):
							_assign_rhs_clauses(s_dict, rhs)

		# Sync SandFloor CylinderMesh height if CylinderShape3D had height and Mesh didn't
		if shared_radius > 0.0 or shared_height > 0.0:
			for sp_any2 in specs:
				var s2: Dictionary = sp_any2
				if str(s2.get("subResourceClass", "")) == "CylinderMesh":
					var subp: Dictionary = s2.get("subProps", {})
					if shared_height > 0.0 and not subp.has("height"):
						subp["height"] = shared_height
					if shared_radius > 0.0 and not subp.has("top_radius"):
						subp["top_radius"] = shared_radius
						subp["bottom_radius"] = shared_radius

	# 3. Also check instruction for `(r=18.0, h=0.5)` or `r=18.0` hints if missing
	if not instr.is_empty():
		var attach_re := RegEx.new()
		attach_re.compile("(res://[A-Za-z0-9_./-]+\\.gd)\\s*(?:to|on)\\s*`?([A-Za-z0-9_]+)`?")
		var am: RegExMatch = attach_re.search(instr)
		if am != null:
			var sp_at: Dictionary = _match_spec_for_table_target(specs, am.get_string(2))
			if not sp_at.is_empty() and str(sp_at.get("attachScript", "")).is_empty():
				sp_at["attachScript"] = am.get_string(1)


func _match_spec_for_table_target(specs: Array, raw_target: String) -> Dictionary:
	var cleaned: String = raw_target.strip_edges()
	var paren_idx: int = cleaned.find("(")
	if paren_idx > 0:
		cleaned = cleaned.substr(0, paren_idx).strip_edges()

	var path_segs: PackedStringArray = []
	for seg in cleaned.split(">", false):
		var st: String = seg.strip_edges()
		if not st.is_empty():
			path_segs.append(st)
	if path_segs.is_empty():
		return {}

	var last_name: String = path_segs[path_segs.size() - 1]
	var parent_hint: String = path_segs[path_segs.size() - 2] if path_segs.size() >= 2 else ""

	# Handle `Node > Script` / `CollisionShape3D > Shape` / `CrabMesh > Mesh` property category suffix
	var category_suffixes := PackedStringArray([
		"script", "shape", "mesh", "material", "timer", "transform", "floor",
		"collision", "collider", "physics", "signals", "signal", "property", "inspector",
		"characterbody3d", "characterbody2d", "staticbody3d", "rigidbody3d",
		"area3d", "area2d", "meshinstance3d", "collisionshape3d", "collisionshape2d",
		"navigationagent3d", "sprite3d", "sprite2d", "node3d", "node2d", "control", "raycast3d"
	])
	if (last_name.to_lower() in category_suffixes) and not parent_hint.is_empty():
		last_name = parent_hint
		parent_hint = path_segs[path_segs.size() - 3] if path_segs.size() >= 3 else ""

	# Exact parent + name match first
	if not parent_hint.is_empty():
		for sp_raw in specs:
			var sp: Dictionary = sp_raw
			if str(sp.get("name", "")).to_lower() == last_name.to_lower() and parent_hint.to_lower() in str(sp.get("path", "")).to_lower():
				return sp

	# Exact name match
	for sp_raw in specs:
		var sp: Dictionary = sp_raw
		if str(sp.get("name", "")).to_lower() == last_name.to_lower():
			return sp

	# Sub-resource class match (e.g. CylinderShape3D)
	for sp_raw in specs:
		var sp: Dictionary = sp_raw
		if str(sp.get("subResourceClass", "")).to_lower() == last_name.to_lower():
			return sp

	return {}


func _apply_paired_prop_values(spec: Dictionary, prop_col: String, val_col: String) -> void:
	# Handle rows where middle column IS a concrete Resource class: `| CrabMesh > Mesh | BoxMesh | Size (1.1, 0.6, 0.9) |`
	var prop_tok: String = prop_col.strip_edges().split(" ", false, 1)[0]
	var is_abstract_res: bool = (prop_tok == "Mesh" or prop_tok == "Shape3D" or prop_tok == "Shape2D")
	if not ("/" in prop_col) and not is_abstract_res and ClassDB.class_exists(prop_tok) and ClassDB.can_instantiate(prop_tok) and (ClassDB.is_parent_class(prop_tok, "Shape3D") or ClassDB.is_parent_class(prop_tok, "Shape2D") or ClassDB.is_parent_class(prop_tok, "Mesh")):
		spec["subResourceClass"] = prop_tok
		_assign_rhs_clauses(spec, val_col)
		return

	var props_raw: PackedStringArray = prop_col.split("/", false)
	var vals_raw: PackedStringArray = val_col.split("/", false)

	if props_raw.size() > 1 and props_raw.size() == vals_raw.size():
		for i in range(props_raw.size()):
			_assign_single_prop(spec, props_raw[i].strip_edges(), vals_raw[i].strip_edges())
		return

	# Special multi-prop single value like `Mesh / Top & Bottom Radius | CylinderMesh / 18.0`
	if vals_raw.size() >= 2 and ("mesh" in prop_col.to_lower() or "shape" in prop_col.to_lower()):
		var first_v: String = vals_raw[0].strip_edges()
		if ClassDB.class_exists(first_v):
			_assign_single_prop(spec, "Shape", first_v)
		if "radius" in prop_col.to_lower() and vals_raw.size() >= 2:
			_assign_single_prop(spec, "Radius", vals_raw[1].strip_edges())
		if "height" in prop_col.to_lower() and vals_raw.size() >= 3:
			_assign_single_prop(spec, "Height", vals_raw[2].strip_edges())
		if "size" in prop_col.to_lower() and vals_raw.size() >= 2:
			_assign_single_prop(spec, "Size", vals_raw[1].strip_edges())
		if "position" in prop_col.to_lower() and vals_raw.size() >= 3:
			_assign_single_prop(spec, "Position", vals_raw[2].strip_edges())
		return

	_assign_single_prop(spec, prop_col, val_col)


func _assign_rhs_clauses(spec: Dictionary, rhs: String) -> void:
	for clause in _split_top_level_commas(rhs):
		var c: String = clause.strip_edges()
		if c.is_empty():
			continue
		if "radius" in c.to_lower():
			_assign_single_prop(spec, "Radius", c)
		elif "height" in c.to_lower():
			_assign_single_prop(spec, "Height", c)
		elif "size" in c.to_lower():
			_assign_single_prop(spec, "Size", c)
		elif "position" in c.to_lower():
			_assign_single_prop(spec, "Position", c)


func _split_top_level_commas(raw: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth: int = 0
	var start: int = 0
	for i in range(raw.length()):
		var ch: String = raw.substr(i, 1)
		if ch == "(":
			depth += 1
		elif ch == ")" and depth > 0:
			depth -= 1
		elif ch == "," and depth == 0:
			out.append(raw.substr(start, i - start))
			start = i + 1
	out.append(raw.substr(start))
	return out


func _assign_single_prop(spec: Dictionary, raw_prop: String, raw_val: String) -> void:
	var p: String = raw_prop.to_lower().strip_edges()
	var v: String = raw_val.strip_edges()
	var props: Dictionary = spec.get("props", {})
	var sub_props: Dictionary = spec.get("subProps", {})

	if "attach script" in p or p == "script":
		if v.begins_with("res://") and v.ends_with(".gd"):
			spec["attachScript"] = v
		return

	if p == "shape" or p == "mesh":
		var parsed_sr := _parse_subresource_decl(v, p)
		var sr_cls := String(parsed_sr.get("class", ""))
		if not sr_cls.is_empty():
			spec["subResourceClass"] = sr_cls
			var sr_props: Dictionary = parsed_sr.get("props", {})
			if not sr_props.is_empty():
				var existing_sr_props: Dictionary = spec.get("subResourceProps", {})
				var existing_sub_props: Dictionary = spec.get("subProps", {})
				for k in sr_props.keys():
					existing_sr_props[k] = sr_props[k]
					existing_sub_props[k] = sr_props[k]
				spec["subResourceProps"] = existing_sr_props
				spec["subProps"] = existing_sub_props
		return
	if p == "material" or p == "material_override" or p == "surface_material_override/0" or p == "surface_material":
		var mat_props := _parse_standard_material_decl(v)
		if not mat_props.is_empty():
			spec["materialProps"] = mat_props
		return
	if p == "snap length" or p == "snap_length" or p == "floor_snap_length":
		if not spec.has("props"):
			spec["props"] = {}
		spec["props"]["floor_snap_length"] = _extract_first_float(v)
		return
	if p == "monitoring" or p == "monitorable" or p == "one shot" or p == "one_shot" or p == "autostart":
		if not spec.has("props"):
			spec["props"] = {}
		var key_norm := p.replace(" ", "_")
		var v_low := v.to_lower()
		spec["props"][key_norm] = (v_low == "true" or v_low == "on" or v_low == "yes" or v_low == "1" or v_low == "enabled")
		return
	if p == "wait time" or p == "wait_time":
		if not spec.has("props"):
			spec["props"] = {}
		spec["props"]["wait_time"] = maxf(0.01, _extract_first_float(v))
		return

	if "position" in p:
		var vec: Variant = _parse_vector3_literal(v)
		if vec is Vector3:
			props["position"] = vec
		return

	if "rotation" in p:
		var vec_rot: Variant = _parse_vector3_literal(v)
		if vec_rot is Vector3:
			props["rotation_degrees"] = vec_rot
		return

	if "spring length" in p or p == "spring_length":
		var fl: float = _extract_first_float(v)
		if not is_nan(fl):
			props["spring_length"] = fl
		return

	if "margin" in p:
		var fm: float = _extract_first_float(v)
		if not is_nan(fm):
			props["margin"] = fm
		return

	if "wait time" in p or p == "wait_time":
		var fw: float = _extract_first_float(v)
		if not is_nan(fw):
			props["wait_time"] = fw
		return

	if "one shot" in p or p == "one_shot":
		var vl: String = v.to_lower()
		props["one_shot"] = (vl == "true" or vl == "on" or vl == "yes" or vl == "1")
		return

	if p == "current":
		var vl2: String = v.to_lower()
		props["current"] = (vl2 == "true" or vl2 == "on" or vl2 == "yes" or vl2 == "1")
		return

	if "collision mask" in p or "collision layer" in p:
		var layer_re := RegEx.new()
		layer_re.compile("([0-9]+)")
		var m_layer: RegExMatch = layer_re.search(v)
		if m_layer != null:
			var bit_idx: int = maxi(1, m_layer.get_string(1).to_int())
			var mask_val: int = 1 << (bit_idx - 1) if "layer" in v.to_lower() else m_layer.get_string(1).to_int()
			var key_name: String = "collision_mask" if "mask" in p else "collision_layer"
			props[key_name] = mask_val
		return

	if "radius" in p:
		var fr: float = _extract_first_float(v)
		if not is_nan(fr):
			sub_props["radius"] = fr
			sub_props["top_radius"] = fr
			sub_props["bottom_radius"] = fr
		return

	if "height" in p:
		var fh: float = _extract_first_float(v)
		if not is_nan(fh):
			sub_props["height"] = fh
		return

	if "size" in p:
		var v3: Variant = _parse_vector3_literal(v)
		if v3 is Vector3:
			sub_props["size"] = v3
			return
		var v2: Variant = _parse_vector2_literal(v)
		if v2 is Vector2:
			sub_props["size"] = v2


func _extract_named_float(text: String, keyword: String) -> float:
	var re := RegEx.new()
	re.compile("(?i)%s\\s*[:=]?\\s*(-?[0-9]+(?:\\.[0-9]+)?)" % keyword)
	var m: RegExMatch = re.search(text)
	if m != null:
		return m.get_string(1).to_float()
	return -1.0


func _extract_first_float(raw: String) -> float:
	var re := RegEx.new()
	re.compile("(-?[0-9]+(?:\\.[0-9]+)?)")
	var m: RegExMatch = re.search(raw)
	if m != null:
		return m.get_string(1).to_float()
	return NAN


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
# Child Scene Instancing, InputMap, Inspector & Multi-Signal Parsers
# ---------------------------------------------------------------------------

func parse_scene_instance_specs(step: Dictionary, target_scene_path: String) -> Array:
	var instances: Array = []
	var combined: String = "%s\n%s" % [str(step.get("instruction", "")), str(step.get("codeSnippet", ""))]
	var inst_re := RegEx.new()
	inst_re.compile("(?i)instance\\s+`?(?:res://(?:scenes/)?)?([a-zA-Z0-9_]+\\.tscn)`?(?:\\s+at\\s+(?:Vector3)?\\(\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*,\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*,\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*\\))?")
	var matches: Array[RegExMatch] = inst_re.search_all(combined)
	var seen: Dictionary = {}
	for m in matches:
		var tscn_file: String = m.get_string(1)
		if tscn_file.is_empty():
			continue
		var full_path: String = "res://scenes/%s" % tscn_file
		if not FileAccess.file_exists(full_path) and FileAccess.file_exists("res://%s" % tscn_file):
			full_path = "res://%s" % tscn_file
		if full_path == target_scene_path or seen.has(full_path):
			continue
		seen[full_path] = true
		var has_pos: bool = not m.get_string(2).is_empty()
		var pos := Vector3(
			m.get_string(2).to_float(),
			m.get_string(3).to_float(),
			m.get_string(4).to_float()
		) if has_pos else Vector3.ZERO
		instances.append({
			"scenePath": full_path,
			"nodeName": tscn_file.get_basename().to_pascal_case(),
			"position": pos,
			"hasPos": has_pos,
		})
	return instances


func parse_input_specs(step: Dictionary) -> Array:
	var specs: Array = []
	var seen: Dictionary = {}
	var code: String = str(step.get("codeSnippet", "")).strip_edges()
	var area2: String = str(step.get("area2Inspector", "")).strip_edges()
	var instr: String = str(step.get("instruction", "")).strip_edges()

	# 1. Pipe table rows: | Input Map > move_forward | Key | W |
	for raw_line in code.replace("\r\n", "\n").split("\n"):
		var line: String = raw_line.strip_edges()
		if not line.begins_with("|"):
			continue
		var cols: PackedStringArray = line.split("|", false)
		if cols.size() < 3:
			continue
		var col0: String = cols[0].strip_edges()
		if "input map" in col0.to_lower() and ">" in col0:
			var act: String = col0.split(">", false, 1)[1].strip_edges()
			var key_hint: String = cols[2].strip_edges()
			if not act.is_empty() and not seen.has(act):
				seen[act] = true
				specs.append({"action": act, "keyLabel": key_hint})

	# 2. area2Inspector & instruction: `move_forward (W)` or `Add dash action (Space)`
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


func parse_inspector_specs(step: Dictionary) -> Array:
	var specs: Array = []
	var seen: Dictionary = {}
	var code: String = str(step.get("codeSnippet", "")).strip_edges()
	var area2: String = str(step.get("area2Inspector", "")).strip_edges()

	for raw_line in code.replace("\r\n", "\n").split("\n"):
		var line: String = raw_line.strip_edges()
		if not line.begins_with("|"):
			continue
		var cols: PackedStringArray = line.split("|", false)
		if cols.size() < 3:
			continue
		var first_col: String = cols[0].strip_edges()
		var fl: String = first_col.to_lower()
		if first_col.is_empty() or first_col.begins_with("-") or first_col.begins_with(":"):
			continue
		if fl.begins_with("node") or fl.begins_with("property") or "input map" in fl:
			continue
		var prop_col: String = cols[1].strip_edges()
		if prop_col.to_lower() == "scene path":
			continue
		var node_part: String = first_col.split(">")[first_col.split(">").size() - 1].strip_edges()
		var paren_i: int = node_part.find("(")
		if paren_i > 0:
			node_part = node_part.substr(0, paren_i).strip_edges()
		var val_col: String = cols[2].strip_edges()
		var key: String = "%s|%s" % [node_part, prop_col]
		if seen.has(key):
			continue
		seen[key] = true
		specs.append({
			"nodeName": node_part,
			"prop": prop_col,
			"value": val_col,
			"label": "%s · %s = %s" % [node_part, prop_col, val_col],
		})

	if specs.is_empty() and not area2.is_empty():
		for part_raw in area2.split("|"):
			var part: String = part_raw.strip_edges()
			if part.is_empty() or "input map" in part.to_lower() or not (":" in part):
				continue
			var kv: PackedStringArray = part.split(":", false, 1)
			var lhs: String = kv[0].strip_edges()
			var rhs: String = kv[1].strip_edges()
			if "." in lhs:
				var dp: PackedStringArray = lhs.split(".", false, 1)
				var n_hint: String = dp[0].strip_edges()
				var p_hint: String = dp[1].strip_edges()
				var key2: String = "%s|%s" % [n_hint, p_hint]
				if not seen.has(key2):
					seen[key2] = true
					specs.append({
						"nodeName": n_hint,
						"prop": p_hint,
						"value": rhs,
						"label": "%s · %s = %s" % [n_hint, p_hint, rhs],
					})

	return specs


func parse_signal_specs(step: Dictionary, scene_root: Node = null) -> Array:
	var specs: Array = []
	var seen: Dictionary = {}
	var code: String = str(step.get("codeSnippet", "")).strip_edges()
	var instr: String = str(step.get("instruction", "")).strip_edges()
	var combined: String = "%s\n%s" % [code, instr]

	var sig_re := RegEx.new()
	sig_re.compile("\\[?([A-Za-z][A-Za-z0-9_]*)\\.([a-z][a-z0-9_]*)\\]?(?:\\(\\))?\\s*(?:-->|──►|─►|->)\\s*\\[?(?:([A-Za-z][A-Za-z0-9_]*)\\.)?([a-zA-Z_][A-Za-z0-9_]*)\\]?(?:\\(\\))?")
	var matches: Array[RegExMatch] = sig_re.search_all(combined)

	var default_target: String = _infer_signal_target_name(step, scene_root)

	for m in matches:
		var src: String = m.get_string(1).strip_edges()
		var sig: String = m.get_string(2).strip_edges()
		var dst: String = m.get_string(3).strip_edges()
		var method: String = m.get_string(4).strip_edges()
		if sig in PackedStringArray(["tscn", "gd", "scn", "tres", "cfg", "json"]):
			continue
		if dst.is_empty():
			dst = default_target
		if src.is_empty() or sig.is_empty() or method.is_empty():
			continue
		var k: String = "%s.%s->%s.%s" % [src, sig, dst, method]
		if seen.has(k):
			continue
		seen[k] = true
		specs.append({
			"source": src,
			"signalName": sig,
			"target": dst,
			"method": method,
			"label": "%s.%s -> %s.%s()" % [src, sig, dst, method] if not dst.is_empty() else "%s.%s -> %s()" % [src, sig, method],
		})

	return specs


func _infer_signal_target_name(step: Dictionary, scene_root: Node) -> String:
	var loc: String = str(step.get("locationLabel", ""))
	var instr: String = str(step.get("instruction", ""))
	var to_re := RegEx.new()
	to_re.compile("(?i)to\\s+`?([A-Z][A-Za-z0-9_]*)\\.[a-zA-Z_]|to\\s+`?([A-Z][A-Za-z0-9_]*)`?\\b")
	var tm: RegExMatch = to_re.search(instr)
	if tm != null:
		var g1: String = tm.get_string(1)
		if not g1.is_empty():
			return g1
		var g2: String = tm.get_string(2)
		if not g2.is_empty():
			return g2
	# Ignore "Node > Signals > <EmitterNode>" breadcrumbs (the last segment is the emitter, not the receiver).
	var loc_low := loc.to_lower()
	if not ("signals" in loc_low):
		for seg in loc.split(">", false):
			var s: String = seg.strip_edges()
			if s.is_valid_identifier() and not (s in PackedStringArray(["Node", "Signals", "Scene", "Tree"])):
				if scene_root == null or _find_node_recursive(scene_root, s) != null:
					return s
	if scene_root != null:
		return scene_root.name
	return ""


# ---------------------------------------------------------------------------
# Unified Step Evaluation (Capabilities + Hierarchical Tree Rows)
# ---------------------------------------------------------------------------

func evaluate_step(feat: Dictionary, step: Dictionary, editor_interface: EditorInterface) -> Dictionary:
	var rows: Array = []
	var role: String = str(step.get("role", "CODE"))
	var step_path: String = resolve_effective_step_path(step, feat, editor_interface.get_edited_scene_root() if editor_interface != null else null)
	var verify_mode: String = str(step.get("verifyMode", "")).strip_edges().to_lower()

	var live_scene_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
	var inspect_root: Node = live_scene_root
	var temp_scene_root: Node = null
	var scene_matches_open: bool = false

	if step_path.ends_with(".tscn"):
		if live_scene_root != null and live_scene_root.scene_file_path == step_path:
			inspect_root = live_scene_root
			scene_matches_open = true
		elif FileAccess.file_exists(step_path):
			var packed: Resource = ResourceLoader.load(step_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
			if packed is PackedScene:
				temp_scene_root = (packed as PackedScene).instantiate()
				inspect_root = temp_scene_root
	elif live_scene_root != null:
		scene_matches_open = true

	var node_specs: Array = parse_scene_node_specs(step)
	var missing_nodes: Array = []
	var instance_specs: Array = parse_scene_instance_specs(step, step_path)
	var missing_instances: Array = []
	var input_specs: Array = parse_input_specs(step)
	var missing_inputs: Array = []
	var insp_specs: Array = parse_inspector_specs(step) if role == "INSP" else []
	var missing_insp: Array = []
	var sig_specs: Array = parse_signal_specs(step, inspect_root)
	var missing_sigs: Array = []

	var first_focus_path: String = "." if inspect_root != null else ""

	# 1. Scene File & Hierarchical Node Specs
	if step_path.ends_with(".tscn") and (role == "SCENE" or not node_specs.is_empty() or not instance_specs.is_empty()):
		var scene_on_disk: bool = FileAccess.file_exists(step_path)
		rows.append({
			"id": "scene_file",
			"parentId": "",
			"depth": 0,
			"title": step_path.get_file(),
			"subtitle": "saved on disk" if scene_on_disk else "not created yet",
			"iconName": "PackedScene",
			"ok": scene_on_disk,
			"focusPath": "." if scene_matches_open else "",
			"resPath": step_path,
		})

	for sp_raw in node_specs:
		var sp: Dictionary = sp_raw
		var n_name: String = str(sp.get("name", ""))
		var rel_path: String = str(sp.get("path", n_name))
		var parent_path: String = str(sp.get("parentPath", ""))
		var n_type: String = str(sp.get("type", "Node3D"))
		var disp_type: String = str(sp.get("displayType", n_type))
		var found: Node = _resolve_spec_node(inspect_root, sp)
		var is_present: bool = found != null
		if not is_present:
			missing_nodes.append(sp)
		elif scene_matches_open and first_focus_path == ".":
			first_focus_path = str(inspect_root.get_path_to(found))

		var parent_row_id: String = ""
		if not parent_path.is_empty():
			parent_row_id = "node:%s" % parent_path

		rows.append({
			"id": "node:%s" % rel_path,
			"parentId": parent_row_id,
			"depth": int(sp.get("depth", 0)),
			"title": n_name,
			"subtitle": disp_type,
			"iconName": n_type,
			"ok": is_present,
			"focusPath": str(inspect_root.get_path_to(found)) if (found != null and scene_matches_open) else "",
			"resPath": "",
		})

	# 2. Child Scene Instance Specs (e.g. CrabPlayer in CoastalArena)
	for inst_raw in instance_specs:
		var inst: Dictionary = inst_raw
		var i_path: String = str(inst.get("scenePath", ""))
		var i_name: String = str(inst.get("nodeName", i_path.get_file().get_basename()))
		var inst_node: Node = _find_instanced_scene_node(inspect_root, i_path)
		var inst_ok: bool = inst_node != null
		if not inst_ok:
			missing_instances.append(inst)
		rows.append({
			"id": "inst:%s" % i_name,
			"parentId": "",
			"depth": 0,
			"title": "Instance %s" % i_path.get_file(),
			"subtitle": "in %s" % step_path.get_file(),
			"iconName": "PackedScene",
			"ok": inst_ok,
			"focusPath": str(inspect_root.get_path_to(inst_node)) if (inst_node != null and scene_matches_open) else "",
			"resPath": i_path,
		})

	# 3. InputMap Bindings
	for inp_raw in input_specs:
		var inp: Dictionary = inp_raw
		var act_name: String = str(inp.get("action", ""))
		var key_lbl: String = str(inp.get("keyLabel", ""))
		var setting_key: String = "input/%s" % act_name
		var has_input: bool = _has_real_input_binding(act_name, setting_key)
		if not has_input:
			missing_inputs.append(inp)
		rows.append({
			"id": "input:%s" % act_name,
			"parentId": "",
			"depth": 0,
			"title": "InputMap: %s" % act_name,
			"subtitle": key_lbl,
			"iconName": "InputEventKey",
			"ok": has_input,
			"focusPath": "",
			"resPath": "",
		})

	# 4. Inspector Properties
	for isp_raw in insp_specs:
		var isp: Dictionary = isp_raw
		var n_hint: String = str(isp.get("nodeName", ""))
		var prop: String = str(isp.get("prop", ""))
		var val_str: String = str(isp.get("value", ""))
		var target_n: Node = _find_node_recursive(inspect_root, n_hint) if not n_hint.is_empty() else null
		var prop_ok: bool = _check_inspector_prop_ok(target_n, prop, val_str)
		if not prop_ok:
			missing_insp.append(isp)
		rows.append({
			"id": "insp:%s:%s" % [n_hint, prop],
			"parentId": "",
			"depth": 0,
			"title": "%s.%s" % [n_hint, prop] if not n_hint.is_empty() else prop,
			"subtitle": val_str,
			"iconName": "Edit",
			"ok": prop_ok,
			"focusPath": str(inspect_root.get_path_to(target_n)) if (target_n != null and scene_matches_open) else "",
			"resPath": "",
		})

	# 5. GDScript Creation, Attachment & Code Hunk Verification
	var has_code: bool = (role == "CODE" or role == "FIX")
	var code_exists: bool = false
	var code_attached: bool = false
	var code_merged: bool = false
	if has_code:
		code_exists = step_path.ends_with(".gd") and FileAccess.file_exists(step_path)
		rows.append({
			"id": "script_file",
			"parentId": "",
			"depth": 0,
			"title": step_path.get_file(),
			"subtitle": step_path,
			"iconName": "Script",
			"ok": code_exists,
			"focusPath": "",
			"resPath": step_path if code_exists else "",
		})

		var attach_node_hint: String = _infer_script_target_node_name(step, step_path, inspect_root)
		var attached_node: Node = _find_node_with_script(inspect_root, step_path) if code_exists else null
		if attached_node == null and not attach_node_hint.is_empty() and code_exists:
			var cand_n: Node = _find_node_recursive(inspect_root, attach_node_hint)
			if cand_n != null and cand_n.get_script() is Script and (cand_n.get_script() as Script).resource_path == step_path:
				attached_node = cand_n
		code_attached = attached_node != null
		rows.append({
			"id": "script_attached",
			"parentId": "",
			"depth": 0,
			"title": "Attached to %s" % (attached_node.name if attached_node != null else (attach_node_hint if not attach_node_hint.is_empty() else "target node")),
			"subtitle": attached_node.get_class() if attached_node != null else "pending attachment",
			"iconName": attached_node.get_class() if attached_node != null else "Node",
			"ok": code_attached,
			"focusPath": str(inspect_root.get_path_to(attached_node)) if (attached_node != null and scene_matches_open) else "",
			"resPath": "",
		})

		var disk_txt: String = ""
		if code_exists:
			var rf := FileAccess.open(step_path, FileAccess.READ)
			if rf != null:
				disk_txt = rf.get_as_text()
				rf.close()
			code_merged = is_step_code_present(disk_txt, step)
		rows.append({
			"id": "script_code",
			"parentId": "",
			"depth": 0,
			"title": "Step code present" if role == "CODE" else "Root-cause patch present",
			"subtitle": "in %s" % step_path.get_file(),
			"iconName": "ScriptExtend" if code_exists else "ScriptCreate",
			"ok": code_merged,
			"focusPath": "",
			"resPath": step_path if code_exists else "",
		})

	# 6. Signal Connections
	for sig_raw in sig_specs:
		var sg: Dictionary = sig_raw
		var src_name: String = str(sg.get("source", ""))
		var sig_name: String = str(sg.get("signalName", ""))
		var dst_name: String = str(sg.get("target", ""))
		var method_name: String = str(sg.get("method", ""))
		var src_node: Node = _find_node_recursive(inspect_root, src_name)
		var dst_node: Node = _find_node_recursive(inspect_root, dst_name) if not dst_name.is_empty() else inspect_root
		var connected: bool = false
		if src_node != null and dst_node != null and src_node.has_signal(sig_name):
			connected = src_node.is_connected(sig_name, Callable(dst_node, method_name))
		if not connected:
			missing_sigs.append(sg)
		rows.append({
			"id": "sig:%s:%s" % [src_name, sig_name],
			"parentId": "",
			"depth": 0,
			"title": "%s.%s" % [src_name, sig_name],
			"subtitle": "-> %s()" % method_name,
			"iconName": "Signals",
			"ok": connected,
			"focusPath": str(inspect_root.get_path_to(src_node)) if (src_node != null and scene_matches_open) else "",
			"resPath": "",
		})

	# 7. Playtest Verification Step (e.g. `Verify Floor Collision` with zero signals)
	var is_playtest_step: bool = (verify_mode == "playtest") or (role == "WIRE" and sig_specs.is_empty() and input_specs.is_empty())
	if rows.is_empty():
		var target_exists: bool = FileAccess.file_exists(step_path) if step_path.begins_with("res://") else false
		var scene_ready: bool = target_exists or (live_scene_root != null)
		rows.append({
			"id": "playtest_scene",
			"parentId": "",
			"depth": 0,
			"title": step_path.get_file() if not step_path.is_empty() else "Active Scene",
			"subtitle": "ready to run with F6" if scene_ready else "create scene first",
			"iconName": "PlayScene",
			"ok": scene_ready,
			"focusPath": "." if scene_matches_open else "",
			"resPath": step_path if target_exists else "",
		})

	if temp_scene_root != null:
		temp_scene_root.free()

	var ready_cnt: int = 0
	for r_raw in rows:
		var r: Dictionary = r_raw
		if bool(r.get("ok", false)):
			ready_cnt += 1

	var all_ready: bool = not rows.is_empty() and ready_cnt == rows.size()
	return {
		"rows": rows,
		"readyCount": ready_cnt,
		"totalCount": rows.size(),
		"allReady": all_ready,
		"stepPath": step_path,
		"nodeSpecs": node_specs,
		"missingNodeSpecs": missing_nodes,
		"instanceSpecs": instance_specs,
		"missingInstanceSpecs": missing_instances,
		"inputSpecs": input_specs,
		"missingInputSpecs": missing_inputs,
		"inspSpecs": insp_specs,
		"missingInspSpecs": missing_insp,
		"sigSpecs": sig_specs,
		"missingSigSpecs": missing_sigs,
		"hasCode": has_code,
		"codeExists": code_exists,
		"codeAttached": code_attached,
		"codeMerged": code_merged,
		"isPlaytestStep": is_playtest_step,
		"firstFocusPath": first_focus_path,
		"sceneMatchesOpen": scene_matches_open,
	}


# ---------------------------------------------------------------------------
# Undoable Step Actions
# ---------------------------------------------------------------------------

func build_missing_scene_nodes(
	editor_interface: EditorInterface,
	undo_redo: EditorUndoRedoManager,
	step: Dictionary,
	eval_info: Dictionary
) -> Dictionary:
	if editor_interface == null:
		return {"ok": false, "message": "EditorInterface unavailable."}

	var step_path: String = str(eval_info.get("stepPath", "res://scenes/main.tscn"))
	var node_specs: Array = eval_info.get("nodeSpecs", [])
	var inst_specs: Array = eval_info.get("missingInstanceSpecs", [])

	if step_path.ends_with(".tscn"):
		if not FileAccess.file_exists(step_path):
			var root_type: String = "Node3D"
			var root_name: String = step_path.get_file().get_basename().to_pascal_case()
			if not node_specs.is_empty():
				var first_spec: Dictionary = node_specs[0]
				var cand: String = str(first_spec.get("type", "Node3D"))
				if ClassDB.class_exists(cand) and ClassDB.can_instantiate(cand) and ClassDB.is_parent_class(cand, "Node"):
					root_type = cand
				var cand_name: String = str(first_spec.get("name", ""))
				if not cand_name.is_empty():
					root_name = cand_name
			var new_root_v: Variant = ClassDB.instantiate(root_type)
			if not (new_root_v is Node):
				return {"ok": false, "message": "Could not instantiate root class %s." % root_type}
			var new_root: Node = new_root_v as Node
			new_root.name = root_name
			_ensure_dir_for_res_path(step_path)
			var packed := PackedScene.new()
			packed.pack(new_root)
			ResourceSaver.save(packed, step_path)
			new_root.queue_free()
			if editor_interface.get_resource_filesystem() != null:
				editor_interface.get_resource_filesystem().scan()
			editor_interface.open_scene_from_path(step_path)
		else:
			var cur_root: Node = editor_interface.get_edited_scene_root()
			if cur_root == null or cur_root.scene_file_path != step_path:
				editor_interface.open_scene_from_path(step_path)

	var scene_root: Node = editor_interface.get_edited_scene_root()
	if scene_root == null:
		return {"ok": false, "message": "Open target scene before building nodes."}

	var added_cnt: int = 0
	var created_nodes: Array[Node] = []
	var created_paths: Dictionary = {}

	if undo_redo != null:
		undo_redo.create_action("LAYERS: Build Missing Scene Nodes")

	for sp_raw in node_specs:
		var sp: Dictionary = sp_raw
		if bool(sp.get("isRoot", false)):
			var root_script_path: String = str(sp.get("attachScript", "")).strip_edges()
			if not root_script_path.is_empty() and FileAccess.file_exists(root_script_path) and scene_root.get_script() == null and can_attach_script_to_node(scene_root, root_script_path):
				var scr: Script = reload_script_safely(root_script_path)
				if scr != null:
					if undo_redo != null:
						undo_redo.add_do_property(scene_root, "script", scr)
						undo_redo.add_undo_property(scene_root, "script", null)
					else:
						scene_root.set_script(scr)
			continue

		var existing_node := _resolve_spec_node(scene_root, sp)
		if existing_node != null:
			if _sync_existing_node_from_spec(existing_node, sp, undo_redo):
				added_cnt += 1
			continue

		var rel_path: String = str(sp.get("path", ""))
		var parent_path: String = str(sp.get("parentPath", "."))
		var parent_node: Node = scene_root
		if parent_path != "." and not parent_path.is_empty():
			if created_paths.has(parent_path):
				parent_node = created_paths[parent_path] as Node
			else:
				parent_node = _resolve_node_by_rel_path(scene_root, parent_path)
		if parent_node == null:
			parent_node = scene_root

		var created_node: Node = instantiate_spec_node(sp)
		if created_node == null:
			continue

		created_paths[rel_path] = created_node
		created_nodes.append(created_node)

		# Attach companion MeshInstance3D inside undo transaction too if present
		var companion_mesh_cls: String = str(sp.get("companionMeshClass", ""))
		var companion_mesh_node: MeshInstance3D = null
		if not companion_mesh_cls.is_empty() and ClassDB.class_exists(companion_mesh_cls):
			companion_mesh_node = MeshInstance3D.new()
			companion_mesh_node.name = "MeshInstance3D"
			var mesh_inst: Variant = ClassDB.instantiate(companion_mesh_cls)
			if mesh_inst is Mesh:
				var sub_p: Dictionary = sp.get("subProps", {})
				_apply_props_to_object(mesh_inst as Object, sub_p)
				companion_mesh_node.mesh = mesh_inst as Mesh

		if undo_redo != null:
			undo_redo.add_do_method(parent_node, "add_child", created_node, true)
			undo_redo.add_do_property(created_node, "owner", scene_root)
			undo_redo.add_do_reference(created_node)
			undo_redo.add_undo_method(parent_node, "remove_child", created_node)
			if companion_mesh_node != null:
				undo_redo.add_do_method(created_node, "add_child", companion_mesh_node, true)
				undo_redo.add_do_property(companion_mesh_node, "owner", scene_root)
				undo_redo.add_do_reference(companion_mesh_node)
				undo_redo.add_undo_method(created_node, "remove_child", companion_mesh_node)
		else:
			parent_node.add_child(created_node, true)
			created_node.owner = scene_root
			if companion_mesh_node != null:
				created_node.add_child(companion_mesh_node, true)
				companion_mesh_node.owner = scene_root

		added_cnt += 1

	# Instance child scenes (e.g. crab_player.tscn)
	for inst_raw in inst_specs:
		var inst: Dictionary = inst_raw
		var s_path: String = str(inst.get("scenePath", ""))
		if not FileAccess.file_exists(s_path):
			continue
		var packed_child: Resource = ResourceLoader.load(s_path, "PackedScene")
		if packed_child is PackedScene:
			var inst_node: Node = (packed_child as PackedScene).instantiate()
			if inst_node != null:
				if bool(inst.get("hasPos", false)) and inst_node is Node3D:
					(inst_node as Node3D).position = inst.get("position", Vector3.ZERO)
				if undo_redo != null:
					undo_redo.add_do_method(scene_root, "add_child", inst_node, true)
					undo_redo.add_do_property(inst_node, "owner", scene_root)
					undo_redo.add_do_reference(inst_node)
					undo_redo.add_undo_method(scene_root, "remove_child", inst_node)
				else:
					scene_root.add_child(inst_node, true)
					inst_node.owner = scene_root
				added_cnt += 1

	if undo_redo != null:
		if added_cnt > 0:
			undo_redo.commit_action()
		else:
			undo_redo.clear_history()

	if added_cnt > 0 and step_path.ends_with(".tscn"):
		sanitize_null_script_exports(scene_root)
		editor_interface.save_scene()
	if not created_nodes.is_empty():
		select_and_inspect_node(editor_interface, created_nodes[0])

	return {"ok": true, "addedCount": added_cnt}


func instantiate_spec_node(sp: Dictionary) -> Node:
	var n_name: String = str(sp.get("name", "Node3D"))
	var n_type: String = str(sp.get("type", "Node3D"))
	var sub_res: String = str(sp.get("subResourceClass", ""))
	var props: Dictionary = sp.get("props", {})
	var sub_props: Dictionary = sp.get("subProps", {})

	var created: Node = null
	if ClassDB.class_exists(n_type) and ClassDB.can_instantiate(n_type) and ClassDB.is_parent_class(n_type, "Node"):
		var inst: Variant = ClassDB.instantiate(n_type)
		if inst is Node:
			created = inst as Node
	if created == null:
		created = Node3D.new()
	created.name = n_name

	if not sub_res.is_empty() and ClassDB.class_exists(sub_res) and ClassDB.can_instantiate(sub_res):
		var res_inst: Variant = ClassDB.instantiate(sub_res)
		if created is CollisionShape3D and res_inst is Shape3D:
			_apply_props_to_object(res_inst as Object, sub_props)
			(created as CollisionShape3D).shape = res_inst as Shape3D
		elif created is CollisionShape2D and res_inst is Shape2D:
			_apply_props_to_object(res_inst as Object, sub_props)
			(created as CollisionShape2D).shape = res_inst as Shape2D
		elif created is MeshInstance3D and res_inst is Mesh:
			_apply_props_to_object(res_inst as Object, sub_props)
			(created as MeshInstance3D).mesh = res_inst as Mesh

	_apply_props_to_object(created, props)

	# Practical default lighting tilt for new DirectionalLight3D if unrotated
	if created is DirectionalLight3D and not props.has("rotation_degrees"):
		(created as DirectionalLight3D).rotation_degrees = Vector3(-45.0, -30.0, 0.0)
		(created as DirectionalLight3D).shadow_enabled = true

	var attach_gd: String = str(sp.get("attachScript", "")).strip_edges()
	if not attach_gd.is_empty() and FileAccess.file_exists(attach_gd) and can_attach_script_to_node(created, attach_gd):
		var scr: Script = reload_script_safely(attach_gd)
		if scr != null:
			created.set_script(scr)

	return created


func apply_input_and_inspector(
	editor_interface: EditorInterface,
	undo_redo: EditorUndoRedoManager,
	step: Dictionary,
	eval_info: Dictionary
) -> Dictionary:
	var step_path: String = str(eval_info.get("stepPath", ""))
	var input_specs: Array = eval_info.get("inputSpecs", [])
	var insp_specs: Array = eval_info.get("inspSpecs", [])

	var input_added: int = 0
	for inp_raw in input_specs:
		var inp: Dictionary = inp_raw
		var act: String = str(inp.get("action", "")).strip_edges()
		var key_lbl: String = str(inp.get("keyLabel", "")).strip_edges()
		if act.is_empty():
			continue
		var setting_key: String = "input/%s" % act
		var ev: InputEvent = _build_input_event_for_label(key_lbl)
		if ev == null:
			ev = _infer_default_input_event_for_action(act)
		if ev != null and not _has_real_input_binding(act, setting_key):
			ProjectSettings.set_setting(setting_key, {"deadzone": 0.2, "events": [ev]})
			input_added += 1

	if input_added > 0:
		ProjectSettings.save()
		InputMap.load_from_project_settings()

	if editor_interface != null and step_path.ends_with(".tscn"):
		var cur: Node = editor_interface.get_edited_scene_root()
		if (cur == null or cur.scene_file_path != step_path) and FileAccess.file_exists(step_path):
			editor_interface.open_scene_from_path(step_path)

	var scene_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
	var props_applied: int = 0
	var focused_node: Node = null

	if scene_root != null and not insp_specs.is_empty():
		if undo_redo != null:
			undo_redo.create_action("LAYERS: Apply Inspector Properties")
		for isp_raw in insp_specs:
			var isp: Dictionary = isp_raw
			var n_hint: String = str(isp.get("nodeName", "")).strip_edges()
			var prop: String = str(isp.get("prop", "")).strip_edges()
			var val_str: String = str(isp.get("value", "")).strip_edges()
			if n_hint.is_empty() or prop.is_empty():
				continue
			var target: Node = _find_node_recursive(scene_root, n_hint)
			if target == null:
				continue
			if focused_node == null:
				focused_node = target
			var applied: bool = _apply_inspector_setting_to_node(target, prop, val_str, undo_redo)
			if applied:
				props_applied += 1
		if undo_redo != null:
			if props_applied > 0:
				undo_redo.commit_action()
			else:
				undo_redo.clear_history()

	if focused_node == null and scene_root != null:
		var focus_path: String = str(eval_info.get("firstFocusPath", "."))
		if focus_path == ".":
			focused_node = scene_root
		elif not focus_path.is_empty():
			focused_node = scene_root.get_node_or_null(NodePath(focus_path))
	if focused_node != null and editor_interface != null:
		select_and_inspect_node(editor_interface, focused_node)
	if props_applied > 0 and editor_interface != null and step_path.ends_with(".tscn"):
		sanitize_null_script_exports(scene_root)
		editor_interface.save_scene()

	return {"ok": true, "inputCount": input_added, "propCount": props_applied}


func apply_or_create_script(
	editor_interface: EditorInterface,
	undo_redo: EditorUndoRedoManager,
	step: Dictionary,
	eval_info: Dictionary
) -> Dictionary:
	var step_path: String = str(eval_info.get("stepPath", ""))
	if not step_path.ends_with(".gd"):
		return {"ok": false, "message": "Step path is not a .gd file."}

	var scene_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
	var target_node_hint: String = _infer_script_target_node_name(step, step_path, scene_root)
	var target_node: Node = _find_node_recursive(scene_root, target_node_hint) if (scene_root != null and not target_node_hint.is_empty()) else null
	var fallback_extends: String = target_node.get_class() if target_node != null else (scene_root.get_class() if scene_root != null else "Node")

	var raw_snip: String = _raw_step_snippet(step)
	var wrote_file: bool = false

	if not FileAccess.file_exists(step_path):
		var content: String = strip_diff_prefixes(raw_snip)
		if content.is_empty():
			content = "extends %s\n" % fallback_extends
		elif not ("extends " in content) and not ("class_name " in content):
			content = "extends %s\n\n%s" % [fallback_extends, content]
		_ensure_dir_for_res_path(step_path)
		var wf := FileAccess.open(step_path, FileAccess.WRITE)
		if wf == null:
			return {"ok": false, "message": "Could not create %s" % step_path}
		wf.store_string(content.strip_edges() + "\n")
		wf.close()
		wrote_file = true
	else:
		var rf := FileAccess.open(step_path, FileAccess.READ)
		var existing: String = rf.get_as_text() if rf != null else ""
		if rf != null:
			rf.close()
		if not is_step_code_present(existing, step) and not raw_snip.is_empty():
			var merged: String = merge_step_code_into_existing(existing, raw_snip, fallback_extends)
			if merged != existing:
				var wf2 := FileAccess.open(step_path, FileAccess.WRITE)
				if wf2 == null:
					return {"ok": false, "message": "Could not update %s" % step_path}
				wf2.store_string(merged)
				wf2.close()
				wrote_file = true

	if wrote_file and editor_interface != null and editor_interface.get_resource_filesystem() != null:
		editor_interface.get_resource_filesystem().scan()

	var scr: Script = reload_script_safely(step_path)
	if scr == null:
		scr = load(step_path) as Script

	var attached_new: bool = false
	if scene_root != null and scr != null and _find_node_with_script(scene_root, step_path) == null:
		var attach_to: Node = target_node
		if attach_to == null and editor_interface != null and editor_interface.get_selection() != null:
			var sel: Array = editor_interface.get_selection().get_selected_nodes()
			if not sel.is_empty() and sel[0] is Node and can_attach_script_to_node(sel[0] as Node, step_path):
				attach_to = sel[0] as Node
		if attach_to == null and can_attach_script_to_node(scene_root, step_path):
			attach_to = scene_root
		if attach_to != null and attach_to.get_script() == null and can_attach_script_to_node(attach_to, step_path):
			if undo_redo != null:
				undo_redo.create_action("LAYERS: Attach %s" % step_path.get_file())
				undo_redo.add_do_property(attach_to, "script", scr)
				undo_redo.add_undo_property(attach_to, "script", null)
				undo_redo.commit_action()
			else:
				attach_to.set_script(scr)
			attached_new = true
			if editor_interface != null:
				sanitize_null_script_exports(scene_root)
				editor_interface.save_scene()

	if editor_interface != null and scr != null:
		editor_interface.edit_script(scr)

	return {"ok": true, "wroteFile": wrote_file, "attached": attached_new, "path": step_path}


func connect_step_signals(
	editor_interface: EditorInterface,
	step: Dictionary,
	eval_info: Dictionary
) -> Dictionary:
	if editor_interface == null:
		return {"ok": false, "message": "EditorInterface unavailable."}
	var step_path: String = str(eval_info.get("stepPath", ""))
	if step_path.ends_with(".tscn") and FileAccess.file_exists(step_path):
		var cur: Node = editor_interface.get_edited_scene_root()
		if cur == null or cur.scene_file_path != step_path:
			editor_interface.open_scene_from_path(step_path)

	var scene_root: Node = editor_interface.get_edited_scene_root()
	if scene_root == null:
		return {"ok": false, "message": "Open target scene before wiring signals."}

	var sig_specs: Array = eval_info.get("sigSpecs", [])
	var connected_cnt: int = 0
	var first_src: Node = null

	for sg_raw in sig_specs:
		var sg: Dictionary = sg_raw
		var src_name: String = str(sg.get("source", ""))
		var sig_name: String = str(sg.get("signalName", ""))
		var dst_name: String = str(sg.get("target", ""))
		var method_name: String = str(sg.get("method", ""))

		var src_node: Node = _find_node_recursive(scene_root, src_name)
		if src_node != null and first_src == null:
			first_src = src_node
		var sig_res := _connect_single_signal_safe(scene_root, src_name, sig_name, dst_name, method_name)
		if bool(sig_res.get("ok", false)):
			connected_cnt += 1

	if connected_cnt > 0:
		sanitize_null_script_exports(scene_root)
		editor_interface.save_scene()
	if first_src != null:
		select_and_inspect_node(editor_interface, first_src)

	return {"ok": connected_cnt > 0, "connectedCount": connected_cnt}


func apply_fix_patch(
	editor_interface: EditorInterface,
	step: Dictionary,
	step_path: String
) -> Dictionary:
	var target_path: String = step_path
	var patch_raw: Variant = step.get("scriptPatch", null)
	var target_block: String = ""
	var replace_block: String = ""

	if typeof(patch_raw) == TYPE_DICTIONARY:
		var patch_d: Dictionary = patch_raw
		var rp: String = str(patch_d.get("resPath", "")).strip_edges()
		if rp.begins_with("res://") and rp.ends_with(".gd"):
			target_path = rp
		target_block = str(patch_d.get("targetBlock", ""))
		replace_block = strip_diff_prefixes(str(patch_d.get("replaceBlock", "")))

	if replace_block.is_empty():
		replace_block = resolve_step_code_text(step)

	if target_path.ends_with(".gd") and not replace_block.is_empty():
		var file_exists: bool = FileAccess.file_exists(target_path)
		var existing_text: String = ""
		if file_exists:
			var rf := FileAccess.open(target_path, FileAccess.READ)
			if rf != null:
				existing_text = rf.get_as_text()
				rf.close()

		var applied: bool = false
		if not file_exists or replace_block.begins_with("extends ") or replace_block.begins_with("class_name "):
			_ensure_dir_for_res_path(target_path)
			var wf := FileAccess.open(target_path, FileAccess.WRITE)
			if wf != null:
				wf.store_string(replace_block.strip_edges() + "\n")
				wf.close()
				applied = true
		elif not target_block.is_empty() and target_block in existing_text:
			var updated_text: String = existing_text.replace(target_block, replace_block)
			var wf2 := FileAccess.open(target_path, FileAccess.WRITE)
			if wf2 != null:
				wf2.store_string(updated_text)
				wf2.close()
				applied = true
		elif _has_diff_markers(_raw_step_snippet(step)):
			var merged: String = merge_step_code_into_existing(existing_text, _raw_step_snippet(step), "Node")
			if merged != existing_text:
				var wf3 := FileAccess.open(target_path, FileAccess.WRITE)
				if wf3 != null:
					wf3.store_string(merged)
					wf3.close()
					applied = true

		if applied:
			if editor_interface != null and editor_interface.get_resource_filesystem() != null:
				editor_interface.get_resource_filesystem().scan()
			open_res_path(editor_interface, target_path)
			return {"ok": true, "applied": true, "path": target_path}

	DisplayServer.clipboard_set(replace_block)
	open_res_path(editor_interface, target_path)
	return {"ok": false, "applied": false, "path": target_path}


func open_res_path(editor_interface: EditorInterface, res_path: String) -> String:
	if editor_interface == null:
		return "EditorInterface unavailable."
	if res_path.ends_with(".tscn") or res_path.ends_with(".scn"):
		if FileAccess.file_exists(res_path):
			editor_interface.open_scene_from_path(res_path)
			return ""
		return "%s does not exist yet — click Build Feature in Godot." % res_path
	if not FileAccess.file_exists(res_path):
		return "%s does not exist yet — click Build Feature in Godot." % res_path
	var res: Resource = reload_script_safely(res_path) if res_path.ends_with(".gd") else ResourceLoader.load(res_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if res is Script:
		editor_interface.edit_script(res as Script)
	elif res != null:
		editor_interface.edit_resource(res)
	return ""


func select_and_inspect_node(editor_interface: EditorInterface, node: Node) -> void:
	if editor_interface == null or node == null:
		return
	if editor_interface.get_selection() != null:
		editor_interface.get_selection().clear()
		editor_interface.get_selection().add_node(node)
	editor_interface.inspect_object(node)


# ---------------------------------------------------------------------------
# Internal Helpers
# ---------------------------------------------------------------------------

func _resolve_spec_node(root: Node, sp: Dictionary) -> Node:
	if root == null:
		return null
	if bool(sp.get("isRoot", false)):
		var expected_type: String = str(sp.get("type", "Node"))
		if expected_type == "Node3D" or expected_type == "Node" or root.get_class() == expected_type or root.is_class(expected_type):
			return root
		return null
	var rel_path: String = str(sp.get("path", ""))
	if not rel_path.is_empty():
		var direct: Node = root.get_node_or_null(NodePath(rel_path))
		if direct != null:
			return direct
	var parent_path: String = str(sp.get("parentPath", ""))
	var n_name: String = str(sp.get("name", ""))
	if parent_path == "." or parent_path.is_empty():
		return _find_node_recursive(root, n_name)
	var p_node: Node = _resolve_node_by_rel_path(root, parent_path)
	if p_node != null:
		for child in p_node.get_children():
			if child.name.to_lower() == n_name.to_lower():
				return child
	return null


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


func _find_node_with_script(root: Node, script_path: String) -> Node:
	if root == null or script_path.is_empty():
		return null
	var scr: Variant = root.get_script()
	if scr is Script and (scr as Script).resource_path == script_path:
		return root
	for child in root.get_children():
		var found: Node = _find_node_with_script(child, script_path)
		if found != null:
			return found
	return null


func _infer_script_target_node_name(step: Dictionary, script_path: String, scene_root: Node) -> String:
	var instr: String = str(step.get("instruction", ""))
	var area2: String = str(step.get("area2Inspector", ""))
	var attach_re := RegEx.new()
	attach_re.compile("(?i)attach[^\\n]*?(?:to|on)\\s+`?([A-Z][A-Za-z0-9_]*)`?")
	var am: RegExMatch = attach_re.search(instr)
	if am != null:
		return am.get_string(1)

	var a2_re := RegEx.new()
	a2_re.compile("\\b([A-Z][A-Za-z0-9_]*)\\s*:\\s*Script\\s+res://")
	var a2m: RegExMatch = a2_re.search(area2)
	if a2m != null:
		return a2m.get_string(1)

	if scene_root != null:
		return scene_root.name
	var fname: String = script_path.get_file().get_basename().to_pascal_case()
	return fname


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
	if "forward" in a or a == "move_up" or a == "up":
		return _match_single_input_token("W")
	if "back" in a or a == "move_down" or a == "down":
		return _match_single_input_token("S")
	if "left" in a:
		return _match_single_input_token("A")
	if "right" in a:
		return _match_single_input_token("D")
	return null


func heal_empty_project_input_actions(feat: Dictionary = {}) -> int:
	var key_hints := {}
	for st in feat.get("steps", []):
		for inp in parse_input_specs(st):
			var act := String(inp.get("action", "")).strip_edges()
			var kl := String(inp.get("keyLabel", "")).strip_edges()
			if not act.is_empty() and not kl.is_empty():
				key_hints[act] = kl

	var healed := 0
	for p_raw in ProjectSettings.get_property_list():
		var p_info: Dictionary = p_raw
		var pname := String(p_info.get("name", ""))
		if not pname.begins_with("input/") or pname.begins_with("input/ui_"):
			continue
		var act := pname.substr("input/".length())
		if _has_real_input_binding(act, pname):
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
					ptype == TYPE_STRING or ptype == TYPE_VECTOR2 or ptype == TYPE_VECTOR2I or
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


func ensure_scene_exists_and_open(
	editor_interface: EditorInterface,
	scene_path: String,
	root_type_hint: String = "",
	root_name_hint: String = ""
) -> Node:
	if scene_path.ends_with(".tscn") and not FileAccess.file_exists(scene_path):
		var rtype := root_type_hint.strip_edges()
		if rtype.is_empty() or not ClassDB.class_exists(rtype) or not ClassDB.can_instantiate(rtype) or not ClassDB.is_parent_class(rtype, "Node"):
			var lower_file := scene_path.get_file().to_lower()
			if "player" in lower_file or "enemy" in lower_file or "crab" in lower_file or "boss" in lower_file:
				rtype = "CharacterBody3D"
			else:
				rtype = "Node3D"
		var rnode := ClassDB.instantiate(rtype) as Node
		if rnode != null:
			rnode.name = root_name_hint if not root_name_hint.is_empty() else scene_path.get_file().get_basename().to_pascal_case()
			var packed := PackedScene.new()
			if packed.pack(rnode) == OK:
				_ensure_dir_for_res_path(scene_path)
				ResourceSaver.save(packed, scene_path)
			rnode.free()
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
		if ln.is_empty():
			continue
		var lower := ln.to_lower()
		if "addons/layers/" in lower or "editoricons" in lower or "vulkan" in lower or "orphan string" in lower:
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


func _check_inspector_prop_ok(node: Node, raw_prop: String, val_str: String) -> bool:
	if node == null:
		return false
	var clean_prop: String = raw_prop.to_lower().strip_edges().replace(" ", "_")
	if "collision_mask" in clean_prop:
		var m_mask: Variant = node.get("collision_mask")
		var num_re := RegEx.new()
		num_re.compile("([0-9]+)")
		var rm: RegExMatch = num_re.search(val_str)
		if rm != null and m_mask is int:
			var expected: int = 1 << (rm.get_string(1).to_int() - 1) if "layer" in val_str.to_lower() else rm.get_string(1).to_int()
			return (m_mask as int & expected) == expected
	var cur_val: Variant = node.get(clean_prop)
	if cur_val == null:
		return false
	if cur_val is float:
		var f_exp: float = _extract_first_float(val_str)
		return not is_nan(f_exp) and is_equal_approx(cur_val as float, f_exp)
	if cur_val is int:
		var i_exp: float = _extract_first_float(val_str)
		return not is_nan(i_exp) and (cur_val as int) == int(i_exp)
	if cur_val is bool:
		var vl: String = val_str.to_lower()
		var b_exp: bool = (vl == "true" or vl == "on" or vl == "yes" or vl == "1")
		return (cur_val as bool) == b_exp
	return str(cur_val).to_lower() == val_str.to_lower()


func _apply_inspector_setting_to_node(node: Node, raw_prop: String, val_str: String, undo_redo: EditorUndoRedoManager) -> bool:
	var sp: Dictionary = {"props": {}, "subProps": {}}
	_assign_single_prop(sp, raw_prop, val_str)
	var props: Dictionary = sp.get("props", {})
	var applied: bool = false
	for k_raw in props.keys():
		var prop_key: String = str(k_raw)
		var new_val: Variant = props[k_raw]
		if undo_redo != null:
			undo_redo.add_do_property(node, prop_key, new_val)
			undo_redo.add_undo_property(node, prop_key, node.get(prop_key))
		else:
			node.set(prop_key, new_val)
		applied = true
	return applied


func _apply_props_to_object(obj: Object, props: Dictionary) -> void:
	if obj == null or props.is_empty():
		return
	for k_raw in props.keys():
		var prop_name: String = str(k_raw)
		if obj.get(prop_name) != null:
			obj.set(prop_name, props[k_raw])


func _is_abstract_subresource_class(cls_name: String) -> bool:
	return cls_name in PackedStringArray([
		"Shape3D", "Shape2D", "Mesh", "Material", "Texture", "Texture2D", "Resource"
	])


func _parse_subresource_decl(raw_val: String, prop_hint: String = "") -> Dictionary:
	var raw := raw_val.strip_edges()
	var cls_part := raw
	var inner_params := ""
	var open_idx := raw.find("(")
	if open_idx > 0:
		cls_part = raw.substr(0, open_idx).strip_edges()
		var close_idx := raw.rfind(")")
		if close_idx > open_idx:
			inner_params = raw.substr(open_idx + 1, close_idx - open_idx - 1).strip_edges()

	# Normalize bare abstract hints to concrete subclasses (Godot 4.7.2 allows ClassDB.can_instantiate on Mesh!).
	if cls_part == "Shape3D":
		if "radius" in inner_params.to_lower() and "height" in inner_params.to_lower():
			cls_part = "CapsuleShape3D" if "capsule" in raw.to_lower() else "CylinderShape3D"
		elif "radius" in inner_params.to_lower():
			cls_part = "SphereShape3D"
		else:
			cls_part = "BoxShape3D"
	elif cls_part == "Shape2D":
		cls_part = "CircleShape2D" if "radius" in inner_params.to_lower() else "RectangleShape2D"
	elif cls_part == "Mesh":
		cls_part = "SphereMesh" if "radius" in inner_params.to_lower() else "BoxMesh"

	if not ClassDB.class_exists(cls_part) or _is_abstract_subresource_class(cls_part) or not ClassDB.can_instantiate(cls_part):
		if prop_hint == "shape":
			cls_part = "BoxShape3D"
		elif prop_hint == "mesh":
			cls_part = "BoxMesh"
		else:
			return {}

	var props := {}
	if not inner_params.is_empty():
		var parts := _split_top_level_commas(inner_params)
		var bare_floats: Array[float] = []
		var all_bare := parts.size() > 0
		for seg in parts:
			var t := seg.strip_edges()
			if not t.is_valid_float():
				all_bare = false
				break
			bare_floats.append(t.to_float())

		if all_bare:
			if bare_floats.size() == 3 and (cls_part == "BoxMesh" or cls_part == "BoxShape3D"):
				props["size"] = Vector3(bare_floats[0], bare_floats[1], bare_floats[2])
			elif bare_floats.size() == 2 and (cls_part == "RectangleShape2D"):
				props["size"] = Vector2(bare_floats[0], bare_floats[1])
			elif bare_floats.size() == 2 and cls_part in PackedStringArray(["CapsuleShape3D", "CapsuleMesh", "CylinderShape3D", "CylinderMesh"]):
				if cls_part == "CylinderMesh":
					props["top_radius"] = bare_floats[0]
					props["bottom_radius"] = bare_floats[0]
				else:
					props["radius"] = bare_floats[0]
				props["height"] = bare_floats[1]
			elif bare_floats.size() == 1 and cls_part in PackedStringArray(["SphereShape3D", "SphereMesh", "CircleShape2D"]):
				props["radius"] = bare_floats[0]
				if cls_part == "SphereMesh":
					props["height"] = bare_floats[0] * 2.0
		else:
			for seg in parts:
				var seg_t := seg.strip_edges()
				var seg_low := seg_t.to_lower()
				if seg_low.begins_with("top radius") or seg_low.begins_with("top_radius"):
					props["top_radius"] = _extract_first_float(seg_t)
				elif seg_low.begins_with("bottom radius") or seg_low.begins_with("bottom_radius"):
					props["bottom_radius"] = _extract_first_float(seg_t)
				elif seg_low.begins_with("radius") or seg_low.begins_with("r=") or seg_low.begins_with("r "):
					var r_val := _extract_first_float(seg_t)
					if cls_part == "CylinderMesh":
						props["top_radius"] = r_val
						props["bottom_radius"] = r_val
					else:
						props["radius"] = r_val
						if cls_part == "SphereMesh" and not props.has("height"):
							props["height"] = r_val * 2.0
				elif seg_low.begins_with("height") or seg_low.begins_with("h=") or seg_low.begins_with("h "):
					props["height"] = _extract_first_float(seg_t)
				elif "size" in seg_low:
					var vec := _parse_vector3_literal(seg_t)
					if typeof(vec) == TYPE_VECTOR3:
						props["size"] = vec
					else:
						var vec2 := _parse_vector2_literal(seg_t)
						if typeof(vec2) == TYPE_VECTOR2:
							props["size"] = vec2

	return { "class": cls_part, "props": props }


func _parse_standard_material_decl(raw_val: String) -> Dictionary:
	var low := raw_val.strip_edges().to_lower()
	if not ("material" in low or "emission" in low or "glow" in low or "color" in low or "orange" in low or "red" in low or "green" in low or "blue" in low or "cyan" in low or "yellow" in low or "sand" in low or "rock" in low or "ocean" in low):
		return {}
	var col := Color(0.85, 0.85, 0.88)
	if "orange" in low:
		col = Color(1.0, 0.48, 0.08)
	elif "red" in low:
		col = Color(0.95, 0.22, 0.2)
	elif "green" in low:
		col = Color(0.22, 0.85, 0.35)
	elif "cyan" in low:
		col = Color(0.15, 0.85, 0.95)
	elif "blue" in low or "ocean" in low or "water" in low:
		col = Color(0.16, 0.48, 0.85)
	elif "yellow" in low or "gold" in low:
		col = Color(0.98, 0.82, 0.2)
	elif "purple" in low or "magenta" in low:
		col = Color(0.75, 0.3, 0.95)
	elif "sand" in low or "tan" in low:
		col = Color(0.84, 0.74, 0.55)
	elif "rock" in low or "gray" in low or "grey" in low:
		col = Color(0.45, 0.47, 0.5)
	var mat := { "albedo_color": col }
	if "emission" in low or "glow" in low:
		mat["emission_enabled"] = true
		mat["emission"] = col
		mat["emission_energy_multiplier"] = 2.0
	return mat


func _apply_material_dict_to_node(node: Node, mat_props: Dictionary) -> bool:
	if node == null or mat_props.is_empty():
		return false
	if not (node is GeometryInstance3D):
		return false
	var gi := node as GeometryInstance3D
	var mat := gi.material_override as StandardMaterial3D
	var changed := false
	if mat == null:
		mat = StandardMaterial3D.new()
		gi.material_override = mat
		changed = true
	for k in mat_props.keys():
		var val: Variant = _coerce_prop_value(mat_props[k], "")
		if mat.get(k) != val:
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
		if s.begins_with("res://") and ResourceLoader.exists(s):
			return ResourceLoader.load(s, "", ResourceLoader.CACHE_MODE_IGNORE)
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
	if (prop_name == "size" or prop_name == "position" or prop_name == "rotation_degrees" or prop_name == "scale") and typeof(val) == TYPE_ARRAY:
		var arr: Array = val
		if arr.size() == 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
		if arr.size() == 2:
			return Vector2(float(arr[0]), float(arr[1]))
	return val


func _sync_existing_node_from_spec(node: Node, sp: Dictionary, _undo_redo: EditorUndoRedoManager = null) -> bool:
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
				for k in sr_props.keys():
					var cv: Variant = _coerce_prop_value(sr_props[k], String(k))
					if cur_shape.get(k) != cv:
						cur_shape.set(k, cv)
						changed = true
		elif node is MeshInstance3D:
			var cur_mesh: Variant = node.get("mesh")
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
		if _apply_material_dict_to_node(node, mat_props):
			changed = true

	var props: Dictionary = sp.get("props", {})
	for pk in props.keys():
		var pv: Variant = _coerce_prop_value(props[pk], String(pk))
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
	var err := scr.reload(true)
	return {
		"ok": err == OK,
		"error_code": err,
		"error": "" if err == OK else "GDScript compile check failed (code %d)." % err,
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


func _resolve_signal_receiver_node(scene_root: Node, src_node: Node, target_hint: String, method_name: String) -> Node:
	if scene_root == null:
		return null
	if not target_hint.is_empty() and target_hint != ".":
		var hinted := _find_node_recursive(scene_root, target_hint)
		if hinted != null and (hinted != src_node or _script_defines_method(hinted, method_name)):
			return hinted
	# Prefer scene root when its script defines the method (or when hint was ".").
	if _script_defines_method(scene_root, method_name):
		return scene_root
	# Search all descendants that have a script defining method_name.
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if _script_defines_method(cur, method_name):
			return cur
		for ch in cur.get_children():
			stack.append(ch)
	# Never default a Timer/emitter self-connection onto itself.
	return scene_root


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

	var cb := Callable(tgt_node, method_name)
	if src_node.is_connected(sig_name, cb):
		return { "ok": true, "changed": false, "detail": "%s.%s -> %s.%s" % [src_node.name, sig_name, tgt_node.name, method_name] }
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
		var eff := resolve_effective_step_path(st, feat, null)
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


func evaluate_feature(
	feat: Dictionary,
	editor_interface: EditorInterface,
	code_files: Dictionary = {},
	arena_hint: String = ""
) -> Dictionary:
	heal_empty_project_input_actions(feat)
	var paths := resolve_feature_paths(feat, code_files, arena_hint)
	var primary_scene := String(paths.get("primary_scene", ""))
	var script_paths: Array = paths.get("script_paths", [])
	var items: Array[Dictionary] = []

	var editor_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
	var primary_open := editor_root != null and (
		primary_scene.is_empty() or
		editor_root.scene_file_path == primary_scene
	)
	var eval_root: Node = editor_root
	var temp_eval_root: Node = null
	if not primary_open and not primary_scene.is_empty() and ResourceLoader.exists(primary_scene):
		var ps := ResourceLoader.load(primary_scene, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if ps != null:
			temp_eval_root = ps.instantiate()
			if temp_eval_root != null:
				eval_root = temp_eval_root

	if not primary_scene.is_empty():
		var exists := FileAccess.file_exists(primary_scene)
		items.append({
			"ok": exists,
			"label": "%s on disk" % primary_scene.get_file(),
			"kind": "scene",
		})

	var steps: Array = feat.get("steps", [])
	var seen_nodes := {}
	var seen_inputs := {}
	var seen_signals := {}
	for st in steps:
		var st_role := String(st.get("role", st.get("stepRole", ""))).strip_edges().to_upper()
		if st_role == "FIX":
			continue
		for sp in parse_scene_node_specs(st):
			var nname := String(sp.get("name", ""))
			if nname.is_empty() or seen_nodes.has(nname):
				continue
			seen_nodes[nname] = true
			var ok_n := false
			if eval_root != null:
				var found := _resolve_spec_node(eval_root, sp)
				if found != null:
					ok_n = true
					var sr_cls := String(sp.get("subResourceClass", ""))
					if not sr_cls.is_empty() and (found is CollisionShape3D or found is CollisionShape2D):
						if found.get("shape") == null:
							ok_n = false
					elif not sr_cls.is_empty() and found is MeshInstance3D:
						if found.get("mesh") == null:
							ok_n = false
			items.append({
				"ok": ok_n,
				"label": "Node: %s (%s)" % [nname, String(sp.get("type", "Node"))],
				"kind": "node",
			})

		for inp in parse_input_specs(st):
			var act := String(inp.get("action", ""))
			if act.is_empty() or seen_inputs.has(act):
				continue
			seen_inputs[act] = true
			items.append({
				"ok": _has_real_input_binding(act, "input/" + act),
				"label": "Input: %s" % act,
				"kind": "input",
			})

		for sig in parse_signal_specs(st, eval_root):
			var sig_n := String(sig.get("signalName", sig.get("signal", "")))
			var key := "%s.%s->%s" % [String(sig.get("source", "")), sig_n, String(sig.get("method", ""))]
			if seen_signals.has(key):
				continue
			seen_signals[key] = true
			var ok_sig := false
			if eval_root != null:
				var src_n := _find_node_recursive(eval_root, String(sig.get("source", "")))
				if src_n != null and src_n.has_signal(sig_n):
					for conn in src_n.get_signal_connection_list(sig_n):
						var cb: Callable = conn.get("callable", Callable())
						if cb.is_valid() and String(cb.get_method()) == String(sig.get("method", "")) and cb.get_object() != src_n:
							ok_sig = true
							break
			items.append({
				"ok": ok_sig,
				"label": "Signal: %s.%s" % [String(sig.get("source", "")), sig_n],
				"kind": "signal",
			})

	var attached_in_scene := _collect_attached_script_paths(eval_root)
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
		items.append({
			"ok": is_valid,
			"label": "Script: %s" % sp_str.get_file(),
			"kind": "script",
		})

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
						items.append({
							"ok": true,
							"label": "Script: %s" % asp.get_file(),
							"kind": "script",
						})

	if temp_eval_root != null:
		temp_eval_root.free()

	var scene_ok := primary_scene.is_empty() or FileAccess.file_exists(primary_scene)
	var any_script_ok := valid_scripts.size() > 0
	if items.is_empty():
		items.append({
			"ok": scene_ok and any_script_ok,
			"label": "Feature scene & script generated",
			"kind": "script",
		})

	var has_built_artifacts := (
		(not primary_scene.is_empty() and FileAccess.file_exists(primary_scene) and (filtered_scripts.is_empty() or any_script_ok)) or
		(primary_scene.is_empty() and any_script_ok)
	)

	var ready := 0
	for it in items:
		if bool(it.get("ok", false)):
			ready += 1
	return {
		"total": items.size(),
		"ready": ready,
		"all_ready": items.size() > 0 and ready == items.size(),
		"has_built_artifacts": has_built_artifacts,
		"missing_count": items.size() - ready,
		"items": items,
		"primary_scene": primary_scene,
		"arena_scene": String(paths.get("arena_scene", "")),
		"script_paths": filtered_scripts,
	}


func build_feature_local(
	feat: Dictionary,
	editor_interface: EditorInterface,
	undo_redo: EditorUndoRedoManager,
	code_files: Dictionary = {},
	arena_hint: String = ""
) -> Dictionary:
	heal_empty_project_input_actions(feat)
	var paths := resolve_feature_paths(feat, code_files, arena_hint)
	var primary_scene := String(paths.get("primary_scene", ""))
	var arena_scene := String(paths.get("arena_scene", ""))
	var actions := PackedStringArray()

	var root: Node = null
	if not primary_scene.is_empty() and editor_interface != null:
		root = ensure_scene_exists_and_open(editor_interface, primary_scene)
	elif editor_interface != null:
		root = editor_interface.get_edited_scene_root()
	if root != null:
		var detached := detach_incompatible_scripts(root)
		for d in detached:
			actions.append("Detached mismatched script: %s" % d)

	var steps: Array = feat.get("steps", [])
	for st in steps:
		var st_role := String(st.get("role", st.get("stepRole", ""))).strip_edges().to_upper()
		if st_role == "FIX":
			continue
		var st_eval: Dictionary = evaluate_step(feat, st, editor_interface)
		if root != null:
			var node_res: Dictionary = build_missing_scene_nodes(editor_interface, undo_redo, st, st_eval)
			var msg := String(node_res.get("message", "")).strip_edges()
			var added_n := int(node_res.get("addedCount", 0))
			if added_n > 0:
				actions.append(msg if not msg.is_empty() else ("Built %d node(s)" % added_n))
			apply_input_and_inspector(editor_interface, undo_redo, st, st_eval)
		else:
			for inp in parse_input_specs(st):
				var act := String(inp.get("action", ""))
				if not act.is_empty() and not _has_real_input_binding(act, "input/" + act):
					apply_input_and_inspector(editor_interface, undo_redo, st, st_eval)
					break

	# Write synced/merged GDScript files & attach safely with ClassDB guard.
	for spath in paths.get("script_paths", []):
		var sp_str := String(spath)
		var synced_code := String(code_files.get(sp_str, "")).strip_edges()
		if not synced_code.is_empty():
			var chk := check_gdscript_compiles(synced_code)
			if bool(chk.get("ok", false)):
				_ensure_dir_for_res_path(sp_str)
				var f := FileAccess.open(sp_str, FileAccess.WRITE)
				if f != null:
					f.store_string(synced_code + "\n")
					f.close()
					reload_script_safely(sp_str, synced_code + "\n")
					actions.append("Synced %s" % sp_str.get_file())

	for st in steps:
		var st_role := String(st.get("role", st.get("stepRole", ""))).strip_edges().to_upper()
		if st_role == "FIX":
			continue
		var code_text := resolve_step_code_text(st)
		if not code_text.is_empty():
			var eff_path := resolve_effective_step_path(st, feat, root)
			if eff_path.ends_with(".gd"):
				var st_eval: Dictionary = evaluate_step(feat, st, editor_interface)
				if root != null:
					var target_name := _infer_script_target_node_name(st, eff_path, root)
					var target_node := root if (target_name.is_empty() or target_name == root.name) else _find_node_recursive(root, target_name)
					if target_node != null and can_attach_script_to_node(target_node, code_text):
						apply_or_create_script(editor_interface, undo_redo, st, st_eval)
					elif target_node != null:
						actions.append("Skipped incompatible script %s for %s (%s)" % [eff_path.get_file(), target_node.name, target_node.get_class()])
				else:
					apply_or_create_script(editor_interface, undo_redo, st, st_eval)

	if root != null:
		for st in steps:
			var st_role := String(st.get("role", st.get("stepRole", ""))).strip_edges().to_upper()
			if st_role == "FIX":
				continue
			for sig in parse_signal_specs(st, root):
				_connect_single_signal_safe(
					root,
					String(sig.get("source", "")),
					String(sig.get("signalName", sig.get("signal", ""))),
					String(sig.get("target", "")),
					String(sig.get("method", ""))
				)

	if editor_interface != null and root != null:
		sanitize_null_script_exports(root)
		editor_interface.save_scene()

	# Also wire arena instances cleanly if any step mentions arena_scene.
	if not arena_scene.is_empty() and arena_scene != primary_scene and editor_interface != null:
		var inst_needed := false
		for st in steps:
			if parse_scene_instance_specs(st, arena_scene).size() > 0:
				inst_needed = true
				break
		if inst_needed:
			var arena_root := ensure_scene_exists_and_open(editor_interface, arena_scene)
			if arena_root != null:
				detach_incompatible_scripts(arena_root)
				for st in steps:
					var st_role := String(st.get("role", st.get("stepRole", ""))).strip_edges().to_upper()
					if st_role == "FIX":
						continue
					var st_eval: Dictionary = evaluate_step(feat, st, editor_interface)
					build_missing_scene_nodes(editor_interface, undo_redo, st, st_eval)
				sanitize_null_script_exports(arena_root)
				editor_interface.save_scene()

	ensure_main_scene_configured(arena_scene, primary_scene)
	var summary := "Feature scaffold ready." if actions.is_empty() else "; ".join(actions)
	return { "ok": true, "summary": summary, "actions": actions }


func apply_agent_bundle(
	editor_interface: EditorInterface,
	undo_redo: EditorUndoRedoManager,
	bundle: Dictionary
) -> Dictionary:
	var applied_scripts := PackedStringArray()
	var warnings := PackedStringArray()
	var applied_ops := 0
	var root_type_hints := {}

	# 1. Compile-verify & save all scriptUpdates first.
	for raw_u in bundle.get("scriptUpdates", []):
		if typeof(raw_u) != TYPE_DICTIONARY:
			continue
		var u: Dictionary = raw_u
		var rpath := String(u.get("resPath", "")).strip_edges()
		var content := strip_diff_prefixes(String(u.get("content", "")))
		if rpath.is_empty() or content.is_empty():
			continue
		var chk := check_gdscript_compiles(content)
		if not bool(chk.get("ok", false)):
			warnings.append("Skipped %s: %s" % [rpath.get_file(), String(chk.get("error", "compile error"))])
			continue
		_ensure_dir_for_res_path(rpath)
		var f := FileAccess.open(rpath, FileAccess.WRITE)
		if f == null:
			warnings.append("Could not write %s." % rpath)
			continue
		f.store_string(content + "\n")
		f.close()
		reload_script_safely(rpath, content + "\n")
		applied_scripts.append(rpath)
		var uspath := String(u.get("scenePath", "")).strip_edges()
		var uattach := String(u.get("attachTo", "")).strip_edges()
		if not uspath.is_empty() and (uattach == "." or uattach == uspath.get_file().get_basename().to_pascal_case()):
			var ext_cls := extract_script_extends(content)
			if not ext_cls.is_empty():
				root_type_hints[uspath] = ext_cls

	# 2. Group sceneOps by scenePath and execute safely.
	var ops_by_scene := {}
	var default_scene := ""
	if editor_interface != null and editor_interface.get_edited_scene_root() != null:
		default_scene = editor_interface.get_edited_scene_root().scene_file_path
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
		if String(op_dict.get("op", "")).to_lower() == "attach_script" and String(op_dict.get("nodePath", ".")) == ".":
			var sp_att := String(op_dict.get("scriptPath", "")).strip_edges()
			if FileAccess.file_exists(sp_att):
				var fa := FileAccess.open(sp_att, FileAccess.READ)
				if fa != null:
					var ext2 := extract_script_extends(fa.get_as_text())
					fa.close()
					if not ext2.is_empty():
						root_type_hints[spath] = ext2

	for spath_key in ops_by_scene.keys():
		var spath_str := String(spath_key)
		var scene_ops: Array = ops_by_scene[spath_str]
		var target_root: Node = null
		if editor_interface != null:
			var rhint := String(root_type_hints.get(spath_str, ""))
			target_root = ensure_scene_exists_and_open(editor_interface, spath_str, rhint)
		if target_root == null:
			warnings.append("Could not open scene %s for sceneOps." % spath_str)
			continue
		detach_incompatible_scripts(target_root)
		applied_ops += apply_scene_ops_to_root(target_root, scene_ops, undo_redo, warnings)
		if editor_interface != null:
			sanitize_null_script_exports(target_root)
			editor_interface.save_scene()

	# Also attach scriptUpdates that specify attachTo + scenePath if not already handled in sceneOps.
	if editor_interface != null:
		for raw_u in bundle.get("scriptUpdates", []):
			if typeof(raw_u) != TYPE_DICTIONARY:
				continue
			var u: Dictionary = raw_u
			var rpath := String(u.get("resPath", "")).strip_edges()
			var attach_to := String(u.get("attachTo", "")).strip_edges()
			var spath := String(u.get("scenePath", default_scene)).strip_edges()
			if rpath.is_empty() or attach_to.is_empty() or spath.is_empty() or not FileAccess.file_exists(rpath):
				continue
			var sroot := ensure_scene_exists_and_open(editor_interface, spath, String(root_type_hints.get(spath, "")))
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
					editor_interface.save_scene()
					applied_ops += 1

	heal_empty_project_input_actions()
	ensure_main_scene_configured(default_scene, String(bundle.get("arenaScenePath", "")))
	var summary := String(bundle.get("summary", "")).strip_edges()
	if summary.is_empty():
		summary = "Updated %d script(s), %d scene op(s)." % [applied_scripts.size(), applied_ops]
	return {
		"ok": warnings.is_empty() or applied_scripts.size() > 0 or applied_ops > 0,
		"summary": summary,
		"applied_scripts": applied_scripts,
		"applied_ops": applied_ops,
		"warnings": warnings,
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


func apply_scene_ops_to_root(
	scene_root: Node,
	ops: Array,
	_undo_redo: EditorUndoRedoManager = null,
	warnings: PackedStringArray = PackedStringArray()
) -> int:
	if scene_root == null:
		return 0
	var count := 0
	for raw_op in ops:
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op_dict: Dictionary = raw_op
		var op := String(op_dict.get("op", "")).strip_edges().to_lower()
		if op == "detach_script":
			var np := String(op_dict.get("nodePath", "."))
			var node := _resolve_op_node(scene_root, np)
			if node != null and node.get_script() != null:
				node.set_script(null)
				count += 1
		elif op == "attach_script":
			var np := String(op_dict.get("nodePath", "."))
			var spath := String(op_dict.get("scriptPath", "")).strip_edges()
			var node := _resolve_op_node(scene_root, np)
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
			var node_type := String(op_dict.get("nodeType", "Node")).strip_edges()
			if node_name.is_empty():
				continue
			var parent := _resolve_op_node(scene_root, parent_p)
			if parent == null:
				parent = scene_root
			var node := parent.get_node_or_null(node_name)
			if node == null:
				if not ClassDB.class_exists(node_type) or not ClassDB.can_instantiate(node_type):
					node_type = "Node"
				node = ClassDB.instantiate(node_type) as Node
				if node == null:
					continue
				node.name = node_name
				parent.add_child(node)
				node.owner = scene_root
				count += 1
			var sr_cls := String(op_dict.get("subResourceClass", "")).strip_edges()
			var sr_props: Dictionary = op_dict.get("subResourceProps", {})
			var fake_sp := {
				"subResourceClass": sr_cls,
				"subResourceProps": sr_props,
				"props": op_dict.get("properties", {}),
			}
			if _sync_existing_node_from_spec(node, fake_sp):
				count += 1
			var attach_sp := String(op_dict.get("scriptPath", "")).strip_edges()
			if not attach_sp.is_empty() and FileAccess.file_exists(attach_sp) and can_attach_script_to_node(node, attach_sp):
				var sres: Script = reload_script_safely(attach_sp)
				if sres != null:
					node.set_script(sres)
					count += 1
		elif op == "set_property":
			var np := String(op_dict.get("nodePath", "."))
			var node := _resolve_op_node(scene_root, np)
			if node == null:
				warnings.append("set_property node not found: %s" % np)
				continue
			var props: Dictionary = op_dict.get("properties", {})
			for pk in props.keys():
				var pk_str := String(pk)
				var raw_v: Variant = props[pk]
				if (pk_str == "material" or pk_str == "material_override") and typeof(raw_v) == TYPE_DICTIONARY:
					_apply_material_dict_to_node(node, raw_v)
				else:
					node.set(pk_str, _coerce_prop_value(raw_v, pk_str))
				count += 1
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
			var inst_node: Node = existing
			if inst_node == null:
				var pscene: PackedScene = ResourceLoader.load(ipath, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
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
				inst_node.set(String(pk), _coerce_prop_value(props[pk], String(pk)))
				count += 1
		elif op == "remove_node":
			var np := String(op_dict.get("nodePath", "")).strip_edges()
			var node := _resolve_op_node(scene_root, np)
			if node != null and node != scene_root:
				if node.get_parent() != null:
					node.get_parent().remove_child(node)
				node.queue_free()
				count += 1
	return count


func extract_feature_export_tuners(script_paths: Array) -> Array:
	var tuners: Array = []
	var seen := {}
	var rx := RegEx.new()
	rx.compile("^(@export(?:_[a-z]+)?(?:\\(([^)]*)\\))?\\s+var\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(?::\\s*([A-Za-z0-9_]+))?\\s*=\\s*([^#\\n]+))")
	for sp in script_paths:
		var spath := String(sp).strip_edges()
		if spath.is_empty() or not FileAccess.file_exists(spath):
			continue
		var f := FileAccess.open(spath, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		for line in text.split("\n"):
			var m := rx.search(line.strip_edges())
			if m == null:
				continue
			var hint_args := m.get_string(2).strip_edges()
			var var_name := m.get_string(3).strip_edges()
			var var_type := m.get_string(4).strip_edges().to_lower()
			var raw_default := m.get_string(5).strip_edges()
			var key := "%s::%s" % [spath, var_name]
			if seen.has(key):
				continue
			seen[key] = true

			var inferred_type := var_type
			var val: Variant = raw_default
			if inferred_type == "bool" or raw_default == "true" or raw_default == "false":
				inferred_type = "bool"
				val = (raw_default == "true")
			elif inferred_type == "int" or (inferred_type.is_empty() and raw_default.is_valid_int()):
				inferred_type = "int"
				val = raw_default.to_int()
			elif inferred_type == "float" or raw_default.is_valid_float():
				inferred_type = "float"
				val = raw_default.to_float()
			elif var_type == "packedscene":
				inferred_type = "packed_scene"
				val = raw_default.trim_prefix("\"").trim_suffix("\"")
			else:
				continue

			var min_v := 0.0
			var max_v := 100.0
			var step_v := 1.0 if inferred_type == "int" else 0.1
			if not hint_args.is_empty():
				var hp := hint_args.split(",", false)
				if hp.size() >= 2 and hp[0].strip_edges().is_valid_float() and hp[1].strip_edges().is_valid_float():
					min_v = hp[0].strip_edges().to_float()
					max_v = hp[1].strip_edges().to_float()
				if hp.size() >= 3 and hp[2].strip_edges().is_valid_float():
					step_v = maxf(0.01, hp[2].strip_edges().to_float())
			if typeof(val) == TYPE_FLOAT and float(val) > max_v:
				max_v = float(val) * 2.0
			elif typeof(val) == TYPE_INT and float(val) > max_v:
				max_v = float(val) * 2.0

			tuners.append({
				"script_path": spath,
				"name": var_name,
				"label": var_name.capitalize(),
				"type": inferred_type,
				"value": val,
				"min": min_v,
				"max": max_v,
				"step": step_v,
			})
	return tuners


func apply_export_tuner_value(
	script_path: String,
	prop_name: String,
	new_value: Variant,
	editor_interface: EditorInterface = null,
	_undo_redo: EditorUndoRedoManager = null
) -> Dictionary:
	if not FileAccess.file_exists(script_path):
		return { "ok": false, "error": "Script not found: %s" % script_path }
	var f := FileAccess.open(script_path, FileAccess.READ)
	if f == null:
		return { "ok": false, "error": "Cannot read %s." % script_path }
	var lines := f.get_as_text().split("\n")
	f.close()

	var formatted_val := ""
	if typeof(new_value) == TYPE_BOOL:
		formatted_val = "true" if bool(new_value) else "false"
	elif typeof(new_value) == TYPE_INT:
		formatted_val = str(int(new_value))
	elif typeof(new_value) == TYPE_FLOAT:
		formatted_val = "%.3f" % float(new_value)
		while formatted_val.ends_with("0") and not formatted_val.ends_with(".0"):
			formatted_val = formatted_val.substr(0, formatted_val.length() - 1)
	else:
		formatted_val = String(new_value)

	var rx := RegEx.new()
	rx.compile("^(\\s*@export(?:_[a-z]+)?(?:\\([^)]*\\))?\\s+var\\s+" + prop_name + "\\b[^=]*=\\s*)([^#\\n]+)(.*)$")
	var updated_disk := false
	for i in range(lines.size()):
		var m := rx.search(lines[i])
		if m != null:
			var prefix := m.get_string(1)
			var comment_suffix := m.get_string(3)
			lines[i] = "%s%s%s" % [prefix, formatted_val, comment_suffix]
			updated_disk = true
			break

	if updated_disk:
		var updated_src := "\n".join(lines)
		var fw := FileAccess.open(script_path, FileAccess.WRITE)
		if fw != null:
			fw.store_string(updated_src)
			fw.close()
			reload_script_safely(script_path, updated_src)

	var updated_nodes := 0
	if editor_interface != null:
		var root := editor_interface.get_edited_scene_root()
		if root != null:
			var stack: Array[Node] = [root]
			while not stack.is_empty():
				var cur: Node = stack.pop_back()
				var scr: Variant = cur.get_script()
				if scr is Script and String((scr as Script).resource_path) == script_path:
					cur.set(prop_name, new_value)
					updated_nodes += 1
				for ch in cur.get_children():
					stack.append(ch)
			if updated_nodes > 0:
				sanitize_null_script_exports(root)
				editor_interface.save_scene()

	return {
		"ok": updated_disk or updated_nodes > 0,
		"updated_disk": updated_disk,
		"updated_nodes": updated_nodes,
	}


func _snapshot_node_tree(root: Node, limit_nodes: int = 80) -> Array:
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
		if cur is CollisionShape3D or cur is CollisionShape2D:
			var shp: Variant = cur.get("shape")
			entry["shape"] = shp.get_class() if shp != null else "<EMPTY>"
		elif cur is MeshInstance3D:
			var msh: Variant = cur.get("mesh")
			entry["mesh"] = msh.get_class() if msh != null else "<EMPTY>"
		elif cur is Area3D or cur is Area2D:
			entry["monitoring"] = cur.get("monitoring")
		elif cur is Timer:
			entry["wait_time"] = cur.get("wait_time")
			entry["one_shot"] = cur.get("one_shot")
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
	var edited_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
	if edited_root != null:
		var ep := edited_root.scene_file_path if not edited_root.scene_file_path.is_empty() else edited_root.name
		scenes[ep] = {
			"isOpenInEditor": true,
			"nodes": _snapshot_node_tree(edited_root),
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


func read_live_scripts_for_feature(feat: Dictionary, code_files: Dictionary = {}, arena_hint: String = "") -> Dictionary:
	var out := {}
	var paths := resolve_feature_paths(feat, code_files, arena_hint)
	for sp in paths.get("script_paths", []):
		var sp_str := String(sp)
		if FileAccess.file_exists(sp_str):
			var f := FileAccess.open(sp_str, FileAccess.READ)
			if f != null:
				out[sp_str] = f.get_as_text()
				f.close()
	# Also include any disk scripts under res://scripts/ already referenced in code_files.
	for cf in code_files.keys():
		var cfp := String(cf)
		if not out.has(cfp) and FileAccess.file_exists(cfp):
			var f2 := FileAccess.open(cfp, FileAccess.READ)
			if f2 != null:
				out[cfp] = f2.get_as_text()
				f2.close()
	return out


func _ensure_dir_for_res_path(res_path: String) -> void:
	var dir_path: String = res_path.get_base_dir()
	if dir_path.is_empty():
		return
	var abs_dir: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
