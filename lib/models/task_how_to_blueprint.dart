import '../constants/text_style_guide.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';

/// Canonical Godot 4 workflow dock stage for a Unified Step inside a Feature Build Queue.
enum GodotDockStage {
  scene(
    badge: 'SCENE',
    fullLabel: 'SCENE TREE (.tscn)',
    stepRole: 'editor_setup',
    sortOrder: 0,
  ),
  inspector(
    badge: 'INSP',
    fullLabel: 'PROPERTY & LAYER SHEET',
    stepRole: 'inspector_setup',
    sortOrder: 1,
  ),
  code(
    badge: 'CODE',
    fullLabel: 'GDSCRIPT PATCH (.gd)',
    stepRole: 'script_logic',
    sortOrder: 2,
  ),
  wire(
    badge: 'WIRE',
    fullLabel: 'NODE SIGNALS & F6',
    stepRole: 'wire_and_verify',
    sortOrder: 3,
  ),
  fix(
    badge: 'FIX',
    fullLabel: 'ROOT-CAUSE [FIX]',
    stepRole: 'fix',
    sortOrder: 4,
  ),
  gate(
    badge: 'GATE',
    fullLabel: 'PLAYTEST SIGN-OFF',
    stepRole: 'wire_and_verify',
    sortOrder: 5,
  );

  const GodotDockStage({
    required this.badge,
    required this.fullLabel,
    required this.stepRole,
    required this.sortOrder,
  });

  final String badge;
  final String fullLabel;
  final String stepRole;
  final int sortOrder;
}

/// Represents a single checkable "How-To" sub-step inside a Feature's Build Queue.
class TaskHowToSubStep {
  final Subtask subtask;
  final String stepNumberLabel; // e.g., "01 · CREATE PLAYER SCENE"
  final String shortTitle;      // e.g., "Build Player Dash Child Nodes"
  final String instruction;     // Concrete implementation instruction
  final String verifyResult;    // "✓ VERIFY BEFORE CHECKING [✓]" visual check
  final String stepPath;        // e.g., "Scene Dock → res://scenes/player.tscn"
  final String codeFormula;     // Short GDScript diff / Inspector pipe table / node chain
  final String explainConcept;  // Project-connected note
  final List<String> specChips; // Spec connection chips
  final String quickFixPitfall; // Step-specific pitfall hint
  final int estimatedMinutes;   // Weighted minutes for this specific step
  final String etaLabel;        // Formatted step ETA (e.g., "15m", "25m")
  final bool isGuardStep;
  final bool isEditorCheck;     // True when step checks Scene Tree / Inspector without Play mode
  final String? stepRole;       // 'editor_setup' | 'inspector_setup' | 'script_logic' | 'wire_and_verify' | 'fix'
  final GodotDockStage? dockStage;
  final String? area1Hierarchy; // Optional AI-synthesized Area 1 (Scene Tree Hierarchy)
  final String? area2Inspector; // Optional AI-synthesized Area 2 (Inspector Bindings)

  const TaskHowToSubStep({
    required this.subtask,
    required this.stepNumberLabel,
    this.shortTitle = '',
    required this.instruction,
    this.verifyResult = '',
    this.stepPath = '',
    required this.codeFormula,
    this.explainConcept = '',
    this.specChips = const [],
    this.quickFixPitfall = '',
    this.estimatedMinutes = 15,
    this.etaLabel = '15m',
    this.isGuardStep = false,
    this.isEditorCheck = false,
    this.stepRole,
    this.dockStage,
    this.area1Hierarchy,
    this.area2Inspector,
  });

  GodotDockStage get resolvedDockStage =>
      dockStage ??
      TaskHowToBlueprint.classifySubStepDockStage(
        title: shortTitle.isNotEmpty ? shortTitle : subtask.text,
        stepRole: stepRole,
        area1Hierarchy: area1Hierarchy,
        area2Inspector: area2Inspector,
        codeFormula: codeFormula,
        stepPath: stepPath,
        instruction: instruction,
      );
}

/// Resolves and caches the structured Parent Task metadata (`numLabel`, `layerTag`,
/// `cleanTitle`, `durationChip`, `whereLocation`, `engineLabel`) and ensures each Parent Task has
/// checkable `How-To` sub-steps (`Subtask.children`) with automatic rollup and Godot 4 formulas.
class TaskHowToBlueprint {
  final String numLabel;      // "01", "02", ...
  final String layerTag;      // "INPUT", "PHYSICS", "STATE", "FEEL", "UI"
  final String cleanTitle;    // Task title without trailing "(2h)"
  final String durationChip;  // Extracted "2h" or "1h"
  final String whereLocation; // e.g. "Script: player_character._physics_process(delta)"
  final String engineLabel;   // "GODOT 4"
  final List<TaskHowToSubStep> subSteps;

  const TaskHowToBlueprint({
    required this.numLabel,
    required this.layerTag,
    required this.cleanTitle,
    required this.durationChip,
    required this.whereLocation,
    required this.engineLabel,
    required this.subSteps,
  });

  static final RegExp _trailingDurationRe =
      RegExp(r'\s*\(([\d\.]+\s*[hm])\)\s*$', caseSensitive: false);
  static final RegExp _anyDurationTagRe =
      RegExp(r'\s*\(([\d\.]+\s*[hm])\)', caseSensitive: false);
  static final RegExp _leadingTagRe = RegExp(
    r'^\[(?:PREREQ|BUILD|HOOK|TEST|INPUT|STATE|PHYSICS|FEEL|UI)\]\s*',
    caseSensitive: false,
  );
  static final RegExp _identifierWordRegex = RegExp(r'[A-Za-z0-9]+');
  static final RegExp _clauseSplitRegex = RegExp(
    r'\s*(?:,|;|->|\+|\band\b|\bthen\b|&)\s*',
    caseSensitive: false,
  );
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _nonLowerAlnumRegex = RegExp(r'[^a-z0-9]+');
  static final RegExp _trimUnderscoresRegex = RegExp(r'^_+|_+$');
  static final RegExp _nonIdentCharRegex = RegExp(r'[^a-zA-Z0-9_]');
  static final RegExp _leadingBracketTagRegex = RegExp(r'^\[[^\]]+\]\s*');
  static final RegExp _bracketTagCaptureRegex = RegExp(r'^\[([^\]]+)\]');
  static final RegExp _stepHeaderPrefixRegex =
      RegExp(r'^STEP\s+\d+\.\d+\s*·\s*', caseSensitive: false);
  static final RegExp _progressiveGoalPreambleRegex = RegExp(
    r'^(?:Goal:\s*)?(?:Upgrade|Polish|Extend|Scale|Tune)\s+[\w\s\-&/]{1,36}?(?:\s+from\s+v\d+\.\d+(?:\s+greybox)?)?\s+(?:(?:into|to)\s+(?:(?:a|an|the|full|complete)\s+)?[\w\s\-]{1,28}?\s+with\s+|with\s+)',
    caseSensitive: false,
  );
  static final RegExp _inlineArticlesRegex = RegExp(
    r'\b(?:a|an|the)\s+',
    caseSensitive: false,
  );
  static final RegExp _digitsOnlyRegex = RegExp(r'^\d+$');
  static final RegExp _trailingGuardSuffixRegex =
      RegExp(r'[\s_]+GUARD$', caseSensitive: false);
  static final RegExp _whitespaceOrUnderscoreRegex = RegExp(r'[\s_]+');
  static final RegExp _versionTokenRegex =
      RegExp(r'^v\d+$', caseSensitive: false);

  static const Set<String> _kAssetNameStopWords = <String>{
    'create',
    'build',
    'implement',
    'implementation',
    'playtest',
    'add',
    'wire',
    'hook',
    'up',
    'setup',
    'set',
    'bind',
    'apply',
    'enforce',
    'verify',
    'test',
    'the',
    'and',
    'for',
    'with',
    'in',
    'on',
    'to',
    'of',
    'a',
    'an',
    'core',
    'state',
    'player',
    'interaction',
    'mechanics',
    'controls',
    'logic',
    'pass',
    'stage',
    'checkpoint',
    'checkpoints',
    'milestone',
    'phase',
    'step',
    'task',
    'version',
    'system',
    'systems',
    'controller',
    'controllers',
    'mechanic',
    'manager',
    'managers',
    'module',
    'handler',
    'service',
    'feature',
    'structure',
    'base',
    'basic',
    'initial',
    'input',
    'mapping',
    'tuning',
    'config',
    'configuration',
    'wiring',
    'pawn',
    'properties',
    'actor',
    'node',
    'velocity',
    'friction',
    'physics',
    'blend',
    'animation',
    'camera',
    'collision',
    'capsule',
  };

  static const Set<String> _kGenericGuardTags = <String>{
    'GUARD',
    'STATE GUARD',
    'INPUT GUARD',
    'PLAYTEST GUARD',
    'SIMULATION GUARD',
  };

  static const Set<String> _kDefaultGuardTokens = <String>{
    'NOT bSelectionLocked',
    '!bSelectionLocked',
    'not selection_locked',
    'bSelectionLocked = true',
    'selection_locked = true',
    'bSelectionLocked',
    'selection_locked',
    'NOT bResetInProgress',
    '!bResetInProgress',
    'bResetInProgress = true',
    'bResetInProgress',
    'reset_in_progress',
  };

  /// Concise 2–4 word task title for `01 STEPS` and the Step Picker dropdown.
  String get shortTaskTitle => formatConciseTaskTitle(cleanTitle);

