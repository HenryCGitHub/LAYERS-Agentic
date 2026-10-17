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
    String modelName = 'gemini-2.5-flash',
  }) async {
    final cleanSpark = rawSpark.trim().isEmpty
        ? 'High-speed grappling hook parkour roguelite'
        : rawSpark.trim();
    final shortTitle = _derivePunchyTitle(cleanSpark);

    final prompt = '''
You are an expert indie game design producer interviewing a developer about their new game idea.
The developer pitched this 1-line spark: "$cleanSpark"

Generate a JSON object tailored SPECIFICALLY to "$cleanSpark" (do not use generic filler; reference the exact genres/mechanics mentioned in "$cleanSpark"):
{
  "title": "A punchy, memorable 2-3 word game working title fitting '$cleanSpark'",
  "questions": [
    {
      "id": "q_perspective",
      "question": "Tailored question asking about camera perspective, movement speed, and control feel for '$cleanSpark'",
      "options": [
        "(Recommended) Specific perspective + control scheme #1 tailored to $cleanSpark",
        "Specific perspective + control scheme #2 tailored to $cleanSpark",
        "Specific perspective + control scheme #3 tailored to $cleanSpark"
      ]
    },
    {
      "id": "q_loop",
      "question": "Tailored question asking how the core mechanics of '$cleanSpark' connect in a 30-second playable loop",
      "options": [
        "(Recommended) Concrete 30-second gameplay loop option #1 combining the mechanics of $cleanSpark",
        "Concrete 30-second gameplay loop option #2 combining the mechanics of $cleanSpark",
        "Concrete 30-second gameplay loop option #3 combining the mechanics of $cleanSpark"
      ]
    },
    {
      "id": "q_milestone",
      "question": "What should we prove first in the Release v0.1 Greybox Prototype?",
      "options": [
        "(Recommended) Specific v0.1 prototype sandbox goal #1 for $cleanSpark",
        "Specific v0.1 prototype sandbox goal #2 for $cleanSpark",
        "Specific v0.1 prototype sandbox goal #3 for $cleanSpark"
      ]
    }
  ],
  "goal": "1 plain-English sentence stating what is being built and why it feels great (no corporate buzzwords).",
  "coreLoopBeats": [
    "Beat 1: Concrete observable action",
    "Beat 2: Concrete observable interaction/payoff",
    "Beat 3: Concrete observable loop resolution/reset"
  ],
  "exclusions": [
    "Specific scope-creep feature #1 to exclude from v0.1",
    "Specific scope-creep feature #2 to exclude from v0.1",
    "Specific scope-creep feature #3 to exclude from v0.1"
  ],
  "doneWhen": "Clear practical condition for when the v0.1 prototype proves the core loop is fun.",
  "releaseTrainTitles": [
    "v0.1: [Specific Prototype Milestone Title] - Prototype",
    "v0.2: [Specific Core Loop Expansion Title] - MVP",
    "v0.3: [Specific Polished Content Milestone Title] - Vertical Slice"
  ]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
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
      return ProjectConceptBlueprint(
        title: aiTitle.isNotEmpty ? aiTitle : shortTitle,
        sparkIdea: cleanSpark,
        questions: qList.isNotEmpty ? qList : _defaultQuestionsForSpark(cleanSpark),
        goal: json['goal']?.toString() ??
            'Build a playable $shortTitle prototype centered on $cleanSpark with immediate game feel.',
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
            _defaultReleaseTrain(shortTitle),
        isInterviewComplete: false,
      );
    }

    return ProjectConceptBlueprint(
      title: shortTitle,
      sparkIdea: cleanSpark,
      questions: _defaultQuestionsForSpark(cleanSpark),
      goal: 'Build a playable $shortTitle prototype centered on $cleanSpark with immediate game feel.',
      coreLoopBeats: _defaultCoreLoopForSpark(cleanSpark),
      exclusions: _defaultExclusions(),
      doneWhen: 'A playtester can complete a full 30-second core loop cycle with responsive controls and clear hit/motion feedback.',
      firstReleasePreset: ReleaseScope.featurePrototype,
      releaseTrainTitles: _defaultReleaseTrain(shortTitle),
      isInterviewComplete: false,
    );
  }

  /// Step 1C: Synthesizes the `ProjectConceptBlueprint` once the user answers the 2-3 interview questions.
  /// Calls Gemini when an API key is available, with instant deterministic fallback for unit tests/offline.
  static Future<ProjectConceptBlueprint> synthesizeFromInterview(
    ProjectConceptBlueprint draft, {
    String apiKey = '',
    String modelName = 'gemini-2.5-flash',
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

Synthesize these exact choices into a cohesive Project Concept JSON object (no corporate buzzwords; use concrete, observable gameplay terms):
{
  "title": "Refined 2-3 word game title fitting the spark and answers",
  "goal": "Exactly 1 plain-English sentence stating what is being built and why it feels great, incorporating the developer's interview answers.",
  "coreLoopBeats": [
    "Beat 1: [Name] — Concrete observable player action & game feel",
    "Beat 2: [Name] — Concrete observable interaction/system hook",
    "Beat 3: [Name] — Concrete observable payoff & loop reset"
  ],
  "exclusions": [
    "3 concrete scope-creep mechanics strictly cut from v0.1"
  ],
  "doneWhen": "1 clear, testable condition for when the v0.1 prototype proves the core loop works in-game.",
  "releaseTrainTitles": [
    "v0.1: [Tailored Prototype Title] - Prototype",
    "v0.2: [Tailored Expansion Title] - MVP",
    "v0.3: [Tailored Vertical Slice Title] - Vertical Slice"
  ]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      temperature: 0.45,
    );

    if (json != null) {
      final newTitle = json['title']?.toString().trim() ?? '';
      if (newTitle.isNotEmpty) draft.title = newTitle;
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
