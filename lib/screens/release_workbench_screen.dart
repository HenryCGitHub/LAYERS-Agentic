import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../agents/workspace_agent_tools.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import '../utils/feature_spec_binding.dart';
import '../utils/section_text_utils.dart';

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

class _ReleaseWorkbenchScreenState extends State<ReleaseWorkbenchScreen> {
  final Set<String> _expandedDoneCheckpoints = {};
  final Set<String> _collapsedOpenCheckpoints = {};
  final Set<String> _awaitingPlaytestVerification = {};
  final Map<String, TextEditingController> _newTaskControllers = {};
  final TextEditingController _copilotPromptController = TextEditingController();
  bool _showOutOfScopeShelf = false;
  bool _hideUnassignedSpecShelf = true;
  bool _showCoPilotDrawer = false;
  bool _showPillarsReferenceDrawer = false;
  bool _showBeatContextDetails = false;
  bool _isSinglePanelMode = true;
  bool _showAllCheckpointsInFocus = false;
  int? _manualCheckpointFocusIndex;
  String _selectedVersionFilter = 'ALL';
  bool _criticalPathOnly = false;
  final Map<String, int> _selectedTaskIndexByCheckpoint = {};
  final Map<String, int> _selectedSubStepIndexByTask = {};
  final Set<String> _expandedHowToTaskKeys = {};
  bool _unrealCppMode = false;
  bool _explainStepOpen = false;

  @override
  void dispose() {
    for (final c in _newTaskControllers.values) {
      c.dispose();
    }
    _copilotPromptController.dispose();
    super.dispose();
  }

  TextEditingController _controllerForCheckpoint(String checkpointId) {
    return _newTaskControllers.putIfAbsent(
      checkpointId,
      () => TextEditingController(),
    );
  }

  bool get _isDark => widget.workbench.isDark;
  Color get _bgBase => AppTheme.bgBaseFor(_isDark);
  Color get _bgSurface => AppTheme.bgSurfaceFor(_isDark);
  Color get _bgRecessed => AppTheme.bgSurfaceRecessedFor(_isDark);
  Color get _bgHover => AppTheme.bgSurfaceHoverFor(_isDark);
  Color get _borderSubtle => AppTheme.borderSubtleFor(_isDark);
  Color get _borderBright => AppTheme.borderBrightFor(_isDark);
  Color get _textPrimary => AppTheme.textPrimaryFor(_isDark);
  Color get _textSecondary => AppTheme.textSecondaryFor(_isDark);
  Color get _textMuted => AppTheme.textMutedFor(_isDark);
  Color get _focalAccent => AppTheme.focalAccentFor(_isDark);
  Color get _focalAccentFg => AppTheme.focalAccentFgFor(_isDark);
  Color get _accentEmerald => AppTheme.accentGreenFor(_isDark);
  Color get _accentCrimson => AppTheme.accentRedFor(_isDark);
  Color get _accentAmber => AppTheme.accentAmberFor(_isDark);

