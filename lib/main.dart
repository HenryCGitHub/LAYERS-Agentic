import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'models/feature_state.dart';
import 'models/tier_document.dart';
import 'providers/workbench_provider.dart';
import 'screens/release_workbench_screen.dart';
import 'screens/widgets/godot_workbench_modals.dart';
import 'theme/app_theme.dart';
import 'utils/markdown_exporter.dart';

part 'screens/shell_exporters_part.dart';
part 'screens/shell_dialogs_part.dart';

const String _actionNewProject = '__new_project__';
const String _actionExportJson = '__export_json__';
const String _actionImportJson = '__import_json__';
const String _prefixRename = '__rename__:';
const String _prefixDuplicate = '__duplicate__:';
const String _prefixDelete = '__delete__:';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }
  runApp(const LayersAgenticApp());
}

class LayersAgenticApp extends StatelessWidget {
  final WorkbenchProvider? provider;

  const LayersAgenticApp({super.key, this.provider});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<WorkbenchProvider>(
      create: (_) => provider ?? WorkbenchProvider(enableAutoLoad: true),
      child: Consumer<WorkbenchProvider>(
        builder: (context, workbench, _) {
          final isDark = workbench.isDark;
          return MaterialApp(
            title: 'LAYERS-Agentic',
            debugShowCheckedModeBanner: false,
            theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: WorkbenchShell(workbench: workbench),
          );
        },
      ),
    );
  }
}

class WorkbenchShell extends StatelessWidget {
  final WorkbenchProvider workbench;

  const WorkbenchShell({super.key, required this.workbench});

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
    final draftIdea = draft?.sparkIdea.trim();
    final String? rawSpark = (projTitle != null && projTitle.isNotEmpty)
        ? projTitle
        : ((draftIdea != null && draftIdea.isNotEmpty) ? draftIdea : null);
    final String? activeProjectLabel = (rawSpark != null && rawSpark.isNotEmpty)
        ? (rawSpark.length > 22 ? '${rawSpark.substring(0, 22)}…' : rawSpark)
        : null;
    final savedProjects = workbench.savedProjects;

