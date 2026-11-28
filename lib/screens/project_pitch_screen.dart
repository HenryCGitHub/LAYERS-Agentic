import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/agent_blueprints.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import 'stage1/stage1_idea_angles_card.dart';
import 'stage1/stage1_shared_widgets.dart';
import 'stage1/stage1_spec_document.dart';
import 'workbench/floating_ai_refine_dock.dart';
import 'workbench/plain_doc_widgets.dart';

/// Flat 700px single-column Stage 1 screen: handles both New Game Idea spark /
/// 3-Angles intake and the Project Brief spec document.
class ProjectPitchScreen extends StatefulWidget {
  final WorkbenchProvider workbench;
  final VoidCallback? onOpenAiSettings;
  final bool embeddedInShell;

  const ProjectPitchScreen({
    super.key,
    required this.workbench,
    this.onOpenAiSettings,
    this.embeddedInShell = false,
  });

  @override
  State<ProjectPitchScreen> createState() => _ProjectPitchScreenState();
}

class _ProjectPitchScreenState extends State<ProjectPitchScreen> {
  final TextEditingController _sparkController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _refineController = TextEditingController();

  bool _editingTitle = false;
  String? _lastSyncedTitle;
  String? _lastActiveProjectId;

  @override
  void initState() {
    super.initState();
    _lastActiveProjectId = widget.workbench.activeProjectId;
  }

  @override
  void dispose() {
    _sparkController.dispose();
    _titleController.dispose();
    _refineController.dispose();
    super.dispose();
  }

  void _resetInlineEditFlags() {
    _editingTitle = false;
  }

  void _clearInlineControllers() {
    _titleController.clear();
    _lastSyncedTitle = null;
    _refineController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final draft = wb.conceptDraft;
    if (_lastActiveProjectId != wb.activeProjectId ||
        (draft == null && _editingTitle)) {
      _lastActiveProjectId = wb.activeProjectId;
      _resetInlineEditFlags();
      _clearInlineControllers();
    }
    if (draft != null && _editingTitle && _lastSyncedTitle != draft.gameTitle) {
      _titleController.text = draft.gameTitle;
      _lastSyncedTitle = draft.gameTitle;
    }

    final isDark = wb.isDark;
    final bgBase = AppTheme.bgBaseFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);

