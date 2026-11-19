part of 'release_workbench_screen.dart';

/// Opens the `v0.2+` Progressive Release Co-Pilot Dialog:
/// 1-click direction presets, baseline `[UPGRADE]` `+Delta` toggles, and `[NEW]` 6-section Epics.
Future<void> showProgressiveReleaseCopilotDialog(
  BuildContext context,
  WorkbenchProvider workbench,
) async {
  await workbench.openProgressiveReleaseCopilot();
  if (!context.mounted) return;

  final directionController = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return AnimatedBuilder(
            animation: workbench,
            builder: (_, __) {
              final isDark = workbench.isDark;
              final draft = workbench.progressiveDraft;
              final textPrimary = AppTheme.textPrimaryFor(isDark);
              final textSecondary = AppTheme.textSecondaryFor(isDark);
              final textMuted = AppTheme.textMutedFor(isDark);
              final border = AppTheme.borderFor(isDark);
              final cyan = AppTheme.accentCyanFor(isDark);
              final green = AppTheme.accentGreenFor(isDark);

              if (draft == null) {
                return AlertDialog(
                  backgroundColor: AppTheme.bgSurfaceRaisedFor(isDark),
                  title: Text('Progressive Release Co-Pilot', style: TextStyle(color: textPrimary)),
                  content: const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }

              final baseEpics = workbench.latestReleaseEpics;

              return Dialog(
                backgroundColor: AppTheme.bgSurfaceRaisedFor(isDark),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  side: BorderSide(color: border),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720, maxHeight: 740),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 18, color: cyan),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Plan Progressive Release (${draft.targetVersion})',
                                style: AppTheme.displayFont(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                workbench.closeProgressiveReleaseCopilot();
                                Navigator.of(dialogCtx).pop();
                              },
                              icon: Icon(Icons.close, color: textMuted),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: border),

                      // Direction input + presets + live delta checklist
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      key: const ValueKey('copilot_direction_input'),
                                      controller: directionController,
                                      style: TextStyle(fontSize: 13, color: textPrimary),
                                      decoration: InputDecoration(
                                        hintText:
                                            'Optional release focus (e.g. "Add 3-wave arena escalation and shield parry")',
                                        hintStyle: TextStyle(fontSize: 12.5, color: textMuted),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    key: const ValueKey('copilot_regenerate_btn'),
                                    onPressed: workbench.isDraftingProgressive
                                        ? null
                                        : () async {
                                            await workbench.openProgressiveReleaseCopilot(
                                              directionPrompt: directionController.text.trim(),
                                            );
                                          },
                                    icon: workbench.isDraftingProgressive
                                        ? const SizedBox(
                                            width: 13,
                                            height: 13,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.refresh, size: 14),
                                    label: const Text('Ask Co-Pilot', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // 1-Click Direction Presets
                              if (draft.presets.isNotEmpty) ...[
                                Text(
                                  'RELEASE DIRECTION PRESETS',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: textMuted,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final preset in draft.presets)
                                      ChoiceChip(
                                        key: ValueKey('copilot_preset_${preset.id}'),
                                        label: Text(preset.label),
                                        selected: draft.activePresetId == preset.id,
                                        onSelected: (_) =>
                                            workbench.applyProgressivePreset(preset.id),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Baseline Epics (Keep Baseline vs [UPGRADE] deltas)
                              Text(
                                'EXISTING BASELINE EPICS',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: textMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final base in baseEpics) ...[
                                Builder(
                                  builder: (_) {
                                    final keyLower = base.lineageKey.toLowerCase();
                                    final upgrades =
                                        draft.upgradesByLineageKey[keyLower] ??
                                            const <EpicUpgradeOption>[];
                                    final newFeatures =
                                        draft.candidateNewFeaturesByLineageKey[
                                                keyLower] ??
                                            const <FeatureSpec>[];
                                    final hasSelectedChange =
                                        upgrades.any((u) => u.chosen) ||
                                        newFeatures.any(
                                          (nf) => workbench
                                              .isProgressiveNewFeatureChosen(
                                            nf.id,
                                          ),
                                        );
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppTheme.bgSurfaceFor(isDark),
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.radiusSm,
                                        ),
                                        border: Border.all(
                                          color: hasSelectedChange
                                              ? cyan.withValues(alpha: 0.4)
                                              : border,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${base.code} · ${base.title}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: textPrimary,
                                                  ),
                                                ),
                                              ),
                                              if (!hasSelectedChange) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: green.withValues(
                                                      alpha: 0.14,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      AppTheme.radiusXs,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'Keep Baseline ✓',
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 11,
                                                      color: green,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (upgrades.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            for (final up in upgrades)
                                              Material(
                                                type: MaterialType.transparency,
                                                child: CheckboxListTile(
                                                  key: ValueKey(
                                                    'copilot_up_${up.id}',
                                                  ),
                                                  dense: true,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  value: up.chosen,
                                                  onChanged: (_) => workbench
                                                      .toggleProgressiveUpgrade(
                                                    base.lineageKey,
                                                    up.id,
                                                  ),
                                                  title: Text(
                                                    up.targetFeatureCode !=
                                                                null &&
                                                            up
                                                                .targetFeatureCode!
                                                                .trim()
                                                                .isNotEmpty
                                                        ? '[+DELTA ${up.targetFeatureCode!.trim()}] ${up.text}'
                                                        : '[UPGRADE] ${up.text}',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                          if (newFeatures.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            for (final nf in newFeatures)
                                              Material(
                                                type: MaterialType.transparency,
                                                child: CheckboxListTile(
                                                  key: ValueKey(
                                                    'copilot_new_feat_${nf.id}',
                                                  ),
                                                  dense: true,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  value: workbench
                                                      .isProgressiveNewFeatureChosen(
                                                    nf.id,
                                                  ),
                                                  onChanged: (_) => workbench
                                                      .toggleProgressiveNewFeature(
                                                    base.lineageKey,
                                                    nf.id,
                                                  ),
                                                  title: Text(
                                                    '[+${draft.targetVersion} NEW ${nf.code}] ${nf.title} (${nf.sliceTime})',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: cyan,
                                                    ),
                                                  ),
                                                  subtitle: nf.goal.isNotEmpty
                                                      ? Text(
                                                          nf.goal,
                                                          style: TextStyle(
                                                            fontSize: 11.5,
                                                            color: textMuted,
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                              ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],

                              // Candidate [NEW] Epics
                              if (draft.candidateNewEpics.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'NEW ${draft.targetVersion.toUpperCase()} EPICS',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cyan,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                for (final cand in draft.candidateNewEpics)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.bgSurfaceFor(isDark),
                                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                                      border: Border.all(
                                        color: cand.chosenForNextRelease
                                            ? cyan.withValues(alpha: 0.5)
                                            : border,
                                      ),
                                    ),
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: CheckboxListTile(
                                        key: ValueKey('copilot_new_${cand.id}'),
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        value: cand.chosenForNextRelease,
                                        onChanged: (_) =>
                                            workbench.toggleProgressiveNewEpic(cand.id),
                                        title: Text(
                                          '[NEW] ${cand.code} · ${cand.title}',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: textPrimary,
                                          ),
                                        ),
                                        subtitle: Text(
                                          cand.features.isNotEmpty
                                              ? '${cand.goal} · ${cand.features.length} Feature slices'
                                              : cand.goal,
                                          style: TextStyle(fontSize: 12, color: textMuted),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      Divider(height: 1, color: border),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                workbench.closeProgressiveReleaseCopilot();
                                Navigator.of(dialogCtx).pop();
                              },
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              key: const ValueKey('copilot_commit_btn'),
                              onPressed: () {
                                workbench.commitProgressiveReleaseDraft();
                                Navigator.of(dialogCtx).pop();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: green,
                                foregroundColor: Colors.black,
                              ),
                              icon: const Icon(Icons.rocket_launch_outlined, size: 16),
                              label: Text('Create ${draft.targetVersion} Release →'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    },
  );

  directionController.dispose();
}
