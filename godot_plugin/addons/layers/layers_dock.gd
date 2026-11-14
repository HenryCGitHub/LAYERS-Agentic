@tool
extends VBoxContainer

const LayersSyncClientScript = preload("res://addons/layers/layers_sync_client.gd")
const DEFAULT_WEB_STUDIO_URL := "https://henrycgithub.github.io/LAYERS-Agentic/"

var editor_interface: EditorInterface

var _sync: Node
var _payload: Dictionary = {}
var _selected_feature_id: String = ""
var _show_token_editor: bool = false

# Unlinked / Connect view nodes
var _connect_panel: VBoxContainer
var _token_input: LineEdit
var _connect_btn: Button
var _cancel_token_btn: Button
var _disconnect_btn: Button

# Connected single-Epic steps-only view nodes
var _workspace_panel: VBoxContainer
var _meta_label: Label
var _epic_label: Label
var _feature_picker: OptionButton
var _steps_container: VBoxContainer
var _complete_card: VBoxContainer
var _status_label: Label
var _sync_btn: Button


func _ready() -> void:
	name = "LAYERS"
	custom_minimum_size = Vector2(250, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	_sync = LayersSyncClientScript.new()
	add_child(_sync)
	_sync.epic_updated.connect(_on_epic_updated)
	_sync.sync_failed.connect(_on_sync_failed)
	_sync.busy_changed.connect(_on_busy_changed)

	_build_ui()

	if _sync.has_link_token():
		var cached: Dictionary = _sync.load_cached_epic()
		if not cached.is_empty():
			_payload = cached
		_refresh_view()
		_sync.fetch_active_epic()
	else:
		_show_token_editor = true
		_refresh_view()


func refresh_from_focus() -> void:
	if _sync != null and _sync.has_link_token() and not _show_token_editor:
		_sync.fetch_active_epic()


func _build_ui() -> void:
	# --- Connect / Link Token Panel ---
	_connect_panel = VBoxContainer.new()
	_connect_panel.add_theme_constant_override("separation", 8)
	add_child(_connect_panel)

	var conn_title := Label.new()
	conn_title.text = "LAYERS · Godot Sync"
	conn_title.add_theme_font_size_override("font_size", 14)
	_connect_panel.add_child(conn_title)

	var conn_hint := Label.new()
	conn_hint.text = "Paste your Project Link Token from LAYERS Web Studio (Connect Godot):"
	conn_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conn_hint.modulate = Color(0.75, 0.80, 0.88)
	_connect_panel.add_child(conn_hint)

	_token_input = LineEdit.new()
	_token_input.placeholder_text = "lyr_..."
	_token_input.secret = true
	_token_input.text_submitted.connect(_on_connect_submitted)
	_connect_panel.add_child(_token_input)

	var conn_btn_row := HBoxContainer.new()
	conn_btn_row.add_theme_constant_override("separation", 6)
	_connect_panel.add_child(conn_btn_row)

	_connect_btn = Button.new()
	_connect_btn.text = "Connect Project"
	_connect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_connect_btn.pressed.connect(_on_connect_pressed)
	conn_btn_row.add_child(_connect_btn)

	_cancel_token_btn = Button.new()
	_cancel_token_btn.text = "Cancel"
	_cancel_token_btn.pressed.connect(_on_cancel_token_pressed)
	conn_btn_row.add_child(_cancel_token_btn)

	_disconnect_btn = Button.new()
	_disconnect_btn.text = "Disconnect Token"
	_disconnect_btn.flat = true
	_disconnect_btn.modulate = Color(0.95, 0.55, 0.55)
	_disconnect_btn.pressed.connect(_on_disconnect_pressed)
	_connect_panel.add_child(_disconnect_btn)

	var open_web_unlinked := Button.new()
	open_web_unlinked.text = "↗ Open LAYERS Web Studio"
	open_web_unlinked.flat = true
	open_web_unlinked.pressed.connect(_on_open_web_pressed)
	_connect_panel.add_child(open_web_unlinked)

	# --- Connected Single-Epic Steps-Only Workspace ---
	_workspace_panel = VBoxContainer.new()
	_workspace_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_panel.add_theme_constant_override("separation", 6)
	add_child(_workspace_panel)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 4)
	_workspace_panel.add_child(top_bar)

	_meta_label = Label.new()
	_meta_label.text = "v0.1 · Epic 1/1"
	_meta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meta_label.add_theme_font_size_override("font_size", 11)
	_meta_label.modulate = Color(0.50, 0.82, 0.98)
	top_bar.add_child(_meta_label)

	_sync_btn = Button.new()
	_sync_btn.text = "↻"
	_sync_btn.tooltip_text = "Sync active Epic from Web Studio"
	_sync_btn.flat = true
	_sync_btn.pressed.connect(_on_sync_pressed)
	top_bar.add_child(_sync_btn)

	var web_btn := Button.new()
	web_btn.text = "↗"
	web_btn.tooltip_text = "Open Full Specs, Code Snippets & Planning in Web Studio"
	web_btn.flat = true
	web_btn.pressed.connect(_on_open_web_pressed)
	top_bar.add_child(web_btn)

	var settings_btn := Button.new()
	settings_btn.text = "⚙"
	settings_btn.tooltip_text = "Change or Disconnect Project Link Token"
	settings_btn.flat = true
	settings_btn.pressed.connect(_on_settings_pressed)
	top_bar.add_child(settings_btn)

	_epic_label = Label.new()
	_epic_label.text = "Connecting..."
	_epic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_epic_label.add_theme_font_size_override("font_size", 14)
	_workspace_panel.add_child(_epic_label)

	_feature_picker = OptionButton.new()
	_feature_picker.clip_text = true
	_feature_picker.item_selected.connect(_on_feature_selected)
	_workspace_panel.add_child(_feature_picker)

	_workspace_panel.add_child(HSeparator.new())

	_complete_card = VBoxContainer.new()
	_complete_card.visible = false
	_complete_card.add_theme_constant_override("separation", 8)
	_workspace_panel.add_child(_complete_card)

	var done_title := Label.new()
	done_title.text = "All Epics Complete ✓"
	done_title.add_theme_font_size_override("font_size", 13)
	done_title.modulate = Color(0.25, 0.85, 0.55)
	_complete_card.add_child(done_title)

	var done_hint := Label.new()
	done_hint.text = "Open LAYERS Web Studio to generate the next Release."
	done_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_complete_card.add_child(done_hint)

	var done_web_btn := Button.new()
	done_web_btn.text = "↗ Open Web Studio"
	done_web_btn.pressed.connect(_on_open_web_pressed)
	_complete_card.add_child(done_web_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_workspace_panel.add_child(scroll)

	_steps_container = VBoxContainer.new()
	_steps_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steps_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_steps_container)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.clip_text = true
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.modulate = Color(0.65, 0.72, 0.82)
	add_child(_status_label)


