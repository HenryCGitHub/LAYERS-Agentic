@tool
extends VBoxContainer

const SYNC_CLIENT_SCRIPT_PATH := "res://addons/layers/layers_sync_client.gd"
const DEFAULT_WEB_STUDIO_URL := "https://henrycgithub.github.io/LAYERS-Agentic/"

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager

var _sync: Node
var _payload: Dictionary = {}
var _selected_feature_id: String = ""
var _selected_step_idx: int = 0
var _show_patch_preview: bool = false
var _fix_drawer_open: bool = false
var _diagnosing_fix: bool = false
var _fix_draft_text: String = ""
var _show_token_editor: bool = false
var _available_remote_version: String = ""
var _updating_plugin: bool = false
var _checking_plugin_update: bool = false

# Slim Top Self-Update Banner
var _update_banner: PanelContainer
var _update_banner_lbl: Label
var _update_now_btn: Button

# Unlinked / Connect view nodes
var _connect_panel: VBoxContainer
var _token_input: LineEdit
var _connect_btn: Button
var _cancel_token_btn: Button
var _disconnect_btn: Button
var _version_label: Label
var _check_update_btn: Button

# Connected single-Epic single-step workspace nodes
var _workspace_panel: VBoxContainer
var _meta_label: Label
var _epic_label: Label
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
var _sync_btn: Button

# Dynamic inputs bound during step rendering
var _fix_input: LineEdit


