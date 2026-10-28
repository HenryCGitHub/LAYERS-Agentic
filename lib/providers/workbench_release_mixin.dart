part of 'workbench_provider.dart';

/// Stage 2 Open-Canvas Release Workbench, Progressive AI Release Co-Pilot,
/// Live Playtest Triage, and Engine Step Synthesis for [WorkbenchProvider].
extension WorkbenchReleaseMixin on WorkbenchProvider {
  void _selectFirstIncompleteFeatureInActiveRelease() {
    final beats = activeReleaseBeats;
    if (beats.isEmpty) return;
    TierDocument? firstActiveBeat;
    TierDocument? firstActiveFeat;

    // 1st Pass: Prioritize incomplete features active in the current release (`newFeature` or `upgrade`)
    for (final b in beats) {
      for (final f in featuresForBeat(b.id)) {
        if (isFeatureActiveInRelease(f) && getDocumentProgress(f.id) < 100) {
          firstActiveBeat = b;
          firstActiveFeat = f;
          break;
        }
      }
      if (firstActiveFeat != null) break;
    }

    // 2nd Pass: Any feature active in the current release (even if 100% complete)
    if (firstActiveFeat == null) {
      for (final b in beats) {
        for (final f in featuresForBeat(b.id)) {
          if (isFeatureActiveInRelease(f)) {
            firstActiveBeat = b;
            firstActiveFeat = f;
            break;
          }
        }
        if (firstActiveFeat != null) break;
      }
    }

    // 3rd Pass: Fall back to any incomplete feature
    if (firstActiveFeat == null) {
      for (final b in beats) {
        for (final f in featuresForBeat(b.id)) {
          if (getDocumentProgress(f.id) < 100) {
            firstActiveBeat = b;
            firstActiveFeat = f;
            break;
          }
        }
        if (firstActiveFeat != null) break;
      }
    }

    _selectedBeatId = (firstActiveBeat ?? beats.first).id;
    final feats = featuresForBeat(_selectedBeatId!);
    _selectedFeatureId =
        (firstActiveFeat ?? (feats.isNotEmpty ? feats.first : null))?.id;
  }

  /// Option 4: Builds a Post-Release Retrospective & Auto-Carryover Summary for the active Release.
  ReleaseRetrospectiveSummary buildActiveReleaseRetrospective() {
    final rel = activeRelease;
    final activeVer = activeReleaseVersionTag;
    final beats = activeReleaseBeats;
    final allFeats = <TierDocument>[
      for (final b in beats) ...featuresForBeat(b.id),
    ];
    int verifiedCps = 0;
    int totalCps = 0;
    int fixTasks = 0;
    int playtestGuards = 0;
    final carryover = <String>[];
    final hardened = <String>[];

    for (final f in allFeats) {
      final isStable =
          f.sections['lifecycle'] == FeatureLifecycleStatus.stable.name;
      final states = FeatureStateNode.getStatesForDocument(f);
      final activeStates =
          states.where((s) => s.releaseVersion == activeVer).toList();
      final effectiveStates =
          activeStates.isNotEmpty ? activeStates : states;
      totalCps += effectiveStates.length;
      bool featHasIncomplete = false;
      bool featWasHardened = false;
      for (final s in effectiveStates) {
        if (s.isCompleted || isStable) {
          verifiedCps++;
        } else {
          featHasIncomplete = true;
        }
        for (final t in s.checklist) {
          if (t.text.startsWith('[FIX]')) {
            fixTasks++;
            featWasHardened = true;
          }
        }
        for (final g in s.edgeCases) {
          if (g.startsWith('[PLAYTEST GUARD]') ||
              g.startsWith('[SIMULATION GUARD]')) {
            playtestGuards++;
            featWasHardened = true;
          }
        }
      }
      if (featHasIncomplete && !isStable) {
        carryover.add(f.title);
      }
      if (featWasHardened) {
        hardened.add(f.title);
      }
    }

    return ReleaseRetrospectiveSummary(
      releaseTitle: rel?.title ?? 'v0.1 Prototype',
      totalFeatures: allFeats.length,
      verifiedCheckpoints: verifiedCps,
      totalCheckpoints: totalCps,
      fixTasksTriaged: fixTasks,
      playtestGuardsAdded: playtestGuards,
      carryoverFeatureTitles: carryover,
      hardenedFeatureTitles: hardened,
    );
  }

  /// Switches the Stage 2 Workbench in-place to an already-built Release (`rel.childrenIds.isNotEmpty`),
  /// or synthesizes and builds the target Release directly into `2. Workbench` if not built yet.
  Future<void> selectActiveRelease(String releaseId) async {
    final targetRel = documents[releaseId];
    if (targetRel == null) return;
    _syncCurrentPhaseFromRelease(targetRel);
    if (targetRel.childrenIds.isNotEmpty) {
      _activeReleaseId = releaseId;
      final savedBp = releaseBlueprintFor(releaseId);
      if (savedBp != null) {
        _releaseBlueprint = savedBp;
      }
      _releaseViewFilter = 'active';
      _currentStage = WorkbenchStage.releaseWorkbench;
      _selectFirstIncompleteFeatureInActiveRelease();
      _syncActiveProjectMetadata();
      notifyListeners();
      return;
    }
    await approveConceptAndBuildRelease(releaseId: releaseId);
  }

  /// 2-Stage Flow (`1. Concept` -> `2. Workbench`): Transitions immediately to `2. Workbench`,
  /// synthesizes the Release Blueprint, and executes it into the active Workbench in one click.
  Future<void> approveConceptAndBuildRelease({String? releaseId}) async {
    if (_conceptDraft != null) {
      _commitConceptToVault(_conceptDraft!, syncBuiltWorkbench: false);
    }
    _releaseViewFilter = 'active';
    _currentStage = WorkbenchStage.releaseWorkbench;
    notifyListeners();

    await openReleasePlanGate(
      releaseId: releaseId,
      transitionToGateStage: false,
    );
    if (_releaseBlueprint != null) {
      await approveAndExecuteReleasePlan();
    } else if (activeReleaseBeats.isEmpty) {
      _currentStage = WorkbenchStage.projectPitch;
      notifyListeners();
    }
  }

  static final RegExp _minorVerRegex = RegExp(
    r'v0\.(\d+)',
    caseSensitive: false,
  );

  void _updateSerializedReleaseBlueprintMetadata(
    TierDocument doc, {
    String? releaseDocId,
    required String versionTag,
    required String title,
  }) {
    final rawArchivedBp = doc.sections['release_blueprint_json'];
    if (rawArchivedBp == null || rawArchivedBp.trim().isEmpty) return;
    try {
      final archivedMap = Map<String, dynamic>.from(
        jsonDecode(rawArchivedBp) as Map,
      );
      if (releaseDocId != null) {
        archivedMap['releaseDocId'] = releaseDocId;
      }
      archivedMap['releaseVersionTag'] = versionTag;
      archivedMap['releaseTitle'] = title;
      doc.sections['release_blueprint_json'] = jsonEncode(archivedMap);
    } catch (_) {}
  }

  /// Evaluates how many Core Loop Epics (`activeReleaseBeats`) and `v0.1` Prototype Features
  /// have received functional `MVP` coverage across built `ProductionPhase.mvp` releases.
  ({
    int coveredBeats,
    int totalBeats,
    int upgradedProtoFeatures,
    int totalProtoFeatures,
    List<String> uncoveredBeatTitles,
    List<String> unupgradedProtoFeatureTitles,
    bool isComplete,
  }) mvpBeatCoverage() {
    final builtReleases =
        projectReleases.where((r) => r.childrenIds.isNotEmpty).toList();
    final mvpVerTags = <String>{
      for (final r in builtReleases)
        if (releasePhaseFor(r) == ProductionPhase.mvp)
          releaseVersionTagFor(r).toLowerCase(),
    };
    final beats = activeReleaseBeats;
    int coveredBeats = 0;
    int totalProtoFeatures = 0;
    int upgradedProtoFeatures = 0;
    final uncoveredBeatTitles = <String>[];
    final unupgradedProtoFeatureTitles = <String>[];

    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final b = beats[bIdx];
      final eTag = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      final feats = featuresForBeat(b.id)
          .where(
            (f) =>
                f.sections['lifecycle'] !=
                FeatureLifecycleStatus.superseded.name,
          )
          .toList();
      bool beatCoveredInMvp = false;
      for (final f in feats) {
        final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
        final states = FeatureStateNode.getStatesForDocument(f);
        final hasMvpCheckpoint = mvpVerTags.contains(originVer) ||
            states.any((s) => mvpVerTags.contains(s.releaseVersion.toLowerCase()));
        if (hasMvpCheckpoint) {
          beatCoveredInMvp = true;
        }
        if (originVer == 'v0.1') {
          totalProtoFeatures++;
          final upgradedPostV01 = states.any(
            (s) => s.releaseVersion.toLowerCase() != 'v0.1',
          );
          if (upgradedPostV01 || hasMvpCheckpoint) {
            upgradedProtoFeatures++;
          } else {
            unupgradedProtoFeatureTitles.add('$eTag · ${f.title}');
          }
        }
      }
      if (beatCoveredInMvp) {
        coveredBeats++;
      } else {
        uncoveredBeatTitles.add('$eTag · ${b.title}');
      }
    }

    final totalBeats = beats.length;
    final protoThreshold =
        totalProtoFeatures > 0 ? (totalProtoFeatures * 0.75).ceil() : 0;
    final isComplete = totalBeats > 0 &&
        coveredBeats >= totalBeats &&
        upgradedProtoFeatures >= protoThreshold;

