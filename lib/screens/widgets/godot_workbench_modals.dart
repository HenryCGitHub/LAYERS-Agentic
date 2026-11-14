import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/godot_project_contract.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/markdown_exporter.dart';

/// Modal editor for per-project Godot 4 Physics Layers, InputMap Actions, Autoloads, and Groups.
Future<void> showGodotContractDialog(
  BuildContext context,
  WorkbenchProvider workbench,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _GodotContractDialog(workbench: workbench),
  );
}

class _GodotContractDialog extends StatefulWidget {
  final WorkbenchProvider workbench;

  const _GodotContractDialog({required this.workbench});

  @override
  State<_GodotContractDialog> createState() => _GodotContractDialogState();
}

class _GodotContractDialogState extends State<_GodotContractDialog> {
  late final GodotProjectContract contract =
      widget.workbench.activeGodotContract;
  late final TextEditingController layersCtrl = TextEditingController(
    text: (contract.physicsLayers.keys.toList()..sort())
        .map((k) => '$k: ${contract.physicsLayers[k]}')
        .join(', '),
  );
  late final TextEditingController inputsCtrl = TextEditingController(
    text: contract.inputActions.join(', '),
  );
  late final TextEditingController autoloadsCtrl = TextEditingController(
    text: contract.autoloads.map((a) => '${a.name}=${a.resPath}').join(', '),
  );
  late final TextEditingController groupsCtrl = TextEditingController(
    text: contract.groups.join(', '),
  );
  late bool is3D = contract.is3D;

  @override
  void dispose() {
    layersCtrl.dispose();
    inputsCtrl.dispose();
    autoloadsCtrl.dispose();
    groupsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext innerCtx) {
    final workbench = widget.workbench;
    void setStateDialog(VoidCallback fn) => setState(fn);

    final isDark = workbench.isDark;
        final bgSurface = AppTheme.bgSurfaceFor(isDark);
        final borderCol = AppTheme.borderSubtleFor(isDark);
        final textPrimary = AppTheme.textPrimaryFor(isDark);
        final textMuted = AppTheme.textMutedFor(isDark);

        GodotProjectContract buildContractFromFields() {
          final parsedLayers = <int, String>{};
          for (final chunk in layersCtrl.text.split(',')) {
            final parts = chunk.split(':');
            if (parts.length < 2) continue;
            final idx = int.tryParse(parts.first.trim());
            final name = parts.sublist(1).join(':').trim();
            if (idx != null && idx >= 1 && idx <= 32 && name.isNotEmpty) {
              parsedLayers[idx] = name;
            }
          }
          final parsedInputs = inputsCtrl.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          final parsedAutoloads = <GodotAutoloadEntry>[];
          for (final chunk in autoloadsCtrl.text.split(',')) {
            final parts = chunk.split('=');
            if (parts.length < 2) continue;
            final name = parts.first.trim();
            final path = GodotAutoloadEntry.normalizeResPath(
              parts.sublist(1).join('='),
            );
            if (name.isNotEmpty && path.isNotEmpty) {
              parsedAutoloads.add(GodotAutoloadEntry(name: name, resPath: path));
            }
          }
          final parsedGroups = groupsCtrl.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          return contract.copyWith(
            physicsLayers: parsedLayers,
            inputActions: parsedInputs,
            autoloads: parsedAutoloads,
            groups: parsedGroups,
            is3D: is3D,
          );
        }

        return AlertDialog(
          backgroundColor: bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: borderCol),
          ),
          title: Row(
            children: [
              const Icon(Icons.tune_rounded, size: 17, color: Color(0xFF38BDF8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Godot 4 Project Contract',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(is3D ? '3D Physics' : '2D Physics'),
                selected: is3D,
                onSelected: (v) => setStateDialog(() => is3D = v),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Shared across prompts, AGENTS.md, and inline Inspector layer toggles.',
                    style: GoogleFonts.inter(fontSize: 12, color: textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('contract_layers_input'),
                    controller: layersCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Physics Layers (e.g. 1: World, 2: Player, 3: Enemy)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('contract_inputs_input'),
                    controller: inputsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'InputMap Actions (comma-separated)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('contract_autoloads_input'),
                    controller: autoloadsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Autoload Singletons (e.g. Events=res://autoloads/events.gd)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('contract_groups_input'),
                    controller: groupsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Node Groups (comma-separated)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                final ini = buildContractFromFields().toProjectGodotIniSnippet();
                Clipboard.setData(ClipboardData(text: ini));
              },
              child: const Text('Copy project.godot INI'),
            ),
            TextButton(
              onPressed: () => Navigator.of(innerCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const ValueKey('contract_save_btn'),
              onPressed: () {
                workbench.updateGodotContract(buildContractFromFields());
                Navigator.of(innerCtx).pop();
              },
              child: const Text('Save Contract'),
            ),
          ],
        );
  }
}

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
                      'GODOT DOCK FOCUS (1 EPIC · 1 STEP AT A TIME)',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: const Color(0xFF38BDF8),
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
                    const SizedBox(height: 4),
                    Text(
                      'Shows 1 active step at a time with live Godot Scene/Script checks, undoable setup actions, and ✦ Ask Agent to Fix.',
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
