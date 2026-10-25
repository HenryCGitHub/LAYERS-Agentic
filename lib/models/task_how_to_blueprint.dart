import '../models/feature_state.dart';
import '../models/tier_document.dart';

/// Represents a single checkable "How-To" sub-step inside a Parent Task's walkthrough.
class TaskHowToSubStep {
  final Subtask subtask;
  final String stepNumberLabel; // e.g., "STEP 1.1 · CREATE ASSET FILE"
  final String shortTitle;      // e.g., "Create BP_GridTileActor"
  final String instruction;     // Concrete implementation instruction
  final String verifyResult;    // "✓ VERIFY BEFORE CHECKING [✓]" visual check
  final String stepPath;        // e.g., "Content Browser → /Game/Blueprints"
  final String codeFormula;     // Short code / formula / hierarchy snippet
  final String explainConcept;  // Project-connected "🎯 Connects to your Spec & Next Step" note
  final List<String> specChips; // Spec connection chips (e.g. ["Next: ...", "Spec: ..."])
  final String quickFixPitfall; // Step-specific "🔧 Quick Fix / Common Pitfall" for the right footer
  final int estimatedMinutes;   // Weighted minutes for this specific step (e.g., 15, 25, 65, 35)
  final String etaLabel;        // Formatted step ETA (e.g., "15m", "25m", "1.1h")
  final bool isGuardStep;

  const TaskHowToSubStep({
    required this.subtask,
    required this.stepNumberLabel,
    this.shortTitle = '',
    required this.instruction,
    this.verifyResult = '',
    this.stepPath = '',
    required this.codeFormula,
    this.explainConcept = '',
    this.specChips = const [],
    this.quickFixPitfall = '',
    this.estimatedMinutes = 15,
    this.etaLabel = '15m',
    this.isGuardStep = false,
  });
}

/// Synthesizes mechanic-specific scope bullets, tuning parameters, edge-case guards,
/// and 60/40 Playable Checkpoint blueprints for any custom or Beat-derived feature title.
class MechanicArchetypeProfile {
  final String category; // 'grapple', 'movement', 'combat', 'farming', 'economy', 'building', 'ui', 'core'
  final String goal;
  final String doneWhen;
  final List<String> inScope;
  final List<String> outOfScope;
  final List<String> tuningParams;
  final List<String> edgeCases;
  final String cp1Title;
  final String cp1Playtest;
  final List<String> cp1Tasks;
  final String cp2Title;
  final String cp2Playtest;
  final List<String> cp2Tasks;

  const MechanicArchetypeProfile({
    required this.category,
    required this.goal,
    required this.doneWhen,
    required this.inScope,
    required this.outOfScope,
    required this.tuningParams,
    required this.edgeCases,
    required this.cp1Title,
    required this.cp1Playtest,
    required this.cp1Tasks,
    required this.cp2Title,
    required this.cp2Playtest,
    required this.cp2Tasks,
  });

