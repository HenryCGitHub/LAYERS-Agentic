import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../agents/workspace_agent_tools.dart';
import '../models/agent_blueprints.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';

/// Stage 2 Screen: The Antigravity Release Plan Gate
/// Shows:
/// 1. Clarifying Release Questions (multiple-choice)
/// 2. Proposed Core Loop Beats & Feature Scope Toggles (unchecking defers to Out of Scope)
/// 3. Confirmation Gate CTA: `[Approve & Build Release ✦]`
class ReleasePlanGateScreen extends StatefulWidget {
  final WorkbenchProvider workbench;

  const ReleasePlanGateScreen({
    super.key,
    required this.workbench,
  });

  @override
  State<ReleasePlanGateScreen> createState() => _ReleasePlanGateScreenState();
}

class _ReleasePlanGateScreenState extends State<ReleasePlanGateScreen>
    with WorkbenchThemeMixin {
  final TextEditingController _releaseChatController = TextEditingController();
  final Set<String> _expandedFeatureIds = {};
  final Set<int> _expandedOutlineBeatIndices = {};
  final Set<int> _collapsedOutlineBeatIndices = {};
  final Set<String> _expandedOutlineFeatureIds = {};
  final Map<String, TextEditingController> _newBeatFeatureControllers = {};
  bool _collapseQuestions = true;
  bool _isStepByBeatMode = true;
  int _activeBeatIndex = 0;

  @override
  bool get isDark => widget.workbench.isDark;

  String _nextReleaseVersionTag(String currentTag) {
    final match = RegExp(r'^v?(\d+)\.(\d+)').firstMatch(currentTag.trim());
    if (match != null) {
      final major = int.tryParse(match.group(1)!) ?? 0;
      final minor = int.tryParse(match.group(2)!) ?? 1;
      return 'v$major.${minor + 1}';
    }
    return 'v0.2';
  }

  bool _isBeatExpandedInOutline(int beatIdx) {
    if (_collapsedOutlineBeatIndices.contains(beatIdx)) return false;
    if (_expandedOutlineBeatIndices.contains(beatIdx)) return true;
    return _isStepByBeatMode && _activeBeatIndex == beatIdx;
  }

  void _toggleBeatExpandedInOutline(int beatIdx) {
    final currentlyExpanded = _isBeatExpandedInOutline(beatIdx);
    setState(() {
      if (currentlyExpanded) {
        _expandedOutlineBeatIndices.remove(beatIdx);
        _collapsedOutlineBeatIndices.add(beatIdx);
      } else {
        _collapsedOutlineBeatIndices.remove(beatIdx);
        _expandedOutlineBeatIndices.add(beatIdx);
      }
    });
  }

  TextEditingController _controllerForBeat(String beatId) {
    return _newBeatFeatureControllers.putIfAbsent(
      beatId,
      () => TextEditingController(),
    );
  }

  @override
  void dispose() {
    _releaseChatController.dispose();
    for (final c in _newBeatFeatureControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submitReleaseChat() async {
    final text = _releaseChatController.text.trim();
    if (text.isEmpty || widget.workbench.isAgentBusy) return;
    _releaseChatController.clear();
    await widget.workbench.sendReleasePlanChatMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final bp = widget.workbench.releaseBlueprint;
    if (bp == null) {
      return Container(
        color: bgBase,
        child: Center(
          child: Text(
            'No active Release Blueprint.',
            style: GoogleFonts.inter(color: textMuted),
          ),
        ),
      );
    }

    return Container(
      color: bgBase,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 780;
          final mainCanvasColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: _isStepByBeatMode ? 980 : 1120,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildGateBanner(bp),
                          const SizedBox(height: 10),
                          _buildStage2AgentStrip(),
                          const SizedBox(height: 10),
                          if (bp.questions.isNotEmpty) ...[
                            _buildReleaseQuestionsSection(bp),
                            const SizedBox(height: 18),
                          ],
                          _buildBeatsBlueprintSection(bp),
                          if (!_isStepByBeatMode) ...[
                            const SizedBox(height: 22),
                            _buildOutOfScopeSummarySection(bp),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _buildStickyBottomDock(bp),
            ],
          );

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 220,
                  child: _buildLeftReleaseOutlinerRail(bp),
                ),
                Expanded(child: mainCanvasColumn),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 308,
                child: _buildLeftReleaseOutlinerRail(bp),
              ),
              Expanded(child: mainCanvasColumn),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStage2AgentStrip() {
    final interventions = widget.workbench.stage2Interventions;
    final trace = widget.workbench.lastAgentTrace;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (trace != null && trace.toolCalls.isNotEmpty)
          Container(
            key: const ValueKey('stage2_agent_trace_banner'),
            margin: EdgeInsets.only(bottom: interventions.isNotEmpty ? 8 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: bgSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accentEmerald.withValues(alpha: 0.42)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentEmerald.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'AGENT TRACE · ${trace.agentRole.toUpperCase()}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: accentEmerald,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${trace.toolCalls.map((c) => "⚙ ${c.toolName}").join(" · ")} — ${trace.reasoning}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => widget.workbench.clearLastAgentTrace(),
                  child: Text(
                    'Dismiss ×',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      color: textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        for (int i = 0; i < interventions.length; i++) ...[
          _buildInterventionBanner(interventions[i], i),
          if (i < interventions.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildInterventionBanner(AgentIntervention item, int index) {
    final color = item.severity == 'crimson'
        ? accentCrimson
        : (item.severity == 'emerald' ? accentEmerald : accentAmber);
    return Container(
      key: ValueKey('stage2_intervention_$index'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.badge,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.title,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.reason,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            key: ValueKey('stage2_apply_intervention_btn_$index'),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: bgBase,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => widget.workbench.applyAgentIntervention(item),
            child: Text(
              item.actionLabel,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryApproveButton(
    ReleaseBlueprint bp, {
    Key? key,
  }) {
    return ElevatedButton(
      key: key,
      style: ElevatedButton.styleFrom(
        backgroundColor: focalAccent,
        foregroundColor: focalAccentFg,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      onPressed: widget.workbench.isAgentBusy
          ? null
          : () => widget.workbench.approveAndExecuteReleasePlan(),
      child: Text(
        'Approve & Build Release (${bp.totalIncludedFeatures} Features · ${bp.totalIncludedHours}h) →',
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ── Unified 308px Left Release Outliner Rail (Overview, Core Loop Beats -> Features -> Build Tasks, & Queued for Next Release) ─
  Widget _buildLeftReleaseOutlinerRail(ReleaseBlueprint bp) {
    final nextVer = _nextReleaseVersionTag(bp.releaseVersionTag);
    final deferredItems = <({ProposedBeatBlueprint beat, ProposedFeatureBlueprint feat})>[
      for (final beat in bp.beats)
        for (final feat in beat.deferredFeatures) (beat: beat, feat: feat),
    ];

    return Container(
      key: const ValueKey('stage2_left_outliner_rail'),
      decoration: BoxDecoration(
        color: bgSurface,
        border: Border(
          right: BorderSide(color: borderSubtle),
          bottom: BorderSide(color: borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Single-Row Outliner Header (matches Stage 1 & Stage 3 grammar)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bgRecessed,
              border: Border(bottom: BorderSide(color: borderSubtle)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentAmber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: accentAmber.withValues(alpha: 0.42),
                    ),
                  ),
                  child: Text(
                    '${bp.releaseVersionTag.toUpperCase()} GATE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: accentAmber,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${bp.totalIncludedHours}h · ${bp.totalIncludedFeatures} Feats',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: accentEmerald,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (bp.totalDeferredHours > 0)
                  Text(
                    '${bp.totalDeferredHours}h → $nextVer',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: accentAmber,
                    ),
                  ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
              children: [
                _buildOutlineCategoryHeader('OVERVIEW & SCOPE'),
                InkWell(
                  key: const ValueKey('stage2_all_beats_chip'),
                  onTap: () {
                    setState(() {
                      _isStepByBeatMode = false;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: BoxDecoration(
                      color: !_isStepByBeatMode
                          ? focalAccent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: !_isStepByBeatMode
                            ? focalAccent.withValues(alpha: 0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '◫',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: !_isStepByBeatMode ? focalAccent : textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'All Beats (${bp.beats.length})',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: !_isStepByBeatMode
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: !_isStepByBeatMode
                                  ? textPrimary
                                  : textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${bp.totalIncludedHours}h',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: accentEmerald,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (bp.questions.isNotEmpty)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _collapseQuestions = !_collapseQuestions;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: !_collapseQuestions
                            ? bgHover
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: 11,
                            color: accentEmerald,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Playtest Priorities',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            '${bp.questions.length}/${bp.questions.length} ✓',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: accentEmerald,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 6),
                _buildOutlineCategoryHeader('CORE LOOP BEATS'),
                Container(
                  key: const ValueKey('stage2_beat_jump_bar'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int bIdx = 0; bIdx < bp.beats.length; bIdx++)
                        _buildOutlineBeatNode(bp, bIdx, nextVer),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                _buildOutlineCategoryHeader(
                  '↪ QUEUED FOR ${nextVer.toUpperCase()} & CUT',
                ),
                if (deferredItems.isEmpty && bp.explicitExclusions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      'No deferred features yet.',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: textMuted,
                      ),
                    ),
                  ),
                for (final dItem in deferredItems)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentAmber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: accentAmber.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '↪ ${dItem.feat.title} ($nextVer)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          key: ValueKey('outline_restore_deferred_feat_${dItem.feat.id}'),
                          onTap: () => widget.workbench.toggleProposedFeatureScope(
                            dItem.beat.id,
                            dItem.feat.id,
                            true,
                          ),
                          child: Text(
                            '+ Restore',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: accentEmerald,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final ex in bp.explicitExclusions.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Row(
                      children: [
                        Text(
                          '[CUT]',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            color: accentCrimson,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            ex,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutlineCategoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: Text(
        title,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: textMuted,
          letterSpacing: 0.9,
        ),
      ),
    );
  }

  Widget _buildOutlineBeatNode(
    ReleaseBlueprint bp,
    int bIdx,
    String nextVer,
  ) {
    final beat = bp.beats[bIdx];
    final isSelectedBeat = _isStepByBeatMode && _activeBeatIndex == bIdx;
    final isExpanded = _isBeatExpandedInOutline(bIdx);
    final beatNum = 'B${(bIdx + 1).toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('stage2_beat_chip_$bIdx'),
          onTap: () {
            setState(() {
              if (_isStepByBeatMode && _activeBeatIndex == bIdx) {
                _toggleBeatExpandedInOutline(bIdx);
              } else {
                _activeBeatIndex = bIdx;
                _isStepByBeatMode = true;
                _collapsedOutlineBeatIndices.remove(bIdx);
              }
            });
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: isSelectedBeat
                  ? focalAccent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelectedBeat
                    ? focalAccent.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleBeatExpandedInOutline(bIdx),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Text(
                      isExpanded ? '▾' : '▸',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isSelectedBeat ? focalAccent : textMuted,
                      ),
                    ),
                  ),
                ),
                Text(
                  beatNum,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: isSelectedBeat ? FontWeight.w800 : FontWeight.w600,
                    color: isSelectedBeat ? focalAccent : textMuted,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    beat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: isSelectedBeat ? FontWeight.w700 : FontWeight.w500,
                      color: isSelectedBeat ? textPrimary : textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${beat.includedFeatures.length}f · ${beat.totalIncludedHours}h',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isSelectedBeat ? focalAccent : textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded && beat.features.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 14, bottom: 5),
            padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isSelectedBeat
                      ? focalAccent.withValues(alpha: 0.35)
                      : borderSubtle,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int fIdx = 0; fIdx < beat.features.length; fIdx++)
                  Builder(
                    builder: (context) {
                      final feat = beat.features[fIdx];
                      final isFeatExpanded =
                          _expandedOutlineFeatureIds.contains(feat.id);
                      final allTasks = <String>[
                        for (final cp in feat.checkpoints) ...cp.tasks,
                      ];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            key: ValueKey('stage2_outline_feat_${feat.id}'),
                            onTap: () {
                              setState(() {
                                _activeBeatIndex = bIdx;
                                _isStepByBeatMode = true;
                                if (isFeatExpanded) {
                                  _expandedOutlineFeatureIds.remove(feat.id);
                                } else {
                                  _expandedOutlineFeatureIds.add(feat.id);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 3,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    isFeatExpanded ? '▾' : '▸',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9.5,
                                      color: textMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${feat.included ? "✓" : "↪"} ${feat.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        fontWeight: feat.included
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: feat.included
                                            ? textSecondary
                                            : textMuted,
                                        decoration: feat.included
                                            ? TextDecoration.none
                                            : TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    feat.included
                                        ? '${feat.activeDeltaHours}h'
                                        : '→ $nextVer',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: feat.included
                                          ? textMuted
                                          : accentAmber,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isFeatExpanded && allTasks.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 14,
                                bottom: 3,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (int tIdx = 0;
                                      tIdx < allTasks.length;
                                      tIdx++)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 1.5,
                                      ),
                                      child: Text(
                                        '0${tIdx + 1} · ${allTasks[tIdx]}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9,
                                          color: textMuted,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildGateBanner(ReleaseBlueprint bp) {
    final includedHours = bp.totalIncludedHours;
    final deferredHours = bp.totalDeferredHours;
    final nextVer = _nextReleaseVersionTag(bp.releaseVersionTag);
    final totalCandidateHours = includedHours + deferredHours;
    final ratio = totalCandidateHours > 0
        ? (includedHours / totalCandidateHours).clamp(0.08, 1.0)
        : 1.0;

    return Container(
      key: const ValueKey('release_plan_gate_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'STAGE 2 · RELEASE PLAN GATE',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: accentAmber,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${bp.beats.length} Beats · ${bp.totalIncludedFeatures} Included · ${bp.totalDeferredFeatures} Queued for $nextVer',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bp.releaseTitle,
                    style: AppTheme.displayFont(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                key: const ValueKey('stage2_view_mode_toggle_btn'),
                onTap: () {
                  setState(() {
                    _isStepByBeatMode = !_isStepByBeatMode;
                    if (_activeBeatIndex >= bp.beats.length) {
                      _activeBeatIndex = 0;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: bgRecessed,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: _isStepByBeatMode ? borderBright : borderSubtle,
                    ),
                  ),
                  child: Text(
                    _isStepByBeatMode
                        ? '▯ Step-by-Beat'
                        : '◫ Full Blueprint',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Live Visual Scope & Hour Budget Bar
          Container(
            key: const ValueKey('release_hour_budget_bar'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bgRecessed,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ACTIVE ${bp.releaseVersionTag.toUpperCase()} SCOPE BUDGET',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: textSecondary,
                      ),
                    ),
                    Text(
                      deferredHours > 0
                          ? '${includedHours}h Included · ${deferredHours}h Queued for $nextVer ↪'
                          : '${includedHours}h Included · 0h Deferred',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accentEmerald,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 5,
                    color: bgSurface,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ratio,
                      child: Container(
                        color: accentEmerald,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // GOAL Callout Blockquote
          _buildCalloutBar(
            badgeLabel: 'GOAL',
            statement: bp.goal,
            accentColor: focalAccent,
            highlightMetrics: false,
          ),
          const SizedBox(height: 6),
          // DONE WHEN Callout Blockquote with Metric Highlighting
          _buildCalloutBar(
            badgeLabel: 'DONE WHEN',
            statement: bp.doneWhen,
            accentColor: accentEmerald,
            highlightMetrics: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCalloutBar({
    required String badgeLabel,
    required String statement,
    required Color accentColor,
    required bool highlightMetrics,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              color: accentColor,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 68,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: highlightMetrics
                            ? accentEmerald.withValues(alpha: 0.12)
                            : bgSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: highlightMetrics
                              ? accentEmerald.withValues(alpha: 0.45)
                              : borderBright,
                        ),
                      ),
                      child: Text(
                        badgeLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: highlightMetrics ? accentEmerald : textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: highlightMetrics
                          ? _buildMetricHighlightedRichText(statement)
                          : Text(
                              statement,
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                height: 1.45,
                                color: textPrimary,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricHighlightedRichText(String statement) {
    final metricRegex = RegExp(
      r'\b(\d+(?:[\.\-]\d+)?(?:\s*(?:minute|minutes|min|second|seconds|sec|s|FPS|fps|key|keys|waves|wave|enemies|enemy|rooms|room|players|player|times|time|ms|%))?)\b',
      caseSensitive: false,
    );
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in metricRegex.allMatches(statement)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: statement.substring(lastEnd, match.start)));
      }
      final metricText = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: accentEmerald.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: accentEmerald.withValues(alpha: 0.42)),
            ),
            child: Text(
              metricText,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
          ),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < statement.length) {
      spans.add(TextSpan(text: statement.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          height: 1.45,
          color: textPrimary,
        ),
        children: spans,
      ),
    );
  }

  Widget _buildReleaseChatBar(ReleaseBlueprint bp) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: bgSurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderBright),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentAmber,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AGENT · ${widget.workbench.planningModel.toUpperCase()}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Conversational Release Plan Refinement',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (bp.chatHistory.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final msg in bp.chatHistory.reversed.take(2).toList().reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: msg.isUser ? accentAmber : accentEmerald,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    '${msg.isUser ? "You" : "Agent"}: ${msg.text}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: textSecondary,
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: bgSurface,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '[ASK AGENT]',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('release_plan_chat_input'),
                          controller: _releaseChatController,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Tell the Agent how to refine this Release Plan (e.g., "Add a wall-run feature to Beat 1", "Defer Beat 4")...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: textMuted,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onSubmitted: (_) => _submitReleaseChat(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey('send_release_chat_btn'),
                onPressed: widget.workbench.isAgentBusy ? null : _submitReleaseChat,
                style: OutlinedButton.styleFrom(
                  foregroundColor: textPrimary,
                  backgroundColor: bgSurface,
                  side: BorderSide(color: borderBright),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                child: Text(
                  widget.workbench.isAgentBusy ? 'Updating...' : 'Refine Plan',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String numLabel,
    required String title,
    String? trailingMeta,
  }) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderSubtle),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                numLabel,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: textSecondary.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (trailingMeta != null)
            Text(
              trailingMeta,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  ({String title, String description}) _splitQuestionOption(
    String rawOption,
    int optIdx,
  ) {
    final clean = rawOption
        .replaceFirst(RegExp(r'^\(Recommended\)\s*', caseSensitive: false), '')
        .trim();
    final colonIdx = clean.indexOf(':');
    if (colonIdx > 0 && colonIdx < 48 && colonIdx < clean.length - 1) {
      return (
        title: clean.substring(0, colonIdx).trim(),
        description: clean.substring(colonIdx + 1).trim(),
      );
    }
    final words = clean.split(RegExp(r'\s+'));
    if (words.length <= 4) {
      return (title: clean, description: 'Apply this priority to the release blueprint.');
    }
    return (
      title: words.take(3).join(' '),
      description: clean,
    );
  }

  Widget _buildReleaseQuestionsSection(ReleaseBlueprint bp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '01',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CLARIFYING RELEASE QUESTIONS',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${bp.questions.length} Playtest Priorities · Live-Syncs Blueprint',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                  InkWell(
                    key: const ValueKey('toggle_release_questions_btn'),
                    onTap: () {
                      setState(() {
                        _collapseQuestions = !_collapseQuestions;
                      });
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: bgSurface,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: borderBright),
                      ),
                      child: Text(
                        _collapseQuestions
                            ? 'Edit Decisions ▾'
                            : 'Collapse Decisions ▴',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Compact Answered Decisions Summary Strip (always visible for quick glance)
        Container(
          key: const ValueKey('answered_decisions_strip'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bgSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderSubtle),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'DECISIONS (${bp.questions.length}/${bp.questions.length} ✓):',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: accentEmerald,
                ),
              ),
              for (int qIdx = 0; qIdx < bp.questions.length; qIdx++)
                Builder(
                  builder: (context) {
                    final q = bp.questions[qIdx];
                    final chosen = q.selectedOption.isNotEmpty
                        ? q.selectedOption
                        : (q.options.isNotEmpty ? q.options.first : '');
                    final parsed = _splitQuestionOption(chosen, 0);
                    return InkWell(
                      onTap: () {
                        if (_collapseQuestions) {
                          setState(() {
                            _collapseQuestions = false;
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: bgRecessed,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: borderSubtle,
                          ),
                        ),
                        child: Text(
                          'Q${qIdx + 1}: ${parsed.title} ✓',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        if (!_collapseQuestions) ...[
          const SizedBox(height: 12),
          for (int qIdx = 0; qIdx < bp.questions.length; qIdx++) ...[
            Container(
              margin: EdgeInsets.only(bottom: qIdx < bp.questions.length - 1 ? 12 : 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgRecessed,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          bp.questions[qIdx].question,
                          style: AppTheme.displayFont(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '✦ Live-syncs Done When',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: accentEmerald,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final opts = bp.questions[qIdx].options;
                      final isWide = constraints.maxWidth >= 680;
                      if (!isWide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int optIdx = 0; optIdx < opts.length; optIdx++) ...[
                              _buildQuestionOptionCard(
                                question: bp.questions[qIdx],
                                qIdx: qIdx,
                                optIdx: optIdx,
                                optionText: opts[optIdx],
                                isFirst: optIdx == 0,
                              ),
                              if (optIdx < opts.length - 1) const SizedBox(height: 8),
                            ],
                          ],
                        );
                      }
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int optIdx = 0; optIdx < opts.length; optIdx++) ...[
                              Expanded(
                                child: _buildQuestionOptionCard(
                                  question: bp.questions[qIdx],
                                  qIdx: qIdx,
                                  optIdx: optIdx,
                                  optionText: opts[optIdx],
                                  isFirst: optIdx == 0,
                                ),
                              ),
                              if (optIdx < opts.length - 1) const SizedBox(width: 10),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildQuestionOptionCard({
    required AgentQuestion question,
    required int qIdx,
    required int optIdx,
    required String optionText,
    required bool isFirst,
  }) {
    final isSelected = question.selectedOption == optionText;
    final parsed = _splitQuestionOption(optionText, optIdx);

    return Material(
      color: isSelected ? bgHover : bgSurface,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        key: ValueKey('release_question_card_${qIdx}_$optIdx'),
        onTap: () => widget.workbench.selectReleaseQuestionOption(
          question.id,
          optionText,
        ),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isSelected ? textPrimary : borderSubtle,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 15,
                        height: 15,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? focalAccent : Colors.transparent,
                          border: Border.all(
                            color: isSelected ? focalAccent : textMuted,
                            width: 1.4,
                          ),
                        ),
                        child: isSelected
                            ? Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: focalAccentFg,
                                ),
                              )
                            : null,
                      ),
                      if (isFirst)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentEmerald.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: accentEmerald.withValues(alpha: 0.42),
                            ),
                          ),
                          child: Text(
                            'RECOMMENDED',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: accentEmerald,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: bgRecessed,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Text(
                            'OPTION 0${optIdx + 1}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    parsed.title,
                    style: AppTheme.displayFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    parsed.description,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.5,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBeatsBlueprintSection(ReleaseBlueprint bp) {
    final nextVer = _nextReleaseVersionTag(bp.releaseVersionTag);
    final allFeatureIds = <String>[
      for (final b in bp.beats)
        for (final f in b.features) f.id,
    ];
    final allSpecsExpanded = allFeatureIds.isNotEmpty &&
        allFeatureIds.every((id) => _expandedFeatureIds.contains(id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '02',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CORE LOOP BEATS & PLAYABLE FEATURES',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Uncheck any feature to queue for $nextVer ↪',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                  InkWell(
                    key: const ValueKey('toggle_all_feat_specs_btn'),
                    onTap: () {
                      setState(() {
                        if (allSpecsExpanded) {
                          _expandedFeatureIds.clear();
                        } else {
                          _expandedFeatureIds.addAll(allFeatureIds);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: bgSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: borderSubtle),
                      ),
                      child: Text(
                        allSpecsExpanded ? 'Collapse All Specs ▴' : 'Expand All Specs ▾',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_isStepByBeatMode && bp.beats.isNotEmpty) ...[
          Builder(
            builder: (context) {
              final safeIdx = _activeBeatIndex.clamp(0, bp.beats.length - 1);
              return Column(
                key: const ValueKey('stage2_step_by_beat_card'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBeatCard(bp, bp.beats[safeIdx], safeIdx),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        key: const ValueKey('stage2_prev_beat_btn'),
                        onTap: safeIdx > 0
                            ? () => setState(() => _activeBeatIndex = safeIdx - 1)
                            : null,
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Text(
                            safeIdx > 0
                                ? '‹ Prev Beat: B${safeIdx.toString().padLeft(2, '0')} ${bp.beats[safeIdx - 1].title}'
                                : '‹ First Beat',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: safeIdx > 0 ? textSecondary : textMuted,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'BEAT ${safeIdx + 1} OF ${bp.beats.length}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: textSecondary,
                        ),
                      ),
                      InkWell(
                        key: const ValueKey('stage2_next_beat_btn'),
                        onTap: safeIdx < bp.beats.length - 1
                            ? () => setState(() => _activeBeatIndex = safeIdx + 1)
                            : () => setState(() => _isStepByBeatMode = false),
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: borderBright,
                            ),
                          ),
                          child: Text(
                            safeIdx < bp.beats.length - 1
                                ? 'Next Beat: B${(safeIdx + 2).toString().padLeft(2, '0')} ${bp.beats[safeIdx + 1].title} →'
                                : 'View Full Blueprint ◫',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ] else
          for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) ...[
            _buildBeatCard(bp, bp.beats[bIdx], bIdx),
            if (bIdx < bp.beats.length - 1)
              Row(
                children: [
                  const SizedBox(width: 47),
                  Container(
                    width: 2,
                    height: 10,
                    color: borderBright,
                  ),
                ],
              ),
          ],
      ],
    );
  }

  Widget _buildBeatCard(
    ReleaseBlueprint bp,
    ProposedBeatBlueprint beat,
    int beatIndex,
  ) {
    final beatCode = 'BEAT·${(beatIndex + 1).toString().padLeft(2, '0')}';
    final activeFeatures = beat.features.where((f) => !f.isSuperseded).toList();
    final allIncluded = activeFeatures.isNotEmpty && activeFeatures.every((f) => f.included);
    final beatCtrl = _controllerForBeat(beat.id);

    void submitNewBeatFeature() {
      final text = beatCtrl.text.trim();
      if (text.isEmpty) return;
      beatCtrl.clear();
      widget.workbench.addProposedFeatureToBeat(beat.id, text);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                key: ValueKey('toggle_beat_${beat.id}'),
                onTap: () => widget.workbench.toggleProposedBeatScope(
                  beat.id,
                  !allIncluded,
                ),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Icon(
                    allIncluded
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 17,
                    color: allIncluded ? accentEmerald : textMuted,
                  ),
                ),
              ),
              Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bgSurface,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: borderBright,
                  ),
                ),
                child: Text(
                  beatCode,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            beat.title,
                            style: AppTheme.displayFont(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Text(
                            '${beat.includedFeatures.length} Features · ${beat.totalIncludedHours}h',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      beat.goal,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 2-Column Feature Playing Cards when Beat has 2+ features and none are expanded
          LayoutBuilder(
            builder: (context, constraints) {
              final hasAnyExpanded = beat.features.any(
                (f) => _expandedFeatureIds.contains(f.id),
              );
              final useTwoCol = constraints.maxWidth >= 1060 &&
                  beat.features.length >= 2 &&
                  !hasAnyExpanded;
              if (!useTwoCol) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int fIdx = 0; fIdx < beat.features.length; fIdx++) ...[
                      _buildFeatureToggleRow(bp, beat, beat.features[fIdx]),
                      if (fIdx < beat.features.length - 1) const SizedBox(height: 7),
                    ],
                  ],
                );
              }
              final rows = <Widget>[];
              for (int i = 0; i < beat.features.length; i += 2) {
                final hasSecond = i + 1 < beat.features.length;
                rows.add(
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildFeatureToggleRow(
                            bp,
                            beat,
                            beat.features[i],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: hasSecond
                              ? _buildFeatureToggleRow(
                                  bp,
                                  beat,
                                  beat.features[i + 1],
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                );
                if (i + 2 < beat.features.length) {
                  rows.add(const SizedBox(height: 8));
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              );
            },
          ),
          const SizedBox(height: 8),
          // Inline "+ Add Feature to Beat" input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: bgSurface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: borderSubtle),
            ),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 15, color: textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: ValueKey('add_beat_feature_input_${beat.id}'),
                    controller: beatCtrl,
                    onSubmitted: (_) => submitNewBeatFeature(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 7),
                      hintText:
                          'Add playable feature to $beatCode (e.g., Slide Boost & Cancel)...',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: textMuted,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  key: ValueKey('add_beat_feature_btn_${beat.id}'),
                  onTap: submitNewBeatFeature,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Text(
                      '+ Add Feature (4h)',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
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

  Widget _buildFeatureToggleRow(
    ReleaseBlueprint bp,
    ProposedBeatBlueprint beat,
    ProposedFeatureBlueprint feat,
  ) {
    final isIncluded = feat.included;
    final isExpanded = _expandedFeatureIds.contains(feat.id);
    final nextVer = _nextReleaseVersionTag(bp.releaseVersionTag);
    final beatIdx = bp.beats.indexWhere((b) => b.id == beat.id);
    final featIdxInBeat = beat.features.indexWhere((f) => f.id == feat.id);
    final depTier = WorkspaceAgentOrchestrator.classifyDependencyTier(
      featureTitle: feat.title,
      beatIndex: beatIdx < 0 ? 0 : beatIdx,
      featureIndexInBeat: featIdxInBeat < 0 ? 0 : featIdxInBeat,
    );

    return Container(
      decoration: BoxDecoration(
        color: isIncluded ? bgSurface : bgRecessed.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isIncluded ? borderBright : borderSubtle,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  key: ValueKey('toggle_feat_${feat.id}'),
                  onTap: () => widget.workbench.toggleProposedFeatureScope(
                    beat.id,
                    feat.id,
                    !feat.included,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1, right: 2),
                    child: Icon(
                      isIncluded
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 16,
                      color: isIncluded ? accentEmerald : textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => widget.workbench.toggleProposedFeatureScope(
                      beat.id,
                      feat.id,
                      !feat.included,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              feat.title,
                              style: AppTheme.displayFont(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: isIncluded ? textPrimary : textMuted,
                              ).copyWith(
                                decoration: isIncluded
                                    ? TextDecoration.none
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            _buildLifecycleBadge(feat, bp.releaseVersionTag),
                            Container(
                              key: ValueKey('stage2_dep_tier_${feat.id}'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: bgRecessed,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: borderSubtle,
                                ),
                              ),
                              child: Text(
                                depTier.shortBadge,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                ),
                              ),
                            ),
                            if (feat.lifecycle == FeatureLifecycleStatus.upgrade)
                              Container(
                                key: ValueKey('stage2_upgrade_diff_${feat.id}'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: accentEmerald.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: accentEmerald.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  '${feat.originVersion} ✓ → +${feat.checkpoints.fold<int>(0, (sum, c) => sum + c.tasks.length)} ${bp.releaseVersionTag} Tasks',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    color: accentEmerald,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          !isIncluded &&
                                  feat.lifecycle !=
                                      FeatureLifecycleStatus.superseded
                              ? '↪ Queued for $nextVer Release Gate · ${feat.goal}'
                              : (feat.lifecycle == FeatureLifecycleStatus.stable
                                  ? 'Verified in ${feat.originVersion} · Untouched in ${bp.releaseVersionTag} (0h new work)'
                                  : feat.goal),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.45,
                            color: isIncluded ? textSecondary : textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (feat.checkpoints.isNotEmpty) ...[
                  Builder(
                    builder: (context) {
                      final totalTasksCount = feat.checkpoints.fold<int>(
                        0,
                        (sum, c) => sum + c.tasks.length,
                      );
                      return InkWell(
                        key: ValueKey('inspect_feat_${feat.id}'),
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedFeatureIds.remove(feat.id);
                            } else {
                              _expandedFeatureIds.add(feat.id);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isExpanded
                                ? bgHover
                                : bgRecessed,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isExpanded
                                  ? borderBright
                                  : borderSubtle,
                            ),
                          ),
                          child: Text(
                            '$totalTasksCount Tasks · ${feat.tuningParams.length} Tune ${isExpanded ? "▴" : "▾"}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: isExpanded ? textPrimary : textSecondary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                InkWell(
                  key: ValueKey('edit_stage2_feat_${feat.id}'),
                  onTap: () => _showEditProposedFeatureDialog(beat.id, feat),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: borderSubtle),
                    ),
                    child: Text(
                      'Edit ✎',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  key: ValueKey('edit_stage2_feat_hours_${feat.id}'),
                  onTap: () => _showEditProposedFeatureDialog(beat.id, feat),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    key: !isIncluded
                        ? ValueKey('stage2_queued_badge_${feat.id}')
                        : null,
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: !isIncluded
                          ? accentAmber.withValues(alpha: 0.14)
                          : (feat.lifecycle == FeatureLifecycleStatus.stable
                              ? accentEmerald.withValues(alpha: 0.12)
                              : bgRecessed),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: !isIncluded
                            ? accentAmber.withValues(alpha: 0.45)
                            : (feat.lifecycle == FeatureLifecycleStatus.stable
                                ? accentEmerald.withValues(alpha: 0.42)
                                : borderSubtle),
                      ),
                    ),
                    child: Text(
                      !isIncluded
                          ? (feat.lifecycle == FeatureLifecycleStatus.superseded
                              ? 'ARCHIVED'
                              : 'QUEUED FOR ${nextVer.toUpperCase()} ↪')
                          : (feat.lifecycle == FeatureLifecycleStatus.stable
                              ? 'STABLE · 0h'
                              : '${feat.activeDeltaHours}h'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: !isIncluded
                            ? accentAmber
                            : (feat.lifecycle == FeatureLifecycleStatus.stable
                                ? accentEmerald
                                : textPrimary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isExpanded)
            Container(
              key: ValueKey('inspect_feat_drawer_${feat.id}'),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: bgRecessed,
                border: Border(top: BorderSide(color: borderSubtle)),
              ),
              child: Builder(
                builder: (context) {
                  final allTasks = <String>[
                    for (final cp in feat.checkpoints) ...cp.tasks,
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentEmerald.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: accentEmerald.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              'FEATURE GOAL & PLAYTEST',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: accentEmerald,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feat.doneWhen,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (allTasks.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            for (int tIdx = 0; tIdx < allTasks.length; tIdx++)
                              Container(
                                width: 320,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: bgSurface,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: borderSubtle),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${(tIdx + 1).toString().padLeft(2, '0')} · ',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: accentAmber,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        allTasks[tIdx],
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (feat.tuningParams.isNotEmpty || feat.edgeCases.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final t in feat.tuningParams)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: bgSurface,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: borderSubtle,
                                  ),
                                ),
                                child: Text(
                                  '⚙ $t',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                            for (final e in feat.edgeCases)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: bgSurface,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: borderSubtle,
                                  ),
                                ),
                                child: Text(
                                  '⚠ $e',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLifecycleBadge(
    ProposedFeatureBlueprint feat,
    String releaseVersionTag,
  ) {
    String label;
    Color textColor;
    Color bgColor;
    Color borderColor;
    switch (feat.lifecycle) {
      case FeatureLifecycleStatus.stable:
        label = 'STABLE · ${feat.originVersion} ✓';
        textColor = accentEmerald;
        bgColor = accentEmerald.withValues(alpha: 0.14);
        borderColor = accentEmerald.withValues(alpha: 0.42);
        break;
      case FeatureLifecycleStatus.upgrade:
        label = '${feat.originVersion} → $releaseVersionTag';
        textColor = accentAmber;
        bgColor = accentAmber.withValues(alpha: 0.14);
        borderColor = accentAmber.withValues(alpha: 0.42);
        break;
      case FeatureLifecycleStatus.superseded:
        label = 'SUPERSEDED (${feat.originVersion})';
        textColor = textMuted;
        bgColor = bgRecessed;
        borderColor = borderSubtle;
        break;
      case FeatureLifecycleStatus.newFeature:
        label = 'NEW $releaseVersionTag';
        textColor = textSecondary;
        bgColor = bgRecessed;
        borderColor = borderSubtle;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildOutOfScopeSummarySection(ReleaseBlueprint bp) {
    final nextVer = _nextReleaseVersionTag(bp.releaseVersionTag);
    // Collect explicit exclusions + deferred features with their beatId/featId for 1-click Restore
    final items = <({String text, String? beatId, String? featId})>[
      for (final ex in bp.explicitExclusions)
        (text: ex, beatId: null, featId: null),
    ];
    for (final beat in bp.beats) {
      for (final deferred in beat.deferredFeatures) {
        final label = '${deferred.title} (queued from ${beat.title})';
        if (!items.any((it) => it.text == label)) {
          items.add((
            text: label,
            beatId: beat.id,
            featId: deferred.id,
          ));
        }
      }
    }

    Widget buildOutOfScopeCard(int idx) {
      final item = items[idx];
      final isDeferredFeat = item.beatId != null && item.featId != null;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgRecessed.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDeferredFeat
                ? accentAmber.withValues(alpha: 0.38)
                : borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDeferredFeat
                    ? accentAmber.withValues(alpha: 0.14)
                    : accentCrimson.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isDeferredFeat
                      ? accentAmber.withValues(alpha: 0.45)
                      : accentCrimson.withValues(alpha: 0.42),
                ),
              ),
              child: Text(
                isDeferredFeat ? 'QUEUED FOR ${nextVer.toUpperCase()} ↪' : 'CUT',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: isDeferredFeat ? accentAmber : accentCrimson,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.text,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: isDeferredFeat ? FontWeight.w600 : FontWeight.w400,
                  color: isDeferredFeat
                      ? textPrimary
                      : textSecondary.withValues(alpha: 0.85),
                ),
              ),
            ),
            if (isDeferredFeat) ...[
              const SizedBox(width: 8),
              InkWell(
                key: ValueKey('restore_deferred_feat_${item.featId}'),
                onTap: () => widget.workbench.toggleProposedFeatureScope(
                  item.beatId!,
                  item.featId!,
                  true,
                ),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: bgSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: borderBright),
                  ),
                  child: Text(
                    '+ Restore',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: accentEmerald,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          numLabel: '03',
          title: 'Queued for $nextVer & Out of Scope Exclusions',
          trailingMeta: '${items.length} Items',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final useTwoCol = constraints.maxWidth >= 620 && items.length > 1;
            if (!useTwoCol) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    buildOutOfScopeCard(i),
                    if (i < items.length - 1) const SizedBox(height: 7),
                  ],
                ],
              );
            }
            final rows = <Widget>[];
            for (int i = 0; i < items.length; i += 2) {
              final hasSecond = i + 1 < items.length;
              rows.add(
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: buildOutOfScopeCard(i)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: hasSecond
                            ? buildOutOfScopeCard(i + 1)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              );
              if (i + 2 < items.length) {
                rows.add(const SizedBox(height: 8));
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            );
          },
        ),
      ],
    );
  }

  Widget _buildStickyBottomDock(ReleaseBlueprint bp) {
    final includedBeatsCount = bp.beats
        .where((b) => b.features.any((f) => f.included))
        .length;

    return Container(
      key: const ValueKey('release_sticky_bottom_dock'),
      decoration: BoxDecoration(
        color: bgSurface,
        border: Border(top: BorderSide(color: borderBright)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildReleaseChatBar(bp),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            widget.workbench.setStage(WorkbenchStage.projectPitch),
                        icon: const Icon(Icons.arrow_back_rounded, size: 14),
                        label: Text(
                          'Back to Project Concept',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          backgroundColor: bgRecessed,
                          side: BorderSide(color: borderSubtle),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: bgRecessed,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: borderSubtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 13,
                              color: accentEmerald,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$includedBeatsCount Beats · ${bp.totalIncludedFeatures} Features · ~${bp.totalIncludedHours}h selected',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _buildPrimaryApproveButton(
                    bp,
                    key: const ValueKey('approve_and_build_release_btn'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditProposedFeatureDialog(
    String beatId,
    ProposedFeatureBlueprint feat,
  ) async {
    final titleCtrl = TextEditingController(text: feat.title);
    final hoursCtrl = TextEditingController(text: '${feat.estimatedHours}');
    final goalCtrl = TextEditingController(text: feat.goal);
    final doneWhenCtrl = TextEditingController(text: feat.doneWhen);
    final cpLines = [
      for (final c in feat.checkpoints) ...c.tasks,
    ].join('\n');
    final cpCtrl = TextEditingController(text: cpLines);
    final tuningCtrl = TextEditingController(
      text: feat.tuningParams.join(', '),
    );

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Edit Proposed Feature',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildDialogField(
                        label: 'FEATURE TITLE',
                        controller: titleCtrl,
                        fieldKey: const ValueKey('edit_feat_title_input'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: _buildDialogField(
                        label: 'HOURS',
                        controller: hoursCtrl,
                        fieldKey: const ValueKey('edit_feat_hours_input'),
                        mono: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildDialogField(
                  label: 'GOAL (1 SENTENCE)',
                  controller: goalCtrl,
                  fieldKey: const ValueKey('edit_feat_goal_input'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                _buildDialogField(
                  label: 'DONE WHEN (PLAYTEST CONDITION)',
                  controller: doneWhenCtrl,
                  fieldKey: const ValueKey('edit_feat_done_when_input'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                _buildDialogField(
                  label: 'BUILD TASKS (1 PER LINE)',
                  controller: cpCtrl,
                  fieldKey: const ValueKey('edit_feat_checkpoints_input'),
                  maxLines: 3,
                  mono: true,
                ),
                const SizedBox(height: 10),
                _buildDialogField(
                  label: 'TUNING PARAMETERS (COMMA SEPARATED)',
                  controller: tuningCtrl,
                  fieldKey: const ValueKey('edit_feat_tuning_input'),
                  mono: true,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('delete_stage2_feat_btn'),
            onPressed: () => Navigator.of(ctx).pop('delete'),
            child: Text(
              'Remove Feature',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accentCrimson,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('save_stage2_feat_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: Text(
              'Save Changes',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == 'cancel') return;
    if (action == 'delete') {
      widget.workbench.removeProposedFeatureFromBeat(beatId, feat.id);
      return;
    }

    final parsedHours = int.tryParse(
          hoursCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        feat.estimatedHours;
    final parsedTuning = tuningCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final rawTaskLines = cpCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final updatedCheckpoints = <ProposedCheckpointBlueprint>[];
    if (rawTaskLines.isNotEmpty) {
      final firstCp = feat.checkpoints.isNotEmpty ? feat.checkpoints.first : null;
      updatedCheckpoints.add(
        ProposedCheckpointBlueprint(
          title: firstCp?.title ?? titleCtrl.text.trim(),
          playtestCriteria: doneWhenCtrl.text.trim().isNotEmpty
              ? doneWhenCtrl.text.trim()
              : (firstCp?.playtestCriteria ?? feat.doneWhen),
          tasks: rawTaskLines,
          coveredScope: firstCp?.coveredScope ?? feat.inScope,
          tuningParams: parsedTuning,
          edgeCases: firstCp?.edgeCases ?? feat.edgeCases,
          releaseVersion: firstCp?.releaseVersion ?? feat.originVersion,
        ),
      );
    }

    widget.workbench.updateProposedFeatureInBeat(
      beatId: beatId,
      featureId: feat.id,
      title: titleCtrl.text,
      goal: goalCtrl.text,
      doneWhen: doneWhenCtrl.text,
      estimatedHours: parsedHours,
      checkpoints:
          updatedCheckpoints.isNotEmpty ? updatedCheckpoints : feat.checkpoints,
      tuningParams: parsedTuning,
    );
  }

  Widget _buildDialogField({
    required String label,
    required TextEditingController controller,
    required Key fieldKey,
    int maxLines = 1,
    bool mono = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: textMuted,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: fieldKey,
          controller: controller,
          maxLines: maxLines,
          style: mono
              ? GoogleFonts.jetBrainsMono(fontSize: 12, color: textPrimary)
              : GoogleFonts.inter(fontSize: 12.5, color: textPrimary),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 9,
            ),
            filled: true,
            fillColor: bgRecessed,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: borderSubtle),
            ),
          ),
        ),
      ],
    );
  }
}
