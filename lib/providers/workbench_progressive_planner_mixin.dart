part of 'workbench_provider.dart';

extension WorkbenchProgressivePlannerMixin on WorkbenchProvider {
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
  /// An Epic only counts as complete (`coveredBeats++`) once ALL of its non-superseded
  /// `v0.1` features have been upgraded beyond `v0.1`.
  ({
    int coveredBeats,
    int totalBeats,
    int upgradedProtoFeatures,
    int totalProtoFeatures,
    List<String> uncoveredBeatTitles,
    List<String> unupgradedProtoFeatureTitles,
    List<String> completedBeatCodes,
    List<String> incompleteBeatCodes,
    bool isComplete,
  }) mvpBeatCoverage() {
    final builtReleases =
        projectReleases.where((r) => r.childrenIds.isNotEmpty).toList();
    final protoVerTags = <String>{
      'v0.1',
      for (final r in builtReleases)
        if (releasePhaseFor(r) == ProductionPhase.prototype)
          releaseVersionTagFor(r).toLowerCase(),
    };
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
    final completedBeatCodes = <String>[];
    final incompleteBeatCodes = <String>[];

    bool featureHasMvpPass(TierDocument f) {
      final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
      final states = FeatureStateNode.getStatesForDocument(f);
      final hasMvpCheckpoint = mvpVerTags.contains(originVer) ||
          states.any(
            (s) => mvpVerTags.contains(s.releaseVersion.toLowerCase()),
          );
      final upgradedPostProto = !protoVerTags.contains(originVer) ||
          states.any(
            (s) => !protoVerTags.contains(s.releaseVersion.toLowerCase()),
          );
      return (upgradedPostProto || hasMvpCheckpoint) && states.isNotEmpty;
    }

    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final b = beats[bIdx];
      if (b.isFullProductionEpic) continue;
      final eTag = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      final feats = featuresForBeat(b.id)
          .where(
            (f) =>
                f.sections['lifecycle'] !=
                FeatureLifecycleStatus.superseded.name,
          )
          .toList();
      final beatHasAnyMvpPass = feats.any(featureHasMvpPass);
      bool allFeaturesInBeatCovered = feats.isNotEmpty && beatHasAnyMvpPass;
      for (final f in feats) {
        totalProtoFeatures++;
        final hasMvpPass = featureHasMvpPass(f);
        final isStableCompletedInCoveredBeat =
            beatHasAnyMvpPass && getDocumentProgress(f.id) >= 100;
        if (hasMvpPass || isStableCompletedInCoveredBeat) {
          upgradedProtoFeatures++;
        } else {
          allFeaturesInBeatCovered = false;
          unupgradedProtoFeatureTitles.add('$eTag · ${f.title}');
        }
      }
      if (allFeaturesInBeatCovered) {
        coveredBeats++;
        completedBeatCodes.add(eTag);
      } else {
        uncoveredBeatTitles.add('$eTag · ${b.title}');
        incompleteBeatCodes.add(eTag);
      }
    }

    final totalBeats = beats.where((b) => !b.isFullProductionEpic).length;
    final isComplete = totalBeats > 0 && coveredBeats >= totalBeats;

