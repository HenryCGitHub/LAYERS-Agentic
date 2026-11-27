part of 'workbench_provider.dart';

/// `v0.2+` Progressive Release Co-Pilot state & non-destructive live-tree merging.
extension WorkbenchProgressivePlannerMixin on WorkbenchProvider {
  Future<ProgressiveReleaseDraft?> openProgressiveReleaseCopilot({
    String directionPrompt = '',
  }) async {
    final rootSpec = _conceptDraft;
    if (rootSpec == null) return null;

    final reqSeq = ++_progressiveDraftRequestSeq;
    final startedProjectId = _activeProjectId;
    final nextVer = nextReleaseVersionTag;
    _isDraftingProgressive = true;
    notifyListeners();

    try {
      final archThinking =
          (_planningModel == GeminiAgentClient.pinnedArchitectModel ||
                  _planningModel == 'gemini-4-neon')
              ? GeminiAgentClient.defaultArchitectThinkingLevel
              : _thinkingLevel;
      final draft = await ReleasePlannerAgent.proposeNextReleaseCopilot(
        rootSpec: rootSpec,
        currentEpics: latestReleaseEpics,
        targetVersion: nextVer,
        apiKey: _apiKey,
        directionPrompt: directionPrompt,
        preferredModel: _planningModel,
        thinkingLevel: archThinking,
      );
      if (reqSeq != _progressiveDraftRequestSeq ||
          _activeProjectId != startedProjectId) {
        return null;
      }
      _progressiveDraft = draft;
      if (draft.activePresetId != null && draft.presets.isNotEmpty) {
        applyProgressivePreset(draft.activePresetId!);
      }
      return draft;
    } finally {
      if (reqSeq == _progressiveDraftRequestSeq) {
        _isDraftingProgressive = false;
        notifyListeners();
      }
    }
  }

  void openInPagePlanNextRelease({String directionPrompt = ''}) {
    _showingPlanNextRelease = true;
    notifyListeners();
    unawaited(openProgressiveReleaseCopilot(directionPrompt: directionPrompt));
  }

  void closeInPagePlanNextRelease() {
    _showingPlanNextRelease = false;
    closeProgressiveReleaseCopilot();
  }

  void closeProgressiveReleaseCopilot() {
    _showingPlanNextRelease = false;
    _resetProgressiveDraftState();
    notifyListeners();
  }

  bool get hasSelectedProgressiveChanges {
    final draft = _progressiveDraft;
    if (draft == null) return false;
    final existingKeys = <String>{
      for (final ep in latestReleaseEpics)
        if (ep.lineageKey.trim().isNotEmpty) ep.lineageKey.trim().toLowerCase(),
    };
    for (final key in existingKeys) {
      final ups = draft.upgradesByLineageKey[key];
      if (ups != null && ups.any((u) => u.chosen)) return true;
      final feats = draft.candidateNewFeaturesByLineageKey[key];
      if (feats != null &&
          feats.any((f) => draft.chosenNewFeatureIds.contains(f.id))) {
        return true;
      }
    }
    return draft.candidateNewEpics.any((ep) => ep.chosenForNextRelease);
  }

  bool isProgressiveNewFeatureChosen(String featureId) {
    final draft = _progressiveDraft;
    return draft != null && draft.chosenNewFeatureIds.contains(featureId);
  }

  void toggleProgressiveNewFeature(String lineageKey, String featureId) {
    final draft = _progressiveDraft;
    if (draft == null) return;
    final list = draft.candidateNewFeaturesByLineageKey[lineageKey.trim().toLowerCase()];
    final exists = (list != null && list.any((f) => f.id == featureId)) ||
        draft.candidateNewFeaturesByLineageKey.values.any(
          (items) => items.any((f) => f.id == featureId),
        );
    if (!exists) return;
    if (!draft.chosenNewFeatureIds.remove(featureId)) {
      draft.chosenNewFeatureIds.add(featureId);
    }
    draft.activePresetId = null;
    notifyListeners();
  }

  void applyProgressivePreset(String presetId) {
    final draft = _progressiveDraft;
    if (draft == null || draft.presets.isEmpty) return;
    final preset = draft.presets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => draft.presets.first,
    );
    draft.activePresetId = preset.id;
    draft.customGoal = preset.description.trim().isNotEmpty
        ? preset.description.trim()
        : 'Progressive release ${draft.targetVersion} (${preset.label})';

