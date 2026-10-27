import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/tier_document.dart';
export 'mechanic_archetype_profile.dart';
export 'task_how_to_blueprint.dart';

/// Represents a single dynamic state node in a Feature's state machine.
///
/// States are 100% dynamic per feature (e.g. "Wall Latch", "Submitting", "Hitstop", "3D Secure").
class FeatureStateNode {
  final String id;
  String name;
  String trigger;
  String? guard;
  Map<String, String> parameters;
  String? feedback;
  List<Subtask> checklist;
  int order;
  List<String> coveredScope;
  List<String> tuningParams;
  List<String> edgeCases;

  FeatureStateNode({
    required this.id,
    required this.name,
    this.trigger = '',
    this.guard,
    Map<String, String>? parameters,
    this.feedback,
    List<Subtask>? checklist,
    this.order = 0,
    List<String>? coveredScope,
    List<String>? tuningParams,
    List<String>? edgeCases,
  })  : parameters = parameters ?? {},
        checklist = checklist ?? [],
        coveredScope = coveredScope ?? [],
        tuningParams = tuningParams ?? [],
        edgeCases = edgeCases ?? [];

  /// Returns the operational stage tag (e.g. '[ROUGH PASS]', '[BUILD PASS]', '[FINAL PASS]') if present in the stage title.
  String? get operationalTag {
    final upper = name.toUpperCase();
    if (upper.contains('[ROUGH PASS]') || upper.contains('[ROUGH]')) return '[ROUGH PASS]';
    if (upper.contains('[BUILD PASS]') || upper.contains('[BUILD]')) return '[BUILD PASS]';
    if (upper.contains('[FINAL PASS]') || upper.contains('[FINAL]')) return '[FINAL PASS]';
    if (upper.contains('[PROTOTYPE]')) return '[ROUGH PASS]';
    if (upper.contains('[CORE]')) return '[BUILD PASS]';
    if (upper.contains('[POLISH]')) return '[FINAL PASS]';
    if (upper.contains('[TEST]')) return '[TEST]';
    return null;
  }

  /// Short operational tag for tight canvas headers (e.g. 'ROUGH', 'BUILD', 'FINAL')
  String? get shortOperationalTag {
    final tag = operationalTag;
    if (tag == null) return null;
    if (tag.contains('ROUGH')) return 'ROUGH';
    if (tag.contains('BUILD')) return 'BUILD';
    if (tag.contains('FINAL')) return 'FINAL';
    return tag.replaceAll('[', '').replaceAll(']', '').trim();
  }

  /// Release version tag this checkpoint was introduced in (e.g. 'v0.1', 'v0.2').
  String get releaseVersion {
    final raw = parameters['releaseVersion']?.trim();
    return (raw != null && raw.isNotEmpty) ? raw : 'v0.1';
  }

  set releaseVersion(String val) {
    parameters['releaseVersion'] = val.trim().isEmpty ? 'v0.1' : val.trim();
  }

