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
var _show_blueprint_details: bool = false
var _selected_script_preview_path: String = ""
var _building_feature: bool = false
var _diagnosing_fix: bool = false
var _fix_draft_text: String = ""
var _last_agent_summary: String = ""
var _last_agent_warnings: PackedStringArray = PackedStringArray()
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
var _complete_card: VBoxContainer
var _step_scroll: ScrollContainer
var _body_container: VBoxContainer
var _footer_box: VBoxContainer
var _primary_cta_btn: Button
var _status_label: Label

# Dynamic Controls Bound Per Render
var _fix_input: LineEdit
var _blueprint_tree: Tree
var _active_tuner_controls: Array[Control] = []


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
		_sync.agent_bundle_received.connect(_on_agent_bundle_received)
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


func _any_tuner_focused() -> bool:
	for ctrl in _active_tuner_controls:
		if ctrl == null or not is_instance_valid(ctrl):
			continue
		if ctrl.has_focus():
			return true
		if ctrl is SpinBox:
			var le: LineEdit = (ctrl as SpinBox).get_line_edit()
			if le != null and le.has_focus():
				return true
	return false


func _on_live_refresh_timeout() -> void:
	if _show_token_editor or not _workspace_panel.visible:
		return
	if _fix_input != null and _fix_input.has_focus():
		return
	if _any_tuner_focused():
		return
	var feat: Dictionary = _get_active_feature()
	if feat.is_empty():
		return
	var prev_scroll: int = _step_scroll.scroll_vertical if _step_scroll != null else 0
	_render_active_feature_workspace(feat)
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
	_version_label.text = "Plugin v%s" % (_sync.get_local_plugin_version() if _sync != null else "2.4.0")
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_label.clip_text = true
	_version_label.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.68, 0.72, 0.78)))
	ver_row.add_child(_version_label)

	_check_update_btn = Button.new()
	_check_update_btn.text = "Check for Plugin Update"
	_check_update_btn.icon = _editor_icon("Reload")
	_check_update_btn.pressed.connect(_on_check_plugin_update_pressed)
	ver_row.add_child(_check_update_btn)

	# 3. Connected Native Feature-First Workspace
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

	# Scrollable Feature Workspace
	_step_scroll = ScrollContainer.new()
	_step_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_workspace_panel.add_child(_step_scroll)

	_body_container = VBoxContainer.new()
	_body_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_container.add_theme_constant_override("separation", _S(8))
	_step_scroll.add_child(_body_container)

	# Sticky Footer CTA
	_footer_box = VBoxContainer.new()
	_footer_box.add_theme_constant_override("separation", _S(4))
	_workspace_panel.add_child(_footer_box)
	_footer_box.add_child(HSeparator.new())

	_primary_cta_btn = Button.new()
	_primary_cta_btn.text = "Build Feature in Godot"
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
		_complete_card.visible = true
		_footer_box.visible = false
		_clear_body()
		return

	_complete_card.visible = false
	if typeof(epic_raw) != TYPE_DICTIONARY or (epic_raw as Dictionary).is_empty():
		_epic_label.text = "No active Epic yet — plan in Web Studio."
		_feature_picker.visible = false
		_footer_box.visible = false
		_clear_body()
		return

	var epic: Dictionary = epic_raw
	_epic_label.text = str(epic.get("title", "Epic"))

	var features: Array = epic.get("features", [])
	_feature_picker.clear()
	_feature_picker.visible = features.size() > 0

	if features.is_empty():
		_footer_box.visible = false
		_clear_body()
		var empty_lbl := Label.new()
		empty_lbl.text = "No features in this Epic yet."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body_container.add_child(empty_lbl)
		return

	var code_files: Dictionary = _payload.get("codeFiles", {}) if typeof(_payload.get("codeFiles", null)) == TYPE_DICTIONARY else {}
	var arena_scene: String = str(_payload.get("arenaScenePath", "")).strip_edges()

	var chosen_idx: int = -1
	var first_incomplete_idx: int = -1
	for i in range(features.size()):
		var f: Dictionary = features[i]
		var f_id: String = str(f.get("id", ""))
		var f_title: String = str(f.get("title", "Feature"))
		var f_done: bool = bool(f.get("isCompleted", false)) or bool(f.get("isPlaytestPassed", false))
		var f_ready := false
		if _executor != null:
			var f_eval: Dictionary = _executor.call("evaluate_feature", f, editor_interface, code_files, arena_scene)
			f_ready = bool(f_eval.get("all_ready", false))
		_feature_picker.add_item(f_title, i)
		var f_icon: Texture2D = _editor_icon(
			"StatusSuccess" if f_done else ("PlayScene" if f_ready else "PackedScene"),
			"Node"
		)
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
		_selected_script_preview_path = ""
		_last_agent_summary = ""
		_last_agent_warnings = PackedStringArray()

	_render_active_feature_workspace(active_feat)


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
	_blueprint_tree = null
	_active_tuner_controls.clear()
	for child in _body_container.get_children():
		_body_container.remove_child(child)
		child.queue_free()


