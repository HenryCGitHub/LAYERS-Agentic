import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/agent_blueprints.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import '../workbench/plain_doc_widgets.dart';

/// Flat 3-angle exploration block rendered on the New Game view with 1px rules
/// and a 2px left active bar (zero cards or pill badges).
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
  final TextEditingController _steerCtrl = TextEditingController();
  String? _lastProjId;

  @override
  void initState() {
    super.initState();
    _lastProjId = widget.activeProjectId;
  }

  @override
  void didUpdateWidget(covariant Stage1IdeaAnglesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastProjId != widget.activeProjectId) {
      _lastProjId = widget.activeProjectId;
      _steerCtrl.clear();
    }
  }

  @override
  void dispose() {
    _steerCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitSteer() async {
    final wb = widget.workbench;
    final text = _steerCtrl.text.trim();
    if (text.isEmpty || wb.isAgentBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await wb.exploreSparkAngles(widget.deck.rawSpark, steerNote: text);
    if (mounted) _steerCtrl.clear();
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
    final focal = AppTheme.focalAccentFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final selectedAngle = deck.selectedAngle;

    return Padding(
      key: const ValueKey('stage1_idea_angles_card'),
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlainSectionHeader(
            title: 'Pick an Angle',
            isDark: isDark,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Round ${deck.round}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: textMuted,
                  ),
                ),
                Text(
                  ' · ${deck.architectureMode.shortLabel}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (deck.steerHistory.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in deck.steerHistory)
                  Text(
                    s,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      color: focal,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, angleConstraints) {
              final threeCol =
                  angleConstraints.maxWidth >= 560 && deck.angles.length == 3;
              if (threeCol) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < deck.angles.length; i++)
                        Expanded(
                          child: _buildAngleColumnCell(
                            wb: wb,
                            angle: deck.angles[i],
                            selected: deck.angles[i].id == selectedAngle.id,
                            showRightDivider: i < deck.angles.length - 1,
                            isDark: isDark,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            textMuted: textMuted,
                            border: border,
                            focal: focal,
                            green: green,
                          ),
                        ),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < deck.angles.length; i++)
                    _buildAngleRow(
                      wb: wb,
                      angle: deck.angles[i],
                      selected: deck.angles[i].id == selectedAngle.id,
                      isDark: isDark,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      textMuted: textMuted,
                      border: border,
                      focal: focal,
                      green: green,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final field = TextField(
                key: const ValueKey('stage1_angle_steer_input'),
                controller: _steerCtrl,
                enabled: !wb.isAgentBusy,
                style: TextStyle(fontSize: 13, color: textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Steer angles (e.g., slower stamina combat, top-down)...',
                  hintStyle: TextStyle(fontSize: 12.5, color: textMuted),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 8,
                  ),
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: focal),
                  ),
                ),
                onSubmitted: (_) => _submitSteer(),
              );
              final btns = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlainPrimaryButton(
                    key: const ValueKey('stage1_angle_steer_btn'),
                    label: 'Steer',
                    outlined: true,
                    isDark: isDark,
                    onPressed: wb.isAgentBusy ? null : _submitSteer,
                  ),
                  const SizedBox(width: 8),
                  PlainPrimaryButton(
                    key: const ValueKey('stage1_angle_reroll_btn'),
                    label: '↻ Reroll',
                    outlined: true,
                    isDark: isDark,
                    onPressed: wb.isAgentBusy
                        ? null
                        : () => wb.exploreSparkAngles(
                              deck.rawSpark,
                              reroll: true,
                            ),
                  ),
                ],
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: btns),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 10),
                  btns,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Selected: ${selectedAngle.title} · ${selectedAngle.cameraHint}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              PlainPrimaryButton(
                key: const ValueKey('stage1_lock_angle_draft_btn'),
                label: 'Draft Selected Angle →',
                isDark: isDark,
                onPressed: wb.isAgentBusy
                    ? null
                    : () => wb.draftSpecFromSelectedAngle(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAngleColumnCell({
    required WorkbenchProvider wb,
    required SparkAngleOption angle,
    required bool selected,
    required bool showRightDivider,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color border,
    required Color focal,
    required Color green,
  }) {
    return InkWell(
      key: ValueKey('stage1_angle_card_${angle.id}'),
      onTap: wb.isAgentBusy ? null : () => wb.selectSparkAngle(angle.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.bgSurfaceActiveFor(isDark)
              : Colors.transparent,
          border: Border(
            top: BorderSide(
              color: selected ? focal : border,
              width: selected ? 2 : 1,
            ),
            right: showRightDivider
                ? BorderSide(color: border, width: 1)
                : BorderSide.none,
            bottom: BorderSide(color: border, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    angle.styleTag.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: selected ? focal : textMuted,
                    ),
                  ),
                ),
                Text(
                  selected ? '✓' : 'Select',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? green : textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              angle.title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              angle.pitch,
              style: TextStyle(fontSize: 12, height: 1.4, color: textSecondary),
            ),
            const Spacer(),
            const SizedBox(height: 6),
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
    );
  }

  Widget _buildAngleRow({
    required WorkbenchProvider wb,
    required SparkAngleOption angle,
    required bool selected,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color border,
    required Color focal,
    required Color green,
  }) {
    return InkWell(
      key: ValueKey('stage1_angle_card_${angle.id}'),
      onTap: wb.isAgentBusy ? null : () => wb.selectSparkAngle(angle.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.bgSurfaceActiveFor(isDark)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? focal : Colors.transparent,
              width: 2,
            ),
            bottom: BorderSide(color: border, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  angle.styleTag.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? focal : textMuted,
                  ),
                ),
                const Spacer(),
                Text(
                  selected ? '✓ Selected' : 'Select',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? green : textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              angle.title,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              angle.pitch,
              style: TextStyle(fontSize: 13, height: 1.45, color: textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              '${angle.cameraHint} · ${angle.sliceHint}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
