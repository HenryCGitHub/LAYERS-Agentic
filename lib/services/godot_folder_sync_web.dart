import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../models/godot_virtual_file.dart';
import 'godot_folder_sync_interface.dart';

@JS('showDirectoryPicker')
external JSPromise<JSObject> _showDirectoryPicker([JSObject? options]);

extension type _JsDirHandle(JSObject _) implements JSObject {
  external JSString get name;
  external JSPromise<JSObject> getFileHandle(JSString name, [JSObject? options]);
  external JSPromise<JSObject> getDirectoryHandle(JSString name, [JSObject? options]);
  external JSObject values();
}

extension type _JsFileHandle(JSObject _) implements JSObject {
  external JSString get name;
  external JSString get kind;
  external JSPromise<JSObject> getFile();
  external JSPromise<JSObject> createWritable();
}

extension type _JsFile(JSObject _) implements JSObject {
  external JSNumber get size;
  external JSPromise<JSString> text();
}

extension type _JsWritableStream(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSString data);
  external JSPromise<JSAny?> close();
}

extension type _JsAsyncIterator(JSObject _) implements JSObject {
  external JSPromise<JSObject> next();
}

extension type _JsIteratorStep(JSObject _) implements JSObject {
  external JSBoolean get done;
  external JSObject? get value;
}

/// Web File System Access API (`showDirectoryPicker`) backend for Chromium desktop browsers.
class GodotFolderSyncWebImpl implements GodotFolderSyncBackend {
  static const int _maxTextBytes = 512 * 1024;
  static const Set<String> _ignoredDirs = {'.godot', '.git', '.import', 'build', '.mono'};

  _JsDirHandle? _rootHandle;
  final Map<String, String?> _previousDiskContentByResPath = {};

  @override
  bool get isSupported => globalContext.has('showDirectoryPicker');

  @override
  String get unsupportedReason => isSupported
      ? ''
      : 'Your browser does not support File System Access (`showDirectoryPicker`). Use Chrome/Edge on desktop, or Copy / Download files directly.';

  @override
  bool get isLinked => _rootHandle != null;

  @override
  String get linkedFolderLabel => _rootHandle?.name.toDart ?? '';

  @override
  Future<GodotFolderSnapshot> linkAndPullFolder({String? directoryPath}) async {
    if (!isSupported) {
      return GodotFolderSnapshot(
        folderLabel: '',
        errorMessage: unsupportedReason,
      );
    }

    try {
      final opts = JSObject()..['mode'] = 'readwrite'.toJS;
      final handle = _JsDirHandle(await _showDirectoryPicker(opts).toDart);

      // Verify `project.godot` exists at the root before accepting the link.
      try {
        await handle.getFileHandle('project.godot'.toJS).toDart;
      } catch (_) {
        return GodotFolderSnapshot(
          folderLabel: handle.name.toDart,
          errorMessage:
              'Missing project.godot in "${handle.name.toDart}". Pick the root of a Godot 4 project.',
        );
      }

      _rootHandle = handle;
      _previousDiskContentByResPath.clear();
      return await refreshLinkedFolder();
    } catch (e) {
      return GodotFolderSnapshot(
        folderLabel: '',
        errorMessage: 'Folder link cancelled or denied: $e',
      );
    }
  }

  @override
  Future<GodotFolderSnapshot> refreshLinkedFolder() async {
    final root = _rootHandle;
    if (root == null) {
      return const GodotFolderSnapshot(
        folderLabel: '',
        errorMessage: 'No Godot folder linked yet.',
      );
    }

    try {
      final projectHandle = _JsFileHandle(await root.getFileHandle('project.godot'.toJS).toDart);
      final projectFile = _JsFile(await projectHandle.getFile().toDart);
      final projectGodotText = (await projectFile.text().toDart).toDart.replaceAll('\r\n', '\n');

      final files = <String, String>{};
      await _collectTextFiles(root, '', files);
      return GodotFolderSnapshot(
        folderLabel: root.name.toDart,
        projectGodotText: projectGodotText,
        filesByResPath: files,
      );
    } catch (e) {
      return GodotFolderSnapshot(
        folderLabel: root.name.toDart,
        errorMessage: 'Failed reading linked browser folder: $e',
      );
    }
  }

