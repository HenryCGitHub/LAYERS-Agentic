import '../agent_blueprints.dart';
import '../epic_spec.dart';

ProjectConceptBlueprint buildEmberkeepPreset(String sparkPrompt) {
  return ProjectConceptBlueprint(
    sparkPrompt: sparkPrompt,
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
    v02Presets: const [
      ReleaseDirectionPreset(
        id: 'agile_flame',
        label: 'Agile Flame Combat',
        description:
            'Pair 2D ember roll dodge with crisp cleave arcs and stalker threat waves.',
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
          text: '+24 px wider 2D torch axe swipe arc with 35ms hitstop',
          chosen: true,
        ),
      ],
      'e02': [
        EpicUpgradeOption(
          id: 'up_ek_e02_flare',
          targetFeatureCode: 'F03',
          text: '+60 px initial ignition flash pulse pushing nearby shadows',
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
    v02NewPool: [
      EpicSpec(
        id: 'ek_e04',
        code: 'E04',
        lineageKey: 'e04',
        title: '2D Night Wave Pressure',
        releaseVersion: 'v0.2',
        lifecycle: EpicLifecycle.newEpic,
        coreLoopBeat: 'Beat 4 · Escalating Courtyard Pressure',
        chosenForNextRelease: true,
        goal:
            'Spawn 3 timed 2D shadow stalker waves from dark keep corners with top-center counter HUD.',
        inScope: const [
          '3 courtyard wave tiers spaced 320 px outside center brazier',
          'Top-center HUD night wave readout & R quick restart',
        ],
        doneWhen: const [
          'Clear Night Wave 1 -> 2.0 s breather plays and Wave 2 spawns from shadowed edges',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: 'res://scripts/night_wave_director.gd',
            role: '2D wave spawn timing, edge offsets & R reset hook',
          ),
        ],
        outOfScope: const [
          'No multi-floor procedural dungeon rooms',
        ],
        states: const [
          'WaveIntro -> ActiveHunt -> Breather (2.0s) -> NightSurvived',
        ],
        interrupts: const [
          'Center brazier burnout halts spawns and triggers Relight Prompt overlay',
        ],
        features: [
          FeatureSpec(
            id: 'ek_e04_f01',
            code: 'F08',
            title: 'Timed Courtyard Wave Spawner',
            introducedIn: 'v0.2',
            sliceTime: '45 min',
            status: FeatureStatus.queued,
            goal: 'Spawn 3 escalating 2D shadow waves at 320 px radius with top-center HUD counter.',
            tuning: [
              EpicTuningParam(key: 'spawn_edge_offset', value: '320', unit: 'px'),
              EpicTuningParam(key: 'breather_seconds', value: '2.0', unit: 's'),
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
