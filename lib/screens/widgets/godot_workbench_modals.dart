import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/markdown_exporter.dart';

/// Modal dialog for downloading the native Godot 4 LAYERS Plugin (.zip),
/// generating/copying/rotating the live Cloud Sync Link Token (`lyr_...`),
/// and previewing the single Epic currently focused in Godot.
Future<void> showConnectGodotPluginDialog(
  BuildContext context,
  WorkbenchProvider workbench,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ConnectGodotPluginDialog(workbench: workbench),
  );
}

class _ConnectGodotPluginDialog extends StatefulWidget {
  final WorkbenchProvider workbench;

  const _ConnectGodotPluginDialog({required this.workbench});

  @override
  State<_ConnectGodotPluginDialog> createState() =>
      _ConnectGodotPluginDialogState();
}

class _ConnectGodotPluginDialogState extends State<_ConnectGodotPluginDialog> {
  String? _token;
  String? _error;
  bool _isLoading = false;
  bool _copiedToken = false;
  String? _downloadFeedback;

  @override
  void initState() {
    super.initState();
    _token = widget.workbench.cachedGodotLinkTokenForActiveProject;
    _loadToken(rotate: false);
  }

  Future<void> _loadToken({required bool rotate}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _copiedToken = false;
    });
    final result =
        await widget.workbench.fetchOrCreateGodotLinkToken(rotate: rotate);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _token = result.token;
      _error = result.error;
    });
  }

  String _maskToken(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length <= 16) return trimmed;
    return '${trimmed.substring(0, 10)}••••••••${trimmed.substring(trimmed.length - 6)}';
  }

  @override
  Widget build(BuildContext innerCtx) {
    final workbench = widget.workbench;
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final bgRecessed = AppTheme.bgSurfaceRecessedFor(isDark);
    final borderCol = AppTheme.borderSubtleFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);

    final snap = workbench.computeActiveGodotEpicSnapshot();
    final epicSummary = snap.totalEpics == 0
        ? 'No Epics planned yet — generate v0.1 first.'
        : snap.allEpicsCompleted
            ? 'All Epics Complete ✓ (${snap.releaseVersion}) — Plan next release in Web Studio.'
            : 'Epic ${snap.epicPosition} of ${snap.totalEpics} · ${snap.activeEpicCode} · ${snap.activeEpicTitle} '
                '(${snap.completedFeaturesInActiveEpic}/${snap.totalFeaturesInActiveEpic} features done)';

    final currentToken = _token;
    final hasToken = currentToken != null && currentToken.isNotEmpty;

    return AlertDialog(
      key: const ValueKey('connect_godot_plugin_dialog'),
      backgroundColor: bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderCol),
      ),
      title: Row(
        children: [
          const Icon(Icons.extension_rounded, size: 18, color: Color(0xFF38BDF8)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Connect Godot 4 LAYERS Dock',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Active Single-Epic Godot Focus Preview
              Container(
                key: const ValueKey('connect_godot_active_epic_preview'),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: bgRecessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GODOT DOCK v3.0.8 · SPEC, PLAYTEST & 2-WAY SYNC',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      workbench.isActiveProjectSyncedWithGodot
                          ? '● Live Sync · ${workbench.formatGodotSyncStatusLabel()}'
                          : '○ Not synced with Godot yet',
                      key: const ValueKey('connect_godot_sync_status_badge'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: workbench.isActiveProjectSyncedWithGodot
                            ? const Color(0xFF34D399)
                            : textMuted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      epicSummary,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    if (snap.activeFeatureId != null &&
                        snap.activeFeatureTitle.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Active Godot Feature: ${snap.activeFeatureTitle}',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: textSecondary,
                            ),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey(
                              'jump_to_active_godot_feature_btn',
                            ),
                            onPressed: workbench.selectedFeatureId ==
                                    snap.activeFeatureId
                                ? null
                                : () {
                                    workbench.focusActiveGodotFeature();
                                    Navigator.of(innerCtx).pop();
                                  },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              minimumSize: const Size(0, 26),
                            ),
                            icon: const Icon(Icons.my_location_rounded, size: 13),
                            label: Text(
                              workbench.selectedFeatureId == snap.activeFeatureId
                                  ? 'Viewing Active Godot Feature ✓'
                                  : 'Jump to Active Godot Feature →',
                              style: GoogleFonts.inter(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Inspect Feature specs inside Godot 4, jump straight to scenes & scripts, run 1-click Playtest, capture debugger traces as [FIX] issues, and sync Done status both ways.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        height: 1.4,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Step 1: Download native Godot 4 addon .zip
              Text(
                '1. INSTALL PLUGIN IN GODOT 4',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton.icon(
                    key: const ValueKey('download_godot_plugin_zip_btn'),
                    onPressed: () {
                      final ok = triggerRelativeAssetDownload(
                        relativeHref: 'layers_godot_plugin.zip',
                        downloadFilename: 'layers_godot_plugin.zip',
                      );
                      setState(() {
                        _downloadFeedback = ok
                            ? 'Downloading layers_godot_plugin.zip...'
                            : 'Plugin archive: layers_godot_plugin.zip (download available on Web Studio).';
                      });
                    },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Download Godot 4 Plugin (.zip)'),
                  ),
                  Text(
                    'Unzip addons/layers/ → Project Settings → Plugins → Enable LAYERS',
                    style: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                  ),
                ],
              ),
              if (_downloadFeedback != null) ...[
                const SizedBox(height: 6),
                Text(
                  _downloadFeedback!,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF34D399),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Step 2: Live Cloud Link Token
              Text(
                '2. PASTE PROJECT LINK TOKEN INTO GODOT DOCK',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bgRecessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderCol),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: hasToken
                              ? SelectableText(
                                  _maskToken(currentToken),
                                  key: const ValueKey('godot_link_token_display'),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF6EE7B7),
                                  ),
                                )
                              : Text(
                                  _isLoading
                                      ? 'Generating live Cloud Link Token...'
                                      : (_error ??
                                          'Sign in with Google to generate a Cloud Link Token.'),
                                  key: const ValueKey(
                                    'godot_link_token_status_text',
                                  ),
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: _isLoading
                                        ? textSecondary
                                        : const Color(0xFFFBBF24),
                                  ),
                                ),
                        ),
                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ElevatedButton.icon(
                          key: const ValueKey('copy_godot_link_token_btn'),
                          onPressed: hasToken
                              ? () {
                                  Clipboard.setData(
                                    ClipboardData(text: currentToken),
                                  );
                                  setState(() => _copiedToken = true);
                                }
                              : null,
                          icon: Icon(
                            _copiedToken
                                ? Icons.check_rounded
                                : Icons.copy_rounded,
                            size: 14,
                          ),
                          label: Text(
                            _copiedToken ? 'Copied Token ✓' : 'Copy Link Token',
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('rotate_godot_link_token_btn'),
                          onPressed: _isLoading
                              ? null
                              : () => _loadToken(rotate: hasToken),
                          icon: const Icon(Icons.refresh_rounded, size: 14),
                          label: Text(hasToken ? 'Rotate Token' : 'Retry'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(innerCtx).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
