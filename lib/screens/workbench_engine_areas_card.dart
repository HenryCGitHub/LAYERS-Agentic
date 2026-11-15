part of 'release_workbench_screen.dart';

extension _WorkbenchEngineAreasExt on _ReleaseWorkbenchScreenState {
  static final RegExp _scopeVarAnnotRegex = RegExp(
    r'\s*\((?:@export|export\s+var|float|int|bool|String|Vector[23]|NodePath|PackedScene)[^)]*\)',
    caseSensitive: false,
  );
  static final RegExp _scopeInlineAssignRegex = RegExp(
    r'\s*[@`]?[a-z_][a-z0-9_]*\s*[:=]\s*[-+]?\d+(?:\.\d+)?[a-zA-Z%/]*',
  );
  static final RegExp _tuningBulletStripRegex = RegExp(r'^[•\*\-\s]+');
  static final RegExp _tuningIdPrefixRegex = RegExp(
    r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*:',
  );

  String _formatPlainEnglishScopeBullet(String raw) {
    var cleaned = raw.trim().replaceFirst(RegExp(r'^[•\*\-\s]+'), '').trim();
    cleaned = cleaned.replaceAll(_scopeVarAnnotRegex, '').trim();
    cleaned = cleaned.replaceAll(_scopeInlineAssignRegex, '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'[,;:\s]+$'), '').trim();
    return cleaned.isEmpty ? raw.trim() : cleaned;
  }

  /// Resolves the 3-Part Plain-English Feature Brief & Playtest Card
  /// (`Goal` + `In Scope` + `Done When` + optional Guards/Open Issues + 1-click Pass).
  Widget _buildPlaytestGateWorkspacePane({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required FeatureStateNode node,
    required String epicShortCode,
    required String epicTitle,
  }) {
    final edgeItems = node.edgeCases;
    final signedOffGuards = node.signedOffGuardsCount;

    final rawGoal = SectionTextUtils.resolveGoal(feat.sections).trim();
    final conciseGoal = rawGoal.isNotEmpty
        ? SectionTextUtils.formatConciseFeatureGoal(rawGoal)
        : node.cleanStageTitle;

    final activeVer = widget.workbench.activeReleaseVersionTag;
    final rawCpVer = (node.parameters['releaseVersion'] ?? '').trim();
    final featPhase = (feat.phase ?? '').trim();
    final cpVer = rawCpVer.isNotEmpty
        ? rawCpVer
        : (featPhase.isNotEmpty ? featPhase : activeVer);
    final rawScopeItems = SectionTextUtils.resolveCheckpointInScope(
      checkpointScope: node.coveredScope,
      sections: feat.sections,
      releaseVersion: cpVer,
    );
    final inScopeBullets = SectionTextUtils.dedupeScopeBullets(
      [
        for (final item in rawScopeItems)
          if (_formatPlainEnglishScopeBullet(item).isNotEmpty)
            _formatPlainEnglishScopeBullet(item),
      ],
      releaseVersion: cpVer,
    );
    final inScopeHeaderLabel = SectionTextUtils.resolveInScopeHeaderLabel(
      inScopeBullets,
      releaseVersion: cpVer,
    );

    final endGoal = SectionTextUtils.resolveCheckpointDoneWhen(
      playtestGoalParam: node.parameters['playtestGoal'],
      checkpointTrigger: node.trigger,
      checkpointFeedback: node.feedback,
      sections: feat.sections,
      fallback: node.playtestCondition,
    );
    final tuningItems = node.tuningParams.isNotEmpty
        ? List<String>.from(node.tuningParams)
        : SectionTextUtils.resolveTuningParams(feat.sections);

    node.flattenLegacyNestedChecklistIfNeeded();
    final openFixEntries = node.openFixItems;

    final hasNextCp = states.any(
      (s) => s.id != node.id && s.releaseVersion == activeVer && !s.isCompleted,
    );
    final bool isPassed = node.isPlaytestPassed || node.isCompleted;

    return Container(
      key: ValueKey('playtest_gate_card_${node.id}'),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D131F) : bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPassed
              ? accentEmerald.withValues(alpha: 0.5)
              : borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. GOAL
          Row(
            children: [
              Text(
                'GOAL',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: fontMicro,
                  fontWeight: weightBold,
                  letterSpacing: 0.7,
                  color: const Color(0xFF7DD3FC),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: bgRecessed,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: borderSubtle),
                  ),
                  child: Text(
                    '$epicShortCode · $epicTitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: weightSemi,
                      color: textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_activeStage2InlineEditKey == 'edit_goal_${node.id}')
            _buildStage2InlineEditor(
              editKey: 'edit_goal_${node.id}',
              inputKey: ValueKey('edit_feature_goal_input_${node.id}'),
              saveBtnKey: ValueKey('save_feature_goal_btn_${node.id}'),
              cancelBtnKey: ValueKey('cancel_feature_goal_btn_${node.id}'),
              hintText: 'One-sentence feature goal or +delta...',
              onSave: (val) {
                widget.workbench.updateActiveFeatureSpec(
                  featureId: feat.id,
                  states: states,
                  activeNode: node,
                  goal: val,
                );
                _rebuild();
              },
            )
          else
            InkWell(
              key: ValueKey('edit_feature_goal_btn_${node.id}'),
              borderRadius: BorderRadius.circular(5),
              onTap: () =>
                  _startStage2InlineEdit('edit_goal_${node.id}', conciseGoal),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        conciseGoal,
                        key: ValueKey('task_sheet_feature_goal_${node.id}'),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: weightSemi,
                          height: 1.45,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '✎',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 2. IN SCOPE (Scannable + 1-Click Inline Editable)
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                inScopeHeaderLabel,
                key: ValueKey('in_scope_header_${node.id}'),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: fontMicro,
                  fontWeight: weightBold,
                  letterSpacing: 0.7,
                  color: textMuted,
                ),
              ),
              InkWell(
                key: ValueKey('add_in_scope_btn_${node.id}'),
                borderRadius: BorderRadius.circular(5),
                onTap: () => _startStage2InlineEdit('add_scope_${node.id}', ''),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    '+ Add Scope',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: weightSemi,
                      color: const Color(0xFF7DD3FC),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (inScopeBullets.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (int i = 0; i < inScopeBullets.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == inScopeBullets.length - 1 ? 0 : 4,
                ),
                child: _activeStage2InlineEditKey ==
                        'edit_scope_${node.id}_$i'
                    ? _buildStage2InlineEditor(
                        editKey: 'edit_scope_${node.id}_$i',
                        inputKey: ValueKey('edit_in_scope_input_${node.id}_$i'),
                        saveBtnKey: ValueKey('save_in_scope_btn_${node.id}_$i'),
                        deleteBtnKey:
                            ValueKey('delete_in_scope_btn_${node.id}_$i'),
                        cancelBtnKey:
                            ValueKey('cancel_in_scope_btn_${node.id}_$i'),
                        hintText: 'Scope deliverable or +delta...',
                        onSave: (val) {
                          final cleaned = val
                              .replaceFirst(_tuningBulletStripRegex, '')
                              .trim();
                          if (cleaned.isEmpty) return;
                          final nextList = List<String>.from(inScopeBullets)
                            ..[i] = cleaned;
                          widget.workbench.updateActiveFeatureSpec(
                            featureId: feat.id,
                            states: states,
                            activeNode: node,
                            inScope: nextList,
                          );
                          _rebuild();
                        },
                        onDelete: () {
                          final nextList = List<String>.from(inScopeBullets)
                            ..removeAt(i);
                          widget.workbench.updateActiveFeatureSpec(
                            featureId: feat.id,
                            states: states,
                            activeNode: node,
                            inScope: nextList,
                          );
                          _rebuild();
                        },
                      )
                    : InkWell(
                        key: ValueKey('in_scope_item_${node.id}_$i'),
                        borderRadius: BorderRadius.circular(5),
                        onTap: () => _startStage2InlineEdit(
                          'edit_scope_${node.id}_$i',
                          inScopeBullets[i],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6, right: 9),
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF38BDF8)
                                        .withValues(alpha: 0.8),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  inScopeBullets[i],
                                  style: GoogleFonts.inter(
                                    fontSize: fontItem,
                                    height: 1.42,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '✎',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
          ] else if (_activeStage2InlineEditKey != 'add_scope_${node.id}') ...[
            const SizedBox(height: 4),
            Text(
              'No scope items listed — click + Add Scope to add one.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: textMuted,
              ),
            ),
          ],
          if (_activeStage2InlineEditKey == 'add_scope_${node.id}') ...[
            const SizedBox(height: 8),
            _buildStage2InlineEditor(
              editKey: 'add_scope_${node.id}',
              inputKey: ValueKey('add_in_scope_input_${node.id}'),
              saveBtnKey: ValueKey('confirm_add_in_scope_btn_${node.id}'),
              cancelBtnKey: ValueKey('cancel_add_in_scope_btn_${node.id}'),
              hintText: 'Scope deliverable or +delta...',
              onSave: (val) {
                final cleaned =
                    val.replaceFirst(_tuningBulletStripRegex, '').trim();
                if (cleaned.isEmpty) return;
                final nextList = List<String>.from(inScopeBullets)..add(cleaned);
                widget.workbench.updateActiveFeatureSpec(
                  featureId: feat.id,
                  states: states,
                  activeNode: node,
                  inScope: nextList,
                );
                _rebuild();
              },
            ),
          ],

          // 2B. TUNING VARIABLES (Scannable + 1-Click Inline Editable)
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TUNING VARIABLES',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: fontMicro,
                  fontWeight: weightBold,
                  letterSpacing: 0.7,
                  color: const Color(0xFF7DD3FC),
                ),
              ),
              InkWell(
                key: ValueKey('add_tuning_var_btn_${node.id}'),
                borderRadius: BorderRadius.circular(5),
                onTap: () => _startStage2InlineEdit('add_tuning_${node.id}', ''),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    '+ Add Variable',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: weightSemi,
                      color: const Color(0xFF7DD3FC),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (tuningItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (int tIdx = 0; tIdx < tuningItems.length; tIdx++)
                  if (_activeStage2InlineEditKey ==
                      'edit_tuning_${node.id}_$tIdx')
                    SizedBox(
                      width: 280,
                      child: _buildStage2InlineEditor(
                        editKey: 'edit_tuning_${node.id}_$tIdx',
                        inputKey: ValueKey(
                          'edit_tuning_var_input_${node.id}_$tIdx',
                        ),
                        saveBtnKey: ValueKey(
                          'save_tuning_var_btn_${node.id}_$tIdx',
                        ),
                        deleteBtnKey: ValueKey(
                          'delete_tuning_var_btn_${node.id}_$tIdx',
                        ),
                        cancelBtnKey: ValueKey(
                          'cancel_tuning_var_btn_${node.id}_$tIdx',
                        ),
                        hintText: 'paramName: 1.0 unit',
                        onSave: (val) {
                          final oldRaw = tuningItems[tIdx];
                          final cleaned = val
                              .replaceFirst(_tuningBulletStripRegex, '')
                              .trim();
                          if (cleaned.isEmpty) return;
                          final nextList = List<String>.from(tuningItems)
                            ..[tIdx] = cleaned;
                          node.tuningParams = nextList;
                          widget.workbench.updateFeatureStates(feat.id, states);
                          final oldIdMatch =
                              _tuningIdPrefixRegex.firstMatch(oldRaw);
                          final newIdMatch =
                              _tuningIdPrefixRegex.firstMatch(cleaned);
                          if (oldIdMatch != null && newIdMatch != null) {
                            final oldId = oldIdMatch.group(1)!;
                            final newId = newIdMatch.group(1)!;
                            if (oldId != newId) {
                              widget.workbench
                                  .propagateVariableRenameAcrossProject(
                                oldId,
                                newId,
                              );
                            }
                          }
                          _rebuild();
                        },
                        onDelete: () {
                          final nextList = List<String>.from(tuningItems)
                            ..removeAt(tIdx);
                          node.tuningParams = nextList;
                          widget.workbench.updateFeatureStates(feat.id, states);
                          _rebuild();
                        },
                      ),
                    )
                  else
                    InkWell(
                      key: ValueKey('tuning_var_item_${node.id}_$tIdx'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _startStage2InlineEdit(
                        'edit_tuning_${node.id}_$tIdx',
                        tuningItems[tIdx],
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0B1320) : bgRecessed,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF38BDF8)
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              tuningItems[tIdx],
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                color: const Color(0xFFBAE6FD),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '✎',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ] else if (_activeStage2InlineEditKey != 'add_tuning_${node.id}') ...[
            const SizedBox(height: 4),
            Text(
              'No tuning variables registered — click + Add Variable to add one.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: textMuted,
              ),
            ),
          ],
          if (_activeStage2InlineEditKey == 'add_tuning_${node.id}') ...[
            const SizedBox(height: 8),
            _buildStage2InlineEditor(
              editKey: 'add_tuning_${node.id}',
              inputKey: ValueKey('add_tuning_var_input_${node.id}'),
              saveBtnKey: ValueKey('confirm_add_tuning_var_btn_${node.id}'),
              cancelBtnKey: ValueKey('cancel_add_tuning_var_btn_${node.id}'),
              hintText: 'paramName: 1.0 unit (e.g. dashSpeed: 12.0 m/s)',
              onSave: (val) {
                final cleaned =
                    val.replaceFirst(_tuningBulletStripRegex, '').trim();
                if (cleaned.isEmpty) return;
                final nextList = List<String>.from(tuningItems)..add(cleaned);
                node.tuningParams = nextList;
                widget.workbench.updateFeatureStates(feat.id, states);
                _rebuild();
              },
            ),
          ],

          // Optional: Plain-English State & Boundary Guards (Checkable + 1-Click Inline Editable)
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PLAYTEST GUARDS',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: fontMicro,
                      fontWeight: weightBold,
                      letterSpacing: 0.6,
                      color: const Color(0xFFFBBF24),
                    ),
                  ),
                  if (edgeItems.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$signedOffGuards/${edgeItems.length} Checked',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: fontMicro,
                        fontWeight: weightBold,
                        color: const Color(0xFFFCD34D),
                      ),
                    ),
                  ],
                ],
              ),
              InkWell(
                key: ValueKey('add_playtest_guard_btn_${node.id}'),
                borderRadius: BorderRadius.circular(5),
                onTap: () => _startStage2InlineEdit('add_guard_${node.id}', ''),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    '+ Add Guard',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: weightSemi,
                      color: const Color(0xFFFBBF24),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (edgeItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (int gIdx = 0; gIdx < edgeItems.length; gIdx++)
              Builder(
                builder: (context) {
                  final rawGuard = edgeItems[gIdx];
                  final isChecked = node.isGuardSignedOff(gIdx, rawGuard);
                  final cleanGuard = rawGuard
                      .replaceFirst(
                        RegExp(
                          r'^\[(?:STATE|PLAYTEST)?\s*GUARD\]\s*',
                          caseSensitive: false,
                        ),
                        '',
                      )
                      .trim();
                  if (_activeStage2InlineEditKey ==
                      'edit_guard_${node.id}_$gIdx') {
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: gIdx == edgeItems.length - 1 ? 0 : 6,
                      ),
                      child: _buildStage2InlineEditor(
                        editKey: 'edit_guard_${node.id}_$gIdx',
                        inputKey:
                            ValueKey('edit_playtest_guard_input_${node.id}_$gIdx'),
                        saveBtnKey:
                            ValueKey('save_playtest_guard_btn_${node.id}_$gIdx'),
                        deleteBtnKey:
                            ValueKey('delete_playtest_guard_btn_${node.id}_$gIdx'),
                        cancelBtnKey:
                            ValueKey('cancel_playtest_guard_btn_${node.id}_$gIdx'),
                        hintText: 'State or boundary guard condition...',
                        onSave: (val) {
                          widget.workbench.editPlaytestGuard(
                            featureId: feat.id,
                            states: states,
                            activeNode: node,
                            guardIndex: gIdx,
                            rawText: val,
                          );
                          _rebuild();
                        },
                        onDelete: () {
                          widget.workbench.deletePlaytestGuard(
                            featureId: feat.id,
                            states: states,
                            activeNode: node,
                            guardIndex: gIdx,
                          );
                          _rebuild();
                        },
                      ),
                    );
                  }
                  return Container(
                    margin: EdgeInsets.only(
                      bottom: gIdx == edgeItems.length - 1 ? 0 : 6,
                    ),
                    padding: const EdgeInsets.only(
                      left: 10,
                      right: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isChecked
                          ? const Color(0xFF0A1F18)
                          : const Color(0xFF0B0E17),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isChecked
                            ? const Color(0xFF34D399).withValues(alpha: 0.4)
                            : const Color(0xFF1F2A3F),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            key: ValueKey('playtest_guard_check_${node.id}_$gIdx'),
                            borderRadius: BorderRadius.circular(6),
                            onTap: () {
                              node.setGuardSignedOff(gIdx, rawGuard, !isChecked);
                              widget.workbench.updateFeatureStates(feat.id, states);
                              _rebuild();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 17,
                                    height: 17,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isChecked
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF07090E),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isChecked
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFFF59E0B)
                                                .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Text(
                                      isChecked ? '✓' : '',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10,
                                        fontWeight: weightBold,
                                        color: const Color(0xFF05101A),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      cleanGuard,
                                      style: GoogleFonts.inter(
                                        fontSize: fontBody,
                                        fontWeight: weightRegular,
                                        color: isChecked
                                            ? textSecondary
                                            : const Color(0xFFFDE68A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          key: ValueKey(
                            'edit_playtest_guard_btn_${node.id}_$gIdx',
                          ),
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => _startStage2InlineEdit(
                            'edit_guard_${node.id}_$gIdx',
                            cleanGuard,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                            child: Text(
                              '✎',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ] else if (_activeStage2InlineEditKey != 'add_guard_${node.id}') ...[
            const SizedBox(height: 4),
            Text(
              'No playtest guards registered — click + Add Guard to add one.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: textMuted,
              ),
            ),
          ],
          if (_activeStage2InlineEditKey == 'add_guard_${node.id}') ...[
            const SizedBox(height: 8),
            _buildStage2InlineEditor(
              editKey: 'add_guard_${node.id}',
              inputKey: ValueKey('add_playtest_guard_input_${node.id}'),
              saveBtnKey: ValueKey('confirm_add_playtest_guard_btn_${node.id}'),
              cancelBtnKey:
                  ValueKey('cancel_add_playtest_guard_btn_${node.id}'),
              hintText: 'State or boundary guard condition...',
              onSave: (val) {
                widget.workbench.addPlaytestGuard(
                  featureId: feat.id,
                  states: states,
                  activeNode: node,
                  rawText: val,
                );
                _rebuild();
              },
            ),
          ],

          // Open [FIX] Issues logged from Web Studio or Godot
          if (openFixEntries.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'OPEN PLAYTEST ISSUES (${openFixEntries.length})',
              style: GoogleFonts.jetBrainsMono(
                fontSize: fontMicro,
                fontWeight: weightBold,
                letterSpacing: 0.6,
                color: const Color(0xFFFBBF24),
              ),
            ),
            const SizedBox(height: 8),
            for (int fIdx = 0; fIdx < openFixEntries.length; fIdx++)
              Builder(
                builder: (context) {
                  final fixTask = openFixEntries[fIdx];
                  final label = fixTask.text
                      .replaceFirst(
                        RegExp(r'^\[FIX\]\s*', caseSensitive: false),
                        '',
                      )
                      .trim();
                  return InkWell(
                    key: ValueKey('open_fix_item_${node.id}_$fIdx'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      fixTask.completed = true;
                      widget.workbench.updateFeatureStates(feat.id, states);
                      _rebuild();
                    },
                    child: Container(
                      margin: EdgeInsets.only(
                        bottom: fIdx == openFixEntries.length - 1 ? 0 : 6,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D160B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bug_report_outlined,
                            size: 14,
                            color: Color(0xFFFBBF24),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              style: GoogleFonts.inter(
                                fontSize: fontBody,
                                color: const Color(0xFFFDE68A),
                              ),
                            ),
                          ),
                          Text(
                            'Resolve ✓',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: weightBold,
                              color: const Color(0xFFFBBF24),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],

          // DONE WHEN (Playtest Check — 1-Click Inline Editable, anchored right above Pass CTA)
          if (endGoal.isNotEmpty ||
              _activeStage2InlineEditKey == 'edit_done_when_${node.id}') ...[
            const SizedBox(height: 16),
            Container(
              key: ValueKey('done_when_section_${node.id}'),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF080E17) : bgRecessed,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isPassed
                      ? accentEmerald.withValues(alpha: 0.45)
                      : const Color(0xFF1E3A34),
                ),
              ),
              child: _activeStage2InlineEditKey == 'edit_done_when_${node.id}'
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '✓ DONE WHEN (PLAYTEST IN GODOT)',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: fontMicro,
                            fontWeight: weightBold,
                            letterSpacing: 0.6,
                            color: const Color(0xFF34D399),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildStage2InlineEditor(
                          editKey: 'edit_done_when_${node.id}',
                          inputKey: ValueKey('edit_done_when_input_${node.id}'),
                          saveBtnKey: ValueKey('save_done_when_btn_${node.id}'),
                          cancelBtnKey:
                              ValueKey('cancel_done_when_btn_${node.id}'),
                          hintText:
                              'Player action -> observable screen result...',
                          onSave: (val) {
                            widget.workbench.updateActiveFeatureSpec(
                              featureId: feat.id,
                              states: states,
                              activeNode: node,
                              doneWhen: val,
                            );
                            _rebuild();
                          },
                        ),
                      ],
                    )
                  : InkWell(
                      key: ValueKey('edit_done_when_btn_${node.id}'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _startStage2InlineEdit(
                        'edit_done_when_${node.id}',
                        endGoal,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '✓ DONE WHEN (PLAYTEST IN GODOT)',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: fontMicro,
                                  fontWeight: weightBold,
                                  letterSpacing: 0.6,
                                  color: const Color(0xFF34D399),
                                ),
                              ),
                              Text(
                                '✎',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            endGoal,
                            style: GoogleFonts.inter(
                              fontSize: fontItem,
                              fontWeight: weightSemi,
                              height: 1.45,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],

          // 1-Click Footer Actions
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: ValueKey('playtest_gate_add_fix_btn_${node.id}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFBBF24),
                  side: BorderSide(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onPressed: () {
                  _rebuild(() {
                    _inlineBugDrawerNodeId = _inlineBugDrawerNodeId == node.id
                        ? null
                        : node.id;
                    _inlineBugInputCtrl.clear();
                  });
                },
                icon: const Icon(Icons.bug_report_outlined, size: 15),
                label: Text(
                  '⚑ Log Issue / Request Tweak',
                  style: GoogleFonts.inter(
                    fontSize: fontBody,
                    fontWeight: weightSemi,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isPassed)
                    OutlinedButton.icon(
                      key: ValueKey('playtest_gate_reopen_btn_${node.id}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textSecondary,
                        side: BorderSide(color: borderSubtle),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onPressed: () =>
                          _reopenCheckpointPlaytestGate(feat, states, node),
                      icon: const Icon(Icons.replay_rounded, size: 15),
                      label: Text(
                        '↺ Reopen Gate',
                        style: GoogleFonts.inter(
                          fontSize: fontBody,
                          fontWeight: weightSemi,
                        ),
                      ),
                    ),
                  ElevatedButton.icon(
                    key: ValueKey('playtest_gate_pass_btn_${node.id}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentEmerald,
                      foregroundColor: const Color(0xFF042117),
                      disabledBackgroundColor:
                          accentEmerald.withValues(alpha: 0.22),
                      disabledForegroundColor: accentEmerald,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onPressed: isPassed
                        ? null
                        : () => _passCheckpointPlaytestAndAdvance(
                              feat,
                              states,
                              node,
                            ),
                    icon: const Icon(Icons.verified_rounded, size: 16),
                    label: Text(
                      isPassed
                          ? '✓ Playtest Passed'
                          : (hasNextCp
                              ? '✓ Pass Playtest & Next Checkpoint →'
                              : '✓ Pass Playtest & Next Feature →'),
                      style: GoogleFonts.inter(
                        fontSize: fontBody,
                        fontWeight: weightBold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
