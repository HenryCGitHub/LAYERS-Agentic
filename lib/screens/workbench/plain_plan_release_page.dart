import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'plain_doc_widgets.dart';

/// Flat 700px in-page Plan Next Release planner backed by [WorkbenchProgressivePlannerMixin].
class PlainPlanReleasePage extends StatefulWidget {
  final WorkbenchProvider workbench;

  const PlainPlanReleasePage({super.key, required this.workbench});

  @override
  State<PlainPlanReleasePage> createState() => _PlainPlanReleasePageState();
}

class _PlainPlanReleasePageState extends State<PlainPlanReleasePage> {
  final TextEditingController _directionCtrl = TextEditingController();

  @override
  void dispose() {
    _directionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final isDark = wb.isDark;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final draft = wb.progressiveDraft;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  PlainTextLink(
                    key: const ValueKey('plan_release_cancel_btn'),
                    label: '← Cancel',
                    isDark: isDark,
                    color: textSecondary,
                    onTap: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      wb.closeInPagePlanNextRelease();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (wb.isDraftingProgressive && draft == null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: focal,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Drafting ${wb.nextReleaseVersionTag} release options…',
                        style: TextStyle(fontSize: 13.5, color: textPrimary),
                      ),
                      const SizedBox(height: 12),
                      PlainTextLink(
                        key: const ValueKey('copilot_loading_cancel_btn'),
                        label: 'Cancel',
                        isDark: isDark,
                        color: textMuted,
                        onTap: () => wb.closeInPagePlanNextRelease(),
                      ),
                    ],
                  ),
                ),
              ] else if (draft == null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No release draft active. Choose + New from the header to plan the next release.',
                    style: TextStyle(fontSize: 13, color: textMuted),
                  ),
                ),
              ] else ...[
                Text(
                  'PLAN NEXT RELEASE · ${draft.targetVersion.toUpperCase()}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Plan ${draft.targetVersion}',
                  style: AppTheme.displayFont(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                PlainDocDivider(isDark: isDark, spacing: 18),

                // Direction steer row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('copilot_direction_input'),
                        controller: _directionCtrl,
                        enabled: !wb.isDraftingProgressive,
                        style: TextStyle(fontSize: 13, color: textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText:
                              'Steer ${draft.targetVersion} focus (e.g., boss wave, stamina depth)...',
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            color: textMuted,
                          ),
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
                        onSubmitted: (val) => wb.openProgressiveReleaseCopilot(
                          directionPrompt: val.trim(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    PlainPrimaryButton(
                      key: const ValueKey('copilot_regenerate_btn'),
                      label: wb.isDraftingProgressive
                          ? 'Drafting…'
                          : 'Ask Co-Pilot',
                      outlined: true,
                      isDark: isDark,
                      onPressed: wb.isDraftingProgressive
                          ? null
                          : () => wb.openProgressiveReleaseCopilot(
                              directionPrompt: _directionCtrl.text.trim(),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (draft.presets.isNotEmpty) ...[
                  PlainSectionHeader(title: 'Direction', isDark: isDark),
                  const SizedBox(height: 6),
                  for (final preset in draft.presets) ...[
                    () {
                      final selected = draft.activePresetId == preset.id;
                      return Tooltip(
                        message: preset.description,
                        child: InkWell(
                          key: ValueKey('copilot_preset_${preset.id}'),
                          onTap: wb.isDraftingProgressive
                              ? null
                              : () => wb.applyProgressivePreset(preset.id),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: selected ? focal : Colors.transparent,
                                  width: 2,
                                ),
                                bottom: BorderSide(color: border, width: 1),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        preset.label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: selected
                                              ? textPrimary
                                              : textSecondary,
                                        ),
                                      ),
                                      if (preset.description.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          preset.description,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: textMuted,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (selected)
                                  Text(
                                    'Selected',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10.5,
                                      color: focal,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }(),
                  ],
                  const SizedBox(height: 20),
                ],

                PlainSectionHeader(
                  title: '${draft.targetVersion} Goal',
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                KeyedSubtree(
                  key: ValueKey(
                    'plan_release_goal_wrap_${draft.targetVersion}_${draft.activePresetId ?? "custom"}',
                  ),
                  child: PlainEditableLineField(
                    fieldKey: const ValueKey('plan_release_goal_input'),
                    value: draft.customGoal,
                    isDark: isDark,
                    multiLine: true,
                    minLines: 2,
                    allowEmpty: true,
                    hintText: 'Define what ${draft.targetVersion} ships...',
                    onChanged: wb.updateProgressiveCustomGoal,
                    onCommit: wb.updateProgressiveCustomGoal,
                  ),
                ),
                const SizedBox(height: 22),

                PlainSectionHeader(
                  title: 'Baseline Epics (+DELTA Upgrades & +NEW Slices)',
                  isDark: isDark,
                ),
                const SizedBox(height: 6),
                for (final base in wb.latestReleaseEpics) ...[
                  () {
                    final keyLower = base.lineageKey.toLowerCase();
                    final upgrades =
                        draft.upgradesByLineageKey[keyLower] ??
                        const <EpicUpgradeOption>[];
                    final newFeatures =
                        draft.candidateNewFeaturesByLineageKey[keyLower] ??
                        const <FeatureSpec>[];
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: border, width: 1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${base.code} ${base.title}',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          if (upgrades.isEmpty && newFeatures.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Keep baseline',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                              ),
                            ),
                          for (final up in upgrades)
                            Material(
                              type: MaterialType.transparency,
                              child: CheckboxListTile(
                                key: ValueKey('copilot_up_${up.id}'),
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                value: up.chosen,
                                onChanged: wb.isDraftingProgressive
                                    ? null
                                    : (_) => wb.toggleProgressiveUpgrade(
                                        base.lineageKey,
                                        up.id,
                                      ),
                                title: Text(
                                  up.targetFeatureCode != null &&
                                          up.targetFeatureCode!.trim().isNotEmpty
                                      ? '[+DELTA ${up.targetFeatureCode!.trim()}] ${up.text}'
                                      : '[+DELTA] ${up.text}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: up.chosen ? amber : textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          for (final nf in newFeatures)
                            Material(
                              type: MaterialType.transparency,
                              child: CheckboxListTile(
                                key: ValueKey('copilot_new_feat_${nf.id}'),
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                value: wb.isProgressiveNewFeatureChosen(nf.id),
                                onChanged: wb.isDraftingProgressive
                                    ? null
                                    : (_) => wb.toggleProgressiveNewFeature(
                                        base.lineageKey,
                                        nf.id,
                                      ),
                                title: Text(
                                  '[+NEW ${nf.code}] ${nf.title} (${nf.sliceTime})',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        wb.isProgressiveNewFeatureChosen(nf.id)
                                            ? cyan
                                            : textSecondary,
                                  ),
                                ),
                                subtitle: nf.goal.isNotEmpty
                                    ? Text(
                                        nf.goal,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: textMuted,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    );
                  }(),
                ],

                if (draft.candidateNewEpics.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  PlainSectionHeader(
                    title: 'New ${draft.targetVersion.toUpperCase()} Epics',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 6),
                  for (final cand in draft.candidateNewEpics)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: border, width: 1),
                        ),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: CheckboxListTile(
                          key: ValueKey('copilot_new_${cand.id}'),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          value: cand.chosenForNextRelease,
                          onChanged: wb.isDraftingProgressive
                              ? null
                              : (_) => wb.toggleProgressiveNewEpic(cand.id),
                          title: Text(
                            '[NEW] ${cand.code} · ${cand.title}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            cand.features.isNotEmpty
                                ? '${cand.goal} · ${cand.features.length} Feature slices'
                                : cand.goal,
                            style: TextStyle(fontSize: 12, color: textMuted),
                          ),
                        ),
                      ),
                    ),
                ],

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: !wb.hasSelectedProgressiveChanges
                          ? Text(
                              'Select at least 1 +DELTA upgrade, +NEW slice, or Epic.',
                              style: TextStyle(fontSize: 12, color: textMuted),
                            )
                          : const SizedBox.shrink(),
                    ),
                    PlainTextLink(
                      label: 'Cancel',
                      isDark: isDark,
                      color: textSecondary,
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        wb.closeInPagePlanNextRelease();
                      },
                    ),
                    const SizedBox(width: 14),
                    PlainPrimaryButton(
                      key: const ValueKey('copilot_commit_btn'),
                      label: 'Create ${draft.targetVersion} →',
                      isDark: isDark,
                      onPressed: (!wb.isDraftingProgressive &&
                              wb.hasSelectedProgressiveChanges)
                          ? () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              wb.commitProgressiveReleaseDraft();
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
