@tool
extends VBoxContainer

const SYNC_CLIENT_SCRIPT_PATH := "res://addons/layers/layers_sync_client.gd"
const STEP_EXECUTOR_SCRIPT_PATH := "res://addons/layers/layers_step_executor.gd"
const DEFAULT_WEB_STUDIO_URL := "https://henrycgithub.github.io/LAYERS-Agentic/"

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager

var _sync: Node
var _executor: RefCounted
var _payload: Dictionary = {}
var _selected_feature_id: String = ""
var _selected_step_idx: int = 0
var _show_code_preview: bool = false
var _fix_drawer_open: bool = false
var _diagnosing_fix: bool = false
var _fix_draft_text: String = ""
var _show_token_editor: bool = false
var _available_remote_version: String = ""
var _updating_plugin: bool = false
var _checking_plugin_update: bool = false
var _live_refresh_timer: Timer

# Slim Top Self-Update Banner
var _update_banner: PanelContainer
var _update_banner_icon: TextureRect
var _update_banner_lbl: Label
var _update_now_btn: Button

# Unlinked / Settings View
var _connect_panel: VBoxContainer
var _token_input: LineEdit
var _connect_btn: Button
var _cancel_token_btn: Button
var _disconnect_btn: Button
var _version_label: Label
var _check_update_btn: Button

# Connected Native Dock Workspace
var _workspace_panel: VBoxContainer
var _meta_label: Label
var _epic_label: Label
var _sync_btn: Button
var _web_btn: Button
var _settings_btn: Button
var _feature_picker: OptionButton
var _step_nav_row: HBoxContainer
var _prev_step_btn: Button
var _step_picker: OptionButton
var _next_step_btn: Button
var _complete_card: VBoxContainer
var _step_scroll: ScrollContainer
var _body_container: VBoxContainer
var _footer_box: VBoxContainer
var _primary_cta_btn: Button
var _status_label: Label

# Dynamic Controls Bound Per Render
var _fix_input: LineEdit
var _check_tree: Tree
var _tree_row_lookup: Dictionary = {}
var _current_step_path: String = ""


