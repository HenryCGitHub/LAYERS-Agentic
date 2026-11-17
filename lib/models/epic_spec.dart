import 'dart:convert';
import '../constants/tiers.dart';
import 'tier_document.dart';

/// Godot 4 spatial target dimension for `ROOT_GODOT_CONTEXT`, `GodotSpecGuard`,
/// and `§02` / `§04` Studio contracts (`3D`: `1 unit = 1 m`, `2D`: pixel space).
enum GodotProjectDimension {
  dim3d,
  dim2d;

  String get id => name;

  String get shortLabel => switch (this) {
        GodotProjectDimension.dim3d => 'Godot 4 · 3D',
        GodotProjectDimension.dim2d => 'Godot 4 · 2D',
      };

  String get pillLabel => switch (this) {
        GodotProjectDimension.dim3d => '3D (m, m/s)',
        GodotProjectDimension.dim2d => '2D (px, px/s)',
      };

  String get fullLabel => switch (this) {
        GodotProjectDimension.dim3d =>
          'Godot 4.x 3D (1 unit = 1 m · CharacterBody3D + Node3D)',
        GodotProjectDimension.dim2d =>
          'Godot 4.x 2D (Pixel Space · CharacterBody2D + Node2D)',
      };

  String get architectureContract => switch (this) {
        GodotProjectDimension.dim3d =>
          'Godot 4 3D (.tscn + GDScript .gd) — CharacterBody3D / Node3D + @export Inspector tuning (1 unit = 1 m)',
        GodotProjectDimension.dim2d =>
          'Godot 4 2D (.tscn + GDScript .gd) — CharacterBody2D / Node2D + @export Inspector tuning (px, px/s)',
      };

  String get codePolicyContract => switch (this) {
        GodotProjectDimension.dim3d =>
          'PURE GODOT 4 GDSCRIPT (.gd + .tscn) — Use typed GDScript 2.0, @export snake_case tuning vars, CharacterBody3D/Area3D/SpringArm3D/Camera3D, and project.godot InputMap.',
        GodotProjectDimension.dim2d =>
          'PURE GODOT 4 GDSCRIPT (.gd + .tscn) — Use typed GDScript 2.0, @export snake_case tuning vars, CharacterBody2D/Area2D/Camera2D, and project.godot InputMap.',
      };

  String get tuningColumnLabel => '@export GDScript Var';

  String get inputContractLabel => 'InputMap Actions (project.godot)';

  String get distanceUnit => switch (this) {
        GodotProjectDimension.dim3d => 'm',
        GodotProjectDimension.dim2d => 'px',
      };

  String get speedUnit => switch (this) {
        GodotProjectDimension.dim3d => 'm/s',
        GodotProjectDimension.dim2d => 'px/s',
      };

  static GodotProjectDimension fromString(String? raw) {
    final lower = (raw ?? '').trim().toLowerCase();
    if (lower == 'dim2d' || lower == '2d' || lower.contains('2d')) {
      return GodotProjectDimension.dim2d;
    }
    return GodotProjectDimension.dim3d;
  }

  static GodotProjectDimension detectFromSpark(String sparkPrompt) {
    final lower = sparkPrompt.trim().toLowerCase();
    if (lower.isEmpty) return GodotProjectDimension.dim3d;
    if (RegExp(
      r'\b(?:2d|pixel[- ]?art|side[- ]?scroller|metroidvania|platformer\s*2d|top[- ]?down\s*2d|tilemap|spritesheet)\b',
    ).hasMatch(lower)) {
      return GodotProjectDimension.dim2d;
    }
    return GodotProjectDimension.dim3d;
  }
}

enum EpicLifecycle {
  queued,
  active,
  stable,
  upgrading,
  newEpic;

  static EpicLifecycle fromString(String? raw) {
    final lower = (raw ?? '').trim().toLowerCase();
    return switch (lower) {
      'active' => EpicLifecycle.active,
      'stable' || 'baseline' => EpicLifecycle.stable,
      'upgrading' => EpicLifecycle.upgrading,
      'new' || 'newepic' || 'new_epic' => EpicLifecycle.newEpic,
      _ => EpicLifecycle.queued,
    };
  }
}

class EpicControlBinding {
  String action;
  String trigger;
  String rule;

