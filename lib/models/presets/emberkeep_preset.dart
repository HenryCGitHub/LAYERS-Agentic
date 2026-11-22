import '../agent_blueprints.dart';
import '../epic_spec.dart';

ProjectConceptBlueprint buildEmberkeepPreset(String sparkPrompt) {
  return ProjectConceptBlueprint(
    sparkPrompt: sparkPrompt,
    gameTitle: 'EMBER KEEP',
    architectureMode: UnrealArchitectureMode.blueprint,
    pitch:
        'Tactical top-down torch defense — cleave shadow stalkers while guarding shrinking brazier light rings',
    coreLoop: const [
      'Swing Torch Axe',
      'Plant Brazier Light',
      'Hold Safe Radius',
      'Collect Ash Shards',
    ],
    cameraChoiceId: 'topdown',
    cameraContract:
        'USpringArmComponent TargetArmLength 1550 cm @ -78 deg pitch, 50 deg FOV, CameraLagSpeed 8.0 (XY cursor world aim)',
    characterScale:
        'ACharacter CapsuleRadius 40 cm · HalfHeight 90 cm · WalkSpeed 620 cm/s',
    inputContract:
        'IMC_EmberKeep (IA_Move, IA_AxeSwing, IA_PlantBrazier)',
    assetPolicy:
        'UStaticMeshComponent Stone Courtyard + UPointLightComponent Torch Rings + Exposed BP Vars',
    feelChoiceId: 'heavy',
    cameraDecisionOptions: ProjectConceptBlueprint.defaultCameraOptions,
    pillars: const [
      'Light Defines Territory: Every dynamic light circle visibly alters enemy aggression and player safety',
      'Deliberate Heavy Swings: Axe cleaves carry distinct windup weight rather than rapid spam',
    ],
    tradeOffs: const [
      TradeOffRule(
        prefer: 'Dynamic radial UPointLightComponent rings for instant clarity',
        avoid: 'Static baked darkness rooms',
      ),
      TradeOffRule(
        prefer: 'Compact 3200x3200 cm courtyard',
        avoid: 'Procedural forest chunks',
      ),
    ],
    outOfScope: const [
      'No hunger, thirst, or weather meters',
      'No inventory drag-and-drop grid',
      'No crafting bench menus',
    ],
    releaseDoneWhen:
        'Run PIE on /Game/Maps/Lvl_KeepProto.umap -> plant brazier and fend off 3 shadow stalkers with 0 Message Log errors',
    initialEpics: [
      EpicSpec(
        id: 'ek_e01',
        code: 'E01',
        lineageKey: 'e01',
        title: 'Keeper Movement & Combat',
        releaseVersion: 'v0.1',
        lifecycle: EpicLifecycle.active,
        coreLoopBeat: 'Beat 1 · Swing Torch Axe',
        goal:
            'Own top-down keeper locomotion, smoothed USpringArmComponent tracking, and heavy directional axe cleaves.',
        inScope: const [
          'Normalized 620 cm/s courtyard walk & camera lag smoothing',
          '0.18 s windup 140 deg torch axe cleave pushing stalkers back',
        ],
        doneWhen: const [
          'Walk and swing across keep courtyard -> 240 cm cleave arc knocks shadow stalkers back cleanly',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: '/Game/Maps/Lvl_KeepProto.umap',
            role: '3200x3200 cm stone courtyard + perimeter wall meshes',
          ),
          EpicSceneOwnership(
            path: '/Game/Blueprints/BP_KeeperPlayer',
            role: 'ACharacter hero + USpringArmComponent + carried torch light',
          ),
        ],
        links: const [
          'Blueprint /Game/Blueprints/BP_KeeperPlayer',
          'Applies cleave knockback & damage to E03 Shadow Stalkers',
        ],
        outOfScope: const [
          'No multi-weapon swapping',
        ],
        controls: [
          EpicControlBinding(
            action: 'IA_Move',
            trigger: 'Triggered (WASD)',
            rule: 'Moves keeper at 620 cm/s; slowed 50% during AxeWindup',
          ),
          EpicControlBinding(
            action: 'IA_AxeSwing',
            trigger: 'Started (LMB)',
            rule: '0.18 s windup -> 140 deg UBoxComponent cleave hitbox out to 240 cm reach',
          ),
        ],
        states: const [
          'Idle / Move -> AxeWindup (0.18s) -> AxeStrike (0.12s) -> AxeRecover (0.20s)',
        ],
        interrupts: const [
          'Planting a Brazier (E02) takes priority over AxeRecover',
        ],
        tuning: [
          EpicTuningParam(key: 'WalkSpeed', value: '620', unit: 'cm/s'),
          EpicTuningParam(key: 'CleaveRadius', value: '240', unit: 'cm'),
          EpicTuningParam(key: 'CleaveDamage', value: '40', unit: 'hp'),
          EpicTuningParam(key: 'KnockbackImpulse', value: '800', unit: 'cm/s'),
        ],
        feedback: const [
          'Translucent amber 140 deg floor arc decal flashes on AxeStrike',
          'Carried UPointLightComponent flickers brighter during swing impact',
        ],
        levelStaging:
            '/Game/Maps/Lvl_KeepProto.umap: 3200x3200 cm stone courtyard + central bonfire + stone walls',
        checks: [
          EpicPieCheck(
            id: 'ek_e01_c1',
            text: 'Press LMB facing cursor -> axe cleave hits 240 cm cone and shoves dummy target back',
          ),
        ],
        features: [
          FeatureSpec(
            id: 'ek_f01',
            code: 'F01',
            title: 'Courtyard Walk & Follow Cam',
            introducedIn: 'v0.1',
            sliceTime: '45 min',
            status: FeatureStatus.passed,
            goal: 'Move keeper smoothly at 620 cm/s with smoothed USpringArmComponent courtyard tracking.',
            controls: [
              EpicControlBinding(
                action: 'IA_Move',
                trigger: 'Triggered (WASD)',
                rule: 'Moves ACharacter at WalkSpeed (620 cm/s)',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'WalkSpeed', value: '620', unit: 'cm/s'),
            ],
            cues: const ['Carried UPointLightComponent flickers gently with movement'],
            checks: [
              EpicPieCheck(
                id: 'ek_f01_c1',
                text: 'Walk across courtyard -> Moves cleanly at 620 cm/s with zero wall snagging',
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
            goal: 'Wind up for 0.18 s and sweep a 240 cm amber cleave sector knocking stalkers back.',
            controls: [
              EpicControlBinding(
                action: 'IA_AxeSwing',
                trigger: 'Started (LMB)',
                rule: '0.18 s windup -> 140 deg cleave trace at 240 cm reach',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'CleaveRadius', value: '240', unit: 'cm'),
              EpicTuningParam(key: 'CleaveDamage', value: '40', unit: 'hp'),
              EpicTuningParam(key: 'KnockbackImpulse', value: '800', unit: 'cm/s'),
            ],
            cues: const ['Amber 140 deg slash Niagara ribbon flashes on AxeStrike'],
            checks: [
              EpicPieCheck(
                id: 'ek_f02_c1',
                text: 'Click LMB facing target -> Cleaves 240 cm sector and knocks target back',
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
            'Deploy temporary field braziers projecting shrinking UPointLightComponent rings and fuel stoking loops.',
        inScope: const ['550 cm safe radius placement 140 cm ahead', '18 s flame decay curve'],
        doneWhen: const ['Press E -> Brazier lights 550 cm circle and shrinks smoothly over 18 s'],
        sceneOwnership: [
          EpicSceneOwnership(
            path: '/Game/Blueprints/BP_FieldBrazier',
            role: 'Placed brazier AActor + UPointLightComponent + floor decal ring',
          ),
        ],
        links: const [
          'Spawns /Game/Blueprints/BP_FieldBrazier and registers active light radius for E03',
        ],
        outOfScope: const [
          'No defensive stone wall grid snapping',
        ],
        controls: [
          EpicControlBinding(
            action: 'IA_PlantBrazier',
            trigger: 'Started (RMB / E)',
            rule: 'Spawns BP_FieldBrazier 140 cm ahead if AmberFuel >= 1',
          ),
        ],
        states: const [
          'Ignited (Full 550 cm radius) -> Flickering (< 200 cm) -> Extinguished',
        ],
        interrupts: const [
          'Hitting a planted brazier with AxeStrike stokes +4 s burn lifetime cleanly',
        ],
        tuning: [
          EpicTuningParam(key: 'StartLightRadius', value: '550', unit: 'cm'),
          EpicTuningParam(key: 'BurnDuration', value: '18.0', unit: 's'),
          EpicTuningParam(key: 'MaxActiveBraziers', value: '3', unit: 'count'),
        ],
        feedback: const [
          'Crisp glowing decal floor ring matches current UPointLightComponent safe attenuation radius',
        ],
        levelStaging:
            '/Game/Maps/Lvl_KeepProto.umap: dark perimeter corners contrast central lit courtyard circle',
        checks: [
          EpicPieCheck(
            id: 'ek_e02_c1',
            text: 'Press E -> brazier illuminates 550 cm circle and shrinks smoothly over 18 s',
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
            goal: 'Spawn a 550 cm UPointLightComponent brazier 140 cm ahead up to 3 active actors.',
            tuning: [
              EpicTuningParam(key: 'StartLightRadius', value: '550', unit: 'cm'),
              EpicTuningParam(key: 'MaxActiveBraziers', value: '3', unit: 'count'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ek_f03_c1',
                text: 'Press E -> Plants brazier lighting 550 cm circle on dark stone',
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
              EpicTuningParam(key: 'BurnDuration', value: '18.0', unit: 's'),
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
        inScope: const ['460 cm/s shadow prowl AI', '760 cm/s light recoil flee interrupt'],
        doneWhen: const ['Light brazier near stalker -> Stalker screeches and recoils past lit perimeter'],
        sceneOwnership: [
          EpicSceneOwnership(
            path: '/Game/Blueprints/BP_ShadowStalker',
            role: 'Enemy ACharacter + light proximity sensor',
          ),
        ],
        links: const [
          'Blueprint /Game/Blueprints/BP_ShadowStalker queries E02 active light rings & E01 cleave hits',
        ],
        outOfScope: const [
          'No ranged shadow projectile casters',
        ],
        controls: [
          EpicControlBinding(
            action: 'IA_AiStalkFlee',
            trigger: 'AI Behavior Tick',
            rule: 'Circles outside bright core -> dashes in when light dips -> flees on ignition',
          ),
        ],
        states: const [
          'ShadowProwl -> BiteLunge -> LightRecoil (1.2s) -> Dead (Drop 1 EmberFuel)',
        ],
        interrupts: const [
          'Fresh Brazier ignition inside 550 cm forces instant LightRecoil and cancels BiteLunge',
        ],
        tuning: [
          EpicTuningParam(key: 'StalkerHp', value: '80', unit: 'hp'),
          EpicTuningParam(key: 'ProwlSpeed', value: '460', unit: 'cm/s'),
          EpicTuningParam(key: 'RecoilSpeed', value: '760', unit: 'cm/s'),
        ],
        feedback: const [
          'Glowing violet eye slits dim whenever forced into LightRecoil',
        ],
        levelStaging:
            '/Game/Maps/Lvl_KeepProto.umap: 3 stalker spawns stationed around dark courtyard corners',
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
            goal: 'Orbit dimly lit zones at 460 cm/s and dart toward keeper when light shrinks.',
            tuning: [
              EpicTuningParam(key: 'StalkerHp', value: '80', unit: 'hp'),
              EpicTuningParam(key: 'ProwlSpeed', value: '460', unit: 'cm/s'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ek_f05_c1',
                text: 'Stand in dimming courtyard -> Stalker creeps inward at 460 cm/s',
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
            goal: 'Cancel enemy BiteLunge cleanly and push stalker outward at 760 cm/s on fresh light.',
            tuning: [
              EpicTuningParam(key: 'RecoilSpeed', value: '760', unit: 'cm/s'),
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
    v02Presets: const [
      ReleaseDirectionPreset(
        id: 'agile_flame',
        label: 'Agile Flame Combat',
        description:
            'Pair ember roll dodge with crisp cleave arcs and stalker threat waves.',
        upgradeIds: ['up_ek_e01_arc', 'up_ek_e03_telegraph', 'ek_f07_roll'],
        newEpicIds: ['ek_e04'],
      ),
      ReleaseDirectionPreset(
        id: 'siege_ring',
        label: 'Brazier Siege Sustain',
        description:
            'Extend brazier flare bursts while defending against escalating night waves.',
        upgradeIds: ['up_ek_e02_flare', 'up_ek_e03_telegraph', 'ek_f07_roll'],
        newEpicIds: ['ek_e04'],
      ),
    ],
    v02UpgradesByLineageKey: {
      'e01': [
        EpicUpgradeOption(
          id: 'up_ek_e01_arc',
          targetFeatureCode: 'F02',
          text: '+60 cm wider torch axe swipe arc with 35ms hitstop',
          chosen: true,
        ),
      ],
      'e02': [
        EpicUpgradeOption(
          id: 'up_ek_e02_flare',
          targetFeatureCode: 'F03',
          text: '+150 cm initial ignition flash pulse pushing nearby shadows',
        ),
      ],
      'e03': [
        EpicUpgradeOption(
          id: 'up_ek_e03_telegraph',
          targetFeatureCode: 'F05',
          text: '+Glowing eye-slit telegraph line 0.35 s before BiteLunge',
          chosen: true,
        ),
      ],
    },
    v02NewFeaturesByLineageKey: {
      'e01': [
        FeatureSpec(
          id: 'ek_f07_roll',
          code: 'F07',
          title: 'Ember Roll Dodge',
          introducedIn: 'v0.2',
          sliceTime: '45 min',
          status: FeatureStatus.active,
          goal: 'Roll 320 cm past stalker bites at 1150 cm/s with 0.55 s cooldown.',
          tuning: [
            EpicTuningParam(key: 'RollSpeed', value: '1150', unit: 'cm/s'),
            EpicTuningParam(key: 'RollDist', value: '320', unit: 'cm'),
          ],
          checks: [
            EpicPieCheck(
              id: 'ek_f07_c1',
              text: 'Press Space -> Keeper rolls 320 cm cleanly with Niagara ember dust',
            ),
          ],
        ),
      ],
    },
    v02NewPool: [
      EpicSpec(
        id: 'ek_e04',
        code: 'E04',
        lineageKey: 'e04',
        title: 'Night Wave Pressure',
        releaseVersion: 'v0.2',
        lifecycle: EpicLifecycle.newEpic,
        coreLoopBeat: 'Beat 4 · Escalating Courtyard Pressure',
        chosenForNextRelease: true,
        goal:
            'Spawn 3 timed shadow stalker waves from dark keep corners with top-center WBP HUD counter.',
        inScope: const [
          '3 courtyard wave tiers spaced 800 cm outside center brazier',
          'Top-center UMG Widget night wave readout & R quick restart',
        ],
        doneWhen: const [
          'Clear Night Wave 1 -> 2.0 s breather plays and Wave 2 spawns from shadowed edges',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: '/Game/Blueprints/BP_NightWaveDirector',
            role: 'Wave spawn timing, edge offsets & R reset hook',
          ),
        ],
        outOfScope: const [
          'No multi-floor procedural dungeon rooms',
        ],
        states: const [
          'WaveIntro -> ActiveHunt -> Breather (2.0s) -> NightSurvived',
        ],
        interrupts: const [
          'Center brazier burnout halts spawns and triggers Relight Prompt UMG Widget',
        ],
        features: [
          FeatureSpec(
            id: 'ek_e04_f01',
            code: 'F08',
            title: 'Timed Courtyard Wave Spawner',
            introducedIn: 'v0.2',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Spawn 3 escalating shadow waves at 800 cm radius with top-center WBP HUD counter.',
            tuning: [
              EpicTuningParam(key: 'SpawnEdgeOffset', value: '800', unit: 'cm'),
              EpicTuningParam(key: 'BreatherSeconds', value: '2.0', unit: 's'),
            ],
            checks: [
              EpicPieCheck(
                id: 'ek_e04_f01_c1',
                text: 'Defeat Wave 1 stalkers -> HUD updates and Wave 2 spawns after 2.0 s',
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
