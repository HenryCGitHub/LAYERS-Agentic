import '../models/godot_virtual_file.dart';

/// Snapshot returned after reading a linked local Godot 4 project folder.
class GodotFolderSnapshot {
  final String folderLabel;
  final String? projectGodotText;
  final Map<String, String> filesByResPath;
  final String? errorMessage;

  const GodotFolderSnapshot({
    required this.folderLabel,
    this.projectGodotText,
    this.filesByResPath = const {},
    this.errorMessage,
  });

  bool get ok => errorMessage == null || errorMessage!.isEmpty;
}

/// Outcome of a diff-gated disk write or Undo operation.
class GodotWriteResult {
  final bool success;
  final String resPath;
  final String message;
  final bool canUndo;

  const GodotWriteResult({
    required this.success,
    required this.resPath,
    required this.message,
    this.canUndo = false,
  });
}

/// Shared guard ensuring disk writes can only touch `.gd` scripts and `.tres` resources inside the project.
bool isSafeWritableGodotResPath(String resPath) {
  final norm = GodotVirtualFile.normalizeResPath(resPath);
  if (norm.isEmpty || norm.contains('..')) return false;
  final lower = norm.toLowerCase();
  return lower.endsWith('.gd') || lower.endsWith('.tres');
}

/// Cross-platform backend interface for safe read-only pull & diff-gated local Godot folder sync.
abstract class GodotFolderSyncBackend {
  bool get isSupported;
  String get unsupportedReason;
  bool get isLinked;
  String get linkedFolderLabel;

  /// Links a Godot project folder (verifying `project.godot` exists at root) and reads `.gd`/`.tres` + `project.godot`.
  Future<GodotFolderSnapshot> linkAndPullFolder({String? directoryPath});

  /// Re-reads the currently linked Godot folder from disk.
  Future<GodotFolderSnapshot> refreshLinkedFolder();

  /// Reads the current on-disk contents of a single `res://` file if present.
  Future<String?> readDiskFile(String resPath);

  /// Writes `.gd` or `.tres` to disk after capturing an in-session Undo snapshot; rejects `.tscn`/`project.godot`.
  Future<GodotWriteResult> writeAllowedFile({
    required String resPath,
    required String content,
  });

  bool canUndo(String resPath);
  String? previousDiskContent(String resPath);

  /// Restores the exact pre-write on-disk text (or deletes newly created file if it did not exist before).
  Future<GodotWriteResult> undoLastWrite(String resPath);

  void unlink();
}
