import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/agent_blueprints.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'stage1_shared_widgets.dart';

/// Stage 1 `§05 Seeded Epics & Initial v0.1 Feature Slices` preview,
/// lean scope indicator, Epic reorder/remove, and inline Feature slice renames.
class Stage1EpicPreviewSection extends StatefulWidget {
  final WorkbenchProvider workbench;
  final ProjectConceptBlueprint spec;
  final String? activeProjectId;
  final bool isUpdated;

  const Stage1EpicPreviewSection({
    super.key,
    required this.workbench,
    required this.spec,
    required this.activeProjectId,
    required this.isUpdated,
  });

  @override
  State<Stage1EpicPreviewSection> createState() =>
      _Stage1EpicPreviewSectionState();
}

class _Stage1EpicPreviewSectionState extends State<Stage1EpicPreviewSection> {
  final TextEditingController _featureTitleController = TextEditingController();
  String? _editingFeatureId;

  @override
  void didUpdateWidget(covariant Stage1EpicPreviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeProjectId != widget.activeProjectId ||
        (!widget.spec.hasSpec && _editingFeatureId != null)) {
      _editingFeatureId = null;
      _featureTitleController.clear();
    }
  }

  @override
  void dispose() {
    _featureTitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final spec = widget.spec;
    final isDark = wb.isDark;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);
    final scope = Stage1ScopeSummary.fromBlueprint(spec);

    return Stage1SectionCard(
      isDark: isDark,
      code: '§05',
      title: 'Seeded Epics & Initial v0.1 Feature Slices',
      isUpdated: widget.isUpdated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: green.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 15, color: green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Strict v0.1 Prototype Gate: Only these Epics build first. v0.2+ waves & meta unlock after v0.1 passes Playtest.',
                    style: TextStyle(fontSize: 12, color: textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('stage1_scope_preview_card'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgSurfaceFor(isDark),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(
                color: scope.isLean ? border : amber.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (scope.isLean ? green : amber)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusXs,
                            ),
                          ),
                          child: Text(
                            scope.isLean ? 'Lean v0.1' : 'Scope Check',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: scope.isLean ? green : amber,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${scope.epicCount} Epics · ${scope.featureCount} Features · ${scope.formattedDuration} · ${scope.inputActionCount} Inputs',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11.5,
                            color: textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if (scope.featureCount > 8 || scope.epicCount > 4)
                      ActionChip(
                        key: const ValueKey('stage1_trim_lean_btn'),
                        label: Text(
                          'Trim to Lean v0.1',
                          style: TextStyle(fontSize: 11, color: textPrimary),
                        ),
                        onPressed: wb.isAgentBusy
                            ? null
                            : () => wb.applyStage1CoDesignInstruction(
                                  'Trim v0.1 scope to 2-3 Epics (<= 6 Features total) and move extra systems into §04 Hard Scope Cuts.',
                                ),
                      ),
                  ],
                ),
                if (scope.warnings.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final w in scope.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• $w',
                        style: TextStyle(fontSize: 11.5, color: amber),
                      ),
                    ),
                ],
                if (scope.firstFeatureLabel != null ||
                    scope.firstPlaytestGate != null) ...[
                  const SizedBox(height: 8),
                  Divider(height: 1, color: border),
                  const SizedBox(height: 8),
                  Text(
                    'First Playtest (${scope.firstFeatureLabel ?? 'F01'}) · ${scope.firstTestScenePath ?? '/Game/Maps/Lvl_ArenaProto.umap'}',
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: cyan),
                  ),
                  if (scope.firstPlaytestGate != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      scope.firstPlaytestGate!,
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Release Done When: ${spec.releaseDoneWhen}',
            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: cyan),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < spec.initialEpics.length; i++)
            _buildStage1EpicCard(
              wb: wb,
              spec: spec,
              epic: spec.initialEpics[i],
              index: i,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              textMuted: textMuted,
              border: border,
              cyan: cyan,
              green: green,
            ),
        ],
      ),
    );
  }

  Widget _buildStage1EpicCard({
    required WorkbenchProvider wb,
    required ProjectConceptBlueprint spec,
    required EpicSpec epic,
    required int index,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color border,
    required Color cyan,
    required Color green,
  }) {
    final v01Features = epic.featuresForRelease('v0.1');
    final beatText = epic.coreLoopBeat.trim().isNotEmpty
        ? epic.coreLoopBeat.trim()
        : (index < spec.coreLoop.length
            ? 'Beat ${index + 1} · ${spec.coreLoop[index]}'
            : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: index == 0 ? green.withValues(alpha: 0.45) : border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cyan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                ),
                child: Text(
                  '${epic.code} · ${epic.releaseVersion}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cyan,
                  ),
                ),
              ),
              if (index == 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                  ),
                  child: Text(
                    '#1 Build First',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: green,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  epic.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                if (beatText.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    beatText,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: cyan.withValues(alpha: 0.9),
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  epic.goal,
                  style: TextStyle(fontSize: 12.5, color: textSecondary),
                ),
                if (v01Features.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Divider(height: 1, color: border),
                  const SizedBox(height: 6),
                  for (final feat in v01Features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _editingFeatureId == feat.id
                          ? Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: ValueKey('stage1_feat_input_${feat.id}'),
                                    controller: _featureTitleController,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11.5,
                                      color: textPrimary,
                                    ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                    ),
                                    onSubmitted: (val) {
                                      wb.renameStage1FeatureSlice(
                                        index,
                                        feat.id,
                                        val,
                                      );
                                      setState(() => _editingFeatureId = null);
                                    },
                                  ),
                                ),
                                IconButton(
                                  key: ValueKey('stage1_feat_save_${feat.id}'),
                                  tooltip: 'Save slice name',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  icon: Icon(
                                    Icons.check_rounded,
                                    size: 15,
                                    color: green,
                                  ),
                                  onPressed: () {
                                    wb.renameStage1FeatureSlice(
                                      index,
                                      feat.id,
                                      _featureTitleController.text,
                                    );
                                    setState(() => _editingFeatureId = null);
                                  },
                                ),
                                IconButton(
                                  key: ValueKey('stage1_feat_cancel_${feat.id}'),
                                  tooltip: 'Cancel rename',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                  ),
                                  onPressed: () =>
                                      setState(() => _editingFeatureId = null),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${feat.code} · ${feat.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11.5,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  feat.sliceTime,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: textMuted,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  key: ValueKey('stage1_feat_edit_${feat.id}'),
                                  tooltip: 'Rename Feature slice',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                    minHeight: 22,
                                  ),
                                  iconSize: 13,
                                  color: textSecondary,
                                  onPressed: wb.isAgentBusy
                                      ? null
                                      : () {
                                          _featureTitleController.text =
                                              feat.title;
                                          setState(
                                            () => _editingFeatureId = feat.id,
                                          );
                                        },
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  key: ValueKey('stage1_feat_remove_${feat.id}'),
                                  tooltip: 'Remove Feature slice',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                    minHeight: 22,
                                  ),
                                  iconSize: 13,
                                  color: v01Features.length > 1
                                      ? AppTheme.accentRedFor(isDark)
                                      : textMuted.withValues(alpha: 0.3),
                                  onPressed: (!wb.isAgentBusy &&
                                          v01Features.length > 1)
                                      ? () => wb.removeStage1FeatureSlice(
                                            index,
                                            feat.id,
                                          )
                                      : null,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                v01Features.isNotEmpty
                    ? '${v01Features.length} Feature slices'
                    : '${epic.checks.length} Checks · ${epic.tuning.length} Tuning',
                textAlign: TextAlign.right,
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: textMuted),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: ValueKey('stage1_epic_up_$index'),
                    tooltip: 'Move earlier in Playtest queue',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    iconSize: 16,
                    color: (!wb.isAgentBusy && index > 0)
                        ? textSecondary
                        : textMuted.withValues(alpha: 0.3),
                    onPressed: (!wb.isAgentBusy && index > 0)
                        ? () => wb.moveInitialEpic(index, -1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    key: ValueKey('stage1_epic_down_$index'),
                    tooltip: 'Move later in Playtest queue',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    iconSize: 16,
                    color: (!wb.isAgentBusy &&
                            index < spec.initialEpics.length - 1)
                        ? textSecondary
                        : textMuted.withValues(alpha: 0.3),
                    onPressed: (!wb.isAgentBusy &&
                            index < spec.initialEpics.length - 1)
                        ? () => wb.moveInitialEpic(index, 1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  IconButton(
                    key: ValueKey('stage1_epic_remove_$index'),
                    tooltip: 'Remove from v0.1 scope',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    iconSize: 15,
                    color: (!wb.isAgentBusy && spec.initialEpics.length > 1)
                        ? AppTheme.accentRedFor(isDark)
                        : textMuted.withValues(alpha: 0.3),
                    onPressed: (!wb.isAgentBusy && spec.initialEpics.length > 1)
                        ? () => wb.removeInitialEpicAt(index)
                        : null,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
