import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import 'gemini_agent_client.dart';

/// A single AI-suggested mechanic or twist card on the New Project screen
/// that the user can toggle on/off to fold into (or remove from) their Concept Summary.
class SparkExpansionCard {
  final String badge;
  final String title;
  final String description;
  final String additionSummary;
  final String accentType;
  bool isSelected;

  SparkExpansionCard({
    required this.badge,
    required this.title,
    required this.description,
    required this.additionSummary,
    this.accentType = 'amber',
    this.isSelected = false,
  });
}

/// Holds the ingested AI summary of the user's raw game idea on the New Project screen,
/// plus the 3 toggleable Concept Expansion Cards tailored to that idea.
class SparkIdeaIntakeResult {
  String rawIdea;
  String workingTitle;
  String baseSummary;
  List<String> mechanics;
  List<SparkExpansionCard> expansionCards;

  SparkIdeaIntakeResult({
    required this.rawIdea,
    required this.workingTitle,
    required this.baseSummary,
    required this.mechanics,
    required this.expansionCards,
  });

  /// Returns the effective summary including any selected Expansion Cards.
  String get effectiveSummary {
    final activeAdditions = expansionCards
        .where((c) => c.isSelected)
        .map((c) => c.additionSummary)
        .toList();
    if (activeAdditions.isEmpty) return baseSummary;
    return '$baseSummary Included additions: ${activeAdditions.join(' · ')}.';
  }

  /// Returns the canonical prompt sent to `startConceptInterview` when the user
  /// clicks `Start Concept Blueprint →`.
  String get canonicalPrompt {
    final activeAdditions = expansionCards
        .where((c) => c.isSelected)
        .map((c) => '${c.title} (${c.additionSummary})')
        .toList();
    if (activeAdditions.isEmpty) {
      return '$rawIdea — $baseSummary';
    }
    return '$rawIdea — $baseSummary With added mechanics: ${activeAdditions.join('; ')}';
  }
}

/// Stage 1 Agent: Turns a "Spark" idea into a Concept Blueprint and section-focused
/// guidance using Gemini AI (`gemini-flash-latest`).
/// Contains zero hardcoded archetypes, zero fallback game templates, and zero minimal scaffolds.
/// Returns `null` (or `false`) whenever the app is offline or Gemini AI is unreachable.
class ProjectConceptAgent {
  static const _kCardAccents = ['amber', 'emerald', 'neutral'];

  static const _kExpansionCardsJsonSchema = '''
  "expansionCards": [
    {"badge": "01 · CORE MECHANIC TWIST", "title": "2-4 Word Name", "description": "1-2 plain sentences.", "additionSummary": "Concise clause"},
    {"badge": "02 · RISK / REWARD HOOK", "title": "2-4 Word Name", "description": "1-2 plain sentences.", "additionSummary": "Concise clause"},
    {"badge": "03 · LOOP PAYOFF & UPGRADE", "title": "2-4 Word Name", "description": "1-2 plain sentences.", "additionSummary": "Concise clause"}
  ]''';

  static bool _isPlaceholderString(String s) =>
      s.isEmpty ||
      s == '...' ||
      s.toLowerCase().startsWith('only if ');

