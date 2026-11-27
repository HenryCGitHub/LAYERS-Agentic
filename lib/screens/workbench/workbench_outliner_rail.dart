import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';

/// Flat 240px left document outline strictly reflecting the 4-tier hierarchy:
/// Project Brief -> Active Release (`v0.X · Title · X/Y`) -> Epics -> Features.
class WorkbenchOutlinerRail extends StatelessWidget {
  final WorkbenchProvider wb;
  final List<EpicSpec> epics;
  final EpicSpec? activeEpic;
  final FeatureSpec? activeFeature;

  const WorkbenchOutlinerRail({
    super.key,
    required this.wb,
    required this.epics,
    required this.activeEpic,
    required this.activeFeature,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = wb.isDark;
    final bgBase = AppTheme.bgBaseFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final activePage = wb.activeDocPage;
    final releases = wb.projectReleases;
    final relVer = wb.activeReleaseVersionTag;
    final releaseRollup = wb.activeReleaseFeatureRollup;

    return Material(
      color: bgBase,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: border, width: 1)),
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OutlineRow(
            key: const ValueKey('outliner_project_brief'),
            active: activePage == WorkbenchDocPage.projectBrief,
            isDark: isDark,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            onTap: () {
              FocusManager.instance.primaryFocus?.unfocus();
              wb.selectProjectBrief();
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Project Brief',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: activePage == WorkbenchDocPage.projectBrief
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: activePage == WorkbenchDocPage.projectBrief
                          ? textPrimary
                          : textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                if (releases.isEmpty && wb.conceptDraft != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      'No release launched yet',
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                  ),
                for (final rel in releases) ...[
                  () {
                    final isCurrentRel = rel.id == wb.activeReleaseId;
                    final isRelActive =
                        isCurrentRel &&
                        activePage == WorkbenchDocPage.releaseSpec;
                    final ver = (rel.sections['release_version'] ?? '')
                            .trim()
                            .isNotEmpty
                        ? rel.sections['release_version']!.trim()
                        : rel.title;
                    return _OutlineRow(
                      key: ValueKey('outliner_release_${rel.id}'),
                      active: isRelActive,
                      isDark: isDark,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        wb.selectReleaseSpec(rel.id);
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$ver · ${rel.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: isCurrentRel
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isCurrentRel ? textPrimary : textMuted,
                              ),
                            ),
                          ),
                          if (isCurrentRel) ...[
                            const SizedBox(width: 6),
                            Text(
                              '${releaseRollup.passed}/${releaseRollup.total}',
                              key: const ValueKey('outliner_release_summary'),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                color: releaseRollup.openFixes > 0
                                    ? AppTheme.accentRedFor(isDark)
                                    : (releaseRollup.total > 0 &&
                                              releaseRollup.passed ==
                                                  releaseRollup.total
                                          ? AppTheme.accentGreenFor(isDark)
                                          : textMuted),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }(),
                  if (rel.id == wb.activeReleaseId) ...[
                    for (final ep in epics)
                      _buildEpicTree(context, ep, relVer),
                  ],
                ],
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: border, width: 1)),
            ),
            child: InkWell(
              key: const ValueKey('outline_add_slice_btn'),
              onTap: epics.isEmpty
                  ? null
                  : () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      wb.quickAddSliceToActiveRelease();
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Text(
                      '+ Add slice',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: epics.isEmpty ? textMuted : focal,
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
    );
  }

  Widget _buildEpicTree(
    BuildContext context,
    EpicSpec ep,
    String relVer,
  ) {
    final isDark = wb.isDark;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final visibleFeatures = wb.visibleFeaturesForEpic(ep);
    final expanded = wb.isEpicExpanded(ep.id);
    final rollup = wb.epicFeatureRollup(ep);
    final isEpicActive =
        activeEpic?.id == ep.id &&
        wb.activeDocPage == WorkbenchDocPage.epicDomain;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OutlineRow(
          active: isEpicActive,
          isDark: isDark,
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            wb.selectEpic(ep.id);
          },
          child: Row(
            children: [
              InkWell(
                key: ValueKey('outliner_epic_toggle_${ep.id}'),
                onTap: () => wb.toggleEpicExpanded(ep.id),
                borderRadius: BorderRadius.circular(2),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 14,
                    color: textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  key: ValueKey('outliner_epic_${ep.id}'),
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    wb.selectEpic(ep.id);
                  },
                  child: Row(
                    children: [
                      Text(
                        ep.code,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isEpicActive ? textPrimary : textMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ep.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: isEpicActive
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isEpicActive ? textPrimary : textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${rollup.passed}/${rollup.total}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: rollup.openFixes > 0
                              ? AppTheme.accentRedFor(isDark)
                              : textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (expanded)
          for (final feat in visibleFeatures)
            _buildFeatureRow(ep, feat, relVer),
      ],
    );
  }

  Widget _buildFeatureRow(
    EpicSpec ep,
    FeatureSpec feat,
    String relVer,
  ) {
    final isDark = wb.isDark;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final isFeatActive =
        activeFeature?.id == feat.id &&
        wb.activeDocPage == WorkbenchDocPage.featureSlice;
    final glyph = _featureGlyph(feat, relVer, isDark);

    return _OutlineRow(
      key: ValueKey('outliner_feature_${feat.id}'),
      active: isFeatActive,
      isDark: isDark,
      padding: const EdgeInsets.fromLTRB(28, 5, 12, 5),
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        wb.selectFeature(ep.id, feat.id);
      },
      child: Row(
        children: [
          Text(
            glyph.symbol,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: glyph.color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            feat.code,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: textMuted,
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              feat.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isFeatActive ? FontWeight.w600 : FontWeight.w400,
                color: isFeatActive ? textPrimary : textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({String symbol, Color color}) _featureGlyph(
    FeatureSpec feat,
    String relVer,
    bool isDark,
  ) {
    if (feat.openFixesCount > 0) {
      return (symbol: '●', color: AppTheme.accentRedFor(isDark));
    }
    if (feat.isPassedForRelease(relVer)) {
      return (symbol: '✓', color: AppTheme.accentGreenFor(isDark));
    }
    if (relVer != 'v0.1' && feat.introducedIn.trim() == relVer) {
      return (symbol: '+', color: AppTheme.accentCyanFor(isDark));
    }
    if (relVer != 'v0.1' && feat.releaseDelta.trim().isNotEmpty) {
      return (symbol: 'Δ', color: AppTheme.accentAmberFor(isDark));
    }
    return (symbol: '○', color: AppTheme.textMutedFor(isDark));
  }
}

class _OutlineRow extends StatelessWidget {
  final Widget child;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;

  const _OutlineRow({
    super.key,
    required this.child,
    required this.active,
    required this.isDark,
    required this.onTap,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final focal = AppTheme.focalAccentFor(isDark);
    return Material(
      color: active ? AppTheme.bgSurfaceActiveFor(isDark) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active ? focal : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Compact 1-line document switcher bar rendered below 960px viewport width.
class WorkbenchCompactSwitcherBar extends StatelessWidget {
  final WorkbenchProvider wb;
  final List<EpicSpec> epics;
  final EpicSpec? activeEpic;
  final FeatureSpec? activeFeature;

  const WorkbenchCompactSwitcherBar({
    super.key,
    required this.wb,
    required this.epics,
    required this.activeEpic,
    required this.activeFeature,
  });

  String _currentSelectionValue() {
    switch (wb.activeDocPage) {
      case WorkbenchDocPage.newGameIdea:
      case WorkbenchDocPage.projectBrief:
        return 'brief';
      case WorkbenchDocPage.releaseSpec:
      case WorkbenchDocPage.planNextRelease:
        if (wb.activeReleaseId != null) {
          return 'rel:${wb.activeReleaseId}';
        }
        return 'brief';
      case WorkbenchDocPage.epicDomain:
        if (activeEpic != null) {
          return 'epic:${activeEpic!.id}';
        }
        return 'brief';
      case WorkbenchDocPage.featureSlice:
        if (activeEpic != null && activeFeature != null) {
          return 'feat:${activeEpic!.id}:${activeFeature!.id}';
        }
        if (activeEpic != null) {
          return 'epic:${activeEpic!.id}';
        }
        return 'brief';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = wb.isDark;
    final border = AppTheme.borderFor(isDark);
    final bgBase = AppTheme.bgBaseFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);

    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem<String>(
        value: 'brief',
        child: Text(
          'Project Brief',
          style: TextStyle(fontSize: 12.5, color: textPrimary),
        ),
      ),
      for (final rel in wb.projectReleases)
        DropdownMenuItem<String>(
          value: 'rel:${rel.id}',
          child: Text(
            '${(rel.sections['release_version'] ?? '').trim().isNotEmpty ? rel.sections['release_version']!.trim() : rel.title} · ${rel.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: textPrimary),
          ),
        ),
      for (final ep in epics) ...[
        DropdownMenuItem<String>(
          value: 'epic:${ep.id}',
          child: Text(
            '  ${ep.code} ${ep.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
        ),
        for (final feat in wb.visibleFeaturesForEpic(ep))
          DropdownMenuItem<String>(
            value: 'feat:${ep.id}:${feat.id}',
            child: Text(
              '    ${feat.code} ${feat.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: textPrimary),
            ),
          ),
      ],
    ];

    final currentVal = _currentSelectionValue();
    final validValues = items.map((e) => e.value).toSet();
    final safeVal = validValues.contains(currentVal) ? currentVal : 'brief';

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: bgBase,
        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              value: safeVal,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              dropdownColor: AppTheme.bgSurfaceFor(isDark),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: textMuted,
              ),
              items: items,
              onChanged: (val) {
                if (val == null) return;
                FocusManager.instance.primaryFocus?.unfocus();
                if (val == 'brief') {
                  wb.selectProjectBrief();
                } else if (val.startsWith('rel:')) {
                  wb.selectReleaseSpec(val.substring(4));
                } else if (val.startsWith('epic:')) {
                  wb.selectEpic(val.substring(5));
                } else if (val.startsWith('feat:')) {
                  final parts = val.split(':');
                  if (parts.length == 3) {
                    wb.selectFeature(parts[1], parts[2]);
                  }
                }
              },
            ),
          ),
          if (epics.isNotEmpty) ...[
            const SizedBox(width: 10),
            InkWell(
              key: const ValueKey('outline_add_slice_btn'),
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                wb.quickAddSliceToActiveRelease();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  '+ Add slice',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: focal,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