  /// Clear 1-sentence imperative goal for `02 TASK OVERVIEW` (`GOAL:`).
  /// Uses the explicit `goal` part when `cleanTitle` is formatted as `"Title — Goal"`,
  /// or uses the full sentence when `cleanTitle` is a legacy long sentence, or synthesizes
  /// a natural 1-sentence goal from the child sub-steps when `cleanTitle` is a short 2–4 word label.
  String get taskGoalSentence {
    final raw = cleanTitle.replaceAll(_anyDurationTagRe, '').trim();
    final dashIdx = raw.indexOf(' — ');
    if (dashIdx > 0 && dashIdx + 3 < raw.length) {
      final goalPart = raw.substring(dashIdx + 3).trim();
      if (goalPart.isNotEmpty) {
        return goalPart.endsWith('.') ? goalPart : '$goalPart.';
      }
    }
    final words = raw.split(_whitespaceRegex).where((w) => w.isNotEmpty).toList();
    if (words.length >= 6) {
      final cap = raw[0].toUpperCase() + raw.substring(1);
      return cap.endsWith('.') ? cap : '$cap.';
    }
    if (subSteps.isNotEmpty) {
      final stepTitles = subSteps
          .map((s) => s.shortTitle.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (stepTitles.length == 1) {
        final firstInst = subSteps.first.instruction.trim();
        if (firstInst.isNotEmpty) {
          return firstInst.endsWith('.') ? firstInst : '$firstInst.';
        }
      } else if (stepTitles.length >= 2) {
        String lowerFirst(String s) =>
            s.length > 1 ? '${s[0].toLowerCase()}${s.substring(1)}' : s.toLowerCase();
        final first = stepTitles.first;
        final rest = stepTitles.skip(1).take(2).map(lowerFirst).toList();
        final joined = rest.length == 1
            ? '$first and ${rest.first}'
            : '$first, ${rest.first}, and ${rest.last}';
        return joined.endsWith('.') ? joined : '$joined.';
      }
    }
    if (raw.isEmpty) return 'Complete the implementation steps for this task group.';
    return 'Configure and wire $raw in $whereLocation.';
  }

  /// Causal `Trigger → Result` verification check for `02 TASK OVERVIEW` (`✓ DONE:`),
  /// reused directly from the task's final sub-step `verifyResult` (`0` extra tokens).
  String get taskDoneCheck {
    for (int i = subSteps.length - 1; i >= 0; i--) {
      final rawVerify = subSteps[i]
          .verifyResult
          .replaceFirst(
            RegExp(
              r'^✓?\s*VERIFY(?:\s+IN\s+ENGINE|\s+BEFORE\s+CHECKING\s*\[✓\])?\s*:\s*',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      if (rawVerify.isNotEmpty) {
        return rawVerify;
      }
    }
    return 'Complete all ${subSteps.length} steps in $shortTaskTitle → behavior responds cleanly in Play mode.';
  }

  static String formatConciseTaskTitle(String rawCleanTitle) =>
      LayersTextStyleGuide.formatConciseTaskTitle(rawCleanTitle);

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

  static const Set<String> _kMinorTitleWords = <String>{
    'a',
    'an',
    'the',
    'and',
    'or',
    'for',
    'to',
    'in',
    'on',
    'at',
    'by',
    'of',
    'with',
  };

  static const Set<String> _kTelegraphicDropWords = <String>{
    'a',
    'an',
    'the',
    'your',
    'our',
  };

  static final RegExp _hasLowercaseRegex = RegExp(r'[a-z]');
  static final RegExp _stepTrailingContextFillerRegex = RegExp(
    r'\s+(?:in\s+(?:the\s+)?(?:scene|level|editor|viewport|hierarchy|inspector)|for\s+(?:the\s+)?player|to\s+(?:the\s+)?scene)$',
    caseSensitive: false,
  );
  static final RegExp _instructionPreambleRegex = RegExp(
    r'^(?:In\s+order\s+to\s+[^,]+,\s*|To\s+(?:set\s+up|configure|implement|create|build)\s+[^,]+,\s*|In\s+this\s+step(?:,\s*you\s+will|\s+we\s+will)?\s*,?\s*|Next,\s*you\s+will\s+|First,\s*we\s+need\s+to\s+|Make\s+sure\s+to\s+)',
    caseSensitive: false,
  );
  static final RegExp _verifyPrefixRegex = RegExp(
    r'^(?:(?:Confirm|Verify|Ensure|Make\s+sure|Check)\s+that\s+|Make\s+sure\s+)',
    caseSensitive: false,
  );
  static final RegExp _verifyWhenClauseRegex = RegExp(
    r'^(?:when|after)\s+(?:you\s+|the\s+player\s+)?([^,]+),\s*(.+)$',
    caseSensitive: false,
  );
  static final RegExp _featureGoalPreambleRegex = RegExp(
    r'^(?:Goal:\s*)?(?:(?:Build|Implement|Create|Develop|Add|Deliver)\s+(?:a\s+|an\s+|the\s+)?(?:playable\s+|responsive\s+|modular\s+|tactile\s+)?[\w\s\-&/]{0,42}?(?:prototype|feature|mechanic|system|loop)\s+(?:that\s+allows\s+(?:the\s+)?player\s+to|where\s+(?:the\s+)?player\s+can|where\s+you\s+can|where\s+you|so\s+(?:the\s+)?player\s+can|to)\s+|(?:Allow|Enable)\s+(?:the\s+)?player\s+to\s+)',
    caseSensitive: false,
  );
  static final RegExp _guardLeadInPreventFromRegex = RegExp(
    r'^Prevent\s+(?:the\s+)?(.+?)\s+from\s+',
    caseSensitive: false,
  );
  static final RegExp _guardLeadInPrefixRegex = RegExp(
    r'^(?:Prevent|Ensure\s+that|Ensure|Make\s+sure\s+that|Make\s+sure|Do\s+not\s+allow)\s+(?:the\s+)?',
    caseSensitive: false,
  );

  /// Formats a step title into Telegraphic Title Case (e.g. `"CREATE THE PLAYER CHARACTERBODY2D IN THE SCENE"`
  /// -> `"Create Player CharacterBody2D"`), stripping articles/pronouns and preserving engine identifiers.
  static String formatTelegraphicStepTitle(String raw) {
    var stripped = raw
        .trim()
        .replaceFirst(_stepHeaderPrefixRegex, '')
        .replaceAll(_anyDurationTagRe, '')
        .trim();
    if (stripped.isEmpty) return raw.trim();
    stripped = stripped.replaceFirst(_stepTrailingContextFillerRegex, '').trim();
    final isMixedCase = stripped.contains(_hasLowercaseRegex);
    final words = stripped.split(_whitespaceRegex);
    final formatted = <String>[];
    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.isEmpty) continue;
      final lower = w.toLowerCase();
      if (i > 0 && _kTelegraphicDropWords.contains(lower)) {
        continue;
      }
      if (isMixedCase) {
        formatted.add(w);
        continue;
      }
      if (_kAcronymWords.contains(w.toUpperCase())) {
        formatted.add(w.toUpperCase());
        continue;
      }
      if (w.contains('_')) {
        // Handle engine prefixes like BP_ROOFRUNNER, IA_MOVE, IMC_DEFAULT
        final parts = w.split('_');
        final prefix = parts.first.toUpperCase();
        final rest = parts
            .skip(1)
            .map(
              (p) => p.isEmpty
                  ? ''
                  : p[0].toUpperCase() + p.substring(1).toLowerCase(),
            )
            .join('_');
        formatted.add('${prefix}_$rest');
        continue;
      }
      if (i > 0 && _kMinorTitleWords.contains(lower)) {
        formatted.add(lower);
      } else {
        formatted.add(
          lower.length == 1
              ? lower.toUpperCase()
              : lower[0].toUpperCase() + lower.substring(1),
        );
      }
    }
    final result = formatted.join(' ').trim();
    if (result.isEmpty) return stripped;
    return result[0].toUpperCase() + result.substring(1);
  }

  /// Formats an edge-case guard into Telegraphic Style for the 1-Line Spec Bar and Area 2 Inspector
  /// (strips `[TAG]`, verbose lead-ins like `"Prevent the ... from "`, and articles `a/an/the`).
  static String formatTelegraphicGuardChip(String raw) {
    var clean = raw.replaceFirst(_leadingBracketTagRegex, '').trim();
    if (clean.isEmpty) return raw.trim();
    final preventFromMatch = _guardLeadInPreventFromRegex.firstMatch(clean);
    if (preventFromMatch != null) {
      final subject = preventFromMatch.group(1)!.trim();
      final rest = clean.substring(preventFromMatch.end).trim();
      clean = 'Block $subject $rest';
    } else {
      clean = clean.replaceFirst(_guardLeadInPrefixRegex, '').trim();
    }
    clean = clean.replaceAll(_inlineArticlesRegex, '').replaceAll(_whitespaceRegex, ' ').trim();
    if (clean.endsWith('.')) {
      clean = clean.substring(0, clean.length - 1).trim();
    }
    if (clean.isNotEmpty) {
      clean = clean[0].toUpperCase() + clean.substring(1);
    }
    return clean.isEmpty ? raw.trim() : clean;
  }

  /// Formats a Feature Header Goal into Concise Messaging (BLUF — Bottom-Line Up Front),
  /// stripping repetitive `"Build a playable ... feature that allows the player to "` preambles.
  static String formatConciseFeatureGoal(String raw) {
    var clean = raw.trim();
    if (clean.isEmpty) return clean;
    clean = clean
        .replaceFirst(_featureGoalPreambleRegex, '')
        .replaceFirst(_progressiveGoalPreambleRegex, '')
        .trim();
    if (clean.startsWith('Goal:')) {
      clean = clean.substring(5).trim();
    }
    if (clean.isNotEmpty) {
      clean = clean[0].toUpperCase() + clean.substring(1);
    }
    return clean;
  }

  /// Formats a step instruction into Concise Messaging (1–2 direct imperative sentences).
  static String formatConciseStepInstruction(String raw) {
    var clean = raw.trim();
    if (clean.isEmpty) return clean;
    clean = clean.replaceFirst(_instructionPreambleRegex, '').trim();
    if (clean.isNotEmpty) {
      clean = clean[0].toUpperCase() + clean.substring(1);
    }
    return clean;
  }

  /// Formats a verify sentence into a direct causal `Action → Result` check.
  static String formatConciseVerifySentence(String raw) {
    var clean = raw.trim();
    if (clean.isEmpty) return clean;
    clean = clean.replaceFirst(_verifyPrefixRegex, '').trim();
    if (!clean.contains('→') && !clean.contains('->')) {
      final whenMatch = _verifyWhenClauseRegex.firstMatch(clean);
      if (whenMatch != null) {
        var action = whenMatch.group(1)!.trim();
        var result = whenMatch.group(2)!.trim();
        if (action.isNotEmpty && result.isNotEmpty) {
          action = action[0].toUpperCase() + action.substring(1);
          result = result[0].toUpperCase() + result.substring(1);
          return '$action → $result';
        }
      }
    } else if (clean.contains(' -> ')) {
      clean = clean.replaceAll(' -> ', ' → ');
    }
    if (clean.isNotEmpty) {
      clean = clean[0].toUpperCase() + clean.substring(1);
    }
    return clean;
  }

  static const Set<String> _inheritedComponentPropertyKeys = {
    'position',
    'globalposition',
    'rotation',
    'rotationdegrees',
    'scale',
    'skew',
    'transform',
    'location',
    'visible',
    'modulate',
    'selfmodulate',
    'zindex',
    'ysortenabled',
    'collisionlayer',
    'collisionmask',
    'processmode',
    'motionmode',
    'wallminslideangle',
    'floorsnaplength',
    'scenepath',
    'nodepath',
    'assetname',
    'parentclass',
  };

  /// Filters out built-in Godot Node Inspector properties (`position`, `rotation`,
  /// `scale`, `collision_layer`, etc.) so the Unified Header shows only true
  /// `@export` declared gameplay tuning variables.
  static List<
      ({
        String name,
        String value,
        String raw,
        int origIdx,
        int typeColorArgb,
      })> filterDeclaredGameplayVariables(List<String> tuningItems) {
    final result = <({
      String name,
      String value,
      String raw,
      int origIdx,
      int typeColorArgb,
    })>[];
    for (int i = 0; i < tuningItems.length; i++) {
      final raw = tuningItems[i].trim();
      if (raw.isEmpty) continue;

      String name;
      String value;
      final eqIdx = raw.indexOf('=');
      final colonIdx = raw.indexOf(':');
      if (eqIdx > 0 && (colonIdx == -1 || eqIdx < colonIdx || raw.contains('.'))) {
        name = raw.substring(0, eqIdx).trim();
        value = raw.substring(eqIdx + 1).trim();
      } else if (colonIdx > 0) {
        name = raw.substring(0, colonIdx).trim();
        value = raw.substring(colonIdx + 1).trim();
      } else {
        name = raw;
        value = '';
      }

      if (name.isEmpty) continue;

      final lowerName = name.toLowerCase();
      final tailSegment = name.split(RegExp(r'[.:]')).last.trim().toLowerCase();
      final tailToken = tailSegment.split(RegExp(r'\s+')).last.trim();
      String norm(String s) => s.replaceAll(RegExp(r'[^a-z0-9]'), '');

      final candidates = {
        norm(lowerName),
        norm(tailSegment),
        norm(tailToken),
      };
      if (candidates.any(_inheritedComponentPropertyKeys.contains)) {
        continue;
      }

      final lowerVal = value.toLowerCase();
      final int typeColorArgb;
      if (lowerVal == 'true' ||
          lowerVal == 'false' ||
          lowerName.startsWith('bool ') ||
          lowerName.endsWith(': bool') ||
          lowerName.startsWith('is_') ||
          lowerName.startsWith('can_') ||
          lowerName.startsWith('has_')) {
        typeColorArgb = 0xFFEF4444; // bool (red)
      } else if (lowerVal.startsWith('(') ||
          lowerVal.startsWith('vector') ||
          lowerVal.startsWith('color(') ||
          lowerName.contains('vector') ||
          lowerName.contains('color') ||
          lowerVal.contains('x=') ||
          lowerVal.contains('y=') ||
          lowerVal.contains('z=')) {
        typeColorArgb = 0xFFEAB308; // Vector2 / Vector3 / Color (gold)
      } else if (int.tryParse(value) != null ||
          lowerName.startsWith('int ') ||
          lowerName.endsWith(': int')) {
        typeColorArgb = 0xFF2DD4BF; // int (teal)
      } else {
        typeColorArgb = 0xFF22C55E; // float (green)
      }

      result.add((
        name: name,
        value: value,
        raw: raw,
        origIdx: i,
        typeColorArgb: typeColorArgb,
      ));
    }
    return result;
  }

  /// Lightweight LRU-style memoization cache for `TaskHowToBlueprint.resolve`
  /// so Outliner ETA rollups and Active Step Workspace renders do not re-run regexes
  /// and object allocations multiple times per frame.
  static final Map<String, ({int signature, TaskHowToBlueprint blueprint})>
      _blueprintCache = {};

  static void clearCache() => _blueprintCache.clear();

  static const String _area1Marker = '\n[[AREA1]]\n';
  static const String _area2Marker = '\n[[AREA2]]\n';
  static const String _verifyModeMarker = '\n[[VERIFY_MODE]]\n';
  static const String _stepRoleMarker = '\n[[STEP_ROLE]]\n';

  static const Set<String> _kValidStepRoles = <String>{
    'editor_setup',
    'inspector_setup',
    'script_logic',
    'wire_and_verify',
    'fix',
  };

  /// Maps raw AI/legacy `stepRole` or `dockStage` aliases onto canonical roles.
  static String normalizeStepRole(String? rawRole) {
    final sr = (rawRole ?? '').trim().toLowerCase();
    if (_kValidStepRoles.contains(sr)) return sr;
    return switch (sr) {
      'scene' || 'scene_setup' || 'node_setup' => 'editor_setup',
      'inspector' || 'input_setup' || 'properties' => 'inspector_setup',
      'code' || 'input_handling' || 'physics' || 'logic' => 'script_logic',
      'wire' ||
      'wiring_and_feel' ||
      'signal_wiring' ||
      'verify' =>
        'wire_and_verify',
      'bugfix' || 'bug' => 'fix',
      _ => '',
    };
  }

  /// Encodes optional AI-synthesized `area1Hierarchy` (Scene/Component tree),
  /// `area2Inspector` (Inspector/Details bindings), `verifyMode` (`'editor'` | `'playtest'`),
  /// and `stepRole` (`'editor_setup'` | `'inspector_setup'` | `'script_logic'` | `'wire_and_verify'` | `'fix'`)
  /// inside `Subtask.specNotes` without altering existing Hive/JSON serialization schemas.
  static String encodeThreeAreaNotes({
    required String instruction,
    String? area1Hierarchy,
    String? area2Inspector,
    String? verifyMode,
    String? stepRole,
  }) {
    final base = instruction.trim();
    final a1 = (area1Hierarchy ?? '').trim();
    final a2 = (area2Inspector ?? '').trim();
    final vm = (verifyMode ?? '').trim().toLowerCase();
    final effectiveVm = (vm == 'editor' || vm == 'playtest') ? vm : '';
    final effectiveSr = normalizeStepRole(stepRole);
    if (a1.isEmpty &&
        a2.isEmpty &&
        effectiveVm.isEmpty &&
        effectiveSr.isEmpty) {
      return base;
    }
    final sb = StringBuffer(base);
    if (a1.isNotEmpty) {
      sb.write(_area1Marker);
      sb.write(a1);
    }
    if (a2.isNotEmpty) {
      sb.write(_area2Marker);
      sb.write(a2);
    }
    if (effectiveVm.isNotEmpty) {
      sb.write(_verifyModeMarker);
      sb.write(effectiveVm);
    }
    if (effectiveSr.isNotEmpty) {
      sb.write(_stepRoleMarker);
      sb.write(effectiveSr);
    }
    return sb.toString();
  }

  /// Decodes `Subtask.specNotes` into clean natural instruction prose plus optional
  /// AI-synthesized `area1Hierarchy`, `area2Inspector`, `verifyMode`, and `stepRole`.
  /// Strips tail markers in reverse append order so raw marker text never leaks.
  static ({
    String cleanInstruction,
    String? area1Hierarchy,
    String? area2Inspector,
    String? verifyMode,
    String? stepRole,
  }) decodeThreeAreaNotes(String? rawSpecNotes) {
    if (rawSpecNotes == null || rawSpecNotes.trim().isEmpty) {
      return (
        cleanInstruction: '',
        area1Hierarchy: null,
        area2Inspector: null,
        verifyMode: null,
        stepRole: null,
      );
    }
    String working = rawSpecNotes;
    String? sr;
    final idxSr = working.indexOf(_stepRoleMarker);
    if (idxSr >= 0) {
      sr = working.substring(idxSr + _stepRoleMarker.length).trim().toLowerCase();
      working = working.substring(0, idxSr);
    }
    String? vm;
    final idxVm = working.indexOf(_verifyModeMarker);
    if (idxVm >= 0) {
      vm = working.substring(idxVm + _verifyModeMarker.length).trim().toLowerCase();
      working = working.substring(0, idxVm);
    }
    String? a2;
    final idx2 = working.indexOf(_area2Marker);
    if (idx2 >= 0) {
      a2 = working.substring(idx2 + _area2Marker.length).trim();
      working = working.substring(0, idx2);
    }
    String? a1;
    final idx1 = working.indexOf(_area1Marker);
    if (idx1 >= 0) {
      a1 = working.substring(idx1 + _area1Marker.length).trim();
      working = working.substring(0, idx1);
    }
    final normalizedSr = normalizeStepRole(sr);
    final validSr = normalizedSr.isNotEmpty ? normalizedSr : null;
    return (
      cleanInstruction: working.trim(),
      area1Hierarchy: (a1 != null && a1.isNotEmpty) ? a1 : null,
      area2Inspector: (a2 != null && a2.isNotEmpty) ? a2 : null,
      verifyMode: (vm == 'editor' || vm == 'playtest') ? vm : null,
      stepRole: validSr,
    );
  }

  /// Godot 4 Native engine label across Stage 1 and Stage 2.
  static String detectEngineLabel(String? engineHint) => 'GODOT 4';

  static String extractCleanTitle(String rawText) {
    var cleaned = rawText.replaceAll(_trailingDurationRe, '').trim();
    cleaned = cleaned.replaceFirst(_leadingTagRe, '').trim();
    return cleaned.isEmpty ? rawText.trim() : cleaned;
  }

  static String extractDurationChip(String rawText) {
    final m = _trailingDurationRe.firstMatch(rawText);
    if (m != null && m.group(1) != null) {
      return m.group(1)!.replaceAll(' ', '');
    }
    return '3h';
  }

  /// Base effort weights (in minutes) across the 6 standard steps of a 3.0h (180m) task:
  /// Step 1: 15m (Create / Open Asset)
  /// Step 2: 25m (Add Components / Hierarchy)
  /// Step 3: 15m (Place in Scene / Level)
  /// Step 4: 25m (Expose Tuning Variables)
  /// Step 5: 65m (Write Core Logic — ~1.1h)
  /// Step 6: 35m (Add Guard & Playtest)
  static const List<int> baseStepWeights180 = <int>[15, 25, 15, 25, 65, 35];

  static int extractTaskTotalMinutes(String rawText) {
    final m = _trailingDurationRe.firstMatch(rawText);
    if (m != null && m.group(1) != null) {
      final parsed = DurationHelper.parseToMinutes(m.group(1)!);
      if (parsed > 0) return parsed;
    }
    return 180; // Default 3h = 180m
  }

  static List<int> computeWeightedStepMinutes(int totalSteps, int totalTaskMinutes) {
    if (totalSteps <= 0) return const <int>[];
    final safeTotal = totalTaskMinutes > 0 ? totalTaskMinutes : 180;
    if (totalSteps == 6 && safeTotal == 180) {
      return baseStepWeights180;
    }
    final rawWeights = List<int>.generate(
      totalSteps,
      (idx) => idx < baseStepWeights180.length ? baseStepWeights180[idx] : 20,
    );
    final weightSum = rawWeights.fold<int>(0, (sum, w) => sum + w);
    if (weightSum <= 0) {
      final each = (safeTotal / totalSteps).round();
      return List<int>.filled(totalSteps, each > 0 ? each : 5);
    }
    final scaled = <int>[];
    int allocated = 0;
    for (int i = 0; i < totalSteps; i++) {
      if (i == totalSteps - 1) {
        final rem = safeTotal - allocated;
        scaled.add(rem > 0 ? rem : 5);
      } else {
        final mins = ((rawWeights[i] / weightSum) * safeTotal).round();
        final clamped = mins > 0 ? mins : 5;
        scaled.add(clamped);
        allocated += clamped;
      }
    }
    return scaled;
  }

  static String formatStepEtaLabel(int minutes) {
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes / 60.0;
    if ((hours - hours.roundToDouble()).abs() < 0.05) {
      return '${hours.round()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }

  static String formatRemainingHoursShort(int minutes) {
    if (minutes <= 0) return '0h';
    final hours = minutes / 60.0;
    if ((hours - hours.roundToDouble()).abs() < 0.05) {
      return '${hours.round()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }

  int get totalTaskMinutes =>
      subSteps.fold<int>(0, (sum, s) => sum + s.estimatedMinutes);

  int get remainingTaskMinutes => subSteps.fold<int>(
        0,
        (sum, s) => sum + (s.subtask.completed ? 0 : s.estimatedMinutes),
      );

  static String inferLayerTag(String rawText, int taskIdx) {
    final lower = rawText.toLowerCase();
    if (lower.contains('input') ||
        lower.contains('mapping') ||
        lower.contains('control') ||
        lower.contains('key') ||
        lower.contains('mouse') ||
        lower.contains('aim') ||
        lower.contains('strafe')) {
      return 'INPUT';
    }
    if (lower.contains('physic') ||
        lower.contains('tuning') ||
        lower.contains('velocity') ||
        lower.contains('force') ||
        lower.contains('speed') ||
        lower.contains('gravity') ||
        lower.contains('collision') ||
        lower.contains('raycast') ||
        lower.contains('movement')) {
      return 'PHYSICS';
    }
    if (lower.contains('visual') ||
        lower.contains('audio') ||
        lower.contains('sfx') ||
        lower.contains('vfx') ||
        lower.contains('cue') ||
        lower.contains('camera') ||
        lower.contains('fov') ||
        lower.contains('feel') ||
        lower.contains('feedback') ||
        lower.contains('anim')) {
      return 'FEEL';
    }
    if (lower.contains('hud') ||
        lower.contains('ui') ||
        lower.contains('menu') ||
        lower.contains('indicator') ||
        lower.contains('readout') ||
        lower.contains('badge')) {
      return 'UI / HUD';
    }
    return taskIdx == 0 ? 'STATE' : (taskIdx == 1 ? 'FEEL' : 'LOGIC');
  }

  static String inferWhereLocation(
    String cleanTitle,
    String layerTag, {
    String engineLabel = 'GODOT 4',
  }) {
    switch (layerTag) {
      case 'INPUT':
        return 'Script: PlayerController._unhandled_input(event)';
      case 'PHYSICS':
        return 'Script: MechanicController._physics_process(delta)';
      case 'FEEL':
        return 'Scene: FeedbackPresenter & CameraController._process(delta)';
      case 'UI / HUD':
        return 'Scene: GameHudOverlay.update_state_readout()';
      default:
        return 'Script: CoreLoopStateController._physics_process(delta)';
    }
  }

  static ({String pascalName, String snakeName}) deriveConcreteAssetName(
    String rawText,
  ) {
    final clean =
        extractCleanTitle(rawText).replaceAll(_anyDurationTagRe, ' ').trim();
    final seenLower = <String>{};
    final words = <String>[];
    for (final m in _identifierWordRegex.allMatches(clean)) {
      final w = m.group(0)!;
      final lowerW = w.toLowerCase();
      if (w.length > 1 &&
          !_kAssetNameStopWords.contains(lowerW) &&
          !_digitsOnlyRegex.hasMatch(w) &&
          !_versionTokenRegex.hasMatch(lowerW) &&
          seenLower.add(lowerW)) {
        words.add(w);
      }
    }
    final lowerClean = clean.toLowerCase();
    final isPlayerMovementCorpus = !lowerClean.contains('locomotion') &&
        !lowerClean.contains('wasd') &&
        (lowerClean.contains('player') ||
            lowerClean.contains('sprint') ||
            lowerClean.contains('slide') ||
            lowerClean.contains('dash') ||
            lowerClean.contains('movement') ||
            lowerClean.contains('character'));
    if (isPlayerMovementCorpus) {
      return (pascalName: 'PlayerCharacter', snakeName: 'player_character');
    }
    if (words.length == 1 &&
        (lowerClean.contains('locomotion') ||
            lowerClean.contains('pawn') ||
            lowerClean.contains('character')) &&
        !seenLower.contains('character')) {
      words.add('Character');
    }
    final chosen = words.isNotEmpty
        ? words.take(3).toList()
        : (lowerClean.contains('input') || lowerClean.contains('mapping')
            ? <String>['Player', 'Character']
            : <String>['Feature', 'Node']);
    final pascal = chosen
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join();
    final snake = chosen.map((w) => w.toLowerCase()).join('_');
    return (pascalName: pascal, snakeName: snake);
  }

  static final RegExp _camelOrSnakeTokenRegex = RegExp(
    r'[A-Z]+(?=[A-Z][a-z]|\d|\b)|[A-Z]?[a-z]+|\d+',
  );
  static final RegExp _assetExtRegex = RegExp(
    r'\.(?:gd|tscn|tres|h|cpp)$',
    caseSensitive: false,
  );

  /// Resolves `(pascalName, snakeName)` from an explicit `primarySharedScriptOrScene`
  /// when present, or falls back to `deriveConcreteAssetName(fallbackText)`.
  static ({String pascalName, String snakeName}) resolveAssetName({
    String? primarySharedAsset,
    required String fallbackText,
  }) {
    final raw = (primarySharedAsset ?? '').trim();
    if (raw.isNotEmpty) {
      var head = raw.split('(').first.trim();
      if (head.isEmpty) head = raw;
      head = head.split('/').last.split(r'\').last.trim();
      head = head.replaceFirst(_assetExtRegex, '').trim();
      final tokens = _camelOrSnakeTokenRegex
          .allMatches(head)
          .map((m) => m.group(0)!)
          .where((t) => t.isNotEmpty)
          .toList();
      if (tokens.isNotEmpty) {
        final pascal = tokens
            .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
            .join();
        final snake = tokens.map((w) => w.toLowerCase()).join('_');
        return (pascalName: pascal, snakeName: snake);
      }
    }
    return deriveConcreteAssetName(fallbackText);
  }

  static int _computeTaskSignature({
    required Subtask parentTask,
    required FeatureStateNode checkpointNode,
    required String? engineHint,
    required ProductionPhase effectivePhase,
  }) {
    var hash = Object.hash(
      parentTask.id,
      parentTask.text,
      parentTask.completed,
      parentTask.children.length,
      checkpointNode.id,
      checkpointNode.name,
      checkpointNode.trigger,
      checkpointNode.tuningParams.join('|'),
      checkpointNode.edgeCases.join('|'),
      checkpointNode.parameters['primarySharedScriptOrScene'] ?? '',
      engineHint ?? '',
      effectivePhase.name,
    );
    for (final c in parentTask.children) {
      hash = Object.hash(
        hash,
        c.id,
        c.text,
        c.completed,
        c.specNotes,
        c.codeSnippet,
        c.codeTargetFile,
        c.verification,
        c.codeLanguage,
      );
    }
    return hash;
  }

  /// Infers the `ProductionPhase` (`prototype`, `mvp`, `verticalSlice`, `fullProduction`, `postLaunch`)
  /// for a `FeatureStateNode` checkpoint when an explicit `phase` is not passed.
  static ProductionPhase inferCheckpointPhase(
    FeatureStateNode checkpointNode, {
    ProductionPhase? explicitPhase,
  }) {
    if (explicitPhase != null) return explicitPhase;
    final rawParamPhase = (checkpointNode.parameters['phase'] ?? '').trim();
    for (final p in ProductionPhase.values) {
      if (p.name == rawParamPhase) return p;
    }
    final ver = checkpointNode.releaseVersion.toLowerCase().trim();
    final nameLower = checkpointNode.name.toLowerCase();
    if (ver.startsWith('v1.') && ver != 'v1.0') {
      return ProductionPhase.postLaunch;
    }
    if (nameLower.contains('post-launch') ||
        nameLower.contains('live ops') ||
        nameLower.contains('patch')) {
      return ProductionPhase.postLaunch;
    }
    if (ver == 'v1.0' ||
        nameLower.contains('full production') ||
        nameLower.contains('data table') ||
        nameLower.contains('roster')) {
      return ProductionPhase.fullProduction;
    }
    if (ver == 'v0.3' ||
        nameLower.contains('vertical slice') ||
        nameLower.contains('polish')) {
      return ProductionPhase.verticalSlice;
    }
    if ((ver.isNotEmpty && ver != 'v0.1') ||
        checkpointNode.order > 0 ||
        nameLower.contains('mvp') ||
        nameLower.contains('upgrade')) {
      return ProductionPhase.mvp;
    }
    return ProductionPhase.prototype;
  }

  static List<String> extractActionClauses(String cleanTitle) {
    final rawParts = cleanTitle.split(_clauseSplitRegex);
    final clauses = <String>[];
    for (final part in rawParts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final wordCount = trimmed.split(_whitespaceRegex).length;
      if (wordCount >= 2 || clauses.isEmpty) {
        clauses.add(trimmed);
      } else if (clauses.isNotEmpty) {
        clauses[clauses.length - 1] = '${clauses.last} and $trimmed';
      }
    }
    return clauses.isEmpty ? <String>[cleanTitle] : clauses;
  }

  /// Formats a crisp 2–4 word `Guard: ...` title for the Outliner and Step Header
  /// (e.g., `[EMPTY LOADOUT GUARD] Require at least 1...` -> `Guard: Empty Loadout`)
  /// so full-sentence guard rules never overflow or wrap in the Outliner.
  static String _formatConciseGuardShortTitle(
    String rawGuard,
    String fallbackShortTitle,
  ) {
    final tagMatch = _bracketTagCaptureRegex.firstMatch(rawGuard.trim());
    if (tagMatch != null) {
      final rawTag = tagMatch.group(1)!.trim();
      final upperTag = rawTag.toUpperCase();
      if (!_kGenericGuardTags.contains(upperTag)) {
        final cleanedTag = rawTag
            .replaceFirst(_trailingGuardSuffixRegex, '')
            .trim();
        if (cleanedTag.isNotEmpty) {
          final titleCased = cleanedTag
              .split(_whitespaceOrUnderscoreRegex)
              .where((w) => w.isNotEmpty)
              .map((w) {
                if (w.toUpperCase() == 'LOS' ||
                    w.toUpperCase() == 'HUD' ||
                    w.toUpperCase() == 'UI') {
                  return w.toUpperCase();
                }
                return w
                    .split('-')
                    .map(
                      (p) => p.isEmpty
                          ? p
                          : p[0].toUpperCase() + p.substring(1).toLowerCase(),
                    )
                    .join('-');
              })
              .join(' ');
          return 'Guard: $titleCased';
        }
      }
    }
    return fallbackShortTitle;
  }

  /// Derives concrete guard variable/condition names and natural English step fields
  /// from a checkpoint edge-case guard string (eliminating raw `[... GUARD]` bracket tags
  /// in prose and generic `ValidateGuard_N()` placeholders in code).
  static ({
    String shortTitle,
    List<String> highlightTokens,
    String instruction,
    String explain,
    String code,
    String verify,
    String pitfall,
  }) deriveConcreteGuardStepSpec({
    required String rawGuard,
    required String targetAssetName,
    String engineLabel = 'GODOT 4',
    required String primaryVarName,
  }) {
    final shortGuard =
        rawGuard.replaceFirst(_leadingBracketTagRegex, '').trim();
    final lower = shortGuard.toLowerCase();

    final isResetGuard = lower.contains('reset') || lower.contains('restart');
    final flagName = isResetGuard ? 'reset_in_progress' : 'selection_locked';
    final notFlagExpr = 'not $flagName';
    final code = '+ if $flagName:\n+     return\n+ $flagName = true';
    return (
      shortTitle: _formatConciseGuardShortTitle(
        rawGuard,
        isResetGuard
            ? 'Guard: Reset Lock Check'
            : 'Guard: Duplicate Trigger Lock',
      ),
      highlightTokens: [
        notFlagExpr,
        '$flagName = true',
        flagName,
      ],
      instruction:
          'At the top of your trigger callback in $targetAssetName, check $notFlagExpr and set $flagName = true on the first activation.',
      explain:
          'Enforces "$shortGuard" so rapid double-clicks or duplicate triggers cannot fire the action twice.',
      code: code,
      verify:
          'Trigger the action rapidly in Play mode (F5/F6) and confirm $flagName blocks duplicate activations so only 1 trigger runs.',
      pitfall:
          'Set $flagName = true immediately on the first frame before yielding with await.',
    );
  }

  /// Returns all concrete guard highlight tokens across `edgeItems` for semantic syntax highlighting.
  static List<String> extractGuardHighlightTokens(List<String> edgeItems) {
    final tokens = Set<String>.from(_kDefaultGuardTokens);
    for (final rawGuard in edgeItems) {
      final trimmed = rawGuard.trim();
      if (trimmed.isNotEmpty) {
        tokens.add(trimmed);
        final stripped = trimmed.replaceFirst(_leadingBracketTagRegex, '').trim();
        if (stripped.length >= 6) {
          tokens.add(stripped);
        }
      }
    }
    return tokens.toList();
  }

  /// Dynamically resolves `parentTask.children` into `1..N` atomic Godot 4 Native Handbook sub-steps
  /// (`Step X.1` through `Step X.N`) across `Scene Tree`, `Inspector`, `Input Map`, `GDScript (.gd)`, and `Signals`.
  static TaskHowToBlueprint resolve({
    required Subtask parentTask,
    required int taskIndex,
    required FeatureStateNode checkpointNode,
    String? engineHint,
    ProductionPhase? phase,
  }) {
    final effectivePhase = inferCheckpointPhase(
      checkpointNode,
      explicitPhase: phase,
    );
    final cacheKey =
        '${checkpointNode.id}_${parentTask.id}_${taskIndex}_${engineHint ?? ''}_${effectivePhase.name}';
    if (parentTask.children.isNotEmpty) {
      final sig = _computeTaskSignature(
        parentTask: parentTask,
        checkpointNode: checkpointNode,
        engineHint: engineHint,
        effectivePhase: effectivePhase,
      );
      final cached = _blueprintCache[cacheKey];
      if (cached != null && cached.signature == sig) {
        return cached.blueprint;
      }
    }

    final taskNum = taskIndex + 1;
    final numLabel = taskNum.toString().padLeft(2, '0');
    final cleanTitle = extractCleanTitle(parentTask.text);
    final durationChip = extractDurationChip(parentTask.text);
    final layerTag = inferLayerTag(parentTask.text, taskIndex);
    final engineLabel = detectEngineLabel(engineHint);
    final whereLocation = inferWhereLocation(
      cleanTitle,
      layerTag,
      engineLabel: engineLabel,
    );

    final assetSource = checkpointNode.checklist.isNotEmpty
        ? checkpointNode.checklist.first.text
        : cleanTitle;
    final asset = resolveAssetName(
      primarySharedAsset:
          checkpointNode.parameters['primarySharedScriptOrScene'],
      fallbackText: '$assetSource ${checkpointNode.name}',
    );
    final pascalAsset = asset.pascalName;
    final snakeAsset = asset.snakeName;

    final lowerCategoryCorpus =
        '$cleanTitle ${checkpointNode.name}'.toLowerCase();
    final effectiveCategory = (layerTag == 'UI / HUD' ||
            lowerCategoryCorpus.contains('hud') ||
            lowerCategoryCorpus.contains('ui ') ||
            lowerCategoryCorpus.contains('menu') ||
            lowerCategoryCorpus.contains('scoreboard') ||
            lowerCategoryCorpus.contains('overlay'))
        ? 'ui'
        : (lowerCategoryCorpus.contains('weapon') ||
                lowerCategoryCorpus.contains('gun') ||
                lowerCategoryCorpus.contains('turret') ||
                lowerCategoryCorpus.contains('shoot') ||
                lowerCategoryCorpus.contains('fire') ||
                lowerCategoryCorpus.contains('attack') ||
                lowerCategoryCorpus.contains('combat') ||
                lowerCategoryCorpus.contains('projectile') ||
                lowerCategoryCorpus.contains('sword') ||
                lowerCategoryCorpus.contains('melee'))
            ? 'combat'
            : (lowerCategoryCorpus.contains('locomotion') ||
                    lowerCategoryCorpus.contains('pawn') ||
                    lowerCategoryCorpus.contains('character') ||
                    lowerCategoryCorpus.contains('parkour') ||
                    lowerCategoryCorpus.contains('sprint') ||
                    lowerCategoryCorpus.contains('slide') ||
                    lowerCategoryCorpus.contains('dash') ||
                    lowerCategoryCorpus.contains('movement') ||
                    lowerCategoryCorpus.contains('traversal') ||
                    lowerCategoryCorpus.contains('first person') ||
                    lowerCategoryCorpus.contains('third person'))
                ? 'character'
                : 'core';
    final effectiveTuningParams = checkpointNode.tuningParams;
    final effectiveEdgeCases = checkpointNode.edgeCases;

    final primaryVar = effectiveTuningParams.isNotEmpty
        ? effectiveTuningParams[taskIndex % effectiveTuningParams.length]
        : 'responseTime: 0.12 s';
    final primaryVarName = primaryVar.split(':').first.trim();
    final primaryGuard = effectiveEdgeCases.isNotEmpty
        ? effectiveEdgeCases[taskIndex % effectiveEdgeCases.length]
        : '[STATE GUARD] Prevent duplicate trigger while active';
    final lowerTaskTitle = cleanTitle.toLowerCase();
    final firstTaskText = checkpointNode.checklist.isNotEmpty
        ? extractCleanTitle(checkpointNode.checklist.first.text).toLowerCase()
        : '';
    final isFirstTaskPureInput = (firstTaskText.contains('input') ||
            firstTaskText.contains('mapping')) &&
        !firstTaskText.contains('character') &&
        !firstTaskText.contains('pawn') &&
        !firstTaskText.contains('actor');
    final isCurrentTaskPureInput = (lowerTaskTitle.contains('input') ||
            lowerTaskTitle.contains('mapping')) &&
        !lowerTaskTitle.contains('character') &&
        !lowerTaskTitle.contains('pawn') &&
        !lowerTaskTitle.contains('actor');
    final isFoundationTask =
        (taskIndex == 0 && !isCurrentTaskPureInput) ||
        (taskIndex == 1 && isFirstTaskPureInput);
    final isInputMappingTask = !isFoundationTask &&
        (lowerTaskTitle.contains('input') ||
            lowerTaskTitle.contains('mapping'));
    final isPhysicsTuningTask = !isFoundationTask &&
        !isInputMappingTask &&
        !lowerTaskTitle.contains('wasd') &&
        (lowerTaskTitle.contains('tuning') ||
            lowerTaskTitle.contains('gravity') ||
            lowerTaskTitle.contains('friction') ||
            lowerTaskTitle.contains('velocity') ||
            lowerTaskTitle.contains('blend') ||
            lowerTaskTitle.contains('animation') ||
            lowerTaskTitle.contains('capsule') ||
            lowerTaskTitle.contains('physics') ||
            (effectiveCategory == 'character' && taskIndex >= 2));
    final isStateLogicTask = !isFoundationTask &&
        !isInputMappingTask &&
        !isPhysicsTuningTask &&
        taskIndex == 1;

    ({
      String stepHeader,
      String shortTitle,
      String instruction,
      String verify,
      String path,
      String code,
      String explain,
    }) buildAtomicStepSpec(int stepIdx) {
      // =======================================================================
      // DEFAULT: GODOT 4 (Strictly GDScript .gd + Scene .tscn Hierarchy)
      // =======================================================================
      switch (stepIdx) {
        case 0:
          return (
            stepHeader: isFoundationTask
                ? 'STEP $taskNum.1 · CREATE $snakeAsset.tscn & .gd SCRIPT'
                : (isInputMappingTask
                    ? 'STEP $taskNum.1 · CONFIGURE INPUT MAP ACTIONS IN $snakeAsset.gd'
                    : (isPhysicsTuningTask
                        ? 'STEP $taskNum.1 · CONFIGURE PHYSICS PROPERTIES IN $snakeAsset.gd'
                        : (isStateLogicTask
                            ? 'STEP $taskNum.1 · DEFINE STATE ENUM IN $snakeAsset.gd'
                            : 'STEP $taskNum.1 · BIND PLAYER INTERACTION INPUT IN $snakeAsset.gd'))),
            shortTitle: isFoundationTask
                ? 'Create $snakeAsset.tscn'
                : (isInputMappingTask
                    ? 'Configure Input Map Actions'
                    : (isPhysicsTuningTask
                        ? 'Configure Physics Properties'
                        : (isStateLogicTask
                            ? 'Define State Enum'
                            : 'Bind Player Interaction Input'))),
            instruction: isFoundationTask
                ? 'In the Scene dock (top-left), click + Other Node → select Node2D / CharacterBody2D → name it "$pascalAsset". Save the scene as res://scenes/$snakeAsset.tscn, then click the Attach Script icon to create res://scripts/$snakeAsset.gd.'
                : (isInputMappingTask
                    ? 'Open Project → Project Settings → Input Map to bind move_left, move_right, move_up, move_down, then open res://scripts/$snakeAsset.gd (created in Task 01).'
                    : (isPhysicsTuningTask
                        ? 'Open res://scenes/$snakeAsset.tscn and res://scripts/$snakeAsset.gd (created in Task 01) to configure movement and physics parameters.'
                        : (isStateLogicTask
                            ? 'In the FileSystem dock, open res://scripts/$snakeAsset.gd and declare the state enum and active state variable for "$cleanTitle".'
                            : 'Open res://scripts/$snakeAsset.gd and bind the player interaction input action for "$cleanTitle".'))),
            verify: isFoundationTask
                ? '$pascalAsset appears in the Scene tree with a scroll icon next to it, and $snakeAsset.gd opens in the Script editor.'
                : '$snakeAsset.gd is open in the central Script workspace.',
            path: 'FileSystem → res://scripts/$snakeAsset.gd',
            code: 'extends CharacterBody2D\nclass_name $pascalAsset\n\nvar is_active: bool = false',
            explain: 'In Godot 4, every reusable game object is a Scene (.tscn) with a GDScript (.gd) attached to its root node.',
          );
        case 1:
          return (
            stepHeader: isFoundationTask
                ? 'STEP $taskNum.2 · ADD VISUAL & COLLISION CHILD NODES'
                : (isInputMappingTask
                    ? 'STEP $taskNum.2 · READ INPUT.GET_VECTOR() IN $snakeAsset.gd'
                    : (isPhysicsTuningTask
                        ? 'STEP $taskNum.2 · CONFIGURE ACCELERATION, FRICTION & GRAVITY'
                        : (isStateLogicTask
                            ? 'STEP $taskNum.2 · BUILD SET_STATE() TRANSITION FUNCTION'
                            : 'STEP $taskNum.2 · CAST RAYCAST2D / AREA2D QUERY'))),
            shortTitle: isFoundationTask
                ? 'Attach CollisionShape2D'
                : (isInputMappingTask
                    ? 'Read Input.get_vector()'
                    : (isPhysicsTuningTask
                        ? 'Configure Velocity & Gravity'
                        : (isStateLogicTask
                            ? 'Build State Transition Function'
                            : 'Cast Interaction RayCast2D'))),
            instruction: isFoundationTask
                ? 'Right-click the root "$pascalAsset" node in the Scene dock → + Add Child Node → add a Sprite2D (or ColorRect) named "Visual" and an Area2D with a CollisionShape2D (RectangleShape2D) named "HitBox".'
                : (isInputMappingTask
                    ? 'In $snakeAsset.gd, read the 2D input direction vector using Input.get_vector("move_left", "move_right", "move_up", "move_down").'
                    : (isPhysicsTuningTask
                        ? 'In $snakeAsset.gd, interpolate velocity toward target speed using move_toward and $primaryVarName.'
                        : (isStateLogicTask
                            ? 'In $snakeAsset.gd, add func set_mechanic_state(new_state: int) -> void: to validate and update the active state.'
                            : 'Use a RayCast2D / Area2D overlap check in $snakeAsset.gd to detect targeted $pascalAsset instances.'))),
            verify:
                'The 2D Viewport shows your visible shape surrounded by a light-blue rectangle collision outline (no yellow warning triangle).',
            path: 'Scene Dock (Top-Left) → $pascalAsset Hierarchy',
            code: isFoundationTask
                ? (effectiveCategory == 'ui'
                    ? '| Node / Category | Property | Value |\n| --- | --- | --- |\n| FollowCamera (Camera2D) | Position Smoothing | true |\n| HudCanvas (CanvasLayer) | Layer | 1 |\n| StatusLabel (Label) | Text | Ready |'
                    : '| Node / Category | Property | Value |\n| --- | --- | --- |\n| Visual (Sprite2D) | Scale | (1.0, 1.0) |\n| HitBox (Area2D) | Monitoring | true |\n| CollisionShape2D | Shape | RectangleShape2D |')
                : (isInputMappingTask
                    ? 'var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")'
                    : (isPhysicsTuningTask
                        ? 'velocity = velocity.move_toward(input_dir * $primaryVarName, $primaryVarName * delta)'
                        : 'func set_mechanic_state(new_state: int) -> void:\n    current_state = new_state')),
            explain: 'Sprite2D/ColorRect makes the object visible on screen, while Area2D + CollisionShape2D lets Godot detect overlaps and clicks.',
          );
        case 2:
          return (
            stepHeader: isFoundationTask
                ? 'STEP $taskNum.3 · INSTANCE SCENE IN MAIN LEVEL'
                : (isInputMappingTask
                    ? 'STEP $taskNum.3 · WIRE INPUT DIRECTION TO VELOCITY IN $snakeAsset.gd'
                    : (isPhysicsTuningTask
                        ? 'STEP $taskNum.3 · CALL MOVE_AND_SLIDE() WITH PHYSICS TUNING'
                        : (isStateLogicTask
                            ? 'STEP $taskNum.3 · SWAP MODULATE / VISUAL ON STATE CHANGE'
                            : 'STEP $taskNum.3 · CALL TRIGGER ON HIT $pascalAsset'))),
            shortTitle: isFoundationTask
                ? 'Instance in Main Scene'
                : (isInputMappingTask
                    ? 'Wire Input to Velocity'
                    : (isPhysicsTuningTask
                        ? 'Call move_and_slide()'
                        : (isStateLogicTask
                            ? 'Swap Visual Color on State Change'
                            : 'Call Interact Trigger on Hit Node'))),
            instruction: isFoundationTask
                ? 'Press Ctrl+S to save $snakeAsset.tscn, switch to your Main level scene tab, and click the Chain-Link icon ("Instantiate Child Scene") to drop $snakeAsset.tscn into the level at (0, 0).'
                : (isInputMappingTask
                    ? 'Assign velocity = input_dir * $primaryVarName inside $snakeAsset.gd so directional input drives $pascalAsset.'
                    : (isPhysicsTuningTask
                        ? 'Call move_and_slide() at the end of _physics_process(delta) in $snakeAsset.gd so collisions and floor slopes resolve cleanly.'
                        : (isStateLogicTask
                            ? 'Inside set_mechanic_state(), update \$Visual.modulate so each state of $pascalAsset has a distinct color on screen.'
                            : 'When the RayCast2D / Area2D hits $pascalAsset, call target.set_mechanic_state() to trigger the transition.'))),
            verify:
                '$pascalAsset appears in the Main scene tree with a small movie-clapper / chain icon next to it.',
            path: 'Main Scene Tab → Instantiate Child Scene (Ctrl+Shift+A)',
            code: isFoundationTask
                ? '| Node (Type) | Property | Value |\n| --- | --- | --- |\n| $pascalAsset ($snakeAsset.tscn) | Transform > Position | (0, 0) |\n| $pascalAsset ($snakeAsset.tscn) | Visible | true |'
                : (isInputMappingTask
                    ? 'velocity = input_dir * $primaryVarName'
                    : (isPhysicsTuningTask
                        ? 'move_and_slide()'
                        : (isStateLogicTask
                            ? '\$Visual.modulate = Color.CYAN if current_state > 0 else Color.WHITE'
                            : 'if ray.is_colliding() and ray.get_collider() == target:\n    target.set_mechanic_state(1)'))),
            explain: 'Instantiating places a live copy of your scene inside the game level so you can see and test it when pressing Play.',
          );
        case 3:
          return (
            stepHeader: 'STEP $taskNum.4 · ADD @export TUNING VARIABLES IN GDSCRIPT',
            shortTitle: isFoundationTask
                ? 'Add @export var $primaryVarName'
                : (isStateLogicTask
                    ? 'Bind $primaryVarName to Transition Speed'
                    : 'Add Target Hover Highlight Cue'),
            instruction:
                'At the top of $snakeAsset.gd, add @export var $primaryVarName: float = 1.0 so you can tune $primaryVarName directly in the right-hand Inspector dock.',
            verify:
                'Selecting $pascalAsset in the Scene tree displays $primaryVarName as an editable field at the top of the Inspector dock.',
            path: 'res://scripts/$snakeAsset.gd (@export)',
            code: '@export var $primaryVarName: float = 1.0 # $primaryVar\n@export var can_trigger: bool = true\nvar current_val: float = 0.0',
            explain: '@export exposes a GDScript variable in the Godot Inspector dock so you can tweak $primaryVarName live without editing code.',
          );
        case 4:
          return (
            stepHeader: 'STEP $taskNum.5 · IMPLEMENT _physics_process(delta) LOGIC',
            shortTitle: isFoundationTask
                ? 'Initialize Default Node State'
                : (isStateLogicTask
                    ? 'Step State with Interpolation Logic'
                    : 'Add Cooldown Timer'),
            instruction:
                'Inside $snakeAsset.gd, add func _physics_process(delta: float) -> void: to check Input.is_action_pressed("primary_action") and step the value using move_toward and $primaryVarName.',
            verify:
                'Triggering $pascalAsset in the scene steps the active value smoothly using $primaryVarName.',
            path: 'res://scripts/$snakeAsset.gd :: _physics_process(delta)',
            code: 'func _physics_process(delta: float) -> void:\n    if Input.is_action_pressed("primary_action") and can_trigger:\n        is_active = true\n        current_val = move_toward(current_val, target_val, $primaryVarName * delta)',
            explain: '_physics_process(delta) runs 60 times per second in sync with physics, and move_toward smoothly transitions values without overshooting.',
          );
        default:
          return (
            stepHeader: isFoundationTask
                ? 'STEP $taskNum.6 · SAVE & VERIFY SCENE IN VIEWPORT'
                : (isStateLogicTask
                    ? 'STEP $taskNum.6 · ADD INVALID-STATE TRANSITION GUARD'
                    : 'STEP $taskNum.6 · PLAYTEST FULL LOOP IN VIEWPORT (F5)'),
            shortTitle: isFoundationTask
                ? 'Verify Scene in Viewport'
                : (isStateLogicTask
                    ? 'Add Invalid-State Transition Guard'
                    : 'Playtest Full Loop in Viewport (F5)'),
            instruction:
                'Add a guard check at the top of _physics_process to enforce $primaryGuard, add print("$cleanTitle Active!"), and press F5 (or the top-right Play button) to test.',
            verify:
                'The game window launches and triggering the action prints "$cleanTitle Active!" in the bottom Output panel.',
            path: 'Top-Right Toolbar → Play Scene (F6) / Play Project (F5)',
            code: 'if not can_trigger or cooldown_timer > 0.0:\n    return # Guard: $primaryGuard\nprint("$cleanTitle Active!")',
            explain: 'The early-return guard stops the function immediately if the mechanic is blocked or on cooldown, preventing state lockups.',
          );
      }
    }

    final totalTaskMinutes = extractTaskTotalMinutes(parentTask.text);
    final clauses = extractActionClauses(cleanTitle);
    final lowerTitle = cleanTitle.toLowerCase();

    final targetAssetName = '$snakeAsset.tscn';

    final phaseFocusNote = switch (effectivePhase) {
      ProductionPhase.prototype =>
        'Greybox foundation pass: prove raw controls, collision, and immediate feel before adding polish.',
      ProductionPhase.mvp =>
        'MVP delta upgrade: extend your existing v0.1 $targetAssetName node and script with full loop state transitions and cooldowns.',
      ProductionPhase.verticalSlice =>
        'Vertical Slice polish pass: bind production meshes/sprites, SFX/VFX particle cues, camera shake/hit-stop, and HUD feedback on $targetAssetName.',
      ProductionPhase.fullProduction =>
        'Full Production scaling pass: connect data-driven Resource / ScriptableObject / DataTable rosters and save/load state serialization to $targetAssetName.',
      ProductionPhase.postLaunch =>
        'Post-Launch Live Ops pass: apply non-breaking tuning balance updates, content entries, and regression guards while preserving v1.0 save compatibility.',
    };
    final phaseBadgeChip = switch (effectivePhase) {
      ProductionPhase.prototype => 'Phase: 01 Prototype',
      ProductionPhase.mvp => 'Phase: 02 MVP Delta',
      ProductionPhase.verticalSlice => 'Phase: 03 Vertical Slice Polish',
      ProductionPhase.fullProduction => 'Phase: 04 Full Production Data',
      ProductionPhase.postLaunch => 'Phase: 05 Post-Launch Live Ops',
    };

    ({
      String explain,
      String primaryChip,
      String pitfall,
    }) buildPhaseSpecContext(int phaseIdx) {
      switch (phaseIdx) {
        case 0:
          return (
            explain:
                '$phaseFocusNote Every step in this task builds inside $targetAssetName so ${checkpointNode.cleanStageTitle} stays modular and reusable across the level.',
            primaryChip: 'Asset: $targetAssetName',
            pitfall:
                'Save the scene in res://scenes/ before attaching the script so node paths stay clean.',
          );
        case 1:
          return (
            explain:
                '$phaseFocusNote Gives $targetAssetName both its visible shape and the collision trigger sensor needed for core logic.',
            primaryChip: 'Asset: $targetAssetName',
            pitfall:
                'Assign a RectangleShape2D or CapsuleShape2D resource inside CollisionShape2D to clear the yellow scene warning icon.',
          );
        case 2:
          return (
            explain:
                '$phaseFocusNote Places a live $targetAssetName instance in the level so you can test "${checkpointNode.playtestCondition}" on screen.',
            primaryChip: 'Instance: $targetAssetName',
            pitfall:
                'Use the Chain-Link icon (Ctrl+Shift+A) to instantiate $targetAssetName rather than copying raw nodes.',
          );
        case 3:
          return (
            explain:
                '$phaseFocusNote Exposes $primaryVarName on $targetAssetName so you can tune gameplay feel live in the Inspector without editing code.',
            primaryChip: 'Spec Param: $primaryVar',
            pitfall:
                'Save the script (Ctrl+S) after adding @export var $primaryVarName so the Inspector dock refreshes.',
          );
        case 4:
          return (
            explain:
                '$phaseFocusNote Connects player trigger input on $targetAssetName to $primaryVarName so the active state updates smoothly every frame.',
            primaryChip: 'Drives: $primaryVar',
            pitfall:
                'Multiply $primaryVarName by delta inside _physics_process(delta) for frame-rate independent motion.',
          );
        default:
          return (
            explain:
                '$phaseFocusNote Enforces $primaryGuard on $targetAssetName and completes playable verification for "${checkpointNode.cleanStageTitle}".',
            primaryChip: 'Guard: $primaryGuard',
            pitfall:
                'Place the guard check at the very top of your function so blocked or cooldown inputs exit immediately ($primaryGuard).',
          );
      }
    }

    // Build the dynamic sequence of step specifications (can scale from 3 steps to 10+ steps)
    final dynamicSpecs = <({
      String stepHeader,
      String shortTitle,
      String instruction,
      String verify,
      String path,
      String code,
      String explain,
      String primaryChip,
      String pitfall,
    })>[];

    void addPhaseStep(int phaseIdx) {
      final rawSpec = buildAtomicStepSpec(phaseIdx);
      final rawCtx = buildPhaseSpecContext(phaseIdx);
      if (phaseIdx == 5) {
        final guardSpec = deriveConcreteGuardStepSpec(
          rawGuard: primaryGuard,
          targetAssetName: targetAssetName,
          engineLabel: engineLabel,
          primaryVarName: primaryVarName,
        );
        dynamicSpecs.add((
          stepHeader:
              'STEP $taskNum.${dynamicSpecs.length + 1} · ${guardSpec.shortTitle.toUpperCase()}',
          shortTitle: guardSpec.shortTitle,
          instruction: guardSpec.instruction,
          verify: guardSpec.verify,
          path: rawSpec.path,
          code: guardSpec.code,
          explain: guardSpec.explain,
          primaryChip: rawCtx.primaryChip,
          pitfall: guardSpec.pitfall,
        ));
        return;
      }
      dynamicSpecs.add((
        stepHeader: rawSpec.stepHeader,
        shortTitle: rawSpec.shortTitle,
        instruction: rawSpec.instruction,
        verify: rawSpec.verify,
        path: rawSpec.path,
        code: rawSpec.code,
        explain: rawCtx.explain,
        primaryChip: rawCtx.primaryChip,
        pitfall: rawCtx.pitfall,
      ));
    }

    final isCompactGuardTask = totalTaskMinutes <= 60 &&
        clauses.length <= 2 &&
        (lowerTitle.startsWith('verify ') ||
            lowerTitle.startsWith('enforce ') ||
            lowerTitle.contains('guard') ||
            lowerTitle.contains('interrupt') ||
            lowerTitle.contains('buffer') ||
            lowerTitle.contains('clamp'));

    final isCompactFeelOrUiTask = !isCompactGuardTask &&
        totalTaskMinutes <= 60 &&
        clauses.length <= 2 &&
        (layerTag == 'FEEL' ||
            layerTag == 'UI / HUD' ||
            lowerTitle.startsWith('hook up ') ||
            lowerTitle.startsWith('wire ') ||
            lowerTitle.startsWith('render ') ||
            lowerTitle.startsWith('trigger ') ||
            lowerTitle.startsWith('spawn '));

    final isSingleClauseExtensionTask = !isFoundationTask &&
        !isCompactGuardTask &&
        !isCompactFeelOrUiTask &&
        totalTaskMinutes <= 120 &&
        clauses.length <= 1;

    if (isCompactGuardTask) {
      // Compact 3-step guard/verification flow
      addPhaseStep(0);
      addPhaseStep(3);
      addPhaseStep(5);
    } else if (isCompactFeelOrUiTask) {
      // Compact 4-step feel/UI cue flow
      addPhaseStep(0);
      addPhaseStep(2);
      addPhaseStep(4);
      addPhaseStep(5);
    } else if (isSingleClauseExtensionTask) {
      // Focused 5-step extension flow
      addPhaseStep(0);
      addPhaseStep(1);
      addPhaseStep(2);
      addPhaseStep(3);
      addPhaseStep(5);
    } else {
      // Core foundation or multi-clause mechanic flow (starts with phases 0..4, expands dynamically for extra clauses/params/guards, ends with phase 5)
      addPhaseStep(0);
      addPhaseStep(1);
      addPhaseStep(2);
      addPhaseStep(3);
      addPhaseStep(4);

      // 1. Add a dedicated step for every additional action clause beyond the first 2
      for (int cIdx = 2; cIdx < clauses.length; cIdx++) {
        final clauseText = clauses[cIdx];
        final clauseIdent = clauseText
            .toLowerCase()
            .replaceAll(_nonLowerAlnumRegex, '_')
            .replaceAll(_trimUnderscoresRegex, '');
        final safeMethod = clauseIdent.isEmpty ? 'step_${cIdx + 1}' : clauseIdent;
        dynamicSpecs.add((
          stepHeader: 'STEP $taskNum.${dynamicSpecs.length + 1} · IMPLEMENT ${clauseText.toUpperCase()}',
          shortTitle: 'Implement $clauseText',
          instruction:
              'In $targetAssetName, add the dedicated handler for "$clauseText" and connect it to the active state loop.',
          verify:
              'Triggering "$clauseText" in the editor updates $targetAssetName state with zero errors.',
          path: whereLocation,
          code: 'func _execute_$safeMethod(delta: float) -> void:\n    # Clause: $clauseText\n    apply_state_delta($primaryVarName * delta)',
          explain:
              'Isolating "$clauseText" into its own step keeps complex multi-part mechanics easy to test and debug.',
          primaryChip: 'Clause: $clauseText',
          pitfall:
              'Verify "$clauseText" only runs when $targetAssetName is in a valid active state.',
        ));
      }

      // 2. When a task is multi-clause (>= 3 clauses) or heavy (> 180m), also emit dedicated steps for each extra tuning parameter and guard
      final expandSpecItems = clauses.length >= 3 || totalTaskMinutes > 180;
      if (expandSpecItems) {
        for (int tIdx = 1; tIdx < effectiveTuningParams.length; tIdx++) {
          final extraTune = effectiveTuningParams[tIdx];
          final extraVarName = extraTune
              .split(':')
              .first
              .trim()
              .replaceAll(_nonIdentCharRegex, '_');
          dynamicSpecs.add((
            stepHeader: 'STEP $taskNum.${dynamicSpecs.length + 1} · WIRE TUNING PARAMETER ${extraVarName.toUpperCase()}',
            shortTitle: 'Wire Tuning: $extraVarName',
            instruction:
                'Expose $extraVarName on $targetAssetName and pass $extraVarName into the active mechanic calculation.',
            verify:
                'Select $targetAssetName in the editor and confirm $extraVarName updates the active behavior live in Play mode.',
            path: whereLocation,
            code: '+ @export var $extraVarName: float = 1.0 # $extraTune',
            explain:
                'Connects $extraVarName directly to $targetAssetName so you can balance gameplay feel live.',
            primaryChip: 'Spec Param: $extraTune',
            pitfall:
                'Clamp $extraVarName > 0 so zero or negative inspector inputs cannot divide by zero.',
          ));
        }

        for (int gIdx = 1; gIdx < effectiveEdgeCases.length; gIdx++) {
          final extraGuard = effectiveEdgeCases[gIdx];
          final guardSpec = deriveConcreteGuardStepSpec(
            rawGuard: extraGuard,
            targetAssetName: targetAssetName,
            engineLabel: engineLabel,
            primaryVarName: primaryVarName,
          );
          dynamicSpecs.add((
            stepHeader:
                'STEP $taskNum.${dynamicSpecs.length + 1} · ${guardSpec.shortTitle.toUpperCase()}',
            shortTitle: guardSpec.shortTitle,
            instruction: guardSpec.instruction,
            verify: guardSpec.verify,
            path: whereLocation,
            code: guardSpec.code,
            explain: guardSpec.explain,
            primaryChip: 'Guard: $extraGuard',
            pitfall: guardSpec.pitfall,
          ));
        }
      }

      addPhaseStep(5);
    }

    // Normalize step numbering headers ("STEP X.1", "STEP X.2", ... "STEP X.N") across all dynamicSpecs
    for (int idx = 0; idx < dynamicSpecs.length; idx++) {
      final raw = dynamicSpecs[idx];
      final suffix = raw.stepHeader.replaceFirst(_stepHeaderPrefixRegex, '');
      dynamicSpecs[idx] = (
        stepHeader: 'STEP $taskNum.${idx + 1} · $suffix',
        shortTitle: raw.shortTitle,
        instruction: raw.instruction,
        verify: raw.verify,
        path: raw.path,
        code: raw.code,
        explain: raw.explain,
        primaryChip: raw.primaryChip,
        pitfall: raw.pitfall,
      );
    }

    final hasStaleEconomyOrGuardSteps = parentTask.children.any(
      (c) =>
          c.codeTargetFile != 'custom_snippet' &&
          ((c.codeSnippet ?? '').contains('ValidateGuard_') ||
              (c.codeSnippet ?? '').contains('_validate_guard_') ||
              (c.codeSnippet ?? '').contains('!IsBoundaryBlocked')),
    );
    if ((parentTask.children.isEmpty || hasStaleEconomyOrGuardSteps) &&
        !parentTask.children.any((c) => c.codeTargetFile == 'custom_snippet')) {
      final isParentCompleted = parentTask.completed;
      parentTask.children = [
        for (int sIdx = 0; sIdx < dynamicSpecs.length; sIdx++)
          Subtask(
            id: '${parentTask.id}_sub_${sIdx + 1}',
            text: dynamicSpecs[sIdx].stepHeader,
            specNotes: dynamicSpecs[sIdx].instruction,
            codeSnippet: dynamicSpecs[sIdx].code,
            completed: isParentCompleted,
          ),
      ];
    }

    final stepMinutesList = computeWeightedStepMinutes(
      parentTask.children.length,
      totalTaskMinutes,
    );

    final resolvedSubs = <TaskHowToSubStep>[];
    for (int i = 0; i < parentTask.children.length; i++) {
      final child = parentTask.children[i];
      final isCustomSnippet = child.codeTargetFile == 'custom_snippet';
      final hasDynamicSpec = i < dynamicSpecs.length;
      final spec = hasDynamicSpec ? dynamicSpecs[i] : dynamicSpecs.last;
      final stepMins = i < stepMinutesList.length ? stepMinutesList[i] : 20;
      final stepEta = formatStepEtaLabel(stepMins);
      final rawLabel = child.text.trim();
      final stepLabel = isCustomSnippet
          ? (rawLabel.toUpperCase().startsWith('STEP ')
              ? rawLabel
              : 'STEP $taskNum.${i + 1} · ${rawLabel.toUpperCase()}')
          : (hasDynamicSpec
              ? spec.stepHeader
              : 'STEP $taskNum.${i + 1} · ${rawLabel.toUpperCase()}');
      final decodedNotes = decodeThreeAreaNotes(child.specNotes);
      final rawInstruction = isCustomSnippet &&
              decodedNotes.cleanInstruction.isNotEmpty
          ? decodedNotes.cleanInstruction
          : (hasDynamicSpec
              ? spec.instruction
              : (decodedNotes.cleanInstruction.isNotEmpty
                  ? decodedNotes.cleanInstruction
                  : 'Implement and verify "$rawLabel" inside $whereLocation.'));
      final instruction = formatConciseStepInstruction(rawInstruction);
      final rawResolvedCode = isCustomSnippet &&
              child.codeSnippet != null &&
              child.codeSnippet!.trim().isNotEmpty
          ? child.codeSnippet!.trim()
          : (hasDynamicSpec
              ? spec.code
              : (child.codeSnippet != null && child.codeSnippet!.trim().isNotEmpty
                  ? child.codeSnippet!.trim()
                  : '// Step $taskNum.${i + 1}: $rawLabel\nexecute_step_${taskNum}_${i + 1}($primaryVarName)'));
      final code = rawResolvedCode;
      final shortTitle = (!isCustomSnippet && hasDynamicSpec)
          ? spec.shortTitle
          : formatTelegraphicStepTitle(rawLabel);

      String nextStepTitle = 'Verify Checkpoint & Continue';
      if (i + 1 < parentTask.children.length) {
        final nextChild = parentTask.children[i + 1];
        final nextCustom = nextChild.codeTargetFile == 'custom_snippet';
        nextStepTitle = (!nextCustom && i + 1 < dynamicSpecs.length)
            ? dynamicSpecs[i + 1].shortTitle
            : formatTelegraphicStepTitle(nextChild.text);
      }

      final isLastStep = i == parentTask.children.length - 1;
      final chips = <String>[
        phaseBadgeChip,
        spec.primaryChip,
        isLastStep
            ? 'Goal: ${checkpointNode.cleanStageTitle}'
            : 'Next: $nextStepTitle',
      ];

      final customVerify = child.verification?.trim() ?? '';
      final customPath = child.codeLanguage?.trim() ?? '';

      if (!isCustomSnippet && hasDynamicSpec) {
        child.text = spec.stepHeader;
        child.specNotes = spec.instruction;
        child.codeSnippet = spec.code;
      }

      resolvedSubs.add(
        TaskHowToSubStep(
          subtask: child,
          stepNumberLabel: stepLabel,
          shortTitle: shortTitle,
          instruction: instruction,
          verifyResult: formatConciseVerifySentence(
            customVerify.isNotEmpty
                ? customVerify
                : (hasDynamicSpec
                     ? spec.verify
                    : 'Verify "$shortTitle" responds cleanly in the active viewport.'),
          ),
          stepPath: customPath.isNotEmpty
              ? customPath
              : (hasDynamicSpec ? spec.path : whereLocation),
          codeFormula: code,
          explainConcept: (!isCustomSnippet && hasDynamicSpec)
              ? spec.explain
              : '$phaseFocusNote Connects "$shortTitle" to "$primaryVar" and "$primaryGuard".',
          specChips: chips,
          quickFixPitfall: spec.pitfall,
          estimatedMinutes: stepMins,
          etaLabel: stepEta,
          isGuardStep: isLastStep || stepLabel.toUpperCase().contains('GUARD'),
          isEditorCheck: decodedNotes.verifyMode == 'editor',
          stepRole: decodedNotes.stepRole,
          area1Hierarchy: decodedNotes.area1Hierarchy,
          area2Inspector: decodedNotes.area2Inspector,
        ),
      );
    }

    final result = TaskHowToBlueprint(
      numLabel: numLabel,
      layerTag: layerTag,
      cleanTitle: cleanTitle,
      durationChip: durationChip,
      whereLocation: whereLocation,
      engineLabel: engineLabel,
      subSteps: resolvedSubs,
    );

    if (_blueprintCache.length > 512) {
      _blueprintCache.clear();
    }
    _blueprintCache[cacheKey] = (
      signature: _computeTaskSignature(
        parentTask: parentTask,
        checkpointNode: checkpointNode,
        engineHint: engineHint,
        effectivePhase: effectivePhase,
      ),
      blueprint: result,
    );
    return result;
  }

  /// Classifies a step into its primary Godot 4 workflow dock stage
  /// (`scene`, `inspector`, `code`, `wire`, `fix`) for unified Single-List rendering.
  static GodotDockStage classifySubStepDockStage({
    required String title,
    String? stepRole,
    String? area1Hierarchy,
    String? area2Inspector,
    String? codeFormula,
    String? stepPath,
    String? instruction,
  }) {
    final upperTitle = title.trim().toUpperCase();
    final lowerRole = (stepRole ?? '').trim().toLowerCase();
    if (upperTitle.contains('[FIX]') || lowerRole == 'fix') {
      return GodotDockStage.fix;
    }
    if (lowerRole == 'inspector_setup' || lowerRole == 'inspector') {
      return GodotDockStage.inspector;
    }
    if (lowerRole == 'script_logic' || lowerRole == 'code') {
      return GodotDockStage.code;
    }

    final hasHierarchy = (area1Hierarchy ?? '').trim().isNotEmpty;
    final code = (codeFormula ?? '').trim();
    final hasInspector = (area2Inspector ?? '').trim().isNotEmpty ||
        (code.contains('|') && code.contains('---'));
    final lowerPath = (stepPath ?? '').toLowerCase();
    final lowerInstr = (instruction ?? '').toLowerCase();
    final lowerTitle = title.toLowerCase();

    if (lowerRole == 'editor_setup' || lowerRole == 'scene') {
      if (!hasHierarchy &&
          (hasInspector ||
              lowerPath.contains('inspector') ||
              lowerPath.contains('input map') ||
              lowerTitle.contains('input map') ||
              lowerTitle.contains('collision layer') ||
              lowerTitle.contains('export'))) {
        return GodotDockStage.inspector;
      }
      return GodotDockStage.scene;
    }

    final looksLikeCode = code.contains('func ') ||
        code.contains('extends ') ||
        code.contains('@export') ||
        code.contains('@onready') ||
        code.contains('var ');
    final looksLikeSignalOrRun =
        lowerPath.contains('node dock') ||
        lowerPath.contains('signal') ||
        (lowerInstr.contains('connect') && lowerInstr.contains('signal')) ||
        code.contains('timeout()') ||
        code.contains('pressed()') ||
        code.contains('body_entered') ||
        code.contains('-->') ||
        code.contains('──►') ||
        code.contains('─►') ||
        lowerInstr.contains('f6') ||
        lowerInstr.contains('f5') ||
        lowerInstr.contains('run scene');

    if (lowerRole == 'wire_and_verify' ||
        lowerRole == 'wire' ||
        lowerRole == 'wiring_and_feel' ||
        lowerRole == 'signal_wiring' ||
        lowerRole.startsWith('wir') ||
        lowerRole.startsWith('signal')) {
      if (!looksLikeCode || looksLikeSignalOrRun) {
        return GodotDockStage.wire;
      }
      return GodotDockStage.code;
    }

    if (looksLikeSignalOrRun && !looksLikeCode) {
      return GodotDockStage.wire;
    }
    if (hasInspector && !hasHierarchy && !looksLikeCode) {
      return GodotDockStage.inspector;
    }
    if ((hasHierarchy ||
            lowerPath.contains('scene dock') ||
            lowerTitle.contains('.tscn') ||
            lowerTitle.contains('child node')) &&
        !looksLikeCode) {
      return GodotDockStage.scene;
    }
    return GodotDockStage.code;
  }

  /// Stable sort putting steps in Godot dock execution order:
  /// `SCENE` -> `INSP` -> `CODE` -> `WIRE` -> `FIX`.
  static List<TaskHowToSubStep> orderUnifiedStepsByGodotDock(
    List<TaskHowToSubStep> steps,
  ) {
    final indexed = steps.asMap().entries.toList();
    indexed.sort((a, b) {
      final orderA = a.value.resolvedDockStage.sortOrder;
      final orderB = b.value.resolvedDockStage.sortOrder;
      if (orderA != orderB) return orderA.compareTo(orderB);
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  /// Stable sort putting raw persisted [Subtask] items in Godot dock execution
  /// order: `SCENE` -> `INSP` -> `CODE` -> `WIRE` -> `FIX`.
  static List<Subtask> orderSubtasksByGodotDock(List<Subtask> steps) {
    final indexed = steps.asMap().entries.toList();
    indexed.sort((a, b) {
      final decA = decodeThreeAreaNotes(a.value.specNotes);
      final decB = decodeThreeAreaNotes(b.value.specNotes);
      final stageA = classifySubStepDockStage(
        title: a.value.text,
        stepRole: decA.stepRole,
        area1Hierarchy: decA.area1Hierarchy,
        area2Inspector: decA.area2Inspector,
        codeFormula: a.value.codeSnippet,
        stepPath: a.value.codeLanguage,
        instruction: decA.cleanInstruction,
      );
      final stageB = classifySubStepDockStage(
        title: b.value.text,
        stepRole: decB.stepRole,
        area1Hierarchy: decB.area1Hierarchy,
        area2Inspector: decB.area2Inspector,
        codeFormula: b.value.codeSnippet,
        stepPath: b.value.codeLanguage,
        instruction: decB.cleanInstruction,
      );
      final cmp = stageA.sortOrder.compareTo(stageB.sortOrder);
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  /// Resolves a [FeatureStateNode] checkpoint into a flat Single Feature Step List
  /// (`BUILD QUEUE`), supporting both flat Unified Steps (`children.isEmpty`) and
  /// legacy nested `parentTask.children` checkpoints transparently.
  static List<TaskHowToSubStep> resolveUnifiedSteps({
    required FeatureStateNode checkpointNode,
    String? engineHint,
    ProductionPhase? phase,
  }) {
    if (checkpointNode.checklist.isEmpty) return const [];

    final effectivePhase = inferCheckpointPhase(
      checkpointNode,
      explicitPhase: phase,
    );
    final entries = checkpointNode.flatStepEntries;
    final hasAnyStructuredStep = entries.any(
      (e) =>
          e.step.codeTargetFile == 'custom_snippet' ||
          e.step.codeTargetFile == 'offline_default' ||
          (e.step.specNotes ?? '').trim().isNotEmpty ||
          (e.step.codeSnippet ?? '').trim().isNotEmpty,
    );

    // If legacy placeholder parent tasks exist without children or notes yet,
    // resolve via temporary non-mutating copies into flat steps.
    if (!hasAnyStructuredStep &&
        checkpointNode.checklist.every((c) => c.children.isEmpty)) {
      final collected = <TaskHowToSubStep>[];
      for (int tIdx = 0; tIdx < checkpointNode.checklist.length; tIdx++) {
        final clone = checkpointNode.checklist[tIdx].copyWith();
        final bp = resolve(
          parentTask: clone,
          taskIndex: tIdx,
          checkpointNode: checkpointNode,
          engineHint: engineHint,
          phase: effectivePhase,
        );
        collected.addAll(bp.subSteps);
      }
      final ordered = checkpointNode.parameters['manualStepOrder'] == 'true'
          ? collected
          : orderUnifiedStepsByGodotDock(collected);
      return _renumberUnifiedSteps(ordered);
    }

    // Legacy nested checklists (with parentTask.children) that lack AI markers
    // can still reuse per-task synthesized specs cleanly when needed.
    final fallbackByStepId = <String, TaskHowToSubStep>{};
    for (int tIdx = 0; tIdx < checkpointNode.checklist.length; tIdx++) {
      final item = checkpointNode.checklist[tIdx];
      if (item.children.isEmpty) continue;
      final needsLegacyFallback = item.children.any(
        (c) =>
            c.codeTargetFile != 'custom_snippet' &&
            (c.specNotes ?? '').trim().isEmpty,
      );
      if (needsLegacyFallback) {
        final bp = resolve(
          parentTask: item,
          taskIndex: tIdx,
          checkpointNode: checkpointNode,
          engineHint: engineHint,
          phase: effectivePhase,
        );
        for (final s in bp.subSteps) {
          fallbackByStepId[s.subtask.id] = s;
        }
      }
    }

    final asset = resolveAssetName(
      primarySharedAsset:
          checkpointNode.parameters['primarySharedScriptOrScene'],
      fallbackText: checkpointNode.name,
    );
    final minutesList = computeWeightedStepMinutes(
      entries.length,
      entries.length * 25,
    );
    final rawSteps = <TaskHowToSubStep>[];

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final step = entry.step;
      final fallback = fallbackByStepId[step.id];
      if (fallback != null && step.codeTargetFile != 'custom_snippet') {
        rawSteps.add(fallback);
        continue;
      }

      final decoded = decodeThreeAreaNotes(step.specNotes);
      final rawLabel = step.text.trim();
      final shortTitle = formatTelegraphicStepTitle(rawLabel);
      final instructionText = decoded.cleanInstruction.isNotEmpty
          ? formatConciseStepInstruction(decoded.cleanInstruction)
          : (fallback?.instruction ??
              'Configure "$shortTitle" on ${asset.pascalName} and verify cleanly.');
      final customVerify = (step.verification ?? '').trim();
      final verifyText = formatConciseVerifySentence(
        customVerify.isNotEmpty
            ? customVerify
            : (fallback?.verifyResult ??
                '$shortTitle updates ${asset.pascalName} cleanly with 0 errors.'),
      );
      final customPath = (step.codeLanguage ?? '').trim();
      final stepPath = customPath.isNotEmpty
          ? customPath
          : (fallback?.stepPath ?? 'res://scripts/${asset.snakeName}.gd');
      final codeText = (step.codeSnippet ?? '').trim().isNotEmpty
          ? step.codeSnippet!.trim()
          : (decoded.area2Inspector ?? fallback?.codeFormula ?? '');

      final dockStage = classifySubStepDockStage(
        title: shortTitle,
        stepRole: decoded.stepRole,
        area1Hierarchy: decoded.area1Hierarchy,
        area2Inspector: decoded.area2Inspector,
        codeFormula: codeText,
        stepPath: stepPath,
        instruction: instructionText,
      );

      final mins = i < minutesList.length ? minutesList[i] : 20;
      rawSteps.add(
        TaskHowToSubStep(
          subtask: step,
          stepNumberLabel: '${(i + 1).toString().padLeft(2, '0')} · ${shortTitle.toUpperCase()}',
          shortTitle: shortTitle,
          instruction: instructionText,
          verifyResult: verifyText,
          stepPath: stepPath,
          codeFormula: codeText,
          explainConcept:
              'Advances ${checkpointNode.cleanStageTitle} in Godot workflow order (${dockStage.badge}).',
          specChips: [dockStage.badge, asset.pascalName],
          quickFixPitfall: dockStage == GodotDockStage.scene
              ? 'Match node names cleanly before attaching scripts or @onready references.'
              : dockStage == GodotDockStage.inspector
                  ? 'Confirm physics collision layers/masks match your Godot Project Contract.'
                  : 'Ensure node paths and signal names match your Scene Tree.',
          estimatedMinutes: mins,
          etaLabel: formatStepEtaLabel(mins),
          isGuardStep: dockStage == GodotDockStage.fix ||
              rawLabel.toUpperCase().contains('[FIX]') ||
              rawLabel.toLowerCase().contains('guard') ||
              rawLabel.toLowerCase().contains('cooldown'),
          isEditorCheck: decoded.verifyMode == 'editor' ||
              dockStage == GodotDockStage.scene ||
              dockStage == GodotDockStage.inspector,
          stepRole: decoded.stepRole ?? dockStage.stepRole,
          dockStage: dockStage,
          area1Hierarchy: decoded.area1Hierarchy,
          area2Inspector: decoded.area2Inspector,
        ),
      );
    }

    final shouldRespectOrder =
        checkpointNode.parameters['manualStepOrder'] == 'true' ||
            entries.any((e) => e.legacyParent != null) == false;
    final ordered = shouldRespectOrder
        ? rawSteps
        : orderUnifiedStepsByGodotDock(rawSteps);
    return _renumberUnifiedSteps(ordered);
  }

  static List<TaskHowToSubStep> _renumberUnifiedSteps(
    List<TaskHowToSubStep> steps,
  ) {
    int numIdx = 1;
    final out = <TaskHowToSubStep>[];
    for (final s in steps) {
      final dock = s.resolvedDockStage;
      final prefix = dock == GodotDockStage.fix
          ? 'FIX'
          : (numIdx++).toString().padLeft(2, '0');
      final title = s.shortTitle.isNotEmpty
          ? s.shortTitle
          : formatTelegraphicStepTitle(s.subtask.text);
      out.add(
        TaskHowToSubStep(
          subtask: s.subtask,
          stepNumberLabel: '$prefix · ${title.toUpperCase()}',
          shortTitle: title,
          instruction: s.instruction,
          verifyResult: s.verifyResult,
          stepPath: s.stepPath,
          codeFormula: s.codeFormula,
          explainConcept: s.explainConcept,
          specChips: s.specChips,
          quickFixPitfall: s.quickFixPitfall,
          estimatedMinutes: s.estimatedMinutes,
          etaLabel: s.etaLabel,
          isGuardStep: s.isGuardStep,
          isEditorCheck: s.isEditorCheck,
          stepRole: s.stepRole ?? dock.stepRole,
          dockStage: dock,
          area1Hierarchy: s.area1Hierarchy,
          area2Inspector: s.area2Inspector,
        ),
      );
    }
    return out;
  }

  /// Populates a newly created [checkpointNode] with 4 dock-ordered flat Unified
  /// Steps (`SCENE` -> `INSP` -> `CODE` -> `WIRE`) immediately (even offline) so
  /// there are zero nested `T1..T3` buckets before AI synthesis runs.
  static void populateDefaultUnifiedSteps(
    FeatureStateNode checkpointNode, {
    String? engineHint,
    ProductionPhase? phase,
  }) {
    if (checkpointNode.checklist.any(
      (c) =>
          c.children.isEmpty &&
          (c.codeTargetFile == 'custom_snippet' ||
              (c.specNotes ?? '').trim().isNotEmpty),
    )) {
      return;
    }
    final asset = resolveAssetName(
      primarySharedAsset:
          checkpointNode.parameters['primarySharedScriptOrScene'],
      fallbackText:
          '${checkpointNode.cleanStageTitle} ${checkpointNode.coveredScope.join(' ')}',
    );
    final pascal = asset.pascalName;
    final snake = asset.snakeName;
    final hintCorpus = [
      engineHint ?? '',
      checkpointNode.parameters['primarySharedScriptOrScene'] ?? '',
      checkpointNode.cleanStageTitle,
      ...checkpointNode.coveredScope,
      ...checkpointNode.tuningParams,
    ].join(' ').toLowerCase();
    final is3D = RegExp(
      r'\b(?:3d|first[- ]?person|third[- ]?person|vector3|characterbody3d|node3d|raycast3d|rigidbody3d|camera3d|meshinstance3d)\b',
    ).hasMatch(hintCorpus);
    final bodyType = is3D ? 'CharacterBody3D' : 'CharacterBody2D';
    final collisionNode = is3D ? 'CollisionShape3D' : 'CollisionShape2D';
    final capsuleShape = is3D ? 'CapsuleShape3D' : 'CapsuleShape2D';
    final parsedVars = filterDeclaredGameplayVariables(checkpointNode.tuningParams);
    final primaryVarName =
        parsedVars.isNotEmpty ? parsedVars.first.name : 'move_speed';
    final primaryVarVal = parsedVars.isNotEmpty && parsedVars.first.value.isNotEmpty
        ? parsedVars.first.value.split(' ').first
        : '240.0';
    final guardText = checkpointNode.edgeCases.isNotEmpty
        ? checkpointNode.edgeCases.first
        : '[STATE GUARD] Prevent duplicate trigger while active';

    final inspectorRows = <String>[
      '| Node | Property | Value |',
      '| --- | --- | --- |',
      if (parsedVars.isEmpty)
        '| $pascal | @export $primaryVarName | $primaryVarVal |',
      for (final v in parsedVars.take(3))
        '| $pascal | @export ${v.name} | ${v.value.isNotEmpty ? v.value : "1.0"} |',
      '| Input Map | ${snake}_action | Space |',
      '| $pascal | collision_mask | 1 |',
    ].join('\n');

    final playtestGoal = checkpointNode.playtestCondition;
    checkpointNode.checklist = [
      Subtask(
        id: '${checkpointNode.id}_step_scene',
        text: 'Build $pascal Scene Nodes',
        codeLanguage: 'Scene Dock → res://scenes/$snake.tscn',
        codeTargetFile: 'offline_default',
        verification:
            '$pascal appears in Scene Tree with $collisionNode and helper child nodes (0 errors).',
        specNotes: encodeThreeAreaNotes(
          instruction:
              'Create res://scenes/$snake.tscn with root $bodyType "$pascal", $collisionNode, and StateTimer, then attach res://scripts/$snake.gd.',
          area1Hierarchy:
              '$pascal ($bodyType) 📜 $snake.gd\n├─ $collisionNode ($capsuleShape)\n└─ StateTimer (Timer)',
          verifyMode: 'editor',
          stepRole: 'editor_setup',
        ),
      ),
      Subtask(
        id: '${checkpointNode.id}_step_insp',
        text: 'Set Layers, InputMap & Exports',
        codeLanguage: 'Inspector & Project Settings',
        codeTargetFile: 'offline_default',
        verification:
            'Input Map exposes ${snake}_action and Inspector shows tuned @export properties.',
        codeSnippet: inspectorRows,
        specNotes: encodeThreeAreaNotes(
          instruction:
              'Bind ${snake}_action in Project Settings → Input Map, set StateTimer.one_shot = true, and verify initial @export values.',
          area2Inspector: inspectorRows,
          verifyMode: 'editor',
          stepRole: 'inspector_setup',
        ),
      ),
      Subtask(
        id: '${checkpointNode.id}_step_code',
        text: 'Code $pascal Core & Guard Logic',
        codeLanguage: 'res://scripts/$snake.gd',
        codeTargetFile: 'offline_default',
        codeSnippet:
            'extends $bodyType\n\n@export var $primaryVarName: float = ${double.tryParse(primaryVarVal) != null ? primaryVarVal : '240.0'}\n@onready var state_timer: Timer = \$StateTimer\n\nfunc _physics_process(delta: float) -> void:\n    # Guard: $guardText\n    if Input.is_action_just_pressed("${snake}_action") and state_timer.is_stopped():\n        _activate_$snake()',
        verification:
            'Triggering ${snake}_action executes cleanly and obeys "$guardText".',
        specNotes: encodeThreeAreaNotes(
          instruction:
              'Declare @export $primaryVarName and implement _activate_$snake() in res://scripts/$snake.gd with guard "$guardText".',
          verifyMode: 'playtest',
          stepRole: 'script_logic',
        ),
      ),
      Subtask(
        id: '${checkpointNode.id}_step_wire',
        text: 'Connect Signals & Playtest (F6)',
        codeLanguage: 'Node Dock → Signals & Run Scene (F6)',
        codeTargetFile: 'offline_default',
        codeSnippet: 'StateTimer.timeout() --> $pascal._on_state_timer_timeout()',
        verification: playtestGoal,
        specNotes: encodeThreeAreaNotes(
          instruction:
              'Connect StateTimer.timeout() to $pascal._on_state_timer_timeout() in the Node dock, then press F6 to test.',
          verifyMode: 'playtest',
          stepRole: 'wire_and_verify',
        ),
      ),
    ];
  }

  /// Returns true when any active highlight token matches [searchableText]
  /// (case-insensitive substring or compact alphanumeric match).
  static bool matchesHighlightTokens(
    Set<String> tokens,
    String searchableText,
  ) {
    if (tokens.isEmpty || searchableText.trim().isEmpty) return false;
    final lower = searchableText.toLowerCase();
    final compact = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    for (final raw in tokens) {
      final token = raw.trim().toLowerCase();
      if (token.length < 3) continue;
      final compactToken = token.replaceAll(RegExp(r'[^a-z0-9]+'), '');
      if (lower.contains(token) ||
          (compactToken.length >= 4 && compact.contains(compactToken))) {
        return true;
      }
    }
    return false;
  }
}