func _ready() -> void:
	name = "LAYERS"
	custom_minimum_size = Vector2(float(_S(260)), 0.0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", _S(6))

	var sync_script: Script = ResourceLoader.load(
		SYNC_CLIENT_SCRIPT_PATH,
		"Script",
		ResourceLoader.CACHE_MODE_REPLACE
	) as Script
	if sync_script == null:
		sync_script = load(SYNC_CLIENT_SCRIPT_PATH) as Script
	if sync_script != null:
		_sync = sync_script.new()
	if _sync != null:
		add_child(_sync)
		_sync.epic_updated.connect(_on_epic_updated)
		_sync.sync_failed.connect(_on_sync_failed)
		_sync.busy_changed.connect(_on_busy_changed)
		_sync.update_available.connect(_on_plugin_update_available)
		_sync.update_check_finished.connect(_on_plugin_update_check_finished)
		_sync.update_ready_to_reload.connect(_on_plugin_update_ready_to_reload)
		_sync.update_failed.connect(_on_plugin_update_failed)

	var exec_script: Script = ResourceLoader.load(
		STEP_EXECUTOR_SCRIPT_PATH,
		"Script",
		ResourceLoader.CACHE_MODE_REPLACE
	) as Script
	if exec_script == null:
		exec_script = load(STEP_EXECUTOR_SCRIPT_PATH) as Script
	if exec_script != null:
		_executor = exec_script.new()

	_live_refresh_timer = Timer.new()
	_live_refresh_timer.one_shot = true
	_live_refresh_timer.wait_time = 0.28
	_live_refresh_timer.timeout.connect(_on_live_refresh_timeout)
	add_child(_live_refresh_timer)

	_connect_live_tree_signals()
	_build_ui()

	if _sync == null:
		_show_token_editor = true
		_refresh_view()
		_set_status("Failed to load layers_sync_client.gd — check Output panel.", true)
		return

	if _sync.has_link_token():
		var cached: Dictionary = _sync.load_cached_epic()
		if not cached.is_empty():
			_payload = cached
		_refresh_view()
		_sync.fetch_active_epic()
	else:
		_show_token_editor = true
		_refresh_view()

	_sync.check_for_plugin_update(true)


func _exit_tree() -> void:
	_disconnect_live_tree_signals()


func refresh_from_focus() -> void:
	if _sync != null and _sync.has_link_token() and not _show_token_editor:
		_sync.fetch_active_epic()
	notify_editor_state_changed()


func notify_editor_state_changed() -> void:
	if not is_inside_tree() or _live_refresh_timer == null:
		return
	if _show_token_editor or not _workspace_panel.visible:
		return
	_live_refresh_timer.start()


func _connect_live_tree_signals() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if not tree.node_added.is_connected(_on_tree_mutated):
		tree.node_added.connect(_on_tree_mutated)
	if not tree.node_removed.is_connected(_on_tree_mutated):
		tree.node_removed.connect(_on_tree_mutated)
	if not tree.node_renamed.is_connected(_on_tree_mutated):
		tree.node_renamed.connect(_on_tree_mutated)


func _disconnect_live_tree_signals() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if tree.node_added.is_connected(_on_tree_mutated):
		tree.node_added.disconnect(_on_tree_mutated)
	if tree.node_removed.is_connected(_on_tree_mutated):
		tree.node_removed.disconnect(_on_tree_mutated)
	if tree.node_renamed.is_connected(_on_tree_mutated):
		tree.node_renamed.disconnect(_on_tree_mutated)


func _on_tree_mutated(node: Node) -> void:
	if editor_interface == null or node == null:
		return
	var edited_root: Node = editor_interface.get_edited_scene_root()
	if edited_root == null:
		return
	if node == edited_root or edited_root.is_ancestor_of(node):
		notify_editor_state_changed()


func _on_live_refresh_timeout() -> void:
	if _show_token_editor or not _workspace_panel.visible:
		return
	if _fix_input != null and _fix_input.has_focus():
		return
	var feat: Dictionary = _get_active_feature()
	if feat.is_empty():
		return
	var prev_scroll: int = _step_scroll.scroll_vertical if _step_scroll != null else 0
	_render_active_step_workspace(feat)
	if _step_scroll != null:
		_step_scroll.set_deferred("scroll_vertical", prev_scroll)


# ---------------------------------------------------------------------------
# UI Construction (100% Native Godot 4 EditorTheme Controls)
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# 1. Slim Native Update Banner (hidden until remote GitHub version > local)
	_update_banner = PanelContainer.new()
	_update_banner.visible = false
	var banner_sb: StyleBox = _editor_stylebox("panel", "Tree")
	if banner_sb != null:
		_update_banner.add_theme_stylebox_override("panel", banner_sb)
	add_child(_update_banner)

	var banner_hb := HBoxContainer.new()
	banner_hb.add_theme_constant_override("separation", _S(6))
	_update_banner.add_child(banner_hb)

	_update_banner_icon = TextureRect.new()
	_update_banner_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_update_banner_icon.texture = _editor_icon("ArrowUp", "Reload")
	banner_hb.add_child(_update_banner_icon)

	_update_banner_lbl = Label.new()
	_update_banner_lbl.text = "Plugin update available"
	_update_banner_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_banner_lbl.clip_text = true
	_update_banner_lbl.add_theme_color_override("font_color", _editor_color("accent_color", Color(0.45, 0.78, 0.98)))
	banner_hb.add_child(_update_banner_lbl)

	_update_now_btn = Button.new()
	_update_now_btn.text = "Update Now"
	_update_now_btn.pressed.connect(_on_update_now_pressed)
	banner_hb.add_child(_update_now_btn)

	# 2. Connect / Plugin Settings Panel
	_connect_panel = VBoxContainer.new()
	_connect_panel.add_theme_constant_override("separation", _S(8))
	add_child(_connect_panel)

	var conn_title := Label.new()
	conn_title.text = "LAYERS · Godot Sync"
	var bold_font: Font = _editor_font("bold")
	if bold_font != null:
		conn_title.add_theme_font_override("font", bold_font)
	_connect_panel.add_child(conn_title)

	var conn_hint := Label.new()
	conn_hint.text = "Paste your Project Link Token from LAYERS Web Studio (Connect Godot):"
	conn_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conn_hint.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.70, 0.74, 0.80)))
	_connect_panel.add_child(conn_hint)

	_token_input = LineEdit.new()
	_token_input.placeholder_text = "lyr_..."
	_token_input.secret = true
	_token_input.text_submitted.connect(_on_connect_submitted)
	_connect_panel.add_child(_token_input)

	var conn_btn_row := HBoxContainer.new()
	conn_btn_row.add_theme_constant_override("separation", _S(6))
	_connect_panel.add_child(conn_btn_row)

	_connect_btn = Button.new()
	_connect_btn.text = "Connect Project"
	_connect_btn.icon = _editor_icon("StatusSuccess")
	_connect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_connect_btn.pressed.connect(_on_connect_pressed)
	conn_btn_row.add_child(_connect_btn)

	_cancel_token_btn = Button.new()
	_cancel_token_btn.text = "Cancel"
	_cancel_token_btn.pressed.connect(_on_cancel_token_pressed)
	conn_btn_row.add_child(_cancel_token_btn)

	_disconnect_btn = Button.new()
	_disconnect_btn.text = "Disconnect Token"
	_disconnect_btn.icon = _editor_icon("Remove", "Close")
	_disconnect_btn.flat = true
	_disconnect_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_disconnect_btn.add_theme_color_override("font_color", _editor_color("error_color", Color(0.95, 0.48, 0.48)))
	_disconnect_btn.pressed.connect(_on_disconnect_pressed)
	_connect_panel.add_child(_disconnect_btn)

	var open_web_unlinked := Button.new()
	open_web_unlinked.text = "Open LAYERS Web Studio"
	open_web_unlinked.icon = _editor_icon("ExternalLink")
	open_web_unlinked.flat = true
	open_web_unlinked.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open_web_unlinked.pressed.connect(_on_open_web_pressed)
	_connect_panel.add_child(open_web_unlinked)

	_connect_panel.add_child(HSeparator.new())

	var ver_row := HBoxContainer.new()
	ver_row.add_theme_constant_override("separation", _S(6))
	_connect_panel.add_child(ver_row)

	_version_label = Label.new()
	_version_label.text = "Plugin v%s" % (_sync.get_local_plugin_version() if _sync != null else "2.3.0")
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_label.clip_text = true
	_version_label.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.68, 0.72, 0.78)))
	ver_row.add_child(_version_label)

	_check_update_btn = Button.new()
	_check_update_btn.text = "Check for Plugin Update"
	_check_update_btn.icon = _editor_icon("Reload")
	_check_update_btn.pressed.connect(_on_check_plugin_update_pressed)
	ver_row.add_child(_check_update_btn)

	# 3. Connected Native Workspace
	_workspace_panel = VBoxContainer.new()
	_workspace_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_panel.add_theme_constant_override("separation", _S(6))
	add_child(_workspace_panel)

	# Top Toolbar
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", _S(4))
	_workspace_panel.add_child(top_bar)

	var header_vb := VBoxContainer.new()
	header_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_vb.add_theme_constant_override("separation", _S(1))
	top_bar.add_child(header_vb)

	_meta_label = Label.new()
	_meta_label.text = "v0.1 · Epic 1/1"
	_meta_label.clip_text = true
	_meta_label.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.66, 0.70, 0.76)))
	header_vb.add_child(_meta_label)

	_epic_label = Label.new()
	_epic_label.text = "Connecting..."
	_epic_label.clip_text = true
	if bold_font != null:
		_epic_label.add_theme_font_override("font", bold_font)
	header_vb.add_child(_epic_label)

	_sync_btn = Button.new()
	_sync_btn.flat = true
	_sync_btn.theme_type_variation = &"FlatButton"
	_sync_btn.icon = _editor_icon("Reload")
	if _sync_btn.icon == null:
		_sync_btn.text = "Sync"
	_sync_btn.tooltip_text = "Sync active Epic from Web Studio"
	_sync_btn.pressed.connect(_on_sync_pressed)
	top_bar.add_child(_sync_btn)

	_web_btn = Button.new()
	_web_btn.flat = true
	_web_btn.theme_type_variation = &"FlatButton"
	_web_btn.icon = _editor_icon("ExternalLink")
	if _web_btn.icon == null:
		_web_btn.text = "Web"
	_web_btn.tooltip_text = "Open Full Specs & Planning in Web Studio"
	_web_btn.pressed.connect(_on_open_web_pressed)
	top_bar.add_child(_web_btn)

	_settings_btn = Button.new()
	_settings_btn.flat = true
	_settings_btn.theme_type_variation = &"FlatButton"
	_settings_btn.icon = _editor_icon("Tools")
	if _settings_btn.icon == null:
		_settings_btn.text = "Settings"
	_settings_btn.tooltip_text = "Plugin Settings, Link Token & Check for Updates"
	_settings_btn.pressed.connect(_on_settings_pressed)
	top_bar.add_child(_settings_btn)

	# Feature Selector
	_feature_picker = OptionButton.new()
	_feature_picker.clip_text = true
	_feature_picker.item_selected.connect(_on_feature_selected)
	_workspace_panel.add_child(_feature_picker)

	# Step Selector Row: [Back] [1/7 · Create Coastal Arena Scene v] [Forward]
	_step_nav_row = HBoxContainer.new()
	_step_nav_row.add_theme_constant_override("separation", _S(4))
	_workspace_panel.add_child(_step_nav_row)

	_prev_step_btn = Button.new()
	_prev_step_btn.icon = _editor_icon("Back")
	if _prev_step_btn.icon == null:
		_prev_step_btn.text = "<"
	_prev_step_btn.tooltip_text = "Previous step"
	_prev_step_btn.custom_minimum_size = Vector2(float(_S(28)), 0.0)
	_prev_step_btn.pressed.connect(_on_prev_step_pressed)
	_step_nav_row.add_child(_prev_step_btn)

	_step_picker = OptionButton.new()
	_step_picker.clip_text = true
	_step_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_picker.item_selected.connect(_on_step_selected)
	_step_nav_row.add_child(_step_picker)

	_next_step_btn = Button.new()
	_next_step_btn.icon = _editor_icon("Forward")
	if _next_step_btn.icon == null:
		_next_step_btn.text = ">"
	_next_step_btn.tooltip_text = "Next step"
	_next_step_btn.custom_minimum_size = Vector2(float(_S(28)), 0.0)
	_next_step_btn.pressed.connect(_on_next_step_pressed)
	_step_nav_row.add_child(_next_step_btn)

	_workspace_panel.add_child(HSeparator.new())

	# All Epics Complete State
	_complete_card = VBoxContainer.new()
	_complete_card.visible = false
	_complete_card.add_theme_constant_override("separation", _S(8))
	_workspace_panel.add_child(_complete_card)

	var done_title := Label.new()
	done_title.text = "All Epics Complete"
	if bold_font != null:
		done_title.add_theme_font_override("font", bold_font)
	done_title.add_theme_color_override("font_color", _editor_color("success_color", Color(0.36, 0.85, 0.56)))
	_complete_card.add_child(done_title)

	var done_hint := Label.new()
	done_hint.text = "Open LAYERS Web Studio to generate the next Release."
	done_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_complete_card.add_child(done_hint)

	var done_web_btn := Button.new()
	done_web_btn.text = "Open Web Studio"
	done_web_btn.icon = _editor_icon("ExternalLink")
	done_web_btn.pressed.connect(_on_open_web_pressed)
	_complete_card.add_child(done_web_btn)

	# Scrollable Active Step Workspace
	_step_scroll = ScrollContainer.new()
	_step_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_workspace_panel.add_child(_step_scroll)

	_body_container = VBoxContainer.new()
	_body_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_container.add_theme_constant_override("separation", _S(6))
	_step_scroll.add_child(_body_container)

	# Footer CTA
	_footer_box = VBoxContainer.new()
	_footer_box.add_theme_constant_override("separation", _S(4))
	_workspace_panel.add_child(_footer_box)
	_footer_box.add_child(HSeparator.new())

	_primary_cta_btn = Button.new()
	_primary_cta_btn.text = "Complete & Next Step"
	_primary_cta_btn.pressed.connect(_on_primary_cta_pressed)
	_footer_box.add_child(_primary_cta_btn)

	_status_label = Label.new()
	_status_label.text = "Ready · Ctrl+Z supported on scene actions"
	_status_label.clip_text = true
	_status_label.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.66, 0.70, 0.76)))
	add_child(_status_label)


func _refresh_update_banner() -> void:
	if _update_banner == null:
		return
	var has_update: bool = not _available_remote_version.is_empty()
	_update_banner.visible = has_update or _updating_plugin
	if _update_banner_lbl != null:
		if _updating_plugin:
			_update_banner_lbl.text = "Downloading v%s..." % _available_remote_version
		elif has_update:
			_update_banner_lbl.text = "Plugin v%s available" % _available_remote_version
	if _update_now_btn != null:
		_update_now_btn.disabled = _updating_plugin
		_update_now_btn.text = "Updating..." if _updating_plugin else "Update Now"


