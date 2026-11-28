import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/epic_spec.dart';
import '../../models/tier_document.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'floating_ai_refine_dock.dart';
import 'monday_release_table.dart';
import 'plain_doc_widgets.dart';
import 'workbench_shared_widgets.dart';

/// Full-width Monday-style Release workspace (`TierType.release`) hosting the
/// Release header, Goal / Done When strip, grouped Epic/Feature table, and
/// pinned Stage 2 AI Refine dock.
class ReleaseSpecSheet extends StatefulWidget {
  final WorkbenchProvider workbench;

  const ReleaseSpecSheet({super.key, required this.workbench});

  @override
  State<ReleaseSpecSheet> createState() => _ReleaseSpecSheetState();
}

class _ReleaseSpecSheetState extends State<ReleaseSpecSheet> {
  bool _addingEpic = false;
  final TextEditingController _newEpicTitleCtrl = TextEditingController();
  final TextEditingController _newEpicGoalCtrl = TextEditingController();
  final TextEditingController _refineCtrl = TextEditingController();

  @override
  void didUpdateWidget(covariant ReleaseSpecSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workbench.activeReleaseId != widget.workbench.activeReleaseId) {
      _addingEpic = false;
      _newEpicTitleCtrl.clear();
      _newEpicGoalCtrl.clear();
    }
  }

  @override
  void dispose() {
    _newEpicTitleCtrl.dispose();
    _newEpicGoalCtrl.dispose();
    _refineCtrl.dispose();
    super.dispose();
  }

  ({String label, VoidCallback onPressed}) _resolvePrimaryAction(
    WorkbenchProvider wb,
    List<TierDocument> epicDocs,
    String relVer,
  ) {
    EpicSpec? firstFixEpic;
    FeatureSpec? firstFixFeat;
    EpicSpec? firstOpenEpic;
    FeatureSpec? firstOpenFeat;

    for (int i = 0; i < epicDocs.length; i++) {
      final ep = EpicSpec.fromDocument(epicDocs[i], indexHint: i);
      final visible = wb.visibleFeaturesForEpic(ep);
      for (final f in visible) {
        if (firstFixFeat == null && f.openFixesCount > 0) {
          firstFixEpic = ep;
          firstFixFeat = f;
        }
        if (firstOpenFeat == null && !f.isResolvedForRelease(relVer)) {
          firstOpenEpic = ep;
          firstOpenFeat = f;
        }
      }
    }

    if (firstFixEpic != null && firstFixFeat != null) {
      final epId = firstFixEpic.id;
      final fId = firstFixFeat.id;
      return (
        label: 'Fix ${firstFixFeat.code} →',
        onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          wb.selectFeature(epId, fId);
        },
      );
    }
    if (firstOpenEpic != null && firstOpenFeat != null) {
      final epId = firstOpenEpic.id;
      final fId = firstOpenFeat.id;
      return (
        label: 'Continue ${firstOpenFeat.code} →',
        onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          wb.selectFeature(epId, fId);
        },
      );
    }
    final nextVer = wb.nextReleaseVersionTag;
    return (
      label: 'Plan $nextVer →',
      onPressed: () {
        FocusManager.instance.primaryFocus?.unfocus();
        wb.openInPagePlanNextRelease();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final isDark = wb.isDark;
    final releaseDoc = wb.activeRelease;
    final epicDocs = wb.activeReleaseEpicDocs;
    final relVer = wb.activeReleaseVersionTag;
    final rollup = wb.activeReleaseFeatureRollup;

    if (releaseDoc == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Select or launch a release from Project Brief first.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textMutedFor(isDark),
            ),
          ),
        ),
      );
    }

    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);

    final releaseGoal = (releaseDoc.sections['goal'] ?? '').trim();
    final releaseDoneWhen = (releaseDoc.sections['doneWhen'] ?? '').trim();
    final primaryAction = _resolvePrimaryAction(wb, epicDocs, relVer);

    final epicsParsed = <EpicSpec>[
      for (int i = 0; i < epicDocs.length; i++)
        EpicSpec.fromDocument(epicDocs[i], indexHint: i),
    ];

    final progressRatio = rollup.total == 0
        ? 0.0
        : (rollup.passed / rollup.total).clamp(0.0, 1.0);
    final showBackgroundAiDock = wb.activeDocPage == WorkbenchDocPage.releaseSpec;

    return KeyedSubtree(
      key: ValueKey('release_sheet_${releaseDoc.id}'),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border, width: 1)),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kPlainDocTableMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'RELEASE · $relVer · ${epicsParsed.length} ${epicsParsed.length == 1 ? 'EPIC' : 'EPICS'} · ${rollup.passed}/${rollup.total} PASSED',
                            key: const ValueKey('release_header_summary'),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.9,
                              color: rollup.openFixes > 0
                                  ? red
                                  : (rollup.total > 0 &&
                                            rollup.passed == rollup.total
                                        ? green
                                        : textMuted),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progressRatio,
                              minHeight: 5,
                              backgroundColor: AppTheme.bgInsetFor(isDark),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                rollup.total > 0 &&
                                        rollup.passed == rollup.total
                                    ? green
                                    : focal,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    PlainEditableLineField(
                      fieldKey: const ValueKey('release_title_input'),
                      value: releaseDoc.title,
                      isDark: isDark,
                      hintText: 'Release title...',
                      style: AppTheme.displayFont(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                      onCommit: (val) =>
                          wb.updateReleaseSpec(releaseDoc.id, title: val),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        PlainPrimaryButton(
                          key: const ValueKey('release_primary_action_btn'),
                          label: primaryAction.label,
                          onPressed: primaryAction.onPressed,
                          isDark: isDark,
                        ),
                        PlainPrimaryButton(
                          key: const ValueKey('release_preview_spec_btn'),
                          label: 'Preview Spec',
                          outlined: true,
                          isDark: isDark,
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            showCoPilotPromptPreviewDialog(
                              context,
                              title: '$relVer Release Spec',
                              promptText: wb.buildReleaseSpecMarkdown(
                                releaseDoc.id,
                              ),
                              isDark: isDark,
                            );
                          },
                        ),
                        PlainTextLink(
                          key: const ValueKey('release_add_epic_btn'),
                          label: _addingEpic ? 'Cancel' : '+ Add epic',
                          isDark: isDark,
                          color: _addingEpic ? textMuted : focal,
                          onTap: () =>
                              setState(() => _addingEpic = !_addingEpic),
                        ),
                        if (epicsParsed.isNotEmpty)
                          PlainTextLink(
                            key: const ValueKey(
                              'release_quick_add_feature_btn',
                            ),
                            label: '+ Add feature',
                            isDark: isDark,
                            color: focal,
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              wb.quickAddSliceToActiveRelease();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kPlainDocTableMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PlainTwoColumnLayout(
                        layoutKey: const ValueKey(
                          'release_contract_two_col_row',
                        ),
                        leftFlex: 6,
                        rightFlex: 6,
                        columnGap: 24,
                        left: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PlainSectionHeader(title: 'Goal', isDark: isDark),
                            const SizedBox(height: 6),
                            PlainEditableLineField(
                              fieldKey: const ValueKey('release_goal_input'),
                              value: releaseGoal,
                              isDark: isDark,
                              multiLine: true,
                              minLines: 1,
                              allowEmpty: true,
                              hintText:
                                  'One plain sentence for what this release ships...',
                              onCommit: (val) =>
                                  wb.updateReleaseSpec(releaseDoc.id, goal: val),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                        right: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PlainSectionHeader(
                              title: 'Done When (PIE Gate)',
                              isDark: isDark,
                            ),
                            const SizedBox(height: 6),
                            PlainEditableLineField(
                              fieldKey: const ValueKey(
                                'release_done_when_input',
                              ),
                              value: releaseDoneWhen,
                              isDark: isDark,
                              multiLine: true,
                              minLines: 1,
                              allowEmpty: true,
                              hintText:
                                  '[Player Action] -> [Observable Viewport Result]',
                              onCommit: (val) => wb.updateReleaseSpec(
                                releaseDoc.id,
                                doneWhen: val,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      if (_addingEpic) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.bgPanelFor(isDark),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMd,
                            ),
                            border: Border.all(color: border, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                key: const ValueKey(
                                  'release_new_epic_title_input',
                                ),
                                controller: _newEpicTitleCtrl,
                                autofocus: true,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: textPrimary,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Epic title (2–5 plain words)...',
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: textMuted,
                                  ),
                                  border: UnderlineInputBorder(
                                    borderSide: BorderSide(color: border),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: focal),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                key: const ValueKey(
                                  'release_new_epic_goal_input',
                                ),
                                controller: _newEpicGoalCtrl,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textSecondary,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Optional 1-sentence domain goal...',
                                  hintStyle: TextStyle(
                                    fontSize: 12.5,
                                    color: textMuted,
                                  ),
                                  border: UnderlineInputBorder(
                                    borderSide: BorderSide(color: border),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: focal),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  PlainTextLink(
                                    label: 'Cancel',
                                    isDark: isDark,
                                    color: textMuted,
                                    onTap: () =>
                                        setState(() => _addingEpic = false),
                                  ),
                                  const SizedBox(width: 12),
                                  PlainPrimaryButton(
                                    key: const ValueKey(
                                      'release_new_epic_save_btn',
                                    ),
                                    label: 'Create Epic',
                                    isDark: isDark,
                                    onPressed: () {
                                      final title =
                                          _newEpicTitleCtrl.text.trim();
                                      if (title.isEmpty) return;
                                      wb.addEpicToActiveRelease(
                                        title: title,
                                        goal: _newEpicGoalCtrl.text.trim(),
                                      );
                                      setState(() {
                                        _addingEpic = false;
                                        _newEpicTitleCtrl.clear();
                                        _newEpicGoalCtrl.clear();
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      MondayReleaseTable(
                        workbench: wb,
                        epics: epicsParsed,
                        releaseVersion: relVer,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showBackgroundAiDock)
            FloatingAiRefineDock(
              isDark: isDark,
              maxWidth: kPlainDocTableMaxWidth,
              targetBadge: 'AI · $relVer',
              hintText: 'Refine $relVer Goal, Done When, or Epic scope...',
              isBusy: wb.isRefiningStage2,
              canUndo: wb.canUndoStage2Edit,
              summaryText: wb.lastStage2RefineSummary,
              errorText: wb.stage2RefineError,
              quickPrompts: const <String>[
                'Tighten Done When into observable PIE checks',
                'Trim scope to fastest playable prototype',
                'Focus Goal on core combat loop feel',
              ],
              externalController: _refineCtrl,
              inputKey: const ValueKey('stage2_ai_refine_input'),
              applyBtnKey: const ValueKey('stage2_ai_refine_apply_btn'),
              undoBtnKey: const ValueKey('stage2_ai_refine_undo_btn'),
              ideasBtnKey: const ValueKey('stage2_ai_ideas_btn'),
              ideasStripKey: const ValueKey('stage2_ai_ideas_strip'),
              onApply: (instruction) =>
                  wb.applyStage2ReleaseRefine(releaseDoc.id, instruction),
              onUndo: wb.undoStage2Edit,
              onDismissError: wb.dismissStage2RefineError,
            ),
        ],
      ),
    );
  }
}
