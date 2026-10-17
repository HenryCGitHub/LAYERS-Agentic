import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';

/// Stage 1 Screen: Turn-by-Turn Antigravity Co-Design Chat + Live Project Blueprint
/// - Left Pane: Conversational turn-by-turn chat where you and Antigravity take turns
///   discussing the game concept, clicking quick-reply chips, or typing any adjustment.
/// - Right Pane: Live-updating Project Concept Blueprint & Release Train artifact
///   with a single confirmation gate CTA: `[Approve Concept & Plan v0.1 Release ✦]`.
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
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

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
    _chatInputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _submitChatTurn([String? presetText]) async {
    final msg = (presetText ?? _chatInputController.text).trim();
    if (msg.isEmpty || widget.workbench.isAgentBusy) return;
    if (presetText == null) {
      _chatInputController.clear();
    }
    await widget.workbench.sendConceptChatMessage(msg);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.workbench.conceptDraft;

    // Before the first Spark is submitted, show the centered Spark launcher + starter ideas
    if (draft == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _buildInitialSparkLauncher(),
          ),
        ),
      );
    }

    // Once the conversation starts: 50/50 Turn-by-Turn Chat (Left) + Live Blueprint Artifact (Right)
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        if (!isWide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 460,
                  child: _buildCoDesignChatPane(draft),
                ),
                const SizedBox(height: 16),
                _buildProjectBlueprintCard(draft),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: _buildCoDesignChatPane(draft),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  child: _buildProjectBlueprintCard(draft),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInitialSparkLauncher() {
    const sampleSparks = [
      'High-speed grappling hook parkour roguelite',
      'Cozy 2D submarine salvage & deep-sea creature photography',
      'Top-down cyberpunk katana deflection boss-rush arena',
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  'Pitch your game idea to start the Co-Design Chat',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Type a 1-sentence game idea below. We will take turns chatting on the left while your live Project Concept Blueprint & Release Train update in real time on the right.',
            style: GoogleFonts.inter(fontSize: 13, color: _textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('spark_input_field'),
                  controller: _sparkController,
                  style: GoogleFonts.inter(fontSize: 14, color: _textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g., High-speed grappling hook parkour roguelite...',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: _textMuted),
                    filled: true,
                    fillColor: _cardBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                  ),
                  onSubmitted: (_) =>
                      widget.workbench.startConceptInterview(_sparkController.text),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                key: const ValueKey('start_concept_interview_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.tierProject,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: widget.workbench.isAgentBusy
                    ? null
                    : () => widget.workbench.startConceptInterview(_sparkController.text),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: Text(
                  widget.workbench.isAgentBusy
                      ? 'Starting Chat...'
                      : 'Start Concept Interview',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in sampleSparks)
                InkWell(
                  onTap: () {
                    _sparkController.text = s;
                    widget.workbench.startConceptInterview(s);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _borderColor),
                    ),
                    child: Text(
                      '✦ $s',
                      style: GoogleFonts.inter(fontSize: 11.5, color: _textSecondary),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoDesignChatPane(ProjectConceptBlueprint draft) {
    final messages = draft.chatHistory;
    final lastMsg = messages.isNotEmpty ? messages.last : null;

    return Container(
      key: const ValueKey('concept_interview_card'),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chat Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'CO-DESIGN CHAT',
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
                    'Turn-by-Turn Concept & Scope Refinement',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.workbench.isAgentBusy
                      ? null
                      : () => widget.workbench.startConceptInterview(draft.sparkIdea),
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: Text(
                    'Reset',
                    style: GoogleFonts.inter(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Message History
          Expanded(
            child: ListView.separated(
              controller: _chatScrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, idx) {
                final m = messages[idx];
                return _buildChatBubble(m);
              },
            ),
          ),

          // Quick-Reply Chips from the latest Assistant turn
          if (lastMsg != null &&
              !lastMsg.isUser &&
              lastMsg.quickReplies.isNotEmpty &&
              !widget.workbench.isAgentBusy)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              decoration: BoxDecoration(
                color: _cardBg.withValues(alpha: 0.6),
                border: Border(top: BorderSide(color: _borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QUICK REPLIES (CLICK OR TYPE ANY ADJUSTMENT BELOW)',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: _textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (int i = 0; i < lastMsg.quickReplies.length; i++)
                        InkWell(
                          key: i == 0
                              ? const ValueKey('synthesize_concept_btn')
                              : ValueKey('quick_reply_$i'),
                          onTap: () => _submitChatTurn(lastMsg.quickReplies[i]),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.accentBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.accentBlue.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              lastMsg.quickReplies[i],
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
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

          // Agent Busy Progress Bar
          if (widget.workbench.isAgentBusy &&
              widget.workbench.agentProgressStep != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: AppTheme.accentBlue.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.workbench.agentProgressStep!,
                      style: GoogleFonts.inter(fontSize: 11.5, color: _textSecondary),
                    ),
                  ),
                ],
              ),
            ),

          // Bottom Turn-by-Turn Chat Input Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border(top: BorderSide(color: _borderColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('concept_chat_input_field'),
                    controller: _chatInputController,
                    style: GoogleFonts.inter(fontSize: 13, color: _textPrimary),
                    decoration: InputDecoration(
                      hintText:
                          'Tell Antigravity what to change (e.g., "Make it 2D", "Cut time trials", "Add a boss beat")...',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: _textMuted),
                      isDense: true,
                      filled: true,
                      fillColor: _bgSurface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _borderColor),
                      ),
                    ),
                    onSubmitted: (_) => _submitChatTurn(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  key: const ValueKey('send_concept_chat_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: widget.workbench.isAgentBusy ? null : () => _submitChatTurn(),
                  icon: const Icon(Icons.send_rounded, size: 15),
                  label: Text(
                    'Send',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(AgentChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUser
                ? AppTheme.tierProject.withValues(alpha: 0.16)
                : _cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isUser
                  ? AppTheme.tierProject.withValues(alpha: 0.45)
                  : _borderColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUser ? Icons.person_outline : Icons.auto_awesome,
                        size: 13,
                        color: isUser ? AppTheme.tierProject : AppTheme.accentBlue,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isUser
                            ? 'YOU'
                            : 'ANTIGRAVITY${msg.modelUsed != null ? " · ${msg.modelUsed!.replaceAll("gemini-", "")}" : ""}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isUser ? AppTheme.tierProject : AppTheme.accentBlue,
                        ),
                      ),
                    ],
                  ),
                  if (msg.updatedFields.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '↻ ${msg.updatedFields.join(", ")}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentGreen,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                msg.text,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.4,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ),
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
                  'LIVE ARTIFACT · PROJECT CONCEPT',
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
          const SizedBox(height: 12),
          Text(
            'IN SCOPE (CORE 30-SECOND LOOP)',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.accentBlue,
            ),
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < draft.coreLoopBeats.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '• ${draft.coreLoopBeats[i]}',
                      style: GoogleFonts.inter(fontSize: 12.5, color: _textPrimary),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      widget.workbench.updateConceptDraft((d) {
                        final removed = d.coreLoopBeats.removeAt(i);
                        d.exclusions.add(removed);
                        d.lastUpdatedFields = const ['Core Loop', 'Exclusions'];
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.close_rounded, size: 14, color: _textMuted),
                    ),
                  ),
                ],
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
              for (int i = 0; i < draft.exclusions.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '⊘ ${draft.exclusions[i]}',
                          style: GoogleFonts.inter(fontSize: 11, color: _textSecondary),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          widget.workbench.updateConceptDraft((d) {
                            d.exclusions.removeAt(i);
                          });
                        },
                        child: Icon(Icons.close, size: 12, color: _textMuted),
                      ),
                    ],
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
                      Flexible(
                        child: Text(
                          draft.releaseTrainTitles[i],
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                            color: i == 0 ? _textPrimary : _textMuted,
                          ),
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
