import 'epic_spec.dart';

part 'spark_presets_part.dart';

/// Clickable Co-Designer decision option inside Stage 1 (`§02` Camera / Scale forks).
class ConceptSectionOption {
  final String id;
  final String label;
  final String contractValue;
  final String? note;

  const ConceptSectionOption({
    required this.id,
    required this.label,
    required this.contractValue,
    this.note,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'contractValue': contractValue,
        if (note != null && note!.trim().isNotEmpty) 'note': note,
      };

  factory ConceptSectionOption.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] ?? 'Camera Option').toString().trim();
    return ConceptSectionOption(
      id: (json['id'] ?? 'opt_${label.toLowerCase()}').toString().trim(),
      label: label,
      contractValue:
          (json['contractValue'] ?? json['value'] ?? label).toString().trim(),
      note: json['note']?.toString().trim(),
    );
  }
}

/// Practical conflict resolution rule (`X OVER Y`).
class TradeOffRule {
  final String prefer;
  final String avoid;

  const TradeOffRule({
    required this.prefer,
    required this.avoid,
  });

  String get formatted => '$prefer OVER $avoid';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'prefer': prefer,
        'avoid': avoid,
      };

  factory TradeOffRule.fromDynamic(dynamic raw) {
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      return TradeOffRule(
        prefer: (m['prefer'] ?? 'Direct arcade response').toString().trim(),
        avoid: (m['avoid'] ?? 'Slow physical inertia').toString().trim(),
      );
    }
    final text = raw.toString().trim();
    final overSplit = text.split(RegExp(r'\s+over\s+', caseSensitive: false));
    if (overSplit.length >= 2) {
      return TradeOffRule(
        prefer: overSplit.first.trim(),
        avoid: overSplit.sublist(1).join(' over ').trim(),
      );
    }
    return TradeOffRule(
      prefer: text.isEmpty ? 'Crisp readable combat' : text,
      avoid: 'Realistic physics clutter',
    );
  }
}

/// Clickable Core Feel option inside Stage 1 (`§03` Core Feel & Trade-Offs).
class CoreFeelOption {
  final String id;
  final String label;
  final TradeOffRule tradeOff;
  final String decelMPerSec;
  final String decelPxPerSec;

  const CoreFeelOption({
    required this.id,
    required this.label,
    required this.tradeOff,
    required this.decelMPerSec,
    required this.decelPxPerSec,
  });

  String decelFor(GodotProjectDimension dim) =>
      dim == GodotProjectDimension.dim2d ? decelPxPerSec : decelMPerSec;
}

/// Stage 1 Godot 4 Root Project Specification (`PROJECT_SPEC.md` -> `ROOT_GODOT_CONTEXT`).
/// Pure high-level foundation: 3D (`1 unit = 1 m`) or 2D (`px`), pillars, trade-offs, hard cuts,
/// and strictly `v0.1` prototype Epics in §05.
class ProjectConceptBlueprint {
  String sparkPrompt;
  String gameTitle;
  GodotProjectDimension dimension;

  // §01 Core Fantasy & 30s Loop
  String pitch;
  List<String> coreLoop;

  // §02 Global Godot 4 Scale & Architecture
  String cameraChoiceId;
  String cameraContract;
  String characterScale;
  String inputContract;
  String assetPolicy;
  List<ConceptSectionOption> cameraDecisionOptions;

  // §03 Design Pillars & Conflict Trade-Offs
  String feelChoiceId;
  List<String> pillars;
  List<TradeOffRule> tradeOffs;

  // §04 Hard Scope Cuts (Do Not Build)
  List<String> outOfScope;

  // §05 Initial Release (v0.1 Prototype Epics Only)
  List<EpicSpec> initialEpics;
  String releaseDoneWhen;

  // Optional preset/AI-generated v0.2 progression hints
  List<ReleaseDirectionPreset> v02Presets;
  List<EpicSpec> v02NewPool;
  Map<String, List<EpicUpgradeOption>> v02UpgradesByLineageKey;
  Map<String, List<FeatureSpec>> v02NewFeaturesByLineageKey;

