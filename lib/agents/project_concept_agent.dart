import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import 'gemini_agent_client.dart';

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
5. COMPLETE SEQUENTIAL CORE LOOP BEATS:
   - Decompose the complete playable game loop into sequential Beats from start to finish.
   - Give each distinct player action, system interaction, escalation step, resource/reward step, and loop reset its own separate Beat instead of bundling multiple mechanics into a single line.
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
    "v0.1: [Plain Functional Prototype Name, e.g. Core Toy & Movement Loop] - Prototype"
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
          'Two-Step Prototype — v0.1 Movement Toy followed by v0.2 Target & Hazard Loop',
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
      'v0.1: Core Toy & Movement Loop - Prototype',
    ];
  }
}
