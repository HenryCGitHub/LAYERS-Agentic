import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';

/// Pure Unreal Engine specification guard, sanitizer & v0.1 scope validator.
/// Ensures zero Godot leakage, clean literal game-dev wording, and canonical `1 UU = 1 cm` units.
class UnrealSpecGuard {
  static final RegExp _godotLeakPattern = RegExp(
    r'\b(godot|gdscript|characterbody3d|characterbody2d|rigidbody3d|rigidbody2d|area3d|area2d|node3d|node2d|camera3d|camera2d|raycast3d|raycast2d|packedscene|_physics_process|gameobject|gameobjects|monobehaviour|serializefield|prefab|prefabs)\b|(?:\.prefab|\.tscn|\.gd)\b|\b(?:px|pixels)/s\b|\b\d+(?:\.\d+)?\s*(?:px|pixels)\b',
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

  static bool containsGodotLeakage(String text) {
    return _godotLeakPattern.hasMatch(text);
  }

  /// Strips Godot/Unity terms or buzzword padding and tightens to literal Unreal phrasing.
  static String sanitizeLine(String raw) {
    var out = raw.trim().replaceFirst(_leadingBulletPattern, '').trim();
    if (out.isEmpty) return '';

    final replacements = <RegExp, String>{
      RegExp(r'\bGDScript\b', caseSensitive: false): 'Blueprint / Verse',
      RegExp(r'\bGodot\b', caseSensitive: false): 'Unreal Engine',
      RegExp(r'\bCharacterBody3D\b', caseSensitive: false): 'ACharacter',
      RegExp(r'\bCharacterBody2D\b', caseSensitive: false): 'ACharacter',
      RegExp(r'\bRigidBody3D\b', caseSensitive: false): 'UPrimitiveComponent',
      RegExp(r'\bRigidBody2D\b', caseSensitive: false): 'UPrimitiveComponent',
      RegExp(r'\bArea3D\b', caseSensitive: false): 'UBoxComponent',
      RegExp(r'\bArea2D\b', caseSensitive: false): 'UBoxComponent',
      RegExp(r'\bNode3D\b', caseSensitive: false): 'AActor',
      RegExp(r'\bNode2D\b', caseSensitive: false): 'AActor',
      RegExp(r'\bCamera3D\b', caseSensitive: false): 'UCameraComponent',
      RegExp(r'\bCamera2D\b', caseSensitive: false): 'UCameraComponent',
      RegExp(r'\bRayCast3D\b', caseSensitive: false): 'LineTraceByChannel',
      RegExp(r'\bRayCast2D\b', caseSensitive: false): 'LineTraceByChannel',
      RegExp(r'\bPackedScene\b', caseSensitive: false): 'Blueprint Class',
      RegExp(r'\b_physics_process\b', caseSensitive: false): 'Tick',
      RegExp(r'\bGameObjects\b', caseSensitive: false): 'AActors',
      RegExp(r'\bGameObject\b', caseSensitive: false): 'AActor',
      RegExp(r'\bMonoBehaviour\b', caseSensitive: false): 'UActorComponent',
      RegExp(r'\bSerializeField\b', caseSensitive: false): 'Instance Editable',
      RegExp(r'\bUCLASS\s*(?:\([^)]*\))?', caseSensitive: false):
          'Blueprint Class',
      RegExp(r'\bUPROPERTY\s*(?:\([^)]*\))?', caseSensitive: false):
          'Instance Editable',
      RegExp(r'\bUFUNCTION\s*(?:\([^)]*\))?', caseSensitive: false):
          'Blueprint Event',
      RegExp(r'\.prefab\b', caseSensitive: false): ' Blueprint',
      RegExp(r'\bPrefabs\b', caseSensitive: false): 'Blueprints',
      RegExp(r'\bPrefab\b', caseSensitive: false): 'Blueprint',
      RegExp(r'\.tscn\b', caseSensitive: false): ' Level / Blueprint',
      RegExp(r'\.gd\b', caseSensitive: false): ' Blueprint',
      RegExp(r'\b(?:px|pixels)/s\b', caseSensitive: false): 'cm/s',
    };
    for (final entry in replacements.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }

    out = out.replaceAllMapped(
      RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\.(?:cpp|hpp|h)\b', caseSensitive: false),
      (m) => '${m.group(1)} Blueprint',
    );
    out = out.replaceAllMapped(
      RegExp(r'\b(\d+(?:\.\d+)?)\s*(?:px|pixels)\b', caseSensitive: false),
      (m) => '${m.group(1)} cm',
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
    out = out.replaceAll(RegExp(r'\s+(?:and|or)\s*$', caseSensitive: false), '');
    out = out.replaceAllMapped(
      RegExp(r'\s+([.,;:])'),
      (m) => m.group(1)!,
    );
    out = out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return out;
  }

  static List<String> sanitizeList(Iterable<String> raw) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in raw) {
      final clean = sanitizeLine(item);
      if (clean.isEmpty) continue;
      if (seen.add(clean.toLowerCase())) {
        result.add(clean);
      }
    }
    return result;
  }

