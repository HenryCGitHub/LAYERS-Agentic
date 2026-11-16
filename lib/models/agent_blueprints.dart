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
  final String brakingDecelCmPerSec;

  const CoreFeelOption({
    required this.id,
    required this.label,
    required this.tradeOff,
    required this.brakingDecelCmPerSec,
  });
}

/// Stage 1 Unreal Root Project Specification (`PROJECT_SPEC.md` -> `ROOT_MCP_CONTEXT`).
/// Pure high-level foundation: 1 UU = 1 cm spatial contracts, pillars, trade-offs, hard cuts,
/// and strictly `v0.1` prototype Epics in §05.
class ProjectConceptBlueprint {
  String sparkPrompt;
  String gameTitle;
  UnrealTargetEngine targetEngine;

  // §01 Core Fantasy & 30s Loop
  String pitch;
  List<String> coreLoop;

  // §02 Global Unreal Scale & Architecture (1 UU = 1 cm)
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

  String lastCoDesignNote;
  bool approved;

  ProjectConceptBlueprint({
    this.sparkPrompt = '',
    this.gameTitle = 'UNTITLED UNREAL PROJECT',
    this.targetEngine = UnrealTargetEngine.ue5Mcp,
    this.pitch = '',
    List<String>? coreLoop,
    this.cameraChoiceId = 'isometric',
    this.cameraContract =
        'SpringArm 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLag 9.0',
    this.characterScale =
        'ACharacter CapsuleRadius 42 cm · HalfHeight 92 cm · MaxWalkSpeed 620 cm/s',
    this.inputContract =
        'Enhanced Input (IMC_Core + IA_Move / IA_Aim / IA_Primary / IA_Secondary)',
    this.assetPolicy =
        'Prototype Greybox Primitives (Engine/BasicShapes) + Debug Materials; UDataAsset for tuning',
    List<ConceptSectionOption>? cameraDecisionOptions,
    this.feelChoiceId = 'snappy',
    List<String>? pillars,
    List<TradeOffRule>? tradeOffs,
    List<String>? outOfScope,
    List<EpicSpec>? initialEpics,
    this.releaseDoneWhen =
        'Start PIE in L_Arena_Proto -> complete full 30s core loop cleanly with 0 Output Log errors',
    List<ReleaseDirectionPreset>? v02Presets,
    List<EpicSpec>? v02NewPool,
    Map<String, List<EpicUpgradeOption>>? v02UpgradesByLineageKey,
    this.lastCoDesignNote = '',
    this.approved = false,
  })  : coreLoop = coreLoop ?? <String>[],
        cameraDecisionOptions =
            cameraDecisionOptions ?? defaultCameraDecisionOptions,
        pillars = pillars ?? <String>[],
        tradeOffs = tradeOffs ?? <TradeOffRule>[],
        outOfScope = outOfScope ?? <String>[],
        initialEpics = initialEpics ?? <EpicSpec>[],
        v02Presets = v02Presets ?? <ReleaseDirectionPreset>[],
        v02NewPool = v02NewPool ?? <EpicSpec>[],
        v02UpgradesByLineageKey =
            v02UpgradesByLineageKey ?? <String, List<EpicUpgradeOption>>{};

