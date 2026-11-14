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

	print("GODOT_SMOKE_OK")
	quit(0)