func _refresh_view() -> void:
	var linked: bool = _sync != null and _sync.has_link_token()
	_connect_panel.visible = (not linked) or _show_token_editor
	_workspace_panel.visible = linked and (not _show_token_editor)
	_cancel_token_btn.visible = linked
	_disconnect_btn.visible = linked
	if _version_label != null and _sync != null:
		_version_label.text = "Plugin v%s" % _sync.get_local_plugin_version()
	_refresh_update_banner()

	if _connect_panel.visible:
		_token_input.text = _sync.get_link_token() if linked else ""
		return

	if _payload.is_empty():
		_meta_label.text = "LAYERS"
		_epic_label.text = "Loading active Epic..."
		_feature_picker.visible = false
		_step_nav_row.visible = false
		_complete_card.visible = false
		_footer_box.visible = false
		_clear_body()
		return

	var ver: String = str(_payload.get("releaseVersion", "v0.1"))
	var pos: int = int(_payload.get("epicPosition", 0))
	var total: int = int(_payload.get("totalEpics", 0))
	var all_done: bool = bool(_payload.get("allEpicsCompleted", false))
	var epic_raw: Variant = _payload.get("activeEpic", null)
	var epic_code: String = "E01"
	if typeof(epic_raw) == TYPE_DICTIONARY:
		var epic_dict_tmp: Dictionary = epic_raw
		if epic_dict_tmp.has("code"):
			epic_code = str(epic_dict_tmp.get("code", "E01"))
	_meta_label.text = "%s · Epic %d/%d · %s" % [ver, pos, maxi(total, 1), epic_code]

	if all_done:
		_epic_label.text = str(_payload.get("releaseTitle", ver))
		_feature_picker.visible = false
		_step_nav_row.visible = false
		_complete_card.visible = true
		_footer_box.visible = false
		_clear_body()
		return

	_complete_card.visible = false
	if typeof(epic_raw) != TYPE_DICTIONARY or (epic_raw as Dictionary).is_empty():
		_epic_label.text = "No active Epic yet — plan in Web Studio."
		_feature_picker.visible = false
		_step_nav_row.visible = false
		_footer_box.visible = false
		_clear_body()
		return

	var epic: Dictionary = epic_raw
	_epic_label.text = str(epic.get("title", "Epic"))

	var features: Array = epic.get("features", [])
	_feature_picker.clear()
	_feature_picker.visible = features.size() > 0

	if features.is_empty():
		_step_nav_row.visible = false
		_footer_box.visible = false
		_clear_body()
		var empty_lbl := Label.new()
		empty_lbl.text = "No features in this Epic yet."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body_container.add_child(empty_lbl)
		return

	var chosen_idx: int = -1
	var first_incomplete_idx: int = -1
	for i in range(features.size()):
		var f: Dictionary = features[i]
		var f_id: String = str(f.get("id", ""))
		var f_title: String = str(f.get("title", "Feature"))
		var f_steps: Array = f.get("steps", [])
		var done_cnt: int = 0
		for st in f_steps:
			if typeof(st) == TYPE_DICTIONARY and bool((st as Dictionary).get("completed", false)):
				done_cnt += 1
		var f_done: bool = bool(f.get("isCompleted", false))
		_feature_picker.add_item("%s (%d/%d)" % [f_title, done_cnt, f_steps.size()], i)
		var f_icon: Texture2D = _editor_icon("StatusSuccess" if f_done else "Folder", "Node")
		if f_icon != null:
			_feature_picker.set_item_icon(i, f_icon)
		if f_id == _selected_feature_id:
			chosen_idx = i
		if first_incomplete_idx == -1 and not f_done:
			first_incomplete_idx = i

	if chosen_idx == -1:
		chosen_idx = first_incomplete_idx if first_incomplete_idx != -1 else 0
	_feature_picker.select(chosen_idx)
	var active_feat: Dictionary = features[chosen_idx]
	var next_feat_id: String = str(active_feat.get("id", ""))
	if next_feat_id != _selected_feature_id:
		_selected_feature_id = next_feat_id
		_selected_step_idx = _find_first_incomplete_step_idx(active_feat)
		_show_code_preview = false

	_render_active_step_workspace(active_feat)


func _find_first_incomplete_step_idx(feat: Dictionary) -> int:
	var steps: Array = feat.get("steps", [])
	for i in range(steps.size()):
		if typeof(steps[i]) == TYPE_DICTIONARY and not bool((steps[i] as Dictionary).get("completed", false)):
			return i
	return steps.size()


func _get_active_feature() -> Dictionary:
	var epic_raw: Variant = _payload.get("activeEpic", null)
	if typeof(epic_raw) != TYPE_DICTIONARY:
		return {}
	var epic_d: Dictionary = epic_raw
	var features: Array = epic_d.get("features", [])
	for f_raw in features:
		if typeof(f_raw) == TYPE_DICTIONARY and str((f_raw as Dictionary).get("id", "")) == _selected_feature_id:
			return f_raw
	return features[0] if not features.is_empty() and typeof(features[0]) == TYPE_DICTIONARY else {}


func _clear_body() -> void:
	_fix_input = null
	_check_tree = null
	_tree_row_lookup = {}
	for child in _body_container.get_children():
		_body_container.remove_child(child)
		child.queue_free()


