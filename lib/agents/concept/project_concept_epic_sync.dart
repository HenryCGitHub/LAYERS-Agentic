import '../../models/agent_blueprints.dart';
import '../../models/epic_spec.dart';
import '../../utils/unreal_spec_guard.dart';

String _swapArchitectureAssetPath(
  String rawPath,
  UnrealArchitectureMode targetMode,
) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return trimmed;
  final lower = trimmed.toLowerCase();
  if (lower.endsWith('.umap') ||
      lower.contains('/game/maps/') ||
      lower.contains('/game/ui/') ||
      lower.contains('/game/data/')) {
    return trimmed;
  }
  if (targetMode == UnrealArchitectureMode.cppHybrid) {
    final m = RegExp(
      r'^/Game/Blueprints/BP_([A-Za-z0-9_]+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (m != null) {
      return 'Source/${m.group(1)}.cpp';
    }
  } else {
    final m = RegExp(
      r'^Source/([A-Za-z0-9_]+)\.(?:cpp|h)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (m != null) {
      return '/Game/Blueprints/BP_${m.group(1)}';
    }
  }
  return trimmed;
}

/// Switches a [ProjectConceptBlueprint] between `Blueprint-First` and `C++ & BP Hybrid`,
/// updating `§02` Asset Policy and non-map `EpicSceneOwnership` paths while keeping `cm` values intact.
ProjectConceptBlueprint convertBlueprintArchitectureModeImpl(
  ProjectConceptBlueprint current,
  UnrealArchitectureMode targetMode,
) {
  final next = current.deepCopy();
  next.architectureMode = targetMode;
  next.assetPolicy = targetMode == UnrealArchitectureMode.cppHybrid
      ? 'Source/ ACharacter & UActorComponent UPROPERTY(EditAnywhere) C++ Base + Thin /Game/Blueprints/BP_* & /Game/Data/DA_*'
      : 'UStaticMeshComponent Greybox + UMaterialInstanceDynamic Tints; /Game/Data/DA_GameTuning & Exposed BP Vars';

  for (final ep in [...next.initialEpics, ...next.v02NewPool]) {
    ep.sceneOwnership = [
      for (final own in ep.sceneOwnership)
        EpicSceneOwnership(
          path: _swapArchitectureAssetPath(own.path, targetMode),
          role: own.role,
        ),
    ];
  }
  return UnrealSpecGuard.sanitizeConceptBlueprint(
    raw: next,
    modeOverride: targetMode,
  );
}

/// Keeps `E01..EN` and `F01..FM` strictly sequential across `initialEpics` without gaps or duplicate codes.
void normalizeSequentialEpicAndFeatureCodesImpl(
  ProjectConceptBlueprint bp,
) {
  final usedLineageKeys = <String>{};
  final usedFeatIds = <String>{};
  int nextFeatNum = 1;
  int lineageOrd = 1;
  for (int i = 0; i < bp.initialEpics.length; i++) {
    final ep = bp.initialEpics[i];
    ep.code = EpicSpec.formatCode(i + 1);
    var lk = ep.lineageKey.trim().toLowerCase();
    if (lk.isEmpty || usedLineageKeys.contains(lk)) {
      while (usedLineageKeys.contains(EpicSpec.formatLineageKey(lineageOrd))) {
        lineageOrd++;
      }
      lk = EpicSpec.formatLineageKey(lineageOrd);
    }
    ep.lineageKey = lk;
    usedLineageKeys.add(lk);
    ep.releaseVersion = 'v0.1';
    if (i == 0 && ep.lifecycle == EpicLifecycle.queued) {
      ep.lifecycle = EpicLifecycle.active;
    }
    bool activatedFirstOpen = false;
    for (int fIdx = 0; fIdx < ep.features.length; fIdx++) {
      var feat = ep.features[fIdx];
      final rawFeatId = feat.id.trim();
      if (rawFeatId.isEmpty ||
          FeatureSpec.isPositionalFallbackFeatureId(rawFeatId) ||
          usedFeatIds.contains(rawFeatId)) {
        var nextId = '${ep.id}_f${nextFeatNum.toString().padLeft(2, '0')}';
        var suffix = 2;
        while (usedFeatIds.contains(nextId)) {
          nextId = '${ep.id}_f${nextFeatNum.toString().padLeft(2, '0')}_$suffix';
          suffix++;
        }
        feat = feat.deepCopy(idOverride: nextId);
        ep.features[fIdx] = feat;
      }
      usedFeatIds.add(feat.id);
      feat.code = FeatureSpec.formatCode(nextFeatNum);
      feat.introducedIn = 'v0.1';
      if (i == 0 && !activatedFirstOpen && !feat.isPassed) {
        if (feat.status == FeatureStatus.queued) {
          feat.status = FeatureStatus.active;
        }
        activatedFirstOpen = true;
      }
      nextFeatNum++;
    }
  }
}