func _ready() -> void:
	name = "LAYERS"
	custom_minimum_size = Vector2(280, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	var sync_script: Script = ResourceLoader.load(
		SYNC_CLIENT_SCRIPT_PATH,
		"Script",
		ResourceLoader.CACHE_MODE_REPLACE
	) as Script
	if sync_script == null:
		sync_script = load(SYNC_CLIENT_SCRIPT_PATH) as Script
	_sync = sync_script.new()
	add_child(_sync)
	_sync.epic_updated.connect(_on_epic_updated)
	_sync.sync_failed.connect(_on_sync_failed)
	_sync.busy_changed.connect(_on_busy_changed)
	_sync.update_available.connect(_on_plugin_update_available)
	_sync.update_check_finished.connect(_on_plugin_update_check_finished)
	_sync.update_ready_to_reload.connect(_on_plugin_update_ready_to_reload)
	_sync.update_failed.connect(_on_plugin_update_failed)

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

	_sync.check_for_plugin_update(true)


func refresh_from_focus() -> void:
	if _sync != null and _sync.has_link_token() and not _show_token_editor:
		_sync.fetch_active_epic()


func _build_ui() -> void:
	# --- Slim Top Self-Update Banner (hidden when up to date) ---
	_update_banner = PanelContainer.new()
	_update_banner.visible = false
	_update_banner.add_theme_stylebox_override("panel", _make_box_style(Color(0.08, 0.19, 0.24, 0.96), Color(0.28, 0.78, 0.96, 0.80), 6, 8))
	add_child(_update_banner)

	var banner_hb := HBoxContainer.new()
	banner_hb.add_theme_constant_override("separation", 6)
	_update_banner.add_child(banner_hb)

	_update_banner_lbl = Label.new()
	_update_banner_lbl.text = "⬆ Plugin update available"
	_update_banner_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_banner_lbl.clip_text = true
	_update_banner_lbl.add_theme_font_size_override("font_size", 11)
	_update_banner_lbl.modulate = Color(0.56, 0.92, 1.0)
	banner_hb.add_child(_update_banner_lbl)

	_update_now_btn = Button.new()
	_update_now_btn.text = "Update Now"
	_update_now_btn.modulate = Color(0.45, 0.95, 0.72)
	_update_now_btn.pressed.connect(_on_update_now_pressed)
	banner_hb.add_child(_update_now_btn)

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

	_connect_panel.add_child(HSeparator.new())

	var ver_row := HBoxContainer.new()
	ver_row.add_theme_constant_override("separation", 6)
	_connect_panel.add_child(ver_row)

	_version_label = Label.new()
	_version_label.text = "Plugin v%s" % _sync.get_local_plugin_version()
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_label.clip_text = true
	_version_label.add_theme_font_size_override("font_size", 11)
	_version_label.modulate = Color(0.68, 0.75, 0.85)
	ver_row.add_child(_version_label)

	_check_update_btn = Button.new()
	_check_update_btn.text = "↻ Check for Plugin Update"
	_check_update_btn.pressed.connect(_on_check_plugin_update_pressed)
	ver_row.add_child(_check_update_btn)

	# --- Connected V2.1 Single-Epic Single-Step Workspace ---
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
	_meta_label.modulate = Color(0.45, 0.80, 0.98)
	top_bar.add_child(_meta_label)

	_sync_btn = Button.new()
	_sync_btn.text = "↻"
	_sync_btn.tooltip_text = "Sync active Epic from Web Studio"
	_sync_btn.flat = true
	_sync_btn.pressed.connect(_on_sync_pressed)
	top_bar.add_child(_sync_btn)

	var web_btn := Button.new()
	web_btn.text = "↗"
	web_btn.tooltip_text = "Open Full Specs & Planning in Web Studio"
	web_btn.flat = true
	web_btn.pressed.connect(_on_open_web_pressed)
	top_bar.add_child(web_btn)

	var settings_btn := Button.new()
	settings_btn.text = "⚙"
	settings_btn.tooltip_text = "Plugin Settings, Link Token & Check for Updates"
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

	# Merged 1-Line Step Switcher: [‹] [Step 1/4 · ROLE ▾] [›]
	_step_nav_row = HBoxContainer.new()
	_step_nav_row.add_theme_constant_override("separation", 4)
	_workspace_panel.add_child(_step_nav_row)

	_prev_step_btn = Button.new()
	_prev_step_btn.text = "‹"
	_prev_step_btn.tooltip_text = "Previous step"
	_prev_step_btn.custom_minimum_size = Vector2(28, 0)
	_prev_step_btn.pressed.connect(_on_prev_step_pressed)
	_step_nav_row.add_child(_prev_step_btn)

	_step_picker = OptionButton.new()
	_step_picker.clip_text = true
	_step_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_picker.item_selected.connect(_on_step_selected)
	_step_nav_row.add_child(_step_picker)

	_next_step_btn = Button.new()
	_next_step_btn.text = "›"
	_next_step_btn.tooltip_text = "Next step"
	_next_step_btn.custom_minimum_size = Vector2(28, 0)
	_next_step_btn.pressed.connect(_on_next_step_pressed)
	_step_nav_row.add_child(_next_step_btn)

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

	_step_scroll = ScrollContainer.new()
	_step_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_workspace_panel.add_child(_step_scroll)

	_body_container = VBoxContainer.new()
	_body_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_container.add_theme_constant_override("separation", 8)
	_step_scroll.add_child(_body_container)

	_footer_box = VBoxContainer.new()
	_footer_box.add_theme_constant_override("separation", 4)
	_workspace_panel.add_child(_footer_box)
	_footer_box.add_child(HSeparator.new())

	_primary_cta_btn = Button.new()
	_primary_cta_btn.text = "✓ Complete & Next Step →"
	_primary_cta_btn.pressed.connect(_on_primary_cta_pressed)
	_footer_box.add_child(_primary_cta_btn)

	_status_label = Label.new()
	_status_label.text = "Ctrl+Z supported on native node actions"
	_status_label.clip_text = true
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.modulate = Color(0.65, 0.72, 0.82)
	add_child(_status_label)


func _refresh_update_banner() -> void:
	if _update_banner == null:
		return
	var has_update: bool = not _available_remote_version.is_empty()
	_update_banner.visible = has_update or _updating_plugin
	if _update_banner_lbl != null:
		if _updating_plugin:
			_update_banner_lbl.text = "⏳ Downloading & installing v%s..." % _available_remote_version
		elif has_update:
			_update_banner_lbl.text = "⬆ Plugin v%s available" % _available_remote_version
	if _update_now_btn != null:
		_update_now_btn.disabled = _updating_plugin
		_update_now_btn.text = "⏳ Updating..." if _updating_plugin else "Update Now"


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
	var epic_raw = _payload.get("activeEpic", null)
	var epic_code: String = "E01"
	if typeof(epic_raw) == TYPE_DICTIONARY and epic_raw.has("code"):
		epic_code = str(epic_raw.get("code", "E01"))
	_meta_label.text = "%s · Epic %d/%d · %s" % [ver, pos, max(total, 1), epic_code]

	if all_done:
		_epic_label.text = str(_payload.get("releaseTitle", ver))
		_feature_picker.visible = false
		_step_nav_row.visible = false
		_complete_card.visible = true
		_footer_box.visible = false
		_clear_body()
		return

	_complete_card.visible = false
	if typeof(epic_raw) != TYPE_DICTIONARY or epic_raw.is_empty():
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
			if typeof(st) == TYPE_DICTIONARY and bool(st.get("completed", false)):
				done_cnt += 1
		var f_done: bool = bool(f.get("isCompleted", false))
		var prefix: String = "✓" if f_done else "•"
		_feature_picker.add_item("%s %s (%d/%d)" % [prefix, f_title, done_cnt, f_steps.size()], i)
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
		_show_patch_preview = false

	_render_active_step_workspace(active_feat)


func _find_first_incomplete_step_idx(feat: Dictionary) -> int:
	var steps: Array = feat.get("steps", [])
	for i in range(steps.size()):
		if typeof(steps[i]) == TYPE_DICTIONARY and not bool(steps[i].get("completed", false)):
			return i
	return steps.size()


func _get_active_feature() -> Dictionary:
	var epic_raw = _payload.get("activeEpic", null)
	if typeof(epic_raw) != TYPE_DICTIONARY:
		return {}
	var features: Array = epic_raw.get("features", [])
	for f_raw in features:
		if typeof(f_raw) == TYPE_DICTIONARY and str(f_raw.get("id", "")) == _selected_feature_id:
			return f_raw
	return features[0] if not features.is_empty() and typeof(features[0]) == TYPE_DICTIONARY else {}


func _clear_body() -> void:
	_fix_input = null
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

	# Populate merged step switcher
	_step_nav_row.visible = true
	_step_picker.clear()
	for i in range(steps.size()):
		if typeof(steps[i]) != TYPE_DICTIONARY:
			continue
		var st: Dictionary = steps[i]
		var st_done: bool = bool(st.get("completed", false))
		var st_role: String = str(st.get("role", "CODE"))
		var mark: String = "✓" if st_done else "•"
		_step_picker.add_item("%s Step %d/%d · %s" % [mark, i + 1, steps.size(), st_role], i)

	var gate_passed: bool = bool(feat.get("isPlaytestPassed", false))
	var gate_mark: String = "✓" if gate_passed else "▶"
	_step_picker.add_item("%s Playtest Gate" % gate_mark, max_idx)
	_step_picker.select(_selected_step_idx)

	_prev_step_btn.disabled = _selected_step_idx <= 0
	_next_step_btn.disabled = _selected_step_idx >= max_idx
	_footer_box.visible = true

	if _selected_step_idx == max_idx:
		_render_playtest_gate_card(feat, feat_id, cp_id, gate_passed)
		_render_agent_fix_drawer(feat, feat_id, cp_id)
		_primary_cta_btn.text = "✓ Playtest Passed — Next Feature →"
		_primary_cta_btn.modulate = Color(0.55, 0.96, 0.72)
		return

	var step: Dictionary = steps[_selected_step_idx]
	var step_id: String = str(step.get("id", ""))
	var role: String = str(step.get("role", "CODE"))
	var title: String = str(step.get("title", "Step"))
	var step_path: String = _resolve_effective_step_path(step, feat)
	var instruction: String = str(step.get("instruction", "")).strip_edges()
	if instruction.is_empty():
		instruction = "Complete \"%s\" in %s." % [title, step_path]
	var diagnosis: String = str(step.get("diagnosis", "")).strip_edges()
	var verify_result: String = str(step.get("verifyResult", "")).strip_edges()
	var is_done: bool = bool(step.get("completed", false))

	# Single Active Step Card
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_box_style(Color(0.11, 0.13, 0.165), Color(0.23, 0.27, 0.33), 6, 10))
	_body_container.add_child(card)

	var card_vb := VBoxContainer.new()
	card_vb.add_theme_constant_override("separation", 8)
	card.add_child(card_vb)

	# 1. Step Header Row (Checkbox + Role Pill + Clean Title) + Clickable Inline res:// Path
	var header_hb := HBoxContainer.new()
	header_hb.add_theme_constant_override("separation", 6)
	card_vb.add_child(header_hb)

	var step_cb := CheckBox.new()
	step_cb.button_pressed = is_done
	step_cb.tooltip_text = "Mark step complete"
	step_cb.toggled.connect(_on_step_checkbox_toggled.bind(feat_id, cp_id, step_id))
	header_hb.add_child(step_cb)

	var title_vb := VBoxContainer.new()
	title_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vb.add_theme_constant_override("separation", 2)
	header_hb.add_child(title_vb)

	var badge_title_row := HBoxContainer.new()
	badge_title_row.add_theme_constant_override("separation", 6)
	title_vb.add_child(badge_title_row)

	badge_title_row.add_child(_make_role_pill(role))

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 13)
	badge_title_row.add_child(title_lbl)

	# Clickable inline target res:// link (zero extra wrapper box!)
	var target_btn := Button.new()
	var is_gd: bool = step_path.ends_with(".gd")
	target_btn.text = "%s %s" % ["📜" if is_gd else "📄", step_path]
	target_btn.tooltip_text = "Open %s in Godot" % step_path
	target_btn.flat = true
	target_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	target_btn.clip_text = true
	target_btn.add_theme_font_size_override("font_size", 11)
	target_btn.modulate = Color(0.45, 0.80, 0.98)
	target_btn.pressed.connect(_open_res_path.bind(step_path))
	title_vb.add_child(target_btn)

	# 2. Agent Root-Cause Diagnosis Box (shown on [FIX] steps)
	if not diagnosis.is_empty():
		var diag_panel := PanelContainer.new()
		diag_panel.add_theme_stylebox_override("panel", _make_box_style(Color(0.24, 0.10, 0.13, 0.80), Color(0.86, 0.34, 0.44, 0.65), 5, 8))
		card_vb.add_child(diag_panel)

		var diag_vb := VBoxContainer.new()
		diag_vb.add_theme_constant_override("separation", 3)
		diag_panel.add_child(diag_vb)

		var diag_hdr := Label.new()
		diag_hdr.text = "🔍 AGENT DIAGNOSIS (GEMINI 4 HYDROGEN)"
		diag_hdr.add_theme_font_size_override("font_size", 10)
		diag_hdr.modulate = Color(0.98, 0.56, 0.64)
		diag_vb.add_child(diag_hdr)

		var diag_lbl := Label.new()
		diag_lbl.text = diagnosis
		diag_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		diag_lbl.add_theme_font_size_override("font_size", 12)
		diag_vb.add_child(diag_lbl)

	# 3. Clear DO Instruction
	var do_vb := VBoxContainer.new()
	do_vb.add_theme_constant_override("separation", 2)
	card_vb.add_child(do_vb)

	var do_hdr := Label.new()
	do_hdr.text = "DO"
	do_hdr.add_theme_font_size_override("font_size", 10)
	do_hdr.modulate = Color(0.45, 0.80, 0.98)
	do_vb.add_child(do_hdr)

	var instr_lbl := Label.new()
	instr_lbl.text = instruction
	instr_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instr_lbl.add_theme_font_size_override("font_size", 12)
	do_vb.add_child(instr_lbl)

	# 4. Live Godot Check Box (Preserving Tree Indentation & Concrete INSP Values)
	var check_info: Dictionary = _evaluate_step_reality_checks(feat, step, role, step_path)
	var check_rows: Array = check_info.get("rows", [])
	var ready_cnt: int = int(check_info.get("readyCount", 0))
	var total_cnt: int = check_rows.size()
	var all_ready: bool = total_cnt > 0 and ready_cnt == total_cnt

	var check_panel := PanelContainer.new()
	check_panel.add_theme_stylebox_override("panel", _make_box_style(Color(0.08, 0.095, 0.12), Color(0.20, 0.23, 0.28), 5, 8))
	card_vb.add_child(check_panel)

	var check_vb := VBoxContainer.new()
	check_vb.add_theme_constant_override("separation", 4)
	check_panel.add_child(check_vb)

	var check_hdr_row := HBoxContainer.new()
	check_vb.add_child(check_hdr_row)

	var check_hdr := Label.new()
	check_hdr.text = "LIVE GODOT CHECK"
	check_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_hdr.add_theme_font_size_override("font_size", 10)
	check_hdr.modulate = Color(0.65, 0.72, 0.82)
	check_hdr_row.add_child(check_hdr)

	var check_cnt_lbl := Label.new()
	check_cnt_lbl.text = "%d/%d ready" % [ready_cnt, total_cnt]
	check_cnt_lbl.add_theme_font_size_override("font_size", 10)
	check_cnt_lbl.modulate = Color(0.30, 0.90, 0.58) if all_ready else Color(0.96, 0.72, 0.30)
	check_hdr_row.add_child(check_cnt_lbl)

	for r_raw in check_rows:
		if typeof(r_raw) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = r_raw
		var r_ok: bool = bool(r.get("ok", false))
		var r_label: String = str(r.get("label", ""))
		var focus_name: String = str(r.get("focusName", ""))

		var line_hb := HBoxContainer.new()
		line_hb.add_theme_constant_override("separation", 4)
		check_vb.add_child(line_hb)

		var row_lbl := Label.new()
		row_lbl.text = "%s %s" % ["✓" if r_ok else "○", r_label]
		row_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_lbl.add_theme_font_size_override("font_size", 11)
		row_lbl.modulate = Color(0.32, 0.90, 0.58) if r_ok else Color(0.74, 0.78, 0.85)
		line_hb.add_child(row_lbl)

		if not focus_name.is_empty():
			var focus_btn := Button.new()
			focus_btn.text = "🎯"
			focus_btn.tooltip_text = "Select %s in Scene & Inspector" % focus_name
			focus_btn.flat = true
			focus_btn.pressed.connect(_focus_node_in_editor.bind(focus_name, step_path))
			line_hb.add_child(focus_btn)

	# 5. Native Godot Role Actions Bar
	_build_native_role_actions(card_vb, feat, step, role, step_path, all_ready, check_info)

	# 6. Collapsible GDScript Preview (CODE & FIX)
	var clean_code: String = _resolve_step_code_text(step)
	if not clean_code.is_empty() and (role == "CODE" or role == "FIX"):
		var toggle_code_btn := Button.new()
		toggle_code_btn.text = "%s Preview GDScript" % ("▾" if _show_patch_preview else "▸")
		toggle_code_btn.flat = true
		toggle_code_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle_code_btn.add_theme_font_size_override("font_size", 11)
		toggle_code_btn.modulate = Color(0.75, 0.82, 0.90)
		toggle_code_btn.pressed.connect(_on_toggle_patch_preview_pressed)
		card_vb.add_child(toggle_code_btn)

		if _show_patch_preview:
			var code_box := TextEdit.new()
			code_box.text = clean_code
			code_box.editable = false
			code_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			var line_count: int = clean_code.split("\n").size()
			code_box.custom_minimum_size = Vector2(0, clampi(line_count * 18 + 16, 72, 180))
			code_box.add_theme_font_size_override("font_size", 11)
			card_vb.add_child(code_box)

	# 7. Verify Result Line
	if not verify_result.is_empty():
		card_vb.add_child(HSeparator.new())
		var ver_lbl := Label.new()
		ver_lbl.text = "✓ VERIFY: %s" % verify_result
		ver_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ver_lbl.add_theme_font_size_override("font_size", 11)
		ver_lbl.modulate = Color(0.58, 0.88, 0.72)
		card_vb.add_child(ver_lbl)

	# Collapsible Agent Fix Drawer (available below ANY step)
	_render_agent_fix_drawer(feat, feat_id, cp_id)

	# Dynamic Primary vs Secondary Bottom CTA
	var is_last_step: bool = (_selected_step_idx == max_idx - 1)
	if all_ready or is_done:
		_primary_cta_btn.text = "✓ Complete & Go to Playtest →" if is_last_step else "✓ Complete & Next Step →"
		_primary_cta_btn.modulate = Color(0.55, 0.96, 0.72)
	else:
		_primary_cta_btn.text = "Complete Manually & Next →"
		_primary_cta_btn.modulate = Color(0.86, 0.90, 0.96)


