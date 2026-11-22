import '../agent_blueprints.dart';
import 'emberkeep_preset.dart';
import 'railjack_preset.dart';
import 'shellbreaker_preset.dart';

class UnrealSparkPresetInfo {
  final String id;
  final String label;
  final String subtitle;
  final String sparkPrompt;

  const UnrealSparkPresetInfo({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.sparkPrompt,
  });
}

class UnrealSparkPresets {
  static const List<UnrealSparkPresetInfo> entries = [
    UnrealSparkPresetInfo(
      id: 'shellbreaker',
      label: 'Shellbreaker',
      subtitle: 'Top-down twin-stick mech arena shooter',
      sparkPrompt:
          'Top-down twin-stick crustacean mech arena shooter with claw dash armor breaks, heavy burst cannon recoil, and 3-wave combat.',
    ),
    UnrealSparkPresetInfo(
      id: 'railjack',
      label: 'Railjack Drift',
      subtitle: 'Third-person hover-skiff canyon racer with boost & gates',
      sparkPrompt:
          'Third-person hover-skiff canyon time-trial racer with apex drift banking, thruster heat gauges, and plasma gate boosts.',
    ),
    UnrealSparkPresetInfo(
      id: 'emberkeep',
      label: 'Ember Keep',
      subtitle: 'Top-down torchlight survival & axe cleave defense',
      sparkPrompt:
          'Top-down survival skirmisher where you chop shadow stalkers, plant brazier light pylons, and hold safe ground as light radius shrinks.',
    ),
  ];

  static ProjectConceptBlueprint? matchSparkPrompt(String prompt) {
    final lower = prompt.toLowerCase().trim();
    if (lower.isEmpty) return null;
    if (RegExp(r'\bshellbreaker\b').hasMatch(lower) ||
        lower == entries[0].sparkPrompt.toLowerCase()) {
      return byId('shellbreaker');
    }
    if (RegExp(r'\brailjack\b').hasMatch(lower) ||
        lower == entries[1].sparkPrompt.toLowerCase()) {
      return byId('railjack');
    }
    if (RegExp(r'\bember\s*keep\b').hasMatch(lower) ||
        lower == entries[2].sparkPrompt.toLowerCase()) {
      return byId('emberkeep');
    }
    return null;
  }

  static ProjectConceptBlueprint byId(String id) {
    return switch (id) {
      'railjack' => buildRailjackPreset(entries[1].sparkPrompt),
      'emberkeep' => buildEmberkeepPreset(entries[2].sparkPrompt),
      _ => buildShellbreakerPreset(entries[0].sparkPrompt),
    };
  }
}
