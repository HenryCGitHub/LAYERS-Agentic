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
/// guidance, letting the Agent dynamically determine the exact number of Core Loop Beats,
/// Design Pillars, Trade-Offs, and Exclusions needed for the concept.
class ProjectConceptAgent {
  /// Step 1B: Generates clarifying questions and initial Concept Blueprint from a spark idea.
  static Future<ProjectConceptBlueprint> startConceptInterview(
    String rawSpark, {
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanSpark = rawSpark.trim().isEmpty
        ? 'High-speed grappling hook parkour roguelite'
        : rawSpark.trim();
    final shortTitle = _derivePunchyTitle(cleanSpark);

    final prompt = '''
You are an expert indie game design producer interviewing a developer about their new game idea.
The developer pitched this spark idea: "$cleanSpark"

STRICT NAMING & WORDING RULES:
1. PLAIN FUNCTIONAL GAME-DEV NAMING (NO THEMATIC / LORE WORDING):
   - Use simple, literal, everyday game-dev words for all Beats, Release titles, and descriptions (e.g., "Crop Farming & Storage", "Shop Buy & Sell", "Arena Wave Combat").
   - NEVER use flowery, archaic, poetic, or roleplay/lore words (e.g., NEVER write "Husbandry", "Homestead", "Expedition", "Wasteland", "Adrenaline", "Ordinance").
2. BANNED BUZZWORDS:
   - Never use corporate filler ("deliver", "verified", "validate", "leverage", "unified", "end-to-end", "synergy", "seamlessly"). Start goals with concrete verbs like "Build..." or "Test...".
3. DESIGN PILLARS (CORE PLAYER EXPERIENCE):
   - Design pillars name the core experiences the game must create and how it should make the player feel—NOT how it is built.
   - A pillar is NOT a feature ("has a skill tree") and NOT a genre ("a roguelike"); it is the experience those things exist to hold up (e.g., "Every run teaches you something new", "Crashes and recoveries feel just as fun as clean speed").
4. TRADE-OFFS (PRIORITIZE X OVER Y):
   - Provide explicit "X over Y" priority rules so production knows what to protect when mechanics conflict (e.g., "Instant arcade response over realistic physics simulation").
5. COMPLETE SEQUENTIAL CORE LOOP BEATS (NO ARTIFICIAL TIME LIMIT):
   - Decompose the complete playable game loop into sequential Beats from start to finish (a game's core loop can take 30 seconds, 5 minutes, or 20 minutes depending on the genre—never force an artificial 30-second limit).
   - Include prep/staging areas, active gameplay beats, shop/upgrade/inventory menus, and loop resolution/reset whenever they are genuinely part of this game's loop.
   - Give each distinct player action, system interaction, escalation step, resource/reward step, and loop reset its own separate Beat (`Beat Name: Observable player action and system response`) instead of bundling multiple mechanics into a single line.
6. PROTOTYPE-FIRST RELEASE FOCUS:
   - In Stage 1, only define the Phase 1 Prototype release(s) needed to prove the Core Game Loop in greybox. Later phases (MVP Releases per Beat, Vertical Slice, Full Production) are unlocked after the Prototype completes.

Generate a JSON object tailored SPECIFICALLY to "$cleanSpark" using plain, literal game-dev terminology (include as many items in each array as this specific game concept genuinely needs):
{
  "title": "A simple, clear working title fitting '$cleanSpark'",
  "gameSpec": [
    "Camera View (e.g., 2D Top-Down or 3D First-Person)",
    "Controls (e.g., Twin-Stick WASD + Aim or Mouse + WASD)",
    "Player Mode (e.g., Singleplayer)",
    "Arena Structure (e.g., Single-Screen Wave Arena)"
  ],
  "techSpec": [
    "Engine (e.g., Godot 4 (2D) or Unity 6)",
    "Platform (e.g., PC (Steam / Desktop))",
    "Asset Pipeline (e.g., 2D Sprites + Particles or Low-Poly 3D)",
    "Network / Save (e.g., Offline-Only Local Save)"
  ],
  "designPillars": [
    "Experiential pillar describing how the game makes the player feel (never a feature or genre)",
    "..."
  ],
  "tradeOffs": [
    "Explicit X over Y priority rule",
    "..."
  ],
  "questions": [
    {
      "id": "q_perspective",
      "question": "Plain, direct question asking about camera perspective, movement speed, and control feel for '$cleanSpark'",
      "options": [
        "(Recommended) Specific perspective + control scheme option in plain game-dev terms",
        "Alternative perspective + control scheme option in plain game-dev terms"
      ]
    },
    {
      "id": "q_loop",
      "question": "Plain, direct question asking how the core mechanics of '$cleanSpark' connect in a playable loop",
      "options": [
        "(Recommended) Concrete gameplay loop option in plain game-dev terms",
        "Alternative gameplay loop option in plain game-dev terms"
      ]
    },
    {
      "id": "q_milestone",
      "question": "What should we build and test first in the Phase 1 Greybox Prototype?",
      "options": [
        "(Recommended) Specific v0.1 prototype sandbox goal in plain game-dev terms",
        "Alternative v0.1 prototype sandbox goal in plain game-dev terms"
      ]
    }
  ],
  "sectionOptions": {
    "goal": [
      "Short Card Title: Specific v0.1 prototype goal option 1 for '$cleanSpark'",
      "Short Card Title: Specific v0.1 prototype goal option 2 for '$cleanSpark'",
      "Short Card Title: Specific v0.1 prototype goal option 3 for '$cleanSpark'"
    ],
    "gameSpec": [
      "Camera · Controls · Mode · Level Layout option 1 tailored to '$cleanSpark'",
      "Camera · Controls · Mode · Level Layout option 2 tailored to '$cleanSpark'",
      "Camera · Controls · Mode · Level Layout option 3 tailored to '$cleanSpark'"
    ],
    "techSpec": [
      "Engine · Platform · Asset Pipeline · Save option 1 tailored to '$cleanSpark'",
      "Engine · Platform · Asset Pipeline · Save option 2 tailored to '$cleanSpark'",
      "Engine · Platform · Asset Pipeline · Save option 3 tailored to '$cleanSpark'"
    ],
    "designPillars": [
      "Short Pillar Title: Player experience focus option 1 tailored to '$cleanSpark'",
      "Short Pillar Title: Player experience focus option 2 tailored to '$cleanSpark'",
      "Short Pillar Title: Player experience focus option 3 tailored to '$cleanSpark'"
    ],
    "tradeOffs": [
      "Short Priority Title: Explicit X over Y trade-off option 1 tailored to '$cleanSpark'",
      "Short Priority Title: Explicit X over Y trade-off option 2 tailored to '$cleanSpark'",
      "Short Priority Title: Explicit X over Y trade-off option 3 tailored to '$cleanSpark'"
    ],
    "coreLoop": [
      "Short Loop Title: Beat 1 → Beat 2 → Beat 3 → Beat 4 tailored to '$cleanSpark'",
      "Short Loop Title: Alternative loop beat sequence tailored to '$cleanSpark'",
      "Short Loop Title: Third loop beat sequence tailored to '$cleanSpark'"
    ],
    "exclusions": [
      "Short Cut Title: Prototype scope-cut option 1 tailored to '$cleanSpark'",
      "Short Cut Title: Prototype scope-cut option 2 tailored to '$cleanSpark'",
      "Short Cut Title: Prototype scope-cut option 3 tailored to '$cleanSpark'"
    ],
    "doneWhen": [
      "Short Verification Title: Observable playtest verification option 1 tailored to '$cleanSpark'",
      "Short Verification Title: Observable playtest verification option 2 tailored to '$cleanSpark'",
      "Short Verification Title: Observable playtest verification option 3 tailored to '$cleanSpark'"
    ],
    "prototypeRelease": [
      "Single v0.1 Greybox: Single Greybox Prototype (v0.1) proving the complete '$cleanSpark' core loop",
      "Two-Step v0.1 → v0.2: v0.1 Core Mechanics Sandbox → v0.2 Full '$cleanSpark' Loop"
    ]
  },
  "goal": "Plain-English sentence starting with 'Build...' stating what mechanics are being built and why (zero corporate buzzwords or thematic fluff).",
  "coreLoopBeats": [
    "Plain Beat Name: Literal player action and mechanic",
    "..."
  ],
  "exclusions": [
    "Specific scope-creep feature to exclude from the Prototype",
    "..."
  ],
  "doneWhen": "Clear practical condition for when a playtester can complete the Prototype loop.",
  "releaseTrainTitles": [
    "v0.1: [Plain Functional Prototype Name, e.g. Core Movement & Game Loop] - Prototype"
  ]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.55,
    );

    if (json != null) {
      final qList = (json['questions'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(AgentQuestion.fromJson)
              .where((q) => q.question.isNotEmpty && q.options.isNotEmpty)
              .toList() ??
          const <AgentQuestion>[];

      final aiTitle = json['title']?.toString().trim() ?? '';
      final resolvedTitle = aiTitle.isNotEmpty ? aiTitle : shortTitle;
      final resolvedQuestions =
          qList.isNotEmpty ? qList : _defaultQuestionsForSpark(cleanSpark);
      final parsedSectionOptions = _parseSectionOptions(
        json['sectionOptions'],
        spark: cleanSpark,
        title: resolvedTitle,
      );

      return ProjectConceptBlueprint(
        title: resolvedTitle,
        sparkIdea: cleanSpark,
        questions: resolvedQuestions,
        goal: json['goal']?.toString() ??
            'Build a playable $resolvedTitle prototype centered on $cleanSpark with immediate game feel.',
        gameSpec: (json['gameSpec'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty && s != '...')
                .toList() ??
            _defaultGameSpec(),
        techSpec: (json['techSpec'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty && s != '...')
                .toList() ??
            _defaultTechSpec(),
        designPillars: (json['designPillars'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty && s != '...')
                .toList() ??
            _defaultDesignPillars(),
        tradeOffs: (json['tradeOffs'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty && s != '...')
                .toList() ??
            _defaultTradeOffs(),
        coreLoopBeats: (json['coreLoopBeats'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty && s != '...')
                .toList() ??
            _defaultCoreLoopForSpark(cleanSpark),
        exclusions: (json['exclusions'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty && s != '...')
                .toList() ??
            _defaultExclusions(),
        doneWhen: json['doneWhen']?.toString() ??
            'Playtester completes a full core loop cycle with responsive controls and clear feedback.',
        firstReleasePreset: ReleaseScope.featurePrototype,
        releaseTrainTitles: (json['releaseTrainTitles'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty && s != '...')
                .toList() ??
            _defaultReleaseTrain(resolvedTitle),
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
        chatHistory: _buildInitialChatHistory(
          spark: cleanSpark,
          title: resolvedTitle,
          questions: resolvedQuestions,
          modelUsed: modelName,
        ),
      );
    }

    final fallbackQuestions = _defaultQuestionsForSpark(cleanSpark);
    return ProjectConceptBlueprint(
      title: shortTitle,
      sparkIdea: cleanSpark,
      questions: fallbackQuestions,
      goal: 'Build a playable $shortTitle prototype centered on $cleanSpark with immediate game feel.',
      gameSpec: _defaultGameSpec(),
      techSpec: _defaultTechSpec(),
      designPillars: _defaultDesignPillars(),
      tradeOffs: _defaultTradeOffs(),
      coreLoopBeats: _defaultCoreLoopForSpark(cleanSpark),
      exclusions: _defaultExclusions(),
      doneWhen: 'A playtester can complete a full core loop cycle with responsive controls and clear hit/motion feedback.',
      firstReleasePreset: ReleaseScope.featurePrototype,
      releaseTrainTitles: _defaultReleaseTrain(shortTitle),
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
      sectionOptions: _defaultSectionOptionsForSpark(cleanSpark, shortTitle),
      chatHistory: _buildInitialChatHistory(
        spark: cleanSpark,
        title: shortTitle,
        questions: fallbackQuestions,
        modelUsed: modelName,
      ),
    );
  }

  static List<AgentChatMessage> _buildInitialChatHistory({
    required String spark,
    required String title,
    required List<AgentQuestion> questions,
    required String modelUsed,
  }) {
    final firstQ = questions.isNotEmpty
        ? questions.first.question
        : 'How does the initial Core Loop look to you?';
    final quickChips = <String>[
      if (questions.isNotEmpty)
        for (final opt in questions.first.options)
          _stripRecommendedPrefix(opt),
      'Looks great — ready to plan v0.1!',
    ];

    return [
      AgentChatMessage(
        id: 'msg_user_0',
        role: 'user',
        text: spark,
      ),
      AgentChatMessage(
        id: 'msg_ai_0',
        role: 'assistant',
        modelUsed: modelUsed,
        updatedFields: const ['Drafted Initial Concept Blueprint'],
        text: 'I drafted the initial **$title** Concept Blueprint based on your idea!\n\n'
            'We can refine each section one at a time (Goal, Game Spec, Tech Spec, Design Pillars, Trade-Offs, Core Loop Beats, Out of Scope, Done When, and Prototype Release).\n\n'
            '**First up:** $firstQ',
        quickReplies: quickChips,
      ),
    ];
  }

  /// Turn-by-turn Co-Design Chat: Takes the user's message, updates the live
  /// `ProjectConceptBlueprint` in place using `conversationModel` (`gemini-flash-latest`),
  /// and appends the AI's conversational reply + next follow-up question / quick replies.
  static Future<ProjectConceptBlueprint> sendConceptChatTurn(
    ProjectConceptBlueprint draft,
    String userMessage, {
    String apiKey = '',
    String conversationModel = 'gemini-flash-latest',
    String planningModel = 'gemini-4-argon',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanMsg = userMessage.trim();
    if (cleanMsg.isEmpty) return draft;

    draft.chatHistory.add(
      AgentChatMessage(
        id: 'msg_user_${draft.chatHistory.length}',
        role: 'user',
        text: cleanMsg,
      ),
    );

    final recentHistory = draft.chatHistory
        .map((m) => '${m.isUser ? "Developer" : "Antigravity"}: ${m.text}')
        .join('\n\n');

    final prompt = '''
You are Antigravity, an expert game producer pair-designing a game concept with a developer.
Original Spark: "${draft.sparkIdea}"

Current Live Project Concept Blueprint:
- Title: "${draft.title}"
- Game Spec: ${draft.gameSpec.join(' · ')}
- Tech Spec: ${draft.techSpec.join(' · ')}
- Design Pillars (Core Player Experience):
${draft.designPillars.map((p) => '  * $p').join('\n')}
- Trade-Offs (Prioritize X over Y):
${draft.tradeOffs.map((t) => '  * $t').join('\n')}
- Goal: "${draft.goal}"
- In Scope (Core Loop Beats):
${draft.coreLoopBeats.map((b) => '  * $b').join('\n')}
- Out of Scope (Hard Exclusions):
${draft.exclusions.map((e) => '  * $e').join('\n')}
- Done When: "${draft.doneWhen}"
- Prototype Release(s):
${draft.releaseTrainTitles.map((r) => '  * $r').join('\n')}

Conversation History:
$recentHistory

Developer's Latest Turn: "$cleanMsg"

STRICT NAMING & WORDING RULES:
- Use PLAIN, LITERAL, NON-THEMATIC game-dev terms for all Beats, Release titles, and descriptions (e.g., "Crop Farming & Storage", "Shop Buy & Sell", "Arena Wave Combat").
- NEVER use flowery, archaic, or roleplay/lore words (e.g., NEVER write "Husbandry", "Homestead", "Expedition", "Wasteland", "Adrenaline").
- NEVER use corporate buzzwords ("deliver", "verified", "validate", "leverage", "unified", "end-to-end", "synergy", "seamlessly").
- Design Pillars MUST describe the core player experience and how the game makes the player feel—NEVER a feature ("has a skill tree") and NEVER a genre ("a roguelike").
- Trade-Offs MUST use explicit "X over Y" priority rules.
- Decompose `coreLoopBeats` into as many distinct sequential playable Beats as the game loop genuinely needs—do not artificially compress multiple steps into a fixed count.
- Keep `releaseTrainTitles` focused on the Phase 1 Prototype release(s); MVP, Vertical Slice, and Full Production phases are defined later after Prototype completion.

Task:
1. Apply the developer's latest direction, answer, or adjustment directly to the Project Concept Blueprint fields (`title`, `gameSpec`, `techSpec`, `designPillars`, `tradeOffs`, `goal`, `coreLoopBeats`, `exclusions`, `doneWhen`, `releaseTrainTitles`). Keep everything concrete, playtestable, and in plain developer English.
2. Write a concise, natural conversational `reply` confirming what you updated on the Blueprint and asking a natural follow-up question.
3. Provide short clickable `quickReplies` the developer can click for their next turn.
4. List which blueprint sections changed in `updatedFields` (e.g. `["Goal", "Design Pillars", "Core Loop"]`).

Return ONLY a JSON object with this schema:
{
  "reply": "Conversational response + follow-up question",
  "quickReplies": ["Short reply option", "..."],
  "updatedFields": ["Goal", "Core Loop"],
  "title": "Updated or existing title",
  "gameSpec": ["Camera View", "Controls", "Player Mode", "Arena Structure"],
  "techSpec": ["Engine", "Platform", "Asset Pipeline", "Network / Save"],
  "designPillars": [
    "Experiential Pillar (how it feels, never a feature/genre)",
    "..."
  ],
  "tradeOffs": [
    "X over Y rule",
    "..."
  ],
  "goal": "Updated plain-English goal starting with 'Build...'",
  "coreLoopBeats": [
    "Plain Beat Name: Literal player action and system response",
    "..."
  ],
  "exclusions": [
    "Concrete exclusion",
    "..."
  ],
  "doneWhen": "Updated Done When condition",
  "releaseTrainTitles": [
    "v0.1: ... - Prototype"
  ]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: conversationModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.45,
    );

    if (json != null) {
      final updated = <String>[];
      final newTitle = json['title']?.toString().trim() ?? '';
      if (newTitle.isNotEmpty && newTitle != draft.title) {
        draft.title = newTitle;
        updated.add('Title');
      }
      final game = (json['gameSpec'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (game != null && game.isNotEmpty) {
        draft.gameSpec = game;
        updated.add('Game Spec');
      }
      final tech = (json['techSpec'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (tech != null && tech.isNotEmpty) {
        draft.techSpec = tech;
        updated.add('Tech Spec');
      }
      final pillars = (json['designPillars'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (pillars != null && pillars.isNotEmpty) {
        draft.designPillars = pillars;
        updated.add('Design Pillars');
      }
      final tradeOffs = (json['tradeOffs'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (tradeOffs != null && tradeOffs.isNotEmpty) {
        draft.tradeOffs = tradeOffs;
        updated.add('Trade-Offs');
      }
      final newGoal = json['goal']?.toString().trim() ?? '';
      if (newGoal.isNotEmpty && newGoal != draft.goal) {
        draft.goal = newGoal;
        updated.add('Goal');
      }
      final beats = (json['coreLoopBeats'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (beats != null && beats.isNotEmpty) {
        draft.coreLoopBeats = beats;
        updated.add('Core Loop');
      }
      final excl = (json['exclusions'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (excl != null && excl.isNotEmpty) {
        draft.exclusions = excl;
        updated.add('Exclusions');
      }
      final done = json['doneWhen']?.toString().trim() ?? '';
      if (done.isNotEmpty && done != draft.doneWhen) {
        draft.doneWhen = done;
        updated.add('Done When');
      }
      final releases = (json['releaseTrainTitles'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (releases != null && releases.isNotEmpty) {
        draft.releaseTrainTitles = releases;
        updated.add('Prototype Release');
      }

      final explicitUpdated = (json['updatedFields'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final effectiveUpdated = (explicitUpdated != null && explicitUpdated.isNotEmpty)
          ? explicitUpdated
          : (updated.isNotEmpty ? updated : const ['Concept Refined']);

      final quickReplies = (json['quickReplies'] as List?)
              ?.map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty && s != '...')
              .toList() ??
          const <String>[];

      final replyText = json['reply']?.toString().trim() ??
          'Updated the Project Concept Blueprint with your direction! Anything else you want to adjust before we plan v0.1?';

      draft.lastUpdatedFields = effectiveUpdated;
      draft.isInterviewComplete = true;
      draft.chatHistory.add(
        AgentChatMessage(
          id: 'msg_ai_${draft.chatHistory.length}',
          role: 'assistant',
          modelUsed: conversationModel,
          text: replyText,
          quickReplies: quickReplies,
          updatedFields: effectiveUpdated,
        ),
      );
      return draft;
    }

    // Offline / deterministic turn update fallback
    _applyDeterministicChatTurn(draft, cleanMsg, conversationModel);
    return draft;
  }

  static void _applyDeterministicChatTurn(
    ProjectConceptBlueprint draft,
    String userMsg,
    String modelUsed,
  ) {
    final lower = userMsg.toLowerCase();
    final updated = <String>[];

    if (lower.contains('exclude') ||
        lower.contains('cut') ||
        lower.contains('remove') ||
        lower.contains('out of scope')) {
      draft.exclusions.add(userMsg);
      updated.add('Exclusions');
    } else if (lower.contains('pillar')) {
      draft.designPillars.add(userMsg);
      updated.add('Design Pillars');
    } else if (lower.contains('over ')) {
      draft.tradeOffs.add(userMsg);
      updated.add('Trade-Offs');
    } else if (lower.contains('godot') ||
        lower.contains('unity') ||
        lower.contains('unreal') ||
        lower.contains('engine')) {
      if (draft.techSpec.isEmpty) {
        draft.techSpec = _defaultTechSpec();
      }
      draft.techSpec[0] = userMsg;
      updated.add('Tech Spec');
    } else if (lower.contains('title') || lower.startsWith('rename')) {
      final cleanedTitle = userMsg
          .replaceFirst(RegExp(r'^(rename|change title|title)\s*(to|:)?\s*', caseSensitive: false), '')
          .trim();
      if (cleanedTitle.isNotEmpty) {
        draft.title = cleanedTitle;
        updated.add('Title');
      }
    } else {
      draft.goal =
          'Build a ${draft.title} prototype focused on "$userMsg" with responsive controls and clear feedback.';
      if (lower.contains('2d') || lower.contains('3d') || lower.contains('top-down')) {
        if (draft.gameSpec.isNotEmpty) {
          draft.gameSpec[0] = userMsg;
          updated.add('Game Spec');
        }
        if (draft.techSpec.isNotEmpty) {
          draft.techSpec[0] = userMsg;
          updated.add('Tech Spec');
        }
      }
      if (draft.coreLoopBeats.isNotEmpty) {
        draft.coreLoopBeats[0] = 'Core Focus: $userMsg';
      } else {
        draft.coreLoopBeats.add('Core Focus: $userMsg');
      }
      updated.addAll(['Goal', 'Core Loop']);
    }

    // Pick next unanswered question if available
    final assistantTurnCount = draft.chatHistory.where((m) => !m.isUser).length;
    final nextQIdx = assistantTurnCount < draft.questions.length ? assistantTurnCount : -1;
    final followUp = nextQIdx != -1
        ? '\n\n**Next question:** ${draft.questions[nextQIdx].question}'
        : '\n\nHow does the updated Blueprint look now? Feel free to ask for more tweaks or click **Approve & Plan v0.1 Release →**.';
    final nextChips = nextQIdx != -1
        ? draft.questions[nextQIdx].options.map(_stripRecommendedPrefix).toList()
        : <String>[
            'Split combat into separate approach and strike beats',
            'Add a boss/hazard challenge beat',
            'Looks great — ready for v0.1!',
          ];

    draft.lastUpdatedFields = updated;
    draft.isInterviewComplete = true;
    draft.chatHistory.add(
      AgentChatMessage(
        id: 'msg_ai_${draft.chatHistory.length}',
        role: 'assistant',
        modelUsed: modelUsed,
        updatedFields: updated,
        text: 'Got it — I updated the **${updated.join(" & ")}** on the live Blueprint to incorporate *"$userMsg"*.$followUp',
        quickReplies: nextChips,
      ),
    );
  }

  /// Step 1C: Synthesizes the `ProjectConceptBlueprint` once the user answers the interview questions.
  /// Calls Gemini (`gemini-flash-latest`) when an API key is available, with instant deterministic fallback for unit tests/offline.
  static Future<ProjectConceptBlueprint> synthesizeFromInterview(
    ProjectConceptBlueprint draft, {
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final qaSummary = draft.questions
        .map((q) => '- Q: ${q.question}\n  A: ${_stripRecommendedPrefix(q.effectiveAnswer)}')
        .join('\n');

    final prompt = '''
You are an expert game producer finalizing a Project Concept Blueprint after interviewing the developer.
Original Spark Idea: "${draft.sparkIdea}"
Working Title: "${draft.title}"
Developer's Interview Answers:
$qaSummary

STRICT NAMING & WORDING RULES:
- Use PLAIN, LITERAL, NON-THEMATIC game-dev words for all Beats, Release titles, and descriptions (e.g., "Crop Farming & Storage", "Shop Buy & Sell", "Arena Wave Combat").
- NEVER use flowery, archaic, or roleplay/lore words (e.g., NEVER write "Husbandry", "Homestead", "Expedition", "Wasteland", "Adrenaline").
- NEVER use corporate buzzwords ("deliver", "verified", "validate", "leverage", "unified", "end-to-end", "synergy", "seamlessly").
- Design Pillars MUST describe the core player experience and how the game makes the player feel—NEVER a feature ("has a skill tree") and NEVER a genre ("a roguelike").
- Decompose `coreLoopBeats` into as many sequential playable Beats as the game loop genuinely requires from start to finish.
- Keep `releaseTrainTitles` focused on the Phase 1 Prototype release(s).

Synthesize these exact choices into a cohesive Project Concept JSON object using plain, literal game-dev terminology:
{
  "title": "Simple, clear working title fitting the spark and answers",
  "gameSpec": ["Camera View", "Controls", "Player Mode", "Arena Structure"],
  "techSpec": ["Engine", "Platform", "Asset Pipeline", "Network / Save"],
  "designPillars": [
    "Experiential Pillar (how it feels, never a feature/genre)",
    "..."
  ],
  "tradeOffs": [
    "Prioritize X over Y rule",
    "..."
  ],
  "goal": "Plain-English sentence starting with 'Build...' stating what is being built and why, incorporating the developer's interview answers.",
  "coreLoopBeats": [
    "Plain Beat Name: Literal observable player action & mechanic",
    "..."
  ],
  "exclusions": [
    "Concrete scope-creep mechanic strictly cut from the Prototype",
    "..."
  ],
  "doneWhen": "Clear, testable condition for when a playtester can complete the Prototype loop.",
  "releaseTrainTitles": [
    "v0.1: [Plain Functional Prototype Name] - Prototype"
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

    if (json != null) {
      final newTitle = json['title']?.toString().trim() ?? '';
      if (newTitle.isNotEmpty) draft.title = newTitle;
      final game = (json['gameSpec'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (game != null && game.isNotEmpty) draft.gameSpec = game;
      final tech = (json['techSpec'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (tech != null && tech.isNotEmpty) draft.techSpec = tech;
      final pillars = (json['designPillars'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (pillars != null && pillars.isNotEmpty) draft.designPillars = pillars;
      final tradeOffs = (json['tradeOffs'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (tradeOffs != null && tradeOffs.isNotEmpty) draft.tradeOffs = tradeOffs;
      final newGoal = json['goal']?.toString().trim() ?? '';
      if (newGoal.isNotEmpty) draft.goal = newGoal;
      final beats = (json['coreLoopBeats'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (beats != null && beats.isNotEmpty) draft.coreLoopBeats = beats;
      final excl = (json['exclusions'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (excl != null && excl.isNotEmpty) draft.exclusions = excl;
      final done = json['doneWhen']?.toString().trim() ?? '';
      if (done.isNotEmpty) draft.doneWhen = done;
      final releases = (json['releaseTrainTitles'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '...')
          .toList();
      if (releases != null && releases.isNotEmpty) {
        draft.releaseTrainTitles = releases;
      }
      draft.isInterviewComplete = true;
      return draft;
    }

    return synthesizeDeterministic(draft);
  }

  /// Synchronous deterministic synthesis fallback (also used by unit tests).
  static ProjectConceptBlueprint synthesizeDeterministic(
    ProjectConceptBlueprint draft,
  ) {
    final perspective = draft.questions.isNotEmpty
        ? _stripRecommendedPrefix(draft.questions[0].effectiveAnswer)
        : 'Responsive Action';
    final loopFocus = draft.questions.length > 1
        ? _stripRecommendedPrefix(draft.questions[1].effectiveAnswer)
        : draft.sparkIdea;
    final scopeChoice = draft.questions.length > 2
        ? _stripRecommendedPrefix(draft.questions[2].effectiveAnswer)
        : 'Prototype';

    ReleaseScope preset = ReleaseScope.featurePrototype;
    final lowerScope = scopeChoice.toLowerCase();
    if (lowerScope.contains('vertical slice')) {
      preset = ReleaseScope.verticalSlice;
    } else if (lowerScope.contains('mvp')) {
      preset = ReleaseScope.mvp;
    }

    draft.firstReleasePreset = preset;
    draft.goal =
        'Build a $perspective ${draft.title} prototype where the player executes "$loopFocus" with crisp visual and audio feedback.';
    if (draft.gameSpec.isEmpty) {
      draft.gameSpec = _defaultGameSpec();
    } else {
      draft.gameSpec[0] = perspective;
    }
    if (draft.techSpec.isEmpty) {
      draft.techSpec = _defaultTechSpec();
    }
    if (draft.designPillars.isEmpty) {
      draft.designPillars = _defaultDesignPillars();
    }
    if (draft.tradeOffs.isEmpty) {
      draft.tradeOffs = _defaultTradeOffs();
    }

    if (draft.coreLoopBeats.isNotEmpty) {
      draft.coreLoopBeats[0] = 'Primary Loop: $loopFocus ($perspective)';
    } else {
      draft.coreLoopBeats = _defaultCoreLoopForSpark(loopFocus);
    }

    draft.doneWhen =
        'Playtester completes a full "$loopFocus" cycle in a greybox test arena at 60 FPS with zero state soft-locks.';
    draft.isInterviewComplete = true;
    return draft;
  }

  static String _stripRecommendedPrefix(String input) {
    return input.replaceFirst(RegExp(r'^\(Recommended\)\s*', caseSensitive: false), '').trim();
  }

  static String _derivePunchyTitle(String spark) {
    const stopWords = {
      'the', 'and', 'with', 'for', 'game', 'about', 'fast', 'that', 'also',
      'combines', 'like', 'where', 'you', 'can', 'into', 'from',
    };
    final words = spark
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stopWords.contains(w.toLowerCase()))
        .take(3)
        .toList();
    if (words.isEmpty) return 'Core Prototype';
    return words
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  static List<String> _defaultGameSpec() {
    return [
      '2D Top-Down',
      'Twin-Stick (WASD + Aim)',
      'Singleplayer',
      'Single-Screen Wave Arena',
    ];
  }

  static List<String> _defaultTechSpec() {
    return [
      'Godot 4 (2D)',
      'PC (Steam / Desktop)',
      '2D Sprites + Particles',
      'Offline-Only Local Save',
    ];
  }

  static List<String> _defaultDesignPillars() {
    return [
      'Flow-State Momentum: Never force the player to stop moving to act or aim.',
      'Readable Chaos: Every hazard and attack is clearly telegraphed before impact.',
      'Every Run Teaches Something: Failures feel fair, fast to recover from, and immediately repeatable.',
    ];
  }

  static List<String> _defaultTradeOffs() {
    return [
      'Instant arcade responsiveness over realistic physics inertia',
      'Clear visual silhouette readability over dense particle clutter',
      'Fast 1-key loop reset over multi-screen menu flows',
    ];
  }

  static List<AgentQuestion> _defaultQuestionsForSpark(String spark) {
    return [
      AgentQuestion(
        id: 'q_perspective',
        question: 'What camera perspective and control feel fits "$spark" best?',
        options: [
          '(Recommended) 3D First-Person / Third-Person Momentum Action',
          '2D Side-Scrolling Precision Platformer',
          'Top-Down / Isometric Twin-Stick Arena',
        ],
      ),
      AgentQuestion(
        id: 'q_loop',
        question: 'How should the core gameplay loop connect from entry to reset?',
        options: [
          '(Recommended) Chain movement mechanics to clear hazards, collect drops, and reset',
          'Time-trial traversal through escalating obstacle rooms for speed ranks',
          'Tactical resource management and counter-attacks under wave pressure',
        ],
      ),
      AgentQuestion(
        id: 'q_milestone',
        question: 'What is our target scope for the Phase 1 Prototype?',
        options: [
          '(Recommended) Prototype — 1 Greybox Arena proving the core loop beats work together',
          'Two-Step Prototype — v0.1 Player Movement & Controls followed by v0.2 Full Core Loop Arena',
        ],
      ),
    ];
  }

  static List<String> _defaultCoreLoopForSpark(String spark) {
    return [
      'Staging & Loadout Prep: Select active tool or movement modifier in the starting zone',
      'Arena Entry & Traversal: Enter the arena and chain primary movement impulses across terrain',
      'Hazard & Wave Spawning: Trigger room encounters with telegraphed enemy waves and active hazards',
      'Primary Combat & Timing: Strike targets using momentum windows, deflection, and dodge recovery',
      'Resource Drop & Pickup: Collect dropped energy, ammo, or health orbs mid-encounter',
      'Room Clear & Upgrade Choice: Complete wave objective and select a run-modifying upgrade',
      'Loop Resolution & Instant Reset: Bank round results or trigger 1-key arena reset on failure',
    ];
  }

  static List<String> _defaultExclusions() {
    return [
      'Multi-branch skill trees and deep inventory crafting menus',
      'Online multiplayer matchmaking and netcode replication',
      'Cinematic story cutscenes and NPC dialogue trees',
    ];
  }

  static List<String> _defaultReleaseTrain(String title) {
    return [
      'v0.1: Core Movement & Game Loop - Prototype',
    ];
  }

  static Map<String, List<String>> _parseSectionOptions(
    dynamic rawSectionOptions, {
    required String spark,
    required String title,
  }) {
    final defaults = _defaultSectionOptionsForSpark(spark, title);
    if (rawSectionOptions is! Map) return defaults;

    final result = <String, List<String>>{};
    for (final entry in defaults.entries) {
      final rawList = rawSectionOptions[entry.key];
      if (rawList is List) {
        final cleaned = rawList
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty && s != '...')
            .toList();
        if (cleaned.isNotEmpty) {
          result[entry.key] = cleaned;
          continue;
        }
      }
      result[entry.key] = entry.value;
    }
    return result;
  }

  static Map<String, List<String>> _defaultSectionOptionsForSpark(
    String spark,
    String title,
  ) {
    return {
      'goal': [
        'Single-Arena Loop: Build a playable $title prototype centered on $spark in a single test arena',
        'Prep + Arena Loop: Include an interactive prep & staging zone before entering the core $title gameplay loop',
        'Controls & Feel First: Focus v0.1 on the primary $title player controls and core mechanic feel first',
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
        'Unbroken Momentum: Prioritize continuous movement velocity and readable telegraphs for $title',
        'Tactical Positioning: Prioritize deliberate positioning decisions and high-clarity feedback for $title',
        'Chain-Reaction Mastery: Prioritize fast chain-reactions and rewarding loop mastery for $title',
      ],
      'tradeOffs': [
        'Instant Input Response: Instant arcade input response over realistic physics inertia',
        'Animation Commitment: Deliberate animation commitment over instant cancelable movement',
        'Greybox Readability: Clean greybox readability over heavy visual shaders in v0.1',
      ],
      'coreLoop': [
        'Complete 4-Beat Loop: Prep & Loadout → Active Gameplay Beats → Resource & Upgrade Choice → Loop Resolution & Reset',
        'Direct Action Loop: Immediate Entry → Core Mechanic Escalation → Target Objective → Score / Loot Tally → Instant Reset',
        'Skill Mastery Loop: Setup & Positioning → Primary Skill Execution → Hazard / Counter Response → Reward Payout → Next Round',
      ],
      'exclusions': [
        'Cut Trees, Co-Op & Story: Cut multi-branch skill trees, online co-op, and story cutscenes from the $title Prototype',
        'Defer Bosses & Crafting: Defer deep inventory crafting and multi-phase bosses until MVP releases',
        'Defer Meta-Save & Audio: Defer persistent meta-progression save files and custom audio menus until MVP',
      ],
      'doneWhen': [
        '60 FPS Full Loop: Playtester completes a full $title core loop cycle at 60 FPS with zero soft-locks',
        'All Beats & Clean Reset: Playtester executes all $title core beats, collects rewards, and resets cleanly',
        '3 Consecutive Runs: Playtester completes 3 consecutive $title loop cycles with responsive controls and clear feedback',
      ],
      'prototypeRelease': [
        'Single v0.1 Greybox: Single Greybox Prototype (v0.1) proving all $title Core Loop Beats work together',
        'Two-Step v0.1 → v0.2: v0.1 Player Movement & Controls → v0.2 Full $title Core Loop Arena',
      ],
    };
  }

  /// Ingests a raw game idea (or refines an existing ingested summary) on the New Project screen,
  /// returning a concise plain-English summary + 3 toggleable Concept Expansion Cards tailored
  /// to the user's idea.
  static Future<SparkIdeaIntakeResult> ingestOrRefineSparkIdea({
    required String userInput,
    SparkIdeaIntakeResult? existingIntake,
    int suggestionVariantOffset = 0,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanInput = userInput.trim();
    final isRefinement = existingIntake != null && cleanInput.isNotEmpty;
    final seedIdea = existingIntake != null
        ? (cleanInput.isEmpty
            ? existingIntake.rawIdea
            : '${existingIntake.rawIdea} ($cleanInput)')
        : (cleanInput.isEmpty
            ? 'High-speed grappling hook parkour roguelite'
            : cleanInput);
    final fallbackTitle = _derivePunchyTitle(
      existingIntake?.rawIdea ?? seedIdea,
    );

    if (GeminiAgentClient.hasKey(apiKey)) {
      final prompt = '''
You are an expert indie game design producer helping a developer shape their game idea before building the blueprint.
${isRefinement ? 'Existing Working Title: "${existingIntake.workingTitle}"\nExisting Summary: "${existingIntake.baseSummary}"\nDeveloper Refinement Request: "$cleanInput"' : 'Developer Pitched Idea: "$seedIdea"'}

Return ONLY a JSON object using plain, literal game-dev language (zero corporate buzzwords or archaic lore words):
{
  "workingTitle": "Short 2-3 word working title",
  "baseSummary": "2 plain-English sentences summarizing the core gameplay premise, player controls/feel, and repeatable loop (incorporating any refinement request).",
  "mechanics": [
    "Short Mechanic Tag 1",
    "Short Mechanic Tag 2",
    "Short Mechanic Tag 3"
  ],
  "expansionCards": [
    {
      "badge": "01 · CORE MECHANIC TWIST",
      "title": "Short 2-4 Word Mechanic Name",
      "description": "1-2 plain sentences describing how this mechanic deepens primary player actions.",
      "additionSummary": "1 concise clause summarizing this mechanic when toggled on"
    },
    {
      "badge": "02 · RISK / REWARD HOOK",
      "title": "Short 2-4 Word Hook Name",
      "description": "1-2 plain sentences describing a tension or risk/reward trade-off inside the loop.",
      "additionSummary": "1 concise clause summarizing this risk/reward hook when toggled on"
    },
    {
      "badge": "03 · LOOP PAYOFF & UPGRADE",
      "title": "Short 2-4 Word Payoff Name",
      "description": "1-2 plain sentences describing a between-round upgrade or loop completion payoff.",
      "additionSummary": "1 concise clause summarizing this payoff when toggled on"
    }
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
      if (json != null) {
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
        if (summary.isNotEmpty && cards.length == 3) {
          return SparkIdeaIntakeResult(
            rawIdea: seedIdea,
            workingTitle: wTitle.isNotEmpty ? wTitle : fallbackTitle,
            baseSummary: summary,
            mechanics: mechs.isNotEmpty
                ? mechs
                : _deterministicMechanicsForIdea(seedIdea),
            expansionCards: cards,
          );
        }
      }
    }

    return buildDeterministicSparkIntake(
      rawIdea: existingIntake?.rawIdea ?? seedIdea,
      refinementText: isRefinement ? cleanInput : null,
      existingIntake: existingIntake,
      suggestionVariantOffset: suggestionVariantOffset,
    );
  }

  static List<String> _deterministicMechanicsForIdea(String idea) {
    final lower = idea.toLowerCase();
    if (lower.contains('grappl') || lower.contains('parkour') || lower.contains('swing')) {
      return const [
        'Momentum Grapple Swing',
        'Mid-Air Dash Cancel',
        'Fast Arena Reset',
      ];
    }
    if (lower.contains('sub') || lower.contains('ocean') || lower.contains('sea') || lower.contains('salvage')) {
      return const [
        'Submarine Depth Navigation',
        'Sonar & Salvage Pickup',
        'Dock Hull Upgrades',
      ];
    }
    if (lower.contains('katana') || lower.contains('deflect') || lower.contains('boss') || lower.contains('parry')) {
      return const [
        'Timed Parry & Deflect',
        'Dash-Strike Counter',
        'Multi-Phase Boss Telegraph',
      ];
    }
    if (lower.contains('farm') || lower.contains('crop') || lower.contains('shop') || lower.contains('alchemy')) {
      return const [
        'Resource Gathering & Plots',
        'Recipe Processing',
        'Shop Customer Orders',
      ];
    }
    return const [
      'Responsive Core Controls',
      'Escalating Round Objective',
      'Between-Round Loadout Choice',
    ];
  }

  static SparkIdeaIntakeResult buildDeterministicSparkIntake({
    required String rawIdea,
    String? refinementText,
    SparkIdeaIntakeResult? existingIntake,
    int suggestionVariantOffset = 0,
  }) {
    final cleanIdea = rawIdea.trim().isEmpty
        ? 'High-speed grappling hook parkour roguelite'
        : rawIdea.trim();
    final title = existingIntake?.workingTitle ?? _derivePunchyTitle(cleanIdea);
    final mechs = List<String>.from(
      existingIntake?.mechanics ?? _deterministicMechanicsForIdea(cleanIdea),
    );

    String summary;
    if (existingIntake != null &&
        refinementText != null &&
        refinementText.trim().isNotEmpty) {
      final cleanRef = refinementText.trim();
      summary =
          '${existingIntake.baseSummary} Updated with your direction: $cleanRef.';
      final shortTag = cleanRef.split(RegExp(r'\s+')).take(3).join(' ');
      if (!mechs.contains(shortTag)) {
        mechs.add(shortTag);
      }
    } else {
      summary =
          '$title centers on "$cleanIdea" — players execute responsive core controls, clear escalating round objectives with immediate visual/audio feedback, and reset or upgrade cleanly between runs.';
    }

    final lower = cleanIdea.toLowerCase();
    final List<SparkExpansionCard> pool;
    if (lower.contains('grappl') || lower.contains('parkour') || lower.contains('swing')) {
      pool = [
        SparkExpansionCard(
          badge: '01 · CORE MECHANIC TWIST',
          title: 'Grapple Reel-Slam & Ricochet',
          description:
              'Pull straight toward a hooked surface or enemy and trigger a high-speed ricochet launch on impact.',
          additionSummary: 'Grapple reel-slam and wall ricochet launch',
          accentType: 'amber',
        ),
        SparkExpansionCard(
          badge: '02 · RISK / REWARD HOOK',
          title: 'Floor-Is-Hazard Speed Multiplier',
          description:
              'Staying airborne chains a velocity multiplier up to 3.0x, while touching the floor resets the combo meter.',
          additionSummary: 'Airborne velocity combo multiplier with floor reset',
          accentType: 'emerald',
        ),
        SparkExpansionCard(
          badge: '03 · LOOP PAYOFF & UPGRADE',
          title: 'Between-Room Hook Modifiers',
          description:
              'Pick 1 of 3 hook modifications (shock tether, dual-anchor, explosive detach) after clearing each arena.',
          additionSummary: 'Between-room hook modifier draft',
          accentType: 'neutral',
        ),
        SparkExpansionCard(
          badge: '01 · CORE MECHANIC TWIST',
          title: 'Throwable Anchor Pylon',
          description:
              'Toss a temporary mid-air anchor point into open space to swing across wide gaps with no walls.',
          additionSummary: 'Throwable mid-air grapple anchor pylon',
          accentType: 'amber',
        ),
        SparkExpansionCard(
          badge: '02 · RISK / REWARD HOOK',
          title: 'Tether Overheat Boost',
          description:
              'Hold boost while swinging to double pull speed at the cost of overheating the winch for 2 seconds.',
          additionSummary: 'Overheat winch boost trade-off',
          accentType: 'emerald',
        ),
        SparkExpansionCard(
          badge: '03 · LOOP PAYOFF & UPGRADE',
          title: 'Time-Gate Shortcut Vaults',
          description:
              'Clear a room under the par timer to unlock a bonus vault exit with high-tier movement augments.',
          additionSummary: 'Par-time shortcut vaults between arenas',
          accentType: 'neutral',
        ),
      ];
    } else if (lower.contains('sub') || lower.contains('ocean') || lower.contains('salvage')) {
      pool = [
        SparkExpansionCard(
          badge: '01 · CORE MECHANIC TWIST',
          title: 'Winch Tether & Heavy Tow',
          description:
              'Latch a physical winch cable onto sunken cargo or sea creatures, adjusting sub ballast to tow heavy loads.',
          additionSummary: 'Physical winch tether and ballast tow physics',
          accentType: 'amber',
        ),
        SparkExpansionCard(
          badge: '02 · RISK / REWARD HOOK',
          title: 'Depth Pressure & Floodlight Drain',
          description:
              'Diving into deeper trenches yields rare salvage, but high pressure drains battery floodlights faster.',
          additionSummary: 'Deep-trench hull pressure and battery drain trade-off',
          accentType: 'emerald',
        ),
        SparkExpansionCard(
          badge: '03 · LOOP PAYOFF & UPGRADE',
          title: 'Drydock Sonar & Hull Bay',
          description:
              'Cash in photos and salvage at the surface dock to upgrade sonar pulse range, floodlights, and cargo bays.',
          additionSummary: 'Surface drydock sonar and hull upgrade bay',
          accentType: 'neutral',
        ),
        SparkExpansionCard(
          badge: '01 · CORE MECHANIC TWIST',
          title: 'Acoustic Decoy Beacon',
          description:
              'Deploy sound beacons that lure territorial trench creatures away from high-value wreck sites.',
          additionSummary: 'Acoustic decoy beacons for stealth salvage',
          accentType: 'amber',
        ),
        SparkExpansionCard(
          badge: '02 · RISK / REWARD HOOK',
          title: 'Overweight Cargo Ballast',
          description:
              'Carrying extra salvage beyond capacity slows vertical ascent speed when returning to the surface.',
          additionSummary: 'Overweight cargo ascent speed penalty',
          accentType: 'emerald',
        ),
        SparkExpansionCard(
          badge: '03 · LOOP PAYOFF & UPGRADE',
          title: 'Marine Codex Bounties',
          description:
              'Complete photo sets of rare trench species to unlock specialized camera lenses and thrusters.',
          additionSummary: 'Marine photo codex bounties and lens unlocks',
          accentType: 'neutral',
        ),
      ];
    } else {
      pool = [
        SparkExpansionCard(
          badge: '01 · CORE MECHANIC TWIST',
          title: 'Precision Timing Cancel & Boost',
          description:
              'Time your primary action on beat or impact to cancel recovery frames into an immediate speed or power burst.',
          additionSummary: 'Precision timing cancel into speed/power burst',
          accentType: 'amber',
        ),
        SparkExpansionCard(
          badge: '02 · RISK / REWARD HOOK',
          title: 'Push-Your-Luck Streak Multiplier',
          description:
              'Bank your round rewards early for a safe payout, or risk an extra escalation wave for double rewards.',
          additionSummary: 'Push-your-luck wave escalation vs safe bank choice',
          accentType: 'emerald',
        ),
        SparkExpansionCard(
          badge: '03 · LOOP PAYOFF & UPGRADE',
          title: '3-Choice Loadout Draft Bench',
          description:
              'Between rounds, pick 1 of 3 tactile mechanic modifiers that noticeably alter how your primary tool behaves.',
          additionSummary: 'Between-round 3-choice mechanic modifier draft',
          accentType: 'neutral',
        ),
        SparkExpansionCard(
          badge: '01 · CORE MECHANIC TWIST',
          title: 'Interactive Arena Hazards',
          description:
              'Knock or redirect arena obstacles into targets to trigger chain-reaction clears.',
          additionSummary: 'Redirectable arena hazards and chain reactions',
          accentType: 'amber',
        ),
        SparkExpansionCard(
          badge: '02 · RISK / REWARD HOOK',
          title: 'Overcharge Cooldown Gamble',
          description:
              'Overcharge your primary ability for 2x area effect, triggering a brief cooldown vent if it misses.',
          additionSummary: 'Overcharge ability risk/reward cooldown vent',
          accentType: 'emerald',
        ),
        SparkExpansionCard(
          badge: '03 · LOOP PAYOFF & UPGRADE',
          title: 'Instant Trial Target Range',
          description:
              'Test newly unlocked upgrades on a live dummy target right inside the prep zone before starting the next round.',
          additionSummary: 'Interactive prep-zone target dummy test range',
          accentType: 'neutral',
        ),
      ];
    }

    final startIdx = (suggestionVariantOffset * 3) % pool.length;
    final selectedCards = <SparkExpansionCard>[
      for (int i = 0; i < 3; i++) pool[(startIdx + i) % pool.length],
    ];

    // Preserve selection state if refreshing/refining
    if (existingIntake != null) {
      for (final card in selectedCards) {
        final match = existingIntake.expansionCards
            .where((c) => c.title == card.title)
            .toList();
        if (match.isNotEmpty) {
          card.isSelected = match.first.isSelected;
        }
      }
    }

    return SparkIdeaIntakeResult(
      rawIdea: cleanIdea,
      workingTitle: title,
      baseSummary: summary,
      mechanics: mechs,
      expansionCards: selectedCards,
    );
  }
}
