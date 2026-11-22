import '../../models/agent_blueprints.dart';
import '../../models/epic_spec.dart';

/// Optional 3-fork clarification draft shown for vague Stage 1 sparks before drafting.
class SparkClarificationDraft {
  final String rawSpark;
  final GodotProjectDimension dimension;
  final String viewChoiceId;
  final String archetypeId;
  final String prototypeHookId;

  const SparkClarificationDraft({
    required this.rawSpark,
    required this.dimension,
    required this.viewChoiceId,
    required this.archetypeId,
    required this.prototypeHookId,
  });

  static const List<({String id, String label})> archetypeOptions = [
    (id: 'combat', label: 'Real-Time Combat'),
    (id: 'movement', label: 'Movement / Precision'),
    (id: 'racer', label: 'Racer / Physics'),
    (id: 'puzzle', label: 'Puzzle / Systemic / Cozy'),
  ];

  static const List<({String id, String label})> prototypeHookOptions = [
    (id: 'skirmish', label: '1-Room Skirmish'),
    (id: 'course', label: '1-Lap / Obstacle Course'),
    (id: 'survival', label: '60s Timed Survival Loop'),
    (id: 'puzzle_room', label: '1-Screen Puzzle Room'),
  ];

  List<ConceptSectionOption> get viewOptions =>
      dimension == GodotProjectDimension.dim2d
          ? ProjectConceptBlueprint.defaultCamera2dOptions
          : ProjectConceptBlueprint.defaultCamera3dOptions;

  static bool isSparkVague(String sparkPrompt) {
    final trimmed = sparkPrompt.trim();
    if (trimmed.isEmpty) return false;
    if (GodotSparkPresets.matchSparkPrompt(trimmed) != null) return false;
    final words = RegExp(r'[A-Za-z0-9]+')
        .allMatches(trimmed)
        .map((m) => m.group(0)!)
        .toList();
    if (words.length < 6) return true;
    final lower = trimmed.toLowerCase();
    final hasViewCue = RegExp(
      r'\b(?:2d|3d|top[- ]?down|side[- ]?scroll(?:er|ing)|isometric|first[- ]?person|third[- ]?person|fps|tps|platformer|pixel[- ]?art|fixed[- ]?camera|overhead)\b',
    ).hasMatch(lower);
    final hasVerbCue = RegExp(
      r'\b(?:dash|shoot|cleave|parry|grapple|drift|stealth|puzzle|jump|climb|farm|craft|build|dodge|race|hack|throw|combo|slash|deck|card|tower|hook|beam|shield|boost|solve|push|collect|chop|plant)\b',
    ).hasMatch(lower);
    return !hasViewCue && !hasVerbCue;
  }

  static SparkClarificationDraft suggestFromSpark(
    String rawSpark, {
    GodotProjectDimension? pinnedDimension,
  }) {
    final cleaned = rawSpark.trim();
    final lower = cleaned.toLowerCase();
    final dim = pinnedDimension ?? GodotProjectDimension.detectFromSpark(cleaned);

    final String viewId;
    if (dim == GodotProjectDimension.dim2d) {
      if (lower.contains('side') ||
          lower.contains('platformer') ||
          lower.contains('metroidvania')) {
        viewId = 'sidescroller2d';
      } else if (lower.contains('room') ||
          lower.contains('puzzle') ||
          lower.contains('sokoban')) {
        viewId = 'fixedarena2d';
      } else {
        viewId = 'topdown2d';
      }
    } else {
      if (lower.contains('first-person') ||
          lower.contains('first person') ||
          lower.contains('fps')) {
        viewId = 'fps';
      } else if (lower.contains('third-person') ||
          lower.contains('third person') ||
          lower.contains('tps') ||
          lower.contains('racer') ||
          lower.contains('drift') ||
          lower.contains('grapple') ||
          lower.contains('glider')) {
        viewId = 'tps';
      } else if (lower.contains('top-down') || lower.contains('top down')) {
        viewId = 'topdown';
      } else {
        viewId = 'isometric';
      }
    }

    final String archId;
    if (RegExp(r'\b(?:race|racer|drift|track|lap|skiff|car|kart|boost)\b')
        .hasMatch(lower)) {
      archId = 'racer';
    } else if (RegExp(
            r'\b(?:platformer|climb|grapple|glider|parkour|hop|jump|course)\b')
        .hasMatch(lower)) {
      archId = 'movement';
    } else if (RegExp(
            r'\b(?:puzzle|cozy|farm|farming|card|deck|sokoban|craft|relay|mirror|cooking)\b')
        .hasMatch(lower)) {
      archId = 'puzzle';
    } else {
      archId = 'combat';
    }

    final String hookId;
    if (archId == 'racer' || archId == 'movement') {
      hookId = 'course';
    } else if (archId == 'puzzle') {
      hookId = 'puzzle_room';
    } else if (RegExp(r'\b(?:survival|survivor|timer|timed|horde|wave)\b')
        .hasMatch(lower)) {
      hookId = 'survival';
    } else {
      hookId = 'skirmish';
    }

    return SparkClarificationDraft(
      rawSpark: cleaned,
      dimension: dim,
      viewChoiceId: viewId,
      archetypeId: archId,
      prototypeHookId: hookId,
    );
  }

