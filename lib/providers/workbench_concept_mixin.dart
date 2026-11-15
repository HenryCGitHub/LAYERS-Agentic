part of 'workbench_provider.dart';

/// Stage 1 actions: Spark Onboarding, Preset Packs, Target Engine toggle,
/// Co-Designer live edits, and `Approve & Launch Unreal Workbench`.
extension WorkbenchConceptMixin on WorkbenchProvider {
  void showSparkPicker() {
    _showingSparkPicker = true;
    _currentStage = WorkbenchStage.projectPitch;
    notifyListeners();
  }

  void resumeActiveRootSpec() {
    if (_conceptDraft == null) return;
    _showingSparkPicker = false;
    _currentStage = WorkbenchStage.projectPitch;
    notifyListeners();
  }

  void _ensureActiveProjectDocument(ProjectConceptBlueprint bp) {
    final pid = _activeProjectId ?? 'proj_${DateTime.now().millisecondsSinceEpoch}';
    _activeProjectId = pid;
    final existing = documents[pid];
    final nextSections = Map<String, String>.from(
      existing?.sections ?? const <String, String>{},
    );
    nextSections['concept_blueprint_json'] = jsonEncode(bp.toJson());
    nextSections['engine'] = bp.targetEngine.shortLabel;
    nextSections['current_stage'] = _currentStage.name;

    final updated = (existing ??
            TierDocument(
              id: pid,
              title: bp.normalizedTitle,
              tier: TierType.project,
              childrenIds: const <String>[],
            ))
        .copyWith(
          title: bp.normalizedTitle,
          tier: TierType.project,
          sections: nextSections,
        );
    documents[pid] = updated;
    _persistDocument(updated);
    _persistSettings();
  }

  void loadPresetSpark(String presetId) {
    final preset = UnrealSparkPresets.byId(presetId);
    preset.targetEngine = _conceptDraft?.targetEngine ?? UnrealTargetEngine.ue5Mcp;
    _conceptDraft = preset;
    _showingSparkPicker = false;
    _showRawRootContext = false;
    _currentStage = WorkbenchStage.projectPitch;
    _ensureActiveProjectDocument(preset);
    notifyListeners();
  }

