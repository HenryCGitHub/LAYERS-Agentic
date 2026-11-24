part of 'workbench_provider.dart';

/// Ultimate Engine CoPilot GDD & Feature / `[FIX]` prompt export helpers.
extension WorkbenchCopilotMixin on WorkbenchProvider {
  UnrealArchitectureMode get unrealArchitectureMode {
    if (_conceptDraft != null) {
      return _conceptDraft!.architectureMode;
    }
    final raw = activeProject?.sections['unreal_arch_mode'];
    if (raw != null && raw.trim().isNotEmpty) {
      return UnrealArchitectureMode.fromString(raw);
    }
    return UnrealArchitectureMode.blueprint;
  }

  String get activeRootUnrealMarkdown {
    final spec = _conceptDraft;
    if (spec == null) {
      return '# ROOT_UNREAL_CONTEXT\nNo Project Spec drafted yet.';
    }
    return UnrealContextBuilder.buildRootUnrealContext(
      spec,
      mode: unrealArchitectureMode,
    );
  }

  /// Returns the CoPilot context prompt for the selected Project, Epic, or Feature.
  String activeCoPilotPrompt({
    EpicSpec? epicOverride,
    FeatureSpec? featureOverride,
  }) {
    final epic = epicOverride ?? selectedEpicSpec;
    if (epic == null) {
      return activeRootUnrealMarkdown;
    }
    final feat = featureOverride ??
        (epicOverride == null ? selectedFeatureSpec : null);
    if (feat != null) {
      return activeFeatureBuildPrompt(epic, feat);
    }
    return activeEpicArchitecturePrompt(epic);
  }

