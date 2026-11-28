import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'plain_doc_widgets.dart';

/// Monday.com-style grouped Release table: Epics are collapsible groups with
/// clickable headers (opening the 2-column Epic Overlay) and ordered Feature rows
/// displaying auto status (`OPEN` / `FIX (N)` / `PASSED`), PIE progress bar, and
/// silent 1-click CoPilot prompt copy (clicking a row opens the Feature Overlay).
class MondayReleaseTable extends StatefulWidget {
  final WorkbenchProvider workbench;
  final List<EpicSpec> epics;
  final String releaseVersion;
  final bool isDark;

  const MondayReleaseTable({
    super.key,
    required this.workbench,
    required this.epics,
    required this.releaseVersion,
    required this.isDark,
  });

  @override
  State<MondayReleaseTable> createState() => _MondayReleaseTableState();
}

class _MondayReleaseTableState extends State<MondayReleaseTable> {
  final Set<String> _collapsedEpicIds = <String>{};
  final TextEditingController _inlineAddTitleCtrl = TextEditingController();

  String? _inlineAddEpicId;
  String? _copiedFeatureId;
  int? _copiedTokens;
  Timer? _copyResetTimer;

  @override
  void didUpdateWidget(covariant MondayReleaseTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.releaseVersion != widget.releaseVersion ||
        oldWidget.workbench.activeReleaseId !=
            widget.workbench.activeReleaseId) {
      _inlineAddEpicId = null;
      _inlineAddTitleCtrl.clear();
      _copyResetTimer?.cancel();
      _copiedFeatureId = null;
      _copiedTokens = null;
    }
  }

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    _inlineAddTitleCtrl.dispose();
    super.dispose();
  }

  void _triggerSilentRowCopy(FeatureSpec feat, String promptText) {
    Clipboard.setData(ClipboardData(text: promptText));
    final tok = (promptText.length / 4).ceil().clamp(1, 999999);
    _copyResetTimer?.cancel();
    setState(() {
      _copiedFeatureId = feat.id;
      _copiedTokens = tok;
    });
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copiedFeatureId = null;
          _copiedTokens = null;
        });
      }
    });
  }

  void _submitInlineAdd(String epicId) {
    final title = _inlineAddTitleCtrl.text.trim();
    if (title.isEmpty) return;
    widget.workbench.addFeatureSlice(
      epicId,
      title: title,
      goal: 'Build and test $title cleanly in UE5 PIE.',
      selectCreated: false,
    );
    _inlineAddTitleCtrl.clear();
    setState(() {
      _inlineAddEpicId = null;
      _collapsedEpicIds.remove(epicId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final epics = widget.epics;
    final relVer = widget.releaseVersion;
    final isDark = widget.isDark;

    final muted = AppTheme.textMutedFor(isDark);
    if (epics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No epics in $relVer yet.',
          style: TextStyle(fontSize: 13, color: muted),
        ),
      );
    }

    final border = AppTheme.borderFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);
    final stripePalette = <Color>[focal, cyan, green, amber];

    return LayoutBuilder(
      builder: (context, constraints) {
        final showWideColumns = constraints.maxWidth >= 780;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < epics.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              _buildEpicGroupCard(
                wb: wb,
                ep: epics[i],
                stripeColor: stripePalette[i % stripePalette.length],
                relVer: relVer,
                showWideColumns: showWideColumns,
                border: border,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildEpicGroupCard({
    required WorkbenchProvider wb,
    required EpicSpec ep,
    required Color stripeColor,
    required String relVer,
    required bool showWideColumns,
    required Color border,
  }) {
    final isDark = widget.isDark;
    final surface = AppTheme.bgSurfaceFor(isDark);
    final headerBg = AppTheme.bgPanelFor(isDark);
    final insetBg = AppTheme.bgInsetFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);

    final visible = wb.visibleFeaturesForEpic(ep);
    final rollup = wb.epicFeatureRollup(ep);
    final collapsed = _collapsedEpicIds.contains(ep.id);

    return Container(
      key: ValueKey('monday_epic_group_${ep.id}'),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: border, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd - 1),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: stripeColor, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Group Header Bar
              Container(
                color: headerBg,
                padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
                child: Row(
                  children: [
                    InkWell(
                      key: ValueKey('table_epic_toggle_${ep.id}'),
                      onTap: () => setState(() {
                        if (collapsed) {
                          _collapsedEpicIds.remove(ep.id);
                        } else {
                          _collapsedEpicIds.add(ep.id);
                        }
                      }),
                      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          collapsed ? '▸' : '▾',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: muted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: InkWell(
                        key: ValueKey('table_epic_open_${ep.id}'),
                        onTap: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          wb.selectEpic(ep.id);
                        },
                        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          child: Row(
                            children: [
                              Text(
                                ep.code,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  ep.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: primary,
                                  ),
                                ),
                              ),
                              if (showWideColumns) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'Open ↗',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: focal,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (showWideColumns && ep.sceneOwnership.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${ep.sceneOwnership.length} @OWNERS',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: muted,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Text(
                      '${rollup.passed}/${rollup.total}',
                      key: ValueKey('table_epic_rollup_${ep.id}'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: rollup.openFixes > 0
                            ? red
                            : (rollup.total > 0 && rollup.passed == rollup.total
                                  ? green
                                  : muted),
                      ),
                    ),
                    const SizedBox(width: 12),
                    PlainTextLink(
                      key: ValueKey('table_epic_add_feature_${ep.id}'),
                      label: '+ Feature',
                      isDark: isDark,
                      fontSize: 11.5,
                      color: focal,
                      onTap: () => setState(() {
                        _collapsedEpicIds.remove(ep.id);
                        _inlineAddEpicId = _inlineAddEpicId == ep.id
                            ? null
                            : ep.id;
                        _inlineAddTitleCtrl.clear();
                      }),
                    ),
                  ],
                ),
              ),
              if (!collapsed) ...[
                Divider(height: 1, thickness: 1, color: border),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Text(
                      'No features in $relVer yet.',
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  )
                else ...[
                  // Column Labels Row
                  Container(
                    color: insetBg,
                    padding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
                    child: Row(
                      children: [
                        Expanded(child: _colHeader('FEATURE', muted)),
                        SizedBox(
                          width: showWideColumns ? 124 : 96,
                          child: _colHeader('STATUS', muted),
                        ),
                        if (showWideColumns)
                          SizedBox(
                            width: 124,
                            child: _colHeader('PIE GATE', muted),
                          ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: showWideColumns ? 192 : 96,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _colHeader('ACTION', muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final feat in visible) ...[
                    Divider(height: 1, thickness: 1, color: border),
                    _buildFeatureRow(
                      wb: wb,
                      ep: ep,
                      feat: feat,
                      relVer: relVer,
                      showWideColumns: showWideColumns,
                      isDark: isDark,
                      border: border,
                      primary: primary,
                      secondary: secondary,
                      muted: muted,
                      focal: focal,
                      green: green,
                      red: red,
                      amber: amber,
                      cyan: cyan,
                    ),
                  ],
                ],
                if (_inlineAddEpicId == ep.id) ...[
                  Divider(height: 1, thickness: 1, color: border),
                  Container(
                    color: insetBg,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: ValueKey('table_inline_feat_input_${ep.id}'),
                            controller: _inlineAddTitleCtrl,
                            autofocus: true,
                            style: TextStyle(fontSize: 13, color: primary),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'New feature title in ${ep.code}...',
                              hintStyle: TextStyle(fontSize: 12, color: muted),
                              border: UnderlineInputBorder(
                                borderSide: BorderSide(color: border),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: focal),
                              ),
                            ),
                            onSubmitted: (_) => _submitInlineAdd(ep.id),
                          ),
                        ),
                        const SizedBox(width: 10),
                        PlainPrimaryButton(
                          key: ValueKey('table_inline_feat_save_${ep.id}'),
                          label: 'Add Feature',
                          isDark: isDark,
                          onPressed: () => _submitInlineAdd(ep.id),
                        ),
                        const SizedBox(width: 8),
                        PlainTextLink(
                          label: 'Cancel',
                          isDark: isDark,
                          color: muted,
                          onTap: () => setState(() => _inlineAddEpicId = null),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required WorkbenchProvider wb,
    required EpicSpec ep,
    required FeatureSpec feat,
    required String relVer,
    required bool showWideColumns,
    required bool isDark,
    required Color border,
    required Color primary,
    required Color secondary,
    required Color muted,
    required Color focal,
    required Color green,
    required Color red,
    required Color amber,
    required Color cyan,
  }) {
    final isLockedBaseline = feat.isLockedBaselineInRelease(relVer);
    final isDelta = relVer != 'v0.1' && feat.releaseDelta.trim().isNotEmpty;
    final isNewInRel = relVer != 'v0.1' && feat.introducedIn.trim() == relVer;
    final passedInRel = isLockedBaseline
        ? feat.isPassed
        : feat.isPassedForRelease(relVer);
    final effChecks = feat.effectiveChecksForRelease(relVer);
    final doneChecks = feat.passedChecksCountForRelease(relVer);
    final totalChecks = effChecks.length;
    final ratio = totalChecks == 0 ? 0.0 : (doneChecks / totalChecks).clamp(0.0, 1.0);
    final subtitle = isLockedBaseline
        ? (feat.isPassed
              ? 'Shipped ${feat.introducedIn} · ${feat.goal}'
              : 'Locked ${feat.introducedIn} baseline (open in ${feat.introducedIn})')
        : (isDelta ? '+DELTA: ${feat.releaseDelta}' : feat.goal);

    final ({String label, Color color}) statusBadge;
    if (isLockedBaseline) {
      statusBadge = (
        label: feat.isPassed
            ? 'SHIPPED ${feat.introducedIn}'
            : 'OPEN ${feat.introducedIn}',
        color: muted,
      );
    } else if (feat.openFixesCount > 0) {
      statusBadge = (label: 'FIX (${feat.openFixesCount})', color: red);
    } else if (passedInRel) {
      statusBadge = (label: 'PASSED', color: green);
    } else {
      statusBadge = (label: 'OPEN', color: secondary);
    }

    final isCopiedHere = _copiedFeatureId == feat.id && _copiedTokens != null;
    final String copyBtnLabel;
    if (isCopiedHere) {
      copyBtnLabel = showWideColumns ? 'Copied (~$_copiedTokens tok)' : 'Copied';
    } else if (feat.openFixesCount > 0) {
      copyBtnLabel = showWideColumns
          ? 'Copy [FIX] (${feat.openFixesCount})'
          : 'Fix (${feat.openFixesCount})';
    } else {
      copyBtnLabel = showWideColumns ? 'Copy Prompt' : 'Copy';
    }

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: ValueKey('table_feature_row_${feat.id}'),
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                wb.selectFeature(ep.id, feat.id);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text(
                                feat.code,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: muted,
                                ),
                              ),
                              Text(
                                feat.title,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: isLockedBaseline ? secondary : primary,
                                ),
                              ),
                              if (isDelta)
                                _tagChip('+DELTA', amber),
                              if (isNewInRel)
                                _tagChip('+NEW $relVer', cyan),
                            ],
                          ),
                          if (subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDelta ? amber : muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: showWideColumns ? 124 : 96,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusBadge.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusXs,
                            ),
                            border: Border.all(
                              color: statusBadge.color.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            statusBadge.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: statusBadge.color,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (showWideColumns)
                      SizedBox(
                        width: 124,
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  minHeight: 5,
                                  backgroundColor: AppTheme.bgInsetFor(isDark),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    totalChecks > 0 && doneChecks == totalChecks
                                        ? green
                                        : focal,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$doneChecks/$totalChecks',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: showWideColumns ? 192 : 96,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: isLockedBaseline
                  ? PlainTextLink(
                      label: 'Inspect →',
                      isDark: isDark,
                      fontSize: 11.5,
                      color: muted,
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        wb.selectFeature(ep.id, feat.id);
                      },
                    )
                  : PlainPrimaryButton(
                      key: ValueKey('table_feature_copy_${feat.id}'),
                      label: copyBtnLabel,
                      icon: isCopiedHere
                          ? Icons.check_rounded
                          : (feat.openFixesCount > 0
                                ? Icons.build_outlined
                                : Icons.bolt_rounded),
                      outlined: !isCopiedHere && feat.openFixesCount == 0,
                      fillColor: isCopiedHere
                          ? green
                          : (feat.openFixesCount > 0 ? red : null),
                      isDark: isDark,
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        _triggerSilentRowCopy(
                          feat,
                          wb.activeFeatureBuildPrompt(ep, feat),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colHeader(String label, Color muted) {
    return Text(
      label,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: muted,
      ),
    );
  }

  Widget _tagChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