  /// Normalizes a `§04` tuning identifier into a valid PascalCase Unreal / Verse variable name
  /// (preserving canonical Unreal `b` boolean prefixes like `bCanDash`).
  static String sanitizeTuningKey(
    String rawKey, {
    String fallback = 'TuningVar',
  }) {
    final trimmed = rawKey.trim();
    if (trimmed.isEmpty) return fallback;
    if (RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(trimmed)) {
      if (trimmed.length >= 2 &&
          trimmed[0] == 'b' &&
          trimmed[1] == trimmed[1].toUpperCase() &&
          trimmed[1] != trimmed[1].toLowerCase()) {
        return trimmed;
      }
      return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
    }
    final tokens = trimmed
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return fallback;
    final joined = tokens
        .map((t) => '${t[0].toUpperCase()}${t.substring(1)}')
        .join();
    if (RegExp(r'^[0-9]').hasMatch(joined)) {
      return 'Param$joined';
    }
    return joined;
  }

  /// Normalizes Unreal tuning unit strings (`1 UU = 1 cm`).
  static String normalizeUnrealUnit(String key, String rawUnit) {
    final clean = rawUnit.trim();
    final lowerUnit = clean.toLowerCase();
    final lowerKey = key.toLowerCase();
    if (lowerUnit == 'px' ||
        lowerUnit == 'pixels' ||
        lowerUnit == 'pixel' ||
        lowerUnit == 'uu') {
      return 'cm';
    }
    if (lowerUnit.startsWith('px/')) return 'cm/${clean.substring(3)}';
    if (lowerUnit.startsWith('pixels/')) return 'cm/${clean.substring(7)}';
    if (lowerUnit == 'sec' ||
        lowerUnit == 'secs' ||
        lowerUnit == 'second' ||
        lowerUnit == 'seconds') {
      return 's';
    }
    if (lowerUnit == 'deg' ||
        lowerUnit == 'degree' ||
        lowerUnit == 'degrees') {
      return 'deg';
    }
    if (lowerUnit == 'pct' ||
        lowerUnit == 'percent' ||
        lowerUnit == 'percentage') {
      return '%';
    }
    if (clean.isNotEmpty) return clean;
    if (lowerKey.contains('speed') ||
        lowerKey.contains('velocity') ||
        lowerKey.contains('impulse') ||
        lowerKey.contains('accel') ||
        lowerKey.contains('decel')) {
      return 'cm/s';
    }
    if (lowerKey.contains('distance') ||
        lowerKey.contains('radius') ||
        lowerKey.contains('height') ||
        lowerKey.contains('range') ||
        lowerKey.contains('offset') ||
        lowerKey.contains('width') ||
        lowerKey.contains('length') ||
        lowerKey.contains('springarm') ||
        lowerKey.contains('boomarm')) {
      return 'cm';
    }
    if (lowerKey.contains('angle') ||
        lowerKey.contains('fov') ||
        lowerKey.contains('pitch') ||
        lowerKey.contains('yaw') ||
        lowerKey.contains('roll') ||
        lowerKey.contains('spread') ||
        lowerKey.contains('deg')) {
      return 'deg';
    }
    if (lowerKey.contains('time') ||
        lowerKey.contains('duration') ||
        lowerKey.contains('cooldown') ||
        lowerKey.contains('delay') ||
        lowerKey.contains('window')) {
      return 's';
    }
    if (lowerKey.contains('chance') ||
        lowerKey.contains('percent') ||
        lowerKey.contains('pct')) {
      return '%';
    }
    if (lowerKey.contains('rate')) {
      return '%/s';
    }
    if (lowerKey.contains('mult') ||
        lowerKey.contains('scale') ||
        lowerKey.contains('factor')) {
      return 'x';
    }
    if (lowerKey.contains('hp') ||
        lowerKey.contains('health') ||
        lowerKey.contains('damage') ||
        lowerKey.contains('armor') ||
        lowerKey.contains('shield')) {
      return 'hp';
    }
    return 'count';
  }

