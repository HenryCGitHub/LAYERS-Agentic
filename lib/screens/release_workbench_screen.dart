import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import '../utils/feature_spec_binding.dart';
import '../utils/section_text_utils.dart';

/// Stage 3 Screen: Active Release Workbench
/// - Left Rail: Core Loop Beats & Features switcher for the active Release
/// - Main Canvas:
///   - Release Completion Banner (when 100% of Checkpoints are VERIFIED ✓)
///   - Ultra-Compact Feature Header (Goal, Done When, Out of Scope badge, Inline Unassigned Spec Shelf)
///   - 60/40 Playable Checkpoint Cards (Checklist Left 60% | Playtest, Scope, Tuning, Edge Cases Right 40%)
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
  final Set<String> _expandedDoneCheckpoints = {};
  final Set<String> _collapsedOpenCheckpoints = {};

  bool get _isDark => widget.workbench.isDark;
  Color get _bgSurface => AppTheme.bgSurfaceFor(_isDark);
  Color get _cardBg => _isDark ? const Color(0xFF141822) : const Color(0xFFF8FAFC);
  Color get _borderColor => AppTheme.borderFor(_isDark);
  Color get _textPrimary => AppTheme.textPrimaryFor(_isDark);
  Color get _textSecondary => AppTheme.textSecondaryFor(_isDark);
  Color get _textMuted => AppTheme.textMutedFor(_isDark);

  @override
  Widget build(BuildContext context) {
    final rel = widget.workbench.activeRelease;
    if (rel == null) {
      return Center(
        child: Text(
          'No active Release loaded.',
          style: GoogleFonts.inter(color: _textMuted),
        ),
      );
    }

    if (widget.workbench.isAgentBusy) {
      return _buildAgentExecutionProgress(rel);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 280,
                child: _buildLeftBeatFeatureRail(rel),
              ),
              Expanded(
                child: _buildFeatureMainCanvas(rel),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLeftBeatFeatureRail(rel, shrinkWrap: true),
              const SizedBox(height: 16),
              _buildFeatureMainCanvas(rel, shrinkWrap: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAgentExecutionProgress(TierDocument rel) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.buttonBreakdown),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Building ${rel.title}...',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final step in widget.workbench.executionLog)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: AppTheme.accentGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: _textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftBeatFeatureRail(TierDocument rel, {bool shrinkWrap = false}) {
    final beats = widget.workbench.activeReleaseBeats;
    final relProgress = widget.workbench.getDocumentProgress(rel.id);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: _borderColor)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ACTIVE RELEASE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.tierRelease,
                    ),
                  ),
                  Text(
                    '$relProgress%',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: relProgress >= 100 ? AppTheme.accentGreen : AppTheme.tierRelease,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                rel.title,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ),
        for (final beat in beats) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppTheme.tierEpic,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    beat.title.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          for (final feat in widget.workbench.featuresForBeat(beat.id))
            _buildFeatureRailItem(feat),
        ],
      ],
    );

    if (shrinkWrap) {
      return Container(
        decoration: BoxDecoration(
          color: _bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderColor),
        ),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _bgSurface,
        border: Border(right: BorderSide(color: _borderColor)),
      ),
      child: SingleChildScrollView(child: content),
    );
  }

  Widget _buildFeatureRailItem(TierDocument feat) {
    final isSelected = widget.workbench.selectedFeatureId == feat.id;
    final progress = widget.workbench.getDocumentProgress(feat.id);
    final isDone = progress >= 100;

    return InkWell(
      key: ValueKey('rail_feat_${feat.id}'),
      onTap: () => widget.workbench.selectFeature(feat.id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.tierFeature.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: isSelected
                ? AppTheme.tierFeature.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14,
              color: isDone
                  ? AppTheme.accentGreen
                  : (isSelected ? AppTheme.tierFeature : _textMuted),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                feat.title,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: _textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$progress%',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isDone ? AppTheme.accentGreen : _textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureMainCanvas(TierDocument rel, {bool shrinkWrap = false}) {
    final feat = widget.workbench.selectedFeature;
    if (feat == null) {
      return Center(
        child: Text(
          'Select a Feature from the left rail.',
          style: GoogleFonts.inter(color: _textMuted),
        ),
      );
    }

    final states = FeatureStateNode.getStatesForDocument(feat);
    final specBinding = FeatureSpecBinding.resolveBindings(feat, states);
    final progress = widget.workbench.getDocumentProgress(feat.id).toDouble();
    final isDone = progress >= 100;

    int totalTasks = 0;
    int completedTasks = 0;
    int completedCps = 0;
    for (final s in states) {
      if (s.isCompleted) completedCps++;
      totalTasks += s.totalChecklistCount;
      completedTasks += s.completedChecklistCount;
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.workbench.isActiveReleaseComplete) ...[
          _buildReleaseShippedBanner(rel),
          const SizedBox(height: 16),
        ],
        _buildUltraCompactFeatureHeader(
          feat,
          states: states,
          specBinding: specBinding,
          statsLabel: '$completedCps/${states.length} cp · $completedTasks/$totalTasks tasks · ${feat.estimatedDuration}',
          progress: progress,
          isDone: isDone,
          presetLabel: rel.releaseScope.label,
        ),
        const SizedBox(height: 16),
        Text(
          'PLAYABLE CHECKPOINTS (${states.length})',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < states.length; i++)
          _buildCheckpointCard(
            feat,
            states,
            i,
            specBinding: specBinding,
          ),
      ],
    );

    if (shrinkWrap) return body;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: body,
        ),
      ),
    );
  }

  Widget _buildReleaseShippedBanner(TierDocument rel) {
    return Container(
      key: const ValueKey('release_complete_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.accentGreen.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accentGreen),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: AppTheme.accentGreen, size: 18),
              const SizedBox(width: 10),
              Text(
                'All Checkpoints in ${rel.title} are VERIFIED ✓!',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          ElevatedButton.icon(
            key: const ValueKey('ship_and_plan_next_release_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () => widget.workbench.advanceToNextRelease(),
            icon: const Icon(Icons.arrow_forward_rounded, size: 15),
            label: const Text('Ship & Plan Next Release ✦'),
          ),
        ],
      ),
    );
  }

  Widget _buildUltraCompactFeatureHeader(
    TierDocument feat, {
    required List<FeatureStateNode> states,
    required FeatureSpecBindingResult specBinding,
    required String statsLabel,
    required double progress,
    required bool isDone,
    required String presetLabel,
  }) {
    final scopeGoal = SectionTextUtils.resolveGoal(feat.sections);
    final doneIf = SectionTextUtils.resolveDoneWhen(feat.sections);
    final outOfScope = SectionTextUtils.resolveExclusions(
      feat.sections,
      splitSingleSentence: false,
    );

    Widget tag(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
          ),
          child: Text(
            text,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tag('F', AppTheme.tierFeature),
                        const SizedBox(width: 8),
                        Text(
                          feat.title,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        tag(presetLabel.toUpperCase(), AppTheme.tierRelease),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (outOfScope.isNotEmpty)
                          Container(
                            key: const ValueKey('feat_out_of_scope_btn'),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: _cardBg,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: _borderColor),
                            ),
                            child: Text(
                              '⊘ ${outOfScope.length} Out',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _textMuted,
                              ),
                            ),
                          ),
                        if (specBinding.hasUnassigned)
                          Container(
                            key: const ValueKey('feat_unassigned_spec_btn'),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              '${specBinding.totalUnassignedCount} unassigned',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    tag('GOAL', AppTheme.tierFeature),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        scopeGoal,
                        style: GoogleFonts.inter(fontSize: 11.5, color: _textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    tag('DONE WHEN', AppTheme.accentGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        doneIf,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentGreen,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statsLabel,
                      style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: _textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (specBinding.hasUnassigned)
            Container(
              key: const ValueKey('feat_inline_spec_shelf'),
              padding: const EdgeInsets.fromLTRB(14, 8, 12, 10),
              decoration: BoxDecoration(
                color: _cardBg,
                border: Border(top: BorderSide(color: _borderColor)),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final sc in specBinding.unassignedScope)
                    Text('✓ $sc', style: GoogleFonts.inter(fontSize: 10.5, color: _textPrimary)),
                  for (final t in specBinding.unassignedTuning)
                    Text('⚙ $t', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _textPrimary)),
                  for (final e in specBinding.unassignedEdgeCases)
                    Text('⚠ $e', style: GoogleFonts.inter(fontSize: 10.5, color: _textPrimary)),
                ],
              ),
            ),
          Container(
            height: 2,
            color: _borderColor.withValues(alpha: 0.35),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (progress / 100.0).clamp(0.0, 1.0),
              child: Container(
                color: isDone ? AppTheme.accentGreen : AppTheme.tierFeature,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckpointCard(
    TierDocument feat,
    List<FeatureStateNode> states,
    int index, {
    required FeatureSpecBindingResult specBinding,
  }) {
    final node = states[index];
    final isDone = node.isCompleted;
    final isCollapsed = isDone
        ? !_expandedDoneCheckpoints.contains(node.id)
        : _collapsedOpenCheckpoints.contains(node.id);

    final scopedItems = specBinding.checkpointScope[node.id] ?? const <String>[];
    final tuningItems = specBinding.checkpointTuning[node.id] ?? const <String>[];
    final edgeItems = specBinding.checkpointEdgeCases[node.id] ?? const <String>[];

    final checklistPane = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int tIdx = 0; tIdx < node.checklist.length; tIdx++)
            InkWell(
              key: ValueKey('task_checkbox_${node.id}_$tIdx'),
              onTap: () {
                node.checklist[tIdx].completed = !node.checklist[tIdx].completed;
                widget.workbench.updateFeatureStates(feat.id, states);
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      node.checklist[tIdx].completed
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 16,
                      color: node.checklist[tIdx].completed
                          ? AppTheme.accentGreen
                          : AppTheme.tierFeature,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        node.checklist[tIdx].text,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: node.checklist[tIdx].completed
                              ? _textMuted
                              : _textPrimary,
                          decoration: node.checklist[tIdx].completed
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    final specContextPane = Container(
      key: ValueKey('checkpoint_spec_pane_$index'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: _cardBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PLAYTEST',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.tierRelease,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.playtestCondition,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (scopedItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '↳ Scope: ${scopedItems.join(' · ')}',
              style: GoogleFonts.inter(fontSize: 11, color: _textSecondary),
            ),
          ],
          if (tuningItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                for (final t in tuningItems)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      t,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (edgeItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                for (final e in edgeItems)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      e,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: _textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: isCollapsed ? BorderSide.none : BorderSide(color: _borderColor),
              ),
            ),
            child: Row(
              children: [
                const Text('🚩', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text(
                  'CHECKPOINT ${index + 1}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.cleanStageTitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                ),
                if (isDone)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'VERIFIED ✓',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentGreen,
                      ),
                    ),
                  )
                else
                  Text(
                    '${node.completedChecklistCount}/${node.totalChecklistCount}',
                    style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: _textMuted),
                  ),
                const SizedBox(width: 6),
                InkWell(
                  key: ValueKey('checkpoint_toggle_$index'),
                  onTap: () {
                    setState(() {
                      if (isCollapsed) {
                        if (isDone) {
                          _expandedDoneCheckpoints.add(node.id);
                        } else {
                          _collapsedOpenCheckpoints.remove(node.id);
                        }
                      } else {
                        if (isDone) {
                          _expandedDoneCheckpoints.remove(node.id);
                        } else {
                          _collapsedOpenCheckpoints.add(node.id);
                        }
                      }
                    });
                  },
                  child: Icon(
                    isCollapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 18,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (!isCollapsed)
            LayoutBuilder(
              builder: (context, constraints) {
                final isTwoCol = constraints.maxWidth >= 560;
                if (isTwoCol) {
                  return IntrinsicHeight(
                    child: Row(
                      key: ValueKey('checkpoint_two_col_row_$index'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 60, child: checklistPane),
                        Container(width: 0.8, color: _borderColor),
                        Expanded(flex: 40, child: specContextPane),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    specContextPane,
                    checklistPane,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
