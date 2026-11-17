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
		var raw_msg: String = rationale if not rationale.strip_edges().is_empty() else code
		var combined: String = ("%s (%s:%d in %s)" % [raw_msg.strip_edges(), file, line, function]).strip_edges()
		var lower: String = combined.to_lower()
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
		var prefix: String = "SCRIPT ERROR: " if error_type == 2 else "ERROR: "
		var formatted: String = (prefix + combined).left(340)
		var now_unix: float = Time.get_unix_time_from_system()
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

	func inject(msg: String) -> void:
		var clean: String = msg.strip_edges().left(340)
		if clean.is_empty():
			return
		_mutex.lock()
		if _entries.size() >= 24:
			_entries.pop_front()
		_entries.append({ "ts": Time.get_unix_time_from_system() + 1.0, "msg": clean })
		_mutex.unlock()


var editor_interface: Variant = null
var undo_redo: EditorUndoRedoManager = null

var _sync_client: Node = null
var _executor: RefCounted = null
var _logger: _LayersEditorLogger = null
var _logger_registered: bool = false

var _payload: Dictionary = {}
var _last_bundle_snapshot: Dictionary = {}
var _auto_heal_attempted: bool = false
var _status_message: String = ""
var _status_is_error: bool = false
var _available_update_ver: String = ""
var _pending_build_preferred_scene: String = ""
var _last_built_scene_path: String = ""
var _errors_cleared_unix: float = 0.0
var _ignored_error_signatures: Dictionary = {}
var _manual_update_check: bool = false
var _show_token_fallback: bool = false

# UI Nodes
var _title_label: Label
var _dim_badge: Label
var _sync_btn: Button
var _studio_btn: Button
var _menu_btn: MenuButton

var _update_banner: PanelContainer
var _update_label: Label
var _update_apply_btn: Button

var _status_label: Label

var _unlinked_panel: PanelContainer
var _google_signin_btn: Button
var _cancel_signin_btn: Button
var _toggle_token_btn: Button
var _token_row: HBoxContainer
var _token_input: LineEdit
var _token_save_btn: Button

var _linked_scroll: ScrollContainer
var _linked_box: VBoxContainer
var _project_meta_label: Label
var _epic_selector: OptionButton

var _primary_cta_btn: Button
var _play_btn: Button
var _undo_btn: Button

var _goal_label: Label
var _deltas_box: VBoxContainer
var _tuning_box: VBoxContainer
var _checks_box: VBoxContainer
var _pass_reopen_btn: Button

var _errors_card: PanelContainer
var _errors_list_box: VBoxContainer
var _clear_errors_btn: Button
var _auto_fix_errors_btn: Button

var _fixes_box: VBoxContainer
var _fix_input: LineEdit
var _flag_fix_btn: Button


func _enter_tree() -> void:
	name = "LAYERS"
	if Engine.is_editor_hint() and _logger == null:
		_logger = _LayersEditorLogger.new()
		if OS.has_method("add_logger"):
			OS.call("add_logger", _logger)
			_logger_registered = true


func _exit_tree() -> void:
	if _logger != null and _logger_registered:
		if OS.has_method("remove_logger"):
			OS.call("remove_logger", _logger)
		_logger_registered = false
		_logger = null


func _ready() -> void:
	_init_helpers()
	_build_ui()
	_wire_signals()

	if _sync_client != null:
		var cached: Dictionary = _sync_client.call("load_cached_epic") as Dictionary
		if not cached.is_empty():
			_payload = cached
		_refresh_ui()
		if bool(_sync_client.call("has_link_token")):
			_sync_with_cloud()
		if Engine.is_editor_hint():
			_sync_client.call("check_for_plugin_update", true)


func _init_helpers() -> void:
	var step_scr: Script = load(STEP_EXECUTOR_SCRIPT_PATH) as Script
	if step_scr != null:
		_executor = step_scr.new()

	var sync_scr: Script = load(SYNC_CLIENT_SCRIPT_PATH) as Script
	if sync_scr != null:
		_sync_client = sync_scr.new() as Node
		if _sync_client != null:
			add_child(_sync_client)


