extends SceneTree

func _init() -> void:
	call_deferred("_run_smoke")


func _write_text(res_path: String, content: String) -> bool:
	var f := FileAccess.open(res_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(content)
	f.close()
	return true


func _run_smoke() -> void:
	var plugin_scripts := [
		"res://addons/layers/layers_step_executor.gd",
		"res://addons/layers/layers_sync_client.gd",
		"res://addons/layers/layers_dock.gd",
		"res://addons/layers/layers_plugin.gd",
	]
	for sp in plugin_scripts:
		var scr := ResourceLoader.load(sp, "", ResourceLoader.CACHE_MODE_IGNORE)
		if scr == null or not (scr is GDScript):
			printerr("FAIL: Could not load plugin script ", sp)
			quit(1)
			return
		var gds := scr as GDScript
		if not sp.ends_with("layers_plugin.gd") and not gds.can_instantiate():
			printerr("FAIL: Plugin script cannot instantiate: ", sp)
			quit(1)
			return

	var exec_scr := ResourceLoader.load("res://addons/layers/layers_step_executor.gd", "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	var exec: Variant = exec_scr.new()
	if exec == null:
		printerr("FAIL: Could not instantiate layers_step_executor.gd")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scripts"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes"))

	var fighter_src := """extends CharacterBody3D

@onready var visual_rig: Node3D = $VisualRig
@onready var claw_pivot: Node3D = $ClawPivot

func _physics_process(_delta: float) -> void:
\tvar dir := Vector3(1.0, 0.0, 1.0).normalized()
\tvisual_rig.rotation.y = atan2(dir.x, dir.z)
\tclaw_pivot.rotation.y = deg_to_rad(30.0)
"""
	var enemy_src := """extends CharacterBody3D

@export var strikeRange: float = 2.4
@onready var strike_area: Area3D = $StrikeArea
var hp: float = 30.0

func _ready() -> void:
\tstrike_area.body_entered.connect(_on_hit)

func _physics_process(_delta: float) -> void:
\tif Input.is_action_just_pressed("crab_enemy_action"):
\t\tstrike_area.monitoring = true
\tvar dir := Vector3(0.0, 0.0, 1.0)
\trotation.y = atan2(dir.x, dir.z)
\tvelocity = -global_transform.basis.z * 8.0

func _on_hit(_body: Node3D) -> void:
\tpass

func take_damage(amount: float) -> void:
\thp -= amount
"""
	if not _write_text("res://scripts/smoke_fighter.gd", fighter_src) or not _write_text("res://scripts/smoke_enemy.gd", enemy_src):
		printerr("FAIL: Could not write smoke GDScript fixtures.")
		quit(1)
		return

	var fighter_scr := ResourceLoader.load("res://scripts/smoke_fighter.gd", "", ResourceLoader.CACHE_MODE_IGNORE) as Script

	var root := CharacterBody3D.new()
	root.name = "SmokeFighter"
	root.collision_layer = 1
	root.collision_mask = 1
	root.set_script(fighter_scr)

	var rig := Node3D.new()
	rig.name = "VisualRig"
	root.add_child(rig)
	rig.owner = root

	var pivot := Node3D.new()
	pivot.name = "ClawPivot"
	root.add_child(pivot)
	pivot.owner = root

	var hitbox := Area3D.new()
	hitbox.name = "ClawHitbox"
	hitbox.position = Vector3(0.0, 0.5, -1.1)
	hitbox.collision_mask = 1
	pivot.add_child(hitbox)
	hitbox.owner = root

	var cshape := CollisionShape3D.new()
	cshape.name = "CollisionShape3D"
	cshape.position = Vector3(0.0, 0.5, 1.0)
	cshape.shape = BoxShape3D.new()
	hitbox.add_child(cshape)
	cshape.owner = root

	var ps := PackedScene.new()
	if ps.pack(root) != OK or ResourceSaver.save(ps, "res://scenes/smoke_fighter.tscn") != OK:
		root.free()
		printerr("FAIL: Could not save smoke_fighter.tscn")
		quit(1)
		return
	root.free()

	var findings: PackedStringArray = exec.call(
		"diagnose_project_combat_and_wiring",
		["res://scenes/smoke_fighter.tscn"],
		{
			"res://scripts/smoke_fighter.gd": fighter_src,
			"res://scripts/smoke_enemy.gd": enemy_src,
		},
		null
	)
	var blob := "\n".join(findings)
	var expected_tags := [
		"[HITBOX OFFSET CANCELLED]",
		"[UNROTATED HITBOX PIVOT]",
		"[NON-PLAYER INPUT]",
		"[3D BASIS FLIP]",
		"[HITBOX OVERLAP]",
		"[SILENT HIT FEEDBACK]",
	]
	for tag in expected_tags:
		if not (tag in blob):
			printerr("FAIL: Missing diagnostic tag ", tag, "\nGot:\n", blob)
			quit(1)
			return

	var ps_reload := ResourceLoader.load("res://scenes/smoke_fighter.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var inst := ps_reload.instantiate()
	var ops := [
		{"op": "reparent_node", "nodePath": "ClawPivot", "newParentPath": "VisualRig"},
		{"op": "set_property", "nodePath": "VisualRig/ClawPivot/ClawHitbox", "properties": {"position": [0.0, 0.5, 1.1]}},
		{"op": "set_property", "nodePath": "VisualRig/ClawPivot/ClawHitbox/CollisionShape3D", "properties": {"position": [0.0, 0.0, 0.0], "size": [1.4, 0.8, 1.4]}},
	]
	var applied_count := int(exec.call("apply_scene_ops_to_root", inst, ops))
	if applied_count < 3:
		inst.free()
		printerr("FAIL: Expected >= 3 applied scene ops, got ", applied_count)
		quit(1)
		return
	var moved_cs := inst.get_node_or_null("VisualRig/ClawPivot/ClawHitbox/CollisionShape3D")
	if moved_cs == null:
		inst.free()
		printerr("FAIL: reparent_node did not move ClawPivot under VisualRig")
		quit(1)
		return
	if moved_cs.owner != inst:
		inst.free()
		printerr("FAIL: reparent_node left inconsistent child owner on CollisionShape3D")
		quit(1)
		return

	var ps_fixed := PackedScene.new()
	ps_fixed.pack(inst)
	ResourceSaver.save(ps_fixed, "res://scenes/smoke_fighter.tscn")
	inst.free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://scripts/smoke_enemy.gd"))
	var findings_after: PackedStringArray = exec.call(
		"diagnose_project_combat_and_wiring",
		["res://scenes/smoke_fighter.tscn"],
		{"res://scripts/smoke_fighter.gd": fighter_src},
		null
	)
	if not findings_after.is_empty():
		printerr("FAIL: Expected 0 diagnostics after reparent/offset fix, got:\n", "\n".join(findings_after))
		quit(1)
		return

	exec.call("apply_input_ops", [
		{"action": "dash", "keys": ["Shift"]},
		{"action": "crab_enemy_action", "keys": ["Space"]},
	])
	if not InputMap.has_action("dash"):
		printerr("FAIL: apply_input_ops did not register 'dash'")
		quit(1)
		return
	if InputMap.has_action("crab_enemy_action"):
		printerr("FAIL: apply_input_ops should suppress bogus 'crab_enemy_action'")
		quit(1)
		return
	exec.call("apply_input_ops", [{"action": "dash", "remove": true}])
	if InputMap.has_action("dash"):
		printerr("FAIL: apply_input_ops remove=true did not erase 'dash'")
		quit(1)
		return

	var orig_fighter_disk := FileAccess.get_file_as_string("res://scripts/smoke_fighter.gd")
	var undo_bundle := {
		"mode": "direct_agent",
		"summary": "Temp AI tweak for snapshot test",
		"scriptUpdates": [
			{"resPath": "res://scripts/smoke_fighter.gd", "content": "extends CharacterBody3D\n\nvar tweaked_speed: float = 99.0\n"},
			{"resPath": "res://scripts/smoke_new_ai_helper.gd", "content": "extends Node\n\nvar created_by_ai: bool = true\n"},
		],
		"inputOps": [
			{"action": "smoke_ai_jump", "keys": ["Space"]},
		],
		"sceneOps": [],
	}
	var pre_snap: Dictionary = exec.call("capture_bundle_snapshot", null, undo_bundle, "res://scenes/smoke_fighter.tscn")
	var bundle_res: Dictionary = exec.call("apply_agent_bundle", null, null, undo_bundle, "res://scenes/smoke_fighter.tscn")
	if not bool(bundle_res.get("ok", false)) or not FileAccess.file_exists("res://scripts/smoke_new_ai_helper.gd") or not InputMap.has_action("smoke_ai_jump"):
		printerr("FAIL: apply_agent_bundle did not apply scriptUpdates/inputOps in smoke probe")
		quit(1)
		return
	var restore_res: Dictionary = exec.call("restore_bundle_snapshot", null, pre_snap)
	if not bool(restore_res.get("ok", false)):
		printerr("FAIL: restore_bundle_snapshot returned ok=false")
		quit(1)
		return
	var restored_scripts: PackedStringArray = restore_res.get("restored_scripts", PackedStringArray())
	if not restored_scripts.has("res://scripts/smoke_fighter.gd") or restored_scripts.has("res://scripts/smoke_new_ai_helper.gd"):
		printerr("FAIL: restore_bundle_snapshot restored_scripts mismatch: ", restored_scripts)
		quit(1)
		return
	if FileAccess.get_file_as_string("res://scripts/smoke_fighter.gd") != orig_fighter_disk:
		printerr("FAIL: restore_bundle_snapshot did not restore exact smoke_fighter.gd contents")
		quit(1)
		return
	if FileAccess.file_exists("res://scripts/smoke_new_ai_helper.gd"):
		printerr("FAIL: restore_bundle_snapshot did not remove newly created smoke_new_ai_helper.gd")
		quit(1)
		return
	if InputMap.has_action("smoke_ai_jump"):
		printerr("FAIL: restore_bundle_snapshot did not remove newly registered 'smoke_ai_jump' InputMap action")
		quit(1)
		return

	var sync_scr := ResourceLoader.load("res://addons/layers/layers_sync_client.gd", "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	var sync_node: Node = sync_scr.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.layers"))
	var legacy_cache_json := JSON.stringify({
		"ok": true,
		"codeFiles": [
			{"resPath": "res://scripts/legacy.gd", "content": "extends Node\n"}
		]
	})
	if not _write_text("res://.layers/epic_cache.json", legacy_cache_json):
		sync_node.free()
		printerr("FAIL: could not write temporary legacy epic_cache.json")
		quit(1)
		return
	sync_node.call("_update_cached_code_files", {"res://scripts/smoke_fighter.gd": orig_fighter_disk})
	var reloaded_cache: Dictionary = sync_node.call("load_cached_epic")
	sync_node.free()
	var cache_cf: Variant = reloaded_cache.get("codeFiles", null)
	var cleanup_ok := true
	for tmp_f in ["res://.layers/epic_cache.json", "res://.layers/.gdignore", "res://.layers/.gitignore"]:
		if FileAccess.file_exists(tmp_f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.layers"))
	if typeof(cache_cf) != TYPE_DICTIONARY:
		printerr("FAIL: expected reloaded codeFiles to be Dictionary, got type ", typeof(cache_cf))
		quit(1)
		return
	var cache_cf_dict: Dictionary = cache_cf
	if cache_cf_dict.get("res://scripts/legacy.gd", "") != "extends Node\n" or cache_cf_dict.get("res://scripts/smoke_fighter.gd", "") != orig_fighter_disk:
		cleanup_ok = false
	if not cleanup_ok:
		printerr("FAIL: _update_cached_code_files / load_cached_epic lost migrated or synced script entry")
		quit(1)
		return

	var broken_bundle := {
		"mode": "direct_agent",
		"summary": "Broken compile probe",
		"scriptUpdates": [
			{"resPath": "res://scripts/smoke_fighter.gd", "content": "extends CharacterBody3D\nfunc broken(:\n"},
		],
		"sceneOps": [],
	}
	Engine.print_error_messages = false
	var broken_res: Dictionary = exec.call("apply_agent_bundle", null, null, broken_bundle, "res://scenes/smoke_fighter.tscn")
	Engine.print_error_messages = true
	var compile_errs: PackedStringArray = broken_res.get("compile_errors", PackedStringArray())
	var failed_updates: Dictionary = broken_res.get("failed_script_updates", {}) if typeof(broken_res.get("failed_script_updates", null)) == TYPE_DICTIONARY else {}
	if compile_errs.size() != 1 or not failed_updates.has("res://scripts/smoke_fighter.gd"):
		printerr("FAIL: expected compile_errors.size()==1 and failed_script_updates to contain smoke_fighter.gd")
		quit(1)
		return
	if FileAccess.get_file_as_string("res://scripts/smoke_fighter.gd") != orig_fighter_disk:
		printerr("FAIL: broken scriptUpdate should not overwrite orig_fighter_disk")
		quit(1)
		return

	var ctx_md: String = exec.call(
		"format_feature_context_markdown",
		{"id": "f1", "title": "Smoke Jump", "doneWhen": "Press Space -> Player jumps"},
		{"res://scripts/smoke_fighter.gd": orig_fighter_disk},
		{"scenes": {"res://scenes/smoke_fighter.tscn": {"isOpenInEditor": true, "nodes": [{"path": ".", "type": "CharacterBody3D", "script": "res://scripts/smoke_fighter.gd"}]}}},
		{"jump": ["Space"]},
		["SCRIPT ERROR: sample"],
		["[3D BASIS FLIP] sample"]
	)
	for needle in ["## LAYERS Godot Context", "smoke_fighter.tscn", "jump", "SCRIPT ERROR: sample", "[3D BASIS FLIP] sample"]:
		if not ctx_md.contains(needle):
			printerr("FAIL: format_feature_context_markdown missing expected substring")
			quit(1)
			return

	print("GODOT_SMOKE_OK")
	quit(0)
