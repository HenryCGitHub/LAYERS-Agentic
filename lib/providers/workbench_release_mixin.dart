part of 'workbench_provider.dart';

/// Stage 2 actions: Release switching, 4-tier Epic -> Feature selection & expansion,
/// live `@export` tuning, Playtest Gate checkboxes, Flag `[FIX]` / Resolve,
/// `addFeatureSlice`, and `passFeature` / `reopenFeature` rollups.
extension WorkbenchReleaseMixin on WorkbenchProvider {
  FeatureSpec? _findFeatureByIdOrCode(EpicSpec spec, String featureIdOrCode) {
    final clean = featureIdOrCode.trim();
    if (clean.isEmpty) return null;
    for (final f in spec.features) {
      if (f.id == clean) return f;
    }
    final lower = clean.toLowerCase();
    for (final f in spec.features) {
      if (f.code.trim().toLowerCase() == lower) return f;
    }
    return null;
  }

  String? _defaultFeatureIdForEpicDoc(
    String? epicId, {
    String? releaseVersion,
    String? preferredId,
    String? preferredCode,
  }) {
    if (epicId == null) return null;
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return null;
    final spec = EpicSpec.fromDocument(doc);
    final ver = releaseVersion ?? activeReleaseVersionTag;
    final visible = visibleFeaturesForEpic(spec, releaseVersion: ver);
    if (visible.isEmpty) return null;
    if (preferredId != null && preferredId.trim().isNotEmpty) {
      for (final f in visible) {
        if (f.id == preferredId.trim()) return f.id;
      }
    }
    if (preferredCode != null && preferredCode.trim().isNotEmpty) {
      final lower = preferredCode.trim().toLowerCase();
      for (final f in visible) {
        if (f.code.trim().toLowerCase() == lower) return f.id;
      }
    }
    for (final f in visible) {
      if (!f.isPassedForRelease(ver)) return f.id;
    }
    return visible.first.id;
  }

  String _releaseVersionForEpicDoc(TierDocument doc, EpicSpec spec) {
    final parentId = doc.parentId;
    if (parentId != null) {
      final parentDoc = documents[parentId];
      if (parentDoc != null && parentDoc.tier == TierType.release) {
        return releaseVersionTagFor(parentDoc);
      }
    }
    final specVer = spec.releaseVersion.trim();
    if (specVer.isNotEmpty) {
      return ReleasePlannerAgent.extractReleaseVersionTag(specVer);
    }
    return activeReleaseVersionTag;
  }

  void _syncEpicLifecycleFromFeatures(EpicSpec spec, String releaseVersion) {
    final visible = visibleFeaturesForEpic(spec, releaseVersion: releaseVersion);
    if (visible.isEmpty) return;
    final hasAnyOpenFixes = spec.openFixes.isNotEmpty ||
        visible.any((f) => f.openFixesCount > 0);
    final allFeaturesPassed = visible.every(
      (f) => f.isPassedForRelease(releaseVersion),
    );
    if (!hasAnyOpenFixes && allFeaturesPassed) {
      spec.lifecycle = EpicLifecycle.stable;
      for (final c in spec.checks) {
        c.passed = true;
      }
    } else if (spec.lifecycle == EpicLifecycle.stable ||
        spec.lifecycle == EpicLifecycle.queued) {
      final relTrimmed = releaseVersion.trim();
      final hasDelta = relTrimmed != 'v0.1' &&
          (spec.upgradeDeltas.isNotEmpty ||
              visible.any((f) => f.releaseDelta.trim().isNotEmpty));
      spec.lifecycle =
          hasDelta ? EpicLifecycle.upgrading : EpicLifecycle.active;
    }
  }

  bool _canEditFeature(FeatureSpec feature, {String? releaseVersion}) =>
      !feature.isLockedBaselineInRelease(
        releaseVersion ?? activeReleaseVersionTag,
      );

