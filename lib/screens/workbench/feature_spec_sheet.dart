import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'plain_doc_widgets.dart';
import 'stage2_inline_editors.dart';
import 'workbench_shared_widgets.dart';

/// Flat plain-document Feature Slice Spec Sheet rendered in strict PIE-first
/// order: (1) Conditional Open Fixes, (2) Playtest (PIE) + Broken in PIE?,
/// (3) Goal / Scope, (4) Controls, (5) Semantic Table Tuning, (6) Cues.
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
  final TextEditingController _fixLogController = TextEditingController();

  bool _editingScope = false;
  bool _showFixLogInput = false;
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
      _fixLogController.clear();
      _editingScope = false;
      _showFixLogInput = false;
      _showControlForm = false;
      _editingControlIndex = null;
      _addingTuning = false;
      _addingCue = false;
      _addingCheck = false;
    }
  }

  @override
  void dispose() {
    _fixInputController.dispose();
    _fixLogController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final epic = widget.epic;
    final feat = widget.feature;
    final isLockedBaseline = widget.isLockedBaseline;
    final isDark = widget.isDark;
    final target = wb.unrealArchitectureMode;
    final relVer = wb.activeReleaseVersionTag;
    final effectiveChecks = feat.effectiveChecksForRelease(relVer);
    final openFixes = feat.openFixes;

    final border = AppTheme.borderFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Conditional Fixes (completely hidden when openFixes is empty)
        if (openFixes.isNotEmpty)
          EpicSectionCard(
            isDark: isDark,
            code: 'FIX',
            title: 'Fixes (${openFixes.length})',
            child: FeatureOpenFixesList(
              openFixes: openFixes,
              isLockedBaseline: isLockedBaseline,
              isDark: isDark,
              onResolve: (fixId) =>
                  wb.resolveFeatureFix(epic.id, feat.id, fixId),
              onDelete: (fixId) => wb.deleteFeatureFix(epic.id, feat.id, fixId),
            ),
          ),

        // 2. Playtest (PIE) + Broken in PIE?
        EpicSectionCard(
          isDark: isDark,
          code: 'PIE',
          title:
              'Playtest (${feat.passedChecksCountForRelease(relVer)}/${effectiveChecks.length})',
          trailing: (isLockedBaseline || _addingCheck)
              ? null
              : PlainTextLink(
                  key: const ValueKey('feature_add_check_btn'),
                  label: '+ Add check',
                  isDark: isDark,
                  fontSize: 11.5,
                  color: focal,
                  onTap: () => setState(() => _addingCheck = true),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_addingCheck && !isLockedBaseline)
                InlineSingleLineAdderBox(
                  isDark: isDark,
                  labelText: 'Playtest Check',
                  hintText:
                      'e.g. Tap dash -> breaks crab shell within 0.25s',
                  submitLabel: 'Add Check',
                  inputKey: const ValueKey('feature_check_input'),
                  saveBtnKey: const ValueKey('feature_check_save_btn'),
                  onSubmit: (text) {
                    wb.addFeatureCheck(epic.id, feat.id, text);
                    setState(() => _addingCheck = false);
                  },
                  onCancel: () => setState(() => _addingCheck = false),
                ),
              for (int i = 0; i < effectiveChecks.length; i++) ...[
                () {
                  final chk = effectiveChecks[i];
                  final isBaseCheckInDeltaFeature =
                      relVer != 'v0.1' &&
                      feat.releaseDeltaChecks.isNotEmpty &&
                      feat.checks.any(
                        (b) => identical(b, chk) || b.id == chk.id,
                      );
                  final canDeleteCheck =
                      !isLockedBaseline && !isBaseCheckInDeltaFeature;

                  return PlainHoverRemoveRow(
                    isDark: isDark,
                    showBottomBorder: i < effectiveChecks.length - 1,
                    removeKey: canDeleteCheck
                        ? ValueKey('feature_check_delete_${chk.id}')
                        : null,
                    removeTooltip: 'Remove check',
                    onRemove: canDeleteCheck
                        ? () => wb.removeFeatureCheck(epic.id, feat.id, chk.id)
                        : null,
                    child: Material(
                      type: MaterialType.transparency,
                      child: CheckboxListTile(
                        key: ValueKey('feature_check_${chk.id}'),
                        value: chk.passed,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: isLockedBaseline
                            ? null
                            : (val) => wb.toggleFeatureCheck(
                                  epic.id,
                                  feat.id,
                                  chk.id,
                                  val,
                                ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          chk.text,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: chk.passed ? green : primary,
                            decoration: chk.passed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }(),
              ],
              if (widget.passGateHint != null) ...[
                const SizedBox(height: 8),
                Text(
                  key: const ValueKey('pass_gate_hint'),
                  widget.passGateHint!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: amber,
                  ),
                ),
              ],
              if (!isLockedBaseline) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('flag_fix_input'),
                        controller: _fixInputController,
                        style: TextStyle(fontSize: 13, color: primary),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText:
                              'Broken in PIE? Log an issue to generate a focused [FIX]...',
                          hintStyle: TextStyle(fontSize: 12.5, color: muted),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: red),
                          ),
                        ),
                        onSubmitted: (_) =>
                            _submitFlagFix(wb, epic.id, feat.id),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PlainTextLink(
                      key: const ValueKey('toggle_fix_log_btn'),
                      label: _showFixLogInput ? 'Hide log' : '+ Paste log',
                      isDark: isDark,
                      fontSize: 11.5,
                      color: _showFixLogInput ? muted : secondary,
                      onTap: () =>
                          setState(() => _showFixLogInput = !_showFixLogInput),
                    ),
                    const SizedBox(width: 10),
                    PlainPrimaryButton(
                      key: const ValueKey('flag_fix_btn'),
                      label: 'Flag [FIX]',
                      outlined: true,
                      isDark: isDark,
                      foregroundColor: red,
                      onPressed: () => _submitFlagFix(wb, epic.id, feat.id),
                    ),
                  ],
                ),
                if (_showFixLogInput) ...[
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('flag_fix_log_input'),
                    controller: _fixLogController,
                    minLines: 2,
                    maxLines: 5,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: primary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText:
                          'Paste UE5 Output Log, Blueprint compile error, or C++ build error (optional)...',
                      hintStyle: TextStyle(fontSize: 11.5, color: muted),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: red),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),

        // 3. Goal / Scope
        EpicSectionCard(
          isDark: isDark,
          code: '§01',
          title: 'Goal & Scope',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isLockedBaseline) ...[
                PlainTextLink(
                  key: const ValueKey('feature_edit_scope_btn'),
                  label: _editingScope ? 'Cancel' : 'Edit Scope',
                  isDark: isDark,
                  fontSize: 11.5,
                  color: _editingScope ? muted : focal,
                  onTap: () => setState(() => _editingScope = !_editingScope),
                ),
                const SizedBox(width: 12),
              ],
              PlainTextLink(
                key: const ValueKey('feature_parent_epic_link'),
                label: '← ${epic.code}',
                isDark: isDark,
                mono: true,
                fontSize: 11.5,
                color: secondary,
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  wb.selectEpic(epic.id);
                },
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editingScope && !isLockedBaseline) ...[
                InlineScopeEditorBox(
                  isDark: isDark,
                  initialGoal: feat.goal,
                  initialInScope: feat.inScope,
                  initialDoneWhen: feat.doneWhen,
                  initialDelta: feat.releaseDelta,
                  showDeltaField: relVer != 'v0.1',
                  goalInputKey: const ValueKey('feature_scope_goal_input'),
                  inScopeInputKey: const ValueKey('feature_scope_in_scope_input'),
                  doneWhenInputKey:
                      const ValueKey('feature_scope_done_when_input'),
                  deltaInputKey: const ValueKey('feature_scope_delta_input'),
                  saveBtnKey: const ValueKey('feature_scope_save_btn'),
                  onSave: ({
                    required String goal,
                    required List<String> inScope,
                    required List<String> doneWhen,
                    required String delta,
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
              ] else ...[
                PlainEditableLineField(
                  fieldKey: ValueKey('feature_goal_inline_${feat.id}'),
                  value: feat.goal,
                  isDark: isDark,
                  multiLine: true,
                  minLines: 1,
                  allowEmpty: true,
                  readOnly: isLockedBaseline,
                  hintText: 'Define 1 plain-English sentence for this feature...',
                  style: TextStyle(fontSize: 14, color: primary, height: 1.45),
                  onCommit: (val) =>
                      wb.updateFeatureScope(epic.id, feat.id, goal: val),
                ),
                if (relVer != 'v0.1' && feat.releaseDelta.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '+DELTA ($relVer): ${feat.releaseDelta}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: amber,
                    ),
                  ),
                ],
                if (feat.inScope.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final s in feat.inScope)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '— $s',
                        style: TextStyle(fontSize: 13.5, color: secondary),
                      ),
                    ),
                ],
                if (feat.doneWhen.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final d in feat.doneWhen)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Done: $d',
                        style: TextStyle(fontSize: 13, color: secondary),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),

        // 4. Controls
        EpicSectionCard(
          isDark: isDark,
          code: '§02',
          title: 'Controls',
          trailing: (isLockedBaseline || _showControlForm)
              ? null
              : PlainTextLink(
                  key: const ValueKey('feature_add_control_btn'),
                  label: '+ Add input',
                  isDark: isDark,
                  fontSize: 11.5,
                  color: focal,
                  onTap: () {
                    setState(() {
                      _showControlForm = true;
                      _editingControlIndex = null;
                    });
                  },
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showControlForm && !isLockedBaseline)
                InlineControlEditorBox(
                  key: ValueKey('ctrl_editor_${_editingControlIndex ?? 'new'}'),
                  isDark: isDark,
                  initialAction: _editingControlIndex != null
                      ? feat.controls[_editingControlIndex!].action
                      : '',
                  initialTrigger: _editingControlIndex != null
                      ? feat.controls[_editingControlIndex!].trigger
                      : 'Pressed',
                  initialRule: _editingControlIndex != null
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
                  onCancel: () {
                    setState(() {
                      _showControlForm = false;
                      _editingControlIndex = null;
                    });
                  },
                ),
              if (feat.controls.isEmpty)
                Text(
                  'No Enhanced Input bindings added yet.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              else
                for (int i = 0; i < feat.controls.length; i++)
                  PlainHoverRemoveRow(
                    isDark: isDark,
                    showBottomBorder: i < feat.controls.length - 1,
                    removeKey: !isLockedBaseline
                        ? ValueKey('feature_control_delete_$i')
                        : null,
                    removeTooltip: 'Delete input',
                    onRemove: isLockedBaseline
                        ? null
                        : () {
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
                            wb.removeFeatureControl(epic.id, feat.id, i);
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                children: [
                                  Text(
                                    feat.controls[i].action,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: primary,
                                    ),
                                  ),
                                  Text(
                                    '· ${feat.controls[i].trigger}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                                if (feat.controls[i].rule.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    feat.controls[i].rule,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: secondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!isLockedBaseline)
                            PlainTextLink(
                              key: ValueKey('feature_control_edit_$i'),
                              label: 'Edit',
                              isDark: isDark,
                              fontSize: 11.5,
                              color: muted,
                              onTap: () {
                                setState(() {
                                  _editingControlIndex = i;
                                  _showControlForm = true;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),

        // 5. Semantic Tuning Table
        EpicSectionCard(
          isDark: isDark,
          code: '§03',
          title: 'Tuning · ${target.tuningColumnLabel}',
          trailing: (isLockedBaseline || _addingTuning)
              ? null
              : PlainTextLink(
                  key: const ValueKey('feature_add_tuning_btn'),
                  label: '+ Add var',
                  isDark: isDark,
                  fontSize: 11.5,
                  color: focal,
                  onTap: () => setState(() => _addingTuning = true),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_addingTuning && !isLockedBaseline)
                InlineTuningAddBox(
                  isDark: isDark,
                  keyInputKey: const ValueKey('feature_tuning_key_input'),
                  valueInputKey: const ValueKey('feature_tuning_value_input'),
                  unitInputKey: const ValueKey('feature_tuning_unit_input'),
                  saveBtnKey: const ValueKey('feature_tuning_save_btn'),
                  onAdd: (keyName, value, unit) {
                    wb.addFeatureTuningParam(
                      epic.id,
                      feat.id,
                      key: keyName,
                      value: value,
                      unit: unit,
                    );
                    setState(() => _addingTuning = false);
                  },
                  onCancel: () => setState(() => _addingTuning = false),
                ),
              if (feat.tuning.isEmpty)
                Text(
                  'No exposed tuning parameters yet.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              else
                Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  columnWidths: <int, TableColumnWidth>{
                    0: const FlexColumnWidth(2.4),
                    1: const FlexColumnWidth(1.4),
                    2: const FlexColumnWidth(0.9),
                    if (!isLockedBaseline) 3: const FixedColumnWidth(28),
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(color: border, width: 1),
                    bottom: BorderSide(color: border, width: 1),
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: border, width: 1),
                        ),
                      ),
                      children: [
                        _tuningHeaderCell('KEY', muted),
                        _tuningHeaderCell('VALUE', muted),
                        _tuningHeaderCell('UNIT', muted),
                        if (!isLockedBaseline) const SizedBox(height: 22),
                      ],
                    ),
                    for (int i = 0; i < feat.tuning.length; i++)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 2,
                            ),
                            child: Text(
                              feat.tuning[i].key,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: primary,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 2,
                              horizontal: 4,
                            ),
                            child: PlainEditableLineField(
                              fieldKey: ValueKey('tuning_input_${feat.id}_$i'),
                              value: feat.tuning[i].value,
                              isDark: isDark,
                              readOnly: isLockedBaseline,
                              allowEmpty: true,
                              trimOnCommit: false,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: focal,
                              ),
                              onChanged: (val) => wb.updateFeatureTuningParam(
                                epic.id,
                                feat.id,
                                i,
                                val,
                              ),
                              onCommit: (_) {},
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 4,
                            ),
                            child: Text(
                              feat.tuning[i].unit,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ),
                          if (!isLockedBaseline)
                            _TuningDeleteCell(
                              deleteKey: ValueKey('tuning_delete_${feat.id}_$i'),
                              isDark: isDark,
                              onDelete: () => wb.removeFeatureTuningParam(
                                epic.id,
                                feat.id,
                                i,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ),

        // 6. Cues
        EpicSectionCard(
          isDark: isDark,
          code: '§04',
          title: 'Cues (VFX, SFX & HUD)',
          trailing: (isLockedBaseline || _addingCue)
              ? null
              : PlainTextLink(
                  key: const ValueKey('feature_add_cue_btn'),
                  label: '+ Add cue',
                  isDark: isDark,
                  fontSize: 11.5,
                  color: focal,
                  onTap: () => setState(() => _addingCue = true),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_addingCue && !isLockedBaseline)
                InlineSingleLineAdderBox(
                  isDark: isDark,
                  labelText: 'Cue (VFX, SFX, HUD, or Camera Shake)',
                  hintText: 'e.g. Shell crack spark + camera punch on dash hit',
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
                  'No viewport or audio cues specified yet.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              else
                for (int i = 0; i < feat.cues.length; i++)
                  PlainHoverRemoveRow(
                    isDark: isDark,
                    showBottomBorder: i < feat.cues.length - 1,
                    removeKey: !isLockedBaseline
                        ? ValueKey('feature_cue_delete_$i')
                        : null,
                    removeTooltip: 'Remove cue',
                    onRemove: isLockedBaseline
                        ? null
                        : () => wb.removeFeatureCue(epic.id, feat.id, i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '— ${feat.cues[i]}',
                        style: TextStyle(fontSize: 13.5, color: secondary),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _tuningHeaderCell(String label, Color muted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2, right: 4),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: muted,
        ),
      ),
    );
  }

  void _submitFlagFix(
    WorkbenchProvider wb,
    String epicId,
    String featureId,
  ) {
    final text = _fixInputController.text.trim();
    if (text.isEmpty) return;
    final logText = _fixLogController.text.trim();
    _fixInputController.clear();
    _fixLogController.clear();
    if (_showFixLogInput) {
      setState(() => _showFixLogInput = false);
    }
    wb.flagFeatureFix(epicId, featureId, text, errorLog: logText);
  }
}

class _TuningDeleteCell extends StatefulWidget {
  final Key deleteKey;
  final bool isDark;
  final VoidCallback onDelete;

  const _TuningDeleteCell({
    required this.deleteKey,
    required this.isDark,
    required this.onDelete,
  });

  @override
  State<_TuningDeleteCell> createState() => _TuningDeleteCellState();
}

class _TuningDeleteCellState extends State<_TuningDeleteCell> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _focused;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: Tooltip(
          message: 'Remove variable',
          child: InkWell(
            key: widget.deleteKey,
            onTap: widget.onDelete,
            child: Opacity(
              opacity: active ? 1.0 : 0.35,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(
                  '×',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.0,
                    color: active
                        ? AppTheme.accentRedFor(widget.isDark)
                        : AppTheme.textMutedFor(widget.isDark),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
