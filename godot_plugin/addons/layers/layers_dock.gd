@tool
extends VBoxContainer

const SYNC_CLIENT_SCRIPT_PATH := "res://addons/layers/layers_sync_client.gd"
const STEP_EXECUTOR_SCRIPT_PATH := "res://addons/layers/layers_step_executor.gd"
const DEFAULT_WEB_STUDIO_URL := "https://henrycgithub.github.io/LAYERS-Agentic/"


class _LayersEditorLogger extends Logger:
	var _mutex := Mutex.new()
	var _entries: Array[Dictionary] = []

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type == 1:
			return
		var raw_msg := rationale if not rationale.strip_edges().is_empty() else code
		var combined := ("%s (%s:%d in %s)" % [raw_msg.strip_edges(), file, line, function]).strip_edges()
		var lower := combined.to_lower()
		if (
			"addons/layers/" in lower or
			"gdscript://" in lower or
			"progress_dialog.cpp" in lower or
			"editoricons" in lower or
			"vulkan" in lower or
			"orphan string" in lower or
			raw_msg.strip_edges().is_empty()
		):
			return
		var prefix := "SCRIPT ERROR: " if error_type == 2 else "ERROR: "
		var formatted := (prefix + combined).left(340)
		var now_unix := Time.get_unix_time_from_system()
		_mutex.lock()
		if _entries.size() >= 24:
			_entries.pop_front()
		_entries.append({ "ts": now_unix, "msg": formatted })
		_mutex.unlock()

	func snapshot_errors(since_unix: float = 0.0) -> Array[String]:
		var out: Array[String] = []
		_mutex.lock()
		for item in _entries:
			var ts: float = float(item.get("ts", 0.0))
			if since_unix <= 0.0 or ts >= since_unix:
				out.append(str(item.get("msg", "")))
		_mutex.unlock()
		return out

	func clear() -> void:
		_mutex.lock()
		_entries.clear()
		_mutex.unlock()

	func entry_count() -> int:
		_mutex.lock()
		var n: int = _entries.size()
		_mutex.unlock()
		return n


var editor_interface: EditorInterface

var _sync: Node
var _executor: RefCounted
var _payload: Dictionary = {}
var _selected_feature_id: String = ""
var _last_synced_web_selected_id: String = ""
var _pull_sync_pending: bool = false
var _fix_draft_text: String = ""
var _issue_composer_expanded: bool = false
var _show_token_editor: bool = false
var _available_remote_version: String = ""
var _updating_plugin: bool = false
var _checking_plugin_update: bool = false
var _last_error_clear_unix: float = 0.0
var _live_refresh_timer: Timer
var _playtest_watch_timer: Timer
var _post_playtest_log_timer: Timer
var _was_playing_scene: bool = false
var _editor_logger: _LayersEditorLogger
var _ignored_error_signatures: Dictionary = {}
var _last_detected_error_count: int = 0
var _last_seen_logger_count: int = 0

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
var _fix_input: TextEdit


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
		if _executor != null:
			_executor.call("ensure_project_file_logging")

	if ClassDB.class_exists("Logger") and OS.has_method("add_logger"):
		_editor_logger = _LayersEditorLogger.new()
		OS.add_logger(_editor_logger)

	_live_refresh_timer = Timer.new()
	_live_refresh_timer.one_shot = true
	_live_refresh_timer.wait_time = 0.28
	_live_refresh_timer.timeout.connect(_on_live_refresh_timeout)
	add_child(_live_refresh_timer)

	_playtest_watch_timer = Timer.new()
	_playtest_watch_timer.one_shot = false
	_playtest_watch_timer.wait_time = 0.5
	_playtest_watch_timer.timeout.connect(_on_playtest_watch_tick)
	add_child(_playtest_watch_timer)
	_playtest_watch_timer.start()

	_post_playtest_log_timer = Timer.new()
	_post_playtest_log_timer.one_shot = true
	_post_playtest_log_timer.wait_time = 0.6
	_post_playtest_log_timer.timeout.connect(_on_post_playtest_log_timeout)
	add_child(_post_playtest_log_timer)

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
			_last_synced_web_selected_id = str(cached.get("webSelectedFeatureId", "")).strip_edges()
		_pull_sync_pending = true
		_refresh_view()
		_sync.fetch_active_epic()
	else:
		_show_token_editor = true
		_refresh_view()

	_sync.check_for_plugin_update(true)


func _exit_tree() -> void:
	if _editor_logger != null and OS.has_method("remove_logger"):
		OS.remove_logger(_editor_logger)
		_editor_logger = null
	_disconnect_live_tree_signals()


func refresh_from_focus() -> void:
	if _sync != null and _sync.has_link_token() and not _show_token_editor:
		_pull_sync_pending = true
		_sync.fetch_active_epic()
	notify_editor_state_changed()


func on_editor_scene_changed(_scene_root: Node = null) -> void:
	if _executor != null:
		_executor.call("invalidate_eval_cache")
	notify_editor_state_changed()


func on_editor_scene_saved(_filepath: String = "") -> void:
	if _executor != null:
		_executor.call("invalidate_eval_cache")
	notify_editor_state_changed()


func on_editor_resource_saved(_resource: Resource = null) -> void:
	if _executor != null:
		_executor.call("invalidate_eval_cache")
	notify_editor_state_changed()


func notify_editor_state_changed() -> void:
	if not is_inside_tree() or _live_refresh_timer == null:
		return
	if _show_token_editor or _workspace_panel == null or not _workspace_panel.visible:
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
		if _executor != null:
			_executor.call("invalidate_eval_cache")
		notify_editor_state_changed()


func _on_live_refresh_timeout() -> void:
	if _show_token_editor or _workspace_panel == null or not _workspace_panel.visible:
		return
	if _fix_input != null and _fix_input.has_focus():
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
	_version_label.text = "Plugin v%s" % (_sync.get_local_plugin_version() if _sync != null else "3.0.7")
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_label.clip_text = true
	_version_label.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.68, 0.72, 0.78)))
	ver_row.add_child(_version_label)

	_check_update_btn = Button.new()
	_check_update_btn.text = "Check for Plugin Update"
	_check_update_btn.icon = _editor_icon("Reload")
	_check_update_btn.pressed.connect(_on_check_plugin_update_pressed)
	ver_row.add_child(_check_update_btn)

	# 3. Connected Native Feature Spec, Playtest & Sync Workspace
	_workspace_panel = VBoxContainer.new()
	_workspace_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_panel.add_theme_constant_override("separation", _S(6))
	add_child(_workspace_panel)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", _S(4))
	_workspace_panel.add_child(top_bar)

	var header_vb := VBoxContainer.new()
	header_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_vb.add_theme_constant_override("separation", _S(1))
	top_bar.add_child(header_vb)

	_meta_label = Label.new()
	_meta_label.text = "v0.1 · E01"
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

	_feature_picker = OptionButton.new()
	_feature_picker.clip_text = true
	_feature_picker.item_selected.connect(_on_feature_selected)
	_workspace_panel.add_child(_feature_picker)

	_workspace_panel.add_child(HSeparator.new())

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

	_step_scroll = ScrollContainer.new()
	_step_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_workspace_panel.add_child(_step_scroll)

	_body_container = VBoxContainer.new()
	_body_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_container.add_theme_constant_override("separation", _S(8))
	_step_scroll.add_child(_body_container)

	_footer_box = VBoxContainer.new()
	_footer_box.add_theme_constant_override("separation", _S(4))
	_workspace_panel.add_child(_footer_box)
	_footer_box.add_child(HSeparator.new())

	_primary_cta_btn = Button.new()
	_primary_cta_btn.text = "Playtest Passed — Next Feature"
	_primary_cta_btn.pressed.connect(_on_primary_cta_pressed)
	_footer_box.add_child(_primary_cta_btn)

	_status_label = Label.new()
	_status_label.text = "Ready"
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


