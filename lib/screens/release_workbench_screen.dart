import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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
  bool _hideUnassignedSpecShelf = false;
  bool _showCoPilotDrawer = true;
  bool _showPillarsReferenceDrawer = false;
  final Map<String, int> _selectedTaskIndexByCheckpoint = {};

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
                width: 288,
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

  Widget _buildLeftBeatFeatureRail(TierDocument rel, {bool shrinkWrap = false}) {
    final beats = widget.workbench.activeReleaseBeats;
    final relProgress = widget.workbench.getDocumentProgress(rel.id);
    final releases = widget.workbench.projectReleases;
    final archivedFeats = widget.workbench.supersededFeatures;
    final isFocus = widget.workbench.focusMode;
    final activeVer = rel.sections['versionTag'] ?? 'v0.1';

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _bgRecessed,
            border: Border(bottom: BorderSide(color: _borderSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    'ACTIVE RELEASE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: _accentAmber,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        key: const ValueKey('focus_mode_toggle_btn'),
                        onTap: () => widget.workbench.toggleFocusMode(),
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isFocus
                                ? _accentAmber.withValues(alpha: 0.14)
                                : _bgSurface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: isFocus
                                  ? _accentAmber.withValues(alpha: 0.45)
                                  : _borderSubtle,
                            ),
                          ),
                          child: Text(
                            'Focus: ${isFocus ? "ON" : "OFF"}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: isFocus ? _accentAmber : _textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$relProgress%',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: relProgress >= 100
                              ? _accentEmerald
                              : _accentAmber,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Compact Release Selector Dropdown (scales past v1.0+)
              PopupMenuButton<String>(
                key: const ValueKey('release_selector_dropdown_btn'),
                color: _bgSurface,
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
                          fontWeight: r.id == rel.id ? FontWeight.w700 : FontWeight.w500,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: '__replan__',
                    child: Text(
                      '✎ Edit ${rel.title} Scope in Plan Gate',
                      style: GoogleFonts.inter(fontSize: 12, color: _accentAmber),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: _bgSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          rel.title,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: _textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Visual Release Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  height: 3.5,
                  width: double.infinity,
                  color: _borderSubtle,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (relProgress / 100.0).clamp(0.0, 1.0),
                    child: Container(
                      color: relProgress >= 100
                          ? _accentEmerald
                          : _accentAmber,
                    ),
                  ),
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
                final beatFeats = widget.workbench.featuresForBeat(beats[bIdx].id);
                final doneBeatCount = beatFeats
                    .where((f) => widget.workbench.getDocumentProgress(f.id) >= 100)
                    .length;
                final allBeatDone = beatFeats.isNotEmpty && doneBeatCount == beatFeats.length;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 5),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: _accentEmerald.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _accentEmerald.withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          'BEAT·${(bIdx + 1).toString().padLeft(2, '0')}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: _accentEmerald,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          beats[bIdx].title.toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: _textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (beatFeats.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          allBeatDone
                              ? '$doneBeatCount/${beatFeats.length} ✓'
                              : '$doneBeatCount/${beatFeats.length}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: allBeatDone ? _accentEmerald : _textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            for (final feat in widget.workbench.featuresForBeat(beats[bIdx].id))
              _buildFeatureRailItem(feat, activeVer: activeVer),
          ],
      ],
    );

    if (shrinkWrap) {
      return Container(
        decoration: BoxDecoration(
          color: _bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _borderSubtle),
        ),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _bgSurface,
        border: Border(right: BorderSide(color: _borderSubtle)),
      ),
      child: SingleChildScrollView(child: content),
    );
  }

  Widget _buildFeatureRailItem(TierDocument feat, {required String activeVer}) {
    final isSelected = widget.workbench.selectedFeatureId == feat.id;
    final progress = widget.workbench.getDocumentProgress(feat.id);
    final isDone = progress >= 100;
    final isFocus = widget.workbench.focusMode;
    final lifecycle = feat.sections['lifecycle'] ?? '';
    final originVer = feat.sections['originVersion'] ?? 'v0.1';

    String? vBadge;
    Color vColor = _textMuted;
    if (lifecycle == 'stable') {
      vBadge = '$originVer ✓';
      vColor = _accentEmerald;
    } else if (lifecycle == 'upgrade') {
      vBadge = '$originVer→$activeVer';
      vColor = _accentAmber;
    } else if (lifecycle == 'superseded') {
      vBadge = 'ARCHIVED';
      vColor = _textMuted;
    } else if (activeVer != 'v0.1') {
      vBadge = 'NEW $activeVer';
      vColor = _accentEmerald;
    }

    final shouldDim = isFocus && !isSelected;

    return Opacity(
      opacity: shouldDim ? 0.55 : 1.0,
      child: InkWell(
        key: ValueKey('rail_feat_${feat.id}'),
        onTap: () => widget.workbench.selectFeature(feat.id),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? _bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? _borderBright
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14,
                color: isDone
                    ? _accentEmerald
                    : (isSelected ? _accentAmber : _textMuted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  feat.title,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: _textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (vBadge != null) ...[
                Container(
                  margin: const EdgeInsets.only(right: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: vColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    vBadge,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: vColor,
                    ),
                  ),
                ),
              ],
              Text(
                '$progress%',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDone ? _accentEmerald : _textMuted,
                ),
              ),
            ],
          ),
        ),
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

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.workbench.isActiveReleaseComplete) ...[
          _buildReleaseShippedBanner(rel),
          const SizedBox(height: 16),
        ] else if (isDone && nextFeat != null) ...[
          _buildNextFeatureAdvanceBanner(feat, nextFeat),
          const SizedBox(height: 16),
        ],
        _buildUltraCompactFeatureHeader(
          feat,
          states: states,
          specBinding: specBinding,
          statsLabel: '$completedCps/${states.length} cp · $completedTasks/$totalTasks tasks · ${feat.estimatedDuration}',
          progress: progress,
          isDone: isDone,
          presetLabel: rel.releaseScope.label,
        ),
        if (_showPillarsReferenceDrawer) ...[
          const SizedBox(height: 10),
          _buildStage1PillarsReferenceDrawer(),
        ],
        const SizedBox(height: 20),
        // De-boxed Stage 1 style section header for Playable Checkpoints
        Container(
          padding: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: _borderSubtle)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '01',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PLAYABLE CHECKPOINTS (${states.length})',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.workbench.focusMode && activeFocusIndex != -1) ...[
                    Text(
                      '🎯 Focus Mode: Expanding Active Checkpoint ${activeFocusIndex + 1} of ${states.length}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _accentAmber,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
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
                          color: _accentAmber,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < states.length; i++)
          _buildCheckpointCard(
            feat,
            states,
            i,
            activeFocusIndex: activeFocusIndex,
            specBinding: specBinding,
          ),
      ],
    );

    final bottomDock = _buildWorkbenchStickyBottomDock(
      rel,
      feat,
      states,
      specBinding,
      activeFocusIndex: activeFocusIndex,
      completedCps: completedCps,
    );

    if (shrinkWrap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          const SizedBox(height: 16),
          bottomDock,
        ],
      );
    }

    return Container(
      color: _bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
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

  void _showReleaseShippedSummaryModal(BuildContext context, TierDocument rel) {
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
        border: Border.all(color: _accentAmber.withValues(alpha: 0.45)),
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
                  color: _accentAmber,
                ),
              ),
              InkWell(
                onTap: () => widget.workbench.setStage(WorkbenchStage.projectPitch),
                child: Text(
                  'Edit in Stage 1 ↗',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: _accentEmerald,
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
                  badgeColor: _accentAmber,
                  items: pillars,
                  emptyHint: 'No Design Pillars defined yet.',
                ),
                const SizedBox(width: 8),
                buildColumn(
                  badge: '05 · TRADE-OFFS (X OVER Y)',
                  badgeColor: _accentEmerald,
                  items: tradeOffs,
                  emptyHint: 'No Trade-Off rules defined yet.',
                ),
                const SizedBox(width: 8),
                buildColumn(
                  badge: '02–03 · GAME & TECH SPEC',
                  badgeColor: AppTheme.accentCyanFor(_isDark),
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
    final allFeats = <TierDocument>[
      for (final b in widget.workbench.activeReleaseBeats)
        ...widget.workbench.featuresForBeat(b.id),
    ];
    final currentFeatIdx = allFeats.indexWhere((f) => f.id == feat.id);
    final prevFeat = currentFeatIdx > 0 ? allFeats[currentFeatIdx - 1] : null;
    final nextSequentialFeat =
        (currentFeatIdx != -1 && currentFeatIdx < allFeats.length - 1)
            ? allFeats[currentFeatIdx + 1]
            : null;

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

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tag('FEATURE', _accentAmber),
                        const SizedBox(width: 8),
                        Text(
                          feat.title,
                          style: AppTheme.displayFont(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.35,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        tag(presetLabel.toUpperCase(), _textSecondary),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        InkWell(
                          key: const ValueKey('toggle_pillars_drawer_btn'),
                          onTap: () {
                            setState(() {
                              _showPillarsReferenceDrawer = !_showPillarsReferenceDrawer;
                            });
                          },
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: _showPillarsReferenceDrawer
                                  ? _accentAmber.withValues(alpha: 0.14)
                                  : _bgRecessed,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: _showPillarsReferenceDrawer
                                    ? _accentAmber.withValues(alpha: 0.45)
                                    : _borderSubtle,
                              ),
                            ),
                            child: Text(
                              '◈ Pillars & Spec ${_showPillarsReferenceDrawer ? "▴" : "▾"}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _showPillarsReferenceDrawer
                                    ? _accentAmber
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
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _showOutOfScopeShelf
                                    ? _accentCrimson.withValues(alpha: 0.14)
                                    : _bgRecessed,
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
                                  fontSize: 10,
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
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _accentAmber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: _accentAmber.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                '${specBinding.totalUnassignedCount} unassigned',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _accentAmber,
                                ),
                              ),
                            ),
                          ),
                        if (allFeats.length > 1) ...[
                          InkWell(
                            key: const ValueKey('prev_feature_btn'),
                            onTap: prevFeat == null
                                ? null
                                : () => widget.workbench.selectFeature(prevFeat.id),
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _bgRecessed,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: _borderSubtle),
                              ),
                              child: Text(
                                '‹ Prev',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: prevFeat == null
                                      ? _textMuted.withValues(alpha: 0.45)
                                      : _textSecondary,
                                ),
                              ),
                            ),
                          ),
                          InkWell(
                            key: const ValueKey('next_feature_btn'),
                            onTap: nextSequentialFeat == null
                                ? null
                                : () => widget.workbench.selectFeature(nextSequentialFeat.id),
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _bgRecessed,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: _borderSubtle),
                              ),
                              child: Text(
                                'Next ›',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: nextSequentialFeat == null
                                      ? _textMuted.withValues(alpha: 0.45)
                                      : _textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tag('GOAL', _accentAmber, width: 68),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        scopeGoal,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.4,
                          color: _textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    tag('DONE WHEN', _accentEmerald, width: 68),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        doneIf,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _accentEmerald,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statsLabel,
                      style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: _textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_showOutOfScopeShelf && outOfScope.isNotEmpty)
            Container(
              key: const ValueKey('feat_out_of_scope_shelf'),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: _bgRecessed,
                border: Border(top: BorderSide(color: _borderSubtle)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isTwoCol = constraints.maxWidth >= 480 && outOfScope.length > 1;
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _bgSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _accentCrimson.withValues(alpha: 0.28),
                              ),
                            ),
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
                        ),
                    ],
                  );
                },
              ),
            ),
          if (specBinding.hasUnassigned && !_hideUnassignedSpecShelf)
            Container(
              key: const ValueKey('feat_inline_spec_shelf'),
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
              decoration: BoxDecoration(
                color: _bgRecessed,
                border: Border(top: BorderSide(color: _borderSubtle)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final sc in specBinding.unassignedScope)
                    Text('✓ $sc', style: GoogleFonts.inter(fontSize: 10.5, color: _textPrimary)),
                  for (final t in specBinding.unassignedTuning)
                    Text('⚙ $t', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _textPrimary)),
                  for (final e in specBinding.unassignedEdgeCases)
                    Text('⚠ $e', style: GoogleFonts.inter(fontSize: 10.5, color: _textPrimary)),
                ],
              ),
            ),
          Container(
            height: 2.5,
            color: _borderSubtle,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (progress / 100.0).clamp(0.0, 1.0),
              child: Container(
                color: isDone ? _accentEmerald : _accentAmber,
              ),
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
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
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
          content: TextField(
            controller: ctrl,
            autofocus: true,
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
    final howToBlueprints = <TaskHowToBlueprint>[
      for (int tIdx = 0; tIdx < node.checklist.length; tIdx++)
        TaskHowToBlueprint.resolve(
          parentTask: node.checklist[tIdx],
          taskIndex: tIdx,
          checkpointNode: node,
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

    Color layerBadgeColor(String layerTag) {
      switch (layerTag) {
        case 'INPUT':
          return AppTheme.accentCyanFor(_isDark);
        case 'PHYSICS':
          return _accentAmber;
        case 'FEEL':
        case 'UI / HUD':
          return _accentEmerald;
        default:
          return _textSecondary;
      }
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
      parentTask.children[sIdx].completed = !parentTask.children[sIdx].completed;
      parentTask.completed =
          parentTask.children.isNotEmpty && parentTask.children.every((c) => c.completed);
      final nowDone = node.isCompleted;
      setState(() {
        if (parentTask.completed) {
          final nextIncomplete = node.checklist.indexWhere((t) => !t.completed);
          if (nextIncomplete != -1) {
            _selectedTaskIndexByCheckpoint[node.id] = nextIncomplete;
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

    final checklistPane = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          for (int tIdx = 0; tIdx < node.checklist.length; tIdx++)
            Builder(
              builder: (context) {
                final task = node.checklist[tIdx];
                final bp = howToBlueprints[tIdx];
                final isSelectedTask = tIdx == selectedTaskIdx;
                final subDoneCount = task.completedChildrenCount;
                final subTotalCount = task.totalChildrenCount;
                final lColor = layerBadgeColor(bp.layerTag);

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelectedTask
                        ? _accentAmber.withValues(alpha: 0.08)
                        : _bgRecessed,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelectedTask
                          ? _accentAmber.withValues(alpha: 0.55)
                          : _borderSubtle,
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
                          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                          child: Icon(
                            task.completed
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 16,
                            color: task.completed ? _accentEmerald : _accentAmber,
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          key: ValueKey('select_task_row_${node.id}_$tIdx'),
                          onTap: () {
                            setState(() {
                              _selectedTaskIndexByCheckpoint[node.id] = tIdx;
                            });
                          },
                          borderRadius: BorderRadius.circular(5),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(2, 8, 8, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 5,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelectedTask
                                            ? _accentAmber
                                            : _bgSurface,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        bp.numLabel,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          color: isSelectedTask
                                              ? Colors.black
                                              : _textMuted,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: lColor.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        bp.layerTag,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          color: lColor,
                                        ),
                                      ),
                                    ),
                                    if (subTotalCount > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: task.completed
                                              ? _accentEmerald.withValues(alpha: 0.16)
                                              : _bgSurface,
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(color: _borderSubtle),
                                        ),
                                        child: Text(
                                          '$subDoneCount/$subTotalCount steps',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w700,
                                            color: task.completed
                                                ? _accentEmerald
                                                : (subDoneCount > 0
                                                    ? _accentAmber
                                                    : _textMuted),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      bp.durationChip,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w600,
                                        color: _textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  task.text,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
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
                                _awaitingPlaytestVerification.remove(node.id);
                              }
                            });
                            widget.workbench.updateFeatureStates(feat.id, states);
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      'Add',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _accentAmber,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final specContextPane = Container(
      key: ValueKey('checkpoint_spec_pane_$index'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: _bgRecessed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectedParentTask != null && selectedHowTo != null) ...[
            // Right Pane Header: Active Task + Sub-Steps Rollup + Script/Scene Location
            Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _borderSubtle)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _accentAmber.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _accentAmber.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          'TASK ${selectedHowTo.numLabel} · ${selectedParentTask.completedChildrenCount}/${selectedParentTask.totalChildrenCount} SUB-STEPS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: _accentAmber,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _bgSurface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _borderSubtle),
                        ),
                        child: Text(
                          '📍 ${selectedHowTo.whereLocation}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accentCyanFor(_isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    selectedHowTo.cleanTitle,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Checkable Step-by-Step How-To Sub-Steps (Step X.1, X.2, X.3)
            for (int subIdx = 0; subIdx < selectedHowTo.subSteps.length; subIdx++)
              Builder(
                builder: (context) {
                  final subStep = selectedHowTo.subSteps[subIdx];
                  final subDone = subStep.subtask.completed;
                  final isCoreStep = subIdx == 1;
                  final isGuardStep = subStep.isGuardStep;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 7),
                    decoration: BoxDecoration(
                      color: subDone
                          ? _accentEmerald.withValues(alpha: 0.05)
                          : _bgSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: subDone
                            ? _accentEmerald.withValues(alpha: 0.35)
                            : (isGuardStep
                                ? _accentCrimson.withValues(alpha: 0.28)
                                : _borderSubtle),
                      ),
                    ),
                    child: InkWell(
                      key: ValueKey(
                        'howto_substep_${node.id}_${selectedTaskIdx}_$subIdx',
                      ),
                      onTap: () =>
                          toggleHowToSubStepCompletion(selectedTaskIdx, subIdx),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                subDone
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 15,
                                color: subDone
                                    ? _accentEmerald
                                    : (isGuardStep ? _accentCrimson : _accentAmber),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    subStep.stepNumberLabel,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                      color: subDone
                                          ? _accentEmerald
                                          : (isGuardStep
                                              ? _accentCrimson
                                              : _accentAmber),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    subStep.instruction,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      height: 1.38,
                                      color: subDone ? _textMuted : _textPrimary,
                                      decoration: subDone
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _bgRecessed,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: _borderSubtle),
                                    ),
                                    child: Text(
                                      subStep.codeFormula,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10,
                                        height: 1.35,
                                        color: subDone
                                            ? _textMuted
                                            : AppTheme.accentCyanFor(_isDark),
                                      ),
                                    ),
                                  ),
                                  if (isCoreStep) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 4,
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
                                            borderRadius: BorderRadius.circular(4),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2.5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _accentAmber.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: _accentAmber.withValues(
                                                    alpha: 0.28,
                                                  ),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                '⚙ ${tuningItems[tuneIdx]} ✎',
                                                style: GoogleFonts.jetBrainsMono(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: _textPrimary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        InkWell(
                                          key: ValueKey('add_tuning_btn_$index'),
                                          onTap: () => promptTuningDialog(),
                                          borderRadius: BorderRadius.circular(4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _bgRecessed,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border:
                                                  Border.all(color: _borderSubtle),
                                            ),
                                            child: Text(
                                              '+ Tune',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: _accentAmber,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (isGuardStep) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
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
                                            borderRadius: BorderRadius.circular(4),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2.5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _accentCrimson.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: _accentCrimson.withValues(
                                                    alpha: 0.28,
                                                  ),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                '🛡 ${edgeItems[edgeIdx]} ✎',
                                                style: GoogleFonts.inter(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                  color: _textPrimary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        InkWell(
                                          key: ValueKey('add_edge_guard_btn_$index'),
                                          onTap: () => promptEdgeCaseDialog(),
                                          borderRadius: BorderRadius.circular(4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _bgRecessed,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border:
                                                  Border.all(color: _borderSubtle),
                                            ),
                                            child: Text(
                                              '+ Edge Guard',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: _accentCrimson,
                                              ),
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
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
          if (scopedItems.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '↳ Scope: ${scopedItems.join(' · ')}',
              style: GoogleFonts.inter(fontSize: 10.5, color: _textSecondary),
            ),
          ],
          const SizedBox(height: 6),
          // Bottom Checkpoint Playtest Gate Bar
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _bgSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDone
                    ? _accentEmerald.withValues(alpha: 0.45)
                    : _borderSubtle,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InkWell(
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
                                color: (isDone ? _accentEmerald : _accentAmber)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
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
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isDone) ...[
                      const SizedBox(width: 8),
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
                        foregroundColor: Colors.white,
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
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActiveFocus
              ? _borderBright
              : _borderSubtle,
          width: isActiveFocus ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isActiveFocus ? _bgHover : _bgSurface,
              borderRadius: isCollapsed
                  ? BorderRadius.circular(7)
                  : const BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(
                bottom: isCollapsed ? BorderSide.none : BorderSide(color: _borderSubtle),
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
                final isTwoCol = constraints.maxWidth >= 560;
                if (isTwoCol) {
                  return IntrinsicHeight(
                    child: Row(
                      key: ValueKey('checkpoint_two_col_row_$index'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 42, child: checklistPane),
                        Container(width: 0.8, color: _borderSubtle),
                        Expanded(flex: 58, child: specContextPane),
                      ],
                    ),
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
      for (final t in cp.checklist) {
        sb.writeln('  - [${t.completed ? "x" : " "}] ${t.text}');
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

  void _applyFeatureCoPilotAction(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureSpecBindingResult specBinding,
    int activeFocusIndex,
    String actionOrPrompt,
  ) {
    final targetIdx = (activeFocusIndex >= 0 && activeFocusIndex < states.length)
        ? activeFocusIndex
        : (states.isNotEmpty ? states.length - 1 : -1);
    final activeVer = widget.workbench.activeRelease?.sections['versionTag'] ?? 'v0.1';
    final lower = actionOrPrompt.trim().toLowerCase();

    String feedbackMsg = 'Updated ${feat.title}';

    if (actionOrPrompt == 'add_polish_checkpoint' ||
        lower.contains('checkpoint') ||
        lower.contains('stage')) {
      final customTitle = (actionOrPrompt != 'add_polish_checkpoint' &&
              actionOrPrompt.trim().isNotEmpty)
          ? actionOrPrompt.trim()
          : 'Screen Feedback & Feel Pass';
      final newCp = FeatureStateNode(
        id: generateUniqueId('cp'),
        name: 'Stage ${states.length + 1}: $customTitle',
        trigger:
            'Trigger ${feat.title} in the scene and verify immediate visual and audio feedback with zero frame hitches.',
        parameters: {'releaseVersion': activeVer},
        tuningParams: const [
          'hit_flash_ms: 85 ms',
          'sfx_pitch_jitter: ±0.06',
        ],
        edgeCases: const [
          '[GUARD] Cancel active tween cleanly when interrupted',
        ],
        checklist: [
          Subtask(
            id: generateUniqueId('check'),
            text: 'Hook up visual flash and sound cue for ${feat.title}',
            completed: false,
          ),
          Subtask(
            id: generateUniqueId('check'),
            text: 'Playtest rapid repeated inputs and tune timing values',
            completed: false,
          ),
        ],
      );
      setState(() {
        states.add(newCp);
        _expandedDoneCheckpoints.add(newCp.id);
      });
      feedbackMsg = 'Added Checkpoint ${states.length} (${newCp.cleanStageTitle}) ✓';
    } else if (actionOrPrompt == 'suggest_tuning' ||
        lower.contains('tune') ||
        lower.contains('tuning')) {
      if (targetIdx != -1) {
        final node = states[targetIdx];
        final currentTuning = List<String>.from(
          specBinding.checkpointTuning[node.id] ?? node.tuningParams,
        );
        final candidates = <String>[
          'response_window_ms: 90 ms',
          'cooldown_sec: 0.35 s',
          'lerp_damping: 14.0',
        ];
        for (final c in candidates) {
          if (!currentTuning.contains(c)) {
            currentTuning.add(c);
          }
        }
        setState(() {
          node.tuningParams = currentTuning;
          _expandedDoneCheckpoints.add(node.id);
        });
        feedbackMsg = 'Added tuning parameters to Checkpoint ${targetIdx + 1} ✓';
      }
    } else if (actionOrPrompt == 'add_edge_guards' ||
        lower.contains('guard') ||
        lower.contains('edge')) {
      if (targetIdx != -1) {
        final node = states[targetIdx];
        final currentEdges = List<String>.from(
          specBinding.checkpointEdgeCases[node.id] ?? node.edgeCases,
        );
        final candidates = <String>[
          '[GUARD] Ignore duplicate input while state transition is active',
          '[GUARD] Clamp velocity and position within arena bounds on frame spike',
        ];
        for (final c in candidates) {
          if (!currentEdges.contains(c)) {
            currentEdges.add(c);
          }
        }
        setState(() {
          node.edgeCases = currentEdges;
          _expandedDoneCheckpoints.add(node.id);
        });
        feedbackMsg = 'Added [GUARD] edge cases to Checkpoint ${targetIdx + 1} ✓';
      }
    } else if (targetIdx != -1 && actionOrPrompt.trim().isNotEmpty) {
      final node = states[targetIdx];
      setState(() {
        node.checklist.add(
          Subtask(
            id: generateUniqueId('check'),
            text: actionOrPrompt.trim(),
            completed: false,
          ),
        );
        _awaitingPlaytestVerification.remove(node.id);
        _expandedDoneCheckpoints.add(node.id);
      });
      feedbackMsg = 'Added task to Checkpoint ${targetIdx + 1} ✓';
    }

    widget.workbench.updateFeatureStates(feat.id, states);
    if (!mounted) return;
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
        border: Border(top: BorderSide(color: _borderSubtle)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Collapsible 3 Side-by-Side Co-Pilot Playing Cards Drawer
              if (_showCoPilotDrawer) ...[
                Row(
                  children: [
                    buildCoPilotCard(
                      key: const ValueKey('copilot_card_add_checkpoint'),
                      badge: 'CO-PILOT 01 · CHECKPOINT',
                      badgeColor: _accentEmerald,
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
                      badgeColor: _accentAmber,
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
                      badgeColor: _accentCrimson,
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
              // Row 2: [ASK AGENT] Feature Co-Pilot Input Bar + Co-Pilot Drawer Toggle
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
                            ? _accentEmerald.withValues(alpha: 0.14)
                            : _bgRecessed,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _showCoPilotDrawer
                              ? _accentEmerald.withValues(alpha: 0.45)
                              : _borderSubtle,
                        ),
                      ),
                      child: Text(
                        '✦ Co-Pilot Cards (3) ${_showCoPilotDrawer ? "▾" : "▴"}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _showCoPilotDrawer ? _accentEmerald : _textSecondary,
                        ),
                      ),
                    ),
                  ),
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
                              color: _accentEmerald.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'ASK AGENT',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: _accentEmerald,
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
                                color: _accentAmber,
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
                        icon: Icon(Icons.copy_rounded, size: 13, color: _accentAmber),
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
