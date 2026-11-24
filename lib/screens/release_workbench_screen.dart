import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'workbench/epic_domain_sheet.dart';
import 'workbench/feature_spec_sheet.dart';
import 'workbench/floating_ai_refine_dock.dart';
import 'workbench/progressive_release_modal.dart';
import 'workbench/workbench_outliner_rail.dart';
import 'workbench/workbench_shared_widgets.dart';

export 'workbench/progressive_release_modal.dart'
    show showProgressiveReleaseCopilotDialog;


/// Stage 2: 4-tier `Project -> Release -> Epic -> Feature` Pure Structured Game Planner.
/// Expandable Epic -> Feature Outliner Rail + Centered Domain / Feature Spec Sheet.
class ReleaseWorkbenchScreen extends StatefulWidget {
  final WorkbenchProvider workbench;

  const ReleaseWorkbenchScreen({
    super.key,
    required this.workbench,
  });

  @override
  State<ReleaseWorkbenchScreen> createState() => _ReleaseWorkbenchScreenState();
}

class _ReleaseWorkbenchScreenState extends State<ReleaseWorkbenchScreen> {
  final ScrollController _specScrollController = ScrollController();

  String? _passGateHint;
  String? _lastSelectionKey;


  @override
  void dispose() {
    _specScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final epics = wb.activeReleaseEpics;
    final selectedEpic =
        wb.selectedEpicSpec ?? (epics.isNotEmpty ? epics.first : null);
    final selectedFeature = wb.selectedFeatureSpec;
    final selectionKey =
        '${wb.activeReleaseId}:${selectedEpic?.id}:${selectedFeature?.id}';
    final selectionChanged = _lastSelectionKey != selectionKey;
    if (selectionChanged) {
      _lastSelectionKey = selectionKey;
      _passGateHint = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_specScrollController.hasClients) return;
        _specScrollController.jumpTo(0);
      });
    }

    final isDark = wb.isDark;

    if (epics.isEmpty || selectedEpic == null) {
      return Container(
        color: AppTheme.bgBaseFor(isDark),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No Unreal Epics planned yet.',
                style: AppTheme.displayFont(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimaryFor(isDark),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => wb.setStage(WorkbenchStage.projectPitch),
                child: const Text('← Return to 1. Project Spec'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;
        return Container(
          color: AppTheme.bgBaseFor(isDark),
          child: Row(
            children: [
              if (isWide)
                WorkbenchOutlinerRail(
                  wb: wb,
                  epics: epics,
                  activeEpic: selectedEpic,
                  activeFeature: selectedFeature,
                ),
              Expanded(
                child: Column(
                  children: [
                    if (!isWide)
                      WorkbenchCompactSwitcherBar(
                        wb: wb,
                        epics: epics,
                        activeEpic: selectedEpic,
                        activeFeature: selectedFeature,
                      ),
                    Expanded(
                      child: _buildCenteredSpecWorkspace(
                        context,
                        wb,
                        epics,
                        selectedEpic,
                        selectedFeature,
                        selectionKey,
                        isNarrow: constraints.maxWidth < 480,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCenteredSpecWorkspace(
    BuildContext context,
    WorkbenchProvider wb,
    List<EpicSpec> epics,
    EpicSpec epic,
    FeatureSpec? feature,
    String selectionKey, {
    required bool isNarrow,
  }) {
    final isDark = wb.isDark;
    final border = AppTheme.borderFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);

    final relVer = wb.activeReleaseVersionTag;
    final isLockedBaseline = wb.isSelectedFeatureLockedBaseline;
    final rollup = wb.epicFeatureRollup(epic);
    final releaseRollup = wb.activeReleaseFeatureRollup;
    final visibleEpicFeatures = wb.visibleFeaturesForEpic(epic);
    final sliceRangeLabel = visibleEpicFeatures.isEmpty
        ? 'child Feature'
        : (visibleEpicFeatures.length == 1
            ? visibleEpicFeatures.first.code
            : '${visibleEpicFeatures.first.code}–${visibleEpicFeatures.last.code}');
    FeatureSpec? nextOpenFeature;
    for (final f in visibleEpicFeatures) {
      if (!f.isPassedForRelease(relVer)) {
        nextOpenFeature = f;
        break;
      }
    }
    final primaryTargetFeature = nextOpenFeature ??
        (visibleEpicFeatures.isNotEmpty ? visibleEpicFeatures.first : null);
    final primaryEpicActionLabel = primaryTargetFeature == null
        ? 'Open Epic'
        : (nextOpenFeature != null
            ? '${rollup.passed == 0 ? 'Start' : 'Continue'} ${primaryTargetFeature.code} →'
            : 'Inspect ${primaryTargetFeature.code} →');
    final projTitle = (wb.conceptDraft?.normalizedTitle ??
            wb.activeProject?.title ??
            'PROJECT')
        .trim();

    return Column(
      children: [
        // Breadcrumbs + Inspector Header Bar
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 12 : 20,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: AppTheme.bgPanelFor(isDark),
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clickable Breadcrumbs (Project / Release / Epic [/ Feature])
              Wrap(
                key: const ValueKey('stage2_breadcrumbs'),
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  InkWell(
                    key: const ValueKey('crumb_project'),
                    onTap: () => wb.setStage(WorkbenchStage.projectPitch),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 2,
                      ),
                      child: Text(
                        'Project ($projTitle)',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: muted,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  Text('/', style: TextStyle(fontSize: 11, color: muted)),
                  InkWell(
                    key: const ValueKey('crumb_release'),
                    onTap: () => wb.selectEpic(epics.first.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 2,
                      ),
                      child: Text(
                        'Release ($relVer)',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: muted,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  Text('/', style: TextStyle(fontSize: 11, color: muted)),
                  InkWell(
                    key: const ValueKey('crumb_epic'),
                    onTap: () => wb.selectEpic(epic.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 2,
                      ),
                      child: Text(
                        '${epic.code} · ${epic.title}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight:
                              feature == null ? FontWeight.w700 : FontWeight.w500,
                          color: feature == null ? primary : muted,
                          decoration: feature == null
                              ? TextDecoration.none
                              : TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  if (feature != null) ...[
                    Text('/', style: TextStyle(fontSize: 11, color: muted)),
                    InkWell(
                      key: const ValueKey('crumb_feature'),
                      onTap: () => wb.selectFeature(epic.id, feature.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 2,
                        ),
                        child: Text(
                          '${feature.code} · ${feature.title}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Header Title, Badges, Tab Switch & Primary Action
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: feature == null
                              ? [
                                  HeaderPill(
                                    label: 'EPIC · LARGE DOMAIN',
                                    color: cyan,
                                  ),
                                  HeaderPill(
                                    label: wb.unrealArchitectureMode.pillLabel,
                                    color: muted,
                                  ),
                                  HeaderPill(
                                    label:
                                        '${rollup.passed}/${rollup.total} Features Passed in $relVer',
                                    color: rollup.total > 0 &&
                                            rollup.passed == rollup.total
                                        ? green
                                        : muted,
                                  ),
                                ]
                              : [
                                  HeaderPill(
                                    label:
                                        'FEATURE · PLAYABLE SLICE (${feature.sliceTime})',
                                    color: muted,
                                  ),
                                  HeaderPill(
                                    label: isLockedBaseline
                                        ? '${feature.introducedIn} ✓ BASELINE LOCKED'
                                        : feature.isPassed
                                            ? 'PASSED ✓'
                                            : feature.executionModeLabel,
                                    color: feature.openFixesCount > 0
                                        ? red
                                        : (isLockedBaseline || feature.isPassed)
                                            ? green
                                            : cyan,
                                  ),
                                  if (relVer != 'v0.1' &&
                                      feature.introducedIn.trim() == relVer)
                                    HeaderPill(
                                      label: '[$relVer +NEW]',
                                      color: cyan,
                                    )
                                  else if (relVer != 'v0.1' &&
                                      feature.releaseDelta.trim().isNotEmpty)
                                    HeaderPill(
                                      label: '[$relVer +DELTA]',
                                      color: amber,
                                    ),
                                ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          feature == null
                              ? '${epic.code} · ${epic.title}'
                              : '${feature.code} · ${feature.title}',
                          style: AppTheme.displayFont(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                        if (feature == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              'Auto-included in $sliceRangeLabel prompts — no separate Epic copy needed.',
                              style: TextStyle(fontSize: 12, color: secondary),
                            ),
                          ),
                      ],
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (feature == null) ...[
                          PopupMenuButton<String>(
                            key: const ValueKey('epic_more_menu_btn'),
                            tooltip: 'Optional Architecture Brief actions',
                            color: AppTheme.bgSurfaceRaisedFor(isDark),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: border),
                            ),
                            onSelected: (val) {
                              if (val == 'preview_brief') {
                                showCoPilotPromptPreviewDialog(
                                  context,
                                  title:
                                      '${epic.code} · ${epic.title} — Epic Architecture Brief',
                                  promptText:
                                      wb.activeEpicArchitecturePrompt(epic),
                                  readableText:
                                      wb.activeEpicReadableBrief(epic),
                                  isDark: isDark,
                                );
                              } else if (val == 'copy_brief') {
                                copyPromptWithToast(
                                  context,
                                  promptText:
                                      wb.activeEpicArchitecturePrompt(epic),
                                  toastMessage:
                                      'Copied ${epic.code} Architecture Brief (optional)',
                                  isDark: isDark,
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem<String>(
                                key: const ValueKey('preview_epic_brief_btn'),
                                value: 'preview_brief',
                                child: Text(
                                  'Inspect Architecture Brief (Optional)',
                                  style: TextStyle(fontSize: 12, color: primary),
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'copy_brief',
                                child: Text(
                                  'Copy Architecture Brief (Advanced)',
                                  style:
                                      TextStyle(fontSize: 12, color: secondary),
                                ),
                              ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.bgSurfaceRaisedFor(isDark),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusSm),
                                border: Border.all(color: border),
                              ),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                size: 16,
                                color: muted,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            key: const ValueKey(
                              'epic_inspect_first_feature_btn',
                            ),
                            onPressed: primaryTargetFeature == null
                                ? null
                                : () => wb.selectFeature(
                                      epic.id,
                                      primaryTargetFeature.id,
                                    ),
                            child: Text(
                              primaryEpicActionLabel,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            key: const ValueKey('copy_copilot_prompt_btn'),
                            onPressed: () => copyPromptWithToast(
                              context,
                              promptText:
                                  wb.activeFeatureBuildPrompt(epic, feature),
                              toastMessage:
                                  'Copied ${feature.code} CoPilot prompt to clipboard',
                              isDark: isDark,
                            ),
                            icon: Icon(
                              feature.openFixesCount > 0
                                  ? Icons.build_rounded
                                  : Icons.bolt_rounded,
                              size: 15,
                            ),
                            label: Text(
                              feature.openFixesCount > 0
                                  ? '🔧 Copy CoPilot [FIX] Prompt (${feature.openFixesCount})'
                                  : (relVer != 'v0.1' &&
                                          (feature.releaseDelta.trim().isNotEmpty ||
                                              feature.introducedIn.trim() == relVer)
                                      ? '⚡ Copy CoPilot Delta Prompt'
                                      : '⚡ Copy CoPilot Prompt'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('preview_copilot_prompt_btn'),
                            onPressed: () => showCoPilotPromptPreviewDialog(
                              context,
                              title:
                                  '${feature.code} · ${feature.title} — CoPilot Prompt',
                              promptText:
                                  wb.activeFeatureBuildPrompt(epic, feature),
                              readableText:
                                  wb.activeFeatureReadablePrompt(epic, feature),
                              isDark: isDark,
                            ),
                            icon: const Icon(Icons.visibility_outlined, size: 14),
                            label: const Text(
                              'Preview',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          if (!isLockedBaseline) ...[
                            if (feature.isPassed)
                              OutlinedButton.icon(
                                key: const ValueKey('reopen_feature_btn'),
                                onPressed: () =>
                                    wb.reopenFeature(epic.id, feature.id),
                                icon: const Icon(Icons.replay, size: 15),
                                label: const Text(
                                  'Reopen Feature',
                                  style: TextStyle(fontSize: 12),
                                ),
                              )
                            else
                              ElevatedButton.icon(
                                key: const ValueKey('pass_feature_btn'),
                                onPressed: () {
                                  final passed = wb.passFeature(
                                    epic.id,
                                    feature.id,
                                  );
                                  if (!passed) {
                                    setState(() {
                                      _passGateHint = feature.openFixes.isNotEmpty
                                          ? 'Resolve all open [FIX] notes before passing this Feature.'
                                          : 'Check every Playtest Gate item before passing this Feature.';
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      wb.canPassFeature(feature)
                                          ? green
                                          : AppTheme.bgSurfaceRaisedFor(isDark),
                                  foregroundColor: wb.canPassFeature(feature)
                                      ? Colors.black
                                      : muted,
                                  side: BorderSide(
                                    color: wb.canPassFeature(feature)
                                        ? green
                                        : border,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  size: 15,
                                ),
                                label: const Text(
                                  'Pass Feature ✓',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Release Complete progression banner once every Feature passes
        if (wb.isActiveReleaseComplete)
          Container(
            key: const ValueKey('release_complete_banner'),
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 12 : 20,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(color: green.withValues(alpha: 0.35)),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                Text(
                  '✓ $relVer Complete (${releaseRollup.passed}/${releaseRollup.total} Slices Passed)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: green,
                  ),
                ),
                OutlinedButton(
                  key: const ValueKey('release_complete_plan_next_btn'),
                  onPressed: wb.isDraftingProgressive
                      ? null
                      : () => showProgressiveReleaseCopilotDialog(context, wb),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: green,
                    side: BorderSide(color: green.withValues(alpha: 0.65)),
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                  child: Text(
                    '${wb.nextReleaseActionLabel} →',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),

        // Read-Only Baseline Banner when viewing prior-release Feature in v0.2+
        if (feature != null && isLockedBaseline)
          Container(
            key: const ValueKey('locked_baseline_banner'),
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 12 : 20,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: cyan.withValues(alpha: 0.08),
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                Text(
                  '${feature.code} shipped in ${feature.introducedIn} baseline inside ${epic.code}. Viewing read-only baseline for $relVer.',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
                OutlinedButton(
                  key: const ValueKey('open_in_baseline_btn'),
                  onPressed: wb.openSelectedFeatureInBaselineRelease,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                  child: Text(
                    'Open in ${feature.introducedIn} →',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),

        // Main Scrollable Workspace Body
        Expanded(
          child: SingleChildScrollView(
            controller: _specScrollController,
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 12 : 24,
              vertical: 20,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: feature == null
                    ? EpicDomainSheet(
                        workbench: wb,
                        epic: epic,
                        isDark: isDark,
                        selectionKey: selectionKey,
                      )
                    : FeatureSpecSheet(
                        workbench: wb,
                        epic: epic,
                        feature: feature,
                        isLockedBaseline: isLockedBaseline,
                        isDark: isDark,
                        selectionKey: selectionKey,
                        passGateHint: _passGateHint,
                      ),
              ),
            ),
          ),
        ),

        // Scoped Stage 2 Floating AI Refine Dock (hidden only on locked baselines)
        if (feature == null || !isLockedBaseline)
          FloatingAiRefineDock(
            isDark: isDark,
            targetBadge: feature == null
                ? 'AI · ${epic.code}'
                : 'AI · ${feature.code}',
            hintText: feature == null
                ? 'Refine ${epic.code} owners, states, or domain cuts with Hydrogen...'
                : 'Refine ${feature.code} controls, tuning (cm / cm/s), cues, or PIE checks...',
            isBusy: wb.isRefiningStage2,
            canUndo: wb.canUndoStage2Edit,
            summaryText: wb.lastStage2RefineSummary,
            errorText: wb.stage2RefineError,
            quickPrompts: feature == null
                ? const [
                    'Add shared /Game/ owner',
                    'Add interrupt rule',
                    'Add scope cut',
                  ]
                : const [
                    'Set DashDistance to 550 cm',
                    'Add impact VFX & SFX cue',
                    'Add PIE gate check',
                  ],
            inputKey: const ValueKey('stage2_ai_refine_input'),
            applyBtnKey: const ValueKey('stage2_ai_refine_apply_btn'),
            undoBtnKey: const ValueKey('stage2_ai_refine_undo_btn'),
            ideasBtnKey: const ValueKey('stage2_ai_ideas_btn'),
            ideasStripKey: const ValueKey('stage2_ai_ideas_strip'),
            onApply: (instruction) async {
              if (feature == null) {
                await wb.applyStage2EpicRefine(epic.id, instruction);
              } else {
                await wb.applyStage2FeatureRefine(
                  epic.id,
                  feature.id,
                  instruction,
                );
              }
            },
            onUndo: wb.undoStage2Edit,
            onDismissError: wb.dismissStage2RefineError,
          ),
      ],
    );
  }
}