  @override
  Widget build(BuildContext context) {
    final rel = widget.workbench.activeRelease;
    if (rel == null) {
      return Center(
        child: Text(
          'No active Release loaded.',
          style: GoogleFonts.inter(color: _textMuted),
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
            color: _bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _borderBright),
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
                      color: _accentAmber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Building ${rel.title}...',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
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
                      Icon(Icons.check_circle, size: 14, color: _accentEmerald),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: _textSecondary,
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

  Widget _buildViewModeTogglePill() {
    return InkWell(
      key: const ValueKey('stage3_view_mode_toggle_btn'),
      onTap: () {
        setState(() {
          _isSinglePanelMode = !_isSinglePanelMode;
        });
      },
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _bgSurface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: _isSinglePanelMode ? _borderBright : _borderSubtle,
          ),
        ),
        child: Text(
          _isSinglePanelMode ? '▯ Single Panel' : '◫ Split View',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            color: _isSinglePanelMode ? _textPrimary : _textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildLeftBeatFeatureRail(TierDocument rel, {bool shrinkWrap = false}) {
    final beats = widget.workbench.activeReleaseBeats;
    final relProgress = widget.workbench.getDocumentProgress(rel.id);
    final releases = widget.workbench.projectReleases;
    final archivedFeats = widget.workbench.supersededFeatures;
    final activeVer = rel.sections['versionTag'] ?? 'v0.1';

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _bgBase,
            border: Border(bottom: BorderSide(color: _borderSubtle)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'OUTLINE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: _textSecondary,
                    ),
                  ),
                  Offstage(
                    offstage: true,
                    child: Text('ACTIVE RELEASE'),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Compact Release Selector Dropdown Pill (matches mockup "v0.1 Prototype ▾")
                  PopupMenuButton<String>(
                    key: const ValueKey('release_selector_dropdown_btn'),
                    color: _bgSurface,
                    tooltip: 'Switch Release View or Evolve Scope',
                    onSelected: (value) {
                      if (value == '__evolve__') {
                        widget.workbench.advanceToNextRelease();
                      } else if (value == '__replan__') {
                        widget.workbench.openReleasePlanGate(releaseId: rel.id);
                      } else if (value == '__toggle_view__') {
                        setState(() {
                          _isSinglePanelMode = !_isSinglePanelMode;
                        });
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
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'all',
                        child: Text(
                          '🌳 All Live Game Features ($activeVer)',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _textPrimary,
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
                              color: _textSecondary,
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
                              color: _textPrimary,
                            ),
                          ),
                        ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: '__toggle_view__',
                        child: Text(
                          _isSinglePanelMode
                              ? '◫ Switch to Full Studio Split View'
                              : '▯ Switch to Clean Single-Step View',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: '__replan__',
                        child: Text(
                          '✎ Edit ${rel.title} Scope in Plan Gate',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _textPrimary,
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
                            color: _accentEmerald,
                          ),
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _bgSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$activeVer ${rel.releaseScope.label} ▾',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildViewModeTogglePill(),
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
                color: _textMuted,
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
                            _showBeatContextDetails = true;
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
                                ? _accentEmerald
                                : (isBeatActive ? _textSecondary : _textMuted),
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
          color: _bgBase,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _borderSubtle),
        ),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _bgBase,
        border: Border(right: BorderSide(color: _borderSubtle)),
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
    final progress = widget.workbench.getDocumentProgress(feat.id);
    final isDone = progress >= 100;
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
              setState(() {
                _manualCheckpointFocusIndex = null;
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
                  SizedBox(
                    width: 12,
                    child: Text(
                      isSelected ? '▾' : '▸',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? _textSecondary : _textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      feat.title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isDone
                            ? _accentEmerald
                            : (isSelected ? _textPrimary : _textSecondary),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
          if (isSelected) _buildOutlineFeatureChildrenTree(feat),
        ],
      ),
    );
  }

  /// Renders the flat, borderless indented tree of Checkpoints -> Tasks -> Sub-Steps (1.1–1.6)
  /// directly under the selected Feature in the Left Outline Sidebar.
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

    final engineHint = widget.workbench.conceptDraft?.techSpec.join(' ') ??
        widget.workbench.activeProject?.sections['tech_spec'];

    return Container(
      margin: const EdgeInsets.fromLTRB(26, 2, 8, 6),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: _borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int cpIdx = 0; cpIdx < states.length; cpIdx++)
            Builder(
              builder: (context) {
                final cpNode = states[cpIdx];
                final isCpActive = cpIdx == effectiveCpIdx;
                final cpCode = 'CP ${(cpIdx + 1).toString().padLeft(2, '0')}';

                int activeTaskIdx = _selectedTaskIndexByCheckpoint[cpNode.id] ??
                    cpNode.checklist.indexWhere((t) => !t.completed);
                if (activeTaskIdx < 0 || activeTaskIdx >= cpNode.checklist.length) {
                  activeTaskIdx = 0;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      key: ValueKey('outline_cp_${feat.id}_$cpIdx'),
                      onTap: () {
                        setState(() {
                          _manualCheckpointFocusIndex = cpIdx;
                          _explainStepOpen = false;
                        });
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 5,
                        ),
                        child: Row(
                          children: [
                            Text(
                              isCpActive ? '▾' : '▸',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                color: isCpActive ? _textPrimary : _textMuted,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              cpCode,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: cpNode.isCompleted
                                    ? _accentEmerald
                                    : _textMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                cpNode.cleanStageTitle,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: isCpActive
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isCpActive
                                      ? _textPrimary
                                      : _textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isCpActive && cpNode.checklist.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(left: 10),
                        padding: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: _borderSubtle)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int tIdx = 0;
                                tIdx < cpNode.checklist.length;
                                tIdx++)
                              Builder(
                                builder: (context) {
                                  final task = cpNode.checklist[tIdx];
                                  final isTaskActive = tIdx == activeTaskIdx;
                                  final bp = TaskHowToBlueprint.resolve(
                                    parentTask: task,
                                    taskIndex: tIdx,
                                    checkpointNode: cpNode,
                                    engineHint: engineHint,
                                    unrealCppMode: _unrealCppMode,
                                  );
                                  final taskKey = '${cpNode.id}_$tIdx';
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
                                          setState(() {
                                            _selectedTaskIndexByCheckpoint[
                                                cpNode.id] = tIdx;
                                            _expandedHowToTaskKeys
                                              ..clear()
                                              ..add(taskKey);
                                            _explainStepOpen = false;
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(5),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4.5,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                task.completed
                                                    ? Icons.check_box_rounded
                                                    : Icons
                                                        .check_box_outline_blank_rounded,
                                                size: 13,
                                                color: task.completed
                                                    ? _accentEmerald
                                                    : (isTaskActive
                                                        ? _textPrimary
                                                        : _textMuted),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  bp.cleanTitle,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11.5,
                                                    fontWeight: isTaskActive
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                    color: task.completed
                                                        ? _textMuted
                                                        : (isTaskActive
                                                            ? _textPrimary
                                                            : _textSecondary),
                                                    decoration: task.completed
                                                        ? TextDecoration
                                                            .lineThrough
                                                        : TextDecoration.none,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${task.completedChildrenCount}/${task.totalChildrenCount}',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 9.5,
                                                  color: task.completed
                                                      ? _accentEmerald
                                                      : _textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (isTaskActive && bp.subSteps.isNotEmpty)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            left: 10,
                                            bottom: 4,
                                          ),
                                          padding: const EdgeInsets.only(left: 8),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              left: BorderSide(
                                                color: _borderSubtle,
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
                                                        sIdx == activeSubIdx;
                                                    final stepDone = step
                                                        .subtask.completed;
                                                    return InkWell(
                                                      key: ValueKey(
                                                        'outline_step_${cpNode.id}_${tIdx}_$sIdx',
                                                      ),
                                                      onTap: () {
                                                        setState(() {
                                                          _selectedSubStepIndexByTask[
                                                              taskKey] = sIdx;
                                                          _expandedHowToTaskKeys
                                                            ..clear()
                                                            ..add(taskKey);
                                                          _explainStepOpen =
                                                              false;
                                                        });
                                                      },
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 6,
                                                          vertical: 4,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: isStepActive
                                                              ? _bgRecessed
                                                              : Colors
                                                                  .transparent,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            InkWell(
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
                                                                  if (step
                                                                          .subtask
                                                                          .completed &&
                                                                      isStepActive) {
                                                                    final nextInc = task
                                                                        .children
                                                                        .indexWhere(
                                                                      (c) => !c
                                                                          .completed,
                                                                    );
                                                                    if (nextInc !=
                                                                        -1) {
                                                                      _selectedSubStepIndexByTask[
                                                                              taskKey] =
                                                                          nextInc;
                                                                    }
                                                                  }
                                                                });
                                                                widget.workbench
                                                                    .updateFeatureStates(
                                                                  feat.id,
                                                                  states,
                                                                );
                                                              },
                                                              child: Icon(
                                                                stepDone
                                                                    ? Icons
                                                                        .check_box_rounded
                                                                    : Icons
                                                                        .check_box_outline_blank_rounded,
                                                                size: 12.5,
                                                                color: stepDone
                                                                    ? _accentEmerald
                                                                    : (isStepActive
                                                                        ? _textPrimary
                                                                        : _textMuted),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Text(
                                                              '${tIdx + 1}.${sIdx + 1}',
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 9.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: isStepActive
                                                                    ? _textPrimary
                                                                    : _textMuted,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                step.shortTitle
                                                                        .isNotEmpty
                                                                    ? step
                                                                        .shortTitle
                                                                    : step
                                                                        .stepNumberLabel,
                                                                style:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontSize: 11,
                                                                  fontWeight: isStepActive
                                                                      ? FontWeight
                                                                          .w600
                                                                      : FontWeight
                                                                          .w400,
                                                                  color: stepDone
                                                                      ? _textMuted
                                                                      : (isStepActive
                                                                          ? _textPrimary
                                                                          : _textSecondary),
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
          style: GoogleFonts.inter(color: _textMuted),
        ),
      );
    }

    final states = FeatureStateNode.getStatesForDocument(feat);
    final specBinding = FeatureSpecBinding.resolveBindings(feat, states);
    final progress = widget.workbench.getDocumentProgress(feat.id).toDouble();
    final isDone = progress >= 100;
    final nextFeat = widget.workbench.nextIncompleteFeature;

    int totalTasks = 0;
    int completedTasks = 0;
    int completedCps = 0;
    int activeFocusIndex = -1;
    for (int i = 0; i < states.length; i++) {
      final s = states[i];
      final awaitingPlaytest = _awaitingPlaytestVerification.contains(s.id);
      if (s.isCompleted) {
        completedCps++;
      }
      // Keep the active focus spotlight on a checkpoint that just finished its tasks
      // until the user clicks "Verify Playtest & Advance"
      if (activeFocusIndex == -1 && (!s.isCompleted || awaitingPlaytest)) {
        activeFocusIndex = i;
      }
      totalTasks += s.totalChecklistCount;
      completedTasks += s.completedChecklistCount;
    }

    if (activeFocusIndex == -1 && states.isNotEmpty) {
      activeFocusIndex = states.length - 1;
    }
    final effectiveFocusIndex = (_manualCheckpointFocusIndex != null &&
            _manualCheckpointFocusIndex! >= 0 &&
            _manualCheckpointFocusIndex! < states.length)
        ? _manualCheckpointFocusIndex!
        : activeFocusIndex;
    final hasMultiVersionHistory =
        states.any((s) => (s.releaseVersion.trim().isNotEmpty ? s.releaseVersion.trim() : 'v0.1') != 'v0.1');

    final beats = widget.workbench.activeReleaseBeats;
    TierDocument? parentBeat;
    int parentBeatIdx = 0;
    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final bFeats = widget.workbench.featuresForBeat(beats[bIdx].id);
      if (bFeats.any((f) => f.id == feat.id)) {
        parentBeat = beats[bIdx];
        parentBeatIdx = bIdx;
        break;
      }
    }

    final activeFeatureContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Offstage(
          offstage: _isSinglePanelMode,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildUltraCompactFeatureHeader(
                feat,
                rel: rel,
                states: states,
                specBinding: specBinding,
                statsLabel:
                    '$completedCps/${states.length} cp · $completedTasks/$totalTasks tasks · ${feat.estimatedDuration}',
                progress: progress,
                isDone: isDone,
                presetLabel: rel.releaseScope.label,
              ),
              if (_showPillarsReferenceDrawer) ...[
                const SizedBox(height: 10),
                _buildStage1PillarsReferenceDrawer(),
              ],
              const SizedBox(height: 20),
              // Stage 1/2 style section header for Playable Checkpoints + Horizontal Stepper Tabs
              _buildCheckpointStepperBar(
                feat,
                states,
                effectiveFocusIndex: effectiveFocusIndex,
              ),
              if (hasMultiVersionHistory) ...[
                const SizedBox(height: 10),
                _buildVersionEvolutionTimelineBar(states),
              ],
              const SizedBox(height: 10),
            ],
          ),
        ),
        for (int i = 0; i < states.length; i++)
          if (_selectedVersionFilter == 'ALL' ||
              !states.any((s) => s.releaseVersion == _selectedVersionFilter) ||
              states[i].releaseVersion == _selectedVersionFilter)
            if (!_isSinglePanelMode ||
                !widget.workbench.focusMode ||
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
        Offstage(
          offstage: _isSinglePanelMode,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.workbench.isActiveReleaseComplete) ...[
                _buildReleaseShippedBanner(rel),
                const SizedBox(height: 14),
              ] else if (isDone && nextFeat != null) ...[
                _buildNextFeatureAdvanceBanner(feat, nextFeat),
                const SizedBox(height: 14),
              ],
              if (parentBeat != null) ...[
                _buildParentBeatContextBanner(parentBeat, parentBeatIdx),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        Container(
          key: const ValueKey('stage3_active_feature_sheet'),
          padding: _isSinglePanelMode
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: _isSinglePanelMode
              ? null
              : BoxDecoration(
                  color: _bgSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderBright),
                ),
          child: activeFeatureContent,
        ),
      ],
    );

    final bottomDock = Offstage(
      offstage: _isSinglePanelMode,
      child: _buildWorkbenchStickyBottomDock(
        rel,
        feat,
        states,
        specBinding,
        activeFocusIndex: activeFocusIndex,
        completedCps: completedCps,
      ),
    );

    if (shrinkWrap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (!_isSinglePanelMode) const SizedBox(height: 16),
          bottomDock,
        ],
      );
    }

    return Container(
      color: _isSinglePanelMode ? _bgSurface : _bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _isSinglePanelMode
                ? LayoutBuilder(
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
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1160),
                        child: body,
                      ),
                    ),
                  ),
          ),
          bottomDock,
        ],
      ),
    );
  }

  Widget _buildParentBeatContextBanner(TierDocument beat, int beatIdx) {
    final beatFeats = widget.workbench.featuresForBeat(beat.id);
    final doneBeatCount = beatFeats
        .where((f) => widget.workbench.getDocumentProgress(f.id) >= 100)
        .length;
    final allBeatDone = beatFeats.isNotEmpty && doneBeatCount == beatFeats.length;
    final beatGoal = SectionTextUtils.resolveGoal(beat.sections);
    final beatDoneWhen = SectionTextUtils.resolveDoneWhen(beat.sections);
    final beatCode = 'CORE LOOP BEAT·${(beatIdx + 1).toString().padLeft(2, '0')}';

    return Container(
      key: const ValueKey('stage3_beat_context_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: allBeatDone
                          ? _accentEmerald.withValues(alpha: 0.12)
                          : _bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: allBeatDone
                            ? _accentEmerald.withValues(alpha: 0.4)
                            : _borderBright,
                      ),
                    ),
                    child: Text(
                      beatCode,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: allBeatDone ? _accentEmerald : _textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    beat.title,
                    style: AppTheme.displayFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: _bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _borderSubtle),
                    ),
                    child: Text(
                      '$doneBeatCount/${beatFeats.length} features ${allBeatDone ? "✓" : "done"} · ${beat.estimatedDuration}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: allBeatDone ? _accentEmerald : _textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              InkWell(
                key: const ValueKey('toggle_beat_context_btn'),
                onTap: () {
                  setState(() {
                    _showBeatContextDetails = !_showBeatContextDetails;
                  });
                },
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _bgRecessed,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Text(
                    'Beat Context ${_showBeatContextDetails ? "▾" : "▸"}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_showBeatContextDetails &&
              (beatGoal.trim().isNotEmpty || beatDoneWhen.trim().isNotEmpty)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: _borderSubtle)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isTwoCol = constraints.maxWidth >= 620;
                  final goalItem = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: _borderSubtle),
                        ),
                        child: Text(
                          'BEAT GOAL',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          beatGoal,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.38,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ],
                  );
                  final doneItem = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: _accentEmerald.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          'BEAT DONE WHEN',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: _accentEmerald,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          beatDoneWhen,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.38,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                    ],
                  );
                  if (isTwoCol) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: goalItem),
                        const SizedBox(width: 14),
                        Expanded(child: doneItem),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      goalItem,
                      const SizedBox(height: 6),
                      doneItem,
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckpointStepperBar(
    TierDocument feat,
    List<FeatureStateNode> states, {
    required int effectiveFocusIndex,
  }) {
    final isFocus = widget.workbench.focusMode;

    return Container(
      key: const ValueKey('checkpoint_stepper_bar'),
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderSubtle)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _bgRecessed,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _borderBright),
                ),
                child: Text(
                  '01',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
              ),
              Text(
                'PLAYABLE CHECKPOINTS (${states.length})',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: _textPrimary,
                ),
              ),
              for (int i = 0; i < states.length; i++) ...[
                if (i > 0)
                  Text(
                    '→',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: _textMuted,
                    ),
                  ),
                Builder(
                  builder: (context) {
                    final cp = states[i];
                    final isDone = cp.isCompleted;
                    final isSelected = i == effectiveFocusIndex;
                    return InkWell(
                      key: ValueKey('checkpoint_step_pill_$i'),
                      onTap: () {
                        setState(() {
                          _manualCheckpointFocusIndex = i;
                          _expandedDoneCheckpoints.add(cp.id);
                          _collapsedOpenCheckpoints.remove(cp.id);
                        });
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _bgHover
                              : (isDone
                                  ? _accentEmerald.withValues(alpha: 0.12)
                                  : _bgRecessed),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: isSelected
                                ? _borderBright
                                : (isDone
                                    ? _accentEmerald.withValues(alpha: 0.42)
                                    : _borderSubtle),
                          ),
                        ),
                        child: Text(
                          '${isDone ? "✓" : (isSelected ? "●" : "○")} CP ${(i + 1).toString().padLeft(2, '0')} · ${cp.cleanStageTitle} (${cp.completedChecklistCount}/${cp.totalChecklistCount})',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? _textPrimary
                                : (isDone ? _accentEmerald : _textSecondary),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_isSinglePanelMode && isFocus && states.length > 1)
                InkWell(
                  key: const ValueKey('toggle_all_checkpoints_focus_btn'),
                  onTap: () {
                    setState(() {
                      _showAllCheckpointsInFocus = !_showAllCheckpointsInFocus;
                    });
                  },
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _bgSurface,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: _borderSubtle),
                    ),
                    child: Text(
                      _showAllCheckpointsInFocus
                          ? 'Show Active Only'
                          : 'View All (${states.length})',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                ),
              InkWell(
                key: const ValueKey('add_checkpoint_header_btn'),
                onTap: () => _promptAddCheckpointDialog(feat, states),
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _bgSurface,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Text(
                    '+ Add Checkpoint',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
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

  /// Option 3: Interactive Cross-Release Version Evolution Timeline Bar (`ALL VERSIONS` · `v0.1 ✓` · `v0.2 ●`).
  Widget _buildVersionEvolutionTimelineBar(List<FeatureStateNode> states) {
    final versions = <String>[];
    for (final s in states) {
      final ver = s.releaseVersion.trim().isNotEmpty ? s.releaseVersion.trim() : 'v0.1';
      if (!versions.contains(ver)) {
        versions.add(ver);
      }
    }
    if (versions.isEmpty) {
      versions.add('v0.1');
    }

    final effectiveFilter = (_selectedVersionFilter == 'ALL' ||
            versions.contains(_selectedVersionFilter))
        ? _selectedVersionFilter
        : 'ALL';

    return Container(
      key: const ValueKey('version_timeline_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderSubtle),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'VERSION TIMELINE:',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: _textMuted,
            ),
          ),
          InkWell(
            key: const ValueKey('version_filter_pill_ALL'),
            onTap: () {
              setState(() {
                _selectedVersionFilter = 'ALL';
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: effectiveFilter == 'ALL'
                    ? _bgHover
                    : _bgRecessed,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: effectiveFilter == 'ALL'
                      ? _borderBright
                      : _borderSubtle,
                ),
              ),
              child: Text(
                'ALL VERSIONS (${states.length} CPs)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: effectiveFilter == 'ALL'
                      ? _textPrimary
                      : _textSecondary,
                ),
              ),
            ),
          ),
          for (int vIdx = 0; vIdx < versions.length; vIdx++) ...[
            if (vIdx > 0)
              Text(
                '→',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  color: _textMuted,
                ),
              ),
            Builder(
              builder: (context) {
                final ver = versions[vIdx];
                final verStates = states
                    .where((s) =>
                        (s.releaseVersion.trim().isNotEmpty
                            ? s.releaseVersion.trim()
                            : 'v0.1') ==
                        ver)
                    .toList();
                final doneCount =
                    verStates.where((s) => s.isCompleted).length;
                final allVerDone =
                    verStates.isNotEmpty && doneCount == verStates.length;
                final isSelected = effectiveFilter == ver;

                return InkWell(
                  key: ValueKey('version_filter_pill_$ver'),
                  onTap: () {
                    setState(() {
                      _selectedVersionFilter =
                          _selectedVersionFilter == ver ? 'ALL' : ver;
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _bgHover
                          : _bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? _borderBright
                            : (allVerDone
                                ? _accentEmerald.withValues(alpha: 0.45)
                                : _borderSubtle),
                      ),
                    ),
                    child: Text(
                      '$ver ${allVerDone ? "✓" : "●"} ($doneCount/${verStates.length})',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: allVerDone
                            ? _accentEmerald
                            : (isSelected ? _textPrimary : _textSecondary),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
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
        color: _bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderBright),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: _accentEmerald,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${completedFeat.title} is 100% VERIFIED ✓! Ready for the next feature in your loop?',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
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
              backgroundColor: _focalAccent,
              foregroundColor: _focalAccentFg,
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
        color: _accentEmerald.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentEmerald.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, color: _accentEmerald, size: 18),
              const SizedBox(width: 10),
              Text(
                'All Checkpoints in ${rel.title} are VERIFIED ✓!',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
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
                  foregroundColor: _accentEmerald,
                  side: BorderSide(color: _accentEmerald.withValues(alpha: 0.5)),
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
                  backgroundColor: _focalAccent,
                  foregroundColor: _focalAccentFg,
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

  void _showFeatureScriptBundleModal(
    BuildContext context,
    TierDocument feat,
    List<FeatureStateNode> states,
  ) {
    final bundle = widget.workbench.generateStarterScriptForFeature(feat, states);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('feature_script_bundle_dialog'),
        backgroundColor: _bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: _accentEmerald.withValues(alpha: 0.55)),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _accentEmerald.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    bundle.engineLabel.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: _accentEmerald,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  bundle.fileName,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
            Text(
              '${bundle.exportedVariables.length} tuning vars · ${bundle.embeddedGuards.length} guards',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: _textMuted,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 680,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 420),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _bgRecessed,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderSubtle),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                bundle.code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  height: 1.48,
                  color: _textPrimary,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: GoogleFonts.inter(fontSize: 12, color: _textSecondary),
            ),
          ),
          ElevatedButton.icon(
            key: const ValueKey('copy_starter_script_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _focalAccent,
              foregroundColor: _focalAccentFg,
              elevation: 0,
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: bundle.code));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: _bgSurface,
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    'Copied ${bundle.fileName} to clipboard ✓',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _accentEmerald,
                    ),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: Text(
              'Copy ${bundle.fileName}',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
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
    int totalCheckpoints = 0;
    int totalTasks = 0;
    for (final f in allFeats) {
      final states = FeatureStateNode.getStatesForDocument(f);
      totalCheckpoints += states.length;
      for (final s in states) {
        totalTasks += s.totalChecklistCount;
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: _accentEmerald.withValues(alpha: 0.6)),
        ),
        title: Row(
          children: [
            Icon(Icons.rocket_launch_rounded, color: _accentEmerald, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${rel.title} — 100% Shipped & Playtested ✓',
                style: AppTheme.displayFont(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
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
                'Every playable checkpoint and How-To sub-step across your Core Loop has been verified:',
                style: GoogleFonts.inter(fontSize: 12.5, color: _textSecondary),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _bgRecessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _borderSubtle),
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
                            color: _accentEmerald,
                          ),
                        ),
                        Text(
                          'CORE BEATS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: _textMuted,
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
                            color: _accentAmber,
                          ),
                        ),
                        Text(
                          'FEATURES',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: _textMuted,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '$totalCheckpoints',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _accentEmerald,
                          ),
                        ),
                        Text(
                          'CHECKPOINTS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: _textMuted,
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
                            color: _textPrimary,
                          ),
                        ),
                        Text(
                          'TASKS DONE',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: _textMuted,
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
                  color: _bgRecessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AGENT RETROSPECTIVE · PLAYTEST HARDENING & CARRYOVER',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: _accentAmber,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• ${retro.fixTasksTriaged} playtest [FIX] task(s) triaged · ${retro.playtestGuardsAdded} [PLAYTEST/SIMULATION GUARD] rules locked into live tree',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: _textSecondary,
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
                            color: _accentAmber,
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
              style: GoogleFonts.inter(fontSize: 12, color: _textSecondary),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _focalAccent,
              foregroundColor: _focalAccentFg,
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

  Widget _buildStage1PillarsReferenceDrawer() {
    final draft = widget.workbench.conceptDraft;
    final pillars = draft?.designPillars ?? const <String>[];
    final tradeOffs = draft?.tradeOffs ?? const <String>[];
    final gameSpec = draft?.gameSpec ?? const <String>[];
    final techSpec = draft?.techSpec ?? const <String>[];

    Widget buildColumn({
      required String badge,
      required Color badgeColor,
      required List<String> items,
      required String emptyHint,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _bgRecessed,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                badge,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: badgeColor,
                ),
              ),
              const SizedBox(height: 6),
              if (items.isEmpty)
                Text(
                  emptyHint,
                  style: GoogleFonts.inter(fontSize: 11, color: _textMuted),
                )
              else
                for (final item in items.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              height: 1.35,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('stage3_pillars_reference_drawer'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderBright),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '◈ STAGE 1 CONCEPT GUARDRAILS — DESIGN PILLARS, TRADE-OFFS & SPEC',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: _textPrimary,
                ),
              ),
              InkWell(
                onTap: () => widget.workbench.setStage(WorkbenchStage.projectPitch),
                child: Text(
                  'Edit in Stage 1 ↗',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: _textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildColumn(
                  badge: '04 · DESIGN PILLARS (PLAYER FEEL)',
                  badgeColor: _textPrimary,
                  items: pillars,
                  emptyHint: 'No Design Pillars defined yet.',
                ),
                const SizedBox(width: 8),
                buildColumn(
                  badge: '05 · TRADE-OFFS (X OVER Y)',
                  badgeColor: _textPrimary,
                  items: tradeOffs,
                  emptyHint: 'No Trade-Off rules defined yet.',
                ),
                const SizedBox(width: 8),
                buildColumn(
                  badge: '02–03 · GAME & TECH SPEC',
                  badgeColor: _textPrimary,
                  items: [...gameSpec.take(2), ...techSpec.take(2)],
                  emptyHint: 'No Game/Tech Spec defined yet.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUltraCompactFeatureHeader(
    TierDocument feat, {
    required TierDocument rel,
    required List<FeatureStateNode> states,
    required FeatureSpecBindingResult specBinding,
    required String statsLabel,
    required double progress,
    required bool isDone,
    required String presetLabel,
  }) {
    final scopeGoal = SectionTextUtils.resolveGoal(feat.sections);
    final doneIf = SectionTextUtils.resolveDoneWhen(feat.sections);
    final outOfScope = SectionTextUtils.resolveExclusions(
      feat.sections,
      splitSingleSentence: false,
    );
    final beats = widget.workbench.activeReleaseBeats;
    final allFeats = <TierDocument>[
      for (final b in beats) ...widget.workbench.featuresForBeat(b.id),
    ];
    final currentFeatIdx = allFeats.indexWhere((f) => f.id == feat.id);
    final prevFeat = currentFeatIdx > 0 ? allFeats[currentFeatIdx - 1] : null;
    final nextSequentialFeat =
        (currentFeatIdx != -1 && currentFeatIdx < allFeats.length - 1)
            ? allFeats[currentFeatIdx + 1]
            : null;

    int activeBeatIdx = 0;
    int activeFeatIdxInBeat = 0;
    String activeBeatTitle = '';
    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final bFeats = widget.workbench.featuresForBeat(beats[bIdx].id);
      final fIdx = bFeats.indexWhere((f) => f.id == feat.id);
      if (fIdx != -1) {
        activeBeatIdx = bIdx;
        activeFeatIdxInBeat = fIdx;
        activeBeatTitle = beats[bIdx].title;
        break;
      }
    }
    final activeDepTier = WorkspaceAgentOrchestrator.classifyDependencyTier(
      featureTitle: feat.title,
      beatIndex: activeBeatIdx,
      featureIndexInBeat: activeFeatIdxInBeat,
    );
    final featCode = 'FEAT·${(currentFeatIdx + 1).toString().padLeft(2, '0')}';

    Widget tag(String text, Color color, {double? width}) => Container(
          width: width,
          alignment: width != null ? Alignment.center : null,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
          ),
          child: Text(
            text,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
        );

    Widget buildCalloutBar({
      required String label,
      required Color accentColor,
      required String text,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _bgRecessed,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _borderSubtle),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: 68,
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _bgSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: accentColor == _focalAccent
                          ? _textSecondary
                          : accentColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Eyebrow Bar (Stage 1 / Stage 2 Studio Style)
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: _borderSubtle)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: _bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _borderSubtle),
                    ),
                    child: Text(
                      'BEAT·${(activeBeatIdx + 1).toString().padLeft(2, '0')} · ${activeBeatTitle.split(':').first.split('—').first.trim().toUpperCase()}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: _bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _borderSubtle,
                      ),
                    ),
                    child: Text(
                      activeDepTier.shortBadge,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: _bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _borderSubtle),
                    ),
                    child: Text(
                      statsLabel,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    key: const ValueKey('generate_feature_script_btn'),
                    onTap: () => _showFeatureScriptBundleModal(
                      context,
                      feat,
                      states,
                    ),
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _bgRecessed,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: _borderSubtle,
                        ),
                      ),
                      child: Text(
                        '✦ Script',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: _textSecondary,
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    key: const ValueKey('toggle_pillars_drawer_btn'),
                    onTap: () {
                      setState(() {
                        _showPillarsReferenceDrawer =
                            !_showPillarsReferenceDrawer;
                      });
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _bgRecessed,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: _showPillarsReferenceDrawer
                              ? _borderBright
                              : _borderSubtle,
                        ),
                      ),
                      child: Text(
                        '◈ Pillars ${_showPillarsReferenceDrawer ? "▴" : "▾"}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: _showPillarsReferenceDrawer
                              ? _textPrimary
                              : _textSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (outOfScope.isNotEmpty)
                    InkWell(
                      key: const ValueKey('feat_out_of_scope_btn'),
                      onTap: () {
                        setState(() {
                          _showOutOfScopeShelf = !_showOutOfScopeShelf;
                        });
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: _showOutOfScopeShelf
                                ? _accentCrimson.withValues(alpha: 0.45)
                                : _borderSubtle,
                          ),
                        ),
                        child: Text(
                          '⊘ ${outOfScope.length} Out ${_showOutOfScopeShelf ? "▴" : "▾"}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: _showOutOfScopeShelf
                                ? _accentCrimson
                                : _textMuted,
                          ),
                        ),
                      ),
                    ),
                  if (specBinding.hasUnassigned)
                    InkWell(
                      key: const ValueKey('feat_unassigned_spec_btn'),
                      onTap: () {
                        setState(() {
                          _hideUnassignedSpecShelf = !_hideUnassignedSpecShelf;
                        });
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: _borderSubtle,
                          ),
                        ),
                        child: Text(
                          '${specBinding.totalUnassignedCount} unassigned',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // Hero Feature Title Dropdown + Prev/Next Buttons
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PopupMenuButton<String>(
              key: const ValueKey('stage3_feature_dropdown_btn'),
              color: _bgSurface,
              tooltip: 'Switch Active Feature',
              onSelected: (featId) {
                setState(() {
                  _manualCheckpointFocusIndex = null;
                });
                widget.workbench.selectFeature(featId);
              },
              itemBuilder: (context) {
                final entries = <PopupMenuEntry<String>>[];
                int seq = 0;
                for (int bIdx = 0; bIdx < beats.length; bIdx++) {
                  final b = beats[bIdx];
                  final bFeats = widget.workbench.featuresForBeat(b.id);
                  if (bFeats.isEmpty) continue;
                  if (entries.isNotEmpty) {
                    entries.add(const PopupMenuDivider());
                  }
                  final doneInBeat = bFeats
                      .where(
                        (f) => widget.workbench.getDocumentProgress(f.id) >= 100,
                      )
                      .length;
                  entries.add(
                    PopupMenuItem<String>(
                      enabled: false,
                      height: 26,
                      child: Text(
                        'BEAT ${(bIdx + 1).toString().padLeft(2, '0')} · ${b.title.toUpperCase()} ($doneInBeat/${bFeats.length})',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: _accentEmerald,
                        ),
                      ),
                    ),
                  );
                  for (final f in bFeats) {
                    seq++;
                    final fProg = widget.workbench.getDocumentProgress(f.id);
                    final fDone = fProg >= 100;
                    final fSel = f.id == feat.id;
                    entries.add(
                      PopupMenuItem<String>(
                        value: f.id,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${fDone ? "✓" : (fSel ? "●" : "○")} ${seq.toString().padLeft(2, '0')} · ${f.title}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: fSel
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: fSel
                                      ? _textPrimary
                                      : (fDone ? _accentEmerald : _textSecondary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$fProg%',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: fDone ? _accentEmerald : _textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                }
                return entries;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _bgRecessed,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _borderBright),
                      ),
                      child: Text(
                        featCode,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        feat.title,
                        style: AppTheme.displayFont(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDone
                            ? _accentEmerald.withValues(alpha: 0.14)
                            : _bgRecessed,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDone
                              ? _accentEmerald.withValues(alpha: 0.45)
                              : _borderSubtle,
                        ),
                      ),
                      child: Text(
                        '${progress.round()}%',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isDone ? _accentEmerald : _textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: _textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (allFeats.length > 1)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    key: const ValueKey('prev_feature_btn'),
                    onTap: prevFeat == null
                        ? null
                        : () {
                            setState(() {
                              _manualCheckpointFocusIndex = null;
                            });
                            widget.workbench.selectFeature(prevFeat.id);
                          },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _bgRecessed,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: _borderSubtle),
                      ),
                      child: Text(
                        '← Prev',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: prevFeat == null
                              ? _textMuted.withValues(alpha: 0.45)
                              : _textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    key: const ValueKey('next_feature_btn'),
                    onTap: nextSequentialFeat == null
                        ? null
                        : () {
                            setState(() {
                              _manualCheckpointFocusIndex = null;
                            });
                            widget.workbench.selectFeature(
                              nextSequentialFeat.id,
                            );
                          },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _bgRecessed,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: nextSequentialFeat == null
                              ? _borderSubtle
                              : _borderBright,
                        ),
                      ),
                      child: Text(
                        'Next →',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: nextSequentialFeat == null
                              ? _textMuted.withValues(alpha: 0.45)
                              : _textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 14),
        // Stage 2 Callout Bars for GOAL and DONE WHEN
        LayoutBuilder(
          builder: (context, constraints) {
            final isTwoCol = constraints.maxWidth >= 620;
            final goalBar = buildCalloutBar(
              label: 'GOAL',
              accentColor: _focalAccent,
              text: scopeGoal,
            );
            final doneBar = buildCalloutBar(
              label: 'DONE WHEN',
              accentColor: _accentEmerald,
              text: doneIf,
            );
            if (isTwoCol) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: goalBar),
                  const SizedBox(width: 10),
                  Expanded(child: doneBar),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                goalBar,
                const SizedBox(height: 8),
                doneBar,
              ],
            );
          },
        ),
        if (_showOutOfScopeShelf && outOfScope.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('feat_out_of_scope_shelf'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: _bgRecessed,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderSubtle),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTwoCol =
                    constraints.maxWidth >= 480 && outOfScope.length > 1;
                final colWidth = isTwoCol
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (final item in outOfScope)
                      SizedBox(
                        width: colWidth,
                        child: Row(
                          children: [
                            tag('CUT', _accentCrimson, width: 42),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
        if (specBinding.hasUnassigned && !_hideUnassignedSpecShelf) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('feat_inline_spec_shelf'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: _bgRecessed,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderSubtle),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final sc in specBinding.unassignedScope)
                  Text(
                    '✓ $sc',
                    style: GoogleFonts.inter(fontSize: 10.5, color: _textPrimary),
                  ),
                for (final t in specBinding.unassignedTuning)
                  Text(
                    '⚙ $t',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: _textPrimary,
                    ),
                  ),
                for (final e in specBinding.unassignedEdgeCases)
                  Text(
                    '⚠ $e',
                    style: GoogleFonts.inter(fontSize: 10.5, color: _textPrimary),
                  ),
              ],
            ),
          ),
        ],
      ],
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
    final isAwaitingPlaytest = isDone && _awaitingPlaytestVerification.contains(node.id);
    final isActiveFocus = index == activeFocusIndex;
    final isFocusMode = widget.workbench.focusMode;

    // In Focus Mode:
    // - Verified checkpoints default to collapsed unless awaiting Playtest confirmation or explicitly expanded
    // - The single Active Focus checkpoint defaults to expanded unless explicitly collapsed
    // - Future ("UP NEXT") checkpoints default to collapsed unless explicitly expanded
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

    final scopedItems = specBinding.checkpointScope[node.id] ?? const <String>[];
    final tuningItems = specBinding.checkpointTuning[node.id] ?? const <String>[];
    final edgeItems = specBinding.checkpointEdgeCases[node.id] ?? const <String>[];
    final verStamp = node.releaseVersion;
    final taskCtrl = _controllerForCheckpoint(node.id);

    void submitNewTask() {
      final text = taskCtrl.text.trim();
      if (text.isEmpty) return;
      taskCtrl.clear();
      setState(() {
        node.checklist.add(
          Subtask(
            id: generateUniqueId('check'),
            text: text,
            completed: false,
          ),
        );
        _awaitingPlaytestVerification.remove(node.id);
      });
      widget.workbench.updateFeatureStates(feat.id, states);
    }

    Future<void> promptTuningDialog({int? editIdx, String? currentVal}) async {
      final ctrl = TextEditingController(text: currentVal ?? '');
      void applyPercentageBump(double multiplier) {
        final raw = ctrl.text;
        final match = RegExp(r'(-?\d+(?:\.\d+)?)').firstMatch(raw);
        if (match == null) return;
        final currentNum = double.tryParse(match.group(1)!);
        if (currentNum == null) return;
        final nextNum = currentNum * multiplier;
        final hasDecimal = match.group(1)!.contains('.');
        final formatted = (!hasDecimal && (nextNum - nextNum.round()).abs() < 0.05)
            ? '${nextNum.round()}'
            : nextNum
                .toStringAsFixed(2)
                .replaceAll(RegExp(r'0+$'), '')
                .replaceAll(RegExp(r'\.$'), '');
        ctrl.text = raw.replaceRange(match.start, match.end, formatted);
        ctrl.selection = TextSelection.fromPosition(
          TextPosition(offset: ctrl.text.length),
        );
      }

      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => AlertDialog(
            backgroundColor: _bgSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: _borderBright),
            ),
            title: Text(
              editIdx == null ? 'Add Tuning Parameter' : 'Edit Tuning Parameter',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const ValueKey('tuning_param_input'),
                    controller: ctrl,
                    autofocus: true,
                    onChanged: (_) => setModalState(() {}),
                    onSubmitted: (_) => Navigator.of(ctx).pop('save'),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12.5,
                      color: _textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g., move_speed: 220 px/s',
                      hintStyle: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        color: _textMuted,
                      ),
                      filled: true,
                      fillColor: _bgRecessed,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: _borderSubtle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'QUICK-BUMP:',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: _textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      for (final bump in const [
                        (label: '-25%', mult: 0.75, key: 'tuning_bump_minus25_btn'),
                        (label: '-10%', mult: 0.90, key: 'tuning_bump_minus10_btn'),
                        (label: '+10%', mult: 1.10, key: 'tuning_bump_plus10_btn'),
                        (label: '+25%', mult: 1.25, key: 'tuning_bump_plus25_btn'),
                      ]) ...[
                        InkWell(
                          key: ValueKey(bump.key),
                          onTap: () {
                            setModalState(() {
                              applyPercentageBump(bump.mult);
                            });
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _accentAmber.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _accentAmber.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              bump.label,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: _accentAmber,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              if (editIdx != null)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('delete'),
                  child: Text(
                    'Delete',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _accentCrimson,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('cancel'),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _textSecondary,
                  ),
                ),
              ),
              ElevatedButton(
                key: const ValueKey('save_tuning_param_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _focalAccent,
                  foregroundColor: _focalAccentFg,
                  elevation: 0,
                ),
                onPressed: () => Navigator.of(ctx).pop('save'),
                child: Text(
                  'Save',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (!mounted || action == null || action == 'cancel') return;
      final updatedTuning = List<String>.from(tuningItems);
      if (action == 'delete' && editIdx != null && editIdx < updatedTuning.length) {
        updatedTuning.removeAt(editIdx);
      } else if (action == 'save') {
        final trimmed = ctrl.text.trim();
        if (trimmed.isEmpty) return;
        if (editIdx != null && editIdx < updatedTuning.length) {
          updatedTuning[editIdx] = trimmed;
        } else {
          updatedTuning.add(trimmed);
        }
      }
      setState(() {
        node.tuningParams = updatedTuning;
      });
      widget.workbench.updateFeatureStates(feat.id, states);
    }

    Future<void> promptLogPlaytestIssueDialog() async {
      final ctrl = TextEditingController();
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: _borderBright),
          ),
          title: Row(
            children: [
              Icon(Icons.flag_rounded, size: 16, color: _accentCrimson),
              const SizedBox(width: 8),
              Text(
                'Log Playtest Issue / Triage',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
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
                  'Describe what failed or felt off during viewport playtesting. This appends a [FIX] task (with 3 checkable debug/fix sub-steps) and pins a [PLAYTEST GUARD] edge case.',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    height: 1.45,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('playtest_issue_input'),
                  controller: ctrl,
                  autofocus: true,
                  maxLines: 2,
                  onSubmitted: (_) => Navigator.of(ctx).pop('log'),
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: _textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'e.g., Hook pulls player through thin walls on high velocity',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: _textMuted,
                    ),
                    filled: true,
                    fillColor: _bgRecessed,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderSubtle),
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
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _textSecondary,
                ),
              ),
            ),
            ElevatedButton.icon(
              key: const ValueKey('confirm_playtest_issue_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentCrimson,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              onPressed: () => Navigator.of(ctx).pop('log'),
              icon: const Icon(Icons.build_circle_outlined, size: 14),
              label: Text(
                'Create [FIX] Task & Guard',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
      if (!mounted || action != 'log') return;
      final issueText = ctrl.text.trim();
      if (issueText.isEmpty) return;
      final newIdx = widget.workbench.logPlaytestIssueOnCheckpoint(
        featureId: feat.id,
        states: states,
        checkpointIndex: index,
        issueDescription: issueText,
      );
      if (newIdx >= 0) {
        setState(() {
          _selectedTaskIndexByCheckpoint[node.id] = newIdx;
          _awaitingPlaytestVerification.remove(node.id);
        });
      }
    }

    Future<void> promptPlaytestDialog() async {
      final ctrl = TextEditingController(text: node.playtestCondition);
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: _borderBright),
          ),
          title: Text(
            'Edit Playtest Criteria',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            onSubmitted: (_) => Navigator.of(ctx).pop('save'),
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: _textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'e.g., Walk across all 4 walls and verify smooth sliding.',
              hintStyle: GoogleFonts.inter(
                fontSize: 11.5,
                color: _textMuted,
              ),
              filled: true,
              fillColor: _bgRecessed,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: _borderSubtle),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _focalAccent,
                foregroundColor: _focalAccentFg,
                elevation: 0,
              ),
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: Text(
                'Save',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
      if (!mounted || action != 'save') return;
      final trimmed = ctrl.text.trim();
      if (trimmed.isEmpty) return;
      setState(() {
        node.trigger = trimmed;
      });
      widget.workbench.updateFeatureStates(feat.id, states);
    }

    Future<void> promptEdgeCaseDialog({int? editIdx, String? currentVal}) async {
      final ctrl = TextEditingController(text: currentVal ?? '');
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: _borderBright),
          ),
          title: Text(
            editIdx == null ? 'Add Edge-Case Guard' : 'Edit Edge-Case Guard',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            onSubmitted: (_) => Navigator.of(ctx).pop('save'),
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: _textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'e.g., [GUARD] Prevent movement during hitstun',
              hintStyle: GoogleFonts.inter(
                fontSize: 11.5,
                color: _textMuted,
              ),
              filled: true,
              fillColor: _bgRecessed,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: _borderSubtle),
              ),
            ),
          ),
          actions: [
            if (editIdx != null)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('delete'),
                child: Text(
                  'Delete',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _accentCrimson,
                  ),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _focalAccent,
                foregroundColor: _focalAccentFg,
                elevation: 0,
              ),
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: Text(
                'Save',
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
      final updatedEdges = List<String>.from(edgeItems);
      if (action == 'delete' && editIdx != null && editIdx < updatedEdges.length) {
        updatedEdges.removeAt(editIdx);
      } else if (action == 'save') {
        final trimmed = ctrl.text.trim();
        if (trimmed.isEmpty) return;
        if (editIdx != null && editIdx < updatedEdges.length) {
          updatedEdges[editIdx] = trimmed;
        } else {
          updatedEdges.add(trimmed);
        }
      }
      setState(() {
        node.edgeCases = updatedEdges;
      });
      widget.workbench.updateFeatureStates(feat.id, states);
    }

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
          backgroundColor: _bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: _borderBright),
          ),
          title: Text(
            'Edit How-To Sub-Step (${pIdx + 1}.${sIdx + 1})',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
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
                  style: GoogleFonts.inter(fontSize: 12.5, color: _textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Sub-step Title',
                    labelStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      color: _textSecondary,
                    ),
                    filled: true,
                    fillColor: _bgRecessed,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderSubtle),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('edit_substep_instruction_input'),
                  controller: instrCtrl,
                  maxLines: 2,
                  style: GoogleFonts.inter(fontSize: 12, color: _textPrimary),
                  decoration: InputDecoration(
                    labelText: 'How-To Instruction',
                    labelStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      color: _textSecondary,
                    ),
                    filled: true,
                    fillColor: _bgRecessed,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderSubtle),
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
                    color: AppTheme.accentCyanFor(_isDark),
                  ),
                  decoration: InputDecoration(
                    labelText: 'Code Formula / Snippet',
                    labelStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      color: _textSecondary,
                    ),
                    filled: true,
                    fillColor: _bgRecessed,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderSubtle),
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
                    color: _accentCrimson,
                  ),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(fontSize: 12, color: _textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _focalAccent,
                foregroundColor: _focalAccentFg,
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

    void addCustomHowToSubStep(int pIdx) {
      if (pIdx < 0 || pIdx >= node.checklist.length) return;
      final parentTask = node.checklist[pIdx];
      final nextSubNum = parentTask.children.length + 1;
      setState(() {
        parentTask.children.add(
          Subtask(
            id: generateUniqueId('${parentTask.id}_sub$nextSubNum'),
            text: 'Custom Verification & Tuning Pass',
            completed: false,
            specNotes:
                'Verify custom step ${pIdx + 1}.$nextSubNum in the active scene and confirm smooth frame timing.',
            codeSnippet: '// Custom verification / formula step ${pIdx + 1}.$nextSubNum',
            codeTargetFile: 'custom_snippet',
          ),
        );
        parentTask.completed = false;
        _awaitingPlaytestVerification.remove(node.id);
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
          backgroundColor: _bgSurface,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Copied Step ${pIdx + 1}.${sIdx + 1} code formula to clipboard ✓',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _accentEmerald,
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
          backgroundColor: _bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: _borderBright),
          ),
          title: Text(
            '✦ Tailor How-To Sub-Steps (Task ${(pIdx + 1).toString().padLeft(2, '0')})',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Describe your exact Scene / Node / Script setup for "${parentTask.text}". The Agent will rewrite Steps ${pIdx + 1}.1, ${pIdx + 1}.2, and ${pIdx + 1}.3 using your exact node and script names:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.4,
                    color: _textSecondary,
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
                    color: _textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'e.g., CharacterBody2D with RayCast2D HookRay and Line2D RopeVisual',
                    hintStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: _textMuted,
                    ),
                    filled: true,
                    fillColor: _bgRecessed,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: _borderSubtle),
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
                style: GoogleFonts.inter(fontSize: 12, color: _textSecondary),
              ),
            ),
            ElevatedButton(
              key: const ValueKey('confirm_tailor_howto_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _focalAccent,
                foregroundColor: _focalAccentFg,
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
          backgroundColor: _bgSurface,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Tailored Task ${(pIdx + 1).toString().padLeft(2, '0')} How-To sub-steps to "$contextText" ✓',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _accentEmerald,
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    void toggleParentTaskCompletion(int tIdx) {
      final wasDone = node.isCompleted;
      final task = node.checklist[tIdx];
      final nextState = !task.completed;
      task.completed = nextState;
      for (final child in task.children) {
        child.completed = nextState;
      }
      final nowDone = node.isCompleted;
      setState(() {
        if (nextState) {
          final nextIncomplete = node.checklist.indexWhere((t) => !t.completed);
          if (nextIncomplete != -1) {
            _selectedTaskIndexByCheckpoint[node.id] = nextIncomplete;
          }
        } else {
          _selectedTaskIndexByCheckpoint[node.id] = tIdx;
        }
        if (!wasDone && nowDone) {
          _awaitingPlaytestVerification.add(node.id);
        } else if (!nowDone) {
          _awaitingPlaytestVerification.remove(node.id);
        }
      });
      widget.workbench.updateFeatureStates(feat.id, states);
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
        if (nextCompleted) {
          int nextInc = -1;
          for (int i = sIdx + 1; i < parentTask.children.length; i++) {
            if (!parentTask.children[i].completed) {
              nextInc = i;
              break;
            }
          }
          if (nextInc == -1) {
            nextInc = parentTask.children.indexWhere((c) => !c.completed);
          }
          if (nextInc != -1) {
            _selectedSubStepIndexByTask['${node.id}_$pIdx'] = nextInc;
          }
        } else {
          _selectedSubStepIndexByTask['${node.id}_$pIdx'] = sIdx;
        }
        if (!wasDone && nowDone) {
          _awaitingPlaytestVerification.add(node.id);
        } else if (!nowDone) {
          _awaitingPlaytestVerification.remove(node.id);
        }
      });
      widget.workbench.updateFeatureStates(feat.id, states);
    }

    void markActiveStepDoneAndAdvance(int pIdx, int sIdx) {
      if (pIdx < 0 || pIdx >= node.checklist.length) return;
      final parentTask = node.checklist[pIdx];
      if (sIdx < 0 || sIdx >= parentTask.children.length) return;
      final wasDone = node.isCompleted;
      parentTask.children[sIdx].completed = true;
      parentTask.completed =
          parentTask.children.isNotEmpty && parentTask.children.every((c) => c.completed);
      final nowDone = node.isCompleted;
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
      setState(() {
        if (nextIncompleteStepIdx != -1) {
          _selectedTaskIndexByCheckpoint[node.id] = pIdx;
          _selectedSubStepIndexByTask['${node.id}_$pIdx'] =
              nextIncompleteStepIdx;
        } else {
          // Current task is 100% done! Advance to the next incomplete task if available
          final nextTaskIdx = node.checklist.indexWhere((t) => !t.completed);
          if (nextTaskIdx != -1) {
            _selectedTaskIndexByCheckpoint[node.id] = nextTaskIdx;
            _selectedSubStepIndexByTask['${node.id}_$nextTaskIdx'] = 0;
          } else if (sIdx + 1 < parentTask.children.length) {
            _selectedSubStepIndexByTask['${node.id}_$pIdx'] = sIdx + 1;
          }
        }
        if (!wasDone && nowDone) {
          _awaitingPlaytestVerification.add(node.id);
        } else if (!nowDone) {
          _awaitingPlaytestVerification.remove(node.id);
        }
      });
      widget.workbench.updateFeatureStates(feat.id, states);
    }

    void quickVerifyEntireCheckpoint() {
      for (final task in node.checklist) {
        task.completed = true;
        for (final child in task.children) {
          child.completed = true;
        }
      }
      setState(() {
        _awaitingPlaytestVerification.remove(node.id);
        _expandedDoneCheckpoints.remove(node.id);
      });
      widget.workbench.updateFeatureStates(feat.id, states);
    }

    final cpCodeLabel = 'CP ${(index + 1).toString().padLeft(2, '0')}';

    // Determine "Next:" label for the bottom of the Left Instruction Pane
    String nextUpLabel = 'Checkpoint Playtest Verification';
    if (selectedHowTo != null) {
      if (activeSubStepIdx + 1 < selectedHowTo.subSteps.length) {
        final nextSub = selectedHowTo.subSteps[activeSubStepIdx + 1];
        nextUpLabel =
            '${selectedTaskIdx + 1}.${activeSubStepIdx + 2} ${nextSub.shortTitle}';
      } else if (selectedTaskIdx + 1 < howToBlueprints.length) {
        final nextTaskBp = howToBlueprints[selectedTaskIdx + 1];
        nextUpLabel = 'Task ${nextTaskBp.numLabel}: ${nextTaskBp.cleanTitle}';
      }
    }

    final pitfallOrGuardText = edgeItems.isNotEmpty
        ? edgeItems.first
        : (tuningItems.isNotEmpty
            ? 'Tuning Target: ${tuningItems.join(' · ')}'
            : 'Verify the parent class and component hierarchy match the spec before wiring logic in the next step.');

    final pinnedActiveStepWindow = (selectedParentTask != null &&
            selectedHowTo != null &&
            activeSubStep != null)
        ? Container(
            key: ValueKey('pinned_active_step_window_${node.id}'),
            color: _bgSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Option B: Full-Width Top Header Bar (.opt2-top) ──
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: _bgBase,
                    border: Border(bottom: BorderSide(color: _borderSubtle)),
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
                                    color: _textSecondary,
                                  ),
                                  children: [
                                    TextSpan(
                                      text:
                                          '${feat.title}  /  $cpCodeLabel: ${node.cleanStageTitle}  /  ',
                                    ),
                                    TextSpan(
                                      text:
                                          'Task ${selectedHowTo.numLabel}: ${selectedHowTo.cleanTitle}',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: _textPrimary,
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
                                color: _textSecondary,
                                height: 1.4,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Checkpoint Goal: ',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimary,
                                  ),
                                ),
                                TextSpan(text: node.playtestCondition),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Right-aligned Action Controls in Top Bar
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
                                color: _bgRecessed,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _borderBright),
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
                                            ? _focalAccent
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
                                              ? _focalAccentFg
                                              : _textSecondary,
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
                                            ? _focalAccent
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
                                              ? _focalAccentFg
                                              : _textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          InkWell(
                            key: ValueKey('toggle_explain_step_btn_${node.id}'),
                            onTap: () {
                              setState(() {
                                _explainStepOpen = !_explainStepOpen;
                              });
                            },
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _explainStepOpen
                                    ? _bgHover
                                    : _bgSurface,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: _explainStepOpen
                                      ? _textPrimary
                                      : _borderSubtle,
                                ),
                              ),
                              child: Text(
                                '? Explain',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _explainStepOpen
                                      ? _textPrimary
                                      : _textSecondary,
                                ),
                              ),
                            ),
                          ),
                          InkWell(
                            key: ValueKey(
                              'copy_howto_code_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                            ),
                            onTap: () => copySubStepCodeFormula(
                              selectedTaskIdx,
                              activeSubStepIdx,
                              activeSubStep.codeFormula,
                            ),
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _bgSurface,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: _borderSubtle),
                              ),
                              child: Text(
                                'Copy',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _textSecondary,
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
                                onTap: () => copySubStepCodeFormula(
                                  selectedTaskIdx,
                                  1,
                                  selectedHowTo.subSteps.length > 1
                                      ? selectedHowTo.subSteps[1].codeFormula
                                      : activeSubStep.codeFormula,
                                ),
                                child: const SizedBox.shrink(),
                              ),
                            ),
                          InkWell(
                            key: ValueKey(
                              'edit_howto_substep_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                            ),
                            onTap: () => promptEditHowToSubStepDialog(
                              selectedTaskIdx,
                              activeSubStepIdx,
                            ),
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _bgSurface,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: _borderSubtle),
                              ),
                              child: Text(
                                'Edit',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                          ),
                          Offstage(
                            offstage: _isSinglePanelMode,
                            child: InkWell(
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
                                  border: Border.all(color: _borderSubtle),
                                ),
                                child: Text(
                                  '✦ Tailor',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _textSecondary,
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

                // ── Option B: Full-Canvas 2-Pane Split (.opt2-split) ──
                LayoutBuilder(
                  builder: (context, splitConstraints) {
                    final useTwoCol = splitConstraints.maxWidth >= 680;
                    final totalSubSteps = selectedHowTo.subSteps.length;

                    // Left Full-Height Instruction Pane (.opt2-left)
                    final leftPane = Container(
                      padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                      decoration: BoxDecoration(
                        color: _bgSurface,
                        border: useTwoCol
                            ? Border(right: BorderSide(color: _borderSubtle))
                            : Border(bottom: BorderSide(color: _borderSubtle)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // STEP X.Y OF X.Z Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentEmerald,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'STEP ${selectedTaskIdx + 1}.${activeSubStepIdx + 1} OF ${selectedTaskIdx + 1}.$totalSubSteps',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF052E16),
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
                                  color: _textPrimary,
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Clear 15.5px Instruction Paragraph
                              Text(
                                activeSubStep.instruction,
                                style: GoogleFonts.inter(
                                  fontSize: 15.5,
                                  height: 1.7,
                                  color: _textPrimary,
                                ),
                              ),
                              const SizedBox(height: 22),
                              // ✓ WHAT YOU SHOULD SEE Callout Box
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentEmerald.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _accentEmerald.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '✓ WHAT YOU SHOULD SEE',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                        color: _accentEmerald,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      activeSubStep.verifyResult,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        height: 1.5,
                                        color: const Color(0xFFD1FAE5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (activeSubStep.explainConcept.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                // 💡 WHY THIS MATTERS Card
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _bgBase,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _explainStepOpen
                                          ? _borderBright
                                          : _borderSubtle,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '💡 WHY THIS MATTERS',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                          color: _textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        activeSubStep.explainConcept,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          height: 1.55,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 28),
                          // Bottom Action Bar inside Left Pane (Next: 1.2 ... + CTA Button)
                          Container(
                            padding: const EdgeInsets.only(top: 18),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: _borderSubtle),
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
                                      color: _textSecondary,
                                    ),
                                    children: [
                                      const TextSpan(text: 'Next: '),
                                      TextSpan(
                                        text: nextUpLabel,
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: _textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  key: ValueKey(
                                    'mark_active_step_done_btn_${node.id}',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _focalAccent,
                                    foregroundColor: _focalAccentFg,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                  ),
                                  onPressed: () => markActiveStepDoneAndAdvance(
                                    selectedTaskIdx,
                                    activeSubStepIdx,
                                  ),
                                  child: Text(
                                    activeSubStep.subtask.completed
                                        ? '✓ Completed — Next Step →'
                                        : '✓ Mark Step ${selectedTaskIdx + 1}.${activeSubStepIdx + 1} Done & Next →',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );

                    // Right Full-Height Code / Blueprint Reference Pane (.opt2-right)
                    final rightPane = Container(
                      color: _bgRecessed,
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
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _bgBase,
                                  border: Border(
                                    bottom: BorderSide(color: _borderSubtle),
                                  ),
                                ),
                                child: Text(
                                  '📍 ${activeSubStep.stepPath.isNotEmpty ? activeSubStep.stepPath : selectedHowTo.whereLocation}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: _textSecondary,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  activeSubStep.codeFormula,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13,
                                    height: 1.65,
                                    color: const Color(0xFFD1D5DB),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Bottom Pitfall / Guard Footer Bar
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: _bgBase,
                              border: Border(
                                top: BorderSide(color: _borderSubtle),
                              ),
                            ),
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: _textSecondary,
                                ),
                                children: [
                                  TextSpan(
                                    text: '⚠️ Common Pitfall: ',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimary,
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
                        constraints: const BoxConstraints(minHeight: 540),
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

                // Keep Step Pills & Tuning/Guard Pills Offstage in Single-Panel Mode (Visible in Split Studio Mode)
                Offstage(
                  offstage: _isSinglePanelMode,
                  child: Container(
                    margin: const EdgeInsets.only(top: 18),
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: _borderSubtle)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (int subIdx = 0;
                                    subIdx < selectedHowTo.subSteps.length;
                                    subIdx++)
                                  Builder(
                                    builder: (context) {
                                      final subStep =
                                          selectedHowTo.subSteps[subIdx];
                                      final subDone = subStep.subtask.completed;
                                      final isCurrentSub =
                                          subIdx == activeSubStepIdx;
                                      return InkWell(
                                        key: ValueKey(
                                          'howto_substep_${node.id}_${selectedTaskIdx}_$subIdx',
                                        ),
                                        onTap: () {
                                          if (isCurrentSub) {
                                            toggleHowToSubStepCompletion(
                                              selectedTaskIdx,
                                              subIdx,
                                            );
                                          } else {
                                            setState(() {
                                              _selectedSubStepIndexByTask[
                                                  selectedTaskKey] = subIdx;
                                              _explainStepOpen = false;
                                            });
                                          }
                                        },
                                        child: Text(
                                          '${selectedTaskIdx + 1}.${subIdx + 1}${subDone ? "✓" : ""}',
                                        ),
                                      );
                                    },
                                  ),
                                InkWell(
                                  key: ValueKey('add_howto_substep_btn_$index'),
                                  onTap: () =>
                                      addCustomHowToSubStep(selectedTaskIdx),
                                  child: const Text('+ Step'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (int tuneIdx = 0;
                                    tuneIdx < tuningItems.length;
                                    tuneIdx++)
                                  InkWell(
                                    key: ValueKey(
                                      'tuning_pill_${index}_$tuneIdx',
                                    ),
                                    onTap: () => promptTuningDialog(
                                      editIdx: tuneIdx,
                                      currentVal: tuningItems[tuneIdx],
                                    ),
                                    child: Text(tuningItems[tuneIdx]),
                                  ),
                                InkWell(
                                  key: ValueKey('add_tuning_btn_$index'),
                                  onTap: () => promptTuningDialog(),
                                  child: const Text('+ Tune'),
                                ),
                                for (int edgeIdx = 0;
                                    edgeIdx < edgeItems.length;
                                    edgeIdx++)
                                  InkWell(
                                    key: ValueKey(
                                      'edge_pill_${index}_$edgeIdx',
                                    ),
                                    onTap: () => promptEdgeCaseDialog(
                                      editIdx: edgeIdx,
                                      currentVal: edgeItems[edgeIdx],
                                    ),
                                    child: Text(edgeItems[edgeIdx]),
                                  ),
                                InkWell(
                                  key: ValueKey('add_edge_guard_btn_$index'),
                                  onTap: () => promptEdgeCaseDialog(),
                                  child: const Text('+ Edge Guard'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
        : const SizedBox.shrink();

    final selectedTaskHowToSection = (selectedParentTask != null &&
            selectedHowTo != null)
        ? Column(
            key: _isSinglePanelMode ? ValueKey('checkpoint_spec_pane_$index') : null,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pinned Active Step Window at the Top of the Task Work Area (NO duplicate 6-row table underneath!)
              pinnedActiveStepWindow,
            ],
          )
        : const SizedBox.shrink();

    final playtestGateFooter = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scopedItems.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '↳ Scope: ${scopedItems.join(' · ')}',
            style: GoogleFonts.inter(fontSize: 10.5, color: _textSecondary),
          ),
        ],
        const SizedBox(height: 6),
        // Bottom Checkpoint Playtest Gate Bar (Stage 2 3px Left Accent Callout Style)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _bgRecessed,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDone
                  ? _accentEmerald.withValues(alpha: 0.45)
                  : _borderSubtle,
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: isDone ? _accentEmerald : _accentAmber,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        key: ValueKey('edit_playtest_btn_$index'),
                        onTap: promptPlaytestDialog,
                        borderRadius: BorderRadius.circular(5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: _bgSurface,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: _borderSubtle),
                              ),
                              child: Text(
                                'PLAYTEST GATE ✎',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDone ? _accentEmerald : _accentAmber,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                node.playtestCondition,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          InkWell(
                            key: ValueKey('simulate_playtest_btn_$index'),
                            onTap: () {
                              final sim = widget.workbench.simulateCheckpointPlaytest(
                                featureDoc: feat,
                                states: states,
                                checkpointIndex: index,
                              );
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: _bgSurface,
                                  behavior: SnackBarBehavior.floating,
                                  content: Text(
                                    '⚡ Simulated: ${sim.recommendedTuningClamp} + [SIMULATION GUARD] added ✓',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _accentAmber,
                                    ),
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _bgSurface,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: _borderSubtle),
                              ),
                              child: Text(
                                '⚡ Simulate',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: _accentAmber,
                                ),
                              ),
                            ),
                          ),
                          InkWell(
                            key: ValueKey('log_playtest_issue_btn_$index'),
                            onTap: promptLogPlaytestIssueDialog,
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _bgSurface,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: _borderSubtle),
                              ),
                              child: Text(
                                '⚑ Log Issue',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: _accentCrimson,
                                ),
                              ),
                            ),
                          ),
                          if (!isDone)
                            InkWell(
                              key: ValueKey('quick_verify_checkpoint_btn_$index'),
                              onTap: quickVerifyEntireCheckpoint,
                              borderRadius: BorderRadius.circular(5),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentEmerald.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: _accentEmerald.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Text(
                                  '✓ Verify Checkpoint →',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: _accentEmerald,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (isAwaitingPlaytest) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            key: ValueKey('verify_playtest_btn_$index'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentEmerald,
                              foregroundColor: _focalAccentFg,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _awaitingPlaytestVerification.remove(node.id);
                                _expandedDoneCheckpoints.remove(node.id);
                              });
                            },
                            icon: const Icon(Icons.verified_rounded, size: 15),
                            label: Text(
                              'Verify Playtest & Advance →',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final checklistPane = Padding(
      padding: _isSinglePanelMode
          ? EdgeInsets.zero
          : const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isSinglePanelMode) ...[
            // Always show ONLY the Pinned Active Step Window in the work area (matching the mockup 1:1!)
            Container(
              key: ValueKey('checkpoint_spec_pane_$index'),
              child: pinnedActiveStepWindow,
            ),
          ] else ...[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  'CHECKPOINT TASKS (${node.completedChecklistCount}/${node.totalChecklistCount})',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: _textSecondary,
                  ),
                ),
                Text(
                  'Select task for How-To →',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Offstage(
            offstage: _isSinglePanelMode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int tIdx = 0; tIdx < node.checklist.length; tIdx++)
                  Builder(
                    builder: (context) {
                      final task = node.checklist[tIdx];
                      final bp = howToBlueprints[tIdx];
                      final isSelectedTask = tIdx == selectedTaskIdx;
                      final taskKey = '${node.id}_$tIdx';
                      final subDoneCount = task.completedChildrenCount;
                      final subTotalCount = task.totalChildrenCount;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelectedTask ? _bgHover : _bgRecessed,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: task.completed
                                ? _accentEmerald.withValues(alpha: 0.45)
                                : (isSelectedTask
                                    ? _borderBright
                                    : _borderSubtle),
                            width: isSelectedTask ? 1.2 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              key: ValueKey('task_checkbox_${node.id}_$tIdx'),
                              onTap: () => toggleParentTaskCompletion(tIdx),
                              borderRadius: BorderRadius.circular(5),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(10, 9, 8, 9),
                                child: Icon(
                                  task.completed
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 16,
                                  color: task.completed
                                      ? _accentEmerald
                                      : (isSelectedTask
                                          ? _textPrimary
                                          : _textSecondary),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                key: ValueKey(
                                  'select_task_row_${node.id}_$tIdx',
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedTaskIndexByCheckpoint[node.id] =
                                        tIdx;
                                    _expandedHowToTaskKeys
                                      ..clear()
                                      ..add(taskKey);
                                    _explainStepOpen = false;
                                  });
                                },
                                borderRadius: BorderRadius.circular(5),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(2, 8, 8, 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelectedTask
                                              ? _focalAccent
                                              : _bgSurface,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border:
                                              Border.all(color: _borderSubtle),
                                        ),
                                        child: Text(
                                          bp.numLabel,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: isSelectedTask
                                                ? _focalAccentFg
                                                : _textSecondary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          task.text,
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: isSelectedTask
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: task.completed
                                                ? _textMuted
                                                : _textPrimary,
                                            decoration: task.completed
                                                ? TextDecoration.lineThrough
                                                : TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: task.completed
                                              ? _accentEmerald.withValues(
                                                  alpha: 0.14,
                                                )
                                              : _bgSurface,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border:
                                              Border.all(color: _borderSubtle),
                                        ),
                                        child: Text(
                                          '$subDoneCount/$subTotalCount steps',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: task.completed
                                                ? _accentEmerald
                                                : (isSelectedTask
                                                    ? _textPrimary
                                                    : _textSecondary),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (node.checklist.length > 1)
                              InkWell(
                                key: ValueKey('delete_task_${node.id}_$tIdx'),
                                onTap: () {
                                  setState(() {
                                    node.checklist.removeAt(tIdx);
                                    if (!node.isCompleted) {
                                      _awaitingPlaytestVerification
                                          .remove(node.id);
                                    }
                                  });
                                  widget.workbench.updateFeatureStates(
                                    feat.id,
                                    states,
                                  );
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 13,
                                    color: _textMuted.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _bgRecessed,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, size: 14, color: _textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          key: ValueKey('add_checkpoint_task_input_$index'),
                          controller: taskCtrl,
                          onSubmitted: (_) => submitNewTask(),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _textPrimary,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 6),
                            hintText: 'Add task step...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: _textMuted,
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        key: ValueKey('add_checkpoint_task_btn_$index'),
                        onTap: submitNewTask,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Text(
                            'Add',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isSinglePanelMode) ...[
                  const SizedBox(height: 8),
                  playtestGateFooter,
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final specContextPane = Container(
      key: _isSinglePanelMode ? null : ValueKey('checkpoint_spec_pane_$index'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: _bgRecessed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          selectedTaskHowToSection,
          playtestGateFooter,
        ],
      ),
    );

    return Container(
      margin: EdgeInsets.only(bottom: _isSinglePanelMode ? 6 : 12),
      decoration: _isSinglePanelMode
          ? null
          : BoxDecoration(
              color: _bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActiveFocus ? _borderBright : _borderSubtle,
                width: isActiveFocus ? 1.4 : 1.0,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isSinglePanelMode || _showAllCheckpointsInFocus)
            Container(
              padding: _isSinglePanelMode
                  ? const EdgeInsets.only(top: 10, bottom: 6)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: _isSinglePanelMode
                  ? null
                  : BoxDecoration(
                      color: isActiveFocus ? _bgHover : _bgSurface,
                      borderRadius: isCollapsed
                          ? BorderRadius.circular(7)
                          : const BorderRadius.vertical(top: Radius.circular(7)),
                      border: Border(
                        bottom: isCollapsed
                            ? BorderSide.none
                            : BorderSide(color: _borderSubtle),
                      ),
                    ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _borderSubtle),
                    ),
                    child: Text(
                      'CHECKPOINT ${index + 1}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: _bgRecessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _borderSubtle),
                    ),
                    child: Text(
                      verStamp,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: _textMuted,
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
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  if (isAwaitingPlaytest)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _accentEmerald.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'READY FOR PLAYTEST',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: _accentEmerald,
                        ),
                      ),
                    )
                  else if (isDone)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _accentEmerald.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'VERIFIED ✓',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: _accentEmerald,
                        ),
                      ),
                    )
                  else if (isActiveFocus)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _accentAmber.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ACTIVE FOCUS · ${node.completedChecklistCount}/${node.totalChecklistCount}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: _accentAmber,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _bgRecessed,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'UP NEXT · ${node.completedChecklistCount}/${node.totalChecklistCount}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: _textMuted,
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
                      color: _textMuted,
                    ),
                  ),
                ],
              ),
            ),
          if (!isCollapsed)
            LayoutBuilder(
              builder: (context, constraints) {
                if (_isSinglePanelMode) {
                  return Container(
                    key: ValueKey('checkpoint_single_col_$index'),
                    child: checklistPane,
                  );
                }
                final isTwoCol = constraints.maxWidth >= 560;
                if (isTwoCol) {
                  return Row(
                    key: ValueKey('checkpoint_two_col_row_$index'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 42, child: checklistPane),
                      Container(width: 0.8, color: _borderSubtle),
                      Expanded(flex: 58, child: specContextPane),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    checklistPane,
                    specContextPane,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _promptAddCheckpointDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
  ) async {
    final titleCtrl = TextEditingController();
    final playtestCtrl = TextEditingController();
    final taskCtrl = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: _borderBright),
        ),
        title: Text(
          'Add Playable Checkpoint',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                style: GoogleFonts.inter(fontSize: 12.5, color: _textPrimary),
                decoration: InputDecoration(
                  labelText: 'Checkpoint Title (2–4 plain game-dev words)',
                  labelStyle: GoogleFonts.inter(fontSize: 11.5, color: _textSecondary),
                  hintText: 'e.g., Wall Slide & Corner Push',
                  hintStyle: GoogleFonts.inter(fontSize: 11.5, color: _textMuted),
                  filled: true,
                  fillColor: _bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: playtestCtrl,
                style: GoogleFonts.inter(fontSize: 12.5, color: _textPrimary),
                decoration: InputDecoration(
                  labelText: 'Playtest Criteria (Observable on screen)',
                  labelStyle: GoogleFonts.inter(fontSize: 11.5, color: _textSecondary),
                  hintText: 'e.g., Walk diagonally into a corner and verify smooth sliding.',
                  hintStyle: GoogleFonts.inter(fontSize: 11.5, color: _textMuted),
                  filled: true,
                  fillColor: _bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: taskCtrl,
                onSubmitted: (_) => Navigator.of(ctx).pop('save'),
                style: GoogleFonts.inter(fontSize: 12.5, color: _textPrimary),
                decoration: InputDecoration(
                  labelText: 'First Task Step',
                  labelStyle: GoogleFonts.inter(fontSize: 11.5, color: _textSecondary),
                  hintText: 'e.g., Add corner push nudge on collider contact',
                  hintStyle: GoogleFonts.inter(fontSize: 11.5, color: _textMuted),
                  filled: true,
                  fillColor: _bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _borderSubtle),
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
              style: GoogleFonts.inter(fontSize: 12, color: _textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _focalAccent,
              foregroundColor: _focalAccentFg,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: Text(
              'Add Checkpoint',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (!mounted || action != 'save') return;
    final rawTitle = titleCtrl.text.trim();
    final cpTitle = rawTitle.isEmpty
        ? 'Stage ${states.length + 1}: Polish & Tuning Pass'
        : (rawTitle.toLowerCase().startsWith('stage ')
            ? rawTitle
            : 'Stage ${states.length + 1}: $rawTitle');
    final cpPlaytest = playtestCtrl.text.trim().isEmpty
        ? 'Playtest ${feat.title} in the scene and verify responsive feel.'
        : playtestCtrl.text.trim();
    final firstTask = taskCtrl.text.trim().isEmpty
        ? 'Wire up and test ${rawTitle.isEmpty ? "checkpoint mechanics" : rawTitle}'
        : taskCtrl.text.trim();
    final activeVer = widget.workbench.activeRelease?.sections['versionTag'] ?? 'v0.1';
    final newCp = FeatureStateNode(
      id: generateUniqueId('cp'),
      name: cpTitle,
      trigger: cpPlaytest,
      parameters: {'releaseVersion': activeVer},
      checklist: [
        Subtask(
          id: generateUniqueId('check'),
          text: firstTask,
          completed: false,
        ),
      ],
    );
    setState(() {
      states.add(newCp);
      _expandedDoneCheckpoints.add(newCp.id);
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  Future<void> _copyFeatureAsMarkdown(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureSpecBindingResult specBinding,
  ) async {
    final scopeGoal = SectionTextUtils.resolveGoal(feat.sections);
    final doneIf = SectionTextUtils.resolveDoneWhen(feat.sections);
    final outOfScope = SectionTextUtils.resolveExclusions(
      feat.sections,
      splitSingleSentence: false,
    );
    final sb = StringBuffer();
    sb.writeln('# Feature: ${feat.title} (${feat.estimatedDuration})');
    sb.writeln('- **Goal**: $scopeGoal');
    sb.writeln('- **Done When**: $doneIf');
    if (outOfScope.isNotEmpty) {
      sb.writeln('- **Out of Scope**:');
      for (final cut in outOfScope) {
        sb.writeln('  - [CUT] $cut');
      }
    }
    sb.writeln('\n## Playable Checkpoints (${states.length})');
    for (int i = 0; i < states.length; i++) {
      final cp = states[i];
      final statusTag = cp.isCompleted ? 'VERIFIED ✓' : 'OPEN';
      sb.writeln(
        '\n### Checkpoint ${i + 1} (${cp.releaseVersion}): ${cp.cleanStageTitle} [$statusTag]',
      );
      sb.writeln('- **Playtest**: ${cp.playtestCondition}');
      final tunes = specBinding.checkpointTuning[cp.id] ?? cp.tuningParams;
      if (tunes.isNotEmpty) {
        sb.writeln('- **Tuning**: ${tunes.join(' · ')}');
      }
      final edges = specBinding.checkpointEdgeCases[cp.id] ?? cp.edgeCases;
      if (edges.isNotEmpty) {
        sb.writeln('- **Edge Guards**: ${edges.join(' · ')}');
      }
      sb.writeln('- **Tasks**:');
      for (int tIdx = 0; tIdx < cp.checklist.length; tIdx++) {
        final t = cp.checklist[tIdx];
        sb.writeln('  - [${t.completed ? "x" : " "}] ${t.text}');
        for (int sIdx = 0; sIdx < t.children.length; sIdx++) {
          final sub = t.children[sIdx];
          sb.writeln(
            '    - [${sub.completed ? "x" : " "}] **Step ${tIdx + 1}.${sIdx + 1} (${sub.text})**: ${sub.specNotes ?? ""}',
          );
          final snippet = sub.codeSnippet?.trim() ?? '';
          if (snippet.isNotEmpty) {
            sb.writeln('      `Formula`: `$snippet`');
          }
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Copied ${feat.title} Markdown spec to clipboard ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _applyFeatureCoPilotAction(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureSpecBindingResult specBinding,
    int activeFocusIndex,
    String actionOrPrompt,
  ) async {
    final targetIdx = (activeFocusIndex >= 0 && activeFocusIndex < states.length)
        ? activeFocusIndex
        : (states.isNotEmpty ? states.length - 1 : 0);

    final trace = await widget.workbench.runStage3AgentCoPilot(
      featureDoc: feat,
      states: states,
      activeCheckpointIndex: targetIdx,
      directive: actionOrPrompt,
    );

    if (states.isNotEmpty) {
      setState(() {
        for (final s in states) {
          _expandedDoneCheckpoints.add(s.id);
        }
      });
    }

    if (!mounted) return;
    final feedbackMsg = trace.toolCalls.isNotEmpty
        ? 'Agent (${trace.toolCalls.first.toolName}): ${trace.toolCalls.first.summary} ✓'
        : 'Updated ${feat.title} ✓';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          feedbackMsg,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildWorkbenchStickyBottomDock(
    TierDocument rel,
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureSpecBindingResult specBinding, {
    required int activeFocusIndex,
    required int completedCps,
  }) {
    final allFeats = <TierDocument>[
      for (final b in widget.workbench.activeReleaseBeats)
        ...widget.workbench.featuresForBeat(b.id),
    ];
    final currentFeatIdx = allFeats.indexWhere((f) => f.id == feat.id);
    final prevFeat = currentFeatIdx > 0 ? allFeats[currentFeatIdx - 1] : null;
    final nextFeat = (currentFeatIdx != -1 && currentFeatIdx < allFeats.length - 1)
        ? allFeats[currentFeatIdx + 1]
        : widget.workbench.nextIncompleteFeature;
    final isReleaseComplete = widget.workbench.isActiveReleaseComplete;

    Widget buildCoPilotCard({
      required Key key,
      required String badge,
      required Color badgeColor,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: _bgRecessed,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: _borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        badge,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    Text(
                      '1-Click ↗',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: AppTheme.displayFont(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    height: 1.3,
                    color: _textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    void submitCustomPrompt() {
      final raw = _copilotPromptController.text.trim();
      if (raw.isEmpty) return;
      _copilotPromptController.clear();
      _applyFeatureCoPilotAction(
        feat,
        states,
        specBinding,
        activeFocusIndex,
        raw,
      );
    }

    return Container(
      key: const ValueKey('workbench_sticky_bottom_dock'),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: BoxDecoration(
        color: _bgSurface,
        border: Border(top: BorderSide(color: _borderBright)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.workbench.lastAgentTrace != null &&
                  widget.workbench.lastAgentTrace!.toolCalls.isNotEmpty) ...[
                Container(
                  key: const ValueKey('stage3_agent_trace_banner'),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: _bgRecessed,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _accentEmerald.withValues(alpha: 0.42),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: _accentEmerald.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'AGENT TRACE · ${widget.workbench.lastAgentTrace!.toolCalls.first.toolName}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: _accentEmerald,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.workbench.lastAgentTrace!.toolCalls.map((c) => c.summary).join(" · ")} — ${widget.workbench.lastAgentTrace!.reasoning}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        key: const ValueKey('dismiss_stage3_trace_btn'),
                        onTap: () => widget.workbench.clearLastAgentTrace(),
                        child: Text(
                          '×',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              for (final intervention in widget.workbench
                  .stage3InterventionsForFeature(feat, states, activeFocusIndex)
                  .take(1)) ...[
                Container(
                  key: const ValueKey('stage3_intervention_banner'),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: _bgRecessed,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _accentAmber.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: _accentAmber.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          intervention.badge,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: _accentAmber,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${intervention.title} — ${intervention.reason}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        key: const ValueKey('stage3_apply_intervention_btn'),
                        onTap: () => widget.workbench.applyAgentIntervention(
                          intervention,
                          stage3States: states,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _accentAmber.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _accentAmber.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            intervention.actionLabel,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: _accentAmber,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              // Collapsible 3 Side-by-Side Co-Pilot Playing Cards Drawer (or Slim 1-Line Quick Pills when collapsed)
              if (_showCoPilotDrawer) ...[
                Row(
                  children: [
                    buildCoPilotCard(
                      key: const ValueKey('copilot_card_add_checkpoint'),
                      badge: 'CO-PILOT 01 · CHECKPOINT',
                      badgeColor: _textSecondary,
                      title: '+ Add Polish Checkpoint',
                      subtitle: 'Append a 60/40 playtest checkpoint with tasks & tuning.',
                      onTap: () => _applyFeatureCoPilotAction(
                        feat,
                        states,
                        specBinding,
                        activeFocusIndex,
                        'add_polish_checkpoint',
                      ),
                    ),
                    const SizedBox(width: 8),
                    buildCoPilotCard(
                      key: const ValueKey('copilot_card_suggest_tuning'),
                      badge: 'CO-PILOT 02 · TUNING',
                      badgeColor: _textSecondary,
                      title: 'Suggest Tuning Values',
                      subtitle: 'Generate concrete numeric parameters for the active checkpoint.',
                      onTap: () => _applyFeatureCoPilotAction(
                        feat,
                        states,
                        specBinding,
                        activeFocusIndex,
                        'suggest_tuning',
                      ),
                    ),
                    const SizedBox(width: 8),
                    buildCoPilotCard(
                      key: const ValueKey('copilot_card_add_guards'),
                      badge: 'CO-PILOT 03 · EDGE GUARDS',
                      badgeColor: _textSecondary,
                      title: 'Add Edge-Case Guards',
                      subtitle: 'Append [GUARD] boundary conditions to prevent state bugs.',
                      onTap: () => _applyFeatureCoPilotAction(
                        feat,
                        states,
                        specBinding,
                        activeFocusIndex,
                        'add_edge_guards',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              // Row 2: [ASK AGENT] Feature Co-Pilot Input Bar + Co-Pilot Drawer Toggle + Compact Quick Pills
              Row(
                children: [
                  InkWell(
                    key: const ValueKey('toggle_copilot_drawer_btn'),
                    onTap: () {
                      setState(() {
                        _showCoPilotDrawer = !_showCoPilotDrawer;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _showCoPilotDrawer
                            ? _bgHover
                            : _bgRecessed,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _showCoPilotDrawer
                              ? _borderBright
                              : _borderSubtle,
                        ),
                      ),
                      child: Text(
                        '✦ Co-Pilot Cards (3) ${_showCoPilotDrawer ? "▾" : "▴"}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _showCoPilotDrawer ? _textPrimary : _textSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (!_showCoPilotDrawer) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _applyFeatureCoPilotAction(
                        feat,
                        states,
                        specBinding,
                        activeFocusIndex,
                        'add_polish_checkpoint',
                      ),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: _borderSubtle,
                          ),
                        ),
                        child: Text(
                          '+ Polish CP',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    InkWell(
                      onTap: () => _applyFeatureCoPilotAction(
                        feat,
                        states,
                        specBinding,
                        activeFocusIndex,
                        'suggest_tuning',
                      ),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: _borderSubtle,
                          ),
                        ),
                        child: Text(
                          '⚡ Tune',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    InkWell(
                      onTap: () => _applyFeatureCoPilotAction(
                        feat,
                        states,
                        specBinding,
                        activeFocusIndex,
                        'add_edge_guards',
                      ),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _bgRecessed,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: _borderSubtle,
                          ),
                        ),
                        child: Text(
                          '+ Guards',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: _bgRecessed,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _bgSurface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _borderSubtle),
                            ),
                            child: Text(
                              'ASK AGENT',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: _textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('workbench_copilot_input'),
                              controller: _copilotPromptController,
                              onSubmitted: (_) => submitCustomPrompt(),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: _textPrimary,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                hintText:
                                    'Ask Agent to add a task, checkpoint, tuning value, or edge guard for ${feat.title}...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: _textMuted,
                                ),
                              ),
                            ),
                          ),
                          InkWell(
                            key: const ValueKey('workbench_copilot_send_btn'),
                            onTap: submitCustomPrompt,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Icon(
                                Icons.send_rounded,
                                size: 15,
                                color: _textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Row 3: Feature Navigation & Copy Markdown Spec Bar
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('dock_prev_feature_btn'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textSecondary,
                          side: BorderSide(color: _borderSubtle),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: prevFeat == null
                            ? null
                            : () => widget.workbench.selectFeature(prevFeat.id),
                        child: Text(
                          '← Prev Feature',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('copy_feature_markdown_btn'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textPrimary,
                          side: BorderSide(color: _borderSubtle),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: () => _copyFeatureAsMarkdown(feat, states, specBinding),
                        icon: Icon(Icons.copy_rounded, size: 13, color: _textSecondary),
                        label: Text(
                          'Copy Feature Markdown',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (currentFeatIdx != -1)
                        Text(
                          'Feature ${currentFeatIdx + 1}/${allFeats.length} · $completedCps/${states.length} Checkpoints',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            color: _textMuted,
                          ),
                        ),
                      if (isReleaseComplete)
                        ElevatedButton.icon(
                          key: const ValueKey('dock_ship_release_btn'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _focalAccent,
                            foregroundColor: _focalAccentFg,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: () => widget.workbench.advanceToNextRelease(),
                          icon: const Icon(Icons.rocket_launch_rounded, size: 14),
                          label: Text(
                            'Ship & Plan Next Release ✦',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      else if (nextFeat != null && nextFeat.id != feat.id)
                        ElevatedButton(
                          key: const ValueKey('dock_next_feature_btn'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _focalAccent,
                            foregroundColor: _focalAccentFg,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: () => widget.workbench.selectFeature(nextFeat.id),
                          child: Text(
                            'Next Feature →',
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
            ],
          ),
        ),
      ),
    );
  }
}
