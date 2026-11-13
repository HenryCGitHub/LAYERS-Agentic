import 'dart:io';

import '../models/godot_virtual_file.dart';
import 'godot_folder_sync_interface.dart';

/// Native `dart:io` implementation of safe Godot project folder read & diff-gated `.gd`/`.tres` writes.
class GodotFolderSyncIoImpl implements GodotFolderSyncBackend {
  static const int _maxTextBytes = 512 * 1024;
  static const Set<String> _ignoredDirs = {'.godot', '.git', '.import', 'build', '.mono'};

  Directory? _rootDir;
  final Map<String, String?> _previousDiskContentByResPath = {};

  @override
  bool get isSupported => true;

  @override
  String get unsupportedReason => '';

  @override
  bool get isLinked => _rootDir != null;

  @override
  String get linkedFolderLabel => _rootDir?.path ?? '';

  @override
  Future<GodotFolderSnapshot> linkAndPullFolder({String? directoryPath}) async {
    final trimmed = (directoryPath ?? '').trim();
    if (trimmed.isEmpty) {
      return const GodotFolderSnapshot(
        folderLabel: '',
        errorMessage: 'Enter the local path to your Godot project folder (containing project.godot).',
      );
    }

    final dir = Directory(trimmed);
    if (!await dir.exists()) {
      return GodotFolderSnapshot(
        folderLabel: trimmed,
        errorMessage: 'Folder not found: $trimmed',
      );
    }

    final projectFile = File(_joinNative(dir.path, 'project.godot'));
    if (!await projectFile.exists()) {
      return GodotFolderSnapshot(
        folderLabel: trimmed,
        errorMessage: 'Missing project.godot in $trimmed. Select the root of a Godot 4 project.',
      );
    }

    _rootDir = dir;
    _previousDiskContentByResPath.clear();
    return refreshLinkedFolder();
  }

  @override
  Future<GodotFolderSnapshot> refreshLinkedFolder() async {
    final root = _rootDir;
    if (root == null) {
      return const GodotFolderSnapshot(
        folderLabel: '',
        errorMessage: 'No Godot folder linked yet.',
      );
    }

    try {
      final projectFile = File(_joinNative(root.path, 'project.godot'));
      if (!await projectFile.exists()) {
        return GodotFolderSnapshot(
          folderLabel: root.path,
          errorMessage: 'project.godot is no longer present in ${root.path}.',
        );
      }
      final projectGodotText =
          (await projectFile.readAsString()).replaceAll('\r\n', '\n');

      final files = <String, String>{};
      await _collectTextFiles(root, '', files);
      return GodotFolderSnapshot(
        folderLabel: root.path,
        projectGodotText: projectGodotText,
        filesByResPath: files,
      );
    } catch (e) {
      return GodotFolderSnapshot(
        folderLabel: root.path,
        errorMessage: 'Failed reading Godot folder: $e',
      );
    }
  }

  Future<void> _collectTextFiles(
    Directory dir,
    String relativePrefix,
    Map<String, String> out,
  ) async {
    await for (final entity in dir.list(followLinks: false)) {
      final name = _baseName(entity.path);
      if (entity is Directory) {
        if (_ignoredDirs.contains(name) || name.startsWith('.')) continue;
        final nextPrefix = relativePrefix.isEmpty ? name : '$relativePrefix/$name';
        await _collectTextFiles(entity, nextPrefix, out);
      } else if (entity is File) {
        final lower = name.toLowerCase();
        if (!lower.endsWith('.gd') && !lower.endsWith('.tres')) continue;
        final len = await entity.length();
        if (len > _maxTextBytes) continue;
        final rel = relativePrefix.isEmpty ? name : '$relativePrefix/$name';
        final resPath = GodotVirtualFile.normalizeResPath(rel);
        out[resPath] = (await entity.readAsString()).replaceAll('\r\n', '\n');
      }
    }
  }

