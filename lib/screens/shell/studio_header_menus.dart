import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/unreal_architecture_mode.dart';
import '../../providers/workbench_provider.dart';
import '../../services/local_gdd_sync_service.dart';
import '../../theme/app_theme.dart';
import 'cloud_ai_settings_dialog.dart';
import 'gdd_inspector_dialog.dart';
import 'studio_export_actions.dart';
import 'team_invites_dialog.dart';

MenuStyle _flatMenuStyle(bool isDark) {
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll(AppTheme.bgPanelFor(isDark)),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(4),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: BorderSide(color: AppTheme.borderBrightFor(isDark)),
      ),
    ),
  );
}

/// Top-right `GDD ▾` dropdown menu backed by [LocalGddSyncService] and spec exports.
class StudioGddMenuButton extends StatelessWidget {
  final WorkbenchProvider workbench;
  final bool isDark;

  const StudioGddMenuButton({
    super.key,
    required this.workbench,
    required this.isDark,
  });

  void _showSnack(BuildContext context, String msg, {bool isError = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        backgroundColor: isError ? const Color(0xFFDC2626) : null,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleLocalGddAction(
    BuildContext context,
    LocalGddSyncStatus status,
  ) async {
    switch (status) {
      case LocalGddSyncStatus.unlinked:
      case LocalGddSyncStatus.fallbackDownloaded:
        final res = await workbench.linkLocalGddFile();
        if (!context.mounted) return;
        if (res.fellBackToDownload) {
          _showSnack(
            context,
            'Downloaded ${res.filename ?? "GDD"} (live auto-sync requires Chrome/Edge).',
          );
        } else if (res.error != null && res.error!.trim().isNotEmpty) {
          _showSnack(context, res.error!, isError: true);
        } else if (res.linked) {
          _showSnack(context, 'Linked live to ${res.filename ?? "GDD"}');
        }
        return;
      case LocalGddSyncStatus.permissionNeeded:
        final ok = await workbench.syncLinkedGddNow(
          force: true,
          requestPermissionIfNeeded: true,
        );
        if (context.mounted && ok) {
          _showSnack(
            context,
            'Synced ${workbench.linkedGddFileName ?? "local GDD"}',
          );
        }
        return;
      case LocalGddSyncStatus.error:
        final hasFile =
            workbench.linkedGddFileName != null &&
            workbench.linkedGddFileName!.isNotEmpty;
        if (hasFile) {
          final ok = await workbench.syncLinkedGddNow(
            force: true,
            requestPermissionIfNeeded: true,
          );
          if (context.mounted && ok) {
            _showSnack(
              context,
              'Synced ${workbench.linkedGddFileName ?? "local GDD"}',
            );
          }
        } else {
          final res = await workbench.linkLocalGddFile();
          if (context.mounted &&
              res.error != null &&
              res.error!.trim().isNotEmpty) {
            _showSnack(context, res.error!, isError: true);
          }
        }
        return;
      case LocalGddSyncStatus.linked:
      case LocalGddSyncStatus.syncing:
      case LocalGddSyncStatus.synced:
        final ok = await workbench.syncLinkedGddNow(force: true);
        if (context.mounted && ok) {
          _showSnack(
            context,
            'Synced ${workbench.linkedGddFileName ?? "local GDD"}',
          );
        }
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = workbench.gddSyncStatus;
    final linkedFile = workbench.linkedGddFileName;
    final hasFile = linkedFile != null && linkedFile.isNotEmpty;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);
    final red = AppTheme.accentRedFor(isDark);

    Color? dotColor;
    String triggerLabel = 'GDD ▾';
    Color labelColor = textSecondary;

    switch (status) {
      case LocalGddSyncStatus.linked:
      case LocalGddSyncStatus.syncing:
      case LocalGddSyncStatus.synced:
        dotColor = green;
        triggerLabel = 'GDD ▾';
        labelColor = textPrimary;
      case LocalGddSyncStatus.permissionNeeded:
        dotColor = amber;
        triggerLabel = 'Grant GDD ▾';
        labelColor = amber;
      case LocalGddSyncStatus.error:
        dotColor = red;
        triggerLabel = 'GDD Error ▾';
        labelColor = red;
      case LocalGddSyncStatus.unlinked:
      case LocalGddSyncStatus.fallbackDownloaded:
        dotColor = null;
        triggerLabel = 'GDD ▾';
    }

    final primaryActionLabel = switch (status) {
      LocalGddSyncStatus.unlinked ||
      LocalGddSyncStatus.fallbackDownloaded => 'Link Local GDD…',
      LocalGddSyncStatus.permissionNeeded => 'Grant GDD Write Permission',
      LocalGddSyncStatus.error => 'Retry Local GDD Sync',
      LocalGddSyncStatus.linked ||
      LocalGddSyncStatus.syncing ||
      LocalGddSyncStatus.synced => 'Sync Linked GDD Now',
    };

    return MenuAnchor(
      style: _flatMenuStyle(isDark),
      menuChildren: [
        if (hasFile ||
            (status == LocalGddSyncStatus.error &&
                workbench.gddSyncError != null))
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasFile)
                    Text(
                      status == LocalGddSyncStatus.syncing
                          ? 'Syncing $linkedFile…'
                          : 'File: $linkedFile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        color: textMuted,
                      ),
                    ),
                  if (status == LocalGddSyncStatus.error &&
                      workbench.gddSyncError != null &&
                      workbench.gddSyncError!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        workbench.gddSyncError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: red),
                      ),
                    ),
                ],
              ),
            ),
          ),
        MenuItemButton(
          key: const ValueKey('top_bar_link_local_gdd_btn'),
          onPressed: () => _handleLocalGddAction(context, status),
          child: Text(
            primaryActionLabel,
            style: TextStyle(fontSize: 12, color: textPrimary),
          ),
        ),
        if (workbench.isLocalGddLinked ||
            status == LocalGddSyncStatus.permissionNeeded ||
            (status == LocalGddSyncStatus.error && hasFile))
          MenuItemButton(
            key: const ValueKey('gdd_menu_unlink_btn'),
            onPressed: () => workbench.unlinkLocalGddFile(),
            child: Text(
              'Unlink Local GDD',
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
          ),
        const Divider(height: 8),
        MenuItemButton(
          key: const ValueKey('top_bar_copilot_gdd_btn'),
          onPressed: () {
            if (workbench.conceptDraft == null) {
              _showSnack(context, 'Draft a Stage 1 Project Spec first.');
              return;
            }
            showGddInspectorDialog(context, workbench);
          },
          child: Text(
            'Inspect GDD…',
            style: TextStyle(fontSize: 12, color: textPrimary),
          ),
        ),
        MenuItemButton(
          key: const ValueKey('gdd_menu_copy_copilot_btn'),
          onPressed: () => exportCoPilotGdd(context, workbench),
          child: Text(
            'Copy CoPilot GDD (MD)',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ),
        MenuItemButton(
          key: const ValueKey('gdd_menu_copy_full_btn'),
          onPressed: () => exportFullProjectSpec(context, workbench),
          child: Text(
            'Copy Full Spec (MD)',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ),
        MenuItemButton(
          key: const ValueKey('gdd_menu_export_json_btn'),
          onPressed: () => exportActiveProjectJson(context, workbench),
          child: Text(
            'Export Project (.layers.json)',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ),
        MenuItemButton(
          key: const ValueKey('gdd_menu_import_json_btn'),
          onPressed: () => showImportProjectJsonDialog(context, workbench),
          child: Text(
            'Import Project (.json)…',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ),
      ],
      builder: (context, controller, child) {
        return Tooltip(
          message: controller.isOpen
              ? ''
              : (hasFile
                    ? 'Local GDD · $linkedFile'
                    : 'Local GDD Auto-Sync & Exports'),
          child: InkWell(
            key: const ValueKey('header_gdd_menu_btn'),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            borderRadius: BorderRadius.circular(2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dotColor != null) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    triggerLabel,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Top-right `Settings ▾` dropdown housing Architecture Mode, Theme, Cloud Vault,
/// Team Invites, AI Model routing, and Session Token usage/reset.
class StudioSettingsMenuButton extends StatelessWidget {
  final WorkbenchProvider workbench;
  final bool isDark;

  const StudioSettingsMenuButton({
    super.key,
    required this.workbench,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final isBlueprint =
        workbench.unrealArchitectureMode == UnrealArchitectureMode.blueprint;

    return MenuAnchor(
      style: _flatMenuStyle(isDark),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Text(
            'UE5 ARCHITECTURE',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: textMuted,
            ),
          ),
        ),
        MenuItemButton(
          key: const ValueKey('settings_arch_blueprint'),
          onPressed: () =>
              workbench.setArchitectureMode(UnrealArchitectureMode.blueprint),
          trailingIcon: isBlueprint
              ? Icon(Icons.check, size: 14, color: focal)
              : null,
          child: Text(
            'Blueprint-First',
            style: TextStyle(fontSize: 12, color: textPrimary),
          ),
        ),
        MenuItemButton(
          key: const ValueKey('settings_arch_cpp_hybrid'),
          onPressed: () =>
              workbench.setArchitectureMode(UnrealArchitectureMode.cppHybrid),
          trailingIcon: !isBlueprint
              ? Icon(Icons.check, size: 14, color: focal)
              : null,
          child: Text(
            'C++ & BP Hybrid',
            style: TextStyle(fontSize: 12, color: textPrimary),
          ),
        ),
        const Divider(height: 8),
        Tooltip(
          message: 'Toggle Theme',
          preferBelow: false,
          waitDuration: const Duration(milliseconds: 600),
          child: MenuItemButton(
            key: const ValueKey('settings_theme_toggle_btn'),
            closeOnActivate: false,
            onPressed: workbench.toggleTheme,
            child: Text(
              isDark
                  ? 'Theme: Dark (Switch to Light)'
                  : 'Theme: Light (Switch to Dark)',
              style: TextStyle(fontSize: 12, color: textPrimary),
            ),
          ),
        ),
        MenuItemButton(
          key: const ValueKey('cloud_sync_auth_btn'),
          onPressed: () => showCloudSyncDialog(context, workbench),
          child: Text(
            workbench.isCloudSynced
                ? 'Cloud Vault (${workbench.userEmail ?? "Connected"})…'
                : 'Cloud Vault (Offline)…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: textPrimary),
          ),
        ),
        if (workbench.isAdminUser)
          MenuItemButton(
            key: const ValueKey('team_invites_btn'),
            onPressed: () => showTeamInvitesDialog(context, workbench),
            child: Text(
              'Team & Invites (${workbench.pendingInvites.length})…',
              style: TextStyle(fontSize: 12, color: textPrimary),
            ),
          ),
        const Divider(height: 8),
        Tooltip(
          message:
              'Active AI Models: ${workbench.activeModelIndicatorLabel} · Architect ${workbench.planningModel} · Refine ${workbench.conversationModel} (thinking: ${workbench.thinkingLevel})'
              '${workbench.activeModelIndicatorLabel.contains('Fallback') && workbench.aiFallbackReason != null ? '\nFallback reason: ${workbench.aiFallbackReason}' : ''}',
          child: MenuItemButton(
            key: const ValueKey('active_model_indicator_pill'),
            closeOnActivate: false,
            onPressed: () {
              final messenger = ScaffoldMessenger.maybeOf(context);
              if (messenger == null) return;
              messenger.clearSnackBars();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Models · Planner: ${workbench.planningModel} · Refine: ${workbench.conversationModel} (${workbench.thinkingLevel})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: Text(
              'AI: ${workbench.activeModelIndicatorLabel} · ${workbench.planningModel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: textSecondary,
              ),
            ),
          ),
        ),
        MenuItemButton(
          key: const ValueKey('token_usage_tracker_pill'),
          closeOnActivate: false,
          onPressed: workbench.resetTokenUsage,
          child: Text(
            'Usage: ${workbench.tokenUsageCompactLabel} · Reset',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: textSecondary,
            ),
          ),
        ),
      ],
      builder: (context, controller, child) {
        return InkWell(
          key: const ValueKey('header_settings_menu_btn'),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          borderRadius: BorderRadius.circular(2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text(
              'Settings ▾',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textSecondary,
              ),
            ),
          ),
        );
      },
    );
  }
}