func _create_native_card() -> Dictionary:
	var panel := PanelContainer.new()
	var sb: StyleBox = _editor_stylebox("panel", "Tree")
	if sb != null:
		panel.add_theme_stylebox_override("panel", sb)
	_body_container.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", _S(8))
	margin.add_theme_constant_override("margin_right", _S(8))
	margin.add_theme_constant_override("margin_top", _S(6))
	margin.add_theme_constant_override("margin_bottom", _S(6))
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _S(6))
	margin.add_child(vb)
	return { "panel": panel, "vb": vb }


func _render_active_feature_workspace(feat: Dictionary) -> void:
	_clear_body()

	var feat_id: String = str(feat.get("id", ""))
	var cp_id: String = str(feat.get("checkpointId", ""))
	var feat_title: String = str(feat.get("title", "Feature")).strip_edges()
	var done_when: String = str(feat.get("doneWhen", "Press F6 and verify this feature with 0 console errors.")).strip_edges()
	var gate_passed: bool = bool(feat.get("isPlaytestPassed", false))

	var code_files: Dictionary = _payload.get("codeFiles", {}) if typeof(_payload.get("codeFiles", null)) == TYPE_DICTIONARY else {}
	var arena_scene: String = str(_payload.get("arenaScenePath", "")).strip_edges()
	var eval_info: Dictionary = _executor.call("evaluate_feature", feat, editor_interface, code_files, arena_scene) if _executor != null else {
		"total": 0, "ready": 0, "all_ready": false, "items": [], "primary_scene": str(feat.get("primaryAsset", "")), "arena_scene": arena_scene, "script_paths": feat.get("scriptPaths", [])
	}
	var primary_scene: String = str(eval_info.get("primary_scene", feat.get("primaryAsset", ""))).strip_edges()
	var script_paths: Array = eval_info.get("script_paths", feat.get("scriptPaths", []))
	var total_cnt: int = int(eval_info.get("total", 0))
	var ready_cnt: int = int(eval_info.get("ready", 0))
	var all_ready: bool = bool(eval_info.get("all_ready", false))

	var bold_font: Font = _editor_font("bold")
	var mono_font: Font = _editor_font("source")

	# -----------------------------------------------------------------------
	# 1. Feature Goal & Clickable Asset Chips
	# -----------------------------------------------------------------------
	var goal_card := _create_native_card()
	var goal_vb: VBoxContainer = goal_card["vb"]

	var hdr_row := HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", _S(6))
	goal_vb.add_child(hdr_row)

	var title_lbl := Label.new()
	title_lbl.text = feat_title
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.clip_text = true
	if bold_font != null:
		title_lbl.add_theme_font_override("font", bold_font)
	hdr_row.add_child(title_lbl)

	var state_lbl := Label.new()
	if gate_passed:
		state_lbl.text = "Passed ✓"
		state_lbl.add_theme_color_override("font_color", _editor_color("success_color", Color(0.36, 0.85, 0.56)))
	elif all_ready:
		state_lbl.text = "Ready to Test"
		state_lbl.add_theme_color_override("font_color", _editor_color("accent_color", Color(0.45, 0.78, 0.98)))
	else:
		state_lbl.text = "Setup Needed"
		state_lbl.add_theme_color_override("font_color", _editor_color("warning_color", Color(0.96, 0.76, 0.36)))
	hdr_row.add_child(state_lbl)

	var goal_rtl := RichTextLabel.new()
	goal_rtl.bbcode_enabled = true
	goal_rtl.fit_content = true
	goal_rtl.scroll_active = false
	goal_rtl.selection_enabled = true
	goal_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if mono_font != null:
		goal_rtl.add_theme_font_override("mono_font", mono_font)
	goal_rtl.add_theme_color_override("default_color", _editor_color("font_color", Color(0.88, 0.90, 0.94)))
	goal_rtl.text = _markdown_to_bbcode(done_when)
	goal_vb.add_child(goal_rtl)

	var chips_flow := HFlowContainer.new()
	chips_flow.add_theme_constant_override("h_separation", _S(4))
	chips_flow.add_theme_constant_override("v_separation", _S(4))
	var chip_paths: Array[String] = []
	if not primary_scene.is_empty():
		chip_paths.append(primary_scene)
	for sp in script_paths:
		var sps := str(sp).strip_edges()
		if not sps.is_empty() and not (sps in chip_paths):
			chip_paths.append(sps)
	if not arena_scene.is_empty() and not (arena_scene in chip_paths):
		chip_paths.append(arena_scene)

	if not chip_paths.is_empty():
		goal_vb.add_child(chips_flow)
		for cp_res in chip_paths:
			var chip_btn := Button.new()
			chip_btn.flat = true
			chip_btn.theme_type_variation = &"FlatButton"
			chip_btn.text = cp_res.get_file()
			chip_btn.icon = _editor_icon("Script" if cp_res.ends_with(".gd") else "PackedScene", "File")
			chip_btn.tooltip_text = "Open %s in Godot" % cp_res
			chip_btn.add_theme_color_override("font_color", _editor_color("accent_color", Color(0.45, 0.76, 0.96)))
			chip_btn.pressed.connect(_on_open_res_path_pressed.bind(cp_res))
			chips_flow.add_child(chip_btn)

	# -----------------------------------------------------------------------
	# 2. 1-Click Feature Builder + Collapsible Blueprint Details
	# -----------------------------------------------------------------------
	var build_card := _create_native_card()
	var build_vb: VBoxContainer = build_card["vb"]

	if _building_feature:
		var busy_btn := Button.new()
		busy_btn.text = "Building Feature with Gemini 4 Hydrogen..."
		busy_btn.icon = _editor_icon("Tools")
		busy_btn.disabled = true
		build_vb.add_child(busy_btn)
	elif not all_ready:
		var build_btn := Button.new()
		build_btn.text = "Build Feature in Godot"
		build_btn.icon = _editor_icon("Add", "Tools")
		build_btn.tooltip_text = "Build scene nodes, properties, InputMap actions, signals, and complete GDScript in 1 click."
		build_btn.pressed.connect(_on_build_feature_pressed.bind(feat))
		build_vb.add_child(build_btn)
	else:
		var built_row := HBoxContainer.new()
		built_row.add_theme_constant_override("separation", _S(6))
		build_vb.add_child(built_row)

		var ok_icon := TextureRect.new()
		ok_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ok_icon.texture = _editor_icon("StatusSuccess")
		built_row.add_child(ok_icon)

		var built_lbl := Label.new()
		built_lbl.text = "Feature Built (%d/%d ready)" % [ready_cnt, maxi(total_cnt, 1)]
		built_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		built_lbl.add_theme_color_override("font_color", _editor_color("success_color", Color(0.36, 0.85, 0.56)))
		built_row.add_child(built_lbl)

		var rebuild_btn := Button.new()
		rebuild_btn.flat = true
		rebuild_btn.theme_type_variation = &"FlatButton"
		rebuild_btn.text = "Rebuild / Repair"
		rebuild_btn.icon = _editor_icon("Reload", "Tools")
		rebuild_btn.pressed.connect(_on_build_feature_pressed.bind(feat))
		built_row.add_child(rebuild_btn)

	var bp_toggle := Button.new()
	bp_toggle.flat = true
	bp_toggle.theme_type_variation = &"FlatButton"
	bp_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	bp_toggle.icon = _editor_icon("GuiTreeArrowDown" if _show_blueprint_details else "GuiTreeArrowRight", "Tools")
	bp_toggle.text = "Blueprint Details (%d/%d ready)" % [ready_cnt, total_cnt]
	bp_toggle.pressed.connect(func() -> void:
		_show_blueprint_details = not _show_blueprint_details
		_render_active_feature_workspace(feat)
	)
	build_vb.add_child(bp_toggle)

	if _show_blueprint_details:
		_blueprint_tree = Tree.new()
		_blueprint_tree.hide_root = true
		_blueprint_tree.custom_minimum_size = Vector2(0.0, float(_S(115)))
		build_vb.add_child(_blueprint_tree)
		var tree_root := _blueprint_tree.create_item()
		for item_raw in eval_info.get("items", []):
			if typeof(item_raw) != TYPE_DICTIONARY:
				continue
			var it: Dictionary = item_raw
			var tr := _blueprint_tree.create_item(tree_root)
			tr.set_text(0, str(it.get("label", "")))
			var it_ok: bool = bool(it.get("ok", false))
			tr.set_icon(0, _editor_icon("StatusSuccess" if it_ok else "StatusWarning", "Node"))
			tr.set_custom_color(0, _editor_color("font_color" if it_ok else "warning_color", Color(0.86, 0.90, 0.94)))

		if not script_paths.is_empty():
			if _selected_script_preview_path.is_empty() or not (_selected_script_preview_path in script_paths):
				_selected_script_preview_path = str(script_paths[0])

			var scr_hdr := HBoxContainer.new()
			scr_hdr.add_theme_constant_override("separation", _S(4))
			build_vb.add_child(scr_hdr)

			if script_paths.size() > 1:
				var scr_picker := OptionButton.new()
				scr_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				scr_picker.clip_text = true
				for idx in range(script_paths.size()):
					var sp_str := str(script_paths[idx])
					scr_picker.add_item(sp_str.get_file(), idx)
					if sp_str == _selected_script_preview_path:
						scr_picker.select(idx)
				scr_picker.item_selected.connect(func(sel_idx: int) -> void:
					if sel_idx >= 0 and sel_idx < script_paths.size():
						_selected_script_preview_path = str(script_paths[sel_idx])
						_render_active_feature_workspace(feat)
				)
				scr_hdr.add_child(scr_picker)
			else:
				var scr_lbl := Label.new()
				scr_lbl.text = _selected_script_preview_path
				scr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				scr_lbl.clip_text = true
				scr_hdr.add_child(scr_lbl)

			var open_scr_btn := Button.new()
			open_scr_btn.flat = true
			open_scr_btn.theme_type_variation = &"FlatButton"
			open_scr_btn.text = "Open in Script Editor"
			open_scr_btn.icon = _editor_icon("Script")
			open_scr_btn.pressed.connect(_on_open_res_path_pressed.bind(_selected_script_preview_path))
			scr_hdr.add_child(open_scr_btn)

			var preview_code := ""
			if FileAccess.file_exists(_selected_script_preview_path):
				var f := FileAccess.open(_selected_script_preview_path, FileAccess.READ)
				if f != null:
					preview_code = f.get_as_text()
					f.close()
			if preview_code.is_empty():
				preview_code = str(code_files.get(_selected_script_preview_path, "# Build Feature in Godot to generate %s" % _selected_script_preview_path.get_file()))

			var code_edit := CodeEdit.new()
			code_edit.editable = false
			code_edit.gutters_draw_line_numbers = true
			code_edit.custom_minimum_size = Vector2(0.0, float(_S(140)))
			code_edit.text = preview_code
			if mono_font != null:
				code_edit.add_theme_font_override("font", mono_font)
			build_vb.add_child(code_edit)

	# -----------------------------------------------------------------------
	# 3. Playtest in Arena (F6) + Live @export Feel Tuning
	# -----------------------------------------------------------------------
	var play_card := _create_native_card()
	var play_vb: VBoxContainer = play_card["vb"]

	var play_hdr := Label.new()
	play_hdr.text = "Playtest & Feel Tuning"
	if bold_font != null:
		play_hdr.add_theme_font_override("font", bold_font)
	play_vb.add_child(play_hdr)

	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", _S(6))
	play_vb.add_child(play_row)

	var arena_btn := Button.new()
	arena_btn.text = "Playtest in Arena (F6)"
	arena_btn.icon = _editor_icon("PlayScene", "Play")
	arena_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_btn.pressed.connect(_on_playtest_arena_pressed.bind(arena_scene, primary_scene))
	play_row.add_child(arena_btn)

	if not primary_scene.is_empty() and primary_scene != arena_scene:
		var feat_run_btn := Button.new()
		feat_run_btn.text = "Run Feature"
		feat_run_btn.icon = _editor_icon("PlayCustom", "Play")
		feat_run_btn.tooltip_text = "Run %s isolated" % primary_scene.get_file()
		feat_run_btn.pressed.connect(_on_run_scene_pressed.bind(primary_scene))
		play_row.add_child(feat_run_btn)

	var tuners: Array = _executor.call("extract_feature_export_tuners", script_paths) if _executor != null else []
	if not tuners.is_empty():
		var tune_sub := Label.new()
		tune_sub.text = "Live Feel Tuning (@export)"
		tune_sub.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.68, 0.72, 0.78)))
		play_vb.add_child(tune_sub)

		for t_raw in tuners:
			if typeof(t_raw) != TYPE_DICTIONARY:
				continue
			var t: Dictionary = t_raw
			var t_script: String = str(t.get("script_path", ""))
			var t_name: String = str(t.get("name", ""))
			var t_label: String = str(t.get("label", t_name))
			var t_type: String = str(t.get("type", "float"))
			var t_val: Variant = t.get("value", 0.0)

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", _S(6))
			play_vb.add_child(row)

			var lbl := Label.new()
			lbl.text = t_label
			lbl.tooltip_text = "%s :: @export var %s" % [t_script.get_file(), t_name]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = true
			row.add_child(lbl)

			if t_type == "bool":
				var cb := CheckBox.new()
				cb.button_pressed = bool(t_val)
				cb.toggled.connect(func(pressed: bool) -> void:
					_on_export_tuner_changed(t_script, t_name, pressed)
				)
				_active_tuner_controls.append(cb)
				row.add_child(cb)
			elif t_type == "int" or t_type == "float":
				var sb_ctrl := SpinBox.new()
				sb_ctrl.custom_minimum_size = Vector2(float(_S(92)), 0.0)
				sb_ctrl.allow_greater = true
				sb_ctrl.allow_lesser = true
				sb_ctrl.min_value = float(t.get("min", 0.0))
				sb_ctrl.max_value = float(t.get("max", 100.0))
				sb_ctrl.step = 1.0 if t_type == "int" else float(t.get("step", 0.1))
				sb_ctrl.value = float(t_val)
				sb_ctrl.value_changed.connect(func(nv: float) -> void:
					var typed_val: Variant = int(round(nv)) if t_type == "int" else nv
					_on_export_tuner_changed(t_script, t_name, typed_val)
				)
				_active_tuner_controls.append(sb_ctrl)
				row.add_child(sb_ctrl)
			elif t_type == "packed_scene":
				var ps_btn := Button.new()
				ps_btn.flat = true
				ps_btn.theme_type_variation = &"FlatButton"
				var ps_val := str(t_val)
				ps_btn.text = ps_val.get_file() if not ps_val.is_empty() else "Set Scene"
				ps_btn.icon = _editor_icon("PackedScene")
				ps_btn.pressed.connect(_on_open_res_path_pressed.bind(t_script))
				row.add_child(ps_btn)
	else:
		var tune_hint := Label.new()
		tune_hint.text = "Expose @export vars in your script to tune feel live here."
		tune_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tune_hint.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.66, 0.70, 0.76)))
		play_vb.add_child(tune_hint)

	# -----------------------------------------------------------------------
	# 4. Unified Agent Director (Direct Tweak + Real Scene & Script Fix)
	# -----------------------------------------------------------------------
	var agent_card := _create_native_card()
	var agent_vb: VBoxContainer = agent_card["vb"]

	var agent_hdr := Label.new()
	agent_hdr.text = "Agent Director · Tweak or Fix"
	if bold_font != null:
		agent_hdr.add_theme_font_override("font", bold_font)
	agent_vb.add_child(agent_hdr)

	var agent_sub := Label.new()
	agent_sub.text = "Request any tweak or Broken? Ask Agent to Fix — edits .gd + .tscn directly."
	agent_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	agent_sub.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.68, 0.72, 0.78)))
	agent_vb.add_child(agent_sub)

	if not _last_agent_summary.is_empty():
		var res_panel := PanelContainer.new()
		var res_sb: StyleBox = _editor_stylebox("panel", "Tree")
		if res_sb != null:
			res_panel.add_theme_stylebox_override("panel", res_sb)
		agent_vb.add_child(res_panel)

		var res_vb := VBoxContainer.new()
		res_vb.add_theme_constant_override("separation", _S(4))
		res_panel.add_child(res_vb)

		var res_hb := HBoxContainer.new()
		res_hb.add_theme_constant_override("separation", _S(4))
		res_vb.add_child(res_hb)

		var res_icon := TextureRect.new()
		res_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		res_icon.texture = _editor_icon("StatusSuccess")
		res_hb.add_child(res_icon)

		var res_lbl := Label.new()
		res_lbl.text = _last_agent_summary
		res_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		res_lbl.add_theme_color_override("font_color", _editor_color("success_color", Color(0.36, 0.85, 0.56)))
		res_hb.add_child(res_lbl)

		var dismiss_btn := Button.new()
		dismiss_btn.flat = true
		dismiss_btn.theme_type_variation = &"FlatButton"
		dismiss_btn.icon = _editor_icon("Close")
		if dismiss_btn.icon == null:
			dismiss_btn.text = "x"
		dismiss_btn.pressed.connect(func() -> void:
			_last_agent_summary = ""
			_last_agent_warnings = PackedStringArray()
			_render_active_feature_workspace(feat)
		)
		res_hb.add_child(dismiss_btn)

		for w in _last_agent_warnings:
			var w_lbl := Label.new()
			w_lbl.text = "Warning: %s" % w
			w_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			w_lbl.add_theme_color_override("font_color", _editor_color("warning_color", Color(0.96, 0.76, 0.36)))
			res_vb.add_child(w_lbl)

	_fix_input = LineEdit.new()
	_fix_input.placeholder_text = "Make lunge faster, spawn 5 crabs, or paste Godot error..."
	_fix_input.text = _fix_draft_text
	_fix_input.text_changed.connect(func(txt: String) -> void: _fix_draft_text = txt)
	_fix_input.text_submitted.connect(_on_fix_input_submitted.bind(feat_id, cp_id))
	agent_vb.add_child(_fix_input)

	var apply_btn := Button.new()
	apply_btn.text = "Applying Agent Changes..." if _diagnosing_fix else "Apply to Scene & Script"
	apply_btn.icon = _editor_icon("Tools")
	apply_btn.disabled = _diagnosing_fix
	apply_btn.pressed.connect(_on_direct_agent_pressed.bind(feat_id, cp_id))
	agent_vb.add_child(apply_btn)

	# Sticky Footer CTA
	_footer_box.visible = true
	_primary_cta_btn.disabled = _building_feature
	if not all_ready:
		_primary_cta_btn.text = "Build Feature in Godot"
		_primary_cta_btn.icon = _editor_icon("Add", "Tools")
	else:
		_primary_cta_btn.text = "Playtest Passed — Next Feature"
		_primary_cta_btn.icon = _editor_icon("StatusSuccess" if gate_passed else "Forward")


