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
    final cleanSpark = ProjectConceptBlueprint.normalizeCommonTypos(
      rawSpark.trim().isEmpty
          ? 'High-speed grappling hook parkour roguelite'
          : rawSpark.trim(),
    );
    final shortTitle = _derivePunchyTitle(cleanSpark);

    // Compact prompt (~480 input tokens vs ~1,450+ tokens; zero 31x $cleanSpark repetition; no legacy questions array)
    final prompt = '''
You are an indie game producer creating a Stage 1 Concept Blueprint for this spark idea:
"$cleanSpark"

${GeminiAgentClient.compactStyleRules}
- Decompose `coreLoopBeats` into sequential playable Beats (`Beat Name: Observable player action and system response`) covering the full loop from entry/prep to reset.
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

    if (json != null) {
      final aiTitle = json['title']?.toString().trim() ?? '';
      final resolvedTitle = aiTitle.isNotEmpty ? aiTitle : shortTitle;
      final resolvedQuestions = _defaultQuestionsForSpark(cleanSpark);
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
            _synthesizeInitialGoalForSpark(cleanSpark, resolvedTitle),
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
            buildDefaultDesignPillarsForSpark(cleanSpark, resolvedTitle),
        tradeOffs: (json['tradeOffs'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty && s != '...')
                .toList() ??
            buildDefaultTradeOffsForSpark(cleanSpark, resolvedTitle),
        coreLoopBeats: (json['coreLoopBeats'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty && s != '...')
                .toList() ??
            _defaultCoreLoopForSpark(cleanSpark),
        exclusions: (json['exclusions'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty && s != '...')
                .toList() ??
            buildDefaultExclusionsForSpark(cleanSpark, resolvedTitle),
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
        lastAgentReply: 'Drafted the initial $resolvedTitle Concept Blueprint.',
      );
    }

    final fallbackQuestions = _defaultQuestionsForSpark(cleanSpark);
    return ProjectConceptBlueprint(
      title: shortTitle,
      sparkIdea: cleanSpark,
      questions: fallbackQuestions,
      goal: _synthesizeInitialGoalForSpark(cleanSpark, shortTitle),
      gameSpec: _defaultGameSpec(),
      techSpec: _defaultTechSpec(),
      designPillars: buildDefaultDesignPillarsForSpark(cleanSpark, shortTitle),
      tradeOffs: buildDefaultTradeOffsForSpark(cleanSpark, shortTitle),
      coreLoopBeats: _defaultCoreLoopForSpark(cleanSpark),
      exclusions: buildDefaultExclusionsForSpark(cleanSpark, shortTitle),
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
      lastAgentReply: 'Drafted the initial $shortTitle Concept Blueprint.',
    );
  }

  /// Stateless Blueprint Turn: Takes the user's instruction, updates the live
  /// `ProjectConceptBlueprint` in place using `conversationModel` (`gemini-flash-latest`),
  /// and sets `lastAgentReply`. Zero conversation history tokens are sent or stored.
  static Future<ProjectConceptBlueprint> sendConceptChatTurn(
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
    if (cleanMsg.isEmpty) return draft;

    // Stateless Delta-Only JSON Prompt (0 history tokens; only modified fields returned)
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

    if (json != null) {
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
        draft.coreLoopBeats = beats;
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
      final effectiveUpdated = (explicitUpdated != null && explicitUpdated.isNotEmpty)
          ? explicitUpdated
          : (updated.isNotEmpty ? updated : const ['Concept Refined']);

      final replyText = json['reply']?.toString().trim() ??
          'Updated the Project Concept Blueprint with your direction!';

      draft.lastUpdatedFields = effectiveUpdated;
      draft.isInterviewComplete = true;
      draft.lastAgentReply = replyText;
      return draft;
    }

    // Offline / deterministic turn synthesis fallback
    _applyDeterministicChatTurn(draft, cleanMsg);
    return draft;
  }

  static void _applyDeterministicChatTurn(
    ProjectConceptBlueprint draft,
    String userMsg,
  ) {
    // Strip any section prefix `[Section 01 Goal]` or meta-instruction wrapper if present,
    // without appending a premature period before pattern matching
    var cleanTurn = ProjectConceptBlueprint.normalizeCommonTypos(userMsg)
        .replaceFirst(
          RegExp(r'^\[Section\s+\d+\s+[^\]]+\]\s*', caseSensitive: false),
          '',
        )
        .trim();
    if (cleanTurn.toLowerCase().contains('to apply this choice:')) {
      cleanTurn = ProjectConceptBlueprint.sanitizeGoalText(cleanTurn);
    }
    if (cleanTurn.endsWith('.')) {
      cleanTurn = cleanTurn.substring(0, cleanTurn.length - 1).trim();
    }

    final lower = cleanTurn.toLowerCase();
    final updated = <String>[];

    if (lower.contains('exclude') ||
        lower.contains('cut') ||
        lower.contains('remove') ||
        lower.contains('out of scope')) {
      draft.exclusions.add(cleanTurn);
      updated.add('Exclusions');
    } else if (lower.contains('pillar')) {
      draft.designPillars.add(
        ProjectConceptBlueprint.ensureNamedPillar(
          cleanTurn,
          draft.designPillars.length,
        ),
      );
      updated.add('Design Pillars');
    } else if (lower.contains('over ')) {
      draft.tradeOffs.add(cleanTurn);
      updated.add('Trade-Offs');
    } else if (lower.contains('godot') ||
        lower.contains('unity') ||
        lower.contains('unreal') ||
        lower.contains('engine')) {
      if (draft.techSpec.isEmpty) {
        draft.techSpec = _defaultTechSpec();
      }
      draft.techSpec[0] = cleanTurn;
      updated.add('Tech Spec');
    } else if (lower.startsWith('title') || lower.startsWith('rename')) {
      final cleanedTitle = cleanTurn
          .replaceFirst(
            RegExp(r'^(rename|change title|title)\s*(to|:)?\s*', caseSensitive: false),
            '',
          )
          .trim();
      if (cleanedTitle.isNotEmpty) {
        draft.title = cleanedTitle;
        updated.add('Title');
      }
    } else {
      _synthesizeConceptTurnUpdate(draft, cleanTurn, updated);
    }

    draft.lastUpdatedFields = updated;
    draft.isInterviewComplete = true;
    draft.lastAgentReply =
        'Synthesized your direction into ${updated.join(" & ")} on the live Blueprint.';
  }

  /// Synthesizes conversational user feedback (replacements like "instead of a crab we use vehicles",
  /// additions like "add drift boosting", or perspective shifts) into natural Goal, Title, Core Loop Beats,
  /// and Section Option updates — NEVER copy-pasting raw user instructions verbatim.
  static void _synthesizeConceptTurnUpdate(
    ProjectConceptBlueprint draft,
    String cleanTurn,
    List<String> updated,
  ) {
    final lower = cleanTurn.toLowerCase();

    // 1. Detect replacement / pivot patterns:
    //    - "instead of (a/an/the) X we use Y" / "instead of X, use Y"
    //    - "replace X with Y" / "change X to Y" / "swap X for Y"
    //    - "X but in a Y" / "X but with Y"
    String? oldSubject;
    String? newSubject;

    final insteadMatch = RegExp(
      r'instead of (?:a |an |the )?([a-z0-9\s-]+?)(?:,|\s+we|\s+let\x27s|\s+i\s+want\s+to|\s+you)?\s+(?:use|using|have|play\s+as|control|drive|pilot|with)\s+(?:a |an |the )?([a-z0-9\s-]+)$',
      caseSensitive: false,
    ).firstMatch(cleanTurn);
    final replaceMatch = RegExp(
      r'(?:replace|change|swap)\s+(?:the\s+|a\s+|an\s+)?([a-z0-9\s-]+?)\s+(?:with|to|for)\s+(?:a\s+|an\s+|the\s+)?([a-z0-9\s-]+)$',
      caseSensitive: false,
    ).firstMatch(cleanTurn);
    final butInMatch = RegExp(
      r'^([a-z0-9\s-]+?)\s+but\s+(?:in|with|using|as)\s+(?:a\s+|an\s+|the\s+)?([a-z0-9\s-]+)$',
      caseSensitive: false,
    ).firstMatch(cleanTurn);

    if (insteadMatch != null) {
      oldSubject = insteadMatch.group(1)!.trim();
      newSubject = insteadMatch.group(2)!.trim();
    } else if (replaceMatch != null) {
      oldSubject = replaceMatch.group(1)!.trim();
      newSubject = replaceMatch.group(2)!.trim();
    } else if (butInMatch != null) {
      oldSubject = butInMatch.group(1)!.trim().split(RegExp(r'\s+')).first;
      newSubject = butInMatch.group(2)!.trim();
    }

    if (oldSubject != null &&
        newSubject != null &&
        oldSubject.isNotEmpty &&
        newSubject.isNotEmpty) {
      final singularNew = newSubject.toLowerCase().endsWith('s') && newSubject.length > 3
          ? newSubject.substring(0, newSubject.length - 1)
          : newSubject;
      final capSingularNew =
          singularNew[0].toUpperCase() + singularNew.substring(1);

      // Update Title if it contains oldSubject
      if (RegExp(RegExp.escape(oldSubject), caseSensitive: false)
          .hasMatch(draft.title)) {
        draft.title = draft.title.replaceAll(
          RegExp(RegExp.escape(oldSubject), caseSensitive: false),
          capSingularNew,
        );
        updated.add('Title');
      }

      // Update Spark & Rewrite Goal cleanly
      draft.goal =
          'Single-Arena Loop: Build a playable ${draft.title} prototype where you control $newSubject, maneuver through arena hazards at speed, and clear escalating enemy waves.';

      // Update Core Loop Beats to reflect the new subject (never "Core Focus: instead of...")
      final isVehicular = newSubject.toLowerCase().contains('vehic') ||
          newSubject.toLowerCase().contains('car') ||
          newSubject.toLowerCase().contains('truck') ||
          newSubject.toLowerCase().contains('mech');
      if (draft.coreLoopBeats.isNotEmpty) {
        draft.coreLoopBeats[0] = isVehicular
            ? '$capSingularNew Loadout & Arena Entry: Select active $singularNew chassis and weapon mount in the starting zone'
            : '$capSingularNew Loadout & Entry: Spawn in the starting zone and test primary $singularNew controls';
        if (draft.coreLoopBeats.length > 1 && isVehicular) {
          draft.coreLoopBeats[1] =
              'High-Speed Arena Driving & Traversal: Drive, drift, and boost across arena terrain while maintaining momentum';
        }
      }

      // Refresh Section 01 Goal Option Cards so they also reflect the updated subject
      draft.sectionOptions['goal'] = _defaultSectionOptionsForSpark(
        '${draft.title} with $newSubject',
        draft.title,
      )['goal']!;

      updated.addAll(['Goal', 'Core Loop']);
      return;
    }

    // 2. Check if cleanTurn is already a complete Option Card or "Build..." sentence
    final colonIdx = cleanTurn.indexOf(':');
    final cleanBody = (colonIdx > 0 && colonIdx < 48 && colonIdx < cleanTurn.length - 1)
        ? cleanTurn.substring(colonIdx + 1).trim()
        : cleanTurn;
    if (cleanBody.toLowerCase().startsWith('build ') ||
        cleanBody.toLowerCase().startsWith('test ') ||
        cleanBody.toLowerCase().startsWith('prove ') ||
        cleanBody.toLowerCase().startsWith('expand ')) {
      draft.goal = ProjectConceptBlueprint.sanitizeGoalText(
        cleanTurn.endsWith('.') ? cleanTurn : '$cleanTurn.',
      );
      updated.add('Goal');
      return;
    }

    // 3. Otherwise synthesize additive / modification feedback into a natural Goal & Beat
    final synthesizedMechanic = cleanBody
        .replaceFirst(
          RegExp(
            r'^(?:please\s+|can\s+we\s+|we\s+should\s+|let\x27s\s+)?(?:add|include|focus\s+on|make\s+it|use|feature|with)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    final effectiveFocus =
        synthesizedMechanic.isNotEmpty ? synthesizedMechanic : cleanBody;

    draft.goal = ProjectConceptBlueprint.sanitizeGoalText(
      'Single-Arena Loop: Build a playable ${draft.title} prototype where you execute $effectiveFocus, chain core movement and combat actions, and clear the arena loop.',
    );

    if (lower.contains('2d') || lower.contains('3d') || lower.contains('top-down')) {
      if (draft.gameSpec.isNotEmpty) {
        draft.gameSpec[0] = cleanTurn;
        updated.add('Game Spec');
      }
      if (draft.techSpec.isNotEmpty) {
        draft.techSpec[0] = cleanTurn;
        updated.add('Tech Spec');
      }
    }

    final shortBeatLabel = effectiveFocus
        .split(RegExp(r'\s+'))
        .take(3)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '')
        .join(' ');
    final beatLine =
        '${shortBeatLabel.isNotEmpty ? shortBeatLabel : "Core Mechanic"} Execution: Execute $effectiveFocus with responsive controls and immediate feedback';
    if (draft.coreLoopBeats.isNotEmpty) {
      draft.coreLoopBeats[0] = beatLine;
    } else {
      draft.coreLoopBeats.add(beatLine);
    }
    draft.sectionOptions['goal'] = _defaultSectionOptionsForSpark(
      '${draft.title} ($effectiveFocus)',
      draft.title,
    )['goal']!;
    updated.addAll(['Goal', 'Core Loop']);
  }

  static String _synthesizeInitialGoalForSpark(String spark, String title) {
    final phrase = _shortSparkPhrase(spark, title);
    return 'Single-Arena Loop: Build a playable $title prototype where you master $phrase, chain core movement and combat actions, and complete a full arena loop.';
  }

  /// Extracts a concise synthesized premise phrase from `spark` (never echoing raw user sentences verbatim).
  static String _shortSparkPhrase(String spark, String fallbackTitle) {
    var base = ProjectConceptBlueprint.normalizeCommonTypos(spark.trim());
    final dashIdx = base.indexOf(' — ');
    if (dashIdx > 0) {
      base = base.substring(0, dashIdx).trim();
    }
    final parenIdx = base.indexOf(' (');
    if (parenIdx > 0) {
      base = base.substring(0, parenIdx).trim();
    }
    // Rewrite "X game but in a Y" / "instead of X we use Y" into a clean mechanic phrase
    final butInMatch = RegExp(
      r'^(.+?)\s+but\s+(?:in|with|using|as)\s+(?:a\s+|an\s+|the\s+)?([a-z0-9\s-]+)$',
      caseSensitive: false,
    ).firstMatch(base);
    if (butInMatch != null) {
      final twist = butInMatch.group(2)!.trim().toLowerCase();
      return 'high-speed $twist arena combat and movement';
    }
    final mechs = _deterministicMechanicsForIdea(base);
    if (mechs.isNotEmpty && mechs.first != 'Responsive Core Controls') {
      return '${mechs.first.toLowerCase()} and ${mechs.length > 1 ? mechs[1].toLowerCase() : 'tactical positioning'}';
    }
    return '${fallbackTitle.toLowerCase()} mechanics';
  }

  static String _derivePunchyTitle(
    String spark, {
    int variantOffset = 0,
  }) {
    var normalized = ProjectConceptBlueprint.normalizeCommonTypos(spark.trim());
    final dashIdx = normalized.indexOf(' — ');
    if (dashIdx > 0) {
      normalized = normalized.substring(0, dashIdx).trim();
    }

    // If spark has "but in a <twist>" or "instead of <old> we use <twist>", lead with the twist!
    final twistMatch = RegExp(
      r'\b(?:but\s+(?:in|with|as)\s+(?:a\s+|an\s+|the\s+)?|instead\s+of\s+[a-z]+\s+(?:we\s+)?use\s+)([a-zA-Z0-9-]+)',
      caseSensitive: false,
    ).firstMatch(normalized);

    const stopWords = {
      'the', 'and', 'with', 'for', 'game', 'about', 'fast', 'that', 'also',
      'combines', 'like', 'where', 'you', 'can', 'into', 'from', 'but',
      'instead', 'use', 'using', 'brave', 'areas', 'area', 'too', 'lethal',
      'ordinary', 'survivors', 'survivor', 'retrieve', 'deliver', 'vital',
      'across', 'ruined', 'fluid', 'high-speed', 'high', 'speed', 'against',
      'hunting', 'your', 'play', 'playing', 'player', 'players', 'explore',
      'exploring', 'survive', 'surviving', 'navigate', 'navigating', 'build',
      'building', 'fight', 'fighting', 'through', 'over', 'under', 'between',
      'around', 'while', 'when', 'every', 'each', 'other', 'their', 'have',
      'has', 'make', 'making', 'take', 'taking', 'keep', 'keeping', 'find',
      'finding', 'must', 'will', 'need', 'needs', 'very', 'more', 'most',
      'some', 'many', 'full', 'deep', 'cozy', 'dark', 'tiny', 'huge', 'giant',
      'small', 'world', 'zones', 'zone', 'add', 'include', 'focus',
    };

    const settingKeywords = {
      'metropolis': 'Metropolis',
      'city': 'City',
      'ruins': 'Ruin',
      'ruin': 'Ruin',
      'arena': 'Arena',
      'dungeon': 'Dungeon',
      'trench': 'Trench',
      'ocean': 'Ocean',
      'sea': 'Deep-Sea',
      'space': 'Space',
      'station': 'Station',
      'outpost': 'Outpost',
      'vault': 'Vault',
      'tower': 'Tower',
      'cyber': 'Cyber',
      'neon': 'Neon',
      'sector': 'Sector',
    };

    const mechanicAndRoleKeywords = {
      'cargo': 'Cargo',
      'courier': 'Courier',
      'parkour': 'Parkour',
      'wall-running': 'Wall-Run',
      'wall-run': 'Wall-Run',
      'wallrun': 'Wall-Run',
      'haul': 'Haul',
      'scavengers': 'Scavenger',
      'scavenger': 'Scavenger',
      'grapple': 'Grapple',
      'grappling': 'Grapple',
      'hook': 'Hook',
      'submarine': 'Submarine',
      'salvage': 'Salvage',
      'photography': 'Photo',
      'katana': 'Katana',
      'blade': 'Blade',
      'parry': 'Parry',
      'deflection': 'Deflect',
      'deflect': 'Deflect',
      'boss': 'Boss',
      'rush': 'Rush',
      'vehicle': 'Vehicle',
      'vehicles': 'Vehicle',
      'motorcycle': 'Moto',
      'motorcycles': 'Moto',
      'drone': 'Drone',
      'drones': 'Drone',
      'mech': 'Mech',
      'mecha': 'Mecha',
      'drift': 'Drift',
      'farm': 'Farm',
      'farming': 'Farm',
      'alchemy': 'Alchemy',
      'shop': 'Shop',
      'deck': 'Deck',
      'stealth': 'Stealth',
      'heist': 'Heist',
      'roguelite': 'Roguelite',
      'runner': 'Runner',
    };

    final rawTokens = normalized
        .replaceAll(RegExp(r'[^\w\s-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();

    final picked = <String>[];
    void addUnique(String label) {
      if (label.isEmpty) return;
      if (!picked.any((p) => p.toLowerCase() == label.toLowerCase())) {
        picked.add(label);
      }
    }

    if (twistMatch != null) {
      final twistWord = twistMatch.group(1)!.trim();
      if (twistWord.length >= 3) {
        final cleanTwist = twistWord.toLowerCase().endsWith('s') && twistWord.length > 3
            ? twistWord.substring(0, twistWord.length - 1)
            : twistWord;
        addUnique(cleanTwist[0].toUpperCase() + cleanTwist.substring(1).toLowerCase());
      }
    }

    for (final token in rawTokens) {
      final lower = token.toLowerCase();
      if (settingKeywords.containsKey(lower)) {
        addUnique(settingKeywords[lower]!);
        break;
      }
    }

    final foundMechanics = <String>[];
    for (final token in rawTokens) {
      final lower = token.toLowerCase();
      if (mechanicAndRoleKeywords.containsKey(lower)) {
        final mapped = mechanicAndRoleKeywords[lower]!;
        if (!foundMechanics.any((m) => m.toLowerCase() == mapped.toLowerCase())) {
          foundMechanics.add(mapped);
        }
      }
    }

    if (foundMechanics.isNotEmpty) {
      final start = foundMechanics.length > 2
          ? (variantOffset % foundMechanics.length)
          : 0;
      for (int i = 0; i < foundMechanics.length; i++) {
        addUnique(foundMechanics[(start + i) % foundMechanics.length]);
        if (picked.length >= 3) break;
      }
    }

    if (picked.length < 2) {
      for (final token in rawTokens) {
        final lower = token.toLowerCase();
        if (!stopWords.contains(lower)) {
          addUnique(token[0].toUpperCase() + token.substring(1).toLowerCase());
          if (picked.length >= 3) break;
        }
      }
    }

    if (picked.isEmpty) return 'Core Prototype';
    return picked.take(3).join(' ');
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

  static List<String> buildDefaultDesignPillarsForSpark(
    String spark,
    String title,
  ) {
    final lower = '$spark $title'.toLowerCase();
    final hasCourierOrCargo = lower.contains('cargo') ||
        lower.contains('courier') ||
        lower.contains('haul') ||
        lower.contains('settlement') ||
        lower.contains('supply') ||
        lower.contains('scaveng');
    final hasFarmOrShop = lower.contains('farm') ||
        lower.contains('crop') ||
        lower.contains('alchemy') ||
        lower.contains('shop') ||
        lower.contains('forag');
    if (hasCourierOrCargo) {
      return [
        'High-Stakes Tension: Every supply run feels like a high-stakes gamble between pushing deeper for caches and extracting alive.',
        'Tactile Scavenging: Loot weight and weapon handling feel grounded and impactful during every encounter.',
        'Deliberate Threat Reading: Hostile zones feel dangerous and readable, rewarding careful observation over reckless rushing.',
      ];
    }
    if (hasFarmOrShop) {
      return [
        'Tactile Crafting Loop: Every harvested resource immediately feeds into a visible, satisfying craft or shop upgrade.',
        'Readable Risk & Yield: Foraging deeper into hostile zones offers clear risk-reward trade-offs before nightfall.',
        'Cozy Hub Contrast: Returning to the shop feels warm, fast to organize, and immediately rewarding.',
      ];
    }
    return [
      'Flow-State Momentum: Never force the player to stop moving to act or aim in $title.',
      'Readable Chaos: Every hazard and attack in $title is clearly telegraphed before impact.',
      'Fast Fair Recovery: Failures feel fair, fast to recover from, and immediately repeatable.',
    ];
  }

  static List<String> buildDefaultTradeOffsForSpark(
    String spark,
    String title,
  ) {
    return buildTradeOffOptionsForSpark(spark, title)
        .map(
          (opt) => opt.contains(':')
              ? opt.substring(opt.indexOf(':') + 1).trim()
              : opt,
        )
        .toList();
  }

  static List<String> buildTradeOffOptionsForSpark(
    String spark,
    String title, {
    int offset = 0,
  }) {
    final lower = '$spark $title'.toLowerCase();
    final hasCourierOrCargo = lower.contains('cargo') ||
        lower.contains('courier') ||
        lower.contains('haul') ||
        lower.contains('settlement') ||
        lower.contains('supply') ||
        lower.contains('scaveng') ||
        lower.contains('cache');
    final hasGrappleOrParkour = lower.contains('grappl') ||
        lower.contains('hook') ||
        lower.contains('parkour') ||
        lower.contains('wall-run') ||
        lower.contains('wallrun');
    final hasFarmOrShop = lower.contains('farm') ||
        lower.contains('crop') ||
        lower.contains('alchemy') ||
        lower.contains('shop') ||
        lower.contains('forag');
    final hasVehicleOrMech = lower.contains('vehic') ||
        lower.contains('car') ||
        lower.contains('moto') ||
        lower.contains('mech') ||
        lower.contains('drift');

    final List<String> pool;
    if (hasCourierOrCargo) {
      pool = [
        'Tactile Haul Weight: Physical cargo weight and movement penalty over weightless bottomless inventory bags',
        'Extraction Tension: High-stakes extraction risk and cache hunting over safe mid-zone checkpoint saves',
        'Readable Gunplay & Loot: Clear enemy threat silhouettes and loot highlights over dense environmental clutter in $title',
        'Fast Contract Turnaround: 1-screen settlement terminal turn-in over multi-building town walking menus',
        'Scavenger Ambush Pacing: Reactive zone threat escalation over static pre-scripted enemy spawns',
        'Slot-Cap Decisions: Hard carry-slot limits that force on-the-spot loot choices over spreadsheet sorting',
      ];
    } else if (hasFarmOrShop) {
      pool = [
        'Instant Plot Actions: 1-button planting, harvesting, and brewing over multi-step tool durability menus',
        'Direct Ingredient Value: Clear 1-to-1 ingredient-to-potion recipes over sprawling randomized crafting trees in $title',
        'Fast Day/Night Cycle: Snappy 3-minute foraging and shop cycles over real-time waiting timers',
        'Readable Shop Queue: Immediate customer request icons over long text dialogue negotiations',
        'Compact Hub Layout: Single-screen farm and shop layout over sprawling town walking distances',
        'Guaranteed Drop Clarity: Predictable monster/plant resource drops over low-probability grind tables',
      ];
    } else if (hasVehicleOrMech) {
      pool = [
        'Arcade Drift Control: Responsive arcade drift and boost recovery over punishing simulation tire spinout',
        'Readable Lock-On & Telegraphs: High-contrast target lock and incoming missile warnings over realistic cockpit occlusion in $title',
        'Instant Bay Refit: Fast 3-slot chassis loadout swap over granular part-by-part weight math',
        'High-Speed Collision Grace: Glancing wall-scrape momentum preservation over full-stop crash penalties',
        'Clear Weapon Cooldowns: Reticle-mounted heat/ammo bars over corner HUD text readouts',
        '1-Key Arena Reset: Instant arena wave reset over garage loading screens',
      ];
    } else if (hasGrappleOrParkour) {
      pool = [
        'Momentum Preservation: Continuous grapple/wall-run momentum carry over realistic pendulum/ledge stop frames',
        'Generous Anchor Aim: Forgiving hook/ledge snap targeting at high speed over pixel-strict aim checks in $title',
        '1-Key Run Restart: Sub-second arena reset on fall or death over multi-screen game-over menus',
        'Airborne Control Authority: Responsive mid-air directional redirect over locked ballistic trajectories',
        'High-Contrast Climb Surfaces: Color-coded grapple/wall-run geometry over noisy background detail in v0.1',
        'Aggressive Forward Recovery: Dashing or grappling forward to recover stamina over passive cover waiting',
      ];
    } else {
      final mechs = _deterministicMechanicsForIdea(spark);
      final primaryMech = mechs.isNotEmpty ? mechs.first : title;
      final secondaryMech =
          mechs.length > 1 ? mechs[1] : 'Tactical Positioning';
      pool = [
        'Responsive $primaryMech: Snappy $primaryMech input response over slow realistic animation windups in $title',
        '$secondaryMech Clarity: Readable $secondaryMech telegraphs and hit confirmation over dense visual effects in v0.1',
        'Fast $title Loop Reset: 1-key $title round reset and loadout retry over multi-screen menu flows',
        'Single-Arena Depth: Deepening $primaryMech interactions in 1 test arena over building multiple empty levels',
        'Exposed Tuning Knobs: Direct inspector tuning variables for $primaryMech over hardcoded magic numbers',
        'Playable Greybox First: Proven $title core loop feel in greybox over premature art polish',
      ];
    }

    final start = (offset * 3) % pool.length;
    return [
      for (int i = 0; i < 3; i++) pool[(start + i) % pool.length],
    ];
  }

  static List<String> buildDefaultExclusionsForSpark(
    String spark,
    String title,
  ) {
    return buildExclusionOptionsForSpark(spark, title)
        .map(
          (opt) => opt.contains(':')
              ? opt.substring(opt.indexOf(':') + 1).trim()
              : opt,
        )
        .toList();
  }

  static List<String> buildExclusionOptionsForSpark(
    String spark,
    String title, {
    int offset = 0,
  }) {
    final lower = '$spark $title'.toLowerCase();
    final hasCourierOrCargo = lower.contains('cargo') ||
        lower.contains('courier') ||
        lower.contains('haul') ||
        lower.contains('settlement') ||
        lower.contains('supply') ||
        lower.contains('scaveng') ||
        lower.contains('cache');
    final hasGrappleOrParkour = lower.contains('grappl') ||
        lower.contains('hook') ||
        lower.contains('parkour') ||
        lower.contains('wall-run') ||
        lower.contains('wallrun');
    final hasFarmOrShop = lower.contains('farm') ||
        lower.contains('crop') ||
        lower.contains('alchemy') ||
        lower.contains('shop') ||
        lower.contains('forag');
    final hasVehicleOrMech = lower.contains('vehic') ||
        lower.contains('car') ||
        lower.contains('moto') ||
        lower.contains('mech') ||
        lower.contains('drift');

    final List<String> pool;
    if (hasCourierOrCargo) {
      pool = [
        'No Vehicles or Fast-Travel: No drivable vehicles, mount systems, or multi-region world map fast-travel in the $title v0.1 Prototype',
        'No Faction Politics or Morality: No multi-settlement faction reputation trees or branching NPC dialogue quests in v0.1',
        'No Base Building or Co-Op: No player settlement construction, companion AI squads, or online co-op in v0.1',
        'No Weapon Crafting Bench: No part-by-part weapon crafting, durability repair benches, or ammo reloading presses in v0.1',
        'No Dynamic Weather Simulation: No procedural storm simulation, day/night survival hunger meters, or sleep schedules in v0.1',
        'No Multi-Zone Open World: No seamless open-world streaming across multiple settlements in v0.1 (prove 1 courier route + 1 hostile zone first)',
      ];
    } else if (hasFarmOrShop) {
      pool = [
        'No Town Romance or NPC Schedules: No villager relationship meters, marriage quests, or 24-hour town walking schedules in $title v0.1',
        'No Multi-Biome Dungeons: No procedural multi-biome world map or multi-phase boss dungeons in v0.1',
        'No Livestock or Cooking Minigames: No animal breeding barns, fishing minigames, or furniture decoration editors in v0.1',
        'No Online Trading Market: No multiplayer item trading, auction houses, or seasonal festival cutscenes in v0.1',
        'No Complex Soil Chemistry: No multi-variable soil pH/fertilizer simulation in v0.1 (keep growth timers direct and readable)',
        'No Hiring Staff Automation: No AI shopkeeper employees or automated conveyor farm pipelines in v0.1',
      ];
    } else if (hasVehicleOrMech) {
      pool = [
        'No Open-World Highway Traffic: No open-world city traffic simulation or multi-kilometer highway streaming in $title v0.1',
        'No Granular Engine Tuning Garage: No 50-part transmission/suspension tuning sliders or paint decal editors in v0.1',
        'No Online Ranked Matchmaking: No online multiplayer lobbies, ghost leaderboards, or replay theater in v0.1',
        'No On-Foot Pilot Sections: No exiting the chassis for on-foot walking hubs or NPC story cutscenes in v0.1',
        'No Soft-Body Mesh Deformation: No realistic per-panel mesh deformation physics in v0.1 (use clear hull health states)',
        'No Multi-Track Career Calendar: No multi-season tournament calendar or sponsor contract negotiations in v0.1',
      ];
    } else if (hasGrappleOrParkour) {
      pool = [
        'No Open-World City Streaming: No sprawling open-world city districts or procedural biome generation in the $title v0.1 Prototype',
        'No Skill Trees or Gear Crafting: No multi-branch RPG skill trees, loot rarity tables, or inventory crafting menus in v0.1',
        'No Co-Op or Story Cutscenes: No online multiplayer race lobbies, ghost replays, or voiced NPC story cutscenes in v0.1',
        'No Stealth Vision Cones: No complex enemy stealth detection cones or disguise mechanics in v0.1',
        'No Custom Level Editor: No in-game track/arena map editor or Steam Workshop sharing in v0.1',
        'No Multi-Phase Boss Cinematics: No scripted multi-stage boss cutscenes before proving core grapple/movement flow in v0.1',
      ];
    } else {
      final mechs = _deterministicMechanicsForIdea(spark);
      final primaryMech = mechs.isNotEmpty ? mechs.first : title;
      pool = [
        'No Multi-Biome World Map: No sprawling multi-zone world map or procedural biome generation before proving $primaryMech in 1 $title arena',
        'No Deep RPG Skill Trees: No multi-branch skill trees, deep inventory crafting, or equipment rarity tables in $title v0.1',
        'No Online Co-Op or Cutscenes: No online multiplayer netcode, leaderboards, or cinematic NPC dialogue trees in $title v0.1',
        'No Meta-Progression Save Shop: No permanent cross-run currency shops or unlock trees in v0.1',
        'No Companion AI Systems: No allied AI squadmates, pet systems, or base-building sub-games in v0.1',
        'No Custom Shaders or Localization: No final production shaders, voice acting, or multi-language localization in v0.1',
      ];
    }

    final start = (offset * 3) % pool.length;
    return [
      for (int i = 0; i < 3; i++) pool[(start + i) % pool.length],
    ];
  }

  /// Upgrades any saved `ProjectConceptBlueprint` whose Pillars lack names or whose
  /// `tradeOffs` / `exclusions` still hold the legacy static placeholder lists.
  static void upgradeLegacyConceptDraftIfNeeded(ProjectConceptBlueprint draft) {
    final spark = draft.sparkIdea.trim().isNotEmpty
        ? draft.sparkIdea
        : draft.title;
    final title = draft.title;

    // 1. Ensure every Design Pillar has a concrete 2-4 word name (never "Pillar 01")
    draft.designPillars = [
      for (int i = 0; i < draft.designPillars.length; i++)
        ProjectConceptBlueprint.ensureNamedPillar(draft.designPillars[i], i),
    ];

    // 2. Upgrade legacy static Trade-Offs & Section 05 options if they match old hardcoded defaults
    final joinedTradeOffs = draft.tradeOffs.join(' | ').toLowerCase();
    final hasLegacyTradeOffs = draft.tradeOffs.isEmpty ||
        (joinedTradeOffs.contains('realistic physics inertia') &&
            (joinedTradeOffs.contains('dense particle clutter') ||
                joinedTradeOffs.contains('complex visual shaders')));
    if (hasLegacyTradeOffs) {
      draft.tradeOffs = buildDefaultTradeOffsForSpark(spark, title);
    }

    final existingTradeOffOpts =
        (draft.sectionOptions['tradeOffs'] ?? const <String>[])
            .join(' | ')
            .toLowerCase();
    if (existingTradeOffOpts.isEmpty ||
        (existingTradeOffOpts.contains('instant input response:') &&
            existingTradeOffOpts.contains('animation commitment:'))) {
      draft.sectionOptions['tradeOffs'] =
          buildTradeOffOptionsForSpark(spark, title);
    }

    // 3. Upgrade legacy static Exclusions & Section 07 options if they match old hardcoded defaults
    final joinedExclusions = draft.exclusions.join(' | ').toLowerCase();
    final hasLegacyExclusions = draft.exclusions.isEmpty ||
        (joinedExclusions.contains('multi-branch skill trees') &&
            joinedExclusions.contains('online multiplayer matchmaking'));
    if (hasLegacyExclusions) {
      draft.exclusions = buildDefaultExclusionsForSpark(spark, title);
    }

    final existingExclOpts =
        (draft.sectionOptions['exclusions'] ?? const <String>[])
            .join(' | ')
            .toLowerCase();
    if (existingExclOpts.isEmpty ||
        (existingExclOpts.contains('cut trees, co-op & story:') &&
            existingExclOpts.contains('defer bosses & crafting:'))) {
      draft.sectionOptions['exclusions'] =
          buildExclusionOptionsForSpark(spark, title);
    }
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
    final lower = spark.toLowerCase();
    final isParkourOrCourier = (lower.contains('parkour') ||
            lower.contains('wall-run') ||
            lower.contains('wallrun') ||
            lower.contains('cargo') ||
            lower.contains('courier') ||
            lower.contains('haul')) &&
        !lower.contains('grappl') &&
        !lower.contains('hook');
    if (isParkourOrCourier) {
      return [
        'Contract & Loadout Prep: Select delivery contract, cargo weight load, and runner gear in the safe zone',
        'Parkour & Wall-Run Traversal: Chain wall-runs, rooftop vaults, and slides across ruined city sectors',
        'Scavenger Ambush & High-Speed Combat: Evade or fight through scavenger packs hunting your active cargo haul',
        'Cargo Dropoff & Loadout Upgrade: Reach the safe-zone terminal with cargo intact to bank credits and upgrade gear',
      ];
    }
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
    final shortSpark = _shortSparkPhrase(spark, title);
    return {
      'goal': [
        'Single-Arena Loop: Build a playable $title prototype centered on $shortSpark in a single test arena.',
        'Prep + Arena Loop: Build a $title prototype with an interactive prep zone before entering the core gameplay loop.',
        'Controls & Feel First: Build a focused $title v0.1 prototype proving primary player controls and core mechanic feel first.',
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
      'tradeOffs': buildTradeOffOptionsForSpark(spark, title),
      'coreLoop': [
        'Complete 4-Beat Loop: Prep & Loadout → Arena Movement & Combat → Loot & Upgrade Choice → Round Clear & Reset',
        'Direct Action Loop: Arena Drop-In → High-Speed Movement & Combat → Wave Objective Clear → Score & Loot Tally → Instant Reset',
        'Skill Mastery Loop: Loadout & Positioning → Primary Weapon & Dash → Hazard Dodge & Counter → Upgrade Pick → Next Wave',
      ],
      'exclusions': buildExclusionOptionsForSpark(spark, title),
      'doneWhen': [
        'All Beats & Clean Reset: Playtester spawns in, executes every $title core loop beat from start to finish, and resets the arena cleanly',
        '3 Consecutive Runs: Playtester completes 3 back-to-back $title loop cycles with clear win/fail resolution and zero soft-locks',
        'No-Explain Playtest: A playtester picks up the controls, reads the primary $title objective from on-screen cues alone, and completes a full round',
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
        ? existingIntake.rawIdea
        : (cleanInput.isEmpty
            ? 'High-speed grappling hook parkour roguelite'
            : cleanInput);

    final isExplicitRename = isRefinement &&
        RegExp(
          r'^(?:please\s+)?(?:rename|change\s+title|set\s+title|title|call\s+it)\s*(?:to|:)?\s+(.+)$',
          caseSensitive: false,
        ).hasMatch(cleanInput);

    if (GeminiAgentClient.hasKey(apiKey) && !isExplicitRename) {
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
          final updatedRawIdea = existingIntake != null
              ? (cleanInput.isNotEmpty ? '${existingIntake.rawIdea}, $cleanInput' : existingIntake.rawIdea)
              : seedIdea;
          return SparkIdeaIntakeResult(
            rawIdea: updatedRawIdea,
            workingTitle: wTitle.isNotEmpty
                ? wTitle
                : (existingIntake?.workingTitle ?? _derivePunchyTitle(updatedRawIdea)),
            baseSummary: summary,
            mechanics: mechs.isNotEmpty
                ? mechs
                : (existingIntake?.mechanics ?? _deterministicMechanicsForIdea(updatedRawIdea)),
            expansionCards: cards,
          );
        }
      }
    }

    return buildDeterministicSparkIntake(
      rawIdea: seedIdea,
      refinementText: isRefinement ? cleanInput : null,
      existingIntake: existingIntake,
      suggestionVariantOffset: suggestionVariantOffset,
      isUpdateAction: existingIntake != null,
    );
  }

  static List<String> _deterministicMechanicsForIdea(String idea) {
    final lower = idea.toLowerCase();
    final hasGrapple = lower.contains('grappl') ||
        lower.contains('hook') ||
        lower.contains('swing') ||
        lower.contains('tether');
    final hasParkour = lower.contains('parkour') ||
        lower.contains('wall-run') ||
        lower.contains('wallrun');
    final hasCourierOrCargo = lower.contains('cargo') ||
        lower.contains('courier') ||
        lower.contains('haul') ||
        lower.contains('settlement') ||
        lower.contains('supply') ||
        lower.contains('deliver');

    if (hasParkour && !hasGrapple) {
      if (hasCourierOrCargo) {
        return const [
          'Fluid Parkour & Wall-Running',
          'Cargo Haul Protection',
          'High-Speed Scavenger Combat',
        ];
      }
      return const [
        'Fluid Parkour & Wall-Running',
        'Momentum Vault & Slide',
        'High-Speed Traversal Combat',
      ];
    }
    if (hasCourierOrCargo && !hasGrapple) {
      return const [
        'Settlement Supply Delivery',
        'Zone Looting & Hidden Caches',
        'Ranged Enemy Combat',
      ];
    }
    if (hasGrapple) {
      return const [
        'Momentum Grapple Swing',
        'Mid-Air Dash Cancel',
        'Fast Arena Reset',
      ];
    }
    return const [
      'Responsive Core Controls',
      'Escalating Round Objective',
      'Between-Round Loadout Choice',
    ];
  }

  /// Synthesizes a natural, plain-English 2-sentence game summary from `cleanIdea`
  /// without ever quoting or splicing the user's raw sentence verbatim.
  static String _synthesizeNaturalSparkSummary(
    String cleanIdea,
    String title, {
    int variantOffset = 0,
  }) {
    final normalized =
        ProjectConceptBlueprint.normalizeCommonTypos(cleanIdea.trim());
    final lower = normalized.toLowerCase();

    final hasGrapple = lower.contains('grappl') ||
        lower.contains('hook') ||
        lower.contains('tether');
    final hasParkour = lower.contains('parkour') ||
        lower.contains('wall-run') ||
        lower.contains('wallrun');
    final hasCargo = lower.contains('cargo') ||
        lower.contains('haul') ||
        lower.contains('courier') ||
        lower.contains('settlement') ||
        lower.contains('supply');

    if (hasParkour && hasCargo) {
      final setting = lower.contains('metropolis')
          ? 'a ruined metropolis'
          : (lower.contains('city') ? 'a contested city' : 'hazardous zones');
      final threat = lower.contains('scavenger')
          ? 'scavengers hunting your haul'
          : (lower.contains('drone')
              ? 'patrol drones hunting your haul'
              : 'hostile ambush squads along your route');
      final traversalPhrase = hasGrapple
          ? 'fluid parkour, wall-running, and grapple swings'
          : 'fluid parkour, wall-running, and high-speed combat';
      if (variantOffset % 2 == 1) {
        return 'Sprint and wall-run across $setting to secure vital cargo and extract it past $threat. Combine $traversalPhrase to protect your haul, cash in deliveries at safe-zone terminals, and unlock upgraded movement rigs between runs.';
      }
      return 'Traverse $setting to retrieve and transport high-value cargo through lethal sectors using $traversalPhrase. Chain rooftop routes to outrun or fight off $threat, bank completed deliveries at safe zones, and upgrade your runner gear between runs.';
    }

    if (hasCargo && !hasParkour) {
      final setting = lower.contains('settlement')
          ? 'isolated settlements and hostile zones'
          : 'contested supply routes';
      if (variantOffset % 2 == 1) {
        return 'Run high-risk supply courier contracts across $setting while fighting off enemies and looting required quest items. Push deeper into each zone to hunt down hidden caches and earn extra combat credits before extracting to upgrade your loadout.';
      }
      return 'Travel between $setting as a supply courier, fighting off hostile enemies and scavenging zones to fulfill item delivery quests. Risk staying longer in dangerous sectors to clear enemies for bonus credits and uncover hidden loot caches before extracting.';
    }

    final mechs = _deterministicMechanicsForIdea(normalized);
    final primaryMech = mechs.isNotEmpty
        ? mechs.first.toLowerCase()
        : '${title.toLowerCase()} controls';
    final secondaryMech = mechs.length > 1
        ? mechs[1].toLowerCase()
        : 'tactical positioning';
    if (variantOffset % 2 == 1) {
      return 'Master $primaryMech and $secondaryMech in fast, repeatable ${title.toLowerCase()} runs with crisp input response and clear telegraphs. Complete escalating round objectives under pressure, pick run-modifying upgrades, and reset cleanly between runs.';
    }
    return 'Execute responsive $primaryMech and $secondaryMech across escalating ${title.toLowerCase()} encounters with immediate visual and audio feedback. Clear each round objective to secure rewards, unlock loadout upgrades, and reset cleanly between runs.';
  }

  static SparkIdeaIntakeResult buildDeterministicSparkIntake({
    required String rawIdea,
    String? refinementText,
    SparkIdeaIntakeResult? existingIntake,
    int suggestionVariantOffset = 0,
    bool isUpdateAction = false,
  }) {
    var effectiveIdea = rawIdea.trim().isEmpty
        ? 'High-speed grappling hook parkour roguelite'
        : rawIdea.trim();
    String? explicitTitleOverride;
    String? replacedOldSub;
    String? replacedNewSub;
    final addedTags = <String>[];
    final addedSentences = <String>[];

    // If user toggled Expansion Cards on and clicked Update Summary, fold them into the base concept!
    if (existingIntake != null && isUpdateAction) {
      final selectedCards = existingIntake.expansionCards
          .where((c) => c.isSelected)
          .toList();
      if (selectedCards.isNotEmpty) {
        for (final c in selectedCards) {
          c.isSelected = false;
          if (!addedTags.contains(c.title)) {
            addedTags.add(c.title);
          }
          final cleanAdd = c.additionSummary.trim();
          if (cleanAdd.isNotEmpty &&
              !effectiveIdea.toLowerCase().contains(cleanAdd.toLowerCase())) {
            effectiveIdea = '$effectiveIdea with $cleanAdd';
            addedSentences.add(cleanAdd);
          }
        }
      }
    }

    bool isFullNewPitch = false;

    // Handle typed input on Update Summary (Title rename, Full new pitch, Replacement, or Additive refinement)
    if (existingIntake != null &&
        refinementText != null &&
        refinementText.trim().isNotEmpty) {
      final cleanRef = ProjectConceptBlueprint.normalizeCommonTypos(
        refinementText.trim(),
      );
      final renameMatch = RegExp(
        r'^(?:please\s+)?(?:rename|change\s+title|set\s+title|title|call\s+it)\s*(?:to|:)?\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(cleanRef);
      final insteadMatch = RegExp(
        r'instead of (?:a |an |the )?([a-z0-9\s-]+?)(?:,|\s+we|\s+let\x27s|\s+i\s+want\s+to|\s+you)?\s+(?:use|using|have|play\s+as|control|drive|pilot|fight|with)\s+(?:a |an |the )?([a-z0-9\s-]+)$',
        caseSensitive: false,
      ).firstMatch(cleanRef);
      final replaceMatch = RegExp(
        r'(?:replace|change|swap)\s+(?:the\s+|a\s+|an\s+)?([a-z0-9\s-]+?)\s+(?:with|to|for)\s+(?:a\s+|an\s+|the\s+)?([a-z0-9\s-]+)$',
        caseSensitive: false,
      ).firstMatch(cleanRef);

      final refWords = cleanRef.split(RegExp(r'\s+'));
      final isExplicitNewGamePitch = refWords.length >= 10 &&
          RegExp(
            r'^(?:(?:new\s+(?:game|idea|pitch)\s*:?\s*)|(?:(?:a|an)\s+[a-z0-9\s-]+\bgame\b))',
            caseSensitive: false,
          ).hasMatch(cleanRef);

      if (renameMatch != null) {
        final rawNewTitle =
            renameMatch.group(1)!.trim().replaceAll(RegExp(r'[."]+$'), '');
        if (rawNewTitle.isNotEmpty) {
          explicitTitleOverride = rawNewTitle;
        }
      } else if (insteadMatch != null || replaceMatch != null) {
        final m = (insteadMatch ?? replaceMatch)!;
        final oldSub = m.group(1)!.trim();
        final newSub = m.group(2)!.trim();
        replacedOldSub = oldSub;
        replacedNewSub = newSub;
        if (RegExp(RegExp.escape(oldSub), caseSensitive: false)
            .hasMatch(effectiveIdea)) {
          effectiveIdea = effectiveIdea.replaceAll(
            RegExp(RegExp.escape(oldSub), caseSensitive: false),
            newSub,
          );
        } else {
          effectiveIdea = '$effectiveIdea using $newSub';
        }
        final capNew = newSub
            .split(RegExp(r'\s+'))
            .take(3)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '')
            .join(' ');
        if (capNew.isNotEmpty) addedTags.add(capNew);
      } else if (isExplicitNewGamePitch) {
        // User explicitly entered a brand-new "A <genre> game..." pitch
        effectiveIdea = cleanRef;
        isFullNewPitch = true;
      } else {
        // Additive / directional refinement (e.g. "add motorcycles", "focus on stealth and drone hacking")
        final strippedClause = cleanRef
            .replaceFirst(
              RegExp(
                r'^(?:please\s+|can\s+we\s+|we\s+should\s+|let\x27s\s+)?(?:add|include|focus\s+on|make\s+it|use|feature|with|also\s+add)\s+',
                caseSensitive: false,
              ),
              '',
            )
            .replaceAll(RegExp(r'[.]+$'), '')
            .trim();
        final clauseToUse =
            strippedClause.isNotEmpty ? strippedClause : cleanRef;
        effectiveIdea = '$effectiveIdea, $clauseToUse';
        addedSentences.add(clauseToUse);
        final shortTag = clauseToUse
            .split(RegExp(r'\s+'))
            .take(3)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '')
            .join(' ');
        if (shortTag.isNotEmpty) {
          addedTags.add(shortTag);
        }
      }
    }

    final title = explicitTitleOverride ??
        _derivePunchyTitle(
          effectiveIdea,
          variantOffset: isUpdateAction ? suggestionVariantOffset : 0,
        );
    final mechs =
        List<String>.from(_deterministicMechanicsForIdea(effectiveIdea));
    if (existingIntake != null && !isFullNewPitch) {
      for (final oldTag in existingIntake.mechanics) {
        if (!mechs.contains(oldTag) &&
            !_deterministicMechanicsForIdea(existingIntake.rawIdea)
                .contains(oldTag)) {
          mechs.add(oldTag);
        }
      }
    }
    for (final tag in addedTags) {
      if (!mechs.any((m) => m.toLowerCase() == tag.toLowerCase())) {
        mechs.add(tag);
      }
    }

    // Preserve and evolve `existingIntake.baseSummary` on Update Summary instead of replacing it
    final hasLegacyQuotedSummary = existingIntake != null &&
        existingIntake.baseSummary.contains('centers on "');
    String summary;
    if (existingIntake != null &&
        isUpdateAction &&
        !isFullNewPitch &&
        !hasLegacyQuotedSummary) {
      summary = existingIntake.baseSummary;
      if (replacedOldSub != null && replacedNewSub != null) {
        if (RegExp(RegExp.escape(replacedOldSub), caseSensitive: false)
            .hasMatch(summary)) {
          summary = summary.replaceAll(
            RegExp(RegExp.escape(replacedOldSub), caseSensitive: false),
            replacedNewSub,
          );
        } else {
          summary = '$summary Incorporates $replacedNewSub into the core loop.';
        }
      }
      if (addedSentences.isNotEmpty) {
        final combinedAdditions = addedSentences.join(' and ');
        if (!summary.toLowerCase().contains(combinedAdditions.toLowerCase())) {
          summary =
              '$summary Incorporates $combinedAdditions directly into the core loop.';
        }
      }
    } else {
      summary = _synthesizeNaturalSparkSummary(
        effectiveIdea,
        title,
        variantOffset: isUpdateAction ? suggestionVariantOffset : 0,
      );
      if (addedSentences.isNotEmpty) {
        final combinedAdditions = addedSentences.join(' and ');
        if (!summary.toLowerCase().contains(combinedAdditions.toLowerCase())) {
          summary =
              '$summary Incorporates $combinedAdditions directly into the core loop.';
        }
      }
    }

    final lower = effectiveIdea.toLowerCase();
    final hasGrapple = lower.contains('grappl') ||
        lower.contains('hook') ||
        lower.contains('swing') ||
        lower.contains('tether');
    final hasParkourOrCourier = (lower.contains('parkour') ||
            lower.contains('wall-run') ||
            lower.contains('wallrun') ||
            lower.contains('cargo') ||
            lower.contains('courier') ||
            lower.contains('haul')) &&
        !hasGrapple;

    final List<SparkExpansionCard> pool;
    if (hasParkourOrCourier) {
      pool = [
        SparkExpansionCard(
          badge: '01 · CORE MECHANIC TWIST',
          title: 'Wall-Run Chain & Vault Boost',
          description:
              'Chain consecutive wall-runs, rooftop vaults, and slides without touching street level to build a sprint speed boost.',
          additionSummary: 'Wall-run chain and rooftop vault speed boost',
          accentType: 'amber',
        ),
        SparkExpansionCard(
          badge: '02 · RISK / REWARD HOOK',
          title: 'Cargo Weight & Scavenger Heat',
          description:
              'Carrying heavier high-payout cargo shifts balance and draws aggressive scavenger ambush packs along your route.',
          additionSummary: 'Cargo weight balance and scavenger ambush heat',
          accentType: 'emerald',
        ),
        SparkExpansionCard(
          badge: '03 · LOOP PAYOFF & UPGRADE',
          title: 'Safe-Zone Dropoff & Rig Upgrades',
          description:
              'Bank completed cargo deliveries at safe-zone terminals to unlock kinetic boots, shock rigs, and quick-draw weapons.',
          additionSummary: 'Safe-zone cargo dropoff and runner rig upgrades',
          accentType: 'neutral',
        ),
        SparkExpansionCard(
          badge: '01 · CORE MECHANIC TWIST',
          title: 'Momentum Slide & Rooftop Kick',
          description:
              'Convert wall-run landing speed into a low slide or knockback kick that launches blocking scavengers off ledges.',
          additionSummary: 'Momentum slide and rooftop knockback kick',
          accentType: 'amber',
        ),
        SparkExpansionCard(
          badge: '02 · RISK / REWARD HOOK',
          title: 'Fragile High-Payout Contraband',
          description:
              'Optional fragile cargo pays 2x credits at extraction but loses integrity whenever you take a hard fall or direct hit.',
          additionSummary: 'Fragile contraband integrity risk/reward',
          accentType: 'emerald',
        ),
        SparkExpansionCard(
          badge: '03 · LOOP PAYOFF & UPGRADE',
          title: 'District Shortcut Ziplines',
          description:
              'Spend delivery credits to permanently unlock rooftop shortcut ramps and stash terminals across metropolis sectors.',
          additionSummary: 'Permanent rooftop shortcut and stash unlocks',
          accentType: 'neutral',
        ),
      ];
    } else if (hasGrapple) {
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

    // Preserve selection state only when not folding/updating
    if (existingIntake != null && !isUpdateAction) {
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
      rawIdea: effectiveIdea,
      workingTitle: title,
      baseSummary: summary,
      mechanics: mechs,
      expansionCards: selectedCards,
    );
  }

  /// Option 5: Extracts a complete 9-section `ProjectConceptBlueprint` from an unstructured
  /// GDD, Notion note, or README document and marks it ready for `Step 10 · Full Review`.
  static Future<ProjectConceptBlueprint> extractConceptFromGdd(
    String rawGdd, {
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanDoc = rawGdd.trim().isEmpty
        ? 'High-speed grappling hook parkour roguelite'
        : rawGdd.trim();

    // Start from the base concept extraction (uses Gemini if key is present, or deterministic fallback)
    final bp = await startConceptInterview(
      cleanDoc,
      apiKey: apiKey,
      modelName: modelName,
      thinkingLevel: thinkingLevel,
    );

    // Parse any explicit markdown headings / bullet lines in the pasted GDD so offline or hybrid imports preserve user lines!
    final lines = cleanDoc
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (line.startsWith('# ') && line.length > 2) {
        final heading = line.substring(2).trim();
        if (heading.isNotEmpty && heading.length <= 42) {
          bp.title = heading;
        }
      } else if (lower.startsWith('title:')) {
        final t = line.substring(6).trim();
        if (t.isNotEmpty) bp.title = t;
      } else if (lower.startsWith('goal:')) {
        final g = line.substring(5).trim();
        if (g.isNotEmpty) bp.goal = g;
      } else if (lower.startsWith('done when:')) {
        final d = line.substring(10).trim();
        if (d.isNotEmpty) bp.doneWhen = d;
      } else if (lower.startsWith('engine:') || lower.startsWith('tech:')) {
        final val = line.split(':').sublist(1).join(':').trim();
        if (val.isNotEmpty) {
          bp.techSpec = val
              .split(RegExp(r'[·,]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
    }

    bp.isInterviewComplete = true;
    bp.lastUpdatedFields = const [
      'Extracted Full 9-Section Concept from Pasted GDD / Notes',
    ];
    return bp;
  }
}