  /// Infers Unreal Blueprint / C++ or UE6 Verse property type for `§04` tuning lines.
  static String inferUnrealPropertyType(
    String value,
    String unit, {
    bool isUe6Verse = false,
  }) {
    final cleanVal = value.trim().toLowerCase();
    final cleanUnit = unit.trim().toLowerCase();
    if (cleanUnit == 'bool' ||
        cleanUnit == 'boolean' ||
        cleanVal == 'true' ||
        cleanVal == 'false') {
      return isUe6Verse ? 'logic' : 'bool';
    }
    if (cleanUnit == 'count' && RegExp(r'^-?\d+$').hasMatch(cleanVal)) {
      return isUe6Verse ? 'int' : 'int32';
    }
    return 'float';
  }

  /// Cleans an AI-generated [EpicSpec] in place/copy so units, release tag, and wording conform cleanly.
  static EpicSpec sanitizeEpicSpec(
    EpicSpec raw, {
    String forceReleaseVersion = 'v0.1',
  }) {
    final cleanedTuning = <EpicTuningParam>[
      for (final t in raw.tuning)
        () {
          final cleanKey = sanitizeTuningKey(t.key);
          return EpicTuningParam(
            key: cleanKey,
            value: t.value.trim().isEmpty ? '0' : t.value.trim(),
            unit: normalizeUnrealUnit(cleanKey, t.unit),
          );
        }(),
    ];

    final cleanedControls = <EpicControlBinding>[
      for (final c in raw.controls)
        EpicControlBinding(
          action: sanitizeLine(c.action).isEmpty
              ? 'IA_Action'
              : sanitizeLine(c.action),
          trigger: sanitizeLine(c.trigger).isEmpty
              ? 'Started'
              : sanitizeLine(c.trigger),
          rule: sanitizeLine(c.rule),
        ),
    ];

    final cleanedChecks = <EpicPieCheck>[
      for (int i = 0; i < raw.checks.length; i++)
        EpicPieCheck(
          id: raw.checks[i].id,
          text: sanitizeLine(raw.checks[i].text),
          passed: raw.checks[i].passed,
        ),
    ].where((c) => c.text.isNotEmpty).toList();

    final cleanedFixes = <EpicPieFix>[
      for (final fx in raw.fixes)
        if (sanitizeLine(fx.text).isNotEmpty)
          fx.copyWith(text: sanitizeLine(fx.text)),
    ];

    final cleanedUpgrades = <EpicUpgradeOption>[
      for (final up in raw.copilotUpgrades)
        if (sanitizeLine(up.text).isNotEmpty)
          up.copyWith(text: sanitizeLine(up.text)),
    ];

    return EpicSpec(
      id: raw.id,
      code: raw.code.trim().isEmpty ? 'E01' : raw.code.trim().toUpperCase(),
      lineageKey: raw.lineageKey,
      title: sanitizeLine(raw.title).isEmpty
          ? 'Untitled System'
          : sanitizeLine(raw.title),
      releaseVersion: raw.releaseVersion.trim().isEmpty
          ? forceReleaseVersion
          : raw.releaseVersion.trim(),
      lifecycle: raw.lifecycle,
      coreLoopBeat: sanitizeLine(raw.coreLoopBeat),
      goal: sanitizeLine(raw.goal),
      links: sanitizeList(raw.links),
      outOfScope: sanitizeList(raw.outOfScope),
      controls: cleanedControls,
      states: sanitizeList(raw.states),
      interrupts: sanitizeList(raw.interrupts),
      tuning: cleanedTuning,
      feedback: sanitizeList(raw.feedback),
      levelStaging: sanitizeLine(raw.levelStaging),
      checks: cleanedChecks,
      fixes: cleanedFixes,
      baselineSummary: sanitizeList(raw.baselineSummary),
      upgradeDeltas: sanitizeList(raw.upgradeDeltas),
      copilotUpgrades: cleanedUpgrades,
      chosenForNextRelease: raw.chosenForNextRelease,
    );
  }

