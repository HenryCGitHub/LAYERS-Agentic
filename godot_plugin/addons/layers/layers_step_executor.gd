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
	var category_suffixes := PackedStringArray(["script", "shape", "mesh", "characterbody3d", "characterbody2d"])
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
		if ClassDB.class_exists(v):
			spec["subResourceClass"] = v
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
	for seg in loc.split(">", false):
		var s: String = seg.strip_edges()
		if s.is_valid_identifier() and not (s in PackedStringArray(["Node", "Signals", "Scene", "Tree"])):
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
			if not root_script_path.is_empty() and FileAccess.file_exists(root_script_path) and scene_root.get_script() == null:
				var scr: Variant = ResourceLoader.load(root_script_path, "Script", ResourceLoader.CACHE_MODE_REPLACE)
				if scr is Script:
					if undo_redo != null:
						undo_redo.add_do_property(scene_root, "script", scr)
						undo_redo.add_undo_property(scene_root, "script", null)
					else:
						scene_root.set_script(scr)
			continue

		if _resolve_spec_node(scene_root, sp) != null:
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
	if not attach_gd.is_empty() and FileAccess.file_exists(attach_gd):
		var scr: Variant = ResourceLoader.load(attach_gd, "Script", ResourceLoader.CACHE_MODE_REPLACE)
		if scr is Script:
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
		var ev_arr: Array = []
		if ev != null:
			ev_arr.append(ev)
		if not _has_real_input_binding(act, setting_key):
			ProjectSettings.set_setting(setting_key, {"deadzone": 0.2, "events": ev_arr})
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

	var scr: Script = ResourceLoader.load(step_path, "Script", ResourceLoader.CACHE_MODE_REPLACE) as Script
	if scr == null:
		scr = load(step_path) as Script

	var attached_new: bool = false
	if scene_root != null and scr != null and _find_node_with_script(scene_root, step_path) == null:
		var attach_to: Node = target_node
		if attach_to == null and editor_interface != null and editor_interface.get_selection() != null:
			var sel: Array = editor_interface.get_selection().get_selected_nodes()
			if not sel.is_empty() and sel[0] is Node:
				attach_to = sel[0] as Node
		if attach_to == null:
			attach_to = scene_root
		if attach_to != null and attach_to.get_script() == null:
			if undo_redo != null:
				undo_redo.create_action("LAYERS: Attach %s" % step_path.get_file())
				undo_redo.add_do_property(attach_to, "script", scr)
				undo_redo.add_undo_property(attach_to, "script", null)
				undo_redo.commit_action()
			else:
				attach_to.set_script(scr)
			attached_new = true
			if editor_interface != null:
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
		var dst_node: Node = _find_node_recursive(scene_root, dst_name) if not dst_name.is_empty() else scene_root
		if src_node != null and first_src == null:
			first_src = src_node
		if src_node != null and dst_node != null and src_node.has_signal(sig_name) and not method_name.is_empty():
			var cb := Callable(dst_node, method_name)
			if not src_node.is_connected(sig_name, cb):
				src_node.connect(sig_name, cb, Object.CONNECT_PERSIST)
			connected_cnt += 1

	if connected_cnt > 0:
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
		return "%s does not exist yet — click Build Missing Scene Nodes." % res_path
	if not FileAccess.file_exists(res_path):
		return "%s does not exist yet — click Create & Attach Script." % res_path
	var res: Resource = ResourceLoader.load(res_path, "", ResourceLoader.CACHE_MODE_REPLACE)
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


func _build_input_event_for_label(key_label: String) -> InputEvent:
	var k: String = key_label.strip_edges().to_upper()
	if k.is_empty():
		return null
	if k == "LMB" or k == "MOUSE LEFT" or k == "LEFT CLICK":
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		return mb
	if k == "RMB" or k == "MOUSE RIGHT" or k == "RIGHT CLICK":
		var mb2 := InputEventMouseButton.new()
		mb2.button_index = MOUSE_BUTTON_RIGHT
		return mb2

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
		"SPACE", "SPACEBAR":
			keycode = KEY_SPACE
		"SHIFT":
			keycode = KEY_SHIFT
		"CTRL", "CONTROL":
			keycode = KEY_CTRL
		"ESC", "ESCAPE":
			keycode = KEY_ESCAPE
		"ENTER", "RETURN":
			keycode = KEY_ENTER
		"TAB":
			keycode = KEY_TAB
		"UP", "ARROW UP":
			keycode = KEY_UP
		"DOWN", "ARROW DOWN":
			keycode = KEY_DOWN
		"LEFT", "ARROW LEFT":
			keycode = KEY_LEFT
		"RIGHT", "ARROW RIGHT":
			keycode = KEY_RIGHT
		_:
			keycode = OS.find_keycode_from_string(k)

	if keycode == KEY_NONE:
		return null
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	return ev


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


func _ensure_dir_for_res_path(res_path: String) -> void:
	var dir_path: String = res_path.get_base_dir()
	if dir_path.is_empty():
		return
	var abs_dir: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
