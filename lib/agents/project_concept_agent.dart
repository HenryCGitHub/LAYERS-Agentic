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
  /// Step 1B: Generates the initial 9-section Concept Blueprint from a spark idea via Gemini AI.
  /// Returns `null` if offline or if Gemini AI cannot be reached.
  static Future<ProjectConceptBlueprint?> startConceptInterview(
    String rawSpark, {
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanSpark = ProjectConceptBlueprint.normalizeCommonTypos(
      rawSpark.trim(),
    );
    if (cleanSpark.isEmpty || !GeminiAgentClient.hasKey(apiKey)) {
      return null;
    }

    final prompt = '''
You are an indie game producer creating a Stage 1 Concept Blueprint for this spark idea:
"$cleanSpark"

${GeminiAgentClient.compactStyleRules}
- Decompose `coreLoopBeats` into sequential playable Beats (`Beat Name: Observable player action and system response`) ordered by PLAYABLE DEVELOPER IMPACT ("Fastest Path to the Fun"):
  1. Beat 1 MUST be the Core Toy & Primary Control (the #1 interactive verb on screen 80% of the time—e.g. Player Movement & Grapple/Dash, Vehicle Handling, Grid Placement/Harvest, or Card Play/Targeting).
  2. Beats 2–3 MUST be Primary Action & Reactive Challenge (weapons/skills and enemies/hazards/orders that push back).
  3. Subsequent Beats cover Reward/Pickup, Objective/Upgrade, Pre-Run Loadout/Staging Prep (built after the core mechanics exist), and Loop Reset.
- Format `goal` as: "Strategy Label: Build a playable [Title] prototype where you [action 1], [action 2], and [action 3]."

Return ONLY valid JSON:
{
  "title": "Short 2-3 word title",
  "goal": "Strategy Label: Build a playable prototype where you [action 1], [action 2], and [action 3].",
  "gameSpec": ["Camera View", "Controls", "Player Mode", "Arena Structure"],
  "techSpec": ["Engine", "Platform", "Asset Pipeline", "Network / Save"],
  "designPillars": ["2-3 Word Pillar Name: Experiential player feeling 1", "2-3 Word Pillar Name: Experiential player feeling 2", "2-3 Word Pillar Name: Experiential player feeling 3"],
  "tradeOffs": ["Concrete X over Y rule tailored to $cleanSpark", "Concrete X over Y rule 2", "Concrete X over Y rule 3"],
  "coreLoopBeats": ["Beat Name: Literal action and response", "..."],
  "exclusions": ["Specific prototype exclusion for $cleanSpark", "Specific prototype exclusion 2", "Specific prototype exclusion 3"],
  "doneWhen": "Concrete playtest completion condition",
  "releaseTrainTitles": ["v0.1: [Plain Prototype Name] - Prototype"],
  "sectionOptions": {
    "goal": ["Title 1: Build...", "Title 2: Build...", "Title 3: Build..."],
    "gameSpec": ["View · Controls · Mode · Structure", "View 2 · Controls 2 · Mode 2 · Structure 2", "View 3 · Controls 3 · Mode 3 · Structure 3"],
    "techSpec": ["Engine · Platform · Pipeline · Save", "Engine 2 · Platform 2 · Pipeline 2 · Save 2", "Engine 3 · Platform 3 · Pipeline 3 · Save 3"],
    "designPillars": ["Title 1: Experience...", "Title 2: Experience...", "Title 3: Experience..."],
    "tradeOffs": ["Rule Title 1: Specific X over Y rule for $cleanSpark", "Rule Title 2: Specific X over Y rule", "Rule Title 3: Specific X over Y rule"],
    "coreLoop": ["Title 1: Beat A → Beat B → Beat C → Beat D", "Title 2: ...", "Title 3: ..."],
    "exclusions": ["Cut Title 1: Specific prototype cut for $cleanSpark", "Cut Title 2: Specific prototype cut", "Cut Title 3: Specific prototype cut"],
    "doneWhen": ["Playtest Gate 1: Observable completion condition", "Playtest Gate 2: ...", "Playtest Gate 3: ..."]
  }
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.55,
    );

    if (json == null) return null;

    final aiTitle = json['title']?.toString().trim() ?? '';
    final resolvedTitle = aiTitle.isNotEmpty ? aiTitle : cleanSpark;
    final parsedSectionOptions = _parseSectionOptions(json['sectionOptions']);

    List<String> parseList(dynamic raw) {
      if (raw is! List) return <String>[];
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
    }

    final releaseTitles = parseList(json['releaseTrainTitles']);

    return ProjectConceptBlueprint(
      title: resolvedTitle,
      sparkIdea: cleanSpark,
      questions: const <AgentQuestion>[],
      goal: json['goal']?.toString().trim() ?? '',
      gameSpec: parseList(json['gameSpec']),
      techSpec: parseList(json['techSpec']),
      designPillars: parseList(json['designPillars']),
      tradeOffs: parseList(json['tradeOffs']),
      coreLoopBeats: sortBeatsByDeveloperImpact(
        parseList(json['coreLoopBeats']),
      ),
      exclusions: parseList(json['exclusions']),
      doneWhen: json['doneWhen']?.toString().trim() ?? '',
      firstReleasePreset: ReleaseScope.featurePrototype,
      releaseTrainTitles: releaseTitles.isNotEmpty
          ? releaseTitles
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
    String planningModel = 'gemini-4-argon',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanMsg = ProjectConceptBlueprint.normalizeCommonTypos(
      userMessage.trim(),
    );
    if (cleanMsg.isEmpty || !GeminiAgentClient.hasKey(apiKey)) return false;

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
- Format `goal` as: "Strategy Label: Build a playable [Title] prototype where you [action 1], [action 2], and [action 3]."
- DELTA-ONLY OUTPUT: Include ONLY `reply`, `updatedFields`, and the specific Blueprint key(s) that actually changed (omit all unchanged arrays!). If `goal` or `title` changed, also include 3 updated `goalOptions`.

Return ONLY valid JSON:
{
  "reply": "1-sentence confirmation of what changed",
  "updatedFields": ["Goal"],
  "title": "Only if title changed",
  "goal": "Only if goal changed",
  "goalOptions": ["Title 1: Build...", "Title 2: Build...", "Title 3: Build..."],
  "gameSpec": ["Only if changed"],
  "techSpec": ["Only if changed"],
  "designPillars": ["Only if changed"],
  "tradeOffs": ["Only if changed"],
  "coreLoopBeats": ["Only if changed"],
  "exclusions": ["Only if changed"],
  "doneWhen": "Only if changed",
  "releaseTrainTitles": ["Only if changed"]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: conversationModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.45,
    );

    if (json == null) return false;

    bool isPlaceholder(String s) =>
        s.isEmpty ||
        s == '...' ||
        s.toLowerCase().startsWith('only if ');

    List<String>? cleanList(dynamic raw) {
      if (raw is! List) return null;
      final list = raw
          .map((e) => e.toString().trim())
          .where((s) => !isPlaceholder(s))
          .toList();
      return list.isNotEmpty ? list : null;
    }

    final updated = <String>[];
    final newTitle = json['title']?.toString().trim() ?? '';
    if (!isPlaceholder(newTitle) && newTitle != draft.title) {
      draft.title = newTitle;
      updated.add('Title');
    }
    final game = cleanList(json['gameSpec']);
    if (game != null && game.length >= 2) {
      draft.gameSpec = game;
      updated.add('Game Spec');
    }
    final tech = cleanList(json['techSpec']);
    if (tech != null && tech.length >= 2) {
      draft.techSpec = tech;
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
    if (!isPlaceholder(newGoal) && newGoal != draft.goal) {
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
    if (!isPlaceholder(done) && done != draft.doneWhen) {
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

  /// Ranks a Core Loop Beat by Playable Developer Impact ("Fastest Path to the Fun"):
  /// - `0`: Core Toy & Primary Control
  /// - `1`: Primary Action & Reactive Challenge
  /// - `2`: Mid-Loop Reward & Objective Escalation
  /// - `3`: Pre-Match Prep / Loadout / Staging Multipliers
  /// - `4`: Loop Closure & Reset
  static int developerImpactTierForBeat(String rawBeat) {
    final head = rawBeat.split(':').first.toLowerCase();
    final full = rawBeat.toLowerCase();

    final isResetOrSummary = head.contains('reset') ||
        head.contains('resolution') ||
        head.contains('summary') ||
        head.contains('tally') ||
        head.contains('dropoff');
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

    final isCoreToyOrControl = head.contains('traversal') ||
        head.contains('movement') ||
        head.contains('locomotion') ||
        head.contains('parkour') ||
        head.contains('wall-run') ||
        head.contains('grappl') ||
        head.contains('driving') ||
        head.contains('steering') ||
        head.contains('control') ||
        head.contains('plant') ||
        head.contains('harvest') ||
        head.contains('card play') ||
        head.contains('placement') ||
        full.contains('primary movement') ||
        full.contains('chain wall-runs');
    if (isCoreToyOrControl) return 0;

    final isActionOrChallenge = head.contains('combat') ||
        head.contains('weapon') ||
        head.contains('hazard') ||
        head.contains('wave') ||
        head.contains('ambush') ||
        head.contains('enemy') ||
        head.contains('strike') ||
        head.contains('attack') ||
        head.contains('shoot');
    if (isActionOrChallenge) return 1;

    return 2;
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
      final rawList = entry.value;
      if (key.isNotEmpty && rawList is List) {
        final cleaned = rawList
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty && s != '...')
            .toList();
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
    String thinkingLevel = 'LOW',
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

    final prompt = '''
You are an indie game producer summarizing a developer's game idea before building the blueprint.
${existingIntake != null ? 'Original Premise: "${existingIntake.rawIdea}"\nPrevious Title: "${existingIntake.workingTitle}"\nPrevious Summary: "${existingIntake.baseSummary}"\nPrevious Mechanics: ${existingIntake.mechanics.join(', ')}$selectedContext\n${cleanInput.isNotEmpty ? 'User Update Direction: "$cleanInput"' : 'Action: Fold any Selected Idea Additions into Previous Summary and propose 3 fresh expansion cards.'}' : 'Raw Idea: "$seedIdea"'}
${GeminiAgentClient.compactStyleRules}
- `workingTitle` MUST be a concrete 2-3 word game title naming the setting/role/mechanic (NEVER just copy the first 3 words of the user's sentence).
- `baseSummary` MUST be 2 natural sentences synthesizing the premise, core mechanics, and loop in game-design language (NEVER quote, echo, or replace the summary with the user's raw input sentence verbatim).
${existingIntake != null ? '- Preserve the core genre, role, and setting of `Previous Summary` while smoothly integrating `User Update Direction` (never switch to an unrelated genre).' : ''}

Return ONLY valid JSON:
{
  "workingTitle": "Short 2-3 word title",
  "baseSummary": "2 plain sentences summarizing core gameplay premise, controls/feel, and repeatable loop.",
  "mechanics": ["Mechanic Tag 1", "Mechanic Tag 2", "Mechanic Tag 3"],
  "expansionCards": [
    {"badge": "01 · CORE MECHANIC TWIST", "title": "2-4 Word Name", "description": "1-2 plain sentences.", "additionSummary": "Concise clause"},
    {"badge": "02 · RISK / REWARD HOOK", "title": "2-4 Word Name", "description": "1-2 plain sentences.", "additionSummary": "Concise clause"},
    {"badge": "03 · LOOP PAYOFF & UPGRADE", "title": "2-4 Word Name", "description": "1-2 plain sentences.", "additionSummary": "Concise clause"}
  ]
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
    final rawMechs = json['mechanics'];
    final mechs = rawMechs is List
        ? rawMechs
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    final rawCards = json['expansionCards'];
    final cards = <SparkExpansionCard>[];
    if (rawCards is List) {
      const accents = ['amber', 'emerald', 'neutral'];
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
              additionSummary:
                  (item['additionSummary'] ?? item['title'] ?? '')
                      .toString()
                      .trim(),
              accentType: accents[i % accents.length],
            ),
          );
        }
      }
    }
    if (summary.isEmpty || cards.isEmpty) return null;

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
      expansionCards: cards,
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
    String thinkingLevel = 'LOW',
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
  "expansionCards": [
    {"badge": "01 · CORE MECHANIC TWIST", "title": "2-4 Word Name", "description": "1-2 plain sentences describing the observable mechanic.", "additionSummary": "Concise clause"},
    {"badge": "02 · RISK / REWARD HOOK", "title": "2-4 Word Name", "description": "1-2 plain sentences describing the risk/reward tension.", "additionSummary": "Concise clause"},
    {"badge": "03 · LOOP PAYOFF & UPGRADE", "title": "2-4 Word Name", "description": "1-2 plain sentences describing the progression payoff.", "additionSummary": "Concise clause"}
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
    if (json == null) return null;

    final rawCards = json['expansionCards'];
    final cards = <SparkExpansionCard>[];
    if (rawCards is List) {
      const accents = ['amber', 'emerald', 'neutral'];
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
              additionSummary:
                  (item['additionSummary'] ?? item['title'] ?? '')
                      .toString()
                      .trim(),
              accentType: accents[i % accents.length],
            ),
          );
        }
      }
    }
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
    String thinkingLevel = 'LOW',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) return null;

    final prompt = '''
You are an indie game producer generating 3 fresh Option Cards for the "$optionKey" section of this game concept:
Title: "${draft.title}"
Spark Premise: "${draft.sparkIdea}"
Current Goal: "${draft.goal}"
Current Core Loop: ${draft.coreLoopBeats.join(' -> ')}
${currentOptions.isNotEmpty ? 'Previously Shown Options (DO NOT REPEAT): ${currentOptions.join(' | ')}' : ''}

${GeminiAgentClient.compactStyleRules}
- Stay 100% faithful to "${draft.title}" and its exact subject and mechanics.
- Format each option as "Short Label: Concrete statement tailored to ${draft.title}".

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
      final parsed = rawList
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .take(3)
          .toList();
      if (parsed.length >= 2) {
        return parsed;
      }
    }
    return null;
  }

  /// Option 5: Extracts a complete 9-section `ProjectConceptBlueprint` from an unstructured
  /// GDD, Notion note, or README document and marks it ready for `Step 10 · Full Review`.
  /// Returns `null` if offline or if Gemini AI is unreachable.
  static Future<ProjectConceptBlueprint?> extractConceptFromGdd(
    String rawGdd, {
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanDoc = rawGdd.trim();
    if (cleanDoc.isEmpty || !GeminiAgentClient.hasKey(apiKey)) return null;

    final bp = await startConceptInterview(
      cleanDoc,
      apiKey: apiKey,
      modelName: modelName,
      thinkingLevel: thinkingLevel,
    );
    if (bp == null) return null;

    bp.isInterviewComplete = true;
    bp.lastUpdatedFields = const [
      'Extracted Full 9-Section Concept from Pasted GDD / Notes',
    ];
    return bp;
  }
}
