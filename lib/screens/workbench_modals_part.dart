part of 'release_workbench_screen.dart';

extension _WorkbenchModalsExt on _ReleaseWorkbenchScreenState {
  Future<void> _showProgressiveNextReleaseModal(BuildContext context) async {
    if (!widget.workbench.isActiveReleaseComplete) {
      final activeRel = widget.workbench.activeRelease;
      final activeVer = widget.workbench.activeReleaseVersionTag;
      final prog = activeRel != null
          ? widget.workbench.getDocumentProgress(activeRel.id)
          : 0;
      final nextVer = widget.workbench.nextProgressiveVersionLabel;
      AppToast.show(
        context,
        'Complete all $activeVer features ($prog% done) before planning $nextVer.',
        icon: Icons.lock_outline_rounded,
        isDark: isDark,
        accentColor: accentAmber,
      );
      return;
    }

    if (_isProgressiveModalOpen) return;

    final prevReleaseId = widget.workbench.activeReleaseId;
    final prevPhase = widget.workbench.currentPhase;

    _rebuild(() {
      _isProgressiveModalOpen = true;
      _progressivePrevReleaseId = prevReleaseId;
      _progressivePrevPhase = prevPhase;
      _selectedProgressiveTrackIndex = 0;
      _addingFeatureToBeatId = null;
      _progressiveDirectiveCtrl.clear();
      _progressiveNewFeatCtrl.clear();
    });

    try {
      await widget.workbench.prepareProgressiveNextReleaseDraft();
    } finally {
      if (mounted) {
        _rebuild(() {});
      }
    }
  }

  Future<void> _closeProgressiveReleasePlanner({
    required bool confirmed,
  }) async {
    final prevRelId = _progressivePrevReleaseId;
    final prevPhase = _progressivePrevPhase ?? widget.workbench.currentPhase;

    if (mounted) {
      _rebuild(() {
        _isProgressiveModalOpen = false;
        _addingFeatureToBeatId = null;
        if (confirmed) {
          _manualCheckpointFocusIndex = null;
          _selectedTaskIndexByCheckpoint.clear();
          _selectedSubStepIndexByTask.clear();
        }
      });
    } else {
      _isProgressiveModalOpen = false;
      _addingFeatureToBeatId = null;
      if (confirmed) {
        _manualCheckpointFocusIndex = null;
        _selectedTaskIndexByCheckpoint.clear();
        _selectedSubStepIndexByTask.clear();
      }
    }

    if (confirmed) {
      await widget.workbench.approveAndExecuteReleasePlan();
    } else {
      widget.workbench.restoreActiveReleaseAfterCancel(prevRelId, prevPhase);
    }
  }