func _refresh_view() -> void:
	var linked: bool = _sync != null and _sync.has_link_token()
	_connect_panel.visible = (not linked) or _show_token_editor
	_workspace_panel.visible = linked and (not _show_token_editor)
	_cancel_token_btn.visible = linked
	_disconnect_btn.visible = linked

	if _connect_panel.visible:
		_token_input.text = _sync.get_link_token() if linked else ""
		return

	if _payload.is_empty():
		_meta_label.text = "LAYERS"
		_epic_label.text = "Loading active Epic..."
		_feature_picker.visible = false
		_complete_card.visible = false
		_clear_steps()
		return

	var ver := str(_payload.get("releaseVersion", "v0.1"))
	var pos := int(_payload.get("epicPosition", 0))
	var total := int(_payload.get("totalEpics", 0))
	var all_done := bool(_payload.get("allEpicsCompleted", false))
	_meta_label.text = "%s · Epic %d/%d" % [ver, pos, max(total, 1)]

	if all_done:
		_epic_label.text = str(_payload.get("releaseTitle", ver))
		_feature_picker.visible = false
		_complete_card.visible = true
		_clear_steps()
		return

	_complete_card.visible = false
	var epic_raw = _payload.get("activeEpic", null)
	if typeof(epic_raw) != TYPE_DICTIONARY or epic_raw.is_empty():
		_epic_label.text = "No active Epic yet — plan in Web Studio."
		_feature_picker.visible = false
		_clear_steps()
		return

	var epic: Dictionary = epic_raw
	_epic_label.text = "%s · %s" % [str(epic.get("code", "E01")), str(epic.get("title", "Epic"))]

	var features: Array = epic.get("features", [])
	_feature_picker.clear()
	_feature_picker.visible = features.size() > 0

	if features.is_empty():
		_clear_steps()
		var empty_lbl := Label.new()
		empty_lbl.text = "No features in this Epic yet."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_steps_container.add_child(empty_lbl)
		return

	var chosen_idx: int = -1
	var first_incomplete_idx: int = -1
	for i in range(features.size()):
		var f: Dictionary = features[i]
		var f_id := str(f.get("id", ""))
		var f_title := str(f.get("title", "Feature"))
		var f_steps: Array = f.get("steps", [])
		var done_cnt := 0
		for st in f_steps:
			if typeof(st) == TYPE_DICTIONARY and bool(st.get("completed", false)):
				done_cnt += 1
		var f_done := bool(f.get("isCompleted", false))
		var prefix := "✓" if f_done else "•"
		_feature_picker.add_item("%s %s (%d/%d)" % [prefix, f_title, done_cnt, f_steps.size()], i)
		if f_id == _selected_feature_id:
			chosen_idx = i
		if first_incomplete_idx == -1 and not f_done:
			first_incomplete_idx = i

	if chosen_idx == -1:
		chosen_idx = first_incomplete_idx if first_incomplete_idx != -1 else 0
	_feature_picker.select(chosen_idx)
	var active_feat: Dictionary = features[chosen_idx]
	_selected_feature_id = str(active_feat.get("id", ""))
	_render_feature_steps(active_feat)


