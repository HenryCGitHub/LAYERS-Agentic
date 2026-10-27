part of 'release_workbench_screen.dart';

extension _WorkbenchModalsExt on _ReleaseWorkbenchScreenState {
  Future<void> _showProgressiveNextReleaseModal(BuildContext context) async {
    final prevReleaseId = widget.workbench.activeReleaseId;
    final prevPhase = widget.workbench.currentPhase;
    final activeBeats = List<TierDocument>.from(
      widget.workbench.activeReleaseBeats,
    );

    // ignore: invalid_use_of_protected_member
    setState(() {
      _isProgressiveModalOpen = true;
    });
    try {
      await widget.workbench.prepareProgressiveNextReleaseDraft();
    } finally {
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {});
      }
    }
    if (!context.mounted) {
      _isProgressiveModalOpen = false;
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
      // ignore: invalid_use_of_protected_member
      setState(() {
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
    final allFeats = <TierDocument>[
      for (final b in beats) ...widget.workbench.featuresForBeat(b.id),
    ];
    int totalTasks = 0;
    int totalStepsDone = 0;
    for (final f in allFeats) {
      final states = FeatureStateNode.getStatesForDocument(f);
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

  Future<void> _promptEditHowToSubStepDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int pIdx,
    int sIdx,
  ) async {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    if (sIdx < 0 || sIdx >= parentTask.children.length) return;
    final sub = parentTask.children[sIdx];
    final bp = TaskHowToBlueprint.resolve(
      parentTask: parentTask,
      taskIndex: pIdx,
      checkpointNode: node,
      engineHint: _engineHint,
      unrealCppMode: _unrealCppMode,
    );
    final resolvedSub = sIdx < bp.subSteps.length ? bp.subSteps[sIdx] : null;
    final titleCtrl = TextEditingController(
      text: resolvedSub?.stepNumberLabel ?? sub.text,
    );
    final whereCtrl = TextEditingController(
      text: resolvedSub?.stepPath ?? sub.codeLanguage ?? '',
    );
    final instrCtrl = TextEditingController(
      text: resolvedSub?.instruction ?? sub.specNotes ?? '',
    );
    final codeCtrl = TextEditingController(
      text: resolvedSub?.codeFormula ?? sub.codeSnippet ?? '',
    );
    final verifyCtrl = TextEditingController(
      text: resolvedSub?.verifyResult ?? sub.verification ?? '',
    );

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Edit How-To Sub-Step (${pIdx + 1}.${sIdx + 1})',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('edit_substep_title_input'),
                controller: titleCtrl,
                style: GoogleFonts.inter(fontSize: 12.5, color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'Sub-step Title',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('edit_substep_where_input'),
                controller: whereCtrl,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'Where in Engine (Menu / Panel / File Path)',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('edit_substep_instruction_input'),
                controller: instrCtrl,
                maxLines: 2,
                style: GoogleFonts.inter(fontSize: 12, color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'How-To Instruction',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('edit_substep_code_input'),
                controller: codeCtrl,
                maxLines: 3,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: AppTheme.accentCyanFor(isDark),
                ),
                decoration: InputDecoration(
                  labelText: 'Code Formula / Snippet',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('edit_substep_verify_input'),
                controller: verifyCtrl,
                style: GoogleFonts.inter(fontSize: 12, color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'Done Check (Verify in Viewport)',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (parentTask.children.length > 1)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('delete'),
              child: Text(
                'Delete',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentCrimson,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: focalAccent,
              foregroundColor: focalAccentFg,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: Text(
              'Save Sub-Step',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == 'cancel') return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      if (action == 'delete' && parentTask.children.length > 1) {
        parentTask.children.removeAt(sIdx);
        parentTask.completed = parentTask.children.isNotEmpty &&
            parentTask.children.every((c) => c.completed);
      } else if (action == 'save') {
        if (titleCtrl.text.trim().isNotEmpty) {
          sub.text = titleCtrl.text.trim();
        }
        sub.codeLanguage = whereCtrl.text.trim();
        sub.specNotes = instrCtrl.text.trim();
        sub.codeSnippet = codeCtrl.text.trim();
        sub.verification = verifyCtrl.text.trim();
        sub.codeTargetFile = 'custom_snippet';
      }
      TaskHowToBlueprint.clearCache();
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  Future<void> _copySubStepCodeFormula(
    int pIdx,
    int sIdx,
    String codeFormula,
  ) async {
    await Clipboard.setData(ClipboardData(text: codeFormula));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Copied Step ${pIdx + 1}.${sIdx + 1} code formula to clipboard ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyAllTaskCode(TaskHowToBlueprint howTo) async {
    final buffer = StringBuffer()
      ..writeln('// === Task ${howTo.numLabel}: ${howTo.cleanTitle} ===');
    for (int i = 0; i < howTo.subSteps.length; i++) {
      final step = howTo.subSteps[i];
      final stepNum = (i + 1).toString().padLeft(2, '0');
      buffer
        ..writeln()
        ..writeln('// --- Step $stepNum: ${step.shortTitle} ---')
        ..writeln(step.codeFormula.trim());
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Copied all ${howTo.subSteps.length} step code blocks for Task ${howTo.numLabel} ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _promptTailorHowToDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    int checkpointIndex,
    int pIdx,
  ) async {
    final node = states[checkpointIndex];
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    final ctrl = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          '✦ Tailor How-To Sub-Steps (Task ${(pIdx + 1).toString().padLeft(2, '0')})',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Describe your exact Scene / Node / Script setup for "${parentTask.text}". The Agent will rewrite all sub-steps in Task ${(pIdx + 1).toString().padLeft(2, '0')} using your exact node and script names:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('tailor_howto_context_input'),
                controller: ctrl,
                autofocus: true,
                maxLines: 3,
                onSubmitted: (_) => Navigator.of(ctx).pop('tailor'),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  hintText:
                      'e.g., CharacterBody2D with RayCast2D HookRay and Line2D RopeVisual',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: textMuted,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_tailor_howto_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: focalAccent,
              foregroundColor: focalAccentFg,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop('tailor'),
            child: Text(
              '✦ Tailor Sub-Steps',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted || action != 'tailor') return;
    final contextText = ctrl.text.trim();
    if (contextText.isEmpty) return;
    await widget.workbench.tailorTaskHowToSubSteps(
      featureId: feat.id,
      states: states,
      checkpointIndex: checkpointIndex,
      taskIndex: pIdx,
      userContext: contextText,
    );
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Tailored Task ${(pIdx + 1).toString().padLeft(2, '0')} How-To sub-steps to "$contextText" ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleHowToSubStepCompletion(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int pIdx,
    int sIdx,
  ) {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    if (sIdx < 0 || sIdx >= parentTask.children.length) return;
    final wasDone = node.isCompleted;
    final nextCompleted = !parentTask.children[sIdx].completed;
    parentTask.children[sIdx].completed = nextCompleted;
    parentTask.completed = parentTask.children.isNotEmpty &&
        parentTask.children.every((c) => c.completed);
    final nowDone = node.isCompleted;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _selectedTaskIndexByCheckpoint[node.id] = pIdx;
      _selectedSubStepIndexByTask['${node.id}_$pIdx'] = sIdx;
      if (!wasDone && nowDone) {
        _awaitingPlaytestVerification.add(node.id);
      } else if (!nowDone) {
        _awaitingPlaytestVerification.remove(node.id);
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  void _toggleTaskGroupCompletion(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int tIdx,
  ) {
    if (tIdx < 0 || tIdx >= node.checklist.length) return;
    final task = node.checklist[tIdx];
    final markDone = !task.completed;
    task.completed = markDone;
    for (final c in task.children) {
      c.completed = markDone;
    }
    // ignore: invalid_use_of_protected_member
    setState(() {
      final nextTaskIdx = node.checklist.indexWhere((t) => !t.completed);
      if (markDone && nextTaskIdx != -1) {
        _manualCheckpointFocusIndex = states.indexWhere((s) => s.id == node.id);
        _selectedTaskIndexByCheckpoint[node.id] = nextTaskIdx;
        _selectedSubStepIndexByTask['${node.id}_$nextTaskIdx'] = 0;
      } else if (markDone) {
        final nextCpIdx = states.indexWhere((s) => !s.isCompleted);
        if (nextCpIdx != -1) {
          _manualCheckpointFocusIndex = nextCpIdx;
          final nextCp = states[nextCpIdx];
          _selectedTaskIndexByCheckpoint[nextCp.id] = 0;
          _selectedSubStepIndexByTask['${nextCp.id}_0'] = 0;
        } else {
          _selectedTaskIndexByCheckpoint[node.id] = tIdx;
        }
      } else {
        _manualCheckpointFocusIndex = states.indexWhere((s) => s.id == node.id);
        _selectedTaskIndexByCheckpoint[node.id] = tIdx;
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  Future<void> _showAddBuildTaskDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    int cpIdx,
  ) async {
    final ctrl = TextEditingController();
    final hoursCtrl = TextEditingController(text: '2');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Add Build Task to Checkpoint ${cpIdx + 1}',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 460,
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  key: const ValueKey('add_stage3_task_title_input'),
                  controller: ctrl,
                  autofocus: true,
                  style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g., Implement wall-jump impulse & SFX cue',
                    hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                    filled: true,
                    fillColor: bgRecessed,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderSubtle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  key: const ValueKey('add_stage3_task_hours_input'),
                  controller: hoursCtrl,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Hours',
                    labelStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: textMuted,
                    ),
                    filled: true,
                    fillColor: bgRecessed,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderSubtle),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_add_stage3_task_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentCyan,
              foregroundColor: const Color(0xFF06131F),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Add Task',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (saved == true &&
        mounted &&
        ctrl.text.trim().isNotEmpty &&
        cpIdx >= 0 &&
        cpIdx < states.length) {
      final hrs = int.tryParse(hoursCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 2;
      final cpNode = states[cpIdx];
      final newTask = Subtask(
        id: 'task_${DateTime.now().millisecondsSinceEpoch}',
        text: '${ctrl.text.trim()} (${hrs}h)',
        completed: false,
      );
      cpNode.checklist.add(newTask);
      final newIdx = cpNode.checklist.length - 1;
      TaskHowToBlueprint.resolve(
        parentTask: newTask,
        taskIndex: newIdx,
        checkpointNode: cpNode,
        engineHint: widget.workbench.conceptDraft?.techSpec.join(' '),
        unrealCppMode: _unrealCppMode,
      );
      widget.workbench.updateFeatureStates(feat.id, states);
      widget.workbench.synthesizeFeatureHowToStepsWithAi(
        feat.id,
        forceRefresh: true,
      );
      // ignore: invalid_use_of_protected_member
      setState(() {
        _manualCheckpointFocusIndex = cpIdx;
        _selectedTaskIndexByCheckpoint[cpNode.id] = newIdx;
        _selectedSubStepIndexByTask['${cpNode.id}_$newIdx'] = 0;
      });
    }
  }

  Future<void> _showEditBuildTaskTitleDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    Subtask parentTask, {
    FeatureStateNode? cpNode,
    int? taskIndex,
  }) async {
    final ctrl = TextEditingController(text: parentTask.text);
    final canDelete =
        cpNode != null && taskIndex != null && cpNode.checklist.length > 1;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Edit Build Task',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: TextField(
            key: const ValueKey('edit_stage3_task_title_input'),
            controller: ctrl,
            autofocus: true,
            style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: bgRecessed,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: borderSubtle),
              ),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
        ),
        actions: [
          if (canDelete)
            TextButton.icon(
              key: const ValueKey('delete_stage3_task_btn'),
              onPressed: () => Navigator.of(ctx).pop('__DELETE_TASK__'),
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 14,
                color: accentCrimson,
              ),
              label: Text(
                'Delete Task',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentCrimson,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('save_stage3_task_title_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(
              'Save',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (saved == '__DELETE_TASK__' &&
        canDelete &&
        taskIndex < cpNode.checklist.length &&
        mounted) {
      cpNode.checklist.removeAt(taskIndex);
      TaskHowToBlueprint.clearCache();
      widget.workbench.updateFeatureStates(feat.id, states);
      // ignore: invalid_use_of_protected_member
      setState(() {
        final nextIdx = cpNode.checklist.isEmpty
            ? 0
            : taskIndex.clamp(0, cpNode.checklist.length - 1);
        _selectedTaskIndexByCheckpoint[cpNode.id] = nextIdx;
        _selectedSubStepIndexByTask['${cpNode.id}_$nextIdx'] = 0;
      });
      return;
    }
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      parentTask.text = saved.trim();
      TaskHowToBlueprint.clearCache();
      widget.workbench.updateFeatureStates(feat.id, states);
    }
  }

  Future<void> _showEditCheckpointTuningAndGuardsDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
  ) async {
    final tuningCtrl = TextEditingController(
      text: node.tuningParams.join(', '),
    );
    final guardsCtrl = TextEditingController(
      text: node.edgeCases.join('\n'),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Edit Checkpoint Tuning & Edge Guards',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'TUNING PARAMETERS (COMMA SEPARATED)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: accentViolet,
                ),
              ),
              const SizedBox(height: 5),
              TextField(
                key: const ValueKey('edit_stage3_tuning_input'),
                controller: tuningCtrl,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: bgRecessed,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'EDGE-CASE GUARDS (1 PER LINE)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: accentAmber,
                ),
              ),
              const SizedBox(height: 5),
              TextField(
                key: const ValueKey('edit_stage3_guards_input'),
                controller: guardsCtrl,
                maxLines: 3,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: bgRecessed,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('save_stage3_tuning_guards_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Save Spec',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      node.tuningParams = tuningCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      node.edgeCases = guardsCtrl.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final tuningBullets = node.tuningParams.map((t) => '• $t').join('\n');
      final edgeBullets = node.edgeCases.map((e) => '• $e').join('\n');
      feat.sections['tuning'] = tuningBullets;
      feat.sections['variables'] = tuningBullets;
      feat.sections['edge_cases'] = edgeBullets;
      TaskHowToBlueprint.clearCache();
      widget.workbench.updateFeatureStates(feat.id, states);
    }
  }

  Future<void> _showAddLiveFeatureDialog(TierDocument beat) async {
    final ctrl = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Add Playable Feature to ${_formatOutlineBeatDisplayTitle(beat.title)}',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: TextField(
            key: const ValueKey('workbench_add_live_feature_input'),
            controller: ctrl,
            autofocus: true,
            style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g., Grapple Swing Release, Shield Parry, Dash Reload',
              hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
              filled: true,
              fillColor: bgRecessed,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: borderSubtle),
              ),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_workbench_add_live_feature_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentCyan,
              foregroundColor: const Color(0xFF06131F),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(
              '+ Add Feature',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      // ignore: invalid_use_of_protected_member
      setState(() {
        _manualCheckpointFocusIndex = null;
      });
      widget.workbench.addLiveFeatureToBeat(beat.id, saved.trim());
    }
  }

  Future<void> _showRenameLiveFeatureDialog(TierDocument feat) async {
    final ctrl = TextEditingController(text: feat.title);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Rename Playable Feature',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: TextField(
            key: const ValueKey('workbench_rename_live_feature_input'),
            controller: ctrl,
            autofocus: true,
            style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: bgRecessed,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: borderSubtle),
              ),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_workbench_rename_live_feature_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(
              'Save',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      widget.workbench.renameLiveFeature(feat.id, saved.trim());
    }
  }

  Future<void> _showLogPlaytestIssueDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    int checkpointIndex,
  ) async {
    final ctrl = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          '🐞 Log Playtest Issue',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Describe the bug or feel issue observed in the game viewport. The Agent will append a 3-step [FIX] task group and a [PLAYTEST GUARD] rule:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('workbench_log_playtest_issue_input'),
                controller: ctrl,
                autofocus: true,
                style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g., Dash clips through thin arena walls on diagonal input',
                  hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                  filled: true,
                  fillColor: bgRecessed,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_workbench_log_playtest_issue_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentAmber,
              foregroundColor: const Color(0xFF1F1300),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(
              '+ Add [FIX] Task & Guard',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      final newIdx = widget.workbench.logPlaytestIssueOnCheckpoint(
        featureId: feat.id,
        states: states,
        checkpointIndex: checkpointIndex,
        issueDescription: saved.trim(),
      );
      if (newIdx >= 0 && checkpointIndex < states.length) {
        final cpNode = states[checkpointIndex];
        // ignore: invalid_use_of_protected_member
        setState(() {
          _manualCheckpointFocusIndex = checkpointIndex;
          _selectedTaskIndexByCheckpoint[cpNode.id] = newIdx;
          _selectedSubStepIndexByTask['${cpNode.id}_$newIdx'] = 0;
        });
      }
    }
  }
}
