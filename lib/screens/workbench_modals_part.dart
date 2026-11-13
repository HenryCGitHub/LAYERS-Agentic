part of 'release_workbench_screen.dart';

extension _WorkbenchModalsExt on _ReleaseWorkbenchScreenState {
  static final RegExp _goalPrefixRegex =
      RegExp(r'^Goal:\s*', caseSensitive: false);

  void _showReleaseShippedSummaryModal(BuildContext context, TierDocument rel) {
    final retro = widget.workbench.buildActiveReleaseRetrospective();
    final beats = widget.workbench.activeReleaseBeats;
    final activeRelVer = widget.workbench.activeReleaseVersionTag;
    final allUnfilteredFeats = <TierDocument>[
      for (final b in beats) ...widget.workbench.featuresForBeat(b.id),
    ];
    final releaseHasActiveFeats = allUnfilteredFeats.any(
      (f) => widget.workbench.isFeatureActiveInRelease(f),
    );
    final allFeats = releaseHasActiveFeats
        ? allUnfilteredFeats
            .where((f) => widget.workbench.isFeatureActiveInRelease(f))
            .toList()
        : allUnfilteredFeats;
    int totalTasks = 0;
    int totalStepsDone = 0;
    for (final f in allFeats) {
      final allStates = FeatureStateNode.getStatesForDocument(f);
      final activeStates = allStates
          .where((s) => s.releaseVersion == activeRelVer)
          .toList();
      final states = activeStates.isNotEmpty ? activeStates : allStates;
      for (final s in states) {
        final steps = TaskHowToBlueprint.resolveUnifiedSteps(
          checkpointNode: s,
          engineHint: _engineHint,
          phase: widget.workbench.currentPhase,
        );
        totalTasks += steps.length;
        totalStepsDone += steps.where((c) => c.subtask.completed).length;
      }
    }

    Widget buildStatCol(String value, String label, Color color) {
      return Column(
        children: [
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              color: textMuted,
            ),
          ),
        ],
      );
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Row(
          children: [
            Icon(Icons.rocket_launch_rounded, color: textPrimary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${rel.title} — 100% Shipped & Playtested ✓',
                style: AppTheme.displayFont(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Every Feature and Step across your Core Loop has been completed and verified:',
                style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bgRecessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    buildStatCol('${beats.length}', 'CORE EPICS', textPrimary),
                    buildStatCol('${allFeats.length}', 'FEATURES', textPrimary),
                    buildStatCol('$totalTasks', 'TOTAL STEPS', textPrimary),
                    buildStatCol('$totalStepsDone', 'STEPS DONE', textPrimary),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bgRecessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AGENT RETROSPECTIVE · PLAYTEST HARDENING & CARRYOVER',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• ${retro.fixTasksTriaged} playtest [FIX] task(s) triaged · ${retro.playtestGuardsAdded} [PLAYTEST/SIMULATION GUARD] rules locked into live tree',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: textSecondary,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Builder(
                        builder: (context) {
                          final cov = widget.workbench.fullProductionCoverage();
                          final nextPh =
                              widget.workbench.inferNextProgressivePhase();
                          final covPct = cov.totalBeats > 0
                              ? ((cov.coveredBeats / cov.totalBeats) * 100)
                                  .round()
                              : 100;
                          return Text(
                            '• Lifecycle: ${widget.workbench.currentPhase.label} Shipped → Next: ${nextPh.label} (v1.0 Readiness: ${cov.coveredBeats}/${cov.totalBeats} Epics Hardened · $covPct%)',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    if (retro.carryoverFeatureTitles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '• Auto-Carryover to next Release: ${retro.carryoverFeatureTitles.join(", ")}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor:
                  isDark ? const Color(0xFF06281E) : Colors.white,
              elevation: 0,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _showProgressiveNextReleaseModal(context);
            },
            icon: const Icon(Icons.auto_awesome_rounded, size: 15),
            label: Text(
              '+ New Release (${widget.workbench.nextProgressiveVersionLabel}) ✦',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _showSavedReleasePlanDialog(BuildContext context, TierDocument initialRel) {
    final allReleases = widget.workbench.projectReleases;
    final builtReleases =
        allReleases.where((r) => r.childrenIds.isNotEmpty).toList();
    final selectableReleases =
        builtReleases.isNotEmpty ? builtReleases : allReleases;
    TierDocument selectedRel = initialRel;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final rel = selectedRel;
          final verTag = widget.workbench.releaseVersionTagFor(rel);
          final displayName = widget.workbench.releaseDisplayName(rel);
          final phaseBadge = widget.workbench.releasePhaseShortBadge(rel);
          final savedBp = widget.workbench.releaseBlueprintFor(rel.id);

          final goalText = (savedBp != null && savedBp.goal.trim().isNotEmpty)
              ? savedBp.goal.trim()
              : (rel.sections['scope']
                      ?.split('\n')
                      .first
                      .replaceFirst(
                        _goalPrefixRegex,
                        '',
                      )
                      .trim() ??
                  'Build and playtest $displayName.');
          final doneWhenText =
              (savedBp != null && savedBp.doneWhen.trim().isNotEmpty)
                  ? savedBp.doneWhen.trim()
                  : 'All $verTag features pass playtest verification.';

          final builtChips = <String>[
            if (savedBp != null)
              for (final item in savedBp.builtSoFar)
                if (item.trim().isNotEmpty) item.trim(),
          ];
          final lackingChips = <String>[
            if (savedBp != null)
              for (final g in savedBp.missingGaps)
                if (g.trim().isNotEmpty) g.trim(),
          ];

          final scopeRows =
              <({String epicBadge, String title, String goal, String badge})>[];
          if (savedBp != null) {
            for (int bIdx = 0; bIdx < savedBp.beats.length; bIdx++) {
              final b = savedBp.beats[bIdx];
              final eBadge = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
              for (final f in b.features) {
                if (!f.included ||
                    f.lifecycle == FeatureLifecycleStatus.stable) {
                  continue;
                }
                scopeRows.add((
                  epicBadge: eBadge,
                  title: _formatOutlineFeatureDisplayTitle(
                    f.title,
                    b.title,
                    beatIndex: bIdx,
                  ),
                  goal: f.goal.trim(),
                  badge: f.lifecycle == FeatureLifecycleStatus.newFeature
                      ? '+ NEW · +${f.activeDeltaHours}h'
                      : '↻ UPGRADE · +${f.activeDeltaHours}h',
                ));
              }
            }
          }
          if (scopeRows.isEmpty) {
            final beats = widget.workbench.activeReleaseBeats;
            for (int bIdx = 0; bIdx < beats.length; bIdx++) {
              final b = beats[bIdx];
              final eBadge = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
              for (final f in widget.workbench.featuresForBeat(b.id)) {
                final states = FeatureStateNode.getStatesForDocument(f);
                final inVer = states.any(
                  (s) =>
                      s.releaseVersion.toLowerCase() == verTag.toLowerCase(),
                );
                if (!inVer && verTag != 'v0.1') continue;
                scopeRows.add((
                  epicBadge: eBadge,
                  title: _formatOutlineFeatureDisplayTitle(
                    f.title,
                    b.title,
                    beatIndex: bIdx,
                  ),
                  goal: (f.sections['scope'] ?? '')
                      .split('\n')
                      .first
                      .replaceFirst(
                        _goalPrefixRegex,
                        '',
                      )
                      .trim(),
                  badge: (f.sections['originVersion'] ?? 'v0.1') == verTag
                      ? '+ NEW'
                      : '↻ UPGRADE',
                ));
              }
            }
          }

          return AlertDialog(
            backgroundColor: bgSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: borderBright),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$phaseBadge · $verTag',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: textMuted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$verTag Release Plan — $displayName',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (selectableReleases.length > 1) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final r in selectableReleases)
                        Builder(
                          builder: (context) {
                            final rVer =
                                widget.workbench.releaseVersionTagFor(r);
                            final rPhase =
                                widget.workbench.releasePhaseShortBadge(r);
                            final isSel = r.id == rel.id;
                            return InkWell(
                              key: ValueKey('saved_plan_tab_${r.id}'),
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                setModalState(() {
                                  selectedRel = r;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: isSel
                                          ? textPrimary
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  '$rVer · $rPhase',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSel ? textPrimary : textSecondary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 540),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  goalText,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: bgRecessed,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: borderSubtle),
                  ),
                  child: Text(
                    'DONE WHEN · $doneWhenText',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                ),
                if (builtChips.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '✓ BUILT BEFORE ${verTag.toUpperCase()} (${builtChips.length})',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final chip in builtChips)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: bgRecessed,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Text(
                            '✓ $chip',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (lackingChips.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '⚠ LACKING AT THE TIME (${lackingChips.length})',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final gap in lackingChips)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        '• $gap',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Text(
                  '✦ SCOPE IN ${verTag.toUpperCase()} (${scopeRows.length} FEATURES)',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final row in scopeRows)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: bgRecessed,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Text(
                            row.epicBadge,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.title,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              if (row.goal.isNotEmpty)
                                Text(
                                  row.goal,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          row.badge,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                Builder(
                  builder: (context) {
                    final ledger =
                        widget.workbench.buildCrossReleaseEvolutionLedger();
                    if (ledger.isEmpty) return const SizedBox.shrink();
                    return Column(
                      key: const ValueKey('cross_release_evolution_ledger'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          '↻ CROSS-RELEASE EVOLUTION & TUNING LEDGER',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final item in ledger)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: bgRecessed,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: borderSubtle),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.epicCode} · ${item.featureTitle}',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: textPrimary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${item.lifecycle} · ${item.guardCount} GUARDS',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                if (item.checkpointProgression.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    item.checkpointProgression.join(' → '),
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                                if (item.tuningDeltaSummary.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'Vars: ${item.tuningDeltaSummary.join(' · ')}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9.5,
                                      color: textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
        ],
      );
    },
  ),
);
  }

  void _showFeatureInboxModal(BuildContext context, {String? preferredBeatId}) {
    _inboxCaptureCtrl.clear();
    bool isSubmitting = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final pendingItems = widget.workbench.pendingFeatureInboxItems;
          final scheduledItems = widget.workbench.scheduledFeatureInboxItems;
          final beats = widget.workbench.activeReleaseBeats;
          final activeVer = widget.workbench.activeReleaseVersionTag;
          final activePhase = widget.workbench.currentPhase;

          Future<void> handleCapture(String text) async {
            final clean = text.trim();
            if (clean.isEmpty || isSubmitting) return;
            setModalState(() => isSubmitting = true);
            _inboxCaptureCtrl.clear();
            await widget.workbench.submitFeatureIdeaToInbox(
              clean,
              preferredBeatId: preferredBeatId,
            );
            if (ctx.mounted) {
              setModalState(() => isSubmitting = false);
            }
            _rebuild(() {});
          }

          return AlertDialog(
            backgroundColor: bgSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: borderBright),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📥 AGENTIC FEATURE INBOX · WHEN · WHERE · HOW TRIAGE',
                        style: AppTheme.displayFont(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Capture any feature idea — the Agent figures out WHEN (Current vs. Split vs. Future Release), WHERE (Epic & Feature vs. Upgrade), and HOW to implement it.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: bgRecessed,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: borderSubtle),
                  ),
                  child: Text(
                    '$activeVer · ${activePhase.shortName}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Quick Capture Bar
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: bgRecessed,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('inbox_capture_input'),
                              controller: _inboxCaptureCtrl,
                              autofocus: pendingItems.isEmpty,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Describe a feature to add (e.g., "Add dash i-frames", "Skill tree shop", "Boss laser sweep")...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                                isDense: true,
                                border: InputBorder.none,
                              ),
                              onSubmitted: handleCapture,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            key: const ValueKey('inbox_capture_submit_btn'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentEmerald,
                              foregroundColor: isDark
                                  ? const Color(0xFF06281E)
                                  : Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () => handleCapture(_inboxCaptureCtrl.text),
                            child: Text(
                              isSubmitting
                                  ? 'Triaging...'
                                  : '+ Capture & Triage ✦',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 2. Needs Triage Section
                    Text(
                      'NEEDS TRIAGE (${pendingItems.length})',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (pendingItems.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: bgRecessed,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderSubtle),
                        ),
                        child: Text(
                          'No untriaged ideas in your Inbox. Type a feature idea above and the Agent will figure out WHEN, WHERE, and HOW to build it.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: textMuted,
                          ),
                        ),
                      )
                    else
                      for (final item in pendingItems)
                        Container(
                          key: ValueKey('inbox_card_${item.id}'),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: bgRecessed,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderBright),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.featureTitle,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    key: ValueKey(
                                      'inbox_dismiss_btn_${item.id}',
                                    ),
                                    onTap: () {
                                      widget.workbench
                                          .removeFeatureInboxItem(item.id);
                                      setModalState(() {});
                                      _rebuild(() {});
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        '✕ Dismiss',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9.5,
                                          color: textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Request: "${item.rawIdea}"',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: textMuted,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // 1. WHEN (Release Timing)
                              Text(
                                '1. WHEN · RELEASE TIMING VERDICT',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final mode
                                      in InboxReleaseTimingMode.values)
                                    Builder(
                                      builder: (context) {
                                        final isSel =
                                            item.releaseTimingMode == mode;
                                        final label = switch (mode) {
                                          InboxReleaseTimingMode.now =>
                                            '🟢 Build Now ($activeVer)',
                                          InboxReleaseTimingMode
                                              .splitNowAndFuture =>
                                            '🟣 Split: $activeVer Core + ${item.targetFuturePhase.shortName} Upgrade',
                                          InboxReleaseTimingMode
                                              .futureRelease =>
                                            '🗓 Schedule for ${item.targetFuturePhase.shortName}',
                                        };
                                        return InkWell(
                                          key: ValueKey(
                                            'inbox_timing_${item.id}_${mode.name}',
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          onTap: () {
                                            widget.workbench
                                                .updateFeatureInboxItemTriage(
                                              item.id,
                                              timingMode: mode,
                                            );
                                            setModalState(() {});
                                            _rebuild(() {});
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSel
                                                  ? bgSurface
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: isSel
                                                    ? accentEmerald
                                                    : borderSubtle,
                                              ),
                                            ),
                                            child: Text(
                                              label,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10,
                                                fontWeight: isSel
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: isSel
                                                    ? textPrimary
                                                    : textSecondary,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                              if (item.releaseTimingMode !=
                                  InboxReleaseTimingMode.now) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    for (final ph in [
                                      ProductionPhase.mvp,
                                      ProductionPhase.verticalSlice,
                                      ProductionPhase.fullProduction,
                                      ProductionPhase.postLaunch,
                                    ])
                                      InkWell(
                                        key: ValueKey(
                                          'inbox_phase_${item.id}_${ph.name}',
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        onTap: () {
                                          widget.workbench
                                              .updateFeatureInboxItemTriage(
                                            item.id,
                                            targetFuturePhase: ph,
                                          );
                                          setModalState(() {});
                                          _rebuild(() {});
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: item.targetFuturePhase == ph
                                                ? bgSurface
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                              color:
                                                  item.targetFuturePhase == ph
                                                      ? borderBright
                                                      : borderSubtle,
                                            ),
                                          ),
                                          child: Text(
                                            'Target: ${ph.label}',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 9.5,
                                              fontWeight:
                                                  item.targetFuturePhase == ph
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                              color:
                                                  item.targetFuturePhase == ph
                                                      ? textPrimary
                                                      : textMuted,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                item.releaseTimingReasoning,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: textSecondary,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // 2. WHERE (Single Live Tree Placement)
                              Text(
                                '2. WHERE · EPIC & LIVE TREE PLACEMENT',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final intMode in [
                                    InboxIntegrationMode.newFeatureInEpic,
                                    InboxIntegrationMode.upgradeExistingFeature,
                                    InboxIntegrationMode.newEpicAndFeature,
                                  ])
                                    Builder(
                                      builder: (context) {
                                        final isSel =
                                            item.integrationMode == intMode;
                                        final modeLabel = switch (intMode) {
                                          InboxIntegrationMode
                                              .newFeatureInEpic =>
                                            '+ NEW Feature in ${item.targetBeatTitle}',
                                          InboxIntegrationMode
                                              .upgradeExistingFeature =>
                                            '↑ UPGRADE "${item.targetFeatureTitle ?? 'Existing Feature'}"',
                                          InboxIntegrationMode
                                              .newEpicAndFeature =>
                                            '+ NEW Core Loop Epic',
                                        };
                                        return InkWell(
                                          key: ValueKey(
                                            'inbox_intmode_${item.id}_${intMode.name}',
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          onTap: () {
                                            widget.workbench
                                                .updateFeatureInboxItemTriage(
                                              item.id,
                                              integrationMode: intMode,
                                            );
                                            setModalState(() {});
                                            _rebuild(() {});
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSel
                                                  ? bgSurface
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: isSel
                                                    ? borderBright
                                                    : borderSubtle,
                                              ),
                                            ),
                                            child: Text(
                                              modeLabel,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10,
                                                fontWeight: isSel
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: isSel
                                                    ? textPrimary
                                                    : textSecondary,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                              if (beats.length > 1 &&
                                  item.integrationMode !=
                                      InboxIntegrationMode
                                          .newEpicAndFeature) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    for (int bIdx = 0;
                                        bIdx < beats.length;
                                        bIdx++)
                                      Builder(
                                        builder: (context) {
                                          final b = beats[bIdx];
                                          final isBeatSel =
                                              item.targetBeatId == b.id;
                                          final eCode =
                                              'E${(bIdx + 1).toString().padLeft(2, '0')}';
                                          return InkWell(
                                            key: ValueKey(
                                              'inbox_beat_${item.id}_${b.id}',
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            onTap: () {
                                              widget.workbench
                                                  .updateFeatureInboxItemTriage(
                                                item.id,
                                                targetBeatId: b.id,
                                              );
                                              setModalState(() {});
                                              _rebuild(() {});
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isBeatSel
                                                    ? bgSurface
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isBeatSel
                                                      ? borderBright
                                                      : borderSubtle,
                                                ),
                                              ),
                                              child: Text(
                                                '$eCode · ${b.title}',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 9.5,
                                                  fontWeight: isBeatSel
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: isBeatSel
                                                      ? textPrimary
                                                      : textMuted,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ],
                              if (item.integrationMode ==
                                  InboxIntegrationMode
                                      .upgradeExistingFeature) ...[
                                Builder(
                                  builder: (context) {
                                    final targetFeats = widget.workbench
                                        .featuresForBeat(item.targetBeatId);
                                    if (targetFeats.length <= 1) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          for (final tf in targetFeats)
                                            Builder(
                                              builder: (context) {
                                                final isFeatSel =
                                                    item.targetFeatureId ==
                                                        tf.id;
                                                return InkWell(
                                                  key: ValueKey(
                                                    'inbox_target_feat_${item.id}_${tf.id}',
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  onTap: () {
                                                    widget.workbench
                                                        .updateFeatureInboxItemTriage(
                                                      item.id,
                                                      targetFeatureId: tf.id,
                                                    );
                                                    setModalState(() {});
                                                    _rebuild(() {});
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: isFeatSel
                                                          ? bgSurface
                                                          : Colors.transparent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                      border: Border.all(
                                                        color: isFeatSel
                                                            ? accentEmerald
                                                            : borderSubtle,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '↑ ${tf.title}',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 9.5,
                                                        fontWeight: isFeatSel
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        color: isFeatSel
                                                            ? textPrimary
                                                            : textMuted,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                item.placementReasoning,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: textSecondary,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // 3. HOW (Implementation Blueprint)
                              Text(
                                '3. HOW · ENGINE & CHECKPOINT ARCHITECTURE',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Goal: ${item.goal}\nPlaytest Gate: ${item.playtestGate}',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: textPrimary,
                                ),
                              ),
                              if (item.architectureHowSummary.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                for (final line in item.architectureHowSummary)
                                  Text(
                                    '• $line',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: textSecondary,
                                    ),
                                  ),
                              ],
                              if (item.tasks.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Tasks: ${item.tasks.join(' · ')}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    color: textMuted,
                                  ),
                                ),
                              ],
                              if (item.releaseTimingMode !=
                                      InboxReleaseTimingMode.now &&
                                  item.futureCheckpointTitle.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: bgSurface,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: borderSubtle),
                                  ),
                                  child: Text(
                                    '🗓 Queued for ${item.targetFuturePhase.label}: ${item.futureCheckpointTitle} — ${item.futureGoal}',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ElevatedButton(
                                    key: ValueKey('inbox_accept_btn_${item.id}'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accentEmerald,
                                      foregroundColor: isDark
                                          ? const Color(0xFF06281E)
                                          : Colors.white,
                                      elevation: 0,
                                    ),
                                    onPressed: () async {
                                      final timing = item.releaseTimingMode;
                                      await widget.workbench
                                          .acceptFeatureInboxTriage(item.id);
                                      if (ctx.mounted) {
                                        if (timing !=
                                            InboxReleaseTimingMode
                                                .futureRelease) {
                                          Navigator.of(ctx).pop();
                                        } else {
                                          setModalState(() {});
                                        }
                                      }
                                      _rebuild(() {
                                        _manualCheckpointFocusIndex = null;
                                        _manualCheckpointFocusFeatureId = null;
                                      });
                                    },
                                    child: Text(
                                      switch (item.releaseTimingMode) {
                                        InboxReleaseTimingMode.now =>
                                          '✓ Build Now in $activeVer →',
                                        InboxReleaseTimingMode
                                            .splitNowAndFuture =>
                                          '✓ Build $activeVer Core + Schedule ${item.targetFuturePhase.shortName} Upgrade →',
                                        InboxReleaseTimingMode.futureRelease =>
                                          '✓ Schedule for ${item.targetFuturePhase.label} →',
                                      },
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                    // 3. Scheduled for Future Releases Section
                    if (scheduledItems.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'SCHEDULED FOR FUTURE RELEASES (${scheduledItems.length}) — AUTO-INJECTS WHEN PHASE OPENS',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final sched in scheduledItems)
                        Container(
                          key: ValueKey('inbox_scheduled_card_${sched.id}'),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: bgRecessed,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '🗓 ${sched.targetFuturePhase.label} · ${sched.futureCheckpointTitle.isNotEmpty ? sched.futureCheckpointTitle : sched.featureTitle}',
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${sched.integrationMode == InboxIntegrationMode.upgradeExistingFeature ? 'Upgrades "${sched.targetFeatureTitle ?? sched.featureTitle}"' : 'New Feature in ${sched.targetBeatTitle}'} — ${sched.futureGoal.isNotEmpty ? sched.futureGoal : sched.goal}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                key: ValueKey(
                                  'inbox_pull_now_btn_${sched.id}',
                                ),
                                onPressed: () async {
                                  await widget.workbench
                                      .acceptFeatureInboxTriage(
                                    sched.id,
                                    forceBuildNow: true,
                                  );
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                  }
                                  _rebuild(() {
                                    _manualCheckpointFocusIndex = null;
                                    _manualCheckpointFocusFeatureId = null;
                                  });
                                },
                                child: Text(
                                  '⚡ Pull into $activeVer Now',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
