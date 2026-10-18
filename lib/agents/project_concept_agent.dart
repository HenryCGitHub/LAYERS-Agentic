import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import 'gemini_agent_client.dart';

/// Stage 1 Agent: Turns a 1-sentence "Spark" idea into an Antigravity-style
/// 3-question multiple-choice Concept Interview, and synthesizes the answers
/// into a structured `ProjectConceptBlueprint` + Release Train roadmap.
class ProjectConceptAgent {
  /// Step 1B: Generates 3 tailored multiple-choice clarifying questions from a 1-line spark.
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
The developer pitched this 1-line spark: "$cleanSpark"

STRICT NAMING & WORDING RULES:
1. PLAIN FUNCTIONAL GAME-DEV NAMING (NO THEMATIC / LORE WORDING):
   - Use simple, literal, everyday game-dev words for all Beats, Release titles, and descriptions (e.g., "Crop Farming & Storage", "Shop Buy & Sell", "Arena Wave Combat").
   - NEVER use flowery, archaic, poetic, or roleplay/lore words (e.g., NEVER write "Husbandry", "Homestead", "Expedition", "Wasteland", "Adrenaline", "Ordinance").
2. BANNED BUZZWORDS:
   - Never use corporate filler ("deliver", "verified", "validate", "leverage", "unified", "end-to-end", "synergy", "seamlessly"). Start goals with concrete verbs like "Build..." or "Test...".
3. DESIGN PILLARS (CORE PLAYER EXPERIENCE):
   - Game design pillars are a short list of 3–4 statements that name the core experiences the game must create and how it should make the player feel—NOT how it is built.
   - A pillar is NOT a feature ("has a skill tree") and NOT a genre ("a roguelike"); it is the experience those things exist to hold up (e.g., "Every run teaches you something new", "Crashes and recoveries feel just as fun as clean speed").
4. TRADE-OFFS (PRIORITIZE X OVER Y):
   - Provide 2–3 explicit "X over Y" priority rules so Stage 2 knows what to protect when mechanics conflict (e.g., "Instant arcade response over realistic physics simulation").

Generate a JSON object tailored SPECIFICALLY to "$cleanSpark" using plain, literal game-dev terminology:
{
  "title": "A simple, clear 2-3 word working title fitting '$cleanSpark'",
  "gameSpec": [
    "Camera View (e.g., 2D Top-Down or 3D First-Person)",
    "Controls (e.g., Twin-Stick WASD + Aim or Mouse + WASD)",
    "Player Mode (e.g., Singleplayer)",
    "Arena Structure (e.g., Single-Screen Wave Arena or 3-Minute Run Arenas)"
  ],
  "techSpec": [
    "Engine (e.g., Godot 4 (2D) or Unity 6)",
    "Platform (e.g., PC (Steam / Desktop))",
    "Asset Pipeline (e.g., 2D Sprites + Particles or Low-Poly 3D)",
    "Network / Save (e.g., Offline-Only Local Save)"
  ],
  "designPillars": [
    "Short experiential pillar #1 (how the game makes the player feel, never a feature or genre)",
    "Short experiential pillar #2 (core player experience, never a feature or genre)",
    "Short experiential pillar #3 (core player experience, never a feature or genre)"
  ],
  "tradeOffs": [
    "Prioritize X over Y rule #1",
    "Prioritize X over Y rule #2",
    "Prioritize X over Y rule #3"
  ],
  "questions": [
    {
      "id": "q_perspective",
      "question": "Plain, direct question asking about camera perspective, movement speed, and control feel for '$cleanSpark'",
      "options": [
        "(Recommended) Specific perspective + control scheme #1 in plain game-dev terms",
        "Specific perspective + control scheme #2 in plain game-dev terms",
        "Specific perspective + control scheme #3 in plain game-dev terms"
      ]
    },
    {
      "id": "q_loop",
      "question": "Plain, direct question asking how the core mechanics of '$cleanSpark' connect in a 30-second playable loop",
      "options": [
        "(Recommended) Concrete 30-second gameplay loop option #1 in plain game-dev terms",
        "Concrete 30-second gameplay loop option #2 in plain game-dev terms",
        "Concrete 30-second gameplay loop option #3 in plain game-dev terms"
      ]
    },
    {
      "id": "q_milestone",
      "question": "What should we build and test first in the Release v0.1 Greybox Prototype?",
      "options": [
        "(Recommended) Specific v0.1 prototype sandbox goal #1 in plain game-dev terms",
        "Specific v0.1 prototype sandbox goal #2 in plain game-dev terms",
        "Specific v0.1 prototype sandbox goal #3 in plain game-dev terms"
      ]
    }
  ],
  "goal": "1 plain-English sentence starting with 'Build...' stating what mechanics are being built and why (zero corporate buzzwords or thematic fluff).",
  "coreLoopBeats": [
    "Plain Beat Name 1: Literal player action and mechanic",
    "Plain Beat Name 2: Literal interaction or system step",
    "Plain Beat Name 3: Literal loop payoff and reset"
  ],
  "exclusions": [
    "Specific scope-creep feature #1 to exclude from v0.1",
    "Specific scope-creep feature #2 to exclude from v0.1",
    "Specific scope-creep feature #3 to exclude from v0.1"
  ],
  "doneWhen": "Clear practical condition for when a playtester can complete the v0.1 prototype loop.",
  "releaseTrainTitles": [
    "v0.1: [Plain Functional Prototype Name, e.g. Core Movement & Combat Loop] - Prototype",
    "v0.2: [Plain Functional MVP Name, e.g. Shop Economy & Wave Loop] - MVP",
    "v0.3: [Plain Functional Vertical Slice Name, e.g. Full Arena & Polish] - Vertical Slice"
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
                .where((s) => s.isNotEmpty)
                .toList() ??
            _defaultGameSpec(),
        techSpec: (json['techSpec'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            _defaultTechSpec(),
        designPillars: (json['designPillars'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            _defaultDesignPillars(),
        tradeOffs: (json['tradeOffs'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            _defaultTradeOffs(),
        coreLoopBeats: (json['coreLoopBeats'] as List?)
                ?.map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toList() ??
            _defaultCoreLoopForSpark(cleanSpark),
        exclusions: (json['exclusions'] as List?)
                ?.map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toList() ??
            _defaultExclusions(),
        doneWhen: json['doneWhen']?.toString() ??
            'Playtester completes a full 30-second core loop cycle with responsive controls and clear feedback.',
        firstReleasePreset: ReleaseScope.featurePrototype,
        releaseTrainTitles: (json['releaseTrainTitles'] as List?)
                ?.map((e) => e.toString())
                .where((s) => s.isNotEmpty)
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
          'Release Train',
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
      doneWhen: 'A playtester can complete a full 30-second core loop cycle with responsive controls and clear hit/motion feedback.',
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
        'Release Train',
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
        : 'How does the initial 30-second core loop look to you?';
    final quickChips = <String>[
      if (questions.isNotEmpty)
        for (final opt in questions.first.options.take(3))
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
        text: 'I drafted the initial **$title** Concept Blueprint on the right based on your idea!\n\n'
            'We can go back and forth right here to tweak anything (Title, Tech Spec, Design Pillars, Trade-Offs, 30s Core Loop Beats, or Release Train).\n\n'
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
You are Antigravity, an expert game producer pair-designing a game concept with a developer in a turn-by-turn chat.
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
- In Scope (30s Core Loop Beats):
${draft.coreLoopBeats.map((b) => '  * $b').join('\n')}
- Out of Scope (Hard Exclusions):
${draft.exclusions.map((e) => '  * $e').join('\n')}
- Done When: "${draft.doneWhen}"
- Release Train:
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

Task:
1. Apply the developer's latest direction, answer, or adjustment directly to the Project Concept Blueprint fields (`title`, `gameSpec`, `techSpec`, `designPillars`, `tradeOffs`, `goal`, `coreLoopBeats`, `exclusions`, `doneWhen`, `releaseTrainTitles`). Keep everything concrete, playtestable, and in plain developer English.
2. Write a concise, natural conversational `reply` (2-3 sentences max) confirming what you updated on the Blueprint and asking 1 natural follow-up question (or inviting any final tweaks before Release v0.1 planning).
3. Provide 2-3 short clickable `quickReplies` the developer can click for their next turn.
4. List which blueprint sections changed in `updatedFields` (e.g. `["Goal", "Design Pillars", "Core Loop"]`).

Return ONLY a JSON object with this schema:
{
  "reply": "Conversational response + 1 follow-up question",
  "quickReplies": ["Short reply option 1", "Short reply option 2", "Short reply option 3"],
  "updatedFields": ["Goal", "Core Loop"],
  "title": "Updated or existing title",
  "gameSpec": ["Camera View", "Controls", "Player Mode", "Arena Structure"],
  "techSpec": ["Engine", "Platform", "Asset Pipeline", "Network / Save"],
  "designPillars": [
    "Experiential Pillar 1 (how it feels, never a feature/genre)",
    "Experiential Pillar 2",
    "Experiential Pillar 3"
  ],
  "tradeOffs": [
    "X over Y rule 1",
    "X over Y rule 2",
    "X over Y rule 3"
  ],
  "goal": "Updated 1-sentence goal starting with 'Build...'",
  "coreLoopBeats": [
    "Plain Beat Name 1: ...",
    "Plain Beat Name 2: ...",
    "Plain Beat Name 3: ..."
  ],
  "exclusions": [
    "Exclusion 1",
    "Exclusion 2",
    "Exclusion 3"
  ],
  "doneWhen": "Updated Done When condition",
  "releaseTrainTitles": [
    "v0.1: ... - Prototype",
    "v0.2: ... - MVP",
    "v0.3: ... - Vertical Slice"
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
          .where((s) => s.isNotEmpty)
          .toList();
      if (game != null && game.isNotEmpty) {
        draft.gameSpec = game;
        updated.add('Game Spec');
      }
      final tech = (json['techSpec'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (tech != null && tech.isNotEmpty) {
        draft.techSpec = tech;
        updated.add('Tech Spec');
      }
      final pillars = (json['designPillars'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (pillars != null && pillars.isNotEmpty) {
        draft.designPillars = pillars;
        updated.add('Design Pillars');
      }
      final tradeOffs = (json['tradeOffs'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
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
          .where((s) => s.isNotEmpty)
          .toList();
      if (beats != null && beats.isNotEmpty) {
        draft.coreLoopBeats = beats;
        updated.add('Core Loop');
      }
      final excl = (json['exclusions'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
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
          .where((s) => s.isNotEmpty)
          .toList();
      if (releases != null && releases.isNotEmpty) {
        draft.releaseTrainTitles = releases;
        updated.add('Release Train');
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
              .where((s) => s.isNotEmpty)
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
            'Tighten scope to 2 core beats',
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

  /// Step 1C: Synthesizes the `ProjectConceptBlueprint` once the user answers the 2-3 interview questions.
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

Synthesize these exact choices into a cohesive Project Concept JSON object using plain, literal game-dev terminology:
{
  "title": "Simple, clear 2-3 word working title fitting the spark and answers",
  "gameSpec": ["Camera View", "Controls", "Player Mode", "Arena Structure"],
  "techSpec": ["Engine", "Platform", "Asset Pipeline", "Network / Save"],
  "designPillars": [
    "Experiential Pillar 1 (how it feels, never a feature/genre)",
    "Experiential Pillar 2",
    "Experiential Pillar 3"
  ],
  "tradeOffs": [
    "Prioritize X over Y rule 1",
    "Prioritize X over Y rule 2",
    "Prioritize X over Y rule 3"
  ],
  "goal": "Exactly 1 plain-English sentence starting with 'Build...' stating what is being built and why, incorporating the developer's interview answers.",
  "coreLoopBeats": [
    "[Plain Beat Name 1] — Literal observable player action & mechanic",
    "[Plain Beat Name 2] — Literal observable interaction/system step",
    "[Plain Beat Name 3] — Literal observable payoff & loop reset"
  ],
  "exclusions": [
    "3 concrete scope-creep mechanics strictly cut from v0.1"
  ],
  "doneWhen": "1 clear, testable condition for when a playtester can complete the v0.1 prototype loop.",
  "releaseTrainTitles": [
    "v0.1: [Plain Functional Prototype Name] - Prototype",
    "v0.2: [Plain Functional Expansion Name] - MVP",
    "v0.3: [Plain Functional Vertical Slice Name] - Vertical Slice"
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
          .where((s) => s.isNotEmpty)
          .toList();
      if (game != null && game.isNotEmpty) draft.gameSpec = game;
      final tech = (json['techSpec'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (tech != null && tech.isNotEmpty) draft.techSpec = tech;
      final pillars = (json['designPillars'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (pillars != null && pillars.isNotEmpty) draft.designPillars = pillars;
      final tradeOffs = (json['tradeOffs'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (tradeOffs != null && tradeOffs.isNotEmpty) draft.tradeOffs = tradeOffs;
      final newGoal = json['goal']?.toString().trim() ?? '';
      if (newGoal.isNotEmpty) draft.goal = newGoal;
      final beats = (json['coreLoopBeats'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (beats != null && beats.isNotEmpty) draft.coreLoopBeats = beats;
      final excl = (json['exclusions'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (excl != null && excl.isNotEmpty) draft.exclusions = excl;
      final done = json['doneWhen']?.toString().trim() ?? '';
      if (done.isNotEmpty) draft.doneWhen = done;
      final releases = (json['releaseTrainTitles'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
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
      draft.coreLoopBeats = ['Primary Loop: $loopFocus ($perspective)'];
    }

    draft.doneWhen =
        'Playtester completes a full "$loopFocus" cycle in one greybox test arena at 60 FPS with zero state soft-locks.';
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
        question: 'What does the player do every 30 seconds in the core gameplay loop?',
        options: [
          '(Recommended) Chain movement mechanics to clear hazards and strike targets',
          'Time-trial traversal through obstacle arenas for speed ranks',
          'Tactical resource management and counter-attacks under pressure',
        ],
      ),
      AgentQuestion(
        id: 'q_milestone',
        question: 'What is our target scope for Release v0.1?',
        options: [
          '(Recommended) Prototype — 1 Greybox Arena proving the 30-second toy is fun',
          'Vertical Slice — Polished single level with production art & audio hooks',
          'MVP — Complete playable run from start screen to win/loss state',
        ],
      ),
    ];
  }

  static List<String> _defaultCoreLoopForSpark(String spark) {
    return [
      'Entry & Movement: Trigger primary traversal / control mechanic with instant camera & SFX feedback',
      'Core Challenge: Engage active arena targets or hazards using momentum/timing windows',
      'Resolution & Reset: Clear room objective, collect immediate combat/speed payoff, and reset loop',
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
      'v0.2: Target Engagement & Hazard Loop - MVP',
      'v0.3: Polished Arena & Progression - Vertical Slice',
    ];
  }
}
