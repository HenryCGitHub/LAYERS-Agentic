/// Single Source of Truth for LAYERS Studio formatting & Godot 4 spec schema rules.
/// Preserves [compactStyleRules] for `GeminiAgentClient` while standardizing on
/// high-level Godot 4 design specs (`3D`: `1 unit = 1 m` | `2D`: `px`, `§01–§06`, `v0.1`-first).
class LayersTextStyleGuide {
  const LayersTextStyleGuide._();

  /// Shared compact style rules injected into Gemini system/user prompts by `GeminiAgentClient`.
  static const String compactStyleRules = '''
LAYERS CANONICAL GODOT 4 SPEC STYLE RULES:
1. HIGH-LEVEL GODOT 4 DESIGN ONLY: Never emit implementation step checklists or Unreal/Unity terms (Blueprint, .uasset, ACharacter, AActor, UMG, GameObject, Prefab). Emit complete cohesive gameplay Epics (`Project -> Release -> Epic`).
2. BLUF FORMAT: "[2-4 Word Payoff] — [Scope]" for Project Vision / Pitch and Epic summaries.
3. CAUSAL PLAYTEST GATES (<= 14 words): "[Player Action] -> [Observable Playtest Screen Result]" for checks & Done When gates.
4. CHANGELOG DELTAS (+Delta, 5-10 words): Progressive release upgrades describe "+mechanic delta" atop locked v0.1 baselines.
5. GODOT 4 SCALE: Use 1 unit = 1 m (`m`, `m/s`) for 3D projects, or pixels (`px`, `px/s`) for 2D projects, plus `deg`, `s`, `hp`, `count`. Never use `cm` or `cm/s`.
6. LITERAL GAME-DEV LANGUAGE: Plain everyday gameplay terms. Ban corporate filler ("seamlessly", "leverage", "synergy", "unified", "validate").
7. PURE GDSCRIPT 2.0 + SCENE TREE POLICY: Reference Godot 4 `res://scenes/*.tscn`, `res://scripts/*.gd`, `snake_case` `@export` variables, and `project.godot` `InputMap` actions.
''';

  static const String epicTitleSchemaDesc =
      '2-5 word plain Godot gameplay system title (e.g. "Player Mech Movement & Claw Dash"). Never use corporate buzzwords or implementation steps.';

  static const String blufVisionSchemaDesc =
      'BLUF 1-line pitch: "[2-4 Word Payoff] — [Compact Godot 4 scope]". Literal game-dev phrasing.';

  static const String coreLoopStepSchemaDesc =
      '2-4 word concrete player verb beat in chronological order (e.g. "Move & Cursor Aim").';

  static const String godotContractSchemaDesc =
      'Exact Godot 4 camera spec (`SpringArm3D` / `Camera3D` distances in `m` for 3D, or `Camera2D` zoom & smoothing for 2D).';

  static const String pillarSchemaDesc =
      'Design pillar naming player experience first ("Pillar Name: experiential reason"), not a raw feature checklist.';

  static const String exclusionItemSchemaDesc =
      'Hard scope cut starting with "No [2-5 word system]" (e.g. "No main menu or save slots").';

  static const String causalPlaytestCheckSchemaDesc =
      'Observable playtest condition in causal format: "[Player Action] -> [Screen Result]" (<= 14 words).';

  static const String godotControlRuleSchemaDesc =
      'Concise input response rule matching active 3D (`m`, `m/s`) or 2D (`px`, `px/s`) dimension and explicit interrupt behavior.';

  static const String godotTuningUnitSchemaDesc =
      'Canonical Godot unit ("m", "m/s" for 3D; "px", "px/s" for 2D; plus "deg", "s", "hp", "x", "%", "count", "bool"). Never use cm.';

  static const String changelogDeltaSchemaDesc =
      '5-10 word additive delta starting with "+" (e.g. "+55ms hitstop freeze & radial shockwave ring").';

  static const String godotSceneLinkSchemaDesc =
      'Concrete Godot asset/signal links (`res://scenes/*.tscn`, `res://scripts/*.gd`, `res://data/*.tres`, groups, signals — zero Unreal assets).';

  static const String godotTuningKeySchemaDesc =
      'snake_case GDScript @export variable identifier (e.g. "max_walk_speed", "wave_1_count", "allow_air_dash"). Never use spaces, hyphens, or PascalCase.';

  static const String godotSceneStagingSchemaDesc =
      'Target Godot test scene (`res://scenes/*.tscn`) and greybox node placement needed to playtest this Epic.';

  static String compactStoredTradeOff(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^[•\-\*\s]+'), '');
    if (cleaned.isEmpty) return '';
    return cleaned.replaceAll(
      RegExp(r'\s+over\s+', caseSensitive: false),
      ' OVER ',
    );
  }

  static String compactStoredExclusion(String raw) {
    final trimmed = raw.trim().replaceFirst(RegExp(r'^[•\-\*\s]+'), '');
    if (trimmed.isEmpty) return '';
    if (trimmed.toLowerCase().startsWith('no ')) return trimmed;
    return 'No $trimmed';
  }

  static String stripExclusionPrefixes(String raw) {
    return raw
        .trim()
        .replaceFirst(RegExp(r'^[•\-\*\s]+'), '')
        .replaceFirst(RegExp(r'^out of scope:\s*', caseSensitive: false), '')
        .trim();
  }

  static String formatConciseTaskTitle(String raw) {
    var s = raw
        .trim()
        .replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '')
        .replaceFirst(RegExp(r'^(Create|Build|Implement|Add)\s+(the\s+)?', caseSensitive: false), '')
        .trim();
    if (s.isEmpty) return raw.trim();
    return s[0].toUpperCase() + s.substring(1);
  }

  static String formatTelegraphicSpecValue(String raw) {
    final cleaned = raw
        .replaceFirst(
          RegExp(r'^(Perspective|Camera|Core Loop|Engine):\s*', caseSensitive: false),
          '',
        )
        .trim();
    return cleaned.isEmpty ? raw.trim() : cleaned;
  }

  static bool isLegacyTemplateTaskTitle(String raw) {
    return RegExp(r'\bstep\s+\d+|micro[- ]?task|\.uasset\b|\.uproject\b',
            caseSensitive: false)
        .hasMatch(raw);
  }
}
