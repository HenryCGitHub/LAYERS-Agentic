import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'stage2_inline_editors.dart';
import 'workbench_shared_widgets.dart';

class FeatureSpecSheet extends StatefulWidget {
  final WorkbenchProvider workbench;
  final EpicSpec epic;
  final FeatureSpec feature;
  final bool isLockedBaseline;
  final bool isDark;
  final String selectionKey;
  final String? passGateHint;

  const FeatureSpecSheet({
    super.key,
    required this.workbench,
    required this.epic,
    required this.feature,
    required this.isLockedBaseline,
    required this.isDark,
    required this.selectionKey,
    required this.passGateHint,
  });

  @override
  State<FeatureSpecSheet> createState() => _FeatureSpecSheetState();
}

class _FeatureSpecSheetState extends State<FeatureSpecSheet> {
  final TextEditingController _fixInputController = TextEditingController();
  bool _editingScope = false;
  bool _showControlForm = false;
  int? _editingControlIndex;
  bool _addingTuning = false;
  bool _addingCue = false;
  bool _addingCheck = false;

  @override
  void didUpdateWidget(covariant FeatureSpecSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionKey != widget.selectionKey) {
      _fixInputController.clear();
      _editingScope = false;
      _showControlForm = false;
      _editingControlIndex = null;
      _addingTuning = false;
      _addingCue = false;
      _addingCheck = false;
    } else if (_editingControlIndex != null &&
        _editingControlIndex! >= widget.feature.controls.length) {
      _showControlForm = false;
      _editingControlIndex = null;
    }
  }

  @override
  void dispose() {
    _fixInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.textPrimaryFor(widget.isDark);
    final secondary = AppTheme.textSecondaryFor(widget.isDark);
    final muted = AppTheme.textMutedFor(widget.isDark);
    final border = AppTheme.borderFor(widget.isDark);
    final cyan = AppTheme.accentCyanFor(widget.isDark);
    final green = AppTheme.accentGreenFor(widget.isDark);
    final red = AppTheme.accentRedFor(widget.isDark);
    final amber = AppTheme.accentAmberFor(widget.isDark);
    return _buildSheetContent(
      context,
      widget.workbench,
      widget.epic,
      widget.feature,
      widget.isLockedBaseline,
      widget.isDark,
      primary,
      secondary,
      muted,
      border,
      cyan,
      green,
      red,
      amber,
    );
  }

  Widget _buildSheetContent(
    BuildContext context,
    WorkbenchProvider wb,
    EpicSpec epic,
    FeatureSpec feat,
    bool isLockedBaseline,
    bool isDark,
    Color primary,
    Color secondary,
    Color muted,
    Color border,
    Color cyan,
    Color green,
    Color red,
    Color amber,
  ) {
    final target = wb.unrealArchitectureMode;
    final relVer = wb.activeReleaseVersionTag;
    final effChecks = feat.effectiveChecksForRelease(relVer);
    final checkedCount = effChecks.where((c) => c.passed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // §01 Feature Scope
        EpicSectionCard(
          isDark: isDark,
          code: '§01',
          title: 'Feature Scope',
          trailing: Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!isLockedBaseline)
                TextButton.icon(
                  key: const ValueKey('feature_edit_scope_btn'),
                  onPressed: () =>
                      setState(() => _editingScope = !_editingScope),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  icon: Icon(
                    _editingScope ? Icons.close : Icons.edit_outlined,
                    size: 13,
                  ),
                  label: Text(
                    _editingScope ? 'Cancel' : 'Edit Scope',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              InkWell(
                key: const ValueKey('feature_parent_epic_link'),
                onTap: () => wb.selectEpic(epic.id),
                child: Text(
                  'Owning Epic: ${epic.code} · ${epic.title}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: cyan,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_editingScope && !isLockedBaseline)
                InlineScopeEditorBox(
                  isDark: isDark,
                  initialGoal: feat.goal,
                  initialInScope: feat.inScope,
                  initialDoneWhen: feat.doneWhen,
                  initialDelta: feat.releaseDelta,
                  showDeltaField: relVer != 'v0.1',
                  goalInputKey: const ValueKey('feature_scope_goal_input'),
                  inScopeInputKey:
                      const ValueKey('feature_scope_in_scope_input'),
                  doneWhenInputKey:
                      const ValueKey('feature_scope_done_when_input'),
                  deltaInputKey: const ValueKey('feature_scope_delta_input'),
                  saveBtnKey: const ValueKey('feature_scope_save_btn'),
                  onSave: ({
                    required goal,
                    required inScope,
                    required doneWhen,
                    required delta,
                  }) {
                    wb.updateFeatureScope(
                      epic.id,
                      feat.id,
                      goal: goal,
                      inScope: inScope,
                      doneWhen: doneWhen,
                      releaseDelta: relVer != 'v0.1' ? delta : null,
                    );
                    setState(() => _editingScope = false);
                  },
                  onCancel: () => setState(() => _editingScope = false),
                ),
              if (relVer != 'v0.1' && feat.releaseDelta.trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: amber.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    '$relVer Upgrade Delta: ${feat.releaseDelta}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ),
              ],
              Text(
                'Goal: ${feat.goal}',
                style: TextStyle(fontSize: 14, color: primary, height: 1.45),
              ),
              if (feat.inScope.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'In Scope',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 4),
                for (final s in feat.inScope)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• $s',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ),
              ],
              if (feat.doneWhen.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Done When',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 4),
                for (final d in feat.doneWhen)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• $d',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §02 Input Actions (Enhanced Input)
        EpicSectionCard(
          isDark: isDark,
          code: '§02',
          title: 'Input Actions (${target.inputContractLabel})',
          trailing: !isLockedBaseline
              ? TextButton.icon(
                  key: const ValueKey('feature_add_control_btn'),
                  onPressed: () => setState(() {
                    _editingControlIndex = null;
                    _showControlForm = !_showControlForm;
                  }),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  icon: Icon(
                    _showControlForm ? Icons.close : Icons.add,
                    size: 13.5,
                  ),
                  label: Text(
                    _showControlForm ? 'Close' : '+ Add Input',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_showControlForm && !isLockedBaseline)
                InlineControlEditorBox(
                  key: ValueKey('ctrl_editor_${_editingControlIndex ?? 'new'}'),
                  isDark: isDark,
                  initialAction: _editingControlIndex != null &&
                          _editingControlIndex! < feat.controls.length
                      ? feat.controls[_editingControlIndex!].action
                      : '',
                  initialTrigger: _editingControlIndex != null &&
                          _editingControlIndex! < feat.controls.length
                      ? feat.controls[_editingControlIndex!].trigger
                      : 'Pressed',
                  initialRule: _editingControlIndex != null &&
                          _editingControlIndex! < feat.controls.length
                      ? feat.controls[_editingControlIndex!].rule
                      : '',
                  actionInputKey:
                      const ValueKey('feature_control_action_input'),
                  triggerInputKey:
                      const ValueKey('feature_control_trigger_input'),
                  ruleInputKey: const ValueKey('feature_control_rule_input'),
                  saveBtnKey: const ValueKey('feature_control_save_btn'),
                  onSave: (action, trigger, rule) {
                    wb.upsertFeatureControl(
                      epic.id,
                      feat.id,
                      index: _editingControlIndex,
                      action: action,
                      trigger: trigger,
                      rule: rule,
                    );
                    setState(() {
                      _showControlForm = false;
                      _editingControlIndex = null;
                    });
                  },
                  onCancel: () => setState(() {
                    _showControlForm = false;
                    _editingControlIndex = null;
                  }),
                ),
              if (feat.controls.isEmpty)
                Text(
                  'Event/system-driven slice — uses parent Epic Enhanced Input triggers.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              else
                Table(
                  columnWidths: <int, TableColumnWidth>{
                    0: const FlexColumnWidth(1.5),
                    1: const FlexColumnWidth(1.1),
                    2: const FlexColumnWidth(2.6),
                    if (!isLockedBaseline) 3: const FixedColumnWidth(62),
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(color: border),
                  ),
                  children: [
                    for (int i = 0; i < feat.controls.length; i++)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Text(
                              feat.controls[i].action,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cyan,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Text(
                              feat.controls[i].trigger,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                color: muted,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Text(
                              feat.controls[i].rule,
                              style: TextStyle(fontSize: 13, color: primary),
                            ),
                          ),
                          if (!isLockedBaseline)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  InkWell(
                                    key: ValueKey('feature_control_edit_$i'),
                                    onTap: () => setState(() {
                                      _editingControlIndex = i;
                                      _showControlForm = true;
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.edit_outlined,
                                        size: 14,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    key: ValueKey('feature_control_delete_$i'),
                                    onTap: () {
                                      if (_editingControlIndex == i) {
                                        setState(() {
                                          _showControlForm = false;
                                          _editingControlIndex = null;
                                        });
                                      } else if (_editingControlIndex != null &&
                                          _editingControlIndex! > i) {
                                        setState(() {
                                          _editingControlIndex =
                                              _editingControlIndex! - 1;
                                        });
                                      }
                                      wb.removeFeatureControl(
                                        epic.id,
                                        feat.id,
                                        i,
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 14,
                                        color: red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §03 Exposed Tuning
        EpicSectionCard(
          isDark: isDark,
          code: '§03',
          title: 'Exposed Tuning (${target.tuningColumnLabel})',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                isLockedBaseline
                    ? 'Locked baseline'
                    : 'Included in CoPilot Feature Prompt',
                style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: muted),
              ),
              if (!isLockedBaseline)
                TextButton.icon(
                  key: const ValueKey('feature_add_tuning_btn'),
                  onPressed: () =>
                      setState(() => _addingTuning = !_addingTuning),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  icon: Icon(_addingTuning ? Icons.close : Icons.add, size: 13.5),
                  label: Text(
                    _addingTuning ? 'Close' : '+ Add Variable',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_addingTuning && !isLockedBaseline)
                InlineTuningAddBox(
                  isDark: isDark,
                  keyInputKey: const ValueKey('feature_tuning_key_input'),
                  valueInputKey: const ValueKey('feature_tuning_value_input'),
                  unitInputKey: const ValueKey('feature_tuning_unit_input'),
                  saveBtnKey: const ValueKey('feature_tuning_save_btn'),
                  onAdd: (key, value, unit) {
                    wb.addFeatureTuningParam(
                      epic.id,
                      feat.id,
                      key: key,
                      value: value,
                      unit: unit,
                    );
                    setState(() => _addingTuning = false);
                  },
                  onCancel: () => setState(() => _addingTuning = false),
                ),
              if (feat.tuning.isEmpty)
                Text(
                  'No exposed tuning variables on this slice.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (int i = 0; i < feat.tuning.length; i++)
                      LiveTuningChip(
                        key: ValueKey(
                          'tuning_chip_${wb.activeReleaseId}_${feat.id}_${feat.tuning[i].key}_$i',
                        ),
                        inputKey: ValueKey('tuning_input_${feat.id}_$i'),
                        param: feat.tuning[i],
                        isDark: isDark,
                        readOnly: isLockedBaseline,
                        deleteKey: ValueKey('tuning_delete_${feat.id}_$i'),
                        onDelete: isLockedBaseline
                            ? null
                            : () => wb.removeFeatureTuningParam(
                                  epic.id,
                                  feat.id,
                                  i,
                                ),
                        onChanged: (val) => wb.updateFeatureTuningParam(
                          epic.id,
                          feat.id,
                          i,
                          val,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §04 Viewport, UI & Audio Cues
        EpicSectionCard(
          isDark: isDark,
          code: '§04',
          title: 'Viewport, UI & Audio Cues',
          trailing: !isLockedBaseline
              ? TextButton.icon(
                  key: const ValueKey('feature_add_cue_btn'),
                  onPressed: () => setState(() => _addingCue = !_addingCue),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  icon: Icon(_addingCue ? Icons.close : Icons.add, size: 13.5),
                  label: Text(
                    _addingCue ? 'Close' : '+ Add Cue',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_addingCue && !isLockedBaseline)
                InlineSingleLineAdderBox(
                  isDark: isDark,
                  labelText: 'Viewport, UI, or Audio Cue',
                  hintText: 'e.g. Orange thruster sparks + impact thud SFX',
                  submitLabel: 'Add Cue',
                  inputKey: const ValueKey('feature_cue_input'),
                  saveBtnKey: const ValueKey('feature_cue_save_btn'),
                  onSubmit: (text) {
                    wb.addFeatureCue(epic.id, feat.id, text);
                    setState(() => _addingCue = false);
                  },
                  onCancel: () => setState(() => _addingCue = false),
                ),
              if (feat.cues.isEmpty)
                Text(
                  'Minimal greybox feedback visual + confirmation sound.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              else
                for (int i = 0; i < feat.cues.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '• ${feat.cues[i]}',
                            style: TextStyle(fontSize: 13, color: primary),
                          ),
                        ),
                        if (!isLockedBaseline)
                          InkWell(
                            key: ValueKey('feature_cue_delete_$i'),
                            onTap: () => wb.removeFeatureCue(
                              epic.id,
                              feat.id,
                              i,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §05 Playtest Gate & [FIX] Notes
        EpicSectionCard(
          isDark: isDark,
          code: '§05',
          title: 'Playtest Gate & [FIX] Notes',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$checkedCount/${effChecks.length} Checked · ${feat.openFixesCount} Open [FIX]',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: effChecks.isNotEmpty && checkedCount == effChecks.length
                      ? green
                      : muted,
                ),
              ),
              if (!isLockedBaseline)
                TextButton.icon(
                  key: const ValueKey('feature_add_check_btn'),
                  onPressed: () => setState(() => _addingCheck = !_addingCheck),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  icon: Icon(
                    _addingCheck ? Icons.close : Icons.add,
                    size: 13.5,
                  ),
                  label: Text(
                    _addingCheck ? 'Close' : '+ Add Check',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_addingCheck && !isLockedBaseline)
                InlineSingleLineAdderBox(
                  isDark: isDark,
                  labelText: 'PIE Playtest Gate (Action -> Result)',
                  hintText: 'e.g. Press IA_Dash -> Mech dashes 450 cm forward',
                  submitLabel: 'Add Check',
                  inputKey: const ValueKey('feature_check_input'),
                  saveBtnKey: const ValueKey('feature_check_save_btn'),
                  onSubmit: (text) {
                    wb.addFeatureCheck(epic.id, feat.id, text);
                    setState(() => _addingCheck = false);
                  },
                  onCancel: () => setState(() => _addingCheck = false),
                ),
              for (final chk in effChecks)
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        type: MaterialType.transparency,
                        child: CheckboxListTile(
                          key: ValueKey('feature_check_${chk.id}'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: chk.passed,
                          onChanged: isLockedBaseline
                              ? null
                              : (val) => wb.toggleFeatureCheck(
                                    epic.id,
                                    feat.id,
                                    chk.id,
                                    val,
                                  ),
                          title: Text(
                            chk.text,
                            style: TextStyle(
                              fontSize: 13,
                              color: chk.passed ? green : primary,
                              decoration:
                                  chk.passed ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!isLockedBaseline &&
                        !(relVer.trim() != feat.introducedIn.trim() &&
                            feat.releaseDelta.trim().isNotEmpty &&
                            feat.checks.any(
                              (b) => identical(b, chk) || b.id == chk.id,
                            )))
                      IconButton(
                        key: ValueKey('feature_check_delete_${chk.id}'),
                        icon: Icon(Icons.close_rounded, size: 15, color: muted),
                        tooltip: 'Remove check',
                        onPressed: () => wb.removeFeatureCheck(
                          epic.id,
                          feat.id,
                          chk.id,
                        ),
                      ),
                  ],
                ),

              if (widget.passGateHint != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.passGateHint!,
                  key: const ValueKey('pass_gate_hint'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: amber,
                  ),
                ),
              ],

              if (!isLockedBaseline) ...[
                const SizedBox(height: 14),
                Text(
                  'Flag Playtest Revision ([FIX]) — switches Feature Build Prompt to Focused [FIX] Pass:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 160,
                        maxWidth: 520,
                      ),
                      child: TextField(
                        key: const ValueKey('flag_fix_input'),
                        controller: _fixInputController,
                        style: TextStyle(fontSize: 13, color: primary),
                        decoration: InputDecoration(
                          hintText:
                              'e.g. Dash stops early against north barrier wall...',
                          hintStyle: TextStyle(fontSize: 12.5, color: muted),
                          isDense: true,
                        ),
                        onSubmitted: (_) =>
                            _submitFlagFix(wb, epic.id, feat.id),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('flag_fix_btn'),
                      onPressed: () => _submitFlagFix(wb, epic.id, feat.id),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: red,
                        side: BorderSide(color: red.withValues(alpha: 0.45)),
                      ),
                      icon: const Icon(Icons.flag_outlined, size: 15),
                      label: const Text('Flag [FIX]'),
                    ),
                  ],
                ),
              ],

              if (feat.fixes.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final fx in feat.fixes)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: fx.resolved
                          ? green.withValues(alpha: 0.08)
                          : red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(
                        color: fx.resolved
                            ? green.withValues(alpha: 0.3)
                            : red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          fx.resolved ? '[FIXED]' : '[FIX]',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: fx.resolved ? green : red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fx.text,
                            style: TextStyle(
                              fontSize: 13,
                              color: primary,
                              decoration:
                                  fx.resolved ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        if (!fx.resolved && !isLockedBaseline)
                          TextButton(
                            key: ValueKey('resolve_fix_${fx.id}'),
                            onPressed: () => wb.resolveFeatureFix(
                              epic.id,
                              feat.id,
                              fx.id,
                            ),
                            child: Text(
                              'Resolve ✓',
                              style: TextStyle(color: green, fontSize: 12),
                            ),
                          ),
                        if (!isLockedBaseline)
                          IconButton(
                            icon: Icon(Icons.close, size: 15, color: muted),
                            onPressed: () =>
                                wb.deleteFeatureFix(epic.id, feat.id, fx.id),
                            tooltip: 'Remove note',
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }

  void _submitFlagFix(
    WorkbenchProvider wb,
    String epicId,
    String featureId,
  ) {
    final text = _fixInputController.text.trim();
    if (text.isEmpty) return;
    _fixInputController.clear();
    wb.flagFeatureFix(epicId, featureId, text);
  }
}
