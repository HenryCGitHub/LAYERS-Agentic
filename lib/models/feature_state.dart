import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/tier_document.dart';

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
    final t = trigger.trim();
    if (t.toLowerCase().startsWith('playtest:')) {
      return t.substring(9).trim();
    }
    if (t.isNotEmpty) return t;
    if (feedback != null && feedback!.trim().isNotEmpty) return feedback!.trim();
    return 'Verify stage deliverables and checklist criteria in game viewport.';
  }

  /// Clean descriptive title of this stage without the "Stage X:" or "[TAG]" prefix.
  String get cleanStageTitle {
    var trimmed = name.trim();
    final tagMatch = RegExp(
      r'^\s*(\[(?:ROUGH PASS|BUILD PASS|FINAL PASS|ROUGH|BUILD|FINAL|PROTOTYPE|CORE|POLISH|TEST)\])\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (tagMatch != null && tagMatch.group(2)!.trim().isNotEmpty) {
      trimmed = tagMatch.group(2)!.trim();
    }
    final match =
        RegExp(r'^\s*Stage\s*\d+\s*[:\-]\s*(.*)$', caseSensitive: false)
            .firstMatch(trimmed);
    if (match != null && match.group(1)!.trim().isNotEmpty) {
      return match.group(1)!.trim();
    }
    // If name is just "Stage 1", try to use trigger or fallback
    if (RegExp(r'^\s*Stage\s*\d+\s*$', caseSensitive: false)
        .hasMatch(trimmed)) {
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

  /// Checks whether a list of subtasks contains the legacy 4 stages (Plan, Setup, Build, Test).
  static bool isLegacyStageSubtasks(List<Subtask> subtasks) {
    if (subtasks.isEmpty) return false;
    final stagePattern =
        RegExp(r'^\s*(\(\d+h?\)\s*)?(Plan|Setup|Build|Test)\b', caseSensitive: false);
    return subtasks.any((st) => stagePattern.hasMatch(st.text));
  }

  /// Checks whether a list of state nodes contains the legacy 4 stages (Plan, Setup, Build, Test).
  static bool isLegacyStateNodes(List<FeatureStateNode> nodes) {
    if (nodes.isEmpty) return false;
    final stagePattern =
        RegExp(r'^\s*(\(\d+h?\)\s*)?(Plan|Setup|Build|Test)\b', caseSensitive: false);
    return nodes.any((n) => stagePattern.hasMatch(n.name));
  }

  /// Auto-heals legacy or corrupted stage nodes (e.g. missing titles, raw JSON in parameters/trigger).
  static void autoHealStageNodes(TierDocument doc, List<FeatureStateNode> nodes) {
    if (nodes.isEmpty) return;
    bool modified = false;
    final defaults = generateDefaultStates(doc.title);

    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];

      // 1. Remove corrupted parameters with raw JSON keys
      if (node.parameters.keys.any((k) => k.contains('{') || k.contains('"'))) {
        node.parameters.clear();
        modified = true;
      }

      // 2. Clean up corrupted trigger containing raw JSON
      if (node.trigger.trim().startsWith('{')) {
        try {
          final decoded = jsonDecode(node.trigger);
          if (decoded is Map && decoded['trigger'] != null) {
            node.trigger = decoded['trigger'].toString();
            modified = true;
          }
        } catch (_) {
          if (i < defaults.length) {
            node.trigger = defaults[i].trigger;
            modified = true;
          }
        }
      }

      // 3. Heal missing stage titles if node.name is just "Stage 1", "Stage 2", etc.
      final bareStageMatch = RegExp(r'^\s*Stage\s*(\d+)\s*$', caseSensitive: false).firstMatch(node.name);
      if (bareStageMatch != null) {
        final stageNum = bareStageMatch.group(1);
        String? healedTitle;
        // Check if trigger was actually the title (e.g. "Graybox Input & Slide State Entry")
        if (node.trigger.isNotEmpty &&
            !node.trigger.toLowerCase().startsWith('playtest:') &&
            !node.trigger.toLowerCase().startsWith('feature') &&
            !node.trigger.contains('{') &&
            node.trigger.length < 50) {
          healedTitle = node.trigger;
          if (i < defaults.length) {
            node.trigger = defaults[i].trigger;
          }
        } else if (i < defaults.length) {
          healedTitle = defaults[i].cleanStageTitle;
        }
        if (healedTitle != null && healedTitle.isNotEmpty) {
          node.name = 'Stage $stageNum: $healedTitle';
          modified = true;
        }
      }
    }

    if (modified) {
      saveStatesToDocument(doc, nodes);
    }
  }

  /// Fallback generator for default operational stages.
  ///
  /// Implements 2-Stage Express Collapse (for atomic/simple features)
  /// vs 4-Stage Pipeline (for standard/dynamic features), with the strict
  /// 4-task schema (`[PREREQ]`, `[BUILD]`, `[HOOK]`, `[TEST]`).
  static List<FeatureStateNode> generateDefaultStates(
    String title, {
    String? targetFile,
  }) {
    final lower = title.toLowerCase();

    // Mode A: 2-Cut Express Collapse for atomic / simple features
    final isAtomic = lower.contains('toggle') ||
        lower.contains('mute') ||
        lower.contains('brightness') ||
        lower.contains('slider') ||
        lower.contains('volume') ||
        lower.contains('flashlight') ||
        lower.contains('switch') ||
        lower.contains('fov') ||
        lower.contains('gamma');

    if (isAtomic) {
      return [
        FeatureStateNode(
          id: generateUniqueId('stage'),
          name: '[PROTOTYPE] $title Signal Path',
          trigger: 'Playtest: Trigger input toggles boolean/scalar state and prints debug confirmation.',
          checklist: [
            Subtask(
              id: generateUniqueId('step'),
              text: '[PREREQ] Setup input action and component prerequisites in target scene',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[BUILD] Declare state property and toggle method in primary script',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[HOOK] Bind action trigger in input controller or UI event listener',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[TEST] In-editor test - Trigger action and confirm state flips in console/inspector',
            ),
          ],
          order: 0,
        ),
        FeatureStateNode(
          id: generateUniqueId('stage'),
          name: '[FINAL] Production Loop & Boundary Safety',
          trigger: 'Playtest: State updates live asset, clamps bounds, and persists across sessions.',
          checklist: [
            Subtask(
              id: generateUniqueId('step'),
              text: '[PREREQ] Configure settings schema and storage serialization asset',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[BUILD] Clamp values within valid bounds and serialize to settings storage',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[HOOK] Bind state change to audio/VFX/UI response and save event',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[TEST] Playtest - Value persists across reload with correct audio/visual feedback',
            ),
          ],
          order: 1,
        ),
      ];
    }

    final isCombat = lower.contains('attack') ||
        lower.contains('weapon') ||
        lower.contains('sword') ||
        lower.contains('swing') ||
        lower.contains('strike') ||
        lower.contains('combat') ||
        lower.contains('damage') ||
        lower.contains('shoot') ||
        lower.contains('fire');

    if (isCombat) {
      return [
        FeatureStateNode(
          id: generateUniqueId('stage'),
          name: '[PROTOTYPE] Attack Trigger & Hitbox Stub',
          trigger: 'Playtest: Left-click triggers windup animation and draws debug sweep ray in under 60m.',
          checklist: [
            Subtask(
              id: generateUniqueId('step'),
              text: '[PREREQ] Author placeholder weapon mesh and setup actor combat socket',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[BUILD] Add attack state flag and forward step vector in primary controller',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[HOOK] Bind IA_Attack input event and connect weapon socket to character mesh',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[TEST] Playtest - Press attack and verify character steps forward with debug ray',
            ),
          ],
          order: 0,
        ),
        FeatureStateNode(
          id: generateUniqueId('stage'),
          name: '[CORE] Swing Mechanics & Trace Damage',
          trigger: 'Playtest: Weapon collision sweep detects training dummy and applies base damage.',
          checklist: [
            Subtask(
              id: generateUniqueId('step'),
              text: '[PREREQ] Create blade swing sound cue and attack animation asset references',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[BUILD] Implement multi-sphere collision trace and damage formula calculation',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[HOOK] Hook attack montage animation and continuous blade swoosh audio cue',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[TEST] Playtest - Swing into dummy to verify hit detection and health reduction',
            ),
          ],
          order: 1,
        ),
        FeatureStateNode(
          id: generateUniqueId('stage'),
          name: '[POLISH] Impact Hitstop & Crunch Juice',
          trigger: 'Playtest: Sparks fly at impact; 60ms animation freeze; bass thud audio plays.',
          checklist: [
            Subtask(
              id: generateUniqueId('step'),
              text: '[PREREQ] Author metal spark Niagara particle system and impact audio cue',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[BUILD] Implement 60ms time dilation freeze and combo window buffer (300ms-500ms)',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[HOOK] Spawn metal spark particle burst and trigger crunch audio layer on impact',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[TEST] Playtest - Attack enemy and confirm hitstop feel and combo timing',
            ),
          ],
          order: 2,
        ),
        FeatureStateNode(
          id: generateUniqueId('stage'),
          name: '[TEST] Stamina Depletion & Boundary Safety',
          trigger: 'Playtest: Deducts 20 stamina; rejects attack at 0 stamina without hitching.',
          checklist: [
            Subtask(
              id: generateUniqueId('step'),
              text: '[PREREQ] Configure stamina attributes and exhausted warning UI widget',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[BUILD] Enforce stamina cost clamp, null checks on target, and recovery cooldown',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[HOOK] Bind low-stamina exhaustion audio cue and UI warning toast',
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[TEST] QA Sign-off - Execute 10 consecutive swings; verify clean stamina rejection',
            ),
          ],
          order: 3,
        ),
      ];
    }

    final isMovement = lower.contains('slide') ||
        lower.contains('dash') ||
        lower.contains('sprint') ||
        lower.contains('hop') ||
        lower.contains('jump') ||
        lower.contains('vault') ||
        lower.contains('run') ||
        lower.contains('movement') ||
        lower.contains('locomotion') ||
        lower.contains('parkour') ||
        lower.contains('wall');

    if (isMovement) {
      return [
        FeatureStateNode(
          id: generateUniqueId('stage'),
          name: '[PROTOTYPE] Basic Locomotion Action',
          trigger: 'Playtest: Press input; state sets to active and debug velocity vector draws.',
          checklist: [
            Subtask(
              id: generateUniqueId('step'),
              text: '[PREREQ] Setup input action IA_Move and ensure CharacterMovementComponent on pawn',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Create Input Action IA_Move asset and assign to default input mapping context',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Verify CharacterMovementComponent exists on player pawn with default walk speed',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[BUILD] Add movement state flag and forward impulse calculation in character controller',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Declare bIsMoving state boolean and speed threshold constants',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Implement forward impulse acceleration calculation in controller tick',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[HOOK] Bind input action trigger and hook character movement component reference',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Bind IA input action trigger delegate to locomotion component',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Connect debug log and viewport velocity vector line draw',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[TEST] Playtest - Press input and verify character moves forward with debug log',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Press input and verify character moves forward with debug line in viewport',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Confirm state flag sets to active without hitching or frame drops',
                ),
              ],
            ),
          ],
          order: 0,
        ),
        FeatureStateNode(
          id: generateUniqueId('stage'),
          name: '[CORE] Kinematic Physics & Motion',
          trigger: 'Playtest: Movement traverses flat and sloped surfaces with smooth animation blend.',
          checklist: [
            Subtask(
              id: generateUniqueId('step'),
              text: '[PREREQ] Author footstep audio cue and ground material physics assets',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Create physical material presets for concrete, dirt, and metal surfaces',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Assign starter footstep audio cue references to surface sound table',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[BUILD] Implement surface normal projection, gravity damping, and velocity curve',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Calculate ground normal vector projection and gravity damping factor',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Apply deceleration friction decay curve on flat surfaces',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[HOOK] Bind primary movement animation blendspace and surface footstep sound cue',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Bind primary movement animation blendspace to current locomotion speed',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Hook surface footstep audio event with material-based audio cues',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[TEST] Playtest - Traverse graybox testing track and verify smooth locomotion loop',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Traverse flat and sloped surfaces and confirm smooth blend transitions',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Confirm footstep sound plays in sync with movement cycle cadence',
                ),
              ],
            ),
          ],
          order: 1,
        ),
        FeatureStateNode(
          id: generateUniqueId('stage'),
          name: '[POLISH] Interrupt Branch & Camera Juice',
          trigger: 'Playtest: Jump cancels action; camera tilts 12°; wind audio layer triggers.',
          checklist: [
            Subtask(
              id: generateUniqueId('step'),
              text: '[PREREQ] Author dust particle emitter and setup camera boom tilt settings',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Create placeholder dust puff Niagara particle system template',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Verify player CameraBoom has lag and roll tilt parameters enabled',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[BUILD] Implement jump-cancel impulse, slope acceleration bonus, and turn steering',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Implement jump-cancel momentum preservation and slope boost bonus',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Add directional turn steering interpolation curve',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[HOOK] Apply 12° camera roll, FOV stretch (+5°), and dust particle emitter',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Apply 12-degree camera roll and dynamic FOV stretch (+5 deg)',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Attach dust particle emitter and wind audio bus layer to actor',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[TEST] Playtest - Perform jump-cancel mid-movement and verify camera feel and particles',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Perform jump-cancel mid-movement and verify camera feel and particles',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Confirm sound layer smoothly fades upon movement exit',
                ),
              ],
            ),
          ],
          order: 2,
        ),
        FeatureStateNode(
          id: generateUniqueId('stage'),
          name: '[TEST] Collision Safety & Safeguards',
          trigger: 'Playtest: Surface ends safely trigger disengage; zero snagging across 90° corners.',
          checklist: [
            Subtask(
              id: generateUniqueId('step'),
              text: '[PREREQ] Setup testing gym collision bounds and telemetry debug logger',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Construct 90-degree corner obstacles and ledge dropoffs in testing level',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Configure telemetry logger channel for velocity clipping assertions',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[BUILD] Handle surface edge drop, zero-stamina slip, and depenetration collision clamps',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Handle surface ledge drop and depenetration collision clamps',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Add zero-stamina slip gating and velocity ceiling clamp',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[HOOK] Connect fall-state recovery transition and telemetry speed assert',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Connect fall-state recovery transition and physics error logging',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Wire telemetry speed assertion logger for clipping detection',
                ),
              ],
            ),
            Subtask(
              id: generateUniqueId('step'),
              text: '[TEST] Telemetry Pass - Verify character maintains expected velocity ± 5% across corners',
              children: [
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Navigate 90-degree corners and confirm zero snagging or clipping',
                ),
                Subtask(
                  id: generateUniqueId('sub'),
                  text: 'Confirm velocity stays within expected range across dropoffs',
                ),
              ],
            ),
          ],
          order: 3,
        ),
      ];
    }

    // Default Generic 4-Stage Pipeline
    return [
      FeatureStateNode(
        id: generateUniqueId('stage'),
        name: '[PROTOTYPE] Basic Core Action',
        trigger: 'Playtest: Trigger action -> observe immediate on-screen/console reaction in <60m.',
        checklist: [
          Subtask(
            id: generateUniqueId('step'),
            text: '[PREREQ] Setup input action and target actor component prerequisites',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Create input action asset and bind to default character mapping context',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Attach necessary actor components (Collision, Mesh, Audio) in viewport',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[BUILD] Implement minimal stub state transition and data placeholder',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Declare state variable and speed threshold constants',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Implement transition gating check and half-height capsule shrink',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[HOOK] Bind trigger event dispatcher and component reference',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Bind IA input actions to execution delegates in component',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Connect visual feedback and audio trigger components',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[TEST] Test trigger in viewport to verify signal path proof',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Trigger action in test gym and verify state activates in inspector',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Verify horizontal speed sustains without stalling or frame hitches',
              ),
            ],
          ),
        ],
        order: 0,
      ),
      FeatureStateNode(
        id: generateUniqueId('stage'),
        name: '[CORE] Controls & Movement Rules',
        trigger: 'Playtest: Execute standard workflow -> core logic functions with primary audio/visuals.',
        checklist: [
          Subtask(
            id: generateUniqueId('step'),
            text: '[PREREQ] Configure core asset references and primary audio cues',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Assign primary audio sound cue to character audio manager',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Verify default mesh textures and skeletal animation assets resolve',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[BUILD] Implement core operational logic, rules, and mathematical calculations',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Implement ground normal slope force projection and decay curves',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Apply parameter limits and directional movement rules',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[HOOK] Bind primary visual elements, asset textures, and baseline audio loops',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Attach looping sound component and modulate pitch dynamically',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Bind primary animation states and asset textures',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[TEST] Verify complete happy-path execution without edge failures',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Test full happy path loop across test surface',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Verify velocity continuously scales without artificial clamping',
              ),
            ],
          ),
        ],
        order: 1,
      ),
      FeatureStateNode(
        id: generateUniqueId('stage'),
        name: '[POLISH] Audio Juice & Particle FX',
        trigger: 'Playtest: Trigger branch/interrupt -> system responds dynamically with feedback juice.',
        checklist: [
          Subtask(
            id: generateUniqueId('step'),
            text: '[PREREQ] Author particle feedback template and configure camera shake asset',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Create placeholder particle system emitter template for dynamic interrupt',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Create CameraShake pattern asset with pitch/roll oscillation frequencies',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[BUILD] Implement cancellation branches, parameter modulation, and dynamic interrupts',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Add jump cancel momentum handoff logic and camera offset interpolation',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Implement recovery transition curves and dynamic parameter modulation',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[HOOK] Hook secondary audio sweeteners, screen shake/motion, and particle effects',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Bind jump input delegate to vector preservation and deep bass sound cue',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Trigger camera roll and particle trailing bursts',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[TEST] Test interrupt handling and verify polished sensory response',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Initiate action and jump immediately; confirm momentum preserves into air',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Verify polished audio and particle response upon interrupt',
              ),
            ],
          ),
        ],
        order: 2,
      ),
      FeatureStateNode(
        id: generateUniqueId('stage'),
        name: '[TEST] Boundary Safeguards & Recovery',
        trigger: 'Playtest: Stress-test limits and failure modes -> graceful recovery and telemetry assert.',
        checklist: [
          Subtask(
            id: generateUniqueId('step'),
            text: '[PREREQ] Setup boundary test bounds and error assertion logging',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Create confined test duct and overhang geometry in testing gym',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Configure diagnostics channel for stuck capsule error reports',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[BUILD] Apply clamping, null guards, timeout rollbacks, and recovery handlers',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Implement capsule sweep collision checks under low obstacle overhangs',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Apply clamping and safety fallbacks for airborne floor disconnects',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[HOOK] Connect telemetry metrics logging and error notification triggers',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Wire telemetry assertion logs for zero-velocity clipping',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Connect capsule stuck states logger to diagnostics system',
              ),
            ],
          ),
          Subtask(
            id: generateUniqueId('step'),
            text: '[TEST] QA Pass - Verify 0 errors under boundary stress and corrupt input conditions',
            children: [
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Slide under 1.2m duct and confirm player cannot stand until clear',
              ),
              Subtask(
                id: generateUniqueId('sub'),
                text: 'Slide off sheer cliff ledge to verify zero velocity hitching',
              ),
            ],
          ),
        ],
        order: 3,
      ),
    ];
  }

  /// Extracts the dynamic state nodes for a given feature document.
  static List<FeatureStateNode> getStatesForDocument(TierDocument doc) {
    final rawJson = doc.sections['states'];
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          final nodes = decoded
              .whereType<Map<String, dynamic>>()
              .map((j) => FeatureStateNode.fromJson(j))
              .toList();
          if (nodes.isNotEmpty && !isLegacyStateNodes(nodes)) {
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
            autoHealStageNodes(doc, nodes);
            return nodes;
          }
        }
      } catch (_) {}
    }

    // Auto-heal: If legacy 4-stage pipeline is detected in subtasks, replace with domain dynamic states
    if (isLegacyStageSubtasks(doc.subtasks)) {
      final generated = generateDefaultStates(doc.title);
      saveStatesToDocument(doc, generated);
      return generated;
    }

    // Fallback: derive from doc.subtasks if available and NOT legacy 4-stage pipeline
    if (doc.subtasks.isNotEmpty) {
      int orderIdx = 0;
      final nodes = doc.subtasks.map((st) {
        return FeatureStateNode.fromSubtask(st, order: orderIdx++);
      }).toList();
      autoHealStageNodes(doc, nodes);
      return nodes;
    }

    // Default: 1 clean initial state for unpopulated cards
    return [
      FeatureStateNode(
        id: generateUniqueId('state'),
        name: 'Idle / Entry',
        trigger: 'Feature initialized',
        order: 0,
      )
    ];
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
  }
}

