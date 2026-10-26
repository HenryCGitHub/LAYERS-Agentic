/// Pure display-title cleanup helpers for Epics (Beats) and Features.
/// Contains zero hardcoded genre archetypes, zero hardcoded feature names,
/// and zero fallback scaffolds.
class MechanicArchetypeProfile {
  /// Strips trailing `: description` or `— description` from an Epic/Beat title
  /// without ever substituting a hardcoded genre beat name.
  static String concreteBeatDisplayTitle(
    String rawBeatTitle, {
    int beatIndex = 0,
  }) {
    final cleaned =
        rawBeatTitle.split(':').first.split('—').first.trim();
    return cleaned.isNotEmpty ? cleaned : rawBeatTitle.trim();
  }

  static final RegExp _trailingTechSuffixRegex = RegExp(
    r'\s+(?:Controller|System|Systems|Mechanic|Mechanics|Manager|Component|Subsystem|Handler)s?$',
    caseSensitive: false,
  );

  /// Strips redundant leading `<BeatTitle>:` prefixes and trailing technical
  /// class suffixes (`Controller`, `System`, `Mechanic`, `Manager`, etc.)
  /// while preserving the concrete AI-generated or user-entered feature title.
  static String concreteFeatureTitleForBeat(
    String rawTitle, {
    String? beatTitle,
    String? beatGoal,
    int beatIndex = 0,
  }) {
    var trimmed = rawTitle.trim();
    if (trimmed.contains(':')) {
      final colonIdx = trimmed.indexOf(':');
      final afterColon = trimmed.substring(colonIdx + 1).trim();
      if (afterColon.isNotEmpty) {
        trimmed = afterColon;
      }
    }
    if (trimmed.contains(' — ')) {
      trimmed = trimmed.split(' — ').first.trim();
    }
    while (_trailingTechSuffixRegex.hasMatch(trimmed)) {
      final stripped = trimmed.replaceFirst(_trailingTechSuffixRegex, '').trim();
      if (stripped.isEmpty) break;
      trimmed = stripped;
    }
    return trimmed;
  }
}
