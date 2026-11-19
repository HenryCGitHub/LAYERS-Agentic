import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';

/// Stage 1: `1. Project Spec` (`PROJECT_SPEC.md` -> `ROOT_GODOT_CONTEXT`).
/// Unified single-space canvas with one top prompt bar (Idea Intake -> Compact Refine Bar)
/// paired directly with the 5-section Blueprint (`§01–§05`), Camera/Feel forks, and `v0.1` Epics.
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

  @override
  void dispose() {
    _sparkController.dispose();
    _coDesignController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final draft = wb.conceptDraft;
    final hasSpec = draft != null && draft.hasSpec;
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
                        _buildCompactRefineTopCard(
                          wb: wb,
                          spec: draft,
                          isDark: isDark,
                          textPrimary: textPrimary,
                          textMuted: textMuted,
                          cyan: cyan,
                        ),
                      const SizedBox(height: 20),
                      if (!hasSpec)
                        _buildEmptyBlueprintOutline(
                          isDark: isDark,
                          textPrimary: textPrimary,
                          textMuted: textMuted,
                          border: border,
                          cyan: cyan,
                        )
                      else
                        _buildCleanSpecDocument(context, wb, draft),
                    ],
                  ),
                ),
              ),
            ),
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
                Text(
                  spec.normalizedTitle,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.displayFont(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('reset_spark_btn'),
                  onPressed: wb.isAgentBusy
                      ? null
                      : () {
                          _sparkController.clear();
                          _coDesignController.clear();
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
                _GodotDimensionToggle(
                  dimension: wb.projectDimension,
                  isDark: isDark,
                  onChanged: wb.isAgentBusy ? null : wb.setProjectDimension,
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
                        return 'Sync & Open Workbench →';
                      }
                      final sliceCount = spec.initialEpics.fold<int>(
                        0,
                        (sum, e) => sum + e.featuresForRelease('v0.1').length,
                      );
                      return 'Approve & Launch (${spec.initialEpics.length} Epics · $sliceCount Features) →';
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
          'Turn a one-sentence idea into a playable v0.1 Godot 4 spec — camera, controls, tuning, and first Epics.',
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
                onSubmitted: (val) async {
                  if (!wb.isAgentBusy && val.trim().isNotEmpty) {
                    await wb.generateSpecFromSpark(val);
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
                  _GodotDimensionToggle(
                    dimension: wb.projectDimension,
                    isDark: isDark,
                    onChanged: wb.isAgentBusy ? null : wb.setProjectDimension,
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
                            await wb.generateSpecFromSpark(text);
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
            for (final preset in GodotSparkPresets.entries)
              ActionChip(
                key: ValueKey('preset_${preset.id}'),
                avatar: Icon(Icons.bolt_rounded, size: 14, color: cyan),
                label: Text(
                  preset.label,
                  style: TextStyle(fontSize: 12, color: textPrimary),
                ),
                onPressed: wb.isAgentBusy
                    ? null
                    : () => wb.loadPresetSpark(preset.id),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactRefineTopCard({
    required WorkbenchProvider wb,
    required ProjectConceptBlueprint spec,
    required bool isDark,
    required Color textPrimary,
    required Color textMuted,
    required Color cyan,
  }) {
    return Container(
      key: const ValueKey('stage1_unified_refine_bar'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgPanelFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.borderBrightFor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  message: spec.dimension.architectureContract,
                  child: Text(
                    spec.dimension.architectureContract,
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
          if (spec.lastCoDesignNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Updated: ${spec.lastCoDesignNote}',
              style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: cyan),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.auto_fix_high_rounded, size: 16, color: cyan),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('stage1_codesign_input'),
                  controller: _coDesignController,
                  style: TextStyle(fontSize: 13.5, color: textPrimary),
                  decoration: InputDecoration(
                    hintText:
                        'Refine spec: "Switch to third-person", "Make movement heavier", or "Add parry shield"...',
                    hintStyle: TextStyle(fontSize: 13, color: textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _submitCoDesign(wb),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                key: const ValueKey('stage1_codesign_apply_btn'),
                onPressed: wb.isAgentBusy ? null : () => _submitCoDesign(wb),
                child: Text(wb.isAgentBusy ? 'Applying...' : 'Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBlueprintOutline({
    required bool isDark,
    required Color textPrimary,
    required Color textMuted,
    required Color border,
    required Color cyan,
  }) {
    const sections = <(String, String, String)>[
      (
        '§01',
        'Core Fantasy & 30s Loop',
        '1-sentence game vision and 4 playable gameplay beats.',
      ),
      (
        '§02',
        'Global Godot 4 Scale & Architecture (3D m | 2D px)',
        'Camera framing fork (3D SpringArm3D or 2D Camera2D), scale, and InputMap actions.',
      ),
      (
        '§03',
        'Core Feel, Design Pillars & Conflict Trade-Offs',
        'Movement feel toggle (Snappy Arcade, Heavy Deliberate, Physics Momentum) and OVER rules.',
      ),
      (
        '§04',
        'Hard Scope Cuts (Do Not Build)',
        'Explicit exclusions keeping v0.1 free of menus, save systems, and networking bloat.',
      ),
      (
        '§05',
        'Seeded Epics & Initial v0.1 Feature Slices',
        'Large-Domain E01–E0N Epics holding playable 30–90 min v0.1 Feature slices.',
      ),
    ];

    return Container(
      key: const ValueKey('stage1_blueprint_empty_outline'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROJECT BLUEPRINT PREVIEW · §01–§05',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textMuted,
            ),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < sections.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: i == sections.length - 1
                  ? null
                  : BoxDecoration(
                      border: Border(bottom: BorderSide(color: border)),
                    ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 38,
                    child: Text(
                      sections[i].$1,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cyan.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sections[i].$2,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sections[i].$3,
                          style: TextStyle(fontSize: 12, color: textMuted),
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

  Future<void> _submitCoDesign(WorkbenchProvider wb) async {
    final text = _coDesignController.text.trim();
    if (text.isEmpty || wb.isAgentBusy) return;
    _coDesignController.clear();
    await wb.applyStage1CoDesignInstruction(text);
  }

  Widget _buildCleanSpecDocument(
    BuildContext context,
    WorkbenchProvider wb,
    ProjectConceptBlueprint spec,
  ) {
    final isDark = wb.isDark;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // §01 Core Fantasy & 30s Loop
        _SectionCard(
          isDark: isDark,
          code: '§01',
          title: 'Core Fantasy & 30s Loop',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spec.pitch,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: textPrimary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (int i = 0; i < spec.coreLoop.length; i++) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurfaceFor(isDark),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(color: border),
                      ),
                      child: Text(
                        '${i + 1}. ${spec.coreLoop[i]}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    if (i < spec.coreLoop.length - 1)
                      Icon(Icons.arrow_forward, size: 14, color: cyan),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // §02 Global Godot 4 Scale & Architecture
        _SectionCard(
          isDark: isDark,
          code: '§02',
          title: 'Global Godot 4 Scale & Architecture (${spec.dimension.pillLabel})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Co-Designer Fork · Camera Framing:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in spec.effectiveCameraDecisionOptions)
                    ChoiceChip(
                      key: ValueKey('camera_opt_${opt.id}'),
                      label: Text(opt.label),
                      selected: spec.cameraChoiceId == opt.id,
                      onSelected: (_) => wb.selectCameraDecisionOption(opt.id),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _ContractRow(label: 'Camera Rig', value: spec.cameraContract, isDark: isDark),
              _ContractRow(label: 'Player Scale', value: spec.characterScale, isDark: isDark),
              _ContractRow(label: 'Input Contract', value: spec.inputContract, isDark: isDark),
              _ContractRow(label: 'Asset Policy', value: spec.assetPolicy, isDark: isDark, isLast: true),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // §03 Core Feel, Design Pillars & Conflict Trade-Offs
        _SectionCard(
          isDark: isDark,
          code: '§03',
          title: 'Core Feel, Design Pillars & Conflict Trade-Offs',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Core Movement & Combat Feel:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in ProjectConceptBlueprint.coreFeelOptions)
                    ChoiceChip(
                      key: ValueKey('feel_opt_${opt.id}'),
                      label: Text(opt.label),
                      selected: spec.feelChoiceId == opt.id,
                      onSelected: (_) => wb.selectCoreFeelOption(opt.id),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              for (final p in spec.pillars)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: cyan, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(
                          p,
                          style: TextStyle(fontSize: 13.5, color: textPrimary, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              if (spec.tradeOffs.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in spec.tradeOffs)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurfaceFor(isDark),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(color: border),
                        ),
                        child: Text(
                          '${t.prefer}  OVER  ${t.avoid}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11.5,
                            color: textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // §04 Hard Scope Cuts (Do Not Build)
        _SectionCard(
          isDark: isDark,
          code: '§04',
          title: 'Hard Scope Cuts (Do Not Build)',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cut in spec.outOfScope)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: red.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    cut,
                    style: TextStyle(fontSize: 12.5, color: textPrimary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // §05 Seeded Epics & Initial v0.1 Feature Slices
        _SectionCard(
          isDark: isDark,
          code: '§05',
          title: 'Seeded Epics & Initial v0.1 Feature Slices',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: green.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 15, color: green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Strict v0.1 Prototype Gate: Only these Epics build first. v0.2+ waves & meta unlock after v0.1 passes Playtest.',
                        style: TextStyle(fontSize: 12, color: textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Release Done When: ${spec.releaseDoneWhen}',
                style: GoogleFonts.jetBrainsMono(fontSize: 12, color: cyan),
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < spec.initialEpics.length; i++)
                _buildStage1EpicCard(
                  wb: wb,
                  spec: spec,
                  epic: spec.initialEpics[i],
                  index: i,
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  textMuted: textMuted,
                  border: border,
                  cyan: cyan,
                  green: green,
                ),
            ],
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }

  Widget _buildStage1EpicCard({
    required WorkbenchProvider wb,
    required ProjectConceptBlueprint spec,
    required EpicSpec epic,
    required int index,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color border,
    required Color cyan,
    required Color green,
  }) {
    final v01Features = epic.featuresForRelease('v0.1');
    final beatText = epic.coreLoopBeat.trim().isNotEmpty
        ? epic.coreLoopBeat.trim()
        : (index < spec.coreLoop.length
            ? 'Beat ${index + 1} · ${spec.coreLoop[index]}'
            : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: index == 0 ? green.withValues(alpha: 0.45) : border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cyan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                ),
                child: Text(
                  '${epic.code} · ${epic.releaseVersion}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cyan,
                  ),
                ),
              ),
              if (index == 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                  ),
                  child: Text(
                    '#1 Build First',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: green,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  epic.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                if (beatText.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    beatText,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: cyan.withValues(alpha: 0.9),
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  epic.goal,
                  style: TextStyle(fontSize: 12.5, color: textSecondary),
                ),
                if (v01Features.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Divider(height: 1, color: border),
                  const SizedBox(height: 6),
                  for (final feat in v01Features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${feat.code} · ${feat.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                color: textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            feat.sliceTime,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                v01Features.isNotEmpty
                    ? '${v01Features.length} Feature slices'
                    : '${epic.checks.length} Checks · ${epic.tuning.length} Tuning',
                textAlign: TextAlign.right,
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: textMuted),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: ValueKey('stage1_epic_up_$index'),
                    tooltip: 'Move earlier in Playtest queue',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    iconSize: 16,
                    color: index > 0 ? textSecondary : textMuted.withValues(alpha: 0.3),
                    onPressed: index > 0
                        ? () => wb.moveInitialEpic(index, -1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    key: ValueKey('stage1_epic_down_$index'),
                    tooltip: 'Move later in Playtest queue',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    iconSize: 16,
                    color: index < spec.initialEpics.length - 1
                        ? textSecondary
                        : textMuted.withValues(alpha: 0.3),
                    onPressed: index < spec.initialEpics.length - 1
                        ? () => wb.moveInitialEpic(index, 1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  IconButton(
                    key: ValueKey('stage1_epic_remove_$index'),
                    tooltip: 'Remove from v0.1 scope',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    iconSize: 15,
                    color: spec.initialEpics.length > 1
                        ? AppTheme.accentRedFor(isDark)
                        : textMuted.withValues(alpha: 0.3),
                    onPressed: spec.initialEpics.length > 1
                        ? () => wb.removeInitialEpicAt(index)
                        : null,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GodotDimensionToggle extends StatelessWidget {
  final GodotProjectDimension dimension;
  final bool isDark;
  final ValueChanged<GodotProjectDimension>? onChanged;

  const _GodotDimensionToggle({
    required this.dimension,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cyan = AppTheme.accentCyanFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    Widget buildOption({
      required Key key,
      required GodotProjectDimension target,
    }) {
      final selected = dimension == target;
      return InkWell(
        key: key,
        onTap: onChanged == null ? null : () => onChanged!(target),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? cyan.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusXs),
            border: selected
                ? Border.all(color: cyan.withValues(alpha: 0.45))
                : null,
          ),
          child: Text(
            target.pillLabel,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? cyan : muted,
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('stage1_dimension_toggle'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOption(
            key: const ValueKey('stage1_dim_3d'),
            target: GodotProjectDimension.dim3d,
          ),
          const SizedBox(width: 2),
          buildOption(
            key: const ValueKey('stage1_dim_2d'),
            target: GodotProjectDimension.dim2d,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final bool isDark;
  final String code;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.isDark,
    required this.code,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceRaisedFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.borderFor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentCyanFor(isDark),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.displayFont(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimaryFor(isDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ContractRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final bool isLast;

  const _ContractRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.borderFor(isDark)),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: AppTheme.textMutedFor(isDark),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimaryFor(isDark),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
