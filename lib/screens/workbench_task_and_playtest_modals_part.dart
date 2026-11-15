part of 'release_workbench_screen.dart';

extension _WorkbenchTaskAndPlaytestModalsExt on _ReleaseWorkbenchScreenState {
  /// Copies the focused single-feature AI Coding Agent prompt to the clipboard.
  void _copyActiveFeaturePrompt(TierDocument feat) {
    final promptText = widget.workbench.buildActiveFeatureCodingAgentPrompt(
      feat.id,
    );
    Clipboard.setData(ClipboardData(text: promptText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied "${feat.title}" AI Coding Prompt to clipboard',
          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Opens the unified Playtest Run Sheet modal listing every active Feature's Playtest Gate,
  /// Tuning Variables, and `[GUARD]` rules in the current release with 1-click Pass & Flag actions.
  Future<void> _showPlaytestRunSheetModal(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return ListenableBuilder(
          listenable: widget.workbench,
          builder: (context, _) {
            final activeVer = widget.workbench.activeReleaseVersionTag;
            final rel = widget.workbench.activeRelease;
            final beats = widget.workbench.activeReleaseBeats;
            final showAllLiveFeatures =
                widget.workbench.releaseViewFilter == 'all';
            final releaseHasActiveFeats = beats.any(
              (b) => widget.workbench
                  .featuresForBeat(b.id)
                  .any((f) => widget.workbench.isFeatureActiveInRelease(f)),
            );
            List<TierDocument> displayedFeaturesForBeat(String beatId) {
              final allBeatFeats = widget.workbench.featuresForBeat(beatId);
              if (!showAllLiveFeatures && releaseHasActiveFeats) {
                return allBeatFeats
                    .where((f) => widget.workbench.isFeatureActiveInRelease(f))
                    .toList();
              }
              return allBeatFeats;
            }

            int totalFeats = 0;
            int passedFeats = 0;
            for (final b in beats) {
              for (final f in displayedFeaturesForBeat(b.id)) {
                totalFeats++;
                if (widget.workbench.getDocumentProgress(f.id) >= 100) {
                  passedFeats++;
                }
              }
            }

            return Dialog(
              key: const ValueKey('playtest_run_sheet_modal'),
              backgroundColor: bgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: borderSubtle),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 760,
                  maxHeight: 680,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Modal Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: bgRecessed,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        border: Border(bottom: BorderSide(color: borderSubtle)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PLAYTEST RUN SHEET · ${activeVer.toUpperCase()} GATE VERIFICATION',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.7,
                                    color: textMuted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  rel?.title ?? '$activeVer Playtest Checklist',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            key: const ValueKey('playtest_sheet_summary_badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Text(
                              '$passedFeats/$totalFeats GATES PASSED',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable Epic & Feature Gate Rows
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int bIdx = 0; bIdx < beats.length; bIdx++)
                              if (displayedFeaturesForBeat(beats[bIdx].id)
                                  .isNotEmpty) ...[
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: bIdx == 0 ? 0 : 14,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    'E${(bIdx + 1).toString().padLeft(2, '0')} · ${_formatOutlineBeatDisplayTitle(beats[bIdx].title).toUpperCase()}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.7,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                                for (final feat in displayedFeaturesForBeat(
                                  beats[bIdx].id,
                                ))
                                Builder(
                                  builder: (context) {
                                    final states =
                                        FeatureStateNode.getStatesForDocument(
                                      feat,
                                    );
                                    int cpIdx = states.lastIndexWhere(
                                      (s) => s.releaseVersion == activeVer,
                                    );
                                    if (cpIdx < 0 && states.isNotEmpty) {
                                      cpIdx = states.length - 1;
                                    }
                                    final cpNode =
                                        cpIdx >= 0 ? states[cpIdx] : null;
                                    final prog = widget.workbench
                                        .getDocumentProgress(feat.id);
                                    final isPassed = cpNode != null
                                        ? cpNode.isPlaytestPassed
                                        : prog >= 100;
                                    final openFixes =
                                        cpNode?.openFixItems ?? const <Subtask>[];

                                    return Container(
                                      key: ValueKey(
                                        'playtest_sheet_row_${feat.id}',
                                      ),
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: bgRecessed,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: borderSubtle,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 3,
                                                ),
                                                child: Icon(
                                                  isPassed
                                                      ? Icons
                                                          .check_circle_rounded
                                                      : Icons
                                                          .radio_button_unchecked_rounded,
                                                  size: 16,
                                                  color: isPassed
                                                      ? textSecondary
                                                      : textMuted,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Wrap(
                                                  spacing: 10,
                                                  runSpacing: 6,
                                                  alignment: WrapAlignment
                                                      .spaceBetween,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    Wrap(
                                                      spacing: 8,
                                                      runSpacing: 4,
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          _formatOutlineFeatureDisplayTitle(
                                                            feat.title,
                                                            beats[bIdx].title,
                                                            beatIndex: bIdx,
                                                          ),
                                                          style:
                                                              GoogleFonts.inter(
                                                            fontSize: 13.5,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: textPrimary,
                                                          ),
                                                        ),
                                                        Text(
                                                          '$prog%',
                                                          style: GoogleFonts
                                                              .jetBrainsMono(
                                                            fontSize: 10.5,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: isPassed
                                                                ? textSecondary
                                                                : textMuted,
                                                          ),
                                                        ),
                                                        if (openFixes
                                                            .isNotEmpty)
                                                          Container(
                                                            key: ValueKey(
                                                              'playtest_sheet_issues_badge_${feat.id}',
                                                            ),
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: accentAmber
                                                                  .withValues(
                                                                alpha: 0.14,
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                4,
                                                              ),
                                                            ),
                                                            child: Text(
                                                              'Issues (${openFixes.length})',
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color:
                                                                    accentAmber,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    if (cpNode != null)
                                                      Wrap(
                                                        spacing: 6,
                                                        runSpacing: 4,
                                                        crossAxisAlignment:
                                                            WrapCrossAlignment
                                                                .center,
                                                        children: [
                                                          InkWell(
                                                            key: ValueKey(
                                                              'playtest_sheet_pass_btn_${feat.id}',
                                                            ),
                                                            onTap: () {
                                                              if (isPassed) {
                                                                _reopenCheckpointPlaytestGate(
                                                                  feat,
                                                                  states,
                                                                  cpNode,
                                                                );
                                                              } else {
                                                                _completeAllCheckpointTasks(
                                                                  cpNode,
                                                                );
                                                                _rebuild(() {
                                                                  _awaitingPlaytestVerification
                                                                      .remove(
                                                                    cpNode.id,
                                                                  );
                                                                });
                                                                widget.workbench
                                                                    .updateFeatureStates(
                                                                  feat.id,
                                                                  states,
                                                                );
                                                              }
                                                            },
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              5,
                                                            ),
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 10,
                                                                vertical: 5,
                                                              ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: isPassed
                                                                    ? Colors
                                                                        .transparent
                                                                    : accentEmerald,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  5,
                                                                ),
                                                              ),
                                                              child: Text(
                                                                isPassed
                                                                    ? '✓ Gate Passed'
                                                                    : '✓ Pass Gate',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: isPassed
                                                                      ? textSecondary
                                                                      : (isDark
                                                                          ? const Color(
                                                                              0xFF06281E,
                                                                            )
                                                                          : Colors
                                                                              .white),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          if (isPassed)
                                                            InkWell(
                                                              key: ValueKey(
                                                                'playtest_sheet_reopen_btn_${feat.id}',
                                                              ),
                                                              onTap: () =>
                                                                  _reopenCheckpointPlaytestGate(
                                                                feat,
                                                                states,
                                                                cpNode,
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                5,
                                                              ),
                                                              child: Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 4,
                                                                ),
                                                                child: Text(
                                                                  '↺ Reopen Gate',
                                                                  style: GoogleFonts
                                                                      .jetBrainsMono(
                                                                    fontSize:
                                                                        10,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color:
                                                                        textSecondary,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          InkWell(
                                                            key: ValueKey(
                                                              'playtest_sheet_flag_btn_${feat.id}',
                                                            ),
                                                            onTap: () =>
                                                                _showLogPlaytestIssueDialog(
                                                              feat,
                                                              states,
                                                              cpIdx,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              5,
                                                            ),
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 6,
                                                                vertical: 4,
                                                              ),
                                                              child: Text(
                                                                'Flag Issue',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color:
                                                                      textSecondary,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          InkWell(
                                                            key: ValueKey(
                                                              'playtest_sheet_pivot_btn_${feat.id}',
                                                            ),
                                                            onTap: () {
                                                              widget.workbench
                                                                  .toggleSupersedeFeature(
                                                                feat.id,
                                                                pivotReason:
                                                                    'Pivoted during $activeVer playtest',
                                                              );
                                                            },
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              5,
                                                            ),
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 6,
                                                                vertical: 4,
                                                              ),
                                                              child: Text(
                                                                '⊗ Pivot',
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
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (cpNode != null)
                                            Builder(
                                              builder: (context) {
                                                final scopeItems =
                                                    SectionTextUtils
                                                        .resolveCheckpointInScope(
                                                  checkpointScope:
                                                      cpNode.coveredScope,
                                                  sections: feat.sections,
                                                  releaseVersion:
                                                      cpNode.releaseVersion,
                                                );
                                                final scopeHdr =
                                                    SectionTextUtils
                                                        .resolveInScopeHeaderLabel(
                                                  scopeItems,
                                                  releaseVersion:
                                                      cpNode.releaseVersion,
                                                  uppercase: false,
                                                );
                                                final resolvedDoneWhen =
                                                    SectionTextUtils
                                                        .formatConciseVerifySentence(
                                                  SectionTextUtils
                                                      .resolveCheckpointDoneWhen(
                                                    playtestGoalParam:
                                                        cpNode.parameters[
                                                            'playtestGoal'],
                                                    checkpointTrigger:
                                                        cpNode.trigger,
                                                    checkpointFeedback:
                                                        cpNode.feedback,
                                                    sections: feat.sections,
                                                    fallback:
                                                        cpNode.playtestCondition,
                                                  ),
                                                );
                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    if (scopeItems
                                                        .isNotEmpty) ...[
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        '$scopeHdr: ${scopeItems.join(' · ')}',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 11.5,
                                                          color: textMuted,
                                                        ),
                                                      ),
                                                    ],
                                                    if (cpNode.edgeCases
                                                        .isNotEmpty) ...[
                                                      const SizedBox(height: 8),
                                                      Wrap(
                                                        spacing: 12,
                                                        runSpacing: 4,
                                                        children: [
                                                          for (int gIdx = 0;
                                                              gIdx <
                                                                  cpNode
                                                                      .edgeCases
                                                                      .length;
                                                              gIdx++)
                                                            Builder(
                                                              builder:
                                                                  (context) {
                                                                final g = cpNode
                                                                        .edgeCases[
                                                                    gIdx];
                                                                final signedOff =
                                                                    cpNode.isGuardSignedOff(
                                                                  gIdx,
                                                                  g,
                                                                );
                                                                return InkWell(
                                                                  key: ValueKey(
                                                                    'playtest_sheet_guard_${feat.id}_$gIdx',
                                                                  ),
                                                                  onTap: () {
                                                                    cpNode.setGuardSignedOff(
                                                                      gIdx,
                                                                      g,
                                                                      !signedOff,
                                                                    );
                                                                    widget
                                                                        .workbench
                                                                        .updateFeatureStates(
                                                                      feat.id,
                                                                      states,
                                                                    );
                                                                  },
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    4,
                                                                  ),
                                                                  child:
                                                                      Padding(
                                                                    padding:
                                                                        const EdgeInsets
                                                                            .symmetric(
                                                                      horizontal:
                                                                          4,
                                                                      vertical:
                                                                          2,
                                                                    ),
                                                                    child: Text(
                                                                      '${signedOff ? '✓' : '○'} ${SectionTextUtils.formatTelegraphicGuardChip(g)}',
                                                                      style: GoogleFonts
                                                                          .jetBrainsMono(
                                                                        fontSize:
                                                                            9.5,
                                                                        color: signedOff
                                                                            ? accentEmerald
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
                                                    if (openFixes
                                                        .isNotEmpty) ...[
                                                      const SizedBox(height: 8),
                                                      for (final fix
                                                          in openFixes)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                            bottom: 4,
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              Expanded(
                                                                child: Text(
                                                                  fix.text
                                                                      .trim(),
                                                                  style: GoogleFonts
                                                                      .jetBrainsMono(
                                                                    fontSize:
                                                                        10.5,
                                                                    color:
                                                                        accentAmber,
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              InkWell(
                                                                key: ValueKey(
                                                                  'playtest_sheet_resolve_fix_${feat.id}_${fix.id}',
                                                                ),
                                                                onTap: () {
                                                                  fix.completed =
                                                                      true;
                                                                  widget
                                                                      .workbench
                                                                      .updateFeatureStates(
                                                                    feat.id,
                                                                    states,
                                                                  );
                                                                },
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  4,
                                                                ),
                                                                child: Padding(
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical: 2,
                                                                  ),
                                                                  child: Text(
                                                                    'Resolve ✓',
                                                                    style: GoogleFonts
                                                                        .jetBrainsMono(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      color:
                                                                          accentEmerald,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                    ],
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'Done When: $resolvedDoneWhen',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 12,
                                                        color: textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ],
                        ),
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
  }
}
