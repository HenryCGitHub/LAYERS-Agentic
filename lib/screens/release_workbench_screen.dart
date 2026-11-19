import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'widgets/godot_bridge_modals.dart';

part 'workbench_progressive_planner_part.dart';

/// Stage 2: 4-tier `Project -> Release -> Epic -> Feature` Pure Structured Game Planner.
/// Expandable Epic -> Feature Outliner Rail + Centered Domain / Feature Spec Sheet + AI Build Prompt tab.
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
  final TextEditingController _fixInputController = TextEditingController();
  final TextEditingController _newFeatureTitleController =
      TextEditingController();
  final TextEditingController _newFeatureGoalController =
      TextEditingController();
  final ScrollController _specScrollController = ScrollController();

  bool _showAddFeatureForm = false;
  String? _passGateHint;
  String? _lastSelectionKey;
  bool? _lastRawMode;

  @override
  void dispose() {
    _fixInputController.dispose();
    _newFeatureTitleController.dispose();
    _newFeatureGoalController.dispose();
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
    final rawModeChanged =
        _lastRawMode != null && _lastRawMode != wb.showRawEpicPayload;
    if (selectionChanged) {
      _lastSelectionKey = selectionKey;
      _showAddFeatureForm = false;
      _passGateHint = null;
    }
    _lastRawMode = wb.showRawEpicPayload;
    if (selectionChanged || rawModeChanged) {
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
                'No Godot Epics planned yet.',
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
                _buildLeftOutlinerRail(
                  context,
                  wb,
                  epics,
                  selectedEpic,
                  selectedFeature,
                ),
              Expanded(
                child: Column(
                  children: [
                    if (!isWide)
                      _buildCompactSwitcherBar(
                        context,
                        wb,
                        epics,
                        selectedEpic,
                        selectedFeature,
                      ),
                    Expanded(
                      child: _buildCenteredSpecWorkspace(
                        context,
                        wb,
                        epics,
                        selectedEpic,
                        selectedFeature,
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

  Widget _buildLeftOutlinerRail(
    BuildContext context,
    WorkbenchProvider wb,
    List<EpicSpec> epics,
    EpicSpec activeEpic,
    FeatureSpec? activeFeature,
  ) {
    final isDark = wb.isDark;
    final border = AppTheme.borderFor(isDark);
    final panelBg = AppTheme.bgPanelFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);

    final relVer = wb.activeReleaseVersionTag;
    final releases = wb.projectReleases;
    final releaseRollup = wb.activeReleaseFeatureRollup;

    return Container(
      width: 286,
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Release Scope Header & Release Switcher Pills
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'RELEASE SCOPE',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: muted,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('plan_next_release_btn'),
                      onPressed: () =>
                          showProgressiveReleaseCopilotDialog(context, wb),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        minimumSize: const Size(0, 28),
                        backgroundColor: wb.isActiveReleaseComplete
                            ? green.withValues(alpha: 0.14)
                            : AppTheme.bgSurfaceRaisedFor(isDark),
                        foregroundColor:
                            wb.isActiveReleaseComplete ? green : primary,
                        side: BorderSide(
                          color: wb.isActiveReleaseComplete ? green : border,
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome, size: 12),
                      label: const Text(
                        '+ New Release',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final rel in releases) ...[
                  _OutlinerReleasePill(
                    key: ValueKey('outliner_release_${rel.id}'),
                    label: wb.releaseDisplayName(rel),
                    goal: (rel.sections['goal'] ?? '').trim(),
                    isActive: rel.id == wb.activeReleaseId,
                    isDark: isDark,
                    onTap: () => wb.selectActiveRelease(rel.id),
                  ),
                  const SizedBox(height: 5),
                ],
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'EPICS & FEATURES',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${releaseRollup.passed}/${releaseRollup.total} Passed',
                      key: const ValueKey('outliner_release_summary'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: releaseRollup.total > 0 &&
                                releaseRollup.passed == releaseRollup.total
                            ? green
                            : muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: border),

          // Expandable Epic -> Feature Outliner Tree
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: epics.length,
              itemBuilder: (ctx, i) {
                final ep = epics[i];
                final expanded = wb.isEpicExpanded(ep.id);
                final isEpicDomainSelected =
                    ep.id == activeEpic.id && activeFeature == null;
                final rollup = wb.epicFeatureRollup(ep);
                final visibleFeatures = wb.visibleFeaturesForEpic(ep);
                final rollupComplete =
                    rollup.total > 0 && rollup.passed == rollup.total;
                final rollupColor = rollup.openFixes > 0
                    ? red
                    : rollupComplete
                        ? green
                        : muted;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(
                      color: isEpicDomainSelected
                          ? cyan.withValues(alpha: 0.6)
                          : border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Epic header row
                      Container(
                        decoration: BoxDecoration(
                          color: isEpicDomainSelected
                              ? cyan.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.vertical(
                            top: const Radius.circular(AppTheme.radiusSm),
                            bottom: expanded
                                ? Radius.zero
                                : const Radius.circular(AppTheme.radiusSm),
                          ),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              key: ValueKey('outliner_epic_toggle_${ep.id}'),
                              onTap: () => wb.toggleEpicExpanded(ep.id),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusXs),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                child: Icon(
                                  expanded
                                      ? Icons.keyboard_arrow_down_rounded
                                      : Icons.keyboard_arrow_right_rounded,
                                  size: 16,
                                  color: muted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                key: ValueKey('outliner_epic_${ep.id}'),
                                onTap: () => wb.selectEpic(ep.id),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    9,
                                    10,
                                    9,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${ep.code} · ${ep.title}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: isEpicDomainSelected
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: isEpicDomainSelected
                                                ? cyan
                                                : primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: rollupColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            AppTheme.radiusXs,
                                          ),
                                          border: Border.all(color: border),
                                        ),
                                        child: Text(
                                          '${rollup.passed}/${rollup.total}',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: rollupColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Child Feature rows
                      if (expanded && visibleFeatures.isNotEmpty) ...[
                        Divider(height: 1, color: border),
                        Container(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          decoration: BoxDecoration(
                            color: AppTheme.bgInsetFor(isDark),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(AppTheme.radiusSm),
                            ),
                          ),
                          child: Column(
                            children: [
                              for (final feat in visibleFeatures)
                                _buildOutlinerFeatureRow(
                                  wb: wb,
                                  epic: ep,
                                  feat: feat,
                                  relVer: relVer,
                                  isSelected: activeFeature?.id == feat.id &&
                                      ep.id == activeEpic.id,
                                  isDark: isDark,
                                  primary: primary,
                                  secondary: secondary,
                                  muted: muted,
                                  border: border,
                                  cyan: cyan,
                                  green: green,
                                  red: red,
                                  amber: amber,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),

          // Godot 4 Plugin Setup footer
          Divider(height: 1, color: border),
          Padding(
            padding: const EdgeInsets.all(10),
            child: OutlinedButton.icon(
              onPressed: () => showConnectGodotPluginDialog(context, wb),
              icon: Icon(
                Icons.cable,
                size: 14,
                color: wb.isActiveProjectSyncedWithGodot ? green : cyan,
              ),
              label: Text(
                wb.isActiveProjectSyncedWithGodot
                    ? wb.formatGodotSyncStatusLabel()
                    : 'Godot 4 Plugin Setup',
                style: const TextStyle(fontSize: 11.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutlinerFeatureRow({
    required WorkbenchProvider wb,
    required EpicSpec epic,
    required FeatureSpec feat,
    required String relVer,
    required bool isSelected,
    required bool isDark,
    required Color primary,
    required Color secondary,
    required Color muted,
    required Color border,
    required Color cyan,
    required Color green,
    required Color red,
    required Color amber,
  }) {
    final badge = _featureOutlinerBadge(
      feat: feat,
      relVer: relVer,
      cyan: cyan,
      amber: amber,
      green: green,
      red: red,
      muted: muted,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        key: ValueKey('outliner_feature_${feat.id}'),
        onTap: () => wb.selectFeature(epic.id, feat.id),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.bgSurfaceActiveFor(isDark)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusXs),
            border: Border.all(
              color: isSelected
                  ? cyan.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${feat.code} · ${feat.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? primary : secondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                  border: Border.all(
                    color: badge.color.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  badge.label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: badge.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ({String label, Color color}) _featureOutlinerBadge({
    required FeatureSpec feat,
    required String relVer,
    required Color cyan,
    required Color amber,
    required Color green,
    required Color red,
    required Color muted,
  }) {
    if (relVer != 'v0.1' && feat.introducedIn.trim() == relVer) {
      return (label: '+$relVer NEW', color: cyan);
    }
    if (relVer != 'v0.1' && feat.releaseDelta.trim().isNotEmpty) {
      return (label: '+DELTA', color: amber);
    }
    if (feat.isLockedBaselineInRelease(relVer)) {
      return (label: '${feat.introducedIn} ✓', color: green);
    }
    if (feat.openFixesCount > 0) {
      return (label: '${feat.openFixesCount} FIX', color: red);
    }
    if (feat.isPassed) {
      return (label: 'Passed ✓', color: green);
    }
    if (feat.status == FeatureStatus.active) {
      return (label: 'Active', color: cyan);
    }
    return (label: 'Queued', color: muted);
  }

  Widget _buildCompactSwitcherBar(
    BuildContext context,
    WorkbenchProvider wb,
    List<EpicSpec> epics,
    EpicSpec activeEpic,
    FeatureSpec? activeFeature,
  ) {
    final isDark = wb.isDark;
    final items = <DropdownMenuItem<String>>[];
    for (final ep in epics) {
      items.add(
        DropdownMenuItem<String>(
          value: 'epic:${ep.id}',
          child: Text(
            '${ep.code} · ${ep.title} (Domain)',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimaryFor(isDark),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      for (final f in wb.visibleFeaturesForEpic(ep)) {
        items.add(
          DropdownMenuItem<String>(
            value: 'feat:${ep.id}::${f.id}',
            child: Text(
              '  ↳ ${f.code} · ${f.title}',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondaryFor(isDark),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }

    final currentVal = activeFeature != null
        ? 'feat:${activeEpic.id}::${activeFeature.id}'
        : 'epic:${activeEpic.id}';
    final safeValue = items.any((i) => i.value == currentVal)
        ? currentVal
        : (items.isNotEmpty ? items.first.value : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgPanelFor(isDark),
        border: Border(bottom: BorderSide(color: AppTheme.borderFor(isDark))),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: safeValue,
                dropdownColor: AppTheme.bgSurfaceRaisedFor(isDark),
                items: items,
                onChanged: (val) {
                  if (val == null) return;
                  if (val.startsWith('epic:')) {
                    wb.selectEpic(val.substring('epic:'.length));
                  } else if (val.startsWith('feat:')) {
                    final parts = val.substring('feat:'.length).split('::');
                    if (parts.length == 2) {
                      wb.selectFeature(parts[0], parts[1]);
                    }
                  }
                },
              ),
            ),
          ),
          IconButton(
            tooltip: wb.nextReleaseActionLabel,
            visualDensity: VisualDensity.compact,
            onPressed: () => showProgressiveReleaseCopilotDialog(context, wb),
            icon: Icon(
              Icons.auto_awesome,
              size: 16,
              color: AppTheme.accentCyanFor(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenteredSpecWorkspace(
    BuildContext context,
    WorkbenchProvider wb,
    List<EpicSpec> epics,
    EpicSpec epic,
    FeatureSpec? feature, {
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
    final promptText = wb.selectedBuildPrompt;
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
                                  _HeaderPill(
                                    label: 'EPIC · LARGE DOMAIN',
                                    color: cyan,
                                  ),
                                  _HeaderPill(
                                    label: wb.projectDimension.pillLabel,
                                    color: muted,
                                  ),
                                  _HeaderPill(
                                    label:
                                        '${rollup.passed}/${rollup.total} Features Passed in $relVer',
                                    color: rollup.total > 0 &&
                                            rollup.passed == rollup.total
                                        ? green
                                        : muted,
                                  ),
                                ]
                              : [
                                  _HeaderPill(
                                    label:
                                        'FEATURE · PLAYABLE SLICE (${feature.sliceTime})',
                                    color: muted,
                                  ),
                                  _HeaderPill(
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
                                    _HeaderPill(
                                      label: '[$relVer +NEW]',
                                      color: cyan,
                                    )
                                  else if (relVer != 'v0.1' &&
                                      feature.releaseDelta.trim().isNotEmpty)
                                    _HeaderPill(
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
                        _SpecViewTabSwitch(
                          isDark: isDark,
                          isRaw: wb.showRawEpicPayload,
                          onChanged: (isRaw) => wb.toggleRawEpicPayload(isRaw),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('copy_build_prompt_btn'),
                          onPressed: () =>
                              _copyBuildPrompt(context, wb, promptText, feature),
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text(
                            'Copy Build Prompt',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        if (feature == null)
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
                          )
                        else if (!isLockedBaseline) ...[
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
                child: wb.showRawEpicPayload
                    ? _buildAiBuildPromptView(
                        context,
                        wb,
                        epic,
                        feature,
                        promptText,
                        isDark,
                        primary,
                        muted,
                        border,
                        cyan,
                        red,
                      )
                    : (feature == null
                        ? _buildEpicDomainSheet(
                            context,
                            wb,
                            epic,
                            isDark,
                            primary,
                            secondary,
                            muted,
                            border,
                            cyan,
                            green,
                            red,
                          )
                        : _buildFeatureSpecSheet(
                            context,
                            wb,
                            epic,
                            feature,
                            isLockedBaseline,
                            isDark,
                            primary,
                            secondary,
                            muted,
                            border,
                            cyan,
                            green,
                            red,
                            amber,
                          )),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _copyBuildPrompt(
    BuildContext context,
    WorkbenchProvider wb,
    String promptText,
    FeatureSpec? feature,
  ) {
    Clipboard.setData(ClipboardData(text: promptText));
    final label = feature != null
        ? (feature.openFixesCount > 0
            ? 'Copied Focused Revision Prompt (${feature.code} · ${feature.openFixesCount} [FIX])'
            : 'Copied Feature Build Prompt (${feature.code})')
        : 'Copied Epic Architecture Brief (${wb.selectedEpicSpec?.code ?? ''})';
    AppToast.show(context, label, isDark: wb.isDark);
  }

  Widget _buildAiBuildPromptView(
    BuildContext context,
    WorkbenchProvider wb,
    EpicSpec epic,
    FeatureSpec? feature,
    String promptText,
    bool isDark,
    Color primary,
    Color muted,
    Color border,
    Color cyan,
    Color red,
  ) {
    final openFixesCount =
        feature != null ? feature.openFixesCount : wb.epicFeatureRollup(epic).openFixes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.bgSurfaceRaisedFor(isDark),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: openFixesCount > 0 ? red.withValues(alpha: 0.45) : border,
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    feature != null
                        ? (openFixesCount > 0
                            ? 'READY-TO-PASTE FOCUSED [FIX] PROMPT (${feature.code})'
                            : 'READY-TO-PASTE GODOT 4 FEATURE BUILD PROMPT (${feature.code})')
                        : 'GODOT 4 EPIC ARCHITECTURE BRIEF (${epic.code})',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: openFixesCount > 0 ? red : cyan,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    feature != null
                        ? 'Bundles Project Contract + Parent ${epic.code} Architecture + Active ${feature.code} Spec & live @export vars.'
                        : 'Domain overview summarizing ${epic.code} scenes/scripts, state rules, and owned Features.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
              ElevatedButton.icon(
                key: const ValueKey('prompt_tab_copy_btn'),
                onPressed: () =>
                    _copyBuildPrompt(context, wb, promptText, feature),
                icon: const Icon(Icons.copy, size: 14),
                label: const Text(
                  'Copy Build Prompt',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.bgInsetFor(isDark),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: border),
          ),
          child: SelectableText(
            promptText,
            key: const ValueKey('ai_build_prompt_text'),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12.5,
              color: primary,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildEpicDomainSheet(
    BuildContext context,
    WorkbenchProvider wb,
    EpicSpec epic,
    bool isDark,
    Color primary,
    Color secondary,
    Color muted,
    Color border,
    Color cyan,
    Color green,
    Color red,
  ) {
    final relVer = wb.activeReleaseVersionTag;
    final visibleFeatures = wb.visibleFeaturesForEpic(epic);
    final ownershipList = epic.sceneOwnership;
    final states = epic.stateFlow;
    final rules = epic.interruptRules;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // §01 Domain Scope (Zero Feature Duplication)
        _EpicSectionCard(
          isDark: isDark,
          code: '§01',
          title: 'Domain Scope (Zero Feature Duplication)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Goal: ${epic.goal}',
                style: TextStyle(fontSize: 14, color: primary, height: 1.45),
              ),
              if (epic.inScope.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'In Scope',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 4),
                for (final item in epic.inScope)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• $item',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ),
              ],
              if (epic.doneWhen.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Done When',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 4),
                for (final item in epic.doneWhen)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• $item',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ),
              ],
              if (epic.upgradeDeltas.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: cyan.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${epic.releaseVersion} UPGRADE DELTAS',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cyan,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final d in epic.upgradeDeltas)
                        Text(
                          '• $d',
                          style: TextStyle(fontSize: 12.5, color: primary),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §02 Shared Scene & Script Ownership
        _EpicSectionCard(
          isDark: isDark,
          code: '§02',
          title: 'Shared Scene & Script Ownership',
          child: ownershipList.isNotEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final own in ownershipList)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurfaceFor(isDark),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(color: border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              own.path,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: cyan,
                              ),
                            ),
                            if (own.role.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                own.role,
                                style:
                                    TextStyle(fontSize: 12.5, color: secondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                )
              : (epic.links.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final l in epic.links)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $l',
                              style: TextStyle(fontSize: 13, color: secondary),
                            ),
                          ),
                      ],
                    )
                  : Text(
                      'No shared scenes mapped yet.',
                      style: TextStyle(fontSize: 12.5, color: muted),
                    )),
        ),
        const SizedBox(height: 14),

        // §03 Shared State & Interrupt Rules
        _EpicSectionCard(
          isDark: isDark,
          code: '§03',
          title: 'Shared State & Interrupt Rules',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (states.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (int i = 0; i < states.length; i++) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurfaceFor(isDark),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(color: border),
                        ),
                        child: Text(
                          states[i],
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: primary,
                          ),
                        ),
                      ),
                      if (i < states.length - 1)
                        Text('→', style: TextStyle(color: muted, fontSize: 12)),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
              ],
              for (final rule in rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $rule',
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                ),
              if (states.isEmpty && rules.isEmpty)
                Text(
                  'Linear slice execution; no cross-slice interrupt locks.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §04 Domain Out-of-Scope Cuts
        _EpicSectionCard(
          isDark: isDark,
          code: '§04',
          title: 'Domain Out-of-Scope Cuts',
          child: epic.outOfScope.isEmpty
              ? Text(
                  'Scoped cleanly to child Features below.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final cut in epic.outOfScope)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                          border: Border.all(color: red.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          cut,
                          style: TextStyle(fontSize: 12, color: primary),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // §05 Child Features + Add Feature Slice
        _EpicSectionCard(
          isDark: isDark,
          code: '§05',
          title: 'Child Features in ${epic.code} ($relVer)',
          trailing: OutlinedButton.icon(
            key: const ValueKey('show_add_feature_btn'),
            onPressed: () =>
                setState(() => _showAddFeatureForm = !_showAddFeatureForm),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: Icon(_showAddFeatureForm ? Icons.close : Icons.add, size: 14),
            label: Text(
              _showAddFeatureForm ? 'Close' : '+ Add Feature Slice',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showAddFeatureForm) ...[
                Container(
                  key: const ValueKey('add_feature_form'),
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: cyan.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('new_feature_title_input'),
                        controller: _newFeatureTitleController,
                        style: TextStyle(fontSize: 13, color: primary),
                        decoration: InputDecoration(
                          labelText: 'Feature Title (2–5 plain words)',
                          hintText: 'e.g. Wall Bounce Dash',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('new_feature_goal_input'),
                        controller: _newFeatureGoalController,
                        style: TextStyle(fontSize: 13, color: primary),
                        decoration: InputDecoration(
                          labelText: 'Slice Goal (1 plain-English sentence)',
                          hintText:
                              'e.g. Ricochet cleanly off angled stone arena walls.',
                          hintStyle: TextStyle(fontSize: 12, color: muted),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          TextButton(
                            onPressed: () {
                              _newFeatureTitleController.clear();
                              _newFeatureGoalController.clear();
                              setState(() => _showAddFeatureForm = false);
                            },
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            key: const ValueKey('submit_add_feature_btn'),
                            onPressed: () {
                              final title =
                                  _newFeatureTitleController.text.trim();
                              final goal =
                                  _newFeatureGoalController.text.trim();
                              if (title.isEmpty || goal.isEmpty) return;
                              wb.addFeatureSlice(
                                epic.id,
                                title: title,
                                goal: goal,
                              );
                              _newFeatureTitleController.clear();
                              _newFeatureGoalController.clear();
                              setState(() => _showAddFeatureForm = false);
                            },
                            child: const Text(
                              'Create Feature Slice →',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (visibleFeatures.isEmpty)
                Text(
                  'No child Features queued in $relVer. Use + Add Feature Slice above.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              else
                for (final feat in visibleFeatures)
                  _buildEpicChildFeatureCard(
                    wb: wb,
                    epic: epic,
                    feat: feat,
                    relVer: relVer,
                    isDark: isDark,
                    primary: primary,
                    secondary: secondary,
                    muted: muted,
                    border: border,
                    cyan: cyan,
                    green: green,
                    red: red,
                  ),
            ],
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }

  Widget _buildEpicChildFeatureCard({
    required WorkbenchProvider wb,
    required EpicSpec epic,
    required FeatureSpec feat,
    required String relVer,
    required bool isDark,
    required Color primary,
    required Color secondary,
    required Color muted,
    required Color border,
    required Color cyan,
    required Color green,
    required Color red,
  }) {
    final effChecks = feat.effectiveChecksForRelease(relVer);
    final passedCount = effChecks.where((c) => c.passed).length;
    final passedFeature = feat.isPassedForRelease(relVer);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: ValueKey('epic_feature_card_${feat.id}'),
        onTap: () => wb.selectFeature(epic.id, feat.id),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgSurfaceFor(isDark),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: passedFeature ? green.withValues(alpha: 0.4) : border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    '${feat.code} · ${feat.sliceTime}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: cyan,
                    ),
                  ),
                  Text(
                    '$passedCount/${effChecks.length} checks${feat.openFixesCount > 0 ? ' · ${feat.openFixesCount} [FIX]' : ''}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: feat.openFixesCount > 0
                          ? red
                          : (passedFeature ? green : muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                feat.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                feat.goal,
                style: TextStyle(fontSize: 12.5, color: secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureSpecSheet(
    BuildContext context,
    WorkbenchProvider wb,
    EpicSpec epic,
    FeatureSpec feat,
    bool isLockedBaseline,
    bool isDark,
    Color primary,
    Color secondary,
    Color muted,
    Color border,
    Color cyan,
    Color green,
    Color red,
    Color amber,
  ) {
    final target = wb.projectDimension;
    final relVer = wb.activeReleaseVersionTag;
    final effChecks = feat.effectiveChecksForRelease(relVer);
    final checkedCount = effChecks.where((c) => c.passed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // §01 Feature Scope
        _EpicSectionCard(
          isDark: isDark,
          code: '§01',
          title: 'Feature Scope',
          trailing: InkWell(
            key: const ValueKey('feature_parent_epic_link'),
            onTap: () => wb.selectEpic(epic.id),
            child: Text(
              'Owning Epic: ${epic.code} · ${epic.title}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: cyan,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (relVer != 'v0.1' && feat.releaseDelta.trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: amber.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    '$relVer Upgrade Delta: ${feat.releaseDelta}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ),
              ],
              Text(
                'Goal: ${feat.goal}',
                style: TextStyle(fontSize: 14, color: primary, height: 1.45),
              ),
              if (feat.inScope.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'In Scope',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 4),
                for (final s in feat.inScope)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• $s',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ),
              ],
              if (feat.doneWhen.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Done When',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 4),
                for (final d in feat.doneWhen)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• $d',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §02 Input Actions (InputMap)
        _EpicSectionCard(
          isDark: isDark,
          code: '§02',
          title: 'Input Actions (${target.inputContractLabel})',
          child: feat.controls.isEmpty
              ? Text(
                  'Signal/system-driven slice — uses parent Epic InputMap triggers.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              : Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.5),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(2.8),
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(color: border),
                  ),
                  children: [
                    for (final c in feat.controls)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Text(
                              c.action,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cyan,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Text(
                              c.trigger,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                color: muted,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Text(
                              c.rule,
                              style: TextStyle(fontSize: 13, color: primary),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // §03 Exposed Tuning (@export GDScript Vars)
        _EpicSectionCard(
          isDark: isDark,
          code: '§03',
          title: 'Exposed Tuning (${target.tuningColumnLabel})',
          trailing: Text(
            isLockedBaseline
                ? 'Locked baseline'
                : 'Edits update AI Build Prompt live',
            style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: muted),
          ),
          child: feat.tuning.isEmpty
              ? Text(
                  'No exposed @export variables on this slice.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (int i = 0; i < feat.tuning.length; i++)
                      _LiveTuningChip(
                        key: ValueKey('tuning_chip_${feat.id}_$i'),
                        inputKey: ValueKey('tuning_input_${feat.id}_$i'),
                        param: feat.tuning[i],
                        isDark: isDark,
                        readOnly: isLockedBaseline,
                        onChanged: (val) => wb.updateFeatureTuningParam(
                          epic.id,
                          feat.id,
                          i,
                          val,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // §04 Viewport, UI & Audio Cues
        _EpicSectionCard(
          isDark: isDark,
          code: '§04',
          title: 'Viewport, UI & Audio Cues',
          child: feat.cues.isEmpty
              ? Text(
                  'Minimal greybox feedback visual + confirmation sound.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final cue in feat.cues)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          '• $cue',
                          style: TextStyle(fontSize: 13, color: primary),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // §05 Playtest Gate & [FIX] Notes
        _EpicSectionCard(
          isDark: isDark,
          code: '§05',
          title: 'Playtest Gate & [FIX] Notes',
          trailing: Text(
            '$checkedCount/${effChecks.length} Checked · ${feat.openFixesCount} Open [FIX]',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: effChecks.isNotEmpty && checkedCount == effChecks.length
                  ? green
                  : muted,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final chk in effChecks)
                Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    key: ValueKey('feature_check_${chk.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: chk.passed,
                    onChanged: isLockedBaseline
                        ? null
                        : (val) => wb.toggleFeatureCheck(
                              epic.id,
                              feat.id,
                              chk.id,
                              val,
                            ),
                    title: Text(
                      chk.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: chk.passed ? green : primary,
                        decoration:
                            chk.passed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ),

              if (_passGateHint != null) ...[
                const SizedBox(height: 6),
                Text(
                  _passGateHint!,
                  key: const ValueKey('pass_gate_hint'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: amber,
                  ),
                ),
              ],

              if (!isLockedBaseline) ...[
                const SizedBox(height: 14),
                Text(
                  'Flag Playtest Revision ([FIX]) — switches Feature Build Prompt to Focused [FIX] Pass:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 160,
                        maxWidth: 520,
                      ),
                      child: TextField(
                        key: const ValueKey('flag_fix_input'),
                        controller: _fixInputController,
                        style: TextStyle(fontSize: 13, color: primary),
                        decoration: InputDecoration(
                          hintText:
                              'e.g. Dash stops early against north barrier wall...',
                          hintStyle: TextStyle(fontSize: 12.5, color: muted),
                          isDense: true,
                        ),
                        onSubmitted: (_) =>
                            _submitFlagFix(wb, epic.id, feat.id),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('flag_fix_btn'),
                      onPressed: () => _submitFlagFix(wb, epic.id, feat.id),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: red,
                        side: BorderSide(color: red.withValues(alpha: 0.45)),
                      ),
                      icon: const Icon(Icons.flag_outlined, size: 15),
                      label: const Text('Flag [FIX]'),
                    ),
                  ],
                ),
              ],

              if (feat.fixes.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final fx in feat.fixes)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: fx.resolved
                          ? green.withValues(alpha: 0.08)
                          : red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(
                        color: fx.resolved
                            ? green.withValues(alpha: 0.3)
                            : red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          fx.resolved ? '[FIXED]' : '[FIX]',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: fx.resolved ? green : red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fx.text,
                            style: TextStyle(
                              fontSize: 13,
                              color: primary,
                              decoration:
                                  fx.resolved ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        if (!fx.resolved && !isLockedBaseline)
                          TextButton(
                            key: ValueKey('resolve_fix_${fx.id}'),
                            onPressed: () => wb.resolveFeatureFix(
                              epic.id,
                              feat.id,
                              fx.id,
                            ),
                            child: Text(
                              'Resolve ✓',
                              style: TextStyle(color: green, fontSize: 12),
                            ),
                          ),
                        if (!isLockedBaseline)
                          IconButton(
                            icon: Icon(Icons.close, size: 15, color: muted),
                            onPressed: () =>
                                wb.deleteFeatureFix(epic.id, feat.id, fx.id),
                            tooltip: 'Remove note',
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }

  void _submitFlagFix(
    WorkbenchProvider wb,
    String epicId,
    String featureId,
  ) {
    final text = _fixInputController.text.trim();
    if (text.isEmpty) return;
    _fixInputController.clear();
    wb.flagFeatureFix(epicId, featureId, text);
  }
}

class _OutlinerReleasePill extends StatelessWidget {
  final String label;
  final String goal;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _OutlinerReleasePill({
    super.key,
    required this.label,
    required this.goal,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? cyan.withValues(alpha: 0.1)
              : AppTheme.bgSurfaceFor(isDark),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: isActive ? cyan.withValues(alpha: 0.65) : border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ),
                if (isActive)
                  Text(
                    'Active',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: cyan,
                    ),
                  ),
              ],
            ),
            if (goal.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                goal,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final String label;
  final Color color;

  const _HeaderPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _SpecViewTabSwitch extends StatelessWidget {
  final bool isDark;
  final bool isRaw;
  final ValueChanged<bool> onChanged;

  const _SpecViewTabSwitch({
    required this.isDark,
    required this.isRaw,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(isDark);
    final raised = AppTheme.bgSurfaceRaisedFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('stage2_tab_clean'),
            onTap: () => onChanged(false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: !isRaw ? raised : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              ),
              child: Text(
                'Spec Sheet',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: !isRaw ? FontWeight.w600 : FontWeight.w400,
                  color: !isRaw ? primary : muted,
                ),
              ),
            ),
          ),
          InkWell(
            key: const ValueKey('stage2_tab_raw'),
            onTap: () => onChanged(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isRaw ? raised : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              ),
              child: Text(
                'AI Build Prompt',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isRaw ? FontWeight.w600 : FontWeight.w400,
                  color: isRaw ? primary : muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpicSectionCard extends StatelessWidget {
  final bool isDark;
  final String code;
  final String title;
  final Widget child;
  final Widget? trailing;

  const _EpicSectionCard({
    required this.isDark,
    required this.code,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceRaisedFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.borderFor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, cardConstraints) {
              final titleStyle = AppTheme.displayFont(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimaryFor(isDark),
              );
              final codeWidget = Text(
                code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentCyanFor(isDark),
                ),
              );
              if (trailing != null && cardConstraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        codeWidget,
                        const SizedBox(width: 8),
                        Expanded(child: Text(title, style: titleStyle)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    trailing!,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  codeWidget,
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: titleStyle)),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LiveTuningChip extends StatefulWidget {
  final EpicTuningParam param;
  final bool isDark;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final Key? inputKey;

  const _LiveTuningChip({
    super.key,
    this.inputKey,
    required this.param,
    required this.isDark,
    this.readOnly = false,
    required this.onChanged,
  });

  @override
  State<_LiveTuningChip> createState() => _LiveTuningChipState();
}

class _LiveTuningChipState extends State<_LiveTuningChip> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.param.value);
  }

  @override
  void didUpdateWidget(covariant _LiveTuningChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.param.value != widget.param.value &&
        _controller.text != widget.param.value) {
      _controller.text = widget.param.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(widget.isDark);
    final cyan = AppTheme.accentCyanFor(widget.isDark);
    final muted = AppTheme.textMutedFor(widget.isDark);
    final primary = AppTheme.textPrimaryFor(widget.isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(widget.isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.param.key}:',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: TextField(
              key: widget.inputKey,
              controller: _controller,
              readOnly: widget.readOnly,
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: widget.readOnly ? muted : cyan,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              ),
              onChanged: widget.readOnly ? null : widget.onChanged,
            ),
          ),
          if (widget.param.unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              widget.param.unit,
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