/// Represents a single checkable "How-To" sub-step inside a Parent Task's walkthrough.
class TaskHowToSubStep {
  final Subtask subtask;
  final String stepNumberLabel; // e.g., "STEP 1.1 · READ INPUT & STATE"
  final String instruction;     // Concrete implementation instruction
  final String codeFormula;     // Short code / formula snippet
  final bool isGuardStep;

  const TaskHowToSubStep({
    required this.subtask,
    required this.stepNumberLabel,
    required this.instruction,
    required this.codeFormula,
    this.isGuardStep = false,
  });
}

/// Synthesizes mechanic-specific scope bullets, tuning parameters, edge-case guards,
/// and 60/40 Playable Checkpoint blueprints for any custom or Beat-derived feature title.
class MechanicArchetypeProfile {
  final String category; // 'grapple', 'movement', 'combat', 'farming', 'economy', 'building', 'ui', 'core'
  final String goal;
  final String doneWhen;
  final List<String> inScope;
  final List<String> outOfScope;
  final List<String> tuningParams;
  final List<String> edgeCases;
  final String cp1Title;
  final String cp1Playtest;
  final List<String> cp1Tasks;
  final String cp2Title;
  final String cp2Playtest;
  final List<String> cp2Tasks;

  const MechanicArchetypeProfile({
    required this.category,
    required this.goal,
    required this.doneWhen,
    required this.inScope,
    required this.outOfScope,
    required this.tuningParams,
    required this.edgeCases,
    required this.cp1Title,
    required this.cp1Playtest,
    required this.cp1Tasks,
    required this.cp2Title,
    required this.cp2Playtest,
    required this.cp2Tasks,
  });