  EpicControlBinding({
    required this.action,
    required this.trigger,
    required this.rule,
  });

  EpicControlBinding copyWith({
    String? action,
    String? trigger,
    String? rule,
  }) {
    return EpicControlBinding(
      action: action ?? this.action,
      trigger: trigger ?? this.trigger,
      rule: rule ?? this.rule,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'action': action,
        'trigger': trigger,
        'rule': rule,
      };

  factory EpicControlBinding.fromJson(Map<String, dynamic> json) {
    return EpicControlBinding(
      action: (json['action'] ?? 'primary_action').toString().trim(),
      trigger: (json['trigger'] ?? 'Just Pressed').toString().trim(),
      rule: (json['rule'] ?? '').toString().trim(),
    );
  }
}

class EpicTuningParam {
  String key;
  String value;
  String unit;

  EpicTuningParam({
    required this.key,
    required this.value,
    required this.unit,
  });

  EpicTuningParam copyWith({
    String? key,
    String? value,
    String? unit,
  }) {
    return EpicTuningParam(
      key: key ?? this.key,
      value: value ?? this.value,
      unit: unit ?? this.unit,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'value': value,
        'unit': unit,
      };

  factory EpicTuningParam.fromJson(Map<String, dynamic> json) {
    return EpicTuningParam(
      key: (json['key'] ?? 'param').toString().trim(),
      value: (json['value'] ?? '0').toString().trim(),
      unit: (json['unit'] ?? '').toString().trim(),
    );
  }
}

class EpicPieCheck {
  String id;
  String text;
  bool passed;

  EpicPieCheck({
    required this.id,
    required this.text,
    this.passed = false,
  });

  EpicPieCheck copyWith({
    String? id,
    String? text,
    bool? passed,
  }) {
    return EpicPieCheck(
      id: id ?? this.id,
      text: text ?? this.text,
      passed: passed ?? this.passed,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        'passed': passed,
      };

  factory EpicPieCheck.fromJson(Map<String, dynamic> json, [int idx = 0]) {
    return EpicPieCheck(
      id: (json['id'] ?? 'chk_${idx + 1}').toString(),
      text: (json['text'] ?? '').toString().trim(),
      passed: json['passed'] == true,
    );
  }
}

class EpicPieFix {
  String id;
  String text;
  bool resolved;
  int createdAtMs;

  EpicPieFix({
    required this.id,
    required this.text,
    this.resolved = false,
    int? createdAtMs,
  }) : createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch;

  EpicPieFix copyWith({
    String? id,
    String? text,
    bool? resolved,
    int? createdAtMs,
  }) {
    return EpicPieFix(
      id: id ?? this.id,
      text: text ?? this.text,
      resolved: resolved ?? this.resolved,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        'resolved': resolved,
        'createdAtMs': createdAtMs,
      };

  factory EpicPieFix.fromJson(Map<String, dynamic> json, [int idx = 0]) {
    return EpicPieFix(
      id: (json['id'] ?? 'fix_${idx + 1}').toString(),
      text: (json['text'] ?? '').toString().trim(),
      resolved: json['resolved'] == true,
      createdAtMs: (json['createdAtMs'] is num)
          ? (json['createdAtMs'] as num).toInt()
          : int.tryParse((json['createdAtMs'] ?? '').toString()) ?? 0,
    );
  }
}

class EpicUpgradeOption {
  String id;
  String text;
  bool chosen;

  EpicUpgradeOption({
    required this.id,
    required this.text,
    this.chosen = false,
  });

  EpicUpgradeOption copyWith({
    String? id,
    String? text,
    bool? chosen,
  }) {
    return EpicUpgradeOption(
      id: id ?? this.id,
      text: text ?? this.text,
      chosen: chosen ?? this.chosen,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        'chosen': chosen,
      };

  factory EpicUpgradeOption.fromJson(Map<String, dynamic> json, [int idx = 0]) {
    return EpicUpgradeOption(
      id: (json['id'] ?? 'up_${idx + 1}').toString(),
      text: (json['text'] ?? '').toString().trim(),
      chosen: json['chosen'] == true,
    );
  }
}

class ReleaseDirectionPreset {
  final String id;
  final String label;
  final String description;
  final List<String> upgradeIds;
  final List<String> newEpicIds;