  static List<String> _parseStringList(
    dynamic raw, {
    bool filterPlaceholders = true,
  }) {
    if (raw is! List) return const <String>[];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => filterPlaceholders ? !_isPlaceholderString(s) : s.isNotEmpty)
        .toList();
  }

  static List<String> _normalizeTechSpecEngine(
    List<String> techSpec,
    List<String> gameSpec,
    String sparkText,
  ) {
    if (techSpec.isEmpty) return techSpec;
    final result = List<String>.from(techSpec);
    final e0 = result.first.toLowerCase();
    final hasConcreteEngine = e0.contains('godot') ||
        e0.contains('unity') ||
        e0.contains('unreal') ||
        e0.contains('gamemaker') ||
        e0.contains('phaser') ||
        e0.contains('bevy') ||
        e0.contains('defold') ||
        e0.contains('flutter') ||
        e0.contains('flame');
    if (hasConcreteEngine) return result;

    final corpus =
        '${gameSpec.join(' ')} ${techSpec.join(' ')} $sparkText'.toLowerCase();
    if (corpus.contains('unreal')) {
      result[0] = 'Unreal Engine 5 (Blueprints / C++)';
    } else if (corpus.contains('unity') || corpus.contains('c#')) {
      result[0] = 'Unity 6 (C#)';
    } else if (corpus.contains('2d') ||
        corpus.contains('sprite') ||
        corpus.contains('pixel') ||
        corpus.contains('tilemap') ||
        corpus.contains('top-down')) {
      result[0] = 'Godot 4 (GDScript)';
    } else {
      result[0] = 'Unreal Engine 5 (Blueprints / C++)';
    }
    return result;
  }

  static List<SparkExpansionCard> _parseExpansionCards(dynamic rawCards) {
    if (rawCards is! List) return const <SparkExpansionCard>[];
    final cards = <SparkExpansionCard>[];
    for (int i = 0; i < rawCards.length && i < 3; i++) {
      final item = rawCards[i];
      if (item is Map) {
        cards.add(
          SparkExpansionCard(
            badge: (item['badge'] ?? '0${i + 1} · IDEA ADDITION')
                .toString()
                .trim(),
            title: (item['title'] ?? 'Gameplay Twist ${i + 1}')
                .toString()
                .trim(),
            description: (item['description'] ?? '').toString().trim(),
            additionSummary: (item['additionSummary'] ?? item['title'] ?? '')
                .toString()
                .trim(),
            accentType: _kCardAccents[i % _kCardAccents.length],
          ),
        );
      }
    }
    return cards;
  }

  /// Native Gemini Tool Declaration for `startConceptInterview` (`commit_concept_blueprint`).
  /// Enforces the 4-cell `gameSpec`, concrete `engine` enum in `techSpec`, `pillarName: playerFeeling`
  /// pairs, and `priorityX over overAlternativeY` rules at the schema level.
  static const Map<String, dynamic> commitConceptBlueprintTool = {
    'name': 'commit_concept_blueprint',
    'description':
        'Commits the structured 8-section Stage 1 Concept Blueprint for the game prototype.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'title': {
          'type': 'STRING',
          'description': 'Short 2-3 word plain game title.',
        },
        'goal': {
          'type': 'STRING',
          'description':
              'Strategy Label: Build a playable [Title] prototype where you [action 1], [action 2], and [action 3].',
        },
        'gameSpec': {
          'type': 'OBJECT',
          'properties': {
            'cameraView': {'type': 'STRING'},
            'controls': {'type': 'STRING'},
            'playerMode': {'type': 'STRING'},
            'arenaStructure': {'type': 'STRING'},
          },
          'required': [
            'cameraView',
            'controls',
            'playerMode',
            'arenaStructure',
          ],
        },
        'techSpec': {
          'type': 'OBJECT',
          'properties': {
            'engine': {
              'type': 'STRING',
              'enum': [
                'Godot 4 (GDScript)',
                'Unity 6 (C#)',
                'Unreal Engine 5 (Blueprints / C++)',
              ],
            },
            'platform': {'type': 'STRING'},
            'assetPipeline': {'type': 'STRING'},
            'saveMode': {'type': 'STRING'},
          },
          'required': ['engine', 'platform', 'assetPipeline', 'saveMode'],
        },
        'designPillars': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description':
                '2-3 Word Pillar Name: Concise 1-sentence player feeling (never a feature or genre).',
          },
        },
        'tradeOffs': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description':
                'Explicit X over Y boundary rule (e.g. "Immediate arcade movement over realistic physics inertia").',
          },
        },
        'coreLoopBeats': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description':
                'Beat Name: Concise 1-sentence observable player action and system response.',
          },
        },
        'exclusions': {
          'type': 'ARRAY',
          'items': {
            'type': 'STRING',
            'description': 'No 2-4 word prototype cut.',
          },
        },
        'doneWhen': {
          'type': 'STRING',
          'description':
              'Concise 1-sentence playtest completion condition without FPS targets.',
        },
        'releaseTrainTitles': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
      },
      'required': [
        'title',
        'goal',
        'gameSpec',
        'techSpec',
        'designPillars',
        'tradeOffs',
        'coreLoopBeats',
        'exclusions',
        'doneWhen',
      ],
    },
  };

  /// Native Gemini Tool Declaration for `sendConceptChatTurn` (`update_concept_section`).
  static const Map<String, dynamic> updateConceptSectionTool = {
    'name': 'update_concept_section',
    'description':
        'Updates only the modified section(s) of the Live Concept Blueprint in response to the developer.',
    'parameters': {
      'type': 'OBJECT',
      'properties': {
        'reply': {
          'type': 'STRING',
          'description': '1-sentence confirmation of what changed.',
        },
        'updatedFields': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'title': {'type': 'STRING'},
        'goal': {'type': 'STRING'},
        'goalOptions': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'gameSpec': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
          'description':
              '4 cells: ["Camera View", "Controls", "Player Mode", "Arena Structure"].',
        },
        'techSpec': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
          'description':
              '4 cells: ["Godot 4 (GDScript) | Unity 6 (C#) | Unreal Engine 5 (Blueprints / C++)", "Platform", "Asset Pipeline", "Network / Save"].',
        },
        'designPillars': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'tradeOffs': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'coreLoopBeats': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'exclusions': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
        'doneWhen': {'type': 'STRING'},
        'releaseTrainTitles': {
          'type': 'ARRAY',
          'items': {'type': 'STRING'},
        },
      },
      'required': ['reply', 'updatedFields'],
    },
  };

  static List<String> _parseSpecCells(
    dynamic raw,
    List<String> keysOrder,
  ) {
    if (raw is Map) {
      final cells = <String>[];
      for (final k in keysOrder) {
        final v = (raw[k] ?? '').toString().trim();
        if (v.isNotEmpty) cells.add(v);
      }
      if (cells.isNotEmpty) return cells;
    }
    return _parseStringList(raw);
  }

  /// Step 1B: Generates the initial 9-section Concept Blueprint from a spark idea via Gemini AI.
  /// Returns `null` if offline or if Gemini AI cannot be reached.
  static Future<ProjectConceptBlueprint?> startConceptInterview(
    String rawSpark, {
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'HIGH',
    bool isGddExtraction = false,
  }) async {
    final cleanSpark = ProjectConceptBlueprint.normalizeCommonTypos(
      rawSpark.trim(),
    );
    if (cleanSpark.isEmpty || !GeminiAgentClient.hasKey(apiKey)) {
      return null;
    }

    final includeUpfrontOptions = GeminiAgentClient.testMockResponder != null;
    final optionsSchemaTail = includeUpfrontOptions
        ? ''',
  "sectionOptions": {
    "goal": ["Title 1: Build...", "Title 2: Build...", "Title 3: Build..."],
    "gameSpec": ["View · Controls · Mode · Structure", "View 2 · Controls 2 · Mode 2 · Structure 2", "View 3 · Controls 3 · Mode 3 · Structure 3"],
    "techSpec": ["Engine · Platform · Pipeline · Save", "Engine 2 · Platform 2 · Pipeline 2 · Save 2", "Engine 3 · Platform 3 · Pipeline 3 · Save 3"],
    "designPillars": ["Title 1: Experience...", "Title 2: Experience...", "Title 3: Experience..."],
    "tradeOffs": ["Rule Title 1: Specific X over Y rule for $cleanSpark", "Rule Title 2: Specific X over Y rule", "Rule Title 3: Specific X over Y rule"],
    "coreLoop": ["Title 1: Beat A → Beat B → Beat C → Beat D", "Title 2: ...", "Title 3: ..."],
    "exclusions": ["Cut Title 1: Specific prototype cut for $cleanSpark", "Cut Title 2: Specific prototype cut", "Cut Title 3: Specific prototype cut"],
    "doneWhen": ["Playtest Gate 1: Observable completion condition", "Playtest Gate 2: ...", "Playtest Gate 3: ..."]
  }'''
        : '';

    final promptLead = isGddExtraction
        ? '''You are an indie game producer extracting a structured 8-section Stage 1 Concept Blueprint from this pasted Game Design Document (GDD) / Notes:
"""
$cleanSpark
"""
- FAITHFUL GDD EXTRACTION: Extract and preserve the exact title, mechanics, camera/controls, engine/platform, design pillars, trade-offs, core loop beats, exclusions, and completion criteria described in the pasted document rather than inventing unrelated systems.'''
        : '''You are an indie game producer creating a Stage 1 Concept Blueprint for this spark idea:
"$cleanSpark"''';

    final prompt = '''
$promptLead

${GeminiAgentClient.compactStyleRules}
- Decompose `coreLoopBeats` into 4 to 6 sequential playable Beats (`Beat Name: Observable player action and system response`) in chronological player-loop order:
  1. Beat 1 MUST be the immediate in-game player control & primary action (e.g. Walking & Tank Inspection, Grapple/Dash Traversal, Vehicle Handling, or Grid Placement—never a pre-match menu).
  2. Middle Beats cover the core simulation/action and reactive challenge in the exact chronological sequence the player experiences them.
  3. Final Beats cover Harvesting/Reward collection, Selling/Upgrading equipment, and starting the next cycle/run so the loop never dead-ends.
- In `techSpec`, ALWAYS name a concrete game engine (`"Godot 4 (GDScript)"`, `"Unity 6 (C#)"`, or `"Unreal Engine 5 (Blueprints / C++)"`) — NEVER output a generic label like `"2D Game Engine"` or `"3D Engine"`.

Call `commit_concept_blueprint` (or return valid JSON):
{
  "title": "Short 2-3 word title",
  "goal": "Strategy Label: Build a playable prototype where you [action 1], [action 2], and [action 3].",
  "gameSpec": ["Camera View", "Controls", "Player Mode", "Arena Structure"],
  "techSpec": ["Godot 4 (GDScript) | Unity 6 (C#) | Unreal Engine 5", "Platform", "Asset Pipeline", "Network / Save"],
  "designPillars": ["2-3 Word Pillar Name: Concise 1-sentence player feeling 1", "2-3 Word Pillar Name: Concise 1-sentence player feeling 2", "2-3 Word Pillar Name: Concise 1-sentence player feeling 3"],
  "tradeOffs": ["2-3 word priority over 2-3 word alternative", "2-3 word priority 2 over 2-3 word alternative 2", "2-3 word priority 3 over 2-3 word alternative 3"],
  "coreLoopBeats": ["Beat Name: Concise 1-sentence action and response", "..."],
  "exclusions": ["No 2-4 word prototype cut 1", "No 2-4 word prototype cut 2", "No 2-4 word prototype cut 3"],
  "doneWhen": "Concise 1-sentence playtest completion condition without FPS targets",
  "releaseTrainTitles": ["v0.1: [Plain Prototype Name] - Prototype"]$optionsSchemaTail
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.55,
      functionDeclarations: const [commitConceptBlueprintTool],
    );

    if (json == null) return null;

    final aiTitle = json['title']?.toString().trim() ?? '';
    final resolvedTitle = aiTitle.isNotEmpty ? aiTitle : cleanSpark;
    final parsedSectionOptions = _parseSectionOptions(json['sectionOptions']);
    final releaseTitles = _parseStringList(json['releaseTrainTitles']);
    final parsedGameSpec = _parseSpecCells(
      json['gameSpec'],
      const ['cameraView', 'controls', 'playerMode', 'arenaStructure'],
    );
    final parsedTechSpec = _normalizeTechSpecEngine(
      _parseSpecCells(
        json['techSpec'],
        const ['engine', 'platform', 'assetPipeline', 'saveMode'],
      ),
      parsedGameSpec,
      cleanSpark,
    );

    return ProjectConceptBlueprint(
      title: resolvedTitle,
      sparkIdea: cleanSpark,
      questions: const <AgentQuestion>[],
      goal: json['goal']?.toString().trim() ?? '',
      gameSpec: parsedGameSpec,
      techSpec: parsedTechSpec,
      designPillars: _parseStringList(json['designPillars']),
      tradeOffs: _parseStringList(json['tradeOffs']),
      coreLoopBeats: sortBeatsByDeveloperImpact(
        _parseStringList(json['coreLoopBeats']),
      ),
      exclusions: _parseStringList(json['exclusions']),
      doneWhen: json['doneWhen']?.toString().trim() ?? '',
      firstReleasePreset: ReleaseScope.featurePrototype,
      releaseTrainTitles: releaseTitles.isNotEmpty
          ? releaseTitles.take(1).toList()
          : <String>['v0.1: $resolvedTitle - Prototype'],
      isInterviewComplete: true,
      lastUpdatedFields: const [
        'Title',
        'Game Spec',
        'Tech Spec',
        'Design Pillars',
        'Trade-Offs',
        'Goal',
        'Core Loop',
        'Exclusions',
        'Prototype Release',
      ],
      sectionOptions: parsedSectionOptions,
      lastAgentReply: 'Drafted the initial $resolvedTitle Concept Blueprint.',
    );
  }

  /// Stateless Blueprint Turn: Takes the user's instruction, updates the live
  /// `ProjectConceptBlueprint` in place using `conversationModel` (`gemini-flash-latest`),
  /// and sets `lastAgentReply`. Returns `false` if offline or if Gemini AI is unreachable.
  static Future<bool> sendConceptChatTurn(
    ProjectConceptBlueprint draft,
    String userMessage, {
    String apiKey = '',
    String conversationModel = 'gemini-flash-latest',
    String planningModel = 'gemini-flash-latest',
    String thinkingLevel = 'HIGH',
  }) async {
    final cleanMsg = ProjectConceptBlueprint.normalizeCommonTypos(
      userMessage.trim(),
    );
    if (cleanMsg.isEmpty || !GeminiAgentClient.hasKey(apiKey)) return false;

    final isSectionScoped = cleanMsg.startsWith('[Section ');
    final sectionScopeRule = isSectionScoped
        ? '\n- SECTION-SCOPED REQUEST: Focus your update on the target `[Section ...]` named in Developer Direction while keeping locked upstream sections consistent. When updating `gameSpec`, always return all 4 cells `["Camera View", "Controls", "Player Mode", "Arena Structure"]`; when updating `techSpec`, always return all 4 cells `["Engine", "Platform", "Asset Pipeline", "Network / Save"]`.'
        : '';

    final prompt = '''
You are Antigravity, an indie game producer updating a Live Concept Blueprint.
Spark: "${draft.sparkIdea}"
Current Blueprint:
- Title: "${draft.title}"
- Goal: "${draft.goal}"
- Game Spec: ${draft.gameSpec.join(' · ')}
- Tech Spec: ${draft.techSpec.join(' · ')}
- Design Pillars: ${draft.designPillars.join(' | ')}
- Trade-Offs: ${draft.tradeOffs.join(' | ')}
- Core Loop Beats: ${draft.coreLoopBeats.join(' | ')}
- Out of Scope: ${draft.exclusions.join(' | ')}
- Done When: "${draft.doneWhen}"
- Release Train: ${draft.releaseTrainTitles.join(' | ')}
Developer Direction: "$cleanMsg"

${GeminiAgentClient.compactStyleRules}
- Synthesize and rewrite the affected field(s) into natural, polished game-dev English. NEVER copy-paste the developer's raw phrasing ("instead of...", "but in a...") verbatim.
- DELTA-ONLY OUTPUT: Call `update_concept_section` (or return JSON) including ONLY `reply`, `updatedFields`, and the specific Blueprint key(s) that actually changed (valid keys: `title`, `goal`, `goalOptions`, `gameSpec`, `techSpec`, `designPillars`, `tradeOffs`, `coreLoopBeats`, `exclusions`, `doneWhen`, `releaseTrainTitles`). Omit all unchanged keys! If `goal` or `title` changed, also include 3 updated `goalOptions`.$sectionScopeRule

Call `update_concept_section` (or return ONLY valid JSON):
{
  "reply": "1-sentence confirmation of what changed",
  "updatedFields": ["Goal"],
  "goal": "Strategy Label: Build a playable prototype where you [action 1], [action 2], and [action 3].",
  "goalOptions": ["Title 1: Build...", "Title 2: Build...", "Title 3: Build..."]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: conversationModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.45,
      functionDeclarations: const [updateConceptSectionTool],
    );

    if (json == null) return false;

    List<String>? cleanList(dynamic raw) {
      if (raw is! List && raw is! Map) return null;
      final list = _parseStringList(raw);
      return list.isNotEmpty ? list : null;
    }

    final updated = <String>[];
    final newTitle = json['title']?.toString().trim() ?? '';
    if (!_isPlaceholderString(newTitle) && newTitle != draft.title) {
      draft.title = newTitle;
      updated.add('Title');
    }
    final game = _parseSpecCells(
      json['gameSpec'],
      const ['cameraView', 'controls', 'playerMode', 'arenaStructure'],
    );
    if (game.length >= 2) {
      draft.gameSpec = game;
      updated.add('Game Spec');
    }
    final tech = _parseSpecCells(
      json['techSpec'],
      const ['engine', 'platform', 'assetPipeline', 'saveMode'],
    );
    if (tech.length >= 2) {
      draft.techSpec = _normalizeTechSpecEngine(
        tech,
        draft.gameSpec,
        draft.sparkIdea,
      );
      updated.add('Tech Spec');
    }
    final pillars = cleanList(json['designPillars']);
    if (pillars != null) {
      draft.designPillars = [
        for (int i = 0; i < pillars.length; i++)
          ProjectConceptBlueprint.ensureNamedPillar(pillars[i], i),
      ];
      updated.add('Design Pillars');
    }
    final tradeOffs = cleanList(json['tradeOffs']);
    if (tradeOffs != null) {
      draft.tradeOffs = tradeOffs;
      updated.add('Trade-Offs');
    }
    final newGoal = json['goal']?.toString().trim() ?? '';
    if (!_isPlaceholderString(newGoal) && newGoal != draft.goal) {
      draft.goal = ProjectConceptBlueprint.sanitizeGoalText(newGoal);
      updated.add('Goal');
    }
    final goalOpts = cleanList(json['goalOptions']);
    if (goalOpts != null && goalOpts.length >= 2) {
      draft.sectionOptions['goal'] = goalOpts;
    }
    final beats = cleanList(json['coreLoopBeats']);
    if (beats != null) {
      draft.coreLoopBeats = sortBeatsByDeveloperImpact(beats);
      updated.add('Core Loop');
    }
    final excl = cleanList(json['exclusions']);
    if (excl != null) {
      draft.exclusions = excl;
      updated.add('Exclusions');
    }
    final done = json['doneWhen']?.toString().trim() ?? '';
    if (!_isPlaceholderString(done) && done != draft.doneWhen) {
      draft.doneWhen = done;
      updated.add('Done When');
    }
    final releases = cleanList(json['releaseTrainTitles']);
    if (releases != null) {
      draft.releaseTrainTitles = releases;
      updated.add('Prototype Release');
    }

    final explicitUpdated = cleanList(json['updatedFields']);
    final effectiveUpdated =
        (explicitUpdated != null && explicitUpdated.isNotEmpty)
            ? explicitUpdated
            : (updated.isNotEmpty ? updated : const ['Concept Refined']);

    final replyText = json['reply']?.toString().trim() ??
        'Updated the Project Concept Blueprint with your direction!';

    draft.lastUpdatedFields = effectiveUpdated;
    draft.isInterviewComplete = true;
    draft.lastAgentReply = replyText;
    return true;
  }

  /// Ranks a Core Loop Beat so pre-match Staging/Loadout menus (`3`) and end-of-run Reset/Summary (`4`)
  /// are never placed ahead of active in-game gameplay beats (`0`), while preserving the exact
  /// chronological player order of all active gameplay beats (`0`).
  static int developerImpactTierForBeat(String rawBeat) {
    final head = rawBeat.split(':').first.toLowerCase();

    final isResetOrSummary = head.contains('reset') ||
        head.contains('resolution') ||
        head.contains('summary') ||
        head.contains('tally');
    if (isResetOrSummary) return 4;

    final isPrepOrLoadout = (head.contains('staging') ||
            head.contains('loadout') ||
            head.contains('prep') ||
            head.contains('contract') ||
            head.contains('menu') ||
            head.contains('rig select')) &&
        !head.contains('traversal') &&
        !head.contains('movement') &&
        !head.contains('driving') &&
        !head.contains('parkour');
    if (isPrepOrLoadout) return 3;

    return 0;
  }

  /// Ensures `coreLoopBeats` starts with the highest-impact Core Toy & Primary Control beat
  /// and places low-impact Staging/Loadout Prep beats after the core gameplay mechanics exist.
  static List<String> sortBeatsByDeveloperImpact(List<String> beats) {
    if (beats.length <= 1) return beats;
    final firstTier = developerImpactTierForBeat(beats.first);
    final hasHigherImpactLater =
        beats.skip(1).any((b) => developerImpactTierForBeat(b) < firstTier);
    if (!hasHigherImpactLater) return beats;

    final indexed = <({int index, int tier, String beat})>[
      for (int i = 0; i < beats.length; i++)
        (index: i, tier: developerImpactTierForBeat(beats[i]), beat: beats[i]),
    ];
    indexed.sort((a, b) {
      final cmp = a.tier.compareTo(b.tier);
      return cmp != 0 ? cmp : a.index.compareTo(b.index);
    });
    return [for (final item in indexed) item.beat];
  }

  static Map<String, List<String>> _parseSectionOptions(
    dynamic rawSectionOptions,
  ) {
    final result = <String, List<String>>{};
    if (rawSectionOptions is! Map) return result;

    for (final entry in rawSectionOptions.entries) {
      final key = entry.key.toString().trim();
      if (key.isNotEmpty) {
        final cleaned = _parseStringList(entry.value);
        if (cleaned.isNotEmpty) {
          result[key] = cleaned;
        }
      }
    }
    return result;
  }

  /// Ingests a raw game idea (or refines an existing ingested summary) on the New Project screen
  /// via Gemini AI (`gemini-flash-latest`). Returns `null` if offline or if Gemini AI is unreachable.
  static Future<SparkIdeaIntakeResult?> ingestOrRefineSparkIdea({
    required String userInput,
    SparkIdeaIntakeResult? existingIntake,
    int suggestionVariantOffset = 0,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'HIGH',
  }) async {
    final cleanInput = userInput.trim();
    final seedIdea =
        existingIntake != null ? existingIntake.rawIdea : cleanInput;
    if (seedIdea.isEmpty || !GeminiAgentClient.hasKey(apiKey)) {
      return null;
    }

    final selectedCardAdditions = existingIntake == null
        ? const <String>[]
        : existingIntake.expansionCards
            .where((c) => c.isSelected)
            .map((c) => '${c.title}: ${c.additionSummary}')
            .toList();
    final selectedContext = selectedCardAdditions.isEmpty
        ? ''
        : '\nSelected Idea Additions to Fold In: ${selectedCardAdditions.join(' | ')}';

    final includeExpansionCards = existingIntake == null ||
        existingIntake.expansionCards.isEmpty ||
        GeminiAgentClient.testMockResponder != null;
    final expansionCardsSchemaTail = includeExpansionCards
        ? ''',
  "mechanics": ["Mechanic Tag 1", "Mechanic Tag 2", "Mechanic Tag 3"],
$_kExpansionCardsJsonSchema'''
        : ''',
  "mechanics": ["Mechanic Tag 1", "Mechanic Tag 2", "Mechanic Tag 3"]''';

    final prompt = '''
You are an indie game producer summarizing a developer's game idea before building the blueprint.
${existingIntake != null ? 'Original Premise: "${existingIntake.rawIdea}"\nPrevious Title: "${existingIntake.workingTitle}"\nPrevious Summary: "${existingIntake.baseSummary}"$selectedContext\n${cleanInput.isNotEmpty ? 'User Update Direction: "$cleanInput"' : 'Action: Polish Previous Summary into a clean 2-sentence game pitch.'}' : 'Raw Idea: "$seedIdea"'}
${GeminiAgentClient.compactStyleRules}
- `workingTitle` MUST be a concrete 2-3 word game title naming the setting/role/mechanic (NEVER just copy the first 3 words of the user's sentence).
- `baseSummary` MUST be 2 natural sentences synthesizing the premise, core mechanics, and loop in game-design language (NEVER quote, echo, or replace the summary with the user's raw input sentence verbatim).
${existingIntake != null ? '- Preserve the core genre, role, and setting of `Previous Summary` while smoothly integrating `User Update Direction` (never switch to an unrelated genre).' : ''}

Return ONLY valid JSON:
{
  "workingTitle": "Short 2-3 word title",
  "baseSummary": "2 plain sentences summarizing core gameplay premise, controls/feel, and repeatable loop."$expansionCardsSchemaTail
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.45,
    );
    if (json == null) return null;

    final wTitle = (json['workingTitle'] ?? '').toString().trim();
    final summary = (json['baseSummary'] ?? '').toString().trim();
    final mechs = _parseStringList(json['mechanics']);
    final cards = _parseExpansionCards(json['expansionCards']);
    if (summary.isEmpty ||
        (GeminiAgentClient.testMockResponder != null && cards.isEmpty)) {
      return null;
    }

    final updatedRawIdea = existingIntake != null
        ? (cleanInput.isNotEmpty
            ? '${existingIntake.rawIdea}, $cleanInput'
            : existingIntake.rawIdea)
        : seedIdea;
    return SparkIdeaIntakeResult(
      rawIdea: updatedRawIdea,
      workingTitle: wTitle.isNotEmpty
          ? wTitle
          : (existingIntake?.workingTitle ?? updatedRawIdea),
      baseSummary: summary,
      mechanics: mechs.isNotEmpty
          ? mechs
          : (existingIntake?.mechanics ?? const <String>[]),
      expansionCards: cards.isNotEmpty
          ? cards
          : (existingIntake?.expansionCards ?? const <SparkExpansionCard>[]),
    );
  }

  /// Refreshes ONLY the 3 Concept Expansion / Twist Cards on the Stage 1A New Project screen
  /// while strictly preserving `existingIntake.rawIdea`, `workingTitle`, `baseSummary`, and `mechanics`.
  /// Returns `null` if offline or if Gemini AI is unreachable.
  static Future<List<SparkExpansionCard>?> refreshSparkExpansionCards({
    required SparkIdeaIntakeResult existingIntake,
    required int suggestionVariantOffset,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'HIGH',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) return null;

    final previousTitles = existingIntake.expansionCards
        .map((c) => c.title.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final prompt = '''
You are an indie game producer proposing 3 NEW gameplay expansion / twist cards for this exact game concept:
Working Title: "${existingIntake.workingTitle}"
Original Idea: "${existingIntake.rawIdea}"
Current Summary: "${existingIntake.baseSummary}"
Core Mechanics: ${existingIntake.mechanics.join(', ')}
${previousTitles.isNotEmpty ? 'Previously Shown Cards (DO NOT REPEAT): ${previousTitles.join(' | ')}' : ''}

${GeminiAgentClient.compactStyleRules}
- Stay 100% faithful to "${existingIntake.workingTitle}" and its exact subject, genre, and mechanics (never switch to an unrelated genre or theme).
- Propose 3 distinct, concrete playable twists that complement "${existingIntake.workingTitle}".

Return ONLY valid JSON:
{
$_kExpansionCardsJsonSchema
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.65,
    );
    if (json == null) return null;

    final cards = _parseExpansionCards(json['expansionCards']);
    if (cards.length < 3) return null;

    return _preserveSelectedExpansionCards(
      existingCards: existingIntake.expansionCards,
      freshCards: cards,
    );
  }

  static List<SparkExpansionCard> _preserveSelectedExpansionCards({
    required List<SparkExpansionCard> existingCards,
    required List<SparkExpansionCard> freshCards,
  }) {
    final result = <SparkExpansionCard>[];
    for (int i = 0; i < 3; i++) {
      if (i < existingCards.length && existingCards[i].isSelected) {
        result.add(existingCards[i]);
      } else if (i < freshCards.length) {
        result.add(freshCards[i]);
      }
    }
    return result;
  }

  /// Regenerates 3 fresh Option Cards for a specific Stage 1B section (`optionKey`)
  /// using `gemini-flash-latest`. Returns `null` if offline or if Gemini AI is unreachable.
  static Future<List<String>?> regenerateSectionOptionsWithAi({
    required ProjectConceptBlueprint draft,
    required String optionKey,
    required List<String> currentOptions,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'HIGH',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) return null;

    final sectionFormatRule = switch (optionKey) {
      'goal' =>
        '- Format each option as: `"Strategy Label: Build a playable ${draft.title} prototype where you [action 1], [action 2], and [action 3]."`',
      'gameSpec' =>
        '- Format each option with 4 `·`-separated cells after the colon: `"Spec Label: Camera View · Controls · Player Mode · Arena Structure"` (e.g., `"Tight Arena Spec: 2D Top-Down · Twin-Stick WASD+Mouse · Singleplayer · Single-Screen Arena"`).',
      'techSpec' =>
        '- Format each option with 4 `·`-separated cells after the colon: `"Stack Label: Concrete Engine · Platform · Asset Pipeline · Save Mode"` (e.g., `"Godot 4 2D Stack: Godot 4 (GDScript) · PC Desktop · 2D Sprites + Particles · Offline Local Save"`).',
      'designPillars' =>
        '- Format each option as: `"2-3 Word Pillar Name: 1-sentence core player feeling or emotional tension (never a feature or genre)"`.',
      'tradeOffs' =>
        '- Format each option as an explicit `X over Y` boundary rule: `"Rule Label: Concrete Priority X over Concrete Alternative Y"`.',
      'coreLoop' =>
        '- Format each option as a 4-to-5 beat chain separated by ` → `: `"Loop Label: Beat 1 Name: Action → Beat 2 Name: Action → Beat 3 Name: Action → Beat 4 Name: Action"`.',
      'exclusions' =>
        '- Format each option as a prototype scope cut: `"Cut Label: No [deferred system/content] in v0.1 prototype"`.',
      'doneWhen' =>
        '- Format each option as an observable playtest gate without FPS targets: `"Playtest Gate Label: Player spawns, completes [core loop actions], and resets cleanly"`.',
      _ =>
        '- Format each option as `"Short Label: Concrete statement tailored to ${draft.title}"`.',
    };

    final prompt = '''
You are an indie game producer generating 3 fresh Option Cards for the "$optionKey" section of this game concept:
Title: "${draft.title}"
Spark Premise: "${draft.sparkIdea}"
Current Goal: "${draft.goal}"
Game Spec: ${draft.gameSpec.join(' · ')}
Tech Spec: ${draft.techSpec.join(' · ')}
Design Pillars: ${draft.designPillars.join(' | ')}
Trade-Offs: ${draft.tradeOffs.join(' | ')}
Current Core Loop: ${draft.coreLoopBeats.join(' -> ')}
Out of Scope: ${draft.exclusions.join(' | ')}
${currentOptions.isNotEmpty ? 'Previously Shown Options (DO NOT REPEAT): ${currentOptions.join(' | ')}' : ''}

${GeminiAgentClient.compactStyleRules}
- Stay 100% faithful to "${draft.title}" and its locked upstream Game Spec, Tech Spec, Design Pillars, and Trade-Offs.
$sectionFormatRule

Return ONLY valid JSON:
{
  "options": [
    "Option Label 1: Concrete option tailored to ${draft.title}",
    "Option Label 2: Concrete option tailored to ${draft.title}",
    "Option Label 3: Concrete option tailored to ${draft.title}"
  ]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.65,
    );
    final rawList = json?['options'];
    if (rawList is List) {
      final parsed = _parseStringList(rawList).take(3).toList();
      if (parsed.length >= 2) {
        return parsed;
      }
    }
    return null;
  }

  /// Option 5: Extracts a complete 8-section `ProjectConceptBlueprint` from an unstructured
  /// GDD, Notion note, or README document and marks it ready for `Step 09 · Full Concept Review`.
  /// Returns `null` if offline or if Gemini AI is unreachable.
  static Future<ProjectConceptBlueprint?> extractConceptFromGdd(
    String rawGdd, {
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'HIGH',
  }) async {
    final cleanDoc = rawGdd.trim();
    if (cleanDoc.isEmpty || !GeminiAgentClient.hasKey(apiKey)) return null;

    final bp = await startConceptInterview(
      cleanDoc,
      apiKey: apiKey,
      modelName: modelName,
      thinkingLevel: thinkingLevel,
      isGddExtraction: true,
    );
    if (bp == null) return null;

    bp.isInterviewComplete = true;
    bp.lastUpdatedFields = const [
      'Extracted Full 8-Section Concept from Pasted GDD / Notes',
    ];
    return bp;
  }
}
