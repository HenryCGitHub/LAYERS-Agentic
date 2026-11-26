import '../../constants/text_style_guide.dart';
import '../../models/epic_spec.dart';
import '../../utils/unreal_spec_guard.dart';
import '../gemini_agent_client.dart';

/// One playable game-concept direction proposed in Stage 1 before drafting `PROJECT_SPEC.md`.
class SparkAngleOption {
  final String id;
  final String styleTag;
  final String title;
  final String pitch;
  final String cameraHint;
  final String viewChoiceId;
  final String sliceHint;

  const SparkAngleOption({
    required this.id,
    required this.styleTag,
    required this.title,
    required this.pitch,
    required this.cameraHint,
    required this.viewChoiceId,
    required this.sliceHint,
  });

  static const Set<String> validViewIds = <String>{
    'isometric',
    'topdown',
    'tps',
    'fps',
    'sidescroller',
  };

  static String normalizeViewChoiceId(String? raw, {String? fallbackText}) {
    final lower = (raw ?? '').trim().toLowerCase();
    if (validViewIds.contains(lower)) return lower;
    final text = '$lower ${(fallbackText ?? '').toLowerCase()}';
    if (text.contains('first-person') ||
        text.contains('first person') ||
        text.contains('fps')) {
      return 'fps';
    }
    if (text.contains('side') || text.contains('2d') || text.contains('platformer')) {
      return 'sidescroller';
    }
    if (text.contains('third-person') ||
        text.contains('third person') ||
        text.contains('shoulder') ||
        text.contains('tps') ||
        text.contains('pursuit')) {
      return 'tps';
    }
    if (text.contains('top-down') || text.contains('top down')) {
      return 'topdown';
    }
    return 'isometric';
  }

  SparkAngleOption copyWith({
    String? id,
    String? styleTag,
    String? title,
    String? pitch,
    String? cameraHint,
    String? viewChoiceId,
    String? sliceHint,
  }) {
    return SparkAngleOption(
      id: id ?? this.id,
      styleTag: styleTag ?? this.styleTag,
      title: title ?? this.title,
      pitch: pitch ?? this.pitch,
      cameraHint: cameraHint ?? this.cameraHint,
      viewChoiceId: viewChoiceId ?? this.viewChoiceId,
      sliceHint: sliceHint ?? this.sliceHint,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'styleTag': styleTag,
        'title': title,
        'pitch': pitch,
        'cameraHint': cameraHint,
        'viewChoiceId': viewChoiceId,
        'sliceHint': sliceHint,
      };

  factory SparkAngleOption.fromJson(
    Map<String, dynamic> json, {
    required int index,
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
  }) {
    String clean(dynamic val, String fallback) {
      final sanitized = UnrealSpecGuard.sanitizeLine(
        (val ?? '').toString(),
        mode: mode,
      ).trim();
      return sanitized.isEmpty ? fallback : sanitized;
    }

    final rawId = (json['id'] ?? '').toString().trim();
    final safeId = rawId.isNotEmpty
        ? rawId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        : 'angle_${index + 1}';
    final title = clean(json['title'], 'Angle ${index + 1}');
    final pitch = clean(json['pitch'], '$title — focused playable prototype loop');
    final cameraHint = clean(json['cameraHint'], 'Third-Person Follow');
    return SparkAngleOption(
      id: safeId,
      styleTag: clean(json['styleTag'], 'ANGLE ${index + 1}').toUpperCase(),
      title: title,
      pitch: pitch,
      cameraHint: cameraHint,
      viewChoiceId: normalizeViewChoiceId(
        json['viewChoiceId']?.toString(),
        fallbackText: '$cameraHint $pitch',
      ),
      sliceHint: clean(json['sliceHint'], '1 Test Room + Core Loop'),
    );
  }
}

/// Interactive 3-angle Stage 1 brainstorming deck steered with Hydrogen before drafting `PROJECT_SPEC.md`.
class SparkAngleDeck {
  final String rawSpark;
  final UnrealArchitectureMode architectureMode;
  final List<SparkAngleOption> angles;
  final String selectedAngleId;
  final List<String> steerHistory;
  final int round;