  static const List<ConceptSectionOption> defaultCameraDecisionOptions = [
    ConceptSectionOption(
      id: 'isometric',
      label: 'Isometric (~52 deg)',
      contractValue:
          'SpringArm 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLag 9.0',
      note: 'Best readability for arena movement + cursor plane aiming.',
    ),
    ConceptSectionOption(
      id: 'topdown',
      label: 'Fixed Top-Down (90 deg)',
      contractValue:
          'SpringArm 1650 cm @ -88 deg pitch, 50 deg FOV, Zero camera roll',
      note: 'Pure 2D tactical grid clarity with zero perspective skew.',
    ),
    ConceptSectionOption(
      id: 'tps',
      label: 'Third-Person Over-Shoulder',
      contractValue:
          'SpringArm 360 cm · SocketOffset (0, 65, 55) cm · 68 deg FOV · CameraLag 11.0',
      note: 'Close-quarters weight and horizon depth over multi-enemy flank readability.',
    ),
    ConceptSectionOption(
      id: 'fps',
      label: 'First-Person (90 deg FOV)',
      contractValue:
          'First-Person Camera · EyeHeight 64 cm · 90 deg FOV · 1:1 yaw/pitch',
      note: 'Immediate eye-level aim precision with narrow peripheral awareness.',
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
      brakingDecelCmPerSec: '2400',
    ),
    CoreFeelOption(
      id: 'heavy',
      label: 'Heavy Deliberate',
      tradeOff: TradeOffRule(
        prefer: 'Committed heavy windups',
        avoid: 'Zero-recovery animation cancel spam',
      ),
      brakingDecelCmPerSec: '1400',
    ),
    CoreFeelOption(
      id: 'physics',
      label: 'Physics Momentum',
      tradeOff: TradeOffRule(
        prefer: 'Velocity carry & drift banking',
        avoid: 'Stop-on-a-dime snapping',
      ),
      brakingDecelCmPerSec: '480',
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

  List<ConceptSectionOption> get effectiveCameraDecisionOptions => [
        ...cameraDecisionOptions,
        for (final def in defaultCameraDecisionOptions)
          if (!cameraDecisionOptions.any((o) => o.id == def.id)) def,
      ];

  bool get hasSpec =>
      pitch.trim().isNotEmpty &&
      coreLoop.isNotEmpty &&
      initialEpics.isNotEmpty;

  String get normalizedTitle =>
      gameTitle.trim().isEmpty ? 'UNTITLED PROJECT' : gameTitle.trim();

  ProjectConceptBlueprint deepCopy() {
    return ProjectConceptBlueprint(
      sparkPrompt: sparkPrompt,
      gameTitle: gameTitle,
      targetEngine: targetEngine,
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
      lastCoDesignNote: lastCoDesignNote,
      approved: approved,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sparkPrompt': sparkPrompt,
        'gameTitle': gameTitle,
        'targetEngine': targetEngine.id,
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
        'lastCoDesignNote': lastCoDesignNote,
        'approved': approved,
      };

  factory ProjectConceptBlueprint.fromJson(Map<String, dynamic> json) {
    // Support both Unreal Root Spec JSON and legacy Stage 1 blueprint JSON
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

    final legacyGameSpec = json['gameSpec'] is Map
        ? Map<String, dynamic>.from(json['gameSpec'] as Map)
        : const <String, dynamic>{};
    final legacyTechSpec = json['techSpec'] is Map
        ? Map<String, dynamic>.from(json['techSpec'] as Map)
        : const <String, dynamic>{};

    return ProjectConceptBlueprint(
      sparkPrompt: (json['sparkPrompt'] ?? json['prompt'] ?? '').toString(),
      gameTitle: (json['gameTitle'] ??
              json['title'] ??
              legacyGameSpec['title'] ??
              'UNTITLED UNREAL PROJECT')
          .toString()
          .trim(),
      targetEngine: UnrealTargetEngine.fromString(
        (json['targetEngine'] ?? legacyTechSpec['engine'] ?? 'ue5Mcp')
            .toString(),
      ),
      pitch: (json['pitch'] ?? json['goal'] ?? '').toString().trim(),
      coreLoop: loop,
      cameraChoiceId: (json['cameraChoiceId'] ?? 'isometric').toString().trim(),
      cameraContract: (json['cameraContract'] ??
              legacyGameSpec['camera'] ??
              'SpringArm 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLag 9.0')
          .toString()
          .trim(),
      characterScale: (json['characterScale'] ??
              'ACharacter CapsuleRadius 42 cm · HalfHeight 92 cm · MaxWalkSpeed 620 cm/s')
          .toString()
          .trim(),
      inputContract: (json['inputContract'] ??
              'Enhanced Input (IMC_Core + IA_Move / IA_Aim / IA_Primary / IA_Secondary)')
          .toString()
          .trim(),
      assetPolicy: (json['assetPolicy'] ??
              'Prototype Greybox Primitives (Engine/BasicShapes) + Debug Materials; UDataAsset for tuning')
          .toString()
          .trim(),
      cameraDecisionOptions: cameraOpts.isEmpty
          ? defaultCameraDecisionOptions
          : cameraOpts,
      feelChoiceId: normalizeFeelChoiceId(json['feelChoiceId']?.toString()),
      pillars: _stringList(json['pillars'] ?? json['designPillars']),
      tradeOffs: trades,
      outOfScope: _stringList(json['outOfScope']),
      initialEpics: epics,
      releaseDoneWhen: (json['releaseDoneWhen'] ??
              json['doneWhen'] ??
              'Start PIE in L_Arena_Proto -> complete full 30s core loop cleanly with 0 Output Log errors')
          .toString()
          .trim(),
      v02Presets: presets,
      v02NewPool: pool,
      v02UpgradesByLineageKey: upgradesMap,
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

/// Curated Unreal Engine starter packs matching `unreal_mcp_spec_studio_v3_mockup.html`.
class UnrealSparkPresetInfo {
  final String id;
  final String label;
  final String subtitle;
  final String sparkPrompt;

  const UnrealSparkPresetInfo({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.sparkPrompt,
  });
}

class UnrealSparkPresets {
  static const List<UnrealSparkPresetInfo> entries = [
    UnrealSparkPresetInfo(
      id: 'shellbreaker',
      label: 'Shellbreaker',
      subtitle: 'Top-down twin-stick crustacean mech arena shooter',
      sparkPrompt:
          'Top-down twin-stick crustacean mech arena shooter with claw dash armor breaks, heavy burst cannon recoil, and 3-wave combat.',
    ),
    UnrealSparkPresetInfo(
      id: 'railjack',
      label: 'Railjack Drift',
      subtitle: 'Third-person hover-skiff canyon racer with boost & gates',
      sparkPrompt:
          'Third-person hover-skiff canyon time-trial racer with apex drift banking, thruster heat gauges, and plasma gate boosts.',
    ),
    UnrealSparkPresetInfo(
      id: 'emberkeep',
      label: 'Ember Keep',
      subtitle: 'Isometric torchlight survival & melee barricade defense',
      sparkPrompt:
          'Isometric survival skirmisher where you chop shadow stalkers, place brazier light pylons, and hold safe ground as light radius shrinks.',
    ),
  ];

  static ProjectConceptBlueprint? matchSparkPrompt(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('shellbreaker') ||
        lower.contains('crustacean') ||
        lower.contains('crab')) {
      return byId('shellbreaker');
    }
    if (lower.contains('railjack') ||
        lower.contains('hover-skiff') ||
        lower.contains('canyon')) {
      return byId('railjack');
    }
    if (lower.contains('ember keep') ||
        lower.contains('brazier') ||
        lower.contains('shadow stalker')) {
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
      targetEngine: UnrealTargetEngine.ue5Mcp,
      pitch:
          'Crisp twin-stick mech brawler — smash armored crabs inside a compact greybox arena',
      coreLoop: const [
        'Skim & Cursor Aim',
        'Claw Dash Slam',
        'Burst Armor Crack',
        'Recover & Reposition',
      ],
      cameraChoiceId: 'isometric',
      cameraContract:
          'SpringArm 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLag 9.0 (Cursor Z-Plane aim)',
      characterScale:
          'BP_PlayerMech CapsuleRadius 42 cm · HalfHeight 92 cm · MaxWalkSpeed 640 cm/s',
      inputContract:
          'Enhanced Input (IMC_Combat + IA_Move, IA_AimCursor, IA_FireBurst, IA_ClawDash)',
      assetPolicy:
          'Greybox Primitives (Engine/BasicShapes) + Solid Tint Material Instances; DA_ShellbreakerTuning PrimaryDataAsset',
      feelChoiceId: 'snappy',
      cameraDecisionOptions: const [
        ConceptSectionOption(
          id: 'isometric',
          label: 'Isometric (~52 deg)',
          contractValue:
              'SpringArm 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLag 9.0 (Cursor Z-Plane aim)',
          note: 'Best clarity for circular dash telegraphs and twin-stick cursor aim.',
        ),
        ConceptSectionOption(
          id: 'topdown',
          label: 'Fixed Top-Down (90 deg)',
          contractValue:
              'SpringArm 1700 cm @ -88 deg pitch, 48 deg FOV, Fixed Arena Framing',
          note: 'Zero foreshortening along arena cover walls.',
        ),
        ConceptSectionOption(
          id: 'tps',
          label: 'Over-Shoulder (68 deg FOV)',
          contractValue:
              'SpringArm 380 cm · SocketOffset (0, 70, 60) cm · 68 deg FOV · CameraLag 10.0',
          note: 'Adds visceral impact scale at the cost of rear flank awareness.',
        ),
      ],
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
          avoid: 'Multi-room streaming levels',
        ),
        TradeOffRule(
          prefer: 'Clear emissive debug shapes',
          avoid: 'Premature skeletal rig detail',
        ),
      ],
      outOfScope: const [
        'No main menu, title screen, or save slots',
        'No inventory screen or multi-weapon loadout UI',
        'No co-op networking or replicated RPCs',
        'No procedural terrain or multi-zone progression',
      ],
      releaseDoneWhen:
          'Press PIE in L_Shellbreaker_Proto -> walk/dash/shoot dummy armor crab into kill state cleanly with 0 Output Log errors',
      initialEpics: [
        EpicSpec(
          id: 'sb_e01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Player Mech Movement & Claw Dash',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          coreLoopBeat: 'Beats 1–2 · Skim, Aim & Claw Dash',
          goal:
              'Move smoothly across the arena plane, rotate upper chassis toward mouse cursor, and execute an invulnerable forward claw dash.',
          links: const [
            'Reads DA_PlayerLocomotion DataAsset',
            'Exposes BPI_Damageable & I_DashImpact for E03 armor break',
            'Drives BP_PlayerMech SpringArm lag and dash burst VFX',
          ],
          outOfScope: const [
            'No slope stair-stepping mechanics',
            'No dash charge stacking',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_Move (Vector2D)',
              trigger: 'Triggered (Hold WASD)',
              rule: 'Ground velocity clamped cleanly at 640 cm/s; ignored during DashActive',
            ),
            EpicControlBinding(
              action: 'IA_AimCursor (Trace)',
              trigger: 'Tick Raycast',
              rule: 'Rotates upper turret mesh toward Z-plane cursor hit point every frame',
            ),
            EpicControlBinding(
              action: 'IA_ClawDash (Bool)',
              trigger: 'Started (Space / RMB)',
              rule: 'Locks facing, launches forward 550 cm in 0.16s on 1.1s cooldown',
            ),
          ],
          states: const [
            'Idle / Move -> DashWindup (0.04s) -> DashActive (0.16s) -> DashRecover (0.08s)',
          ],
          interrupts: const [
            'DashActive cancels weapon burst fire cleanly and toggles ECC_GameTraceChannel_Dash overlap',
            'Camera lag dips briefly on DashActive impact to amplify speed feel',
          ],
          tuning: [
            EpicTuningParam(key: 'MoveSpeed', value: '640', unit: 'cm/s'),
            EpicTuningParam(key: 'DashDistance', value: '550', unit: 'cm'),
            EpicTuningParam(key: 'DashDuration', value: '0.16', unit: 's'),
            EpicTuningParam(key: 'DashCooldown', value: '1.1', unit: 's'),
          ],
          feedback: const [
            'Orange emissive thruster trail ribbon during DashActive (0.16s)',
            'Compact radial cooldown ring around mech base in UMG HUD',
            'Camera shake pulse (Scale 0.45) on wall or enemy dash collision',
          ],
          levelStaging:
              'L_Shellbreaker_Proto: 3000x3000 cm walled greybox floor + 2 solid cover pillars + PlayerStart at origin',
          checks: [
            EpicPieCheck(
              id: 'sb_e01_c1',
              text: 'Press WASD -> mech accelerates smoothly to 640 cm/s with zero wall snagging',
            ),
            EpicPieCheck(
              id: 'sb_e01_c2',
              text: 'Move cursor across floor -> upper turret tracks aim vector immediately without gimbal flip',
            ),
            EpicPieCheck(
              id: 'sb_e01_c3',
              text: 'Press Space -> dash travels ~550 cm cleanly along aim direction and obeys 1.1s cooldown',
            ),
          ],
          baselineSummary: const [
            '8-way movement at 640 cm/s',
            'Cursor plane turret aim',
            '550 cm invulnerable Claw Dash',
          ],
        ),
        EpicSpec(
          id: 'sb_e02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Twin-Stick Burst Cannon & Recoil',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 3 · Burst Cannon Fire',
          goal:
              'Fire 3-round high-velocity kinetic bolts toward cursor aim with punchy muzzle recoil and heat cooldown.',
          links: const [
            'Attached to BP_PlayerMech turret muzzle socket',
            'Applies KineticImpact interface event to E03 Crab targets',
          ],
          outOfScope: const [
            'No alternate ammo pickups',
            'No manual reload button',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_FireBurst (Bool)',
              trigger: 'Pressed / Held (LMB)',
              rule: 'Spawns 3-bolt burst over 0.24s when Heat < 100 and not DashActive',
            ),
          ],
          states: const [
            'Ready -> BurstFiring (3 shots @ 0.08s interval) -> CycleCooldown (0.28s) -> Ready',
            'Heat >= 100 -> OverheatLock (1.3s vent) -> Ready',
          ],
          interrupts: const [
            'Triggering IA_ClawDash immediately aborts remaining burst bolts safely',
            'Passive heat decay pauses for 0.35s right after last shot fired',
          ],
          tuning: [
            EpicTuningParam(key: 'BoltSpeed', value: '2400', unit: 'cm/s'),
            EpicTuningParam(key: 'BurstDamage', value: '18', unit: 'hp'),
            EpicTuningParam(key: 'OverheatTime', value: '1.3', unit: 's'),
            EpicTuningParam(key: 'RecoilImpulse', value: '120', unit: 'cm/s'),
          ],
          feedback: const [
            'Bright yellow emissive projectile capsules with hit-spark Niagara/Debug burst on wall hit',
            'Turret barrel kicks back 18 cm per shot and interpolates cleanly forward',
            'Thin curved heat bar next to center cursor turns amber above 75%',
          ],
          levelStaging:
              'L_Shellbreaker_Proto: firing lane with static calibration cubes at 600 cm and 1400 cm distance',
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
          title: 'Crustacean Grunt & Armor Break',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beats 3–4 · Armor Crack & Reposition',
          goal:
              'Patrol and telegraph melee pincer lunges while requiring a Claw Dash hit to shatter front shell armor.',
          links: const [
            'Targets BP_PlayerMech via AI Perception / direct distance check',
            'Responds to BPI_Damageable & I_DashImpact from E01/E02',
          ],
          outOfScope: const [
            'No wave spawner director yet (placed directly in level)',
            'No ranged enemy variants',
          ],
          controls: [
            EpicControlBinding(
              action: 'AI MoveTo / Lunge',
              trigger: 'Loop (420 cm range)',
              rule: 'Faces player -> telegraphs 0.45s crimson flash -> lunges 420 cm',
            ),
          ],
          states: const [
            'ArmoredAdvance -> PincerWindup (0.45s) -> PincerLunge -> ExposedStagger (2.0s) -> Dead',
          ],
          interrupts: const [
            'E01 Claw Dash hit shatters ShellShield immediately and pushes enemy into ExposedStagger (2.0s)',
            'Bolt impacts on intact shell deal 25% chip damage and emit metallic deflect sparks',
          ],
          tuning: [
            EpicTuningParam(key: 'ShellHP', value: '60', unit: 'hp'),
            EpicTuningParam(key: 'CoreHP', value: '90', unit: 'hp'),
            EpicTuningParam(key: 'TelegraphDuration', value: '0.45', unit: 's'),
            EpicTuningParam(key: 'StaggerDuration', value: '2.0', unit: 's'),
          ],
          feedback: const [
            'Front dome shifts from slate-grey armored tint to glowing exposed magenta on Armor Break',
            'Compact floating world-space HP + Armor bar above enemy mesh',
            'Enemy flashes solid white for 0.08s on exposed core bolt impacts',
          ],
          levelStaging:
              'L_Shellbreaker_Proto: 2 static Armored Crab Grunt actors placed 1200 cm north of PlayerStart',
          checks: [
            EpicPieCheck(
              id: 'sb_e03_c1',
              text: 'Shoot frontal shell -> reduced chip damage with deflect flash until Claw Dash hits',
            ),
            EpicPieCheck(
              id: 'sb_e03_c2',
              text: 'Dash through crab -> front armor shatters into 2.0s ExposedStagger and bursts kill cleanly',
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
              'Tighten dash hit-stop, add burst finisher overdrive, and bring in 3-wave arena escalation.',
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
            text: '+55ms Hit-Stop freeze & radial shockwave ring on Dash impact',
            chosen: true,
          ),
          EpicUpgradeOption(
            id: 'up_e01_trail',
            text: '+Afterimage echo silhouette during DashActive',
          ),
        ],
        'e02': [
          EpicUpgradeOption(
            id: 'up_e02_crit',
            text: '+2x Weak-Point crit bolts vs staggered crabs (instant heat vent on kill)',
          ),
        ],
        'e03': [
          EpicUpgradeOption(
            id: 'up_e03_knockback',
            text: '+Wall-Slam knockback impulse & extra 25 hp stagger wall damage',
            chosen: true,
          ),
          EpicUpgradeOption(
            id: 'up_e03_deathshatter',
            text: '+Explosive shell shards on crab death pushing adjacent grunts',
          ),
        ],
      },
      v02NewPool: [
        EpicSpec(
          id: 'sb_e04',
          code: 'E04',
          lineageKey: 'e04',
          title: '3-Wave Arena Spawner & HUD Counter',
          releaseVersion: 'v0.2',
          lifecycle: EpicLifecycle.newEpic,
          chosenForNextRelease: true,
          goal:
              'Spawn escalating 3-wave crab squads from perimeter gates with live wave banner and quick restart flow.',
          links: const [
            'Spawns E03 BP_CrabGrunt actors at 4 perimeter SpawnGates',
            'Updates UMG_ArenaHUD Wave index + Remaining count',
          ],
          outOfScope: const [
            'No endless wave scaling past Wave 3',
            'No boss cutscenes',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_QuickRestart (Bool)',
              trigger: 'Pressed (R on Clear)',
              rule: 'Resets player HP/pos and restarts Wave 1 cleanly in < 0.2s',
            ),
          ],
          states: const [
            'WaveIntro (1.2s) -> WaveCombat -> WaveClear (2.0s breather) -> ArenaVictory',
          ],
          interrupts: const [
            'Player HP <= 0 transitions directly to ArenaDefeat overlay and stops active spawners',
          ],
          tuning: [
            EpicTuningParam(key: 'Wave1Count', value: '3', unit: 'count'),
            EpicTuningParam(key: 'Wave3Count', value: '7', unit: 'count'),
            EpicTuningParam(key: 'BreatherSeconds', value: '2.0', unit: 's'),
          ],
          feedback: const [
            'Perimeter floor pad pulses cyan 1.0s before spawning each grunt',
            'Top-center UMG Wave pill animates scale punch on wave transitions',
          ],
          levelStaging:
              'L_Shellbreaker_Proto: 4 SpawnGate target points placed along North/East/South/West walls',
          checks: [
            EpicPieCheck(
              id: 'sb_e04_c1',
              text: 'Kill all Wave 1 crabs -> 2.0s breather plays and Wave 2 spawns cleanly from lit gates',
            ),
            EpicPieCheck(
              id: 'sb_e04_c2',
              text: 'Press R after ArenaVictory -> resets arena immediately with 0 stale actors',
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
          goal:
              'Raise timed front energy buckler that staggers incoming crab lunges on tight guard timing.',
          links: const [
            'Coordinates with E01 IA_Secondary timing and E03 PincerLunge hit check',
          ],
          outOfScope: const [
            'No persistent hold block drain',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_ShellGuard (Bool)',
              trigger: 'Started (Shift / Q)',
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
            EpicTuningParam(key: 'ParryWindow', value: '0.25', unit: 's'),
            EpicTuningParam(key: 'ParryStagger', value: '2.2', unit: 's'),
          ],
          feedback: const [
            'Cyan arc shield mesh flashes front 120 deg cone during GuardWindow',
          ],
          levelStaging:
              'L_Shellbreaker_Proto: test directly against E03 Crab lunge telegraph',
          checks: [
            EpicPieCheck(
              id: 'sb_e05_c1',
              text: 'Press Q during crimson crab windup -> attacker stops and enters 2.2s stagger',
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
      targetEngine: UnrealTargetEngine.ue5Mcp,
      pitch:
          'High-speed canyon hover-skiff racer — carve long drift arcs through boost gates to beat par time',
      coreLoop: const [
        'Carve Canyon Line',
        'Hold Apex Drift',
        'Chain Boost Gate',
        'Vent Thruster Heat',
      ],
      cameraChoiceId: 'tps',
      cameraContract:
          'SpringArm 440 cm @ -12 deg pitch · Dynamic FOV 74->92 deg by speed · CameraLag 12.0',
      characterScale:
          'BP_HoverSkiff Hull 340x160 cm · HoverHeight 85 cm · TopSpeed 3800 cm/s',
      inputContract:
          'Enhanced Input (IMC_Race + IA_Throttle, IA_Steer, IA_Drift, IA_Boost)',
      assetPolicy:
          'Spline Greybox Canyon Floor + Emissive Gate Frames (Engine/BasicShapes); DA_SkiffPhysics PrimaryDataAsset',
      feelChoiceId: 'physics',
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
          'Complete 1 clean canyon lap in L_Canyon_Proto crossing Start/Finish gate with final timer HUD and 0 Output Log errors',
      initialEpics: [
        EpicSpec(
          id: 'rj_e01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Hover Skiff Suspension & Drift Carve',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          coreLoopBeat: 'Beats 1–2 · Carve Canyon Line & Hold Apex Drift',
          goal:
              'Maintain steady ground-hugging hover height over canyon slopes while carving responsive high-angle drifts.',
          links: const [
            'Reads DA_SkiffPhysics DataAsset',
            'Exposes SpeedRatio & IsDrifting to E02 Boost & E03 Gate HUD',
          ],
          outOfScope: const [
            'No upside-down loop-the-loop gravity shifts',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_Throttle (Axis1D)',
              trigger: 'Held (W / Trigger)',
              rule: 'Accelerates forward velocity smoothly up to BaseTopSpeed 3100 cm/s',
            ),
            EpicControlBinding(
              action: 'IA_Steer (Axis1D)',
              trigger: 'Held (A/D)',
              rule: 'Banks hull roll +/-26 deg smoothly while turning yaw rate',
            ),
            EpicControlBinding(
              action: 'IA_Drift (Bool)',
              trigger: 'Held (Space / LShift)',
              rule: 'Widens lateral slip angle, locks forward carry, and builds DriftCharge/s',
            ),
          ],
          states: const [
            'GripCruise -> ApexDrift (Charges Boost) -> CornerExitSnap -> GripCruise',
          ],
          interrupts: const [
            'Wall glance clamps normal impact speed to 78% and slides hull along tangent safely',
          ],
          tuning: [
            EpicTuningParam(key: 'HoverHeight', value: '85', unit: 'cm'),
            EpicTuningParam(key: 'BaseTopSpeed', value: '3100', unit: 'cm/s'),
            EpicTuningParam(key: 'MaxBankAngle', value: '26', unit: 'deg'),
            EpicTuningParam(key: 'DriftChargeRate', value: '35', unit: '%/s'),
          ],
          feedback: const [
            'Twin cyan thrusters lengthen with throttle and flare orange during ApexDrift',
            'Dynamic camera FOV expands smoothly from 74 to 92 deg with forward velocity',
          ],
          levelStaging:
              'L_Canyon_Proto: wide banked spline greybox track (~40s loop) with banked hairpin turn',
          checks: [
            EpicPieCheck(
              id: 'rj_e01_c1',
              text: 'Drive over sloped ramp -> hull holds steady ~85 cm clearance without nose-diving into floor',
            ),
            EpicPieCheck(
              id: 'rj_e01_c2',
              text: 'Hold Space + A/D in hairpin -> skiff enters clean drift slide and exits cleanly',
            ),
          ],
        ),
        EpicSpec(
          id: 'rj_e02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Boost Thruster & Plasma Heat Gauge',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 3 · Chain Boost & Thruster Surge',
          goal:
              'Spend accumulated boost meter for an immediate velocity surge without overheating past limit.',
          links: const [
            'Consumes DriftCharge from E01 and BoostPad pulses from E03',
          ],
          outOfScope: const [
            'No combat missiles or shield energy sharing',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_Boost (Bool)',
              trigger: 'Held (RMB / E)',
              rule: 'Pushes target speed to 4200 cm/s while draining BoostMeter',
            ),
          ],
          states: const [
            'Normal -> Boosting (Max 4200 cm/s) -> OverheatLockout (1.5s) -> Normal',
          ],
          interrupts: const [
            'Touching E03 Boost Gate grants instant +0.8s surge without raising Heat',
          ],
          tuning: [
            EpicTuningParam(key: 'BoostTopSpeed', value: '4200', unit: 'cm/s'),
            EpicTuningParam(key: 'BoostDrainRate', value: '28', unit: '%/s'),
            EpicTuningParam(key: 'OverheatCooldown', value: '1.5', unit: 's'),
          ],
          feedback: const [
            'Edge speed-lines post/UMG vignette + bright white exhaust core while Boosting',
            'Centered horizontal thruster gauge shows speed km/h & Boost %',
          ],
          levelStaging:
              'L_Canyon_Proto: straightaway run + speed readout debug overlay',
          checks: [
            EpicPieCheck(
              id: 'rj_e02_c1',
              text: 'Hold E with Boost available -> velocity jumps smoothly to 4200 cm/s with widened FOV',
            ),
          ],
        ),
        EpicSpec(
          id: 'rj_e03',
          code: 'E03',
          lineageKey: 'e03',
          title: 'Canyon Checkpoint Gates & Lap Timer',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beats 3–4 · Checkpoint Gates & Lap Closure',
          goal:
              'Track ordered spline gates, reward clean gate pass with speed pulse, and display final lap time.',
          links: const [
            'Reads overlap events from BP_HoverSkiff (E01)',
            'Triggers free surge impulse on E02 thruster component',
          ],
          outOfScope: const [
            'No persistent ghost replay serialization',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_ResetTrack (Bool)',
              trigger: 'Pressed (R)',
              rule: 'Snaps skiff cleanly to StartLine and resets LapTimer to 0.00s',
            ),
          ],
          states: const [
            'Countdown (0.8s) -> Racing (Gate 1..6) -> LapFinished (Display Final Time)',
          ],
          interrupts: const [
            'Skipping an ordered gate shows floating OFF-COURSE arrow toward missed gate',
          ],
          tuning: [
            EpicTuningParam(key: 'GateHalfWidth', value: '480', unit: 'cm'),
            EpicTuningParam(key: 'GateBoostDuration', value: '0.8', unit: 's'),
            EpicTuningParam(key: 'ParTimeSeconds', value: '42.0', unit: 's'),
          ],
          feedback: const [
            'Active next gate glows bright emerald; passed gates turn muted slate',
            'Top-right UMG timer displays mm:ss.ms + green/red delta vs ParTime',
          ],
          levelStaging:
              'L_Canyon_Proto: 6 sequential BP_BoostGate archways ending at Start/Finish gantry',
          checks: [
            EpicPieCheck(
              id: 'rj_e03_c1',
              text: 'Pass Gate 1..6 sequentially -> green next-gate highlights advance and Gate 6 posts Lap Time',
            ),
          ],
        ),
      ],
    );
  }

  static ProjectConceptBlueprint _emberKeep() {
    return ProjectConceptBlueprint(
      sparkPrompt: entries[2].sparkPrompt,
      gameTitle: 'EMBER KEEP',
      targetEngine: UnrealTargetEngine.ue5Mcp,
      pitch:
          'Tactical isometric torch defense — carve shadow stalkers away while guarding shrinking brazier light zones',
      coreLoop: const [
        'Swing Torch Axe',
        'Plant Brazier Light',
        'Hold Safe Radius',
        'Collect Ash Shards',
      ],
      cameraChoiceId: 'isometric',
      cameraContract:
          'SpringArm 1350 cm @ -50 deg pitch, 52 deg FOV, CameraLag 8.0 (Isometric cursor aim)',
      characterScale:
          'BP_Keeper CapsuleRadius 38 cm · HalfHeight 88 cm · WalkSpeed 540 cm/s',
      inputContract:
          'Enhanced Input (IMC_Keeper + IA_Move, IA_AxeSwing, IA_PlantBrazier)',
      assetPolicy:
          'Greybox Keep Courtyard + Warm PointLights (No baked lightmaps required); DA_KeeperTuning PrimaryDataAsset',
      feelChoiceId: 'heavy',
      pillars: const [
        'Light Defines Territory: Every dynamic light cone visibly alters enemy aggression and player safety',
        'Deliberate Heavy Swings: Axe cleaves carry distinct windup weight rather than rapid spam',
      ],
      tradeOffs: const [
        TradeOffRule(
          prefer: 'Dynamic moveable PointLights for instant PIE clarity',
          avoid: 'Long baked lighting builds',
        ),
        TradeOffRule(
          prefer: 'Compact 2400x2400 cm courtyard',
          avoid: 'Procedural forest chunks',
        ),
      ],
      outOfScope: const [
        'No hunger, thirst, or weather meters',
        'No inventory drag-and-drop grid',
        'No crafting bench menus',
      ],
      releaseDoneWhen:
          'Plant 1 brazier and fend off 3 shadow stalkers across 30s without brazier extinguishing or console errors',
      initialEpics: [
        EpicSpec(
          id: 'ek_e01',
          code: 'E01',
          lineageKey: 'e01',
          title: 'Keeper Movement & Heavy Axe Cleave',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          coreLoopBeat: 'Beat 1 · Swing Torch Axe',
          goal:
              'Move across the courtyard and unleash a directional 140 deg cleave arc knocking back shadow stalkers.',
          links: const [
            'Deals HitImpact & LightPulse to E03 Shadow Stalkers',
          ],
          outOfScope: const [
            'No multi-weapon swapping',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_Move (Vector2D)',
              trigger: 'Held WASD',
              rule: 'Moves keeper at 540 cm/s; slowed 50% during AxeWindup',
            ),
            EpicControlBinding(
              action: 'IA_AxeSwing (Bool)',
              trigger: 'Started (LMB)',
              rule: '0.18s windup -> 140 deg sweep hitbox out to 240 cm reach',
            ),
          ],
          states: const [
            'Idle / Move -> AxeWindup (0.18s) -> AxeStrike (0.12s) -> AxeRecover (0.20s)',
          ],
          interrupts: const [
            'Planting a Brazier (E02) takes priority over AxeRecover',
          ],
          tuning: [
            EpicTuningParam(key: 'WalkSpeed', value: '540', unit: 'cm/s'),
            EpicTuningParam(key: 'CleaveRadius', value: '240', unit: 'cm'),
            EpicTuningParam(key: 'CleaveDamage', value: '40', unit: 'hp'),
            EpicTuningParam(key: 'KnockbackImpulse', value: '480', unit: 'cm/s'),
          ],
          feedback: const [
            'Translucent amber 140 deg floor arc flashes briefly on AxeStrike',
            'Carried lantern flickers brighter during swing impact',
          ],
          levelStaging:
              'L_Keep_Proto: 2400x2400 cm stone courtyard with central main bonfire',
          checks: [
            EpicPieCheck(
              id: 'ek_e01_c1',
              text: 'Press LMB facing cursor -> axe cleave hits 240 cm cone and shoves dummy target back',
            ),
          ],
        ),
        EpicSpec(
          id: 'ek_e02',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Brazier Placement & Light Decay Radius',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beats 2–3 · Plant Brazier & Hold Safe Radius',
          goal:
              'Deploy temporary field braziers that project a shrinking safe light ring forcing enemies to recoil.',
          links: const [
            'Broadcasts LightRadius query to E03 Shadow Stalkers',
          ],
          outOfScope: const [
            'No defensive stone wall grid snapping',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_PlantBrazier (Bool)',
              trigger: 'Started (RMB / E)',
              rule: 'Spawns BP_FieldBrazier 140 cm ahead if AmberFuel >= 1',
            ),
          ],
          states: const [
            'Ignited (Full 480 cm radius) -> Flickering (< 160 cm) -> Extinguished',
          ],
          interrupts: const [
            'Hitting a planted brazier with AxeStrike stokes +4s lifetime cleanly',
          ],
          tuning: [
            EpicTuningParam(key: 'StartLightRadius', value: '480', unit: 'cm'),
            EpicTuningParam(key: 'BurnDuration', value: '18.0', unit: 's'),
            EpicTuningParam(key: 'MaxActiveBraziers', value: '3', unit: 'count'),
          ],
          feedback: const [
            'Crisp floor decal ring matches current safe PointLight attenuation radius',
          ],
          levelStaging:
              'L_Keep_Proto: verify dark perimeter edge around central stone circle',
          checks: [
            EpicPieCheck(
              id: 'ek_e02_c1',
              text: 'Press E -> brazier illuminates 480 cm circle and shrinks smoothly over 18s',
            ),
          ],
        ),
        EpicSpec(
          id: 'ek_e03',
          code: 'E03',
          lineageKey: 'e03',
          title: 'Shadow Stalker Patrol & Light Recoil',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beats 3–4 · Shadow Recoil & Ash Shards',
          goal:
              'Stalk the keeper from perimeter darkness and recoil dramatically whenever bright brazier light expands over them.',
          links: const [
            'Queries E02 active LightRadius spheres + E01 AxeStrike events',
          ],
          outOfScope: const [
            'No ranged shadow projectile casters',
          ],
          controls: [
            EpicControlBinding(
              action: 'AI Stalk / Flee',
              trigger: 'Tick AI',
              rule: 'Circles outside bright core -> dashes in when light dips -> flees on ignition',
            ),
          ],
          states: const [
            'ShadowProwl -> BiteLunge -> LightRecoil (1.2s) -> Dead (Drop 1 EmberFuel)',
          ],
          interrupts: const [
            'Fresh Brazier ignition inside 480 cm forces instant LightRecoil and cancels BiteLunge',
          ],
          tuning: [
            EpicTuningParam(key: 'StalkerHP', value: '80', unit: 'hp'),
            EpicTuningParam(key: 'ProwlSpeed', value: '430', unit: 'cm/s'),
            EpicTuningParam(key: 'RecoilSpeed', value: '680', unit: 'cm/s'),
          ],
          feedback: const [
            'Glowing violet eye slits dim whenever forced into LightRecoil',
          ],
          levelStaging:
              'L_Keep_Proto: 3 stalker spawns stationed around dark courtyard corners',
          checks: [
            EpicPieCheck(
              id: 'ek_e03_c1',
              text: 'Plant brazier near approaching stalker -> stalker screeches and flees outside lit ring',
            ),
          ],
        ),
      ],
    );
  }
}
