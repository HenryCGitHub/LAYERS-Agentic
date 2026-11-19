import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';

/// Pure Godot 4 specification guard, sanitizer & `v0.1` scope validator.
/// Ensures zero Unreal/Unity/C++ leakage, clean literal game-dev wording,
/// and canonical Godot 4 `3D` (`m`, `m/s`) or `2D` (`px`, `px/s`) units.
class GodotSpecGuard {
  static final RegExp _nonGodotLeakPattern = RegExp(
    r'\b(unreal(?:\s+engine)?|blueprints?|uasset|uproject|acharacter|aactor|upawn|uspringarmcomponent|ucameracomponent|uboxcomponent|uinputaction|umg|niagara|uclass|uproperty|ufunction|live\s+coding|gameobjects?|monobehaviour|serializefield|prefabs?|uu)\b|\b(?:IA|IMC|BP|WBP|BPI|DA)_[A-Za-z0-9_]+\b|(?:\.uasset|\.uproject|\.prefab|\.cpp|\.hpp)\b|\bcm/s\b|\b\d+(?:\.\d+)?\s*cm\b',
    caseSensitive: false,
  );

  static final RegExp _leadingBulletPattern = RegExp(r'^[\-\*\u2022\s]+');

  static final List<String> _bannedFillerPhrases = <String>[
    'end-to-end loop',
    'end-to-end',
    'unified pipeline',
    'unified',
    'seamlessly',
    'synergistic',
    'synergy',
  ];

  static final List<(String, String)> _jargonReplacements = <(String, String)>[
    ('leveraging', 'using'),
    ('leverages', 'uses'),
    ('leverage', 'use'),
    ('validates', 'checks'),
    ('validated', 'checked'),
    ('validate', 'check'),
    ('verified', 'checked'),
    ('delivering', 'producing'),
    ('delivers', 'produces'),
    ('deliver', 'produce'),
    ('husbandry', 'breeding'),
    ('homestead', 'base'),
    ('expedition', 'run'),
    ('ordinance', 'weaponry'),
  ];