  String lastCoDesignNote;
  bool approved;

  ProjectConceptBlueprint({
    this.sparkPrompt = '',
    this.gameTitle = 'UNTITLED GODOT PROJECT',
    this.dimension = GodotProjectDimension.dim3d,
    String? cameraChoiceId,
    String? cameraContract,
    String? characterScale,
    String? inputContract,
    String? assetPolicy,
    this.pitch = '',
    List<String>? coreLoop,
    List<ConceptSectionOption>? cameraDecisionOptions,
    this.feelChoiceId = 'snappy',
    List<String>? pillars,
    List<TradeOffRule>? tradeOffs,
    List<String>? outOfScope,
    List<EpicSpec>? initialEpics,
    this.releaseDoneWhen =
        'Run F6 on res://scenes/arena_proto.tscn -> complete full 30s core loop cleanly with 0 Debugger errors',
    List<ReleaseDirectionPreset>? v02Presets,
    List<EpicSpec>? v02NewPool,
    Map<String, List<EpicUpgradeOption>>? v02UpgradesByLineageKey,
    Map<String, List<FeatureSpec>>? v02NewFeaturesByLineageKey,
    this.lastCoDesignNote = '',
    this.approved = false,
  })  : cameraChoiceId = cameraChoiceId ??
            (dimension == GodotProjectDimension.dim2d
                ? 'topdown2d'
                : 'isometric'),
        cameraContract = cameraContract ??
            (dimension == GodotProjectDimension.dim2d
                ? 'Camera2D Zoom 1.0x · PositionSmoothing 8.0 · Cursor 2D world aim'
                : 'SpringArm3D 14.5 m @ -52 deg pitch, 55 deg FOV, CameraLag 9.0'),
        characterScale = characterScale ??
            (dimension == GodotProjectDimension.dim2d
                ? 'CharacterBody2D CollisionShape 32x48 px · move_speed 260 px/s'
                : 'CharacterBody3D CapsuleRadius 0.42 m · Height 1.84 m · move_speed 6.2 m/s'),
        inputContract = inputContract ??
            'InputMap (move_left/right/up/down, dodge, primary_action)',
        assetPolicy = assetPolicy ??
            (dimension == GodotProjectDimension.dim2d
                ? 'ColorRect / Polygon2D Greybox Prototypes + Solid Tint Materials; @export vars & Resource (.tres)'
                : 'CSGBox3D / PrimitiveMesh Greybox + StandardMaterial3D Tints; @export vars & Resource (.tres)'),
        coreLoop = coreLoop ?? <String>[],
        cameraDecisionOptions = cameraDecisionOptions ??
            (dimension == GodotProjectDimension.dim2d
                ? defaultCamera2dOptions
                : defaultCamera3dOptions),
        pillars = pillars ?? <String>[],
        tradeOffs = tradeOffs ?? <TradeOffRule>[],
        outOfScope = outOfScope ?? <String>[],
        initialEpics = initialEpics ?? <EpicSpec>[],
        v02Presets = v02Presets ?? <ReleaseDirectionPreset>[],
        v02NewPool = v02NewPool ?? <EpicSpec>[],
        v02UpgradesByLineageKey =
            v02UpgradesByLineageKey ?? <String, List<EpicUpgradeOption>>{},
        v02NewFeaturesByLineageKey =
            v02NewFeaturesByLineageKey ?? <String, List<FeatureSpec>>{};

