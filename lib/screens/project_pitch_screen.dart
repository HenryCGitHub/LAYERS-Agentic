import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';

/// Stage 1: `1. Project Spec` (`PROJECT_SPEC.md` -> `ROOT_MCP_CONTEXT`).
/// State 1A: 1-Sentence Spark + 3 Unreal Presets (`Shellbreaker`, `Railjack Drift`, `Ember Keep`).
/// State 1B: Centered Editorial Spec Document (`Clean Spec Document` | `Raw ROOT_MCP_CONTEXT.md`)
/// paired with `1 UU = 1 cm` architecture, camera forks, strict `v0.1` Epics, and Co-Designer bar.
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
    final showSpark = wb.showingSparkPicker || draft == null || !draft.hasSpec;
    if (showSpark) {
      return _buildSparkOnboarding(context, wb, draft);
    }
    return _buildSpecDocumentWorkspace(context, wb, draft);
  }

  Widget _buildSparkOnboarding(
    BuildContext context,
    WorkbenchProvider wb,
    ProjectConceptBlueprint? existingDraft,
  ) {
    final isDark = wb.isDark;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);

    return Container(
      color: AppTheme.bgBaseFor(isDark),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        border: Border.all(color: cyan.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        'STAGE 1 · UNREAL MCP ROOT SPEC',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cyan,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (existingDraft != null && existingDraft.hasSpec)
                      TextButton.icon(
                        key: const ValueKey('resume_spec_btn'),
                        onPressed: wb.resumeActiveRootSpec,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                        label: Text(
                          'Resume ${existingDraft.normalizedTitle} Spec',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Describe your Unreal game in one sentence.',
                  style: AppTheme.displayFont(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'LAYERS drafts a clean PROJECT_SPEC.md with 1 UU = 1 cm Unreal contracts and strictly v0.1 prototype Epics before anything hits Unreal MCP.',
                  style: TextStyle(
                    fontSize: 14,
                    color: textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
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
                              'e.g. Top-down twin-stick crustacean mech arena shooter with claw dash armor breaks and 3-wave combat...',
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
                          _TargetEngineToggle(
                            target: wb.targetEngine,
                            isDark: isDark,
                            onChanged: wb.setTargetEngine,
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
                                        'Enter a 1-sentence game idea or pick a preset below.',
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome, size: 15),
                            label: Text(
                              wb.isAgentBusy
                                  ? (wb.agentProgressStep ?? 'Drafting...')
                                  : 'Draft Project Spec ✦',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'OR START FROM AN UNREAL STARTER SPEC',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final preset in UnrealSparkPresets.entries)
                      InkWell(
                        key: ValueKey('preset_pill_${preset.id}'),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        onTap: wb.isAgentBusy
                            ? null
                            : () {
                                _sparkController.text = preset.sparkPrompt;
                                wb.loadPresetSpark(preset.id);
                              },
                        child: Container(
                          width: 236,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.bgSurfaceFor(isDark),
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                            border: Border.all(color: border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      preset.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: 14,
                                    color: cyan,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                preset.subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textMuted,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecDocumentWorkspace(
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

    return Container(
      color: AppTheme.bgBaseFor(isDark),
      child: Column(
        children: [
          // Top editorial bar
          Container(
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
                      TextButton.icon(
                        key: const ValueKey('back_to_spark_btn'),
                        onPressed: wb.showSparkPicker,
                        icon: const Icon(Icons.arrow_back, size: 15),
                        label: const Text('Change Spark', style: TextStyle(fontSize: 12)),
                      ),
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
                    ],
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      // View Tabs: Clean Spec Document | Raw ROOT_MCP_CONTEXT.md
                      _SegmentedTab(
                        isDark: isDark,
                        leftKey: const ValueKey('stage1_tab_clean'),
                        rightKey: const ValueKey('stage1_tab_raw'),
                        leftLabel: 'Clean Spec Document',
                        rightLabel: 'Raw ROOT_MCP_CONTEXT.md',
                        isRightSelected: wb.showRawRootContext,
                        onSelect: (isRaw) => wb.toggleRawRootContext(isRaw),
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
                        label: const Text('Approve & Launch Unreal Workbench →'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Centered single-column scrolling document
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: wb.showRawRootContext
                      ? _buildRawContextView(context, wb, isDark, textPrimary, border, cyan)
                      : _buildCleanSpecDocument(context, wb, spec),
                ),
              ),
            ),
          ),

          // Bottom Co-Designer bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bgPanelFor(isDark),
              border: Border(top: BorderSide(color: border)),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (spec.lastCoDesignNote.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Co-Designer: ${spec.lastCoDesignNote}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: cyan,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Icon(Icons.smart_toy_outlined, size: 16, color: cyan),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('stage1_codesign_input'),
                            controller: _coDesignController,
                            style: TextStyle(fontSize: 13, color: textPrimary),
                            decoration: InputDecoration(
                              hintText:
                                  'Co-Designer: "Switch camera to third-person" or "No boss phase in v0.1"...',
                              hintStyle: TextStyle(fontSize: 13, color: textMuted),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onSubmitted: (val) async {
                              await _submitCoDesign(wb);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          key: const ValueKey('stage1_codesign_apply_btn'),
                          onPressed: wb.isAgentBusy
                              ? null
                              : () => _submitCoDesign(wb),
                          child: Text(wb.isAgentBusy ? 'Applying...' : 'Apply ✦'),
                        ),
                      ],
                    ),
                  ],
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
    _coDesignController.clear();
    await wb.applyStage1CoDesignInstruction(text);
  }

  Widget _buildRawContextView(
    BuildContext context,
    WorkbenchProvider wb,
    bool isDark,
    Color textPrimary,
    Color border,
    Color cyan,
  ) {
    final rawText = wb.activeRootMcpMarkdown;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgInsetFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Exact ROOT_MCP_CONTEXT Wire Markdown',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cyan,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: rawText));
                  AppToast.show(
                    context,
                    'Copied ROOT_MCP_CONTEXT Markdown',
                    isDark: isDark,
                  );
                },
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy Context', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            rawText,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12.5,
              color: textPrimary,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
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
        // Target Architecture banner row
        Row(
          children: [
            _TargetEngineToggle(
              target: spec.targetEngine,
              isDark: isDark,
              onChanged: wb.setTargetEngine,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                spec.targetEngine.architectureContract,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

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

        // §02 Global Unreal Scale & Architecture (1 UU = 1 cm)
        _SectionCard(
          isDark: isDark,
          code: '§02',
          title: 'Global Unreal Scale & Architecture (1 UU = 1 cm)',
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
                  for (final opt in spec.cameraDecisionOptions)
                    ChoiceChip(
                      key: ValueKey('camera_opt_${opt.id}'),
                      label: Text(opt.label),
                      selected: spec.cameraChoiceId == opt.id,
                      onSelected: (_) => wb.selectCameraDecisionOption(opt.id),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _ContractRow(label: 'Camera & Boom', value: spec.cameraContract, isDark: isDark),
              _ContractRow(label: 'Player Scale', value: spec.characterScale, isDark: isDark),
              _ContractRow(label: 'Input Contract', value: spec.inputContract, isDark: isDark),
              _ContractRow(label: 'Asset Policy', value: spec.assetPolicy, isDark: isDark, isLast: true),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // §03 Design Pillars & Conflict Trade-Offs
        _SectionCard(
          isDark: isDark,
          code: '§03',
          title: 'Design Pillars & Conflict Trade-Offs',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

        // §05 Initial Release (v0.1 Prototype Epics Only)
        _SectionCard(
          isDark: isDark,
          code: '§05',
          title: 'Initial Release (v0.1 Prototype Epics Only)',
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
                        'Strict v0.1 Prototype Gate: Only these Epics build first. v0.2+ waves & meta unlock after v0.1 passes PIE.',
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
              for (final ep in spec.initialEpics)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cyan.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                        ),
                        child: Text(
                          '${ep.code} · ${ep.releaseVersion}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cyan,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ep.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              ep.goal,
                              style: TextStyle(fontSize: 12.5, color: textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${ep.checks.length} Checks\n${ep.tuning.length} Tuning',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: textMuted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }
}

class _TargetEngineToggle extends StatelessWidget {
  final UnrealTargetEngine target;
  final bool isDark;
  final ValueChanged<UnrealTargetEngine> onChanged;

  const _TargetEngineToggle({
    required this.target,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(isDark);
    final activeBg = AppTheme.accentCyanFor(isDark).withValues(alpha: 0.16);
    final activeFg = AppTheme.accentCyanFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    Widget btn(UnrealTargetEngine mode, Key key) {
      final selected = target == mode;
      return InkWell(
        key: key,
        onTap: () => onChanged(mode),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusXs),
          ),
          child: Text(
            mode.shortLabel,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? activeFg : muted,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(UnrealTargetEngine.ue5Mcp, const ValueKey('stage1_target_ue5')),
          btn(UnrealTargetEngine.ue6Verse, const ValueKey('stage1_target_ue6')),
        ],
      ),
    );
  }
}

class _SegmentedTab extends StatelessWidget {
  final bool isDark;
  final Key leftKey;
  final Key rightKey;
  final String leftLabel;
  final String rightLabel;
  final bool isRightSelected;
  final ValueChanged<bool> onSelect;

  const _SegmentedTab({
    required this.isDark,
    required this.leftKey,
    required this.rightKey,
    required this.leftLabel,
    required this.rightLabel,
    required this.isRightSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(isDark);
    final raised = AppTheme.bgSurfaceRaisedFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: leftKey,
            onTap: () => onSelect(false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: !isRightSelected ? raised : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              ),
              child: Text(
                leftLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: !isRightSelected ? FontWeight.w600 : FontWeight.w400,
                  color: !isRightSelected ? primary : muted,
                ),
              ),
            ),
          ),
          InkWell(
            key: rightKey,
            onTap: () => onSelect(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isRightSelected ? raised : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              ),
              child: Text(
                rightLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isRightSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isRightSelected ? primary : muted,
                ),
              ),
            ),
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
