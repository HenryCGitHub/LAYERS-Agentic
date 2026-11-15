part of 'release_workbench_screen.dart';

extension _WorkbenchEngineAreasExt on _ReleaseWorkbenchScreenState {
  static final RegExp _scopeVarAnnotRegex = RegExp(
    r'\s*\((?:@export|export\s+var|float|int|bool|String|Vector[23]|NodePath|PackedScene)[^)]*\)',
    caseSensitive: false,
  );
  static final RegExp _scopeInlineAssignRegex = RegExp(
    r'\s*[@`]?[a-z_][a-z0-9_]*\s*[:=]\s*[-+]?\d+(?:\.\d+)?[a-zA-Z%/]*',
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

    final scopeSource = node.coveredScope.isNotEmpty
        ? node.coveredScope
        : SectionTextUtils.resolveInScope(feat.sections);
    final inScopeBullets = [
      for (final item in scopeSource)
        if (_formatPlainEnglishScopeBullet(item).isNotEmpty)
          _formatPlainEnglishScopeBullet(item),
    ];

    final endGoal = node.playtestCondition.trim().isNotEmpty
        ? node.playtestCondition.trim()
        : SectionTextUtils.resolveDoneWhen(feat.sections).trim();

    node.flattenLegacyNestedChecklistIfNeeded();
    final openFixEntries = node.openFixItems;

    final activeVer = widget.workbench.activeReleaseVersionTag;
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
          Text(
            conciseGoal,
            key: ValueKey('task_sheet_feature_goal_${node.id}'),
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: weightSemi,
              height: 1.45,
              color: textPrimary,
            ),
          ),

          // 2. IN SCOPE
          if (inScopeBullets.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'IN SCOPE',
              style: GoogleFonts.jetBrainsMono(
                fontSize: fontMicro,
                fontWeight: weightBold,
                letterSpacing: 0.7,
                color: textMuted,
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < inScopeBullets.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == inScopeBullets.length - 1 ? 0 : 6,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 9),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.8),
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
                  ],
                ),
              ),
          ],

          // 3. DONE WHEN (Playtest Check)
          if (endGoal.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
          ],

          // Optional: Open [FIX] Issues logged from Web Studio or Godot
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

          // Optional: Plain-English State & Boundary Guards
          if (edgeItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                Text(
                  '$signedOffGuards/${edgeItems.length} Checked',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: fontMicro,
                    fontWeight: weightBold,
                    color: const Color(0xFFFCD34D),
                  ),
                ),
              ],
            ),
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
                  return InkWell(
                    key: ValueKey('playtest_guard_check_${node.id}_$gIdx'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      node.setGuardSignedOff(gIdx, rawGuard, !isChecked);
                      widget.workbench.updateFeatureStates(feat.id, states);
                      _rebuild();
                    },
                    child: Container(
                      margin: EdgeInsets.only(
                        bottom: gIdx == edgeItems.length - 1 ? 0 : 6,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
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
                  );
                },
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
              ElevatedButton.icon(
                key: ValueKey('playtest_gate_pass_btn_${node.id}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPassed
                      ? accentEmerald.withValues(alpha: 0.22)
                      : accentEmerald,
                  foregroundColor:
                      isPassed ? accentEmerald : const Color(0xFF042117),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onPressed: () =>
                    _passCheckpointPlaytestAndAdvance(feat, states, node),
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
    );
  }
}