  static String inferCategory(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('grappl') ||
        lower.contains('hook') ||
        lower.contains('swing') ||
        lower.contains('rope') ||
        lower.contains('tether') ||
        lower.contains('zipline')) {
      return 'grapple';
    }
    if (lower.contains('dash') ||
        lower.contains('slide') ||
        lower.contains('jump') ||
        lower.contains('wall') ||
        lower.contains('sprint') ||
        lower.contains('climb') ||
        lower.contains('move') ||
        lower.contains('locomotion') ||
        lower.contains('parkour')) {
      return 'movement';
    }
    if (lower.contains('shotgun') ||
        lower.contains('weapon') ||
        lower.contains('gun') ||
        lower.contains('shoot') ||
        lower.contains('fire') ||
        lower.contains('attack') ||
        lower.contains('combat') ||
        lower.contains('slash') ||
        lower.contains('enemy') ||
        lower.contains('wave') ||
        lower.contains('turret') ||
        lower.contains('boss') ||
        lower.contains('damage')) {
      return 'combat';
    }
    if (lower.contains('crop') ||
        lower.contains('farm') ||
        lower.contains('plant') ||
        lower.contains('harvest') ||
        lower.contains('seed') ||
        lower.contains('soil') ||
        lower.contains('water') ||
        lower.contains('forag')) {
      return 'farming';
    }
    if (lower.contains('shop') ||
        lower.contains('buy') ||
        lower.contains('sell') ||
        lower.contains('smelt') ||
        lower.contains('furnace') ||
        lower.contains('craft') ||
        lower.contains('invent') ||
        lower.contains('loot') ||
        lower.contains('ore') ||
        lower.contains('loadout') ||
        lower.contains('upgrade')) {
      return 'economy';
    }
    if (lower.contains('grid') ||
        lower.contains('build') ||
        lower.contains('place') ||
        lower.contains('construct') ||
        lower.contains('tile') ||
        lower.contains('snap')) {
      return 'building';
    }
    if (lower.contains('camera') ||
        lower.contains('hud') ||
        lower.contains('ui') ||
        lower.contains('radar') ||
        lower.contains('minimap') ||
        lower.contains('menu') ||
        lower.contains('medal') ||
        lower.contains('score') ||
        lower.contains('timer')) {
      return 'ui';
    }
    return 'core';
  }

  static MechanicArchetypeProfile fromFeatureTitle(
    String rawTitle, {
    String? beatTitle,
    String? beatDescription,
  }) {
    final clean = rawTitle.trim().isEmpty ? 'Core Mechanic' : rawTitle.trim();
    // First inspect the feature title itself; only fall back to beat context if the feature title is generic
    final titleCat = inferCategory(clean);
    final cat = titleCat != 'core'
        ? titleCat
        : inferCategory('$clean ${beatTitle ?? ''} ${beatDescription ?? ''}');

    switch (cat) {
      case 'grapple':
        return MechanicArchetypeProfile(
          category: 'grapple',
          goal: 'Build $clean raycast targeting, tether pull velocity, and release momentum.',
          doneWhen: 'Player fires $clean at valid anchors, swings/pulls smoothly at 60 FPS, and keeps momentum on release.',
          inScope: [
            'Anchor raycast check and tether line rendering for $clean',
            'Pull/swing velocity impulse and release momentum transfer',
          ],
          outOfScope: [
            'Multi-segment Verlet rope wrapping around complex meshes',
          ],
          tuningParams: const [
            'hookMaxRange: 18.0 m',
            'hookPullSpeed: 28.0 m/s',
            'releaseBoostMultiplier: 1.25 x',
          ],
          edgeCases: const [
            '[LOS BREAK GUARD] Detach tether cleanly if moving obstacle blocks line of sight',
            '[MAX TENSION CLAMP] Clamp velocity on release so frame spikes never launch player out of bounds',
          ],
          cp1Title: '$clean Targeting & Pull Velocity',
          cp1Playtest: 'Aim at anchor within hookMaxRange and fire -> player pulls toward anchor and releases with momentum.',
          cp1Tasks: [
            'Implement anchor raycast check and tether state entry for $clean (2h)',
            'Apply hookPullSpeed velocity and releaseBoostMultiplier on detach (2h)',
          ],
          cp2Title: 'Tether Visual Line & Detach Guards',
          cp2Playtest: 'Break line-of-sight mid-pull -> tether detaches cleanly with audio/visual cue and zero physics hitch.',
          cp2Tasks: [
            'Render active tether line and attach/detach audio-visual cues (1h)',
            'Enforce line-of-sight break guard and velocity clamp for $clean (1h)',
          ],
        );

      case 'movement':
        return MechanicArchetypeProfile(
          category: 'movement',
          goal: 'Build responsive $clean input handling, velocity acceleration, and recovery timing.',
          doneWhen: 'Player chains $clean smoothly across arena obstacles with zero input drop or wall-clip.',
          inScope: [
            'Directional input read, acceleration curve, and velocity impulse for $clean',
            'Screen-feel feedback (FOV kick / dust particles) and cooldown recovery',
          ],
          outOfScope: [
            'Procedural skeletal IK foot placement',
          ],
          tuningParams: const [
            'moveMaxSpeed: 240.0 px/s',
            'burstImpulseSpeed: 420.0 px/s',
            'moveCooldownSec: 0.35 s',
          ],
          edgeCases: const [
            '[CORNER SLIDE GUARD] Slide smoothly along wall normals without zeroing tangential velocity',
            '[BUFFER WINDOW] Queue input pressed 0.10s before landing or cooldown expiry',
          ],
          cp1Title: '$clean Velocity & Physics Loop',
          cp1Playtest: 'Trigger $clean while moving -> character accelerates to burstImpulseSpeed and slides cleanly along walls.',
          cp1Tasks: [
            'Bind directional input and velocity impulse math for $clean (2h)',
            'Enforce wall-slide normal projection and cooldown recovery timer (2h)',
          ],
          cp2Title: '$clean Feel Cues & Input Buffer',
          cp2Playtest: 'Chain $clean repeatedly -> verify 0.10s input buffer and crisp FOV/trail feedback.',
          cp2Tasks: [
            'Hook up motion trail / FOV kick and sound cue on $clean trigger (1h)',
            'Verify input buffer window and mid-air transition guard (1h)',
          ],
        );

      case 'combat':
        return MechanicArchetypeProfile(
          category: 'combat',
          goal: 'Build $clean hit detection, damage/knockback application, and reload/cooldown pacing.',
          doneWhen: 'Player engages targets with $clean, registers crisp hit-confirm feedback, and clears enemy waves reliably.',
          inScope: [
            'Hitbox / raycast detection, damage application, and knockback impulse for $clean',
            'Muzzle / impact flash, hit-stop frame, and ammo / cooldown HUD readout',
          ],
          outOfScope: [
            'limb-specific gore dismemberment physics',
          ],
          tuningParams: const [
            'baseDamage: 25.0 hp',
            'fireCooldownSec: 0.45 s',
            'knockbackImpulse: 14.0 m/s',
          ],
          edgeCases: const [
            '[HIT-ONCE GUARD] Single attack swing or projectile hit-reg applies damage exactly once per target ID',
            '[RELOAD INTERRUPT] Dodging or swapping mid-reload cancels reload timer cleanly without ammo duplication',
          ],
          cp1Title: '$clean Hit Detection & Knockback',
          cp1Playtest: 'Fire/trigger $clean at test target -> deducts baseDamage, applies knockbackImpulse, and respects fireCooldownSec.',
          cp1Tasks: [
            'Implement raycast/hitbox query and baseDamage application for $clean (2h)',
            'Apply knockbackImpulse and enforce single-hit-per-target guard (2h)',
          ],
          cp2Title: 'Impact Feel & Cooldown Readout',
          cp2Playtest: 'Rapid-fire $clean in arena -> verify hit-flash, audio punch, and clean reload/cooldown interrupt.',
          cp2Tasks: [
            'Hook up target hit-flash, impact SFX, and HUD ammo/cooldown bar (1h)',
            'Verify reload/cooldown interrupt guard when switching states (1h)',
          ],
        );

      case 'farming':
        return MechanicArchetypeProfile(
          category: 'farming',
          goal: 'Build $clean plot interaction, growth stage timer progression, and harvest item yield.',
          doneWhen: 'Player plants, grows, and harvests crops via $clean with clear stage visuals and inventory pickup.',
          inScope: [
            'Plot tile state machine (Empty -> Planted -> Growing -> Ready) for $clean',
            'Growth tick timer, harvest pickup spawn, and plot reset',
          ],
          outOfScope: [
            'Seasonal weather simulation and soil pH chemistry',
          ],
          tuningParams: const [
            'growthStageDuration: 12.0 s',
            'harvestYieldCount: 3 items',
            'interactRadius: 1.8 m',
          ],
          edgeCases: const [
            '[OCCUPIED PLOT GUARD] Prevent planting a second seed on an already planted tile',
            '[FULL INVENTORY DROP] If player storage is full on harvest, spawn pickup item on ground instead of deleting yield',
          ],
          cp1Title: '$clean Plot State & Growth Timer',
          cp1Playtest: 'Interact with empty plot -> plants seed, advances through growthStageDuration, and marks Ready.',
          cp1Tasks: [
            'Implement plot state machine and growthStageDuration tick timer for $clean (2h)',
            'Enforce occupied-plot guard and interaction range check (1h)',
          ],
          cp2Title: 'Harvest Yield & Visual Stage Cues',
          cp2Playtest: 'Harvest mature plot -> spawns harvestYieldCount items, plays pop cue, and resets plot to Empty.',
          cp2Tasks: [
            'Spawn harvestYieldCount items on harvest and update storage readout (1h)',
            'Hook up stage sprite swap and full-inventory overflow drop guard (1h)',
          ],
        );

      case 'economy':
        return MechanicArchetypeProfile(
          category: 'economy',
          goal: 'Build $clean item transaction logic, resource count validation, and immediate UI inventory sync.',
          doneWhen: 'Player executes $clean transactions with accurate resource deduction/addition and zero duplicate item bugs.',
          inScope: [
            'Resource requirement check, count delta math, and output grant for $clean',
            'Slot highlight, transaction sound cue, and live counter readout',
          ],
          outOfScope: [
            'Dynamic NPC supply-and-demand market inflation',
          ],
          tuningParams: const [
            'transactionCostBase: 25 gold',
            'processDurationSec: 2.0 s',
            'stackMaxCapacity: 99 items',
          ],
          edgeCases: const [
            '[INSUFFICIENT FUNDS GUARD] Block transaction and flash cost label red when resources < transactionCostBase',
            '[STACK CAP CLAMP] Clamp slot count at stackMaxCapacity and spill remainder to next open slot',
          ],
          cp1Title: '$clean Transaction & Resource Math',
          cp1Playtest: 'Trigger $clean with valid resources -> deducts cost, grants output, and updates inventory count.',
          cp1Tasks: [
            'Implement resource check and inventory delta math for $clean (2h)',
            'Enforce insufficient-funds and stackMaxCapacity overflow guards (1h)',
          ],
          cp2Title: '$clean UI Readout & Audio Cues',
          cp2Playtest: 'Attempt $clean both with and without enough resources -> verify confirm chime vs. red reject flash.',
          cp2Tasks: [
            'Wire live resource counter labels and slot highlight for $clean (1h)',
            'Hook up transaction confirm SFX and insufficient-resource shake cue (1h)',
          ],
        );

      case 'building':
        return MechanicArchetypeProfile(
          category: 'building',
          goal: 'Build $clean grid coordinate snapping, placement collision check, and structure instantiation.',
          doneWhen: 'Player previews ghost placement on the grid, validates clear cells, and places/removes structures cleanly.',
          inScope: [
            'World-to-grid coordinate snapping and cell occupancy lookup for $clean',
            'Valid/invalid ghost preview tint and placement confirmation cue',
          ],
          outOfScope: [
            'Structural physics collapse simulation',
          ],
          tuningParams: const [
            'gridCellSize: 32.0 px',
            'placeReachDistance: 4.5 tiles',
            'refundRatio: 1.0 x',
          ],
          edgeCases: const [
            '[OVERLAP GUARD] Block placement and tint ghost red when target cell is occupied or overlaps player collider',
            '[BOUNDARY CLAMP] Reject grid coordinates outside valid build bounds',
          ],
          cp1Title: '$clean Grid Snapping & Cell Occupancy',
          cp1Playtest: 'Move cursor across arena -> ghost snaps to gridCellSize steps and places structure on open cell.',
          cp1Tasks: [
            'Implement world-to-grid snapping and cell occupancy dictionary for $clean (2h)',
            'Instantiate placed structure and block overlapping cells (1h)',
          ],
          cp2Title: 'Placement Ghost Tint & Removal Guard',
          cp2Playtest: 'Hover over occupied cell -> ghost tints red and blocks click; right-click removes and refunds cleanly.',
          cp2Tasks: [
            'Wire green/red ghost preview shader and placement thud SFX (1h)',
            'Enforce player-overlap guard and clean cell release on removal (1h)',
          ],
        );

      case 'ui':
        return MechanicArchetypeProfile(
          category: 'ui',
          goal: 'Build $clean state binding, smooth camera/HUD interpolation, and threshold notifications.',
          doneWhen: 'Camera and HUD readouts for $clean update at 60 FPS in sync with gameplay state changes.',
          inScope: [
            'Event-driven HUD readout binding and smooth interpolation for $clean',
            'Threshold pop animation and clean reset on round restart',
          ],
          outOfScope: [
            'Custom remappable HUD layout editor',
          ],
          tuningParams: const [
            'cameraFollowLerp: 14.0',
            'hudPopScale: 1.18 x',
            'readoutLerpSpeed: 10.0',
          ],
          edgeCases: const [
            '[ARENA BOUND CLAMP] Clamp camera and off-screen indicators cleanly at level edges',
            '[RAPID EVENT DEBOUNCE] Coalesce simultaneous state changes in the same frame without UI flicker',
          ],
          cp1Title: '$clean State Signal & Smooth Readout',
          cp1Playtest: 'Trigger state change in arena -> $clean updates immediately with smooth lerp and zero frame hitch.',
          cp1Tasks: [
            'Subscribe $clean presenter to gameplay state signal and update readout (2h)',
            'Apply cameraFollowLerp / readoutLerpSpeed smoothing and arena bound clamp (2h)',
          ],
          cp2Title: 'Threshold Callout & Reset Cleanup',
          cp2Playtest: 'Cross target threshold and reset round -> badge animates once and resets cleanly.',
          cp2Tasks: [
            'Trigger hudPopScale callout animation and audio chime on threshold (1h)',
            'Enforce rapid-event debounce and clean HUD reset on loop restart (1h)',
          ],
        );

      default:
        final descSuffix = (beatDescription != null && beatDescription.trim().isNotEmpty)
            ? ' (${beatDescription.trim()})'
            : '';
        return MechanicArchetypeProfile(
          category: 'core',
          goal: 'Build playable $clean mechanics, state transitions, and player feedback$descSuffix.',
          doneWhen: 'Playtester can execute $clean reliably at 60 FPS with immediate visual and audio confirmation.',
          inScope: [
            'Core player input, state transition logic, and active execution for $clean',
            'Immediate on-screen visual/audio feedback and clean transition to next beat',
          ],
          outOfScope: [
            'Final production art shaders and meta-progression unlocks for $clean',
          ],
          tuningParams: const [
            'actionResponseWindow: 0.10 s',
            'stateCooldownSec: 0.25 s',
          ],
          edgeCases: const [
            '[INPUT GUARD] Rapid repeated inputs during active state transition cleanly without state lock',
          ],
          cp1Title: '$clean Core State & Controls',
          cp1Playtest: 'Trigger $clean in the test arena -> state activates within actionResponseWindow and updates gameplay.',
          cp1Tasks: [
            'Implement player input trigger and state logic for $clean (2h)',
            'Apply actionResponseWindow timing and stateCooldownSec recovery (1h)',
          ],
          cp2Title: '$clean Visual/Audio Cues & Guardrails',
          cp2Playtest: 'Spam input during $clean transition -> feedback plays cleanly and state never locks up.',
          cp2Tasks: [
            'Hook up immediate visual indicator and audio cue for $clean (1h)',
            'Enforce rapid-input state guard and clean reset on round restart (1h)',
          ],
        );
    }
  }
}

