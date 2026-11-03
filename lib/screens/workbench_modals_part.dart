part of 'release_workbench_screen.dart';

extension _WorkbenchModalsExt on _ReleaseWorkbenchScreenState {
  static final RegExp _trailingDotRegex = RegExp(r'\.$');
  static final RegExp _recommendedPrefixRegex =
      RegExp(r'^\(recommended\)\s*', caseSensitive: false);
  static final RegExp _goalPrefixRegex =
      RegExp(r'^Goal:\s*', caseSensitive: false);

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
      _showProgressiveStableFeaturesDrawer = false;
      _progressivePrevReleaseId = prevReleaseId;
      _progressivePrevPhase = prevPhase;
      _pendingPhaseGraduationOverride = null;
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

    void resetState() {
      _isProgressiveModalOpen = false;
      _showProgressiveStableFeaturesDrawer = false;
      _pendingPhaseGraduationOverride = null;
      _addingFeatureToBeatId = null;
      if (confirmed) {
        _manualCheckpointFocusIndex = null;
        _manualCheckpointFocusFeatureId = null;
        _selectedTaskIndexByCheckpoint.clear();
        _selectedSubStepIndexByTask.clear();
      }
    }

    if (mounted) {
      _rebuild(resetState);
    } else {
      resetState();
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
                    SizedBox(
                      height: 1,
                      child: Opacity(
                        opacity: 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'PROGRESSIVE RELEASE CO-PILOT · ${nextVer.toUpperCase()}',
                            ),
                            Text('·  $prevVer 100% SHIPPED ✓'),
                            if (bp?.releaseTitle.isNotEmpty == true)
                              Text(bp!.releaseTitle),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: bgRecessed,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Text(
                            nextVer,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: accentEmerald,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            bp?.releaseTitle.isNotEmpty == true
                                ? bp!.releaseTitle.replaceFirst(
                                    RegExp(
                                      r'^v\d+(?:\.\d+)*\s*[:·—\-]\s*',
                                      caseSensitive: false,
                                    ),
                                    '',
                                  )
                                : (widget.workbench.isAgentBusy
                                    ? 'Architecting $nextVer Release Scope...'
                                    : 'Recommended Scope for $nextVer'),
                            style: AppTheme.displayFont(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final activePhase = widget.workbench.currentPhase;
                        final mvpCov = widget.workbench.mvpBeatCoverage();
                        final vsCov =
                            widget.workbench.verticalSliceBeatCoverage();
                        final fpCov =
                            widget.workbench.fullProductionCoverage();

                        bool isPhaseCompleted(ProductionPhase p) {
                          switch (p) {
                            case ProductionPhase.prototype:
                              return true;
                            case ProductionPhase.mvp:
                              return mvpCov.isComplete ||
                                  activePhase.index > ProductionPhase.mvp.index;
                            case ProductionPhase.verticalSlice:
                              return vsCov.isComplete ||
                                  activePhase.index >
                                      ProductionPhase.verticalSlice.index;
                            case ProductionPhase.fullProduction:
                              return fpCov.isReadyForLaunch &&
                                  activePhase == ProductionPhase.postLaunch;
                            case ProductionPhase.postLaunch:
                              return false;
                          }
                        }

                        bool isPhaseGated(ProductionPhase p) {
                          if (p.index <= activePhase.index) return false;
                          switch (p) {
                            case ProductionPhase.prototype:
                            case ProductionPhase.mvp:
                              return false;
                            case ProductionPhase.verticalSlice:
                              return !mvpCov.isComplete;
                            case ProductionPhase.fullProduction:
                              return !mvpCov.isComplete || !vsCov.isComplete;
                            case ProductionPhase.postLaunch:
                              return !fpCov.isReadyForLaunch;
                          }
                        }

                        String? inlineEpicCounterFor(ProductionPhase p) {
                          if (p != activePhase) return null;
                          switch (p) {
                            case ProductionPhase.prototype:
                              return null;
                            case ProductionPhase.mvp:
                              return '${mvpCov.coveredBeats}/${mvpCov.totalBeats} Epics';
                            case ProductionPhase.verticalSlice:
                              return '${vsCov.polishedBeats}/${vsCov.totalBeats} Epics';
                            case ProductionPhase.fullProduction:
                              return '${fpCov.coveredBeats}/${fpCov.totalBeats} Epics';
                            case ProductionPhase.postLaunch:
                              return fpCov.openFixCount > 0
                                  ? '${fpCov.openFixCount} Fixes'
                                  : 'Live Ops';
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'PHASE:',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.7,
                                    color: textMuted,
                                  ),
                                ),
                                for (final phase in ProductionPhase.values)
                                  Builder(
                                    builder: (context) {
                                      final isSelected = activePhase == phase;
                                      final isCompleted =
                                          !isSelected && isPhaseCompleted(phase);
                                      final isGated = isPhaseGated(phase);
                                      final epicCounter =
                                          inlineEpicCounterFor(phase);
                                      final shortLabel = phase ==
                                              ProductionPhase.prototype
                                          ? '01 · Prototype'
                                          : (phase == ProductionPhase.mvp
                                              ? '02 · MVP'
                                              : (phase ==
                                                      ProductionPhase
                                                          .verticalSlice
                                                  ? '03 · Vertical Slice'
                                                  : (phase ==
                                                          ProductionPhase
                                                              .fullProduction
                                                      ? '04 · Full Production'
                                                      : '05 · Post-Launch')));
                                      return InkWell(
                                        key: ValueKey(
                                          'progressive_phase_pill_${phase.name}',
                                        ),
                                        borderRadius: BorderRadius.circular(5),
                                        onTap: () async {
                                          if (isSelected) return;
                                          if (isGated &&
                                              _pendingPhaseGraduationOverride !=
                                                  phase) {
                                            _rebuild(() {
                                              _pendingPhaseGraduationOverride =
                                                  phase;
                                            });
                                            return;
                                          }
                                          _rebuild(() {
                                            _pendingPhaseGraduationOverride =
                                                null;
                                            _selectedProgressiveTrackIndex = 0;
                                          });
                                          await widget.workbench
                                              .setDraftReleasePhase(phase);
                                          if (mounted) {
                                            _rebuild(() {});
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? bgRecessed
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            border: Border(
                                              bottom: BorderSide(
                                                color: isSelected
                                                    ? accentEmerald
                                                    : Colors.transparent,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                isCompleted
                                                    ? '$shortLabel ✓'
                                                    : shortLabel,
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 10,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: isSelected
                                                      ? textPrimary
                                                      : (isCompleted
                                                          ? textMuted
                                                          : textSecondary),
                                                ),
                                              ),
                                              if (epicCounter != null) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  epicCounter,
                                                  key: const ValueKey(
                                                    'progressive_phase_coverage_badge',
                                                  ),
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: accentEmerald,
                                                  ),
                                                ),
                                              ] else if (isGated) ...[
                                                const SizedBox(width: 4),
                                                Text(
                                                  '🔒',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 9.5,
                                                    color: textMuted,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            if (_pendingPhaseGraduationOverride != null) ...[
                              const SizedBox(height: 10),
                              Builder(
                                builder: (context) {
                                  final targetOverride =
                                      _pendingPhaseGraduationOverride!;
                                  final remainingCodes = activePhase ==
                                          ProductionPhase.mvp
                                      ? mvpCov.incompleteBeatCodes
                                      : vsCov.incompleteBeatCodes;
                                  final totalCount = activePhase ==
                                          ProductionPhase.mvp
                                      ? mvpCov.totalBeats
                                      : vsCov.totalBeats;
                                  final phaseName = activePhase ==
                                          ProductionPhase.mvp
                                      ? '02 · MVP'
                                      : '03 · Vertical Slice';
                                  return Container(
                                    key: const ValueKey(
                                      'progressive_phase_graduation_guard_banner',
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accentAmber.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(7),
                                      border: Border.all(
                                        color:
                                            accentAmber.withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          '${remainingCodes.length}/$totalCount Epics incomplete in $phaseName (${remainingCodes.join(", ")}) — finish remaining Epics first or override.',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: textPrimary,
                                          ),
                                        ),
                                        InkWell(
                                          key: const ValueKey(
                                            'progressive_phase_stay_btn',
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          onTap: () {
                                            _rebuild(() {
                                              _pendingPhaseGraduationOverride =
                                                  null;
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: accentAmber,
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              'Stay in $phaseName (Recommended)',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF1F1600),
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          key: const ValueKey(
                                            'progressive_phase_override_confirm_btn',
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          onTap: () async {
                                            _rebuild(() {
                                              _pendingPhaseGraduationOverride =
                                                  null;
                                              _selectedProgressiveTrackIndex =
                                                  0;
                                            });
                                            await widget.workbench
                                                .setDraftReleasePhase(
                                                  targetOverride,
                                                );
                                            if (mounted) {
                                              _rebuild(() {});
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: accentAmber.withValues(
                                                  alpha: 0.5,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              'Override → ${targetOverride.label}',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: accentAmber,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                        foregroundColor: isDark
                            ? const Color(0xFF06281E)
                            : Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onPressed: (widget.workbench.isAgentBusy ||
                              bp == null ||
                              (upgradeCount + newCount) == 0)
                          ? null
                          : () => _closeProgressiveReleasePlanner(
                                confirmed: true,
                              ),
                      child: Text(
                        'Approve & Build $nextVer →',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
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
                              color: borderBright,
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
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      widget.workbench.agentProgressStep ??
                                          'Planning $nextVer Epic upgrades…',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (bp != null) ...[
                        // Streamlined 3-Step Progressive Release Canvas
                        Builder(
                          builder: (context) {
                            final nextRows = <({
                              String beatId,
                              String epicCode,
                              ProposedFeatureBlueprint feat,
                            })>[];
                            final stableRows = <({
                              String beatId,
                              String epicCode,
                              ProposedFeatureBlueprint feat,
                            })>[];
                            final pivotedRows = <({
                              String beatId,
                              String epicCode,
                              ProposedFeatureBlueprint feat,
                            })>[];
                            for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) {
                              final b = bp.beats[bIdx];
                              final eCode =
                                  'E${(bIdx + 1).toString().padLeft(2, '0')}';
                              for (final f in b.features) {
                                if (f.isSuperseded) {
                                  pivotedRows.add((
                                    beatId: b.id,
                                    epicCode: eCode,
                                    feat: f,
                                  ));
                                } else if (f.isStable) {
                                  stableRows.add((
                                    beatId: b.id,
                                    epicCode: eCode,
                                    feat: f,
                                  ));
                                } else {
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
                                    : 'Advance $nextVer with the selected features and upgrades below.');

                            final selectedChangesCount =
                                nextRows.where((r) => r.feat.included).length;
                            final epicFocusOptions = widget.workbench
                                .epicFocusOptionsForBlueprint(bp);
                            final activeOptIdx = (_selectedProgressiveTrackIndex >=
                                        0 &&
                                    _selectedProgressiveTrackIndex <
                                        epicFocusOptions.length)
                                ? _selectedProgressiveTrackIndex
                                : 0;
                            final activeEpicOpt = epicFocusOptions.isNotEmpty
                                ? epicFocusOptions[activeOptIdx]
                                : null;

                            final activePhaseForEpics =
                                widget.workbench.currentPhase;
                            final isVsForEpics = activePhaseForEpics ==
                                ProductionPhase.verticalSlice;
                            final mvpCovForEpics =
                                widget.workbench.mvpBeatCoverage();
                            final vsCovForEpics =
                                widget.workbench.verticalSliceBeatCoverage();
                            final availCodes = isVsForEpics
                                ? vsCovForEpics.incompleteBeatCodes
                                : mvpCovForEpics.incompleteBeatCodes;
                            final doneCodesHeader = isVsForEpics
                                ? vsCovForEpics.completedBeatCodes
                                : mvpCovForEpics.completedBeatCodes;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Step 1: EPICS (3 Available Incomplete Epic Cards + 2-Line BLUF Goal & Causal End Goal Box)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: bgSurface,
                                    borderRadius: BorderRadius.circular(10),
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
                                          Flexible(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'EPICS',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.6,
                                                    color: textPrimary,
                                                  ),
                                                ),
                                                if (availCodes.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: accentEmerald
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      border: Border.all(
                                                        color: accentEmerald
                                                            .withValues(
                                                              alpha: 0.25,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '${availCodes.length} Available (${availCodes.join(", ")})',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: accentEmerald,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                doneCodesHeader.isNotEmpty
                                                    ? '${doneCodesHeader.join(", ")} COMPLETE ✓ · PICK EPICS FOR ${nextVer.toUpperCase()}'
                                                    : 'PICK EPICS FOR ${nextVer.toUpperCase()} · ${widget.workbench.activePhaseBadgeLabel.toUpperCase()}',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: textMuted,
                                                ),
                                              ),
                                              SizedBox(
                                                width: 1,
                                                height: 1,
                                                child: Opacity(
                                                  opacity: 0,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        '1. CHOOSE ${nextVer.toUpperCase()} FOCUS',
                                                      ),
                                                      Text(
                                                        'AGENT ARCHITECTURAL RECOMMENDATION · ${widget.workbench.activePhaseBadgeLabel}',
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      if (widget
                                          .workbench
                                          .isSynthesizingProgressiveFocus)
                                        Container(
                                          key: const ValueKey(
                                            'progressive_section_1_loading',
                                          ),
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: bgRecessed,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: borderSubtle,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: textPrimary,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  'Synthesizing Section 1 · Analyzing completed $prevVer features & Design Pillars to recommend $nextVer focus and 3 strategic options...',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: textSecondary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else ...[
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            final isWide =
                                                constraints.maxWidth >= 700;
                                            final cardCount =
                                                epicFocusOptions.isNotEmpty
                                                    ? epicFocusOptions.length
                                                    : dynamicOptions.length;
                                            final optionCards = <Widget>[
                                              for (int oIdx = 0;
                                                  oIdx < cardCount;
                                                  oIdx++)
                                                Builder(
                                                  builder: (context) {
                                                    final isSelected =
                                                        _selectedProgressiveTrackIndex ==
                                                        oIdx;
                                                    final epicOpt = oIdx <
                                                            epicFocusOptions
                                                                .length
                                                        ? epicFocusOptions[oIdx]
                                                        : null;
                                                    final rawOpt = oIdx <
                                                            dynamicOptions
                                                                .length
                                                        ? dynamicOptions[oIdx]
                                                        : '';
                                                    final isRec = epicOpt != null
                                                        ? epicOpt.isRecommended
                                                        : rawOpt
                                                            .toLowerCase()
                                                            .startsWith(
                                                              '(recommended)',
                                                            );
                                                    final stripped = rawOpt
                                                        .replaceFirst(
                                                          _recommendedPrefixRegex,
                                                          '',
                                                        )
                                                        .trim();
                                                    final colonIdx =
                                                        stripped.indexOf(':');
                                                    final optTitle = epicOpt !=
                                                            null
                                                        ? epicOpt.title
                                                        : (colonIdx > 0
                                                            ? stripped
                                                                .substring(
                                                                  0,
                                                                  colonIdx,
                                                                )
                                                                .trim()
                                                            : stripped);
                                                    final optDesc = epicOpt !=
                                                            null
                                                        ? epicOpt.subtitle
                                                        : (colonIdx > 0
                                                            ? stripped
                                                                .substring(
                                                                  colonIdx + 1,
                                                                )
                                                                .trim()
                                                            : '');
                                                    return InkWell(
                                                      key: ValueKey(
                                                        'progressive_preset_chip_$oIdx',
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      onTap: widget
                                                              .workbench
                                                              .isAgentBusy
                                                          ? null
                                                          : () async {
                                                              final prevIdx =
                                                                  _selectedProgressiveTrackIndex;
                                                              if (prevIdx ==
                                                                  oIdx) {
                                                                return;
                                                              }
                                                              _rebuild(() {
                                                                _selectedProgressiveTrackIndex =
                                                                    oIdx;
                                                              });
                                                              if (epicOpt !=
                                                                  null) {
                                                                widget.workbench
                                                                    .applyProgressiveEpicFocusOption(
                                                                  oIdx,
                                                                  epicOpt
                                                                      .targetBeatIndices,
                                                                );
                                                                _rebuild(() {});
                                                              } else {
                                                                if (prevIdx !=
                                                                    0) {
                                                                  widget
                                                                      .workbench
                                                                      .restoreInitialProgressiveDraftBlueprint();
                                                                }
                                                                if (oIdx > 0) {
                                                                  await submitDirective(
                                                                    'Re-architect $nextVer around this strategic option: $rawOpt',
                                                                  );
                                                                } else {
                                                                  _rebuild(
                                                                    () {},
                                                                  );
                                                                }
                                                              }
                                                            },
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              12,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: isSelected
                                                              ? bgSurface
                                                              : bgRecessed,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          border: Border.all(
                                                            color: isSelected
                                                                ? textPrimary
                                                                    .withValues(
                                                                      alpha: 0.7,
                                                                    )
                                                                : borderSubtle,
                                                            width: isSelected
                                                                ? 1.5
                                                                : 1.0,
                                                          ),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  isSelected
                                                                      ? '●'
                                                                      : '○',
                                                                  style: GoogleFonts
                                                                      .jetBrainsMono(
                                                                    fontSize: 11,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: isSelected
                                                                        ? textPrimary
                                                                        : textMuted,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 8,
                                                                ),
                                                                Expanded(
                                                                  child: Text(
                                                                    optTitle,
                                                                    style: GoogleFonts
                                                                        .inter(
                                                                      fontSize:
                                                                          12.5,
                                                                      fontWeight: isSelected
                                                                          ? FontWeight
                                                                              .w700
                                                                          : FontWeight
                                                                              .w600,
                                                                      color: isSelected
                                                                          ? textPrimary
                                                                          : textSecondary,
                                                                    ),
                                                                  ),
                                                                ),
                                                                if (isRec) ...[
                                                                  const SizedBox(
                                                                    width: 6,
                                                                  ),
                                                                  Text(
                                                                    '★ REC',
                                                                    style: GoogleFonts
                                                                        .jetBrainsMono(
                                                                      fontSize:
                                                                          9.5,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      color:
                                                                          accentEmerald,
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    width: 1,
                                                                    height: 1,
                                                                    child:
                                                                        Opacity(
                                                                      opacity: 0,
                                                                      child: Text(
                                                                        '★ RECOMMENDED',
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ],
                                                            ),
                                                            if (optDesc
                                                                .isNotEmpty) ...[
                                                              const SizedBox(
                                                                height: 5,
                                                              ),
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets.only(
                                                                  left: 19,
                                                                ),
                                                                child: Text(
                                                                  optDesc,
                                                                  style: GoogleFonts
                                                                      .jetBrainsMono(
                                                                    fontSize:
                                                                        11,
                                                                    height: 1.35,
                                                                    color: isSelected
                                                                        ? textSecondary
                                                                        : textMuted,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                            ];
                                            if (isWide &&
                                                optionCards.length > 1) {
                                              return IntrinsicHeight(
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.stretch,
                                                  children: [
                                                    for (int i = 0;
                                                        i < optionCards.length;
                                                        i++) ...[
                                                      if (i > 0)
                                                        const SizedBox(width: 10),
                                                      Expanded(
                                                        child: optionCards[i],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              );
                                            }
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                for (int i = 0;
                                                    i < optionCards.length;
                                                    i++) ...[
                                                  if (i > 0)
                                                    const SizedBox(height: 8),
                                                  optionCards[i],
                                                ],
                                              ],
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        // 2-Line Stacked Box: Line 1 = BLUF Goal | Line 2 = Causal Trigger → Result End Goal
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: bgRecessed,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: borderSubtle,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.baseline,
                                                textBaseline:
                                                    TextBaseline.alphabetic,
                                                children: [
                                                  SizedBox(
                                                    width: 96,
                                                    child: Text(
                                                      'GOAL:',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: accentCyan,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: activeEpicOpt != null
                                                        ? RichText(
                                                            text: TextSpan(
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 12,
                                                                height: 1.35,
                                                                color:
                                                                    textPrimary,
                                                              ),
                                                              children: [
                                                                TextSpan(
                                                                  text: activeEpicOpt
                                                                      .blufHeadline,
                                                                  style:
                                                                      const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                  ),
                                                                ),
                                                                TextSpan(
                                                                  text:
                                                                      ' — ${activeEpicOpt.blufDetail}',
                                                                  style:
                                                                      TextStyle(
                                                                    color:
                                                                        textSecondary,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          )
                                                        : Text(
                                                            heroGoal,
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 12,
                                                              height: 1.35,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: textPrimary,
                                                            ),
                                                          ),
                                                  ),
                                                ],
                                              ),
                                              Container(
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 7,
                                                ),
                                                height: 1,
                                                color: borderSubtle,
                                              ),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.baseline,
                                                textBaseline:
                                                    TextBaseline.alphabetic,
                                                children: [
                                                  SizedBox(
                                                    width: 96,
                                                    child: Text(
                                                      '✓ END GOAL:',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: accentEmerald,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      activeEpicOpt != null
                                                          ? activeEpicOpt
                                                              .causalDoneWhen
                                                          : bp.doneWhen.trim(),
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 11.5,
                                                        height: 1.35,
                                                        color: textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              SizedBox(
                                                height: 1,
                                                child: Opacity(
                                                  opacity: 0,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(heroGoal),
                                                      const Text('✓ DONE WHEN: '),
                                                      Text(bp.doneWhen.trim()),
                                                    ],
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
                                const SizedBox(height: 12),

                                // Step 2: Epics & Features in v0.X (Outliner-Style Epic -> Feature Tree)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: bgSurface,
                                    borderRadius: BorderRadius.circular(10),
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
                                          Flexible(
                                            child: Text(
                                              '2. EPICS & FEATURES IN ${nextVer.toUpperCase()} ($selectedChangesCount SELECTED · ${bp.totalIncludedHours}H)',
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.6,
                                                color: textMuted,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'GROUPED BY EPIC · CLICK FEATURE TO INCLUDE / SKIP',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w600,
                                              color: textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      if (widget
                                              .workbench
                                              .isSynthesizingProgressiveFocus &&
                                          selectedChangesCount == 0)
                                        Container(
                                          key: const ValueKey(
                                            'progressive_section_2_waiting',
                                          ),
                                          margin: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 11,
                                          ),
                                          decoration: BoxDecoration(
                                            color: bgRecessed,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: borderSubtle,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 12,
                                                height: 12,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 1.6,
                                                  color: textMuted,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  'Waiting for Section 1 focus before populating target Epics for $nextVer...',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11.5,
                                                    color: textSecondary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      for (int bIdx = 0;
                                          bIdx < bp.beats.length;
                                          bIdx++)
                                        Builder(
                                          builder: (context) {
                                            final b = bp.beats[bIdx];
                                            final epicCode =
                                                'E${(bIdx + 1).toString().padLeft(2, '0')}';
                                            final epicTitle =
                                                _formatOutlineBeatDisplayTitle(
                                              b.title,
                                            ).toUpperCase();
                                            final activeEpicFeats = b.features
                                                .where(
                                                  (f) =>
                                                      !f.isStable &&
                                                      !f.isSuperseded,
                                                )
                                                .toList();
                                            final isAddingHere =
                                                _addingFeatureToBeatId == b.id;
                                            final isSynthesizingEpic = widget
                                                .workbench
                                                .isSynthesizingProgressiveBeat(
                                                  b.id,
                                                );
                                            final isQueuedEpic = widget
                                                .workbench
                                                .isQueuedProgressiveBeat(
                                                  b.id,
                                                );
                                            if (activeEpicFeats.isEmpty &&
                                                !isAddingHere &&
                                                !isSynthesizingEpic &&
                                                !isQueuedEpic) {
                                              return const SizedBox.shrink();
                                            }
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: bgRecessed,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: borderSubtle,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  // Outliner-Style Epic Group Header (ONLY Epics have E0# codes)
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 9,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: bgSurface
                                                          .withValues(
                                                            alpha: 0.65,
                                                          ),
                                                      borderRadius:
                                                          const BorderRadius.vertical(
                                                            top: Radius.circular(
                                                              7,
                                                            ),
                                                          ),
                                                      border: Border(
                                                        bottom: BorderSide(
                                                          color: borderSubtle,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            '$epicCode — $epicTitle',
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: GoogleFonts
                                                                .jetBrainsMono(
                                                              fontSize: 10.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              letterSpacing:
                                                                  0.6,
                                                              color:
                                                                  textPrimary,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            if (isSynthesizingEpic) ...[
                                                              SizedBox(
                                                                width: 10,
                                                                height: 10,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      1.6,
                                                                  color:
                                                                      accentAmber,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 6,
                                                              ),
                                                              Text(
                                                                'Planning $nextVer changes...',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize: 9.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color:
                                                                      accentAmber,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                            ] else if (isQueuedEpic &&
                                                                activeEpicFeats
                                                                    .isEmpty) ...[
                                                              Text(
                                                                'Queued',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize: 9.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color:
                                                                      textMuted,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                            ],
                                                            InkWell(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                        4,
                                                                      ),
                                                              onTap: () {
                                                                _rebuild(() {
                                                                  _addingFeatureToBeatId =
                                                                      b.id;
                                                                  _progressiveNewFeatCtrl
                                                                      .clear();
                                                                });
                                                              },
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          7,
                                                                      vertical:
                                                                          2,
                                                                    ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color:
                                                                      bgRecessed,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        4,
                                                                      ),
                                                                  border:
                                                                      Border.all(
                                                                    color:
                                                                        borderSubtle,
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  '+ Add',
                                                                  style: GoogleFonts
                                                                      .jetBrainsMono(
                                                                    fontSize:
                                                                        9.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color:
                                                                        textSecondary,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  // Indented Features Tree (mirrors Outliner hierarchy — no E0# on feature rows)
                                                  Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          left: 16,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          12,
                                                          8,
                                                          10,
                                                          8,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      border: Border(
                                                        left: BorderSide(
                                                          color: borderSubtle,
                                                          width: 1.5,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        if (activeEpicFeats
                                                                .isEmpty &&
                                                            (isSynthesizingEpic ||
                                                                isQueuedEpic))
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                              vertical: 4,
                                                            ),
                                                            child: Row(
                                                              children: [
                                                                if (isSynthesizingEpic) ...[
                                                                  SizedBox(
                                                                    width: 11,
                                                                    height: 11,
                                                                    child:
                                                                        CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          1.5,
                                                                      color:
                                                                          accentAmber,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                ],
                                                                Expanded(
                                                                  child: Text(
                                                                    isSynthesizingEpic
                                                                        ? 'Synthesizing $epicCode upgrades…'
                                                                        : 'Queued',
                                                                    style: GoogleFonts
                                                                        .inter(
                                                                      fontSize:
                                                                          11.5,
                                                                      color: isSynthesizingEpic
                                                                          ? textSecondary
                                                                          : textMuted,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        for (int fIdx = 0;
                                                            fIdx <
                                                                activeEpicFeats
                                                                    .length;
                                                            fIdx++)
                                                          Builder(
                                                            builder: (context) {
                                                              final f =
                                                                  activeEpicFeats[
                                                                      fIdx];
                                                              final isUpg = f
                                                                      .lifecycle ==
                                                                  FeatureLifecycleStatus
                                                                      .upgrade;
                                                              final isInc =
                                                                  f.included;
                                                              final cleanGoal =
                                                                  f.goal
                                                                      .trim()
                                                                      .replaceAll(
                                                                        _trailingDotRegex,
                                                                        '',
                                                                      );
                                                              return Padding(
                                                                padding: EdgeInsets.only(
                                                                  bottom: fIdx +
                                                                              1 <
                                                                          activeEpicFeats
                                                                              .length
                                                                      ? 5
                                                                      : 0,
                                                                ),
                                                                child: InkWell(
                                                                  key: ValueKey(
                                                                    'progressive_toggle_feat_${f.id}',
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                            6,
                                                                          ),
                                                                  onTap: () {
                                                                    widget
                                                                        .workbench
                                                                        .toggleProposedFeatureScope(
                                                                      b.id,
                                                                      f.id,
                                                                      !f.included,
                                                                    );
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
                                                                              7,
                                                                        ),
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: isInc
                                                                          ? bgSurface
                                                                          : Colors
                                                                              .transparent,
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            6,
                                                                          ),
                                                                      border:
                                                                          Border.all(
                                                                        color:
                                                                            borderSubtle,
                                                                      ),
                                                                    ),
                                                                    child: Row(
                                                                      children: [
                                                                        Text(
                                                                          isInc
                                                                              ? '☑'
                                                                              : '☐',
                                                                          style: GoogleFonts
                                                                              .jetBrainsMono(
                                                                            fontSize:
                                                                                13,
                                                                            fontWeight:
                                                                                FontWeight.w700,
                                                                            color: isInc
                                                                                ? accentEmerald
                                                                                : textMuted,
                                                                          ),
                                                                        ),
                                                                        const SizedBox(
                                                                          width:
                                                                              10,
                                                                        ),
                                                                        Expanded(
                                                                          child:
                                                                              RichText(
                                                                            maxLines:
                                                                                1,
                                                                            overflow:
                                                                                TextOverflow.ellipsis,
                                                                            text:
                                                                                TextSpan(
                                                                              style: GoogleFonts.inter(
                                                                                fontSize: 12.5,
                                                                                color: isInc ? textPrimary : textMuted,
                                                                              ),
                                                                              children: [
                                                                                TextSpan(
                                                                                  text: f.title,
                                                                                  style: const TextStyle(
                                                                                    fontWeight: FontWeight.w700,
                                                                                  ),
                                                                                ),
                                                                                TextSpan(
                                                                                  text:
                                                                                      ' — ${widget.workbench.formatChangelogDeltaForFeature(f)}',
                                                                                  style: GoogleFonts.jetBrainsMono(
                                                                                    fontSize: 11.5,
                                                                                    color: !isInc
                                                                                        ? textMuted
                                                                                        : (isUpg ? textSecondary : accentEmerald.withValues(alpha: 0.9)),
                                                                                  ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        const SizedBox(
                                                                          width:
                                                                              10,
                                                                        ),
                                                                        Container(
                                                                          padding:
                                                                              const EdgeInsets.symmetric(
                                                                            horizontal:
                                                                                7,
                                                                            vertical:
                                                                                2,
                                                                          ),
                                                                          decoration:
                                                                              BoxDecoration(
                                                                            color: !isInc
                                                                                ? bgRecessed
                                                                                : (isUpg
                                                                                    ? accentAmber.withValues(alpha: 0.1)
                                                                                    : accentEmerald.withValues(alpha: 0.1)),
                                                                            borderRadius:
                                                                                BorderRadius.circular(
                                                                              4,
                                                                            ),
                                                                            border:
                                                                                Border.all(
                                                                              color: !isInc
                                                                                  ? borderSubtle
                                                                                  : (isUpg
                                                                                      ? accentAmber.withValues(alpha: 0.25)
                                                                                      : accentEmerald.withValues(alpha: 0.25)),
                                                                            ),
                                                                          ),
                                                                          child:
                                                                              Text(
                                                                            !isInc
                                                                                ? 'SKIPPED'
                                                                                : (isUpg
                                                                                    ? 'UPGRADE'
                                                                                    : 'NEW'),
                                                                            style:
                                                                                GoogleFonts.jetBrainsMono(
                                                                              fontSize:
                                                                                  9.5,
                                                                              fontWeight:
                                                                                  FontWeight.w700,
                                                                              color: !isInc
                                                                                  ? textMuted
                                                                                  : (isUpg
                                                                                      ? accentAmber
                                                                                      : accentEmerald),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        SizedBox(
                                                                          width:
                                                                              1,
                                                                          height:
                                                                              1,
                                                                          child:
                                                                              Opacity(
                                                                            opacity:
                                                                                0,
                                                                            child:
                                                                                Row(
                                                                              mainAxisSize: MainAxisSize.min,
                                                                              children: [
                                                                                if (cleanGoal.isNotEmpty)
                                                                                  Text(cleanGoal),
                                                                                Text(
                                                                                  !isInc
                                                                                      ? 'Skipped'
                                                                                      : (isUpg ? 'Upgrade' : 'New'),
                                                                                ),
                                                                                Text(
                                                                                  '${isInc ? f.estimatedHours : 0}h',
                                                                                ),
                                                                              ],
                                                                            ),
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
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      if (pivotedRows.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            for (final pRow in pivotedRows)
                                              InkWell(
                                                key: ValueKey(
                                                  'progressive_restore_feat_${pRow.feat.id}',
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                onTap: () {
                                                  widget.workbench
                                                      .toggleProposedFeatureSuperseded(
                                                    pRow.beatId,
                                                    pRow.feat.id,
                                                  );
                                                  _rebuild(() {});
                                                },
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: bgRecessed,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                    border: Border.all(
                                                      color: borderSubtle,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'ARCHIVED: ${pRow.feat.title} · ↺ Restore',
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 9.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: textMuted,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Builder(
                                        builder: (context) {
                                          final activePhase =
                                              widget.workbench.currentPhase;
                                          final isVs = activePhase ==
                                              ProductionPhase.verticalSlice;
                                          final mvpCov = widget.workbench
                                              .mvpBeatCoverage();
                                          final vsCov = widget.workbench
                                              .verticalSliceBeatCoverage();
                                          final doneCodes = isVs
                                              ? vsCov.completedBeatCodes
                                              : mvpCov.completedBeatCodes;
                                          final remCodes = isVs
                                              ? vsCov.incompleteBeatCodes
                                              : mvpCov.incompleteBeatCodes;
                                          final untouchedEpicCount = bp.beats
                                              .where(
                                                (b) => b.features.every(
                                                  (f) =>
                                                      f.isStable ||
                                                      f.isSuperseded,
                                                ),
                                              )
                                              .length;
                                          return Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              if (stableRows.isNotEmpty)
                                                InkWell(
                                                  key: const ValueKey(
                                                    'progressive_toggle_stable_drawer_btn',
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  onTap: () {
                                                    _rebuild(() {
                                                      _showProgressiveStableFeaturesDrawer =
                                                          !_showProgressiveStableFeaturesDrawer;
                                                    });
                                                  },
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: bgRecessed,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: borderSubtle,
                                                      ),
                                                    ),
                                                    child: Wrap(
                                                      spacing: 8,
                                                      runSpacing: 4,
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          _showProgressiveStableFeaturesDrawer
                                                              ? '▾ Hide Other Epics (${stableRows.length} Stable)'
                                                              : '▸ Other $untouchedEpicCount Epics:',
                                                          style: GoogleFonts
                                                              .jetBrainsMono(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color:
                                                                textSecondary,
                                                          ),
                                                        ),
                                                        if (!_showProgressiveStableFeaturesDrawer) ...[
                                                          if (doneCodes
                                                              .isNotEmpty)
                                                            Text(
                                                              '${doneCodes.length} Complete ✓ (${doneCodes.join(", ")})',
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    accentEmerald,
                                                              ),
                                                            ),
                                                          if (remCodes
                                                              .isNotEmpty)
                                                            Text(
                                                              '· ${remCodes.length} Remaining (${remCodes.join(", ")})',
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    textMuted,
                                                              ),
                                                            ),
                                                          Text(
                                                            '· Expand all ▾',
                                                            style: GoogleFonts
                                                                .jetBrainsMono(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: textMuted,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              if (bp.beats.isNotEmpty &&
                                                  _addingFeatureToBeatId ==
                                                      null)
                                                InkWell(
                                                  key: ValueKey(
                                                    'progressive_add_feat_btn_${bp.beats.first.id}',
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  onTap: () {
                                                    _rebuild(() {
                                                      _addingFeatureToBeatId =
                                                          bp.beats.first.id;
                                                      _progressiveNewFeatCtrl
                                                          .clear();
                                                    });
                                                  },
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: bgRecessed,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: borderSubtle,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '+ Add New Feature...',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                      if (_showProgressiveStableFeaturesDrawer &&
                                          stableRows.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: bgRecessed,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: borderSubtle,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              for (int bIdx = 0;
                                                  bIdx < bp.beats.length;
                                                  bIdx++)
                                                Builder(
                                                  builder: (context) {
                                                    final b = bp.beats[bIdx];
                                                    final epicCode =
                                                        'E${(bIdx + 1).toString().padLeft(2, '0')}';
                                                    final epicTitle =
                                                        _formatOutlineBeatDisplayTitle(
                                                      b.title,
                                                    ).toUpperCase();
                                                    final beatStableFeats = b
                                                        .features
                                                        .where(
                                                          (f) => f.isStable,
                                                        )
                                                        .toList();
                                                    if (beatStableFeats
                                                        .isEmpty) {
                                                      return const SizedBox
                                                          .shrink();
                                                    }
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 10,
                                                          ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            '$epicCode · $epicTitle (${beatStableFeats.length} BUILT)',
                                                            style: GoogleFonts
                                                                .jetBrainsMono(
                                                              fontSize: 9.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              letterSpacing:
                                                                  0.6,
                                                              color: textMuted,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 5,
                                                          ),
                                                          Container(
                                                            margin:
                                                                const EdgeInsets.only(
                                                                  left: 12,
                                                                ),
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  left: 10,
                                                                ),
                                                            decoration:
                                                                BoxDecoration(
                                                              border: Border(
                                                                left:
                                                                    BorderSide(
                                                                  color:
                                                                      borderSubtle,
                                                                  width: 1.5,
                                                                ),
                                                              ),
                                                            ),
                                                            child: Wrap(
                                                              spacing: 6,
                                                              runSpacing: 6,
                                                              children: [
                                                                for (final sf
                                                                    in beatStableFeats)
                                                                  InkWell(
                                                                    key: ValueKey(
                                                                      'progressive_toggle_feat_${sf.id}',
                                                                    ),
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                              4,
                                                                            ),
                                                                    onTap: () {
                                                                      widget
                                                                          .workbench
                                                                          .toggleProposedFeatureUpgradeOrStable(
                                                                        b.id,
                                                                        sf.id,
                                                                      );
                                                                      _rebuild(
                                                                        () {},
                                                                      );
                                                                    },
                                                                    child:
                                                                        Container(
                                                                      padding:
                                                                          const EdgeInsets.symmetric(
                                                                            horizontal:
                                                                                8,
                                                                            vertical:
                                                                                4,
                                                                          ),
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color:
                                                                            bgSurface,
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              4,
                                                                            ),
                                                                        border:
                                                                            Border.all(
                                                                          color:
                                                                              borderSubtle,
                                                                        ),
                                                                      ),
                                                                      child: Text(
                                                                        '+ ${sf.title}',
                                                                        style: GoogleFonts
                                                                            .inter(
                                                                          fontSize:
                                                                              11.5,
                                                                          color:
                                                                              textSecondary,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                              ],
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
                                      if (_addingFeatureToBeatId != null &&
                                          bp.beats.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (bp.beats.length > 1)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 6,
                                                ),
                                                child: Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    for (int bIdx = 0;
                                                        bIdx < bp.beats.length;
                                                        bIdx++)
                                                      Builder(
                                                        builder: (context) {
                                                          final b =
                                                              bp.beats[bIdx];
                                                          final isSelBeat =
                                                              _addingFeatureToBeatId ==
                                                              b.id;
                                                          final code =
                                                              'E${(bIdx + 1).toString().padLeft(2, '0')}';
                                                          return InkWell(
                                                            key: ValueKey(
                                                              'progressive_add_feat_target_epic_${b.id}',
                                                            ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                      4,
                                                                    ),
                                                            onTap: () {
                                                              _rebuild(() {
                                                                _addingFeatureToBeatId =
                                                                    b.id;
                                                              });
                                                            },
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical: 2,
                                                                  ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: isSelBeat
                                                                    ? bgRecessed
                                                                    : bgSurface,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                          4,
                                                                        ),
                                                                border:
                                                                    Border.all(
                                                                  color: isSelBeat
                                                                      ? textPrimary
                                                                          .withValues(
                                                                            alpha:
                                                                                0.45,
                                                                          )
                                                                      : borderSubtle,
                                                                ),
                                                              ),
                                                              child: Text(
                                                                '$code · ${b.title}',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize: 9.5,
                                                                  fontWeight: isSelBeat
                                                                      ? FontWeight
                                                                          .w700
                                                                      : FontWeight
                                                                          .w500,
                                                                  color: isSelBeat
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
                                              ),
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
                                                          'New $nextVer feature title...',
                                                      hintStyle:
                                                          GoogleFonts.inter(
                                                        fontSize: 11.5,
                                                        color: textMuted,
                                                      ),
                                                      filled: true,
                                                      fillColor: bgRecessed,
                                                      isDense: true,
                                                      contentPadding:
                                                          const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 7,
                                                      ),
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              5,
                                                            ),
                                                        borderSide: BorderSide(
                                                          color: borderSubtle,
                                                        ),
                                                      ),
                                                    ),
                                                    onSubmitted: (val) {
                                                      if (val.trim().isEmpty) {
                                                        return;
                                                      }
                                                      widget.workbench
                                                          .addCustomFeatureToProposedBeat(
                                                        _addingFeatureToBeatId!,
                                                        val.trim(),
                                                      );
                                                      _rebuild(() {
                                                        _addingFeatureToBeatId =
                                                            null;
                                                      });
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                TextButton(
                                                  onPressed: () {
                                                    final val =
                                                        _progressiveNewFeatCtrl
                                                            .text
                                                            .trim();
                                                    if (val.isNotEmpty) {
                                                      widget.workbench
                                                          .addCustomFeatureToProposedBeat(
                                                        _addingFeatureToBeatId!,
                                                        val,
                                                      );
                                                    }
                                                    _rebuild(() {
                                                      _addingFeatureToBeatId =
                                                          null;
                                                    });
                                                  },
                                                  child: Text(
                                                    'Add',
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: textPrimary,
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
                                const SizedBox(height: 12),

                                // Step 3: Ask Agent Prompt Bar
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
                                              'Want to adjust the $nextVer plan? Tell the Agent what to swap or add...',
                                          hintStyle: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: textMuted,
                                          ),
                                          filled: true,
                                          fillColor: bgSurface,
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 11,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            borderSide: BorderSide(
                                              color: borderSubtle,
                                            ),
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
                                        foregroundColor: textPrimary,
                                        backgroundColor: bgSurface,
                                        side: BorderSide(
                                          color: borderBright,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                      ),
                                      onPressed: widget.workbench.isAgentBusy
                                          ? null
                                          : () async {
                                              final text =
                                                  _progressiveDirectiveCtrl
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
                            );
                          },
                        ),
                  Builder(
                    builder: (context) {
                      final activeInbox = widget.workbench.featureInboxItems
                          .where(
                            (i) => i.status != FeatureInboxStatus.implemented,
                          )
                          .toList();
                      if (activeInbox.isEmpty) return const SizedBox.shrink();
                      final activePhase = widget.workbench.currentPhase;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          key: const ValueKey(
                            'progressive_release_inbox_queue_card',
                          ),
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
                                '📥 FEATURE INBOX QUEUE (${activeInbox.length}) — CLICK TO PULL INTO ${nextVer.toUpperCase()}',
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
                                  for (final item in activeInbox)
                                    Builder(
                                      builder: (context) {
                                        final isAutoIncluded = (item.status ==
                                                    FeatureInboxStatus
                                                        .scheduledForFuture ||
                                                (item.status ==
                                                        FeatureInboxStatus
                                                            .triagePending &&
                                                    item.releaseTimingMode ==
                                                        InboxReleaseTimingMode
                                                            .futureRelease)) &&
                                            item.targetFuturePhase.index <=
                                                activePhase.index;
                                        final title = item.futureCheckpointTitle
                                                .trim()
                                                .isNotEmpty
                                            ? item.futureCheckpointTitle.trim()
                                            : item.featureTitle;
                                        return InkWell(
                                          key: ValueKey(
                                            'progressive_pull_inbox_chip_${item.id}',
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          onTap: isAutoIncluded
                                              ? null
                                              : () {
                                                  widget.workbench
                                                      .pullInboxItemIntoReleaseDraft(
                                                    item.id,
                                                  );
                                                  _rebuild(() {});
                                                },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isAutoIncluded
                                                  ? accentEmerald.withValues(
                                                      alpha: 0.1,
                                                    )
                                                  : bgRecessed,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isAutoIncluded
                                                    ? accentEmerald.withValues(
                                                        alpha: 0.4,
                                                      )
                                                    : borderSubtle,
                                              ),
                                            ),
                                            child: Text(
                                              isAutoIncluded
                                                  ? '✓ Auto-Included in $nextVer · $title'
                                                  : '+ Pull into $nextVer · $title (${item.targetFuturePhase.shortName})',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: isAutoIncluded
                                                    ? accentEmerald
                                                    : textPrimary,
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
                        ),
                      );
                    },
                  ),
                        Builder(
                          builder: (context) {
                            final promotableExclusions =
                                <({int originalIdx, String text})>[];
                            for (int eIdx = 0;
                                eIdx < bp.explicitExclusions.length;
                                eIdx++) {
                              final exText = bp.explicitExclusions[eIdx].trim();
                              if (exText.isEmpty) continue;
                              final lower = exText.toLowerCase();
                              if (lower.startsWith('no ') ||
                                  lower.contains(': no ') ||
                                  lower.contains('] no ') ||
                                  lower.contains('[never]') ||
                                  lower.contains('[cut]')) {
                                continue;
                              }
                              promotableExclusions.add((
                                originalIdx: eIdx,
                                text: exText,
                              ));
                            }
                            if (promotableExclusions.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
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
                                      'DEFERRED BACKLOG (${promotableExclusions.length}) — CLICK TO PROMOTE INTO ${nextVer.toUpperCase()}',
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
                                        for (final entry
                                            in promotableExclusions)
                                          Builder(
                                            builder: (context) {
                                              final exText = entry.text;
                                              final activePhase = widget
                                                  .workbench
                                                  .currentPhase;
                                              final isUnlocked = ReleaseBlueprint
                                                  .isDeferredExclusionUnlockedInPhase(
                                                exText,
                                                activePhase,
                                              );
                                              final labelText = isUnlocked
                                                  ? '✦ UNLOCKED IN ${activePhase.shortName.toUpperCase()} · + Promote: $exText'
                                                  : '+ Promote: $exText';
                                              return InkWell(
                                                key: ValueKey(
                                                  'promote_exclusion_chip_${entry.originalIdx}',
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                                onTap: () {
                                                  widget.workbench
                                                      .promoteExclusionToNextRelease(
                                                    exText,
                                                  );
                                                  _rebuild(() {});
                                                },
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 9,
                                                        vertical: 5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: bgRecessed,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          5,
                                                        ),
                                                    border: Border.all(
                                                      color: isUnlocked
                                                          ? const Color(
                                                              0xFF10B981,
                                                            ).withValues(
                                                              alpha: 0.55,
                                                            )
                                                          : borderSubtle,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    labelText,
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 10.5,
                                                      fontWeight: isUnlocked
                                                          ? FontWeight.w700
                                                          : FontWeight.w600,
                                                      color: isUnlocked
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
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
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
        totalTasks += s.totalChecklistCount;
        for (final t in s.checklist) {
          totalStepsDone += t.children.isNotEmpty
              ? t.children.where((c) => c.completed).length
              : (t.completed ? 6 : 0);
        }
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
                    buildStatCol('${beats.length}', 'CORE EPICS', textPrimary),
                    buildStatCol('${allFeats.length}', 'FEATURES', textPrimary),
                    buildStatCol('$totalTasks', 'BUILD TASKS', textPrimary),
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