func _clear_steps() -> void:
	for child in _steps_container.get_children():
		_steps_container.remove_child(child)
		child.queue_free()


func _render_feature_steps(feat: Dictionary) -> void:
	_clear_steps()
	var feat_id := str(feat.get("id", ""))
	var cp_id := str(feat.get("checkpointId", ""))
	var steps: Array = feat.get("steps", [])

	for s_raw in steps:
		if typeof(s_raw) != TYPE_DICTIONARY:
			continue
		var st: Dictionary = s_raw
		var step_id := str(st.get("id", ""))
		var idx_num := int(st.get("index", 1))
		var role := str(st.get("role", "CODE"))
		var title := str(st.get("title", "Step"))
		var step_path := str(st.get("stepPath", ""))
		var is_done := bool(st.get("completed", false))

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 4)
		_steps_container.add_child(row)

		var cb := CheckBox.new()
		cb.text = "%02d · %s · %s" % [idx_num, role, title]
		cb.button_pressed = is_done
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_done:
			cb.modulate = Color(0.55, 0.78, 0.65)
		cb.toggled.connect(
			func(pressed: bool) -> void:
				_status_label.text = "Syncing..."
				_sync.toggle_step(feat_id, cp_id, step_id, pressed)
		)
		row.add_child(cb)

		if step_path.begins_with("res://") and FileAccess.file_exists(step_path):
			var open_btn := Button.new()
			open_btn.text = "📂"
			open_btn.tooltip_text = "Open %s in Godot" % step_path
			open_btn.flat = true
			open_btn.pressed.connect(
				func() -> void:
					_open_res_path(step_path)
			)
			row.add_child(open_btn)

	_steps_container.add_child(HSeparator.new())

	# Final compact Playtest Gate row + F6 run trigger
	var gate_row := HBoxContainer.new()
	gate_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gate_row.add_theme_constant_override("separation", 4)
	_steps_container.add_child(gate_row)

	var gate_passed := bool(feat.get("isPlaytestPassed", false))
	var gate_cb := CheckBox.new()
	gate_cb.text = "▶ Playtest Passed"
	gate_cb.button_pressed = gate_passed
	gate_cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if gate_passed:
		gate_cb.modulate = Color(0.30, 0.90, 0.58)
	gate_cb.toggled.connect(
		func(pressed: bool) -> void:
			_status_label.text = "Syncing Playtest Gate..."
			_sync.set_playtest_passed(feat_id, cp_id, pressed)
	)
	gate_row.add_child(gate_cb)

	var run_btn := Button.new()
	run_btn.text = "▶ F6"
	run_btn.tooltip_text = "Play Current Scene (F6)"
	run_btn.pressed.connect(_on_run_scene_pressed)
	gate_row.add_child(run_btn)