func _format_epic_meta_line(
	ver: String,
	epic_code: String,
	pos: int,
	total: int,
	passed_count: int = -1,
	feat_total: int = 0
) -> String:
	var epic_part: String = ("%s (%d/%d active)" % [epic_code, maxi(pos, 1), total]) if total > 1 else epic_code
	if passed_count >= 0 and feat_total > 0:
		return "%s · %s · %d/%d Passed" % [ver, epic_part, passed_count, feat_total]
	return "%s · %s" % [ver, epic_part]


func _refresh_view() -> void:
	if _connect_panel == null or _workspace_panel == null:
		return
	var linked: bool = _sync != null and _sync.has_link_token()
	_connect_panel.visible = (not linked) or _show_token_editor
	_workspace_panel.visible = linked and (not _show_token_editor)
	if _cancel_token_btn != null:
		_cancel_token_btn.visible = linked
	if _disconnect_btn != null:
		_disconnect_btn.visible = linked
	if _version_label != null and _sync != null:
		_version_label.text = "Plugin v%s" % _sync.get_local_plugin_version()
	_refresh_update_banner()

	if _connect_panel.visible:
		if _token_input != null:
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
		var epic_dict_tmp: Dictionary = epic_raw as Dictionary
		if epic_dict_tmp.has("code"):
			epic_code = str(epic_dict_tmp.get("code", "E01"))
	_meta_label.text = _format_epic_meta_line(ver, epic_code, pos, total)

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

	var epic: Dictionary = epic_raw as Dictionary
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

	var payload_sel_id: String = str(_payload.get("selectedFeatureId", "")).strip_edges()
	var chosen_idx: int = -1
	var payload_sel_idx: int = -1
	var first_incomplete_idx: int = -1
	var passed_count: int = 0
	for i in range(features.size()):
		var f: Dictionary = features[i]
		var f_id: String = str(f.get("id", ""))
		var f_title: String = str(f.get("title", "Feature"))
		var f_done: bool = bool(f.get("isCompleted", false)) or bool(f.get("isPlaytestPassed", false))
		var f_issues: Variant = f.get("openIssues", [])
		var has_issues: bool = typeof(f_issues) == TYPE_ARRAY and not (f_issues as Array).is_empty()
		if f_done:
			passed_count += 1
		_feature_picker.add_item(f_title, i)
		var f_icon: Texture2D = _editor_icon(
			"StatusSuccess" if f_done else ("StatusWarning" if has_issues else "PlayScene"),
			"Node"
		)
		if f_icon != null:
			_feature_picker.set_item_icon(i, f_icon)
		if f_id == _selected_feature_id:
			chosen_idx = i
		if not payload_sel_id.is_empty() and f_id == payload_sel_id:
			payload_sel_idx = i
		if first_incomplete_idx == -1 and not f_done:
			first_incomplete_idx = i

	_meta_label.text = _format_epic_meta_line(ver, epic_code, pos, total, passed_count, features.size())

	if chosen_idx == -1:
		if payload_sel_idx != -1:
			chosen_idx = payload_sel_idx
		else:
			chosen_idx = first_incomplete_idx if first_incomplete_idx != -1 else 0
	_feature_picker.select(chosen_idx)
	var active_feat: Dictionary = features[chosen_idx]
	_selected_feature_id = str(active_feat.get("id", ""))
	_render_active_feature_workspace(active_feat)


func _get_feature_by_id(feat_id: String) -> Dictionary:
	if feat_id.is_empty():
		return {}
	var epic_raw: Variant = _payload.get("activeEpic", null)
	if typeof(epic_raw) != TYPE_DICTIONARY:
		return {}
	for f_raw in (epic_raw as Dictionary).get("features", []):
		if typeof(f_raw) == TYPE_DICTIONARY and str((f_raw as Dictionary).get("id", "")) == feat_id:
			return f_raw as Dictionary
	return {}


func _get_active_feature() -> Dictionary:
	var by_id := _get_feature_by_id(_selected_feature_id)
	if not by_id.is_empty():
		return by_id
	var epic_raw: Variant = _payload.get("activeEpic", null)
	if typeof(epic_raw) != TYPE_DICTIONARY:
		return {}
	var features: Array = (epic_raw as Dictionary).get("features", [])
	return (features[0] as Dictionary) if not features.is_empty() and typeof(features[0]) == TYPE_DICTIONARY else {}


func _clear_body() -> void:
	_fix_input = null
	if _body_container == null:
		return
	for child in _body_container.get_children():
		_body_container.remove_child(child)
		child.queue_free()


func _create_native_card() -> Dictionary:
	var panel := PanelContainer.new()
	var sb: StyleBox = _editor_stylebox("panel", "Tree")
	if sb != null:
		panel.add_theme_stylebox_override("panel", sb)
	if _body_container != null:
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


func _collect_active_playtest_errors() -> Array:
	_last_seen_logger_count = _editor_logger.entry_count() if _editor_logger != null else 0
	if _executor == null:
		return []
	var base_ctrl: Node = editor_interface.get_base_control() if editor_interface != null else null
	var logger_errs: Array = _editor_logger.snapshot_errors(_last_error_clear_unix) if _editor_logger != null else []
	return _executor.call(
		"read_editor_and_playtest_errors",
		base_ctrl,
		logger_errs,
		_ignored_error_signatures,
		_last_error_clear_unix,
		3,
		_editor_icon("Warning")
	)


