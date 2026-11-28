import '../constants/text_style_guide.dart';
import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import '../utils/unreal_spec_guard.dart';

bool hasRootV02Cache(ProjectConceptBlueprint rootSpec) {
  return rootSpec.v02NewPool.isNotEmpty ||
      rootSpec.v02UpgradesByLineageKey.isNotEmpty ||
      rootSpec.v02NewFeaturesByLineageKey.isNotEmpty;
}

String resolveEpicLineageKey(
  String rawKeyOriginal,
  List<EpicSpec> currentEpics,
) {
  final cleanOrig = rawKeyOriginal.trim();
  final rawKey = cleanOrig.toLowerCase();
  if (rawKey.isEmpty) return '';
  EpicSpec? matched = currentEpics
      .where((ep) => ep.lineageKey.trim().toLowerCase() == rawKey)
      .firstOrNull;
  matched ??= currentEpics
      .where((ep) => ep.code.trim().toLowerCase() == rawKey)
      .firstOrNull;
  matched ??= currentEpics
      .where((ep) => ep.id.trim().toLowerCase() == rawKey)
      .firstOrNull;
  matched ??= currentEpics
      .where((ep) => ep.title.trim().toLowerCase() == rawKey)
      .firstOrNull;
  return matched != null ? matched.lineageKey.trim().toLowerCase() : '';
}

ProgressiveReleaseDraft draftFromRootCache(
  ProjectConceptBlueprint rootSpec,
  List<EpicSpec> currentEpics,
  String targetVersion,
) {
  final upgrades = <String, List<EpicUpgradeOption>>{};
  final newFeatures = <String, List<FeatureSpec>>{};
  final featureCodes = FeatureCodeAllocator(currentEpics);

  for (final ep in currentEpics) {
    final key = ep.lineageKey.toLowerCase();
    final cached = rootSpec.v02UpgradesByLineageKey[key];
    if (cached != null && cached.isNotEmpty) {
      upgrades[key] = [for (final u in cached) u.copyWith()];
    }
    final cachedNewFeats = rootSpec.v02NewFeaturesByLineageKey[key];
    if (cachedNewFeats != null && cachedNewFeats.isNotEmpty) {
      newFeatures[key] = [
        for (final f in cachedNewFeats)
          () {
            final copy = f.deepCopy()..introducedIn = targetVersion;
            copy.code = featureCodes.allocate(copy.code);
            return copy;
          }(),
      ];
    }
  }
  final newPool = [
    for (final ep in rootSpec.v02NewPool)
      () {
        final copy = ep.deepCopy(
          releaseVersionOverride: targetVersion,
          lifecycleOverride: EpicLifecycle.newEpic,
        );
        for (final feat in copy.features) {
          feat.introducedIn = targetVersion;
          feat.code = featureCodes.allocate(feat.code);
        }
        return copy;
      }(),
  ];
  final effectivePresets = rootSpec.v02Presets.isNotEmpty
      ? List<ReleaseDirectionPreset>.from(rootSpec.v02Presets)
      : defaultProgressivePresets(upgrades, newFeatures, newPool);
  return ProgressiveReleaseDraft(
    targetVersion: targetVersion,
    presets: effectivePresets,
    upgradesByLineageKey: upgrades,
    candidateNewFeaturesByLineageKey: newFeatures,
    candidateNewEpics: newPool,
    activePresetId:
        effectivePresets.isNotEmpty ? effectivePresets.first.id : null,
  );
}