func _render_active_step_workspace(feat: Dictionary) -> void:
	_clear_body()

	var feat_id: String = str(feat.get("id", ""))
	var cp_id: String = str(feat.get("checkpointId", ""))
	var steps: Array = feat.get("steps", [])
	var max_idx: int = steps.size()
	_selected_step_idx = clampi(_selected_step_idx, 0, max_idx)

	# Populate Step Dropdown with Actual Step Titles + Native Role Icons
	_step_nav_row.visible = true
	_step_picker.clear()
	for i in range(steps.size()):
		if typeof(steps[i]) != TYPE_DICTIONARY:
			continue
		var st: Dictionary = steps[i]
		var st_done: bool = bool(st.get("completed", false))
		var st_title: String = str(st.get("title", "Step %d" % (i + 1))).strip_edges()
		_step_picker.add_item("%d/%d · %s" % [i + 1, steps.size(), st_title], i)
		var s_icon: Texture2D = _step_picker_icon(st, st_done)
		if s_icon != null:
			_step_picker.set_item_icon(i, s_icon)

	var gate_passed: bool = bool(feat.get("isPlaytestPassed", false))
	_step_picker.add_item("Playtest Gate", max_idx)
	var gate_icon: Texture2D = _editor_icon("StatusSuccess" if gate_passed else "PlayScene", "Play")
	if gate_icon != null:
		_step_picker.set_item_icon(_step_picker.item_count - 1, gate_icon)
	_step_picker.select(_selected_step_idx)

	_prev_step_btn.disabled = _selected_step_idx <= 0
	_next_step_btn.disabled = _selected_step_idx >= max_idx
	_footer_box.visible = true

	if _selected_step_idx == max_idx:
		_render_playtest_gate(feat, feat_id, cp_id, gate_passed)
		_render_agent_fix_drawer(feat, feat_id, cp_id)
		_primary_cta_btn.text = "Playtest Passed — Next Feature"
		_primary_cta_btn.icon = _editor_icon("StatusSuccess" if gate_passed else "Forward")
		return

	var step: Dictionary = steps[_selected_step_idx]
	var step_id: String = str(step.get("id", ""))
	var role: String = str(step.get("role", "CODE"))
	var live_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
	var step_path: String = _executor.call("resolve_effective_step_path", step, feat, live_root) if _executor != null else str(step.get("stepPath", "res://scenes/main.tscn"))
	_current_step_path = step_path

	var instruction: String = str(step.get("instruction", "")).strip_edges()
	if instruction.is_empty():
		instruction = "Complete `%s` in `%s`." % [str(step.get("title", "Step")), step_path]
	var diagnosis: String = str(step.get("diagnosis", "")).strip_edges()
	var verify_result: String = str(step.get("verifyResult", "")).strip_edges()
	var is_done: bool = bool(step.get("completed", false))

	# 1. Target Resource Bar (CheckBox + Clickable res:// Path + Quick Run F6)
	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", _S(4))
	_body_container.add_child(target_row)

	var step_cb := CheckBox.new()
	step_cb.button_pressed = is_done
	step_cb.tooltip_text = "Mark step completed"
	step_cb.toggled.connect(_on_step_checkbox_toggled.bind(feat_id, cp_id, step_id))
	target_row.add_child(step_cb)

	var path_btn := Button.new()
	var is_gd: bool = step_path.ends_with(".gd")
	path_btn.text = step_path
	path_btn.icon = _editor_icon("Script" if is_gd else "PackedScene", "File")
	path_btn.flat = true
	path_btn.theme_type_variation = &"FlatButton"
	path_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	path_btn.clip_text = true
	path_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_btn.tooltip_text = "Open %s in Godot" % step_path
	path_btn.add_theme_color_override("font_color", _editor_color("accent_color", Color(0.45, 0.76, 0.96)))
	path_btn.pressed.connect(_on_open_res_path_pressed.bind(step_path))
	target_row.add_child(path_btn)

	var quick_f6 := Button.new()
	quick_f6.flat = true
	quick_f6.theme_type_variation = &"FlatButton"
	quick_f6.icon = _editor_icon("PlayScene", "Play")
	if quick_f6.icon == null:
		quick_f6.text = "F6"
	quick_f6.tooltip_text = "Run Scene (F6)"
	quick_f6.pressed.connect(_on_run_scene_pressed.bind(step_path))
	target_row.add_child(quick_f6)

	# 2. Agent Root-Cause Diagnosis (only present on [FIX] steps)
	if not diagnosis.is_empty():
		var diag_panel := PanelContainer.new()
		var diag_sb: StyleBox = _editor_stylebox("panel", "Tree")
		if diag_sb != null:
			diag_panel.add_theme_stylebox_override("panel", diag_sb)
		_body_container.add_child(diag_panel)

		var diag_hb := HBoxContainer.new()
		diag_hb.add_theme_constant_override("separation", _S(6))
		diag_panel.add_child(diag_hb)

		var diag_icon := TextureRect.new()
		diag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		diag_icon.texture = _editor_icon("StatusError")
		diag_hb.add_child(diag_icon)

		var diag_lbl := Label.new()
		diag_lbl.text = diagnosis
		diag_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		diag_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		diag_lbl.add_theme_color_override("font_color", _editor_color("error_color", Color(0.96, 0.56, 0.62)))
		diag_hb.add_child(diag_lbl)

	# 3. Clean Native BBCode Instructions (RichTextLabel — ZERO raw backticks)
	var instr_rtl := RichTextLabel.new()
	instr_rtl.bbcode_enabled = true
	instr_rtl.fit_content = true
	instr_rtl.scroll_active = false
	instr_rtl.selection_enabled = true
	instr_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mono_font: Font = _editor_font("source")
	if mono_font != null:
		instr_rtl.add_theme_font_override("mono_font", mono_font)
	instr_rtl.add_theme_color_override("default_color", _editor_color("font_color", Color(0.88, 0.90, 0.94)))
	instr_rtl.text = _markdown_to_bbcode(instruction)
	_body_container.add_child(instr_rtl)

	# 4. Evaluate Step Capabilities & Render Native Godot Tree Widget
	var eval_info: Dictionary = _executor.call("evaluate_step", feat, step, editor_interface) if _executor != null else {"rows": [], "readyCount": 0, "totalCount": 0, "allReady": false}
	var rows: Array = eval_info.get("rows", [])
	var ready_cnt: int = int(eval_info.get("readyCount", 0))
	var total_cnt: int = int(eval_info.get("totalCount", rows.size()))
	var all_ready: bool = bool(eval_info.get("allReady", false))

	var check_hdr_row := HBoxContainer.new()
	check_hdr_row.add_theme_constant_override("separation", _S(4))
	_body_container.add_child(check_hdr_row)

	var check_hdr := Label.new()
	check_hdr.text = "Live Scene & Editor Check"
	check_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bold_font: Font = _editor_font("bold")
	if bold_font != null:
		check_hdr.add_theme_font_override("font", bold_font)
	check_hdr.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.68, 0.72, 0.78)))
	check_hdr_row.add_child(check_hdr)

	var check_cnt_lbl := Label.new()
	check_cnt_lbl.text = "%d/%d ready" % [ready_cnt, total_cnt]
	check_cnt_lbl.add_theme_color_override(
		"font_color",
		_editor_color("success_color", Color(0.35, 0.85, 0.56)) if all_ready else _editor_color("warning_color", Color(0.94, 0.74, 0.34))
	)
	check_hdr_row.add_child(check_cnt_lbl)

	_build_native_check_tree(rows)

	# 5. Capability-Driven Native Godot Action Buttons
	_build_capability_actions(step, role, step_path, eval_info)

	# 6. Collapsible Native CodeEdit Preview (for CODE & FIX steps)
	var clean_code: String = _executor.call("resolve_step_code_text", step) if _executor != null else str(step.get("codeSnippet", ""))
	if not clean_code.is_empty() and (role == "CODE" or role == "FIX"):
		var toggle_code_btn := Button.new()
		toggle_code_btn.text = "GDScript Preview"
		toggle_code_btn.icon = _editor_icon("GuiTreeArrowDown" if _show_code_preview else "GuiTreeArrowRight", "Script")
		toggle_code_btn.flat = true
		toggle_code_btn.theme_type_variation = &"FlatButton"
		toggle_code_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle_code_btn.pressed.connect(_on_toggle_code_preview_pressed)
		_body_container.add_child(toggle_code_btn)

		if _show_code_preview:
			var code_view := CodeEdit.new()
			code_view.text = clean_code
			code_view.editable = false
			code_view.gutters_draw_line_numbers = true
			code_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			if mono_font != null:
				code_view.add_theme_font_override("font", mono_font)
			var line_count: int = clean_code.split("\n").size()
			code_view.custom_minimum_size = Vector2(0.0, float(_S(clampi(line_count * 20 + 18, 84, 210))))
			_body_container.add_child(code_view)

	# 7. Verify Result Line
	if not verify_result.is_empty():
		var ver_hb := HBoxContainer.new()
		ver_hb.add_theme_constant_override("separation", _S(6))
		_body_container.add_child(ver_hb)

		var ver_icon := TextureRect.new()
		ver_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ver_icon.texture = _editor_icon("StatusSuccess" if all_ready else "GuiRadioUnchecked", "StatusSuccess")
		ver_hb.add_child(ver_icon)

		var ver_lbl := Label.new()
		ver_lbl.text = "Verify: %s" % verify_result.replace("->", "→")
		ver_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ver_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ver_lbl.add_theme_color_override("font_color", _editor_color("success_color" if all_ready else "disabled_font_color", Color(0.65, 0.75, 0.72)))
		ver_hb.add_child(ver_lbl)

	# 8. Collapsible AI Fix Bar
	_render_agent_fix_drawer(feat, feat_id, cp_id)

	# 9. Primary Footer CTA
	var is_last_step: bool = (_selected_step_idx == max_idx - 1)
	if all_ready or is_done:
		_primary_cta_btn.text = "Complete & Go to Playtest" if is_last_step else "Complete & Next Step"
		_primary_cta_btn.icon = _editor_icon("StatusSuccess")
	else:
		_primary_cta_btn.text = "Complete Manually & Next"
		_primary_cta_btn.icon = _editor_icon("Forward")