func _render_active_feature_workspace(feat: Dictionary) -> void:
	if _body_container == null:
		return
	_clear_body()

	var ver: String = str(_payload.get("releaseVersion", "v0.1")).strip_edges()
	var feat_title: String = str(feat.get("title", "Feature")).strip_edges()
	var spec_info: Dictionary = _executor.call("resolve_clean_feature_spec", feat, ver) if _executor != null else {
		"goal": str(feat.get("goal", "")).strip_edges(),
		"scope_items": feat.get("coveredScope", []),
		"scope_header": "In Scope",
		"done_when": str(feat.get("doneWhen", "Press F6 and verify %s works with 0 console errors." % (feat_title if not feat_title.is_empty() else "this feature"))).strip_edges(),
	}
	var feat_goal: String = str(spec_info.get("goal", "")).strip_edges()
	var scope_raw: Variant = spec_info.get("scope_items", PackedStringArray())
	var scope_items := PackedStringArray()
	if typeof(scope_raw) == TYPE_PACKED_STRING_ARRAY or typeof(scope_raw) == TYPE_ARRAY:
		for sr in scope_raw:
			var s_txt := str(sr).strip_edges()
			if not s_txt.is_empty():
				scope_items.append(s_txt)
	var scope_header: String = str(spec_info.get("scope_header", "In Scope")).strip_edges()
	var done_when: String = str(spec_info.get("done_when", "Press F6 and verify this feature works with 0 console errors.")).strip_edges()
	var gate_passed: bool = bool(feat.get("isPlaytestPassed", false)) or bool(feat.get("isCompleted", false))

	var raw_issues: Variant = feat.get("openIssues", [])
	var open_issues: Array = raw_issues if typeof(raw_issues) == TYPE_ARRAY else []

	var raw_guards: Variant = feat.get("edgeCases", [])
	var guard_items: Array = raw_guards if typeof(raw_guards) == TYPE_ARRAY else []
	var checked_guards: int = 0
	for g_raw in guard_items:
		if typeof(g_raw) == TYPE_DICTIONARY and bool((g_raw as Dictionary).get("signedOff", false)):
			checked_guards += 1
	var live_pct: int = _recompute_feature_progress(feat)

	var arena_scene: String = str(_payload.get("arenaScenePath", "")).strip_edges()
	var eval_info: Dictionary = _executor.call("evaluate_feature", feat, editor_interface, arena_scene) if _executor != null else {
		"primary_scene": str(feat.get("primaryAsset", "")), "arena_scene": arena_scene, "script_paths": feat.get("scriptPaths", [])
	}
	var primary_scene: String = str(eval_info.get("primary_scene", feat.get("primaryAsset", ""))).strip_edges()

	var bold_font: Font = _editor_font("bold")
	var mono_font: Font = _editor_font("source")

	# -----------------------------------------------------------------------
	# 1. Feature Spec & Playtest Card
	# -----------------------------------------------------------------------
	var brief_card := _create_native_card()
	var brief_vb: VBoxContainer = brief_card["vb"]

	var hdr_row := HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", _S(4))
	brief_vb.add_child(hdr_row)

	var state_lbl := Label.new()
	state_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_lbl.clip_text = true
	if bold_font != null:
		state_lbl.add_theme_font_override("font", bold_font)
	if gate_passed:
		state_lbl.text = "Passed ✓"
		state_lbl.add_theme_color_override("font_color", _editor_color("success_color", Color(0.36, 0.85, 0.56)))
	elif not open_issues.is_empty():
		state_lbl.text = "Issues (%d)" % open_issues.size()
		state_lbl.add_theme_color_override("font_color", _editor_color("warning_color", Color(0.96, 0.76, 0.36)))
	elif live_pct > 0:
		state_lbl.text = "In Progress · %d%%" % live_pct
		state_lbl.add_theme_color_override("font_color", _editor_color("accent_color", Color(0.45, 0.78, 0.98)))
	else:
		state_lbl.text = "Queued"
		state_lbl.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.64, 0.68, 0.76)))
	hdr_row.add_child(state_lbl)

	var copy_ctx_btn := Button.new()
	copy_ctx_btn.flat = true
	copy_ctx_btn.theme_type_variation = &"FlatButton"
	copy_ctx_btn.text = "Copy Context"
	copy_ctx_btn.icon = _editor_icon("ActionCopy", "Copy")
	copy_ctx_btn.tooltip_text = "Copy active feature spec, scene trees, scripts, InputMap & errors as Markdown"
	copy_ctx_btn.pressed.connect(_on_copy_context_pressed.bind(feat))
	hdr_row.add_child(copy_ctx_btn)

	if gate_passed:
		var reopen_btn := Button.new()
		reopen_btn.flat = true
		reopen_btn.theme_type_variation = &"FlatButton"
		reopen_btn.text = "Reopen Gate"
		reopen_btn.icon = _editor_icon("Reload", "UndoRedo")
		reopen_btn.tooltip_text = "Mark this feature unpassed so you can iterate and re-verify it"
		reopen_btn.pressed.connect(_on_reopen_gate_pressed.bind(feat))
		hdr_row.add_child(reopen_btn)

	if not feat_goal.is_empty() and feat_goal != feat_title:
		var goal_lbl := Label.new()
		goal_lbl.text = feat_goal
		goal_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal_lbl.add_theme_color_override("font_color", _editor_color("font_color", Color(0.90, 0.92, 0.96)))
		brief_vb.add_child(goal_lbl)

	if not scope_items.is_empty():
		var scope_hdr := Label.new()
		scope_hdr.text = scope_header if not scope_header.is_empty() else "In Scope"
		scope_hdr.add_theme_color_override("font_color", _editor_color("font_color", Color(0.86, 0.89, 0.94)))
		if bold_font != null:
			scope_hdr.add_theme_font_override("font", bold_font)
		brief_vb.add_child(scope_hdr)

		var scope_box := VBoxContainer.new()
		scope_box.add_theme_constant_override("separation", _S(2))
		brief_vb.add_child(scope_box)
		var scope_cap: int = mini(scope_items.size(), 6)
		for idx in range(scope_cap):
			var scope_txt: String = str(scope_items[idx]).strip_edges()
			if scope_txt.is_empty():
				continue
			var s_lbl := Label.new()
			s_lbl.text = "•  %s" % scope_txt
			s_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			s_lbl.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.72, 0.76, 0.82)))
			scope_box.add_child(s_lbl)

	var raw_tuning: Variant = feat.get("tuningParams", [])
	var tuning_items: Array = raw_tuning if typeof(raw_tuning) == TYPE_ARRAY else []
	if not tuning_items.is_empty():
		var tuning_hdr := Label.new()
		tuning_hdr.text = "Tuning Variables"
		tuning_hdr.add_theme_color_override("font_color", _editor_color("accent_color", Color(0.56, 0.78, 0.98)))
		if bold_font != null:
			tuning_hdr.add_theme_font_override("font", bold_font)
		brief_vb.add_child(tuning_hdr)

		var tuning_box := VBoxContainer.new()
		tuning_box.add_theme_constant_override("separation", _S(2))
		brief_vb.add_child(tuning_box)
		var tuning_cap: int = mini(tuning_items.size(), 8)
		for idx in range(tuning_cap):
			var tuning_txt: String = str(tuning_items[idx]).strip_edges()
			if tuning_txt.is_empty():
				continue
			var t_lbl := Label.new()
			t_lbl.text = "•  %s" % tuning_txt
			t_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if mono_font != null:
				t_lbl.add_theme_font_override("font", mono_font)
			t_lbl.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.76, 0.82, 0.88)))
			tuning_box.add_child(t_lbl)

	if not guard_items.is_empty():
		var guards_hdr := Label.new()
		guards_hdr.text = "Playtest Guards (%d/%d)" % [checked_guards, guard_items.size()]
		guards_hdr.add_theme_color_override("font_color", _editor_color("warning_color", Color(0.96, 0.76, 0.36)))
		if bold_font != null:
			guards_hdr.add_theme_font_override("font", bold_font)
		brief_vb.add_child(guards_hdr)

		var guards_box := VBoxContainer.new()
		guards_box.add_theme_constant_override("separation", _S(2))
		brief_vb.add_child(guards_box)

		for g_i in range(guard_items.size()):
			var g_entry: Variant = guard_items[g_i]
			var g_idx: int = g_i
			var raw_guard_txt: String = ""
			var disp_guard_txt: String = ""
			var is_signed: bool = false
			if typeof(g_entry) == TYPE_DICTIONARY:
				var gd: Dictionary = g_entry as Dictionary
				g_idx = int(gd.get("index", g_i))
				raw_guard_txt = str(gd.get("rawText", gd.get("text", ""))).strip_edges()
				disp_guard_txt = str(gd.get("text", raw_guard_txt)).strip_edges()
				is_signed = bool(gd.get("signedOff", false))
			else:
				raw_guard_txt = str(g_entry).strip_edges()
				disp_guard_txt = raw_guard_txt
			if disp_guard_txt.is_empty():
				continue
			var cb := CheckBox.new()
			cb.text = disp_guard_txt
			cb.button_pressed = is_signed
			cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cb.toggled.connect(_on_guard_toggled.bind(feat, g_idx, raw_guard_txt))
			guards_box.add_child(cb)

	var done_rtl := RichTextLabel.new()
	done_rtl.bbcode_enabled = true
	done_rtl.fit_content = true
	done_rtl.scroll_active = false
	done_rtl.selection_enabled = true
	done_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bold_font != null:
		done_rtl.add_theme_font_override("bold_font", bold_font)
	if mono_font != null:
		done_rtl.add_theme_font_override("mono_font", mono_font)
	done_rtl.add_theme_color_override("default_color", _editor_color("font_color", Color(0.88, 0.90, 0.94)))
	done_rtl.text = "[b]Done When:[/b] " + _markdown_to_bbcode(done_when)
	brief_vb.add_child(done_rtl)

	var scenes_to_open := PackedStringArray()
	if not primary_scene.is_empty() and primary_scene.ends_with(".tscn") and FileAccess.file_exists(primary_scene):
		scenes_to_open.append(primary_scene)
	if not arena_scene.is_empty() and arena_scene.ends_with(".tscn") and FileAccess.file_exists(arena_scene) and not (arena_scene in scenes_to_open):
		scenes_to_open.append(arena_scene)

	var scripts_to_open := PackedStringArray()
	var raw_script_paths: Variant = eval_info.get("script_paths", feat.get("scriptPaths", []))
	if typeof(raw_script_paths) == TYPE_ARRAY or typeof(raw_script_paths) == TYPE_PACKED_STRING_ARRAY:
		for sp_raw in raw_script_paths:
			var sp_cand := str(sp_raw).strip_edges()
			if sp_cand.begins_with("res://") and sp_cand.ends_with(".gd") and FileAccess.file_exists(sp_cand) and not (sp_cand in scripts_to_open):
				scripts_to_open.append(sp_cand)

	var known_jump_paths := PackedStringArray()
	for ks in scenes_to_open:
		if not (ks in known_jump_paths):
			known_jump_paths.append(ks)
	for kg in scripts_to_open:
		if not (kg in known_jump_paths):
			known_jump_paths.append(kg)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", _S(6))
	brief_vb.add_child(action_row)

	var play_btn := Button.new()
	var is_playing := _is_editor_playing()
	play_btn.text = "Stop Playtest (F8)" if is_playing else "Playtest Scene (F6)"
	play_btn.icon = _editor_icon("Stop" if is_playing else "PlayScene", "Play")
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_btn.pressed.connect(_on_playtest_arena_pressed.bind(arena_scene, primary_scene))
	action_row.add_child(play_btn)

	_maybe_add_open_scene_button(action_row, scenes_to_open, arena_scene)
	_maybe_add_open_script_button(action_row, scripts_to_open)

	# -----------------------------------------------------------------------
	# 2. Playtest Console & Issues Card (auto-collapsed when clean)
	# -----------------------------------------------------------------------
	var log_errors: Array = _collect_active_playtest_errors()
	_last_detected_error_count = log_errors.size()
	var has_console_or_issues: bool = (
		(not log_errors.is_empty()) or
		(not open_issues.is_empty()) or
		(not _fix_draft_text.strip_edges().is_empty()) or
		_issue_composer_expanded
	)

	if not has_console_or_issues:
		var expand_issue_btn := Button.new()
		expand_issue_btn.flat = true
		expand_issue_btn.theme_type_variation = &"FlatButton"
		expand_issue_btn.text = "+ Log Playtest Issue"
		expand_issue_btn.icon = _editor_icon("Add", "StatusWarning")
		expand_issue_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		expand_issue_btn.tooltip_text = "Describe a playtest bug or feel note for this feature"
		expand_issue_btn.pressed.connect(func() -> void:
			_issue_composer_expanded = true
			_render_active_feature_workspace(feat)
			if _fix_input != null and _fix_input.is_inside_tree():
				_fix_input.grab_focus()
		)
		_body_container.add_child(expand_issue_btn)
	else:
		var issue_card := _create_native_card()
		var issue_vb: VBoxContainer = issue_card["vb"]

		var issue_hdr_row := HBoxContainer.new()
		issue_hdr_row.add_theme_constant_override("separation", _S(4))
		issue_vb.add_child(issue_hdr_row)

		var issue_hdr := Label.new()
		issue_hdr.text = "Playtest Console & Issues"
		issue_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bold_font != null:
			issue_hdr.add_theme_font_override("font", bold_font)
		issue_hdr_row.add_child(issue_hdr)

		if log_errors.is_empty() and open_issues.is_empty():
			var close_composer_btn := Button.new()
			close_composer_btn.flat = true
			close_composer_btn.theme_type_variation = &"FlatButton"
			close_composer_btn.icon = _editor_icon("Close")
			if close_composer_btn.icon == null:
				close_composer_btn.text = "x"
			close_composer_btn.tooltip_text = "Hide playtest issue composer"
			close_composer_btn.pressed.connect(func() -> void:
				_fix_draft_text = ""
				_issue_composer_expanded = false
				_render_active_feature_workspace(feat)
			)
			issue_hdr_row.add_child(close_composer_btn)

		if not log_errors.is_empty():
			var err_row := HBoxContainer.new()
			err_row.add_theme_constant_override("separation", _S(4))
			issue_vb.add_child(err_row)

			var err_fmt: Dictionary = _format_capped_issue_list(
				log_errors,
				3,
				"Console errors (%d)" % log_errors.size() if log_errors.size() > 1 else ""
			)
			var err_lbl := Label.new()
			err_lbl.text = String(err_fmt.get("inline_text", ""))
			err_lbl.tooltip_text = String(err_fmt.get("tooltip_text", ""))
			err_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
			err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			err_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			err_lbl.add_theme_color_override("font_color", _editor_color("error_color", Color(0.95, 0.48, 0.48)))
			err_row.add_child(err_lbl)

			_maybe_add_issue_jump_button(err_row, log_errors, known_jump_paths)

			var log_err_btn := Button.new()
			log_err_btn.flat = true
			log_err_btn.theme_type_variation = &"FlatButton"
			log_err_btn.text = "Log Issue"
			log_err_btn.icon = _editor_icon("StatusWarning", "Add")
			log_err_btn.tooltip_text = "Log detected console errors as a playtest issue on this feature"
			log_err_btn.pressed.connect(_on_log_console_errors_pressed.bind(feat, log_errors))
			err_row.add_child(log_err_btn)

			var dismiss_err_btn := Button.new()
			dismiss_err_btn.flat = true
			dismiss_err_btn.theme_type_variation = &"FlatButton"
			dismiss_err_btn.icon = _editor_icon("Close")
			if dismiss_err_btn.icon == null:
				dismiss_err_btn.text = "x"
			dismiss_err_btn.tooltip_text = "Dismiss error notice"
			dismiss_err_btn.pressed.connect(func() -> void:
				for le in log_errors:
					_ignored_error_signatures[str(le)] = true
				_last_error_clear_unix = Time.get_unix_time_from_system()
				if _editor_logger != null:
					_editor_logger.clear()
				_render_active_feature_workspace(feat)
			)
			err_row.add_child(dismiss_err_btn)

		if not open_issues.is_empty():
			var issues_box := VBoxContainer.new()
			issues_box.add_theme_constant_override("separation", _S(4))
			issue_vb.add_child(issues_box)
			for iss_raw in open_issues:
				var iss_id: String = ""
				var iss_txt: String = ""
				if typeof(iss_raw) == TYPE_DICTIONARY:
					var iss_d: Dictionary = iss_raw as Dictionary
					iss_id = str(iss_d.get("id", "")).strip_edges()
					iss_txt = str(iss_d.get("text", "")).strip_edges()
				else:
					iss_txt = str(iss_raw).strip_edges()
				if iss_txt.is_empty():
					continue
				var iss_row := HBoxContainer.new()
				iss_row.add_theme_constant_override("separation", _S(4))
				issues_box.add_child(iss_row)

				var iss_lbl := Label.new()
				iss_lbl.text = "[FIX] %s" % iss_txt
				iss_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				iss_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				iss_lbl.add_theme_color_override("font_color", _editor_color("warning_color", Color(0.96, 0.76, 0.36)))
				iss_row.add_child(iss_lbl)

				_maybe_add_issue_jump_button(iss_row, [iss_txt], known_jump_paths)

				var res_btn := Button.new()
				res_btn.flat = true
				res_btn.theme_type_variation = &"FlatButton"
				res_btn.text = "Resolve ✓"
				res_btn.icon = _editor_icon("StatusSuccess")
				res_btn.tooltip_text = "Mark this playtest issue resolved"
				res_btn.pressed.connect(_on_resolve_issue_pressed.bind(feat, iss_id))
				iss_row.add_child(res_btn)

		_fix_input = TextEdit.new()
		_fix_input.placeholder_text = "Describe playtest bug or feel note... (Enter to log, Shift+Enter for newline)"
		_fix_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		_fix_input.scroll_fit_content_height = true
		_fix_input.custom_minimum_size = Vector2(0.0, float(_S(46)))
		_fix_input.text = _fix_draft_text
		_fix_input.text_changed.connect(func() -> void:
			if _fix_input != null:
				_fix_draft_text = _fix_input.text
		)
		_fix_input.gui_input.connect(_on_fix_input_gui_input.bind(feat))
		issue_vb.add_child(_fix_input)

		var log_btn := Button.new()
		log_btn.text = "+ Log Playtest Issue"
		log_btn.icon = _editor_icon("Add", "StatusWarning")
		log_btn.pressed.connect(_on_log_issue_pressed.bind(feat))
		issue_vb.add_child(log_btn)

	if _footer_box != null:
		_footer_box.visible = not gate_passed
		if not gate_passed and _primary_cta_btn != null:
			_primary_cta_btn.disabled = false
			_primary_cta_btn.text = "Playtest Passed — Next Feature"
			_primary_cta_btn.icon = _editor_icon("Forward")


