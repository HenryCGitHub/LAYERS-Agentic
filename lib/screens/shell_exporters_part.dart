part of '../main.dart';

extension _WorkbenchShellExporters on WorkbenchShell {
  /// Exports the complete Stage 1 + Stage 2 project markdown (`PROJECT_SPEC.md`).
  Future<void> _exportFullProjectSpec(BuildContext context) async {
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

    final releases = wb.projectReleases;
    final epicsByRelease = <String, List<EpicSpec>>{};
    for (final rel in releases) {
      epicsByRelease[wb.releaseDisplayName(rel)] = wb.epicsForRelease(rel.id);
    }

    final md = UnrealMcpPayloadBuilder.buildFullProjectSpecMarkdown(
      rootSpec: rootSpec,
      epicsByReleaseLabel: epicsByRelease,
    );

    final safeSlug = rootSpec.normalizedTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final filename =
        '${safeSlug.isEmpty ? 'layers' : safeSlug}_project_spec.md';

    await Clipboard.setData(ClipboardData(text: md));
    final downloaded = triggerMarkdownFileDownload(
      filename: filename,
      content: md,
    );
    if (!context.mounted) return;
    AppToast.show(
      context,
      downloaded
          ? 'Downloaded $filename & copied to clipboard'
          : 'Copied full PROJECT_SPEC.md to clipboard',
      isDark: isDark,
    );
  }

  /// Exports the active Release (`ROOT_MCP_CONTEXT` + all active Epic payloads).
  Future<void> _exportActiveReleaseAgentsMd(BuildContext context) async {
    final wb = workbench;
    final isDark = wb.isDark;
    final rootSpec = wb.conceptDraft;
    if (rootSpec == null) {
      AppToast.show(
        context,
        'Create a Project Spec first.',
        isDark: isDark,
        accentColor: AppTheme.accentRedFor(isDark),
      );
      return;
    }
    final rel = wb.activeRelease;
    final releaseLabel =
        rel != null ? wb.releaseDisplayName(rel) : 'v0.1 · Prototype';
    final md = UnrealMcpPayloadBuilder.buildReleaseMcpBundle(
      rootSpec: rootSpec,
      releaseLabel: releaseLabel,
      releaseEpics: wb.activeReleaseEpics,
      liveUprojectContext: wb.latestLiveUprojectContext,
    );

    final filename =
        'unreal_mcp_release_${wb.activeReleaseVersionTag.replaceAll('.', '_')}.md';
    await Clipboard.setData(ClipboardData(text: md));
    final downloaded = triggerMarkdownFileDownload(
      filename: filename,
      content: md,
    );
    if (!context.mounted) return;
    AppToast.show(
      context,
      downloaded
          ? 'Downloaded $filename & copied to clipboard'
          : 'Copied active Release MCP bundle to clipboard',
      isDark: isDark,
    );
  }

  /// Exports a portable `.layers.json` backup of the active project tree.
  Future<void> _exportActiveProjectJson(BuildContext context) async {
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
    final projTitle = (wb.activeProject?.title ?? 'layers_project')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
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

  Future<void> _showImportProjectJsonDialog(BuildContext context) async {
    final wb = workbench;
    final controller = TextEditingController();
    final isDark = wb.isDark;
    final primary = AppTheme.textPrimaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
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
        );
      },
    );
    controller.dispose();
  }
}