func _build_ui() -> void:
	custom_minimum_size = Vector2(270, 0)
	add_theme_constant_override("separation", 8)

	# Top Header Bar
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	add_child(header)

	_title_label = Label.new()
	_title_label.text = "LAYERS"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 14)
	header.add_child(_title_label)

	_dim_badge = Label.new()
	_dim_badge.text = "3D"
	_dim_badge.add_theme_font_size_override("font_size", 11)
	header.add_child(_dim_badge)

	_sync_btn = Button.new()
	_sync_btn.text = "↻"
	_sync_btn.tooltip_text = "Sync Active Epic Spec & Project Snapshot"
	header.add_child(_sync_btn)

	_studio_btn = Button.new()
	_studio_btn.text = "Studio"
	_studio_btn.tooltip_text = "Open Web Studio"
	header.add_child(_studio_btn)

	_menu_btn = MenuButton.new()
	_menu_btn.text = "⚙"
	_menu_btn.tooltip_text = "Plugin Settings & Account"
	var popup := _menu_btn.get_popup()
	popup.add_item("Sign in with Google", 1)
	popup.add_item("Check Plugin Updates", 2)
	popup.add_item("Clear Captured Errors", 3)
	popup.add_separator()
	popup.add_item("Unlink Project", 4)
	header.add_child(_menu_btn)

	# Self-update banner
	_update_banner = PanelContainer.new()
	_update_banner.visible = false
	add_child(_update_banner)
	var ub_row := HBoxContainer.new()
	ub_row.add_theme_constant_override("separation", 6)
	_update_banner.add_child(ub_row)
	_update_label = Label.new()
	_update_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_label.add_theme_font_size_override("font_size", 11)
	ub_row.add_child(_update_label)
	_update_apply_btn = Button.new()
	_update_apply_btn.text = "Update"
	ub_row.add_child(_update_apply_btn)

	# Status line
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.visible = false
	add_child(_status_label)

	# Unlinked Card
	_unlinked_panel = PanelContainer.new()
	add_child(_unlinked_panel)
	var ul_box := VBoxContainer.new()
	ul_box.add_theme_constant_override("separation", 8)
	_unlinked_panel.add_child(ul_box)

	var ul_title := Label.new()
	ul_title.text = "Connect Godot 4 to LAYERS Studio"
	ul_title.add_theme_font_size_override("font_size", 13)
	ul_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ul_box.add_child(ul_title)

	var ul_desc := Label.new()
	ul_desc.text = "Sign in once with Google to stream your Epic spec and enable 1-click Build & Playtest repair inside Godot."
	ul_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ul_desc.add_theme_font_size_override("font_size", 11)
	ul_box.add_child(ul_desc)

	_google_signin_btn = Button.new()
	_google_signin_btn.text = "⚡ Sign in with Google"
	ul_box.add_child(_google_signin_btn)

	_cancel_signin_btn = Button.new()
	_cancel_signin_btn.text = "Cancel Waiting for Browser"
	_cancel_signin_btn.visible = false
	ul_box.add_child(_cancel_signin_btn)

	_toggle_token_btn = Button.new()
	_toggle_token_btn.text = "Use fallback lyr_ token instead ▾"
	_toggle_token_btn.flat = true
	ul_box.add_child(_toggle_token_btn)

	_token_row = HBoxContainer.new()
	_token_row.visible = false
	_token_row.add_theme_constant_override("separation", 6)
	ul_box.add_child(_token_row)

	_token_input = LineEdit.new()
	_token_input.placeholder_text = "Paste lyr_... token"
	_token_input.secret = true
	_token_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_token_row.add_child(_token_input)

	_token_save_btn = Button.new()
	_token_save_btn.text = "Link"
	_token_row.add_child(_token_save_btn)

	# Linked Workspace Scroll
	_linked_scroll = ScrollContainer.new()
	_linked_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_linked_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_linked_scroll)

	_linked_box = VBoxContainer.new()
	_linked_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_linked_box.add_theme_constant_override("separation", 10)
	_linked_scroll.add_child(_linked_box)

	_project_meta_label = Label.new()
	_project_meta_label.text = "Project · v0.1"
	_project_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_project_meta_label.add_theme_font_size_override("font_size", 12)
	_linked_box.add_child(_project_meta_label)

	_epic_selector = OptionButton.new()
	_epic_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_linked_box.add_child(_epic_selector)

	# Action Row: Build/Fix/Pass + Play + Undo
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	_linked_box.add_child(action_row)

	_primary_cta_btn = Button.new()
	_primary_cta_btn.text = "⚡ Build E01"
	_primary_cta_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_primary_cta_btn)

	_play_btn = Button.new()
	_play_btn.text = "▶ Play"
	_play_btn.tooltip_text = "Run Test Scene (or Main Scene)"
	action_row.add_child(_play_btn)

	_undo_btn = Button.new()
	_undo_btn.text = "↶ Undo"
	_undo_btn.tooltip_text = "Restore files/scenes/InputMap to before last AI build"
	_undo_btn.disabled = true
	action_row.add_child(_undo_btn)

	# Intent / Deltas Card
	var goal_card := PanelContainer.new()
	_linked_box.add_child(goal_card)
	var goal_vbox := VBoxContainer.new()
	goal_vbox.add_theme_constant_override("separation", 6)
	goal_card.add_child(goal_vbox)

	var goal_hdr := Label.new()
	goal_hdr.text = "§01 EPIC INTENT"
	goal_hdr.add_theme_font_size_override("font_size", 10)
	goal_vbox.add_child(goal_hdr)

	_goal_label = Label.new()
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_label.add_theme_font_size_override("font_size", 12)
	goal_vbox.add_child(_goal_label)

	_deltas_box = VBoxContainer.new()
	_deltas_box.add_theme_constant_override("separation", 3)
	goal_vbox.add_child(_deltas_box)

	# Captured Errors Card
	_errors_card = PanelContainer.new()
	_errors_card.visible = false
	_linked_box.add_child(_errors_card)
	var err_vbox := VBoxContainer.new()
	err_vbox.add_theme_constant_override("separation", 6)
	_errors_card.add_child(err_vbox)

	var err_hdr_row := HBoxContainer.new()
	err_hdr_row.add_theme_constant_override("separation", 6)
	err_vbox.add_child(err_hdr_row)

	var err_hdr := Label.new()
	err_hdr.text = "DETECTED GODOT ERRORS"
	err_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	err_hdr.add_theme_font_size_override("font_size", 10)
	err_hdr_row.add_child(err_hdr)

	_clear_errors_btn = Button.new()
	_clear_errors_btn.text = "Clear"
	_clear_errors_btn.tooltip_text = "Acknowledge & clear detected errors"
	err_hdr_row.add_child(_clear_errors_btn)

	_errors_list_box = VBoxContainer.new()
	_errors_list_box.add_theme_constant_override("separation", 3)
	err_vbox.add_child(_errors_list_box)

	_auto_fix_errors_btn = Button.new()
	_auto_fix_errors_btn.text = "🔧 Fix Detected Errors with Gemini"
	err_vbox.add_child(_auto_fix_errors_btn)

	# §04 Spatial & Exposed Tuning Card
	var tuning_card := PanelContainer.new()
	_linked_box.add_child(tuning_card)
	var tuning_vbox := VBoxContainer.new()
	tuning_vbox.add_theme_constant_override("separation", 6)
	tuning_card.add_child(tuning_vbox)

	var tuning_hdr := Label.new()
	tuning_hdr.text = "§04 @export TUNING"
	tuning_hdr.add_theme_font_size_override("font_size", 10)
	tuning_vbox.add_child(tuning_hdr)

	_tuning_box = VBoxContainer.new()
	_tuning_box.add_theme_constant_override("separation", 4)
	tuning_vbox.add_child(_tuning_box)

	# §06 Playtest Acceptance Gate Card
	var checks_card := PanelContainer.new()
	_linked_box.add_child(checks_card)
	var checks_vbox := VBoxContainer.new()
	checks_vbox.add_theme_constant_override("separation", 6)
	checks_card.add_child(checks_vbox)

	var checks_hdr := Label.new()
	checks_hdr.text = "§06 PLAYTEST GATE"
	checks_hdr.add_theme_font_size_override("font_size", 10)
	checks_vbox.add_child(checks_hdr)

	_checks_box = VBoxContainer.new()
	_checks_box.add_theme_constant_override("separation", 4)
	checks_vbox.add_child(_checks_box)

	_pass_reopen_btn = Button.new()
	_pass_reopen_btn.text = "Pass Epic ✓"
	checks_vbox.add_child(_pass_reopen_btn)

	# [FIX] Revisions Card
	var fixes_card := PanelContainer.new()
	_linked_box.add_child(fixes_card)
	var fixes_vbox := VBoxContainer.new()
	fixes_vbox.add_theme_constant_override("separation", 6)
	fixes_card.add_child(fixes_vbox)

	var fixes_hdr := Label.new()
	fixes_hdr.text = "[FIX] PLAYTEST REVISIONS"
	fixes_hdr.add_theme_font_size_override("font_size", 10)
	fixes_vbox.add_child(fixes_hdr)

	_fixes_box = VBoxContainer.new()
	_fixes_box.add_theme_constant_override("separation", 4)
	fixes_vbox.add_child(_fixes_box)

	var fix_row := HBoxContainer.new()
	fix_row.add_theme_constant_override("separation", 6)
	fixes_vbox.add_child(fix_row)

	_fix_input = LineEdit.new()
	_fix_input.placeholder_text = "Flag broken feel or bug..."
	_fix_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fix_row.add_child(_fix_input)

	_flag_fix_btn = Button.new()
	_flag_fix_btn.text = "+ [FIX]"
	fix_row.add_child(_flag_fix_btn)