# ---------------------------------------------------------------------------
# Feature Actions, Playtest, Export Tuners & Agent Director
# ---------------------------------------------------------------------------

func _on_build_feature_pressed(feat: Dictionary) -> void:
	if _executor == null or _building_feature:
		return
	var feat_id: String = str(feat.get("id", ""))
	var cp_id: String = str(feat.get("checkpointId", ""))
	var code_files: Dictionary = _payload.get("codeFiles", {}) if typeof(_payload.get("codeFiles", null)) == TYPE_DICTIONARY else {}
	var arena_scene: String = str(_payload.get("arenaScenePath", "")).strip_edges()

	var local_res: Dictionary = _executor.call("build_feature_local", feat, editor_interface, undo_redo, code_files, arena_scene)
	if editor_interface != null and editor_interface.get_resource_filesystem() != null:
		editor_interface.get_resource_filesystem().scan()

	if _sync == null or not _sync.has_link_token():
		var local_sum := str(local_res.get("summary", "Built local feature scaffold."))
		_last_agent_summary = local_sum
		_set_status(local_sum, not bool(local_res.get("ok", true)))
		_render_active_feature_workspace(feat)
		return

	var paths: Dictionary = _executor.call("resolve_feature_paths", feat, code_files, arena_scene)
	var primary_scene: String = str(paths.get("primary_scene", ""))
	var extra_scenes := PackedStringArray()
	if not primary_scene.is_empty():
		extra_scenes.append(primary_scene)
	if not arena_scene.is_empty() and not (arena_scene in extra_scenes):
		extra_scenes.append(arena_scene)

	var scene_snap: Dictionary = _executor.call("capture_rich_scene_snapshot", editor_interface, extra_scenes)
	var live_scripts: Dictionary = _executor.call("read_live_scripts_for_feature", feat, code_files, arena_scene)
	_building_feature = true
	_set_status("Building %s with Gemini 4 Hydrogen..." % str(feat.get("title", "Feature")), false)
	_render_active_feature_workspace(feat)
	_sync.build_feature(feat_id, cp_id, scene_snap, live_scripts, arena_scene, primary_scene)


