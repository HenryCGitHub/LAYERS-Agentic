import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import 'godot_spec_guard.dart';

/// Single Source of Truth that formats `ProjectConceptBlueprint` + `EpicSpec`
/// into exact Godot 4 AI context markdown (mirrored 1:1 in `functions/index.js`).
class GodotContextBuilder {
  const GodotContextBuilder._();

  static void _addContextListLine(
    List<String> out,
    String label,
    dynamic rawList,
    int cap,
  ) {
    if (rawList is! List || rawList.isEmpty) return;
    final clean = rawList
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .take(cap)
        .toList();
    if (clean.isEmpty) return;
    out.add('- $label: ${clean.join(', ')}');
  }

  /// Builds `ROOT_GODOT_CONTEXT` (Prepended to every Epic payload used by Godot 4 AI Builder).
  static String buildRootGodotContext(
    ProjectConceptBlueprint rootSpec, {
    GodotProjectDimension? dimensionOverride,
    Map<String, dynamic>? liveGodotContext,
  }) {
    final dim = dimensionOverride ?? rootSpec.dimension;
    final b = StringBuffer();
    b.writeln('# ROOT_GODOT_CONTEXT · ${rootSpec.normalizedTitle}');
    b.writeln('Target Architecture: ${dim.architectureContract}');
    b.writeln('Code Policy: ${dim.codePolicyContract}');
    b.writeln();
    b.writeln('## §01 Concept & 30s Core Loop');
    b.writeln('- Vision: ${rootSpec.pitch.trim()}');
    if (rootSpec.coreLoop.isNotEmpty) {
      b.writeln('- Loop: ${rootSpec.coreLoop.join(' -> ')}');
    }
    if (rootSpec.releaseDoneWhen.trim().isNotEmpty) {
      b.writeln('- Release Gate: ${rootSpec.releaseDoneWhen.trim()}');
    }
    b.writeln();
    b.writeln('## §02 Global Godot 4 Contracts (${dim.pillLabel})');
    b.writeln('- Camera Rig: ${rootSpec.cameraContract.trim()}');
    b.writeln('- Player Scale: ${rootSpec.characterScale.trim()}');
    b.writeln('- Input Contract: ${rootSpec.inputContract.trim()}');
    b.writeln('- Asset Policy: ${rootSpec.assetPolicy.trim()}');
    b.writeln();
    b.writeln('## §03 Pillars & Conflict Trade-Offs');
    b.writeln('- Core Feel: ${rootSpec.selectedCoreFeelOption.label}');
    for (final pillar in rootSpec.pillars) {
      b.writeln('- Pillar: $pillar');
    }
    for (final tradeOff in rootSpec.tradeOffs) {
      b.writeln('- Trade-Off: ${tradeOff.formatted}');
    }
    if (rootSpec.outOfScope.isNotEmpty) {
      b.writeln();
      b.writeln('## §04 Hard Scope Cuts (Do Not Build)');
      for (final cut in rootSpec.outOfScope) {
        b.writeln('- $cut');
      }
    }

    if (liveGodotContext != null && liveGodotContext.isNotEmpty) {
      final snapshotLines = <String>[];
      final projName = (liveGodotContext['project_name'] ?? '').toString().trim();
      final mainScene = (liveGodotContext['main_scene'] ?? '').toString().trim();
      if (projName.isNotEmpty) snapshotLines.add('- Project: $projName');
      if (mainScene.isNotEmpty) snapshotLines.add('- Main Scene: $mainScene');
      _addContextListLine(
        snapshotLines,
        'Existing InputMap Actions',
        liveGodotContext['input_actions'],
        16,
      );
      _addContextListLine(
        snapshotLines,
        'Existing Scenes (.tscn)',
        liveGodotContext['scene_files'],
        12,
      );
      _addContextListLine(
        snapshotLines,
        'Existing Scripts (.gd)',
        liveGodotContext['script_files'],
        14,
      );
      _addContextListLine(
        snapshotLines,
        'Existing Resources (.tres)',
        liveGodotContext['resource_files'],
        8,
      );
      final recentErrors = liveGodotContext['recent_errors'];
      if (recentErrors is List && recentErrors.isNotEmpty) {
        final cleanErrors = recentErrors
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .take(4)
            .toList();
        if (cleanErrors.isNotEmpty) {
          snapshotLines.add('- Recent Editor/Debugger Errors:');
          for (final err in cleanErrors) {
            snapshotLines.add('  - $err');
          }
        }
      }
      if (snapshotLines.isNotEmpty) {
        b.writeln();
        b.writeln('## Live Godot Project Snapshot (project.godot via Dock)');
        for (final line in snapshotLines) {
          b.writeln(line);
        }
      }
    }

    return b.toString().trimRight();
  }

