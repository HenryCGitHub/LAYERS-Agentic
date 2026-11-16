part of 'workbench_provider.dart';

/// `v0.2+` Progressive Release Co-Pilot state & non-destructive live-tree merging.
extension WorkbenchProgressivePlannerMixin on WorkbenchProvider {
  Future<ProgressiveReleaseDraft?> openProgressiveReleaseCopilot({
    String directionPrompt = '',
  }) async {
    final rootSpec = _conceptDraft;
    if (rootSpec == null) return null;

    final nextVer = ReleasePlannerAgent.nextMinorVersionTag(
      highestProjectReleaseVersionTag,
    );
    _isDraftingProgressive = true;
    notifyListeners();

    try {
      final draft = await ReleasePlannerAgent.proposeNextReleaseCopilot(
        rootSpec: rootSpec,
        currentEpics: latestReleaseEpics,
        targetVersion: nextVer,
        apiKey: _apiKey,
        directionPrompt: directionPrompt,
        preferredModel: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      _progressiveDraft = draft;
      if (draft.activePresetId != null && draft.presets.isNotEmpty) {
        applyProgressivePreset(draft.activePresetId!);
      }
      return draft;
    } finally {
      _isDraftingProgressive = false;
      notifyListeners();
    }
  }

  void closeProgressiveReleaseCopilot() {
    _progressiveDraft = null;
    notifyListeners();
  }

  void applyProgressivePreset(String presetId) {
    final draft = _progressiveDraft;
    if (draft == null) return;
    final preset = draft.presets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => draft.presets.first,
    );
    draft.activePresetId = preset.id;

    final upIdsLower = preset.upgradeIds.map((id) => id.trim().toLowerCase()).toSet();
    final newIdsLower = preset.newEpicIds.map((id) => id.trim().toLowerCase()).toSet();

    for (final opts in draft.upgradesByLineageKey.values) {
      for (final opt in opts) {
        opt.chosen = upIdsLower.contains(opt.id.trim().toLowerCase());
      }
    }
    for (final cand in draft.candidateNewEpics) {
      final candIdLower = cand.id.trim().toLowerCase();
      final candCodeLower = cand.code.trim().toLowerCase();
      final candLineageLower = cand.lineageKey.trim().toLowerCase();
      cand.chosenForNextRelease =
          newIdsLower.contains(candIdLower) ||
          newIdsLower.contains(candCodeLower) ||
          newIdsLower.any(
            (pid) =>
                candLineageLower.isNotEmpty && pid.contains(candLineageLower),
          );
    }
    notifyListeners();
  }

  void toggleProgressiveUpgrade(String lineageKey, String upgradeId) {
    final draft = _progressiveDraft;
    if (draft == null) return;
    final list = draft.upgradesByLineageKey[lineageKey.toLowerCase()];
    if (list == null) return;
    for (final opt in list) {
      if (opt.id == upgradeId) {
        opt.chosen = !opt.chosen;
        break;
      }
    }
    draft.activePresetId = null;
    notifyListeners();
  }

  void toggleProgressiveNewEpic(String candidateId) {
    final draft = _progressiveDraft;
    if (draft == null) return;
    for (final cand in draft.candidateNewEpics) {
      if (cand.id == candidateId) {
        cand.chosenForNextRelease = !cand.chosenForNextRelease;
        break;
      }
    }
    draft.activePresetId = null;
    notifyListeners();
  }

