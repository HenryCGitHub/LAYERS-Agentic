import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/agents/project_concept_agent.dart';
import 'package:layers_agentic/agents/release_planner_agent.dart';
import 'package:layers_agentic/constants/tiers.dart';
import 'package:layers_agentic/main.dart';
import 'package:layers_agentic/models/agent_blueprints.dart';
import 'package:layers_agentic/models/feature_state.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/project_pitch_screen.dart';

Future<Map<String, dynamic>?> _mockGeminiResponder(
  String prompt,
  String preferredModel,
) async {
  // 1. Stage 1A: refreshSparkExpansionCards
  if (prompt.contains('proposing 3 NEW gameplay expansion / twist cards')) {
    final titleMatch =
        RegExp(r'Working Title: "([^"]+)"').firstMatch(prompt);
    final wTitle = titleMatch?.group(1) ?? 'Game Concept';
    return {
      'expansionCards': [
        {
          'badge': '01 · CORE MECHANIC TWIST',
          'title': 'Chain Combo Surge',
          'description': 'Chain rapid actions inside $wTitle for a speed boost.',
          'additionSummary': 'chain combo surge for $wTitle',
        },
        {
          'badge': '02 · RISK / REWARD HOOK',
          'title': 'Overcharge Gamble',
          'description': 'Risk overcharging in $wTitle for double payout.',
          'additionSummary': 'overcharge gamble in $wTitle',
        },
        {
          'badge': '03 · LOOP PAYOFF & UPGRADE',
          'title': 'Mastery Relic Slot',
          'description': 'Unlock a relic slot between $wTitle runs.',
          'additionSummary': 'mastery relic slot for $wTitle',
        },
      ],
    };
  }

  // 2. Stage 1A: ingestOrRefineSparkIdea
  if (prompt.contains(
    'summarizing a developer\'s game idea before building the blueprint',
  )) {
    if (prompt.contains('rename to Metro Runner')) {
      return {
        'workingTitle': 'Metro Runner',
        'baseSummary':
            'Retrieve and deliver vital cargo across a ruined metropolis using fluid parkour while evading patrol drones.',
        'mechanics': [
          'Fluid Parkour & Wall-Running',
          'Cargo Haul Protection',
          'Patrol Drones',
        ],
        'expansionCards': [
          {
            'badge': '01 · CORE MECHANIC TWIST',
            'title': 'Momentum Slide & Rooftop Kick',
            'description': 'Slide under obstacles and kick off ledges.',
            'additionSummary': 'momentum slide and rooftop kick',
          },
          {
            'badge': '02 · RISK / REWARD HOOK',
            'title': 'Heavy Crate Overhaul',
            'description': 'Carry extra crates for bonus payout.',
            'additionSummary': 'heavy crate overhaul',
          },
          {
            'badge': '03 · LOOP PAYOFF & UPGRADE',
            'title': 'Grapple Rig Tuning',
            'description': 'Upgrade rig speed between deliveries.',
            'additionSummary': 'grapple rig tuning',
          },
        ],
      };
    }
    if (prompt.contains('instead of scavengers use patrol drones')) {
      return {
        'workingTitle': 'Metropolis Cargo Parkour',
        'baseSummary':
            'Retrieve and deliver vital cargo across a ruined metropolis using fluid parkour while evading patrol drones.',
        'mechanics': [
          'Fluid Parkour & Wall-Running',
          'Cargo Haul Protection',
          'Patrol Drones',
        ],
        'expansionCards': [
          {
            'badge': '01 · CORE MECHANIC TWIST',
            'title': 'Momentum Slide & Rooftop Kick',
            'description': 'Slide under obstacles and kick off ledges.',
            'additionSummary': 'momentum slide and rooftop kick',
          },
          {
            'badge': '02 · RISK / REWARD HOOK',
            'title': 'EMP Drone Jammer',
            'description': 'Disable nearby patrol drones briefly.',
            'additionSummary': 'EMP drone jammer',
          },
          {
            'badge': '03 · LOOP PAYOFF & UPGRADE',
            'title': 'Exo-Boot Thrusters',
            'description': 'Boost wall-run distance.',
            'additionSummary': 'exo-boot thrusters',
          },
        ],
      };
    }
    if (prompt.contains('Selected Idea Additions to Fold In: Wall-Run Chain & Vault Boost')) {
      return {
        'workingTitle': 'Metropolis Cargo Parkour',
        'baseSummary':
            'Retrieve and deliver vital cargo across a ruined metropolis using fluid parkour, wall-run chain and rooftop vault speed boost.',
        'mechanics': [
          'Fluid Parkour & Wall-Running',
          'Cargo Haul Protection',
          'Wall-Run Chain & Vault Boost',
        ],
        'expansionCards': [
          {
            'badge': '01 · CORE MECHANIC TWIST',
            'title': 'Momentum Slide & Rooftop Kick',
            'description': 'Slide under obstacles and kick off ledges.',
            'additionSummary': 'momentum slide and rooftop kick',
          },
          {
            'badge': '02 · RISK / REWARD HOOK',
            'title': 'Heavy Crate Overhaul',
            'description': 'Carry extra crates for bonus payout.',
            'additionSummary': 'heavy crate overhaul',
          },
          {
            'badge': '03 · LOOP PAYOFF & UPGRADE',
            'title': 'Safe-House Shortcut',
            'description': 'Unlock rooftop shortcuts.',
            'additionSummary': 'safe-house shortcut',
          },
        ],
      };
    }
    if (prompt.contains('Brave areas too lethal')) {
      return {
        'workingTitle': 'Metropolis Cargo Parkour',
        'baseSummary':
            'Navigate a ruined metropolis using fluid parkour and high-speed combat to deliver vital cargo through scavenger ambushes.',
        'mechanics': [
          'Fluid Parkour & Wall-Running',
          'Cargo Haul Protection',
          'Scavenger Ambush Defense',
        ],
        'expansionCards': [
          {
            'badge': '01 · CORE MECHANIC TWIST',
            'title': 'Wall-Run Chain & Vault Boost',
            'description': 'Chain wall-runs into rooftop vault speed boosts.',
            'additionSummary': 'wall-run chain and rooftop vault speed boost',
          },
          {
            'badge': '02 · RISK / REWARD HOOK',
            'title': 'Fragile High-Value Cargo',
            'description': 'Deliver fragile cargo without taking hits.',
            'additionSummary': 'fragile high-value cargo',
          },
          {
            'badge': '03 · LOOP PAYOFF & UPGRADE',
            'title': 'Runner Rig Upgrades',
            'description': 'Spend delivery credits on parkour gear.',
            'additionSummary': 'runner rig upgrades',
          },
        ],
      };
    }
    if (prompt.contains('supply courier') ||
        prompt.contains('staying longer in the zone')) {
      return {
        'workingTitle': 'Settlement Supply Courier',
        'baseSummary':
            'Travel from settlement to settlement as an armed supply courier, clearing enemy zones and searching hidden caches for extra credits.',
        'mechanics': [
          'Settlement Route Delivery',
          'Zone Combat & Cache Search',
          'Item Quest Extraction',
        ],
        'expansionCards': [
          {
            'badge': '01 · CORE MECHANIC TWIST',
            'title': 'Cache Signal Scanner',
            'description': 'Ping nearby hidden supply caches.',
            'additionSummary': 'cache signal scanner',
          },
          {
            'badge': '02 · RISK / REWARD HOOK',
            'title': 'Overtime Zone Bounty',
            'description': 'Stay longer in hostile zones for higher credit bounties.',
            'additionSummary': 'overtime zone bounty',
          },
          {
            'badge': '03 · LOOP PAYOFF & UPGRADE',
            'title': 'Settlement Caravan Upgrades',
            'description': 'Upgrade courier armor and weapon slots.',
            'additionSummary': 'settlement caravan upgrades',
          },
        ],
      };
    }
    if (prompt.contains('pizza alchemy')) {
      return {
        'workingTitle': 'Cozy Pizza Alchemy',
        'baseSummary':
            'Brew magical toppings and bake custom pizzas for hungry night-shift monsters.',
        'mechanics': [
          'Dough Toss & Oven Timing',
          'Potion Topping Brew',
          'Monster Order Rush',
        ],
        'expansionCards': [
          {
            'badge': '01 · CORE MECHANIC TWIST',
            'title': 'Enchanted Oven Flame',
            'description': 'Control magical oven heat in Cozy Pizza Alchemy.',
            'additionSummary': 'enchanted oven flame',
          },
          {
            'badge': '02 · RISK / REWARD HOOK',
            'title': 'Spicy Cauldron Rush',
            'description': 'Double-brew volatile toppings in Cozy Pizza Alchemy.',
            'additionSummary': 'spicy cauldron rush',
          },
          {
            'badge': '03 · LOOP PAYOFF & UPGRADE',
            'title': 'Kitchen Familiar Helpers',
            'description': 'Recruit imp helpers in Cozy Pizza Alchemy.',
            'additionSummary': 'kitchen familiar helpers',
          },
        ],
      };
    }
    final hasWallRun = prompt.contains('wall-run chains');
    return {
      'workingTitle': 'Grapple Parkour Roguelite',
      'baseSummary':
          'Swing across floating ruins using a grappling hook${hasWallRun ? " and wall-run chains" : ""} in a fast action roguelite loop.',
      'mechanics': [
        'Grappling Hook Swing',
        if (hasWallRun) 'Wall-Run Chains' else 'Aerial Dash Boost',
        'Arena Wave Clear',
      ],
      'expansionCards': [
        {
          'badge': '01 · CORE MECHANIC TWIST',
          'title': 'Grapple Release Boost',
          'description': 'Release hook at peak swing for a burst of speed.',
          'additionSummary': 'grapple release boost',
        },
        {
          'badge': '02 · RISK / REWARD HOOK',
          'title': 'High-Altitude Combo Multiplier',
          'description': 'Stay airborne to multiply combat rewards.',
          'additionSummary': 'high-altitude combo multiplier',
        },
        {
          'badge': '03 · LOOP PAYOFF & UPGRADE',
          'title': 'Hook Mod Workbench',
          'description': 'Slot elemental tether mods between runs.',
          'additionSummary': 'hook mod workbench',
        },
      ],
    };
  }

  // 3. Stage 1A: extractConceptFromGdd
  if (prompt.contains('# Solar Skiff Salvage')) {
    return {
      'title': 'Solar Skiff Salvage',
      'goal':
          'Core Skiff Loop: Build a fast 3D hover-skiff salvage and grapple loop in Unity 6.',
      'gameSpec': [
        '3D Third-Person',
        'Gamepad + Mouse/KB',
        'Singleplayer',
        'Open Salvage Zone',
      ],
      'techSpec': [
        'Unity 6 (C#)',
        'PC Desktop',
        '3D Low-Poly Meshes',
        'Offline Local Save',
      ],
      'designPillars': [
        'High-Speed Skiff Momentum: Skiff drifting feels responsive on every turn',
        'Readable Hazard Telegraphs: Sandstorms and debris are clear at a glance',
        'Tactile Winch Tension: Towing heavy scrap visibly pulls the skiff hull',
      ],
      'tradeOffs': [
        'Arcade Skiff Handling: Responsive arcade hover physics over realistic aero simulation',
        'Instant Winch Latch: Fast grapple attachment over manual rope aiming',
      ],
      'coreLoopBeats': [
        'Skiff Launch & Boost: Launch hover-skiff into the salvage zone',
        'Grapple & Tow Salvage: Latch onto scrap and tow to the barge',
        'Hazard Evasion: Dodge storm hazards while towing',
        'Dock & Reset: Dock at the barge, bank scrap, and start next run',
      ],
      'exclusions': [
        'No online multiplayer',
        'No on-foot interior exploration',
      ],
      'doneWhen':
          'Playtester completes 3 consecutive salvage runs and docks without clipping.',
      'releaseTrainTitles': [
        'v0.1: Solar Skiff Salvage Core Loop - Prototype',
      ],
    };
  }

  // 4. Stage 1B: regenerateSectionOptionsWithAi
  if (prompt.contains('generating 3 fresh Option Cards for the')) {
    return {
      'options': [
        'Speed & Precision Core (1): Build a responsive greybox loop focused on core controls and immediate feedback.',
        'High-Tension Risk/Reward (1): Build a compact play space where bold decisions multiply rewards.',
        'Tactile Sandbox Toy (1): Build a physics-driven testbed where core movement feels fun first.',
      ],
    };
  }

  // 5. Stage 1B: sendConceptChatTurn
  if (prompt.contains('updating a Live Concept Blueprint')) {
    if (prompt.contains('instead of a crab')) {
      return {
        'reply': 'Switched protagonist and core loop to armored vehicles.',
        'updatedFields': ['Title', 'Goal', 'Core Loop'],
        'title': 'Vehicle Arena Boomer Shooter',
        'goal':
            'Vehicle Arena Loop: Build a playable Vehicle Arena Boomer Shooter prototype where you drive armored vehicles, drift around hazards, and clear enemy waves.',
        'coreLoopBeats': [
          'Vehicle Drift & Boost: Drive armored vehicles and drift across the arena',
          'Mounted Turret Combat: Fire vehicle weapons at incoming enemy waves',
          'Scrap & Chassis Upgrade: Collect scrap drops and pick 1 vehicle mod',
          'Wave Clear & Reset: Clear the arena wave and reset for the next round',
        ],
      };
    }
    return {
      'reply': 'Updated Concept Blueprint to 2D Side-Scrolling Precision Platformer.',
      'updatedFields': ['Goal'],
      'goal':
          '2D Side-Scrolling Precision Platformer: Build a responsive 2D Side-Scrolling Precision Platformer prototype with grappling hook swing and wall-run chains.',
    };
  }

  // 6. Stage 1B: startConceptInterview
  if (prompt.contains('creating a Stage 1 Concept Blueprint for this spark idea:')) {
    final isFarm = prompt.toLowerCase().contains('cozy alchemy shop');
    final isCourier = prompt.toLowerCase().contains('supply courier');
    return {
      'title': isFarm
          ? 'Cozy Alchemy Shop'
          : (isCourier ? 'Settlement Supply Courier' : 'Grapple Parkour Roguelite'),
      'goal': isFarm
          ? 'Core Shop & Garden Loop: Build a playable Cozy Alchemy Shop prototype where you harvest herbs, brew potions, and sell to customers.'
          : 'Core Grapple Loop: Build a playable Grapple Parkour Roguelite prototype where you swing across arena gaps, clear enemy waves, and reset cleanly.',
      'gameSpec': [
        '2D Top-Down',
        'Twin-Stick (WASD + Mouse Aim)',
        'Singleplayer',
        'Single-Screen Arena',
      ],
      'techSpec': [
        'Godot 4 (2D)',
        'PC Desktop',
        '2D Sprites + Particles',
        'Offline Local Save',
      ],
      'designPillars': [
        'Unbroken Momentum: Prioritize continuous movement velocity and readable telegraphs',
        'Tactical Positioning: Prioritize deliberate positioning and high-clarity feedback',
        'Chain-Reaction Mastery: Prioritize fast chain-reactions and rewarding loop mastery',
      ],
      'tradeOffs': isFarm
          ? [
              'Instant Cauldron Craft: Instant recipe crafting over waiting on real-time timers',
              'Clear Price Signals: Transparent customer haggling over hidden RNG math',
            ]
          : [
              'Instant Input Response: Instant arcade input response over realistic physics inertia',
              'Greybox Readability: Clean greybox readability over heavy visual shaders in v0.1',
            ],
      'coreLoopBeats': [
        'Arena Entry & Traversal: Enter the arena, dash across hazards, and chain grapple swings',
        'Primary Action & Targets: Engage reactive targets with primary weapon fire',
        'Hazard & Counter Response: Dodge telegraphed attacks and counter-strike',
        'Resource & Drop Pickup: Collect dropped energy shards from cleared targets',
        'Mid-Run Upgrade Choice: Pick 1 of 3 active modifiers from the reward cache',
        'Loop Resolution & Reset: Clear the final wave, tally score, and reset the arena',
        'Staging & Loadout Prep: Select starting weapon and dash module in the staging zone',
      ],
      'exclusions': isFarm
          ? [
              'No combat dungeons in v0.1',
              'No town romance relationship trees',
            ]
          : [
              'Cut multi-branch skill trees and online co-op from v0.1',
              'Defer multi-phase bosses and deep crafting until MVP',
            ],
      'doneWhen':
          'Playtester spawns in, executes every core loop beat from start to finish, and resets the arena cleanly.',
      'releaseTrainTitles': [
        'v0.1: Core Movement & Game Loop - Prototype',
      ],
      'sectionOptions': {
        'goal': [
          'Single-Arena Loop: Focus v0.1 strictly on the core gameplay loop in a single test arena',
          'Prep + Arena Loop: Include an interactive prep & staging zone before entering the active loop in v0.1',
          'Controls & Feel First: Focus v0.1 on primary player controls and core mechanic feel first',
        ],
        'gameSpec': [
          '2D Top-Down · Twin-Stick (WASD + Mouse Aim) · Singleplayer · Single-Screen Arena',
          '2D Side-Scrolling · Precision Controls · Singleplayer · Multi-Room Stages',
          '3D First-Person · Mouse + WASD · Singleplayer · Enclosed Sandbox',
        ],
        'techSpec': [
          'Godot 4 (2D) · PC Desktop · 2D Sprites + Particles · Offline Local Save',
          'Unity 6 · PC & Steam Deck · 2D/3D Hybrid Pipeline · Steam Cloud Save',
          'Unreal Engine 5 · PC Desktop · 3D Greybox Meshes · Offline Local Save',
        ],
        'designPillars': [
          'Unbroken Momentum: Prioritize continuous movement velocity and readable telegraphs',
          'Tactical Positioning: Prioritize deliberate positioning and high-clarity feedback',
          'Chain-Reaction Mastery: Prioritize fast chain-reactions and rewarding loop mastery',
        ],
        'tradeOffs': isFarm
            ? [
                'Instant Cauldron Craft: Instant recipe crafting over waiting on real-time timers',
                'Clear Price Signals: Transparent customer haggling over hidden RNG math',
                'Compact Shop Layout: Single-screen shop layout over sprawling town map',
              ]
            : [
                'Instant Input Response: Instant arcade input response over realistic physics inertia',
                'Animation Commitment: Deliberate animation commitment over instant cancelable movement',
                'Greybox Readability: Clean greybox readability over heavy visual shaders in v0.1',
              ],
        'coreLoop': [
          'Complete 4-Beat Loop: Staging & Prep → Active Gameplay Beats → Resource & Upgrade Choice → Loop Resolution & Reset',
          'Direct Action Loop: Immediate Entry → Core Mechanic Escalation → Target Objective → Score / Loot Tally → Instant Reset',
          'Skill Mastery Loop: Setup & Positioning → Primary Skill Execution → Hazard / Counter Response → Reward Payout → Next Round',
        ],
        'exclusions': isFarm
            ? [
                'Cut Combat Dungeons: Cut combat dungeons and boss fights from Prototype',
                'Defer Romance Trees: Defer NPC romance and seasonal festivals until MVP',
                'Defer Online Trade: Defer player-to-player market trading until Full Production',
              ]
            : [
                'Cut Trees, Co-Op & Story: Cut multi-branch skill trees, online co-op, and story cutscenes from Prototype',
                'Defer Bosses & Crafting: Defer multi-phase bosses and deep inventory crafting until MVP releases',
                'Defer Meta-Save & Audio: Defer persistent meta-progression saves and audio settings until MVP',
              ],
        'doneWhen': [
          'All Beats & Clean Reset: Playtester spawns in, executes every core loop beat from start to finish, and resets the arena cleanly',
          '3 Consecutive Runs: Playtester completes 3 back-to-back loop cycles with clear win/fail resolution and zero soft-locks',
          'No-Explain Playtest: A playtester picks up the controls, reads the primary objective from on-screen cues alone, and completes a full round',
        ],
        'prototypeRelease': [
          'Single v0.1 Greybox: Single Greybox Prototype (v0.1) proving all Core Loop Beats work together',
          'Two-Step v0.1 → v0.2: v0.1 Controls & Primary Mechanics → v0.2 Full Core Loop & Reset',
        ],
      },
    };
  }

  // 7. Stage 2: sendReleasePlanChatTurn
  if (prompt.contains('Antigravity Release Planner Agent updating')) {
    if (prompt.contains('Add Ore Smelting Furnace to Beat 2')) {
      return {
        'reply': 'Added Ore Smelting Furnace to Beat 2.',
        'goal': 'Build v0.1 prototype loop.',
        'doneWhen': 'Playtester completes loop 3 times.',
        'explicitExclusions': ['No online co-op'],
        'beats': [
          {
            'id': 'beat_2',
            'title': 'Primary Action & Targets',
            'goal': 'Engage reactive targets and smelt ore.',
            'doneWhen': 'Targets cleared and ore smelted.',
            'features': [
              {
                'id': 'feat_2_1',
                'title': 'Target Combat',
                'goal': 'Build target combat.',
                'doneWhen': 'Targets defeated.',
                'estimatedHours': 4,
                'included': true,
                'lifecycle': 'new',
                'inScope': ['Target hit detection'],
                'outOfScope': ['Boss phases'],
                'tuningParams': ['fireRate: 4.0 shots/s'],
                'edgeCases': ['[HIT GUARD] Ignore dead targets'],
                'checkpoints': [
                  {
                    'title': 'Target Hit Detection',
                    'playtestCriteria': 'Fire at target -> target takes damage',
                    'tasks': ['Hitbox Setup (2h)', 'Damage State (2h)'],
                  },
                ],
              },
              {
                'id': 'feat_2_2',
                'title': 'Ore Smelting Furnace',
                'goal': 'Build ore smelting furnace economy loop.',
                'doneWhen': 'Player smelts ore into ingots.',
                'estimatedHours': 4,
                'included': true,
                'lifecycle': 'new',
                'inScope': ['Ore input', 'Ingot output'],
                'outOfScope': ['Multi-tier alloys'],
                'tuningParams': ['transactionCostBase: 25 gold'],
                'edgeCases': ['[OVERFLOW GUARD] Cap furnace queue at 5'],
                'checkpoints': [
                  {
                    'title': 'Furnace Deposit & Smelt',
                    'playtestCriteria': 'Deposit ore -> smelt timer runs',
                    'tasks': ['Furnace Actor (2h)', 'Smelt Timer (2h)'],
                  },
                  {
                    'title': 'Ingot Payout & UI',
                    'playtestCriteria': 'Timer finishes -> ingot spawns',
                    'tasks': ['Ingot Spawn (2h)'],
                  },
                ],
              },
            ],
          },
        ],
      };
    }
    return {
      'reply': 'Updated release plan.',
      'goal': 'Updated release goal.',
      'doneWhen': 'Updated done when.',
      'explicitExclusions': ['No online co-op'],
      'beats': [],
    };
  }

  // 8. Stage 2: ReleasePlannerAgent.planRelease
  if (prompt.contains('planning Release:')) {
    final isPart1 = prompt.contains('PHASE 1 SPLIT PROTOTYPE (PART 1 OF 2');
    final isPart2 = prompt.contains('Prototype — Part 2');
    final isMvp = prompt.contains('PHASE 2 PER-EPIC MVP RELEASE (TARGET: EPIC ') &&
        !prompt.contains('Grapple Momentum Release');
    final isVerticalSlice = prompt.contains('PHASE 3 VERTICAL SLICE');
    final isFullProd = prompt.contains('PHASE 4 FULL PRODUCTION');
    final isFirstRelease = prompt.contains('First Release (v0.1): No prior features exist yet.');

    if (isPart1 || isPart2 || isMvp || isVerticalSlice || isFullProd) {
      final fourBeatTitles = [
        'Staging & Loadout Prep',
        'Arena Entry & Traversal',
        'Combat & Wave Escalation',
        'Loot & Round Reset',
      ];
      final count = isPart1 ? 2 : 4;
      int targetMvpIdx = 0;
      if (isMvp) {
        final m = RegExp(r'TARGET: EPIC (\d+) ONLY').firstMatch(prompt);
        if (m != null) {
          targetMvpIdx = (int.tryParse(m.group(1)!) ?? 1) - 1;
        }
      }

      final beats = <Map<String, dynamic>>[];
      for (int i = 0; i < count; i++) {
        String lifecycle = 'new';
        String cpTitle = '${fourBeatTitles[i]} Core';
        if (isPart2) {
          lifecycle = i < 2 ? 'stable' : 'new';
        } else if (isMvp) {
          lifecycle = i == targetMvpIdx ? 'upgrade' : 'stable';
          cpTitle = 'MVP ${fourBeatTitles[i]} Upgrade';
        } else if (isVerticalSlice) {
          lifecycle = 'upgrade';
          cpTitle = 'Visual, Audio & Feel Polish';
        } else if (isFullProd) {
          lifecycle = 'upgrade';
          cpTitle = 'Content Roster & Progression Scaling';
        }

        final feats = <Map<String, dynamic>>[
          {
            'id': 'feat_${i + 1}_1',
            'title': '${fourBeatTitles[i]} Mechanics & Controls',
            'goal': 'Build ${fourBeatTitles[i]} mechanics.',
            'doneWhen': '${fourBeatTitles[i]} works in playtest.',
            'estimatedHours': lifecycle == 'stable' ? 0 : 4,
            'included': true,
            'lifecycle': lifecycle,
            'inScope': ['${fourBeatTitles[i]} core'],
            'outOfScope': ['Deferred polish'],
            'tuningParams': ['moveSpeed: 240.0 px/s', 'cooldown: 0.4 s'],
            'edgeCases': ['[STATE GUARD] Prevent duplicate trigger'],
            'checkpoints': lifecycle == 'stable'
                ? []
                : [
                    {
                      'title': cpTitle,
                      'playtestCriteria': 'Trigger action -> verify response',
                      'tasks': [
                        'Actor Setup (2h)',
                        'State Logic (1h)',
                        'State Guard (1h)',
                      ],
                    },
                  ],
          },
        ];
        if (isFullProd && i == 0) {
          feats.add({
            'id': 'feat_fp_promoted_1',
            'title': 'Endless Boss Rush Mode',
            'goal': 'Build promoted Endless Boss Rush Mode.',
            'doneWhen': 'Boss rush wave spawns and clears.',
            'estimatedHours': 6,
            'included': true,
            'lifecycle': 'new',
            'inScope': ['Boss wave queue'],
            'outOfScope': [],
            'tuningParams': ['bossWaveInterval: 30.0 s'],
            'edgeCases': ['[SPAWN GUARD] Cap active bosses at 1'],
            'checkpoints': [
              {
                'title': 'Boss Rush Spawner',
                'playtestCriteria': 'Start rush -> boss spawns',
                'tasks': ['Boss Queue (3h)', 'Reward Scaling (3h)'],
              },
            ],
          });
        }
        beats.add({
          'id': 'beat_${i + 1}',
          'title': fourBeatTitles[i],
          'goal': 'Build ${fourBeatTitles[i]}.',
          'doneWhen': '${fourBeatTitles[i]} verified.',
          'features': feats,
        });
      }

      return {
        'goal': 'Build release milestone.',
        'doneWhen': 'Playtester verifies all beats.',
        'explicitExclusions': ['Daily Seeded Leaderboard'],
        'questions': [
          {
            'id': 'rel_q_feel',
            'question': 'What should we prioritize?',
            'options': [
              '(Recommended) Tight Controls: Prioritize movement response',
              'Visual Clarity: Prioritize clear telegraphs',
            ],
          },
        ],
        'beats': beats,
      };
    }

    // Default 7-beat concept (v0.1 or v0.2)
    final sevenBeatTitles = [
      'Arena Entry & Traversal',
      'Primary Action & Targets',
      'Hazard & Counter Response',
      'Resource & Drop Pickup',
      'Mid-Run Upgrade Choice',
      'Loop Resolution & Reset',
      'Staging & Loadout Prep',
    ];
    final beats = <Map<String, dynamic>>[];
    for (int i = 0; i < sevenBeatTitles.length; i++) {
      final bTitle = sevenBeatTitles[i];
      if (isFirstRelease) {
        final feats = <Map<String, dynamic>>[
          {
            'id': 'feat_${i + 1}_1',
            'title': '$bTitle Mechanics & Controls',
            'goal': 'Build $bTitle mechanics and controls.',
            'doneWhen': 'Playtester verifies $bTitle in arena.',
            'estimatedHours': 4,
            'included': true,
            'lifecycle': 'new',
            'inScope': ['$bTitle input', '$bTitle feedback'],
            'outOfScope': ['Advanced skill tree'],
            'tuningParams': ['moveSpeed: 240.0 px/s', 'dashCooldown: 0.4 s'],
            'edgeCases': ['[STATE GUARD] Prevent invalid state transition'],
            'checkpoints': [
              {
                'title': '$bTitle Core',
                'playtestCriteria': 'Press input -> actor responds within 100ms',
                'tasks': [
                  'Actor Setup (2h)',
                  'State Logic (1h)',
                  'State Guard (1h)',
                ],
              },
            ],
          },
        ];
        if (i == 0) {
          feats.add({
            'id': 'feat_1_2',
            'title': 'Grapple Momentum Release',
            'goal': 'Build grapple release speed burst.',
            'doneWhen': 'Releasing grapple boosts velocity.',
            'estimatedHours': 4,
            'included': true,
            'lifecycle': 'new',
            'inScope': ['Release boost'],
            'outOfScope': ['Rope tangling'],
            'tuningParams': ['releaseBoostSpeed: 320.0 px/s'],
            'edgeCases': ['[VELOCITY CLAMP] Cap max release speed'],
            'checkpoints': [
              {
                'title': 'Release Impulse',
                'playtestCriteria': 'Detach mid-swing -> player launches forward',
                'tasks': [
                  'Release Input (2h)',
                  'Impulse Math (1h)',
                  'Speed Clamp (1h)',
                ],
              },
            ],
          });
        }
        beats.add({
          'id': 'beat_${i + 1}',
          'title': bTitle,
          'goal': 'Build $bTitle.',
          'doneWhen': '$bTitle complete.',
          'features': feats,
        });
      } else {
        // v0.2 subsequent release
        final feats = <Map<String, dynamic>>[
          {
            'id': 'feat_${i + 1}_1',
            'title': '$bTitle Mechanics & Controls',
            'goal': 'Upgrade $bTitle mechanics.',
            'doneWhen': '$bTitle v0.2 upgrade verified.',
            'estimatedHours': i == 0 ? 4 : 0,
            'included': true,
            'lifecycle': i == 0 ? 'upgrade' : 'stable',
            'inScope': ['$bTitle v0.2 polish'],
            'outOfScope': [],
            'tuningParams': ['moveSpeed: 260.0 px/s'],
            'edgeCases': ['[STATE GUARD] Preserve momentum on land'],
            'checkpoints': i == 0
                ? [
                    {
                      'title': '$bTitle v0.2 Upgrade',
                      'playtestCriteria': 'Chain movement -> speed bonus active',
                      'tasks': [
                        'Upgrade Logic (2h)',
                        'VFX Hook (2h)',
                      ],
                    },
                  ]
                : [],
          },
        ];
        if (i == 0) {
          feats.add({
            'id': 'feat_1_2',
            'title': 'Grapple Momentum Release',
            'goal': 'Keep Grapple Momentum Release stable.',
            'doneWhen': 'Remains verified.',
            'estimatedHours': 0,
            'included': true,
            'lifecycle': 'stable',
            'inScope': ['Release boost'],
            'outOfScope': [],
            'tuningParams': ['releaseBoostSpeed: 320.0 px/s'],
            'edgeCases': ['[VELOCITY CLAMP] Cap max release speed'],
            'checkpoints': [],
          });
        }
        beats.add({
          'id': 'beat_${i + 1}',
          'title': bTitle,
          'goal': 'Evolve $bTitle for v0.2.',
          'doneWhen': '$bTitle v0.2 complete.',
          'features': feats,
        });
      }
    }

    return {
      'agentReasoning':
          'v0.1 proved core movement and arena entry. Next, we should deepen traversal momentum and combat readability so the core loop rewards skill.',
      'goal': 'Build playable release loop.',
      'doneWhen': 'Playtester completes loop 3 times in a row.',
      'explicitExclusions': [
        'Online Multiplayer Matchmaking',
        'Cutscene Cinematics',
      ],
      'questions': [
        {
          'id': 'rel_q_feel',
          'question': 'What should we prioritize in this release?',
          'options': [
            '(Recommended) Tight Controls: Prioritize movement feel',
            'Combat Readability: Prioritize telegraph clarity',
          ],
        },
      ],
      'beats': beats,
    };
  }

  // 9. Stage 3: Tailor How-To / Stage 3 Co-Pilot Tools / Live Feature AI enrichment
  if (prompt.contains("Developer's Exact Scene / Node / Script Setup:")) {
    return {
      'subSteps': [
        {
          'title': 'STEP 1.1 · ATTACH HOOKRAY & ROPEVISUAL NODES',
          'stepPath': 'Scene Dock → CharacterBody2D → + Add Child Node',
          'instruction':
              'Attach RayCast2D HookRay and Line2D RopeVisual under CharacterBody2D.',
          'codeFormula':
              'CharacterBody2D\n ├─ HookRay (RayCast2D)\n └─ RopeVisual (Line2D)',
          'verifyResult':
              'Confirm HookRay and RopeVisual appear under CharacterBody2D in the Scene Dock.',
        },
        {
          'title': 'STEP 1.2 · WIRE HOOKRAY TARGET & ROPEVISUAL POINTS',
          'stepPath': 'res://scripts/grapple_movement.gd',
          'instruction':
              'Cast HookRay on input and draw RopeVisual to the collision point.',
          'codeFormula':
              'if HookRay.is_colliding():\n    RopeVisual.points = [Vector2.ZERO, to_local(HookRay.get_collision_point())]',
          'verifyResult':
              'Press grapple in Play mode and verify RopeVisual renders to the HookRay hit point.',
        },
        {
          'title': 'STEP 1.3 · GUARD HOOKRAY DETACH ON RELEASE',
          'stepPath': 'res://scripts/grapple_movement.gd',
          'instruction':
              'Clear RopeVisual points when HookRay loses line of sight.',
          'codeFormula':
              'if not HookRay.is_colliding():\n    RopeVisual.clear_points()',
          'verifyResult':
              'Release grapple and confirm RopeVisual clears immediately.',
        },
      ],
    };
  }

  if (prompt.contains('Choose 1 to 3 surgical workspace tool calls to fulfill the directive.')) {
    final activeIdMatch = RegExp(r'Active Feature: "[^"]+" \(id: ([^)]+)\)').firstMatch(prompt);
    final activeId = activeIdMatch?.group(1) ?? 'feat_1_1';
    final sibIdMatch = RegExp(r'Sibling Features in Release: ([^\s]+)').firstMatch(prompt);
    final sibId = sibIdMatch?.group(1) ?? activeId;
    return {
      'reasoning': 'Synchronized tuning parameters across active and coupled sibling features.',
      'toolCalls': [
        {
          'toolName': 'rebalance_tuning_params',
          'targetTitle': 'Active Feature',
          'summary': 'Injected coyote_time_ms and response_window_ms tuning variables',
          'args': {
            'targetFeatureId': activeId,
            'tuningParams': [
              'coyote_time_ms: 110 ms',
              'response_window_ms: 90 ms',
            ],
          },
        },
        {
          'toolName': 'rebalance_tuning_params',
          'targetTitle': 'Sibling Feature',
          'summary': 'Synchronized coupled_sync_window_ms: 90 ms on sibling feature',
          'args': {
            'targetFeatureId': sibId,
            'tuningParams': [
              'coupled_sync_window_ms: 90 ms',
            ],
          },
        },
      ],
    };
  }

  if (prompt.contains('Synthesize concrete, beginner-friendly 3-Area Engine How-To steps')) {
    return null;
  }

  if (prompt.contains('Tailor this newly added Feature')) {
    return {
      'goal': 'Build zipline anchor attach and momentum release mechanics.',
      'doneWhen': 'Player attaches to zipline and detaches cleanly in playtest.',
      'checkpointTitle': 'Zipline Attach & Detach',
      'playtestGate': 'Press interact near zipline -> slide and detach cleanly',
      'tasks': [
        'Zipline Anchor Setup (2h)',
        'Slide Velocity Logic (1h)',
        'Detach Momentum Guard (1h)',
      ],
      'tuningParams': [
        'ziplineSpeed: 320.0 px/s',
        'detachImpulse: 180.0 px/s',
      ],
      'edgeCases': [
        '[DETACH GUARD] Ignore re-attach for 250ms after jump',
      ],
    };
  }

  if (prompt.contains('Rewrite the implementation sub-steps') ||
      prompt.contains('Playtest Root-Cause Debugger')) {
    return null;
  }

  return {};
}

