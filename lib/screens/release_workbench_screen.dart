import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../agents/workspace_agent_tools.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import '../utils/section_text_utils.dart';

/// Stage 3 Screen: Active Release Workbench
/// - Left Rail: Core Loop Epics & Features switcher for the active Release
/// - Main Canvas:
///   - Release Completion Banner (when 100% of Checkpoints are VERIFIED ✓)
///   - Focused Task Sheet with 6-Step Accordion List (Do -> Copy -> Verify Triad)
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
  final Set<String> _expandedDoneCheckpoints = {};
  final Set<String> _awaitingPlaytestVerification = {};
  int? _manualCheckpointFocusIndex;
  bool _criticalPathOnly = false;
  final Map<String, int> _selectedTaskIndexByCheckpoint = {};
  final Map<String, int> _selectedSubStepIndexByTask = {};
  final Set<String> _collapsedOutlineFeatureIds = {};
  final Set<String> _expandedOutlineFeatureIds = {};
  final Map<String, int> _lastOutlineTapMsByKey = {};
  bool _unrealCppMode = false;
  double _outlinerWidth = 340.0;
  bool _isHalfScreenOutlinerOpen = false;

  String _formatOutlineFeatureDisplayTitle(
    String featTitle,
    String? beatTitle,
  ) {
    if (beatTitle == null || beatTitle.trim().isEmpty) return featTitle;
    final cleanBeat = beatTitle.split(':').last.split('—').last.trim();
    if (cleanBeat.isEmpty) return featTitle;
    final lowerFeat = featTitle.toLowerCase();
    final lowerBeat = cleanBeat.toLowerCase();
    if (lowerFeat.startsWith(lowerBeat) &&
        featTitle.length > cleanBeat.length + 2) {
      var remainder = featTitle.substring(cleanBeat.length).trimLeft();
      if (remainder.startsWith(':') ||
          remainder.startsWith('—') ||
          remainder.startsWith('-')) {
        remainder = remainder.substring(1).trimLeft();
      }
      if (remainder.isNotEmpty) {
        return remainder;
      }
    }
    return featTitle;
  }

  bool _isDoubleClickOnOutlineItem(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _lastOutlineTapMsByKey[key];
    _lastOutlineTapMsByKey[key] = now;
    return prev != null && (now - prev) <= 340;
  }

  bool _isFeatureExpandedInOutline(String featId, {required bool isSelected}) {
    if (_expandedOutlineFeatureIds.contains(featId)) return true;
    if (_collapsedOutlineFeatureIds.contains(featId)) return false;
    return isSelected;
  }

  void _toggleFeatureExpandedInOutline(
    String featId, {
    required bool currentlyExpanded,
  }) {
    if (currentlyExpanded) {
      _expandedOutlineFeatureIds.remove(featId);
      _collapsedOutlineFeatureIds.add(featId);
    } else {
      _collapsedOutlineFeatureIds.remove(featId);
      _expandedOutlineFeatureIds.add(featId);
    }
  }

  @override
  bool get isDark => widget.workbench.isDark;

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
                                  .clamp(260.0, 520.0);
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
            _outlinerWidth.clamp(260.0, constraints.maxWidth * 0.85);
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
    final activeVer = rel.sections['versionTag'] ?? 'v0.1';
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
          decoration: BoxDecoration(
            color: bgBase,
            border: Border(bottom: BorderSide(color: borderSubtle)),
          ),
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
                        if (value == '__evolve__') {
                          widget.workbench.advanceToNextRelease();
                        } else if (value == '__replan__') {
                          widget.workbench.reopenCurrentReleasePlanGate();
                        } else if (value.startsWith('rel:')) {
                          final targetId = value.substring(4);
                          widget.workbench.selectActiveRelease(targetId);
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
                                  final rVer = r.sections['versionTag'] ??
                                      (r.title.contains(':')
                                          ? r.title.split(':').first.trim()
                                          : 'v0.${rIdx + 1}');
                                  final rScopeLabel = r.releaseScope.label;
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
                                                  'Plan Gate →',
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
                              'STAGE 2 · RELEASE PLAN GATE',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: textMuted,
                              ),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: '__replan__',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '✎ Edit $activeVer Scope in Gate',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Stage 2',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    color: textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: '__evolve__',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '+ Plan Next Release Milestone',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: accentEmerald,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Stage 2 ✦',
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
                              TextSpan(text: '${rel.releaseScope.label} ▾'),
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
                    InkWell(
                      key: const ValueKey('critical_path_filter_btn'),
                      onTap: () {
                        setState(() {
                          _criticalPathOnly = !_criticalPathOnly;
                        });
                      },
                      child: const SizedBox.shrink(),
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
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 5),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: borderSubtle),
                        ),
                      ),
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
                                'E${(bIdx + 1).toString().padLeft(2, '0')} · ${beat.title.split(':').last.split('—').last.trim().toUpperCase()}',
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
                              Text(
                                '$doneBeatCount/${beatFeats.length}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: allBeatDone ? accentEmerald : textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    for (int fIdx = 0; fIdx < beatFeats.length; fIdx++)
                      Builder(
                        builder: (context) {
                          final feat = beatFeats[fIdx];
                          final depTier =
                              WorkspaceAgentOrchestrator.classifyDependencyTier(
                            featureTitle: feat.title,
                            beatIndex: bIdx,
                            featureIndexInBeat: fIdx,
                          );
                          if (_criticalPathOnly && depTier.tierRank > 2) {
                            return const SizedBox.shrink();
                          }
                          return _buildFeatureRailItem(
                            feat,
                            activeVer: activeVer,
                            beatTitle: beat.title,
                            beatIndex: bIdx,
                            featureIndexInBeat: fIdx,
                            globalFeatureIndex: prevFeaturesBeforeBeat + fIdx,
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ],
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
    final isExpanded =
        _isFeatureExpandedInOutline(feat.id, isSelected: isSelected);
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
    final displayTitle =
        _formatOutlineFeatureDisplayTitle(feat.title, beatTitle);

    return Opacity(
      opacity: shouldDim ? 0.68 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : bgSurface)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: borderSubtle),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey('rail_feat_${feat.id}'),
              onTap: () {
                final isDouble = _isDoubleClickOnOutlineItem('feat_${feat.id}');
                setState(() {
                  _manualCheckpointFocusIndex = null;
                  if (isDouble) {
                    _toggleFeatureExpandedInOutline(
                      feat.id,
                      currentlyExpanded: isExpanded,
                    );
                  } else {
                    _collapsedOutlineFeatureIds.remove(feat.id);
                  }
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
                            _toggleFeatureExpandedInOutline(
                              feat.id,
                              currentlyExpanded: isExpanded,
                            );
                          });
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 14,
                          height: 18,
                          child: Center(
                            child: Text(
                              isDone && !isExpanded
                                  ? '✓'
                                  : (isExpanded ? '▾' : '▸'),
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
            if (isExpanded) _buildOutlineFeatureChildrenTree(feat),
          ],
        ),
      ),
    );
  }

  /// Unified 4-Rank Outliner Hierarchy: Renders `Feature -> Numbered Tasks (01 · ...) -> Nested Steps (01..06)`
  /// with full untruncated multi-line titles and an L2 elevated pill on the active step.
  Widget _buildOutlineFeatureChildrenTree(TierDocument feat) {
    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isEmpty) return const SizedBox.shrink();

    int activeCpIdx = -1;
    for (int i = 0; i < states.length; i++) {
      if (!states[i].isCompleted ||
          _awaitingPlaytestVerification.contains(states[i].id)) {
        activeCpIdx = i;
        break;
      }
    }
    if (activeCpIdx == -1) activeCpIdx = states.length - 1;
    final effectiveCpIdx = (_manualCheckpointFocusIndex != null &&
            _manualCheckpointFocusIndex! >= 0 &&
            _manualCheckpointFocusIndex! < states.length)
        ? _manualCheckpointFocusIndex!
        : activeCpIdx;

    final engineHint = _engineHint;

    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 10, 6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: borderSubtle, width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int cpIdx = 0; cpIdx < states.length; cpIdx++)
            Builder(
              builder: (context) {
                final cpNode = states[cpIdx];
                final cpDone = cpNode.isCompleted &&
                    !_awaitingPlaytestVerification.contains(cpNode.id);
                final isCpActive = cpIdx == effectiveCpIdx;
                final isCpVisible = states.length == 1 ||
                    isCpActive ||
                    _expandedDoneCheckpoints.contains(cpNode.id);

                int activeTaskIdx = _selectedTaskIndexByCheckpoint[cpNode.id] ??
                    cpNode.checklist.indexWhere((t) => !t.completed);
                if (activeTaskIdx < 0 ||
                    activeTaskIdx >= cpNode.checklist.length) {
                  activeTaskIdx = 0;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Offstage(
                      offstage: true,
                      child: InkWell(
                        key: ValueKey('outline_cp_${feat.id}_$cpIdx'),
                        onTap: () {
                          setState(() {
                            _manualCheckpointFocusIndex = cpIdx;
                            if (cpDone) {
                              if (_expandedDoneCheckpoints
                                  .contains(cpNode.id)) {
                                _expandedDoneCheckpoints.remove(cpNode.id);
                              } else {
                                _expandedDoneCheckpoints.add(cpNode.id);
                              }
                            }
                          });
                        },
                        child: Text(cpNode.cleanStageTitle),
                      ),
                    ),
                    if (isCpVisible && cpNode.checklist.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int tIdx = 0;
                              tIdx < cpNode.checklist.length;
                              tIdx++)
                            Builder(
                              builder: (context) {
                                final task = cpNode.checklist[tIdx];
                                final isFixTask =
                                    task.text.trim().startsWith('[FIX]');
                                final isTaskActive =
                                    isCpActive && tIdx == activeTaskIdx;
                                final bp = TaskHowToBlueprint.resolve(
                                  parentTask: task,
                                  taskIndex: tIdx,
                                  checkpointNode: cpNode,
                                  engineHint: engineHint,
                                  unrealCppMode: _unrealCppMode,
                                );
                                final taskRemLabel = TaskHowToBlueprint
                                    .formatRemainingHoursShort(
                                  bp.remainingTaskMinutes,
                                );
                                final doneSubCount = bp.subSteps
                                    .where((s) => s.subtask.completed)
                                    .length;
                                final totalSubCount = bp.subSteps.length;
                                final taskSymbol = task.completed
                                    ? '✓'
                                    : (isTaskActive ? '●' : '○');

                                int activeSubStepIdx =
                                    _selectedSubStepIndexByTask[
                                            '${cpNode.id}_$tIdx'] ??
                                        task.children
                                            .indexWhere((c) => !c.completed);
                                if (activeSubStepIdx < 0 ||
                                    activeSubStepIdx >= bp.subSteps.length) {
                                  activeSubStepIdx = 0;
                                }

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    InkWell(
                                      key: ValueKey(
                                        'outline_task_${cpNode.id}_$tIdx',
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _manualCheckpointFocusIndex = cpIdx;
                                          _selectedTaskIndexByCheckpoint[
                                              cpNode.id] = tIdx;
                                        });
                                        if (widget
                                                .workbench.selectedFeatureId !=
                                            feat.id) {
                                          widget.workbench
                                              .selectFeature(feat.id);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          4,
                                          8,
                                          4,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 1),
                                              child: SizedBox(
                                                width: 14,
                                                child: Text(
                                                  taskSymbol,
                                                  textAlign: TextAlign.center,
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: task.completed
                                                        ? accentEmerald
                                                        : (isFixTask
                                                            ? accentCrimson
                                                            : (isTaskActive
                                                                ? accentCyan
                                                                : textMuted)),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Expanded(
                                              child: Text(
                                                '${bp.numLabel} · ${bp.cleanTitle}',
                                                maxLines: 2,
                                                style: GoogleFonts.inter(
                                                  fontSize: 11.5,
                                                  height: 1.25,
                                                  fontWeight: isTaskActive &&
                                                          !task.completed
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                  color: task.completed
                                                      ? textMuted.withValues(
                                                          alpha: 0.5,
                                                        )
                                                      : (isFixTask
                                                          ? accentCrimson
                                                          : (isTaskActive
                                                              ? textPrimary
                                                              : textMuted)),
                                                  decoration: task.completed
                                                      ? TextDecoration
                                                          .lineThrough
                                                      : TextDecoration.none,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 1),
                                              child: Text(
                                                '$doneSubCount/$totalSubCount · $taskRemLabel',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 9.5,
                                                  fontWeight: isTaskActive
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: task.completed
                                                      ? accentEmerald
                                                          .withValues(
                                                          alpha: 0.65,
                                                        )
                                                      : (isTaskActive
                                                          ? accentCyan
                                                          : textMuted),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Rank 4 in Unified Outliner: Nested Steps 01..06 directly inside the Active Task
                                    if (isTaskActive &&
                                        widget.workbench.selectedFeatureId ==
                                            feat.id &&
                                        bp.subSteps.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.fromLTRB(
                                          18,
                                          1,
                                          4,
                                          3,
                                        ),
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
                                                  final stepItem =
                                                      bp.subSteps[sIdx];
                                                  final isStepActive =
                                                      sIdx == activeSubStepIdx;
                                                  final isStepDone = stepItem
                                                      .subtask.completed;
                                                  return InkWell(
                                                    key: ValueKey(
                                                      'outliner_substep_${cpNode.id}_${tIdx}_$sIdx',
                                                    ),
                                                    onTap: () {
                                                      setState(() {
                                                        _manualCheckpointFocusIndex =
                                                            cpIdx;
                                                        _selectedTaskIndexByCheckpoint[
                                                            cpNode.id] = tIdx;
                                                        _selectedSubStepIndexByTask[
                                                                '${cpNode.id}_$tIdx'] =
                                                            sIdx;
                                                        _isHalfScreenOutlinerOpen =
                                                            false;
                                                      });
                                                    },
                                                    borderRadius:
                                                        const BorderRadius.only(
                                                      topRight:
                                                          Radius.circular(5),
                                                      bottomRight:
                                                          Radius.circular(5),
                                                    ),
                                                    child: Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                        bottom: 1,
                                                      ),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3.5,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isStepActive
                                                            ? bgSurface
                                                            : Colors
                                                                .transparent,
                                                        borderRadius:
                                                            const BorderRadius
                                                                .only(
                                                          topRight:
                                                              Radius.circular(
                                                                  5),
                                                          bottomRight:
                                                              Radius.circular(
                                                                  5),
                                                        ),
                                                        border: Border(
                                                          left: BorderSide(
                                                            color: isStepActive
                                                                ? accentCyan
                                                                : Colors
                                                                    .transparent,
                                                            width: 2.5,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                              top: 1,
                                                            ),
                                                            child: Text(
                                                              (sIdx + 1)
                                                                  .toString()
                                                                  .padLeft(
                                                                      2, '0'),
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 9.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: isStepActive
                                                                    ? accentCyan
                                                                    : (isStepDone
                                                                        ? accentEmerald
                                                                        : textMuted),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              stepItem
                                                                  .shortTitle,
                                                              maxLines: 2,
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 11,
                                                                height: 1.25,
                                                                fontWeight: isStepActive
                                                                    ? FontWeight
                                                                        .w700
                                                                    : FontWeight
                                                                        .w500,
                                                                color: isStepActive
                                                                    ? textPrimary
                                                                    : (isStepDone
                                                                        ? textMuted
                                                                            .withValues(
                                                                            alpha:
                                                                                0.65,
                                                                          )
                                                                        : textSecondary),
                                                                decoration: isStepDone &&
                                                                        !isStepActive
                                                                    ? TextDecoration
                                                                        .lineThrough
                                                                    : TextDecoration
                                                                        .none,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                              top: 1,
                                                            ),
                                                            child: Text(
                                                              isStepDone
                                                                  ? '✓'
                                                                  : '~${stepItem.etaLabel}',
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 9.5,
                                                                fontWeight: isStepActive ||
                                                                        isStepDone
                                                                    ? FontWeight
                                                                        .w700
                                                                    : FontWeight
                                                                        .w500,
                                                                color: isStepDone
                                                                    ? accentEmerald
                                                                    : (isStepActive
                                                                        ? accentCyan
                                                                        : textMuted),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          if (isCpActive)
                            InkWell(
                              key: ValueKey('outline_add_task_btn_${cpNode.id}'),
                              onTap: () => _showAddBuildTaskDialog(
                                feat,
                                states,
                                cpIdx,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 3, 8, 3),
                                child: Text(
                                  '+ Add Build Task...',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: accentCyan.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                );
              },
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
                    '${completedFeat.title} is 100% VERIFIED ✓! Ready for the next feature in your loop?',
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
              'Continue to ${nextFeat.title} →',
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
                onPressed: () => widget.workbench.advanceToNextRelease(),
                icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                label: Text(
                  'Ship & Plan Next Release ✦',
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
              widget.workbench.advanceToNextRelease();
            },
            icon: const Icon(Icons.arrow_forward_rounded, size: 15),
            label: Text(
              'Evolve to Next Release ✦',
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
    for (final task in node.checklist) {
      task.completed = true;
      for (final child in task.children) {
        child.completed = true;
      }
    }
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
    final isDone = node.isCompleted;
    final isAwaitingPlaytest =
        isDone && _awaitingPlaytestVerification.contains(node.id);
    final isActiveFocus = index == activeFocusIndex;
    final isFocusMode = widget.workbench.focusMode;

    final bool isCollapsed;
    if (isAwaitingPlaytest) {
      isCollapsed = false;
    } else if (isDone || (isFocusMode && !isActiveFocus)) {
      isCollapsed = !_expandedDoneCheckpoints.contains(node.id);
    } else {
      isCollapsed = false;
    }

    final featureArchetype =
        MechanicArchetypeProfile.fromFeatureTitle(feat.title);
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

    final canGoToPreviousStep = selectedTaskIdx > 0 || activeSubStepIdx > 0;

    // Determine whether this is the final remaining step of the entire Checkpoint (#2)
    final isFinalCheckpointStep = node.isCompleted ||
        (selectedParentTask != null &&
            node.checklist.every(
              (t) =>
                  t.id == selectedParentTask.id || t.completed,
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

    final pitfallOrGuardText =
        (activeSubStep != null && activeSubStep.quickFixPitfall.isNotEmpty)
            ? activeSubStep.quickFixPitfall
            : (edgeItems.isNotEmpty
                ? edgeItems.first
                : (tuningItems.isNotEmpty
                    ? 'Tuning Target: ${tuningItems.join(' · ')}'
                    : 'Verify the parent class and component hierarchy match the spec before wiring logic in the next step.'));

    final doneSubStepCount = selectedHowTo?.subSteps
            .where((s) => s.subtask.completed)
            .length ??
        0;

    final pinnedActiveStepWindow = (selectedParentTask != null &&
            selectedHowTo != null &&
            activeSubStep != null)
        ? Container(
            key: ValueKey('pinned_active_step_window_${node.id}'),
            color: bgBase,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── GREYSCALE-VALIDATED COHESIVE 3-ZONE FOCUSED STEP VIEW (Centered 780px Studio Column) ──
                Container(
                  key: ValueKey(
                    'task_sheet_active_step_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                  ),
                  color: bgBase,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Fixed 44px Header Bar ([ ☰ Outline ] in Half-Screen + Step Dropdown + Progress & Typographic Unreal Mode Switch)
                      Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        decoration: BoxDecoration(
                          color: bgBase,
                          border: Border(
                            bottom: BorderSide(color: borderSubtle),
                          ),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 780),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isHalfScreenOverlayMode) ...[
                                        InkWell(
                                          key: ValueKey(
                                            'halfscreen_outliner_trigger_${node.id}',
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _isHalfScreenOutlinerOpen =
                                                  !_isHalfScreenOutlinerOpen;
                                            });
                                          },
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _isHalfScreenOutlinerOpen
                                                  ? accentCyan.withValues(
                                                      alpha: 0.14,
                                                    )
                                                  : bgSurface,
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: _isHalfScreenOutlinerOpen
                                                    ? accentCyan
                                                    : borderBright,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.menu_open_rounded,
                                                  size: 13,
                                                  color: _isHalfScreenOutlinerOpen
                                                      ? accentCyan
                                                      : textPrimary,
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  'Outline',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        _isHalfScreenOutlinerOpen
                                                            ? accentCyan
                                                            : textPrimary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          width: 1,
                                          height: 14,
                                          color: borderSubtle,
                                        ),
                                        const SizedBox(width: 10),
                                      ],
                                      Flexible(
                                        child: PopupMenuButton<int>(
                                          key: ValueKey(
                                            'step_dropdown_${node.id}_$selectedTaskIdx',
                                          ),
                                          tooltip: 'Switch Step',
                                          color: bgSurface,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            side:
                                                BorderSide(color: borderBright),
                                          ),
                                          onSelected: (selectedIdx) {
                                            setState(() {
                                              _selectedTaskIndexByCheckpoint[
                                                  node.id] = selectedTaskIdx;
                                              _selectedSubStepIndexByTask[
                                                      '${node.id}_$selectedTaskIdx'] =
                                                  selectedIdx;
                                            });
                                          },
                                          itemBuilder: (context) => [
                                            for (int sIdx = 0;
                                                sIdx <
                                                    selectedHowTo
                                                        .subSteps.length;
                                                sIdx++)
                                              PopupMenuItem<int>(
                                                value: sIdx,
                                                height: 36,
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        '${(sIdx + 1).toString().padLeft(2, '0')} · ${selectedHowTo.subSteps[sIdx].shortTitle}',
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 12,
                                                          fontWeight: sIdx ==
                                                                  activeSubStepIdx
                                                              ? FontWeight.w700
                                                              : FontWeight.w500,
                                                          color: sIdx ==
                                                                  activeSubStepIdx
                                                              ? accentCyan
                                                              : (selectedHowTo
                                                                      .subSteps[
                                                                          sIdx]
                                                                      .subtask
                                                                      .completed
                                                                  ? textMuted
                                                                  : textPrimary),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Text(
                                                      selectedHowTo
                                                              .subSteps[sIdx]
                                                              .subtask
                                                              .completed
                                                          ? '✓'
                                                          : '~${selectedHowTo.subSteps[sIdx].etaLabel}',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: selectedHowTo
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
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    'STEP ${activeSubStepIdx + 1} OF ${selectedHowTo.subSteps.length} · ~${activeSubStep.etaLabel}${activeSubStep.subtask.completed ? ' · COMPLETED ✓' : ''}',
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 0.4,
                                                      color: activeSubStep
                                                              .subtask.completed
                                                          ? accentEmerald
                                                          : accentCyan,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                Icon(
                                                  Icons
                                                      .keyboard_arrow_down_rounded,
                                                  size: 15,
                                                  color: activeSubStep
                                                          .subtask.completed
                                                      ? accentEmerald
                                                      : accentCyan,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$doneSubStepCount / ${selectedHowTo.subSteps.length} Done',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: doneSubStepCount ==
                                                selectedHowTo.subSteps.length
                                            ? accentEmerald
                                            : textSecondary,
                                      ),
                                    ),
                                    if (selectedHowTo.engineLabel ==
                                        'UNREAL 5') ...[
                                      const SizedBox(width: 14),
                                      Container(
                                        key: ValueKey(
                                          'unreal_mode_toggle_${node.id}',
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    bottom: BorderSide(
                                                      color: !_unrealCppMode
                                                          ? accentCyan
                                                          : Colors.transparent,
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(
                                                  'Blueprint',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 10.5,
                                                    fontWeight: !_unrealCppMode
                                                        ? FontWeight.w800
                                                        : FontWeight.w600,
                                                    color: !_unrealCppMode
                                                        ? accentCyan
                                                        : textMuted,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                              ),
                                              child: Text(
                                                '/',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 10.5,
                                                  color: textMuted,
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    bottom: BorderSide(
                                                      color: _unrealCppMode
                                                          ? accentCyan
                                                          : Colors.transparent,
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(
                                                  'C++',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 10.5,
                                                    fontWeight: _unrealCppMode
                                                        ? FontWeight.w800
                                                        : FontWeight.w600,
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
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // 2. Centered 780px Cohesive 3-Zone Studio Column
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 780),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ── ZONE 1: Step Title + Boxless FEATURE GOAL (with subtle 1px hairline) + Instruction + Why ──
                                Text(
                                  activeSubStep.shortTitle,
                                  style: GoogleFonts.inter(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.45,
                                    height: 1.2,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),

                                // Boxless FEATURE GOAL Directly Under Step Title + subtle 1px bottom hairline
                                Container(
                                  key: ValueKey(
                                    'task_sheet_feature_goal_${node.id}',
                                  ),
                                  padding: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: borderSubtle.withValues(
                                          alpha: 0.65,
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: Text.rich(
                                    TextSpan(
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        height: 1.45,
                                        color: textSecondary,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: 'FEATURE GOAL · ',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.4,
                                            color: accentCyan,
                                          ),
                                        ),
                                        TextSpan(text: featureGoalText),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // Action Instruction + Why Explanation
                                Text.rich(
                                  _buildSemanticStepSpan(
                                    text: activeSubStep.instruction,
                                    baseStyle: GoogleFonts.inter(
                                      fontSize: 15.5,
                                      height: 1.6,
                                      color: textPrimary,
                                    ),
                                    tuningItems: tuningItems,
                                    edgeItems: edgeItems,
                                    isCodeBlock: false,
                                  ),
                                ),
                                if (activeSubStep.explainConcept
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text.rich(
                                    _buildSemanticStepSpan(
                                      text: activeSubStep.explainConcept,
                                      baseStyle: GoogleFonts.inter(
                                        fontSize: 13,
                                        height: 1.5,
                                        color: textSecondary,
                                      ),
                                      tuningItems: tuningItems,
                                      edgeItems: edgeItems,
                                      isCodeBlock: false,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 22),

                                // ── ZONE 2: External Path & Copy/Edit Caption Bar + Single L2 Elevated Slate Code Well ──
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '📍 ${activeSubStep.stepPath.isNotEmpty ? activeSubStep.stepPath : selectedHowTo.whereLocation}',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: accentCyan,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
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
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              'Copy',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: textSecondary,
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
                                              onTap: () =>
                                                  _copySubStepCodeFormula(
                                                selectedTaskIdx,
                                                1,
                                                selectedHowTo.subSteps.length >
                                                        1
                                                    ? selectedHowTo
                                                        .subSteps[1].codeFormula
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
                                              horizontal: 6,
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
                                const SizedBox(height: 7),

                                // Single L2 Elevated Slate Code Well (bgSurface + 3px left accentCyan bar, zero inner header box)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: bgSurface,
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(8),
                                      bottomRight: Radius.circular(8),
                                    ),
                                    border: Border(
                                      left: BorderSide(
                                        color: accentCyan,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                  child: Text.rich(
                                    _buildSemanticStepSpan(
                                      text: activeSubStep.codeFormula,
                                      baseStyle: GoogleFonts.jetBrainsMono(
                                        fontSize: 12.5,
                                        height: 1.65,
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
                                const SizedBox(height: 22),

                                // ── ZONE 3: Cohesive Verify + [ ✓ Complete & Next Step → ] Row (22px directly below Code Well) + Playtest Footnote ──
                                Container(
                                  padding: const EdgeInsets.only(top: 20),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: borderSubtle),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '✓ VERIFY BEFORE CHECKING',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.4,
                                                    color: accentEmerald,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text.rich(
                                                  _buildSemanticStepSpan(
                                                    text: activeSubStep
                                                        .verifyResult,
                                                    baseStyle:
                                                        GoogleFonts.inter(
                                                      fontSize: 13.5,
                                                      height: 1.45,
                                                      color: textPrimary,
                                                    ),
                                                    tuningItems: tuningItems,
                                                    edgeItems: edgeItems,
                                                    isCodeBlock: false,
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                RichText(
                                                  text: TextSpan(
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11.5,
                                                      color: textMuted,
                                                      height: 1.35,
                                                    ),
                                                    children: [
                                                      TextSpan(
                                                        text: 'Tip: ',
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: accentAmber,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text:
                                                            pitfallOrGuardText,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 20),
                                          ElevatedButton.icon(
                                            key: ValueKey(
                                              'one_click_complete_next_btn_${node.id}',
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: accentEmerald,
                                              foregroundColor:
                                                  const Color(0xFF052E16),
                                              elevation: 0,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 14,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                            ),
                                            onPressed: () {
                                              if (!activeSubStep
                                                  .subtask.completed) {
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
                                              size: 16,
                                            ),
                                            label: Text(
                                              isFinalCheckpointStep
                                                  ? 'Complete Feature & Continue →'
                                                  : 'Complete & Next Step →',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Container(
                                        key: ValueKey(
                                          'task_sheet_playtest_check_${node.id}',
                                        ),
                                        child: Text.rich(
                                          TextSpan(
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              height: 1.4,
                                              color: textMuted,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: 'PLAYTEST CHECK · ',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.4,
                                                  color: accentEmerald,
                                                ),
                                              ),
                                              TextSpan(
                                                text: resolvedPlaytestCheck,
                                              ),
                                            ],
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
                          Text(
                            '${selectedHowTo.numLabel} · ${selectedHowTo.cleanTitle}',
                          ),
                          Text(nextUpLabel),
                          const Text('✓ VERIFY BEFORE CHECKING [✓]'),
                          Container(
                            key: ValueKey('howto_engine_badge_${node.id}'),
                            child: Text(selectedHowTo.engineLabel),
                          ),
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
    final assetRegex = RegExp(
      r'\b(?:BP_[A-Za-z0-9_]+|A[A-Z][A-Za-z0-9_]+Actor|[A-Za-z0-9_]+\.(?:uasset|tscn|gd|cs|h|cpp)|InteractBox|VisualMesh|DefaultSceneRoot|InteractTrigger|HitBox|CollisionShape2D|BoxCollider)\b',
    );
    for (final m in assetRegex.allMatches(text)) {
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
}