func _on_fix_input_submitted(_text: String, feat_id: String, cp_id: String) -> void:
	_on_direct_agent_pressed(feat_id, cp_id)


func _on_direct_agent_pressed(feat_id: String, cp_id: String) -> void:
	if _sync == null or _diagnosing_fix:
		return
	var prompt_txt: String = (_fix_input.text if _fix_input != null else _fix_draft_text).strip_edges()
	if prompt_txt.is_empty():
		_set_status("Type a gameplay tweak or paste a Godot error first.", true)
		return
	var feat: Dictionary = _get_active_feature()
	var code_files: Dictionary = _payload.get("codeFiles", {}) if typeof(_payload.get("codeFiles", null)) == TYPE_DICTIONARY else {}
	var arena_scene: String = str(_payload.get("arenaScenePath", "")).strip_edges()
	var paths: Dictionary = _executor.call("resolve_feature_paths", feat, code_files, arena_scene) if _executor != null else {}
	var primary_scene: String = str(paths.get("primary_scene", feat.get("primaryAsset", ""))).strip_edges()

	var extra_scenes := PackedStringArray()
	if not primary_scene.is_empty():
		extra_scenes.append(primary_scene)
	if not arena_scene.is_empty() and not (arena_scene in extra_scenes):
		extra_scenes.append(arena_scene)

	var scene_snap: Dictionary = _executor.call("capture_rich_scene_snapshot", editor_interface, extra_scenes) if _executor != null else {}
	var live_scripts: Dictionary = _executor.call("read_live_scripts_for_feature", feat, code_files, arena_scene) if _executor != null else {}

	_diagnosing_fix = true
	_set_status("Agent Director updating Scene & GDScript...", false)
	if not feat.is_empty():
		_render_active_feature_workspace(feat)
	_sync.direct_agent(feat_id, cp_id, prompt_txt, scene_snap, live_scripts, arena_scene, primary_scene, prompt_txt)


