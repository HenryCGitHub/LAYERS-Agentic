import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'cloud_ai_settings_dialog.dart';
import 'project_manage_dialogs.dart';
import 'studio_export_actions.dart';
import 'team_invites_dialog.dart';

const String _actionNewProject = '__new_project__';
const String _actionExportJson = '__export_json__';
const String _actionImportJson = '__import_json__';
const String _prefixRename = '__rename__:';
const String _prefixDuplicate = '__duplicate__:';
const String _prefixDelete = '__delete__:';

class StudioTopBar extends StatelessWidget implements PreferredSizeWidget {
  final WorkbenchProvider workbench;

  const StudioTopBar({super.key, required this.workbench});

  @override
  Size get preferredSize => const Size.fromHeight(50);

  @override
  Widget build(BuildContext context) {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final borderColor = AppTheme.borderFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);

    final bgRecessed = AppTheme.bgSurfaceRecessedFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);

    final draft = workbench.conceptDraft;

    final projTitle = workbench.activeProject?.title.trim();
    final draftIdea = draft?.sparkPrompt.trim();
    final String? rawSpark = (projTitle != null && projTitle.isNotEmpty)
        ? projTitle
        : ((draftIdea != null && draftIdea.isNotEmpty) ? draftIdea : null);
    final String? activeProjectLabel = (rawSpark != null && rawSpark.isNotEmpty)
        ? (rawSpark.length > 22 ? '${rawSpark.substring(0, 22)}…' : rawSpark)
        : null;
    final savedProjects = workbench.savedProjects;

    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bgRecessed,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: LayoutBuilder(
          builder: (context, barConstraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: barConstraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'LAYERS',
                  style: AppTheme.displayFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '/',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: textMuted,
                  ),
                ),
                const SizedBox(width: 5),
                PopupMenuButton<String>(
                  key: const ValueKey('project_switcher_dropdown_btn'),
                  tooltip: 'Switch Project or Start New Spark',
                  color: bgSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: borderColor),
                  ),
                  onSelected: (val) async {
                    if (val == _actionNewProject) {
                      workbench.createNewProject();
                    } else if (val == _actionExportJson) {
                      await exportActiveProjectJson(context, workbench);
                    } else if (val == _actionImportJson) {
                      await showImportProjectJsonDialog(context, workbench);
                    } else if (val.startsWith(_prefixRename)) {
                      final projId = val.substring(_prefixRename.length);
                      final proj = savedProjects.where((p) => p.id == projId).firstOrNull;
                      if (proj == null) return;
                      await promptRenameProjectDialog(context, workbench, proj);
                    } else if (val.startsWith(_prefixDuplicate)) {
                      final projId = val.substring(_prefixDuplicate.length);
                      workbench.duplicateProject(projId);
                    } else if (val.startsWith(_prefixDelete)) {
                      final projId = val.substring(_prefixDelete.length);
                      final proj = savedProjects.where((p) => p.id == projId).firstOrNull;
                      if (proj == null) return;
                      if (await confirmDeleteProjectDialog(context, workbench, proj)) {
                        workbench.deleteProject(projId);
                      }
                    } else {
                      workbench.switchProject(val);
                    }
                  },
                  itemBuilder: (ctx) => [
                    for (final p in savedProjects)
                      PopupMenuItem<String>(
                        value: p.id,
                        child: Row(
                          children: [
                            Icon(
                              p.id == workbench.activeProjectId
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.folder_outlined,
                              size: 13,
                              color: p.id == workbench.activeProjectId
                                  ? textPrimary
                                  : textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: p.id == workbench.activeProjectId
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: p.id == workbench.activeProjectId
                                      ? textPrimary
                                      : textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Tooltip(
                              message: 'Rename Project',
                              child: InkWell(
                                key: ValueKey('switcher_rename_${p.id}'),
                                onTap: () => Navigator.of(ctx).pop('$_prefixRename${p.id}'),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.edit_outlined,
                                    size: 12.5,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Duplicate Project',
                              child: InkWell(
                                key: ValueKey('switcher_duplicate_${p.id}'),
                                onTap: () => Navigator.of(ctx).pop('$_prefixDuplicate${p.id}'),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.copy_all_rounded,
                                    size: 12.5,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Delete Project',
                              child: InkWell(
                                key: ValueKey('switcher_delete_${p.id}'),
                                onTap: () => Navigator.of(ctx).pop('$_prefixDelete${p.id}'),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 13,
                                    color: AppTheme.accentRedFor(isDark),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (savedProjects.isNotEmpty) const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: _actionNewProject,
                      child: Row(
                        children: [
                          Icon(Icons.add_circle_outline_rounded, size: 13, color: textPrimary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '+ New Project',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      key: const ValueKey('switcher_export_project_json_item'),
                      value: _actionExportJson,
                      child: Row(
                        children: [
                          Icon(Icons.file_download_outlined, size: 13, color: textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Export Project (.json)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      key: const ValueKey('switcher_import_project_json_item'),
                      value: _actionImportJson,
                      child: Row(
                        children: [
                          Icon(Icons.file_upload_outlined, size: 13, color: textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Import Project (.json)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (activeProjectLabel != null)
                          Text(
                            activeProjectLabel,
                            key: const ValueKey('top_bar_project_title'),
                            style: AppTheme.displayFont(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: textPrimary,
                            ),
                          )
                        else
                          Text(
                            'Projects',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: textSecondary,
                            ),
                          ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 13,
                          color: textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (workbench.activeRelease != null &&
                    workbench.projectReleases.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '|',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: borderColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    key: const ValueKey('global_bar_release_selector_btn'),
                    tooltip: 'Switch Release Version',
                    color: bgSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: borderColor),
                    ),
                    onSelected: (val) {
                      workbench.selectActiveRelease(val);
                    },
                    itemBuilder: (ctx) => [
                      for (final r in workbench.projectReleases)
                        PopupMenuItem<String>(
                          value: r.id,
                          child: Row(
                            children: [
                              Icon(
                                r.id == workbench.activeRelease?.id
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.layers_outlined,
                                size: 13,
                                color: r.id == workbench.activeRelease?.id
                                    ? textPrimary
                                    : textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight:
                                        r.id == workbench.activeRelease?.id
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                    color: r.id == workbench.activeRelease?.id
                                        ? textPrimary
                                        : textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: bgSurface,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: borderColor,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${workbench.releaseConciseLabel(workbench.activeRelease!)} ▾',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (workbench.activeReleaseEpicDocs.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    key: const ValueKey('nav_stage_1_btn'),
                    borderRadius: BorderRadius.circular(5),
                    onTap: () =>
                        workbench.setStage(WorkbenchStage.projectPitch),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: workbench.currentStage ==
                                WorkbenchStage.projectPitch
                            ? AppTheme.bgSurfaceActiveFor(isDark)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: workbench.currentStage ==
                                  WorkbenchStage.projectPitch
                              ? AppTheme.accentCyanFor(isDark)
                                  .withValues(alpha: 0.45)
                              : borderColor,
                        ),
                      ),
                      child: Text(
                        '1. Project Spec',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: workbench.currentStage ==
                                  WorkbenchStage.projectPitch
                              ? textPrimary
                              : textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    key: const ValueKey('nav_stage_2_btn'),
                    borderRadius: BorderRadius.circular(5),
                    onTap: () =>
                        workbench.setStage(WorkbenchStage.releaseWorkbench),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: workbench.currentStage ==
                                WorkbenchStage.releaseWorkbench
                            ? AppTheme.bgSurfaceActiveFor(isDark)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: workbench.currentStage ==
                                  WorkbenchStage.releaseWorkbench
                              ? AppTheme.accentCyanFor(isDark)
                                  .withValues(alpha: 0.45)
                              : borderColor,
                        ),
                      ),
                      child: Text(
                        '2. Release Workbench',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: workbench.currentStage ==
                                  WorkbenchStage.releaseWorkbench
                              ? textPrimary
                              : textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Clean borderless Studio Utility Strip (Export · Cloud Vault · AI Models · Theme)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (draft != null) ...[
                      Builder(
                        builder: (ctx) {
                          final isNarrowTopBar =
                              MediaQuery.sizeOf(ctx).width < 1040;
                          final accentCyan = AppTheme.accentCyanFor(isDark);
                          return Tooltip(
                            message:
                                'Export & Copy Ultimate Engine CoPilot GDD (*_copilot_gdd.md)',
                            child: InkWell(
                              key: const ValueKey('top_bar_copilot_gdd_btn'),
                              borderRadius: BorderRadius.circular(5),
                              onTap: () => exportCoPilotGdd(context, workbench),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isNarrowTopBar ? 6 : 8,
                                  vertical: 3.5,
                                ),
                                decoration: BoxDecoration(
                                  color: bgSurface,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: accentCyan.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Text(
                                  isNarrowTopBar ? '⚡ GDD' : '⚡ CoPilot GDD',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: accentCyan,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        key: const ValueKey('global_export_spec_btn'),
                        tooltip: 'Export CoPilot GDD, Spec or Backup (.md / .layers.json)',
                        constraints: const BoxConstraints(
                          minWidth: 280,
                          maxWidth: 340,
                        ),
                        color: bgSurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(color: borderColor),
                        ),
                        onSelected: (val) {
                          if (val == 'copilot_gdd') {
                            exportCoPilotGdd(context, workbench);
                          } else if (val == 'spec') {
                            exportFullProjectSpec(context, workbench);
                          } else if (val == 'json_export') {
                            exportActiveProjectJson(context, workbench);
                          } else if (val == 'json_import') {
                            showImportProjectJsonDialog(context, workbench);
                          }
                        },
                        itemBuilder: (ctx) => [
                          _buildExportMenuItem(
                            value: 'copilot_gdd',
                            icon: Icons.bolt_rounded,
                            iconColor: AppTheme.accentCyanFor(isDark),
                            label: 'Export CoPilot GDD (.md)',
                            textColor: textPrimary,
                          ),
                          _buildExportMenuItem(
                            value: 'spec',
                            icon: Icons.copy_rounded,
                            iconColor: textSecondary,
                            label: 'Copy Full Project Spec (.md)',
                            textColor: textPrimary,
                          ),
                          _buildExportMenuItem(
                            value: 'json_export',
                            icon: Icons.download_rounded,
                            iconColor: textSecondary,
                            label: 'Export Project Vault (.layers.json)',
                            textColor: textPrimary,
                          ),
                          _buildExportMenuItem(
                            value: 'json_import',
                            icon: Icons.file_upload_outlined,
                            iconColor: textSecondary,
                            label: 'Import Project Backup (.layers.json)',
                            textColor: textPrimary,
                          ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Text(
                            'Export ▾',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    // Google Account & Cloud Sync Badge
                    Builder(
                      builder: (ctx) {
                        final isNarrow = MediaQuery.sizeOf(ctx).width < 1040;
                        final isSynced = workbench.isCloudSynced;
                        final email = workbench.userEmail ?? '';
                        final initial = email.isNotEmpty ? email[0].toUpperCase() : 'G';
                        final tooltipMsg = isSynced
                            ? 'Signed in as $email · Synced to Firebase Cloud'
                            : 'Project Vault & Google Cloud Sync · Sign in to sync projects';

                        return Tooltip(
                          message: tooltipMsg,
                          child: InkWell(
                            key: const ValueKey('cloud_sync_auth_btn'),
                            onTap: () => showCloudSyncDialog(context, workbench),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isNarrow ? 5 : 7,
                                vertical: 3.5,
                              ),
                              decoration: BoxDecoration(
                                color: bgSurface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSynced
                                      ? const Color(0xFF10B981).withValues(alpha: 0.35)
                                      : borderColor,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSynced) ...[
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFF10B981),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        initial,
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF06281E),
                                        ),
                                      ),
                                    ),
                                    if (!isNarrow && email.isNotEmpty) ...[
                                      const SizedBox(width: 5),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 130),
                                        child: Text(
                                          email,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w500,
                                            color: textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.cloud_done_rounded,
                                      size: 12,
                                      color: Color(0xFF10B981),
                                    ),
                                  ] else ...[
                                    Text(
                                      'G',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: textPrimary,
                                      ),
                                    ),
                                    if (!isNarrow) ...[
                                      const SizedBox(width: 5),
                                      Text(
                                        'Sign in',
                                        style: GoogleFonts.inter(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.cloud_upload_outlined,
                                      size: 12,
                                      color: textMuted,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message:
                          'Active AI Model: ${workbench.activeModelIndicatorLabel} (${workbench.conversationModel}, thinking: ${workbench.thinkingLevel})'
                          '${workbench.activeModelIndicatorLabel.contains('Fallback') && workbench.aiFallbackReason != null ? '\nFallback reason: ${workbench.aiFallbackReason}' : ''}',
                      child: Container(
                        key: const ValueKey('active_model_indicator_pill'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: bgSurface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: workbench.activeModelIndicatorLabel
                                    .contains('Fallback')
                                ? AppTheme.accentAmberFor(isDark)
                                    .withValues(alpha: 0.45)
                                : borderColor,
                          ),
                        ),
                        child: Text(
                          workbench.activeModelIndicatorLabel,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: workbench.activeModelIndicatorLabel
                                    .contains('Fallback')
                                ? AppTheme.accentAmberFor(isDark)
                                : textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Gemini 4 Hydrogen Session Token Usage:\n'
                          '• Input: ${workbench.totalInputTokens} tokens (\$1.50 / 1M)\n'
                          '• Output: ${workbench.totalOutputTokens} tokens (\$7.50 / 1M inc. reasoning)\n'
                          '• Est. Cost: \$${workbench.totalEstimatedCostUsd.toStringAsFixed(4)}\n\n'
                          'Click to reset session token counter.',
                      child: InkWell(
                        key: const ValueKey('token_usage_tracker_pill'),
                        onTap: workbench.resetTokenUsage,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.token_outlined,
                                size: 11,
                                color: textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                workbench.tokenUsageCompactLabel,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (workbench.isAdminUser) ...[
                      const SizedBox(width: 4),
                      Builder(
                        builder: (context) {
                          final pendingCount =
                              workbench.pendingInvites.length;
                          final hasPending = pendingCount > 0;
                          final accentAmber = AppTheme.accentAmberFor(isDark);
                          return Tooltip(
                            message: hasPending
                                ? '$pendingCount pending invite(s) — Manage Team Access & Invites'
                                : 'Invite Users & Manage Team Access',
                            child: InkWell(
                              key: const ValueKey('team_invites_btn'),
                              onTap: () => showTeamInvitesDialog(context, workbench),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3.5,
                                ),
                                decoration: BoxDecoration(
                                  color: hasPending
                                      ? accentAmber.withValues(alpha: 0.14)
                                      : bgSurface,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: hasPending
                                        ? accentAmber.withValues(alpha: 0.55)
                                        : borderColor,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.person_add_alt_1_rounded,
                                      size: 11.5,
                                      color: hasPending
                                          ? accentAmber
                                          : textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      hasPending
                                          ? 'Invites · $pendingCount pending'
                                          : '+ Invite',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: hasPending
                                            ? accentAmber
                                            : textPrimary,
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
                    const SizedBox(width: 2),
                    Tooltip(
                      message: 'Toggle Theme',
                      child: InkWell(
                        onTap: workbench.toggleTheme,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Icon(
                            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                            size: 14,
                            color: textMuted,
                          ),
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
            );
          },
        ),
      );
  }

  PopupMenuItem<String> _buildExportMenuItem({
    Key? key,
    required String value,
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color textColor,
  }) {
    return PopupMenuItem<String>(
      key: key,
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