EpicSpec _findLocomotionEpic(ProjectConceptBlueprint draft) {
  for (final ep in draft.initialEpics) {
    if (ep.lineageKey.trim().toLowerCase() == 'e01') return ep;
  }
  for (final ep in draft.initialEpics) {
    final text =
        '${ep.title} ${ep.goal} ${ep.sceneOwnership.map((s) => s.path).join(' ')}'
            .toLowerCase();
    if (text.contains('movement') ||
        text.contains('locomotion') ||
        text.contains('camera') ||
        text.contains('handling') ||
        text.contains('player') ||
        text.contains('skiff')) {
      return ep;
    }
  }
  return draft.initialEpics.first;
}

void _upsertTuningParam(
  List<EpicTuningParam> tuning,
  String key,
  String value,
  String unit,
) {
  final idx = tuning.indexWhere(
    (t) => t.key.trim().toLowerCase() == key.toLowerCase(),
  );
  if (idx >= 0) {
    tuning[idx].key = key;
    tuning[idx].value = value;
    tuning[idx].unit = unit;
  } else {
    tuning.add(EpicTuningParam(key: key, value: value, unit: unit));
  }
}

void _upsertAimControl(
  List<EpicControlBinding> controls,
  String aimAction,
  String aimTrigger,
  String aimRule,
) {
  final aimIdx = controls.indexWhere((c) {
    final a = c.action.toLowerCase();
    return a.contains('aim') || a.contains('look') || a.contains('camera');
  });
  if (aimIdx >= 0) {
    controls[aimIdx].action = aimAction;
    controls[aimIdx].trigger = aimTrigger;
    controls[aimIdx].rule = aimRule;
  } else {
    controls.add(
      EpicControlBinding(action: aimAction, trigger: aimTrigger, rule: aimRule),
    );
  }
}

void _upsertCameraCheck(
  List<EpicPieCheck> checks,
  String fallbackId,
  String expectedCheck,
) {
  final checkIdx = checks.indexWhere((c) {
    final t = c.text.toLowerCase();
    return t.contains('cursor') ||
        t.contains('reticle') ||
        t.contains('springarm') ||
        t.contains('uspringarm') ||
        t.contains('camera') ||
        t.contains('turret') ||
        t.contains('first-person') ||
        t.contains('aim');
  });
  if (checkIdx >= 0) {
    checks[checkIdx].text = expectedCheck;
  } else {
    checks.add(EpicPieCheck(id: fallbackId, text: expectedCheck));
  }
}

String? _extractCmFromContract(String contract, RegExp cmRx, RegExp meterRx) {
  final cmMatch = cmRx.firstMatch(contract);
  if (cmMatch != null) return cmMatch.group(1);
  final mMatch = meterRx.firstMatch(contract);
  if (mMatch != null) {
    final v = double.tryParse(mMatch.group(1) ?? '');
    if (v != null) {
      final cm = v * 100.0;
      return (cm - cm.roundToDouble()).abs() < 0.01
          ? cm.round().toString()
          : cm.toStringAsFixed(1);
    }
  }
  return null;
}

