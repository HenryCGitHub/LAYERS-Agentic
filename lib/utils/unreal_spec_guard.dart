import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';

/// Unreal Engine 5 specification guard, sanitizer & `v0.1` scope protector.
/// Flags and rewrites Godot/Unity terms into canonical UE5 assets, `cm`/`cm/s` units,
/// `PascalCase` tuning keys, and `IA_*` Enhanced Input bindings.
class UnrealSpecGuard {
  static final RegExp _nonUnrealLeakPattern = RegExp(
    r'\b(godot(?:\s*4(?:\.\d+)?)?|gdscript|characterbody[23]d|node[23]d|area[23]d|springarm3d|camera[23]d|collisionshape[23]d|raycast[23]d|gpuparticles[23]d|cpuparticles[23]d|csgbox3d|csgcylinder3d|csgshape3d|meshinstance3d|polygon2d|colorrect|canvaslayer|inputmap|packedscene|project\.godot|gameobjects?|monobehaviour|serializefield|prefabs?)\b|\.(?:tscn|gd|tres|prefab)\b|\bres://[^\s]+|@export(?:\s+var\b)?|\b(?:m|px)/s\b|(?:(?:\b|\d+x)\d+(?:\.\d+)?\s*(?:m|px))(?=$|[\s.,;:)!?])',
    caseSensitive: false,
  );

  static final RegExp _leadingBulletPattern =
      RegExp(r'^(?:[\-\*]\s+|\u2022\s*)+');

  static const Set<String> _mapStemKeywords = <String>{
    'arena', 'level', 'lvl', 'map', 'room', 'track', 'course', 'proto',
    'world', 'yard', 'keep', 'station', 'gym', 'pit',
  };

  static const List<(String, String)> _bannedPhraseReplacements = [
    ('end-to-end loop', 'core loop'),
    ('end-to-end', 'full'),
    ('unified pipeline', 'pipeline'),
  ];

  static const List<String> _bannedFillerPhrases = [
    'unified',
    'seamlessly',
    'synergistic',
    'synergy',
  ];

  static const List<(String, String)> _jargonReplacements = [
    ('leveraging', 'using'), ('leveraged', 'used'), ('leverages', 'uses'),
    ('leverage', 'use'), ('validating', 'checking'), ('validates', 'checks'),
    ('validated', 'checked'), ('validate', 'check'), ('verified', 'checked'),
    ('delivering', 'producing'), ('delivered', 'produced'),
    ('delivers', 'produces'), ('deliver', 'produce'),
    ('husbandry', 'breeding'), ('homesteads', 'bases'),
    ('homestead', 'base'), ('expeditions', 'runs'), ('expedition', 'run'),
    ('ordinances', 'weapons'), ('ordinance', 'weaponry'),
  ];

