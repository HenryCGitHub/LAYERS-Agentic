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
                child: SingleChildScrollView(
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
                                  '2. Connect via Google Account (or Fallback Token)',
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
                          const SizedBox(height: 6),
                          Text(
                            'In Unreal Editor, click `⚡ Sign in with Google` on the Play Toolbar to bind your `.uproject` in 1 click — or use the fallback token below for headless/remote machines.',
                            style: TextStyle(fontSize: 12, color: muted, height: 1.35),
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
            ),
          );
        },
      );
    },
  );
}

/// Overlay shown when Unreal Editor (`LayersBridge`) opens Web Studio via
/// `?unreal_auth=1&port=<port>&state=<nonce>&uproject=<Name>` to bind a `.uproject`
/// using the user's Google account without copying tokens manually.
class UnrealAuthHandoffOverlay extends StatelessWidget {
  final WorkbenchProvider workbench;

  const UnrealAuthHandoffOverlay({super.key, required this.workbench});

  @override
  Widget build(BuildContext context) {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceRaisedFor(isDark);
    final bgInset = AppTheme.bgInsetFor(isDark);
    final border = AppTheme.borderBrightFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final uprojName = workbench.pendingUnrealUprojectName?.trim();
    final port = workbench.pendingUnrealAuthPort;

    if (workbench.isUnrealAuthMinimized) {
      return Positioned(
        top: 12,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            key: const ValueKey('unreal_handoff_minimized_banner'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cyan.withValues(alpha: 0.55)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cable, size: 15, color: cyan),
                const SizedBox(width: 8),
                Text(
                  uprojName != null && uprojName.isNotEmpty
                      ? 'Unreal Waiting: $uprojName.uproject'
                      : 'Unreal Waiting to Link Project',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  key: const ValueKey('unreal_handoff_restore_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF06281E),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: () => workbench.setUnrealAuthMinimized(false),
                  child: const Text(
                    'Connect to Unreal',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('dismiss_unreal_handoff_minimized_btn'),
                  onPressed: workbench.dismissPendingUnrealAuth,
                  icon: Icon(Icons.close_rounded, size: 15, color: muted),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final projects = workbench.savedProjects;
    final selectedPid = workbench.effectiveUnrealAuthProjectId;

    return Container(
      key: const ValueKey('unreal_handoff_overlay'),
      color: Colors.black.withValues(alpha: 0.7),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'UNREAL EDITOR · GOOGLE SIGN-IN HANDOFF',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: cyan,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    key: const ValueKey('dismiss_unreal_handoff_btn'),
                    onTap: workbench.dismissPendingUnrealAuth,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                uprojName != null && uprojName.isNotEmpty
                    ? 'Connect $uprojName.uproject to LAYERS'
                    : 'Connect Unreal Editor to LAYERS',
                style: AppTheme.displayFont(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w700,
                  color: primary,
                ),
              ),
              if (port != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: bgInset,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.borderFor(isDark)),
                  ),
                  child: Text(
                    uprojName != null && uprojName.isNotEmpty
                        ? '$uprojName.uproject -> 127.0.0.1:$port'
                        : 'LayersBridge -> 127.0.0.1:$port',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: secondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (!workbench.isUserLoggedIn) ...[
                Text(
                  'Sign in once with your Google account to link this `.uproject` with your LAYERS project automatically — no manual token copying required.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.45,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('unreal_handoff_google_signin_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF06281E),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => workbench.signInWithGoogle(),
                    icon: const Icon(Icons.login_rounded, size: 16),
                    label: Text(
                      'Sign in with Google →',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ] else if (projects.isEmpty) ...[
                Text(
                  'Signed in as ${workbench.userEmail ?? 'Google Account'}. Draft your first LAYERS Project Spec, then click `Connect to Unreal` in the banner to complete linking.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.45,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('unreal_handoff_minimize_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF06281E),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => workbench.setUnrealAuthMinimized(true),
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    label: Text(
                      'Draft Project Spec First',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'Signed in as ${workbench.userEmail ?? 'Google Account'}. Choose the LAYERS project for this `.uproject`:',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.45,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: bgInset,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.borderFor(isDark)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const ValueKey('unreal_handoff_project_dropdown'),
                      isExpanded: true,
                      dropdownColor: bgSurface,
                      value: selectedPid,
                      items: [
                        for (final proj in projects)
                          DropdownMenuItem<String>(
                            value: proj.id,
                            child: Text(
                              proj.title,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: primary,
                              ),
                            ),
                          ),
                      ],
                      onChanged: workbench.isCompletingUnrealAuth
                          ? null
                          : (val) {
                              if (val != null) {
                                workbench.selectUnrealAuthProject(val);
                              }
                            },
                    ),
                  ),
                ),
                if (workbench.unrealAuthError != null &&
                    workbench.unrealAuthError!.isNotEmpty) ...[
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
                      workbench.unrealAuthError!,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        height: 1.35,
                        color: primary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('unreal_handoff_approve_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF06281E),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: workbench.isCompletingUnrealAuth
                        ? null
                        : () => workbench.completePendingUnrealAuthHandoff(),
                    icon: const Icon(Icons.verified_user_rounded, size: 16),
                    label: Text(
                      workbench.isCompletingUnrealAuth
                          ? 'Connecting to Unreal…'
                          : 'Link Project to Unreal Editor →',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
