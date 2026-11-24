import 'dart:async';

import '../utils/markdown_exporter.dart';
import 'local_gdd_sync_stub.dart'
    if (dart.library.js_interop) 'local_gdd_sync_web.dart';

/// Live state of the optional local `*_copilot_gdd.md` file link for a Project.
enum LocalGddSyncStatus {
  unlinked,
  linked,
  syncing,
  synced,
  permissionNeeded,
  fallbackDownloaded,
  error,
}

/// Outcome returned when linking a local `*_copilot_gdd.md` file.
class LocalGddLinkResult {
  final bool linked;
  final bool fellBackToDownload;
  final bool cancelled;
  final String? filename;
  final String? error;

  const LocalGddLinkResult({
    required this.linked,
    this.fellBackToDownload = false,
    this.cancelled = false,
    this.filename,
    this.error,
  });
}

/// Outcome returned when auto-writing a linked local GDD file.
class LocalGddWriteResult {
  final bool written;
  final bool permissionDenied;
  final String? error;

  const LocalGddWriteResult({
    required this.written,
    this.permissionDenied = false,
    this.error,
  });
}

/// Platform backend contract for linking and delta-writing a local GDD file.
abstract class LocalGddFileBackend {
  bool get isSupported;

  Future<LocalGddLinkResult> pickAndWriteFile({
    required String projectId,
    required String suggestedFilename,
    required String content,
  });

  Future<String?> restoreLinkedFilename(String projectId);

  Future<LocalGddWriteResult> writeLinkedFile({
    required String projectId,
    required String content,
    bool requestPermissionIfNeeded = false,
  });

  Future<void> unlinkProject(String projectId);
}

/// Manages per-project local `*_copilot_gdd.md` linking and delta-only writes
/// with graceful download fallback on browsers without File System Access API.
class LocalGddSyncService {
  final LocalGddFileBackend _backend;
  final Map<String, String> _lastWrittenByProject = <String, String>{};
  final Map<String, Future<void>> _writeQueues = <String, Future<void>>{};

  LocalGddSyncService({LocalGddFileBackend? backend})
      : _backend = backend ?? createLocalGddFileBackend();

  bool get isSupported => _backend.isSupported;

  bool hasDelta(String projectId, String content) =>
      _lastWrittenByProject[projectId] != content;

  /// Serializes per-project file writes/unlinks so concurrent calls never overlap
  /// and a failed task never poisons subsequent queued operations.
  Future<T> _enqueueWrite<T>(
    String projectId,
    Future<T> Function() task,
  ) {
    final prev = _writeQueues[projectId] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> next;
    next = prev.catchError((Object _) {}).then((_) async {
      try {
        final result = await task();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      } finally {
        if (identical(_writeQueues[projectId], next)) {
          _writeQueues.remove(projectId);
        }
      }
    });
    _writeQueues[projectId] = next;
    return completer.future;
  }

  /// Opens the local save picker (when supported) or falls back to direct file download.
  Future<LocalGddLinkResult> linkProjectFile({
    required String projectId,
    required String suggestedFilename,
    required String content,
  }) async {
    if (!_backend.isSupported) {
      triggerMarkdownFileDownload(
        filename: suggestedFilename,
        content: content,
      );
      return LocalGddLinkResult(
        linked: false,
        fellBackToDownload: true,
        filename: suggestedFilename,
      );
    }

    return _enqueueWrite(projectId, () async {
      final result = await _backend.pickAndWriteFile(
        projectId: projectId,
        suggestedFilename: suggestedFilename,
        content: content,
      );
      if (result.linked) {
        _lastWrittenByProject[projectId] = content;
      }
      return result;
    });
  }

  /// Restores a previously linked filename handle for [projectId], if persisted.
  Future<String?> restoreLinkedFilename(String projectId) =>
      _backend.restoreLinkedFilename(projectId);

  /// Writes [content] only when it differs from the last written GDD string (unless [force] is true).
  Future<LocalGddWriteResult> syncIfChanged({
    required String projectId,
    required String content,
    bool force = false,
    bool requestPermissionIfNeeded = false,
  }) =>
      _enqueueWrite(projectId, () async {
        if (!force && !hasDelta(projectId, content)) {
          return const LocalGddWriteResult(written: false);
        }
        final result = await _backend.writeLinkedFile(
          projectId: projectId,
          content: content,
          requestPermissionIfNeeded: requestPermissionIfNeeded,
        );
        if (result.written) {
          _lastWrittenByProject[projectId] = content;
        }
        return result;
      });

  /// Removes any cached hash and stored file handle for [projectId].
  Future<void> unlinkProject(String projectId) =>
      _enqueueWrite(projectId, () async {
        _lastWrittenByProject.remove(projectId);
        await _backend.unlinkProject(projectId);
      });
}