/// Synchronizes locomotion Epic & first Feature's aim/look controls, tail tuning,
/// and playtest check whenever the Stage 1 Camera Decision (`§02`) changes, without shifting `tuning[0]`.
void syncEpicCameraFramingImpl(
  ProjectConceptBlueprint draft, {
  required String optionId,
  required String contractValue,
}) {
  if (draft.initialEpics.isEmpty) return;
  final locoEpic = _findLocomotionEpic(draft);
  final lowerId = optionId.toLowerCase();
  final lowerContract = contractValue.toLowerCase();
  final isTps = lowerId.contains('tps') ||
      lowerId.contains('shoulder') ||
      lowerId.contains('third') ||
      lowerContract.contains('offset');
  final isFps = lowerId.contains('fps') || lowerId.contains('first');
  final isSide = lowerId.contains('side');

  void upsertTailTuning(String key, String value, String unit) {
    if (locoEpic.tuning.isNotEmpty || locoEpic.features.isEmpty) {
      _upsertTuningParam(locoEpic.tuning, key, value, unit);
    }
    if (locoEpic.features.isNotEmpty) {
      _upsertTuningParam(locoEpic.features.first.tuning, key, value, unit);
    }
  }

  void removeTuning(String key) {
    locoEpic.tuning.removeWhere(
      (t) => t.key.trim().toLowerCase() == key.toLowerCase(),
    );
    for (final f in locoEpic.features) {
      f.tuning.removeWhere(
        (t) => t.key.trim().toLowerCase() == key.toLowerCase(),
      );
    }
  }

  final springCm = _extractCmFromContract(
    contractValue,
    RegExp(r'(?:TargetArmLength|USpringArmComponent)\s+(\d+(?:\.\d+)?)\s*cm',
        caseSensitive: false),
    RegExp(r'(?:TargetArmLength|USpringArmComponent|SpringArm\w*)\s+(\d+(?:\.\d+)?)\s*m',
        caseSensitive: false),
  );
  final eyeCm = _extractCmFromContract(
    contractValue,
    RegExp(r'EyeHeight\s+(\d+(?:\.\d+)?)\s*cm', caseSensitive: false),
    RegExp(r'EyeHeight\s+(\d+(?:\.\d+)?)\s*m', caseSensitive: false),
  );

  if (springCm != null) {
    removeTuning('EyeHeight');
    upsertTailTuning('SpringArmLength', springCm, 'cm');
  } else if (isFps) {
    removeTuning('SpringArmLength');
    if (eyeCm != null) {
      upsertTailTuning('EyeHeight', eyeCm, 'cm');
    }
  }
  final fovMatch = RegExp(
    r'(\d+(?:\.\d+)?)\s*deg\s*FOV',
    caseSensitive: false,
  ).firstMatch(contractValue);
  if (fovMatch != null) {
    upsertTailTuning('CameraFOV', fovMatch.group(1)!, 'deg');
  }

  final aimAction = (isTps || isFps) ? 'IA_LookAxis' : 'IA_MouseAim';
  final aimTrigger = (isTps || isFps)
      ? 'Triggered (Mouse XY 2D-Axis)'
      : 'Tick GetHitResultUnderCursor';
  final aimRule = isTps
      ? 'Orbits over-shoulder USpringArmComponent yaw/pitch and aligns center reticle'
      : isFps
          ? 'Direct 1:1 first-person UCameraComponent yaw/pitch rotation'
          : isSide
              ? 'Tracks locked side-view USpringArmComponent along forward travel plane'
              : 'Projects cursor trace onto ground XY plane to orient TurretVisual aim';

  if (locoEpic.controls.isNotEmpty || locoEpic.features.isEmpty) {
    _upsertAimControl(locoEpic.controls, aimAction, aimTrigger, aimRule);
  }
  if (locoEpic.features.isNotEmpty) {
    _upsertAimControl(
      locoEpic.features.first.controls,
      aimAction,
      aimTrigger,
      aimRule,
    );
  }

  final expectedCheck = isTps
      ? 'Move mouse -> over-shoulder USpringArmComponent orbits smoothly with center reticle alignment'
      : isFps
          ? 'Move mouse -> first-person UCameraComponent turns smoothly with center reticle alignment'
          : isSide
              ? 'Run left/right -> side-scroller camera tracks smoothly with clear jump lookahead'
              : 'Move cursor across floor -> TurretVisual tracks ground XY aim smoothly';

  if (locoEpic.checks.isNotEmpty || locoEpic.features.isEmpty) {
    _upsertCameraCheck(
      locoEpic.checks,
      '${locoEpic.code.toLowerCase()}_cam',
      expectedCheck,
    );
  }
  if (locoEpic.features.isNotEmpty) {
    final firstFeat = locoEpic.features.first;
    _upsertCameraCheck(
      firstFeat.checks,
      '${firstFeat.id}_cam',
      expectedCheck,
    );
  }
}

/// Synchronizes `feelChoiceId`, primary §03 feel `TradeOffRule`, and locomotion Epic tail tuning (`BrakingDeceleration`)
/// without disturbing `tuning[0]`.
void syncEpicCoreFeelImpl(
  ProjectConceptBlueprint draft, {
  required String feelId,
}) {
  final opt = ProjectConceptBlueprint.coreFeelOptionById(feelId);
  draft.feelChoiceId = opt.id;

  final feelKeywords = <String>[
    for (final f in ProjectConceptBlueprint.coreFeelOptions)
      f.tradeOff.prefer.toLowerCase(),
    'acceleration',
    'windup',
    'velocity carry',
    'hovering spring',
    'momentum',
  ];
  final updatedTrades = List<TradeOffRule>.from(draft.tradeOffs);
  final idx = updatedTrades.indexWhere((t) {
    final p = t.prefer.toLowerCase();
    return feelKeywords.any((kw) => p.contains(kw));
  });
  if (idx >= 0) {
    updatedTrades.removeAt(idx);
  }
  updatedTrades.insert(0, opt.tradeOff);
  draft.tradeOffs = updatedTrades;

  if (draft.initialEpics.isEmpty) return;
  final locoEpic = _findLocomotionEpic(draft);
  final decelVal = opt.decelCmPerSec;
  if (locoEpic.tuning.isNotEmpty || locoEpic.features.isEmpty) {
    _upsertTuningParam(locoEpic.tuning, 'BrakingDeceleration', decelVal, 'cm/s');
  }
  if (locoEpic.features.isNotEmpty) {
    _upsertTuningParam(
      locoEpic.features.first.tuning,
      'BrakingDeceleration',
      decelVal,
      'cm/s',
    );
  }
}