  Future<ProjectConceptBlueprint?> generateSpecFromSpark(
    String sparkPrompt,
  ) async {
    final cleanPrompt = sparkPrompt.trim();
    if (cleanPrompt.isEmpty) return null;

    _isAgentBusy = true;
    _agentProgressStep = 'Drafting Unreal Root Spec (PROJECT_SPEC.md)...';
    _offlineErrorMessage = null;
    notifyListeners();

    try {
      final drafted = await ProjectConceptAgent.draftSpecFromSpark(
        sparkPrompt: cleanPrompt,
        apiKey: _apiKey,
        targetEngine: _conceptDraft?.targetEngine ?? UnrealTargetEngine.ue5Mcp,
        preferredModel: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      _conceptDraft = drafted;
      _showingSparkPicker = false;
      _showRawRootContext = false;
      _currentStage = WorkbenchStage.projectPitch;
      _ensureActiveProjectDocument(drafted);
      return drafted;
    } catch (e) {
      _offlineErrorMessage = 'Spec generation error: $e';
      return null;
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  Future<ProjectConceptBlueprint?> applyStage1CoDesignInstruction(
    String instruction,
  ) async {
    final draft = _conceptDraft;
    final clean = instruction.trim();
    if (draft == null || clean.isEmpty) return null;

    _isAgentBusy = true;
    _agentProgressStep = 'Co-Designer updating ROOT_MCP_CONTEXT...';
    _offlineErrorMessage = null;
    notifyListeners();

    try {
      final updated = await ProjectConceptAgent.applyCoDesignEdit(
        currentSpec: draft,
        instruction: clean,
        apiKey: _apiKey,
        preferredModel: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      _conceptDraft = updated;
      _ensureActiveProjectDocument(updated);
      return updated;
    } catch (e) {
      _offlineErrorMessage = 'Co-Designer edit error: $e';
      return null;
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  void setTargetEngine(UnrealTargetEngine target) {
    final draft = _conceptDraft;
    if (draft == null) {
      _conceptDraft = ProjectConceptBlueprint(targetEngine: target);
    } else {
      draft.targetEngine = target;
    }
    if (activeProject != null && _conceptDraft != null) {
      _ensureActiveProjectDocument(_conceptDraft!);
    }
    notifyListeners();
  }

  void selectCameraDecisionOption(String optionId) {
    final draft = _conceptDraft;
    if (draft == null) return;
    for (final opt in draft.cameraDecisionOptions) {
      if (opt.id == optionId) {
        draft.cameraChoiceId = opt.id;
        draft.cameraContract = opt.contractValue;
        draft.lastCoDesignNote =
            'Camera contract set to ${opt.label}.';
        _ensureActiveProjectDocument(draft);
        notifyListeners();
        return;
      }
    }
  }

  void updateRootSpecSections({
    String? gameTitle,
    String? pitch,
    String? cameraContract,
    String? characterScale,
    String? inputContract,
    String? assetPolicy,
    String? releaseDoneWhen,
    List<String>? coreLoop,
    List<String>? pillars,
    List<String>? outOfScope,
  }) {
    final draft = _conceptDraft;
    if (draft == null) return;
    if (gameTitle != null && gameTitle.trim().isNotEmpty) {
      draft.gameTitle = gameTitle.trim().toUpperCase();
    }
    if (pitch != null) draft.pitch = pitch.trim();
    if (cameraContract != null) draft.cameraContract = cameraContract.trim();
    if (characterScale != null) draft.characterScale = characterScale.trim();
    if (inputContract != null) draft.inputContract = inputContract.trim();
    if (assetPolicy != null) draft.assetPolicy = assetPolicy.trim();
    if (releaseDoneWhen != null) draft.releaseDoneWhen = releaseDoneWhen.trim();
    if (coreLoop != null) draft.coreLoop = coreLoop;
    if (pillars != null) draft.pillars = pillars;
    if (outOfScope != null) draft.outOfScope = outOfScope;
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  /// Approves `PROJECT_SPEC.md` and materializes strict `v0.1 · Prototype` release + 6-section Epics,
  /// transitioning straight to Stage 2 (`2. Epic Specs`).
  String? approveRootSpecAndLaunchWorkbench() {
    var draft = _conceptDraft;
    if (draft == null) return null;
    draft = UnrealSpecGuard.sanitizeConceptBlueprint(draft);
    draft.approved = true;
    _conceptDraft = draft;

    final pid = _activeProjectId ?? 'proj_${DateTime.now().millisecondsSinceEpoch}';
    _activeProjectId = pid;
    _ensureActiveProjectDocument(draft);
    final proj = documents[pid]!;

    // Reuse existing v0.1 release if present cleanly, or create fresh v0.1 Prototype
    TierDocument? v01Rel;
    for (final rid in proj.childrenIds) {
      final candidate = documents[rid];
      if (candidate != null &&
          candidate.tier == TierType.release &&
          releaseVersionTagFor(candidate) == 'v0.1') {
        v01Rel = candidate;
        break;
      }
    }

    final relId = v01Rel?.id ?? '${pid}_rel_v01';
    final epicIds = <String>[];

    if (v01Rel == null || epicDocsForRelease(relId).isEmpty) {
      for (int i = 0; i < draft.initialEpics.length; i++) {
        final rawEpic = draft.initialEpics[i];
        final epId = '${relId}_epic_${i + 1}';
        final cleanEpic = rawEpic.deepCopy(
          idOverride: epId,
          releaseVersionOverride: 'v0.1',
          lifecycleOverride:
              i == 0 ? EpicLifecycle.active : EpicLifecycle.queued,
        );
        cleanEpic.code = 'E0${i + 1}';
        cleanEpic.lineageKey = 'e0${i + 1}';
        final epDoc = cleanEpic.toTierDocument(
          docId: epId,
          parentReleaseId: relId,
        );
        documents[epId] = epDoc;
        _persistDocument(epDoc);
        epicIds.add(epId);
      }
    } else {
      for (final d in epicDocsForRelease(relId)) {
        epicIds.add(d.id);
      }
    }

    final relDoc = TierDocument(
      id: relId,
      title: 'v0.1 · Prototype',
      tier: TierType.release,
      parentId: pid,
      childrenIds: epicIds,
      estimatedDuration: '${epicIds.length} Epics',
      sections: <String, String>{
        'release_version': 'v0.1',
        'goal': draft.pitch,
        'doneWhen': draft.releaseDoneWhen,
      },
    );
    documents[relId] = relDoc;
    _persistDocument(relDoc);

    if (!proj.childrenIds.contains(relId)) {
      proj.childrenIds = [relId, ...proj.childrenIds];
    }
    _activeReleaseId = relId;
    _selectedEpicId = epicIds.isNotEmpty ? epicIds.first : null;
    _currentStage = WorkbenchStage.releaseWorkbench;
    _showRawEpicPayload = false;
    _syncActiveProjectMetadata();
    notifyListeners();
    return relId;
  }
}
