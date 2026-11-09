import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/agents/project_concept_agent.dart';
import 'package:layers_agentic/agents/release_planner_agent.dart';
import 'package:layers_agentic/constants/text_style_guide.dart';
import 'package:layers_agentic/constants/tiers.dart';
import 'package:layers_agentic/main.dart';
import 'package:layers_agentic/models/agent_blueprints.dart';
import 'package:layers_agentic/models/feature_state.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/project_pitch_screen.dart';
import 'package:layers_agentic/utils/section_text_utils.dart';

Future<Map<String, dynamic>?> _mockGeminiResponder(
  String prompt,
  String preferredModel,
) async {
  // 1. Stage 1A: refreshSparkExpansionCards
  if (prompt.contains('proposing 3 NEW gameplay expansion / twist cards')) {
    final titleMatch = RegExp(r'Working Title: "([^"]+)"').firstMatch(prompt);
    final wTitle = titleMatch?.group(1) ?? 'Game Concept';
    return {
      'expansionCards': [
        {
          'badge': '01 · CORE MECHANIC TWIST',
          'title': 'Chain Combo Surge',
          'description':
              'Chain rapid actions inside $wTitle for a speed boost.',
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
    if (prompt.contains(
        'Selected Idea Additions to Fold In: Wall-Run Chain & Vault Boost')) {
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
            'description':
                'Stay longer in hostile zones for higher credit bounties.',
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
            'description':
                'Double-brew volatile toppings in Cozy Pizza Alchemy.',
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
      'reply':
          'Updated Concept Blueprint to 2D Side-Scrolling Precision Platformer.',
      'updatedFields': ['Goal'],
      'goal':
          '2D Side-Scrolling Precision Platformer: Build a responsive 2D Side-Scrolling Precision Platformer prototype with grappling hook swing and wall-run chains.',
    };
  }

  // 6. Stage 1B: startConceptInterview
  if (prompt
      .contains('creating a Stage 1 Concept Blueprint for this spark idea:')) {
    final isFarm = prompt.toLowerCase().contains('cozy alchemy shop');
    final isCourier = prompt.toLowerCase().contains('supply courier');
    return {
      'title': isFarm
          ? 'Cozy Alchemy Shop'
          : (isCourier
              ? 'Settlement Supply Courier'
              : 'Grapple Parkour Roguelite'),
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
    final isPart2 = prompt.contains('PHASE 1 SPLIT PROTOTYPE (PART 2 OF 2') ||
        prompt.contains('planning Release: "v0.2: Prototype — Part 2');
    final isMvp =
        prompt.contains('PHASE 2 PER-EPIC MVP RELEASE (TARGET: EPIC ') &&
            !prompt.contains('Grapple Momentum Release');
    final isVerticalSlice = prompt.contains('PHASE 3 VERTICAL SLICE');
    final isFullProd = prompt.contains('PHASE 4 FULL PRODUCTION');
    final isFirstRelease =
        prompt.contains('First Release (v0.1): No prior features exist yet.');

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
                'playtestCriteria':
                    'Press input -> actor responds within 100ms',
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
                'playtestCriteria':
                    'Detach mid-swing -> player launches forward',
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
                      'playtestCriteria':
                          'Chain movement -> speed bonus active',
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

  if (prompt.contains(
      'Choose 1 to 3 surgical workspace tool calls to fulfill the directive.')) {
    final activeIdMatch =
        RegExp(r'Active Feature: "[^"]+" \(id: ([^)]+)\)').firstMatch(prompt);
    final activeId = activeIdMatch?.group(1) ?? 'feat_1_1';
    final sibIdMatch =
        RegExp(r'Sibling Features in Release: ([^\s]+)').firstMatch(prompt);
    final sibId = sibIdMatch?.group(1) ?? activeId;
    return {
      'reasoning':
          'Synchronized tuning parameters across active and coupled sibling features.',
      'toolCalls': [
        {
          'toolName': 'rebalance_tuning_params',
          'targetTitle': 'Active Feature',
          'summary':
              'Injected coyote_time_ms and response_window_ms tuning variables',
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
          'summary':
              'Synchronized coupled_sync_window_ms: 90 ms on sibling feature',
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

  if (prompt.contains(
      'Synthesize concrete, beginner-friendly 3-Area Engine How-To steps')) {
    return null;
  }

  if (prompt.contains('Tailor this newly added Feature')) {
    return {
      'goal': 'Build zipline anchor attach and momentum release mechanics.',
      'doneWhen':
          'Player attaches to zipline and detaches cleanly in playtest.',
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
      GeminiAgentClient.resetUsage();
      GeminiAgentClient.testMockResponder = _mockGeminiResponder;
    });

    tearDown(() {
      GeminiAgentClient.testMockResponder = null;
      GeminiAgentClient.resetUsage();
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

    test(
        'ProjectConceptAgent seeds turn-by-turn chat and updates Live Concept Blueprint on each turn',
        () async {
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
      expect(
          crabDraft.goal.toLowerCase(), isNot(contains('instead of a crab')));
      expect(crabDraft.coreLoopBeats.first.toLowerCase(),
          isNot(contains('instead of a crab')));
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

        // ── Stage 1A: Single-Input 80-Character Word Document Composer (00 · PITCH & CONCEPT) ──
        expect(find.byKey(const ValueKey('connected_pipeline_track')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('rail_concept_blueprint_btn')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('rail_pre_release_empty_state')),
            findsOneWidget);
        expect(find.text('00 · PITCH & CONCEPT'), findsOneWidget);
        expect(
            find.byKey(const ValueKey('spark_composer_card')), findsOneWidget);
        // Only ONE TextField is rendered in Step 1A
        expect(find.byType(TextField), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_input_field')), findsOneWidget);
        expect(find.byKey(const ValueKey('ingest_idea_summary_btn')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('direct_generate_blueprint_btn')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('spark_committed_pitch_text')),
            findsNothing);
        expect(find.byKey(const ValueKey('spark_undo_btn')), findsNothing);

        // Verify dynamic tooltip & hint when empty ('Input your game idea...')
        final emptyPitchTooltip = tester.widget<Tooltip>(
          find.byKey(const ValueKey('spark_pitch_tooltip')),
        );
        expect(emptyPitchTooltip.message, contains('Input your game idea'));
        final initialSparkField = tester.widget<TextField>(
          find.byKey(const ValueKey('spark_input_field')),
        );
        expect(
          initialSparkField.decoration?.hintText,
          contains('Input your game idea'),
        );

        // Verify 80-character line wrapping and Shift+Enter line skipping in the single input
        const longPitch =
            'A high-speed grappling hook parkour roguelite where players swing across floating ruins and chain aerial combos';
        final wrappedPitch = MaxColumnLineWrapFormatter.wrapTextAtColumn(
          longPitch,
          maxCharsPerLine: 80,
        );
        expect(wrappedPitch.split('\n').length, greaterThan(1));
        for (final line in wrappedPitch.split('\n')) {
          expect(line.length, lessThanOrEqualTo(80));
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
          expect(line.length, lessThanOrEqualTo(80));
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
        expect(
            sparkField.controller!.text, equals('High-speed grappling hook\n'));
        expect(find.byKey(const ValueKey('spark_committed_pitch_text')),
            findsNothing);

        // Submit initial game idea via Return icon (↵) -> displays clean document text above
        // and switches the SAME single input area to 'Input to refine...'
        await tester.enterText(
          find.byKey(const ValueKey('spark_input_field')),
          'High-speed grappling hook parkour roguelite',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('ingest_idea_summary_btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('spark_committed_pitch_text')),
            findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(sparkField.controller!.text, isEmpty);
        final refineTooltip = tester.widget<Tooltip>(
          find.byKey(const ValueKey('spark_pitch_tooltip')),
        );
        expect(refineTooltip.message, contains('Input to refine'));
        final refineSparkField = tester.widget<TextField>(
          find.byKey(const ValueKey('spark_input_field')),
        );
        expect(
          refineSparkField.decoration?.hintText,
          contains('Input to refine'),
        );

        // Use the SAME single input field to refine the pitch -> updates document text and reveals Undo
        await tester.enterText(
          find.byKey(const ValueKey('spark_input_field')),
          'Add wall-run chains',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('ingest_idea_summary_btn')));
        await tester.pumpAndSettle();

        expect(find.textContaining('wall-run chains'), findsWidgets);
        expect(find.byKey(const ValueKey('spark_undo_btn')), findsOneWidget);

        // Verify Undo reverts to the previous summary in one click
        await tester.tap(find.byKey(const ValueKey('spark_undo_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('spark_undo_btn')), findsNothing);

        // Explicitly click "Generate Concept Blueprint →" to launch Stage 1B (Sections 01–08)
        await tester
            .tap(find.byKey(const ValueKey('direct_generate_blueprint_btn')));
        await tester.pumpAndSettle();

        // ── Stage 1B: Full-Width Single-Page Concept Blueprint (All 9 Sections Together, Zero Left Stepper Rail) ──
        expect(find.byKey(const ValueKey('project_blueprint_card')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_left_outliner_rail')),
            findsNothing);
        expect(find.byKey(const ValueKey('top_bar_project_title')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('project_switcher_dropdown_btn')),
            findsOneWidget);
        expect(
            find.byKey(const ValueKey('cloud_sync_auth_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('global_export_spec_btn')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('concept_interview_card')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('concept_sticky_bottom_dock')),
            findsOneWidget);
        expect(
            find.byKey(const ValueKey('new_spark_reset_btn')), findsOneWidget);
        expect(find.text('+ New Project'), findsOneWidget);
        expect(find.byKey(const ValueKey('blueprint_twist_pills_bar')),
            findsOneWidget);

        // Verify clean 1-sentence Goal card (no redundant bottom clause rows)
        expect(find.byKey(const ValueKey('stage1_goal_structured_card')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_goal_clause_card_0')),
            findsNothing);

        // Verify opening the Refine drawer on Section 01 shows option cards, applies an option, and restores the default Goal
        final refineGoalBtn =
            find.byKey(const ValueKey('refine_drawer_toggle_btn_0'));
        await tester.ensureVisible(refineGoalBtn);
        await tester.pumpAndSettle();
        await tester.tap(refineGoalBtn);
        await tester.pumpAndSettle();

        final initialGoal = provider.conceptDraft!.goal;
        final goalPill1 = find.byKey(const ValueKey('compact_option_pill_0_1'));
        await tester.ensureVisible(goalPill1);
        await tester.pumpAndSettle();
        await tester.tap(goalPill1);
        await tester.pumpAndSettle();
        expect(provider.conceptDraft!.goal, isNot(equals(initialGoal)));
        await tester.tap(goalPill1);
        await tester.pumpAndSettle();
        expect(provider.conceptDraft!.goal, equals(initialGoal));

        // Verify 02 Game Spec and 03 Tech Spec 2x2 KV grid labels are visible together on the Single-Page Blueprint
        expect(find.text('CAMERA VIEW'), findsOneWidget);
        expect(find.text('CONTROLS'), findsOneWidget);
        expect(find.text('ENGINE'), findsOneWidget);
        expect(find.text('PLATFORM'), findsOneWidget);

        // Verify 04 Design Pillars & multi-select Refine drawer (opening Section 04 closes Section 01 drawer)
        expect(find.text('DESIGN PILLARS'), findsOneWidget);
        expect(find.textContaining('Load-Bearing'), findsNothing);
        final refinePillarsBtn =
            find.byKey(const ValueKey('refine_drawer_toggle_btn_3'));
        await tester.ensureVisible(refinePillarsBtn);
        await tester.pumpAndSettle();
        await tester.tap(refinePillarsBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('refine_drawer_container_0')),
          findsNothing,
        );

        final pillarPill0 =
            find.byKey(const ValueKey('compact_option_pill_3_0'));
        final pillarPill1 =
            find.byKey(const ValueKey('compact_option_pill_3_1'));
        await tester.ensureVisible(pillarPill0);
        await tester.pumpAndSettle();
        await tester.tap(pillarPill0);
        await tester.pumpAndSettle();
        await tester.tap(pillarPill1);
        await tester.pumpAndSettle();
        expect(
          provider.conceptDraft!.designPillars.join(' '),
          contains('Unbroken Momentum'),
        );
        expect(
          provider.conceptDraft!.designPillars.join(' '),
          contains('Tactical Positioning'),
        );

        // Verify Full Blueprint Review header & Release Train
        expect(find.text('RELEASE TARGET'), findsOneWidget);
        expect(find.text('v0.1: Core Movement & Game Loop - Prototype'),
            findsOneWidget);
        expect(find.text('1. Concept'), findsOneWidget);
        expect(find.text('2. Workbench'), findsOneWidget);
        expect(find.text('2. Release Plan'), findsNothing);

        // Clicking "Approve & Build v0.1 →" builds v0.1 and jumps directly into 2. Workbench (2-Stage Workflow)
        final approveConceptBtn =
            find.byKey(const ValueKey('approve_concept_plan_release_btn'));
        await tester.ensureVisible(approveConceptBtn);
        await tester.pumpAndSettle();
        await tester.tap(approveConceptBtn);
        await tester.pumpAndSettle();
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);

        // Verify all 7 Stage 1 Core Loop Beats map 1-to-1 into the Release Blueprint (8 included features across 7 beats)
        expect(provider.releaseBlueprint!.beats.length, 7);
        expect(provider.releaseBlueprint!.totalIncludedFeatures, 8);
        expect(provider.releaseBlueprint!.totalDeferredFeatures, 0);
        final firstProposedFeat =
            provider.releaseBlueprint!.beats.first.features.first;
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
        expect(find.byKey(const ValueKey('outline_release_eta_summary')),
            findsOneWidget);
        final firstBeatId = provider.activeReleaseBeats.first.id;
        expect(find.byKey(ValueKey('rail_beat_$firstBeatId')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage3_active_feature_sheet')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_single_col_0')),
            findsOneWidget);
        expect(
            find.textContaining('Arena Entry & Traversal Mechanics & Controls'),
            findsWidgets);

        // The Pinned Active Step Window is always visible at the top of the work area in Single-Panel mode
        final activeFeat0 = provider.selectedFeature!;
        final cp0NodeId = provider.documents[activeFeat0.id]!.subtasks.first.id;
        expect(find.byKey(ValueKey('pinned_active_step_window_$cp0NodeId')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_spec_pane_0')),
            findsOneWidget);

        // Verify clicking Concept Blueprint in the Left Rail swaps the Main Canvas to the Concept Blueprint,
        // and clicking the Feature row in the Left Rail swaps back to the Feature Step Runbook!
        await tester.tap(
          find.byKey(const ValueKey('rail_concept_blueprint_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('project_blueprint_card')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('stage3_active_feature_sheet')),
            findsNothing);

        await tester.tap(find.byKey(ValueKey('rail_feat_${activeFeat0.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('stage3_active_feature_sheet')),
            findsOneWidget);

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
        final secondCp0NodeId =
            provider.documents[secondFeat.id]!.subtasks.first.id;
        // Verify Single-Row Outliner Header live Release ETA summary ("12h Left #%")
        expect(find.byKey(const ValueKey('outline_release_eta_summary')),
            findsOneWidget);

        // Verify Next → starts locked (onTap == null) while Step 1 is unchecked
        final secondTask0Steps = provider.documents[secondFeat.id]!.subtasks
            .first.children.first.children.length;
        final nextBtnBefore = tester.widget<InkWell>(
          find.byKey(ValueKey('next_active_step_btn_$secondCp0NodeId')),
        );
        expect(nextBtnBefore.onTap, isNull);
        expect(find.textContaining('STEP 1 OF $secondTask0Steps · ~'),
            findsOneWidget);
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

        // Verify the step mark badge [1] / [✓] on the active step row checks and unchecks directly
        final stepMarkFinder = find.byKey(
          ValueKey('toggle_step_mark_${secondCp0NodeId}_0_0'),
        );
        expect(stepMarkFinder, findsOneWidget);
        await tester.ensureVisible(stepMarkFinder);
        await tester.pumpAndSettle();
        await tester.tap(stepMarkFinder);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[secondFeat.id]!,
          ).first.checklist.first.children.first.completed,
          isTrue,
        );
        await tester.tap(stepMarkFinder);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[secondFeat.id]!,
          ).first.checklist.first.children.first.completed,
          isFalse,
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
        expect(find.textContaining('STEP 1 OF $secondTask0Steps · ~'),
            findsOneWidget);
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
        expect(find.textContaining('STEP 2 OF $secondTask0Steps · ~'),
            findsOneWidget);

        // Verify clicking the task chevron in the Outliner expands Task 02 for peeking without losing Step 2 in the workspace
        final task1ChevronFinder = find.byKey(
          ValueKey('outline_task_chevron_${secondCp0NodeId}_1'),
        );
        if (task1ChevronFinder.evaluate().isNotEmpty) {
          await tester.tap(task1ChevronFinder);
          await tester.pumpAndSettle();
          expect(find.textContaining('STEP 2 OF $secondTask0Steps · ~'),
              findsOneWidget);
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
        expect(find.textContaining('STEP 1 OF $secondTask0Steps · ~'),
            findsOneWidget);

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
        final copyCodeBtn =
            find.byKey(ValueKey('copy_howto_code_${cp0Id}_0_0'));
        await tester.ensureVisible(copyCodeBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyCodeBtn);
        await tester.pumpAndSettle();

        // Verify 1-Click "⧉ Copy All Code" in the Task Sheet header copies all task code snippets
        final copyAllCodeBtn =
            find.byKey(ValueKey('copy_all_task_code_btn_${cp0Id}_0'));
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
        await tester
            .tap(find.byKey(const ValueKey('confirm_tailor_howto_btn')));
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

        // Verify Editorial Runbook layout:
        // 1. Only the focused Task (Task 0) displays its GOAL & DONE rows and its Steps
        expect(
          find.byKey(ValueKey('task_overview_goal_box_${cp0Id}_0')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('task_overview_goal_box_${cp0Id}_1')),
          findsNothing,
        );
        expect(find.text('DONE'), findsWidgets);
        expect(find.text('✓ DONE:'), findsNothing);
        expect(find.text('Done'), findsWidgets);
        expect(find.text('✓ Done & Next →'), findsNothing);
        // 2. Only the focused Task (Task 0) expands its Steps
        expect(
          find.byKey(ValueKey('task_sheet_step_row_${cp0Id}_0_0')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('task_sheet_step_row_${cp0Id}_1_0')),
          findsNothing,
        );

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

        // Resize to Half-Width (720px) and verify Companion Sidecar Context Bar + Step Dropdown + Auto-Closing Drawer
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
        expect(
          find.byKey(
            ValueKey('halfscreen_feature_actions_menu_btn_${activeFeat.id}'),
          ),
          findsOneWidget,
        );
        expect(find.text('Done & Next →'), findsOneWidget);

        // Open Slide-Over Outliner Drawer and verify selecting a feature automatically closes it
        await tester.tap(
          find.byKey(ValueKey('halfscreen_outliner_trigger_$cp0Id')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('halfscreen_outliner_scrim')),
          findsOneWidget,
        );
        final railFeatFinder = find.byKey(ValueKey('rail_feat_${activeFeat.id}'));
        await tester.ensureVisible(railFeatFinder);
        await tester.pumpAndSettle();
        await tester.tap(railFeatFinder);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('halfscreen_outliner_scrim')),
          findsNothing,
        );

        // Verify Google Account & Cloud Sync Badge and Dialog
        final cloudSyncBtn = find.byKey(const ValueKey('cloud_sync_auth_btn'));
        expect(cloudSyncBtn, findsOneWidget);
        await tester.ensureVisible(cloudSyncBtn);
        await tester.pumpAndSettle();
        await tester.tap(cloudSyncBtn);
        await tester.pumpAndSettle();
        expect(find.text('Firebase Cloud Sync & Local Vault'), findsOneWidget);
        expect(find.byKey(const ValueKey('google_sign_in_modal_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('cloud_sync_now_btn')), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        // Verify Project JSON Export and Import Roundtrip
        final exportedJson = provider.exportProjectToJson();
        expect(exportedJson.isNotEmpty, isTrue);
        expect(exportedJson.contains('format'), isTrue);
        final importedId = provider.importProjectFromJson(exportedJson);
        expect(importedId != null, isTrue);
        expect(provider.savedProjects.any((p) => p.id == importedId), isTrue);

        // Verify Playtest Bug button is visible on the active step action bar
        final playtestFeat = provider.selectedFeature!;
        final playtestStates = FeatureStateNode.getStatesForDocument(playtestFeat);
        final cpNode = playtestStates.first;
        final stepBugBtn = find.byKey(ValueKey('feature_step_log_bug_btn_${cpNode.id}'));
        expect(stepBugBtn, findsOneWidget);

        // Tap the Step Bug button to open the Playtest Bug modal
        await tester.ensureVisible(stepBugBtn);
        await tester.pumpAndSettle();
        await tester.tap(stepBugBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('workbench_log_playtest_issue_input')), findsOneWidget);
        expect(find.byKey(const ValueKey('confirm_workbench_log_playtest_issue_btn')), findsOneWidget);

        // Enter a bug description and submit
        await tester.enterText(
          find.byKey(const ValueKey('workbench_log_playtest_issue_input')),
          'Elevator drops player through floor collision',
        );
        await tester.tap(find.byKey(const ValueKey('confirm_workbench_log_playtest_issue_btn')));
        await tester.pumpAndSettle();

        // Verify [FIX] task is appended to checkpoint checklist
        final updatedStates = FeatureStateNode.getStatesForDocument(playtestFeat);
        final updatedCp = updatedStates.first;
        final hasFixTask = updatedCp.checklist.any((t) => t.text.contains('[FIX] Elevator drops player'));
        expect(hasFixTask, isTrue);

        // Verify [PLAYTEST GUARD] is added to edge cases
        final hasPlaytestGuard = updatedCp.edgeCases.any((g) => g.contains('Elevator drops player'));
        expect(hasPlaytestGuard, isTrue);
      },
    );

    test(
      'Evolving from Release v0.1 to v0.2 preserves STABLE features (0h delta) and appends v0.2 checkpoints to UPGRADE features',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview(
            'High-speed grappling hook parkour roguelite');
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
        expect(
            v1FirstFeat.title, 'Arena Entry & Traversal Mechanics & Controls');

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
        // Because v0.2 only upgraded Beat 1 out of 7 Beats, v0.3 stays in MVP (Pass 2) rather than prematurely jumping to Vertical Slice!
        expect(
          provider.releasePhaseFor(allRels[2]),
          ProductionPhase.mvp,
        );
        expect(
          provider.releaseConciseLabel(allRels[2]),
          'MVP (Pass 2)',
        );
        expect(
          provider.inferNextProgressivePhase(),
          ProductionPhase.mvp,
        );

        // Once all Core Loop Epics receive MVP coverage, inferNextProgressivePhase() advances to Vertical Slice,
        // stays in Vertical Slice across partial passes, and only graduates to Full Production once all Epics are polished!
        for (final beat in liveBeats) {
          for (final feat in provider.featuresForBeat(beat.id)) {
            final st = FeatureStateNode.getStatesForDocument(feat);
            if (!st.any((s) =>
                s.releaseVersion == 'v0.2' || s.releaseVersion == 'v0.3')) {
              st.add(
                FeatureStateNode(
                  id: '${feat.id}_v0.3_mvp',
                  name: 'Checkpoint 2: ${feat.title} MVP',
                  trigger: 'Playtest MVP',
                  order: st.length,
                  checklist: [
                    Subtask(id: 'm1', text: 'MVP Task (2h)', completed: true)
                  ],
                  parameters: const {'releaseVersion': 'v0.3'},
                ),
              );
              provider.updateFeatureStates(feat.id, st);
            }
          }
        }
        expect(provider.mvpBeatCoverage().isComplete, isTrue);
        expect(
          provider.inferNextProgressivePhase(),
          ProductionPhase.verticalSlice,
        );

        // Verify that executing a v0.4 blueprint with a + NEW feature placed before an existing STABLE feature never collides feature IDs or duplicates beatDoc.childrenIds
        final firstEpic = liveBeats.first;
        final existingFeatIdsBefore = List<String>.from(firstEpic.childrenIds);
        expect(
          existingFeatIdsBefore.toSet().length,
          existingFeatIdsBefore.length,
        );
        final v4Reconciled =
            ReleasePlannerAgent.reconcileReleaseBlueprintWithPhaseRules(
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
        await provider
            .startConceptInterview('Tactical Mecha Extraction Shooter');
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

        await provider
            .startConceptInterview('Cozy Alchemy Shop & Dungeon Forager');
        final proj3Id = provider.activeProjectId!;
        expect(provider.savedProjects.length, 3);

        // Delete the duplicated project
        provider.deleteProject(dupId);
        expect(provider.savedProjects.length, 2);

        // Switch back to Project 1 and verify Stage 1, 2, and 3 state restored from JSON metadata
        provider.switchProject(proj1Id);
        expect(provider.activeProjectId, proj1Id);
        expect(provider.conceptDraft!.sparkIdea,
            'Tactical Mecha Extraction Shooter');
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
        expect(godotBp.subSteps[4].codeFormula,
            contains('Input.is_action_pressed'));
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
        expect(
            unityBp.subSteps[4].codeFormula, contains('Time.fixedDeltaTime'));

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
        expect(unrealBp.subSteps[0].codeFormula,
            contains('EMechanicState::Active'));
        expect(unrealBp.subSteps[0].explainConcept, contains('BP_'));
        expect(unrealBp.subSteps[0].specChips,
            contains('Next: ${unrealBp.subSteps[1].shortTitle}'));
        expect(unrealBp.subSteps[4].codeFormula,
            contains('FMath::FInterpConstantTo'));

        final unrealCpp = TaskHowToBlueprint.resolve(
          parentTask: unrealTask,
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
          unrealCppMode: true,
        );
        expect(unrealCpp.engineLabel, 'UNREAL 5');
        expect(unrealCpp.whereLocation, contains('ActorComponent'));
        expect(unrealCpp.subSteps[0].explainConcept,
            contains('AWasdMovementDash'));
        expect(unrealCpp.subSteps[3].codeFormula,
            contains('UPROPERTY(EditAnywhere'));
        expect(unrealCpp.subSteps[4].codeFormula,
            contains('FMath::FInterpConstantTo'));

        // Verify custom_snippet C++ code adapts to Blueprint node chain when unrealCppMode == false
        final customRampTask = Subtask(
          id: 'custom_ramp',
          text: 'Dock Collision Bounds',
          children: [
            Subtask(
              id: 'custom_ramp_s1',
              text: 'Spawn Cargo Delivery Ramp',
              specNotes:
                  'Spawn cargo ramp StaticMeshActor in dock arena and set pitch rotation to rampInclineAngle: 25.0 deg.',
              codeTargetFile: 'custom_snippet',
              codeSnippet: '''// Place cargo ramp actor aligned to dock apron
FTransform RampTransform(FRotator(25.0f, 0.0f, 0.0f), FVector(1200.f, -400.f, 0.f), FVector(4.f, 3.f, 1.5f));
Ramp_CargoDelivery->SetActorTransform(RampTransform);
Ramp_CargoDelivery->GetStaticMeshComponent()->SetCollisionProfileName(TEXT("BlockAll"));''',
            ),
          ],
        );
        final resolvedRampBp = TaskHowToBlueprint.resolve(
          parentTask: customRampTask,
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5',
          unrealCppMode: false,
        );
        final resolvedRampCpp = TaskHowToBlueprint.resolve(
          parentTask: customRampTask,
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5',
          unrealCppMode: true,
        );
        expect(
          resolvedRampBp.subSteps.first.codeFormula,
          contains('[Make Transform'),
        );
        expect(
          resolvedRampBp.subSteps.first.codeFormula,
          contains('[Set Actor Transform (Target: Ramp_CargoDelivery'),
        );
        expect(
          resolvedRampBp.subSteps.first.codeFormula,
          contains('[Set Collision Profile Name'),
        );
        expect(
          resolvedRampCpp.subSteps.first.codeFormula,
          contains('Ramp_CargoDelivery->SetActorTransform(RampTransform);'),
        );
        expect(
          resolvedRampBp.subSteps.first.codeFormula,
          isNot(equals(resolvedRampCpp.subSteps.first.codeFormula)),
        );

        // Verify custom_snippet Blueprint node chain (Smoke Beacon Marker) adapts to real Unreal C++ when unrealCppMode == true
        final customBeaconTask = Subtask(
          id: 'custom_beacon',
          text: 'Beacon Collision Hull',
          children: [
            Subtask(
              id: 'custom_beacon_s1',
              text: 'Configure Flare Mesh Collision',
              specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
                instruction:
                    'Configure FlareCylinderMesh physics collision and position ScorchDecal onto ground pavement upon first rigid body contact.',
                area1Hierarchy:
                    'BP_DropFlareBeacon (Actor)\n└─ SceneRoot (DefaultSceneRoot)\n   ├─ FlareCylinderMesh (StaticMeshComponent)',
                area2Inspector:
                    'Simulate Physics: True | Collision Profile: BlockAllDynamic',
              ),
              codeTargetFile: 'custom_snippet',
              codeSnippet: '''[FlareCylinderMesh (OnComponentHit)]
└──► [LineTraceByChannel (Start: HitLocation, End: HitLocation - (0,0,150), TraceChannel: ECC_Visibility)]
└──► [Branch (Is Hit Valid)]
   ├──► [Set World Location (Target: ScorchDecal, NewLocation: TraceHitLocation)]
   └──► [Set Visibility (Target: ScorchDecal, NewVisibility: True)]''',
            ),
          ],
        );
        final resolvedBeaconBp = TaskHowToBlueprint.resolve(
          parentTask: customBeaconTask,
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5',
          unrealCppMode: false,
        );
        final resolvedBeaconCpp = TaskHowToBlueprint.resolve(
          parentTask: customBeaconTask,
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5',
          unrealCppMode: true,
        );
        expect(
          resolvedBeaconBp.subSteps.first.codeFormula,
          contains('└──► [LineTraceByChannel'),
        );
        expect(
          resolvedBeaconCpp.subSteps.first.codeFormula,
          contains('GetWorld()->LineTraceSingleByChannel('),
        );
        expect(
          resolvedBeaconCpp.subSteps.first.codeFormula,
          contains('ScorchDecal->SetWorldLocation(TraceHitLocation);'),
        );
        expect(
          resolvedBeaconCpp.subSteps.first.codeFormula,
          contains('ScorchDecal->SetVisibility(true);'),
        );

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
        expect(t0.subSteps[0].shortTitle,
            isNot(equals(t1.subSteps[0].shortTitle)));
        expect(t1.subSteps[0].shortTitle,
            isNot(equals(t2.subSteps[0].shortTitle)));
        expect(t0.subSteps[1].shortTitle,
            isNot(equals(t1.subSteps[1].shortTitle)));
        expect(t1.subSteps[1].shortTitle,
            isNot(equals(t2.subSteps[1].shortTitle)));
        expect(t0.subSteps[2].shortTitle,
            isNot(equals(t1.subSteps[2].shortTitle)));
        expect(t1.subSteps[2].shortTitle,
            isNot(equals(t2.subSteps[2].shortTitle)));

        // Verify dynamic step scaling (compact 3-step guard, 4-step feel, 5-step single-clause extension, and 10+ step complex mechanic)
        expect(t0.subSteps.length, 6);
        expect(t1.subSteps.length,
            7); // 4h heavy task includes extra tuning parameter step
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
        await provider.startConceptInterview(
            'High-speed grappling hook parkour roguelite');
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
          tuningParams: const [
            'hookMaxRange: 18.0 m',
            'hookPullSpeed: 28.0 m/s'
          ],
          edgeCases: const [
            '[LOS BREAK GUARD] Detach when line-of-sight breaks'
          ],
          checkpoints: [
            ProposedCheckpointBlueprint(
              title: 'Grapple Anchor & Swing',
              playtestCriteria: 'Fire hook -> swing across gap',
              tasks: const ['Hook Raycast (2h)', 'Swing Arc (2h)'],
              tuningParams: const [
                'hookMaxRange: 18.0 m',
                'hookPullSpeed: 28.0 m/s'
              ],
              edgeCases: const [
                '[LOS BREAK GUARD] Detach when line-of-sight breaks'
              ],
              releaseVersion: 'v0.1',
            ),
            ProposedCheckpointBlueprint(
              title: 'Release Boost & Cooldown',
              playtestCriteria: 'Release hook -> launch with momentum',
              tasks: const ['Release Impulse (2h)'],
              tuningParams: const [
                'hookMaxRange: 18.0 m',
                'hookPullSpeed: 28.0 m/s'
              ],
              edgeCases: const [
                '[LOS BREAK GUARD] Detach when line-of-sight breaks'
              ],
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
        await provider
            .sendReleasePlanChatMessage('Add Ore Smelting Furnace to Beat 2');
        final secondBeat = provider.releaseBlueprint!.beats[1];
        final furnaceBp = secondBeat.features.last;
        expect(furnaceBp.title, 'Ore Smelting Furnace');
        expect(furnaceBp.checkpoints.length, 2);
        expect(
            furnaceBp.tuningParams, contains('transactionCostBase: 25 gold'));

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
          afterFixStates.first.edgeCases
              .any((g) => g.startsWith('[PLAYTEST GUARD]')),
          isTrue,
        );

        // Post-Release Retrospective & Auto-Carryover Summary into v0.2
        final retro = provider.buildActiveReleaseRetrospective();
        expect(retro.playtestGuardsAdded, greaterThanOrEqualTo(1));
        expect(retro.carryoverFeatureTitles, isNotEmpty);
        expect(retro.verifiedCheckpoints,
            lessThanOrEqualTo(retro.totalCheckpoints));
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
          for (int bIdx = 0;
              bIdx < provider.activeReleaseBeats.length;
              bIdx++) {
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
          intake.expansionCards
              .any((c) => c.title.toLowerCase().contains('grapple')),
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
          afterCourierSearch.mechanics.any((m) =>
              m.toLowerCase().contains('submarine') ||
              m.toLowerCase().contains('sonar')),
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
        expect(
            provider.sparkIntake!.workingTitle, equals('Cozy Pizza Alchemy'));
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
        final unprefixedParsed =
            ProjectConceptBlueprint.parsePillarTitleAndBody(
          'Every run feels tense as cargo weight slows your movement',
          0,
        );
        expect(
            unprefixedParsed.title.toLowerCase(), isNot(startsWith('pillar ')));
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
          contains(
              'Goal: Build zipline anchor attach and momentum release mechanics.'),
        );
        expect(
          courierProvider.documents[newLiveFeatId]!.sections['scope'],
          contains(
              'Done When: Player attaches to zipline and detaches cleanly in playtest.'),
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
          ..verification =
              'Confirm custom AI step verify check passes in Play mode.';
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
          reason:
              'Completed sub-step state must be preserved when tuning parameters update',
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
          if (prompt.contains(
              'Synthesize concrete, beginner-friendly 3-Area Engine How-To steps')) {
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
                      'instruction':
                          'Instantiate UCableComponent in C++ constructor.',
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

        expect(capturedModel, equals('gemini-flash-latest'));
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
        expect(
            resolvedBp.subSteps.first.area1Hierarchy, contains('GrappleCable'));
        expect(resolvedBp.subSteps.first.area2Inspector,
            contains('grappleRange: 1800.0 cm'));
        expect(resolvedBp.subSteps.first.instruction,
            equals('Instantiate UCableComponent in C++ constructor.'));

        // ── Upgrade 3: Engine-Ready Context Export (AGENTS.md / .cursorrules) ──
        final agentsMd = provider.buildActiveReleaseCodingAgentMarkdown(
          unrealCppMode: true,
        );
        expect(agentsMd, contains('# AGENTS.md —'));
        expect(agentsMd, contains('UNREAL 5 C++ (.h / .cpp)'));
        expect(agentsMd,
            contains('## 3. Canonical Tuning Variables & Inspector Bindings'));
        expect(
            agentsMd, contains('## 4. Mandatory Playtest & Edge-Case Guards'));
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
          reason:
              'Stage 1 -> Stage 2 sync must preserve completed task progress',
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
          d.techSpec = [
            'Engine: Unreal Engine 5',
            'Language: C++ & Blueprints'
          ];
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
        expect(singlePrompt,
            contains('# AI CODING AGENT TASK PROMPT — ${firstFeat.title}'));
        expect(singlePrompt, contains('UNREAL 5 C++ (.h / .cpp)'));
        expect(singlePrompt,
            contains('## 2. Canonical Tuning Variables & Sibling Context'));
        expect(singlePrompt,
            contains('## 3. Mandatory Edge-Case & Playtest Guards'));
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
          syncedStates.last.tuningParams
              .any((p) => p.contains('dashCooldown: 0.25')),
          isTrue,
        );
        expect(
          syncedStates.last.tuningParams
              .any((p) => p.contains('comboWindowSec: 0.45')),
          isTrue,
        );
        expect(
          syncedStates.last.edgeCases.any(
            (g) => g.contains(
                'Cancel dash impulse immediately when player hits a solid wall normal'),
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
        statesB.last.tuningParams = [
          'grappleSpeed: 650.0',
          'releaseBoost: 1.25'
        ];
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
        expect(
            updatedStatesA.last.tuningParams, contains('zipVelocity: 650.0'));
        expect(
          updatedStatesA.last.edgeCases.first,
          contains('Clamp zipVelocity when player collides with ceiling'),
        );

        final updatedStatesB = FeatureStateNode.getStatesForDocument(featB);
        expect(
            updatedStatesB.last.tuningParams, contains('zipVelocity: 650.0'));
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
        expect(freshProvider.currentStage,
            equals(WorkbenchStage.releaseWorkbench));
        expect(freshProvider.activeReleaseBeats.length, equals(beats.length));

        final restoredFeats = <TierDocument>[
          for (final b in freshProvider.activeReleaseBeats)
            ...freshProvider.featuresForBeat(b.id),
        ];
        final restoredStatesB = FeatureStateNode.getStatesForDocument(
          restoredFeats[1],
        );
        expect(
            restoredStatesB.last.tuningParams, contains('zipVelocity: 650.0'));
        expect(
          restoredStatesB.last.checklist.first.children.first.codeSnippet,
          contains('zipVelocity * releaseBoost'),
        );

        // Import again into the same provider to verify collision-safe ID remapping
        final duplicateImportId =
            freshProvider.importProjectFromJson(exportedJson);
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

        // Opening Refine drawer on Section 01 (Goal) updates Goal in 1 click
        final initialGoal = provider.conceptDraft!.goal;
        final refineGoalBtn = find.byKey(
          const ValueKey('refine_drawer_toggle_btn_0'),
        );
        await tester.ensureVisible(refineGoalBtn);
        await tester.pumpAndSettle();
        await tester.tap(refineGoalBtn);
        await tester.pumpAndSettle();

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

        // ── 3. Upgrade 4: 1-Click Direct Pitch -> Blueprint & 1-Click Express Build v0.1 from Spark ──
        final resetBtn = find.byKey(const ValueKey('new_spark_reset_btn'));
        await tester.ensureVisible(resetBtn);
        await tester.pumpAndSettle();
        await tester.tap(resetBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('direct_generate_blueprint_btn')),
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

        final afterCopyNextStates =
            FeatureStateNode.getStatesForDocument(feat0);
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

        // ── 5. Audit Item 4: Dynamic Compact 2-Column Layout (Section 02 + Section 03) & Click-to-Tune Row ──
        final area2Header = find.byKey(
          ValueKey('area2_selected_component_header_${node.id}'),
        );
        final area3Panel = find.byKey(
          ValueKey('area3_script_setup_panel_${node.id}'),
        );
        expect(area2Header, findsOneWidget);
        expect(area3Panel, findsOneWidget);
        final sec2Rect = tester.getRect(area2Header);
        final sec3Rect = tester.getRect(area3Panel);
        expect(
          sec2Rect.top,
          closeTo(sec3Rect.top, 1.0),
          reason: 'Section 02 and Section 03 must sit side-by-side in a 2-column Row on desktop viewports.',
        );
        expect(
          sec2Rect.width,
          inInclusiveRange(250.0, 350.0),
          reason: 'Section 02 must use a compact content-hugging dynamic width (250px–350px).',
        );
        expect(
          sec3Rect.width,
          greaterThan(sec2Rect.width),
          reason: 'Section 03 (Script & Main Scene Setup) must expand to take the majority of the horizontal width.',
        );

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
        expect(bp0.subSteps[0].shortTitle,
            equals('Create BP_LocomotionCharacter'));
        expect(bp0.subSteps[0].codeFormula, contains('Character (ACharacter'));
        expect(bp0.subSteps[1].codeFormula, contains('CapsuleComponent'));
        expect(bp0.subSteps[1].codeFormula, contains('FirstPersonCamera'));
        expect(bp0.subSteps[1].codeFormula, contains('CharacterMovement'));

        // Task 2 (Input Mapping) sets up IA_Move & IMC_Default and wires to AddMovementInput on the SAME BP_LocomotionCharacter
        expect(
            bp1.subSteps[0].shortTitle, equals('Create IA_Move & IMC_Default'));
        expect(bp1.subSteps[0].codeFormula,
            contains('BP_LocomotionCharacter (Reuse from Task 01)'));
        expect(bp1.subSteps[1].shortTitle, equals('Register Mapping Context'));
        expect(bp1.subSteps[2].shortTitle,
            equals('Wire IA_Move to AddMovementInput'));

        // Task 3 (Physics Tuning) tunes CharacterMovement speed, acceleration & velocity on the SAME BP_LocomotionCharacter
        expect(bp2.subSteps[0].shortTitle, equals('Select Movement Component'));
        expect(bp2.subSteps[0].codeFormula,
            contains('BP_LocomotionCharacter (Reuse from Task 01)'));
        expect(bp2.subSteps[1].shortTitle,
            equals('Configure Walk Speed & Gravity'));
        expect(
            bp2.subSteps[2].shortTitle, equals('Wire Physics Momentum Curve'));

        // ── 2. AI Step Synthesis: 1-Based taskIndex (1, 2, 3) Maps Cleanly to checklist[0], [1], [2] with Zero Shift ──
        final prevResponder = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, preferredModel) async {
          if (prompt.contains(
            'Synthesize concrete, beginner-friendly 3-Area Engine How-To steps',
          )) {
            expect(prompt, contains('ONE SHARED ASSET ACROSS ALL TASKS'));
            expect(prompt, contains('STRICT TASK-ROLE ALIGNMENT'));
            return <String, dynamic>{
              'tasks': [
                {
                  'taskIndex': 1,
                  'subSteps': [
                    {
                      'title':
                          'STEP 1.1 · CREATE CHARACTER BLUEPRINT BP_ROOFRUNNER',
                      'stepPath':
                          'Content Browser → /Game/Blueprints/BP_RoofRunner',
                      'instruction':
                          'Create BP_RoofRunner inheriting from Character.',
                      'area1Hierarchy':
                          'BP_RoofRunner (ACharacter)\n └─ CapsuleComponent',
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
                      'instruction':
                          'Bind IA_Move and IMC_Default inside BP_RoofRunner.',
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
                      'title':
                          'STEP 3.1 · TUNE VELOCITY, GRAVITY & COLLISION GUARD',
                      'stepPath': 'BP_RoofRunner → CharacterMovement Details',
                      'instruction':
                          'Set Max Walk Speed = 600 and Jump Z Velocity = 450.',
                      'area1Hierarchy': '',
                      'area2Inspector':
                          'walkSpeed: 600 cm/s | jumpForce: 450 cm/s',
                      'codeFormula':
                          'CharacterMovement->MaxWalkSpeed = walkSpeed;',
                      'verifyResult':
                          'BP_RoofRunner sprints and jumps without roof clipping.',
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
                Subtask(
                    id: 'u_1', text: 'Upgrade tuning (2h)', completed: false),
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
        final statesAfterReloadOnV01 = FeatureStateNode.getStatesForDocument(
            provider.documents[featA.id]!);
        expect(
          statesAfterReloadOnV01.any((s) => s.releaseVersion == 'v0.2'),
          isTrue,
          reason:
              'Reloading project state while viewing v0.1 must never wipe v0.2+ checkpoints',
        );
      },
    );

    test(
      '21. Sequential Feature-by-Feature Cumulative Project Ledger, Multi-Feature Epic Scope Boundaries, and Zero Artificial Step Limits',
      () async {
        final provider = WorkbenchProvider(enableAutoLoad: false);
        await provider.startConceptInterview(
          'Unreal 5 arena shooter with grapple hook, wave spawner, and ore extraction.',
        );
        provider.updateConceptDraft((d) {
          d.techSpec = ['Unreal Engine 5', '3D Arena'];
        });
        await provider.approveConceptAndBuildRelease();

        final beat1 = provider.activeReleaseBeats.first;
        final beat1Feats = provider.featuresForBeat(beat1.id);
        expect(beat1Feats.length, greaterThanOrEqualTo(2));
        final feat1 = beat1Feats[0];
        final feat2 = beat1Feats[1];

        final capturedPromptsByFeatTitle = <String, String>{};
        final prevResponder = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, preferredModel) async {
          if (prompt.contains(
            'Synthesize concrete, beginner-friendly 3-Area Engine How-To steps',
          )) {
            if (prompt.contains('for Feature "${feat1.title}"')) {
              capturedPromptsByFeatTitle[feat1.title] = prompt;
              return <String, dynamic>{
                'tasks': [
                  {
                    'taskIndex': 0,
                    'subSteps': [
                      {
                        'title': 'STEP 1.1 · CREATE BP_PLAYERCHARACTER ASSET',
                        'stepPath': '/Game/Blueprints/BP_PlayerCharacter',
                        'instruction':
                            'Create BP_PlayerCharacter and attach GrappleComponent.',
                        'area1Hierarchy':
                            'BP_PlayerCharacter (Self)\n └─ GrappleComponent (USceneComponent)',
                        'area2Inspector': 'moveSpeed: 600.0 cm/s',
                        'codeFormula': 'moveSpeed = 600.0;',
                        'verifyResult':
                            'BP_PlayerCharacter spawns in the arena.',
                      },
                    ],
                  },
                ],
              };
            }
            if (prompt.contains('for Feature "${feat2.title}"')) {
              capturedPromptsByFeatTitle[feat2.title] = prompt;
              return <String, dynamic>{
                'tasks': [
                  {
                    'taskIndex': 0,
                    'subSteps': [
                      {
                        'title':
                            'STEP 1.1 · EXTEND BP_PLAYERCHARACTER RELEASE IMPULSE',
                        'stepPath': '/Game/Blueprints/BP_PlayerCharacter',
                        'instruction':
                            'Extend BP_PlayerCharacter with releaseBoostSpeed.',
                        'area1Hierarchy': '',
                        'area2Inspector': 'releaseBoostSpeed: 320.0 px/s',
                        'codeFormula': 'releaseBoostSpeed = 320.0;',
                        'verifyResult':
                            'Release boost launches BP_PlayerCharacter.',
                      },
                    ],
                  },
                ],
              };
            }
          }
          return prevResponder != null
              ? await prevResponder(prompt, preferredModel)
              : null;
        };

        try {
          await provider.synthesizeFeatureHowToStepsWithAi(
            feat1.id,
            forceRefresh: true,
          );
          await provider.synthesizeFeatureHowToStepsWithAi(
            feat2.id,
            forceRefresh: true,
          );
        } finally {
          GeminiAgentClient.testMockResponder = prevResponder;
        }

        final prompt1 = capturedPromptsByFeatTitle[feat1.title]!;
        final prompt2 = capturedPromptsByFeatTitle[feat2.title]!;

        // 1. Zero artificial step count limits
        expect(prompt1, contains('zero artificial step count limits'));
        expect(prompt1, isNot(contains('return 3 to 5 sequential sub-steps')));

        // 2. Same-Epic Multi-Feature Scope Boundaries
        expect(prompt1, contains('SAME-EPIC MULTI-FEATURE SCOPE BOUNDARIES'));
        expect(
          prompt1,
          contains(
            'Later Sibling in Same Epic (2/${beat1Feats.length}): "${feat2.title}"',
          ),
        );
        expect(prompt1, contains('QUEUED LATER IN THIS EPIC'));

        expect(prompt2, contains('SAME-EPIC MULTI-FEATURE SCOPE BOUNDARIES'));
        expect(
          prompt2,
          contains(
            'Earlier Sibling in Same Epic (1/${beat1Feats.length}): "${feat1.title}"',
          ),
        );
        expect(prompt2, contains('ALREADY BUILT'));

        // 3. Cumulative Project Ledger passed from Feature #1 into Feature #2
        expect(prompt2, contains('CUMULATIVE PROJECT LEDGER'));
        expect(prompt2, contains('BP_PlayerCharacter'));
        expect(prompt2, contains('moveSpeed: 240.0 px/s'));

        // 4. Stage 2 Intra-Epic Build Dependency Rules (Surface Before Actor, Target Before Tether, Base Action Before Gate)
        final epic1Ordered =
            ReleasePlannerAgent.enforceIntraEpicBuildDependencies(
          [
            ProposedFeatureBlueprint(
              id: 'f1',
              title: 'First Person Movement',
              goal: 'Walk',
              doneWhen: 'Done',
            ),
            ProposedFeatureBlueprint(
              id: 'f2',
              title: 'Station Corridor Blockout',
              goal: 'Corridor',
              doneWhen: 'Done',
            ),
          ],
          epicIndex: 0,
        );
        expect(epic1Ordered.first.title, equals('Station Corridor Blockout'));

        final epic3SalvageOrdered =
            ReleasePlannerAgent.enforceIntraEpicBuildDependencies(
          [
            ProposedFeatureBlueprint(
              id: 'f3_1',
              title: 'Harpoon Tow Cable',
              goal: 'Tether',
              doneWhen: 'Done',
            ),
            ProposedFeatureBlueprint(
              id: 'f3_2',
              title: 'Scrap Core Physics',
              goal: 'Core body',
              doneWhen: 'Done',
            ),
          ],
          epicIndex: 2,
        );
        expect(epic3SalvageOrdered.first.title, equals('Scrap Core Physics'));
        expect(epic3SalvageOrdered[1].title, equals('Harpoon Tow Cable'));

        final epic3CropOrdered =
            ReleasePlannerAgent.enforceIntraEpicBuildDependencies(
          [
            ProposedFeatureBlueprint(
              id: 'f3_a',
              title: 'Seed Planting',
              goal: 'Plant',
              doneWhen: 'Done',
            ),
            ProposedFeatureBlueprint(
              id: 'f3_b',
              title: 'Tank Seal Depressurize',
              goal: 'Depressurize gate',
              doneWhen: 'Done',
            ),
            ProposedFeatureBlueprint(
              id: 'f3_c',
              title: 'Mature Crop Harvest',
              goal: 'Harvest crop',
              doneWhen: 'Done',
            ),
          ],
          epicIndex: 2,
        );
        expect(epic3CropOrdered[1].title, equals('Mature Crop Harvest'));
        expect(epic3CropOrdered[2].title, equals('Tank Seal Depressurize'));
      },
    );

    test(
      '22. 6 Full-Lifecycle Workflow Upgrades: 1-Click Feature Pivot/Restore, Phase-Aware Exclusions, Phase-Specific 3-Area Steps, Full Production Gate, Phase 5 Post-Launch (v1.1+), and Cross-Release Evolution Ledger',
      () async {
        // ── Upgrade 2: Phase-Aware 07 Out of Scope Exclusions ──
        expect(
          ReleaseBlueprint.isExclusionActiveForPhase(
            'No online multiplayer [NEVER]',
            ProductionPhase.prototype,
          ),
          isTrue,
        );
        expect(
          ReleaseBlueprint.isExclusionActiveForPhase(
            'No online multiplayer [NEVER]',
            ProductionPhase.fullProduction,
          ),
          isTrue,
        );
        expect(
          ReleaseBlueprint.isExclusionActiveForPhase(
            'No online multiplayer [NEVER]',
            ProductionPhase.postLaunch,
          ),
          isTrue,
        );

        // Prototype-only exclusion ("in v0.1") blocks in Prototype, unlocks in MVP+
        expect(
          ReleaseBlueprint.isExclusionActiveForPhase(
            'No skill tree in v0.1',
            ProductionPhase.prototype,
          ),
          isTrue,
        );
        expect(
          ReleaseBlueprint.isExclusionActiveForPhase(
            'No skill tree in v0.1',
            ProductionPhase.mvp,
          ),
          isFalse,
        );
        expect(
          ReleaseBlueprint.isDeferredExclusionUnlockedInPhase(
            'No skill tree in v0.1',
            ProductionPhase.mvp,
          ),
          isTrue,
        );

        // Full-production deferred exclusion blocks in Prototype/MVP/Vertical Slice, unlocks in Full Production+
        expect(
          ReleaseBlueprint.isExclusionActiveForPhase(
            'Defer boss rush mode until full production',
            ProductionPhase.verticalSlice,
          ),
          isTrue,
        );
        expect(
          ReleaseBlueprint.isExclusionActiveForPhase(
            'Defer boss rush mode until full production',
            ProductionPhase.fullProduction,
          ),
          isFalse,
        );
        expect(
          ReleaseBlueprint.isDeferredExclusionUnlockedInPhase(
            'Defer boss rush mode until full production',
            ProductionPhase.fullProduction,
          ),
          isTrue,
        );

        // ── Upgrade 3: Phase-Specific 3-Area Step Synthesis ──
        final testCp = FeatureStateNode(
          id: 'cp_phase_test',
          name: 'Checkpoint 1: Dash Core (v0.1)',
          trigger: 'Press Space -> player dashes forward',
          order: 0,
          tuningParams: const ['dashSpeed: 900.0 px/s'],
          edgeCases: const ['[COOLDOWN GUARD] Prevent dash during cooldown'],
          checklist: [
            Subtask(id: 't_1', text: 'Character & Input Setup (2h)'),
          ],
          parameters: const {'releaseVersion': 'v0.1'},
        );

        TaskHowToBlueprint.clearCache();
        final protoBp = TaskHowToBlueprint.resolve(
          parentTask: testCp.checklist.first,
          taskIndex: 0,
          checkpointNode: testCp,
          engineHint: 'Godot 4',
          phase: ProductionPhase.prototype,
        );
        expect(protoBp.subSteps.first.specChips, contains('Phase: 01 Prototype'));
        expect(
          protoBp.subSteps.first.explainConcept,
          contains('Greybox foundation pass'),
        );

        final vsBp = TaskHowToBlueprint.resolve(
          parentTask: testCp.checklist.first,
          taskIndex: 0,
          checkpointNode: testCp,
          engineHint: 'Godot 4',
          phase: ProductionPhase.verticalSlice,
        );
        expect(
          vsBp.subSteps.first.specChips,
          contains('Phase: 03 Vertical Slice Polish'),
        );
        expect(
          vsBp.subSteps.first.explainConcept,
          contains('Vertical Slice polish pass'),
        );

        final postBp = TaskHowToBlueprint.resolve(
          parentTask: testCp.checklist.first,
          taskIndex: 0,
          checkpointNode: testCp,
          engineHint: 'Godot 4',
          phase: ProductionPhase.postLaunch,
        );
        expect(
          postBp.subSteps.first.specChips,
          contains('Phase: 05 Post-Launch Live Ops'),
        );
        expect(
          postBp.subSteps.first.explainConcept,
          contains('Post-Launch Live Ops pass'),
        );

        // ── Upgrade 1: 1-Click Feature Pivot / Supersede & Restore ──
        final provider = WorkbenchProvider(enableAutoLoad: false);
        await provider.startConceptInterview(
          'Top-down arena shooter with dash, grapple, and wave survival.',
        );
        provider.updateConceptDraft((d) {
          d.exclusions = [
            'No online multiplayer [NEVER]',
            'Defer boss rush mode until full production',
          ];
        });
        await provider.approveConceptAndBuildRelease();

        final beat1 = provider.activeReleaseBeats.first;
        final beat1Feats = provider.featuresForBeat(beat1.id);
        expect(beat1Feats, isNotEmpty);
        final pivotTarget = beat1Feats.first;

        final archivedNow = provider.toggleSupersedeFeature(
          pivotTarget.id,
          pivotReason: 'Pivoted during v0.1 playtest',
        );
        expect(archivedNow, isTrue);
        expect(
          pivotTarget.sections['lifecycle'],
          equals(FeatureLifecycleStatus.superseded.name),
        );
        expect(
          pivotTarget.sections['pivotReason'],
          equals('Pivoted during v0.1 playtest'),
        );
        expect(provider.isFeatureActiveInRelease(pivotTarget), isFalse);
        expect(
          provider.supersededFeatures.map((f) => f.id),
          contains(pivotTarget.id),
        );

        // Restore the archived feature back to active scope
        final archivedAfterRestore =
            provider.toggleSupersedeFeature(pivotTarget.id);
        expect(archivedAfterRestore, isFalse);
        expect(
          pivotTarget.sections['lifecycle'],
          equals(FeatureLifecycleStatus.newFeature.name),
        );
        expect(provider.isFeatureActiveInRelease(pivotTarget), isTrue);

        // ── Upgrade 6: Cross-Release Evolution & Tuning Delta Ledger ──
        final targetStates = FeatureStateNode.getStatesForDocument(pivotTarget);
        targetStates.first.tuningParams = ['dashSpeed: 240.0 px/s'];
        targetStates.first.edgeCases = ['[COOLDOWN GUARD] Wait 0.4s'];
        for (final t in targetStates.first.checklist) {
          t.completed = true;
          for (final sub in t.children) {
            sub.completed = true;
          }
        }
        targetStates.add(
          FeatureStateNode(
            id: '${pivotTarget.id}_v0.2_cp_2',
            name: 'Checkpoint 2: Dash Upgrade (v0.2)',
            trigger: 'Dash chains into shield bash',
            order: 1,
            tuningParams: ['dashSpeed: 310.0 px/s'],
            edgeCases: [
              '[COOLDOWN GUARD] Wait 0.4s',
              '[STAMINA GUARD] Require 15 stamina',
            ],
            checklist: [
              Subtask(id: 'u_t1', text: 'Chain Logic (2h)', completed: true),
            ],
            parameters: const {'releaseVersion': 'v0.2'},
          ),
        );
        provider.updateFeatureStates(pivotTarget.id, targetStates);

        final evolutionLedger = provider.buildCrossReleaseEvolutionLedger();
        expect(evolutionLedger, isNotEmpty);
        final ledgerEntry = evolutionLedger.firstWhere(
          (r) => r.featureId == pivotTarget.id,
        );
        expect(ledgerEntry.checkpointProgression.length, equals(2));
        expect(
          ledgerEntry.tuningDeltaSummary.first,
          contains('dashSpeed: 240.0 px/s (v0.1) → 310.0 px/s (v0.2)'),
        );
        expect(ledgerEntry.guardCount, equals(2));

        final agentsMd = provider.buildActiveReleaseCodingAgentMarkdown();
        expect(
          agentsMd,
          contains('## 6. Cross-Release Evolution & Tuning History'),
        );
        expect(
          agentsMd,
          contains('dashSpeed: 240.0 px/s (v0.1) → 310.0 px/s (v0.2)'),
        );

        // ── Upgrade 4 & Upgrade 5: Full Production Coverage Gate & Phase 5 Post-Launch (v1.1+) ──
        // Complete all features in the active release so we can advance to Full Production -> Post-Launch
        for (final b in provider.activeReleaseBeats) {
          for (final f in provider.featuresForBeat(b.id)) {
            final fStates = FeatureStateNode.getStatesForDocument(f);
            for (final s in fStates) {
              for (final t in s.checklist) {
                t.completed = true;
                for (final sub in t.children) {
                  sub.completed = true;
                }
              }
            }
            provider.updateFeatureStates(f.id, fStates);
          }
        }

        await provider.prepareProgressiveNextReleaseDraft();
        await provider.setDraftReleasePhase(ProductionPhase.fullProduction);
        expect(provider.currentPhase, equals(ProductionPhase.fullProduction));
        // Manual phase override (no Full Production Blueprint) keeps v0.N numbering and legacy coverage
        expect(provider.activeReleaseVersionTag, startsWith('v0.'));
        await provider.approveAndExecuteReleasePlan();

        // Mark all v1.0 Full Production checkpoints complete
        for (final b in provider.activeReleaseBeats) {
          for (final f in provider.featuresForBeat(b.id)) {
            final fStates = FeatureStateNode.getStatesForDocument(f);
            for (final s in fStates) {
              for (final t in s.checklist) {
                t.completed = true;
                for (final sub in t.children) {
                  sub.completed = true;
                }
              }
            }
            provider.updateFeatureStates(f.id, fStates);
          }
        }

        final fpCov = provider.fullProductionCoverage();
        expect(fpCov.coveredBeats, equals(fpCov.totalBeats));
        expect(fpCov.openFixCount, equals(0));
        expect(fpCov.isReadyForLaunch, isTrue);

        // Once v1.0 Full Production is verified, inferNextProgressivePhase unlocks Phase 5 Post-Launch (v1.1)
        expect(
          provider.inferNextProgressivePhase(),
          equals(ProductionPhase.postLaunch),
        );
        expect(provider.nextProgressiveVersionLabel, equals('v1.1'));

        await provider.prepareProgressiveNextReleaseDraft();
        expect(provider.currentPhase, equals(ProductionPhase.postLaunch));
        expect(provider.activeReleaseVersionTag, equals('v1.1'));
        expect(
          provider.activePhaseBadgeLabel,
          equals('PHASE 5 · POST-LAUNCH & LIVE OPS (PASS 1)'),
        );
        expect(
          provider.releasePhaseShortBadge(provider.activeRelease!),
          equals('LIVE'),
        );
      },
    );

    test(
      'Agentic Feature Inbox (WHEN / WHERE / HOW Triage, Split Now + Future, Auto-Injection on Phase Advance) & Multi-Release Superseded Restoration',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview(
          'Top-down roguelike arena shooter with dash and twin-stick weapons',
        );
        await provider.openReleasePlanGate();
        await provider.approveAndExecuteReleasePlan();

        expect(provider.currentPhase, equals(ProductionPhase.prototype));
        expect(provider.activeReleaseVersionTag, equals('v0.1'));
        final beats = provider.activeReleaseBeats;
        expect(beats, isNotEmpty);

        // 1. Capture an immediate feature idea ('now') -> materialize in v0.1
        final nowItem = await provider.submitFeatureIdeaToInbox(
          'Add Grappling Hook Pull to yank enemies',
          preferredBeatId: beats.first.id,
        );
        expect(nowItem, isNotNull);
        expect(nowItem!.status, equals(FeatureInboxStatus.triagePending));
        expect(
          nowItem.releaseTimingMode,
          equals(InboxReleaseTimingMode.now),
        );
        final createdNowFeatId =
            await provider.acceptFeatureInboxTriage(nowItem.id);
        expect(createdNowFeatId, isNotNull);
        expect(
          provider
              .featuresForBeat(beats.first.id)
              .any((f) => f.id == createdNowFeatId),
          isTrue,
        );

        // 2. Capture a split progression idea during v0.1 Prototype ('splitNowAndFuture')
        // -> builds lean core modifier in v0.1 AND schedules the upgrade for 02 · MVP
        final splitItem = await provider.submitFeatureIdeaToInbox(
          'Add Weapon Perk Shop with persistent tiers',
          preferredBeatId: beats.first.id,
        );
        expect(splitItem, isNotNull);
        expect(
          splitItem!.releaseTimingMode,
          equals(InboxReleaseTimingMode.splitNowAndFuture),
        );
        expect(splitItem.targetFuturePhase, equals(ProductionPhase.mvp));

        final splitCoreFeatId =
            await provider.acceptFeatureInboxTriage(splitItem.id);
        expect(splitCoreFeatId, isNotNull);
        expect(
          provider.scheduledInboxUpgradesForFeature(splitCoreFeatId!),
          hasLength(1),
        );

        // 3. Capture a future-phase idea ('futureRelease' targeting Vertical Slice)
        final vsItem = await provider.submitFeatureIdeaToInbox(
          'Add Boss Cutscene Shader & VFX Intro',
          preferredBeatId: beats.last.id,
        );
        expect(vsItem, isNotNull);
        expect(
          vsItem!.releaseTimingMode,
          equals(InboxReleaseTimingMode.futureRelease),
        );
        expect(vsItem.targetFuturePhase, equals(ProductionPhase.verticalSlice));
        final vsImmediateFeatId =
            await provider.acceptFeatureInboxTriage(vsItem.id);
        expect(vsImmediateFeatId, isNull);
        expect(provider.scheduledFeatureInboxItems, hasLength(2));

        // 4. Test Multi-Release SUPERSEDED filtering & restoration across v0.1 -> v0.2
        final activeCountBeforePivot =
            provider.featuresForBeat(beats.first.id).length;
        provider.toggleSupersedeFeature(
          createdNowFeatId!,
          pivotReason: 'Pivoted grappling hook in v0.1 playtest',
        );
        // Excluded from active featuresForBeat immediately, but retained with includeSuperseded: true
        expect(
          provider.featuresForBeat(beats.first.id).length,
          equals(activeCountBeforePivot - 1),
        );
        expect(
          provider
              .featuresForBeat(beats.first.id, includeSuperseded: true)
              .any((f) => f.id == createdNowFeatId),
          isTrue,
        );

        // 5. Verify side-effect-free Cancel on Progressive Release Draft before building v0.2:
        final preCancelRelId = provider.activeReleaseId;
        final preCancelPhase = provider.currentPhase;
        await provider.prepareProgressiveNextReleaseDraft();
        final cancelBp = provider.releaseBlueprint!;
        final cancelTargetBeat = cancelBp.beats.first;
        provider.toggleProposedFeatureSuperseded(
          cancelTargetBeat.id,
          splitCoreFeatId,
        );
        expect(
          provider.documents[splitCoreFeatId]!.sections['lifecycle'],
          equals(FeatureLifecycleStatus.superseded.name),
        );
        provider.restoreActiveReleaseAfterCancel(preCancelRelId, preCancelPhase);
        expect(
          provider.documents[splitCoreFeatId]!.sections['lifecycle'],
          isNot(equals(FeatureLifecycleStatus.superseded.name)),
        );

        // Advance to v0.2 (02 · MVP) -> verify the scheduled 02 · MVP upgrade auto-injects into the v0.2 Release Blueprint!
        await provider.prepareProgressiveNextReleaseDraft();
        expect(provider.currentPhase, equals(ProductionPhase.mvp));
        final v2Bp = provider.releaseBlueprint!;
        final upgradedSplitFeatInBp = v2Bp.beats
            .expand((b) => b.features)
            .where((f) => f.id == splitCoreFeatId)
            .firstOrNull;
        expect(upgradedSplitFeatInBp, isNotNull);
        expect(
          upgradedSplitFeatInBp!.lifecycle,
          equals(FeatureLifecycleStatus.upgrade),
        );
        expect(upgradedSplitFeatInBp.included, isTrue);

        // Verify bidirectional STABLE <-> UPGRADE toggling on prior-release features:
        final splitBeatId = v2Bp.beats
            .firstWhere((b) => b.features.any((f) => f.id == splitCoreFeatId))
            .id;
        provider.toggleProposedFeatureUpgradeOrStable(
          splitBeatId,
          splitCoreFeatId,
        );
        expect(
          upgradedSplitFeatInBp.lifecycle,
          equals(FeatureLifecycleStatus.stable),
        );
        provider.toggleProposedFeatureUpgradeOrStable(
          splitBeatId,
          splitCoreFeatId,
        );
        expect(
          upgradedSplitFeatInBp.lifecycle,
          equals(FeatureLifecycleStatus.upgrade),
        );

        // Also test 1-click `pullInboxItemIntoReleaseDraft` inside the Progressive Release Co-Pilot:
        // Add a Full Production Inbox item and pull it into v0.2 draft, while leaving `vsItem` for Vertical Slice
        final fpItem = await provider.submitFeatureIdeaToInbox(
          'Add Steam Achievements & Cloud Save Sync',
          preferredBeatId: beats.last.id,
        );
        expect(fpItem, isNotNull);
        provider.updateFeatureInboxItemTriage(
          fpItem!.id,
          timingMode: InboxReleaseTimingMode.futureRelease,
          targetFuturePhase: ProductionPhase.fullProduction,
        );
        expect(provider.pullInboxItemIntoReleaseDraft(fpItem.id), isTrue);
        expect(
          v2Bp.beats
              .expand((b) => b.features)
              .any((f) => f.id == 'feat_v0.2_inbox_${fpItem.id}'),
          isTrue,
        );

        // Build v0.2 -> the 02 · MVP scheduled Inbox item and pulled `fpItem` mark implemented, while the 03 · Vertical Slice item (`vsItem`) remains scheduled
        await provider.approveAndExecuteReleasePlan();
        expect(
          provider.scheduledInboxUpgradesForFeature(splitCoreFeatId),
          isEmpty,
        );
        expect(provider.scheduledFeatureInboxItems, hasLength(1));
        expect(
          provider.scheduledFeatureInboxItems.first.targetFuturePhase,
          equals(ProductionPhase.verticalSlice),
        );

        // Verify immediate `upgradeExistingFeature` and `newEpicAndFeature` via `acceptFeatureInboxTriage` sync with `_releaseBlueprint`
        final liveUpgradeItem = await provider.submitFeatureIdeaToInbox(
          'Add grappling hook air-dash cancel boost',
          preferredBeatId: beats.first.id,
        );
        expect(liveUpgradeItem, isNotNull);
        provider.updateFeatureInboxItemTriage(
          liveUpgradeItem!.id,
          timingMode: InboxReleaseTimingMode.now,
          integrationMode: InboxIntegrationMode.upgradeExistingFeature,
          targetFeatureId: splitCoreFeatId,
        );
        final upgradedId =
            await provider.acceptFeatureInboxTriage(liveUpgradeItem.id);
        expect(upgradedId, equals(splitCoreFeatId));
        final syncedBpFeat = provider.releaseBlueprint!.beats
            .expand((b) => b.features)
            .firstWhere((f) => f.id == splitCoreFeatId);
        expect(syncedBpFeat.checkpoints.length, greaterThanOrEqualTo(2));

        final newEpicItem = await provider.submitFeatureIdeaToInbox(
          'Add Co-Op Lobby Matchmaking Browser',
          preferredBeatId: beats.first.id,
        );
        expect(newEpicItem, isNotNull);
        provider.updateFeatureInboxItemTriage(
          newEpicItem!.id,
          timingMode: InboxReleaseTimingMode.now,
          integrationMode: InboxIntegrationMode.newEpicAndFeature,
        );
        final newEpicFeatId =
            await provider.acceptFeatureInboxTriage(newEpicItem.id);
        expect(newEpicFeatId, isNotNull);
        expect(
          provider.releaseBlueprint!.beats
              .expand((b) => b.features)
              .any((f) => f.id == newEpicFeatId),
          isTrue,
        );

        // Even after v0.2 executeBlueprint rebuilt beatDoc.childrenIds, the v0.1 superseded feature
        // remains in buildCrossReleaseEvolutionLedger and restores cleanly back into beats.first.childrenIds!
        expect(
          provider
              .buildCrossReleaseEvolutionLedger()
              .any((r) => r.featureId == createdNowFeatId && r.lifecycle == 'ARCHIVED'),
          isTrue,
        );
        provider.toggleSupersedeFeature(createdNowFeatId);
        expect(
          provider
              .featuresForBeat(beats.first.id)
              .any((f) => f.id == createdNowFeatId),
          isTrue,
        );

        // 6. Verify duplicateProject and importProjectFromJson remap feature_inbox_json targetBeatId & targetFeatureId
        final scheduledFollowup = await provider.submitFeatureIdeaToInbox(
          'Add grappling hook rope swing momentum upgrade',
          preferredBeatId: beats.first.id,
        );
        expect(scheduledFollowup, isNotNull);
        provider.updateFeatureInboxItemTriage(
          scheduledFollowup!.id,
          timingMode: InboxReleaseTimingMode.futureRelease,
          targetFuturePhase: ProductionPhase.verticalSlice,
          integrationMode: InboxIntegrationMode.upgradeExistingFeature,
          targetFeatureId: createdNowFeatId,
        );
        provider.acceptFeatureInboxTriage(scheduledFollowup.id);
        expect(
          provider.scheduledInboxUpgradesForFeature(createdNowFeatId),
          isNotEmpty,
        );

        final srcProjectId = provider.activeProjectId!;
        final exportedBundle = provider.exportProjectToJson(srcProjectId);
        final clonedProjId = provider.duplicateProject(srcProjectId);
        expect(clonedProjId, isNotNull);
        expect(clonedProjId, isNot(equals(srcProjectId)));

        final clonedBeats = provider.activeReleaseBeats;
        final clonedGrappleFeat = provider
            .featuresForBeat(clonedBeats.first.id)
            .firstWhere((f) => f.title.toLowerCase().contains('grappling'));
        expect(clonedGrappleFeat.id, isNot(equals(createdNowFeatId)));
        final clonedScheduledUpgrades =
            provider.scheduledInboxUpgradesForFeature(clonedGrappleFeat.id);
        expect(clonedScheduledUpgrades, isNotEmpty);
        expect(
          clonedScheduledUpgrades.first.targetBeatId,
          equals(clonedBeats.first.id),
        );
        expect(
          clonedScheduledUpgrades.first.targetFeatureId,
          equals(clonedGrappleFeat.id),
        );

        // Importing the exported bundle while srcProjectId still exists triggers ID-collision remapping
        final importedProjId = provider.importProjectFromJson(exportedBundle);
        expect(importedProjId, isNotNull);
        expect(importedProjId, isNot(equals(srcProjectId)));
        final importedBeats = provider.activeReleaseBeats;
        final importedGrappleFeat = provider
            .featuresForBeat(importedBeats.first.id)
            .firstWhere((f) => f.title.toLowerCase().contains('grappling'));
        expect(importedGrappleFeat.id, isNot(equals(createdNowFeatId)));
        final importedScheduledUpgrades =
            provider.scheduledInboxUpgradesForFeature(importedGrappleFeat.id);
        expect(importedScheduledUpgrades, isNotEmpty);
        expect(
          importedScheduledUpgrades.first.targetBeatId,
          equals(importedBeats.first.id),
        );
        expect(
          importedScheduledUpgrades.first.targetFeatureId,
          equals(importedGrappleFeat.id),
        );
      },
    );

    test(
      'Crop Shotgun Arena End-to-End Workflow Audit Regressions: Concrete Engine Normalization, 2D Step Guard, Full Core Loop Seeding, Canonical Epic Preservation, Eager Sub-Steps, and Scheduled newEpicAndFeature Inbox Injection',
      () async {
        final capturedStepPrompts = <String>[];
        final capturedInboxPrompts = <String>[];

        GeminiAgentClient.testMockResponder = (prompt, model) async {
          if (prompt.contains(
            'creating a Stage 1 Concept Blueprint for this spark idea:',
          )) {
            return {
              'title': 'Crop Shotgun Arena',
              'goal':
                  'Build a playable 2D top-down arena shooter where planting crops by day yields elemental shotgun ammo by night.',
              'gameSpec': [
                '2D Top-Down',
                'Twin-Stick (WASD + Mouse Aim)',
                'Singleplayer',
                'Compact Farm Arena',
              ],
              // Fix 1 test case: LLM returns generic "2D Game Engine" and 2 release titles
              'techSpec': [
                '2D Game Engine',
                'PC Desktop',
                '2D Pixel Art Sprites',
                'Offline Local Save',
              ],
              'designPillars': [
                'Harvest Fuels Firepower: Every crop you tend directly shapes your combat ammo.',
                'Relentless Forward Dash: Dashing through enemies rewards aggressive positioning.',
                'Readable Night Waves: Enemy telegraphs and ammo counts stay clear at a glance.',
              ],
              'tradeOffs': [
                'Snappy Arcade Movement: Instant twin-stick velocity over realistic inertia',
                'Direct Plot Interaction: One-button planting and harvest over complex farming menus',
              ],
              'coreLoopBeats': [
                'Crop Planting & Harvest: Plant seeds in soil plots, water them, and harvest ammo pods.',
                'Day Night Phase Shift: Trigger sunset transition to lock plots and spawn enemy waves.',
                'Dash Reload Combat: Dash through enemies to reload shells and fire elemental spreads.',
                'Shotgun Wave Clearing: Clear pest waves and collect dropped seed packets.',
                'Seed Loot & Plot Upgrade: Spend harvested pods to unlock soil plots and start next day.',
              ],
              'exclusions': [
                'No town NPC dialogue trees',
                'No online co-op multiplayer',
              ],
              'doneWhen':
                  'Playtester plants crops, survives 2 night waves using dash-reload shotgun shells, and unlocks a soil plot.',
              'releaseTrainTitles': [
                'v0.1: Prototype — Part 1: Controls & Primary Mechanics',
                'v0.2: Prototype — Part 2: Progression & Loop Reset',
              ],
            };
          }

          if (prompt.contains('updating a Live Concept Blueprint')) {
            return {
              'reply': 'Added dash-through-enemy reload and kept 2D engine.',
              'updatedFields': ['Tech Spec', 'Core Loop'],
              'techSpec': [
                '2D Engine',
                'PC Desktop',
                '2D Pixel Art Sprites',
                'Offline Local Save',
              ],
            };
          }

          if (prompt.contains(
            'Synthesize concrete, beginner-friendly 3-Area Engine How-To steps',
          )) {
            capturedStepPrompts.add(prompt);
            return null; // Let deterministic fallback or eager seeding verify
          }

          if (prompt.contains(
            'Triage this developer feature request captured in the Feature Inbox',
          )) {
            capturedInboxPrompts.add(prompt);
            if (prompt.contains('Seed Mutator Workbench')) {
              return {
                'releaseTimingMode': 'futureRelease',
                'targetFuturePhase': 'mvp',
                'releaseTimingReasoning':
                    'Meta-crafting fits Phase 2 (02 · MVP) as a dedicated progression station.',
                'integrationMode': 'newEpicAndFeature',
                'targetBeatId': 'new_epic',
                'newEpicTitle': 'Seed Combiner Station',
                'placementReasoning':
                    'Belongs in its own Seed Combiner Station Epic.',
                'featureTitle': 'Physical Seed Combiner',
                'goal': 'Build a 2-slot seed combiner anvil between waves.',
                'inScope': [
                  'Two-slot seed anvil interaction',
                  'Hybrid seed output drop',
                ],
                'doneWhen':
                    'Playtester drops 2 seeds onto the anvil and collects 1 hybrid seed.',
                'architectureHowSummary': [
                  'Area2D SeedAnvil with 2 slot markers',
                  'Interact signal combines 2 seed IDs',
                  'Guard against empty slots before combining',
                ],
                'checkpointTitle': 'Playable Physical Seed Combiner',
                'playtestGate': 'Drop 2 seeds -> spawns 1 hybrid seed',
                'tasks': [
                  'Build 2-slot seed anvil trigger and hybrid output spawner (1.5h)',
                  'Wire seed packet consumption and hybrid pickup prompt (1.5h)',
                ],
                'tuningParams': ['combineDuration: 1.5 s'],
                'edgeCases': [
                  '[EMPTY SLOT GUARD] Require 2 valid seeds before combining',
                ],
                'futureCheckpointTitle': 'Playable Physical Seed Combiner',
                'futureGoal':
                    'Build a 2-slot seed combiner anvil between waves.',
                'futurePlaytestGate': 'Drop 2 seeds -> spawns 1 hybrid seed',
                'futureTasks': [
                  'Build 2-slot seed anvil trigger and hybrid output spawner (1.5h)',
                  'Wire seed packet consumption and hybrid pickup prompt (1.5h)',
                ],
              };
            }
            return {
              'releaseTimingMode': 'now',
              'targetFuturePhase': 'mvp',
              'releaseTimingReasoning':
                  'Fits directly into active v0.1 combat feel.',
              'integrationMode': 'newFeatureInEpic',
              'targetBeatId': 'beat_3',
              'placementReasoning': 'Fits inside Dash Reload Combat.',
              'featureTitle': 'Shotgun Knockback Recoil',
              'goal':
                  'Apply backward recoil impulse when firing shotgun shells.',
              'inScope': ['Recoil velocity impulse on fire'],
              'doneWhen':
                  'Firing shotgun pushes player back by recoilImpulse without clipping walls.',
              'architectureHowSummary': [
                'CharacterBody2D recoil vector',
                'Apply opposite aim impulse on fire',
                'Clamp velocity against walls',
              ],
              'checkpointTitle': 'Playable Shotgun Knockback Recoil',
              'playtestGate': 'Fire shotgun -> player nudges backward cleanly',
              'tasks': [
                'Apply backward recoil velocity vector on shotgun fire (1.5h)',
                'Clamp recoil impulse against arena boundary collisions (1.5h)',
              ],
              'tuningParams': ['recoilImpulse: 180.0 px/s'],
              'edgeCases': [
                '[WALL CLIP GUARD] Zero recoil impulse when colliding with wall',
              ],
            };
          }

          if (prompt.contains('planning Release:')) {
            final isFirstRelease = prompt.contains(
              'First Release (v0.1): No prior features exist yet.',
            );
            if (isFirstRelease) {
              // Fix 3A test case: LLM only returns 3 beats out of the 5 Stage 1 Core Loop Beats in v0.1
              return {
                'goal':
                    'Plant seeds, shift to night, and dash-reload through enemy waves.',
                'doneWhen':
                    'Playtester plants seeds, shifts to night, and clears wave.',
                'explicitExclusions': ['No online co-op'],
                'beats': [
                  {
                    'id': 'beat_1',
                    'title': 'Crop Planting & Harvest',
                    'goal': 'Plant seeds in soil plots and harvest ammo pods.',
                    'doneWhen': 'Plots grow and drop ammo pods.',
                    'features': [
                      {
                        'id': 'feat_1_1',
                        'title': 'Soil Plot Planting',
                        'lifecycle': 'new',
                        'included': true,
                        'estimatedHours': 3,
                        'goal':
                            'Plant seeds in soil plots and harvest ammo pods.',
                        'inScope': ['Soil plot state and pod drop'],
                        'doneWhen':
                            'Player plants a seed and collects harvested ammo pod.',
                        'tuningParams': ['growthTime: 6.0 s'],
                        'edgeCases': [
                          '[PLOT BUSY GUARD] Block planting on occupied plot',
                        ],
                        'checkpoints': [
                          {
                            'title': 'Playable Soil Plot Planting',
                            'playtestCriteria':
                                'Plant seed in plot and harvest ammo pod.',
                            'tasks': [
                              'Build soil plot interaction and growth timer (1.5h)',
                              'Spawn harvestable ammo pod when timer completes (1.5h)',
                            ],
                          },
                        ],
                      },
                    ],
                  },
                  {
                    'id': 'beat_2',
                    'title': 'Day Night Phase Shift',
                    'goal':
                        'Trigger sunset transition and spawn enemy waves.',
                    'doneWhen': 'Bell switches phase to night.',
                    'features': [
                      {
                        'id': 'feat_2_1',
                        'title': 'Sunset Wave Bell',
                        'lifecycle': 'new',
                        'included': true,
                        'estimatedHours': 3,
                        'goal': 'Transition from day planting to night combat.',
                        'inScope': ['Phase state switch and wave trigger'],
                        'doneWhen':
                            'Ringing bell switches phase to night and spawns enemies.',
                        'tuningParams': ['waveCount: 5 enemies'],
                        'edgeCases': [
                          '[NIGHT LOCK GUARD] Disable bell during active night wave',
                        ],
                        'checkpoints': [
                          {
                            'title': 'Playable Sunset Wave Bell',
                            'playtestCriteria':
                                'Ring bell to shift into night wave combat.',
                            'tasks': [
                              'Create bell interactable and day/night state switch (1.5h)',
                              'Trigger night enemy spawner on phase change (1.5h)',
                            ],
                          },
                        ],
                      },
                    ],
                  },
                  {
                    'id': 'beat_3',
                    'title': 'Dash Reload Combat',
                    'goal':
                        'Dash through enemies to reload shells and fire.',
                    'doneWhen': 'Dashing through enemy refills 2 shells.',
                    'features': [
                      {
                        'id': 'feat_3_1',
                        'title': 'Dash Burst',
                        'lifecycle': 'new',
                        'included': true,
                        'estimatedHours': 3,
                        'goal': 'Dash across the arena with brief i-frames.',
                        'inScope': ['Dash velocity burst and cooldown'],
                        'doneWhen':
                            'Player dashes cleanly without clipping walls.',
                        'tuningParams': ['dashSpeed: 420.0 px/s'],
                        'edgeCases': [
                          '[COOLDOWN GUARD] Block dash during active cooldown',
                        ],
                        'checkpoints': [
                          {
                            'title': 'Playable Dash Burst',
                            'playtestCriteria': 'Dash forward with Spacebar.',
                            'tasks': [
                              'Implement 2D dash velocity impulse and timer (1.5h)',
                              'Add dash trail visual and cooldown guard (1.5h)',
                            ],
                          },
                        ],
                      },
                      {
                        'id': 'feat_3_2',
                        'title': 'Dash Strike Reload',
                        'lifecycle': 'new',
                        'included': true,
                        'estimatedHours': 3,
                        'goal':
                            'Refill shotgun ammo by dashing through enemies.',
                        'inScope': ['Dash overlap detector and ammo refill'],
                        'doneWhen':
                            'Dashing through an enemy refills 2 shells up to maxAmmo.',
                        'tuningParams': ['reloadPerDash: 2 shells'],
                        'edgeCases': [
                          '[MAX AMMO GUARD] Clamp shell count to maxCapacity',
                        ],
                        'checkpoints': [
                          {
                            'title': 'Playable Dash Strike Reload',
                            'playtestCriteria':
                                'Refill 2 shells when dashing through an enemy.',
                            'tasks': [
                              'Detect enemy overlap during active dash state (1.5h)',
                              'Increment currentAmmo and play reload cue (1.5h)',
                            ],
                          },
                        ],
                      },
                    ],
                  },
                ],
              };
            } else {
              // Fix 3B test case: In v0.2, LLM returns 3 beats where Beat #3 is a brand-new topic ("Farm Upgrading")
              // at positional index 2 (where "Dash Reload Combat" lives).
              return {
                'goal':
                    'Test multi-stage crop growth, sunset hazards, and plot upgrades.',
                'doneWhen': 'Playtester verifies v0.2 upgrades.',
                'explicitExclusions': ['No online co-op'],
                'beats': [
                  {
                    'id': 'beat_1',
                    'title': 'Crop Growth Cycle',
                    'goal': 'Upgrade soil plots with fertilizer boost.',
                    'doneWhen': 'Fertilized plots drop 2x pods.',
                    'features': [
                      {
                        'id': 'feat_1_1',
                        'title': 'Soil Plot Planting',
                        'lifecycle': 'upgrade',
                        'included': true,
                        'estimatedHours': 3,
                        'goal':
                            'Add fertilizer yield boost to soil plots.',
                        'inScope': ['Fertilizer interaction and 2x yield'],
                        'doneWhen':
                            'Fertilized plot drops 2x ammo pods on harvest.',
                        'tuningParams': ['fertilizerMultiplier: 2.0x'],
                        'edgeCases': [
                          '[DOUBLE FERTILIZE GUARD] Block second fertilizer on same plot',
                        ],
                        'checkpoints': [
                          {
                            'title': 'Fertilizer Yield Upgrade',
                            'playtestCriteria':
                                'Apply fertilizer to double ammo pod harvest.',
                            'tasks': [
                              'Add fertilizer state and 2x pod spawn multiplier (1.5h)',
                              'Add fertilized soil tint and harvest pop cue (1.5h)',
                            ],
                          },
                        ],
                      },
                    ],
                  },
                  {
                    'id': 'beat_2',
                    'title': 'Day Night Transition',
                    'goal': 'Upgrade sunset bell with early-ring bonus.',
                    'doneWhen': 'Early bell ring drops bonus seed packet.',
                    'features': [
                      {
                        'id': 'feat_2_1',
                        'title': 'Sunset Wave Bell',
                        'lifecycle': 'upgrade',
                        'included': true,
                        'estimatedHours': 3,
                        'goal':
                            'Reward early bell activation with bonus seeds.',
                        'inScope': ['Early-ring timer check and bonus drop'],
                        'doneWhen':
                            'Ringing bell early drops 1 bonus seed packet.',
                        'tuningParams': ['earlyBonusSeeds: 1 packet'],
                        'edgeCases': [
                          '[DUSK EXPIRED GUARD] No bonus after dusk timer ends',
                        ],
                        'checkpoints': [
                          {
                            'title': 'Early Bell Bonus Upgrade',
                            'playtestCriteria':
                                'Ring bell early to earn bonus seed packet.',
                            'tasks': [
                              'Track remaining daylight time on bell activation (1.5h)',
                              'Spawn bonus seed packet when triggered early (1.5h)',
                            ],
                          },
                        ],
                      },
                    ],
                  },
                  {
                    'id': 'beat_3',
                    'title': 'Farm Upgrading',
                    'goal': 'Unlock irrigation sprinklers for plots.',
                    'doneWhen': 'Sprinklers auto-water adjacent plots.',
                    'features': [
                      {
                        'id': 'feat_3_new',
                        'title': 'Sprinkler Auto-Water',
                        'lifecycle': 'new',
                        'included': true,
                        'estimatedHours': 3,
                        'goal':
                            'Auto-water adjacent soil plots each morning.',
                        'inScope': ['Sprinkler placement and radius water'],
                        'doneWhen':
                            'Placed sprinkler waters adjacent plots automatically.',
                        'tuningParams': ['sprinklerRadius: 120.0 px'],
                        'edgeCases': [
                          '[OVERLAP GUARD] Prevent placing two sprinklers on same tile',
                        ],
                        'checkpoints': [
                          {
                            'title': 'Playable Sprinkler Auto-Water',
                            'playtestCriteria':
                                'Place sprinkler and auto-water nearby plots.',
                            'tasks': [
                              'Build sprinkler placement node and radius check (1.5h)',
                              'Trigger watered state on adjacent plots at dawn (1.5h)',
                            ],
                          },
                        ],
                      },
                    ],
                  },
                ],
              };
            }
          }

          return _mockGeminiResponder(prompt, model);
        };

        final provider = WorkbenchProvider();
        await provider.startConceptInterview(
          'A 2D top-down arena shooter where you farm crops by day for shotgun ammo by night',
        );

        // Verify Fix 1: "2D Game Engine" normalized to "Godot 4 (GDScript)" and initial releaseTrainTitles capped to 1
        expect(provider.conceptDraft!.techSpec.first, 'Godot 4 (GDScript)');
        expect(provider.conceptDraft!.releaseTrainTitles.length, 1);

        // Verify Fix 1 on chat turn as well ("2D Engine" -> "Godot 4 (GDScript)")
        await provider.sendConceptChatMessage(
          'Add dash-through-enemy reload mechanic',
        );
        expect(provider.conceptDraft!.techSpec.first, 'Godot 4 (GDScript)');

        // Build v0.1 Release
        await provider.openReleasePlanGate();
        final v01RelDoc = provider.activeRelease!;
        expect(v01RelDoc.sections['prototypePart'], isNull);

        // Verify Fix 3A: Even though the LLM only returned 3 beats, all 5 Stage 1 Core Loop Beats are present in v0.1
        expect(provider.releaseBlueprint!.beats.length, 5);

        await provider.approveAndExecuteReleasePlan();

        // Verify Fix 4: Immediately after executeBlueprint, every feature task already has >= 3 sub-steps via eager TaskHowToBlueprint.resolve
        for (final beat in provider.activeReleaseBeats) {
          for (final feat in provider.featuresForBeat(beat.id)) {
            final states = FeatureStateNode.getStatesForDocument(feat);
            expect(states, isNotEmpty);
            for (final task in states.first.checklist) {
              expect(
                task.children.length,
                greaterThanOrEqualTo(3),
                reason:
                    'Feature "${feat.title}" task "${task.text}" must eagerly have >= 3 sub-steps immediately after executeBlueprint',
              );
            }
          }
        }

        // Verify Fix 2: 2D Game Spec & Tech Spec inject explicit 2D dimension guard into step synthesis prompt
        expect(capturedStepPrompts, isNotEmpty);
        expect(
          capturedStepPrompts.first,
          contains('PROJECT DIMENSION & CAMERA SPEC: 2D GAME'),
        );

        // Test Feature Inbox in v0.1:
        // 1) Immediate ('now') Inbox item eagerly populates >= 3 sub-steps
        final nowInbox = await provider.submitFeatureIdeaToInbox(
          'Add shotgun knockback recoil when firing heavy shells',
          preferredBeatId: provider.activeReleaseBeats[2].id,
        );
        expect(nowInbox, isNotNull);
        expect(capturedInboxPrompts.last, contains('Game Spec: 2D Top-Down'));
        expect(
          capturedInboxPrompts.last,
          contains('Tech Spec: Godot 4 (GDScript)'),
        );
        final nowFeatId = await provider.acceptFeatureInboxTriage(nowInbox!.id);
        expect(nowFeatId, isNotNull);
        final nowFeatDoc = provider.documents[nowFeatId!]!;
        final nowFeatStates = FeatureStateNode.getStatesForDocument(nowFeatDoc);
        for (final task in nowFeatStates.first.checklist) {
          expect(task.children.length, greaterThanOrEqualTo(3));
        }

        // 2) Scheduled ('futureRelease' -> 02 · MVP) Inbox item with newEpicAndFeature ("Physical Seed Combiner")
        final mvpInbox = await provider.submitFeatureIdeaToInbox(
          'Add Seed Mutator Workbench to combine two seeds between waves',
          preferredBeatId: provider.activeReleaseBeats.first.id,
        );
        expect(mvpInbox, isNotNull);
        expect(
          mvpInbox!.integrationMode,
          equals(InboxIntegrationMode.newEpicAndFeature),
        );
        expect(
          mvpInbox.releaseTimingMode,
          equals(InboxReleaseTimingMode.futureRelease),
        );
        expect(mvpInbox.targetFuturePhase, equals(ProductionPhase.mvp));
        await provider.acceptFeatureInboxTriage(mvpInbox.id);
        expect(provider.scheduledFeatureInboxItems, hasLength(1));

        // Advance to v0.2 (02 · MVP)
        await provider.prepareProgressiveNextReleaseDraft();
        final v02Bp = provider.releaseBlueprint!;

        // Verify Fix 3B:
        // - Beat #1 and Beat #2 keep their canonical Stage 1 / v0.1 Epic titles ("Crop Planting & Harvest", "Day Night Phase Shift"), never renamed to "Crop Growth Cycle" or "Day Night Transition"
        // - Beat #3 ("Dash Reload Combat") is NOT overwritten by positional Beat #3 ("Farm Upgrading") and preserves its v0.1 features (Dash Burst, Dash Strike Reload, Shotgun Knockback Recoil)
        // - "Farm Upgrading" is appended as a new Epic
        final v02BeatTitles = v02Bp.beats.map((b) => b.title).toList();
        expect(v02BeatTitles, contains('Crop Planting & Harvest'));
        expect(v02BeatTitles, contains('Day Night Phase Shift'));
        expect(v02BeatTitles, contains('Dash Reload Combat'));
        expect(v02BeatTitles, contains('Farm Upgrading'));
        expect(v02BeatTitles, isNot(contains('Crop Growth Cycle')));
        expect(v02BeatTitles, isNot(contains('Day Night Transition')));

        final dashBeatInV02 = v02Bp.beats.firstWhere(
          (b) => b.title == 'Dash Reload Combat',
        );
        final dashFeatTitles =
            dashBeatInV02.features.map((f) => f.title).toList();
        expect(dashFeatTitles, contains('Dash Burst'));
        expect(dashFeatTitles, contains('Dash Strike Reload'));
        expect(dashFeatTitles, contains('Shotgun Knockback Recoil'));

        // Verify Fix 5: Scheduled 02 · MVP newEpicAndFeature ("Physical Seed Combiner" in "Seed Combiner Station") is auto-injected into v0.2!
        expect(v02BeatTitles, contains('Seed Combiner Station'));
        final combinerBeat = v02Bp.beats.firstWhere(
          (b) => b.title == 'Seed Combiner Station',
        );
        expect(
          combinerBeat.features.any(
            (f) => f.title == 'Physical Seed Combiner',
          ),
          isTrue,
        );

        await provider.approveAndExecuteReleasePlan();
        expect(provider.scheduledFeatureInboxItems, isEmpty);
      },
    );

    test(
      '2nd Project Multi-Project Vault & Token Optimization Audit ("Submerged Mech Salvage" Unity 6 C# after "Crop Shotgun Arena" Godot 4)',
      () async {
        int planReleaseCalls = 0;
        GeminiAgentClient.testMockResponder = (prompt, model) async {
          if (prompt.contains('planning Release:') &&
              !prompt.contains('DELTA-ONLY BEATS')) {
            planReleaseCalls++;
            if (prompt.contains('Submerged Mech Salvage')) {
              return {
                'releaseTitle': 'v0.1: Trench Walk & Harpoon Tow - Prototype',
                'releasePhase': 'prototype',
                'agentReasoning':
                    'Prioritizes weighted 3D seabed movement and physics-tethered harpoon towing.',
                'goal':
                    'Build a playable 3D abyssal trench salvage loop in Unity 6.',
                'doneWhen':
                    'Playtester walks the trench, winches a core, defends against drones, and docks.',
                'explicitExclusions': ['4-Player Co-Op'],
                'questions': [],
                'beats': [
                  {
                    'id': 'beat_1',
                    'title': 'Exo-Rig Trench Walk',
                    'goal': 'Build weighted 3D exo-rig movement.',
                    'doneWhen': 'Player walks across the trench floor.',
                    'features': [
                      {
                        'id': 'feat_1_1',
                        'title': 'Exo-Rig Buoyancy Walk',
                        'goal': 'Implement 3D Rigidbody movement.',
                        'doneWhen': 'Rig walks and jumps with thruster hop.',
                        'estimatedHours': 4,
                        'included': true,
                        'lifecycle': 'new',
                        'inScope': ['Rigidbody movement'],
                        'outOfScope': [],
                        'tuningParams': ['moveForce: 18000 N'],
                        'edgeCases': [
                          '[DEPTH GUARD] Clamp downward velocity on trench floor impact',
                        ],
                        'checkpoints': [
                          {
                            'title': 'Exo-Rig Buoyancy Walk',
                            'playtestCriteria':
                                'Hold WASD -> Rig walks with weighted footstep drag',
                            'tasks': [
                              'Configure ExoRigController Rigidbody (2h)',
                              'Implement WASD movement and thruster impulse (1h)',
                              'Clamp terminal sink speed (1h)',
                            ],
                          },
                        ],
                      },
                    ],
                  },
                  {
                    'id': 'beat_2',
                    'title': 'Harpoon Winch & Tow',
                    'goal': 'Build harpoon firing and cable towing.',
                    'doneWhen': 'Player winches heavy salvage cores.',
                    'features': [
                      {
                        'id': 'feat_2_1',
                        'title': 'Harpoon Cable Winch',
                        'goal': 'Fire harpoon projectile and reel target.',
                        'doneWhen': 'Harpoon latches onto salvage core.',
                        'estimatedHours': 4,
                        'included': true,
                        'lifecycle': 'new',
                        'inScope': ['ConfigurableJoint winch'],
                        'outOfScope': [],
                        'tuningParams': ['maxCableLength: 28.0 m'],
                        'edgeCases': [
                          '[TENSION GUARD] Auto-detach cable if tension exceeds limit',
                        ],
                        'checkpoints': [
                          {
                            'title': 'Harpoon Cable Winch',
                            'playtestCriteria':
                                'Fire harpoon -> core reels toward rig',
                            'tasks': [
                              'Create HarpoonProjectile and ConfigurableJoint (2h)',
                              'Implement cable reel-in force (1h)',
                              'Add LineRenderer cable visual (1h)',
                            ],
                          },
                        ],
                      },
                    ],
                  },
                ],
              };
            }
          }
          if (prompt.contains('DELTA-ONLY BEATS')) {
            // Simulate LLM returning schema placeholder "id": "beat_1" and "id": "feat_1_1"
            // while targeting Beat #2 ("Harpoon Winch & Tow") by title to add a 2nd feature
            return {
              'reply':
                  'Added Cable Tension Snap Meter to Harpoon Winch & Tow.',
              'goal':
                  'Build a playable 3D abyssal trench salvage loop in Unity 6.',
              'doneWhen':
                  'Playtester walks the trench, winches a core with tension gauge, and docks.',
              'explicitExclusions': ['4-Player Co-Op'],
              'beats': [
                {
                  'id': 'beat_1',
                  'title': 'Harpoon Winch & Tow',
                  'goal': 'Build harpoon firing, cable towing, and tension HUD.',
                  'doneWhen':
                      'Player winches heavy salvage cores without snapping the cable.',
                  'features': [
                    {
                      'id': 'feat_1_1',
                      'title': 'Cable Tension Snap Meter',
                      'goal':
                          'Display live cable strain and snap cable if redlined.',
                      'doneWhen':
                          'Tension bar fills during heavy tow and snaps after 1.5s overload.',
                      'estimatedHours': 3,
                      'included': true,
                      'lifecycle': 'new',
                      'inScope': ['Tension gauge UI'],
                      'outOfScope': [],
                      'tuningParams': ['overloadSnapDuration: 1.5 s'],
                      'edgeCases': [
                        '[SNAP GUARD] Reset tension gauge on detach',
                      ],
                      'checkpoints': [
                        {
                          'title': 'Cable Tension Snap Meter',
                          'playtestCriteria':
                              'Tow trapped core -> gauge flashes red and snaps after 1.5s',
                          'tasks': [
                            'Calculate joint force ratio (1h)',
                            'Bind CableTensionSlider color (1h)',
                            'Trigger joint break on overload (1h)',
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            };
          }
          if (prompt.contains(
            'creating a Stage 1 Concept Blueprint for this spark idea:',
          )) {
            if (prompt.contains('Crop Shotgun Arena')) {
              return {
                'reply': 'Drafted Crop Shotgun Arena.',
                'title': 'Crop Shotgun Arena',
                'goal': 'Build a 2D farm-and-fight arena loop.',
                'gameSpec': ['Perspective: 2D Top-Down'],
                'techSpec': ['Engine: Godot 4 (GDScript)'],
                'designPillars': ['Fast Action: Every crop fuels combat'],
                'tradeOffs': ['Arcade speed over farming sim'],
                'coreLoopBeats': [
                  'Crop Planting & Harvest: Plant and harvest crops',
                ],
                'exclusions': ['Multiplayer'],
                'doneWhen': 'Player completes 1 loop.',
                'sectionOptions': <String, dynamic>{},
                'clarifyingQuestions': <dynamic>[],
              };
            }
            return {
              'reply': 'Drafted Submerged Mech Salvage.',
              'title': 'Submerged Mech Salvage',
              'goal':
                  'Build a 3D underwater mech salvage loop in Unity 6.',
              'gameSpec': ['Perspective: 3D Third-Person Over-Shoulder'],
              'techSpec': ['Engine: Unity 6 (C#)'],
              'designPillars': ['Crushing Abyssal Weight: Heavy momentum'],
              'tradeOffs': [
                'Tethered cable physics over free-swimming arcade flight',
              ],
              'coreLoopBeats': [
                'Exo-Rig Trench Walk: Walk across the seabed in a weighted rig',
                'Harpoon Winch & Tow: Latch onto salvage cores and winch them',
              ],
              'exclusions': ['4-Player Co-Op'],
              'doneWhen': 'Player extracts 2 cores.',
              'sectionOptions': <String, dynamic>{},
              'clarifyingQuestions': <dynamic>[],
            };
          }
          return _mockGeminiResponder(prompt, model);
        };

        final provider = WorkbenchProvider(enableAutoLoad: false);

        // 1. Set up Project #1 ("Crop Shotgun Arena") and advance it to MVP with retrospective state
        await provider.startConceptInterview('Crop Shotgun Arena');
        final proj1Id = provider.activeProject!.id;
        await provider.approveConceptAndBuildRelease();
        await provider.prepareProgressiveNextReleaseDraft();
        await provider.approveAndExecuteReleasePlan();
        expect(provider.currentPhase, equals(ProductionPhase.mvp));
        expect(provider.lastReleaseRetrospective, isNotNull);

        // 2. Create Project #2 via createNewProject() — verify Bug 1 Fix (full state isolation)
        provider.createNewProject();
        expect(provider.currentPhase, equals(ProductionPhase.prototype));
        expect(provider.lastReleaseRetrospective, isNull);
        expect(provider.releaseViewFilter, equals('active'));
        expect(provider.executionLog, isEmpty);

        // 3. Draft Project #2 ("Submerged Mech Salvage", Unity 6 C#) and verify Cost Fix 1
        // (Stage 1 concept edits do NOT trigger background planRelease pre-warm calls)
        planReleaseCalls = 0;
        await provider.startConceptInterview('Submerged Mech Salvage');
        final proj2Id = provider.activeProject!.id;
        expect(proj2Id, isNot(equals(proj1Id)));
        provider.updateConceptDraft((d) {
          d.techSpec = ['Engine: Unity 6 (C#)', 'Platform: Desktop PC'];
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          planReleaseCalls,
          equals(0),
          reason:
              'Stage 1 concept interview and inline edits must not fire wasteful background planRelease pre-warm calls',
        );

        // 4. Open Release Plan Gate for v0.1 and test delta chat turn (Bug 2 Fix)
        await provider.openReleasePlanGate();
        expect(planReleaseCalls, equals(1));
        expect(provider.releaseBlueprint!.beats, hasLength(2));

        await provider.sendReleasePlanChatMessage(
          'Add Cable Tension Snap Meter to Harpoon Winch & Tow',
        );
        final bpAfterChat = provider.releaseBlueprint!;
        expect(
          bpAfterChat.beats[0].title,
          equals('Exo-Rig Trench Walk'),
          reason:
              'Beat #1 must not be overwritten when LLM delta returns placeholder id beat_1 for Beat #2',
        );
        expect(bpAfterChat.beats[0].features, hasLength(1));
        expect(
          bpAfterChat.beats[0].features.first.title,
          equals('Exo-Rig Buoyancy Walk'),
        );
        expect(bpAfterChat.beats[1].title, equals('Harpoon Winch & Tow'));
        expect(
          bpAfterChat.beats[1].features.map((f) => f.title).toList(),
          equals(['Harpoon Cable Winch', 'Cable Tension Snap Meter']),
        );
        expect(
          bpAfterChat.beats[1].features[1].id,
          isNot(equals('feat_1_1')),
          reason: 'Added feature in Beat #2 must receive a unique feature ID',
        );

        // 5. Execute v0.1 and verify Bug 3 Fix (persisted release_blueprint_json has updated epic_... and feat_... IDs)
        await provider.approveAndExecuteReleasePlan();
        final relDoc = provider.activeRelease!;
        final persistedBpJson =
            relDoc.sections['release_blueprint_json'] ?? '';
        for (final epicDoc in provider.activeReleaseBeats) {
          expect(persistedBpJson, contains(epicDoc.id));
        }

        // 6. Verify Bug 5 Fix: addLiveFeatureToBeat immediately seeds 3 tasks with >= 3 eager sub-steps each
        final addedFeatId = provider.addLiveFeatureToBeat(
          provider.activeReleaseBeats.first.id,
          'Sonar Ping Scanner',
        );
        expect(addedFeatId, isNotNull);
        final addedFeatDoc = provider.documents[addedFeatId!]!;
        final addedStates = FeatureStateNode.getStatesForDocument(addedFeatDoc);
        expect(addedStates.first.checklist, hasLength(3));
        for (final task in addedStates.first.checklist) {
          expect(task.children.length, greaterThanOrEqualTo(3));
        }

        // 7. Verify Bug 4 Fix: logPlaytestIssueOnCheckpoint on Unity 6 (C#) project uses C# Debug.LogWarning & .cs path
        final firstFeat =
            provider.featuresForBeat(provider.activeReleaseBeats.first.id).first;
        final firstStates = FeatureStateNode.getStatesForDocument(firstFeat);
        final fixIdx = provider.logPlaytestIssueOnCheckpoint(
          featureId: firstFeat.id,
          states: firstStates,
          checkpointIndex: 0,
          issueDescription:
              'Winch cable pulls mech through seafloor terrain collider',
        );
        expect(fixIdx, greaterThanOrEqualTo(0));
        final fixSub1 =
            FeatureStateNode.getStatesForDocument(firstFeat)
                .first
                .checklist[fixIdx]
                .children
                .first;
        expect(fixSub1.codeSnippet, contains('Debug.LogWarning'));
        expect(
          fixSub1.codeLanguage,
          equals('Assets/Scripts/PlaytestFixController.cs'),
        );

        // 8. Verify Multi-Project Vault Switching (Project #2 <-> Project #1)
        expect(provider.savedProjects, hasLength(2));
        provider.switchProject(proj1Id);
        expect(provider.activeProject!.title, equals('Crop Shotgun Arena'));
        expect(provider.conceptDraft!.title, equals('Crop Shotgun Arena'));

        provider.switchProject(proj2Id);
        expect(provider.activeProject!.title, equals('Submerged Mech Salvage'));
        expect(provider.conceptDraft!.title, equals('Submerged Mech Salvage'));

        // 9. Verify Pure gemini-flash-latest (LOW) configuration & Focused Context Architecture:
        expect(
          WorkbenchProvider.availablePlanningModels,
          isNot(contains('gemini-4-argon')),
        );
        expect(provider.thinkingLevel, equals('LOW'));

        String? capturedStepSynthPrompt;
        String? capturedTailorPrompt;
        String? capturedOptionRegenPrompt;
        String? capturedGddPrompt;
        String? capturedRelChatPrompt;
        int sonarStepSynthCalls = 0;
        GeminiAgentClient.testMockResponder = (prompt, model) async {
          if (prompt.contains(
            'You are the Antigravity Release Planner Agent updating',
          )) {
            capturedRelChatPrompt = prompt;
            return _mockGeminiResponder(prompt, model);
          }
          if (prompt.contains(
            'Synthesize concrete, beginner-friendly 3-Area Engine How-To steps for Feature',
          )) {
            capturedStepSynthPrompt = prompt;
            if (prompt.contains('"Hull Breach Welder"')) {
              sonarStepSynthCalls++;
            }
            return _mockGeminiResponder(prompt, model);
          }
          if (prompt.contains(
            'Break this task down into the exact number of checkable How-To Sub-Steps',
          )) {
            capturedTailorPrompt = prompt;
            return {
              'subSteps': [
                {
                  'title': 'STEP 1.1 · WIRE HARPOON REEL JOINT',
                  'stepPath': 'Assets/Scripts/HarpoonWinch.cs',
                  'instruction': 'Attach ConfigurableJoint to HarpoonWinch.',
                  'area1Hierarchy': 'HarpoonWinch\n └─ WinchCableJoint',
                  'area2Inspector': 'maxReelForce: 450 N | cableDamping: 0.8',
                  'codeFormula': 'winchJoint.xMotion = ConfigurableJointMotion.Limited;',
                  'verifyResult': 'Cable reels in target core cleanly in Play mode.',
                },
              ],
            };
          }
          if (prompt.contains('generating 3 fresh Option Cards for the')) {
            capturedOptionRegenPrompt = prompt;
            return {
              'options': [
                'Tight Salvage Spec: 3D Third-Person Action · PC (Steam) · Single-Player PvE · Trench Arena',
                'Cockpit Sim Spec: 3D Cockpit Sim · PC & Steam Deck · 2-Player Co-Op · Modular Wreck',
                'Side-View Spec: 2.5D Side-View Action · PC & Switch · Single-Player · Abyssal Shaft',
              ],
            };
          }
          if (prompt.contains('FAITHFUL GDD EXTRACTION')) {
            capturedGddPrompt = prompt;
            return _mockGeminiResponder(prompt, model);
          }
          return _mockGeminiResponder(prompt, model);
        };

        // Select 2nd feature ("Harpoon Cable Winch") and verify prompt includes Stage 1 Pillars, Trade-Offs, and Preceding Feature #1 Ledger with derived asset & goal
        final secondBeat = provider.activeReleaseBeats[1];
        final secondBeatFirstFeat =
            provider.featuresForBeat(secondBeat.id).first;
        await provider.synthesizeFeatureHowToStepsWithAi(
          secondBeatFirstFeat.id,
          forceRefresh: true,
        );
        expect(
          WorkbenchProvider.availableConversationModels,
          equals(const ['gemini-flash-latest']),
        );
        expect(
          WorkbenchProvider.availablePlanningModels,
          equals(const ['gemini-flash-latest']),
        );
        expect(capturedStepSynthPrompt, isNotNull);
        expect(capturedStepSynthPrompt, contains('Design Pillars:'));
        expect(capturedStepSynthPrompt, contains('Trade-Offs:'));
        expect(capturedStepSynthPrompt, contains('Feature Goal:'));
        expect(capturedStepSynthPrompt, contains('Checkpoint Playtest Gate:'));
        expect(
          capturedStepSynthPrompt,
          contains('PlayerController.cs / MonoBehaviour Prefab'),
        );
        expect(
          capturedStepSynthPrompt,
          isNot(contains('BP_PlayerCharacter')),
          reason:
              'Unity 6 step synthesis prompt must not contain hardcoded Unreal 5 BP_PlayerCharacter instructions',
        );
        expect(
          capturedStepSynthPrompt,
          contains('CUMULATIVE PROJECT LEDGER'),
        );
        expect(capturedStepSynthPrompt, contains('assets=['));

        // Verify addLiveFeatureToBeat only triggers step synthesis ONCE (not twice via selectFeature + _enrichLiveFeatureWithAi)
        final welderFeatId = provider.addLiveFeatureToBeat(
          provider.activeReleaseBeats.first.id,
          'Hull Breach Welder',
        );
        expect(welderFeatId, isNotNull);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          sonarStepSynthCalls,
          lessThanOrEqualTo(1),
          reason:
              'addLiveFeatureToBeat must not fire duplicate synthesizeFeatureHowToStepsWithAi calls',
        );

        // Verify tailorTaskHowToSubSteps encodes 3-Area notes (area1Hierarchy & area2Inspector)
        final winchStates =
            FeatureStateNode.getStatesForDocument(secondBeatFirstFeat);
        final tailoredOk = await provider.tailorTaskHowToSubSteps(
          featureId: secondBeatFirstFeat.id,
          states: winchStates,
          checkpointIndex: 0,
          taskIndex: 0,
          userContext: 'HarpoonWinch with WinchCableJoint',
        );
        expect(tailoredOk, isTrue);
        final tailoredSub = FeatureStateNode.getStatesForDocument(
          secondBeatFirstFeat,
        ).first.checklist.first.children.first;
        final decodedThreeArea =
            TaskHowToBlueprint.decodeThreeAreaNotes(tailoredSub.specNotes);
        expect(
          decodedThreeArea.area1Hierarchy,
          equals('HarpoonWinch\n └─ WinchCableJoint'),
        );
        expect(
          decodedThreeArea.area2Inspector,
          equals('maxReelForce: 450 N | cableDamping: 0.8'),
        );
        expect(capturedTailorPrompt, isNotNull);
        expect(
          capturedTailorPrompt,
          contains('Project Specs (match exact 2D/3D classes and camera):'),
        );
        expect(capturedTailorPrompt, contains('Playtest Gate:'));

        // Verify Stage 1B Option Card Regeneration injects exact Section Format Rules
        final regenOpts = await ProjectConceptAgent.regenerateSectionOptionsWithAi(
          draft: provider.conceptDraft!,
          optionKey: 'gameSpec',
          currentOptions: const [],
          apiKey: 'mock-key',
          modelName: 'gemini-flash-latest',
          thinkingLevel: 'HIGH',
        );
        expect(regenOpts, isNotNull);
        expect(regenOpts!.first, contains(' · '));
        expect(capturedOptionRegenPrompt, isNotNull);
        expect(
          capturedOptionRegenPrompt,
          contains('4 `·`-separated cells after the colon'),
        );

        // Verify GDD extraction mode passes isGddExtraction: true so pasted docs are extracted rather than treated as a 1-line spark
        await ProjectConceptAgent.extractConceptFromGdd(
          '# Salvage Protocol\n## Core Loop\nDive -> Cut Hull -> Extract Core',
          apiKey: 'mock-key',
          modelName: 'gemini-flash-latest',
          thinkingLevel: 'HIGH',
        );
        expect(capturedGddPrompt, isNotNull);
        expect(
          capturedGddPrompt,
          contains('FAITHFUL GDD EXTRACTION'),
        );

        // Verify _enrichLiveFeatureWithAi persists tuning and edge_cases onto featDoc.sections
        final welderDoc = provider.documents[welderFeatId]!;
        expect(welderDoc.sections['tuning'], isNotEmpty);
        expect(welderDoc.sections['edge_cases'], isNotEmpty);

        // Verify ReleasePlannerAgent.sendReleasePlanChatTurn resolves snake_case game_spec / tech_spec / design_pillars / trade_offs
        await provider.sendReleasePlanChatMessage(
          'Add a hull pressure alarm warning to Epic 1',
        );
        expect(capturedRelChatPrompt, isNotNull);
        expect(
          capturedRelChatPrompt,
          isNot(
            contains(
              'Concept Context: Game Spec:  | Tech Spec:  | Pillars:  | Trade-Offs:',
            ),
          ),
        );
        expect(capturedRelChatPrompt, contains('Unity 6 (C#)'));

        // Verify Native Gemini Function Calling tool schemas & typed argument parsers
        expect(
          ProjectConceptAgent.commitConceptBlueprintTool['name'],
          equals('commit_concept_blueprint'),
        );
        expect(
          ProjectConceptAgent.updateConceptSectionTool['name'],
          equals('update_concept_section'),
        );
        expect(
          ReleasePlannerAgent.commitReleasePlanTool['name'],
          equals('commit_release_plan'),
        );
        expect(
          ReleasePlannerAgent.mutateReleasePlanTool['name'],
          equals('mutate_release_plan'),
        );
        expect(
          WorkbenchReleaseMixin.commitFeatureHowToStepsTool['name'],
          equals('commit_feature_howto_steps'),
        );

        // Verify dynamic {role, title} checkpoint task array parsing & role ordering (supports 1..N middle tasks)
        final dynamicToolTasks =
            ReleasePlannerAgent.extractCheckpointTasksFromMap({
          'tasks': [
            {
              'role': 'core_action_and_math',
              'title': 'Harpoon Reel Tension Math (2h)',
            },
            {
              'role': 'entity_and_collision_foundation',
              'title': 'Winch Mount & Cable Body (2h)',
            },
            {
              'role': 'core_action_and_math',
              'title': 'Scrap Mass Drag Scaling (1h)',
            },
            {
              'role': 'feedback_and_boundary_guard',
              'title': 'Snap Threshold & Sparks (1h)',
            },
            {
              'role': 'core_action_and_math',
              'title': 'Docking Clamp Release (1h)',
            },
          ],
        });
        expect(dynamicToolTasks.length, equals(5));
        expect(dynamicToolTasks[0], equals('Winch Mount & Cable Body (2h)'));
        expect(dynamicToolTasks[1], equals('Harpoon Reel Tension Math (2h)'));
        expect(dynamicToolTasks[2], equals('Scrap Mass Drag Scaling (1h)'));
        expect(dynamicToolTasks[3], equals('Docking Clamp Release (1h)'));
        expect(dynamicToolTasks[4], equals('Snap Threshold & Sparks (1h)'));

        // Verify Stage 1 Section-Scoped Tools isolate each stepper section (01..08) and prevent cross-section bleed
        final tradeOffTool = ProjectConceptAgent.buildFocusedConceptSectionTool(
          '[Section 05 Trade-Offs]',
        );
        expect(tradeOffTool['name'], equals('update_trade_offs_section'));
        final tradeOffProps =
            (tradeOffTool['parameters'] as Map)['properties'] as Map;
        expect(tradeOffProps.containsKey('tradeOffs'), isTrue);
        expect(tradeOffProps.containsKey('goal'), isFalse);
        expect(tradeOffProps.containsKey('coreLoopBeats'), isFalse);

        final techSpecTool = ProjectConceptAgent.buildFocusedConceptSectionTool(
          '[Section 03 Tech Spec]',
        );
        expect(techSpecTool['name'], equals('update_tech_spec_section'));
        final fullReviewTool =
            ProjectConceptAgent.buildFocusedConceptSectionTool(
          '[Section 09 Full Concept Review]',
        );
        expect(fullReviewTool['name'], equals('update_concept_section'));

        // Verify structured Trade-Off & Design Pillar tool object parsers
        final parsedTradeOffs = ProjectConceptAgent.parseTradeOffsList([
          {
            'priorityX': 'Immediate winch physics',
            'overAlternativeY': 'Complex rope simulation',
          },
        ]);
        expect(
          parsedTradeOffs,
          equals(['Immediate winch physics over Complex rope simulation']),
        );
        final parsedPillars = ProjectConceptAgent.parsePillarsList([
          {
            'pillarName': 'Claustrophobic Tension',
            'playerExperience': 'Every hull cut risks flooding the dive rig.',
          },
        ]);
        expect(
          parsedPillars,
          equals([
            'Claustrophobic Tension: Every hull cut risks flooding the dive rig.',
          ]),
        );

        // Verify Stage 2 Surface-Specific Tools are registered
        expect(
          WorkbenchReleaseMixin.commitTailoredTaskSubStepsTool['name'],
          equals('commit_tailored_task_substeps'),
        );
        expect(
          WorkbenchReleaseMixin.commitPlaytestFixTool['name'],
          equals('commit_playtest_fix'),
        );
        expect(
          WorkbenchReleaseMixin.commitLiveFeatureEnrichmentTool['name'],
          equals('commit_live_feature_enrichment'),
        );
        expect(
          WorkbenchReleaseMixin.commitInboxFeatureTriageTool['name'],
          equals('commit_inbox_feature_triage'),
        );
        expect(
          WorkbenchReleaseMixin.commitCodeToSpecSyncTool['name'],
          equals('commit_code_to_spec_sync'),
        );

        // Verify Stage 1A Spark Intake & Expansion Tools and typed Section Option tools
        expect(
          ProjectConceptAgent.commitSparkIntakeTool['name'],
          equals('commit_spark_intake'),
        );
        expect(
          ProjectConceptAgent.proposeSparkExpansionCardsTool['name'],
          equals('propose_spark_expansion_cards'),
        );
        expect(
          ProjectConceptAgent.buildSectionOptionsTool('designPillars')['name'],
          equals('propose_design_pillar_options'),
        );
        expect(
          ProjectConceptAgent.buildSectionOptionsTool('coreLoop')['name'],
          equals('propose_core_loop_options'),
        );
        final parsedLoopOpts =
            ProjectConceptAgent.parseSectionOptionsToolOutput(
          'coreLoop',
          [
            {
              'label': 'High-Risk Salvage',
              'beats': ['Dive & Cut', 'Haul Scrap', 'Refuel Rig'],
            },
          ],
        );
        expect(
          parsedLoopOpts,
          equals(['High-Risk Salvage: Dive & Cut → Haul Scrap → Refuel Rig']),
        );

        // Verify AI Add Workflow Refinements:
        // 1. commitLiveFeatureEnrichmentTool includes inScope and primarySharedScriptOrScene
        final liveEnrichProps =
            (WorkbenchReleaseMixin.commitLiveFeatureEnrichmentTool['parameters']
                as Map)['properties'] as Map;
        expect(liveEnrichProps.containsKey('inScope'), isTrue);
        expect(
          liveEnrichProps.containsKey('primarySharedScriptOrScene'),
          isTrue,
        );

        // 2. commitInboxFeatureTriageTool uses typed { role, title } tasks & futureTasks + futureTuningParams & futureEdgeCases
        final inboxTriageProps =
            (WorkbenchReleaseMixin.commitInboxFeatureTriageTool['parameters']
                as Map)['properties'] as Map;
        expect(inboxTriageProps.containsKey('futureTuningParams'), isTrue);
        expect(inboxTriageProps.containsKey('futureEdgeCases'), isTrue);
        final inboxTasksSchema = inboxTriageProps['tasks'] as Map;
        final inboxTaskItemSchema = inboxTasksSchema['items'] as Map;
        expect(inboxTaskItemSchema['type'], equals('OBJECT'));
        final inboxFutureTasksSchema = inboxTriageProps['futureTasks'] as Map;
        final inboxFutureTaskItemSchema = inboxFutureTasksSchema['items'] as Map;
        expect(inboxFutureTaskItemSchema['type'], equals('OBJECT'));

        // 3. addBuildTaskToCheckpointWithAi appends a new task and preserves existing tasks 0..N-1
        final targetFeatForAddTask = provider.selectedFeature!;
        final statesBeforeAdd =
            FeatureStateNode.getStatesForDocument(targetFeatForAddTask);
        final cp0BeforeCount = statesBeforeAdd.first.checklist.length;
        final firstTaskFirstChildBefore =
            statesBeforeAdd.first.checklist.first.children.first.text;
        final addedTaskIdx = provider.addBuildTaskToCheckpointWithAi(
          featureId: targetFeatForAddTask.id,
          states: statesBeforeAdd,
          checkpointIndex: 0,
          rawTaskTitle: 'Tether Winch Recoil Clamp',
        );
        expect(addedTaskIdx, equals(cp0BeforeCount));
        final statesAfterAdd =
            FeatureStateNode.getStatesForDocument(targetFeatForAddTask);
        expect(
          statesAfterAdd.first.checklist.length,
          equals(cp0BeforeCount + 1),
        );
        expect(
          statesAfterAdd.first.checklist.last.text,
          equals('Tether Winch Recoil Clamp (2h)'),
        );
        expect(
          statesAfterAdd.first.checklist.first.children.first.text,
          equals(firstTaskFirstChildBefore),
        );

        // 4. Verify End-to-End AI & Workflow Audit fixes:
        // 4a. commitSparkIntakeTool & proposeSparkExpansionCardsTool require badge & description
        final sparkExpItems = (((ProjectConceptAgent
                    .commitSparkIntakeTool['parameters'] as Map)['properties']
                as Map)['expansionCards'] as Map)['items'] as Map;
        expect(
          sparkExpItems['required'],
          equals(['badge', 'title', 'description', 'additionSummary']),
        );
        final proposeExpItems = (((ProjectConceptAgent
                        .proposeSparkExpansionCardsTool['parameters']
                    as Map)['properties'] as Map)['expansionCards']
            as Map)['items'] as Map;
        expect(
          proposeExpItems['required'],
          equals(['badge', 'title', 'description', 'additionSummary']),
        );

        // 4b. updateConceptSectionTool enforces typed OBJECT schemas for gameSpec, techSpec, designPillars, tradeOffs
        final updateConceptProps = (ProjectConceptAgent
                .updateConceptSectionTool['parameters'] as Map)['properties']
            as Map;
        expect((updateConceptProps['gameSpec'] as Map)['type'], equals('OBJECT'));
        expect((updateConceptProps['techSpec'] as Map)['type'], equals('OBJECT'));
        expect(
          ((updateConceptProps['designPillars'] as Map)['items'] as Map)['type'],
          equals('OBJECT'),
        );
        expect(
          ((updateConceptProps['tradeOffs'] as Map)['items'] as Map)['type'],
          equals('OBJECT'),
        );

        // 4c. ReleaseExecutorAgent carries primary_asset into v0.2+ upgrade checkpoints
        targetFeatForAddTask.sections['primary_asset'] =
            'res://actors/salvage_winch.gd';
        final upgradeBp = ReleaseBlueprint(
          releaseDocId: provider.activeRelease!.id,
          releaseTitle: 'v0.2: Winch Upgrade',
          releaseVersionTag: 'v0.2',
          goal: 'Extend winch with tension overload.',
          doneWhen: 'Overload snaps cable at max tension.',
          questions: const [],
          beats: [
            ProposedBeatBlueprint(
              id: targetFeatForAddTask.parentId!,
              title: 'Core Loop Epic',
              goal: 'Extend winch.',
              doneWhen: 'Verified.',
              features: [
                ProposedFeatureBlueprint(
                  id: targetFeatForAddTask.id,
                  title: targetFeatForAddTask.title,
                  goal: 'Add tension overload.',
                  doneWhen: 'Verified.',
                  lifecycle: FeatureLifecycleStatus.upgrade,
                  originVersion: 'v0.1',
                  checkpoints: const [
                    ProposedCheckpointBlueprint(
                      title: 'Tension Overload',
                      playtestCriteria: 'Pull heavy scrap -> tension meter flashes',
                      tasks: ['Overload Meter (2h)'],
                      releaseVersion: 'v0.2',
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        await ReleaseExecutorAgent.executeBlueprint(
          releaseDoc: provider.activeRelease!,
          blueprint: upgradeBp,
          existingDocuments: provider.documents,
        );
        final upgradedStates =
            FeatureStateNode.getStatesForDocument(targetFeatForAddTask);
        expect(
          upgradedStates.last.parameters['primarySharedScriptOrScene'],
          equals('res://actors/salvage_winch.gd'),
        );

        // 4d. Stage 1 -> Stage 2 newly synced Core Loop Beat stamps needs_ai_enrichment and clears on selectFeature
        provider.conceptDraft!.coreLoopBeats.add(
          'Emergency Beacon Extraction: Trigger extraction flare and defend drop zone',
        );
        provider.syncConceptChangesToBuiltWorkbench(provider.conceptDraft!);
        final newlySyncedBeat = provider.activeReleaseBeats.last;
        final newlySyncedFeat =
            provider.featuresForBeat(newlySyncedBeat.id).first;
        expect(
          newlySyncedFeat.sections['needs_ai_enrichment'],
          equals('true'),
        );

        // 5. Pass 2 AI & Workflow Refinements
        // 5a. commitPlaytestFixTool exposes fixTaskTitle and tuningUpdates
        final playtestFixProps =
            (WorkbenchReleaseMixin.commitPlaytestFixTool['parameters']
                as Map)['properties'] as Map;
        expect(playtestFixProps.containsKey('fixTaskTitle'), isTrue);
        expect(playtestFixProps.containsKey('tuningUpdates'), isTrue);

        // 5b. commitInboxFeatureTriageTool & FeatureInboxItem support primarySharedScriptOrScene
        expect(
          inboxTriageProps.containsKey('primarySharedScriptOrScene'),
          isTrue,
        );
        final inboxSample = FeatureInboxItem(
          id: 'inbox_test_1',
          rawIdea: 'Add grapple hook',
          featureTitle: 'Grapple Hook',
          checkpointTitle: 'Hook & Swing',
          goal: 'Fire grapple hook and pull player to anchor.',
          doneWhen: 'Player swings across gap.',
          playtestGate: 'Aim at ledge -> fire hook -> swing across',
          targetBeatId: 'beat_1',
          targetBeatTitle: 'Core Movement',
          primarySharedScriptOrScene: 'res://actors/grapple_hook.gd',
        );
        final decodedInbox = FeatureInboxItem.fromJson(inboxSample.toJson());
        expect(
          decodedInbox.primarySharedScriptOrScene,
          equals('res://actors/grapple_hook.gd'),
        );

        // 5c. buildSectionOptionsTool('techSpec') uses canonical 'Unreal Engine 5 (Blueprints / C++)'
        final pass2TechSpecTool = ProjectConceptAgent.buildSectionOptionsTool(
          'techSpec',
        );
        final pass2TechSpecProps =
            (((pass2TechSpecTool['parameters'] as Map)['properties']
                    as Map)['options'] as Map)['items']
                as Map;
        final pass2EngineEnum =
            ((pass2TechSpecProps['properties'] as Map)['engine']
                as Map)['enum'] as List<dynamic>;
        expect(
          pass2EngineEnum,
          contains('Unreal Engine 5 (Blueprints / C++)'),
        );

        // 5d. updateFeatureStates automatically syncs _releaseBlueprint feature tuning, edgeCases, and task titles
        final liveDocForBpSync =
            provider.featuresForBeat(provider.activeReleaseBeats.first.id).first;
        final statesToMutate = FeatureStateNode.getStatesForDocument(
          liveDocForBpSync,
        );
        statesToMutate.last.tuningParams = ['syncTestSpeed = 777'];
        statesToMutate.last.edgeCases = ['[GUARD] Sync test guard'];
        statesToMutate.last.checklist.first.text = 'Synced Task Title (2h)';
        provider.updateFeatureStates(liveDocForBpSync.id, statesToMutate);
        final syncedBpFeat =
            provider.releaseBlueprint!.beats.first.features.firstWhere(
          (f) => f.title.toLowerCase() == liveDocForBpSync.title.toLowerCase(),
        );
        expect(syncedBpFeat.tuningParams, contains('syncTestSpeed = 777'));
        expect(syncedBpFeat.edgeCases, contains('[GUARD] Sync test guard'));
        expect(
          syncedBpFeat.checkpoints.last.tasks,
          contains('Synced Task Title (2h)'),
        );

        // 6. Pass 3 AI & Workflow Refinements
        // 6a. commitConceptBlueprintTool defines explicit OpenAPI properties on sectionOptions
        final conceptBpProps =
            (ProjectConceptAgent.commitConceptBlueprintTool['parameters']
                as Map)['properties'] as Map;
        final sectionOptsSchema = conceptBpProps['sectionOptions'] as Map;
        expect(sectionOptsSchema.containsKey('properties'), isTrue);
        final sectionOptsProps = sectionOptsSchema['properties'] as Map;
        expect(sectionOptsProps.containsKey('gameSpec'), isTrue);
        expect(sectionOptsProps.containsKey('techSpec'), isTrue);
        expect(sectionOptsProps.containsKey('coreLoop'), isTrue);

        // 6b. commitReleasePlanTool lifecycle enum includes 'stable'
        final relPlanBeatItems = (((ReleasePlannerAgent
                    .commitReleasePlanTool['parameters'] as Map)['properties']
                as Map)['beats'] as Map)['items'] as Map;
        final relPlanFeatItems = (((relPlanBeatItems['properties']
                as Map)['features'] as Map)['items']
            as Map);
        final relPlanLifecycleEnum =
            ((relPlanFeatItems['properties'] as Map)['lifecycle']
                as Map)['enum'] as List<dynamic>;
        expect(
          relPlanLifecycleEnum,
          equals(['new', 'upgrade', 'stable', 'superseded']),
        );

        // 6c. commitTailoredTaskSubStepsTool supports primarySharedScriptOrScene
        final tailorToolProps =
            (WorkbenchReleaseMixin.commitTailoredTaskSubStepsTool['parameters']
                as Map)['properties'] as Map;
        expect(
          tailorToolProps.containsKey('primarySharedScriptOrScene'),
          isTrue,
        );

        // 7. Pass 4 AI & Workflow Refinements
        // 7a. commitCodeToSpecSyncTool supports primarySharedScriptOrScene
        final codeSyncToolProps =
            (WorkbenchReleaseMixin.commitCodeToSpecSyncTool['parameters']
                as Map)['properties'] as Map;
        expect(
          codeSyncToolProps.containsKey('primarySharedScriptOrScene'),
          isTrue,
        );

        // 7b. buildActiveReleaseCodingAgentMarkdown and buildActiveFeatureCodingAgentPrompt output Primary Shared Asset
        liveDocForBpSync.sections['primary_asset'] =
            'GrappleHookController (res://scripts/grapple_hook_controller.gd)';
        final releaseAgentsMd =
            provider.buildActiveReleaseCodingAgentMarkdown();
        expect(
          releaseAgentsMd,
          contains(
            'GrappleHookController (res://scripts/grapple_hook_controller.gd)',
          ),
        );
        final singleFeaturePrompt =
            provider.buildActiveFeatureCodingAgentPrompt(liveDocForBpSync.id);
        expect(
          singleFeaturePrompt,
          contains(
            '**Primary Shared Asset**: `GrappleHookController (res://scripts/grapple_hook_controller.gd)`',
          ),
        );
        expect(singleFeaturePrompt, contains('**Design Pillars**:'));

        // 7c. TaskHowToBlueprint.resolve honors checkpointNode.parameters['primarySharedScriptOrScene']
        TaskHowToBlueprint.clearCache();
        final sharedAssetCp = FeatureStateNode(
          id: 'cp_shared_asset_test',
          name: 'Checkpoint 1: Grapple Swing',
          trigger: 'Playtest: Press E -> attach grapple hook',
          checklist: [
            Subtask(
              id: 't_shared_1',
              text: 'Implement swing tension physics (2h)',
            ),
          ],
          parameters: {
            'releaseVersion': 'v0.1',
            'primarySharedScriptOrScene':
                'CustomHookRig (res://scenes/custom_hook_rig.tscn)',
          },
        );
        final resolvedSharedBp = TaskHowToBlueprint.resolve(
          parentTask: sharedAssetCp.checklist.first,
          taskIndex: 0,
          checkpointNode: sharedAssetCp,
          engineHint: 'Godot 4 (2D)',
        );
        expect(
          resolvedSharedBp.subSteps.first.stepPath,
          contains('custom_hook_rig.gd'),
        );

        // 8. Pass 5 AI & Workflow Refinements
        // 8a. Feature Inbox switching integrationMode to upgradeExistingFeature auto-resolves targetFeatureId & syncs primarySharedScriptOrScene
        final inboxUpgradeIdea = await provider.submitFeatureIdeaToInbox(
          'Add grapple cable sparks and tension recoil',
        );
        expect(inboxUpgradeIdea, isNotNull);
        // Simulate switching from newFeatureInEpic (with null targetFeatureId) to upgradeExistingFeature
        provider.updateFeatureInboxItemTriage(
          inboxUpgradeIdea!.id,
          integrationMode: InboxIntegrationMode.upgradeExistingFeature,
        );
        final updatedInboxItem = provider.featureInboxItems
            .firstWhere((i) => i.id == inboxUpgradeIdea.id);
        expect(updatedInboxItem.targetFeatureId, isNotNull);
        expect(updatedInboxItem.targetFeatureTitle, isNotEmpty);

        // 8b. Editing sub-step instruction via encodeThreeAreaNotes preserves [[AREA1]] and [[AREA2]]
        final encodedThreeAreaPass5 = TaskHowToBlueprint.encodeThreeAreaNotes(
          instruction: 'Updated step instruction prose.',
          area1Hierarchy: 'PlayerRoot (CharacterBody2D)\n└─ GrappleRig (Node2D)',
          area2Inspector: 'maxTension: 900.0 | reelSpeed: 420.0',
        );
        final decodedThreeAreaPass5 =
            TaskHowToBlueprint.decodeThreeAreaNotes(encodedThreeAreaPass5);
        expect(
          decodedThreeAreaPass5.cleanInstruction,
          equals('Updated step instruction prose.'),
        );
        expect(
          decodedThreeAreaPass5.area1Hierarchy,
          contains('GrappleRig (Node2D)'),
        );
        expect(
          decodedThreeAreaPass5.area2Inspector,
          contains('maxTension: 900.0'),
        );

        // 9. Pass 6 Cross-Stage & Cross-Action State-Transition Refinements
        // 9a. propagateVariableRenameAcrossProject updates f.checkpoints inside _releaseBlueprint
        if (provider.releaseBlueprint != null &&
            provider.releaseBlueprint!.beats.isNotEmpty) {
          final sampleFeatBp =
              provider.releaseBlueprint!.beats.first.features.first;
          sampleFeatBp.tuningParams = ['grappleTensionMax: 850.0'];
          sampleFeatBp.checkpoints = [
            ProposedCheckpointBlueprint(
              title: 'Grapple Core',
              playtestCriteria: 'Verify grappleTensionMax in arena',
              tasks: ['Clamp grappleTensionMax in physics tick (1h)'],
              coveredScope: ['Grapple Core'],
              tuningParams: ['grappleTensionMax: 850.0'],
              edgeCases: ['[STATE GUARD] Clamp grappleTensionMax <= 1200.0'],
              releaseVersion: 'v0.1',
            ),
          ];
          provider.propagateVariableRenameAcrossProject(
            'grappleTensionMax',
            'cableTensionLimit',
          );
          expect(
            sampleFeatBp.checkpoints.first.tuningParams.first,
            contains('cableTensionLimit'),
          );
          expect(
            sampleFeatBp.checkpoints.first.edgeCases.first,
            contains('cableTensionLimit'),
          );
          expect(
            sampleFeatBp.checkpoints.first.tasks.first,
            contains('cableTensionLimit'),
          );
          expect(
            sampleFeatBp.checkpoints.first.playtestCriteria,
            contains('cableTensionLimit'),
          );
        }

        // 9b. Switching 03 Tech Spec Engine in Stage 1 (Unity 6 -> Godot 4 -> Unity 6) invalidates stale custom_snippet code and regenerates engine steps
        final switchFeatId = liveDocForBpSync.id;
        provider.updateConceptDraft((d) {
          d.techSpec = ['Godot 4 (GDScript)', 'PC (Steam)', '2D Sprite & Tilemap'];
        });
        provider.documents[switchFeatId]!.sections['primary_asset'] =
            'res://scenes/grapple_rig.tscn';
        final preSwitchStates = FeatureStateNode.getStatesForDocument(
          provider.documents[switchFeatId]!,
        );
        preSwitchStates.first.parameters['primarySharedScriptOrScene'] =
            'res://scenes/grapple_rig.tscn';
        preSwitchStates.first.checklist.first.completed = true;
        preSwitchStates.first.checklist.first.children = [
          Subtask(
            id: 'stale_godot_sub_1',
            text: 'STEP 1.1 · CREATE GODOT SCENE',
            specNotes: 'Attach grapple_rig.gd in Godot.',
            codeSnippet: '@export var cable_speed: float = 400.0',
            codeLanguage: 'res://scenes/grapple_rig.tscn',
            codeTargetFile: 'custom_snippet',
            completed: true,
          ),
        ];
        provider.updateFeatureStates(switchFeatId, preSwitchStates);

        provider.updateConceptDraft((d) {
          d.techSpec = ['Unity 6 (C#)', 'PC (Steam)', '2D Sprite & Tilemap'];
        });

        final postSwitchDoc = provider.documents[switchFeatId]!;
        expect(postSwitchDoc.sections.containsKey('primary_asset'), isFalse);
        final postSwitchStates =
            FeatureStateNode.getStatesForDocument(postSwitchDoc);
        expect(
          postSwitchStates.first.parameters
              .containsKey('primarySharedScriptOrScene'),
          isFalse,
        );
        expect(postSwitchStates.first.checklist.first.completed, isTrue);
        final resolvedUnityBp = TaskHowToBlueprint.resolve(
          parentTask: postSwitchStates.first.checklist.first,
          taskIndex: 0,
          checkpointNode: postSwitchStates.first,
          engineHint: 'Unity 6 (C#)',
        );
        expect(resolvedUnityBp.engineLabel, equals('UNITY C#'));
        expect(
          resolvedUnityBp.subSteps.first.codeFormula,
          isNot(contains('@export var')),
        );

        // 9c. Promoting an Exclusion inside Progressive Release Co-Pilot and then canceling restores _conceptDraft.exclusions
        provider.updateConceptDraft((d) {
          d.exclusions = ['No Online Multiplayer', 'No VR Support'];
        });
        final prevRelId = provider.activeReleaseId;
        final prevPhase = provider.currentPhase;
        await provider.prepareProgressiveNextReleaseDraft();
        provider.promoteExclusionToNextRelease('No Online Multiplayer');
        expect(
          provider.conceptDraft!.exclusions.contains('No Online Multiplayer'),
          isFalse,
        );
        provider.restoreActiveReleaseAfterCancel(prevRelId, prevPhase);
        expect(
          provider.conceptDraft!.exclusions.contains('No Online Multiplayer'),
          isTrue,
        );

        // 10. Pass 7 AI & Workflow Audit Refinements
        // 10a. SectionTextUtils.resolveDoneWhen and resolveInScope fallback to 'pass'/'doneWhen' and 'inScope' when 'scope' only has 'Goal:'
        final splitKeySections = <String, String>{
          'scope': 'Goal: Build a responsive arcade grapple swing.',
          'inScope': '• Hook projectile launch\n• Pendulum swing tension',
          'pass': 'Playtester swings across 3 chasm gaps without clipping.',
        };
        expect(
          SectionTextUtils.resolveDoneWhen(splitKeySections),
          equals('Playtester swings across 3 chasm gaps without clipping.'),
        );
        expect(
          SectionTextUtils.resolveInScope(splitKeySections),
          equals(['Hook projectile launch', 'Pendulum swing tension']),
        );

        // 10b. setDraftReleasePhase updates relDoc.title and restoreInitialProgressiveDraftBlueprint restores exclusions & inbox state
        final pass7PrevRelId = provider.activeReleaseId;
        final pass7PrevPhase = provider.currentPhase;
        await provider.prepareProgressiveNextReleaseDraft();
        await provider.setDraftReleasePhase(ProductionPhase.fullProduction);
        // Act 2: Full Production releases continue v0.N numbering (v1.0 is reserved for the Launch Release)
        expect(provider.activeRelease!.title, startsWith('v0.2:'));
        expect(provider.activeReleaseVersionTag, equals('v0.2'));
        await provider.setDraftReleasePhase(ProductionPhase.mvp);
        expect(provider.activeRelease!.title, startsWith('v0.2:'));
        expect(provider.activeReleaseVersionTag, equals('v0.2'));

        provider.promoteExclusionToNextRelease('No Online Multiplayer');
        expect(
          provider.conceptDraft!.exclusions.contains('No Online Multiplayer'),
          isFalse,
        );
        provider.restoreInitialProgressiveDraftBlueprint();
        expect(
          provider.conceptDraft!.exclusions.contains('No Online Multiplayer'),
          isTrue,
        );
        provider.restoreActiveReleaseAfterCancel(
          pass7PrevRelId,
          pass7PrevPhase,
        );

        // 10c. Switching projects restores each project's own saved selected_feature_id
        final pass7Proj1Id = provider.activeProjectId;
        final pass7Proj1Beats = provider.activeReleaseBeats;
        if (pass7Proj1Id != null && pass7Proj1Beats.length >= 2) {
          final secondBeatFeats =
              provider.featuresForBeat(pass7Proj1Beats[1].id);
          if (secondBeatFeats.isNotEmpty) {
            final targetProj1FeatId = secondBeatFeats.first.id;
            provider.selectFeature(
              targetProj1FeatId,
              triggerAiSynthesis: false,
            );
            expect(provider.selectedFeatureId, equals(targetProj1FeatId));

            provider.createNewProject();
            final pass7Proj2Id = provider.activeProjectId;
            expect(pass7Proj2Id, isNot(equals(pass7Proj1Id)));

            provider.switchProject(pass7Proj1Id);
            expect(provider.selectedFeatureId, equals(targetProj1FeatId));
          }
        }

        // 11. Stage 2 Workbench & AI Release Architecture Audit Regressions
        // 11a. GeminiAgentClient.buildNativeThinkingConfig uses capped fast thinking budget (256)
        expect(
          GeminiAgentClient.buildNativeThinkingConfig(
            normalizedThinking: 'LOW',
            useThinkingLevelEnum: false,
          )['thinkingBudget'],
          equals(256),
        );
        expect(
          GeminiAgentClient.buildNativeThinkingConfig(
            normalizedThinking: 'MEDIUM',
            useThinkingLevelEnum: false,
          )['thinkingBudget'],
          equals(256),
        );
        expect(
          GeminiAgentClient.buildNativeThinkingConfig(
            normalizedThinking: 'HIGH',
            useThinkingLevelEnum: false,
          )['thinkingBudget'],
          equals(256),
        );
        expect(
          ProjectConceptAgent.conceptSectionBuildOrder.length,
          equals(8),
        );

        // 11b. ProjectConceptAgent.buildSectionOptionsTool('coreLoop') has zero hardcoded beat counts
        final coreLoopToolDesc =
            (ProjectConceptAgent.buildSectionOptionsTool('coreLoop')[
                    'description'] ??
                '') as String;
        expect(coreLoopToolDesc.contains('4-6'), isFalse);

        // 11c. Dynamic Beat-to-Feature decomposition splits clauses dynamically and never clones Beat title
        final multiClauseFeats =
            ReleasePlannerAgent.decomposeBeatIntoDynamicFeatures(
          beatNumber: 1,
          beatIndex: 0,
          beatTitle: 'Debris Clearing',
          rawBeatLine:
              'Debris Clearing: Clear hull scrap with the laser cutter, vacuum salvage into storage, and vent excess heat',
          rawDescPart:
              'Clear hull scrap with the laser cutter, vacuum salvage into storage, and vent excess heat',
          versionTag: 'v0.1',
        );
        expect(multiClauseFeats.length, equals(3));
        for (final mf in multiClauseFeats) {
          expect(
            mf.title.toLowerCase(),
            isNot(equals('debris clearing')),
          );
        }
        final singleClauseFeats =
            ReleasePlannerAgent.decomposeBeatIntoDynamicFeatures(
          beatNumber: 2,
          beatIndex: 1,
          beatTitle: 'Debris Clearing',
          rawBeatLine: 'Debris Clearing',
          rawDescPart: '',
          versionTag: 'v0.1',
        );
        expect(singleClauseFeats.length, equals(1));
        expect(
          singleClauseFeats.first.title.toLowerCase(),
          isNot(equals('debris clearing')),
        );
        expect(
          ReleasePlannerAgent.commitReleaseSystemEpicsTool['name'],
          equals('commit_release_system_epics'),
        );
        expect(
          ReleasePlannerAgent.commitEpicFeaturesTool['name'],
          equals('commit_epic_features'),
        );

        // 11d. Section-by-Section Workbench materializes E01..EN and populates each Epic's features without overwriting E01
        final testRelDoc = TierDocument(
          id: 'rel_sec_test',
          title: 'v0.1: Train Turret Defense',
          tier: TierType.release,
        );
        final testSysBp = ReleaseBlueprint(
          releaseDocId: testRelDoc.id,
          releaseTitle: testRelDoc.title,
          releaseVersionTag: 'v0.1',
          preset: ReleaseScope.featurePrototype,
          goal: 'Build train defense loop.',
          doneWhen: 'Player clears 1 sector.',
          questions: const [],
          explicitExclusions: const ['No multiplayer'],
          beats: [
            ProposedBeatBlueprint(
              id: 'beat_1',
              title: 'Locomotive & Track Navigation',
              goal: 'Steer train along desert tracks.',
              doneWhen: 'Train moves along track splines.',
              features: [
                ProposedFeatureBlueprint(
                  id: 'feat_1_1',
                  title: 'Track Spline & Train Body',
                  goal: 'Build track spline and train collision.',
                  doneWhen: 'Train follows track.',
                  estimatedHours: 4,
                  inScope: const ['Track spline', 'Locomotive body'],
                  tuningParams: const ['trainSpeed: 12.0 m/s'],
                  edgeCases: const ['[BOUNDS] Clamp speed at junctions'],
                  checkpoints: const [],
                ),
              ],
            ),
            ProposedBeatBlueprint(
              id: 'beat_2',
              title: 'Roof Turret Aiming & Fire',
              goal: 'Aim and fire roof turrets.',
              doneWhen: 'Turret fires projectiles.',
              features: [
                ProposedFeatureBlueprint(
                  id: 'feat_2_1',
                  title: 'Turret Swivel & Projectile',
                  goal: 'Rotate turret toward cursor and spawn shells.',
                  doneWhen: 'Shells hit target.',
                  estimatedHours: 4,
                  inScope: const ['Turret rotation', 'Shell spawner'],
                  tuningParams: const ['fireRate: 3.5 shots/s'],
                  edgeCases: const ['[COOLDOWN] Prevent fire during reload'],
                  checkpoints: const [],
                ),
              ],
            ),
          ],
        );
        final createdSysEpics =
            ReleaseExecutorAgent.createInitialSystemEpicDocs(
          releaseDoc: testRelDoc,
          blueprint: testSysBp,
        );
        expect(createdSysEpics.length, equals(2));
        expect(
          testRelDoc.childrenIds,
          equals(['epic_rel_sec_test_1', 'epic_rel_sec_test_2']),
        );
        final e01CreatedFeats =
            ReleaseExecutorAgent.materializeFeaturesForSingleEpic(
          releaseDoc: testRelDoc,
          beatDoc: createdSysEpics[0],
          blueprint: testSysBp,
          beatBp: testSysBp.beats[0],
          epicIndex: 0,
        );
        final e02CreatedFeats =
            ReleaseExecutorAgent.materializeFeaturesForSingleEpic(
          releaseDoc: testRelDoc,
          beatDoc: createdSysEpics[1],
          blueprint: testSysBp,
          beatBp: testSysBp.beats[1],
          epicIndex: 1,
        );
        expect(
          testRelDoc.childrenIds,
          equals(['epic_rel_sec_test_1', 'epic_rel_sec_test_2']),
        );
        expect(
          createdSysEpics[0].childrenIds,
          equals([e01CreatedFeats.first.id]),
        );
        expect(
          createdSysEpics[1].childrenIds,
          equals([e02CreatedFeats.first.id]),
        );
        expect(
          e01CreatedFeats.first.id,
          isNot(equals(e02CreatedFeats.first.id)),
        );

        // 11e. Section-by-Section Progressive Release builds 0ms skeleton, Section 1 Focus, and Epic-by-Epic Section 2 changes
        final secExistingBeats = List<TierDocument>.from(
          provider.activeReleaseBeats,
        );
        final secExistingFeaturesByBeat = <String, List<TierDocument>>{
          for (final b in secExistingBeats)
            b.id: provider.featuresForBeat(b.id),
        };
        final secFirstBeat = secExistingBeats.first;
        final secFirstFeat = secExistingFeaturesByBeat[secFirstBeat.id]!.first;

        final prevMock = GeminiAgentClient.testMockResponder;
        final observedSection1States = <bool>[];
        final observedEpicIds = <String?>[];
        void progListener() {
          observedSection1States.add(provider.isSynthesizingProgressiveFocus);
          observedEpicIds.add(provider.synthesizingProgressiveBeatId);
        }

        provider.addListener(progListener);
        try {
          GeminiAgentClient.testMockResponder = (
            String prompt,
            String preferredModel,
          ) async {
            if (prompt.contains('commit_progressive_release_focus')) {
              return {
                'inferredPhase': 'mvp',
                'releaseTitle': 'v0.2: Arena Wave Loop & Dash Upgrade',
                'goal':
                    'Build multi-wave arena escalation and upgrade hovertank dash recharge.',
                'doneWhen':
                    'Playtester clears 3 escalating waves and verifies dash cooldown indicator.',
                'whatWeBuiltSoFar': [
                  'v0.1 (${secExistingBeats.length} Epics): Hovertank movement and primary cannon.',
                ],
                'missingGaps': [
                  'Missing dash cooldown HUD bar and wave escalation spawner.',
                ],
                'explicitExclusions': ['No online multiplayer'],
                'questions': [
                  {
                    'id': 'rel_q_focus',
                    'question': 'Which direction should anchor v0.2?',
                    'options': [
                      '(Recommended) Wave Escalation & Dash: Upgrade ${secFirstFeat.title} and add Wave Spawner',
                      'Hazard Rooms: Add arena laser traps and shield recharge',
                      'Boss Encounter: Focus v0.2 on a single multi-phase boss tank',
                    ],
                  },
                ],
                'targetEpicNumbers': [1, 2],
              };
            }
            if (prompt.contains('commit_progressive_epic_changes')) {
              if (prompt.contains('Target Epic E01')) {
                return {
                  'epicNumber': 1,
                  'epicGoal': 'Upgrade hovertank dash with recharge bar.',
                  'epicDoneWhen': 'Dash recharge bar fills in 1.2s.',
                  'features': [
                    {
                      'id': secFirstFeat.id,
                      'title': secFirstFeat.title,
                      'lifecycle': 'upgrade',
                      'goal':
                          'Add dash recharge bar and invulnerability window.',
                      'doneWhen':
                          'Playtester dashes through projectiles and sees cooldown bar.',
                      'estimatedHours': 3,
                      'primarySharedScriptOrScene': 'PlayerTank.gd',
                      'inScope': ['Dash recharge bar', 'I-frame window'],
                      'outOfScope': ['Skill tree perks'],
                      'tuningParams': ['dashCooldown: 1.2 s'],
                      'edgeCases': [
                        '[INPUT GUARD] Ignore dash input while cooldown > 0',
                      ],
                      'checkpointTitle': 'Dash Cooldown & I-Frames',
                      'playtestCriteria':
                          'Press Space -> dash triggers i-frames -> bar refills in 1.2s',
                      'tasks': [
                        {
                          'role': 'entity_and_collision_foundation',
                          'title': 'Cooldown Timer & Bar Node',
                        },
                        {
                          'role': 'core_action_and_math',
                          'title': 'I-Frame Collision Toggle',
                        },
                        {
                          'role': 'feedback_and_boundary_guard',
                          'title': 'Ready Flash & Input Guard',
                        },
                      ],
                    },
                  ],
                };
              }
              return {
                'epicNumber': 2,
                'epicGoal': 'Spawn escalating enemy tank waves.',
                'epicDoneWhen': '3 enemy waves spawn and clear cleanly.',
                'features': [
                  {
                    'id': 'feat_wave_escalation_v02',
                    'title': 'Enemy Wave Spawner',
                    'lifecycle': 'new',
                    'goal': 'Spawn 3 escalating enemy waves in the arena.',
                    'doneWhen':
                        'Clearing wave 1 spawns wave 2 and wave 3 in sequence.',
                    'estimatedHours': 4,
                    'primarySharedScriptOrScene': 'WaveDirector.gd',
                    'inScope': ['3-wave table', 'Spawn perimeter points'],
                    'outOfScope': ['Endless leaderboard'],
                    'tuningParams': ['waveSpawnDelay: 2.5 s'],
                    'edgeCases': [
                      '[BOUNDS GUARD] Clamp spawn points inside arena navmesh',
                    ],
                    'checkpointTitle': '3-Wave Escalation Loop',
                    'playtestCriteria':
                        'Destroy wave 1 -> wave 2 spawns after 2.5s',
                    'tasks': [
                      {
                        'role': 'entity_and_collision_foundation',
                        'title': 'Spawn Point Array & Wave Table',
                      },
                      {
                        'role': 'core_action_and_math',
                        'title': 'Wave Counter & Enemy Instantiation',
                      },
                      {
                        'role': 'feedback_and_boundary_guard',
                        'title': 'Wave Banner & Bounds Guard',
                      },
                    ],
                  },
                ],
              };
            }
            return prevMock!(prompt, preferredModel);
          };

          final relV02 = TierDocument(
            id: 'rel_v02_sec_test',
            tier: TierType.release,
            title: 'v0.2: Progressive Release',
            parentId: provider.activeProject!.id,
            sections: {'versionTag': 'v0.2', 'phase': 'mvp'},
          );

          final planned = await provider.planProgressiveReleaseSectionBySection(
            projectDoc: provider.activeProject!,
            releaseDoc: relV02,
            completedReleases: provider.projectReleases,
            existingBeats: secExistingBeats,
            existingFeaturesByBeat: secExistingFeaturesByBeat,
            deferredByBeatIndex: const {},
          );

          expect(planned, isNotNull);
          expect(
            planned!.goal,
            contains('Complete E01'),
          );
          expect(planned.questions, isNotEmpty);
          expect(planned.questions.first.options.length, equals(3));

          // Verify Section 1 is seeded deterministically in 0ms without a Pass 1 network wait
          expect(observedSection1States, contains(false));
          expect(provider.isSynthesizingProgressiveFocus, isFalse);

          // Verify Epic-by-Epic synthesis visited E01 and E02
          expect(observedEpicIds, contains(secExistingBeats[0].id));
          expect(observedEpicIds, contains(secExistingBeats[1].id));

          // Verify E01 has the UPGRADE feature and E02 has the NEW feature, while other features remain STABLE
          final e01Upgrades = planned.beats[0].features
              .where((f) => f.lifecycle == FeatureLifecycleStatus.upgrade)
              .toList();
          expect(e01Upgrades.length, equals(1));
          expect(e01Upgrades.first.id, equals(secFirstFeat.id));

          final e02NewFeats = planned.beats[1].features
              .where((f) => f.lifecycle == FeatureLifecycleStatus.newFeature)
              .toList();
          expect(e02NewFeats.length, equals(1));
          expect(e02NewFeats.first.title, equals('Enemy Wave Spawner'));
          // Whole-Epic rule: existing feature(s) in E02 are also upgraded alongside the NEW feature
          final e02Upgrades = planned.beats[1].features
              .where((f) => f.lifecycle == FeatureLifecycleStatus.upgrade)
              .toList();
          expect(
            e02Upgrades.length,
            equals(secExistingFeaturesByBeat[secExistingBeats[1].id]!.length),
          );

          // 11f. Whole-Epic Completion Rule (Multi-Feature Epic), Strict Epic-Only Phase Coverage, and Unbuilt Draft Release Guard
          final secondFeatInE01 = TierDocument(
            id: 'feat_e01_extra_v01',
            tier: TierType.feature,
            title: 'Hovertank Boost Jets',
            parentId: secFirstBeat.id,
            sections: {
              'goal': 'Activate lateral boost jets on Shift key.',
              'doneWhen': 'Playtester presses Shift and boosts sideways.',
              'originVersion': 'v0.1',
              'lastUpdatedRelease': 'v0.1',
            },
          );
          final multiFeatMap = <String, List<TierDocument>>{
            for (final entry in secExistingFeaturesByBeat.entries)
              entry.key: List<TierDocument>.from(entry.value),
          };
          multiFeatMap[secFirstBeat.id] = [secFirstFeat, secondFeatInE01];

          final multiFeatPlanned =
              await provider.planProgressiveReleaseSectionBySection(
                projectDoc: provider.activeProject!,
                releaseDoc: relV02,
                completedReleases: provider.projectReleases,
                existingBeats: secExistingBeats,
                existingFeaturesByBeat: multiFeatMap,
                deferredByBeatIndex: const {},
              );
          expect(multiFeatPlanned, isNotNull);
          final multiE01Upgrades = multiFeatPlanned!.beats[0].features
              .where((f) => f.lifecycle == FeatureLifecycleStatus.upgrade)
              .toList();
          // Even though the mock only returned secFirstFeat, Whole-Epic rule upgrades ALL 2 features in E01!
          expect(multiE01Upgrades.length, equals(2));
          expect(
            multiE01Upgrades.map((f) => f.id).toSet(),
            equals({secFirstFeat.id, secondFeatInE01.id}),
          );

          // Verify Vertical Slice phase switching works in planProgressiveReleaseSectionBySection
          final relV03Vs = TierDocument(
            id: 'rel_v03_vs_test',
            tier: TierType.release,
            title: 'v0.3: Vertical Slice Polish',
            parentId: provider.activeProject!.id,
            sections: {'versionTag': 'v0.3', 'phase': 'verticalSlice'},
          );
          final vsPlanned =
              await provider.planProgressiveReleaseSectionBySection(
                projectDoc: provider.activeProject!,
                releaseDoc: relV03Vs,
                completedReleases: provider.projectReleases,
                existingBeats: secExistingBeats,
                existingFeaturesByBeat: multiFeatMap,
                deferredByBeatIndex: const {},
              );
          expect(vsPlanned, isNotNull);
          expect(vsPlanned!.preset, equals(ReleaseScope.verticalSlice));
          expect(
            vsPlanned.beats[0].features
                .where((f) => f.lifecycle == FeatureLifecycleStatus.upgrade)
                .length,
            equals(2),
          );

          // Verify unbuilt draft release (empty childrenIds) returns isActiveReleaseComplete == false
          final savedChildren = List<String>.from(
            provider.activeRelease!.childrenIds,
          );
          provider.activeRelease!.childrenIds.clear();
          expect(provider.isActiveReleaseComplete, isFalse);
          provider.activeRelease!.childrenIds.addAll(savedChildren);
        } finally {
          provider.removeListener(progListener);
          GeminiAgentClient.testMockResponder = prevMock;
        }
      },
    );

    test(
      'Workbench & Progressive Release text style formatters (Telegraphic, Micro-Communications, Concise BLUF & Causal) and Regex-First Code Sync',
      () async {
        // 1. Telegraphic Task Group Header (strips leading verbs + articles even on short titles)
        expect(
          TaskHowToBlueprint.formatConciseTaskTitle(
            'Create the Capsule Body and Camera (2h)',
          ),
          equals('Capsule Body & Camera'),
        );
        expect(
          TaskHowToBlueprint.formatConciseTaskTitle('Create the HUD (1h)'),
          equals('HUD'),
        );

        // 2. Telegraphic Step Title (strips articles a/an/the and trailing prepositional filler while preserving engine identifiers)
        expect(
          TaskHowToBlueprint.formatTelegraphicStepTitle(
            'STEP 1.1 · Attach a RayCast2D to the Player in the scene (15m)',
          ),
          equals('Attach RayCast2D to Player'),
        );
        expect(
          TaskHowToBlueprint.formatTelegraphicStepTitle(
            'STEP 1.2 · CREATE THE BP_PLAYER_CHARACTER ACTOR IN THE LEVEL',
          ),
          equals('Create BP_Player_Character Actor'),
        );

        // 3. Telegraphic Guard Chip (converts "Prevent <X> from <Y>ing" -> "Block <X> <Y>ing" and strips articles)
        expect(
          TaskHowToBlueprint.formatTelegraphicGuardChip(
            '[STATE GUARD] Prevent the player from dashing while stunned.',
          ),
          equals('Block player dashing while stunned'),
        );

        // 4. Concise BLUF Feature Goal Subtitle (strips "Build a playable ... that allows the player to ")
        expect(
          TaskHowToBlueprint.formatConciseFeatureGoal(
            'Build a playable prototype that allows the player to dash across gaps with cooldown.',
          ),
          equals('Dash across gaps with cooldown.'),
        );

        // 5. Concise Imperative Step Instruction (strips preamble clauses)
        expect(
          TaskHowToBlueprint.formatConciseStepInstruction(
            'In order to configure movement, open Player.gd and export dashSpeed.',
          ),
          equals('Open Player.gd and export dashSpeed.'),
        );

        // 6. Concise Causal VERIFY Sentence ("When you <action>, <result>" -> "<Action> → <Result>")
        expect(
          TaskHowToBlueprint.formatConciseVerifySentence(
            'Confirm that when you press Spacebar, the character dashes 4m forward.',
          ),
          equals('Press Spacebar → The character dashes 4m forward.'),
        );

        // 6b. Stage 1 Concept Blueprint Section 02 & 03 Telegraphic Spec Value Compression
        expect(
          LayersTextStyleGuide.formatTelegraphicSpecValue(
            'First-person immersive camera with direct tool manipulation and precision interaction',
          ),
          equals('3D First-Person'),
        );
        expect(
          LayersTextStyleGuide.formatTelegraphicSpecValue(
            'Keyboard and Mouse / Gamepad with contextual tool bindings',
          ),
          equals('KBM / Gamepad'),
        );
        expect(
          LayersTextStyleGuide.formatTelegraphicSpecValue(
            'Single-player narrative survival simulation with environmental hazards',
          ),
          equals('Singleplayer Survival'),
        );
        expect(
          LayersTextStyleGuide.formatTelegraphicSpecValue(
            'Interconnected rooftop garden hub with ziplines and vertical scaffolds',
          ),
          equals('Interconnected Rooftop Garden Hub'),
        );
        expect(
          LayersTextStyleGuide.formatTelegraphicSpecValue('Twin-Stick (WASD + Mouse Aim)'),
          equals('WASD + Mouse'),
        );
        expect(
          LayersTextStyleGuide.formatTelegraphicSpecValue('Perspective: 3D Third-Person Over-Shoulder'),
          equals('3D Third-Person'),
        );

        // 7. Telegraphic Progressive Release Feature +Delta Summary
        final provider = WorkbenchProvider(enableAutoLoad: false);
        final sampleUpgradeFeat = ProposedFeatureBlueprint(
          id: 'feat_upg_delta_test',
          title: 'Player Dash',
          goal: 'Upgrade Player Dash with invulnerability frames and ghost trail.',
          doneWhen: 'Press Shift -> dash with trail',
          estimatedHours: 4,
          included: true,
          lifecycle: FeatureLifecycleStatus.upgrade,
          originVersion: 'v0.1',
          inScope: const [
            'Add a dash cooldown bar on screen',
            'Implement the ghost trail particles in the arena',
          ],
          outOfScope: const [],
          tuningParams: const ['dashSpeed: 900'],
          edgeCases: const ['[STATE GUARD] Block dash while stunned'],
          checkpoints: const [],
        );
        final deltaSummary = provider.formatChangelogDeltaForFeature(
          sampleUpgradeFeat,
        );
        expect(
          deltaSummary,
          equals('+Dash cooldown bar, +Ghost trail particles'),
        );

        // 8. Regex-First Two-Way Code Sync (0 LLM calls when regex extracts tuning/guards)
        await provider.startConceptInterview('Crop Shotgun Arena');
        await provider.approveConceptAndBuildRelease();
        final firstFeat = provider.selectedFeature!;
        int llmCalls = 0;
        final prevResponder = GeminiAgentClient.testMockResponder;
        try {
          GeminiAgentClient.testMockResponder = (
            String prompt,
            String preferredModel,
          ) async {
            if (prompt.contains('Code-to-Spec Synchronizer')) {
              llmCalls++;
            }
            return <String, dynamic>{};
          };

          final syncRes = await provider.syncFeatureTuningAndGuardsFromCode(
            firstFeat.id,
            '@export var moveSpeed: float = 750.0\n# [GUARD] Block dash while airborne',
          );
          expect(syncRes.updatedVars, greaterThanOrEqualTo(1));
          expect(syncRes.addedGuards, equals(1));
          expect(llmCalls, equals(0));

          // 9. Central LayersTextStyleGuide single source of truth & long task group title condensation
          expect(
            GeminiAgentClient.compactStyleRules,
            equals(LayersTextStyleGuide.compactStyleRules),
          );
          expect(
            TaskHowToBlueprint.formatConciseTaskTitle(
              'Setup dash collision response layer & invulnerability state flags',
            ),
            equals('Collision Layer & State Flags'),
          );
          expect(
            TaskHowToBlueprint.formatConciseTaskTitle(
              'Code dash trajectory impulse, invulnerability window timer, & cooldown',
            ),
            equals('Trajectory Impulse & Window Timer'),
          );
          expect(
            TaskHowToBlueprint.formatConciseTaskTitle(
              'Ghost trail particle trail & trigger dash burst sound cue while dashing',
            ),
            equals('Ghost Trail & Sound Cue'),
          );
          expect(
            TaskHowToBlueprint.formatConciseFeatureGoal(
              'Upgrade dash burst into full combat evasion with i-frame invulnerability window, animation cues, and cooldown tuning.',
            ),
            equals(
              'I-frame invulnerability window, animation cues, and cooldown tuning.',
            ),
          );
          final extractedWithGoals =
              ReleasePlannerAgent.extractCheckpointTasksFromMap({
            'tasks': [
              {
                'role': 'entity_and_collision_foundation',
                'title': 'Shard Physics Hull',
                'goal':
                    'Configure the low-poly scrap shard collision hull, gravity scale, and floor bounce material.',
              },
              {
                'role': 'core_action_and_math',
                'title': 'Radial Scatter Impulse',
                'goal':
                    'Calculate radial scatter vectors with randomized pitch and roll impulse on monster death.',
              },
            ],
          });
          expect(
            extractedWithGoals.first,
            equals(
              'Shard Physics Hull — Configure the low-poly scrap shard collision hull, gravity scale, and floor bounce material.',
            ),
          );
          final sampleBp = TaskHowToBlueprint(
            numLabel: '01',
            layerTag: 'PHYSICS',
            cleanTitle: extractedWithGoals.first,
            durationChip: '1h',
            whereLocation: 'Script: ScrapShard.gd',
            engineLabel: 'GODOT 4',
            subSteps: [
              TaskHowToSubStep(
                subtask: Subtask(id: 's1', text: 'Setup Shard Physics Hull'),
                stepNumberLabel: 'STEP 1.1',
                shortTitle: 'Setup Shard Physics Hull',
                instruction: 'Attach RigidBody3D and CollisionShape3D.',
                verifyResult:
                    'Drop ScrapShard from 3m → bounces twice before resting',
                codeFormula: 'gravity_scale = 1.8',
              ),
            ],
          );
          expect(sampleBp.shortTaskTitle, equals('Shard Physics Hull'));
          expect(
            sampleBp.taskGoalSentence,
            equals(
              'Configure the low-poly scrap shard collision hull, gravity scale, and floor bounce material.',
            ),
          );
          expect(
            sampleBp.taskDoneCheck,
            equals('Drop ScrapShard from 3m → bounces twice before resting'),
          );

          // 10. Built feature never flips to "Waiting" when selected while another feature is synthesizing
          String? capturedCp2Prompt;
          GeminiAgentClient.testMockResponder = (
            String prompt,
            String preferredModel,
          ) async {
            capturedCp2Prompt = prompt;
            return {
              'primarySharedScriptOrScene':
                  'PlayerDashController (res://scripts/player_dash.gd)',
              'tasks': [
                for (int tIdx = 0; tIdx < 3; tIdx++)
                  {
                    'taskIndex': tIdx,
                    'subSteps': [
                      {
                        'title': 'Attach Dash Raycast',
                        'stepPath': 'Scene Dock → Player',
                        'instruction':
                            'Attach RayCast2D to Player and set target_position.',
                        'area1Hierarchy': 'Player\n └─ DashRay (RayCast2D)',
                        'area2Inspector': 'target_position = Vector2(120, 0)',
                        'codeFormula':
                            'func _physics_process(delta: float) -> void:\n\tvar dash_speed: float = 900.0',
                        'verifyResult':
                            'Press Shift → Player dashes 4m forward.',
                      },
                    ],
                  },
              ],
            };
          };
          await provider.synthesizeFeatureHowToStepsWithAi(firstFeat.id);
          expect(
            provider.hasSynthesizedFeatureStepsForActiveRelease(firstFeat.id),
            isTrue,
          );
          provider.selectFeature(firstFeat.id);
          expect(provider.isFeatureQueuedForSteps(firstFeat.id), isFalse);
          expect(
            provider.isFeatureWaitingForStepsInLiveMode(firstFeat.id),
            isFalse,
          );

          // 11. Prior-Checkpoint Structural Snapshot extracts Existing Scene Hierarchy (area1Hierarchy) and Script Symbols (funcs=[...]) on CP2+
          final statesForCp2 = FeatureStateNode.getStatesForDocument(firstFeat);
          for (final t in statesForCp2.first.checklist) {
            t.completed = true;
            for (final c in t.children) {
              c.completed = true;
            }
          }
          statesForCp2.add(
            FeatureStateNode(
              id: '${firstFeat.id}_cp_2',
              name: 'Checkpoint 2: Dash Ghost Trail',
              trigger: 'Playtest: Press Shift → leaves 3 ghost sprites',
              order: 1,
              checklist: [
                Subtask(
                  id: 'cp2_t1',
                  text:
                      'Ghost Sprite Spawner — Spawn 3 fading afterimage sprites along the dash trajectory.',
                ),
              ],
              coveredScope: const ['+3 fading afterimage sprites'],
              tuningParams: const ['ghostFadeDuration: 0.25 s'],
              edgeCases: const ['[STATE GUARD] Pool ghost sprites at 6'],
              parameters: {
                'releaseVersion': provider.activeReleaseVersionTag,
              },
            ),
          );
          provider.updateFeatureStates(firstFeat.id, statesForCp2);
          await provider.synthesizeFeatureHowToStepsWithAi(
            firstFeat.id,
            forceRefresh: true,
          );
          expect(capturedCp2Prompt, isNotNull);
          expect(
            capturedCp2Prompt,
            contains('Previous Checkpoints Structural Snapshot'),
          );
          expect(
            capturedCp2Prompt,
            contains(
              'Existing Scene Hierarchy (extend in-place — do NOT recreate): Player > DashRay (RayCast2D)',
            ),
          );
          expect(
            capturedCp2Prompt,
            contains('funcs=[_physics_process]'),
          );

          // 12. Full-Project Audit Upgrades: Direct Epic Creation, STABLE Sibling MVP Coverage, & v0.2+ Stage 1 Core Loop Append
          final initialBeatCount = provider.activeReleaseBeats.length;
          final newEpicId = provider.addLiveEpicToActiveRelease(
            'Save & Meta-Progression: Persist unlocked relics between runs',
          );
          expect(newEpicId, isNotNull);
          expect(
            provider.activeReleaseBeats.length,
            equals(initialBeatCount + 1),
          );
          final createdEpic = provider.documents[newEpicId!]!;
          expect(createdEpic.title, equals('Save & Meta-Progression'));
          expect(provider.featuresForBeat(newEpicId), isNotEmpty);

          // Verify that a 100% complete STABLE v0.1 sibling feature in an Epic that also has an MVP feature does not deadlock mvpBeatCoverage()
          final beatWithSiblings = provider.activeReleaseBeats.first;
          final siblingFeats = provider.featuresForBeat(beatWithSiblings.id);
          if (siblingFeats.length >= 2) {
            final stableFeat = siblingFeats[0];
            final upgradedFeat = siblingFeats[1];
            final st0 = FeatureStateNode.getStatesForDocument(stableFeat);
            for (final s in st0) {
              for (final t in s.checklist) {
                t.completed = true;
                for (final c in t.children) {
                  c.completed = true;
                }
              }
            }
            provider.updateFeatureStates(stableFeat.id, st0);

            final st1 = FeatureStateNode.getStatesForDocument(upgradedFeat);
            st1.add(
              FeatureStateNode(
                id: '${upgradedFeat.id}_v0.2_cp',
                name: 'Checkpoint 2: MVP Upgrade',
                trigger: 'Playtest MVP',
                order: st1.length,
                checklist: [
                  Subtask(id: 'mvp_t1', text: 'MVP Task (2h)', completed: true),
                ],
                parameters: const {'releaseVersion': 'v0.2'},
              ),
            );
            provider.updateFeatureStates(upgradedFeat.id, st1);

            final mvpCov = provider.mvpBeatCoverage();
            expect(mvpCov.completedBeatCodes, contains('E01'));
            expect(
              mvpCov.unupgradedProtoFeatureTitles
                  .any((t) => t.contains(stableFeat.title)),
              isFalse,
            );
          }

          // 13. Act 2 · Full Production Blueprint -> Full-Game Skeleton -> Production Pass -> v1.0 Launch Release -> v1.1 Post-Launch
          GeminiAgentClient.testMockResponder = (
            String prompt,
            String preferredModel,
          ) async {
            if (prompt.contains('ACT 2 FULL-GAME SKELETON') ||
                prompt.contains('commit_release_plan')) {
              return {
                'releaseTitle': 'v0.3: Full-Game Campaign Skeleton',
                'goal':
                    'Playable Campaign Outer Loop — Wire Hub forge, biome transitions, and save persistence end-to-end.',
                'doneWhen':
                    'Complete run and reload game → Unlocked relics and gold persist in Hub',
                'explicitExclusions': [
                  'No Online Co-Op Lobby',
                  'No Procedural Dialogue Trees',
                ],
                'beats': [
                  {
                    'id': 'epic_fp_hub',
                    'title': 'Hub Town & Forge',
                    'goal': 'Equip weapons and upgrade tiers between runs',
                    'doneWhen': 'Spend gold at forge → Weapon tier persists',
                    'features': [
                      {
                        'id': 'feat_fp_forge',
                        'title': 'Hub Weapon Forge',
                        'lifecycle': 'newFeature',
                        'included': true,
                        'estimatedHours': 2,
                        'goal': '+Weapon rack interactable, +gold upgrade button',
                        'inScope': ['+Forge UI panel', '+Gold deduction'],
                        'doneWhen': 'Click upgrade → Weapon damage increases',
                        'primarySharedScriptOrScene': 'res://scripts/hub_forge.gd',
                        'checkpoints': [
                          {
                            'title': 'Functional Baseline (Hub Weapon Forge)',
                            'playtestCriteria':
                                'Interact with forge → Buy Tier 2 upgrade',
                            'tasks': [
                              'Forge Trigger & Panel (2h)',
                            ],
                          },
                        ],
                      },
                    ],
                  },
                  {
                    'id': 'epic_fp_save',
                    'title': 'Save & Campaign Flow',
                    'goal': 'Persist campaign unlocks and roll credits on win',
                    'doneWhen': 'Reload game → Unlocked relics remain active',
                    'features': [
                      {
                        'id': 'feat_fp_save',
                        'title': 'Save Slot & Cloud Sync',
                        'lifecycle': 'newFeature',
                        'included': true,
                        'estimatedHours': 2,
                        'goal': '+JSON save writer, +auto-load on boot',
                        'inScope': ['+SaveManager singleton', '+Boot load'],
                        'doneWhen': 'Restart game → Gold and relics restored',
                        'primarySharedScriptOrScene':
                            'res://scripts/save_manager.gd',
                        'checkpoints': [
                          {
                            'title':
                                'Functional Baseline (Save Slot & Cloud Sync)',
                            'playtestCriteria':
                                'Quit and relaunch → Save persistence works',
                            'tasks': [
                              'JSON Save Serializer (2h)',
                            ],
                          },
                        ],
                      },
                    ],
                  },
                ],
              };
            }
            if (prompt.contains('commit_full_production_blueprint')) {
              return {
                'goal':
                    'Complete 3-Biome Campaign — Hub town, relic unlocks, and final boss victory',
                'contentScale': [
                  'Biomes / Levels: 3 distinct arenas + final boss chamber',
                  'Enemy Roster: 6 standard archetypes + 2 bosses',
                  'Weapons / Unlocks: 5 weapons + 8 permanent relics',
                  'Target Playtime: 20m per full campaign run',
                ],
                'fullGameLoop': [
                  'Spawn in Hub Town → Equip weapon & relic loadouts at forge',
                  'Clear 3 Biome Arenas → Defeat biome boss and bank gold',
                  'Return to Hub or Beat Final Boss → Unlock permanent relics & roll credits',
                ],
                'promotedSystems': [
                  'Save Slot & Cloud Sync — Persist unlocked relics and biome progress across runs',
                  'Hub Weapon Forge — Spend banked gold on permanent weapon tiers',
                ],
                'permanentCuts': [
                  'No Online Co-Op Lobby',
                  'No Procedural Dialogue Trees',
                ],
                'doneWhen':
                    'Beat Final Boss from fresh save → Credits roll & unlocked relics persist on reload',
                'goalOptions': [
                  'Complete 3-Biome Campaign — Hub town, relic unlocks, and final boss victory',
                ],
                'contentScaleOptions': [
                  '3 Biomes + 6 Enemies + 5 Weapons (20m run)',
                ],
                'fullGameLoopOptions': [
                  'Hub Forge → 3 Biome Runs → Final Boss Victory & Save',
                ],
                'promotedSystemsOptions': [
                  'Save Slot & Cloud Sync | Hub Weapon Forge',
                ],
                'permanentCutsOptions': [
                  'No Online Co-Op Lobby | No Procedural Dialogue Trees',
                ],
                'doneWhenOptions': [
                  'Beat Final Boss from fresh save → Credits roll & unlocked relics persist on reload',
                ],
              };
            }
            return {
              'featureTitle': 'Save Slot & Cloud Sync',
              'featureSummary':
                  'Persist unlocked relics and biome progress across runs',
              'placementMode': 'newEpicAndFeature',
              'proposedNewEpicTitle': 'Save & Campaign Flow',
              'releaseTimingMode': 'futureRelease',
              'targetFuturePhase': 'fullProduction',
              'reasoning': 'Meta-progression save system belongs in Act 2.',
            };
          };

          final fpInboxItem = await provider.submitFeatureIdeaToInbox(
            'Save Slot & Cloud Sync: Persist unlocked relics and biome progress across runs',
          );
          expect(fpInboxItem, isNotNull);
          provider.updateFeatureInboxItemTriage(
            fpInboxItem!.id,
            timingMode: InboxReleaseTimingMode.futureRelease,
            targetFuturePhase: ProductionPhase.fullProduction,
          );

          // Simulate entering Act 2 Full Production Blueprint gate
          await provider.prepareProgressiveNextReleaseDraft();
          await provider.setDraftReleasePhase(ProductionPhase.fullProduction);
          expect(provider.needsFullProductionBlueprint, isTrue);

          await provider.draftFullProductionBlueprint();
          final fpBp = provider.fullProductionBlueprint;
          expect(fpBp, isNotNull);
          expect(fpBp!.isReadyToApprove, isTrue);
          expect(fpBp.goal, contains('Complete 3-Biome Campaign'));
          expect(fpBp.fullGameLoop.length, equals(3));

          final preCoreEpicIds = provider.activeReleaseBeats
              .where((b) => !b.isFullProductionEpic)
              .map((b) => b.id)
              .toSet();

          final skeletonOk =
              await provider.approveFullProductionBlueprintAndBuildSkeleton();
          expect(skeletonOk, isTrue);
          expect(provider.needsFullProductionBlueprint, isFalse);

          // Promoted inbox item should now be marked implemented
          final updatedInboxItem = provider.featureInboxItems.firstWhere(
            (i) => i.id == fpInboxItem.id,
          );
          expect(
            updatedInboxItem.status,
            equals(FeatureInboxStatus.implemented),
          );

          // Verify new Act 2 Full Production Epics were created & tagged with act=fullProduction, while Core Epics stayed intact
          final fpEpics = provider.activeReleaseBeats
              .where((b) => b.isFullProductionEpic)
              .toList();
          expect(fpEpics.length, equals(2));
          expect(
            fpEpics.map((e) => e.title),
            containsAll(['Hub Town & Forge', 'Save & Campaign Flow']),
          );
          for (final coreId in preCoreEpicIds) {
            expect(provider.documents.containsKey(coreId), isTrue);
          }

          // Skeleton release alone does not count as Production Pass coverage yet
          final fpCovAfterSkeleton = provider.fullProductionCoverage();
          expect(fpCovAfterSkeleton.isLegacy, isFalse);
          expect(fpCovAfterSkeleton.totalBeats, equals(2));
          expect(fpCovAfterSkeleton.coveredBeats, equals(0));
          expect(fpCovAfterSkeleton.isReadyForLaunch, isFalse);

          // Simulate a built Production Pass release (v0.4) that upgrades the 2 Act 2 Epics
          final nextPassVer = provider.nextProgressiveVersionLabel;
          expect(nextPassVer, startsWith('v0.'));
          final passRelDoc = TierDocument(
            id: 'rel_fp_pass_test',
            title: '$nextPassVer: Act 2 Production Pass',
            tier: TierType.release,
            parentId: provider.activeProject!.id,
            childrenIds: [for (final e in fpEpics) e.id],
            sections: {
              'versionTag': nextPassVer,
              'phase': ProductionPhase.fullProduction.name,
              'releaseScope': ReleaseScope.fullProduction.name,
            },
          );
          provider.documents[passRelDoc.id] = passRelDoc;
          provider.activeProject!.childrenIds.add(passRelDoc.id);

          for (final fpEpic in fpEpics) {
            for (final feat in provider.featuresForBeat(fpEpic.id)) {
              final states = FeatureStateNode.getStatesForDocument(feat);
              for (final s in states) {
                for (final t in s.checklist) {
                  t.completed = true;
                  for (final c in t.children) {
                    c.completed = true;
                  }
                }
              }
              states.add(
                FeatureStateNode(
                  id: '${feat.id}_${nextPassVer}_cp',
                  name: 'Checkpoint 2: Production Pass (${feat.title})',
                  trigger: 'Verify production depth & polish',
                  order: states.length,
                  checklist: [
                    Subtask(
                      id: '${feat.id}_prod_t1',
                      text: 'Production Content & Feel Pass (2h)',
                      completed: true,
                    ),
                  ],
                  parameters: {'releaseVersion': nextPassVer},
                ),
              );
              provider.updateFeatureStates(feat.id, states);
            }
          }

          // Now all 2 Full Production Epics have a completed Production Pass beyond the skeleton release!
          final fpCovReady = provider.fullProductionCoverage();
          expect(fpCovReady.coveredBeats, equals(2));
          expect(fpCovReady.totalBeats, equals(2));
          expect(fpCovReady.isReadyForLaunch, isTrue);
          expect(provider.isNextReleaseV1Launch, isTrue);
          expect(provider.nextProgressiveVersionLabel, equals('v1.0'));

          // Advance into the v1.0 Launch Release and verify Fast Path 0 builds the deterministic Release Build Export feature
          await provider.prepareProgressiveNextReleaseDraft();
          expect(provider.releaseBlueprint, isNotNull);
          expect(provider.releaseBlueprint!.releaseVersionTag, equals('v1.0'));
          await provider.approveAndExecuteReleasePlan();
          expect(
            provider.activeRelease?.sections['launchRelease'],
            equals('true'),
          );
          final launchExportFeature = provider.documents.values.firstWhere(
            (d) =>
                d.tier == TierType.feature &&
                d.title == 'Release Build Export',
          );
          expect(launchExportFeature, isNotNull);

          // Complete the v1.0 Release Build Export tasks -> project graduates to 05 · Post-Launch (v1.1)
          final exportStates =
              FeatureStateNode.getStatesForDocument(launchExportFeature);
          for (final s in exportStates) {
            for (final t in s.checklist) {
              t.completed = true;
              for (final c in t.children) {
                c.completed = true;
              }
            }
          }
          provider.updateFeatureStates(launchExportFeature.id, exportStates);

          expect(
            provider.inferNextProgressivePhase(),
            equals(ProductionPhase.postLaunch),
          );
          expect(provider.nextProgressiveVersionLabel, equals('v1.1'));
        } finally {
          GeminiAgentClient.testMockResponder = prevResponder;
        }
      },
    );

    group('Stage 1A "What\'s Missing" nudge', () {
      Map<String, dynamic> intakeJson(Object? missing) => {
            'workingTitle': 'Crop Shotgun',
            'baseSummary':
                'Fire grown vegetables at mutant beetle swarms in a top-down arena.',
            'mechanics': ['Crop Firing'],
            'expansionCards': [
              for (int i = 1; i <= 3; i++)
                {
                  'badge': '0$i · TWIST',
                  'title': 'Card $i',
                  'description': 'Desc $i',
                  'additionSummary': 'card $i',
                },
            ],
            if (missing != null) 'missing': missing,
          };

      Future<WorkbenchProvider> pumpWithResponse(
        WidgetTester tester,
        Map<String, dynamic> response,
      ) async {
        tester.view.physicalSize = const Size(1440, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final prev = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (p, m) async => response;
        addTearDown(() => GeminiAgentClient.testMockResponder = prev);

        final provider = WorkbenchProvider();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: provider,
                builder: (ctx, _) => ProjectPitchScreen(workbench: provider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('spark_input_field')),
          'Fire vegetables at beetles',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('ingest_idea_summary_btn')));
        await tester.pumpAndSettle();
        return provider;
      }

      testWidgets('shows missing twist, seeds input on tap, ignores bare seed',
          (tester) async {
        final provider = await pumpWithResponse(
          tester,
          intakeJson([
            {'kind': 'TWIST', 'question': 'What makes it stressful?'},
            {'kind': 'bogus', 'question': 'ignored'},
          ]),
        );
        expect(provider.sparkIntake!.missing!.length, 1);
        expect(find.byKey(const ValueKey('spark_missing_nudge')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('spark_missing_TWIST')),
            findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('spark_missing_TWIST')));
        await tester.pump();
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('spark_input_field')),
        );
        expect(field.controller!.text, equals('Twist: '));
        expect(find.byType(TextField), findsOneWidget);

        // Bare seed submit is ignored (text stays, summary unchanged)
        final before = provider.sparkIntake!.baseSummary;
        await tester.tap(find.byKey(const ValueKey('ingest_idea_summary_btn')));
        await tester.pumpAndSettle();
        expect(field.controller!.text, equals('Twist: '));
        expect(provider.sparkIntake!.baseSummary, equals(before));
      });

      testWidgets('empty missing shows covered line', (tester) async {
        await pumpWithResponse(tester, intakeJson(<Object>[]));
        expect(find.text('✓ Action, twist, and setup covered'),
            findsOneWidget);
      });

      testWidgets('absent missing key shows no nudge row', (tester) async {
        final provider = await pumpWithResponse(tester, intakeJson(null));
        expect(provider.sparkIntake!.missing, isNull);
        expect(find.byKey(const ValueKey('spark_missing_nudge')), findsNothing);
      });

      testWidgets('Undo hides the nudge', (tester) async {
        await pumpWithResponse(
          tester,
          intakeJson([
            {'kind': 'SETUP', 'question': 'What camera and engine?'},
          ]),
        );
        expect(find.byKey(const ValueKey('spark_missing_nudge')),
            findsOneWidget);
        // Refine once so an Undo snapshot exists
        await tester.enterText(
          find.byKey(const ValueKey('spark_input_field')),
          'Add wall runs',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('ingest_idea_summary_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('spark_undo_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('spark_missing_nudge')), findsNothing);
      });
    });

    test(
      'Stage 2 Quiet Workbench supports unchecking steps in STABLE features and restoring active upgrade lifecycle',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('Top-down arena shooter');
        await provider.openReleasePlanGate();
        await provider.approveAndExecuteReleasePlan();

        final featId = provider.selectedFeatureId!;
        final feat = provider.documents[featId]!;
        feat.sections['lifecycle'] = FeatureLifecycleStatus.stable.name;
        final updatedStates = FeatureStateNode.getStatesForDocument(feat);
        for (final t in updatedStates.first.checklist) {
          t.completed = true;
          for (final c in t.children) {
            c.completed = true;
          }
        }
        provider.updateFeatureStates(featId, updatedStates);
        expect(provider.getDocumentProgress(featId), 100);

        // Uncheck one sub-step and update states -> lifecycle transitions out of STABLE and progress drops below 100%
        updatedStates.first.checklist.first.children.first.completed = false;
        updatedStates.first.checklist.first.completed = false;
        provider.updateFeatureStates(featId, updatedStates);
        expect(
          provider.documents[featId]!.sections['lifecycle'],
          isNot(FeatureLifecycleStatus.stable.name),
        );
        expect(provider.getDocumentProgress(featId), lessThan(100));
      },
    );

    testWidgets(
      'Option A Inline Feature Playtest Gate logs inline [FIX] bug and passes feature gate in 1 click',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final provider = WorkbenchProvider(enableAutoLoad: false);
        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        await provider.startConceptInterview(
          'Top-down arena shooter with dash and wave spawner in Godot 4.',
        );
        final buildFuture = provider.approveConceptAndBuildRelease();
        await tester.pumpAndSettle();
        await buildFuture;
        await tester.pumpAndSettle();

        final firstFeatId = provider.selectedFeatureId!;
        final firstFeat = provider.documents[firstFeatId]!;
        final statesBefore = FeatureStateNode.getStatesForDocument(firstFeat);
        final cpId = statesBefore.last.id;
        final initialTaskCount = statesBefore.last.checklist.length;

        // 1. Open inline bug drawer on the bottom FEATURE PLAYTEST GATE card
        final logBugBtn = find.byKey(
          ValueKey('feature_gate_log_bug_btn_$cpId'),
        );
        expect(logBugBtn, findsOneWidget);
        await tester.ensureVisible(logBugBtn);
        await tester.pumpAndSettle();
        await tester.tap(logBugBtn);
        await tester.pumpAndSettle();

        final bugInput = find.byKey(ValueKey('feature_gate_bug_input_$cpId'));
        expect(bugInput, findsOneWidget);
        await tester.enterText(
          bugInput,
          'Dash clips through thin arena walls on diagonal input',
        );
        await tester.pumpAndSettle();

        final submitBugBtn = find.byKey(
          ValueKey('feature_gate_bug_submit_btn_$cpId'),
        );
        expect(submitBugBtn, findsOneWidget);
        await tester.tap(submitBugBtn);
        await tester.pumpAndSettle();

        final statesAfterBug = FeatureStateNode.getStatesForDocument(
          provider.documents[firstFeatId]!,
        );
        expect(
          statesAfterBug.last.checklist.length,
          equals(initialTaskCount + 1),
        );
        expect(
          statesAfterBug.last.checklist.last.text,
          contains('[FIX]'),
        );
        expect(
          statesAfterBug.last.edgeCases.any(
            (g) => g.contains('PLAYTEST GUARD'),
          ),
          isTrue,
        );

        // 2. Click "Pass Playtest & Continue ->" on the inline gate card
        final passGateBtn = find.byKey(ValueKey('feature_gate_pass_btn_$cpId'));
        expect(passGateBtn, findsOneWidget);
        await tester.ensureVisible(passGateBtn);
        await tester.pumpAndSettle();
        await tester.tap(passGateBtn);
        await tester.pumpAndSettle();

        expect(provider.getDocumentProgress(firstFeatId), equals(100));
        expect(provider.selectedFeatureId, isNot(equals(firstFeatId)));
      },
    );

    testWidgets(
      'Gemini 3.8 Flash LOW thinking standard, accumulative token usage tracking, pricing math, and reset',
      (tester) async {
        final provider = WorkbenchProvider();
        expect(provider.thinkingLevel, equals('LOW'));
        expect(provider.totalInputTokens, equals(0));
        expect(provider.totalOutputTokens, equals(0));
        expect(provider.totalEstimatedCostUsd, equals(0.0));
        expect(provider.tokenUsageCompactLabel, equals('0 in · 0 out · \$0.00'));

        // 1. Simulate multiple API calls accumulating tokens
        // Call 1: 100,000 in, 20,000 out
        // Cost: (100000 * 0.75 + 20000 * 3.75) / 1,000,000 = (75,000 + 75,000) / 1M = 0.15
        provider.recordTokenUsage(
          inputTokens: 100000,
          outputTokens: 20000,
          thinkingTokens: 5000,
        );
        expect(provider.totalInputTokens, equals(100000));
        expect(provider.totalOutputTokens, equals(20000));
        expect(provider.totalThinkingTokens, equals(5000));
        expect(provider.totalEstimatedCostUsd, closeTo(0.15, 0.0001));
        expect(provider.tokenUsageCompactLabel, equals('100k in · 20k out · \$0.150'));

        // Call 2: Add 50,000 in, 10,000 out
        // Total In: 150,000, Total Out: 30,000
        // Cost: (150000 * 0.75 + 30000 * 3.75) / 1M = (112,500 + 112,500) / 1M = 0.225
        provider.recordTokenUsage(
          inputTokens: 50000,
          outputTokens: 10000,
          thinkingTokens: 2000,
        );
        expect(provider.totalInputTokens, equals(150000));
        expect(provider.totalOutputTokens, equals(30000));
        expect(provider.totalThinkingTokens, equals(7000));
        expect(provider.totalEstimatedCostUsd, closeTo(0.225, 0.0001));
        expect(provider.tokenUsageCompactLabel, equals('150k in · 30k out · \$0.225'));

        // 2. Pump the app UI and verify top bar token tracker pill displays
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        final pillFinder = find.byKey(const ValueKey('token_usage_tracker_pill'));
        expect(pillFinder, findsOneWidget);
        expect(find.text('150k in · 30k out · \$0.225'), findsOneWidget);

        // 3. Click the pill to reset token counters
        await tester.tap(pillFinder);
        await tester.pumpAndSettle();

        expect(provider.totalInputTokens, equals(0));
        expect(provider.totalOutputTokens, equals(0));
        expect(provider.totalEstimatedCostUsd, equals(0.0));
        expect(find.text('0 in · 0 out · \$0.00'), findsOneWidget);

        // 4. Open AI settings dialog and verify pricing rates & reset button in dialog
        final aiSettingsBtn = find.byKey(const ValueKey('ai_settings_btn'));
        expect(aiSettingsBtn, findsOneWidget);
        await tester.tap(aiSettingsBtn);
        await tester.pumpAndSettle();

        expect(find.text('04 · ACCUMULATIVE TOKEN USAGE & EST. COST'), findsOneWidget);
        expect(find.text('\$0.75 / 1M'), findsOneWidget);
        expect(find.text('\$3.75 / 1M (inc. thinking)'), findsOneWidget);

        final dialogResetBtn = find.byKey(const ValueKey('reset_token_usage_btn'));
        expect(dialogResetBtn, findsOneWidget);
        await tester.ensureVisible(dialogResetBtn);
        await tester.pumpAndSettle();
        await tester.tap(dialogResetBtn);
        await tester.pumpAndSettle();

        expect(provider.totalInputTokens, equals(0));
      },
    );

    testWidgets(
      'Core Loop Beats (06 · Core Loop) are decoupled from System Epics (E01..EN) in Stage 1 UI, Consolidation, Reconciliation, and Live Sync',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wastelandCoreLoopBeats = <String>[
          'Route Departure — Player steps past outpost gates onto highway as HUD tracks active haul weight.',
          'Hostile Ambush — Scavengers open fire from roadside cover while player returns hitscan shots to neutralize threats.',
          'Cargo Retrieval — Player sifts fallen scavenger crates to pack sellable scrap into backpack inventory.',
          'Transit Risk — Player navigates hazard choke points, risking complete cargo drop on lethal damage.',
          'Settlement Barter — Player enters destination gates, selling recovered trade goods to merchants for currency.',
          'Gear Resupply — Player purchases surplus ammunition and medkits before plotting the next overland route.',
        ];

        GeminiAgentClient.testMockResponder = (prompt, model) async {
          if (prompt.contains(
            'creating a Stage 1 Concept Blueprint for this spark idea:',
          )) {
            return {
              'title': 'Wasteland Peddler',
              'goal':
                  'Wasteland Haul Loop — Pack scrap cargo, survive highway ambushes, and barter at settlement gates.',
              'gameSpec': [
                '3D First-Person',
                'WASD + Mouse Aim',
                'Singleplayer',
                'Highway Corridor',
              ],
              'techSpec': [
                'Godot 4 (3D)',
                'PC Desktop',
                '3D Low-Poly Meshes',
                'Offline Local Save',
              ],
              'designPillars': [
                'Every Pound Matters — Heavy cargo directly slows movement speed.',
                'Lethal Highway Choke Points — Ambushes demand quick cover.',
              ],
              'tradeOffs': [
                'Readable Weight Tiers over complex inventory tetris',
                'Hitscan Scavenger Duels over realistic bullet drop',
              ],
              'coreLoopBeats': wastelandCoreLoopBeats,
              'exclusions': [
                'No drivable vehicles or caravan pack beasts',
                'No open-world free-roam map or procedural route generation',
              ],
              'doneWhen':
                  'Eliminate highway scavengers, pack dropped cargo, and sell haul to settlement merchant without dying.',
              'releaseTrainTitles': [
                'v0.1: Wasteland Peddler - Prototype',
              ],
            };
          }

          if (prompt.contains('planning Release:')) {
            // Return 4 consolidated System Epics covering all 6 Core Loop Beats (many-to-many)
            return {
              'goal':
                  'Wasteland Haul Loop — Build the 4 core systems for highway transit, ambush combat, cargo haul, and settlement barter.',
              'doneWhen':
                  'Eliminate highway scavengers, pack dropped cargo, and sell haul to settlement merchant without dying.',
              'explicitExclusions': [
                'No drivable vehicles or caravan pack beasts',
              ],
              'beats': [
                {
                  'id': 'beat_1',
                  'title': 'Highway Route & Transit',
                  'goal':
                      'Step past outpost gates onto highway route departure and navigate transit risk hazard choke points.',
                  'doneWhen':
                      'Player departs outpost -> navigates highway hazard choke points.',
                  'features': [
                    {
                      'id': 'feat_1_1',
                      'title': 'Highway Hazard Corridor',
                      'lifecycle': 'new',
                      'included': true,
                      'estimatedHours': 3,
                      'goal':
                          'Route departure gate and transit risk hazard choke points.',
                      'inScope': ['Outpost departure gate', 'Hazard choke point'],
                      'doneWhen':
                          'Step past gate -> traverse highway hazard zone.',
                      'tuningParams': ['moveSpeed: 6.0 m/s'],
                      'edgeCases': [
                        '[LETHAL DROP GUARD] Drop cargo on lethal hazard damage',
                      ],
                      'checkpoints': [
                        {
                          'title': 'Highway Corridor & Hazards',
                          'playtestCriteria':
                              'Depart outpost -> cross hazard choke point.',
                          'tasks': [
                            'Outpost Gate & Highway Setup (1.5h)',
                            'Transit Hazard Choke Point (1.5h)',
                          ],
                        },
                      ],
                    },
                  ],
                },
                {
                  'id': 'beat_2',
                  'title': 'Scavenger Ambush Combat',
                  'goal':
                      'Survive hostile ambush as scavengers open fire from cover and player returns hitscan shots.',
                  'doneWhen':
                      'Fire hitscan rifle -> neutralize roadside ambush scavengers.',
                  'features': [
                    {
                      'id': 'feat_2_1',
                      'title': 'Hitscan Scavenger Duel',
                      'lifecycle': 'new',
                      'included': true,
                      'estimatedHours': 3,
                      'goal':
                          'Hostile ambush scavenger cover fire and player hitscan shots.',
                      'inScope': ['Hitscan raycast', 'Scavenger ambush AI'],
                      'doneWhen':
                          'Shoot scavenger -> scavenger drops cargo crate.',
                      'tuningParams': ['rifleDamage: 25.0 hp'],
                      'edgeCases': [
                        '[DEAD TARGET GUARD] Ignore hitscan on defeated scavenger',
                      ],
                      'checkpoints': [
                        {
                          'title': 'Hitscan Ambush Combat',
                          'playtestCriteria':
                              'Fire hitscan shots -> defeat ambush scavenger.',
                          'tasks': [
                            'Hitscan Weapon Raycast (1.5h)',
                            'Roadside Scavenger Ambush (1.5h)',
                          ],
                        },
                      ],
                    },
                  ],
                },
                {
                  'id': 'beat_3',
                  'title': 'Cargo Loot & Inventory',
                  'goal':
                      'Cargo retrieval from fallen scavenger crates to pack sellable scrap into backpack inventory with haul weight.',
                  'doneWhen':
                      'Interact with crate -> pack scrap into weighted backpack.',
                  'features': [
                    {
                      'id': 'feat_3_1',
                      'title': 'Crate Scrap & Weight HUD',
                      'lifecycle': 'new',
                      'included': true,
                      'estimatedHours': 3,
                      'goal':
                          'Cargo retrieval from scavenger crates and HUD haul weight tracking.',
                      'inScope': ['Crate loot pickup', 'Haul weight HUD'],
                      'doneWhen':
                          'Pack scrap from crate -> HUD updates haul weight.',
                      'tuningParams': ['maxCarryWeight: 50.0 kg'],
                      'edgeCases': [
                        '[OVERWEIGHT GUARD] Cap sprint when haul exceeds maxCarryWeight',
                      ],
                      'checkpoints': [
                        {
                          'title': 'Cargo Retrieval & Weight',
                          'playtestCriteria':
                              'Loot fallen crate -> backpack weight updates.',
                          'tasks': [
                            'Scavenger Crate Loot Pickup (1.5h)',
                            'Backpack Haul Weight HUD (1.5h)',
                          ],
                        },
                      ],
                    },
                  ],
                },
                {
                  'id': 'beat_4',
                  'title': 'Settlement Merchant & Resupply',
                  'goal':
                      'Settlement barter selling recovered trade goods to merchants for currency and gear resupply purchasing surplus ammo and medkits.',
                  'doneWhen':
                      'Sell cargo to merchant -> buy surplus ammo and medkits.',
                  'features': [
                    {
                      'id': 'feat_4_1',
                      'title': 'Merchant Barter & Resupply Counter',
                      'lifecycle': 'new',
                      'included': true,
                      'estimatedHours': 3,
                      'goal':
                          'Settlement barter for currency and gear resupply for ammo and medkits.',
                      'inScope': ['Merchant sell counter', 'Gear resupply shop'],
                      'doneWhen':
                          'Sell scrap for currency -> purchase ammo and medkits.',
                      'tuningParams': ['ammoPackCost: 15 caps'],
                      'edgeCases': [
                        '[INSUFFICIENT FUNDS GUARD] Block gear resupply when currency is low',
                      ],
                      'checkpoints': [
                        {
                          'title': 'Settlement Barter & Gear Resupply',
                          'playtestCriteria':
                              'Sell scrap -> purchase surplus ammo and medkits.',
                          'tasks': [
                            'Settlement Merchant Barter Counter (1.5h)',
                            'Surplus Ammo & Medkit Resupply (1.5h)',
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            };
          }

          return _mockGeminiResponder(prompt, model);
        };

        final provider = WorkbenchProvider();
        await provider.startConceptInterview(
          'Wasteland Peddler: haul cargo along a dangerous highway and barter at settlements',
          true,
        );

        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        // 1. Before v0.1 is built, Card 09 · RELEASE TARGET must show "6 Loop Beats · 4 Specs" (NEVER "6 Epics")
        expect(
          find.text(
            '6 Loop Beats · 4 Specs · Click to rename target ✎',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            '6 Epics · 4 Specs · Click to rename target ✎',
          ),
          findsNothing,
        );

        // 2. Verify deterministic system consolidation also groups 6 1:1 loop-beat Epics into 4 System Epics
        final rawSixBeats = <ProposedBeatBlueprint>[
          for (int i = 0; i < wastelandCoreLoopBeats.length; i++)
            ProposedBeatBlueprint(
              id: 'beat_${i + 1}',
              title: wastelandCoreLoopBeats[i].split('—').first.trim(),
              goal: wastelandCoreLoopBeats[i].split('—').last.trim(),
              doneWhen: 'Verified.',
              features: const [],
            ),
        ];
        final consolidated =
            ReleasePlannerAgent.consolidateSystemEpicsFromLoopBeats(rawSixBeats);
        expect(consolidated.length, equals(4));

        // 3. Build v0.1 and verify reconcileReleaseBlueprintWithPhaseRules keeps the 4 consolidated System Epics (does NOT pad to 6)
        await tester.runAsync(() => provider.approveConceptAndBuildRelease());
        await tester.pump();

        expect(provider.conceptDraft!.coreLoopBeats.length, equals(6));
        expect(provider.activeReleaseBeats.length, equals(4));

        // 4. Verify live Stage 1 -> Stage 2 sync preserves the 4 consolidated System Epics (many-to-1 coverage)
        provider.updateConceptDraft((draft) {
          draft.coreLoopBeats[5] =
              'Gear Resupply — Player purchases surplus shotgun shells and medkits before plotting the next overland route.';
        });
        expect(provider.activeReleaseBeats.length, equals(4));
        expect(
          provider.activeReleaseBeats.last.title,
          equals('Settlement Merchant & Resupply'),
        );

        // 5. Switch back to Stage 1 Concept Blueprint and verify Card 09 shows "4 Epics · 6 Loop Beats · 4 Specs"
        provider.setStage(WorkbenchStage.projectPitch);
        await tester.pump();
        expect(
          find.text(
            '4 Epics · 6 Loop Beats · 4 Specs · Click to rename target ✎',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