  static String _formatCleanNum(double v) {
    if ((v - v.roundToDouble()).abs() < 0.001) return v.round().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _replaceCaseAware(String input, String fromWord, String toLower) {
    return input.replaceAllMapped(RegExp('\\b$fromWord\\b', caseSensitive: false), (m) {
      final matched = m.group(0) ?? '';
      if (matched.isNotEmpty &&
          matched[0] == matched[0].toUpperCase() &&
          matched[0] != matched[0].toLowerCase()) {
        return '${toLower[0].toUpperCase()}${toLower.substring(1)}';
      }
      return toLower;
    });
  }

  static bool containsEngineLeakage(String text) => _nonUnrealLeakPattern.hasMatch(text);

  static String _stripLeadingTag(String pascal, String tagLower) =>
      pascal.length > tagLower.length && pascal.toLowerCase().startsWith(tagLower)
          ? pascal.substring(tagLower.length)
          : pascal;

  static String _convertAssetPath(
    String rawPath,
    String extLower,
    UnrealArchitectureMode mode,
  ) {
    final cleanStem = rawPath.split('/').last.trim();
    final pascal = toPascalCaseToken(cleanStem.isEmpty ? 'Asset' : cleanStem);
    if (extLower == 'tscn') {
      final isMap = _mapStemKeywords.any((kw) => cleanStem.toLowerCase().contains(kw));
      if (isMap) return '/Game/Maps/Lvl_${_stripLeadingTag(pascal, 'lvl')}.umap';
      return '/Game/Blueprints/BP_${_stripLeadingTag(pascal, 'bp')}';
    }
    if (extLower == 'gd') {
      return mode == UnrealArchitectureMode.cppHybrid
          ? 'Source/$pascal.cpp'
          : '/Game/Blueprints/BP_${_stripLeadingTag(pascal, 'bp')}';
    }
    return '/Game/Data/DA_${_stripLeadingTag(pascal, 'da')}';
  }

  /// Strips Godot/Unity terms or filler and converts metric/pixel numbers to Unreal `cm`/`cm/s`.
  static String sanitizeLine(
    String raw, {
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
  }) {
    var out = raw.trim().replaceFirst(_leadingBulletPattern, '').trim();
    if (out.isEmpty) return '';

    final isHybrid = mode == UnrealArchitectureMode.cppHybrid;
    out = out.replaceAllMapped(
      RegExp(r'res://([A-Za-z0-9_/\-]+)\.(tscn|gd|tres)\b', caseSensitive: false),
      (m) => _convertAssetPath(
        m.group(1) ?? 'asset',
        (m.group(2) ?? 'tscn').toLowerCase(),
        mode,
      ),
    );
    out = out.replaceAllMapped(
      RegExp(r'(?<![/A-Za-z0-9_])([A-Za-z0-9_\-]+)\.(tscn|gd|tres)\b', caseSensitive: false),
      (m) => _convertAssetPath(
        m.group(1) ?? 'asset',
        (m.group(2) ?? 'tscn').toLowerCase(),
        mode,
      ),
    );
    out = out.replaceAllMapped(RegExp(r'res://([A-Za-z0-9_/\-]+)'), (m) => '/Game/${m.group(1)}');
    out = out.replaceAllMapped(
      RegExp(r'@export\s+var\s+([A-Za-z0-9_]+)', caseSensitive: false),
      (m) => sanitizeTuningKey(m.group(1) ?? 'Param'),
    );

    final replacements = <RegExp, String>{
      RegExp(r'\bGodot(?:\s*4(?:\.\d+)?)?\b', caseSensitive: false): 'Unreal Engine 5',
      RegExp(r'\bUnity(?:\s*3D|\s*2D)?\b', caseSensitive: false): 'Unreal Engine 5',
      RegExp(r'\bGDScript(?:\s*2\.0)?\b', caseSensitive: false): isHybrid ? 'C++ / Blueprint' : 'Blueprint',
      RegExp(r'\bproject\.godot\b', caseSensitive: false): 'Config/DefaultInput.ini',
      RegExp(r'\bCharacterBody(?:3D|2D)\b'): 'ACharacter',
      RegExp(r'\bNode(?:3D|2D)\b'): 'AActor',
      RegExp(r'\bArea(?:3D|2D)\b'): 'UBoxComponent',
      RegExp(r'\bCollisionShape(?:3D|2D)\b'): 'UCapsuleComponent',
      RegExp(r'\bSpringArm3D\b'): 'USpringArmComponent',
      RegExp(r'\bCamera(?:3D|2D)\b'): 'UCameraComponent',
      RegExp(r'\bRayCast(?:3D|2D)\b'): 'LineTraceSingleByChannel',
      RegExp(r'\b(?:GPU|CPU)Particles(?:3D|2D)\b'): 'Niagara',
      RegExp(r'\b(?:CSGBox3D|CSGCylinder3D|CSGShape3D|MeshInstance3D|Polygon2D|ColorRect)\b'): 'UStaticMeshComponent',
      RegExp(r'\b(?:StandardMaterial3D|CanvasItemMaterial)\b'): 'UMaterialInstanceDynamic',
      RegExp(r'\b(?:CanvasLayer|Control HUD)\b', caseSensitive: false): 'UMG Widget',
      RegExp(r'\bInputMap Actions?\b', caseSensitive: false): 'Enhanced Input Action',
      RegExp(r'\bInputMap\b', caseSensitive: false): 'Enhanced Input',
      RegExp(r'\bPackedScenes\b', caseSensitive: false): 'Blueprint Classes',
      RegExp(r'\bPackedScene\b', caseSensitive: false): 'Blueprint Class',
      RegExp(r'\bPrefabs\b', caseSensitive: false): 'Blueprint Classes',
      RegExp(r'\bPrefab\b', caseSensitive: false): 'Blueprint Class',
      RegExp(r'\bGameObjects\b', caseSensitive: false): 'AActors',
      RegExp(r'\bGameObject\b', caseSensitive: false): 'AActor',
      RegExp(r'\bMonoBehaviour\b', caseSensitive: false): 'UActorComponent',
      RegExp(r'\bSerializeField\b', caseSensitive: false): 'UPROPERTY(EditAnywhere)',
      RegExp(r'@export\b', caseSensitive: false): isHybrid ? 'UPROPERTY(EditAnywhere)' : 'Exposed BP Var',
      RegExp(r'\bResource\s*\(\.tres\)', caseSensitive: false): 'PrimaryDataAsset',
      RegExp(r'\.prefab\b', caseSensitive: false): 'Blueprint Class',
      RegExp(r'\bGodot Debugger\b', caseSensitive: false): 'Output Log',
      RegExp(r'\bSpawnPoint\b', caseSensitive: false): 'APlayerStart',
    };
    for (final entry in replacements.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }

    for (final (unitSuffix, factor) in const [('m', 100.0), ('px', 2.5)]) {
      out = out.replaceAllMapped(
        RegExp('(\\d+(?:\\.\\d+)?)\\s*x\\s*(\\d+(?:\\.\\d+)?)\\s*$unitSuffix(?=\$|[\\s.,;:)!?])', caseSensitive: false),
        (m) => '${_formatCleanNum((double.tryParse(m.group(1) ?? '') ?? 0) * factor)}x${_formatCleanNum((double.tryParse(m.group(2) ?? '') ?? 0) * factor)} cm',
      );
      out = out.replaceAllMapped(
        RegExp('\\b(\\d+(?:\\.\\d+)?)\\s*$unitSuffix/s\\b', caseSensitive: false),
        (m) => '${_formatCleanNum((double.tryParse(m.group(1) ?? '') ?? 0) * factor)} cm/s',
      );
      out = out.replaceAllMapped(
        RegExp('(?<=^|[\\s(~])(\\d+(?:\\.\\d+)?)\\s*$unitSuffix(?=\$|[\\s.,;:)!?])', caseSensitive: false),
        (m) => '${_formatCleanNum((double.tryParse(m.group(1) ?? '') ?? 0) * factor)} cm',
      );
    }
    out = out.replaceAll(RegExp(r'\b(?:m|px)/s\b', caseSensitive: false), 'cm/s');

    for (final (fromPhrase, toPhrase) in _bannedPhraseReplacements) {
      out = _replaceCaseAware(out, RegExp.escape(fromPhrase), toPhrase);
    }
    out = out.replaceAllMapped(
      RegExp(r'(?<![/._A-Za-z0-9])st' 'aging(?![/._A-Za-z0-9])', caseSensitive: false),
      (m) => (m.group(0) ?? '').startsWith(RegExp(r'[A-Z]')) ? 'Layout' : 'layout',
    );
    for (final (fromWord, toLower) in _jargonReplacements) {
      out = _replaceCaseAware(out, fromWord, toLower);
    }
    for (final filler in _bannedFillerPhrases) {
      out = out.replaceAll(RegExp('\\b${RegExp.escape(filler)}\\b', caseSensitive: false), '');
    }

    out = out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    out = out.replaceAllMapped(RegExp(r'\s+(?:and|or)\s*([.,;:])', caseSensitive: false), (m) => m.group(1)!);
    return out.replaceAllMapped(RegExp(r'\s+([.,;:])'), (m) => m.group(1)!).trim();
  }

  static String toPascalCaseToken(String raw) {
    final spaced = raw
        .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m.group(1)}_${m.group(2)}')
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m.group(1)}_${m.group(2)}')
        .replaceAllMapped(RegExp(r'([a-zA-Z])(\d)'), (m) => '${m.group(1)}_${m.group(2)}');
    final tokens = spaced.split(RegExp(r'[^A-Za-z0-9]+')).map((t) => t.trim()).where((t) => t.isNotEmpty);
    return tokens.map((t) => '${t[0].toUpperCase()}${t.substring(1).toLowerCase()}').join();
  }

  /// Normalizes a tuning key into an Unreal `PascalCase` variable name (`MaxWalkSpeed`).
  static String sanitizeTuningKey(String rawKey, {String fallback = 'TuningParam'}) {
    var clean = rawKey.trim().replaceAll(RegExp(r'^@export\s+var\s+', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
    final boolMatch = RegExp(r'^b([A-Z][A-Za-z0-9_]*)$').firstMatch(clean);
    if (boolMatch != null) clean = boolMatch.group(1)!;
    if (clean.isEmpty) return fallback;
    final pascal = toPascalCaseToken(clean);
    if (pascal.isEmpty) return fallback;
    return RegExp(r'^[0-9]').hasMatch(pascal) ? 'Param$pascal' : pascal;
  }

  /// Normalizes an input action name into Unreal Enhanced Input format (`IA_ClawDash`).
  static String sanitizeInputActionName(String rawAction) {
    final stripped = rawAction.trim().replaceFirst(RegExp(r'^IA_', caseSensitive: false), '');
    final pascal = toPascalCaseToken(stripped);
    return pascal.isEmpty ? 'IA_PrimaryAction' : 'IA_$pascal';
  }

  static String scaleTuningValue(String rawValue, String rawUnit) {
    final cleanVal = rawValue.trim();
    final unit = rawUnit.trim().toLowerCase();
    final numVal = double.tryParse(cleanVal);
    if (numVal == null) return cleanVal;
    if (const {'m', 'meter', 'meters', 'mps', 'm/s'}.contains(unit)) {
      return _formatCleanNum(numVal * 100.0);
    }
    if (const {'px', 'pixel', 'pixels', 'px/s', 'pixels/s'}.contains(unit)) {
      return _formatCleanNum(numVal * 2.5);
    }
    return cleanVal;
  }

  /// Normalizes tuning units into canonical Unreal Engine units (`cm`, `cm/s`, `deg`, `s`, `hp`, `x`, `%`, `count`, `bool`).
  static String normalizeUnrealUnit(String key, String rawUnit) {
    final unit = rawUnit.trim().toLowerCase();
    if (unit.isNotEmpty) {
      if (const {'cm/s', 'uu/s', 'mps', 'm/s', 'px/s', 'pixels/s'}.contains(unit)) return 'cm/s';
      if (const {'cm', 'uu', 'm', 'meter', 'meters', 'px', 'pixel', 'pixels'}.contains(unit)) return 'cm';
      if (const {'degrees', 'degree', 'deg'}.contains(unit)) return 'deg';
      if (const {'sec', 'secs', 'seconds', 's'}.contains(unit)) return 's';
      if (const {'pct', 'percent', '%'}.contains(unit)) return '%';
      if (unit == 'boolean' || unit == 'bool') return 'bool';
      return unit;
    }

    final lowerKey = sanitizeTuningKey(key, fallback: '').toLowerCase();
    if (const ['speed', 'velocity', 'accel', 'decel'].any(lowerKey.contains)) return 'cm/s';
    if (const ['distance', 'range', 'radius', 'height', 'width', 'length', 'offset', 'reach'].any(lowerKey.contains)) return 'cm';
    if (const ['cooldown', 'duration', 'time', 'delay', 'interval', 'window'].any(lowerKey.contains)) return 's';
    if (const ['angle', 'pitch', 'yaw', 'fov', 'arc'].any(lowerKey.contains)) return 'deg';
    if (const ['hp', 'health', 'damage', 'armor', 'shield'].any(lowerKey.contains)) return 'hp';
    if (const ['count', 'waves', 'charges', 'ammo', 'maxenemies'].any(lowerKey.contains)) return 'count';
    if (const ['mult', 'scale', 'zoom'].any(lowerKey.contains)) return 'x';
    return '';
  }

  /// Infers Unreal Engine property type (`float`, `int32`, `bool`).
  static String inferUnrealPropertyType(String value, String unit) {
    final cleanVal = value.trim().toLowerCase();
    final cleanUnit = unit.trim().toLowerCase();
    if (cleanUnit == 'bool' || cleanUnit == 'boolean' || cleanVal == 'true' || cleanVal == 'false') {
      return 'bool';
    }
    if (cleanUnit == 'count' && RegExp(r'^-?\d+$').hasMatch(cleanVal)) return 'int32';
    return 'float';
  }

  /// Ensures `§04` cuts start with `No [system]` and stay strictly literal.
  static String sanitizeExclusion(
    String raw, {
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
  }) {
    final clean = sanitizeLine(raw, mode: mode);
    if (clean.isEmpty) return '';
    return clean.toLowerCase().startsWith('no ') ? clean : 'No $clean';
  }

  /// Clamps `v0.1` Epics to `maxEpics` and strips menu/save/wave bloat from `v0.1`.
  static List<EpicSpec> clampV01InitialEpics(
    List<EpicSpec> epics, {
    int maxEpics = 4,
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
  }) {
    final filtered = epics.where((ep) {
      final lower = ep.title.toLowerCase();
      final isMetaMenu = (lower.contains('main menu') ||
              lower.contains('save slot') ||
              lower.contains('skill tree') ||
              lower.contains('settings modal') ||
              lower.contains('multiplayer lobby')) &&
          !lower.contains('combat');
      return !isMetaMenu;
    }).take(maxEpics).toList();
    final source = filtered.isNotEmpty ? filtered : epics.take(maxEpics).toList();
    return [
      for (int i = 0; i < source.length; i++)
        sanitizeEpicSpec(
          source[i],
          mode: mode,
          forceCode: EpicSpec.formatCode(i + 1),
          forceReleaseVersion: 'v0.1',
          forceLifecycle: i == 0 ? EpicLifecycle.active : EpicLifecycle.queued,
        ),
    ];
  }

  static List<String> _sanitizeList(List<String> items, UnrealArchitectureMode mode) => [
        for (final item in items)
          if (sanitizeLine(item, mode: mode).isNotEmpty) sanitizeLine(item, mode: mode),
      ];

  static List<EpicControlBinding> _sanitizeControls(List<EpicControlBinding> items, UnrealArchitectureMode mode) => [
        for (final c in items)
          EpicControlBinding(
            action: sanitizeInputActionName(c.action),
            trigger: sanitizeLine(c.trigger, mode: mode),
            rule: sanitizeLine(c.rule, mode: mode),
          ),
      ];

  static List<EpicTuningParam> _sanitizeTuning(List<EpicTuningParam> items) => [
        for (int i = 0; i < items.length; i++)
          EpicTuningParam(
            key: sanitizeTuningKey(items[i].key, fallback: 'Param${i + 1}'),
            value: scaleTuningValue(items[i].value, items[i].unit),
            unit: normalizeUnrealUnit(items[i].key, items[i].unit),
          ),
      ];

  static List<EpicPieCheck> _sanitizeChecks(List<EpicPieCheck> items, UnrealArchitectureMode mode) => [
        for (final chk in items) EpicPieCheck(id: chk.id, text: sanitizeLine(chk.text, mode: mode), passed: chk.passed),
      ];

  static List<EpicPieFix> _sanitizeFixes(List<EpicPieFix> items, UnrealArchitectureMode mode) => [
        for (final fx in items)
          EpicPieFix(id: fx.id, text: sanitizeLine(fx.text, mode: mode), resolved: fx.resolved, createdAtMs: fx.createdAtMs),
      ];

  static FeatureSpec sanitizeFeatureSpec(
    FeatureSpec spec, {
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
    String? forceCode,
  }) {
    final out = spec.deepCopy();
    if (forceCode != null && forceCode.trim().isNotEmpty) {
      out.code = forceCode.trim();
    } else if (out.code.trim().isEmpty) {
      out.code = 'F01';
    }
    out.title = sanitizeLine(out.title, mode: mode);
    out.goal = sanitizeLine(out.goal, mode: mode);
    out.sliceTime = sanitizeLine(out.sliceTime, mode: mode);
    out.releaseDelta = sanitizeLine(out.releaseDelta, mode: mode);
    out.inScope = _sanitizeList(out.inScope, mode);
    out.doneWhen = _sanitizeList(out.doneWhen, mode);
    out.controls = _sanitizeControls(out.controls, mode);
    out.tuning = _sanitizeTuning(out.tuning);
    out.cues = _sanitizeList(out.cues, mode);
    out.checks = _sanitizeChecks(out.checks, mode);
    out.releaseDeltaChecks = _sanitizeChecks(out.releaseDeltaChecks, mode);
    out.fixes = _sanitizeFixes(out.fixes, mode);
    return out;
  }

  static EpicSpec sanitizeEpicSpec(
    EpicSpec spec, {
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
    String? forceCode,
    String? forceReleaseVersion,
    EpicLifecycle? forceLifecycle,
  }) {
    final out = spec.deepCopy();
    if (forceCode != null && forceCode.trim().isNotEmpty) out.code = forceCode.trim();
    if (forceReleaseVersion != null && forceReleaseVersion.trim().isNotEmpty) {
      out.releaseVersion = forceReleaseVersion.trim();
    }
    if (forceLifecycle != null) out.lifecycle = forceLifecycle;

    out.title = sanitizeLine(out.title, mode: mode);
    out.coreLoopBeat = sanitizeLine(out.coreLoopBeat, mode: mode);
    out.goal = sanitizeLine(out.goal, mode: mode);
    out.inScope = _sanitizeList(out.inScope, mode);
    out.doneWhen = _sanitizeList(out.doneWhen, mode);
    out.sceneOwnership = [
      for (final o in out.sceneOwnership)
        if (sanitizeLine(o.path, mode: mode).isNotEmpty)
          EpicSceneOwnership(path: sanitizeLine(o.path, mode: mode), role: sanitizeLine(o.role, mode: mode)),
    ];
    out.levelStaging = sanitizeLine(out.levelStaging, mode: mode);
    out.links = _sanitizeList(out.links, mode);
    out.outOfScope = [
      for (final o in out.outOfScope)
        if (sanitizeExclusion(o, mode: mode).isNotEmpty) sanitizeExclusion(o, mode: mode),
    ];
    out.controls = _sanitizeControls(out.controls, mode);
    out.states = _sanitizeList(out.states, mode);
    out.stateFlow = _sanitizeList(out.stateFlow, mode);
    out.interrupts = _sanitizeList(out.interrupts, mode);
    out.interruptRules = _sanitizeList(out.interruptRules, mode);
    out.tuning = _sanitizeTuning(out.tuning);
    out.feedback = _sanitizeList(out.feedback, mode);
    out.checks = _sanitizeChecks(out.checks, mode);
    out.fixes = _sanitizeFixes(out.fixes, mode);
    out.features = [
      for (int i = 0; i < out.features.length; i++)
        sanitizeFeatureSpec(
          out.features[i],
          mode: mode,
          forceCode: out.features[i].code.trim().isEmpty ? FeatureSpec.formatCode(i + 1) : null,
        ),
    ];
    out.baselineSummary = _sanitizeList(out.baselineSummary, mode);
    out.upgradeDeltas = _sanitizeList(out.upgradeDeltas, mode);
    return out;
  }

  static ProjectConceptBlueprint sanitizeConceptBlueprint({
    required ProjectConceptBlueprint raw,
    UnrealArchitectureMode? modeOverride,
  }) {
    final out = raw.deepCopy();
    final mode = modeOverride ?? UnrealArchitectureMode.blueprint;
    out.pitch = sanitizeLine(out.pitch, mode: mode);
    out.coreLoop = _sanitizeList(out.coreLoop, mode);
    out.cameraContract = sanitizeLine(out.cameraContract, mode: mode);
    out.characterScale = sanitizeLine(out.characterScale, mode: mode);
    out.inputContract = sanitizeLine(out.inputContract, mode: mode);
    out.assetPolicy = sanitizeLine(out.assetPolicy, mode: mode);
    out.cameraDecisionOptions = [
      for (final opt in out.cameraDecisionOptions)
        ConceptSectionOption(
          id: opt.id,
          label: sanitizeLine(opt.label, mode: mode),
          contractValue: sanitizeLine(opt.contractValue, mode: mode),
          note: opt.note == null ? null : sanitizeLine(opt.note!, mode: mode),
        ),
    ];
    out.pillars = _sanitizeList(out.pillars, mode);
    out.tradeOffs = [
      for (final t in out.tradeOffs)
        TradeOffRule(prefer: sanitizeLine(t.prefer, mode: mode), avoid: sanitizeLine(t.avoid, mode: mode)),
    ];
    out.outOfScope = [
      for (final cut in out.outOfScope)
        if (sanitizeExclusion(cut, mode: mode).isNotEmpty) sanitizeExclusion(cut, mode: mode),
    ];
    out.releaseDoneWhen = sanitizeLine(out.releaseDoneWhen, mode: mode);
    out.initialEpics = clampV01InitialEpics(out.initialEpics, mode: mode);
    out.v02NewPool = [for (final ep in out.v02NewPool) sanitizeEpicSpec(ep, mode: mode)];
    out.v02Presets = [
      for (final p in out.v02Presets)
        ReleaseDirectionPreset(
          id: p.id,
          label: sanitizeLine(p.label, mode: mode),
          description: sanitizeLine(p.description, mode: mode),
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
              text: sanitizeLine(u.text, mode: mode),
              targetFeatureCode: u.targetFeatureCode,
              chosen: u.chosen,
            ),
        ],
    };
    out.v02NewFeaturesByLineageKey = {
      for (final entry in out.v02NewFeaturesByLineageKey.entries)
        entry.key.toLowerCase(): [for (final f in entry.value) sanitizeFeatureSpec(f, mode: mode)],
    };
    return out;
  }
}