func _build_native_check_tree(rows: Array) -> void:
	_check_tree = Tree.new()
	_check_tree.hide_root = true
	_check_tree.columns = 2
	_check_tree.column_titles_visible = false
	_check_tree.select_mode = Tree.SELECT_ROW
	_check_tree.set_column_expand(0, true)
	_check_tree.set_column_expand(1, false)
	_check_tree.set_column_custom_minimum_width(1, _S(48))
	var target_h: int = _S(clampf(float(maxi(rows.size(), 1)) * 27.0 + 12.0, 56.0, 236.0))
	_check_tree.custom_minimum_size = Vector2(0.0, float(target_h))
	_check_tree.item_activated.connect(_on_check_tree_item_activated)
	_check_tree.button_clicked.connect(_on_check_tree_button_clicked)
	_body_container.add_child(_check_tree)

	var root_item: TreeItem = _check_tree.create_item()
	var item_by_id: Dictionary = {}
	_tree_row_lookup = {}

	var ok_icon: Texture2D = _editor_icon("StatusSuccess")
	var pending_icon: Texture2D = _editor_icon("GuiRadioUnchecked", "StatusWarning")
	var inspect_icon: Texture2D = _editor_icon("GuiVisibilityVisible", "Search")
	var ok_col: Color = _editor_color("success_color", Color(0.36, 0.85, 0.56))
	var muted_col: Color = _editor_color("disabled_font_color", Color(0.66, 0.70, 0.76))

	for r_raw in rows:
		if typeof(r_raw) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = r_raw
		var r_id: String = str(r.get("id", ""))
		var p_id: String = str(r.get("parentId", ""))
		var title: String = str(r.get("title", ""))
		var subtitle: String = str(r.get("subtitle", ""))
		var icon_name: String = str(r.get("iconName", "Node"))
		var r_ok: bool = bool(r.get("ok", false))
		var focus_path: String = str(r.get("focusPath", ""))
		var res_path: String = str(r.get("resPath", ""))

		var parent_item: TreeItem = root_item
		if not p_id.is_empty() and item_by_id.has(p_id):
			parent_item = item_by_id[p_id] as TreeItem

		var item: TreeItem = _check_tree.create_item(parent_item)
		var label_txt: String = title if subtitle.is_empty() else "%s  (%s)" % [title, subtitle]
		item.set_text(0, label_txt)
		item.set_tooltip_text(0, label_txt)
		var cls_icon: Texture2D = _editor_icon(icon_name, "Node")
		if cls_icon != null:
			item.set_icon(0, cls_icon)

		if r_ok:
			item.set_custom_color(0, ok_col)
			if ok_icon != null:
				item.set_icon(1, ok_icon)
		else:
			item.set_custom_color(0, _editor_color("font_color", Color(0.88, 0.90, 0.94)))
			if pending_icon != null:
				item.set_icon(1, pending_icon)
				item.set_icon_modulate(1, muted_col)

		if not focus_path.is_empty() or not res_path.is_empty():
			if inspect_icon != null:
				item.add_button(1, inspect_icon, 0, false, "Focus in Scene / Open in Editor")

		var key_id: String = r_id if not r_id.is_empty() else str(_tree_row_lookup.size())
		item.set_metadata(0, key_id)
		_tree_row_lookup[key_id] = r
		if not r_id.is_empty():
			item_by_id[r_id] = item


func _build_capability_actions(step: Dictionary, role: String, step_path: String, eval_info: Dictionary) -> void:
	var missing_nodes: Array = eval_info.get("missingNodeSpecs", [])
	var missing_instances: Array = eval_info.get("missingInstanceSpecs", [])
	var missing_inputs: Array = eval_info.get("missingInputSpecs", [])
	var missing_insp: Array = eval_info.get("missingInspSpecs", [])
	var sig_specs: Array = eval_info.get("sigSpecs", [])
	var missing_sigs: Array = eval_info.get("missingSigSpecs", [])
	var has_code: bool = bool(eval_info.get("hasCode", false))
	var code_exists: bool = bool(eval_info.get("codeExists", false))
	var code_attached: bool = bool(eval_info.get("codeAttached", false))
	var code_merged: bool = bool(eval_info.get("codeMerged", false))
	var is_playtest_step: bool = bool(eval_info.get("isPlaytestStep", false))
	var needs_scene_file: bool = step_path.ends_with(".tscn") and not FileAccess.file_exists(step_path)

	var did_add_action: bool = false

	# 1. Missing Scene Nodes / Child Scene Instances / Missing .tscn File
	if not missing_nodes.is_empty() or not missing_instances.is_empty() or (needs_scene_file and (role == "SCENE" or not eval_info.get("nodeSpecs", []).is_empty())):
		var build_btn := Button.new()
		build_btn.text = "Build Missing Scene Nodes"
		build_btn.icon = _editor_icon("Add")
		build_btn.tooltip_text = "Create missing nodes, shapes, meshes & scene file (Ctrl+Z supported)"
		build_btn.pressed.connect(_on_action_build_scene_nodes.bind(step, eval_info))
		_body_container.add_child(build_btn)
		did_add_action = true

	# 2. Missing InputMap Key Bindings or Inspector Properties
	if not missing_inputs.is_empty() or not missing_insp.is_empty():
		var insp_btn := Button.new()
		insp_btn.text = "Apply Input & Inspector Settings" if (not missing_inputs.is_empty() and not missing_insp.is_empty()) else ("Bind InputMap Keys" if not missing_inputs.is_empty() else "Apply Inspector Settings")
		insp_btn.icon = _editor_icon("Edit", "Tools")
		insp_btn.pressed.connect(_on_action_apply_input_and_inspector.bind(step, eval_info))
		_body_container.add_child(insp_btn)
		did_add_action = true
	elif role == "INSP" and not did_add_action:
		var focus_btn := Button.new()
		focus_btn.text = "Focus Node in Inspector"
		focus_btn.icon = _editor_icon("GuiVisibilityVisible", "Search")
		focus_btn.pressed.connect(_on_action_apply_input_and_inspector.bind(step, eval_info))
		_body_container.add_child(focus_btn)
		did_add_action = true

	# 3. GDScript Create / Merge / Attach / Open + Copy
	if has_code:
		var code_row := HBoxContainer.new()
		code_row.add_theme_constant_override("separation", _S(6))
		_body_container.add_child(code_row)

		var script_btn := Button.new()
		script_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if role == "FIX":
			if not code_merged:
				script_btn.text = "Apply Fix Patch to Script"
				script_btn.icon = _editor_icon("ScriptExtend", "Script")
			else:
				script_btn.text = "Open Patched Script"
				script_btn.icon = _editor_icon("Script")
			script_btn.pressed.connect(_on_action_apply_fix_patch.bind(step, step_path))
		else:
			if not code_exists:
				script_btn.text = "Create & Attach Script"
				script_btn.icon = _editor_icon("ScriptCreate", "Script")
			elif not code_merged:
				script_btn.text = "Apply Step Code to Script"
				script_btn.icon = _editor_icon("ScriptExtend", "Script")
			elif not code_attached:
				script_btn.text = "Attach & Open Script"
				script_btn.icon = _editor_icon("Script")
			else:
				script_btn.text = "Open Script in Editor"
				script_btn.icon = _editor_icon("Script")
			script_btn.pressed.connect(_on_action_apply_or_create_script.bind(step, eval_info))
		code_row.add_child(script_btn)

		var copy_btn := Button.new()
		copy_btn.text = "Copy Code"
		copy_btn.icon = _editor_icon("ActionCopy")
		copy_btn.pressed.connect(_on_copy_step_code_pressed.bind(step))
		code_row.add_child(copy_btn)
		did_add_action = true

	# 4. Signal Wiring (ONLY shown when actual signal specs exist)
	if not sig_specs.is_empty():
		var w_row := HBoxContainer.new()
		w_row.add_theme_constant_override("separation", _S(6))
		_body_container.add_child(w_row)

		var conn_btn := Button.new()
		conn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not missing_sigs.is_empty():
			conn_btn.text = "Connect Signal" if sig_specs.size() == 1 else "Connect %d Signals" % sig_specs.size()
			conn_btn.icon = _editor_icon("Signals")
		else:
			conn_btn.text = "Signal Connected" if sig_specs.size() == 1 else "%d Signals Connected" % sig_specs.size()
			conn_btn.icon = _editor_icon("StatusSuccess")
		conn_btn.pressed.connect(_on_action_connect_signals.bind(step, eval_info))
		w_row.add_child(conn_btn)

		var f6_w_btn := Button.new()
		f6_w_btn.text = "Run Scene (F6)"
		f6_w_btn.icon = _editor_icon("PlayScene", "Play")
		f6_w_btn.pressed.connect(_on_run_scene_pressed.bind(step_path))
		w_row.add_child(f6_w_btn)
		did_add_action = true

	# 5. Playtest Verification Button (e.g., Verify Floor Collision)
	if is_playtest_step and sig_specs.is_empty() and missing_nodes.is_empty() and missing_inputs.is_empty() and not needs_scene_file:
		var run_btn := Button.new()
		run_btn.text = "Run Scene (F6)"
		run_btn.icon = _editor_icon("PlayScene", "Play")
		run_btn.pressed.connect(_on_run_scene_pressed.bind(step_path))
		_body_container.add_child(run_btn)
		did_add_action = true

	# 6. Fallback when Scene nodes are already complete
	if not did_add_action and step_path.ends_with(".tscn"):
		var open_scene_btn := Button.new()
		open_scene_btn.text = "Open Scene in Godot"
		open_scene_btn.icon = _editor_icon("PackedScene")
		open_scene_btn.pressed.connect(_on_open_res_path_pressed.bind(step_path))
		_body_container.add_child(open_scene_btn)


