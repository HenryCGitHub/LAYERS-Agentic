import 'godot_folder_sync_interface.dart';

/// Fallback no-op folder sync backend for unsupported targets.
class GodotFolderSyncStubImpl implements GodotFolderSyncBackend {
  @override
  bool get isSupported => false;

  @override
  String get unsupportedReason =>
      'Direct Godot folder access is available in Chromium desktop browsers (Chrome/Edge) or desktop builds.';

  @override
  bool get isLinked => false;

  @override
  String get linkedFolderLabel => '';

  @override
  Future<GodotFolderSnapshot> linkAndPullFolder({String? directoryPath}) async {
    return GodotFolderSnapshot(
      folderLabel: '',
      errorMessage: unsupportedReason,
    );
  }

  @override
  Future<GodotFolderSnapshot> refreshLinkedFolder() async {
    return GodotFolderSnapshot(
      folderLabel: '',
      errorMessage: unsupportedReason,
    );
  }

  @override
  Future<String?> readDiskFile(String resPath) async => null;

  @override
  Future<GodotWriteResult> writeAllowedFile({
    required String resPath,
    required String content,
  }) async {
    return GodotWriteResult(
      success: false,
      resPath: resPath,
      message: unsupportedReason,
    );
  }

  @override
  bool canUndo(String resPath) => false;

  @override
  String? previousDiskContent(String resPath) => null;

  @override
  Future<GodotWriteResult> undoLastWrite(String resPath) async {
    return GodotWriteResult(
      success: false,
      resPath: resPath,
      message: unsupportedReason,
    );
  }

  @override
  void unlink() {}
}

GodotFolderSyncBackend createGodotFolderSyncBackend() => GodotFolderSyncStubImpl();