  SparkClarificationDraft copyWith({
    String? rawSpark,
    GodotProjectDimension? dimension,
    String? viewChoiceId,
    String? archetypeId,
    String? prototypeHookId,
  }) {
    final nextDim = dimension ?? this.dimension;
    final nextView = viewChoiceId ??
        (dimension != null && dimension != this.dimension
            ? (nextDim == GodotProjectDimension.dim2d
                ? 'topdown2d'
                : 'isometric')
            : this.viewChoiceId);
    return SparkClarificationDraft(
      rawSpark: rawSpark ?? this.rawSpark,
      dimension: nextDim,
      viewChoiceId: nextView,
      archetypeId: archetypeId ?? this.archetypeId,
      prototypeHookId: prototypeHookId ?? this.prototypeHookId,
    );
  }

  String buildEnrichedSpark() {
    String viewLabel = viewChoiceId;
    for (final opt in viewOptions) {
      if (opt.id == viewChoiceId) {
        viewLabel = opt.label;
        break;
      }
    }
    String archLabel = archetypeId;
    for (final opt in archetypeOptions) {
      if (opt.id == archetypeId) {
        archLabel = opt.label;
        break;
      }
    }
    String hookLabel = prototypeHookId;
    for (final opt in prototypeHookOptions) {
      if (opt.id == prototypeHookId) {
        hookLabel = opt.label;
        break;
      }
    }
    return '$rawSpark (Dimension: ${dimension.pillLabel}; Camera: $viewLabel; Loop Focus: $archLabel; v0.1 Scope: $hookLabel)';
  }
}

/// Zero-token `v0.1` Prototype Scope Readiness & First Playtest preview metrics for Stage 1 `§05`.
class Stage1ScopeSummary {
  final int epicCount;
  final int featureCount;
  final int estimatedMinutes;
  final int inputActionCount;
  final String? firstTestScenePath;
  final String? firstFeatureLabel;
  final String? firstPlaytestGate;
  final List<String> warnings;

  const Stage1ScopeSummary({
    required this.epicCount,
    required this.featureCount,
    required this.estimatedMinutes,
    required this.inputActionCount,
    this.firstTestScenePath,
    this.firstFeatureLabel,
    this.firstPlaytestGate,
    this.warnings = const <String>[],
  });

  String get formattedDuration {
    if (estimatedMinutes >= 60) {
      final hrs = (estimatedMinutes / 60.0)
          .toStringAsFixed(1)
          .replaceFirst(RegExp(r'\.0$'), '');
      return '~$hrs hrs';
    }
    return '~$estimatedMinutes min';
  }

  bool get isLean => warnings.isEmpty;