func _on_agent_bundle_received(bundle: Dictionary, _payload_data: Dictionary) -> void:
	_building_feature = false
	_diagnosing_fix = false
	if _executor == null:
		return
	var apply_res: Dictionary = _executor.call("apply_agent_bundle", editor_interface, undo_redo, bundle)
	if editor_interface != null and editor_interface.get_resource_filesystem() != null:
		editor_interface.get_resource_filesystem().scan()
	var summary := str(apply_res.get("summary", bundle.get("summary", "Applied scene & script updates.")))
	_last_agent_summary = summary
	_last_agent_warnings = apply_res.get("warnings", PackedStringArray())
	if bool(apply_res.get("ok", false)):
		_fix_draft_text = ""
	_set_status(summary, not bool(apply_res.get("ok", true)))
	_refresh_view()


func _on_export_tuner_changed(script_path: String, prop_name: String, new_val: Variant) -> void:
	if _executor == null:
		return
	var res: Dictionary = _executor.call("apply_export_tuner_value", script_path, prop_name, new_val, editor_interface, undo_redo)
	if bool(res.get("ok", false)):
		_set_status("Updated %s = %s" % [prop_name, str(new_val)], false)
	else:
		_set_status(str(res.get("error", "Could not update @export var %s" % prop_name)), true)


