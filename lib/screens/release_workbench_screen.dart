import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import '../utils/section_text_utils.dart';
import 'project_pitch_screen.dart';

part 'workbench_engine_areas_card.dart';
part 'workbench_modals_part.dart';
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
    r'\b(?:BP_[A-Za-z0-9_]+|A[A-Z][A-Za-z0-9_]+Actor|[A-Za-z0-9_]+\.(?:uasset|tscn|gd|cs|h|cpp)|InteractBox|VisualMesh|DefaultSceneRoot|InteractTrigger|HitBox|CollisionShape2D|BoxCollider)\b',
  );
  static final RegExp _treeChildRegex = RegExp(
    r'[├└]─\s*([A-Za-z0-9_]+)\s*(?:\(([^)]+)\))?',
  );
  static final RegExp _tuningVarDelimiterRegex = RegExp(r'[:=]');
  static String? _cachedSpecTokenKey;
  static Map<String, String> _cachedBaseTokens = const {};
  static RegExp? _cachedBaseTokenRegex;

  final Set<String> _awaitingPlaytestVerification = {};
  int? _manualCheckpointFocusIndex;
  String? _manualCheckpointFocusFeatureId;
  final Map<String, int> _selectedTaskIndexByCheckpoint = {};
  final Map<String, int> _selectedSubStepIndexByTask = {};
  bool _unrealCppMode = false;
  double _outlinerWidth = 360.0;
  final int _engineAreaFilter = 0;
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
  final TextEditingController _inboxCaptureCtrl = TextEditingController();
  String? _inlineBugDrawerNodeId;
  final TextEditingController _inlineBugInputCtrl = TextEditingController();
  String _outlinerSearchQuery = '';
  bool _isOutlinerSearchOpen = false;
  final TextEditingController _outlinerSearchController =
      TextEditingController();

  @override
  void dispose() {
    _progressiveDirectiveCtrl.dispose();
    _progressiveNewFeatCtrl.dispose();
    _stage2InlineEditController.dispose();
    _inboxCaptureCtrl.dispose();
    _inlineBugInputCtrl.dispose();
    _outlinerSearchController.dispose();
    super.dispose();
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
        _selectedTaskIndexByCheckpoint[cpNode.id] = newIdx;
        _selectedSubStepIndexByTask['${cpNode.id}_$newIdx'] = 0;
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
          '🐞 Log Playtest Issue',
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
                'Describe the viewport bug or feel issue to append a 3-step [FIX] task and [PLAYTEST GUARD]:',
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
          _selectedTaskIndexByCheckpoint[cpNode.id] = newIdx;
          _selectedSubStepIndexByTask['${cpNode.id}_$newIdx'] = 0;
        });
      }
    }
  }

  Color get bgSurfaceHover =>
      isDark ? const Color(0xFF181D28) : const Color(0xFFF1F5F9);

  Widget _buildHalfScreenDrawerTriggerBar(String viewLabel) {
    final isHud = widget.workbench.isCompanionHudMode;
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
              isHud ? '◨ Companion HUD · $viewLabel' : viewLabel,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isHud ? FontWeight.w700 : FontWeight.w500,
                color: isHud ? textPrimary : textMuted,
              ),
            ),
          ),
          if (isHud) ...[
            const SizedBox(width: 8),
            Builder(
              builder: (context) {
                final feat = widget.workbench.selectedFeature;
                final states = feat != null ? FeatureStateNode.getStatesForDocument(feat) : <FeatureStateNode>[];
                final cpIdx = _manualCheckpointFocusIndex ??
                    (states.isNotEmpty ? states.indexWhere((s) => !s.isCompleted) : -1);
                final safeCpIdx = cpIdx >= 0 && cpIdx < states.length ? cpIdx : (states.isNotEmpty ? 0 : -1);
                final cpNode = safeCpIdx >= 0 ? states[safeCpIdx] : null;

                if (feat == null || cpNode == null) return const SizedBox.shrink();

                return InkWell(
                  key: const ValueKey('companion_hud_log_bug_btn'),
                  onTap: () => _showLogPlaytestIssueDialog(
                    feat,
                    states,
                    safeCpIdx,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFFFBBF24).withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🐞', style: TextStyle(fontSize: 10)),
                        const SizedBox(width: 4),
                        Text(
                          'Log Bug',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFBBF24),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            InkWell(
              key: const ValueKey('exit_companion_hud_btn'),
              onTap: () => widget.workbench.toggleCompanionHudMode(false),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderBright),
                ),
                child: Text(
                  '✕ Exit HUD',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
            ),
          ],
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

    // Companion HUD Mode: Full focus on active Step Runbook (centered 440px cockpit)
    if (widget.workbench.isCompanionHudMode) {
      return Container(
        color: bgBase,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _buildActiveMainCanvas(
              context,
              rel,
              isHalfScreenOverlayMode: true,
            ),
          ),
        ),
      );
    }

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
        final overlayWidth =
            _outlinerWidth.clamp(220.0, constraints.maxWidth * 0.85);
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
    int rem = 0;
    for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
      final bp = TaskHowToBlueprint.resolve(
        parentTask: cpNode.checklist[tIdx],
        taskIndex: tIdx,
        checkpointNode: cpNode,
        engineHint: hint,
        unrealCppMode: _unrealCppMode,
        phase: phase,
      );
      rem += bp.remainingTaskMinutes;
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
