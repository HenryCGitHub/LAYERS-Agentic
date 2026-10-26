/// Synthesizes mechanic-specific scope bullets, tuning parameters, edge-case guards,
/// and 60/40 Playable Checkpoint blueprints for any custom or Beat-derived feature title.
class MechanicArchetypeProfile {
  final String category; // 'grapple', 'movement', 'combat', 'farming', 'economy', 'building', 'ui', 'deckbuilder', 'vehicle', 'stealth', 'puzzle', 'core'
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
    if (lower.contains('visual, audio & feel polish') ||
        lower.contains('gold standard polish') ||
        lower.contains('final art & material pass')) {
      return 'polish';
    }
    if (lower.contains('content roster & progression scaling') ||
        lower.contains('integration & polish') ||
        lower.contains('content data table & roster')) {
      return 'content';
    }
    if (lower.contains('grappl') ||
        lower.contains('hook') ||
        lower.contains('swing') ||
        lower.contains('rope') ||
        lower.contains('tether') ||
        lower.contains('zipline')) {
      return 'grapple';
    }
    // Check specialized genres (deckbuilder, vehicle, stealth, puzzle, farming) BEFORE generic combat/movement/reset keywords
    if (lower.contains('deck') ||
        lower.contains('card') ||
        lower.contains('draw pile') ||
        lower.contains('discard pile') ||
        lower.contains('hand slot') ||
        lower.contains('mana cost') ||
        lower.contains('turn-based')) {
      if (!lower.contains('upgrade card') &&
          !lower.contains('3-card roll') &&
          !lower.contains('reward')) {
        return 'deckbuilder';
      }
    }
    if (lower.contains('vehicle') ||
        lower.contains('drift') ||
        lower.contains('steering') ||
        lower.contains('throttle') ||
        lower.contains('chassis') ||
        lower.contains('suspension') ||
        lower.contains('lap timer')) {
      return 'vehicle';
    }
    if (lower.contains('stealth') ||
        lower.contains('vision cone') ||
        lower.contains('suspicion') ||
        lower.contains('sneak') ||
        lower.contains('cloak') ||
        lower.contains('noise radius')) {
      return 'stealth';
    }
    if (lower.contains('puzzle') ||
        lower.contains('pressure plate') ||
        lower.contains('logic gate') ||
        lower.contains('laser beam') ||
        lower.contains('push block') ||
        lower.contains('match') ||
        lower.contains('undo') ||
        lower.contains('sokoban') ||
        lower.contains('hint')) {
      return 'puzzle';
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
        lower.contains('ore') ||
        lower.contains('brew') ||
        lower.contains('potion') ||
        lower.contains('haggle')) {
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
    String? beatGoal,
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
    final contextLower =
        '$cleanFeat ${beatTitle ?? ''} ${beatGoal ?? ''}'.toLowerCase();

    // Deduplicate secondary features like "Loadout Presets & Reroll" across different Epics
    if (lowerStripped == 'loadout presets & reroll' ||
        cleanFeat.toLowerCase().endsWith('loadout presets & reroll')) {
      if (contextLower.contains('upgrade') ||
          contextLower.contains('loot') ||
          contextLower.contains('resource') ||
          contextLower.contains('reward') ||
          contextLower.contains('choice') ||
          beatIndex == 2) {
        return 'Upgrade Reroll';
      }
      if (contextLower.contains('reset') ||
          contextLower.contains('clear') ||
          contextLower.contains('resolution') ||
          contextLower.contains('resolve') ||
          beatIndex == 3) {
        return 'Run Summary';
      }
      return 'Weapon Pedestal';
    }

    final isGenericMechanicsSuffix =
        lowerStripped == 'mechanics & controls' ||
        lowerStripped == 'core mechanics & controls' ||
        cleanFeat.toLowerCase().endsWith('mechanics & controls');

    if (!isGenericMechanicsSuffix) {
      if (stripped.contains(' & ')) {
        final firstPart = stripped.split(' & ').first.trim();
        if (firstPart.split(RegExp(r'\s+')).length >= 2) {
          return firstPart;
        }
      }
      return stripped;
    }

    if (contextLower.contains('deck') ||
        contextLower.contains('card') ||
        contextLower.contains('hand') ||
        contextLower.contains('mana')) {
      return 'Card Hand & Play';
    }
    if (contextLower.contains('vehicle') ||
        contextLower.contains('drift') ||
        contextLower.contains('steering') ||
        contextLower.contains('throttle')) {
      return 'Vehicle Drift Control';
    }
    if (contextLower.contains('stealth') ||
        contextLower.contains('vision cone') ||
        contextLower.contains('sneak')) {
      return 'Stealth Vision Cone';
    }
    if (contextLower.contains('puzzle') ||
        contextLower.contains('pressure plate') ||
        contextLower.contains('logic gate')) {
      return 'Puzzle Switch Link';
    }
    if (contextLower.contains('shield') || contextLower.contains('boss')) {
      return 'Boss Shield Break';
    }
    if (contextLower.contains('grappl') ||
        contextLower.contains('hook') ||
        contextLower.contains('swing') ||
        contextLower.contains('tether')) {
      return 'Grapple Hook';
    }
    if (contextLower.contains('entry') ||
        contextLower.contains('traversal') ||
        contextLower.contains('dash') ||
        contextLower.contains('locomotion') ||
        contextLower.contains('parkour')) {
      return 'Player Dash';
    }
    if (contextLower.contains('loadout') ||
        contextLower.contains('prep') ||
        contextLower.contains('staging') ||
        contextLower.contains('equip')) {
      return 'Weapon Equip';
    }
    if (contextLower.contains('hazard') ||
        contextLower.contains('enemy') ||
        contextLower.contains('escalation') ||
        contextLower.contains('counter')) {
      return 'Enemy Wave Spawner';
    }
    if (contextLower.contains('combat') ||
        contextLower.contains('weapon') ||
        contextLower.contains('shoot') ||
        contextLower.contains('fire') ||
        contextLower.contains('attack') ||
        contextLower.contains('active gameplay') ||
        contextLower.contains('gameplay beat') ||
        contextLower.contains('skill execution')) {
      return 'Weapon Firing';
    }
    if (contextLower.contains('drop') ||
        contextLower.contains('pickup') ||
        contextLower.contains('loot') ||
        contextLower.contains('tally')) {
      return 'Loot Pickup';
    }
    if (contextLower.contains('upgrade') ||
        contextLower.contains('reward') ||
        contextLower.contains('resource') ||
        contextLower.contains('perk') ||
        contextLower.contains('choice')) {
      return 'Upgrade Card Pick';
    }
    if (contextLower.contains('reset') ||
        contextLower.contains('resolution') ||
        contextLower.contains('resolve') ||
        contextLower.contains('next round') ||
        contextLower.contains('next wave') ||
        contextLower.contains('next-wave') ||
        contextLower.contains('clear')) {
      return 'Wave Reset';
    }
    if (contextLower.contains('crop') ||
        contextLower.contains('farm') ||
        contextLower.contains('plant') ||
        contextLower.contains('harvest')) {
      return 'Crop Plot Timer';
    }
    if (contextLower.contains('shop') ||
        contextLower.contains('buy') ||
        contextLower.contains('sell') ||
        contextLower.contains('smelt') ||
        contextLower.contains('craft') ||
        contextLower.contains('brew') ||
        contextLower.contains('potion')) {
      return 'Shop Purchase';
    }
    if (contextLower.contains('grid') ||
        contextLower.contains('build') ||
        contextLower.contains('place') ||
        contextLower.contains('tile')) {
      return 'Grid Placement';
    }

    // If the prefix before "Mechanics & Controls" has concrete words, preserve them!
    final prefixWithoutSuffix = cleanFeat
        .replaceFirst(
          RegExp(r'\s*(?:Core\s+)?Mechanics\s*&\s*Controls$', caseSensitive: false),
          '',
        )
        .trim();
    if (prefixWithoutSuffix.isNotEmpty &&
        prefixWithoutSuffix.toLowerCase() != 'core' &&
        !prefixWithoutSuffix.toLowerCase().startsWith('core loop beat')) {
      return prefixWithoutSuffix;
    }

    switch (beatIndex % 4) {
      case 0:
        return 'Weapon Equip';
      case 1:
        return 'Weapon Firing';
      case 2:
        return 'Upgrade Card Pick';
      default:
        return 'Wave Reset';
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
      case 'polish':
        return MechanicArchetypeProfile(
          category: 'polish',
          goal: 'Polish $clean with final art materials, spatial SFX, VFX particle cues, and a 60fps frame-time guard.',
          doneWhen: 'Player experiences $clean in the Gold Standard slice level with final materials, responsive SFX/VFX, and zero frame drops.',
          inScope: [
            'Final materials, shaders, and animation curves for $clean',
            'Spatial SFX, particle bursts, and HUD readout animations',
          ],
          outOfScope: [
            'Additional multi-level content rosters',
          ],
          tuningParams: const [
            'vfxBurstScale: 1.15 x',
            'sfxPitchVariance: 0.08',
            'hudTweenDuration: 0.14 s',
          ],
          edgeCases: const [
            '[FRAME-TIME GUARD] Pool particle and audio emitters so 60fps never drops during rapid action',
            '[VISUAL CLARITY GUARD] Keep hit-flash and screen-shake within readability bounds',
          ],
          cp1Title: '$clean · Visual, Audio & Feel Polish',
          cp1Playtest: 'Play through $clean in the Vertical Slice level -> final art, SFX pitch variance, VFX bursts, and HUD animations fire at 60fps.',
          cp1Tasks: [
            '01 · Final Art & Material Pass (1h)',
            '02 · SFX, VFX & Camera Feel Cues (1h)',
            '03 · HUD Polish & Frame-Time Guard (1h)',
          ],
          cp2Title: '$clean · Gold Standard Readability Pass',
          cp2Playtest: 'Trigger rapid actions in the Vertical Slice level -> audio/visual cues remain crisp with zero emitter clipping.',
          cp2Tasks: [
            '01 · Final Art & Material Pass (1h)',
            '02 · SFX, VFX & Camera Feel Cues (1h)',
            '03 · HUD Polish & Frame-Time Guard (1h)',
          ],
        );

      case 'content':
        return MechanicArchetypeProfile(
          category: 'content',
          goal: 'Expand $clean with data-driven content rosters, multi-wave/level scaling, and persistent run state.',
          doneWhen: 'Player progresses through multiple waves/levels using expanded $clean rosters and save-state persistence.',
          inScope: [
            'Data-table roster definitions and multi-tier variants for $clean',
            'Level/wave difficulty curve scaling and run-state save hooks',
          ],
          outOfScope: [
            'Post-launch expansion packs',
          ],
          tuningParams: const [
            'contentTierMultiplier: 1.25 x',
            'rosterSpawnWeight: 1.0',
            'progressionCurveExponent: 1.18',
          ],
          edgeCases: const [
            '[PROGRESSION GUARD] Clamp tier scaling at max level cap to prevent stat overflow',
            '[SAVE STATE GUARD] Persist unlocked roster state cleanly across level transitions',
          ],
          cp1Title: '$clean · Content Roster & Progression Scaling',
          cp1Playtest: 'Play through 3 consecutive waves/levels -> expanded $clean variants spawn and scale smoothly along progressionCurveExponent.',
          cp1Tasks: [
            '01 · Content Data Table & Roster Setup (2h)',
            '02 · Multi-Wave / Level Scaling Integration (2h)',
            '03 · Persistence & Progression Guard (1h)',
          ],
          cp2Title: '$clean · Full Production Polish & Balance',
          cp2Playtest: 'Complete a full multi-level run -> unlocked $clean tiers persist and balance curves hold steady.',
          cp2Tasks: [
            '01 · Content Data Table & Roster Setup (1h)',
            '02 · Multi-Wave / Level Scaling Integration (1h)',
            '03 · Persistence & Progression Guard (1h)',
          ],
        );

      case 'deckbuilder':
        return MechanicArchetypeProfile(
          category: 'deckbuilder',
          goal: 'Build $clean card draw, mana cost validation, target selection, and discard/reshuffle cycle.',
          doneWhen: 'Player draws a hand of cards, plays valid cards by spending mana, resolves card effects on targets, and cycles the discard pile cleanly.',
          inScope: [
            'Draw pile shuffle, hand slot layout, and mana cost validation for $clean',
            'Card play effect resolution, discard pile routing, and turn-end hand cycle',
          ],
          outOfScope: [
            'Online tournament deck-sharing codes and foil card shader packs',
          ],
          tuningParams: const [
            'startingHandSize: 5 cards',
            'turnManaMax: 3 mana',
            'cardDrawDelaySec: 0.12 s',
          ],
          edgeCases: const [
            '[EMPTY DRAW RESHUFFLE] Automatically shuffle discard pile into draw pile when draw count exceeds remaining cards',
            '[INSUFFICIENT MANA GUARD] Reject card play and shake mana crystal readout when cardCost > currentMana',
          ],
          cp1Title: '$clean Hand Draw & Card Play Resolution',
          cp1Playtest: 'Start turn and drag/click a card onto a valid target -> deducts mana, executes card effect, and moves card to discard pile.',
          cp1Tasks: [
            'Implement deck shuffle, startingHandSize draw, and mana check for $clean (2h)',
            'Resolve played card effect on target and route card to discard pile (2h)',
          ],
          cp2Title: '$clean Reshuffle Cycle & Card Hover Feel',
          cp2Playtest: 'Empty the draw pile and trigger another draw -> discard pile reshuffles seamlessly with card hover fan and audio cues.',
          cp2Tasks: [
            'Hook up card hover lift, play whoosh SFX, and mana crystal readout (1h)',
            'Enforce empty-draw reshuffle guard and turn-lock input guard (1h)',
          ],
        );

      case 'vehicle':
        return MechanicArchetypeProfile(
          category: 'vehicle',
          goal: 'Build $clean throttle acceleration, steering yaw torque, lateral drift grip, and boost release.',
          doneWhen: 'Player accelerates, initiates a controlled drift around corners, and releases a drift boost without spinning out or clipping.',
          inScope: [
            'Forward throttle force, speed-sensitive steering torque, and lateral slip damping for $clean',
            'Drift state entry, boost charge buildup, and tire trail / engine pitch cues',
          ],
          outOfScope: [
            'Soft-body chassis crumple deformation and pit-stop tire wear simulation',
          ],
          tuningParams: const [
            'maxForwardSpeed: 38.0 m/s',
            'driftGripFactor: 0.65',
            'boostImpulseMultiplier: 1.35 x',
          ],
          edgeCases: const [
            '[SPINOUT CLAMP] Clamp angular yaw velocity during sharp drift transitions so the vehicle never enters an unrecoverable spin',
            '[WALL SCRAPE GUARD] Project velocity along track barrier normals on glancing impacts instead of dead-stopping',
          ],
          cp1Title: '$clean Throttle, Steering & Drift Physics',
          cp1Playtest: 'Accelerate into a turn and hold Drift -> vehicle slides at driftGripFactor angle and releases boostImpulseMultiplier on exit.',
          cp1Tasks: [
            'Implement forward throttle acceleration and steering yaw torque for $clean (2h)',
            'Apply lateral driftGripFactor slip and exit boostImpulseMultiplier (2h)',
          ],
          cp2Title: '$clean Tire Trails, Engine Pitch & Wall-Scrape Guard',
          cp2Playtest: 'Drift against a track barrier at high speed -> vehicle slides along the barrier normal with skid marks and engine pitch ramp.',
          cp2Tasks: [
            'Hook up tire skid ribbons, engine RPM pitch modulation, and boost FOV kick (1h)',
            'Enforce angular spinout clamp and barrier wall-scrape projection guard (1h)',
          ],
        );

      case 'stealth':
        return MechanicArchetypeProfile(
          category: 'stealth',
          goal: 'Build $clean line-of-sight vision cone detection, suspicion meter buildup, and noise radius alerts.',
          doneWhen: 'Player sneaks past patrol vision cones, sees the suspicion gauge fill when exposed, and breaks line of sight to reset alert state.',
          inScope: [
            'Vision cone angle/distance check and obstacle occlusion raycast for $clean',
            'Suspicion meter buildup/decay, noise ring trigger, and alert state transitions',
          ],
          outOfScope: [
            'Dynamic cloth shadow GI raytracing and multi-faction diplomacy',
          ],
          tuningParams: const [
            'visionConeAngleDeg: 65.0 deg',
            'visionRangeMeters: 14.0 m',
            'suspicionFillRate: 0.85 /s',
          ],
          edgeCases: const [
            '[OCCLUSION RAY GUARD] Verify unobstructed raycast between watcher eye socket and player before incrementing suspicionFillRate',
            '[ALERT COOLDOWN DECAY] Decay suspicion smoothly after line of sight is broken for 2.0s without flickering between states',
          ],
          cp1Title: '$clean Vision Cone & Suspicion Meter',
          cp1Playtest: 'Step into patrol vision cone -> unobstructed raycast fills suspicion meter at suspicionFillRate and triggers Alert at 100%.',
          cp1Tasks: [
            'Implement visionConeAngleDeg check and obstacle occlusion raycast for $clean (2h)',
            'Drive suspicionFillRate meter buildup and Alert state transition (2h)',
          ],
          cp2Title: '$clean Cone Telegraph & LoS Break Decay',
          cp2Playtest: 'Duck behind cover before suspicion hits 100% -> cone tint shifts yellow-to-clear and suspicion decays cleanly.',
          cp2Tasks: [
            'Render vision cone ground decal tint, suspicion UI arc, and alert stinger (1h)',
            'Enforce cover occlusion ray guard and hysteresis cooldown decay (1h)',
          ],
        );

      case 'puzzle':
        return MechanicArchetypeProfile(
          category: 'puzzle',
          goal: 'Build $clean activator state evaluation, linked mechanism signaling, and instant puzzle reset.',
          doneWhen: 'Player activates puzzle elements in the test room, triggers the linked door/bridge when conditions are met, and can reset cleanly.',
          inScope: [
            'Activator trigger detection (pressure plate / switch / beam) and boolean signal emission for $clean',
            'Linked receiver evaluation, visual connection line, and 1-button room reset',
          ],
          outOfScope: [
            'Community workshop level sharing backend',
          ],
          tuningParams: const [
            'activationHoldDelaySec: 0.15 s',
            'signalPropagationSpeed: 18.0 m/s',
            'resetSnapDurationSec: 0.25 s',
          ],
          edgeCases: const [
            '[SIGNAL DEBOUNCE GUARD] Ignore physics jitter on pressure plates during activationHoldDelaySec so linked doors never rapid-toggle',
            '[CLEAN ROOM RESET] Resetting the puzzle restores all movable blocks and switches to initial transforms with zero residual velocity',
          ],
          cp1Title: '$clean Signal Link & Receiver Unlock',
          cp1Playtest: 'Activate $clean in the puzzle room -> signal line illuminates and unlocks the linked target mechanism.',
          cp1Tasks: [
            'Implement activator state check and signal emission for $clean (2h)',
            'Evaluate linked receiver conditions and trigger unlock state (2h)',
          ],
          cp2Title: '$clean Indicator Cues & Jitter Guard',
          cp2Playtest: 'Step on/off activator rapidly and trigger room reset -> signal debounce prevents flicker and reset restores initial state.',
          cp2Tasks: [
            'Hook up active wire/glyph illumination and solve chime for $clean (1h)',
            'Enforce activationHoldDelaySec debounce and zero-velocity room reset guard (1h)',
          ],
        );

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

  /// Returns a concise, mechanic-specific Task Group overline title (`01`, `02`, `03`)
  /// so the Flat Borderless Step Timeline names the actual system instead of generic "State Logic & Player Input".
  static String taskGroupTitle(
    String category,
    int taskIndex, {
    String fallbackTitle = '',
  }) {
    if (fallbackTitle.toUpperCase().startsWith('[FIX]') || taskIndex >= 3) {
      return fallbackTitle;
    }
    switch (category) {
      case 'loadout':
        return switch (taskIndex) {
          0 => 'Pedestal & Slots',
          1 => 'Equip & Socket',
          _ => 'HUD & Swap Guard',
        };
      case 'combat':
        return switch (taskIndex) {
          0 => 'Combat Actor & Hitbox',
          1 => 'Fire & Damage Math',
          _ => 'Hit-Flash & Guards',
        };
      case 'movement':
        return switch (taskIndex) {
          0 => 'Movement & Velocity',
          1 => 'Dash & Combo Chain',
          _ => 'FOV Kick & Guards',
        };
      case 'upgrade':
        return switch (taskIndex) {
          0 => 'Reward Chest & Data',
          1 => '3-Card Roll & Buff',
          _ => 'Pickup VFX & Lock',
        };
      case 'reset':
        return switch (taskIndex) {
          0 => 'Wave Manager Setup',
          1 => 'Clear & Wave Scale',
          _ => 'Banner & Cleanup',
        };
      case 'ui':
        return switch (taskIndex) {
          0 => 'Camera & HUD Setup',
          1 => 'Follow Lerp & Signal',
          _ => 'Callout & Bound Clamp',
        };
      case 'farming':
        return switch (taskIndex) {
          0 => 'Plot Tile & State',
          1 => 'Growth Timer & Yield',
          _ => 'Stage Swap & Guards',
        };
      case 'economy':
        return switch (taskIndex) {
          0 => 'Shop & Slot Data',
          1 => 'Cost & Inventory Math',
          _ => 'Readout & Cap Guard',
        };
      case 'building':
        return switch (taskIndex) {
          0 => 'Grid Cell & Snap',
          1 => 'Placement & Occupancy',
          _ => 'Ghost Tint & Guards',
        };
      case 'grapple':
        return switch (taskIndex) {
          0 => 'Hook Raycast & Anchor',
          1 => 'Pull Velocity & Swing',
          _ => 'Tether Line & Guards',
        };
      case 'deckbuilder':
        return switch (taskIndex) {
          0 => 'Deck & Hand Setup',
          1 => 'Mana & Card Play',
          _ => 'Reshuffle & Guards',
        };
      case 'vehicle':
        return switch (taskIndex) {
          0 => 'Chassis & Steering',
          1 => 'Drift & Boost Impulse',
          _ => 'Skid Cues & Guards',
        };
      case 'stealth':
        return switch (taskIndex) {
          0 => 'Vision Cone & Raycast',
          1 => 'Suspicion & Alert State',
          _ => 'Cone Decal & Decay Guard',
        };
      case 'puzzle':
        return switch (taskIndex) {
          0 => 'Activator & Signal',
          1 => 'Receiver Unlock Logic',
          _ => 'Wire Cues & Reset Guard',
        };
      case 'polish':
        return switch (taskIndex) {
          0 => 'Art & Material Pass',
          1 => 'SFX, VFX & Camera Feel',
          _ => 'HUD & Frame Guard',
        };
      case 'content':
        return switch (taskIndex) {
          0 => 'Content Data & Roster',
          1 => 'Wave & Level Scaling',
          _ => 'Save State & Bounds Guard',
        };
      default:
        return fallbackTitle.isNotEmpty
            ? fallbackTitle
            : switch (taskIndex) {
                0 => 'Actor & Base Setup',
                1 => 'Input & Core Logic',
                _ => 'Feedback & Guards',
              };
    }
  }

  /// Resolves domain-specific Step titles, instructions, verification checks, and code comments
  /// across all 3 Task Groups (`01`, `02`, `03`) for each mechanic archetype.
  static ({
    String stepHeader,
    String shortTitle,
    String instruction,
    String verify,
    String codeLead,
  })? mechanicStepOverride({
    required String category,
    required int taskIndex,
    required int stepIdx,
    required int taskNum,
    required String targetAsset,
    required String primaryVarName,
  }) {
    if (category == 'core' || stepIdx < 0 || stepIdx > 4) return null;
    final grp = taskIndex.clamp(0, 2);

    ({String title, String instr, String verify, String codeLead})? entry;

    switch (category) {
      case 'loadout':
        entry = switch ((grp, stepIdx)) {
          (0, 0) => (
              title: 'Create $targetAsset Class',
              instr: 'Create $targetAsset and define the weapon and ability slot fields (EquippedWeaponId, CurrentAmmo, bIsSlotReady).',
              verify: '$targetAsset compiles cleanly with weapon slot properties ready in the editor.',
              codeLead: '// Loadout Slot Data on $targetAsset',
            ),
          (0, 1) => (
              title: 'Add Pedestal Mesh & Overlap Box',
              instr: 'Attach the pedestal VisualMesh and InteractBox trigger volume to $targetAsset so players can step up to equip.',
              verify: 'Pedestal mesh and InteractBox wireframe appear aligned in the viewport.',
              codeLead: '// Pedestal Mesh + Overlap Trigger Volume',
            ),
          (0, 2) => (
              title: 'Place Pedestal in Staging Zone',
              instr: 'Compile and place $targetAsset inside the starting staging room near the arena entry gate.',
              verify: '$targetAsset is positioned in the staging area and listed in the scene outliner.',
              codeLead: '// Staging Zone Pedestal Placement',
            ),
          (0, 3) => (
              title: 'Expose $primaryVarName in Inspector',
              instr: 'Expose $primaryVarName on $targetAsset so designers can tune starting ammo and swap timing live.',
              verify: 'Selecting $targetAsset shows $primaryVarName as an editable field in the Details/Inspector panel.',
              codeLead: '// Loadout Tuning Parameter: $primaryVarName',
            ),
          (0, _) => (
              title: 'Initialize Starting Weapon Slots',
              instr: 'Populate the default weapon/ability slot state on startup using $primaryVarName.',
              verify: 'Pressing Play initializes $targetAsset with valid default slot values from $primaryVarName.',
              codeLead: '// Initialize Default Weapon Slots ($primaryVarName)',
            ),
          (1, 0) => (
              title: 'Detect Pedestal Overlap',
              instr: 'Bind the InteractBox overlap event on $targetAsset to detect when the player enters equip range.',
              verify: 'Walking up to $targetAsset registers player overlap and highlights the active pedestal.',
              codeLead: '// Detect Player Overlap at Weapon Pedestal',
            ),
          (1, 1) => (
              title: 'Bind Interact & Validate Slot',
              instr: 'When the player presses Interact at $targetAsset, verify the target weapon slot is unlocked and ready to equip.',
              verify: 'Pressing Interact near $targetAsset validates the slot and fires the equip handler.',
              codeLead: '// Validate Target Weapon Slot on Interact',
            ),
          (1, 2) => (
              title: 'Attach Weapon Actor to Hand Socket',
              instr: 'Attach the chosen weapon actor/mesh to the player character\'s WeaponSocket and update the active loadout reference.',
              verify: 'Interacting with $targetAsset visibly attaches the weapon to the player\'s hand socket on screen.',
              codeLead: '// Attach Equipped Weapon to Player Hand Socket',
            ),
          (1, 3) => (
              title: 'Apply $primaryVarName & Swap Cooldown',
              instr: 'Set the equipped weapon\'s starting ammo/cooldown from $primaryVarName when the swap completes.',
              verify: 'Equipped weapon initializes its ammo and swap timer directly from $primaryVarName.',
              codeLead: '// Apply $primaryVarName to Equipped Loadout Slot',
            ),
          (1, _) => (
              title: 'Unlock Arena Launch Trigger',
              instr: 'Mark the player loadout as ready on $targetAsset so stepping into the arena launch volume starts Round 1.',
              verify: 'Equipping a primary weapon unlocks the arena launch trigger and transitions smoothly.',
              codeLead: '// Enable Arena Entry Trigger Once Armed ($primaryVarName)',
            ),
          (_, 0) => (
              title: 'Bind Loadout HUD Dispatcher',
              instr: 'Connect $targetAsset\'s OnWeaponEquipped signal/event to the active HUD weapon slot controller.',
              verify: 'Equipping a weapon on $targetAsset broadcasts the updated slot payload to the HUD.',
              codeLead: '// Broadcast OnWeaponEquipped to HUD Controller',
            ),
          (_, 1) => (
              title: 'Sync HUD Weapon Icon & Ammo Readout',
              instr: 'Update the HUD weapon icon and ammo counter text immediately whenever the active slot changes.',
              verify: 'Swapping weapons at $targetAsset updates the on-screen HUD icon and ammo count in real time.',
              codeLead: '// Sync HUD Weapon Slot Icon & Ammo Counter',
            ),
          (_, 2) => (
              title: 'Trigger Equip SFX & Socket Flash',
              instr: 'Play the weapon-equip audio cue and socket flash effect on $targetAsset when a weapon locks into place.',
              verify: 'Picking up a weapon plays the equip sound and visual flash without delay.',
              codeLead: '// Play Weapon Equip Audio & Socket Flash Cue',
            ),
          (_, 3) => (
              title: 'Bind $primaryVarName Cooldown Indicator',
              instr: 'Drive the HUD swap-cooldown bar and pedestal prompt readiness using $primaryVarName.',
              verify: 'The HUD swap indicator reflects $primaryVarName timing accurately during swaps.',
              codeLead: '// Drive HUD Swap Cooldown Readout ($primaryVarName)',
            ),
          (_, _) => (
              title: 'Verify Rapid Pedestal Swap Flow',
              instr: 'Test rapid interact presses across pedestals to confirm clean weapon swapping and HUD sync.',
              verify: 'Rapidly swapping weapons updates the player hand socket and HUD with zero duplicate actors.',
              codeLead: '// Verify Rapid Pedestal Swap & Cooldown ($primaryVarName)',
            ),
        };
      case 'combat':
        entry = switch ((grp, stepIdx)) {
          (0, 0) => (
              title: 'Create $targetAsset Combat Class',
              instr: 'Create $targetAsset to manage weapon firing, muzzle origin, and target hit registration.',
              verify: '$targetAsset compiles cleanly and appears in your project scripts/blueprints folder.',
              codeLead: '// Combat Actor & Weapon Firing Foundation ($targetAsset)',
            ),
          (0, 1) => (
              title: 'Add Muzzle Origin & Hitbox Sensor',
              instr: 'Attach the weapon VisualMesh, MuzzleSocket origin point, and InteractBox hitbox collision sensor to $targetAsset.',
              verify: 'Weapon mesh, muzzle point, and hitbox wireframe appear properly aligned in the viewport.',
              codeLead: '// Attach Weapon Mesh, MuzzleSocket & Hitbox Sensor',
            ),
          (0, 2) => (
              title: 'Place $targetAsset in Arena Viewport',
              instr: 'Place $targetAsset inside the combat arena level alongside test enemy targets.',
              verify: '$targetAsset is spawned in the arena viewport and ready for live fire testing.',
              codeLead: '// Spawn $targetAsset in Combat Arena',
            ),
          (0, 3) => (
              title: 'Expose $primaryVarName Combat Tuning',
              instr: 'Expose $primaryVarName on $targetAsset so damage, fire cadence, or wave count can be tuned live.',
              verify: 'Selecting $targetAsset in the arena shows $primaryVarName in the Inspector/Details panel.',
              codeLead: '// Combat Tuning Parameter: $primaryVarName',
            ),
          (0, _) => (
              title: 'Initialize Fire Timer & Ammo State',
              instr: 'Initialize the fire-rate timer and active combat readiness on $targetAsset using $primaryVarName.',
              verify: '$targetAsset starts Play mode with full ammo and fire timer calibrated to $primaryVarName.',
              codeLead: '// Initialize Fire Cadence & Ammo State ($primaryVarName)',
            ),
          (1, 0) => (
              title: 'Bind Primary Fire & Aim Input',
              instr: 'Bind primary fire input and read the normalized aim direction vector on $targetAsset.',
              verify: 'Pressing Fire reads the player\'s current aim vector and triggers the fire handler.',
              codeLead: '// Bind Primary Fire & Aim Vector Input',
            ),
          (1, 1) => (
              title: 'Fire Projectile / Raycast Hit Query',
              instr: 'Spawn a projectile or cast a hit trace from MuzzleSocket along the aim vector to detect enemy hitboxes.',
              verify: 'Firing projects a trace/projectile from MuzzleSocket and detects impacts on arena targets.',
              codeLead: '// Fire Projectile / Raycast from MuzzleSocket',
            ),
          (1, 2) => (
              title: 'Apply $primaryVarName Damage & Knockback',
              instr: 'On target impact, subtract enemy health using $primaryVarName and apply knockback impulse along the hit normal.',
              verify: 'Hitting an enemy reduces its HP by $primaryVarName and pushes it back visibly.',
              codeLead: '// Apply Damage ($primaryVarName) & Knockback Impulse',
            ),
          (1, 3) => (
              title: 'Wire $primaryVarName Fire Cadence',
              instr: 'Gate consecutive shots using $primaryVarName so holding or tapping Fire respects the weapon fire rate.',
              verify: 'Holding Fire shoots at a steady cadence governed by $primaryVarName.',
              codeLead: '// Enforce Fire-Rate Cadence ($primaryVarName)',
            ),
          (1, _) => (
              title: 'Step Recoil Recovery & Aim Velocity',
              instr: 'Interpolate weapon recoil recovery and combat strafe velocity each physics tick using $primaryVarName.',
              verify: 'Firing while moving recovers reticle spread smoothly using $primaryVarName.',
              codeLead: '// Step Combat Velocity & Recoil Recovery ($primaryVarName)',
            ),
          (_, 0) => (
              title: 'Bind Target Hit Confirmation Signal',
              instr: 'Connect the impact hit event on $targetAsset to trigger immediate visual and audio combat cues.',
              verify: 'Every confirmed hit fires the impact feedback handler on $targetAsset.',
              codeLead: '// Connect Hit Confirmation Event on $targetAsset',
            ),
          (_, 1) => (
              title: 'Flash Target Material on Impact',
              instr: 'Trigger a crisp emissive white hit-flash on the struck enemy mesh when damage lands.',
              verify: 'Struck targets flash white briefly on impact before returning to their base color.',
              codeLead: '// Trigger 60ms Emissive Hit-Flash on Struck Target',
            ),
          (_, 2) => (
              title: 'Spawn Muzzle Flash & Impact Sparks',
              instr: 'Spawn a muzzle flash and impact particle burst at the hit point alongside the gunshot/hit audio cue.',
              verify: 'Firing and hitting a target plays both the muzzle cue and impact spark burst on screen.',
              codeLead: '// Spawn Impact Sparks & Play Hit-Confirm SFX',
            ),
          (_, 3) => (
              title: 'Scale Hitstop & Shake by $primaryVarName',
              instr: 'Use $primaryVarName to scale brief impact hitstop and camera punch on heavy hits.',
              verify: 'Adjusting $primaryVarName visibly tunes impact punch during arena combat.',
              codeLead: '// Scale Hitstop & Camera Punch ($primaryVarName)',
            ),
          (_, _) => (
              title: 'Verify Multi-Target Hit Registration',
              instr: 'Fire across multiple enemy targets in Play mode to confirm clean hit registration and knockback.',
              verify: 'Rapid shots across multiple enemies register damage and hit-flashes without dropped hits.',
              codeLead: '// Verify Multi-Target Hit Registration ($primaryVarName)',
            ),
        };
      case 'movement':
        entry = switch ((grp, stepIdx)) {
          (0, 0) => (
              title: 'Create $targetAsset Locomotion Class',
              instr: 'Create $targetAsset to drive player movement velocity, dash burst, and combo speed scaling.',
              verify: '$targetAsset compiles cleanly and is ready to attach to the player pawn.',
              codeLead: '// Player Locomotion & Dash Controller ($targetAsset)',
            ),
          (0, 1) => (
              title: 'Add Capsule Collider & Ground Sensor',
              instr: 'Attach the character VisualMesh and InteractBox collision/ground sensor to $targetAsset.',
              verify: 'Character mesh and collision bounds appear centered in the viewport.',
              codeLead: '// Attach Collision Capsule & Ground Check Sensor',
            ),
          (0, 2) => (
              title: 'Place $targetAsset at Arena Spawn',
              instr: 'Place $targetAsset at the arena spawn marker (0, 0, 0) for immediate movement testing.',
              verify: '$targetAsset spawns cleanly on the arena floor when entering Play mode.',
              codeLead: '// Spawn $targetAsset at Arena Start Point',
            ),
          (0, 3) => (
              title: 'Expose $primaryVarName Speed Tuning',
              instr: 'Expose $primaryVarName on $targetAsset so top speed, acceleration, or dash impulse can be tuned live.',
              verify: '$primaryVarName appears in the Inspector/Details panel when $targetAsset is selected.',
              codeLead: '// Movement Tuning Variable: $primaryVarName',
            ),
          (0, _) => (
              title: 'Apply Base WASD Acceleration',
              instr: 'Read directional movement input each physics tick and accelerate $targetAsset smoothly toward $primaryVarName.',
              verify: 'Pressing WASD moves $targetAsset smoothly across the arena floor at $primaryVarName.',
              codeLead: '// Step Base WASD Velocity ($primaryVarName)',
            ),
          (1, 0) => (
              title: 'Bind Dash & Directional Input',
              instr: 'Bind the Dash / Burst input action on $targetAsset and capture the current movement direction vector.',
              verify: 'Pressing Dash captures the active input direction and triggers the burst state.',
              codeLead: '// Bind Dash Input & Capture Direction Vector',
            ),
          (1, 1) => (
              title: 'Apply Dash Velocity Impulse',
              instr: 'Launch $targetAsset along the input vector with burst velocity and start the active dash window.',
              verify: 'Pressing Dash propels $targetAsset forward with a crisp burst of speed.',
              codeLead: '// Apply Dash Burst Velocity Impulse',
            ),
          (1, 2) => (
              title: 'Chain Combo Speed Multiplier',
              instr: 'Increment the combo speed stack when chaining actions within the timing window and update move speed.',
              verify: 'Chaining dashes/hits in rhythm increases movement speed visibly across the arena.',
              codeLead: '// Increment Combo Chain Speed Multiplier',
            ),
          (1, 3) => (
              title: 'Wire $primaryVarName Dash Cooldown',
              instr: 'Drive the dash recharge timer and combo decay window using $primaryVarName.',
              verify: 'Dash cooldown recovers cleanly according to $primaryVarName.',
              codeLead: '// Tick Dash Cooldown & Combo Window ($primaryVarName)',
            ),
          (1, _) => (
              title: 'Interpolate Deceleration & Turn Grip',
              instr: 'Smoothly interpolate velocity from dash burst back to cruise speed each frame using $primaryVarName.',
              verify: 'Exiting a dash transitions smoothly into normal run speed without snapping.',
              codeLead: '// Interpolate Dash Recovery Velocity ($primaryVarName)',
            ),
          (_, 0) => (
              title: 'Bind Dash Start & Recovery Signals',
              instr: 'Emit dash start and recovery events from $targetAsset to drive camera FOV and trail effects.',
              verify: 'Triggering a dash fires the visual feedback signal on $targetAsset.',
              codeLead: '// Emit Dash Start / Recovery Visual Signals',
            ),
          (_, 1) => (
              title: 'Lerp Camera FOV Kick on Burst',
              instr: 'Punch camera FOV outward during dash burst and ease back smoothly as velocity settles.',
              verify: 'Dashing produces a responsive camera FOV kick that settles cleanly.',
              codeLead: '// Lerp Camera FOV Kick During Dash Burst',
            ),
          (_, 2) => (
              title: 'Activate Speed Trail & Whoosh SFX',
              instr: 'Enable the motion trail emitter and play the dash whoosh audio cue while burst speed is active.',
              verify: 'Dashing leaves a visible speed trail and plays the burst sound cue.',
              codeLead: '// Toggle Speed Trail Emitter & Dash SFX',
            ),
          (_, 3) => (
              title: 'Tune $primaryVarName Wall-Slide Projection',
              instr: 'Use $primaryVarName to slide velocity smoothly along wall normals when dashing into angled geometry.',
              verify: 'Dashing at a 45° angle into an arena wall slides smoothly along the surface.',
              codeLead: '// Project Velocity Along Wall Normal ($primaryVarName)',
            ),
          (_, _) => (
              title: 'Verify Jump-Cancel & Corner Slide',
              instr: 'Test jump-canceling mid-dash and sliding along arena corners to verify velocity preservation.',
              verify: 'Corner slides and jump-cancels preserve momentum without snagging or clipping.',
              codeLead: '// Verify Corner Slide & Dash Cancel ($primaryVarName)',
            ),
        };
      case 'upgrade':
        entry = switch ((grp, stepIdx)) {
          (0, 0) => (
              title: 'Create $targetAsset & Upgrade Struct',
              instr: 'Create $targetAsset and define the upgrade option struct (UpgradeId, StatTarget, BuffMultiplier).',
              verify: '$targetAsset compiles cleanly with the upgrade pool data fields defined.',
              codeLead: '// Upgrade Reward Actor & Card Data ($targetAsset)',
            ),
          (0, 1) => (
              title: 'Add Reward Chest Mesh & Pickup Zone',
              instr: 'Attach the reward chest/altar VisualMesh and InteractBox trigger volume to $targetAsset.',
              verify: 'Reward chest mesh and pickup trigger box appear in the viewport.',
              codeLead: '// Attach Reward Chest Mesh & Pickup Trigger',
            ),
          (0, 2) => (
              title: 'Place $targetAsset at Arena Center',
              instr: 'Place $targetAsset at the arena center reward spawn point so it activates on wave clear.',
              verify: '$targetAsset sits at the arena reward point and is listed in the scene hierarchy.',
              codeLead: '// Place $targetAsset at Center Arena Reward Point',
            ),
          (0, 3) => (
              title: 'Expose $primaryVarName Buff Tuning',
              instr: 'Expose $primaryVarName on $targetAsset to tune option count, stat multiplier, or reroll cost.',
              verify: '$primaryVarName is editable in the Inspector/Details panel on $targetAsset.',
              codeLead: '// Upgrade Tuning Parameter: $primaryVarName',
            ),
          (0, _) => (
              title: 'Initialize Candidate Upgrade Pool',
              instr: 'Populate the weighted list of stat/weapon upgrades on $targetAsset driven by $primaryVarName.',
              verify: '$targetAsset initializes its candidate upgrade pool with valid stat modifiers on startup.',
              codeLead: '// Initialize Weighted Upgrade Pool ($primaryVarName)',
            ),
          (1, 0) => (
              title: 'Roll 3 Non-Duplicate Upgrades on Clear',
              instr: 'When a wave clears, roll 3 distinct upgrade options from $targetAsset\'s candidate pool.',
              verify: 'Clearing a wave rolls 3 unique upgrade choices with zero duplicate cards.',
              codeLead: '// Roll 3 Non-Duplicate Upgrade Options on Wave Clear',
            ),
          (1, 1) => (
              title: 'Present 3 Selectable Upgrade Cards',
              instr: 'Display the 3 rolled upgrade cards with their title, icon, and exact stat modifier percentage.',
              verify: 'All 3 upgrade cards appear on screen and highlight when hovered or approached.',
              codeLead: '// Populate 3 Selectable Upgrade Card Slots',
            ),
          (1, 2) => (
              title: 'Apply Chosen Stat Multiplier to Player',
              instr: 'When the player selects a card on $targetAsset, immediately multiply the target player stat (damage, fire rate, or speed).',
              verify: 'Picking an upgrade card immediately boosts the player\'s active stat in the arena.',
              codeLead: '// Apply Selected Stat Multiplier to Player',
            ),
          (1, 3) => (
              title: 'Scale Buff Magnitude by $primaryVarName',
              instr: 'Calculate the applied stat delta using $primaryVarName and refresh the choices if Reroll is pressed.',
              verify: 'Stat buffs scale accurately by $primaryVarName and rerolling deals 3 fresh cards.',
              codeLead: '// Compute Stat Buff Delta ($primaryVarName) & Reroll',
            ),
          (1, _) => (
              title: 'Despawn Unchosen Rewards & Resume',
              instr: 'Despawn the remaining unchosen upgrade options on $targetAsset and signal the next arena wave.',
              verify: 'Selecting 1 card despawns the other 2 options immediately and resumes gameplay.',
              codeLead: '// Despawn Unchosen Cards & Advance Loop ($primaryVarName)',
            ),
          (_, 0) => (
              title: 'Bind Upgrade Claimed Event',
              instr: 'Connect $targetAsset\'s OnUpgradeClaimed event to the HUD buff bar and audio player.',
              verify: 'Claiming an upgrade fires the HUD notification and audio handler.',
              codeLead: '// Broadcast OnUpgradeClaimed to HUD & Audio',
            ),
          (_, 1) => (
              title: 'Spawn Claim Burst VFX & +Stat Popup',
              instr: 'Spawn a pickup particle burst and floating "+Stat%" callout text when an upgrade is claimed.',
              verify: 'Picking an upgrade spawns the burst VFX and floating stat popup on screen.',
              codeLead: '// Spawn Upgrade Claim VFX & Floating Stat Callout',
            ),
          (_, 2) => (
              title: 'Add Active Buff Badge to HUD Row',
              instr: 'Append the chosen upgrade\'s icon and stack count to the player\'s active HUD buff bar.',
              verify: 'The claimed upgrade badge appears in the HUD buff bar and increments on stack.',
              codeLead: '// Add Claimed Upgrade Badge to HUD Buff Bar',
            ),
          (_, 3) => (
              title: 'Sync $primaryVarName Reroll & Stack Cap',
              instr: 'Update the reroll cost readout and clamp stacked stat multipliers using $primaryVarName.',
              verify: 'Stacked upgrades respect the safety cap defined by $primaryVarName.',
              codeLead: '// Clamp Stacked Buffs & Sync Reroll ($primaryVarName)',
            ),
          (_, _) => (
              title: 'Verify Single-Claim Lock on Pickup',
              instr: 'Test spamming interact or overlapping two cards simultaneously to confirm only 1 upgrade can be claimed.',
              verify: 'Simultaneous inputs claim exactly 1 upgrade and lock out duplicate picks.',
              codeLead: '// Verify Single-Claim Lock ($primaryVarName)',
            ),
        };
      case 'reset':
        entry = switch ((grp, stepIdx)) {
          (0, 0) => (
              title: 'Create $targetAsset Wave Manager',
              instr: 'Create $targetAsset to track active enemy count, current wave index, and round reset state.',
              verify: '$targetAsset compiles cleanly with wave counter and reset state properties.',
              codeLead: '// Wave Clear & Loop Reset Manager ($targetAsset)',
            ),
          (0, 1) => (
              title: 'Add Arena Bounds & Spawn Markers',
              instr: 'Attach the arena boundary volume and enemy wave spawn point references to $targetAsset.',
              verify: 'Spawn markers and arena bounds are linked to $targetAsset in the viewport.',
              codeLead: '// Link Arena Bounds & Wave Spawn Markers',
            ),
          (0, 2) => (
              title: 'Place $targetAsset in Arena Level',
              instr: 'Place $targetAsset in the main arena level and link the player respawn transform.',
              verify: '$targetAsset is active in the level outliner with valid spawn point references.',
              codeLead: '// Register $targetAsset in Main Arena Level',
            ),
          (0, 3) => (
              title: 'Expose $primaryVarName Wave Tuning',
              instr: 'Expose $primaryVarName on $targetAsset to tune inter-wave countdown delay and enemy scaling.',
              verify: '$primaryVarName is editable in the Details/Inspector panel for $targetAsset.',
              codeLead: '// Wave Reset Tuning Parameter: $primaryVarName',
            ),
          (0, _) => (
              title: 'Initialize Wave 1 Counter & Timer',
              instr: 'Initialize CurrentWave = 1 and reset the active enemy counter on startup using $primaryVarName.',
              verify: 'Entering Play mode starts Wave 1 cleanly with enemy counts tracked by $targetAsset.',
              codeLead: '// Initialize Wave 1 State & Timer ($primaryVarName)',
            ),
          (1, 0) => (
              title: 'Detect Zero Remaining Enemies',
              instr: 'Decrement ActiveEnemyCount on each enemy elimination and fire OnWaveCleared when it reaches 0.',
              verify: 'Defeating the last enemy in a wave immediately triggers OnWaveCleared on $targetAsset.',
              codeLead: '// Detect Final Enemy Elimination -> OnWaveCleared',
            ),
          (1, 1) => (
              title: 'Increment Wave Index & Scale Spawn Count',
              instr: 'Advance CurrentWaveIndex and scale the next wave\'s enemy count/HP multiplier.',
              verify: 'Wave counter increments (Wave 1 -> Wave 2) and calculates the scaled spawn count.',
              codeLead: '// Increment Wave Counter & Scale Next Wave Cohort',
            ),
          (1, 2) => (
              title: 'Sweep & Destroy Orphan Projectiles',
              instr: 'Clear all leftover enemy projectiles, hazards, and temporary debris from the arena on wave end.',
              verify: 'All active projectiles and hazards are destroyed cleanly when the round ends.',
              codeLead: '// Destroy Leftover Projectiles & Arena Hazards',
            ),
          (1, 3) => (
              title: 'Run $primaryVarName Inter-Wave Countdown',
              instr: 'Tick the inter-wave breather countdown using $primaryVarName before spawning the next wave.',
              verify: 'Next wave waits $primaryVarName after wave clear before spawning enemies.',
              codeLead: '// Run Inter-Wave Countdown Timer ($primaryVarName)',
            ),
          (1, _) => (
              title: 'Spawn Next Wave or 1-Key Run Reset',
              instr: 'Spawn the next wave cohort when the countdown finishes, or reset to Wave 1 in 1 keypress on player death.',
              verify: 'Next wave spawns cleanly after $primaryVarName, and pressing Restart resets the run in under 1s.',
              codeLead: '// Spawn Next Wave Cohort / Instant Run Reset ($primaryVarName)',
            ),
          (_, 0) => (
              title: 'Bind Wave Clear & Run Summary Signals',
              instr: 'Connect OnWaveCleared and OnRunReset from $targetAsset to the HUD banner controller.',
              verify: 'Clearing a wave or ending a run notifies the HUD overlay immediately.',
              codeLead: '// Connect Wave Clear & Reset Signals to HUD',
            ),
          (_, 1) => (
              title: 'Animate Wave Clear Banner & Tally',
              instr: 'Display the "WAVE CLEARED" / run summary banner with clear time and enemies defeated.',
              verify: 'The Wave Clear banner animates on screen with accurate round stats.',
              codeLead: '// Display Wave Clear Banner & Run Tally',
            ),
          (_, 2) => (
              title: 'Bind 1-Key Instant Restart Shortcut',
              instr: 'Bind the quick-restart input (R / Gamepad Start) so playtesters can restart a run immediately.',
              verify: 'Pressing the restart shortcut resets player health, ammo, and Wave 1 state in under 1s.',
              codeLead: '// Bind 1-Key Instant Run Restart Input',
            ),
          (_, 3) => (
              title: 'Sync $primaryVarName Countdown Readout',
              instr: 'Update the on-screen "Next Wave in X.Xs" HUD countdown text from $primaryVarName.',
              verify: 'The HUD countdown ticks down smoothly from $primaryVarName to 0.0s.',
              codeLead: '// Sync Next-Wave HUD Countdown ($primaryVarName)',
            ),
          (_, _) => (
              title: 'Verify 3 Consecutive Wave Resets',
              instr: 'Play through and reset 3 consecutive waves in the viewport to confirm zero leftover actors or duplicate timers.',
              verify: '3 consecutive wave clears and resets run with stable frame time and zero orphan actors.',
              codeLead: '// Verify 3-Wave Reset Stability ($primaryVarName)',
            ),
        };
      case 'ui':
        entry = switch ((grp, stepIdx)) {
          (0, 0) => (
              title: 'Create $targetAsset Camera & HUD Rig',
              instr: 'Create $targetAsset to manage smooth camera tracking and live HUD state readouts.',
              verify: '$targetAsset compiles cleanly and is ready to attach to the active viewport.',
              codeLead: '// Camera Follow & HUD Readout Controller ($targetAsset)',
            ),
          (0, 1) => (
              title: 'Add Camera Arm & HUD Canvas Layer',
              instr: 'Attach the camera spring-arm/node and root HUD status container to $targetAsset.',
              verify: 'Camera view and HUD overlay container render cleanly in the editor preview.',
              codeLead: '// Attach Camera Rig & Root HUD Container',
            ),
          (0, 2) => (
              title: 'Register $targetAsset in Main Level',
              instr: 'Place $targetAsset in the arena level and bind it to track the spawned player actor.',
              verify: '$targetAsset locks onto the player pawn as soon as Play mode starts.',
              codeLead: '// Register $targetAsset & Bind Player Target',
            ),
          (0, 3) => (
              title: 'Expose $primaryVarName Lerp Speed',
              instr: 'Expose $primaryVarName on $targetAsset to tune camera follow smoothing and HUD pop scale.',
              verify: '$primaryVarName appears in the Inspector/Details panel for $targetAsset.',
              codeLead: '// Camera & HUD Tuning Parameter: $primaryVarName',
            ),
          (0, _) => (
              title: 'Initialize Target Anchor & Arena Bounds',
              instr: 'Cache the player transform anchor and arena boundary min/max limits on startup using $primaryVarName.',
              verify: '$targetAsset initializes with valid arena bounds and zero camera snap on spawn.',
              codeLead: '// Initialize Camera Anchor & Arena Bounds ($primaryVarName)',
            ),
          (1, 0) => (
              title: 'Subscribe to Player Ammo & State Signals',
              instr: 'Connect player weapon, ammo, and wave state signals to $targetAsset.',
              verify: 'Player actions immediately notify $targetAsset without polling every node.',
              codeLead: '// Subscribe $targetAsset to Player State Signals',
            ),
          (1, 1) => (
              title: 'Lerp Camera Position Toward Player',
              instr: 'Smoothly interpolate camera position toward the player anchor each tick using $primaryVarName.',
              verify: 'Moving and dashing across the arena tracks the player smoothly without camera judder.',
              codeLead: '// Lerp Camera Transform Toward Player ($primaryVarName)',
            ),
          (1, 2) => (
              title: 'Update HUD Ammo, Health & Wave Readout',
              instr: 'Refresh the HUD ammo counter, health bar, and wave badge whenever state signals fire.',
              verify: 'Firing, taking damage, or clearing a wave updates the HUD readout on the same frame.',
              codeLead: '// Refresh HUD Ammo, Health & Wave Counters',
            ),
          (1, 3) => (
              title: 'Apply $primaryVarName Aim Look-Ahead',
              instr: 'Offset the camera focus slightly toward the player\'s aim direction scaled by $primaryVarName.',
              verify: 'Aiming shifts camera framing smoothly toward the target area.',
              codeLead: '// Apply Aim Look-Ahead Offset ($primaryVarName)',
            ),
          (1, _) => (
              title: 'Clamp Camera at Arena Boundaries',
              instr: 'Clamp the interpolated camera coordinates inside the arena bounds so the view never shows empty void.',
              verify: 'Walking to the edge of the arena clamps the camera smoothly at the boundary wall.',
              codeLead: '// Clamp Camera Coordinates to Arena Bounds ($primaryVarName)',
            ),
          (_, 0) => (
              title: 'Bind Critical State Callout Trigger',
              instr: 'Detect low-ammo, reload, or medal threshold events in $targetAsset to trigger HUD callouts.',
              verify: 'Crossing a state threshold triggers the HUD callout animation handler.',
              codeLead: '// Trigger HUD Callout on State Threshold',
            ),
          (_, 1) => (
              title: 'Animate HUD Pop Scale & Reticle Flash',
              instr: 'Pulse the HUD counter scale and reticle tint briefly when state changes or hits occur.',
              verify: 'HUD counters pop cleanly on update and settle back to 1.0x scale.',
              codeLead: '// Pulse HUD Counter Scale & Reticle Cue',
            ),
          (_, 2) => (
              title: 'Trigger Audio Chime & Edge Vignette',
              instr: 'Play the UI confirmation chime and subtle screen-edge vignette when a callout fires.',
              verify: 'State callouts play crisp audio/visual feedback without obscuring the crosshair.',
              codeLead: '// Play UI Chime & Screen-Edge Vignette Cue',
            ),
          (_, 3) => (
              title: 'Decay Shake Trauma with $primaryVarName',
              instr: 'Decay camera shake trauma smoothly back to rest each frame using $primaryVarName.',
              verify: 'Camera shake recovers smoothly to rest with zero lingering jitter.',
              codeLead: '// Decay Camera Shake Trauma ($primaryVarName)',
            ),
          (_, _) => (
              title: 'Verify Tracking at High Dash Speeds',
              instr: 'Dash rapidly into arena corners while firing to verify smooth camera clamping and HUD sync.',
              verify: 'High-speed movement at arena boundaries stays locked at 60fps with zero camera snap.',
              codeLead: '// Verify Corner Clamping & HUD Sync ($primaryVarName)',
            ),
        };
      case 'polish':
        entry = switch ((grp, stepIdx)) {
          (0, 0) => (
              title: 'Swap Greybox Mesh for Final $targetAsset Art',
              instr: 'Replace the greybox proxy mesh on $targetAsset with the final production mesh and LOD group.',
              verify: '$targetAsset renders with final silhouette and clean collision bounds in the Vertical Slice level.',
              codeLead: '// Swap Greybox Proxy for Final Production Mesh ($targetAsset)',
            ),
          (0, 1) => (
              title: 'Assign Master Shader & Emissive Parameters',
              instr: 'Apply the master surface shader to $targetAsset and expose dynamic emissive/hit-flash parameters.',
              verify: 'Material instance on $targetAsset responds to runtime state and lighting.',
              codeLead: '// Bind Dynamic Material & Emissive Parameters',
            ),
          (0, 2) => (
              title: 'Bind Animation Blend & Easing Curves',
              instr: 'Connect state transitions on $targetAsset to smooth animation blend spaces and easing curves.',
              verify: 'Activating $targetAsset plays smooth anticipation and recovery motion with zero pop.',
              codeLead: '// Configure Animation Blend & Easing Curve',
            ),
          (0, 3) => (
              title: 'Expose $primaryVarName Polish Scalar',
              instr: 'Expose $primaryVarName in the Inspector to tune visual intensity in the Gold Standard slice.',
              verify: '$primaryVarName adjusts visual intensity live in the viewport.',
              codeLead: '// Inspector Polish Scalar: $primaryVarName',
            ),
          (0, _) => (
              title: 'Verify Lighting & Readability Contrast',
              instr: 'Inspect $targetAsset under Vertical Slice level lighting to confirm clear silhouette contrast.',
              verify: '$targetAsset remains immediately readable against arena backgrounds.',
              codeLead: '// Verify Silhouette & Readability Contrast ($primaryVarName)',
            ),
          (1, 0) => (
              title: 'Attach Pooled VFX Emitter to $targetAsset',
              instr: 'Attach a pre-warmed particle emitter to $targetAsset for activation, impact, and recovery bursts.',
              verify: 'Triggering $targetAsset spawns crisp particle cues without first-frame shader hitch.',
              codeLead: '// Attach Pre-Warmed VFX Emitter ($targetAsset)',
            ),
          (1, 1) => (
              title: 'Wire Spatial SFX with Pitch Variance',
              instr: 'Play spatialized audio cues on $targetAsset with randomized pitch variance to prevent ear fatigue.',
              verify: 'Repeated triggers on $targetAsset play distinct, balanced spatial audio.',
              codeLead: '// Play Spatial SFX with Pitch Variance',
            ),
          (1, 2) => (
              title: 'Add Micro Camera Impulse & Hit-Stop',
              instr: 'Trigger a subtle camera trauma impulse or 2-frame hit-stop when $targetAsset lands a high-impact action.',
              verify: 'Impact moments feel punchy without disorienting player aim.',
              codeLead: '// Trigger Micro Camera Impulse & Hit-Stop',
            ),
          (1, 3) => (
              title: 'Scale Feel Cues by $primaryVarName',
              instr: 'Multiply particle burst scale and audio attenuation by $primaryVarName.',
              verify: 'Adjusting $primaryVarName scales VFX/SFX intensity proportionally.',
              codeLead: '// Scale VFX & Audio Cues by $primaryVarName',
            ),
          (1, _) => (
              title: 'Recycle Emitters on Action Complete',
              instr: 'Return finished VFX/SFX instances to the object pool cleanly when $targetAsset finishes its cycle.',
              verify: 'Active emitter count returns to baseline after rapid triggers.',
              codeLead: '// Recycle Pooled VFX/SFX Instances ($primaryVarName)',
            ),
          (_, 0) => (
              title: 'Animate HUD Readout Tween on $targetAsset',
              instr: 'Replace instant HUD text/bar jumps with a smooth eased tween driven by $targetAsset signals.',
              verify: 'HUD counters and bars animate smoothly on every $targetAsset update.',
              codeLead: '// Animate HUD Readout Tween ($targetAsset)',
            ),
          (_, 1) => (
              title: 'Add Screen-Space Callout & Icon Pulse',
              instr: 'Pulse the HUD icon and status callout when $targetAsset becomes ready or triggers a critical state.',
              verify: 'Player peripheral vision catches state changes without looking away from the center.',
              codeLead: '// Trigger HUD Icon Pulse & Callout',
            ),
          (_, 2) => (
              title: 'Enforce Emitter Pool Cap & Frame Guard',
              instr: 'Cap simultaneous active particles/sounds on $targetAsset so frame time stays under 16.6ms.',
              verify: 'Stress-testing rapid inputs holds a locked 60fps frame time.',
              codeLead: '// Enforce 60fps Emitter Pool Cap',
            ),
          (_, 3) => (
              title: 'Clamp Polish Intensity via $primaryVarName',
              instr: 'Clamp screen-shake and flash opacity using $primaryVarName so combat remains readable.',
              verify: 'Overlapping triggers never wash out screen visibility.',
              codeLead: '// Clamp Readability Bounds ($primaryVarName)',
            ),
          (_, _) => (
              title: 'Verify Gold Standard Slice Sign-Off',
              instr: 'Play a full Vertical Slice loop and verify $targetAsset meets visual, audio, and 60fps quality targets.',
              verify: '$targetAsset feels shipping-ready across the entire Gold Standard level.',
              codeLead: '// Verify Vertical Slice Quality Bar ($primaryVarName)',
            ),
        };
      case 'content':
        entry = switch ((grp, stepIdx)) {
          (0, 0) => (
              title: 'Define $targetAsset Roster Data Schema',
              instr: 'Create a data table / resource schema for $targetAsset variants (TierId, BaseStat, SpawnWeight, AssetRef).',
              verify: 'Roster data schema compiles and supports multiple tier rows in the editor.',
              codeLead: '// Define Content Roster Schema ($targetAsset)',
            ),
          (0, 1) => (
              title: 'Populate Tier 1–3 Content Variants',
              instr: 'Author Tier 1, Tier 2, and Tier 3 variant entries for $targetAsset with distinct stats and visuals.',
              verify: 'All 3 content tiers appear in the roster table with valid asset references.',
              codeLead: '// Populate Tier 1-3 Roster Entries',
            ),
          (0, 2) => (
              title: 'Wire Data-Driven Loader on $targetAsset',
              instr: 'Load stats, mesh, and behavior parameters on $targetAsset dynamically from the active roster row.',
              verify: 'Spawning $targetAsset with different TierIds applies the matching variant config.',
              codeLead: '// Load Variant Config from Roster Row',
            ),
          (0, 3) => (
              title: 'Expose $primaryVarName Scaling Curve',
              instr: 'Expose $primaryVarName in the Inspector to tune cross-tier progression scaling.',
              verify: '$primaryVarName scales variant stats cleanly across tiers.',
              codeLead: '// Inspector Progression Scalar: $primaryVarName',
            ),
          (0, _) => (
              title: 'Validate Missing-Row Fallback Defaults',
              instr: 'Provide safe default values if an invalid or locked TierId is requested on $targetAsset.',
              verify: 'Invalid roster queries fall back cleanly to Tier 1 without null errors.',
              codeLead: '// Guard Missing Roster Row Fallback ($primaryVarName)',
            ),
          (1, 0) => (
              title: 'Bind Level & Wave Progression Index',
              instr: 'Subscribe $targetAsset to the current level/wave index from the run progression manager.',
              verify: 'Advancing to the next level or wave notifies $targetAsset of the new difficulty tier.',
              codeLead: '// Bind Level & Wave Progression Index ($targetAsset)',
            ),
          (1, 1) => (
              title: 'Select Variant by Weighted Spawn Table',
              instr: 'Roll weighted variant selection on $targetAsset based on current level depth and SpawnWeight.',
              verify: 'Higher levels introduce Tier 2 and Tier 3 variants at the expected weights.',
              codeLead: '// Roll Weighted Variant Selection',
            ),
          (1, 2) => (
              title: 'Apply Multi-Level Difficulty Multiplier',
              instr: 'Scale $targetAsset health, yield, or cooldowns across levels using $primaryVarName.',
              verify: 'Progression difficulty curve scales smoothly from early to late levels.',
              codeLead: '// Apply Multi-Level Scaling ($primaryVarName)',
            ),
          (1, 3) => (
              title: 'Sync Level Transition & Arena Handoff',
              instr: 'Reset transient state on $targetAsset while preserving unlocked tiers across level transitions.',
              verify: 'Moving between levels transitions $targetAsset cleanly with zero state leak.',
              codeLead: '// Sync Level Transition Handoff',
            ),
          (1, _) => (
              title: 'Verify Multi-Wave Pacing Curve',
              instr: 'Simulate a 3-level progression pass and verify $targetAsset variant pacing and balance.',
              verify: 'Tier ramp-up feels balanced and rewarding across consecutive levels.',
              codeLead: '// Verify Multi-Level Pacing Curve ($primaryVarName)',
            ),
          (_, 0) => (
              title: 'Serialize $targetAsset Unlock & Run State',
              instr: 'Write unlocked tier IDs and persistent counters for $targetAsset into the save-state payload.',
              verify: 'Saving the run records current $targetAsset progression data accurately.',
              codeLead: '// Serialize Persistent State ($targetAsset)',
            ),
          (_, 1) => (
              title: 'Restore Saved Roster State on Load',
              instr: 'Restore unlocked tiers and progression state on $targetAsset when loading or continuing a run.',
              verify: 'Reloading the session restores exact $targetAsset unlocks and stats.',
              codeLead: '// Restore Saved Roster State',
            ),
          (_, 2) => (
              title: 'Enforce Max-Tier Cap & Overflow Guard',
              instr: 'Clamp $primaryVarName scaling at the maximum progression cap so late-game math never overflows.',
              verify: 'End-game waves stay within safe numerical and frame-time bounds.',
              codeLead: '// Clamp Max-Tier Scaling ($primaryVarName)',
            ),
          (_, 3) => (
              title: 'Update HUD Progression & Unlock Banner',
              instr: 'Display the active tier badge and unlock notification on the HUD when $targetAsset upgrades.',
              verify: 'HUD clearly communicates newly unlocked content tiers to the player.',
              codeLead: '// Emit HUD Tier Unlock Notification',
            ),
          (_, _) => (
              title: 'Verify Full Production Loop Across Levels',
              instr: 'Run an end-to-end multi-level session verifying roster variety, scaling, and save-state persistence.',
              verify: '$targetAsset operates at full production quality across all levels.',
              codeLead: '// Verify Full Production Multi-Level Loop ($primaryVarName)',
            ),
        };
      default:
        entry = switch ((grp, stepIdx)) {
          (0, 0) => (
              title: 'Create $targetAsset Mechanic Class',
              instr: 'Create $targetAsset and declare the core data fields for this mechanic.',
              verify: '$targetAsset compiles cleanly and appears in the project asset browser.',
              codeLead: '// Mechanic Foundation Class ($targetAsset)',
            ),
          (0, 1) => (
              title: 'Add Visual Mesh & Trigger Volume',
              instr: 'Attach the visible mesh and InteractBox collision sensor to $targetAsset.',
              verify: 'Mesh and collision wireframe appear aligned in the viewport.',
              codeLead: '// Attach Visual Mesh & Collision Trigger',
            ),
          (0, 2) => (
              title: 'Place $targetAsset in Test Arena',
              instr: 'Place a live instance of $targetAsset in the test arena level at (0, 0, 0).',
              verify: '$targetAsset appears in the level viewport and scene outliner.',
              codeLead: '// Place $targetAsset Instance in Level',
            ),
          (0, 3) => (
              title: 'Expose $primaryVarName in Inspector',
              instr: 'Expose $primaryVarName on $targetAsset for live playtest tuning in the Inspector/Details panel.',
              verify: '$primaryVarName is editable in the Inspector when $targetAsset is selected.',
              codeLead: '// Inspector Tuning Variable: $primaryVarName',
            ),
          (0, _) => (
              title: 'Initialize Mechanic Startup State',
              instr: 'Initialize the starting state and timer values on $targetAsset using $primaryVarName.',
              verify: 'Entering Play mode initializes $targetAsset cleanly with $primaryVarName.',
              codeLead: '// Initialize Startup State ($primaryVarName)',
            ),
          (1, 0) => (
              title: 'Bind Player Trigger Input',
              instr: 'Bind the primary player input or overlap event on $targetAsset to start the mechanic.',
              verify: 'Triggering the input in Play mode invokes the handler on $targetAsset.',
              codeLead: '// Bind Primary Player Trigger on $targetAsset',
            ),
          (1, 1) => (
              title: 'Execute Core Mechanic Action',
              instr: 'Run the core spatial/gameplay action on $targetAsset when triggered by the player.',
              verify: 'Triggering $targetAsset executes the primary gameplay action on screen.',
              codeLead: '// Execute Core Mechanic Action on $targetAsset',
            ),
          (1, 2) => (
              title: 'Update Active Visual & World State',
              instr: 'Update $targetAsset\'s visual state and world properties immediately when the action executes.',
              verify: '$targetAsset visibly updates on screen in response to the player action.',
              codeLead: '// Sync Active Visual & World State',
            ),
          (1, 3) => (
              title: 'Drive Action Math with $primaryVarName',
              instr: 'Scale the mechanic\'s speed, duration, or magnitude directly from $primaryVarName.',
              verify: 'Changing $primaryVarName in the Inspector immediately alters the live gameplay behavior.',
              codeLead: '// Scale Mechanic Execution by $primaryVarName',
            ),
          (1, _) => (
              title: 'Step Active Tick & Recovery Loop',
              instr: 'Advance the active timer/velocity each physics tick using $primaryVarName and return cleanly to ready.',
              verify: 'The mechanic steps smoothly each frame and recovers cleanly when finished.',
              codeLead: '// Step Active Physics Tick ($primaryVarName)',
            ),
          (_, 0) => (
              title: 'Bind Feedback & HUD Signal',
              instr: 'Connect $targetAsset\'s state completion signal to the HUD and feedback emitters.',
              verify: 'Executing the mechanic emits the feedback signal cleanly.',
              codeLead: '// Emit HUD & Feedback Signal on $targetAsset',
            ),
          (_, 1) => (
              title: 'Trigger Visual Highlight & Particle Cue',
              instr: 'Play the on-screen visual highlight or particle burst on $targetAsset when activated.',
              verify: 'Activating $targetAsset displays immediate visual confirmation on screen.',
              codeLead: '// Trigger Visual Highlight & Particle Burst',
            ),
          (_, 2) => (
              title: 'Play Confirmation SFX & HUD Pop',
              instr: 'Play the confirmation audio cue and update the HUD indicator when $targetAsset completes.',
              verify: 'Audio cue and HUD readout trigger in sync with the action.',
              codeLead: '// Play Confirmation Audio & Update HUD Readout',
            ),
          (_, 3) => (
              title: 'Wire $primaryVarName Cooldown Window',
              instr: 'Enforce the cooldown recovery window on $targetAsset using $primaryVarName.',
              verify: 'Rapid inputs respect the $primaryVarName cooldown timer.',
              codeLead: '// Enforce Cooldown Window ($primaryVarName)',
            ),
          (_, _) => (
              title: 'Verify Full Mechanic Loop in Viewport',
              instr: 'Run the complete mechanic loop in Play mode and verify smooth transitions under rapid input.',
              verify: 'The full action -> feedback -> cooldown loop runs cleanly in the viewport.',
              codeLead: '// Verify Complete Mechanic Loop ($primaryVarName)',
            ),
        };
    }

    return (
      stepHeader: 'STEP $taskNum.${stepIdx + 1} · ${entry.title.toUpperCase()}',
      shortTitle: entry.title,
      instruction: entry.instr,
      verify: entry.verify,
      codeLead: entry.codeLead,
    );
  }
}
