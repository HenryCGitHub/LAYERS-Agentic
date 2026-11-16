/// Single Source of Truth for LAYERS Studio formatting & Unreal MCP schema rules.
/// Preserves [compactStyleRules] for `GeminiAgentClient` while standardizing on
/// high-level Unreal Engine design specs (`1 UU = 1 cm`, `§01–§06`, `v0.1`-first).
class LayersTextStyleGuide {
  const LayersTextStyleGuide._();

  /// Shared compact style rules injected into Gemini system/user prompts by `GeminiAgentClient`.
  static const String compactStyleRules = '''
LAYERS CANONICAL UNREAL SPEC STYLE RULES:
1. HIGH-LEVEL UNREAL DESIGN ONLY: Never emit implementation micro-steps, file trees, or Godot terms (.tscn, .gd, GDScript, CharacterBody3D). Emit complete high-level Unreal systems (`Project -> Release -> Epic`).
2. BLUF FORMAT: "[2-4 Word Payoff] — [Scope]" for Project Vision / Pitch and Epic summaries.
3. CAUSAL PIE GATES (<= 14 words): "[Player Action] -> [Observable PIE Screen Result]" for checks & Done When gates.
4. CHANGELOG DELTAS (+Delta, 5-10 words): Progressive release upgrades describe "+mechanic delta" atop locked v0.1 baselines.
5. UNREAL SCALE (1 UU = 1 cm): Always specify spatial distances in cm, speeds in cm/s, angles in deg, durations in s, health in hp.
6. LITERAL GAME-DEV LANGUAGE: Plain everyday gameplay terms. Ban corporate filler ("seamlessly", "leverage", "synergy", "unified", "validate").
''';

  static const String epicTitleSchemaDesc =
      '2-5 word plain Unreal gameplay system title (e.g. "Player Mech Movement & Claw Dash"). Never use corporate buzzwords or implementation steps.';

  static const String blufVisionSchemaDesc =
      'BLUF 1-line pitch: "[2-4 Word Payoff] — [Compact Unreal scope]". Literal game-dev phrasing.';

  static const String coreLoopStepSchemaDesc =
      '2-4 word concrete player verb beat in chronological order (e.g. "Skim & Cursor Aim").';

  static const String unrealContractSchemaDesc =
      'Exact Unreal Engine 1 UU = 1 cm architecture spec (e.g. "SpringArm 1450 cm @ -52 deg pitch, 55 deg FOV, CameraLag 9.0").';

  static const String pillarSchemaDesc =
      'Design pillar naming player experience first ("Pillar Name: experiential reason"), not a raw feature checklist.';

  static const String exclusionItemSchemaDesc =
      'Hard scope cut starting with "No [2-5 word system]" (e.g. "No main menu or save slots").';

  static const String causalPieCheckSchemaDesc =
      'Observable PIE test condition in causal format: "[Player Action] -> [Screen Result]" (<= 14 words).';

  static const String unrealControlRuleSchemaDesc =
      'Concise input response rule using UE units (cm, cm/s, s) and explicit interrupt behavior.';

  static const String unrealTuningUnitSchemaDesc =
      'Canonical Unreal unit ("cm", "cm/s", "deg", "s", "hp", "x", "%", "count"). Never use pixels.';

  static const String changelogDeltaSchemaDesc =
      '5-10 word additive delta starting with "+" (e.g. "+55ms Hit-Stop freeze & radial shockwave ring").';

  static const String unrealActorLinkSchemaDesc =
      'Concrete Unreal asset/interface links using UE prefixes (BP_*, DA_*, BPI_*, IMC_*, IA_*, WBP_*).';

  static const String unrealTuningKeySchemaDesc =
      'PascalCase Unreal variable identifier (e.g. "MaxWalkSpeed", "Wave1Count", "bAllowAirDash"). Never use spaces or hyphens.';

  static const String unrealLevelStagingSchemaDesc =
      'Target Unreal test map (L_*) and greybox actor placement needed to test this Epic in PIE.';

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
    return RegExp(r'\bstep\s+\d+|micro[- ]?task|\.tscn|\.gd\b', caseSensitive: false)
        .hasMatch(raw);
  }
}