  Widget _buildProgressiveReleasePlannerCanvas(BuildContext context) {
    final bp = widget.workbench.releaseBlueprint;
    final nextVer =
        bp?.releaseVersionTag ?? widget.workbench.nextProgressiveVersionLabel;
    final prevRelDoc = _progressivePrevReleaseId != null
        ? widget.workbench.documents[_progressivePrevReleaseId!]
        : null;
    final prevVer = prevRelDoc != null
        ? widget.workbench.releaseVersionTagFor(prevRelDoc)
        : 'v0.1';

    int upgradeCount = 0;
    int newCount = 0;
    if (bp != null) {
      for (final b in bp.beats) {
        for (final f in b.features) {
          if (f.lifecycle == FeatureLifecycleStatus.upgrade && f.included) {
            upgradeCount++;
          } else if (f.lifecycle == FeatureLifecycleStatus.newFeature &&
              f.included) {
            newCount++;
          }
        }
      }
    }

    final dynamicQuestion =
        (bp != null && bp.questions.isNotEmpty) ? bp.questions.first : null;
    final dynamicOptions = dynamicQuestion != null &&
            dynamicQuestion.options.isNotEmpty
        ? dynamicQuestion.options
        : <String>[
            '(Recommended) Keep Agent\'s Recommended $nextVer Scope',
            'Focus $nextVer on Core Mechanic Depth & Game Feel',
            'Promote 1 Deferred Backlog Feature into $nextVer',
          ];

    Future<void> submitDirective(String promptText) async {
      final cleanPrompt = promptText.trim();
      if (cleanPrompt.isEmpty || widget.workbench.isAgentBusy) return;
      await widget.workbench.sendReleasePlanChatMessage(cleanPrompt);
      if (mounted) _rebuild(() {});
    }

    return Container(
      key: const ValueKey('progressive_next_release_modal'),
      color: bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Sticky Header Bar
          Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
            decoration: BoxDecoration(
              color: bgSurface,
              border: Border(bottom: BorderSide(color: borderBright)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 10,
              spacing: 16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: accentCyan,
                          size: 16,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'PROGRESSIVE RELEASE CO-PILOT · ${nextVer.toUpperCase()}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: accentCyan,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accentEmerald.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: accentEmerald.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            '$prevVer 100% SHIPPED ✓',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: accentEmerald,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bp?.releaseTitle.isNotEmpty == true
                          ? bp!.releaseTitle
                          : (widget.workbench.isAgentBusy
                              ? 'Architecting $nextVer Release Scope...'
                              : 'Recommended Scope for $nextVer'),
                      style: AppTheme.displayFont(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'TARGET PHASE:',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: textMuted,
                          ),
                        ),
                        for (final phase in ProductionPhase.values)
                          Builder(
                            builder: (context) {
                              final isSelected =
                                  widget.workbench.currentPhase == phase;
                              final shortLabel =
                                  phase == ProductionPhase.prototype
                                      ? '01 · Prototype'
                                      : (phase == ProductionPhase.mvp
                                          ? '02 · MVP'
                                          : (phase ==
                                                  ProductionPhase.verticalSlice
                                              ? '03 · Vertical Slice'
                                              : '04 · Full Production'));
                              return InkWell(
                                key: ValueKey(
                                  'progressive_phase_pill_${phase.name}',
                                ),
                                borderRadius: BorderRadius.circular(5),
                                onTap: widget.workbench.isAgentBusy
                                    ? null
                                    : () async {
                                        if (isSelected) return;
                                        await widget.workbench
                                            .setDraftReleasePhase(phase);
                                        if (mounted) _rebuild(() {});
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? accentCyan.withValues(alpha: 0.14)
                                        : bgRecessed,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: isSelected
                                          ? accentCyan.withValues(alpha: 0.55)
                                          : borderSubtle,
                                    ),
                                  ),
                                  child: Text(
                                    shortLabel,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? accentCyan
                                          : textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bp != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: bgRecessed,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: borderSubtle),
                        ),
                        child: Text(
                          '${bp.totalIncludedHours}h in $nextVer · ${upgradeCount + newCount} Active Features',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: accentEmerald,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    TextButton(
                      onPressed: () =>
                          _closeProgressiveReleasePlanner(confirmed: false),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      key: const ValueKey('confirm_progressive_release_btn'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentEmerald,
                        foregroundColor: const Color(0xFF052E16),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onPressed: (widget.workbench.isAgentBusy || bp == null)
                          ? null
                          : () => _closeProgressiveReleasePlanner(
                                confirmed: true,
                              ),
                      child: Text(
                        'Approve & Build $nextVer →',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main Scrollable Progressive Release Canvas
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.workbench.isAgentBusy) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: accentCyan.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accentCyan,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      widget.workbench.agentProgressStep ??
                                          '✦ Agent is analyzing your completed $prevVer build state and synthesizing $nextVer...',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: accentCyan,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (bp == null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Inspecting your completed $prevVer features, verified checkpoints, live tuning variables, playtest fixes, and Stage 1 Design Pillars to determine which features to upgrade or introduce in $nextVer...',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      if (bp != null) ...[
                        // Section 1: Greyscale-First Vertical Agent Diagnostic Card (gemini-4-argon)
                        Builder(
                          builder: (context) {
                            // 1. Resolve "Built So Far" chips
                            final builtChips = <String>[
                              for (final item in bp.builtSoFar)
                                if (item.trim().isNotEmpty) item.trim(),
                            ];
                            if (builtChips.isEmpty) {
                              for (final b in bp.beats) {
                                for (final f in b.features) {
                                  if (f.isStable &&
                                      f.title.trim().isNotEmpty &&
                                      !builtChips.contains(f.title.trim())) {
                                    builtChips.add(f.title.trim());
                                  }
                                }
                              }
                            }
                            if (builtChips.isEmpty &&
                                bp.lastAgentReply != null &&
                                bp.lastAgentReply!.trim().isNotEmpty) {
                              final firstSentence = bp.lastAgentReply!
                                  .split(RegExp(r'\.\s+'))
                                  .first
                                  .replaceFirst(
                                    RegExp(
                                      r'^Prior releases established\s+',
                                      caseSensitive: false,
                                    ),
                                    '',
                                  )
                                  .trim();
                              for (final part in firstSentence.split(
                                RegExp(r',\s*(?:and\s+)?|\s+and\s+'),
                              )) {
                                final cleanPart = part
                                    .replaceAll(RegExp(r'\.$'), '')
                                    .trim();
                                if (cleanPart.isNotEmpty &&
                                    cleanPart.length <= 48) {
                                  builtChips.add(cleanPart);
                                }
                              }
                            }

                            // 2. Resolve "Lacking Now" rows (with optional E0X tag)
                            final rawGaps = <String>[
                              for (final g in bp.missingGaps)
                                if (g.trim().isNotEmpty) g.trim(),
                            ];
                            if (rawGaps.isEmpty &&
                                bp.lastAgentReply != null &&
                                bp.lastAgentReply!.trim().isNotEmpty) {
                              final sentences = bp.lastAgentReply!
                                  .split(RegExp(r'(?<=\.)\s+'));
                              for (final s in sentences) {
                                final lower = s.toLowerCase();
                                if (lower.contains('however') ||
                                    lower.contains('lacks') ||
                                    lower.contains('missing')) {
                                  final cleaned = s
                                      .replaceFirst(
                                        RegExp(
                                          r'^However,\s*',
                                          caseSensitive: false,
                                        ),
                                        '',
                                      )
                                      .replaceAll(RegExp(r'\.$'), '')
                                      .trim();
                                  for (final clause in cleaned.split(
                                    RegExp(
                                      r',\s*(?=(?:Beat|Epic|E0)\s*\d+)|,\s+and\s+(?=(?:Beat|Epic|E0)\s*\d+)',
                                      caseSensitive: false,
                                    ),
                                  )) {
                                    final c = clause.trim();
                                    if (c.isNotEmpty) rawGaps.add(c);
                                  }
                                }
                              }
                            }
                            if (rawGaps.isEmpty) {
                              for (int bIdx = 0;
                                  bIdx < bp.beats.length;
                                  bIdx++) {
                                final b = bp.beats[bIdx];
                                final activeFeats = b.includedFeatures
                                    .where((f) => !f.isStable)
                                    .toList();
                                if (activeFeats.isNotEmpty) {
                                  final eCode =
                                      'E${(bIdx + 1).toString().padLeft(2, '0')}';
                                  rawGaps.add(
                                    '$eCode ${b.title}: Needs ${activeFeats.map((f) => f.title).join(' & ')}',
                                  );
                                }
                              }
                            }

                            // 3. Collect "Next in v0.X" active feature rows
                            final nextRows = <({
                              String beatId,
                              String epicCode,
                              ProposedFeatureBlueprint feat,
                            })>[];
                            for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) {
                              final b = bp.beats[bIdx];
                              final eCode =
                                  'E${(bIdx + 1).toString().padLeft(2, '0')}';
                              for (final f in b.features) {
                                if (!f.isStable && !f.isSuperseded) {
                                  nextRows.add((
                                    beatId: b.id,
                                    epicCode: eCode,
                                    feat: f,
                                  ));
                                }
                              }
                            }

                            final heroGoal = bp.goal.trim().isNotEmpty
                                ? bp.goal.trim()
                                : ((bp.lastAgentReply != null &&
                                        bp.lastAgentReply!.trim().isNotEmpty)
                                    ? bp.lastAgentReply!.trim()
                                    : 'Advance $nextVer with the active features and upgrades below.');

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: bgSurface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderSubtle),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 1. Unboxed Hero Header (Goal & Done When)
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: accentCyan,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'AGENT ARCHITECTURAL RECOMMENDATION · ${nextVer.toUpperCase()} (${widget.workbench.activePhaseBadgeLabel})',
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.6,
                                                  color: textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: bgRecessed,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border:
                                              Border.all(color: borderSubtle),
                                        ),
                                        child: Text(
                                          '${upgradeCount + newCount} Active Changes · ${bp.totalIncludedHours}h',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    heroGoal,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      height: 1.4,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary,
                                    ),
                                  ),
                                  if (bp.doneWhen.trim().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '✓ DONE WHEN → ',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: accentEmerald,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            bp.doneWhen.trim(),
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              height: 1.35,
                                              color: textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 14),

                                  // 2. Unified Vertical Diagnostic Ledger (Built -> Lacking Now -> Next in v0.X)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: bgRecessed,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: borderSubtle),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (builtChips.isNotEmpty) ...[
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 126,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 2,
                                                        ),
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: textMuted,
                                                        ),
                                                        children: [
                                                          TextSpan(
                                                            text: '✓ ',
                                                            style: TextStyle(
                                                              color:
                                                                  accentEmerald,
                                                            ),
                                                          ),
                                                          TextSpan(
                                                            text:
                                                                'BUILT (≤$prevVer)',
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Wrap(
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    children: [
                                                      for (final chip
                                                          in builtChips.take(8))
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 3,
                                                              ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: bgSurface,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                            border: Border.all(
                                                              color:
                                                                  borderSubtle,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            '✓ $chip',
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 11.5,
                                                              color:
                                                                  textSecondary,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: borderSubtle,
                                          ),
                                        ],
                                        if (rawGaps.isNotEmpty) ...[
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 126,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 2,
                                                        ),
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: textMuted,
                                                        ),
                                                        children: [
                                                          TextSpan(
                                                            text: '⚠ ',
                                                            style: TextStyle(
                                                              color:
                                                                  accentAmber,
                                                            ),
                                                          ),
                                                          const TextSpan(
                                                            text: 'LACKING NOW',
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      for (int gIdx = 0;
                                                          gIdx <
                                                              rawGaps
                                                                  .take(5)
                                                                  .length;
                                                          gIdx++)
                                                        Builder(
                                                          builder: (context) {
                                                            var gapText =
                                                                rawGaps[gIdx];
                                                            String? epicTag;
                                                            final beatMatch =
                                                                RegExp(
                                                              r'^(?:Beat|Epic)[\s\-–—]*0*(\d+)\s*(?:\(([^)]+)\))?\s*[:\-–—]?\s*(.+)$',
                                                              caseSensitive:
                                                                  false,
                                                            ).firstMatch(
                                                              gapText,
                                                            );
                                                            final eCodeMatch =
                                                                RegExp(
                                                              r'^(E\d+)\s*[:\-–—]?\s*(.+)$',
                                                              caseSensitive:
                                                                  false,
                                                            ).firstMatch(
                                                              gapText,
                                                            );
                                                            if (beatMatch !=
                                                                null) {
                                                              final num = int
                                                                      .tryParse(
                                                                        beatMatch
                                                                            .group(
                                                                              1,
                                                                            )!,
                                                                      ) ??
                                                                  1;
                                                              epicTag =
                                                                  'E${num.toString().padLeft(2, '0')}';
                                                              final beatName =
                                                                  beatMatch
                                                                      .group(2)
                                                                      ?.trim();
                                                              final rest =
                                                                  beatMatch
                                                                      .group(3)!
                                                                      .trim();
                                                              gapText =
                                                                  (beatName !=
                                                                              null &&
                                                                          beatName
                                                                              .isNotEmpty)
                                                                      ? '$beatName — $rest'
                                                                      : rest;
                                                            } else if (eCodeMatch !=
                                                                null) {
                                                              epicTag =
                                                                  eCodeMatch
                                                                      .group(1)!
                                                                      .toUpperCase();
                                                              gapText =
                                                                  eCodeMatch
                                                                      .group(2)!
                                                                      .trim();
                                                            }
                                                            return Padding(
                                                              padding: EdgeInsets.only(
                                                                bottom: gIdx +
                                                                            1 <
                                                                        rawGaps
                                                                            .take(
                                                                              5,
                                                                            )
                                                                            .length
                                                                    ? 6
                                                                    : 0,
                                                              ),
                                                              child: Row(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  if (epicTag !=
                                                                      null) ...[
                                                                    Container(
                                                                      padding: const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            5,
                                                                        vertical:
                                                                            1.5,
                                                                      ),
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color:
                                                                            bgSurface,
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              3,
                                                                            ),
                                                                        border: Border.all(
                                                                          color:
                                                                              borderSubtle,
                                                                        ),
                                                                      ),
                                                                      child:
                                                                          Text(
                                                                        epicTag,
                                                                        style: GoogleFonts
                                                                            .jetBrainsMono(
                                                                          fontSize:
                                                                              9.5,
                                                                          fontWeight:
                                                                              FontWeight.w700,
                                                                          color:
                                                                              textMuted,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 7,
                                                                    ),
                                                                  ] else ...[
                                                                    Text(
                                                                      '• ',
                                                                      style: GoogleFonts
                                                                          .jetBrainsMono(
                                                                        fontSize:
                                                                            11,
                                                                        color:
                                                                            textMuted,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                  Expanded(
                                                                    child: Text(
                                                                      gapText,
                                                                      style: GoogleFonts
                                                                          .inter(
                                                                        fontSize:
                                                                            12,
                                                                        height:
                                                                            1.35,
                                                                        color:
                                                                            textPrimary,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: borderSubtle,
                                          ),
                                        ],
                                        if (nextRows.isNotEmpty ||
                                            bp.beats.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 126,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 5,
                                                        ),
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: textPrimary,
                                                        ),
                                                        children: [
                                                          TextSpan(
                                                            text: '✦ ',
                                                            style: TextStyle(
                                                              color: accentCyan,
                                                            ),
                                                          ),
                                                          TextSpan(
                                                            text:
                                                                'NEXT IN ${nextVer.toUpperCase()}',
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      for (int nIdx = 0;
                                                          nIdx <
                                                              nextRows.length;
                                                          nIdx++)
                                                        Builder(
                                                          builder: (context) {
                                                            final row =
                                                                nextRows[nIdx];
                                                            final f = row.feat;
                                                            final isUpg = f
                                                                    .lifecycle ==
                                                                FeatureLifecycleStatus
                                                                    .upgrade;
                                                            final isInc =
                                                                f.included;
                                                            final badgeColor = !isInc
                                                                ? textMuted
                                                                : (isUpg
                                                                    ? accentAmber
                                                                    : accentEmerald);
                                                            final cleanGoal = f
                                                                .goal
                                                                .trim()
                                                                .replaceAll(
                                                                  RegExp(
                                                                    r'\.$',
                                                                  ),
                                                                  '',
                                                                );
                                                            return Padding(
                                                              padding: EdgeInsets.only(
                                                                bottom: nIdx +
                                                                            1 <
                                                                        nextRows
                                                                            .length
                                                                    ? 6
                                                                    : 0,
                                                              ),
                                                              child: InkWell(
                                                                key: ValueKey(
                                                                  'progressive_toggle_feat_${f.id}',
                                                                ),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                          5,
                                                                        ),
                                                                onTap: () {
                                                                  if (f.lifecycle ==
                                                                      FeatureLifecycleStatus
                                                                          .newFeature) {
                                                                    widget
                                                                        .workbench
                                                                        .toggleProposedFeatureScope(
                                                                      row.beatId,
                                                                      f.id,
                                                                      !f.included,
                                                                    );
                                                                  } else {
                                                                    widget
                                                                        .workbench
                                                                        .toggleProposedFeatureUpgradeOrStable(
                                                                      row.beatId,
                                                                      f.id,
                                                                    );
                                                                  }
                                                                  _rebuild(
                                                                    () {},
                                                                  );
                                                                },
                                                                child:
                                                                    Container(
                                                                  padding:
                                                                      const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            10,
                                                                        vertical:
                                                                            6,
                                                                      ),
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color:
                                                                        bgSurface,
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          5,
                                                                        ),
                                                                    border:
                                                                        Border.all(
                                                                      color:
                                                                          borderSubtle,
                                                                    ),
                                                                  ),
                                                                  child: Row(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .spaceBetween,
                                                                    children: [
                                                                      Expanded(
                                                                        child:
                                                                            Row(
                                                                          children: [
                                                                            Container(
                                                                              padding: const EdgeInsets.symmetric(
                                                                                horizontal:
                                                                                    5,
                                                                                vertical:
                                                                                    1.5,
                                                                              ),
                                                                              decoration:
                                                                                  BoxDecoration(
                                                                                color: badgeColor.withValues(
                                                                                  alpha: 0.14,
                                                                                ),
                                                                                borderRadius:
                                                                                    BorderRadius.circular(
                                                                                      3,
                                                                                    ),
                                                                                border: Border.all(
                                                                                  color: badgeColor.withValues(
                                                                                    alpha: 0.35,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              child:
                                                                                  Text(
                                                                                !isInc
                                                                                    ? 'DEFERRED'
                                                                                    : (isUpg ? '↻ UPGRADE' : '+ NEW'),
                                                                                style: GoogleFonts.jetBrainsMono(
                                                                                  fontSize: 9,
                                                                                  fontWeight: FontWeight.w800,
                                                                                  color: badgeColor,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            const SizedBox(
                                                                              width:
                                                                                  8,
                                                                            ),
                                                                            Flexible(
                                                                              child:
                                                                                  RichText(
                                                                                maxLines:
                                                                                    1,
                                                                                overflow:
                                                                                    TextOverflow.ellipsis,
                                                                                text: TextSpan(
                                                                                  style: GoogleFonts.inter(
                                                                                    fontSize: 12,
                                                                                    color: isInc ? textPrimary : textMuted,
                                                                                  ),
                                                                                  children: [
                                                                                    TextSpan(
                                                                                      text: f.title,
                                                                                      style: const TextStyle(
                                                                                        fontWeight: FontWeight.w700,
                                                                                      ),
                                                                                    ),
                                                                                    if (cleanGoal.isNotEmpty)
                                                                                      TextSpan(
                                                                                        text: ' — $cleanGoal',
                                                                                        style: TextStyle(
                                                                                          color: isInc ? textSecondary : textMuted,
                                                                                        ),
                                                                                      ),
                                                                                  ],
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            10,
                                                                      ),
                                                                        Text(
                                                                          '${row.epicCode} · ${isInc ? f.estimatedHours : 0}h',
                                                                          style: GoogleFonts
                                                                              .jetBrainsMono(
                                                                            fontSize:
                                                                                10,
                                                                            fontWeight:
                                                                                FontWeight.w600,
                                                                            color:
                                                                                textMuted,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        if (bp.beats
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          if (_addingFeatureToBeatId ==
                                                              null)
                                                            Align(
                                                              alignment: Alignment
                                                                  .centerLeft,
                                                              child: InkWell(
                                                                key: ValueKey(
                                                                  'progressive_add_feat_btn_${bp.beats.first.id}',
                                                                ),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                          4,
                                                                        ),
                                                                onTap: () {
                                                                  _rebuild(() {
                                                                    _addingFeatureToBeatId =
                                                                        bp
                                                                            .beats
                                                                            .first
                                                                            .id;
                                                                    _progressiveNewFeatCtrl
                                                                        .clear();
                                                                  });
                                                                },
                                                                child: Padding(
                                                                  padding:
                                                                      const EdgeInsets.symmetric(
                                                                        vertical:
                                                                            2,
                                                                      ),
                                                                  child: Text(
                                                                    '+ Add Custom Feature...',
                                                                    style: GoogleFonts
                                                                        .jetBrainsMono(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      color:
                                                                          textMuted,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            )
                                                          else
                                                            Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .stretch,
                                                              children: [
                                                                if (bp.beats
                                                                        .length >
                                                                    1)
                                                                  Padding(
                                                                    padding:
                                                                        const EdgeInsets.only(
                                                                      bottom: 6,
                                                                    ),
                                                                    child: Wrap(
                                                                      spacing:
                                                                          6,
                                                                      runSpacing:
                                                                          4,
                                                                      children: [
                                                                        for (int bIdx =
                                                                                0;
                                                                            bIdx <
                                                                                bp.beats.length;
                                                                            bIdx++)
                                                                          Builder(
                                                                            builder:
                                                                                (context) {
                                                                              final b = bp.beats[bIdx];
                                                                              final isSelBeat = _addingFeatureToBeatId == b.id;
                                                                              final code = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
                                                                              return InkWell(
                                                                                key: ValueKey('progressive_add_feat_target_epic_${b.id}'),
                                                                                borderRadius: BorderRadius.circular(4),
                                                                                onTap: () {
                                                                                  _rebuild(() {
                                                                                    _addingFeatureToBeatId = b.id;
                                                                                  });
                                                                                },
                                                                                child: Container(
                                                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                                  decoration: BoxDecoration(
                                                                                    color: isSelBeat ? accentCyan.withValues(alpha: 0.16) : bgSurface,
                                                                                    borderRadius: BorderRadius.circular(4),
                                                                                    border: Border.all(
                                                                                      color: isSelBeat ? accentCyan.withValues(alpha: 0.55) : borderSubtle,
                                                                                    ),
                                                                                  ),
                                                                                  child: Text(
                                                                                    '$code · ${b.title}',
                                                                                    style: GoogleFonts.jetBrainsMono(
                                                                                      fontSize: 9.5,
                                                                                      fontWeight: isSelBeat ? FontWeight.w800 : FontWeight.w600,
                                                                                      color: isSelBeat ? accentCyan : textMuted,
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                              );
                                                                            },
                                                                          ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                Row(
                                                                  children: [
                                                                    Expanded(
                                                                      child:
                                                                          TextField(
                                                                        controller:
                                                                            _progressiveNewFeatCtrl,
                                                                        autofocus:
                                                                            true,
                                                                        style: GoogleFonts
                                                                            .inter(
                                                                          fontSize:
                                                                              12,
                                                                          color:
                                                                              textPrimary,
                                                                        ),
                                                                        decoration:
                                                                            InputDecoration(
                                                                          hintText:
                                                                              'New $nextVer feature title...',
                                                                          hintStyle:
                                                                              GoogleFonts.inter(
                                                                            fontSize:
                                                                                11.5,
                                                                            color:
                                                                                textMuted,
                                                                          ),
                                                                          filled:
                                                                              true,
                                                                          fillColor:
                                                                              bgSurface,
                                                                          isDense:
                                                                              true,
                                                                          contentPadding:
                                                                              const EdgeInsets.symmetric(
                                                                            horizontal:
                                                                                10,
                                                                            vertical:
                                                                                7,
                                                                          ),
                                                                          border:
                                                                              OutlineInputBorder(
                                                                            borderRadius:
                                                                                BorderRadius.circular(
                                                                                  5,
                                                                                ),
                                                                            borderSide:
                                                                                BorderSide(
                                                                              color:
                                                                                  borderSubtle,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        onSubmitted:
                                                                            (val) {
                                                                          if (val
                                                                              .trim()
                                                                              .isEmpty) {
                                                                            return;
                                                                          }
                                                                          widget
                                                                              .workbench
                                                                              .addCustomFeatureToProposedBeat(
                                                                            _addingFeatureToBeatId!,
                                                                            val.trim(),
                                                                          );
                                                                          _rebuild(
                                                                            () {
                                                                              _addingFeatureToBeatId =
                                                                                  null;
                                                                            },
                                                                          );
                                                                        },
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 6,
                                                                    ),
                                                                    TextButton(
                                                                      onPressed:
                                                                          () {
                                                                        final val =
                                                                            _progressiveNewFeatCtrl
                                                                                .text
                                                                                .trim();
                                                                        if (val
                                                                            .isNotEmpty) {
                                                                          widget
                                                                              .workbench
                                                                              .addCustomFeatureToProposedBeat(
                                                                            _addingFeatureToBeatId!,
                                                                            val,
                                                                          );
                                                                        }
                                                                        _rebuild(
                                                                          () {
                                                                            _addingFeatureToBeatId =
                                                                                null;
                                                                          },
                                                                        );
                                                                      },
                                                                      child: Text(
                                                                        'Add',
                                                                        style: GoogleFonts
                                                                            .jetBrainsMono(
                                                                          fontSize:
                                                                              10.5,
                                                                          fontWeight:
                                                                              FontWeight
                                                                                  .w700,
                                                                          color:
                                                                              accentCyan,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                  // 3. Vertical Radio-Style Strategic Direction Selector
                                  Text(
                                    (dynamicQuestion?.question ??
                                            'STRATEGIC DIRECTION (SELECT TO RE-ARCHITECT ${nextVer.toUpperCase()})')
                                        .toUpperCase(),
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      color: textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (int oIdx = 0;
                                          oIdx < dynamicOptions.length;
                                          oIdx++)
                                        Builder(
                                          builder: (context) {
                                            final rawOpt = dynamicOptions[oIdx];
                                            final isSelected =
                                                _selectedProgressiveTrackIndex ==
                                                oIdx;
                                            final isRec = rawOpt
                                                .toLowerCase()
                                                .startsWith('(recommended)');
                                            final stripped = rawOpt
                                                .replaceFirst(
                                                  RegExp(
                                                    r'^\(recommended\)\s*',
                                                    caseSensitive: false,
                                                  ),
                                                  '',
                                                )
                                                .trim();
                                            final colonIdx =
                                                stripped.indexOf(':');
                                            final optTitle = colonIdx > 0
                                                ? stripped
                                                    .substring(0, colonIdx)
                                                    .trim()
                                                : stripped;
                                            final optDesc = colonIdx > 0
                                                ? stripped
                                                    .substring(colonIdx + 1)
                                                    .trim()
                                                : '';
                                            return Padding(
                                              padding: EdgeInsets.only(
                                                bottom: oIdx + 1 <
                                                        dynamicOptions.length
                                                    ? 6
                                                    : 0,
                                              ),
                                              child: InkWell(
                                                key: ValueKey(
                                                  'progressive_preset_chip_$oIdx',
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(7),
                                                onTap: widget
                                                        .workbench
                                                        .isAgentBusy
                                                    ? null
                                                    : () async {
                                                        final prevIdx =
                                                            _selectedProgressiveTrackIndex;
                                                        _rebuild(() {
                                                          _selectedProgressiveTrackIndex =
                                                              oIdx;
                                                        });
                                                        if (oIdx > 0) {
                                                          await submitDirective(
                                                            'Re-architect $nextVer around this strategic option: $rawOpt',
                                                          );
                                                        } else if (prevIdx !=
                                                            0) {
                                                          widget.workbench
                                                              .restoreInitialProgressiveDraftBlueprint();
                                                          _rebuild(() {});
                                                        }
                                                      },
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 9,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? bgRecessed
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          7,
                                                        ),
                                                    border: Border.all(
                                                      color: isSelected
                                                          ? accentCyan
                                                              .withValues(
                                                                alpha: 0.65,
                                                              )
                                                          : borderSubtle,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 1,
                                                            ),
                                                        child: Text(
                                                          isSelected
                                                              ? '●'
                                                              : '○',
                                                          style: GoogleFonts
                                                              .jetBrainsMono(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: isSelected
                                                                ? accentCyan
                                                                : textMuted,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Flexible(
                                                                  child: Text(
                                                                    optTitle,
                                                                    style: GoogleFonts
                                                                        .inter(
                                                                      fontSize:
                                                                          12,
                                                                      fontWeight: isSelected
                                                                          ? FontWeight.w700
                                                                          : FontWeight.w600,
                                                                      color: isSelected
                                                                          ? textPrimary
                                                                          : textSecondary,
                                                                    ),
                                                                  ),
                                                                ),
                                                                if (isRec) ...[
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          6,
                                                                      vertical:
                                                                          1.5,
                                                                    ),
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: accentCyan.withValues(
                                                                        alpha:
                                                                            0.14,
                                                                      ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            4,
                                                                          ),
                                                                    ),
                                                                    child: Text(
                                                                      'Recommended',
                                                                      style: GoogleFonts
                                                                          .jetBrainsMono(
                                                                        fontSize:
                                                                            9,
                                                                        fontWeight:
                                                                            FontWeight.w700,
                                                                        color:
                                                                            accentCyan,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ],
                                                            ),
                                                            if (optDesc
                                                                .isNotEmpty) ...[
                                                              const SizedBox(
                                                                height: 2,
                                                              ),
                                                              Text(
                                                                optDesc,
                                                                style: GoogleFonts
                                                                    .inter(
                                                                  fontSize: 11.5,
                                                                  height: 1.35,
                                                                  color:
                                                                      textMuted,
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const ValueKey(
                                      'progressive_release_prompt_input',
                                    ),
                                    controller: _progressiveDirectiveCtrl,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      color: textPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          'Want to adjust the Agent\'s $nextVer recommendation? Tell the Agent what to swap or add...',
                                      hintStyle: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: textMuted,
                                      ),
                                      filled: true,
                                      fillColor: bgRecessed,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 11,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide:
                                            BorderSide(color: borderSubtle),
                                      ),
                                    ),
                                    onSubmitted: (val) async {
                                      if (val.trim().isEmpty) return;
                                      _progressiveDirectiveCtrl.clear();
                                      await submitDirective(val);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  key: const ValueKey(
                                    'progressive_release_ask_agent_btn',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: accentCyan,
                                    backgroundColor: bgRecessed,
                                    side: BorderSide(
                                      color: accentCyan.withValues(alpha: 0.5),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: widget.workbench.isAgentBusy
                                      ? null
                                      : () async {
                                          final text = _progressiveDirectiveCtrl
                                              .text
                                              .trim();
                                          if (text.isEmpty) return;
                                          _progressiveDirectiveCtrl.clear();
                                          await submitDirective(text);
                                        },
                                  child: Text(
                                    'Ask Agent ✦',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                        if (bp.explicitExclusions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: bgSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderSubtle),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DEFERRED BACKLOG (${bp.explicitExclusions.length}) — CLICK TO PROMOTE INTO ${nextVer.toUpperCase()}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (int eIdx = 0;
                                        eIdx < bp.explicitExclusions.length;
                                        eIdx++)
                                      InkWell(
                                        key: ValueKey(
                                          'promote_exclusion_chip_$eIdx',
                                        ),
                                        borderRadius: BorderRadius.circular(5),
                                        onTap: () {
                                          widget.workbench
                                              .promoteExclusionToNextRelease(
                                            bp.explicitExclusions[eIdx],
                                          );
                                          _rebuild(() {});
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: bgRecessed,
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            border: Border.all(
                                              color: accentAmber.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            '+ Promote: ${bp.explicitExclusions[eIdx]}',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: accentAmber,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReleaseShippedSummaryModal(BuildContext context, TierDocument rel) {
    final retro = widget.workbench.buildActiveReleaseRetrospective();
    final beats = widget.workbench.activeReleaseBeats;
    final activeRelVer = widget.workbench.activeReleaseVersionTag;
    final allFeats = <TierDocument>[
      for (final b in beats) ...widget.workbench.featuresForBeat(b.id),
    ];
    int totalTasks = 0;
    int totalStepsDone = 0;
    for (final f in allFeats) {
      final allStates = FeatureStateNode.getStatesForDocument(f);
      final activeStates = allStates
          .where((s) => s.releaseVersion == activeRelVer)
          .toList();
      final states = activeStates.isNotEmpty ? activeStates : allStates;
      for (final s in states) {
        totalTasks += s.totalChecklistCount;
        for (final t in s.checklist) {
          totalStepsDone += t.children.isNotEmpty
              ? t.children.where((c) => c.completed).length
              : (t.completed ? 6 : 0);
        }
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: accentEmerald.withValues(alpha: 0.6)),
        ),
        title: Row(
          children: [
            Icon(Icons.rocket_launch_rounded, color: accentEmerald, size: 18),
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
                'Every Feature, Build Task, and Step across your Core Loop has been completed and verified:',
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
                    Column(
                      children: [
                        Text(
                          '${beats.length}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: accentEmerald,
                          ),
                        ),
                        Text(
                          'CORE EPICS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '${allFeats.length}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: accentAmber,
                          ),
                        ),
                        Text(
                          'FEATURES',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '$totalTasks',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: accentEmerald,
                          ),
                        ),
                        Text(
                          'BUILD TASKS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '$totalStepsDone',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          'STEPS DONE',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
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
                        fontWeight: FontWeight.w800,
                        color: accentAmber,
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
                    if (retro.carryoverFeatureTitles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '• Auto-Carryover to next Release: ${retro.carryoverFeatureTitles.join(", ")}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: accentAmber,
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
              backgroundColor: focalAccent,
              foregroundColor: focalAccentFg,
              elevation: 0,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _showProgressiveNextReleaseModal(context);
            },
            icon: const Icon(Icons.auto_awesome_rounded, size: 15),
            label: Text(
              '+ New Release (${widget.workbench.nextProgressiveVersionLabel}) ✦',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
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
                        RegExp(r'^Goal:\s*', caseSensitive: false),
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
                        RegExp(r'^Goal:\s*', caseSensitive: false),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: bgRecessed,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: borderSubtle),
                      ),
                      child: Text(
                        '$phaseBadge · $verTag',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: accentCyan,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$verTag Release Plan — $displayName',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (selectableReleases.length > 1) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
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
                              borderRadius: BorderRadius.circular(5),
                              onTap: () {
                                setModalState(() {
                                  selectedRel = r;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? accentCyan.withValues(alpha: 0.14)
                                      : bgRecessed,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: isSel
                                        ? accentCyan.withValues(alpha: 0.55)
                                        : borderSubtle,
                                  ),
                                ),
                                child: Text(
                                  '$rVer · $rPhase',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: isSel
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isSel ? accentCyan : textSecondary,
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
                            fontWeight: FontWeight.w800,
                            color: row.badge.startsWith('+')
                                ? accentEmerald
                                : accentAmber,
                          ),
                        ),
                      ],
                    ),
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
}