func _on_playtest_arena_pressed(arena_scene: String, primary_scene: String) -> void:
	if editor_interface == null:
		return
	if not arena_scene.is_empty() and arena_scene.ends_with(".tscn") and FileAccess.file_exists(arena_scene):
		editor_interface.play_custom_scene(arena_scene)
		return
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", "")).strip_edges()
	if not main_scene.is_empty() and main_scene.ends_with(".tscn") and FileAccess.file_exists(main_scene):
		editor_interface.play_custom_scene(main_scene)
		return
	if not primary_scene.is_empty() and primary_scene.ends_with(".tscn") and FileAccess.file_exists(primary_scene):
		editor_interface.play_custom_scene(primary_scene)
		return
	editor_interface.play_current_scene()


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


func _on_feature_selected(idx: int) -> void:
	var epic_raw: Variant = _payload.get("activeEpic", null)
	if typeof(epic_raw) != TYPE_DICTIONARY:
		return
	var features: Array = (epic_raw as Dictionary).get("features", [])
	if idx >= 0 and idx < features.size():
		var f: Dictionary = features[idx]
		_selected_feature_id = str(f.get("id", ""))
		_selected_script_preview_path = ""
		_last_agent_summary = ""
		_last_agent_warnings = PackedStringArray()
		_render_active_feature_workspace(f)