  static void _writeReleaseEpicRoadmap(
    StringBuffer b,
    EpicSpec activeEpic,
    List<EpicSpec>? releaseEpics,
  ) {
    if (releaseEpics == null || releaseEpics.length < 2) return;
    final passedCount = releaseEpics.where((e) => e.isPassed).length;
    b.writeln();
    b.writeln(
      '## Release Epic Roadmap (${activeEpic.releaseVersion} · $passedCount/${releaseEpics.length} Passed)',
    );
    for (final sib in releaseEpics) {
      final isCurrent = (activeEpic.id.isNotEmpty && sib.id == activeEpic.id) ||
          (activeEpic.id.isEmpty && sib.code == activeEpic.code);
      if (isCurrent) {
        b.writeln('- [ACTIVE →] ${sib.code} · ${sib.title} — build in this pass');
      } else if (sib.isPassed) {
        final seenContracts = <String>{};
        final contracts = <String>[];
        void addContract(String raw) {
          final clean = raw.trim();
          if (clean.isEmpty || contracts.length >= 3) return;
          if (seenContracts.add(clean.toLowerCase())) {
            contracts.add(clean);
          }
        }

        for (final link in sib.links.take(2)) {
          addContract(link);
        }
        for (final ctrl in sib.controls.take(2)) {
          addContract(ctrl.action);
        }
        if (contracts.isNotEmpty) {
          b.writeln(
            '- [BUILT ✓] ${sib.code} · ${sib.title} — preserve & reuse (${contracts.join(', ')})',
          );
        } else {
          b.writeln(
            '- [BUILT ✓] ${sib.code} · ${sib.title} — preserve & reuse existing scenes/scripts',
          );
        }
      } else {
        b.writeln(
          '- [QUEUED — DEFER] ${sib.code} · ${sib.title} — do not build yet; stub signals only if needed',
        );
      }
    }
  }

  /// Builds the exact Godot 4 AI context payload for an Epic (`ROOT_GODOT_CONTEXT` + `ACTIVE EPIC SPEC`).
  /// Automatically switches footer instructions between:
  /// - `FOCUSED PLAYTEST REVISION PASS (N OPEN [FIX])` when any unresolved `[FIX]` exists, or
  /// - `FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK` for single-pass build.
  static String buildEpicGodotContext({
    required ProjectConceptBlueprint rootSpec,
    required EpicSpec epic,
    List<EpicSpec>? releaseEpics,
    GodotProjectDimension? dimensionOverride,
    Map<String, dynamic>? liveGodotContext,
    bool includeRootContext = true,
    bool includeExecutionFooter = true,
  }) {
    final dim = dimensionOverride ?? rootSpec.dimension;
    final b = StringBuffer();

    if (includeRootContext) {
      b.writeln(
        buildRootGodotContext(
          rootSpec,
          dimensionOverride: dim,
          liveGodotContext: liveGodotContext,
        ),
      );
      _writeReleaseEpicRoadmap(b, epic, releaseEpics);
      b.writeln();
      b.writeln('---');
      b.writeln();
    }

    final openFixes = epic.openFixes;

    b.writeln(
      '# ACTIVE EPIC SPEC · ${epic.code} · ${epic.title} (${epic.releaseVersion})',
    );
    if (openFixes.isNotEmpty) {
      b.writeln(
        'Execution Mode: FOCUSED PLAYTEST REVISION PASS (${openFixes.length} OPEN [FIX]) — surgical edits only; keep passing checks intact',
      );
    } else if (includeExecutionFooter) {
      b.writeln('Execution Mode: FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK');
    }
    b.writeln();
    b.writeln('## §01 System Intent & Scene Links');
    if (epic.coreLoopBeat.trim().isNotEmpty) {
      b.writeln('- Core Loop Beat: ${epic.coreLoopBeat.trim()}');
    }
    b.writeln('- Goal: ${epic.goal.trim()}');
    if (epic.links.isNotEmpty) {
      b.writeln('- Links: ${epic.links.join(' · ')}');
    }
    if (epic.outOfScope.isNotEmpty) {
      b.writeln('- Out of Scope: ${epic.outOfScope.join('; ')}');
    }
    if (epic.baselineSummary.isNotEmpty &&
        (epic.releaseVersion != 'v0.1' || epic.upgradeDeltas.isNotEmpty)) {
      b.writeln('- Locked Baseline: ${epic.baselineSummary.join(' · ')}');
    }

    if (epic.upgradeDeltas.isNotEmpty) {
      b.writeln();
      b.writeln(
        '## ${epic.releaseVersion} Upgrade Deltas (atop locked v0.1 baseline)',
      );
      for (final delta in epic.upgradeDeltas) {
        final cleanDelta = delta.trim().replaceFirst(RegExp(r'^\+\s*'), '');
        if (cleanDelta.isNotEmpty) {
          b.writeln('- +$cleanDelta');
        }
      }
    }

    b.writeln();
    b.writeln('## §02 Controls (${dim.inputContractLabel})');
    if (epic.controls.isEmpty) {
      b.writeln('- None (passive/system-driven Epic)');
    } else {
      for (final c in epic.controls) {
        b.writeln('- ${c.action} | ${c.trigger} | ${c.rule}');
      }
    }

    b.writeln();
    b.writeln('## §03 State Flow & Interrupt Rules');
    if (epic.states.isEmpty && epic.interrupts.isEmpty) {
      b.writeln('- Stateless / signal-driven Epic');
    } else {
      for (final s in epic.states) {
        b.writeln('- State: $s');
      }
      for (final rule in epic.interrupts) {
        b.writeln('- Interrupt: $rule');
      }
    }

    b.writeln();
    b.writeln('## §04 Spatial & Exposed Tuning (${dim.tuningColumnLabel})');
    if (epic.tuning.isEmpty) {
      b.writeln('- None');
    } else {
      for (final t in epic.tuning) {
        final unitSuffix = t.unit.trim().isEmpty ? '' : ' ${t.unit.trim()}';
        final propType = GodotSpecGuard.inferGodotPropertyType(
          t.value,
          t.unit,
        );
        b.writeln('- ${t.key}: ${t.value}$unitSuffix [$propType]');
      }
    }

    b.writeln();
    b.writeln('## §05 Viewport, UI & Audio Cues');
    if (epic.feedback.isEmpty) {
      b.writeln('- Minimal greybox debug visuals');
    } else {
      for (final f in epic.feedback) {
        b.writeln('- $f');
      }
    }

    b.writeln();
    b.writeln('## §06 Test Scene Staging & Playtest Acceptance Gate');
    if (epic.levelStaging.trim().isNotEmpty) {
      b.writeln('- Test Scene: ${epic.levelStaging.trim()}');
    }
    for (int i = 0; i < epic.checks.length; i++) {
      final chk = epic.checks[i];
      final tag = chk.passed ? '[PASSED]' : '[VERIFY]';
      b.writeln('  $tag Check ${i + 1}: ${chk.text}');
    }

    if (openFixes.isNotEmpty) {
      b.writeln();
      b.writeln('## Open Playtest Revisions ([FIX])');
      for (final fx in openFixes) {
        final idTag = fx.id.trim().isNotEmpty ? ' (id: ${fx.id.trim()})' : '';
        b.writeln('- [FIX] ${fx.text}$idTag');
      }
      b.writeln();
      b.writeln(
        '### FOCUSED PLAYTEST REVISION PASS (${openFixes.length} OPEN [FIX])',
      );
      b.writeln(
        'Targeted edits only to resolve every open [FIX] item above; keep already-passing checks intact, emit compile-clean Godot 4 .gd/.tscn/${dim.shortLabel} updates, and leave final pass sign-off to human playtest.',
      );
    } else if (includeExecutionFooter) {
      b.writeln();
      b.writeln('### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK');
      b.writeln(
        'Synthesize §01-§06 cleanly into Godot 4 (${dim.shortLabel}: .gd scripts + .tscn sceneOps + project.godot inputOps) matching ROOT_GODOT_CONTEXT contracts, expose every §04 @export variable in snake_case, and ensure zero GDScript compile errors.',
      );
    }

    return b.toString().trimRight();
  }