func _wire_signals() -> void:
	_sync_btn.pressed.connect(_sync_with_cloud)
	_studio_btn.pressed.connect(_open_web_studio)
	_menu_btn.get_popup().id_pressed.connect(_on_menu_id_pressed)
	_update_apply_btn.pressed.connect(_on_apply_update_pressed)

	_google_signin_btn.pressed.connect(_on_google_signin_pressed)
	_cancel_signin_btn.pressed.connect(_on_cancel_signin_pressed)
	_toggle_token_btn.pressed.connect(func() -> void:
		_show_token_fallback = not _show_token_fallback
		_token_row.visible = _show_token_fallback
	)
	_token_save_btn.pressed.connect(_on_save_token_pressed)
	_token_input.text_submitted.connect(func(_t: String) -> void: _on_save_token_pressed())

	_epic_selector.item_selected.connect(_on_epic_selected)
	_primary_cta_btn.pressed.connect(_on_primary_cta_pressed)
	_play_btn.pressed.connect(_on_play_pressed)
	_undo_btn.pressed.connect(_on_undo_pressed)
	_pass_reopen_btn.pressed.connect(_on_pass_reopen_pressed)
	_clear_errors_btn.pressed.connect(clear_captured_errors)
	_auto_fix_errors_btn.pressed.connect(func() -> void:
		_auto_heal_attempted = false
		_trigger_epic_agent("fix_epic")
	)
	_flag_fix_btn.pressed.connect(_on_flag_fix_pressed)
	_fix_input.text_submitted.connect(func(_t: String) -> void: _on_flag_fix_pressed())

	if _sync_client != null:
		_sync_client.connect("epic_updated", _on_epic_updated)
		_sync_client.connect("sync_failed", _on_sync_failed)
		_sync_client.connect("busy_changed", _on_busy_changed)
		_sync_client.connect("agent_busy_changed", _on_agent_busy_changed)
		_sync_client.connect("agent_bundle_received", _on_agent_bundle_received)
		_sync_client.connect("auth_completed", _on_auth_completed)
		_sync_client.connect("auth_status_changed", _on_auth_status_changed)
		_sync_client.connect("update_available", _on_update_available)
		_sync_client.connect("update_check_finished", _on_update_check_finished)
		_sync_client.connect("update_ready_to_reload", _on_update_ready_to_reload)
		_sync_client.connect("update_failed", _on_update_failed)


func on_editor_scene_changed(_scene_root: Node) -> void:
	_refresh_errors_card()


func on_editor_scene_saved(_filepath: String) -> void:
	_refresh_errors_card()


func on_editor_resource_saved(_resource: Resource) -> void:
	_refresh_errors_card()


func notify_editor_state_changed() -> void:
	_refresh_errors_card()


func _as_editor_interface() -> EditorInterface:
	return editor_interface as EditorInterface if editor_interface is EditorInterface else null


func _extract_tscn_paths_from_text(raw_text: String) -> PackedStringArray:
	var out := PackedStringArray()
	if raw_text.strip_edges().is_empty():
		return out
	var rx := RegEx.new()
	rx.compile("res://[A-Za-z0-9_./-]+\\.tscn")
	for m in rx.search_all(raw_text):
		var p: String = m.get_string(0).strip_edges()
		if not p.is_empty() and not (p in out):
			out.append(p)
	return out


func _resolve_play_scene_path() -> String:
	var candidates := PackedStringArray()
	if not _last_built_scene_path.strip_edges().is_empty():
		candidates.append(_last_built_scene_path.strip_edges())
	var arena_scene: String = str(_payload.get("arenaScenePath", "")).strip_edges()
	if not arena_scene.is_empty():
		candidates.append(arena_scene)
	var epic: Dictionary = _get_active_epic()
	if not epic.is_empty():
		for sp in _extract_tscn_paths_from_text(str(epic.get("levelStaging", ""))):
			candidates.append(sp)
		var links_v: Variant = epic.get("links", [])
		if typeof(links_v) == TYPE_ARRAY:
			for lk in (links_v as Array):
				for sp2 in _extract_tscn_paths_from_text(str(lk)):
					candidates.append(sp2)
	var main_sc: String = str(ProjectSettings.get_setting("application/run/main_scene", "")).strip_edges()
	if not main_sc.is_empty():
		candidates.append(main_sc)
	if editor_interface != null and editor_interface.has_method("get_edited_scene_root"):
		var ed_raw: Variant = editor_interface.call("get_edited_scene_root")
		if ed_raw != null and ed_raw is Node:
			var ed_path: String = String((ed_raw as Node).scene_file_path).strip_edges()
			if not ed_path.is_empty():
				candidates.append(ed_path)
	if _executor != null and _executor.has_method("collect_project_scene_paths"):
		var proj_raw: Variant = _executor.call("collect_project_scene_paths", "res://", 8)
		if typeof(proj_raw) == TYPE_ARRAY or typeof(proj_raw) == TYPE_PACKED_STRING_ARRAY:
			for ps in proj_raw:
				candidates.append(str(ps).strip_edges())
	for c in candidates:
		if not c.is_empty() and c.ends_with(".tscn") and FileAccess.file_exists(c):
			return c
	return ""


func refresh_from_focus() -> void:
	if _sync_client != null and bool(_sync_client.call("has_link_token")) and not bool(_sync_client.call("is_busy")) and not bool(_sync_client.call("is_waiting_for_auth")):
		_sync_with_cloud()


