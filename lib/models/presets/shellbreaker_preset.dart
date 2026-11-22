import '../agent_blueprints.dart';
import '../epic_spec.dart';

ProjectConceptBlueprint buildShellbreakerPreset(String sparkPrompt) {
  return ProjectConceptBlueprint(
    sparkPrompt: sparkPrompt,
    gameTitle: 'SHELLBREAKER',
    architectureMode: UnrealArchitectureMode.blueprint,
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
        'USpringArmComponent TargetArmLength 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLagSpeed 9.0 (XY cursor plane aim)',
    characterScale:
        'ACharacter CapsuleRadius 42 cm · HalfHeight 92 cm · MaxWalkSpeed 640 cm/s',
    inputContract:
        'IMC_Shellbreaker (IA_Move, IA_MouseAim, IA_ClawDash, IA_FireBurst)',
    assetPolicy:
        'UStaticMeshComponent Greybox + UMaterialInstanceDynamic Tints; /Game/Data/DA_ShellbreakerTuning',
    feelChoiceId: 'snappy',
    cameraDecisionOptions: ProjectConceptBlueprint.defaultCameraOptions,
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
      'No co-op multiplayer networking',
      'No procedural terrain or multi-zone progression',
    ],
    releaseDoneWhen:
        'Run PIE on /Game/Maps/Lvl_ShellbreakerProto.umap -> dash and shatter dummy crab cleanly with 0 Message Log errors',
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
          '8-way arena XY planar movement & mouse ground-plane aim',
          'Invulnerable 550 cm forward Claw Dash with cooldown indicator',
          'Dampened USpringArmComponent follow camera with cursor aim lead',
        ],
        doneWhen: const [
          'All E01 movement and dash Features pass PIE -> Camera & mech move smoothly with zero snag',
        ],
        sceneOwnership: [
          EpicSceneOwnership(
            path: '/Game/Maps/Lvl_ShellbreakerProto.umap',
            role: '3000x3000 cm walled greybox floor + cover pillars',
          ),
          EpicSceneOwnership(
            path: '/Game/Blueprints/BP_PlayerMech',
            role: 'ACharacter root + TurretVisual + DashHitbox + USpringArmComponent',
          ),
        ],
        links: const [
          'Blueprint /Game/Blueprints/BP_PlayerMech',
          'Broadcasts OnDashImpact dispatcher & ApplyDamage contract to E03',
          'Drives USpringArmComponent lag and dash Niagara ribbon',
        ],
        outOfScope: const [
          'No slope stair-stepping mechanics',
          'No dash charge stacking',
        ],
        controls: [
          EpicControlBinding(
            action: 'IA_Move',
            trigger: 'Triggered (WASD)',
            rule: 'Ground velocity clamped cleanly at 640 cm/s; locked during DashActive',
          ),
          EpicControlBinding(
            action: 'IA_MouseAim',
            trigger: 'Tick HitResult UnderCursor',
            rule: 'Rotates TurretVisual scene component toward cursor XY ground intersection every frame',
          ),
          EpicControlBinding(
            action: 'IA_ClawDash',
            trigger: 'Started (Space / RMB)',
            rule: 'Launches forward 550 cm over 0.16 s along aim vector on 1.1 s cooldown',
          ),
        ],
        states: const [
          'Idle / Move -> DashWindup (0.04s) -> DashActive (0.16s) -> DashRecover (0.08s)',
        ],
        interrupts: const [
          'DashActive cancels weapon burst fire cleanly and enables DashHitbox overlap',
        ],
        tuning: [
          EpicTuningParam(key: 'MoveSpeed', value: '640', unit: 'cm/s'),
          EpicTuningParam(key: 'DashDistance', value: '550', unit: 'cm'),
          EpicTuningParam(key: 'DashDuration', value: '0.16', unit: 's'),
          EpicTuningParam(key: 'DashCooldown', value: '1.1', unit: 's'),
        ],
        feedback: const [
          'Orange emissive Niagara thruster ribbon during DashActive (0.16 s)',
          'Compact radial cooldown arc inside WBP HUD UMG Widget overlay',
          'Subtle camera shake punch on wall or enemy dash collision',
        ],
        levelStaging:
            '/Game/Maps/Lvl_ShellbreakerProto.umap: 3000x3000 cm walled greybox floor + 2 static cover pillars + PlayerStart at origin',
        checks: [
          EpicPieCheck(
            id: 'sb_e01_c1',
            text: 'Hold WASD -> mech accelerates smoothly to 640 cm/s with zero wall snagging',
          ),
          EpicPieCheck(
            id: 'sb_e01_c2',
            text: 'Move cursor across floor -> TurretVisual tracks aim vector smoothly without flip',
          ),
          EpicPieCheck(
            id: 'sb_e01_c3',
            text: 'Press Space -> dash travels ~550 cm along aim direction and obeys 1.1s cooldown',
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
                'Move smoothly at 640 cm/s across the arena XY plane and orient TurretVisual toward the mouse trace target.',
            inScope: const [
              'WASD 8-way planar locomotion',
              'Ground-plane XY cursor line-trace aim',
              'Dampened USpringArmComponent follow camera',
            ],
            doneWhen: const [
              'Hold WASD into cover pillars -> Mech slides smoothly without catching edges',
            ],
            controls: [
              EpicControlBinding(
                action: 'IA_Move',
                trigger: 'Triggered (WASD)',
                rule: 'Accelerates immediately up to MaxWalkSpeed (640 cm/s)',
              ),
              EpicControlBinding(
                action: 'IA_MouseAim',
                trigger: 'Tick HitResult UnderCursor',
                rule: 'Projects cursor trace onto XY plane to rotate TurretVisual',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'MoveSpeed', value: '640', unit: 'cm/s'),
              EpicTuningParam(key: 'CamFollowDamp', value: '9.0', unit: '1/s'),
            ],
            cues: const [
              'Floor aim ring decal highlights cursor intersection point cleanly',
            ],
            checks: [
              EpicPieCheck(
                id: 'sb_f01_c1',
                text: 'Hold WASD -> mech moves cleanly at 640 cm/s with zero wall snagging',
                passed: true,
              ),
              EpicPieCheck(
                id: 'sb_f01_c2',
                text: 'Move mouse across arena -> TurretVisual tracks cursor accurately',
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
                'Launch a 550 cm forward commitment dash with Niagara ribbon, invulnerability window, and 1.1 s cooldown.',
            inScope: const [
              'Space / RMB dash impulse over 0.16 s',
              'DashHitbox UBoxComponent enemy impact trigger',
              'Radial cooldown WBP UMG Widget indicator',
            ],
            doneWhen: const [
              'Press Space -> Mech crosses 550 cm cleanly and triggers OnDashImpact on crab shells',
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
                action: 'IA_ClawDash',
                trigger: 'Started (Space / RMB)',
                rule: 'Launches 550 cm over 0.16 s along aim vector on 1.1 s cooldown',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'DashDistance', value: '550', unit: 'cm'),
              EpicTuningParam(key: 'DashDuration', value: '0.16', unit: 's'),
              EpicTuningParam(key: 'DashCooldown', value: '1.1', unit: 's'),
            ],
            cues: const [
              'Orange emissive Niagara thruster ribbon fires for 0.16 s',
              'Subtle camera punch on wall or crab shell impact',
            ],
            checks: [
              EpicPieCheck(
                id: 'sb_f02_c1',
                text: 'Press Space -> dash travels 550 cm along aim vector and obeys 1.1 s cooldown',
                passed: false,
              ),
            ],
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
            path: '/Game/Blueprints/BP_KineticBolt',
            role: 'High-velocity UProjectileMovementComponent + emissive mesh',
          ),
          EpicSceneOwnership(
            path: '/Game/Blueprints/BP_BurstCannonComponent',
            role: '3-round fire cadence, recoil push & heat tracker',
          ),
        ],
        links: const [
          'Spawns /Game/Blueprints/BP_KineticBolt from player muzzle USceneComponent',
          'Calls ApplyDamage on E03 crab targets',
        ],
        outOfScope: const [
          'No alternate ammo pickups',
          'No manual reload button',
        ],
        controls: [
          EpicControlBinding(
            action: 'IA_FireBurst',
            trigger: 'Triggered (LMB)',
            rule: 'Spawns 3-bolt burst over 0.24 s when Heat < 100 and not DashActive',
          ),
        ],
        states: const [
          'Ready -> BurstFiring (3 shots @ 0.08s interval) -> CycleCooldown (0.28s) -> Ready',
          'Heat >= 100 -> OverheatLock (1.3s vent) -> Ready',
        ],
        interrupts: const [
          'Triggering IA_ClawDash immediately aborts remaining burst bolts safely',
          'Passive heat decay pauses for 0.35 s right after last shot fired',
        ],
        tuning: [
          EpicTuningParam(key: 'BoltSpeed', value: '2400', unit: 'cm/s'),
          EpicTuningParam(key: 'BurstDamage', value: '18', unit: 'hp'),
          EpicTuningParam(key: 'OverheatTime', value: '1.3', unit: 's'),
          EpicTuningParam(key: 'RecoilImpulse', value: '120', unit: 'cm/s'),
        ],
        feedback: const [
          'Bright yellow emissive projectile capsules with Niagara spark burst on wall hit',
          'Barrel kicks back 18 cm per shot and lerps smoothly forward',
          'Thin curved heat bar turns amber above 75%',
        ],
        levelStaging:
            '/Game/Maps/Lvl_ShellbreakerProto.umap: firing lane with static calibration cubes at 600 cm and 1400 cm',
        checks: [
          EpicPieCheck(
            id: 'sb_e02_c1',
            text: 'Hold LMB -> fires crisp 3-bolt bursts toward cursor with visible barrel recoil',
          ),
          EpicPieCheck(
            id: 'sb_e02_c2',
            text: 'Sustained fire past cap -> triggers 1.3 s overheat vent and resumes cleanly',
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
                'Spawn 3-bolt 2400 cm/s bursts toward cursor aim with backwards barrel recoil impulse.',
            inScope: const ['3-round 0.08 s cadence', '120 cm/s chassis recoil push'],
            doneWhen: const ['Hold LMB -> 3 yellow bolts streak toward cursor with barrel kick'],
            controls: [
              EpicControlBinding(
                action: 'IA_FireBurst',
                trigger: 'Triggered (LMB)',
                rule: 'Fires 3 bolts when Heat < 100 and not DashActive',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'BoltSpeed', value: '2400', unit: 'cm/s'),
              EpicTuningParam(key: 'BurstDamage', value: '18', unit: 'hp'),
              EpicTuningParam(key: 'RecoilImpulse', value: '120', unit: 'cm/s'),
            ],
            cues: const ['Barrel kicks back 18 cm per bolt + Niagara hit sparks on wall collision'],
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
            inScope: const ['1.3 s OverheatLock vent cycle', 'WBP curved heat gauge'],
            doneWhen: const ['Fire continuously to cap -> Heat bar triggers 1.3 s vent cleanly'],
            releaseDelta: '+2x weak-point crit bolts vs staggered crabs (instant heat vent)',
            releaseDeltaChecks: [
              EpicPieCheck(
                id: 'sb_f04_dc1',
                text: 'Shoot staggered crab -> 2x amber crits trigger immediate heat vent',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'OverheatTime', value: '1.3', unit: 's'),
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
            path: '/Game/Blueprints/BP_CrabGrunt',
            role: 'Enemy ACharacter + front armor shield collider',
          ),
        ],
        links: const [
          'Blueprint /Game/Blueprints/BP_CrabGrunt',
          'Responds to ApplyDamage & ApplyDashShatter from E01/E02',
        ],
        outOfScope: const [
          'No wave spawner director yet (placed directly in map)',
          'No ranged enemy variants',
        ],
        controls: [
          EpicControlBinding(
            action: 'IA_AiLunge',
            trigger: 'AI Behavior (420 cm range)',
            rule: 'Faces player -> telegraphs 0.45 s crimson flash -> lunges 420 cm',
          ),
        ],
        states: const [
          'ArmoredAdvance -> PincerWindup (0.45s) -> PincerLunge -> ExposedStagger (2.0s) -> Dead',
        ],
        interrupts: const [
          'E01 Claw Dash hit shatters shell immediately and enters ExposedStagger (2.0s)',
          'Bolt impacts on intact shell deal 25% chip damage and emit metallic Niagara sparks',
        ],
        tuning: [
          EpicTuningParam(key: 'ShellHp', value: '60', unit: 'hp'),
          EpicTuningParam(key: 'CoreHp', value: '90', unit: 'hp'),
          EpicTuningParam(key: 'TelegraphDuration', value: '0.45', unit: 's'),
          EpicTuningParam(key: 'StaggerDuration', value: '2.0', unit: 's'),
        ],
        feedback: const [
          'Front dome UMaterialInstanceDynamic shifts slate-grey to magenta on Armor Break',
          'UWidgetComponent floating HP + Armor bar above enemy mesh',
          'Enemy flashes solid white for 0.08 s on exposed core hits',
        ],
        levelStaging:
            '/Game/Maps/Lvl_ShellbreakerProto.umap: 2 placed BP_CrabGrunt actors 1200 cm north of PlayerStart',
        checks: [
          EpicPieCheck(
            id: 'sb_e03_c1',
            text: 'Shoot frontal shell -> reduced chip damage with flash until Claw Dash hits',
          ),
          EpicPieCheck(
            id: 'sb_e03_c2',
            text: 'Dash through crab -> armor shatters into 2.0 s stagger and bursts kill cleanly',
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
                'Pursue player inside arena and commit to a 420 cm forward lunge after a clear 0.45 s crimson telegraph.',
            inScope: const ['420 cm aggro stop distance', '0.45 s crimson warning stripe'],
            doneWhen: const ['Approach crab -> 0.45 s crimson flash warns clearly before lunge'],
            controls: [
              EpicControlBinding(
                action: 'IA_AiLunge',
                trigger: 'AI Behavior (420 cm range)',
                rule: 'Faces player -> telegraphs 0.45 s -> lunges 420 cm',
              ),
            ],
            tuning: [
              EpicTuningParam(key: 'TelegraphDuration', value: '0.45', unit: 's'),
              EpicTuningParam(key: 'LungeRange', value: '420', unit: 'cm'),
            ],
            cues: const ['Glowing red windup telegraph decal strip ahead of pincers'],
            checks: [
              EpicPieCheck(
                id: 'sb_f05_c1',
                text: 'Stand within 420 cm -> crimson telegraph warns 0.45 s before forward lunge',
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
              EpicTuningParam(key: 'ShellHp', value: '60', unit: 'hp'),
              EpicTuningParam(key: 'CoreHp', value: '90', unit: 'hp'),
              EpicTuningParam(key: 'StaggerDuration', value: '2.0', unit: 's'),
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
              'Refund IA_ClawDash cooldown immediately for 0.35 s after shattering an enemy shell.',
          inScope: const ['0.35 s chain grace timer', '1.2x chained dash burst speed'],
          doneWhen: const [
            'Shatter crab shell then tap Space -> Second dash chains immediately with zero wait',
          ],
          controls: [
            EpicControlBinding(
              action: 'IA_ClawDash',
              trigger: 'Started (Space / RMB)',
              rule: 'Bypasses cooldown cleanly during 0.35 s chain window',
            ),
          ],
          tuning: [
            EpicTuningParam(key: 'ChainDashDistance', value: '550', unit: 'cm'),
            EpicTuningParam(key: 'ChainWindowS', value: '0.35', unit: 's'),
            EpicTuningParam(key: 'ChainSpeedMult', value: '1.2', unit: 'x'),
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
            'Spawn escalating 3-wave crab squads from perimeter gates with live WBP HUD wave banner and quick restart flow.',
        inScope: const ['4 perimeter SpawnGate actors', 'UMG Widget wave counter & R quick reset'],
        doneWhen: const ['Clear 3 waves -> Victory banner shows cleanly and R restarts in < 0.2 s'],
        sceneOwnership: [
          EpicSceneOwnership(
            path: '/Game/Blueprints/BP_WaveDirector',
            role: '3-wave squad timer, HUD counter & arena reset',
          ),
        ],
        links: const [
          'Spawns /Game/Blueprints/BP_CrabGrunt (E03) at 4 perimeter SpawnGate TargetPoints',
          'Updates WBP_ArenaHud wave label and remaining enemy counter',
        ],
        outOfScope: const [
          'No endless wave scaling past Wave 3',
          'No boss cutscenes',
        ],
        controls: [
          EpicControlBinding(
            action: 'IA_QuickRestart',
            trigger: 'Started (R on Clear)',
            rule: 'Resets player HP/pos and restarts Wave 1 cleanly in < 0.2 s',
          ),
        ],
        states: const [
          'WaveIntro (1.2s) -> WaveCombat -> WaveClear (2.0s breather) -> ArenaVictory',
        ],
        interrupts: const [
          'Player HP <= 0 transitions directly to ArenaDefeat UMG Widget and stops active spawn timers',
        ],
        tuning: [
          EpicTuningParam(key: 'Wave1Count', value: '3', unit: 'count'),
          EpicTuningParam(key: 'Wave3Count', value: '7', unit: 'count'),
          EpicTuningParam(key: 'BreatherSeconds', value: '2.0', unit: 's'),
        ],
        feedback: const [
          'Perimeter floor pad pulses cyan 1.0 s before spawning each grunt',
          'Top-center WBP HUD Wave pill animates scale punch on wave transitions',
        ],
        levelStaging:
            '/Game/Maps/Lvl_ShellbreakerProto.umap: 4 SpawnGate TargetPoint actors along N/E/S/W walls',
        checks: [
          EpicPieCheck(
            id: 'sb_e04_c1',
            text: 'Kill all Wave 1 crabs -> 2.0 s breather plays and Wave 2 spawns from lit gates',
          ),
          EpicPieCheck(
            id: 'sb_e04_c2',
            text: 'Press R after ArenaVictory -> resets arena immediately with 0 stale actors',
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
              EpicTuningParam(key: 'Wave1Count', value: '3', unit: 'count'),
              EpicTuningParam(key: 'BreatherSeconds', value: '2.0', unit: 's'),
            ],
            checks: [
              EpicPieCheck(
                id: 'sb_e04_f01_c1',
                text: 'Clear Wave 1 -> 2.0 s breather plays and Wave 2 spawns from lit gates',
              ),
            ],
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
            path: '/Game/Blueprints/BP_ShellGuardComponent',
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
            action: 'IA_ShellGuard',
            trigger: 'Started (Shift / Q)',
            rule: 'Opens 0.25 s parry window; successful reflect staggers attacker 2.2 s',
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
          'Cyan arc shield UStaticMeshComponent flashes front 120 deg cone during GuardWindow',
        ],
        levelStaging:
            '/Game/Maps/Lvl_ShellbreakerProto.umap: test directly against E03 Crab lunge telegraph',
        checks: [
          EpicPieCheck(
            id: 'sb_e05_c1',
            text: 'Press Q during crimson crab windup -> attacker stops and enters 2.2 s stagger',
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
              EpicTuningParam(key: 'ParryWindow', value: '0.25', unit: 's'),
              EpicTuningParam(key: 'ParryStagger', value: '2.2', unit: 's'),
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
