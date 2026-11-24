import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/agent_blueprints.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'stage1_epic_preview_section.dart';
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
  final TextEditingController _cameraCtrl = TextEditingController();
  final TextEditingController _scaleCtrl = TextEditingController();
  final TextEditingController _inputContractCtrl = TextEditingController();
  final TextEditingController _assetPolicyCtrl = TextEditingController();
  final TextEditingController _pillarsCtrl = TextEditingController();
  final TextEditingController _tradeoffsCtrl = TextEditingController();

  bool _editingPitch = false;
  bool _editingContracts = false;
  bool _editingPillars = false;
  bool _addingCut = false;
  String? _tradeoffsError;

  String? _lastSyncedPitch;
  String? _lastSyncedCamera;
  String? _lastSyncedScale;
  String? _lastSyncedInputContract;
  String? _lastSyncedAssetPolicy;
  String? _lastSyncedPillars;
  String? _lastSyncedTradeoffs;

  void _resetInlineFlags() {
    _editingPitch = false;
    _editingContracts = false;
    _editingPillars = false;
    _addingCut = false;
    _tradeoffsError = null;
  }

  static String _formatTradeOffs(List<TradeOffRule> rules) =>
      rules.map((t) => '${t.prefer} OVER ${t.avoid}').join('\n');

  @override
  void didUpdateWidget(covariant Stage1SpecDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeProjectId != widget.activeProjectId ||
        (!widget.spec.hasSpec &&
            (_editingPitch ||
                _editingContracts ||
                _editingPillars ||
                _addingCut))) {
      _resetInlineFlags();
      _pitchController.clear();
      _cutController.clear();
      _cameraCtrl.clear();
      _scaleCtrl.clear();
      _inputContractCtrl.clear();
      _assetPolicyCtrl.clear();
      _pillarsCtrl.clear();
      _tradeoffsCtrl.clear();
      return;
    }
    if (_editingPitch &&
        (oldWidget.spec.pitch != widget.spec.pitch ||
            (_lastSyncedPitch != null &&
                _lastSyncedPitch != widget.spec.pitch))) {
      _pitchController.text = widget.spec.pitch;
      _lastSyncedPitch = widget.spec.pitch;
    }
    if (_editingContracts) {
      if (oldWidget.spec.cameraContract != widget.spec.cameraContract ||
          (_lastSyncedCamera != null &&
              _lastSyncedCamera != widget.spec.cameraContract)) {
        _cameraCtrl.text = widget.spec.cameraContract;
        _lastSyncedCamera = widget.spec.cameraContract;
      }
      if (oldWidget.spec.characterScale != widget.spec.characterScale ||
          (_lastSyncedScale != null &&
              _lastSyncedScale != widget.spec.characterScale)) {
        _scaleCtrl.text = widget.spec.characterScale;
        _lastSyncedScale = widget.spec.characterScale;
      }
      if (oldWidget.spec.inputContract != widget.spec.inputContract ||
          (_lastSyncedInputContract != null &&
              _lastSyncedInputContract != widget.spec.inputContract)) {
        _inputContractCtrl.text = widget.spec.inputContract;
        _lastSyncedInputContract = widget.spec.inputContract;
      }
      if (oldWidget.spec.assetPolicy != widget.spec.assetPolicy ||
          (_lastSyncedAssetPolicy != null &&
              _lastSyncedAssetPolicy != widget.spec.assetPolicy)) {
        _assetPolicyCtrl.text = widget.spec.assetPolicy;
        _lastSyncedAssetPolicy = widget.spec.assetPolicy;
      }
    }
    if (_editingPillars) {
      final oldPillars = oldWidget.spec.pillars.join('\n');
      final nextPillars = widget.spec.pillars.join('\n');
      if (oldPillars != nextPillars ||
          (_lastSyncedPillars != null && _lastSyncedPillars != nextPillars)) {
        _pillarsCtrl.text = nextPillars;
        _lastSyncedPillars = nextPillars;
      }
      final oldTradeoffs = _formatTradeOffs(oldWidget.spec.tradeOffs);
      final nextTradeoffs = _formatTradeOffs(widget.spec.tradeOffs);
      if (oldTradeoffs != nextTradeoffs ||
          (_lastSyncedTradeoffs != null &&
              _lastSyncedTradeoffs != nextTradeoffs)) {
        _tradeoffsCtrl.text = nextTradeoffs;
        _lastSyncedTradeoffs = nextTradeoffs;
        _tradeoffsError = null;
      }
    }
  }

  @override
  void dispose() {
    _pitchController.dispose();
    _cutController.dispose();
    _cameraCtrl.dispose();
    _scaleCtrl.dispose();
    _inputContractCtrl.dispose();
    _assetPolicyCtrl.dispose();
    _pillarsCtrl.dispose();
    _tradeoffsCtrl.dispose();
    super.dispose();
  }

  static List<TradeOffRule> _parseTradeOffLines(String raw) {
    final out = <TradeOffRule>[];
    for (final line in raw.split('\n')) {
      final clean = line.trim();
      if (clean.isEmpty) continue;
      final overMatch = RegExp(r'\s+OVER\s+', caseSensitive: false)
          .firstMatch(clean);
      if (overMatch != null) {
        final prefer = clean.substring(0, overMatch.start).trim();
        final avoid = clean.substring(overMatch.end).trim();
        if (prefer.isNotEmpty && avoid.isNotEmpty) {
          out.add(TradeOffRule(prefer: prefer, avoid: avoid));
        }
      }
    }
    return out;
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
    final changed = wb.lastStage1ChangedSections;

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
                              _lastSyncedPitch = spec.pitch;
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
          trailing: TextButton.icon(
            key: const ValueKey('stage1_edit_contracts_btn'),
            onPressed: wb.isAgentBusy
                ? null
                : () {
                    if (!_editingContracts) {
                      _cameraCtrl.text = spec.cameraContract;
                      _scaleCtrl.text = spec.characterScale;
                      _inputContractCtrl.text = spec.inputContract;
                      _assetPolicyCtrl.text = spec.assetPolicy;
                      _lastSyncedCamera = spec.cameraContract;
                      _lastSyncedScale = spec.characterScale;
                      _lastSyncedInputContract = spec.inputContract;
                      _lastSyncedAssetPolicy = spec.assetPolicy;
                    }
                    setState(() => _editingContracts = !_editingContracts);
                  },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            ),
            icon: Icon(
              _editingContracts ? Icons.close : Icons.edit_outlined,
              size: 13,
            ),
            label: Text(
              _editingContracts ? 'Cancel' : 'Edit Contracts',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
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
              if (_editingContracts) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: cyan.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('stage1_camera_input'),
                        controller: _cameraCtrl,
                        style: TextStyle(fontSize: 12.5, color: textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Camera Rig',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('stage1_scale_input'),
                        controller: _scaleCtrl,
                        style: TextStyle(fontSize: 12.5, color: textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Player Scale (cm / cm/s)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('stage1_input_contract_input'),
                        controller: _inputContractCtrl,
                        style: TextStyle(fontSize: 12.5, color: textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Input Contract (IMC_* / IA_*)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('stage1_asset_policy_input'),
                        controller: _assetPolicyCtrl,
                        style: TextStyle(fontSize: 12.5, color: textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Asset Policy',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                setState(() => _editingContracts = false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            key: const ValueKey('stage1_contracts_save_btn'),
                            onPressed: () {
                              wb.updateRootSpecSections(
                                cameraContract: _cameraCtrl.text.trim(),
                                characterScale: _scaleCtrl.text.trim(),
                                inputContract: _inputContractCtrl.text.trim(),
                                assetPolicy: _assetPolicyCtrl.text.trim(),
                              );
                              setState(() => _editingContracts = false);
                            },
                            child: const Text(
                              'Save Contracts',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Stage1ContractRow(
                  label: 'Camera Rig',
                  value: spec.cameraContract,
                  isDark: isDark,
                ),
                Stage1ContractRow(
                  label: 'Player Scale',
                  value: spec.characterScale,
                  isDark: isDark,
                ),
                Stage1ContractRow(
                  label: 'Input Contract',
                  value: spec.inputContract,
                  isDark: isDark,
                ),
                Stage1ContractRow(
                  label: 'Asset Policy',
                  value: spec.assetPolicy,
                  isDark: isDark,
                  isLast: true,
                ),
              ],
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
          trailing: TextButton.icon(
            key: const ValueKey('stage1_edit_pillars_btn'),
            onPressed: wb.isAgentBusy
                ? null
                : () {
                    if (!_editingPillars) {
                      final pillarsText = spec.pillars.join('\n');
                      final tradeoffsText = _formatTradeOffs(spec.tradeOffs);
                      _pillarsCtrl.text = pillarsText;
                      _tradeoffsCtrl.text = tradeoffsText;
                      _lastSyncedPillars = pillarsText;
                      _lastSyncedTradeoffs = tradeoffsText;
                    }
                    setState(() {
                      _tradeoffsError = null;
                      _editingPillars = !_editingPillars;
                    });
                  },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            ),
            icon: Icon(
              _editingPillars ? Icons.close : Icons.edit_outlined,
              size: 13,
            ),
            label: Text(
              _editingPillars ? 'Cancel' : 'Edit Pillars',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
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
              if (_editingPillars) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: cyan.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('stage1_pillars_input'),
                        controller: _pillarsCtrl,
                        minLines: 2,
                        maxLines: 5,
                        style: TextStyle(fontSize: 12.5, color: textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Design Pillars (one per line)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('stage1_tradeoffs_input'),
                        controller: _tradeoffsCtrl,
                        minLines: 2,
                        maxLines: 4,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText:
                              'Trade-Offs (Prefer OVER Avoid, one per line)',
                          isDense: true,
                        ),
                      ),
                      if (_tradeoffsError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _tradeoffsError!,
                          key: const ValueKey('stage1_tradeoffs_error'),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.accentRedFor(isDark),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              _editingPillars = false;
                              _tradeoffsError = null;
                            }),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            key: const ValueKey('stage1_pillars_save_btn'),
                            onPressed: () {
                              final lines = _pillarsCtrl.text
                                  .split('\n')
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList();
                              final List<TradeOffRule> nextTradeOffs;
                              if (_tradeoffsCtrl.text.trim().isEmpty) {
                                nextTradeOffs = const <TradeOffRule>[];
                              } else {
                                final nonEmptyLines = _tradeoffsCtrl.text
                                    .split('\n')
                                    .map((s) => s.trim())
                                    .where((s) => s.isNotEmpty)
                                    .toList();
                                final rules =
                                    _parseTradeOffLines(_tradeoffsCtrl.text);
                                if (rules.length < nonEmptyLines.length) {
                                  setState(() {
                                    _tradeoffsError =
                                        'Use "<Prefer> OVER <Avoid>" on each line (or leave blank to clear).';
                                  });
                                  return;
                                }
                                nextTradeOffs = rules;
                              }
                              wb.updateRootSpecSections(
                                pillars: lines,
                                tradeOffs: nextTradeOffs,
                              );
                              setState(() {
                                _tradeoffsError = null;
                                _editingPillars = false;
                              });
                            },
                            child: const Text(
                              'Save Pillars',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                for (final p in spec.pillars)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ',
                          style: TextStyle(
                            color: cyan,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            p,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: textPrimary,
                              height: 1.4,
                            ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.bgSurfaceFor(isDark),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
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
                      Flexible(
                        child: Text(
                          spec.outOfScope[i],
                          style: TextStyle(fontSize: 12.5, color: textPrimary),
                        ),
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
        Stage1EpicPreviewSection(
          workbench: wb,
          spec: spec,
          activeProjectId: widget.activeProjectId,
          isUpdated: changed.contains('s05'),
        ),
        const SizedBox(height: 36),
      ],
    );
  }
}