func _collect_recent_errors() -> Array[String]:
	var errs: Array[String] = []
	var logger_errs: Array[String] = []
	if _logger != null:
		logger_errs = _logger.snapshot_errors(_errors_cleared_unix)
		for le in logger_errs:
			_ignored_error_signatures.erase(le)
			if not errs.has(le):
				errs.append(le)
	var base_ctrl: Node = null
	if editor_interface != null and editor_interface.has_method("get_base_control"):
		var bc_raw: Variant = editor_interface.call("get_base_control")
		if bc_raw is Node:
			base_ctrl = bc_raw as Node
	if _executor != null and (base_ctrl != null or not logger_errs.is_empty()):
		var ed_raw: Variant = _executor.call(
			"read_editor_and_playtest_errors",
			base_ctrl,
			logger_errs,
			_ignored_error_signatures,
			_errors_cleared_unix,
			5
		)
		if typeof(ed_raw) == TYPE_ARRAY or typeof(ed_raw) == TYPE_PACKED_STRING_ARRAY:
			for e in ed_raw:
				var es: String = str(e).strip_edges()
				if not es.is_empty() and not _ignored_error_signatures.has(es) and not errs.has(es):
					errs.append(es)
	return errs


func _acknowledge_resolved_errors() -> void:
	var cur_errs: Array[String] = _collect_recent_errors()
	for e in cur_errs:
		_ignored_error_signatures[e] = true
	_errors_cleared_unix = Time.get_unix_time_from_system()
	if _logger != null:
		_logger.clear()


func clear_captured_errors() -> void:
	_acknowledge_resolved_errors()
	_refresh_ui()
	_set_status("Cleared captured errors.", false)


func inject_test_error(msg: String) -> void:
	var clean: String = msg.strip_edges().left(340)
	if clean.is_empty():
		return
	if _logger == null:
		_logger = _LayersEditorLogger.new()
	_ignored_error_signatures.erase(clean)
	_logger.inject(clean)
	_refresh_ui()


func _collect_live_context() -> Dictionary:
	var errs: Array[String] = _collect_recent_errors()
	if _executor != null:
		var ctx_v: Variant = _executor.call("collect_godot_project_context", editor_interface, errs)
		if typeof(ctx_v) == TYPE_DICTIONARY:
			return ctx_v as Dictionary
	return {"recent_errors": errs}


func _sync_with_cloud(preferred_epic_id: String = "") -> void:
	if _sync_client == null or not bool(_sync_client.call("has_link_token")):
		_refresh_ui()
		return
	var live_ctx: Dictionary = _collect_live_context()
	_sync_client.call("fetch_active_epic", live_ctx, preferred_epic_id)


func _open_web_studio() -> void:
	var url: String = str(_payload.get("webStudioUrl", DEFAULT_WEB_STUDIO_URL)).strip_edges()
	if url.is_empty():
		url = DEFAULT_WEB_STUDIO_URL
	OS.shell_open(url)


func _on_menu_id_pressed(id: int) -> void:
	match id:
		1:
			_on_google_signin_pressed()
		2:
			if _sync_client != null:
				_manual_update_check = true
				_set_status("Checking GitHub for LAYERS plugin updates...", false)
				_sync_client.call("check_for_plugin_update", false)
		3:
			clear_captured_errors()
		4:
			if _sync_client != null:
				_sync_client.call("clear_link_token")
			_payload = {}
			_last_bundle_snapshot = {}
			_last_built_scene_path = ""
			_ignored_error_signatures.clear()
			_errors_cleared_unix = 0.0
			_set_status("Unlinked project.", false)
			_refresh_ui()


func _on_google_signin_pressed() -> void:
	if _sync_client == null:
		return
	var ctx: Dictionary = _collect_live_context()
	var proj_name: String = str(ctx.get("project_name", "GodotProject"))
	_sync_client.call("start_google_sign_in", proj_name, DEFAULT_WEB_STUDIO_URL, true)
	_refresh_ui()


func _on_cancel_signin_pressed() -> void:
	if _sync_client != null:
		_sync_client.call("cancel_google_sign_in")
	_refresh_ui()


func _on_save_token_pressed() -> void:
	var tok: String = _token_input.text.strip_edges()
	if not (tok.begins_with("lyr_") and tok.length() >= 20):
		_set_status("Enter a valid lyr_... token copied from LAYERS Web Studio.", true)
		return
	_token_input.text = ""
	if _sync_client != null:
		_sync_client.call("save_link_token", tok)
	_set_status("Token saved! Syncing active Epic...", false)
	_sync_with_cloud()


func _on_auth_completed(project_title: String) -> void:
	_set_status("Connected to %s! Pulling active Epic..." % (project_title if not project_title.is_empty() else "LAYERS"), false)
	_sync_with_cloud()


func _on_auth_status_changed(waiting: bool, message: String) -> void:
	_cancel_signin_btn.visible = waiting
	if _google_signin_btn != null:
		_google_signin_btn.text = "Waiting for Browser Sign-In..." if waiting else "⚡ Sign in with Google"
		_google_signin_btn.disabled = waiting
	if not message.is_empty():
		_set_status(message, false)


func _on_epic_updated(new_payload: Dictionary) -> void:
	_payload = new_payload
	_refresh_ui()


func _on_sync_failed(message: String) -> void:
	_auto_heal_attempted = false
	_set_status(message, true)
	_refresh_ui()


func _on_busy_changed(busy: bool) -> void:
	if _sync_btn != null:
		_sync_btn.disabled = busy


func _on_agent_busy_changed(agent_busy: bool) -> void:
	_primary_cta_btn.disabled = agent_busy
	_auto_fix_errors_btn.disabled = agent_busy
	_pass_reopen_btn.disabled = agent_busy
	_epic_selector.disabled = agent_busy
	_flag_fix_btn.disabled = agent_busy


func _on_epic_selected(idx: int) -> void:
	if idx < 0 or _epic_selector == null:
		return
	var meta_v: Variant = _epic_selector.get_item_metadata(idx)
	var eid: String = str(meta_v).strip_edges()
	if not eid.is_empty():
		_sync_with_cloud(eid)


func _get_active_epic() -> Dictionary:
	var ep_v: Variant = _payload.get("activeEpic", {})
	if typeof(ep_v) == TYPE_DICTIONARY:
		return ep_v as Dictionary
	return {}


func _get_active_epic_open_fixes_count(epic: Dictionary) -> int:
	var raw_open: Variant = epic.get("openFixes", null)
	if typeof(raw_open) == TYPE_ARRAY:
		return (raw_open as Array).size()
	return int(epic.get("openFixesCount", 0))


