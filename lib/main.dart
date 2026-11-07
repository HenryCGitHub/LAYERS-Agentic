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
    final bp = workbench.releaseBlueprint;
    final rel = workbench.activeRelease;

    int totalFeatCount = 0;
    int doneFeatCount = 0;
    int activeTotalCount = 0;
    int activeDoneCount = 0;

    for (final b in workbench.activeReleaseBeats) {
      for (final f in workbench.featuresForBeat(b.id)) {
        totalFeatCount++;
        final isDone = workbench.getDocumentProgress(f.id) >= 100;
        if (isDone) doneFeatCount++;
        if (workbench.isFeatureActiveInRelease(f)) {
          activeTotalCount++;
          if (isDone) activeDoneCount++;
        }
      }
    }

    final int targetTotal = activeTotalCount > 0 ? activeTotalCount : totalFeatCount;
    final int targetDone = activeTotalCount > 0 ? activeDoneCount : doneFeatCount;

    final String? stage1Badge = draft != null ? '✓' : null;
    final String? stage3Badge = targetTotal > 0
        ? '$targetDone/$targetTotal'
        : (rel != null ? '${workbench.getDocumentProgress(rel.id)}%' : null);

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
                            SizedBox(
                              width: 1,
                              height: 1,
                              child: Opacity(
                                opacity: 0,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${workbench.activeReleaseVersionTag} · ${workbench.releaseDisplayName(workbench.activeRelease!)}',
                                    ),
                                    Text(
                                      '${workbench.getDocumentProgress(workbench.activeRelease!.id)}%',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(
                width: 1,
                height: 1,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Opacity(
                    opacity: 0,
                    child: Container(
                      key: const ValueKey('connected_pipeline_track'),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildStagePill(
                            label: '1. Concept',
                            badge: stage1Badge,
                            stage: WorkbenchStage.projectPitch,
                            isCompleted: bp != null || totalFeatCount > 0,
                            onTap: () => workbench.setStage(WorkbenchStage.projectPitch),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '▸',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: textMuted,
                              ),
                            ),
                          ),
                          _buildStagePill(
                            label: '2. Workbench',
                            badge: stage3Badge,
                            stage: WorkbenchStage.releaseWorkbench,
                            isCompleted: workbench.isActiveReleaseComplete,
                            onTap: workbench.activeReleaseBeats.isNotEmpty
                                ? () => workbench.setStage(WorkbenchStage.releaseWorkbench)
                                : (workbench.conceptDraft != null && !workbench.isAgentBusy
                                    ? () => workbench.approveConceptAndBuildRelease()
                                    : null),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                            }
                          },
                          itemBuilder: (ctx) => [
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
                        const SizedBox.shrink(
                          key: ValueKey('global_export_agents_md_btn'),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Tooltip(
                        message: workbench.isCloudSynced
                            ? 'Synced to Firebase Cloud (${workbench.userEmail ?? "Signed In"})'
                            : 'Project Vault & Google Cloud Sync',
                        child: InkWell(
                          key: const ValueKey('cloud_sync_auth_btn'),
                          onTap: () => _showCloudSyncDialog(context),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Icon(
                              workbench.isCloudSynced
                                  ? Icons.cloud_done_rounded
                                  : Icons.cloud_upload_outlined,
                              size: 14,
                              color: workbench.isCloudSynced ? textPrimary : textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Gemini 3.8 Flash Session Token Usage:\n'
                            '• Input: ${workbench.totalInputTokens} tokens (\$0.75 / 1M)\n'
                            '• Output: ${workbench.totalOutputTokens} tokens (\$3.75 / 1M inc. reasoning)\n'
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
                      const SizedBox(width: 2),
                      Tooltip(
                        message: workbench.aiLastErrorStatus != null
                            ? 'AI API Key Notice (${workbench.aiLastErrorStatus}) — Click to update key'
                            : 'AI Model Routing & API Key Settings',
                        child: InkWell(
                          key: const ValueKey('ai_settings_btn'),
                          onTap: () => _showAiSettingsDialog(context),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Icon(
                              Icons.tune_rounded,
                              size: 13.5,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ),
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
      body: Column(
        children: [
          if (workbench.isOffline)
            Container(
              key: const ValueKey('global_offline_banner'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.accentRedFor(isDark).withValues(alpha: 0.14),
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.accentRedFor(isDark).withValues(alpha: 0.45),
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
                  InkWell(
                    key: const ValueKey('offline_banner_settings_btn'),
                    onTap: () => _showAiSettingsDialog(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: bgSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: borderColor),
                      ),
                      child: Text(
                        'AI Settings',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
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
    );
  }

  Widget _buildStagePill({
    required String label,
    String? badge,
    required WorkbenchStage stage,
    required bool isCompleted,
    VoidCallback? onTap,
  }) {
    final isDark = workbench.isDark;
    final isActive = stage == workbench.currentStage;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTheme.displayFont(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.1,
                color: isActive
                    ? textPrimary
                    : (isCompleted ? textSecondary : textMuted),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Text(
                badge,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? textPrimary : textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveStageBody() {
    return ReleaseWorkbenchScreen(workbench: workbench);
  }
}
