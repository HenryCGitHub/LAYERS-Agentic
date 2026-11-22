/// Unreal Engine 5 architecture mode for Project Specs, `UnrealSpecGuard`,
/// and Ultimate Engine CoPilot prompts (`Blueprint-First` vs `C++ & BP Hybrid`).
enum UnrealArchitectureMode {
  blueprint,
  cppHybrid;

  String get id => name;

  String get shortLabel => switch (this) {
        UnrealArchitectureMode.blueprint => 'UE5 · Blueprint',
        UnrealArchitectureMode.cppHybrid => 'UE5 · C++ & BP',
      };

  String get pillLabel => switch (this) {
        UnrealArchitectureMode.blueprint => 'Blueprint-First',
        UnrealArchitectureMode.cppHybrid => 'C++ & BP Hybrid',
      };

  String get fullLabel => switch (this) {
        UnrealArchitectureMode.blueprint => 'Unreal Engine 5 — Blueprint-First',
        UnrealArchitectureMode.cppHybrid =>
          'Unreal Engine 5 — C++ & BP Hybrid',
      };

  String get architectureContract => switch (this) {
        UnrealArchitectureMode.blueprint =>
          'Unreal Engine 5 Blueprint-First (BP_* Actors/Characters + WBP_* UMG Widgets + Enhanced Input)',
        UnrealArchitectureMode.cppHybrid =>
          'Unreal Engine 5 C++ & Blueprint Hybrid (Source/ ACharacter/AActor/UActorComponent + UPROPERTY(EditAnywhere) + Thin BP_* & WBP_* Subclasses)',
      };

  String get codePolicyContract => switch (this) {
        UnrealArchitectureMode.blueprint =>
          'UNREAL ENGINE 5 BLUEPRINT-FIRST — Build gameplay in modular BP_* Blueprints, WBP_* UMG Widgets, and IA_*/IMC_* Enhanced Input with PascalCase Instance-Editable variables.',
        UnrealArchitectureMode.cppHybrid =>
          'UNREAL ENGINE 5 C++ & BLUEPRINT HYBRID — Build core state, math, and UPROPERTY(EditAnywhere, BlueprintReadWrite) PascalCase tuning in Source/ C++ classes paired with thin BP_* subclasses, WBP_* UMG Widgets, and IA_*/IMC_* Enhanced Input.',
      };

  String get tuningColumnLabel => switch (this) {
        UnrealArchitectureMode.blueprint => 'Exposed BP Var',
        UnrealArchitectureMode.cppHybrid => 'UPROPERTY(EditAnywhere) Var',
      };

  String get inputContractLabel => 'Enhanced Input (IA_* / IMC_*)';

  String get distanceUnit => 'cm';

  String get speedUnit => 'cm/s';

  static UnrealArchitectureMode fromString(String? raw) {
    final lower = (raw ?? '').trim().toLowerCase();
    if (lower == 'cpphybrid' ||
        lower == 'cpp_hybrid' ||
        lower.contains('c++') ||
        lower.contains('hybrid') ||
        lower == 'cpp') {
      return UnrealArchitectureMode.cppHybrid;
    }
    return UnrealArchitectureMode.blueprint;
  }

  static UnrealArchitectureMode detectFromSpark(String sparkPrompt) {
    final lower = sparkPrompt.trim().toLowerCase();
    if (lower.isEmpty) return UnrealArchitectureMode.blueprint;
    if (RegExp(
      r'\b(?:c\+\+|cpp|uproperty|ufunction|uclass|gameplay\s+ability\s+system|gas|hybrid|native\s+code|unreal\s+c\+\+)\b',
    ).hasMatch(lower)) {
      return UnrealArchitectureMode.cppHybrid;
    }
    return UnrealArchitectureMode.blueprint;
  }
}