func _render_playtest_gate_card(feat: Dictionary, feat_id: String, cp_id: String, gate_passed: bool) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_box_style(Color(0.10, 0.14, 0.13), Color(0.20, 0.65, 0.45, 0.60), 6, 10))
	_body_container.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	vb.add_child(hdr)

	var pill := _make_role_pill("GATE")
	hdr.add_child(pill)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spacer)

	var run_btn := Button.new()
	run_btn.text = "▶ Run Scene (F6)"
	run_btn.tooltip_text = "Play Current Scene (F6)"
	run_btn.pressed.connect(_on_run_scene_pressed)
	hdr.add_child(run_btn)

	var goal_hdr := Label.new()
	goal_hdr.text = "✓ END GOAL"
	goal_hdr.add_theme_font_size_override("font_size", 10)
	goal_hdr.modulate = Color(0.65, 0.72, 0.82)
	vb.add_child(goal_hdr)

	var done_when: String = str(feat.get("doneWhen", "Press F6 and verify this feature with 0 console errors.")).strip_edges()
	var goal_lbl := Label.new()
	goal_lbl.text = done_when
	goal_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(goal_lbl)

	var gate_cb := CheckBox.new()
	gate_cb.text = "Playtest Passed (0 Console Errors)"
	gate_cb.button_pressed = gate_passed
	gate_cb.toggled.connect(_on_playtest_gate_toggled.bind(feat_id, cp_id))
	vb.add_child(gate_cb)


func _render_agent_fix_drawer(_feat: Dictionary, feat_id: String, cp_id: String) -> void:
	var drawer := PanelContainer.new()
	drawer.add_theme_stylebox_override("panel", _make_box_style(Color(0.10, 0.115, 0.145), Color(0.24, 0.27, 0.34), 6, 8))
	_body_container.add_child(drawer)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	drawer.add_child(vb)

	var toggle_btn := Button.new()
	toggle_btn.text = "✦ Broken? Ask Agent to Fix   %s" % ("▾" if _fix_drawer_open else "▸")
	toggle_btn.flat = true
	toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle_btn.add_theme_font_size_override("font_size", 12)
	toggle_btn.modulate = Color(0.95, 0.76, 0.78) if _fix_drawer_open else Color(0.80, 0.84, 0.90)
	toggle_btn.pressed.connect(_on_toggle_fix_drawer_pressed)
	vb.add_child(toggle_btn)

	if not _fix_drawer_open:
		return

	var hint_lbl := Label.new()
	hint_lbl.text = "Sends live Scene Tree + .gd scripts to Gemini 4 Hydrogen for a 1-click patch."
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.modulate = Color(0.68, 0.74, 0.82)
	vb.add_child(hint_lbl)

	_fix_input = LineEdit.new()
	_fix_input.placeholder_text = "Describe bug or paste Godot error..."
	_fix_input.text = _fix_draft_text
	_fix_input.text_changed.connect(func(txt: String) -> void: _fix_draft_text = txt)
	_fix_input.text_submitted.connect(_on_fix_input_submitted.bind(feat_id, cp_id))
	vb.add_child(_fix_input)

	var ask_btn := Button.new()
	ask_btn.text = "⏳ Diagnosing Live Project..." if _diagnosing_fix else "✦ Diagnose & Fix"
	ask_btn.disabled = _diagnosing_fix
	ask_btn.modulate = Color(0.98, 0.62, 0.68)
	ask_btn.pressed.connect(_on_ask_agent_fix_pressed.bind(feat_id, cp_id))
	vb.add_child(ask_btn)


