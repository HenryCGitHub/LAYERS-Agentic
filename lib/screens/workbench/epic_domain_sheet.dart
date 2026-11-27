import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'plain_doc_widgets.dart';
import 'stage2_inline_editors.dart';
import 'workbench_shared_widgets.dart';

/// Flat plain-document Epic Domain Sheet (`700px` single-column, 1px dividers,
/// zero card chrome or pill clutter).
class EpicDomainSheet extends StatefulWidget {
  final WorkbenchProvider workbench;
  final EpicSpec epic;
  final bool isDark;
  final String selectionKey;

  const EpicDomainSheet({
    super.key,
    required this.workbench,
    required this.epic,
    required this.isDark,
    required this.selectionKey,
  });

  @override
  State<EpicDomainSheet> createState() => _EpicDomainSheetState();
}

class _EpicDomainSheetState extends State<EpicDomainSheet> {
  bool _editingScope = false;
  bool _showOwnerForm = false;
  int? _editingOwnerIndex;
  final TextEditingController _ownerPathController = TextEditingController();
  final TextEditingController _ownerRoleController = TextEditingController();
  bool _editingStateRules = false;
  final TextEditingController _statesController = TextEditingController();
  final TextEditingController _interruptsController = TextEditingController();
  bool _addingCut = false;
  bool _showAddFeature = false;
  final TextEditingController _newFeatureTitleController =
      TextEditingController();
  final TextEditingController _newFeatureGoalController =
      TextEditingController();

