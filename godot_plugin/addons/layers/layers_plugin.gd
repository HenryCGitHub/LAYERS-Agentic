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


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _dock != null:
		var now_msec := Time.get_ticks_msec()
		if now_msec - _last_focus_sync_msec >= 5000:
			_last_focus_sync_msec = now_msec
			_dock.refresh_from_focus()
