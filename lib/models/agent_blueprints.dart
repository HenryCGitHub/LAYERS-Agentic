import 'epic_spec.dart';

export '../agents/concept/spark_clarifier.dart';
export 'presets/spark_presets.dart';

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

  String get decelCmPerSec => decelPxPerSec;

  String decelFor(GodotProjectDimension dim) =>
      dim == GodotProjectDimension.dim2d ? decelPxPerSec : decelMPerSec;
}

/// Stage 1 Unreal Engine 5 Root Project Specification (`PROJECT_SPEC.md` -> `ROOT_UNREAL_CONTEXT`).
/// Pure high-level foundation: Blueprint-First or C++ & BP Hybrid, `cm`/`cm/s`, pillars,
/// trade-offs, hard cuts, and strictly `v0.1` prototype Epics in §05.
class ProjectConceptBlueprint {
  String sparkPrompt;
  String gameTitle;
  GodotProjectDimension dimension;
  UnrealArchitectureMode architectureMode;

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
    this.gameTitle = 'UNTITLED UNREAL PROJECT',
    this.dimension = GodotProjectDimension.dim3d,
    this.architectureMode = UnrealArchitectureMode.blueprint,
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
        'Run PIE on /Game/Maps/Lvl_ArenaProto.umap -> complete full 30s core loop cleanly with 0 Message Log errors',
    List<ReleaseDirectionPreset>? v02Presets,
    List<EpicSpec>? v02NewPool,
    Map<String, List<EpicUpgradeOption>>? v02UpgradesByLineageKey,
    Map<String, List<FeatureSpec>>? v02NewFeaturesByLineageKey,
    this.lastCoDesignNote = '',
    this.approved = false,
  })  : cameraChoiceId = cameraChoiceId ?? 'isometric',
        cameraContract = cameraContract ??
            'USpringArmComponent TargetArmLength 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLagSpeed 9.0',
        characterScale = characterScale ??
            'ACharacter CapsuleRadius 42 cm · HalfHeight 92 cm · MaxWalkSpeed 620 cm/s',
        inputContract = inputContract ??
            'IMC_Gameplay (IA_Move, IA_Dodge, IA_PrimaryAction)',
        assetPolicy = assetPolicy ?? architectureMode.architectureContract,
        coreLoop = coreLoop ?? <String>[],
        cameraDecisionOptions =
            cameraDecisionOptions ?? defaultCamera3dOptions,
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
          'USpringArmComponent TargetArmLength 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLagSpeed 9.0',
      note: 'Best readability for arena movement + XY cursor plane aiming.',
    ),
    ConceptSectionOption(
      id: 'topdown',
      label: 'Fixed Top-Down (90 deg)',
      contractValue:
          'USpringArmComponent TargetArmLength 1650 cm @ -88 deg pitch, 50 deg FOV, Zero camera roll',
      note: 'Pure tactical arena clarity with minimal perspective skew.',
    ),
    ConceptSectionOption(
      id: 'tps',
      label: 'Third-Person Over-Shoulder',
      contractValue:
          'USpringArmComponent TargetArmLength 360 cm · SocketOffset (0, 65, 55) cm · 68 deg FOV · CameraLagSpeed 11.0',
      note: 'Close-quarters weight and horizon depth over rear flank awareness.',
    ),
    ConceptSectionOption(
      id: 'fps',
      label: 'First-Person (90 deg FOV)',
      contractValue:
          'UCameraComponent EyeHeight 165 cm · 90 deg FOV · Captured mouse yaw/pitch',
      note: 'Immediate eye-level aim precision with narrow peripheral awareness.',
    ),
    ConceptSectionOption(
      id: 'sidescroller',
      label: 'Side-Scroller Cam',
      contractValue:
          'USpringArmComponent TargetArmLength 950 cm · Ortho/Locked Track · 55 deg FOV · Lookahead 160 cm',
      note: 'Clear vertical platform clearance and grounded forward readability.',
    ),
  ];

  static const List<ConceptSectionOption> defaultCamera2dOptions =
      defaultCamera3dOptions;

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
      architectureMode: architectureMode,
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
        'architectureMode': architectureMode.id,
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
    final archMode = UnrealArchitectureMode.fromString(
      (json['architectureMode'] ?? json['mode'] ?? json['dimension'] ?? '')
          .toString(),
    );

    return ProjectConceptBlueprint(
      sparkPrompt: (json['sparkPrompt'] ?? json['prompt'] ?? '').toString(),
      gameTitle: (json['gameTitle'] ??
              json['title'] ??
              legacyGameSpec['title'] ??
              'UNTITLED UNREAL PROJECT')
          .toString()
          .trim(),
      dimension: dim,
      architectureMode: archMode,
      pitch: (json['pitch'] ?? json['goal'] ?? '').toString().trim(),
      coreLoop: loop,
      cameraChoiceId: (json['cameraChoiceId'] ?? 'isometric').toString().trim(),
      cameraContract: (json['cameraContract'] ??
              legacyGameSpec['camera'] ??
              'USpringArmComponent TargetArmLength 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLagSpeed 9.0')
          .toString()
          .trim(),
      characterScale: (json['characterScale'] ??
              'ACharacter CapsuleRadius 42 cm · HalfHeight 92 cm · MaxWalkSpeed 620 cm/s')
          .toString()
          .trim(),
      inputContract: (json['inputContract'] ??
              'IMC_Gameplay (IA_Move, IA_Dodge, IA_PrimaryAction)')
          .toString()
          .trim(),
      assetPolicy: (json['assetPolicy'] ?? archMode.architectureContract)
          .toString()
          .trim(),
      cameraDecisionOptions:
          cameraOpts.isEmpty ? defaultCamera3dOptions : cameraOpts,
      feelChoiceId: normalizeFeelChoiceId(json['feelChoiceId']?.toString()),
      pillars: _stringList(json['pillars'] ?? json['designPillars']),
      tradeOffs: trades,
      outOfScope: _stringList(json['outOfScope']),
      initialEpics: epics,
      releaseDoneWhen: (json['releaseDoneWhen'] ??
              json['doneWhen'] ??
              'Run PIE on /Game/Maps/Lvl_ArenaProto.umap -> complete full 30s core loop cleanly with 0 Message Log errors')
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