  /// Builds filename + Ultimate Engine CoPilot GDD Markdown (`*_copilot_gdd.md`).
  ({String filename, String content}) buildCoPilotGddExport() {
    final rootSpec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'layers_project',
        );
    final epicsByRelease = <String, List<EpicSpec>>{
      for (final rel in projectReleases)
        releaseDisplayName(rel): epicsForRelease(rel.id),
    };
    return (
      filename: buildCoPilotGddFilename(rootSpec.normalizedTitle),
      content: UnrealContextBuilder.buildCoPilotGddMarkdown(
        rootSpec: rootSpec,
        epicsByReleaseLabel: epicsByRelease,
        mode: unrealArchitectureMode,
      ),
    );
  }

  /// Builds filename + full structured project Markdown across all releases, Epics, and Features.
  ({String filename, String content}) buildFullProjectMarkdownExport() {
    final rootSpec = _conceptDraft ??
        ProjectConceptBlueprint(
          gameTitle: activeProject?.title ?? 'layers_project',
        );
    final epicsByRelease = <String, List<EpicSpec>>{
      for (final rel in projectReleases)
        releaseDisplayName(rel): epicsForRelease(rel.id),
    };
    return (
      filename: buildProjectSpecFilename(rootSpec.normalizedTitle),
      content: UnrealContextBuilder.buildFullProjectSpecMarkdown(
        rootSpec: rootSpec,
        epicsByReleaseLabel: epicsByRelease,
        mode: unrealArchitectureMode,
      ),
    );
  }

  /// Opens the local Save File Picker (or downloads on unsupported browsers) and links `*_copilot_gdd.md`.
  Future<LocalGddLinkResult> linkLocalGddFile() async {
    final projId = _activeProjectId;
    if (projId == null) {
      return const LocalGddLinkResult(
        linked: false,
        error: 'No active project to link.',
      );
    }
    final prevStatus = _gddSyncStatus;
    _gddSyncStatus = LocalGddSyncStatus.syncing;
    _gddSyncError = null;
    notifyListeners();

    final bundle = buildCoPilotGddExport();
    final res = await _localGddSync.linkProjectFile(
      projectId: projId,
      suggestedFilename: bundle.filename,
      content: bundle.content,
    );
    if (_isDisposed) return res;

    if (res.cancelled) {
      _gddSyncStatus =
          isLocalGddLinked ? prevStatus : LocalGddSyncStatus.unlinked;
    } else if (res.fellBackToDownload) {
      _linkedGddProjectId = null;
      _linkedGddFileName = res.filename ?? bundle.filename;
      _gddSyncStatus = LocalGddSyncStatus.fallbackDownloaded;
      _gddSyncError = null;
    } else if (res.linked) {
      _linkedGddProjectId = projId;
      _linkedGddFileName = res.filename ?? bundle.filename;
      _gddSyncStatus = LocalGddSyncStatus.synced;
      _lastGddSyncAt = DateTime.now();
      _gddSyncError = null;
    } else {
      _gddSyncStatus = LocalGddSyncStatus.error;
      _gddSyncError = res.error ?? 'Could not link local GDD file.';
    }
    notifyListeners();
    return res;
  }

  /// Detaches the linked local `*_copilot_gdd.md` handle for the active project.
  Future<void> unlinkLocalGddFile() async {
    _localGddDebounceTimer?.cancel();
    final projId = _activeProjectId;
    _linkedGddProjectId = null;
    _linkedGddFileName = null;
    _gddSyncStatus = LocalGddSyncStatus.unlinked;
    _lastGddSyncAt = null;
    _gddSyncError = null;
    notifyListeners();
    if (projId != null) {
      await _localGddSync.unlinkProject(projId);
    }
  }

  /// Writes `*_copilot_gdd.md` to the linked local handle only when its compiled output changed.
  Future<bool> syncLinkedGddNow({
    bool force = false,
    bool requestPermissionIfNeeded = false,
  }) async {
    final projId = _activeProjectId;
    if (_isDisposed ||
        projId == null ||
        !isLocalGddLinked ||
        _linkedGddProjectId != projId) {
      return false;
    }
    final bundle = buildCoPilotGddExport();
    if (!force && !_localGddSync.hasDelta(projId, bundle.content)) {
      return false;
    }

    _gddSyncStatus = LocalGddSyncStatus.syncing;
    notifyListeners();

    final res = await _localGddSync.syncIfChanged(
      projectId: projId,
      content: bundle.content,
      force: force,
      requestPermissionIfNeeded: requestPermissionIfNeeded,
    );
    if (_isDisposed || _activeProjectId != projId) return false;

    if (res.permissionDenied) {
      _gddSyncStatus = LocalGddSyncStatus.permissionNeeded;
      _gddSyncError = 'Permission needed to write local GDD file.';
      notifyListeners();
      return false;
    }
    if (res.error != null) {
      _gddSyncStatus = LocalGddSyncStatus.error;
      _gddSyncError = res.error;
      notifyListeners();
      return false;
    }
    if (res.written) {
      _gddSyncStatus = LocalGddSyncStatus.synced;
      _lastGddSyncAt = DateTime.now();
      _gddSyncError = null;
      notifyListeners();
      return true;
    }
    return false;
  }

  void _scheduleLinkedGddSync() {
    if (_isDisposed ||
        !isLocalGddLinked ||
        _activeProjectId == null ||
        _linkedGddProjectId != _activeProjectId) {
      return;
    }
    _localGddDebounceTimer?.cancel();
    if (!enableAutoLoad) {
      unawaited(syncLinkedGddNow());
      return;
    }
    _localGddDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(syncLinkedGddNow());
    });
  }

  Future<void> _restoreLocalGddLinkForActiveProject() async {
    if (_isDisposed) return;
    final projId = _activeProjectId;
    if (projId != null &&
        projId == _linkedGddProjectId &&
        _linkedGddFileName != null &&
        _linkedGddFileName!.isNotEmpty) {
      return;
    }
    _localGddDebounceTimer?.cancel();
    _linkedGddProjectId = projId;
    _linkedGddFileName = null;
    _gddSyncStatus = LocalGddSyncStatus.unlinked;
    _lastGddSyncAt = null;
    _gddSyncError = null;
    if (projId == null || !isLocalGddLinkSupported) return;

    final restored = await _localGddSync.restoreLinkedFilename(projId);
    if (_isDisposed ||
        _activeProjectId != projId ||
        restored == null ||
        restored.trim().isEmpty) {
      return;
    }
    _linkedGddProjectId = projId;
    _linkedGddFileName = restored.trim();
    _gddSyncStatus = LocalGddSyncStatus.linked;
    notifyListeners();
  }
}
