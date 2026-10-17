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
