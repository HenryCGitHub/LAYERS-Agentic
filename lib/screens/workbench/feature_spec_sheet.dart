import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'workbench_shared_widgets.dart';

class FeatureSpecSheet extends StatefulWidget {
  final WorkbenchProvider workbench;
  final EpicSpec epic;
  final FeatureSpec feature;
  final bool isLockedBaseline;
  final bool isDark;
  final String selectionKey;
  final String? passGateHint;

  const FeatureSpecSheet({
    super.key,
    required this.workbench,
    required this.epic,
    required this.feature,
    required this.isLockedBaseline,
    required this.isDark,
    required this.selectionKey,
    required this.passGateHint,
  });

  @override
  State<FeatureSpecSheet> createState() => _FeatureSpecSheetState();
}

class _FeatureSpecSheetState extends State<FeatureSpecSheet> {
  final TextEditingController _fixInputController = TextEditingController();

  @override
  void didUpdateWidget(covariant FeatureSpecSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionKey != widget.selectionKey) {
      _fixInputController.clear();
    }
  }

  @override
  void dispose() {
    _fixInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.textPrimaryFor(widget.isDark);
    final secondary = AppTheme.textSecondaryFor(widget.isDark);
    final muted = AppTheme.textMutedFor(widget.isDark);
    final border = AppTheme.borderFor(widget.isDark);
    final cyan = AppTheme.accentCyanFor(widget.isDark);
    final green = AppTheme.accentGreenFor(widget.isDark);
    final red = AppTheme.accentRedFor(widget.isDark);
    final amber = AppTheme.accentAmberFor(widget.isDark);
    return _buildSheetContent(
      context,
      widget.workbench,
      widget.epic,
      widget.feature,
      widget.isLockedBaseline,
      widget.isDark,
      primary,
      secondary,
      muted,
      border,
      cyan,
      green,
      red,
      amber,
    );
  }

  Widget _buildSheetContent(
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
        EpicSectionCard(
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

        // §02 Input Actions (Enhanced Input)
        EpicSectionCard(
          isDark: isDark,
          code: '§02',
          title: 'Input Actions (${target.inputContractLabel})',
          child: feat.controls.isEmpty
              ? Text(
                  'Event/system-driven slice — uses parent Epic Enhanced Input triggers.',
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

        // §03 Exposed Tuning
        EpicSectionCard(
          isDark: isDark,
          code: '§03',
          title: 'Exposed Tuning (${target.tuningColumnLabel})',
          trailing: Text(
            isLockedBaseline
                ? 'Locked baseline'
                : 'Included in CoPilot Feature Prompt',
            style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: muted),
          ),
          child: feat.tuning.isEmpty
              ? Text(
                  'No exposed tuning variables on this slice.',
                  style: TextStyle(fontSize: 12.5, color: muted),
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (int i = 0; i < feat.tuning.length; i++)
                      LiveTuningChip(
                        key: ValueKey(
                          'tuning_chip_${wb.activeReleaseId}_${feat.id}_${feat.tuning[i].key}_$i',
                        ),
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
        EpicSectionCard(
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
        EpicSectionCard(
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

              if (widget.passGateHint != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.passGateHint!,
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