void main() {
  group('LAYERS-Agentic 3-Stage End-to-End Flow Tests', () {
    setUp(() {
      GeminiAgentClient.testMockResponder = _mockGeminiResponder;
    });

    tearDown(() {
      GeminiAgentClient.testMockResponder = null;
    });

    test(
      'Strict Offline Mode: returns null / false and surfaces "App is offline" banner with zero minimal scaffolds when Gemini AI is unreachable',
      () async {
        GeminiAgentClient.testMockResponder = null;
        final offlineProvider = WorkbenchProvider();
        offlineProvider.updateAiConfig(apiKey: '');

        await offlineProvider.ingestOrRefineSparkIdea(
          'High-speed grappling hook parkour roguelite',
        );
        expect(offlineProvider.sparkIntake, isNull);
        expect(offlineProvider.isOffline, isTrue);
        expect(offlineProvider.offlineErrorMessage, contains('App is offline'));

        offlineProvider.clearOfflineError();
        expect(offlineProvider.isOffline, isFalse);

        await offlineProvider.startConceptInterview(
          'High-speed grappling hook parkour roguelite',
        );
        expect(offlineProvider.conceptDraft, isNull);
        expect(offlineProvider.isOffline, isTrue);
        expect(offlineProvider.offlineErrorMessage, contains('App is offline'));
      },
    );

    test('ProjectConceptAgent seeds turn-by-turn chat and updates Live Concept Blueprint on each turn', () async {
      final draft = await ProjectConceptAgent.startConceptInterview(
        'High-speed grappling hook parkour roguelite',
      );
      expect(draft, isNotNull);
      expect(draft!.isInterviewComplete, isTrue);
      expect(draft.lastAgentReply, isNotEmpty);
      expect(draft.coreLoopBeats.length, greaterThanOrEqualTo(6));
      // Impact-First Ordering: Beat 1 starts with Core Toy / Traversal (never pre-match Staging & Loadout Prep)
      expect(draft.coreLoopBeats.first, startsWith('Arena Entry & Traversal:'));
      expect(
        ProjectConceptAgent.sortBeatsByDeveloperImpact([
          'Staging & Loadout Prep: Choose weapon in safe room',
          'Grapple & Wall-Run Traversal: Swing and wall-run across arena gaps',
          'Primary Combat & Wave Clear: Defeat enemy wave',
          'Loop Resolution & Reset: Tally score and restart',
        ]).first,
        startsWith('Grapple & Wall-Run Traversal:'),
      );
      expect(draft.releaseTrainTitles.length, 1);

      // Send a user turn in the chat and verify the Blueprint updates in real time
      final updatedOk = await ProjectConceptAgent.sendConceptChatTurn(
        draft,
        '2D Side-Scrolling Precision Platformer',
      );
      expect(updatedOk, isTrue);
      expect(draft.lastAgentReply, isNotEmpty);
      expect(draft.goal, contains('2D Side-Scrolling Precision Platformer'));
      expect(draft.toFormattedScopeSection(), contains('Goal:'));
      expect(draft.toFormattedScopeSection(), contains('In Scope:'));
      expect(draft.toFormattedScopeSection(), contains('Out of Scope:'));
      expect(draft.toFormattedScopeSection(), contains('Done When:'));

      // Verify sanitizeGoalText strips leaked `[Section 01 Goal]...` wrappers with nested quotes
      const leakedGoal =
          'Build a Crop Defense Shooter prototype focused on "[Section 01 Goal] Update ONLY the Goal section for "Crop Defense Shooter" (Build a 2D Top-Down Arena prototype around Crop Defense Shooter...) to apply this choice: "Core Farm-to-Shooter Sandbox: Build a playable prototype where you plant and harvest crops, sell or load them as ammo, and clear a 3-wave arena run.". Keep all other sections intact and do not repeat this instruction text inside the output field." with responsive controls and clear feedback.';
      expect(
        ProjectConceptBlueprint.sanitizeGoalText(leakedGoal),
        equals(
          'Core Farm-to-Shooter Sandbox: Build a playable prototype where you plant and harvest crops, sell or load them as ammo, and clear a 3-wave arena run.',
        ),
      );

      // Verify conversational replacement ("instead of a crab we use vehicals.") synthesizes a clean Goal, Title, and Core Loop Beats
      final crabDraft = await ProjectConceptAgent.startConceptInterview(
        'Crab champion boomer shooter game',
      );
      expect(crabDraft, isNotNull);
      final vehicleUpdatedOk = await ProjectConceptAgent.sendConceptChatTurn(
        crabDraft!,
        '[Section 01 Goal] instead of a crab we use vehicals.',
      );
      expect(vehicleUpdatedOk, isTrue);
      expect(crabDraft.title, contains('Vehicle'));
      expect(crabDraft.goal, contains('vehicles'));
      expect(crabDraft.goal.toLowerCase(), isNot(contains('instead of a crab')));
      expect(crabDraft.coreLoopBeats.first.toLowerCase(), isNot(contains('instead of a crab')));
    });

    testWidgets(
      'Full 3-Stage Antigravity Flow: Spark -> Concept Interview -> Release Plan Gate -> 60/40 Active Workbench',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final provider = WorkbenchProvider();

        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        // ── Stage 1A: New Project (Interactive AI Idea Intake & Concept Expansion Cards) ──
        expect(find.byKey(const ValueKey('connected_pipeline_track')), findsOneWidget);
        expect(find.text('STEP 1A · NEW PROJECT'), findsOneWidget);
        expect(find.byKey(const ValueKey('ingest_idea_summary_btn')), findsOneWidget);
        // Before entering an initial idea, the Agent summary and 3 expansion cards are hidden
        expect(find.byKey(const ValueKey('agent_idea_summary_card')), findsNothing);
        expect(find.byKey(const ValueKey('spark_card_0')), findsNothing);
        expect(find.byKey(const ValueKey('spark_card_1')), findsNothing);
        expect(find.byKey(const ValueKey('spark_card_2')), findsNothing);
        expect(find.byKey(const ValueKey('shuffle_spark_ideas_btn')), findsNothing);
        expect(find.byKey(const ValueKey('start_concept_interview_btn')), findsNothing);

        // Verify 70-character line wrapping and Shift+Enter line skipping in the pitch input
        const longPitch =
            'A high-speed grappling hook parkour roguelite where players swing across floating ruins and chain aerial combos';
        final wrappedPitch = MaxColumnLineWrapFormatter.wrapTextAtColumn(
          longPitch,
          maxCharsPerLine: 70,
        );
        expect(wrappedPitch.split('\n').length, greaterThan(1));
        for (final line in wrappedPitch.split('\n')) {
          expect(line.length, lessThanOrEqualTo(70));
        }

        await tester.tap(find.byKey(const ValueKey('spark_input_field')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('spark_input_field')),
          longPitch,
        );
        await tester.pump();
        final sparkField = tester.widget<TextField>(
          find.byKey(const ValueKey('spark_input_field')),
        );
        expect(sparkField.maxLines, isNull);
        expect(sparkField.controller!.text, contains('\n'));
        for (final line in sparkField.controller!.text.split('\n')) {
          expect(line.length, lessThanOrEqualTo(70));
        }

        // Verify Shift + Enter skips to a new line instead of submitting
        await tester.enterText(
          find.byKey(const ValueKey('spark_input_field')),
          'High-speed grappling hook',
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(sparkField.controller!.text, equals('High-speed grappling hook\n'));
        expect(find.byKey(const ValueKey('agent_idea_summary_card')), findsNothing);

        // Input a raw game idea and verify the Agent ingests & summarizes it back AND generates the 3 Concept Expansion Cards
        await tester.enterText(
          find.byKey(const ValueKey('spark_input_field')),
          'High-speed grappling hook parkour roguelite',
        );
        await tester.tap(find.byKey(const ValueKey('ingest_idea_summary_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('agent_idea_summary_card')), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_2')), findsOneWidget);
        expect(find.byKey(const ValueKey('shuffle_spark_ideas_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('fast_track_concept_review_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('start_concept_interview_btn')), findsOneWidget);
        expect(find.text('STEP 1A · NEW PROJECT'), findsOneWidget);

        // Use the same input field to refine the Agent's summary
        await tester.enterText(
          find.byKey(const ValueKey('spark_input_field')),
          'Add wall-run chains',
        );
        await tester.tap(find.byKey(const ValueKey('ingest_idea_summary_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('wall-run chains'), findsWidgets);

        // Clicking a Concept Expansion Card toggles it on (adds to summary) without auto-launching Stage 1B,
        // and clicking it a second time unselects it!
        await tester.tap(find.byKey(const ValueKey('spark_card_0')));
        await tester.pumpAndSettle();
        expect(find.text('STEP 1A · NEW PROJECT'), findsOneWidget);
        expect(provider.sparkIntake!.expansionCards.first.isSelected, isTrue);

        await tester.tap(find.byKey(const ValueKey('spark_card_0')));
        await tester.pumpAndSettle();
        expect(provider.sparkIntake!.expansionCards.first.isSelected, isFalse);

        // Explicitly click "Start Concept Blueprint →" to accept and launch Stage 1B (Option A Single-Page Blueprint default)
        await tester.tap(find.byKey(const ValueKey('start_concept_interview_btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('project_blueprint_card')), findsOneWidget);
        // Click Section 01 in the Left Outliner Rail to verify the Focused One-Section-at-a-Time view
        await tester.tap(find.byKey(const ValueKey('step_node_0')));
        await tester.pumpAndSettle();

        // ── Stage 1B: One-Section-at-a-Time Dynamic UI (Sections 01..08) ──
        expect(find.byKey(const ValueKey('top_bar_project_title')), findsOneWidget);
        expect(find.byKey(const ValueKey('project_switcher_dropdown_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('cloud_sync_auth_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('global_export_spec_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('concept_interview_card')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_left_outliner_rail')), findsOneWidget);
        expect(find.byKey(const ValueKey('concept_sticky_bottom_dock')), findsOneWidget);
        expect(find.byKey(const ValueKey('new_spark_reset_btn')), findsOneWidget);
        expect(find.text('+ New Project'), findsOneWidget);
        expect(find.byKey(const ValueKey('agent_option_card_0_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('agent_option_card_0_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('agent_option_card_0_2')), findsOneWidget);
        expect(find.text('SECTION 01 / 08'), findsOneWidget);
        expect(find.text('Goal'), findsWidgets);
        // Verify Option A structured Goal card + 3 Scannable Clause Cards (01, 02, 03)
        expect(find.byKey(const ValueKey('stage1_goal_structured_card')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_goal_clause_card_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_goal_clause_card_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_goal_clause_card_2')), findsOneWidget);

        // Verify clicking a Stage 1B Option Card applies it, and clicking it again unselects it and restores the default Goal
        final initialGoal = provider.conceptDraft!.goal;
        await tester.tap(find.byKey(const ValueKey('agent_option_card_0_1')));
        await tester.pumpAndSettle();
        expect(provider.conceptDraft!.goal, isNot(equals(initialGoal)));
        await tester.tap(find.byKey(const ValueKey('agent_option_card_0_1')));
        await tester.pumpAndSettle();
        expect(provider.conceptDraft!.goal, equals(initialGoal));

        // Step to Section 02 (Game Spec) and verify 2x2 KV grid labels
        await tester.tap(find.byKey(const ValueKey('next_section_btn')));
        await tester.pumpAndSettle();
        expect(find.text('SECTION 02 / 08'), findsOneWidget);
        expect(find.text('CAMERA VIEW'), findsOneWidget);
        expect(find.text('CONTROLS'), findsOneWidget);

        // Step to Section 03 (Tech Spec) and verify 2x2 KV grid labels
        await tester.tap(find.byKey(const ValueKey('next_section_btn')));
        await tester.pumpAndSettle();
        expect(find.text('SECTION 03 / 08'), findsOneWidget);
        expect(find.text('ENGINE'), findsOneWidget);
        expect(find.text('PLATFORM'), findsOneWidget);

        // Step to Section 04 (Design Pillars — plain label, never "Load-Bearing")
        await tester.tap(find.byKey(const ValueKey('next_section_btn')));
        await tester.pumpAndSettle();
        expect(find.text('SECTION 04 / 08'), findsOneWidget);
        expect(find.text('Design Pillars'), findsWidgets);
        expect(find.textContaining('Load-Bearing'), findsNothing);
        // Verify Stage 1 + / ✓ Multi-Select Playing Cards on Section 04
        expect(find.byKey(const ValueKey('multi_select_badge_3')), findsOneWidget);
        expect(find.text('+ Add to Design Pillars'), findsNWidgets(3));
        await tester.tap(find.byKey(const ValueKey('agent_option_card_3_0')));
        await tester.pumpAndSettle();
        expect(find.text('✓ Added to Design Pillars'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('agent_option_card_3_1')));
        await tester.pumpAndSettle();
        expect(find.text('✓ Added to Design Pillars'), findsNWidgets(2));
        expect(
          provider.conceptDraft!.designPillars.join(' '),
          contains('Unbroken Momentum'),
        );
        expect(
          provider.conceptDraft!.designPillars.join(' '),
          contains('Tactical Positioning'),
        );

        // Jump to Step 09: Full Blueprint Review using the prominent bottom dock button
        expect(find.byKey(const ValueKey('skip_to_full_review_btn')), findsOneWidget);
        final synthBtn = find.byKey(const ValueKey('synthesize_concept_btn'));
        await tester.ensureVisible(synthBtn);
        await tester.pumpAndSettle();
        await tester.tap(synthBtn);
        await tester.pumpAndSettle();

        // ── Stage 1C: Step 09 Full Blueprint Review & Progressive Releases ──
        expect(find.byKey(const ValueKey('project_blueprint_card')), findsOneWidget);
        expect(find.byKey(const ValueKey('concept_sticky_bottom_dock')), findsOneWidget);
        expect(find.text('STEP 09 · FINAL BLUEPRINT VERIFICATION'), findsOneWidget);
        expect(find.text('v0.1: Core Movement & Game Loop - Prototype'), findsOneWidget);
        expect(find.text('1. Concept'), findsOneWidget);
        expect(find.text('2. Workbench'), findsOneWidget);
        expect(find.text('2. Release Plan'), findsNothing);

        // Clicking "Approve & Build v0.1 →" builds v0.1 and jumps directly into 2. Workbench (2-Stage Workflow)
        final approveConceptBtn = find.byKey(const ValueKey('approve_concept_plan_release_btn'));
        await tester.ensureVisible(approveConceptBtn);
        await tester.pumpAndSettle();
        await tester.tap(approveConceptBtn);
        await tester.pumpAndSettle();
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);

        // Verify all 7 Stage 1 Core Loop Beats map 1-to-1 into the Release Blueprint (8 included features across 7 beats)
        expect(provider.releaseBlueprint!.beats.length, 7);
        expect(provider.releaseBlueprint!.totalIncludedFeatures, 8);
        expect(provider.releaseBlueprint!.totalDeferredFeatures, 0);
        final firstProposedFeat = provider.releaseBlueprint!.beats.first.features.first;
        expect(firstProposedFeat.checkpoints.first.tasks.length, 3);

        // Verify Singular-Focused Feature Titles & Progressive AI Release button in 2. Workbench
        expect(
          MechanicArchetypeProfile.concreteFeatureTitleForBeat(
            firstProposedFeat.title,
            beatTitle: provider.releaseBlueprint!.beats.first.title,
          ),
          equals('Arena Entry & Traversal Mechanics & Controls'),
        );
        expect(
          find.byKey(const ValueKey('outliner_new_progressive_release_btn')),
          findsOneWidget,
        );

        // ── Stage 2 (Workbench): Active Release Workbench (Left Outliner + Open-Canvas Workspace) ──
        expect(find.text('OUTLINE', skipOffstage: false), findsOneWidget);
        expect(find.byKey(const ValueKey('outline_release_eta_summary')), findsOneWidget);
        final firstBeatId = provider.activeReleaseBeats.first.id;
        expect(find.byKey(ValueKey('rail_beat_$firstBeatId')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage3_active_feature_sheet')), findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_single_col_0')), findsOneWidget);
        expect(find.textContaining('Arena Entry & Traversal Mechanics & Controls'), findsWidgets);

        // The Pinned Active Step Window is always visible at the top of the work area in Single-Panel mode
        final activeFeat0 = provider.selectedFeature!;
        final cp0NodeId = provider.documents[activeFeat0.id]!.subtasks.first.id;
        expect(find.byKey(ValueKey('pinned_active_step_window_$cp0NodeId')), findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_spec_pane_0')), findsOneWidget);

        // Verify clicking Feature 2 in the Left Outline and marking Step 1.1 done preserves focus on Feature 2
        final allFeatsInOrder = <String>[
          for (final b in provider.activeReleaseBeats)
            for (final f in provider.featuresForBeat(b.id)) f.id,
        ];
        final secondFeatId = allFeatsInOrder[1];
        await tester.tap(find.byKey(ValueKey('rail_feat_$secondFeatId')));
        await tester.pumpAndSettle();
        final secondFeat = provider.selectedFeature!;
        expect(secondFeat.id, isNot(equals(activeFeat0.id)));
        final secondCp0NodeId = provider.documents[secondFeat.id]!.subtasks.first.id;
        // Verify Single-Row Outliner Header live Release ETA summary ("12h Left #%")
        expect(find.byKey(const ValueKey('outline_release_eta_summary')), findsOneWidget);

        // Verify Next → starts locked (onTap == null) while Step 1 is unchecked
        final secondTask0Steps =
            provider.documents[secondFeat.id]!.subtasks.first.children.first.children.length;
        final nextBtnBefore = tester.widget<InkWell>(
          find.byKey(ValueKey('next_active_step_btn_$secondCp0NodeId')),
        );
        expect(nextBtnBefore.onTap, isNull);
        expect(find.textContaining('STEP 1 OF $secondTask0Steps · ~'), findsOneWidget);
        expect(find.text('✓ VERIFY BEFORE CHECKING [✓]'), findsOneWidget);
        expect(
          find.byKey(ValueKey('one_click_complete_next_btn_$secondCp0NodeId')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            ValueKey('task_sheet_step_row_${secondCp0NodeId}_0_1'),
          ),
          findsOneWidget,
        );

        // Tap the simple square Checkmark Box [✓] to mark Step 1 done in place and unlock Next →
        final markDoneFinder = find.byKey(
          ValueKey('mark_active_step_done_btn_$secondCp0NodeId'),
        );
        await tester.ensureVisible(markDoneFinder);
        await tester.pumpAndSettle();
        await tester.tap(markDoneFinder);
        await tester.pumpAndSettle();
        expect(provider.selectedFeature!.id, equals(secondFeat.id));
        expect(find.textContaining('STEP 1 OF $secondTask0Steps · ~'), findsOneWidget);
        final nextBtnAfter = tester.widget<InkWell>(
          find.byKey(ValueKey('next_active_step_btn_$secondCp0NodeId')),
        );
        expect(nextBtnAfter.onTap, isNotNull);

        // Tap Next Step → to advance to Step 2
        final nextBtnFinder = find.byKey(
          ValueKey('next_active_step_btn_$secondCp0NodeId'),
        );
        await tester.ensureVisible(nextBtnFinder);
        await tester.pumpAndSettle();
        await tester.tap(nextBtnFinder);
        await tester.pumpAndSettle();
        expect(find.textContaining('STEP 2 OF $secondTask0Steps · ~'), findsOneWidget);

        // Verify clicking the task chevron in the Outliner expands Task 02 for peeking without losing Step 2 in the workspace
        final task1ChevronFinder = find.byKey(
          ValueKey('outline_task_chevron_${secondCp0NodeId}_1'),
        );
        if (task1ChevronFinder.evaluate().isNotEmpty) {
          await tester.tap(task1ChevronFinder);
          await tester.pumpAndSettle();
          expect(find.textContaining('STEP 2 OF $secondTask0Steps · ~'), findsOneWidget);
        }

        // Verify the compact Previous Step (←) button steps back to Step 1
        final prevBtnFinder = find.byKey(
          ValueKey('prev_active_step_btn_$secondCp0NodeId'),
        );
        expect(prevBtnFinder, findsOneWidget);
        await tester.ensureVisible(prevBtnFinder);
        await tester.pumpAndSettle();
        await tester.tap(prevBtnFinder);
        await tester.pumpAndSettle();
        expect(find.textContaining('STEP 1 OF $secondTask0Steps · ~'), findsOneWidget);

        // Verify the Left Outline stops cleanly at the Task level (no duplicate 4th-level step rows)
        expect(
          find.byKey(ValueKey('outline_step_${secondCp0NodeId}_0_0')),
          findsNothing,
        );
        // Uncheck Step 1 via the workspace Checkmark Box [✓] to restore clean state, then select Feature 1
        await tester.ensureVisible(markDoneFinder);
        await tester.pumpAndSettle();
        await tester.tap(markDoneFinder);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('rail_feat_${activeFeat0.id}')));
        await tester.pumpAndSettle();
        expect(provider.selectedFeature!.id, equals(activeFeat0.id));

        // Verify Focus Mode is ON by default in Single-Panel Stage 3
        expect(provider.focusMode, isTrue);

        // Verify 1-Click "Copy" on the active How-To sub-step copies the code formula
        final activeFeat = provider.selectedFeature!;
        final cp0Id = provider.documents[activeFeat.id]!.subtasks.first.id;
        final copyCodeBtn = find.byKey(ValueKey('copy_howto_code_${cp0Id}_0_0'));
        await tester.ensureVisible(copyCodeBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyCodeBtn);
        await tester.pumpAndSettle();

        // Verify 1-Click "⧉ Copy All Code" in the Task Sheet header copies all task code snippets
        final copyAllCodeBtn = find.byKey(ValueKey('copy_all_task_code_btn_${cp0Id}_0'));
        await tester.ensureVisible(copyAllCodeBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyAllCodeBtn);
        await tester.pumpAndSettle();

        // Verify Task-Scoped AI "✦ Tailor" rewrites sub-steps with exact scene/node context directly in Single-Panel mode
        final tailorBtn = find.byKey(ValueKey('tailor_howto_btn_${cp0Id}_0'));
        await tester.ensureVisible(tailorBtn);
        await tester.pumpAndSettle();
        await tester.tap(tailorBtn);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('tailor_howto_context_input')),
          'CharacterBody2D with RayCast2D HookRay and Line2D RopeVisual',
        );
        await tester.tap(find.byKey(const ValueKey('confirm_tailor_howto_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('HookRay'), findsWidgets);
        expect(find.textContaining('RopeVisual'), findsWidgets);

        // Verify Full-Width vs. Half-Width Streamlined Open-Canvas Workbench layout
        expect(
          find.byKey(ValueKey('work_area_step_timeline_$cp0Id')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('task_sheet_feature_goal_$cp0Id')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('step_dropdown_${cp0Id}_0')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('inline_step_copilot_tailor_btn_$cp0Id')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('inline_step_copilot_log_issue_btn_$cp0Id')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('rail_add_feat_to_beat_$firstBeatId')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('workbench_rename_feature_btn_${activeFeat.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('workbench_remove_feature_btn_${activeFeat.id}')),
          findsOneWidget,
        );
        expect(find.textContaining('✓ Verify: '), findsOneWidget);
        expect(find.text('Complete & Next →'), findsOneWidget);

        // Regression: Completing a task group and clicking back onto the completed task never shows a blank workbench
        final completeTask0Btn = find.byKey(
          ValueKey('complete_task_group_${cp0Id}_0'),
        );
        await tester.ensureVisible(completeTask0Btn);
        await tester.pumpAndSettle();
        await tester.tap(completeTask0Btn);
        await tester.pumpAndSettle();
        final task0Header = find.byKey(ValueKey('outline_task_${cp0Id}_0'));
        await tester.tap(task0Header);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('pinned_active_step_window_$cp0Id')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('work_area_step_timeline_$cp0Id')),
          findsOneWidget,
        );
        // Uncheck Task 0 to restore clean state
        await tester.tap(completeTask0Btn);
        await tester.pumpAndSettle();

        // Verify Progressive AI Release Co-Pilot Modal (+ Plan Next Release (v0.2) ✦) enforces the 100% completion gate:
        // 1. Before v0.1 is 100% complete, tapping the button does NOT open the planner
        final newProgRelBtn = find.byKey(
          const ValueKey('outliner_new_progressive_release_btn'),
        );
        await tester.ensureVisible(newProgRelBtn);
        await tester.pumpAndSettle();
        await tester.tap(newProgRelBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('progressive_next_release_modal')),
          findsNothing,
        );

        // 2. Mark all features in v0.1 100% complete to unlock the Progressive Release Interface
        for (final beat in provider.activeReleaseBeats) {
          for (final feat in provider.featuresForBeat(beat.id)) {
            final states = FeatureStateNode.getStatesForDocument(feat);
            for (final cp in states) {
              for (final task in cp.checklist) {
                task.completed = true;
                for (final child in task.children) {
                  child.completed = true;
                }
              }
            }
            provider.updateFeatureStates(feat.id, states);
          }
        }
        await tester.pumpAndSettle();
        expect(provider.isActiveReleaseComplete, isTrue);

        await tester.ensureVisible(newProgRelBtn);
        await tester.pumpAndSettle();
        await tester.tap(newProgRelBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('progressive_next_release_modal')),
          findsOneWidget,
        );
        expect(
          find.textContaining('AGENT ARCHITECTURAL RECOMMENDATION'),
          findsOneWidget,
        );
        expect(
          find.textContaining('DONE WHEN'),
          findsWidgets,
        );
        expect(
          find.byKey(const ValueKey('progressive_preset_chip_0')),
          findsOneWidget,
        );
        // Verify STABLE ✓ prior-release features (like Grapple Momentum Release) are hidden from the active v0.2 scope view
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('progressive_next_release_modal')),
            matching: find.text('Grapple Momentum Release'),
          ),
          findsNothing,
        );
        // Verify interactive tree toggles inside the Progressive Release Interface:
        // - Toggling an existing feature switches between UPGRADE (+4h) and STABLE (0h)
        // - Adding a custom feature appends a + NEW feature to the Beat
        final draftBp = provider.releaseBlueprint!;
        final firstDraftBeat = draftBp.beats.first;
        final firstDraftFeat = firstDraftBeat.features.first;
        final initialLifecycle = firstDraftFeat.lifecycle;
        provider.toggleProposedFeatureUpgradeOrStable(
          firstDraftBeat.id,
          firstDraftFeat.id,
        );
        expect(firstDraftFeat.lifecycle, isNot(equals(initialLifecycle)));
        provider.addCustomFeatureToProposedBeat(
          firstDraftBeat.id,
          'Shield Drone Companion',
        );
        expect(
          firstDraftBeat.features.any(
            (f) =>
                f.title == 'Shield Drone Companion' &&
                f.lifecycle == FeatureLifecycleStatus.newFeature,
          ),
          isTrue,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Restore first feature's Task 0 to incomplete so the half-width step dropdown assertion below remains active
        final activeStates = FeatureStateNode.getStatesForDocument(activeFeat);
        activeStates.first.checklist.first.completed = false;
        for (final c in activeStates.first.checklist.first.children) {
          c.completed = false;
        }
        provider.updateFeatureStates(activeFeat.id, activeStates);
        await tester.pumpAndSettle();

        // Resize to Half-Width (720px) and verify 1-Line Unified Context Bar + Step Dropdown
        tester.view.physicalSize = const Size(720, 900);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('work_area_step_timeline_$cp0Id')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('halfscreen_outliner_trigger_$cp0Id')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('step_dropdown_${cp0Id}_0')),
          findsOneWidget,
        );
      },
    );

    test(
      'Evolving from Release v0.1 to v0.2 preserves STABLE features (0h delta) and appends v0.2 checkpoints to UPGRADE features',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('High-speed grappling hook parkour roguelite');
        expect(provider.conceptDraft!.designPillars, isNotEmpty);
        expect(provider.conceptDraft!.tradeOffs, isNotEmpty);
        expect(provider.conceptDraft!.techSpec, isNotEmpty);

        // Plan & Execute v0.1 (Epics start with 0 pre-deferred features; deferring a feature in Beat 2 verifies automatic carryover into v0.2!)
        await provider.openReleasePlanGate();
        for (final epic in provider.releaseBlueprint!.beats) {
          expect(epic.deferredFeatures, isEmpty);
        }
        final v1RelId = provider.activeRelease!.id;
        final v1Beat2 = provider.releaseBlueprint!.beats[1];
        v1Beat2.features.add(
          ProposedFeatureBlueprint(
            id: 'feat_slide_boost_test',
            title: 'Slide Boost & Cancel',
            goal: 'Build Slide Boost & Cancel inside ${v1Beat2.title}.',
            doneWhen: 'Playtester slides and cancels cleanly.',
            estimatedHours: 4,
            included: true,
            lifecycle: FeatureLifecycleStatus.newFeature,
            originVersion: 'v0.1',
            checkpoints: [
              ProposedCheckpointBlueprint(
                title: 'Slide Boost & Cancel',
                playtestCriteria: 'Slide -> cancel cleanly',
                tasks: const ['Slide Boost (2h)'],
                releaseVersion: 'v0.1',
              ),
            ],
          ),
        );
        final deferredSlideFeat = v1Beat2.features.last;
        provider.toggleProposedFeatureScope(
          v1Beat2.id,
          deferredSlideFeat.id,
          false,
        );
        expect(deferredSlideFeat.included, isFalse);
        await provider.approveAndExecuteReleasePlan();
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);
        expect(provider.releaseBlueprint!.releaseDocId, v1RelId);

        final v1Beats = provider.activeReleaseBeats;
        // All 7 Stage 1 Core Loop Beats carry into Stage 2 & Stage 3!
        expect(v1Beats.length, provider.conceptDraft!.coreLoopBeats.length);
        final v1FirstFeat = provider.featuresForBeat(v1Beats.first.id).first;
        expect(v1FirstFeat.title, 'Arena Entry & Traversal Mechanics & Controls');

        // Advance to v0.2 Plan Gate
        await provider.advanceToNextRelease();
        final v2Blueprint = provider.releaseBlueprint!;
        expect(v2Blueprint.releaseVersionTag, 'v0.2');

        // Verify the feature deferred in v0.1 ("Slide Boost & Cancel") automatically carried over into Beat 2 of v0.2!
        final carriedOverSlide = v2Blueprint.beats[1].features.firstWhere(
          (f) => f.title == 'Slide Boost & Cancel',
        );
        expect(carriedOverSlide.included, isTrue);
        expect(carriedOverSlide.originVersion, 'v0.2');

        // Beat 1 Feature 1 is upgraded (4h delta), Beat 1 Feature 2 is STABLE (0h delta)
        final b1f1 = v2Blueprint.beats[0].features[0];
        final b1f2 = v2Blueprint.beats[0].features[1];
        expect(b1f1.lifecycle.name, 'upgrade');
        expect(b1f1.activeDeltaHours, 4);
        expect(b1f2.lifecycle.name, 'stable');
        expect(b1f2.activeDeltaHours, 0);

        // Execute v0.2 and verify v0.1 checkpoints are preserved + v0.2 checkpoint is appended
        await provider.approveAndExecuteReleasePlan();
        final evolvedFeat = provider.documents[v1FirstFeat.id]!;
        expect(evolvedFeat.sections['lifecycle'], 'upgrade');

        // Regression: When an unbuilt draft release was pruned leaving a skipped version (e.g., 2nd release labeled v0.6),
        // repackProjectReleasesSequentially compacts the 2nd release back to v0.2 and advances cleanly to v0.3 -> v0.4!
        provider.activeRelease!.title = 'v0.6: Room Clearance & Threat Variety';
        provider.activeRelease!.sections['versionTag'] = 'v0.6';
        provider.repackProjectReleasesSequentially(
          provider.activeProject!,
          pruneAllUnbuilt: true,
        );
        expect(provider.activeReleaseVersionTag, 'v0.2');
        expect(
          provider.activeRelease!.title,
          'v0.2: Room Clearance & Threat Variety',
        );
        expect(provider.nextProgressiveVersionLabel, 'v0.3');
        final v3Bp = await provider.prepareProgressiveNextReleaseDraft();
        expect(v3Bp, isNotNull);
        expect(v3Bp!.releaseVersionTag, 'v0.3');
        expect(provider.activeReleaseVersionTag, 'v0.3');
        await provider.approveAndExecuteReleasePlan();
        expect(provider.nextProgressiveVersionLabel, 'v0.4');

        // Verify delta-only JSON output (where LLM returns only Beat 3) reconciles into canonical E01..E0N order
        final liveBeats = provider.activeReleaseBeats;
        final existingFeatsMap = <String, List<TierDocument>>{
          for (final b in liveBeats) b.id: provider.featuresForBeat(b.id),
        };
        final deltaOnlyBp = ReleaseBlueprint(
          releaseDocId: provider.activeRelease!.id,
          releaseTitle: 'v0.4: Delta Subset Test',
          releaseVersionTag: 'v0.4',
          preset: ReleaseScope.mvp,
          goal: 'Verify delta beat reconciliation.',
          doneWhen: 'Canonical order preserved.',
          questions: const [],
          beats: [
            ProposedBeatBlueprint(
              id: liveBeats[2].id,
              title: liveBeats[2].title,
              goal: 'Beat 3 goal',
              doneWhen: 'Beat 3 done',
              features: [
                ProposedFeatureBlueprint(
                  id: 'feat_new_delta_3',
                  title: 'Hazard Trap',
                  goal: 'Add hazard trap.',
                  doneWhen: 'Hazard trap triggers.',
                  estimatedHours: 4,
                  included: true,
                  lifecycle: FeatureLifecycleStatus.newFeature,
                  originVersion: 'v0.4',
                ),
              ],
            ),
          ],
        );
        final reconciled =
            ReleasePlannerAgent.reconcileReleaseBlueprintWithPhaseRules(
          parsed: deltaOnlyBp,
          releaseDoc: provider.activeRelease!,
          preset: ReleaseScope.mvp,
          versionTag: 'v0.4',
          existingBeats: liveBeats,
          existingFeaturesByBeat: existingFeatsMap,
          deferredByBeatIndex: const {},
          projectExclusions: const [],
          allCoreLoopItems: provider.conceptDraft!.coreLoopBeats,
        );
        expect(reconciled.beats.length, liveBeats.length);
        expect(reconciled.beats[0].id, liveBeats[0].id);
        expect(reconciled.beats[1].id, liveBeats[1].id);
        expect(reconciled.beats[2].id, liveBeats[2].id);
        expect(
          reconciled.beats[2].features.any((f) => f.title == 'Hazard Trap'),
          isTrue,
        );

        // Selecting an already-built release (v0.1) in the Stage 3 dropdown switches in-place without kicking back to Stage 2
        await provider.selectActiveRelease(v1RelId);
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);
        expect(provider.activeRelease!.id, v1RelId);

        // Verify per-release ReleaseBlueprint persistence and restoration when switching releases
        final savedV1Bp = provider.releaseBlueprintFor(v1RelId);
        expect(savedV1Bp, isNotNull);
        expect(savedV1Bp!.releaseDocId, v1RelId);
        expect(provider.releaseBlueprint!.releaseDocId, v1RelId);

        // Verify phase classification and descriptive release display names for dropdown grouping
        final allRels = provider.projectReleases;
        expect(allRels.length, 3);
        expect(provider.releasePhaseFor(allRels[0]), ProductionPhase.prototype);
        expect(provider.releasePhaseShortBadge(allRels[0]), 'PROTO');
        expect(
          provider.releaseDisplayName(allRels[0]),
          isNot(equals('Prototype')),
        );
        expect(
          provider.releaseDisplayName(allRels[1]),
          'Room Clearance & Threat Variety',
        );
        // Once all Core Loop Epics are populated and at least 1 MVP release is built, v0.3 advances to Vertical Slice, and the next inferred phase is Full Production
        expect(
          provider.releasePhaseFor(allRels[2]),
          ProductionPhase.verticalSlice,
        );
        expect(
          provider.inferNextProgressivePhase(),
          ProductionPhase.fullProduction,
        );

        // Verify that executing a v0.4 blueprint with a + NEW feature placed before an existing STABLE feature never collides feature IDs or duplicates beatDoc.childrenIds
        final firstEpic = liveBeats.first;
        final existingFeatIdsBefore = List<String>.from(firstEpic.childrenIds);
        expect(
          existingFeatIdsBefore.toSet().length,
          existingFeatIdsBefore.length,
        );
        final v4Reconciled = ReleasePlannerAgent
            .reconcileReleaseBlueprintWithPhaseRules(
              parsed: ReleaseBlueprint(
                releaseDocId: 'rel_v0_4',
                releaseTitle: 'v0.4: Boss & Projectile Pass',
                releaseVersionTag: 'v0.4',
                preset: ReleaseScope.mvp,
                goal: 'Add enemy projectile fire without overwriting v0.1 cards.',
                doneWhen: 'Boss fires projectiles and v0.1 cards remain intact.',
                questions: const [],
                beats: [
                  ProposedBeatBlueprint(
                    id: firstEpic.id,
                    title: firstEpic.title,
                    goal: 'Expand first epic with a new feature at index 0.',
                    doneWhen: 'Both existing and new features exist distinctly.',
                    features: [
                      ProposedFeatureBlueprint(
                        id: 'feat_1',
                        title: 'Enemy Projectile Fire',
                        goal: 'Spawn aimed projectiles from ranged enemies.',
                        doneWhen: 'Projectiles travel and deal damage on hit.',
                        estimatedHours: 6,
                        included: true,
                        lifecycle: FeatureLifecycleStatus.newFeature,
                        originVersion: 'v0.4',
                      ),
                    ],
                  ),
                ],
              ),
              releaseDoc: provider.activeRelease!,
              preset: ReleaseScope.mvp,
              versionTag: 'v0.4',
              existingBeats: liveBeats,
              existingFeaturesByBeat: existingFeatsMap,
              deferredByBeatIndex: const {},
              projectExclusions: const [],
              allCoreLoopItems: provider.conceptDraft!.coreLoopBeats,
            );
        // Existing features stay first, followed by the + NEW feature with a non-colliding ID
        final reconciledBeat = v4Reconciled.beats.first;
        expect(
          reconciledBeat.features.any(
            (f) =>
                f.title == 'Enemy Projectile Fire' &&
                f.lifecycle == FeatureLifecycleStatus.newFeature &&
                !existingFeatIdsBefore.contains(f.id),
          ),
          isTrue,
        );

        // Verify ReleaseBlueprint builtSoFar & missingGaps round-trip serialization
        final diagBp = ReleaseBlueprint(
          releaseDocId: 'rel_diag',
          releaseTitle: 'v0.3: Economy & Crafting Loop',
          releaseVersionTag: 'v0.3',
          preset: ReleaseScope.mvp,
          goal: 'Wire ore drops into crafting bench.',
          doneWhen: 'Player crafts 1 item from looted ore.',
          builtSoFar: const ['Twin-Stick Aiming', 'Shotgun Firing & Reload'],
          missingGaps: const ['E03 · Loot Drops & Pickup (0 features)'],
          questions: const [],
          beats: const [],
        );
        final roundTripBp = ReleaseBlueprint.fromJson(diagBp.toJson());
        expect(roundTripBp.builtSoFar, [
          'Twin-Stick Aiming',
          'Shotgun Firing & Reload',
        ]);
        expect(roundTripBp.missingGaps, [
          'E03 · Loot Drops & Pickup (0 features)',
        ]);
      },
    );

    test(
      'Blueprint JSON serialization & Multi-Project Vault Manager (Switch, Rename, Deep 4-Tier Duplicate, Collaborators, Delete) preserve Stage 1, 2, and 3 state',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('Tactical Mecha Extraction Shooter');
        await provider.openReleasePlanGate();
        await provider.approveAndExecuteReleasePlan();

        final proj1Id = provider.activeProjectId!;
        final origBeatsCount = provider.activeReleaseBeats.length;
        expect(provider.savedProjects.length, 1);
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);

        // Invite collaborator on Project 1
        final invited = await provider.inviteProjectCollaborator(
          collaboratorEmail: 'teammate@studio.dev',
        );
        expect(invited, isTrue);
        expect(
          provider.collaboratorsForProject(proj1Id).map((c) => c['email']),
          contains('teammate@studio.dev'),
        );

        // Rename Project 1
        provider.renameProject(proj1Id, 'Mecha Drop v1');
        expect(provider.documents[proj1Id]!.title, 'Mecha Drop v1');

        // Deep 4-Tier Duplicate Project 1 (Project -> Release -> Beat -> Feature + Checkpoints)
        final dupId = provider.duplicateProject(proj1Id);
        expect(dupId, isNotNull);
        expect(provider.savedProjects.length, 2);
        expect(provider.activeProjectId, dupId);
        expect(provider.documents[dupId!]!.title, 'Mecha Drop v1 (Copy)');
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);
        expect(provider.activeReleaseBeats.length, origBeatsCount);
        expect(
          provider.featuresForBeat(provider.activeReleaseBeats.first.id),
          isNotEmpty,
        );

        // Create a third project via createNewProject()
        provider.createNewProject();
        expect(provider.conceptDraft, isNull);
        expect(provider.currentStage, WorkbenchStage.projectPitch);

        await provider.startConceptInterview('Cozy Alchemy Shop & Dungeon Forager');
        final proj3Id = provider.activeProjectId!;
        expect(provider.savedProjects.length, 3);

        // Delete the duplicated project
        provider.deleteProject(dupId);
        expect(provider.savedProjects.length, 2);

        // Switch back to Project 1 and verify Stage 1, 2, and 3 state restored from JSON metadata
        provider.switchProject(proj1Id);
        expect(provider.activeProjectId, proj1Id);
        expect(provider.conceptDraft!.sparkIdea, 'Tactical Mecha Extraction Shooter');
        expect(provider.releaseBlueprint, isNotNull);
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);
        expect(provider.activeReleaseBeats, isNotEmpty);

        // Delete Project 3
        provider.deleteProject(proj3Id);
        expect(provider.savedProjects.length, 1);
      },
    );

    test(
      'Engine-Aware TaskHowToBlueprint.resolve adapts whereLocation and code formulas for Godot 4, Unity C#, and Unreal 5',
      () {
        final cp = FeatureStateNode(
          id: 'cp_test',
          name: 'Stage 1: Greybox Core Loop',
          trigger: 'Verify movement and dash in arena.',
          tuningParams: const ['move_speed: 240 px/s', 'dash_cooldown: 0.4 s'],
          edgeCases: const ['[GUARD] Ignore dash input while airborne'],
        );

        final godotTask = Subtask(
          id: 't_godot',
          text: 'Bind WASD movement and dash physics velocity',
          completed: false,
        );
        final godotBp = TaskHowToBlueprint.resolve(
          parentTask: godotTask,
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Godot 4.3 GDScript 2D',
        );
        expect(godotBp.engineLabel, 'GODOT 4');
        expect(godotBp.subSteps.length, 6);
        expect(godotBp.whereLocation, contains('_physics_process'));
        expect(godotBp.subSteps[4].codeFormula, contains('Input.is_action_pressed'));
        expect(godotBp.subSteps[4].codeFormula, contains('move_toward'));

        final unityTask = Subtask(
          id: 't_unity',
          text: 'Bind WASD movement and dash physics velocity',
          completed: false,
        );
        final unityBp = TaskHowToBlueprint.resolve(
          parentTask: unityTask,
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Unity 6 C# URP',
        );
        expect(unityBp.engineLabel, 'UNITY C#');
        expect(unityBp.subSteps.length, 6);
        expect(unityBp.whereLocation, contains('MonoBehaviour'));
        expect(unityBp.subSteps[4].codeFormula, contains('Input.GetButton'));
        expect(unityBp.subSteps[4].codeFormula, contains('Time.fixedDeltaTime'));

        final unrealTask = Subtask(
          id: 't_unreal',
          text: 'Bind WASD movement and dash physics velocity',
          completed: false,
        );
        final unrealBp = TaskHowToBlueprint.resolve(
          parentTask: unrealTask,
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
          unrealCppMode: false,
        );
        expect(unrealBp.engineLabel, 'UNREAL 5');
        expect(unrealBp.subSteps.length, 6);
        expect(unrealBp.whereLocation, contains('ActorComponent'));
        expect(unrealBp.subSteps[0].stepPath, contains('/Game/Blueprints/'));
        expect(unrealBp.subSteps[0].codeFormula, contains('EMechanicState::Active'));
        expect(unrealBp.subSteps[0].explainConcept, contains('BP_'));
        expect(unrealBp.subSteps[0].specChips, contains('Next: ${unrealBp.subSteps[1].shortTitle}'));
        expect(unrealBp.subSteps[4].codeFormula, contains('FMath::FInterpConstantTo'));

        final unrealCpp = TaskHowToBlueprint.resolve(
          parentTask: unrealTask,
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
          unrealCppMode: true,
        );
        expect(unrealCpp.engineLabel, 'UNREAL 5');
        expect(unrealCpp.whereLocation, contains('ActorComponent'));
        expect(unrealCpp.subSteps[0].explainConcept, contains('AWasdMovementDash'));
        expect(unrealCpp.subSteps[3].codeFormula, contains('UPROPERTY(EditAnywhere'));
        expect(unrealCpp.subSteps[4].codeFormula, contains('FMath::FInterpConstantTo'));

        // Verify Task 01 (Setup), Task 02 (State Logic), and Task 03 (Input/Raycast) have non-repeating step titles
        final t0 = TaskHowToBlueprint.resolve(
          parentTask: Subtask(id: 't0', text: 'Create Grid Tile Actor (2h)'),
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
        );
        final t1 = TaskHowToBlueprint.resolve(
          parentTask: Subtask(id: 't1', text: 'Implement State Machine (4h)'),
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
        );
        final t2 = TaskHowToBlueprint.resolve(
          parentTask: Subtask(id: 't2', text: 'Add Interaction Raycast (2h)'),
          taskIndex: 2,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
        );
        expect(t0.subSteps[0].shortTitle, isNot(equals(t1.subSteps[0].shortTitle)));
        expect(t1.subSteps[0].shortTitle, isNot(equals(t2.subSteps[0].shortTitle)));
        expect(t0.subSteps[1].shortTitle, isNot(equals(t1.subSteps[1].shortTitle)));
        expect(t1.subSteps[1].shortTitle, isNot(equals(t2.subSteps[1].shortTitle)));
        expect(t0.subSteps[2].shortTitle, isNot(equals(t1.subSteps[2].shortTitle)));
        expect(t1.subSteps[2].shortTitle, isNot(equals(t2.subSteps[2].shortTitle)));

        // Verify dynamic step scaling (compact 3-step guard, 4-step feel, 5-step single-clause extension, and 10+ step complex mechanic)
        expect(t0.subSteps.length, 6);
        expect(t1.subSteps.length, 7); // 4h heavy task includes extra tuning parameter step
        expect(t2.subSteps.length, 5); // 2h single-clause extension task

        final tGuard = TaskHowToBlueprint.resolve(
          parentTask: Subtask(
            id: 't_guard',
            text: 'Enforce line-of-sight break guard (1h)',
          ),
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Godot 4.3 GDScript 2D',
        );
        expect(tGuard.subSteps.length, 3);

        final tFeel = TaskHowToBlueprint.resolve(
          parentTask: Subtask(
            id: 't_feel',
            text: 'Hook up impact flash and audio cue (1h)',
          ),
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Godot 4.3 GDScript 2D',
        );
        expect(tFeel.subSteps.length, 4);

        final richCp = FeatureStateNode(
          id: 'cp_rich',
          name: 'Stage 1: Grapple Physics & Momentum',
          trigger: 'Verify full grapple swing and release loop.',
          tuningParams: const [
            'hook_range: 18 m',
            'pull_speed: 28 m/s',
            'swing_damping: 0.92',
          ],
          edgeCases: const [
            '[LOS GUARD] Detach on obstacle block',
            '[TENSION CLAMP] Clamp velocity on frame spike',
            '[COOLDOWN GUARD] Lock out re-fire during detach',
          ],
        );
        final tComplex = TaskHowToBlueprint.resolve(
          parentTask: Subtask(
            id: 't_complex',
            text:
                'Implement anchor raycast, tether state entry, pull impulse, swing arc damping, and release momentum boost (4h)',
          ),
          taskIndex: 0,
          checkpointNode: richCp,
          engineHint: 'Godot 4.3 GDScript 2D',
        );
        expect(tComplex.subSteps.length, greaterThanOrEqualTo(10));

        // Verify deriveConcreteAssetName strips "Checkpoint" and deduplicates repeated words without forcing "Controller"
        final terminalAsset = TaskHowToBlueprint.deriveConcreteAssetName(
          'Create Terminal interaction (2h) Checkpoint 1: Terminal Interaction & Contract',
        );
        expect(terminalAsset.pascalName, 'TerminalContract');
        expect(terminalAsset.pascalName, isNot(contains('Checkpoint')));
        expect(terminalAsset.pascalName, isNot(contains('Controller')));

        // Verify deriveConcreteGuardStepSpec formats underscore bracket tags as clean Title Case
        final spamGuard = TaskHowToBlueprint.deriveConcreteGuardStepSpec(
          rawGuard: '[INPUT_SPAM GUARD] Ignore rapid interact clicks',
          targetAssetName: 'BP_TerminalContractActor',
          engineLabel: 'UNREAL 5',
          unrealCppMode: false,
          primaryVarName: 'interactCooldown',
        );
        expect(spamGuard.shortTitle, 'Guard: Input Spam');

        // Verify UI / HUD and Combat tasks resolve their specialized component hierarchies
        final uiBp = TaskHowToBlueprint.resolve(
          parentTask: Subtask(
            id: 't_ui',
            text: 'Build HUD scoreboard overlay widget (2h)',
          ),
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Godot 4.3 GDScript 2D',
        );
        expect(uiBp.subSteps[1].codeFormula, contains('HudCanvas'));

        final combatBp = TaskHowToBlueprint.resolve(
          parentTask: Subtask(
            id: 't_combat',
            text: 'Configure Weapon Projectile Spawner (2h)',
          ),
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
        );
        expect(combatBp.subSteps[1].codeFormula, contains('WeaponMesh'));
        expect(combatBp.subSteps[1].codeFormula, contains('MuzzlePoint'));
      },
    );

    test(
      '2-Stage Release Plan Chat & Custom Mechanic Breakdown synthesizes domain-specific tuning variables, edge guards, and playable checkpoints',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('High-speed grappling hook parkour roguelite');
        await provider.openReleasePlanGate();

        final firstBeat = provider.releaseBlueprint!.beats.first;
        final customFeatBp = ProposedFeatureBlueprint(
          id: 'feat_grapple_hook_swing',
          title: 'Grapple Hook Swing',
          goal: 'Latch onto overhead anchors and swing across gaps.',
          doneWhen: 'Player swings across 3 gaps and releases with momentum.',
          estimatedHours: 6,
          included: true,
          lifecycle: FeatureLifecycleStatus.newFeature,
          originVersion: 'v0.1',
          tuningParams: const ['hookMaxRange: 18.0 m', 'hookPullSpeed: 28.0 m/s'],
          edgeCases: const ['[LOS BREAK GUARD] Detach when line-of-sight breaks'],
          checkpoints: [
            ProposedCheckpointBlueprint(
              title: 'Grapple Anchor & Swing',
              playtestCriteria: 'Fire hook -> swing across gap',
              tasks: const ['Hook Raycast (2h)', 'Swing Arc (2h)'],
              tuningParams: const ['hookMaxRange: 18.0 m', 'hookPullSpeed: 28.0 m/s'],
              edgeCases: const ['[LOS BREAK GUARD] Detach when line-of-sight breaks'],
              releaseVersion: 'v0.1',
            ),
            ProposedCheckpointBlueprint(
              title: 'Release Boost & Cooldown',
              playtestCriteria: 'Release hook -> launch with momentum',
              tasks: const ['Release Impulse (2h)'],
              tuningParams: const ['hookMaxRange: 18.0 m', 'hookPullSpeed: 28.0 m/s'],
              edgeCases: const ['[LOS BREAK GUARD] Detach when line-of-sight breaks'],
              releaseVersion: 'v0.1',
            ),
          ],
        );
        firstBeat.features.add(customFeatBp);

        expect(customFeatBp.title, 'Grapple Hook Swing');
        expect(customFeatBp.checkpoints.length, 2);
        expect(customFeatBp.tuningParams, contains('hookMaxRange: 18.0 m'));
        expect(customFeatBp.tuningParams, contains('hookPullSpeed: 28.0 m/s'));
        expect(
          customFeatBp.edgeCases.first,
          contains('[LOS BREAK GUARD]'),
        );

        // Also verify Release Plan chat command "Add Ore Smelting Furnace to Beat 2" adds a tailored economy feature
        await provider.sendReleasePlanChatMessage('Add Ore Smelting Furnace to Beat 2');
        final secondBeat = provider.releaseBlueprint!.beats[1];
        final furnaceBp = secondBeat.features.last;
        expect(furnaceBp.title, 'Ore Smelting Furnace');
        expect(furnaceBp.checkpoints.length, 2);
        expect(furnaceBp.tuningParams, contains('transactionCostBase: 25 gold'));

        // Execute into 2. Workbench and verify the custom Grapple Hook Swing feature carries its 2 checkpoints & tuning into the Workbench
        await provider.approveAndExecuteReleasePlan();
        final stage2Beat1Feats = provider.featuresForBeat(
          provider.activeReleaseBeats.first.id,
        );
        final stage2GrappleDoc = stage2Beat1Feats.firstWhere(
          (f) => f.title == 'Grapple Hook Swing',
        );
        final stage2GrappleStates =
            FeatureStateNode.getStatesForDocument(stage2GrappleDoc);
        expect(stage2GrappleStates.length, 2);
        expect(
          stage2GrappleStates.first.tuningParams,
          contains('hookPullSpeed: 28.0 m/s'),
        );
      },
    );

    test(
      '2. Workbench Live Feature Add/Rename/Remove, Section/Cache Sync on updateFeatureStates, and Playtest Issue Triage ([FIX] task + [PLAYTEST GUARD])',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('Cyberpunk Grapple Arena');
        await provider.approveConceptAndBuildRelease();

        final firstBeat = provider.activeReleaseBeats.first;
        final addedFeatId = provider.addLiveFeatureToBeat(
          firstBeat.id,
          'Temp Debug Feature',
        );
        expect(addedFeatId, isNotNull);
        final removed = provider.removeLiveFeature(addedFeatId!);
        expect(removed, isTrue);
        expect(provider.documents.containsKey(addedFeatId), isFalse);

        final builtFeat = provider.featuresForBeat(firstBeat.id).first;
        provider.renameLiveFeature(builtFeat.id, 'Wall Grapple & Vault');
        expect(builtFeat.title, 'Wall Grapple & Vault');

        final states = FeatureStateNode.getStatesForDocument(builtFeat);
        states.first.tuningParams = [
          'grapplePullSpeed: 32.0 m/s',
          'vaultBoost: 12.0 m/s',
        ];
        states.first.edgeCases = ['[WALL_CLIP GUARD] Clamp vault clearance'];
        provider.updateFeatureStates(builtFeat.id, states);

        // Verify updateFeatureStates syncs feat.sections['tuning'], ['variables'], and ['edge_cases']
        expect(
          builtFeat.sections['tuning'],
          contains('grapplePullSpeed: 32.0 m/s'),
        );
        expect(
          builtFeat.sections['variables'],
          contains('vaultBoost: 12.0 m/s'),
        );
        expect(
          builtFeat.sections['edge_cases'],
          contains('[WALL_CLIP GUARD] Clamp vault clearance'),
        );

        final initialTaskCount = states.first.checklist.length;
        final newFixIdx = provider.logPlaytestIssueOnCheckpoint(
          featureId: builtFeat.id,
          states: states,
          checkpointIndex: 0,
          issueDescription: 'Hook pulls player through thin walls',
        );
        expect(newFixIdx, initialTaskCount);

        final updatedStates = FeatureStateNode.getStatesForDocument(builtFeat);
        final fixTask = updatedStates.first.checklist.last;
        expect(fixTask.text, '[FIX] Hook pulls player through thin walls (1h)');
        expect(fixTask.children.length, 3);
        expect(
          fixTask.children.first.text,
          contains('REPRODUCE & INSPECT PLAYTEST ISSUE'),
        );
        expect(
          updatedStates.first.edgeCases,
          contains('[PLAYTEST GUARD] Hook pulls player through thin walls'),
        );
      },
    );

    test(
      'Stage 1 Option Refresh, Full Markdown Concept Spec, and Post-Release Retrospective Summary',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('Cyberpunk Grapple Arena');

        // Verify ProjectConceptBlueprint.toFullMarkdownSpec includes Game Spec, Tech Spec, Design Pillars, and Trade-Offs
        final fullMd = provider.conceptDraft!.toFullMarkdownSpec();
        expect(fullMd, contains('Game Spec:'));
        expect(fullMd, contains('Tech Spec:'));
        expect(fullMd, contains('Design Pillars:'));
        expect(fullMd, contains('Trade-Offs:'));
        expect(fullMd, contains('Goal:'));
        expect(fullMd, contains('In Scope:'));
        expect(fullMd, contains('Done When:'));

        // Regenerate Stage 1 section options
        await provider.regenerateStage1SectionOptions('goal');
        expect(provider.conceptDraft!.sectionOptions['goal'], isNotEmpty);
        expect(
          provider.conceptDraft!.sectionOptions['goal']!.first,
          contains('(1):'),
        );

        // Build v0.1 in 2. Workbench
        await provider.approveConceptAndBuildRelease();
        final firstBeat = provider.activeReleaseBeats.first;
        final firstFeat = provider.featuresForBeat(firstBeat.id).first;
        final states = FeatureStateNode.getStatesForDocument(firstFeat);

        // Log a Playtest Issue on Checkpoint 1 to verify [PLAYTEST GUARD] & [FIX] task injection
        provider.logPlaytestIssueOnCheckpoint(
          featureId: firstFeat.id,
          states: states,
          checkpointIndex: 0,
          issueDescription: 'Rapid input causes duplicate dash trigger',
        );
        final afterFixStates = FeatureStateNode.getStatesForDocument(firstFeat);
        expect(
          afterFixStates.first.edgeCases.any((g) => g.startsWith('[PLAYTEST GUARD]')),
          isTrue,
        );

        // Post-Release Retrospective & Auto-Carryover Summary into v0.2
        final retro = provider.buildActiveReleaseRetrospective();
        expect(retro.playtestGuardsAdded, greaterThanOrEqualTo(1));
        expect(retro.carryoverFeatureTitles, isNotEmpty);
        expect(retro.verifiedCheckpoints, lessThanOrEqualTo(retro.totalCheckpoints));
        await provider.advanceToNextRelease();
        expect(provider.lastReleaseRetrospective, isNotNull);
      },
    );

    test(
      'GDD Ingestion & Jump to Full Concept Review, and Dual-Model Config Persistence',
      () async {
        final provider = WorkbenchProvider();

        // Import Existing GDD / Pitch Notes and jump straight to Step 09 Full Concept Review
        await provider.importExistingGddAndJumpToReview('''
# Solar Skiff Salvage
Goal: Build a fast 3D hover-skiff salvage and grapple loop in Unity 6.
Engine: Unity 6 (C#)
Done When: Playtester completes 3 consecutive salvage runs and docks without clipping.
''');
        expect(provider.conceptDraft, isNotNull);
        expect(provider.conceptDraft!.title, 'Solar Skiff Salvage');
        expect(
          provider.conceptDraft!.goal,
          contains('hover-skiff salvage and grapple loop'),
        );
        expect(provider.jumpToFullReviewPending, isTrue);
        provider.consumeJumpToFullReviewPending();
        expect(provider.jumpToFullReviewPending, isFalse);

        // Dual-Model AI Config updates both conversationModel and planningModel
        provider.updateAiConfig(
          conversationModel: 'gemini-3.8-flash',
          planningModel: 'gemini-3.8-flash',
          thinkingLevel: 'MEDIUM',
        );
        expect(provider.conversationModel, 'gemini-3.8-flash');
        expect(provider.planningModel, 'gemini-3.8-flash');
        expect(provider.thinkingLevel, 'MEDIUM');
      },
    );

    test(
      '4-Phase Release Train: Split Prototype (v0.1 -> v0.2) -> Per-Epic MVPs (MVP Epic 1..4) -> Vertical Slice -> Full Production',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('Arena Roguelite');

        // Configure a 4-Beat Core Loop with a 2-Part Split Prototype in Stage 1 Step 09
        provider.updateConceptDraft((draft) {
          draft.coreLoopBeats = [
            'Staging & Loadout Prep: Choose starting weapon and dash module.',
            'Arena Entry & Traversal: Enter arena and dash across hazards.',
            'Combat & Wave Escalation: Defeat enemy waves and dodge attacks.',
            'Loot & Round Reset: Pick 1 of 3 upgrades and start next wave.',
          ];
          draft.releaseTrainTitles = [
            'v0.1: Prototype — Part 1: Controls & Primary Mechanics',
            'v0.2: Prototype — Part 2: Progression & Loop Reset',
          ];
          draft.exclusions = [
            'Endless Boss Rush Mode',
            'Daily Seeded Leaderboard',
          ];
        });

        // Phase 1 · Part 1 (v0.1): Should only include the first half of the Core Loop Beats (2 Beats)
        await provider.openReleasePlanGate();
        expect(provider.currentPhase, ProductionPhase.prototype);
        expect(provider.activePhaseBadgeLabel, 'PHASE 1 · PROTOTYPE (1/2)');
        expect(
          provider.nextReleaseActionLabel,
          'Ship & Plan v0.2 (Prototype Part 2) ✦',
        );
        final part1Bp = provider.releaseBlueprint!;
        expect(part1Bp.beats.length, 2);
        await provider.approveAndExecuteReleasePlan();

        // Advance to Phase 1 · Part 2 (v0.2): Keeps Part 1 Epics STABLE ✓ and adds the remaining 2 Core Loop Beats as NEW
        await provider.advanceToNextRelease();
        expect(provider.currentPhase, ProductionPhase.prototype);
        expect(provider.activePhaseBadgeLabel, 'PHASE 1 · PROTOTYPE (2/2)');
        expect(
          provider.nextReleaseActionLabel,
          'Ship & Unlock Phase 2 (MVP Epic 1) ✦',
        );
        final part2Bp = provider.releaseBlueprint!;
        expect(part2Bp.beats.length, 4);
        expect(
          part2Bp.beats[0].features.every(
            (f) => f.lifecycle == FeatureLifecycleStatus.stable,
          ),
          isTrue,
        );
        expect(
          part2Bp.beats[2].features.any(
            (f) => f.lifecycle == FeatureLifecycleStatus.newFeature,
          ),
          isTrue,
        );
        await provider.approveAndExecuteReleasePlan();
        // Stage 3 auto-focuses the first incomplete NEW Beat (Beat 3, index 2) and marks Part 1 STABLE features 100% complete
        expect(provider.selectedBeatId, provider.activeReleaseBeats[2].id);

        // Advance to Phase 2 · Per-Epic MVPs (unlocks 1 MVP Epic release at a time, zero pre-queued releases)
        await provider.advanceToNextRelease();
        expect(provider.currentPhase, ProductionPhase.mvp);
        final mvpReleases = provider.projectReleases
            .where((r) => r.sections['phase'] == ProductionPhase.mvp.name)
            .toList();
        expect(mvpReleases.length, 1);

        for (int epicIdx = 0; epicIdx < 4; epicIdx++) {
          expect(provider.currentPhase, ProductionPhase.mvp);
          expect(
            provider.activePhaseBadgeLabel,
            'PHASE 2 · MVP EPIC ${epicIdx + 1} OF 4',
          );
          final mvpBp = provider.releaseBlueprint!;
          expect(mvpBp.releaseTitle, contains('MVP Epic ${epicIdx + 1}'));

          // Only Epic `epicIdx` should have UPGRADING/NEW features; all other Epics must be STABLE ✓ (0h)
          for (int bIdx = 0; bIdx < mvpBp.beats.length; bIdx++) {
            final beatFeats = mvpBp.beats[bIdx].features;
            if (bIdx == epicIdx) {
              expect(
                beatFeats.any(
                  (f) =>
                      f.lifecycle == FeatureLifecycleStatus.upgrade ||
                      f.lifecycle == FeatureLifecycleStatus.newFeature,
                ),
                isTrue,
                reason:
                    'Epic ${epicIdx + 1} should upgrade in its targeted MVP release',
              );
            } else {
              expect(
                beatFeats.every(
                  (f) => f.lifecycle == FeatureLifecycleStatus.stable,
                ),
                isTrue,
                reason:
                    'Non-target Epic ${bIdx + 1} must stay STABLE in MVP Epic ${epicIdx + 1}',
              );
            }
          }

          await provider.approveAndExecuteReleasePlan();
          // Stage 3 auto-focuses the active MVP Epic `epicIdx`, starts active release & feature progress at 0%, and ensures STABLE Epics have 100% progress
          expect(
            provider.selectedBeatId,
            provider.activeReleaseBeats[epicIdx].id,
          );
          expect(
            provider.getDocumentProgress(provider.selectedFeatureId!),
            0,
            reason:
                'Upgraded feature in MVP Epic ${epicIdx + 1} should start at 0% for its new delta checkpoints',
          );
          expect(
            provider.getDocumentProgress(provider.activeReleaseId!),
            0,
            reason:
                'New MVP Epic ${epicIdx + 1} release should start at 0% (ignoring 100% STABLE Epics)',
          );
          expect(
            provider.releaseConciseLabel(provider.activeRelease!),
            contains('MVP Epic ${epicIdx + 1}'),
          );
          for (int bIdx = 0; bIdx < provider.activeReleaseBeats.length; bIdx++) {
            if (bIdx != epicIdx) {
              final stableBeat = provider.activeReleaseBeats[bIdx];
              for (final feat in provider.featuresForBeat(stableBeat.id)) {
                expect(
                  provider.getDocumentProgress(feat.id),
                  100,
                  reason:
                      'STABLE Feature ${feat.title} in Epic ${bIdx + 1} should have 100% progress',
                );
              }
            }
          }
          // Verify revisiting Stage 1 mid-project preserves built Phase 2 MVP releases without pre-queuing unbuilt ones
          if (epicIdx == 0) {
            provider.updateConceptDraft((draft) {
              draft.exclusions = [
                ...draft.exclusions,
                'Co-Op Split Screen Mode',
              ];
            });
            expect(
              provider.projectReleases
                  .where((r) => r.sections['phase'] == ProductionPhase.mvp.name)
                  .length,
              1,
            );
          }
          if (epicIdx == 3) {
            expect(
              provider.nextReleaseActionLabel,
              'Ship & Unlock Phase 3 (Vertical Slice) ✦',
            );
          }
          await provider.advanceToNextRelease();
        }

        // Phase 3 · Vertical Slice: Unlocks automatically after all 4 Per-Epic MVPs complete
        expect(provider.currentPhase, ProductionPhase.verticalSlice);
        expect(provider.activePhaseBadgeLabel, 'PHASE 3 · VERTICAL SLICE');
        expect(
          provider.nextReleaseActionLabel,
          'Ship & Unlock Phase 4 (Full Production) ✦',
        );
        final vsBp = provider.releaseBlueprint!;
        expect(vsBp.releaseTitle, contains('Vertical Slice'));
        // Every Epic's primary feature receives a Vertical Slice Polish upgrade checkpoint
        for (final beat in vsBp.beats) {
          expect(
            beat.features.first.lifecycle,
            FeatureLifecycleStatus.upgrade,
          );
          expect(
            beat.features.first.checkpoints.first.title,
            contains('Visual, Audio & Feel Polish'),
          );
        }
        await provider.approveAndExecuteReleasePlan();

        // Phase 4 · Full Production: Unlocks automatically after Vertical Slice completes
        await provider.advanceToNextRelease();
        expect(provider.currentPhase, ProductionPhase.fullProduction);
        expect(
          provider.activePhaseBadgeLabel,
          'PHASE 4 · FULL PRODUCTION (PASS 1)',
        );
        final fpBp = provider.releaseBlueprint!;
        expect(fpBp.releaseTitle, contains('Full Production'));
        expect(fpBp.preset, ReleaseScope.fullProduction);
        // Primary features receive Content Roster & Progression Scaling checkpoints + deferred Out of Scope items promote as NEW features
        expect(
          fpBp.beats.first.features.first.checkpoints.first.title,
          contains('Content Roster & Progression Scaling'),
        );
        final promotedNewFeatures = fpBp.beats
            .expand((b) => b.features)
            .where((f) => f.lifecycle == FeatureLifecycleStatus.newFeature)
            .toList();
        expect(promotedNewFeatures, isNotEmpty);
        await provider.approveAndExecuteReleasePlan();
      },
    );

    test(
      'Stage 1A Idea Summarizer & Update Summary handles initial pitch, empty-input card fold/refresh, replacement, rename, and full pitch swap',
      () async {
        const courierPitch =
            'Brave areas too lethal for ordinary survivors to retrieve and deliver vital cargo across a ruined metropolis using fluid parkour, wall-running, and high-speed combat against scavengers hunting your haul.';
        final provider = WorkbenchProvider();
        await provider.ingestOrRefineSparkIdea(courierPitch);
        final intake = provider.sparkIntake!;

        // 1. Working Title extracts domain/mechanic nouns instead of copying first 3 words ("Brave Areas Too")
        expect(intake.workingTitle, isNot('Brave Areas Too'));
        expect(intake.workingTitle, 'Metropolis Cargo Parkour');

        // 2. Summary is natural and never quotes the raw pitch verbatim
        expect(intake.baseSummary, isNot(contains('"Brave areas too')));
        expect(intake.baseSummary, isNot(contains('centers on "')));
        expect(intake.baseSummary.toLowerCase(), contains('metropolis'));
        expect(intake.baseSummary.toLowerCase(), contains('parkour'));

        // 3. Mechanics and Expansion Cards reflect parkour/courier/scavengers, NOT grapple hooks
        expect(intake.mechanics, contains('Fluid Parkour & Wall-Running'));
        expect(intake.mechanics, contains('Cargo Haul Protection'));
        expect(
          intake.mechanics.any((m) => m.toLowerCase().contains('grapple')),
          isFalse,
        );
        expect(
          intake.expansionCards.any((c) => c.title.toLowerCase().contains('grapple')),
          isFalse,
        );
        expect(
          intake.expansionCards.first.title,
          'Wall-Run Chain & Vault Boost',
        );

        // 4. Flow 4: Toggle an Expansion Card on and click Update Summary with an empty input box
        provider.toggleSparkExpansionCard(0);
        expect(provider.sparkIntake!.expansionCards.first.isSelected, isTrue);
        await provider.ingestOrRefineSparkIdea('');
        final afterEmptyUpdate = provider.sparkIntake!;
        // Selected card is folded into baseSummary & mechanics, and new Expansion Cards are loaded
        expect(
          afterEmptyUpdate.baseSummary.toLowerCase(),
          contains('wall-run chain and rooftop vault speed boost'),
        );
        expect(
          afterEmptyUpdate.mechanics,
          contains('Wall-Run Chain & Vault Boost'),
        );
        expect(
          afterEmptyUpdate.expansionCards.first.title,
          'Momentum Slide & Rooftop Kick',
        );

        // 5. Flow 3: Replacement refinement ("instead of scavengers use patrol drones")
        await provider.ingestOrRefineSparkIdea(
          'instead of scavengers use patrol drones',
        );
        final afterReplace = provider.sparkIntake!;
        expect(afterReplace.rawIdea.toLowerCase(), contains('patrol drones'));
        expect(afterReplace.mechanics, contains('Patrol Drones'));

        // 6. Flow 1: Explicit title rename ("rename to Metro Runner")
        await provider.ingestOrRefineSparkIdea('rename to Metro Runner');
        expect(provider.sparkIntake!.workingTitle, 'Metro Runner');

        // 7. Regression: Settlement supply courier + "searching for caches hidden" never triggers submarine/sonar
        provider.clearSparkIdeaIntake();
        await provider.ingestOrRefineSparkIdea(
          'A supply courier that goes from settlement to settlement shooting enemies and looting the area to finish the required item quests',
        );
        await provider.ingestOrRefineSparkIdea(
          'staying longer in the zone to get more credits for killing enemies and searching for caches hidden',
        );
        final afterCourierSearch = provider.sparkIntake!;
        expect(
          afterCourierSearch.baseSummary.toLowerCase(),
          isNot(contains('submarine')),
        );
        expect(
          afterCourierSearch.baseSummary.toLowerCase(),
          isNot(contains('sonar')),
        );
        expect(
          afterCourierSearch.mechanics
              .any((m) => m.toLowerCase().contains('submarine') || m.toLowerCase().contains('sonar')),
          isFalse,
        );
        expect(
          afterCourierSearch.baseSummary.toLowerCase(),
          contains('courier'),
        );

        // 8. Regression: Clicking Refresh Suggestions (shuffleSparkExpansionCards) NEVER overwrites
        // the user's workingTitle, baseSummary, or mechanics, and keeps expansion cards on the same subject
        provider.clearSparkIdeaIntake();
        await provider.ingestOrRefineSparkIdea(
          'A cozy pizza alchemy game where you brew magical toppings and deliver pies to night-shift monsters',
        );
        provider.sparkIntake!.workingTitle = 'Cozy Pizza Alchemy';
        provider.sparkIntake!.baseSummary =
            'Brew magical toppings and bake custom pizzas for hungry night-shift monsters.';
        provider.sparkIntake!.mechanics = [
          'Dough Toss & Oven Timing',
          'Potion Topping Brew',
          'Monster Order Rush',
        ];
        await provider.shuffleSparkExpansionCards();
        expect(provider.sparkIntake!.workingTitle, equals('Cozy Pizza Alchemy'));
        expect(
          provider.sparkIntake!.baseSummary,
          equals(
            'Brew magical toppings and bake custom pizzas for hungry night-shift monsters.',
          ),
        );
        expect(
          provider.sparkIntake!.mechanics,
          equals([
            'Dough Toss & Oven Timing',
            'Potion Topping Brew',
            'Monster Order Rush',
          ]),
        );
        expect(
          provider.sparkIntake!.expansionCards.first.description,
          contains('Cozy Pizza Alchemy'),
        );
      },
    );

    test(
      'Items 2-4 Regressions: Named Design Pillars, Premise-Specific Trade-Offs & Exclusions, and 0% Initial v0.1 Feature Checkpoints',
      () async {
        // Item 4: Default & unprefixed Design Pillars always receive concrete 2-3 word names (never "Pillar 01")
        final defaultBlueprint = ProjectConceptBlueprint(
          sparkIdea: 'A fast top-down action game.',
          title: 'Test Project',
          goal: 'Playable prototype loop.',
          coreLoopBeats: ['Move', 'Attack', 'Extract'],
          exclusions: ['No online multiplayer'],
          doneWhen: 'Loop completes cleanly',
          releaseTrainTitles: ['v0.1 Prototype'],
          questions: const [],
        );
        for (int i = 0; i < defaultBlueprint.designPillars.length; i++) {
          final parsed = ProjectConceptBlueprint.parsePillarTitleAndBody(
            defaultBlueprint.designPillars[i],
            i,
          );
          expect(parsed.title.toLowerCase(), isNot(startsWith('pillar ')));
          expect(parsed.title, isNotEmpty);
          expect(parsed.body, isNotEmpty);
        }
        final unprefixedParsed = ProjectConceptBlueprint.parsePillarTitleAndBody(
          'Every run feels tense as cargo weight slows your movement',
          0,
        );
        expect(unprefixedParsed.title.toLowerCase(), isNot(startsWith('pillar ')));
        expect(unprefixedParsed.title, 'High-Stakes Cargo');

        // Item 4: Different game premises generate distinct Trade-Offs (05) and Out of Scope Exclusions (07)
        final courierProvider = WorkbenchProvider();
        await courierProvider.startConceptInterview(
          'A supply courier traveling from settlement to settlement shooting enemies and looting item quests',
        );
        final courierDraft = courierProvider.conceptDraft!;

        final farmProvider = WorkbenchProvider();
        await farmProvider.startConceptInterview(
          'A cozy alchemy shop where you grow crops, brew potions, and haggle with townsfolk',
        );
        final farmDraft = farmProvider.conceptDraft!;

        expect(courierDraft.tradeOffs, isNot(equals(farmDraft.tradeOffs)));
        expect(courierDraft.exclusions, isNot(equals(farmDraft.exclusions)));
        expect(
          courierDraft.sectionOptions['tradeOffs'],
          isNot(equals(farmDraft.sectionOptions['tradeOffs'])),
        );
        expect(
          courierDraft.sectionOptions['exclusions'],
          isNot(equals(farmDraft.sectionOptions['exclusions'])),
        );

        // Item 1: Pure 2-Stage Workflow (1. Concept -> 2. Workbench) transitions immediately to releaseWorkbench
        final observedStages = <WorkbenchStage>[];
        farmProvider.addListener(() {
          observedStages.add(farmProvider.currentStage);
        });
        await farmProvider.approveConceptAndBuildRelease();
        expect(farmProvider.currentStage, WorkbenchStage.releaseWorkbench);
        expect(
          observedStages.first,
          WorkbenchStage.releaseWorkbench,
          reason:
              '2-stage workflow must transition immediately from 1. Concept to 2. Workbench',
        );
        await farmProvider.prepareProgressiveNextReleaseDraft();
        expect(farmProvider.currentStage, WorkbenchStage.releaseWorkbench);

        // Item 2: v0.1 features always start at 0% progress with 1 cohesive greybox checkpoint (never 50% / 15/30 DONE)
        await courierProvider.openReleasePlanGate();
        await courierProvider.approveAndExecuteReleasePlan();
        // Even if openReleasePlanGate + approveAndExecuteReleasePlan is triggered a second time on v0.1,
        // features must still start at 0% with 1 checkpoint and zero pre-completed tasks.
        await courierProvider.openReleasePlanGate();
        await courierProvider.approveAndExecuteReleasePlan();

        final v01Feats = [
          for (final b in courierProvider.activeReleaseBeats)
            ...courierProvider.featuresForBeat(b.id),
        ];
        expect(v01Feats, isNotEmpty);
        for (final feat in v01Feats) {
          final states = FeatureStateNode.getStatesForDocument(feat);
          expect(
            states.length,
            1,
            reason:
                'v0.1 feature "${feat.title}" should have exactly 1 cohesive greybox checkpoint',
          );
          expect(states.first.isCompleted, isFalse);
          expect(
            courierProvider.getDocumentProgress(feat.id),
            0.0,
            reason: 'v0.1 feature "${feat.title}" must start at 0% progress',
          );
        }

        // Category 1 & 2 Streamlining: Fast-Track to Full Review + Live Workbench Feature CRUD (Add, Rename, Defer/Remove)
        final fastTrackProvider = WorkbenchProvider();
        await fastTrackProvider.startConceptInterview(
          'A tactical mech extraction shooter',
          true,
        );
        expect(fastTrackProvider.jumpToFullReviewPending, isTrue);

        final firstBeatDoc = courierProvider.activeReleaseBeats.first;
        final initialBeatFeatCount =
            courierProvider.featuresForBeat(firstBeatDoc.id).length;
        final newLiveFeatId = courierProvider.addLiveFeatureToBeat(
          firstBeatDoc.id,
          'Zipline Anchor & Detach',
        );
        expect(newLiveFeatId, isNotNull);
        expect(courierProvider.selectedFeatureId, newLiveFeatId);
        await Future<void>.delayed(Duration.zero);
        expect(
          courierProvider.documents[newLiveFeatId!]!.sections['scope'],
          contains('Goal: Build zipline anchor attach and momentum release mechanics.'),
        );
        expect(
          courierProvider.documents[newLiveFeatId]!.sections['scope'],
          contains('Done When: Player attaches to zipline and detaches cleanly in playtest.'),
        );
        expect(
          courierProvider.featuresForBeat(firstBeatDoc.id).length,
          initialBeatFeatCount + 1,
        );
        courierProvider.renameLiveFeature(
          newLiveFeatId,
          'Zipline Boost & Detach',
        );
        expect(
          courierProvider.documents[newLiveFeatId]!.title,
          'Zipline Boost & Detach',
        );
        final removed = courierProvider.removeLiveFeature(newLiveFeatId);
        expect(removed, isTrue);
        expect(
          courierProvider.featuresForBeat(firstBeatDoc.id).length,
          initialBeatFeatCount,
        );

        // Pure title cleanup helper (no hardcoded archetype substitution)
        expect(
          MechanicArchetypeProfile.concreteFeatureTitleForBeat(
            'Card Hand & Mana: Deck Draw — Draw cards each turn',
            beatTitle: 'Card Hand & Mana',
          ),
          'Deck Draw',
        );
        expect(
          MechanicArchetypeProfile.concreteFeatureTitleForBeat(
            'Truck Physics Controller',
          ),
          'Truck Physics',
        );
        expect(
          MechanicArchetypeProfile.concreteFeatureTitleForBeat(
            'Automated Turret System',
          ),
          'Automated Turret',
        );
        expect(
          MechanicArchetypeProfile.concreteFeatureTitleForBeat(
            'Cargo Pickup Mechanic',
          ),
          'Cargo Pickup',
        );

        // Verify custom_snippet sub-steps preserve custom verification (verifyResult) & codeLanguage (stepPath)
        final sampleFeat = courierProvider
            .featuresForBeat(courierProvider.activeReleaseBeats.first.id)
            .first;
        final sampleStates = FeatureStateNode.getStatesForDocument(sampleFeat);
        final sampleCp = sampleStates.first;
        final sampleTask = sampleCp.checklist.first;
        TaskHowToBlueprint.resolve(
          parentTask: sampleTask,
          taskIndex: 0,
          checkpointNode: sampleCp,
          engineHint: 'Godot 4',
        );
        sampleTask.children.first
          ..codeTargetFile = 'custom_snippet'
          ..codeLanguage = 'Scene Dock → PlayerCharacter → Inspector'
          ..verification = 'Confirm custom AI step verify check passes in Play mode.';
        TaskHowToBlueprint.clearCache();
        final resolvedCustom = TaskHowToBlueprint.resolve(
          parentTask: sampleTask,
          taskIndex: 0,
          checkpointNode: sampleCp,
          engineHint: 'Godot 4',
        );
        expect(
          resolvedCustom.subSteps.first.stepPath,
          'Scene Dock → PlayerCharacter → Inspector',
        );
        expect(
          resolvedCustom.subSteps.first.verifyResult,
          'Confirm custom AI step verify check passes in Play mode.',
        );

        // Round 3: Editing checkpoint tuningParams & edgeCases re-binds non-custom Subtask children & code formulas while preserving completion state
        sampleTask.children[3].completed = true;
        sampleCp.tuningParams = ['truckNitroSpeed: 42.0 m/s'];
        sampleCp.edgeCases = ['[NITRO LOCK GUARD] Block nitro while braking'];
        TaskHowToBlueprint.clearCache();
        final resolvedAfterSpecEdit = TaskHowToBlueprint.resolve(
          parentTask: sampleTask,
          taskIndex: 0,
          checkpointNode: sampleCp,
          engineHint: 'Godot 4',
        );
        expect(
          resolvedAfterSpecEdit.subSteps[3].codeFormula,
          contains('truckNitroSpeed'),
        );
        expect(
          sampleTask.children[3].codeSnippet,
          contains('truckNitroSpeed'),
        );
        expect(
          sampleTask.children[3].completed,
          isTrue,
          reason: 'Completed sub-step state must be preserved when tuning parameters update',
        );

        // Round 6: Cancelling Progressive Next Release cleanly rolls back unbuilt v0.2 releases, phase, and blueprint
        final preCancelRelId = courierProvider.activeReleaseId;
        final preCancelPhase = courierProvider.currentPhase;
        final preCancelReleaseCount = courierProvider.projectReleases.length;
        final draftV02 =
            await courierProvider.prepareProgressiveNextReleaseDraft();
        expect(draftV02, isNotNull);
        expect(
          courierProvider.projectReleases.length,
          greaterThan(preCancelReleaseCount),
        );
        courierProvider.restoreActiveReleaseAfterCancel(
          preCancelRelId,
          preCancelPhase,
        );
        expect(courierProvider.activeReleaseId, equals(preCancelRelId));
        expect(courierProvider.currentPhase, equals(preCancelPhase));
        expect(
          courierProvider.projectReleases.length,
          equals(preCancelReleaseCount),
          reason:
              'Unbuilt progressive release documents must be removed on modal cancel',
        );
        expect(
          courierProvider.releaseBlueprint?.releaseDocId,
          equals(preCancelRelId),
        );

        // Round 7: ReleaseScope.fromDocument resolves sections['releaseScope'] and custom v0.1 titles
        final customV01Doc = TierDocument(
          id: 'rel_custom_v0_1',
          title: 'v0.1: Neon Arena',
          tier: TierType.release,
          sections: {'releaseScope': ReleaseScope.prototype.name},
        );
        expect(
          customV01Doc.releaseScope,
          equals(ReleaseScope.featurePrototype),
        );
        final titleOnlyV01Doc = TierDocument(
          id: 'rel_title_v0_1',
          title: 'v0.1: Neon Arena',
          tier: TierType.release,
        );
        expect(
          titleOnlyV01Doc.releaseScope,
          equals(ReleaseScope.featurePrototype),
        );

        // Round 7: Switching releaseViewFilter between 'archived' and 'active' auto-selects archived / active features
        sampleFeat.sections['lifecycle'] =
            FeatureLifecycleStatus.superseded.name;
        courierProvider.setReleaseViewFilter('archived');
        expect(courierProvider.releaseViewFilter, equals('archived'));
        expect(courierProvider.selectedFeatureId, equals(sampleFeat.id));
        courierProvider.setReleaseViewFilter('active');
        expect(courierProvider.releaseViewFilter, equals('active'));
        expect(
          courierProvider.selectedFeatureId,
          isNot(equals(sampleFeat.id)),
        );
        sampleFeat.sections['lifecycle'] =
            FeatureLifecycleStatus.newFeature.name;

        // Round 8: Removing the last archived testbed while viewing 'archived' resets releaseViewFilter to 'active'
        final tempArchDoc = TierDocument(
          id: 'feat_temp_archived',
          title: 'Temp Archived Testbed',
          tier: TierType.feature,
          parentId: courierProvider.activeReleaseBeats.first.id,
          sections: {'lifecycle': FeatureLifecycleStatus.superseded.name},
        );
        courierProvider.documents[tempArchDoc.id] = tempArchDoc;
        courierProvider.setReleaseViewFilter('archived');
        expect(courierProvider.selectedFeatureId, equals(tempArchDoc.id));
        final removedArch = courierProvider.removeLiveFeature(tempArchDoc.id);
        expect(removedArch, isTrue);
        expect(courierProvider.releaseViewFilter, equals('active'));
        expect(
          courierProvider.selectedFeatureId,
          isNot(equals(tempArchDoc.id)),
        );

        // Round 9: TaskHowToBlueprint.formatConciseTaskTitle strips trailing " for <Beat>" and leading action verbs
        expect(
          TaskHowToBlueprint.formatConciseTaskTitle(
            'Implement player dash velocity and cooldown timer for Arena Entry & Traversal (2h)',
          ),
          equals('Player dash velocity & cooldown timer'),
        );
      },
    );

    test(
      '14. Dynamic 3-Area gemini-flash-latest Synthesis, AGENTS.md Export, and Stage 1 -> Stage 2 Live Sync',
      () async {
        final provider = WorkbenchProvider(enableAutoLoad: false);
        await provider.startConceptInterview(
          'Unreal 5 arena shooter with grapple hook, wave spawner, and ore extraction.',
        );
        provider.updateConceptDraft((d) {
          d.techSpec = ['Unreal Engine 5', '3D Arena'];
          d.exclusions = ['No multiplayer matchmaking'];
        });
        await provider.approveConceptAndBuildRelease();

        final initialBeats = provider.activeReleaseBeats;
        expect(initialBeats.length, greaterThanOrEqualTo(3));
        final beat1Id = initialBeats[0].id;
        final beat2Id = initialBeats[1].id;
        final beat3Id = initialBeats[2].id;
        final beat3OriginalTitle = initialBeats[2].title;
        final beat1Feat = provider.featuresForBeat(beat1Id).first;

        // Mark Task 1 of Beat 1's feature as 100% completed
        final b1States = FeatureStateNode.getStatesForDocument(beat1Feat);
        expect(b1States, isNotEmpty);
        b1States.first.checklist.first.completed = true;
        for (final sub in b1States.first.checklist.first.children) {
          sub.completed = true;
        }
        provider.updateFeatureStates(beat1Feat.id, b1States);
        expect(provider.getDocumentProgress(beat1Feat.id), greaterThan(0));

        // ── Upgrade 2: Dynamic 3-Area gemini-flash-latest synthesis & LRU cache invalidation ──
        String? capturedModel;
        String? capturedPrompt;
        final prevResponder = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, preferredModel) async {
          if (prompt.contains('Synthesize concrete, beginner-friendly 3-Area Engine How-To steps')) {
            capturedModel = preferredModel;
            capturedPrompt = prompt;
            return <String, dynamic>{
              'tasks': [
                {
                  'taskIndex': 0,
                  'subSteps': [
                    {
                      'title': 'STEP 1.1 · ATTACH GRAPPLE CABLE COMPONENT',
                      'stepPath': 'Source/Project/GrappleCharacter.cpp',
                      'instruction': 'Instantiate UCableComponent in C++ constructor.',
                      'area1Hierarchy':
                          'AGrappleCharacter (Self)\n └─ GrappleCable (UCableComponent)',
                      'area2Inspector':
                          'grappleRange: 1800.0 cm | cableWidth: 6.0',
                      'codeFormula':
                          'GrappleCable = CreateDefaultSubobject<UCableComponent>(TEXT("GrappleCable"));',
                      'verifyResult':
                          'GrappleCable appears under RootComponent in Details panel.',
                    },
                  ],
                },
              ],
            };
          }
          return prevResponder != null
              ? await prevResponder(prompt, preferredModel)
              : null;
        };

        try {
          await provider.synthesizeFeatureHowToStepsWithAi(
            beat1Feat.id,
            forceRefresh: true,
            unrealCppMode: true,
          );
        } finally {
          GeminiAgentClient.testMockResponder = prevResponder;
        }

        expect(capturedModel, equals('gemini-4-argon'));
        expect(capturedPrompt, contains('UNREAL 5 C++'));
        expect(capturedPrompt, contains('Sibling Feature'));

        final updatedStates = FeatureStateNode.getStatesForDocument(beat1Feat);
        final resolvedBp = TaskHowToBlueprint.resolve(
          parentTask: updatedStates.first.checklist.first,
          taskIndex: 0,
          checkpointNode: updatedStates.first,
          engineHint: 'Unreal Engine 5',
          unrealCppMode: true,
        );
        expect(resolvedBp.subSteps.first.area1Hierarchy, contains('GrappleCable'));
        expect(resolvedBp.subSteps.first.area2Inspector, contains('grappleRange: 1800.0 cm'));
        expect(resolvedBp.subSteps.first.instruction, equals('Instantiate UCableComponent in C++ constructor.'));

        // ── Upgrade 3: Engine-Ready Context Export (AGENTS.md / .cursorrules) ──
        final agentsMd = provider.buildActiveReleaseCodingAgentMarkdown(
          unrealCppMode: true,
        );
        expect(agentsMd, contains('# AGENTS.md —'));
        expect(agentsMd, contains('UNREAL 5 C++ (.h / .cpp)'));
        expect(agentsMd, contains('## 3. Canonical Tuning Variables & Inspector Bindings'));
        expect(agentsMd, contains('## 4. Mandatory Playtest & Edge-Case Guards'));
        expect(agentsMd, contains('Area 1 (Hierarchy)'));
        expect(agentsMd, contains('Area 2 (Inspector)'));

        // ── Upgrade 4: Stage 1 -> Stage 2 Live Sync (with Edge Case 3 Guard) ──
        final progressBeforeSync = provider.getDocumentProgress(beat1Feat.id);
        expect(progressBeforeSync, greaterThan(0));
        // Edit Stage 1:
        // 1. Rename Beat 1 in-place ("Arena Entry & Traversal" -> "Arena Entry & Grapple Launch")
        // 2. Delete Beat 2
        // 3. Keep Beat 3 (shifts to index 1)
        // 4. Add a brand-new Beat at index 2 ("Boss Escape Portal: Open the warp gate")
        provider.updateConceptDraft((d) {
          d.coreLoopBeats = [
            'Arena Entry & Grapple Launch: Enter the arena, dash across hazards, and chain grapple swings',
            '$beat3OriginalTitle: Dodge telegraphed attacks and counter-strike',
            'Boss Escape Portal: Open the warp gate after depositing ore',
          ];
          d.exclusions = [
            'No multiplayer matchmaking',
            'No weapon crafting tree',
          ];
        });

        final syncedBeats = provider.activeReleaseBeats;
        expect(syncedBeats.length, equals(3));
        // Beat 1 was updated in-place and preserved its ID and completed progress!
        expect(syncedBeats[0].id, equals(beat1Id));
        expect(syncedBeats[0].title, equals('Arena Entry & Grapple Launch'));
        expect(
          provider.getDocumentProgress(beat1Feat.id),
          equals(progressBeforeSync),
          reason: 'Stage 1 -> Stage 2 sync must preserve completed task progress',
        );
        // Beat 3 shifted to index 1 and kept its original Beat ID!
        expect(syncedBeats[1].id, equals(beat3Id));
        expect(syncedBeats[1].title, equals(beat3OriginalTitle));
        // Brand-new Beat 3 ("Boss Escape Portal") was created fresh and NOT falsely matched to deleted Beat 2!
        expect(syncedBeats[2].id, isNot(equals(beat2Id)));
        expect(syncedBeats[2].title, equals('Boss Escape Portal'));
        expect(provider.featuresForBeat(syncedBeats[2].id), isNotEmpty);
        // Deleted Beat 2's features were safely archived as superseded
        expect(
          provider.supersededFeatures.any((f) => f.parentId == beat2Id),
          isTrue,
        );
        // Exclusions synced into ReleaseBlueprint
        expect(
          provider.releaseBlueprint?.explicitExclusions,
          contains('No weapon crafting tree'),
        );
      },
    );

    testWidgets(
      '15. Single-Feature AI Prompt Export, Playtest Run Sheet Gate Triage, and Two-Way Code Sync',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final provider = WorkbenchProvider(enableAutoLoad: false);
        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        await provider.startConceptInterview(
          'Build a fast 3D action slasher in Unreal Engine 5.',
        );
        provider.updateConceptDraft((d) {
          d.title = 'Neon Katana';
          d.goal = 'Build a fast 3D action slasher in Unreal Engine 5.';
          d.techSpec = ['Engine: Unreal Engine 5', 'Language: C++ & Blueprints'];
        });
        final buildFuture = provider.approveConceptAndBuildRelease();
        await tester.pumpAndSettle();
        await buildFuture;
        await tester.pumpAndSettle();

        final beats = provider.activeReleaseBeats;
        expect(beats, isNotEmpty);
        final firstFeat = provider.featuresForBeat(beats.first.id).first;

        // ── 1. Single-Feature AI Prompt Export (Upgrade 2) ──
        final singlePrompt = provider.buildActiveFeatureCodingAgentPrompt(
          firstFeat.id,
          unrealCppMode: true,
        );
        expect(singlePrompt, contains('# AI CODING AGENT TASK PROMPT — ${firstFeat.title}'));
        expect(singlePrompt, contains('UNREAL 5 C++ (.h / .cpp)'));
        expect(singlePrompt, contains('## 2. Canonical Tuning Variables & Sibling Context'));
        expect(singlePrompt, contains('## 3. Mandatory Edge-Case & Playtest Guards'));
        expect(singlePrompt, contains('## 4. 3-Area Implementation Steps'));
        expect(
          find.byKey(ValueKey('copy_feature_ai_prompt_btn_${firstFeat.id}')),
          findsOneWidget,
        );

        // ── 2. Two-Way Engine Code Sync (Upgrade 4 + Gotcha 3 Multi-Line C++/C#/GDScript Regex) ──
        final syncResult = await provider.syncFeatureTuningAndGuardsFromCode(
          firstFeat.id,
          '''
          UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Movement")
          float moveSpeed = 780.0f;

          [SerializeField]
          private float dashCooldown = 0.25f;

          @export var comboWindowSec: float = 0.45

          // [GUARD] Cancel dash impulse immediately when player hits a solid wall normal
          ''',
        );
        expect(syncResult.updatedVars, greaterThanOrEqualTo(3));
        expect(syncResult.addedGuards, equals(1));

        final syncedStates = FeatureStateNode.getStatesForDocument(firstFeat);
        expect(
          syncedStates.last.tuningParams.any((p) => p.contains('780.0')),
          isTrue,
        );
        expect(
          syncedStates.last.tuningParams.any((p) => p.contains('dashCooldown: 0.25')),
          isTrue,
        );
        expect(
          syncedStates.last.tuningParams.any((p) => p.contains('comboWindowSec: 0.45')),
          isTrue,
        );
        expect(
          syncedStates.last.edgeCases.any(
            (g) => g.contains('Cancel dash impulse immediately when player hits a solid wall normal'),
          ),
          isTrue,
        );

        // ── 3. Unified Playtest Run Sheet Modal + Live Reactive Rebuilds (Upgrade 3 + Gotcha 2) ──
        final playtestSheetBtn = find.byKey(
          const ValueKey('open_playtest_run_sheet_btn'),
        );
        expect(playtestSheetBtn, findsOneWidget);
        await tester.ensureVisible(playtestSheetBtn);
        await tester.pumpAndSettle();
        await tester.tap(playtestSheetBtn);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('playtest_run_sheet_modal')),
          findsOneWidget,
        );
        expect(provider.getDocumentProgress(firstFeat.id), lessThan(100));

        // Click "✓ Pass Gate" inside the open modal and verify live reactive rebuild to 100%
        final passBtn = find.byKey(
          ValueKey('playtest_sheet_pass_btn_${firstFeat.id}'),
        );
        expect(passBtn, findsOneWidget);
        await tester.tap(passBtn);
        await tester.pumpAndSettle();

        expect(provider.getDocumentProgress(firstFeat.id), equals(100));
        expect(find.text('✓ Gate Passed'), findsWidgets);
      },
    );

    test(
      '16. Project JSON Backup/Restore (.layers.json) and Cross-Feature Variable Rename Propagation',
      () async {
        final provider = WorkbenchProvider(enableAutoLoad: false);
        await provider.startConceptInterview(
          'Build a fast 2D grapple action platformer in Godot 4.',
        );
        provider.updateConceptDraft((d) {
          d.title = 'Hook Runner';
          d.goal = 'Build a fast 2D grapple action platformer in Godot 4.';
          d.techSpec = ['Engine: Godot 4', 'Language: GDScript'];
        });
        await provider.approveConceptAndBuildRelease();

        final beats = provider.activeReleaseBeats;
        expect(beats, isNotEmpty);
        final allFeats = <TierDocument>[
          for (final b in beats) ...provider.featuresForBeat(b.id),
        ];
        expect(allFeats.length, greaterThanOrEqualTo(2));

        final featA = allFeats[0];
        final featB = allFeats[1];

        // Seed shared variable `grappleSpeed` across both Feature A and Feature B
        final statesA = FeatureStateNode.getStatesForDocument(featA);
        statesA.last.tuningParams = ['grappleSpeed: 650.0', 'hookRange: 320.0'];
        statesA.last.edgeCases = [
          '[GUARD] Clamp grappleSpeed when player collides with ceiling',
        ];
        provider.updateFeatureStates(featA.id, statesA);

        final statesB = FeatureStateNode.getStatesForDocument(featB);
        statesB.last.tuningParams = ['grappleSpeed: 650.0', 'releaseBoost: 1.25'];
        statesB.last.edgeCases = [
          '[GUARD] Scale momentum impulse by grappleSpeed on detach',
        ];
        statesB.last.checklist.first.children = [
          Subtask(
            id: 'sub_b_1',
            text: 'Apply grappleSpeed multiplier on release',
            specNotes: 'NODE: GrappleController | PROP: grappleSpeed = 650.0',
            codeSnippet: 'velocity = hook_dir * grappleSpeed * releaseBoost',
            verification: 'Confirm grappleSpeed scales launch arc cleanly.',
          ),
        ];
        provider.updateFeatureStates(featB.id, statesB);

        // ── 1. Cross-Feature Variable Rename Propagation (Upgrade 3) ──
        final updatedCount = provider.propagateVariableRenameAcrossProject(
          'grappleSpeed',
          'zipVelocity',
        );
        expect(updatedCount, greaterThanOrEqualTo(2));

        final updatedStatesA = FeatureStateNode.getStatesForDocument(featA);
        expect(updatedStatesA.last.tuningParams, contains('zipVelocity: 650.0'));
        expect(
          updatedStatesA.last.edgeCases.first,
          contains('Clamp zipVelocity when player collides with ceiling'),
        );

        final updatedStatesB = FeatureStateNode.getStatesForDocument(featB);
        expect(updatedStatesB.last.tuningParams, contains('zipVelocity: 650.0'));
        expect(
          updatedStatesB.last.edgeCases.first,
          contains('Scale momentum impulse by zipVelocity on detach'),
        );
        final updatedSubB = updatedStatesB.last.checklist.first.children.first;
        expect(updatedSubB.text, contains('zipVelocity'));
        expect(updatedSubB.specNotes, contains('zipVelocity = 650.0'));
        expect(updatedSubB.codeSnippet, contains('zipVelocity * releaseBoost'));
        expect(updatedSubB.verification, contains('zipVelocity'));

        // ── 2. Full Project JSON Export & Restore (.layers.json) (Upgrade 2) ──
        final exportedJson = provider.exportProjectToJson();
        expect(exportedJson, contains('"format": "layers-agentic-project-v2"'));
        expect(exportedJson, contains('"Hook Runner"'));
        expect(exportedJson, contains('zipVelocity: 650.0'));

        // Restore into a fresh provider instance (exact ID restoration)
        final freshProvider = WorkbenchProvider(enableAutoLoad: false);
        final restoredId = freshProvider.importProjectFromJson(exportedJson);
        expect(restoredId, isNotNull);
        expect(freshProvider.activeProject?.title, equals('Hook Runner'));
        expect(freshProvider.currentStage, equals(WorkbenchStage.releaseWorkbench));
        expect(freshProvider.activeReleaseBeats.length, equals(beats.length));

        final restoredFeats = <TierDocument>[
          for (final b in freshProvider.activeReleaseBeats)
            ...freshProvider.featuresForBeat(b.id),
        ];
        final restoredStatesB = FeatureStateNode.getStatesForDocument(
          restoredFeats[1],
        );
        expect(restoredStatesB.last.tuningParams, contains('zipVelocity: 650.0'));
        expect(
          restoredStatesB.last.checklist.first.children.first.codeSnippet,
          contains('zipVelocity * releaseBoost'),
        );

        // Import again into the same provider to verify collision-safe ID remapping
        final duplicateImportId = freshProvider.importProjectFromJson(exportedJson);
        expect(duplicateImportId, isNotNull);
        expect(duplicateImportId, isNot(equals(restoredId)));
        expect(
          freshProvider.activeProject?.title,
          equals('Hook Runner (Imported)'),
        );
        expect(freshProvider.savedProjects.length, equals(2));
      },
    );

    testWidgets(
      '17. Option A Single-Page Blueprint Default & 5 Frictionless Workflow Upgrades',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final provider = WorkbenchProvider(enableAutoLoad: false);
        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        // ── 1. Option A: Single-Page Live Blueprint by Default + Compact AI Pills + KV Dropdowns + Global Chat ──
        await provider.startConceptInterview(
          'A fast top-down mech arena shooter in Godot 4.',
        );
        await tester.pumpAndSettle();

        // Lands directly on the Single-Page Complete Blueprint (no 8-step click-through required)
        expect(
          find.byKey(const ValueKey('project_blueprint_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('full_blueprint_global_chat_input')),
          findsOneWidget,
        );

        // Compact 1-line AI Option Pill on Section 01 (Goal) updates Goal in 1 click
        final initialGoal = provider.conceptDraft!.goal;
        final compactGoalPill = find.byKey(
          const ValueKey('compact_option_pill_0_1'),
        );
        expect(compactGoalPill, findsOneWidget);
        await tester.ensureVisible(compactGoalPill);
        await tester.pumpAndSettle();
        await tester.tap(compactGoalPill);
        await tester.pumpAndSettle();
        expect(provider.conceptDraft!.goal, isNot(equals(initialGoal)));

        // Direct 1-Click KV Cell Dropdown on 02 Game Spec updates cell 0 without opening a modal dialog
        final gameCellDropdown = find.byKey(
          const ValueKey('kv_cell_dropdown_game_0'),
        );
        expect(gameCellDropdown, findsOneWidget);
        await tester.ensureVisible(gameCellDropdown);
        await tester.pumpAndSettle();
        await tester.tap(gameCellDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('3D Isometric').last);
        await tester.pumpAndSettle();
        expect(
          provider.conceptDraft!.gameSpec.first,
          contains('3D Isometric'),
        );

        // ── 2. Upgrade 2 (Stage 1 Inline Click-to-Edit without AlertDialog) ──
        final goalCard = find.byKey(
          const ValueKey('stage1_goal_structured_card'),
        );
        await tester.ensureVisible(goalCard);
        await tester.pumpAndSettle();
        await tester.tap(goalCard);
        await tester.pumpAndSettle();

        final inlineGoalInput = find.byKey(
          const ValueKey('stage1_inline_edit_field_goal'),
        );
        expect(inlineGoalInput, findsOneWidget);
        await tester.enterText(
          inlineGoalInput,
          'Build a responsive mech arena prototype where you dash, lock missiles, and extract scrap.',
        );
        await tester.tap(
          find.byKey(const ValueKey('stage1_inline_save_btn_goal')),
        );
        await tester.pumpAndSettle();
        expect(
          provider.conceptDraft!.goal,
          contains('lock missiles, and extract scrap'),
        );

        // ── 3. Upgrade 4: Focused Section "Anytime Build" Header + "Use & Next →" on Option Cards ──
        await tester.tap(find.byKey(const ValueKey('step_node_0')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('section_header_approve_build_btn')),
          findsOneWidget,
        );
        final useAndNextBtn = find.byKey(
          const ValueKey('use_and_next_option_btn_0_0'),
        );
        expect(useAndNextBtn, findsOneWidget);
        await tester.ensureVisible(useAndNextBtn);
        await tester.pumpAndSettle();
        await tester.tap(useAndNextBtn);
        await tester.pumpAndSettle();
        // Advanced immediately to Section 02 / 08
        expect(find.text('SECTION 02 / 08'), findsOneWidget);

        // ── 4. Upgrade 1: 1-Click Express Build v0.1 from Spark ──
        await tester.tap(find.byKey(const ValueKey('new_spark_reset_btn')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('express_build_v01_btn')),
          findsOneWidget,
        );
        final expressFuture = provider.expressBuildReleaseFromSpark(
          'A fast twin-stick cyber-mech arena shooter in Godot 4.',
        );
        await tester.pumpAndSettle();
        await expressFuture;
        await tester.pumpAndSettle();
        expect(provider.currentStage, equals(WorkbenchStage.releaseWorkbench));
        expect(provider.activeReleaseBeats, isNotEmpty);

        // ── 5. Upgrade 2 (Stage 2 Inline Tuning Pill Edit + Cross-Feature Variable Rename) ──
        final allFeats = <TierDocument>[
          for (final b in provider.activeReleaseBeats)
            ...provider.featuresForBeat(b.id),
        ];
        final feat0 = allFeats.first;
        final states0 = FeatureStateNode.getStatesForDocument(feat0);
        final node0 = states0.first;
        node0.tuningParams = ['mechDashSpeed: 650.0'];
        provider.updateFeatureStates(feat0.id, states0);
        await tester.pumpAndSettle();

        final inlineTuningPill = find.byKey(
          ValueKey('inline_tuning_pill_${node0.id}'),
        );
        expect(inlineTuningPill, findsOneWidget);
        await tester.tap(inlineTuningPill);
        await tester.pumpAndSettle();

        final inlineTuningInput = find.byKey(
          ValueKey('inline_tuning_input_${node0.id}'),
        );
        expect(inlineTuningInput, findsOneWidget);
        await tester.enterText(inlineTuningInput, 'boostThrustSpeed: 820.0');
        await tester.tap(
          find.byKey(ValueKey('inline_tuning_save_btn_${node0.id}')),
        );
        await tester.pumpAndSettle();

        final updatedStates0 = FeatureStateNode.getStatesForDocument(feat0);
        expect(
          updatedStates0.first.tuningParams.first,
          equals('boostThrustSpeed: 820.0'),
        );

        // ── 6. Upgrade 3 & 5: 1-Click "⧉ Copy & Next →", "▶ Next Incomplete", and Release Complete Banner ──
        final copyNextBtn = find.byKey(
          ValueKey('copy_and_complete_next_btn_${node0.id}'),
        );
        expect(copyNextBtn, findsOneWidget);
        await tester.ensureVisible(copyNextBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyNextBtn);
        await tester.pumpAndSettle();

        final afterCopyNextStates = FeatureStateNode.getStatesForDocument(feat0);
        expect(
          afterCopyNextStates.first.checklist.first.children.first.completed,
          isTrue,
        );

        // Click the completed first step row in the Left Step List so "▶ Next Incomplete" appears in the Feature Header Bar
        final firstStepRow = find.byKey(
          ValueKey('task_sheet_step_row_${node0.id}_0_0'),
        );
        await tester.ensureVisible(firstStepRow);
        await tester.pumpAndSettle();
        await tester.tap(firstStepRow);
        await tester.pumpAndSettle();
        final resumeNextBtn = find.byKey(
          const ValueKey('resume_next_incomplete_step_btn'),
        );
        expect(resumeNextBtn, findsOneWidget);
        await tester.ensureVisible(resumeNextBtn);
        await tester.pumpAndSettle();
        await tester.tap(resumeNextBtn);
        await tester.pumpAndSettle();

        // Mark all features in v0.1 complete and verify the auto-surfaced Release Complete -> Next Release banner
        for (final f in allFeats) {
          final st = FeatureStateNode.getStatesForDocument(f);
          for (final cp in st) {
            for (final t in cp.checklist) {
              t.completed = true;
              for (final c in t.children) {
                c.completed = true;
              }
            }
          }
          provider.updateFeatureStates(f.id, st);
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('release_complete_next_release_banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('banner_launch_next_release_btn')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '18. Workflow Audit: Zero-Modal Inline Creation & Editing, Smart Return to Workbench, and Interactive Area 2 Inspector Tuning',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final provider = WorkbenchProvider(enableAutoLoad: false);
        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        await provider.startConceptInterview(
          'A fast top-down mech arena shooter in Godot 4.',
        );
        await tester.pumpAndSettle();

        // ── 1. Audit Item 6: Stage 1 Inline Project Title & 09 Progressive Releases Editing ──
        final titleTrigger = find.byKey(
          const ValueKey('stage1_blueprint_title_inline_trigger'),
        );
        expect(titleTrigger, findsOneWidget);
        await tester.ensureVisible(titleTrigger);
        await tester.pumpAndSettle();
        await tester.tap(titleTrigger);
        await tester.pumpAndSettle();

        final titleInput = find.byKey(
          const ValueKey('stage1_inline_edit_field_blueprint_project_title'),
        );
        expect(titleInput, findsOneWidget);
        await tester.enterText(titleInput, 'IRON VANGUARD ARENA');
        await tester.tap(
          find.byKey(
            const ValueKey('stage1_inline_save_btn_blueprint_project_title'),
          ),
        );
        await tester.pumpAndSettle();
        expect(provider.conceptDraft!.title, equals('IRON VANGUARD ARENA'));

        // Inline edit 09 Progressive Releases row 0
        final releaseTrainCard0 = find.byKey(
          const ValueKey('stage1_release_train_card_0'),
        );
        expect(releaseTrainCard0, findsOneWidget);
        await tester.ensureVisible(releaseTrainCard0);
        await tester.pumpAndSettle();
        await tester.tap(releaseTrainCard0);
        await tester.pumpAndSettle();

        final releaseTrainInput0 = find.byKey(
          const ValueKey('stage1_inline_edit_field_release_train_0'),
        );
        expect(releaseTrainInput0, findsOneWidget);
        await tester.enterText(
          releaseTrainInput0,
          'v0.1 Prototype — Dash, Lock-On Missiles & Scrap Pickup',
        );
        await tester.tap(
          find.byKey(
            const ValueKey('stage1_inline_save_btn_release_train_0'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          provider.conceptDraft!.releaseTrainTitles.first,
          contains('Lock-On Missiles & Scrap Pickup'),
        );

        // ── 2. Audit Item 1: Stage 1 Inline "+ Add ..." Rows (without AlertDialog) ──
        final addPillarBtn = find.byKey(
          const ValueKey('section_3_add_pillar_btn'),
        );
        expect(addPillarBtn, findsOneWidget);
        await tester.ensureVisible(addPillarBtn);
        await tester.pumpAndSettle();
        await tester.tap(addPillarBtn);
        await tester.pumpAndSettle();

        final addPillarInput = find.byKey(
          const ValueKey('stage1_inline_edit_field_add_pillar'),
        );
        expect(addPillarInput, findsOneWidget);
        await tester.enterText(
          addPillarInput,
          'Every boost dash feels weighty, decisive, and high-risk.',
        );
        await tester.tap(
          find.byKey(const ValueKey('stage1_inline_save_btn_add_pillar')),
        );
        await tester.pumpAndSettle();
        expect(
          provider.conceptDraft!.designPillars.any(
            (p) => p.contains('weighty, decisive, and high-risk'),
          ),
          isTrue,
        );

        // ── 3. Audit Item 2: Smart Stage 1 -> Stage 2 Return CTA ("✓ Synced · Return to Workbench →") ──
        final approveFuture = provider.approveConceptAndBuildRelease();
        await tester.pumpAndSettle();
        await approveFuture;
        await tester.pumpAndSettle();
        expect(provider.currentStage, equals(WorkbenchStage.releaseWorkbench));
        expect(provider.activeReleaseBeats, isNotEmpty);

        // Switch back to Stage 1 (Concept) and verify Return CTA + Rebuild CTA
        provider.setStage(WorkbenchStage.projectPitch);
        await tester.pumpAndSettle();

        final returnToWorkbenchBtn = find.byKey(
          const ValueKey('return_to_workbench_btn'),
        );
        final rebuildV01Btn = find.byKey(
          const ValueKey('rebuild_v01_from_concept_btn'),
        );
        expect(returnToWorkbenchBtn, findsWidgets);
        expect(rebuildV01Btn, findsWidgets);

        await tester.ensureVisible(returnToWorkbenchBtn.first);
        await tester.pumpAndSettle();
        await tester.tap(returnToWorkbenchBtn.first);
        await tester.pumpAndSettle();
        expect(provider.currentStage, equals(WorkbenchStage.releaseWorkbench));

        // ── 4. Audit Item 3: Stage 2 Inline Feature Creation, Rename & Task Editing ──
        final firstBeat = provider.activeReleaseBeats.first;
        final initialBeatFeatCount =
            provider.featuresForBeat(firstBeat.id).length;

        final addFeatBtn = find.byKey(
          ValueKey('rail_add_feat_to_beat_${firstBeat.id}'),
        );
        expect(addFeatBtn, findsOneWidget);
        await tester.ensureVisible(addFeatBtn);
        await tester.pumpAndSettle();
        await tester.tap(addFeatBtn);
        await tester.pumpAndSettle();

        final addFeatInput = find.byKey(
          const ValueKey('workbench_add_live_feature_input'),
        );
        expect(addFeatInput, findsOneWidget);
        await tester.enterText(addFeatInput, 'Shield Parry');
        await tester.tap(
          find.byKey(const ValueKey('confirm_workbench_add_live_feature_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          provider.featuresForBeat(firstBeat.id).length,
          equals(initialBeatFeatCount + 1),
        );

        // Inline Rename active feature in Feature Header Bar
        final activeFeat = provider.selectedFeature!;
        final renameFeatBtn = find.byKey(
          ValueKey('workbench_rename_feature_btn_${activeFeat.id}'),
        );
        expect(renameFeatBtn, findsOneWidget);
        await tester.tap(renameFeatBtn);
        await tester.pumpAndSettle();

        final renameFeatInput = find.byKey(
          const ValueKey('workbench_rename_live_feature_input'),
        );
        expect(renameFeatInput, findsOneWidget);
        await tester.enterText(renameFeatInput, 'Plasma Shield Parry');
        await tester.tap(
          find.byKey(
            const ValueKey('confirm_workbench_rename_live_feature_btn'),
          ),
        );
        await tester.pumpAndSettle();
        expect(provider.selectedFeature!.title, equals('Plasma Shield Parry'));

        // Inline Edit Task Title in Left Step List
        final states = FeatureStateNode.getStatesForDocument(
          provider.selectedFeature!,
        );
        final node = states.first;
        final editTaskBtn = find.byKey(
          ValueKey('edit_active_task_title_btn_${node.id}_0'),
        );
        expect(editTaskBtn, findsOneWidget);
        await tester.ensureVisible(editTaskBtn);
        await tester.pumpAndSettle();
        await tester.tap(editTaskBtn);
        await tester.pumpAndSettle();

        final editTaskInput = find.byKey(
          const ValueKey('edit_stage3_task_title_input'),
        );
        expect(editTaskInput, findsOneWidget);
        await tester.enterText(editTaskInput, 'Bind Parry Input & Shield Arc');
        await tester.tap(
          find.byKey(const ValueKey('save_stage3_task_title_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(provider.selectedFeature!)
              .first
              .checklist
              .first
              .text,
          equals('Bind Parry Input & Shield Arc'),
        );

        // Inline "+ Add Build Task..." in Left Step List
        final initialTaskCount = FeatureStateNode.getStatesForDocument(
          provider.selectedFeature!,
        ).first.checklist.length;
        final addTaskBtn = find.byKey(
          ValueKey('outline_add_task_btn_${node.id}'),
        );
        expect(addTaskBtn, findsOneWidget);
        await tester.ensureVisible(addTaskBtn);
        await tester.pumpAndSettle();
        await tester.tap(addTaskBtn);
        await tester.pumpAndSettle();

        final addTaskInput = find.byKey(
          const ValueKey('add_stage3_task_title_input'),
        );
        expect(addTaskInput, findsOneWidget);
        await tester.enterText(addTaskInput, 'Trigger Parry Reflect Spark');
        await tester.tap(
          find.byKey(const ValueKey('confirm_add_stage3_task_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(provider.selectedFeature!)
              .first
              .checklist
              .length,
          equals(initialTaskCount + 1),
        );

        // ── 5. Audit Item 4: Interactive Click-to-Tune Row Inside Area 2 Inspector ──
        final area2Row0 = find.byKey(
          ValueKey('area2_inspector_tuning_row_${node.id}_0'),
        );
        expect(area2Row0, findsOneWidget);
        await tester.ensureVisible(area2Row0);
        await tester.pumpAndSettle();
        await tester.tap(area2Row0);
        await tester.pumpAndSettle();

        final area2Input0 = find.byKey(
          ValueKey('area2_inspector_tuning_input_${node.id}_0'),
        );
        expect(area2Input0, findsOneWidget);
        await tester.enterText(area2Input0, 'parryWindowSec: 0.35');
        await tester.tap(
          find.byKey(ValueKey('area2_inspector_tuning_save_${node.id}_0')),
        );
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(provider.selectedFeature!)
              .first
              .tuningParams,
          contains('parryWindowSec: 0.35'),
        );
      },
    );

    test(
      '19. Feature Task Ordering & Shared Asset Continuity: 1-Based taskIndex Alignment and Role-Aware SETUP -> INPUT -> PHYSICS Steps',
      () async {
        final provider = WorkbenchProvider(enableAutoLoad: false);
        await provider.startConceptInterview(
          'First-person parkour roof runner in Unreal Engine 5.',
        );
        provider.updateConceptDraft((d) {
          d.techSpec = ['Unreal Engine 5', '3D First-Person'];
        });
        await provider.approveConceptAndBuildRelease();

        final beat1 = provider.activeReleaseBeats.first;
        final feat = provider.featuresForBeat(beat1.id).first;
        provider.renameLiveFeature(feat.id, 'First Person Locomotion');
        final states = FeatureStateNode.getStatesForDocument(feat);
        states.first
          ..name = 'Basic Locomotion (v0.1)'
          ..tuningParams = ['walkSpeed: 600 cm/s', 'jumpForce: 450 cm/s']
          ..edgeCases = [
            '[COLLISION GUARD] Prevent player clipping into roof geometry',
          ]
          ..checklist = [
            Subtask(id: 't_pawn', text: 'Pawn Setup (2h)'),
            Subtask(id: 't_input', text: 'Input Mapping (2h)'),
            Subtask(id: 't_phys', text: 'Physics Tuning (2h)'),
          ];
        provider.updateFeatureStates(feat.id, states);

        // ── 1. Deterministic Fallback: Shared Asset (BP_LocomotionCharacter) + Role-Aware SETUP -> INPUT -> PHYSICS ──
        TaskHowToBlueprint.clearCache();
        final freshStates = FeatureStateNode.getStatesForDocument(feat);
        final cp = freshStates.first;
        final bp0 = TaskHowToBlueprint.resolve(
          parentTask: cp.checklist[0],
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5',
        );
        final bp1 = TaskHowToBlueprint.resolve(
          parentTask: cp.checklist[1],
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5',
        );
        final bp2 = TaskHowToBlueprint.resolve(
          parentTask: cp.checklist[2],
          taskIndex: 2,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5',
        );

        // Task 1 (Pawn Setup) creates BP_LocomotionCharacter as ACharacter with Capsule + Camera + CharacterMovement
        expect(bp0.subSteps[0].shortTitle, equals('Create BP_LocomotionCharacter'));
        expect(bp0.subSteps[0].codeFormula, contains('Character (ACharacter'));
        expect(bp0.subSteps[1].codeFormula, contains('CapsuleComponent'));
        expect(bp0.subSteps[1].codeFormula, contains('FirstPersonCamera'));
        expect(bp0.subSteps[1].codeFormula, contains('CharacterMovement'));

        // Task 2 (Input Mapping) sets up IA_Move & IMC_Default and wires to AddMovementInput on the SAME BP_LocomotionCharacter
        expect(bp1.subSteps[0].shortTitle, equals('Create IA_Move & IMC_Default'));
        expect(bp1.subSteps[0].codeFormula, contains('BP_LocomotionCharacter (Reuse from Task 01)'));
        expect(bp1.subSteps[1].shortTitle, equals('Register Mapping Context'));
        expect(bp1.subSteps[2].shortTitle, equals('Wire IA_Move to AddMovementInput'));

        // Task 3 (Physics Tuning) tunes CharacterMovement speed, acceleration & velocity on the SAME BP_LocomotionCharacter
        expect(bp2.subSteps[0].shortTitle, equals('Select Movement Component'));
        expect(bp2.subSteps[0].codeFormula, contains('BP_LocomotionCharacter (Reuse from Task 01)'));
        expect(bp2.subSteps[1].shortTitle, equals('Configure Walk Speed & Gravity'));
        expect(bp2.subSteps[2].shortTitle, equals('Wire Physics Momentum Curve'));

        // ── 2. AI Step Synthesis: 1-Based taskIndex (1, 2, 3) Maps Cleanly to checklist[0], [1], [2] with Zero Shift ──
        final prevResponder = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, preferredModel) async {
          if (prompt.contains(
            'Synthesize concrete, beginner-friendly 3-Area Engine How-To steps',
          )) {
            expect(prompt, contains('ONE CANONICAL ASSET ACROSS ALL TASKS'));
            expect(prompt, contains('STRICT TASK-ROLE ALIGNMENT'));
            return <String, dynamic>{
              'tasks': [
                {
                  'taskIndex': 1,
                  'subSteps': [
                    {
                      'title': 'STEP 1.1 · CREATE CHARACTER BLUEPRINT BP_ROOFRUNNER',
                      'stepPath': 'Content Browser → /Game/Blueprints/BP_RoofRunner',
                      'instruction': 'Create BP_RoofRunner inheriting from Character.',
                      'area1Hierarchy': 'BP_RoofRunner (ACharacter)\n └─ CapsuleComponent',
                      'area2Inspector': 'walkSpeed: 600 cm/s',
                      'codeFormula': 'Parent Class: Character (ACharacter)',
                      'verifyResult': 'BP_RoofRunner compiles cleanly.',
                    },
                  ],
                },
                {
                  'taskIndex': 2,
                  'subSteps': [
                    {
                      'title': 'STEP 2.1 · SETUP ENHANCED INPUT MAPPING',
                      'stepPath': 'BP_RoofRunner → Event Graph',
                      'instruction': 'Bind IA_Move and IMC_Default inside BP_RoofRunner.',
                      'area1Hierarchy': '',
                      'area2Inspector': 'walkSpeed: 600 cm/s',
                      'codeFormula': '[IA_Move] ──► [AddMovementInput]',
                      'verifyResult': 'WASD moves BP_RoofRunner in Play mode.',
                    },
                  ],
                },
                {
                  'taskIndex': 3,
                  'subSteps': [
                    {
                      'title': 'STEP 3.1 · TUNE VELOCITY, GRAVITY & COLLISION GUARD',
                      'stepPath': 'BP_RoofRunner → CharacterMovement Details',
                      'instruction': 'Set Max Walk Speed = 600 and Jump Z Velocity = 450.',
                      'area1Hierarchy': '',
                      'area2Inspector': 'walkSpeed: 600 cm/s | jumpForce: 450 cm/s',
                      'codeFormula': 'CharacterMovement->MaxWalkSpeed = walkSpeed;',
                      'verifyResult': 'BP_RoofRunner sprints and jumps without roof clipping.',
                    },
                  ],
                },
              ],
            };
          }
          return prevResponder != null
              ? await prevResponder(prompt, preferredModel)
              : null;
        };

        try {
          await provider.synthesizeFeatureHowToStepsWithAi(
            feat.id,
            forceRefresh: true,
          );
        } finally {
          GeminiAgentClient.testMockResponder = prevResponder;
        }

        final afterAiStates = FeatureStateNode.getStatesForDocument(feat);
        final afterCp = afterAiStates.first;
        // Task 01 (Pawn Setup) got taskIndex 1's steps
        expect(
          afterCp.checklist[0].children.first.text,
          equals('STEP 1.1 · CREATE CHARACTER BLUEPRINT BP_ROOFRUNNER'),
        );
        // Task 02 (Input Mapping) got taskIndex 2's steps (NOT Pawn Setup!)
        expect(
          afterCp.checklist[1].children.first.text,
          equals('STEP 2.1 · SETUP ENHANCED INPUT MAPPING'),
        );
        // Task 03 (Physics Tuning) got taskIndex 3's steps (NOT Input Mapping and NOT dropped!)
        expect(
          afterCp.checklist[2].children.first.text,
          equals('STEP 3.1 · TUNE VELOCITY, GRAVITY & COLLISION GUARD'),
        );

        // ── 3. Foundation-First Task Order & Zero Throwaway Actors ("Chamber Blast" & "Concrete Jungle Run") ──
        final normalizedChamber =
            ReleasePlannerAgent.normalizeFoundationFirstTasks(
          const [
            'Input Mapping (2h)',
            'Velocity Logic (2h)',
            'Friction Tuning (2h)',
          ],
          featureTitle: 'Sprinting Movement',
          beatTitle: 'Core Movement',
          isFirstFeatureOfRelease: true,
        );
        expect(normalizedChamber[0], equals('Character Setup (2h)'));
        expect(normalizedChamber[1], equals('Input & Velocity Logic (2h)'));
        expect(normalizedChamber[2], equals('Friction Tuning (2h)'));

        final normalizedJungle =
            ReleasePlannerAgent.normalizeFoundationFirstTasks(
          const [
            'Input Mapping (2h)',
            'Physics Setup (2h)',
            'Animation Blend (2h)',
          ],
          featureTitle: 'Player Sprint Slide',
          beatTitle: 'Dash and Slide',
          isFirstFeatureOfRelease: true,
        );
        expect(normalizedJungle[0], equals('Character Setup (2h)'));
        expect(normalizedJungle[1], equals('Input & Physics Logic (2h)'));
        expect(normalizedJungle[2], equals('Animation Blend (2h)'));

        // Even if a saved project has Task 1 = "Input Mapping (2h)", TaskHowToBlueprint never creates
        // a throwaway BP_InputMapping... Actor; Task 1 creates IA_Move & IMC_Default, Task 2 creates
        // BP_PlayerCharacter, and Task 3 tunes BP_PlayerCharacter!
        final slideCp = FeatureStateNode(
          id: 'cp_slide',
          name: 'Movement (v0.1)',
          trigger: 'Press slide -> character slides',
          order: 0,
          tuningParams: const ['slideSpeed: 1200 cm/s', 'frictionDecay: 0.8'],
          edgeCases: const ['[COOLDOWN] Prevent slide spam'],
          checklist: [
            Subtask(id: 's_1', text: 'Input Mapping (2h)'),
            Subtask(id: 's_2', text: 'Physics Setup (2h)'),
            Subtask(id: 's_3', text: 'Animation Blend (2h)'),
          ],
        );
        TaskHowToBlueprint.clearCache();
        final slideBp0 = TaskHowToBlueprint.resolve(
          parentTask: slideCp.checklist[0],
          taskIndex: 0,
          checkpointNode: slideCp,
          engineHint: 'Unreal Engine 5',
        );
        final slideBp1 = TaskHowToBlueprint.resolve(
          parentTask: slideCp.checklist[1],
          taskIndex: 1,
          checkpointNode: slideCp,
          engineHint: 'Unreal Engine 5',
        );
        final slideBp2 = TaskHowToBlueprint.resolve(
          parentTask: slideCp.checklist[2],
          taskIndex: 2,
          checkpointNode: slideCp,
          engineHint: 'Unreal Engine 5',
        );
        expect(
          slideBp0.subSteps[0].shortTitle,
          equals('Create IA_Move & IMC_Default'),
        );
        expect(
          slideBp0.subSteps[0].shortTitle.contains('BP_InputMapping'),
          isFalse,
        );
        expect(
          slideBp1.subSteps[0].shortTitle,
          equals('Create BP_PlayerCharacter'),
        );
        expect(
          slideBp2.subSteps[0].codeFormula,
          contains('BP_PlayerCharacter'),
        );
      },
    );

    test(
      'Pass 3 Multi-Release Integrity: Release-Scoped Feature Visibility (v0.1 <-> v0.2), Reload Checkpoint Preservation & Progressive Option 0 Restore',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('Neon Mech Arena');
        await provider.approveConceptAndBuildRelease();

        final v01RelId = provider.activeReleaseId!;
        final v01Beats = provider.activeReleaseBeats;
        expect(v01Beats, isNotEmpty);
        final firstBeat = v01Beats.first;
        final v01Feats = provider.featuresForBeat(firstBeat.id);
        expect(v01Feats, isNotEmpty);
        final featA = v01Feats.first;

        // Prepare v0.2 Progressive Release Draft and test Option 0 snapshot restoration
        final draftBp = await provider.prepareProgressiveNextReleaseDraft();
        expect(draftBp, isNotNull);
        final initialGoal = draftBp!.goal;
        draftBp.goal = 'Mutated Option 1 Strategic Goal';
        provider.restoreInitialProgressiveDraftBlueprint();
        expect(provider.releaseBlueprint!.goal, equals(initialGoal));

        // Add a brand-new v0.2 feature to Beat 1, keep featA as UPGRADE (or STABLE), and build v0.2
        provider.addCustomFeatureToProposedBeat(
          firstBeat.id,
          'Overheat Vent Shield',
        );
        await provider.approveAndExecuteReleasePlan();

        final v02RelId = provider.activeReleaseId!;
        expect(v02RelId, isNot(equals(v01RelId)));

        final allBeatFeatsAfterV02 = provider.featuresForBeat(firstBeat.id);
        final newV02Feat = allBeatFeatsAfterV02.firstWhere(
          (f) => f.title == 'Overheat Vent Shield',
        );

        // Ensure featA has both v0.1 and v0.2 checkpoints (or mark a second v0.1 feature stable in v0.2)
        final featAStates = FeatureStateNode.getStatesForDocument(featA);
        if (featAStates.length < 2) {
          featA.sections['lifecycle'] = FeatureLifecycleStatus.upgrade.name;
          featA.sections['activeReleaseVersion'] = 'v0.2';
          featAStates.add(
            FeatureStateNode(
              id: '${featA.id}_v0.2_cp_2',
              name: 'Checkpoint 2: ${featA.title} Upgrade (v0.2)',
              trigger: 'Playtest v0.2 upgrade',
              order: 1,
              checklist: [
                Subtask(id: 'u_1', text: 'Upgrade tuning (2h)', completed: false),
              ],
              parameters: const {'releaseVersion': 'v0.2'},
            ),
          );
          provider.updateFeatureStates(featA.id, featAStates);
        }

        // In v0.2: newV02Feat is active; in v0.1: newV02Feat was not yet created so it is inactive!
        expect(provider.isFeatureActiveInRelease(newV02Feat, 'v0.2'), isTrue);
        expect(provider.isFeatureActiveInRelease(newV02Feat, 'v0.1'), isFalse);
        expect(provider.isFeatureActiveInRelease(featA, 'v0.1'), isTrue);
        expect(provider.isFeatureActiveInRelease(featA, 'v0.2'), isTrue);

        // Switch back to v0.1 and trigger project state reload/switch: v0.2 checkpoint on featA MUST NOT be wiped!
        await provider.selectActiveRelease(v01RelId);
        expect(provider.activeReleaseVersionTag, equals('v0.1'));
        expect(provider.isFeatureActiveInRelease(newV02Feat), isFalse);
        expect(provider.isFeatureActiveInRelease(featA), isTrue);

        final activeProjId = provider.activeProjectId!;
        provider.switchProject(activeProjId);
        final statesAfterReloadOnV01 =
            FeatureStateNode.getStatesForDocument(provider.documents[featA.id]!);
        expect(
          statesAfterReloadOnV01.any((s) => s.releaseVersion == 'v0.2'),
          isTrue,
          reason:
              'Reloading project state while viewing v0.1 must never wipe v0.2+ checkpoints',
        );
      },
    );
  });
}
