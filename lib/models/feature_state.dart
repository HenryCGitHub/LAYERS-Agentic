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
  final String stepNumberLabel; // e.g., "STEP 1.1 · CREATE ASSET FILE"
  final String shortTitle;      // e.g., "Create BP_GridTileActor"
  final String instruction;     // Concrete implementation instruction
  final String verifyResult;    // "✓ VERIFY BEFORE CHECKING [✓]" visual check
  final String stepPath;        // e.g., "Content Browser → /Game/Blueprints"
  final String codeFormula;     // Short code / formula / hierarchy snippet
  final String explainConcept;  // Project-connected "🎯 Connects to your Spec & Next Step" note
  final List<String> specChips; // Spec connection chips (e.g. ["Next: ...", "Spec: ..."])
  final String quickFixPitfall; // Step-specific "🔧 Quick Fix / Common Pitfall" for the right footer
  final int estimatedMinutes;   // Weighted minutes for this specific step (e.g., 15, 25, 65, 35)
  final String etaLabel;        // Formatted step ETA (e.g., "15m", "25m", "1.1h")
  final bool isGuardStep;

  const TaskHowToSubStep({
    required this.subtask,
    required this.stepNumberLabel,
    this.shortTitle = '',
    required this.instruction,
    this.verifyResult = '',
    this.stepPath = '',
    required this.codeFormula,
    this.explainConcept = '',
    this.specChips = const [],
    this.quickFixPitfall = '',
    this.estimatedMinutes = 15,
    this.etaLabel = '15m',
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
    return '3h';
  }

  /// Base effort weights (in minutes) across the 6 standard steps of a 3.0h (180m) task:
  /// Step 1: 15m (Create / Open Asset)
  /// Step 2: 25m (Add Components / Hierarchy)
  /// Step 3: 15m (Place in Scene / Level)
  /// Step 4: 25m (Expose Tuning Variables)
  /// Step 5: 65m (Write Core Logic — ~1.1h)
  /// Step 6: 35m (Add Guard & Playtest)
  static const List<int> baseStepWeights180 = <int>[15, 25, 15, 25, 65, 35];

  static int extractTaskTotalMinutes(String rawText) {
    final m = _trailingDurationRe.firstMatch(rawText);
    if (m != null && m.group(1) != null) {
      final parsed = DurationHelper.parseToMinutes(m.group(1)!);
      if (parsed > 0) return parsed;
    }
    return 180; // Default 3h = 180m
  }

  static List<int> computeWeightedStepMinutes(int totalSteps, int totalTaskMinutes) {
    if (totalSteps <= 0) return const <int>[];
    final safeTotal = totalTaskMinutes > 0 ? totalTaskMinutes : 180;
    if (totalSteps == 6 && safeTotal == 180) {
      return baseStepWeights180;
    }
    final rawWeights = List<int>.generate(
      totalSteps,
      (idx) => idx < baseStepWeights180.length ? baseStepWeights180[idx] : 20,
    );
    final weightSum = rawWeights.fold<int>(0, (sum, w) => sum + w);
    if (weightSum <= 0) {
      final each = (safeTotal / totalSteps).round();
      return List<int>.filled(totalSteps, each > 0 ? each : 5);
    }
    final scaled = <int>[];
    int allocated = 0;
    for (int i = 0; i < totalSteps; i++) {
      if (i == totalSteps - 1) {
        final rem = safeTotal - allocated;
        scaled.add(rem > 0 ? rem : 5);
      } else {
        final mins = ((rawWeights[i] / weightSum) * safeTotal).round();
        final clamped = mins > 0 ? mins : 5;
        scaled.add(clamped);
        allocated += clamped;
      }
    }
    return scaled;
  }

  static String formatStepEtaLabel(int minutes) {
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    final hours = minutes / 60.0;
    if ((hours - hours.roundToDouble()).abs() < 0.05) {
      return '${hours.round()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }

  static String formatRemainingHoursShort(int minutes) {
    if (minutes <= 0) return '0h';
    final hours = minutes / 60.0;
    if ((hours - hours.roundToDouble()).abs() < 0.05) {
      return '${hours.round()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }

  int get totalTaskMinutes =>
      subSteps.fold<int>(0, (sum, s) => sum + s.estimatedMinutes);

  int get remainingTaskMinutes => subSteps.fold<int>(
        0,
        (sum, s) => sum + (s.subtask.completed ? 0 : s.estimatedMinutes),
      );

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

  static ({String pascalName, String snakeName}) deriveConcreteAssetName(
    String rawText,
  ) {
    final clean = extractCleanTitle(rawText);
    const stopWords = <String>{
      'create',
      'build',
      'implement',
      'add',
      'wire',
      'hook',
      'up',
      'setup',
      'set',
      'bind',
      'apply',
      'enforce',
      'verify',
      'test',
      'the',
      'and',
      'for',
      'with',
      'in',
      'on',
      'to',
      'of',
      'a',
      'an',
      'core',
      'state',
      'player',
      'interaction',
      'mechanics',
      'controls',
      'logic',
      'pass',
      'stage',
    };
    final words = RegExp(r'[A-Za-z0-9]+')
        .allMatches(clean)
        .map((m) => m.group(0)!)
        .where((w) => w.length > 1 && !stopWords.contains(w.toLowerCase()))
        .toList();
    final chosen = words.isNotEmpty
        ? words.take(3).toList()
        : <String>['Grid', 'Tile', 'Actor'];
    if (!chosen.any((w) =>
        w.toLowerCase() == 'actor' ||
        w.toLowerCase() == 'controller' ||
        w.toLowerCase() == 'node' ||
        w.toLowerCase() == 'manager')) {
      chosen.add('Actor');
    }
    final pascal = chosen
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join();
    final snake = chosen.map((w) => w.toLowerCase()).join('_');
    return (pascalName: pascal, snakeName: snake);
  }

  /// Guarantees that `parentTask.children` contains 6 atomic, zero-assumption "LEGO / IKEA" sub-steps
  /// (`Step X.1` through `Step X.6`) adapted to `engineHint` (`GODOT 4`, `UNITY C#`, `UNREAL 5`),
  /// supporting Task 01 (create foundation asset) vs. Task 02+ (extend existing asset) and
  /// Unreal 5 `Blueprint | C++` toggle (`unrealCppMode`).
  static TaskHowToBlueprint resolve({
    required Subtask parentTask,
    required int taskIndex,
    required FeatureStateNode checkpointNode,
    String? engineHint,
    bool unrealCppMode = false,
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

    final assetSource = checkpointNode.checklist.isNotEmpty
        ? checkpointNode.checklist.first.text
        : cleanTitle;
    final asset = deriveConcreteAssetName('$assetSource ${checkpointNode.name}');
    final pascalAsset = asset.pascalName;
    final snakeAsset = asset.snakeName;
    final bpAsset = 'BP_$pascalAsset';
    final cppClass = 'A$pascalAsset';

    final primaryVar = checkpointNode.tuningParams.isNotEmpty
        ? checkpointNode.tuningParams[taskIndex % checkpointNode.tuningParams.length]
        : 'responseTime: 0.12 s';
    final primaryVarName = primaryVar.split(':').first.trim();
    final primaryGuard = checkpointNode.edgeCases.isNotEmpty
        ? checkpointNode.edgeCases[taskIndex % checkpointNode.edgeCases.length]
        : '[STATE GUARD] Prevent duplicate trigger while active';
    final isFoundationTask = taskIndex == 0;

    ({
      String stepHeader,
      String shortTitle,
      String instruction,
      String verify,
      String path,
      String code,
      String explain,
    }) buildAtomicStepSpec(int stepIdx) {
      // =======================================================================
      // UNREAL 5 (Supports both Blueprint mode & C++ mode)
      // =======================================================================
      if (engineLabel == 'UNREAL 5') {
        if (unrealCppMode) {
          switch (stepIdx) {
            case 0:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.1 · CREATE $cppClass C++ CLASS'
                    : 'STEP $taskNum.1 · OPEN EXISTING $pascalAsset.h / .cpp',
                shortTitle: isFoundationTask
                    ? 'Create $cppClass C++ Class'
                    : 'Open Existing $pascalAsset.cpp',
                instruction: isFoundationTask
                    ? 'In the Unreal Editor top menu, click Tools → New C++ Class... → choose Actor as the parent class → name it $pascalAsset and click Create Class.'
                    : 'Open your existing $pascalAsset.h and $pascalAsset.cpp files (created in Task 01) in Visual Studio or Rider to extend them for "$cleanTitle".',
                verify: isFoundationTask
                    ? 'Visual Studio / Rider opens with $pascalAsset.h and $pascalAsset.cpp generated.'
                    : '$pascalAsset.cpp is open in your IDE with no compile errors.',
                path: 'Source/Project/$pascalAsset.h',
                code: '#pragma once\n#include "CoreMinimal.h"\n#include "GameFramework/Actor.h"\n#include "$pascalAsset.generated.h"\n\nUCLASS()\nclass $cppClass : public AActor {\n  GENERATED_BODY()\npublic:\n  $cppClass();\n  EMechanicState ActiveState = EMechanicState::Idle;\n};',
                explain: 'An AActor C++ class is the foundation object you can spawn or place inside a level.',
              );
            case 1:
              return (
                stepHeader: 'STEP $taskNum.2 · ATTACH MESH & COLLISION SUBOBJECTS',
                shortTitle: 'Create Mesh & Collision Subobjects',
                instruction:
                    'Inside the $cppClass() constructor in $pascalAsset.cpp, instantiate a UStaticMeshComponent ("VisualMesh") and UBoxComponent ("InteractBox") and attach them to RootComponent.',
                verify:
                    'Live Coding (Ctrl+Alt+F11) compiles cleanly with VisualMesh and InteractBox attached under RootComponent.',
                path: 'Source/Project/$pascalAsset.cpp :: $cppClass()',
                code: '$cppClass::$cppClass() {\n  RootComponent = CreateDefaultSubobject<USceneComponent>("Root");\n  VisualMesh = CreateDefaultSubobject<UStaticMeshComponent>("VisualMesh");\n  VisualMesh->SetupAttachment(RootComponent);\n  InteractBox = CreateDefaultSubobject<UBoxComponent>("InteractBox");\n  InteractBox->InitBoxExtent(FVector(50.f, 50.f, 20.f));\n  InteractBox->SetupAttachment(RootComponent);\n}',
                explain: 'CreateDefaultSubobject constructs the visible 3D mesh and the collision sensor box inside your C++ constructor.',
              );
            case 2:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.3 · COMPILE & PLACE IN LEVEL VIEWPORT'
                    : 'STEP $taskNum.3 · SELECT INSTANCE IN LEVEL OUTLINER',
                shortTitle: isFoundationTask
                    ? 'Place $cppClass in Level'
                    : 'Select $cppClass in Outliner',
                instruction: isFoundationTask
                    ? 'Press Ctrl+Alt+F11 (Live Coding) to compile, then open C++ Classes in the Content Browser and drag $pascalAsset into the Level Viewport at (0, 0, 0).'
                    : 'Press Ctrl+Alt+F11 (Live Coding) and select your existing $pascalAsset instance in the Level Outliner to inspect its updated properties.',
                verify:
                    '$pascalAsset appears in the World Outliner at (0, 0, 0) with VisualMesh and InteractBox visible.',
                path: 'Level Editor → Content Browser → C++ Classes → Viewport',
                code: 'Instance: ${pascalAsset}_0 ($cppClass)\nTransform Location: FVector(0.f, 0.f, 0.f)',
                explain: 'Dragging the C++ class into the Level Viewport spawns a physical instance in your playable scene.',
              );
            case 3:
              return (
                stepHeader: 'STEP $taskNum.4 · EXPOSE UPROPERTY TUNING VARIABLES',
                shortTitle: 'Expose UPROPERTY $primaryVarName',
                instruction:
                    'In $pascalAsset.h under public:, declare $primaryVarName with UPROPERTY(EditAnywhere, BlueprintReadWrite) so designers can tune "$primaryVar" in the Details panel.',
                verify:
                    'After Live Coding, selecting the actor in the Level shows "$primaryVarName" inside the Details panel.',
                path: 'Source/Project/$pascalAsset.h (UPROPERTY)',
                code: 'UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Tuning")\nfloat $primaryVarName = 1.0f; // $primaryVar\n\nUPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="State")\nbool bIsOccupied = false;',
                explain: 'UPROPERTY(EditAnywhere) exposes a C++ variable to the Unreal Editor Details panel so you can tweak it without recompiling.',
              );
            case 4:
              return (
                stepHeader: 'STEP $taskNum.5 · IMPLEMENT OVERLAP / TICK LOGIC',
                shortTitle: 'Implement $cleanTitle in C++',
                instruction:
                    'In $pascalAsset.cpp, implement the trigger and state interpolation for "$cleanTitle" using FMath::FInterpConstantTo driven by $primaryVarName.',
                verify:
                    'C++ method compiles cleanly and transitions ActiveState to EMechanicState::Active on trigger.',
                path: 'Source/Project/$pascalAsset.cpp :: TickComponent / Overlap',
                code: 'void $cppClass::ExecuteMechanicStep(float DeltaTime) {\n  if (bInputPressed && CanEnterState()) {\n    ActiveState = EMechanicState::Active;\n  }\n  CurrentVal = FMath::FInterpConstantTo(CurrentVal, TargetVal, DeltaTime, $primaryVarName);\n}',
                explain: 'FMath::FInterpConstantTo smoothly steps your value each frame using DeltaTime so movement speed is frame-rate independent.',
              );
            default:
              return (
                stepHeader: 'STEP $taskNum.6 · ADD GUARD CHECK & PLAYTEST (ALT+P)',
                shortTitle: 'Add Guard & Playtest (Alt+P)',
                instruction:
                    'Add a guard check at the top of your function to enforce "$primaryGuard", compile with Ctrl+Alt+F11, and press Play (Alt+P) to test in the viewport.',
                verify:
                    'Pressing Play (Alt+P) triggers "$cleanTitle" cleanly on screen and blocks duplicate triggers.',
                path: 'Main Toolbar → Live Coding (Ctrl+Alt+F11) → Play (Alt+P)',
                code: 'if (IsBoundaryBlocked() || CooldownTimer > 0.f) return; // Guard: $primaryGuard\nif (GEngine) {\n  GEngine->AddOnScreenDebugMessage(-1, 2.f, FColor::Cyan, TEXT("$cleanTitle Active!"));\n}',
                explain: 'The early-return guard prevents double-triggering or out-of-bounds states when the player spams input.',
              );
          }
        } else {
          // UNREAL 5 — Blueprint Mode (Default)
          switch (stepIdx) {
            case 0:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.1 · CREATE $bpAsset BLUEPRINT ASSET'
                    : 'STEP $taskNum.1 · OPEN EXISTING $bpAsset BLUEPRINT',
                shortTitle: isFoundationTask
                    ? 'Create $bpAsset'
                    : 'Open Existing $bpAsset',
                instruction: isFoundationTask
                    ? 'In the Content Browser (bottom panel), right-click inside /Game/Blueprints → choose Blueprint Class → click Actor, and name it $bpAsset.'
                    : 'In the Content Browser (/Game/Blueprints), double-click your existing $bpAsset (created in Task 01) to open it for "$cleanTitle".',
                verify: isFoundationTask
                    ? 'A new blue-underlined Blueprint icon named $bpAsset appears inside /Game/Blueprints.'
                    : 'The Blueprint Editor opens showing your existing $bpAsset components and Event Graph.',
                path: 'Content Browser → /Game/Blueprints/$bpAsset',
                code: 'Asset Name:   $bpAsset\nParent Class: Actor (AActor / EMechanicState::Active)',
                explain: 'An Actor Blueprint is a visual container you can place in a level that holds 3D meshes, collision sensors, and Event Graph nodes.',
              );
            case 1:
              return (
                stepHeader: 'STEP $taskNum.2 · ATTACH VISUAL MESH & BOX COLLISION',
                shortTitle: 'Attach Mesh & BoxCollision',
                instruction:
                    'Inside $bpAsset, look at the top-left Components panel and click + Add to attach a Static Mesh ("VisualMesh", set to Shape_Plane/Cube) and a Box Collision ("InteractBox").',
                verify:
                    'A visible 3D shape surrounded by an orange wireframe collision box appears in the central Viewport tab.',
                path: '$bpAsset → Components Panel (Top-Left)',
                code: '$bpAsset (Self)\n └─ DefaultSceneRoot\n     ├─ VisualMesh  (StaticMesh: Shape_Plane / Cube)\n     └─ InteractBox (BoxCollision: Extent 50, 50, 20)',
                explain: 'Static Mesh makes the object visible to the player. Box Collision creates an invisible trigger zone so the game knows when the player overlaps or clicks it.',
              );
            case 2:
              return (
                stepHeader: isFoundationTask
                    ? 'STEP $taskNum.3 · DRAG $bpAsset INTO LEVEL VIEWPORT'
                    : 'STEP $taskNum.3 · VERIFY $bpAsset IN LEVEL OUTLINER',
                shortTitle: isFoundationTask
                    ? 'Drag into Level Viewport'
                    : 'Select in Level Outliner',
                instruction: isFoundationTask
                    ? 'Click Compile & Save (top-left of $bpAsset), then switch to the main Level tab and drag $bpAsset from the Content Browser onto the floor at (0, 0, 0).'
                    : 'Click Compile & Save, then select your existing $bpAsset instance in the Level Outliner on the right to verify the updated component.',
                verify:
                    '$bpAsset sits on the level floor and is listed inside the World Outliner panel.',
                path: 'Main Level Viewport & World Outliner',
                code: 'Instance: ${bpAsset}_0\nLocation: X = 0.0, Y = 0.0, Z = 0.0',
                explain: 'A Blueprint in the Content Browser is just a template. Dragging it into the Level Viewport spawns an actual physical copy inside your game world.',
              );
            case 3:
              return (
                stepHeader: 'STEP $taskNum.4 · ADD & EXPOSE TUNING VARIABLES',
                shortTitle: 'Add $primaryVarName Variable',
                instruction:
                    'In $bpAsset, find My Blueprint → Variables on the left and click + to add "$primaryVarName" (Float) and "bIsActive" (Boolean). Click the Eye Icon next to "$primaryVarName" to make it Instance Editable.',
                verify:
                    '"$primaryVarName" shows an open yellow Eye Icon and defaults to "$primaryVar" in the Details panel.',
                path: '$bpAsset → My Blueprint → Variables → +',
                code: '$primaryVarName : Float ($primaryVar)  [👁 Instance Editable]\nbIsActive      : Boolean = false      [👁 Instance Editable]',
                explain: 'Variables store your mechanic\'s state and speed. Clicking the Eye Icon (Instance Editable) lets you tweak the value directly in the Level without reopening the Blueprint.',
              );
            case 4:
              return (
                stepHeader: 'STEP $taskNum.5 · WIRE EVENT GRAPH NODE CHAIN',
                shortTitle: 'Wire Event Graph Logic',
                instruction:
                    'Open the Event Graph tab. Right-click InteractBox → Add Event → OnComponentBeginOverlap (or Input Action) → connect a Branch node → Set bIsActive = true and update using FMath::FInterpConstantTo ($primaryVarName).',
                verify:
                    'A white execution wire connects the red Event node through the Branch node to Set bIsActive = true.',
                path: '$bpAsset → Event Graph Tab',
                code: '[Event OnBeginOverlap (InteractBox)]\n   └──► [Branch: NOT bIsActive]\n           └──► (True) ──► [Set bIsActive = true]\n                           [FMath::FInterpConstantTo ($primaryVarName)]',
                explain: 'The Event Graph is the visual brain of your Blueprint. Execution flows left-to-right along the white wire whenever the event fires.',
              );
            default:
              return (
                stepHeader: 'STEP $taskNum.6 · ADD GUARD & PLAYTEST (ALT+P)',
                shortTitle: 'Connect Guard & Playtest (Alt+P)',
                instruction:
                    'Ensure your Branch node checks "$primaryGuard" before firing, connect a Print String ("$cleanTitle Active!") node to confirm, click Compile, and press Play (Alt+P).',
                verify:
                    'Pressing Play (Alt+P) and triggering the object prints "$cleanTitle Active!" in cyan text at the top-left of the viewport.',
                path: 'Main Toolbar → Compile → Play (Alt+P)',
                code: '// Guard: $primaryGuard\n[Branch: !IsBoundaryBlocked && Cooldown <= 0]\n   └──► (True) ──► [Print String: "$cleanTitle Active!"]',
                explain: 'Checking the guard condition on the Branch node prevents the mechanic from double-firing or locking up when inputs are spammed.',
              );
          }
        }
      }

      // =======================================================================
      // UNITY C# (Strictly C# MonoBehaviour + GameObject Hierarchy)
      // =======================================================================
      if (engineLabel == 'UNITY C#') {
        switch (stepIdx) {
          case 0:
            return (
              stepHeader: isFoundationTask
                  ? 'STEP $taskNum.1 · CREATE $pascalAsset.cs C# SCRIPT'
                  : 'STEP $taskNum.1 · OPEN EXISTING $pascalAsset.cs SCRIPT',
              shortTitle: isFoundationTask
                  ? 'Create $pascalAsset.cs'
                  : 'Open Existing $pascalAsset.cs',
              instruction: isFoundationTask
                  ? 'In the Project window (bottom panel), right-click inside Assets/Scripts → Create → C# Script, and name it $pascalAsset.'
                  : 'In Assets/Scripts, double-click your existing $pascalAsset.cs script (from Task 01) to open it in your code editor for "$cleanTitle".',
              verify: isFoundationTask
                  ? '$pascalAsset.cs appears in Assets/Scripts with class $pascalAsset : MonoBehaviour.'
                  : '$pascalAsset.cs is open in VS Code / Visual Studio / Rider.',
              path: 'Project Window → Assets/Scripts/$pascalAsset.cs',
              code: 'using UnityEngine;\n\npublic class $pascalAsset : MonoBehaviour {\n    private bool isActive = false;\n}',
              explain: 'A MonoBehaviour C# script is a custom component you can attach to any GameObject in your Unity scene.',
            );
          case 1:
            return (
              stepHeader: 'STEP $taskNum.2 · CREATE GAMEOBJECT & ATTACH COLLIDER',
              shortTitle: 'Add Mesh & BoxCollider',
              instruction:
                  'In the Hierarchy window (left), right-click → Create Empty → name it "$pascalAsset". In the Inspector, click Add Component to attach a MeshRenderer/SpriteRenderer, a BoxCollider (check Is Trigger), and your $pascalAsset script.',
              verify:
                  'Selecting $pascalAsset in the Scene view shows a green wireframe BoxCollider outline.',
              path: 'Hierarchy → $pascalAsset → Inspector → Add Component',
              code: '$pascalAsset (GameObject)\n ├─ VisualMesh      (MeshFilter + MeshRenderer / SpriteRenderer)\n ├─ InteractTrigger (BoxCollider: isTrigger = true)\n └─ $pascalAsset    (MonoBehaviour Script)',
              explain: 'The Renderer draws the object on screen, the BoxCollider detects overlaps/clicks, and the Script runs your C# logic.',
            );
          case 2:
            return (
              stepHeader: isFoundationTask
                  ? 'STEP $taskNum.3 · POSITION IN SCENE & SAVE PREFAB'
                  : 'STEP $taskNum.3 · SELECT $pascalAsset IN SCENE HIERARCHY',
              shortTitle: isFoundationTask
                  ? 'Place in Scene at (0, 0, 0)'
                  : 'Select in Scene Hierarchy',
              instruction: isFoundationTask
                  ? 'Select $pascalAsset in the Hierarchy, set its Transform Position to (0, 0, 0) in the Inspector, and drag it into Assets/Prefabs to save a reusable Prefab.'
                  : 'Select your $pascalAsset instance in the Hierarchy so you can inspect the new fields in the Inspector.',
              verify:
                  '$pascalAsset sits at (0, 0, 0) in the Scene view with a blue Prefab icon in the Hierarchy.',
              path: 'Hierarchy & Scene View → Transform (0, 0, 0)',
              code: 'GameObject: $pascalAsset\nTransform.position = new Vector3(0f, 0f, 0f);',
              explain: 'Saving your GameObject as a Prefab lets you place multiple copies across the level and update them all at once.',
            );
          case 3:
            return (
              stepHeader: 'STEP $taskNum.4 · EXPOSE [SerializeField] TUNING VARIABLES',
              shortTitle: 'Add [SerializeField] $primaryVarName',
              instruction:
                  'At the top of $pascalAsset.cs inside the class body, add [SerializeField] private float $primaryVarName so you can tune "$primaryVar" directly in the Unity Inspector.',
              verify:
                  'Saving the script and clicking $pascalAsset in Unity shows "$primaryVarName" as an editable number field in the Inspector.',
              path: 'Assets/Scripts/$pascalAsset.cs (Inspector Fields)',
              code: '[Header("Tuning Parameters")]\n[SerializeField] private float $primaryVarName = 1.0f; // $primaryVar\n[SerializeField] private bool canTrigger = true;',
              explain: '[SerializeField] exposes a private C# variable inside the Unity Inspector without making it public to other scripts.',
            );
          case 4:
            return (
              stepHeader: 'STEP $taskNum.5 · WRITE UPDATE / TRIGGER LOGIC IN C#',
              shortTitle: 'Implement Update() / Trigger Logic',
              instruction:
                  'Inside $pascalAsset.cs, implement Update() / FixedUpdate() to read input with Input.GetButton("Fire1") and advance state using Time.fixedDeltaTime and $primaryVarName.',
              verify:
                  'Unity compiles the script in the bottom-right corner with zero Console errors.',
              path: 'Assets/Scripts/$pascalAsset.cs :: FixedUpdate()',
              code: 'private void FixedUpdate() {\n    if (Input.GetButton("Fire1") && canTrigger) {\n        isActive = true;\n        currentVal = Mathf.MoveTowards(currentVal, targetVal, $primaryVarName * Time.fixedDeltaTime);\n    }\n}',
              explain: 'FixedUpdate() runs on a fixed physics clock, and multiplying by Time.fixedDeltaTime keeps speeds identical at any frame rate.',
            );
          default:
            return (
              stepHeader: 'STEP $taskNum.6 · ADD GUARD CHECK & PRESS PLAY (CTRL+P)',
              shortTitle: 'Add Guard & Playtest (Ctrl+P)',
              instruction:
                  'Add an early return guard at the top of your method to enforce "$primaryGuard", save the script, and press the Play button (Ctrl+P) at the top of the Unity Editor.',
              verify:
                  'In Play Mode, triggering "$cleanTitle" logs confirmation in the Console and prevents duplicate triggers.',
              path: 'Unity Top Toolbar → Play (Ctrl+P)',
              code: 'if (!canTrigger || cooldownTimer > 0f) return; // Guard: $primaryGuard\nDebug.Log("$cleanTitle activated!");',
              explain: 'The guard clause exits immediately if the mechanic is on cooldown or blocked, preventing state bugs when buttons are spammed.',
            );
        }
      }

      // =======================================================================
      // DEFAULT: GODOT 4 (Strictly GDScript .gd + Scene .tscn Hierarchy)
      // =======================================================================
      switch (stepIdx) {
        case 0:
          return (
            stepHeader: isFoundationTask
                ? 'STEP $taskNum.1 · CREATE $snakeAsset.tscn & .gd SCRIPT'
                : 'STEP $taskNum.1 · OPEN EXISTING $snakeAsset.gd SCRIPT',
            shortTitle: isFoundationTask
                ? 'Create $snakeAsset.tscn & .gd'
                : 'Open Existing $snakeAsset.gd',
            instruction: isFoundationTask
                ? 'In the Scene dock (top-left), click + Other Node → select Node2D / CharacterBody2D → name it "$pascalAsset". Save the scene as res://scenes/$snakeAsset.tscn, then click the Attach Script icon to create res://scripts/$snakeAsset.gd.'
                : 'In the FileSystem dock (bottom-left), double-click your existing res://scripts/$snakeAsset.gd script (from Task 01) to open it for "$cleanTitle".',
            verify: isFoundationTask
                ? '$pascalAsset appears in the Scene tree with a scroll icon next to it, and $snakeAsset.gd opens in the Script editor.'
                : '$snakeAsset.gd is open in the central Script workspace.',
            path: 'FileSystem → res://scripts/$snakeAsset.gd',
            code: 'extends Node2D\nclass_name $pascalAsset\n\nvar is_active: bool = false',
            explain: 'In Godot 4, every reusable game object is a Scene (.tscn) with a GDScript (.gd) attached to its root node.',
          );
        case 1:
          return (
            stepHeader: 'STEP $taskNum.2 · ADD VISUAL & COLLISION CHILD NODES',
            shortTitle: 'Add Sprite2D & Area2D/CollisionShape2D',
            instruction:
                'Right-click the root "$pascalAsset" node in the Scene dock → + Add Child Node → add a Sprite2D (or ColorRect) named "Visual" and an Area2D with a CollisionShape2D (RectangleShape2D) named "HitBox".',
            verify:
                'The 2D Viewport shows your visible shape surrounded by a light-blue rectangle collision outline (no yellow warning triangle).',
            path: 'Scene Dock (Top-Left) → $pascalAsset Hierarchy',
            code: '$pascalAsset (Node2D / CharacterBody2D)\n ├─ Visual (Sprite2D / ColorRect: 64x64)\n └─ HitBox (Area2D)\n     └─ CollisionShape2D (RectangleShape2D)',
            explain: 'Sprite2D/ColorRect makes the object visible on screen, while Area2D + CollisionShape2D lets Godot detect overlaps and clicks.',
          );
        case 2:
          return (
            stepHeader: isFoundationTask
                ? 'STEP $taskNum.3 · INSTANCE SCENE IN MAIN LEVEL'
                : 'STEP $taskNum.3 · SELECT $pascalAsset IN MAIN SCENE',
            shortTitle: isFoundationTask
                ? 'Instance in Main Scene'
                : 'Select in Main Scene',
            instruction: isFoundationTask
                ? 'Press Ctrl+S to save $snakeAsset.tscn, switch to your Main level scene tab, and click the Chain-Link icon ("Instantiate Child Scene") to drop $snakeAsset.tscn into the level at (0, 0).'
                : 'Switch to your Main level scene tab and select the $pascalAsset node to preview its updated Inspector properties.',
            verify:
                '$pascalAsset appears in the Main scene tree with a small movie-clapper / chain icon next to it.',
            path: 'Main Scene Tab → Instantiate Child Scene (Ctrl+Shift+A)',
            code: 'Instanced Node: $pascalAsset (res://scenes/$snakeAsset.tscn)\nposition = Vector2(0, 0)',
            explain: 'Instantiating places a live copy of your scene inside the game level so you can see and test it when pressing Play.',
          );
        case 3:
          return (
            stepHeader: 'STEP $taskNum.4 · ADD @export TUNING VARIABLES IN GDSCRIPT',
            shortTitle: 'Add @export var $primaryVarName',
            instruction:
                'At the top of $snakeAsset.gd, add @export var $primaryVarName: float = 1.0 so you can tune "$primaryVar" directly in the right-hand Inspector dock.',
            verify:
                'Selecting $pascalAsset in the Scene tree displays "$primaryVarName" at the top of the Inspector dock.',
            path: 'res://scripts/$snakeAsset.gd (@export)',
            code: '@export var $primaryVarName: float = 1.0 # $primaryVar\n@export var can_trigger: bool = true\nvar current_val: float = 0.0',
            explain: '@export exposes a GDScript variable in the Godot Inspector dock so you can tweak numbers live without editing code.',
          );
        case 4:
          return (
            stepHeader: 'STEP $taskNum.5 · IMPLEMENT _physics_process(delta) LOGIC',
            shortTitle: 'Write _physics_process(delta)',
            instruction:
                'Inside $snakeAsset.gd, add func _physics_process(delta: float) -> void: to check Input.is_action_pressed("primary_action") and step the value using move_toward and $primaryVarName.',
            verify:
                'The script editor shows zero red syntax errors at the bottom of the panel.',
            path: 'res://scripts/$snakeAsset.gd :: _physics_process(delta)',
            code: 'func _physics_process(delta: float) -> void:\n    if Input.is_action_pressed("primary_action") and can_trigger:\n        is_active = true\n        current_val = move_toward(current_val, target_val, $primaryVarName * delta)',
            explain: '_physics_process(delta) runs 60 times per second in sync with physics, and move_toward smoothly transitions values without overshooting.',
          );
        default:
          return (
            stepHeader: 'STEP $taskNum.6 · ADD GUARD CHECK & PRESS PLAY (F5)',
            shortTitle: 'Add Guard & Playtest (F5)',
            instruction:
                'Add a guard check at the top of _physics_process to enforce "$primaryGuard", add print("$cleanTitle Active!"), and press F5 (or the top-right Play button) to test.',
            verify:
                'The game window launches and triggering the action prints "$cleanTitle Active!" in the bottom Output panel.',
            path: 'Top-Right Toolbar → Play Scene (F6) / Play Project (F5)',
            code: 'if not can_trigger or cooldown_timer > 0.0:\n    return # Guard: $primaryGuard\nprint("$cleanTitle Active!")',
            explain: 'The early-return guard stops the function immediately if the mechanic is blocked or on cooldown, preventing state lockups.',
          );
      }
    }

    if (parentTask.children.length < 6 &&
        !parentTask.children.any((c) => c.codeTargetFile == 'custom_snippet')) {
      final isParentCompleted = parentTask.completed;
      final existingDone = <int, bool>{
        for (int i = 0; i < parentTask.children.length; i++)
          i: parentTask.children[i].completed,
      };
      parentTask.children = [
        for (int sIdx = 0; sIdx < 6; sIdx++)
          () {
            final s = buildAtomicStepSpec(sIdx);
            return Subtask(
              id: '${parentTask.id}_sub_${sIdx + 1}',
              text: s.stepHeader,
              specNotes: s.instruction,
              codeSnippet: s.code,
              completed: existingDone[sIdx] ?? isParentCompleted,
            );
          }(),
      ];
    }

    final totalTaskMinutes = extractTaskTotalMinutes(parentTask.text);
    final stepMinutesList = computeWeightedStepMinutes(
      parentTask.children.length,
      totalTaskMinutes,
    );

    ({
      String explain,
      List<String> chips,
      String pitfall,
    }) buildProjectSpecContext(int stepIdx) {
      switch (stepIdx) {
        case 0:
          return (
            explain:
                'Every step in this task builds inside this asset so "$cleanTitle" stays modular and reusable across the arena.',
            chips: <String>[
              'Next: Attach Visual & Collision',
              'Target: $cleanTitle',
            ],
            pitfall: engineLabel == 'UNREAL 5'
                ? 'Choose Actor (AActor) as the parent class so you can attach components and place it in the level.'
                : (engineLabel == 'UNITY C#'
                    ? 'Make sure the file name "$pascalAsset.cs" matches the class name "$pascalAsset" so Unity can attach it.'
                    : 'Save the scene in res://scenes/ before attaching the script so node paths stay clean.'),
          );
        case 1:
          return (
            explain:
                'Gives "$cleanTitle" both its on-screen visual shape and the collision trigger sensor needed for Step 5 logic.',
            chips: <String>[
              'Next: Place in Level Viewport',
              'Trigger Sensor: HitBox / InteractBox',
            ],
            pitfall: engineLabel == 'UNREAL 5'
                ? 'Set Collision Presets on InteractBox to OverlapAllDynamic so player overlap events fire reliably.'
                : (engineLabel == 'UNITY C#'
                    ? 'Check the "Is Trigger" box on BoxCollider so the player does not physically snag on the sensor.'
                    : 'Assign a RectangleShape2D resource inside CollisionShape2D to clear the yellow scene warning icon.'),
          );
        case 2:
          return (
            explain:
                'Spawns a live testable instance in the arena so you can verify "${checkpointNode.playtestCondition}" on screen.',
            chips: <String>[
              'Next: Expose $primaryVarName',
              'Playtest: ${checkpointNode.cleanStageTitle}',
            ],
            pitfall: engineLabel == 'UNREAL 5'
                ? 'Click Compile & Save before dragging into the viewport so the new mesh and collision box appear.'
                : (engineLabel == 'UNITY C#'
                    ? 'Reset Transform Position to (0, 0, 0) in the Inspector so the object is not hidden off-camera.'
                    : 'Use the Chain-Link icon (Ctrl+Shift+A) to instantiate the child scene rather than copying raw nodes.'),
          );
        case 3:
          return (
            explain:
                'Exposes "$primaryVar" directly in the Inspector so you can tune "$cleanTitle" feel live without recompiling.',
            chips: <String>[
              'Spec Param: $primaryVar',
              'Next: Wire Step 5 Logic',
            ],
            pitfall: engineLabel == 'UNREAL 5'
                ? 'Click the Eye icon (Instance Editable) next to $primaryVarName so it appears in the Level Details panel.'
                : (engineLabel == 'UNITY C#'
                    ? 'Keep [SerializeField] above private float $primaryVarName so Unity serializes it in the Inspector.'
                    : 'Save the script (Ctrl+S) after adding @export var $primaryVarName so the Inspector dock refreshes.'),
          );
        case 4:
          return (
            explain:
                'Connects player trigger input to "$primaryVarName" so "$cleanTitle" updates smoothly every physics frame.',
            chips: <String>[
              'Drives: $primaryVar',
              'Next: Enforce Guard & Playtest',
            ],
            pitfall: engineLabel == 'UNREAL 5'
                ? 'Connect the white execution wire from the Branch (True) pin into your state update node.'
                : (engineLabel == 'UNITY C#'
                    ? 'Multiply by Time.fixedDeltaTime inside FixedUpdate() so speed stays identical at any frame rate.'
                    : 'Multiply $primaryVarName by delta inside _physics_process(delta) for frame-rate independent motion.'),
          );
        default:
          return (
            explain:
                'Enforces "$primaryGuard" and completes the playable verification for "${checkpointNode.cleanStageTitle}".',
            chips: <String>[
              'Guard: $primaryGuard',
              'Goal: ${checkpointNode.cleanStageTitle}',
            ],
            pitfall:
                'Place the guard check at the very top of your function so blocked or cooldown inputs exit immediately ($primaryGuard).',
          );
      }
    }

    final resolvedSubs = <TaskHowToSubStep>[];
    for (int i = 0; i < parentTask.children.length; i++) {
      final child = parentTask.children[i];
      final isCustomSnippet = child.codeTargetFile == 'custom_snippet';
      final spec = buildAtomicStepSpec(i < 6 ? i : 5);
      final projCtx = buildProjectSpecContext(i < 6 ? i : 5);
      final stepMins = i < stepMinutesList.length ? stepMinutesList[i] : 20;
      final stepEta = formatStepEtaLabel(stepMins);
      final rawLabel = child.text.trim();
      final stepLabel = isCustomSnippet
          ? (rawLabel.toUpperCase().startsWith('STEP ')
              ? rawLabel
              : 'STEP $taskNum.${i + 1} · ${rawLabel.toUpperCase()}')
          : (i < 6
              ? spec.stepHeader
              : 'STEP $taskNum.${i + 1} · ${rawLabel.toUpperCase()}');
      final instruction = isCustomSnippet &&
              child.specNotes != null &&
              child.specNotes!.trim().isNotEmpty
          ? child.specNotes!.trim()
          : (i < 6
              ? spec.instruction
              : (child.specNotes != null && child.specNotes!.trim().isNotEmpty
                  ? child.specNotes!.trim()
                  : 'Implement and verify "$rawLabel" inside $whereLocation.'));
      final code = isCustomSnippet &&
              child.codeSnippet != null &&
              child.codeSnippet!.trim().isNotEmpty
          ? child.codeSnippet!.trim()
          : (i < 6
              ? spec.code
              : (child.codeSnippet != null && child.codeSnippet!.trim().isNotEmpty
                  ? child.codeSnippet!.trim()
                  : '// Step $taskNum.${i + 1}: $rawLabel\nexecute_step_${taskNum}_${i + 1}($primaryVarName)'));
      final shortTitle = (!isCustomSnippet && i < 6)
          ? spec.shortTitle
          : rawLabel.replaceFirst(
              RegExp(r'^STEP\s+\d+\.\d+\s*·\s*', caseSensitive: false),
              '',
            );

      resolvedSubs.add(
        TaskHowToSubStep(
          subtask: child,
          stepNumberLabel: stepLabel,
          shortTitle: shortTitle,
          instruction: instruction,
          verifyResult: i < 6
              ? spec.verify
              : 'Verify "$shortTitle" responds cleanly in the active viewport.',
          stepPath: i < 6 ? spec.path : whereLocation,
          codeFormula: code,
          explainConcept: i < 6
              ? projCtx.explain
              : 'Connects "$shortTitle" to "$primaryVar" and "$primaryGuard".',
          specChips: projCtx.chips,
          quickFixPitfall: projCtx.pitfall,
          estimatedMinutes: stepMins,
          etaLabel: stepEta,
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

