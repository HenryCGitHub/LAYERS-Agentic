import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';

/// Pure Unreal Engine specification guard, sanitizer & v0.1 scope validator.
/// Ensures zero Godot leakage, clean literal game-dev wording, and canonical `1 UU = 1 cm` units.
class UnrealSpecGuard {
  static final RegExp _godotLeakPattern = RegExp(
    r'\b(godot|gdscript|characterbody3d|characterbody2d|area3d|area2d|_physics_process|\.tscn|\.gd)\b|\bpx/s\b',
    caseSensitive: false,
  );

  static final RegExp _leadingBulletPattern = RegExp(r'^[\-\*\u2022\s]+');

  static final List<String> _bannedFillerPhrases = <String>[
    'seamlessly',
    'synergy',
    'leverage',
    'end-to-end loop',
    'unified pipeline',
  ];

  static bool containsGodotLeakage(String text) {
    return _godotLeakPattern.hasMatch(text);
  }

  /// Strips Godot-specific terms or buzzword padding and tightens to literal Unreal phrasing.
  static String sanitizeLine(String raw) {
    var out = raw.trim().replaceFirst(_leadingBulletPattern, '').trim();
    if (out.isEmpty) return '';

    final replacements = <RegExp, String>{
      RegExp(r'\bGDScript\b', caseSensitive: false): 'Blueprint / Verse',
      RegExp(r'\bGodot\b', caseSensitive: false): 'Unreal Engine',
      RegExp(r'\bCharacterBody3D\b', caseSensitive: false): 'ACharacter',
      RegExp(r'\bCharacterBody2D\b', caseSensitive: false): 'ACharacter',
      RegExp(r'\b_physics_process\b', caseSensitive: false): 'Tick',
      RegExp(r'\bpx/s\b', caseSensitive: false): 'cm/s',
      RegExp(r'\.tscn\b', caseSensitive: false): ' Level / Blueprint',
      RegExp(r'\.gd\b', caseSensitive: false): ' Blueprint',
    };
    for (final entry in replacements.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }

    for (final filler in _bannedFillerPhrases) {
      out = out.replaceAll(RegExp('\\b${RegExp.escape(filler)}\\b', caseSensitive: false), '');
    }

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
      fixes: raw.fixes,
      baselineSummary: sanitizeList(raw.baselineSummary),
      upgradeDeltas: sanitizeList(raw.upgradeDeltas),
      copilotUpgrades: raw.copilotUpgrades,
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
      cameraDecisionOptions: spec.cameraDecisionOptions,
      feelChoiceId: ProjectConceptBlueprint.normalizeFeelChoiceId(
        spec.feelChoiceId,
      ),
      pillars: sanitizeList(spec.pillars),
      tradeOffs: spec.tradeOffs,
      outOfScope: sanitizeList(spec.outOfScope),
      initialEpics: cleanedEpics,
      releaseDoneWhen: sanitizeLine(spec.releaseDoneWhen),
      v02Presets: spec.v02Presets,
      v02NewPool: [
        for (final ep in spec.v02NewPool)
          sanitizeEpicSpec(ep, forceReleaseVersion: 'v0.2'),
      ],
      v02UpgradesByLineageKey: spec.v02UpgradesByLineageKey,
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
    if (containsGodotLeakage(spec.pitch) ||
        containsGodotLeakage(spec.cameraContract) ||
        containsGodotLeakage(spec.inputContract)) {
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