  const ReleaseDirectionPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.upgradeIds,
    required this.newEpicIds,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'desc': description,
        'upgrades': upgradeIds,
        'newEpics': newEpicIds,
      };

  factory ReleaseDirectionPreset.fromJson(Map<String, dynamic> json) {
    return ReleaseDirectionPreset(
      id: (json['id'] ?? 'preset').toString(),
      label: (json['label'] ?? 'Release Direction').toString(),
      description: (json['desc'] ?? json['description'] ?? '').toString(),
      upgradeIds: _strList(json['upgrades']),
      newEpicIds: _strList(json['newEpics']),
    );
  }
}

class ProgressiveReleaseDraft {
  final String targetVersion;
  List<ReleaseDirectionPreset> presets;
  Map<String, List<EpicUpgradeOption>> upgradesByLineageKey;
  List<EpicSpec> candidateNewEpics;
  String? activePresetId;

  ProgressiveReleaseDraft({
    required this.targetVersion,
    required this.presets,
    required this.upgradesByLineageKey,
    required this.candidateNewEpics,
    this.activePresetId,
  });

  ProgressiveReleaseDraft deepCopy() {
    return ProgressiveReleaseDraft(
      targetVersion: targetVersion,
      presets: List<ReleaseDirectionPreset>.from(presets),
      upgradesByLineageKey: {
        for (final e in upgradesByLineageKey.entries)
          e.key: [for (final u in e.value) u.copyWith()],
      },
      candidateNewEpics: [
        for (final ep in candidateNewEpics) ep.deepCopy(),
      ],
      activePresetId: activePresetId,
    );
  }
}

List<String> _strList(dynamic raw) {
  if (raw is! List) return <String>[];
  return raw
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Canonical 6-Section Godot 4 Epic Spec (`Project -> Release -> Epic`).
/// Single-pass Epic contract: "What You Read Is What Godot 4 Builds".
class EpicSpec {
  static String formatCode(int oneBasedIndex) =>
      'E${oneBasedIndex.toString().padLeft(2, '0')}';

  static String formatLineageKey(int oneBasedIndex) =>
      'e${oneBasedIndex.toString().padLeft(2, '0')}';

  final String id;
  String code;
  String lineageKey;
  String title;
  String releaseVersion;
  EpicLifecycle lifecycle;

  // §01 System Intent & Actor Links
  String coreLoopBeat;
  String goal;
  List<String> links;
  List<String> outOfScope;

  // §02 Controls
  List<EpicControlBinding> controls;

  // §03 State Flow & Interrupt Rules
  List<String> states;
  List<String> interrupts;

  // §04 Spatial & Exposed Tuning (@export GDScript Vars)
  List<EpicTuningParam> tuning;

  // §05 Viewport, UI & Audio Cues
  List<String> feedback;

  // §06 Test Scene Staging & Playtest Acceptance Gate
  String levelStaging;
  List<EpicPieCheck> checks;
  List<EpicPieFix> fixes;

  // Progressive Release Co-Pilot deltas & baseline lock metadata
  List<String> baselineSummary;
  List<String> upgradeDeltas;
  List<EpicUpgradeOption> copilotUpgrades;
  bool chosenForNextRelease;

  EpicSpec({
    required this.id,
    required this.code,
    String? lineageKey,
    required this.title,
    this.releaseVersion = 'v0.1',
    this.lifecycle = EpicLifecycle.queued,
    this.coreLoopBeat = '',
    required this.goal,
    List<String>? links,
    List<String>? outOfScope,
    List<EpicControlBinding>? controls,
    List<String>? states,
    List<String>? interrupts,
    List<EpicTuningParam>? tuning,
    List<String>? feedback,
    this.levelStaging = '',
    List<EpicPieCheck>? checks,
    List<EpicPieFix>? fixes,
    List<String>? baselineSummary,
    List<String>? upgradeDeltas,
    List<EpicUpgradeOption>? copilotUpgrades,
    this.chosenForNextRelease = false,
  })  : lineageKey = (lineageKey != null && lineageKey.trim().isNotEmpty)
            ? lineageKey.trim()
            : code.toLowerCase(),
        links = links ?? <String>[],
        outOfScope = outOfScope ?? <String>[],
        controls = controls ?? <EpicControlBinding>[],
        states = states ?? <String>[],
        interrupts = interrupts ?? <String>[],
        tuning = tuning ?? <EpicTuningParam>[],
        feedback = feedback ?? <String>[],
        checks = checks ?? <EpicPieCheck>[],
        fixes = fixes ?? <EpicPieFix>[],
        baselineSummary = baselineSummary ?? <String>[],
        upgradeDeltas = upgradeDeltas ?? <String>[],
        copilotUpgrades = copilotUpgrades ?? <EpicUpgradeOption>[];

  List<EpicPieFix> get openFixes => fixes.where((f) => !f.resolved).toList();

  int get openFixesCount => fixes.where((f) => !f.resolved).length;

  int get passedChecksCount => checks.where((c) => c.passed).length;

  bool get allChecksPassed =>
      checks.isNotEmpty && checks.every((c) => c.passed);

  bool get isPassed =>
      openFixes.isEmpty &&
      lifecycle == EpicLifecycle.stable &&
      (checks.isEmpty || checks.every((c) => c.passed));

  int get progressPercent {
    if (isPassed) return 100;
    if (checks.isEmpty) return 0;
    return ((passedChecksCount / checks.length) * 90).round();
  }

  String get statusLabel {
    if (openFixesCount > 0) return '$openFixesCount [FIX] Open';
    if (isPassed) return 'Baseline ✓';
    if (allChecksPassed) return 'Ready to Pass';
    if (lifecycle == EpicLifecycle.upgrading) return 'Upgrading $releaseVersion';
    if (lifecycle == EpicLifecycle.newEpic) return 'NEW $releaseVersion';
    if (passedChecksCount > 0 || lifecycle == EpicLifecycle.active) {
      return 'In Progress';
    }
    return 'Queued';
  }

  EpicSpec deepCopy({
    String? idOverride,
    String? releaseVersionOverride,
    EpicLifecycle? lifecycleOverride,
  }) {
    return EpicSpec(
      id: idOverride ?? id,
      code: code,
      lineageKey: lineageKey,
      title: title,
      releaseVersion: releaseVersionOverride ?? releaseVersion,
      lifecycle: lifecycleOverride ?? lifecycle,
      coreLoopBeat: coreLoopBeat,
      goal: goal,
      links: List<String>.from(links),
      outOfScope: List<String>.from(outOfScope),
      controls: [for (final c in controls) c.copyWith()],
      states: List<String>.from(states),
      interrupts: List<String>.from(interrupts),
      tuning: [for (final t in tuning) t.copyWith()],
      feedback: List<String>.from(feedback),
      levelStaging: levelStaging,
      checks: [for (final c in checks) c.copyWith()],
      fixes: [for (final f in fixes) f.copyWith()],
      baselineSummary: List<String>.from(baselineSummary),
      upgradeDeltas: List<String>.from(upgradeDeltas),
      copilotUpgrades: [for (final u in copilotUpgrades) u.copyWith()],
      chosenForNextRelease: chosenForNextRelease,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'code': code,
        'lineageKey': lineageKey,
        'title': title,
        'releaseVersion': releaseVersion,
        'lifecycle': lifecycle.name,
        'coreLoopBeat': coreLoopBeat,
        'goal': goal,
        'links': links,
        'outOfScope': outOfScope,
        'controls': [for (final c in controls) c.toJson()],
        'states': states,
        'interrupts': interrupts,
        'tuning': [for (final t in tuning) t.toJson()],
        'feedback': feedback,
        'levelStaging': levelStaging,
        'checks': [for (final c in checks) c.toJson()],
        'fixes': [for (final f in fixes) f.toJson()],
        'baselineSummary': baselineSummary,
        'upgradeDeltas': upgradeDeltas,
        'copilotUpgrades': [for (final u in copilotUpgrades) u.toJson()],
        'chosen': chosenForNextRelease,
      };

  factory EpicSpec.fromJson(Map<String, dynamic> json, {int indexHint = 0}) {
    final fallbackCode = formatCode(indexHint + 1);
    final rawCode = (json['code'] ?? fallbackCode).toString().trim();
    final rawChecks = json['checks'] as List? ?? const [];
    final rawFixes = json['fixes'] as List? ?? const [];
    final rawControls = json['controls'] as List? ?? const [];
    final rawTuning = json['tuning'] as List? ?? const [];
    final rawUps = json['copilotUpgrades'] as List? ?? const [];

    return EpicSpec(
      id: (json['id'] ?? json['chosenId'] ?? 'epic_${indexHint + 1}')
          .toString(),
      code: rawCode.isEmpty ? fallbackCode : rawCode,
      lineageKey: (json['lineageKey'] ?? rawCode.toLowerCase()).toString(),
      title: (json['title'] ?? 'Untitled System').toString().trim(),
      releaseVersion: (json['releaseVersion'] ?? 'v0.1').toString().trim(),
      lifecycle: EpicLifecycle.fromString(json['lifecycle']?.toString()),
      coreLoopBeat: (json['coreLoopBeat'] ?? '').toString().trim(),
      goal: (json['goal'] ?? '').toString().trim(),
      links: _strList(json['links'] ?? json['plugsInto']),
      outOfScope: _strList(json['outOfScope']),
      controls: [
        for (final item in rawControls)
          if (item is Map)
            EpicControlBinding.fromJson(Map<String, dynamic>.from(item)),
      ],
      states: _strList(json['states']),
      interrupts: _strList(json['interrupts']),
      tuning: [
        for (final item in rawTuning)
          if (item is Map)
            EpicTuningParam.fromJson(Map<String, dynamic>.from(item)),
      ],
      feedback: _strList(json['feedback']),
      levelStaging: (json['levelStaging'] ?? '').toString().trim(),
      checks: [
        for (int i = 0; i < rawChecks.length; i++)
          if (rawChecks[i] is Map)
            EpicPieCheck.fromJson(
              Map<String, dynamic>.from(rawChecks[i] as Map),
              i,
            )
          else if (rawChecks[i] is String &&
              rawChecks[i].toString().trim().isNotEmpty)
            EpicPieCheck(
              id: 'chk_${i + 1}',
              text: rawChecks[i].toString().trim(),
            ),
      ],
      fixes: [
        for (int i = 0; i < rawFixes.length; i++)
          if (rawFixes[i] is Map)
            EpicPieFix.fromJson(
              Map<String, dynamic>.from(rawFixes[i] as Map),
              i,
            )
          else if (rawFixes[i] is String &&
              rawFixes[i].toString().trim().isNotEmpty)
            EpicPieFix(
              id: 'fix_${i + 1}',
              text: rawFixes[i].toString().trim(),
            ),
      ],
      baselineSummary: _strList(json['baselineSummary']),
      upgradeDeltas: _strList(json['upgradeDeltas']),
      copilotUpgrades: [
        for (int i = 0; i < rawUps.length; i++)
          if (rawUps[i] is Map)
            EpicUpgradeOption.fromJson(
              Map<String, dynamic>.from(rawUps[i] as Map),
              i,
            ),
      ],
      chosenForNextRelease: json['chosen'] == true,
    );
  }

  /// Hydrates an [EpicSpec] from a persisted [TierDocument] (`TierType.epic`).
  factory EpicSpec.fromDocument(TierDocument doc, {int indexHint = 0}) {
    final rawJson = doc.sections['epic_spec_json'];
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map) {
          final parsed = EpicSpec.fromJson(
            Map<String, dynamic>.from(decoded),
            indexHint: indexHint,
          );
          final syncedChecks = parsed.checks.isNotEmpty
              ? parsed.checks
              : [
                  for (int i = 0; i < doc.subtasks.length; i++)
                    EpicPieCheck(
                      id: doc.subtasks[i].id,
                      text: doc.subtasks[i].text,
                      passed: doc.subtasks[i].completed,
                    ),
                ];
          return EpicSpec(
            id: doc.id,
            code: (doc.sections['code'] ?? '').trim().isNotEmpty
                ? doc.sections['code']!.trim()
                : parsed.code,
            lineageKey: (doc.sections['lineage_key'] ?? '').trim().isNotEmpty
                ? doc.sections['lineage_key']!.trim()
                : parsed.lineageKey,
            title: doc.title.trim().isNotEmpty ? doc.title : parsed.title,
            releaseVersion:
                (doc.sections['release_version'] ?? '').trim().isNotEmpty
                    ? doc.sections['release_version']!.trim()
                    : parsed.releaseVersion,
            lifecycle: (doc.sections['lifecycle'] ?? '').trim().isNotEmpty
                ? EpicLifecycle.fromString(doc.sections['lifecycle'])
                : parsed.lifecycle,
            coreLoopBeat: parsed.coreLoopBeat,
            goal: parsed.goal.isNotEmpty
                ? parsed.goal
                : (doc.sections['goal'] ?? ''),
            links: parsed.links,
            outOfScope: parsed.outOfScope,
            controls: parsed.controls,
            states: parsed.states,
            interrupts: parsed.interrupts,
            tuning: parsed.tuning,
            feedback: parsed.feedback,
            levelStaging: parsed.levelStaging,
            checks: syncedChecks,
            fixes: parsed.fixes,
            baselineSummary: parsed.baselineSummary,
            upgradeDeltas: parsed.upgradeDeltas,
            copilotUpgrades: parsed.copilotUpgrades,
            chosenForNextRelease: parsed.chosenForNextRelease,
          );
        }
      } catch (_) {}
    }

    final defaultCode = formatCode(indexHint + 1);
    final fallbackCode = (doc.sections['code'] ?? defaultCode).trim();
    return EpicSpec(
      id: doc.id,
      code: fallbackCode.isEmpty ? defaultCode : fallbackCode,
      lineageKey: doc.sections['lineage_key'] ?? fallbackCode.toLowerCase(),
      title: doc.title,
      releaseVersion: doc.sections['release_version'] ?? 'v0.1',
      lifecycle: doc.isCompleted
          ? EpicLifecycle.stable
          : EpicLifecycle.fromString(doc.sections['lifecycle']),
      goal: doc.sections['goal'] ?? doc.sections['scope'] ?? doc.title,
      checks: [
        for (int i = 0; i < doc.subtasks.length; i++)
          EpicPieCheck(
            id: doc.subtasks[i].id,
            text: doc.subtasks[i].text,
            passed: doc.subtasks[i].completed,
          ),
      ],
    );
  }