  /// Builds the full project Markdown export (`PROJECT_SPEC.md` + all planned releases & Epics).
  static String buildFullProjectSpecMarkdown({
    required ProjectConceptBlueprint rootSpec,
    required Map<String, List<EpicSpec>> epicsByReleaseLabel,
    Map<String, dynamic>? liveGodotContext,
  }) {
    final b = StringBuffer();
    b.writeln(
      buildRootGodotContext(
        rootSpec,
        liveGodotContext: liveGodotContext,
      ),
    );
    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln('# Release Roadmap & Godot 4 Epic Specs');
    final effectiveReleases = epicsByReleaseLabel.isNotEmpty
        ? epicsByReleaseLabel
        : (rootSpec.initialEpics.isNotEmpty
            ? <String, List<EpicSpec>>{
                'v0.1 · Prototype': rootSpec.initialEpics,
              }
            : const <String, List<EpicSpec>>{});
    for (final entry in effectiveReleases.entries) {
      b.writeln();
      b.writeln('## Release ${entry.key}');
      for (final epic in entry.value) {
        b.writeln();
        b.writeln(
          buildEpicGodotContext(
            rootSpec: rootSpec,
            epic: epic,
            includeRootContext: false,
            includeExecutionFooter: false,
          ),
        );
      }
    }
    return b.toString().trimRight();
  }

  /// Builds a Release bundle (`ROOT_GODOT_CONTEXT` + all Epics in one release).
  static String buildReleaseContextBundle({
    required ProjectConceptBlueprint rootSpec,
    required String releaseLabel,
    required List<EpicSpec> releaseEpics,
    Map<String, dynamic>? liveGodotContext,
  }) {
    final b = StringBuffer();
    b.writeln(
      buildRootGodotContext(
        rootSpec,
        liveGodotContext: liveGodotContext,
      ),
    );
    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln('# RELEASE BUNDLE · $releaseLabel');
    for (final epic in releaseEpics) {
      b.writeln();
      b.writeln(
        buildEpicGodotContext(
          rootSpec: rootSpec,
          epic: epic,
          includeRootContext: false,
          includeExecutionFooter: false,
        ),
      );
    }
    return b.toString().trimRight();
  }
}