func _on_primary_cta_pressed() -> void:
	var feat: Dictionary = _get_active_feature()
	if feat.is_empty():
		return
	var code_files: Dictionary = _payload.get("codeFiles", {}) if typeof(_payload.get("codeFiles", null)) == TYPE_DICTIONARY else {}
	var arena_scene: String = str(_payload.get("arenaScenePath", "")).strip_edges()
	var eval_info: Dictionary = _executor.call("evaluate_feature", feat, editor_interface, code_files, arena_scene) if _executor != null else { "all_ready": false }
	if not bool(eval_info.get("all_ready", false)):
		_on_build_feature_pressed(feat)
		return

	if _sync == null:
		return
	var feat_id: String = str(feat.get("id", ""))
	var cp_id: String = str(feat.get("checkpointId", ""))
	feat["isPlaytestPassed"] = true
	feat["isCompleted"] = true

	var epic_raw: Variant = _payload.get("activeEpic", null)
	if typeof(epic_raw) == TYPE_DICTIONARY:
		var features: Array = (epic_raw as Dictionary).get("features", [])
		for f_raw in features:
			if typeof(f_raw) == TYPE_DICTIONARY:
				var fd: Dictionary = f_raw
				if str(fd.get("id", "")) != feat_id and not bool(fd.get("isCompleted", false)):
					_selected_feature_id = str(fd.get("id", ""))
					break

	_set_status("Playtest passed — advancing to next feature...", false)
	_sync.set_playtest_passed(feat_id, cp_id, true)


func _on_epic_updated(payload: Dictionary) -> void:
	_payload = payload
	_building_feature = false
	_diagnosing_fix = false
	if _last_agent_summary.is_empty():
		_set_status("Synced", false)
	_refresh_view()


func _on_sync_failed(message: String) -> void:
	_building_feature = false
	_diagnosing_fix = false
	_set_status(message, true)
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty() and _workspace_panel.visible:
		_render_active_feature_workspace(feat)


func _on_busy_changed(is_busy: bool) -> void:
	if _sync_btn != null:
		_sync_btn.disabled = is_busy
	if is_busy and _status_label != null and not _diagnosing_fix and not _building_feature:
		_status_label.text = "Syncing..."
		_status_label.add_theme_color_override("font_color", _editor_color("accent_color", Color(0.45, 0.78, 0.98)))


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
# Settings, Link Token & 1-Click GitHub Plugin Self-Update
# ---------------------------------------------------------------------------

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
	_last_agent_summary = ""
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
	_last_agent_summary = ""
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
