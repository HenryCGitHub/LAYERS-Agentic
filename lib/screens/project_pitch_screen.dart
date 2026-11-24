import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../agents/project_concept_agent.dart';
import '../models/agent_blueprints.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import 'stage1/stage1_shared_widgets.dart';
import 'stage1/stage1_spec_document.dart';
import 'workbench/floating_ai_refine_dock.dart';


/// Stage 1: `1. Project Spec` (`PROJECT_SPEC.md` -> `ROOT_UNREAL_CONTEXT`).
/// Single-space canvas with Idea Intake + vague-spark forks, scoped patch Refine + Undo,
/// changed-section badges, `§05` Scope & First Playtest preview, and lean direct inline edits.
class ProjectPitchScreen extends StatefulWidget {
  final WorkbenchProvider workbench;
  final VoidCallback? onOpenAiSettings;

  const ProjectPitchScreen({
    super.key,
    required this.workbench,
    this.onOpenAiSettings,
  });

  @override
  State<ProjectPitchScreen> createState() => _ProjectPitchScreenState();
}

class _ProjectPitchScreenState extends State<ProjectPitchScreen> {
  final TextEditingController _sparkController = TextEditingController();
  final TextEditingController _coDesignController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  bool _editingTitle = false;
  String? _lastActiveProjectId;


  void _resetInlineEditFlags() {
    _editingTitle = false;
  }

  void _clearInlineControllers({bool includeSpark = false}) {
    _titleController.clear();
    _coDesignController.clear();
    if (includeSpark) {
      _sparkController.clear();
    }
  }

  @override
  void dispose() {
    _sparkController.dispose();
    _coDesignController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final draft = wb.conceptDraft;
    final hasSpec = draft != null && draft.hasSpec;
    if (_lastActiveProjectId != wb.activeProjectId ||
        (!hasSpec && _editingTitle)) {
      final projectChanged = _lastActiveProjectId != null &&
          _lastActiveProjectId != wb.activeProjectId;
      _lastActiveProjectId = wb.activeProjectId;
      _resetInlineEditFlags();
      _clearInlineControllers(
        includeSpark: projectChanged &&
            !hasSpec &&
            (draft == null || draft.sparkPrompt.isEmpty),
      );
    }
    final isDark = wb.isDark;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);

