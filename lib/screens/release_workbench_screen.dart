import 'package:flutter/material.dart';
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
  bool _showOutOfScopeShelf = false;
  bool _hideUnassignedSpecShelf = false;

  @override
  void dispose() {
    for (final c in _newTaskControllers.values) {
      c.dispose();
    }
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
              if (widget.workbench.focusMode && activeFocusIndex != -1)
                Text(
                  '🎯 Focus Mode: Expanding Active Checkpoint ${activeFocusIndex + 1} of ${states.length}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _accentAmber,
                  ),
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

    if (shrinkWrap) return body;

    return Container(
      color: _bgBase,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: body,
          ),
        ),
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
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              decoration: BoxDecoration(
                color: _bgRecessed,
                border: Border(top: BorderSide(color: _borderSubtle)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in outOfScope)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          tag('CUT', _accentCrimson, width: 48),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
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

    final checklistPane = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int tIdx = 0; tIdx < node.checklist.length; tIdx++)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: ValueKey('task_checkbox_${node.id}_$tIdx'),
                    onTap: () {
                      final wasDone = node.isCompleted;
                      node.checklist[tIdx].completed =
                          !node.checklist[tIdx].completed;
                      final nowDone = node.isCompleted;
                      setState(() {
                        if (!wasDone && nowDone) {
                          // Hold checkpoint open so the developer can read the PLAYTEST instructions
                          // and click "Verify Playtest & Advance"
                          _awaitingPlaytestVerification.add(node.id);
                        } else if (!nowDone) {
                          _awaitingPlaytestVerification.remove(node.id);
                        }
                      });
                      widget.workbench.updateFeatureStates(feat.id, states);
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 5,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            node.checklist[tIdx].completed
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 16,
                            color: node.checklist[tIdx].completed
                                ? _accentEmerald
                                : _accentAmber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              node.checklist[tIdx].text,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: node.checklist[tIdx].completed
                                    ? _textMuted
                                    : _textPrimary,
                                decoration: node.checklist[tIdx].completed
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
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
          const SizedBox(height: 6),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: (isDone ? _accentEmerald : _accentAmber).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'PLAYTEST',
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
          if (isAwaitingPlaytest) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: ValueKey('verify_playtest_btn_$index'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentEmerald,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          if (scopedItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '↳ Scope: ${scopedItems.join(' · ')}',
              style: GoogleFonts.inter(fontSize: 11, color: _textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              for (int tuneIdx = 0; tuneIdx < tuningItems.length; tuneIdx++)
                InkWell(
                  key: ValueKey('tuning_pill_${index}_$tuneIdx'),
                  onTap: () => promptTuningDialog(
                    editIdx: tuneIdx,
                    currentVal: tuningItems[tuneIdx],
                  ),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _accentAmber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _accentAmber.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      tuningItems[tuneIdx],
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _bgSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _borderSubtle),
                  ),
                  child: Text(
                    '+ Tune',
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
          if (edgeItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                for (final e in edgeItems)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _accentCrimson.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _accentCrimson.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      e,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: _textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
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
                    style: GoogleFonts.inter(
                      fontSize: 13,
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
                        Expanded(flex: 60, child: checklistPane),
                        Container(width: 0.8, color: _borderSubtle),
                        Expanded(flex: 40, child: specContextPane),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    specContextPane,
                    checklistPane,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