ProgressiveReleaseDraft buildOfflineProgressiveDraft({
  required ProjectConceptBlueprint rootSpec,
  required List<EpicSpec> currentEpics,
  required String targetVersion,
  required String directionPrompt,
}) {
  if (targetVersion == 'v0.2' &&
      directionPrompt.trim().isEmpty &&
      hasRootV02Cache(rootSpec)) {
    return draftFromRootCache(rootSpec, currentEpics, targetVersion);
  }

  final upgradesByKey = <String, List<EpicUpgradeOption>>{};
  final newFeaturesByKey = <String, List<FeatureSpec>>{};
  final archMode = rootSpec.architectureMode;
  final featureCodes = FeatureCodeAllocator(currentEpics);

  if (currentEpics.isNotEmpty) {
    final firstEpic = currentEpics.first;
    final firstKey = firstEpic.lineageKey.toLowerCase();
    final firstFeatCode = firstEpic.features.isNotEmpty
        ? firstEpic.features.last.code
        : 'F01';
    final newFeatCode = featureCodes.allocate();
    final domainCorpus = <String>[
      rootSpec.sparkPrompt,
      rootSpec.pitch,
      rootSpec.coreLoop.join(' '),
      for (final ep in currentEpics) ...[
        ep.title,
        ep.goal,
        for (final f in ep.features) ...[f.title, f.goal],
      ],
    ].join(' ').toLowerCase();
    final hasCombatCue = RegExp(
      r'\b(?:combat|enemy|enemies|damage|melee|shooter|arena|boss|weapon|brawler|crab|parry|attack|strike|turret)\b',
    ).hasMatch(domainCorpus);
    final hasNonCombatCue = RegExp(
      r'\b(?:parkour|courier|rooftop|parcel|grapple|wall-run|wallrun|racer|drift|puzzle|cozy|runner|obstacle|course|finish\s*gate|checkpoint)\b',
    ).hasMatch(domainCorpus);
    final isNonCombat = !hasCombatCue && hasNonCombatCue;

    upgradesByKey[firstKey] = [
      EpicUpgradeOption(
        id: 'up_${firstKey}_juice',
        targetFeatureCode: firstFeatCode,
        text: isNonCombat
            ? '+Landing momentum camera dip & speed-line burst'
            : '+45ms Hit-Stop impact freeze & camera lag snap',
        chosen: true,
      ),
      EpicUpgradeOption(
        id: 'up_${firstKey}_vfx',
        targetFeatureCode: firstFeatCode,
        text: '+Emissive Niagara trail burst during primary movement action',
      ),
    ];
    newFeaturesByKey[firstKey] = [
      UnrealSpecGuard.sanitizeFeatureSpec(
        isNonCombat
            ? FeatureSpec(
                id: '${firstKey}_${targetVersion}_chain',
                code: newFeatCode,
                title: 'Momentum Vault & Quick Recover',
                introducedIn: targetVersion,
                sliceTime: '45 min',
                status: FeatureStatus.active,
                goal:
                    'Chain a brief $targetVersion speed burst inside ${firstEpic.code} when landing clean obstacle vaults or drops.',
                tuning: [
                  EpicTuningParam(
                    key: 'ChainWindowS',
                    value: '0.35',
                    unit: 's',
                  ),
                  EpicTuningParam(
                    key: 'VaultBoostSpeed',
                    value: '950',
                    unit: 'cm/s',
                  ),
                  EpicTuningParam(
                    key: 'LandingGraceWindowS',
                    value: '0.18',
                    unit: 's',
                  ),
                ],
                checks: [
                  EpicPieCheck(
                    id: 'off_feat_c1',
                    text:
                        'Land clean vault or roll -> Follow-up sprint surges cleanly with zero stall',
                  ),
                ],
              )
            : FeatureSpec(
                id: '${firstKey}_${targetVersion}_chain',
                code: newFeatCode,
                title: 'Counter Impulse & Quick Recover',
                introducedIn: targetVersion,
                sliceTime: '45 min',
                status: FeatureStatus.active,
                goal:
                    'Grant a brief $targetVersion follow-up dash refund inside ${firstEpic.code} when landing clean counters.',
                tuning: [
                  EpicTuningParam(
                    key: 'ChainWindowS',
                    value: '0.35',
                    unit: 's',
                  ),
                  EpicTuningParam(
                    key: 'CounterBurstSpeed',
                    value: '950',
                    unit: 'cm/s',
                  ),
                  EpicTuningParam(
                    key: 'ShockwaveRadius',
                    value: '240',
                    unit: 'cm',
                  ),
                ],
                checks: [
                  EpicPieCheck(
                    id: 'off_feat_c1',
                    text:
                        'Trigger counter -> Follow-up movement bursts cleanly with 0 cooldown wait',
                  ),
                ],
              ),
        mode: archMode,
      ),
    ];
  }

  final usedLineageKeys = <String>{
    for (final ep in currentEpics)
      if (ep.lineageKey.trim().isNotEmpty) ep.lineageKey.trim().toLowerCase(),
  };
  int nextLineageOrd = currentEpics.length + 1;
  while (usedLineageKeys.contains(EpicSpec.formatLineageKey(nextLineageOrd))) {
    nextLineageOrd++;
  }
  final nextCode = EpicSpec.formatCode(currentEpics.length + 1);
  final nextLineageKey = EpicSpec.formatLineageKey(nextLineageOrd);
  final focusTitle = directionPrompt.trim().isNotEmpty
      ? LayersTextStyleGuide.formatConciseTaskTitle(directionPrompt.trim())
      : 'Round & Score Escalation';
  final newEpicFeatCode = featureCodes.allocate();
  final directorPath = archMode == UnrealArchitectureMode.cppHybrid
      ? 'Source/RoundDirector.cpp'
      : '/Game/Blueprints/BP_RoundDirector';
  final newEpic = EpicSpec(
    id: 'ep_${targetVersion}_1',
    code: nextCode,
    lineageKey: nextLineageKey,
    title: focusTitle,
    releaseVersion: targetVersion,
    lifecycle: EpicLifecycle.newEpic,
    coreLoopBeat: rootSpec.coreLoop.isNotEmpty
        ? 'Beat ${rootSpec.coreLoop.length} · ${rootSpec.coreLoop.last}'
        : 'Loop Escalation',
    chosenForNextRelease: true,
    goal:
        'Expand $targetVersion loop continuity with round pacing, UMG Widget HUD counter readout, and instant quick-restart.',
    inScope: const [
      '3-stage round progression timer',
      'Top-center WBP HUD round counter & R quick reset',
    ],
    doneWhen: const [
      'Complete Stage 1 objective -> UMG HUD updates and Stage 2 starts after 2.0 s',
    ],
    sceneOwnership: [
      EpicSceneOwnership(
        path: directorPath,
        role: 'Stage timer progression, HUD delegate & R quick reset',
      ),
    ],
    outOfScope: const [
      'No main menu save-slot persistence',
    ],
    states: const [
      'RoundStart (1.0s) -> ActiveRound -> StageClear (2.0s) -> NextStage / Victory',
    ],
    interrupts: const [
      'Run reset cleanly halts stage timers and restores initial actors in < 0.2 s',
    ],
    features: [
      FeatureSpec(
        id: 'ep_${targetVersion}_f01',
        code: newEpicFeatCode,
        title: 'Multi-Stage Pacer & HUD Counter',
        introducedIn: targetVersion,
        sliceTime: '45 min',
        status: FeatureStatus.queued,
        goal:
            'Advance 3 timed gameplay stages and update top-center WBP HUD banner.',
        tuning: [
          EpicTuningParam(key: 'RoundStageCount', value: '3', unit: 'count'),
          EpicTuningParam(key: 'StageDelay', value: '2.0', unit: 's'),
        ],
        checks: [
          EpicPieCheck(
            id: 'ep_${targetVersion}_f01_c1',
            text:
                'Complete Stage 1 objective -> UMG HUD updates and Stage 2 starts after 2.0 s',
          ),
        ],
      ),
    ],
  );

  final candidateList = [
    UnrealSpecGuard.sanitizeEpicSpec(
      newEpic,
      mode: archMode,
      forceReleaseVersion: targetVersion,
    ),
  ];

  final presets = defaultProgressivePresets(upgradesByKey, newFeaturesByKey, candidateList);
  return ProgressiveReleaseDraft(
    targetVersion: targetVersion,
    presets: presets,
    upgradesByLineageKey: upgradesByKey,
    candidateNewFeaturesByLineageKey: newFeaturesByKey,
    candidateNewEpics: candidateList,
    activePresetId: presets.first.id,
  );
}