/// Resolves and persists the structured Parent Task metadata (`numLabel`, `layerTag`,
/// `cleanTitle`, `durationChip`, `whereLocation`, `engineLabel`) and ensures each Parent Task has
/// 3 checkable `How-To` sub-steps (`Subtask.children`) with automatic rollup and engine-aware code formulas.
class TaskHowToBlueprint {
  final String numLabel;      // "01", "02", ...
  final String layerTag;      // "INPUT", "PHYSICS", "STATE", "FEEL", "UI"
  final String cleanTitle;    // Task title without trailing "(2h)"
  final String durationChip;  // Extracted "2h" or "1h"
  final String whereLocation; // e.g. "Script: PlayerController._physics_process(delta)"
  final String engineLabel;   // "GODOT 4", "UNITY C#", "UNREAL 5"
  final List<TaskHowToSubStep> subSteps;

  const TaskHowToBlueprint({
    required this.numLabel,
    required this.layerTag,
    required this.cleanTitle,
    required this.durationChip,
    required this.whereLocation,
    required this.engineLabel,
    required this.subSteps,
  });

  static final RegExp _trailingDurationRe =
      RegExp(r'\s*\(([\d\.]+\s*[hm])\)\s*$', caseSensitive: false);

  static String detectEngineLabel(String? engineHint) {
    final lower = (engineHint ?? '').toLowerCase();
    if (lower.contains('unity') || lower.contains('c#')) {
      return 'UNITY C#';
    }
    if (lower.contains('unreal') || lower.contains('ue5') || lower.contains('c++')) {
      return 'UNREAL 5';
    }
    return 'GODOT 4';
  }