  Future<void> _collectTextFiles(
    _JsDirHandle dir,
    String relativePrefix,
    Map<String, String> out,
  ) async {
    final iterator = _JsAsyncIterator(dir.values());
    while (true) {
      final step = _JsIteratorStep(await iterator.next().toDart);
      if (step.done.toDart) break;
      final val = step.value;
      if (val == null) continue;
      final entry = _JsFileHandle(val);
      final name = entry.name.toDart;
      final kind = entry.kind.toDart;
      if (kind == 'directory') {
        if (_ignoredDirs.contains(name) || name.startsWith('.')) continue;
        final nextPrefix = relativePrefix.isEmpty ? name : '$relativePrefix/$name';
        await _collectTextFiles(_JsDirHandle(val), nextPrefix, out);
      } else if (kind == 'file') {
        final lower = name.toLowerCase();
        if (!lower.endsWith('.gd') && !lower.endsWith('.tres')) continue;
        final file = _JsFile(await entry.getFile().toDart);
        if (file.size.toDartInt > _maxTextBytes) continue;
        final rel = relativePrefix.isEmpty ? name : '$relativePrefix/$name';
        final resPath = GodotVirtualFile.normalizeResPath(rel);
        out[resPath] = (await file.text().toDart).toDart.replaceAll('\r\n', '\n');
      }
    }
  }

  @override
  Future<String?> readDiskFile(String resPath) async {
    final root = _rootHandle;
    if (root == null) return null;
    final norm = GodotVirtualFile.normalizeResPath(resPath);
    if (norm.contains('..')) return null;
    final segments = norm.replaceFirst('res://', '').split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    try {
      var dir = root;
      for (var i = 0; i < segments.length - 1; i++) {
        dir = _JsDirHandle(await dir.getDirectoryHandle(segments[i].toJS).toDart);
      }
      final fileHandle = _JsFileHandle(await dir.getFileHandle(segments.last.toJS).toDart);
      final file = _JsFile(await fileHandle.getFile().toDart);
      return (await file.text().toDart).toDart.replaceAll('\r\n', '\n');
    } catch (_) {
      return null;
    }
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
    final root = _rootHandle;
    if (root == null) {
      return GodotWriteResult(
        success: false,
        resPath: norm,
        message: 'No Godot folder linked yet.',
      );
    }

    try {
      final previous = await readDiskFile(norm);
      _previousDiskContentByResPath[norm] = previous;
      await _writeTextAtPath(root, norm, content.replaceAll('\r\n', '\n'));
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

  Future<void> _writeTextAtPath(_JsDirHandle root, String resPath, String text) async {
    final segments = resPath.replaceFirst('res://', '').split('/').where((s) => s.isNotEmpty).toList();
    var dir = root;
    final createOpt = JSObject()..['create'] = true.toJS;
    for (var i = 0; i < segments.length - 1; i++) {
      dir = _JsDirHandle(await dir.getDirectoryHandle(segments[i].toJS, createOpt).toDart);
    }
    final fileHandle =
        _JsFileHandle(await dir.getFileHandle(segments.last.toJS, createOpt).toDart);
    final writable = _JsWritableStream(await fileHandle.createWritable().toDart);
    await writable.write(text.toJS).toDart;
    await writable.close().toDart;
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
    final root = _rootHandle;
    if (root == null) {
      return GodotWriteResult(
        success: false,
        resPath: norm,
        message: 'Linked folder unavailable.',
      );
    }

    try {
      final prev = _previousDiskContentByResPath.remove(norm);
      if (prev == null) {
        // Restore empty/non-existent state cleanly when deleting isn't exposed on older handles.
        await _writeTextAtPath(root, norm, '');
        return GodotWriteResult(
          success: true,
          resPath: norm,
          message: 'Cleared newly created $norm.',
        );
      } else {
        await _writeTextAtPath(root, norm, prev);
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
    _rootHandle = null;
    _previousDiskContentByResPath.clear();
  }
}

GodotFolderSyncBackend createGodotFolderSyncBackend() => GodotFolderSyncWebImpl();
