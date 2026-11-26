import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/agent_blueprints.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';

/// In-place Stage 1 Idea Workbench card showing 3 AI-proposed playable angles
/// with 1-line steer, reroll, and one-click lock into Argon `PROJECT_SPEC.md` drafting.
class Stage1IdeaAnglesCard extends StatefulWidget {
  final WorkbenchProvider workbench;
  final SparkAngleDeck deck;
  final String? activeProjectId;
  final bool isDark;

  const Stage1IdeaAnglesCard({
    super.key,
    required this.workbench,
    required this.deck,
    required this.activeProjectId,
    required this.isDark,
  });

  @override
  State<Stage1IdeaAnglesCard> createState() => _Stage1IdeaAnglesCardState();
}

class _Stage1IdeaAnglesCardState extends State<Stage1IdeaAnglesCard> {
  final TextEditingController _steerController = TextEditingController();

  @override
  void didUpdateWidget(covariant Stage1IdeaAnglesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeProjectId != widget.activeProjectId ||
        oldWidget.deck.rawSpark != widget.deck.rawSpark) {
      _steerController.clear();
    }
  }

  @override
  void dispose() {
    _steerController.dispose();
    super.dispose();
  }

  Future<void> _submitSteer() async {
    final text = _steerController.text.trim();
    if (text.isEmpty || widget.workbench.isAgentBusy) return;
    final res = await widget.workbench.exploreSparkAngles(
      widget.deck.rawSpark,
      steerNote: text,
    );
    if (!mounted) return;
    if (res != null) {
      _steerController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final deck = widget.deck;
    final isDark = widget.isDark;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final selectedAngle = deck.selectedAngle;

    return Container(
      key: const ValueKey('stage1_idea_angles_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgPanelFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cyan.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                  border: Border.all(color: cyan.withValues(alpha: 0.35)),
                ),
                child: Text(
                  '⚡ Hydrogen · 3 Angles',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: cyan,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pick a Direction for "${deck.rawSpark}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurfaceFor(isDark),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                  border: Border.all(color: border),
                ),
                child: Text(
                  'Round ${deck.round}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Close 3-Angles Picker',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: Icon(Icons.close_rounded, size: 15, color: textMuted),
                onPressed: wb.isAgentBusy ? null : wb.dismissSparkAngles,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Pick the 1-sentence direction that feels closest, steer/reroll in place if needed, then draft your UE5 spec.',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 680) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < deck.angles.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: _buildAngleOptionCard(
                            wb: wb,
                            angle: deck.angles[i],
                            selected: deck.angles[i].id == selectedAngle.id,
                            isDark: isDark,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            textMuted: textMuted,
                            border: border,
                            cyan: cyan,
                            green: green,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < deck.angles.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _buildAngleOptionCard(
                      wb: wb,
                      angle: deck.angles[i],
                      selected: deck.angles[i].id == selectedAngle.id,
                      isDark: isDark,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      textMuted: textMuted,
                      border: border,
                      cyan: cyan,
                      green: green,
                    ),
                  ],
                ],
              );
            },
          ),
          if (deck.steerHistory.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Steers:',
                  style: TextStyle(fontSize: 11.5, color: textMuted),
                ),
                for (final steer in deck.steerHistory)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurfaceFor(isDark),
                      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      steer,
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.bgSurfaceFor(isDark),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: border),
            ),
            child: LayoutBuilder(
              builder: (context, steerConstraints) {
                final narrowSteer = steerConstraints.maxWidth < 520;
                final steerField = TextField(
                  key: const ValueKey('stage1_angle_steer_input'),
                  controller: _steerController,
                  enabled: !wb.isAgentBusy,
                  style: TextStyle(fontSize: 12.5, color: textPrimary),
                  decoration: InputDecoration(
                    hintText:
                        'Steer angles: "Make #1 co-op", "Swap boat for oil rig", "Tighter 1-room slice"...',
                    hintStyle: TextStyle(fontSize: 12, color: textMuted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                  ),
                  onSubmitted: (_) => _submitSteer(),
                );
                final steerBtns = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('stage1_angle_steer_btn'),
                      onPressed: wb.isAgentBusy ? null : _submitSteer,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                      child: const Text('Steer', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton(
                      key: const ValueKey('stage1_angle_reroll_btn'),
                      onPressed: wb.isAgentBusy
                          ? null
                          : () => wb.exploreSparkAngles(
                                deck.rawSpark,
                                reroll: true,
                              ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                      child: const Text(
                        '↻ Reroll',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                );
                if (narrowSteer) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      steerField,
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerRight, child: steerBtns),
                    ],
                  );
                }
                return Row(
                  children: [
                    Text(
                      '✨ Steer',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: cyan,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: steerField),
                    const SizedBox(width: 8),
                    steerBtns,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: border),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Text(
                  'Selected: ${selectedAngle.title} (${selectedAngle.cameraHint}) · ${deck.architectureMode.pillLabel}',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
                ElevatedButton.icon(
                  key: const ValueKey('stage1_lock_angle_draft_btn'),
                  onPressed: wb.isAgentBusy
                      ? null
                      : () => wb.draftSpecFromSelectedAngle(),
                  icon: const Icon(Icons.auto_awesome, size: 15),
                  label: const Text('Draft Selected Angle →'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAngleOptionCard({
    required WorkbenchProvider wb,
    required SparkAngleOption angle,
    required bool selected,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color border,
    required Color cyan,
    required Color green,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('stage1_angle_card_${angle.id}'),
        onTap: wb.isAgentBusy ? null : () => wb.selectSparkAngle(angle.id),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? cyan.withValues(alpha: 0.11)
                : AppTheme.bgSurfaceFor(isDark),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: selected ? cyan : border,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          angle.styleTag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: cyan,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        selected ? '✓ Selected' : 'Select',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? green : textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    angle.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    angle.pitch,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(height: 1, color: border),
                    const SizedBox(height: 7),
                    Text(
                      '${angle.cameraHint} · ${angle.sliceHint}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        color: textMuted,
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
}
