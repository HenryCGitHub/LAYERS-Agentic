import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../agents/workspace_agent_tools.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import '../utils/feature_spec_binding.dart';

/// Stage 3 Screen: Active Release Workbench
/// - Left Rail: Core Loop Beats & Features switcher for the active Release
/// - Main Canvas:
///   - Release Completion Banner (when 100% of Checkpoints are VERIFIED ✓)
///   - Ultra-Compact Feature Header (Goal, Done When, Out of Scope badge, Inline Unassigned Spec Shelf)
///   - 60/40 Playable Checkpoint Cards (Checklist Left 60% | Playtest, Scope, Tuning, Edge Cases Right 40%)
///   - Sticky Bottom Studio Dock (3 Side-by-Side Co-Pilot Playing Cards, [ASK AGENT] Input, Copy Markdown & Feature Nav)
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
  final Set<String> _collapsedOpenCheckpoints = {};
  final Set<String> _awaitingPlaytestVerification = {};
  final bool _showAllCheckpointsInFocus = false;
  int? _manualCheckpointFocusIndex;
  final String _selectedVersionFilter = 'ALL';
  bool _criticalPathOnly = false;
  final Map<String, int> _selectedTaskIndexByCheckpoint = {};
  final Map<String, int> _selectedSubStepIndexByTask = {};
  final Set<String> _expandedHowToTaskKeys = {};
  final Set<String> _collapsedOutlineFeatureIds = {};
  final Set<String> _expandedOutlineFeatureIds = {};
  final Set<String> _collapsedOutlineTaskKeys = {};
  final Map<String, int> _lastOutlineTapMsByKey = {};
  bool _unrealCppMode = false;

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
        final isWide = constraints.maxWidth >= 780;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 280,
                child: _buildLeftBeatFeatureRail(rel),
              ),
              Expanded(
                child: _buildFeatureMainCanvas(rel),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLeftBeatFeatureRail(rel, shrinkWrap: true),
              const SizedBox(height: 16),
              _buildFeatureMainCanvas(rel, shrinkWrap: true),
            ],
          ),
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

  Widget _buildLeftBeatFeatureRail(TierDocument rel, {bool shrinkWrap = false}) {
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                  // Right: Simple Number-Only Live Rollup ("12h Left #%"), no tile, no progress bar
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
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'E${(bIdx + 1).toString().padLeft(2, '0')} · ${beat.title.split(':').last.split('—').last.trim().toUpperCase()}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: allBeatDone
                                      ? accentEmerald.withValues(alpha: 0.75)
                                      : (isBeatActive ? textSecondary : textMuted),
                                  decoration: allBeatDone
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (beatFeats.isNotEmpty)
                              Text(
                                '$doneBeatCount/${beatFeats.length}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: allBeatDone ? accentEmerald : textMuted,
                                ),
                              ),
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
        border: Border(right: BorderSide(color: borderSubtle)),
      ),
      child: SingleChildScrollView(child: content),
    );
  }

  Widget _buildFeatureRailItem(
    TierDocument feat, {
    required String activeVer,
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

    return Opacity(
      opacity: shouldDim ? 0.62 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? bgSurface : Colors.transparent,
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
                  10,
                  16,
                  10,
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
                  children: [
                    InkWell(
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
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        feat.title,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isDone
                              ? textMuted.withValues(alpha: 0.6)
                              : (isSelected ? textPrimary : textSecondary),
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
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

  /// Single-Spine De-Boxed Outliner Hierarchy: Renders `Feature -> Numbered Tasks (01 · ...) -> Leaf Steps (✓ / ● / ○)`
  /// along a single 2px vertical guide spine without nested boxes or double borders.
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
      margin: const EdgeInsets.fromLTRB(22, 2, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: borderSubtle, width: 2),
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
                if (activeTaskIdx < 0 || activeTaskIdx >= cpNode.checklist.length) {
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
                              if (_expandedDoneCheckpoints.contains(cpNode.id)) {
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
                                final taskKey = '${cpNode.id}_$tIdx';
                                final doneSubCount = bp.subSteps
                                    .where((s) => s.subtask.completed)
                                    .length;
                                final totalSubCount = bp.subSteps.length;
                                final taskSymbol = task.completed
                                    ? '✓'
                                    : (isTaskActive ? '●' : '○');

                                return InkWell(
                                  key: ValueKey(
                                    'outline_task_${cpNode.id}_$tIdx',
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _manualCheckpointFocusIndex = cpIdx;
                                      _selectedTaskIndexByCheckpoint[
                                          cpNode.id] = tIdx;
                                      _expandedHowToTaskKeys
                                        ..clear()
                                        ..add(taskKey);
                                    });
                                    if (widget.workbench.selectedFeatureId !=
                                        feat.id) {
                                      widget.workbench.selectFeature(feat.id);
                                    }
                                  },
                                  child: Container(
                                    padding: EdgeInsets.fromLTRB(
                                      isTaskActive ? 8 : 10,
                                      6,
                                      8,
                                      6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isTaskActive
                                          ? accentCyan.withValues(alpha: 0.08)
                                          : Colors.transparent,
                                      border: isTaskActive
                                          ? Border(
                                              left: BorderSide(
                                                color: isFixTask
                                                    ? accentCrimson
                                                    : accentCyan,
                                                width: 2,
                                              ),
                                            )
                                          : null,
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 14,
                                          child: Text(
                                            taskSymbol,
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.jetBrainsMono(
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
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            '${bp.numLabel} · ${bp.cleanTitle}',
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              fontWeight: isTaskActive &&
                                                      !task.completed
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: task.completed
                                                  ? textMuted.withValues(
                                                      alpha: 0.5,
                                                    )
                                                  : (isFixTask
                                                      ? accentCrimson
                                                      : (isTaskActive
                                                          ? textPrimary
                                                          : textSecondary)),
                                              decoration: task.completed
                                                  ? TextDecoration.lineThrough
                                                  : TextDecoration.none,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '$doneSubCount/$totalSubCount · $taskRemLabel',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 9.5,
                                            fontWeight: isTaskActive
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: task.completed
                                                ? accentEmerald.withValues(
                                                    alpha: 0.65,
                                                  )
                                                : (isTaskActive
                                                    ? accentCyan
                                                    : textMuted),
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
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureMainCanvas(TierDocument rel, {bool shrinkWrap = false}) {
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
    final specBinding = FeatureSpecBinding.resolveBindings(feat, states);
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
          if (_selectedVersionFilter == 'ALL' ||
              !states.any((s) => s.releaseVersion == _selectedVersionFilter) ||
              states[i].releaseVersion == _selectedVersionFilter)
            if (!widget.workbench.focusMode ||
                _showAllCheckpointsInFocus ||
                i == effectiveFocusIndex ||
                states.length <= 1)
              _buildCheckpointCard(
                feat,
                states,
                i,
                activeFocusIndex: effectiveFocusIndex,
                specBinding: specBinding,
              ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('stage3_active_feature_sheet'),
          child: activeFeatureContent,
        ),
      ],
    );

    if (shrinkWrap) {
      return body;
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
                      minHeight: viewportConstraints.maxHeight,
                      minWidth: viewportConstraints.maxWidth,
                    ),
                    child: body,
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
                          'CORE BEATS',
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

  Widget _buildCheckpointCard(
    TierDocument feat,
    List<FeatureStateNode> states,
    int index, {
    required int activeFocusIndex,
    required FeatureSpecBindingResult specBinding,
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
    } else if (isDone) {
      isCollapsed = !_expandedDoneCheckpoints.contains(node.id);
    } else if (isFocusMode && !isActiveFocus) {
      isCollapsed = !_expandedDoneCheckpoints.contains(node.id);
    } else {
      isCollapsed = _collapsedOpenCheckpoints.contains(node.id);
    }

    final tuningItems =
        specBinding.checkpointTuning[node.id] ?? const <String>[];
    final edgeItems =
        specBinding.checkpointEdgeCases[node.id] ?? const <String>[];
    final verStamp = node.releaseVersion;

    // Resolve Checkable How-To Blueprints for all parent tasks in this checkpoint
    final engineHint = widget.workbench.conceptDraft?.techSpec.join(' ') ??
        widget.workbench.activeProject?.sections['tech_spec'];
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

    Future<void> promptEditHowToSubStepDialog(int pIdx, int sIdx) async {
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

    Future<void> copySubStepCodeFormula(
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

    Future<void> promptTailorHowToDialog(int pIdx) async {
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
        checkpointIndex: index,
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

    void toggleHowToSubStepCompletion(int pIdx, int sIdx) {
      if (pIdx < 0 || pIdx >= node.checklist.length) return;
      final parentTask = node.checklist[pIdx];
      if (sIdx < 0 || sIdx >= parentTask.children.length) return;
      final wasDone = node.isCompleted;
      final nextCompleted = !parentTask.children[sIdx].completed;
      parentTask.children[sIdx].completed = nextCompleted;
      parentTask.completed =
          parentTask.children.isNotEmpty && parentTask.children.every((c) => c.completed);
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

    void advanceToNextStep(int pIdx, int sIdx) {
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
          _selectedSubStepIndexByTask['${node.id}_$pIdx'] =
              nextIncompleteStepIdx;
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

      // All tasks & steps in this Checkpoint are 100% done! Verify Checkpoint & Continue -> (#2)
      for (final task in node.checklist) {
        task.completed = true;
        for (final child in task.children) {
          child.completed = true;
        }
      }
      setState(() {
        _awaitingPlaytestVerification.remove(node.id);
        _expandedDoneCheckpoints.remove(node.id);
        // Advance to next incomplete Checkpoint in this Feature if available
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

    final canGoToPreviousStep = selectedTaskIdx > 0 || activeSubStepIdx > 0;

    void retreatToPreviousStep(int pIdx, int sIdx) {
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
          _collapsedOutlineTaskKeys.remove('${node.id}_$prevTaskIdx');
        });
      }
    }

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

    final pinnedActiveStepWindow = (selectedParentTask != null &&
            selectedHowTo != null &&
            activeSubStep != null)
        ? Container(
            key: ValueKey('pinned_active_step_window_${node.id}'),
            color: bgBase,
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1020),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 1. Full-Page Task Sheet Header (Breadcrumb + Title + Playtest Goal + Tuning Spec Chip + Mode Controls) ──
                    Container(
                      padding: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: borderSubtle)),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: textSecondary,
                                      ),
                                      children: [
                                        TextSpan(text: '${feat.title}  /  '),
                                        TextSpan(
                                          text:
                                              'TASK ${selectedHowTo.numLabel} OF ${howToBlueprints.length.toString().padLeft(2, '0')}',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: accentCyan,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Offstage(
                                    offstage: true,
                                    child: Container(
                                      key: ValueKey(
                                        'howto_engine_badge_${node.id}',
                                      ),
                                      child: Text(selectedHowTo.engineLabel),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${selectedHowTo.numLabel} · ${selectedHowTo.cleanTitle}',
                                style: GoogleFonts.inter(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 12,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        color: textSecondary,
                                        height: 1.4,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: 'PLAYTEST GOAL: ',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: accentEmerald,
                                          ),
                                        ),
                                        TextSpan(text: node.playtestCondition),
                                      ],
                                    ),
                                  ),
                                  if (tuningItems.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: accentViolet.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '⚙ ${tuningItems.join(' · ')}',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: accentViolet,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          // Right-aligned Action Controls (Unreal Blueprint | C++ toggle + Tailor)
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (selectedHowTo.engineLabel == 'UNREAL 5')
                                Container(
                                  key: ValueKey('unreal_mode_toggle_${node.id}'),
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: bgRecessed,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: borderBright),
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
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 11,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: !_unrealCppMode
                                                ? accentCyan
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Blueprint',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 11,
                                              fontWeight: !_unrealCppMode
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                              color: !_unrealCppMode
                                                  ? const Color(0xFF06131F)
                                                  : textSecondary,
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
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 11,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _unrealCppMode
                                                ? accentCyan
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'C++',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 11,
                                              fontWeight: _unrealCppMode
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                              color: _unrealCppMode
                                                  ? const Color(0xFF06131F)
                                                  : textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              InkWell(
                                key: ValueKey(
                                  'tailor_howto_btn_${node.id}_$selectedTaskIdx',
                                ),
                                onTap: () =>
                                    promptTailorHowToDialog(selectedTaskIdx),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    '✦ Tailor',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: accentViolet,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ── 2. Option A: Focused 6-Step Accordion List (Completed Rows -> Active Step Do/Copy/Verify Triad -> Upcoming Rows) ──
                    Container(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: borderSubtle)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int sIdx = 0;
                              sIdx < selectedHowTo.subSteps.length;
                              sIdx++)
                            if (sIdx == activeSubStepIdx)
                              // ── ACTIVE EXPANDED STEP CARD (Do -> Copy -> Verify Triad) ──
                              Container(
                                key: ValueKey(
                                  'task_sheet_active_step_${node.id}_${selectedTaskIdx}_$sIdx',
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  21,
                                  20,
                                  24,
                                  22,
                                ),
                                decoration: BoxDecoration(
                                  color: bgSurface,
                                  border: Border(
                                    left: BorderSide(
                                      color: activeSubStep.subtask.completed
                                          ? accentEmerald
                                          : accentCyan,
                                      width: 3,
                                    ),
                                    bottom: BorderSide(color: borderSubtle),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Top Row: STEP X OF Y Overline + Step Title
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'STEP ${activeSubStepIdx + 1} OF ${selectedHowTo.subSteps.length} · ~${activeSubStep.etaLabel}',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.4,
                                                  color: activeSubStep
                                                          .subtask.completed
                                                      ? accentEmerald
                                                      : accentCyan,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                activeSubStep.shortTitle,
                                                style: GoogleFonts.inter(
                                                  fontSize: 19.5,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: -0.2,
                                                  color: textPrimary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          'Click any step row to switch',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10.5,
                                            color: textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // 1. DO: Clear Action Instruction
                                    Text(
                                      activeSubStep.instruction,
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        height: 1.65,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // 2. COPY / CONFIGURE: Full-Width Inline Code / Blueprint Block
                                    Container(
                                      decoration: BoxDecoration(
                                        color: bgBase,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: borderSubtle),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: bgRecessed,
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: borderSubtle,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '📍 ${activeSubStep.stepPath.isNotEmpty ? activeSubStep.stepPath : selectedHowTo.whereLocation}',
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: accentCyan,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    InkWell(
                                                      key: ValueKey(
                                                        'copy_howto_code_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                                                      ),
                                                      onTap: () =>
                                                          copySubStepCodeFormula(
                                                        selectedTaskIdx,
                                                        activeSubStepIdx,
                                                        activeSubStep
                                                            .codeFormula,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                        child: Text(
                                                          'Copy',
                                                          style: GoogleFonts
                                                              .jetBrainsMono(
                                                            fontSize: 10.5,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                textSecondary,
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
                                                              copySubStepCodeFormula(
                                                            selectedTaskIdx,
                                                            1,
                                                            selectedHowTo
                                                                        .subSteps
                                                                        .length >
                                                                    1
                                                                ? selectedHowTo
                                                                    .subSteps[1]
                                                                    .codeFormula
                                                                : activeSubStep
                                                                    .codeFormula,
                                                          ),
                                                          child: const SizedBox
                                                              .shrink(),
                                                        ),
                                                      ),
                                                    const SizedBox(width: 6),
                                                    InkWell(
                                                      key: ValueKey(
                                                        'edit_howto_substep_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                                                      ),
                                                      onTap: () =>
                                                          promptEditHowToSubStepDialog(
                                                        selectedTaskIdx,
                                                        activeSubStepIdx,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                        child: Text(
                                                          'Edit',
                                                          style: GoogleFonts
                                                              .jetBrainsMono(
                                                            fontSize: 10.5,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                textSecondary,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                            child: Text(
                                              activeSubStep.codeFormula,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 12.5,
                                                height: 1.6,
                                                color: isDark
                                                    ? const Color(0xFFE5E7EB)
                                                    : textPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // 3. VERIFY + 1-Click Complete Footer
                                    Container(
                                      padding: const EdgeInsets.only(top: 14),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(color: borderSubtle),
                                        ),
                                      ),
                                      child: Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 16,
                                        runSpacing: 12,
                                        children: [
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 680,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.only(
                                                left: 12,
                                              ),
                                              decoration: BoxDecoration(
                                                border: Border(
                                                  left: BorderSide(
                                                    color: accentEmerald,
                                                    width: 3,
                                                  ),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '✓ VERIFY BEFORE CHECKING [✓]',
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 0.4,
                                                      color: accentEmerald,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    activeSubStep.verifyResult,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 13,
                                                      height: 1.45,
                                                      color: textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  RichText(
                                                    text: TextSpan(
                                                      style: GoogleFonts.inter(
                                                        fontSize: 12,
                                                        color: textMuted,
                                                        height: 1.4,
                                                      ),
                                                      children: [
                                                        TextSpan(
                                                          text: '🔧 Tip: ',
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
                                          ),
                                          // 1-Click Complete & Next Step CTA
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
                                                horizontal: 16,
                                                vertical: 12,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                            ),
                                            onPressed: () {
                                              if (!activeSubStep
                                                  .subtask.completed) {
                                                toggleHowToSubStepCompletion(
                                                  selectedTaskIdx,
                                                  activeSubStepIdx,
                                                );
                                              }
                                              advanceToNextStep(
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
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              // ── COLLAPSED STEP ROW (Completed `✓` or Upcoming `03..06`) ──
                              Builder(
                                builder: (context) {
                                  final stepItem = selectedHowTo.subSteps[sIdx];
                                  final isStepDone = stepItem.subtask.completed;
                                  final stepNumStr = (sIdx + 1)
                                      .toString()
                                      .padLeft(2, '0');
                                  return InkWell(
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
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 11,
                                      ),
                                      decoration: BoxDecoration(
                                        color: bgBase,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: borderSubtle,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          InkWell(
                                            onTap: () =>
                                                toggleHowToSubStepCompletion(
                                              selectedTaskIdx,
                                              sIdx,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            child: Container(
                                              width: 22,
                                              height: 22,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: isStepDone
                                                    ? accentEmerald.withValues(
                                                        alpha: 0.14,
                                                      )
                                                    : bgRecessed,
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                                border: Border.all(
                                                  color: isStepDone
                                                      ? accentEmerald
                                                          .withValues(
                                                          alpha: 0.45,
                                                        )
                                                      : borderSubtle,
                                                ),
                                              ),
                                              child: Text(
                                                isStepDone ? '✓' : stepNumStr,
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: isStepDone
                                                      ? accentEmerald
                                                      : textMuted,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              '$stepNumStr · ${stepItem.shortTitle}',
                                              style: GoogleFonts.inter(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                                color: isStepDone
                                                    ? textMuted
                                                    : textSecondary,
                                                decoration: isStepDone
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            isStepDone
                                                ? 'Done ✓'
                                                : '~${stepItem.etaLabel}',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 11,
                                              color: isStepDone
                                                  ? accentEmerald
                                                  : textMuted,
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

                    const SizedBox(height: 18),

                    // ── 3. Full-Page Bottom Task Progress & Step Controls Bar ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: bgRecessed,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderSubtle),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: textSecondary,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      'Task ${selectedHowTo.numLabel}: ${selectedHowTo.subSteps.where((s) => s.subtask.completed).length}/${selectedHowTo.subSteps.length} Steps Done  ·  Next: ',
                                ),
                                TextSpan(
                                  text: nextUpLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Compact Previous Step (←) Button
                              Tooltip(
                                message: canGoToPreviousStep
                                    ? 'Previous Step'
                                    : 'First Step',
                                child: InkWell(
                                  key: ValueKey(
                                    'prev_active_step_btn_${node.id}',
                                  ),
                                  onTap: canGoToPreviousStep
                                      ? () => retreatToPreviousStep(
                                            selectedTaskIdx,
                                            activeSubStepIdx,
                                          )
                                      : null,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: canGoToPreviousStep
                                          ? bgSurface
                                          : bgBase.withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: canGoToPreviousStep
                                            ? borderBright
                                            : borderSubtle,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.arrow_back_rounded,
                                      size: 16,
                                      color: canGoToPreviousStep
                                          ? textPrimary
                                          : textMuted.withValues(alpha: 0.35),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Simple Square Checkmark Box [✓]
                              Tooltip(
                                message: activeSubStep.subtask.completed
                                    ? 'Step Done (Click to uncheck)'
                                    : 'Mark Step Done to unlock Next →',
                                child: InkWell(
                                  key: ValueKey(
                                    'mark_active_step_done_btn_${node.id}',
                                  ),
                                  onTap: () => toggleHowToSubStepCompletion(
                                    selectedTaskIdx,
                                    activeSubStepIdx,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: activeSubStep.subtask.completed
                                          ? accentEmerald
                                          : bgSurface,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: activeSubStep.subtask.completed
                                            ? accentEmerald
                                            : borderBright,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.check_rounded,
                                      size: 19,
                                      color: activeSubStep.subtask.completed
                                          ? const Color(0xFF052E16)
                                          : textMuted.withValues(alpha: 0.35),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Gated Next Step / Next Task / Complete Feature Button
                              InkWell(
                                key: ValueKey(
                                  'next_active_step_btn_${node.id}',
                                ),
                                onTap: activeSubStep.subtask.completed
                                    ? () => advanceToNextStep(
                                          selectedTaskIdx,
                                          activeSubStepIdx,
                                        )
                                    : null,
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: activeSubStep.subtask.completed
                                        ? (isFinalCheckpointStep
                                            ? accentEmerald
                                            : accentCyan)
                                        : bgBase.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: activeSubStep.subtask.completed
                                          ? (isFinalCheckpointStep
                                              ? accentEmerald
                                              : accentCyan)
                                          : borderSubtle,
                                    ),
                                  ),
                                  child: Text(
                                    advanceButtonLabel,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: activeSubStep.subtask.completed
                                          ? (isFinalCheckpointStep
                                              ? const Color(0xFF052E16)
                                              : const Color(0xFF06131F))
                                          : textMuted.withValues(alpha: 0.45),
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
          )
        : const SizedBox.shrink();

    final checklistPane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: ValueKey('checkpoint_spec_pane_$index'),
          child: pinnedActiveStepWindow,
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showAllCheckpointsInFocus)
            Container(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: borderSubtle),
                    ),
                    child: Text(
                      'CHECKPOINT ${index + 1}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: borderSubtle),
                    ),
                    child: Text(
                      verStamp,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      node.cleanStageTitle,
                      style: AppTheme.displayFont(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  if (isAwaitingPlaytest)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accentEmerald.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'READY FOR PLAYTEST',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: accentEmerald,
                        ),
                      ),
                    )
                  else if (isDone)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accentEmerald.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'VERIFIED ✓',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: accentEmerald,
                        ),
                      ),
                    )
                  else if (isActiveFocus)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accentAmber.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ACTIVE FOCUS · ${node.completedChecklistCount}/${node.totalChecklistCount}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: accentAmber,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: bgRecessed,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'UP NEXT · ${node.completedChecklistCount}/${node.totalChecklistCount}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: textMuted,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  InkWell(
                    key: ValueKey('checkpoint_toggle_$index'),
                    onTap: () {
                      setState(() {
                        if (isAwaitingPlaytest) {
                          _awaitingPlaytestVerification.remove(node.id);
                          _expandedDoneCheckpoints.remove(node.id);
                        } else if (isCollapsed) {
                          if (isDone || (isFocusMode && !isActiveFocus)) {
                            _expandedDoneCheckpoints.add(node.id);
                          } else {
                            _collapsedOpenCheckpoints.remove(node.id);
                          }
                        } else {
                          if (isDone || (isFocusMode && !isActiveFocus)) {
                            _expandedDoneCheckpoints.remove(node.id);
                          } else {
                            _collapsedOpenCheckpoints.add(node.id);
                          }
                        }
                      });
                    },
                    child: Icon(
                      isCollapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 18,
                      color: textMuted,
                    ),
                  ),
                ],
              ),
            ),
          if (!isCollapsed)
            Container(
              key: ValueKey('checkpoint_single_col_$index'),
              child: checklistPane,
            ),
        ],
      ),
    );
  }
}
