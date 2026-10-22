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
  final Set<String> _expandedOutlineTaskKeys = {};
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

  bool _isTaskExpandedInOutline(
    String taskKey, {
    required bool isTaskActive,
    required bool isTaskCompleted,
  }) {
    if (_expandedOutlineTaskKeys.contains(taskKey)) return true;
    if (_collapsedOutlineTaskKeys.contains(taskKey)) return false;
    return isTaskActive && !isTaskCompleted;
  }

  void _toggleTaskExpandedInOutline(
    String taskKey, {
    required bool currentlyExpanded,
  }) {
    if (currentlyExpanded) {
      _expandedOutlineTaskKeys.remove(taskKey);
      _collapsedOutlineTaskKeys.add(taskKey);
    } else {
      _collapsedOutlineTaskKeys.remove(taskKey);
      _expandedOutlineTaskKeys.add(taskKey);
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
                width: 308,
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
                          widget.workbench.openReleasePlanGate(releaseId: rel.id);
                        } else if (value.startsWith('rel:')) {
                          final targetId = value.substring(4);
                          widget.workbench.openReleasePlanGate(releaseId: targetId);
                        } else {
                          widget.workbench.setReleaseViewFilter(value);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'active',
                          child: Text(
                            '● Active: ${rel.title} ($relProgress%)',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'all',
                          child: Text(
                            '🌳 All Live Game Features ($activeVer)',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        if (archivedFeats.isNotEmpty)
                          PopupMenuItem<String>(
                            value: 'archived',
                            child: Text(
                              '🗄 Superseded Testbeds Archive (${archivedFeats.length})',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        const PopupMenuDivider(),
                        for (final r in releases)
                          PopupMenuItem<String>(
                            value: 'rel:${r.id}',
                            child: Text(
                              '${r.id == rel.id ? "▸ " : "  "}${r.title}',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight:
                                    r.id == rel.id ? FontWeight.w700 : FontWeight.w500,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        const PopupMenuDivider(),
                        PopupMenuItem<String>(
                          value: '__replan__',
                          child: Text(
                            '✎ Edit ${rel.title} Scope in Plan Gate',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: '__evolve__',
                          child: Text(
                            '+ Evolve to Next Release Milestone ✦',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: accentEmerald,
                            ),
                          ),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: bgSurface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: borderSubtle),
                        ),
                        child: Text(
                          '$activeVer ${rel.releaseScope.label} ▾',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
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
                            fontWeight: FontWeight.w500,
                            color: isReleaseDone ? accentEmerald : textSecondary,
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
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
                        child: Text(
                          beat.title.split(':').last.split('—').last.trim().toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: allBeatDone
                                ? textMuted.withValues(alpha: 0.45)
                                : (isBeatActive ? textSecondary : textMuted),
                            decoration: allBeatDone
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
          color: bgBase,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderSubtle),
        ),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bgBase,
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
      opacity: shouldDim ? 0.65 : 1.0,
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
              margin: const EdgeInsets.fromLTRB(10, 1, 10, 1),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
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
                          isExpanded ? '▾' : '▸',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isDone
                                ? textMuted.withValues(alpha: 0.45)
                                : (isSelected ? textSecondary : textMuted),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      feat.title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isDone
                            ? textMuted.withValues(alpha: 0.45)
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
                    featRemLabel,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isDone
                          ? textMuted.withValues(alpha: 0.45)
                          : textMuted,
                      decoration: isDone
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
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
    );
  }

  /// Option A Outliner Hierarchy: Renders `Feature -> Numbered Tasks (01 · ...) -> Leaf Steps (✓ / ● / ○)`
  /// directly under the Feature in the Left Outline Sidebar without a redundant middle `Checkpoint 1` wrapper.
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
      margin: const EdgeInsets.fromLTRB(24, 2, 8, 6),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: borderSubtle)),
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
                                final isTaskExpanded = _isTaskExpandedInOutline(
                                  taskKey,
                                  isTaskActive: isTaskActive,
                                  isTaskCompleted: task.completed,
                                );
                                int activeSubIdx =
                                    _selectedSubStepIndexByTask[taskKey] ??
                                        task.children.indexWhere(
                                          (c) => !c.completed,
                                        );
                                if (activeSubIdx < 0 ||
                                    activeSubIdx >= bp.subSteps.length) {
                                  activeSubIdx = 0;
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
                                        final isDouble =
                                            _isDoubleClickOnOutlineItem(
                                          'task_$taskKey',
                                        );
                                        setState(() {
                                          _manualCheckpointFocusIndex = cpIdx;
                                          _selectedTaskIndexByCheckpoint[
                                              cpNode.id] = tIdx;
                                          _expandedHowToTaskKeys
                                            ..clear()
                                            ..add(taskKey);
                                          if (isDouble) {
                                            _toggleTaskExpandedInOutline(
                                              taskKey,
                                              currentlyExpanded: isTaskExpanded,
                                            );
                                          } else {
                                            _collapsedOutlineTaskKeys
                                                .remove(taskKey);
                                          }
                                        });
                                        if (widget.workbench.selectedFeatureId !=
                                            feat.id) {
                                          widget.workbench
                                              .selectFeature(feat.id);
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(5),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4.5,
                                        ),
                                        child: Row(
                                          children: [
                                            InkWell(
                                              key: ValueKey(
                                                'outline_task_chevron_${cpNode.id}_$tIdx',
                                              ),
                                              onTap: () {
                                                setState(() {
                                                  _toggleTaskExpandedInOutline(
                                                    taskKey,
                                                    currentlyExpanded:
                                                        isTaskExpanded,
                                                  );
                                                });
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: SizedBox(
                                                width: 14,
                                                height: 16,
                                                child: Center(
                                                  child: Text(
                                                    isTaskExpanded ? '▾' : '▸',
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 9.5,
                                                      color: task.completed
                                                          ? textMuted
                                                              .withValues(
                                                              alpha: 0.45,
                                                            )
                                                          : (isTaskActive
                                                              ? textPrimary
                                                              : textMuted),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                '${bp.numLabel} · ${bp.cleanTitle}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11.5,
                                                  fontWeight: isTaskActive &&
                                                          !task.completed
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                  color: task.completed
                                                      ? textMuted.withValues(
                                                          alpha: 0.45,
                                                        )
                                                      : (isTaskActive
                                                          ? textPrimary
                                                          : textSecondary),
                                                  decoration: task.completed
                                                      ? TextDecoration
                                                          .lineThrough
                                                      : TextDecoration.none,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              taskRemLabel,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w500,
                                                color: task.completed
                                                    ? textMuted.withValues(
                                                        alpha: 0.45,
                                                      )
                                                    : textMuted,
                                                decoration: task.completed
                                                    ? TextDecoration.lineThrough
                                                    : TextDecoration.none,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (isTaskExpanded &&
                                        bp.subSteps.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(
                                          left: 12,
                                          bottom: 4,
                                        ),
                                        padding: const EdgeInsets.only(left: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            left: BorderSide(
                                              color: borderSubtle,
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
                                                  final step =
                                                      bp.subSteps[sIdx];
                                                  final isStepActive =
                                                      isTaskActive &&
                                                          sIdx == activeSubIdx;
                                                  final stepDone =
                                                      step.subtask.completed;
                                                  final leafSymbol = stepDone
                                                      ? '✓'
                                                      : (isStepActive
                                                          ? '●'
                                                          : '○');

                                                  return InkWell(
                                                    key: ValueKey(
                                                      'outline_step_${cpNode.id}_${tIdx}_$sIdx',
                                                    ),
                                                    onTap: () {
                                                      final isDouble =
                                                          _isDoubleClickOnOutlineItem(
                                                        'step_${cpNode.id}_${tIdx}_$sIdx',
                                                      );
                                                      setState(() {
                                                        _manualCheckpointFocusIndex =
                                                            cpIdx;
                                                        _selectedTaskIndexByCheckpoint[
                                                            cpNode.id] = tIdx;
                                                        _selectedSubStepIndexByTask[
                                                            taskKey] = sIdx;
                                                        _expandedHowToTaskKeys
                                                          ..clear()
                                                          ..add(taskKey);
                                                        if (isDouble) {
                                                          step.subtask
                                                                  .completed =
                                                              !step.subtask
                                                                  .completed;
                                                          task.completed = task
                                                                  .children
                                                                  .isNotEmpty &&
                                                              task.children
                                                                  .every(
                                                                (c) =>
                                                                    c.completed,
                                                              );
                                                        }
                                                      });
                                                      if (isDouble) {
                                                        widget.workbench
                                                            .updateFeatureStates(
                                                          feat.id,
                                                          states,
                                                        );
                                                      }
                                                      if (widget.workbench
                                                              .selectedFeatureId !=
                                                          feat.id) {
                                                        widget.workbench
                                                            .selectFeature(
                                                          feat.id,
                                                        );
                                                      }
                                                    },
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      4,
                                                    ),
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 6,
                                                        vertical: 4.5,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isStepActive
                                                            ? bgRecessed
                                                            : Colors
                                                                .transparent,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Offstage(
                                                            offstage: true,
                                                            child: InkWell(
                                                              key: ValueKey(
                                                                'outline_step_chk_${cpNode.id}_${tIdx}_$sIdx',
                                                              ),
                                                              onTap: () {
                                                                setState(() {
                                                                  step.subtask
                                                                          .completed =
                                                                      !step
                                                                          .subtask
                                                                          .completed;
                                                                  task.completed = task
                                                                          .children
                                                                          .isNotEmpty &&
                                                                      task.children
                                                                          .every(
                                                                        (c) => c
                                                                            .completed,
                                                                      );
                                                                });
                                                                widget.workbench
                                                                    .updateFeatureStates(
                                                                  feat.id,
                                                                  states,
                                                                );
                                                              },
                                                              child:
                                                                  const SizedBox
                                                                      .shrink(),
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            width: 13,
                                                            child: Text(
                                                              leafSymbol,
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 9.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: stepDone
                                                                    ? accentEmerald
                                                                        .withValues(
                                                                        alpha:
                                                                            0.7,
                                                                      )
                                                                    : (isStepActive
                                                                        ? textPrimary
                                                                        : textMuted
                                                                            .withValues(
                                                                            alpha:
                                                                                0.65,
                                                                          )),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 5,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              step.shortTitle
                                                                      .isNotEmpty
                                                                  ? step
                                                                      .shortTitle
                                                                  : step
                                                                      .stepNumberLabel,
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 11.5,
                                                                fontWeight: isStepActive &&
                                                                        !stepDone
                                                                    ? FontWeight
                                                                        .w600
                                                                    : FontWeight
                                                                        .w400,
                                                                color: stepDone
                                                                    ? textMuted
                                                                        .withValues(
                                                                        alpha:
                                                                            0.45,
                                                                      )
                                                                    : (isStepActive
                                                                        ? textPrimary
                                                                        : textSecondary),
                                                                decoration: stepDone
                                                                    ? TextDecoration
                                                                        .lineThrough
                                                                    : TextDecoration
                                                                        .none,
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
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
      color: bgSurface,
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
            color: bgSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Option A: Full-Width Top Header Bar ──
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: bgBase,
                    border: Border(bottom: BorderSide(color: borderSubtle)),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 10,
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
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: textSecondary,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '${feat.title}  /  ',
                                    ),
                                    TextSpan(
                                      text:
                                          '${selectedHowTo.numLabel} · ${selectedHowTo.cleanTitle}',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Offstage(
                                offstage: true,
                                child: Container(
                                  key: ValueKey('howto_engine_badge_${node.id}'),
                                  child: Text(selectedHowTo.engineLabel),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          RichText(
                            text: TextSpan(
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: textSecondary,
                                height: 1.4,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Feature Goal: ',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                                TextSpan(text: node.playtestCondition),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Right-aligned Action Controls in Top Bar (Unreal Blueprint | C++ toggle + Tailor)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Unreal 5 Only: Blueprint | C++ Segmented Toggle
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
                                    key: ValueKey('unreal_bp_btn_${node.id}'),
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
                                            ? focalAccent
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Blueprint',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11,
                                          fontWeight: !_unrealCppMode
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: !_unrealCppMode
                                              ? focalAccentFg
                                              : textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    key: ValueKey('unreal_cpp_btn_${node.id}'),
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
                                            ? focalAccent
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'C++',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11,
                                          fontWeight: _unrealCppMode
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: _unrealCppMode
                                              ? focalAccentFg
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
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: borderSubtle),
                              ),
                              child: Text(
                                '✦ Tailor',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
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

                // ── Option B: Full-Canvas 2-Pane Split (.opt2-split) ──
                LayoutBuilder(
                  builder: (context, splitConstraints) {
                    final useTwoCol = splitConstraints.maxWidth >= 680;
                    final totalSubSteps = selectedHowTo.subSteps.length;

                    // Left Full-Height Instruction Pane (.opt2-left)
                    final leftPane = Container(
                      padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                      decoration: BoxDecoration(
                        color: bgSurface,
                        border: useTwoCol
                            ? Border(right: BorderSide(color: borderSubtle))
                            : Border(bottom: BorderSide(color: borderSubtle)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // STEP X OF Y · ~Zm Badge (Step-only realistic weighted ETA)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: activeSubStep.subtask.completed
                                      ? accentEmerald
                                      : bgHover,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'STEP ${activeSubStepIdx + 1} OF $totalSubSteps · ~${activeSubStep.etaLabel}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: activeSubStep.subtask.completed
                                        ? const Color(0xFF052E16)
                                        : textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Large 22px Hero Step Title
                              Text(
                                activeSubStep.shortTitle,
                                style: GoogleFonts.inter(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Clear 15.5px Instruction Paragraph
                              Text(
                                activeSubStep.instruction,
                                style: GoogleFonts.inter(
                                  fontSize: 15.5,
                                  height: 1.7,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 22),
                              // ✓ VERIFY BEFORE CHECKING [✓] Callout Box
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: accentEmerald.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: accentEmerald.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '✓ VERIFY BEFORE CHECKING [✓]',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                        color: accentEmerald,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      activeSubStep.verifyResult,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        height: 1.5,
                                        color: isDark
                                            ? const Color(0xFFD1FAE5)
                                            : const Color(0xFF065F46),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (activeSubStep.explainConcept.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                // 🎯 CONNECTS TO YOUR SPEC & NEXT STEP Left-Bordered Note + Chips
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.only(
                                    left: 14,
                                    top: 2,
                                    bottom: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: borderBright,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '🎯 CONNECTS TO YOUR SPEC & NEXT STEP',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                          color: textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        activeSubStep.explainConcept,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          height: 1.55,
                                          color: textSecondary,
                                        ),
                                      ),
                                      if (activeSubStep.specChips.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            for (final chip
                                                in activeSubStep.specChips)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: bgBase,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: borderSubtle,
                                                  ),
                                                ),
                                                child: Text(
                                                  chip,
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 10.5,
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
                              ],
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Bottom Action Bar inside Left Pane (Next: ... | [✓] Checkmark Box + Gated Next / Verify Checkpoint Button)
                          Container(
                            padding: const EdgeInsets.only(top: 16),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: borderSubtle),
                              ),
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
                                      const TextSpan(text: 'Next: '),
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
                                        borderRadius: BorderRadius.circular(7),
                                        child: Container(
                                          width: 38,
                                          height: 38,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: canGoToPreviousStep
                                                ? bgBase
                                                : bgBase.withValues(alpha: 0.45),
                                            borderRadius:
                                                BorderRadius.circular(7),
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
                                                : textMuted.withValues(
                                                    alpha: 0.35,
                                                  ),
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
                                        onTap: () =>
                                            toggleHowToSubStepCompletion(
                                          selectedTaskIdx,
                                          activeSubStepIdx,
                                        ),
                                        borderRadius: BorderRadius.circular(7),
                                        child: Container(
                                          width: 38,
                                          height: 38,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color:
                                                activeSubStep.subtask.completed
                                                    ? accentEmerald
                                                    : bgBase,
                                            borderRadius:
                                                BorderRadius.circular(7),
                                            border: Border.all(
                                              color: activeSubStep
                                                      .subtask.completed
                                                  ? accentEmerald
                                                  : borderBright,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.check_rounded,
                                            size: 19,
                                            color:
                                                activeSubStep.subtask.completed
                                                    ? const Color(0xFF052E16)
                                                    : textMuted.withValues(
                                                        alpha: 0.35,
                                                      ),
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
                                      borderRadius: BorderRadius.circular(7),
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
                                                  : focalAccent)
                                              : bgBase.withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(7),
                                          border: Border.all(
                                            color:
                                                activeSubStep.subtask.completed
                                                    ? (isFinalCheckpointStep
                                                        ? accentEmerald
                                                        : focalAccent)
                                                    : borderSubtle,
                                          ),
                                        ),
                                        child: Text(
                                          advanceButtonLabel,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                activeSubStep.subtask.completed
                                                    ? (isFinalCheckpointStep
                                                        ? const Color(0xFF052E16)
                                                        : focalAccentFg)
                                                    : textMuted.withValues(
                                                        alpha: 0.45,
                                                      ),
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
                    );

                    // Right Full-Height Code / Blueprint Reference Pane (.opt2-right)
                    final rightPane = Container(
                      color: bgRecessed,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: bgBase,
                                  border: Border(
                                    bottom: BorderSide(color: borderSubtle),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '📍 ${activeSubStep.stepPath.isNotEmpty ? activeSubStep.stepPath : selectedHowTo.whereLocation}',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: textSecondary,
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
                                          onTap: () => copySubStepCodeFormula(
                                            selectedTaskIdx,
                                            activeSubStepIdx,
                                            activeSubStep.codeFormula,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: bgSurface,
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: borderSubtle,
                                              ),
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
                                                  copySubStepCodeFormula(
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
                                              BorderRadius.circular(5),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: bgSurface,
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: borderSubtle,
                                              ),
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
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  activeSubStep.codeFormula,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13,
                                    height: 1.65,
                                    color: isDark
                                        ? const Color(0xFFD1D5DB)
                                        : textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Bottom Step-Specific Quick Fix / Pitfall Footer Bar (#1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: bgBase,
                              border: Border(
                                top: BorderSide(color: borderSubtle),
                              ),
                            ),
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: textSecondary,
                                ),
                                children: [
                                  TextSpan(
                                    text: '🔧 Quick Fix / Pitfall: ',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary,
                                    ),
                                  ),
                                  TextSpan(text: pitfallOrGuardText),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (useTwoCol) {
                      return ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 420),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 48, child: leftPane),
                              Expanded(flex: 52, child: rightPane),
                            ],
                          ),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        leftPane,
                        rightPane,
                      ],
                    );
                  },
                ),
              ],
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
