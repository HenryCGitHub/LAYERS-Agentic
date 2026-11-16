import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import 'unreal_spec_guard.dart';

/// Deterministic single-source-of-truth Markdown compiler for Unreal MCP payloads.
/// Matches `buildRootMcpMarkdown` and `buildEpicMcpMarkdown` in the approved v3 spec UI
/// and feeds `LayersBridge` (`layers_get_active_epic_spec`) via Cloud Functions.
class UnrealMcpPayloadBuilder {
  static void _writeContextList(
    StringBuffer b,
    String label,
    dynamic raw,
    int cap,
  ) {
    if (raw is! List || raw.isEmpty) return;
    final clean = raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .take(cap)
        .toList();
    if (clean.isEmpty) return;
    b.writeln('- $label: ${clean.join(', ')}');
  }

  /// Builds `ROOT_MCP_CONTEXT` (Prepended to every Epic payload sent to Unreal MCP).
  static String buildRootMcpContext(
    ProjectConceptBlueprint rootSpec, {
    UnrealTargetEngine? targetOverride,
    Map<String, dynamic>? liveUprojectContext,
  }) {
    final target = targetOverride ?? rootSpec.targetEngine;
    final b = StringBuffer();
    b.writeln('# ROOT_MCP_CONTEXT · ${rootSpec.normalizedTitle}');
    b.writeln('Target Architecture: ${target.architectureContract}');
    b.writeln();
    b.writeln('## §01 Concept & 30s Core Loop');
    b.writeln('- Vision: ${rootSpec.pitch.trim()}');
    if (rootSpec.coreLoop.isNotEmpty) {
      b.writeln('- Loop: ${rootSpec.coreLoop.join(' -> ')}');
    }
    b.writeln();
    b.writeln('## §02 Global Unreal Contracts (1 UU = 1 cm)');
    b.writeln('- Camera & Boom: ${rootSpec.cameraContract.trim()}');
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

    if (liveUprojectContext != null && liveUprojectContext.isNotEmpty) {
      b.writeln();
      b.writeln('## Live Unreal Project Snapshot (.uproject via LayersBridge)');
      final projName = (liveUprojectContext['project_name'] ?? '').toString().trim();
      final level = (liveUprojectContext['current_level'] ?? '').toString().trim();
      final gameMode = (liveUprojectContext['game_mode'] ?? '').toString().trim();
      final pawn = (liveUprojectContext['default_pawn'] ?? '').toString().trim();
      if (projName.isNotEmpty) b.writeln('- Project: $projName');
      if (level.isNotEmpty) b.writeln('- Open Level: $level');
      if (gameMode.isNotEmpty) b.writeln('- GameMode: $gameMode');
      if (pawn.isNotEmpty) b.writeln('- DefaultPawnClass: $pawn');
      _writeContextList(
        b,
        'Existing Enhanced Input Assets',
        liveUprojectContext['input_assets'],
        12,
      );
      _writeContextList(
        b,
        'Existing Blueprints',
        liveUprojectContext['blueprint_assets'],
        12,
      );
      _writeContextList(
        b,
        'Existing DataAssets & Tables',
        liveUprojectContext['data_assets'],
        8,
      );
      _writeContextList(
        b,
        'Existing UMG Widgets',
        liveUprojectContext['widget_assets'],
        8,
      );
      _writeContextList(
        b,
        'Existing Levels',
        liveUprojectContext['level_assets'],
        6,
      );
      _writeContextList(
        b,
        'Existing Verse Files',
        liveUprojectContext['verse_files'],
        8,
      );
      final recentErrors = liveUprojectContext['recent_errors'];
      if (recentErrors is List && recentErrors.isNotEmpty) {
        b.writeln('- Recent Editor/PIE Log Warnings:');
        for (final err in recentErrors.take(4)) {
          b.writeln('  - $err');
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
            '- [BUILT ✓] ${sib.code} · ${sib.title} — preserve & reuse existing assets',
          );
        }
      } else {
        b.writeln(
          '- [QUEUED — DEFER] ${sib.code} · ${sib.title} — do not build yet; stub interfaces only if needed',
        );
      }
    }
  }

  /// Builds the exact Unreal MCP wire payload for an Epic (`ROOT_MCP_CONTEXT` + `ACTIVE EPIC SPEC`).
  /// Automatically switches footer instructions between:
  /// - `FOCUSED PIE REVISION PASS (N OPEN [FIX])` when any unresolved `[FIX]` exists, or
  /// - `FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK` for single-pass build.
  static String buildEpicMcpPayload({
    required ProjectConceptBlueprint rootSpec,
    required EpicSpec epic,
    List<EpicSpec>? releaseEpics,
    UnrealTargetEngine? targetOverride,
    Map<String, dynamic>? liveUprojectContext,
    bool includeRootContext = true,
    bool includeExecutionFooter = true,
  }) {
    final target = targetOverride ?? rootSpec.targetEngine;
    final b = StringBuffer();

    if (includeRootContext) {
      b.writeln(
        buildRootMcpContext(
          rootSpec,
          targetOverride: target,
          liveUprojectContext: liveUprojectContext,
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
        'Execution Mode: FOCUSED PIE REVISION PASS (${openFixes.length} OPEN [FIX]) — surgical edits only; keep passing checks intact',
      );
    } else if (includeExecutionFooter) {
      b.writeln('Execution Mode: FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK');
    }
    b.writeln();
    b.writeln('## §01 System Intent & Actor Links');
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
    b.writeln('## §02 Controls (${target.inputContractLabel})');
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
      b.writeln('- Stateless / event-driven Epic');
    } else {
      for (final s in epic.states) {
        b.writeln('- State: $s');
      }
      for (final rule in epic.interrupts) {
        b.writeln('- Interrupt: $rule');
      }
    }

    b.writeln();
    b.writeln('## §04 Spatial & Exposed Tuning (${target.tuningColumnLabel})');
    if (epic.tuning.isEmpty) {
      b.writeln('- None');
    } else {
      final isUe6 = target == UnrealTargetEngine.ue6Verse;
      for (final t in epic.tuning) {
        final unitSuffix = t.unit.trim().isEmpty ? '' : ' ${t.unit.trim()}';
        final propType = UnrealSpecGuard.inferUnrealPropertyType(
          t.value,
          t.unit,
          isUe6Verse: isUe6,
        );
        b.writeln('- ${t.key}: ${t.value}$unitSuffix [$propType]');
      }
    }

    b.writeln();
    b.writeln('## §05 Viewport, UMG & Audio Cues');
    if (epic.feedback.isEmpty) {
      b.writeln('- Minimal greybox debug visuals');
    } else {
      for (final f in epic.feedback) {
        b.writeln('- $f');
      }
    }

    b.writeln();
    b.writeln('## §06 Test Level Staging & PIE Acceptance Gate');
    if (epic.levelStaging.trim().isNotEmpty) {
      b.writeln('- Test Level: ${epic.levelStaging.trim()}');
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
        '### FOCUSED PIE REVISION PASS (${openFixes.length} OPEN [FIX])',
      );
      b.writeln(
        'Targeted edits only to resolve every open [FIX] item above; keep already-passing checks intact, compile/save modified Blueprint/Verse assets, and report via layers_resolve_pie_fix(fix_id) + layers_toggle_pie_check(check_id, passed=true). Do NOT call layers_pass_active_epic (reserved for human PIE sign-off).',
      );
    } else if (includeExecutionFooter) {
      b.writeln();
      b.writeln('### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK');
      b.writeln(
        'Implement §01-§06 in one Unreal MCP pass matching ROOT_MCP_CONTEXT contracts, expose every §04 tuning variable, then run PIE self-check against every §06 Check and call layers_toggle_pie_check(check_id, passed=true). Do NOT call layers_pass_active_epic (reserved for human PIE sign-off).',
      );
    }

    return b.toString().trimRight();
  }

  /// Builds the full project Markdown export (`PROJECT_SPEC.md` + all planned releases & Epics).
  static String buildFullProjectSpecMarkdown({
    required ProjectConceptBlueprint rootSpec,
    required Map<String, List<EpicSpec>> epicsByReleaseLabel,
    Map<String, dynamic>? liveUprojectContext,
  }) {
    final b = StringBuffer();
    b.writeln(
      buildRootMcpContext(
        rootSpec,
        liveUprojectContext: liveUprojectContext,
      ),
    );
    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln('# Release Roadmap & Unreal MCP Epic Specs');
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
          buildEpicMcpPayload(
            rootSpec: rootSpec,
            epic: epic,
            includeRootContext: false,
            includeExecutionFooter: epic.openFixes.isNotEmpty,
          ),
        );
      }
    }
    return b.toString().trimRight();
  }

  /// Builds a copy/export bundle for the active Release (for coding agents / Unreal MCP).
  static String buildReleaseMcpBundle({
    required ProjectConceptBlueprint rootSpec,
    required String releaseLabel,
    required List<EpicSpec> releaseEpics,
    Map<String, dynamic>? liveUprojectContext,
  }) {
    final b = StringBuffer();
    b.writeln(
      buildRootMcpContext(
        rootSpec,
        liveUprojectContext: liveUprojectContext,
      ),
    );
    b.writeln();
    b.writeln('---');
    b.writeln('# ACTIVE RELEASE BUNDLE · $releaseLabel');
    final effectiveEpics =
        releaseEpics.isNotEmpty ? releaseEpics : rootSpec.initialEpics;
    for (int i = 0; i < effectiveEpics.length; i++) {
      final epic = effectiveEpics[i];
      b.writeln();
      b.writeln(
        buildEpicMcpPayload(
          rootSpec: rootSpec,
          epic: epic,
          includeRootContext: false,
          includeExecutionFooter: epic.openFixes.isNotEmpty,
        ),
      );
      if (i < effectiveEpics.length - 1) {
        b.writeln();
        b.writeln('---');
      }
    }
    if (effectiveEpics.isNotEmpty) {
      b.writeln();
      b.writeln('### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK');
      b.writeln(
        'Implement §01-§06 per Epic in one Unreal MCP pass matching ROOT_MCP_CONTEXT contracts, expose every §04 tuning variable, then run PIE self-check against every §06 Check and call layers_toggle_pie_check(check_id, passed=true). Do NOT call layers_pass_active_epic (reserved for human PIE sign-off).',
      );
    }
    return b.toString().trimRight();
  }
}