  const SparkAngleDeck({
    required this.rawSpark,
    required this.architectureMode,
    required this.angles,
    required this.selectedAngleId,
    this.steerHistory = const <String>[],
    this.round = 1,
  });

  SparkAngleOption get selectedAngle {
    for (final a in angles) {
      if (a.id == selectedAngleId) return a;
    }
    return angles.first;
  }

  SparkAngleDeck copyWith({
    String? rawSpark,
    UnrealArchitectureMode? architectureMode,
    List<SparkAngleOption>? angles,
    String? selectedAngleId,
    List<String>? steerHistory,
    int? round,
  }) {
    return SparkAngleDeck(
      rawSpark: rawSpark ?? this.rawSpark,
      architectureMode: architectureMode ?? this.architectureMode,
      angles: angles ?? this.angles,
      selectedAngleId: selectedAngleId ?? this.selectedAngleId,
      steerHistory: steerHistory ?? this.steerHistory,
      round: round ?? this.round,
    );
  }

  /// Compiles a crisp single-prompt handoff string from the chosen angle + user steers for Argon.
  String buildSelectedHandoffPrompt() {
    final chosen = selectedAngle;
    final cleanSteers = steerHistory
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final steerSuffix =
        cleanSteers.isEmpty ? '' : ' | Steers: ${cleanSteers.join('; ')}';
    return '$rawSpark — ${chosen.title} (${chosen.styleTag}): ${chosen.pitch} '
        '| Camera: ${chosen.cameraHint} (${chosen.viewChoiceId}) '
        '| Target v0.1 Slice: ${chosen.sliceHint} '
        '| Mode: ${architectureMode.pillLabel}$steerSuffix';
  }
}

/// Structured result wrapper preserving real Cloud Gemini errors on Stage 1 angle exploration.
class SparkAngleOutcome {
  final SparkAngleDeck? deck;
  final String? errorMessage;
  final bool usedOfflineFallback;

  const SparkAngleOutcome({
    required this.deck,
    this.errorMessage,
    this.usedOfflineFallback = false,
  });
}

/// Fast Stage 1 Idea Workbench agent (`gemini-4-hydrogen`, `LOW` thinking) turning rough prompts
/// into 3 distinct playable UE5 game angles with 1-line steer and reroll support.
class SparkAngleAgent {
  const SparkAngleAgent._();

  static const String proposeAnglesToolName = 'propose_spark_angles';

  static Map<String, dynamic> get proposeAnglesToolSchema => <String, dynamic>{
        'name': proposeAnglesToolName,
        'description':
            'Propose 3 distinct playable Unreal Engine 5 game concept angles for a rough spark prompt without generating release Epics or spec clutter.',
        'parameters': <String, dynamic>{
          'type': 'OBJECT',
          'required': ['angles'],
          'properties': <String, dynamic>{
            'angles': <String, dynamic>{
              'type': 'ARRAY',
              'description':
                  'Exactly 3 varied, concrete playable directions (e.g. Arcade Action, Tactical Risk, Atmospheric Shift).',
              'items': <String, dynamic>{
                'type': 'OBJECT',
                'required': [
                  'id',
                  'styleTag',
                  'title',
                  'pitch',
                  'cameraHint',
                  'viewChoiceId',
                  'sliceHint',
                ],
                'properties': <String, dynamic>{
                  'id': {
                    'type': 'STRING',
                    'description':
                        'Short snake_case angle ID (e.g. "arcade", "tactical", "atmospheric").',
                  },
                  'styleTag': {
                    'type': 'STRING',
                    'description':
                        '2-word uppercase vibe tag (e.g. "ARCADE DUEL", "TACTICAL WATCH", "PHYSICS RIG").',
                  },
                  'title': {
                    'type': 'STRING',
                    'description':
                        '2-4 word plain playable title (never archaic lore or corporate words).',
                  },
                  'pitch': {
                    'type': 'STRING',
                    'description': LayersTextStyleGuide.blufVisionSchemaDesc,
                  },
                  'cameraHint': {
                    'type': 'STRING',
                    'description':
                        '2-4 word camera label (e.g. "First-Person Boat Deck", "Third-Person Pursuit", "Isometric Arena").',
                  },
                  'viewChoiceId': {
                    'type': 'STRING',
                    'enum': [
                      'isometric',
                      'topdown',
                      'tps',
                      'fps',
                      'sidescroller',
                    ],
                  },
                  'sliceHint': {
                    'type': 'STRING',
                    'description':
                        'Concrete small v0.1 playable goal (3-6 words, e.g. "1 Night Shift + 3 Catches").',
                  },
                },
              },
            },
          },
        },
      };

