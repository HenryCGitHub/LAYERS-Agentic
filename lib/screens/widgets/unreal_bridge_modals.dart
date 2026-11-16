import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/markdown_exporter.dart';

/// Opens the `LayersBridge` Unreal MCP & Editor Plugin setup modal:
/// 1) 1-Click `layers_unreal_plugin.zip` download
/// 2) Generate/copy/rotate per-project `lyr_...` Cloud Link Token
/// 3) Official Unreal MCP (`http://127.0.0.1:8000/mcp`) + `LayersToolset` instructions
Future<void> showConnectUnrealPluginDialog(
  BuildContext context,
  WorkbenchProvider workbench,
) async {
  String? fetchedToken = workbench.cachedUnrealLinkTokenForActiveProject;
  String? tokenError;
  bool loading = fetchedToken == null;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          if (loading && fetchedToken == null && tokenError == null) {
            workbench.fetchOrCreateUnrealLinkToken().then((res) {
              if (!dialogCtx.mounted) return;
              setModalState(() {
                loading = false;
                fetchedToken = res.token;
                tokenError = res.error;
              });
            });
          }

          final isDark = workbench.isDark;
          final border = AppTheme.borderFor(isDark);
          final primary = AppTheme.textPrimaryFor(isDark);
          final secondary = AppTheme.textSecondaryFor(isDark);
          final muted = AppTheme.textMutedFor(isDark);
          final cyan = AppTheme.accentCyanFor(isDark);
          final green = AppTheme.accentGreenFor(isDark);

          final mcpConfigSnippet = '''{
  "mcpServers": {
    "unreal-editor-layers": {
      "url": "http://127.0.0.1:8000/mcp"
    }
  }
}''';

          return Dialog(
            backgroundColor: AppTheme.bgSurfaceRaisedFor(isDark),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              side: BorderSide(color: border),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cable, size: 18, color: cyan),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Connect Unreal MCP & LayersBridge',
                            style: AppTheme.displayFont(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          icon: Icon(Icons.close, color: muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pure-Python `.uplugin` (Zero C++ compile). Exposes `layers_get_active_epic_spec`, `layers_toggle_pie_check`, `layers_update_epic_tuning`, `layers_log_pie_fix`, `layers_resolve_pie_fix`, `layers_pass_active_epic`, and `layers_reopen_epic` on Unreal MCP.',
                      style: TextStyle(fontSize: 12.5, color: secondary, height: 1.4),
                    ),
                    const SizedBox(height: 16),

                    // Step 1: Download LayersBridge.uplugin
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurfaceFor(isDark),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '1. Install LayersBridge (.uplugin)',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: primary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Unzip into `<YourUEProject>/Plugins/LayersBridge` and enable `PythonScriptPlugin` + `ModelContextProtocol`. Adds `[ ⚡ Build E01 | 1/3 ✓ ▾ ]` directly next to Unreal Play.',
                                  style: TextStyle(fontSize: 12, color: muted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            key: const ValueKey('download_unreal_plugin_btn'),
                            onPressed: () {
                              final ok = triggerRelativeAssetDownload(
                                relativeHref: 'layers_unreal_plugin.zip',
                                downloadFilename: 'layers_unreal_plugin.zip',
                              );
                              AppToast.show(
                                dialogCtx,
                                ok
                                    ? 'Downloading layers_unreal_plugin.zip...'
                                    : 'Bundle ready at web/layers_unreal_plugin.zip',
                                isDark: isDark,
                              );
                            },
                            icon: const Icon(Icons.download_rounded, size: 15),
                            label: const Text('Download Zip'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Step 2: Project Cloud Link Token
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurfaceFor(isDark),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  '2. Project Sync Token (LAYERS_LINK_TOKEN)',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: primary,
                                  ),
                                ),
                                Text(
                                  workbench.formatUnrealSyncStatusLabel(),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: workbench.isActiveProjectSyncedWithUnreal
                                        ? green
                                        : muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (loading)
                            const LinearProgressIndicator(minHeight: 2)
                          else if (tokenError != null)
                            Text(
                              tokenError!,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.accentAmberFor(isDark),
                              ),
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.bgInsetFor(isDark),
                                          borderRadius: BorderRadius.circular(
                                            AppTheme.radiusXs,
                                          ),
                                          border: Border.all(color: border),
                                        ),
                                        child: SelectableText(
                                          fetchedToken ?? '',
                                          key: const ValueKey('unreal_link_token_text'),
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 12,
                                            color: cyan,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      key: const ValueKey('copy_unreal_token_btn'),
                                      onPressed: fetchedToken == null
                                          ? null
                                          : () {
                                              Clipboard.setData(
                                                ClipboardData(text: fetchedToken!),
                                              );
                                              AppToast.show(
                                                dialogCtx,
                                                'Copied Unreal Link Token',
                                                isDark: isDark,
                                              );
                                            },
                                      icon: const Icon(Icons.copy, size: 14),
                                      label: const Text('Copy'),
                                    ),
                                    const SizedBox(width: 6),
                                    TextButton(
                                      key: const ValueKey('rotate_unreal_token_btn'),
                                      onPressed: () {
                                        setModalState(() {
                                          loading = true;
                                          tokenError = null;
                                        });
                                        workbench
                                            .fetchOrCreateUnrealLinkToken(rotate: true)
                                            .then((res) {
                                          if (!dialogCtx.mounted) return;
                                          setModalState(() {
                                            loading = false;
                                            fetchedToken = res.token;
                                            tokenError = res.error;
                                          });
                                        });
                                      },
                                      child: const Text('Rotate'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  key: const ValueKey('copy_unreal_setup_py_btn'),
                                  onPressed: fetchedToken == null
                                      ? null
                                      : () {
                                          final cmd =
                                              'import init_unreal; init_unreal.get_pie_dock().configure_token("$fetchedToken")';
                                          Clipboard.setData(
                                            ClipboardData(text: cmd),
                                          );
                                          AppToast.show(
                                            dialogCtx,
                                            'Copied Unreal Output Log Python command',
                                            isDark: isDark,
                                          );
                                        },
                                  icon: const Icon(Icons.terminal_rounded, size: 14),
                                  label: const Text(
                                    'Copy UE Python Setup',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Step 3: Official Unreal MCP Endpoint snippet
                    Text(
                      '3. Point your AI Agent (Claude / Antigravity / Cursor) at Unreal MCP:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgInsetFor(isDark),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SelectableText(
                              mcpConfigSnippet,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                color: secondary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: mcpConfigSnippet));
                              AppToast.show(
                                dialogCtx,
                                'Copied MCP server config',
                                isDark: isDark,
                              );
                            },
                            icon: Icon(Icons.copy, size: 15, color: cyan),
                            tooltip: 'Copy MCP JSON',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
