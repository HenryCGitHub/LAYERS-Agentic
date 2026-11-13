import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/godot_project_contract.dart';
import '../../models/godot_virtual_file.dart';
import '../../models/tier_document.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/markdown_exporter.dart';

/// Opens the Active Godot 4 Files, Cloud Sync & Diff-Gated Disk Sync modal.
Future<void> showGodotFilesAndSyncDialog(
  BuildContext context,
  WorkbenchProvider workbench, {
  String? initialResPath,
  TierDocument? activeFeature,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => _GodotFilesAndSyncDialog(
      workbench: workbench,
      initialResPath: initialResPath,
      activeFeature: activeFeature,
    ),
  );
}

class _GodotFilesAndSyncDialog extends StatefulWidget {
  final WorkbenchProvider workbench;
  final String? initialResPath;
  final TierDocument? activeFeature;

  const _GodotFilesAndSyncDialog({
    required this.workbench,
    this.initialResPath,
    this.activeFeature,
  });

  @override
  State<_GodotFilesAndSyncDialog> createState() =>
      _GodotFilesAndSyncDialogState();
}

class _GodotFilesAndSyncDialogState extends State<_GodotFilesAndSyncDialog> {
  final TextEditingController folderPathCtrl = TextEditingController();
  late String? selectedKey = widget.initialResPath != null &&
          widget.initialResPath!.trim().isNotEmpty
      ? GodotVirtualFile.normalizeResPath(widget.initialResPath!)
      : null;
  String? syncFeedback;
  bool syncIsError = false;

