@tool
extends EditorPlugin

const DOCK_SCRIPT_PATH := "res://addons/layers/layers_dock.gd"

var _dock: Control
var _dock_added: bool = false
var _last_focus_sync_msec: int = 0


static func load_fresh_script(res_path: String) -> Script:
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
	var standalone := GDScript.new()
	standalone.source_code = disk_code
	if standalone.reload(true) == OK:
		return standalone
	return null


func _enter_tree() -> void:
	_dock_added = false
	var dock_script: Script = load_fresh_script(DOCK_SCRIPT_PATH)
	if dock_script == null:
		push_error("LAYERS: Failed to load %s" % DOCK_SCRIPT_PATH)
		return
	var inst_v: Variant = dock_script.new()
	if not (inst_v is Control):
		if inst_v is Object:
			(inst_v as Object).free()
		push_error("LAYERS: %s did not instantiate a Control." % DOCK_SCRIPT_PATH)
		return
	_dock = inst_v as Control
	if "editor_interface" in _dock:
		_dock.set("editor_interface", get_editor_interface())
	if "undo_redo" in _dock:
		_dock.set("undo_redo", get_undo_redo())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_dock_added = true

	if not scene_changed.is_connected(_on_editor_scene_changed):
		scene_changed.connect(_on_editor_scene_changed)
	if not scene_saved.is_connected(_on_editor_scene_saved):
		scene_saved.connect(_on_editor_scene_saved)
	if not resource_saved.is_connected(_on_editor_resource_saved):
		resource_saved.connect(_on_editor_resource_saved)


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_editor_scene_changed):
		scene_changed.disconnect(_on_editor_scene_changed)
	if scene_saved.is_connected(_on_editor_scene_saved):
		scene_saved.disconnect(_on_editor_scene_saved)
	if resource_saved.is_connected(_on_editor_resource_saved):
		resource_saved.disconnect(_on_editor_resource_saved)
	if _dock != null:
		if _dock_added:
			remove_control_from_docks(_dock)
		_dock_added = false
		_dock.queue_free()
		_dock = null


func _on_editor_scene_changed(scene_root: Node) -> void:
	if _dock == null:
		return
	if _dock.has_method("on_editor_scene_changed"):
		_dock.call("on_editor_scene_changed", scene_root)
	elif _dock.has_method("notify_editor_state_changed"):
		_dock.call("notify_editor_state_changed")


func _on_editor_scene_saved(filepath: String) -> void:
	if _dock == null:
		return
	if _dock.has_method("on_editor_scene_saved"):
		_dock.call("on_editor_scene_saved", filepath)
	elif _dock.has_method("notify_editor_state_changed"):
		_dock.call("notify_editor_state_changed")


func _on_editor_resource_saved(resource: Resource) -> void:
	if _dock == null:
		return
	if _dock.has_method("on_editor_resource_saved"):
		_dock.call("on_editor_resource_saved", resource)
	elif _dock.has_method("notify_editor_state_changed"):
		_dock.call("notify_editor_state_changed")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _dock != null:
		var now_msec := Time.get_ticks_msec()
		if now_msec - _last_focus_sync_msec >= 5000:
			_last_focus_sync_msec = now_msec
			if _dock.has_method("refresh_from_focus"):
				_dock.call("refresh_from_focus")
