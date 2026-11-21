import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'widgets/godot_bridge_modals.dart';

part 'workbench_progressive_planner_part.dart';
part 'workbench_epic_sheet_part.dart';
part 'workbench_feature_sheet_part.dart';
part 'workbench_widgets_part.dart';

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
  final TextEditingController _fixInputController = TextEditingController();
  final TextEditingController _newFeatureTitleController =
      TextEditingController();
  final TextEditingController _newFeatureGoalController =
      TextEditingController();
  final ScrollController _specScrollController = ScrollController();

  bool _showAddFeatureForm = false;
  String? _passGateHint;
  String? _lastSelectionKey;

  void _mutateUi(VoidCallback fn) => setState(fn);

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
    if (selectionChanged) {
      _lastSelectionKey = selectionKey;
      _showAddFeatureForm = false;
      _passGateHint = null;
      _fixInputController.clear();
      _newFeatureTitleController.clear();
      _newFeatureGoalController.clear();
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
                      onPressed: wb.isDraftingProgressive
                          ? null
                          : () => showProgressiveReleaseCopilotDialog(
                                context,
                                wb,
                              ),
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
            onPressed: wb.isDraftingProgressive
                ? null
                : () => showProgressiveReleaseCopilotDialog(context, wb),
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
                child: feature == null
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
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