# ---------------------------------------------------------------------------
# Live Godot Project Inspection & Role Actions (Undoable)
# ---------------------------------------------------------------------------

func _resolve_effective_step_path(step: Dictionary, feat: Dictionary) -> String:
	var p: String = str(step.get("stepPath", "")).strip_edges()
	if p.begins_with("res://"):
		return p
	var primary: String = str(feat.get("primaryAsset", "")).strip_edges()
	if primary.begins_with("res://"):
		return primary
	return "res://scenes/main.tscn"


func _resolve_step_code_text(step: Dictionary) -> String:
	var patch_raw = step.get("scriptPatch", null)
	if typeof(patch_raw) == TYPE_DICTIONARY:
		var rep: String = str(patch_raw.get("replaceBlock", "")).strip_edges()
		if not rep.is_empty():
			return _strip_diff_prefixes(rep)
	var snip: String = str(step.get("codeSnippet", "")).strip_edges()
	return _strip_diff_prefixes(snip)


func _strip_diff_prefixes(raw: String) -> String:
	var lines: PackedStringArray = raw.split("\n")
	var out: PackedStringArray = []
	for line in lines:
		if line.begins_with("+ "):
			out.append(line.substr(2))
		else:
			out.append(line)
	return "\n".join(out).strip_edges()


func _parse_scene_node_specs(step: Dictionary) -> Array:
	var specs: Array = []
	var seen: Dictionary = {}
	var area1: String = str(step.get("area1Hierarchy", "")).strip_edges()

	if not area1.is_empty():
		var lines: PackedStringArray = area1.split("\n")
		for raw_line in lines:
			var line: String = raw_line.strip_edges(false, true)
			if line.strip_edges().is_empty():
				continue
			var clean: String = line.strip_edges()
			var prefix: String = ""
			var idx_branch: int = maxi(line.find("├─ "), line.find("└─ "))
			if idx_branch >= 0:
				prefix = line.substr(0, idx_branch + 3)
				clean = line.substr(idx_branch + 3).strip_edges()
			elif line.begins_with("- ") or line.begins_with("* "):
				prefix = "├─ "
				clean = line.substr(2).strip_edges()

			var node_name: String = clean
			var node_class: String = ""
			var paren_open: int = clean.find("(")
			var paren_close: int = clean.find(")", paren_open + 1)
			if paren_open > 0 and paren_close > paren_open:
				node_name = clean.substr(0, paren_open).strip_edges()
				var meta: String = clean.substr(paren_open + 1, paren_close - paren_open - 1).strip_edges()
				node_class = meta.split(" ")[0].strip_edges()
			elif clean.find(">") >= 0:
				var parts: PackedStringArray = clean.split(">", false, 1)
				node_name = parts[0].strip_edges()
				if parts.size() > 1:
					node_class = parts[1].strip_edges().split(" ")[0]

			node_name = node_name.split(" ")[0].strip_edges()
			if node_name.is_empty() or seen.has(node_name):
				continue
			seen[node_name] = true
			specs.append({
				"name": node_name,
				"type": node_class if not node_class.is_empty() else _guess_node_class(node_name),
				"prefix": prefix,
			})
		if not specs.is_empty():
			return specs

	# Fallback: parse markdown pipe table or instruction text for explicit Node (Class) patterns
	var combined: String = "%s\n%s\n%s" % [
		str(step.get("title", "")),
		str(step.get("instruction", "")),
		str(step.get("codeSnippet", "")),
	]
	var re := RegEx.new()
	re.compile("\\b([A-Z][A-Za-z0-9_]{2,32})\\s*(?:\\(|>)\\s*([A-Z][A-Za-z0-9_]*3D|[A-Z][A-Za-z0-9_]*2D|Timer|Control|Node|CanvasLayer|RigidBody[23]D|CharacterBody[23]D|StaticBody[23]D|Area[23]D|CollisionShape[23]D|Marker[23]D|RayCast[23]D|AudioStreamPlayer(?:[23]D)?|AnimationPlayer|Panel|Label|Button)")
	for m in re.search_all(combined):
		var n_name: String = m.get_string(1)
		var n_type: String = m.get_string(2)
		if not seen.has(n_name):
			seen[n_name] = true
			specs.append({
				"name": n_name,
				"type": n_type,
				"prefix": "├─ " if specs.size() > 0 else "",
			})

	return specs


func _guess_node_class(node_name: String) -> String:
	var lower: String = node_name.to_lower()
	if "timer" in lower or "cooldown" in lower:
		return "Timer"
	if "shape" in lower or "collider" in lower:
		return "CollisionShape3D"
	if "zone" in lower or "area" in lower or "hitbox" in lower or "trigger" in lower:
		return "Area3D"
	if "floor" in lower or "wall" in lower or "ground" in lower:
		return "StaticBody3D"
	if "marker" in lower or "spawnpoint" in lower:
		return "Marker3D"
	if "camera" in lower:
		return "Camera3D"
	if "player" in lower:
		return "CharacterBody3D"
	return "Node3D"


func _find_node_recursive(root: Node, target_name: String) -> Node:
	if root == null:
		return null
	if root.name.to_lower() == target_name.to_lower():
		return root
	for child in root.get_children():
		var found: Node = _find_node_recursive(child, target_name)
		if found != null:
			return found
	return null


func _find_node_with_script(root: Node, script_path: String) -> Node:
	if root == null or script_path.is_empty():
		return null
	var scr: Variant = root.get_script()
	if scr is Script and (scr as Script).resource_path == script_path:
		return root
	for child in root.get_children():
		var found: Node = _find_node_with_script(child, script_path)
		if found != null:
			return found
	return null


func _parse_inspector_specs(step: Dictionary) -> Array:
	var specs: Array = []
	var seen: Dictionary = {}

	var raw_a2: String = str(step.get("area2Inspector", "")).strip_edges()
	var code: String = str(step.get("codeSnippet", "")).strip_edges()

	# 1. Pipe table rows in codeSnippet: | Node | Property | Value |
	if "|" in code:
		for raw_line in code.split("\n"):
			var line: String = raw_line.strip_edges()
			if not line.begins_with("|"):
				continue
			var cols: PackedStringArray = line.split("|", false)
			if cols.size() < 2:
				continue
			var first_col: String = cols[0].strip_edges()
			if first_col.is_empty() or first_col.begins_with("-") or first_col.to_lower().begins_with("node") or first_col.to_lower().begins_with("property"):
				continue
			var clean_line: String = ""
			if cols.size() >= 3:
				clean_line = "%s · %s = %s" % [first_col.split(">")[0].strip_edges(), cols[1].strip_edges(), cols[2].strip_edges()]
				specs.append({
					"label": clean_line,
					"nodeName": first_col.split(">")[0].strip_edges(),
					"prop": cols[1].strip_edges(),
					"value": cols[2].strip_edges(),
				})
			else:
				clean_line = "%s = %s" % [first_col, cols[1].strip_edges()]
				specs.append({
					"label": clean_line,
					"nodeName": "",
					"prop": first_col,
					"value": cols[1].strip_edges(),
				})
			seen[clean_line] = true

	# 2. area2Inspector pipe or semicolon-delimited items
	if not raw_a2.is_empty():
		for raw_part in raw_a2.split("|"):
			var part: String = raw_part.strip_edges()
			if part.is_empty() or seen.has(part):
				continue
			seen[part] = true
			var node_hint: String = ""
			var prop_hint: String = ""
			var val_hint: String = ""
			if ":" in part:
				var kv: PackedStringArray = part.split(":", false, 1)
				var lhs: String = kv[0].strip_edges()
				val_hint = kv[1].strip_edges()
				if "." in lhs:
					var dot_parts: PackedStringArray = lhs.split(".", false, 1)
					node_hint = dot_parts[0].strip_edges()
					prop_hint = dot_parts[1].strip_edges()
				else:
					prop_hint = lhs
			specs.append({
				"label": part,
				"nodeName": node_hint,
				"prop": prop_hint,
				"value": val_hint,
			})

	# 3. Scan instruction for InputMap quotes when no specs parsed yet
	var combined: String = "%s\n%s" % [str(step.get("instruction", "")), code]
	var input_re := RegEx.new()
	input_re.compile("[\"']([a-z][a-z0-9_]{1,28})[\"']")
	var lower_comb: String = combined.to_lower()
	if "input" in lower_comb or "action" in lower_comb:
		for m in input_re.search_all(combined):
			var act: String = m.get_string(1)
			var act_label: String = "InputMap \"%s\"" % act
			if not seen.has(act_label):
				seen[act_label] = true
				specs.append({
					"label": act_label,
					"nodeName": "",
					"prop": "input/%s" % act,
					"value": "bound",
				})

	return specs