    final upIdsLower = preset.upgradeIds.map((id) => id.trim().toLowerCase()).toSet();
    final newIdsLower = preset.newEpicIds.map((id) => id.trim().toLowerCase()).toSet();

    for (final opts in draft.upgradesByLineageKey.values) {
      for (final opt in opts) {
        opt.chosen = upIdsLower.contains(opt.id.trim().toLowerCase());
      }
    }
    final chosenLineageKeys = <String>{
      for (final entry in draft.upgradesByLineageKey.entries)
        if (entry.value.any((opt) => opt.chosen)) entry.key.trim().toLowerCase(),
    };
    final nextChosenFeatureIds = <String>{};
    for (final entry in draft.candidateNewFeaturesByLineageKey.entries) {
      final keyLower = entry.key.trim().toLowerCase();
      for (final feat in entry.value) {
        final fIdLower = feat.id.trim().toLowerCase();
        final fCodeLower = feat.code.trim().toLowerCase();
        final matchesPreset = upIdsLower.contains(fIdLower) ||
            upIdsLower.contains(fCodeLower) ||
            newIdsLower.contains(fIdLower) ||
            newIdsLower.contains(fCodeLower);
        if (matchesPreset || chosenLineageKeys.contains(keyLower)) {
          nextChosenFeatureIds.add(feat.id);
        }
      }
    }
    draft.chosenNewFeatureIds = nextChosenFeatureIds;

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

