import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'project_manage_dialogs.dart';
import 'studio_export_actions.dart';
import 'studio_gdd_bar_widgets.dart';

/// Flat 40px workstation top header (`LAYERS / [Project ▾]`, release links,
/// and strictly `GDD ▾` + `Settings ▾`).
class StudioTopBar extends StatelessWidget implements PreferredSizeWidget {
  final WorkbenchProvider workbench;

  static const String _actionNewProject = '__new_project__';
  static const String _actionExportJson = '__export_json__';
  static const String _actionImportJson = '__import_json__';
  static const String _prefixSwitch = 'switch_';
  static const String _prefixRename = 'rename_';
  static const String _prefixDuplicate = 'duplicate_';
  static const String _prefixDelete = 'delete_';

  const StudioTopBar({super.key, required this.workbench});

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  Widget build(BuildContext context) {
    final isDark = workbench.isDark;
    final bgBase = AppTheme.bgBaseFor(isDark);
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final borderSubtle = AppTheme.borderFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final savedProjects = workbench.savedProjects;
    final activeProj = workbench.activeProjectId != null
        ? savedProjects
              .where((p) => p.id == workbench.activeProjectId)
              .firstOrNull
        : null;
    final String? projTitle = activeProj?.title.trim();
    final String? draftIdea = workbench.conceptDraft?.normalizedTitle.trim();
    final String rawProjectName = (projTitle != null && projTitle.isNotEmpty)
        ? projTitle
        : ((draftIdea != null && draftIdea.isNotEmpty)
              ? draftIdea
              : 'New Game');
    final releases = workbench.projectReleases;

    return Material(
      color: bgBase,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: borderSubtle, width: 1)),
        ),
        child: LayoutBuilder(
        builder: (context, constraints) {
          final hideWordmark = constraints.maxWidth < 520;
          final compactTitleWidth = constraints.maxWidth < 720 ? 115.0 : 190.0;

          return Row(
            children: [
              if (!hideWordmark) ...[
                Text(
                  'LAYERS',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: textMuted,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '/',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      color: textMuted,
                    ),
                  ),
                ),
              ],
              PopupMenuButton<String>(
                key: const ValueKey('project_switcher_dropdown_btn'),
                tooltip: 'Switch Project or Start New Game',
                color: bgSurface,
                elevation: 4,
                surfaceTintColor: Colors.transparent,
                onSelected: (value) async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  if (value == _actionNewProject) {
                    workbench.createNewProject();
                    return;
                  }
                  if (value == _actionExportJson) {
                    await exportActiveProjectJson(context, workbench);
                    return;
                  }
                  if (value == _actionImportJson) {
                    showImportProjectJsonDialog(context, workbench);
                    return;
                  }
                  if (value.startsWith(_prefixSwitch)) {
                    workbench.switchProject(
                      value.substring(_prefixSwitch.length),
                    );
                  } else if (value.startsWith(_prefixRename)) {
                    final projId = value.substring(_prefixRename.length);
                    final proj = savedProjects
                        .where((p) => p.id == projId)
                        .firstOrNull;
                    if (proj != null) {
                      await promptRenameProjectDialog(
                        context,
                        workbench,
                        proj,
                      );
                    }
                  } else if (value.startsWith(_prefixDuplicate)) {
                    workbench.duplicateProject(
                      value.substring(_prefixDuplicate.length),
                    );
                  } else if (value.startsWith(_prefixDelete)) {
                    final projId = value.substring(_prefixDelete.length);
                    final proj = savedProjects
                        .where((p) => p.id == projId)
                        .firstOrNull;
                    if (proj != null) {
                      final confirmed = await confirmDeleteProjectDialog(
                        context,
                        workbench,
                        proj,
                      );
                      if (confirmed) {
                        workbench.deleteProject(proj.id);
                      }
                    }
                  }
                },
                itemBuilder: (ctx) {
                  return <PopupMenuEntry<String>>[
                    for (final p in savedProjects)
                      PopupMenuItem<String>(
                        value: '$_prefixSwitch${p.id}',
                        height: 34,
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: p.id == workbench.activeProjectId
                                    ? focal
                                    : Colors.transparent,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                p.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
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
                            Tooltip(
                              message: 'Rename Project',
                              child: InkWell(
                                key: ValueKey('switcher_rename_${p.id}'),
                                onTap: () =>
                                    Navigator.of(ctx).pop('$_prefixRename${p.id}'),
                                borderRadius: BorderRadius.circular(2),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.edit_outlined,
                                    size: 13.5,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Duplicate Project',
                              child: InkWell(
                                key: ValueKey('switcher_duplicate_${p.id}'),
                                onTap: () => Navigator.of(
                                  ctx,
                                ).pop('$_prefixDuplicate${p.id}'),
                                borderRadius: BorderRadius.circular(2),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.content_copy_rounded,
                                    size: 13.5,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Delete Project',
                              child: InkWell(
                                key: ValueKey('switcher_delete_${p.id}'),
                                onTap: () =>
                                    Navigator.of(ctx).pop('$_prefixDelete${p.id}'),
                                borderRadius: BorderRadius.circular(2),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 14,
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
                      height: 34,
                      child: Text(
                        '+ New Game',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: focal,
                        ),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      key: const ValueKey('switcher_export_project_json_item'),
                      value: _actionExportJson,
                      height: 32,
                      child: Text(
                        'Export Project (.layers.json)',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ),
                    PopupMenuItem<String>(
                      key: const ValueKey('switcher_import_project_json_item'),
                      value: _actionImportJson,
                      height: 32,
                      child: Text(
                        'Import Project (.json)…',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ),
                  ];
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: compactTitleWidth),
                        child: Text(
                          rawProjectName,
                          key: const ValueKey('top_bar_project_title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 15,
                        color: textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: releases.isEmpty
                    ? const SizedBox.shrink()
                    : Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < releases.length; i++) ...[
                                if (i > 0)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Text(
                                      '·',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        color: textMuted,
                                      ),
                                    ),
                                  ),
                                _HeaderReleaseLink(
                                  key: ValueKey(
                                    'header_release_${releases[i].id}',
                                  ),
                                  label:
                                      (releases[i].sections['release_version'] ??
                                              '')
                                          .trim()
                                          .isNotEmpty
                                      ? releases[i]
                                            .sections['release_version']!
                                            .trim()
                                      : releases[i].title,
                                  isCurrentRelease:
                                      releases[i].id ==
                                          workbench.activeReleaseId &&
                                      workbench.activeDocPage !=
                                          WorkbenchDocPage.planNextRelease,
                                  isReleaseSpecActive:
                                      releases[i].id ==
                                          workbench.activeReleaseId &&
                                      workbench.isInspectingReleaseSpec,
                                  isDark: isDark,
                                  onTap: () {
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    workbench.selectReleaseSpec(releases[i].id);
                                  },
                                ),
                              ],
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  '·',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                              InkWell(
                                key: const ValueKey('plan_next_release_btn'),
                                onTap: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  workbench.openInPagePlanNextRelease();
                                },
                                borderRadius: BorderRadius.circular(2),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    '+ New',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11.5,
                                      fontWeight:
                                          workbench.isPlanningNextRelease
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: workbench.isPlanningNextRelease
                                          ? focal
                                          : textSecondary,
                                      decoration: workbench.isPlanningNextRelease
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              StudioGddMenuButton(workbench: workbench, isDark: isDark),
              const SizedBox(width: 8),
              StudioSettingsMenuButton(workbench: workbench, isDark: isDark),
            ],
          );
        },
      ),
    ),
    );
  }
}

class _HeaderReleaseLink extends StatelessWidget {
  final String label;
  final bool isCurrentRelease;
  final bool isReleaseSpecActive;
  final bool isDark;
  final VoidCallback onTap;

  const _HeaderReleaseLink({
    super.key,
    required this.label,
    required this.isCurrentRelease,
    required this.isReleaseSpecActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11.5,
            fontWeight: isCurrentRelease ? FontWeight.w700 : FontWeight.w400,
            color: isCurrentRelease ? textPrimary : textMuted,
            decoration: isReleaseSpecActive
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationColor: textPrimary,
          ),
        ),
      ),
    );
  }
}
