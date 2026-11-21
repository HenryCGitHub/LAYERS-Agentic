import '../../models/agent_blueprints.dart';
import '../../models/epic_spec.dart';
import '../../utils/godot_spec_guard.dart';

String _fmtScaleNum(double v) {
  if ((v - v.roundToDouble()).abs() < 0.01) {
    return v.round().toString();
  }
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

void _convertTuningListDimension(
  List<EpicTuningParam> tuning,
  GodotProjectDimension prevDim,
  GodotProjectDimension targetDim,
) {
  const pxPerMeter = 40.0;
  final is2d = targetDim == GodotProjectDimension.dim2d;
  for (final param in tuning) {
    final rawUnit = param.unit.trim().toLowerCase();
    final parsed = double.tryParse(param.value.trim());
    if (prevDim == GodotProjectDimension.dim3d && is2d) {
      if (rawUnit == 'm') {
        if (parsed != null) param.value = _fmtScaleNum(parsed * pxPerMeter);
        param.unit = 'px';
      } else if (rawUnit == 'm/s') {
        if (parsed != null) param.value = _fmtScaleNum(parsed * pxPerMeter);
        param.unit = 'px/s';
      }
    } else if (prevDim == GodotProjectDimension.dim2d && !is2d) {
      if (rawUnit == 'px') {
        if (parsed != null) param.value = _fmtScaleNum(parsed / pxPerMeter);
        param.unit = 'm';
      } else if (rawUnit == 'px/s') {
        if (parsed != null) param.value = _fmtScaleNum(parsed / pxPerMeter);
        param.unit = 'm/s';
      }
    }
  }
}

String _swapDimensionLabelsOutsidePaths(
  String text, {
  required bool to2d,
}) {
  if (text.isEmpty) return text;
  final resPathRx = RegExp(r'res://\S+');
  String transformChunk(String chunk) {
    if (to2d) {
      return chunk
          .replaceAll(RegExp(r'\b3D\b'), '2D')
          .replaceAll(
            RegExp(r'\bXZ\s+ground[- ]plane\b', caseSensitive: false),
            '2D XY plane',
          )
          .replaceAll(
            RegExp(r'\bXZ\s+plane\b', caseSensitive: false),
            'XY plane',
          )
          .replaceAll(RegExp(r'\bXZ\b'), 'XY');
    }
    return chunk
        .replaceAll(RegExp(r'\b2D\b'), '3D')
        .replaceAll(
          RegExp(r'\bXY\s+plane\b', caseSensitive: false),
          'XZ plane',
        )
        .replaceAll(RegExp(r'\bXY\b'), 'XZ');
  }

  final buf = StringBuffer();
  int cursor = 0;
  for (final m in resPathRx.allMatches(text)) {
    if (m.start > cursor) {
      buf.write(transformChunk(text.substring(cursor, m.start)));
    }
    buf.write(m.group(0));
    cursor = m.end;
  }
  if (cursor < text.length) {
    buf.write(transformChunk(text.substring(cursor)));
  }
  return buf.toString();
}

void _convertFeatureDimensionContent(
  FeatureSpec feat,
  GodotProjectDimension prevDim,
  GodotProjectDimension targetDim,
) {
  final to2d = targetDim == GodotProjectDimension.dim2d;
  String conv(String s) => _swapDimensionLabelsOutsidePaths(s, to2d: to2d);
  feat.title = conv(feat.title);
  feat.goal = conv(feat.goal);
  feat.releaseDelta = conv(feat.releaseDelta);
  feat.inScope = [for (final s in feat.inScope) conv(s)];
  feat.doneWhen = [for (final s in feat.doneWhen) conv(s)];
  feat.controls = [
    for (final c in feat.controls)
      EpicControlBinding(
        action: c.action,
        trigger: conv(c.trigger),
        rule: conv(c.rule),
      ),
  ];
  _convertTuningListDimension(feat.tuning, prevDim, targetDim);
  feat.cues = [for (final c in feat.cues) conv(c)];
  feat.checks = [
    for (final chk in feat.checks)
      chk.copyWith(text: conv(chk.text)),
  ];
  feat.releaseDeltaChecks = [
    for (final chk in feat.releaseDeltaChecks)
      chk.copyWith(text: conv(chk.text)),
  ];
}

void _convertEpicDimensionContent(
  EpicSpec ep,
  GodotProjectDimension prevDim,
  GodotProjectDimension targetDim,
) {
  final to2d = targetDim == GodotProjectDimension.dim2d;
  String conv(String s) => _swapDimensionLabelsOutsidePaths(s, to2d: to2d);
  ep.title = conv(ep.title);
  ep.coreLoopBeat = conv(ep.coreLoopBeat);
  ep.goal = conv(ep.goal);
  ep.inScope = [for (final s in ep.inScope) conv(s)];
  ep.doneWhen = [for (final s in ep.doneWhen) conv(s)];
  ep.sceneOwnership = [
    for (final o in ep.sceneOwnership)
      EpicSceneOwnership(path: o.path, role: conv(o.role)),
  ];
  ep.states = [for (final s in ep.states) conv(s)];
  ep.interrupts = [for (final s in ep.interrupts) conv(s)];
  ep.outOfScope = [for (final s in ep.outOfScope) conv(s)];
  ep.links = [for (final s in ep.links) conv(s)];
  ep.feedback = [for (final s in ep.feedback) conv(s)];
  ep.levelStaging = conv(ep.levelStaging);
  ep.checks = [
    for (final chk in ep.checks) chk.copyWith(text: conv(chk.text)),
  ];
  ep.baselineSummary = [for (final s in ep.baselineSummary) conv(s)];
  ep.upgradeDeltas = [for (final s in ep.upgradeDeltas) conv(s)];
  _convertTuningListDimension(ep.tuning, prevDim, targetDim);
  for (final feat in ep.features) {
    _convertFeatureDimensionContent(feat, prevDim, targetDim);
  }
}

/// Converts an active [ProjectConceptBlueprint] between Godot 4 `3D` (`m`, `m/s`)
/// and `2D` (`px`, `px/s`), updating §02 camera/scale contracts, Epics, and Features cleanly.
ProjectConceptBlueprint convertBlueprintDimensionImpl(
  ProjectConceptBlueprint current,
  GodotProjectDimension targetDim,
) {
  final next = current.deepCopy();
  if (next.dimension == targetDim) return next;
  final prevDim = next.dimension;
  next.dimension = targetDim;

  final is2d = targetDim == GodotProjectDimension.dim2d;
  String conv(String s) => _swapDimensionLabelsOutsidePaths(s, to2d: is2d);
  next.pitch = conv(next.pitch);
  next.coreLoop = [for (final b in next.coreLoop) conv(b)];
  next.pillars = [for (final p in next.pillars) conv(p)];
  next.tradeOffs = [
    for (final t in next.tradeOffs)
      TradeOffRule(prefer: conv(t.prefer), avoid: conv(t.avoid)),
  ];
  next.outOfScope = [for (final s in next.outOfScope) conv(s)];
  next.releaseDoneWhen = conv(next.releaseDoneWhen);

  next.cameraDecisionOptions = is2d
      ? List<ConceptSectionOption>.from(
          ProjectConceptBlueprint.defaultCamera2dOptions,
        )
      : List<ConceptSectionOption>.from(
          ProjectConceptBlueprint.defaultCamera3dOptions,
        );
  next.cameraChoiceId = is2d ? 'topdown2d' : 'isometric';
  next.cameraContract = next.cameraDecisionOptions.first.contractValue;

  if (is2d) {
    next.characterScale =
        'CharacterBody2D CollisionShape 32x48 px · move_speed 260 px/s';
    next.assetPolicy =
        'ColorRect / Polygon2D Greybox Prototypes + Solid Tint Materials; @export vars & Resource (.tres)';
  } else {
    next.characterScale =
        'CharacterBody3D CapsuleRadius 0.42 m · Height 1.84 m · move_speed 6.2 m/s';
    next.assetPolicy =
        'CSGBox3D / PrimitiveMesh Greybox + StandardMaterial3D Tints; @export vars & Resource (.tres)';
  }

  for (final ep in [...next.initialEpics, ...next.v02NewPool]) {
    _convertEpicDimensionContent(ep, prevDim, targetDim);
  }
  for (final list in next.v02NewFeaturesByLineageKey.values) {
    for (final feat in list) {
      _convertFeatureDimensionContent(feat, prevDim, targetDim);
    }
  }
  next.v02Presets = [
    for (final p in next.v02Presets)
      ReleaseDirectionPreset(
        id: p.id,
        label: conv(p.label),
        description: conv(p.description),
        upgradeIds: List<String>.from(p.upgradeIds),
        newEpicIds: List<String>.from(p.newEpicIds),
      ),
  ];
  next.v02UpgradesByLineageKey = {
    for (final entry in next.v02UpgradesByLineageKey.entries)
      entry.key: [
        for (final u in entry.value)
          u.copyWith(text: conv(u.text)),
      ],
  };

  syncEpicCameraFramingImpl(
    next,
    optionId: next.cameraChoiceId,
    contractValue: next.cameraContract,
  );
  syncEpicCoreFeelImpl(next, feelId: next.feelChoiceId);
  return GodotSpecGuard.sanitizeConceptBlueprint(next);
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

/// Resolves the locomotion/camera Epic by `lineageKey` or domain keywords even after queue reordering.
EpicSpec _findLocomotionEpic(ProjectConceptBlueprint draft) {
  for (final ep in draft.initialEpics) {
    if (ep.lineageKey.trim().toLowerCase() == 'e01') {
      return ep;
    }
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
      EpicControlBinding(
        action: aimAction,
        trigger: aimTrigger,
        rule: aimRule,
      ),
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
        t.contains('camera') ||
        t.contains('visualrig') ||
        t.contains('first-person') ||
        t.contains('aim');
  });
  if (checkIdx >= 0) {
    checks[checkIdx].text = expectedCheck;
  } else {
    checks.add(EpicPieCheck(id: fallbackId, text: expectedCheck));
  }
}

/// Synchronizes locomotion Epic & first Feature's aim/look controls, tail tuning, and playtest check
/// whenever the Stage 1 Camera Decision (`§02`) changes, without shifting `tuning[0]`.
void syncEpicCameraFramingImpl(
  ProjectConceptBlueprint draft, {
  required String optionId,
  required String contractValue,
}) {
  if (draft.initialEpics.isEmpty) return;
  final locoEpic = _findLocomotionEpic(draft);
  final lowerId = optionId.toLowerCase();
  final lowerContract = contractValue.toLowerCase();
  final is2d = draft.dimension == GodotProjectDimension.dim2d ||
      lowerId.endsWith('2d') ||
      lowerContract.contains('camera2d');
  final isTps = !is2d &&
      (lowerId.contains('tps') ||
          lowerId.contains('shoulder') ||
          lowerId.contains('third') ||
          lowerContract.contains('offset'));
  final isFps = !is2d && (lowerId.contains('fps') || lowerId.contains('first'));

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

  if (is2d) {
    removeTuning('spring_arm_length');
    removeTuning('eye_height');
    removeTuning('camera_fov');
    final zoomMatch = RegExp(
      r'Zoom\s+(\d+(?:\.\d+)?)x',
      caseSensitive: false,
    ).firstMatch(contractValue);
    if (zoomMatch != null) {
      upsertTailTuning('camera_zoom', zoomMatch.group(1)!, 'x');
    }
  } else {
    removeTuning('camera_zoom');
    final springArmMatch = RegExp(
      r'SpringArm3D\s+(\d+(?:\.\d+)?)\s*m',
      caseSensitive: false,
    ).firstMatch(contractValue);
    final eyeHeightMatch = RegExp(
      r'EyeHeight\s+(\d+(?:\.\d+)?)\s*m',
      caseSensitive: false,
    ).firstMatch(contractValue);
    if (springArmMatch != null) {
      removeTuning('eye_height');
      upsertTailTuning('spring_arm_length', springArmMatch.group(1)!, 'm');
    } else if (isFps) {
      removeTuning('spring_arm_length');
      if (eyeHeightMatch != null) {
        upsertTailTuning('eye_height', eyeHeightMatch.group(1)!, 'm');
      }
    }
    final fovMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*deg\s*FOV',
      caseSensitive: false,
    ).firstMatch(contractValue);
    if (fovMatch != null) {
      upsertTailTuning('camera_fov', fovMatch.group(1)!, 'deg');
    }
  }

  final aimAction = is2d
      ? 'mouse_aim'
      : ((isTps || isFps) ? 'look_axis' : 'mouse_aim');
  final aimTrigger = (isTps || isFps)
      ? 'InputEventMouseMotion'
      : (is2d ? 'Cursor 2D Global Pos' : 'Physics Tick XZ Raycast');
  final aimRule = is2d
      ? 'Rotates player Sprite2D/WeaponPivot toward get_global_mouse_position() cleanly'
      : isTps
          ? 'Orbits over-shoulder SpringArm3D yaw/pitch and aligns center reticle'
          : isFps
              ? 'Direct 1:1 first-person Camera3D yaw/pitch rotation'
              : 'Projects cursor ray onto ground XZ-plane to orient VisualRig aim';

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

  final expectedCheck = is2d
      ? 'Move cursor across 2D viewport -> player aim indicator tracks cursor immediately'
      : isTps
          ? 'Move mouse -> over-shoulder SpringArm3D orbits smoothly with center reticle alignment'
          : isFps
              ? 'Move mouse -> first-person Camera3D turns smoothly with center reticle alignment'
              : 'Move cursor across floor -> VisualRig tracks ground XZ aim smoothly';

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

/// Synchronizes `feelChoiceId`, primary §03 feel `TradeOffRule`, and locomotion Epic tail tuning (`braking_decel`)
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
  final decelVal = opt.decelFor(draft.dimension);
  final speedUnit = draft.dimension.speedUnit;
  if (locoEpic.tuning.isNotEmpty || locoEpic.features.isEmpty) {
    _upsertTuningParam(locoEpic.tuning, 'braking_decel', decelVal, speedUnit);
  }
  if (locoEpic.features.isNotEmpty) {
    _upsertTuningParam(
      locoEpic.features.first.tuning,
      'braking_decel',
      decelVal,
      speedUnit,
    );
  }
}
