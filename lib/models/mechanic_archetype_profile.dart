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

  /// Strips redundant leading `<BeatTitle>:` prefixes from a Feature title
  /// while preserving the exact AI-generated or user-entered feature title.
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
    return trimmed;
  }
}