  static String inferCategory(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('grappl') ||
        lower.contains('hook') ||
        lower.contains('swing') ||
        lower.contains('rope') ||
        lower.contains('tether') ||
        lower.contains('zipline')) {
      return 'grapple';
    }
    if (lower.contains('dash') ||
        lower.contains('slide') ||
        lower.contains('jump') ||
        lower.contains('wall') ||
        lower.contains('sprint') ||
        lower.contains('climb') ||
        lower.contains('move') ||
        lower.contains('locomotion') ||
        lower.contains('parkour')) {
      return 'movement';
    }
    if (lower.contains('shotgun') ||
        lower.contains('weapon') ||
        lower.contains('gun') ||
        lower.contains('shoot') ||
        lower.contains('fire') ||
        lower.contains('attack') ||
        lower.contains('combat') ||
        lower.contains('slash') ||
        lower.contains('enemy') ||
        lower.contains('wave') ||
        lower.contains('turret') ||
        lower.contains('boss') ||
        lower.contains('damage') ||
        lower.contains('active gameplay') ||
        lower.contains('gameplay beat') ||
        lower.contains('escalation') ||
        lower.contains('skill execution')) {
      return 'combat';
    }
    if (lower.contains('crop') ||
        lower.contains('farm') ||
        lower.contains('plant') ||
        lower.contains('harvest') ||
        lower.contains('seed') ||
        lower.contains('soil') ||
        lower.contains('water') ||
        lower.contains('forag')) {
      return 'farming';
    }
    if (lower.contains('loadout') ||
        lower.contains('prep') ||
        lower.contains('staging') ||
        lower.contains('setup') ||
        lower.contains('equip')) {
      return 'loadout';
    }
    if (lower.contains('upgrade') ||
        lower.contains('reward') ||
        lower.contains('perk') ||
        lower.contains('pickup') ||
        lower.contains('resource') ||
        lower.contains('claim')) {
      return 'upgrade';
    }
    if (lower.contains('reset') ||
        lower.contains('next round') ||
        lower.contains('restart') ||
        lower.contains('resolve') ||
        lower.contains('wave clear')) {
      return 'reset';
    }
    if (lower.contains('shop') ||
        lower.contains('buy') ||
        lower.contains('sell') ||
        lower.contains('smelt') ||
        lower.contains('furnace') ||
        lower.contains('craft') ||
        lower.contains('invent') ||
        lower.contains('loot') ||
        lower.contains('ore')) {
      return 'economy';
    }
    if (lower.contains('grid') ||
        lower.contains('build') ||
        lower.contains('place') ||
        lower.contains('construct') ||
        lower.contains('tile') ||
        lower.contains('snap')) {
      return 'building';
    }
    if (lower.contains('camera') ||
        lower.contains('hud') ||
        lower.contains('ui') ||
        lower.contains('radar') ||
        lower.contains('minimap') ||
        lower.contains('menu') ||
        lower.contains('medal') ||
        lower.contains('score') ||
        lower.contains('timer')) {
      return 'ui';
    }
    return 'core';
  }

  /// Replaces meta design-doc beat names (`Active Gameplay Beats`, `Loop Resolution & Reset`)
  /// with concrete gameplay phase titles (`Arena Movement & Combat`, `Round Clear & Reset`).
  static String concreteBeatDisplayTitle(String rawBeatTitle) {
    final clean = rawBeatTitle.split(':').last.split('—').last.trim();
    if (clean.isEmpty) return rawBeatTitle;
    final lower = clean.toLowerCase();
    if (lower == 'active gameplay beats' ||
        lower == 'active gameplay beat' ||
        lower == 'core mechanic escalation' ||
        lower == 'primary skill execution') {
      return 'Arena Movement & Combat';
    }
    if (lower == 'loop resolution & reset') {
      return 'Round Clear & Reset';
    }
    if (lower == 'resource & upgrade choice') {
      return 'Loot & Upgrade Choice';
    }
    return clean;
  }

  /// Resolves a distinct, concrete 3–4 word gameplay mechanic title whenever a feature
  /// title (or its stripped remainder) is the generic `"Mechanics & Controls"` suffix.
  static String concreteFeatureTitleForBeat(
    String rawTitle, {
    String? beatTitle,
    int beatIndex = 0,
  }) {
    final cleanFeat = rawTitle.trim();
    if (cleanFeat.isEmpty) return 'Core Mechanic';

    String stripped = cleanFeat;
    if (beatTitle != null && beatTitle.trim().isNotEmpty) {
      final cleanBeat = beatTitle.split(':').last.split('—').last.trim();
      final lowerFeat = cleanFeat.toLowerCase();
      final lowerBeat = cleanBeat.toLowerCase();
      if (cleanBeat.isNotEmpty &&
          lowerFeat.startsWith(lowerBeat) &&
          cleanFeat.length > cleanBeat.length + 2) {
        var rem = cleanFeat.substring(cleanBeat.length).trimLeft();
        if (rem.startsWith(':') ||
            rem.startsWith('—') ||
            rem.startsWith('-')) {
          rem = rem.substring(1).trimLeft();
        }
        if (rem.isNotEmpty) {
          stripped = rem;
        }
      }
    }

    final lowerStripped = stripped.toLowerCase();
    final isGenericMechanicsSuffix =
        lowerStripped == 'mechanics & controls' ||
        lowerStripped == 'core mechanics & controls' ||
        cleanFeat.toLowerCase().endsWith('mechanics & controls');

    if (!isGenericMechanicsSuffix) {
      return stripped;
    }

    final contextLower = '$cleanFeat ${beatTitle ?? ''}'.toLowerCase();
    if (contextLower.contains('shield') || contextLower.contains('boss')) {
      return 'Boss Shield & Weakpoint';
    }
    if (contextLower.contains('grappl') ||
        contextLower.contains('hook') ||
        contextLower.contains('swing') ||
        contextLower.contains('tether')) {
      return 'Grapple Hook & Swing';
    }
    if (contextLower.contains('entry') ||
        contextLower.contains('traversal') ||
        contextLower.contains('dash') ||
        contextLower.contains('locomotion') ||
        contextLower.contains('parkour')) {
      return 'Movement & Dash Controls';
    }
    if (contextLower.contains('loadout') ||
        contextLower.contains('prep') ||
        contextLower.contains('staging') ||
        contextLower.contains('equip')) {
      return 'Weapon & Ability Equip';
    }
    if (contextLower.contains('hazard') ||
        contextLower.contains('enemy') ||
        contextLower.contains('escalation') ||
        contextLower.contains('counter')) {
      return 'Enemy Wave & Hazard Spawner';
    }
    if (contextLower.contains('combat') ||
        contextLower.contains('weapon') ||
        contextLower.contains('shoot') ||
        contextLower.contains('fire') ||
        contextLower.contains('attack') ||
        contextLower.contains('active gameplay') ||
        contextLower.contains('gameplay beat') ||
        contextLower.contains('skill execution')) {
      return 'Movement & Weapon Firing';
    }
    if (contextLower.contains('drop') ||
        contextLower.contains('pickup') ||
        contextLower.contains('loot') ||
        contextLower.contains('tally')) {
      return 'Loot Drop & Pickup';
    }
    if (contextLower.contains('upgrade') ||
        contextLower.contains('reward') ||
        contextLower.contains('resource') ||
        contextLower.contains('perk') ||
        contextLower.contains('choice')) {
      return 'Wave-Clear Upgrade Pick';
    }
    if (contextLower.contains('reset') ||
        contextLower.contains('resolution') ||
        contextLower.contains('resolve') ||
        contextLower.contains('next round') ||
        contextLower.contains('next wave') ||
        contextLower.contains('next-wave') ||
        contextLower.contains('clear')) {
      return 'Round Clear & Wave Reset';
    }
    if (contextLower.contains('crop') ||
        contextLower.contains('farm') ||
        contextLower.contains('plant') ||
        contextLower.contains('harvest')) {
      return 'Crop Plot & Growth Timer';
    }
    if (contextLower.contains('shop') ||
        contextLower.contains('buy') ||
        contextLower.contains('sell') ||
        contextLower.contains('smelt') ||
        contextLower.contains('craft')) {
      return 'Shop Buy & Sell';
    }
    if (contextLower.contains('grid') ||
        contextLower.contains('build') ||
        contextLower.contains('place') ||
        contextLower.contains('tile')) {
      return 'Grid Snap & Placement';
    }

    switch (beatIndex % 4) {
      case 0:
        return 'Weapon & Ability Equip';
      case 1:
        return 'Movement & Weapon Firing';
      case 2:
        return 'Wave-Clear Upgrade Pick';
      default:
        return 'Round Clear & Wave Reset';
    }
  }

  static MechanicArchetypeProfile fromFeatureTitle(
    String rawTitle, {
    String? beatTitle,
    String? beatDescription,
  }) {
    final clean = rawTitle.trim().isEmpty ? 'Core Mechanic' : rawTitle.trim();
    final titleCat = inferCategory(clean);
    final cat = titleCat != 'core'
        ? titleCat
        : inferCategory('$clean ${beatTitle ?? ''} ${beatDescription ?? ''}');

    switch (cat) {
      case 'grapple':
        return MechanicArchetypeProfile(
          category: 'grapple',
          goal: 'Build $clean raycast targeting, tether pull velocity, and release momentum.',
          doneWhen: 'Player fires $clean at valid anchors, swings/pulls smoothly across gaps, and keeps momentum on release.',
          inScope: [
            'Anchor raycast check and tether line rendering for $clean',
            'Pull/swing velocity impulse and release momentum transfer',
          ],
          outOfScope: [
            'Multi-segment Verlet rope wrapping around complex meshes',
          ],
          tuningParams: const [
            'hookMaxRange: 18.0 m',
            'hookPullSpeed: 28.0 m/s',
            'releaseBoostMultiplier: 1.25 x',
          ],
          edgeCases: const [
            '[LOS BREAK GUARD] Detach tether cleanly if moving obstacle blocks line of sight',
            '[MAX TENSION CLAMP] Clamp velocity on release so frame spikes never launch player out of bounds',
          ],
          cp1Title: '$clean Targeting & Pull Velocity',
          cp1Playtest: 'Aim at anchor within hookMaxRange and fire -> player pulls toward anchor and releases with momentum.',
          cp1Tasks: [
            'Implement anchor raycast check and tether state entry for $clean (2h)',
            'Apply hookPullSpeed velocity and releaseBoostMultiplier on detach (2h)',
          ],
          cp2Title: 'Tether Visual Line & Detach Guards',
          cp2Playtest: 'Break line-of-sight mid-pull -> tether detaches cleanly with audio/visual cue and zero physics hitch.',
          cp2Tasks: [
            'Render active tether line and attach/detach audio-visual cues (1h)',
            'Enforce line-of-sight break guard and velocity clamp for $clean (1h)',
          ],
        );

      case 'movement':
        return MechanicArchetypeProfile(
          category: 'movement',
          goal: 'Build responsive $clean input handling, velocity acceleration, and recovery timing.',
          doneWhen: 'Player chains $clean smoothly across arena obstacles with zero input drop or wall-clip.',
          inScope: [
            'Directional input read, acceleration curve, and velocity impulse for $clean',
            'Screen-feel feedback (FOV kick / dust particles) and cooldown recovery',
          ],
          outOfScope: [
            'Procedural skeletal IK foot placement',
          ],
          tuningParams: const [
            'moveMaxSpeed: 240.0 px/s',
            'burstImpulseSpeed: 420.0 px/s',
            'moveCooldownSec: 0.35 s',
          ],
          edgeCases: const [
            '[CORNER SLIDE GUARD] Slide smoothly along wall normals without zeroing tangential velocity',
            '[BUFFER WINDOW] Queue input pressed 0.10s before landing or cooldown expiry',
          ],
          cp1Title: '$clean Velocity & Physics Loop',
          cp1Playtest: 'Trigger $clean while moving -> character accelerates to burstImpulseSpeed and slides cleanly along walls.',
          cp1Tasks: [
            'Bind directional input and velocity impulse math for $clean (2h)',
            'Enforce wall-slide normal projection and cooldown recovery timer (2h)',
          ],
          cp2Title: '$clean Feel Cues & Input Buffer',
          cp2Playtest: 'Chain $clean repeatedly -> verify 0.10s input buffer and crisp FOV/trail feedback.',
          cp2Tasks: [
            'Hook up motion trail / FOV kick and sound cue on $clean trigger (1h)',
            'Verify input buffer window and mid-air transition guard (1h)',
          ],
        );

      case 'combat':
        return MechanicArchetypeProfile(
          category: 'combat',
          goal: 'Build $clean hit detection, damage/knockback application, and reload/cooldown pacing.',
          doneWhen: 'Player engages targets with $clean, registers crisp hit-confirm feedback, and clears enemy waves reliably.',
          inScope: [
            'Hitbox / raycast detection, damage application, and knockback impulse for $clean',
            'Muzzle / impact flash, hit-stop frame, and ammo / cooldown HUD readout',
          ],
          outOfScope: [
            'limb-specific gore dismemberment physics',
          ],
          tuningParams: const [
            'baseDamage: 25.0 hp',
            'fireCooldownSec: 0.45 s',
            'knockbackImpulse: 14.0 m/s',
          ],
          edgeCases: const [
            '[HIT-ONCE GUARD] Single attack swing or projectile hit-reg applies damage exactly once per target ID',
            '[RELOAD INTERRUPT] Dodging or swapping mid-reload cancels reload timer cleanly without ammo duplication',
          ],
          cp1Title: '$clean Hit Detection & Knockback',
          cp1Playtest: 'Fire/trigger $clean at test target -> deducts baseDamage, applies knockbackImpulse, and respects fireCooldownSec.',
          cp1Tasks: [
            'Implement raycast/hitbox query and baseDamage application for $clean (2h)',
            'Apply knockbackImpulse and enforce single-hit-per-target guard (2h)',
          ],
          cp2Title: 'Impact Feel & Cooldown Readout',
          cp2Playtest: 'Rapid-fire $clean in arena -> verify hit-flash, audio punch, and clean reload/cooldown interrupt.',
          cp2Tasks: [
            'Hook up target hit-flash, impact SFX, and HUD ammo/cooldown bar (1h)',
            'Verify reload/cooldown interrupt guard when switching states (1h)',
          ],
        );

      case 'farming':
        return MechanicArchetypeProfile(
          category: 'farming',
          goal: 'Build $clean plot interaction, growth stage timer progression, and harvest item yield.',
          doneWhen: 'Player plants, grows, and harvests crops via $clean with clear stage visuals and inventory pickup.',
          inScope: [
            'Plot tile state machine (Empty -> Planted -> Growing -> Ready) for $clean',
            'Growth tick timer, harvest pickup spawn, and plot reset',
          ],
          outOfScope: [
            'Seasonal weather simulation and soil pH chemistry',
          ],
          tuningParams: const [
            'growthStageDuration: 12.0 s',
            'harvestYieldCount: 3 items',
            'interactRadius: 1.8 m',
          ],
          edgeCases: const [
            '[OCCUPIED PLOT GUARD] Prevent planting a second seed on an already planted tile',
            '[FULL INVENTORY DROP] If player storage is full on harvest, spawn pickup item on ground instead of deleting yield',
          ],
          cp1Title: '$clean Plot State & Growth Timer',
          cp1Playtest: 'Interact with empty plot -> plants seed, advances through growthStageDuration, and marks Ready.',
          cp1Tasks: [
            'Implement plot state machine and growthStageDuration tick timer for $clean (2h)',
            'Enforce occupied-plot guard and interaction range check (1h)',
          ],
          cp2Title: 'Harvest Yield & Visual Stage Cues',
          cp2Playtest: 'Harvest mature plot -> spawns harvestYieldCount items, plays pop cue, and resets plot to Empty.',
          cp2Tasks: [
            'Spawn harvestYieldCount items on harvest and update storage readout (1h)',
            'Hook up stage sprite swap and full-inventory overflow drop guard (1h)',
          ],
        );

      case 'economy':
        return MechanicArchetypeProfile(
          category: 'economy',
          goal: 'Build $clean item transaction logic, resource count validation, and immediate UI inventory sync.',
          doneWhen: 'Player executes $clean transactions with accurate resource deduction/addition and zero duplicate item bugs.',
          inScope: [
            'Resource requirement check, count delta math, and output grant for $clean',
            'Slot highlight, transaction sound cue, and live counter readout',
          ],
          outOfScope: [
            'Dynamic NPC supply-and-demand market inflation',
          ],
          tuningParams: const [
            'transactionCostBase: 25 gold',
            'processDurationSec: 2.0 s',
            'stackMaxCapacity: 99 items',
          ],
          edgeCases: const [
            '[INSUFFICIENT FUNDS GUARD] Block transaction and flash cost label red when resources < transactionCostBase',
            '[STACK CAP CLAMP] Clamp slot count at stackMaxCapacity and spill remainder to next open slot',
          ],
          cp1Title: '$clean Transaction & Resource Math',
          cp1Playtest: 'Trigger $clean with valid resources -> deducts cost, grants output, and updates inventory count.',
          cp1Tasks: [
            'Implement resource check and inventory delta math for $clean (2h)',
            'Enforce insufficient-funds and stackMaxCapacity overflow guards (1h)',
          ],
          cp2Title: '$clean UI Readout & Audio Cues',
          cp2Playtest: 'Attempt $clean both with and without enough resources -> verify confirm chime vs. red reject flash.',
          cp2Tasks: [
            'Wire live resource counter labels and slot highlight for $clean (1h)',
            'Hook up transaction confirm SFX and insufficient-resource shake cue (1h)',
          ],
        );

      case 'building':
        return MechanicArchetypeProfile(
          category: 'building',
          goal: 'Build $clean grid coordinate snapping, placement collision check, and structure instantiation.',
          doneWhen: 'Player previews ghost placement on the grid, validates clear cells, and places/removes structures cleanly.',
          inScope: [
            'World-to-grid coordinate snapping and cell occupancy lookup for $clean',
            'Valid/invalid ghost preview tint and placement confirmation cue',
          ],
          outOfScope: [
            'Structural physics collapse simulation',
          ],
          tuningParams: const [
            'gridCellSize: 32.0 px',
            'placeReachDistance: 4.5 tiles',
            'refundRatio: 1.0 x',
          ],
          edgeCases: const [
            '[OVERLAP GUARD] Block placement and tint ghost red when target cell is occupied or overlaps player collider',
            '[BOUNDARY CLAMP] Reject grid coordinates outside valid build bounds',
          ],
          cp1Title: '$clean Grid Snapping & Cell Occupancy',
          cp1Playtest: 'Move cursor across arena -> ghost snaps to gridCellSize steps and places structure on open cell.',
          cp1Tasks: [
            'Implement world-to-grid snapping and cell occupancy dictionary for $clean (2h)',
            'Instantiate placed structure and block overlapping cells (1h)',
          ],
          cp2Title: 'Placement Ghost Tint & Removal Guard',
          cp2Playtest: 'Hover over occupied cell -> ghost tints red and blocks click; right-click removes and refunds cleanly.',
          cp2Tasks: [
            'Wire green/red ghost preview shader and placement thud SFX (1h)',
            'Enforce player-overlap guard and clean cell release on removal (1h)',
          ],
        );

      case 'ui':
        return MechanicArchetypeProfile(
          category: 'ui',
          goal: 'Build $clean state binding, smooth camera/HUD interpolation, and threshold notifications.',
          doneWhen: 'Camera and HUD readouts for $clean update immediately in sync with gameplay state changes.',
          inScope: [
            'Event-driven HUD readout binding and smooth interpolation for $clean',
            'Threshold pop animation and clean reset on round restart',
          ],
          outOfScope: [
            'Custom remappable HUD layout editor',
          ],
          tuningParams: const [
            'cameraFollowLerp: 14.0',
            'hudPopScale: 1.18 x',
            'readoutLerpSpeed: 10.0',
          ],
          edgeCases: const [
            '[ARENA BOUND CLAMP] Clamp camera and off-screen indicators cleanly at level edges',
            '[RAPID EVENT DEBOUNCE] Coalesce simultaneous state changes in the same frame without UI flicker',
          ],
          cp1Title: '$clean State Signal & Smooth Readout',
          cp1Playtest: 'Trigger state change in arena -> $clean updates immediately with smooth lerp and zero frame hitch.',
          cp1Tasks: [
            'Subscribe $clean presenter to gameplay state signal and update readout (2h)',
            'Apply cameraFollowLerp / readoutLerpSpeed smoothing and arena bound clamp (2h)',
          ],
          cp2Title: 'Threshold Callout & Reset Cleanup',
          cp2Playtest: 'Cross target threshold and reset round -> badge animates once and resets cleanly.',
          cp2Tasks: [
            'Trigger hudPopScale callout animation and audio chime on threshold (1h)',
            'Enforce rapid-event debounce and clean HUD reset on loop restart (1h)',
          ],
        );

      case 'loadout':
        return MechanicArchetypeProfile(
          category: 'loadout',
          goal: 'Let the player pick their starting weapon and ability in the staging area and step into the arena trigger to start a run.',
          doneWhen: 'Player interacts with weapon/ability pedestals to equip their loadout, sees HUD ammo/ability slots update, and enters the arena cleanly.',
          inScope: [
            'Staging weapon/ability selection pedestals and equip interaction for $clean',
            'Active weapon slot binding, HUD icon/ammo sync, and arena start trigger',
          ],
          outOfScope: [
            'Persistent multi-tab skill trees and cosmetic skin lockers',
          ],
          tuningParams: const [
            'startingAmmoMax: 30 rounds',
            'swapCooldownSec: 0.25 s',
            'interactRadius: 2.0 m',
          ],
          edgeCases: const [
            '[EMPTY LOADOUT GUARD] Require at least 1 equipped primary weapon before activating the arena launch trigger',
            '[SWAP DEBOUNCE] Lock weapon swap duringswapCooldownSec so rapid presses never spawn duplicate weapon actors',
          ],
          cp1Title: '$clean Weapon & Ability Equip',
          cp1Playtest: 'Interact with a weapon pedestal in the staging area -> player equips the weapon, HUD ammo updates, and stepping into the launch zone starts Round 1.',
          cp1Tasks: [
            'Create staging pedestal interaction and active weapon/ability equip logic for $clean (2h)',
            'Bind HUD weapon/ammo readout and arena launch trigger volume (2h)',
          ],
          cp2Title: '$clean Swap Guard & Visual Cues',
          cp2Playtest: 'Rapidly swap pedestals and test entering arena unarmed -> verify swapCooldownSec debounce and empty-loadout guard.',
          cp2Tasks: [
            'Hook up weapon equip SFX, pedestal highlight, and HUD slot flash (1h)',
            'Enforce empty-loadout launch guard and swapCooldownSec debounce (1h)',
          ],
        );

      case 'upgrade':
        return MechanicArchetypeProfile(
          category: 'upgrade',
          goal: 'Spawn a wave-clear reward pickup or chest that lets the player choose 1 stat or weapon modifier before the next round.',
          doneWhen: 'Clearing a wave spawns the reward prompt, picking an upgrade immediately modifies player stats, and only 1 choice can be claimed per round.',
          inScope: [
            'Reward pickup/chest spawn on wave clear and 3-choice upgrade selection for $clean',
            'Immediate stat/weapon modifier application and HUD stat pop feedback',
          ],
          outOfScope: [
            '100-item meta-unlock encyclopedia and reroll currency shops',
          ],
          tuningParams: const [
            'upgradeChoicesCount: 3 options',
            'statBuffMultiplier: 1.20 x',
            'pickupMagnetRadius: 3.5 m',
          ],
          edgeCases: const [
            '[SINGLE CLAIM GUARD] Despawn remaining reward options immediately after 1 upgrade is selected',
            '[STAT STACK CLAMP] Clamp fire-rate and speed multipliers so stacked upgrades never divide by zero',
          ],
          cp1Title: '$clean Reward Spawn & Stat Modifier',
          cp1Playtest: 'Clear the test wave and pick 1 upgrade -> player stat increases by statBuffMultiplier and remaining choices despawn.',
          cp1Tasks: [
            'Spawn wave-clear reward trigger and present upgradeChoicesCount options for $clean (2h)',
            'Apply selected statBuffMultiplier to active player stats and despawn unchosen options (2h)',
          ],
          cp2Title: '$clean Pickup Feel & Stack Clamp',
          cp2Playtest: 'Stack multiple upgrades in a row -> verify HUD stat callout chime and clamped max fire-rate/speed.',
          cp2Tasks: [
            'Hook up reward chest/pickup VFX, selection chime, and HUD buff badge (1h)',
            'Enforce single-claim lock and stat multiplier safety clamps (1h)',
          ],
        );

      case 'reset':
        return MechanicArchetypeProfile(
          category: 'reset',
          goal: 'Clear leftover projectiles and enemies on round end or player death, advance the wave counter, and spawn the next wave or restart cleanly.',
          doneWhen: 'Finishing a wave or dying resets arena state in under 1 second with zero orphaned actors or duplicated timers.',
          inScope: [
            'Round-end / player-death state check, arena actor cleanup, and wave counter increment for $clean',
            'Next-wave spawn trigger and instant 1-button run restart flow',
          ],
          outOfScope: [
            'Online leaderboard replay uploads and cinematic post-match cutscenes',
          ],
          tuningParams: const [
            'nextWaveDelaySec: 2.5 s',
            'enemyCountScale: 1.25 x',
            'respawnInvulnSec: 1.0 s',
          ],
          edgeCases: const [
            '[ORPHAN ACTOR CLEANUP] Destroy all active enemy projectiles and hazards before spawning the next round',
            '[DOUBLE TRIGGER GUARD] Ensure simultaneous last-enemy kill and player death resolves deterministically without double-spawning waves',
          ],
          cp1Title: '$clean Wave Transition & Run Restart',
          cp1Playtest: 'Clear the final enemy or trigger player death -> leftover projectiles clear, wave counter increments (or resets to Round 1), and next wave spawns after nextWaveDelaySec.',
          cp1Tasks: [
            'Implement wave-clear / death state transition and arena cleanup for $clean (2h)',
            'Wire wave counter increment, enemyCountScale spawn math, and instant restart reset (2h)',
          ],
          cp2Title: '$clean Banner Cues & Cleanup Guards',
          cp2Playtest: 'Trigger simultaneous kill/death edge case and spam restart -> verify zero duplicate wave spawns and clean HUD reset.',
          cp2Tasks: [
            'Hook up Round Clear / Try Again banner and audio stinger for $clean (1h)',
            'Enforce orphan projectile cleanup and double-trigger lock (1h)',
          ],
        );

      default:
        final cleanBeatDesc = (beatDescription ?? '').trim();
        final isCircularDesc =
            cleanBeatDesc.toLowerCase().startsWith('execute ');
        final descSuffix =
            (cleanBeatDesc.isNotEmpty && !isCircularDesc)
                ? ' ($cleanBeatDesc)'
                : '';
        return MechanicArchetypeProfile(
          category: 'core',
          goal: 'Build playable $clean input handling, active state logic, and immediate on-screen player feedback$descSuffix.',
          doneWhen: 'Player triggers $clean in the arena and sees immediate movement/combat state response and HUD/audio confirmation.',
          inScope: [
            'Core player input, state transition logic, and active execution for $clean',
            'Immediate on-screen visual/audio feedback and clean transition to next beat',
          ],
          outOfScope: [
            'Final production art shaders and meta-progression unlocks for $clean',
          ],
          tuningParams: const [
            'actionResponseWindow: 0.10 s',
            'stateCooldownSec: 0.25 s',
          ],
          edgeCases: const [
            '[INPUT GUARD] Rapid repeated inputs during active state transition cleanly without state lock',
          ],
          cp1Title: '$clean Core State & Controls',
          cp1Playtest: 'Trigger $clean in the test arena -> player action executes within actionResponseWindow with visible state change and HUD/audio feedback.',
          cp1Tasks: [
            'Implement player input trigger and state logic for $clean (2h)',
            'Apply actionResponseWindow timing and stateCooldownSec recovery (1h)',
          ],
          cp2Title: '$clean Visual/Audio Cues & Guardrails',
          cp2Playtest: 'Spam input during $clean transition -> feedback plays cleanly and state never locks up.',
          cp2Tasks: [
            'Hook up immediate visual indicator and audio cue for $clean (1h)',
            'Enforce rapid-input state guard and clean reset on round restart (1h)',
          ],
        );
    }
  }
}