func _parse_signal_spec(step: Dictionary) -> Dictionary:
	var combined: String = "%s\n%s" % [str(step.get("codeSnippet", "")), str(step.get("instruction", ""))]
	var sig_re := RegEx.new()
	sig_re.compile("\\[?([A-Za-z0-9_]+)\\.([a-z_]+)\\]?(?:\\(\\))?\\s*(?:-->|──►|─►|->|to)\\s*\\[?([A-Za-z0-9_]+)\\.([A-Za-z0-9_]+)")
	var m := sig_re.search(combined)
	if m != null:
		return {
			"source": m.get_string(1),
			"signalName": m.get_string(2),
			"target": m.get_string(3),
			"method": m.get_string(4),
			"label": "%s.%s → %s.%s()" % [m.get_string(1), m.get_string(2), m.get_string(3), m.get_string(4)],
		}
	return {}


func _evaluate_step_reality_checks(feat: Dictionary, step: Dictionary, role: String, step_path: String) -> Dictionary:
	var rows: Array = []
	var scene_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
	var missing_nodes: Array = []
	var first_existing_node: String = ""

	if role == "SCENE":
		var scene_exists: bool = step_path.ends_with(".tscn") and FileAccess.file_exists(step_path)
		if step_path.ends_with(".tscn"):
			rows.append({
				"ok": scene_exists,
				"label": "%s saved on disk" % step_path,
				"focusName": "",
			})
		var node_specs: Array = _parse_scene_node_specs(step)
		for sp in node_specs:
			var n_name: String = str(sp.get("name", ""))
			var n_type: String = str(sp.get("type", "Node3D"))
			var prefix: String = str(sp.get("prefix", ""))
			var found: Node = _find_node_recursive(scene_root, n_name)
			var is_present: bool = found != null
			if is_present and first_existing_node.is_empty():
				first_existing_node = found.name
			elif not is_present:
				missing_nodes.append(sp)
			rows.append({
				"ok": is_present,
				"label": "%s%s (%s)" % [prefix, n_name, n_type],
				"focusName": found.name if found != null else "",
			})
		if node_specs.is_empty():
			var root_ok: bool = scene_root != null
			rows.append({
				"ok": root_ok,
				"label": "Open scene root: %s" % scene_root.name if root_ok else "Open target scene in Godot",
				"focusName": scene_root.name if root_ok else "",
			})
	elif role == "INSP":
		var insp_specs: Array = _parse_inspector_specs(step)
		for sp in insp_specs:
			var lbl: String = str(sp.get("label", ""))
			var prop: String = str(sp.get("prop", ""))
			var n_hint: String = str(sp.get("nodeName", ""))
			var is_ok: bool = false
			var focus_target: String = ""

			if prop.begins_with("input/"):
				is_ok = ProjectSettings.has_setting(prop) or InputMap.has_action(prop.trim_prefix("input/"))
			elif "layer" in prop.to_lower() and "layer_names" in prop.to_lower():
				is_ok = ProjectSettings.has_setting(prop)
			elif scene_root != null and not n_hint.is_empty():
				var target_node: Node = _find_node_recursive(scene_root, n_hint)
				if target_node != null:
					focus_target = target_node.name
					if first_existing_node.is_empty():
						first_existing_node = target_node.name
					var clean_prop: String = prop.to_lower().replace(" ", "_")
					var cur_val: Variant = target_node.get(clean_prop)
					is_ok = cur_val != null and str(cur_val).to_lower() == str(sp.get("value", "")).to_lower()
			rows.append({
				"ok": is_ok,
				"label": lbl,
				"focusName": focus_target,
			})
		if insp_specs.is_empty():
			var root_present: bool = scene_root != null
			rows.append({
				"ok": root_present,
				"label": "Inspect active node properties in Inspector",
				"focusName": scene_root.name if root_present else "",
			})
	elif role == "CODE":
		var script_exists: bool = step_path.ends_with(".gd") and FileAccess.file_exists(step_path)
		rows.append({
			"ok": script_exists,
			"label": "%s on disk" % step_path,
			"focusName": "",
		})
		var attached_node: Node = _find_node_with_script(scene_root, step_path) if script_exists else null
		rows.append({
			"ok": attached_node != null,
			"label": "Attached to %s" % attached_node.name if attached_node != null else "Attached to target node in open scene",
			"focusName": attached_node.name if attached_node != null else (scene_root.name if scene_root != null else ""),
		})
	elif role == "WIRE":
		var sig_info: Dictionary = _parse_signal_spec(step)
		if not sig_info.is_empty():
			var src_name: String = str(sig_info.get("source", ""))
			var sig_name: String = str(sig_info.get("signalName", ""))
			var dst_name: String = str(sig_info.get("target", ""))
			var method_name: String = str(sig_info.get("method", ""))
			var src_node: Node = _find_node_recursive(scene_root, src_name)
			var dst_node: Node = _find_node_recursive(scene_root, dst_name)
			var connected: bool = false
			if src_node != null and dst_node != null and src_node.has_signal(sig_name):
				connected = src_node.is_connected(sig_name, Callable(dst_node, method_name))
			rows.append({
				"ok": connected,
				"label": str(sig_info.get("label", "")),
				"focusName": src_node.name if src_node != null else "",
			})
		else:
			rows.append({
				"ok": bool(step.get("completed", false)),
				"label": "Wire node signal & verify in F6",
				"focusName": scene_root.name if scene_root != null else "",
			})
	else: # FIX
		var fix_exists: bool = step_path.ends_with(".gd") and FileAccess.file_exists(step_path)
		rows.append({
			"ok": fix_exists,
			"label": "Target file %s" % step_path,
			"focusName": "",
		})
		var patch_applied: bool = false
		if fix_exists:
			var f := FileAccess.open(step_path, FileAccess.READ)
			if f != null:
				var disk_text: String = f.get_as_text()
				var patch_code: String = _resolve_step_code_text(step)
				patch_applied = not patch_code.is_empty() and patch_code in disk_text
		rows.append({
			"ok": patch_applied,
			"label": "Root-cause patch present in .gd" if patch_applied else "Root-cause patch ready to apply",
			"focusName": "",
		})

	var ready_cnt: int = 0
	for r in rows:
		if typeof(r) == TYPE_DICTIONARY and bool(r.get("ok", false)):
			ready_cnt += 1

	return {
		"rows": rows,
		"readyCount": ready_cnt,
		"missingNodes": missing_nodes,
		"firstFocusNode": first_existing_node,
		"inspSpecs": _parse_inspector_specs(step) if role == "INSP" else [],
		"sigSpec": _parse_signal_spec(step) if role == "WIRE" else {},
	}