  /// Theme-aware accent color for the operational stage tag badge.
  static Color tagColor(String tag, bool isDark) {
    switch (tag.toUpperCase()) {
      case '[ROUGH PASS]':
      case '[ROUGH]':
      case '[PROTOTYPE]':
        return isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7); // Sky Blue
      case '[BUILD PASS]':
      case '[BUILD]':
      case '[CORE]':
        return isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C); // Orange
      case '[FINAL PASS]':
      case '[FINAL]':
      case '[POLISH]':
        return isDark ? const Color(0xFF10B981) : const Color(0xFF059669); // Emerald
      case '[TEST]':
        return isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5); // Indigo / Purple
      default:
        return const Color(0xFF10B981);
    }
  }

  /// Number of completed checklist items in this state node
  /// Total number of atomic leaf checklist items / substeps in this state node
  int get totalChecklistCount =>
      checklist.fold(0, (sum, item) => sum + item.leafCount);

  /// Number of completed atomic leaf checklist items / substeps
  int get completedChecklistCount =>
      checklist.fold(0, (sum, item) => sum + item.completedLeafCount);

  /// Fractional progress (0.0 to 1.0) of this state's checklist
  double get progress => totalChecklistCount == 0
      ? 0.0
      : completedChecklistCount / totalChecklistCount;

  bool get isCompleted =>
      totalChecklistCount > 0 && completedChecklistCount == totalChecklistCount;

  /// Observable in-viewport playtest condition for this stage.
  String get playtestCondition {
    var t = trigger.trim();
    if (t.toLowerCase().startsWith('playtest:')) {
      t = t.substring(9).trim();
    }
    if (t.isNotEmpty) {
      return t;
    }
    if (feedback != null && feedback!.trim().isNotEmpty) return feedback!.trim();
    return 'Verify stage deliverables and checklist criteria in game viewport.';
  }

  static final RegExp _stageBracketTagRegex = RegExp(
    r'^\s*(\[(?:ROUGH PASS|BUILD PASS|FINAL PASS|ROUGH|BUILD|FINAL|PROTOTYPE|CORE|POLISH|TEST)\])\s*(.*)$',
    caseSensitive: false,
  );
  static final RegExp _stagePrefixRegex = RegExp(
    r'^\s*Stage\s*\d+\s*[:\-]\s*(.*)$',
    caseSensitive: false,
  );
  static final RegExp _bareStageRegex = RegExp(
    r'^\s*Stage\s*\d+\s*$',
    caseSensitive: false,
  );

  /// Clean descriptive title of this stage without the "Stage X:" or "[TAG]" prefix.
  String get cleanStageTitle {
    var trimmed = name.trim();
    final tagMatch = _stageBracketTagRegex.firstMatch(trimmed);
    if (tagMatch != null && tagMatch.group(2)!.trim().isNotEmpty) {
      trimmed = tagMatch.group(2)!.trim();
    }
    final match = _stagePrefixRegex.firstMatch(trimmed);
    if (match != null && match.group(1)!.trim().isNotEmpty) {
      return match.group(1)!.trim();
    }
    // If name is just "Stage 1", try to use trigger or fallback
    if (_bareStageRegex.hasMatch(trimmed)) {
      if (trigger.isNotEmpty &&
          !trigger.toLowerCase().startsWith('playtest:') &&
          !trigger.toLowerCase().startsWith('feature') &&
          !trigger.contains('{')) {
        return trigger;
      }
      return 'Stage Deliverables & Verification';
    }
    return trimmed;
  }

  /// Creates a [FeatureStateNode] from a [Subtask], intelligently decomposing
  /// structured metadata (trigger, guard, feedback, parameters) from specNotes and
  /// preserving nested child substeps.
  static FeatureStateNode fromSubtask(Subtask st, {int order = 0}) {
    String trigger = '';
    String? guard;
    String? feedback;
    Map<String, String> parameters = {};
    List<String> coveredScope = [];
    List<String> tuningParams = [];
    List<String> edgeCases = [];

    final notes = st.specNotes?.trim() ?? '';
    if (notes.isNotEmpty) {
      if (notes.startsWith('{') && notes.endsWith('}')) {
        try {
          final decoded = jsonDecode(notes);
          if (decoded is Map) {
            trigger = decoded['trigger']?.toString() ?? '';
            guard = decoded['guard']?.toString();
            feedback = decoded['feedback']?.toString();
            if (decoded['parameters'] is Map) {
              parameters = (decoded['parameters'] as Map).map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              );
            }
            if (decoded['coveredScope'] is List) {
              coveredScope = (decoded['coveredScope'] as List).map((e) => e.toString()).toList();
            } else if (decoded['covers_scope'] is List) {
              coveredScope = (decoded['covers_scope'] as List).map((e) => e.toString()).toList();
            }
            if (decoded['tuningParams'] is List) {
              tuningParams = (decoded['tuningParams'] as List).map((e) => e.toString()).toList();
            } else if (decoded['tuning'] is List) {
              tuningParams = (decoded['tuning'] as List).map((e) => e.toString()).toList();
            }
            if (decoded['edgeCases'] is List) {
              edgeCases = (decoded['edgeCases'] as List).map((e) => e.toString()).toList();
            } else if (decoded['edge_cases'] is List) {
              edgeCases = (decoded['edge_cases'] as List).map((e) => e.toString()).toList();
            }
          }
        } catch (_) {}
      }

      if (trigger.isEmpty && parameters.isEmpty) {
        // Parse pipe-delimited format
        final parts = notes.split('|');
        for (final rawPart in parts) {
          final part = rawPart.trim();
          if (part.isEmpty) continue;
          final lower = part.toLowerCase();
          if (lower.startsWith('trigger:')) {
            trigger = part.substring(8).trim();
          } else if (lower.startsWith('guard:') ||
              lower.startsWith('precondition:') ||
              lower.startsWith('guard / precondition:')) {
            final colon = part.indexOf(':');
            guard = part.substring(colon + 1).trim();
          } else if (lower.startsWith('feedback:') ||
              lower.startsWith('sensory:') ||
              lower.startsWith('ux:')) {
            final colon = part.indexOf(':');
            feedback = part.substring(colon + 1).trim();
          } else if (part.contains(':') && !part.contains('::')) {
            final colon = part.indexOf(':');
            final k = part.substring(0, colon).trim();
            final v = part.substring(colon + 1).trim();
            if (k.isNotEmpty && v.isNotEmpty) {
              parameters[k] = v;
            }
          } else {
            if (trigger.isEmpty) {
              trigger = part;
            } else {
              trigger = '$trigger, $part';
            }
          }
        }
      }
    }

    final checklist = st.children.isNotEmpty
        ? st.children
        : [
            Subtask(
              id: generateUniqueId('check'),
              text: 'Verify ${st.text}',
              completed: st.completed,
            )
          ];

    return FeatureStateNode(
      id: st.id.isNotEmpty ? st.id : generateUniqueId('state'),
      name: st.text,
      trigger: trigger,
      guard: guard,
      feedback: feedback,
      parameters: parameters,
      checklist: checklist,
      order: order,
      coveredScope: coveredScope,
      tuningParams: tuningParams,
      edgeCases: edgeCases,
    );
  }

  factory FeatureStateNode.fromJson(Map<String, dynamic> json) {
    final rawParams = json['parameters'] as Map<String, dynamic>? ?? {};
    final parsedParams =
        rawParams.map((k, v) => MapEntry(k.toString(), v.toString()));

    final rawChecklist = json['checklist'] as List<dynamic>? ??
        json['subtasks'] as List<dynamic>? ??
        [];
    final checklistItems = rawChecklist.map((item) {
      if (item is Map<String, dynamic>) {
        return Subtask.fromJson(item);
      }
      return Subtask(
        id: generateUniqueId('check'),
        text: item.toString(),
      );
    }).toList();

    final rawScope = json['coveredScope'] as List<dynamic>? ??
        json['covers_scope'] as List<dynamic>? ??
        [];
    final coveredScope = rawScope.map((e) => e.toString()).toList();

    final rawTuning = json['tuningParams'] as List<dynamic>? ??
        json['tuning'] as List<dynamic>? ??
        [];
    final tuningParams = rawTuning.map((e) => e.toString()).toList();

    final rawEdge = json['edgeCases'] as List<dynamic>? ??
        json['edge_cases'] as List<dynamic>? ??
        [];
    final edgeCases = rawEdge.map((e) => e.toString()).toList();

    return FeatureStateNode(
      id: json['id'] as String? ?? generateUniqueId('state'),
      name: json['name'] as String? ?? 'State',
      trigger: json['trigger'] as String? ?? '',
      guard: json['guard'] as String?,
      parameters: parsedParams,
      feedback: json['feedback'] as String?,
      checklist: checklistItems,
      order: json['order'] as int? ?? 0,
      coveredScope: coveredScope,
      tuningParams: tuningParams,
      edgeCases: edgeCases,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'trigger': trigger,
      if (guard != null && guard!.isNotEmpty) 'guard': guard,
      'parameters': parameters,
      if (feedback != null && feedback!.isNotEmpty) 'feedback': feedback,
      'checklist': checklist.map((item) => item.toJson()).toList(),
      'order': order,
      if (coveredScope.isNotEmpty) 'coveredScope': coveredScope,
      if (tuningParams.isNotEmpty) 'tuningParams': tuningParams,
      if (edgeCases.isNotEmpty) 'edgeCases': edgeCases,
    };
  }

  FeatureStateNode copyWith({
    String? id,
    String? name,
    String? trigger,
    String? guard,
    Map<String, String>? parameters,
    String? feedback,
    List<Subtask>? checklist,
    int? order,
    List<String>? coveredScope,
    List<String>? tuningParams,
    List<String>? edgeCases,
  }) {
    return FeatureStateNode(
      id: id ?? this.id,
      name: name ?? this.name,
      trigger: trigger ?? this.trigger,
      guard: guard ?? this.guard,
      parameters: parameters ?? Map.from(this.parameters),
      feedback: feedback ?? this.feedback,
      checklist: checklist ?? this.checklist.map((c) => c.copyWith()).toList(),
      order: order ?? this.order,
      coveredScope: coveredScope ?? List.from(this.coveredScope),
      tuningParams: tuningParams ?? List.from(this.tuningParams),
      edgeCases: edgeCases ?? List.from(this.edgeCases),
    );
  }

  /// Memoization cache for `getStatesForDocument` so repeated per-frame calls
  /// (Left Outliner, Feature ETA, Release ETA, Active Step Workspace) do not
  /// re-run `jsonDecode` when the underlying JSON & subtask completion state is unchanged.
  static final Map<String, ({int signature, List<FeatureStateNode> states})>
      _statesCache = {};

  static int _computeDocStatesSignature(TierDocument doc) {
    final rawJson = doc.sections['states'] ?? '';
    var hash = Object.hash(doc.id, doc.title, rawJson, doc.subtasks.length);
    void hashSubs(List<Subtask> items) {
      for (final it in items) {
        hash = Object.hash(hash, it.id, it.completed, it.children.length);
        hashSubs(it.children);
      }
    }
    hashSubs(doc.subtasks);
    return hash;
  }

  /// Extracts the dynamic state nodes for a given feature document.
  static List<FeatureStateNode> getStatesForDocument(TierDocument doc) {
    final sig = _computeDocStatesSignature(doc);
    final cached = _statesCache[doc.id];
    if (cached != null && cached.signature == sig) {
      return cached.states;
    }

    final rawJson = doc.sections['states'];
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          final nodes = decoded
              .whereType<Map<String, dynamic>>()
              .map((j) => FeatureStateNode.fromJson(j))
              .toList();
          if (nodes.isNotEmpty) {
            // Reconcile checklist completed states with doc.subtasks if available
            final subtaskMap = <String, Subtask>{};
            void collectSubtasks(List<Subtask> items) {
              for (final it in items) {
                subtaskMap[it.id] = it;
                collectSubtasks(it.children);
              }
            }

            collectSubtasks(doc.subtasks);
            for (final node in nodes) {
              for (final check in node.checklist) {
                if (subtaskMap.containsKey(check.id)) {
                  check.completed = subtaskMap[check.id]!.completed;
                }
                for (final sub in check.children) {
                  if (subtaskMap.containsKey(sub.id)) {
                    sub.completed = subtaskMap[sub.id]!.completed;
                  }
                }
              }
            }
            _statesCache[doc.id] = (
              signature: sig,
              states: nodes,
            );
            return nodes;
          }
        }
      } catch (_) {}
    }

    // Fallback: derive from doc.subtasks if available
    if (doc.subtasks.isNotEmpty) {
      int orderIdx = 0;
      final nodes = doc.subtasks.map((st) {
        return FeatureStateNode.fromSubtask(st, order: orderIdx++);
      }).toList();
      _statesCache[doc.id] = (
        signature: sig,
        states: nodes,
      );
      return nodes;
    }

    // Default: 1 clean initial state for unpopulated cards
    final fallback = [
      FeatureStateNode(
        id: generateUniqueId('state'),
        name: 'Idle / Entry',
        trigger: 'Feature initialized',
        order: 0,
      )
    ];
    _statesCache[doc.id] = (
      signature: sig,
      states: fallback,
    );
    return fallback;
  }

  /// Saves states back to the feature document, keeping both `doc.sections['states']`
  /// and `doc.subtasks` synchronized so progress metrics work seamlessly.
  static void saveStatesToDocument(
    TierDocument doc,
    List<FeatureStateNode> states,
  ) {
    doc.sections['states'] =
        jsonEncode(states.map((s) => s.toJson()).toList());
    doc.subtasks = states.map((s) {
      final meta = <String, dynamic>{
        'trigger': s.trigger,
        if (s.guard != null && s.guard!.isNotEmpty) 'guard': s.guard,
        if (s.feedback != null && s.feedback!.isNotEmpty) 'feedback': s.feedback,
        if (s.parameters.isNotEmpty) 'parameters': s.parameters,
        if (s.coveredScope.isNotEmpty) 'coveredScope': s.coveredScope,
        if (s.tuningParams.isNotEmpty) 'tuningParams': s.tuningParams,
        if (s.edgeCases.isNotEmpty) 'edgeCases': s.edgeCases,
      };
      return Subtask(
        id: s.id,
        text: s.name,
        completed: s.isCompleted,
        children: s.checklist,
        specNotes: jsonEncode(meta),
      );
    }).toList();
    _statesCache[doc.id] = (
      signature: _computeDocStatesSignature(doc),
      states: states,
    );
  }
}
