import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

class _ReleasePlanGateScreenState extends State<ReleasePlanGateScreen> {
  bool get _isDark => widget.workbench.isDark;
  Color get _bgSurface => AppTheme.bgSurfaceFor(_isDark);
  Color get _cardBg => _isDark ? const Color(0xFF141822) : const Color(0xFFF8FAFC);
  Color get _borderColor => AppTheme.borderFor(_isDark);
  Color get _textPrimary => AppTheme.textPrimaryFor(_isDark);
  Color get _textSecondary => AppTheme.textSecondaryFor(_isDark);
  Color get _textMuted => AppTheme.textMutedFor(_isDark);

  @override
  Widget build(BuildContext context) {
    final bp = widget.workbench.releaseBlueprint;
    if (bp == null) {
      return Center(
        child: Text(
          'No active Release Blueprint.',
          style: GoogleFonts.inter(color: _textMuted),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildGateBanner(bp),
              const SizedBox(height: 16),
              if (bp.questions.isNotEmpty) ...[
                _buildReleaseQuestionsCard(bp),
                const SizedBox(height: 16),
              ],
              _buildBeatsBlueprintCard(bp),
              const SizedBox(height: 16),
              _buildOutOfScopeSummaryCard(bp),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  TextButton.icon(
                    onPressed: () => widget.workbench.setStage(WorkbenchStage.projectPitch),
                    icon: const Icon(Icons.arrow_back, size: 15),
                    label: const Text('Back to Project Pitch'),
                  ),
                  ElevatedButton.icon(
                    key: const ValueKey('approve_and_build_release_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.buttonBreakdown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: widget.workbench.isAgentBusy
                        ? null
                        : () => widget.workbench.approveAndExecuteReleasePlan(),
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: Text(
                      'Approve & Build Release (${bp.totalIncludedFeatures} Features · ${bp.totalIncludedHours}h) ✦',
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800),
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

  Widget _buildGateBanner(ReleaseBlueprint bp) {
    return Container(
      key: const ValueKey('release_plan_gate_banner'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.tierRelease.withValues(alpha: 0.5)),
      ),
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.tierRelease.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppTheme.tierRelease.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      'STAGE 2 · RELEASE PLAN GATE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.tierRelease,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      bp.releaseTitle,
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${bp.totalIncludedFeatures} Features · ${bp.totalIncludedHours}h Budget',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'GOAL: ${bp.goal}',
            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: _textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'DONE WHEN: ${bp.doneWhen}',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accentGreen),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseQuestionsCard(ReleaseBlueprint bp) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CLARIFYING RELEASE QUESTIONS',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.accentBlue,
            ),
          ),
          const SizedBox(height: 10),
          for (final q in bp.questions) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.question,
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: _textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final opt in q.options)
                        InkWell(
                          onTap: () => setState(() => q.selectedOption = opt),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: q.selectedOption == opt
                                  ? AppTheme.accentBlue.withValues(alpha: 0.16)
                                  : _cardBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: q.selectedOption == opt ? AppTheme.accentBlue : _borderColor,
                              ),
                            ),
                            child: Text(
                              opt,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: q.selectedOption == opt ? FontWeight.w700 : FontWeight.w500,
                                color: _textPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBeatsBlueprintCard(ReleaseBlueprint bp) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROPOSED CORE LOOP BEATS & FEATURES (UNCHECK TO DEFER TO OUT OF SCOPE)',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.tierEpic,
            ),
          ),
          const SizedBox(height: 12),
          for (final beat in bp.beats) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.tierEpic.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'CORE LOOP BEAT',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.tierEpic,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          beat.title,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${beat.totalIncludedHours}h',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    beat.goal,
                    style: GoogleFonts.inter(fontSize: 11.5, color: _textSecondary),
                  ),
                  const SizedBox(height: 10),
                  for (final feat in beat.features)
                    InkWell(
                      key: ValueKey('toggle_feat_${feat.id}'),
                      onTap: () => widget.workbench.toggleProposedFeatureScope(
                        beat.id,
                        feat.id,
                        !feat.included,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _bgSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: feat.included
                                ? AppTheme.tierFeature.withValues(alpha: 0.45)
                                : _borderColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              feat.included
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 16,
                              color: feat.included ? AppTheme.tierFeature : _textMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    feat.title,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: feat.included ? _textPrimary : _textMuted,
                                      decoration: feat.included
                                          ? TextDecoration.none
                                          : TextDecoration.lineThrough,
                                    ),
                                  ),
                                  Text(
                                    '${feat.checkpoints.length} Checkpoints · ${feat.tuningParams.length} Tune · ${feat.edgeCases.length} Edge',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: _textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              feat.included ? '${feat.estimatedHours}h' : 'DEFERRED',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: feat.included ? AppTheme.tierFeature : _textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOutOfScopeSummaryCard(ReleaseBlueprint bp) {
    final exclusions = bp.effectiveOutOfScope;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EFFECTIVE OUT OF SCOPE (${exclusions.length} DEFERRED ITEMS)',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final item in exclusions)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Text(
                    '⊘ $item',
                    style: GoogleFonts.inter(fontSize: 11, color: _textSecondary),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
