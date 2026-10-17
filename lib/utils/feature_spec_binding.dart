import '../models/feature_state.dart';
import '../models/tier_document.dart';
import 'section_text_utils.dart';

/// Result container holding the mapped specification items per checkpoint,
/// as well as any leftover/unassigned items.
class FeatureSpecBindingResult {
  final Map<String, List<String>> checkpointScope;
  final Map<String, List<String>> checkpointTuning;
  final Map<String, List<String>> checkpointEdgeCases;
  final List<String> unassignedScope;
  final List<String> unassignedTuning;
  final List<String> unassignedEdgeCases;

  const FeatureSpecBindingResult({
    required this.checkpointScope,
    required this.checkpointTuning,
    required this.checkpointEdgeCases,
    required this.unassignedScope,
    required this.unassignedTuning,
    required this.unassignedEdgeCases,
  });

  /// Total count of unassigned scope deliverables, tuning parameters, and edge cases.
  int get totalUnassignedCount =>
      unassignedScope.length +
      unassignedTuning.length +
      unassignedEdgeCases.length;

  /// Returns true if there are any unassigned spec items that haven't been absorbed.
  bool get hasUnassigned => totalUnassignedCount > 0;
}

/// Helper that binds Feature specification items (In Scope, Tuning Parameters, Edge Cases)
/// directly to Playable Checkpoints (`FeatureStateNode`), and identifies any unassigned leftovers.
class FeatureSpecBinding {
  static final RegExp _bulletStripRegex = RegExp(r'^[•\*\-\s]+');

