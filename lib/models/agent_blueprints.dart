import 'epic_spec.dart';

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

/// Curated Godot 4 starter packs (`3D` and `2D`).
class GodotSparkPresetInfo {
  final String id;
  final String label;
  final String subtitle;
  final String sparkPrompt;

  const GodotSparkPresetInfo({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.sparkPrompt,
  });
}

class GodotSparkPresets {
  static const List<GodotSparkPresetInfo> entries = [
    GodotSparkPresetInfo(
      id: 'shellbreaker',
      label: 'Shellbreaker (3D)',
      subtitle: 'Top-down 3D crustacean mech arena shooter',
      sparkPrompt:
          'Top-down twin-stick crustacean mech arena shooter with claw dash armor breaks, heavy burst cannon recoil, and 3-wave combat.',
    ),
    GodotSparkPresetInfo(
      id: 'railjack',
      label: 'Railjack Drift (3D)',
      subtitle: 'Third-person hover-skiff canyon racer with boost & gates',
      sparkPrompt:
          'Third-person hover-skiff canyon time-trial racer with apex drift banking, thruster heat gauges, and plasma gate boosts.',
    ),
    GodotSparkPresetInfo(
      id: 'emberkeep',
      label: 'Ember Keep (2D)',
      subtitle: '2D pixel-art torchlight survival & axe cleave defense',
      sparkPrompt:
          '2D top-down survival skirmisher where you chop shadow stalkers, plant brazier light pylons, and hold safe ground as light radius shrinks.',
    ),
  ];

  static ProjectConceptBlueprint? matchSparkPrompt(String prompt) {
    final lower = prompt.toLowerCase().trim();
    if (lower.isEmpty) return null;
    if (RegExp(r'\bshellbreaker\b').hasMatch(lower) ||
        lower == entries[0].sparkPrompt.toLowerCase()) {
      return byId('shellbreaker');
    }
    if (RegExp(r'\brailjack\b').hasMatch(lower) ||
        lower == entries[1].sparkPrompt.toLowerCase()) {
      return byId('railjack');
    }
    if (RegExp(r'\bember\s*keep\b').hasMatch(lower) ||
        lower == entries[2].sparkPrompt.toLowerCase()) {
      return byId('emberkeep');
    }
    return null;
  }

  static ProjectConceptBlueprint byId(String id) {
    return switch (id) {
      'railjack' => _railjack(),
      'emberkeep' => _emberKeep(),
      _ => _shellbreaker(),
    };
  }