# ---------------------------------------------------------------------------
# Feature Actions, Playtest, Guards & Issues (2-Way Sync)
# ---------------------------------------------------------------------------

func _format_capped_issue_list(items: Array, max_inline: int = 3, header_prefix: String = "") -> Dictionary:
	var clean := PackedStringArray()
	for raw_item in items:
		var s := str(raw_item).strip_edges()
		if not s.is_empty():
			clean.append(s)
	if clean.is_empty():
		return {"inline_text": "", "tooltip_text": ""}
	var tip_lines := PackedStringArray()
	if not header_prefix.is_empty():
		tip_lines.append(header_prefix + ":")
	for idx in range(clean.size()):
		tip_lines.append("%d. %s" % [idx + 1, clean[idx]])
	var tooltip_str := "\n".join(tip_lines)
	if clean.size() == 1:
		var single := ("%s: %s" % [header_prefix, clean[0]]) if not header_prefix.is_empty() else clean[0]
		return {"inline_text": single, "tooltip_text": tooltip_str}
	var inline_lines := PackedStringArray()
	if not header_prefix.is_empty():
		inline_lines.append(header_prefix + ":")
	var cap: int = mini(clean.size(), maxi(max_inline, 1))
	for idx in range(cap):
		inline_lines.append("• %s" % clean[idx])
	if clean.size() > cap:
		inline_lines.append("+%d more (hover for full list)" % (clean.size() - cap))
	return {"inline_text": "\n".join(inline_lines), "tooltip_text": tooltip_str}


