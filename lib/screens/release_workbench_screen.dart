import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'widgets/unreal_bridge_modals.dart';

part 'workbench_progressive_planner_part.dart';

/// Stage 2: `2. Epic Specs` (`Project -> Release -> Epic` 6-Section Unreal MCP Spec Studio).
/// Left Outliner Rail + Centered Single-Column Spec Document (`Clean Epic Spec` | `Exact Unreal MCP Payload`).
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
  final TextEditingController _fixInputController = TextEditingController();

  @override
  void dispose() {
    _fixInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final epics = wb.activeReleaseEpics;
    final selectedEpic = wb.selectedEpicSpec ?? (epics.isNotEmpty ? epics.first : null);
    final isDark = wb.isDark;

    if (epics.isEmpty || selectedEpic == null) {
      return Container(
        color: AppTheme.bgBaseFor(isDark),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No Unreal Epics planned yet.',
                style: AppTheme.displayFont(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimaryFor(isDark),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => wb.setStage(WorkbenchStage.projectPitch),
                child: const Text('← Return to 1. Project Spec'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;
        return Container(
          color: AppTheme.bgBaseFor(isDark),
          child: Row(
            children: [
              if (isWide) _buildLeftOutlinerRail(context, wb, epics, selectedEpic),
              Expanded(
                child: Column(
                  children: [
                    if (!isWide)
                      _buildCompactSwitcherBar(context, wb, epics, selectedEpic),
                    Expanded(
                      child: _buildCenteredSpecWorkspace(
                        context,
                        wb,
                        selectedEpic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeftOutlinerRail(
    BuildContext context,
    WorkbenchProvider wb,
    List<EpicSpec> epics,
    EpicSpec activeEpic,
  ) {
    final isDark = wb.isDark;
    final border = AppTheme.borderFor(isDark);
    final panelBg = AppTheme.bgPanelFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);

    final passedCount = epics.where((e) => e.isPassed).length;
    final releases = wb.projectReleases;

    return Container(
      width: 272,
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Release selector header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (releases.length > 1)
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      isDense: true,
                      value: wb.activeReleaseId,
                      dropdownColor: AppTheme.bgSurfaceRaisedFor(isDark),
                      items: [
                        for (final r in releases)
                          DropdownMenuItem<String>(
                            value: r.id,
                            child: Text(
                              wb.releaseDisplayName(r),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) wb.selectActiveRelease(val);
                      },
                    ),
                  )
                else
                  Text(
                    wb.activeRelease != null
                        ? wb.releaseDisplayName(wb.activeRelease!)
                        : 'v0.1 · Prototype',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  '$passedCount / ${epics.length} Epics Passed PIE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: passedCount == epics.length ? green : muted,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: border),

          // System Epic list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: epics.length,
              itemBuilder: (ctx, i) {
                final ep = epics[i];
                final isSelected = ep.id == activeEpic.id;
                final statusColor = ep.openFixesCount > 0
                    ? red
                    : ep.isPassed
                        ? green
                        : (ep.lifecycle == EpicLifecycle.upgrading ||
                                ep.lifecycle == EpicLifecycle.newEpic)
                            ? cyan
                            : amber;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    key: ValueKey('outliner_epic_${ep.id}'),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    onTap: () => wb.selectEpic(ep.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.bgSurfaceActiveFor(isDark)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(
                          color: isSelected
                              ? cyan.withValues(alpha: 0.45)
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                ep.code,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? cyan : muted,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  borderRadius:
                                      BorderRadius.circular(AppTheme.radiusXs),
                                ),
                                child: Text(
                                  ep.statusLabel,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ep.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected
                                  ? primary
                                  : AppTheme.textSecondaryFor(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom Release Gate & LayersBridge card
          Divider(height: 1, color: border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  key: const ValueKey('plan_next_release_btn'),
                  onPressed: () =>
                      showProgressiveReleaseCopilotDialog(context, wb),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: wb.isActiveReleaseComplete
                        ? green
                        : AppTheme.bgSurfaceRaisedFor(isDark),
                    foregroundColor:
                        wb.isActiveReleaseComplete ? Colors.black : primary,
                    side: BorderSide(
                      color: wb.isActiveReleaseComplete ? green : border,
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 15),
                  label: Text(
                    wb.nextReleaseActionLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => showConnectUnrealPluginDialog(context, wb),
                  icon: Icon(
                    Icons.cable,
                    size: 14,
                    color: wb.isActiveProjectSyncedWithUnreal ? green : cyan,
                  ),
                  label: Text(
                    wb.isActiveProjectSyncedWithUnreal
                        ? wb.formatUnrealSyncStatusLabel()
                        : 'LayersBridge Setup',
                    style: const TextStyle(fontSize: 11.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSwitcherBar(
    BuildContext context,
    WorkbenchProvider wb,
    List<EpicSpec> epics,
    EpicSpec activeEpic,
  ) {
    final isDark = wb.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgPanelFor(isDark),
        border: Border(bottom: BorderSide(color: AppTheme.borderFor(isDark))),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: activeEpic.id,
                dropdownColor: AppTheme.bgSurfaceRaisedFor(isDark),
                items: [
                  for (final ep in epics)
                    DropdownMenuItem<String>(
                      value: ep.id,
                      child: Text(
                        '${ep.code} · ${ep.title} (${ep.statusLabel})',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textPrimaryFor(isDark),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) wb.selectEpic(id);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => showProgressiveReleaseCopilotDialog(context, wb),
            child: Text(wb.nextReleaseActionLabel, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildCenteredSpecWorkspace(
    BuildContext context,
    WorkbenchProvider wb,
    EpicSpec epic,
  ) {
    final isDark = wb.isDark;
    final border = AppTheme.borderFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);

    final openFixesCount = epic.openFixesCount;
    final payloadText = wb.activeEpicMcpPayload(epic);

    return Column(
      children: [
        // Spec Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.bgPanelFor(isDark),
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cyan.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                      ),
                      child: Text(
                        '${epic.code} · ${epic.releaseVersion}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cyan,
                        ),
                      ),
                    ),
                    Text(
                      epic.title,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.displayFont(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    if (openFixesCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                          border: Border.all(color: red.withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          '$openFixesCount [FIX] Focused Mode',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: red,
                          ),
                        ),
                      ),
                    _SpecViewTabSwitch(
                      isDark: isDark,
                      isRaw: wb.showRawEpicPayload,
                      onChanged: (isRaw) => wb.toggleRawEpicPayload(isRaw),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('copy_epic_mcp_payload_btn'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: payloadText));
                        AppToast.show(
                          context,
                          openFixesCount > 0
                              ? 'Copied Focused Revision Payload ($openFixesCount [FIX])'
                              : 'Copied Full Unreal MCP Payload (${epic.code})',
                          isDark: isDark,
                        );
                      },
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('Copy MCP Payload', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Scrollable single-column body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: wb.showRawEpicPayload
                    ? _buildExactMcpPayloadView(wb, epic, payloadText, isDark, primary, border, cyan, red)
                    : _buildSixSectionEpicSpec(wb, epic, isDark, primary, muted, border, cyan, green, red),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExactMcpPayloadView(
    WorkbenchProvider wb,
    EpicSpec epic,
    String payloadText,
    bool isDark,
    Color primary,
    Color border,
    Color cyan,
    Color red,
  ) {
    final openFixesCount = epic.openFixesCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgInsetFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: openFixesCount > 0 ? red.withValues(alpha: 0.45) : border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                openFixesCount > 0 ? Icons.build_circle_outlined : Icons.terminal,
                size: 15,
                color: openFixesCount > 0 ? red : cyan,
              ),
              const SizedBox(width: 8),
              Text(
                openFixesCount > 0
                    ? 'WIRE PREVIEW · FOCUSED PIE REVISION PASS ($openFixesCount OPEN [FIX])'
                    : 'WIRE PREVIEW · SINGLE-PASS FULL EPIC PAYLOAD (ROOT + ${epic.code})',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: openFixesCount > 0 ? red : cyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            payloadText,
            key: const ValueKey('raw_epic_mcp_payload_text'),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12.5,
              color: primary,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSixSectionEpicSpec(
    WorkbenchProvider wb,
    EpicSpec epic,
    bool isDark,
    Color primary,
    Color muted,
    Color border,
    Color cyan,
    Color green,
    Color red,
  ) {
    final target = wb.targetEngine;
    final secondary = AppTheme.textSecondaryFor(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // §01 System Intent & Actor Links
        _EpicSectionCard(
          isDark: isDark,
          code: '§01',
          title: 'System Intent & Actor Links',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                epic.goal,
                style: TextStyle(fontSize: 14.5, color: primary, height: 1.45),
              ),
              if (epic.upgradeDeltas.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: cyan.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${epic.releaseVersion} UPGRADE DELTAS (BASELINE LOCKED)',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cyan,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final d in epic.upgradeDeltas)
                        Text(
                          '• $d',
                          style: TextStyle(fontSize: 13, color: primary, height: 1.35),
                        ),
                    ],
                  ),
                ),
              ],
              if (epic.links.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Actor & Asset Links',
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 6),
                for (final l in epic.links)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $l', style: TextStyle(fontSize: 13, color: secondary)),
                  ),
              ],
              if (epic.outOfScope.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final cut in epic.outOfScope)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                          border: Border.all(color: red.withValues(alpha: 0.3)),
                        ),
                        child: Text(cut, style: TextStyle(fontSize: 12, color: primary)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §02 Controls
        _EpicSectionCard(
          isDark: isDark,
          code: '§02',
          title: 'Controls (${target.inputContractLabel})',
          child: epic.controls.isEmpty
              ? Text('Passive / non-input Epic.', style: TextStyle(color: muted))
              : Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.5),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(2.8),
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(color: border),
                  ),
                  children: [
                    for (final c in epic.controls)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Text(
                              c.action,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cyan,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Text(
                              c.trigger,
                              style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: muted),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Text(
                              c.rule,
                              style: TextStyle(fontSize: 13, color: primary),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),

        // §03 State Flow & Interrupt Rules
        _EpicSectionCard(
          isDark: isDark,
          code: '§03',
          title: 'State Flow & Interrupt Rules',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final st in epic.states)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    st,
                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: primary),
                  ),
                ),
              for (final rule in epic.interrupts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $rule', style: TextStyle(fontSize: 13, color: secondary)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §04 Spatial & Exposed Tuning (Live Editable -> Immediate MCP Payload Update)
        _EpicSectionCard(
          isDark: isDark,
          code: '§04',
          title: 'Spatial & Exposed Tuning (${target.tuningColumnLabel})',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (int i = 0; i < epic.tuning.length; i++)
                _LiveTuningChip(
                  key: ValueKey('tuning_chip_${epic.id}_$i'),
                  inputKey: ValueKey('tuning_input_${epic.id}_$i'),
                  param: epic.tuning[i],
                  isDark: isDark,
                  onChanged: (val) => wb.updateEpicTuningParam(epic.id, i, val),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §05 Viewport, UMG & Audio Cues
        _EpicSectionCard(
          isDark: isDark,
          code: '§05',
          title: 'Viewport, UMG & Audio Cues',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final cue in epic.feedback)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('• $cue', style: TextStyle(fontSize: 13, color: primary)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // §06 Test Level Staging & PIE Acceptance Gate
        _EpicSectionCard(
          isDark: isDark,
          code: '§06',
          title: 'Test Level Staging & PIE Acceptance Gate',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (epic.levelStaging.trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurfaceFor(isDark),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    'Test Level: ${epic.levelStaging}',
                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: cyan),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              for (final chk in epic.checks)
                Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    key: ValueKey('pie_check_${chk.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: chk.passed,
                    onChanged: (val) => wb.togglePieCheck(epic.id, chk.id, val),
                    title: Text(
                      chk.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: chk.passed ? green : primary,
                        decoration:
                            chk.passed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 14),
              // [FIX] Flagging input + list
              Text(
                'Flag Playtest Revision ([FIX]) — switches Epic MCP payload to Focused Revision Pass:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondary),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('flag_fix_input'),
                      controller: _fixInputController,
                      style: TextStyle(fontSize: 13, color: primary),
                      decoration: InputDecoration(
                        hintText: 'e.g. Dash stops early against north barrier wall...',
                        hintStyle: TextStyle(fontSize: 12.5, color: muted),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _submitFlagFix(wb, epic.id),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('flag_fix_btn'),
                    onPressed: () => _submitFlagFix(wb, epic.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: red,
                      side: BorderSide(color: red.withValues(alpha: 0.45)),
                    ),
                    icon: const Icon(Icons.flag_outlined, size: 15),
                    label: const Text('Flag [FIX]'),
                  ),
                ],
              ),

              if (epic.fixes.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final fx in epic.fixes)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: fx.resolved
                          ? green.withValues(alpha: 0.08)
                          : red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(
                        color: fx.resolved
                            ? green.withValues(alpha: 0.3)
                            : red.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          fx.resolved ? '[FIXED]' : '[FIX]',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: fx.resolved ? green : red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fx.text,
                            style: TextStyle(
                              fontSize: 13,
                              color: primary,
                              decoration:
                                  fx.resolved ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        if (!fx.resolved)
                          TextButton(
                            key: ValueKey('resolve_fix_${fx.id}'),
                            onPressed: () => wb.resolveEpicFix(epic.id, fx.id),
                            child: Text(
                              'Resolve ✓',
                              style: TextStyle(color: green, fontSize: 12),
                            ),
                          ),
                        IconButton(
                          icon: Icon(Icons.close, size: 15, color: muted),
                          onPressed: () => wb.deleteEpicFix(epic.id, fx.id),
                          tooltip: 'Remove note',
                        ),
                      ],
                    ),
                  ),
              ],

              const SizedBox(height: 16),
              Row(
                children: [
                  const Spacer(),
                  if (epic.isPassed)
                    OutlinedButton.icon(
                      key: const ValueKey('reopen_epic_btn'),
                      onPressed: () => wb.reopenEpic(epic.id),
                      icon: const Icon(Icons.replay, size: 15),
                      label: const Text('Reopen Epic'),
                    )
                  else
                    ElevatedButton.icon(
                      key: const ValueKey('pass_epic_btn'),
                      onPressed: () => wb.passActiveEpic(epic.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                      ),
                      icon: const Icon(Icons.verified_outlined, size: 16),
                      label: Text('Pass ${epic.code} PIE Gate ✓'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }

  void _submitFlagFix(WorkbenchProvider wb, String epicId) {
    final text = _fixInputController.text.trim();
    if (text.isEmpty) return;
    _fixInputController.clear();
    wb.flagEpicFix(epicId, text);
  }
}

class _SpecViewTabSwitch extends StatelessWidget {
  final bool isDark;
  final bool isRaw;
  final ValueChanged<bool> onChanged;

  const _SpecViewTabSwitch({
    required this.isDark,
    required this.isRaw,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(isDark);
    final raised = AppTheme.bgSurfaceRaisedFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('stage2_tab_clean'),
            onTap: () => onChanged(false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: !isRaw ? raised : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              ),
              child: Text(
                'Clean Epic Spec',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: !isRaw ? FontWeight.w600 : FontWeight.w400,
                  color: !isRaw ? primary : muted,
                ),
              ),
            ),
          ),
          InkWell(
            key: const ValueKey('stage2_tab_raw'),
            onTap: () => onChanged(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isRaw ? raised : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
              ),
              child: Text(
                'Exact Unreal MCP Payload',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isRaw ? FontWeight.w600 : FontWeight.w400,
                  color: isRaw ? primary : muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpicSectionCard extends StatelessWidget {
  final bool isDark;
  final String code;
  final String title;
  final Widget child;

  const _EpicSectionCard({
    required this.isDark,
    required this.code,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceRaisedFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.borderFor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentCyanFor(isDark),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.displayFont(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimaryFor(isDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LiveTuningChip extends StatefulWidget {
  final EpicTuningParam param;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final Key? inputKey;

  const _LiveTuningChip({
    super.key,
    this.inputKey,
    required this.param,
    required this.isDark,
    required this.onChanged,
  });

  @override
  State<_LiveTuningChip> createState() => _LiveTuningChipState();
}

class _LiveTuningChipState extends State<_LiveTuningChip> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.param.value);
  }

  @override
  void didUpdateWidget(covariant _LiveTuningChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.param.value != widget.param.value &&
        _controller.text != widget.param.value) {
      _controller.text = widget.param.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(widget.isDark);
    final cyan = AppTheme.accentCyanFor(widget.isDark);
    final muted = AppTheme.textMutedFor(widget.isDark);
    final primary = AppTheme.textPrimaryFor(widget.isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(widget.isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.param.key}:',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: TextField(
              key: widget.inputKey,
              controller: _controller,
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: cyan,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              ),
              onChanged: widget.onChanged,
            ),
          ),
          if (widget.param.unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              widget.param.unit,
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