  static const List<ConceptSectionOption> defaultCamera3dOptions = [
    ConceptSectionOption(
      id: 'isometric',
      label: 'Isometric (~52 deg)',
      contractValue:
          'SpringArm3D 14.5 m @ -52 deg pitch, 55 deg FOV, CameraLag 9.0',
      note: 'Best readability for 3D arena movement + XZ cursor plane aiming.',
    ),
    ConceptSectionOption(
      id: 'topdown',
      label: 'Fixed Top-Down (90 deg)',
      contractValue:
          'SpringArm3D 16.5 m @ -88 deg pitch, 50 deg FOV, Zero camera roll',
      note: 'Pure tactical arena clarity with minimal perspective skew.',
    ),
    ConceptSectionOption(
      id: 'tps',
      label: 'Third-Person Over-Shoulder',
      contractValue:
          'SpringArm3D 3.6 m · Offset (0.65, 0.55) m · 68 deg FOV · CameraLag 11.0',
      note: 'Close-quarters weight and horizon depth over rear flank awareness.',
    ),
    ConceptSectionOption(
      id: 'fps',
      label: 'First-Person (90 deg FOV)',
      contractValue:
          'Camera3D EyeHeight 1.65 m · 90 deg FOV · Captured mouse yaw/pitch',
      note: 'Immediate eye-level aim precision with narrow peripheral awareness.',
    ),
  ];

  static const List<ConceptSectionOption> defaultCamera2dOptions = [
    ConceptSectionOption(
      id: 'topdown2d',
      label: 'Top-Down 2D Follow',
      contractValue:
          'Camera2D Zoom 1.0x · PositionSmoothing 8.0 · Cursor 2D world aim',
      note: 'Crisp 360-degree top-down movement and mouse aim across 2D rooms.',
    ),
    ConceptSectionOption(
      id: 'sidescroller2d',
      label: '2D Side-Scroller Cam',
      contractValue:
          'Camera2D Zoom 1.4x · Lookahead 64 px · Horizontal floor lock',
      note: 'Clear vertical platform clearance and grounded forward readability.',
    ),
    ConceptSectionOption(
      id: 'fixedarena2d',
      label: 'Fixed Room Frame (1280x720)',
      contractValue:
          'Camera2D Centered Fixed Frame (Zoom 1.0x) · Whole arena visible',
      note: 'Zero scrolling disorientation for compact wave skirmish rooms.',
    ),
  ];

  static const List<CoreFeelOption> coreFeelOptions = [
    CoreFeelOption(
      id: 'snappy',
      label: 'Snappy Arcade',
      tradeOff: TradeOffRule(
        prefer: 'Instant arcade acceleration',
        avoid: 'Heavy momentum turn inertia',
      ),
      decelMPerSec: '24.0',
      decelPxPerSec: '2400',
    ),
    CoreFeelOption(
      id: 'heavy',
      label: 'Heavy Deliberate',
      tradeOff: TradeOffRule(
        prefer: 'Committed heavy windups',
        avoid: 'Zero-recovery animation cancel spam',
      ),
      decelMPerSec: '14.0',
      decelPxPerSec: '1400',
    ),
    CoreFeelOption(
      id: 'physics',
      label: 'Physics Momentum',
      tradeOff: TradeOffRule(
        prefer: 'Velocity carry & drift banking',
        avoid: 'Stop-on-a-dime snapping',
      ),
      decelMPerSec: '4.8',
      decelPxPerSec: '480',
    ),
  ];

  static String normalizeFeelChoiceId(String? raw) {
    final clean = raw?.trim().toLowerCase();
    if (clean == 'heavy') return 'heavy';
    if (clean == 'physics') return 'physics';
    return 'snappy';
  }

  static CoreFeelOption coreFeelOptionById(String id) {
    final normalized = normalizeFeelChoiceId(id);
    for (final opt in coreFeelOptions) {
      if (opt.id == normalized) return opt;
    }
    return coreFeelOptions.first;
  }

  CoreFeelOption get selectedCoreFeelOption => coreFeelOptionById(feelChoiceId);

  List<ConceptSectionOption> get effectiveCameraDecisionOptions {
    final defaults = dimension == GodotProjectDimension.dim2d
        ? defaultCamera2dOptions
        : defaultCamera3dOptions;
    return [
      ...cameraDecisionOptions,
      for (final def in defaults)
        if (!cameraDecisionOptions.any((o) => o.id == def.id)) def,
    ];
  }

  bool get hasSpec =>
      pitch.trim().isNotEmpty &&
      coreLoop.isNotEmpty &&
      initialEpics.isNotEmpty;

