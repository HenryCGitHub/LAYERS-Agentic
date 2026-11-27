import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/epic_spec.dart';
import '../../models/tier_document.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'floating_ai_refine_dock.dart';
import 'plain_doc_widgets.dart';
import 'workbench_shared_widgets.dart';

/// Flat 700px single-column Release Spec view (`TierType.release`).
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
        if (firstOpenFeat == null && !f.isPassedForRelease(relVer)) {
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
    final amber = AppTheme.accentAmberFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);

    final releaseGoal = (releaseDoc.sections['goal'] ?? '').trim();
    final releaseDoneWhen = (releaseDoc.sections['doneWhen'] ?? '').trim();
    final primaryAction = _resolvePrimaryAction(wb, epicDocs, relVer);

    final epicsParsed = <EpicSpec>[
      for (int i = 0; i < epicDocs.length; i++)
        EpicSpec.fromDocument(epicDocs[i], indexHint: i),
    ];

    final deltaRows = <({EpicSpec epic, FeatureSpec feat})>[];
    final newSliceRows = <({EpicSpec epic, FeatureSpec feat})>[];
    final baselineRows = <({EpicSpec epic, FeatureSpec feat})>[];

    if (relVer != 'v0.1') {
      for (final ep in epicsParsed) {
        for (final feat in wb.visibleFeaturesForEpic(ep)) {
          if (feat.releaseDelta.trim().isNotEmpty) {
            deltaRows.add((epic: ep, feat: feat));
          }
          if (feat.introducedIn.trim() == relVer) {
            newSliceRows.add((epic: ep, feat: feat));
          } else if (feat.isLockedBaselineInRelease(relVer)) {
            baselineRows.add((epic: ep, feat: feat));
          }
        }
      }
    }

    return KeyedSubtree(
      key: ValueKey('release_sheet_${releaseDoc.id}'),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'RELEASE · $relVer · ${epicsParsed.length} ${epicsParsed.length == 1 ? 'EPIC' : 'EPICS'} · ${rollup.passed}/${rollup.total} PASSED',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.9,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      PlainEditableLineField(
                        fieldKey: const ValueKey('release_title_input'),
                        value: releaseDoc.title,
                        isDark: isDark,
                        hintText: 'Release title...',
                        style: AppTheme.displayFont(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                        onCommit: (val) =>
                            wb.updateReleaseSpec(releaseDoc.id, title: val),
                      ),
                      const SizedBox(height: 16),
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
                        ],
                      ),
                      PlainDocDivider(isDark: isDark, spacing: 22),

                      PlainSectionHeader(title: 'Goal', isDark: isDark),
                      const SizedBox(height: 8),
                      PlainEditableLineField(
                        fieldKey: const ValueKey('release_goal_input'),
                        value: releaseGoal,
                        isDark: isDark,
                        multiLine: true,
                        minLines: 2,
                        allowEmpty: true,
                        hintText: 'One plain sentence for what this release ships...',
                        onCommit: (val) =>
                            wb.updateReleaseSpec(releaseDoc.id, goal: val),
                      ),
                      const SizedBox(height: 20),

                      PlainSectionHeader(
                        title: 'Done When (PIE Gate)',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 8),
                      PlainEditableLineField(
                        fieldKey: const ValueKey('release_done_when_input'),
                        value: releaseDoneWhen,
                        isDark: isDark,
                        multiLine: true,
                        minLines: 2,
                        allowEmpty: true,
                        hintText: '[Player Action] -> [Observable Viewport Result]',
                        onCommit: (val) =>
                            wb.updateReleaseSpec(releaseDoc.id, doneWhen: val),
                      ),
                      const SizedBox(height: 24),

                      PlainSectionHeader(
                        title: 'In Scope',
                        isDark: isDark,
                        trailing: PlainTextLink(
                          key: const ValueKey('release_add_epic_btn'),
                          label: _addingEpic ? 'Cancel' : '+ Add epic',
                          isDark: isDark,
                          color: _addingEpic ? textMuted : focal,
                          onTap: () =>
                              setState(() => _addingEpic = !_addingEpic),
                        ),
                      ),
                      if (_addingEpic) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: border, width: 1),
                            ),
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
                                children: [
                                  PlainPrimaryButton(
                                    key: const ValueKey(
                                      'release_new_epic_save_btn',
                                    ),
                                    label: 'Create Epic',
                                    isDark: isDark,
                                    onPressed: () {
                                      final title = _newEpicTitleCtrl.text.trim();
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
                      const SizedBox(height: 6),

                      if (relVer == 'v0.1') ...[
                        if (epicsParsed.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No epics in this release yet.',
                              style: TextStyle(fontSize: 13, color: textMuted),
                            ),
                          ),
                        for (final ep in epicsParsed)
                          _buildV01EpicScopeGroup(
                            wb,
                            ep,
                            relVer,
                            isDark,
                            border,
                            textPrimary,
                            textSecondary,
                            textMuted,
                            green,
                            red,
                          ),
                      ] else ...[
                        if (deltaRows.isNotEmpty) ...[
                          _buildSubgroupLabel('+DELTA UPGRADES', amber),
                          for (final row in deltaRows)
                            _buildFlatSliceRow(
                              wb: wb,
                              epic: row.epic,
                              feat: row.feat,
                              relVer: relVer,
                              subtitle: '+DELTA: ${row.feat.releaseDelta}',
                              subtitleColor: amber,
                              isDark: isDark,
                              border: border,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              green: green,
                              red: red,
                            ),
                          const SizedBox(height: 12),
                        ],
                        if (newSliceRows.isNotEmpty) ...[
                          _buildSubgroupLabel('+NEW $relVer FEATURES', cyan),
                          for (final row in newSliceRows)
                            _buildFlatSliceRow(
                              wb: wb,
                              epic: row.epic,
                              feat: row.feat,
                              relVer: relVer,
                              subtitle: row.feat.goal,
                              subtitleColor: textSecondary,
                              isDark: isDark,
                              border: border,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              green: green,
                              red: red,
                            ),
                          const SizedBox(height: 12),
                        ],
                        if (baselineRows.isNotEmpty) ...[
                          _buildSubgroupLabel('LOCKED BASELINE', textMuted),
                          for (final row in baselineRows)
                            _buildFlatSliceRow(
                              wb: wb,
                              epic: row.epic,
                              feat: row.feat,
                              relVer: relVer,
                              subtitle: row.feat.isPassed
                                  ? 'Shipped ${row.feat.introducedIn} · ${row.epic.code} ${row.epic.title}'
                                  : 'Locked ${row.feat.introducedIn} baseline (open in ${row.feat.introducedIn}) · ${row.epic.code} ${row.epic.title}',
                              subtitleColor: textMuted,
                              mutedRow: true,
                              isDark: isDark,
                              border: border,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              green: green,
                              red: red,
                            ),
                        ],
                        const SizedBox(height: 12),
                        _buildSubgroupLabel('EPICS IN $relVer', textMuted),
                        for (final ep in epicsParsed)
                          InkWell(
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              wb.selectEpic(ep.id);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: border, width: 1),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    ep.code,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: textMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      ep.title,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${wb.epicFeatureRollup(ep).passed}/${wb.epicFeatureRollup(ep).total}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11.5,
                                      color: textMuted,
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
            ),
          ),
          FloatingAiRefineDock(
            isDark: isDark,
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

  Widget _buildSubgroupLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }

  Widget _buildV01EpicScopeGroup(
    WorkbenchProvider wb,
    EpicSpec ep,
    String relVer,
    bool isDark,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
    Color green,
    Color red,
  ) {
    final visible = wb.visibleFeaturesForEpic(ep);
    final epRollup = wb.epicFeatureRollup(ep);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              FocusManager.instance.primaryFocus?.unfocus();
              wb.selectEpic(ep.id);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    ep.code,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ep.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${epRollup.passed}/${epRollup.total}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: epRollup.openFixes > 0
                          ? red
                          : (epRollup.total > 0 &&
                                    epRollup.passed == epRollup.total
                                ? green
                                : textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (ep.goal.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 34, bottom: 6),
              child: Text(
                ep.goal,
                style: TextStyle(fontSize: 12.5, color: textSecondary),
              ),
            ),
          for (final feat in visible)
            InkWell(
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                wb.selectFeature(ep.id, feat.id);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(34, 4, 4, 4),
                child: Row(
                  children: [
                    Text(
                      feat.openFixesCount > 0
                          ? '●'
                          : (feat.isPassedForRelease(relVer) ? '✓' : '○'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: feat.openFixesCount > 0
                            ? red
                            : (feat.isPassedForRelease(relVer)
                                  ? green
                                  : textMuted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      feat.code,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        feat.title,
                        style: TextStyle(fontSize: 13, color: textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFlatSliceRow({
    required WorkbenchProvider wb,
    required EpicSpec epic,
    required FeatureSpec feat,
    required String relVer,
    required String subtitle,
    required Color subtitleColor,
    bool mutedRow = false,
    required bool isDark,
    required Color border,
    required Color textPrimary,
    required Color textMuted,
    required Color green,
    required Color red,
  }) {
    final passedInView =
        mutedRow ? feat.isPassed : feat.isPassedForRelease(relVer);
    final glyph = feat.openFixesCount > 0
        ? (symbol: '●', color: red)
        : (passedInView
              ? (symbol: '✓', color: green)
              : (symbol: '○', color: textMuted));

    return InkWell(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        wb.selectFeature(epic.id, feat.id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                glyph.symbol,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: glyph.color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${feat.code} ${feat.title}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: mutedRow ? textMuted : textPrimary,
                    ),
                  ),
                  if (subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: subtitleColor),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