  static String extractCleanTitle(String rawText) {
    var cleaned = rawText.replaceAll(_trailingDurationRe, '').trim();
    cleaned = cleaned
        .replaceFirst(
          RegExp(r'^\[(?:PREREQ|BUILD|HOOK|TEST|INPUT|STATE|PHYSICS|FEEL|UI)\]\s*',
              caseSensitive: false),
          '',
        )
        .trim();
    return cleaned.isEmpty ? rawText.trim() : cleaned;
  }

  static String extractDurationChip(String rawText) {
    final m = _trailingDurationRe.firstMatch(rawText);
    if (m != null && m.group(1) != null) {
      return m.group(1)!.replaceAll(' ', '');
    }
    return '1h';
  }

  static String inferLayerTag(String rawText, int taskIdx) {
    final lower = rawText.toLowerCase();
    if (lower.contains('input') ||
        lower.contains('control') ||
        lower.contains('key') ||
        lower.contains('mouse') ||
        lower.contains('aim') ||
        lower.contains('strafe')) {
      return 'INPUT';
    }
    if (lower.contains('physic') ||
        lower.contains('velocity') ||
        lower.contains('force') ||
        lower.contains('speed') ||
        lower.contains('gravity') ||
        lower.contains('collision') ||
        lower.contains('raycast') ||
        lower.contains('movement')) {
      return 'PHYSICS';
    }
    if (lower.contains('visual') ||
        lower.contains('audio') ||
        lower.contains('sfx') ||
        lower.contains('vfx') ||
        lower.contains('cue') ||
        lower.contains('camera') ||
        lower.contains('fov') ||
        lower.contains('feel') ||
        lower.contains('feedback') ||
        lower.contains('anim')) {
      return 'FEEL';
    }
    if (lower.contains('hud') ||
        lower.contains('ui') ||
        lower.contains('menu') ||
        lower.contains('indicator') ||
        lower.contains('readout') ||
        lower.contains('badge')) {
      return 'UI / HUD';
    }
    return taskIdx == 0 ? 'STATE' : (taskIdx == 1 ? 'FEEL' : 'LOGIC');
  }