func _sync_active_epic_summary_counts() -> void:
	var epic: Dictionary = _get_active_epic()
	if epic.is_empty():
		return
	var active_id: String = str(epic.get("id", ""))
	var open_fixes: int = _get_active_epic_open_fixes_count(epic)
	epic["openFixesCount"] = open_fixes
	var checks_raw: Variant = epic.get("checks", [])
	var checks: Array = checks_raw as Array if typeof(checks_raw) == TYPE_ARRAY else []
	var passed_count: int = 0
	for cv in checks:
		if typeof(cv) == TYPE_DICTIONARY and bool((cv as Dictionary).get("passed", false)):
			passed_count += 1
	epic["passedChecksCount"] = passed_count
	var summary_v: Variant = _payload.get("releaseEpicsSummary", [])
	if typeof(summary_v) == TYPE_ARRAY:
		for sv in (summary_v as Array):
			if typeof(sv) == TYPE_DICTIONARY and str((sv as Dictionary).get("id", "")) == active_id:
				var sd: Dictionary = sv as Dictionary
				sd["openFixesCount"] = open_fixes
				sd["passedChecksCount"] = passed_count
				sd["isPassed"] = bool(epic.get("isPassed", false))


func compute_primary_cta_state() -> Dictionary:
	var epic: Dictionary = _get_active_epic()
	if epic.is_empty():
		return {"mode": "sync", "text": "↻ Sync Epics", "issue_count": 0}
	var ecode: String = str(epic.get("code", "E01"))
	var open_fixes: int = _get_active_epic_open_fixes_count(epic)
	var errs: Array[String] = _collect_recent_errors()
	var issue_count: int = open_fixes + errs.size()
	var checks_raw: Variant = epic.get("checks", [])
	var checks: Array = checks_raw as Array if typeof(checks_raw) == TYPE_ARRAY else []
	var passed_count: int = 0
	if not checks.is_empty():
		for cv in checks:
			if typeof(cv) == TYPE_DICTIONARY and bool((cv as Dictionary).get("passed", false)):
				passed_count += 1
	else:
		passed_count = int(epic.get("passedChecksCount", 0))
	var is_passed: bool = bool(epic.get("isPassed", false))

	if issue_count > 0:
		return {"mode": "fix", "text": "🔧 Fix %s (%d)" % [ecode, issue_count], "issue_count": issue_count}
	if not is_passed and not checks.is_empty() and passed_count >= checks.size():
		return {"mode": "pass", "text": "✓ Pass %s →" % ecode, "issue_count": 0}
	return {
		"mode": "build",
		"text": ("⚡ Rebuild %s" % ecode) if is_passed else ("⚡ Build %s" % ecode),
		"issue_count": 0,
	}


func _on_primary_cta_pressed() -> void:
	var epic: Dictionary = _get_active_epic()
	if epic.is_empty():
		_sync_with_cloud()
		return
	var cta: Dictionary = compute_primary_cta_state()
	var mode: String = str(cta.get("mode", "build"))
	if mode == "pass":
		if _sync_client != null:
			_sync_client.call("push_epic_mutation", {
				"action": "pass_epic",
				"epicId": str(epic.get("id", "")),
			}, _collect_live_context())
		return
	_auto_heal_attempted = false
	if mode == "fix":
		_trigger_epic_agent("fix_epic")
	else:
		_trigger_epic_agent("build_epic")


func _trigger_epic_agent(action: String, extra_error_text: String = "") -> void:
	if _sync_client == null or _executor == null:
		return
	var epic: Dictionary = _get_active_epic()
	if epic.is_empty():
		return
	var epic_id: String = str(epic.get("id", ""))
	var dim_str: String = str(_payload.get("dimension", "dim3d")).strip_edges().to_lower()
	var default_arena: String = "res://scenes/arena_2d.tscn" if dim_str == "dim2d" else "res://scenes/arena_3d.tscn"
	var arena_scene: String = str(_payload.get("arenaScenePath", "")).strip_edges()
	if arena_scene.is_empty():
		arena_scene = _resolve_play_scene_path()
	if arena_scene.is_empty():
		arena_scene = default_arena
	var live_ctx: Dictionary = _collect_live_context()

	var ed_int: EditorInterface = _as_editor_interface()
	var live_scripts_v: Variant = _executor.call("read_all_live_project_scripts", "res://", ed_int)
	var live_scripts: Dictionary = live_scripts_v as Dictionary if typeof(live_scripts_v) == TYPE_DICTIONARY else {}

	var diag_scenes: Array = []
	var extra_scenes := PackedStringArray()
	for cand in [arena_scene, _resolve_play_scene_path()]:
		var cs: String = str(cand).strip_edges()
		if not cs.is_empty() and cs.ends_with(".tscn") and not (cs in extra_scenes):
			extra_scenes.append(cs)
			diag_scenes.append(cs)
	for sp_lvl in _extract_tscn_paths_from_text(str(epic.get("levelStaging", ""))):
		if not (sp_lvl in extra_scenes):
			extra_scenes.append(sp_lvl)
			diag_scenes.append(sp_lvl)
	var links_v: Variant = epic.get("links", [])
	if typeof(links_v) == TYPE_ARRAY:
		for lk in (links_v as Array):
			for sp_lk in _extract_tscn_paths_from_text(str(lk)):
				if not (sp_lk in extra_scenes):
					extra_scenes.append(sp_lk)
					diag_scenes.append(sp_lk)

	var snap_v: Variant = _executor.call("capture_rich_scene_snapshot", ed_int, extra_scenes)
	var input_v: Variant = _executor.call("capture_input_map_snapshot")
	var input_snap: Dictionary = input_v as Dictionary if typeof(input_v) == TYPE_DICTIONARY else {}
	var diag_v: Variant = _executor.call("diagnose_project_combat_and_wiring", diag_scenes, live_scripts, ed_int)
	var diag_arr: Array = diag_v as Array if typeof(diag_v) == TYPE_ARRAY or typeof(diag_v) == TYPE_PACKED_STRING_ARRAY else []

	var errs: Array[String] = _collect_recent_errors()
	if not extra_error_text.strip_edges().is_empty():
		errs.append(extra_error_text.strip_edges())
	var open_fixes_v: Variant = epic.get("openFixes", [])
	var prompt_parts := PackedStringArray()
	if typeof(open_fixes_v) == TYPE_ARRAY:
		for fx_raw in (open_fixes_v as Array):
			if typeof(fx_raw) == TYPE_DICTIONARY:
				var fxt: String = str((fx_raw as Dictionary).get("text", "")).strip_edges()
				if not fxt.is_empty():
					prompt_parts.append("[FIX] " + fxt)

	_pending_build_preferred_scene = arena_scene
	_set_status(
		"%s %s via Cloud Gemini..." % ["🔧 Fixing" if action == "fix_epic" else "⚡ Building", str(epic.get("code", "Epic"))],
		false
	)
	_sync_client.call(
		"run_epic_agent",
		action,
		epic_id,
		snap_v,
		live_scripts,
		live_ctx,
		arena_scene,
		arena_scene,
		"\n".join(prompt_parts),
		"\n".join(errs),
		input_snap,
		diag_arr
	)


