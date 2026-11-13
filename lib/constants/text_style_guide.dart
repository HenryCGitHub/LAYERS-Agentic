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
- Concept Spec Cells (02 Game Spec & 03 Tech Spec): Strictly 2-4 Title-Case words naming the concrete setup (e.g. "3D First-Person", "WASD + Mouse", "Singleplayer", "Rooftop Garden Hub", "Godot 4 (GDScript)", "PC Desktop"). NEVER write narrative sentences, explanatory preambles ("with...", "featuring..."), or punctuation.
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

  static final RegExp _anyDurationTagRe =
      RegExp(r'\s*\(([\d\.]+\s*[hm])\)', caseSensitive: false);
  static final RegExp _trailingForBeatSuffixRegex =
      RegExp(r'\s+for\s+[A-Z][\w\s&\-\/]*$');
  static final RegExp _leadingVerbPrefixRegex = RegExp(
    r'^(?:Create|Implement|Build|Configure|Set\s+up|Setup|Code|Write|Add|Hook\s+up|Hook|Wire|Subscribe|Enforce|Spawn|Apply|Bind|Trigger|Update|Extend|Upgrade|Define|Declare|Attach|Connect|Handle|Polish)\s+(?:(?:a|an|the)\s+)?',
    caseSensitive: false,
  );
  static final RegExp _inlineAmpersandVerbRegex = RegExp(
    r'(&|,)\s*(?:and\s+)?(?:create|implement|build|configure|set\s+up|setup|code|write|add|hook\s+up|hook|wire|subscribe|enforce|spawn|apply|bind|trigger|update|extend|upgrade|define|declare|attach|connect|handle|polish)\s+(?:(?:a|an|the)\s+)?',
    caseSensitive: false,
  );
  static final RegExp _trailingSubordinateClauseRegex = RegExp(
    r'\s+(?:while|when|during|so\s+that|in\s+order\s+to)\s+.*$',
    caseSensitive: false,
  );
  static final RegExp _leadingArticlePrefixRegex = RegExp(
    r'^(?:a|an|the)\s+',
    caseSensitive: false,
  );
  static final RegExp _inlineArticlesRegex = RegExp(
    r'\b(?:a|an|the)\s+',
    caseSensitive: false,
  );
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _cutPrefixRegex = RegExp(
    r'^\[cut\]\s*',
    caseSensitive: false,
  );
  static final RegExp _noPrefixRegex = RegExp(
    r'^no\s+',
    caseSensitive: false,
  );
  static final RegExp _leadingBulletRegex = RegExp(r'^[•\-\*\s]+');
  static final RegExp _tradeOffVerbPrefixRegex = RegExp(
    r'^(?:prioritize|favor|choose)\s+',
    caseSensitive: false,
  );
  static final RegExp _exclusionCutVerbPrefixRegex = RegExp(
    r'^(?:cut|defer|exclude|skip)\s+',
    caseSensitive: false,
  );
  static final RegExp _exclusionProtoSuffixRegex = RegExp(
    r'\s+(?:in|for|during)\s+(?:the\s+)?(?:v0\.1\s+)?prototype$',
    caseSensitive: false,
  );
  static final RegExp _exclusionV01SuffixRegex = RegExp(
    r'\s+in\s+v0\.1$',
    caseSensitive: false,
  );

  static const Set<String> _kAcronymWords = <String>{
    '2D',
    '3D',
    'UI',
    'HUD',
    'VFX',
    'SFX',
    'NPC',
    'AI',
    'WASD',
    'C++',
    'FPS',
    'IK',
    'UV',
    'LOD',
    'PBR',
    'GI',
  };

  /// Deterministically condenses a legacy verbose task title (when no `" — "` separator is present)
  /// into a clean `2–4` word Title-Case micro-label (Style 5) so `01 STEPS` and the Step Picker
  /// dropdown never overflow or wrap across 3 lines.
  static String formatConciseTaskTitle(String rawCleanTitle) {
    var text = rawCleanTitle.replaceAll(_anyDurationTagRe, '').trim();
    if (text.isEmpty) return text;
    final dashIdx = text.indexOf(' — ');
    if (dashIdx > 0) {
      text = text.substring(0, dashIdx).trim();
    }
    text = stripLegacyTemplateTaskSuffix(text);

    String? badgePrefix;
    if (text.startsWith('[FIX]')) {
      badgePrefix = '[FIX] ';
      text = text.substring(5).trim();
    } else if (text.startsWith('[POLISH]')) {
      badgePrefix = '[POLISH] ';
      text = text.substring(8).trim();
    }

    String withBadge(String val) =>
        badgePrefix != null ? '$badgePrefix$val' : val;

    final lower = text.toLowerCase();
    if (lower.startsWith('create actor/node structure') ||
        lower.startsWith('create actor / node structure')) {
      return withBadge('Actor & Base Properties');
    }
    if (lower.startsWith('implement core state transitions')) {
      return withBadge('State Logic & Player Input');
    }
    if (lower.startsWith('hook visual/audio feedback cues') ||
        lower.startsWith('hook up visual/audio feedback cues')) {
      return withBadge('Feedback Cues & State Guard');
    }
    if (lower.startsWith('create camera rig and hud')) {
      return withBadge('Camera Rig & HUD Container');
    }
    if (lower.startsWith('implement camera follow smoothing')) {
      return withBadge('Follow Smoothing & Bound Clamp');
    }
    if (lower.startsWith('wire active state readout')) {
      return withBadge('State Readout & Viewport Test');
    }

    // Strip redundant trailing " for <Beat/Feature Name>" and subordinate clauses ("while ...", "when ...")
    text = text
        .replaceFirst(_trailingForBeatSuffixRegex, '')
        .replaceFirst(_trailingSubordinateClauseRegex, '');
    text = text
        .replaceFirst(_leadingVerbPrefixRegex, '')
        .replaceFirst(_leadingArticlePrefixRegex, '')
        .replaceAllMapped(
          _inlineAmpersandVerbRegex,
          (m) => '${m.group(1)} ',
        )
        .replaceAll(_inlineArticlesRegex, '')
        .replaceAll(' and ', ' & ')
        .trim();
    if (text.contains(',') || text.length > 40) {
      final rawClauses = text
          .split(RegExp(r'\s*(?:,|&)\s*'))
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .take(2)
          .toList();
      if (rawClauses.isNotEmpty) {
        final condensedClauses = <String>[];
        for (final clause in rawClauses) {
          final strippedClause = clause
              .replaceFirst(_leadingVerbPrefixRegex, '')
              .replaceFirst(_leadingArticlePrefixRegex, '')
              .trim();
          final rawWords = strippedClause
              .split(_whitespaceRegex)
              .where((w) => w.isNotEmpty && w.toLowerCase() != 'response')
              .toList();
          // Check if duplicate trailing word exists (e.g. "Ghost trail particle trail" -> "Ghost trail")
          final seenLower = <String>{};
          final hasDuplicateWord =
              rawWords.any((w) => !seenLower.add(w.toLowerCase()));
          final List<String> coreWords;
          if (rawWords.length <= 2) {
            coreWords = rawWords;
          } else if (hasDuplicateWord) {
            final deduped = <String>[];
            final seen = <String>{};
            for (final w in rawWords) {
              if (seen.add(w.toLowerCase())) {
                deduped.add(w);
              }
            }
            coreWords = deduped.take(2).toList();
          } else {
            coreWords = rawWords.sublist(rawWords.length - 2);
          }
          if (coreWords.isNotEmpty) {
            final titleCased = coreWords
                .map((w) {
                  final upper = w.toUpperCase();
                  if (_kAcronymWords.contains(upper)) return upper;
                  return w.length == 1
                      ? upper
                      : w[0].toUpperCase() + w.substring(1);
                })
                .join(' ');
            condensedClauses.add(titleCased);
          }
        }
        if (condensedClauses.isNotEmpty) {
          return withBadge(condensedClauses.join(' & '));
        }
      }
    }
    if (text.isNotEmpty) {
      text = text[0].toUpperCase() + text.substring(1);
    }
    return text.isEmpty ? rawCleanTitle : withBadge(text);
  }

  /// Strips leading `"Prioritize / Favor / Choose"` and trailing periods from a stored Trade-Off rule.
  static String compactStoredTradeOff(String raw) {
    var clean = raw.trim();
    if (clean.endsWith('.')) {
      clean = clean.substring(0, clean.length - 1).trim();
    }
    return clean.replaceFirst(_tradeOffVerbPrefixRegex, '');
  }

  /// Strips leading `"Cut / Defer / Exclude / Skip"` (replacing with `"No "`) and trailing `"in v0.1 prototype"`
  /// from a stored Out-of-Scope exclusion item.
  static String compactStoredExclusion(String raw) {
    var clean = raw.trim();
    if (clean.endsWith('.')) {
      clean = clean.substring(0, clean.length - 1).trim();
    }
    final colonIdx = clean.indexOf(':');
    if (colonIdx > 0 && colonIdx < 32) {
      clean = clean.substring(colonIdx + 1).trim();
    }
    return clean
        .replaceFirst(_exclusionCutVerbPrefixRegex, 'No ')
        .replaceAll(_exclusionProtoSuffixRegex, '')
        .replaceAll(_exclusionV01SuffixRegex, '')
        .trim();
  }

  /// Strips leading `[CUT]`, `No `, and bullet characters from an exclusion string.
  static String stripExclusionPrefixes(
    String raw, {
    bool stripNoPrefix = true,
  }) {
    var text = raw.replaceFirst(_cutPrefixRegex, '');
    if (stripNoPrefix) {
      text = text.replaceFirst(_noPrefixRegex, '');
    }
    return text.replaceFirst(_leadingBulletRegex, '').trim();
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
      '2-4 short newline-separated imperative micro-actions (max 10 words per line, each starting with "- <Dock/Node> → <Command Verb + Value>" or "- <Command Verb + Exact Node/Value>"). Never write a paragraph.';

  static const List<String> engineBuildTierEnum = <String>[
    'tier_1_world_space',
    'tier_2_actor_locomotion',
    'tier_3_targets_hazards',
    'tier_4_verbs_tools_combat',
    'tier_5_loop_economy_hud',
  ];

  static const String buildTierSchemaDesc =
      'Engine build-dependency tier: tier_1_world_space (Arena/Level/Grid/Camera blockout), tier_2_actor_locomotion (Player/Vehicle/Cursor controller), tier_3_targets_hazards (Enemies, Props, Spawners, Hazards — world nouns), tier_4_verbs_tools_combat (Weapons, Tools, Projectiles, Interactions — verbs acting on Tier 2-3), or tier_5_loop_economy_hud (Wave/Score/Shop state, Reset, HUD widgets).';

  static const List<String> stepPhaseRoleEnum = <String>[
    'editor_setup',
    'script_logic',
    'wire_and_verify',
  ];

  static const String stepPhaseRoleSchemaDesc =
      'Intra-task runbook beat: editor_setup (create Scene/Hierarchy nodes, Colliders, Collision Layers, or exported Inspector properties FIRST), script_logic (add/extend functions & math on primarySharedScriptOrScene SECOND), or wire_and_verify (connect signals/events/Inspector refs & verify THIRD).';

  static const List<String> verifyModeEnum = <String>[
    'editor',
    'playtest',
  ];

  static const String verifyModeSchemaDesc =
      'Verification mode: "editor" for pure setup steps whose runtime wiring does not exist yet (inspect Scene Tree / Inspector / 0 compile errors without pressing Play), or "playtest" for runnable steps (mandatory on final step of playable tasks & checkpoints).';

  static const String stepVerifyResultSchemaDesc =
      'If verifyMode=="editor": concise Hierarchy/Inspector/Compiler check (<= 14 words, NO "Press Play ->", e.g. "PlayerCharacter shows DashTimer child node + 0 script errors"). If verifyMode=="playtest": Causal Trigger -> Result ("<Player Action> -> <Observable Screen Result>", <= 14 words).';
}
