/// Central Single Source of Truth for the 5-Style LAYERS Text Format Guide
/// (documented in `STYLE_GUIDE.md` and `GEMINI.md`).
///
/// Referenced directly across Stage 1 (`ProjectConceptAgent`) and Stage 2
/// (`ReleasePlannerAgent`, `WorkbenchReleaseMixin`, `GeminiAgentClient`)
/// tool schemas and prompts so Gemini generates the exact target format on
/// the first pass without 2-step post-formatting token waste.
class LayersTextStyleGuide {
  const LayersTextStyleGuide._();

  /// Shared compact style rules injected across Stage 1 & Stage 2 prompts.
  static const String compactStyleRules = '''
RULES (LAYERS 5-STYLE FORMAT GUIDE — GENERATE DIRECTLY AT SOURCE):
- Feature & Epic Titles (Micro-Label): 2-3 plain Title-Case game-dev words naming 1 observable player/world action or object (e.g. "Truck Steering", "Shotgun Spread", "Ore Drop Pickup"). NEVER use code-architecture suffixes ("Controller", "System", "Mechanic", "Manager", "Component", "Handler") or roleplay/archaic lore ("Husbandry", "Homestead", "Expedition") or buzzwords ("canonical", "deliver", "verified", "validate", "leverage", "unified", "end-to-end", "synergy", "seamlessly").
- Release Goals (BLUF): "[2-4 Word Payoff] — [Scope]" (e.g. "3-Wave Arena Combat — Complete E02 Shotgun Hazards and E03 Enemy Waves for MVP.").
- Feature Goals & In-Scope (Changelog +Delta): Direct 5-10 word summary of concrete mechanics/deltas (e.g. "+6-pellet cone spread, +knockback impulse" for upgrades; "Magnetic ore shard spawn on enemy kill" for new features). NEVER start feature goals with "Build a playable..." or "Upgrade <Feature> into/with..." and NEVER copy-paste raw user instructions verbatim.
- Done When, Playtest Gates & Verify (Causal Trigger -> Result): "[Player Action] -> [Observable Screen Result]" (<= 14 words, e.g. "Press Fire within 4m of target -> 6 pellets fan out + push enemy back 2.5m"). NEVER use FPS/60fps targets.
- Concept Spec Cells (02 Game Spec & 03 Tech Spec): Strictly 2-4 Title-Case words naming the concrete setup (e.g. "3D First-Person", "WASD + Mouse", "Singleplayer", "Rooftop Garden Hub", "Unreal Engine 5", "PC Desktop"). NEVER write narrative sentences, explanatory preambles ("with...", "featuring..."), or punctuation.
- Parent Task Group Titles & Goals (tasks[]): tasks[].title = strictly 2-4 Title-Case words naming the specific scene node, UI widget, data resource, or gameplay calculation for that task (e.g. "Shard Physics Hull", "Merchant Trade Panel", "Backpack Weight Counter", "Hitscan Recoil Ray"; NO verbs, NO 3-item lists, NO "(2h)" tags, and NEVER use generic template suffixes like "Body & Collision", "Prop & Collision", "Action & Math", "Cue & Clamp", or "Cue & Boundary Clamp"); tasks[].goal = 1 clear imperative sentence (8-14 words) stating what this task group configures or builds (e.g. "Configure the low-poly scrap shard collision hull, gravity scale, and floor bounce material.").
- Sub-Step Titles & Instructions (Imperative Runbook): subSteps[].title = 3-4 Title-Case "Verb + Object" words (e.g. "Spawn 6 Pellet Raycasts", NO "STEP X.Y" prefix); instruction = 1 imperative sentence (<= 18 words) starting with a command verb + exact node/script and tuning value.''';

  // ── Stage 1: Concept Blueprint Schema Descriptions ────────────────────────

  static const String stage1TitleSchemaDesc =
      'Short 2-3 word plain Title-Case game title.';

  static const String stage1GoalSchemaDesc =
      '1 direct sentence: "Build a playable [Title] prototype where you [action 1], [action 2], and [action 3]." (No "Strategy Label:" prefix on goal).';