func _on_agent_bundle_received(agent_bundle: Dictionary, _payload_resp: Dictionary) -> void:
	if _executor == null or agent_bundle.is_empty():
		_set_status("Cloud Gemini returned empty bundle.", true)
		return

	var ed_int: EditorInterface = _as_editor_interface()
	var snap_v: Variant = _executor.call(
		"capture_bundle_snapshot",
		ed_int,
		agent_bundle,
		_pending_build_preferred_scene
	)
	if typeof(snap_v) == TYPE_DICTIONARY:
		_last_bundle_snapshot = snap_v as Dictionary
		_undo_btn.disabled = _last_bundle_snapshot.is_empty()

	var res_v: Variant = _executor.call(
		"apply_agent_bundle",
		ed_int,
		undo_redo,
		agent_bundle,
		_pending_build_preferred_scene
	)
	var res: Dictionary = res_v as Dictionary if typeof(res_v) == TYPE_DICTIONARY else {}

	for cand_path in [agent_bundle.get("epicScenePath", ""), agent_bundle.get("arenaScenePath", ""), _pending_build_preferred_scene]:
		var cp: String = str(cand_path).strip_edges()
		if not cp.is_empty() and cp.ends_with(".tscn") and FileAccess.file_exists(cp):
			_last_built_scene_path = cp
			break

	if ed_int != null:
		var rfs: Variant = ed_int.get_resource_filesystem()
		if rfs != null and rfs.has_method("scan"):
			rfs.call("scan")

	var compile_errs_v: Variant = res.get("compile_errors", PackedStringArray())
	var compile_errs: PackedStringArray = compile_errs_v as PackedStringArray if (typeof(compile_errs_v) == TYPE_PACKED_STRING_ARRAY or typeof(compile_errs_v) == TYPE_ARRAY) else PackedStringArray()
	if not compile_errs.is_empty() and not _auto_heal_attempted:
		_auto_heal_attempted = true
		var joined_err: String = "\n".join(compile_errs)
		_set_status("Auto-healing GDScript compile error...", true)
		_trigger_epic_agent("fix_epic", joined_err)
		return

	_auto_heal_attempted = false
	var summary: String = str(res.get("summary", agent_bundle.get("summary", "Applied Epic build.")))
	if not compile_errs.is_empty():
		_set_status("Applied with compile warning: %s" % compile_errs[0], true)
	else:
		_acknowledge_resolved_errors()
		var epic: Dictionary = _get_active_epic()
		if _get_active_epic_open_fixes_count(epic) > 0:
			_set_status("%s — press ▶ Play, then click ✓ on resolved [FIX] items." % summary, false)
		else:
			_set_status(summary, false)
	_refresh_ui()


func _on_play_pressed() -> void:
	if editor_interface == null:
		return
	var target_scene: String = _resolve_play_scene_path()
	if target_scene.is_empty():
		var epic: Dictionary = _get_active_epic()
		var ecode: String = str(epic.get("code", "E01"))
		_set_status("No scene built yet — click ⚡ Build %s first." % ecode, true)
		return
	if editor_interface.has_method("save_scene"):
		editor_interface.call("save_scene")
	if editor_interface.has_method("play_custom_scene"):
		editor_interface.call("play_custom_scene", target_scene)
	elif editor_interface.has_method("play_main_scene"):
		editor_interface.call("play_main_scene")


func _on_undo_pressed() -> void:
	if _executor == null or _last_bundle_snapshot.is_empty():
		return
	var ed_int: EditorInterface = _as_editor_interface()
	var res_v: Variant = _executor.call("restore_bundle_snapshot", ed_int, _last_bundle_snapshot)
	var res: Dictionary = res_v as Dictionary if typeof(res_v) == TYPE_DICTIONARY else {}
	if bool(res.get("ok", false)):
		_last_bundle_snapshot = {}
		_undo_btn.disabled = true
		if ed_int != null and ed_int.get_resource_filesystem() != null:
			ed_int.get_resource_filesystem().scan()
		_set_status("Restored pre-build project snapshot.", false)
	else:
		_set_status("Nothing to undo.", true)


func toggle_epic_check_by_id(check_id: String, pressed: bool) -> void:
	var epic: Dictionary = _get_active_epic()
	if epic.is_empty():
		return
	var checks_v: Variant = epic.get("checks", [])
	if typeof(checks_v) == TYPE_ARRAY:
		for cv in (checks_v as Array):
			if typeof(cv) == TYPE_DICTIONARY and str((cv as Dictionary).get("id", "")) == check_id:
				(cv as Dictionary)["passed"] = pressed
				break
	_sync_active_epic_summary_counts()
	_refresh_ui()
	if _sync_client != null and bool(_sync_client.call("has_link_token")):
		_sync_client.call("push_epic_mutation", {
			"action": "toggle_check",
			"epicId": str(epic.get("id", "")),
			"checkId": check_id,
			"passed": pressed,
		}, _collect_live_context())


func log_epic_fix_text(raw_text: String) -> String:
	var txt: String = raw_text.strip_edges()
	var epic: Dictionary = _get_active_epic()
	if txt.is_empty() or epic.is_empty():
		return ""
	var fix_id: String = "fix_%d_%04d" % [int(Time.get_unix_time_from_system() * 1000.0), randi() % 10000]
	var open_v: Variant = epic.get("openFixes", null)
	if typeof(open_v) != TYPE_ARRAY:
		open_v = []
		epic["openFixes"] = open_v
	(open_v as Array).append({
		"id": fix_id,
		"text": txt,
		"resolved": false,
	})
	_sync_active_epic_summary_counts()
	_refresh_ui()
	_set_status("Logged [FIX] revision on %s." % str(epic.get("code", "Epic")), false)
	if _sync_client != null and bool(_sync_client.call("has_link_token")):
		_sync_client.call("push_epic_mutation", {
			"action": "log_fix",
			"epicId": str(epic.get("id", "")),
			"fixId": fix_id,
			"fixText": txt,
		}, _collect_live_context())
	return fix_id