    if (draft == null || !draft.hasSpec) {
      return Material(
        color: bgBase,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: _buildNewGameIntakeView(
                wb: wb,
                isDark: isDark,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                textMuted: textMuted,
                border: border,
                focal: focal,
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: bgBase,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border, width: 1)),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kPlainDocWideMaxWidth,
                ),
                child: _buildBriefHeader(
                  wb: wb,
                  spec: draft,
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  textMuted: textMuted,
                  border: border,
                  focal: focal,
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kPlainDocWideMaxWidth,
                  ),
                  child: Stage1SpecDocument(
                    workbench: wb,
                    spec: draft,
                    activeProjectId: wb.activeProjectId,
                  ),
                ),
              ),
            ),
          ),
          FloatingAiRefineDock(
            isDark: isDark,
            targetBadge: 'AI · Brief',
            hintText: 'Refine pitch, UE5 setup, pillars, cuts, or v0.1 features...',
            isBusy: wb.isAgentBusy,
            canUndo: wb.canUndoStage1,
            alwaysShowUndo: true,
            summaryText: draft.lastCoDesignNote,
            errorText: wb.stage1InlineError,
            customErrorBanner: wb.stage1InlineError == null
                ? null
                : _buildStage1InlineErrorBanner(
                    wb: wb,
                    isDark: isDark,
                    textPrimary: textPrimary,
                    retryKey: const ValueKey('stage1_refine_retry_btn'),
                    onRetry: () => _submitRefine(wb),
                  ),
            quickPrompts: const <String>[
              'Tighten v0.1 scope to 2 core Epics',
              'Add hitstop and camera shake feel trade-off',
              'Exclude multiplayer and save system from v0.1',
            ],
            externalController: _refineController,
            inputKey: const ValueKey('stage1_codesign_input'),
            applyBtnKey: const ValueKey('stage1_codesign_apply_btn'),
            undoBtnKey: const ValueKey('stage1_undo_btn'),
            ideasBtnKey: const ValueKey('stage1_ai_ideas_btn'),
            ideasStripKey: const ValueKey('stage1_ai_ideas_strip'),
            onApply: (instruction) async {
              FocusManager.instance.primaryFocus?.unfocus();
              final res = await wb.applyStage1CoDesignInstruction(instruction);
              if (res != null && mounted) {
                _refineController.clear();
              }
            },
            onUndo: wb.undoStage1Edit,
            onDismissError: wb.dismissStage1InlineError,
          ),
        ],
      ),
    );
  }

  Widget _buildBriefHeader({
    required WorkbenchProvider wb,
    required ProjectConceptBlueprint spec,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color border,
    required Color focal,
  }) {
    final launched = wb.projectReleases.isNotEmpty;
    final launchLabel = launched
        ? 'Sync Spec & Return to ${wb.activeReleaseVersionTag} →'
        : 'Approve & Launch v0.1 →';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'PROJECT BRIEF · ${spec.architectureMode.shortLabel.toUpperCase()}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.9,
                color: textMuted,
              ),
            ),
            const Spacer(),
            if (!_editingTitle)
              PlainTextLink(
                key: const ValueKey('stage1_edit_title_btn'),
                label: 'Rename',
                isDark: isDark,
                fontSize: 11.5,
                color: textMuted,
                onTap: wb.isAgentBusy
                    ? null
                    : () {
                        _titleController.text = spec.gameTitle;
                        _lastSyncedTitle = spec.gameTitle;
                        setState(() => _editingTitle = true);
                      },
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_editingTitle) ...[
          Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('stage1_title_input'),
                      controller: _titleController,
                      autofocus: true,
                      style: AppTheme.displayFont(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
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
                        wb.updateRootSpecSections(gameTitle: val);
                        setState(() => _editingTitle = false);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  PlainPrimaryButton(
                    key: const ValueKey('stage1_title_save_btn'),
                    label: 'Save',
                    isDark: isDark,
                    onPressed: () {
                      wb.updateRootSpecSections(
                        gameTitle: _titleController.text,
                      );
                      setState(() => _editingTitle = false);
                    },
                  ),
                  const SizedBox(width: 6),
                  PlainTextLink(
                    key: const ValueKey('stage1_title_cancel_btn'),
                    label: 'Cancel',
                    isDark: isDark,
                    color: textMuted,
                    onTap: () => setState(() => _editingTitle = false),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          PlainEditableLineField(
            fieldKey: const ValueKey('stage1_title_inline_field'),
            value: spec.normalizedTitle,
            isDark: isDark,
            style: AppTheme.displayFont(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
            onCommit: (val) => wb.updateRootSpecSections(gameTitle: val),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PlainPrimaryButton(
              key: const ValueKey('approve_launch_workbench_btn'),
              label: launchLabel,
              isDark: isDark,
              onPressed: wb.isAgentBusy
                  ? null
                  : () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      wb.approveRootSpecAndLaunchWorkbench(
                        openReleaseSpec: true,
                      );
                    },
            ),
            UnrealArchitectureToggle(
              mode: wb.unrealArchitectureMode,
              isDark: isDark,
              onChanged: wb.isAgentBusy ? null : wb.setArchitectureMode,
            ),
            PlainTextLink(
              key: const ValueKey('reset_spark_btn'),
              label: 'New Idea',
              isDark: isDark,
              color: textMuted,
              onTap: wb.isAgentBusy
                  ? null
                  : () {
                      setState(_resetInlineEditFlags);
                      _clearInlineControllers();
                      wb.resetStage1ToNewIdea();
                    },
            ),
          ],
        ),
        if (spec.sparkPrompt.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Spark: "${spec.sparkPrompt.trim()}"',
            style: TextStyle(fontSize: 12, color: textMuted),
          ),
        ],
      ],
    );
  }

  Widget _buildNewGameIntakeView({
    required WorkbenchProvider wb,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color border,
    required Color focal,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wb.canCancelNewGame) ...[
          Row(
            children: [
              PlainTextLink(
                key: const ValueKey('new_game_cancel_btn'),
                label:
                    '← Back to ${wb.previousProjectTitleBeforeNewGame ?? "Project"}',
                isDark: isDark,
                color: textSecondary,
                onTap: wb.isAgentBusy
                    ? null
                    : () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        wb.cancelNewGame();
                      },
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        Text(
          'NEW GAME · IDEA SPARK',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.9,
            color: textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'What are you building in UE5?',
          style: AppTheme.displayFont(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Describe the player verb, camera, and prototype goal. Pick an angle or generate the v0.1 Project Brief directly.',
          style: TextStyle(fontSize: 13.5, height: 1.45, color: textSecondary),
        ),
        const SizedBox(height: 22),
        TextField(
          key: const ValueKey('spark_prompt_input'),
          controller: _sparkController,
          maxLines: 3,
          minLines: 2,
          enabled: !wb.isAgentBusy,
          style: TextStyle(fontSize: 15, height: 1.45, color: textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText:
                'e.g., Third-person mech claw dash arena where breaking crab armor drops shield plates...',
            hintStyle: TextStyle(fontSize: 14, color: textMuted),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: focal, width: 1.5),
            ),
          ),
          onChanged: wb.previewArchitectureModeFromSparkText,
          onSubmitted: (val) async {
            if (!wb.isAgentBusy && val.trim().isNotEmpty) {
              await wb.exploreSparkAngles(val);
            }
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PlainPrimaryButton(
              key: const ValueKey('explore_angles_btn'),
              label: wb.isAgentBusy
                  ? (wb.agentProgressStep ?? 'Thinking...')
                  : (wb.pendingAngleDeck != null
                        ? 'Re-Explore Angles'
                        : 'Explore 3 Angles'),
              isDark: isDark,
              onPressed: wb.isAgentBusy
                  ? null
                  : () async {
                      final text = _sparkController.text.trim();
                      if (text.isEmpty) return;
                      await wb.exploreSparkAngles(text);
                    },
            ),
            PlainPrimaryButton(
              key: const ValueKey('draft_spark_btn'),
              label: 'Create Spec',
              outlined: true,
              isDark: isDark,
              onPressed: wb.isAgentBusy
                  ? null
                  : () async {
                      final text = _sparkController.text.trim();
                      if (text.isEmpty) return;
                      await wb.draftSpecDirectlyFromSpark(text);
                    },
            ),
            UnrealArchitectureToggle(
              mode: wb.unrealArchitectureMode,
              isDark: isDark,
              onChanged: wb.isAgentBusy ? null : wb.setArchitectureMode,
            ),
          ],
        ),
        if (!wb.hasLiveAiKey) ...[
          const SizedBox(height: 12),
          Row(
            key: const ValueKey('offline_template_mode_notice'),
            children: [
              Expanded(
                child: Text(
                  'Template Mode (signed out) — Sign in with Google or add a Gemini key for live AI specs.',
                  style: TextStyle(fontSize: 12, color: textMuted),
                ),
              ),
              const SizedBox(width: 8),
              PlainTextLink(
                key: const ValueKey('intake_template_signin_btn'),
                label: 'Sign in',
                isDark: isDark,
                fontSize: 12,
                color: AppTheme.accentGreenFor(isDark),
                onTap: wb.isAgentBusy ? null : wb.signInWithGoogle,
              ),
            ],
          ),
        ],
        if (wb.stage1InlineError != null) ...[
          const SizedBox(height: 14),
          _buildStage1InlineErrorBanner(
            wb: wb,
            isDark: isDark,
            textPrimary: textPrimary,
            retryKey: const ValueKey('stage1_intake_retry_btn'),
            onRetry: () => wb.retryLastStage1Intake(_sparkController.text),
          ),
        ],
        if (wb.pendingAngleDeck != null)
          Stage1IdeaAnglesCard(
            workbench: wb,
            deck: wb.pendingAngleDeck!,
            activeProjectId: wb.activeProjectId,
            isDark: isDark,
          ),
        const SizedBox(height: 22),
        Divider(height: 1, thickness: 1, color: border),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Starter Examples:',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: textMuted,
              ),
            ),
            for (final preset in UnrealSparkPresets.entries)
              PlainTextLink(
                key: ValueKey('preset_${preset.id}'),
                label: preset.label,
                isDark: isDark,
                color: focal,
                onTap: wb.isAgentBusy
                    ? null
                    : () {
                        setState(_resetInlineEditFlags);
                        _clearInlineControllers();
                        wb.loadPresetSpark(preset.id);
                      },
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStage1InlineErrorBanner({
    required WorkbenchProvider wb,
    required bool isDark,
    required Color textPrimary,
    required Key retryKey,
    required VoidCallback onRetry,
  }) {
    final red = AppTheme.accentRedFor(isDark);
    return Container(
      key: const ValueKey('stage1_inline_error_banner'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: red.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              wb.stage1InlineError ?? 'Request failed.',
              style: TextStyle(fontSize: 12.5, color: red),
            ),
          ),
          const SizedBox(width: 8),
          if (!wb.isUserLoggedIn) ...[
            PlainTextLink(
              key: const ValueKey('stage1_inline_signin_btn'),
              label: 'Sign in',
              isDark: isDark,
              color: AppTheme.accentGreenFor(isDark),
              onTap: wb.isAgentBusy ? null : wb.signInWithGoogle,
            ),
            const SizedBox(width: 8),
          ],
          PlainTextLink(
            key: retryKey,
            label: 'Retry',
            isDark: isDark,
            color: textPrimary,
            onTap: wb.isAgentBusy ? null : onRetry,
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: wb.dismissStage1InlineError,
            child: Icon(Icons.close_rounded, size: 14, color: red),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRefine(WorkbenchProvider wb) async {
    final text = _refineController.text.trim();
    if (text.isEmpty || wb.isAgentBusy) return;
    final res = await wb.applyStage1CoDesignInstruction(text);
    if (res != null && mounted) {
      _refineController.clear();
    }
  }
}