  /// Materializes the progressive release (`v0.2+`) non-destructively:
  /// - Existing Epics without upgrades stay `Baseline ✓` (`EpicLifecycle.stable`)
  /// - Existing Epics with checked upgrades become `Upgrading` (`EpicLifecycle.upgrading`) with additive deltas + PIE checks
  /// - Checked `[NEW]` Epics are added cleanly (`EpicLifecycle.newEpic`)
  String? commitProgressiveReleaseDraft() {
    final draft = _progressiveDraft;
    final proj = activeProject;
    if (draft == null || proj == null) return null;

    final nextVer = draft.targetVersion;
    final relId =
        '${proj.id}_rel_${nextVer.replaceAll('.', '')}_${DateTime.now().millisecondsSinceEpoch}';
    final nextEpicDocIds = <String>[];
    String? firstFocusEpicId;

    final existingEpics = latestReleaseEpics;
    for (int i = 0; i < existingEpics.length; i++) {
      final base = existingEpics[i];
      final key = base.lineageKey.toLowerCase();
      final chosenUps = (draft.upgradesByLineageKey[key] ?? const [])
          .where((u) => u.chosen)
          .map((u) => u.text)
          .toList();

      final clonedId = '${relId}_epic_${nextEpicDocIds.length + 1}';
      final nextEpic = base.deepCopy(idOverride: clonedId);
      nextEpic.code = EpicSpec.formatCode(nextEpicDocIds.length + 1);
      nextEpic.fixes = <EpicPieFix>[];

      for (final prevDelta in base.upgradeDeltas) {
        final cleanDelta = prevDelta.trim();
        if (cleanDelta.isEmpty) continue;
        final entry = '${base.releaseVersion}: $cleanDelta';
        if (!nextEpic.baselineSummary.contains(entry)) {
          nextEpic.baselineSummary.add(entry);
        }
      }

      final lockedBaseChecks = [
        for (int cIdx = 0; cIdx < nextEpic.checks.length; cIdx++)
          EpicPieCheck(
            id: nextEpic.checks[cIdx].id.contains('_delta_')
                ? '${clonedId}_base_${cIdx + 1}'
                : nextEpic.checks[cIdx].id,
            text: nextEpic.checks[cIdx].text,
            passed: true,
          ),
      ];

      if (chosenUps.isNotEmpty) {
        nextEpic.lifecycle = EpicLifecycle.upgrading;
        nextEpic.releaseVersion = nextVer;
        nextEpic.upgradeDeltas = chosenUps;
        final baseCount = lockedBaseChecks.length;
        for (int uIdx = 0; uIdx < chosenUps.length; uIdx++) {
          lockedBaseChecks.add(
            EpicPieCheck(
              id: '${clonedId}_delta_${uIdx + 1}',
              text:
                  'Verify $nextVer delta: ${chosenUps[uIdx].replaceFirst(RegExp(r'^\+\s*'), '')}',
              passed: false,
            ),
          );
        }
        nextEpic.checks = lockedBaseChecks;
        if (nextEpic.baselineSummary.isEmpty && baseCount > 0) {
          nextEpic.baselineSummary = [
            '${base.releaseVersion} baseline locked ($baseCount PIE checks passing)',
          ];
        }
        firstFocusEpicId ??= clonedId;
      } else {
        nextEpic.lifecycle = EpicLifecycle.stable;
        nextEpic.upgradeDeltas = <String>[];
        nextEpic.checks = lockedBaseChecks;
      }

      final doc = nextEpic.toTierDocument(
        docId: clonedId,
        parentReleaseId: relId,
      );
      documents[clonedId] = doc;
      _persistDocument(doc);
      nextEpicDocIds.add(clonedId);
    }

    for (final cand in draft.candidateNewEpics) {
      if (!cand.chosenForNextRelease) continue;
      final newId = '${relId}_epic_${nextEpicDocIds.length + 1}';
      final newCode = EpicSpec.formatCode(nextEpicDocIds.length + 1);
      final clonedNew = cand.deepCopy(
        idOverride: newId,
        releaseVersionOverride: nextVer,
        lifecycleOverride: EpicLifecycle.newEpic,
      );
      clonedNew.code = newCode;
      clonedNew.lineageKey = newCode.toLowerCase();
      clonedNew.upgradeDeltas = <String>[];

      final doc = clonedNew.toTierDocument(
        docId: newId,
        parentReleaseId: relId,
      );
      documents[newId] = doc;
      _persistDocument(doc);
      nextEpicDocIds.add(newId);
      firstFocusEpicId ??= newId;
    }

    final presetLabel = draft.activePresetId != null
        ? draft.presets
            .firstWhere(
              (p) => p.id == draft.activePresetId,
              orElse: () => draft.presets.first,
            )
            .label
        : 'Update';

    final newRelDoc = TierDocument(
      id: relId,
      title: '$nextVer · $presetLabel',
      tier: TierType.release,
      parentId: proj.id,
      childrenIds: nextEpicDocIds,
      estimatedDuration: '${nextEpicDocIds.length} Epics',
      sections: <String, String>{
        'release_version': nextVer,
        'goal': 'Progressive release $nextVer ($presetLabel)',
      },
    );
    documents[relId] = newRelDoc;
    _persistDocument(newRelDoc);

    proj.childrenIds = [...proj.childrenIds, relId];
    _activeReleaseId = relId;
    _selectedEpicId = firstFocusEpicId ??
        (nextEpicDocIds.isNotEmpty ? nextEpicDocIds.first : null);
    _progressiveDraft = null;
    _currentStage = WorkbenchStage.releaseWorkbench;
    _syncActiveProjectMetadata();
    notifyListeners();
    return relId;
  }
}
