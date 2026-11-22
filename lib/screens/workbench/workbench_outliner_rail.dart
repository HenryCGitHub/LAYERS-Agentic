import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'progressive_release_modal.dart';
import 'workbench_shared_widgets.dart';

class WorkbenchOutlinerRail extends StatelessWidget {
  final WorkbenchProvider wb;
  final List<EpicSpec> epics;
  final EpicSpec activeEpic;
  final FeatureSpec? activeFeature;

  const WorkbenchOutlinerRail({
    super.key,
    required this.wb,
    required this.epics,
    required this.activeEpic,
    required this.activeFeature,
  });

  @override
  Widget build(BuildContext context) =>
      _buildRail(context, wb, epics, activeEpic, activeFeature);

  Widget _buildRail(
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
                  OutlinerReleasePill(
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
}

class WorkbenchCompactSwitcherBar extends StatelessWidget {
  final WorkbenchProvider wb;
  final List<EpicSpec> epics;
  final EpicSpec activeEpic;
  final FeatureSpec? activeFeature;

  const WorkbenchCompactSwitcherBar({
    super.key,
    required this.wb,
    required this.epics,
    required this.activeEpic,
    required this.activeFeature,
  });

  @override
  Widget build(BuildContext context) =>
      _buildSwitcher(context, wb, epics, activeEpic, activeFeature);

  Widget _buildSwitcher(
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
}