  /// Cleans an entire Stage 1 [ProjectConceptBlueprint] and clamps §05 Epics strictly to `v0.1`.
  static ProjectConceptBlueprint sanitizeConceptBlueprint(
    ProjectConceptBlueprint spec,
  ) {
    final cleanedEpics = <EpicSpec>[
      for (int i = 0; i < spec.initialEpics.length; i++)
        sanitizeEpicSpec(
          spec.initialEpics[i],
          forceReleaseVersion: 'v0.1',
        )
          ..releaseVersion = 'v0.1'
          ..code = 'E${(i + 1).toString().padLeft(2, '0')}'
          ..lineageKey = (spec.initialEpics[i].lineageKey.trim().isEmpty
              ? 'epic_${i + 1}'
              : spec.initialEpics[i].lineageKey.trim()),
    ];

    final cleanedCameraOptions = <ConceptSectionOption>[
      for (final opt in spec.cameraDecisionOptions)
        ConceptSectionOption(
          id: opt.id,
          label: sanitizeLine(opt.label).isEmpty
              ? opt.label.trim()
              : sanitizeLine(opt.label),
          contractValue: sanitizeLine(opt.contractValue).isEmpty
              ? opt.contractValue.trim()
              : sanitizeLine(opt.contractValue),
          note: opt.note == null ? null : sanitizeLine(opt.note!),
        ),
    ];

    final cleanedTradeOffs = <TradeOffRule>[
      for (final t in spec.tradeOffs)
        if (sanitizeLine(t.prefer).isNotEmpty || sanitizeLine(t.avoid).isNotEmpty)
          TradeOffRule(
            prefer: sanitizeLine(t.prefer),
            avoid: sanitizeLine(t.avoid),
          ),
    ];

    final cleanedPresets = <ReleaseDirectionPreset>[
      for (final p in spec.v02Presets)
        ReleaseDirectionPreset(
          id: p.id,
          label: sanitizeLine(p.label).isEmpty
              ? 'Release Direction'
              : sanitizeLine(p.label),
          description: sanitizeLine(p.description),
          upgradeIds: p.upgradeIds,
          newEpicIds: p.newEpicIds,
        ),
    ];

    final cleanedUpgradesByLineage = <String, List<EpicUpgradeOption>>{
      for (final e in spec.v02UpgradesByLineageKey.entries)
        e.key: [
          for (final u in e.value)
            if (sanitizeLine(u.text).isNotEmpty)
              u.copyWith(text: sanitizeLine(u.text)),
        ],
    };

    return ProjectConceptBlueprint(
      sparkPrompt: spec.sparkPrompt.trim(),
      gameTitle: sanitizeLine(spec.gameTitle).isEmpty
          ? 'UNTITLED UNREAL PROJECT'
          : sanitizeLine(spec.gameTitle).toUpperCase(),
      targetEngine: spec.targetEngine,
      pitch: sanitizeLine(spec.pitch),
      coreLoop: sanitizeList(spec.coreLoop),
      cameraChoiceId: spec.cameraChoiceId,
      cameraContract: sanitizeLine(spec.cameraContract),
      characterScale: sanitizeLine(spec.characterScale),
      inputContract: sanitizeLine(spec.inputContract),
      assetPolicy: sanitizeLine(spec.assetPolicy),
      cameraDecisionOptions: cleanedCameraOptions,
      feelChoiceId: ProjectConceptBlueprint.normalizeFeelChoiceId(
        spec.feelChoiceId,
      ),
      pillars: sanitizeList(spec.pillars),
      tradeOffs: cleanedTradeOffs,
      outOfScope: sanitizeList(spec.outOfScope),
      initialEpics: cleanedEpics,
      releaseDoneWhen: sanitizeLine(spec.releaseDoneWhen),
      v02Presets: cleanedPresets,
      v02NewPool: [
        for (final ep in spec.v02NewPool)
          sanitizeEpicSpec(ep, forceReleaseVersion: 'v0.2'),
      ],
      v02UpgradesByLineageKey: cleanedUpgradesByLineage,
      lastCoDesignNote: sanitizeLine(spec.lastCoDesignNote),
      approved: spec.approved,
    );
  }

  /// Machine-readable spec lint warnings for Stage 1 or Stage 2 preview pills.
  static List<String> auditBlueprint(ProjectConceptBlueprint spec) {
    final warnings = <String>[];
    if (spec.initialEpics.isEmpty) {
      warnings.add('No v0.1 prototype Epics defined in §05.');
    }
    if (spec.initialEpics.any((e) => e.releaseVersion != 'v0.1')) {
      warnings.add('Stage 1 §05 contains non-v0.1 Epics.');
    }
    final allTexts = <String>[
      spec.pitch,
      spec.cameraContract,
      spec.characterScale,
      spec.inputContract,
      spec.assetPolicy,
      ...spec.pillars,
      ...spec.tradeOffs.map((t) => t.formatted),
      for (final opt in spec.cameraDecisionOptions) ...[
        opt.label,
        opt.contractValue,
        if (opt.note != null) opt.note!,
      ],
      for (final ep in spec.initialEpics) ...[
        ep.title,
        ep.goal,
        ep.levelStaging,
        ...ep.links,
        ...ep.checks.map((c) => c.text),
        ...ep.fixes.map((f) => f.text),
      ],
    ];
    if (allTexts.any(containsGodotLeakage)) {
      warnings.add('Detected legacy Godot terminology in Unreal foundation.');
    }
    for (final ep in spec.initialEpics) {
      if (ep.checks.isEmpty) {
        warnings.add('${ep.code} (${ep.title}) has 0 PIE acceptance checks.');
      }
    }
    return warnings;
  }
}