  @override
  void dispose() {
    folderPathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    final workbench = widget.workbench;
    final activeFeature = widget.activeFeature;
    void setModalState(VoidCallback fn) => setState(fn);

    final isDark = workbench.isDark;
          final bgSurface = AppTheme.bgSurfaceFor(isDark);
          final bgInset = AppTheme.bgInsetFor(isDark);
          final borderCol = AppTheme.borderSubtleFor(isDark);
          final textPrimary = AppTheme.textPrimaryFor(isDark);
          final textSecondary = AppTheme.textSecondaryFor(isDark);
          final textMuted = AppTheme.textMutedFor(isDark);

          final files = workbench.activeProjectGodotFiles;
          final contract = workbench.activeGodotContract;
          final activeFeat = activeFeature ??
              (workbench.selectedFeatureId != null
                  ? workbench.documents[workbench.selectedFeatureId!]
                  : null);
          final scenePath = workbench.extractPrimarySceneResPath(
                activeFeat?.sections['primary_asset'],
              ) ??
              'res://scenes/main_feature.tscn';
          final scriptForScene = workbench.extractPrimaryScriptResPath(
            activeFeat?.sections['primary_asset'],
          );
          final tscnScaffold = GodotVirtualFile.buildTscnStarterScaffold(
            rootNodeName: _pascalFromFeatTitle(activeFeat?.title ?? 'MainNode'),
            rootNodeType: contract.is3D ? 'Node3D' : 'Node2D',
            scriptResPath: scriptForScene,
          );
          final iniSnippet = contract.toProjectGodotIniSnippet();

          const tscnVirtualKey = '__tscn_scaffold__';
          const iniVirtualKey = '__project_godot_ini__';

          if (selectedKey == null) {
            selectedKey = files.isNotEmpty ? files.first.resPath : tscnVirtualKey;
          } else if (selectedKey != tscnVirtualKey &&
              selectedKey != iniVirtualKey &&
              !files.any((f) => f.resPath == selectedKey)) {
            selectedKey = files.isNotEmpty ? files.first.resPath : tscnVirtualKey;
          }

          final selectedFile = files.cast<GodotVirtualFile?>().firstWhere(
                (f) => f?.resPath == selectedKey,
                orElse: () => null,
              );

          final String viewerTitle;
          final String viewerContent;
          final String downloadName;
          final bool isReadOnlyScaffold;
          if (selectedKey == tscnVirtualKey) {
            viewerTitle = '$scenePath (Starter .tscn Scaffold)';
            viewerContent = tscnScaffold;
            downloadName = scenePath.split('/').last;
            isReadOnlyScaffold = true;
          } else if (selectedKey == iniVirtualKey) {
            viewerTitle = 'project.godot (INI Contract Snippet)';
            viewerContent = iniSnippet.isNotEmpty
                ? iniSnippet
                : '; Add layers, actions, or autoloads in ⚙ Contract.';
            downloadName = 'project.godot.ini.txt';
            isReadOnlyScaffold = true;
          } else {
            viewerTitle = selectedFile?.resPath ?? 'Script';
            viewerContent = selectedFile?.content ?? '';
            downloadName =
                (selectedFile?.resPath.split('/').last ?? 'script.gd');
            isReadOnlyScaffold = !(selectedFile?.isDiskWritable ?? false);
          }

          final size = MediaQuery.of(ctx).size;
          final maxW = (size.width * 0.92).clamp(320.0, 960.0);
          final maxH = (size.height * 0.88).clamp(420.0, 740.0);

          final bool folderLinked = workbench.isGodotFolderLinked;
          final List<GodotDiffLine> pendingDiskDiff =
              (folderLinked && selectedFile != null && selectedFile.isDiskWritable)
                  ? workbench.previewDiskDiffForResPath(selectedFile.resPath)
                  : const [];
          final bool canUndo = selectedFile != null &&
              workbench.canUndoDiskWrite(selectedFile.resPath);
          final List<String> patchWarnings = selectedFile != null
              ? workbench.patchWarningsForResPath(selectedFile.resPath)
              : const [];
          final unmatchedHunks = selectedFile != null
              ? workbench.unmatchedPatchHunksForResPath(selectedFile.resPath)
              : const [];

          return Dialog(
            backgroundColor: bgSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: borderCol),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header ──
                    Row(
                      children: [
                        const Icon(
                          Icons.folder_copy_outlined,
                          size: 18,
                          color: Color(0xFF38BDF8),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Active Godot 4 Files & Sync',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        _cloudStatusChip(workbench, selectedFile?.id),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          key: const ValueKey('godot_modal_open_contract_btn'),
                          onPressed: () async {
                            await showGodotContractDialog(ctx, workbench);
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.tune_rounded, size: 14),
                          label: Text(
                            'Contract',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: Icon(Icons.close, size: 18, color: textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Local Godot Folder Sync Bar ──
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: bgInset,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderCol),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                            folderLinked
                                ? Icons.link_rounded
                                : Icons.link_off_rounded,
                            size: 15,
                            color: folderLinked
                                ? const Color(0xFF34D399)
                                : textMuted,
                          ),
                          if (folderLinked) ...[
                            Text(
                              'Linked: ${workbench.linkedGodotFolderLabel}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF6EE7B7),
                              ),
                            ),
                            OutlinedButton.icon(
                              key: const ValueKey('godot_refresh_pull_btn'),
                              onPressed: () async {
                                final snap = await workbench
                                    .refreshLinkedGodotFolder();
                                setModalState(() {
                                  syncIsError = !snap.ok;
                                  syncFeedback = snap.ok
                                      ? 'Pulled ${snap.filesByResPath.length} disk files & project.godot.'
                                      : snap.errorMessage;
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 14),
                              label: const Text('Pull Disk'),
                            ),
                            TextButton(
                              onPressed: () {
                                workbench.unlinkGodotProjectFolder();
                                setModalState(() {
                                  syncIsError = false;
                                  syncFeedback = 'Unlinked local Godot folder.';
                                });
                              },
                              child: const Text('Unlink'),
                            ),
                          ] else if (workbench.isGodotFolderSyncSupported) ...[
                            if (!kIsWeb)
                              SizedBox(
                                width: 280,
                                child: TextField(
                                  key: const ValueKey('godot_folder_path_input'),
                                  controller: folderPathCtrl,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11.5,
                                    color: textPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '/path/to/godot_project (contains project.godot)',
                                    hintStyle: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: textMuted,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ElevatedButton.icon(
                              key: const ValueKey('godot_link_folder_btn'),
                              onPressed: () async {
                                final snap =
                                    await workbench.linkGodotProjectFolder(
                                  directoryPath: kIsWeb
                                      ? null
                                      : folderPathCtrl.text.trim(),
                                );
                                setModalState(() {
                                  syncIsError = !snap.ok;
                                  syncFeedback = snap.ok
                                      ? 'Linked "${snap.folderLabel}" · pulled ${snap.filesByResPath.length} files.'
                                      : snap.errorMessage;
                                });
                              },
                              icon: const Icon(Icons.folder_open_rounded, size: 14),
                              label: Text(
                                kIsWeb
                                    ? 'Link Godot Folder'
                                    : 'Link & Pull Folder',
                              ),
                            ),
                          ] else ...[
                            Expanded(
                              child: Text(
                                workbench.godotFolderSyncUnsupportedReason,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (syncFeedback != null && syncFeedback!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        syncFeedback!,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: syncIsError
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF6EE7B7),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),

                    // ── Cumulative File Tabs + Read-Only Scaffolds ──
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final vf in files) ...[
                            _fileChip(
                              label: vf.resPath.replaceFirst('res://', ''),
                              selected: selectedKey == vf.resPath,
                              hasDiff: folderLinked &&
                                  vf.isDiskWritable &&
                                  workbench
                                      .previewDiskDiffForResPath(vf.resPath)
                                      .isNotEmpty,
                              onTap: () =>
                                  setModalState(() => selectedKey = vf.resPath),
                              isDark: isDark,
                            ),
                            const SizedBox(width: 6),
                          ],
                          _fileChip(
                            label: '.tscn Starter (Read-Only)',
                            selected: selectedKey == tscnVirtualKey,
                            onTap: () =>
                                setModalState(() => selectedKey = tscnVirtualKey),
                            isDark: isDark,
                          ),
                          const SizedBox(width: 6),
                          _fileChip(
                            label: 'project.godot INI (Read-Only)',
                            selected: selectedKey == iniVirtualKey,
                            onTap: () =>
                                setModalState(() => selectedKey = iniVirtualKey),
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Patch Warnings / Unmatched Hunk Notice ──
                    if (patchWarnings.isNotEmpty || unmatchedHunks.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF78350F).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          [
                            ...patchWarnings,
                            if (unmatchedHunks.isNotEmpty)
                              '${unmatchedHunks.length} patch hunk(s) could not match your custom edits cleanly and were preserved unapplied for manual review.',
                          ].join(' · '),
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: const Color(0xFFFDE68A),
                          ),
                        ),
                      ),
                    ],

                    // ── Active File Header + Action Buttons ──
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            viewerTitle,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF7DD3FC),
                            ),
                          ),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                key: const ValueKey('godot_modal_copy_btn'),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: viewerContent),
                                  );
                                  setModalState(() {
                                    syncIsError = false;
                                    syncFeedback =
                                        'Copied $downloadName to clipboard.';
                                  });
                                },
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                label: const Text('Copy'),
                              ),
                              OutlinedButton.icon(
                                key: const ValueKey('godot_modal_download_btn'),
                                onPressed: () {
                                  triggerMarkdownFileDownload(
                                    filename: downloadName,
                                    content: viewerContent,
                                  );
                                },
                                icon: const Icon(
                                  Icons.download_rounded,
                                  size: 14,
                                ),
                                label: const Text('Download'),
                              ),
                              if (folderLinked &&
                                  selectedFile != null &&
                                  selectedFile.isDiskWritable) ...[
                                ElevatedButton.icon(
                                  key: const ValueKey(
                                    'godot_modal_review_diff_btn',
                                  ),
                                  onPressed: pendingDiskDiff.isEmpty
                                      ? null
                                      : () async {
                                          final confirmed =
                                              await _showRedGreenDiskDiffDialog(
                                                ctx,
                                                resPath: selectedFile.resPath,
                                                diffLines: pendingDiskDiff,
                                                isDark: isDark,
                                              );
                                          if (confirmed == true) {
                                            final res = await workbench
                                                .applyVirtualFileToDisk(
                                                  selectedFile.resPath,
                                                );
                                            setModalState(() {
                                              syncIsError = !res.success;
                                              syncFeedback = res.message;
                                            });
                                          }
                                        },
                                  icon: const Icon(
                                    Icons.difference_outlined,
                                    size: 14,
                                  ),
                                  label: Text(
                                    pendingDiskDiff.isEmpty
                                        ? 'Matches Disk ✓'
                                        : 'Review Diff → Write',
                                  ),
                                ),
                                if (canUndo)
                                  OutlinedButton.icon(
                                    key: const ValueKey(
                                      'godot_modal_undo_disk_btn',
                                    ),
                                    onPressed: () async {
                                      final res = await workbench
                                          .undoLastDiskWrite(
                                            selectedFile.resPath,
                                          );
                                      setModalState(() {
                                        syncIsError = !res.success;
                                        syncFeedback = res.message;
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.undo_rounded,
                                      size: 14,
                                    ),
                                    label: const Text('Restore Previous'),
                                  ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Source Code Well ──
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: bgInset,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderCol),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            viewerContent.isEmpty
                                ? '// Empty file — synthesize steps or paste code to populate.'
                                : viewerContent,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              height: 1.45,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isReadOnlyScaffold) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Safe Mode: .tscn scenes and project.godot snippets are copy/download-only so Godot UIDs and editor settings are never overwritten on disk.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: textMuted,
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

/// Red/Green Unified Diff review dialog gating every disk write (`.gd` / `.tres` only).
Future<bool?> _showRedGreenDiskDiffDialog(
  BuildContext context, {
  required String resPath,
  required List<GodotDiffLine> diffLines,
  required bool isDark,
}) {
  final bgSurface = AppTheme.bgSurfaceFor(isDark);
  final bgInset = AppTheme.bgInsetFor(isDark);
  final borderCol = AppTheme.borderSubtleFor(isDark);
  final textPrimary = AppTheme.textPrimaryFor(isDark);

  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderCol),
      ),
      title: Text(
        'Review Disk Diff · $resPath',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      content: SizedBox(
        width: 680,
        height: 380,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bgInset,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderCol),
          ),
          child: ListView.builder(
            itemCount: diffLines.length,
            itemBuilder: (_, i) {
              final line = diffLines[i];
              final Color? rowBg = switch (line.kind) {
                GodotDiffLineKind.added =>
                  const Color(0xFF065F46).withValues(alpha: 0.35),
                GodotDiffLineKind.removed =>
                  const Color(0xFF7F1D1D).withValues(alpha: 0.38),
                GodotDiffLineKind.context => null,
              };
              final Color fg = switch (line.kind) {
                GodotDiffLineKind.added => const Color(0xFF6EE7B7),
                GodotDiffLineKind.removed => const Color(0xFFFCA5A5),
                GodotDiffLineKind.context => AppTheme.textSecondaryFor(isDark),
              };
              final prefix = switch (line.kind) {
                GodotDiffLineKind.added => '+ ',
                GodotDiffLineKind.removed => '- ',
                GodotDiffLineKind.context => '  ',
              };
              return Container(
                color: rowBg,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                child: Text(
                  '$prefix${line.text}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11.5,
                    color: fg,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          key: const ValueKey('confirm_apply_disk_diff_btn'),
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.check_rounded, size: 15),
          label: const Text('Apply to Disk'),
        ),
      ],
    ),
  );
}

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

Widget _cloudStatusChip(WorkbenchProvider workbench, String? docId) {
  final pending = docId != null && workbench.isDocPendingCloudWrite(docId);
  final cloudReady = workbench.isCloudSaveReady;
  final label = pending
      ? '☁ Syncing...'
      : (cloudReady ? '☁ Cloud Saved' : '💾 Local Vault');
  final color = pending
      ? const Color(0xFFFBBF24)
      : (cloudReady ? const Color(0xFF34D399) : const Color(0xFF94A3B8));
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}

Widget _fileChip({
  required String label,
  required bool selected,
  required VoidCallback onTap,
  required bool isDark,
  bool hasDiff = false,
}) {
  final bg = selected
      ? const Color(0xFF1D4ED8).withValues(alpha: 0.25)
      : AppTheme.bgInsetFor(isDark);
  final border = selected
      ? const Color(0xFF60A5FA)
      : AppTheme.borderSubtleFor(isDark);
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected
                  ? const Color(0xFF93C5FD)
                  : AppTheme.textSecondaryFor(isDark),
            ),
          ),
          if (hasDiff) ...[
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFF59E0B),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

String _pascalFromFeatTitle(String title) {
  final words = title
      .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'MainNode';
  return words
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join();
}
