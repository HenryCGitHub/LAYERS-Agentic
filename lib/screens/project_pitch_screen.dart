import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';

/// Stage 1 Screen: Initial Project Concept Creation
/// 1A. The Spark (1-line game idea input)
/// 1B. Antigravity Concept Interview (2-3 multiple-choice questions + write-in)
/// 1C. Project Concept Blueprint & Release Train -> [Approve Concept & Plan v0.1 Release ✦]
class ProjectPitchScreen extends StatefulWidget {
  final WorkbenchProvider workbench;

  const ProjectPitchScreen({
    super.key,
    required this.workbench,
  });

  @override
  State<ProjectPitchScreen> createState() => _ProjectPitchScreenState();
}

class _ProjectPitchScreenState extends State<ProjectPitchScreen> {
  final TextEditingController _sparkController = TextEditingController(
    text: 'High-speed grappling hook parkour roguelite',
  );

  bool get _isDark => widget.workbench.isDark;
  Color get _bgSurface => AppTheme.bgSurfaceFor(_isDark);
  Color get _cardBg => _isDark ? const Color(0xFF141822) : const Color(0xFFF8FAFC);
  Color get _borderColor => AppTheme.borderFor(_isDark);
  Color get _textPrimary => AppTheme.textPrimaryFor(_isDark);
  Color get _textSecondary => AppTheme.textSecondaryFor(_isDark);
  Color get _textMuted => AppTheme.textMutedFor(_isDark);

  @override
  void dispose() {
    _sparkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.workbench.conceptDraft;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSparkCard(draft),
              if (draft != null) ...[
                const SizedBox(height: 20),
                _buildConceptInterviewCard(draft),
              ],
              if (draft != null && draft.isInterviewComplete) ...[
                const SizedBox(height: 20),
                _buildProjectBlueprintCard(draft),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSparkCard(ProjectConceptBlueprint? draft) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.tierProject.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.tierProject.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'STEP 1A · THE SPARK',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.tierProject,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'What kind of game are we building?',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('spark_input_field'),
                  controller: _sparkController,
                  style: GoogleFonts.inter(fontSize: 14, color: _textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g., Fast-paced grappling hook roguelite...',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: _textMuted),
                    filled: true,
                    fillColor: _cardBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                  ),
                  onSubmitted: (_) => widget.workbench.startConceptInterview(_sparkController.text),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                key: const ValueKey('start_concept_interview_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.tierProject,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: widget.workbench.isAgentBusy
                    ? null
                    : () => widget.workbench.startConceptInterview(_sparkController.text),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: Text(
                  draft == null ? 'Start Concept Interview' : 'Re-Run Interview',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConceptInterviewCard(ProjectConceptBlueprint draft) {
    return Container(
      key: const ValueKey('concept_interview_card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'STEP 1B · CONCEPT INTERVIEW',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accentBlue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Align on Core Feel & First Milestone (${draft.title})',
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
          for (int i = 0; i < draft.questions.length; i++) ...[
            _buildQuestionBlock(draft.questions[i], i),
            if (i < draft.questions.length - 1) const SizedBox(height: 14),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.workbench.isAgentBusy &&
                  widget.workbench.agentProgressStep != null)
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accentBlue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.workbench.agentProgressStep!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              ElevatedButton.icon(
                key: const ValueKey('synthesize_concept_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: widget.workbench.isAgentBusy
                    ? null
                    : () => widget.workbench.completeConceptInterview(),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: Text(
                  draft.isInterviewComplete
                      ? 'Update Project Blueprint'
                      : 'Generate Project Blueprint ✦',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionBlock(AgentQuestion q, int index) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}. ${q.question}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in q.options)
                InkWell(
                  onTap: () {
                    setState(() {
                      q.selectedOption = opt;
                      q.customWriteIn = '';
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: q.selectedOption == opt && q.customWriteIn.isEmpty
                          ? AppTheme.accentBlue.withValues(alpha: 0.16)
                          : _bgSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: q.selectedOption == opt && q.customWriteIn.isEmpty
                            ? AppTheme.accentBlue
                            : _borderColor,
                        width: q.selectedOption == opt && q.customWriteIn.isEmpty ? 1.2 : 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          q.selectedOption == opt && q.customWriteIn.isEmpty
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 14,
                          color: q.selectedOption == opt && q.customWriteIn.isEmpty
                              ? AppTheme.accentBlue
                              : _textMuted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            opt,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: q.selectedOption == opt && q.customWriteIn.isEmpty
                                  ? FontWeight.w700
                                  : FontWeight.w500,
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
          const SizedBox(height: 8),
          TextField(
            style: GoogleFonts.inter(fontSize: 12, color: _textPrimary),
            decoration: InputDecoration(
              hintText: 'Or type a custom direction for this question...',
              hintStyle: GoogleFonts.inter(fontSize: 11.5, color: _textMuted),
              isDense: true,
              filled: true,
              fillColor: _bgSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: _borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: q.customWriteIn.trim().isNotEmpty
                      ? AppTheme.accentBlue
                      : _borderColor,
                ),
              ),
            ),
            onChanged: (val) {
              setState(() {
                q.customWriteIn = val;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProjectBlueprintCard(ProjectConceptBlueprint draft) {
    return Container(
      key: const ValueKey('project_blueprint_card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'STEP 1C · PROJECT CONCEPT & RELEASE TRAIN',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accentGreen,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  draft.title,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildTagRow('GOAL', draft.goal, AppTheme.tierProject),
          const SizedBox(height: 10),
          Text(
            'IN SCOPE (CORE 30-SECOND LOOP)',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.accentBlue,
            ),
          ),
          const SizedBox(height: 6),
          for (final beat in draft.coreLoopBeats)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $beat',
                style: GoogleFonts.inter(fontSize: 12.5, color: _textPrimary),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'OUT OF SCOPE (HARD EXCLUSIONS)',
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
              for (final ex in draft.exclusions)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Text(
                    '⊘ $ex',
                    style: GoogleFonts.inter(fontSize: 11, color: _textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTagRow('DONE WHEN', draft.doneWhen, AppTheme.accentGreen),
          const Divider(height: 24),
          Text(
            'RELEASE TRAIN (ONE RELEASE AT A TIME)',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.tierRelease,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (int i = 0; i < draft.releaseTrainTitles.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: i == 0
                        ? AppTheme.tierRelease.withValues(alpha: 0.14)
                        : _cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: i == 0 ? AppTheme.tierRelease : _borderColor,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        i == 0 ? Icons.play_circle_fill : Icons.lock_outline,
                        size: 14,
                        color: i == 0 ? AppTheme.tierRelease : _textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        draft.releaseTrainTitles[i],
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                          color: i == 0 ? _textPrimary : _textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              key: const ValueKey('approve_concept_plan_release_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: widget.workbench.isAgentBusy
                  ? null
                  : () => widget.workbench.openReleasePlanGate(),
              icon: const Icon(Icons.rocket_launch_rounded, size: 16),
              label: Text(
                'Approve Concept & Plan v0.1 Release ✦',
                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagRow(String label, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