  String get normalizedTitle =>
      gameTitle.trim().isEmpty ? 'UNTITLED GODOT PROJECT' : gameTitle.trim();

  ProjectConceptBlueprint deepCopy() {
    return ProjectConceptBlueprint(
      sparkPrompt: sparkPrompt,
      gameTitle: gameTitle,
      dimension: dimension,
      pitch: pitch,
      coreLoop: List<String>.from(coreLoop),
      cameraChoiceId: cameraChoiceId,
      cameraContract: cameraContract,
      characterScale: characterScale,
      inputContract: inputContract,
      assetPolicy: assetPolicy,
      cameraDecisionOptions: List<ConceptSectionOption>.from(
        cameraDecisionOptions,
      ),
      feelChoiceId: feelChoiceId,
      pillars: List<String>.from(pillars),
      tradeOffs: List<TradeOffRule>.from(tradeOffs),
      outOfScope: List<String>.from(outOfScope),
      initialEpics: [for (final ep in initialEpics) ep.deepCopy()],
      releaseDoneWhen: releaseDoneWhen,
      v02Presets: List<ReleaseDirectionPreset>.from(v02Presets),
      v02NewPool: [for (final ep in v02NewPool) ep.deepCopy()],
      v02UpgradesByLineageKey: {
        for (final entry in v02UpgradesByLineageKey.entries)
          entry.key: [for (final opt in entry.value) opt.copyWith()],
      },
      v02NewFeaturesByLineageKey: {
        for (final entry in v02NewFeaturesByLineageKey.entries)
          entry.key: [for (final feat in entry.value) feat.deepCopy()],
      },
      lastCoDesignNote: lastCoDesignNote,
      approved: approved,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sparkPrompt': sparkPrompt,
        'gameTitle': gameTitle,
        'dimension': dimension.id,
        'pitch': pitch,
        'coreLoop': coreLoop,
        'cameraChoiceId': cameraChoiceId,
        'cameraContract': cameraContract,
        'characterScale': characterScale,
        'inputContract': inputContract,
        'assetPolicy': assetPolicy,
        'cameraDecisionOptions': [
          for (final o in cameraDecisionOptions) o.toJson(),
        ],
        'feelChoiceId': feelChoiceId,
        'pillars': pillars,
        'tradeOffs': [for (final t in tradeOffs) t.toJson()],
        'outOfScope': outOfScope,
        'initialEpics': [for (final e in initialEpics) e.toJson()],
        'releaseDoneWhen': releaseDoneWhen,
        'v02Presets': [for (final p in v02Presets) p.toJson()],
        'v02NewPool': [for (final e in v02NewPool) e.toJson()],
        'v02UpgradesByLineageKey': {
          for (final entry in v02UpgradesByLineageKey.entries)
            entry.key: [for (final opt in entry.value) opt.toJson()],
        },
        'v02NewFeaturesByLineageKey': {
          for (final entry in v02NewFeaturesByLineageKey.entries)
            entry.key: [for (final feat in entry.value) feat.toJson()],
        },
        'lastCoDesignNote': lastCoDesignNote,
        'approved': approved,
      };

  factory ProjectConceptBlueprint.fromJson(Map<String, dynamic> json) {
    final rawLoop = json['coreLoop'];
    final loop = <String>[];
    if (rawLoop is List) {
      for (final item in rawLoop) {
        final s = item.toString().trim();
        if (s.isNotEmpty) loop.add(s);
      }
    } else if (rawLoop is String && rawLoop.trim().isNotEmpty) {
      final parts = rawLoop
          .split(RegExp(r'->|→|\n|,'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      loop.addAll(parts);
    }

    final rawCameraOpts = json['cameraDecisionOptions'] as List? ?? const [];
    final cameraOpts = <ConceptSectionOption>[
      for (final item in rawCameraOpts)
        if (item is Map)
          ConceptSectionOption.fromJson(Map<String, dynamic>.from(item)),
    ];

    final rawTradeOffs = json['tradeOffs'] as List? ?? const [];
    final trades = <TradeOffRule>[
      for (final item in rawTradeOffs) TradeOffRule.fromDynamic(item),
    ];

    final rawEpics = json['initialEpics'] as List? ?? const [];
    final epics = <EpicSpec>[
      for (int i = 0; i < rawEpics.length; i++)
        if (rawEpics[i] is Map)
          EpicSpec.fromJson(
            Map<String, dynamic>.from(rawEpics[i] as Map),
            indexHint: i,
          ),
    ];

    final rawV02Presets = json['v02Presets'] as List? ?? const [];
    final presets = <ReleaseDirectionPreset>[
      for (final item in rawV02Presets)
        if (item is Map)
          ReleaseDirectionPreset.fromJson(Map<String, dynamic>.from(item)),
    ];

    final rawV02Pool = json['v02NewPool'] as List? ?? const [];
    final pool = <EpicSpec>[
      for (int i = 0; i < rawV02Pool.length; i++)
        if (rawV02Pool[i] is Map)
          EpicSpec.fromJson(
            Map<String, dynamic>.from(rawV02Pool[i] as Map),
            indexHint: epics.length + i,
          ),
    ];

    final upgradesMap = <String, List<EpicUpgradeOption>>{};
    final rawUpMap = json['v02UpgradesByLineageKey'];
    if (rawUpMap is Map) {
      for (final entry in rawUpMap.entries) {
        final list = entry.value;
        if (list is List) {
          upgradesMap[entry.key.toString().toLowerCase()] = [
            for (int i = 0; i < list.length; i++)
              if (list[i] is Map)
                EpicUpgradeOption.fromJson(
                  Map<String, dynamic>.from(list[i] as Map),
                  i,
                ),
          ];
        }
      }
    }

    final newFeaturesMap = <String, List<FeatureSpec>>{};
    final rawNewFeatMap = json['v02NewFeaturesByLineageKey'];
    if (rawNewFeatMap is Map) {
      for (final entry in rawNewFeatMap.entries) {
        final list = entry.value;
        if (list is List) {
          newFeaturesMap[entry.key.toString().toLowerCase()] = [
            for (int i = 0; i < list.length; i++)
              if (list[i] is Map)
                FeatureSpec.fromJson(
                  Map<String, dynamic>.from(list[i] as Map),
                  indexHint: i,
                  idPrefixHint: '${entry.key.toString().trim().toLowerCase()}_v02',
                ),
          ];
        }
      }
    }

    final legacyGameSpec = json['gameSpec'] is Map
        ? Map<String, dynamic>.from(json['gameSpec'] as Map)
        : const <String, dynamic>{};
    final legacyTechSpec = json['techSpec'] is Map
        ? Map<String, dynamic>.from(json['techSpec'] as Map)
        : const <String, dynamic>{};

    final dim = GodotProjectDimension.fromString(
      (json['dimension'] ?? json['engine'] ?? legacyTechSpec['engine'] ?? 'dim3d')
          .toString(),
    );
    final is2d = dim == GodotProjectDimension.dim2d;

    return ProjectConceptBlueprint(
      sparkPrompt: (json['sparkPrompt'] ?? json['prompt'] ?? '').toString(),
      gameTitle: (json['gameTitle'] ??
              json['title'] ??
              legacyGameSpec['title'] ??
              'UNTITLED GODOT PROJECT')
          .toString()
          .trim(),
      dimension: dim,
      pitch: (json['pitch'] ?? json['goal'] ?? '').toString().trim(),
      coreLoop: loop,
      cameraChoiceId: (json['cameraChoiceId'] ??
              (is2d ? 'topdown2d' : 'isometric'))
          .toString()
          .trim(),
      cameraContract: (json['cameraContract'] ??
              legacyGameSpec['camera'] ??
              (is2d
                  ? 'Camera2D Zoom 1.0x · PositionSmoothing 8.0 · Cursor 2D world aim'
                  : 'SpringArm3D 14.5 m @ -52 deg pitch, 55 deg FOV, CameraLag 9.0'))
          .toString()
          .trim(),
      characterScale: (json['characterScale'] ??
              (is2d
                  ? 'CharacterBody2D CollisionShape 32x48 px · move_speed 260 px/s'
                  : 'CharacterBody3D CapsuleRadius 0.42 m · Height 1.84 m · move_speed 6.2 m/s'))
          .toString()
          .trim(),
      inputContract: (json['inputContract'] ??
              'InputMap (move_left/right/up/down, dodge, primary_action)')
          .toString()
          .trim(),
      assetPolicy: (json['assetPolicy'] ??
              (is2d
                  ? 'ColorRect / Polygon2D Greybox Prototypes + Solid Tint Materials; @export vars & Resource (.tres)'
                  : 'CSGBox3D / PrimitiveMesh Greybox + StandardMaterial3D Tints; @export vars & Resource (.tres)'))
          .toString()
          .trim(),
      cameraDecisionOptions: cameraOpts.isEmpty
          ? (is2d ? defaultCamera2dOptions : defaultCamera3dOptions)
          : cameraOpts,
      feelChoiceId: normalizeFeelChoiceId(json['feelChoiceId']?.toString()),
      pillars: _stringList(json['pillars'] ?? json['designPillars']),
      tradeOffs: trades,
      outOfScope: _stringList(json['outOfScope']),
      initialEpics: epics,
      releaseDoneWhen: (json['releaseDoneWhen'] ??
              json['doneWhen'] ??
              'Run F6 on res://scenes/arena_proto.tscn -> complete full 30s core loop cleanly with 0 Debugger errors')
          .toString()
          .trim(),
      v02Presets: presets,
      v02NewPool: pool,
      v02UpgradesByLineageKey: upgradesMap,
      v02NewFeaturesByLineageKey: newFeaturesMap,
      lastCoDesignNote: (json['lastCoDesignNote'] ?? '').toString().trim(),
      approved: json['approved'] == true,
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(RegExp(r'\n|•'))
          .map((e) => e.replaceFirst(RegExp(r'^[\-\*\s]+'), '').trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return <String>[];
  }
}

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
          .replaceAll(RegExp(r'\bInputMap\b', caseSensitive: false), '')
          .replaceAll(RegExp(r'[()]'), ' ');
      for (final tok in cleanedInput.split(RegExp(r'[,/;]'))) {
        final c = tok.trim().toLowerCase();
        if (c.isNotEmpty) actions.add(c);
      }
    }

    final tscnRx = RegExp(r'res://[^\s,;)\]]+\.tscn', caseSensitive: false);
    String? testScene;
    for (final ep in epics) {
      for (final own in ep.sceneOwnership) {
        if (own.path.toLowerCase().endsWith('.tscn')) {
          testScene = own.path.trim();
          break;
        }
      }
      if (testScene != null) break;
      final m = tscnRx.firstMatch(ep.levelStaging);
      if (m != null) {
        testScene = m.group(0);
        break;
      }
    }
    testScene ??= tscnRx.firstMatch(spec.releaseDoneWhen)?.group(0);

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
        'Missing a .tscn playtest scene in E01 Scene Ownership',
      if (anyMissingCheck) 'One or more Features lack a Playtest Gate check',
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

/// Structured Stage 1 Co-Designer outcome surfacing real AI errors and modified `§01–§05` sections.
class Stage1AgentOutcome {
  final ProjectConceptBlueprint? blueprint;
  final bool usedOfflineFallback;
  final String? errorMessage;
  final Set<String> changedSections;

  const Stage1AgentOutcome({
    this.blueprint,
    this.usedOfflineFallback = false,
    this.errorMessage,
    this.changedSections = const <String>{},
  });
}

/// Context-aware quick-refine chip displayed below the Stage 1 Refine bar.
class QuickRefineSuggestion {
  final String label;
  final String instruction;

  const QuickRefineSuggestion({
    required this.label,
    required this.instruction,
  });
}