func _build_native_role_actions(
	parent_vb: VBoxContainer,
	feat: Dictionary,
	step: Dictionary,
	role: String,
	step_path: String,
	all_ready: bool,
	check_info: Dictionary
) -> void:
	if role == "SCENE":
		if not all_ready:
			var add_btn := Button.new()
			add_btn.text = "⚡ Add Missing Nodes (Undoable)"
			add_btn.modulate = Color(0.50, 0.86, 1.0)
			add_btn.pressed.connect(_on_action_create_scene_nodes.bind(step, step_path, check_info.get("missingNodes", [])))
			parent_vb.add_child(add_btn)
		else:
			var open_scene_btn := Button.new()
			open_scene_btn.text = "📂 Open Scene in Godot"
			open_scene_btn.pressed.connect(_open_res_path.bind(step_path))
			parent_vb.add_child(open_scene_btn)
	elif role == "INSP":
		var apply_btn := Button.new()
		apply_btn.text = "⚡ Apply Settings & Focus" if not all_ready else "🎯 Focus Node in Inspector"
		if not all_ready:
			apply_btn.modulate = Color(0.98, 0.78, 0.38)
		apply_btn.pressed.connect(_on_action_apply_inspector.bind(step_path, check_info.get("inspSpecs", []), str(check_info.get("firstFocusNode", ""))))
		parent_vb.add_child(apply_btn)
	elif role == "CODE":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		parent_vb.add_child(row)

		var gd_exists: bool = step_path.ends_with(".gd") and FileAccess.file_exists(step_path)
		var scene_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
		var attached: Node = _find_node_with_script(scene_root, step_path) if gd_exists else null

		var script_btn := Button.new()
		script_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not gd_exists:
			script_btn.text = "+ Create & Attach .gd"
			script_btn.modulate = Color(0.45, 0.92, 0.68)
		elif attached == null:
			script_btn.text = "🔗 Attach & Edit .gd"
			script_btn.modulate = Color(0.45, 0.92, 0.68)
		else:
			script_btn.text = "📜 Edit .gd"
		script_btn.pressed.connect(_on_action_create_or_edit_script.bind(step, step_path))
		row.add_child(script_btn)

		var copy_btn := Button.new()
		copy_btn.text = "⧉ Copy GDScript"
		copy_btn.pressed.connect(_on_copy_step_code_pressed.bind(step))
		row.add_child(copy_btn)
	elif role == "WIRE":
		var w_row := HBoxContainer.new()
		w_row.add_theme_constant_override("separation", 6)
		parent_vb.add_child(w_row)

		var sig_spec: Dictionary = check_info.get("sigSpec", {})
		var conn_btn := Button.new()
		conn_btn.text = "⚡ Connect Signal" if not all_ready else "✓ Signal Connected"
		conn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not all_ready:
			conn_btn.modulate = Color(0.76, 0.64, 0.98)
		conn_btn.pressed.connect(_on_action_connect_signal.bind(sig_spec, step_path))
		w_row.add_child(conn_btn)

		var f6_btn := Button.new()
		f6_btn.text = "▶ Run F6"
		f6_btn.pressed.connect(_on_run_scene_pressed)
		w_row.add_child(f6_btn)
	else: # FIX
		var f_row := HBoxContainer.new()
		f_row.add_theme_constant_override("separation", 6)
		parent_vb.add_child(f_row)

		var patch_btn := Button.new()
		patch_btn.text = "⚡ Apply Fix Patch to .gd" if not all_ready else "📜 Open Patched .gd"
		patch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		patch_btn.modulate = Color(0.98, 0.56, 0.64)
		patch_btn.pressed.connect(_on_action_apply_fix_patch.bind(step, step_path))
		f_row.add_child(patch_btn)

		var copy_patch_btn := Button.new()
		copy_patch_btn.text = "⧉ Copy"
		copy_patch_btn.pressed.connect(_on_copy_step_code_pressed.bind(step))
		f_row.add_child(copy_patch_btn)


func _on_action_create_scene_nodes(step: Dictionary, step_path: String, missing_nodes: Array) -> void:
	if editor_interface == null:
		return
	var scene_root: Node = editor_interface.get_edited_scene_root()

	# Create scene file on disk if missing and step_path is .tscn
	if step_path.ends_with(".tscn") and not FileAccess.file_exists(step_path):
		var root_type: String = "Node3D"
		var root_name: String = step_path.get_file().get_basename().to_pascal_case()
		if not missing_nodes.is_empty():
			var first_spec: Dictionary = missing_nodes[0]
			var cand_type: String = str(first_spec.get("type", "Node3D"))
			if ClassDB.class_exists(cand_type) and ClassDB.can_instantiate(cand_type) and ClassDB.is_parent_class(cand_type, "Node"):
				root_type = cand_type
			root_name = str(first_spec.get("name", root_name))
		var new_root: Variant = ClassDB.instantiate(root_type)
		if new_root is Node:
			(new_root as Node).name = root_name
			_ensure_dir_for_res_path(step_path)
			var packed := PackedScene.new()
			packed.pack(new_root as Node)
			ResourceSaver.save(packed, step_path)
			(new_root as Node).queue_free()
			if editor_interface.get_resource_filesystem() != null:
				editor_interface.get_resource_filesystem().scan()
			editor_interface.open_scene_from_path(step_path)
			scene_root = editor_interface.get_edited_scene_root()

	if scene_root == null and step_path.ends_with(".tscn") and FileAccess.file_exists(step_path):
		editor_interface.open_scene_from_path(step_path)
		scene_root = editor_interface.get_edited_scene_root()

	if scene_root == null:
		_set_status("Open target scene first before adding nodes.", true)
		return

	var added_cnt: int = 0
	if undo_redo != null:
		undo_redo.create_action("LAYERS: Add Missing Scene Nodes")

	for sp_raw in missing_nodes:
		if typeof(sp_raw) != TYPE_DICTIONARY:
			continue
		var n_name: String = str(sp_raw.get("name", "")).strip_edges()
		var n_type: String = str(sp_raw.get("type", "Node3D")).strip_edges()
		if n_name.is_empty() or _find_node_recursive(scene_root, n_name) != null:
			continue

		var created_node: Node = _instantiate_node_or_shape(n_name, n_type)
		if created_node == null:
			continue

		if undo_redo != null:
			undo_redo.add_do_method(scene_root, "add_child", created_node, true)
			undo_redo.add_do_property(created_node, "owner", scene_root)
			undo_redo.add_do_reference(created_node)
			undo_redo.add_undo_method(scene_root, "remove_child", created_node)
		else:
			scene_root.add_child(created_node, true)
			created_node.owner = scene_root
		added_cnt += 1

	if undo_redo != null:
		if added_cnt > 0:
			undo_redo.commit_action()
		else:
			undo_redo.clear_history()

	_set_status("Added %d node(s) (Ctrl+Z supported) ✓" % added_cnt, false)
	_refresh_view()


func _instantiate_node_or_shape(n_name: String, raw_type: String) -> Node:
	if ClassDB.class_exists(raw_type) and ClassDB.can_instantiate(raw_type):
		if ClassDB.is_parent_class(raw_type, "Node"):
			var inst: Variant = ClassDB.instantiate(raw_type)
			if inst is Node:
				(inst as Node).name = n_name
				return inst as Node
		elif ClassDB.is_parent_class(raw_type, "Shape3D"):
			var col := CollisionShape3D.new()
			col.name = n_name
			col.shape = ClassDB.instantiate(raw_type)
			return col
		elif ClassDB.is_parent_class(raw_type, "Shape2D"):
			var col2d := CollisionShape2D.new()
			col2d.name = n_name
			col2d.shape = ClassDB.instantiate(raw_type)
			return col2d

	var fallback := Node3D.new()
	fallback.name = n_name
	return fallback