/// Resolves and caches the structured Parent Task metadata (`numLabel`, `layerTag`,
/// `cleanTitle`, `durationChip`, `whereLocation`, `engineLabel`) and ensures each Parent Task has
/// 6 checkable `How-To` sub-steps (`Subtask.children`) with automatic rollup and engine-aware code formulas.
class TaskHowToBlueprint {
  final String numLabel;      // "01", "02", ...
  final String layerTag;      // "INPUT", "PHYSICS", "STATE", "FEEL", "UI"
  final String cleanTitle;    // Task title without trailing "(2h)"
  final String durationChip;  // Extracted "2h" or "1h"
  final String whereLocation; // e.g. "Script: PlayerController._physics_process(delta)"
  final String engineLabel;   // "GODOT 4", "UNITY C#", "UNREAL 5"
  final List<TaskHowToSubStep> subSteps;

  const TaskHowToBlueprint({
    required this.numLabel,
    required this.layerTag,
    required this.cleanTitle,
    required this.durationChip,
    required this.whereLocation,
    required this.engineLabel,
    required this.subSteps,
  });

  static final RegExp _trailingDurationRe =
      RegExp(r'\s*\(([\d\.]+\s*[hm])\)\s*$', caseSensitive: false);
  static final RegExp _anyDurationTagRe =
      RegExp(r'\s*\(([\d\.]+\s*[hm])\)', caseSensitive: false);
  static final RegExp _leadingTagRe = RegExp(
    r'^\[(?:PREREQ|BUILD|HOOK|TEST|INPUT|STATE|PHYSICS|FEEL|UI)\]\s*',
    caseSensitive: false,
  );
  static final RegExp _identifierWordRegex = RegExp(r'[A-Za-z0-9]+');
  static final RegExp _clauseSplitRegex = RegExp(
    r'\s*(?:,|;|->|\+|\band\b|\bthen\b|&)\s*',
    caseSensitive: false,
  );
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _nonLowerAlnumRegex = RegExp(r'[^a-z0-9]+');
  static final RegExp _trimUnderscoresRegex = RegExp(r'^_+|_+$');
  static final RegExp _nonIdentCharRegex = RegExp(r'[^a-zA-Z0-9_]');
  static final RegExp _leadingBracketTagRegex = RegExp(r'^\[[^\]]+\]\s*');
  static final RegExp _bracketTagCaptureRegex = RegExp(r'^\[([^\]]+)\]');
  static final RegExp _stepHeaderPrefixRegex =
      RegExp(r'^STEP\s+\d+\.\d+\s*·\s*', caseSensitive: false);

  /// Concise 3–4 word task title for the Left Outliner (condensing legacy verbose task sentences).
  String get shortTaskTitle => formatConciseTaskTitle(cleanTitle);