  static String inferWhereLocation(
    String cleanTitle,
    String layerTag, {
    String engineLabel = 'GODOT 4',
  }) {
    if (engineLabel == 'UNITY C#') {
      switch (layerTag) {
        case 'INPUT':
          return 'MonoBehaviour: PlayerInputController.Update()';
        case 'PHYSICS':
          return 'MonoBehaviour: MechanicController.FixedUpdate()';
        case 'FEEL':
          return 'MonoBehaviour: FeedbackPresenter.LateUpdate()';
        case 'UI / HUD':
          return 'MonoBehaviour: GameHudOverlay.RefreshReadout()';
        default:
          return 'MonoBehaviour: CoreLoopStateController.FixedUpdate()';
      }
    }
    if (engineLabel == 'UNREAL 5') {
      switch (layerTag) {
        case 'INPUT':
          return 'ActorComponent: UPlayerInputComp::SetupPlayerInputComponent()';
        case 'PHYSICS':
          return 'ActorComponent: UMechanicComponent::TickComponent(DeltaTime)';
        case 'FEEL':
          return 'ActorComponent: UFeedbackPresenter::TriggerFeelCue()';
        case 'UI / HUD':
          return 'UserWidget: UGameHudWidget::UpdateStateReadout()';
        default:
          return 'ActorComponent: UCoreLoopStateComp::TickComponent(DeltaTime)';
      }
    }
    switch (layerTag) {
      case 'INPUT':
        return 'Script: PlayerController._unhandled_input(event)';
      case 'PHYSICS':
        return 'Script: MechanicController._physics_process(delta)';
      case 'FEEL':
        return 'Scene: FeedbackPresenter & CameraController._process(delta)';
      case 'UI / HUD':
        return 'Scene: GameHudOverlay.update_state_readout()';
      default:
        return 'Script: CoreLoopStateController._physics_process(delta)';
    }
  }