  @override
  void didUpdateWidget(covariant EpicDomainSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionKey != widget.selectionKey) {
      _editingScope = false;
      _showOwnerForm = false;
      _editingOwnerIndex = null;
      _ownerPathController.clear();
      _ownerRoleController.clear();
      _editingStateRules = false;
      _addingCut = false;
      _showAddFeature = false;
      _newFeatureTitleController.clear();
      _newFeatureGoalController.clear();
    } else if (_editingStateRules) {
      final oldStates = oldWidget.epic.states.join(' -> ');
      final nextStates = widget.epic.states.join(' -> ');
      final oldRules = oldWidget.epic.interrupts.join('\n');
      final nextRules = widget.epic.interrupts.join('\n');
      if (oldStates != nextStates) {
        _statesController.text = nextStates;
      }
      if (oldRules != nextRules) {
        _interruptsController.text = nextRules;
      }
    }
  }

  @override
  void dispose() {
    _ownerPathController.dispose();
    _ownerRoleController.dispose();
    _statesController.dispose();
    _interruptsController.dispose();
    _newFeatureTitleController.dispose();
    _newFeatureGoalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final epic = widget.epic;
    final isDark = widget.isDark;
    final border = AppTheme.borderFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final states = epic.states;
    final rules = epic.interrupts;
    final ownershipList = epic.sceneOwnership;
    final relVer = wb.activeReleaseVersionTag;
    final visibleFeatures = wb.visibleFeaturesForEpic(epic);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // §01 Domain Scope
        EpicSectionCard(
          isDark: isDark,
          code: '§01',
          title: 'Domain Scope',
          trailing: PlainTextLink(
            key: const ValueKey('epic_edit_scope_btn'),
            label: _editingScope ? 'Cancel' : 'Edit Scope',
            isDark: isDark,
            fontSize: 11.5,
            color: _editingScope ? muted : focal,
            onTap: () => setState(() => _editingScope = !_editingScope),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editingScope) ...[
                InlineScopeEditorBox(
                  isDark: isDark,
                  initialGoal: epic.goal,
                  initialInScope: epic.inScope,
                  initialDoneWhen: epic.doneWhen,
                  goalInputKey: const ValueKey('epic_scope_goal_input'),
                  inScopeInputKey: const ValueKey('epic_scope_in_scope_input'),
                  doneWhenInputKey: const ValueKey('epic_scope_done_when_input'),
                  saveBtnKey: const ValueKey('epic_scope_save_btn'),
                  onSave: ({
                    required String goal,
                    required List<String> inScope,
                    required List<String> doneWhen,
                    required String delta,
                  }) {
                    wb.updateEpicScope(
                      epic.id,
                      goal: goal,
                      inScope: inScope,
                      doneWhen: doneWhen,
                    );
                    setState(() => _editingScope = false);
                  },
                  onCancel: () => setState(() => _editingScope = false),
                ),
              ] else ...[
                PlainEditableLineField(
                  fieldKey: ValueKey('epic_goal_inline_${epic.id}'),
                  value: epic.goal,
                  isDark: isDark,
                  multiLine: true,
                  minLines: 1,
                  allowEmpty: true,
                  hintText: 'Define one plain-English sentence for this domain...',
                  style: TextStyle(fontSize: 14, color: primary, height: 1.45),
                  onCommit: (val) => wb.updateEpicScope(epic.id, goal: val),
                ),
                if (epic.inScope.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'IN SCOPE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final item in epic.inScope)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '— $item',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: secondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
                if (epic.doneWhen.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'DONE WHEN',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final cond in epic.doneWhen)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '— $cond',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: secondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),

        // §02 @OWNERS
        EpicSectionCard(
          isDark: isDark,
          code: '§02',
          title: '@OWNERS · Blueprint, Level & Class Ownership',
          trailing: PlainTextLink(
            key: const ValueKey('epic_add_owner_btn'),
            label: _showOwnerForm ? 'Cancel' : '+ Add owner',
            isDark: isDark,
            fontSize: 11.5,
            color: _showOwnerForm ? muted : focal,
            onTap: () {
              setState(() {
                _showOwnerForm = !_showOwnerForm;
                _editingOwnerIndex = null;
                _ownerPathController.clear();
                _ownerRoleController.clear();
              });
            },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showOwnerForm)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: focal, width: 2),
                      bottom: BorderSide(color: border, width: 1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('epic_owner_path_input'),
                        controller: _ownerPathController,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12.5,
                          color: primary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText:
                              'Asset or class path (e.g. /Game/Characters/BP_Player.uasset)',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: focal),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('epic_owner_role_input'),
                        controller: _ownerRoleController,
                        style: TextStyle(fontSize: 13, color: primary),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText:
                              'Responsibility (e.g. Owns character locomotion & Enhanced Input)',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: focal),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          PlainTextLink(
                            label: 'Cancel',
                            isDark: isDark,
                            color: muted,
                            onTap: () {
                              setState(() {
                                _showOwnerForm = false;
                                _editingOwnerIndex = null;
                                _ownerPathController.clear();
                                _ownerRoleController.clear();
                              });
                            },
                          ),
                          const SizedBox(width: 12),
                          PlainPrimaryButton(
                            key: const ValueKey('epic_owner_save_btn'),
                            label: _editingOwnerIndex != null
                                ? 'Update Owner'
                                : 'Add Owner',
                            isDark: isDark,
                            onPressed: () {
                              final path = _ownerPathController.text.trim();
                              if (path.isEmpty) return;
                              wb.upsertEpicOwnership(
                                epic.id,
                                index: _editingOwnerIndex,
                                path: path,
                                role: _ownerRoleController.text.trim(),
                              );
                              setState(() {
                                _showOwnerForm = false;
                                _editingOwnerIndex = null;
                                _ownerPathController.clear();
                                _ownerRoleController.clear();
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (ownershipList.isNotEmpty)
                for (int i = 0; i < ownershipList.length; i++)
                  PlainHoverRemoveRow(
                    isDark: isDark,
                    showBottomBorder: i < ownershipList.length - 1,
                    removeKey: ValueKey('epic_owner_delete_$i'),
                    removeTooltip: 'Remove owner',
                    onRemove: () {
                      if (_editingOwnerIndex == i) {
                        setState(() {
                          _showOwnerForm = false;
                          _editingOwnerIndex = null;
                          _ownerPathController.clear();
                          _ownerRoleController.clear();
                        });
                      } else if (_editingOwnerIndex != null &&
                          _editingOwnerIndex! > i) {
                        setState(() {
                          _editingOwnerIndex = _editingOwnerIndex! - 1;
                        });
                      }
                      wb.removeEpicOwnership(epic.id, i);
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
                                Text(
                                  ownershipList[i].path,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: primary,
                                  ),
                                ),
                                if (ownershipList[i].role.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    ownershipList[i].role,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: secondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          PlainTextLink(
                            key: ValueKey('epic_owner_edit_$i'),
                            label: 'Edit',
                            isDark: isDark,
                            fontSize: 11.5,
                            color: muted,
                            onTap: () {
                              setState(() {
                                _editingOwnerIndex = i;
                                _showOwnerForm = true;
                                _ownerPathController.text =
                                    ownershipList[i].path;
                                _ownerRoleController.text =
                                    ownershipList[i].role;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  )
              else if (epic.links.isNotEmpty)
                for (final l in epic.links)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '— $l',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  )
              else
                Text(
                  'No shared UE5 Blueprints, levels, or classes mapped yet.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                ),
            ],
          ),
        ),

        // §03 Shared State & Interrupt Rules
        EpicSectionCard(
          isDark: isDark,
          code: '§03',
          title: 'State & Interrupt Rules',
          trailing: PlainTextLink(
            key: const ValueKey('epic_edit_states_btn'),
            label: _editingStateRules ? 'Cancel' : 'Edit Rules',
            isDark: isDark,
            fontSize: 11.5,
            color: _editingStateRules ? muted : focal,
            onTap: () {
              setState(() {
                _editingStateRules = !_editingStateRules;
                if (_editingStateRules) {
                  _statesController.text = states.join(' -> ');
                  _interruptsController.text = rules.join('\n');
                }
              });
            },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editingStateRules)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: focal, width: 2),
                      bottom: BorderSide(color: border, width: 1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('epic_states_input'),
                        controller: _statesController,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12.5,
                          color: primary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText:
                              'State flow (e.g. Idle -> Moving -> Dashing -> Recovery)',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: focal),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('epic_interrupts_input'),
                        controller: _interruptsController,
                        minLines: 2,
                        maxLines: 5,
                        style: TextStyle(fontSize: 13, color: primary),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Interrupt rules (one rule per line)',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: focal),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          PlainTextLink(
                            label: 'Cancel',
                            isDark: isDark,
                            color: muted,
                            onTap: () =>
                                setState(() => _editingStateRules = false),
                          ),
                          const SizedBox(width: 12),
                          PlainPrimaryButton(
                            key: const ValueKey('epic_states_save_btn'),
                            label: 'Save Rules',
                            isDark: isDark,
                            onPressed: () {
                              final parsedStates = _statesController.text
                                  .split(RegExp(r'->|\n|,'))
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList();
                              final parsedRules = _interruptsController.text
                                  .split('\n')
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList();
                              wb.updateEpicStateRules(
                                epic.id,
                                stateFlow: parsedStates,
                                interruptRules: parsedRules,
                              );
                              setState(() => _editingStateRules = false);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else ...[
                if (states.isNotEmpty) ...[
                  Text(
                    states.join(' -> '),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12.5,
                      color: primary,
                      height: 1.45,
                    ),
                  ),
                  if (rules.isNotEmpty) const SizedBox(height: 8),
                ],
                if (rules.isNotEmpty)
                  for (final r in rules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '— $r',
                        style: TextStyle(fontSize: 13.5, color: secondary),
                      ),
                    )
                else if (states.isEmpty)
                  Text(
                    'No shared state machine or interrupt rules specified yet.',
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
              ],
            ],
          ),
        ),

        // §04 Out of Scope
        EpicSectionCard(
          isDark: isDark,
          code: '§04',
          title: 'Out of Scope',
          trailing: PlainTextLink(
            key: const ValueKey('epic_add_cut_btn'),
            label: _addingCut ? 'Cancel' : '+ Add cut',
            isDark: isDark,
            fontSize: 11.5,
            color: _addingCut ? muted : focal,
            onTap: () => setState(() => _addingCut = !_addingCut),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_addingCut)
                InlineSingleLineAdderBox(
                  isDark: isDark,
                  labelText: 'Domain Out-of-Scope Cut',
                  hintText: 'e.g. No multiplayer lag compensation',
                  submitLabel: 'Add Cut',
                  inputKey: const ValueKey('epic_cut_input'),
                  saveBtnKey: const ValueKey('epic_cut_save_btn'),
                  onSubmit: (text) {
                    wb.addEpicOutOfScopeCut(epic.id, text);
                    setState(() => _addingCut = false);
                  },
                  onCancel: () => setState(() => _addingCut = false),
                ),
              if (epic.outOfScope.isEmpty)
                Text(
                  'No domain out-of-scope cuts specified.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              else
                for (int i = 0; i < epic.outOfScope.length; i++)
                  PlainHoverRemoveRow(
                    isDark: isDark,
                    showBottomBorder: i < epic.outOfScope.length - 1,
                    removeKey: ValueKey('epic_cut_delete_$i'),
                    removeTooltip: 'Remove cut',
                    onRemove: () => wb.removeEpicOutOfScopeCut(epic.id, i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        epic.outOfScope[i],
                        style: TextStyle(fontSize: 13.5, color: secondary),
                      ),
                    ),
                  ),
            ],
          ),
        ),

        // §05 Child Slices
        EpicSectionCard(
          isDark: isDark,
          code: '§05',
          title: 'Child Slices (${visibleFeatures.length})',
          trailing: PlainTextLink(
            key: const ValueKey('show_add_feature_btn'),
            label: _showAddFeature ? 'Cancel' : '+ Add slice',
            isDark: isDark,
            fontSize: 11.5,
            color: _showAddFeature ? muted : focal,
            onTap: () => setState(() => _showAddFeature = !_showAddFeature),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showAddFeature)
                Container(
                  key: const ValueKey('add_feature_form'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: focal, width: 2),
                      bottom: BorderSide(color: border, width: 1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('new_feature_title_input'),
                        controller: _newFeatureTitleController,
                        autofocus: true,
                        style: TextStyle(fontSize: 13.5, color: primary),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Slice title (e.g. Shield Bash Knockback)',
                          hintStyle: TextStyle(fontSize: 12.5, color: muted),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: focal),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('new_feature_goal_input'),
                        controller: _newFeatureGoalController,
                        style: TextStyle(fontSize: 13, color: secondary),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Playable outcome in 1 plain sentence',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: focal),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          PlainTextLink(
                            label: 'Cancel',
                            isDark: isDark,
                            color: muted,
                            onTap: () =>
                                setState(() => _showAddFeature = false),
                          ),
                          const SizedBox(width: 12),
                          PlainPrimaryButton(
                            key: const ValueKey('submit_add_feature_btn'),
                            label: 'Create Feature Slice',
                            isDark: isDark,
                            onPressed: () {
                              final title =
                                  _newFeatureTitleController.text.trim();
                              if (title.isEmpty) return;
                              wb.addFeatureSlice(
                                epic.id,
                                title: title,
                                goal: _newFeatureGoalController.text.trim(),
                              );
                              _newFeatureTitleController.clear();
                              _newFeatureGoalController.clear();
                              setState(() => _showAddFeature = false);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              for (final feat in visibleFeatures)
                EpicChildFeatureCard(
                  feat: feat,
                  relVer: relVer,
                  isDark: isDark,
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    wb.selectFeature(epic.id, feat.id);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