  void selectActiveRelease(String releaseId) {
    final rel = documents[releaseId];
    if (rel == null || rel.tier != TierType.release) return;
    final prevEpic = selectedEpicSpec;
    final prevFeat = selectedFeatureSpec;
    final wasDomainSheet = selectedEpicDoc != null && _selectedFeatureId == null;

    _activeReleaseId = rel.id;
    final relVer = releaseVersionTagFor(rel);
    final epics = epicDocsForRelease(rel.id);
    if (epics.isEmpty) {
      _selectedEpicId = null;
      _selectedFeatureId = null;
    } else {
      TierDocument? matchedEpicDoc;
      if (prevEpic != null) {
        final prevLineage = prevEpic.lineageKey.trim().toLowerCase();
        final prevCode = prevEpic.code.trim().toLowerCase();
        for (int i = 0; i < epics.length; i++) {
          final cand = EpicSpec.fromDocument(epics[i], indexHint: i);
          if ((prevLineage.isNotEmpty &&
                  cand.lineageKey.trim().toLowerCase() == prevLineage) ||
              (prevCode.isNotEmpty &&
                  cand.code.trim().toLowerCase() == prevCode)) {
            matchedEpicDoc = epics[i];
            break;
          }
        }
      }
      matchedEpicDoc ??= epics.firstWhere(
        (d) => !EpicSpec.fromDocument(d).isPassed,
        orElse: () => epics.first,
      );
      _selectedEpicId = matchedEpicDoc.id;
      _expandedEpicIds.add(_selectedEpicId!);
      if (wasDomainSheet && prevEpic != null) {
        _selectedFeatureId = null;
      } else {
        _selectedFeatureId = _defaultFeatureIdForEpicDoc(
          _selectedEpicId,
          releaseVersion: relVer,
          preferredId: prevFeat?.id,
          preferredCode: prevFeat?.code,
        );
      }
    }
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  void openSelectedFeatureInBaselineRelease() {
    final feat = selectedFeatureSpec;
    final epic = selectedEpicSpec;
    final targetTag = (feat?.introducedIn ?? 'v0.1').trim().toLowerCase();
    TierDocument? targetRel;
    for (final rel in projectReleases) {
      if (releaseVersionTagFor(rel).toLowerCase() == targetTag) {
        targetRel = rel;
        break;
      }
    }
    targetRel ??= v01BaselineRelease;
    if (targetRel == null) return;
    selectActiveRelease(targetRel.id);
    if (feat != null && epic != null) {
      final targetEpics = epicDocsForRelease(targetRel.id);
      final targetLineage = epic.lineageKey.trim().toLowerCase();
      final targetCode = epic.code.trim().toLowerCase();
      for (int i = 0; i < targetEpics.length; i++) {
        final cand = EpicSpec.fromDocument(targetEpics[i], indexHint: i);
        if ((targetLineage.isNotEmpty &&
                cand.lineageKey.trim().toLowerCase() == targetLineage) ||
            (targetCode.isNotEmpty &&
                cand.code.trim().toLowerCase() == targetCode)) {
          final matchFeat = cand.features.firstWhere(
            (f) =>
                f.id == feat.id ||
                f.code.trim().toLowerCase() == feat.code.trim().toLowerCase(),
            orElse: () => feat,
          );
          selectFeature(targetEpics[i].id, matchFeat.id);
          return;
        }
      }
    }
  }

  void selectEpic(String epicId, {bool openDomainSheet = true}) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return;
    if (doc.parentId != null && doc.parentId != _activeReleaseId) {
      _activeReleaseId = doc.parentId;
    }
    _selectedEpicId = epicId;
    _expandedEpicIds.add(epicId);
    if (openDomainSheet) {
      _selectedFeatureId = null;
    }
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  void selectFeature(String epicId, String featureId) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return;
    if (doc.parentId != null && doc.parentId != _activeReleaseId) {
      _activeReleaseId = doc.parentId;
    }
    _selectedEpicId = epicId;
    _expandedEpicIds.add(epicId);
    final spec = EpicSpec.fromDocument(doc);
    final visible = visibleFeaturesForEpic(spec);
    FeatureSpec? match;
    for (final f in visible) {
      if (f.id == featureId ||
          f.code.trim().toLowerCase() == featureId.trim().toLowerCase()) {
        match = f;
        break;
      }
    }
    match ??= _findFeatureByIdOrCode(spec, featureId);
    _selectedFeatureId = match?.id;
    _syncActiveProjectMetadata();
    notifyListeners();
  }

  void toggleEpicExpanded(String epicId, [bool? expanded]) {
    final next = expanded ?? !_expandedEpicIds.contains(epicId);
    if (next) {
      _expandedEpicIds.add(epicId);
    } else {
      _expandedEpicIds.remove(epicId);
    }
    notifyListeners();
  }

