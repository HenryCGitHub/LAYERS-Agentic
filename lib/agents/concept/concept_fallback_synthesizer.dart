import '../../models/agent_blueprints.dart';
import '../../models/epic_spec.dart';
import '../../utils/unreal_spec_guard.dart';
import 'project_concept_epic_sync.dart';

String _ownerAsset(String stem, UnrealArchitectureMode mode) =>
    mode == UnrealArchitectureMode.cppHybrid
        ? 'Source/$stem.cpp'
        : '/Game/Blueprints/BP_$stem';

ProjectConceptBlueprint buildSynthesizedFallback(
  String sparkPrompt, {
  GodotProjectDimension dimension = GodotProjectDimension.dim3d,
  UnrealArchitectureMode? architectureMode,
  String? archetypeId,
  String? viewChoiceId,
  String? prototypeHookId,
}) {
  final cleaned = sparkPrompt.trim();
  final lower = cleaned.toLowerCase();
  final archMode =
      architectureMode ?? UnrealArchitectureMode.detectFromSpark(cleaned);
  final resolvedCamOptions = ProjectConceptBlueprint.defaultCamera3dOptions;

  String cameraChoice;
  if (viewChoiceId != null &&
      resolvedCamOptions.any((o) => o.id == viewChoiceId)) {
    cameraChoice = viewChoiceId;
  } else {
    final isFps = lower.contains('first-person') ||
        lower.contains('first person') ||
        lower.contains('fps');
    final isSide = !isFps &&
        (lower.contains('side-scroller') ||
            lower.contains('side scroller') ||
            lower.contains('platformer'));
    final isTps = !isFps &&
        !isSide &&
        (lower.contains('third-person') ||
            lower.contains('third person') ||
            lower.contains('over-shoulder') ||
            lower.contains('over shoulder') ||
            lower.contains('glider') ||
            lower.contains('grapple') ||
            lower.contains('racer') ||
            lower.contains('tps'));
    final isTopDown = !isFps &&
        !isSide &&
        !isTps &&
        (lower.contains('top-down') || lower.contains('top down'));
    cameraChoice = isFps
        ? 'fps'
        : (isSide
            ? 'sidescroller'
            : (isTps ? 'tps' : (isTopDown ? 'topdown' : 'isometric')));
  }

  final cameraContract = resolvedCamOptions
      .firstWhere(
        (o) => o.id == cameraChoice,
        orElse: () => resolvedCamOptions.first,
      )
      .contractValue;

  final effectiveArchetype = (archetypeId != null &&
          const {'combat', 'movement', 'racer', 'puzzle'}
              .contains(archetypeId))
      ? archetypeId
      : (RegExp(r'\b(?:race|racer|drift|track|lap|skiff|car|kart|boost)\b')
              .hasMatch(lower)
          ? 'racer'
          : (RegExp(
                      r'\b(?:puzzle|cozy|farm|farming|card|deck|sokoban|craft|relay|mirror|cooking)\b')
                  .hasMatch(lower)
              ? 'puzzle'
              : (RegExp(
                          r'\b(?:platformer|climb|grapple|parkour|hop|jump|course)\b')
                      .hasMatch(lower) &&
                  !lower.contains('shooter') &&
                  !lower.contains('brawler') &&
                  !lower.contains('crawler')
                  ? 'movement'
                  : 'combat')));

  final feelId = (lower.contains('heavy') ||
          lower.contains('deliberate') ||
          lower.contains('souls'))
      ? 'heavy'
      : (lower.contains('drift') ||
              lower.contains('hover') ||
              lower.contains('glider') ||
              lower.contains('physics') ||
              effectiveArchetype == 'racer')
          ? 'physics'
          : 'snappy';

  final titleWords = cleaned
      .replaceAll(RegExp(r'[^A-Za-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length >= 3)
      .take(2)
      .map((w) => w.toUpperCase())
      .toList();
  final title =
      titleWords.isEmpty ? 'PROTOTYPE ZERO' : titleWords.join(' ');
  final rawShortSpark = cleaned.isEmpty
      ? 'Focused Unreal Engine 5 vertical prototype testing core player movement and primary interaction'
      : cleaned;
  final shortSpark = UnrealSpecGuard.sanitizeLine(
    rawShortSpark,
    mode: archMode,
  );

  final List<String> loop;
  final List<EpicSpec> epics;
  final String testMapPath;
  final String inputSummary;

  if (effectiveArchetype == 'puzzle') {
    testMapPath = '/Game/Maps/Lvl_RoomProto.umap';
    inputSummary =
        'IMC_Puzzle (IA_Move, IA_Interact, IA_RotateOrUse, IA_ResetRoom)';
    loop = const [
      'Move & Inspect',
      'Manipulate Relay',
      'Trigger Signal Chain',
      'Open Gate & Reset',
    ];
    epics = [
      EpicSpec(
        id: 'ep_01',
        code: 'E01',
        lineageKey: 'e01',
        title: 'Player Movement & Camera',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.active,
        coreLoopBeat: 'Beat 1 · ${loop[0]}',
        goal:
            'Own ACharacter room movement, collision sliding, and locked USpringArmComponent framing.',
        inScope: const [
          'Smooth directional movement at 620 cm/s inside 2800x2800 cm puzzle room',
          'Clean corner sliding along greybox block obstacles',
        ],
        doneWhen: const [
          'Walk all 4 walls of 2800x2800 cm room -> Zero snagging with clear cursor highlight',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: testMapPath,
            role: '2800x2800 cm puzzle room + PlayerStart + ExitGate',
          ),
          EpicSceneOwnership(
            path: _ownerAsset('PuzzlePlayerPawn', archMode),
            role: 'ACharacter + USpringArmComponent + UCameraComponent + LineTrace focus probe',
          ),
        ],
        outOfScope: const ['No sprint stamina or combat dodge states'],
        states: const ['Idle <-> Walk -> Interacting'],
        interrupts: const ['Press R resets player back to PlayerStart cleanly'],
        features: [
          FeatureSpec(
            id: 'ep_01_f01',
            code: 'F01',
            title: 'Room Walk & Camera Tracking',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.active,
            goal: 'Move player cleanly at 620 cm/s with crisp USpringArmComponent framing.',
            controls: [
              EpicControlBinding(
                action: 'IA_Move',
                trigger: 'Triggered (WASD)',
                rule: 'Moves smoothly at 620 cm/s across puzzle room',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'MoveSpeed', value: '620', unit: 'cm/s'),
            ],
            cues: const ['Subtle footstep dust Niagara puff & focus reticle outline'],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f01_c1',
                text: 'Hold WASD -> Player glides smoothly inside room with zero corner snags',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_01_f02',
            code: 'F02',
            title: 'Target Probe & Focus Outline',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Highlight nearest interactable object within 220 cm.',
            controls: [
              EpicControlBinding(
                action: 'IA_Interact',
                trigger: 'Started (E / LMB)',
                rule: 'Selects highlighted puzzle node within 220 cm',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'InteractReach', value: '220', unit: 'cm'),
            ],
            cues: const ['Bright cyan material outline glow on active target object'],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f02_c1',
                text: 'Approach object -> Target highlights crisply at 220 cm',
              ),
            ],
          ),
        ],
      ),
      EpicSpec(
        id: 'ep_02',
        code: 'E02',
        lineageKey: 'e02',
        title: 'Interactive Objects & Relays',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.queued,
        coreLoopBeat: 'Beat 2 · ${loop[1]}',
        goal:
            'Own movable/rotatable puzzle objects and clean signal delegate emission to room gates.',
        inScope: const [
          'Push, pick, or rotate greybox relays snapping within 80 cm',
          'Broadcast OnStateChanged delegate to linked receptors',
        ],
        doneWhen: const [
          'Press E near relay -> State toggles visibly and linked signal beam updates immediately',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: _ownerAsset('PuzzleRelayObject', archMode),
            role: 'Interactive block / relay + UBoxComponent trigger',
          ),
        ],
        outOfScope: const ['No physics rope chains or inventory crafting tree'],
        states: const ['Resting -> Moved / Rotated -> LinkedActive'],
        interrupts: const ['Wall collision blocks push past room boundary cleanly'],
        features: [
          FeatureSpec(
            id: 'ep_02_f01',
            code: 'F03',
            title: 'Push, Place & Snap Relay',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Interact to move or rotate relay nodes with 80 cm snap alignment.',
            controls: [
              EpicControlBinding(
                action: 'IA_RotateOrUse',
                trigger: 'Started (R / RMB)',
                rule: 'Rotates or toggles held puzzle node state cleanly',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'SnapTolerance', value: '80', unit: 'cm'),
            ],
            cues: const ['Soft chime pitch increment on each snap step'],
            checks: [
              EpicPieCheck(
                id: 'ep_02_f01_c1',
                text: 'Press E/RMB on relay -> Object shifts cleanly and emits beam/color cue',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_02_f02',
            code: 'F04',
            title: 'Receptor Signal Beam Link',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Propagate active signal from aligned relays to the exit receptor.',
            tuning: [
              EpicTuningParam(key: 'SignalDelayS', value: '0.1', unit: 's'),
            ],
            cues: const ['Green Niagara beam lights up between relay and gate'],
            checks: [
              EpicPieCheck(
                id: 'ep_02_f02_c1',
                text: 'Align two relays -> Exit receptor turns green immediately',
              ),
            ],
          ),
        ],
      ),
      EpicSpec(
        id: 'ep_03',
        code: 'E03',
        lineageKey: 'e03',
        title: 'Puzzle Goal & Room Reset',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.queued,
        coreLoopBeat: 'Beat 4 · ${loop[3]}',
        goal:
            'Own room completion state detection, exit gate opening, WBP HUD status, and instant reset.',
        inScope: const [
          'Exit gate unlocks automatically when required relays stay active',
          'Instant room state reset on R without map reload flicker',
        ],
        doneWhen: const [
          'Solve room relays and enter ExitGate -> Victory banner shows and R resets room cleanly',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: _ownerAsset('RoomController', archMode),
            role: 'Signal aggregator + R reset snapshot',
          ),
        ],
        outOfScope: const ['No multi-level world map or save slots'],
        states: const ['Locked -> Solved -> Resetting'],
        interrupts: const ['Any relay deactivated re-locks ExitGate immediately'],
        features: [
          FeatureSpec(
            id: 'ep_03_f01',
            code: 'F05',
            title: 'Goal Gate Unlock & Banner',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Unlock ExitGate within 220 cm trigger zone when solved.',
            tuning: [
              EpicTuningParam(key: 'GoalGateRadius', value: '220', unit: 'cm'),
            ],
            cues: const ['Gate slides open with subtle green glow and solved WBP HUD banner'],
            checks: [
              EpicPieCheck(
                id: 'ep_03_f01_c1',
                text: 'Complete puzzle chain -> Gate opens and walking in shows Solved HUD',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_03_f02',
            code: 'F06',
            title: 'Instant Room State Reset',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Restore initial relay positions and PlayerStart in < 0.2 s on R.',
            controls: [
              EpicControlBinding(
                action: 'IA_ResetRoom',
                trigger: 'Started (R)',
                rule: 'Restores player and all puzzle objects cleanly',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'ResetFadeS', value: '0.15', unit: 's'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_03_f02_c1',
                text: 'Press R -> Room layout resets cleanly to starting configuration',
              ),
            ],
          ),
        ],
      ),
    ];
  } else if (effectiveArchetype == 'racer') {
    testMapPath = '/Game/Maps/Lvl_TrackProto.umap';
    inputSummary =
        'IMC_Racer (IA_Throttle, IA_Brake, IA_Steer, IA_DriftBoost, IA_ResetTrack)';
    loop = const [
      'Throttle & Steer',
      'Drift Through Apex',
      'Hit Boost Gate',
      'Clear Lap & Restart',
    ];
    epics = [
      EpicSpec(
        id: 'ep_01',
        code: 'E01',
        lineageKey: 'e01',
        title: 'Vehicle Handling & Camera',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.active,
        coreLoopBeat: 'Beat 1 · ${loop[0]}',
        goal:
            'Own responsive craft throttle, steering, drift slip banking, and follow USpringArmComponent rig.',
        inScope: const [
          'Forward acceleration up to 2400 cm/s with wall slide bounce',
          'Speed-reactive FOV pull on high velocity corners',
        ],
        doneWhen: const [
          'Hold W + A/D along track -> Craft holds corner line at 2400 cm/s cleanly',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: testMapPath,
            role: 'Looping greybox test circuit + guardrails + PlayerStart',
          ),
          EpicSceneOwnership(
            path: _ownerAsset('RacerPawn', archMode),
            role: 'APawn craft + USpringArmComponent follow camera',
          ),
        ],
        outOfScope: const ['No AI rubber-banding opponents or vehicle garage'],
        states: const ['Cruise -> DriftBank -> OverheatSlowdown -> Recover'],
        interrupts: const ['Guardrail bump dampens speed 25% without sticking'],
        features: [
          FeatureSpec(
            id: 'ep_01_f01',
            code: 'F01',
            title: 'Throttle, Steer & Chase Camera',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.active,
            goal: 'Drive craft smoothly up to 2400 cm/s with banked follow cam.',
            controls: [
              EpicControlBinding(
                action: 'IA_Throttle',
                trigger: 'Triggered (W / Up)',
                rule: 'Accelerates craft smoothly up to 2400 cm/s',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'TopSpeed', value: '2400', unit: 'cm/s'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f01_c1',
                text: 'Hold W + A/D -> Craft banks cleanly around corners',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_01_f02',
            code: 'F02',
            title: 'Drift Slip & Corner Hold',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Hold tight drift angle on Space with Niagara sparks trail feedback.',
            controls: [
              EpicControlBinding(
                action: 'IA_DriftBoost',
                trigger: 'Triggered / Completed (Space)',
                rule: 'Enters drift slide and triggers exit surge on straight',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'DriftGrip', value: '0.65', unit: 'x'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f02_c1',
                text: 'Hold Space in turn -> Rear slides smoothly with spark ribbon',
              ),
            ],
          ),
        ],
      ),
      EpicSpec(
        id: 'ep_02',
        code: 'E02',
        lineageKey: 'e02',
        title: 'Boost Pads & Thruster Heat',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.queued,
        coreLoopBeat: 'Beat 3 · ${loop[2]}',
        goal:
            'Own track boost gates, surge speed impulses, and thruster heat buildup.',
        inScope: const [
          '550 cm boost gates adding temporary speed surge',
          'UMG Widget speed + thruster heat gauge bar',
        ],
        doneWhen: const [
          'Pass through gate -> Craft surges briefly and WBP HUD heat bar updates smoothly',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: _ownerAsset('BoostGate', archMode),
            role: 'Track UBoxComponent trigger gate + glowing chevron mesh',
          ),
        ],
        outOfScope: const ['No item boxes or weapon pickups'],
        states: const ['Normal -> Boosting (0.9s) -> Cooling'],
        interrupts: const ['Exceeding 100% heat triggers 1.2 s forced vent slowdown'],
        features: [
          FeatureSpec(
            id: 'ep_02_f01',
            code: 'F03',
            title: 'Track Boost Gate Surge',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Pass 550 cm gate to gain +620 cm/s boost.',
            tuning: [
              EpicTuningParam(key: 'BoostBonusSpeed', value: '620', unit: 'cm/s'),
              EpicTuningParam(key: 'GateWidth', value: '550', unit: 'cm'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_02_f01_c1',
                text: 'Cross glowing gate -> Speed flashes upward cleanly for 0.9 s',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_02_f02',
            code: 'F04',
            title: 'Thruster Heat Gauge & Vent',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Track 0-100% heat meter on WBP HUD with red overheat warning.',
            tuning: [
              EpicTuningParam(key: 'OverheatVentS', value: '1.2', unit: 's'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_02_f02_c1',
                text: 'Chain boosts to max heat -> HUD warns red and craft vents briefly',
              ),
            ],
          ),
        ],
      ),
      EpicSpec(
        id: 'ep_03',
        code: 'E03',
        lineageKey: 'e03',
        title: 'Checkpoints & Lap Timer',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.queued,
        coreLoopBeat: 'Beat 4 · ${loop[3]}',
        goal:
            'Own sequential track checkpoints, live lap stopwatch UMG HUD, and R instant reset.',
        inScope: const [
          'Ordered checkpoint zones preventing reverse-lap skip',
          'Live lap time + best lap readout + R restart',
        ],
        doneWhen: const [
          'Finish 1 lap and press R -> Best lap records cleanly and craft resets to start line',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: '/Game/UI/WBP_LapTimer',
            role: 'Checkpoint sequence tracker & UMG HUD timer',
          ),
        ],
        outOfScope: const ['No online leaderboards or ghost replay saving'],
        states: const ['Countdown -> Racing -> LapFinish'],
        interrupts: const ['Press R resets lap clock and snaps craft to PlayerStart'],
        features: [
          FeatureSpec(
            id: 'ep_03_f01',
            code: 'F05',
            title: 'Checkpoint Split Gates',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Require passing 550 cm checkpoints before start gate counts.',
            tuning: [
              EpicTuningParam(key: 'CheckpointWidth', value: '550', unit: 'cm'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_03_f01_c1',
                text: 'Drive full circuit -> Split chime fires and lap counter increments cleanly',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_03_f02',
            code: 'F06',
            title: 'Lap Stopwatch & Track Reset',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Display millisecond lap timer and reset track cleanly on R.',
            controls: [
              EpicControlBinding(
                action: 'IA_ResetTrack',
                trigger: 'Started (R)',
                rule: 'Zeroes velocity and places craft at starting gate',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'ResetFadeS', value: '0.15', unit: 's'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_03_f02_c1',
                text: 'Press R mid-lap -> Craft snaps back to start gate with 00.00 timer',
              ),
            ],
          ),
        ],
      ),
    ];
  } else if (effectiveArchetype == 'movement') {
    testMapPath = '/Game/Maps/Lvl_CourseProto.umap';
    inputSummary =
        'IMC_Course (IA_Move, IA_Jump, IA_AirDash, IA_ResetCourse)';
    loop = const [
      'Run & Jump',
      'Chain Air Dash',
      'Clear Obstacle Gap',
      'Hit Finish & Reset',
    ];
    epics = [
      EpicSpec(
        id: 'ep_01',
        code: 'E01',
        lineageKey: 'e01',
        title: 'Player Movement & Camera',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.active,
        coreLoopBeat: 'Beat 1 · ${loop[0]}',
        goal:
            'Own responsive ACharacter run/jump physics with coyote time and smooth USpringArmComponent follow.',
        inScope: const [
          'Run speed 620 cm/s + crisp jump arc across obstacle platforms',
          '500 cm air dash burst resetting on landing',
        ],
        doneWhen: const [
          'Run and jump across greybox gaps -> Zero missed edges during coyote window',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: testMapPath,
            role: 'Obstacle course test map + PlayerStart + FinishGate',
          ),
          EpicSceneOwnership(
            path: _ownerAsset('RunnerCharacter', archMode),
            role: 'ACharacter + coyote jump buffer + USpringArmComponent follow rig',
          ),
        ],
        outOfScope: const ['No wall-climb stamina bars or weapon combat'],
        states: const ['Grounded -> Airborne -> AirDash -> LandRecover'],
        interrupts: const ['Touching ground resets AirDash charge immediately'],
        features: [
          FeatureSpec(
            id: 'ep_01_f01',
            code: 'F01',
            title: 'Run, Jump & Coyote Buffer',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.active,
            goal: 'Run at 620 cm/s with crisp 0.12 s coyote jump grace.',
            controls: [
              EpicControlBinding(
                action: 'IA_Jump',
                trigger: 'Started (Space)',
                rule: 'Jumps cleanly with coyote & pre-land input buffer',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'MoveSpeed', value: '620', unit: 'cm/s'),
              EpicTuningParam(key: 'CoyoteTimeS', value: '0.12', unit: 's'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f01_c1',
                text: 'Tap Space just past ledge -> Jump executes cleanly',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_01_f02',
            code: 'F02',
            title: 'Directional Air Dash Burst',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Burst 500 cm mid-air along input vector before falling.',
            controls: [
              EpicControlBinding(
                action: 'IA_AirDash',
                trigger: 'Started (Shift)',
                rule: 'Surges 500 cm mid-air once per airborne jump',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'DashDistance', value: '500', unit: 'cm'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f02_c1',
                text: 'Press Shift mid-jump -> Traverses 500 cm cleanly with trail',
              ),
            ],
          ),
        ],
      ),
      EpicSpec(
        id: 'ep_02',
        code: 'E02',
        lineageKey: 'e02',
        title: 'Course Obstacles & Checkpoints',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.queued,
        coreLoopBeat: 'Beat 3 · ${loop[2]}',
        goal:
            'Own greybox moving platforms, fall reset volume, and course checkpoints.',
        inScope: const [
          'Checkpoints within 220 cm capture safe respawn coordinates',
          'Out-of-bounds trigger teleports cleanly to active checkpoint',
        ],
        doneWhen: const [
          'Touch checkpoint then miss jump -> Player respawns at checkpoint in < 0.2 s',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: _ownerAsset('CheckpointPad', archMode),
            role: 'Checkpoint pad + UBoxComponent flag trigger & fall reset',
          ),
        ],
        outOfScope: const ['No branching skill upgrades or collectible shop'],
        states: const ['ActiveRun -> Fell -> CheckpointRespawn'],
        interrupts: const ['Respawn clears downward velocity before placing player'],
        features: [
          FeatureSpec(
            id: 'ep_02_f01',
            code: 'F03',
            title: 'Checkpoint Pads & Safe Respawn',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Capture spawn point within 220 cm pad radius on overlap.',
            tuning: [
              EpicTuningParam(key: 'CheckpointRadius', value: '220', unit: 'cm'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_02_f01_c1',
                text: 'Step on pad and fall off -> Player restores at pad cleanly',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_02_f02',
            code: 'F04',
            title: 'Launch Pad & Moving Platform',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Boost upward jump velocity cleanly when crossing launch pad actors.',
            tuning: [
              EpicTuningParam(key: 'SpringBoostMult', value: '1.6', unit: 'x'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_02_f02_c1',
                text: 'Land on spring pad -> Player launches cleanly onto high ledge',
              ),
            ],
          ),
        ],
      ),
      EpicSpec(
        id: 'ep_03',
        code: 'E03',
        lineageKey: 'e03',
        title: 'Course Finish & Run Timer',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.queued,
        coreLoopBeat: 'Beat 4 · ${loop[3]}',
        goal:
            'Own speedrun stopwatch UMG HUD, finish banner detection, and R instant course restart.',
        inScope: const [
          'WBP stopwatch timer stopping on FinishGate overlap',
          'Instant R full-course restart',
        ],
        doneWhen: const [
          'Reach FinishGate -> Timer freezes cleanly and R restarts run from PlayerStart',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: '/Game/UI/WBP_CourseTimer',
            role: 'Run timer & FinishGate UMG Widget banner',
          ),
        ],
        outOfScope: const ['No ghost race replays or unlock menus'],
        states: const ['Running -> Finished'],
        interrupts: const ['Press R resets timer to 00.00 and clears active checkpoint'],
        features: [
          FeatureSpec(
            id: 'ep_03_f01',
            code: 'F05',
            title: 'Finish Gate & Run Timer HUD',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Stop stopwatch and display clear time when crossing 550 cm finish gate.',
            tuning: [
              EpicTuningParam(key: 'FinishGateWidth', value: '550', unit: 'cm'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_03_f01_c1',
                text: 'Cross final gate -> Timer freezes cleanly with clear banner',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_03_f02',
            code: 'F06',
            title: 'Instant Course Quick Restart',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Reset player to PlayerStart and zero timer in < 0.2 s on R.',
            controls: [
              EpicControlBinding(
                action: 'IA_ResetCourse',
                trigger: 'Started (R)',
                rule: 'Restarts course run immediately',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'ResetFadeS', value: '0.15', unit: 's'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_03_f02_c1',
                text: 'Press R -> Course & timer reset cleanly back to start',
              ),
            ],
          ),
        ],
      ),
    ];
  } else {
    final hasDeployVerb = lower.contains('deploy') ||
        lower.contains('pad') ||
        lower.contains('turret') ||
        lower.contains('build') ||
        lower.contains('beacon');
    testMapPath = '/Game/Maps/Lvl_ArenaProto.umap';
    inputSummary =
        'IMC_Combat (IA_Move, IA_Dodge, IA_PrimaryAction, IA_ResetProto)';
    loop = <String>[
      'Move & Orient',
      'Trigger Primary Action',
      if (hasDeployVerb) 'Deploy Field Utility',
      'React & Complete Run',
    ];
    epics = <EpicSpec>[
      EpicSpec(
        id: 'ep_01',
        code: 'E01',
        lineageKey: 'e01',
        title: 'Player Movement & Camera',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.active,
        coreLoopBeat: 'Beat 1 · ${loop[0]}',
        goal:
            'Own ACharacter locomotion, dash evasion impulse, and locked USpringArmComponent framing.',
        inScope: const [
          'WASD movement at 620 cm/s inside 2800x2800 cm playtest room',
          'Forward 500 cm dodge dash on 1.0 s cooldown',
        ],
        doneWhen: const [
          'Move and dodge cleanly inside 2800x2800 cm -> Zero snagging against walls',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: testMapPath,
            role: '2800x2800 cm greybox test room + PlayerStart',
          ),
          EpicSceneOwnership(
            path: _ownerAsset('PlayerCharacter', archMode),
            role: 'ACharacter + USpringArmComponent follow rig',
          ),
        ],
        outOfScope: const [
          'No climbing, swimming, or crouch stances',
        ],
        states: const [
          'Idle / Move -> DodgeImpulse (0.16s) -> Recover -> Idle / Move',
        ],
        interrupts: const [
          'DodgeImpulse grants temporary collision channel bypass on enemy actors',
        ],
        features: [
          FeatureSpec(
            id: 'ep_01_f01',
            code: 'F01',
            title: 'Planar Walk & Camera Tracking',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.active,
            goal: 'Control player movement at 620 cm/s with smooth USpringArmComponent follow.',
            controls: [
              EpicControlBinding(
                action: 'IA_Move',
                trigger: 'Triggered (WASD)',
                rule: 'Moves smoothly at 620 cm/s across floor',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'MoveSpeed', value: '620', unit: 'cm/s'),
            ],
            cues: const ['Subtle movement lean matching travel vector'],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f01_c1',
                text: 'Hold WASD -> Player moves at 620 cm/s cleanly',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_01_f02',
            code: 'F02',
            title: 'Impulse Dodge Dash',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Execute 500 cm forward dodge impulse on 1.0 s cooldown.',
            controls: [
              EpicControlBinding(
                action: 'IA_Dodge',
                trigger: 'Started (Space)',
                rule: 'Dashes 500 cm forward over 0.16 s',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'DodgeDistance', value: '500', unit: 'cm'),
              EpicTuningParam(key: 'DodgeCooldown', value: '1.0', unit: 's'),
            ],
            cues: const ['Bright cyan Niagara trail ribbon during DodgeImpulse'],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f02_c1',
                text: 'Press Space -> Travels 500 cm cleanly with cooldown ring',
              ),
            ],
          ),
        ],
      ),
      EpicSpec(
        id: 'ep_02',
        code: 'E02',
        lineageKey: 'e02',
        title: 'Primary Combat & Action',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.queued,
        coreLoopBeat: 'Beat 2 · ${loop[1]}',
        goal:
            'Own primary offensive actions along aim direction, impact damage, and cooldown cadence.',
        inScope: const [
          '1600 cm aimed strike with 25 hp base hit damage',
          'Brief screen impulse and impact flash on hit',
        ],
        doneWhen: const [
          'Click LMB toward target -> Hit registers out to 1600 cm cleanly',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: _ownerAsset('PrimaryCombatComponent', archMode),
            role: 'LineTrace / projectile spawn & 0.25 s cooldown lock',
          ),
        ],
        outOfScope: const [
          'No secondary skill tree or combo upgrades',
        ],
        states: const [
          'Ready -> ActiveAction (0.18s) -> Cooldown (0.25s) -> Ready',
        ],
        interrupts: const [
          'E01 DodgeImpulse cleanly cancels cooldown wind-down',
        ],
        features: [
          FeatureSpec(
            id: 'ep_02_f01',
            code: 'F03',
            title: 'Aimed Primary Strike',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Execute 1600 cm strike toward aim vector dealing 25 hp.',
            controls: [
              EpicControlBinding(
                action: 'IA_PrimaryAction',
                trigger: 'Started (LMB)',
                rule: 'Fires active projectile or melee trace out to 1600 cm',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'ActionRange', value: '1600', unit: 'cm'),
              EpicTuningParam(key: 'ActionDamage', value: '25', unit: 'hp'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_02_f01_c1',
                text: 'Click LMB -> Strikes cleanly out to 1600 cm',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_02_f02',
            code: 'F04',
            title: 'Action Cooldown & Hit Flash',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Enforce 0.25 s strike cadence and emit white impact flash plus camera pulse.',
            tuning: [
              EpicTuningParam(key: 'ActionCooldown', value: '0.25', unit: 's'),
            ],
            cues: const ['Emissive impact flash on hit + micro camera shake'],
            checks: [
              EpicPieCheck(
                id: 'ep_02_f02_c1',
                text: 'Spam LMB -> Respects 0.25 s fire rate with surface flash on hit',
              ),
            ],
          ),
        ],
      ),
      if (hasDeployVerb)
        EpicSpec(
          id: 'ep_03_util',
          code: 'E03',
          lineageKey: 'e03_util',
          title: 'Field Utility & Actors',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 3 · ${loop[2]}',
          goal:
              'Own deployable utility actors placed ahead of the player to shape arena space.',
          inScope: const [
            'Spawn utility 200 cm ahead on 3.0 s cooldown',
            'Cap max 2 concurrent deployed instances cleanly',
          ],
          doneWhen: const [
            'Press E -> Utility actor deploys 200 cm ahead and activates on overlap',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: _ownerAsset('FieldUtility', archMode),
              role: 'Deployed utility AActor + UBoxComponent trigger',
            ),
          ],
          outOfScope: const [
            'No multi-tier building upgrade grid',
          ],
          states: const [
            'Ready -> DeployActive (200 cm offset) -> Cooldown (3.0s)',
          ],
          interrupts: const [
            'Max 2 active utility instances destroy oldest actor automatically',
          ],
          features: [
            FeatureSpec(
              id: 'ep_03_util_f01',
              code: 'F05',
              title: 'Forward Utility Deploy',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Place utility 200 cm ahead on E with cyan ring decal.',
              controls: [
                EpicControlBinding(
                  action: 'IA_SecondaryAction',
                  trigger: 'Started (E / RMB)',
                  rule: 'Deploys utility actor 200 cm ahead on a 3.0 s cooldown',
                ),
              ],
              tuning: [
                EpicTuningParam(key: 'DeployDistance', value: '200', unit: 'cm'),
                EpicTuningParam(key: 'DeployCooldown', value: '3.0', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_03_util_f01_c1',
                  text: 'Press E -> Utility appears 200 cm ahead',
                ),
              ],
            ),
            FeatureSpec(
              id: 'ep_03_util_f02',
              code: 'F06',
              title: 'Instance Cap Recycling',
              introducedIn: 'v0.1',
              sliceTime: '30 min',
              status: FeatureStatus.queued,
              goal: 'Keep at most 2 active utilities by destroying oldest actor on third deploy.',
              tuning: [
                EpicTuningParam(key: 'MaxDeployed', value: '2', unit: 'count'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_03_util_f02_c1',
                  text: 'Deploy third utility -> Oldest actor despawns cleanly',
                ),
              ],
            ),
          ],
        ),
      EpicSpec(
        id: 'ep_loop_close',
        code: hasDeployVerb ? 'E04' : 'E03',
        lineageKey: hasDeployVerb ? 'e04' : 'e03',
        title: 'Enemy Encounters & Loop Reset',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.queued,
        coreLoopBeat: 'Beat ${loop.length} · ${loop.last}',
        goal:
            'Own interactive target enemies, readable threat telegraphs, HP tracking, and arena quick reset.',
        inScope: const [
          '100 hp target entities stationed 1200 cm from PlayerStart',
          '0.50 s telegraph warning before strike + R arena reset',
        ],
        doneWhen: const [
          'Defeat targets and press R -> HUD updates cleanly and arena resets in < 0.2 s',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: _ownerAsset('TargetEnemy', archMode),
            role: 'Target ACharacter + UWidgetComponent HP bar + telegraph cue',
          ),
        ],
        outOfScope: const [
          'No procedural dungeon rooms or loot chests',
        ],
        states: const [
          'Patrol -> Telegraph (0.50s) -> Execute -> Stagger / Defeated',
        ],
        interrupts: const [
          'Heavy hit triggers 0.40 s brief knockback stagger without freezing player movement',
        ],
        features: [
          FeatureSpec(
            id: 'ep_loop_f01',
            code: 'F05',
            title: 'Telegraphed Target AI & HP',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Broadcast 0.50 s crimson telegraph before strike and track 100 hp.',
            tuning: [
              EpicTuningParam(key: 'TargetHp', value: '100', unit: 'hp'),
              EpicTuningParam(key: 'AggroRange', value: '1200', unit: 'cm'),
              EpicTuningParam(key: 'TelegraphDuration', value: '0.50', unit: 's'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_loop_f01_c1',
                text: 'Approach target -> 0.50 s telegraph warns before attack',
              ),
            ],
          ),
          FeatureSpec(
            id: 'ep_loop_f02',
            code: 'F06',
            title: 'Arena Defeat & Quick Reset',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Update remaining target counter on defeat and reset arena in < 0.2 s on R.',
            controls: [
              EpicControlBinding(
                action: 'IA_ResetProto',
                trigger: 'Started (R)',
                rule: 'Respawns targets and resets player HP to 100 in < 0.2 s',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'ResetFadeS', value: '0.15', unit: 's'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_loop_f02_c1',
                text: 'Press R after clearing room -> Arena & HP reset cleanly',
              ),
            ],
          ),
        ],
      ),
    ];
  }

  final bp = ProjectConceptBlueprint(
    sparkPrompt: cleaned,
    gameTitle: title,
    dimension: dimension,
    architectureMode: archMode,
    pitch: '$title — $shortSpark',
    coreLoop: loop,
    cameraChoiceId: cameraChoice,
    cameraContract: cameraContract,
    inputContract: inputSummary,
    assetPolicy: archMode.architectureContract,
    feelChoiceId: feelId,
    pillars: const [
      'Instant Frame-1 Control: Player movement and actions respond immediately without sluggish inertia',
      'Clear Spatial Silhouettes: Distinct bright/dark debug shapes communicate state changes before impact',
    ],
    tradeOffs: const [
      TradeOffRule(
        prefer: 'Tight single-map greybox playtest room',
        avoid: 'Multi-level streaming worlds',
      ),
      TradeOffRule(
        prefer: 'Readable debug geometry & UMG Widget HUD',
        avoid: 'Premature final art pipelines',
      ),
    ],
    outOfScope: const [
      'No main menu, settings modal, or save slots',
      'No multiplayer networking or lobby flows',
      'No inventory UI or equipment loadouts',
    ],
    releaseDoneWhen:
        'Run PIE on $testMapPath -> complete full 30s core loop cleanly with 0 Message Log errors',
    initialEpics: epics,
  );
  normalizeSequentialEpicAndFeatureCodesImpl(bp);
  syncEpicCameraFramingImpl(
    bp,
    optionId: cameraChoice,
    contractValue: cameraContract,
  );
  syncEpicCoreFeelImpl(bp, feelId: feelId);
  return UnrealSpecGuard.sanitizeConceptBlueprint(
    raw: bp,
    modeOverride: archMode,
  );
}
