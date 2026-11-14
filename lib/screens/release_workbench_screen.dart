import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/godot_virtual_file.dart';
import '../models/tier_document.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import '../utils/godot_gdscript_guard.dart';
import '../utils/section_text_utils.dart';
import 'project_pitch_screen.dart';
import 'widgets/godot_inspector_panel.dart';
import 'widgets/godot_workbench_modals.dart';

part 'workbench_engine_areas_card.dart';
part 'workbench_modals_part.dart';
part 'workbench_progressive_planner_part.dart';
part 'workbench_task_and_playtest_modals_part.dart';
part 'workbench_outliner_and_shell_part.dart';
part 'workbench_checkpoint_workspace_part.dart';
part 'workbench_full_production_blueprint_part.dart';

/// Stage 2 Screen: Streamlined 2-Surface Open-Canvas Release Workbench
/// - Left Outliner Rail (`#0C0E12`): Core Loop Epics (`E01`, `E02`, ...) & Singular-Focused Features
/// - Right Open Workspace (`#12151B`):
///   - Full-Width: Fixed-Order Step List (`STEPS (X/Y)`) on the left + Active Step (`Do -> Copy -> Verify`) on the right
///   - Half-Width: 1-Line Floating Context Bar (`E01 · Epic › Feature ▾` + `Step X/Y ▾ | ‹ ›`) + Active Step
class ReleaseWorkbenchScreen extends StatefulWidget {
  final WorkbenchProvider workbench;

  const ReleaseWorkbenchScreen({
    super.key,
    required this.workbench,
  });

  @override
  State<ReleaseWorkbenchScreen> createState() => _ReleaseWorkbenchScreenState();
}

