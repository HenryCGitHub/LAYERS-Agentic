import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'workbench/epic_domain_sheet.dart';
import 'workbench/feature_spec_sheet.dart';
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
        if (_specScrollController.hasClients) {
          _specScrollController.jumpTo(0);
        }
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
                      ],
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (feature == null) ...[
                          OutlinedButton.icon(
                            key: const ValueKey('copy_epic_brief_btn'),
                            onPressed: () => copyPromptWithToast(
                              context,
                              promptText: wb.activeEpicArchitecturePrompt(epic),
                              toastMessage:
                                  'Copied ${epic.code} Epic Architecture Brief',
                              isDark: isDark,
                            ),
                            icon: const Icon(Icons.copy_rounded, size: 14),
                            label: const Text(
                              'Copy Epic Brief',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          ElevatedButton(
                            key: const ValueKey(
                              'epic_inspect_first_feature_btn',
                            ),
                            onPressed: () {
                              final visible = wb.visibleFeaturesForEpic(epic);
                              if (visible.isNotEmpty) {
                                wb.selectFeature(epic.id, visible.first.id);
                              }
                            },
                            child: const Text(
                              'Inspect Child Feature →',
                              style: TextStyle(fontSize: 12),
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
      ],
    );
  }
}
