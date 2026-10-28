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
                          : 'Recommended Scope for $nextVer',
                      style: AppTheme.displayFont(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                        '${bp?.totalIncludedHours ?? 0}h in $nextVer · ${upgradeCount + newCount} Active Features',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: accentEmerald,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: accentCyan.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
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
                        ),
                      ],

                      // Section 1: Proactive Agent Architectural Recommendation (gemini-4-argon)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: bgSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: accentCyan.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.psychology_rounded,
                                  size: 16,
                                  color: accentCyan,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '✦ AGENT ARCHITECTURAL RECOMMENDATION FOR ${nextVer.toUpperCase()} (GEMINI-4-ARGON)',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                      color: accentCyan,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              (bp?.lastAgentReply != null &&
                                      bp!.lastAgentReply!.trim().isNotEmpty)
                                  ? bp.lastAgentReply!.trim()
                                  : 'Based on your completed $prevVer features and Stage 1 Design Pillars, $nextVer focuses on the active deliverables below.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                            if (bp != null && bp.goal.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
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
                                      'Goal: ${bp.goal.trim()}',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: textSecondary,
                                      ),
                                    ),
                                    if (bp.doneWhen.trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Done When: ${bp.doneWhen.trim()}',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: accentEmerald,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              dynamicQuestion?.question ??
                                  'AI-Synthesized Strategic Focus for $nextVer (Click an alternative to re-architect $nextVer):',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (int oIdx = 0;
                                    oIdx < dynamicOptions.length;
                                    oIdx++)
                                  Builder(
                                    builder: (context) {
                                      final opt = dynamicOptions[oIdx];
                                      final isSelected =
                                          _selectedProgressiveTrackIndex == oIdx;
                                      return InkWell(
                                        key: ValueKey(
                                          'progressive_preset_chip_$oIdx',
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: widget.workbench.isAgentBusy
                                            ? null
                                            : () async {
                                                _rebuild(() {
                                                  _selectedProgressiveTrackIndex =
                                                      oIdx;
                                                });
                                                if (oIdx > 0) {
                                                  await submitDirective(
                                                    'Re-architect $nextVer around this strategic option: $opt',
                                                  );
                                                }
                                              },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? accentCyan.withValues(
                                                    alpha: 0.12,
                                                  )
                                                : bgRecessed,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isSelected
                                                  ? accentCyan
                                                  : borderSubtle,
                                            ),
                                          ),
                                          child: Text(
                                            opt,
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
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
                      ),

                      if (bp != null) ...[
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                '✦ RECOMMENDED ${nextVer.toUpperCase()} ACTIVE SCOPE (ONLY WHAT YOU WILL BUILD IN ${nextVer.toUpperCase()})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Completed $prevVer features are hidden',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: accentEmerald,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) ...[
                          Builder(
                            builder: (context) {
                              final beat = bp.beats[bIdx];
                              final activeFeatsInBeat = beat.features
                                  .where(
                                    (f) =>
                                        f.lifecycle !=
                                        FeatureLifecycleStatus.stable,
                                  )
                                  .toList();
                              if (activeFeatsInBeat.isEmpty &&
                                  _addingFeatureToBeatId != beat.id) {
                                return const SizedBox.shrink();
                              }
                              final beatTitle =
                                  _formatOutlineBeatDisplayTitle(beat.title);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: bgSurface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderSubtle),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: bgRecessed,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: borderSubtle,
                                                  ),
                                                ),
                                                child: Text(
                                                  'E${(bIdx + 1).toString().padLeft(2, '0')}',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: accentCyan,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  beatTitle.toUpperCase(),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: textPrimary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              '+${beat.totalIncludedHours}h in $nextVer',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: accentAmber,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            InkWell(
                                              key: ValueKey(
                                                'progressive_add_feat_btn_${beat.id}',
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              onTap: () {
                                                _rebuild(() {
                                                  if (_addingFeatureToBeatId ==
                                                      beat.id) {
                                                    _addingFeatureToBeatId =
                                                        null;
                                                  } else {
                                                    _addingFeatureToBeatId =
                                                        beat.id;
                                                    _progressiveNewFeatCtrl
                                                        .clear();
                                                  }
                                                });
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: bgRecessed,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: accentEmerald
                                                        .withValues(alpha: 0.4),
                                                  ),
                                                ),
                                                child: Text(
                                                  '+ Add Feature',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: accentEmerald,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (_addingFeatureToBeatId == beat.id) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller:
                                                  _progressiveNewFeatCtrl,
                                              autofocus: true,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: textPrimary,
                                              ),
                                              decoration: InputDecoration(
                                                hintText:
                                                    'New $nextVer feature for $beatTitle (e.g., Shield Drone)...',
                                                hintStyle: GoogleFonts.inter(
                                                  fontSize: 11.5,
                                                  color: textMuted,
                                                ),
                                                filled: true,
                                                fillColor: bgRecessed,
                                                isDense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 8,
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                  borderSide: BorderSide(
                                                    color: borderSubtle,
                                                  ),
                                                ),
                                              ),
                                              onSubmitted: (val) {
                                                if (val.trim().isEmpty) return;
                                                widget.workbench
                                                    .addCustomFeatureToProposedBeat(
                                                  beat.id,
                                                  val.trim(),
                                                );
                                                _rebuild(() {
                                                  _addingFeatureToBeatId = null;
                                                });
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: accentEmerald,
                                              foregroundColor:
                                                  const Color(0xFF052E16),
                                              elevation: 0,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 9,
                                              ),
                                            ),
                                            onPressed: () {
                                              final val =
                                                  _progressiveNewFeatCtrl.text
                                                      .trim();
                                              if (val.isEmpty) return;
                                              widget.workbench
                                                  .addCustomFeatureToProposedBeat(
                                                beat.id,
                                                val,
                                              );
                                              _rebuild(() {
                                                _addingFeatureToBeatId = null;
                                              });
                                            },
                                            child: Text(
                                              'Add',
                                              style: GoogleFonts.inter(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    for (final feat in activeFeatsInBeat)
                                      Builder(
                                        builder: (context) {
                                          final isNew = feat.lifecycle ==
                                              FeatureLifecycleStatus.newFeature;
                                          final isUpgrade = feat.lifecycle ==
                                              FeatureLifecycleStatus.upgrade;
                                          final displayTitle =
                                              _formatOutlineFeatureDisplayTitle(
                                            feat.title,
                                            beat.title,
                                            beatIndex: bIdx,
                                          );
                                          return InkWell(
                                            key: ValueKey(
                                              'progressive_toggle_feat_${feat.id}',
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            onTap: () {
                                              if (isNew) {
                                                widget.workbench
                                                    .toggleProposedFeatureScope(
                                                  beat.id,
                                                  feat.id,
                                                  !feat.included,
                                                );
                                              } else {
                                                widget.workbench
                                                    .toggleProposedFeatureUpgradeOrStable(
                                                  beat.id,
                                                  feat.id,
                                                );
                                              }
                                              _rebuild(() {});
                                            },
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: bgRecessed,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: isNew
                                                      ? (feat.included
                                                          ? accentEmerald
                                                              .withValues(
                                                              alpha: 0.45,
                                                            )
                                                          : borderSubtle)
                                                      : (isUpgrade
                                                          ? accentAmber
                                                              .withValues(
                                                              alpha: 0.45,
                                                            )
                                                          : borderSubtle),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    isNew
                                                        ? (feat.included
                                                            ? Icons
                                                                .add_box_rounded
                                                            : Icons
                                                                .check_box_outline_blank_rounded)
                                                        : Icons
                                                            .autorenew_rounded,
                                                    size: 16,
                                                    color: isNew
                                                        ? (feat.included
                                                            ? accentEmerald
                                                            : textMuted)
                                                        : accentAmber,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          displayTitle,
                                                          style:
                                                              GoogleFonts.inter(
                                                            fontSize: 12.5,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: (isNew &&
                                                                    !feat
                                                                        .included)
                                                                ? textMuted
                                                                : textPrimary,
                                                          ),
                                                        ),
                                                        if (feat.goal
                                                            .trim()
                                                            .isNotEmpty)
                                                          Text(
                                                            isUpgrade
                                                                ? 'Upgrade in $nextVer: ${feat.checkpoints.isNotEmpty ? feat.checkpoints.first.title : feat.goal.trim()}'
                                                                : 'New in $nextVer: ${feat.goal.trim()}',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 11,
                                                              color: textMuted,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: bgSurface,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                      border: Border.all(
                                                        color: borderSubtle,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      isNew
                                                          ? (feat.included
                                                              ? '+ NEW · +${feat.activeDeltaHours}h'
                                                              : 'DEFERRED · 0h')
                                                          : '↻ UPGRADE · +${feat.activeDeltaHours}h',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: isNew
                                                            ? (feat.included
                                                                ? accentEmerald
                                                                : textMuted)
                                                            : accentAmber,
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
                                ),
                              );
                            },
                          ),
                        ],
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

}
