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
  final TextEditingController _releaseChatController = TextEditingController();
  final Set<String> _expandedFeatureIds = {};
  final Map<String, TextEditingController> _newBeatFeatureControllers = {};
  bool _collapseQuestions = false;

  bool get _isDark => widget.workbench.isDark;
  Color get _bgBase => AppTheme.bgBaseFor(_isDark);
  Color get _bgSurface => AppTheme.bgSurfaceFor(_isDark);
  Color get _bgRecessed => AppTheme.bgSurfaceRecessedFor(_isDark);
  Color get _bgHover => AppTheme.bgSurfaceHoverFor(_isDark);
  Color get _borderSubtle => AppTheme.borderSubtleFor(_isDark);
  Color get _borderBright => AppTheme.borderBrightFor(_isDark);
  Color get _textPrimary => AppTheme.textPrimaryFor(_isDark);
  Color get _textSecondary => AppTheme.textSecondaryFor(_isDark);
  Color get _textMuted => AppTheme.textMutedFor(_isDark);
  Color get _focalAccent => AppTheme.focalAccentFor(_isDark);
  Color get _focalAccentFg => AppTheme.focalAccentFgFor(_isDark);
  Color get _accentEmerald => AppTheme.accentGreenFor(_isDark);
  Color get _accentCrimson => AppTheme.accentRedFor(_isDark);
  Color get _accentAmber => AppTheme.accentAmberFor(_isDark);

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
        color: _bgBase,
        child: Center(
          child: Text(
            'No active Release Blueprint.',
            style: GoogleFonts.inter(color: _textMuted),
          ),
        ),
      );
    }

    return Container(
      color: _bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildGateBanner(bp),
                      const SizedBox(height: 22),
                      if (bp.questions.isNotEmpty) ...[
                        _buildReleaseQuestionsSection(bp),
                        const SizedBox(height: 22),
                      ],
                      _buildBeatsBlueprintSection(bp),
                      const SizedBox(height: 22),
                      _buildOutOfScopeSummarySection(bp),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildStickyBottomDock(bp),
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
        backgroundColor: _focalAccent,
        foregroundColor: _focalAccentFg,
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

  Widget _buildGateBanner(ReleaseBlueprint bp) {
    final includedHours = bp.totalIncludedHours;
    final deferredHours = bp.totalDeferredHours;
    final totalCandidateHours = includedHours + deferredHours;
    final ratio = totalCandidateHours > 0
        ? (includedHours / totalCandidateHours).clamp(0.08, 1.0)
        : 1.0;

    return Container(
      key: const ValueKey('release_plan_gate_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderBright),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
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
                          letterSpacing: 0.6,
                          color: _accentAmber,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _borderSubtle),
                        ),
                        child: Text(
                          '${bp.beats.length} Beats · ${bp.totalIncludedFeatures} Included · ${bp.totalDeferredFeatures} Deferred',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    bp.releaseTitle,
                    style: AppTheme.displayFont(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Review the proposed Core Loop Beats & Playable Features below. Uncheck any feature to defer it to Out of Scope.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
              _buildPrimaryApproveButton(bp),
            ],
          ),
          const SizedBox(height: 14),
          // Live Visual Scope & Hour Budget Bar
          Container(
            key: const ValueKey('release_hour_budget_bar'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _bgRecessed,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderSubtle),
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
                        color: _textSecondary,
                      ),
                    ),
                    Text(
                      deferredHours > 0
                          ? '${includedHours}h Included · ${deferredHours}h Deferred (Saved)'
                          : '${includedHours}h Included · 0h Deferred',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _accentEmerald,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 6,
                    color: _bgSurface,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ratio,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_accentEmerald, _accentAmber],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // GOAL Callout Blockquote
          _buildCalloutBar(
            badgeLabel: 'GOAL',
            statement: bp.goal,
            accentColor: _focalAccent,
            highlightMetrics: false,
          ),
          const SizedBox(height: 8),
          // DONE WHEN Callout Blockquote with Metric Highlighting
          _buildCalloutBar(
            badgeLabel: 'DONE WHEN',
            statement: bp.doneWhen,
            accentColor: _accentEmerald,
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
        color: _bgRecessed,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderSubtle),
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
                            ? _accentEmerald.withValues(alpha: 0.12)
                            : _bgSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: highlightMetrics
                              ? _accentEmerald.withValues(alpha: 0.45)
                              : _borderBright,
                        ),
                      ),
                      child: Text(
                        badgeLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: highlightMetrics ? _accentEmerald : _textSecondary,
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
                                color: _textPrimary,
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
              color: _accentEmerald.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _accentEmerald.withValues(alpha: 0.42)),
            ),
            child: Text(
              metricText,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
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
          color: _textPrimary,
        ),
        children: spans,
      ),
    );
  }

  Widget _buildReleaseChatBar(ReleaseBlueprint bp) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: _bgRecessed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: _bgSurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _borderBright),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _accentAmber,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AGENT · ${widget.workbench.planningModel.toUpperCase()}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
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
                    color: _textPrimary,
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
                        color: msg.isUser ? _accentAmber : _accentEmerald,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    '${msg.isUser ? "You" : "Agent"}: ${msg.text}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: _textSecondary,
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
                    color: _bgSurface,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '[ASK AGENT]',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _textSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('release_plan_chat_input'),
                          controller: _releaseChatController,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Tell the Agent how to refine this Release Plan (e.g., "Add a wall-run feature to Beat 1", "Defer Beat 4")...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: _textMuted,
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
                  foregroundColor: _textPrimary,
                  backgroundColor: _bgSurface,
                  side: BorderSide(color: _borderBright),
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
          bottom: BorderSide(color: _borderSubtle),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                numLabel,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _textSecondary.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: _textPrimary,
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
                color: _textSecondary,
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
              bottom: BorderSide(color: _borderSubtle),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '01',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CLARIFYING RELEASE QUESTIONS',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${bp.questions.length} Playtest Priorities · Live-Syncs Blueprint',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
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
                        color: _bgSurface,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: _borderBright),
                      ),
                      child: Text(
                        _collapseQuestions
                            ? 'Edit Decisions ▾'
                            : 'Collapse Decisions ▴',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: _accentEmerald,
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
            color: _bgSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _borderSubtle),
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
                  color: _accentEmerald,
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
                          color: _accentEmerald.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _accentEmerald.withValues(alpha: 0.38),
                          ),
                        ),
                        child: Text(
                          'Q${qIdx + 1}: ${parsed.title} ✓',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
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
                color: _bgRecessed,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _borderSubtle),
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
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '✦ Live-syncs Done When',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: _accentEmerald,
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
      color: isSelected ? _bgHover : _bgSurface,
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
              color: isSelected ? _textPrimary : _borderSubtle,
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
                          color: isSelected ? _focalAccent : Colors.transparent,
                          border: Border.all(
                            color: isSelected ? _focalAccent : _textMuted,
                            width: 1.4,
                          ),
                        ),
                        child: isSelected
                            ? Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _focalAccentFg,
                                ),
                              )
                            : null,
                      ),
                      if (isFirst)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _accentEmerald.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: _accentEmerald.withValues(alpha: 0.42),
                            ),
                          ),
                          child: Text(
                            'RECOMMENDED',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: _accentEmerald,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _bgRecessed,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: _borderSubtle),
                          ),
                          child: Text(
                            'OPTION 0${optIdx + 1}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: _textSecondary,
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
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    parsed.description,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.5,
                      color: _textSecondary,
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
    final allFeatureIds = <String>[
      for (final b in bp.beats)
        for (final f in b.features) f.id,
    ];
    final allSpecsExpanded = allFeatureIds.isNotEmpty &&
        allFeatureIds.every((id) => _expandedFeatureIds.contains(id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          numLabel: '02',
          title: 'Core Loop Beats & Playable Features',
          trailingMeta: 'Uncheck any feature to defer to Out of Scope',
        ),
        const SizedBox(height: 10),
        // Beat Jump-Bar + 1-Click Expand/Collapse All Specs
        Container(
          key: const ValueKey('stage2_beat_jump_bar'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _bgSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _borderSubtle),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (int bIdx = 0; bIdx < bp.beats.length; bIdx++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _bgRecessed,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _borderSubtle),
                      ),
                      child: Text(
                        'B${(bIdx + 1).toString().padLeft(2, '0')} · ${bp.beats[bIdx].title} (${bp.beats[bIdx].totalIncludedHours}h)',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: _textSecondary,
                        ),
                      ),
                    ),
                ],
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
                    color: _bgRecessed,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _borderBright),
                  ),
                  child: Text(
                    allSpecsExpanded ? 'Collapse All Specs ▴' : 'Expand All Specs ▾',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: _accentAmber,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) ...[
          _buildBeatCard(bp, bp.beats[bIdx], bIdx),
          if (bIdx < bp.beats.length - 1)
            Row(
              children: [
                const SizedBox(width: 47),
                Container(
                  width: 2,
                  height: 10,
                  color: _accentEmerald.withValues(alpha: 0.45),
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
        color: _bgRecessed,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderSubtle),
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
                    color: allIncluded ? _accentEmerald : _textMuted,
                  ),
                ),
              ),
              Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accentEmerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _accentEmerald.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  beatCode,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _accentEmerald,
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
                              color: _textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _bgSurface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _borderSubtle),
                          ),
                          child: Text(
                            '${beat.includedFeatures.length} Features · ${beat.totalIncludedHours}h',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _textSecondary,
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
                        color: _textSecondary,
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
              final useTwoCol = constraints.maxWidth >= 680 &&
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
              color: _bgSurface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: _borderSubtle),
            ),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 15, color: _textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: ValueKey('add_beat_feature_input_${beat.id}'),
                    controller: beatCtrl,
                    onSubmitted: (_) => submitNewBeatFeature(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 7),
                      hintText:
                          'Add playable feature to $beatCode (e.g., Slide Boost & Cancel)...',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: _textMuted,
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
                        color: _accentAmber,
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

    return Container(
      decoration: BoxDecoration(
        color: isIncluded ? _bgSurface : _bgRecessed.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isIncluded ? _borderBright : _borderSubtle,
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
                      color: isIncluded ? _accentEmerald : _textMuted,
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
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              feat.title,
                              style: AppTheme.displayFont(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: isIncluded ? _textPrimary : _textMuted,
                              ).copyWith(
                                decoration: isIncluded
                                    ? TextDecoration.none
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            _buildLifecycleBadge(feat, bp.releaseVersionTag),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          feat.lifecycle == FeatureLifecycleStatus.stable
                              ? 'Verified in ${feat.originVersion} · Untouched in ${bp.releaseVersionTag} (0h new work)'
                              : feat.goal,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.45,
                            color: isIncluded ? _textSecondary : _textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (feat.checkpoints.isNotEmpty) ...[
                  InkWell(
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
                            ? _accentAmber.withValues(alpha: 0.14)
                            : _bgRecessed,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isExpanded
                              ? _accentAmber.withValues(alpha: 0.45)
                              : _borderSubtle,
                        ),
                      ),
                      child: Text(
                        '${feat.checkpoints.length} Checkpoints · ${feat.tuningParams.length} Tune ${isExpanded ? "▴" : "▾"}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: isExpanded ? _accentAmber : _textSecondary,
                        ),
                      ),
                    ),
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
                      color: _bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _borderSubtle),
                    ),
                    child: Text(
                      'Edit ✎',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _textSecondary,
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
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: !isIncluded
                          ? _accentCrimson.withValues(alpha: 0.12)
                          : (feat.lifecycle == FeatureLifecycleStatus.stable
                              ? _accentEmerald.withValues(alpha: 0.12)
                              : _bgRecessed),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: !isIncluded
                            ? _accentCrimson.withValues(alpha: 0.42)
                            : (feat.lifecycle == FeatureLifecycleStatus.stable
                                ? _accentEmerald.withValues(alpha: 0.42)
                                : _borderSubtle),
                      ),
                    ),
                    child: Text(
                      !isIncluded
                          ? (feat.lifecycle == FeatureLifecycleStatus.superseded
                              ? 'ARCHIVED'
                              : 'DEFERRED')
                          : (feat.lifecycle == FeatureLifecycleStatus.stable
                              ? 'STABLE · 0h'
                              : '${feat.activeDeltaHours}h'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: !isIncluded
                            ? _accentCrimson
                            : (feat.lifecycle == FeatureLifecycleStatus.stable
                                ? _accentEmerald
                                : _textPrimary),
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
                color: _bgRecessed,
                border: Border(top: BorderSide(color: _borderSubtle)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _accentEmerald.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: _accentEmerald.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'DONE WHEN',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: _accentEmerald,
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
                            color: _accentEmerald,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (int cIdx = 0; cIdx < feat.checkpoints.length; cIdx++)
                        Container(
                          width: 320,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _bgSurface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: _borderSubtle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'CHECKPOINT ${cIdx + 1} · ${feat.checkpoints[cIdx].title}',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: _textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    'PLAYTEST',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: _accentAmber,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                feat.checkpoints[cIdx].playtestCriteria,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: _textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
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
                              color: _accentAmber.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: _accentAmber.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              '⚙ $t',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                          ),
                        for (final e in feat.edgeCases)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _accentCrimson.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: _accentCrimson.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              '⚠ $e',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: _textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
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
    Color color;
    switch (feat.lifecycle) {
      case FeatureLifecycleStatus.stable:
        label = 'STABLE · ${feat.originVersion} ✓';
        color = _accentEmerald;
        break;
      case FeatureLifecycleStatus.upgrade:
        label = '${feat.originVersion} → $releaseVersionTag';
        color = _accentAmber;
        break;
      case FeatureLifecycleStatus.superseded:
        label = 'SUPERSEDED (${feat.originVersion})';
        color = _textMuted;
        break;
      case FeatureLifecycleStatus.newFeature:
        label = 'NEW $releaseVersionTag';
        color = _accentAmber;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.42), width: 0.8),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildOutOfScopeSummarySection(ReleaseBlueprint bp) {
    // Collect explicit exclusions + deferred features with their beatId/featId for 1-click Restore
    final items = <({String text, String? beatId, String? featId})>[
      for (final ex in bp.explicitExclusions)
        (text: ex, beatId: null, featId: null),
    ];
    for (final beat in bp.beats) {
      for (final deferred in beat.deferredFeatures) {
        final label = '${deferred.title} (deferred from ${beat.title})';
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
          color: _bgRecessed.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDeferredFeat
                ? _accentAmber.withValues(alpha: 0.38)
                : _borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _accentCrimson.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: _accentCrimson.withValues(alpha: 0.42),
                ),
              ),
              child: Text(
                isDeferredFeat ? 'DEFERRED' : 'CUT',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _accentCrimson,
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
                      ? _textPrimary
                      : _textSecondary.withValues(alpha: 0.85),
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
                    color: _bgSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _borderBright),
                  ),
                  child: Text(
                    '+ Restore',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: _accentEmerald,
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
          title: 'Out of Scope (Deferred & Excluded)',
          trailingMeta: '${items.length} Items Cut',
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
        color: _bgSurface,
        border: Border(top: BorderSide(color: _borderBright)),
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
                          foregroundColor: _textPrimary,
                          backgroundColor: _bgRecessed,
                          side: BorderSide(color: _borderSubtle),
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
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: _borderSubtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 13,
                              color: _accentEmerald,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$includedBeatsCount Beats · ${bp.totalIncludedFeatures} Features · ~${bp.totalIncludedHours}h selected',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: _textSecondary,
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
    final cpLines = feat.checkpoints
        .map((c) => '${c.title} | ${c.playtestCriteria}')
        .join('\n');
    final cpCtrl = TextEditingController(text: cpLines);
    final tuningCtrl = TextEditingController(
      text: feat.tuningParams.join(', '),
    );

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: _borderBright),
        ),
        title: Text(
          'Edit Proposed Feature',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
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
                  label: 'CHECKPOINTS (1 PER LINE: Title | Playtest Criteria)',
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
                color: _accentCrimson,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: _textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('save_stage2_feat_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentEmerald,
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

    final rawCpLines = cpCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final updatedCheckpoints = <ProposedCheckpointBlueprint>[];
    for (int i = 0; i < rawCpLines.length; i++) {
      final parts = rawCpLines[i].split('|');
      final cpTitle = parts.first.trim();
      final cpPlaytest = parts.length > 1
          ? parts.sublist(1).join('|').trim()
          : (i < feat.checkpoints.length
              ? feat.checkpoints[i].playtestCriteria
              : feat.doneWhen);
      final existingCp =
          i < feat.checkpoints.length ? feat.checkpoints[i] : null;
      updatedCheckpoints.add(
        ProposedCheckpointBlueprint(
          title: cpTitle,
          playtestCriteria: cpPlaytest,
          tasks: existingCp?.tasks ??
              const [
                'Wire core input & movement state (2h)',
                'Connect feedback & boundary guard (1h)',
              ],
          coveredScope: existingCp?.coveredScope ?? feat.inScope,
          tuningParams: parsedTuning,
          edgeCases: existingCp?.edgeCases ?? feat.edgeCases,
          releaseVersion: existingCp?.releaseVersion ?? feat.originVersion,
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
            color: _textMuted,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: fieldKey,
          controller: controller,
          maxLines: maxLines,
          style: mono
              ? GoogleFonts.jetBrainsMono(fontSize: 12, color: _textPrimary)
              : GoogleFonts.inter(fontSize: 12.5, color: _textPrimary),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 9,
            ),
            filled: true,
            fillColor: _bgRecessed,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: _borderSubtle),
            ),
          ),
        ),
      ],
    );
  }
}
