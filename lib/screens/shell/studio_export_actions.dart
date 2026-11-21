import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/markdown_exporter.dart';
import 'project_manage_dialogs.dart';

/// Exports the complete Stage 1 + Stage 2 project markdown (`*_project_spec.md`).
Future<void> exportFullProjectSpec(BuildContext context, WorkbenchProvider workbench) async {
  final wb = workbench;
  final isDark = wb.isDark;
  final rootSpec = wb.conceptDraft;
  if (rootSpec == null || !rootSpec.hasSpec) {
    AppToast.show(
      context,
      'Draft a Stage 1 Project Spec first.',
      isDark: isDark,
      accentColor: AppTheme.accentRedFor(isDark),
    );
    return;
  }

  final bundle = wb.buildFullProjectMarkdownExport();
  await Clipboard.setData(ClipboardData(text: bundle.content));
  final downloaded = triggerMarkdownFileDownload(
    filename: bundle.filename,
    content: bundle.content,
  );
  if (!context.mounted) return;
  AppToast.show(
    context,
    downloaded
        ? 'Downloaded ${bundle.filename} & copied to clipboard'
        : 'Copied full PROJECT_SPEC.md to clipboard',
    isDark: isDark,
  );
}

/// Exports a portable `.layers.json` backup of the active project tree.
Future<void> exportActiveProjectJson(BuildContext context, WorkbenchProvider workbench) async {
  final wb = workbench;
  final isDark = wb.isDark;
  final rawJson = wb.exportProjectToJson();
  if (rawJson.isEmpty) {
    AppToast.show(
      context,
      'No active project to export.',
      isDark: isDark,
      accentColor: AppTheme.accentRedFor(isDark),
    );
    return;
  }
  final projTitle = sanitizeExportSlug(
    wb.activeProject?.title ?? 'layers_project',
    fallback: 'layers_project',
  );
  final filename = '$projTitle.layers.json';
  await Clipboard.setData(ClipboardData(text: rawJson));
  final downloaded = triggerMarkdownFileDownload(
    filename: filename,
    content: rawJson,
  );
  if (!context.mounted) return;
  AppToast.show(
    context,
    downloaded
        ? 'Downloaded $filename & copied JSON'
        : 'Copied .layers.json backup to clipboard',
    isDark: isDark,
  );
}

Future<void> showImportProjectJsonDialog(BuildContext context, WorkbenchProvider workbench) async {
  final wb = workbench;
  final isDark = wb.isDark;
  final primary = AppTheme.textPrimaryFor(isDark);
  final muted = AppTheme.textMutedFor(isDark);

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      return DisposableTextControllerScope(
        builder: (dialogCtx, controller) => AlertDialog(
          backgroundColor: AppTheme.bgSurfaceRaisedFor(isDark),
          title: Text('Import .layers.json Backup', style: TextStyle(color: primary)),
          content: SizedBox(
            width: 480,
            child: TextField(
              controller: controller,
              maxLines: 8,
              style: GoogleFonts.jetBrainsMono(fontSize: 12, color: primary),
              decoration: InputDecoration(
                hintText: 'Paste exported .layers.json contents here...',
                hintStyle: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final importedId = wb.importProjectFromJson(controller.text);
                if (importedId != null) {
                  Navigator.of(dialogCtx).pop();
                  AppToast.show(
                    context,
                    'Imported project cleanly.',
                    isDark: isDark,
                  );
                } else {
                  AppToast.show(
                    dialogCtx,
                    'Invalid .layers.json payload.',
                    isDark: isDark,
                    accentColor: AppTheme.accentRedFor(isDark),
                  );
                }
              },
              child: const Text('Import Project'),
            ),
          ],
        ),
      );
    },
  );
}
