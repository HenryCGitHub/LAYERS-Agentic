import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';

/// Stage 1 Agent: Turns a 1-sentence "Spark" idea into an Antigravity-style
/// 3-question multiple-choice Concept Interview, and synthesizes the answers
/// into a structured `ProjectConceptBlueprint` + Release Train roadmap.
class ProjectConceptAgent {
  static const String _envApiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// Step 1B: Generates 3 tailored multiple-choice clarifying questions from a 1-line spark.
  static Future<ProjectConceptBlueprint> startConceptInterview(
    String rawSpark, {
    String? apiKey,
  }) async {
    final cleanSpark = rawSpark.trim().isEmpty
        ? 'High-speed grappling hook parkour roguelite'
        : rawSpark.trim();
    final shortTitle = _derivePunchyTitle(cleanSpark);

    final effectiveKey = (apiKey != null && apiKey.trim().isNotEmpty)
        ? apiKey.trim()
        : _envApiKey;

    if (effectiveKey.isNotEmpty) {
      try {
        final model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: effectiveKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            temperature: 0.4,
          ),
        );

        final prompt = '''
You are an expert indie game producer helping a developer lock in their initial game concept.
The user pitched this 1-line spark: "$cleanSpark"

Return a JSON object with:
- "title": Punchy 2-4 word game working title
- "questions": Exactly 3 multiple-choice questions (1: Camera & Control Feel, 2: Core 30-Second Gameplay Loop, 3: First Milestone Target). Prefix the first option of each with "(Recommended) ".
- "goal": 1 plain-English sentence stating what is being built and why it feels great (no corporate buzzwords).
- "coreLoopBeats": 3-4 concise observable gameplay loop bullets.
- "exclusions": 3 concrete scope bloat items strictly cut from v0.1.
- "doneWhen": Clear practical condition for when the v0.1 prototype proves the fun.
- "releaseTrainTitles": 3 sequential release titles (e.g. "v0.1: Core Loop Prototype", "v0.2: Combat & Hazard Loop", "v0.3: Vertical Slice").
''';

        final response = await model.generateContent([Content.text(prompt)]);
        final text = response.text;
        if (text != null && text.isNotEmpty) {
          final parsed = jsonDecode(text) as Map<String, dynamic>;
          final qList = (parsed['questions'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map(AgentQuestion.fromJson)
                  .toList() ??
              _defaultQuestionsForSpark(cleanSpark);

          return ProjectConceptBlueprint(
            title: parsed['title']?.toString() ?? shortTitle,
            sparkIdea: cleanSpark,
            questions: qList.isNotEmpty ? qList : _defaultQuestionsForSpark(cleanSpark),
            goal: parsed['goal']?.toString() ??
                'Build a playable $shortTitle prototype with responsive controls and immediate on-screen feedback.',
            coreLoopBeats: (parsed['coreLoopBeats'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                _defaultCoreLoopForSpark(cleanSpark),
            exclusions: (parsed['exclusions'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                _defaultExclusions(),
            doneWhen: parsed['doneWhen']?.toString() ??
                'A playtester can complete 3 consecutive 30-second gameplay loops without UI prompts or Physics bugs.',
            releaseTrainTitles: (parsed['releaseTrainTitles'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                _defaultReleaseTrain(shortTitle),
            isInterviewComplete: false,
          );
        }
      } catch (_) {
        // Fallback to instant deterministic synthesis below.
      }
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

  /// Step 1C: Refines the `ProjectConceptBlueprint` once the user answers the 2-3 interview questions.
  static ProjectConceptBlueprint synthesizeFromInterview(
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

    // Ensure the user's chosen loop focus is reflected in the first Core Loop Beat
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
    final words = spark
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !{'the', 'and', 'with', 'for', 'game', 'about', 'fast'}.contains(w.toLowerCase()))
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