  /// Guarantees that `parentTask.children` contains concrete, checkable "How-To" sub-steps
  /// (Step X.1 Setup/Input, Step X.2 Core Logic + Variables, Step X.3 Edge-Case Guard Check)
  /// adapted to `engineHint` (`GODOT 4`, `UNITY C#`, `UNREAL 5`) and returns the resolved [TaskHowToBlueprint].
  static TaskHowToBlueprint resolve({
    required Subtask parentTask,
    required int taskIndex,
    required FeatureStateNode checkpointNode,
    String? engineHint,
  }) {
    final taskNum = taskIndex + 1;
    final numLabel = taskNum.toString().padLeft(2, '0');
    final cleanTitle = extractCleanTitle(parentTask.text);
    final durationChip = extractDurationChip(parentTask.text);
    final layerTag = inferLayerTag(parentTask.text, taskIndex);
    final engineLabel = detectEngineLabel(engineHint);
    final whereLocation = inferWhereLocation(
      cleanTitle,
      layerTag,
      engineLabel: engineLabel,
    );

    final primaryVar = checkpointNode.tuningParams.isNotEmpty
        ? checkpointNode.tuningParams[taskIndex % checkpointNode.tuningParams.length]
        : 'responseTime: 0.12 s';
    final primaryVarName = primaryVar.split(':').first.trim();
    final primaryGuard = checkpointNode.edgeCases.isNotEmpty
        ? checkpointNode.edgeCases[taskIndex % checkpointNode.edgeCases.length]
        : '[STATE GUARD] Prevent duplicate trigger while active';
    final mechanicCategory = MechanicArchetypeProfile.inferCategory(
      '$cleanTitle ${checkpointNode.name} ${checkpointNode.trigger}',
    );

    String buildEngineSnippet({
      required int stepIdx,
      required bool isFeelOrUi,
    }) {
      if (engineLabel == 'UNITY C#') {
        if (isFeelOrUi) {
          if (stepIdx == 0) {
            return 'mechanicController.OnStateChanged += HandleMechanicStateChanged;';
          } else if (stepIdx == 1) {
            return 'hudIndicator.SetActive(true);\nfeedbackSource.PlayOneShot(cueClip, $primaryVarName);';
          } else {
            return 'if (!isStateActive) { hudIndicator.ResetCleanly(); return; } // Guard: $primaryGuard';
          }
        } else {
          if (stepIdx == 0) {
            if (mechanicCategory == 'grapple') {
              return 'if (Input.GetButtonDown("Fire2") && Physics.Raycast(aimOrigin.position, aimDir, out RaycastHit hit, $primaryVarName)) {\n    activeAnchor = hit.point;\n    activeState = MechanicState.Active;\n}';
            }
            if (mechanicCategory == 'combat') {
              return 'if (Input.GetButton("Fire1") && Time.time >= nextFireTime && CanEnterState()) {\n    activeState = MechanicState.Active;\n}';
            }
            return 'if (Input.GetButton("Fire1") && CanEnterState()) {\n    activeState = MechanicState.Active;\n}';
          } else if (stepIdx == 1) {
            if (mechanicCategory == 'grapple') {
              return 'Vector3 pullDir = (activeAnchor - transform.position).normalized;\nrb.velocity = Vector3.MoveTowards(rb.velocity, pullDir * $primaryVarName, $primaryVarName * Time.fixedDeltaTime);';
            }
            return 'currentVal = Mathf.MoveTowards(currentVal, targetVal, $primaryVarName * Time.fixedDeltaTime);\nApplyMechanicStep(currentVal);';
          } else {
            return 'if (IsBoundaryBlocked() || cooldownTimer > 0f) return; // Guard: $primaryGuard';
          }
        }
      }
      if (engineLabel == 'UNREAL 5') {
        if (isFeelOrUi) {
          if (stepIdx == 0) {
            return 'MechanicComp->OnStateChanged.AddDynamic(this, &UFeedbackPresenter::OnMechanicStateChanged);';
          } else if (stepIdx == 1) {
            return 'HudWidget->SetIndicatorActive(true);\nUGameplayStatics::PlaySound2D(this, CueSound, $primaryVarName);';
          } else {
            return 'if (!bIsStateActive) { HudWidget->ResetCleanly(); return; } // Guard: $primaryGuard';
          }
        } else {
          if (stepIdx == 0) {
            if (mechanicCategory == 'grapple') {
              return 'if (bInputPressed && GetWorld()->LineTraceSingleByChannel(HitResult, StartLoc, EndLoc, ECC_Visibility)) {\n    ActiveAnchor = HitResult.ImpactPoint;\n    ActiveState = EMechanicState::Active;\n}';
            }
            return 'if (bInputPressed && CanEnterState()) {\n    ActiveState = EMechanicState::Active;\n}';
          } else if (stepIdx == 1) {
            return 'CurrentVal = FMath::FInterpConstantTo(CurrentVal, TargetVal, DeltaTime, $primaryVarName);\nApplyMechanicStep(CurrentVal);';
          } else {
            return 'if (IsBoundaryBlocked() || CooldownTimer > 0.f) return; // Guard: $primaryGuard';
          }
        }
      }
      // Default: GODOT 4 (GDScript)
      if (isFeelOrUi) {
        if (stepIdx == 0) {
          return 'mechanicController.state_changed.connect(_on_mechanic_state_changed)';
        } else if (stepIdx == 1) {
          return 'hudIndicator.set_active(true)\nfeedbackPlayer.play_cue(intensity = $primaryVarName)';
        } else {
          return 'if not is_state_active:\n    hudIndicator.reset_cleanly() // Guard: $primaryGuard';
        }
      } else {
        if (stepIdx == 0) {
          if (mechanicCategory == 'grapple') {
            return 'if Input.is_action_pressed("primary_action") and hook_ray.is_colliding() and can_enter_state():\n    activeAnchor = hook_ray.get_collision_point()\n    activeState = State.ACTIVE';
          }
          if (mechanicCategory == 'farming' || mechanicCategory == 'economy' || mechanicCategory == 'building') {
            return 'if Input.is_action_just_pressed("primary_action") and can_enter_state():\n    activeState = State.ACTIVE';
          }
          return 'if Input.is_action_pressed("primary_action") and can_enter_state():\n    activeState = State.ACTIVE';
        } else if (stepIdx == 1) {
          if (mechanicCategory == 'grapple') {
            return 'var pull_dir = global_position.direction_to(activeAnchor)\nvelocity = velocity.move_toward(pull_dir * $primaryVarName, $primaryVarName * delta)\nmove_and_slide()';
          }
          if (mechanicCategory == 'farming') {
            return 'growthTimer = move_toward(growthTimer, $primaryVarName, delta)\nif growthTimer >= $primaryVarName:\n    advance_plot_stage()';
          }
          if (mechanicCategory == 'economy') {
            return 'if currentResources >= $primaryVarName:\n    currentResources -= $primaryVarName\n    grant_transaction_output()';
          }
          if (mechanicCategory == 'building') {
            return 'var grid_cell = local_to_map(get_global_mouse_position())\nplace_structure_at_cell(grid_cell, $primaryVarName)';
          }
          return 'currentValue = move_toward(currentValue, targetValue, $primaryVarName * delta)\napply_mechanic_step(currentValue)';
        } else {
          return 'if is_boundary_blocked() or cooldownTimer > 0.0:\n    return // Guard: $primaryGuard';
        }
      }
    }

    final isFeelOrUi = layerTag == 'FEEL' || layerTag == 'UI / HUD';

    if (parentTask.children.isEmpty) {
      final isParentCompleted = parentTask.completed;
      if (isFeelOrUi) {
        parentTask.children = [
          Subtask(
            id: '${parentTask.id}_sub_1',
            text: 'STEP $taskNum.1 · BIND STATE CHANGE SIGNAL TO VISUAL/AUDIO PRESENTER',
            specNotes:
                'Subscribe your HUD/VFX presenter node to the mechanic state signal so feedback triggers on transition for $cleanTitle:',
            codeSnippet: buildEngineSnippet(stepIdx: 0, isFeelOrUi: true),
            completed: isParentCompleted,
          ),
          Subtask(
            id: '${parentTask.id}_sub_2',
            text: 'STEP $taskNum.2 · TRIGGER ON-SCREEN FEEDBACK & APPLY TUNING PARAMETER',
            specNotes:
                'Update the active on-screen indicator, camera/animation response, and audio cue scaled by $primaryVarName:',
            codeSnippet: buildEngineSnippet(stepIdx: 1, isFeelOrUi: true),
            completed: isParentCompleted,
          ),
          Subtask(
            id: '${parentTask.id}_sub_3',
            text: 'STEP $taskNum.3 · ENFORCE CLEANUP & TRANSITION GUARD',
            specNotes:
                'Immediately clear active visual/audio effects on state exit or reset to satisfy "$primaryGuard":',
            codeSnippet: buildEngineSnippet(stepIdx: 2, isFeelOrUi: true),
            completed: isParentCompleted,
          ),
        ];
      } else {
        parentTask.children = [
          Subtask(
            id: '${parentTask.id}_sub_1',
            text: 'STEP $taskNum.1 · READ PLAYER INPUT & VALIDATE ENTRY STATE',
            specNotes:
                'Inside your update loop, read the player trigger input and verify the mechanic can enter "$cleanTitle":',
            codeSnippet: buildEngineSnippet(stepIdx: 0, isFeelOrUi: false),
            completed: isParentCompleted,
          ),
          Subtask(
            id: '${parentTask.id}_sub_2',
            text: 'STEP $taskNum.2 · EXECUTE CORE MECHANIC LOGIC WITH INSPECTOR VARIABLES',
            specNotes:
                'Apply the state update and movement/interaction math for "$cleanTitle" driven by inspector variable $primaryVarName:',
            codeSnippet: buildEngineSnippet(stepIdx: 1, isFeelOrUi: false),
            completed: isParentCompleted,
          ),
          Subtask(
            id: '${parentTask.id}_sub_3',
            text: 'STEP $taskNum.3 · ADD EDGE-CASE GUARD CHECK BEFORE COMMITTING STATE',
            specNotes:
                'Add an explicit guard check to enforce "$primaryGuard" so rapid inputs or boundary hits never lock the loop:',
            codeSnippet: buildEngineSnippet(stepIdx: 2, isFeelOrUi: false),
            completed: isParentCompleted,
          ),
        ];
      }
    }

    final resolvedSubs = <TaskHowToSubStep>[];
    for (int i = 0; i < parentTask.children.length; i++) {
      final child = parentTask.children[i];
      final rawLabel = child.text.trim();
      final stepLabel = rawLabel.toUpperCase().startsWith('STEP ')
          ? rawLabel
          : 'STEP $taskNum.${i + 1} · ${rawLabel.toUpperCase()}';
      final instruction = (child.specNotes != null && child.specNotes!.trim().isNotEmpty)
          ? child.specNotes!.trim()
          : 'Implement and verify "$rawLabel" inside $whereLocation.';
      // If user hasn't customized the snippet (`codeTargetFile != 'custom_snippet'`) and i < 3,
      // dynamically adapt the code formula to the current engine & active tuning variable!
      final isCustomSnippet = child.codeTargetFile == 'custom_snippet';
      final code = (isCustomSnippet &&
              child.codeSnippet != null &&
              child.codeSnippet!.trim().isNotEmpty)
          ? child.codeSnippet!.trim()
          : (i < 3
              ? buildEngineSnippet(stepIdx: i, isFeelOrUi: isFeelOrUi)
              : (child.codeSnippet != null && child.codeSnippet!.trim().isNotEmpty
                  ? child.codeSnippet!.trim()
                  : '// Step $taskNum.${i + 1}: $rawLabel\nexecute_step_${taskNum}_${i + 1}($primaryVarName)'));
      resolvedSubs.add(
        TaskHowToSubStep(
          subtask: child,
          stepNumberLabel: stepLabel,
          instruction: instruction,
          codeFormula: code,
          isGuardStep: i == parentTask.children.length - 1 ||
              stepLabel.toUpperCase().contains('GUARD'),
        ),
      );
    }

    return TaskHowToBlueprint(
      numLabel: numLabel,
      layerTag: layerTag,
      cleanTitle: cleanTitle,
      durationChip: durationChip,
      whereLocation: whereLocation,
      engineLabel: engineLabel,
      subSteps: resolvedSubs,
    );
  }