  static Future<SparkAngleOutcome> proposeAngles({
    required String rawSpark,
    required String apiKey,
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
    String? steerNote,
    bool reroll = false,
    SparkAngleDeck? previousDeck,
    String preferredModel = GeminiAgentClient.pinnedLiveFlashModel,
    String thinkingLevel = GeminiAgentClient.defaultFastThinkingLevel,
  }) async {
    final cleanedSpark = UnrealSpecGuard.sanitizeLine(rawSpark, mode: mode);
    final effectiveSpark =
        cleanedSpark.isEmpty ? rawSpark.trim() : cleanedSpark;
    if (effectiveSpark.isEmpty) {
      return const SparkAngleOutcome(
        deck: null,
        errorMessage: 'Enter a short game idea before exploring angles.',
      );
    }

    final cleanSteer = (steerNote ?? '').trim();
    final nextSteers = <String>[
      if (previousDeck != null) ...previousDeck.steerHistory,
      if (cleanSteer.isNotEmpty) cleanSteer,
    ];
    final nextRound = previousDeck != null ? previousDeck.round + 1 : 1;

    if (!GeminiAgentClient.hasKey(apiKey)) {
      return SparkAngleOutcome(
        deck: _buildFallbackDeck(
          rawSpark: effectiveSpark,
          mode: mode,
          steerNote: cleanSteer,
          reroll: reroll,
          steerHistory: nextSteers,
          round: nextRound,
        ),
        usedOfflineFallback: true,
      );
    }

    final prevSummary = previousDeck == null || previousDeck.angles.isEmpty
        ? ''
        : '\nPREVIOUS ANGLES (generate fresher alternatives, do not repeat titles): '
            '${previousDeck.angles.map((a) => '"${a.title}" (${a.styleTag})').join(', ')}';
    final steerDirective = cleanSteer.isEmpty
        ? ''
        : '\nUSER STEER DIRECTION: "$cleanSteer" (apply this constraint across all 3 angles).';
    final rerollDirective = reroll
        ? '\nREROLL REQUEST: Keep the core spark but twist the mechanics, camera framing, or risk loop into 3 fresh directions.'
        : '';

    final prompt = '''
${LayersTextStyleGuide.compactStyleRules}

You are the LAYERS Stage 1 Idea Workbench co-designer.
Generate 3 distinct playable game concept angles for Unreal Engine 5 (`${mode.pillLabel}`) so the creator can pick a creative direction before writing `PROJECT_SPEC.md`.
RAW SPARK: "$effectiveSpark"$steerDirective$rerollDirective$prevSummary

CONSTRAINTS:
- Call `$proposeAnglesToolName` with exactly 3 genuinely different playable directions.
- Each pitch follows BLUF syntax: `[2-4 Word Fantasy] — [Concrete Playable Loop]` in plain everyday game-dev words.
- Keep scope strictly `v0.1` playable slice sized (1 room/course/shift, 2–3 core verbs).
- Stay 100% Unreal Engine 5 compatible; never emit `§01–§05` sections, non-Unreal engine terms, or filler buzzwords.
''';

    final res = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: preferredModel,
      thinkingLevel: thinkingLevel,
      temperature: reroll ? 0.85 : 0.65,
      functionDeclarations: [proposeAnglesToolSchema],
    );

    if (res == null) {
      return SparkAngleOutcome(
        deck: null,
        errorMessage: GeminiAgentClient.lastErrorStatus ??
            'Cloud Gemini could not propose game angles. Retry when ready.',
      );
    }

    final rawAngles = res['angles'] is List ? (res['angles'] as List) : const [];
    final parsed = <SparkAngleOption>[];
    final seenIds = <String>{};
    for (int i = 0; i < rawAngles.length && parsed.length < 3; i++) {
      final item = rawAngles[i];
      if (item is! Map) continue;
      var opt = SparkAngleOption.fromJson(
        Map<String, dynamic>.from(item),
        index: parsed.length,
        mode: mode,
      );
      if (!seenIds.add(opt.id)) {
        opt = opt.copyWith(id: '${opt.id}_${parsed.length + 1}');
        seenIds.add(opt.id);
      }
      parsed.add(opt);
    }

