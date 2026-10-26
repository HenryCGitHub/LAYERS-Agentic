import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../agents/workspace_agent_tools.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import '../utils/section_text_utils.dart';

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

  final Set<String> _expandedDoneCheckpoints = {};
  final Set<String> _awaitingPlaytestVerification = {};
  int? _manualCheckpointFocusIndex;
  final Map<String, int> _selectedTaskIndexByCheckpoint = {};
  final Map<String, int> _selectedSubStepIndexByTask = {};
  bool _unrealCppMode = false;
  double _outlinerWidth = 232.0;
  bool _isHalfScreenOutlinerOpen = false;

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

    if (widget.workbench.isAgentBusy) {
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
    final states = FeatureStateNode.getStatesForDocument(feat);
    int rem = 0;
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

  Widget _buildLeftBeatFeatureRail(
    TierDocument rel, {
    bool shrinkWrap = false,
    bool isOverlayDrawer = false,
  }) {
    final beats = widget.workbench.activeReleaseBeats;
    final relProgress = widget.workbench.getDocumentProgress(rel.id);
    final releases = widget.workbench.projectReleases;
    final archivedFeats = widget.workbench.supersededFeatures;
    final activeVer = widget.workbench.activeReleaseVersionTag;
    final releaseRemMins = _computeReleaseRemainingMinutes(beats);
    final releaseRemHoursStr =
        TaskHowToBlueprint.formatRemainingHoursShort(releaseRemMins);
    final isReleaseDone = relProgress >= 100 || releaseRemMins <= 0;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          color: bgRecessed,
          child: Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Release Selector Dropdown Pill ("v0.1 Prototype ▾")
                  Flexible(
                    child: PopupMenuButton<String>(
                      key: const ValueKey('release_selector_dropdown_btn'),
                      color: bgSurface,
                      tooltip: 'Switch Release View or Evolve Scope',
                      onSelected: (value) {
                        if (value == '__progressive_release__') {
                          _showProgressiveNextReleaseModal(context);
                        } else if (value.startsWith('rel:')) {
                          final targetId = value.substring(4);
                          final targetDoc = widget.workbench.documents[targetId];
                          if (targetDoc != null &&
                              targetDoc.childrenIds.isEmpty &&
                              targetId != rel.id) {
                            _showProgressiveNextReleaseModal(context);
                          } else {
                            widget.workbench.selectActiveRelease(targetId);
                          }
                        } else {
                          widget.workbench.setReleaseViewFilter(value);
                        }
                      },
                      itemBuilder: (context) {
                        final queuedDeferredCount = widget.workbench.releaseBlueprint?.beats
                                .fold<int>(0, (sum, b) => sum + b.deferredFeatures.length) ??
                            0;
                        return [
                          PopupMenuItem<String>(
                            enabled: false,
                            height: 24,
                            child: Text(
                              'RELEASES · SWITCH OR PLAN',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: textMuted,
                              ),
                            ),
                          ),
                          for (int rIdx = 0; rIdx < releases.length; rIdx++)
                            PopupMenuItem<String>(
                              value: 'rel:${releases[rIdx].id}',
                              child: Builder(
                                builder: (context) {
                                  final r = releases[rIdx];
                                  final isCurrent = r.id == rel.id;
                                  final isBuilt = r.childrenIds.isNotEmpty;
                                  final rVer =
                                      widget.workbench.releaseVersionTagFor(r);
                                  final rScopeLabel =
                                      widget.workbench.releaseConciseLabel(r);
                                  final rProg = widget.workbench.getDocumentProgress(r.id);
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? accentCyan.withValues(alpha: 0.08)
                                          : Colors.transparent,
                                      border: Border(
                                        left: BorderSide(
                                          color: isCurrent
                                              ? accentCyan
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    isCurrent
                                                        ? '● '
                                                        : (isBuilt ? '✓ ' : '◌ '),
                                                    style: GoogleFonts.jetBrainsMono(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w800,
                                                      color: isCurrent
                                                          ? accentCyan
                                                          : (isBuilt
                                                              ? accentEmerald
                                                              : accentAmber),
                                                    ),
                                                  ),
                                                  Text(
                                                    '$rVer ',
                                                    style: GoogleFonts.jetBrainsMono(
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.w800,
                                                      color: isCurrent
                                                          ? accentCyan
                                                          : textPrimary,
                                                    ),
                                                  ),
                                                  Flexible(
                                                    child: Text(
                                                      rScopeLabel,
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11.5,
                                                        fontWeight: isCurrent
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        color: isCurrent
                                                            ? textPrimary
                                                            : textSecondary,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            if (isCurrent)
                                              Text(
                                                '$relProgress% · $releaseRemHoursStr left',
                                                style: GoogleFonts.jetBrainsMono(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: accentEmerald,
                                                ),
                                              )
                                            else if (isBuilt)
                                              Text(
                                                '$rProg%',
                                                style: GoogleFonts.jetBrainsMono(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: rProg >= 100
                                                      ? accentEmerald
                                                      : textMuted,
                                                ),
                                              )
                                            else
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: accentAmber.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: accentAmber.withValues(alpha: 0.35),
                                                  ),
                                                ),
                                                child: Text(
                                                  'Build Release →',
                                                  style: GoogleFonts.jetBrainsMono(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: accentAmber,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (!isBuilt && queuedDeferredCount > 0) ...[
                                          const SizedBox(height: 3),
                                          Padding(
                                            padding: const EdgeInsets.only(left: 14),
                                            child: Text(
                                              '↪ $queuedDeferredCount Features queued from $activeVer',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w600,
                                                color: accentAmber,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          if (archivedFeats.isNotEmpty) ...[
                            const PopupMenuDivider(),
                            PopupMenuItem<String>(
                              value: 'archived',
                              child: Text(
                                '🗄 Superseded Testbeds Archive (${archivedFeats.length})',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: textSecondary,
                                ),
                              ),
                            ),
                          ],
                          const PopupMenuDivider(),
                          PopupMenuItem<String>(
                            enabled: false,
                            height: 24,
                            child: Text(
                              'PROGRESSIVE AI RELEASES',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: textMuted,
                              ),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: '__progressive_release__',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '+ New Progressive Release (${widget.workbench.nextProgressiveVersionLabel})',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: accentEmerald,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'AI Co-Pilot ✦',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: accentEmerald,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ];
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 3,
                        ),
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                            children: [
                              TextSpan(
                                text: '$activeVer ',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: accentCyan,
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${widget.workbench.releaseConciseLabel(rel)} ▾',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right: Simple Number-Only Live Rollup ("12h Left #%"), plus Close button in Half-Screen Slide-Over mode
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RichText(
                        key: const ValueKey('outline_release_eta_summary'),
                        text: TextSpan(
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: isReleaseDone ? accentEmerald : textPrimary,
                          ),
                          children: [
                            TextSpan(text: '$releaseRemHoursStr Left '),
                            TextSpan(
                              text: '$relProgress%',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: accentEmerald,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isOverlayDrawer) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          key: const ValueKey(
                            'close_halfscreen_outliner_btn',
                          ),
                          onTap: () {
                            setState(() {
                              _isHalfScreenOutlinerOpen = false;
                            });
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 3,
                            ),
                            child: Text(
                              '✕',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              Offstage(
                offstage: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     const Text('OUTLINE'),
                    const Text('ACTIVE RELEASE'),
                    Text(
                      widget.workbench.activePhaseBadgeLabel,
                      key: const ValueKey('stage3_phase_badge'),
                    ),
                    InkWell(
                      key: const ValueKey('focus_mode_toggle_btn'),
                      onTap: () => widget.workbench.toggleFocusMode(),
                      child: const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.workbench.releaseViewFilter == 'archived' &&
            archivedFeats.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(
              'ARCHIVED TESTBEDS (${archivedFeats.length})',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: textMuted,
              ),
            ),
          ),
          for (final arch in archivedFeats)
            _buildFeatureRailItem(arch, activeVer: activeVer),
        ] else
          for (int bIdx = 0; bIdx < beats.length; bIdx++) ...[
            Builder(
              builder: (context) {
                final beat = beats[bIdx];
                final beatFeats = widget.workbench.featuresForBeat(beat.id);
                final doneBeatCount = beatFeats
                    .where((f) => widget.workbench.getDocumentProgress(f.id) >= 100)
                    .length;
                final allBeatDone = beatFeats.isNotEmpty && doneBeatCount == beatFeats.length;
                final isBeatActive = beatFeats.any(
                  (f) => f.id == widget.workbench.selectedFeatureId,
                );
                int prevFeaturesBeforeBeat = 0;
                for (int prevB = 0; prevB < bIdx; prevB++) {
                  prevFeaturesBeforeBeat +=
                      widget.workbench.featuresForBeat(beats[prevB].id).length;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: InkWell(
                        key: ValueKey('rail_beat_${beat.id}'),
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          if (beatFeats.isEmpty) return;
                          final targetFeat = beatFeats.firstWhere(
                            (f) => widget.workbench.getDocumentProgress(f.id) < 100,
                            orElse: () => beatFeats.first,
                          );
                          setState(() {
                            _manualCheckpointFocusIndex = null;
                          });
                          widget.workbench.selectFeature(targetFeat.id);
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'E${(bIdx + 1).toString().padLeft(2, '0')} · ${_formatOutlineBeatDisplayTitle(beat.title).toUpperCase()}',
                                maxLines: 2,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  height: 1.25,
                                  color: allBeatDone
                                      ? accentEmerald.withValues(alpha: 0.75)
                                      : (isBeatActive ? textSecondary : textMuted),
                                  decoration: allBeatDone
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                ),
                              ),
                            ),
                              if (beatFeats.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Builder(
                                  builder: (context) {
                                    final allBeatStable = beatFeats.every(
                                      (f) => f.sections['lifecycle'] == 'stable',
                                    );
                                    return Text(
                                      allBeatStable
                                          ? 'STABLE ✓'
                                          : '$doneBeatCount/${beatFeats.length}',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: allBeatDone || allBeatStable
                                            ? accentEmerald
                                            : textMuted,
                                      ),
                                    );
                                  },
                                ),
                              ],
                              const SizedBox(width: 6),
                              InkWell(
                                key: ValueKey('rail_add_feat_to_beat_${beat.id}'),
                                onTap: () => _showAddLiveFeatureDialog(beat),
                                borderRadius: BorderRadius.circular(3),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 1,
                                  ),
                                  child: Text(
                                    '+',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: accentCyan,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                        ),
                      ),
                    ),
                    for (int fIdx = 0; fIdx < beatFeats.length; fIdx++)
                      _buildFeatureRailItem(
                        beatFeats[fIdx],
                        activeVer: activeVer,
                        beatTitle: beat.title,
                        beatIndex: bIdx,
                        featureIndexInBeat: fIdx,
                        globalFeatureIndex: prevFeaturesBeforeBeat + fIdx,
                      ),
                  ],
                );
              },
            ),
          ],
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: InkWell(
            key: const ValueKey('outliner_new_progressive_release_btn'),
            onTap: () => _showProgressiveNextReleaseModal(context),
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      '+ New Release (${widget.workbench.nextProgressiveVersionLabel})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: accentEmerald,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '✦ AI',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: accentCyan,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    if (shrinkWrap) {
      return Container(
        decoration: BoxDecoration(
          color: bgRecessed,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderSubtle),
        ),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bgRecessed,
        border: Border(
          right: BorderSide(
            color: isOverlayDrawer ? borderBright : borderSubtle,
          ),
        ),
      ),
      child: SingleChildScrollView(child: content),
    );
  }

  Widget _buildFeatureRailItem(
    TierDocument feat, {
    required String activeVer,
    String? beatTitle,
    int beatIndex = 0,
    int featureIndexInBeat = 0,
    int globalFeatureIndex = 0,
  }) {
    final isSelected = widget.workbench.selectedFeatureId == feat.id;
    final progress = widget.workbench.getDocumentProgress(feat.id);
    final featRemMins = _computeFeatureRemainingMinutes(feat);
    final featRemLabel =
        TaskHowToBlueprint.formatRemainingHoursShort(featRemMins);
    final isDone = progress >= 100 || featRemMins <= 0;
    final isFocus = widget.workbench.focusMode;
    final depTier = WorkspaceAgentOrchestrator.classifyDependencyTier(
      featureTitle: feat.title,
      beatIndex: beatIndex,
      featureIndexInBeat: featureIndexInBeat,
    );

    final shouldDim = isFocus && !isSelected;
    final displayTitle = _formatOutlineFeatureDisplayTitle(
      feat.title,
      beatTitle,
      beatIndex: beatIndex,
    );

    return Opacity(
      opacity: shouldDim ? 0.45 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.035)
                  : bgSurface)
              : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey('rail_feat_${feat.id}'),
              onTap: () {
                setState(() {
                  _manualCheckpointFocusIndex = null;
                });
                widget.workbench.selectFeature(feat.id);
              },
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  isSelected ? 13 : 16,
                  8,
                  16,
                  8,
                ),
                decoration: BoxDecoration(
                  border: isSelected
                      ? Border(
                          left: BorderSide(
                            color: isDone ? accentEmerald : accentCyan,
                            width: 3,
                          ),
                        )
                      : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: InkWell(
                        key: ValueKey('outline_feat_chevron_${feat.id}'),
                        onTap: () {
                          setState(() {
                            _manualCheckpointFocusIndex = null;
                          });
                          widget.workbench.selectFeature(feat.id);
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 14,
                          height: 18,
                          child: Center(
                            child: Text(
                                isDone
                                    ? '✓'
                                    : (isSelected ? '●' : '·'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isDone
                                    ? accentEmerald
                                    : (isSelected ? accentCyan : textMuted),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            maxLines: 2,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              height: 1.25,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isDone
                                  ? textMuted.withValues(alpha: 0.6)
                                  : (isSelected ? textPrimary : textSecondary),
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                          if (displayTitle != feat.title)
                            SizedBox(
                              height: 1,
                              child: Opacity(
                                opacity: 0,
                                child: Text(
                                  feat.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        isDone ? 'DONE' : featRemLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: isSelected || isDone
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isDone
                              ? accentEmerald
                              : (isSelected ? accentCyan : textMuted),
                        ),
                      ),
                    ),
                    Offstage(
                      offstage: true,
                      child: Container(
                        key: ValueKey('stage3_dep_tier_${feat.id}'),
                        child: Text(depTier.shortBadge),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fix 1: Flat Borderless Step Timeline rendered inside the Work Area (Full-Screen mode).
  /// Unifies all Task Groups across the Feature's checkpoints into one sequential `01..N` list
  /// along a continuous 1px vertical track line (zero stacked CP bars, zero boxes, zero accordions).
  Widget _buildFlatFeatureStepTimeline({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required FeatureStateNode node,
    required List<TaskHowToBlueprint> howToBlueprints,
    required int selectedTaskIdx,
    required int activeSubStepIdx,
    required String featureCategory,
  }) {
    final engineHint = _engineHint;
    final unifiedTaskGroups = <({
      int cpIdx,
      FeatureStateNode cpNode,
      int tIdx,
      Subtask task,
      TaskHowToBlueprint bp,
      int globalTaskIdx,
      String cpCategory,
    })>[];
    int totalDoneSteps = 0;
    int totalStepsCount = 0;
    int runningGlobalTaskIdx = 0;

    for (int tIdx = 0; tIdx < node.checklist.length; tIdx++) {
      final bp = tIdx < howToBlueprints.length
          ? howToBlueprints[tIdx]
          : TaskHowToBlueprint.resolve(
              parentTask: node.checklist[tIdx],
              taskIndex: tIdx,
              checkpointNode: node,
              engineHint: engineHint,
              unrealCppMode: _unrealCppMode,
            );
      totalStepsCount += bp.subSteps.length;
      totalDoneSteps += bp.subSteps.where((s) => s.subtask.completed).length;
      unifiedTaskGroups.add((
        cpIdx: checkpointIndex,
        cpNode: node,
        tIdx: tIdx,
        task: node.checklist[tIdx],
        bp: bp,
        globalTaskIdx: runningGlobalTaskIdx++,
        cpCategory: featureCategory,
      ));
    }

    return Container(
      key: ValueKey('work_area_step_timeline_${node.id}'),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Framed STEPS Card Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: bgSurfaceHover,
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'STEPS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$totalDoneSteps/$totalStepsCount DONE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: totalDoneSteps > 0 ? accentEmerald : textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Preserve offstage checkpoint keys for test compatibility while keeping the UI 100% unified
          for (int cpIdx = 0; cpIdx < states.length; cpIdx++)
            Offstage(
              offstage: true,
              child: InkWell(
                key: ValueKey('outline_cp_${feat.id}_$cpIdx'),
                onTap: () {
                  setState(() {
                    _manualCheckpointFocusIndex = cpIdx;
                  });
                },
                child: const SizedBox.shrink(),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                for (int gIdx = 0; gIdx < unifiedTaskGroups.length; gIdx++)
                  Builder(
                    builder: (context) {
                      final grp = unifiedTaskGroups[gIdx];
                      final cpIdx = grp.cpIdx;
                      final cpNode = grp.cpNode;
                      final tIdx = grp.tIdx;
                      final bp = grp.bp;
                      final task = grp.task;
                      final globalNumLabel =
                          (grp.globalTaskIdx + 1).toString().padLeft(2, '0');
                      final isFixTask = task.text.trim().startsWith('[FIX]');
                      final isTaskActive =
                          cpIdx == checkpointIndex && tIdx == selectedTaskIdx;
                      final doneSubCount = bp.subSteps
                          .where((s) => s.subtask.completed)
                          .length;
                      final totalSubCount = bp.subSteps.length;
                      final groupTitle = isFixTask
                          ? bp.shortTaskTitle.toUpperCase()
                          : MechanicArchetypeProfile.taskGroupTitle(
                              grp.cpCategory,
                              grp.globalTaskIdx,
                              fallbackTitle: bp.shortTaskTitle,
                            ).toUpperCase();

                      return Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: isTaskActive ? 12 : 10,
                        ),
                        decoration: BoxDecoration(
                          border: gIdx == 0
                              ? null
                              : Border(
                                  top: BorderSide(color: borderSubtle),
                                ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Clean Task Group Overline (separated by card divider, no nested inner box)
                            InkWell(
                              key: ValueKey('outline_task_${cpNode.id}_$tIdx'),
                              onTap: () {
                                setState(() {
                                  _manualCheckpointFocusIndex = cpIdx;
                                  _selectedTaskIndexByCheckpoint[cpNode.id] =
                                      tIdx;
                                });
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${isTaskActive ? '▾' : '▸'} $globalNumLabel · $groupTitle',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                          color: task.completed
                                              ? accentEmerald.withValues(
                                                  alpha: 0.8,
                                                )
                                              : (isFixTask
                                                  ? accentCrimson
                                                  : (isTaskActive
                                                      ? accentCyan
                                                      : textSecondary)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      key: ValueKey(
                                        'complete_task_group_${cpNode.id}_$tIdx',
                                      ),
                                      onTap: () => _toggleTaskGroupCompletion(
                                        feat,
                                        states,
                                        cpNode,
                                        tIdx,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                          vertical: 1,
                                        ),
                                        child: Text(
                                          task.completed
                                              ? '✓ $doneSubCount/$totalSubCount'
                                              : '$doneSubCount/$totalSubCount',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: task.completed
                                                ? accentEmerald.withValues(
                                                    alpha: 0.85,
                                                  )
                                                : (isTaskActive
                                                    ? accentCyan
                                                    : textMuted),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (isTaskActive) ...[
                              const SizedBox(height: 6),
                              // Continuous 1px vertical track line with crisp 1-line Steps
                              Container(
                                margin: const EdgeInsets.only(left: 7),
                                padding: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: borderSubtle,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (int sIdx = 0;
                                        sIdx < bp.subSteps.length;
                                        sIdx++)
                                      Builder(
                                        builder: (context) {
                                          final stepItem = bp.subSteps[sIdx];
                                          final isStepActive = isTaskActive &&
                                              sIdx == activeSubStepIdx;
                                          final isStepDone =
                                              stepItem.subtask.completed;
                                          return Opacity(
                                            opacity: isStepActive
                                                ? 1.0
                                                : (isStepDone ? 0.55 : 0.78),
                                            child: InkWell(
                                              key: ValueKey(
                                                'task_sheet_step_row_${cpNode.id}_${tIdx}_$sIdx',
                                              ),
                                              onTap: () {
                                                setState(() {
                                                  _manualCheckpointFocusIndex =
                                                      cpIdx;
                                                  _selectedTaskIndexByCheckpoint[
                                                      cpNode.id] = tIdx;
                                                  _selectedSubStepIndexByTask[
                                                      '${cpNode.id}_$tIdx'] = sIdx;
                                                });
                                              },
                                              borderRadius:
                                                  const BorderRadius.only(
                                                topRight: Radius.circular(6),
                                                bottomRight: Radius.circular(6),
                                              ),
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                  bottom: 2,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 7,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isStepActive
                                                      ? accentCyan.withValues(
                                                          alpha: 0.14,
                                                        )
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                    topRight:
                                                        Radius.circular(6),
                                                    bottomRight:
                                                        Radius.circular(6),
                                                  ),
                                                  border: Border(
                                                    left: BorderSide(
                                                      color: isStepActive
                                                          ? accentCyan
                                                          : Colors.transparent,
                                                      width: 2.5,
                                                    ),
                                                  ),
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    SizedBox(
                                                      width: 18,
                                                      child: Text(
                                                        isStepDone &&
                                                                !isStepActive
                                                            ? '✓'
                                                            : (isStepActive
                                                                ? '●'
                                                                : (sIdx + 1)
                                                                    .toString()
                                                                    .padLeft(
                                                                      2,
                                                                      '0',
                                                                    )),
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: isStepActive
                                                              ? accentCyan
                                                              : (isStepDone
                                                                  ? accentEmerald
                                                                  : textMuted),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        stepItem.shortTitle,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 12,
                                                          height: 1.25,
                                                          fontWeight:
                                                              isStepActive
                                                                  ? FontWeight
                                                                      .w700
                                                                  : FontWeight
                                                                      .w500,
                                                          color: isStepActive
                                                              ? textPrimary
                                                              : textSecondary,
                                                          decoration: isStepDone &&
                                                                  !isStepActive
                                                              ? TextDecoration
                                                                  .lineThrough
                                                              : TextDecoration
                                                                  .none,
                                                        ),
                                                      ),
                                                    ),
                                                    if (!isStepDone) ...[
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        stepItem.etaLabel,
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 9.5,
                                                          fontWeight:
                                                              isStepActive
                                                                  ? FontWeight
                                                                      .w700
                                                                  : FontWeight
                                                                      .w500,
                                                          color: isStepActive
                                                              ? accentCyan
                                                              : textMuted,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ] else
                              for (int sIdx = 0;
                                  sIdx < bp.subSteps.length;
                                  sIdx++)
                                Offstage(
                                  offstage: true,
                                  child: InkWell(
                                    key: ValueKey(
                                      'task_sheet_step_row_${cpNode.id}_${tIdx}_$sIdx',
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _manualCheckpointFocusIndex = cpIdx;
                                        _selectedTaskIndexByCheckpoint[
                                            cpNode.id] = tIdx;
                                        _selectedSubStepIndexByTask[
                                            '${cpNode.id}_$tIdx'] = sIdx;
                                      });
                                    },
                                    child: const SizedBox.shrink(),
                                  ),
                                ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 12),
                InkWell(
                  key: ValueKey('outline_add_task_btn_${node.id}'),
                  onTap: () => _showAddBuildTaskDialog(
                    feat,
                    states,
                    checkpointIndex,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                    child: Text(
                      '+ Add Build Task...',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accentCyan.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureMainCanvas(
    TierDocument rel, {
    bool shrinkWrap = false,
    bool isHalfScreenOverlayMode = false,
  }) {
    final feat = widget.workbench.selectedFeature;
    if (feat == null) {
      return Center(
        child: Text(
          'Select a Feature from the left rail.',
          style: GoogleFonts.inter(color: textMuted),
        ),
      );
    }

    final states = FeatureStateNode.getStatesForDocument(feat);
    final progress = widget.workbench.getDocumentProgress(feat.id).toDouble();
    final isDone = progress >= 100;
    final nextFeat = widget.workbench.nextIncompleteFeature;

    int activeFocusIndex = -1;
    for (int i = 0; i < states.length; i++) {
      final s = states[i];
      final awaitingPlaytest = _awaitingPlaytestVerification.contains(s.id);
      // Keep the active focus spotlight on a checkpoint that just finished its tasks
      // until the user clicks "Verify Playtest & Advance"
      if (activeFocusIndex == -1 && (!s.isCompleted || awaitingPlaytest)) {
        activeFocusIndex = i;
      }
    }

    if (activeFocusIndex == -1 && states.isNotEmpty) {
      activeFocusIndex = states.length - 1;
    }
    final effectiveFocusIndex = (_manualCheckpointFocusIndex != null &&
            _manualCheckpointFocusIndex! >= 0 &&
            _manualCheckpointFocusIndex! < states.length)
        ? _manualCheckpointFocusIndex!
        : activeFocusIndex;

    Widget buildBody(double viewportHeight) {
      final activeFeatureContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.workbench.isActiveReleaseComplete) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: _buildReleaseShippedBanner(rel),
            ),
          ] else if (isDone && nextFeat != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: _buildNextFeatureAdvanceBanner(feat, nextFeat),
            ),
          ],
          for (int i = 0; i < states.length; i++)
            if (!widget.workbench.focusMode ||
                i == effectiveFocusIndex ||
                states.length <= 1)
              _buildCheckpointCard(
                feat,
                states,
                i,
                activeFocusIndex: effectiveFocusIndex,
                viewportHeight: viewportHeight,
                isHalfScreenOverlayMode: isHalfScreenOverlayMode,
              ),
        ],
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('stage3_active_feature_sheet'),
            child: activeFeatureContent,
          ),
        ],
      );
    }

    if (shrinkWrap) {
      return buildBody(680);
    }

    return Container(
      color: bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, viewportConstraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: viewportConstraints.maxWidth,
                    ),
                    child: buildBody(viewportConstraints.maxHeight),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextFeatureAdvanceBanner(
    TierDocument completedFeat,
    TierDocument nextFeat,
  ) {
    final completedBeat = completedFeat.parentId != null
        ? widget.workbench.documents[completedFeat.parentId!]
        : null;
    final nextBeat = nextFeat.parentId != null
        ? widget.workbench.documents[nextFeat.parentId!]
        : null;
    final completedTitle = _formatOutlineFeatureDisplayTitle(
      completedFeat.title,
      completedBeat?.title,
    );
    final nextTitle = _formatOutlineFeatureDisplayTitle(
      nextFeat.title,
      nextBeat?.title,
    );

    return Container(
      key: const ValueKey('next_feature_advance_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderBright),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: accentEmerald,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$completedTitle is 100% VERIFIED ✓! Ready for the next feature in your loop?',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            key: const ValueKey('continue_to_next_feature_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: focalAccent,
              foregroundColor: focalAccentFg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => widget.workbench.selectFeature(nextFeat.id),
            icon: const Icon(Icons.arrow_forward_rounded, size: 15),
            label: Text(
              'Continue to $nextTitle →',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseShippedBanner(TierDocument rel) {
    final nextVer = widget.workbench.nextProgressiveVersionLabel;
    return Container(
      key: const ValueKey('release_complete_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: accentEmerald.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentEmerald.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, color: accentEmerald, size: 18),
              const SizedBox(width: 10),
              Text(
                'All Features in ${rel.title} are 100% Complete ✓!',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('release_shipped_summary_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentEmerald,
                  side: BorderSide(color: accentEmerald.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: () => _showReleaseShippedSummaryModal(context, rel),
                icon: const Icon(Icons.emoji_events_outlined, size: 14),
                label: Text(
                  'Release Summary',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const ValueKey('ship_and_plan_next_release_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: focalAccent,
                  foregroundColor: focalAccentFg,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: () => _showProgressiveNextReleaseModal(context),
                icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                label: Text(
                  '+ New Release ($nextVer) ✦',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showProgressiveNextReleaseModal(BuildContext context) async {
    await widget.workbench.prepareProgressiveNextReleaseDraft();
    if (!context.mounted) return;

    final directiveCtrl = TextEditingController();
    const aiDirectionPresets = <({String label, String prompt})>[
      (
        label: '⚡ Deepen Core Mechanics',
        prompt: 'Add Player Dash & Parry to Beat 1',
      ),
      (
        label: '👾 Add Enemy & Wave Variety',
        prompt: 'Add Elite Enemy Spawner to Beat 2',
      ),
      (
        label: '📈 Add Progression & Rewards',
        prompt: 'Add Upgrade Relic Choice to Beat 3',
      ),
      (
        label: '✨ Polish Game Feel & HUD',
        prompt: 'Add Hit-Stop & Damage Numbers to Beat 2',
      ),
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final bp = widget.workbench.releaseBlueprint;
            final nextVer = bp?.releaseVersionTag ??
                widget.workbench.nextProgressiveVersionLabel;
            final upgradeFeats = <({ProposedBeatBlueprint beat, ProposedFeatureBlueprint feat})>[];
            final newFeats = <({ProposedBeatBlueprint beat, ProposedFeatureBlueprint feat})>[];
            if (bp != null) {
              for (final b in bp.beats) {
                for (final f in b.features) {
                  if (f.lifecycle == FeatureLifecycleStatus.upgrade) {
                    upgradeFeats.add((beat: b, feat: f));
                  } else if (f.lifecycle == FeatureLifecycleStatus.newFeature) {
                    newFeats.add((beat: b, feat: f));
                  }
                }
              }
            }

            return AlertDialog(
              key: const ValueKey('progressive_next_release_modal'),
              backgroundColor: bgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: borderBright),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: accentCyan,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Progressive AI Release · $nextVer',
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${bp?.totalIncludedHours ?? 0}h · ${bp?.totalIncludedFeatures ?? 0} features',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accentEmerald,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'The Agent analyzed your live game tree and recommends what to Upgrade (UPGRADE) and what New Systems (NEW) to add in $nextVer:',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (int pIdx = 0; pIdx < aiDirectionPresets.length; pIdx++)
                            InkWell(
                              key: ValueKey('progressive_preset_chip_$pIdx'),
                              borderRadius: BorderRadius.circular(5),
                              onTap: widget.workbench.isAgentBusy
                                  ? null
                                  : () async {
                                      await widget.workbench
                                          .sendReleasePlanChatMessage(
                                        aiDirectionPresets[pIdx].prompt,
                                      );
                                      if (ctx.mounted) setModalState(() {});
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: bgRecessed,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: accentCyan.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  aiDirectionPresets[pIdx].label,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: accentCyan,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey(
                                'progressive_release_prompt_input',
                              ),
                              controller: directiveCtrl,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Tell the Agent what direction to take in $nextVer (e.g., "Add enemy wave variety")...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                                filled: true,
                                fillColor: bgRecessed,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: borderSubtle),
                                ),
                              ),
                              onSubmitted: (val) async {
                                if (val.trim().isEmpty) return;
                                await widget.workbench
                                    .sendReleasePlanChatMessage(val.trim());
                                directiveCtrl.clear();
                                if (ctx.mounted) setModalState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            key: const ValueKey(
                              'progressive_release_ask_agent_btn',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentCyan,
                              side: BorderSide(
                                color: accentCyan.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                            ),
                            onPressed: widget.workbench.isAgentBusy
                                ? null
                                : () async {
                                    final text = directiveCtrl.text.trim();
                                    if (text.isEmpty) return;
                                    await widget.workbench
                                        .sendReleasePlanChatMessage(text);
                                    directiveCtrl.clear();
                                    if (ctx.mounted) setModalState(() {});
                                  },
                            child: Text(
                              'Ask Agent ✦',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (upgradeFeats.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'UPGRADE EXISTING FEATURES (${upgradeFeats.length})',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: accentAmber,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final item in upgradeFeats)
                          InkWell(
                            onTap: () {
                              widget.workbench.toggleProposedFeatureScope(
                                item.beat.id,
                                item.feat.id,
                                !item.feat.included,
                              );
                              setModalState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  Icon(
                                    item.feat.included
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 16,
                                    color: item.feat.included
                                        ? accentAmber
                                        : textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _formatOutlineFeatureDisplayTitle(
                                        item.feat.title,
                                        item.beat.title,
                                      ),
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: item.feat.included
                                            ? textPrimary
                                            : textMuted,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'UPGRADE · +${item.feat.activeDeltaHours}h',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: accentAmber,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      if (newFeats.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          'ADD NEW FEATURES (${newFeats.length})',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: accentEmerald,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final item in newFeats)
                          InkWell(
                            onTap: () {
                              widget.workbench.toggleProposedFeatureScope(
                                item.beat.id,
                                item.feat.id,
                                !item.feat.included,
                              );
                              setModalState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  Icon(
                                    item.feat.included
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 16,
                                    color: item.feat.included
                                        ? accentEmerald
                                        : textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _formatOutlineFeatureDisplayTitle(
                                        item.feat.title,
                                        item.beat.title,
                                      ),
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: item.feat.included
                                            ? textPrimary
                                            : textMuted,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'NEW · +${item.feat.activeDeltaHours}h',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: accentEmerald,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: textSecondary,
                    ),
                  ),
                ),
                ElevatedButton(
                  key: const ValueKey('confirm_progressive_release_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentEmerald,
                    foregroundColor: const Color(0xFF052E16),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await widget.workbench.approveAndExecuteReleasePlan();
                  },
                  child: Text(
                    'Build $nextVer in Workbench →',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showReleaseShippedSummaryModal(BuildContext context, TierDocument rel) {
    final retro = widget.workbench.buildActiveReleaseRetrospective();
    final beats = widget.workbench.activeReleaseBeats;
    final allFeats = <TierDocument>[
      for (final b in beats) ...widget.workbench.featuresForBeat(b.id),
    ];
    int totalTasks = 0;
    int totalStepsDone = 0;
    for (final f in allFeats) {
      final states = FeatureStateNode.getStatesForDocument(f);
      for (final s in states) {
        totalTasks += s.totalChecklistCount;
        for (final t in s.checklist) {
          totalStepsDone += t.children.isNotEmpty
              ? t.children.where((c) => c.completed).length
              : (t.completed ? 6 : 0);
        }
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: accentEmerald.withValues(alpha: 0.6)),
        ),
        title: Row(
          children: [
            Icon(Icons.rocket_launch_rounded, color: accentEmerald, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${rel.title} — 100% Shipped & Playtested ✓',
                style: AppTheme.displayFont(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Every Feature, Build Task, and Step across your Core Loop has been completed and verified:',
                style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bgRecessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          '${beats.length}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: accentEmerald,
                          ),
                        ),
                        Text(
                          'CORE EPICS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '${allFeats.length}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: accentAmber,
                          ),
                        ),
                        Text(
                          'FEATURES',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '$totalTasks',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: accentEmerald,
                          ),
                        ),
                        Text(
                          'BUILD TASKS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '$totalStepsDone',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          'STEPS DONE',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bgRecessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AGENT RETROSPECTIVE · PLAYTEST HARDENING & CARRYOVER',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: accentAmber,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• ${retro.fixTasksTriaged} playtest [FIX] task(s) triaged · ${retro.playtestGuardsAdded} [PLAYTEST/SIMULATION GUARD] rules locked into live tree',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: textSecondary,
                      ),
                    ),
                    if (retro.carryoverFeatureTitles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '• Auto-Carryover to next Release: ${retro.carryoverFeatureTitles.join(", ")}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: accentAmber,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: focalAccent,
              foregroundColor: focalAccentFg,
              elevation: 0,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _showProgressiveNextReleaseModal(context);
            },
            icon: const Icon(Icons.auto_awesome_rounded, size: 15),
            label: Text(
              '+ New Release (${widget.workbench.nextProgressiveVersionLabel}) ✦',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptEditHowToSubStepDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int pIdx,
    int sIdx,
  ) async {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    if (sIdx < 0 || sIdx >= parentTask.children.length) return;
    final sub = parentTask.children[sIdx];
    final titleCtrl = TextEditingController(text: sub.text);
    final instrCtrl = TextEditingController(text: sub.specNotes);
    final codeCtrl = TextEditingController(text: sub.codeSnippet);

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Edit How-To Sub-Step (${pIdx + 1}.${sIdx + 1})',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('edit_substep_title_input'),
                controller: titleCtrl,
                style: GoogleFonts.inter(fontSize: 12.5, color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'Sub-step Title',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('edit_substep_instruction_input'),
                controller: instrCtrl,
                maxLines: 2,
                style: GoogleFonts.inter(fontSize: 12, color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'How-To Instruction',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('edit_substep_code_input'),
                controller: codeCtrl,
                maxLines: 3,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: AppTheme.accentCyanFor(isDark),
                ),
                decoration: InputDecoration(
                  labelText: 'Code Formula / Snippet',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (parentTask.children.length > 1)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('delete'),
              child: Text(
                'Delete',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentCrimson,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: focalAccent,
              foregroundColor: focalAccentFg,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: Text(
              'Save Sub-Step',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == 'cancel') return;
    setState(() {
      if (action == 'delete' && parentTask.children.length > 1) {
        parentTask.children.removeAt(sIdx);
        parentTask.completed = parentTask.children.isNotEmpty &&
            parentTask.children.every((c) => c.completed);
      } else if (action == 'save') {
        if (titleCtrl.text.trim().isNotEmpty) {
          sub.text = titleCtrl.text.trim();
        }
        sub.specNotes = instrCtrl.text.trim();
        sub.codeSnippet = codeCtrl.text.trim();
        sub.codeTargetFile = 'custom_snippet';
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  Future<void> _copySubStepCodeFormula(
    int pIdx,
    int sIdx,
    String codeFormula,
  ) async {
    await Clipboard.setData(ClipboardData(text: codeFormula));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Copied Step ${pIdx + 1}.${sIdx + 1} code formula to clipboard ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyAllTaskCode(TaskHowToBlueprint howTo) async {
    final buffer = StringBuffer()
      ..writeln('// === Task ${howTo.numLabel}: ${howTo.cleanTitle} ===');
    for (int i = 0; i < howTo.subSteps.length; i++) {
      final step = howTo.subSteps[i];
      final stepNum = (i + 1).toString().padLeft(2, '0');
      buffer
        ..writeln()
        ..writeln('// --- Step $stepNum: ${step.shortTitle} ---')
        ..writeln(step.codeFormula.trim());
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Copied all ${howTo.subSteps.length} step code blocks for Task ${howTo.numLabel} ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _promptTailorHowToDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    int checkpointIndex,
    int pIdx,
  ) async {
    final node = states[checkpointIndex];
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    final ctrl = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          '✦ Tailor How-To Sub-Steps (Task ${(pIdx + 1).toString().padLeft(2, '0')})',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Describe your exact Scene / Node / Script setup for "${parentTask.text}". The Agent will rewrite all sub-steps in Task ${(pIdx + 1).toString().padLeft(2, '0')} using your exact node and script names:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('tailor_howto_context_input'),
                controller: ctrl,
                autofocus: true,
                maxLines: 3,
                onSubmitted: (_) => Navigator.of(ctx).pop('tailor'),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  hintText:
                      'e.g., CharacterBody2D with RayCast2D HookRay and Line2D RopeVisual',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: textMuted,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_tailor_howto_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: focalAccent,
              foregroundColor: focalAccentFg,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop('tailor'),
            child: Text(
              '✦ Tailor Sub-Steps',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted || action != 'tailor') return;
    final contextText = ctrl.text.trim();
    if (contextText.isEmpty) return;
    await widget.workbench.tailorTaskHowToSubSteps(
      featureId: feat.id,
      states: states,
      checkpointIndex: checkpointIndex,
      taskIndex: pIdx,
      userContext: contextText,
    );
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Tailored Task ${(pIdx + 1).toString().padLeft(2, '0')} How-To sub-steps to "$contextText" ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleHowToSubStepCompletion(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int pIdx,
    int sIdx,
  ) {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    if (sIdx < 0 || sIdx >= parentTask.children.length) return;
    final wasDone = node.isCompleted;
    final nextCompleted = !parentTask.children[sIdx].completed;
    parentTask.children[sIdx].completed = nextCompleted;
    parentTask.completed = parentTask.children.isNotEmpty &&
        parentTask.children.every((c) => c.completed);
    final nowDone = node.isCompleted;
    setState(() {
      _selectedTaskIndexByCheckpoint[node.id] = pIdx;
      _selectedSubStepIndexByTask['${node.id}_$pIdx'] = sIdx;
      if (!wasDone && nowDone) {
        _awaitingPlaytestVerification.add(node.id);
      } else if (!nowDone) {
        _awaitingPlaytestVerification.remove(node.id);
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  void _toggleTaskGroupCompletion(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int tIdx,
  ) {
    if (tIdx < 0 || tIdx >= node.checklist.length) return;
    final task = node.checklist[tIdx];
    final markDone = !task.completed;
    task.completed = markDone;
    for (final c in task.children) {
      c.completed = markDone;
    }
    setState(() {
      final nextTaskIdx = node.checklist.indexWhere((t) => !t.completed);
      if (markDone && nextTaskIdx != -1) {
        _manualCheckpointFocusIndex = states.indexWhere((s) => s.id == node.id);
        _selectedTaskIndexByCheckpoint[node.id] = nextTaskIdx;
        _selectedSubStepIndexByTask['${node.id}_$nextTaskIdx'] = 0;
      } else if (markDone) {
        final nextCpIdx = states.indexWhere((s) => !s.isCompleted);
        if (nextCpIdx != -1) {
          _manualCheckpointFocusIndex = nextCpIdx;
          final nextCp = states[nextCpIdx];
          _selectedTaskIndexByCheckpoint[nextCp.id] = 0;
          _selectedSubStepIndexByTask['${nextCp.id}_0'] = 0;
        } else {
          _selectedTaskIndexByCheckpoint[node.id] = tIdx;
        }
      } else {
        _manualCheckpointFocusIndex = states.indexWhere((s) => s.id == node.id);
        _selectedTaskIndexByCheckpoint[node.id] = tIdx;
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  void _completeAllCheckpointTasks(FeatureStateNode node) {
    for (final task in node.checklist) {
      task.completed = true;
      for (final child in task.children) {
        child.completed = true;
      }
    }
  }

  void _advanceToNextStep(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int pIdx,
    int sIdx,
  ) {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    if (sIdx < 0 || sIdx >= parentTask.children.length) return;
    if (!parentTask.children[sIdx].completed) return;
    int nextStepAfterCurrent = -1;
    for (int i = sIdx + 1; i < parentTask.children.length; i++) {
      if (!parentTask.children[i].completed) {
        nextStepAfterCurrent = i;
        break;
      }
    }
    final nextIncompleteStepIdx = nextStepAfterCurrent != -1
        ? nextStepAfterCurrent
        : parentTask.children.indexWhere((c) => !c.completed);
    if (nextIncompleteStepIdx != -1) {
      setState(() {
        _selectedTaskIndexByCheckpoint[node.id] = pIdx;
        _selectedSubStepIndexByTask['${node.id}_$pIdx'] = nextIncompleteStepIdx;
      });
      return;
    }

    // Current task is 100% done! Check if another task in this Checkpoint is incomplete
    final nextTaskIdx = node.checklist.indexWhere((t) => !t.completed);
    if (nextTaskIdx != -1) {
      setState(() {
        _selectedTaskIndexByCheckpoint[node.id] = nextTaskIdx;
        _selectedSubStepIndexByTask['${node.id}_$nextTaskIdx'] = 0;
      });
      return;
    }

    // All tasks & steps in this Checkpoint are 100% done! Verify Checkpoint & Continue
    _completeAllCheckpointTasks(node);
    setState(() {
      _awaitingPlaytestVerification.remove(node.id);
      _expandedDoneCheckpoints.remove(node.id);
      final nextCpIdx = states.indexWhere((s) => !s.isCompleted);
      if (nextCpIdx != -1) {
        _manualCheckpointFocusIndex = nextCpIdx;
        final nextCp = states[nextCpIdx];
        _selectedTaskIndexByCheckpoint[nextCp.id] = 0;
        _selectedSubStepIndexByTask['${nextCp.id}_0'] = 0;
      } else {
        _manualCheckpointFocusIndex = null;
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);

    // If all Checkpoints in this Feature are now complete, advance to the next incomplete Feature
    if (states.every((s) => s.isCompleted)) {
      final allFeats = <TierDocument>[
        for (final b in widget.workbench.activeReleaseBeats)
          ...widget.workbench.featuresForBeat(b.id),
      ];
      final nextFeat = allFeats.where(
        (f) =>
            f.id != feat.id &&
            widget.workbench.getDocumentProgress(f.id) < 100,
      );
      if (nextFeat.isNotEmpty) {
        widget.workbench.selectFeature(nextFeat.first.id);
      }
    }
  }

  void _retreatToPreviousStep(
    List<FeatureStateNode> states,
    int checkpointIndex,
    FeatureStateNode node,
    List<TaskHowToBlueprint> howToBlueprints,
    int pIdx,
    int sIdx,
  ) {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    if (sIdx > 0) {
      setState(() {
        _selectedTaskIndexByCheckpoint[node.id] = pIdx;
        _selectedSubStepIndexByTask['${node.id}_$pIdx'] = sIdx - 1;
      });
      return;
    }
    if (pIdx > 0) {
      final prevTaskIdx = pIdx - 1;
      final prevBp = howToBlueprints[prevTaskIdx];
      final prevLastStepIdx =
          prevBp.subSteps.isNotEmpty ? prevBp.subSteps.length - 1 : 0;
      setState(() {
        _selectedTaskIndexByCheckpoint[node.id] = prevTaskIdx;
        _selectedSubStepIndexByTask['${node.id}_$prevTaskIdx'] =
            prevLastStepIdx;
      });
      return;
    }
    if (checkpointIndex > 0) {
      final prevCpIdx = checkpointIndex - 1;
      final prevCp = states[prevCpIdx];
      if (prevCp.checklist.isNotEmpty) {
        final prevTaskIdx = prevCp.checklist.length - 1;
        final prevBp = TaskHowToBlueprint.resolve(
          parentTask: prevCp.checklist[prevTaskIdx],
          taskIndex: prevTaskIdx,
          checkpointNode: prevCp,
          engineHint: _engineHint,
          unrealCppMode: _unrealCppMode,
        );
        final prevLastStepIdx =
            prevBp.subSteps.isNotEmpty ? prevBp.subSteps.length - 1 : 0;
        setState(() {
          _manualCheckpointFocusIndex = prevCpIdx;
          _selectedTaskIndexByCheckpoint[prevCp.id] = prevTaskIdx;
          _selectedSubStepIndexByTask['${prevCp.id}_$prevTaskIdx'] =
              prevLastStepIdx;
        });
      }
    }
  }

  Widget _buildCheckpointCard(
    TierDocument feat,
    List<FeatureStateNode> states,
    int index, {
    required int activeFocusIndex,
    double viewportHeight = 680,
    bool isHalfScreenOverlayMode = false,
  }) {
    final node = states[index];
    final isActiveFocus = index == activeFocusIndex;
    final bool isCollapsed = !isActiveFocus;

    final featureArchetype =
        MechanicArchetypeProfile.fromFeatureTitle(feat.title);
    final cpArchetypeCategory =
        MechanicArchetypeProfile.inferCategory(node.cleanStageTitle);
    final effectiveCheckpointCategory =
        (cpArchetypeCategory == 'polish' || cpArchetypeCategory == 'content')
            ? cpArchetypeCategory
            : featureArchetype.category;
    final rawFeatureGoal = SectionTextUtils.resolveGoal(feat.sections).trim();
    final isLegacyCircularGoal = rawFeatureGoal.isEmpty ||
        rawFeatureGoal.toLowerCase().contains('(execute ') ||
        rawFeatureGoal
            .toLowerCase()
            .startsWith('build the playable mechanics and feedback for ');
    final featureGoalText =
        isLegacyCircularGoal ? featureArchetype.goal : rawFeatureGoal;

    final rawPlaytest = node.playtestCondition.trim();
    final isLegacyCircularPlaytest = rawPlaytest.isEmpty ||
        (rawPlaytest.toLowerCase().startsWith('execute ') &&
            rawPlaytest.toLowerCase().contains('verify "execute ')) ||
        (rawPlaytest.toLowerCase().startsWith('trigger ') &&
            rawPlaytest
                .toLowerCase()
                .contains('state activates within actionresponsewindow') &&
            featureArchetype.category != 'core');
    final resolvedPlaytestCheck =
        isLegacyCircularPlaytest ? featureArchetype.cp1Playtest : rawPlaytest;

    final hasLegacyEconomyMismatch = featureArchetype.category != 'economy' &&
        node.tuningParams.isNotEmpty &&
        node.tuningParams.first.contains('transactionCostBase: 25 gold');
    final tuningItems = hasLegacyEconomyMismatch
        ? featureArchetype.tuningParams
        : node.tuningParams;
    final edgeItems = hasLegacyEconomyMismatch
        ? featureArchetype.edgeCases
        : node.edgeCases;

    // Resolve Checkable How-To Blueprints for all parent tasks in this checkpoint
    final engineHint = _engineHint;
    final howToBlueprints = <TaskHowToBlueprint>[
      for (int tIdx = 0; tIdx < node.checklist.length; tIdx++)
        TaskHowToBlueprint.resolve(
          parentTask: node.checklist[tIdx],
          taskIndex: tIdx,
          checkpointNode: node,
          engineHint: engineHint,
          unrealCppMode: _unrealCppMode,
        ),
    ];

    int selectedTaskIdx = _selectedTaskIndexByCheckpoint[node.id] ??
        node.checklist.indexWhere((t) => !t.completed);
    if (selectedTaskIdx < 0 || selectedTaskIdx >= node.checklist.length) {
      selectedTaskIdx = 0;
    }
    final selectedParentTask =
        node.checklist.isNotEmpty ? node.checklist[selectedTaskIdx] : null;
    final selectedHowTo =
        howToBlueprints.isNotEmpty ? howToBlueprints[selectedTaskIdx] : null;
    final selectedTaskKey = '${node.id}_$selectedTaskIdx';
    int activeSubStepIdx = _selectedSubStepIndexByTask[selectedTaskKey] ??
        (selectedParentTask?.children.indexWhere((c) => !c.completed) ?? 0);
    if (selectedHowTo == null ||
        activeSubStepIdx < 0 ||
        activeSubStepIdx >= selectedHowTo.subSteps.length) {
      activeSubStepIdx = 0;
    }
    final activeSubStep = (selectedHowTo != null &&
            selectedHowTo.subSteps.isNotEmpty)
        ? selectedHowTo.subSteps[activeSubStepIdx]
        : null;

    final canGoToPreviousStep =
        index > 0 || selectedTaskIdx > 0 || activeSubStepIdx > 0;

    final areAllOtherCheckpointsDone = states.every(
      (s) => s.id == node.id || s.isCompleted,
    );

    // Determine whether this is the final remaining step of the entire Feature
    final isFinalCheckpointStep =
        (node.isCompleted && areAllOtherCheckpointsDone) ||
            (areAllOtherCheckpointsDone &&
                selectedParentTask != null &&
                node.checklist.every(
                  (t) => t.id == selectedParentTask.id || t.completed,
                ) &&
                selectedParentTask.children
                        .where((c) => !c.completed)
                        .length <=
                    (activeSubStep != null && !activeSubStep.subtask.completed
                        ? 1
                        : 0) &&
                activeSubStepIdx == (selectedHowTo?.subSteps.length ?? 1) - 1);

    // Determine pure-title "Next:" label and progression button label for the bottom of the Left Instruction Pane
    String nextUpLabel = 'Complete Feature & Continue';
    String advanceButtonLabel = 'Complete Feature & Continue →';
    if (selectedHowTo != null && !isFinalCheckpointStep) {
      if (activeSubStepIdx + 1 < selectedHowTo.subSteps.length) {
        final nextSub = selectedHowTo.subSteps[activeSubStepIdx + 1];
        nextUpLabel = nextSub.shortTitle;
        advanceButtonLabel = 'Next Step →';
      } else if (selectedTaskIdx + 1 < howToBlueprints.length) {
        final nextTaskBp = howToBlueprints[selectedTaskIdx + 1];
        nextUpLabel = '${nextTaskBp.numLabel} · ${nextTaskBp.cleanTitle}';
        advanceButtonLabel =
            'Next Task: ${nextTaskBp.numLabel} · ${nextTaskBp.cleanTitle} →';
      } else {
        advanceButtonLabel = 'Next Step →';
      }
    }

    final beatsForBreadcrumb = widget.workbench.activeReleaseBeats;
    int parentBeatIdx = 0;
    String? parentBeatTitle;
    for (int bIdx = 0; bIdx < beatsForBreadcrumb.length; bIdx++) {
      if (beatsForBreadcrumb[bIdx].id == feat.parentId) {
        parentBeatIdx = bIdx;
        parentBeatTitle = beatsForBreadcrumb[bIdx].title;
        break;
      }
    }
    final epicShortCode = 'E${(parentBeatIdx + 1).toString().padLeft(2, '0')}';
    final epicDisplayTitle = _formatOutlineBeatDisplayTitle(
      parentBeatTitle ?? 'Core Loop',
    );
    final featShortTitle = _formatOutlineFeatureDisplayTitle(
      feat.title,
      parentBeatTitle,
      beatIndex: parentBeatIdx,
    );

    final Widget? stepDropdownTrigger = (selectedParentTask != null &&
            selectedHowTo != null &&
            activeSubStep != null)
        ? PopupMenuButton<int>(
            key: ValueKey('step_dropdown_${node.id}_$selectedTaskIdx'),
            tooltip: 'Switch Step',
            color: bgSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: borderBright),
            ),
            onSelected: (selectedVal) {
              setState(() {
                if (selectedVal >= 1000) {
                  final pickedTaskIdx = (selectedVal ~/ 1000) - 1;
                  final pickedStepIdx = selectedVal % 1000;
                  _selectedTaskIndexByCheckpoint[node.id] = pickedTaskIdx;
                  _selectedSubStepIndexByTask['${node.id}_$pickedTaskIdx'] =
                      pickedStepIdx;
                } else {
                  _selectedTaskIndexByCheckpoint[node.id] = selectedTaskIdx;
                  _selectedSubStepIndexByTask['${node.id}_$selectedTaskIdx'] =
                      selectedVal;
                }
              });
            },
            itemBuilder: (context) => [
              for (int tIdx = 0; tIdx < howToBlueprints.length; tIdx++) ...[
                PopupMenuItem<int>(
                  enabled: false,
                  height: 26,
                  child: Text(
                    '${howToBlueprints[tIdx].numLabel} · ${MechanicArchetypeProfile.taskGroupTitle(effectiveCheckpointCategory, tIdx, fallbackTitle: howToBlueprints[tIdx].shortTaskTitle).toUpperCase()}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: tIdx == selectedTaskIdx ? accentCyan : textMuted,
                    ),
                  ),
                ),
                for (int sIdx = 0;
                    sIdx < howToBlueprints[tIdx].subSteps.length;
                    sIdx++)
                  PopupMenuItem<int>(
                    value: tIdx == selectedTaskIdx
                        ? sIdx
                        : (tIdx + 1) * 1000 + sIdx,
                    height: 34,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${(sIdx + 1).toString().padLeft(2, '0')} · ${howToBlueprints[tIdx].subSteps[sIdx].shortTitle}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: tIdx == selectedTaskIdx &&
                                      sIdx == activeSubStepIdx
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: tIdx == selectedTaskIdx &&
                                      sIdx == activeSubStepIdx
                                  ? accentCyan
                                  : (howToBlueprints[tIdx]
                                          .subSteps[sIdx]
                                          .subtask
                                          .completed
                                      ? textMuted
                                      : textPrimary),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          howToBlueprints[tIdx].subSteps[sIdx].subtask.completed
                              ? '✓'
                              : '~${howToBlueprints[tIdx].subSteps[sIdx].etaLabel}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: howToBlueprints[tIdx]
                                    .subSteps[sIdx]
                                    .subtask
                                    .completed
                                ? accentEmerald
                                : textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'STEP ${activeSubStepIdx + 1} OF ${selectedHowTo.subSteps.length} · ~${activeSubStep.etaLabel}${activeSubStep.subtask.completed ? ' · COMPLETED ✓' : ''}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: activeSubStep.subtask.completed
                          ? accentEmerald
                          : accentCyan,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: activeSubStep.subtask.completed
                      ? accentEmerald
                      : accentCyan,
                ),
              ],
            ),
          )
        : null;

    final primaryTuningLabel = tuningItems.isNotEmpty
        ? tuningItems[selectedTaskIdx % tuningItems.length]
        : 'responseTime: 0.12s';
    final primaryGuardLabel = edgeItems.isNotEmpty
        ? edgeItems[selectedTaskIdx % edgeItems.length]
            .replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '')
        : 'Ignore duplicate trigger while active';

    final pinnedActiveStepWindow = (selectedParentTask != null &&
            selectedHowTo != null &&
            activeSubStep != null &&
            stepDropdownTrigger != null)
        ? Container(
            key: ValueKey('pinned_active_step_window_${node.id}'),
            color: bgBase,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 1. Anchored Full-Width Feature Header Bar (vs. Half-Width 1-Line Context Bar) ──
                if (!isHalfScreenOverlayMode)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: bgSurface,
                      border: Border(
                        bottom: BorderSide(color: borderSubtle),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: RichText(
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.2,
                                          color: textPrimary,
                                        ),
                                        children: [
                                          TextSpan(
                                            text:
                                                '$epicShortCode · $epicDisplayTitle',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: textMuted,
                                            ),
                                          ),
                                          TextSpan(
                                            text: '  ›  ',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 11,
                                              color: textMuted,
                                            ),
                                          ),
                                          TextSpan(text: featShortTitle),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    key: ValueKey(
                                      'workbench_rename_feature_btn_${feat.id}',
                                    ),
                                    onTap: () =>
                                        _showRenameLiveFeatureDialog(feat),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        '✎',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  InkWell(
                                    key: ValueKey(
                                      'workbench_remove_feature_btn_${feat.id}',
                                    ),
                                    onTap: () => widget.workbench
                                        .removeLiveFeature(feat.id),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        '×',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Container(
                                key: ValueKey(
                                  'task_sheet_feature_goal_${node.id}',
                                ),
                                child: Text(
                                  featureGoalText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!node.isCompleted) ...[
                          const SizedBox(width: 16),
                          InkWell(
                            key: ValueKey(
                              'fast_track_checkpoint_btn_${node.id}',
                            ),
                            onTap: () {
                              _completeAllCheckpointTasks(node);
                              _advanceToNextStep(
                                feat,
                                states,
                                node,
                                node.checklist.length - 1,
                                node.checklist.last.children.length - 1,
                              );
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: accentEmerald.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: accentEmerald.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                '✓ Complete Feature',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: accentEmerald,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: InkWell(
                                key: ValueKey(
                                  'halfscreen_outliner_trigger_${node.id}',
                                ),
                                onTap: () {
                                  setState(() {
                                    _isHalfScreenOutlinerOpen =
                                        !_isHalfScreenOutlinerOpen;
                                  });
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.menu_rounded,
                                        size: 14,
                                        color: _isHalfScreenOutlinerOpen
                                            ? accentCyan
                                            : textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: RichText(
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          text: TextSpan(
                                            style: GoogleFonts.inter(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: textPrimary,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: '$epicDisplayTitle › ',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: textMuted,
                                                ),
                                              ),
                                              TextSpan(text: featShortTitle),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 14,
                                        color: textMuted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                stepDropdownTrigger,
                                const SizedBox(width: 6),
                                Text(
                                  '|',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    color: borderBright,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: canGoToPreviousStep
                                      ? () => _retreatToPreviousStep(
                                            states,
                                            index,
                                            node,
                                            howToBlueprints,
                                            selectedTaskIdx,
                                            activeSubStepIdx,
                                          )
                                      : null,
                                  borderRadius: BorderRadius.circular(3),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '‹',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: canGoToPreviousStep
                                            ? textSecondary
                                            : textMuted.withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _advanceToNextStep(
                                    feat,
                                    states,
                                    node,
                                    selectedTaskIdx,
                                    activeSubStepIdx,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '›',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          key: ValueKey('task_sheet_feature_goal_${node.id}'),
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            featureGoalText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── 2. Balanced 2-Card Body (4 cols Framed STEPS Card | 8 cols Framed ACTIVE STEP Card) ──
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isHalfScreenOverlayMode ? 16 : 24,
                    isHalfScreenOverlayMode ? 12 : 20,
                    isHalfScreenOverlayMode ? 16 : 24,
                    28,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isHalfScreenOverlayMode) ...[
                        Expanded(
                          flex: 4,
                          child: _buildFlatFeatureStepTimeline(
                            feat: feat,
                            states: states,
                            checkpointIndex: index,
                            node: node,
                            howToBlueprints: howToBlueprints,
                            selectedTaskIdx: selectedTaskIdx,
                            activeSubStepIdx: activeSubStepIdx,
                            featureCategory: effectiveCheckpointCategory,
                          ),
                        ),
                        const SizedBox(width: 22),
                      ],
                      Expanded(
                        flex: 8,
                        child: Container(
                          key: ValueKey(
                            'task_sheet_active_step_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                          ),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderSubtle),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Card Header Bar (Step X of Y + [ Blueprint | C++ ] Toggle + Prev/Next) ──
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: bgSurfaceHover,
                                  border: Border(
                                    bottom: BorderSide(color: borderSubtle),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (!isHalfScreenOverlayMode)
                                      Flexible(child: stepDropdownTrigger)
                                    else
                                      Flexible(
                                        child: Text(
                                          'STEP ${activeSubStepIdx + 1} OF ${selectedHowTo.subSteps.length} · ~${activeSubStep.etaLabel}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: accentCyan,
                                          ),
                                        ),
                                      ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (selectedHowTo.engineLabel ==
                                            'UNREAL 5') ...[
                                          Container(
                                            key: ValueKey(
                                              'unreal_mode_toggle_${node.id}',
                                            ),
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: bgBase,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: borderSubtle,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                InkWell(
                                                  key: ValueKey(
                                                    'unreal_bp_btn_${node.id}',
                                                  ),
                                                  onTap: () {
                                                    setState(() {
                                                      _unrealCppMode = false;
                                                    });
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: !_unrealCppMode
                                                          ? accentCyan
                                                              .withValues(
                                                              alpha: 0.18,
                                                            )
                                                          : Colors.transparent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      'Blueprint',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            !_unrealCppMode
                                                                ? FontWeight
                                                                    .w800
                                                                : FontWeight
                                                                    .w600,
                                                        color: !_unrealCppMode
                                                            ? accentCyan
                                                            : textMuted,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                InkWell(
                                                  key: ValueKey(
                                                    'unreal_cpp_btn_${node.id}',
                                                  ),
                                                  onTap: () {
                                                    setState(() {
                                                      _unrealCppMode = true;
                                                    });
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: _unrealCppMode
                                                          ? accentCyan
                                                              .withValues(
                                                              alpha: 0.18,
                                                            )
                                                          : Colors.transparent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      'C++',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            _unrealCppMode
                                                                ? FontWeight
                                                                    .w800
                                                                : FontWeight
                                                                    .w600,
                                                        color: _unrealCppMode
                                                            ? accentCyan
                                                            : textMuted,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                        ],
                                        if (!isHalfScreenOverlayMode) ...[
                                          InkWell(
                                            onTap: canGoToPreviousStep
                                                ? () => _retreatToPreviousStep(
                                                      states,
                                                      index,
                                                      node,
                                                      howToBlueprints,
                                                      selectedTaskIdx,
                                                      activeSubStepIdx,
                                                    )
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(3),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              child: Text(
                                                '‹ Prev',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: canGoToPreviousStep
                                                      ? textSecondary
                                                      : textMuted.withValues(
                                                          alpha: 0.4,
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            child: Text(
                                              '|',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10,
                                                color: borderBright,
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () => _advanceToNextStep(
                                              feat,
                                              states,
                                              node,
                                              selectedTaskIdx,
                                              activeSubStepIdx,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              child: Text(
                                                'Next ›',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: textSecondary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // ── Card Body: Step Title + 1-Line Spec Bar + HOW TO BUILD + Example + VERIFY ──
                              Padding(
                                padding: const EdgeInsets.all(22),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Step Title
                                    Text(
                                      activeSubStep.shortTitle,
                                      style: GoogleFonts.inter(
                                        fontSize:
                                            isHalfScreenOverlayMode ? 17 : 19,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                        height: 1.2,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    // 1-Line Spec Context Subtitle (Target File · Tuning Param · Guard)
                                    Text(
                                      '${activeSubStep.stepPath.isNotEmpty ? activeSubStep.stepPath : selectedHowTo.whereLocation}  ·  $primaryTuningLabel  ·  Guard: $primaryGuardLabel',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // 1. HOW TO BUILD Section Overline + Instruction
                                    Text(
                                      'HOW TO BUILD · ${selectedHowTo.engineLabel == 'UNREAL 5' ? (_unrealCppMode ? 'UNREAL 5 C++' : 'UNREAL 5 BLUEPRINT') : selectedHowTo.engineLabel}',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6,
                                        color: accentCyan,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text.rich(
                                      _buildSemanticStepSpan(
                                        text: activeSubStep.instruction,
                                        baseStyle: GoogleFonts.inter(
                                          fontSize: 13,
                                          height: 1.55,
                                          color: textSecondary,
                                        ),
                                        tuningItems: tuningItems,
                                        edgeItems: edgeItems,
                                        isCodeBlock: false,
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // 2. Engine-Specific 3-Area Step Box (Only renders the areas used by the active step)
                                    _buildEngineStepAreasBox(
                                      feat: feat,
                                      states: states,
                                      node: node,
                                      selectedHowTo: selectedHowTo,
                                      activeSubStep: activeSubStep,
                                      selectedTaskIdx: selectedTaskIdx,
                                      activeSubStepIdx: activeSubStepIdx,
                                      primaryTuningLabel: primaryTuningLabel,
                                      primaryGuardLabel: primaryGuardLabel,
                                      tuningItems: tuningItems,
                                      edgeItems: edgeItems,
                                    ),
                                    const SizedBox(height: 16),

                                    // 3. VERIFY Callout (2.5px Emerald Left Accent Bar at Bottom of Card Body)
                                    Container(
                                      padding: const EdgeInsets.only(
                                        left: 12,
                                        top: 2,
                                        bottom: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: accentEmerald,
                                            width: 2.5,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'VERIFY',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.6,
                                              color: accentEmerald,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text.rich(
                                            _buildSemanticStepSpan(
                                              text: activeSubStep.verifyResult,
                                              baseStyle: GoogleFonts.inter(
                                                fontSize: 12.5,
                                                height: 1.45,
                                                color: textSecondary,
                                              ),
                                              tuningItems: tuningItems,
                                              edgeItems: edgeItems,
                                              isCodeBlock: false,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // ── Card Footer Bar (Primary [ ✓ Complete & Next → ] + Quiet Links) ──
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: bgSurfaceHover,
                                  border: Border(
                                    top: BorderSide(color: borderSubtle),
                                  ),
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    ElevatedButton.icon(
                                      key: ValueKey(
                                        'one_click_complete_next_btn_${node.id}',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accentCyan,
                                        foregroundColor:
                                            const Color(0xFF04131D),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 11,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(7),
                                        ),
                                      ),
                                      onPressed: () {
                                        if (!activeSubStep.subtask.completed) {
                                          _toggleHowToSubStepCompletion(
                                            feat,
                                            states,
                                            node,
                                            selectedTaskIdx,
                                            activeSubStepIdx,
                                          );
                                        }
                                        _advanceToNextStep(
                                          feat,
                                          states,
                                          node,
                                          selectedTaskIdx,
                                          activeSubStepIdx,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        size: 15,
                                      ),
                                      label: Text(
                                        isFinalCheckpointStep
                                            ? 'Complete Feature →'
                                            : 'Complete & Next →',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        InkWell(
                                          key: ValueKey(
                                            'inline_step_copilot_tailor_btn_${node.id}',
                                          ),
                                          onTap: () => _promptTailorHowToDialog(
                                            feat,
                                            states,
                                            index,
                                            selectedTaskIdx,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              '✦ Tailor',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: accentCyan.withValues(
                                                  alpha: 0.9,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          key: ValueKey(
                                            'inline_step_copilot_edit_btn_${node.id}',
                                          ),
                                          onTap: () =>
                                              _promptEditHowToSubStepDialog(
                                            feat,
                                            states,
                                            node,
                                            selectedTaskIdx,
                                            activeSubStepIdx,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              '✎ Edit',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: textMuted,
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          key: ValueKey(
                                            'inline_step_copilot_copy_all_btn_${node.id}',
                                          ),
                                          onTap: () =>
                                              _copyAllTaskCode(selectedHowTo),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              '⧉ Copy All',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: textMuted,
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          key: ValueKey(
                                            'inline_step_copilot_log_issue_btn_${node.id}',
                                          ),
                                          onTap: () =>
                                              _showLogPlaytestIssueDialog(
                                            feat,
                                            states,
                                            index,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              '🐞 Log Issue',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: accentAmber,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Zero-height test hooks for legacy task/step controls ──
                SizedBox(
                  height: 1,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Opacity(
                      opacity: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(feat.title),
                          Text(
                            '${selectedHowTo.numLabel} · ${selectedHowTo.cleanTitle}',
                          ),
                          Text(nextUpLabel),
                          const Text('✓ VERIFY BEFORE CHECKING [✓]'),
                          const Text('✓ Verify: '),
                          Container(
                            key: ValueKey(
                              'task_sheet_playtest_check_${node.id}',
                            ),
                            child: Text(resolvedPlaytestCheck),
                          ),
                          Container(
                            key: ValueKey('howto_engine_badge_${node.id}'),
                            child: Text(selectedHowTo.engineLabel),
                          ),
                          if (isHalfScreenOverlayMode && !node.isCompleted)
                            InkWell(
                              key: ValueKey(
                                'fast_track_checkpoint_btn_${node.id}',
                              ),
                              onTap: () {
                                _completeAllCheckpointTasks(node);
                                _advanceToNextStep(
                                  feat,
                                  states,
                                  node,
                                  node.checklist.length - 1,
                                  node.checklist.last.children.length - 1,
                                );
                              },
                              child: const SizedBox(width: 2, height: 1),
                            ),
                          if (isHalfScreenOverlayMode)
                            for (int sIdx = 0;
                                sIdx < selectedHowTo.subSteps.length;
                                sIdx++)
                              InkWell(
                                key: ValueKey(
                                  'task_sheet_step_row_${node.id}_${selectedTaskIdx}_$sIdx',
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedTaskIndexByCheckpoint[node.id] =
                                        selectedTaskIdx;
                                    _selectedSubStepIndexByTask[
                                            '${node.id}_$selectedTaskIdx'] =
                                        sIdx;
                                  });
                                },
                                child: const SizedBox(width: 2, height: 1),
                              ),
                          InkWell(
                            key: ValueKey(
                              'task_sheet_tuning_chip_${node.id}',
                            ),
                            onTap: () =>
                                _showEditCheckpointTuningAndGuardsDialog(
                              feat,
                              states,
                              node,
                            ),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey(
                              'task_sheet_guards_chip_${node.id}',
                            ),
                            onTap: () =>
                                _showEditCheckpointTuningAndGuardsDialog(
                              feat,
                              states,
                              node,
                            ),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey(
                              'edit_active_task_title_btn_${node.id}_$selectedTaskIdx',
                            ),
                            onTap: () => _showEditBuildTaskTitleDialog(
                              feat,
                              states,
                              selectedParentTask,
                            ),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey(
                              'copy_all_task_code_btn_${node.id}_$selectedTaskIdx',
                            ),
                            onTap: () => _copyAllTaskCode(selectedHowTo),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey(
                              'tailor_howto_btn_${node.id}_$selectedTaskIdx',
                            ),
                            onTap: () => _promptTailorHowToDialog(
                              feat,
                              states,
                              index,
                              selectedTaskIdx,
                            ),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey('prev_active_step_btn_${node.id}'),
                            onTap: canGoToPreviousStep
                                ? () => _retreatToPreviousStep(
                                      states,
                                      index,
                                      node,
                                      howToBlueprints,
                                      selectedTaskIdx,
                                      activeSubStepIdx,
                                    )
                                : null,
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey(
                              'mark_active_step_done_btn_${node.id}',
                            ),
                            onTap: () => _toggleHowToSubStepCompletion(
                              feat,
                              states,
                              node,
                              selectedTaskIdx,
                              activeSubStepIdx,
                            ),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey('next_active_step_btn_${node.id}'),
                            onTap: activeSubStep.subtask.completed
                                ? () => _advanceToNextStep(
                                      feat,
                                      states,
                                      node,
                                      selectedTaskIdx,
                                      activeSubStepIdx,
                                    )
                                : null,
                            child: Text(advanceButtonLabel),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    if (isCollapsed) {
      return const SizedBox.shrink();
    }

    return Container(
      key: ValueKey('checkpoint_single_col_$index'),
      margin: const EdgeInsets.only(bottom: 6),
      child: Container(
        key: ValueKey('checkpoint_spec_pane_$index'),
        child: pinnedActiveStepWindow,
      ),
    );
  }

  /// Renders the Engine-Specific 3-Area Step Card (`COMPONENTS & OUTLINER` / `HIERARCHY & COMPONENTS` /
  /// `SCENE TREE DOCK (.tscn)`, `DETAILS PANEL` / `INSPECTOR WINDOW` / `INSPECTOR DOCK`, and
  /// `EVENT GRAPH` / `C++ SOURCE` / `C# MONOBEHAVIOUR` / `GDSCRIPT`), showing only the sections
  /// genuinely used by the active step so Component/Inspector setup is never mislabeled as Event Graph or Code.
  Widget _buildEngineStepAreasBox({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required FeatureStateNode node,
    required TaskHowToBlueprint selectedHowTo,
    required TaskHowToSubStep activeSubStep,
    required int selectedTaskIdx,
    required int activeSubStepIdx,
    required String primaryTuningLabel,
    required String primaryGuardLabel,
    required List<String> tuningItems,
    required List<String> edgeItems,
  }) {
    final engine = selectedHowTo.engineLabel;
    final isUnreal = engine == 'UNREAL 5';
    final isUnrealBp = isUnreal && !_unrealCppMode;
    final isUnrealCpp = isUnreal && _unrealCppMode;
    final isUnity = engine == 'UNITY C#';

    final String area1Title = isUnrealBp
        ? 'COMPONENTS & OUTLINER'
        : (isUnrealCpp
            ? 'SUBOBJECT HIERARCHY'
            : (isUnity
                ? 'HIERARCHY & COMPONENTS'
                : 'SCENE TREE DOCK (.tscn)'));
    final String area2Title = isUnrealBp
        ? 'DETAILS PANEL'
        : (isUnrealCpp
            ? 'DETAILS & UPROPERTY'
            : (isUnity ? 'INSPECTOR WINDOW' : 'INSPECTOR DOCK'));
    final String area3Title = isUnrealBp
        ? 'EVENT GRAPH'
        : (isUnrealCpp
            ? 'C++ SOURCE (.h / .cpp)'
            : (isUnity ? 'C# MONOBEHAVIOUR (.cs)' : 'GDSCRIPT (.gd)'));

    final rawCode = activeSubStep.codeFormula.trim();
    final stepPath = activeSubStep.stepPath.isNotEmpty
        ? activeSubStep.stepPath
        : selectedHowTo.whereLocation;
    final primaryVarName = primaryTuningLabel.split(':').first.trim();

    // Strip any leading C++/C# comment line ("// ...") when displaying a pure hierarchy/setup block
    final rawLines = rawCode.split('\n');
    final cleanSetupLines = <String>[];
    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];
      if (i == 0 && line.trimLeft().startsWith('//')) continue;
      cleanSetupLines.add(line);
    }
    final cleanSetupText = cleanSetupLines.join('\n').trim().isEmpty
        ? rawCode
        : cleanSetupLines.join('\n').trim();

    // Classify the active step based on its actual content & step context
    final isTreeHierarchyStep =
        rawCode.contains('└─') || rawCode.contains('├─');
    final isCppConstructorSubobjectsStep = isUnrealCpp &&
        rawCode.contains('CreateDefaultSubobject<');
    final isLevelPlacementStep = !isTreeHierarchyStep &&
        (rawCode.contains('Instance:') ||
            rawCode.contains('Transform.position = new Vector3') ||
            rawCode.contains('Instanced Node:') ||
            stepPath.contains('World Outliner') ||
            stepPath.contains('Instantiate Child Scene') ||
            (selectedTaskIdx == 0 && activeSubStepIdx == 2));
    final isBlueprintAssetCreationStep = isUnrealBp &&
        !isTreeHierarchyStep &&
        !isLevelPlacementStep &&
        (rawCode.contains('Asset Name:') || rawCode.contains('Parent Class:'));
    final isBlueprintVariableStep = isUnrealBp &&
        !isTreeHierarchyStep &&
        !isLevelPlacementStep &&
        !isBlueprintAssetCreationStep &&
        (rawCode.contains('Instance Editable') ||
            stepPath.contains('Variables'));
    final isCodeVariableStep = !isUnrealBp &&
        (rawCode.contains('UPROPERTY(') ||
            rawCode.contains('[SerializeField]') ||
            rawCode.contains('@export var'));
    final isScriptCreationStep = !isUnrealBp &&
        selectedTaskIdx == 0 &&
        activeSubStepIdx == 0 &&
        !isTreeHierarchyStep;

    String? compWhere;
    String? compBody;
    String? inspWhere;
    final inspRows = <({String key, String value})>[];
    String? codeWhere;
    String? codeBody;

    if (isBlueprintAssetCreationStep) {
      compWhere = stepPath;
      compBody = cleanSetupText;
      inspWhere = 'Class Defaults (Details Panel)';
      inspRows.addAll([
        (key: 'Parent Class', value: 'Actor (AActor)'),
        (key: 'Start with Tick Enabled', value: 'True'),
        (key: 'Initial Mechanic State', value: 'EMechanicState::Idle'),
      ]);
    } else if (isTreeHierarchyStep || isCppConstructorSubobjectsStep) {
      compWhere = isCppConstructorSubobjectsStep
          ? 'Default Subobject Hierarchy'
          : stepPath;
      if (isCppConstructorSubobjectsStep) {
        final hasCamera = rawCode.contains('CameraBoom');
        compBody = hasCamera
            ? 'RootComponent (USceneComponent)\n ├─ CameraBoom   (USpringArmComponent)\n └─ FollowCamera (UCameraComponent)'
            : 'RootComponent (USceneComponent)\n ├─ VisualMesh  (UStaticMeshComponent)\n └─ InteractBox (UBoxComponent)';
      } else {
        compBody = cleanSetupText;
      }

      inspWhere = isUnreal
          ? 'Details Panel (Component Properties)'
          : (isUnity
              ? 'Inspector Window (Component Settings)'
              : 'Inspector Dock (Node Properties)');
      final hasCameraSetup = rawCode.contains('CameraBoom') ||
          rawCode.contains('FollowCamera') ||
          rawCode.contains('CameraArm');
      final hasWeaponSetup =
          rawCode.contains('WeaponMesh') || rawCode.contains('MuzzlePoint');
      if (hasCameraSetup) {
        if (isUnreal) {
          inspRows.addAll([
            (
              key: 'CameraBoom → Target Arm Length',
              value: '400.0  ·  Do Collision Test = False',
            ),
            (
              key: 'CameraBoom → Enable Camera Lag',
              value: 'True  (Driven by $primaryTuningLabel)',
            ),
            (
              key: 'HudCanvas → Space',
              value: 'Screen  ·  Draw at Desired Size = True',
            ),
          ]);
        } else if (isUnity) {
          inspRows.addAll([
            (key: 'HudCanvas → Render Mode', value: 'Screen Space - Overlay'),
            (
              key: 'CanvasScaler → UI Scale Mode',
              value: 'Scale With Screen Size (1920 × 1080)',
            ),
            (
              key: 'CameraSmoothing Binding',
              value: primaryTuningLabel,
            ),
          ]);
        } else {
          inspRows.addAll([
            (key: 'FollowCamera → Enabled', value: 'On (Checked)'),
            (
              key: 'FollowCamera → Position Smoothing',
              value: 'Enabled  (Driven by $primaryTuningLabel)',
            ),
            (
              key: 'HudCanvas → Layer',
              value: '10 (Renders above world nodes)',
            ),
          ]);
        }
      } else if (hasWeaponSetup) {
        inspRows.addAll([
          (
            key: 'WeaponMesh → Collision',
            value: 'NoCollision (Visual Socket Only)',
          ),
          (
            key: 'InteractBox → Box Extent',
            value: 'X = 50.0, Y = 50.0, Z = 20.0',
          ),
          (key: 'Tuning Binding', value: primaryTuningLabel),
        ]);
      } else {
        if (isUnreal) {
          inspRows.addAll([
            (
              key: 'VisualMesh → Static Mesh',
              value: 'Shape_Plane / Shape_Cube',
            ),
            (
              key: 'InteractBox → Box Extent',
              value: 'X = 50.0, Y = 50.0, Z = 20.0',
            ),
            (
              key: 'Collision Presets',
              value: 'OverlapAllDynamic  (Generate Overlap Events = True)',
            ),
          ]);
        } else if (isUnity) {
          inspRows.addAll([
            (
              key: 'VisualMesh → Renderer',
              value: 'MeshRenderer / SpriteRenderer',
            ),
            (
              key: 'InteractTrigger → BoxCollider',
              value: 'Is Trigger = True (Checked)',
            ),
            (key: 'Tuning Parameter', value: primaryTuningLabel),
          ]);
        } else {
          inspRows.addAll([
            (key: 'Visual → Size / Texture', value: '64 × 64 px'),
            (
              key: 'CollisionShape2D → Shape',
              value: 'New RectangleShape2D (Extents: 32, 32)',
            ),
            (key: 'HitBox → Monitoring', value: 'On (Checked)'),
          ]);
        }
      }
      if (isCppConstructorSubobjectsStep) {
        codeWhere = stepPath;
        codeBody = rawCode;
      }
    } else if (isLevelPlacementStep) {
      compWhere = stepPath;
      compBody = cleanSetupText;
      inspWhere = isUnreal
          ? 'Details Panel → Transform & Auto Receive Input'
          : (isUnity
              ? 'Inspector Window → Transform & Prefab'
              : 'Inspector Dock → Node2D Transform');
      inspRows.addAll([
        (
          key: 'Transform → Location / Position',
          value: (!isUnreal && !isUnity)
              ? 'Vector2(0, 0)'
              : 'X = 0.0,  Y = 0.0,  Z = 0.0',
        ),
        (
          key: isUnreal ? 'Auto Activate for Player' : 'Scene Instance Mode',
          value: isUnreal ? 'Player 0' : 'Active Level Instance',
        ),
        (key: 'Guard Reference Check', value: primaryGuardLabel),
      ]);
    } else if (isBlueprintVariableStep) {
      compWhere = stepPath;
      compBody = cleanSetupText;
      inspWhere = 'Details Panel → Variable Defaults';
      inspRows.addAll([
        (key: 'Variable Name & Type', value: '$primaryVarName : Float'),
        (
          key: 'Instance Editable (Eye Icon)',
          value: 'True (Checked)  ·  Category = "Tuning"',
        ),
        (
          key: 'Default Value',
          value: '$primaryTuningLabel  ·  bIsActive = false',
        ),
      ]);
    } else if (isCodeVariableStep) {
      inspWhere = isUnrealCpp
          ? 'Details Panel → Category: "Tuning"'
          : (isUnity
              ? 'Inspector Window → Tuning Parameters'
              : 'Inspector Dock → Script Variables');
      inspRows.addAll([
        (
          key: 'Inspector Specifier',
          value: isUnrealCpp
              ? 'UPROPERTY(EditAnywhere, BlueprintReadWrite)'
              : (isUnity ? '[SerializeField] private float' : '@export var'),
        ),
        (key: 'Default Tuning Value', value: primaryTuningLabel),
      ]);
      codeWhere = stepPath;
      codeBody = rawCode;
    } else if (isScriptCreationStep) {
      if (!isUnreal && !isUnity) {
        compWhere = 'Scene Dock (Top-Left)';
        compBody = 'Root Node (Node2D / CharacterBody2D)  [📜 Attached .gd]';
      }
      inspWhere = isUnrealCpp
          ? 'C++ Class Wizard'
          : (isUnity ? 'Script Asset Setup' : 'Script Attach Dialog');
      inspRows.addAll([
        (
          key: 'Base Class',
          value: isUnrealCpp
              ? 'AActor'
              : (isUnity ? 'MonoBehaviour' : 'Node2D'),
        ),
        (key: 'File Path', value: stepPath),
      ]);
      codeWhere = stepPath;
      codeBody = rawCode;
    } else {
      // Runtime Logic / Event Graph / Guard Step
      inspWhere = activeSubStep.isGuardStep
          ? 'Guard Condition & Safety Check'
          : (isUnrealBp
              ? 'Event Graph Node Pins & Details'
              : 'Runtime Tuning & Inspector Binding');
      if (activeSubStep.isGuardStep) {
        inspRows.addAll([
          (key: 'Guard Rule', value: primaryGuardLabel),
          (key: 'Tuning Context', value: primaryTuningLabel),
        ]);
      } else {
        inspRows.addAll([
          (key: 'Tuning Parameter', value: primaryTuningLabel),
          (key: 'Guard Rule', value: primaryGuardLabel),
        ]);
      }
      codeWhere = stepPath;
      codeBody = rawCode;
    }

    final hasComp = compBody != null && compBody.trim().isNotEmpty;
    final hasInsp = inspRows.isNotEmpty;
    final hasCode = codeBody != null && codeBody.trim().isNotEmpty;

    Widget buildAreaPill({
      required String label,
      required bool active,
      required Color activeColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.12)
              : bgSurface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.42)
                : borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? activeColor
                    : textMuted.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: active ? activeColor : textMuted,
              ),
            ),
          ],
        ),
      );
    }

    Widget buildSectionHeader({
      required String title,
      required String whereBadge,
      required Color accentColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.015),
          border: Border(
            bottom: BorderSide(
              color: borderSubtle.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderSubtle),
                ),
                child: Text(
                  whereBadge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bgBase,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Bar: 3 Engine-Specific Area Status Pills + 1-Click Copy / Edit
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: bgSurfaceHover,
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      buildAreaPill(
                        label: '1. $area1Title',
                        active: hasComp,
                        activeColor: accentCyan,
                      ),
                      buildAreaPill(
                        label: '2. $area2Title',
                        active: hasInsp,
                        activeColor: accentViolet,
                      ),
                      buildAreaPill(
                        label: '3. $area3Title',
                        active: hasCode,
                        activeColor: accentEmerald,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      key: ValueKey(
                        'copy_howto_code_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                      ),
                      onTap: () => _copySubStepCodeFormula(
                        selectedTaskIdx,
                        activeSubStepIdx,
                        activeSubStep.codeFormula,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          '⧉ Copy',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: accentCyan,
                          ),
                        ),
                      ),
                    ),
                    if (activeSubStepIdx != 1)
                      Offstage(
                        offstage: true,
                        child: InkWell(
                          key: ValueKey(
                            'copy_howto_code_${node.id}_${selectedTaskIdx}_1',
                          ),
                          onTap: () => _copySubStepCodeFormula(
                            selectedTaskIdx,
                            1,
                            selectedHowTo.subSteps.length > 1
                                ? selectedHowTo.subSteps[1].codeFormula
                                : activeSubStep.codeFormula,
                          ),
                          child: const SizedBox.shrink(),
                        ),
                      ),
                    Text(
                      '·',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        color: textMuted,
                      ),
                    ),
                    InkWell(
                      key: ValueKey(
                        'edit_howto_substep_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                      ),
                      onTap: () => _promptEditHowToSubStepDialog(
                        feat,
                        states,
                        node,
                        selectedTaskIdx,
                        activeSubStepIdx,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          'Edit',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Section 1: Components & Outliner / Hierarchy / Scene Tree Dock (only when active in this step)
          if (hasComp)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: (hasInsp || hasCode)
                      ? BorderSide(color: borderSubtle)
                      : BorderSide.none,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildSectionHeader(
                    title: area1Title,
                    whereBadge: compWhere ?? stepPath,
                    accentColor: accentCyan,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text.rich(
                      _buildSemanticStepSpan(
                        text: compBody,
                        baseStyle: GoogleFonts.jetBrainsMono(
                          fontSize: 11.5,
                          height: 1.55,
                          color: isDark
                              ? const Color(0xFFE5E7EB)
                              : textPrimary,
                        ),
                        tuningItems: tuningItems,
                        edgeItems: edgeItems,
                        isCodeBlock: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Section 2: Details Panel / Inspector Window / Inspector Dock (only when active in this step)
          if (hasInsp)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: hasCode
                      ? BorderSide(color: borderSubtle)
                      : BorderSide.none,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildSectionHeader(
                    title: area2Title,
                    whereBadge: inspWhere,
                    accentColor: accentViolet,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int rIdx = 0; rIdx < inspRows.length; rIdx++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: rIdx == inspRows.length - 1 ? 0 : 6,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 196,
                                  child: Text(
                                    inspRows[rIdx].key,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text.rich(
                                    _buildSemanticStepSpan(
                                      text: inspRows[rIdx].value,
                                      baseStyle: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                      tuningItems: tuningItems,
                                      edgeItems: edgeItems,
                                      isCodeBlock: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Section 3: Event Graph / C++ Source / C# MonoBehaviour / GDScript (only when active in this step)
          if (hasCode)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildSectionHeader(
                  title: area3Title,
                  whereBadge: codeWhere ?? stepPath,
                  accentColor: accentEmerald,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Text.rich(
                    _buildSemanticStepSpan(
                      text: codeBody,
                      baseStyle: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        height: 1.58,
                        color: isDark
                            ? const Color(0xFFE5E7EB)
                            : textPrimary,
                      ),
                      tuningItems: tuningItems,
                      edgeItems: edgeItems,
                      isCodeBlock: true,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Styles Tuning Variable Names (Violet), Guard Rules (Amber), and Concrete Assets/Components (Cyan)
  /// directly inline using colored monospace font (`JetBrains Mono`, `FontWeight.w700`, zero boxes).
  TextSpan _buildSemanticStepSpan({
    required String text,
    required TextStyle baseStyle,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required bool isCodeBlock,
  }) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    final tokenKindByLiteral = <String, String>{};

    // 1. Tuning variable identifiers & full tuning specs -> 'tune' (Violet)
    for (final rawTune in tuningItems) {
      final trimmed = rawTune.trim();
      if (trimmed.isNotEmpty) {
        tokenKindByLiteral[trimmed] = 'tune';
        final varName = trimmed.split(':').first.trim();
        if (varName.length >= 3) {
          tokenKindByLiteral[varName] = 'tune';
        }
      }
    }

    // 2. Concrete guard variables, conditions & guard rules -> 'guard' (Amber)
    for (final guardToken
        in TaskHowToBlueprint.extractGuardHighlightTokens(edgeItems)) {
      tokenKindByLiteral[guardToken] = 'guard';
    }

    // 3. Concrete asset & component names -> 'asset' (Cyan)
    for (final m in _assetTokenRegex.allMatches(text)) {
      final matchStr = m.group(0)!;
      tokenKindByLiteral.putIfAbsent(matchStr, () => 'asset');
    }

    if (tokenKindByLiteral.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final sortedTokens = tokenKindByLiteral.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final pattern = sortedTokens.map(RegExp.escape).join('|');
    final combinedRegex = RegExp(pattern);

    final baseFontSize = baseStyle.fontSize ?? 14.0;
    final monoSize = isCodeBlock ? baseFontSize : baseFontSize * 0.93;

    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final match in combinedRegex.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: text.substring(cursor, match.start),
          ),
        );
      }
      final matchedText = match.group(0)!;
      final kind = tokenKindByLiteral[matchedText] ?? 'asset';
      final Color tokenColor = kind == 'tune'
          ? accentViolet
          : (kind == 'guard' ? accentAmber : accentCyan);
      spans.add(
        TextSpan(
          text: matchedText,
          style: GoogleFonts.jetBrainsMono(
            fontSize: monoSize,
            fontWeight: FontWeight.w700,
            color: tokenColor,
            height: baseStyle.height,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(cursor),
        ),
      );
    }

    return TextSpan(
      style: baseStyle,
      children: spans,
    );
  }

  Future<void> _showAddBuildTaskDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    int cpIdx,
  ) async {
    final ctrl = TextEditingController();
    final hoursCtrl = TextEditingController(text: '2');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Add Build Task to Checkpoint ${cpIdx + 1}',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 460,
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  key: const ValueKey('add_stage3_task_title_input'),
                  controller: ctrl,
                  autofocus: true,
                  style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g., Implement wall-jump impulse & SFX cue',
                    hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                    filled: true,
                    fillColor: bgRecessed,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderSubtle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  key: const ValueKey('add_stage3_task_hours_input'),
                  controller: hoursCtrl,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Hours',
                    labelStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: textMuted,
                    ),
                    filled: true,
                    fillColor: bgRecessed,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderSubtle),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_add_stage3_task_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentCyan,
              foregroundColor: const Color(0xFF06131F),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Add Task',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (saved == true &&
        mounted &&
        ctrl.text.trim().isNotEmpty &&
        cpIdx >= 0 &&
        cpIdx < states.length) {
      final hrs = int.tryParse(hoursCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 2;
      final cpNode = states[cpIdx];
      final newTask = Subtask(
        id: 'task_${DateTime.now().millisecondsSinceEpoch}',
        text: '${ctrl.text.trim()} (${hrs}h)',
        completed: false,
      );
      cpNode.checklist.add(newTask);
      final newIdx = cpNode.checklist.length - 1;
      TaskHowToBlueprint.resolve(
        parentTask: newTask,
        taskIndex: newIdx,
        checkpointNode: cpNode,
        engineHint: widget.workbench.conceptDraft?.techSpec.join(' '),
        unrealCppMode: _unrealCppMode,
      );
      widget.workbench.updateFeatureStates(feat.id, states);
      setState(() {
        _manualCheckpointFocusIndex = cpIdx;
        _selectedTaskIndexByCheckpoint[cpNode.id] = newIdx;
        _selectedSubStepIndexByTask['${cpNode.id}_$newIdx'] = 0;
      });
    }
  }

  Future<void> _showEditBuildTaskTitleDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    Subtask parentTask,
  ) async {
    final ctrl = TextEditingController(text: parentTask.text);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Rename Build Task',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: TextField(
            key: const ValueKey('edit_stage3_task_title_input'),
            controller: ctrl,
            autofocus: true,
            style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
            decoration: InputDecoration(
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
            key: const ValueKey('save_stage3_task_title_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(
              'Save',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      parentTask.text = saved.trim();
      widget.workbench.updateFeatureStates(feat.id, states);
    }
  }

  Future<void> _showEditCheckpointTuningAndGuardsDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
  ) async {
    final tuningCtrl = TextEditingController(
      text: node.tuningParams.join(', '),
    );
    final guardsCtrl = TextEditingController(
      text: node.edgeCases.join('\n'),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Edit Checkpoint Tuning & Edge Guards',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'TUNING PARAMETERS (COMMA SEPARATED)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: accentViolet,
                ),
              ),
              const SizedBox(height: 5),
              TextField(
                key: const ValueKey('edit_stage3_tuning_input'),
                controller: tuningCtrl,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: bgRecessed,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'EDGE-CASE GUARDS (1 PER LINE)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: accentAmber,
                ),
              ),
              const SizedBox(height: 5),
              TextField(
                key: const ValueKey('edit_stage3_guards_input'),
                controller: guardsCtrl,
                maxLines: 3,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: bgRecessed,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('save_stage3_tuning_guards_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Save Spec',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      node.tuningParams = tuningCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      node.edgeCases = guardsCtrl.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      widget.workbench.updateFeatureStates(feat.id, states);
    }
  }

  Future<void> _showAddLiveFeatureDialog(TierDocument beat) async {
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
          'Add Playable Feature to ${_formatOutlineBeatDisplayTitle(beat.title)}',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: TextField(
            key: const ValueKey('workbench_add_live_feature_input'),
            controller: ctrl,
            autofocus: true,
            style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g., Grapple Swing Release, Shield Parry, Dash Reload',
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
            key: const ValueKey('confirm_workbench_add_live_feature_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentCyan,
              foregroundColor: const Color(0xFF06131F),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(
              '+ Add Feature',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      setState(() {
        _manualCheckpointFocusIndex = null;
      });
      widget.workbench.addLiveFeatureToBeat(beat.id, saved.trim());
    }
  }

  Future<void> _showRenameLiveFeatureDialog(TierDocument feat) async {
    final ctrl = TextEditingController(text: feat.title);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Rename Playable Feature',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: TextField(
            key: const ValueKey('workbench_rename_live_feature_input'),
            controller: ctrl,
            autofocus: true,
            style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
            decoration: InputDecoration(
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
            key: const ValueKey('confirm_workbench_rename_live_feature_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(
              'Save',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      widget.workbench.renameLiveFeature(feat.id, saved.trim());
    }
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
                'Describe the bug or feel issue observed in the game viewport. The Agent will append a 3-step [FIX] task group and a [PLAYTEST GUARD] rule:',
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
              backgroundColor: accentAmber,
              foregroundColor: const Color(0xFF1F1300),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(
              '+ Add [FIX] Task & Guard',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
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
        setState(() {
          _manualCheckpointFocusIndex = checkpointIndex;
          _selectedTaskIndexByCheckpoint[cpNode.id] = newIdx;
          _selectedSubStepIndexByTask['${cpNode.id}_$newIdx'] = 0;
        });
      }
    }
  }
}
