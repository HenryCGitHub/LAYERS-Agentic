import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'local_gdd_sync_service.dart';

/// Web File System Access API (`showSaveFilePicker`) + IndexedDB handle persistence
/// using Dart 3 `dart:js_interop` with zero extra plugins.
class LocalGddFileBackendWeb implements LocalGddFileBackend {
  static const String _dbName = 'layers_local_gdd_handles';
  static const String _storeName = 'handles';
  static const int _dbVersion = 1;

  final Map<String, JSObject> _handles = <String, JSObject>{};

  @override
  bool get isSupported {
    try {
      return globalContext.has('showSaveFilePicker') &&
          globalContext.has('indexedDB');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<LocalGddLinkResult> pickAndWriteFile({
    required String projectId,
    required String suggestedFilename,
    required String content,
  }) async {
    if (!isSupported) {
      return LocalGddLinkResult(
        linked: false,
        fellBackToDownload: true,
        filename: suggestedFilename,
      );
    }
    try {
      final options = <String, Object?>{
        'suggestedName': suggestedFilename,
        'types': <Object?>[
          <String, Object?>{
            'description': 'Markdown CoPilot GDD',
            'accept': <String, Object?>{
              'text/markdown': <String>['.md'],
            },
          },
        ],
      }.jsify();
      final handle = await globalContext
          .callMethod<JSPromise<JSObject>>('showSaveFilePicker'.toJS, options)
          .toDart;
      await _writeHandle(handle, content);
      _handles[projectId] = handle;
      await _putHandle(projectId, handle);
      final name = _handleFilename(handle, fallback: suggestedFilename);
      return LocalGddLinkResult(linked: true, filename: name);
    } catch (e) {
      final text = e.toString();
      if (text.contains('AbortError') || text.contains('aborted')) {
        return const LocalGddLinkResult(linked: false, cancelled: true);
      }
      return LocalGddLinkResult(linked: false, error: text);
    }
  }

  @override
  Future<String?> restoreLinkedFilename(String projectId) async {
    final cached = _handles[projectId];
    if (cached != null) {
      return _handleFilename(cached);
    }
    final stored = await _getHandle(projectId);
    if (stored == null) return null;
    _handles[projectId] = stored;
    return _handleFilename(stored);
  }

  @override
  Future<LocalGddWriteResult> writeLinkedFile({
    required String projectId,
    required String content,
    bool requestPermissionIfNeeded = false,
  }) async {
    try {
      var handle = _handles[projectId];
      handle ??= await _getHandle(projectId);
      if (handle == null) {
        return const LocalGddWriteResult(
          written: false,
          error: 'No linked local GDD file handle.',
        );
      }
      _handles[projectId] = handle;

      final permOpts = <String, Object?>{'mode': 'readwrite'}.jsify();
      var state = (await handle
              .callMethod<JSPromise<JSString>>('queryPermission'.toJS, permOpts)
              .toDart)
          .toDart;
      if (state != 'granted' && requestPermissionIfNeeded) {
        state = (await handle
                .callMethod<JSPromise<JSString>>(
                  'requestPermission'.toJS,
                  permOpts,
                )
                .toDart)
            .toDart;
      }
      if (state != 'granted') {
        return const LocalGddWriteResult(
          written: false,
          permissionDenied: true,
        );
      }
      await _writeHandle(handle, content);
      return const LocalGddWriteResult(written: true);
    } catch (e) {
      return LocalGddWriteResult(written: false, error: e.toString());
    }
  }

  @override
  Future<void> unlinkProject(String projectId) async {
    _handles.remove(projectId);
    await _deleteHandle(projectId);
  }

  String _handleFilename(JSObject handle, {String fallback = 'copilot_gdd.md'}) {
    try {
      final raw = handle['name'];
      if (raw.isDefinedAndNotNull && raw.typeofEquals('string')) {
        final name = (raw as JSString).toDart.trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> _writeHandle(JSObject handle, String content) async {
    final writable = await handle
        .callMethod<JSPromise<JSObject>>('createWritable'.toJS)
        .toDart;
    try {
      await writable
          .callMethod<JSPromise<JSAny?>>('write'.toJS, content.toJS)
          .toDart;
    } finally {
      await writable.callMethod<JSPromise<JSAny?>>('close'.toJS).toDart;
    }
  }

  Future<JSObject?> _openDb() async {
    try {
      final idb = globalContext['indexedDB'];
      if (!idb.isDefinedAndNotNull || !idb.typeofEquals('object')) return null;
      final req = (idb as JSObject)
          .callMethod<JSObject>('open'.toJS, _dbName.toJS, _dbVersion.toJS);
      final completer = Completer<JSObject?>();
      req['onupgradeneeded'] = ((JSObject event) {
        try {
          final target = event['target'];
          if (!target.isDefinedAndNotNull || !target.typeofEquals('object')) {
            return;
          }
          final db = (target as JSObject)['result'];
          if (!db.isDefinedAndNotNull || !db.typeofEquals('object')) return;
          final dbObj = db as JSObject;
          final stores = dbObj['objectStoreNames'];
          final hasStore = stores.isDefinedAndNotNull &&
              stores.typeofEquals('object') &&
              (stores as JSObject)
                  .callMethod<JSBoolean>('contains'.toJS, _storeName.toJS)
                  .toDart;
          if (!hasStore) {
            dbObj.callMethod<JSAny?>('createObjectStore'.toJS, _storeName.toJS);
          }
        } catch (_) {}
      }).toJS;
      req['onsuccess'] = ((JSAny? _) {
        if (completer.isCompleted) return;
        final res = req['result'];
        completer.complete(
          res.isDefinedAndNotNull && res.typeofEquals('object')
              ? res as JSObject
              : null,
        );
      }).toJS;
      req['onerror'] = ((JSAny? _) {
        if (!completer.isCompleted) completer.complete(null);
      }).toJS;
      return completer.future;
    } catch (_) {
      return null;
    }
  }

  Future<void> _putHandle(String projectId, JSObject handle) =>
      _runReadWriteOp((store) {
        store.callMethod<JSObject>('put'.toJS, handle, projectId.toJS);
      });

  Future<void> _deleteHandle(String projectId) => _runReadWriteOp((store) {
        store.callMethod<JSObject>('delete'.toJS, projectId.toJS);
      });

  Future<void> _runReadWriteOp(void Function(JSObject store) op) async {
    final db = await _openDb();
    if (db == null) return;
    try {
      final completer = Completer<void>();
      final tx = db.callMethod<JSObject>(
        'transaction'.toJS,
        _storeName.toJS,
        'readwrite'.toJS,
      );
      final store =
          tx.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
      op(store);
      final onDone = ((JSAny? _) {
        if (!completer.isCompleted) completer.complete();
      }).toJS;
      tx['oncomplete'] = onDone;
      tx['onerror'] = onDone;
      tx['onabort'] = onDone;
      await completer.future;
    } catch (_) {
    } finally {
      try {
        db.callMethod<JSAny?>('close'.toJS);
      } catch (_) {}
    }
  }

  Future<JSObject?> _getHandle(String projectId) async {
    final db = await _openDb();
    if (db == null) return null;
    try {
      final completer = Completer<JSObject?>();
      final tx = db.callMethod<JSObject>(
        'transaction'.toJS,
        _storeName.toJS,
        'readonly'.toJS,
      );
      final store =
          tx.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
      final req = store.callMethod<JSObject>('get'.toJS, projectId.toJS);
      req['onsuccess'] = ((JSAny? _) {
        if (completer.isCompleted) return;
        final res = req['result'];
        completer.complete(
          res.isDefinedAndNotNull && res.typeofEquals('object')
              ? res as JSObject
              : null,
        );
      }).toJS;
      req['onerror'] = ((JSAny? _) {
        if (!completer.isCompleted) completer.complete(null);
      }).toJS;
      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      try {
        db.callMethod<JSAny?>('close'.toJS);
      } catch (_) {}
    }
  }
}

LocalGddFileBackend createLocalGddFileBackend() => LocalGddFileBackendWeb();