    final fallbackDeck = _buildFallbackDeck(
      rawSpark: effectiveSpark,
      mode: mode,
      steerNote: cleanSteer,
      reroll: reroll,
      steerHistory: nextSteers,
      round: nextRound,
    );
    while (parsed.length < 3) {
      var pad = fallbackDeck.angles[parsed.length];
      if (!seenIds.add(pad.id)) {
        pad = pad.copyWith(id: '${pad.id}_${parsed.length + 1}');
        seenIds.add(pad.id);
      }
      parsed.add(pad);
    }

    final preservedSelectedId = previousDeck != null &&
            parsed.any((a) => a.id == previousDeck.selectedAngleId)
        ? previousDeck.selectedAngleId
        : parsed.first.id;

    return SparkAngleOutcome(
      deck: SparkAngleDeck(
        rawSpark: effectiveSpark,
        architectureMode: mode,
        angles: parsed,
        selectedAngleId: preservedSelectedId,
        steerHistory: nextSteers,
        round: nextRound,
      ),
    );
  }

  static SparkAngleDeck _buildFallbackDeck({
    required String rawSpark,
    required UnrealArchitectureMode mode,
    required String steerNote,
    required bool reroll,
    required List<String> steerHistory,
    required int round,
  }) {
    final lower = rawSpark.toLowerCase();
    final steerLower = steerNote.toLowerCase();
    final isCoop = steerLower.contains('co-op') || steerLower.contains('coop');
    final steerTag = steerNote.trim().isEmpty
        ? ''
        : ' (${UnrealSpecGuard.sanitizeLine(steerNote, mode: mode)})';
    final passTag = reroll && round > 1 ? ' v$round' : '';

    final List<SparkAngleOption> options;
    if (lower.contains('fish') || lower.contains('boat') || lower.contains('dredge')) {
      options = [
        SparkAngleOption(
          id: 'arcade',
          styleTag: 'ARCADE DUEL',
          title: 'Snap-Hook Trawler$passTag',
          pitch:
              'Midnight trawler duel — cast jittered lines, win violent reel stamina pulls, and bank 3 catches before storm flood$steerTag.',
          cameraHint: 'First-Person Boat Deck',
          viewChoiceId: 'fps',
          sliceHint: '1 Night Shift + 3 Catches',
        ),
        SparkAngleOption(
          id: 'tactical',
          styleTag: 'TACTICAL WATCH',
          title: 'Fog Pier Beacon$passTag',
          pitch:
              'Foggy pier watch — balance narrow floodlights against sonar pings so deep threats never breach the dock$steerTag.',
          cameraHint: 'Isometric Foggy Pier',
          viewChoiceId: 'isometric',
          sliceHint: '1 Wooden Pier + 2 Predators',
        ),
        SparkAngleOption(
          id: 'atmospheric',
          styleTag: 'TENSE SHIFT',
          title: 'Cabin Mimic Shift$passTag',
          pitch:
              'Quiet single-boat shift — winch up deep catches, check twitching crates under lamp light, and toss mimics overboard$steerTag.',
          cameraHint: 'First-Person Cabin',
          viewChoiceId: 'fps',
          sliceHint: '1 Shift + Specimen Gate',
        ),
      ];
    } else if (lower.contains('courier') ||
        lower.contains('grapple') ||
        lower.contains('mech') && !lower.contains('arena')) {
      options = [
        SparkAngleOption(
          id: 'arcade',
          styleTag: 'ARCADE FLOW',
          title: 'Skyhook Sling Runner$passTag',
          pitch:
              'Rooftop grapple sprint — fire crane tethers, pump winch slings, and flare into wingsuit glides over skyline gaps$steerTag.',
          cameraHint: 'Third-Person Pursuit',
          viewChoiceId: 'tps',
          sliceHint: '1 Rooftop Course + 2 Pads',
        ),
        SparkAngleOption(
          id: 'tactical',
          styleTag: 'PHYSICS RIG',
          title: 'Heavy Cargo Walker$passTag',
          pitch:
              'Weighted parcel rig — counterbalance bulky reactor crates across skybridges while venting thruster heat on steep drops$steerTag.',
          cameraHint: 'Tight Shoulder Aim',
          viewChoiceId: 'tps',
          sliceHint: '1 Skybridge + Vent Gauge',
        ),
        SparkAngleOption(
          id: 'atmospheric',
          styleTag: 'STORM SHIFT',
          title: 'Cloudline Night Drop$passTag',
          pitch:
              'Storm-tier rooftop courier — track sodium tower beacons through crosswind gusts to stamp silent high-altitude drops$steerTag.',
          cameraHint: 'Third-Person Pursuit',
          viewChoiceId: 'tps',
          sliceHint: '60s Wind Corridor Run',
        ),
      ];
    } else if (lower.contains('cozy') ||
        lower.contains('farm') ||
        lower.contains('bake') ||
        lower.contains('puzzle') ||
        lower.contains('craft')) {
      options = [
        SparkAngleOption(
          id: 'arcade',
          styleTag: 'ORDER RUSH',
          title: 'Counter Rush Loop$passTag',
          pitch:
              'Fast shop-floor sprint — prep stations, dodge clutter, and clear timed counter orders cleanly before dusk bell$steerTag.',
          cameraHint: 'Isometric Counter View',
          viewChoiceId: 'isometric',
          sliceHint: '1 Station Room + 3 Orders',
        ),
        SparkAngleOption(
          id: 'tactical',
          styleTag: 'SYSTEMIC CRAFT',
          title: 'Tactile Workshop Chain$passTag',
          pitch:
              'Compact workbench chain — link resource plots and heat timings into high-yield recipes inside one cozy yard$steerTag.',
          cameraHint: 'Top-Down Workshop',
          viewChoiceId: 'topdown',
          sliceHint: '1 Yard + 3 Combine Recipes',
        ),
        SparkAngleOption(
          id: 'atmospheric',
          styleTag: 'COZY SHIFT',
          title: 'Lantern Porch Oddities$passTag',
          pitch:
              'Quiet twilight shop — tend 3 glowing crop beds and craft oddity charms for roaming regulars without a clock$steerTag.',
          cameraHint: 'Isometric Porch',
          viewChoiceId: 'isometric',
          sliceHint: '1 Quiet Plot + 3 Guests',
        ),
      ];
    } else {
      final cleanVerb = rawSpark.trim();
      final coopPrefix = isCoop ? '2-player co-op ' : '';
      options = [
        SparkAngleOption(
          id: 'arcade',
          styleTag: 'ARCADE ACTION',
          title: 'High-Tempo Rush$passTag',
          pitch:
              '${coopPrefix}Snappy $cleanVerb — instant dash movement, crisp hitstop impacts, and fast arena wave clears$steerTag.',
          cameraHint: 'Isometric Arena',
          viewChoiceId: 'isometric',
          sliceHint: '1 Greybox Room + 3 Beats',
        ),
        SparkAngleOption(
          id: 'tactical',
          styleTag: 'TACTICAL DEPTH',
          title: 'Committed Risk Duel$passTag',
          pitch:
              '${coopPrefix}Deliberate $cleanVerb — read telegraphed threats cleanly and commit limited stamina or ability charges$steerTag.',
          cameraHint: 'Third-Person Follow',
          viewChoiceId: 'tps',
          sliceHint: '1 Encounter + Guard Counter',
        ),
        SparkAngleOption(
          id: 'atmospheric',
          styleTag: 'FOCUSED SHIFT',
          title: 'Tight Room Tension$passTag',
          pitch:
              '${coopPrefix}Grounded $cleanVerb — navigate one tight room using diegetic world cues and clean sound reads$steerTag.',
          cameraHint: 'First-Person Direct',
          viewChoiceId: 'fps',
          sliceHint: '1 Room + 60s Survival',
        ),
      ];
    }

    return SparkAngleDeck(
      rawSpark: rawSpark,
      architectureMode: mode,
      angles: options,
      selectedAngleId: options.first.id,
      steerHistory: steerHistory,
      round: round,
    );
  }
}