  static String formatConciseTaskTitle(String rawCleanTitle) {
    var text = rawCleanTitle.replaceAll(_anyDurationTagRe, '').trim();
    final lower = text.toLowerCase();
    if (lower.startsWith('create actor/node structure') ||
        lower.startsWith('create actor / node structure')) {
      return 'Actor & Base Properties';
    }
    if (lower.startsWith('implement core state transitions')) {
      return 'State Logic & Player Input';
    }
    if (lower.startsWith('hook visual/audio feedback cues') ||
        lower.startsWith('hook up visual/audio feedback cues')) {
      return 'Feedback Cues & State Guard';
    }
    if (lower.startsWith('create camera rig and hud')) {
      return 'Camera Rig & HUD Container';
    }
    if (lower.startsWith('implement camera follow smoothing')) {
      return 'Follow Smoothing & Bound Clamp';
    }
    if (lower.startsWith('wire active state readout')) {
      return 'State Readout & Viewport Test';
    }
    // Strip redundant trailing " for <Beat/Feature Name>"
    text = text.replaceFirst(
      RegExp(r'\s+for\s+[A-Z][\w\s&\-\/]*$'),
      '',
    );
    if (text.length > 32) {
      text = text
          .replaceFirst(
            RegExp(
              r'^(?:Create|Implement|Hook up|Hook|Wire|Subscribe|Enforce|Spawn|Apply|Bind)\s+',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(' and ', ' & ')
          .trim();
      if (text.isNotEmpty) {
        text = text[0].toUpperCase() + text.substring(1);
      }
    }
    return text.isEmpty ? rawCleanTitle : text;
  }

  /// Lightweight LRU-style memoization cache for `TaskHowToBlueprint.resolve`
  /// so Outliner ETA rollups and Active Step Workspace renders do not re-run regexes
  /// and object allocations multiple times per frame.
  static final Map<String, ({int signature, TaskHowToBlueprint blueprint})>
      _blueprintCache = {};

  static void clearCache() => _blueprintCache.clear();

  static String detectEngineLabel(String? engineHint) {
    final lower = (engineHint ?? '').toLowerCase();
    if (lower.contains('unity') || lower.contains('c#')) {
      return 'UNITY C#';
    }
    if (lower.contains('unreal') || lower.contains('ue5') || lower.contains('c++')) {
      return 'UNREAL 5';
    }
    return 'GODOT 4';
  }

  static String extractCleanTitle(String rawText) {
    var cleaned = rawText.replaceAll(_trailingDurationRe, '').trim();
    cleaned = cleaned.replaceFirst(_leadingTagRe, '').trim();
    return cleaned.isEmpty ? rawText.trim() : cleaned;
  }

  static String extractDurationChip(String rawText) {
    final m = _trailingDurationRe.firstMatch(rawText);
    if (m != null && m.group(1) != null) {
      return m.group(1)!.replaceAll(' ', '');
    }
    return '3h';
  }

  /// Base effort weights (in minutes) across the 6 standard steps of a 3.0h (180m) task:
  /// Step 1: 15m (Create / Open Asset)
  /// Step 2: 25m (Add Components / Hierarchy)
  /// Step 3: 15m (Place in Scene / Level)
  /// Step 4: 25m (Expose Tuning Variables)
  /// Step 5: 65m (Write Core Logic — ~1.1h)
  /// Step 6: 35m (Add Guard & Playtest)
  static const List<int> baseStepWeights180 = <int>[15, 25, 15, 25, 65, 35];

  static int extractTaskTotalMinutes(String rawText) {
    final m = _trailingDurationRe.firstMatch(rawText);
    if (m != null && m.group(1) != null) {
      final parsed = DurationHelper.parseToMinutes(m.group(1)!);
      if (parsed > 0) return parsed;
    }
    return 180; // Default 3h = 180m
  }

  static List<int> computeWeightedStepMinutes(int totalSteps, int totalTaskMinutes) {
    if (totalSteps <= 0) return const <int>[];
    final safeTotal = totalTaskMinutes > 0 ? totalTaskMinutes : 180;
    if (totalSteps == 6 && safeTotal == 180) {
      return baseStepWeights180;
    }
    final rawWeights = List<int>.generate(
      totalSteps,
      (idx) => idx < baseStepWeights180.length ? baseStepWeights180[idx] : 20,
    );
    final weightSum = rawWeights.fold<int>(0, (sum, w) => sum + w);
    if (weightSum <= 0) {
      final each = (safeTotal / totalSteps).round();
      return List<int>.filled(totalSteps, each > 0 ? each : 5);
    }
    final scaled = <int>[];
    int allocated = 0;
    for (int i = 0; i < totalSteps; i++) {
      if (i == totalSteps - 1) {
        final rem = safeTotal - allocated;
        scaled.add(rem > 0 ? rem : 5);
      } else {
        final mins = ((rawWeights[i] / weightSum) * safeTotal).round();
        final clamped = mins > 0 ? mins : 5;
        scaled.add(clamped);
        allocated += clamped;
      }
    }
    return scaled;
  }

  static String formatStepEtaLabel(int minutes) {
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes / 60.0;
    if ((hours - hours.roundToDouble()).abs() < 0.05) {
      return '${hours.round()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }

  static String formatRemainingHoursShort(int minutes) {
    if (minutes <= 0) return '0h';
    final hours = minutes / 60.0;
    if ((hours - hours.roundToDouble()).abs() < 0.05) {
      return '${hours.round()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }

  int get totalTaskMinutes =>
      subSteps.fold<int>(0, (sum, s) => sum + s.estimatedMinutes);

  int get remainingTaskMinutes => subSteps.fold<int>(
        0,
        (sum, s) => sum + (s.subtask.completed ? 0 : s.estimatedMinutes),
      );

  static String inferLayerTag(String rawText, int taskIdx) {
    final lower = rawText.toLowerCase();
    if (lower.contains('input') ||
        lower.contains('control') ||
        lower.contains('key') ||
        lower.contains('mouse') ||
        lower.contains('aim') ||
        lower.contains('strafe')) {
      return 'INPUT';
    }
    if (lower.contains('physic') ||
        lower.contains('velocity') ||
        lower.contains('force') ||
        lower.contains('speed') ||
        lower.contains('gravity') ||
        lower.contains('collision') ||
        lower.contains('raycast') ||
        lower.contains('movement')) {
      return 'PHYSICS';
    }
    if (lower.contains('visual') ||
        lower.contains('audio') ||
        lower.contains('sfx') ||
        lower.contains('vfx') ||
        lower.contains('cue') ||
        lower.contains('camera') ||
        lower.contains('fov') ||
        lower.contains('feel') ||
        lower.contains('feedback') ||
        lower.contains('anim')) {
      return 'FEEL';
    }
    if (lower.contains('hud') ||
        lower.contains('ui') ||
        lower.contains('menu') ||
        lower.contains('indicator') ||
        lower.contains('readout') ||
        lower.contains('badge')) {
      return 'UI / HUD';
    }
    return taskIdx == 0 ? 'STATE' : (taskIdx == 1 ? 'FEEL' : 'LOGIC');
  }

  static String inferWhereLocation(
    String cleanTitle,
    String layerTag, {
    String engineLabel = 'GODOT 4',
  }) {
    if (engineLabel == 'UNITY C#') {
      switch (layerTag) {
        case 'INPUT':
          return 'MonoBehaviour: PlayerInputController.Update()';
        case 'PHYSICS':
          return 'MonoBehaviour: MechanicController.FixedUpdate()';
        case 'FEEL':
          return 'MonoBehaviour: FeedbackPresenter.LateUpdate()';
        case 'UI / HUD':
          return 'MonoBehaviour: GameHudOverlay.RefreshReadout()';
        default:
          return 'MonoBehaviour: CoreLoopStateController.FixedUpdate()';
      }
    }
    if (engineLabel == 'UNREAL 5') {
      switch (layerTag) {
        case 'INPUT':
          return 'ActorComponent: UPlayerInputComp::SetupPlayerInputComponent()';
        case 'PHYSICS':
          return 'ActorComponent: UMechanicComponent::TickComponent(DeltaTime)';
        case 'FEEL':
          return 'ActorComponent: UFeedbackPresenter::TriggerFeelCue()';
        case 'UI / HUD':
          return 'UserWidget: UGameHudWidget::UpdateStateReadout()';
        default:
          return 'ActorComponent: UCoreLoopStateComp::TickComponent(DeltaTime)';
      }
    }
    switch (layerTag) {
      case 'INPUT':
        return 'Script: PlayerController._unhandled_input(event)';
      case 'PHYSICS':
        return 'Script: MechanicController._physics_process(delta)';
      case 'FEEL':
        return 'Scene: FeedbackPresenter & CameraController._process(delta)';
      case 'UI / HUD':
        return 'Scene: GameHudOverlay.update_state_readout()';
      default:
        return 'Script: CoreLoopStateController._physics_process(delta)';
    }
  }

  static ({String pascalName, String snakeName}) deriveConcreteAssetName(
    String rawText,
  ) {
    final clean =
        extractCleanTitle(rawText).replaceAll(_anyDurationTagRe, ' ').trim();
    final lowerClean = clean.toLowerCase();
    if (lowerClean.contains('loop resolution') ||
        lowerClean.contains('round clear & reset') ||
        lowerClean.contains('next-wave loop reset') ||
        lowerClean.contains('wave-clear / death state transition')) {
      return (
        pascalName: 'WaveResetManager',
        snakeName: 'wave_reset_manager',
      );
    }
    if (lowerClean.contains('active gameplay beat') ||
        lowerClean.contains('arena movement & combat') ||
        lowerClean.contains('primary combat & timing') ||
        lowerClean.contains('core mechanic escalation') ||
        lowerClean.contains('primary skill execution')) {
      return (
        pascalName: 'PlayerCombatActor',
        snakeName: 'player_combat_actor',
      );
    }
    if (lowerClean.contains('resource & upgrade choice') ||
        lowerClean.contains('loot & upgrade choice') ||
        lowerClean.contains('room clear & upgrade') ||
        lowerClean.contains('wave-clear reward trigger')) {
      return (
        pascalName: 'UpgradeChestActor',
        snakeName: 'upgrade_chest_actor',
      );
    }
    if (lowerClean.contains('prep & loadout') ||
        lowerClean.contains('staging & loadout') ||
        lowerClean.contains('staging pedestal')) {
      return (
        pascalName: 'LoadoutPedestalActor',
        snakeName: 'loadout_pedestal_actor',
      );
    }
    const stopWords = <String>{
      'create',
      'build',
      'implement',
      'implementation',
      'playtest',
      'add',
      'wire',
      'hook',
      'up',
      'setup',
      'set',
      'bind',
      'apply',
      'enforce',
      'verify',
      'test',
      'the',
      'and',
      'for',
      'with',
      'in',
      'on',
      'to',
      'of',
      'a',
      'an',
      'core',
      'state',
      'player',
      'interaction',
      'mechanics',
      'controls',
      'logic',
      'pass',
      'stage',
      'structure',
      'base',
      'properties',
      'actor',
      'node',
    };
    final words = _identifierWordRegex
        .allMatches(clean)
        .map((m) => m.group(0)!)
        .where((w) => w.length > 1 && !stopWords.contains(w.toLowerCase()))
        .toList();
    final chosen = words.isNotEmpty
        ? words.take(3).toList()
        : <String>['Grid', 'Tile', 'Actor'];
    if (!chosen.any((w) =>
        w.toLowerCase() == 'actor' ||
        w.toLowerCase() == 'controller' ||
        w.toLowerCase() == 'node' ||
        w.toLowerCase() == 'manager')) {
      chosen.add('Actor');
    }
    final pascal = chosen
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join();
    final snake = chosen.map((w) => w.toLowerCase()).join('_');
    return (pascalName: pascal, snakeName: snake);
  }

  static int _computeTaskSignature({
    required Subtask parentTask,
    required FeatureStateNode checkpointNode,
    required String? engineHint,
    required bool unrealCppMode,
  }) {
    var hash = Object.hash(
      parentTask.id,
      parentTask.text,
      parentTask.completed,
      parentTask.children.length,
      checkpointNode.id,
      checkpointNode.name,
      checkpointNode.trigger,
      checkpointNode.tuningParams.join('|'),
      checkpointNode.edgeCases.join('|'),
      engineHint ?? '',
      unrealCppMode,
    );
    for (final c in parentTask.children) {
      hash = Object.hash(
        hash,
        c.id,
        c.text,
        c.completed,
        c.specNotes,
        c.codeSnippet,
        c.codeTargetFile,
      );
    }
    return hash;
  }

  static List<String> extractActionClauses(String cleanTitle) {
    final rawParts = cleanTitle.split(_clauseSplitRegex);
    final clauses = <String>[];
    for (final part in rawParts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final wordCount = trimmed.split(_whitespaceRegex).length;
      if (wordCount >= 2 || clauses.isEmpty) {
        clauses.add(trimmed);
      } else if (clauses.isNotEmpty) {
        clauses[clauses.length - 1] = '${clauses.last} and $trimmed';
      }
    }
    return clauses.isEmpty ? <String>[cleanTitle] : clauses;
  }

  /// Formats a crisp 2–4 word `Guard: ...` title for the Outliner and Step Header
  /// (e.g., `[EMPTY LOADOUT GUARD] Require at least 1...` -> `Guard: Empty Loadout`)
  /// so full-sentence guard rules never overflow or wrap in the Outliner.
  static String _formatConciseGuardShortTitle(
    String rawGuard,
    String fallbackShortTitle,
  ) {
    final tagMatch = _bracketTagCaptureRegex.firstMatch(rawGuard.trim());
    if (tagMatch != null) {
      final rawTag = tagMatch.group(1)!.trim();
      final upperTag = rawTag.toUpperCase();
      const genericTags = <String>{
        'GUARD',
        'STATE GUARD',
        'INPUT GUARD',
        'PLAYTEST GUARD',
        'SIMULATION GUARD',
      };
      if (!genericTags.contains(upperTag)) {
        final cleanedTag = rawTag
            .replaceFirst(RegExp(r'\s+GUARD$', caseSensitive: false), '')
            .trim();
        if (cleanedTag.isNotEmpty) {
          final titleCased = cleanedTag
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .map((w) {
                if (w.toUpperCase() == 'LOS' ||
                    w.toUpperCase() == 'HUD' ||
                    w.toUpperCase() == 'UI') {
                  return w.toUpperCase();
                }
                return w
                    .split('-')
                    .map(
                      (p) => p.isEmpty
                          ? p
                          : p[0].toUpperCase() + p.substring(1).toLowerCase(),
                    )
                    .join('-');
              })
              .join(' ');
          return 'Guard: $titleCased';
        }
      }
    }
    return fallbackShortTitle;
  }

  /// Derives concrete guard variable/condition names and natural English step fields
  /// from a checkpoint edge-case guard string (eliminating raw `[... GUARD]` bracket tags
  /// in prose and generic `ValidateGuard_N()` placeholders in code).
  static ({
    String shortTitle,
    List<String> highlightTokens,
    String instruction,
    String explain,
    String code,
    String verify,
    String pitfall,
  }) deriveConcreteGuardStepSpec({
    required String rawGuard,
    required String targetAssetName,
    required String engineLabel,
    required bool unrealCppMode,
    required String primaryVarName,
  }) {
    final shortGuard =
        rawGuard.replaceFirst(_leadingBracketTagRegex, '').trim();
    final lower = shortGuard.toLowerCase();

    // 1. Stack / Cap / Max Limit Guard
    if (lower.contains('stack') ||
        (lower.contains('cap') && lower.contains('limit')) ||
        lower.contains('max capacity')) {
      final code = engineLabel == 'UNREAL 5'
          ? (unrealCppMode
              ? 'if (currentBuffStacks >= maxBuffStacks) return;\ncurrentBuffStacks++;'
              : '[Branch: currentBuffStacks < maxBuffStacks]\n   └──► (True)  ──► [Increment currentBuffStacks] ──► [Apply Stat Buff ($primaryVarName)]\n   └──► (False) ──► [Return / Skip Buff]')
          : (engineLabel == 'UNITY C#'
              ? 'if (currentBuffStacks >= maxBuffStacks) return;\ncurrentBuffStacks++;'
              : 'if current_buff_stacks >= max_buff_stacks:\n    return\ncurrent_buff_stacks += 1');
      final condToken = engineLabel == 'GODOT 4'
          ? 'current_buff_stacks < max_buff_stacks'
          : 'currentBuffStacks < maxBuffStacks';
      return (
        shortTitle: _formatConciseGuardShortTitle(
          rawGuard,
          'Guard: Max Stack Cap',
        ),
        highlightTokens: const [
          'currentBuffStacks < maxBuffStacks',
          'currentBuffStacks >= maxBuffStacks',
          'current_buff_stacks < max_buff_stacks',
          'current_buff_stacks >= max_buff_stacks',
          'currentBuffStacks',
          'maxBuffStacks',
          'current_buff_stacks',
          'max_buff_stacks',
        ],
        instruction:
            'In $targetAssetName, check $condToken before applying the effect so stacks cannot exceed the cap.',
        explain:
            'Prevents runaway stat scaling when the player triggers the same upgrade or effect repeatedly.',
        code: code,
        verify:
            'Trigger the effect repeatedly in Play mode and confirm $condToken stops additional stacks once the cap is reached.',
        pitfall:
            'Check $condToken before modifying player attributes so capped picks exit cleanly.',
      );
    }

    // 2. Despawn / Cleanup / Clear Unchosen Widgets Guard
    if (lower.contains('despawn') ||
        lower.contains('unchosen') ||
        lower.contains('cleanup') ||
        lower.contains('orphan')) {
      final code = engineLabel == 'UNREAL 5'
          ? (unrealCppMode
              ? 'if (!bCardsActive) return;\nbCardsActive = false;\nDespawnUnchosenCards();'
              : '[Branch: bCardsActive]\n   └──► (True) ──► [Set bCardsActive = false]\n                   [Call DespawnUnchosenCards()]')
          : (engineLabel == 'UNITY C#'
              ? 'if (!bCardsActive) return;\nbCardsActive = false;\nDespawnUnchosenCards();'
              : 'if not cards_active:\n    return\ncards_active = false\ndespawn_unchosen_cards()');
      final fnToken = engineLabel == 'GODOT 4'
          ? 'despawn_unchosen_cards()'
          : 'DespawnUnchosenCards()';
      final flagToken =
          engineLabel == 'GODOT 4' ? 'cards_active' : 'bCardsActive';
      return (
        shortTitle: _formatConciseGuardShortTitle(
          rawGuard,
          'Guard: Clear Unchosen Cards',
        ),
        highlightTokens: const [
          'DespawnUnchosenCards()',
          'despawn_unchosen_cards()',
          'bCardsActive = false',
          'cards_active = false',
          'bCardsActive',
          'cards_active',
        ],
        instruction:
            'After applying the selection in $targetAssetName, check $flagToken and call $fnToken so remaining unchosen cards are removed immediately.',
        explain:
            'Prevents leftover upgrade cards from lingering on screen or being clicked a second time after a choice is made.',
        code: code,
        verify:
            'Select 1 of the spawned upgrade cards in Play mode and confirm $fnToken removes all remaining cards immediately.',
        pitfall:
            'Set $flagToken = false before calling $fnToken so rapid clicks during close animations are ignored.',
      );
    }

    // 3.Occupied / Solid Tile / Grid Boundary Guard
    if (lower.contains('tile') ||
        lower.contains('occupied') ||
        lower.contains('solid') ||
        lower.contains('boundary') ||
        lower.contains('bounds')) {
      final code = engineLabel == 'UNREAL 5'
          ? (unrealCppMode
              ? 'if (IsTileBlocked(targetCell)) return;\nStepTowardCell(targetCell, $primaryVarName);'
              : '[Branch: NOT IsTileBlocked(targetCell)]\n   └──► (True) ──► [Step Toward targetCell ($primaryVarName)]')
          : (engineLabel == 'UNITY C#'
              ? 'if (IsTileBlocked(targetCell)) return;\nStepTowardCell(targetCell, $primaryVarName);'
              : 'if is_tile_blocked(target_cell):\n    return\nstep_toward_cell(target_cell, $primaryVarName)');
      final fnToken = engineLabel == 'GODOT 4'
          ? 'is_tile_blocked(target_cell)'
          : 'IsTileBlocked(targetCell)';
      return (
        shortTitle: _formatConciseGuardShortTitle(
          rawGuard,
          'Guard: Blocked Tile Check',
        ),
        highlightTokens: const [
          'NOT IsTileBlocked(targetCell)',
          'IsTileBlocked(targetCell)',
          'is_tile_blocked(target_cell)',
        ],
        instruction:
            'Before stepping $targetAssetName into the target cell, check $fnToken so movement into occupied or solid tiles is blocked.',
        explain:
            'Prevents $targetAssetName from clipping into walls or overlapping occupied grid cells.',
        code: code,
        verify:
            'Attempt to move into an occupied or solid cell in Play mode and confirm $fnToken blocks the move cleanly.',
        pitfall:
            'Check $fnToken before starting interpolation so blocked moves never shift the actor position.',
      );
    }

    // 4. Default / Lock Selection / Duplicate Trigger / Cooldown Guard
    final isResetGuard = lower.contains('reset') || lower.contains('restart');
    final flagName = engineLabel == 'GODOT 4'
        ? (isResetGuard ? 'reset_in_progress' : 'selection_locked')
        : (isResetGuard ? 'bResetInProgress' : 'bSelectionLocked');
    final notFlagExpr = engineLabel == 'UNREAL 5' && !unrealCppMode
        ? 'NOT $flagName'
        : (engineLabel == 'GODOT 4' ? 'not $flagName' : '!$flagName');
    final code = engineLabel == 'UNREAL 5'
        ? (unrealCppMode
            ? 'if ($flagName) return;\n$flagName = true;'
            : '[Branch: $notFlagExpr]\n   └──► (True) ──► [Set $flagName = true]\n                   [Apply Action ($primaryVarName)]')
        : (engineLabel == 'UNITY C#'
            ? 'if ($flagName) return;\n$flagName = true;'
            : 'if $flagName:\n    return\n$flagName = true');
    return (
      shortTitle: _formatConciseGuardShortTitle(
        rawGuard,
        isResetGuard
            ? 'Guard: Reset Lock Check'
            : 'Guard: Duplicate Trigger Lock',
      ),
      highlightTokens: [
        'NOT $flagName',
        '!$flagName',
        'not $flagName',
        '$flagName = true',
        flagName,
      ],
      instruction:
          'At the start of your trigger event in $targetAssetName, check $notFlagExpr and set $flagName = true on the first activation.',
      explain:
          'Enforces "$shortGuard" so rapid double-clicks or duplicate triggers cannot fire the action twice.',
      code: code,
      verify:
          'Trigger the action rapidly in Play mode and confirm $flagName blocks duplicate activations so only 1 trigger runs.',
      pitfall:
          'Set $flagName = true immediately on the first frame before running any animation or state delay.',
    );
  }

  /// Returns all concrete guard highlight tokens across `edgeItems` for semantic syntax highlighting.
  static List<String> extractGuardHighlightTokens(List<String> edgeItems) {
    final tokens = <String>{
      'currentBuffStacks < maxBuffStacks',
      'currentBuffStacks >= maxBuffStacks',
      'current_buff_stacks < max_buff_stacks',
      'current_buff_stacks >= max_buff_stacks',
      'currentBuffStacks',
      'maxBuffStacks',
      'current_buff_stacks',
      'max_buff_stacks',
      'DespawnUnchosenCards()',
      'despawn_unchosen_cards()',
      'bCardsActive = false',
      'cards_active = false',
      'bCardsActive',
      'cards_active',
      'NOT IsTileBlocked(targetCell)',
      'IsTileBlocked(targetCell)',
      'is_tile_blocked(target_cell)',
      'NOT bSelectionLocked',
      '!bSelectionLocked',
      'not selection_locked',
      'bSelectionLocked = true',
      'selection_locked = true',
      'bSelectionLocked',
      'selection_locked',
      'NOT bResetInProgress',
      '!bResetInProgress',
      'bResetInProgress = true',
      'bResetInProgress',
      'reset_in_progress',
    };
    final bracketPrefix = RegExp(r'^\[[^\]]+\]\s*');
    for (final rawGuard in edgeItems) {
      final trimmed = rawGuard.trim();
      if (trimmed.isNotEmpty) {
        tokens.add(trimmed);
        final stripped = trimmed.replaceFirst(bracketPrefix, '').trim();
        if (stripped.length >= 6) {
          tokens.add(stripped);
        }
      }
    }
    return tokens.toList();
  }

  /// Dynamically resolves `parentTask.children` into `1..N` atomic, zero-assumption "LEGO / IKEA" sub-steps
  /// (`Step X.1` through `Step X.N`) adapted to `engineHint` (`GODOT 4`, `UNITY C#`, `UNREAL 5`),
  /// scaling down to 3–4 steps for compact feel/guard tasks or up to 10+ steps for multi-clause,
  /// multi-parameter, and multi-guard mechanics, while supporting Unreal 5 `Blueprint | C++` toggle (`unrealCppMode`).
  static TaskHowToBlueprint resolve({
    required Subtask parentTask,
    required int taskIndex,
    required FeatureStateNode checkpointNode,
    String? engineHint,
    bool unrealCppMode = false,
  }) {
    final cacheKey = '${checkpointNode.id}_${parentTask.id}_$taskIndex';
    if (parentTask.children.isNotEmpty) {
      final sig = _computeTaskSignature(
        parentTask: parentTask,
        checkpointNode: checkpointNode,
        engineHint: engineHint,
        unrealCppMode: unrealCppMode,
      );
      final cached = _blueprintCache[cacheKey];
      if (cached != null && cached.signature == sig) {
        return cached.blueprint;
      }
    }

    final taskNum = taskIndex + 1;
    final numLabel = taskNum.toString().padLeft(2, '0');
    final cleanTitle = extractCleanTitle(parentTask.text);
    final durationChip = extractDurationChip(parentTask.text);
    final layerTag = inferLayerTag(parentTask.text, taskIndex);
    final engineLabel = detectEngineLabel(engineHint);
    final whereLocation = inferWhereLocation(
      cleanTitle,
      layerTag,
      engineLabel: engineLabel,
    );

    final assetSource = checkpointNode.checklist.isNotEmpty
        ? checkpointNode.checklist.first.text
        : cleanTitle;
    final asset = deriveConcreteAssetName('$assetSource ${checkpointNode.name}');
    final pascalAsset = asset.pascalName;
    final snakeAsset = asset.snakeName;
    final bpAsset = 'BP_$pascalAsset';
    final cppClass = 'A$pascalAsset';

    final cpArchetype =
        MechanicArchetypeProfile.fromFeatureTitle(checkpointNode.cleanStageTitle);
    final hasLegacyEconomyMismatch = cpArchetype.category != 'economy' &&
        checkpointNode.tuningParams.isNotEmpty &&
        checkpointNode.tuningParams.first.contains('transactionCostBase: 25 gold');
    final effectiveTuningParams = hasLegacyEconomyMismatch
        ? cpArchetype.tuningParams
        : checkpointNode.tuningParams;
    final effectiveEdgeCases = hasLegacyEconomyMismatch
        ? cpArchetype.edgeCases
        : checkpointNode.edgeCases;

    final primaryVar = effectiveTuningParams.isNotEmpty
        ? effectiveTuningParams[taskIndex % effectiveTuningParams.length]
        : 'responseTime: 0.12 s';
    final primaryVarName = primaryVar.split(':').first.trim();
    final primaryGuard = effectiveEdgeCases.isNotEmpty
        ? effectiveEdgeCases[taskIndex % effectiveEdgeCases.length]
        : '[STATE GUARD] Prevent duplicate trigger while active';
    final isFoundationTask = taskIndex == 0;
    final isStateLogicTask = taskIndex == 1;

    ({
      String stepHeader,
      String shortTitle,
      String instruction,
      String verify,
      String path,
      String code,
      String explain,
    }) buildAtomicStepSpec(int stepIdx) {
      // =======================================================================
      // UNREAL 5 (Supports both Blueprint mode & C++ mode)
      // =======================================================================
      if (engineLabel == 'UNREAL 5') {
        if (unrealCppMode) {
          switch (stepIdx) {
            case 0:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.1 · CREATE $cppClass C++ CLASS'
                    : (isStateLogicTask
                        ? 'STEP $taskNum.1 · DEFINE STATE ENUM & PROPERTIES IN $pascalAsset.h'
                        : 'STEP $taskNum.1 · BIND INTERACTION INPUT IN $pascalAsset.cpp'),
                shortTitle: isFoundationTask
                    ? 'Create $cppClass C++ Class'
                    : (isStateLogicTask
                        ? 'Define State Enum & Properties'
                        : 'Bind Player Interaction Input'),
                instruction: isFoundationTask
                    ? 'In the Unreal Editor top menu, click Tools → New C++ Class... → choose Actor as the parent class → name it $pascalAsset and click Create Class.'
                    : (isStateLogicTask
                        ? 'Open $pascalAsset.h and declare the state enum and active state properties for "$cleanTitle" on $cppClass.'
                        : 'Open $pascalAsset.cpp and bind the player interaction action / trace trigger for "$cleanTitle".'),
                verify: isFoundationTask
                    ? 'Visual Studio / Rider opens with $pascalAsset.h and $pascalAsset.cpp generated.'
                    : '$pascalAsset.h and $pascalAsset.cpp compile cleanly in your IDE.',
                path: 'Source/Project/$pascalAsset.h',
                code: '#pragma once\n#include "CoreMinimal.h"\n#include "GameFramework/Actor.h"\n#include "$pascalAsset.generated.h"\n\nUCLASS()\nclass $cppClass : public AActor {\n  GENERATED_BODY()\npublic:\n  $cppClass();\n  EMechanicState ActiveState = EMechanicState::Idle;\n};',
                explain: 'An AActor C++ class is the foundation object you can spawn or place inside a level.',
              );
            case 1:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.2 · ATTACH MESH & COLLISION SUBOBJECTS'
                    : (isStateLogicTask
                        ? 'STEP $taskNum.2 · BUILD SETSTATE() TRANSITION FUNCTION'
                        : 'STEP $taskNum.2 · CAST INTERACTION LINETRACE IN C++'),
                shortTitle: isFoundationTask
                    ? 'Create Mesh & Collision Subobjects'
                    : (isStateLogicTask
                        ? 'Build State Transition Function'
                        : 'Cast Interaction LineTrace'),
                instruction: isFoundationTask
                    ? 'Inside the $cppClass() constructor in $pascalAsset.cpp, instantiate a UStaticMeshComponent ("VisualMesh") and UBoxComponent ("InteractBox") and attach them to RootComponent.'
                    : (isStateLogicTask
                        ? 'In $pascalAsset.cpp, add a SetMechanicState(EMechanicState NewState) method that validates and updates ActiveState.'
                        : 'In $pascalAsset.cpp, run GetWorld()->LineTraceSingleByChannel from the camera view to detect $cppClass instances.'),
                verify: isFoundationTask
                    ? 'Live Coding (Ctrl+Alt+F11) compiles cleanly with VisualMesh and InteractBox attached under RootComponent.'
                    : (isStateLogicTask
                        ? 'SetMechanicState compiles cleanly and updates ActiveState when called.'
                        : 'LineTrace hits $cppClass InteractBox within interaction range.'),
                path: 'Source/Project/$pascalAsset.cpp :: $cppClass()',
                code: isFoundationTask
                    ? '$cppClass::$cppClass() {\n  RootComponent = CreateDefaultSubobject<USceneComponent>("Root");\n  VisualMesh = CreateDefaultSubobject<UStaticMeshComponent>("VisualMesh");\n  VisualMesh->SetupAttachment(RootComponent);\n  InteractBox = CreateDefaultSubobject<UBoxComponent>("InteractBox");\n  InteractBox->InitBoxExtent(FVector(50.f, 50.f, 20.f));\n  InteractBox->SetupAttachment(RootComponent);\n}'
                    : (isStateLogicTask
                        ? 'void $cppClass::SetMechanicState(EMechanicState NewState) {\n  if (ActiveState == NewState) return;\n  ActiveState = NewState;\n  OnStateChanged(ActiveState);\n}'
                        : 'FHitResult Hit;\nGetWorld()->LineTraceSingleByChannel(Hit, StartLoc, EndLoc, ECC_Visibility);\nif ($cppClass* Target = Cast<$cppClass>(Hit.GetActor())) {\n  Target->Interact();\n}'),
                explain: isFoundationTask
                    ? 'CreateDefaultSubobject constructs the visible 3D mesh and the collision sensor box inside your C++ constructor.'
                    : 'Separating state transition and raycast queries into dedicated C++ methods keeps your actor modular and easy to debug.',
              );
            case 2:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.3 · COMPILE & PLACE IN LEVEL VIEWPORT'
                    : (isStateLogicTask
                        ? 'STEP $taskNum.3 · SWAP MATERIAL / VISUAL ON STATE CHANGE'
                        : 'STEP $taskNum.3 · CALL TRIGGER ON HIT $cppClass'),
                shortTitle: isFoundationTask
                    ? 'Place $cppClass in Level'
                    : (isStateLogicTask
                        ? 'Swap Visual Material on State Change'
                        : 'Call Interact Trigger on Hit Actor'),
                instruction: isFoundationTask
                    ? 'Press Ctrl+Alt+F11 (Live Coding) to compile, then open C++ Classes in the Content Browser and drag $pascalAsset into the Level Viewport at (0, 0, 0).'
                    : (isStateLogicTask
                        ? 'Inside OnStateChanged(), update VisualMesh material parameters so each state of $cppClass is visually distinct.'
                        : 'When the trace hits $cppClass, invoke its interaction method to advance the state machine.'),
                verify:
                    '$pascalAsset updates cleanly in the Level Viewport and World Outliner.',
                path: 'Level Editor → Content Browser → C++ Classes → Viewport',
                code: isFoundationTask
                    ? 'Instance: ${pascalAsset}_0 ($cppClass)\nTransform Location: FVector(0.f, 0.f, 0.f)'
                    : 'VisualMesh->SetVectorParameterValueOnMaterials(TEXT("StateTint"), ActiveColor);',
                explain: 'Immediate visual feedback on the mesh lets playtesters see state changes without relying on debug text.',
              );
            case 3:
              return (
                stepHeader: 'STEP $taskNum.4 · EXPOSE UPROPERTY TUNING VARIABLES',
                shortTitle: isFoundationTask
                    ? 'Expose UPROPERTY $primaryVarName'
                    : (isStateLogicTask
                        ? 'Bind $primaryVarName to State Transition'
                        : 'Add Target Hover Highlight Cue'),
                instruction:
                    'In $pascalAsset.h under public:, declare $primaryVarName with UPROPERTY(EditAnywhere, BlueprintReadWrite) so designers can tune $primaryVarName in the Details panel.',
                verify:
                    'After Live Coding, selecting $cppClass in the Level shows $primaryVarName as an editable field inside the Details panel.',
                path: 'Source/Project/$pascalAsset.h (UPROPERTY)',
                code: 'UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Tuning")\nfloat $primaryVarName = 1.0f; // $primaryVar\n\nUPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="State")\nbool bIsOccupied = false;',
                explain: 'UPROPERTY(EditAnywhere) exposes a C++ variable to the Unreal Editor Details panel so you can tweak it without recompiling.',
              );
            case 4:
              return (
                stepHeader: 'STEP $taskNum.5 · IMPLEMENT OVERLAP / TICK LOGIC',
                shortTitle: isFoundationTask
                    ? 'Initialize Default Component State'
                    : (isStateLogicTask
                        ? 'Step State with Interpolation Logic'
                        : 'Connect Cooldown & Range Check'),
                instruction:
                    'In $pascalAsset.cpp, implement the trigger and state interpolation for "$cleanTitle" using FMath::FInterpConstantTo driven by $primaryVarName.',
                verify:
                    'Triggering $cppClass in Play mode updates ActiveState smoothly using $primaryVarName.',
                path: 'Source/Project/$pascalAsset.cpp :: TickComponent / Overlap',
                code: 'void $cppClass::ExecuteMechanicStep(float DeltaTime) {\n  if (bInputPressed && CanEnterState()) {\n    ActiveState = EMechanicState::Active;\n  }\n  CurrentVal = FMath::FInterpConstantTo(CurrentVal, TargetVal, DeltaTime, $primaryVarName);\n}',
                explain: 'FMath::FInterpConstantTo smoothly steps your value each frame using DeltaTime so movement speed is frame-rate independent.',
              );
            default:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.6 · COMPILE & VERIFY ACTOR IN LEVEL'
                    : (isStateLogicTask
                        ? 'STEP $taskNum.6 · ADD INVALID-STATE TRANSITION GUARD'
                        : 'STEP $taskNum.6 · PLAYTEST FULL LOOP IN VIEWPORT (ALT+P)'),
                shortTitle: isFoundationTask
                    ? 'Compile & Verify Actor in Level'
                    : (isStateLogicTask
                        ? 'Add Invalid-State Transition Guard'
                        : 'Playtest Full Loop in Viewport (Alt+P)'),
                instruction:
                    'Add a guard check at the top of your function to enforce "$primaryGuard", compile with Ctrl+Alt+F11, and press Play (Alt+P) to test in the viewport.',
                verify:
                    'Pressing Play (Alt+P) triggers "$cleanTitle" cleanly on screen and blocks duplicate triggers.',
                path: 'Main Toolbar → Live Coding (Ctrl+Alt+F11) → Play (Alt+P)',
                code: 'if (IsBoundaryBlocked() || CooldownTimer > 0.f) return; // Guard: $primaryGuard\nif (GEngine) {\n  GEngine->AddOnScreenDebugMessage(-1, 2.f, FColor::Cyan, TEXT("$cleanTitle Active!"));\n}',
                explain: 'The early-return guard prevents double-triggering or out-of-bounds states when the player spams input.',
              );
          }
        } else {
          // UNREAL 5 — Blueprint Mode (Default)
          switch (stepIdx) {
            case 0:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.1 · CREATE $bpAsset BLUEPRINT ASSET'
                    : (isStateLogicTask
                        ? 'STEP $taskNum.1 · DEFINE STATE ENUM & VARIABLES IN $bpAsset'
                        : 'STEP $taskNum.1 · BIND PLAYER INTERACTION INPUT IN $bpAsset'),
                shortTitle: isFoundationTask
                    ? 'Create $bpAsset'
                    : (isStateLogicTask
                        ? 'Define State Enum & Variables'
                        : 'Bind Player Interaction Input'),
                instruction: isFoundationTask
                    ? 'In the Content Browser (bottom panel), right-click inside /Game/Blueprints → choose Blueprint Class → click Actor, and name it $bpAsset.'
                    : (isStateLogicTask
                        ? 'In /Game/Blueprints, double-click $bpAsset (created in Task 01) and add a State variable (Enum / Integer) under My Blueprint → Variables for "$cleanTitle".'
                        : 'Open $bpAsset in /Game/Blueprints and add your player interaction input event (e.g., EnhancedInputAction IA_Interact) on the Event Graph.'),
                verify: isFoundationTask
                    ? 'A new blue-underlined Blueprint icon named $bpAsset appears inside /Game/Blueprints.'
                    : 'The Blueprint Editor opens showing $bpAsset ready for "$cleanTitle".',
                path: 'Content Browser → /Game/Blueprints/$bpAsset',
                code: 'Asset Name:   $bpAsset\nParent Class: Actor (AActor / EMechanicState::Active)',
                explain: 'An Actor Blueprint is a visual container you can place in a level that holds 3D meshes, collision sensors, and Event Graph nodes.',
              );
            case 1:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.2 · ATTACH VISUAL MESH & BOX COLLISION'
                    : (isStateLogicTask
                        ? 'STEP $taskNum.2 · BUILD STATE TRANSITION FUNCTION'
                        : 'STEP $taskNum.2 · CAST INTERACTION LINETRACE BY CHANNEL'),
                shortTitle: isFoundationTask
                    ? 'Attach Mesh & BoxCollision'
                    : (isStateLogicTask
                        ? 'Build State Transition Function'
                        : 'Cast Interaction LineTrace'),
                instruction: isFoundationTask
                    ? 'Inside $bpAsset, look at the top-left Components panel and click + Add to attach a Static Mesh ("VisualMesh", set to Shape_Plane/Cube) and a Box Collision ("InteractBox").'
                    : (isStateLogicTask
                        ? 'In $bpAsset under My Blueprint → Functions, click + to create a function named "AdvanceState" with a Switch on State node to step through valid states.'
                        : 'From your Input Action node, wire a LineTraceByChannel node projecting forward from the Player Camera to detect $bpAsset.'),
                verify: isFoundationTask
                    ? 'A visible 3D shape surrounded by an orange wireframe collision box appears in the central Viewport tab.'
                    : (isStateLogicTask
                        ? 'The AdvanceState function tab opens with Input → Switch on State → Set CurrentState nodes.'
                        : 'Triggering the input fires a red debug trace line toward the targeted $bpAsset.'),
                path: isFoundationTask
                    ? '$bpAsset → Components Panel (Top-Left)'
                    : '$bpAsset → Functions / Event Graph',
                code: isFoundationTask
                    ? '$bpAsset (Self)\n └─ DefaultSceneRoot\n     ├─ VisualMesh  (StaticMesh: Shape_Plane / Cube)\n     └─ InteractBox (BoxCollision: Extent 50, 50, 20)'
                    : (isStateLogicTask
                        ? '[Function: AdvanceState]\n   └──► [Switch on E_State]\n           ├──► Idle   ──► [Set CurrentState = Active]\n           └──► Active ──► [Set CurrentState = Complete]'
                        : '[IA_Interact (Started)] ──► [LineTraceByChannel (Camera → +400cm)]\n   └──► [Break Hit Result (Hit Actor)]'),
                explain: isFoundationTask
                    ? 'Static Mesh makes the object visible to the player. Box Collision creates an invisible trigger zone so the game knows when the player overlaps or clicks it.'
                    : (isStateLogicTask
                        ? 'Putting state transitions inside a dedicated function keeps your Event Graph clean and callable from any trigger.'
                        : 'LineTraceByChannel projects an invisible ray from the player camera to find exactly which actor you are looking at.'),
              );
            case 2:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.3 · DRAG $bpAsset INTO LEVEL VIEWPORT'
                    : (isStateLogicTask
                        ? 'STEP $taskNum.3 · SWAP VISUAL MATERIAL ON STATE CHANGE'
                        : 'STEP $taskNum.3 · CALL INTERACT TRIGGER ON HIT ACTOR'),
                shortTitle: isFoundationTask
                    ? 'Drag into Level Viewport'
                    : (isStateLogicTask
                        ? 'Swap Visual Material on State Change'
                        : 'Call Interact Trigger on Hit Actor'),
                instruction: isFoundationTask
                    ? 'Click Compile & Save (top-left of $bpAsset), then switch to the main Level tab and drag $bpAsset from the Content Browser onto the floor at (0, 0, 0).'
                    : (isStateLogicTask
                        ? 'At the end of AdvanceState in $bpAsset, drag VisualMesh into the graph and call Set Material (or Set Vector Parameter Value) so each state changes color on screen.'
                        : 'Drag off the Hit Actor pin from Break Hit Result, Cast To $bpAsset, and call its AdvanceState / Interact function.'),
                verify: isFoundationTask
                    ? '$bpAsset sits on the level floor and is listed inside the World Outliner panel.'
                    : (isStateLogicTask
                        ? 'VisualMesh updates its material color immediately whenever CurrentState changes.'
                        : 'Looking at $bpAsset and pressing Interact invokes AdvanceState on the hit instance.'),
                path: isFoundationTask
                    ? 'Main Level Viewport & World Outliner'
                    : '$bpAsset → Event Graph / AdvanceState',
                code: isFoundationTask
                    ? 'Instance: ${bpAsset}_0\nLocation: X = 0.0, Y = 0.0, Z = 0.0'
                    : (isStateLogicTask
                        ? '[Set CurrentState] ──► [Set Material (Target: VisualMesh)]\n                         (Select Material by CurrentState)'
                        : '[Break Hit Result] ──► [Cast To $bpAsset]\n                          └──► [Call AdvanceState ()]'),
                explain: isFoundationTask
                    ? 'A Blueprint in the Content Browser is just a template. Dragging it into the Level Viewport spawns an actual physical copy inside your game world.'
                    : 'Updating the mesh material gives instant visual confirmation that the state change succeeded.',
              );
            case 3:
              return (
                stepHeader: 'STEP $taskNum.4 · ADD & EXPOSE TUNING VARIABLES',
                shortTitle: isFoundationTask
                    ? 'Add $primaryVarName Variable'
                    : (isStateLogicTask
                        ? 'Bind $primaryVarName to Transition Speed'
                        : 'Add Target Hover Highlight Cue'),
                instruction:
                    'In $bpAsset, find My Blueprint → Variables on the left and click + to add $primaryVarName (Float) and bIsActive (Boolean). Click the Eye Icon next to $primaryVarName to make it Instance Editable.',
                verify:
                    'Select $bpAsset in the Level and confirm $primaryVarName is editable inside the Details panel.',
                path: '$bpAsset → My Blueprint → Variables → +',
                code: '$primaryVarName : Float ($primaryVar)  [👁 Instance Editable]\nbIsActive      : Boolean = false      [👁 Instance Editable]',
                explain: 'Variables store your mechanic\'s state and speed. Clicking the Eye Icon (Instance Editable) lets you tweak $primaryVarName directly in the Level without reopening the Blueprint.',
              );
            case 4:
              return (
                stepHeader: 'STEP $taskNum.5 · WIRE EVENT GRAPH NODE CHAIN',
                shortTitle: isFoundationTask
                    ? 'Initialize Default Component State'
                    : (isStateLogicTask
                        ? 'Step State with Interpolation Logic'
                        : 'Connect Cooldown & Range Check'),
                instruction:
                    'Open the Event Graph tab. Right-click InteractBox → Add Event → OnComponentBeginOverlap (or Input Action) → connect a Branch node → Set bIsActive = true and update the active state using $primaryVarName.',
                verify:
                    'Walk into $bpAsset in Play mode and confirm the overlap event updates the active state driven by $primaryVarName.',
                path: '$bpAsset → Event Graph Tab',
                code: '[Event OnBeginOverlap (InteractBox)]\n   └──► [Branch: NOT bIsActive]\n           └──► (True) ──► [Set bIsActive = true]\n                           [FMath::FInterpConstantTo ($primaryVarName)]',
                explain: 'The Event Graph is the visual brain of your Blueprint. Execution flows left-to-right along the white wire whenever the event fires.',
              );
            default:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.6 · COMPILE & VERIFY ACTOR IN LEVEL'
                    : (isStateLogicTask
                        ? 'STEP $taskNum.6 · ADD INVALID-STATE TRANSITION GUARD'
                        : 'STEP $taskNum.6 · PLAYTEST FULL LOOP IN VIEWPORT (ALT+P)'),
                shortTitle: isFoundationTask
                    ? 'Compile & Verify Actor in Level'
                    : (isStateLogicTask
                        ? 'Add Invalid-State Transition Guard'
                        : 'Playtest Full Loop in Viewport (Alt+P)'),
                instruction:
                    'Ensure your Branch node checks "$primaryGuard" before firing, connect a Print String ("$cleanTitle Active!") node to confirm, click Compile, and press Play (Alt+P).',
                verify:
                    'Pressing Play (Alt+P) and triggering the object prints "$cleanTitle Active!" in cyan text at the top-left of the viewport.',
                path: 'Main Toolbar → Compile → Play (Alt+P)',
                code: '// Guard: $primaryGuard\n[Branch: !IsBoundaryBlocked && Cooldown <= 0]\n   └──► (True) ──► [Print String: "$cleanTitle Active!"]',
                explain: 'Checking the guard condition on the Branch node prevents the mechanic from double-firing or locking up when inputs are spammed.',
              );
          }
        }
      }