func _maybe_add_open_scene_button(action_row: HBoxContainer, scene_paths: PackedStringArray, arena_scene_path: String = "") -> void:
	if scene_paths.is_empty():
		return
	if scene_paths.size() == 1:
		var scene_path: String = scene_paths[0]
		var open_scene_btn := Button.new()
		open_scene_btn.flat = true
		open_scene_btn.theme_type_variation = &"FlatButton"
		open_scene_btn.text = "Open Scene"
		open_scene_btn.icon = _editor_icon("PackedScene", "File")
		open_scene_btn.tooltip_text = "Open %s in Godot viewport" % scene_path
		open_scene_btn.pressed.connect(_on_open_res_path_pressed.bind(scene_path))
		action_row.add_child(open_scene_btn)
		return
	var open_menu_btn := MenuButton.new()
	open_menu_btn.flat = true
	open_menu_btn.theme_type_variation = &"FlatButton"
	open_menu_btn.text = "Open Scene (%d)" % scene_paths.size()
	open_menu_btn.icon = _editor_icon("PackedScene", "File")
	open_menu_btn.tooltip_text = "Choose feature scene or arena scene to open in Godot viewport"
	var popup: PopupMenu = open_menu_btn.get_popup()
	for idx in range(scene_paths.size()):
		var sp: String = scene_paths[idx]
		var role_tag: String = "Arena" if (not arena_scene_path.is_empty() and sp == arena_scene_path) else "Feature"
		popup.add_item("%s (%s)" % [sp.get_file(), role_tag], idx)
		popup.set_item_tooltip(idx, sp)
	popup.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < scene_paths.size():
			_on_open_res_path_pressed(scene_paths[id])
	)
	action_row.add_child(open_menu_btn)


func _maybe_add_open_script_button(action_row: HBoxContainer, script_paths: PackedStringArray) -> void:
	if script_paths.is_empty():
		return
	if script_paths.size() == 1:
		var script_path: String = script_paths[0]
		var open_script_btn := Button.new()
		open_script_btn.flat = true
		open_script_btn.theme_type_variation = &"FlatButton"
		open_script_btn.text = "Open Script"
		open_script_btn.icon = _editor_icon("Script", "File")
		open_script_btn.tooltip_text = "Open %s in Godot Script Editor" % script_path
		open_script_btn.pressed.connect(_on_open_res_path_pressed.bind(script_path))
		action_row.add_child(open_script_btn)
		return
	var open_menu_btn := MenuButton.new()
	open_menu_btn.flat = true
	open_menu_btn.theme_type_variation = &"FlatButton"
	open_menu_btn.text = "Open Script (%d)" % script_paths.size()
	open_menu_btn.icon = _editor_icon("Script", "File")
	open_menu_btn.tooltip_text = "Choose one of %d feature scripts to open in Godot Script Editor" % script_paths.size()
	var popup: PopupMenu = open_menu_btn.get_popup()
	for idx in range(script_paths.size()):
		popup.add_item(script_paths[idx].get_file(), idx)
		popup.set_item_tooltip(idx, script_paths[idx])
	popup.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < script_paths.size():
			_on_open_res_path_pressed(script_paths[id])
	)
	action_row.add_child(open_menu_btn)