  void updateProgressiveCustomGoal(String goal) {
    final draft = _progressiveDraft;
    if (draft == null) return;
    draft.customGoal = goal.trim();
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
  /// - Existing Epics with checked upgrades/new Features become `Upgrading` (`EpicLifecycle.upgrading`) with additive deltas + `[+NEW]` Features attached cleanly inside the permanent parent Epic
  /// - Checked `[NEW]` Epics are added cleanly (`EpicLifecycle.newEpic`)
  String? commitProgressiveReleaseDraft() {
    final draft = _progressiveDraft;
    final proj = activeProject;
    if (draft == null || proj == null || !hasSelectedProgressiveChanges) {
      return null;
    }

    final nextVer = draft.targetVersion;
    final relId =
        '${proj.id}_rel_${nextVer.replaceAll('.', '')}_${DateTime.now().millisecondsSinceEpoch}';
    final nextEpicDocIds = <String>[];
    String? firstFocusEpicId;
    String? firstFocusFeatureId;

    final existingEpics = latestReleaseEpics;
    final usedLineageKeys = <String>{
      for (final ep in existingEpics)
        if (ep.lineageKey.trim().isNotEmpty) ep.lineageKey.trim().toLowerCase(),
    };
    final usedFeatureIds = <String>{
      for (final ep in existingEpics)
        for (final f in ep.features) f.id,
    };
    final usedFeatureCodesLower = <String>{};
    int maxFeatureNum = 0;
    final featCodeRx = RegExp(r'^F(\d+)$', caseSensitive: false);
    for (final rel in projectReleases) {
      for (final epDoc in epicDocsForRelease(rel.id)) {
        final ep = EpicSpec.fromDocument(epDoc);
        if (ep.lineageKey.trim().isNotEmpty) {
          usedLineageKeys.add(ep.lineageKey.trim().toLowerCase());
        }
        for (final f in ep.features) {
          usedFeatureIds.add(f.id);
          final codeLower = f.code.trim().toLowerCase();
          if (codeLower.isNotEmpty) {
            usedFeatureCodesLower.add(codeLower);
            final m = featCodeRx.firstMatch(f.code.trim());
            if (m != null) {
              final numVal = int.tryParse(m.group(1) ?? '') ?? 0;
              if (numVal > maxFeatureNum) maxFeatureNum = numVal;
            }
          }
        }
      }
    }
    for (final ep in existingEpics) {
      for (final f in ep.features) {
        final codeLower = f.code.trim().toLowerCase();
        if (codeLower.isNotEmpty) {
          usedFeatureCodesLower.add(codeLower);
          final m = featCodeRx.firstMatch(f.code.trim());
          if (m != null) {
            final numVal = int.tryParse(m.group(1) ?? '') ?? 0;
            if (numVal > maxFeatureNum) maxFeatureNum = numVal;
          }
        }
      }
    }

    String allocateFeatureCode(String preferred) {
      final cleanPref = preferred.trim();
      final prefLower = cleanPref.toLowerCase();
      if (cleanPref.isNotEmpty && !usedFeatureCodesLower.contains(prefLower)) {
        usedFeatureCodesLower.add(prefLower);
        final m = featCodeRx.firstMatch(cleanPref);
        if (m != null) {
          final numVal = int.tryParse(m.group(1) ?? '') ?? 0;
          if (numVal > maxFeatureNum) maxFeatureNum = numVal;
        }
        return cleanPref;
      }
      do {
        maxFeatureNum++;
      } while (usedFeatureCodesLower
          .contains(FeatureSpec.formatCode(maxFeatureNum).toLowerCase()));
      final nextCode = FeatureSpec.formatCode(maxFeatureNum);
      usedFeatureCodesLower.add(nextCode.toLowerCase());
      return nextCode;
    }

    for (int i = 0; i < existingEpics.length; i++) {
      final base = existingEpics[i];
      final key = base.lineageKey.toLowerCase();
      final chosenUpgradeOpts = (draft.upgradesByLineageKey[key] ?? const [])
          .where((u) => u.chosen)
          .toList();
      final chosenUps = [for (final u in chosenUpgradeOpts) u.text];
      final chosenNewFeats =
          (draft.candidateNewFeaturesByLineageKey[key] ?? const [])
              .where((f) => draft.chosenNewFeatureIds.contains(f.id))
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

      // Lock carried-over baseline features clean before applying v0.2+ deltas
      final baseRelVer = base.releaseVersion.trim().isEmpty
          ? 'v0.1'
          : base.releaseVersion.trim();
      final baseFeatureById = <String, FeatureSpec>{
        for (final bf in base.features) bf.id: bf,
      };
      for (final feat in nextEpic.features) {
        final wasPassedInBase = feat.isPassedForRelease(baseRelVer);
        final seenCheckIds = <String>{};
        final foldedChecks = <EpicPieCheck>[];
        for (final c in feat.effectiveChecksForRelease(baseRelVer)) {
          if (seenCheckIds.add(c.id)) {
            foldedChecks.add(
              wasPassedInBase ? c.copyWith(passed: true) : c.copyWith(),
            );
          }
        }
        feat.checks = foldedChecks;
        feat.releaseDeltaChecks = <EpicPieCheck>[];
        feat.releaseDelta = '';
        feat.fixes = <EpicPieFix>[];
        feat.status =
            wasPassedInBase ? FeatureStatus.passed : FeatureStatus.active;
      }

      for (final upOpt in chosenUpgradeOpts) {
        if (nextEpic.features.isEmpty) break;
        final targetCodeLower = (upOpt.targetFeatureCode ?? '').trim().toLowerCase();
        FeatureSpec? targetFeat;
        if (targetCodeLower.isNotEmpty) {
          for (final f in nextEpic.features) {
            if (f.code.trim().toLowerCase() == targetCodeLower ||
                f.id.trim().toLowerCase() == targetCodeLower) {
              targetFeat = f;
              break;
            }
          }
        }
        targetFeat ??= nextEpic.features.last;

        final rawText = upOpt.text.trim();
        final cleanNoPlus = rawText.replaceFirst(RegExp(r'^\+\s*'), '').trim();
        final formattedDelta =
            rawText.startsWith('+') ? rawText : '+$cleanNoPlus';
        targetFeat.releaseDelta = targetFeat.releaseDelta.isEmpty
            ? formattedDelta
            : '${targetFeat.releaseDelta} ; $formattedDelta';
        targetFeat.status = FeatureStatus.active;

        final origBase = baseFeatureById[targetFeat.id];
        final matchesSeededDelta = origBase != null &&
            origBase.releaseDelta
                    .replaceFirst(RegExp(r'^\+\s*'), '')
                    .trim()
                    .toLowerCase() ==
                cleanNoPlus.toLowerCase() &&
            origBase.releaseDeltaChecks.isNotEmpty;
        if (matchesSeededDelta && targetFeat.releaseDeltaChecks.isEmpty) {
          targetFeat.releaseDeltaChecks = [
            for (final dc in origBase.releaseDeltaChecks)
              dc.copyWith(passed: false),
          ];
        } else {
          targetFeat.releaseDeltaChecks.add(
            EpicPieCheck(
              id: '${clonedId}_${targetFeat.code.toLowerCase()}_delta_${targetFeat.releaseDeltaChecks.length + 1}',
              text: 'Verify $nextVer delta: $cleanNoPlus',
              passed: false,
            ),
          );
        }
        firstFocusEpicId ??= clonedId;
        firstFocusFeatureId ??= targetFeat.id;
      }

      for (final newFeat in chosenNewFeats) {
        final dupExists = nextEpic.features.any(
          (f) =>
              (!FeatureSpec.isPositionalFallbackFeatureId(newFeat.id) &&
                  f.id == newFeat.id) ||
              f.title.trim().toLowerCase() == newFeat.title.trim().toLowerCase(),
        );
        if (dupExists) continue;
        final newCode = allocateFeatureCode(newFeat.code);
        var attached = newFeat.deepCopy();
        if (attached.id.trim().isEmpty ||
            FeatureSpec.isPositionalFallbackFeatureId(attached.id) ||
            usedFeatureIds.contains(attached.id)) {
          var nextId = '${clonedId}_${newCode.toLowerCase()}';
          var sfx = 2;
          while (usedFeatureIds.contains(nextId)) {
            nextId = '${clonedId}_${newCode.toLowerCase()}_$sfx';
            sfx++;
          }
          attached = attached.deepCopy(idOverride: nextId);
        }
        usedFeatureIds.add(attached.id);
        attached.code = newCode;
        attached.introducedIn = nextVer;
        attached.status = FeatureStatus.active;
        attached.releaseDelta = '';
        attached.releaseDeltaChecks = <EpicPieCheck>[];
        attached.fixes = <EpicPieFix>[];
        for (final c in attached.checks) {
          c.passed = false;
        }
        nextEpic.features.add(attached);
        firstFocusEpicId ??= clonedId;
        firstFocusFeatureId ??= attached.id;
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

      nextEpic.releaseVersion = nextVer;
      final hasEpicWorkInNext =
          chosenUps.isNotEmpty || chosenNewFeats.isNotEmpty;
      if (hasEpicWorkInNext) {
        nextEpic.lifecycle = EpicLifecycle.upgrading;
        final epicDeltaTexts = chosenUps.isNotEmpty
            ? chosenUps
            : [for (final nf in chosenNewFeats) '+${nf.code} ${nf.title}'];
        nextEpic.upgradeDeltas = epicDeltaTexts;
        final baseCount = lockedBaseChecks.length;
        for (int uIdx = 0; uIdx < epicDeltaTexts.length; uIdx++) {
          lockedBaseChecks.add(
            EpicPieCheck(
              id: '${clonedId}_delta_${uIdx + 1}',
              text:
                  'Verify $nextVer delta: ${epicDeltaTexts[uIdx].replaceFirst(RegExp(r'^\+\s*'), '')}',
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

      final cleanNextEpic = UnrealSpecGuard.sanitizeEpicSpec(
        nextEpic,
        mode: unrealArchitectureMode,
      );
      final doc = cleanNextEpic.toTierDocument(
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
      var lkOrd = nextEpicDocIds.length + 1;
      var nextLk = EpicSpec.formatLineageKey(lkOrd);
      while (usedLineageKeys.contains(nextLk)) {
        lkOrd++;
        nextLk = EpicSpec.formatLineageKey(lkOrd);
      }
      usedLineageKeys.add(nextLk);
      clonedNew.lineageKey = nextLk;
      clonedNew.upgradeDeltas = <String>[];
      for (int fIdx = 0; fIdx < clonedNew.features.length; fIdx++) {
        var feat = clonedNew.features[fIdx];
        final allocatedCode = allocateFeatureCode(feat.code);
        if (feat.id.trim().isEmpty ||
            FeatureSpec.isPositionalFallbackFeatureId(feat.id) ||
            usedFeatureIds.contains(feat.id)) {
          var nextId = '${newId}_${allocatedCode.toLowerCase()}';
          var sfx = 2;
          while (usedFeatureIds.contains(nextId)) {
            nextId = '${newId}_${allocatedCode.toLowerCase()}_$sfx';
            sfx++;
          }
          feat = feat.deepCopy(idOverride: nextId);
          clonedNew.features[fIdx] = feat;
        }
        usedFeatureIds.add(feat.id);
        feat.code = allocatedCode;
        feat.introducedIn = nextVer;
        feat.status = FeatureStatus.active;
        feat.fixes = <EpicPieFix>[];
        for (final c in [...feat.checks, ...feat.releaseDeltaChecks]) {
          c.passed = false;
        }
      }

      final cleanNewEpic = UnrealSpecGuard.sanitizeEpicSpec(
        clonedNew,
        mode: unrealArchitectureMode,
      );
      final doc = cleanNewEpic.toTierDocument(
        docId: newId,
        parentReleaseId: relId,
      );
      documents[newId] = doc;
      _persistDocument(doc);
      nextEpicDocIds.add(newId);
      firstFocusEpicId ??= newId;
      if (firstFocusFeatureId == null && clonedNew.features.isNotEmpty) {
        firstFocusFeatureId = clonedNew.features.first.id;
      }
    }

    final presetLabel = (draft.activePresetId != null && draft.presets.isNotEmpty)
        ? draft.presets
            .firstWhere(
              (p) => p.id == draft.activePresetId,
              orElse: () => draft.presets.first,
            )
            .label
        : 'Update';

    final fromInPage = _showingPlanNextRelease;
    int activeSliceCount = 0;
    String? sampleGateText;
    for (final docId in nextEpicDocIds) {
      final epDoc = documents[docId];
      if (epDoc == null) continue;
      final epSpec = EpicSpec.fromDocument(epDoc);
      for (final f in epSpec.features) {
        final isNextWork =
            f.introducedIn.trim() == nextVer ||
            f.releaseDelta.trim().isNotEmpty;
        if (!isNextWork) continue;
        activeSliceCount++;
        if (sampleGateText == null) {
          final eff = f.effectiveChecksForRelease(nextVer);
          if (eff.isNotEmpty && eff.first.text.trim().isNotEmpty) {
            sampleGateText = eff.first.text.trim();
          } else if (f.doneWhen.isNotEmpty &&
              f.doneWhen.first.trim().isNotEmpty) {
            sampleGateText = f.doneWhen.first.trim();
          } else if (f.title.trim().isNotEmpty) {
            sampleGateText = '${f.code} ${f.title.trim()} passes in PIE';
          }
        }
      }
    }

    final customGoal = draft.customGoal.trim();
    final goalText = customGoal.isNotEmpty
        ? customGoal
        : 'Progressive release $nextVer ($presetLabel)';
    final doneWhenGate = activeSliceCount > 0
        ? 'Pass all $activeSliceCount $nextVer ${activeSliceCount == 1 ? 'feature' : 'features'} in PIE -> ${sampleGateText ?? 'Every upgrade and new feature behaves cleanly'}'
        : 'Pass all $nextVer features in PIE -> Every upgrade and new feature behaves cleanly';

    final newRelDoc = TierDocument(
      id: relId,
      title: '$nextVer · $presetLabel',
      tier: TierType.release,
      parentId: proj.id,
      childrenIds: nextEpicDocIds,
      estimatedDuration: '${nextEpicDocIds.length} Epics',
      sections: <String, String>{
        'release_version': nextVer,
        'goal': goalText,
        'doneWhen': doneWhenGate,
      },
    );
    documents[relId] = newRelDoc;
    _persistDocument(newRelDoc);

    proj.childrenIds = [...proj.childrenIds, relId];
    _activeReleaseId = relId;
    _selectedEpicId = firstFocusEpicId ??
        (nextEpicDocIds.isNotEmpty ? nextEpicDocIds.first : null);
    if (_selectedEpicId != null) {
      _expandedEpicIds.add(_selectedEpicId!);
    }
    _selectedFeatureId = firstFocusFeatureId ??
        _defaultFeatureIdForEpicDoc(_selectedEpicId, releaseVersion: nextVer);
    _showingPlanNextRelease = false;
    _showingReleaseSpec = fromInPage;
    _resetProgressiveDraftState();
    _currentStage = WorkbenchStage.releaseWorkbench;
    _syncActiveProjectMetadata();
    notifyListeners();
    return relId;
  }
}