func _open_res_path(res_path: String) -> void:
	if editor_interface == null:
		return
	if res_path.ends_with(".tscn") or res_path.ends_with(".scn"):
		editor_interface.open_scene_from_path(res_path)
		return
	var res := ResourceLoader.load(res_path)
	if res is Script:
		editor_interface.edit_script(res)
	elif res != null:
		editor_interface.edit_resource(res)


func _on_run_scene_pressed() -> void:
	if editor_interface != null:
		editor_interface.play_current_scene()


func _on_feature_selected(idx: int) -> void:
	var epic_raw = _payload.get("activeEpic", null)
	if typeof(epic_raw) != TYPE_DICTIONARY:
		return
	var features: Array = epic_raw.get("features", [])
	if idx >= 0 and idx < features.size():
		var f: Dictionary = features[idx]
		_selected_feature_id = str(f.get("id", ""))
		_render_feature_steps(f)


func _on_epic_updated(payload: Dictionary) -> void:
	_payload = payload
	_status_label.text = "Synced"
	_status_label.modulate = Color(0.45, 0.85, 0.65)
	_refresh_view()


func _on_sync_failed(message: String) -> void:
	_status_label.text = message
	_status_label.modulate = Color(0.95, 0.45, 0.45)


func _on_busy_changed(is_busy: bool) -> void:
	if _sync_btn != null:
		_sync_btn.disabled = is_busy
	if is_busy and _status_label != null:
		_status_label.text = "Syncing..."
		_status_label.modulate = Color(0.55, 0.78, 0.98)


func _on_connect_submitted(_text: String) -> void:
	_on_connect_pressed()


func _on_connect_pressed() -> void:
	var token := _token_input.text.strip_edges()
	if not token.begins_with("lyr_") or token.length() < 20:
		_status_label.text = "Enter a valid lyr_... Link Token."
		_status_label.modulate = Color(0.95, 0.45, 0.45)
		return
	_sync.save_link_token(token)
	_show_token_editor = false
	_payload = {}
	_selected_feature_id = ""
	_refresh_view()
	_sync.fetch_active_epic()


func _on_cancel_token_pressed() -> void:
	_show_token_editor = false
	_refresh_view()


func _on_disconnect_pressed() -> void:
	_sync.clear_link_token()
	_payload = {}
	_selected_feature_id = ""
	_show_token_editor = true
	_status_label.text = "Disconnected"
	_status_label.modulate = Color(0.65, 0.72, 0.82)
	_refresh_view()


func _on_sync_pressed() -> void:
	_sync.fetch_active_epic()


func _on_open_web_pressed() -> void:
	var url := str(_payload.get("webStudioUrl", DEFAULT_WEB_STUDIO_URL)).strip_edges()
	if url.is_empty():
		url = DEFAULT_WEB_STUDIO_URL
	OS.shell_open(url)


func _on_settings_pressed() -> void:
	_show_token_editor = true
	_refresh_view()