func _maybe_add_issue_jump_button(
	row: HBoxContainer,
	issue_items: Array,
	known_paths: PackedStringArray
) -> void:
	if _executor == null or row == null or issue_items.is_empty():
		return
	var raw_targets: Variant = _executor.call("extract_issue_jump_targets", issue_items, known_paths)
	if typeof(raw_targets) != TYPE_ARRAY:
		return
	var valid_targets: Array = []
	for t_raw in (raw_targets as Array):
		if typeof(t_raw) != TYPE_DICTIONARY:
			continue
		var td: Dictionary = t_raw as Dictionary
		var tp := str(td.get("path", "")).strip_edges()
		if tp.begins_with("res://") and FileAccess.file_exists(tp):
			valid_targets.append(td)
	if valid_targets.is_empty():
		return
	if valid_targets.size() == 1:
		var first_t: Dictionary = valid_targets[0]
		var fp := str(first_t.get("path", ""))
		var fln := int(first_t.get("line", 0))
		var jump_btn := Button.new()
		jump_btn.flat = true
		jump_btn.theme_type_variation = &"FlatButton"
		jump_btn.text = ("Open :%d" % fln) if fln > 0 else "Open"
		jump_btn.icon = _editor_icon("Script" if fp.ends_with(".gd") else "PackedScene", "File")
		jump_btn.tooltip_text = ("Jump to %s line %d" % [fp, fln]) if fln > 0 else ("Open %s" % fp)
		jump_btn.pressed.connect(_on_open_res_path_pressed.bind(fp, fln if fln > 0 else -1))
		row.add_child(jump_btn)
		return
	var jump_menu := MenuButton.new()
	jump_menu.flat = true
	jump_menu.theme_type_variation = &"FlatButton"
	jump_menu.text = "Open (%d)" % valid_targets.size()
	jump_menu.icon = _editor_icon("Script", "File")
	jump_menu.tooltip_text = "Jump to an affected script line or scene"
	var popup: PopupMenu = jump_menu.get_popup()
	for idx in range(valid_targets.size()):
		var td: Dictionary = valid_targets[idx]
		popup.add_item(str(td.get("label", "Open")), idx)
		popup.set_item_tooltip(idx, str(td.get("path", "")))
	popup.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < valid_targets.size():
			var chosen: Dictionary = valid_targets[id]
			var cp := str(chosen.get("path", ""))
			var cln := int(chosen.get("line", 0))
			_on_open_res_path_pressed(cp, cln if cln > 0 else -1)
	)
	row.add_child(jump_menu)


func _on_fix_input_gui_input(event: InputEvent, feat: Dictionary) -> void:
	if not (event is InputEventKey):
		return
	var ev: InputEventKey = event as InputEventKey
	if not ev.pressed or ev.alt_pressed:
		return
	if ev.keycode != KEY_ENTER and ev.keycode != KEY_KP_ENTER:
		return
	if ev.shift_pressed:
		if _fix_input != null:
			_fix_input.insert_text_at_caret("\n")
			_fix_draft_text = _fix_input.text
			if _fix_input.is_inside_tree():
				_fix_input.accept_event()
		return
	if ev.echo:
		if _fix_input != null and _fix_input.is_inside_tree():
			_fix_input.accept_event()
		return
	if _fix_input != null and _fix_input.is_inside_tree():
		_fix_input.accept_event()
	_on_log_issue_pressed(feat)


func _recompute_feature_progress(feat: Dictionary) -> int:
	if bool(feat.get("isPlaytestPassed", false)) or bool(feat.get("isCompleted", false)):
		feat["progress"] = 100
		return 100
	var raw_guards: Variant = feat.get("edgeCases", [])
	if typeof(raw_guards) == TYPE_ARRAY and not (raw_guards as Array).is_empty():
		var arr: Array = raw_guards as Array
		var checked_cnt: int = 0
		for g_raw in arr:
			if typeof(g_raw) == TYPE_DICTIONARY and bool((g_raw as Dictionary).get("signedOff", false)):
				checked_cnt += 1
		var pct: int = int(round(float(checked_cnt) / float(arr.size()) * 50.0))
		feat["progress"] = pct
		return pct
	feat["progress"] = 0
	return 0


func _on_guard_toggled(toggled_on: bool, feat: Dictionary, guard_idx: int, raw_guard_text: String) -> void:
	if feat.is_empty():
		return
	var feat_id: String = str(feat.get("id", ""))
	var cp_id: String = str(feat.get("checkpointId", ""))
	var raw_guards: Variant = feat.get("edgeCases", [])
	if typeof(raw_guards) == TYPE_ARRAY:
		var arr: Array = raw_guards as Array
		for i in range(arr.size()):
			if typeof(arr[i]) == TYPE_DICTIONARY:
				var d: Dictionary = arr[i]
				if int(d.get("index", i)) == guard_idx:
					d["signedOff"] = toggled_on
					break
	_recompute_feature_progress(feat)
	if _sync != null and not _payload.is_empty():
		_sync.save_cached_epic(_payload)
	_render_active_feature_workspace(feat)
	if _sync != null and _sync.has_link_token() and not feat_id.is_empty():
		_sync.toggle_guard(feat_id, cp_id, guard_idx, raw_guard_text, toggled_on)


func _on_log_console_errors_pressed(feat: Dictionary, log_errors: Array) -> void:
	var joined := PackedStringArray()
	for e in log_errors:
		var s := str(e).strip_edges()
		if not s.is_empty():
			joined.append(s)
			_ignored_error_signatures[s] = true
	if joined.is_empty():
		return
	_last_error_clear_unix = Time.get_unix_time_from_system()
	if _editor_logger != null:
		_editor_logger.clear()
	_submit_log_issue(feat, "\n".join(joined))


func _on_log_issue_pressed(feat: Dictionary = {}) -> void:
	var target_feat: Dictionary = feat if not feat.is_empty() else _get_active_feature()
	var prompt_txt: String = (_fix_input.text if _fix_input != null else _fix_draft_text).strip_edges()
	if prompt_txt.is_empty():
		_set_status("Describe the playtest issue first.", true)
		return
	_submit_log_issue(target_feat, prompt_txt)


func _submit_log_issue(feat: Dictionary, issue_text: String) -> void:
	if feat.is_empty():
		return
	var clean_txt := issue_text.strip_edges()
	if clean_txt.is_empty():
		return
	var feat_id: String = str(feat.get("id", ""))
	var cp_id: String = str(feat.get("checkpointId", ""))

	var raw_issues: Variant = feat.get("openIssues", [])
	var next_issues: Array = (raw_issues as Array).duplicate() if typeof(raw_issues) == TYPE_ARRAY else []
	next_issues.append({
		"id": "local_fix_%d" % Time.get_ticks_msec(),
		"text": clean_txt,
	})
	feat["openIssues"] = next_issues
	feat["isPlaytestPassed"] = false
	feat["isCompleted"] = false
	var raw_guards: Variant = feat.get("edgeCases", [])
	var next_guards: Array = (raw_guards as Array).duplicate() if typeof(raw_guards) == TYPE_ARRAY else []
	var lower_clean: String = clean_txt.to_lower()
	var has_guard: bool = false
	for g_raw in next_guards:
		var g_str: String = ""
		if typeof(g_raw) == TYPE_DICTIONARY:
			var gd: Dictionary = g_raw as Dictionary
			g_str = str(gd.get("rawText", gd.get("text", ""))).to_lower()
		else:
			g_str = str(g_raw).to_lower()
		if g_str.find(lower_clean) != -1:
			has_guard = true
			break
	if not has_guard:
		var next_idx: int = next_guards.size()
		next_guards.append({
			"index": next_idx,
			"rawText": "[PLAYTEST GUARD] %s" % clean_txt,
			"text": clean_txt,
			"signedOff": false,
		})
		feat["edgeCases"] = next_guards
	_fix_draft_text = ""
	_issue_composer_expanded = false
	if _fix_input != null:
		_fix_input.text = ""
	if _sync != null and not _payload.is_empty():
		_sync.save_cached_epic(_payload)
	_set_status("Logged playtest issue.", false)
	_refresh_view()
	if _sync != null and _sync.has_link_token() and not feat_id.is_empty():
		_sync.log_playtest_issue(feat_id, cp_id, clean_txt)


