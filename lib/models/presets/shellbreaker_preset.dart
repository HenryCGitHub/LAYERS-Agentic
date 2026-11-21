import '../agent_blueprints.dart';
import '../epic_spec.dart';

ProjectConceptBlueprint buildShellbreakerPreset(String sparkPrompt) {
  return ProjectConceptBlueprint(
    sparkPrompt: sparkPrompt,
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
        upgradeIds: ['up_e01_hitstop', 'up_e03_knockback', 'sb_f07_chain'],
        newEpicIds: ['sb_e04'],
      ),
      ReleaseDirectionPreset(
        id: 'defensive',
        label: 'Parry & Crowd Control',
        description:
            'Reward close-range shell parries while expanding the wave loop.',
        upgradeIds: ['up_e02_crit', 'up_e03_deathshatter'],
        newEpicIds: ['sb_e04', 'sb_e05'],
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
            code: 'F08',
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
            code: 'F09',
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
