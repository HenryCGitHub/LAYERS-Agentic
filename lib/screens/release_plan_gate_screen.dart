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
  final Map<String, TextEditingController> _newBeatFeatureControllers = {};
  bool _collapseQuestions = true;
  bool _isStepByBeatMode = true;
  int _activeBeatIndex = 0;

  /// Active section in the Stage 2 Flat Section Stepper:
  /// `'goal'`, `'questions'`, `'beat'` (uses `_activeBeatIndex`), `'queued'`, or `'full_review'`.
  String _activeStage2Section = 'beat';

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

  Widget _buildActiveStage2SectionWorkspace(ReleaseBlueprint bp) {
    final interventions = widget.workbench.stage2Interventions;
    if (!_isStepByBeatMode || _activeStage2Section == 'full_review') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildGateBanner(bp),
          const SizedBox(height: 18),
          if (interventions.isNotEmpty) ...[
            _buildScopeGuardSection(bp),
            const SizedBox(height: 22),
          ],
          if (bp.questions.isNotEmpty) ...[
            _buildReleaseQuestionsSection(bp),
            const SizedBox(height: 22),
          ],
          _buildBeatsBlueprintSection(bp),
          const SizedBox(height: 24),
          _buildOutOfScopeSummarySection(bp),
        ],
      );
    }

    switch (_activeStage2Section) {
      case 'goal':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildGateBanner(bp),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                key: const ValueKey('stage2_goal_next_btn'),
                onTap: () {
                  setState(() {
                    if (bp.questions.isNotEmpty) {
                      _activeStage2Section = 'questions';
                      _collapseQuestions = false;
                    } else {
                      _activeStage2Section = 'beat';
                      _activeBeatIndex = 0;
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Text(
                    bp.questions.isNotEmpty
                        ? 'Next Section: 02 Playtest Priorities →'
                        : 'Next Section: B01 →',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: accentCyan,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case 'questions':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildReleaseQuestionsSection(bp),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => setState(() => _activeStage2Section = 'goal'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      '‹ Prev Section: 01 Release Goal & Budget',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  key: const ValueKey('stage2_questions_next_btn'),
                  onTap: () => setState(() {
                    _activeStage2Section = 'beat';
                    _activeBeatIndex = 0;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      'Next Section: B01 ${bp.beats.isNotEmpty ? bp.beats.first.title : "Beats"} →',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: accentCyan,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case 'queued':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildOutOfScopeSummarySection(bp),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => setState(() {
                    _activeStage2Section = 'beat';
                    _activeBeatIndex = bp.beats.isNotEmpty ? bp.beats.length - 1 : 0;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      '‹ Prev Section: B${bp.beats.length.toString().padLeft(2, '0')}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  key: const ValueKey('stage2_queued_next_btn'),
                  onTap: () => setState(() {
                    _activeStage2Section = 'scope_guard';
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      'Next Section: Producer Scope Guard →',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: accentCyan,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case 'scope_guard':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildScopeGuardSection(bp),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => setState(() {
                    _activeStage2Section = 'queued';
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      '‹ Prev Section: Queued & Cuts',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  key: const ValueKey('stage2_scope_guard_next_btn'),
                  onTap: () => setState(() {
                    _isStepByBeatMode = false;
                    _activeStage2Section = 'full_review';
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      'Next: Full Release Review ◫ →',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: accentCyan,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case 'beat':
      default:
        // Dedicated 1-Beat-at-a-Time Focus Canvas (No Repeated Top Gate Banner or Clarifying Questions)
        return _buildBeatsBlueprintSection(bp);
    }
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
                          _buildStage2AgentStrip(),
                          _buildActiveStage2SectionWorkspace(bp),
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
                width: 280,
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
    final trace = widget.workbench.lastAgentTrace;

    if (trace == null || trace.toolCalls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        key: const ValueKey('stage2_agent_trace_banner'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bgSurface,
          border: Border(
            left: BorderSide(color: accentEmerald, width: 3),
            bottom: BorderSide(color: borderSubtle),
          ),
        ),
        child: Row(
          children: [
            Text(
              'AGENT TRACE · ${trace.agentRole.toUpperCase()}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: accentEmerald,
              ),
            ),
            const SizedBox(width: 10),
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
    );
  }

  Widget _buildScopeGuardSection(ReleaseBlueprint bp) {
    final interventions = widget.workbench.stage2Interventions;
    return Container(
      key: const ValueKey('stage2_scope_guard_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderSubtle)),
            ),
            child: Row(
              children: [
                Text(
                  '🛡 PRODUCER SCOPE GUARD',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: interventions.isEmpty ? accentEmerald : accentAmber,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    interventions.isEmpty
                        ? 'All ${bp.releaseVersionTag} scope & budget guardrails passing ✓'
                        : '${interventions.length} scope/budget recommendation${interventions.length == 1 ? "" : "s"} — Keep in Scope ✓ or Defer ✦',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: textSecondary,
                    ),
                  ),
                ),
                if (interventions.length > 1)
                  InkWell(
                    key: const ValueKey('stage2_keep_all_interventions_btn'),
                    onTap: () => widget.workbench.keepAllStage2Interventions(),
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: accentEmerald.withValues(alpha: 0.6),
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'Keep All in Scope ✓',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: accentEmerald,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (interventions.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: bgSurface,
                border: Border(
                  left: BorderSide(color: accentEmerald, width: 3),
                  bottom: BorderSide(color: borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '✓',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: accentEmerald,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No unresolved Out-of-Scope conflicts or oversized (>8h) features in ${bp.releaseVersionTag}.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < interventions.length; i++) ...[
              _buildInterventionBanner(interventions[i], i),
              if (i < interventions.length - 1) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _buildInterventionBanner(AgentIntervention item, int index) {
    final color = item.severity == 'crimson'
        ? accentCrimson
        : (item.severity == 'emerald' ? accentEmerald : accentAmber);
    return Container(
      key: ValueKey('stage2_intervention_$index'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgSurface,
        border: Border(
          left: BorderSide(color: color, width: 3),
          bottom: BorderSide(color: borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.badge,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                key: ValueKey('stage2_keep_intervention_btn_$index'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentEmerald,
                  side: BorderSide(color: accentEmerald.withValues(alpha: 0.65)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: () => widget.workbench.keepAgentIntervention(item),
                child: Text(
                  'Keep in Scope ✓',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                key: ValueKey('stage2_apply_intervention_btn_$index'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: bgBase,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
        backgroundColor: accentEmerald,
        foregroundColor: bgBase,
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

  // ── De-Boxed Flush Flat Section Stepper (`01 Goal & Budget`, `02 Priorities`, `B01..B0N`, `↪ Queued`, `🛡 Scope Guard`, `◫ Full Release Review`) ─
  Widget _buildLeftReleaseOutlinerRail(ReleaseBlueprint bp) {
    final nextVer = _nextReleaseVersionTag(bp.releaseVersionTag);
    final interventions = widget.workbench.stage2Interventions;
    final isGoalActive = _isStepByBeatMode && _activeStage2Section == 'goal';
    final isQuestionsActive =
        _isStepByBeatMode && _activeStage2Section == 'questions';
    final isQueuedActive = _isStepByBeatMode && _activeStage2Section == 'queued';
    final isScopeGuardActive =
        _isStepByBeatMode && _activeStage2Section == 'scope_guard';
    final isFullReviewActive =
        !_isStepByBeatMode || _activeStage2Section == 'full_review';

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
          // Single-Row Flush Stepper Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: bgRecessed,
              border: Border(bottom: BorderSide(color: borderSubtle)),
            ),
            child: Row(
              children: [
                Text(
                  '${bp.releaseVersionTag.toUpperCase()} GATE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: accentCyan,
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
              padding: EdgeInsets.zero,
              children: [
                // 01 Release Goal & Budget
                _buildFlushStepperRow(
                  rowKey: const ValueKey('stage2_step_goal'),
                  code: '01',
                  title: 'Release Goal & Budget',
                  trailingText: '✓',
                  trailingColor: accentEmerald,
                  isActive: isGoalActive,
                  onTap: () {
                    setState(() {
                      _isStepByBeatMode = true;
                      _activeStage2Section = 'goal';
                    });
                  },
                ),

                // 02 Playtest Priorities
                if (bp.questions.isNotEmpty)
                  _buildFlushStepperRow(
                    rowKey: const ValueKey('stage2_step_questions'),
                    code: '02',
                    title: 'Playtest Priorities',
                    trailingText: '${bp.questions.length}/${bp.questions.length} ✓',
                    trailingColor: accentEmerald,
                    isActive: isQuestionsActive,
                    onTap: () {
                      setState(() {
                        _isStepByBeatMode = true;
                        _activeStage2Section = 'questions';
                        _collapseQuestions = false;
                      });
                    },
                  ),

                // B01..B0N Core Loop Beats
                Container(
                  key: const ValueKey('stage2_beat_jump_bar'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int bIdx = 0; bIdx < bp.beats.length; bIdx++)
                        _buildOutlineBeatNode(bp, bIdx),
                    ],
                  ),
                ),

                // ↪ Out of Scope & Planned for Next Release
                _buildFlushStepperRow(
                  rowKey: const ValueKey('stage2_step_queued'),
                  code: '↪',
                  codeColor: accentAmber,
                  title: 'Out of Scope & $nextVer',
                  trailingText: bp.totalDeferredFeatures > 0
                      ? '+${bp.totalDeferredFeatures}f · ${bp.totalDeferredHours}h'
                      : '${bp.explicitExclusions.length} cuts',
                  trailingColor: bp.totalDeferredFeatures > 0
                      ? accentAmber
                      : accentCrimson,
                  isActive: isQueuedActive,
                  onTap: () {
                    setState(() {
                      _isStepByBeatMode = true;
                      _activeStage2Section = 'queued';
                    });
                  },
                ),

                // 🛡 Dedicated Producer Scope Guard Section
                _buildFlushStepperRow(
                  rowKey: const ValueKey('stage2_step_scope_guard'),
                  code: '🛡',
                  codeColor: interventions.isEmpty
                      ? accentEmerald
                      : accentAmber,
                  title: 'Producer Scope Guard',
                  trailingText: interventions.isEmpty
                      ? '✓ Clean'
                      : '${interventions.length} alert${interventions.length == 1 ? "" : "s"}',
                  trailingColor: interventions.isEmpty
                      ? accentEmerald
                      : accentCrimson,
                  isActive: isScopeGuardActive,
                  onTap: () {
                    setState(() {
                      _isStepByBeatMode = true;
                      _activeStage2Section = 'scope_guard';
                    });
                  },
                ),

                // Last Item in Outline: Full Release Review
                Material(
                  color: isFullReviewActive ? bgHover : bgRecessed,
                  child: InkWell(
                    key: const ValueKey('stage2_all_beats_chip'),
                    onTap: () {
                      setState(() {
                        _isStepByBeatMode = false;
                        _activeStage2Section = 'full_review';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: borderSubtle),
                          left: BorderSide(
                            color: isFullReviewActive ? accentCyan : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text(
                              '◫',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isFullReviewActive ? accentCyan : textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Full Release Review',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: isFullReviewActive
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: isFullReviewActive
                                        ? textPrimary
                                        : textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 1.5),
                                Text(
                                  'All ${bp.beats.length} Epics & Scope Budget',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    color: textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${bp.totalIncludedHours}h',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isFullReviewActive ? accentCyan : accentEmerald,
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
        ],
      ),
    );
  }

  Widget _buildFlushStepperRow({
    required Key rowKey,
    required String code,
    Color? codeColor,
    required String title,
    required String trailingText,
    required Color trailingColor,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isActive ? bgHover : Colors.transparent,
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10.5),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isActive ? accentCyan : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  code,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                    color: isActive
                        ? accentCyan
                        : (codeColor ?? textMuted),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? textPrimary : textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                trailingText,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isActive ? accentCyan : trailingColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutlineBeatNode(
    ReleaseBlueprint bp,
    int bIdx,
  ) {
    final beat = bp.beats[bIdx];
    final isSelectedBeat = _isStepByBeatMode &&
        _activeStage2Section == 'beat' &&
        _activeBeatIndex == bIdx;
    final beatNum = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
    final hasIncluded = beat.includedFeatures.isNotEmpty;
    final deferredCount = beat.deferredFeatures.length;

    return _buildFlushStepperRow(
      rowKey: ValueKey('stage2_beat_chip_$bIdx'),
      code: beatNum,
      title: beat.title,
      trailingText: deferredCount > 0
          ? '${beat.includedFeatures.length} in · +$deferredCount · ${beat.totalIncludedHours}h'
          : '${beat.includedFeatures.length}f · ${beat.totalIncludedHours}h',
      trailingColor: hasIncluded ? accentEmerald : textMuted,
      isActive: isSelectedBeat,
      onTap: () {
        setState(() {
          _activeBeatIndex = bIdx;
          _isStepByBeatMode = true;
          _activeStage2Section = 'beat';
        });
      },
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Wrap(
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
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: accentCyan,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${bp.beats.length} Epics · ${bp.totalIncludedFeatures} Included · ${bp.totalDeferredFeatures} Queued for $nextVer',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      bp.releaseTitle,
                      style: AppTheme.displayFont(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
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
                      _activeStage2Section =
                          _isStepByBeatMode ? 'beat' : 'full_review';
                      if (_activeBeatIndex >= bp.beats.length) {
                        _activeBeatIndex = 0;
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      _isStepByBeatMode
                          ? '▯ Step-by-Epic'
                          : '◫ Full Blueprint',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: accentCyan,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Open Editorial Scope & Hour Budget Bar
          Container(
            key: const ValueKey('release_hour_budget_bar'),
            padding: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
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
                        fontSize: 10,
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
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: accentEmerald,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 6,
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
          const SizedBox(height: 14),
          // GOAL Callout Left-Bar Blockquote
          _buildCalloutBar(
            badgeLabel: 'GOAL',
            statement: bp.goal,
            accentColor: accentCyan,
            highlightMetrics: false,
          ),
          const SizedBox(height: 12),
          // DONE WHEN Callout Left-Bar Blockquote with Metric Highlighting
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
      padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4, right: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: accentColor,
            width: 3,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                badgeLabel,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: highlightMetrics
                ? buildMetricHighlightedRichText(statement)
                : Text(
                    statement,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      height: 1.48,
                      color: textPrimary,
                    ),
                  ),
          ),
        ],
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
          padding: const EdgeInsets.only(bottom: 10),
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
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: accentCyan,
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
                spacing: 12,
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
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                      child: Text(
                        _collapseQuestions
                            ? 'Edit Decisions ▾'
                            : 'Collapse Decisions ▴',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accentCyan,
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
        // Open Left-Bar Answered Decisions Summary Strip
        Container(
          key: const ValueKey('answered_decisions_strip'),
          padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accentEmerald, width: 3),
            ),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'DECISIONS (${bp.questions.length}/${bp.questions.length} ✓):',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
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
                      child: Text(
                        'Q${qIdx + 1}: ${parsed.title} ✓',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        if (!_collapseQuestions) ...[
          const SizedBox(height: 16),
          for (int qIdx = 0; qIdx < bp.questions.length; qIdx++) ...[
            Container(
              padding: const EdgeInsets.only(bottom: 16),
              margin: EdgeInsets.only(bottom: qIdx < bp.questions.length - 1 ? 16 : 0),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: borderSubtle),
                ),
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
                            fontSize: 15,
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
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final opts = bp.questions[qIdx].options;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int optIdx = 0; optIdx < opts.length; optIdx++)
                            _buildQuestionOptionCard(
                              question: bp.questions[qIdx],
                              qIdx: qIdx,
                              optIdx: optIdx,
                              optionText: opts[optIdx],
                              isFirst: optIdx == 0,
                            ),
                        ],
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
      color: isSelected ? bgHover.withValues(alpha: 0.45) : Colors.transparent,
      child: InkWell(
        key: ValueKey('release_question_card_${qIdx}_$optIdx'),
        onTap: () => widget.workbench.selectReleaseQuestionOption(
          question.id,
          optionText,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(isSelected ? 13 : 8, 13, 8, 13),
          decoration: BoxDecoration(
            border: Border(
              left: isSelected
                  ? BorderSide(color: accentCyan, width: 3)
                  : BorderSide.none,
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Unified Radio Circle Indicator (Aligned with Stage 1 single-select options)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  width: 15,
                  height: 15,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? accentCyan : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? accentCyan : textMuted,
                      width: 1.4,
                    ),
                  ),
                  child: isSelected
                      ? Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: bgBase,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          parsed.title,
                          style: AppTheme.displayFont(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isFirst ? 'RECOMMENDED' : 'OPTION 0${optIdx + 1}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: isFirst ? accentCyan : textSecondary,
                              ),
                            ),
                            if (isSelected)
                              Text(
                                ' · SELECTED',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: accentEmerald,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      parsed.description,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.48,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
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
          padding: const EdgeInsets.only(bottom: 10),
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
                    'STAGE 2 · CORE LOOP EPICS & PLAYABLE FEATURES',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: accentCyan,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Uncheck any feature to queue for $nextVer ↪',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                      child: Text(
                        allSpecsExpanded ? 'Collapse All Specs ▴' : 'Expand All Specs ▾',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accentCyan,
                        ),
                      ),
                    ),
                  ),
                  if (_isStepByBeatMode)
                    InkWell(
                      key: const ValueKey('stage2_view_mode_toggle_btn'),
                      onTap: () {
                        setState(() {
                          _isStepByBeatMode = false;
                          _activeStage2Section = 'full_review';
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                        child: Text(
                          '◫ Full Blueprint',
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
          ),
        ),
        const SizedBox(height: 14),
        if (_isStepByBeatMode && bp.beats.isNotEmpty) ...[
          Builder(
            builder: (context) {
              final safeIdx = _activeBeatIndex.clamp(0, bp.beats.length - 1);
              return Column(
                key: const ValueKey('stage2_step_by_beat_card'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBeatCard(bp, bp.beats[safeIdx], safeIdx),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        key: const ValueKey('stage2_prev_beat_btn'),
                        onTap: safeIdx > 0
                            ? () => setState(() => _activeBeatIndex = safeIdx - 1)
                            : () => setState(() {
                                  if (bp.questions.isNotEmpty) {
                                    _activeStage2Section = 'questions';
                                    _collapseQuestions = false;
                                  } else {
                                    _activeStage2Section = 'goal';
                                  }
                                }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Text(
                            safeIdx > 0
                                ? '‹ Prev Epic: E${safeIdx.toString().padLeft(2, '0')} ${bp.beats[safeIdx - 1].title}'
                                : '‹ Prev: Playtest Priorities',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: textSecondary,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'EPIC ${safeIdx + 1} OF ${bp.beats.length}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accentCyan,
                        ),
                      ),
                      InkWell(
                        key: const ValueKey('stage2_next_beat_btn'),
                        onTap: safeIdx < bp.beats.length - 1
                            ? () => setState(() => _activeBeatIndex = safeIdx + 1)
                            : () => setState(() {
                                  _isStepByBeatMode = false;
                                  _activeStage2Section = 'full_review';
                                }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Text(
                            safeIdx < bp.beats.length - 1
                                ? 'Next Epic: E${(safeIdx + 2).toString().padLeft(2, '0')} ${bp.beats[safeIdx + 1].title} →'
                                : 'View Full Blueprint ◫ →',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: accentCyan,
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
            if (bIdx < bp.beats.length - 1) const SizedBox(height: 22),
          ],
      ],
    );
  }

  Widget _buildBeatCard(
    ReleaseBlueprint bp,
    ProposedBeatBlueprint beat,
    int beatIndex,
  ) {
    final beatCode = 'EPIC·${(beatIndex + 1).toString().padLeft(2, '0')}';
    final nextVer = _nextReleaseVersionTag(bp.releaseVersionTag);
    final activeFeatures = beat.features.where((f) => !f.isSuperseded).toList();
    final includedInEpic = beat.features.where((f) => f.included || f.isSuperseded).toList();
    final deferredInEpic = beat.deferredFeatures;
    final allIncluded = activeFeatures.isNotEmpty && activeFeatures.every((f) => f.included);
    final beatCtrl = _controllerForBeat(beat.id);

    void submitNewBeatFeature() {
      final text = beatCtrl.text.trim();
      if (text.isEmpty) return;
      beatCtrl.clear();
      widget.workbench.addProposedFeatureToBeat(beat.id, text);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Open Editorial Epic Header with 1px Bottom Hairline
        Container(
          padding: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Row(
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
                  padding: const EdgeInsets.only(top: 3, right: 10),
                  child: Icon(
                    allIncluded
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 18,
                    color: allIncluded ? accentEmerald : textMuted,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                beatCode,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: accentCyan,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  beat.title,
                                  style: AppTheme.displayFont(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          deferredInEpic.isNotEmpty
                              ? '${beat.includedFeatures.length} in ${bp.releaseVersionTag} · ${deferredInEpic.length} for $nextVer · ${beat.totalIncludedHours}h'
                              : '${beat.includedFeatures.length} Features · ${beat.totalIncludedHours}h',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: accentEmerald,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      beat.goal,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 1. In-Scope Features for Current Release
        for (final feat in includedInEpic)
          _buildFeatureToggleRow(bp, beat, feat),

        // 2. Out-of-Scope / Planned for Next Release Features right inside the Epic
        if (deferredInEpic.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: bgRecessed.withValues(alpha: 0.55),
              border: Border(
                left: BorderSide(color: accentAmber, width: 3),
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '↪ OUT OF SCOPE IN THIS EPIC · PLANNED FOR ${nextVer.toUpperCase()} (${deferredInEpic.length})',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: accentAmber,
                  ),
                ),
                Text(
                  'Check box to include in ${bp.releaseVersionTag}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ),
          for (final feat in deferredInEpic)
            _buildFeatureToggleRow(bp, beat, feat),
        ],

        const SizedBox(height: 10),
        // Inline "+ Add Feature to Epic" input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: borderSubtle),
            ),
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
                    fontSize: 12.5,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                    hintText:
                        'Add playable feature to $beatCode (e.g., Slide Boost & Cancel)...',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 12,
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
                      fontWeight: FontWeight.w800,
                      color: accentCyan,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
        border: Border(
          bottom: BorderSide(color: borderSubtle),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                  padding: const EdgeInsets.only(top: 1, right: 10),
                  child: Icon(
                    isIncluded
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 17,
                    color: isIncluded ? accentEmerald : textMuted,
                  ),
                ),
              ),
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
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            feat.title,
                            style: AppTheme.displayFont(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isIncluded ? textPrimary : textMuted,
                            ).copyWith(
                              decoration: isIncluded
                                  ? TextDecoration.none
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                          _buildLifecycleBadge(feat, bp.releaseVersionTag),
                          Text(
                            depTier.shortBadge,
                            key: ValueKey('stage2_dep_tier_${feat.id}'),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: accentCyan,
                            ),
                          ),
                          if (feat.lifecycle == FeatureLifecycleStatus.upgrade)
                            Text(
                              '${feat.originVersion} ✓ → +${feat.checkpoints.fold<int>(0, (sum, c) => sum + c.tasks.length)} ${bp.releaseVersionTag} Tasks',
                              key: ValueKey('stage2_upgrade_diff_${feat.id}'),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: accentEmerald,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        !isIncluded &&
                                feat.lifecycle !=
                                    FeatureLifecycleStatus.superseded
                            ? '↪ Queued for $nextVer Release Gate · ${feat.goal}'
                            : (feat.lifecycle == FeatureLifecycleStatus.stable
                                ? 'Verified in ${feat.originVersion} · Untouched in ${bp.releaseVersionTag} (0h new work)'
                                : feat.goal),
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Text(
                          '$totalTasksCount Tasks · ${feat.tuningParams.length} Tune ${isExpanded ? "▴" : "▾"}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isExpanded ? accentCyan : textSecondary,
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                  child: Text(
                    'Edit ✎',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: ValueKey('edit_stage2_feat_hours_${feat.id}'),
                onTap: () => _showEditProposedFeatureDialog(beat.id, feat),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  key: !isIncluded
                      ? ValueKey('stage2_queued_badge_${feat.id}')
                      : null,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
                  child: Text(
                    !isIncluded
                        ? (feat.lifecycle == FeatureLifecycleStatus.superseded
                            ? 'ARCHIVED'
                            : 'QUEUED FOR ${nextVer.toUpperCase()} ↪')
                        : (feat.lifecycle == FeatureLifecycleStatus.stable
                            ? 'STABLE · 0h'
                            : '${feat.activeDeltaHours}h'),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
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
          // ── 2px Vertical Spec Thread (No Box-Inside-Box Drawer) ──
          if (isExpanded)
            Container(
              key: ValueKey('inspect_feat_drawer_${feat.id}'),
              margin: const EdgeInsets.only(left: 27, top: 10),
              padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: borderBright, width: 2),
                ),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 148,
                            child: Text(
                              'FEATURE GOAL & PLAYTEST',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
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
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (allTasks.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (int tIdx = 0; tIdx < allTasks.length; tIdx++)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: borderSubtle.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${(tIdx + 1).toString().padLeft(2, '0')} · ',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: accentCyan,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    allTasks[tIdx],
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      if (feat.tuningParams.isNotEmpty || feat.edgeCases.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 14,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final t in feat.tuningParams)
                              Text(
                                '⚙ $t',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: accentViolet,
                                ),
                              ),
                            for (final e in feat.edgeCases)
                              Text(
                                '⚠ $e',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: accentAmber,
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
    switch (feat.lifecycle) {
      case FeatureLifecycleStatus.stable:
        label = 'STABLE · ${feat.originVersion} ✓';
        textColor = accentEmerald;
        break;
      case FeatureLifecycleStatus.upgrade:
        label = '${feat.originVersion} → $releaseVersionTag';
        textColor = accentAmber;
        break;
      case FeatureLifecycleStatus.superseded:
        label = 'SUPERSEDED (${feat.originVersion})';
        textColor = textMuted;
        break;
      case FeatureLifecycleStatus.newFeature:
        label = 'NEW $releaseVersionTag';
        textColor = accentCyan;
        break;
    }

    return Text(
      label,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        color: textColor,
      ),
    );
  }

  Widget _buildOutOfScopeSummarySection(ReleaseBlueprint bp) {
    final nextVer = _nextReleaseVersionTag(bp.releaseVersionTag);
    final deferredItems = <({
      String text,
      String epicCode,
      String epicTitle,
      String goal,
      int hours,
      String beatId,
      String featId,
    })>[];
    for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) {
      final beat = bp.beats[bIdx];
      final epicCode = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      for (final deferred in beat.deferredFeatures) {
        final label = '${deferred.title} ($epicCode · ${beat.title})';
        if (!deferredItems.any((it) => it.featId == deferred.id)) {
          deferredItems.add((
            text: label,
            epicCode: epicCode,
            epicTitle: beat.title,
            goal: deferred.goal,
            hours: deferred.estimatedHours,
            beatId: beat.id,
            featId: deferred.id,
          ));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          numLabel: '↪',
          title: 'Out of Scope & Planned for $nextVer',
          trailingMeta:
              '${deferredItems.length} Planned for $nextVer · ${bp.explicitExclusions.length} Cuts',
        ),
        const SizedBox(height: 14),
        // Open 3px Amber Left-Bar Section: Out of Scope Features Planned for Next Release
        Container(
          padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accentAmber, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '↪ OUT OF SCOPE FEATURES · PLANNED FOR ${nextVer.toUpperCase()} RELEASE',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: accentAmber,
                ),
              ),
              const SizedBox(height: 6),
              if (deferredItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'All proposed features are currently included in ${bp.releaseVersionTag}. Uncheck any feature inside an Epic to plan it for $nextVer.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: textMuted,
                    ),
                  ),
                ),
              for (final item in deferredItems)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: borderSubtle),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${item.epicCode} · ${nextVer.toUpperCase()} ↪',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: accentAmber,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.text,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                            if (item.goal.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.goal,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${item.hours}h',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        key: ValueKey('restore_deferred_feat_${item.featId}'),
                        onTap: () => widget.workbench.toggleProposedFeatureScope(
                          item.beatId,
                          item.featId,
                          true,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            '+ Keep in ${bp.releaseVersionTag}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: accentEmerald,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (bp.explicitExclusions.isNotEmpty) ...[
          const SizedBox(height: 18),
          // Open 3px Rose Left-Bar Section: Permanent Concept Exclusions
          Container(
            padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: accentCrimson, width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '✕ PERMANENT CONCEPT EXCLUSIONS (NEVER BUILT)',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: accentCrimson,
                  ),
                ),
                const SizedBox(height: 6),
                for (final ex in bp.explicitExclusions)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: borderSubtle),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            '✕ CUT',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: accentCrimson,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ex,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: textSecondary,
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
                              '$includedBeatsCount Epics · ${bp.totalIncludedFeatures} Features · ~${bp.totalIncludedHours}h selected',
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