func _render_playtest_gate(feat: Dictionary, feat_id: String, cp_id: String, gate_passed: bool) -> void:
	var goal_hdr := Label.new()
	goal_hdr.text = "Feature End Goal (Playtest Gate)"
	var bold_font: Font = _editor_font("bold")
	if bold_font != null:
		goal_hdr.add_theme_font_override("font", bold_font)
	goal_hdr.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.68, 0.72, 0.78)))
	_body_container.add_child(goal_hdr)

	var done_when: String = str(feat.get("doneWhen", "Press F6 and verify this feature with 0 console errors.")).strip_edges()
	var goal_lbl := Label.new()
	goal_lbl.text = done_when
	goal_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_container.add_child(goal_lbl)

	var gate_cb := CheckBox.new()
	gate_cb.text = "Playtest Passed (0 Console Errors)"
	gate_cb.button_pressed = gate_passed
	gate_cb.toggled.connect(_on_playtest_gate_toggled.bind(feat_id, cp_id))
	_body_container.add_child(gate_cb)

	var run_btn := Button.new()
	run_btn.text = "Run Current Scene (F6)"
	run_btn.icon = _editor_icon("PlayScene", "Play")
	run_btn.pressed.connect(_on_run_scene_pressed.bind(str(feat.get("primaryAsset", ""))))
	_body_container.add_child(run_btn)


func _render_agent_fix_drawer(_feat: Dictionary, feat_id: String, cp_id: String) -> void:
	var drawer := PanelContainer.new()
	var drawer_sb: StyleBox = _editor_stylebox("panel", "Tree")
	if drawer_sb != null:
		drawer.add_theme_stylebox_override("panel", drawer_sb)
	_body_container.add_child(drawer)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _S(6))
	drawer.add_child(vb)

	var toggle_btn := Button.new()
	toggle_btn.text = "Broken? Ask Agent to Fix"
	toggle_btn.icon = _editor_icon("GuiTreeArrowDown" if _fix_drawer_open else "GuiTreeArrowRight", "Tools")
	toggle_btn.flat = true
	toggle_btn.theme_type_variation = &"FlatButton"
	toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle_btn.pressed.connect(_on_toggle_fix_drawer_pressed)
	vb.add_child(toggle_btn)

	if not _fix_drawer_open:
		return

	var hint_lbl := Label.new()
	hint_lbl.text = "Sends live Scene Tree + .gd scripts to Gemini 4 Hydrogen for a 1-click patch."
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.68, 0.72, 0.78)))
	vb.add_child(hint_lbl)

	_fix_input = LineEdit.new()
	_fix_input.placeholder_text = "Describe bug or paste Godot Output error..."
	_fix_input.text = _fix_draft_text
	_fix_input.text_changed.connect(func(txt: String) -> void: _fix_draft_text = txt)
	_fix_input.text_submitted.connect(_on_fix_input_submitted.bind(feat_id, cp_id))
	vb.add_child(_fix_input)

	var ask_btn := Button.new()
	ask_btn.text = "Diagnosing Live Project..." if _diagnosing_fix else "Diagnose & Fix"
	ask_btn.icon = _editor_icon("Tools")
	ask_btn.disabled = _diagnosing_fix
	ask_btn.pressed.connect(_on_ask_agent_fix_pressed.bind(feat_id, cp_id))
	vb.add_child(ask_btn)


# ---------------------------------------------------------------------------
# Action & Tree Callbacks
# ---------------------------------------------------------------------------

func _on_check_tree_button_clicked(item: TreeItem, _column: int, _id: int, _mouse_button_index: int) -> void:
	_focus_or_open_tree_item(item)


func _on_check_tree_item_activated() -> void:
	if _check_tree == null:
		return
	var item: TreeItem = _check_tree.get_selected()
	if item != null:
		_focus_or_open_tree_item(item)


func _focus_or_open_tree_item(item: TreeItem) -> void:
	if item == null:
		return
	var key_id: String = str(item.get_metadata(0))
	if not _tree_row_lookup.has(key_id):
		return
	var row: Dictionary = _tree_row_lookup[key_id]
	var focus_path: String = str(row.get("focusPath", ""))
	var res_path: String = str(row.get("resPath", ""))

	if not focus_path.is_empty() and editor_interface != null:
		var root: Node = editor_interface.get_edited_scene_root()
		if root != null:
			var target: Node = root if focus_path == "." else root.get_node_or_null(NodePath(focus_path))
			if target != null and _executor != null:
				_executor.call("select_and_inspect_node", editor_interface, target)
				_set_status("Focused %s in Scene & Inspector" % target.name, false)
				return
	if not res_path.is_empty():
		_on_open_res_path_pressed(res_path)


func _on_action_build_scene_nodes(step: Dictionary, eval_info: Dictionary) -> void:
	if _executor == null:
		return
	var res: Dictionary = _executor.call("build_missing_scene_nodes", editor_interface, undo_redo, step, eval_info)
	if not bool(res.get("ok", false)):
		_set_status(str(res.get("message", "Could not build scene nodes.")), true)
		return
	var added_cnt: int = int(res.get("addedCount", 0))
	_set_status("Built %d node(s) with Ctrl+Z support" % added_cnt if added_cnt > 0 else "Scene hierarchy already up to date", false)
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_action_apply_input_and_inspector(step: Dictionary, eval_info: Dictionary) -> void:
	if _executor == null:
		return
	var res: Dictionary = _executor.call("apply_input_and_inspector", editor_interface, undo_redo, step, eval_info)
	var inp_cnt: int = int(res.get("inputCount", 0))
	var prop_cnt: int = int(res.get("propCount", 0))
	_set_status("Bound %d InputMap action(s), updated %d property change(s)" % [inp_cnt, prop_cnt], false)
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_action_apply_or_create_script(step: Dictionary, eval_info: Dictionary) -> void:
	if _executor == null:
		return
	var res: Dictionary = _executor.call("apply_or_create_script", editor_interface, undo_redo, step, eval_info)
	if not bool(res.get("ok", false)):
		_set_status(str(res.get("message", "Could not update script.")), true)
		return
	var p: String = str(res.get("path", ""))
	if bool(res.get("wroteFile", false)):
		_set_status("Updated %s & opened in Script Editor" % p.get_file(), false)
	else:
		_set_status("Opened %s in Script Editor" % p.get_file(), false)
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_action_connect_signals(step: Dictionary, eval_info: Dictionary) -> void:
	if _executor == null:
		return
	var res: Dictionary = _executor.call("connect_step_signals", editor_interface, step, eval_info)
	var cnt: int = int(res.get("connectedCount", 0))
	if cnt > 0:
		_set_status("Connected %d signal(s) persistently" % cnt, false)
	else:
		_set_status("Select source node in Node -> Signals dock to finish wiring.", false)
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_action_apply_fix_patch(step: Dictionary, step_path: String) -> void:
	if _executor == null:
		return
	var res: Dictionary = _executor.call("apply_fix_patch", editor_interface, step, step_path)
	if bool(res.get("applied", false)):
		_set_status("Applied AI fix patch to %s" % str(res.get("path", "")).get_file(), false)
	else:
		_set_status("Copied clean fix snippet & opened %s — paste at target function." % str(res.get("path", "")).get_file(), false)
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_copy_step_code_pressed(step: Dictionary) -> void:
	var clean: String = _executor.call("resolve_step_code_text", step) if _executor != null else str(step.get("codeSnippet", ""))
	DisplayServer.clipboard_set(clean)
	_set_status("Copied clean GDScript to clipboard", false)


func _on_open_res_path_pressed(res_path: String) -> void:
	if _executor == null:
		return
	var err_msg: String = str(_executor.call("open_res_path", editor_interface, res_path))
	if not err_msg.is_empty():
		_set_status(err_msg, true)


func _on_run_scene_pressed(target_scene_path: String = "") -> void:
	if editor_interface == null:
		return
	if not target_scene_path.is_empty() and target_scene_path.ends_with(".tscn") and FileAccess.file_exists(target_scene_path):
		var cur_root: Node = editor_interface.get_edited_scene_root()
		if cur_root == null or cur_root.scene_file_path != target_scene_path:
			editor_interface.play_custom_scene(target_scene_path)
			return
	editor_interface.play_current_scene()


# ---------------------------------------------------------------------------
# Live Scene & Script Snapshots for Agent Fix
# ---------------------------------------------------------------------------

func _capture_live_scene_snapshot() -> String:
	if editor_interface == null:
		return "(No EditorInterface)"
	var root: Node = editor_interface.get_edited_scene_root()
	if root == null:
		return "(No edited scene open in Godot)"
	var lines: PackedStringArray = []
	lines.append("Edited Scene: %s" % root.scene_file_path)
	_append_node_snapshot(root, 0, lines)
	return "\n".join(lines)