List<ReleaseDirectionPreset> defaultProgressivePresets(
  Map<String, List<EpicUpgradeOption>> upgradesByKey,
  Map<String, List<FeatureSpec>> newFeaturesByKey,
  List<EpicSpec> candidates,
) {
  final firstUpIds = <String>[
    for (final list in upgradesByKey.values)
      if (list.isNotEmpty) list.first.id,
    for (final list in newFeaturesByKey.values)
      if (list.isNotEmpty) list.first.id,
  ];
  final firstNewIds = <String>[
    if (candidates.isNotEmpty) candidates.first.id,
  ];
  final allUpIds = <String>[
    for (final list in upgradesByKey.values)
      for (final o in list) o.id,
    for (final list in newFeaturesByKey.values)
      for (final f in list) f.id,
  ];
  final allNewIds = <String>[for (final c in candidates) c.id];

  return [
    ReleaseDirectionPreset(
      id: 'focused',
      label: 'Focused Feel + Loop',
      description:
          'Apply core game-feel upgrades and add the primary new Epic.',
      upgradeIds: firstUpIds,
      newEpicIds: firstNewIds,
    ),
    ReleaseDirectionPreset(
      id: 'expanded',
      label: 'Full Release Expansion',
      description:
          'Include all proposed upgrades and new Epics for maximum scope.',
      upgradeIds: allUpIds,
      newEpicIds: allNewIds,
    ),
  ];
}

/// Tracks allocated `F##` codes across baseline Epics and assigns non-colliding sequential codes.
class FeatureCodeAllocator {
  static final RegExp _codeRx = RegExp(r'^F(\d+)$', caseSensitive: false);
  final Set<String> _usedLower = <String>{};
  int _nextOrdinal = 1;

  int get nextOrdinal => _nextOrdinal;

  FeatureCodeAllocator(List<EpicSpec> currentEpics) {
    for (final ep in currentEpics) {
      for (final f in ep.features) {
        final clean = f.code.trim();
        if (clean.isNotEmpty) {
          _usedLower.add(clean.toLowerCase());
        }
        final m = _codeRx.firstMatch(clean);
        final numVal = int.tryParse(m?.group(1) ?? '') ?? 0;
        if (numVal >= _nextOrdinal) _nextOrdinal = numVal + 1;
      }
    }
  }

  String allocate([String preferred = '']) {
    final cleanPref = preferred.trim();
    final prefLower = cleanPref.toLowerCase();
    if (cleanPref.isNotEmpty && !_usedLower.contains(prefLower)) {
      _usedLower.add(prefLower);
      final m = _codeRx.firstMatch(cleanPref);
      if (m != null) {
        final numVal = int.tryParse(m.group(1) ?? '') ?? 0;
        if (numVal >= _nextOrdinal) _nextOrdinal = numVal + 1;
      }
      return cleanPref;
    }
    while (_usedLower
        .contains(FeatureSpec.formatCode(_nextOrdinal).toLowerCase())) {
      _nextOrdinal++;
    }
    final allocated = FeatureSpec.formatCode(_nextOrdinal);
    _usedLower.add(allocated.toLowerCase());
    _nextOrdinal++;
    return allocated;
  }
}
