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
    for (final opt in draft.effectiveCameraDecisionOptions) {
      if (opt.id == optionId) {
        draft.cameraChoiceId = opt.id;
        draft.cameraContract = opt.contractValue;
        ProjectConceptAgent.syncEpicCameraFraming(
          draft,
          optionId: opt.id,
          contractValue: opt.contractValue,
        );
        draft.lastCoDesignNote =
            'Camera contract & E01 look framing set to ${opt.label}.';
        _ensureActiveProjectDocument(draft);
        notifyListeners();
        return;
      }
    }
  }

  void selectCoreFeelOption(String feelId) {
    final draft = _conceptDraft;
    if (draft == null) return;
    final chosen = ProjectConceptBlueprint.coreFeelOptionById(feelId);
    ProjectConceptAgent.syncEpicCoreFeel(draft, feelId: chosen.id);
    draft.lastCoDesignNote =
        'Core feel & E01 locomotion set to ${chosen.label}.';
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  /// Clears the active unapproved draft back to empty Stage 1 intake, or opens a fresh Stage 1
  /// project when existing approved Releases exist so saved project work is preserved.
  void resetStage1ToNewIdea() {
    final target = targetEngine;
    if (projectReleases.isNotEmpty) {
      createNewProject();
      setTargetEngine(target);
      return;
    }
    final orphanId = _activeProjectId;
    if (orphanId != null) {
      _persistTimers.remove(orphanId)?.cancel();
      documents.remove(orphanId);
      LocalVaultService.deleteDocument(orphanId);
      final user = _authService.currentUser;
      if (user != null) {
        _firestoreService.deleteDocument(uid: user.uid, docId: orphanId);
      }
    }
    _activeProjectId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    _activeReleaseId = null;
    _selectedEpicId = null;
    _progressiveDraft = null;
    _executionLog.clear();
    _conceptDraft = ProjectConceptBlueprint(targetEngine: target);
    _showingSparkPicker = true;
    _showRawRootContext = false;
    _showRawEpicPayload = false;
    _offlineErrorMessage = null;
    _currentStage = WorkbenchStage.projectPitch;
    _persistSettings();
    notifyListeners();
  }

  void _renumberInitialEpics(ProjectConceptBlueprint draft) {
    for (int i = 0; i < draft.initialEpics.length; i++) {
      final ep = draft.initialEpics[i];
      ep.code = 'E${(i + 1).toString().padLeft(2, '0')}';
      if (ep.lineageKey.trim().isEmpty) {
        ep.lineageKey = 'epic_${i + 1}';
      }
      if (!ep.isPassed &&
          ep.lifecycle != EpicLifecycle.upgrading &&
          ep.lifecycle != EpicLifecycle.newEpic) {
        ep.lifecycle = i == 0 ? EpicLifecycle.active : EpicLifecycle.queued;
      }
    }
  }

  /// Reorders a Stage 1 `§05` prototype Epic (`delta = -1` up, `+1` down) while keeping `id` & `lineageKey`.
  void moveInitialEpic(int index, int delta) {
    final draft = _conceptDraft;
    if (draft == null) return;
    final newIndex = index + delta;
    if (index < 0 ||
        index >= draft.initialEpics.length ||
        newIndex < 0 ||
        newIndex >= draft.initialEpics.length ||
        newIndex == index) {
      return;
    }
    final moved = draft.initialEpics.removeAt(index);
    draft.initialEpics.insert(newIndex, moved);
    _renumberInitialEpics(draft);
    draft.lastCoDesignNote =
        'Reordered §05 queue: ${moved.title} -> ${moved.code}.';
    _ensureActiveProjectDocument(draft);
    notifyListeners();
  }

  /// Prunes a Stage 1 `§05` prototype Epic (keeping at least 1 Epic in `v0.1`).
  void removeInitialEpicAt(int index) {
    final draft = _conceptDraft;
    if (draft == null ||
        draft.initialEpics.length <= 1 ||
        index < 0 ||
        index >= draft.initialEpics.length) {
      return;
    }
    final removed = draft.initialEpics.removeAt(index);
    _renumberInitialEpics(draft);
    draft.lastCoDesignNote = 'Removed ${removed.title} from Stage 1 §05.';
    _ensureActiveProjectDocument(draft);
    notifyListeners();
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

  /// Approves `PROJECT_SPEC.md` and materializes or non-destructively reconciles `v0.1 · Prototype` Epics,
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
    final existingDocs = epicDocsForRelease(relId);

    if (v01Rel == null || existingDocs.isEmpty) {
      for (int i = 0; i < draft.initialEpics.length; i++) {
        final rawEpic = draft.initialEpics[i];
        final epId = '${relId}_epic_${i + 1}';
        final cleanEpic = rawEpic.deepCopy(
          idOverride: epId,
          releaseVersionOverride: 'v0.1',
          lifecycleOverride:
              i == 0 ? EpicLifecycle.active : EpicLifecycle.queued,
        );
        cleanEpic.code = 'E${(i + 1).toString().padLeft(2, '0')}';
        cleanEpic.lineageKey = rawEpic.lineageKey.trim().isEmpty
            ? EpicSpec.formatLineageKey(i + 1)
            : rawEpic.lineageKey.trim();
        final epDoc = cleanEpic.toTierDocument(
          docId: epId,
          parentReleaseId: relId,
        );
        documents[epId] = epDoc;
        _persistDocument(epDoc);
        epicIds.add(epId);
      }
    } else {
      final existingSpecs = [
        for (int i = 0; i < existingDocs.length; i++)
          EpicSpec.fromDocument(existingDocs[i], indexHint: i),
      ];
      final matched = List<bool>.filled(existingDocs.length, false);

      int? findMatchIdx(EpicSpec incoming) {
        final inKey = incoming.lineageKey.trim().toLowerCase();
        if (inKey.isNotEmpty) {
          for (int j = 0; j < existingSpecs.length; j++) {
            if (!matched[j] &&
                existingSpecs[j].lineageKey.trim().toLowerCase() == inKey) {
              return j;
            }
          }
        }
        for (int j = 0; j < existingDocs.length; j++) {
          if (!matched[j] && existingDocs[j].id == incoming.id) {
            return j;
          }
        }
        final inTitle = incoming.title.trim().toLowerCase();
        if (inTitle.isNotEmpty) {
          for (int j = 0; j < existingSpecs.length; j++) {
            if (!matched[j] &&
                existingSpecs[j].title.trim().toLowerCase() == inTitle) {
              return j;
            }
          }
        }
        return null;
      }

      final reconciledSpecs = <EpicSpec>[];
      final reconciledBaseDocs = <TierDocument?>[];

      for (int i = 0; i < draft.initialEpics.length; i++) {
        final incoming = draft.initialEpics[i];
        final matchIdx = findMatchIdx(incoming);
        if (matchIdx != null) {
          matched[matchIdx] = true;
          final existingDoc = existingDocs[matchIdx];
          final existingSpec = existingSpecs[matchIdx];
          if (existingSpec.isPassed) {
            reconciledSpecs.add(existingSpec.deepCopy(idOverride: existingDoc.id));
            reconciledBaseDocs.add(existingDoc);
          } else {
            final merged = incoming.deepCopy(
              idOverride: existingDoc.id,
              releaseVersionOverride: 'v0.1',
              lifecycleOverride: existingSpec.lifecycle,
            );
            merged.fixes = [for (final f in existingSpec.fixes) f.copyWith()];
            merged.baselineSummary = List<String>.from(existingSpec.baselineSummary);
            merged.upgradeDeltas = List<String>.from(existingSpec.upgradeDeltas);
            for (final check in merged.checks) {
              final wasPassed = existingSpec.checks.any(
                (old) =>
                    old.passed &&
                    (old.id == check.id ||
                        old.text.trim().toLowerCase() ==
                            check.text.trim().toLowerCase()),
              );
              if (wasPassed) check.passed = true;
            }
            reconciledSpecs.add(merged);
            reconciledBaseDocs.add(existingDoc);
          }
        } else {
          final newEpId =
              '${relId}_epic_${DateTime.now().microsecondsSinceEpoch}_$i';
          final created = incoming.deepCopy(
            idOverride: newEpId,
            releaseVersionOverride: 'v0.1',
          );
          if (created.lineageKey.trim().isEmpty) {
            created.lineageKey = 'epic_${reconciledSpecs.length + 1}';
          }
          reconciledSpecs.add(created);
          reconciledBaseDocs.add(null);
        }
      }

      final user = _authService.currentUser;
      for (int j = 0; j < existingDocs.length; j++) {
        if (matched[j]) continue;
        final existingDoc = existingDocs[j];
        final existingSpec = existingSpecs[j];
        if (existingSpec.isPassed ||
            existingSpec.openFixes.isNotEmpty ||
            existingSpec.passedChecksCount > 0) {
          reconciledSpecs.add(existingSpec.deepCopy(idOverride: existingDoc.id));
          reconciledBaseDocs.add(existingDoc);
        } else {
          documents.remove(existingDoc.id);
          LocalVaultService.deleteDocument(existingDoc.id);
          if (user != null) {
            _firestoreService.deleteDocument(
              uid: user.uid,
              docId: existingDoc.id,
            );
          }
        }
      }

      bool assignedActive = false;
      for (int i = 0; i < reconciledSpecs.length; i++) {
        final spec = reconciledSpecs[i];
        spec.code = 'E${(i + 1).toString().padLeft(2, '0')}';
        if (spec.lineageKey.trim().isEmpty) {
          spec.lineageKey = EpicSpec.formatLineageKey(i + 1);
        }
        if (!spec.isPassed &&
            spec.lifecycle != EpicLifecycle.upgrading &&
            spec.lifecycle != EpicLifecycle.newEpic) {
          if (!assignedActive) {
            spec.lifecycle = EpicLifecycle.active;
            assignedActive = true;
          } else {
            spec.lifecycle = EpicLifecycle.queued;
          }
        }

        final baseDoc = reconciledBaseDocs[i];
        final updatedDoc = baseDoc != null
            ? spec.applyToDocument(baseDoc)
            : spec.toTierDocument(docId: spec.id, parentReleaseId: relId);
        documents[updatedDoc.id] = updatedDoc;
        _persistDocument(updatedDoc);
        epicIds.add(updatedDoc.id);
      }

      draft.initialEpics = [for (final s in reconciledSpecs) s.deepCopy()];
      _conceptDraft = draft;
    }

    final relDoc = TierDocument(
      id: relId,
      title: v01Rel?.title ?? 'v0.1 · Prototype',
      tier: TierType.release,
      parentId: pid,
      childrenIds: epicIds,
      estimatedDuration: '${epicIds.length} Epics',
      sections: <String, String>{
        if (v01Rel != null) ...v01Rel.sections,
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
    final prevActiveRel =
        _activeReleaseId != null ? documents[_activeReleaseId!] : null;
    final keepExistingHigherRelease = prevActiveRel != null &&
        prevActiveRel.tier == TierType.release &&
        prevActiveRel.parentId == pid &&
        prevActiveRel.id != relId;
    if (keepExistingHigherRelease) {
      _activeReleaseId = prevActiveRel.id;
      final activeDocs = epicDocsForRelease(prevActiveRel.id);
      final keepsSelected = _selectedEpicId != null &&
          activeDocs.any((d) => d.id == _selectedEpicId);
      if (!keepsSelected) {
        final fallback = activeDocs.firstWhere(
          (d) => !EpicSpec.fromDocument(d).isPassed,
          orElse: () => activeDocs.isNotEmpty
              ? activeDocs.first
              : TierDocument(
                  id: '',
                  title: '',
                  tier: TierType.epic,
                ),
        );
        _selectedEpicId = fallback.id.isNotEmpty ? fallback.id : null;
      }
    } else {
      _activeReleaseId = relId;
      final firstUnpassedId = epicIds.firstWhere(
        (id) {
          final d = documents[id];
          return d != null && !EpicSpec.fromDocument(d).isPassed;
        },
        orElse: () => epicIds.isNotEmpty ? epicIds.first : '',
      );
      _selectedEpicId = firstUnpassedId.isNotEmpty ? firstUnpassedId : null;
    }
    _currentStage = WorkbenchStage.releaseWorkbench;
    _showRawEpicPayload = false;
    _syncActiveProjectMetadata();
    notifyListeners();
    return relId;
  }
}