  void _updateAndPersistEpic(
    String epicId,
    void Function(EpicSpec spec) mutate, {
    bool debounce = false,
  }) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return;
    final idx = activeReleaseEpicDocs.indexWhere((d) => d.id == epicId);
    final spec = EpicSpec.fromDocument(doc, indexHint: idx >= 0 ? idx : 0);
    mutate(spec);
    final updatedDoc = spec.applyToDocument(doc);
    documents[epicId] = updatedDoc;
    _persistDocument(updatedDoc, debounce: debounce);
    notifyListeners();
  }

  bool _updateAndPersistFeature(
    String epicId,
    String featureId,
    void Function(EpicSpec spec, FeatureSpec feat, String relVer) mutate, {
    bool debounce = false,
    bool requireUnlocked = true,
  }) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return false;
    final idx = activeReleaseEpicDocs.indexWhere((d) => d.id == epicId);
    final spec = EpicSpec.fromDocument(doc, indexHint: idx >= 0 ? idx : 0);
    final relVer = _releaseVersionForEpicDoc(doc, spec);
    final feat = _findFeatureByIdOrCode(spec, featureId);
    if (feat == null) return false;
    if (requireUnlocked && !_canEditFeature(feat, releaseVersion: relVer)) {
      return false;
    }
    mutate(spec, feat, relVer);
    final updatedDoc = spec.applyToDocument(doc);
    documents[epicId] = updatedDoc;
    _persistDocument(updatedDoc, debounce: debounce);
    notifyListeners();
    return true;
  }

  void updateFeatureTuningParam(
    String epicId,
    String featureId,
    int paramIndex,
    String newValue,
  ) {
    final cleanVal = newValue.trim();
    _updateAndPersistFeature(
      epicId,
      featureId,
      (spec, feat, _) {
        if (paramIndex < 0 || paramIndex >= feat.tuning.length) return;
        final param = feat.tuning[paramIndex];
        param.value = cleanVal;
        for (final parentParam in spec.tuning) {
          if (parentParam.key.trim().toLowerCase() ==
              param.key.trim().toLowerCase()) {
            parentParam.value = cleanVal;
          }
        }
      },
      debounce: true,
    );
  }

  void addFeatureTuningParam(
    String epicId,
    String featureId, {
    required String key,
    required String value,
    required String unit,
  }) {
    final cleanKey = GodotSpecGuard.sanitizeTuningKey(key, fallback: '');
    if (cleanKey.isEmpty) return;
    final dim = projectDimension;
    _updateAndPersistFeature(epicId, featureId, (spec, feat, _) {
      final nextVal = value.trim().isEmpty ? '0' : value.trim();
      final nextUnit = GodotSpecGuard.normalizeGodotUnit(
        cleanKey,
        unit,
        dimension: dim,
      );
      final existingIdx = feat.tuning.indexWhere(
        (t) => t.key.trim().toLowerCase() == cleanKey.toLowerCase(),
      );
      if (existingIdx >= 0) {
        final existing = feat.tuning[existingIdx];
        existing.value = nextVal;
        existing.unit = unit.trim().isEmpty ? existing.unit : nextUnit;
      } else {
        feat.tuning.add(
          EpicTuningParam(
            key: cleanKey,
            value: nextVal,
            unit: nextUnit,
          ),
        );
      }
      for (final parentParam in spec.tuning) {
        if (parentParam.key.trim().toLowerCase() == cleanKey.toLowerCase()) {
          parentParam.value = nextVal;
          parentParam.unit = nextUnit;
        }
      }
    });
  }

  void updateFeatureSections(
    String epicId,
    String featureId, {
    String? title,
    String? goal,
    String? sliceTime,
  }) {
    final dim = projectDimension;
    _updateAndPersistFeature(
      epicId,
      featureId,
      (_, feat, __) {
        if (title != null && title.trim().isNotEmpty) {
          feat.title = GodotSpecGuard.sanitizeLine(title, dimension: dim);
        }
        if (goal != null) {
          feat.goal = GodotSpecGuard.sanitizeLine(goal, dimension: dim);
        }
        if (sliceTime != null && sliceTime.trim().isNotEmpty) {
          feat.sliceTime = sliceTime.trim();
        }
      },
      debounce: true,
    );
  }

  void toggleFeatureCheck(
    String epicId,
    String featureId,
    String checkId, [
    bool? value,
  ]) {
    _updateAndPersistFeature(epicId, featureId, (spec, feat, relVer) {
      bool matched = false;
      for (final c in feat.effectiveChecksForRelease(relVer)) {
        if (c.id == checkId) {
          c.passed = value ?? !c.passed;
          matched = true;
          if (value == null) break;
        }
      }
      if (!matched) return;
      final allEffPassed = feat.allEffectiveChecksPassedForRelease(relVer);
      if (feat.status == FeatureStatus.queued) {
        feat.status = FeatureStatus.active;
      } else if (feat.status == FeatureStatus.passed && !allEffPassed) {
        feat.status = FeatureStatus.active;
      }
      _syncEpicLifecycleFromFeatures(spec, relVer);
    });
  }

  void flagFeatureFix(String epicId, String featureId, String fixText) {
    final clean = fixText.trim();
    if (clean.isEmpty) return;
    final dim = projectDimension;
    _updateAndPersistFeature(epicId, featureId, (spec, feat, relVer) {
      feat.fixes.add(
        EpicPieFix(
          id: 'fix_${DateTime.now().microsecondsSinceEpoch}',
          text: GodotSpecGuard.sanitizeLine(clean, dimension: dim),
          resolved: false,
        ),
      );
      feat.status = FeatureStatus.active;
      _syncEpicLifecycleFromFeatures(spec, relVer);
    });
  }

  void resolveFeatureFix(
    String epicId,
    String featureId,
    String fixId, {
    bool resolved = true,
  }) {
    _updateAndPersistFeature(epicId, featureId, (spec, feat, relVer) {
      for (final f in feat.fixes) {
        if (f.id == fixId) {
          f.resolved = resolved;
          break;
        }
      }
      if (!resolved) {
        feat.status = FeatureStatus.active;
      }
      _syncEpicLifecycleFromFeatures(spec, relVer);
    });
  }

  void deleteFeatureFix(String epicId, String featureId, String fixId) {
    _updateAndPersistFeature(epicId, featureId, (spec, feat, relVer) {
      feat.fixes.removeWhere((f) => f.id == fixId);
      _syncEpicLifecycleFromFeatures(spec, relVer);
    });
  }

  FeatureSpec? addFeatureSlice(
    String epicId, {
    required String title,
    required String goal,
    String sliceTime = '45 min',
    bool selectCreated = true,
  }) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return null;
    final dim = projectDimension;
    final cleanTitle = GodotSpecGuard.sanitizeLine(title, dimension: dim);
    final cleanGoal = GodotSpecGuard.sanitizeLine(goal, dimension: dim);
    if (cleanTitle.isEmpty || cleanGoal.isEmpty) return null;

    int maxNum = 0;
    int totalCount = 0;
    final usedCodesLower = <String>{};
    final codeRx = RegExp(r'^F(\d+)$', caseSensitive: false);
    final allEpics = <EpicSpec>[
      for (final rel in projectReleases)
        for (final epDoc in epicDocsForRelease(rel.id))
          EpicSpec.fromDocument(epDoc),
    ];
    for (final ep in (allEpics.isNotEmpty ? allEpics : activeReleaseEpics)) {
      for (final f in ep.features) {
        totalCount++;
        final cClean = f.code.trim();
        if (cClean.isNotEmpty) {
          usedCodesLower.add(cClean.toLowerCase());
        }
        final m = codeRx.firstMatch(cClean);
        if (m != null) {
          final parsed = int.tryParse(m.group(1) ?? '') ?? 0;
          if (parsed > maxNum) maxNum = parsed;
        }
      }
    }
    var nextNum = (maxNum > 0 ? maxNum : totalCount) + 1;
    while (usedCodesLower.contains(FeatureSpec.formatCode(nextNum).toLowerCase())) {
      nextNum++;
    }
    final nextCode = FeatureSpec.formatCode(nextNum);
    final relVer = activeReleaseVersionTag;
    final featId = '${epicId}_f_${DateTime.now().microsecondsSinceEpoch}';
    final is2d = dim == GodotProjectDimension.dim2d;
    final rawCreated = FeatureSpec(
      id: featId,
      code: nextCode,
      title: cleanTitle,
      introducedIn: relVer,
      sliceTime: sliceTime.trim().isEmpty ? '45 min' : sliceTime.trim(),
      status: FeatureStatus.active,
      goal: cleanGoal,
      inScope: [cleanTitle],
      doneWhen: [
        'Trigger $cleanTitle in playtest -> Expected scene response runs cleanly',
      ],
      controls: [
        EpicControlBinding(
          action: 'primary_action',
          trigger: 'Just Pressed (Space / LMB)',
          rule: 'Triggers $cleanTitle cleanly',
        ),
      ],
      tuning: [
        EpicTuningParam(
          key: 'slice_magnitude',
          value: is2d ? '80' : '2.5',
          unit: dim.distanceUnit,
        ),
      ],
      cues: ['Visual feedback pulse + crisp activation audio cue'],
      checks: [
        EpicPieCheck(
          id: '${featId}_c1',
          text:
              'Activate $cleanTitle -> Observable response behaves cleanly in playtest',
        ),
      ],
    );
    final sanitized = GodotSpecGuard.sanitizeFeatureSpec(
      rawCreated,
      dimension: dim,
      forceCode: nextCode,
    );
    sanitized.code = nextCode;
    sanitized.introducedIn = relVer;
    sanitized.status = FeatureStatus.active;

    _updateAndPersistEpic(epicId, (spec) {
      spec.features.add(sanitized);
      _syncEpicLifecycleFromFeatures(spec, relVer);
    });
    if (selectCreated) {
      _selectedEpicId = epicId;
      _expandedEpicIds.add(epicId);
      _selectedFeatureId = sanitized.id;
      _syncActiveProjectMetadata();
      notifyListeners();
    }
    return sanitized;
  }

  bool canPassFeature(FeatureSpec feature, {String? releaseVersion}) {
    final ver = releaseVersion ?? activeReleaseVersionTag;
    if (feature.isLockedBaselineInRelease(ver)) return false;
    if (feature.openFixes.isNotEmpty) return false;
    final eff = feature.effectiveChecksForRelease(ver);
    if (eff.isNotEmpty && eff.any((c) => !c.passed)) return false;
    return true;
  }

  bool passFeature(
    String epicId,
    String featureId, {
    bool forceResolve = false,
  }) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return false;
    final spec = EpicSpec.fromDocument(doc);
    final relVer = _releaseVersionForEpicDoc(doc, spec);
    final target = _findFeatureByIdOrCode(spec, featureId);
    if (target == null || !_canEditFeature(target, releaseVersion: relVer)) {
      return false;
    }
    if (!forceResolve && !canPassFeature(target, releaseVersion: relVer)) {
      return false;
    }

    final saved = _updateAndPersistFeature(epicId, target.id, (epSpec, feat, docRelVer) {
      if (forceResolve) {
        for (final fx in feat.fixes) {
          fx.resolved = true;
        }
        for (final c in feat.effectiveChecksForRelease(docRelVer)) {
          c.passed = true;
        }
      }
      feat.status = FeatureStatus.passed;
      _syncEpicLifecycleFromFeatures(epSpec, docRelVer);
    });
    if (!saved) return false;

    selectNextOpenFeature(
      startingAfterEpicId: epicId,
      startingAfterFeatureId: target.id,
    );
    return true;
  }

  void reopenFeature(String epicId, String featureId) {
    _updateAndPersistFeature(epicId, featureId, (spec, feat, relVer) {
      feat.status = FeatureStatus.active;
      final hasDelta = relVer != 'v0.1' &&
          feat.releaseDelta.trim().isNotEmpty &&
          feat.releaseDeltaChecks.isNotEmpty;
      if (hasDelta) {
        for (final c in feat.releaseDeltaChecks) {
          c.passed = false;
        }
      } else {
        for (final c in feat.checks) {
          c.passed = false;
        }
      }
      if (spec.lifecycle == EpicLifecycle.stable) {
        if (relVer != 'v0.1' && spec.upgradeDeltas.isNotEmpty) {
          final verLower = relVer.toLowerCase();
          for (final c in spec.checks) {
            final t = c.text.trim().toLowerCase();
            if (c.id.contains('_delta_') ||
                t.startsWith('verify $verLower delta')) {
              c.passed = false;
            }
          }
        } else {
          for (final c in spec.checks) {
            c.passed = false;
          }
        }
      }
      _syncEpicLifecycleFromFeatures(spec, relVer);
    });
  }

  bool selectNextOpenFeature({
    String? startingAfterEpicId,
    String? startingAfterFeatureId,
  }) {
    final epics = activeReleaseEpics;
    if (epics.isEmpty) return false;
    final relVer = activeReleaseVersionTag;
    final flat = <({String epicId, FeatureSpec feat})>[];
    for (final ep in epics) {
      for (final f in visibleFeaturesForEpic(ep, releaseVersion: relVer)) {
        flat.add((epicId: ep.id, feat: f));
      }
    }
    if (flat.isEmpty) return false;

    int startIdx = 0;
    if (startingAfterEpicId != null && startingAfterFeatureId != null) {
      final foundIdx = flat.indexWhere(
        (pair) =>
            pair.epicId == startingAfterEpicId &&
            pair.feat.id == startingAfterFeatureId,
      );
      if (foundIdx >= 0) {
        startIdx = (foundIdx + 1) % flat.length;
      }
    }

    for (int offset = 0; offset < flat.length; offset++) {
      final pair = flat[(startIdx + offset) % flat.length];
      if (!pair.feat.isPassedForRelease(relVer)) {
        _selectedEpicId = pair.epicId;
        _expandedEpicIds.add(pair.epicId);
        _selectedFeatureId = pair.feat.id;
        _syncActiveProjectMetadata();
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void togglePieCheck(String epicId, String checkId, [bool? value]) {
    _updateAndPersistEpic(epicId, (spec) {
      for (final c in spec.checks) {
        if (c.id == checkId) {
          c.passed = value ?? !c.passed;
          break;
        }
      }
      final anyUnchecked = spec.checks.any((c) => !c.passed);
      if (spec.lifecycle == EpicLifecycle.queued) {
        spec.lifecycle = EpicLifecycle.active;
      } else if (spec.lifecycle == EpicLifecycle.stable && anyUnchecked) {
        spec.lifecycle = spec.upgradeDeltas.isNotEmpty
            ? EpicLifecycle.upgrading
            : EpicLifecycle.active;
      }
    });
  }

  void updateEpicTuningParam(String epicId, int paramIndex, String newValue) {
    _updateAndPersistEpic(
      epicId,
      (spec) {
        if (paramIndex >= 0 && paramIndex < spec.tuning.length) {
          spec.tuning[paramIndex].value = newValue.trim();
        }
      },
      debounce: true,
    );
  }

  void addEpicTuningParam(
    String epicId, {
    required String key,
    required String value,
    required String unit,
  }) {
    final cleanKey = GodotSpecGuard.sanitizeTuningKey(key, fallback: '');
    if (cleanKey.isEmpty) return;
    final dim = projectDimension;
    _updateAndPersistEpic(epicId, (spec) {
      final nextVal = value.trim().isEmpty ? '0' : value.trim();
      final existingIdx = spec.tuning.indexWhere(
        (t) => t.key.trim().toLowerCase() == cleanKey.toLowerCase(),
      );
      if (existingIdx >= 0) {
        final existing = spec.tuning[existingIdx];
        existing.value = nextVal;
        existing.unit = GodotSpecGuard.normalizeGodotUnit(
          existing.key,
          unit.trim().isEmpty ? existing.unit : unit,
          dimension: dim,
        );
      } else {
        spec.tuning.add(
          EpicTuningParam(
            key: cleanKey,
            value: nextVal,
            unit: GodotSpecGuard.normalizeGodotUnit(
              cleanKey,
              unit,
              dimension: dim,
            ),
          ),
        );
      }
    });
  }

  void updateEpicSections(
    String epicId, {
    String? title,
    String? goal,
    String? levelStaging,
  }) {
    final dim = projectDimension;
    _updateAndPersistEpic(
      epicId,
      (spec) {
        if (title != null && title.trim().isNotEmpty) {
          spec.title = GodotSpecGuard.sanitizeLine(title, dimension: dim);
        }
        if (goal != null) {
          spec.goal = GodotSpecGuard.sanitizeLine(goal, dimension: dim);
        }
        if (levelStaging != null) {
          spec.levelStaging = GodotSpecGuard.sanitizeLine(
            levelStaging,
            dimension: dim,
          );
        }
      },
      debounce: true,
    );
  }

  void flagEpicFix(String epicId, String fixText) {
    final clean = fixText.trim();
    if (clean.isEmpty) return;
    final dim = projectDimension;
    _updateAndPersistEpic(epicId, (spec) {
      spec.fixes.add(
        EpicPieFix(
          id: 'fix_${DateTime.now().microsecondsSinceEpoch}',
          text: GodotSpecGuard.sanitizeLine(clean, dimension: dim),
          resolved: false,
        ),
      );
      if (spec.lifecycle == EpicLifecycle.stable ||
          spec.lifecycle == EpicLifecycle.queued) {
        spec.lifecycle = spec.upgradeDeltas.isNotEmpty
            ? EpicLifecycle.upgrading
            : EpicLifecycle.active;
      }
    });
  }

  void resolveEpicFix(String epicId, String fixId, {bool resolved = true}) {
    _updateAndPersistEpic(epicId, (spec) {
      for (final f in spec.fixes) {
        if (f.id == fixId) {
          f.resolved = resolved;
          break;
        }
      }
    });
  }

  void deleteEpicFix(String epicId, String fixId) {
    _updateAndPersistEpic(epicId, (spec) {
      spec.fixes.removeWhere((f) => f.id == fixId);
    });
  }

  void passActiveEpic(String epicId) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return;
    _updateAndPersistEpic(epicId, (spec) {
      final relVer = _releaseVersionForEpicDoc(doc, spec);
      for (final f in spec.fixes) {
        f.resolved = true;
      }
      for (final c in spec.checks) {
        c.passed = true;
      }
      for (final feat in spec.features) {
        if (feat.isLockedBaselineInRelease(relVer)) continue;
        for (final fx in feat.fixes) {
          fx.resolved = true;
        }
        for (final c in feat.effectiveChecksForRelease(relVer)) {
          c.passed = true;
        }
        feat.status = FeatureStatus.passed;
      }
      spec.lifecycle = EpicLifecycle.stable;
    });
    selectNextUnfinishedEpic();
  }

  void reopenEpic(String epicId) {
    final doc = documents[epicId];
    if (doc == null || doc.tier != TierType.epic) return;
    final initialSpec = EpicSpec.fromDocument(doc);
    final relVer = _releaseVersionForEpicDoc(doc, initialSpec);
    final visible = visibleFeaturesForEpic(initialSpec, releaseVersion: relVer);
    if (initialSpec.upgradeDeltas.isEmpty &&
        visible.isNotEmpty &&
        visible.every((f) => f.isLockedBaselineInRelease(relVer))) {
      return;
    }
    _updateAndPersistEpic(epicId, (spec) {
      if (relVer != 'v0.1' && spec.upgradeDeltas.isNotEmpty) {
        spec.lifecycle = EpicLifecycle.upgrading;
        final verLower = relVer.toLowerCase();
        final deltaChecks = spec.checks.where((c) {
          final t = c.text.trim().toLowerCase();
          return c.id.contains('_delta_') ||
              (verLower.isNotEmpty
                  ? t.startsWith('verify $verLower delta')
                  : t.contains('delta:'));
        }).toList();
        if (deltaChecks.isNotEmpty) {
          for (final c in deltaChecks) {
            c.passed = false;
          }
        } else {
          for (final c in spec.checks) {
            c.passed = false;
          }
        }
        for (final feat in spec.features) {
          if (feat.isLockedBaselineInRelease(relVer)) continue;
          feat.status = FeatureStatus.active;
          if (feat.releaseDeltaChecks.isNotEmpty) {
            for (final c in feat.releaseDeltaChecks) {
              c.passed = false;
            }
          } else if (feat.introducedIn.trim() == relVer) {
            for (final c in feat.checks) {
              c.passed = false;
            }
          }
        }
      } else {
        spec.lifecycle = EpicLifecycle.active;
        for (final c in spec.checks) {
          c.passed = false;
        }
        for (final feat in spec.features) {
          if (feat.isLockedBaselineInRelease(relVer)) continue;
          feat.status = FeatureStatus.active;
          for (final c in feat.checks) {
            c.passed = false;
          }
        }
      }
    });
  }

  void selectNextUnfinishedEpic() {
    final epics = activeReleaseEpics;
    if (epics.isEmpty) return;
    for (final ep in epics) {
      if (!ep.isPassed) {
        _selectedEpicId = ep.id;
        _expandedEpicIds.add(ep.id);
        _selectedFeatureId = _defaultFeatureIdForEpicDoc(ep.id);
        _syncActiveProjectMetadata();
        notifyListeners();
        return;
      }
    }
  }
}