func _append_node_snapshot(node: Node, depth: int, lines: PackedStringArray) -> void:
	if node == null or lines.size() > 80:
		return
	var indent: String = "  ".repeat(depth)
	var scr: Variant = node.get_script()
	var scr_note: String = " [script: %s]" % (scr as Script).resource_path if scr is Script else ""
	lines.append("%s- %s (%s)%s" % [indent, node.name, node.get_class(), scr_note])
	for child in node.get_children():
		_append_node_snapshot(child, depth + 1, lines)


func _capture_live_scripts_snapshot(feat: Dictionary) -> String:
	var seen: Dictionary = {}
	var chunks: PackedStringArray = []
	var steps: Array = feat.get("steps", [])
	for s_raw in steps:
		if typeof(s_raw) == TYPE_DICTIONARY:
			var sp: String = str((s_raw as Dictionary).get("stepPath", "")).strip_edges()
			if sp.ends_with(".gd") and FileAccess.file_exists(sp):
				seen[sp] = true
	if editor_interface != null and editor_interface.get_edited_scene_root() != null:
		_collect_scene_scripts(editor_interface.get_edited_scene_root(), seen)

	for path in seen.keys():
		if chunks.size() >= 5:
			break
		var f := FileAccess.open(str(path), FileAccess.READ)
		if f != null:
			chunks.append("=== %s ===\n%s" % [str(path), f.get_as_text().substr(0, 6000)])
			f.close()
	return "\n\n".join(chunks)


func _collect_scene_scripts(node: Node, seen: Dictionary) -> void:
	if node == null:
		return
	var scr: Variant = node.get_script()
	if scr is Script:
		var rp: String = (scr as Script).resource_path
		if rp.begins_with("res://") and FileAccess.file_exists(rp):
			seen[rp] = true
	for child in node.get_children():
		_collect_scene_scripts(child, seen)


# ---------------------------------------------------------------------------
# Native Godot EditorTheme & Formatting Helpers
# ---------------------------------------------------------------------------

func _ed_scale() -> float:
	if editor_interface != null:
		var sc: float = editor_interface.get_editor_scale()
		if sc > 0.0:
			return sc
	return 1.0


func _S(px: float) -> int:
	return int(roundf(px * _ed_scale()))


func _theme_ctrl() -> Control:
	if editor_interface != null and editor_interface.get_base_control() != null:
		return editor_interface.get_base_control()
	return self


func _editor_icon(icon_name: String, fallback_name: String = "") -> Texture2D:
	var tc: Control = _theme_ctrl()
	if tc == null:
		return null
	if not icon_name.is_empty() and tc.has_theme_icon(icon_name, &"EditorIcons"):
		return tc.get_theme_icon(icon_name, &"EditorIcons")
	if not fallback_name.is_empty() and tc.has_theme_icon(fallback_name, &"EditorIcons"):
		return tc.get_theme_icon(fallback_name, &"EditorIcons")
	return null


func _editor_color(color_name: String, fallback: Color) -> Color:
	var tc: Control = _theme_ctrl()
	if tc != null and tc.has_theme_color(color_name, &"Editor"):
		return tc.get_theme_color(color_name, &"Editor")
	return fallback


func _editor_font(font_name: String) -> Font:
	var tc: Control = _theme_ctrl()
	if tc != null and tc.has_theme_font(font_name, &"EditorFonts"):
		return tc.get_theme_font(font_name, &"EditorFonts")
	return null


func _editor_stylebox(box_name: String, theme_type: String) -> StyleBox:
	var tc: Control = _theme_ctrl()
	if tc != null and tc.has_theme_stylebox(box_name, StringName(theme_type)):
		return tc.get_theme_stylebox(box_name, StringName(theme_type))
	return null


func _step_picker_icon(st: Dictionary, is_done: bool) -> Texture2D:
	if is_done:
		return _editor_icon("StatusSuccess")
	var st_role: String = str(st.get("role", "CODE"))
	match st_role:
		"SCENE":
			return _editor_icon("PackedScene", "Node")
		"INSP":
			return _editor_icon("Edit", "Tools")
		"CODE":
			return _editor_icon("Script", "TextFile")
		"WIRE":
			if str(st.get("verifyMode", "")) == "playtest" and not ("-->" in str(st.get("codeSnippet", "")) or "──►" in str(st.get("codeSnippet", "")) or "->" in str(st.get("codeSnippet", ""))):
				return _editor_icon("PlayScene", "Play")
			return _editor_icon("Signals", "PlayScene")
		"FIX":
			return _editor_icon("StatusError", "Tools")
	return _editor_icon("Node")


func _markdown_to_bbcode(raw: String) -> String:
	var out_lines := PackedStringArray()
	var code_bg: Color = _editor_color("dark_color_2", Color(0.10, 0.12, 0.15))
	var code_fg: Color = _editor_color("accent_color", Color(0.62, 0.84, 0.98))
	var bg_hex: String = code_bg.to_html(false)
	var fg_hex: String = code_fg.to_html(false)

	for raw_line in raw.replace("\r\n", "\n").split("\n"):
		var line: String = raw_line.strip_edges()
		if line.is_empty():
			continue
		var is_bullet: bool = false
		if line.begins_with("- ") or line.begins_with("* "):
			is_bullet = true
			line = line.substr(2).strip_edges()

		var escaped: String = line.replace("[", "[lb]").replace("->", "→")
		var formatted: String = ""
		var parts: PackedStringArray = escaped.split("`")
		for idx in range(parts.size()):
			var seg: String = parts[idx]
			if idx % 2 == 1 and idx < parts.size() - 1:
				formatted += "[bgcolor=#%s][color=#%s][code] %s [/code][/color][/bgcolor]" % [bg_hex, fg_hex, seg]
			else:
				formatted += seg
		if is_bullet:
			out_lines.append("•  " + formatted)
		else:
			out_lines.append(formatted)
	return "\n".join(out_lines)


func _set_status(msg: String, is_error: bool) -> void:
	if _status_label == null:
		return
	_status_label.text = msg
	if is_error:
		_status_label.add_theme_color_override("font_color", _editor_color("error_color", Color(0.95, 0.48, 0.48)))
	else:
		_status_label.add_theme_color_override("font_color", _editor_color("success_color", Color(0.36, 0.85, 0.56)))


# ---------------------------------------------------------------------------
# Signal Handlers & Navigation
# ---------------------------------------------------------------------------

func _on_feature_selected(idx: int) -> void:
	var epic_raw: Variant = _payload.get("activeEpic", null)
	if typeof(epic_raw) != TYPE_DICTIONARY:
		return
	var features: Array = (epic_raw as Dictionary).get("features", [])
	if idx >= 0 and idx < features.size():
		var f: Dictionary = features[idx]
		_selected_feature_id = str(f.get("id", ""))
		_selected_step_idx = _find_first_incomplete_step_idx(f)
		_show_code_preview = false
		_render_active_step_workspace(f)


func _on_step_selected(idx: int) -> void:
	_selected_step_idx = idx
	_show_code_preview = false
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_prev_step_pressed() -> void:
	_selected_step_idx = maxi(0, _selected_step_idx - 1)
	_show_code_preview = false
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_next_step_pressed() -> void:
	var feat: Dictionary = _get_active_feature()
	if feat.is_empty():
		return
	var steps: Array = feat.get("steps", [])
	_selected_step_idx = mini(steps.size(), _selected_step_idx + 1)
	_show_code_preview = false
	_render_active_step_workspace(feat)


func _on_step_checkbox_toggled(pressed: bool, feat_id: String, cp_id: String, step_id: String) -> void:
	if _sync == null:
		return
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty() and str(feat.get("id", "")) == feat_id:
		for st_raw in feat.get("steps", []):
			if typeof(st_raw) == TYPE_DICTIONARY and str((st_raw as Dictionary).get("id", "")) == step_id:
				(st_raw as Dictionary)["completed"] = pressed
				break
		if not pressed:
			feat["isPlaytestPassed"] = false
			feat["isCompleted"] = false
	_set_status("Syncing...", false)
	_sync.toggle_step(feat_id, cp_id, step_id, pressed)


func _on_playtest_gate_toggled(pressed: bool, feat_id: String, cp_id: String) -> void:
	if _sync == null:
		return
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty() and str(feat.get("id", "")) == feat_id:
		feat["isPlaytestPassed"] = pressed
	_set_status("Syncing Playtest Gate...", false)
	_sync.set_playtest_passed(feat_id, cp_id, pressed)


func _on_toggle_code_preview_pressed() -> void:
	_show_code_preview = not _show_code_preview
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_toggle_fix_drawer_pressed() -> void:
	_fix_drawer_open = not _fix_drawer_open
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_fix_input_submitted(_text: String, feat_id: String, cp_id: String) -> void:
	_on_ask_agent_fix_pressed(feat_id, cp_id)


