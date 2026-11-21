part of 'project_concept_agent.dart';

ProjectConceptBlueprint _buildSynthesizedFallback(
  String sparkPrompt, {
  required GodotProjectDimension dimension,
  String? archetypeId,
  String? viewChoiceId,
  String? prototypeHookId,
}) {
  final cleaned = sparkPrompt.trim();
  final lower = cleaned.toLowerCase();
  final is2d = dimension == GodotProjectDimension.dim2d;

  final resolvedCamOptions = is2d
      ? ProjectConceptBlueprint.defaultCamera2dOptions
      : ProjectConceptBlueprint.defaultCamera3dOptions;

  String cameraChoice;
  if (viewChoiceId != null &&
      resolvedCamOptions.any((o) => o.id == viewChoiceId)) {
    cameraChoice = viewChoiceId;
  } else if (is2d) {
    final isSideScroller = lower.contains('side-scroller') ||
        lower.contains('side scroller') ||
        lower.contains('platformer') ||
        lower.contains('metroidvania');
    final isFixedRoom = lower.contains('puzzle') ||
        lower.contains('sokoban') ||
        lower.contains('room');
    cameraChoice = isSideScroller
        ? 'sidescroller2d'
        : (isFixedRoom ? 'fixedarena2d' : 'topdown2d');
  } else {
    final isFps = lower.contains('first-person') ||
        lower.contains('first person') ||
        lower.contains('fps');
    final isTps = !isFps &&
        (lower.contains('third-person') ||
            lower.contains('third person') ||
            lower.contains('over-shoulder') ||
            lower.contains('over shoulder') ||
            lower.contains('glider') ||
            lower.contains('wingsuit') ||
            lower.contains('grapple') ||
            lower.contains('grappling') ||
            lower.contains('racer') ||
            lower.contains('tps'));
    final isTopDown3d = !isFps &&
        !isTps &&
        (lower.contains('top-down') || lower.contains('top down'));
    cameraChoice = isFps
        ? 'fps'
        : (isTps ? 'tps' : (isTopDown3d ? 'topdown' : 'isometric'));
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
  final shortSpark = cleaned.isEmpty
      ? 'Focused Godot 4 vertical prototype testing core player movement and primary interaction'
      : cleaned;

  final distUnit = dimension.distanceUnit;
  final speedUnit = dimension.speedUnit;
  final moveVal = is2d ? '260' : '6.2';
  final dodgeDist = is2d ? '180' : '5.0';
  final actionRange = is2d ? '420' : '16.0';
  final deployDist = is2d ? '72' : '2.0';
  final arenaExtent = is2d ? '1280x720 px' : '28x28 m';
  final targetDist = is2d ? '320 px' : '12 m';
  final reachVal = is2d ? '64' : '2.2';
  final snapVal = is2d ? '24' : '0.8';
  final topSpeedVal = is2d ? '520' : '24.0';
  final gateWidthVal = is2d ? '140' : '5.5';
  final bodyCls = is2d ? 'CharacterBody2D' : 'CharacterBody3D';
  final camNote = is2d ? 'Camera2D' : 'SpringArm3D';

  final List<String> loop;
  final List<EpicSpec> epics;
  String testScenePath;
  String inputSummary;

  if (effectiveArchetype == 'puzzle') {
    testScenePath = 'res://scenes/room_proto.tscn';
    inputSummary =
        'InputMap (move_left/right/up/down, interact, rotate_or_use, reset_room)';
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
            'Own player $bodyCls room movement, collision sliding, and locked $camNote framing.',
        inScope: [
          'Smooth directional movement at $moveVal $speedUnit inside $arenaExtent puzzle room',
          'Clean corner sliding along greybox block obstacles',
        ],
        doneWhen: [
          'Walk all 4 walls of $arenaExtent -> Zero snagging with clear cursor highlight',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scenes/room_proto.tscn',
            role: '$arenaExtent puzzle room + SpawnPoint + ExitGate',
          ),
          EpicSceneOwnership(
            path: 'res://scenes/player.tscn',
            role: '$bodyCls + $camNote + InteractionRay',
          ),
          EpicSceneOwnership(
            path: 'res://scripts/player.gd',
            role: 'Grid/free locomotion & focus probe',
          ),
        ],
        outOfScope: const ['No sprint stamina or combat dodge states'],
        states: const ['Idle <-> Walk -> Interacting'],
        interrupts: const ['Press R resets player back to SpawnPoint cleanly'],
        features: [
          FeatureSpec(
            id: 'ep_01_f01',
            code: 'F01',
            title: 'Room Walk & Camera Tracking',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.active,
            goal: 'Move player cleanly at $moveVal $speedUnit with crisp $camNote framing.',
            controls: [
              EpicControlBinding(
                action: 'move_8way',
                trigger: 'Held (WASD)',
                rule: 'Moves smoothly at $moveVal $speedUnit across puzzle room',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'move_speed', value: moveVal, unit: speedUnit),
            ],
            cues: const ['Subtle footstep dust & focus reticle outline'],
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
            goal: 'Highlight nearest interactable object within $reachVal $distUnit.',
            controls: [
              EpicControlBinding(
                action: 'interact',
                trigger: 'Just Pressed (E / LMB)',
                rule: 'Selects highlighted puzzle node within $reachVal $distUnit',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'interact_reach', value: reachVal, unit: distUnit),
            ],
            cues: const ['Bright cyan outline glow on active target object'],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f02_c1',
                text: 'Approach object -> Target highlights crisply at $reachVal $distUnit',
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
            'Own movable/rotatable puzzle objects and clean signal state emission to room gates.',
        inScope: [
          'Push, pick, or rotate greybox relays snapping within $snapVal $distUnit',
          'Emit state_changed signal to linked receptors',
        ],
        doneWhen: [
          'Press E near relay -> State toggles visibly and linked signal beam updates immediately',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scenes/puzzle_object.tscn',
            role: 'Interactive block / relay + trigger collider',
          ),
          EpicSceneOwnership(
            path: 'res://scripts/puzzle_object.gd',
            role: 'Snap placement & active state signal',
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
            goal: 'Interact to move or rotate relay nodes with $snapVal $distUnit snap alignment.',
            controls: [
              EpicControlBinding(
                action: 'rotate_or_use',
                trigger: 'Just Pressed (R / RMB)',
                rule: 'Rotates or toggles held puzzle node state cleanly',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'snap_tolerance', value: snapVal, unit: distUnit),
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
              EpicTuningParam(key: 'signal_delay_s', value: '0.1', unit: 's'),
            ],
            cues: const ['Green signal line lights up between relay and gate'],
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
            'Own room completion state detection, exit gate opening, HUD status, and instant reset.',
        inScope: [
          'Exit gate unlocks automatically when required relays stay active',
          'Instant room state reset on R without scene reload flicker',
        ],
        doneWhen: [
          'Solve room relays and enter ExitGate -> Victory banner shows and R resets room cleanly',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scripts/room_controller.gd',
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
            goal: 'Unlock ExitGate within $reachVal $distUnit trigger zone when solved.',
            tuning: [
              EpicTuningParam(key: 'goal_gate_radius', value: reachVal, unit: distUnit),
            ],
            cues: const ['Gate slides open with subtle green glow and solved banner'],
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
            goal: 'Restore initial relay positions and SpawnPoint in < 0.2 s on R.',
            controls: [
              EpicControlBinding(
                action: 'reset_room',
                trigger: 'Just Pressed (R)',
                rule: 'Restores player and all puzzle objects cleanly',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'reset_fade_s', value: '0.15', unit: 's'),
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
    testScenePath = 'res://scenes/track_proto.tscn';
    inputSummary =
        'InputMap (throttle, brake, steer_left/steer_right, drift_boost, reset_track)';
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
            'Own responsive craft throttle, steering, drift slip banking, and follow $camNote rig.',
        inScope: [
          'Forward acceleration up to $topSpeedVal $speedUnit with wall slide bounce',
          'Speed-reactive FOV/zoom pull on high velocity corners',
        ],
        doneWhen: [
          'Hold W + A/D along track -> Craft holds corner line at $topSpeedVal $speedUnit cleanly',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scenes/track_proto.tscn',
            role: 'Looping greybox test circuit + guardrails + SpawnPoint',
          ),
          EpicSceneOwnership(
            path: 'res://scenes/racer.tscn',
            role: '$bodyCls craft + $camNote follow camera',
          ),
          EpicSceneOwnership(
            path: 'res://scripts/racer.gd',
            role: 'Acceleration, steer banking & drift state machine',
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
            goal: 'Drive craft smoothly up to $topSpeedVal $speedUnit with banked follow cam.',
            controls: [
              EpicControlBinding(
                action: 'throttle',
                trigger: 'Held (W / Up)',
                rule: 'Accelerates craft smoothly up to $topSpeedVal $speedUnit',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'top_speed', value: topSpeedVal, unit: speedUnit),
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
            goal: 'Hold tight drift angle on Space with sparks trail feedback.',
            controls: [
              EpicControlBinding(
                action: 'drift_boost',
                trigger: 'Held / Released (Space)',
                rule: 'Enters drift slide and triggers exit surge on straight',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'drift_grip', value: '0.65', unit: 'x'),
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
        inScope: [
          '$gateWidthVal $distUnit boost gates adding temporary speed surge',
          'HUD speed + thruster heat gauge bar',
        ],
        doneWhen: [
          'Pass through gate -> Craft surges briefly and HUD heat bar updates smoothly',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scenes/boost_pad.tscn',
            role: 'Track trigger gate + glowing chevron mesh',
          ),
          EpicSceneOwnership(
            path: 'res://scripts/boost_pad.gd',
            role: 'Area overlap boost impulse & cooldown lock',
          ),
        ],
        outOfScope: const ['No item boxes or weapon pickups'],
        states: const ['Normal -> Boosting (0.9s) -> Cooling'],
        interrupts: const ['Exceeding 100% heat triggers 1.2s forced vent slowdown'],
        features: [
          FeatureSpec(
            id: 'ep_02_f01',
            code: 'F03',
            title: 'Track Boost Gate Surge',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Pass $gateWidthVal $distUnit gate to gain +$moveVal $speedUnit boost.',
            tuning: [
              EpicTuningParam(key: 'boost_bonus_speed', value: moveVal, unit: speedUnit),
              EpicTuningParam(key: 'gate_width', value: gateWidthVal, unit: distUnit),
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
            goal: 'Track 0-100% heat meter on CanvasLayer HUD with red overheat warning.',
            tuning: [
              EpicTuningParam(key: 'overheat_vent_s', value: '1.2', unit: 's'),
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
            'Own sequential track checkpoints, live lap stopwatch HUD, and R instant reset.',
        inScope: [
          'Ordered checkpoint zones preventing reverse-lap skip',
          'Live lap time + best lap readout + R restart',
        ],
        doneWhen: [
          'Finish 1 lap and press R -> Best lap records cleanly and craft resets to start line',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scripts/lap_timer.gd',
            role: 'Checkpoint sequence tracker & CanvasLayer HUD timer',
          ),
        ],
        outOfScope: const ['No online leaderboards or ghost replay saving'],
        states: const ['Countdown -> Racing -> LapFinish'],
        interrupts: const ['Press R resets lap clock and transforms craft to SpawnPoint'],
        features: [
          FeatureSpec(
            id: 'ep_03_f01',
            code: 'F05',
            title: 'Checkpoint Split Gates',
            introducedIn: 'v0.1',
            sliceTime: '30 min',
            status: FeatureStatus.queued,
            goal: 'Require passing $gateWidthVal $distUnit checkpoints before start gate counts.',
            tuning: [
              EpicTuningParam(key: 'checkpoint_width', value: gateWidthVal, unit: distUnit),
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
                action: 'reset_track',
                trigger: 'Just Pressed (R)',
                rule: 'Zeroes velocity and places craft at starting gate',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'reset_fade_s', value: '0.15', unit: 's'),
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
    testScenePath = 'res://scenes/course_proto.tscn';
    inputSummary =
        'InputMap (move_left/right/up/down, jump, air_dash, reset_course)';
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
            'Own responsive $bodyCls run/jump physics with coyote time and smooth $camNote follow.',
        inScope: [
          'Run speed $moveVal $speedUnit + crisp jump arc across obstacle platforms',
          '$dodgeDist $distUnit air dash / grapple burst resetting on landing',
        ],
        doneWhen: [
          'Run and jump across greybox gaps -> Zero missed edges during coyote window',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scenes/course_proto.tscn',
            role: 'Obstacle course test level + SpawnPoint + FinishGate',
          ),
          EpicSceneOwnership(
            path: 'res://scenes/player.tscn',
            role: '$bodyCls + $camNote follow rig',
          ),
          EpicSceneOwnership(
            path: 'res://scripts/player.gd',
            role: 'Run, jump buffer, coyote window & air dash state machine',
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
            goal: 'Run at $moveVal $speedUnit with crisp 0.12 s coyote jump grace.',
            controls: [
              EpicControlBinding(
                action: 'jump',
                trigger: 'Just Pressed (Space)',
                rule: 'Jumps cleanly with coyote & pre-land input buffer',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'move_speed', value: moveVal, unit: speedUnit),
              EpicTuningParam(key: 'coyote_time_s', value: '0.12', unit: 's'),
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
            goal: 'Burst $dodgeDist $distUnit mid-air along input vector before falling.',
            controls: [
              EpicControlBinding(
                action: 'air_dash',
                trigger: 'Just Pressed (Shift)',
                rule: 'Surges $dodgeDist $distUnit mid-air once per airborne jump',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'dash_distance', value: dodgeDist, unit: distUnit),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f02_c1',
                text: 'Press Shift mid-jump -> Traverses $dodgeDist $distUnit cleanly with trail',
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
            'Own greybox moving/crumbling platforms, fall reset plane, and course checkpoints.',
        inScope: [
          'Checkpoints within $reachVal $distUnit capture safe respawn coordinates',
          'Out-of-bounds trigger teleports cleanly to active checkpoint',
        ],
        doneWhen: [
          'Touch checkpoint then miss jump -> Player respawns at checkpoint in < 0.2 s',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scenes/checkpoint.tscn',
            role: 'Checkpoint pad + Area flag trigger',
          ),
          EpicSceneOwnership(
            path: 'res://scripts/course_hazards.gd',
            role: 'Fall plane & checkpoint respawn manager',
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
            goal: 'Capture spawn point within $reachVal $distUnit pad radius on overlap.',
            tuning: [
              EpicTuningParam(key: 'checkpoint_radius', value: reachVal, unit: distUnit),
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
            goal: 'Boost upward jump velocity cleanly when crossing spring pad nodes.',
            tuning: [
              EpicTuningParam(key: 'spring_boost_mult', value: '1.6', unit: 'x'),
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
            'Own speedrun stopwatch HUD, finish banner detection, and R instant course restart.',
        inScope: [
          'CanvasLayer stopwatch timer stopping on FinishGate contact',
          'Instant R full-course restart',
        ],
        doneWhen: [
          'Reach FinishGate -> Timer freezes cleanly and R restarts run from SpawnPoint',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scripts/course_timer.gd',
            role: 'Run timer & FinishGate HUD banner',
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
            goal: 'Stop stopwatch and display clear time when crossing $gateWidthVal $distUnit finish gate.',
            tuning: [
              EpicTuningParam(key: 'finish_gate_width', value: gateWidthVal, unit: distUnit),
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
            goal: 'Reset player to SpawnPoint and zero timer in < 0.2 s on R.',
            controls: [
              EpicControlBinding(
                action: 'reset_course',
                trigger: 'Just Pressed (R)',
                rule: 'Restarts course run immediately',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'reset_fade_s', value: '0.15', unit: 's'),
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
    testScenePath = 'res://scenes/arena_proto.tscn';
    inputSummary =
        'InputMap (move_left/right/up/down, dodge, primary_action, reset_proto)';
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
            'Own player $bodyCls locomotion, dash evasion impulse, and locked $camNote framing.',
        inScope: [
          'WASD movement at $moveVal $speedUnit inside $arenaExtent playtest room',
          'Forward $dodgeDist $distUnit dodge dash on 1.0 s cooldown',
        ],
        doneWhen: [
          'Move and dodge cleanly inside $arenaExtent -> Zero snagging against walls',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scenes/arena_proto.tscn',
            role: '$arenaExtent greybox test room + SpawnPoint',
          ),
          EpicSceneOwnership(
            path: 'res://scenes/player.tscn',
            role: '$bodyCls + $camNote follow rig',
          ),
          EpicSceneOwnership(
            path: 'res://scripts/player.gd',
            role: 'Movement state machine & @export physics',
          ),
        ],
        outOfScope: const [
          'No climbing, swimming, or crouch stances',
        ],
        states: const [
          'Idle / Move -> DodgeImpulse (0.16s) -> Recover -> Idle / Move',
        ],
        interrupts: const [
          'DodgeImpulse grants temporary collision mask bypass on enemy bodies',
        ],
        features: [
          FeatureSpec(
            id: 'ep_01_f01',
            code: 'F01',
            title: 'Planar Walk & Camera Tracking',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.active,
            goal: 'Control player movement at $moveVal $speedUnit with smooth $camNote follow.',
            controls: [
              EpicControlBinding(
                action: 'move_8way',
                trigger: 'Held (WASD)',
                rule: 'Moves smoothly at $moveVal $speedUnit across floor',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'move_speed', value: moveVal, unit: speedUnit),
            ],
            cues: const ['Subtle movement lean matching travel vector'],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f01_c1',
                text: 'Hold WASD -> Player moves at $moveVal $speedUnit cleanly',
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
            goal: 'Execute $dodgeDist $distUnit forward dodge impulse on 1.0 s cooldown.',
            controls: [
              EpicControlBinding(
                action: 'dodge',
                trigger: 'Just Pressed (Space)',
                rule: 'Dashes $dodgeDist $distUnit forward over 0.16 s',
              ),
            ],
            tuning: [
              EpicTuningParam(
                key: 'dodge_distance',
                value: dodgeDist,
                unit: distUnit,
              ),
              EpicTuningParam(key: 'dodge_cooldown', value: '1.0', unit: 's'),
            ],
            cues: const ['Bright debug trail ribbon during DodgeImpulse'],
            checks: [
              EpicPieCheck(
                id: 'ep_01_f02_c1',
                text: 'Press Space -> Travels $dodgeDist $distUnit cleanly with cooldown ring',
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
        inScope: [
          '$actionRange $distUnit aimed strike with 25 hp base hit damage',
          'Brief screen impulse and impact flash on hit',
        ],
        doneWhen: [
          'Click LMB toward target -> Hit registers out to $actionRange $distUnit cleanly',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scripts/primary_action.gd',
            role: 'Input trace / projectile spawn & 0.25 s cooldown lock',
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
            goal: 'Execute $actionRange $distUnit strike toward aim vector dealing 25 hp.',
            controls: [
              EpicControlBinding(
                action: 'primary_action',
                trigger: 'Just Pressed (LMB)',
                rule: 'Fires active projectile or melee trace out to $actionRange $distUnit',
              ),
            ],
            tuning: [
              EpicTuningParam(
                key: 'action_range',
                value: actionRange,
                unit: distUnit,
              ),
              EpicTuningParam(key: 'action_damage', value: '25', unit: 'hp'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ep_02_f01_c1',
                text: 'Click LMB -> Strikes cleanly out to $actionRange $distUnit',
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
              EpicTuningParam(key: 'action_cooldown', value: '0.25', unit: 's'),
            ],
            cues: const ['Emissive impact flash on hit + micro camera kick'],
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
          title: 'Field Utility & Nodes',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.queued,
          coreLoopBeat: 'Beat 3 · ${loop[2]}',
          goal:
              'Own deployable utility instances placed ahead of the player to shape arena space.',
          inScope: [
            'Spawn utility $deployDist $distUnit ahead on 3.0 s cooldown',
            'Cap max 2 concurrent deployed instances cleanly',
          ],
          doneWhen: [
            'Press E -> Utility node deploys $deployDist $distUnit ahead and activates on overlap',
          ],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/field_utility.tscn',
              role: 'Deployed utility node + trigger area',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/field_utility.gd',
              role: 'Placement distance, cooldown & max count queue',
            ),
          ],
          outOfScope: const [
            'No multi-tier building upgrade grid',
          ],
          states: [
            'Ready -> DeployActive ($deployDist $distUnit offset) -> Cooldown (3.0s)',
          ],
          interrupts: const [
            'Max 2 active utility instances free oldest node automatically',
          ],
          features: [
            FeatureSpec(
              id: 'ep_03_util_f01',
              code: 'F05',
              title: 'Forward Utility Deploy',
              introducedIn: 'v0.1',
              sliceTime: '45 min',
              status: FeatureStatus.queued,
              goal: 'Place utility $deployDist $distUnit ahead on E with cyan ring indicator.',
              controls: [
                EpicControlBinding(
                  action: 'secondary_action',
                  trigger: 'Just Pressed (E / RMB)',
                  rule: 'Deploys utility node $deployDist $distUnit ahead on a 3.0s cooldown',
                ),
              ],
              tuning: [
                EpicTuningParam(
                  key: 'deploy_distance',
                  value: deployDist,
                  unit: distUnit,
                ),
                EpicTuningParam(key: 'deploy_cooldown', value: '3.0', unit: 's'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_03_util_f01_c1',
                  text: 'Press E -> Utility appears $deployDist $distUnit ahead',
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
              goal: 'Keep at most 2 active utilities by freeing oldest instance on third deploy.',
              tuning: [
                EpicTuningParam(key: 'max_deployed', value: '2', unit: 'count'),
              ],
              checks: [
                EpicPieCheck(
                  id: 'ep_03_util_f02_c1',
                  text: 'Deploy third utility -> Oldest node despawns cleanly',
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
        inScope: [
          '100 hp target entities stationed $targetDist from SpawnPoint',
          '0.50 s telegraph warning before strike + R arena reset',
        ],
        doneWhen: [
          'Defeat targets and press R -> HUD updates cleanly and arena resets in < 0.2 s',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scenes/target_enemy.tscn',
            role: 'Target body + floating HP bar + telegraph indicator',
          ),
          EpicSceneOwnership(
            path: 'res://scripts/target_enemy.gd',
            role: 'Patrol / 0.50 s telegraph / Stagger loop',
          ),
        ],
        outOfScope: const [
          'No procedural dungeon rooms or loot chests',
        ],
        states: const [
          'Patrol -> Telegraph (0.50s) -> Execute -> Stagger / Defeated',
        ],
        interrupts: const [
          'Heavy hit triggers 0.40s brief knockback stagger without freezing player movement',
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
              EpicTuningParam(key: 'target_hp', value: '100', unit: 'hp'),
              EpicTuningParam(
                key: 'aggro_range',
                value: is2d ? '320' : '12.0',
                unit: distUnit,
              ),
              EpicTuningParam(
                key: 'telegraph_duration',
                value: '0.50',
                unit: 's',
              ),
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
                action: 'reset_proto',
                trigger: 'Just Pressed (R)',
                rule: 'Respawns targets and resets player HP to 100 in < 0.2s',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'reset_fade_s', value: '0.15', unit: 's'),
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
    pitch: '$title — $shortSpark',
    coreLoop: loop,
    cameraChoiceId: cameraChoice,
    cameraContract: cameraContract,
    inputContract: inputSummary,
    feelChoiceId: feelId,
    pillars: const [
      'Instant Frame-1 Control: Player movement and actions respond immediately without sluggish inertia',
      'Clear Spatial Silhouettes: Distinct bright/dark debug shapes communicate state changes before impact',
    ],
    tradeOffs: const [
      TradeOffRule(
        prefer: 'Tight single-scene greybox playtest room',
        avoid: 'Multi-level streaming worlds',
      ),
      TradeOffRule(
        prefer: 'Readable debug geometry & Control HUD',
        avoid: 'Premature final art pipelines',
      ),
    ],
    outOfScope: const [
      'No main menu, settings modal, or save slots',
      'No multiplayer networking or lobby flows',
      'No inventory UI or equipment loadouts',
    ],
    releaseDoneWhen:
        'Run F6 on $testScenePath -> complete full 30s core loop cleanly with 0 Debugger errors',
    initialEpics: epics,
  );
  _normalizeSequentialEpicAndFeatureCodesImpl(bp);
  _syncEpicCameraFramingImpl(
    bp,
    optionId: cameraChoice,
    contractValue: cameraContract,
  );
  _syncEpicCoreFeelImpl(bp, feelId: feelId);
  return bp;
}
