import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/agent_blueprints.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import '../workbench/plain_doc_widgets.dart';
import 'stage1_shared_widgets.dart';

/// Flat Initial v0.1 Scope Preview inside the Stage 1 Project Brief.
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
  String? _editingFeatId;
  final TextEditingController _featCtrl = TextEditingController();
  String? _lastProjId;

  @override
  void initState() {
    super.initState();
    _lastProjId = widget.activeProjectId;
  }

  @override
  void didUpdateWidget(covariant Stage1EpicPreviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastProjId != widget.activeProjectId) {
      _lastProjId = widget.activeProjectId;
      _editingFeatId = null;
      _featCtrl.clear();
    }
  }

  @override
  void dispose() {
    _featCtrl.dispose();
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
    final focal = AppTheme.focalAccentFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);
    final scope = Stage1ScopeSummary.fromBlueprint(spec);

    return Stage1SectionCard(
      isDark: isDark,
      code: '05',
      title: 'Initial v0.1 Scope',
      isUpdated: widget.isUpdated,
      trailing: (scope.featureCount > 8 || scope.epicCount > 4)
          ? PlainTextLink(
              key: const ValueKey('stage1_trim_lean_btn'),
              label: 'Trim to Lean v0.1',
              isDark: isDark,
              color: amber,
              fontSize: 11.5,
              onTap: wb.isAgentBusy
                  ? null
                  : () => wb.applyStage1CoDesignInstruction(
                        'Trim v0.1 scope to 2-3 Epics (<= 6 Features total) and move extra systems into §04 Hard Scope Cuts.',
                      ),
            )
          : null,
      child: Column(
        key: const ValueKey('stage1_scope_preview_card'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${scope.isLean ? 'Lean v0.1' : 'Scope Check'} · ${scope.epicCount} Epics · ${scope.featureCount} Features · ${scope.formattedDuration} · ${scope.inputActionCount} Inputs',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11.5,
                    color: scope.isLean ? textPrimary : amber,
                  ),
                ),
                if (scope.warnings.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  for (final w in scope.warnings)
                    Text(
                      '• $w',
                      style: TextStyle(fontSize: 12, color: amber),
                    ),
                ],
                if (scope.firstFeatureLabel != null ||
                    scope.firstPlaytestGate != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'First Playtest (${scope.firstFeatureLabel ?? 'F01'}) · ${scope.firstTestScenePath ?? '/Game/Maps/Lvl_ArenaProto.umap'}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: textMuted,
                    ),
                  ),
                  if (scope.firstPlaytestGate != null)
                    Text(
                      scope.firstPlaytestGate!,
                      style: TextStyle(fontSize: 12.5, color: textSecondary),
                    ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Release Done When: ${spec.releaseDoneWhen}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11.5,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < spec.initialEpics.length; i++)
            _buildEpicBlock(
              wb: wb,
              spec: spec,
              epic: spec.initialEpics[i],
              index: i,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              textMuted: textMuted,
              border: border,
              focal: focal,
            ),
        ],
      ),
    );
  }

  Widget _buildEpicBlock({
    required WorkbenchProvider wb,
    required ProjectConceptBlueprint spec,
    required EpicSpec epic,
    required int index,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color border,
    required Color focal,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                epic.code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  epic.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('stage1_epic_up_$index'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                tooltip: 'Move Up',
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  size: 14,
                  color: (!wb.isAgentBusy && index > 0)
                      ? textSecondary
                      : textMuted.withValues(alpha: 0.35),
                ),
                onPressed: (!wb.isAgentBusy && index > 0)
                    ? () => wb.moveInitialEpic(index, -1)
                    : null,
              ),
              IconButton(
                key: ValueKey('stage1_epic_down_$index'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                tooltip: 'Move Down',
                icon: Icon(
                  Icons.arrow_downward_rounded,
                  size: 14,
                  color: (!wb.isAgentBusy &&
                          index < spec.initialEpics.length - 1)
                      ? textSecondary
                      : textMuted.withValues(alpha: 0.35),
                ),
                onPressed: (!wb.isAgentBusy &&
                        index < spec.initialEpics.length - 1)
                    ? () => wb.moveInitialEpic(index, 1)
                    : null,
              ),
              IconButton(
                key: ValueKey('stage1_epic_remove_$index'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                tooltip: 'Remove Epic',
                icon: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: (!wb.isAgentBusy && spec.initialEpics.length > 1)
                      ? textMuted
                      : textMuted.withValues(alpha: 0.3),
                ),
                onPressed: (!wb.isAgentBusy && spec.initialEpics.length > 1)
                    ? () => wb.removeInitialEpicAt(index)
                    : null,
              ),
            ],
          ),
          if (epic.goal.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              epic.goal,
              style: TextStyle(fontSize: 12.5, color: textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          for (final feat in epic.features)
            _editingFeatId == feat.id
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: ValueKey('stage1_feat_input_${feat.id}'),
                            controller: _featCtrl,
                            autofocus: true,
                            style: TextStyle(fontSize: 13, color: textPrimary),
                            decoration: InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(
                                borderSide: BorderSide(color: border),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: focal),
                              ),
                            ),
                            onSubmitted: (val) {
                              wb.renameStage1FeatureSlice(index, feat.id, val);
                              setState(() => _editingFeatId = null);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        PlainPrimaryButton(
                          key: ValueKey('stage1_feat_save_${feat.id}'),
                          label: 'Save',
                          isDark: isDark,
                          onPressed: () {
                            wb.renameStage1FeatureSlice(
                              index,
                              feat.id,
                              _featCtrl.text,
                            );
                            setState(() => _editingFeatId = null);
                          },
                        ),
                        const SizedBox(width: 6),
                        PlainTextLink(
                          key: ValueKey('stage1_feat_cancel_${feat.id}'),
                          label: 'Cancel',
                          isDark: isDark,
                          color: textMuted,
                          onTap: () => setState(() => _editingFeatId = null),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${feat.code} · ${feat.title}',
                            style: TextStyle(fontSize: 13, color: textPrimary),
                          ),
                        ),
                        if (feat.sliceTime.trim().isNotEmpty) ...[
                          Text(
                            feat.sliceTime,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        PlainTextLink(
                          key: ValueKey('stage1_feat_edit_${feat.id}'),
                          label: 'Edit',
                          isDark: isDark,
                          fontSize: 11.5,
                          color: textMuted,
                          onTap: wb.isAgentBusy
                              ? null
                              : () {
                                  _featCtrl.text = feat.title;
                                  setState(() => _editingFeatId = feat.id);
                                },
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          key: ValueKey('stage1_feat_remove_${feat.id}'),
                          onTap: (!wb.isAgentBusy && epic.features.length > 1)
                              ? () => wb.removeStage1FeatureSlice(
                                    index,
                                    feat.id,
                                  )
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              '×',
                              style: TextStyle(
                                fontSize: 14,
                                color:
                                    (!wb.isAgentBusy && epic.features.length > 1)
                                        ? textMuted
                                        : textMuted.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
        ],
      ),
    );
  }
}