    return Container(
      color: AppTheme.bgBaseFor(isDark),
      child: Column(
        children: [
          if (hasSpec)
            _buildTopEditorialBar(
              wb: wb,
              spec: draft,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              border: border,
              green: green,
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!hasSpec)
                        _buildIdeaIntakeHeaderCard(
                          context: context,
                          wb: wb,
                          isDark: isDark,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          textMuted: textMuted,
                          cyan: cyan,
                        )
                      else
                        _buildSparkContextCaption(
                          spec: draft,
                          isDark: isDark,
                          textMuted: textMuted,
                          border: border,
                        ),
                      const SizedBox(height: 16),
                      if (!hasSpec)
                        Stage1EmptyBlueprintOutline(isDark: isDark)
                      else
                        Stage1SpecDocument(
                          workbench: wb,
                          spec: draft,
                          activeProjectId: wb.activeProjectId,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasSpec)
            FloatingAiRefineDock(
              isDark: isDark,
              targetBadge: 'AI · Spec',
              hintText:
                  'Refine spec: "Switch to third-person", "Make movement heavier", or "Add parry shield"...',
              isBusy: wb.isAgentBusy,
              canUndo: wb.canUndoStage1,
              alwaysShowUndo: true,
              externalController: _coDesignController,
              summaryText: draft.lastCoDesignNote.isEmpty
                  ? null
                  : 'Updated: ${draft.lastCoDesignNote}',
              errorText: wb.stage1InlineError,
              customErrorBanner: wb.stage1InlineError == null
                  ? null
                  : _buildStage1InlineErrorBanner(
                      wb: wb,
                      isDark: isDark,
                      textPrimary: textPrimary,
                      retryKey: const ValueKey('stage1_refine_retry_btn'),
                      onRetry: () => _submitCoDesign(wb),
                    ),
              quickPrompts: [
                for (final chip in ProjectConceptAgent.suggestQuickRefines(draft))
                  chip.instruction,
              ],
              inputKey: const ValueKey('stage1_codesign_input'),
              applyBtnKey: const ValueKey('stage1_codesign_apply_btn'),
              undoBtnKey: const ValueKey('stage1_undo_btn'),
              ideasBtnKey: const ValueKey('stage1_ai_ideas_btn'),
              ideasStripKey: const ValueKey('stage1_ai_ideas_strip'),
              onApply: (_) => _submitCoDesign(wb),
              onUndo: () {
                setState(_resetInlineEditFlags);
                _clearInlineControllers();
                wb.undoStage1Edit();
              },
              onDismissError: wb.dismissStage1InlineError,
            ),
        ],
      ),
    );
  }

  Widget _buildTopEditorialBar({
    required WorkbenchProvider wb,
    required ProjectConceptBlueprint spec,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
    required Color green,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgPanelFor(isDark),
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    'PROJECT_SPEC.md',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: textSecondary,
                    ),
                  ),
                ),
                if (_editingTitle)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 240,
                        child: TextField(
                          key: const ValueKey('stage1_title_input'),
                          controller: _titleController,
                          style: AppTheme.displayFont(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          onSubmitted: (val) {
                            wb.updateRootSpecSections(gameTitle: val);
                            setState(() => _editingTitle = false);
                          },
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('stage1_title_save_btn'),
                        tooltip: 'Save title',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.check_rounded, size: 17, color: green),
                        onPressed: () {
                          wb.updateRootSpecSections(
                            gameTitle: _titleController.text,
                          );
                          setState(() => _editingTitle = false);
                        },
                      ),
                      IconButton(
                        key: const ValueKey('stage1_title_cancel_btn'),
                        tooltip: 'Cancel title edit',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () => setState(() => _editingTitle = false),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          spec.normalizedTitle,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.displayFont(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('stage1_edit_title_btn'),
                        tooltip: 'Rename project',
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.only(left: 4),
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: textSecondary,
                        ),
                        onPressed: wb.isAgentBusy
                            ? null
                            : () {
                                _titleController.text = spec.normalizedTitle;
                                setState(() => _editingTitle = true);
                              },
                      ),
                    ],
                  ),
                TextButton.icon(
                  key: const ValueKey('reset_spark_btn'),
                  onPressed: wb.isAgentBusy
                      ? null
                      : () {
                          _sparkController.clear();
                          _coDesignController.clear();
                          setState(_resetInlineEditFlags);
                          wb.resetStage1ToNewIdea();
                        },
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: const Text('New Idea', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                UnrealArchitectureToggle(
                  mode: wb.unrealArchitectureMode,
                  isDark: isDark,
                  onChanged: wb.isAgentBusy ? null : wb.setArchitectureMode,
                ),
                ElevatedButton.icon(
                  key: const ValueKey('approve_launch_workbench_btn'),
                  onPressed: wb.isAgentBusy
                      ? null
                      : () {
                          wb.approveRootSpecAndLaunchWorkbench();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    () {
                      if (wb.projectReleases.isNotEmpty) {
                        return 'Sync Spec & Return to ${wb.activeReleaseVersionTag} →';
                      }
                      final sliceCount = spec.initialEpics.fold<int>(
                        0,
                        (sum, e) => sum + e.featuresForRelease('v0.1').length,
                      );
                      return 'Approve & Launch v0.1 (${spec.initialEpics.length} Epics · $sliceCount Features) →';
                    }(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdeaIntakeHeaderCard({
    required BuildContext context,
    required WorkbenchProvider wb,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color cyan,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cyan.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(color: cyan.withValues(alpha: 0.35)),
          ),
          child: Text(
            'STAGE 1 · PROJECT SPEC',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cyan,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Describe the game you want to build.',
          style: AppTheme.displayFont(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Turn a one-sentence idea into a playable v0.1 Unreal Engine 5 spec — camera, Enhanced Input, tuning, and first Epics.',
          style: TextStyle(
            fontSize: 14,
            color: textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.bgSurfaceRaisedFor(isDark),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.borderBrightFor(isDark)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('spark_prompt_input'),
                controller: _sparkController,
                minLines: 2,
                maxLines: 4,
                style: TextStyle(fontSize: 15, color: textPrimary),
                decoration: InputDecoration(
                  hintText:
                      'e.g. Top-down mech arena brawler where a forward claw dash shatters enemy shell armor...',
                  hintStyle: TextStyle(color: textMuted, fontSize: 14),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: wb.previewArchitectureModeFromSparkText,
                onSubmitted: (val) async {
                  if (!wb.isAgentBusy && val.trim().isNotEmpty) {
                    await wb.handleStage1SparkSubmit(val);
                  }
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  UnrealArchitectureToggle(
                    mode: wb.unrealArchitectureMode,
                    isDark: isDark,
                    onChanged: wb.isAgentBusy ? null : wb.setArchitectureMode,
                  ),
                  ElevatedButton.icon(
                    key: const ValueKey('draft_spark_btn'),
                    onPressed: wb.isAgentBusy
                        ? null
                        : () async {
                            final text = _sparkController.text.trim();
                            if (text.isEmpty) {
                              AppToast.show(
                                context,
                                'Enter a one-sentence game idea to draft your spec.',
                                isDark: isDark,
                                accentColor: AppTheme.accentRedFor(isDark),
                              );
                              return;
                            }
                            await wb.handleStage1SparkSubmit(text);
                          },
                    icon: wb.isAgentBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome, size: 15),
                    label: Text(
                      wb.isAgentBusy
                          ? (wb.agentProgressStep ?? 'Drafting...')
                          : 'Draft Project Spec',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (wb.stage1InlineError != null) ...[
          const SizedBox(height: 12),
          _buildStage1InlineErrorBanner(
            wb: wb,
            isDark: isDark,
            textPrimary: textPrimary,
            retryKey: const ValueKey('stage1_intake_retry_btn'),
            onRetry: () => wb.pendingSparkClarification != null
                ? wb.confirmSparkClarification()
                : wb.handleStage1SparkSubmit(_sparkController.text),
          ),
        ],
        if (wb.pendingSparkClarification != null) ...[
          const SizedBox(height: 12),
          _buildSparkClarifyCard(
            wb: wb,
            pending: wb.pendingSparkClarification!,
            isDark: isDark,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: textMuted,
            cyan: cyan,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Starter Packs:',
              style: TextStyle(fontSize: 12, color: textMuted),
            ),
            for (final preset in UnrealSparkPresets.entries)
              ActionChip(
                key: ValueKey('preset_${preset.id}'),
                avatar: Icon(Icons.bolt_rounded, size: 14, color: cyan),
                label: Text(
                  preset.label,
                  style: TextStyle(fontSize: 12, color: textPrimary),
                ),
                onPressed: wb.isAgentBusy
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: red.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              wb.stage1InlineError ?? 'Request failed.',
              style: TextStyle(fontSize: 12.5, color: textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: retryKey,
            onPressed: wb.isAgentBusy ? null : onRetry,
            child: const Text('Retry'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: const Icon(Icons.close_rounded, size: 15),
            onPressed: wb.dismissStage1InlineError,
          ),
        ],
      ),
    );
  }

  Widget _buildSparkClarifyCard({
    required WorkbenchProvider wb,
    required SparkClarificationDraft pending,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color cyan,
  }) {
    final border = AppTheme.borderFor(isDark);
    return Container(
      key: const ValueKey('stage1_spark_clarify_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgPanelFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cyan.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Quick Forks · Sharpen "${pending.rawSpark}"',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close quick forks',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: Icon(Icons.close_rounded, size: 15, color: textMuted),
                onPressed:
                    wb.isAgentBusy ? null : wb.dismissSparkClarification,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Camera View:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final opt in pending.viewOptions)
                ChoiceChip(
                  key: ValueKey('clarify_view_${opt.id}'),
                  label: Text(opt.label),
                  selected: pending.viewChoiceId == opt.id,
                  onSelected: wb.isAgentBusy
                      ? null
                      : (_) => wb.updateSparkClarification(
                            viewChoiceId: opt.id,
                          ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Core Loop Focus:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final opt in SparkClarificationDraft.archetypeOptions)
                ChoiceChip(
                  key: ValueKey('clarify_archetype_${opt.id}'),
                  label: Text(opt.label),
                  selected: pending.archetypeId == opt.id,
                  onSelected: wb.isAgentBusy
                      ? null
                      : (_) => wb.updateSparkClarification(
                            archetypeId: opt.id,
                          ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'v0.1 Prototype Goal:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final opt in SparkClarificationDraft.prototypeHookOptions)
                ChoiceChip(
                  key: ValueKey('clarify_hook_${opt.id}'),
                  label: Text(opt.label),
                  selected: pending.prototypeHookId == opt.id,
                  onSelected: wb.isAgentBusy
                      ? null
                      : (_) => wb.updateSparkClarification(
                            prototypeHookId: opt.id,
                          ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: border),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const ValueKey('stage1_clarify_skip_btn'),
                onPressed: wb.isAgentBusy
                    ? null
                    : () => wb.confirmSparkClarification(skipPicks: true),
                child: const Text('Skip → Draft Now'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const ValueKey('stage1_clarify_confirm_btn'),
                onPressed: wb.isAgentBusy
                    ? null
                    : () => wb.confirmSparkClarification(skipPicks: false),
                icon: const Icon(Icons.auto_awesome, size: 15),
                label: const Text('Draft with Picks'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSparkContextCaption({
    required ProjectConceptBlueprint spec,
    required bool isDark,
    required Color textMuted,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgPanelFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          if (spec.sparkPrompt.trim().isNotEmpty) ...[
            Expanded(
              flex: 2,
              child: Text(
                'Spark: "${spec.sparkPrompt.trim()}"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: textMuted),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 3,
            child: Tooltip(
              message: spec.architectureMode.architectureContract,
              child: Text(
                spec.architectureMode.architectureContract,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitCoDesign(WorkbenchProvider wb) async {
    final text = _coDesignController.text.trim();
    if (text.isEmpty || wb.isAgentBusy) return;
    final res = await wb.applyStage1CoDesignInstruction(text);
    if (!mounted) return;
    if (res != null) {
      _coDesignController.clear();
    }
  }
}