      // =======================================================================
      // UNITY C# (Strictly C# MonoBehaviour + GameObject Hierarchy)
      // =======================================================================
      if (engineLabel == 'UNITY C#') {
        switch (stepIdx) {
          case 0:
            return (
              stepHeader: isFoundationTask
                  ? 'STEP $taskNum.1 · CREATE $pascalAsset.cs C# SCRIPT'
                  : (isStateLogicTask
                      ? 'STEP $taskNum.1 · DEFINE STATE ENUM IN $pascalAsset.cs'
                      : 'STEP $taskNum.1 · BIND PLAYER INTERACTION INPUT IN $pascalAsset.cs'),
              shortTitle: isFoundationTask
                  ? 'Create $pascalAsset.cs'
                  : (isStateLogicTask
                      ? 'Define State Enum & Variables'
                      : 'Bind Player Interaction Input'),
              instruction: isFoundationTask
                  ? 'In the Project window (bottom panel), right-click inside Assets/Scripts → Create → C# Script, and name it $pascalAsset.'
                  : (isStateLogicTask
                      ? 'In Assets/Scripts, open $pascalAsset.cs and define the state enum and active state field for "$cleanTitle".'
                      : 'Open $pascalAsset.cs and bind the player interaction input check for "$cleanTitle".'),
              verify: isFoundationTask
                  ? '$pascalAsset.cs appears in Assets/Scripts with class $pascalAsset : MonoBehaviour.'
                  : '$pascalAsset.cs compiles cleanly in your code editor.',
              path: 'Project Window → Assets/Scripts/$pascalAsset.cs',
              code: 'using UnityEngine;\n\npublic class $pascalAsset : MonoBehaviour {\n    private bool isActive = false;\n}',
              explain: 'A MonoBehaviour C# script is a custom component you can attach to any GameObject in your Unity scene.',
            );
          case 1:
            return (
              stepHeader: isFoundationTask
                  ? 'STEP $taskNum.2 · CREATE GAMEOBJECT & ATTACH COLLIDER'
                  : (isStateLogicTask
                      ? 'STEP $taskNum.2 · BUILD SETSTATE() TRANSITION METHOD'
                      : 'STEP $taskNum.2 · CAST PHYSICS RAYCAST TO TARGET'),
              shortTitle: isFoundationTask
                  ? 'Add Mesh & BoxCollider'
                  : (isStateLogicTask
                      ? 'Build State Transition Function'
                      : 'Cast Interaction Raycast'),
              instruction: isFoundationTask
                  ? 'In the Hierarchy window (left), right-click → Create Empty → name it "$pascalAsset". In the Inspector, click Add Component to attach a MeshRenderer/SpriteRenderer, a BoxCollider (check Is Trigger), and your $pascalAsset script.'
                  : (isStateLogicTask
                      ? 'Inside $pascalAsset.cs, write a SetState() method that validates and advances the current state.'
                      : 'Inside $pascalAsset.cs, cast a Physics.Raycast from Camera.main to detect the targeted $pascalAsset collider.'),
              verify:
                  'Selecting $pascalAsset in the Scene view shows a green wireframe BoxCollider outline.',
              path: 'Hierarchy → $pascalAsset → Inspector → Add Component',
              code: '$pascalAsset (GameObject)\n ├─ VisualMesh      (MeshFilter + MeshRenderer / SpriteRenderer)\n ├─ InteractTrigger (BoxCollider: isTrigger = true)\n └─ $pascalAsset    (MonoBehaviour Script)',
              explain: 'The Renderer draws the object on screen, the BoxCollider detects overlaps/clicks, and the Script runs your C# logic.',
            );
          case 2:
            return (
              stepHeader: isFoundationTask
                  ? 'STEP $taskNum.3 · POSITION IN SCENE & SAVE PREFAB'
                  : (isStateLogicTask
                      ? 'STEP $taskNum.3 · SWAP MATERIAL COLOR ON STATE CHANGE'
                      : 'STEP $taskNum.3 · CALL TRIGGER ON HIT $pascalAsset'),
              shortTitle: isFoundationTask
                  ? 'Place in Scene at (0, 0, 0)'
                  : (isStateLogicTask
                      ? 'Swap Visual Material on State Change'
                      : 'Call Interact Trigger on Hit Actor'),
              instruction: isFoundationTask
                  ? 'Select $pascalAsset in the Hierarchy, set its Transform Position to (0, 0, 0) in the Inspector, and drag it into Assets/Prefabs to save a reusable Prefab.'
                  : (isStateLogicTask
                      ? 'Update the MeshRenderer / SpriteRenderer color inside SetState() so each state is visually distinct.'
                      : 'When Physics.Raycast hits a collider, call GetComponent<$pascalAsset>()?.TriggerInteract().'),
              verify:
                  '$pascalAsset sits at (0, 0, 0) in the Scene view with a blue Prefab icon in the Hierarchy.',
              path: 'Hierarchy & Scene View → Transform (0, 0, 0)',
              code: 'GameObject: $pascalAsset\nTransform.position = new Vector3(0f, 0f, 0f);',
              explain: 'Saving your GameObject as a Prefab lets you place multiple copies across the level and update them all at once.',
            );
          case 3:
            return (
              stepHeader: 'STEP $taskNum.4 · EXPOSE [SerializeField] TUNING VARIABLES',
              shortTitle: isFoundationTask
                  ? 'Add [SerializeField] $primaryVarName'
                  : (isStateLogicTask
                      ? 'Bind $primaryVarName to Transition Speed'
                      : 'Add Target Hover Highlight Cue'),
              instruction:
                  'At the top of $pascalAsset.cs inside the class body, add [SerializeField] private float $primaryVarName so you can tune $primaryVarName directly in the Unity Inspector.',
              verify:
                  'Saving the script and clicking $pascalAsset in Unity shows $primaryVarName as an editable number field in the Inspector.',
              path: 'Assets/Scripts/$pascalAsset.cs (Inspector Fields)',
              code: '[Header("Tuning Parameters")]\n[SerializeField] private float $primaryVarName = 1.0f; // $primaryVar\n[SerializeField] private bool canTrigger = true;',
              explain: '[SerializeField] exposes a private C# variable inside the Unity Inspector without making it public to other scripts.',
            );
          case 4:
            return (
              stepHeader: 'STEP $taskNum.5 · WRITE UPDATE / TRIGGER LOGIC IN C#',
              shortTitle: isFoundationTask
                  ? 'Initialize Default Component State'
                  : (isStateLogicTask
                      ? 'Step State with Interpolation Logic'
                      : 'Connect Cooldown & Range Check'),
              instruction:
                  'Inside $pascalAsset.cs, implement Update() / FixedUpdate() to read input with Input.GetButton("Fire1") and advance state using Time.fixedDeltaTime and $primaryVarName.',
              verify:
                  'Triggering $pascalAsset in Play Mode steps the active value smoothly using $primaryVarName.',
              path: 'Assets/Scripts/$pascalAsset.cs :: FixedUpdate()',
              code: 'private void FixedUpdate() {\n    if (Input.GetButton("Fire1") && canTrigger) {\n        isActive = true;\n        currentVal = Mathf.MoveTowards(currentVal, targetVal, $primaryVarName * Time.fixedDeltaTime);\n    }\n}',
              explain: 'FixedUpdate() runs on a fixed physics clock, and multiplying by Time.fixedDeltaTime keeps speeds identical at any frame rate.',
            );
          default:
            return (
              stepHeader: isFoundationTask
                  ? 'STEP $taskNum.6 · COMPILE & VERIFY PREFAB IN SCENE'
                  : (isStateLogicTask
                      ? 'STEP $taskNum.6 · ADD INVALID-STATE TRANSITION GUARD'
                      : 'STEP $taskNum.6 · PLAYTEST FULL LOOP IN EDITOR (CTRL+P)'),
              shortTitle: isFoundationTask
                  ? 'Compile & Verify in Scene'
                  : (isStateLogicTask
                      ? 'Add Invalid-State Transition Guard'
                      : 'Playtest Full Loop in Editor (Ctrl+P)'),
              instruction:
                  'Add an early return guard at the top of your method to enforce "$primaryGuard", save the script, and press the Play button (Ctrl+P) at the top of the Unity Editor.',
              verify:
                  'In Play Mode, triggering "$cleanTitle" logs confirmation in the Console and prevents duplicate triggers.',
              path: 'Unity Top Toolbar → Play (Ctrl+P)',
              code: 'if (!canTrigger || cooldownTimer > 0f) return; // Guard: $primaryGuard\nDebug.Log("$cleanTitle activated!");',
              explain: 'The guard clause exits immediately if the mechanic is on cooldown or blocked, preventing state bugs when buttons are spammed.',
            );
        }
      }

