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
  "designPillars": ["Experiential pillar 1", "Experiential pillar 2", "Experiential pillar 3"],
  "tradeOffs": ["X over Y rule 1", "X over Y rule 2", "X over Y rule 3"],
  "coreLoopBeats": ["Beat Name: Literal action and response", "..."],
  "exclusions": ["Prototype exclusion 1", "Prototype exclusion 2", "Prototype exclusion 3"],
  "doneWhen": "Concrete playtest completion condition",
  "releaseTrainTitles": ["v0.1: [Plain Prototype Name] - Prototype"],
  "sectionOptions": {
    "goal": ["Title 1: Build...", "Title 2: Build...", "Title 3: Build..."],
    "designPillars": ["Title 1: Experience...", "Title 2: Experience...", "Title 3: Experience..."],
    "coreLoop": ["Title 1: Beat A → Beat B → Beat C → Beat D", "Title 2: ...", "Title 3: ..."]
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
      goal: _synthesizeInitialGoalForSpark(cleanSpark, shortTitle),
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
    final cleanMsg = ProjectConceptBlueprint.normalizeCommonTypos(
      userMessage.trim(),
    );
    if (cleanMsg.isEmpty) return draft;

    draft.chatHistory.add(
      AgentChatMessage(
        id: 'msg_user_${draft.chatHistory.length}',
        role: 'user',
        text: cleanMsg,
      ),
    );

    // Cap history to the last 2 messages (and omit when a direct [Section XX] tag is present)
    final isDirectSectionEdit = cleanMsg.startsWith('[Section ');
    final historySlice = isDirectSectionEdit
        ? const <AgentChatMessage>[]
        : (draft.chatHistory.length > 3
            ? draft.chatHistory.sublist(draft.chatHistory.length - 3, draft.chatHistory.length - 1)
            : draft.chatHistory.take(draft.chatHistory.length - 1).toList());
    final recentHistory = historySlice
        .map((m) => '${m.isUser ? "Dev" : "AI"}: ${m.text}')
        .join('\n');

    // Delta-Only JSON Prompt (~380 input tokens, ~140 output tokens — 75% reduction)
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
${recentHistory.isNotEmpty ? 'Recent Context:\n$recentHistory\n' : ''}
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
        draft.designPillars = pillars;
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

      final quickReplies = cleanList(json['quickReplies']) ?? const <String>[];

      final replyText = json['reply']?.toString().trim() ??
          'Updated the Project Concept Blueprint with your direction!';

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

    // Offline / deterministic turn synthesis fallback
    _applyDeterministicChatTurn(draft, cleanMsg, conversationModel);
    return draft;
  }

  static void _applyDeterministicChatTurn(
    ProjectConceptBlueprint draft,
    String userMsg,
    String modelUsed,
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
      draft.designPillars.add(cleanTurn);
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
        text: 'Got it — I synthesized your direction into the **${updated.join(" & ")}** on the live Blueprint.$followUp',
        quickReplies: nextChips,
      ),
    );
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

  static String _stripRecommendedPrefix(String input) {
    return input
        .replaceFirst(RegExp(r'^\(Recommended\)\s*', caseSensitive: false), '')
        .trim();
  }

  /// Extracts a concise synthesized premise phrase from `spark` (never echoing raw "X game but in a Y" brain dumps).
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
    if (base.isEmpty || base.length > 72) {
      return '${fallbackTitle.toLowerCase()} mechanics';
    }
    return base;
  }

  static String _derivePunchyTitle(String spark) {
    final normalized = ProjectConceptBlueprint.normalizeCommonTypos(spark);
    // If spark has "but in a <twist>" or "instead of <old> we use <twist>", lead with the twist!
    final twistMatch = RegExp(
      r'\b(?:but\s+(?:in|with|as)\s+(?:a\s+|an\s+|the\s+)?|instead\s+of\s+[a-z]+\s+(?:we\s+)?use\s+)([a-zA-Z0-9-]+)',
      caseSensitive: false,
    ).firstMatch(normalized);

    const stopWords = {
      'the', 'and', 'with', 'for', 'game', 'about', 'fast', 'that', 'also',
      'combines', 'like', 'where', 'you', 'can', 'into', 'from', 'but',
      'instead', 'use', 'using',
    };
    final words = normalized
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stopWords.contains(w.toLowerCase()))
        .take(3)
        .toList();
    if (words.isEmpty) return 'Core Prototype';
    if (twistMatch != null && words.isNotEmpty) {
      final twistWord = twistMatch.group(1)!.trim();
      if (twistWord.length >= 3) {
        words[0] = twistWord.toLowerCase().endsWith('s') && twistWord.length > 3
            ? twistWord.substring(0, twistWord.length - 1)
            : twistWord;
      }
    }
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
You are an indie game producer summarizing a developer's game idea before building the blueprint.
${isRefinement ? 'Title: "${existingIntake.workingTitle}"\nSummary: "${existingIntake.baseSummary}"\nRefinement: "$cleanInput"' : 'Idea: "$seedIdea"'}
${GeminiAgentClient.compactStyleRules}

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