func _on_ask_agent_fix_pressed(feat_id: String, cp_id: String) -> void:
	if _sync == null or _fix_input == null:
		return
	var issue: String = _fix_input.text.strip_edges()
	if issue.is_empty():
		_set_status("Describe the bug or paste a Godot error first.", true)
		return
	var feat: Dictionary = _get_active_feature()
	var scene_snap: String = _capture_live_scene_snapshot()
	var scripts_snap: String = _capture_live_scripts_snapshot(feat)
	_diagnosing_fix = true
	_set_status("Inspecting live Scene Tree + .gd scripts...", false)
	if not feat.is_empty():
		_render_active_step_workspace(feat)
	_sync.diagnose_fix(feat_id, cp_id, issue, scene_snap, scripts_snap)


func _on_primary_cta_pressed() -> void:
	if _sync == null:
		return
	var feat: Dictionary = _get_active_feature()
	if feat.is_empty():
		return
	var feat_id: String = str(feat.get("id", ""))
	var cp_id: String = str(feat.get("checkpointId", ""))
	var steps: Array = feat.get("steps", [])

	if _selected_step_idx >= steps.size():
		_set_status("Passing Playtest Gate...", false)
		_sync.set_playtest_passed(feat_id, cp_id, true)
		return

	var st: Dictionary = steps[_selected_step_idx]
	var step_id: String = str(st.get("id", ""))
	st["completed"] = true
	_selected_step_idx = mini(steps.size(), _selected_step_idx + 1)
	_show_code_preview = false
	_set_status("Step completed", false)
	_refresh_view()
	_sync.toggle_step(feat_id, cp_id, step_id, true)


func _on_epic_updated(payload: Dictionary) -> void:
	_payload = payload
	_diagnosing_fix = false

	var created_fix_id: String = str(payload.get("createdFixStepId", "")).strip_edges()
	if not created_fix_id.is_empty():
		_fix_drawer_open = false
		_fix_draft_text = ""
		_show_code_preview = true
		var feat: Dictionary = _get_active_feature()
		var steps: Array = feat.get("steps", []) if not feat.is_empty() else []
		for i in range(steps.size()):
			if typeof(steps[i]) == TYPE_DICTIONARY and str((steps[i] as Dictionary).get("id", "")) == created_fix_id:
				_selected_step_idx = i
				break
		_set_status("Gemini 4 Hydrogen created [FIX] patch", false)
	else:
		_set_status("Synced", false)
	_refresh_view()


func _on_sync_failed(message: String) -> void:
	_diagnosing_fix = false
	_set_status(message, true)
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty() and _workspace_panel.visible:
		_render_active_step_workspace(feat)


func _on_busy_changed(is_busy: bool) -> void:
	if _sync_btn != null:
		_sync_btn.disabled = is_busy
	if is_busy and _status_label != null and not _diagnosing_fix:
		_status_label.text = "Syncing..."
		_status_label.add_theme_color_override("font_color", _editor_color("accent_color", Color(0.45, 0.78, 0.98)))


func _on_connect_submitted(_text: String) -> void:
	_on_connect_pressed()


func _on_connect_pressed() -> void:
	if _sync == null:
		return
	var token: String = _token_input.text.strip_edges()
	if not token.begins_with("lyr_") or token.length() < 20:
		_set_status("Enter a valid lyr_... Link Token.", true)
		return
	_sync.save_link_token(token)
	_show_token_editor = false
	_payload = {}
	_selected_feature_id = ""
	_selected_step_idx = 0
	_refresh_view()
	_sync.fetch_active_epic()


func _on_cancel_token_pressed() -> void:
	_show_token_editor = false
	_refresh_view()


func _on_disconnect_pressed() -> void:
	if _sync == null:
		return
	_sync.clear_link_token()
	_payload = {}
	_selected_feature_id = ""
	_selected_step_idx = 0
	_show_token_editor = true
	_status_label.text = "Disconnected"
	_status_label.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.66, 0.70, 0.76)))
	_refresh_view()


func _on_sync_pressed() -> void:
	if _sync != null:
		_sync.fetch_active_epic()


func _on_open_web_pressed() -> void:
	var url: String = str(_payload.get("webStudioUrl", DEFAULT_WEB_STUDIO_URL)).strip_edges()
	if url.is_empty():
		url = DEFAULT_WEB_STUDIO_URL
	OS.shell_open(url)


func _on_settings_pressed() -> void:
	_show_token_editor = true
	_refresh_view()


func _on_check_plugin_update_pressed() -> void:
	if _sync == null or _checking_plugin_update or _updating_plugin:
		return
	_checking_plugin_update = true
	if _check_update_btn != null:
		_check_update_btn.disabled = true
		_check_update_btn.text = "Checking..."
	_set_status("Checking GitHub for plugin updates...", false)
	_sync.check_for_plugin_update(false)


func _on_update_now_pressed() -> void:
	if _sync == null or _updating_plugin:
		return
	_updating_plugin = true
	_refresh_update_banner()
	_set_status("Downloading LAYERS plugin v%s..." % _available_remote_version, false)
	_sync.download_and_apply_plugin_update()


func _on_plugin_update_available(_local_ver: String, remote_ver: String) -> void:
	_available_remote_version = remote_ver
	_refresh_update_banner()


func _on_plugin_update_check_finished(up_to_date: bool, local_ver: String, remote_ver: String) -> void:
	var was_manual: bool = _checking_plugin_update
	_checking_plugin_update = false
	if _check_update_btn != null:
		_check_update_btn.disabled = false
		_check_update_btn.text = "Check for Plugin Update"
	if _version_label != null:
		_version_label.text = "Plugin v%s" % local_ver
	if up_to_date:
		_available_remote_version = ""
		_refresh_update_banner()
		if was_manual:
			_set_status("Plugin v%s is up to date" % local_ver, false)
	else:
		_available_remote_version = remote_ver
		_refresh_update_banner()
		if was_manual:
			_set_status("Plugin v%s available — click Update Now above." % remote_ver, false)


func _on_plugin_update_failed(message: String) -> void:
	_checking_plugin_update = false
	_updating_plugin = false
	if _check_update_btn != null:
		_check_update_btn.disabled = false
		_check_update_btn.text = "Check for Plugin Update"
	_refresh_update_banner()
	_set_status(message, true)


func _on_plugin_update_ready_to_reload(new_ver: String, updated_gd_paths: PackedStringArray) -> void:
	_updating_plugin = false
	_available_remote_version = ""
	if _version_label != null:
		_version_label.text = "Plugin v%s" % new_ver
	_refresh_update_banner()
	_set_status("Updated to v%s — reloading LAYERS dock..." % new_ver, false)
	_trigger_plugin_hot_reload(new_ver, updated_gd_paths)


func _trigger_plugin_hot_reload(new_ver: String, updated_gd_paths: PackedStringArray) -> void:
	if editor_interface == null or editor_interface.get_base_control() == null:
		_set_status("Updated to v%s — toggle LAYERS plugin off/on to reload." % new_ver, false)
		return

	var base_ctrl: Control = editor_interface.get_base_control()
	var plugin_key: String = "layers"
	if not editor_interface.is_plugin_enabled("layers") and editor_interface.is_plugin_enabled("res://addons/layers/plugin.cfg"):
		plugin_key = "res://addons/layers/plugin.cfg"

	var reloader_script := GDScript.new()
	reloader_script.source_code = """@tool
extends Node

var ei: EditorInterface
var plugin_key: String = "layers"
var gd_paths: PackedStringArray = PackedStringArray()


func run_reload() -> void:
	if ei == null or get_tree() == null:
		queue_free()
		return
	ei.set_plugin_enabled(plugin_key, false)
	await get_tree().process_frame
	for p in gd_paths:
		ResourceLoader.load(p, "Script", ResourceLoader.CACHE_MODE_REPLACE)
	if ei.get_resource_filesystem() != null:
		ei.get_resource_filesystem().scan()
	await get_tree().process_frame
	ei.set_plugin_enabled(plugin_key, true)
	queue_free()
"""
	if reloader_script.reload() != OK:
		_set_status("Updated to v%s — toggle LAYERS plugin off/on to reload." % new_ver, false)
		return

	var reloader := Node.new()
	reloader.set_script(reloader_script)
	reloader.set("ei", editor_interface)
	reloader.set("plugin_key", plugin_key)
	reloader.set("gd_paths", updated_gd_paths)
	base_ctrl.add_child(reloader)
	reloader.call_deferred("run_reload")