    return Scaffold(
      backgroundColor: AppTheme.bgCanvasFor(isDark),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(50),
        child: Container(
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
                        await _exportActiveProjectJson(context);
                      } else if (val == _actionImportJson) {
                        await _showImportProjectJsonDialog(context);
                      } else if (val.startsWith(_prefixRename)) {
                        final projId = val.substring(_prefixRename.length);
                        final proj = savedProjects.where((p) => p.id == projId).firstOrNull;
                        if (proj == null) return;
                        await _promptRenameProjectDialog(context, proj);
                      } else if (val.startsWith(_prefixDuplicate)) {
                        final projId = val.substring(_prefixDuplicate.length);
                        workbench.duplicateProject(projId);
                      } else if (val.startsWith(_prefixDelete)) {
                        final projId = val.substring(_prefixDelete.length);
                        workbench.deleteProject(projId);
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
                            Text(
                              '+ New Project',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
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
                            Text(
                              'Export Project (.json)',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: textSecondary,
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
                            Text(
                              'Import Project (.json)',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: textSecondary,
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
                              '${workbench.activeReleaseVersionTag} · ${workbench.releaseConciseLabel(workbench.activeRelease!)} ▾',
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
                        PopupMenuButton<String>(
                          key: const ValueKey('global_export_spec_btn'),
                          tooltip:
                              'Export Project Spec or AI Coding Agent Context (AGENTS.md)',
                          color: bgSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(color: borderColor),
                          ),
                          onSelected: (val) {
                            if (val == 'spec') {
                              _exportFullProjectSpec(context);
                            } else if (val == 'agents_md') {
                              _exportActiveReleaseAgentsMd(context);
                            } else if (val == 'godot_files') {
                              showGodotFilesAndSyncDialog(context, workbench);
                            } else if (val == 'godot_contract') {
                              showGodotContractDialog(context, workbench);
                            } else if (val == 'json_export') {
                              _exportActiveProjectJson(context);
                            } else if (val == 'json_import') {
                              _showImportProjectJsonDialog(context);
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem<String>(
                              value: 'godot_files',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.folder_copy_outlined,
                                    size: 13,
                                    color: Color(0xFF38BDF8),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Godot Files, Cloud & Folder Sync',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'godot_contract',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.tune_rounded,
                                    size: 13,
                                    color: textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Godot 4 Project Contract',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'spec',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.copy_rounded,
                                    size: 13,
                                    color: textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Copy Full Project Spec (.md)',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'agents_md',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.terminal_rounded,
                                    size: 13,
                                    color: textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Export AI Agent Context (AGENTS.md)',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'json_export',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.download_rounded,
                                    size: 13,
                                    color: textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Export Project Vault (.layers.json)',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'json_import',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.file_upload_outlined,
                                    size: 13,
                                    color: textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Import Project Backup (.layers.json)',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
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
                              onTap: () => _showCloudSyncDialog(context),
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
                                onTap: () => _showTeamInvitesDialog(context),
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
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (workbench.isOffline)
                Container(
                  key: const ValueKey('global_offline_banner'),
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        AppTheme.accentRedFor(isDark).withValues(alpha: 0.14),
                    border: Border(
                      bottom: BorderSide(
                        color: AppTheme.accentRedFor(isDark)
                            .withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 15,
                        color: AppTheme.accentRedFor(isDark),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          workbench.offlineErrorMessage ??
                              'App is offline — Unable to reach Gemini AI.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!workbench.isUserLoggedIn) ...[
                        InkWell(
                          key: const ValueKey(
                              'offline_banner_google_signin_btn'),
                          onTap: () => workbench.signInWithGoogle(),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentGreenFor(isDark)
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppTheme.accentGreenFor(isDark)
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                            child: Text(
                              'Sign in with Google',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentGreenFor(isDark),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      InkWell(
                        key: const ValueKey('offline_banner_dismiss_btn'),
                        onTap: workbench.clearOfflineError,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: _buildActiveStageBody()),
            ],
          ),
          if (workbench.hasPendingInviteLanding)
            Container(
              key: const ValueKey('invite_acceptance_overlay'),
              color: Colors.black.withValues(alpha: 0.68),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: bgSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.borderBrightFor(isDark),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'LAYERS-AGENTIC INVITE',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                          InkWell(
                            key: const ValueKey('dismiss_invite_overlay_btn'),
                            onTap: workbench.dismissPendingUrlInvite,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 15,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "You've been invited to join LAYERS-Agentic",
                        style: AppTheme.displayFont(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        workbench.pendingUrlInvitedEmail != null &&
                                workbench.pendingUrlInvitedEmail!.isNotEmpty
                            ? 'Accept your invite using your Google account (${workbench.pendingUrlInvitedEmail}) to unlock Cloud Sync and Gemini 4 Hydrogen.'
                            : 'Accept your invite by signing in with your invited Google account to unlock Cloud Sync and Gemini 4 Hydrogen.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.45,
                          color: textSecondary,
                        ),
                      ),
                      if (workbench.inviteFeedbackMessage != null &&
                          workbench.inviteFeedbackMessage!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.accentAmberFor(isDark)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppTheme.accentAmberFor(isDark)
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            workbench.inviteFeedbackMessage!,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              height: 1.35,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: const ValueKey('accept_invite_google_btn'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: const Color(0xFF06281E),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: () =>
                              workbench.acceptPendingInviteWithGoogle(),
                          icon: const Icon(Icons.verified_user_rounded,
                              size: 16),
                          label: Text(
                            'Accept Invite & Sign in with Google →',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveStageBody() {
    return ReleaseWorkbenchScreen(workbench: workbench);
  }
}
