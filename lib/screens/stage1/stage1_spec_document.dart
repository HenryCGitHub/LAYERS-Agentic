import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/agent_blueprints.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'stage1_shared_widgets.dart';

class Stage1SpecDocument extends StatefulWidget {
  final WorkbenchProvider workbench;
  final ProjectConceptBlueprint spec;
  final String? activeProjectId;

  const Stage1SpecDocument({
    super.key,
    required this.workbench,
    required this.spec,
    required this.activeProjectId,
  });

  @override
  State<Stage1SpecDocument> createState() => _Stage1SpecDocumentState();
}

class _Stage1SpecDocumentState extends State<Stage1SpecDocument> {
  final TextEditingController _pitchController = TextEditingController();
  final TextEditingController _cutController = TextEditingController();
  final TextEditingController _featureTitleController = TextEditingController();

  bool _editingPitch = false;
  bool _addingCut = false;
  String? _editingFeatureId;

  void _resetInlineFlags() {
    _editingPitch = false;
    _addingCut = false;
    _editingFeatureId = null;
  }

  @override
  void didUpdateWidget(covariant Stage1SpecDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeProjectId != widget.activeProjectId ||
        (!widget.spec.hasSpec &&
            (_editingPitch || _addingCut || _editingFeatureId != null))) {
      _resetInlineFlags();
      _pitchController.clear();
      _cutController.clear();
      _featureTitleController.clear();
    }
  }

  @override
  void dispose() {
    _pitchController.dispose();
    _cutController.dispose();
    _featureTitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _buildDocumentContent(context, widget.workbench, widget.spec);

  Widget _buildDocumentContent(
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
    final amber = AppTheme.accentAmberFor(isDark);
    final changed = wb.lastStage1ChangedSections;
    final scope = Stage1ScopeSummary.fromBlueprint(spec);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // §01 Core Fantasy & 30s Loop
        Stage1SectionCard(
          isDark: isDark,
          code: '§01',
          title: 'Core Fantasy & 30s Loop',
          isUpdated: changed.contains('s01'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_editingPitch)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('stage1_pitch_input'),
                        controller: _pitchController,
                        minLines: 1,
                        maxLines: 3,
                        style: TextStyle(fontSize: 14.5, color: textPrimary),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        onSubmitted: (val) {
                          wb.updateRootSpecSections(pitch: val);
                          setState(() => _editingPitch = false);
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const ValueKey('stage1_pitch_save_btn'),
                      tooltip: 'Save pitch',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.check_rounded, size: 17, color: green),
                      onPressed: () {
                        wb.updateRootSpecSections(pitch: _pitchController.text);
                        setState(() => _editingPitch = false);
                      },
                    ),
                    IconButton(
                      key: const ValueKey('stage1_pitch_cancel_btn'),
                      tooltip: 'Cancel pitch edit',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => setState(() => _editingPitch = false),
                    ),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        spec.pitch,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: textPrimary,
                          height: 1.45,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('stage1_edit_pitch_btn'),
                      tooltip: 'Edit pitch',
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.only(left: 6),
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 15,
                        color: textSecondary,
                      ),
                      onPressed: wb.isAgentBusy
                          ? null
                          : () {
                              _pitchController.text = spec.pitch;
                              setState(() => _editingPitch = true);
                            },
                    ),
                  ],
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

        // §02 Unreal Engine 5 Scale & Architecture
        Stage1SectionCard(
          isDark: isDark,
          code: '§02',
          title: 'Unreal Engine 5 Scale & Architecture (${spec.architectureMode.pillLabel})',
          isUpdated: changed.contains('s02'),
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
                      onSelected: wb.isAgentBusy
                          ? null
                          : (_) => wb.selectCameraDecisionOption(opt.id),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Stage1ContractRow(label: 'Camera Rig', value: spec.cameraContract, isDark: isDark),
              Stage1ContractRow(label: 'Player Scale', value: spec.characterScale, isDark: isDark),
              Stage1ContractRow(label: 'Input Contract', value: spec.inputContract, isDark: isDark),
              Stage1ContractRow(label: 'Asset Policy', value: spec.assetPolicy, isDark: isDark, isLast: true),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // §03 Core Feel, Design Pillars & Conflict Trade-Offs
        Stage1SectionCard(
          isDark: isDark,
          code: '§03',
          title: 'Core Feel, Design Pillars & Conflict Trade-Offs',
          isUpdated: changed.contains('s03'),
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
                      onSelected: wb.isAgentBusy
                          ? null
                          : (_) => wb.selectCoreFeelOption(opt.id),
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
        Stage1SectionCard(
          isDark: isDark,
          code: '§04',
          title: 'Hard Scope Cuts (Do Not Build)',
          isUpdated: changed.contains('s04'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < spec.outOfScope.length; i++)
                Container(
                  padding: const EdgeInsets.only(
                    left: 10,
                    right: 6,
                    top: 6,
                    bottom: 6,
                  ),
                  decoration: BoxDecoration(
                    color: red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: red.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        spec.outOfScope[i],
                        style: TextStyle(fontSize: 12.5, color: textPrimary),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        key: ValueKey('stage1_cut_remove_$i'),
                        borderRadius: BorderRadius.circular(4),
                        onTap: wb.isAgentBusy
                            ? null
                            : () => wb.removeStage1OutOfScopeCut(i),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_addingCut)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        key: const ValueKey('stage1_cut_add_input'),
                        controller: _cutController,
                        style: TextStyle(fontSize: 12.5, color: textPrimary),
                        decoration: InputDecoration(
                          hintText: 'No ...',
                          hintStyle: TextStyle(fontSize: 12, color: textMuted),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                        ),
                        onSubmitted: (val) {
                          wb.addStage1OutOfScopeCut(val);
                          setState(() => _addingCut = false);
                        },
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('stage1_cut_add_save_btn'),
                      tooltip: 'Add scope cut',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.check_rounded, size: 16, color: green),
                      onPressed: () {
                        wb.addStage1OutOfScopeCut(_cutController.text);
                        setState(() => _addingCut = false);
                      },
                    ),
                    IconButton(
                      key: const ValueKey('stage1_cut_add_cancel_btn'),
                      tooltip: 'Cancel cut',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 15),
                      onPressed: () => setState(() => _addingCut = false),
                    ),
                  ],
                )
              else
                ActionChip(
                  key: const ValueKey('stage1_cut_add_btn'),
                  avatar: Icon(Icons.add_rounded, size: 14, color: cyan),
                  label: Text(
                    'Add cut',
                    style: TextStyle(fontSize: 12, color: textPrimary),
                  ),
                  onPressed: wb.isAgentBusy
                      ? null
                      : () {
                          _cutController.clear();
                          setState(() => _addingCut = true);
                        },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // §05 Seeded Epics & Initial v0.1 Feature Slices
        Stage1SectionCard(
          isDark: isDark,
          code: '§05',
          title: 'Seeded Epics & Initial v0.1 Feature Slices',
          isUpdated: changed.contains('s05'),
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
              Container(
                key: const ValueKey('stage1_scope_preview_card'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurfaceFor(isDark),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(
                    color: scope.isLean
                        ? border
                        : amber.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: (scope.isLean ? green : amber)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusXs,
                                ),
                              ),
                              child: Text(
                                scope.isLean ? 'Lean v0.1' : 'Scope Check',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: scope.isLean ? green : amber,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${scope.epicCount} Epics · ${scope.featureCount} Features · ${scope.formattedDuration} · ${scope.inputActionCount} Inputs',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                color: textPrimary,
                              ),
                            ),
                          ],
                        ),
                        if (scope.featureCount > 8 || scope.epicCount > 4)
                          ActionChip(
                            key: const ValueKey('stage1_trim_lean_btn'),
                            label: Text(
                              'Trim to Lean v0.1',
                              style: TextStyle(fontSize: 11, color: textPrimary),
                            ),
                            onPressed: wb.isAgentBusy
                                ? null
                                : () => wb.applyStage1CoDesignInstruction(
                                      'Trim v0.1 scope to 2-3 Epics (<= 6 Features total) and move extra systems into §04 Hard Scope Cuts.',
                                    ),
                          ),
                      ],
                    ),
                    if (scope.warnings.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final w in scope.warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '• $w',
                            style: TextStyle(fontSize: 11.5, color: amber),
                          ),
                        ),
                    ],
                    if (scope.firstFeatureLabel != null ||
                        scope.firstPlaytestGate != null) ...[
                      const SizedBox(height: 8),
                      Divider(height: 1, color: border),
                      const SizedBox(height: 8),
                      Text(
                        'First Playtest (${scope.firstFeatureLabel ?? 'F01'}) · ${scope.firstTestScenePath ?? '/Game/Maps/Lvl_ArenaProto.umap'}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: cyan,
                        ),
                      ),
                      if (scope.firstPlaytestGate != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          scope.firstPlaytestGate!,
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ],
                    ],
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
                      child: _editingFeatureId == feat.id
                          ? Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: ValueKey('stage1_feat_input_${feat.id}'),
                                    controller: _featureTitleController,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11.5,
                                      color: textPrimary,
                                    ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                    ),
                                    onSubmitted: (val) {
                                      wb.renameStage1FeatureSlice(
                                        index,
                                        feat.id,
                                        val,
                                      );
                                      setState(() => _editingFeatureId = null);
                                    },
                                  ),
                                ),
                                IconButton(
                                  key: ValueKey('stage1_feat_save_${feat.id}'),
                                  tooltip: 'Save slice name',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  icon: Icon(
                                    Icons.check_rounded,
                                    size: 15,
                                    color: green,
                                  ),
                                  onPressed: () {
                                    wb.renameStage1FeatureSlice(
                                      index,
                                      feat.id,
                                      _featureTitleController.text,
                                    );
                                    setState(() => _editingFeatureId = null);
                                  },
                                ),
                                IconButton(
                                  key: ValueKey('stage1_feat_cancel_${feat.id}'),
                                  tooltip: 'Cancel rename',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                  ),
                                  onPressed: () =>
                                      setState(() => _editingFeatureId = null),
                                ),
                              ],
                            )
                          : Row(
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
                                const SizedBox(width: 4),
                                IconButton(
                                  key: ValueKey('stage1_feat_edit_${feat.id}'),
                                  tooltip: 'Rename Feature slice',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                    minHeight: 22,
                                  ),
                                  iconSize: 13,
                                  color: textSecondary,
                                  onPressed: wb.isAgentBusy
                                      ? null
                                      : () {
                                          _featureTitleController.text =
                                              feat.title;
                                          setState(
                                            () => _editingFeatureId = feat.id,
                                          );
                                        },
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  key: ValueKey('stage1_feat_remove_${feat.id}'),
                                  tooltip: 'Remove Feature slice',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                    minHeight: 22,
                                  ),
                                  iconSize: 13,
                                  color: v01Features.length > 1
                                      ? AppTheme.accentRedFor(isDark)
                                      : textMuted.withValues(alpha: 0.3),
                                  onPressed: (!wb.isAgentBusy &&
                                          v01Features.length > 1)
                                      ? () => wb.removeStage1FeatureSlice(
                                            index,
                                            feat.id,
                                          )
                                      : null,
                                  icon: const Icon(Icons.close_rounded),
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
                    color: (!wb.isAgentBusy && index > 0)
                        ? textSecondary
                        : textMuted.withValues(alpha: 0.3),
                    onPressed: (!wb.isAgentBusy && index > 0)
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
                    color: (!wb.isAgentBusy &&
                            index < spec.initialEpics.length - 1)
                        ? textSecondary
                        : textMuted.withValues(alpha: 0.3),
                    onPressed: (!wb.isAgentBusy &&
                            index < spec.initialEpics.length - 1)
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
                    color: (!wb.isAgentBusy && spec.initialEpics.length > 1)
                        ? AppTheme.accentRedFor(isDark)
                        : textMuted.withValues(alpha: 0.3),
                    onPressed: (!wb.isAgentBusy && spec.initialEpics.length > 1)
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