  static String _formatCleanNum(double v) {
    if ((v - v.roundToDouble()).abs() < 0.001) {
      return v.round().toString();
    }
    final two = v.toStringAsFixed(2);
    return two.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _replaceCaseAware(
    String input,
    String fromWord,
    String toLower,
  ) {
    return input.replaceAllMapped(
      RegExp('\\b$fromWord\\b', caseSensitive: false),
      (m) {
        final matched = m.group(0) ?? '';
        if (matched.isNotEmpty &&
            matched[0] == matched[0].toUpperCase() &&
            matched[0] != matched[0].toLowerCase()) {
          return '${toLower[0].toUpperCase()}${toLower.substring(1)}';
        }
        return toLower;
      },
    );
  }

  static bool containsEngineLeakage(String text) {
    return _nonGodotLeakPattern.hasMatch(text);
  }

  /// Strips Unreal/Unity/C++ terms or buzzword padding and tightens to literal Godot 4 phrasing.
  static String sanitizeLine(
    String raw, {
    GodotProjectDimension dimension = GodotProjectDimension.dim3d,
  }) {
    var out = raw.trim().replaceFirst(_leadingBulletPattern, '').trim();
    if (out.isEmpty) return '';

    final is2d = dimension == GodotProjectDimension.dim2d;
    final bodyClass = is2d ? 'CharacterBody2D' : 'CharacterBody3D';
    final nodeClass = is2d ? 'Node2D' : 'Node3D';
    final areaClass = is2d ? 'Area2D' : 'Area3D';
    final camClass = is2d ? 'Camera2D' : 'Camera3D';
    final particlesClass = is2d ? 'GPUParticles2D' : 'GPUParticles3D';
    final springCam = is2d ? 'Camera2D' : 'SpringArm3D';

    final replacements = <RegExp, String>{
      RegExp(r'\bUnreal Engine\b', caseSensitive: false): 'Godot 4',
      RegExp(r'\bUnreal\b', caseSensitive: false): 'Godot 4',
      RegExp(r'\bACharacter\b', caseSensitive: false): bodyClass,
      RegExp(r'\bAPawn\b', caseSensitive: false): bodyClass,
      RegExp(r'\bAActor\b', caseSensitive: false): nodeClass,
      RegExp(r'\bGameObjects\b', caseSensitive: false): '${nodeClass}s',
      RegExp(r'\bGameObject\b', caseSensitive: false): nodeClass,
      RegExp(r'\bMonoBehaviour\b', caseSensitive: false): 'GDScript Node',
      RegExp(r'\bUBoxComponent\b', caseSensitive: false): areaClass,
      RegExp(r'\bUSpringArmComponent\b', caseSensitive: false): springCam,
      RegExp(r'\bSpringArm\b', caseSensitive: false): springCam,
      RegExp(r'\bUCameraComponent\b', caseSensitive: false): camClass,
      RegExp(r'\bUInputAction\b', caseSensitive: false): 'InputMap Action',
      RegExp(r'\bEnhanced Input\b', caseSensitive: false): 'InputMap',
      RegExp(r'\bIMC_[A-Za-z0-9_]+\b'): 'InputMap',
      RegExp(r'\bNiagara\b', caseSensitive: false): particlesClass,
      RegExp(r'\bUMG\b', caseSensitive: false): 'Control HUD',
      RegExp(r'\bPlayerStart\b', caseSensitive: false): 'SpawnPoint',
      RegExp(r'\bOutput Log\b', caseSensitive: false): 'Godot Debugger',
      RegExp(r'\bPIE\b'): 'Playtest',
      RegExp(r'\bSerializeField\b', caseSensitive: false): '@export',
      RegExp(r'\bUCLASS\s*(?:\([^)]*\))?', caseSensitive: false): 'PackedScene',
      RegExp(r'\bUPROPERTY\s*(?:\([^)]*\))?', caseSensitive: false): '@export',
      RegExp(r'\bUFUNCTION\s*(?:\([^)]*\))?', caseSensitive: false):
          'GDScript Signal',
      RegExp(r'\bBlueprint Class\b', caseSensitive: false): 'PackedScene',
      RegExp(r'\bBlueprints\b', caseSensitive: false): 'Scenes/Scripts',
      RegExp(r'\bBlueprint\b', caseSensitive: false): 'Scene/Script',
      RegExp(r'\bPrimaryDataAsset\b', caseSensitive: false): 'Resource (.tres)',
      RegExp(r'\bUDataAsset\b', caseSensitive: false): 'Resource (.tres)',
      RegExp(r'\.uasset\b', caseSensitive: false): '.tscn',
      RegExp(r'\.uproject\b', caseSensitive: false): 'project.godot',
      RegExp(r'\.prefab\b', caseSensitive: false): '.tscn',
      RegExp(r'\bPrefabs\b', caseSensitive: false): 'PackedScenes',
      RegExp(r'\bPrefab\b', caseSensitive: false): 'PackedScene',
    };
    for (final entry in replacements.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }

    // Rewrite Unreal prefixes IA_ClawDash / BP_CrabPlayer / WBP_Hud -> snake_case Godot identifiers
    out = out.replaceAllMapped(
      RegExp(r'\bIA_([A-Za-z0-9_]+)\b'),
      (m) => _toSnakeCaseToken(m.group(1) ?? 'action'),
    );
    out = out.replaceAllMapped(
      RegExp(r'\b(?:BP|BPI|WBP|DA)_([A-Za-z0-9_]+)\b'),
      (m) => _toSnakeCaseToken(m.group(1) ?? 'entity'),
    );
    out = out.replaceAllMapped(
      RegExp(r'\bL_([A-Za-z0-9_]+)\b'),
      (m) => '${_toSnakeCaseToken(m.group(1) ?? 'arena')}.tscn',
    );
    out = out.replaceAllMapped(
      RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\.(?:cpp|hpp)\b',
          caseSensitive: false),
      (m) => '${_toSnakeCaseToken(m.group(1) ?? 'script')}.gd',
    );

    // Convert cm / cm/s -> m / m/s in 3D, or px / px/s in 2D
    out = out.replaceAllMapped(
      RegExp(r'\b(\d+(?:\.\d+)?)\s*cm/s\b', caseSensitive: false),
      (m) {
        final rawNum = double.tryParse(m.group(1) ?? '') ?? 0;
        if (is2d) return '${_formatCleanNum(rawNum)} px/s';
        return '${_formatCleanNum(rawNum / 100.0)} m/s';
      },
    );
    out = out.replaceAllMapped(
      RegExp(r'\b(\d+(?:\.\d+)?)\s*cm\b', caseSensitive: false),
      (m) {
        final rawNum = double.tryParse(m.group(1) ?? '') ?? 0;
        if (is2d) return '${_formatCleanNum(rawNum)} px';
        return '${_formatCleanNum(rawNum / 100.0)} m';
      },
    );

    for (final (fromWord, toLower) in _jargonReplacements) {
      out = _replaceCaseAware(out, fromWord, toLower);
    }

    for (final filler in _bannedFillerPhrases) {
      out = out.replaceAll(
        RegExp('\\b${RegExp.escape(filler)}\\b', caseSensitive: false),
        '',
      );
    }

    out = out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    out = out.replaceAllMapped(
      RegExp(r'\s+(?:and|or)\s*([.,;:])', caseSensitive: false),
      (m) => m.group(1)!,
    );
    out = out.replaceAllMapped(
      RegExp(r'\s+([.,;:])'),
      (m) => m.group(1)!,
    );
    return out.trim();
  }