    return (
      coveredBeats: coveredBeats,
      totalBeats: totalBeats,
      upgradedProtoFeatures: upgradedProtoFeatures,
      totalProtoFeatures: totalProtoFeatures,
      uncoveredBeatTitles: uncoveredBeatTitles,
      unupgradedProtoFeatureTitles: unupgradedProtoFeatureTitles,
      completedBeatCodes: completedBeatCodes,
      incompleteBeatCodes: incompleteBeatCodes,
      isComplete: isComplete,
    );
  }

  /// Evaluates how many Core Loop Epics (`activeReleaseBeats`) and live Features have received
  /// `Vertical Slice` polish coverage across built `ProductionPhase.verticalSlice` releases.
  /// An Epic counts as complete (`polishedBeats++`) once it has received a Vertical Slice polish
  /// checkpoint and all of its non-superseded features are either Vertical-Slice polished or
  /// `100%` complete `STABLE ✓` features.
  ({
    int polishedBeats,
    int totalBeats,
    int polishedFeatures,
    int totalFeatures,
    List<String> unpolishedBeatTitles,
    List<String> unpolishedFeatureTitles,
    List<String> completedBeatCodes,
    List<String> incompleteBeatCodes,
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
    final completedBeatCodes = <String>[];
    final incompleteBeatCodes = <String>[];

    bool featureHasVsPass(TierDocument f) {
      final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
      final states = FeatureStateNode.getStatesForDocument(f);
      return vsVerTags.contains(originVer) ||
          states.any(
            (s) => vsVerTags.contains(s.releaseVersion.toLowerCase()),
          );
    }

    for (int bIdx = 0; bIdx < beats.length; bIdx++) {
      final b = beats[bIdx];
      if (b.isFullProductionEpic) continue;
      final eTag = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      final feats = featuresForBeat(b.id)
          .where(
            (f) =>
                f.sections['lifecycle'] !=
                FeatureLifecycleStatus.superseded.name,
          )
          .toList();
      final beatHasAnyVsPass = feats.any(featureHasVsPass);
      bool allFeaturesInBeatPolished = feats.isNotEmpty && beatHasAnyVsPass;
      for (final f in feats) {
        totalFeatures++;
        final hasVsCheckpoint = featureHasVsPass(f);
        final isStableCompletedInPolishedBeat =
            beatHasAnyVsPass && getDocumentProgress(f.id) >= 100;
        if (hasVsCheckpoint || isStableCompletedInPolishedBeat) {
          polishedFeatures++;
        } else {
          allFeaturesInBeatPolished = false;
          unpolishedFeatureTitles.add('$eTag · ${f.title}');
        }
      }
      if (allFeaturesInBeatPolished) {
        polishedBeats++;
        completedBeatCodes.add(eTag);
      } else {
        unpolishedBeatTitles.add('$eTag · ${b.title}');
        incompleteBeatCodes.add(eTag);
      }
    }

    final totalBeats = beats.where((b) => !b.isFullProductionEpic).length;
    final isComplete = totalBeats > 0 && polishedBeats >= totalBeats;

    return (
      polishedBeats: polishedBeats,
      totalBeats: totalBeats,
      polishedFeatures: polishedFeatures,
      totalFeatures: totalFeatures,
      unpolishedBeatTitles: unpolishedBeatTitles,
      unpolishedFeatureTitles: unpolishedFeatureTitles,
      completedBeatCodes: completedBeatCodes,
      incompleteBeatCodes: incompleteBeatCodes,
      isComplete: isComplete,
    );
  }

  /// Version tag of the Act 2 Full-Game Skeleton release (`fpSkeleton: 'true'`), or `null` before it is built.
  String? get fullProductionSkeletonVersionTag {
    for (final r in projectReleases) {
      if (r.childrenIds.isNotEmpty && r.sections['fpSkeleton'] == 'true') {
        return releaseVersionTagFor(r).toLowerCase();
      }
    }
    return null;
  }

  /// Evaluates `04 · Full Production` progress.
  /// - Act 2 (Full Production Blueprint): counts only Full Production Epics (`act: fullProduction`).
  ///   An Epic is covered once it receives a Production Pass after the Skeleton (same STABLE-sibling rule as MVP).
  ///   `isReadyForLaunch` = Skeleton built and every Full Production Epic covered → next release is `v1.0` Launch.
  /// - Legacy projects (Full Production built before Act 2, no tagged Epics) keep the old all-Epic coverage.
  ({
    int coveredBeats,
    int totalBeats,
    int remainingDeferredCount,
    int openFixCount,
    List<String> uncoveredBeatTitles,
    List<String> remainingDeferredExclusions,
    List<String> completedBeatCodes,
    List<String> incompleteBeatCodes,
    bool skeletonBuilt,
    bool launchReleaseBuilt,
    bool isLegacy,
    bool isReadyForLaunch,
  }) fullProductionCoverage() {
    final builtReleases =
        projectReleases.where((r) => r.childrenIds.isNotEmpty).toList();
    final builtFullProd = builtReleases
        .where((r) => releasePhaseFor(r) == ProductionPhase.fullProduction)
        .toList();
    final skeletonVer = fullProductionSkeletonVersionTag;
    final launchReleaseBuilt =
        builtFullProd.any((r) => r.sections['launchRelease'] == 'true');
    final beats = activeReleaseBeats;
    final hasFpEpics = beats.any((b) => b.isFullProductionEpic);
    final isLegacy = builtFullProd.isNotEmpty && !hasFpEpics;
    final prodOrVsVerTags = <String>{
      for (final r in builtReleases)
        if (releasePhaseFor(r) == ProductionPhase.fullProduction ||
            releasePhaseFor(r) == ProductionPhase.verticalSlice ||
            releasePhaseFor(r) == ProductionPhase.postLaunch)
          releaseVersionTagFor(r).toLowerCase(),
    };
    int coveredBeats = 0;
    int totalBeats = 0;
    int openFixCount = 0;
    final uncoveredBeatTitles = <String>[];
    final completedBeatCodes = <String>[];
    final incompleteBeatCodes = <String>[];
    final activeFeatTitlesLower = <String>{};

    bool featureHasProductionPass(TierDocument f) {
      if (skeletonVer == null) return false;
      final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
      if (originVer != skeletonVer) return true;
      return FeatureStateNode.getStatesForDocument(f).any(
        (s) => s.releaseVersion.toLowerCase() != skeletonVer,
      );
    }

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
      for (final f in feats) {
        activeFeatTitlesLower.add(f.title.toLowerCase().trim());
        for (final s in FeatureStateNode.getStatesForDocument(f)) {
          for (final t in s.checklist) {
            if (t.text.startsWith('[FIX]') && !t.completed) {
              openFixCount++;
            }
          }
        }
      }

      final bool beatCovered;
      if (isLegacy) {
        beatCovered = feats.any((f) {
          final originVer =
              (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
          final states = FeatureStateNode.getStatesForDocument(f);
          return prodOrVsVerTags.contains(originVer) ||
              states.any(
                (s) => prodOrVsVerTags.contains(s.releaseVersion.toLowerCase()),
              ) ||
              getDocumentProgress(f.id) >= 100;
        });
      } else {
        if (!b.isFullProductionEpic) continue;
        final beatHasAnyPass = feats.any(featureHasProductionPass);
        beatCovered = feats.isNotEmpty &&
            beatHasAnyPass &&
            feats.every(
              (f) =>
                  featureHasProductionPass(f) ||
                  getDocumentProgress(f.id) >= 100,
            );
      }
      totalBeats++;
      if (beatCovered) {
        coveredBeats++;
        completedBeatCodes.add(eTag);
      } else {
        uncoveredBeatTitles.add('$eTag · ${b.title}');
        incompleteBeatCodes.add(eTag);
      }
    }

    final remainingDeferredExclusions = <String>[];
    final proj = activeProject;
    final rawEx = (proj?.sections['exclusions'] ?? '').trim();
    if (rawEx.isNotEmpty) {
      for (final line in rawEx.split('\n')) {
        final clean = WorkbenchReleaseMixin._stripExclusionPrefixes(line, stripNoPrefix: false);
        if (clean.isEmpty) continue;
        // Permanent exclusions stay excluded; deferred exclusions unlocked by Full Production count if not yet promoted
        if (ReleaseBlueprint.isDeferredExclusionUnlockedInPhase(
          clean,
          ProductionPhase.fullProduction,
        )) {
          final shortTitle = WorkbenchReleaseMixin._stripExclusionPrefixes(clean)
              .split('—')
              .first
              .split(':')
              .first
              .toLowerCase()
              .trim();
          final alreadyPromoted = shortTitle.isNotEmpty &&
              activeFeatTitlesLower.any(
                (ft) => ft.contains(shortTitle) || shortTitle.contains(ft),
              );
          if (!alreadyPromoted) {
            remainingDeferredExclusions.add(clean);
          }
        }
      }
    }

    final allCovered = totalBeats > 0 && coveredBeats >= totalBeats;
    final isReadyForLaunch = isLegacy
        ? allCovered && openFixCount == 0
        : skeletonVer != null && allCovered;

    return (
      coveredBeats: coveredBeats,
      totalBeats: totalBeats,
      remainingDeferredCount: remainingDeferredExclusions.length,
      openFixCount: openFixCount,
      uncoveredBeatTitles: uncoveredBeatTitles,
      remainingDeferredExclusions: remainingDeferredExclusions,
      completedBeatCodes: completedBeatCodes,
      incompleteBeatCodes: incompleteBeatCodes,
      skeletonBuilt: skeletonVer != null,
      launchReleaseBuilt: launchReleaseBuilt,
      isLegacy: isLegacy,
      isReadyForLaunch: isReadyForLaunch,
    );
  }

  /// True once the Vertical Slice is done (or a draft release is set to Full Production)
  /// and the next step is defining the Act 2 Full Production Blueprint (no Full Production release built yet).
  bool get needsFullProductionBlueprint {
    final builtReleases =
        projectReleases.where((r) => r.childrenIds.isNotEmpty).toList();
    if (builtReleases.isEmpty) return false;
    if (builtReleases.any(
      (r) =>
          releasePhaseFor(r) == ProductionPhase.fullProduction ||
          releasePhaseFor(r) == ProductionPhase.postLaunch,
    )) {
      return false;
    }
    final activeDraftPhase =
        (activeRelease != null && activeRelease!.childrenIds.isEmpty)
            ? releasePhaseFor(activeRelease!)
            : null;
    return inferNextProgressivePhase() == ProductionPhase.fullProduction ||
        activeDraftPhase == ProductionPhase.fullProduction;
  }

  /// Infers the natural next `ProductionPhase` (`prototype` -> multi-release `mvp` -> multi-release `verticalSlice` -> `fullProduction` -> `postLaunch`).
  /// Act 2 stays in `fullProduction` (Skeleton -> Production Passes -> `v1.0` Launch) until the `v1.0` Launch Release
  /// is 100% verified with `0` open `[FIX]` tasks, then graduates to `v1.1+` Post-Launch & Live Ops.
  ProductionPhase inferNextProgressivePhase() {
    final releases = projectReleases;
    final builtReleases =
        releases.where((r) => r.childrenIds.isNotEmpty).toList();
    if (builtReleases.isEmpty) {
      return ProductionPhase.prototype;
    }
    if (builtReleases.any(
      (r) => releasePhaseFor(r) == ProductionPhase.postLaunch,
    )) {
      return ProductionPhase.postLaunch;
    }
    final builtFullProd = builtReleases
        .where((r) => releasePhaseFor(r) == ProductionPhase.fullProduction)
        .toList();
    if (builtFullProd.isNotEmpty) {
      final fpCov = fullProductionCoverage();
      if (fpCov.isLegacy) {
        final allFullProdVerified = builtFullProd.every(
          (r) => getDocumentProgress(r.id) >= 100,
        );
        if (allFullProdVerified || fpCov.isReadyForLaunch) {
          return ProductionPhase.postLaunch;
        }
        return ProductionPhase.fullProduction;
      }
      final launchRels =
          builtFullProd.where((r) => r.sections['launchRelease'] == 'true');
      if (launchRels.isNotEmpty &&
          launchRels.every((r) => getDocumentProgress(r.id) >= 100) &&
          fpCov.openFixCount == 0) {
        return ProductionPhase.postLaunch;
      }
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

  /// True when the next Full Production release should be the `v1.0` Launch Release.
  bool get isNextReleaseV1Launch {
    if (inferNextProgressivePhase() != ProductionPhase.fullProduction) {
      return false;
    }
    final cov = fullProductionCoverage();
    return !cov.isLegacy && cov.isReadyForLaunch && !cov.launchReleaseBuilt;
  }

  /// Next Post-Launch version: highest existing `v1.N` minor + 1 (handles legacy `v1.x` Full Production tags).
  String get _nextPostLaunchVersionTag {
    int maxMinor = 0;
    final v1Regex = RegExp(r'^v1\.(\d+)$');
    for (final r in projectReleases) {
      if (r.childrenIds.isEmpty) continue;
      final m = v1Regex.firstMatch(releaseVersionTagFor(r).toLowerCase());
      if (m != null) {
        final minor = int.tryParse(m.group(1)!) ?? 0;
        if (minor > maxMinor) maxMinor = minor;
      }
    }
    return 'v1.${maxMinor + 1}';
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
      case ProductionPhase.postLaunch:
        return ReleaseScope.fullProduction;
    }
  }

  /// Allows the developer to switch the target `ProductionPhase` (`MVP`, `Vertical Slice`, `Full Production`, `Post-Launch`)
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
    if (targetPhase == ProductionPhase.postLaunch) {
      final existingPostCount = projectReleases
          .where(
            (r) =>
                r.id != relDoc.id &&
                releasePhaseFor(r) == ProductionPhase.postLaunch,
          )
          .length;
      relDoc.sections['versionTag'] = _nextPostLaunchVersionTag;
      relDoc.sections['postLaunchPass'] = '${existingPostCount + 1}';
      relDoc.sections.remove('launchRelease');
    } else if (targetPhase == ProductionPhase.fullProduction) {
      relDoc.sections.remove('postLaunchPass');
      final existingFullProdCount = projectReleases
          .where(
            (r) =>
                r.id != relDoc.id &&
                releasePhaseFor(r) == ProductionPhase.fullProduction,
          )
          .length;
      final pass = existingFullProdCount + 1;
      final idx = proj.childrenIds.indexOf(relDoc.id);
      final isLaunch = isNextReleaseV1Launch;
      relDoc.sections['versionTag'] = isLaunch
          ? 'v1.0'
          : 'v0.${idx >= 0 ? idx + 1 : proj.childrenIds.length}';
      if (isLaunch) {
        relDoc.sections['launchRelease'] = 'true';
      } else {
        relDoc.sections.remove('launchRelease');
      }
      relDoc.sections['fullProductionPass'] = '$pass';
    } else {
      relDoc.sections.remove('fullProductionPass');
      relDoc.sections.remove('postLaunchPass');
      relDoc.sections.remove('launchRelease');
      final idx = proj.childrenIds.indexOf(relDoc.id);
      if (idx >= 0) {
        relDoc.sections['versionTag'] = 'v0.${idx + 1}';
      }
    }
    final resolvedVerTag = relDoc.sections['versionTag'] ?? 'v0.2';
    relDoc.title = '$resolvedVerTag: ${targetPhase.label}';
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
      final isActTwoOrLater =
          relDoc.sections['phase'] == ProductionPhase.fullProduction.name ||
          relDoc.sections['phase'] == ProductionPhase.postLaunch.name ||
          relDoc.releaseScope == ReleaseScope.fullProduction ||
          currentVerTag.toLowerCase().startsWith('v1.');
      if (isActTwoOrLater) continue;

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
      if (WorkbenchReleaseMixin._minorVerRegex.hasMatch(relDoc.title)) {
        final updatedTitle = relDoc.title.replaceAll(
          WorkbenchReleaseMixin._minorVerRegex,
          expectedVer,
        );
        if (updatedTitle != relDoc.title) {
          relDoc.title = updatedTitle;
          docChanged = true;
        }
      }
      final rawScope = relDoc.sections['scope'];
      if (rawScope != null &&
          WorkbenchReleaseMixin._minorVerRegex.hasMatch(rawScope)) {
        final updatedScope = rawScope.replaceAll(
          WorkbenchReleaseMixin._minorVerRegex,
          expectedVer,
        );
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
              WorkbenchReleaseMixin._minorVerRegex,
              expectedVer,
            ),
            doneWhen: _releaseBlueprint!.doneWhen.replaceAll(
              WorkbenchReleaseMixin._minorVerRegex,
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

  /// Next progressive version tag (`v0.2`, `v0.3`, ... continuing through Act 2 Full Production,
  /// `v1.0` for the Launch Release, then `v1.1+` in Post-Launch).
  String get nextProgressiveVersionLabel {
    final releases = projectReleases;
    final builtReleases =
        releases.where((r) => r.childrenIds.isNotEmpty).toList();
    if (builtReleases.isNotEmpty) {
      final nextPhase = inferNextProgressivePhase();
      if (nextPhase == ProductionPhase.postLaunch) {
        return _nextPostLaunchVersionTag;
      }
      if (nextPhase == ProductionPhase.fullProduction) {
        if (isNextReleaseV1Launch) return 'v1.0';
        if (fullProductionCoverage().isLegacy) {
          return _nextPostLaunchVersionTag;
        }
      }
    }
    final builtCount = builtReleases.length;
    final baseCount = builtCount > 0 ? builtCount : releases.length;
    return 'v0.${baseCount + 1}';
  }

  // ===========================================================================
  // ACT 2 · FULL PRODUCTION BLUEPRINT (Blueprint -> v0.N Skeleton -> Passes -> v1.0 Launch)
  // ===========================================================================

  /// The approved or in-progress Act 2 Full Production Blueprint persisted on the active project.
  FullProductionBlueprint? get fullProductionBlueprint {
    final raw = activeProject?.sections[FullProductionBlueprint.storageKey];
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return FullProductionBlueprint.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  bool get isDraftingFullProductionBlueprint =>
      _isDraftingFullProductionBlueprint;

  /// Saves edits to the Full Production Blueprint (before the Skeleton is built).
  void updateFullProductionBlueprint(FullProductionBlueprint bp) {
    final proj = activeProject;
    if (proj == null) return;
    proj.sections[FullProductionBlueprint.storageKey] = jsonEncode(bp.toJson());
    _persistDocument(proj);
    notifyListeners();
  }

  /// Inbox items scheduled for Full Production (not yet implemented).
  List<FeatureInboxItem> get _fullProductionScheduledInboxItems => featureInboxItems
      .where(
        (i) =>
            i.status != FeatureInboxStatus.implemented &&
            i.releaseTimingMode != InboxReleaseTimingMode.now &&
            i.targetFuturePhase.index <= ProductionPhase.fullProduction.index,
      )
      .toList();

  /// Drafts the 6-section Full Production Blueprint with `gemini-flash-latest` (single pass).
  Future<FullProductionBlueprint?> draftFullProductionBlueprint() async {
    final proj = activeProject;
    if (proj == null) return null;
    _isDraftingFullProductionBlueprint = true;
    notifyListeners();
    try {
      final conceptSummary = '''
Concept Blueprint:
- 01 Goal: "${SectionTextUtils.resolveGoal(proj.sections)}"
- 02 Game Spec: ${proj.sections['game_spec'] ?? ''}
- 03 Tech Spec: ${proj.sections['tech_spec'] ?? ''}
- 04 Design Pillars: ${(proj.sections['design_pillars'] ?? '').replaceAll('\n', ' | ')}
- 05 Trade-Offs: ${(proj.sections['trade_offs'] ?? '').replaceAll('\n', ' | ')}
- 07 Out of Scope: ${(proj.sections['exclusions'] ?? '').replaceAll('\n', ' | ')}
- 08 Done When: "${SectionTextUtils.resolveDoneWhen(proj.sections)}"''';
      final treeLines = <String>[];
      final beats = activeReleaseBeats;
      for (int bIdx = 0; bIdx < beats.length; bIdx++) {
        final feats = featuresForBeat(beats[bIdx].id).map((f) {
          final asset = (f.sections['primary_asset'] ?? '').trim();
          return asset.isNotEmpty ? '${f.title} [$asset]' : f.title;
        }).join(', ');
        treeLines.add(
          '- E${(bIdx + 1).toString().padLeft(2, '0')} ${beats[bIdx].title}: $feats',
        );
      }
      final unlockedDeferred = fullProductionCoverage().remainingDeferredExclusions;
      final drafted = await FullProductionBlueprintAgent.draft(
        projectTitle: proj.title,
        conceptSummary: conceptSummary,
        liveTreeSummary: treeLines.join('\n'),
        unlockedDeferredExclusions: unlockedDeferred,
        scheduledInboxTitles: [
          for (final i in _fullProductionScheduledInboxItems) i.featureTitle,
        ],
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
      );
      if (drafted == null) {
        _setOfflineState();
        return null;
      }
      _offlineErrorMessage = null;
      updateFullProductionBlueprint(drafted);
      return drafted;
    } finally {
      _isDraftingFullProductionBlueprint = false;
      notifyListeners();
    }
  }

  /// Approves the Full Production Blueprint and builds the `v0.N` Full-Game Skeleton release:
  /// core Epics stay `STABLE ✓`, new Full Production Epics are planned in one full-blueprint pass
  /// (always via `planRelease`, never section-by-section) and tagged `act: fullProduction` on execute.
  Future<bool> approveFullProductionBlueprintAndBuildSkeleton() async {
    final proj = activeProject;
    final fpBp = fullProductionBlueprint;
    if (proj == null || fpBp == null || !fpBp.isReadyToApprove) return false;
    if (!GeminiAgentClient.hasKey(_apiKey)) {
      _setOfflineState();
      notifyListeners();
      return false;
    }

    repackProjectReleasesSequentially(proj, pruneAllUnbuilt: true);
    final existingBeats = List<TierDocument>.from(activeReleaseBeats);
    final existingFeaturesByBeat = <String, List<TierDocument>>{
      for (final b in existingBeats)
        b.id: featuresForBeat(b.id, includeSuperseded: true),
    };
    final completedReleases = projectReleases
        .where((r) => r.childrenIds.isNotEmpty)
        .toList();
    final allocated = _allocateNextReleaseIdAndIndex(proj);
    final verTag = 'v0.${allocated.index}';
    final relDoc = TierDocument(
      id: allocated.id,
      title: '$verTag: Full-Game Skeleton - Full Production',
      tier: TierType.release,
      parentId: proj.id,
      sections: {
        'versionTag': verTag,
        'releaseScope': ReleaseScope.fullProduction.name,
        'phase': ProductionPhase.fullProduction.name,
        'fullProductionPass': '1',
        'fpSkeleton': 'true',
        'scope':
            'Goal: ${fpBp.goal}\n\nIn Scope:\n${fpBp.fullGameLoop.map((l) => '• $l').join('\n')}\n\nDone When: ${fpBp.doneWhen}',
      },
    );
    documents[relDoc.id] = relDoc;
    _persistDocument(relDoc);
    proj.childrenIds.add(relDoc.id);
    _activeReleaseId = relDoc.id;
    _currentPhase = ProductionPhase.fullProduction;
    _currentStage = WorkbenchStage.releaseWorkbench;
    _syncActiveProjectMetadata();

    _isAgentBusy = true;
    _agentProgressStep = 'Planning $verTag Full-Game Skeleton…';
    notifyListeners();
    ReleaseBlueprint? planned;
    try {
      planned = await ReleasePlannerAgent.planRelease(
        projectDoc: proj,
        releaseDoc: relDoc,
        completedReleases: completedReleases,
        existingBeats: existingBeats,
        existingFeaturesByBeat: existingFeaturesByBeat,
        apiKey: _apiKey,
        modelName: _planningModel,
        thinkingLevel: _thinkingLevel,
        fullProductionBlueprint: fpBp,
      );
    } finally {
      _isAgentBusy = false;
      _agentProgressStep = null;
    }
    if (planned == null ||
        !planned.beats.any(
          (b) => !existingBeats.any((eb) => eb.id == b.id) &&
              b.includedFeatures.isNotEmpty,
        )) {
      proj.childrenIds.remove(relDoc.id);
      documents.remove(relDoc.id);
      LocalVaultService.deleteDocument(relDoc.id);
      _activeReleaseId = completedReleases.isNotEmpty
          ? completedReleases.last.id
          : null;
      _syncActiveProjectMetadata();
      _setOfflineState();
      notifyListeners();
      return false;
    }
    planned.releaseVersionTag = verTag;
    relDoc.sections['release_blueprint_json'] = jsonEncode(planned.toJson());
    _persistDocument(relDoc);
    _releaseBlueprint = planned;
    _offlineErrorMessage = null;
    _markPromotedInboxItemsImplemented(fpBp.promotedSystems);
    await approveAndExecuteReleasePlan();
    return true;
  }

  /// Single source of truth: Inbox items promoted through `04 Promoted Systems` are marked implemented
  /// so they are never auto-injected a second time.
  void _markPromotedInboxItemsImplemented(List<String> promotedSystems) {
    final promotedLower = [
      for (final p in promotedSystems) p.toLowerCase().trim(),
    ].where((p) => p.isNotEmpty).toList();
    if (promotedLower.isEmpty) return;
    final items = List<FeatureInboxItem>.from(featureInboxItems);
    bool changed = false;
    for (final item in items) {
      if (item.status == FeatureInboxStatus.implemented) continue;
      if (item.targetFuturePhase.index > ProductionPhase.fullProduction.index) {
        continue;
      }
      final title = item.featureTitle.toLowerCase().trim();
      if (title.isEmpty) continue;
      if (promotedLower.any((p) => p == title || p.contains(title) || title.contains(p))) {
        item.status = FeatureInboxStatus.implemented;
        changed = true;
      }
    }
    if (changed) _saveFeatureInboxItems(items);
  }

  /// Deterministic `v1.0` Launch Release blueprint: every feature stays `STABLE ✓` (open `[FIX]` tasks are
  /// resolved in place) plus 1 `[NEW]` Release Build Export feature in the last Full Production Epic.
  ReleaseBlueprint? _buildLaunchReleaseBlueprint(
    TierDocument relDoc,
    String verTag,
    List<TierDocument> existingBeats,
  ) {
    if (existingBeats.isEmpty) return null;
    final fpBp = fullProductionBlueprint;
    final shipWhen = (fpBp?.doneWhen.trim().isNotEmpty ?? false)
        ? fpBp!.doneWhen.trim()
        : 'Launch standalone build → play from title screen to credits without crashes';
    final lastFpIdx = existingBeats.lastIndexWhere((b) => b.isFullProductionEpic);
    final hostIdx = lastFpIdx >= 0 ? lastFpIdx : existingBeats.length - 1;
    const exportTuning = <String>[
      'buildTargets: 1 platform',
      'fullRunThroughs: 2 runs',
    ];
    const exportGuards = <String>[
      '[STATE GUARD] Block ship while any [FIX] task is open',
    ];
    final beats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final b = existingBeats[bIdx];
      final feats = <ProposedFeatureBlueprint>[
        for (final f in featuresForBeat(b.id, includeSuperseded: true))
          ProposedFeatureBlueprint(
            id: f.id,
            title: f.title,
            goal: SectionTextUtils.resolveGoal(f.sections),
            doneWhen: SectionTextUtils.resolveDoneWhen(f.sections),
            estimatedHours: 0,
            included: !isFeatureSuperseded(f),
            lifecycle: isFeatureSuperseded(f)
                ? FeatureLifecycleStatus.superseded
                : FeatureLifecycleStatus.stable,
            originVersion: f.sections['originVersion'] ?? 'v0.1',
            primarySharedScriptOrScene:
                (f.sections['primary_asset'] ?? '').trim().isNotEmpty
                    ? f.sections['primary_asset']!.trim()
                    : null,
            inScope: SectionTextUtils.resolveInScope(f.sections),
          ),
        if (bIdx == hostIdx)
          ProposedFeatureBlueprint(
            id: 'feat_${b.id}_${verTag.replaceAll('.', '_')}_release_export',
            title: 'Release Build Export',
            goal: '+Standalone export preset, +full run-through, +crash & save check',
            doneWhen: shipWhen,
            estimatedHours: 4,
            included: true,
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: verTag,
            inScope: const [
              '+Standalone export preset & icon',
              '+Full title-to-credits run-through',
              '+Crash & save check',
            ],
            tuningParams: exportTuning,
            edgeCases: exportGuards,
            checkpoints: [
              ProposedCheckpointBlueprint(
                title: 'Release Build Export',
                playtestCriteria: shipWhen,
                releaseVersion: verTag,
                tasks: const [
                  'Export Preset & Icon',
                  'Standalone Run-Through',
                  'Crash & Save Check',
                ],
                coveredScope: const ['+Standalone export & run-through'],
                tuningParams: exportTuning,
                edgeCases: exportGuards,
              ),
            ],
          ),
      ];
      beats.add(
        ProposedBeatBlueprint(
          id: b.id,
          title: b.title,
          goal: SectionTextUtils.resolveGoal(b.sections),
          doneWhen: SectionTextUtils.resolveDoneWhen(b.sections),
          features: feats,
        ),
      );
    }
    return ReleaseBlueprint(
      releaseDocId: relDoc.id,
      releaseTitle: '$verTag: Launch Release — Build Export & Ship Sweep',
      releaseVersionTag: verTag,
      preset: ReleaseScope.fullProduction,
      goal: 'v1.0 Launch — Export the standalone build and clear every open [FIX] task.',
      doneWhen: shipWhen,
      questions: const [],
      beats: beats,
      explicitExclusions: fpBp?.permanentCuts ?? const [],
    );
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
    _preModalFeatureInboxJson = activeProject?.sections['feature_inbox_json'];
    _preModalExclusions = activeProject?.sections['exclusions'];
    _preModalConceptExclusions = _conceptDraft != null
        ? List<String>.from(_conceptDraft!.exclusions)
        : null;
    _preModalFeatureLifecycles = {
      for (final d in documents.values.where((d) => d.tier == TierType.feature))
        d.id: d.sections['lifecycle'],
    };
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
      final proj = activeProject;
      if (proj != null) {
        if (_preModalFeatureInboxJson != null) {
          proj.sections['feature_inbox_json'] = _preModalFeatureInboxJson!;
        } else {
          proj.sections.remove('feature_inbox_json');
        }
        _cachedInboxRawHash = null;
        if (_preModalExclusions != null) {
          proj.sections['exclusions'] = _preModalExclusions!;
        } else {
          proj.sections.remove('exclusions');
        }
        _persistDocument(proj);
      }
      if (_conceptDraft != null && _preModalConceptExclusions != null) {
        _conceptDraft!.exclusions =
            List<String>.from(_preModalConceptExclusions!);
      }
      final preLifecycles = _preModalFeatureLifecycles;
      if (preLifecycles != null) {
        for (final entry in preLifecycles.entries) {
          final featDoc = documents[entry.key];
          if (featDoc == null) continue;
          if (entry.value != null) {
            featDoc.sections['lifecycle'] = entry.value!;
          } else {
            featDoc.sections.remove('lifecycle');
          }
          if (entry.value != FeatureLifecycleStatus.superseded.name) {
            featDoc.sections.remove('supersededInVersion');
          }
          _persistDocument(featDoc);
        }
      }
      final relDoc = activeRelease;
      if (relDoc != null && relDoc.id == restored.releaseDocId) {
        relDoc.sections['release_blueprint_json'] = raw;
        _persistDocument(relDoc);
      }
      _syncActiveProjectMetadata();
      notifyListeners();
    } catch (_) {}
  }

  static final RegExp _epicPrefixStripper = RegExp(
    r'^(?:epic\s*\d+|beat\s*\d+|e0?\d+)\s*[:·—\-]\s*',
    caseSensitive: false,
  );
  static final RegExp _leadingVerbStripper = RegExp(
    r'^(?:build|create|implement|add|upgrade|extend|configure|wire|setup|set up|enable|establish|allow|support)\s+(?:the|a|an)?\s*',
    caseSensitive: false,
  );
  static final RegExp _changelogInlineArticlesRegex = RegExp(
    r'\b(?:a|an|the|your|our)\s+',
    caseSensitive: false,
  );
  static final RegExp _changelogTrailingFillerRegex = RegExp(
    r'\s+(?:in\s+(?:the\s+)?(?:arena|scene|level|game|viewport)|for\s+(?:the\s+)?player|on\s+screen)$',
    caseSensitive: false,
  );

  String _shortBeatName(String rawTitle, int idx) {
    final cleaned = rawTitle.replaceFirst(_epicPrefixStripper, '').trim();
    return cleaned.isNotEmpty ? cleaned : 'Epic ${idx + 1}';
  }

  String _formatTelegraphicDeltaItem(String raw, {required bool isUpgrade}) {
    var cleaned = raw
        .trim()
        .replaceFirst(RegExp(r'^\+\s*'), '')
        .replaceFirst(_leadingVerbStripper, '')
        .replaceFirst(_changelogTrailingFillerRegex, '')
        .replaceAll(_changelogInlineArticlesRegex, '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';
    cleaned = cleaned[0].toUpperCase() + cleaned.substring(1);
    return isUpgrade ? '+$cleaned' : cleaned;
  }

  /// Formats a feature's scope/goal into a concise **Telegraphic Changelog Delta (`+Delta`)** string for `UPGRADE`
  /// features or a clean telegraphic phrase for `NEW` features.
  String formatChangelogDeltaForFeature(ProposedFeatureBlueprint feat) {
    final isUpg = feat.lifecycle == FeatureLifecycleStatus.upgrade;
    final items = <String>[];
    for (final raw in feat.inScope) {
      final cleaned = _formatTelegraphicDeltaItem(raw, isUpgrade: isUpg);
      if (cleaned.isNotEmpty &&
          cleaned.replaceFirst('+', '').toLowerCase() !=
              feat.title.toLowerCase()) {
        items.add(cleaned);
      }
      if (items.length >= 2) break;
    }
    if (items.isNotEmpty) {
      return items.join(', ');
    }
    final cleanGoal = _formatTelegraphicDeltaItem(feat.goal, isUpgrade: isUpg);
    if (cleanGoal.isEmpty) {
      return isUpg ? '+MVP functional upgrade & tuning' : feat.title;
    }
    return cleanGoal;
  }

  /// Generates the 3 selectable **EPICS** option cards for the Progressive Release Co-Pilot
  /// directly from the remaining incomplete Epics (`E01..EN`), using:
  /// - **BLUF** card titles (`E02 + E03 · <Epic Titles>`)
  /// - **Telegraphic (`+`-joined)** card subtitles
  /// - **BLUF** `GOAL:` (`<Bold Payoff> — <Concise Epic Scope>`)
  /// - **Causal `Trigger → Result`** `✓ END GOAL:` (`<Action> → <Observable Screen Result>`)
  List<({
    String title,
    String subtitle,
    String blufHeadline,
    String blufDetail,
    String causalDoneWhen,
    List<int> targetBeatIndices,
    bool isRecommended,
  })> epicFocusOptionsForBlueprint(ReleaseBlueprint bp) {
    final totalBeats = bp.beats.length;
    if (totalBeats == 0) return const [];

    // Act 2 · v1.0 Launch Release: a single Launch Sweep card (no Epic slicing).
    if (documents[bp.releaseDocId]?.sections['launchRelease'] == 'true') {
      final hostIdx = bp.beats.indexWhere(
        (b) => b.features.any((f) => f.included && !f.isStable && !f.isSuperseded),
      );
      final openFixes = fullProductionCoverage().openFixCount;
      return [
        (
          title: 'v1.0 Launch Sweep',
          subtitle:
              'Release Build Export${openFixes > 0 ? ' + $openFixes open [FIX]' : ''}',
          blufHeadline: 'v1.0 Launch',
          blufDetail:
              'Export the standalone build and clear every open [FIX] task.',
          causalDoneWhen: bp.doneWhen,
          targetBeatIndices: <int>[if (hostIdx >= 0) hostIdx],
          isRecommended: true,
        ),
      ];
    }

    final phase = _currentPhase;
    final isVs = phase == ProductionPhase.verticalSlice;
    final isFp = phase == ProductionPhase.fullProduction;
    final mvpCov = mvpBeatCoverage();
    final vsCov = verticalSliceBeatCoverage();
    final fpCov = isFp ? fullProductionCoverage() : null;
    final incompleteCodes = (fpCov != null && !fpCov.isLegacy)
        ? fpCov.incompleteBeatCodes.toSet()
        : (isVs
            ? vsCov.incompleteBeatCodes.toSet()
            : mvpCov.incompleteBeatCodes.toSet());

    final incompleteIndices = <int>[];
    final initialActiveIndices = <int>[];
    for (int i = 0; i < totalBeats; i++) {
      final code = 'E${(i + 1).toString().padLeft(2, '0')}';
      if (incompleteCodes.contains(code)) {
        incompleteIndices.add(i);
      }
      final b = bp.beats[i];
      if (b.features.any((f) => f.included && !f.isStable && !f.isSuperseded)) {
        initialActiveIndices.add(i);
      }
    }

    final fpEpicIndices = <int>[
      if (fpCov != null && !fpCov.isLegacy)
        for (int i = 0; i < totalBeats; i++)
          if (documents[bp.beats[i].id]?.isFullProductionEpic ?? false) i,
    ];
    final availableIndices = incompleteIndices.isNotEmpty
        ? incompleteIndices
        : (fpEpicIndices.isNotEmpty
            ? fpEpicIndices
            : List<int>.generate(totalBeats, (i) => i));

    // Card 0 (Recommended): initial active incomplete Epics (or first 1-2 available incomplete Epics)
    final recIndices = initialActiveIndices.isNotEmpty
        ? initialActiveIndices
        : availableIndices.take(availableIndices.length >= 2 ? 2 : 1).toList();

    // Card 1: Focused single-Epic option on the first available incomplete Epic
    final firstSingleIdx = availableIndices.first;
    final opt1Indices = (recIndices.length == 1 &&
            recIndices.first == firstSingleIdx &&
            availableIndices.length >= 2)
        ? <int>[availableIndices[0], availableIndices[1]]
        : <int>[firstSingleIdx];

    // Card 2: Alternative incomplete Epic(s)
    List<int> opt2Indices;
    if (availableIndices.length >= 3) {
      opt2Indices = <int>[availableIndices[1], availableIndices[2]];
    } else if (availableIndices.length == 2) {
      opt2Indices = <int>[availableIndices[1]];
    } else if (totalBeats >= 2) {
      final otherIdx = (firstSingleIdx + 1) % totalBeats;
      opt2Indices = <int>[firstSingleIdx, otherIdx];
    } else {
      opt2Indices = <int>[0];
    }

    ({
      String title,
      String subtitle,
      String blufHeadline,
      String blufDetail,
      String causalDoneWhen,
      List<int> targetBeatIndices,
      bool isRecommended,
    }) buildCardConfig(
      List<int> indices, {
      required bool isRec,
      required bool forceSingleLabel,
    }) {
      final codes = [
        for (final i in indices) 'E${(i + 1).toString().padLeft(2, '0')}',
      ];
      final names = [
        for (final i in indices) _shortBeatName(bp.beats[i].title, i),
      ];
      final codePrefix = forceSingleLabel && codes.length == 1
          ? '${codes.first} Only'
          : codes.join(' + ');
      final joinedNames = names.take(2).join(' & ');
      final cardTitle = '$codePrefix · $joinedNames';

      final telegraphicTokens = <String>[];
      for (final i in indices) {
        for (final f in bp.beats[i].features) {
          if (f.isSuperseded) continue;
          telegraphicTokens.add(f.title);
          if (telegraphicTokens.length >= 3) break;
        }
        if (telegraphicTokens.length >= 3) break;
      }
      final subtitle = telegraphicTokens.isNotEmpty
          ? telegraphicTokens.join(' + ')
          : names.join(' + ');

      final phaseLabel = phase == ProductionPhase.verticalSlice
          ? 'Vertical Slice polish'
          : (phase == ProductionPhase.fullProduction
              ? 'Full Production'
              : 'MVP');
      final epicPairsText = [
        for (int k = 0; k < indices.length; k++) '${codes[k]} ${names[k]}',
      ].join(' and ');

      final blufHeadline = joinedNames;
      final blufDetail = 'Complete $epicPairsText for $phaseLabel.';

      final String causalDoneWhen;
      if (isRec && bp.doneWhen.trim().isNotEmpty && bp.doneWhen.contains('→')) {
        causalDoneWhen = bp.doneWhen.trim();
      } else if (telegraphicTokens.length >= 2) {
        causalDoneWhen =
            'Trigger ${telegraphicTokens.first} in Play mode → verify ${telegraphicTokens.skip(1).join(" + ")} on screen';
      } else {
        causalDoneWhen =
            'Playtest ${codes.join(" + ")} in Play mode → verify all $joinedNames mechanics respond without state locks';
      }

      return (
        title: cardTitle,
        subtitle: subtitle,
        blufHeadline: blufHeadline,
        blufDetail: blufDetail,
        causalDoneWhen: causalDoneWhen,
        targetBeatIndices: indices,
        isRecommended: isRec,
      );
    }

    return [
      buildCardConfig(
        recIndices,
        isRec: true,
        forceSingleLabel: false,
      ),
      buildCardConfig(
        opt1Indices,
        isRec: false,
        forceSingleLabel: opt1Indices.length == 1,
      ),
      buildCardConfig(
        opt2Indices,
        isRec: false,
        forceSingleLabel: opt2Indices.length == 1 && opt1Indices.length > 1,
      ),
    ];
  }

  /// Immediately switches the active whole Epics in `_releaseBlueprint` (`0ms`) when the user clicks
  /// one of the 3 Epic option cards in the Progressive Release Co-Pilot.
  void applyProgressiveEpicFocusOption(
    int optionIndex,
    List<int> targetBeatIndices,
  ) {
    if (optionIndex == 0) {
      restoreInitialProgressiveDraftBlueprint();
      return;
    }
    restoreInitialProgressiveDraftBlueprint();
    final bp = _releaseBlueprint;
    if (bp == null || bp.beats.isEmpty) return;

    final verTag = bp.releaseVersionTag;
    final targetSet = targetBeatIndices.toSet();
    final options = epicFocusOptionsForBlueprint(bp);
    final selectedOpt =
        (optionIndex >= 0 && optionIndex < options.length) ? options[optionIndex] : null;

    for (int bIdx = 0; bIdx < bp.beats.length; bIdx++) {
      final beat = bp.beats[bIdx];
      final isTarget = targetSet.contains(bIdx);
      for (final feat in beat.features) {
        if (feat.isSuperseded) continue;
        if (isTarget) {
          if (feat.lifecycle == FeatureLifecycleStatus.stable) {
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
                      'Trigger ${feat.title} in Play mode → verify $verTag upgrade on screen',
                  tasks: ReleasePlannerAgent.defaultDockStepTitles(
                    subject: feat.title,
                  ),
                  coveredScope: feat.inScope.isNotEmpty
                      ? List<String>.from(feat.inScope)
                      : ['${feat.title} $verTag upgrade'],
                  tuningParams: List<String>.from(feat.tuningParams),
                  edgeCases: List<String>.from(feat.edgeCases),
                  releaseVersion: verTag,
                ),
              ];
            }
          } else {
            feat.included = true;
          }
        } else {
          if (feat.lifecycle == FeatureLifecycleStatus.upgrade) {
            feat.lifecycle = FeatureLifecycleStatus.stable;
            feat.estimatedHours = 0;
            feat.included = true;
          } else if (feat.lifecycle == FeatureLifecycleStatus.newFeature) {
            feat.included = false;
          }
        }
      }
    }

    if (selectedOpt != null) {
      bp.releaseTitle = '$verTag: ${selectedOpt.blufHeadline}';
      bp.goal = '${selectedOpt.blufHeadline} — ${selectedOpt.blufDetail}';
      bp.doneWhen = selectedOpt.causalDoneWhen;
      final relDoc = activeRelease;
      if (relDoc != null && relDoc.id == bp.releaseDocId) {
        relDoc.title = bp.releaseTitle;
        relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
        _persistDocument(relDoc);
      }
    }
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  /// Restores the active release, blueprint, and production phase if the user cancels (or fails offline in)
  /// the Progressive Next Release modal, and removes any newly created unbuilt draft release documents.
  void restoreActiveReleaseAfterCancel(
    String? previousReleaseId,
    ProductionPhase previousPhase,
  ) {
    _progressivePlanGeneration++;
    _isSynthesizingProgressiveFocus = false;
    _synthesizingProgressiveBeatId = null;
    _queuedProgressiveBeatIds.clear();
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
    if (proj != null) {
      if (_preModalFeatureInboxJson != null) {
        proj.sections['feature_inbox_json'] = _preModalFeatureInboxJson!;
      } else {
        proj.sections.remove('feature_inbox_json');
      }
      _cachedInboxRawHash = null;
      if (_preModalExclusions != null) {
        proj.sections['exclusions'] = _preModalExclusions!;
      } else {
        proj.sections.remove('exclusions');
      }
    }
    if (_conceptDraft != null && _preModalConceptExclusions != null) {
      _conceptDraft!.exclusions =
          List<String>.from(_preModalConceptExclusions!);
    }
    final preLifecycles = _preModalFeatureLifecycles;
    if (preLifecycles != null) {
      for (final entry in preLifecycles.entries) {
        final featDoc = documents[entry.key];
        if (featDoc == null) continue;
        if (entry.value != null) {
          featDoc.sections['lifecycle'] = entry.value!;
        } else {
          featDoc.sections.remove('lifecycle');
        }
        if (entry.value != FeatureLifecycleStatus.superseded.name) {
          featDoc.sections.remove('supersededInVersion');
        }
        _persistDocument(featDoc);
      }
    }
    if (_preModalReleaseBlueprint != null) {
      _releaseBlueprint = _preModalReleaseBlueprint;
    }
    _preModalReleaseIds = null;
    _preModalReleaseBlueprint = null;
    _preModalFeatureInboxJson = null;
    _preModalExclusions = null;
    _preModalConceptExclusions = null;
    _preModalFeatureLifecycles = null;
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
              existingFeaturesByBeat[bDoc.id] = featuresForBeat(
                bDoc.id,
                includeSuperseded: true,
              );
            }
          }
        }
      }
    }

    // Capture any features deferred (unchecked) across all prior Release Plan Gates (not yet built)
    // so they automatically carry over into the next release's Beat, and archive the prior ReleaseBlueprint on its own Release doc!
    final deferredByBeatIndex = <int, List<ProposedFeatureBlueprint>>{};
    final priorBp = _releaseBlueprint;
    if (priorBp != null) {
      final priorRelDoc = documents[priorBp.releaseDocId];
      if (priorRelDoc != null) {
        priorRelDoc.sections['release_blueprint_json'] =
            _encodeCompactArchivedReleaseBlueprint(priorBp);
        _persistDocument(priorRelDoc);
      }
    }
    final builtFeatureTitleSet = <String>{
      for (final featList in existingFeaturesByBeat.values)
        for (final ef in featList) ef.title.toLowerCase().trim(),
    };
    final priorBlueprintsToScan = <ReleaseBlueprint>[
      for (final rel in projectReleases)
        if (rel.id != targetRelId && rel.childrenIds.isNotEmpty)
          if (releaseBlueprintFor(rel.id) != null) releaseBlueprintFor(rel.id)!,
      if (priorBp != null && priorBp.releaseDocId != targetRelId) priorBp,
    ];
    final seenDeferredByBeat = <int, Set<String>>{};
    for (final scannedBp in priorBlueprintsToScan) {
      for (int bIdx = 0; bIdx < scannedBp.beats.length; bIdx++) {
        final seenTitles = seenDeferredByBeat.putIfAbsent(bIdx, () => <String>{});
        final deferredInBeat = deferredByBeatIndex.putIfAbsent(
          bIdx,
          () => <ProposedFeatureBlueprint>[],
        );
        for (final df in scannedBp.beats[bIdx].deferredFeatures) {
          final normTitle = df.title.toLowerCase().trim();
          if (normTitle.isNotEmpty &&
              !builtFeatureTitleSet.contains(normTitle) &&
              seenTitles.add(normTitle)) {
            deferredInBeat.add(df);
          }
        }
      }
    }
    deferredByBeatIndex.removeWhere((_, list) => list.isEmpty);

    _activeReleaseId = targetRelId;
    final relDoc = documents[targetRelId];
    if (relDoc == null) return;
    _syncCurrentPhaseFromRelease(relDoc);

    _stepQueueGeneration++;
    _progressivePlanGeneration++;
    final int planGeneration = _progressivePlanGeneration;
    _pendingFeatureStepQueue.clear();
    final verTag = releaseVersionTagFor(relDoc);
    relDoc.sections['versionTag'] = verTag;

    // Fast Path 0: `v1.0` Launch Release is deterministic (no AI call): STABLE tree + Release Build Export.
    if (relDoc.sections['launchRelease'] == 'true' && existingBeats.isNotEmpty) {
      final launchBp = _buildLaunchReleaseBlueprint(relDoc, verTag, existingBeats);
      if (launchBp != null) {
        relDoc.title = launchBp.releaseTitle;
        relDoc.sections['release_blueprint_json'] = jsonEncode(launchBp.toJson());
        _persistDocument(relDoc);
        _releaseBlueprint = launchBp;
        _offlineErrorMessage = null;
        if (transitionToGateStage) {
          _currentStage = WorkbenchStage.releaseWorkbench;
        }
        _syncActiveProjectMetadata();
        notifyListeners();
        return;
      }
    }

    _releaseBlueprint = null;
    _isAgentBusy = true;
    final displayPlanModel = _planningModel;
    _agentProgressStep =
        'Synthesizing $verTag Release Architecture ($displayPlanModel)...';

    // Step 0 (`0ms` Live-Tree Skeleton): When opening a Progressive Release (`v0.2+`) in live mode,
    // immediately populate `_releaseBlueprint` with the existing `E01..EN` Epics and `STABLE` features
    // so the 3-Step Progressive Release canvas opens in `0ms` while Section 1 and Section 2 stream in.
    if (!isFirstPrototypeRelease &&
        existingBeats.isNotEmpty &&
        GeminiAgentClient.hasKey(_apiKey) &&
        GeminiAgentClient.testMockResponder == null) {
      final skeletonBp =
          ReleasePlannerAgent.buildProgressiveLiveTreeSkeletonBlueprint(
        projectDoc: proj,
        releaseDoc: relDoc,
        existingBeats: existingBeats,
        existingFeaturesByBeat: existingFeaturesByBeat,
        deferredByBeatIndex: deferredByBeatIndex,
      );
      if (skeletonBp != null) {
        _injectDueScheduledInboxItemsIntoBlueprint(skeletonBp, _currentPhase);
        _releaseBlueprint = skeletonBp;
        _isSynthesizingProgressiveFocus = false;
        _synthesizingProgressiveBeatId = null;
        _queuedProgressiveBeatIds.clear();
        final initialCards = epicFocusOptionsForBlueprint(skeletonBp);
        final initialRec = initialCards.isNotEmpty ? initialCards.first : null;
        final rawTargetEpicIdx = relDoc.sections['targetEpicIndex'];
        final isAgentReasoned = relDoc.sections['agentReasoned'] == 'true';
        final explicitIdx = !isAgentReasoned && rawTargetEpicIdx != null
            ? int.tryParse(rawTargetEpicIdx)
            : null;
        final initialTargetIndices = (explicitIdx != null &&
                explicitIdx >= 0 &&
                explicitIdx < existingBeats.length)
            ? <int>[explicitIdx]
            : (initialRec != null && initialRec.targetBeatIndices.isNotEmpty
                ? initialRec.targetBeatIndices
                : <int>[0]);
        for (final idx in initialTargetIndices) {
          if (idx >= 0 && idx < skeletonBp.beats.length) {
            _queuedProgressiveBeatIds.add(skeletonBp.beats[idx].id);
          }
        }
        _agentProgressStep = 'Planning $verTag Epic upgrades…';
      }
    }
    notifyListeners();

    try {
      final completedPriorReleases = projectReleases
          .where((r) => r.id != targetRelId && r.childrenIds.isNotEmpty)
          .toList();
      final ReleaseBlueprint? planned;
      if (!isFirstPrototypeRelease &&
          existingBeats.isNotEmpty &&
          GeminiAgentClient.testMockResponder == null) {
        planned = await planProgressiveReleaseSectionBySection(
          projectDoc: proj,
          releaseDoc: relDoc,
          completedReleases: completedPriorReleases,
          existingBeats: existingBeats,
          existingFeaturesByBeat: existingFeaturesByBeat,
          deferredByBeatIndex: deferredByBeatIndex,
          generation: planGeneration,
        );
      } else {
        planned = await ReleasePlannerAgent.planRelease(
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
      }
      if (planGeneration != _progressivePlanGeneration) return;
      if (planned != null) {
        if (planned.releaseTitle.isNotEmpty &&
            planned.releaseTitle != relDoc.title) {
          relDoc.title = planned.releaseTitle;
        }
        relDoc.sections.remove('used_baseline_fallback');
        relDoc.sections['versionTag'] = verTag;
        _syncCurrentPhaseFromRelease(relDoc);
        if (!isFirstPrototypeRelease) {
          _injectDueScheduledInboxItemsIntoBlueprint(planned, _currentPhase);
        }
        relDoc.sections['release_blueprint_json'] =
            jsonEncode(planned.toJson());
        _persistDocument(relDoc);
        _releaseBlueprint = planned;
        _offlineErrorMessage = null;
        if (transitionToGateStage) {
          _currentStage = WorkbenchStage.releaseWorkbench;
        }
        _syncActiveProjectMetadata();
      } else {
        _releaseBlueprint = null;
        if (!isFirstPrototypeRelease && existingBeats.isNotEmpty) {
          final fallbackProgressive =
              ReleasePlannerAgent.buildImmediateProgressiveBaselineBlueprint(
            projectDoc: proj,
            releaseDoc: relDoc,
            existingBeats: existingBeats,
            existingFeaturesByBeat: existingFeaturesByBeat,
            deferredByBeatIndex: deferredByBeatIndex,
          );
          if (fallbackProgressive != null) {
            _injectDueScheduledInboxItemsIntoBlueprint(
              fallbackProgressive,
              _currentPhase,
            );
            relDoc.sections['used_baseline_fallback'] = 'true';
            relDoc.sections['release_blueprint_json'] =
                jsonEncode(fallbackProgressive.toJson());
            _persistDocument(relDoc);
            _releaseBlueprint = fallbackProgressive;
            _syncActiveProjectMetadata();
          }
        } else if (isFirstPrototypeRelease &&
            GeminiAgentClient.hasKey(_apiKey)) {
          final fallbackInitial =
              ReleasePlannerAgent.buildImmediateInitialBaselineBlueprint(
            projectDoc: proj,
            releaseDoc: relDoc,
          );
          if (fallbackInitial != null) {
            relDoc.sections['used_baseline_fallback'] = 'true';
            relDoc.sections['versionTag'] = verTag;
            relDoc.sections['release_blueprint_json'] =
                jsonEncode(fallbackInitial.toJson());
            _persistDocument(relDoc);
            _releaseBlueprint = fallbackInitial;
            _syncActiveProjectMetadata();
          }
        }
        if (_releaseBlueprint == null) {
          _setOfflineState();
        }
      }
    } finally {
      if (planGeneration == _progressivePlanGeneration) {
        _isSynthesizingProgressiveFocus = false;
        _synthesizingProgressiveBeatId = null;
        _queuedProgressiveBeatIds.clear();
        _isAgentBusy = false;
        _agentProgressStep = null;
        notifyListeners();
      }
    }
  }

  /// Section-by-Section Progressive Release Orchestrator (`Step 0: 0ms Live-Tree Skeleton & Deterministic Section 1` ->
  /// `Pass 2: Section 2 Target Epics One-by-One`).
  Future<ReleaseBlueprint?> planProgressiveReleaseSectionBySection({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    required List<TierDocument> completedReleases,
    required List<TierDocument> existingBeats,
    required Map<String, List<TierDocument>> existingFeaturesByBeat,
    required Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex,
    bool isBackgroundPrewarm = false,
    int? generation,
  }) async {
    if (!GeminiAgentClient.hasKey(_apiKey) || existingBeats.isEmpty) {
      return null;
    }
    bool isCancelled() =>
        !isBackgroundPrewarm &&
        generation != null &&
        generation != _progressivePlanGeneration;
    final verTag = releaseVersionTagFor(releaseDoc);
    final workingBp = (!isBackgroundPrewarm &&
            _releaseBlueprint != null &&
            _releaseBlueprint!.releaseDocId == releaseDoc.id)
        ? _releaseBlueprint!
        : ReleasePlannerAgent.buildProgressiveLiveTreeSkeletonBlueprint(
            projectDoc: projectDoc,
            releaseDoc: releaseDoc,
            existingBeats: existingBeats,
            existingFeaturesByBeat: existingFeaturesByBeat,
            deferredByBeatIndex: deferredByBeatIndex,
          );
    if (workingBp == null) return null;

    // Pass 1 (0ms Deterministic Section 1): Seed `1. Choose v0.X Focus`, `GOAL`, `END GOAL`, & 3 Epic Option Cards
    final epicCards = epicFocusOptionsForBlueprint(workingBp);
    final recCard = epicCards.isNotEmpty ? epicCards.first : null;
    final rawTargetEpicIdx = releaseDoc.sections['targetEpicIndex'];
    final isAgentReasoned = releaseDoc.sections['agentReasoned'] == 'true';
    final explicitIdx = !isAgentReasoned && rawTargetEpicIdx != null
        ? int.tryParse(rawTargetEpicIdx)
        : null;
    final targetEpicIndices = (explicitIdx != null &&
            explicitIdx >= 0 &&
            explicitIdx < existingBeats.length)
        ? <int>[explicitIdx]
        : (recCard != null && recCard.targetBeatIndices.isNotEmpty
            ? recCard.targetBeatIndices
            : <int>[0]);

    if (recCard != null) {
      workingBp.releaseTitle = '$verTag: ${recCard.blufHeadline}';
      releaseDoc.title = workingBp.releaseTitle;
      workingBp.goal = '${recCard.blufHeadline} — ${recCard.blufDetail}';
      workingBp.doneWhen = recCard.causalDoneWhen;
      workingBp.questions = [
        AgentQuestion(
          id: 'rel_q_1',
          question: 'Which available Epics should $verTag build?',
          options: [
            for (final c in epicCards)
              '${c.isRecommended ? "(Recommended) " : ""}${c.title}: ${c.subtitle}',
          ],
        ),
      ];
    }
    workingBp.missingGaps = [
      for (final idx in targetEpicIndices)
        if (idx >= 0 && idx < existingBeats.length)
          'E${(idx + 1).toString().padLeft(2, '0')}: Complete ${existingBeats[idx].title} for ${_currentPhase.shortName}',
    ];

    if (!isBackgroundPrewarm) {
      _releaseBlueprint = workingBp;
      _isSynthesizingProgressiveFocus = false;
      _synthesizingProgressiveBeatId = null;
      _queuedProgressiveBeatIds.clear();
      for (final idx in targetEpicIndices) {
        if (idx >= 0 && idx < workingBp.beats.length) {
          _queuedProgressiveBeatIds.add(workingBp.beats[idx].id);
        }
      }
      notifyListeners();
    }

    // Pass 2 (Epic-by-Epic): Synthesize Section 2 (`2. Epics & Features in v0.X`) one target Epic at a time
    final alreadyPlannedChanges = <String>[];
    for (final bIdx in targetEpicIndices) {
      if (isCancelled()) return null;
      if (bIdx < 0 ||
          bIdx >= existingBeats.length ||
          bIdx >= workingBp.beats.length) {
        continue;
      }
      final eb = existingBeats[bIdx];
      final eCode = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      if (!isBackgroundPrewarm) {
        _queuedProgressiveBeatIds.remove(eb.id);
        _synthesizingProgressiveBeatId = eb.id;
        _agentProgressStep = 'Synthesizing $eCode (${eb.title}) upgrades…';
        notifyListeners();
      }

      final beatExistingFeatures =
          existingFeaturesByBeat[eb.id] ?? const <TierDocument>[];
      final updatedBeat = await ReleasePlannerAgent.planProgressiveEpicChanges(
        projectDoc: projectDoc,
        releaseDoc: releaseDoc,
        epicDoc: eb,
        epicIndex: bIdx,
        totalEpicsCount: existingBeats.length,
        existingFeaturesInEpic: beatExistingFeatures,
        queuedDeferredInEpic:
            deferredByBeatIndex[bIdx] ?? const <ProposedFeatureBlueprint>[],
        section1Goal: workingBp.goal,
        section1DoneWhen: workingBp.doneWhen,
        missingGaps: workingBp.missingGaps,
        alreadyPlannedChanges: alreadyPlannedChanges,
        godotCodebaseSummary: buildGodotCodebaseSummaryForPlanner(
          featureIds: beatExistingFeatures.map((f) => f.id),
        ),
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: 'LOW',
      );
      if (isCancelled()) return null;
      if (updatedBeat != null) {
        workingBp.beats[bIdx] = updatedBeat;
        for (final f in updatedBeat.features) {
          if (!f.isStable && !f.isSuperseded) {
            alreadyPlannedChanges.add(f.title);
          }
        }
        if (!isBackgroundPrewarm) {
          _injectDueScheduledInboxItemsIntoBlueprint(workingBp, _currentPhase);
          notifyListeners();
        }
      }
    }

    if (!isBackgroundPrewarm) {
      _synthesizingProgressiveBeatId = null;
      _queuedProgressiveBeatIds.clear();
    }

    final hasAnyActiveChange = workingBp.beats.any(
      (b) => b.features.any((f) => !f.isStable && !f.isSuperseded),
    );
    if (!hasAnyActiveChange) return null;
    final refreshedCards = epicFocusOptionsForBlueprint(workingBp);
    if (refreshedCards.isNotEmpty) {
      final refreshedRec = refreshedCards.first;
      workingBp.goal =
          '${refreshedRec.blufHeadline} — ${refreshedRec.blufDetail}';
      workingBp.doneWhen = refreshedRec.causalDoneWhen;
    }
    return workingBp;
  }

  /// Sends a user turn in the Stage 2 Release Plan Gate Chat to refine Beats, Features, or Scope.
  Future<void> sendReleasePlanChatMessage(String message) async {
    final bp = _releaseBlueprint;
    if (bp == null || message.trim().isEmpty) return;

    _isAgentBusy = true;
    _agentProgressStep =
        'Refining Release Plan ($_conversationModel)...';
    notifyListeners();

    try {
      final ok = await ReleasePlannerAgent.sendReleasePlanChatTurn(
        blueprint: bp,
        userMessage: message,
        projectDoc: activeProject,
        apiKey: _apiKey,
        modelName: _conversationModel,
        thinkingLevel: _thinkingLevel,
      );
      if (ok) {
        _injectDueScheduledInboxItemsIntoBlueprint(bp, _currentPhase);
        final relDoc = activeRelease;
        if (relDoc != null) {
          if (bp.releaseTitle.trim().isNotEmpty &&
              bp.releaseTitle != relDoc.title) {
            relDoc.title = bp.releaseTitle;
          }
          relDoc.sections['release_blueprint_json'] = jsonEncode(bp.toJson());
          _persistDocument(relDoc);
        }
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
                    tasks: ReleasePlannerAgent.defaultDockStepTitles(),
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

  /// Toggles an existing Feature in the Progressive Release Planner between `SUPERSEDED` (archived testbed)
  /// and `STABLE ✓` / `UPGRADE`.
  void toggleProposedFeatureSuperseded(
    String beatId,
    String featureId,
  ) {
    final bp = _releaseBlueprint;
    if (bp == null) return;
    for (final beat in bp.beats) {
      if (beat.id == beatId) {
        for (final feat in beat.features) {
          if (feat.id == featureId) {
            if (feat.lifecycle == FeatureLifecycleStatus.superseded) {
              feat.lifecycle = FeatureLifecycleStatus.stable;
              feat.included = true;
              feat.estimatedHours = 0;
            } else {
              feat.lifecycle = FeatureLifecycleStatus.superseded;
              feat.included = false;
              feat.estimatedHours = 0;
            }
            // Sync live document if already built
            final liveDoc = documents[featureId];
            if (liveDoc != null && liveDoc.tier == TierType.feature) {
              liveDoc.sections['lifecycle'] = feat.lifecycle.name;
              if (feat.lifecycle == FeatureLifecycleStatus.superseded) {
                liveDoc.sections['supersededInVersion'] = bp.releaseVersionTag;
              } else {
                liveDoc.sections.remove('supersededInVersion');
              }
              _persistDocument(liveDoc);
            }
            _syncActiveProjectMetadata();
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  /// 1-Click Feature Pivot / Supersede (`01 Prototype` -> `02 MVP`+):
  /// Archives a live Feature into `Superseded Testbeds Archive` (`FeatureLifecycleStatus.superseded`)
  /// when a playtest proves the mechanic should be cut/pivoted, or restores an archived Feature back into active scope.
  bool toggleSupersedeFeature(
    String featureId, {
    String? pivotReason,
  }) {
    final featDoc = documents[featureId];
    if (featDoc == null || featDoc.tier != TierType.feature) return false;
    final activeVer = activeReleaseVersionTag;
    final wasSuperseded =
        featDoc.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name;

    if (wasSuperseded) {
      final originVer = (featDoc.sections['originVersion'] ?? activeVer).trim();
      final restoredLifecycle = originVer == activeVer
          ? FeatureLifecycleStatus.newFeature
          : FeatureLifecycleStatus.upgrade;
      featDoc.sections['lifecycle'] = restoredLifecycle.name;
      featDoc.sections['activeReleaseVersion'] = activeVer;
      featDoc.sections.remove('supersededInVersion');
      featDoc.sections.remove('pivotReason');
      featDoc.sections.remove('pivot_reason');
      _persistDocument(featDoc);

      final parentBeatId = featDoc.parentId;
      if (parentBeatId != null) {
        final beatDoc = documents[parentBeatId];
        if (beatDoc != null && !beatDoc.childrenIds.contains(featureId)) {
          beatDoc.childrenIds.add(featureId);
          _persistDocument(beatDoc);
        }
      }

      final bp = _releaseBlueprint;
      if (bp != null) {
        for (final b in bp.beats) {
          for (final f in b.features) {
            if (f.id == featureId ||
                f.title.toLowerCase().trim() ==
                    featDoc.title.toLowerCase().trim()) {
              f.lifecycle = restoredLifecycle;
              f.included = true;
              if (f.estimatedHours <= 0) f.estimatedHours = 4;
            }
          }
        }
      }

      if (_releaseViewFilter == 'archived' && supersededFeatures.isEmpty) {
        _releaseViewFilter = 'active';
        _selectedFeatureId = featureId;
        if (featDoc.parentId != null) {
          _selectedBeatId = featDoc.parentId;
        }
      }
    } else {
      featDoc.sections['lifecycle'] = FeatureLifecycleStatus.superseded.name;
      featDoc.sections['supersededInVersion'] = activeVer;
      if (pivotReason != null && pivotReason.trim().isNotEmpty) {
        final cleanReason = pivotReason.trim();
        featDoc.sections['pivotReason'] = cleanReason;
        featDoc.sections['pivot_reason'] = cleanReason;
      }
      _persistDocument(featDoc);

      final bp = _releaseBlueprint;
      if (bp != null) {
        for (final b in bp.beats) {
          for (final f in b.features) {
            if (f.id == featureId ||
                f.title.toLowerCase().trim() ==
                    featDoc.title.toLowerCase().trim()) {
              f.lifecycle = FeatureLifecycleStatus.superseded;
              f.included = false;
              f.estimatedHours = 0;
            }
          }
        }
      }

      if (_selectedFeatureId == featureId && _releaseViewFilter != 'archived') {
        _selectFirstIncompleteFeatureInActiveRelease();
      }
    }

    _syncActiveProjectMetadata();
    notifyListeners();
    return !wasSuperseded;
  }

  /// Adds a custom `+ NEW` feature to a Beat inside the Progressive Release Planner (`_releaseBlueprint`).
  ProposedFeatureBlueprint? addCustomFeatureToProposedBeat(
    String beatId,
    String rawTitle, {
    String? customGoal,
  }) {
    final bp = _releaseBlueprint;
    final cleanTitle =
        rawTitle.replaceFirst(WorkbenchReleaseMixin._noPrefixRegex, '').trim();
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
              tasks: ReleasePlannerAgent.defaultDockStepTitles(),
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
        if (GeminiAgentClient.hasKey(_apiKey) ||
            GeminiAgentClient.testMockResponder != null) {
          _enrichProposedBlueprintFeatureWithAi(
            beatId: beat.id,
            featureId: created.id,
            beatTitle: beat.title,
            preserveCustomGoal:
                customGoal != null && customGoal.trim().isNotEmpty,
          );
        }
        return created;
      }
    }
    return null;
  }
}