class _ReleaseWorkbenchScreenState extends State<ReleaseWorkbenchScreen>
    with WorkbenchThemeMixin {
  static final RegExp _assetTokenRegex = RegExp(
    r'\b(?:res://[A-Za-z0-9_./-]+\.(?:tscn|gd|tres)|[A-Za-z0-9_]+\.(?:tscn|gd|tres|h|cpp)|CharacterBody[23]D|RigidBody[23]D|StaticBody[23]D|CollisionShape[23]D|Area[23]D|Camera[23]D|Marker[23]D|MeshInstance3D|Sprite2D|CanvasLayer|Control|Timer|RayCast[23]D)\b',
  );
  static final RegExp _tuningVarDelimiterRegex = RegExp(r'[:=]');
  static String? _cachedSpecTokenKey;
  static Map<String, String> _cachedBaseTokens = const {};
  static RegExp? _cachedBaseTokenRegex;

  final Set<String> _awaitingPlaytestVerification = {};
  int? _manualCheckpointFocusIndex;
  String? _manualCheckpointFocusFeatureId;
  final Map<String, int> _selectedFlatStepIndexByCheckpoint = {};
  final Set<String> _playtestGateActiveCheckpoints = {};
  Set<String> _hoveredDoTokens = const {};
  String? _hoveredDoRowKey;
  double _outlinerWidth = 320.0;

  int _resolveFlatStepIndex(
    FeatureStateNode cpNode,
    List<TaskHowToSubStep> unifiedSteps,
  ) {
    if (unifiedSteps.isEmpty) return 0;
    final explicit = _selectedFlatStepIndexByCheckpoint[cpNode.id];
    if (explicit != null && explicit >= 0 && explicit < unifiedSteps.length) {
      return explicit;
    }
    final firstIncomplete =
        unifiedSteps.indexWhere((s) => !s.subtask.completed);
    return firstIncomplete != -1 ? firstIncomplete : 0;
  }

  bool _isPlaytestGateSelected(
    FeatureStateNode cpNode,
    List<TaskHowToSubStep> unifiedSteps,
  ) {
    if (_playtestGateActiveCheckpoints.contains(cpNode.id)) return true;
    final allBuildDone =
        unifiedSteps.isNotEmpty && unifiedSteps.every((s) => s.subtask.completed);
    return allBuildDone && !_selectedFlatStepIndexByCheckpoint.containsKey(cpNode.id);
  }

  void _selectFlatStep(String checkpointId, int stepIndex) {
    _rebuild(() {
      _playtestGateActiveCheckpoints.remove(checkpointId);
      _selectedFlatStepIndexByCheckpoint[checkpointId] = stepIndex;
    });
  }

  void _openPlaytestGate(String checkpointId) {
    _rebuild(() {
      _playtestGateActiveCheckpoints.add(checkpointId);
    });
  }
  final Set<String> _collapsedBeatIds = {};
  String? _accordionInitReleaseId;
  String? _lastSyncedAccordionFeatureId;
  bool _isHalfScreenOutlinerOpen = false;
  bool _isProgressiveModalOpen = false;
  bool _showProgressiveStableFeaturesDrawer = false;
  String? _progressivePrevReleaseId;
  ProductionPhase? _progressivePrevPhase;
  ProductionPhase? _pendingPhaseGraduationOverride;
  int _selectedProgressiveTrackIndex = 0;
  String? _addingFeatureToBeatId;
  final TextEditingController _progressiveDirectiveCtrl =
      TextEditingController();
  final TextEditingController _progressiveNewFeatCtrl =
      TextEditingController();
  String? _activeStage2InlineEditKey;
  final TextEditingController _stage2InlineEditController =
      TextEditingController();
  GodotDockStage _inlineAddStepStage = GodotDockStage.code;
  final Map<String, String> _customComponentPropertyOverrides = {};
  final TextEditingController _inboxCaptureCtrl = TextEditingController();
  String? _inlineBugDrawerNodeId;
  final TextEditingController _inlineBugInputCtrl = TextEditingController();
  String _outlinerSearchQuery = '';
  bool _isOutlinerSearchOpen = false;
  bool _filterOutlinerTodoOnly = false;
  final TextEditingController _outlinerSearchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleWorkbenchKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleWorkbenchKeyEvent);
    _progressiveDirectiveCtrl.dispose();
    _progressiveNewFeatCtrl.dispose();
    _stage2InlineEditController.dispose();
    _inboxCaptureCtrl.dispose();
    _inlineBugInputCtrl.dispose();
    _outlinerSearchController.dispose();
    super.dispose();
  }

  bool _isEditableTextFocused() {
    final focusCtx = FocusManager.instance.primaryFocus?.context;
    if (focusCtx == null) return false;
    if (focusCtx.widget is EditableText) return true;
    return focusCtx.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _handleWorkbenchKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (!HardwareKeyboard.instance.isAltPressed) return false;
    if (_isEditableTextFocused()) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (_isProgressiveModalOpen ||
        widget.workbench.currentStage != WorkbenchStage.releaseWorkbench) {
      return false;
    }

    final key = event.logicalKey;
    final ctx = _resolveActiveWorkspaceContext();
    if (ctx == null) return false;

    if (key == LogicalKeyboardKey.arrowUp) {
      _retreatToPreviousStep(
        ctx.states,
        ctx.cpIndex,
        ctx.node,
        ctx.unifiedSteps,
        ctx.activeStepIdx,
        ctx.isPlaytestGate,
      );
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _browseToNextStep(
        ctx.states,
        ctx.cpIndex,
        ctx.node,
        ctx.unifiedSteps,
        ctx.activeStepIdx,
        ctx.isPlaytestGate,
      );
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _triggerPrimaryDoneAction(
        feat: ctx.feat,
        states: ctx.states,
        node: ctx.node,
        unifiedSteps: ctx.unifiedSteps,
        activeStepIdx: ctx.activeStepIdx,
        isPlaytestGate: ctx.isPlaytestGate,
      );
      return true;
    }
    return false;
  }

  int _resolveActiveCheckpointIndex(
    TierDocument feat,
    List<FeatureStateNode> states,
  ) {
    if (states.isEmpty) return 0;
    if (_manualCheckpointFocusFeatureId == feat.id &&
        _manualCheckpointFocusIndex != null &&
        _manualCheckpointFocusIndex! >= 0 &&
        _manualCheckpointFocusIndex! < states.length) {
      return _manualCheckpointFocusIndex!;
    }
    final activeVer = widget.workbench.activeReleaseVersionTag;
    for (int i = 0; i < states.length; i++) {
      final s = states[i];
      if (s.releaseVersion != activeVer) continue;
      final awaitingPlaytest = _awaitingPlaytestVerification.contains(s.id);
      if (!s.isCompleted || awaitingPlaytest) {
        return i;
      }
    }
    final lastActiveVerIdx =
        states.lastIndexWhere((s) => s.releaseVersion == activeVer);
    if (lastActiveVerIdx != -1) return lastActiveVerIdx;
    for (int i = 0; i < states.length; i++) {
      final s = states[i];
      if (!s.isCompleted || _awaitingPlaytestVerification.contains(s.id)) {
        return i;
      }
    }
    return states.length - 1;
  }

  ({
    TierDocument feat,
    List<FeatureStateNode> states,
    int cpIndex,
    FeatureStateNode node,
    List<TaskHowToSubStep> unifiedSteps,
    int activeStepIdx,
    bool isPlaytestGate,
  })? _resolveActiveWorkspaceContext() {
    final feat = widget.workbench.selectedFeature;
    if (feat == null) return null;
    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isEmpty) return null;
    final cpIndex = _resolveActiveCheckpointIndex(feat, states);
    final node = states[cpIndex];
    final unifiedSteps = TaskHowToBlueprint.resolveUnifiedSteps(
      checkpointNode: node,
      engineHint: _engineHint,
      phase: widget.workbench.currentPhase,
    );
    final activeStepIdx = _resolveFlatStepIndex(node, unifiedSteps);
    final isPlaytestGate = _isPlaytestGateSelected(node, unifiedSteps);
    return (
      feat: feat,
      states: states,
      cpIndex: cpIndex,
      node: node,
      unifiedSteps: unifiedSteps,
      activeStepIdx: activeStepIdx,
      isPlaytestGate: isPlaytestGate,
    );
  }

  bool _featureMatchesOutlinerSearch(TierDocument feat, String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (feat.title.toLowerCase().contains(q)) return true;
    final pAsset = (feat.sections['primary_asset'] ?? '').toLowerCase();
    if (pAsset.contains(q)) return true;
    final states = FeatureStateNode.getStatesForDocument(feat);
    for (final s in states) {
      final cpAsset =
          (s.parameters['primarySharedScriptOrScene'] ?? '').toLowerCase();
      if (cpAsset.contains(q)) return true;
      if (s.tuningParams.any((tp) => tp.toLowerCase().contains(q))) return true;
      if (s.edgeCases.any((ec) => ec.toLowerCase().contains(q))) return true;
    }
    return false;
  }

  String _formatOutlineBeatDisplayTitle(String rawBeatTitle) {
    return MechanicArchetypeProfile.concreteBeatDisplayTitle(rawBeatTitle);
  }

  String _formatOutlineFeatureDisplayTitle(
    String featTitle,
    String? beatTitle, {
    int beatIndex = 0,
  }) {
    return MechanicArchetypeProfile.concreteFeatureTitleForBeat(
      featTitle,
      beatTitle: beatTitle,
      beatIndex: beatIndex,
    );
  }

  @override
  bool get isDark => widget.workbench.isDark;

  void _rebuild([VoidCallback? fn]) => setState(fn ?? () {});

  void _submitInlinePlaytestBug(
    TierDocument feat,
    List<FeatureStateNode> states,
    int checkpointIndex,
    FeatureStateNode node, [
    String? customDesc,
  ]) {
    final desc = (customDesc ?? _inlineBugInputCtrl.text).trim();
    if (desc.isEmpty) return;
    final newIdx = widget.workbench.logPlaytestIssueOnCheckpoint(
      featureId: feat.id,
      states: states,
      checkpointIndex: checkpointIndex,
      issueDescription: desc,
    );
    _rebuild(() {
      _inlineBugDrawerNodeId = null;
      _inlineBugInputCtrl.clear();
      if (newIdx >= 0 && checkpointIndex < states.length) {
        final cpNode = states[checkpointIndex];
        _manualCheckpointFocusIndex = checkpointIndex;
        _playtestGateActiveCheckpoints.remove(cpNode.id);
        _selectedFlatStepIndexByCheckpoint[cpNode.id] = newIdx;
      }
    });
  }

  Future<void> _showLogPlaytestIssueDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    int checkpointIndex,
  ) async {
    final ctrl = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Log Playtest Issue',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Describe the viewport bug or feel issue to append a [FIX] step and [PLAYTEST GUARD]:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('workbench_log_playtest_issue_input'),
                controller: ctrl,
                autofocus: true,
                style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g., Dash clips through thin arena walls on diagonal input',
                  hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                  filled: true,
                  fillColor: bgRecessed,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_workbench_log_playtest_issue_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor:
                  isDark ? const Color(0xFF06281E) : Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(
              '+ Add [FIX] Task & Guard',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      final newIdx = widget.workbench.logPlaytestIssueOnCheckpoint(
        featureId: feat.id,
        states: states,
        checkpointIndex: checkpointIndex,
        issueDescription: saved.trim(),
      );
      if (newIdx >= 0 && checkpointIndex < states.length) {
        final cpNode = states[checkpointIndex];
        _rebuild(() {
          _manualCheckpointFocusIndex = checkpointIndex;
          _playtestGateActiveCheckpoints.remove(cpNode.id);
          _selectedFlatStepIndexByCheckpoint[cpNode.id] = newIdx;
        });
      }
    }
  }

  Color get bgSurfaceHover =>
      isDark ? const Color(0xFF181D28) : const Color(0xFFF1F5F9);

  Widget _buildHalfScreenDrawerTriggerBar(String viewLabel) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: bgRecessed,
        border: Border(
          bottom: BorderSide(color: borderSubtle),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            key: const ValueKey('halfscreen_outliner_global_trigger'),
            borderRadius: BorderRadius.circular(5),
            onTap: () {
              setState(() {
                _isHalfScreenOutlinerOpen = true;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                '☰',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              viewLabel,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveMainCanvas(
    BuildContext context,
    TierDocument? rel, {
    required bool isHalfScreenOverlayMode,
  }) {
    final isConceptView =
        widget.workbench.currentStage == WorkbenchStage.projectPitch ||
        rel == null ||
        (widget.workbench.activeReleaseBeats.isEmpty &&
            !widget.workbench.isAgentBusy);
    if (isConceptView) {
      final conceptScreen = ProjectPitchScreen(workbench: widget.workbench);
      if (!isHalfScreenOverlayMode) return conceptScreen;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHalfScreenDrawerTriggerBar('Concept Blueprint'),
          Expanded(child: conceptScreen),
        ],
      );
    }
    if (_isProgressiveModalOpen) {
      final progressiveCanvas = _buildProgressiveReleasePlannerCanvas(context);
      if (!isHalfScreenOverlayMode) return progressiveCanvas;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHalfScreenDrawerTriggerBar(
            'Next release · ${widget.workbench.nextProgressiveVersionLabel}',
          ),
          Expanded(child: progressiveCanvas),
        ],
      );
    }
    final featureCanvas = _buildFeatureMainCanvas(
      rel,
      isHalfScreenOverlayMode: isHalfScreenOverlayMode,
    );
    if (!isHalfScreenOverlayMode) return featureCanvas;
    final featTitle = widget.workbench.selectedFeature?.title ?? 'Active Step Runbook';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHalfScreenDrawerTriggerBar(featTitle),
        Expanded(child: featureCanvas),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.workbench.activeRelease;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isFullScreenDocked = constraints.maxWidth >= 1040;
        if (isFullScreenDocked) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _outlinerWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: _buildLeftBeatFeatureRail(rel),
                    ),
                    Positioned(
                      top: 0,
                      right: -3,
                      bottom: 0,
                      width: 6,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              _outlinerWidth = (_outlinerWidth + details.delta.dx)
                                  .clamp(260.0, 560.0);
                            });
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildActiveMainCanvas(
                  context,
                  rel,
                  isHalfScreenOverlayMode: false,
                ),
              ),
            ],
          );
        }

        // Half-Screen Mode (< 1040px): Main Canvas gets 100% width; Outliner becomes a Slide-Over Overlay Drawer
        final maxOverlayWidth = constraints.maxWidth * 0.85;
        final minOverlayWidth =
            maxOverlayWidth < 220.0 ? maxOverlayWidth : 220.0;
        final overlayWidth =
            _outlinerWidth.clamp(minOverlayWidth, maxOverlayWidth);
        return Stack(
          children: [
            Positioned.fill(
              child: _buildActiveMainCanvas(
                context,
                rel,
                isHalfScreenOverlayMode: true,
              ),
            ),
            if (_isHalfScreenOutlinerOpen)
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('halfscreen_outliner_scrim'),
                  onTap: () {
                    setState(() {
                      _isHalfScreenOutlinerOpen = false;
                    });
                  },
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.52),
                  ),
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 0,
              left: _isHalfScreenOutlinerOpen ? 0 : -(overlayWidth + 24),
              width: overlayWidth,
              child: Material(
                color: Colors.transparent,
                elevation: _isHalfScreenOutlinerOpen ? 20 : 0,
                child: _buildLeftBeatFeatureRail(
                  rel,
                  isOverlayDrawer: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAgentExecutionProgress(TierDocument rel) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderBright),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Building ${rel.title}...',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (widget.workbench.agentProgressStep != null &&
                  widget.workbench.agentProgressStep!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.workbench.agentProgressStep!,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final step in widget.workbench.executionLog)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 14, color: textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? get _engineHint {
    final draftTech =
        widget.workbench.conceptDraft?.techSpec.join(' ').trim() ?? '';
    if (draftTech.isNotEmpty) return draftTech;
    final projSec = widget.workbench.activeProject?.sections;
    return projSec?['tech_spec'] ?? projSec?['techSpec'];
  }

  int _computeCheckpointRemainingMinutes(FeatureStateNode cpNode) {
    final hint = _engineHint;
    final phase = widget.workbench.currentPhase;
    final steps = TaskHowToBlueprint.resolveUnifiedSteps(
      checkpointNode: cpNode,
      engineHint: hint,
      phase: phase,
    );
    int rem = 0;
    for (final s in steps) {
      if (!s.subtask.completed) rem += s.estimatedMinutes;
    }
    return rem;
  }

  int _computeFeatureRemainingMinutes(TierDocument feat) {
    if (!widget.workbench.isFeatureActiveInRelease(feat)) {
      return 0;
    }
    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isEmpty) return 0;
    final activeVer = widget.workbench.activeReleaseVersionTag;
    int rem = 0;
    bool foundActive = false;
    for (final cp in states) {
      if (cp.releaseVersion == activeVer) {
        rem += _computeCheckpointRemainingMinutes(cp);
        foundActive = true;
      }
    }
    if (foundActive) return rem;
    for (final cp in states) {
      rem += _computeCheckpointRemainingMinutes(cp);
    }
    return rem;
  }

  int _computeReleaseRemainingMinutes(List<TierDocument> beats) {
    int rem = 0;
    for (final beat in beats) {
      for (final feat in widget.workbench.featuresForBeat(beat.id)) {
        rem += _computeFeatureRemainingMinutes(feat);
      }
    }
    return rem;
  }

}