  static int _parseSliceMinutes(String raw) {
    final m = RegExp(r'(\d+)(?:\s*[-–]\s*(\d+))?').firstMatch(raw);
    if (m == null) return 45;
    final a = int.tryParse(m.group(1) ?? '') ?? 45;
    final b = m.group(2) != null ? int.tryParse(m.group(2)!) : null;
    if (b != null && b >= a) return ((a + b) / 2.0).round();
    return a.clamp(15, 180);
  }

  factory Stage1ScopeSummary.fromBlueprint(ProjectConceptBlueprint spec) {
    final epics = spec.initialEpics;
    int featCount = 0;
    int mins = 0;
    final actions = <String>{};
    bool anyMissingCheck = false;
    FeatureSpec? firstFeat;

    for (final ep in epics) {
      final v01Feats = ep.featuresForRelease('v0.1');
      featCount += v01Feats.length;
      for (final f in v01Feats) {
        firstFeat ??= f;
        mins += _parseSliceMinutes(f.sliceTime);
        if (f.checks.isEmpty) anyMissingCheck = true;
        for (final c in f.controls) {
          final tokens = c.action
              .split(RegExp(r'[/,]'))
              .map((s) => s.trim().toLowerCase())
              .where((s) => s.isNotEmpty);
          actions.addAll(tokens);
        }
      }
      if (v01Feats.isEmpty) {
        for (final c in ep.controls) {
          final tokens = c.action
              .split(RegExp(r'[/,]'))
              .map((s) => s.trim().toLowerCase())
              .where((s) => s.isNotEmpty);
          actions.addAll(tokens);
        }
      }
    }

    if (actions.isEmpty && spec.inputContract.trim().isNotEmpty) {
      final cleanedInput = spec.inputContract
          .replaceAll(
            RegExp(r'\b(?:Enhanced Input|InputMap|IMC_[A-Za-z0-9_]+)\b',
                caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'[():]'), ' ');
      for (final tok in cleanedInput.split(RegExp(r'[,/;]'))) {
        final c = tok.trim().toLowerCase();
        if (c.isNotEmpty) actions.add(c);
      }
    }

    final mapRx = RegExp(
      r'(?:/Game/|res://)[^\s,;)\]]+\.(?:umap|tscn)',
      caseSensitive: false,
    );
    String? testScene;
    for (final ep in epics) {
      for (final own in ep.sceneOwnership) {
        final low = own.path.toLowerCase();
        if (low.endsWith('.umap') || low.endsWith('.tscn')) {
          testScene = own.path.trim();
          break;
        }
      }
      if (testScene != null) break;
      final m = mapRx.firstMatch(ep.levelStaging);
      if (m != null) {
        testScene = m.group(0);
        break;
      }
    }
    testScene ??= mapRx.firstMatch(spec.releaseDoneWhen)?.group(0);

    final firstGate = (firstFeat != null && firstFeat.checks.isNotEmpty)
        ? firstFeat.checks.first.text
        : (epics.isNotEmpty && epics.first.doneWhen.isNotEmpty
            ? epics.first.doneWhen.first
            : spec.releaseDoneWhen);

    final warns = <String>[
      if (epics.length > 4)
        '${epics.length} Epics in v0.1 (keep 2-4 Epics for focused playtesting)',
      if (featCount > 8)
        '$featCount Features in v0.1 (trim to <= 8 slices to ship faster)',
      if (testScene == null)
        'Missing a /Game/Maps/Lvl_*.umap playtest map in E01 Scene Ownership',
      if (anyMissingCheck) 'One or more Features lack a PIE Playtest Gate check',
    ];

    return Stage1ScopeSummary(
      epicCount: epics.length,
      featureCount: featCount,
      estimatedMinutes: mins,
      inputActionCount: actions.length,
      firstTestScenePath: testScene,
      firstFeatureLabel:
          firstFeat != null ? '${firstFeat.code} — ${firstFeat.title}' : null,
      firstPlaytestGate: firstGate.trim().isEmpty ? null : firstGate.trim(),
      warnings: warns,
    );
  }
}