func resolve_epic_fix_by_id(fix_id: String) -> void:
	var epic: Dictionary = _get_active_epic()
	if epic.is_empty():
		return
	var open_v: Variant = epic.get("openFixes", [])
	if typeof(open_v) == TYPE_ARRAY:
		var arr: Array = open_v as Array
		for i in range(arr.size() - 1, -1, -1):
			if typeof(arr[i]) == TYPE_DICTIONARY and str((arr[i] as Dictionary).get("id", "")) == fix_id:
				arr.remove_at(i)
	_sync_active_epic_summary_counts()
	_refresh_ui()
	_set_status("Marked [FIX] resolved.", false)
	if _sync_client != null and bool(_sync_client.call("has_link_token")):
		_sync_client.call("push_epic_mutation", {
			"action": "resolve_fix",
			"epicId": str(epic.get("id", "")),
			"fixId": fix_id,
			"resolved": true,
		}, _collect_live_context())


func apply_epic_tuning_value(tkey: String, next_v: String, tunit: String = "") -> void:
	var clean_val: String = next_v.strip_edges()
	var epic: Dictionary = _get_active_epic()
	if clean_val.is_empty() or epic.is_empty():
		return
	var tuning_v: Variant = epic.get("tuning", [])
	if typeof(tuning_v) == TYPE_ARRAY:
		for tv in (tuning_v as Array):
			if typeof(tv) == TYPE_DICTIONARY and str((tv as Dictionary).get("key", "")) == tkey:
				(tv as Dictionary)["value"] = clean_val
				break
	var local_updated := false
	if _executor != null and _executor.has_method("apply_live_export_tuning"):
		var tune_res_v: Variant = _executor.call(
			"apply_live_export_tuning",
			_as_editor_interface(),
			tkey,
			clean_val,
			tunit,
			_resolve_play_scene_path()
		)
		if typeof(tune_res_v) == TYPE_DICTIONARY:
			local_updated = bool((tune_res_v as Dictionary).get("ok", false))
	if _sync_client != null and bool(_sync_client.call("has_link_token")):
		_sync_client.call("push_epic_mutation", {
			"action": "update_tuning",
			"epicId": str(epic.get("id", "")),
			"key": tkey,
			"value": clean_val,
			"unit": tunit,
		}, _collect_live_context())
	if local_updated:
		_set_status("Updated %s = %s %s in local .gd/.tscn and Web Studio." % [tkey, clean_val, tunit], false)
	else:
		_set_status("Updated %s = %s %s in Web Studio." % [tkey, clean_val, tunit], false)


func _on_pass_reopen_pressed() -> void:
	var epic: Dictionary = _get_active_epic()
	if epic.is_empty() or _sync_client == null:
		return
	var action: String = "reopen_epic" if bool(epic.get("isPassed", false)) else "pass_epic"
	_sync_client.call("push_epic_mutation", {
		"action": action,
		"epicId": str(epic.get("id", "")),
	}, _collect_live_context())


func _on_flag_fix_pressed() -> void:
	var txt: String = _fix_input.text.strip_edges()
	if txt.is_empty():
		return
	_fix_input.text = ""
	log_epic_fix_text(txt)


func _on_update_available(_local_ver: String, remote_ver: String) -> void:
	_manual_update_check = false
	_available_update_ver = remote_ver
	_update_label.text = "LAYERS v%s available" % remote_ver
	_update_banner.visible = true


func _on_update_check_finished(up_to_date: bool, local_ver: String, _remote_ver: String) -> void:
	var was_manual: bool = _manual_update_check
	_manual_update_check = false
	if was_manual and up_to_date:
		_set_status("LAYERS plugin v%s is up to date." % local_ver, false)


func _on_apply_update_pressed() -> void:
	if _sync_client == null:
		return
	_update_apply_btn.disabled = true
	_set_status("Updating LAYERS plugin...", false)
	_sync_client.call("download_and_apply_plugin_update")


func _on_update_ready_to_reload(new_ver: String, _updated_gd_paths: PackedStringArray) -> void:
	_update_banner.visible = false
	_update_apply_btn.disabled = false
	_set_status("Updated plugin to v%s. Disable & re-enable LAYERS in Project Settings → Plugins to reload." % new_ver, false)


func _on_update_failed(message: String) -> void:
	_manual_update_check = false
	_update_apply_btn.disabled = false
	_set_status(message, true)


func _set_status(msg: String, is_err: bool) -> void:
	_status_message = msg.strip_edges()
	_status_is_error = is_err
	if _status_label != null:
		_status_label.text = _status_message
		_status_label.visible = not _status_message.is_empty()
		if _status_is_error:
			_status_label.add_theme_color_override("font_color", Color(0.97, 0.44, 0.44))
		else:
			_status_label.add_theme_color_override("font_color", Color(0.45, 0.85, 0.72))


func _refresh_errors_card() -> void:
	if _errors_card == null or _errors_list_box == null:
		return
	for ch in _errors_list_box.get_children():
		ch.queue_free()
	var errs: Array[String] = _collect_recent_errors()
	_errors_card.visible = not errs.is_empty()
	for e in errs.slice(0, 5):
		var lbl := Label.new()
		lbl.text = "• %s" % e
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.97, 0.65, 0.45))
		_errors_list_box.add_child(lbl)