  /// Cleans raw multiline text into clean individual spec bullet lines.
  static List<String> cleanSpecLines(String raw) {
    if (raw.trim().isEmpty) return const [];
    return raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .map((l) => l.replaceFirst(_bulletStripRegex, '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// Resolves the bindings for a Feature document and its checkpoint state nodes.
  static FeatureSpecBindingResult resolveBindings(
    TierDocument feat,
    List<FeatureStateNode> states,
  ) {
    final rawInScope = SectionTextUtils.resolveInScope(feat.sections);
    final rawTuning = cleanSpecLines(
      feat.sections['variables'] ?? feat.sections['tuning'] ?? '',
    );
    final rawEdgeCases = cleanSpecLines(
      feat.sections['edge_cases'] ?? feat.sections['edgecases'] ?? '',
    );

    final checkpointScope = <String, List<String>>{};
    final checkpointTuning = <String, List<String>>{};
    final checkpointEdgeCases = <String, List<String>>{};

    for (final s in states) {
      checkpointScope[s.id] = <String>[];
      checkpointTuning[s.id] = <String>[];
      checkpointEdgeCases[s.id] = <String>[];
    }

    if (states.isEmpty) {
      return FeatureSpecBindingResult(
        checkpointScope: checkpointScope,
        checkpointTuning: checkpointTuning,
        checkpointEdgeCases: checkpointEdgeCases,
        unassignedScope: List.from(rawInScope),
        unassignedTuning: List.from(rawTuning),
        unassignedEdgeCases: List.from(rawEdgeCases),
      );
    }

    // ── 1. Map Tuning Parameters ──
    final assignedTuning = <String>{};

    // First: explicit state.tuningParams
    for (final s in states) {
      for (final p in s.tuningParams) {
        final cleanP = p.replaceFirst(_bulletStripRegex, '').trim();
        if (cleanP.isEmpty) continue;
        final match = rawTuning.firstWhere(
          (t) => _isTuningMatch(t, cleanP),
          orElse: () => cleanP,
        );
        if (!checkpointTuning[s.id]!.contains(match)) {
          checkpointTuning[s.id]!.add(match);
        }
        assignedTuning.add(match);
      }
    }

    // Second: heuristic matching for remaining tuning items
    for (final t in rawTuning) {
      if (assignedTuning.contains(t)) continue;
      final key = _extractTuningKey(t).toLowerCase();
      final val = _extractTuningVal(t).toLowerCase();

      FeatureStateNode? bestNode;
      for (final s in states) {
        final combinedText = '${s.name} ${s.playtestCondition} ${s.checklist.map((c) => c.text).join(' ')}'.toLowerCase();
        if ((key.length >= 3 && combinedText.contains(key)) ||
            (val.length >= 2 && combinedText.contains(val))) {
          bestNode = s;
          break;
        }
      }

      if (bestNode != null) {
        checkpointTuning[bestNode.id]!.add(t);
        assignedTuning.add(t);
      }
    }

    // ── 2. Map Edge Cases ──
    final assignedEdge = <String>{};

    // First: explicit state.edgeCases
    for (final s in states) {
      for (final e in s.edgeCases) {
        final cleanE = e.replaceFirst(_bulletStripRegex, '').trim();
        if (cleanE.isEmpty) continue;
        final match = rawEdgeCases.firstWhere(
          (item) => _isEdgeMatch(item, cleanE),
          orElse: () => cleanE,
        );
        if (!checkpointEdgeCases[s.id]!.contains(match)) {
          checkpointEdgeCases[s.id]!.add(match);
        }
        assignedEdge.add(match);
      }
    }

    // Second: heuristic matching for remaining edge cases with tag matching
    for (final e in rawEdgeCases) {
      if (assignedEdge.contains(e)) continue;
      final tag = _extractEdgeTag(e).toLowerCase();

      FeatureStateNode? matchedNode;
      if (tag.isNotEmpty) {
        for (final s in states) {
          final combined =
              '${s.name} ${s.playtestCondition} ${s.checklist.map((c) => c.text).join(' ')}'
                  .toLowerCase();
          if (combined.contains(tag)) {
            matchedNode = s;
            break;
          }
        }
      }

      if (matchedNode != null) {
        checkpointEdgeCases[matchedNode.id]!.add(e);
        assignedEdge.add(e);
      }
    }

    // ── 3. Map In Scope Deliverables ──
    final assignedScope = <String>{};
    for (final s in states) {
      for (final sc in s.coveredScope) {
        final cleanSc = sc.replaceFirst(_bulletStripRegex, '').trim();
        if (cleanSc.isEmpty) continue;
        final match = rawInScope.firstWhere(
          (item) => item.toLowerCase().contains(cleanSc.toLowerCase()) || cleanSc.toLowerCase().contains(item.toLowerCase()),
          orElse: () => cleanSc,
        );
        if (!checkpointScope[s.id]!.contains(match)) {
          checkpointScope[s.id]!.add(match);
        }
        assignedScope.add(match);
      }
    }

    for (int i = 0; i < rawInScope.length; i++) {
      final sc = rawInScope[i];
      if (assignedScope.contains(sc)) continue;
      final words = sc.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 3).toList();
      FeatureStateNode? matched;
      for (final s in states) {
        final text = '${s.name} ${s.playtestCondition}'.toLowerCase();
        if (words.any((w) => text.contains(w))) {
          matched = s;
          break;
        }
      }
      if (matched != null) {
        checkpointScope[matched.id]!.add(sc);
        assignedScope.add(sc);
      }
    }

    final unassignedTuning =
        rawTuning.where((t) => !assignedTuning.contains(t)).toList();
    final unassignedEdge =
        rawEdgeCases.where((e) => !assignedEdge.contains(e)).toList();
    final unassignedScope =
        rawInScope.where((s) => !assignedScope.contains(s)).toList();

    return FeatureSpecBindingResult(
      checkpointScope: checkpointScope,
      checkpointTuning: checkpointTuning,
      checkpointEdgeCases: checkpointEdgeCases,
      unassignedScope: unassignedScope,
      unassignedTuning: unassignedTuning,
      unassignedEdgeCases: unassignedEdge,
    );
  }

  static bool _isTuningMatch(String fullLine, String candidate) {
    final a = fullLine.toLowerCase();
    final b = candidate.toLowerCase();
    if (a == b) return true;
    final keyA = _extractTuningKey(fullLine).toLowerCase();
    final keyB = _extractTuningKey(candidate).toLowerCase();
    if (keyA.isNotEmpty && keyA == keyB) return true;
    return a.contains(b) || b.contains(a);
  }

  static bool _isEdgeMatch(String fullLine, String candidate) {
    final a = fullLine.toLowerCase();
    final b = candidate.toLowerCase();
    if (a == b) return true;
    final tagA = _extractEdgeTag(fullLine).toLowerCase();
    final tagB = _extractEdgeTag(candidate).toLowerCase();
    if (tagA.isNotEmpty && tagA == tagB) return true;
    return a.contains(b) || b.contains(a);
  }

  static String _extractTuningKey(String text) {
    if (text.contains(':')) {
      return text.split(':')[0].trim();
    }
    if (text.contains('=')) {
      return text.split('=')[0].trim();
    }
    return text.trim();
  }

  static String _extractTuningVal(String text) {
    if (text.contains(':')) {
      final parts = text.split(':');
      if (parts.length > 1) {
        // Return first token or up to dash
        final after = parts[1].trim();
        if (after.contains('-')) return after.split('-')[0].trim();
        return after;
      }
    }
    return '';
  }

  static String _extractEdgeTag(String text) {
    final match = RegExp(r'\[([^\]]+)\]').firstMatch(text);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return '';
  }
}