  @override
  Future<String?> readDiskFile(String resPath) async {
    final file = _resolveSafeFile(resPath, allowReadOnly: true);
    if (file == null || !await file.exists()) return null;
    return (await file.readAsString()).replaceAll('\r\n', '\n');
  }

  @override
  Future<GodotWriteResult> writeAllowedFile({
    required String resPath,
    required String content,
  }) async {
    final norm = GodotVirtualFile.normalizeResPath(resPath);
    if (!isSafeWritableGodotResPath(norm)) {
      return GodotWriteResult(
        success: false,
        resPath: norm,
        message: 'Safe sync only writes .gd and .tres files. Scene (.tscn) and project.godot files stay read-only.',
      );
    }
    final file = _resolveSafeFile(norm);
    if (file == null) {
      return GodotWriteResult(
        success: false,
        resPath: norm,
        message: 'No linked Godot folder or invalid relative path.',
      );
    }

    try {
      String? previous;
      if (await file.exists()) {
        previous = (await file.readAsString()).replaceAll('\r\n', '\n');
      }
      _previousDiskContentByResPath[norm] = previous;
      await file.parent.create(recursive: true);
      await file.writeAsString(content.replaceAll('\r\n', '\n'));
      return GodotWriteResult(
        success: true,
        resPath: norm,
        message: previous == null ? 'Created $norm on disk.' : 'Updated $norm on disk.',
        canUndo: true,
      );
    } catch (e) {
      return GodotWriteResult(
        success: false,
        resPath: norm,
        message: 'Failed writing $norm: $e',
      );
    }
  }

  @override
  bool canUndo(String resPath) =>
      _previousDiskContentByResPath.containsKey(GodotVirtualFile.normalizeResPath(resPath));

  @override
  String? previousDiskContent(String resPath) =>
      _previousDiskContentByResPath[GodotVirtualFile.normalizeResPath(resPath)];

  @override
  Future<GodotWriteResult> undoLastWrite(String resPath) async {
    final norm = GodotVirtualFile.normalizeResPath(resPath);
    if (!_previousDiskContentByResPath.containsKey(norm)) {
      return GodotWriteResult(
        success: false,
        resPath: norm,
        message: 'No previous snapshot recorded for $norm in this session.',
      );
    }
    final file = _resolveSafeFile(norm);
    if (file == null) {
      return GodotWriteResult(
        success: false,
        resPath: norm,
        message: 'Linked folder unavailable.',
      );
    }

    try {
      final prev = _previousDiskContentByResPath.remove(norm);
      if (prev == null) {
        if (await file.exists()) await file.delete();
        return GodotWriteResult(
          success: true,
          resPath: norm,
          message: 'Removed newly created $norm.',
        );
      } else {
        await file.parent.create(recursive: true);
        await file.writeAsString(prev);
        return GodotWriteResult(
          success: true,
          resPath: norm,
          message: 'Restored previous contents of $norm.',
        );
      }
    } catch (e) {
      return GodotWriteResult(
        success: false,
        resPath: norm,
        message: 'Undo failed for $norm: $e',
      );
    }
  }

  @override
  void unlink() {
    _rootDir = null;
    _previousDiskContentByResPath.clear();
  }

  File? _resolveSafeFile(String resPath, {bool allowReadOnly = false}) {
    final root = _rootDir;
    if (root == null) return null;
    final norm = GodotVirtualFile.normalizeResPath(resPath);
    if (norm.contains('..')) return null;
    if (!allowReadOnly && !isSafeWritableGodotResPath(norm)) return null;
    final rel = norm.replaceFirst('res://', '');
    if (rel.isEmpty) return null;
    final segments = rel.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return File([root.path, ...segments].join(Platform.pathSeparator));
  }

  static String _joinNative(String base, String child) {
    final clean = base.endsWith(Platform.pathSeparator)
        ? base.substring(0, base.length - 1)
        : base;
    return '$clean${Platform.pathSeparator}$child';
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx == -1 ? normalized : normalized.substring(idx + 1);
  }
}

GodotFolderSyncBackend createGodotFolderSyncBackend() => GodotFolderSyncIoImpl();
