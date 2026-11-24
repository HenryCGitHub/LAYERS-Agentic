import 'local_gdd_sync_service.dart';

/// Safe non-Web stub for platforms without browser File System Access API.
class LocalGddFileBackendStub implements LocalGddFileBackend {
  @override
  bool get isSupported => false;

  @override
  Future<LocalGddLinkResult> pickAndWriteFile({
    required String projectId,
    required String suggestedFilename,
    required String content,
  }) async =>
      LocalGddLinkResult(
        linked: false,
        fellBackToDownload: true,
        filename: suggestedFilename,
      );

  @override
  Future<String?> restoreLinkedFilename(String projectId) async => null;

  @override
  Future<LocalGddWriteResult> writeLinkedFile({
    required String projectId,
    required String content,
    bool requestPermissionIfNeeded = false,
  }) async =>
      const LocalGddWriteResult(written: false);

  @override
  Future<void> unlinkProject(String projectId) async {}
}

LocalGddFileBackend createLocalGddFileBackend() => LocalGddFileBackendStub();