func _on_resolve_issue_pressed(feat: Dictionary, issue_id: String) -> void:
	if feat.is_empty():
		return
	var feat_id: String = str(feat.get("id", ""))
	var cp_id: String = str(feat.get("checkpointId", ""))
	var raw_issues: Variant = feat.get("openIssues", [])
	if typeof(raw_issues) == TYPE_ARRAY:
		var remaining: Array = []
		for item in (raw_issues as Array):
			if typeof(item) == TYPE_DICTIONARY and str((item as Dictionary).get("id", "")).strip_edges() == issue_id:
				continue
			remaining.append(item)
		feat["openIssues"] = remaining
	if _sync != null and not _payload.is_empty():
		_sync.save_cached_epic(_payload)
	_set_status("Resolved playtest issue.", false)
	_refresh_view()
	if _sync != null and _sync.has_link_token() and not feat_id.is_empty() and not issue_id.is_empty():
		_sync.resolve_playtest_issue(feat_id, cp_id, issue_id)


func _is_editor_playing() -> bool:
	return editor_interface != null and editor_interface.has_method("is_playing_scene") and bool(editor_interface.call("is_playing_scene"))


func _on_playtest_watch_tick() -> void:
	var playing_now := _is_editor_playing()
	if playing_now != _was_playing_scene:
		_was_playing_scene = playing_now
		if not playing_now:
			if _executor != null:
				_executor.call("invalidate_eval_cache")
			if is_inside_tree() and _post_playtest_log_timer != null:
				_post_playtest_log_timer.start()
		var feat := _get_active_feature()
		if not _show_token_editor and _workspace_panel != null and _workspace_panel.visible and not feat.is_empty():
			_render_active_feature_workspace(feat)
		return
	if not _show_token_editor and _workspace_panel != null and _workspace_panel.visible and not (_fix_input != null and _fix_input.has_focus()):
		var cur_logger_cnt: int = _editor_logger.entry_count() if _editor_logger != null else 0
		if playing_now or cur_logger_cnt != _last_seen_logger_count:
			var live_err_count: int = _collect_active_playtest_errors().size()
			if live_err_count != _last_detected_error_count:
				var feat := _get_active_feature()
				if not feat.is_empty():
					_render_active_feature_workspace(feat)


func _on_post_playtest_log_timeout() -> void:
	if _show_token_editor or _workspace_panel == null or not _workspace_panel.visible:
		return
	var feat := _get_active_feature()
	if not feat.is_empty():
		_render_active_feature_workspace(feat)


func _on_playtest_arena_pressed(arena_scene: String, primary_scene: String) -> void:
	if editor_interface == null:
		return
	if _is_editor_playing() and editor_interface.has_method("stop_playing_scene"):
		editor_interface.call("stop_playing_scene")
		return
	if editor_interface.has_method("get_script_editor"):
		var script_ed: Variant = editor_interface.get_script_editor()
		if script_ed != null and script_ed.has_method("save_all_scripts"):
			script_ed.call("save_all_scripts")
	if editor_interface.has_method("save_all_scenes"):
		editor_interface.call("save_all_scenes")
	elif editor_interface.has_method("save_scene"):
		editor_interface.call("save_scene")
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


func _on_open_res_path_pressed(res_path: String, line_number: int = -1) -> void:
	if _executor == null:
		return
	var err_msg: String = str(_executor.call("open_res_path", editor_interface, res_path, line_number))
	if not err_msg.is_empty():
		_set_status(err_msg, true)


func _on_feature_selected(idx: int) -> void:
	var epic_raw: Variant = _payload.get("activeEpic", null)
	if typeof(epic_raw) != TYPE_DICTIONARY:
		return
	var features: Array = (epic_raw as Dictionary).get("features", [])
	if idx >= 0 and idx < features.size():
		var f: Dictionary = features[idx]
		var next_id := str(f.get("id", ""))
		if next_id != _selected_feature_id:
			_issue_composer_expanded = false
		_selected_feature_id = next_id
		_render_active_feature_workspace(f)


func _on_primary_cta_pressed() -> void:
	var feat: Dictionary = _get_active_feature()
	if feat.is_empty() or _sync == null:
		return
	var feat_id: String = str(feat.get("id", ""))
	var cp_id: String = str(feat.get("checkpointId", ""))
	feat["isPlaytestPassed"] = true
	feat["isCompleted"] = true
	feat["progress"] = 100
	feat["openIssues"] = []
	_issue_composer_expanded = false
	var raw_guards: Variant = feat.get("edgeCases", [])
	if typeof(raw_guards) == TYPE_ARRAY:
		for g_raw in (raw_guards as Array):
			if typeof(g_raw) == TYPE_DICTIONARY:
				(g_raw as Dictionary)["signedOff"] = true

	var epic_raw: Variant = _payload.get("activeEpic", null)
	if typeof(epic_raw) == TYPE_DICTIONARY:
		var features: Array = (epic_raw as Dictionary).get("features", [])
		for f_raw in features:
			if typeof(f_raw) == TYPE_DICTIONARY:
				var fd: Dictionary = f_raw as Dictionary
				if str(fd.get("id", "")) != feat_id and not bool(fd.get("isCompleted", false)):
					_selected_feature_id = str(fd.get("id", ""))
					break

	if not _payload.is_empty():
		_sync.save_cached_epic(_payload)
	_set_status("Playtest passed — advancing to next feature...", false)
	_refresh_view()
	_sync.set_playtest_passed(feat_id, cp_id, true)


func _on_reopen_gate_pressed(feat: Dictionary) -> void:
	if feat.is_empty():
		return
	var feat_id: String = str(feat.get("id", ""))
	var cp_id: String = str(feat.get("checkpointId", ""))
	feat["isPlaytestPassed"] = false
	feat["isCompleted"] = false
	_recompute_feature_progress(feat)
	if _sync != null and not _payload.is_empty():
		_sync.save_cached_epic(_payload)
	_set_status("Playtest gate reopened — iterate & re-verify when ready.", false)
	_refresh_view()
	if _sync != null and _sync.has_link_token() and not feat_id.is_empty():
		_sync.set_playtest_passed(feat_id, cp_id, false)


