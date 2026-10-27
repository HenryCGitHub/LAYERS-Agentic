part of 'release_workbench_screen.dart';

extension _WorkbenchModalsExt on _ReleaseWorkbenchScreenState {
  Future<void> _showProgressiveNextReleaseModal(BuildContext context) async {
    final prevReleaseId = widget.workbench.activeReleaseId;
    final prevPhase = widget.workbench.currentPhase;
    final activeBeats = List<TierDocument>.from(
      widget.workbench.activeReleaseBeats,
    );

        _rebuild(() {
      _isProgressiveModalOpen = true;
    });
    ReleaseBlueprint? preparedBp;
    try {
      preparedBp = await widget.workbench.prepareProgressiveNextReleaseDraft();
    } finally {
      if (mounted) {
                _rebuild(() {});
      }
    }
    if (!context.mounted || preparedBp == null) {
            if (mounted) {
                _rebuild(() {
          _isProgressiveModalOpen = false;
        });
      } else {
        _isProgressiveModalOpen = false;
      }
      widget.workbench.restoreActiveReleaseAfterCancel(prevReleaseId, prevPhase);
      return;
    }

    final directiveCtrl = TextEditingController();
    final b1Title = activeBeats.isNotEmpty
        ? _formatOutlineBeatDisplayTitle(activeBeats[0].title)
        : 'Core Controls';
    final b2Title = activeBeats.length > 1
        ? _formatOutlineBeatDisplayTitle(activeBeats[1].title)
        : b1Title;
    final b3Title = activeBeats.length > 2
        ? _formatOutlineBeatDisplayTitle(activeBeats[2].title)
        : b2Title;

    final aiDirectionPresets = <({String label, String prompt})>[
      (
        label: '⚡ Deepen $b1Title',
        prompt: 'Upgrade $b1Title in Beat 1 with deeper mechanics & responsiveness',
      ),
      (
        label: '🎯 Expand $b2Title',
        prompt: 'Add a new playable challenge mechanic to Beat 2 ($b2Title)',
      ),
      (
        label: '📈 Add $b3Title Progression',
        prompt: 'Add progression & reward choices to Beat 3 ($b3Title)',
      ),
      (
        label: '✨ Polish Game Feel & HUD',
        prompt: 'Add visual/audio feedback cues and HUD polish across Beat 2 ($b2Title)',
      ),
    ];

    bool isModalBusy = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final bp = widget.workbench.releaseBlueprint;
            final nextVer = bp?.releaseVersionTag ??
                widget.workbench.nextProgressiveVersionLabel;
            final upgradeFeats = <({int beatIdx, ProposedBeatBlueprint beat, ProposedFeatureBlueprint feat})>[];
            final newFeats = <({int beatIdx, ProposedBeatBlueprint beat, ProposedFeatureBlueprint feat})>[];
            if (bp != null) {
              for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) {
                final b = bp.beats[bIdx];
                for (final f in b.features) {
                  if (f.lifecycle == FeatureLifecycleStatus.upgrade) {
                    upgradeFeats.add((beatIdx: bIdx, beat: b, feat: f));
                  } else if (f.lifecycle == FeatureLifecycleStatus.newFeature) {
                    newFeats.add((beatIdx: bIdx, beat: b, feat: f));
                  }
                }
              }
            }

            Future<void> submitDirective(String promptText) async {
              final cleanPrompt = promptText.trim();
              if (cleanPrompt.isEmpty || isModalBusy) return;
              setModalState(() {
                isModalBusy = true;
              });
              try {
                await widget.workbench.sendReleasePlanChatMessage(cleanPrompt);
              } finally {
                if (ctx.mounted) {
                  setModalState(() {
                    isModalBusy = false;
                  });
                }
              }
            }

