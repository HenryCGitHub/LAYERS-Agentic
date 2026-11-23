import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'workbench_shared_widgets.dart';

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
  final TextEditingController _newFeatureTitleController =
      TextEditingController();
  final TextEditingController _newFeatureGoalController =
      TextEditingController();
  final TextEditingController _ownerPathController = TextEditingController();
  final TextEditingController _ownerRoleController = TextEditingController();
  final TextEditingController _statesController = TextEditingController();
  final TextEditingController _interruptsController = TextEditingController();

  bool _showAddFeatureForm = false;
  bool _showOwnerForm = false;
  int? _editingOwnerIndex;
  bool _editingStateRules = false;

  @override
  void didUpdateWidget(covariant EpicDomainSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionKey != widget.selectionKey) {
      _showAddFeatureForm = false;
      _showOwnerForm = false;
      _editingOwnerIndex = null;
      _editingStateRules = false;
      _newFeatureTitleController.clear();
      _newFeatureGoalController.clear();
      _ownerPathController.clear();
      _ownerRoleController.clear();
      _statesController.clear();
      _interruptsController.clear();
    }
  }

  @override
  void dispose() {
    _newFeatureTitleController.dispose();
    _newFeatureGoalController.dispose();
    _ownerPathController.dispose();
    _ownerRoleController.dispose();
    _statesController.dispose();
    _interruptsController.dispose();
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
    return _buildSheetContent(
      context,
      widget.workbench,
      widget.epic,
      widget.isDark,
      primary,
      secondary,
      muted,
      border,
      cyan,
      green,
      red,
    );
  }

  Widget _buildSheetContent(
    BuildContext context,
    WorkbenchProvider wb,
    EpicSpec epic,
    bool isDark,
    Color primary,
    Color secondary,
    Color muted,
    Color border,
    Color cyan,
    Color green,
    Color red,
  ) {
    final relVer = wb.activeReleaseVersionTag;
    final visibleFeatures = wb.visibleFeaturesForEpic(epic);
    final ownershipList = epic.sceneOwnership;
    final states = epic.stateFlow;
    final rules = epic.interruptRules;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // §01 Domain Scope (Zero Feature Duplication)
        EpicSectionCard(
          isDark: isDark,
          code: '§01',
          title: 'Domain Scope (Zero Feature Duplication)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Goal: ${epic.goal}',
                style: TextStyle(fontSize: 14, color: primary, height: 1.45),
              ),
              if (epic.inScope.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'In Scope',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 4),
                for (final item in epic.inScope)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• $item',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ),
              ],
              if (epic.doneWhen.isNotEmpty) ...[
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
                for (final item in epic.doneWhen)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• $item',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ),
              ],
              if (epic.upgradeDeltas.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: cyan.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${epic.releaseVersion} UPGRADE DELTAS',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cyan,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final d in epic.upgradeDeltas)
                        Text(
                          '• $d',
                          style: TextStyle(fontSize: 12.5, color: primary),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §02 Shared Blueprint, Level & Class Ownership
        EpicSectionCard(
          isDark: isDark,
          code: '§02',
          title: 'Shared Blueprint, Level & Class Ownership',
          trailing: OutlinedButton.icon(
            key: const ValueKey('epic_add_owner_btn'),
            onPressed: () {
              setState(() {
                _showOwnerForm = !_showOwnerForm;
                _editingOwnerIndex = null;
                _ownerPathController.clear();
                _ownerRoleController.clear();
              });
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: Icon(_showOwnerForm ? Icons.close : Icons.add, size: 14),
            label: Text(
              _showOwnerForm ? 'Close' : '+ Add Owner',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showOwnerForm)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: cyan.withValues(alpha: 0.5)),
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
                          labelText: 'UE5 Asset / Class Path',
                          hintText:
                              'e.g. /Game/Player/BP_PlayerCharacter.uasset or Source/.../Player.cpp',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('epic_owner_role_input'),
                        controller: _ownerRoleController,
                        style: TextStyle(fontSize: 13, color: primary),
                        decoration: InputDecoration(
                          labelText: 'Domain Role (optional)',
                          hintText: 'e.g. Shared locomotion & dash owner',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _showOwnerForm = false;
                                _editingOwnerIndex = null;
                                _ownerPathController.clear();
                                _ownerRoleController.clear();
                              });
                            },
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            key: const ValueKey('epic_owner_save_btn'),
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
                            child: Text(
                              _editingOwnerIndex != null
                                  ? 'Update Owner'
                                  : 'Add Owner',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (ownershipList.isNotEmpty)
                for (int i = 0; i < ownershipList.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurfaceFor(isDark),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(color: border),
                    ),
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
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: cyan,
                                ),
                              ),
                              if (ownershipList[i].role.isNotEmpty) ...[
                                const SizedBox(height: 3),
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
                        IconButton(
                          key: ValueKey('epic_owner_edit_$i'),
                          tooltip: 'Edit owner',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 15,
                            color: muted,
                          ),
                          onPressed: () {
                            setState(() {
                              _editingOwnerIndex = i;
                              _showOwnerForm = true;
                              _ownerPathController.text = ownershipList[i].path;
                              _ownerRoleController.text = ownershipList[i].role;
                            });
                          },
                        ),
                        IconButton(
                          key: ValueKey('epic_owner_delete_$i'),
                          tooltip: 'Remove owner',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          icon: Icon(Icons.close, size: 15, color: muted),
                          onPressed: () {
                            if (_editingOwnerIndex == i) {
                              setState(() {
                                _showOwnerForm = false;
                                _editingOwnerIndex = null;
                                _ownerPathController.clear();
                                _ownerRoleController.clear();
                              });
                            }
                            wb.removeEpicOwnership(epic.id, i);
                          },
                        ),
                      ],
                    ),
                  )
              else if (epic.links.isNotEmpty)
                for (final l in epic.links)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $l',
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
        const SizedBox(height: 14),

        // §03 Shared State & Interrupt Rules
        EpicSectionCard(
          isDark: isDark,
          code: '§03',
          title: 'Shared State & Interrupt Rules',
          trailing: OutlinedButton.icon(
            key: const ValueKey('epic_edit_states_btn'),
            onPressed: () {
              setState(() {
                _editingStateRules = !_editingStateRules;
                if (_editingStateRules) {
                  _statesController.text = states.join(' -> ');
                  _interruptsController.text = rules.join('\n');
                }
              });
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: Icon(
              _editingStateRules ? Icons.close : Icons.edit_outlined,
              size: 14,
            ),
            label: Text(
              _editingStateRules ? 'Close' : 'Edit Rules',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editingStateRules)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: cyan.withValues(alpha: 0.5)),
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
                          labelText: 'State Flow (separate with -> or →)',
                          hintText: 'e.g. Idle -> Move -> Dash -> Recovery',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('epic_interrupts_input'),
                        controller: _interruptsController,
                        maxLines: 3,
                        style: TextStyle(fontSize: 12.5, color: primary),
                        decoration: InputDecoration(
                          labelText: 'Interrupt Rules (1 per line)',
                          hintText:
                              'e.g. Dash cancels Move\nHitstun cancels Dash',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () =>
                                setState(() => _editingStateRules = false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            key: const ValueKey('epic_states_save_btn'),
                            onPressed: () {
                              wb.updateEpicStateRules(
                                epic.id,
                                stateFlow: _statesController.text.split(
                                  RegExp(r'\s*(?:->|→)\s*'),
                                ),
                                interruptRules: _interruptsController.text
                                    .split('\n'),
                              );
                              setState(() => _editingStateRules = false);
                            },
                            child: const Text(
                              'Save State Rules',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (states.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (int i = 0; i < states.length; i++) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurfaceFor(isDark),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(color: border),
                        ),
                        child: Text(
                          states[i],
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: primary,
                          ),
                        ),
                      ),
                      if (i < states.length - 1)
                        Text('→', style: TextStyle(color: muted, fontSize: 12)),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
              ],
              for (final rule in rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $rule',
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                ),
              if (states.isEmpty && rules.isEmpty)
                Text(
                  'Linear slice execution; no cross-slice interrupt locks.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §04 Domain Out-of-Scope Cuts
        EpicSectionCard(
          isDark: isDark,
          code: '§04',
          title: 'Domain Out-of-Scope Cuts',
          child: epic.outOfScope.isEmpty
              ? Text(
                  'Scoped cleanly to child Features below.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final cut in epic.outOfScope)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                          border: Border.all(color: red.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          cut,
                          style: TextStyle(fontSize: 12, color: primary),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // §05 Child Features + Add Feature Slice
        EpicSectionCard(
          isDark: isDark,
          code: '§05',
          title: 'Child Features in ${epic.code} ($relVer)',
          trailing: OutlinedButton.icon(
            key: const ValueKey('show_add_feature_btn'),
            onPressed: () =>
                setState(() => _showAddFeatureForm = !_showAddFeatureForm),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: Icon(_showAddFeatureForm ? Icons.close : Icons.add, size: 14),
            label: Text(
              _showAddFeatureForm ? 'Close' : '+ Add Feature Slice',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showAddFeatureForm) ...[
                Container(
                  key: const ValueKey('add_feature_form'),
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: cyan.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('new_feature_title_input'),
                        controller: _newFeatureTitleController,
                        style: TextStyle(fontSize: 13, color: primary),
                        decoration: InputDecoration(
                          labelText: 'Feature Title (2–5 plain words)',
                          hintText: 'e.g. Wall Bounce Dash',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('new_feature_goal_input'),
                        controller: _newFeatureGoalController,
                        style: TextStyle(fontSize: 13, color: primary),
                        decoration: InputDecoration(
                          labelText: 'Slice Goal (1 plain-English sentence)',
                          hintText:
                              'e.g. Ricochet cleanly off angled stone arena walls.',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          TextButton(
                            onPressed: () {
                              _newFeatureTitleController.clear();
                              _newFeatureGoalController.clear();
                              setState(() => _showAddFeatureForm = false);
                            },
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            key: const ValueKey('submit_add_feature_btn'),
                            onPressed: () {
                              final title =
                                  _newFeatureTitleController.text.trim();
                              final goal =
                                  _newFeatureGoalController.text.trim();
                              if (title.isEmpty || goal.isEmpty) return;
                              wb.addFeatureSlice(
                                epic.id,
                                title: title,
                                goal: goal,
                              );
                              _newFeatureTitleController.clear();
                              _newFeatureGoalController.clear();
                              setState(() => _showAddFeatureForm = false);
                            },
                            child: const Text(
                              'Create Feature Slice →',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (visibleFeatures.isEmpty)
                Text(
                  'No child Features queued in $relVer. Use + Add Feature Slice above.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              else
                for (final feat in visibleFeatures)
                  _buildEpicChildFeatureCard(
                    wb: wb,
                    epic: epic,
                    feat: feat,
                    relVer: relVer,
                    isDark: isDark,
                    primary: primary,
                    secondary: secondary,
                    muted: muted,
                    border: border,
                    cyan: cyan,
                    green: green,
                    red: red,
                  ),
            ],
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }

  Widget _buildEpicChildFeatureCard({
    required WorkbenchProvider wb,
    required EpicSpec epic,
    required FeatureSpec feat,
    required String relVer,
    required bool isDark,
    required Color primary,
    required Color secondary,
    required Color muted,
    required Color border,
    required Color cyan,
    required Color green,
    required Color red,
  }) {
    final effChecks = feat.effectiveChecksForRelease(relVer);
    final passedCount = effChecks.where((c) => c.passed).length;
    final passedFeature = feat.isPassedForRelease(relVer);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: ValueKey('epic_feature_card_${feat.id}'),
        onTap: () => wb.selectFeature(epic.id, feat.id),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgSurfaceFor(isDark),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: passedFeature ? green.withValues(alpha: 0.4) : border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    '${feat.code} · ${feat.sliceTime}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: cyan,
                    ),
                  ),
                  Text(
                    '$passedCount/${effChecks.length} checks${feat.openFixesCount > 0 ? ' · ${feat.openFixesCount} [FIX]' : ''}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: feat.openFixesCount > 0
                          ? red
                          : (passedFeature ? green : muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                feat.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                feat.goal,
                style: TextStyle(fontSize: 12.5, color: secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