func _on_copy_context_pressed(feat: Dictionary) -> void:
	if _executor == null:
		return
	var arena_scene: String = str(_payload.get("arenaScenePath", "")).strip_edges()
	var paths: Dictionary = _executor.call("resolve_feature_paths", feat, arena_scene)
	var primary_scene: String = str(paths.get("primary_scene", feat.get("primaryAsset", ""))).strip_edges()
	var all_scenes: PackedStringArray = _executor.call("collect_project_scene_paths", "res://", 120)
	var extra_scenes := PackedStringArray()
	if not primary_scene.is_empty():
		extra_scenes.append(primary_scene)
	if not arena_scene.is_empty() and not (arena_scene in extra_scenes):
		extra_scenes.append(arena_scene)
	for sc in all_scenes:
		if not (sc in extra_scenes):
			extra_scenes.append(sc)
	var scene_snap: Dictionary = _executor.call("capture_rich_scene_snapshot", editor_interface, extra_scenes)
	var live_scripts: Dictionary = _executor.call("read_all_live_project_scripts", "res://", editor_interface)
	var input_map_snap: Dictionary = _executor.call("capture_input_map_snapshot")
	var recent_errors: Array = _collect_active_playtest_errors()
	var ctx_feat: Dictionary = feat.duplicate()
	if not ctx_feat.has("releaseVersion"):
		ctx_feat["releaseVersion"] = str(_payload.get("releaseVersion", "v0.1"))
	var epic_raw: Variant = _payload.get("activeEpic", {})
	var epic_dict: Dictionary = epic_raw if typeof(epic_raw) == TYPE_DICTIONARY else {}
	var sibling_tuning: Array = []
	var cur_feat_id: String = str(feat.get("id", "")).strip_edges()
	var epic_feats: Variant = epic_dict.get("features", [])
	if typeof(epic_feats) == TYPE_ARRAY:
		for sib_raw in (epic_feats as Array):
			if typeof(sib_raw) != TYPE_DICTIONARY:
				continue
			var sib_d: Dictionary = sib_raw as Dictionary
			if str(sib_d.get("id", "")).strip_edges() == cur_feat_id:
				continue
			var sib_params: Variant = sib_d.get("tuningParams", [])
			var sib_clean_params := PackedStringArray()
			if typeof(sib_params) == TYPE_ARRAY or typeof(sib_params) == TYPE_PACKED_STRING_ARRAY:
				for sp_item in sib_params:
					var sp_str := str(sp_item).strip_edges()
					if not sp_str.is_empty():
						sib_clean_params.append(sp_str)
			if not sib_clean_params.is_empty():
				sibling_tuning.append({
					"title": str(sib_d.get("title", "Feature")).strip_edges(),
					"tuningParams": sib_clean_params,
				})
	var project_ctx: Dictionary = {
		"projectTitle": str(_payload.get("projectTitle", "")).strip_edges(),
		"releaseVersion": str(_payload.get("releaseVersion", "v0.1")).strip_edges(),
		"designPillars": _payload.get("designPillars", []),
		"tradeOffs": _payload.get("tradeOffs", []),
		"epicCode": str(epic_dict.get("code", "")).strip_edges(),
		"epicTitle": str(epic_dict.get("title", "")).strip_edges(),
		"siblingTuning": sibling_tuning,
	}
	var md: String = _executor.call(
		"format_feature_context_markdown",
		ctx_feat,
		live_scripts,
		scene_snap,
		input_map_snap,
		recent_errors,
		project_ctx
	)
	DisplayServer.clipboard_set(md)
	_set_status("Copied Godot context (%d chars) to clipboard." % md.length(), false)


func _on_epic_updated(payload: Dictionary) -> void:
	var prev_epic_id := str((_payload.get("activeEpic", {}) as Dictionary).get("id", "")) if typeof(_payload.get("activeEpic", null)) == TYPE_DICTIONARY else ""
	var next_epic_id := str((payload.get("activeEpic", {}) as Dictionary).get("id", "")) if typeof(payload.get("activeEpic", null)) == TYPE_DICTIONARY else ""
	var remote_focus_id := str(payload.get("selectedFeatureId", "")).strip_edges()
	var remote_web_sel := str(payload.get("webSelectedFeatureId", "")).strip_edges()
	var web_sel_changed := (not remote_web_sel.is_empty()) and remote_web_sel != _last_synced_web_selected_id
	if prev_epic_id != next_epic_id:
		_issue_composer_expanded = false
	if _selected_feature_id.is_empty() or prev_epic_id != next_epic_id:
		if not remote_focus_id.is_empty():
			_selected_feature_id = remote_focus_id
		elif prev_epic_id != next_epic_id:
			_selected_feature_id = ""
	elif _pull_sync_pending and web_sel_changed:
		_selected_feature_id = remote_web_sel
	_last_synced_web_selected_id = remote_web_sel
	_pull_sync_pending = false
	_payload = payload
	_set_status("Synced", false)
	_refresh_view()


func _on_sync_failed(message: String) -> void:
	_pull_sync_pending = false
	_set_status(message, true)
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty() and _workspace_panel != null and _workspace_panel.visible:
		_render_active_feature_workspace(feat)


func _on_busy_changed(is_busy: bool) -> void:
	if _sync_btn != null:
		_sync_btn.disabled = is_busy
	if is_busy and _status_label != null:
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
	_last_synced_web_selected_id = ""
	_pull_sync_pending = true
	_refresh_view()
	_sync.fetch_active_epic()
	if _sync.has_method("check_for_plugin_update"):
		_sync.check_for_plugin_update(true)


func _on_cancel_token_pressed() -> void:
	_show_token_editor = false
	_refresh_view()


func _on_disconnect_pressed() -> void:
	if _sync == null:
		return
	_sync.clear_link_token()
	_payload = {}
	_selected_feature_id = ""
	_last_synced_web_selected_id = ""
	_pull_sync_pending = false
	_show_token_editor = true
	if _status_label != null:
		_status_label.text = "Disconnected"
		_status_label.add_theme_color_override("font_color", _editor_color("disabled_font_color", Color(0.66, 0.70, 0.76)))
	_refresh_view()


func _on_sync_pressed() -> void:
	if _executor != null:
		_executor.call("invalidate_eval_cache")
	if _sync != null:
		_pull_sync_pending = true
		_sync.fetch_active_epic()
		if _sync.has_method("check_for_plugin_update"):
			_sync.check_for_plugin_update(true)
	if _workspace_panel != null and _workspace_panel.visible and not _payload.is_empty():
		_refresh_view()


func build_web_studio_deep_link(base_url: String, project_id: String, feature_id: String) -> String:
	var url := base_url.strip_edges()
	if url.is_empty():
		url = DEFAULT_WEB_STUDIO_URL
	var fragment := ""
	var hash_idx := url.find("#")
	if hash_idx != -1:
		fragment = url.substr(hash_idx)
		url = url.substr(0, hash_idx)
	var params := PackedStringArray()
	var clean_proj := project_id.strip_edges()
	var clean_feat := feature_id.strip_edges()
	if not clean_proj.is_empty():
		params.append("project=%s" % clean_proj.uri_encode())
	if not clean_feat.is_empty():
		params.append("feature=%s" % clean_feat.uri_encode())
	if not params.is_empty():
		var sep := "&" if url.contains("?") else "?"
		url = "%s%s%s" % [url, sep, "&".join(params)]
	return "%s%s" % [url, fragment]


func _on_open_web_pressed() -> void:
	var base_url: String = str(_payload.get("webStudioUrl", DEFAULT_WEB_STUDIO_URL)).strip_edges()
	var project_id: String = str(_payload.get("projectId", "")).strip_edges()
	OS.shell_open(build_web_studio_deep_link(base_url, project_id, _selected_feature_id))


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
	await get_tree().create_timer(0.03).timeout
	if ei == null or get_tree() == null:
		queue_free()
		return
	ei.set_plugin_enabled(plugin_key, false)
	await get_tree().create_timer(0.02).timeout
	for p in gd_paths:
		ResourceLoader.load(p, "Script", ResourceLoader.CACHE_MODE_REPLACE)
	if ei.get_resource_filesystem() != null:
		ei.get_resource_filesystem().scan()
	await get_tree().create_timer(0.02).timeout
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