  static String _toSnakeCaseToken(String raw) {
    final spaced = raw
        .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'([a-zA-Z])(\d)'),
          (m) => '${m.group(1)}_${m.group(2)}',
        );
    final tokens = spaced
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();
    return tokens.isEmpty ? 'item' : tokens.join('_');
  }

  /// Normalizes a `§04` tuning key into a clean Godot `snake_case` `@export` identifier.
  /// Handles legacy Unreal `bAllowAirDash` -> `allow_air_dash` and `MaxWalkSpeed` -> `max_walk_speed`.
  static String sanitizeTuningKey(
    String rawKey, {
    String fallback = 'tuning_param',
  }) {
    var clean = rawKey.trim().replaceAll(RegExp(r'^@export\s+var\s+', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
    // Strip Unreal Hungarian boolean prefix `b` when followed by uppercase letter
    final boolMatch = RegExp(r'^b([A-Z][A-Za-z0-9_]*)$').firstMatch(clean);
    if (boolMatch != null) {
      clean = boolMatch.group(1)!;
    }
    if (clean.isEmpty) return fallback;
    final snake = _toSnakeCaseToken(clean);
    if (snake.isEmpty) return fallback;
    return RegExp(r'^[0-9]').hasMatch(snake) ? 'param_$snake' : snake;
  }

  /// Normalizes `§04` tuning units into Godot 4 canonical units (`m`, `m/s`, `px`, `px/s`, `deg`, `s`, `hp`, `x`, `%`, `count`, `bool`).
  static String normalizeGodotUnit(
    String key,
    String rawUnit, {
    GodotProjectDimension dimension = GodotProjectDimension.dim3d,
  }) {
    final unit = rawUnit.trim().toLowerCase();
    final speedUnit = dimension.speedUnit;
    final distUnit = dimension.distanceUnit;
    if (unit.isNotEmpty) {
      if (unit == 'cm/s' ||
          unit == 'uu/s' ||
          unit == 'mps' ||
          unit == 'm/s' ||
          unit == 'px/s' ||
          unit == 'pixels/s') {
        return speedUnit;
      }
      if (unit == 'cm' ||
          unit == 'uu' ||
          unit == 'm' ||
          unit == 'meter' ||
          unit == 'meters' ||
          unit == 'px' ||
          unit == 'pixel' ||
          unit == 'pixels') {
        return distUnit;
      }
      if (unit == 'degrees' || unit == 'degree' || unit == 'deg') {
        return 'deg';
      }
      if (unit == 'sec' || unit == 'secs' || unit == 'seconds' || unit == 's') {
        return 's';
      }
      if (unit == 'pct' || unit == 'percent' || unit == '%') {
        return '%';
      }
      if (unit == 'boolean' || unit == 'bool') {
        return 'bool';
      }
      return unit;
    }

    final lowerKey = sanitizeTuningKey(key, fallback: '').toLowerCase();
    if (lowerKey.contains('speed') ||
        lowerKey.contains('velocity') ||
        lowerKey.contains('accel') ||
        lowerKey.contains('decel')) {
      return speedUnit;
    }
    if (lowerKey.contains('distance') ||
        lowerKey.contains('range') ||
        lowerKey.contains('radius') ||
        lowerKey.contains('height') ||
        lowerKey.contains('width') ||
        lowerKey.contains('length') ||
        lowerKey.contains('offset') ||
        lowerKey.contains('reach')) {
      return distUnit;
    }
    if (lowerKey.contains('cooldown') ||
        lowerKey.contains('duration') ||
        lowerKey.contains('time') ||
        lowerKey.contains('delay') ||
        lowerKey.contains('interval') ||
        lowerKey.contains('window')) {
      return 's';
    }
    if (lowerKey.contains('angle') ||
        lowerKey.contains('pitch') ||
        lowerKey.contains('yaw') ||
        lowerKey.contains('fov') ||
        lowerKey.contains('arc')) {
      return 'deg';
    }
    if (lowerKey.contains('hp') ||
        lowerKey.contains('health') ||
        lowerKey.contains('damage') ||
        lowerKey.contains('armor') ||
        lowerKey.contains('shield')) {
      return 'hp';
    }
    if (lowerKey.contains('count') ||
        lowerKey.contains('waves') ||
        lowerKey.contains('charges') ||
        lowerKey.contains('ammo') ||
        lowerKey.contains('max_enemies')) {
      return 'count';
    }
    if (lowerKey.contains('mult') ||
        lowerKey.contains('scale') ||
        lowerKey.contains('zoom')) {
      return 'x';
    }
    return '';
  }

  /// Infers GDScript `@export` type hint for `§04` tuning lines (`float`, `int`, `bool`).
  static String inferGodotPropertyType(String value, String unit) {
    final cleanVal = value.trim().toLowerCase();
    final cleanUnit = unit.trim().toLowerCase();
    if (cleanUnit == 'bool' ||
        cleanUnit == 'boolean' ||
        cleanVal == 'true' ||
        cleanVal == 'false') {
      return 'bool';
    }
    if (cleanUnit == 'count' && RegExp(r'^-?\d+$').hasMatch(cleanVal)) {
      return 'int';
    }
    return 'float';
  }

  /// Ensures `§04` cuts start with `No [system]` and stay strictly literal.
  static String sanitizeExclusion(
    String raw, {
    GodotProjectDimension dimension = GodotProjectDimension.dim3d,
  }) {
    final clean = sanitizeLine(raw, dimension: dimension);
    if (clean.isEmpty) return '';
    if (clean.toLowerCase().startsWith('no ')) return clean;
    return 'No $clean';
  }

  /// Clamps `v0.1` Epics to `maxEpics` and strips menu/save/wave bloat from `v0.1`.
  static List<EpicSpec> clampV01InitialEpics(
    List<EpicSpec> epics, {
    int maxEpics = 4,
    GodotProjectDimension dimension = GodotProjectDimension.dim3d,
  }) {
    final filtered = epics
        .where((ep) {
          final lower = ep.title.toLowerCase();
          final isMetaMenu = (lower.contains('main menu') ||
                  lower.contains('save slot') ||
                  lower.contains('skill tree') ||
                  lower.contains('settings modal') ||
                  lower.contains('multiplayer lobby')) &&
              !lower.contains('combat');
          return !isMetaMenu;
        })
        .take(maxEpics)
        .toList();

    final source = filtered.isNotEmpty
        ? filtered
        : epics.take(maxEpics).toList();
    return [
      for (int i = 0; i < source.length; i++)
        sanitizeEpicSpec(
          source[i],
          dimension: dimension,
          forceCode: EpicSpec.formatCode(i + 1),
          forceReleaseVersion: 'v0.1',
          forceLifecycle: i == 0 ? EpicLifecycle.active : EpicLifecycle.queued,
        ),
    ];
  }

  static List<String> _sanitizeStringList(
    List<String> items,
    GodotProjectDimension dim,
  ) =>
      [
        for (final item in items)
          if (sanitizeLine(item, dimension: dim).isNotEmpty)
            sanitizeLine(item, dimension: dim),
      ];

  static List<EpicControlBinding> _sanitizeControls(
    List<EpicControlBinding> items,
    GodotProjectDimension dim,
  ) =>
      [
        for (final c in items)
          EpicControlBinding(
            action: _toSnakeCaseToken(
              c.action.replaceAll(RegExp(r'^IA_', caseSensitive: false), ''),
            ),
            trigger: sanitizeLine(c.trigger, dimension: dim),
            rule: sanitizeLine(c.rule, dimension: dim),
          ),
      ];

  static List<EpicTuningParam> _sanitizeTuning(
    List<EpicTuningParam> items,
    GodotProjectDimension dim,
  ) =>
      [
        for (int i = 0; i < items.length; i++)
          () {
            final cleanKey = sanitizeTuningKey(
              items[i].key,
              fallback: 'param_${i + 1}',
            );
            final rawUnit = items[i].unit.trim().toLowerCase();
            var cleanVal = items[i].value.trim();
            if (dim == GodotProjectDimension.dim3d &&
                (rawUnit == 'cm' || rawUnit == 'cm/s')) {
              final numVal = double.tryParse(cleanVal);
              if (numVal != null) {
                cleanVal = _formatCleanNum(numVal / 100.0);
              }
            }
            return EpicTuningParam(
              key: cleanKey,
              value: cleanVal,
              unit: normalizeGodotUnit(
                cleanKey,
                items[i].unit,
                dimension: dim,
              ),
            );
          }(),
      ];

  static List<EpicPieCheck> _sanitizeChecks(
    List<EpicPieCheck> items,
    GodotProjectDimension dim,
  ) =>
      [
        for (final chk in items)
          EpicPieCheck(
            id: chk.id,
            text: sanitizeLine(chk.text, dimension: dim),
            passed: chk.passed,
          ),
      ];

  static List<EpicPieFix> _sanitizeFixes(
    List<EpicPieFix> items,
    GodotProjectDimension dim,
  ) =>
      [
        for (final fx in items)
          EpicPieFix(
            id: fx.id,
            text: sanitizeLine(fx.text, dimension: dim),
            resolved: fx.resolved,
            createdAtMs: fx.createdAtMs,
          ),
      ];

  static FeatureSpec sanitizeFeatureSpec(
    FeatureSpec spec, {
    GodotProjectDimension dimension = GodotProjectDimension.dim3d,
    String? forceCode,
  }) {
    final out = spec.deepCopy();
    if (forceCode != null && forceCode.trim().isNotEmpty) {
      out.code = forceCode.trim();
    } else if (out.code.trim().isEmpty) {
      out.code = 'F01';
    }
    out.title = sanitizeLine(out.title, dimension: dimension);
    out.goal = sanitizeLine(out.goal, dimension: dimension);
    out.sliceTime = sanitizeLine(out.sliceTime, dimension: dimension);
    out.releaseDelta = sanitizeLine(out.releaseDelta, dimension: dimension);
    out.inScope = _sanitizeStringList(out.inScope, dimension);
    out.doneWhen = _sanitizeStringList(out.doneWhen, dimension);
    out.controls = _sanitizeControls(out.controls, dimension);
    out.tuning = _sanitizeTuning(out.tuning, dimension);
    out.cues = _sanitizeStringList(out.cues, dimension);
    out.checks = _sanitizeChecks(out.checks, dimension);
    out.releaseDeltaChecks = _sanitizeChecks(out.releaseDeltaChecks, dimension);
    out.fixes = _sanitizeFixes(out.fixes, dimension);
    return out;
  }

  static EpicSpec sanitizeEpicSpec(
    EpicSpec spec, {
    GodotProjectDimension dimension = GodotProjectDimension.dim3d,
    String? forceCode,
    String? forceReleaseVersion,
    EpicLifecycle? forceLifecycle,
  }) {
    final out = spec.deepCopy();
    if (forceCode != null && forceCode.trim().isNotEmpty) {
      out.code = forceCode.trim();
    }
    if (forceReleaseVersion != null && forceReleaseVersion.trim().isNotEmpty) {
      out.releaseVersion = forceReleaseVersion.trim();
    }
    if (forceLifecycle != null) {
      out.lifecycle = forceLifecycle;
    }

    out.title = sanitizeLine(out.title, dimension: dimension);
    out.coreLoopBeat = sanitizeLine(out.coreLoopBeat, dimension: dimension);
    out.goal = sanitizeLine(out.goal, dimension: dimension);
    out.inScope = _sanitizeStringList(out.inScope, dimension);
    out.doneWhen = _sanitizeStringList(out.doneWhen, dimension);
    out.sceneOwnership = [
      for (final o in out.sceneOwnership)
        if (sanitizeLine(o.path, dimension: dimension).isNotEmpty)
          EpicSceneOwnership(
            path: sanitizeLine(o.path, dimension: dimension),
            role: sanitizeLine(o.role, dimension: dimension),
          ),
    ];
    out.levelStaging = sanitizeLine(out.levelStaging, dimension: dimension);
    out.links = _sanitizeStringList(out.links, dimension);
    out.outOfScope = [
      for (final o in out.outOfScope)
        if (sanitizeExclusion(o, dimension: dimension).isNotEmpty)
          sanitizeExclusion(o, dimension: dimension),
    ];
    out.controls = _sanitizeControls(out.controls, dimension);
    out.states = _sanitizeStringList(out.states, dimension);
    out.interrupts = _sanitizeStringList(out.interrupts, dimension);
    out.tuning = _sanitizeTuning(out.tuning, dimension);
    out.feedback = _sanitizeStringList(out.feedback, dimension);
    out.checks = _sanitizeChecks(out.checks, dimension);
    out.fixes = _sanitizeFixes(out.fixes, dimension);
    out.features = [
      for (int i = 0; i < out.features.length; i++)
        sanitizeFeatureSpec(
          out.features[i],
          dimension: dimension,
          forceCode: out.features[i].code.trim().isEmpty
              ? FeatureSpec.formatCode(i + 1)
              : null,
        ),
    ];
    out.baselineSummary = _sanitizeStringList(out.baselineSummary, dimension);
    out.upgradeDeltas = _sanitizeStringList(out.upgradeDeltas, dimension);
    return out;
  }

  static ProjectConceptBlueprint sanitizeConceptBlueprint(
    ProjectConceptBlueprint raw,
  ) {
    final out = raw.deepCopy();
    final dim = out.dimension;
    out.pitch = sanitizeLine(out.pitch, dimension: dim);
    out.coreLoop = [
      for (final beat in out.coreLoop)
        if (sanitizeLine(beat, dimension: dim).isNotEmpty)
          sanitizeLine(beat, dimension: dim),
    ];
    out.cameraContract = sanitizeLine(out.cameraContract, dimension: dim);
    out.characterScale = sanitizeLine(out.characterScale, dimension: dim);
    out.inputContract = sanitizeLine(out.inputContract, dimension: dim);
    out.assetPolicy = sanitizeLine(out.assetPolicy, dimension: dim);
    out.cameraDecisionOptions = [
      for (final opt in out.cameraDecisionOptions)
        ConceptSectionOption(
          id: opt.id,
          label: sanitizeLine(opt.label, dimension: dim),
          contractValue: sanitizeLine(opt.contractValue, dimension: dim),
          note: opt.note == null ? null : sanitizeLine(opt.note!, dimension: dim),
        ),
    ];
    out.pillars = [
      for (final p in out.pillars)
        if (sanitizeLine(p, dimension: dim).isNotEmpty)
          sanitizeLine(p, dimension: dim),
    ];
    out.tradeOffs = [
      for (final t in out.tradeOffs)
        TradeOffRule(
          prefer: sanitizeLine(t.prefer, dimension: dim),
          avoid: sanitizeLine(t.avoid, dimension: dim),
        ),
    ];
    out.outOfScope = [
      for (final cut in out.outOfScope)
        if (sanitizeExclusion(cut, dimension: dim).isNotEmpty)
          sanitizeExclusion(cut, dimension: dim),
    ];
    out.releaseDoneWhen = sanitizeLine(out.releaseDoneWhen, dimension: dim);
    out.initialEpics = clampV01InitialEpics(out.initialEpics, dimension: dim);
    out.v02NewPool = [
      for (int i = 0; i < out.v02NewPool.length; i++)
        sanitizeEpicSpec(out.v02NewPool[i], dimension: dim),
    ];
    out.v02Presets = [
      for (final p in out.v02Presets)
        ReleaseDirectionPreset(
          id: p.id,
          label: sanitizeLine(p.label, dimension: dim),
          description: sanitizeLine(p.description, dimension: dim),
          upgradeIds: List<String>.from(p.upgradeIds),
          newEpicIds: List<String>.from(p.newEpicIds),
        ),
    ];
    out.v02UpgradesByLineageKey = {
      for (final entry in out.v02UpgradesByLineageKey.entries)
        entry.key.toLowerCase(): [
          for (final u in entry.value)
            EpicUpgradeOption(
              id: u.id,
              text: sanitizeLine(u.text, dimension: dim),
              targetFeatureCode: u.targetFeatureCode,
              chosen: u.chosen,
            ),
        ],
    };
    out.v02NewFeaturesByLineageKey = {
      for (final entry in out.v02NewFeaturesByLineageKey.entries)
        entry.key.toLowerCase(): [
          for (final f in entry.value)
            sanitizeFeatureSpec(f, dimension: dim),
        ],
    };
    return out;
  }
}