      // =======================================================================
      // DEFAULT: GODOT 4 (Strictly GDScript .gd + Scene .tscn Hierarchy)
      // =======================================================================
      switch (stepIdx) {
        case 0:
          return (
            stepHeader: isFoundationTask
                ? 'STEP $taskNum.1 · CREATE $snakeAsset.tscn & .gd SCRIPT'
                : (isStateLogicTask
                    ? 'STEP $taskNum.1 · DEFINE STATE ENUM IN $snakeAsset.gd'
                    : 'STEP $taskNum.1 · BIND PLAYER INTERACTION INPUT IN $snakeAsset.gd'),
            shortTitle: isFoundationTask
                ? 'Create $snakeAsset.tscn & .gd'
                : (isStateLogicTask
                    ? 'Define State Enum & Variables'
                    : 'Bind Player Interaction Input'),
            instruction: isFoundationTask
                ? 'In the Scene dock (top-left), click + Other Node → select Node2D / CharacterBody2D → name it "$pascalAsset". Save the scene as res://scenes/$snakeAsset.tscn, then click the Attach Script icon to create res://scripts/$snakeAsset.gd.'
                : (isStateLogicTask
                    ? 'In the FileSystem dock, open res://scripts/$snakeAsset.gd and declare the state enum and active state variable for "$cleanTitle".'
                    : 'Open res://scripts/$snakeAsset.gd and bind the player interaction input action for "$cleanTitle".'),
            verify: isFoundationTask
                ? '$pascalAsset appears in the Scene tree with a scroll icon next to it, and $snakeAsset.gd opens in the Script editor.'
                : '$snakeAsset.gd is open in the central Script workspace.',
            path: 'FileSystem → res://scripts/$snakeAsset.gd',
            code: 'extends Node2D\nclass_name $pascalAsset\n\nvar is_active: bool = false',
            explain: 'In Godot 4, every reusable game object is a Scene (.tscn) with a GDScript (.gd) attached to its root node.',
          );
        case 1:
          return (
            stepHeader: isFoundationTask
                ? 'STEP $taskNum.2 · ADD VISUAL & COLLISION CHILD NODES'
                : (isStateLogicTask
                    ? 'STEP $taskNum.2 · BUILD SET_STATE() TRANSITION FUNCTION'
                    : 'STEP $taskNum.2 · CAST RAYCAST2D / AREA2D QUERY'),
            shortTitle: isFoundationTask
                ? 'Add Sprite2D & Area2D/CollisionShape2D'
                : (isStateLogicTask
                    ? 'Build State Transition Function'
                    : 'Cast Interaction RayCast2D'),
            instruction: isFoundationTask
                ? 'Right-click the root "$pascalAsset" node in the Scene dock → + Add Child Node → add a Sprite2D (or ColorRect) named "Visual" and an Area2D with a CollisionShape2D (RectangleShape2D) named "HitBox".'
                : (isStateLogicTask
                    ? 'In $snakeAsset.gd, add func set_mechanic_state(new_state: int) -> void: to validate and update the active state.'
                    : 'Use a RayCast2D / Area2D overlap check in $snakeAsset.gd to detect targeted $pascalAsset instances.'),
            verify:
                'The 2D Viewport shows your visible shape surrounded by a light-blue rectangle collision outline (no yellow warning triangle).',
            path: 'Scene Dock (Top-Left) → $pascalAsset Hierarchy',
            code: '$pascalAsset (Node2D / CharacterBody2D)\n ├─ Visual (Sprite2D / ColorRect: 64x64)\n └─ HitBox (Area2D)\n     └─ CollisionShape2D (RectangleShape2D)',
            explain: 'Sprite2D/ColorRect makes the object visible on screen, while Area2D + CollisionShape2D lets Godot detect overlaps and clicks.',
          );
        case 2:
          return (
            stepHeader: isFoundationTask
                ? 'STEP $taskNum.3 · INSTANCE SCENE IN MAIN LEVEL'
                : (isStateLogicTask
                    ? 'STEP $taskNum.3 · SWAP MODULATE / VISUAL ON STATE CHANGE'
                    : 'STEP $taskNum.3 · CALL TRIGGER ON HIT $pascalAsset'),
            shortTitle: isFoundationTask
                ? 'Instance in Main Scene'
                : (isStateLogicTask
                    ? 'Swap Visual Color on State Change'
                    : 'Call Interact Trigger on Hit Node'),
            instruction: isFoundationTask
                ? 'Press Ctrl+S to save $snakeAsset.tscn, switch to your Main level scene tab, and click the Chain-Link icon ("Instantiate Child Scene") to drop $snakeAsset.tscn into the level at (0, 0).'
                : (isStateLogicTask
                    ? 'Inside set_mechanic_state(), update \$Visual.modulate so each state of $pascalAsset has a distinct color on screen.'
                    : 'When the RayCast2D / Area2D hits $pascalAsset, call target.set_mechanic_state() to trigger the transition.'),
            verify:
                '$pascalAsset appears in the Main scene tree with a small movie-clapper / chain icon next to it.',
            path: 'Main Scene Tab → Instantiate Child Scene (Ctrl+Shift+A)',
            code: 'Instanced Node: $pascalAsset (res://scenes/$snakeAsset.tscn)\nposition = Vector2(0, 0)',
            explain: 'Instantiating places a live copy of your scene inside the game level so you can see and test it when pressing Play.',
          );
        case 3:
          return (
            stepHeader: 'STEP $taskNum.4 · ADD @export TUNING VARIABLES IN GDSCRIPT',
            shortTitle: isFoundationTask
                ? 'Add @export var $primaryVarName'
                : (isStateLogicTask
                    ? 'Bind $primaryVarName to Transition Speed'
                    : 'Add Target Hover Highlight Cue'),
            instruction:
                'At the top of $snakeAsset.gd, add @export var $primaryVarName: float = 1.0 so you can tune $primaryVarName directly in the right-hand Inspector dock.',
            verify:
                'Selecting $pascalAsset in the Scene tree displays $primaryVarName as an editable field at the top of the Inspector dock.',
            path: 'res://scripts/$snakeAsset.gd (@export)',
            code: '@export var $primaryVarName: float = 1.0 # $primaryVar\n@export var can_trigger: bool = true\nvar current_val: float = 0.0',
            explain: '@export exposes a GDScript variable in the Godot Inspector dock so you can tweak $primaryVarName live without editing code.',
          );
        case 4:
          return (
            stepHeader: 'STEP $taskNum.5 · IMPLEMENT _physics_process(delta) LOGIC',
            shortTitle: isFoundationTask
                ? 'Initialize Default Node State'
                : (isStateLogicTask
                    ? 'Step State with Interpolation Logic'
                    : 'Connect Cooldown & Range Check'),
            instruction:
                'Inside $snakeAsset.gd, add func _physics_process(delta: float) -> void: to check Input.is_action_pressed("primary_action") and step the value using move_toward and $primaryVarName.',
            verify:
                'Triggering $pascalAsset in the scene steps the active value smoothly using $primaryVarName.',
            path: 'res://scripts/$snakeAsset.gd :: _physics_process(delta)',
            code: 'func _physics_process(delta: float) -> void:\n    if Input.is_action_pressed("primary_action") and can_trigger:\n        is_active = true\n        current_val = move_toward(current_val, target_val, $primaryVarName * delta)',
            explain: '_physics_process(delta) runs 60 times per second in sync with physics, and move_toward smoothly transitions values without overshooting.',
          );
        default:
          return (
            stepHeader: isFoundationTask
                ? 'STEP $taskNum.6 · SAVE & VERIFY SCENE IN VIEWPORT'
                : (isStateLogicTask
                    ? 'STEP $taskNum.6 · ADD INVALID-STATE TRANSITION GUARD'
                    : 'STEP $taskNum.6 · PLAYTEST FULL LOOP IN VIEWPORT (F5)'),
            shortTitle: isFoundationTask
                ? 'Save & Verify Scene in Viewport'
                : (isStateLogicTask
                    ? 'Add Invalid-State Transition Guard'
                    : 'Playtest Full Loop in Viewport (F5)'),
            instruction:
                'Add a guard check at the top of _physics_process to enforce $primaryGuard, add print("$cleanTitle Active!"), and press F5 (or the top-right Play button) to test.',
            verify:
                'The game window launches and triggering the action prints "$cleanTitle Active!" in the bottom Output panel.',
            path: 'Top-Right Toolbar → Play Scene (F6) / Play Project (F5)',
            code: 'if not can_trigger or cooldown_timer > 0.0:\n    return # Guard: $primaryGuard\nprint("$cleanTitle Active!")',
            explain: 'The early-return guard stops the function immediately if the mechanic is blocked or on cooldown, preventing state lockups.',
          );
      }
    }

    final totalTaskMinutes = extractTaskTotalMinutes(parentTask.text);
    final clauses = extractActionClauses(cleanTitle);
    final lowerTitle = cleanTitle.toLowerCase();

    final targetAssetName = engineLabel == 'UNREAL 5'
        ? (unrealCppMode ? cppClass : bpAsset)
        : (engineLabel == 'UNITY C#'
            ? '$pascalAsset.cs'
            : '$snakeAsset.tscn');

    ({
      String explain,
      String primaryChip,
      String pitfall,
    }) buildPhaseSpecContext(int phaseIdx) {
      switch (phaseIdx) {
        case 0:
          return (
            explain:
                'Every step in this task builds inside $targetAssetName so ${checkpointNode.cleanStageTitle} stays modular and reusable across the level.',
            primaryChip: 'Asset: $targetAssetName',
            pitfall: engineLabel == 'UNREAL 5'
                ? 'Choose Actor (AActor) as the parent class so you can attach components and place $targetAssetName in the level.'
                : (engineLabel == 'UNITY C#'
                    ? 'Make sure the file name "$pascalAsset.cs" matches the class name "$pascalAsset" so Unity can attach it.'
                    : 'Save the scene in res://scenes/ before attaching the script so node paths stay clean.'),
          );
        case 1:
          return (
            explain:
                'Gives $targetAssetName both its visible shape and the collision trigger sensor needed for core logic.',
            primaryChip: 'Asset: $targetAssetName',
            pitfall: engineLabel == 'UNREAL 5'
                ? 'Set Collision Presets on InteractBox to OverlapAllDynamic so player overlap events fire reliably.'
                : (engineLabel == 'UNITY C#'
                     ? 'Check the "Is Trigger" box on BoxCollider so the player does not physically snag on the sensor.'
                     : 'Assign a RectangleShape2D resource inside CollisionShape2D to clear the yellow scene warning icon.'),
          );
        case 2:
          return (
            explain:
                'Places a live $targetAssetName instance in the level so you can test "${checkpointNode.playtestCondition}" on screen.',
            primaryChip: 'Instance: $targetAssetName',
            pitfall: engineLabel == 'UNREAL 5'
                ? 'Click Compile & Save before dragging $targetAssetName into the viewport so the new mesh and collision box appear.'
                : (engineLabel == 'UNITY C#'
                    ? 'Reset Transform Position to (0, 0, 0) in the Inspector so $pascalAsset is not hidden off-camera.'
                    : 'Use the Chain-Link icon (Ctrl+Shift+A) to instantiate $targetAssetName rather than copying raw nodes.'),
          );
        case 3:
          return (
            explain:
                'Exposes $primaryVarName on $targetAssetName so you can tune gameplay feel live in the editor without recompiling.',
            primaryChip: 'Spec Param: $primaryVar',
            pitfall: engineLabel == 'UNREAL 5'
                ? 'Click the Eye icon (Instance Editable) next to $primaryVarName so it appears in the Level Details panel.'
                : (engineLabel == 'UNITY C#'
                    ? 'Keep [SerializeField] above private float $primaryVarName so Unity serializes it in the Inspector.'
                    : 'Save the script (Ctrl+S) after adding @export var $primaryVarName so the Inspector dock refreshes.'),
          );
        case 4:
          return (
            explain:
                'Connects player trigger input on $targetAssetName to $primaryVarName so the active state updates smoothly every frame.',
            primaryChip: 'Drives: $primaryVar',
            pitfall: engineLabel == 'UNREAL 5'
                ? 'Connect the white execution wire from the Branch (True) pin into your state update node.'
                : (engineLabel == 'UNITY C#'
                    ? 'Multiply by Time.fixedDeltaTime inside FixedUpdate() so speed stays identical at any frame rate.'
                    : 'Multiply $primaryVarName by delta inside _physics_process(delta) for frame-rate independent motion.'),
          );
        default:
          return (
            explain:
                'Enforces $primaryGuard on $targetAssetName and completes playable verification for "${checkpointNode.cleanStageTitle}".',
            primaryChip: 'Guard: $primaryGuard',
            pitfall:
                'Place the guard check at the very top of your function so blocked or cooldown inputs exit immediately ($primaryGuard).',
          );
      }
    }

    // Build the dynamic sequence of step specifications (can scale from 3 steps to 10+ steps)
    final dynamicSpecs = <({
      String stepHeader,
      String shortTitle,
      String instruction,
      String verify,
      String path,
      String code,
      String explain,
      String primaryChip,
      String pitfall,
    })>[];

    void addPhaseStep(int phaseIdx) {
      final rawSpec = buildAtomicStepSpec(phaseIdx);
      final rawCtx = buildPhaseSpecContext(phaseIdx);
      if (phaseIdx == 5) {
        final guardSpec = deriveConcreteGuardStepSpec(
          rawGuard: primaryGuard,
          targetAssetName: targetAssetName,
          engineLabel: engineLabel,
          unrealCppMode: unrealCppMode,
          primaryVarName: primaryVarName,
        );
        dynamicSpecs.add((
          stepHeader:
              'STEP $taskNum.${dynamicSpecs.length + 1} · ${guardSpec.shortTitle.toUpperCase()}',
          shortTitle: guardSpec.shortTitle,
          instruction: guardSpec.instruction,
          verify: guardSpec.verify,
          path: rawSpec.path,
          code: guardSpec.code,
          explain: guardSpec.explain,
          primaryChip: rawCtx.primaryChip,
          pitfall: guardSpec.pitfall,
        ));
        return;
      }
      dynamicSpecs.add((
        stepHeader: rawSpec.stepHeader,
        shortTitle: rawSpec.shortTitle,
        instruction: rawSpec.instruction,
        verify: rawSpec.verify,
        path: rawSpec.path,
        code: rawSpec.code,
        explain: rawCtx.explain,
        primaryChip: rawCtx.primaryChip,
        pitfall: rawCtx.pitfall,
      ));
    }

    final isCompactGuardTask = totalTaskMinutes <= 60 &&
        clauses.length <= 2 &&
        (lowerTitle.startsWith('verify ') ||
            lowerTitle.startsWith('enforce ') ||
            lowerTitle.contains('guard') ||
            lowerTitle.contains('interrupt') ||
            lowerTitle.contains('buffer') ||
            lowerTitle.contains('clamp'));

    final isCompactFeelOrUiTask = !isCompactGuardTask &&
        totalTaskMinutes <= 60 &&
        clauses.length <= 2 &&
        (layerTag == 'FEEL' ||
            layerTag == 'UI / HUD' ||
            lowerTitle.startsWith('hook up ') ||
            lowerTitle.startsWith('wire ') ||
            lowerTitle.startsWith('render ') ||
            lowerTitle.startsWith('trigger ') ||
            lowerTitle.startsWith('spawn '));

    final isSingleClauseExtensionTask = !isFoundationTask &&
        !isCompactGuardTask &&
        !isCompactFeelOrUiTask &&
        totalTaskMinutes <= 120 &&
        clauses.length <= 1;

    if (isCompactGuardTask) {
      // Compact 3-step guard/verification flow
      addPhaseStep(0);
      addPhaseStep(3);
      addPhaseStep(5);
    } else if (isCompactFeelOrUiTask) {
      // Compact 4-step feel/UI cue flow
      addPhaseStep(0);
      addPhaseStep(2);
      addPhaseStep(4);
      addPhaseStep(5);
    } else if (isSingleClauseExtensionTask) {
      // Focused 5-step extension flow
      addPhaseStep(0);
      addPhaseStep(1);
      addPhaseStep(2);
      addPhaseStep(3);
      addPhaseStep(5);
    } else {
      // Core foundation or multi-clause mechanic flow (starts with phases 0..4, expands dynamically for extra clauses/params/guards, ends with phase 5)
      addPhaseStep(0);
      addPhaseStep(1);
      addPhaseStep(2);
      addPhaseStep(3);
      addPhaseStep(4);

      // 1. Add a dedicated step for every additional action clause beyond the first 2
      for (int cIdx = 2; cIdx < clauses.length; cIdx++) {
        final clauseText = clauses[cIdx];
        final clauseIdent = clauseText
            .toLowerCase()
            .replaceAll(_nonLowerAlnumRegex, '_')
            .replaceAll(_trimUnderscoresRegex, '');
        final safeMethod = clauseIdent.isEmpty ? 'step_${cIdx + 1}' : clauseIdent;
        dynamicSpecs.add((
          stepHeader: 'STEP $taskNum.${dynamicSpecs.length + 1} · IMPLEMENT ${clauseText.toUpperCase()}',
          shortTitle: 'Implement $clauseText',
          instruction:
              'In $targetAssetName, add the dedicated handler for "$clauseText" and connect it to the active state loop.',
          verify:
              'Triggering "$clauseText" in the editor updates $targetAssetName state with zero errors.',
          path: whereLocation,
          code: engineLabel == 'UNREAL 5'
              ? (unrealCppMode
                  ? 'void $cppClass::Execute_$safeMethod(float DeltaTime) {\n  // Clause: $clauseText\n  ApplyStateDelta(DeltaTime * $primaryVarName);\n}'
                  : '[Custom Event: Execute_$safeMethod]\n   └──► [Apply State Delta ($primaryVarName)] // $clauseText')
              : (engineLabel == 'UNITY C#'
                  ? 'private void Execute_$safeMethod() {\n    // Clause: $clauseText\n    ApplyStateDelta($primaryVarName * Time.fixedDeltaTime);\n}'
                  : 'func _execute_$safeMethod(delta: float) -> void:\n    # Clause: $clauseText\n    apply_state_delta($primaryVarName * delta)'),
          explain:
              'Isolating "$clauseText" into its own step keeps complex multi-part mechanics easy to test and debug.',
          primaryChip: 'Clause: $clauseText',
          pitfall:
              'Verify "$clauseText" only runs when $targetAssetName is in a valid active state.',
        ));
      }

      // 2. When a task is multi-clause (>= 3 clauses) or heavy (> 180m), also emit dedicated steps for each extra tuning parameter and guard
      final expandSpecItems = clauses.length >= 3 || totalTaskMinutes > 180;
      if (expandSpecItems) {
        for (int tIdx = 1; tIdx < effectiveTuningParams.length; tIdx++) {
          final extraTune = effectiveTuningParams[tIdx];
          final extraVarName = extraTune
              .split(':')
              .first
              .trim()
              .replaceAll(_nonIdentCharRegex, '_');
          dynamicSpecs.add((
            stepHeader: 'STEP $taskNum.${dynamicSpecs.length + 1} · WIRE TUNING PARAMETER ${extraVarName.toUpperCase()}',
            shortTitle: 'Wire Tuning: $extraVarName',
            instruction:
                'Expose $extraVarName on $targetAssetName and pass $extraVarName into the active mechanic calculation.',
            verify:
                'Select $targetAssetName in the editor and confirm $extraVarName updates the active behavior live in Play mode.',
            path: whereLocation,
            code: engineLabel == 'UNREAL 5'
                ? 'UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Tuning")\nfloat $extraVarName = 1.0f; // $extraTune'
                : (engineLabel == 'UNITY C#'
                    ? '[SerializeField] private float $extraVarName = 1.0f; // $extraTune'
                    : '@export var $extraVarName: float = 1.0 # $extraTune'),
            explain:
                'Connects $extraVarName directly to $targetAssetName so you can balance gameplay feel live.',
            primaryChip: 'Spec Param: $extraTune',
            pitfall:
                'Clamp $extraVarName > 0 so zero or negative inspector inputs cannot divide by zero.',
          ));
        }

        for (int gIdx = 1; gIdx < effectiveEdgeCases.length; gIdx++) {
          final extraGuard = effectiveEdgeCases[gIdx];
          final guardSpec = deriveConcreteGuardStepSpec(
            rawGuard: extraGuard,
            targetAssetName: targetAssetName,
            engineLabel: engineLabel,
            unrealCppMode: unrealCppMode,
            primaryVarName: primaryVarName,
          );
          dynamicSpecs.add((
            stepHeader:
                'STEP $taskNum.${dynamicSpecs.length + 1} · ${guardSpec.shortTitle.toUpperCase()}',
            shortTitle: guardSpec.shortTitle,
            instruction: guardSpec.instruction,
            verify: guardSpec.verify,
            path: whereLocation,
            code: guardSpec.code,
            explain: guardSpec.explain,
            primaryChip: 'Guard: $extraGuard',
            pitfall: guardSpec.pitfall,
          ));
        }
      }

      addPhaseStep(5);
    }

    // Normalize step numbering headers ("STEP X.1", "STEP X.2", ... "STEP X.N") across all dynamicSpecs
    for (int idx = 0; idx < dynamicSpecs.length; idx++) {
      final raw = dynamicSpecs[idx];
      final suffix = raw.stepHeader.replaceFirst(_stepHeaderPrefixRegex, '');
      dynamicSpecs[idx] = (
        stepHeader: 'STEP $taskNum.${idx + 1} · $suffix',
        shortTitle: raw.shortTitle,
        instruction: raw.instruction,
        verify: raw.verify,
        path: raw.path,
        code: raw.code,
        explain: raw.explain,
        primaryChip: raw.primaryChip,
        pitfall: raw.pitfall,
      );
    }

    final hasStaleEconomyOrGuardSteps = parentTask.children.any(
      (c) =>
          c.codeTargetFile != 'custom_snippet' &&
          ((hasLegacyEconomyMismatch &&
                  (c.text.toUpperCase().contains('TRANSACTIONCOSTBASE') ||
                      c.text.toUpperCase().contains('PROCESSDURATIONSEC') ||
                      c.text.toUpperCase().contains('STACKMAXCAPACITY') ||
                      (c.codeSnippet ?? '').contains('transactionCostBase'))) ||
              (c.codeSnippet ?? '').contains('ValidateGuard_') ||
              (c.codeSnippet ?? '').contains('_validate_guard_') ||
              (c.codeSnippet ?? '').contains('!IsBoundaryBlocked')),
    );
    if ((parentTask.children.isEmpty || hasStaleEconomyOrGuardSteps) &&
        !parentTask.children.any((c) => c.codeTargetFile == 'custom_snippet')) {
      final isParentCompleted = parentTask.completed;
      parentTask.children = [
        for (int sIdx = 0; sIdx < dynamicSpecs.length; sIdx++)
          () {
            final s = dynamicSpecs[sIdx];
            return Subtask(
              id: '${parentTask.id}_sub_${sIdx + 1}',
              text: s.stepHeader,
              specNotes: s.instruction,
              codeSnippet: s.code,
              completed: isParentCompleted,
            );
          }(),
      ];
    }

    final stepMinutesList = computeWeightedStepMinutes(
      parentTask.children.length,
      totalTaskMinutes,
    );

    final resolvedSubs = <TaskHowToSubStep>[];
    for (int i = 0; i < parentTask.children.length; i++) {
      final child = parentTask.children[i];
      final isCustomSnippet = child.codeTargetFile == 'custom_snippet';
      final hasDynamicSpec = i < dynamicSpecs.length;
      final spec = hasDynamicSpec ? dynamicSpecs[i] : dynamicSpecs.last;
      final stepMins = i < stepMinutesList.length ? stepMinutesList[i] : 20;
      final stepEta = formatStepEtaLabel(stepMins);
      final rawLabel = child.text.trim();
      final stepLabel = isCustomSnippet
          ? (rawLabel.toUpperCase().startsWith('STEP ')
              ? rawLabel
              : 'STEP $taskNum.${i + 1} · ${rawLabel.toUpperCase()}')
          : (hasDynamicSpec
              ? spec.stepHeader
              : 'STEP $taskNum.${i + 1} · ${rawLabel.toUpperCase()}');
      final instruction = isCustomSnippet &&
              child.specNotes != null &&
              child.specNotes!.trim().isNotEmpty
          ? child.specNotes!.trim()
          : (hasDynamicSpec
              ? spec.instruction
              : (child.specNotes != null && child.specNotes!.trim().isNotEmpty
                  ? child.specNotes!.trim()
                  : 'Implement and verify "$rawLabel" inside $whereLocation.'));
      final code = isCustomSnippet &&
              child.codeSnippet != null &&
              child.codeSnippet!.trim().isNotEmpty
          ? child.codeSnippet!.trim()
          : (hasDynamicSpec
              ? spec.code
              : (child.codeSnippet != null && child.codeSnippet!.trim().isNotEmpty
                  ? child.codeSnippet!.trim()
                  : '// Step $taskNum.${i + 1}: $rawLabel\nexecute_step_${taskNum}_${i + 1}($primaryVarName)'));
      final shortTitle = (!isCustomSnippet && hasDynamicSpec)
          ? spec.shortTitle
          : rawLabel.replaceFirst(_stepHeaderPrefixRegex, '');

      String nextStepTitle = 'Verify Checkpoint & Continue';
      if (i + 1 < parentTask.children.length) {
        final nextChild = parentTask.children[i + 1];
        final nextCustom = nextChild.codeTargetFile == 'custom_snippet';
        nextStepTitle = (!nextCustom && i + 1 < dynamicSpecs.length)
            ? dynamicSpecs[i + 1].shortTitle
            : nextChild.text.trim().replaceFirst(_stepHeaderPrefixRegex, '');
      }

      final isLastStep = i == parentTask.children.length - 1;
      final chips = <String>[
        spec.primaryChip,
        isLastStep
            ? 'Goal: ${checkpointNode.cleanStageTitle}'
            : 'Next: $nextStepTitle',
      ];

      resolvedSubs.add(
        TaskHowToSubStep(
          subtask: child,
          stepNumberLabel: stepLabel,
          shortTitle: shortTitle,
          instruction: instruction,
          verifyResult: (!isCustomSnippet && hasDynamicSpec)
              ? spec.verify
              : 'Verify "$shortTitle" responds cleanly in the active viewport.',
          stepPath: (!isCustomSnippet && hasDynamicSpec) ? spec.path : whereLocation,
          codeFormula: code,
          explainConcept: (!isCustomSnippet && hasDynamicSpec)
              ? spec.explain
              : 'Connects "$shortTitle" to "$primaryVar" and "$primaryGuard".',
          specChips: chips,
          quickFixPitfall: spec.pitfall,
          estimatedMinutes: stepMins,
          etaLabel: stepEta,
          isGuardStep: isLastStep || stepLabel.toUpperCase().contains('GUARD'),
        ),
      );
    }

    final result = TaskHowToBlueprint(
      numLabel: numLabel,
      layerTag: layerTag,
      cleanTitle: cleanTitle,
      durationChip: durationChip,
      whereLocation: whereLocation,
      engineLabel: engineLabel,
      subSteps: resolvedSubs,
    );

    if (_blueprintCache.length > 512) {
      _blueprintCache.clear();
    }
    _blueprintCache[cacheKey] = (
      signature: _computeTaskSignature(
        parentTask: parentTask,
        checkpointNode: checkpointNode,
        engineHint: engineHint,
        unrealCppMode: unrealCppMode,
      ),
      blueprint: result,
    );
    return result;
  }

  /// Tailors `parentTask.children` (Step X.1, X.2, X.3) to the developer's exact scene/node/script context
  /// (e.g. "CharacterBody2D with RayCast2D HookRay and Line2D RopeVisual") and marks each sub-step
  /// with `codeTargetFile = 'custom_snippet'` so it persists across re-renders.
  static void tailorSubStepsForContext({
    required Subtask parentTask,
    required int taskIndex,
    required FeatureStateNode checkpointNode,
    required String userContext,
    String? engineHint,
  }) {
    resolve(
      parentTask: parentTask,
      taskIndex: taskIndex,
      checkpointNode: checkpointNode,
      engineHint: engineHint,
    );

    final taskNum = taskIndex + 1;
    final cleanTitle = extractCleanTitle(parentTask.text);
    final engineLabel = detectEngineLabel(engineHint);
    final cpArchetype =
        MechanicArchetypeProfile.fromFeatureTitle(checkpointNode.cleanStageTitle);
    final hasLegacyEconomyMismatch = cpArchetype.category != 'economy' &&
        checkpointNode.tuningParams.isNotEmpty &&
        checkpointNode.tuningParams.first.contains('transactionCostBase: 25 gold');
    final effectiveTuningParams = hasLegacyEconomyMismatch
        ? cpArchetype.tuningParams
        : checkpointNode.tuningParams;
    final effectiveEdgeCases = hasLegacyEconomyMismatch
        ? cpArchetype.edgeCases
        : checkpointNode.edgeCases;

    final primaryVar = effectiveTuningParams.isNotEmpty
        ? effectiveTuningParams[taskIndex % effectiveTuningParams.length]
        : 'responseTime: 0.12 s';
    final primaryVarName = primaryVar.split(':').first.trim();
    final primaryGuard = effectiveEdgeCases.isNotEmpty
        ? effectiveEdgeCases[taskIndex % effectiveEdgeCases.length]
        : '[STATE GUARD] Prevent duplicate trigger while active';

    final stopWords = <String>{
      'using',
      'with',
      'named',
      'and',
      'the',
      'for',
      'inside',
      'from',
      'into',
      'node',
      'script',
      'class',
      'component',
      'scene',
    };
    final tokens = RegExp(r'[A-Za-z_][A-Za-z0-9_]{2,}')
        .allMatches(userContext)
        .map((m) => m.group(0)!)
        .where((w) => !stopWords.contains(w.toLowerCase()))
        .toList();

    final primaryNode = tokens.isNotEmpty ? tokens.first : 'PlayerController';
    final secondaryNode = tokens.length > 1 ? tokens[1] : primaryNode;
    final tertiaryNode = tokens.length > 2 ? tokens[2] : secondaryNode;

    String step1Code;
    String step2Code;
    String step3Code;

    if (engineLabel == 'UNITY C#') {
      step1Code =
          '// Context: $userContext\nif (Input.GetButton("Fire1") && $secondaryNode != null && CanEnterState()) {\n    activeState = MechanicState.Active;\n}';
      step2Code =
          '$primaryNode.ExecuteStep($secondaryNode, $primaryVarName * Time.fixedDeltaTime);\n$tertiaryNode.SyncVisualState(activeState);';
      step3Code =
          'if (!$primaryNode.IsValidState($secondaryNode) || cooldownTimer > 0f) return; // Guard: $primaryGuard';
    } else if (engineLabel == 'UNREAL 5') {
      step1Code =
          '// Context: $userContext\nif (bInputPressed && IsValid($secondaryNode) && CanEnterState()) {\n    ActiveState = EMechanicState::Active;\n}';
      step2Code =
          '$primaryNode->ExecuteStep($secondaryNode, DeltaTime * $primaryVarName);\n$tertiaryNode->SyncVisualState(ActiveState);';
      step3Code =
          'if (!$primaryNode->IsValidState($secondaryNode) || CooldownTimer > 0.f) return; // Guard: $primaryGuard';
    } else {
      step1Code =
          '# Context: $userContext\nif Input.is_action_pressed("primary_action") and is_instance_valid($secondaryNode) and can_enter_state():\n    activeState = State.ACTIVE';
      step2Code =
          '$primaryNode.apply_mechanic_step($secondaryNode, $primaryVarName * delta)\n$tertiaryNode.sync_visual_state(activeState)';
      step3Code =
          'if not $primaryNode.is_valid_state($secondaryNode) or cooldownTimer > 0.0:\n    return # Guard: $primaryGuard';
    }

    for (int idx = 0; idx < parentTask.children.length; idx++) {
      final isFirst = idx == 0;
      final isLast = idx == parentTask.children.length - 1;
      if (isFirst) {
        parentTask.children[idx].text =
            'STEP $taskNum.1 · BIND INPUT & VALIDATE ${secondaryNode.toUpperCase()} IN ${primaryNode.toUpperCase()}';
        parentTask.children[idx].specNotes =
            'Inside $primaryNode, read player input and validate $secondaryNode before entering "$cleanTitle" ($userContext):';
        parentTask.children[idx].codeSnippet = step1Code;
      } else if (isLast) {
        parentTask.children[idx].text =
            'STEP $taskNum.${idx + 1} · ENFORCE GUARD CHECK ON ${secondaryNode.toUpperCase()} & PLAYTEST';
        parentTask.children[idx].specNotes =
            'Guard $primaryNode / $secondaryNode against invalid state or rapid re-triggers to satisfy "$primaryGuard":';
        parentTask.children[idx].codeSnippet = step3Code;
      } else if (idx == 1) {
        parentTask.children[idx].text =
            'STEP $taskNum.2 · APPLY ${primaryVarName.toUpperCase()} LOGIC ACROSS ${primaryNode.toUpperCase()} & ${tertiaryNode.toUpperCase()}';
        parentTask.children[idx].specNotes =
            'Drive "$cleanTitle" on $primaryNode / $secondaryNode using inspector parameter $primaryVarName and update $tertiaryNode:';
        parentTask.children[idx].codeSnippet = step2Code;
      } else if (idx == 2) {
        parentTask.children[idx].text =
            'STEP $taskNum.3 · SYNC ${tertiaryNode.toUpperCase()} VISUAL STATE FROM ${primaryNode.toUpperCase()}';
        parentTask.children[idx].specNotes =
            'Update $tertiaryNode visual feedback whenever $primaryNode / $secondaryNode changes state:';
        parentTask.children[idx].codeSnippet = step2Code;
      } else if (idx == 3) {
        parentTask.children[idx].text =
            'STEP $taskNum.4 · EXPOSE ${primaryVarName.toUpperCase()} ON ${primaryNode.toUpperCase()}';
        parentTask.children[idx].specNotes =
            'Expose $primaryVarName on $primaryNode so you can tune $secondaryNode and $tertiaryNode live in the editor:';
        parentTask.children[idx].codeSnippet = step2Code;
      } else {
        parentTask.children[idx].text =
            'STEP $taskNum.${idx + 1} · STEP ${secondaryNode.toUpperCase()} INTERPOLATION IN ${primaryNode.toUpperCase()}';
        parentTask.children[idx].specNotes =
            'Advance $secondaryNode and $tertiaryNode each physics tick inside $primaryNode using $primaryVarName:';
        parentTask.children[idx].codeSnippet = step2Code;
      }
      parentTask.children[idx].codeTargetFile = 'custom_snippet';
    }
    _blueprintCache.remove('${checkpointNode.id}_${parentTask.id}_$taskIndex');
  }
}