func _on_action_apply_inspector(step_path: String, insp_specs: Array, first_focus_node: String) -> void:
	if editor_interface == null:
		return
	var scene_root: Node = editor_interface.get_edited_scene_root()
	var input_added: int = 0
	var props_applied: int = 0
	var focused_node: Node = null

	for sp_raw in insp_specs:
		if typeof(sp_raw) != TYPE_DICTIONARY:
			continue
		var prop: String = str(sp_raw.get("prop", ""))
		var val_str: String = str(sp_raw.get("value", "")).strip_edges()
		var n_hint: String = str(sp_raw.get("nodeName", "")).strip_edges()

		if prop.begins_with("input/"):
			if not ProjectSettings.has_setting(prop):
				ProjectSettings.set_setting(prop, {"deadzone": 0.2, "events": []})
				ProjectSettings.save()
				input_added += 1
		elif scene_root != null and not n_hint.is_empty():
			var node: Node = _find_node_recursive(scene_root, n_hint)
			if node != null:
				if focused_node == null:
					focused_node = node
				var clean_prop: String = prop.to_lower().replace(" ", "_")
				if node.get(clean_prop) != null:
					var parsed_val: Variant = _parse_scalar_value(val_str, typeof(node.get(clean_prop)))
					if parsed_val != null:
						if undo_redo != null:
							undo_redo.create_action("LAYERS: Set %s.%s" % [node.name, clean_prop])
							undo_redo.add_do_property(node, clean_prop, parsed_val)
							undo_redo.add_undo_property(node, clean_prop, node.get(clean_prop))
							undo_redo.commit_action()
						else:
							node.set(clean_prop, parsed_val)
						props_applied += 1

	if focused_node == null and not first_focus_node.is_empty() and scene_root != null:
		focused_node = _find_node_recursive(scene_root, first_focus_node)
	if focused_node != null:
		_select_and_inspect_node(focused_node)
	elif step_path.ends_with(".tscn"):
		_open_res_path(step_path)

	_set_status("Applied %d InputMap + %d property change(s) ✓" % [input_added, props_applied], false)
	_refresh_view()


func _parse_scalar_value(raw: String, target_type: int) -> Variant:
	var lower: String = raw.to_lower()
	if target_type == TYPE_BOOL:
		if lower == "true":
			return true
		if lower == "false":
			return false
	elif target_type == TYPE_INT and raw.is_valid_int():
		return raw.to_int()
	elif target_type == TYPE_FLOAT and raw.is_valid_float():
		return raw.to_float()
	return null


func _on_action_create_or_edit_script(step: Dictionary, step_path: String) -> void:
	if not step_path.ends_with(".gd"):
		_open_res_path(step_path)
		return

	if not FileAccess.file_exists(step_path):
		var content: String = _resolve_step_code_text(step)
		if content.is_empty() or not ("extends " in content):
			var body_prefix: String = "extends Node\n\n"
			content = body_prefix + content if not content.is_empty() else "extends Node\n"
		_ensure_dir_for_res_path(step_path)
		var f := FileAccess.open(step_path, FileAccess.WRITE)
		if f != null:
			f.store_string(content + "\n")
			f.close()
		if editor_interface != null and editor_interface.get_resource_filesystem() != null:
			editor_interface.get_resource_filesystem().scan()

	# Attach script to matching selected node or scene root if unattached
	if editor_interface != null:
		var scene_root: Node = editor_interface.get_edited_scene_root()
		var scr := ResourceLoader.load(step_path)
		if scene_root != null and scr is Script and _find_node_with_script(scene_root, step_path) == null:
			var target_node: Node = null
			if editor_interface.get_selection() != null:
				var sel: Array = editor_interface.get_selection().get_selected_nodes()
				if not sel.is_empty() and sel[0] is Node:
					target_node = sel[0] as Node
			if target_node == null:
				target_node = scene_root
			if target_node.get_script() == null:
				if undo_redo != null:
					undo_redo.create_action("LAYERS: Attach %s" % step_path.get_file())
					undo_redo.add_do_property(target_node, "script", scr)
					undo_redo.add_undo_property(target_node, "script", null)
					undo_redo.commit_action()
				else:
					target_node.set_script(scr)
		if scr is Script:
			editor_interface.edit_script(scr as Script)

	_set_status("Opened %s ✓" % step_path, false)
	_refresh_view()


func _on_action_connect_signal(sig_spec: Dictionary, step_path: String) -> void:
	if editor_interface == null:
		return
	var scene_root: Node = editor_interface.get_edited_scene_root()
	if scene_root == null:
		_open_res_path(step_path)
		return

	var src_name: String = str(sig_spec.get("source", ""))
	var sig_name: String = str(sig_spec.get("signalName", ""))
	var dst_name: String = str(sig_spec.get("target", ""))
	var method_name: String = str(sig_spec.get("method", ""))

	var src_node: Node = _find_node_recursive(scene_root, src_name) if not src_name.is_empty() else null
	var dst_node: Node = _find_node_recursive(scene_root, dst_name) if not dst_name.is_empty() else src_node

	if src_node != null and dst_node != null and not sig_name.is_empty() and not method_name.is_empty() and src_node.has_signal(sig_name):
		var target_callable := Callable(dst_node, method_name)
		if not src_node.is_connected(sig_name, target_callable):
			src_node.connect(sig_name, target_callable, Object.CONNECT_PERSIST)
			_set_status("Connected %s.%s → %s.%s() ✓" % [src_node.name, sig_name, dst_node.name, method_name], false)
		_select_and_inspect_node(src_node)
	else:
		if src_node != null:
			_select_and_inspect_node(src_node)
		_set_status("Focus %s in Node Dock → Signals to finish wiring." % (src_node.name if src_node != null else "source node"), false)
	_refresh_view()


func _on_action_apply_fix_patch(step: Dictionary, step_path: String) -> void:
	var target_path: String = step_path
	var patch_raw = step.get("scriptPatch", null)
	var target_block: String = ""
	var replace_block: String = ""

	if typeof(patch_raw) == TYPE_DICTIONARY:
		var rp: String = str(patch_raw.get("resPath", "")).strip_edges()
		if rp.begins_with("res://") and rp.ends_with(".gd"):
			target_path = rp
		target_block = str(patch_raw.get("targetBlock", ""))
		replace_block = _strip_diff_prefixes(str(patch_raw.get("replaceBlock", "")))

	if replace_block.is_empty():
		replace_block = _resolve_step_code_text(step)

	if target_path.ends_with(".gd") and not replace_block.is_empty():
		var file_exists: bool = FileAccess.file_exists(target_path)
		var existing_text: String = ""
		if file_exists:
			var rf := FileAccess.open(target_path, FileAccess.READ)
			if rf != null:
				existing_text = rf.get_as_text()
				rf.close()

		var applied: bool = false
		if not file_exists or replace_block.begins_with("extends ") or replace_block.begins_with("class_name "):
			_ensure_dir_for_res_path(target_path)
			var wf := FileAccess.open(target_path, FileAccess.WRITE)
			if wf != null:
				wf.store_string(replace_block + "\n")
				wf.close()
				applied = true
		elif not target_block.is_empty() and target_block in existing_text:
			var updated_text: String = existing_text.replace(target_block, replace_block)
			var wf2 := FileAccess.open(target_path, FileAccess.WRITE)
			if wf2 != null:
				wf2.store_string(updated_text)
				wf2.close()
				applied = true

		if applied:
			if editor_interface != null and editor_interface.get_resource_filesystem() != null:
				editor_interface.get_resource_filesystem().scan()
			_open_res_path(target_path)
			_set_status("Applied AI fix patch to %s ✓" % target_path, false)
			_refresh_view()
			return

	DisplayServer.clipboard_set(replace_block)
	_open_res_path(target_path)
	_set_status("Copied clean fix snippet & opened %s — paste at target function." % target_path, false)


func _on_copy_step_code_pressed(step: Dictionary) -> void:
	var clean: String = _resolve_step_code_text(step)
	DisplayServer.clipboard_set(clean)
	_set_status("Copied clean GDScript to clipboard ✓", false)


func _focus_node_in_editor(node_name: String, step_path: String) -> void:
	if editor_interface == null:
		return
	var scene_root: Node = editor_interface.get_edited_scene_root()
	var node: Node = _find_node_recursive(scene_root, node_name)
	if node != null:
		_select_and_inspect_node(node)
		_set_status("Focused %s in Scene & Inspector ✓" % node.name, false)
	elif step_path.ends_with(".tscn"):
		_open_res_path(step_path)


func _select_and_inspect_node(node: Node) -> void:
	if editor_interface == null or node == null:
		return
	if editor_interface.get_selection() != null:
		editor_interface.get_selection().clear()
		editor_interface.get_selection().add_node(node)
	editor_interface.inspect_object(node)