    return (
      coveredBeats: coveredBeats,
      totalBeats: totalBeats,
      upgradedProtoFeatures: upgradedProtoFeatures,
      totalProtoFeatures: totalProtoFeatures,
      uncoveredBeatTitles: uncoveredBeatTitles,
      unupgradedProtoFeatureTitles: unupgradedProtoFeatureTitles,
      isComplete: isComplete,
    );
  }

  /// Evaluates how many Core Loop Epics (`activeReleaseBeats`) and live Features have received
  /// `Vertical Slice` polish coverage across built `ProductionPhase.verticalSlice` releases.
  ({
    int polishedBeats,
    int totalBeats,
    int polishedFeatures,
    int totalFeatures,
    List<String> unpolishedBeatTitles,
    List<String> unpolishedFeatureTitles,
    bool isComplete,
  }) verticalSliceBeatCoverage() {
    final builtReleases =
        projectReleases.where((r) => r.childrenIds.isNotEmpty).toList();
    final vsVerTags = <String>{
      for (final r in builtReleases)
        if (releasePhaseFor(r) == ProductionPhase.verticalSlice)
          releaseVersionTagFor(r).toLowerCase(),
    };
    final beats = activeReleaseBeats;
    int polishedBeats = 0;
    int totalFeatures = 0;
    int polishedFeatures = 0;
    final unpolishedBeatTitles = <String>[];
    final unpolishedFeatureTitles = <String>[];

    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final b = beats[bIdx];
      final eTag = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      final feats = featuresForBeat(b.id)
          .where(
            (f) =>
                f.sections['lifecycle'] !=
                FeatureLifecycleStatus.superseded.name,
          )
          .toList();
      bool beatPolishedInVs = false;
      for (final f in feats) {
        totalFeatures++;
        final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
        final states = FeatureStateNode.getStatesForDocument(f);
        final hasVsCheckpoint = vsVerTags.contains(originVer) ||
            states.any((s) => vsVerTags.contains(s.releaseVersion.toLowerCase()));
        if (hasVsCheckpoint) {
          beatPolishedInVs = true;
          polishedFeatures++;
        } else {
          unpolishedFeatureTitles.add('$eTag · ${f.title}');
        }
      }
      if (beatPolishedInVs) {
        polishedBeats++;
      } else {
        unpolishedBeatTitles.add('$eTag · ${b.title}');
      }
    }

    final totalBeats = beats.length;
    final featureThreshold =
        totalFeatures > 0 ? (totalFeatures * 0.75).ceil() : 0;
    final isComplete = totalBeats > 0 &&
        polishedBeats >= totalBeats &&
        (polishedFeatures >= featureThreshold || polishedBeats >= totalBeats);

    return (
      polishedBeats: polishedBeats,
      totalBeats: totalBeats,
      polishedFeatures: polishedFeatures,
      totalFeatures: totalFeatures,
      unpolishedBeatTitles: unpolishedBeatTitles,
      unpolishedFeatureTitles: unpolishedFeatureTitles,
      isComplete: isComplete,
    );
  }

  /// Infers the natural next `ProductionPhase` (`prototype` -> multi-release `mvp` -> multi-release `verticalSlice` -> `fullProduction`)
  /// based on the live game tree's Epic & Feature coverage so progressive releases complete all MVP Epics and
  /// all Vertical Slice polish passes before graduating to `v1.0` Full Production.
  ProductionPhase inferNextProgressivePhase() {
    final releases = projectReleases;
    final builtReleases =
        releases.where((r) => r.childrenIds.isNotEmpty).toList();
    if (builtReleases.isEmpty) {
      return ProductionPhase.prototype;
    }
    if (builtReleases.any(
      (r) => releasePhaseFor(r) == ProductionPhase.fullProduction,
    )) {
      return ProductionPhase.fullProduction;
    }
    final vsCov = verticalSliceBeatCoverage();
    if (vsCov.isComplete) {
      return ProductionPhase.fullProduction;
    }
    if (builtReleases.any(
      (r) => releasePhaseFor(r) == ProductionPhase.verticalSlice,
    )) {
      return ProductionPhase.verticalSlice;
    }
    final mvpCov = mvpBeatCoverage();
    if (mvpCov.isComplete) {
      return ProductionPhase.verticalSlice;
    }
    return ProductionPhase.mvp;
  }

  ReleaseScope _releaseScopeForPhase(ProductionPhase phase) {
    switch (phase) {
      case ProductionPhase.prototype:
        return ReleaseScope.prototype;
      case ProductionPhase.mvp:
        return ReleaseScope.mvp;
      case ProductionPhase.verticalSlice:
        return ReleaseScope.verticalSlice;
      case ProductionPhase.fullProduction:
        return ReleaseScope.fullProduction;
    }
  }

  /// Allows the developer to switch the target `ProductionPhase` (`MVP`, `Vertical Slice`, `Full Production`)
  /// inside the Progressive Release Co-Pilot modal and re-synthesize the draft blueprint for that phase.
  Future<void> setDraftReleasePhase(ProductionPhase targetPhase) async {
    final relDoc = activeRelease;
    final proj = activeProject;
    if (relDoc == null || proj == null) return;
    _currentPhase = targetPhase;
    final targetScope = _releaseScopeForPhase(targetPhase);
    relDoc.sections['phase'] = targetPhase.name;
    relDoc.sections['releaseScope'] = targetScope.name;
    relDoc.sections['agentReasoned'] = 'true';
    relDoc.sections['phaseLockedByUser'] = 'true';
    if (targetPhase == ProductionPhase.fullProduction) {
      final existingFullProdCount = projectReleases
          .where(
            (r) =>
                r.id != relDoc.id &&
                releasePhaseFor(r) == ProductionPhase.fullProduction,
          )
          .length;
      final pass = existingFullProdCount + 1;
      final fpVer = 'v1.${pass - 1}';
      relDoc.sections['versionTag'] = fpVer;
      relDoc.sections['fullProductionPass'] = '$pass';
    } else {
      relDoc.sections.remove('fullProductionPass');
      final idx = proj.childrenIds.indexOf(relDoc.id);
      if (idx >= 0) {
        relDoc.sections['versionTag'] = 'v0.${idx + 1}';
      }
    }
    _persistDocument(relDoc);
    _syncActiveProjectMetadata();
    await openReleasePlanGate(
      releaseId: relDoc.id,
      transitionToGateStage: false,
    );
    if (_releaseBlueprint != null) {
      _initialProgressiveTrack0BlueprintJson =
          jsonEncode(_releaseBlueprint!.toJson());
    }
  }

  /// Prunes any leftover unbuilt draft releases (once the project has at least one built release)
  /// and sequentially re-packs all `v0.X` releases (`v0.1`, `v0.2`, ..., `v0.N`) so skipped
  /// version gaps never occur.
  void repackProjectReleasesSequentially(
    TierDocument proj, {
    bool pruneAllUnbuilt = false,
    String? keepReleaseId,
  }) {
    final user = _authService.currentUser;

    // 1. Deduplicate proj.childrenIds while keeping only existing release docs
    final deduped = <String>[];
    for (final id in proj.childrenIds) {
      if (!deduped.contains(id) && documents.containsKey(id)) {
        deduped.add(id);
      }
    }
    proj.childrenIds = deduped;

    // 2. If at least one built release exists, prune unbuilt draft releases
    final hasBuiltRelease = proj.childrenIds.any(
      (id) => documents[id]?.childrenIds.isNotEmpty ?? false,
    );
    if (hasBuiltRelease) {
      final toRemove = <String>[];
      for (final id in proj.childrenIds) {
        final relDoc = documents[id];
        if (relDoc == null) continue;
        if (relDoc.childrenIds.isEmpty) {
          final shouldKeep = !pruneAllUnbuilt && id == keepReleaseId;
          if (!shouldKeep) {
            toRemove.add(id);
          }
        }
      }
      for (final id in toRemove) {
        proj.childrenIds.remove(id);
        documents.remove(id);
        LocalVaultService.deleteDocument(id);
        if (user != null) {
          _firestoreService.deleteDocument(uid: user.uid, docId: id);
        }
      }
    }

    // Remove any orphaned TierType.release documents belonging to this project
    final activeSet = proj.childrenIds.toSet();
    final orphanRelIds = documents.values
        .where(
          (d) =>
              d.tier == TierType.release &&
              d.parentId == proj.id &&
              !activeSet.contains(d.id),
        )
        .map((d) => d.id)
        .toList();
    for (final orphanId in orphanRelIds) {
      documents.remove(orphanId);
      LocalVaultService.deleteDocument(orphanId);
      if (user != null) {
        _firestoreService.deleteDocument(uid: user.uid, docId: orphanId);
      }
    }

    // 3. Re-pack remaining v0.X releases sequentially (1..N)
    final versionRemap = <String, String>{};
    bool anyChanged = false;

    for (int i = 0; i < proj.childrenIds.length; i++) {
      final seqNum = i + 1;
      final oldRelId = proj.childrenIds[i];
      final relDoc = documents[oldRelId];
      if (relDoc == null) continue;

      final currentVerTag = releaseVersionTagFor(relDoc);
      final isFullProdV1 =
          relDoc.sections['phase'] == ProductionPhase.fullProduction.name ||
          relDoc.releaseScope == ReleaseScope.fullProduction ||
          currentVerTag.toLowerCase().startsWith('v1.');
      if (isFullProdV1) continue;

      final expectedVer = 'v0.$seqNum';
      final expectedId = proj.id == 'proj_main'
          ? 'rel_v0_$seqNum'
          : '${proj.id}_rel_v0_$seqNum';

      bool docChanged = false;
      if (currentVerTag != expectedVer &&
          currentVerTag.toLowerCase().startsWith('v0.')) {
        versionRemap[currentVerTag] = expectedVer;
        docChanged = true;
      }
      if (relDoc.sections['versionTag'] != expectedVer) {
        relDoc.sections['versionTag'] = expectedVer;
        docChanged = true;
      }
      if (_minorVerRegex.hasMatch(relDoc.title)) {
        final updatedTitle = relDoc.title.replaceAll(
          _minorVerRegex,
          expectedVer,
        );
        if (updatedTitle != relDoc.title) {
          relDoc.title = updatedTitle;
          docChanged = true;
        }
      }
      final rawScope = relDoc.sections['scope'];
      if (rawScope != null && _minorVerRegex.hasMatch(rawScope)) {
        final updatedScope = rawScope.replaceAll(_minorVerRegex, expectedVer);
        if (updatedScope != rawScope) {
          relDoc.sections['scope'] = updatedScope;
          docChanged = true;
        }
      }

      if (oldRelId != expectedId &&
          (!documents.containsKey(expectedId) ||
              !proj.childrenIds.contains(expectedId))) {
        final movedDoc = relDoc.copyWith(
          id: expectedId,
          sections: Map<String, String>.from(relDoc.sections),
        );
        _updateSerializedReleaseBlueprintMetadata(
          movedDoc,
          releaseDocId: expectedId,
          versionTag: expectedVer,
          title: movedDoc.title,
        );
        documents.remove(oldRelId);
        LocalVaultService.deleteDocument(oldRelId);
        if (user != null) {
          _firestoreService.deleteDocument(uid: user.uid, docId: oldRelId);
        }
        documents[expectedId] = movedDoc;
        _persistDocument(movedDoc);
        proj.childrenIds[i] = expectedId;

        if (_activeReleaseId == oldRelId) {
          _activeReleaseId = expectedId;
        }
        if (proj.sections['active_release_id'] == oldRelId) {
          proj.sections['active_release_id'] = expectedId;
        }
        if (_releaseBlueprint != null &&
            _releaseBlueprint!.releaseDocId == oldRelId) {
          _releaseBlueprint = ReleaseBlueprint(
            releaseDocId: expectedId,
            releaseTitle: movedDoc.title,
            releaseVersionTag: expectedVer,
            preset: _releaseBlueprint!.preset,
            goal: _releaseBlueprint!.goal.replaceAll(
              _minorVerRegex,
              expectedVer,
            ),
            doneWhen: _releaseBlueprint!.doneWhen.replaceAll(
              _minorVerRegex,
              expectedVer,
            ),
            questions: _releaseBlueprint!.questions,
            beats: _releaseBlueprint!.beats,
            explicitExclusions: _releaseBlueprint!.explicitExclusions,
            builtSoFar: _releaseBlueprint!.builtSoFar,
            missingGaps: _releaseBlueprint!.missingGaps,
            lastAgentReply: _releaseBlueprint!.lastAgentReply,
          );
        }
        for (final doc in documents.values) {
          if (doc.parentId == oldRelId) {
            doc.parentId = expectedId;
            _persistDocument(doc);
          }
        }
        anyChanged = true;
      } else if (docChanged) {
        _updateSerializedReleaseBlueprintMetadata(
          relDoc,
          versionTag: expectedVer,
          title: relDoc.title,
        );
        if (_releaseBlueprint != null &&
            _releaseBlueprint!.releaseDocId == oldRelId) {
          _releaseBlueprint!.releaseVersionTag = expectedVer;
          _releaseBlueprint!.releaseTitle = relDoc.title;
        }
        _persistDocument(relDoc);
        anyChanged = true;
      }
    }

    // 3b. Deduplicate beatDoc.childrenIds across all Epics of the project so duplicate feature cards never appear
    final projectBeatIdsForDedup = <String>{
      for (final relId in proj.childrenIds)
        ...?documents[relId]?.childrenIds,
    };
    for (final bId in projectBeatIdsForDedup) {
      final beatDoc = documents[bId];
      if (beatDoc == null || beatDoc.childrenIds.length <= 1) continue;
      final dedupedFeatIds = <String>[];
      for (final fid in beatDoc.childrenIds) {
        if (!dedupedFeatIds.contains(fid) && documents.containsKey(fid)) {
          dedupedFeatIds.add(fid);
        }
      }
      if (dedupedFeatIds.length != beatDoc.childrenIds.length) {
        beatDoc.childrenIds = dedupedFeatIds;
        _persistDocument(beatDoc);
        anyChanged = true;
      }
    }

    // 4. Remap any FeatureStateNode checkpoint releaseVersion tags and blueprint items
    if (versionRemap.isNotEmpty) {
      final projectBeatIds = <String>{
        for (final relId in proj.childrenIds)
          ...?documents[relId]?.childrenIds,
      };
      for (final doc in documents.values) {
        if (doc.tier == TierType.feature &&
            doc.parentId != null &&
            projectBeatIds.contains(doc.parentId)) {
          final states = FeatureStateNode.getStatesForDocument(doc);
          bool featStatesChanged = false;
          for (final s in states) {
            final mappedVer = versionRemap[s.releaseVersion];
            if (mappedVer != null) {
              s.parameters['releaseVersion'] = mappedVer;
              featStatesChanged = true;
            }
          }
          if (featStatesChanged) {
            FeatureStateNode.saveStatesToDocument(doc, states);
            _persistDocument(doc);
          }
        }
      }
      if (_releaseBlueprint != null) {
        for (final beat in _releaseBlueprint!.beats) {
          for (final feat in beat.features) {
            final mappedOrigin = versionRemap[feat.originVersion];
            if (mappedOrigin != null) {
              feat.originVersion = mappedOrigin;
            }
            feat.checkpoints = [
              for (final cp in feat.checkpoints)
                versionRemap.containsKey(cp.releaseVersion)
                    ? ProposedCheckpointBlueprint(
                        title: cp.title,
                        playtestCriteria: cp.playtestCriteria,
                        tasks: cp.tasks,
                        coveredScope: cp.coveredScope,
                        tuningParams: cp.tuningParams,
                        edgeCases: cp.edgeCases,
                        releaseVersion: versionRemap[cp.releaseVersion]!,
                      )
                    : cp,
            ];
          }
        }
      }
    }

    if (proj.childrenIds.isNotEmpty &&
        (_activeReleaseId == null ||
            !proj.childrenIds.contains(_activeReleaseId))) {
      _activeReleaseId = proj.childrenIds.last;
      anyChanged = true;
    }

    if (anyChanged || versionRemap.isNotEmpty) {
      _persistDocument(proj);
    }
  }

  ({int index, String id}) _allocateNextReleaseIdAndIndex(TierDocument proj) {
    repackProjectReleasesSequentially(proj, pruneAllUnbuilt: true);
    final nextIndex = proj.childrenIds.length + 1;
    final candidateId = proj.id == 'proj_main'
        ? 'rel_v0_$nextIndex'
        : '${proj.id}_rel_v0_$nextIndex';
    return (index: nextIndex, id: candidateId);
  }

  /// Next progressive version tag (`v0.2`, `v0.3`, ..., or `v1.0`, `v1.1` in Full Production).
  String get nextProgressiveVersionLabel {
    final releases = projectReleases;
    final builtReleases =
        releases.where((r) => r.childrenIds.isNotEmpty).toList();
    if (builtReleases.isNotEmpty &&
        inferNextProgressivePhase() == ProductionPhase.fullProduction) {
      final existingFullProdCount = builtReleases
          .where((r) => releasePhaseFor(r) == ProductionPhase.fullProduction)
          .length;
      return 'v1.$existingFullProdCount';
    }
    final builtCount = builtReleases.length;
    final baseCount = builtCount > 0 ? builtCount : releases.length;
    return 'v0.${baseCount + 1}';
  }

  /// Prepares the next Progressive Release (`v0.2`, `v0.3+`) blueprint in-memory while keeping
  /// the user inside `2. Workbench`, optionally applying a natural-language directive from the
  /// Agentic Next-Release Co-Pilot.
  Future<ReleaseBlueprint?> prepareProgressiveNextReleaseDraft({
    String? agentDirective,
  }) async {
    _preModalReleaseIds = Set<String>.from(
      activeProject?.childrenIds ?? const <String>[],
    );
    _preModalReleaseBlueprint = _releaseBlueprint;
    await advanceToNextRelease(
      transitionToGateStage: false,
      agentReasonedProgressive: true,
    );
    _currentStage = WorkbenchStage.releaseWorkbench;
    if (_releaseBlueprint == null ||
        _releaseBlueprint!.releaseDocId != _activeReleaseId) {
      notifyListeners();
      return null;
    }
    _initialProgressiveTrack0BlueprintJson =
        jsonEncode(_releaseBlueprint!.toJson());
    if (agentDirective != null && agentDirective.trim().isNotEmpty) {
      await sendReleasePlanChatMessage(agentDirective.trim());
    }
    notifyListeners();
    return _releaseBlueprint;
  }

  /// Restores the initial Option 0 (`(Recommended)`) draft `ReleaseBlueprint` when the user clicks
  /// back onto Option 0 after exploring Option 1 or Option 2 in the Progressive Release Co-Pilot.
  void restoreInitialProgressiveDraftBlueprint() {
    final raw = _initialProgressiveTrack0BlueprintJson;
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final restored = ReleaseBlueprint.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      _releaseBlueprint = restored;
      final relDoc = activeRelease;
      if (relDoc != null && relDoc.id == restored.releaseDocId) {
        relDoc.sections['release_blueprint_json'] = raw;
        _persistDocument(relDoc);
      }
      _syncActiveProjectMetadata();
      notifyListeners();
    } catch (_) {}
  }

  /// Restores the active release, blueprint, and production phase if the user cancels (or fails offline in)
  /// the Progressive Next Release modal, and removes any newly created unbuilt draft release documents.
  void restoreActiveReleaseAfterCancel(
    String? previousReleaseId,
    ProductionPhase previousPhase,
  ) {
    final proj = activeProject;
    final preIds = _preModalReleaseIds;
    if (proj != null && preIds != null) {
      final addedUnbuiltIds = proj.childrenIds
          .where((id) {
            if (preIds.contains(id)) return false;
            final relDoc = documents[id];
            return relDoc != null && relDoc.childrenIds.isEmpty;
          })
          .toList();
      final user = _authService.currentUser;
      for (final id in addedUnbuiltIds) {
        proj.childrenIds.remove(id);
        documents.remove(id);
        LocalVaultService.deleteDocument(id);
        if (user != null) {
          _firestoreService.deleteDocument(uid: user.uid, docId: id);
        }
      }
    }
    if (_preModalReleaseBlueprint != null) {
      _releaseBlueprint = _preModalReleaseBlueprint;
    }
    _preModalReleaseIds = null;
    _preModalReleaseBlueprint = null;
    if (previousReleaseId != null && documents.containsKey(previousReleaseId)) {
      _activeReleaseId = previousReleaseId;
    }
    if (proj != null) {
      repackProjectReleasesSequentially(
        proj,
        keepReleaseId: _activeReleaseId,
      );
    }
    _currentPhase = previousPhase;
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  /// Executes the prepared (or newly synthesized) next Progressive Release (`v0.2`, `v0.3+`)
  /// directly into `2. Workbench`.
  Future<void> buildProgressiveNextRelease({String? agentDirective}) async {
    final currentBp = _releaseBlueprint;
    final activeRel = activeRelease;
    if (currentBp == null ||
        (activeRel != null &&
            currentBp.releaseDocId == activeRel.id &&
            activeRel.childrenIds.isNotEmpty)) {
      await prepareProgressiveNextReleaseDraft(agentDirective: agentDirective);
    } else if (agentDirective != null && agentDirective.trim().isNotEmpty) {
      await sendReleasePlanChatMessage(agentDirective.trim());
    }
    if (_releaseBlueprint != null) {
      await approveAndExecuteReleasePlan();
    }
  }

  /// Synthesizes the Release Blueprint for the active Release.
  Future<void> openReleasePlanGate({
    String? releaseId,
    bool transitionToGateStage = false,
  }) async {
    if (releaseId != null) {
      _activeReleaseId = releaseId;
    }
    final existingProj = activeProject;
    if (_conceptDraft != null &&
        (existingProj == null || existingProj.childrenIds.isEmpty)) {
      _commitConceptToVault(_conceptDraft!, syncBuiltWorkbench: false);
    }

    final proj = activeProject;
    if (proj == null) return;

    final targetRelId = releaseId ??
        _activeReleaseId ??
        (proj.childrenIds.isNotEmpty ? proj.childrenIds.first : null);
    if (targetRelId == null) return;
    _activeReleaseId = targetRelId;

    // Collect existing live Beats & Features from prior releases (never from targetRelId itself,
    // and never when planning the initial v0.1 release) so v0.1 starts clean at 0% and v0.2+ preserves the single live game tree!
    final isFirstPrototypeRelease =
        proj.childrenIds.isEmpty || proj.childrenIds.first == targetRelId;
    final existingBeats = <TierDocument>[];
    final existingFeaturesByBeat = <String, List<TierDocument>>{};
    if (!isFirstPrototypeRelease) {
      for (final rel in projectReleases) {
        if (rel.id == targetRelId) continue;
        if (rel.childrenIds.isNotEmpty) {
          for (final beatId in rel.childrenIds) {
            final bDoc = documents[beatId];
            if (bDoc != null && !existingBeats.any((b) => b.id == bDoc.id)) {
              existingBeats.add(bDoc);
              existingFeaturesByBeat[bDoc.id] = featuresForBeat(bDoc.id);
            }
          }
        }
      }
    }

    // Capture any features deferred (unchecked) in the prior Release Plan Gate
    // so they automatically carry over into the next release's Beat, and archive the prior ReleaseBlueprint on its own Release doc!
    final deferredByBeatIndex = <int, List<ProposedFeatureBlueprint>>{};
    final priorBp = _releaseBlueprint;
    if (priorBp != null) {
      final priorRelDoc = documents[priorBp.releaseDocId];
      if (priorRelDoc != null) {
        priorRelDoc.sections['release_blueprint_json'] =
            jsonEncode(priorBp.toJson());
        _persistDocument(priorRelDoc);
      }
      for (int bIdx = 0; bIdx < priorBp.beats.length; bIdx++) {
        final seenTitles = <String>{};
        final deferredInBeat = <ProposedFeatureBlueprint>[];
        for (final df in priorBp.beats[bIdx].deferredFeatures) {
          final normTitle = df.title.toLowerCase().trim();
          if (normTitle.isNotEmpty && seenTitles.add(normTitle)) {
            deferredInBeat.add(df);
          }
        }
        if (deferredInBeat.isNotEmpty) {
          deferredByBeatIndex[bIdx] = deferredInBeat;
        }
      }
    }

    _activeReleaseId = targetRelId;
    final relDoc = documents[targetRelId];
    if (relDoc == null) return;
    _syncCurrentPhaseFromRelease(relDoc);

    // Clear _releaseBlueprint while gemini-4-argon is synthesizing so the UI shows an honest
    // Agent Architectural Synthesis state rather than a pre-baked or prior-release plan.
    _releaseBlueprint = null;
    final verTag = releaseVersionTagFor(relDoc);
    relDoc.sections['versionTag'] = verTag;
    _isAgentBusy = true;
    _agentProgressStep =
        'Synthesizing $verTag Release Architecture ($_planningModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final completedPriorReleases = projectReleases
          .where((r) => r.id != targetRelId && r.childrenIds.isNotEmpty)
          .toList();
      final planned = await ReleasePlannerAgent.planRelease(
        projectDoc: proj,
        releaseDoc: relDoc,
        completedReleases: completedPriorReleases,
        existingBeats: existingBeats,
        existingFeaturesByBeat: existingFeaturesByBeat,
        deferredByBeatIndex: deferredByBeatIndex,
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      if (planned != null) {
        if (planned.releaseTitle.isNotEmpty &&
            planned.releaseTitle != relDoc.title) {
          relDoc.title = planned.releaseTitle;
        }
        relDoc.sections['versionTag'] = verTag;
        relDoc.sections['release_blueprint_json'] =
            jsonEncode(planned.toJson());
        _syncCurrentPhaseFromRelease(relDoc);
        _persistDocument(relDoc);
        _releaseBlueprint = planned;
        _offlineErrorMessage = null;
        if (transitionToGateStage) {
          _currentStage = WorkbenchStage.releaseWorkbench;
        }
        _syncActiveProjectMetadata();
      } else {
        if (!isFirstPrototypeRelease && existingBeats.isNotEmpty) {
          _releaseBlueprint =
              ReleasePlannerAgent.buildImmediateProgressiveBaselineBlueprint(
            projectDoc: proj,
            releaseDoc: relDoc,
            existingBeats: existingBeats,
            existingFeaturesByBeat: existingFeaturesByBeat,
            deferredByBeatIndex: deferredByBeatIndex,
          );
        }
        _setOfflineState();
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Sends a user turn in the Stage 2 Release Plan Gate Chat to refine Beats, Features, or Scope.
  Future<void> sendReleasePlanChatMessage(String message) async {
    final bp = _releaseBlueprint;
    if (bp == null || message.trim().isEmpty) return;

    _isAgentBusy = true;
    _agentProgressStep =
        'Refining Release Plan ($_conversationModel · ${_thinkingLevel.toLowerCase()})...';
    notifyListeners();

    try {
      final ok = await ReleasePlannerAgent.sendReleasePlanChatTurn(
        blueprint: bp,
        userMessage: message,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (ok) {
        _offlineErrorMessage = null;
        _syncActiveProjectMetadata();
      } else {
        _setOfflineState();
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  /// Toggles whether a proposed Feature in the Release Plan Gate is kept in scope or deferred to Out of Scope.
  void toggleProposedFeatureScope(
    String beatId,
    String featureId,
    bool included,
  ) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        for (final feat in beat.features) {
          if (feat.id == featureId) {
            feat.included = included;
            _syncActiveProjectMetadata();
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  /// Toggles an existing Feature in the Progressive Release Planner between `UPGRADE` (`+4h` delta checkpoint)
  /// and `STABLE ✓` (`0h`, locked at 100%).
  void toggleProposedFeatureUpgradeOrStable(
    String beatId,
    String featureId,
  ) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    final verTag = bp.releaseVersionTag;
    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        for (final feat in beat.features) {
          if (feat.id == featureId) {
            if (feat.lifecycle == FeatureLifecycleStatus.upgrade) {
              feat.lifecycle = FeatureLifecycleStatus.stable;
              feat.estimatedHours = 0;
              feat.included = true;
            } else {
              feat.lifecycle = FeatureLifecycleStatus.upgrade;
              feat.included = true;
              if (feat.estimatedHours <= 0) {
                feat.estimatedHours = 4;
              }
              if (feat.checkpoints.isEmpty) {
                feat.checkpoints = [
                  ProposedCheckpointBlueprint(
                    title: '${feat.title} $verTag Upgrade',
                    playtestCriteria:
                        'Trigger ${feat.title} in playtest -> verify $verTag upgrade and polish',
                    tasks: [
                      'Component & State Upgrade (2h)',
                      'Logic & Feel Extension (1h)',
                      'State & Bounds Guard (1h)',
                    ],
                    coveredScope: feat.inScope.isNotEmpty
                        ? List<String>.from(feat.inScope)
                        : ['${feat.title} $verTag upgrade'],
                    tuningParams: List<String>.from(feat.tuningParams),
                    edgeCases: List<String>.from(feat.edgeCases),
                    releaseVersion: verTag,
                  ),
                ];
              }
            }
            _syncActiveProjectMetadata();
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  /// Adds a custom `+ NEW` feature to a Beat inside the Progressive Release Planner (`_releaseBlueprint`).
  ProposedFeatureBlueprint? addCustomFeatureToProposedBeat(
    String beatId,
    String rawTitle, {
    String? customGoal,
  }) {
    final bp = _releaseBlueprint;
    final cleanTitle = rawTitle
        .replaceFirst(RegExp(r'^No\s+', caseSensitive: false), '')
        .trim();
    if (bp == null || cleanTitle.isEmpty) return null;
    final verTag = bp.releaseVersionTag;
    for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) {
      final beat = bp.beats[bIdx];
      if (beat.id == beatId) {
        final newFeatId =
            'feat_${verTag}_${bIdx + 1}_${beat.features.length + 1}';
        final goalText = (customGoal != null && customGoal.trim().isNotEmpty)
            ? customGoal.trim()
            : 'Build $cleanTitle inside ${beat.title} for $verTag.';
        final created = ProposedFeatureBlueprint(
          id: newFeatId,
          title: cleanTitle,
          goal: goalText,
          doneWhen: 'Playtester verifies $cleanTitle in the arena.',
          estimatedHours: 4,
          included: true,
          lifecycle: FeatureLifecycleStatus.newFeature,
          originVersion: verTag,
          inScope: ['$cleanTitle core setup & feedback'],
          outOfScope: const [],
          tuningParams: const ['responseWindowSec: 0.25 s'],
          edgeCases: const ['[STATE GUARD] Prevent duplicate trigger while active'],
          checkpoints: [
            ProposedCheckpointBlueprint(
              title: '$cleanTitle Core',
              playtestCriteria:
                  'Trigger $cleanTitle in playtest -> responds cleanly on screen',
              tasks: const [
                'Actor & Component Setup (2h)',
                'Input & Core Logic (1h)',
                'State & Cooldown Guard (1h)',
              ],
              coveredScope: ['$cleanTitle core setup & feedback'],
              tuningParams: const ['responseWindowSec: 0.25 s'],
              edgeCases: const [
                '[STATE GUARD] Prevent duplicate trigger while active',
              ],
              releaseVersion: verTag,
            ),
          ],
        );
        beat.features.add(created);
        _syncActiveProjectMetadata();
        notifyListeners();
        return created;
      }
    }
    return null;
  }

  /// Promotes an Out-of-Scope exclusion item into a `+ NEW` feature in the Progressive Release Planner.
  ProposedFeatureBlueprint? promoteExclusionToNextRelease(
    String exclusionText, {
    String? targetBeatId,
  }) {
    final bp = _releaseBlueprint;
    if (bp == null || bp.beats.isEmpty) return null;
    final cleanEx = exclusionText.trim();
    if (cleanEx.isEmpty) return null;
    final shortTitle = cleanEx
        .replaceFirst(RegExp(r'^\[CUT\]\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^No\s+', caseSensitive: false), '')
        .split('—')
        .first
        .split(':')
        .first
        .trim();
    final targetBeat = targetBeatId != null
        ? bp.beats.firstWhere(
            (b) => b.id == targetBeatId,
            orElse: () => bp.beats.last,
          )
        : bp.beats.last;
    bp.explicitExclusions.removeWhere(
      (e) => e.toLowerCase().trim() == cleanEx.toLowerCase().trim(),
    );
    // Also remove from Stage 1 project exclusions so future Agent turns never treat this promoted item as banned
    final normShort = shortTitle.toLowerCase().trim();
    if (_conceptDraft != null) {
      _conceptDraft!.exclusions.removeWhere((e) {
        final normE = e
            .toLowerCase()
            .replaceFirst(RegExp(r'^\[cut\]\s*'), '')
            .replaceFirst(RegExp(r'^no\s+'), '')
            .trim();
        return e.toLowerCase().trim() == cleanEx.toLowerCase().trim() ||
            (normShort.isNotEmpty && normE.contains(normShort));
      });
    }
    final proj = activeProject;
    if (proj != null) {
      final rawEx = proj.sections['exclusions'] ?? '';
      final currentEx = rawEx
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^[•\-\*\s]+'), '').trim())
          .where((l) => l.isNotEmpty)
          .toList();
      currentEx.removeWhere((e) {
        final normE = e
            .toLowerCase()
            .replaceFirst(RegExp(r'^\[cut\]\s*'), '')
            .replaceFirst(RegExp(r'^no\s+'), '')
            .trim();
        return e.toLowerCase().trim() == cleanEx.toLowerCase().trim() ||
            (normShort.isNotEmpty && normE.contains(normShort));
      });
      proj.sections['exclusions'] =
          currentEx.map((e) => '• $e').join('\n');
      _persistDocument(proj, debounce: true);
    }
    return addCustomFeatureToProposedBeat(
      targetBeat.id,
      shortTitle.isNotEmpty ? shortTitle : cleanEx,
      customGoal: 'Promote "$shortTitle" into playable ${bp.releaseVersionTag} scope.',
    );
  }

  /// Adds a new Playable Feature directly into an active Epic (`beatId`) inside `2. Workbench`
  /// and enriches it via Gemini AI.
  String? addLiveFeatureToBeat(String beatId, String rawTitle) {
    final beatDoc = documents[beatId];
    final cleanTitle = rawTitle.trim();
    if (beatDoc == null || cleanTitle.isEmpty) return null;
    if (!GeminiAgentClient.hasKey(_apiKey) &&
        GeminiAgentClient.testMockResponder == null) {
      _setOfflineState();
      notifyListeners();
      return null;
    }

    final versionTag = activeReleaseVersionTag;
    final featId =
        'feat_${beatDoc.id}_${beatDoc.childrenIds.length + 1}_${DateTime.now().millisecondsSinceEpoch % 10000}';

    final featDoc = TierDocument(
      id: featId,
      title: cleanTitle,
      tier: TierType.feature,
      parentId: beatDoc.id,
      estimatedDuration: '4h',
      sections: {
        'originVersion': versionTag,
        'activeReleaseVersion': versionTag,
        'lifecycle': FeatureLifecycleStatus.newFeature.name,
        'scope': '',
        'variables': '',
        'tuning': '',
        'edge_cases': '',
      },
    );

    final stateNode = FeatureStateNode(
      id: '${featId}_${versionTag}_cp_1',
      name: 'Checkpoint 1: $cleanTitle',
      trigger: '',
      order: 0,
      checklist: const [],
      coveredScope: const [],
      tuningParams: const [],
      edgeCases: const [],
      parameters: {'releaseVersion': versionTag},
    );

    FeatureStateNode.saveStatesToDocument(featDoc, [stateNode]);
    documents[featId] = featDoc;
    beatDoc.childrenIds.add(featId);
    _persistDocument(featDoc);
    _persistDocument(beatDoc);

    // Keep _releaseBlueprint in sync if present
    final bp = _releaseBlueprint;
    if (bp != null) {
      for (final b in bp.beats) {
        if (b.id == beatId ||
            b.title.toLowerCase().trim() ==
                beatDoc.title.toLowerCase().trim()) {
          b.features.add(
            ProposedFeatureBlueprint(
              id: featId,
              title: cleanTitle,
              goal: '',
              doneWhen: '',
              estimatedHours: 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.newFeature,
              originVersion: versionTag,
              inScope: const [],
              outOfScope: const [],
              tuningParams: const [],
              edgeCases: const [],
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: cleanTitle,
                  playtestCriteria: '',
                  tasks: const [],
                  coveredScope: const [],
                  tuningParams: const [],
                  edgeCases: const [],
                  releaseVersion: versionTag,
                ),
              ],
            ),
          );
          break;
        }
      }
    }

    selectFeature(featId);
    _syncActiveProjectMetadata();
    _enrichLiveFeatureWithAi(featId, beatDoc.title);
    return featId;
  }

  Future<void> _enrichLiveFeatureWithAi(
    String featureId,
    String beatTitle,
  ) async {
    final featDoc = documents[featureId];
    if (featDoc == null) return;
    final states = FeatureStateNode.getStatesForDocument(featDoc);
    if (states.isEmpty) return;
    final projTitle = activeProject?.title ?? 'Game Prototype';
    final engineLabel = _activeEngineLabel;
    final prompt = '''
You are the Systems Designer for "$projTitle" ($engineLabel).
Tailor this newly added Feature ("${featDoc.title}" inside Epic "$beatTitle") so its tasks, numeric tuning parameters, and edge-case guards fit "$projTitle".
Return ONLY a JSON object:
{
  "goal": "<1 plain-English sentence starting with Build/Implement>",
  "doneWhen": "<1 observable playtest completion condition>",
  "checkpointTitle": "<2-4 word playable checkpoint title>",
  "playtestGate": "<Action -> Observable result>",
  "tasks": [
    "<Task 1 title> (2h)",
    "<Task 2 title> (1h)",
    "<Task 3 title> (1h)"
  ],
  "tuningParams": [
    "<param1: numericValue unit>",
    "<param2: numericValue unit>"
  ],
  "edgeCases": [
    "[STATE GUARD] <concise guard rule>"
  ]
}''';
    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: _apiKey,
      preferredModel: _conversationModel,
      thinkingLevel: _thinkingLevel,
      temperature: 0.4,
    );
    if (json != null && documents.containsKey(featureId)) {
      final cp = states.first;
      final aiGoal = json['goal']?.toString().trim() ?? '';
      final aiDoneWhen = json['doneWhen']?.toString().trim() ?? '';
      final aiTitle = json['checkpointTitle']?.toString().trim() ?? '';
      final aiGate = json['playtestGate']?.toString().trim() ?? '';
      final rawTasks = json['tasks'];
      final rawTuning = json['tuningParams'];
      final rawGuards = json['edgeCases'];
      if (aiGoal.isNotEmpty || aiDoneWhen.isNotEmpty) {
        final effectiveGoal = aiGoal.isNotEmpty
            ? aiGoal
            : 'Build ${featDoc.title} inside $beatTitle.';
        final effectiveDoneWhen = aiDoneWhen.isNotEmpty
            ? aiDoneWhen
            : (aiGate.isNotEmpty
                ? aiGate
                : 'Playtester verifies ${featDoc.title} in the test arena.');
        featDoc.sections['scope'] =
            'Goal: $effectiveGoal\n\nIn Scope:\n• ${featDoc.title}\n\nDone When: $effectiveDoneWhen';
        _persistDocument(featDoc);
        final bp = _releaseBlueprint;
        if (bp != null) {
          for (final b in bp.beats) {
            for (final f in b.features) {
              if (f.id == featureId) {
                f.goal = effectiveGoal;
                f.doneWhen = effectiveDoneWhen;
              }
            }
          }
        }
      }
      if (aiTitle.isNotEmpty) {
        cp.name = 'Checkpoint 1: $aiTitle';
      }
      if (aiGate.isNotEmpty) {
        cp.trigger = 'Playtest: $aiGate';
      }
      if (rawTasks is List && rawTasks.isNotEmpty) {
        cp.checklist = [
          for (int i = 0; i < rawTasks.length; i++)
            Subtask(
              id: '${featureId}_ai_t${i + 1}',
              text: rawTasks[i].toString().trim(),
              completed: false,
            ),
        ];
      }
      if (rawTuning is List && rawTuning.isNotEmpty) {
        cp.tuningParams =
            rawTuning.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      if (rawGuards is List && rawGuards.isNotEmpty) {
        cp.edgeCases =
            rawGuards.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      updateFeatureStates(featureId, states);
    }
    await synthesizeFeatureHowToStepsWithAi(featureId, forceRefresh: true);
  }

  /// Renames an active Feature document directly inside `2. Workbench` and syncs `_releaseBlueprint`.
  void renameLiveFeature(String featureId, String newTitle) {
    final featDoc = documents[featureId];
    final cleanTitle = newTitle.trim();
    if (featDoc == null || cleanTitle.isEmpty) return;

    final oldTitle = featDoc.title;
    featDoc.title = cleanTitle;
    _persistDocument(featDoc);

    final bp = _releaseBlueprint;
    if (bp != null) {
      for (final b in bp.beats) {
        for (final f in b.features) {
          if (f.id == featureId ||
              f.title.toLowerCase().trim() == oldTitle.toLowerCase().trim()) {
            f.title = cleanTitle;
          }
        }
      }
    }
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  /// Removes/defers a Feature document from its parent Epic inside `2. Workbench`
  /// and automatically selects the next available Feature.
  bool removeLiveFeature(String featureId) {
    final featDoc = documents[featureId];
    if (featDoc == null) return false;
    final parentBeatId = featDoc.parentId;
    final beatDoc = parentBeatId != null ? documents[parentBeatId] : null;
    final isArchivedFeat =
        featDoc.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name;

    // Prevent deleting the very last feature in the entire release so the Workbench never empties
    final allFeats = <TierDocument>[
      for (final b in activeReleaseBeats) ...featuresForBeat(b.id),
    ];
    if (!isArchivedFeat && allFeats.length <= 1) return false;

    if (beatDoc != null) {
      beatDoc.childrenIds.remove(featureId);
      _persistDocument(beatDoc);
    }
    documents.remove(featureId);
    LocalVaultService.deleteDocument(featureId);
    final user = _authService.currentUser;
    if (user != null) {
      _firestoreService.deleteDocument(uid: user.uid, docId: featureId);
    }

    final bp = _releaseBlueprint;
    if (bp != null) {
      for (final b in bp.beats) {
        for (final f in b.features) {
          if (f.id == featureId ||
              f.title.toLowerCase().trim() ==
                  featDoc.title.toLowerCase().trim()) {
            f.included = false;
          }
        }
      }
    }

    if (_releaseViewFilter == 'archived') {
      final remainingArchived = supersededFeatures;
      if (remainingArchived.isNotEmpty) {
        if (_selectedFeatureId == featureId) {
          _selectedFeatureId = remainingArchived.first.id;
        }
      } else {
        _releaseViewFilter = 'active';
        _selectFirstIncompleteFeatureInActiveRelease();
      }
    } else if (_selectedFeatureId == featureId) {
      _selectFirstIncompleteFeatureInActiveRelease();
    }
    _syncActiveProjectMetadata();
    notifyListeners();
    return true;
  }

  /// Logs a Playtest Issue on a Checkpoint in `2. Workbench`:
  /// 1. Appends a `[FIX] <issueDescription> (1h)` Parent Task to `cpNode.checklist` with
  ///    3 checkable, engine-aware debug/fix How-To Sub-Steps.
  /// 2. Appends `[PLAYTEST GUARD] <issueDescription>` to `cpNode.edgeCases`.
  /// Returns the index of the newly created `[FIX]` Parent Task.
  int logPlaytestIssueOnCheckpoint({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required String issueDescription,
  }) {
    final cleanIssue = issueDescription.trim();
    if (cleanIssue.isEmpty ||
        checkpointIndex < 0 ||
        checkpointIndex >= states.length) {
      return -1;
    }
    final cpNode = states[checkpointIndex];
    final newTaskIndex = cpNode.checklist.length;
    final taskNum = newTaskIndex + 1;
    final engineLabel = _activeEngineLabel;
    final isUnity = engineLabel.contains('Unity');
    final isUnreal = engineLabel.contains('Unreal');
    final primaryTune = cpNode.tuningParams.isNotEmpty
        ? cpNode.tuningParams.first
        : 'threshold: 1.0';

    final fixTask = Subtask(
      id: generateUniqueId('fix_task'),
      text: '[FIX] $cleanIssue (1h)',
      completed: false,
      children: [
        Subtask(
          id: generateUniqueId('fix_sub_1'),
          text: 'STEP $taskNum.1 · REPRODUCE & INSPECT PLAYTEST ISSUE',
          specNotes:
              'Trigger "$cleanIssue" in the game viewport and inspect live state values ($primaryTune).',
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Inspect live state when "$cleanIssue" occurs\nDebug.LogWarning("[PLAYTEST FIX] $cleanIssue | $primaryTune");'
              : (isUnreal
                  ? '// Inspect live state when "$cleanIssue" occurs\nUE_LOG(LogTemp, Warning, TEXT("[PLAYTEST FIX] %s"), *GetName());'
                  : '# Inspect live state when "$cleanIssue" occurs\nprint("[PLAYTEST FIX] $cleanIssue | $primaryTune")'),
        ),
        Subtask(
          id: generateUniqueId('fix_sub_2'),
          text: 'STEP $taskNum.2 · APPLY FIX & CLAMP TUNING BOUNDS',
          specNotes:
              'Adjust the update/collision logic and clamp $primaryTune so "$cleanIssue" cannot happen.',
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Enforce boundary check for: $cleanIssue\n// Active tuning: $primaryTune'
              : (isUnreal
                  ? '// Enforce boundary check for: $cleanIssue\n// Active tuning: $primaryTune'
                  : '# Enforce boundary check for: $cleanIssue\n# Active tuning: $primaryTune'),
        ),
        Subtask(
          id: generateUniqueId('fix_sub_3'),
          text: 'STEP $taskNum.3 · VERIFY PLAYTEST GUARD IN VIEWPORT',
          specNotes:
              'Re-run the checkpoint playtest gate ("${cpNode.playtestCondition}") 3 times to confirm "$cleanIssue" is resolved.',
          codeTargetFile: 'custom_snippet',
          codeSnippet: isUnity
              ? '// Verify guard in Play mode: [PLAYTEST GUARD] $cleanIssue'
              : (isUnreal
                  ? '// Verify guard in Play mode: [PLAYTEST GUARD] $cleanIssue'
                  : '# Verify guard in Play mode: [PLAYTEST GUARD] $cleanIssue'),
        ),
      ],
    );

    cpNode.checklist.add(fixTask);
    final guardText = '[PLAYTEST GUARD] $cleanIssue';
    if (!cpNode.edgeCases.contains(guardText)) {
      cpNode.edgeCases = [...cpNode.edgeCases, guardText];
    }
    updateFeatureStates(featureId, states);
    if (GeminiAgentClient.hasKey(_apiKey) ||
        GeminiAgentClient.testMockResponder != null) {
      _enrichPlaytestFixWithAi(
        featureId: featureId,
        states: states,
        checkpointIndex: checkpointIndex,
        fixTaskIndex: newTaskIndex,
        issueDescription: cleanIssue,
      );
    } else {
      _setOfflineState();
      notifyListeners();
    }
    return newTaskIndex;
  }

  Future<void> _enrichPlaytestFixWithAi({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required int fixTaskIndex,
    required String issueDescription,
  }) async {
    if (checkpointIndex < 0 || checkpointIndex >= states.length) return;
    final cpNode = states[checkpointIndex];
    if (fixTaskIndex < 0 || fixTaskIndex >= cpNode.checklist.length) return;
    final fixTask = cpNode.checklist[fixTaskIndex];
    final featTitle = documents[featureId]?.title ?? cpNode.cleanStageTitle;
    final engineLabel = _activeEngineLabel;
    final taskNum = fixTaskIndex + 1;

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();
    try {
      final prompt = '''
You are the Playtest Root-Cause Debugger for LAYERS-Agentic ($engineLabel).
Diagnose this reported playtest bug on Feature "$featTitle" (Checkpoint "${cpNode.cleanStageTitle}") and synthesize a concrete 3-step engine fix:
Reported Bug: "$issueDescription"
Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Guards: ${cpNode.edgeCases.join(', ')}

Return ONLY a JSON object with 3 concrete fix steps:
{
  "playtestGuard": "[PLAYTEST GUARD] <1 concise rule preventing this bug>",
  "steps": [
    {
      "title": "STEP $taskNum.1 · <SHORT LITERAL STEP TITLE>",
      "stepPath": "<Exact $engineLabel panel/inspector/script path>",
      "instruction": "<1 sentence concrete fix/inspection instruction>",
      "codeFormula": "<2-4 lines of $engineLabel code or node setup>",
      "verifyResult": "<1 sentence visual/console check in Play mode>"
    }
  ]
}''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _planningModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.3,
      );
      if (json == null) return;
      final rawSteps = json['steps'];
      if (rawSteps is List && rawSteps.isNotEmpty) {
        final updatedSubs = <Subtask>[];
        for (int i = 0; i < rawSteps.length; i++) {
          final item = rawSteps[i];
          if (item is Map) {
            final title = item['title']?.toString().trim() ?? '';
            final path = item['stepPath']?.toString().trim() ?? '';
            final instr = item['instruction']?.toString().trim() ?? '';
            final code = item['codeFormula']?.toString().trim() ?? '';
            final verify = item['verifyResult']?.toString().trim() ?? '';
            final prevDone = i < fixTask.children.length
                ? fixTask.children[i].completed
                : false;
            updatedSubs.add(
              Subtask(
                id: i < fixTask.children.length
                    ? fixTask.children[i].id
                    : generateUniqueId('fix_ai_sub_${i + 1}'),
                text: title.isNotEmpty
                    ? title
                    : 'STEP $taskNum.${i + 1} · APPLY ROOT-CAUSE FIX ${i + 1}',
                specNotes: instr,
                codeSnippet: code,
                codeLanguage: path,
                verification: verify,
                codeTargetFile: 'custom_snippet',
                completed: prevDone,
              ),
            );
          }
        }
        if (updatedSubs.isNotEmpty) {
          fixTask.children = updatedSubs;
        }
      }
      final aiGuard = json['playtestGuard']?.toString().trim() ?? '';
      if (aiGuard.isNotEmpty) {
        final normGuard = aiGuard.startsWith('[PLAYTEST GUARD]')
            ? aiGuard
            : '[PLAYTEST GUARD] $aiGuard';
        if (!cpNode.edgeCases.contains(normGuard)) {
          cpNode.edgeCases = [...cpNode.edgeCases, normGuard];
        }
      }
      TaskHowToBlueprint.clearCache();
      updateFeatureStates(featureId, states);
    } finally {
      _synthesizingFeatureIds.remove(featureId);
      notifyListeners();
    }
  }

  /// Tailors the checkable How-To sub-steps (`Step X.1` through `Step X.N`) for a specific
  /// Parent Task in `2. Workbench` using Gemini AI (`gemini-flash-latest`).
  /// Returns `true` if AI sub-steps were synthesized and applied, or `false` if offline/failed.
  Future<bool> tailorTaskHowToSubSteps({
    required String featureId,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required int taskIndex,
    required String userContext,
  }) async {
    final cleanContext = userContext.trim();
    if (cleanContext.isEmpty ||
        checkpointIndex < 0 ||
        checkpointIndex >= states.length) {
      return false;
    }
    final cpNode = states[checkpointIndex];
    if (taskIndex < 0 || taskIndex >= cpNode.checklist.length) return false;
    final parentTask = cpNode.checklist[taskIndex];
    final featDoc = documents[featureId];
    final engineHint = _activeEngineHint;
    final engineLabel = _activeEngineLabel;
    final taskNum = taskIndex + 1;

    // Ensure children are initialized first
    TaskHowToBlueprint.resolve(
      parentTask: parentTask,
      taskIndex: taskIndex,
      checkpointNode: cpNode,
      engineHint: engineHint,
    );

    if (!GeminiAgentClient.hasKey(_apiKey)) {
      _setOfflineState();
      return false;
    }

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();
    try {
      final prompt = '''
You are a senior game engine programmer assisting with a concrete implementation task.
Engine: $engineLabel
Feature: "${featDoc?.title ?? cpNode.name}"
Task ($taskNum): "${parentTask.text}"
Active Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Active Edge-Case Guards: ${cpNode.edgeCases.join(', ')}
Developer's Exact Scene / Node / Script Setup: "$cleanContext"

Break this task down into the exact number of checkable How-To Sub-Steps (Step $taskNum.1 through Step $taskNum.N — e.g., 3 steps for a simple hook/guard task or up to 6 steps for a multi-part mechanic) specifically using the developer's node/script names from "$cleanContext".
Return ONLY a JSON object with this schema:
{
  "subSteps": [
    {
      "title": "STEP $taskNum.1 · SHORT LITERAL SUB-STEP TITLE",
      "stepPath": "Exact $engineLabel editor panel/inspector/script path",
      "instruction": "1-sentence literal instruction referencing the user's exact nodes/scripts",
      "codeFormula": "2-4 lines of $engineLabel code or hierarchy setup using the user's node/script names",
      "verifyResult": "1-sentence observable verification check in Play mode"
    }
  ]
}
''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _planningModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.25,
      );
      final rawSubs = json?['subSteps'];
      if (rawSubs is List && rawSubs.isNotEmpty) {
        final newChildren = <Subtask>[];
        for (int i = 0; i < rawSubs.length; i++) {
          final item = rawSubs[i];
          if (item is Map) {
            final t = (item['title'] ?? '').toString().trim();
            final path = (item['stepPath'] ?? '').toString().trim();
            final instr = (item['instruction'] ?? '').toString().trim();
            final code = (item['codeFormula'] ?? '').toString().trim();
            final verify = (item['verifyResult'] ?? '').toString().trim();
            final prevDone = i < parentTask.children.length
                ? parentTask.children[i].completed
                : parentTask.completed;
            newChildren.add(
              Subtask(
                id: '${parentTask.id}_sub_${i + 1}',
                text: t.isNotEmpty
                    ? t
                    : 'STEP $taskNum.${i + 1} · IMPLEMENT STEP ${i + 1}',
                specNotes: instr,
                codeSnippet: code,
                codeLanguage: path,
                verification: verify,
                codeTargetFile: 'custom_snippet',
                completed: prevDone,
              ),
            );
          }
        }
        if (newChildren.isNotEmpty) {
          _offlineErrorMessage = null;
          parentTask.children = newChildren;
          TaskHowToBlueprint.clearCache();
          updateFeatureStates(featureId, states);
          return true;
        }
      }

      _setOfflineState();
      return false;
    } finally {
      _synthesizingFeatureIds.remove(featureId);
      notifyListeners();
    }
  }

  /// Stage 2 -> Stage 3: User approves the Release Plan Gate; Executor Agent builds or evolves the Release hierarchy.
  Future<void> approveAndExecuteReleasePlan() async {
    final bp = _releaseBlueprint;
    final relDoc = activeRelease;
    if (bp == null || relDoc == null) return;

    _isAgentBusy = true;
    _executionLog.clear();
    _currentStage = WorkbenchStage.releaseWorkbench;
    _releaseViewFilter = 'active';
    notifyListeners();

    try {
      final createdDocs = await ReleaseExecutorAgent.executeBlueprint(
        releaseDoc: relDoc,
        blueprint: bp,
        existingDocuments: documents,
        onProgress: (msg) {
          _agentProgressStep = msg;
          _executionLog.add(msg);
          notifyListeners();
        },
      );

      for (final d in createdDocs) {
        documents[d.id] = d;
        _persistDocument(d);
      }
      _persistDocument(relDoc);

      // Auto-select the first Feature that has incomplete checkpoints (or Beat 1 / Feature 1)
      // before syncing project metadata so selected_beat_id / selected_feature_id are persisted together.
      _selectFirstIncompleteFeatureInActiveRelease();
      _syncActiveProjectMetadata();
      if (GeminiAgentClient.hasKey(_apiKey) ||
          GeminiAgentClient.testMockResponder != null) {
        final activeFeatureIds = <String>[
          for (final b in activeReleaseBeats)
            for (final f in featuresForBeat(b.id))
              if (isFeatureActiveInRelease(f)) f.id,
        ];
        if (activeFeatureIds.isNotEmpty) {
          final primaryFeatId = (_selectedFeatureId != null &&
                  activeFeatureIds.contains(_selectedFeatureId))
              ? _selectedFeatureId!
              : activeFeatureIds.first;
          final primaryTitle =
              documents[primaryFeatId]?.title ?? 'Primary Feature';
          _agentProgressStep =
              'Synthesizing Engine Steps for $primaryTitle ($_planningModel)...';
          _executionLog.add(_agentProgressStep!);
          notifyListeners();
          await synthesizeFeatureHowToStepsWithAi(primaryFeatId);

          final remainingFeatIds = activeFeatureIds
              .where((id) => id != primaryFeatId)
              .toList();
          if (remainingFeatIds.isNotEmpty) {
            if (GeminiAgentClient.testMockResponder != null) {
              await Future.wait(
                remainingFeatIds.map(
                  (fId) => synthesizeFeatureHowToStepsWithAi(fId),
                ),
              );
            } else {
              unawaited(
                _prefetchRemainingFeatureStepsInBackground(remainingFeatIds),
              );
            }
          }
        }
      }
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
      notifyListeners();
    }
  }

  Future<void> _prefetchRemainingFeatureStepsInBackground(
    List<String> featureIds,
  ) async {
    final startProjectId = _activeProjectId;
    final startReleaseId = _activeReleaseId;
    for (final fId in featureIds) {
      if (_activeProjectId != startProjectId ||
          _activeReleaseId != startReleaseId) {
        break;
      }
      if (!documents.containsKey(fId)) continue;
      await synthesizeFeatureHowToStepsWithAi(fId);
    }
  }

  bool isSynthesizingFeatureSteps(String featureId) =>
      _synthesizingFeatureIds.contains(featureId);

  /// Synthesizes bespoke, engine-specific 3-Area How-To Sub-Steps (`Hierarchy` -> `Inspector` -> `Code` -> `Verify`)
  /// for the active checkpoint of `featureId` using `_planningModel` (`gemini-4-argon`),
  /// reasoning through the project's cumulative asset state, exact variable names, and previous checkpoints.
  Future<void> synthesizeFeatureHowToStepsWithAi(
    String featureId, {
    bool forceRefresh = false,
    bool unrealCppMode = false,
  }) async {
    if (!GeminiAgentClient.hasKey(_apiKey) &&
        GeminiAgentClient.testMockResponder == null) {
      return;
    }
    final feat = documents[featureId];
    if (feat == null) return;
    final engineLabel = _activeEngineLabel;
    final engineHint = _activeEngineHint;
    final activeVer = activeReleaseVersionTag;
    final modeSuffix = engineLabel == 'UNREAL 5'
        ? (unrealCppMode ? '_CPP' : '_BP')
        : '';
    final synthKey = '${featureId}_${activeVer}_$engineLabel$modeSuffix';
    if (!forceRefresh &&
        (_aiSynthesizedFeatureSteps.contains(synthKey) ||
            _synthesizingFeatureIds.contains(featureId))) {
      return;
    }

    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isEmpty) return;
    int cpIndex = states.indexWhere(
      (s) => s.releaseVersion == activeVer && !s.isCompleted,
    );
    if (cpIndex < 0) {
      cpIndex = states.lastIndexWhere((s) => s.releaseVersion == activeVer);
    }
    final effectiveCpIndex = cpIndex >= 0 ? cpIndex : 0;
    final cpNode = states[effectiveCpIndex];
    if (cpNode.checklist.isEmpty) return;

    // Skip if already customized with custom_snippet across tasks (unless forceRefresh)
    final alreadyCustom = cpNode.checklist.every(
      (t) =>
          t.children.isNotEmpty &&
          t.children.every((c) => c.codeTargetFile == 'custom_snippet'),
    );
    if (!forceRefresh && alreadyCustom) {
      _aiSynthesizedFeatureSteps.add(synthKey);
      return;
    }

    for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
      TaskHowToBlueprint.resolve(
        parentTask: cpNode.checklist[tIdx],
        taskIndex: tIdx,
        checkpointNode: cpNode,
        engineHint: engineHint,
        unrealCppMode: unrealCppMode,
      );
    }

    _synthesizingFeatureIds.add(featureId);
    notifyListeners();

    try {
      final projTitle = activeProject?.title ?? 'Game Prototype';
      final taskSummaries = <String>[];
      for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
        taskSummaries.add(
          'Task ${tIdx + 1} (taskIndex: $tIdx): "${cpNode.checklist[tIdx].text}"',
        );
      }

      // Determine project-wide feature build order so the agent knows what assets already exist vs. must be created first
      final allReleaseFeatures = <TierDocument>[
        for (final b in activeReleaseBeats) ...featuresForBeat(b.id),
      ];
      final featOrderIdx =
          allReleaseFeatures.indexWhere((f) => f.id == featureId);
      final isGreenfieldFirstFeature =
          (featOrderIdx <= 0) && effectiveCpIndex == 0;
      final precedingFeatureTitles = featOrderIdx > 0
          ? allReleaseFeatures
              .take(featOrderIdx)
              .map((f) => '"${f.title}"')
              .toList()
          : const <String>[];
      final projectBuildStateContext = isGreenfieldFirstFeature
          ? 'Project Build State: FEATURE #1 OF THE ENTIRE PROJECT (Greenfield). No Character Blueprint, Pawn, or Input Mapping Context exists yet. You MUST create the playable character/foundation asset (e.g., BP_PlayerCharacter inheriting from ACharacter with CapsuleComponent, CameraComponent, and CharacterMovement) and possess it in the level before or alongside wiring input and physics.'
          : 'Project Build State: Feature #${featOrderIdx + 1} in the release (preceded by: ${precedingFeatureTitles.join(', ')}). Reuse and extend the existing player character (e.g., BP_PlayerCharacter and IMC_Default) for player-attached mechanics, or create this feature\'s dedicated Actor and connect it to the existing player character.';

      // Gather previous checkpoints & sibling features' exact variable names and guards
      final priorCheckpointsSummary = <String>[];
      for (int i = 0; i < effectiveCpIndex; i++) {
        final prev = states[i];
        priorCheckpointsSummary.add(
          '- ${prev.cleanStageTitle} (${prev.releaseVersion}): vars=[${prev.tuningParams.join(', ')}], guards=[${prev.edgeCases.join(', ')}]',
        );
      }
      if (feat.parentId != null) {
        for (final sib in featuresForBeat(feat.parentId!)) {
          if (sib.id == feat.id) continue;
          final sibStates = FeatureStateNode.getStatesForDocument(sib);
          for (final sibCp in sibStates) {
            if (sibCp.tuningParams.isNotEmpty) {
              priorCheckpointsSummary.add(
                '- Sibling Feature "${sib.title}" (${sibCp.releaseVersion}): vars=[${sibCp.tuningParams.join(', ')}]',
              );
            }
          }
        }
      }

      final cleanEdgeCases = cpNode.edgeCases
          .map(
            (g) => g
                .replaceAll(RegExp(r'^\s*(?:\[[^\]]+\]\s*)+'), '')
                .trim(),
          )
          .where((g) => g.isNotEmpty)
          .toList();

      final targetEngineMode = engineLabel == 'UNREAL 5'
          ? (unrealCppMode ? 'UNREAL 5 C++ (.h / .cpp)' : 'UNREAL 5 BLUEPRINTS')
          : (engineLabel == 'UNITY C#'
              ? 'UNITY C# (MonoBehaviour)'
              : 'GODOT 4 (GDScript 2.0)');

      final prompt = '''
You are the Principal Game Engine Architect ($targetEngineMode) for "$projTitle".
Synthesize concrete, beginner-friendly 3-Area Engine How-To steps for Feature "${feat.title}" (Checkpoint "${cpNode.cleanStageTitle}").
$projectBuildStateContext
Tasks:
${taskSummaries.join('\n')}
Active Tuning Parameters (MUST use exact variable names): ${cpNode.tuningParams.join(', ')}
Active Guards (MUST enforce in code without raw [TAG] brackets in prose): ${cleanEdgeCases.join(', ')}
${priorCheckpointsSummary.isNotEmpty ? 'Previous Checkpoints & Project Variable Context (reuse exact identifiers):\n${priorCheckpointsSummary.join('\n')}' : ''}

CRITICAL MULTI-TASK CONTINUITY & ORDERING RULES:
- ONE CANONICAL ASSET ACROSS ALL TASKS: Choose ONE primary asset/class/scene for "${feat.title}" (e.g., BP_PlayerCharacter / PlayerCharacter.cs / player_character.tscn for player movement/actions, or a single Actor/Scene for world mechanics). NEVER create a throwaway Actor (such as "BP_InputMappingBasic" or "BP_InputMappingMovement") just to replace it with BP_PlayerCharacter in the next task.
- STRICT TASK-ROLE ALIGNMENT & CUMULATIVE HAND-OFF (NO BLEEDING OR SHIFTING): Each task's subSteps MUST strictly implement that specific task's title while building cumulatively on the preceding task:
  * If Task 1 is Asset/Pawn/Character/Actor Setup: Step 1.1 creates the canonical asset (e.g., BP_PlayerCharacter inheriting from ACharacter with CapsuleComponent, CameraComponent, CharacterMovement), configures its base variables, and places/possesses it in the level. Then Task 2 creates/binds the Input Actions (IA_Move, IA_Sprint, IA_Slide) and IMC_Default inside that same asset and wires the core mechanic velocity/action logic. Then Task 3 stays inside that same asset to tune physics/capsule/friction (${cpNode.tuningParams.join(', ')}) and enforce the guards (${cleanEdgeCases.join(', ')}).
  * If Task 1 is Input Mapping: Task 1 creates and verifies the Enhanced Input Action(s) (IA_...) and Input Mapping Context (IMC_Default) in /Game/Input (NEVER a throwaway Actor). Then Task 2 Step 2.1 creates/opens BP_PlayerCharacter (ACharacter with CapsuleComponent, CameraComponent, CharacterMovement), registers IMC_Default from Task 1 on BeginPlay, and wires Task 1's Input Action into the core velocity/physics logic. Then Task 3 extends that same BP_PlayerCharacter with the remaining physics/animation/guard steps.

For each task (taskIndex: 0..${cpNode.checklist.length - 1}), return 3 to 5 sequential sub-steps covering the 3 Engine Areas (1. Hierarchy/Components, 2. Inspector/Details Bindings, 3. Attached Script/Graph Code) and using the project's exact variable names:
1. "title": "STEP X.Y · SHORT LITERAL STEP TITLE"
2. "stepPath": Exact $targetEngineMode editor panel/menu/inspector/script path
3. "instruction": 1-2 sentences explaining what to click or type in $targetEngineMode
4. "area1Hierarchy": Optional Scene/Component hierarchy tree using ├─ / └─ when the step adds or modifies nodes/components (or "" if pure code step)
5. "area2Inspector": Inspector/Details bindings formatted as "Property: Value | Property2: Value2" using the exact tuning parameter names
6. "codeFormula": 2-6 lines of concrete $targetEngineMode code or node graph wiring using the exact tuning variables and guard checks
7. "verifyResult": 1 sentence observable verification check in the editor or Play mode

Return ONLY valid JSON:
{
  "tasks": [
    {
      "taskIndex": 0,
      "subSteps": [
        {
          "title": "STEP 1.1 · ...",
          "stepPath": "...",
          "instruction": "...",
          "area1Hierarchy": "...",
          "area2Inspector": "paramName: value | ...",
          "codeFormula": "...",
          "verifyResult": "..."
        }
      ]
    }
  ]
}''';

      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _planningModel,
        thinkingLevel: _thinkingLevel,
        temperature: 0.25,
      );
      final rawTasks = json?['tasks'];
      if (rawTasks is! List || rawTasks.isEmpty) return;

      final parsedTaskIndices = rawTasks
          .whereType<Map>()
          .map((t) => int.tryParse(t['taskIndex']?.toString() ?? '') ?? -1)
          .where((idx) => idx >= 0)
          .toList();
      final isOneBasedTaskIndexing = parsedTaskIndices.isNotEmpty &&
          !parsedTaskIndices.contains(0) &&
          parsedTaskIndices.every(
            (idx) => idx >= 1 && idx <= cpNode.checklist.length,
          );
      final useDirectPositionalMapping =
          rawTasks.length == cpNode.checklist.length;

      bool mutated = false;
      for (int listIdx = 0; listIdx < rawTasks.length; listIdx++) {
        final rawTask = rawTasks[listIdx];
        if (rawTask is! Map) continue;
        final rawIdx =
            int.tryParse(rawTask['taskIndex']?.toString() ?? '') ?? -1;
        final tIdx = useDirectPositionalMapping
            ? listIdx
            : (rawIdx < 0
                ? listIdx
                : (isOneBasedTaskIndexing ? rawIdx - 1 : rawIdx));
        if (tIdx < 0 || tIdx >= cpNode.checklist.length) continue;
        final parentTask = cpNode.checklist[tIdx];
        final taskNum = tIdx + 1;
        final rawSubs = rawTask['subSteps'];
        if (rawSubs is! List || rawSubs.isEmpty) continue;

        final newChildren = <Subtask>[];
        for (int sIdx = 0; sIdx < rawSubs.length; sIdx++) {
          final item = rawSubs[sIdx];
          if (item is! Map) continue;
          final rawTitle = item['title']?.toString().trim() ?? '';
          final strippedTitle = rawTitle
              .replaceFirst(
                RegExp(r'^STEP\s+\d+(?:\.\d+)?\s*[·:\-]\s*', caseSensitive: false),
                '',
              )
              .trim();
          final title = strippedTitle.isNotEmpty
              ? 'STEP $taskNum.${sIdx + 1} · $strippedTitle'
              : '';
          final path = item['stepPath']?.toString().trim() ?? '';
          final instr = item['instruction']?.toString().trim() ?? '';
          final area1 = item['area1Hierarchy']?.toString().trim() ?? '';
          final area2 = item['area2Inspector']?.toString().trim() ?? '';
          final code = item['codeFormula']?.toString().trim() ?? '';
          final verify = item['verifyResult']?.toString().trim() ?? '';
          if (instr.isEmpty && code.isEmpty) continue;
          final prevDone = sIdx < parentTask.children.length
              ? parentTask.children[sIdx].completed
              : parentTask.completed;
          final encodedNotes = TaskHowToBlueprint.encodeThreeAreaNotes(
            instruction: instr,
            area1Hierarchy: area1,
            area2Inspector: area2,
          );
          newChildren.add(
            Subtask(
              id: '${parentTask.id}_sub_${sIdx + 1}',
              text: title.isNotEmpty
                  ? title
                  : 'STEP $taskNum.${sIdx + 1} · IMPLEMENT STEP ${sIdx + 1}',
              specNotes: encodedNotes,
              codeSnippet: code,
              codeLanguage: path,
              verification: verify,
              codeTargetFile: 'custom_snippet',
              completed: prevDone,
            ),
          );
        }
        if (newChildren.isNotEmpty) {
          parentTask.children = newChildren;
          mutated = true;
        }
      }

      if (mutated) {
        _aiSynthesizedFeatureSteps.add(synthKey);
        TaskHowToBlueprint.clearCache();
        updateFeatureStates(featureId, states);
      }
    } finally {
      _synthesizingFeatureIds.remove(featureId);
      notifyListeners();
    }
  }

  /// Generates a drop-in `AGENTS.md` / `.cursorrules` context file for the Active Release (`v0.1`, `v0.2`, etc.)
  /// containing the release's engine architecture, Epic/Feature hierarchy, canonical tuning variable table,
  /// mandatory `[GUARD]` rules, and 3-Area implementation steps.
  String buildActiveReleaseCodingAgentMarkdown({bool unrealCppMode = false}) {
    final draft = _conceptDraft;
    final proj = activeProject;
    final rel = activeRelease;
    final activeVer = activeReleaseVersionTag;
    final engineHint = _activeEngineHint;
    final engineLabel = _activeEngineLabel;
    final effectiveEngineTarget = engineLabel == 'UNREAL 5'
        ? (unrealCppMode ? 'UNREAL 5 C++ (.h / .cpp)' : 'UNREAL 5 BLUEPRINTS')
        : (engineLabel == 'UNITY C#'
            ? 'UNITY C# (MonoBehaviour)'
            : 'GODOT 4 (GDScript 2.0)');
    final projectTitle = (draft != null && draft.title.trim().isNotEmpty)
        ? draft.title.trim()
        : (proj != null && proj.title.trim().isNotEmpty
            ? proj.title.trim()
            : 'LAYERS-Agentic Game Project');
    final relTitle = rel?.title ?? '$activeVer Prototype';

    final sb = StringBuffer();
    sb.writeln('# AGENTS.md — $projectTitle ($activeVer AI Coding Agent Context)');
    sb.writeln(
      '> Drop this file into your game repository root as `AGENTS.md` or `.cursorrules` so your AI coding agent builds strictly within the active release scope, variable names, and playtest guards.',
    );

    sb.writeln('\n## 1. Engine & Architecture Rules');
    sb.writeln('- **Project**: $projectTitle');
    sb.writeln('- **Active Release**: $relTitle (`$activeVer`)');
    sb.writeln('- **Target Engine**: $effectiveEngineTarget');
    if (draft != null) {
      if (draft.goal.trim().isNotEmpty) {
        sb.writeln('- **Goal**: ${draft.goal.trim()}');
      }
      if (draft.designPillars.isNotEmpty) {
        sb.writeln('- **Design Pillars**: ${draft.designPillars.join(' · ')}');
      }
      if (draft.tradeOffs.isNotEmpty) {
        sb.writeln('- **Engineering Trade-Offs**: ${draft.tradeOffs.join(' · ')}');
      }
      if (draft.exclusions.isNotEmpty) {
        sb.writeln(
          '- **Explicitly Out of Scope (DO NOT BUILD IN $activeVer)**: ${draft.exclusions.join(' · ')}',
        );
      }
      if (draft.doneWhen.trim().isNotEmpty) {
        sb.writeln('- **Release Done When**: ${draft.doneWhen.trim()}');
      }
    }

    final beats = activeReleaseBeats;
    final allTuningRows = <({String feature, String variable, String value})>[];
    final allGuards = <({String feature, String guard})>[];

    sb.writeln('\n## 2. Active Release Hierarchy ($activeVer)');
    if (beats.isEmpty && _releaseBlueprint != null) {
      for (int bIdx = 0; bIdx < _releaseBlueprint!.beats.length; bIdx++) {
        final b = _releaseBlueprint!.beats[bIdx];
        final eNum = (bIdx + 1).toString().padLeft(2, '0');
        sb.writeln('- **E$eNum · ${b.title}**: ${b.goal}');
        for (final f in b.features.where((f) => f.included)) {
          sb.writeln('  - **${f.title}** (${f.estimatedHours}h): ${f.goal}');
        }
      }
    } else {
      for (int bIdx = 0; bIdx < beats.length; bIdx++) {
        final beat = beats[bIdx];
        final eNum = (bIdx + 1).toString().padLeft(2, '0');
        sb.writeln('- **E$eNum · ${beat.title}**');
        for (final feat in featuresForBeat(beat.id)) {
          final lc = (feat.sections['lifecycle'] ?? 'newFeature').toUpperCase();
          final p = getDocumentProgress(feat.id);
          sb.writeln(
            '  - **${feat.title}** [`$lc` · $p% verified · ${feat.estimatedDuration}]',
          );
          final states = FeatureStateNode.getStatesForDocument(feat);
          final activeStates =
              states.where((s) => s.releaseVersion == activeVer).toList();
          final effectiveStates =
              activeStates.isNotEmpty ? activeStates : states;
          for (final cp in effectiveStates) {
            for (final t in cp.tuningParams) {
              final parts = t.split(':');
              final k = parts.first.trim();
              final v = parts.length > 1
                  ? parts.sublist(1).join(':').trim()
                  : '1.0';
              if (k.isNotEmpty) {
                allTuningRows.add((
                  feature: feat.title,
                  variable: k,
                  value: v,
                ));
              }
            }
            for (final g in cp.edgeCases) {
              if (g.trim().isNotEmpty) {
                allGuards.add((feature: feat.title, guard: g.trim()));
              }
            }
          }
        }
      }
    }

    sb.writeln('\n## 3. Canonical Tuning Variables & Inspector Bindings');
    sb.writeln(
      'Always use these exact variable identifiers across scripts, Inspector/Details panels, and scenes:',
    );
    if (allTuningRows.isEmpty) {
      sb.writeln('- *(No numeric tuning variables registered yet)*');
    } else {
      sb.writeln('| Feature | Variable Identifier | Default / Target Value |');
      sb.writeln('| :--- | :--- | :--- |');
      for (final row in allTuningRows) {
        sb.writeln('| ${row.feature} | `${row.variable}` | `${row.value}` |');
      }
    }

    sb.writeln('\n## 4. Mandatory Playtest & Edge-Case Guards');
    sb.writeln(
      'Enforce every guard below with an explicit early-return or clamp in your runtime update/input logic:',
    );
    if (allGuards.isEmpty) {
      sb.writeln('- *(No edge-case guards registered yet)*');
    } else {
      for (final g in allGuards) {
        sb.writeln('- **${g.feature}**: `${g.guard}`');
      }
    }

    sb.writeln('\n## 5. 3-Area Engine Implementation Blueprint ($effectiveEngineTarget)');
    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final beat = beats[bIdx];
      final eNum = (bIdx + 1).toString().padLeft(2, '0');
      sb.writeln('\n### E$eNum · ${beat.title}');
      for (final feat in featuresForBeat(beat.id)) {
        final states = FeatureStateNode.getStatesForDocument(feat);
        final activeStates =
            states.where((s) => s.releaseVersion == activeVer).toList();
        final effectiveStates =
            activeStates.isNotEmpty ? activeStates : states;
        for (final cp in effectiveStates) {
          sb.writeln(
            '\n#### ${feat.title} — ${cp.cleanStageTitle} (${cp.releaseVersion})',
          );
          sb.writeln('- **Playtest Gate**: ${cp.playtestCondition}');
          for (int tIdx = 0; tIdx < cp.checklist.length; tIdx++) {
            final task = cp.checklist[tIdx];
            final bp = TaskHowToBlueprint.resolve(
              parentTask: task,
              taskIndex: tIdx,
              checkpointNode: cp,
              engineHint: engineHint,
              unrealCppMode: unrealCppMode,
            );
            final doneMark = task.completed ? 'x' : ' ';
            sb.writeln(
              '- [$doneMark] **Task ${bp.numLabel}: ${bp.cleanTitle}** (`${bp.whereLocation}`)',
            );
            for (final sub in bp.subSteps) {
              final sMark = sub.subtask.completed ? 'x' : ' ';
              sb.writeln(
                '  - [$sMark] **${sub.stepNumberLabel}** — ${sub.instruction}',
              );
              if (sub.area1Hierarchy != null &&
                  sub.area1Hierarchy!.trim().isNotEmpty) {
                sb.writeln(
                  '    - **Area 1 (Hierarchy)**: `${sub.area1Hierarchy!.replaceAll('\n', ' / ')}`',
                );
              }
              if (sub.area2Inspector != null &&
                  sub.area2Inspector!.trim().isNotEmpty) {
                sb.writeln(
                  '    - **Area 2 (Inspector)**: `${sub.area2Inspector!.replaceAll('\n', ' | ')}`',
                );
              }
              if (sub.codeFormula.trim().isNotEmpty) {
                sb.writeln('    ```');
                for (final line in sub.codeFormula.trim().split('\n')) {
                  sb.writeln('    $line');
                }
                sb.writeln('    ```');
              }
              if (sub.verifyResult.trim().isNotEmpty) {
                sb.writeln('    - *Verify*: ${sub.verifyResult.trim()}');
              }
            }
          }
        }
      }
    }

    return sb.toString();
  }

  /// Generates a focused, single-feature AI Coding Agent prompt (for Cursor, Claude Code, or Antigravity)
  /// containing only the selected Feature's 3-Area blueprint, exact tuning variable names, sibling variable
  /// references, mandatory `[GUARD]` rules, and Playtest Gate condition.
  String buildActiveFeatureCodingAgentPrompt(
    String featureId, {
    bool unrealCppMode = false,
  }) {
    final feat = documents[featureId];
    if (feat == null) return '';
    final draft = _conceptDraft;
    final proj = activeProject;
    final activeVer = activeReleaseVersionTag;
    final engineHint = _activeEngineHint;
    final engineLabel = _activeEngineLabel;
    final effectiveEngineTarget = engineLabel == 'UNREAL 5'
        ? (unrealCppMode ? 'UNREAL 5 C++ (.h / .cpp)' : 'UNREAL 5 BLUEPRINTS')
        : (engineLabel == 'UNITY C#'
            ? 'UNITY C# (MonoBehaviour)'
            : 'GODOT 4 (GDScript 2.0)');
    final projectTitle = (draft != null && draft.title.trim().isNotEmpty)
        ? draft.title.trim()
        : (proj != null && proj.title.trim().isNotEmpty
            ? proj.title.trim()
            : 'LAYERS-Agentic Game Project');

    final parentBeat =
        feat.parentId != null ? documents[feat.parentId!] : null;
    final beats = activeReleaseBeats;
    final beatIdx =
        parentBeat != null ? beats.indexWhere((b) => b.id == parentBeat.id) : 0;
    final eNum = ((beatIdx >= 0 ? beatIdx : 0) + 1).toString().padLeft(2, '0');
    final epicLabel = parentBeat != null
        ? 'E$eNum · ${parentBeat.title}'
        : 'E01 · Core Loop Epic';

    final states = FeatureStateNode.getStatesForDocument(feat);
    final activeStates =
        states.where((s) => s.releaseVersion == activeVer).toList();
    final cpNode = activeStates.isNotEmpty
        ? activeStates.last
        : (states.isNotEmpty ? states.last : null);

    final sb = StringBuffer();
    sb.writeln(
      '# AI CODING AGENT TASK PROMPT — ${feat.title} ($activeVer · $effectiveEngineTarget)',
    );
    sb.writeln(
      '> Implement this single feature in **$effectiveEngineTarget** using the exact variable names, scene hierarchy, and playtest guards below.',
    );

    sb.writeln('\n## 1. Feature Scope & Context');
    sb.writeln('- **Project**: $projectTitle (`$activeVer`)');
    sb.writeln('- **Target Engine**: $effectiveEngineTarget');
    sb.writeln('- **Epic**: $epicLabel');
    sb.writeln('- **Feature**: ${feat.title}');
    final rawGoal = (feat.sections['scope'] ?? feat.sections['goal'] ?? '').trim();
    if (rawGoal.isNotEmpty) {
      sb.writeln('- **Goal**: ${rawGoal.split('\n').first.replaceFirst(RegExp(r'^Goal:\s*', caseSensitive: false), '').trim()}');
    }
    if (cpNode != null && cpNode.playtestCondition.trim().isNotEmpty) {
      sb.writeln('- **Playtest Gate (Done When)**: ${cpNode.playtestCondition.trim()}');
    }

    sb.writeln('\n## 2. Canonical Tuning Variables & Sibling Context');
    if (cpNode == null || cpNode.tuningParams.isEmpty) {
      sb.writeln('- *(No numeric tuning variables registered)*');
    } else {
      sb.writeln('### Active Feature Variables (`${feat.title}`)');
      for (final param in cpNode.tuningParams) {
        sb.writeln('- `$param`');
      }
    }
    if (parentBeat != null) {
      final siblingLines = <String>[];
      for (final sib in featuresForBeat(parentBeat.id)) {
        if (sib.id == feat.id) continue;
        final sibStates = FeatureStateNode.getStatesForDocument(sib);
        if (sibStates.isNotEmpty && sibStates.last.tuningParams.isNotEmpty) {
          siblingLines.add(
            '- **${sib.title}**: `${sibStates.last.tuningParams.join('`, `')}`',
          );
        }
      }
      if (siblingLines.isNotEmpty) {
        sb.writeln('\n### Sibling Feature Variables in $epicLabel (Reuse Exact Identifiers)');
        for (final line in siblingLines) {
          sb.writeln(line);
        }
      }
    }

    sb.writeln('\n## 3. Mandatory Edge-Case & Playtest Guards');
    if (cpNode == null || cpNode.edgeCases.isEmpty) {
      sb.writeln('- *(No edge-case guards registered)*');
    } else {
      for (final g in cpNode.edgeCases) {
        sb.writeln('- `${g.trim()}`');
      }
    }

    if (cpNode != null) {
      sb.writeln('\n## 4. 3-Area Implementation Steps ($effectiveEngineTarget)');
      for (int tIdx = 0; tIdx < cpNode.checklist.length; tIdx++) {
        final task = cpNode.checklist[tIdx];
        final bp = TaskHowToBlueprint.resolve(
          parentTask: task,
          taskIndex: tIdx,
          checkpointNode: cpNode,
          engineHint: engineHint,
          unrealCppMode: unrealCppMode,
        );
        final doneMark = task.completed ? 'x' : ' ';
        sb.writeln(
          '- [$doneMark] **Task ${bp.numLabel}: ${bp.cleanTitle}** (`${bp.whereLocation}`)',
        );
        for (final sub in bp.subSteps) {
          final sMark = sub.subtask.completed ? 'x' : ' ';
          sb.writeln(
            '  - [$sMark] **${sub.stepNumberLabel}** — ${sub.instruction}',
          );
          if (sub.area1Hierarchy != null &&
              sub.area1Hierarchy!.trim().isNotEmpty) {
            sb.writeln(
              '    - **Area 1 (Hierarchy)**: `${sub.area1Hierarchy!.replaceAll('\n', ' / ')}`',
            );
          }
          if (sub.area2Inspector != null &&
              sub.area2Inspector!.trim().isNotEmpty) {
            sb.writeln(
              '    - **Area 2 (Inspector)**: `${sub.area2Inspector!.replaceAll('\n', ' | ')}`',
            );
          }
          if (sub.codeFormula.trim().isNotEmpty) {
            sb.writeln('    ```');
            for (final line in sub.codeFormula.trim().split('\n')) {
              sb.writeln('    $line');
            }
            sb.writeln('    ```');
          }
          if (sub.verifyResult.trim().isNotEmpty) {
            sb.writeln('    - *Verify*: ${sub.verifyResult.trim()}');
          }
        }
      }
    }

    return sb.toString();
  }

  /// Two-Way Engine Sync: Parses a developer's pasted GDScript, C#, or Unreal C++ script
  /// (using `gemini-flash-latest` when online + a deterministic multi-line regex parser fallback)
  /// to update changed numeric tuning variable values and append newly added `[GUARD]` checks
  /// directly onto the Feature's active checkpoint.
  Future<({int updatedVars, int addedGuards})>
      syncFeatureTuningAndGuardsFromCode(
    String featureId,
    String pastedCode,
  ) async {
    final feat = documents[featureId];
    final trimmedCode = pastedCode.trim();
    if (feat == null || trimmedCode.isEmpty) {
      return (updatedVars: 0, addedGuards: 0);
    }

    final states = FeatureStateNode.getStatesForDocument(feat);
    if (states.isEmpty) return (updatedVars: 0, addedGuards: 0);
    final activeVer = activeReleaseVersionTag;
    int cpIdx = states.lastIndexWhere((s) => s.releaseVersion == activeVer);
    if (cpIdx < 0) cpIdx = states.length - 1;
    final cpNode = states[cpIdx];

    final extractedTuning = <String, String>{};
    final extractedGuards = <String>[];

    // 1. Fast AI extraction pass via gemini-flash-latest when key is available
    if (GeminiAgentClient.hasKey(_apiKey)) {
      final prompt = '''
You are a Game Engine Code-to-Spec Synchronizer.
Compare the developer's pasted engine script against the Feature's current Tuning Parameters and Guards.
Feature: "${feat.title}"
Current Tuning Parameters: ${cpNode.tuningParams.join(', ')}
Current Guards: ${cpNode.edgeCases.join(' | ')}

Pasted Engine Script:
```
$trimmedCode
```

Extract:
1. "tuningUpdates": Any updated or newly exported numeric/boolean/string tuning variables from the script formatted as "variableName: value". Preserve existing variable names when they match.
2. "newGuards": Any new safety/null/cooldown/bounds guard checks in the script formatted as "[GUARD] condition — safe fallback".

Return ONLY valid JSON:
{
  "tuningUpdates": ["moveSpeed: 650.0"],
  "newGuards": ["[GUARD] Prevent dash while stunned — early-return when isStunned is true"]
}''';
      final json = await GeminiAgentClient.generateJson(
        prompt: prompt,
        apiKey: _apiKey,
        preferredModel: _conversationModel,
        thinkingLevel: 'LOW',
        temperature: 0.1,
      );
      final rawTuning = json?['tuningUpdates'];
      if (rawTuning is List) {
        for (final item in rawTuning) {
          final text = item?.toString().trim() ?? '';
          final colonIdx = text.indexOf(':');
          if (colonIdx > 0) {
            final k = text.substring(0, colonIdx).trim();
            final v = text.substring(colonIdx + 1).trim();
            if (k.isNotEmpty && v.isNotEmpty) {
              extractedTuning[k] = v;
            }
          }
        }
      }
      final rawGuards = json?['newGuards'];
      if (rawGuards is List) {
        for (final item in rawGuards) {
          final text = item?.toString().trim() ?? '';
          if (text.isNotEmpty) {
            extractedGuards.add(
              text.startsWith('[') ? text : '[GUARD] $text',
            );
          }
        }
      }
    }

    // 2. Deterministic multi-line regex extraction (handles Godot 4 @export, Unity [SerializeField], Unreal UPROPERTY across line breaks)
    String cleanNumericValue(String raw) {
      var val = raw
          .split('//')
          .first
          .split('#')
          .first
          .trim()
          .replaceAll(RegExp(r';$'), '')
          .trim();
      // Strip trailing C#/C++ float 'f' suffix on numeric literals (e.g. 600.0f -> 600.0, 6f -> 6.0)
      final floatMatch = RegExp(r'^(-?\d+(?:\.\d+)?)[fF]$').firstMatch(val);
      if (floatMatch != null) {
        final numPart = floatMatch.group(1)!;
        val = numPart.contains('.') ? numPart : '$numPart.0';
      }
      return val;
    }

    // 2a. Multi-line Unity [SerializeField] / Unreal UPROPERTY(...) attribute on same or preceding line
    final attrFieldRegex = RegExp(
      r'(?:\[SerializeField[^\]]*\]|UPROPERTY\([^)]*\))\s*(?:(?:private|public|protected|internal|mutable|const)\s+)?[\w<>:*&]+\s+(\w+)\s*=\s*([^;\n]+);',
      multiLine: true,
    );
    for (final m in attrFieldRegex.allMatches(trimmedCode)) {
      final k = m.group(1)?.trim() ?? '';
      final v = cleanNumericValue(m.group(2) ?? '');
      if (k.isNotEmpty && v.isNotEmpty) {
        extractedTuning.putIfAbsent(k, () => v);
      }
    }

    // 2b. Godot 4 @export var / typed var declarations
    final gdVarRegex = RegExp(
      r'@export(?:_[a-z_]+)?(?:\([^)]*\))?\s+var\s+(\w+)(?:\s*:\s*[\w.]+)?\s*=\s*([^\n#;]+)',
      multiLine: true,
    );
    for (final m in gdVarRegex.allMatches(trimmedCode)) {
      final k = m.group(1)?.trim() ?? '';
      final v = cleanNumericValue(m.group(2) ?? '');
      if (k.isNotEmpty && v.isNotEmpty) {
        extractedTuning.putIfAbsent(k, () => v);
      }
    }

    // 2c. Direct assignment match for any existing tuningParams keys
    for (final existing in cpNode.tuningParams) {
      final existingKey = existing.split(':').first.trim();
      if (existingKey.isEmpty) continue;
      final keyRegex = RegExp(
        r'\b' +
            RegExp.escape(existingKey) +
            r'\b(?:\s*:\s*[\w.]+)?\s*=\s*([^\n;#/]+)',
        multiLine: true,
        caseSensitive: false,
      );
      final match = keyRegex.firstMatch(trimmedCode);
      if (match != null) {
        final v = cleanNumericValue(match.group(1) ?? '');
        if (v.isNotEmpty) {
          extractedTuning[existingKey] = v;
        }
      }
    }

    // 2d. Guard comment extraction (// [GUARD] ..., # [GUARD] ..., // GUARD: ...)
    final guardCommentRegex = RegExp(
      r'(?://|#)\s*\[?(?:PLAYTEST\s+)?GUARD\]?\s*:?\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    );
    for (final m in guardCommentRegex.allMatches(trimmedCode)) {
      final gText = m.group(1)?.trim() ?? '';
      if (gText.isNotEmpty) {
        final formatted = gText.startsWith('[') ? gText : '[GUARD] $gText';
        if (!extractedGuards.contains(formatted)) {
          extractedGuards.add(formatted);
        }
      }
    }

    // 3. Apply extracted tuning updates and new guards to cpNode in-place
    int updatedVars = 0;
    int addedGuards = 0;

    final updatedTuningList = List<String>.from(cpNode.tuningParams);
    String normalizeVarKey(String k) =>
        k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    for (final entry in extractedTuning.entries) {
      final normTarget = normalizeVarKey(entry.key);
      if (normTarget.isEmpty) continue;
      final existingIdx = updatedTuningList.indexWhere(
        (item) => normalizeVarKey(item.split(':').first) == normTarget,
      );
      if (existingIdx >= 0) {
        final canonicalKey =
            updatedTuningList[existingIdx].split(':').first.trim();
        final newEntry = '$canonicalKey: ${entry.value}';
        if (updatedTuningList[existingIdx] != newEntry) {
          updatedTuningList[existingIdx] = newEntry;
          updatedVars++;
        }
      } else {
        updatedTuningList.add('${entry.key}: ${entry.value}');
        updatedVars++;
      }
    }

    final updatedGuardsList = List<String>.from(cpNode.edgeCases);
    for (final g in extractedGuards) {
      final normG = g.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      final alreadyExists = updatedGuardsList.any(
        (existing) =>
            existing.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim() ==
            normG,
      );
      if (!alreadyExists) {
        updatedGuardsList.add(g);
        addedGuards++;
      }
    }

    if (updatedVars > 0 || addedGuards > 0) {
      cpNode.tuningParams = updatedTuningList;
      cpNode.edgeCases = updatedGuardsList;
      TaskHowToBlueprint.clearCache();
      updateFeatureStates(featureId, states);
    }

    return (updatedVars: updatedVars, addedGuards: addedGuards);
  }

  void selectFeature(String featureId) {
    final feat = documents[featureId];
    if (feat == null) return;
    _selectedFeatureId = featureId;
    if (feat.parentId != null) {
      _selectedBeatId = feat.parentId;
    }
    final proj = activeProject;
    if (proj != null) {
      proj.sections['selected_feature_id'] = featureId;
      if (_selectedBeatId != null) {
        proj.sections['selected_beat_id'] = _selectedBeatId!;
      }
      _persistDocument(proj, debounce: true);
    }
    notifyListeners();
    if (GeminiAgentClient.hasKey(_apiKey)) {
      final states = FeatureStateNode.getStatesForDocument(feat);
      final activeVer = activeReleaseVersionTag;
      final activeCp = states.isNotEmpty
          ? (states.where((s) => s.releaseVersion == activeVer).lastOrNull ??
              states.last)
          : null;
      final alreadySynthesized = activeCp != null &&
          activeCp.checklist.isNotEmpty &&
          activeCp.checklist.every(
            (t) =>
                t.children.isNotEmpty &&
                t.children.every((c) => c.codeTargetFile == 'custom_snippet'),
          );
      if (!alreadySynthesized) {
        synthesizeFeatureHowToStepsWithAi(featureId);
      }
    }
  }

  void updateFeatureStates(String featureId, List<FeatureStateNode> states) {
    final feat = documents[featureId];
    if (feat == null) return;
    FeatureStateNode.saveStatesToDocument(feat, states);
    if (states.isNotEmpty) {
      final activeVer = activeReleaseVersionTag;
      final activeCp = states.firstWhere(
        (s) => s.releaseVersion == activeVer && !s.isCompleted,
        orElse: () => states.lastWhere(
          (s) => s.releaseVersion == activeVer,
          orElse: () => states.firstWhere(
            (s) => !s.isCompleted,
            orElse: () => states.last,
          ),
        ),
      );
      if (activeCp.tuningParams.isNotEmpty) {
        final formattedTuning =
            activeCp.tuningParams.map((p) => '• $p').join('\n');
        feat.sections['tuning'] = formattedTuning;
        feat.sections['variables'] = formattedTuning;
      }
      if (activeCp.edgeCases.isNotEmpty) {
        feat.sections['edge_cases'] =
            activeCp.edgeCases.map((e) => '• $e').join('\n');
      }
    }
    TaskHowToBlueprint.clearCache();
    _persistDocument(feat, debounce: true);
    notifyListeners();
  }

  /// Propagates a variable identifier rename (`oldIdentifier` -> `newIdentifier`)
  /// across all Features, Checkpoints, Tuning Lists, Playtest Guards, and 3-Area
  /// Steps (`sub.text`, `sub.specNotes`, `sub.codeSnippet`, `sub.verification`)
  /// in the active project using exact word-boundary matching.
  /// Returns the number of Feature documents updated.
  int propagateVariableRenameAcrossProject(
    String oldIdentifier,
    String newIdentifier,
  ) {
    final oldId = oldIdentifier.trim();
    final newId = newIdentifier.trim();
    if (oldId.isEmpty || newId.isEmpty || oldId == newId) return 0;

    final idRegex = RegExp(r'\b' + RegExp.escape(oldId) + r'\b');
    int updatedFeatureCount = 0;

    bool replaceSubtaskTree(Subtask node) {
      var changed = false;
      if (idRegex.hasMatch(node.text)) {
        node.text = node.text.replaceAll(idRegex, newId);
        changed = true;
      }
      if (node.specNotes != null && idRegex.hasMatch(node.specNotes!)) {
        node.specNotes = node.specNotes!.replaceAll(idRegex, newId);
        changed = true;
      }
      if (node.codeSnippet != null && idRegex.hasMatch(node.codeSnippet!)) {
        node.codeSnippet = node.codeSnippet!.replaceAll(idRegex, newId);
        changed = true;
      }
      if (node.verification != null && idRegex.hasMatch(node.verification!)) {
        node.verification = node.verification!.replaceAll(idRegex, newId);
        changed = true;
      }
      for (final child in node.children) {
        if (replaceSubtaskTree(child)) {
          changed = true;
        }
      }
      return changed;
    }

    // Collect all feature documents in the active project
    final projectFeatureIds = <String>{};
    for (final rel in projectReleases) {
      for (final bId in rel.childrenIds) {
        final beat = documents[bId];
        if (beat == null) continue;
        for (final fId in beat.childrenIds) {
          if (documents[fId]?.tier == TierType.feature) {
            projectFeatureIds.add(fId);
          }
        }
      }
    }

    for (final fId in projectFeatureIds) {
      final feat = documents[fId];
      if (feat == null) continue;
      var featChanged = false;

      final states = FeatureStateNode.getStatesForDocument(feat);
      for (final cp in states) {
        for (int i = 0; i < cp.tuningParams.length; i++) {
          if (idRegex.hasMatch(cp.tuningParams[i])) {
            cp.tuningParams[i] = cp.tuningParams[i].replaceAll(idRegex, newId);
            featChanged = true;
          }
        }
        for (int i = 0; i < cp.edgeCases.length; i++) {
          if (idRegex.hasMatch(cp.edgeCases[i])) {
            cp.edgeCases[i] = cp.edgeCases[i].replaceAll(idRegex, newId);
            featChanged = true;
          }
        }
        if (idRegex.hasMatch(cp.trigger)) {
          cp.trigger = cp.trigger.replaceAll(idRegex, newId);
          featChanged = true;
        }
        for (final task in cp.checklist) {
          if (replaceSubtaskTree(task)) {
            featChanged = true;
          }
        }
      }

      for (final key in feat.sections.keys.toList()) {
        if (key == 'feature_states_json') continue;
        final val = feat.sections[key];
        if (val != null && idRegex.hasMatch(val)) {
          feat.sections[key] = val.replaceAll(idRegex, newId);
          featChanged = true;
        }
      }

      if (featChanged) {
        FeatureStateNode.saveStatesToDocument(feat, states);
        _persistDocument(feat, debounce: true);
        updatedFeatureCount++;
      }
    }

    if (_releaseBlueprint != null) {
      var bpChanged = false;
      for (final b in _releaseBlueprint!.beats) {
        for (final f in b.features) {
          for (int i = 0; i < f.tuningParams.length; i++) {
            if (idRegex.hasMatch(f.tuningParams[i])) {
              f.tuningParams[i] = f.tuningParams[i].replaceAll(idRegex, newId);
              bpChanged = true;
            }
          }
          for (int i = 0; i < f.edgeCases.length; i++) {
            if (idRegex.hasMatch(f.edgeCases[i])) {
              f.edgeCases[i] = f.edgeCases[i].replaceAll(idRegex, newId);
              bpChanged = true;
            }
          }
        }
      }
      if (bpChanged) {
        _syncActiveProjectMetadata();
      }
    }

    TaskHowToBlueprint.clearCache();
    if (updatedFeatureCount > 0) {
      notifyListeners();
    }
    return updatedFeatureCount;
  }

  /// Advances to the next queued Release in the current Production Phase, or unlocks the
  /// next Production Phase once the current phase's releases are completed:
  /// - Phase 1 (Prototype) complete -> Phase 2 (MVP Track: 1 MVP Release per Core Loop Beat)
  /// - Phase 2 (MVP Track) complete -> Phase 3 (Vertical Slice: 1 Polished Gold Standard Level)
  /// - Phase 3 (Vertical Slice) complete -> Phase 4 (Full Production: World & Content Expansion)
  Future<void> advanceToNextRelease({
    bool transitionToGateStage = true,
    bool agentReasonedProgressive = false,
  }) async {
    final proj = activeProject;
    if (proj == null) return;
    repackProjectReleasesSequentially(proj, pruneAllUnbuilt: true);
    final releases = projectReleases;
    if (releases.isEmpty) return;

    _lastReleaseRetrospective = buildActiveReleaseRetrospective();

    Future<void> openGateAndRecordRetro(String targetRelId) async {
      await openReleasePlanGate(
        releaseId: targetRelId,
        transitionToGateStage: transitionToGateStage,
      );
      if (_releaseBlueprint != null) {
        notifyListeners();
      }
    }

    final currentIdx = releases.indexWhere((r) => r.id == _activeReleaseId);
    final nextIdx = currentIdx + 1;
    if (currentIdx >= 0 && nextIdx < releases.length) {
      final nextRel = releases[nextIdx];
      // When planning a progressive release from the Co-Pilot, only reuse a queued release if it is still unbuilt.
      if (!agentReasonedProgressive || nextRel.childrenIds.isEmpty) {
        final phaseStr = nextRel.sections['phase'];
        if (phaseStr != null && phaseStr.isNotEmpty) {
          for (final p in ProductionPhase.values) {
            if (p.name == phaseStr) {
              _currentPhase = p;
              break;
            }
          }
        }
        await openGateAndRecordRetro(nextRel.id);
        return;
      }
    }

    // Current Phase has no more queued releases — create ONLY 1 single next Release on demand!
    final currentRel = activeRelease ?? releases.last;
    final allocated = _allocateNextReleaseIdAndIndex(proj);
    final newIndex = allocated.index;
    final newRelId = allocated.id;

    if (_currentPhase == ProductionPhase.prototype &&
        currentRel.sections['prototypePart'] == '1') {
      final part2Title = currentRel.sections['splitPrototypePart2Title'] ??
          'v0.$newIndex: Prototype — Part 2: Progression & Loop Reset';
      final newRelDoc = TierDocument(
        id: newRelId,
        title: part2Title,
        tier: TierType.release,
        parentId: proj.id,
        sections: {
          'versionTag': 'v0.$newIndex',
          'releaseScope': ReleaseScope.prototype.name,
          'phase': ProductionPhase.prototype.name,
          'prototypePart': '2',
          'scope':
              'Goal: Complete the remaining Core Loop Epics for the ${proj.title} prototype.\n\nIn Scope:\n• Remaining Core Loop Epics from ${proj.title}\n\nDone When: Full prototype core loop connects end-to-end.',
        },
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      proj.childrenIds.add(newRelId);
      _syncActiveProjectMetadata();
      await openGateAndRecordRetro(newRelId);
      return;
    }

    if (agentReasonedProgressive) {
      final nextPhase = inferNextProgressivePhase();
      _currentPhase = nextPhase;
      final nextScope = _releaseScopeForPhase(nextPhase);
      final existingFullProdCount = releases
          .where((r) => releasePhaseFor(r) == ProductionPhase.fullProduction)
          .length;
      final fullProdPass = existingFullProdCount + 1;
      final effectiveVer = nextPhase == ProductionPhase.fullProduction
          ? 'v1.${fullProdPass - 1}'
          : 'v0.$newIndex';
      final defaultTitle = nextPhase == ProductionPhase.verticalSlice
          ? '$effectiveVer: Gold Standard Polish Pass - Vertical Slice'
          : (nextPhase == ProductionPhase.fullProduction
              ? '$effectiveVer: Content & World Expansion - Full Production'
              : '$effectiveVer: Progressive Release');
      final newRelDoc = TierDocument(
        id: newRelId,
        title: defaultTitle,
        tier: TierType.release,
        parentId: proj.id,
        sections: {
          'versionTag': effectiveVer,
          'releaseScope': nextScope.name,
          'phase': nextPhase.name,
          'agentReasoned': 'true',
          if (nextPhase == ProductionPhase.fullProduction)
            'fullProductionPass': '$fullProdPass',
          'scope':
              'Goal: Synthesize the highest-impact $effectiveVer features and upgrades for ${proj.title}.\n\nIn Scope:\n• Agent-recommended $effectiveVer features and upgrades\n\nDone When: All $effectiveVer features pass playtest verification.',
        },
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      proj.childrenIds.add(newRelId);
      _syncActiveProjectMetadata();
      await openGateAndRecordRetro(newRelId);
      return;
    }

    final beatNames = <String>[];
    final existingBeats = activeReleaseBeats;
    if (existingBeats.isNotEmpty) {
      for (final b in existingBeats) {
        beatNames.add(b.title);
      }
    } else if (_conceptDraft != null &&
        _conceptDraft!.coreLoopBeats.isNotEmpty) {
      for (final raw in _conceptDraft!.coreLoopBeats) {
        final cleanTitle = raw.split(':').first.split('—').first.trim();
        beatNames.add(cleanTitle.isNotEmpty ? cleanTitle : raw);
      }
    }
    if (beatNames.isEmpty) {
      beatNames.add('Core Gameplay Systems');
    }

    final existingMvpCount = releases
        .where((r) => r.sections['phase'] == ProductionPhase.mvp.name)
        .length;

    if (_currentPhase == ProductionPhase.prototype ||
        (_currentPhase == ProductionPhase.mvp &&
            existingMvpCount < beatNames.length)) {
      _currentPhase = ProductionPhase.mvp;
      final i = existingMvpCount;
      final beatLabel = beatNames[i];
      final newRelDoc = TierDocument(
        id: newRelId,
        title: 'v0.$newIndex: MVP Epic ${i + 1} ($beatLabel) - MVP',
        tier: TierType.release,
        parentId: proj.id,
        sections: {
          'versionTag': 'v0.$newIndex',
          'releaseScope': ReleaseScope.mvp.name,
          'phase': ProductionPhase.mvp.name,
          'targetEpicIndex': '$i',
          'mvpEpicTotal': '${beatNames.length}',
          'scope':
              'Goal: Build and connect MVP systems for Epic ${i + 1} ($beatLabel).\n\nIn Scope:\n• $beatLabel\n\nDone When: Epic ${i + 1} is playable end-to-end inside the rough representative level.',
        },
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      proj.childrenIds.add(newRelId);
      _syncActiveProjectMetadata();
      await openGateAndRecordRetro(newRelId);
      return;
    } else if (_currentPhase == ProductionPhase.mvp) {
      _currentPhase = ProductionPhase.verticalSlice;
      final newRelDoc = TierDocument(
        id: newRelId,
        title:
            'v0.$newIndex: Gold Standard Level (Combined MVPs) - Vertical Slice',
        tier: TierType.release,
        parentId: proj.id,
        sections: {
          'versionTag': 'v0.$newIndex',
          'releaseScope': ReleaseScope.verticalSlice.name,
          'phase': ProductionPhase.verticalSlice.name,
          'scope':
              'Goal: Combine all completed MVP Epics into 1 fully polished Gold Standard level.\n\nIn Scope:\n• Final art, audio, UI, and game-feel pass on the representative level\n\nDone When: Playtester completes the polished Vertical Slice level at shippable quality.',
        },
      );
      documents[newRelId] = newRelDoc;
      _persistDocument(newRelDoc);
      proj.childrenIds.add(newRelId);
      _syncActiveProjectMetadata();
      await openGateAndRecordRetro(newRelId);
      return;
    }

    // Phase 4: Full Production content drops (reusing the Rough -> Polish pattern)
    _currentPhase = ProductionPhase.fullProduction;
    final existingFullProdCount = releases
        .where((r) => r.sections['phase'] == ProductionPhase.fullProduction.name)
        .length;
    final fullProdPass = existingFullProdCount + 1;
    final fullProdVersion = 'v1.${fullProdPass - 1}';
    final fullProdTitle = fullProdPass == 1
        ? '$fullProdVersion: Full Production — Content, Levels & Deferred Systems - Full Production'
        : '$fullProdVersion: Full Production — World & Balance Expansion (Pass $fullProdPass) - Full Production';
    final newRelDoc = TierDocument(
      id: newRelId,
      title: fullProdTitle,
      tier: TierType.release,
      parentId: proj.id,
      sections: {
        'versionTag': fullProdVersion,
        'releaseScope': ReleaseScope.fullProduction.name,
        'phase': ProductionPhase.fullProduction.name,
        'fullProductionPass': '$fullProdPass',
        'scope':
            'Goal: Expand the verified Vertical Slice template across new levels, content waves, and previously deferred systems.\n\nIn Scope:\n• Content & level roster expansion\n• Promote deferred Out-of-Scope systems up to the Vertical Slice bar\n\nDone When: All new content and promoted systems pass playtest verification at Vertical Slice quality.',
      },
    );
    documents[newRelId] = newRelDoc;
    _persistDocument(newRelDoc);
    proj.childrenIds.add(newRelId);
    _syncActiveProjectMetadata();
    await openGateAndRecordRetro(newRelId);
  }
}
