/// Pure display-title cleanup helpers for Epics (Beats) and Features.
/// Contains zero hardcoded genre archetypes, zero hardcoded feature names,
/// and zero fallback scaffolds.
class MechanicArchetypeProfile {
  const MechanicArchetypeProfile._();

  /// Strips trailing `: description` or `— description` from an Epic/Beat title
  /// without ever substituting a hardcoded genre beat name.
  static String concreteBeatDisplayTitle(
    String rawBeatTitle, {
    int beatIndex = 0,
  }) {
    var cleaned = rawBeatTitle;
    final colonIdx = cleaned.indexOf(':');
    if (colonIdx >= 0) cleaned = cleaned.substring(0, colonIdx);
    final dashIdx = cleaned.indexOf('—');
    if (dashIdx >= 0) cleaned = cleaned.substring(0, dashIdx);
    cleaned = cleaned.trim();
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
    final colonIdx = trimmed.indexOf(':');
    if (colonIdx >= 0) {
      final afterColon = trimmed.substring(colonIdx + 1).trim();
      if (afterColon.isNotEmpty) {
        trimmed = afterColon;
      }
    }
    final emDashIdx = trimmed.indexOf(' — ');
    if (emDashIdx > 0) {
      trimmed = trimmed.substring(0, emDashIdx).trim();
    }
    while (true) {
      final stripped = trimmed.replaceFirst(_trailingTechSuffixRegex, '').trim();
      if (stripped == trimmed || stripped.isEmpty) break;
      trimmed = stripped;
    }
    return trimmed;
  }
}