func _ensure_dir_for_res_path(res_path: String) -> void:
	var dir_path: String = res_path.get_base_dir()
	if dir_path.is_empty():
		return
	var abs_dir: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)


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
			var sp: String = str(s_raw.get("stepPath", "")).strip_edges()
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
# UI Helpers & Styling
# ---------------------------------------------------------------------------

func _make_box_style(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


func _make_role_pill(role: String) -> PanelContainer:
	var bg := Color(0.20, 0.25, 0.34, 0.9)
	var fg := Color(0.80, 0.86, 0.96)
	match role:
		"SCENE":
			bg = Color(0.10, 0.26, 0.38, 0.95)
			fg = Color(0.45, 0.84, 0.98)
		"INSP":
			bg = Color(0.32, 0.22, 0.08, 0.95)
			fg = Color(0.98, 0.76, 0.30)
		"CODE":
			bg = Color(0.09, 0.28, 0.20, 0.95)
			fg = Color(0.32, 0.90, 0.58)
		"WIRE":
			bg = Color(0.24, 0.16, 0.38, 0.95)
			fg = Color(0.76, 0.64, 0.98)
		"FIX":
			bg = Color(0.36, 0.11, 0.16, 0.95)
			fg = Color(0.98, 0.56, 0.64)
		"GATE":
			bg = Color(0.09, 0.28, 0.20, 0.95)
			fg = Color(0.32, 0.90, 0.58)

	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = fg * Color(1, 1, 1, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = role
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.modulate = fg
	pill.add_child(lbl)
	return pill


func _set_status(msg: String, is_error: bool) -> void:
	if _status_label == null:
		return
	_status_label.text = msg
	_status_label.modulate = Color(0.96, 0.48, 0.48) if is_error else Color(0.45, 0.85, 0.65)


func _open_res_path(res_path: String) -> void:
	if editor_interface == null:
		return
	if res_path.ends_with(".tscn") or res_path.ends_with(".scn"):
		if FileAccess.file_exists(res_path):
			editor_interface.open_scene_from_path(res_path)
		else:
			_set_status("%s does not exist yet — click ⚡ Add Missing Nodes." % res_path, true)
		return
	if not FileAccess.file_exists(res_path):
		_set_status("%s does not exist yet — click + Create & Attach .gd." % res_path, true)
		return
	var res := ResourceLoader.load(res_path)
	if res is Script:
		editor_interface.edit_script(res)
	elif res != null:
		editor_interface.edit_resource(res)


# ---------------------------------------------------------------------------
# Signal Handlers & Navigation
# ---------------------------------------------------------------------------

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
		_selected_step_idx = _find_first_incomplete_step_idx(f)
		_show_patch_preview = false
		_render_active_step_workspace(f)


func _on_step_selected(idx: int) -> void:
	_selected_step_idx = idx
	_show_patch_preview = false
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_prev_step_pressed() -> void:
	_selected_step_idx = maxi(0, _selected_step_idx - 1)
	_show_patch_preview = false
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty():
		_render_active_step_workspace(feat)


func _on_next_step_pressed() -> void:
	var feat: Dictionary = _get_active_feature()
	if feat.is_empty():
		return
	var steps: Array = feat.get("steps", [])
	_selected_step_idx = mini(steps.size(), _selected_step_idx + 1)
	_show_patch_preview = false
	_render_active_step_workspace(feat)


func _on_step_checkbox_toggled(pressed: bool, feat_id: String, cp_id: String, step_id: String) -> void:
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty() and str(feat.get("id", "")) == feat_id:
		for st_raw in feat.get("steps", []):
			if typeof(st_raw) == TYPE_DICTIONARY and str(st_raw.get("id", "")) == step_id:
				st_raw["completed"] = pressed
				break
		if not pressed:
			feat["isPlaytestPassed"] = false
			feat["isCompleted"] = false
	_set_status("Syncing...", false)
	_sync.toggle_step(feat_id, cp_id, step_id, pressed)


func _on_playtest_gate_toggled(pressed: bool, feat_id: String, cp_id: String) -> void:
	var feat: Dictionary = _get_active_feature()
	if not feat.is_empty() and str(feat.get("id", "")) == feat_id:
		feat["isPlaytestPassed"] = pressed
	_set_status("Syncing Playtest Gate...", false)
	_sync.set_playtest_passed(feat_id, cp_id, pressed)


func _on_toggle_patch_preview_pressed() -> void:
	_show_patch_preview = not _show_patch_preview
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
	if _fix_input == null:
		return
	var issue: String = _fix_input.text.strip_edges()
	if issue.is_empty():
		_set_status("Describe the bug or paste a Godot error first.", true)
		return
	var feat: Dictionary = _get_active_feature()
	var scene_snap: String = _capture_live_scene_snapshot()
	var scripts_snap: String = _capture_live_scripts_snapshot(feat)
	_diagnosing_fix = true
	_set_status("⏳ Inspecting live Scene Tree + .gd scripts...", false)
	if not feat.is_empty():
		_render_active_step_workspace(feat)
	_sync.diagnose_fix(feat_id, cp_id, issue, scene_snap, scripts_snap)


func _on_primary_cta_pressed() -> void:
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
	_show_patch_preview = false
	_set_status("Step completed ✓", false)
	_refresh_view()
	_sync.toggle_step(feat_id, cp_id, step_id, true)


func _on_epic_updated(payload: Dictionary) -> void:
	_payload = payload
	var had_diagnosing: bool = _diagnosing_fix
	_diagnosing_fix = false

	var created_fix_id: String = str(payload.get("createdFixStepId", "")).strip_edges()
	if not created_fix_id.is_empty():
		_fix_drawer_open = false
		_fix_draft_text = ""
		_show_patch_preview = true
		var feat: Dictionary = _get_active_feature()
		var steps: Array = feat.get("steps", []) if not feat.is_empty() else []
		for i in range(steps.size()):
			if typeof(steps[i]) == TYPE_DICTIONARY and str(steps[i].get("id", "")) == created_fix_id:
				_selected_step_idx = i
				break
		_set_status("Gemini 4 Hydrogen created [FIX] patch ✓", false)
	elif had_diagnosing:
		_set_status("Synced ✓", false)
	else:
		_set_status("Synced ✓", false)
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
		_status_label.modulate = Color(0.55, 0.78, 0.98)


func _on_connect_submitted(_text: String) -> void:
	_on_connect_pressed()


func _on_connect_pressed() -> void:
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
	_sync.clear_link_token()
	_payload = {}
	_selected_feature_id = ""
	_selected_step_idx = 0
	_show_token_editor = true
	_status_label.text = "Disconnected"
	_status_label.modulate = Color(0.65, 0.72, 0.82)
	_refresh_view()


func _on_sync_pressed() -> void:
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
		_check_update_btn.text = "↻ Check for Plugin Update"
	if _version_label != null:
		_version_label.text = "Plugin v%s" % local_ver
	if up_to_date:
		_available_remote_version = ""
		_refresh_update_banner()
		if was_manual:
			_set_status("Plugin v%s is up to date ✓" % local_ver, false)
	else:
		_available_remote_version = remote_ver
		_refresh_update_banner()
		if was_manual:
			_set_status("⬆ Plugin v%s available — click Update Now above." % remote_ver, false)


func _on_plugin_update_failed(message: String) -> void:
	_checking_plugin_update = false
	_updating_plugin = false
	if _check_update_btn != null:
		_check_update_btn.disabled = false
		_check_update_btn.text = "↻ Check for Plugin Update"
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
		_set_status("Updated to v%s ✓ — toggle LAYERS plugin off/on to reload." % new_ver, false)
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
		_set_status("Updated to v%s ✓ — toggle LAYERS plugin off/on to reload." % new_ver, false)
		return

	var reloader := Node.new()
	reloader.set_script(reloader_script)
	reloader.set("ei", editor_interface)
	reloader.set("plugin_key", plugin_key)
	reloader.set("gd_paths", updated_gd_paths)
	base_ctrl.add_child(reloader)
	reloader.call_deferred("run_reload")
