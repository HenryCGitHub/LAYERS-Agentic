/// Single Source of Truth for LAYERS Studio formatting & Unreal Engine 5 spec schema rules.
/// Preserves [compactStyleRules] for `GeminiAgentClient` while standardizing on
/// high-level Unreal Engine 5 specs (`Blueprint-First` | `C++ & BP Hybrid`, `cm`/`cm/s`, `§01–§05`, `v0.1`-first).
class LayersTextStyleGuide {
  const LayersTextStyleGuide._();

  /// Shared compact style rules injected into Gemini system/user prompts by `GeminiAgentClient`.
  static const String compactStyleRules = '''
LAYERS CANONICAL UNREAL ENGINE 5 SPEC STYLE RULES:
1. 4-TIER UNREAL ENGINE 5 ARCHITECTURE (`Project -> Release -> Epic -> Feature`, ZERO Tasks/Steps): Never emit implementation step checklists or non-Unreal engine terms. Epics own large domain architecture (shared `/Game/Maps/Lvl_*.umap`, `/Game/Blueprints/BP_*`, `/Game/UI/WBP_*`, or `Source/*.h`/`*.cpp` assets, state & interrupt rules, domain cuts); Features own sittable 30-90 min playable slices (Enhanced Input `IA_*` bindings, Exposed BP / `UPROPERTY(EditAnywhere)` tuning, viewport/UMG/Niagara/audio cues, PIE Playtest Gate).
2. BLUF FORMAT: "[2-4 Word Payoff] — [Scope]" for Project Vision / Pitch and Epic summaries.
3. CAUSAL PIE PLAYTEST GATES (<= 14 words): "[Player Action] -> [Observable PIE Viewport Result]" for checks & Done When gates.
4. CHANGELOG DELTAS (+Delta, 5-10 words): Progressive release upgrades describe "+mechanic delta" atop locked v0.1 baselines inside permanent Epics without duplicating cards.
5. UNREAL UNITS: Use centimeters (`cm`, `cm/s`) for distances and speeds, plus `deg`, `s`, `hp`, `x`, `%`, `count`, `bool`. Never emit metric meters or pixel units.
6. LITERAL GAME-DEV LANGUAGE: Plain everyday gameplay terms. Ban corporate filler ("seamlessly", "leverage", "synergy", "unified", "validate").
7. BLUEPRINT / C++ HYBRID POLICY: Reference `/Game/Maps/Lvl_*.umap`, `/Game/Blueprints/BP_*`, `/Game/UI/WBP_*`, `/Game/Data/DA_*`, `PascalCase` Exposed BP or `UPROPERTY(EditAnywhere)` variables, and Enhanced Input `IA_*` / `IMC_*` actions.
''';

  static const String epicTitleSchemaDesc =
      '2-5 word plain Unreal Engine 5 domain title covering multiple child Features (e.g. "Player Movement & Camera", "Claw Combat & Hitstop"). Never use corporate buzzwords or implementation steps.';

  static const String featureTitleSchemaDesc =
      '2-5 word plain playable Feature slice title (30-90 min scope, e.g. "Armored Claw Dash", "8-Way Walk & Iso Camera").';

  static const String sceneOwnershipSchemaDesc =
      'Concrete Unreal Engine 5 `/Game/Maps/Lvl_*.umap`, `/Game/Blueprints/BP_*`, `/Game/UI/WBP_*`, or `Source/*.h`/`*.cpp` asset owned by this Epic domain (`path` + concise `role`).';

  static const String blufVisionSchemaDesc =
      'BLUF 1-line pitch: "[2-4 Word Payoff] — [Compact Unreal Engine 5 scope]". Literal game-dev phrasing.';

  static const String coreLoopStepSchemaDesc =
      '2-4 word concrete player verb beat in chronological order (e.g. "Move & Cursor Aim").';

  static const String unrealContractSchemaDesc =
      'Exact Unreal Engine 5 camera spec (`USpringArmComponent` `TargetArmLength` in `cm`, pitch/FOV in `deg`, `CameraLagSpeed`, or `UCameraComponent` setup).';

  static const String pillarSchemaDesc =
      'Design pillar naming player experience first ("Pillar Name: experiential reason"), not a raw feature checklist.';

  static const String exclusionItemSchemaDesc =
      'Hard scope cut starting with "No [2-5 word system]" (e.g. "No main menu or save slots").';

  static const String causalPlaytestCheckSchemaDesc =
      'Observable PIE playtest condition in causal format: "[Player Action] -> [Screen Result]" (<= 14 words).';

  static const String unrealControlRuleSchemaDesc =
      'Concise Enhanced Input response rule in `cm` / `cm/s` with explicit interrupt behavior.';

  static const String unrealTuningUnitSchemaDesc =
      'Canonical Unreal unit ("cm", "cm/s", "deg", "s", "hp", "x", "%", "count", "bool"). Never use metric meters or px.';

  static const String changelogDeltaSchemaDesc =
      '5-10 word additive delta starting with "+" (e.g. "+55ms hitstop freeze & radial shockwave ring").';

  static const String unrealTuningKeySchemaDesc =
      'PascalCase Exposed BP or UPROPERTY(EditAnywhere) variable identifier (e.g. "MaxWalkSpeed", "Wave1Count", "bAllowAirDash"). Never use spaces or hyphens.';

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
    return RegExp(r'\bstep\s+\d+|micro[- ]?task', caseSensitive: false)
        .hasMatch(raw);
  }
}
