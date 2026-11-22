import '../agent_blueprints.dart';
import '../epic_spec.dart';

ProjectConceptBlueprint buildRailjackPreset(String sparkPrompt) {
  return ProjectConceptBlueprint(
    sparkPrompt: sparkPrompt,
    gameTitle: 'RAILJACK DRIFT',
    architectureMode: UnrealArchitectureMode.cppHybrid,
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
        'USpringArmComponent TargetArmLength 440 cm @ -12 deg pitch · Dynamic FOV 74->92 deg by speed · CameraLagSpeed 12.0',
    characterScale:
        'APawn Hull 340x160 cm · HoverHeight 85 cm · BaseTopSpeed 3100 cm/s',
    inputContract:
        'IMC_SkiffControls (IA_Throttle, IA_Steer, IA_DriftHold, IA_BoostHold, IA_ResetTrack)',
    assetPolicy:
        'Source/HoverSkiffPawn.cpp UPROPERTY(EditAnywhere) Physics + Thin /Game/Blueprints/BP_HoverSkiff & /Game/Data/DA_SkiffPhysics',
    feelChoiceId: 'physics',
    cameraDecisionOptions: ProjectConceptBlueprint.defaultCameraOptions,
    pillars: const [
      'Flow Over Friction: Wall scrapes glance forward cleanly instead of dead-stopping momentum',
      'Speed Tells Everything: Camera FOV, engine pitch, and wing-tip Niagara trails rise smoothly into boost',
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
        'Run PIE on /Game/Maps/Lvl_CanyonProto.umap -> complete 1 clean canyon lap with final timer HUD and 0 Message Log errors',
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
          '85 cm spring hover height stabilization',
          'ApexDrift carving that feeds boost charge',
        ],
        doneWhen: const [
          'Carve hairpin canyon turn -> Skiff maintains 85 cm height and exits cleanly on tangent',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: '/Game/Maps/Lvl_CanyonProto.umap',
            role: 'Banked greybox canyon track loop',
          ),
          EpicSceneOwnership(
            path: 'Source/HoverSkiffPawn.cpp',
            role: 'Hover raycast springs + drift slip math (C++ base)',
          ),
          EpicSceneOwnership(
            path: '/Game/Blueprints/BP_HoverSkiff',
            role: 'Thin Pawn subclass + USpringArmComponent camera rig',
          ),
        ],
        links: const [
          'Source/HoverSkiffPawn.cpp + /Game/Blueprints/BP_HoverSkiff',
          'Exposes OnSpeedChanged & OnDriftStateChanged delegates to E02 Boost & E03 Gate HUD',
        ],
        outOfScope: const [
          'No upside-down loop-the-loop gravity shifts',
        ],
        controls: [
          EpicControlBinding(
            action: 'IA_Throttle',
            trigger: 'Triggered (W / Up)',
            rule: 'Accelerates forward velocity smoothly up to BaseTopSpeed 3100 cm/s',
          ),
          EpicControlBinding(
            action: 'IA_Steer',
            trigger: 'Triggered (A / D)',
            rule: 'Banks SkiffMesh roll +/-26 deg smoothly while turning yaw rate',
          ),
          EpicControlBinding(
            action: 'IA_DriftHold',
            trigger: 'Triggered (Space / Shift)',
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
          EpicTuningParam(key: 'HoverHeight', value: '85', unit: 'cm'),
          EpicTuningParam(key: 'BaseTopSpeed', value: '3100', unit: 'cm/s'),
          EpicTuningParam(key: 'MaxBankAngle', value: '26', unit: 'deg'),
          EpicTuningParam(key: 'DriftChargeRate', value: '35', unit: '%/s'),
        ],
        feedback: const [
          'Twin cyan thrusters lengthen with throttle and flare orange during ApexDrift',
          'Dynamic UCameraComponent FOV expands smoothly from 74 to 92 deg with forward velocity',
        ],
        levelStaging:
            '/Game/Maps/Lvl_CanyonProto.umap: wide banked greybox canyon track (~40s loop) with hairpin turn',
        checks: [
          EpicPieCheck(
            id: 'rj_e01_c1',
            text: 'Drive over sloped ramp -> hull holds ~85 cm clearance without floor clipping',
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
            goal: 'Keep hull hovering at 85 cm across slopes while cruising up to 3100 cm/s.',
            inScope: const ['LineTraceSingleByChannel ground spring', 'W/A/D steer banking +/-26 deg'],
            doneWhen: const ['Ride canyon slope -> Hull holds 85 cm clearance without scraping'],
            controls: [
              EpicControlBinding(
                action: 'IA_Throttle',
                trigger: 'Triggered (W / Up)',
                rule: 'Accelerates smoothly up to 3100 cm/s',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'HoverHeight', value: '85', unit: 'cm'),
              EpicTuningParam(key: 'BaseTopSpeed', value: '3100', unit: 'cm/s'),
            ],
            cues: const ['Twin cyan Niagara thrusters scale cleanly with throttle'],
            checks: [
              EpicPieCheck(
                id: 'rj_f01_c1',
                text: 'Drive across ramp -> Skiff maintains 85 cm hover gap cleanly',
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
                action: 'IA_DriftHold',
                trigger: 'Triggered (Space / Shift)',
                rule: 'Enters ApexDrift and charges boost meter',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'MaxBankAngle', value: '26', unit: 'deg'),
              EpicTuningParam(key: 'DriftChargeRate', value: '35', unit: '%/s'),
            ],
            cues: const ['Wing thrusters flare orange with faint Niagara edge sparks'],
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
        inScope: const ['4200 cm/s manual boost surge', '1.5 s overheat lockout vent'],
        doneWhen: const ['Hold E with boost -> Speed surges to 4200 cm/s and HUD bar responds'],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'Source/ThrusterBoostComponent.cpp',
            role: 'Boost drain curve, heat cap & FOV kick delegate',
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
            action: 'IA_BoostHold',
            trigger: 'Triggered (RMB / E)',
            rule: 'Pushes target speed to 4200 cm/s while draining boost meter',
          ),
        ],
        states: const [
          'Normal -> Boosting (Max 4200 cm/s) -> OverheatLockout (1.5s) -> Normal',
        ],
        interrupts: const [
          'Touching E03 Boost Gate grants instant +0.8 s surge without raising heat',
        ],
        tuning: [
          EpicTuningParam(key: 'BoostTopSpeed', value: '4200', unit: 'cm/s'),
          EpicTuningParam(key: 'BoostDrainRate', value: '28', unit: '%/s'),
          EpicTuningParam(key: 'OverheatCooldown', value: '1.5', unit: 's'),
        ],
        feedback: const [
          'Edge speed-lines UMG Widget overlay + bright white exhaust core while Boosting',
          'Centered horizontal WBP thruster progress bar shows cm/s & Boost %',
        ],
        levelStaging:
            '/Game/Maps/Lvl_CanyonProto.umap: straightaway run + speed readout UMG Widget overlay',
        checks: [
          EpicPieCheck(
            id: 'rj_e02_c1',
            text: 'Hold E with Boost available -> velocity jumps smoothly to 4200 cm/s with widened FOV',
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
            goal: 'Accelerate top speed to 4200 cm/s when holding E while widening UCameraComponent FOV.',
            tuning: [
              EpicTuningParam(key: 'BoostTopSpeed', value: '4200', unit: 'cm/s'),
            ],
            cues: const ['White exhaust core + widened FOV 92 deg speed-lines'],
            checks: [
              EpicPieCheck(
                id: 'rj_f03_c1',
                text: 'Hold E on straightaway -> Velocity surges to 4200 cm/s smoothly',
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
            goal: 'Lock thruster after sustained overheat for 1.5 s with centered speed and % HUD gauge.',
            tuning: [
              EpicTuningParam(key: 'OverheatCooldown', value: '1.5', unit: 's'),
            ],
            cues: const ['WBP thruster bar flashes red during 1.5 s vent'],
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
        inScope: const ['6 sequential boost gate rings', 'Par timer WBP HUD & R instant reset'],
        doneWhen: const ['Pass Gate 1..6 -> Gate 6 posts final mm:ss.ms lap time cleanly'],
        sceneOwnership: [
          EpicSceneOwnership(
            path: '/Game/UI/WBP_LapTimerHud',
            role: 'Gate sequencer UI, par delta readout & R track reset',
          ),
        ],
        links: const [
          'Connects UBoxComponent OnComponentBeginOverlap from BP_HoverSkiff (E01) to E02 surge pulse',
        ],
        outOfScope: const [
          'No persistent ghost replay serialization',
        ],
        controls: [
          EpicControlBinding(
            action: 'IA_ResetTrack',
            trigger: 'Started (R)',
            rule: 'Snaps skiff cleanly to StartLine TargetPoint and resets LapTimer to 0.00 s',
          ),
        ],
        states: const [
          'Countdown (0.8s) -> Racing (Gate 1..6) -> LapFinished (Display Final Time)',
        ],
        interrupts: const [
          'Skipping an ordered gate shows floating OFF-COURSE WBP HUD arrow toward missed gate',
        ],
        tuning: [
          EpicTuningParam(key: 'GateHalfWidth', value: '480', unit: 'cm'),
          EpicTuningParam(key: 'GateBoostDuration', value: '0.8', unit: 's'),
          EpicTuningParam(key: 'ParTimeSeconds', value: '42.0', unit: 's'),
        ],
        feedback: const [
          'Active next gate glows bright emerald; passed gates turn muted slate',
          'Top-right WBP_LapTimerHud displays mm:ss.ms + green/red delta vs par time',
        ],
        levelStaging:
            '/Game/Maps/Lvl_CanyonProto.umap: 6 sequential UBoxComponent boost gate arches ending at Start/Finish',
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
              EpicTuningParam(key: 'GateHalfWidth', value: '480', unit: 'cm'),
              EpicTuningParam(key: 'GateBoostDuration', value: '0.8', unit: 's'),
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
              EpicTuningParam(key: 'ParTimeSeconds', value: '42.0', unit: 's'),
            ],
            cues: const ['Green/red split delta flashes cleanly across top-right UMG Widget'],
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
    v02Presets: const [
      ReleaseDirectionPreset(
        id: 'precision',
        label: 'Precision Drift Flow',
        description:
            'Hold boost charge through apex carves and spray canyon wall sparks cleanly.',
        upgradeIds: ['up_rj_e01_slipstream', 'up_rj_e03_split_badge', 'rj_f07_wallglide'],
        newEpicIds: ['rj_e04'],
      ),
      ReleaseDirectionPreset(
        id: 'marathon',
        label: 'Time Trial Rivals',
        description:
            'Add sector split ghost playback alongside drift spark feedback and overdrive.',
        upgradeIds: ['up_rj_e02_grip_flash', 'up_rj_e03_split_badge', 'rj_f07_wallglide'],
        newEpicIds: ['rj_e04'],
      ),
    ],
    v02UpgradesByLineageKey: {
      'e01': [
        EpicUpgradeOption(
          id: 'up_rj_e01_slipstream',
          targetFeatureCode: 'F01',
          text: '+12% yaw turn-in crispness above 2800 cm/s cruise speed',
          chosen: true,
        ),
      ],
      'e02': [
        EpicUpgradeOption(
          id: 'up_rj_e02_grip_flash',
          targetFeatureCode: 'F04',
          text: '+Amber thrusters pulse when Drift Charge reaches 100%',
        ),
      ],
      'e03': [
        EpicUpgradeOption(
          id: 'up_rj_e03_split_badge',
          targetFeatureCode: 'F06',
          text: '+Floating green/red split sector delta flash on gate pass',
          chosen: true,
        ),
      ],
    },
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
            EpicTuningParam(key: 'WallKeepPct', value: '78', unit: '%'),
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
    v02NewPool: [
      EpicSpec(
        id: 'rj_e04',
        code: 'E04',
        lineageKey: 'e04',
        title: 'Ghost Split Replay',
        releaseVersion: 'v0.2',
        lifecycle: EpicLifecycle.newEpic,
        coreLoopBeat: 'Beat 4 · Best-Lap Ghost Comparison',
        chosenForNextRelease: true,
        goal:
            'Record local best-run transform samples at 15 Hz and replay a translucent wireframe skiff ghost.',
        inScope: const [
          '15 Hz ring-buffer transform recorder',
          'Translucent ghost skiff playback against par clock',
        ],
        doneWhen: const [
          'Complete Lap 1 and press R -> Ghost skiff races along prior best line cleanly',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'Source/GhostRecorderComponent.cpp',
            role: '15 Hz transform sampling & translucent ghost playback',
          ),
        ],
        outOfScope: const [
          'No online leaderboard uploads',
        ],
        states: const [
          'Recording -> LapSaved -> PlaybackLoop',
        ],
        interrupts: const [
          'Press R resets ghost playback cleanly to frame 0 at StartLine',
        ],
        features: [
          FeatureSpec(
            id: 'rj_e04_f01',
            code: 'F08',
            title: 'Best-Lap Wireframe Ghost Skiff',
            introducedIn: 'v0.2',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Record 15 Hz skiff transforms and spawn translucent wireframe ghost on subsequent runs.',
            tuning: [
              EpicTuningParam(key: 'GhostSampleHz', value: '15', unit: 'count'),
            ],
            checks: [
              EpicPieCheck(
                id: 'rj_e04_f01_c1',
                text: 'Finish Lap 1 and tap R -> Wireframe ghost skiff replays prior line cleanly',
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