  static const String specCellSchemaDesc =
      'Strictly 2-4 Title-Case words naming the setup (e.g. "3D First-Person", "WASD + Mouse", "Singleplayer", "Rooftop Garden Hub"). NEVER write full sentences or narrative clauses.';

  /// Compresses a verbose narrative Game Spec or Tech Spec cell string into a crisp
  /// 2–4 word Title-Case telegraphic tag (Style 5).
  static String formatTelegraphicSpecValue(String raw) {
    var clean = raw.trim().replaceFirst(RegExp(r'^Offline(?:-Only)?\s+', caseSensitive: false), '');
    // Strip leading field name labels if present (e.g. "Perspective: 3D Third-Person")
    final colonIdx = clean.indexOf(':');
    if (colonIdx > 0 && colonIdx <= 24 && colonIdx < clean.length - 1) {
      clean = clean.substring(colonIdx + 1).trim();
    }
    // Prune trailing punctuation
    while (clean.endsWith('.') || clean.endsWith(',')) {
      clean = clean.substring(0, clean.length - 1).trim();
    }

    // Common verbose phrases compression
    if (clean == 'Twin-Stick (WASD + Mouse Aim)' ||
        clean == 'Twin-Stick (WASD + Aim)') {
      return 'WASD + Mouse';
    }
    if (clean == 'Keyboard and Mouse / Gamepad with contextual controls' ||
        clean.toLowerCase().contains('keyboard and mouse / gamepad') ||
        clean.toLowerCase().contains('keyboard & mouse / gamepad') ||
        clean.toLowerCase().contains('kbm / gamepad')) {
      return 'KBM / Gamepad';
    }
    if (clean == 'Single-Screen Wave Arena') {
      return 'Single-Screen Arena';
    }

    // Strip trailing narrative/prepositional clauses ("with...", "featuring...", "that allows...", "where...")
    final narrativeClauseMatch = RegExp(
      r'\s+(?:with|featuring|where|that|using)\s+.*$',
      caseSensitive: false,
    ).firstMatch(clean);
    if (narrativeClauseMatch != null && narrativeClauseMatch.start > 3) {
      clean = clean.substring(0, narrativeClauseMatch.start).trim();
    }

    // Strip filler descriptors like "immersive", "narrative survival simulation", etc.
    clean = clean.replaceAll(RegExp(r'\bimmersive\s+', caseSensitive: false), '');

    // Common patterns compression
    final lower = clean.toLowerCase();
    if (lower.contains('first-person') || lower.contains('first person')) {
      if (lower.contains('tool') || lower.contains('camera')) {
        clean = '3D First-Person';
      }
    } else if (lower.contains('third-person') || lower.contains('third person')) {
      if (lower.contains('over-shoulder') || lower.contains('camera')) {
        clean = '3D Third-Person';
      }
    } else if (lower.contains('single-player') || lower.contains('singleplayer')) {
      if (lower.contains('survival')) {
        clean = 'Singleplayer Survival';
      } else if (lower.contains('roguelite') || lower.contains('roguelike')) {
        clean = 'Singleplayer Roguelite';
      } else {
        clean = 'Singleplayer';
      }
    }

    // If still longer than 4 words, take first 3-4 words cleanly
    final words = clean.split(_whitespaceRegex).where((w) => w.isNotEmpty).toList();
    final cappedWords = words.length > 4 ? words.take(3).toList() : words;

    // Convert to Title Case while preserving uppercase 2D/3D/KBM/PC/HUD/UI/WASD
    final titleCased = cappedWords.map((w) {
      if (w.isEmpty) return w;
      final upper = w.toUpperCase();
      if (upper == '2D' || upper == '3D' || upper == 'KBM' || upper == 'PC' || upper == 'HUD' || upper == 'UI' || upper == 'WASD') {
        return upper;
      }
      if (w.contains('-')) {
        return w.split('-').map((p) => p.isEmpty ? p : (p[0].toUpperCase() + p.substring(1).toLowerCase())).join('-');
      }
      if (w.contains('/')) {
        return w.split('/').map((p) {
          final pUpper = p.trim().toUpperCase();
          if (pUpper == 'KBM' || pUpper == 'PC') return pUpper;
          return p.trim().isEmpty ? p : (p.trim()[0].toUpperCase() + p.trim().substring(1).toLowerCase());
        }).join(' / ');
      }
      if (w == '+' || w == '&' || w == '·') return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');

    return titleCased.trim();
  }

  static const String pillarNameSchemaDesc =
      '2-3 Title-Case Word Pillar Name';

  static const String pillarExperienceSchemaDesc =
      'Concise 1-sentence player feeling or emotional tension (never a feature or genre).';

  static const String tradeOffPrioritySchemaDesc =
      '2-4 words naming what we prioritize (e.g. "Arcade dash response")';

  static const String tradeOffAlternativeSchemaDesc =
      '2-4 words naming what we sacrifice (e.g. "Momentum inertia")';

  static const String coreLoopBeatSchemaDesc =
      '2-3 Word Beat Name: Concise observable player action and system response.';

  static const String exclusionItemSchemaDesc =
      'No [2-4 word excluded system/content] (never use "Cut/Defer" or "in v0.1 prototype").';

  // ── Stage 2: Release Plan, Progressive Release & Workbench Descriptions ───

  static const String epicTitleSchemaDesc =
      '2-4 Title-Case game-dev words naming the gameplay system or body of engineering work (never copy a 06 Core Loop beat title word-for-word).';

  static const String featureTitleSchemaDesc =
      '2-3 Title-Case words naming 1 observable action or object (no "System"/"Controller"/"Manager" or "&").';

  static const String blufReleaseGoalSchemaDesc =
      'BLUF style: "[2-4 Word Payoff] — Complete E0# [System] and E0# [System] for [Phase]." (e.g. "3-Wave Arena Combat — Complete E02 Shotgun Hazards and E03 Enemy Waves for MVP.").';

  static const String progressiveEpicOptionSchemaDesc =
      'BLUF + Telegraphic +Delta option: "E0# + E0# · 2-4 Word Title — +delta1 + +delta2 + +delta3" (Option 1 prefixed with "(Recommended) ").';

  static const String progressiveMissingGapSchemaDesc =
      'Telegraphic 4-8 word gap prefixed with "E0#: " naming what is lacking right now.';

  static const String causalTriggerResultSchemaDesc =
      'Causal Trigger -> Result style ("<Player Action> -> <Observable Screen Result>", <= 14 words, no FPS targets).';

  static const String changelogDeltaGoalSchemaDesc =
      'Changelog +Delta style (5-10 words): "+delta1, +delta2" for upgrades (e.g. "+6-pellet cone spread, +knockback impulse") or direct noun summary for new features (e.g. "Magnetic ore shard spawn on enemy kill"). NO "Build/Upgrade <Feature> with" preambles.';

  static const String changelogDeltaInScopeSchemaDesc =
      '2-3 telegraphic 2-4 word changelog deltas without articles a/an/the (prefix upgrades with "+", e.g. "+6-pellet cone spread", "+knockback impulse").';

  static const String taskGroupTitleSchemaDesc =
      'Strictly 2-4 Title-Case words naming the specific scene node, UI widget, data resource, or gameplay calculation for this task (e.g. "Shard Physics Hull", "Merchant Trade Panel", "Backpack Weight Counter", "Hitscan Recoil Ray"). NO verbs (Setup/Code/Create/Trigger/Implement), NO 3-item lists, NO "while/when" clauses, NO "(2h)" duration tags, and NEVER use generic template suffixes ("Body & Collision", "Prop & Collision", "Action & Math", "Cue & Clamp", "Cue & Boundary Clamp").';

  static final RegExp _legacyTemplateSuffixRegex = RegExp(
    r'\b(?:Body\s*&\s*Collision|Prop\s*&\s*Collision|Action\s*&\s*Math|Cue\s*&\s*Boundary\s*Clamp|Cue\s*&\s*Clamp)\b',
    caseSensitive: false,
  );

  /// Returns true if [rawTitle] contains one of the legacy generic 3-task template suffixes.
  static bool isLegacyTemplateTaskTitle(String rawTitle) {
    final head = rawTitle.split(' — ').first.trim();
    return _legacyTemplateSuffixRegex.hasMatch(head);
  }

  /// Replaces any legacy generic template suffix (`Body & Collision`, `Prop & Collision`,
  /// `Action & Math`, `Cue & Boundary Clamp`, `Cue & Clamp`) with a clean component/logic/state noun.
  static String stripLegacyTemplateTaskSuffix(String rawTitle) {
    var s = rawTitle.trim();
    s = s.replaceAllMapped(_legacyTemplateSuffixRegex, (m) {
      final lower = (m.group(0) ?? '').toLowerCase();
      if (lower.contains('collision')) return 'Scene Nodes';
      if (lower.contains('math')) return 'State Logic';
      return 'Feedback & Guard';
    });
    return s.replaceAll(_whitespaceRegex, ' ').trim();
  }

  static const String taskGroupGoalSchemaDesc =
      '1 clear imperative sentence (8-14 words) stating what this task group configures or builds (e.g. "Configure the low-poly scrap shard collision hull, gravity scale, and floor bounce material.").';

  static final RegExp _leadingTaskVerbRegex = RegExp(
    r'^(?:configure|setup|set\s+up|create|build|implement|add|write|code|bind|wire|define|establish|calculate|apply|trigger|spawn|attach|initialize|declare|enable|clamp|verify|test|update|upgrade|connect|hook\s+up|register|assign|expose|tune|polish|integrate|handle|enforce)\s+(?:the\s+|a\s+|an\s+)?',
    caseSensitive: false,
  );
  static final RegExp _trailingTaskClauseRegex = RegExp(
    r'\s+(?:while|when|after|before|during|upon|on\s+[a-z0-9_]+\s+(?:event|death|hit|kill|trigger|overlap|collision|enter|exit)|for\s+(?:the\s+|a\s+)?[a-z0-9_\s]+|in\s+(?:the\s+|a\s+)?(?:greybox|arena|scene|level|chamber|inspector|viewport).*|so\s+that.*|to\s+(?:prevent|ensure|allow|enable|support|clamp|block).*)$',
    caseSensitive: false,
  );
  static final RegExp _taskListSplitRegex = RegExp(
    r'\s*(?:,\s*(?:and\s+|&\s*)?|\s+&\s+|\s+and\s+)\s*',
    caseSensitive: false,
  );
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static const Set<String> _taskFillerWords = <String>{
    'the',
    'a',
    'an',
    'with',
    'using',
    'into',
    'onto',
    'from',
    'low-poly',
    'low',
    'poly',
    'custom',
    'basic',
    'simple',
    'initial',
    'core',
    'proper',
    'clean',
    'playable',
    'functional',
    'dynamic',
    'stylized',
  };

  /// Deterministically condenses a legacy verbose task title (when no `" — "` separator is present)
  /// into a clean `2–4` word Title-Case micro-label (Style 5) so `01 STEPS` and the Step Picker
  /// dropdown never overflow or wrap across 3 lines.
  static String formatConciseTaskTitle(String rawTitle) {
    var t = rawTitle.trim();
    if (t.isEmpty) return t;
    final dashIdx = t.indexOf(' — ');
    if (dashIdx > 0) {
      t = t.substring(0, dashIdx).trim();
    }
    t = stripLegacyTemplateTaskSuffix(t);

    String? badgePrefix;
    if (t.startsWith('[FIX]')) {
      badgePrefix = '[FIX] ';
      t = t.substring(5).trim();
    } else if (t.startsWith('[POLISH]')) {
      badgePrefix = '[POLISH] ';
      t = t.substring(8).trim();
    }

    final initialWords =
        t.split(_whitespaceRegex).where((w) => w.isNotEmpty).toList();
    if (initialWords.length <= 4 &&
        !_leadingTaskVerbRegex.hasMatch(t) &&
        !t.contains(',')) {
      return badgePrefix != null ? '$badgePrefix$t' : t;
    }

    t = t.replaceFirst(_leadingTaskVerbRegex, '').trim();
    t = t.replaceFirst(_trailingTaskClauseRegex, '').trim();

    final clauses = t
        .split(_taskListSplitRegex)
        .map((c) => c.replaceFirst(_leadingTaskVerbRegex, '').trim())
        .where((c) => c.isNotEmpty)
        .toList();

    List<String> cleanClauseWords(String clause) {
      final rawWords = clause
          .replaceAll(RegExp(r'[^\w\s\-/]'), '')
          .split(_whitespaceRegex)
          .where((w) => w.isNotEmpty)
          .toList();
      final filtered = rawWords
          .where((w) => !_taskFillerWords.contains(w.toLowerCase()))
          .toList();
      final source = filtered.isNotEmpty ? filtered : rawWords;
      if (source.length <= 2) return source;
      return source.sublist(source.length - 2);
    }

    String titleCaseWord(String w) {
      if (w.isEmpty) return w;
      if (w.toUpperCase() == w && w.length >= 2) return w;
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }

    String result;
    if (clauses.length >= 2) {
      final firstPart = cleanClauseWords(clauses.first).map(titleCaseWord).join(' ');
      final secondPart = cleanClauseWords(clauses[1]).map(titleCaseWord).join(' ');
      if (firstPart.isNotEmpty &&
          secondPart.isNotEmpty &&
          firstPart.toLowerCase() != secondPart.toLowerCase()) {
        final combinedWords = '$firstPart & $secondPart'.split(_whitespaceRegex);
        if (combinedWords.length <= 5) {
          result = '$firstPart & $secondPart';
        } else {
          final shortFirst = titleCaseWord(cleanClauseWords(clauses.first).last);
          final shortSecond = titleCaseWord(cleanClauseWords(clauses[1]).last);
          result = '$shortFirst & $shortSecond';
        }
      } else {
        result = firstPart.isNotEmpty ? firstPart : secondPart;
      }
    } else {
      final words = (clauses.isNotEmpty ? clauses.first : t)
          .replaceAll(RegExp(r'[^\w\s\-/&]'), '')
          .split(_whitespaceRegex)
          .where((w) => w.isNotEmpty && !_taskFillerWords.contains(w.toLowerCase()))
          .toList();
      final capped = words.length > 4 ? words.take(4).toList() : words;
      result = capped.map(titleCaseWord).join(' ');
    }

    if (result.isEmpty) {
      final fallback = initialWords.take(4).map(titleCaseWord).join(' ');
      return badgePrefix != null ? '$badgePrefix$fallback' : fallback;
    }
    return badgePrefix != null ? '$badgePrefix$result' : result;
  }

  static const String tuningParamSchemaDesc =
      'paramName: numericValue unit (e.g. "dashSpeed: 14.0 m/s")';

  static const String stateGuardSchemaDesc =
      'Telegraphic state guard formatted as "[STATE GUARD] <3-6 word rule without articles a/an/the>" (e.g. "[STATE GUARD] Block dash while cooldown active").';

  static const String playtestGuardSchemaDesc =
      'Telegraphic guard formatted as "[PLAYTEST GUARD] <3-6 word rule without articles a/an/the>"';

  static const String runbookStepTitleSchemaDesc =
      '3-4 Title-Case Imperative Runbook words (Verb + Object, e.g. "Spawn 6 Pellet Raycasts", "Add Hazard Detection Component", drop articles a/an/the). Do NOT include "STEP X.Y" prefix.';

  static const String runbookStepPathSchemaDesc =
      'Telegraphic editor panel/menu/inspector/script breadcrumb separated by " > "';

  static const String runbookInstructionSchemaDesc =
      '1 Imperative Runbook sentence (<= 18 words) starting with a command verb (Create, Bind, Spawn, Clamp, Set) + exact node/script and tuning value.';
}