  /// Tailors `parentTask.children` (Step X.1, X.2, X.3) to the developer's exact scene/node/script context
  /// (e.g. "CharacterBody2D with RayCast2D HookRay and Line2D RopeVisual") and marks each sub-step
  /// with `codeTargetFile = 'custom_snippet'` so it persists across re-renders.
  static void tailorSubStepsForContext({
    required Subtask parentTask,
    required int taskIndex,
    required FeatureStateNode checkpointNode,
    required String userContext,
    String? engineHint,
  }) {
    // Ensure base children exist first
    resolve(
      parentTask: parentTask,
      taskIndex: taskIndex,
      checkpointNode: checkpointNode,
      engineHint: engineHint,
    );

    final taskNum = taskIndex + 1;
    final cleanTitle = extractCleanTitle(parentTask.text);
    final engineLabel = detectEngineLabel(engineHint);
    final primaryVar = checkpointNode.tuningParams.isNotEmpty
        ? checkpointNode.tuningParams[taskIndex % checkpointNode.tuningParams.length]
        : 'responseTime: 0.12 s';
    final primaryVarName = primaryVar.split(':').first.trim();
    final primaryGuard = checkpointNode.edgeCases.isNotEmpty
        ? checkpointNode.edgeCases[taskIndex % checkpointNode.edgeCases.length]
        : '[STATE GUARD] Prevent duplicate trigger while active';

    // Extract CamelCase / PascalCase / snake_case node or script identifiers from userContext
    final stopWords = <String>{
      'using',
      'with',
      'named',
      'and',
      'the',
      'for',
      'inside',
      'from',
      'into',
      'node',
      'script',
      'class',
      'component',
      'scene',
    };
    final tokens = RegExp(r'[A-Za-z_][A-Za-z0-9_]{2,}')
        .allMatches(userContext)
        .map((m) => m.group(0)!)
        .where((w) => !stopWords.contains(w.toLowerCase()))
        .toList();

    final primaryNode = tokens.isNotEmpty ? tokens.first : 'PlayerController';
    final secondaryNode = tokens.length > 1 ? tokens[1] : primaryNode;
    final tertiaryNode = tokens.length > 2 ? tokens[2] : secondaryNode;

    String step1Code;
    String step2Code;
    String step3Code;

    if (engineLabel == 'UNITY C#') {
      step1Code =
          '// Context: $userContext\nif (Input.GetButton("Fire1") && $secondaryNode != null && CanEnterState()) {\n    activeState = MechanicState.Active;\n}';
      step2Code =
          '$primaryNode.ExecuteStep($secondaryNode, $primaryVarName * Time.fixedDeltaTime);\n$tertiaryNode.SyncVisualState(activeState);';
      step3Code =
          'if (!$primaryNode.IsValidState($secondaryNode) || cooldownTimer > 0f) return; // Guard: $primaryGuard';
    } else if (engineLabel == 'UNREAL 5') {
      step1Code =
          '// Context: $userContext\nif (bInputPressed && IsValid($secondaryNode) && CanEnterState()) {\n    ActiveState = EMechanicState::Active;\n}';
      step2Code =
          '$primaryNode->ExecuteStep($secondaryNode, DeltaTime * $primaryVarName);\n$tertiaryNode->SyncVisualState(ActiveState);';
      step3Code =
          'if (!$primaryNode->IsValidState($secondaryNode) || CooldownTimer > 0.f) return; // Guard: $primaryGuard';
    } else {
      step1Code =
          '# Context: $userContext\nif Input.is_action_pressed("primary_action") and is_instance_valid($secondaryNode) and can_enter_state():\n    activeState = State.ACTIVE';
      step2Code =
          '$primaryNode.apply_mechanic_step($secondaryNode, $primaryVarName * delta)\n$tertiaryNode.sync_visual_state(activeState)';
      step3Code =
          'if not $primaryNode.is_valid_state($secondaryNode) or cooldownTimer > 0.0:\n    return # Guard: $primaryGuard';
    }

    if (parentTask.children.isNotEmpty) {
      parentTask.children[0].text =
          'STEP $taskNum.1 · BIND INPUT & VALIDATE ${secondaryNode.toUpperCase()} IN ${primaryNode.toUpperCase()}';
      parentTask.children[0].specNotes =
          'Inside $primaryNode, read player input and validate $secondaryNode before entering "$cleanTitle" ($userContext):';
      parentTask.children[0].codeSnippet = step1Code;
      parentTask.children[0].codeTargetFile = 'custom_snippet';
    }
    if (parentTask.children.length > 1) {
      parentTask.children[1].text =
          'STEP $taskNum.2 · APPLY ${primaryVarName.toUpperCase()} LOGIC ACROSS ${primaryNode.toUpperCase()} & ${tertiaryNode.toUpperCase()}';
      parentTask.children[1].specNotes =
          'Drive "$cleanTitle" on $primaryNode / $secondaryNode using inspector parameter $primaryVarName and update $tertiaryNode:';
      parentTask.children[1].codeSnippet = step2Code;
      parentTask.children[1].codeTargetFile = 'custom_snippet';
    }
    if (parentTask.children.length > 2) {
      parentTask.children[2].text =
          'STEP $taskNum.3 · ENFORCE GUARD CHECK ON ${secondaryNode.toUpperCase()}';
      parentTask.children[2].specNotes =
          'Guard $primaryNode / $secondaryNode against invalid state or rapid re-triggers to satisfy "$primaryGuard":';
      parentTask.children[2].codeSnippet = step3Code;
      parentTask.children[2].codeTargetFile = 'custom_snippet';
    }
  }
}