  /// Writes this [EpicSpec] cleanly back into a [TierDocument] for local/Cloud sync.
  TierDocument applyToDocument(TierDocument existing) {
    final nextSections = Map<String, String>.from(existing.sections);
    final payloadSpec = EpicSpec(
      id: existing.id,
      code: code,
      lineageKey: lineageKey,
      title: title,
      releaseVersion: releaseVersion,
      lifecycle: lifecycle,
      coreLoopBeat: coreLoopBeat,
      goal: goal,
      links: links,
      outOfScope: outOfScope,
      controls: controls,
      states: states,
      interrupts: interrupts,
      tuning: tuning,
      feedback: feedback,
      levelStaging: levelStaging,
      checks: checks,
      fixes: fixes,
      baselineSummary: baselineSummary,
      upgradeDeltas: upgradeDeltas,
      copilotUpgrades: copilotUpgrades,
      chosenForNextRelease: chosenForNextRelease,
    );
    nextSections['code'] = code;
    nextSections['lineage_key'] = lineageKey;
    nextSections['release_version'] = releaseVersion;
    nextSections['lifecycle'] = lifecycle.name;
    nextSections['goal'] = goal;
    nextSections['epic_spec_json'] = jsonEncode(payloadSpec.toJson());
    nextSections['updated_at_ms'] =
        DateTime.now().millisecondsSinceEpoch.toString();

    return existing.copyWith(
      title: title,
      tier: TierType.epic,
      sections: nextSections,
      isCompleted: isPassed,
      subtasks: [
        for (final c in checks)
          Subtask(id: c.id, text: c.text, completed: c.passed),
      ],
    );
  }

  TierDocument toTierDocument({
    required String docId,
    required String parentReleaseId,
  }) {
    final base = TierDocument(
      id: docId,
      title: title,
      tier: TierType.epic,
      parentId: parentReleaseId,
      childrenIds: const <String>[],
      estimatedDuration: '1h',
      icon: 'E',
      isCompleted: isPassed,
    );
    return applyToDocument(base);
  }
}
