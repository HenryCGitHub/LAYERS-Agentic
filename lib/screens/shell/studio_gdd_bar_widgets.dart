import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'gdd_inspector_dialog.dart';
import 'studio_export_actions.dart';

/// Top-bar pill for linking `*_copilot_gdd.md` to disk via File System Access API
/// (with download fallback on non-Chromium browsers).
class LocalGddLinkPill extends StatelessWidget {
  final WorkbenchProvider workbench;
  final bool isDark;

  const LocalGddLinkPill({
    super.key,
    required this.workbench,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final border = AppTheme.borderFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);
    final red = AppTheme.accentRedFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);

    final status = workbench.gddSyncStatus;
    final needsPerm = status == LocalGddSyncStatus.permissionNeeded;
    final isError = status == LocalGddSyncStatus.error;
    final isLinked = workbench.isLocalGddLinked;
    final hasLinkedFile = workbench.linkedGddFileName != null &&
        workbench.linkedGddFileName!.isNotEmpty;
    final fileName = workbench.linkedGddFileName ?? 'copilot_gdd.md';
    final compact = MediaQuery.sizeOf(context).width < 1280;

    final Color accentColor;
    final String labelText;
    final String tooltip;
    if (isError) {
      accentColor = red;
      labelText = compact ? 'GDD Error' : 'GDD Error · Retry';
      tooltip = workbench.gddSyncError ?? 'Local GDD sync error';
    } else if (needsPerm) {
      accentColor = amber;
      labelText = compact ? 'Grant GDD' : 'Grant GDD Write';
      tooltip = 'Re-authorize write access to local $fileName';
    } else if (isLinked) {
      accentColor = green;
      final shortName = fileName.length > 22 && compact
          ? '${fileName.substring(0, 19)}…'
          : fileName;
      labelText = '● Live · $shortName';
      tooltip =
          'Auto-syncing deltas locally to $fileName. Click to inspect GDD.';
    } else {
      accentColor = secondary;
      labelText = 'Link Local GDD';
      tooltip = workbench.isLocalGddLinkSupported
          ? 'Pick local *_copilot_gdd.md in your UE5 Content/Docs folder for delta-only auto-writes'
          : 'Download *_copilot_gdd.md (use Chrome/Edge/Arc for live disk auto-sync)';
    }
    final highlighted = isLinked || needsPerm || isError;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: const ValueKey('top_bar_link_local_gdd_btn'),
        borderRadius: BorderRadius.circular(5),
        onTap: () async {
          if (isError && hasLinkedFile) {
            await showGddInspectorDialog(context, workbench);
            return;
          }
          if (needsPerm) {
            await workbench.syncLinkedGddNow(
              force: true,
              requestPermissionIfNeeded: true,
            );
            return;
          }
          if (isLinked) {
            await showGddInspectorDialog(context, workbench);
            return;
          }
          final res = await workbench.linkLocalGddFile();
          if (!context.mounted) return;
          if (res.linked) {
            AppToast.show(
              context,
              'Live-linked ${res.filename ?? 'CoPilot GDD'}',
              isDark: isDark,
            );
          } else if (res.fellBackToDownload) {
            AppToast.show(
              context,
              'Downloaded ${res.filename ?? 'CoPilot GDD'}',
              isDark: isDark,
            );
          } else if (!res.cancelled && res.error != null) {
            AppToast.show(
              context,
              res.error!,
              isDark: isDark,
              accentColor: red,
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: highlighted
                ? accentColor.withValues(alpha: 0.11)
                : bgSurface,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: highlighted
                  ? accentColor.withValues(alpha: 0.48)
                  : border,
            ),
          ),
          child: Text(
            labelText,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: highlighted ? accentColor : primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Top-bar pill opening the heading-indexed CoPilot GDD Inspector modal.
class CoPilotGddInspectPill extends StatelessWidget {
  final WorkbenchProvider workbench;
  final bool isDark;

  const CoPilotGddInspectPill({
    super.key,
    required this.workbench,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 1140;
    final cyan = AppTheme.accentCyanFor(isDark);
    return Tooltip(
      message: 'Inspect CoPilot GDD (*_copilot_gdd.md), copy or download',
      child: InkWell(
        key: const ValueKey('top_bar_copilot_gdd_btn'),
        borderRadius: BorderRadius.circular(5),
        onTap: () => showGddInspectorDialog(context, workbench),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 6 : 8,
            vertical: 3.5,
          ),
          decoration: BoxDecoration(
            color: AppTheme.bgSurfaceFor(isDark),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: cyan.withValues(alpha: 0.45)),
          ),
          child: Text(
            isNarrow ? '⚡ GDD' : '⚡ Inspect GDD',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: cyan,
            ),
          ),
        ),
      ),
    );
  }
}

/// Extracted Export menu button preserving full Markdown & `.layers.json` export actions.
class StudioExportMenuButton extends StatelessWidget {
  final WorkbenchProvider workbench;
  final bool isDark;

  const StudioExportMenuButton({
    super.key,
    required this.workbench,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final border = AppTheme.borderFor(isDark);

    return PopupMenuButton<String>(
      key: const ValueKey('global_export_spec_btn'),
      tooltip:
          'Export CoPilot GDD, Human Spec (.md), or Vault Backup (.layers.json)',
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 340),
      color: bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: border),
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
        _item(
          value: 'copilot_gdd',
          icon: Icons.bolt_rounded,
          iconColor: AppTheme.accentCyanFor(isDark),
          label: 'Export CoPilot GDD (.md)',
          textColor: primary,
        ),
        _item(
          value: 'spec',
          icon: Icons.copy_rounded,
          iconColor: secondary,
          label: 'Copy Full Project Spec (.md)',
          textColor: primary,
        ),
        _item(
          value: 'json_export',
          icon: Icons.download_rounded,
          iconColor: secondary,
          label: 'Export Project Vault (.layers.json)',
          textColor: primary,
        ),
        _item(
          value: 'json_import',
          icon: Icons.file_upload_outlined,
          iconColor: secondary,
          label: 'Import Project Backup (.layers.json)',
          textColor: primary,
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          'Export ▾',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: muted,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _item({
    required String value,
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color textColor,
  }) {
    return PopupMenuItem<String>(
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
