import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import '../utils/section_text_utils.dart';

part 'workbench_engine_areas_card.dart';
part 'workbench_modals_part.dart';
part 'workbench_task_and_playtest_modals_part.dart';
part 'workbench_outliner_and_shell_part.dart';
part 'workbench_checkpoint_workspace_part.dart';

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
  static final RegExp _leadingBracketTagRegex = RegExp(r'^\[[^\]]+\]\s*');
  static String? _cachedSpecTokenKey;
  static Map<String, String> _cachedBaseTokens = const {};
  static RegExp? _cachedBaseTokenRegex;

  final Set<String> _awaitingPlaytestVerification = {};
  int? _manualCheckpointFocusIndex;
  final Map<String, int> _selectedTaskIndexByCheckpoint = {};
  final Map<String, int> _selectedSubStepIndexByTask = {};
  bool _unrealCppMode = false;
  double _outlinerWidth = 232.0;
  bool _isHalfScreenOutlinerOpen = false;
  bool _isProgressiveModalOpen = false;
  String? _inlineEditingTuningNodeId;
  final TextEditingController _inlineTuningEditController =
      TextEditingController();

  @override
  void dispose() {
    _inlineTuningEditController.dispose();
    super.dispose();
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

  static final RegExp _nonDigitRegex = RegExp(r'[^0-9]');

  @override
  bool get isDark => widget.workbench.isDark;

  void _rebuild([VoidCallback? fn]) => setState(fn ?? () {});

  Color get bgSurfaceHover =>
      isDark ? const Color(0xFF181D28) : const Color(0xFFF1F5F9);

  @override
  Widget build(BuildContext context) {
    final rel = widget.workbench.activeRelease;
    if (rel == null) {
      return Center(
        child: Text(
          'No active Release loaded.',
          style: GoogleFonts.inter(color: textMuted),
        ),
      );
    }

    if (widget.workbench.isAgentBusy && !_isProgressiveModalOpen) {
      return _buildAgentExecutionProgress(rel);
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
                                  .clamp(220.0, 520.0);
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
                child: _buildFeatureMainCanvas(
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
              child: _buildFeatureMainCanvas(
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
                      color: accentAmber,
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
                        color: accentCyan,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.workbench.agentProgressStep!,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accentCyan,
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
                      Icon(Icons.check_circle, size: 14, color: accentEmerald),
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

  String? get _engineHint =>
      widget.workbench.conceptDraft?.techSpec.join(' ') ??
      widget.workbench.activeProject?.sections['tech_spec'];

  int _computeCheckpointRemainingMinutes(FeatureStateNode cpNode) {
    final hint = _engineHint;
    int rem = 0;
    for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
      final bp = TaskHowToBlueprint.resolve(
        parentTask: cpNode.checklist[tIdx],
        taskIndex: tIdx,
        checkpointNode: cpNode,
        engineHint: hint,
        unrealCppMode: _unrealCppMode,
      );
      rem += bp.remainingTaskMinutes;
    }
    return rem;
  }

  int _computeFeatureRemainingMinutes(TierDocument feat) {
    if (feat.sections['lifecycle'] == FeatureLifecycleStatus.stable.name) {
      return 0;
    }
    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isEmpty) return 0;
    final activeVer = widget.workbench.activeReleaseVersionTag;
    final activeStates =
        states.where((s) => s.releaseVersion == activeVer).toList();
    final effectiveStates = activeStates.isNotEmpty ? activeStates : states;
    int rem = 0;
    for (final cp in effectiveStates) {
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