func _refresh_ui() -> void:
	var linked: bool = _sync_client != null and bool(_sync_client.call("has_link_token"))
	var waiting_auth: bool = _sync_client != null and bool(_sync_client.call("is_waiting_for_auth"))

	_unlinked_panel.visible = not linked
	_cancel_signin_btn.visible = waiting_auth
	if _google_signin_btn != null:
		_google_signin_btn.text = "Waiting for Browser Sign-In..." if waiting_auth else "⚡ Sign in with Google"
		_google_signin_btn.disabled = waiting_auth
	_linked_scroll.visible = linked
	_sync_btn.visible = linked

	var dim_id: String = str(_payload.get("dimension", "dim3d")).strip_edges().to_lower()
	_dim_badge.text = "2D" if dim_id == "dim2d" else "3D"
	_undo_btn.disabled = _last_bundle_snapshot.is_empty()

	_refresh_errors_card()
	if not linked:
		return

	var proj_title: String = str(_payload.get("projectTitle", "LAYERS Project"))
	var rel_ver: String = str(_payload.get("releaseVersion", "v0.1"))
	var pos: int = int(_payload.get("epicPosition", 0))
	var total: int = int(_payload.get("totalEpics", 0))
	_project_meta_label.text = "%s · %s (%d/%d Epics)" % [proj_title, rel_ver, pos, total]

	var epic: Dictionary = _get_active_epic()
	var active_eid: String = str(epic.get("id", ""))

	# Populate Epic OptionButton
	_epic_selector.clear()
	var summary_v: Variant = _payload.get("releaseEpicsSummary", [])
	var selected_dropdown_idx: int = -1
	if typeof(summary_v) == TYPE_ARRAY:
		var summary_arr: Array = summary_v as Array
		for i in range(summary_arr.size()):
			if typeof(summary_arr[i]) != TYPE_DICTIONARY:
				continue
			var sdict: Dictionary = summary_arr[i] as Dictionary
			var sid: String = str(sdict.get("id", ""))
			var scode: String = str(sdict.get("code", "E01"))
			var stitle: String = str(sdict.get("title", "Epic"))
			var s_passed: bool = bool(sdict.get("isPassed", false))
			var s_fixes: int = int(sdict.get("openFixesCount", 0))
			var icon_tag: String = "✓" if s_passed else ("!" if s_fixes > 0 else "→")
			_epic_selector.add_item("%s %s · %s" % [icon_tag, scode, stitle])
			var item_idx: int = _epic_selector.item_count - 1
			_epic_selector.set_item_metadata(item_idx, sid)
			if sid == active_eid:
				selected_dropdown_idx = item_idx
	if selected_dropdown_idx >= 0:
		_epic_selector.select(selected_dropdown_idx)

	if epic.is_empty():
		_goal_label.text = "No active Epic yet. Approve Epics in LAYERS Web Studio and click ↻ Sync."
		_primary_cta_btn.text = "↻ Sync Epics"
		return

	var ecode: String = str(epic.get("code", "E01"))
	var checks_v: Variant = epic.get("checks", [])
	var checks: Array = checks_v as Array if typeof(checks_v) == TYPE_ARRAY else []
	var is_passed: bool = bool(epic.get("isPassed", false))
	var cta: Dictionary = compute_primary_cta_state()
	_primary_cta_btn.text = str(cta.get("text", "⚡ Build %s" % ecode))

	_goal_label.text = str(epic.get("goal", ""))

	# Upgrade deltas
	for ch in _deltas_box.get_children():
		ch.queue_free()
	var deltas_v: Variant = epic.get("upgradeDeltas", [])
	if typeof(deltas_v) == TYPE_ARRAY:
		for dv in (deltas_v as Array):
			var d_lbl := Label.new()
			d_lbl.text = "• +%s" % str(dv).strip_edges().trim_prefix("+").strip_edges()
			d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d_lbl.add_theme_font_size_override("font_size", 11)
			d_lbl.add_theme_color_override("font_color", Color(0.49, 0.83, 0.99))
			_deltas_box.add_child(d_lbl)

	# §04 Tuning rows
	for ch in _tuning_box.get_children():
		ch.queue_free()
	var tuning_v: Variant = epic.get("tuning", [])
	if typeof(tuning_v) == TYPE_ARRAY:
		for tv in (tuning_v as Array):
			if typeof(tv) != TYPE_DICTIONARY:
				continue
			var td: Dictionary = tv as Dictionary
			var tkey: String = str(td.get("key", ""))
			var tval: String = str(td.get("value", "0"))
			var tunit: String = str(td.get("unit", ""))

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			_tuning_box.add_child(row)

			var klbl := Label.new()
			klbl.text = tkey
			klbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			klbl.add_theme_font_size_override("font_size", 11)
			row.add_child(klbl)

			var v_edit := LineEdit.new()
			v_edit.text = tval
			v_edit.custom_minimum_size = Vector2(68, 0)
			row.add_child(v_edit)

			if not tunit.is_empty():
				var ulbl := Label.new()
				ulbl.text = tunit
				ulbl.add_theme_font_size_override("font_size", 10)
				row.add_child(ulbl)

			var set_btn := Button.new()
			set_btn.text = "Set"
			row.add_child(set_btn)

			var commit_tuning := func() -> void:
				apply_epic_tuning_value(tkey, v_edit.text, tunit)

			set_btn.pressed.connect(commit_tuning)
			v_edit.text_submitted.connect(func(_s: String) -> void: commit_tuning.call())

	# §06 Playtest Gate checkboxes
	for ch in _checks_box.get_children():
		ch.queue_free()
	for cv in checks:
		if typeof(cv) != TYPE_DICTIONARY:
			continue
		var cd: Dictionary = cv as Dictionary
		var cid: String = str(cd.get("id", ""))
		var ctext: String = str(cd.get("text", ""))
		var cpassed: bool = bool(cd.get("passed", false))
		var cb := CheckBox.new()
		cb.text = ctext
		cb.button_pressed = cpassed
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.toggled.connect(func(pressed: bool) -> void:
			toggle_epic_check_by_id(cid, pressed)
		)
		_checks_box.add_child(cb)

	_pass_reopen_btn.text = "↺ Reopen %s" % ecode if is_passed else "✓ Pass %s Gate" % ecode

	# Open [FIX] items
	for ch in _fixes_box.get_children():
		ch.queue_free()
	var open_fixes_v: Variant = epic.get("openFixes", [])
	if typeof(open_fixes_v) == TYPE_ARRAY and not (open_fixes_v as Array).is_empty():
		for fv in (open_fixes_v as Array):
			if typeof(fv) != TYPE_DICTIONARY:
				continue
			var fd: Dictionary = fv as Dictionary
			var fid: String = str(fd.get("id", ""))
			var ftext: String = str(fd.get("text", ""))

			var frow := HBoxContainer.new()
			frow.add_theme_constant_override("separation", 6)
			_fixes_box.add_child(frow)

			var flbl := Label.new()
			flbl.text = "[FIX] %s" % ftext
			flbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			flbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			flbl.add_theme_font_size_override("font_size", 11)
			flbl.add_theme_color_override("font_color", Color(0.97, 0.55, 0.55))
			frow.add_child(flbl)

			var res_btn := Button.new()
			res_btn.text = "✓"
			res_btn.tooltip_text = "Mark [FIX] resolved"
			res_btn.pressed.connect(func() -> void:
				resolve_epic_fix_by_id(fid)
			)
			frow.add_child(res_btn)
	else:
		var none_lbl := Label.new()
		none_lbl.text = "No open [FIX] revisions."
		none_lbl.add_theme_font_size_override("font_size", 11)
		_fixes_box.add_child(none_lbl)
