import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/agent_blueprints.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import '../workbench/plain_doc_widgets.dart';
import 'stage1_epic_preview_section.dart';
import 'stage1_shared_widgets.dart';

/// Flat Project Brief document body (`§01 Pitch`, `Core Loop`, `§02 UE5 Setup`,
/// `§03 Pillars & Trade-Offs`, `§04 Out of Scope`, and `§05 Initial v0.1 Scope`).
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
  bool _editingPitch = false;
  bool _editingContracts = false;
  bool _editingPillars = false;
  bool _addingCut = false;

  final TextEditingController _pitchController = TextEditingController();
  final TextEditingController _ueProjectAnchorCtrl = TextEditingController();
  final TextEditingController _cameraCtrl = TextEditingController();
  final TextEditingController _scaleCtrl = TextEditingController();
  final TextEditingController _inputContractCtrl = TextEditingController();
  final TextEditingController _assetPolicyCtrl = TextEditingController();
  final TextEditingController _pillarsCtrl = TextEditingController();
  final TextEditingController _tradeoffsCtrl = TextEditingController();
  final TextEditingController _cutController = TextEditingController();

  String? _lastProjectId;
  String? _lastSyncedPitch;
  String? _lastSyncedUeAnchor;
  String? _lastSyncedCamera;
  String? _lastSyncedScale;
  String? _lastSyncedInputContract;
  String? _lastSyncedAssetPolicy;
  String? _lastSyncedPillars;
  String? _lastSyncedTradeoffs;
  String? _tradeoffsError;

  static String _formatTradeOffs(List<TradeOffRule> rules) =>
      rules.map((t) => '${t.prefer} OVER ${t.avoid}').join('\n');

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
  void initState() {
    super.initState();
    _lastProjectId = widget.activeProjectId;
  }

  @override
  void didUpdateWidget(covariant Stage1SpecDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastProjectId != widget.activeProjectId ||
        (!widget.spec.hasSpec &&
            (_editingPitch ||
                _editingContracts ||
                _editingPillars ||
                _addingCut))) {
      _lastProjectId = widget.activeProjectId;
      _editingPitch = false;
      _editingContracts = false;
      _editingPillars = false;
      _addingCut = false;
      _tradeoffsError = null;
      _pitchController.clear();
      _cutController.clear();
      _lastSyncedPitch = null;
    }
    if (_editingPitch &&
        (oldWidget.spec.pitch != widget.spec.pitch ||
            (_lastSyncedPitch != null &&
                _lastSyncedPitch != widget.spec.pitch))) {
      _pitchController.text = widget.spec.pitch;
      _lastSyncedPitch = widget.spec.pitch;
    }
    if (_editingContracts) {
      if (oldWidget.spec.ueProjectAnchor != widget.spec.ueProjectAnchor ||
          (_lastSyncedUeAnchor != null &&
              _lastSyncedUeAnchor != widget.spec.ueProjectAnchor)) {
        _ueProjectAnchorCtrl.text = widget.spec.ueProjectAnchor;
        _lastSyncedUeAnchor = widget.spec.ueProjectAnchor;
      }
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
      }
    }
  }

  @override
  void dispose() {
    _pitchController.dispose();
    _ueProjectAnchorCtrl.dispose();
    _cameraCtrl.dispose();
    _scaleCtrl.dispose();
    _inputContractCtrl.dispose();
    _assetPolicyCtrl.dispose();
    _pillarsCtrl.dispose();
    _tradeoffsCtrl.dispose();
    _cutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final spec = widget.spec;
    final isDark = wb.isDark;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final changed = wb.lastStage1ChangedSections;

    final Widget setupColumn = KeyedSubtree(
      key: const ValueKey('brief_col_setup'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlainColumnLabel(label: 'GAME & ENGINE SETUP', isDark: isDark),
          // §01 Pitch & Core Loop
          Stage1SectionCard(
          isDark: isDark,
          code: '01',
          title: 'Pitch & Core Loop',
          isUpdated: changed.contains('s01'),
          trailing: _editingPitch
              ? null
              : PlainTextLink(
                  key: const ValueKey('stage1_edit_pitch_btn'),
                  label: 'Edit',
                  isDark: isDark,
                  fontSize: 11.5,
                  color: textMuted,
                  onTap: wb.isAgentBusy
                      ? null
                      : () {
                          _pitchController.text = spec.pitch;
                          _lastSyncedPitch = spec.pitch;
                          setState(() => _editingPitch = true);
                        },
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editingPitch) ...[
                TextField(
                  key: const ValueKey('stage1_pitch_input'),
                  controller: _pitchController,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 2,
                  style: TextStyle(fontSize: 14, color: textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Enter BLUF pitch ([Payoff] — [Scope])...',
                    hintStyle: TextStyle(fontSize: 13, color: textMuted),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: border),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: focal),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PlainTextLink(
                      key: const ValueKey('stage1_pitch_cancel_btn'),
                      label: 'Cancel',
                      isDark: isDark,
                      color: textMuted,
                      onTap: () => setState(() => _editingPitch = false),
                    ),
                    const SizedBox(width: 12),
                    PlainPrimaryButton(
                      key: const ValueKey('stage1_pitch_save_btn'),
                      label: 'Save Pitch',
                      isDark: isDark,
                      onPressed: () {
                        wb.updateRootSpecSections(pitch: _pitchController.text);
                        setState(() => _editingPitch = false);
                      },
                    ),
                  ],
                ),
              ] else ...[
                PlainEditableLineField(
                  fieldKey: const ValueKey('stage1_pitch_inline_field'),
                  value: spec.pitch,
                  isDark: isDark,
                  multiLine: true,
                  minLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                    color: textPrimary,
                  ),
                  onCommit: (val) => wb.updateRootSpecSections(pitch: val),
                ),
              ],
              if (spec.coreLoop.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'CORE LOOP',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                for (int i = 0; i < spec.coreLoop.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${i + 1}.',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            spec.coreLoop[i],
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),

        // §02 UE5 Setup & Contracts
        Stage1SectionCard(
          isDark: isDark,
          code: '02',
          title: 'UE5 Setup (${spec.architectureMode.pillLabel})',
          isUpdated: changed.contains('s02'),
          trailing: _editingContracts
              ? null
              : PlainTextLink(
                  key: const ValueKey('stage1_edit_contracts_btn'),
                  label: 'Edit',
                  isDark: isDark,
                  fontSize: 11.5,
                  color: textMuted,
                  onTap: wb.isAgentBusy
                      ? null
                      : () {
                          _ueProjectAnchorCtrl.text = spec.ueProjectAnchor;
                          _cameraCtrl.text = spec.cameraContract;
                          _scaleCtrl.text = spec.characterScale;
                          _inputContractCtrl.text = spec.inputContract;
                          _assetPolicyCtrl.text = spec.assetPolicy;
                          _lastSyncedUeAnchor = spec.ueProjectAnchor;
                          _lastSyncedCamera = spec.cameraContract;
                          _lastSyncedScale = spec.characterScale;
                          _lastSyncedInputContract = spec.inputContract;
                          _lastSyncedAssetPolicy = spec.assetPolicy;
                          setState(() => _editingContracts = true);
                        },
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'UE5 VERSION',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  for (final ver in ProjectConceptBlueprint.ueVersionOptions)
                    InkWell(
                      key: ValueKey('ue_version_opt_${ver.replaceAll(' ', '_')}'),
                      onTap: wb.isAgentBusy
                          ? null
                          : () => wb.updateRootSpecSections(ueVersion: ver),
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: spec.ueVersion == ver ? focal : border,
                              width: spec.ueVersion == ver ? 2 : 1,
                            ),
                          ),
                        ),
                        child: Text(
                          spec.ueVersion == ver ? '✓ $ver' : ver,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: spec.ueVersion == ver
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: spec.ueVersion == ver
                                ? textPrimary
                                : textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (spec.effectiveCameraDecisionOptions.isNotEmpty) ...[
                Text(
                  'CAMERA FORK',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (final opt in spec.effectiveCameraDecisionOptions)
                      InkWell(
                        key: ValueKey('camera_opt_${opt.id}'),
                        onTap: wb.isAgentBusy
                            ? null
                            : () => wb.selectCameraDecisionOption(opt.id),
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: spec.cameraChoiceId == opt.id
                                    ? focal
                                    : border,
                                width: spec.cameraChoiceId == opt.id ? 2 : 1,
                              ),
                            ),
                          ),
                          child: Text(
                            spec.cameraChoiceId == opt.id
                                ? '✓ ${opt.label}'
                                : opt.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: spec.cameraChoiceId == opt.id
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: spec.cameraChoiceId == opt.id
                                  ? textPrimary
                                  : textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (_editingContracts) ...[
                Stage1ContractEditField(
                  fieldKey: const ValueKey('stage1_project_anchor_input'),
                  label: 'Project Base',
                  hintText:
                      'e.g. Module: MyGame · Extends BP_ThirdPersonCharacter (or Blank)',
                  controller: _ueProjectAnchorCtrl,
                  border: border,
                  focal: focal,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
                Stage1ContractEditField(
                  fieldKey: const ValueKey('stage1_camera_input'),
                  label: 'Camera',
                  controller: _cameraCtrl,
                  border: border,
                  focal: focal,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
                Stage1ContractEditField(
                  fieldKey: const ValueKey('stage1_scale_input'),
                  label: 'World Scale',
                  controller: _scaleCtrl,
                  border: border,
                  focal: focal,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
                Stage1ContractEditField(
                  fieldKey: const ValueKey('stage1_input_contract_input'),
                  label: 'Inputs',
                  controller: _inputContractCtrl,
                  border: border,
                  focal: focal,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
                Stage1ContractEditField(
                  fieldKey: const ValueKey('stage1_asset_policy_input'),
                  label: 'Assets',
                  controller: _assetPolicyCtrl,
                  border: border,
                  focal: focal,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PlainTextLink(
                      label: 'Cancel',
                      isDark: isDark,
                      color: textMuted,
                      onTap: () => setState(() => _editingContracts = false),
                    ),
                    const SizedBox(width: 12),
                    PlainPrimaryButton(
                      key: const ValueKey('stage1_contracts_save_btn'),
                      label: 'Save Setup',
                      isDark: isDark,
                      onPressed: () {
                        wb.updateRootSpecSections(
                          ueProjectAnchor: _ueProjectAnchorCtrl.text,
                          cameraContract: _cameraCtrl.text,
                          characterScale: _scaleCtrl.text,
                          inputContract: _inputContractCtrl.text,
                          assetPolicy: _assetPolicyCtrl.text,
                        );
                        setState(() => _editingContracts = false);
                      },
                    ),
                  ],
                ),
              ] else ...[
                Stage1ContractRow(
                  label: 'UE5 Project',
                  value: spec.ueProjectAnchor.trim().isEmpty
                      ? spec.ueVersion
                      : '${spec.ueVersion} · ${spec.ueProjectAnchor.trim()}',
                  isDark: isDark,
                ),
                Stage1ContractRow(
                  label: 'Camera',
                  value: spec.cameraContract,
                  isDark: isDark,
                ),
                Stage1ContractRow(
                  label: 'World Scale',
                  value: spec.characterScale,
                  isDark: isDark,
                ),
                Stage1ContractRow(
                  label: 'Inputs',
                  value: spec.inputContract,
                  isDark: isDark,
                ),
                Stage1ContractRow(
                  label: 'Architecture',
                  value: spec.assetPolicy,
                  isDark: isDark,
                  isLast: true,
                ),
              ],
            ],
          ),
        ),
        ],
      ),
    );

    final Widget planColumn = KeyedSubtree(
      key: const ValueKey('brief_col_plan'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlainColumnLabel(label: 'DIRECTION & v0.1 PLAN', isDark: isDark),
          // §03 Pillars, Feel & Trade-Offs
          Stage1SectionCard(
          isDark: isDark,
          code: '03',
          title: 'Pillars & Trade-Offs',
          isUpdated: changed.contains('s03'),
          trailing: _editingPillars
              ? null
              : PlainTextLink(
                  key: const ValueKey('stage1_edit_pillars_btn'),
                  label: 'Edit',
                  isDark: isDark,
                  fontSize: 11.5,
                  color: textMuted,
                  onTap: wb.isAgentBusy
                      ? null
                      : () {
                          final pillarsText = spec.pillars.join('\n');
                          final tradeoffsText = _formatTradeOffs(spec.tradeOffs);
                          _pillarsCtrl.text = pillarsText;
                          _tradeoffsCtrl.text = tradeoffsText;
                          _lastSyncedPillars = pillarsText;
                          _lastSyncedTradeoffs = tradeoffsText;
                          setState(() {
                            _tradeoffsError = null;
                            _editingPillars = true;
                          });
                        },
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ProjectConceptBlueprint.coreFeelOptions.isNotEmpty) ...[
                Text(
                  'CORE FEEL',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (final opt in ProjectConceptBlueprint.coreFeelOptions)
                      InkWell(
                        key: ValueKey('feel_opt_${opt.id}'),
                        onTap: wb.isAgentBusy
                            ? null
                            : () => wb.selectCoreFeelOption(opt.id),
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: spec.feelChoiceId == opt.id
                                    ? focal
                                    : border,
                                width: spec.feelChoiceId == opt.id ? 2 : 1,
                              ),
                            ),
                          ),
                          child: Text(
                            spec.feelChoiceId == opt.id
                                ? '✓ ${opt.label}'
                                : opt.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: spec.feelChoiceId == opt.id
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: spec.feelChoiceId == opt.id
                                  ? textPrimary
                                  : textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (_editingPillars) ...[
                Text(
                  'Design Pillars (one per line)',
                  style: TextStyle(fontSize: 12, color: textMuted),
                ),
                const SizedBox(height: 4),
                TextField(
                  key: const ValueKey('stage1_pillars_input'),
                  controller: _pillarsCtrl,
                  maxLines: 4,
                  minLines: 2,
                  style: TextStyle(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: border),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: focal),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Trade-Offs (<Prefer> OVER <Avoid>)',
                  style: TextStyle(fontSize: 12, color: textMuted),
                ),
                const SizedBox(height: 4),
                TextField(
                  key: const ValueKey('stage1_tradeoffs_input'),
                  controller: _tradeoffsCtrl,
                  maxLines: 3,
                  minLines: 2,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12.5,
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
                ),
                if (_tradeoffsError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _tradeoffsError!,
                    key: const ValueKey('stage1_tradeoffs_error'),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.accentRedFor(isDark),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PlainTextLink(
                      label: 'Cancel',
                      isDark: isDark,
                      color: textMuted,
                      onTap: () => setState(() {
                        _editingPillars = false;
                        _tradeoffsError = null;
                      }),
                    ),
                    const SizedBox(width: 12),
                    PlainPrimaryButton(
                      key: const ValueKey('stage1_pillars_save_btn'),
                      label: 'Save Pillars',
                      isDark: isDark,
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
                          final rules = _parseTradeOffLines(_tradeoffsCtrl.text);
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
                    ),
                  ],
                ),
              ] else ...[
                for (final p in spec.pillars)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '— $p',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: textPrimary,
                      ),
                    ),
                  ),
                if (spec.tradeOffs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final t in spec.tradeOffs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${t.prefer} OVER ${t.avoid}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),

        // §04 Out of Scope Cuts
        Stage1SectionCard(
          isDark: isDark,
          code: '04',
          title: 'Out of Scope (Cuts)',
          isUpdated: changed.contains('s04'),
          trailing: _addingCut
              ? null
              : PlainTextLink(
                  key: const ValueKey('stage1_cut_add_btn'),
                  label: '+ Add cut',
                  isDark: isDark,
                  fontSize: 11.5,
                  color: focal,
                  onTap: wb.isAgentBusy
                      ? null
                      : () {
                          _cutController.clear();
                          setState(() => _addingCut = true);
                        },
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < spec.outOfScope.length; i++)
                PlainHoverRemoveRow(
                  isDark: isDark,
                  showBottomBorder: i < spec.outOfScope.length - 1,
                  removeKey: ValueKey('stage1_cut_remove_$i'),
                  removeTooltip: 'Remove cut',
                  onRemove: wb.isAgentBusy
                      ? null
                      : () => wb.removeStage1OutOfScopeCut(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      spec.outOfScope[i],
                      style: TextStyle(fontSize: 13, color: textSecondary),
                    ),
                  ),
                ),
              if (_addingCut) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('stage1_cut_add_input'),
                        controller: _cutController,
                        autofocus: true,
                        style: TextStyle(fontSize: 13, color: textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'No [system to exclude from v0.1]...',
                          hintStyle: TextStyle(fontSize: 12.5, color: textMuted),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: focal),
                          ),
                        ),
                        onSubmitted: (val) {
                          wb.addStage1OutOfScopeCut(val);
                          _cutController.clear();
                          setState(() => _addingCut = false);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    PlainPrimaryButton(
                      key: const ValueKey('stage1_cut_add_save_btn'),
                      label: 'Add',
                      isDark: isDark,
                      onPressed: () {
                        wb.addStage1OutOfScopeCut(_cutController.text);
                        _cutController.clear();
                        setState(() => _addingCut = false);
                      },
                    ),
                    const SizedBox(width: 6),
                    PlainTextLink(
                      key: const ValueKey('stage1_cut_add_cancel_btn'),
                      label: 'Cancel',
                      isDark: isDark,
                      color: textMuted,
                      onTap: () => setState(() => _addingCut = false),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // §05 Initial v0.1 Scope Preview
        Stage1EpicPreviewSection(
          workbench: wb,
          spec: spec,
          activeProjectId: widget.activeProjectId,
          isUpdated: changed.contains('s05'),
        ),
        ],
      ),
    );

    return PlainTwoColumnLayout(
      left: setupColumn,
      right: planColumn,
    );
  }
}