  static ProjectConceptBlueprint _shellbreaker() {
    return ProjectConceptBlueprint(
      sparkPrompt: entries[0].sparkPrompt,
      gameTitle: 'SHELLBREAKER',
      dimension: GodotProjectDimension.dim3d,
      pitch:
          'Crisp twin-stick 3D mech brawler — smash armored crabs inside a compact greybox arena',
      coreLoop: const [
        'Skim & Cursor Aim',
        'Claw Dash Slam',
        'Burst Armor Crack',
        'Recover & Reposition',
      ],
      cameraChoiceId: 'isometric',
      cameraContract:
          'SpringArm3D 14.5 m @ -52 deg pitch, 55 deg FOV, CameraLag 9.0 (XZ cursor plane aim)',
      characterScale:
          'CharacterBody3D CapsuleRadius 0.42 m · Height 1.84 m · move_speed 6.4 m/s',
      inputContract:
          'InputMap (move_left/right/up/down, claw_dash, fire_burst)',
      assetPolicy:
          'CSGBox3D / PrimitiveMesh Greybox + StandardMaterial3D Tints; res://data/shellbreaker_tuning.tres',
      feelChoiceId: 'snappy',
      cameraDecisionOptions: ProjectConceptBlueprint.defaultCamera3dOptions,
      pillars: const [
        'Aggressive Armor Cracking: Every dash creates an immediate weak-spot window',
        'Readable Telegraph Clarity: Distinct silhouette colors and sharp windup cues beat visual noise',
        'Zero-Lag Snap Response: Movement and cannon bursts fire on frame 1 with strict interrupt cancels',
      ],
      tradeOffs: const [
        TradeOffRule(
          prefer: 'Instant arcade acceleration',
          avoid: 'Heavy momentum turn inertia',
        ),
        TradeOffRule(
          prefer: 'Tight single-arena testbed',
          avoid: 'Multi-room streaming scenes',
        ),
        TradeOffRule(
          prefer: 'Clear emissive debug shapes',
          avoid: 'Premature skeletal rig detail',
        ),
      ],
      outOfScope: const [
        'No main menu, title screen, or save slots',
        'No inventory screen or multi-weapon loadout UI',
        'No co-op multiplayer networking',
        'No procedural terrain or multi-zone progression',
      ],
      releaseDoneWhen:
          'Run F6 on res://scenes/shellbreaker_proto.tscn -> dash and shatter dummy crab cleanly with 0 Debugger errors',
      initialEpics: [
        EpicSpec(
          id: 'sb_e01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Player Movement & Camera',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          coreLoopBeat: 'Beats 1–2 · Skim, Aim & Claw Dash',
          goal:
              'Own mech planar locomotion, cursor turret facing, horizontal claw dash commitments, and follow camera tracking.',
          inScope: const [
            '8-way arena XZ planar movement & mouse ground-plane aim',
            'Invulnerable 5.5 m forward Claw Dash with cooldown indicator',
            'Dampened SpringArm3D follow camera with cursor aim lead',
          ],
          doneWhen: const [
            'All E01 movement and dash Features pass Playtest Gate -> Camera & mech move smoothly with zero snag',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/shellbreaker_proto.tscn',
              role: '30x30 m walled greybox floor + cover pillars',
            ),
            EpicSceneOwnership(
              path: 'res://scenes/player_mech.tscn',
              role: 'CharacterBody3D root + VisualRig + DashHitbox',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/player_mech.gd',
              role: 'Movement state machine, aim raycast & @export physics',
            ),
          ],
          links: const [
            'Scene res://scenes/player_mech.tscn + res://scripts/player_mech.gd',
            'Emits dash_impact signal & hit_damage method contract to E03',
            'Drives SpringArm3D follow lag and dash thruster GPUParticles3D',
          ],
          outOfScope: const [
            'No slope stair-stepping mechanics',
            'No dash charge stacking',
          ],
          controls: [
            EpicControlBinding(
              action: 'move_left / move_right / move_up / move_down',
              trigger: 'Held (WASD)',
              rule: 'Ground velocity clamped cleanly at 6.4 m/s; locked during DashActive',
            ),
            EpicControlBinding(
              action: 'mouse_aim',
              trigger: 'Physics Tick Raycast',
              rule: r'Rotates $VisualRig child toward cursor XZ plane hit every frame',
            ),
            EpicControlBinding(
              action: 'claw_dash',
              trigger: 'Just Pressed (Space / RMB)',
              rule: 'Launches forward 5.5 m over 0.16s along aim vector on 1.1s cooldown',
            ),
          ],
          states: const [
            'Idle / Move -> DashWindup (0.04s) -> DashActive (0.16s) -> DashRecover (0.08s)',
          ],
          interrupts: const [
            'DashActive cancels weapon burst fire cleanly and toggles DashHitbox monitoring',
          ],
          tuning: [
            EpicTuningParam(key: 'move_speed', value: '6.4', unit: 'm/s'),
            EpicTuningParam(key: 'dash_distance', value: '5.5', unit: 'm'),
            EpicTuningParam(key: 'dash_duration', value: '0.16', unit: 's'),
            EpicTuningParam(key: 'dash_cooldown', value: '1.1', unit: 's'),
          ],
          feedback: const [
            'Orange emissive thruster trail during DashActive (0.16s)',
            'Compact radial cooldown arc inside Control HUD overlay',
            'Subtle camera punch on wall or enemy dash collision',
          ],
          levelStaging:
              'res://scenes/shellbreaker_proto.tscn: 30x30 m walled greybox floor + 2 solid CSG cover pillars + SpawnPoint at origin',
          checks: [
            EpicPieCheck(
              id: 'sb_e01_c1',
              text: 'Hold WASD -> mech accelerates smoothly to 6.4 m/s with zero wall snagging',
            ),
            EpicPieCheck(
              id: 'sb_e01_c2',
              text: 'Move cursor across floor -> VisualRig tracks aim vector smoothly without flip',
            ),
            EpicPieCheck(
              id: 'sb_e01_c3',
              text: 'Press Space -> dash travels ~5.5 m along aim direction and obeys 1.1s cooldown',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'sb_f01',
              code: 'F01',
              title: '8-Way Walk & Iso Camera',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.passed,
              goal:
                  'Move smoothly at 6.4 m/s across the arena XZ plane and orient VisualRig toward the mouse raycast target.',
              inScope: const [
                'WASD 8-way planar locomotion',
                'Ground-plane XZ cursor raycast aim',
                'Dampened SpringArm3D follow camera',
              ],
              doneWhen: const [
                'Hold WASD into cover pillars -> Mech slides smoothly without catching edges',
              ],
              controls: [
                EpicControlBinding(
                  action: 'move_left / move_right / move_up / move_down',
                  trigger: 'Held (WASD)',
                  rule: 'Accelerates immediately up to move_speed (6.4 m/s)',
                ),
                EpicControlBinding(
                  action: 'mouse_aim',
                  trigger: 'Physics Tick Raycast',
                  rule: 'Projects cursor ray onto XZ plane to rotate VisualRig',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'move_speed', value: '6.4', unit: 'm/s'),
                EpicTuningParam(key: 'cam_follow_damp', value: '9.0', unit: '1/s'),
              ],
              cues: const [
                'Floor aim ring highlights cursor intersection point cleanly',
              ],
              checks: [
                EpicPieCheck(
                  id: 'sb_f01_c1',
                  text: 'Hold WASD -> mech moves cleanly at 6.4 m/s with zero wall snagging',
                  passed: true,
                ),
                EpicPieCheck(
                  id: 'sb_f01_c2',
                  text: 'Move mouse across arena -> VisualRig tracks cursor accurately',
                  passed: true,
                ),
              ],
            ),
            FeatureSpec(
              id: 'sb_f02',
              code: 'F02',
              title: 'Armored Claw Dash',
              introducedIn: 'v0.1',
              sliceTime: '60 min',
              status: FeatureStatus.active,
              goal:
                  'Launch a 5.5 m forward commitment dash with thruster trail, invulnerability window, and 1.1 s cooldown.',
              inScope: const [
                'Space / RMB dash impulse over 0.16 s',
                'DashHitbox Area3D enemy impact trigger',
                'Radial cooldown HUD ring indicator',
              ],
              doneWhen: const [
                'Press Space -> Mech crosses 5.5 m cleanly and triggers dash_impact on crab shells',
              ],
              releaseDelta: '+55ms hitstop freeze & radial shockwave ring on Dash impact',
              releaseDeltaChecks: [
                EpicPieCheck(
                  id: 'sb_f02_dc1',
                  text: 'Strike crab during dash -> 55ms hitstop pauses impact with shockwave ring',
                ),
              ],
              controls: [
                EpicControlBinding(
                  action: 'claw_dash',
                  trigger: 'Just Pressed (Space / RMB)',
                  rule: 'Launches 5.5 m over 0.16 s along aim vector on 1.1 s cooldown',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'dash_distance', value: '5.5', unit: 'm'),
                EpicTuningParam(key: 'dash_duration', value: '0.16', unit: 's'),
                EpicTuningParam(key: 'dash_cooldown', value: '1.1', unit: 's'),
              ],
              cues: const [
                'Orange emissive thruster ribbon fires for 0.16 s',
                'Subtle camera punch on wall or crab shell impact',
              ],
              checks: [
                EpicPieCheck(
                  id: 'sb_f02_c1',
                  text: 'Press Space -> dash travels 5.5 m along aim vector and obeys 1.1 s cooldown',
                  passed: false,
                ),
              ],
            ),
          ],
          baselineSummary: const [
            '8-way movement at 6.4 m/s',
            'Cursor plane turret aim',
            '5.5 m invulnerable Claw Dash',
          ],
        ),
        EpicSpec(
          id: 'sb_e02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Claw Combat & Hitstop',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 3 · Burst Cannon Fire',
          goal:
              'Own kinetic bolt burst fire, weapon heat venting, directional recoil impulses, and shared impact feedback.',
          inScope: const [
            '3-round kinetic burst projectiles toward cursor aim',
            'Weapon heat cap gauge with 1.3 s overheat vent lock',
          ],
          doneWhen: const [
            'Hold LMB -> Bolts fire cleanly toward cursor with visible recoil and overheat cycle',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/kinetic_bolt.tscn',
              role: 'High-velocity projectile Area3D + emissive mesh',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/burst_cannon.gd',
              role: '3-round fire cadence, recoil push & heat tracker',
            ),
          ],
          links: const [
            'Spawns res://scenes/kinetic_bolt.tscn from player muzzle Marker3D',
            'Calls take_damage(amount) on E03 crab targets in enemy group',
          ],
          outOfScope: const [
            'No alternate ammo pickups',
            'No manual reload button',
          ],
          controls: [
            EpicControlBinding(
              action: 'fire_burst',
              trigger: 'Pressed / Held (LMB)',
              rule: 'Spawns 3-bolt burst over 0.24s when heat < 100 and not DashActive',
            ),
          ],
          states: const [
            'Ready -> BurstFiring (3 shots @ 0.08s interval) -> CycleCooldown (0.28s) -> Ready',
            'Heat >= 100 -> OverheatLock (1.3s vent) -> Ready',
          ],
          interrupts: const [
            'Triggering claw_dash immediately aborts remaining burst bolts safely',
            'Passive heat decay pauses for 0.35s right after last shot fired',
          ],
          tuning: [
            EpicTuningParam(key: 'bolt_speed', value: '24.0', unit: 'm/s'),
            EpicTuningParam(key: 'burst_damage', value: '18', unit: 'hp'),
            EpicTuningParam(key: 'overheat_time', value: '1.3', unit: 's'),
            EpicTuningParam(key: 'recoil_impulse', value: '1.2', unit: 'm/s'),
          ],
          feedback: const [
            'Bright yellow emissive projectile capsules with hit-spark burst on wall hit',
            'Barrel kicks back 0.18 m per shot and tweens smoothly forward',
            'Thin curved heat bar turns amber above 75%',
          ],
          levelStaging:
              'res://scenes/shellbreaker_proto.tscn: firing lane with static calibration cubes at 6 m and 14 m',
          checks: [
            EpicPieCheck(
              id: 'sb_e02_c1',
              text: 'Hold LMB -> fires crisp 3-bolt bursts toward cursor with visible barrel recoil',
            ),
            EpicPieCheck(
              id: 'sb_e02_c2',
              text: 'Sustained fire past cap -> triggers 1.3s overheat vent and resumes cleanly',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'sb_f03',
              code: 'F03',
              title: 'Kinetic Burst Cannon',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal:
                  'Spawn 3-bolt 24 m/s bursts toward cursor aim with backwards barrel recoil impulse.',
              inScope: const ['3-round 0.08 s cadence', '1.2 m/s chassis recoil push'],
              doneWhen: const ['Hold LMB -> 3 yellow bolts streak toward cursor with barrel kick'],
              controls: [
                EpicControlBinding(
                  action: 'fire_burst',
                  trigger: 'Held (LMB)',
                  rule: 'Fires 3 bolts when heat < 100 and not DashActive',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'bolt_speed', value: '24.0', unit: 'm/s'),
                EpicTuningParam(key: 'burst_damage', value: '18', unit: 'hp'),
                EpicTuningParam(key: 'recoil_impulse', value: '1.2', unit: 'm/s'),
              ],
              cues: const ['Barrel kicks back 0.18 m per bolt + hit sparks on wall collision'],
              checks: [
                EpicPieCheck(
                  id: 'sb_f03_c1',
                  text: 'Hold LMB -> fires 3-bolt bursts cleanly toward cursor aim',
                ),
              ],
            ),
            FeatureSpec(
              id: 'sb_f04',
              code: 'F04',
              title: 'Heat Vent & Weak-Point Crit',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal:
                  'Build heat per burst shot, lock cannon for 1.3 s at overheat, and boost damage on staggered targets.',
              inScope: const ['1.3 s OverheatLock vent cycle', 'HUD curved heat gauge'],
              doneWhen: const ['Fire continuously to cap -> Heat bar triggers 1.3 s vent cleanly'],
              releaseDelta: '+2x weak-point crit bolts vs staggered crabs (instant heat vent)',
              releaseDeltaChecks: [
                EpicPieCheck(
                  id: 'sb_f04_dc1',
                  text: 'Shoot staggered crab -> 2x amber crits trigger immediate heat vent',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'overheat_time', value: '1.3', unit: 's'),
              ],
              cues: const ['Heat gauge turns amber above 75% and vents steam at 100%'],
              checks: [
                EpicPieCheck(
                  id: 'sb_f04_c1',
                  text: 'Hold fire past cap -> vents for 1.3 s then resumes smoothly',
                ),
              ],
            ),
          ],
          baselineSummary: const [
            '3-round kinetic burst cannon',
            '1.3s overheat gauge vent',
            'Muzzle kick & impact spark',
          ],
        ),
        EpicSpec(
          id: 'sb_e03',
          code: 'E03',
          lineageKey: 'e03',
          title: 'Enemy Encounters & Armor Break',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beats 3–4 · Armor Crack & Reposition',
          goal:
              'Own enemy carapace durability vs core health, crimson lunge telegraphs, stagger interruptions, and encounter waves.',
          inScope: const [
            'Armored front shell vs dash-shatter stagger cycle',
            '0.45 s crimson lunge telegraph and melee pincer strike',
          ],
          doneWhen: const [
            'Dash through armored crab -> Shell cracks into 2.0 s stagger and bursts kill cleanly',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/crab_grunt.tscn',
              role: 'Enemy CharacterBody3D + front armor shield collider',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/crab_grunt.gd',
              role: 'Patrol / Windup / Lunge / Stagger AI state machine',
            ),
          ],
          links: const [
            'Scene res://scenes/crab_grunt.tscn + res://scripts/crab_grunt.gd',
            'Responds to take_damage() & apply_dash_shatter() from E01/E02',
          ],
          outOfScope: const [
            'No wave spawner director yet (placed directly in scene)',
            'No ranged enemy variants',
          ],
          controls: [
            EpicControlBinding(
              action: 'ai_lunge',
              trigger: 'AI Loop (4.2 m range)',
              rule: 'Faces player -> telegraphs 0.45s crimson flash -> lunges 4.2 m',
            ),
          ],
          states: const [
            'ArmoredAdvance -> PincerWindup (0.45s) -> PincerLunge -> ExposedStagger (2.0s) -> Dead',
          ],
          interrupts: const [
            'E01 Claw Dash hit shatters shell immediately and enters ExposedStagger (2.0s)',
            'Bolt impacts on intact shell deal 25% chip damage and emit metallic sparks',
          ],
          tuning: [
            EpicTuningParam(key: 'shell_hp', value: '60', unit: 'hp'),
            EpicTuningParam(key: 'core_hp', value: '90', unit: 'hp'),
            EpicTuningParam(key: 'telegraph_duration', value: '0.45', unit: 's'),
            EpicTuningParam(key: 'stagger_duration', value: '2.0', unit: 's'),
          ],
          feedback: const [
            'Front dome shifts from slate-grey armor to glowing magenta on Armor Break',
            'SubViewport floating HP + Armor bar above enemy mesh',
            'Enemy flashes solid white for 0.08s on exposed core hits',
          ],
          levelStaging:
              'res://scenes/shellbreaker_proto.tscn: 2 static CrabGrunt instances placed 12 m north of SpawnPoint',
          checks: [
            EpicPieCheck(
              id: 'sb_e03_c1',
              text: 'Shoot frontal shell -> reduced chip damage with flash until Claw Dash hits',
            ),
            EpicPieCheck(
              id: 'sb_e03_c2',
              text: 'Dash through crab -> armor shatters into 2.0s stagger and bursts kill cleanly',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'sb_f05',
              code: 'F05',
              title: 'Crab Pincer Telegraph Lunge',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal:
                  'Pursue player inside arena and commit to a 4.2 m forward lunge after a clear 0.45 s crimson telegraph.',
              inScope: const ['4.2 m aggro stop distance', '0.45 s crimson warning stripe'],
              doneWhen: const ['Approach crab -> 0.45 s crimson flash warns clearly before lunge'],
              controls: [
                EpicControlBinding(
                  action: 'ai_lunge',
                  trigger: 'AI Loop (4.2 m range)',
                  rule: 'Faces player -> telegraphs 0.45 s -> lunges 4.2 m',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'telegraph_duration', value: '0.45', unit: 's'),
                EpicTuningParam(key: 'lunge_range', value: '4.2', unit: 'm'),
              ],
              cues: const ['Glowing red windup telegraph strip ahead of pincers'],
              checks: [
                EpicPieCheck(
                  id: 'sb_f05_c1',
                  text: 'Stand within 4.2 m -> crimson telegraph warns 0.45 s before forward lunge',
                ),
              ],
            ),
            FeatureSpec(
              id: 'sb_f06',
              code: 'F06',
              title: 'Carapace Crack & Exposed Stagger',
              introducedIn: 'v0.1',
              sliceTime: '60 min',
              status: FeatureStatus.queued,
              goal:
                  'Mitigate bolt fire on intact frontal shell until Claw Dash shatters armor into a 2.0 s stagger window.',
              inScope: const ['60 hp shell vs 90 hp core split', '2.0 s ExposedStagger state'],
              doneWhen: const ['Dash into crab -> Armor turns glowing magenta for 2.0 s core vulnerability'],
              releaseDelta: '+Wall-slam knockback impulse & extra 25 hp wall smash damage',
              releaseDeltaChecks: [
                EpicPieCheck(
                  id: 'sb_f06_dc1',
                  text: 'Knock crab into arena wall -> 25 hp smash burst triggers cleanly',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'shell_hp', value: '60', unit: 'hp'),
                EpicTuningParam(key: 'core_hp', value: '90', unit: 'hp'),
                EpicTuningParam(key: 'stagger_duration', value: '2.0', unit: 's'),
              ],
              cues: const [
                'Front dome shifts slate-grey -> magenta on Armor Break',
                '0.08 s white impact flash on exposed core hits',
              ],
              checks: [
                EpicPieCheck(
                  id: 'sb_f06_c1',
                  text: 'Shoot intact shell -> reduced sparks; Claw Dash breaks armor into 2.0 s stagger',
                ),
              ],
            ),
          ],
          baselineSummary: const [
            'Armored front shell vs dash shatter',
            '0.45s pincer telegraph lunge',
            '2.0s ExposedStagger core vulnerability',
          ],
        ),
      ],
      v02Presets: const [
        ReleaseDirectionPreset(
          id: 'juice',
          label: 'Combat Juice Pass',
          description:
              'Tighten dash hitstop, add chain dash on shell break, and bring in 3-wave arena escalation.',
          upgradeIds: ['up_e01_hitstop', 'up_e03_knockback'],
          newEpicIds: ['e04_waves'],
        ),
        ReleaseDirectionPreset(
          id: 'defensive',
          label: 'Parry & Crowd Control',
          description:
              'Reward close-range shell parries while expanding the wave loop.',
          upgradeIds: ['up_e02_crit', 'up_e03_deathshatter'],
          newEpicIds: ['e04_waves', 'e05_parry'],
        ),
      ],
      v02UpgradesByLineageKey: {
        'e01': [
          EpicUpgradeOption(
            id: 'up_e01_hitstop',
            targetFeatureCode: 'F02',
            text: '+55ms hitstop freeze & radial shockwave ring on Dash impact',
            chosen: true,
          ),
          EpicUpgradeOption(
            id: 'up_e01_trail',
            targetFeatureCode: 'F02',
            text: '+Afterimage echo silhouette during DashActive',
          ),
        ],
        'e02': [
          EpicUpgradeOption(
            id: 'up_e02_crit',
            targetFeatureCode: 'F04',
            text: '+2x weak-point crit bolts vs staggered crabs (instant heat vent)',
          ),
        ],
        'e03': [
          EpicUpgradeOption(
            id: 'up_e03_knockback',
            targetFeatureCode: 'F06',
            text: '+Wall-slam knockback impulse & extra 25 hp wall smash damage',
            chosen: true,
          ),
          EpicUpgradeOption(
            id: 'up_e03_deathshatter',
            targetFeatureCode: 'F06',
            text: '+Explosive shell shards on crab death pushing adjacent grunts',
          ),
        ],
      },
      v02NewFeaturesByLineageKey: {
        'e01': [
          FeatureSpec(
            id: 'sb_f07_chain',
            code: 'F07',
            title: 'Chain Dash on Shell Break',
            introducedIn: 'v0.2',
            sliceTime: '45 min',
            status: FeatureStatus.active,
            goal:
                'Refund claw_dash cooldown immediately for 0.35 s after shattering an enemy shell.',
            inScope: const ['0.35 s chain grace timer', '1.2x chained dash burst speed'],
            doneWhen: const [
              'Shatter crab shell then tap Space -> Second dash chains immediately with zero wait',
            ],
            controls: [
              EpicControlBinding(
                action: 'claw_dash',
                trigger: 'Just Pressed (Space / RMB)',
                rule: 'Bypasses cooldown cleanly during 0.35 s chain window',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'chain_dash_distance', value: '5.5', unit: 'm'),
              EpicTuningParam(key: 'chain_window_s', value: '0.35', unit: 's'),
              EpicTuningParam(key: 'chain_speed_mult', value: '1.2', unit: 'x'),
            ],
            cues: const ['Pitch-up synth chirp + cyan wireframe afterimage mesh'],
            checks: [
              EpicPieCheck(
                id: 'sb_f07_c1',
                text: 'Crack crab armor then tap Space -> Second dash chains cleanly',
              ),
            ],
          ),
        ],
      },
      v02NewPool: [
        EpicSpec(
          id: 'sb_e04',
          code: 'E04',
          lineageKey: 'e04',
          title: 'Wave Escalation & Arena Reset',
          releaseVersion: 'v0.2',
          lifecycle: EpicLifecycle.newEpic,
          coreLoopBeat: 'Beat 4 · 3-Wave Escalation & Arena Reset',
          chosenForNextRelease: true,
          goal:
              'Spawn escalating 3-wave crab squads from perimeter gates with live wave banner and quick restart flow.',
          inScope: const ['4 perimeter SpawnGate spawners', 'HUD wave counter & R quick reset'],
          doneWhen: const ['Clear 3 waves -> Victory banner shows cleanly and R restarts in < 0.2 s'],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scripts/wave_director.gd',
              role: '3-wave squad timer, HUD counter & arena reset',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'sb_e04_f01',
              code: 'F01',
              title: '3-Wave Arena Spawner & Quick Restart',
              introducedIn: 'v0.2',
              sliceTime: '60 min',
              status: FeatureStatus.queued,
              goal: 'Spawn 3 escalating waves from 4 perimeter SpawnGates with HUD readout and R reset.',
              tuning: [
                EpicTuningParam(key: 'wave_1_count', value: '3', unit: 'count'),
                EpicTuningParam(key: 'breather_seconds', value: '2.0', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'sb_e04_f01_c1',
                  text: 'Clear Wave 1 -> 2.0 s breather plays and Wave 2 spawns from lit gates',
                ),
              ],
            ),
          ],
          links: const [
            'Instantiates res://scenes/crab_grunt.tscn (E03) at 4 perimeter Marker3D SpawnGates',
            'Updates Control HUD wave label and remaining enemy counter',
          ],
          outOfScope: const [
            'No endless wave scaling past Wave 3',
            'No boss cutscenes',
          ],
          controls: [
            EpicControlBinding(
              action: 'quick_restart',
              trigger: 'Just Pressed (R on Clear)',
              rule: 'Resets player HP/pos and restarts Wave 1 cleanly in < 0.2s',
            ),
          ],
          states: const [
            'WaveIntro (1.2s) -> WaveCombat -> WaveClear (2.0s breather) -> ArenaVictory',
          ],
          interrupts: const [
            'Player HP <= 0 transitions directly to ArenaDefeat overlay and stops active spawn timers',
          ],
          tuning: [
            EpicTuningParam(key: 'wave_1_count', value: '3', unit: 'count'),
            EpicTuningParam(key: 'wave_3_count', value: '7', unit: 'count'),
            EpicTuningParam(key: 'breather_seconds', value: '2.0', unit: 's'),
          ],
          feedback: const [
            'Perimeter floor pad pulses cyan 1.0s before spawning each grunt',
            'Top-center HUD Wave pill animates scale punch on wave transitions',
          ],
          levelStaging:
              'res://scenes/shellbreaker_proto.tscn: 4 SpawnGate Marker3D nodes placed along N/E/S/W walls',
          checks: [
            EpicPieCheck(
              id: 'sb_e04_c1',
              text: 'Kill all Wave 1 crabs -> 2.0s breather plays and Wave 2 spawns from lit gates',
            ),
            EpicPieCheck(
              id: 'sb_e04_c2',
              text: 'Press R after ArenaVictory -> resets arena immediately with 0 stale nodes',
            ),
          ],
        ),
        EpicSpec(
          id: 'sb_e05',
          code: 'E05',
          lineageKey: 'e05',
          title: 'Shell Reflect Guard',
          releaseVersion: 'v0.2',
          lifecycle: EpicLifecycle.newEpic,
          coreLoopBeat: 'Beats 2–3 · Guard Parry & Counter Stagger',
          goal:
              'Raise timed front energy buckler that staggers incoming crab lunges on tight guard timing.',
          inScope: const ['0.25 s front guard parry cone', '2.2 s attacker stagger counter'],
          doneWhen: const ['Press Q during red lunge telegraph -> Attacker stops and staggers 2.2 s'],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scripts/shell_guard.gd',
              role: 'Parry cone window & heat zero counter hook',
            ),
          ],
          links: const [
            'Coordinates with E01 player dash state and E03 PincerLunge overlap check',
          ],
          outOfScope: const [
            'No persistent hold block drain',
          ],
          controls: [
            EpicControlBinding(
              action: 'shell_guard',
              trigger: 'Just Pressed (Shift / Q)',
              rule: 'Opens 0.25s parry window; successful reflect staggers attacker 2.2s',
            ),
          ],
          states: const [
            'Ready -> GuardWindow (0.25s) -> ReflectFlash / MissRecover (0.45s)',
          ],
          interrupts: const [
            'Successful parry zeroes heat bar and allows immediate Dash cancel',
          ],
          tuning: [
            EpicTuningParam(key: 'parry_window', value: '0.25', unit: 's'),
            EpicTuningParam(key: 'parry_stagger', value: '2.2', unit: 's'),
          ],
          feedback: const [
            'Cyan arc shield mesh flashes front 120 deg cone during GuardWindow',
          ],
          levelStaging:
              'res://scenes/shellbreaker_proto.tscn: test directly against E03 Crab lunge telegraph',
          checks: [
            EpicPieCheck(
              id: 'sb_e05_c1',
              text: 'Press Q during crimson crab windup -> attacker stops and enters 2.2s stagger',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'sb_e05_f01',
              code: 'F01',
              title: 'Timed Buckler Parry Counter',
              introducedIn: 'v0.2',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Flash 120 deg front parry arc for 0.25 s to counter crab lunges and reset cannon heat.',
              tuning: [
                EpicTuningParam(key: 'parry_window', value: '0.25', unit: 's'),
                EpicTuningParam(key: 'parry_stagger', value: '2.2', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'sb_e05_f01_c1',
                  text: 'Press Q on red telegraph -> Crab staggers 2.2 s and cannon heat resets',
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static ProjectConceptBlueprint _railjack() {
    return ProjectConceptBlueprint(
      sparkPrompt: entries[1].sparkPrompt,
      gameTitle: 'RAILJACK DRIFT',
      dimension: GodotProjectDimension.dim3d,
      pitch:
          'High-speed 3D canyon hover-skiff racer — carve long drift arcs through boost gates to beat par time',
      coreLoop: const [
        'Carve Canyon Line',
        'Hold Apex Drift',
        'Chain Boost Gate',
        'Vent Thruster Heat',
      ],
      cameraChoiceId: 'tps',
      cameraContract:
          'SpringArm3D 4.4 m @ -12 deg pitch · Dynamic FOV 74->92 deg by speed · CameraLag 12.0',
      characterScale:
          'CharacterBody3D Hull 3.4x1.6 m · HoverHeight 0.85 m · top_speed 38.0 m/s',
      inputContract:
          'InputMap (throttle, steer_left, steer_right, drift_hold, boost_hold)',
      assetPolicy:
          'CSG / MeshInstance3D Canyon Track + Emissive Gate Frames; res://data/skiff_physics.tres',
      feelChoiceId: 'physics',
      cameraDecisionOptions: ProjectConceptBlueprint.defaultCamera3dOptions,
      pillars: const [
        'Flow Over Friction: Wall scrapes glance forward cleanly instead of dead-stopping momentum',
        'Speed Tells Everything: Camera FOV, engine pitch, and wing-tip trails rise smoothly into boost',
        'Drift-to-Earn Boost: Sustained cornering feeds thruster energy faster than straight coasting',
      ],
      tradeOffs: const [
        TradeOffRule(
          prefer: 'Snappy hovering spring stabilization',
          avoid: 'Wild upside-down physics tumbling',
        ),
        TradeOffRule(
          prefer: 'Single 60s canyon circuit loop',
          avoid: 'Open-world streaming terrain',
        ),
      ],
      outOfScope: const [
        'No AI opponent rubber-banding',
        'No garage paint shop or parts crafting',
        'No multiplayer ghost leaderboards',
      ],
      releaseDoneWhen:
          'Run F6 on res://scenes/canyon_proto.tscn -> complete 1 clean canyon lap with final timer HUD and 0 Debugger errors',
      initialEpics: [
        EpicSpec(
          id: 'rj_e01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Skiff Handling & Drift Physics',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          coreLoopBeat: 'Beats 1–2 · Carve Canyon Line & Hold Apex Drift',
          goal:
              'Own hover suspension clearance over canyon slopes, banking turns, and drift slip-angle charging.',
          inScope: const [
            '0.85 m spring hover height stabilization',
            'ApexDrift carving that feeds boost charge',
          ],
          doneWhen: const [
            'Carve hairpin canyon turn -> Skiff maintains 0.85 m height and exits cleanly on tangent',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/canyon_proto.tscn',
              role: 'Banked greybox canyon track loop',
            ),
            EpicSceneOwnership(
              path: 'res://scenes/hover_skiff.tscn',
              role: 'CharacterBody3D skiff hull + Camera3D rig',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/hover_skiff.gd',
              role: 'Hover raycast springs + drift slip math',
            ),
          ],
          links: const [
            'Scene res://scenes/hover_skiff.tscn + res://scripts/hover_skiff.gd',
            'Exposes speed_ratio & is_drifting signals to E02 Boost & E03 Gate HUD',
          ],
          outOfScope: const [
            'No upside-down loop-the-loop gravity shifts',
          ],
          controls: [
            EpicControlBinding(
              action: 'throttle',
              trigger: 'Held (W / Up)',
              rule: 'Accelerates forward velocity smoothly up to base_top_speed 31.0 m/s',
            ),
            EpicControlBinding(
              action: 'steer_left / steer_right',
              trigger: 'Held (A / D)',
              rule: 'Banks VisualRig roll +/-26 deg smoothly while turning yaw rate',
            ),
            EpicControlBinding(
              action: 'drift_hold',
              trigger: 'Held (Space / Shift)',
              rule: 'Widens lateral slip angle, locks forward carry, and builds drift charge/s',
            ),
          ],
          states: const [
            'GripCruise -> ApexDrift (Charges Boost) -> CornerExitSnap -> GripCruise',
          ],
          interrupts: const [
            'Wall glance clamps normal impact speed to 78% and slides hull along tangent safely',
          ],
          tuning: [
            EpicTuningParam(key: 'hover_height', value: '0.85', unit: 'm'),
            EpicTuningParam(key: 'base_top_speed', value: '31.0', unit: 'm/s'),
            EpicTuningParam(key: 'max_bank_angle', value: '26', unit: 'deg'),
            EpicTuningParam(key: 'drift_charge_rate', value: '35', unit: '%/s'),
          ],
          feedback: const [
            'Twin cyan thrusters lengthen with throttle and flare orange during ApexDrift',
            'Dynamic Camera3D FOV expands smoothly from 74 to 92 deg with forward velocity',
          ],
          levelStaging:
              'res://scenes/canyon_proto.tscn: wide banked greybox canyon track (~40s loop) with hairpin turn',
          checks: [
            EpicPieCheck(
              id: 'rj_e01_c1',
              text: 'Drive over sloped ramp -> hull holds ~0.85 m clearance without floor clipping',
            ),
            EpicPieCheck(
              id: 'rj_e01_c2',
              text: 'Hold Space + A/D in hairpin -> skiff enters clean drift slide and exits cleanly',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'rj_f01',
              code: 'F01',
              title: 'Hover Spring & Throttle Drive',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.passed,
              goal: 'Keep hull hovering at 0.85 m across slopes while cruising up to 31.0 m/s.',
              inScope: const ['Raycast ground spring', 'W/A/D steer banking +/-26 deg'],
              doneWhen: const ['Ride canyon slope -> Hull holds 0.85 m clearance without scraping'],
              controls: [
                EpicControlBinding(
                  action: 'throttle',
                  trigger: 'Held (W / Up)',
                  rule: 'Accelerates smoothly up to 31.0 m/s',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'hover_height', value: '0.85', unit: 'm'),
                EpicTuningParam(key: 'base_top_speed', value: '31.0', unit: 'm/s'),
              ],
              cues: const ['Twin cyan thrusters scale cleanly with throttle'],
              checks: [
                EpicPieCheck(
                  id: 'rj_f01_c1',
                  text: 'Drive across ramp -> Skiff maintains 0.85 m hover gap cleanly',
                  passed: true,
                ),
              ],
            ),
            FeatureSpec(
              id: 'rj_f02',
              code: 'F02',
              title: 'Apex Drift Carve & Charge',
              introducedIn: 'v0.1',
              sliceTime: '60 min',
              status: FeatureStatus.active,
              goal: 'Widen lateral drift slip when holding Space and charge thruster meter cleanly.',
              inScope: const ['Space drift slip angle lock', '35 %/s drift boost generation'],
              doneWhen: const ['Hold Space + A/D in hairpin -> Thrusters flare orange and charge rises'],
              controls: [
                EpicControlBinding(
                  action: 'drift_hold',
                  trigger: 'Held (Space / Shift)',
                  rule: 'Enters ApexDrift and charges boost meter',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'max_bank_angle', value: '26', unit: 'deg'),
                EpicTuningParam(key: 'drift_charge_rate', value: '35', unit: '%/s'),
              ],
              cues: const ['Wing thrusters flare orange with faint tire/air sparks'],
              checks: [
                EpicPieCheck(
                  id: 'rj_f02_c1',
                  text: 'Hold Space + A/D in turn -> Carves smooth slide and charges boost meter',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'rj_e02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Thruster Boost & Heat System',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 3 · Chain Boost & Thruster Surge',
          goal:
              'Spend accumulated boost meter for an immediate velocity surge while managing thruster overheat risk.',
          inScope: const ['42.0 m/s manual boost surge', '1.5 s overheat lockout vent'],
          doneWhen: const ['Hold E with boost -> Speed surges to 42.0 m/s and HUD bar responds'],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scripts/thruster_boost.gd',
              role: 'Boost drain curve, heat cap & FOV kick emitter',
            ),
          ],
          links: const [
            'Consumes drift charge from E01 and boost gate pulses from E03',
          ],
          outOfScope: const [
            'No combat missiles or shield energy sharing',
          ],
          controls: [
            EpicControlBinding(
              action: 'boost_hold',
              trigger: 'Held (RMB / E)',
              rule: 'Pushes target speed to 42.0 m/s while draining boost meter',
            ),
          ],
          states: const [
            'Normal -> Boosting (Max 42.0 m/s) -> OverheatLockout (1.5s) -> Normal',
          ],
          interrupts: const [
            'Touching E03 Boost Gate grants instant +0.8s surge without raising heat',
          ],
          tuning: [
            EpicTuningParam(key: 'boost_top_speed', value: '42.0', unit: 'm/s'),
            EpicTuningParam(key: 'boost_drain_rate', value: '28', unit: '%/s'),
            EpicTuningParam(key: 'overheat_cooldown', value: '1.5', unit: 's'),
          ],
          feedback: const [
            'Edge speed-lines Control overlay + bright white exhaust core while Boosting',
            'Centered horizontal thruster progress bar shows m/s & Boost %',
          ],
          levelStaging:
              'res://scenes/canyon_proto.tscn: straightaway run + speed readout HUD overlay',
          checks: [
            EpicPieCheck(
              id: 'rj_e02_c1',
              text: 'Hold E with Boost available -> velocity jumps smoothly to 42.0 m/s with widened FOV',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'rj_f03',
              code: 'F03',
              title: 'Manual Thruster Surge & FOV',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Accelerate top speed to 42.0 m/s when holding E while widening Camera3D FOV.',
              tuning: [
                EpicTuningParam(key: 'boost_top_speed', value: '42.0', unit: 'm/s'),
              ],
              cues: const ['White exhaust core + widened FOV 92 deg speed-lines'],
              checks: [
                EpicPieCheck(
                  id: 'rj_f03_c1',
                  text: 'Hold E on straightaway -> Velocity surges to 42.0 m/s smoothly',
                ),
              ],
            ),
            FeatureSpec(
              id: 'rj_f04',
              code: 'F04',
              title: 'Plasma Heat Cap & Vent Lock',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Lock thruster after sustained overheat for 1.5 s with centered m/s and % HUD gauge.',
              tuning: [
                EpicTuningParam(key: 'overheat_cooldown', value: '1.5', unit: 's'),
              ],
              cues: const ['Thruster bar flashes red during 1.5 s vent'],
              checks: [
                EpicPieCheck(
                  id: 'rj_f04_c1',
                  text: 'Push heat past 100% -> 1.5 s vent locks boost cleanly until cooled',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'rj_e03',
          code: 'E03',
          lineageKey: 'e03',
          title: 'Track Gates & Time-Trial Loop',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beats 3–4 · Checkpoint Gates & Lap Closure',
          goal:
              'Own sequential canyon gate progression, gate surge triggers, off-course warnings, and lap timer HUD.',
          inScope: const ['6 sequential boost gate rings', 'Par timer HUD & R instant reset'],
          doneWhen: const ['Pass Gate 1..6 -> Gate 6 posts final mm:ss.ms lap time cleanly'],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scripts/lap_timer_hud.gd',
              role: 'Gate sequencer, par delta readout & R track reset',
            ),
          ],
          links: const [
            'Connects Area3D body_entered from HoverSkiff (E01) to E02 surge pulse',
          ],
          outOfScope: const [
            'No persistent ghost replay serialization',
          ],
          controls: [
            EpicControlBinding(
              action: 'reset_track',
              trigger: 'Just Pressed (R)',
              rule: 'Snaps skiff cleanly to StartLine Marker3D and resets lap_timer to 0.00s',
            ),
          ],
          states: const [
            'Countdown (0.8s) -> Racing (Gate 1..6) -> LapFinished (Display Final Time)',
          ],
          interrupts: const [
            'Skipping an ordered gate shows floating OFF-COURSE HUD arrow toward missed gate',
          ],
          tuning: [
            EpicTuningParam(key: 'gate_half_width', value: '4.8', unit: 'm'),
            EpicTuningParam(key: 'gate_boost_duration', value: '0.8', unit: 's'),
            EpicTuningParam(key: 'par_time_seconds', value: '42.0', unit: 's'),
          ],
          feedback: const [
            'Active next gate glows bright emerald; passed gates turn muted slate',
            'Top-right Control timer displays mm:ss.ms + green/red delta vs par time',
          ],
          levelStaging:
              'res://scenes/canyon_proto.tscn: 6 sequential boost gate Area3D arches ending at Start/Finish',
          checks: [
            EpicPieCheck(
              id: 'rj_e03_c1',
              text: 'Pass Gate 1..6 sequentially -> next-gate highlight advances and Gate 6 posts Lap Time',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'rj_f05',
              code: 'F05',
              title: 'Ordered Boost Gate Arches',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Highlight next emerald gate arch and trigger free 0.8 s velocity pulse on pass.',
              tuning: [
                EpicTuningParam(key: 'gate_half_width', value: '4.8', unit: 'm'),
                EpicTuningParam(key: 'gate_boost_duration', value: '0.8', unit: 's'),
              ],
              cues: const ['Active gate glows bright emerald; off-course points back on skip'],
              checks: [
                EpicPieCheck(
                  id: 'rj_f05_c1',
                  text: 'Fly through Gate 1 -> Gate pulses 0.8 s speed boost and highlights Gate 2',
                ),
              ],
            ),
            FeatureSpec(
              id: 'rj_f06',
              code: 'F06',
              title: 'Lap Timer HUD & Track Reset',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Track mm:ss.ms elapsed race clock against 42.0 s par and snap to StartLine on R.',
              tuning: [
                EpicTuningParam(key: 'par_time_seconds', value: '42.0', unit: 's'),
              ],
              cues: const ['Green/red split delta flashes cleanly across top-right HUD'],
              checks: [
                EpicPieCheck(
                  id: 'rj_f06_c1',
                  text: 'Press R -> Skiff resets to StartLine at 0.00 s cleanly',
                ),
              ],
            ),
          ],
        ),
      ],
      v02NewFeaturesByLineageKey: {
        'e01': [
          FeatureSpec(
            id: 'rj_f07_wallglide',
            code: 'F07',
            title: 'Canyon Wall Scrape Sparks',
            introducedIn: 'v0.2',
            sliceTime: '30 min',
            status: FeatureStatus.active,
            goal: 'Preserve 78% tangential velocity during cliff wall touches with directional hull sparks.',
            tuning: [
              EpicTuningParam(key: 'wall_keep_pct', value: '78', unit: '%'),
            ],
            checks: [
              EpicPieCheck(
                id: 'rj_f07_c1',
                text: 'Graze canyon wall -> Hull sparks fly and forward momentum glides smoothly',
              ),
            ],
          ),
        ],
      },
    );
  }

  static ProjectConceptBlueprint _emberKeep() {
    return ProjectConceptBlueprint(
      sparkPrompt: entries[2].sparkPrompt,
      gameTitle: 'EMBER KEEP',
      dimension: GodotProjectDimension.dim2d,
      pitch:
          'Tactical 2D top-down torch defense — cleave shadow stalkers while guarding shrinking brazier light rings',
      coreLoop: const [
        'Swing Torch Axe',
        'Plant Brazier Light',
        'Hold Safe Radius',
        'Collect Ash Shards',
      ],
      cameraChoiceId: 'topdown2d',
      cameraContract:
          'Camera2D Zoom 1.0x · PositionSmoothing 8.0 · Cursor 2D world aim',
      characterScale:
          'CharacterBody2D CollisionShape 32x40 px · walk_speed 260 px/s',
      inputContract:
          'InputMap (move_left/right/up/down, axe_swing, plant_brazier)',
      assetPolicy:
          'Polygon2D / ColorRect Keep Courtyard + PointLight2D (CanvasModulate dusk tint); @export vars',
      feelChoiceId: 'heavy',
      cameraDecisionOptions: ProjectConceptBlueprint.defaultCamera2dOptions,
      pillars: const [
        'Light Defines Territory: Every 2D light circle visibly alters enemy aggression and player safety',
        'Deliberate Heavy Swings: Axe cleaves carry distinct windup weight rather than rapid spam',
      ],
      tradeOffs: const [
        TradeOffRule(
          prefer: 'Dynamic 2D radial light circles for instant clarity',
          avoid: 'Static darkness masks',
        ),
        TradeOffRule(
          prefer: 'Compact 1280x1280 px courtyard',
          avoid: 'Procedural forest chunks',
        ),
      ],
      outOfScope: const [
        'No hunger, thirst, or weather meters',
        'No inventory drag-and-drop grid',
        'No crafting bench menus',
      ],
      releaseDoneWhen:
          'Run F6 on res://scenes/keep_proto.tscn -> plant brazier and fend off 3 shadow stalkers with 0 Debugger errors',
      initialEpics: [
        EpicSpec(
          id: 'ek_e01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Keeper Movement & 2D Combat',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          coreLoopBeat: 'Beat 1 · Swing Torch Axe',
          goal:
              'Own 2D top-down keeper locomotion, snapped Camera2D tracking, and heavy directional axe cleaves.',
          inScope: const [
            'Normalized 260 px/s 2D courtyard walk & Camera2D smoothing',
            '0.18 s windup 140 deg torch axe cleave pushing stalkers back',
          ],
          doneWhen: const [
            'Walk and swing across keep courtyard -> 96 px cleave arc knocks shadow stalkers back cleanly',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/keep_proto.tscn',
              role: '1280x1280 px 2D stone courtyard + TileMapLayer walls',
            ),
            EpicSceneOwnership(
              path: 'res://scenes/keeper_player.tscn',
              role: 'CharacterBody2D hero + Camera2D + PointLight2D',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/keeper_player.gd',
              role: '2D movement loop & @export px/s axe cleave vars',
            ),
          ],
          links: const [
            'Scene res://scenes/keeper_player.tscn + res://scripts/keeper_player.gd',
            'Applies cleave knockback & damage to E03 Shadow Stalkers in enemy group',
          ],
          outOfScope: const [
            'No multi-weapon swapping',
          ],
          controls: [
            EpicControlBinding(
              action: 'move_left / move_right / move_up / move_down',
              trigger: 'Held WASD',
              rule: 'Moves keeper at 260 px/s; slowed 50% during AxeWindup',
            ),
            EpicControlBinding(
              action: 'axe_swing',
              trigger: 'Just Pressed (LMB)',
              rule: '0.18s windup -> 140 deg Area2D cleave hitbox out to 96 px reach',
            ),
          ],
          states: const [
            'Idle / Move -> AxeWindup (0.18s) -> AxeStrike (0.12s) -> AxeRecover (0.20s)',
          ],
          interrupts: const [
            'Planting a Brazier (E02) takes priority over AxeRecover',
          ],
          tuning: [
            EpicTuningParam(key: 'walk_speed', value: '260', unit: 'px/s'),
            EpicTuningParam(key: 'cleave_radius', value: '96', unit: 'px'),
            EpicTuningParam(key: 'cleave_damage', value: '40', unit: 'hp'),
            EpicTuningParam(key: 'knockback_impulse', value: '320', unit: 'px/s'),
          ],
          feedback: const [
            'Translucent amber 140 deg floor arc Polygon2D flashes on AxeStrike',
            'Carried PointLight2D flickers brighter during swing impact',
          ],
          levelStaging:
              'res://scenes/keep_proto.tscn: 1280x1280 px 2D stone courtyard + central bonfire + TileMapLayer walls',
          checks: [
            EpicPieCheck(
              id: 'ek_e01_c1',
              text: 'Press LMB facing cursor -> axe cleave hits 96 px cone and shoves dummy target back',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'ek_f01',
              code: 'F01',
              title: '2D Grid Walk & Camera2D',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.passed,
              goal: 'Move keeper smoothly at 260 px/s with smoothed Camera2D courtyard tracking.',
              controls: [
                EpicControlBinding(
                  action: 'move_2d',
                  trigger: 'Held (WASD)',
                  rule: 'Moves CharacterBody2D at walk_speed (260 px/s)',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'walk_speed', value: '260', unit: 'px/s'),
              ],
              cues: const ['Carried PointLight2D flickers gently with movement'],
              checks: [
                EpicPieCheck(
                  id: 'ek_f01_c1',
                  text: 'Walk across courtyard -> Moves cleanly at 260 px/s with zero wall snagging',
                  passed: true,
                ),
              ],
            ),
            FeatureSpec(
              id: 'ek_f02',
              code: 'F02',
              title: '140-Deg Heavy Torch Cleave',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.active,
              goal: 'Wind up for 0.18 s and sweep a 96 px amber cleave sector knocking stalkers back.',
              controls: [
                EpicControlBinding(
                  action: 'axe_swing',
                  trigger: 'Just Pressed (LMB)',
                  rule: '0.18 s windup -> 140 deg Area2D cleave at 96 px reach',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'cleave_radius', value: '96', unit: 'px'),
                EpicTuningParam(key: 'cleave_damage', value: '40', unit: 'hp'),
                EpicTuningParam(key: 'knockback_impulse', value: '320', unit: 'px/s'),
              ],
              cues: const ['Amber 140 deg Polygon2D slash arc flashes on AxeStrike'],
              checks: [
                EpicPieCheck(
                  id: 'ek_f02_c1',
                  text: 'Click LMB facing target -> Cleaves 96 px sector and knocks target back',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'ek_e02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Brazier Light & Safe Zones',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beats 2–3 · Plant Brazier & Hold Safe Radius',
          goal:
              'Deploy temporary 2D braziers projecting shrinking PointLight2D rings and fuel stoking loops.',
          inScope: const ['220 px safe radius placement 56 px ahead', '18 s flame decay curve'],
          doneWhen: const ['Press E -> Brazier lights 220 px circle and shrinks smoothly over 18 s'],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/field_brazier.tscn',
              role: 'Placed brazier Node2D + PointLight2D + Line2D border',
            ),
          ],
          links: const [
            'Instantiates res://scenes/field_brazier.tscn and registers active light radius for E03',
          ],
          outOfScope: const [
            'No defensive stone wall grid snapping',
          ],
          controls: [
            EpicControlBinding(
              action: 'plant_brazier',
              trigger: 'Just Pressed (RMB / E)',
              rule: 'Spawns field_brazier.tscn 56 px ahead if amber_fuel >= 1',
            ),
          ],
          states: const [
            'Ignited (Full 220 px radius) -> Flickering (< 80 px) -> Extinguished',
          ],
          interrupts: const [
            'Hitting a planted brazier with AxeStrike stokes +4s burn lifetime cleanly',
          ],
          tuning: [
            EpicTuningParam(key: 'start_light_radius', value: '220', unit: 'px'),
            EpicTuningParam(key: 'burn_duration', value: '18.0', unit: 's'),
            EpicTuningParam(key: 'max_active_braziers', value: '3', unit: 'count'),
          ],
          feedback: const [
            'Crisp Line2D floor ring matches current PointLight2D safe attenuation radius',
          ],
          levelStaging:
              'res://scenes/keep_proto.tscn: dark perimeter corners contrast central lit courtyard circle',
          checks: [
            EpicPieCheck(
              id: 'ek_e02_c1',
              text: 'Press E -> brazier illuminates 220 px circle and shrinks smoothly over 18s',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'ek_f03',
              code: 'F03',
              title: 'Plant Brazier Light Pylon',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Spawn a 220 px PointLight2D brazier 56 px ahead up to 3 active nodes.',
              tuning: [
                EpicTuningParam(key: 'start_light_radius', value: '220', unit: 'px'),
                EpicTuningParam(key: 'max_active_braziers', value: '3', unit: 'count'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ek_f03_c1',
                  text: 'Press E -> Plants brazier lighting 220 px circle on dark stone',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ek_f04',
              code: 'F04',
              title: 'Flame Decay & Axe Stoke',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Shrink safe radius over 18 s and grant +4 s burn duration when struck by AxeStrike.',
              tuning: [
                EpicTuningParam(key: 'burn_duration', value: '18.0', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ek_f04_c1',
                  text: 'Swipe planted brazier -> Light ring flares outward +4 s lifetime',
                ),
              ],
            ),
          ],
        ),
        EpicSpec(
          id: 'ek_e03',
          code: 'E03',
          lineageKey: 'e03',
          title: 'Shadow Encounters & Recoil',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beats 3–4 · Shadow Recoil & Ash Shards',
          goal:
              'Own shadow enemy pursuit inside darkness, light-burst recoil interrupts, and courtyard waves.',
          inScope: const ['190 px/s shadow prowl AI', '310 px/s light recoil flee interrupt'],
          doneWhen: const ['Light brazier near stalker -> Stalker screeches and recoils past lit perimeter'],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/shadow_stalker.tscn',
              role: '2D enemy CharacterBody2D + light proximity sensor',
            ),
          ],
          links: const [
            'Scene res://scenes/shadow_stalker.tscn queries E02 active light circles & E01 cleave hits',
          ],
          outOfScope: const [
            'No ranged shadow projectile casters',
          ],
          controls: [
            EpicControlBinding(
              action: 'ai_stalk_flee',
              trigger: 'Physics Tick AI',
              rule: 'Circles outside bright core -> dashes in when light dips -> flees on ignition',
            ),
          ],
          states: const [
            'ShadowProwl -> BiteLunge -> LightRecoil (1.2s) -> Dead (Drop 1 EmberFuel)',
          ],
          interrupts: const [
            'Fresh Brazier ignition inside 220 px forces instant LightRecoil and cancels BiteLunge',
          ],
          tuning: [
            EpicTuningParam(key: 'stalker_hp', value: '80', unit: 'hp'),
            EpicTuningParam(key: 'prowl_speed', value: '190', unit: 'px/s'),
            EpicTuningParam(key: 'recoil_speed', value: '310', unit: 'px/s'),
          ],
          feedback: const [
            'Glowing violet eye slits dim whenever forced into LightRecoil',
          ],
          levelStaging:
              'res://scenes/keep_proto.tscn: 3 stalker spawns stationed around dark courtyard corners',
          checks: [
            EpicPieCheck(
              id: 'ek_e03_c1',
              text: 'Plant brazier near approaching stalker -> stalker screeches and flees outside lit ring',
            ),
          ],
          features: [
            FeatureSpec(
              id: 'ek_f05',
              code: 'F05',
              title: 'Shadow Stalker Prowl AI',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Orbit dimly lit zones at 190 px/s and dart toward keeper when light shrinks.',
              tuning: [
                EpicTuningParam(key: 'stalker_hp', value: '80', unit: 'hp'),
                EpicTuningParam(key: 'prowl_speed', value: '190', unit: 'px/s'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ek_f05_c1',
                  text: 'Stand in dimming courtyard -> Stalker creeps inward at 190 px/s',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ek_f06',
              code: 'F06',
              title: 'Ignition Light Recoil Flee',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Cancel enemy BiteLunge cleanly and push stalker outward at 310 px/s on fresh light.',
              tuning: [
                EpicTuningParam(key: 'recoil_speed', value: '310', unit: 'px/s'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ek_f06_c1',
                  text: 'Plant brazier near stalker -> Eye slits dim and stalker flees outside ring',
                ),
              ],
            ),
          ],
        ),
      ],
      v02NewFeaturesByLineageKey: {
        'e01': [
          FeatureSpec(
            id: 'ek_f07_roll',
            code: 'F07',
            title: '2D Ember Roll Dodge',
            introducedIn: 'v0.2',
            sliceTime: '45 min',
            status: FeatureStatus.active,
            goal: 'Roll 128 px past stalker bites at 480 px/s with 0.55 s cooldown.',
            tuning: [
              EpicTuningParam(key: 'roll_speed', value: '480', unit: 'px/s'),
              EpicTuningParam(key: 'roll_dist', value: '128', unit: 'px'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ek_f07_c1',
                text: 'Press Space -> Keeper rolls 128 px cleanly with ember dust',
              ),
            ],
          ),
        ],
      },
    );
  }
}