            return AlertDialog(
              key: const ValueKey('progressive_next_release_modal'),
              backgroundColor: bgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: borderBright),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: accentCyan,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Progressive AI Release · $nextVer',
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${bp?.totalIncludedHours ?? 0}h · ${bp?.totalIncludedFeatures ?? 0} features',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accentEmerald,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isModalBusy || widget.workbench.isAgentBusy) ...[
                        LinearProgressIndicator(
                          color: accentCyan,
                          backgroundColor: bgRecessed,
                          minHeight: 2,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '✦ Agent is updating $nextVer scope & features...',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: accentCyan,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        'The Agent analyzed your live game tree and recommends what to Upgrade (UPGRADE) and what New Systems (NEW) to add in $nextVer:',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (int pIdx = 0; pIdx < aiDirectionPresets.length; pIdx++)
                            InkWell(
                              key: ValueKey('progressive_preset_chip_$pIdx'),
                              borderRadius: BorderRadius.circular(5),
                              onTap: (isModalBusy || widget.workbench.isAgentBusy)
                                  ? null
                                  : () => submitDirective(
                                        aiDirectionPresets[pIdx].prompt,
                                      ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: bgRecessed,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: accentCyan.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  aiDirectionPresets[pIdx].label,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: accentCyan,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey(
                                'progressive_release_prompt_input',
                              ),
                              controller: directiveCtrl,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Tell the Agent what direction to take in $nextVer (e.g., "Deepen $b1Title")...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                                filled: true,
                                fillColor: bgRecessed,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: borderSubtle),
                                ),
                              ),
                              onSubmitted: (val) async {
                                if (val.trim().isEmpty) return;
                                directiveCtrl.clear();
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
                              side: BorderSide(
                                color: accentCyan.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                            ),
                            onPressed: (isModalBusy || widget.workbench.isAgentBusy)
                                ? null
                                : () async {
                                    final text = directiveCtrl.text.trim();
                                    if (text.isEmpty) return;
                                    directiveCtrl.clear();
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
                      if (upgradeFeats.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'UPGRADE EXISTING FEATURES (${upgradeFeats.length})',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: accentAmber,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final item in upgradeFeats)
                          InkWell(
                            onTap: () {
                              widget.workbench.toggleProposedFeatureScope(
                                item.beat.id,
                                item.feat.id,
                                !item.feat.included,
                              );
                              setModalState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      item.feat.included
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank_rounded,
                                      size: 16,
                                      color: item.feat.included
                                          ? accentAmber
                                          : textMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: bgRecessed,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                border: Border.all(
                                                  color: borderSubtle,
                                                ),
                                              ),
                                              child: Text(
                                                'E${(item.beatIdx + 1).toString().padLeft(2, '0')}',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: textSecondary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                _formatOutlineFeatureDisplayTitle(
                                                  item.feat.title,
                                                  item.beat.title,
                                                ),
                                                style: GoogleFonts.inter(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: item.feat.included
                                                      ? textPrimary
                                                      : textMuted,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (item.feat.goal.trim().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              item.feat.goal.trim(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: textMuted,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'UPGRADE · +${item.feat.activeDeltaHours}h',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: accentAmber,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      if (newFeats.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          'ADD NEW FEATURES (${newFeats.length})',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: accentEmerald,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final item in newFeats)
                          InkWell(
                            onTap: () {
                              widget.workbench.toggleProposedFeatureScope(
                                item.beat.id,
                                item.feat.id,
                                !item.feat.included,
                              );
                              setModalState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      item.feat.included
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank_rounded,
                                      size: 16,
                                      color: item.feat.included
                                          ? accentEmerald
                                          : textMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: bgRecessed,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                border: Border.all(
                                                  color: borderSubtle,
                                                ),
                                              ),
                                              child: Text(
                                                'E${(item.beatIdx + 1).toString().padLeft(2, '0')}',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: textSecondary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                _formatOutlineFeatureDisplayTitle(
                                                  item.feat.title,
                                                  item.beat.title,
                                                ),
                                                style: GoogleFonts.inter(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: item.feat.included
                                                      ? textPrimary
                                                      : textMuted,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (item.feat.goal.trim().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              item.feat.goal.trim(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: textMuted,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'NEW · +${item.feat.activeDeltaHours}h',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: accentEmerald,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: textSecondary,
                    ),
                  ),
                ),
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
                  onPressed: (isModalBusy || widget.workbench.isAgentBusy)
                      ? null
                      : () => Navigator.of(ctx).pop(true),
                  child: Text(
                    'Build $nextVer in Workbench →',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (mounted) {
            _rebuild(() {
        _isProgressiveModalOpen = false;
      });
    } else {
      _isProgressiveModalOpen = false;
    }

    if (confirmed == true) {
      await widget.workbench.approveAndExecuteReleasePlan();
    } else {
      widget.workbench.restoreActiveReleaseAfterCancel(prevReleaseId, prevPhase);
    }
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
