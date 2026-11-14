@tool
extends EditorPlugin

const DOCK_SCRIPT_PATH := "res://addons/layers/layers_dock.gd"

var _dock: Control
var _last_focus_sync_msec: int = 0


func _enter_tree() -> void:
	var dock_script: Script = ResourceLoader.load(
		DOCK_SCRIPT_PATH,
		"Script",
		ResourceLoader.CACHE_MODE_REPLACE
	) as Script
	if dock_script == null:
		dock_script = load(DOCK_SCRIPT_PATH) as Script
	if dock_script == null:
		push_error("LAYERS: Failed to load %s" % DOCK_SCRIPT_PATH)
		return
	_dock = dock_script.new()
	_dock.editor_interface = get_editor_interface()
	_dock.undo_redo = get_undo_redo()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

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
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _on_editor_scene_changed(_scene_root: Node) -> void:
	if _dock != null and _dock.has_method("notify_editor_state_changed"):
		_dock.call("notify_editor_state_changed")


func _on_editor_scene_saved(_filepath: String) -> void:
	if _dock != null and _dock.has_method("notify_editor_state_changed"):
		_dock.call("notify_editor_state_changed")


func _on_editor_resource_saved(_resource: Resource) -> void:
	if _dock != null and _dock.has_method("notify_editor_state_changed"):
		_dock.call("notify_editor_state_changed")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _dock != null:
		var now_msec := Time.get_ticks_msec()
		if now_msec - _last_focus_sync_msec >= 5000:
			_last_focus_sync_msec = now_msec
			_dock.refresh_from_focus()
