import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/unreal_prompt_compactor.dart';
import 'studio_export_actions.dart';

/// Opens the Flight Deck GDD Inspector showing `*_copilot_gdd.md`,
/// local file link status, copy, and download controls.
Future<void> showGddInspectorDialog(
  BuildContext context,
  WorkbenchProvider workbench,
) async {
  final rootSpec = workbench.conceptDraft;
  if (rootSpec == null || !rootSpec.hasSpec) {
    AppToast.show(
      context,
      'Draft a Stage 1 Project Spec first.',
      isDark: workbench.isDark,
      accentColor: AppTheme.accentRedFor(workbench.isDark),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => AnimatedBuilder(
      animation: workbench,
      builder: (dialogCtx, _) {
        final isDark = workbench.isDark;
        final border = AppTheme.borderFor(isDark);
        final primary = AppTheme.textPrimaryFor(isDark);
        final muted = AppTheme.textMutedFor(isDark);
        final cyan = AppTheme.accentCyanFor(isDark);
        final green = AppTheme.accentGreenFor(isDark);
        final amber = AppTheme.accentAmberFor(isDark);
        final red = AppTheme.accentRedFor(isDark);

        final bundle = workbench.buildCoPilotGddExport();
        final tokens = UnrealPromptCompactor.estimateTokens(bundle.content);
        final isLinked = workbench.isLocalGddLinked;
        final needsPerm =
            workbench.gddSyncStatus == LocalGddSyncStatus.permissionNeeded;
        final isError = workbench.gddSyncStatus == LocalGddSyncStatus.error;
        final linkedName = workbench.linkedGddFileName;
        final hasLinkedFile = linkedName != null && linkedName.isNotEmpty;
        final errorLabel = workbench.gddSyncError ?? 'Local GDD write failed.';

        return Dialog(
          key: const ValueKey('gdd_inspector_dialog'),
          backgroundColor: AppTheme.bgPanelFor(isDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(2),
            side: BorderSide(color: border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 18, color: cyan),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CoPilot GDD Inspector · ${bundle.filename}',
                              style: AppTheme.displayFont(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: primary,
                              ),
                            ),
                            Text(
                              'Compiled locally in memory (0 AI tokens spent by LAYERS)',
                              style: TextStyle(fontSize: 11.5, color: muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('close_gdd_inspector_btn'),
                        tooltip: 'Close GDD Inspector',
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        icon: Icon(Icons.close, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border(bottom: BorderSide(color: border)),
                        ),
                        child: Text(
                          'Paste size: ~$tokens tok',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cyan,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isError
                              ? red.withValues(alpha: 0.12)
                              : (needsPerm
                                  ? amber.withValues(alpha: 0.12)
                                  : (isLinked
                                      ? green.withValues(alpha: 0.12)
                                      : AppTheme.bgSurfaceRecessedFor(isDark))),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(
                            color: isError
                                ? red.withValues(alpha: 0.45)
                                : (needsPerm
                                    ? amber.withValues(alpha: 0.45)
                                    : (isLinked
                                        ? green.withValues(alpha: 0.45)
                                        : border)),
                          ),
                        ),
                        child: Text(
                          isError
                              ? (hasLinkedFile
                                  ? 'Sync error ($linkedName): $errorLabel'
                                  : 'Sync error: $errorLabel')
                              : (needsPerm
                                  ? 'Permission needed: $linkedName'
                                  : (isLinked
                                      ? 'Live · $linkedName'
                                      : 'Not linked to local disk yet')),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isError
                                ? red
                                : (needsPerm
                                    ? amber
                                    : (isLinked ? green : muted)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.bgBaseFor(isDark),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: border),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          bundle.content,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11.5,
                            height: 1.45,
                            color: primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (needsPerm)
                        OutlinedButton.icon(
                          key: const ValueKey('gdd_inspector_grant_perm_btn'),
                          onPressed: () async {
                            await workbench.syncLinkedGddNow(
                              force: true,
                              requestPermissionIfNeeded: true,
                            );
                          },
                          icon: Icon(Icons.lock_open_rounded,
                              size: 14, color: amber),
                          label: const Text('Grant Write Permission'),
                        ),
                      if (isError && hasLinkedFile)
                        OutlinedButton.icon(
                          key: const ValueKey('gdd_inspector_retry_btn'),
                          onPressed: () async {
                            await workbench.syncLinkedGddNow(force: true);
                          },
                          icon: Icon(Icons.refresh_rounded,
                              size: 14, color: red),
                          label: const Text('Retry Sync'),
                        ),
                      if (isLinked || needsPerm || isError)
                        OutlinedButton.icon(
                          key: const ValueKey('gdd_inspector_unlink_btn'),
                          onPressed: () => workbench.unlinkLocalGddFile(),
                          icon: const Icon(Icons.link_off_rounded, size: 14),
                          label: const Text('Unlink Local File'),
                        ),
                      if (!isLinked && !needsPerm && !(isError && hasLinkedFile))
                        OutlinedButton.icon(
                          key: const ValueKey('gdd_inspector_link_btn'),
                          onPressed: () async {
                            final res = await workbench.linkLocalGddFile();
                            if (!dialogCtx.mounted) return;
                            if (res.linked) {
                              AppToast.show(
                                dialogCtx,
                                'Linked ${res.filename ?? bundle.filename}',
                                isDark: isDark,
                              );
                            } else if (res.fellBackToDownload) {
                              AppToast.show(
                                dialogCtx,
                                'Downloaded ${bundle.filename} (browser lacks file-link API)',
                                isDark: isDark,
                              );
                            } else if (!res.cancelled && res.error != null) {
                              AppToast.show(
                                dialogCtx,
                                res.error!,
                                isDark: isDark,
                                accentColor: red,
                              );
                            }
                          },
                          icon: const Icon(Icons.link_rounded, size: 14),
                          label: Text(
                            workbench.isLocalGddLinkSupported
                                ? 'Link Local File'
                                : 'Download GDD',
                          ),
                        ),
                      OutlinedButton.icon(
                        key: const ValueKey('gdd_inspector_download_btn'),
                        onPressed: () =>
                            exportCoPilotGdd(dialogCtx, workbench),
                        icon: const Icon(Icons.download_rounded, size: 14),
                        label: const Text('Download .md'),
                      ),
                      ElevatedButton.icon(
                        key: const ValueKey('gdd_inspector_copy_btn'),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: bundle.content),
                          );
                          if (!dialogCtx.mounted) return;
                          AppToast.show(
                            dialogCtx,
                            'Copied ${bundle.filename} to clipboard',
                            isDark: isDark,
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text('Copy GDD'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
