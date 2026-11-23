import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import 'unreal_prompt_compactor.dart';
import 'unreal_spec_guard.dart';

export 'unreal_prompt_compactor.dart';

/// Formats `ProjectConceptBlueprint`, `EpicSpec`, and `FeatureSpec` into
/// Unreal Engine 5 GDD documents and Feature / `[FIX]` prompts for Ultimate Engine CoPilot.
class UnrealContextBuilder {
  const UnrealContextBuilder._();

  static String _s(String raw, UnrealArchitectureMode mode) =>
      UnrealSpecGuard.sanitizeLine(raw, mode: mode);

  static String _extractReleaseVersion(
    String rawLabel, {
    String fallback = 'v0.1',
  }) {
    final m =
        RegExp(r'v\d+(?:\.\d+)*', caseSensitive: false).firstMatch(rawLabel);
    if (m != null) return m.group(0)!.toLowerCase();
    final cleanFallback = fallback.trim();
    return cleanFallback.isEmpty ? 'v0.1' : cleanFallback;
  }

  static List<MapEntry<String, List<EpicSpec>>> _sortedReleaseEntries(
    Map<String, List<EpicSpec>> map,
  ) {
    final entries = map.entries.toList();
    entries.sort(
      (a, b) => compareReleaseVersions(
        _extractReleaseVersion(a.key),
        _extractReleaseVersion(b.key),
        const [],
      ),
    );
    return entries;
  }

  static void _writeRootSections(
    StringBuffer b,
    ProjectConceptBlueprint rootSpec,
    UnrealArchitectureMode mode,
  ) {
    b.writeln('Target Architecture: ${mode.architectureContract}');
    b.writeln('Policy: ${mode.codePolicyContract}');
    b.writeln();
    b.writeln('## §01 Concept & 30s Core Loop');
    b.writeln('- Vision: ${_s(rootSpec.pitch, mode)}');
    if (rootSpec.coreLoop.isNotEmpty) {
      final cleanLoop = [
        for (final step in rootSpec.coreLoop)
          if (_s(step, mode).isNotEmpty) _s(step, mode),
      ];
      if (cleanLoop.isNotEmpty) {
        b.writeln('- Loop: ${cleanLoop.join(' -> ')}');
      }
    }
    if (rootSpec.releaseDoneWhen.trim().isNotEmpty) {
      b.writeln('- Release Gate: ${_s(rootSpec.releaseDoneWhen, mode)}');
    }
    b.writeln();
    b.writeln('## §02 Global Unreal Engine 5 Contracts (${mode.pillLabel})');
    b.writeln('- Camera Rig: ${_s(rootSpec.cameraContract, mode)}');
    b.writeln('- Character Scale: ${_s(rootSpec.characterScale, mode)}');
    b.writeln('- Input Contract: ${_s(rootSpec.inputContract, mode)}');
    b.writeln('- Asset Policy: ${_s(rootSpec.assetPolicy, mode)}');
    b.writeln();
    b.writeln('## §03 Pillars & Conflict Trade-Offs');
    b.writeln('- Core Feel: ${rootSpec.selectedCoreFeelOption.label}');
    for (final pillar in rootSpec.pillars) {
      final clean = _s(pillar, mode);
      if (clean.isNotEmpty) b.writeln('- Pillar: $clean');
    }
    for (final tradeOff in rootSpec.tradeOffs) {
      final cleanPref = _s(tradeOff.prefer, mode);
      final cleanAvoid = _s(tradeOff.avoid, mode);
      if (cleanPref.isNotEmpty || cleanAvoid.isNotEmpty) {
        b.writeln('- Trade-Off: $cleanPref OVER $cleanAvoid');
      }
    }
    if (rootSpec.outOfScope.isNotEmpty) {
      b.writeln();
      b.writeln('## §04 Hard Scope Cuts (Do Not Build)');
      for (final cut in rootSpec.outOfScope) {
        final cleanCut = UnrealSpecGuard.sanitizeExclusion(cut, mode: mode);
        if (cleanCut.isNotEmpty) b.writeln('- $cleanCut');
      }
    }
  }

  /// Builds root Unreal Engine 5 foundation context prepended to exports.
  static String buildRootUnrealContext(
    ProjectConceptBlueprint rootSpec, {
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
  }) {
    final b = StringBuffer();
    b.writeln('# ROOT_UNREAL_CONTEXT · ${rootSpec.normalizedTitle}');
    _writeRootSections(b, rootSpec, mode);
    return b.toString().trimRight();
  }

  static void _writeEpicOwnershipAndRules(
    StringBuffer b,
    EpicSpec epic,
    UnrealArchitectureMode mode,
  ) {
    if (epic.coreLoopBeat.trim().isNotEmpty) {
      b.writeln('Core Loop Beat: ${_s(epic.coreLoopBeat, mode)}');
    }
    b.writeln('Domain Goal: ${_s(epic.goal, mode)}');
    if (epic.inScope.isNotEmpty) {
      b.writeln('In Scope:');
      for (final item in epic.inScope) {
        final clean = _s(item, mode);
        if (clean.isNotEmpty) b.writeln('- $clean');
      }
    }
    if (epic.doneWhen.isNotEmpty) {
      b.writeln('Done When:');
      for (final item in epic.doneWhen) {
        final clean = _s(item, mode);
        if (clean.isNotEmpty) b.writeln('- $clean');
      }
    }

    b.writeln();
    b.writeln('Shared Blueprint, Level & Class Ownership:');
    if (epic.sceneOwnership.isNotEmpty) {
      for (final own in epic.sceneOwnership) {
        final path = _s(own.path, mode);
        final role = _s(own.role, mode);
        if (path.isEmpty) continue;
        final suffix = role.isEmpty ? '' : ' — $role';
        b.writeln('- $path$suffix');
      }
    } else if (epic.links.isNotEmpty || epic.levelStaging.trim().isNotEmpty) {
      for (final link in epic.links) {
        final clean = _s(link, mode);
        if (clean.isNotEmpty) b.writeln('- $clean');
      }
      if (epic.levelStaging.trim().isNotEmpty) {
        b.writeln('- Test Level: ${_s(epic.levelStaging, mode)}');
      }
    } else {
      b.writeln('- Pending Blueprint/Level assignment');
    }

    b.writeln();
    b.writeln('Shared State & Interrupt Rules:');
    if (epic.stateFlow.isEmpty && epic.interruptRules.isEmpty) {
      b.writeln('- Event-driven domain with decoupled Feature slices');
    } else {
      if (epic.stateFlow.isNotEmpty) {
        final states = [
          for (final st in epic.stateFlow)
            if (_s(st, mode).isNotEmpty) _s(st, mode),
        ];
        if (states.isNotEmpty) b.writeln('- States: ${states.join(' -> ')}');
      }
      for (final rule in epic.interruptRules) {
        final clean = _s(rule, mode);
        if (clean.isNotEmpty) b.writeln('- Rule: $clean');
      }
    }

    if (epic.outOfScope.isNotEmpty) {
      b.writeln();
      b.writeln('Domain Out-of-Scope Cuts:');
      for (final cut in epic.outOfScope) {
        final clean = UnrealSpecGuard.sanitizeExclusion(cut, mode: mode);
        if (clean.isNotEmpty) b.writeln('- $clean');
      }
    }
  }

  static String _featureStatusTag(
    FeatureSpec feat,
    String releaseVersion,
  ) {
    if (releaseVersion != 'v0.1' && feat.introducedIn == releaseVersion) {
      return '+$releaseVersion NEW';
    }
    if (releaseVersion != 'v0.1' && feat.releaseDelta.trim().isNotEmpty) {
      return '+$releaseVersion DELTA';
    }
    if (feat.isLockedBaselineInRelease(releaseVersion)) {
      final baseVer = feat.introducedIn.trim().isEmpty
          ? 'v0.1'
          : feat.introducedIn.trim();
      return '$baseVer ✓ BASELINE';
    }
    if (feat.isPassed) return 'PASSED ✓';
    if (feat.openFixesCount > 0) return '${feat.openFixesCount} FIX';
    if (feat.status == FeatureStatus.active) return 'ACTIVE';
    return 'QUEUED';
  }

  /// Builds the heading-indexed `*_copilot_gdd.md` document for Ultimate Engine CoPilot's GDD slot.
  static String buildCoPilotGddMarkdown({
    required ProjectConceptBlueprint rootSpec,
    required Map<String, List<EpicSpec>> epicsByReleaseLabel,
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
  }) {
    final b = StringBuffer();
    b.writeln('# PROJECT GDD · ${rootSpec.normalizedTitle} (${mode.pillLabel})');
    b.writeln('Arch: ${mode.architectureContract}');
    b.writeln();
    b.writeln('## §01 Concept & 30s Loop');
    b.writeln('- Vision: ${UnrealPromptCompactor.compactProse(_s(rootSpec.pitch, mode))}');
    if (rootSpec.coreLoop.isNotEmpty) {
      final cleanLoop = [
        for (final step in rootSpec.coreLoop)
          if (_s(step, mode).isNotEmpty)
            UnrealPromptCompactor.compactProse(_s(step, mode)),
      ];
      if (cleanLoop.isNotEmpty) {
        b.writeln('- Loop: ${cleanLoop.join(' -> ')}');
      }
    }
    if (rootSpec.releaseDoneWhen.trim().isNotEmpty) {
      b.writeln(
        '- PIE Gate: ${UnrealPromptCompactor.compactProse(_s(rootSpec.releaseDoneWhen, mode))}',
      );
    }
    b.writeln();
    b.writeln('## §02 Global UE5 Contracts (${mode.pillLabel})');
    b.writeln('- Cam: ${UnrealPromptCompactor.compactProse(_s(rootSpec.cameraContract, mode))}');
    b.writeln('- Scale: ${UnrealPromptCompactor.compactProse(_s(rootSpec.characterScale, mode))}');
    b.writeln('- Input: ${_s(rootSpec.inputContract, mode)}');
    b.writeln('- Assets: ${UnrealPromptCompactor.compactProse(_s(rootSpec.assetPolicy, mode))}');
    b.writeln();
    b.writeln('## §03 Pillars & Trade-Offs');
    b.writeln('- Feel: ${rootSpec.selectedCoreFeelOption.label}');
    for (final pillar in rootSpec.pillars) {
      final clean = UnrealPromptCompactor.compactProse(_s(pillar, mode));
      if (clean.isNotEmpty) b.writeln('- Pillar: $clean');
    }
    for (final tradeOff in rootSpec.tradeOffs) {
      final cleanPref = UnrealPromptCompactor.compactProse(_s(tradeOff.prefer, mode));
      final cleanAvoid = UnrealPromptCompactor.compactProse(_s(tradeOff.avoid, mode));
      if (cleanPref.isNotEmpty || cleanAvoid.isNotEmpty) {
        b.writeln('- Rule: $cleanPref OVER $cleanAvoid');
      }
    }
    final compactRootCuts =
        UnrealPromptCompactor.compactCuts(rootSpec.outOfScope, mode: mode);
    if (compactRootCuts.isNotEmpty) {
      b.writeln();
      b.writeln('## §04 Hard Scope Cuts');
      b.writeln('- $compactRootCuts');
    }

    b.writeln();
    b.writeln('## §05 Release Architecture & Epic Domain Ownership');
    final effectiveReleases = epicsByReleaseLabel.isNotEmpty
        ? epicsByReleaseLabel
        : (rootSpec.initialEpics.isNotEmpty
            ? <String, List<EpicSpec>>{
                'v0.1 · Prototype': rootSpec.initialEpics,
              }
            : const <String, List<EpicSpec>>{});
    final sortedReleases = _sortedReleaseEntries(effectiveReleases);
    final releaseOrder = <String>[
      for (final entry in sortedReleases) _extractReleaseVersion(entry.key),
    ];

    if (sortedReleases.isEmpty) {
      b.writeln('- No Epics planned.');
    } else {
      for (final entry in sortedReleases) {
        final relVer = _extractReleaseVersion(entry.key);
        b.writeln();
        b.writeln('### ${entry.key}');
        for (final rawEpic in entry.value) {
          final epic = UnrealSpecGuard.sanitizeEpicSpec(rawEpic, mode: mode);
          b.writeln(
            '- **${epic.code} · ${epic.title}**: ${UnrealPromptCompactor.compactProse(epic.goal)}',
          );
          if (epic.sceneOwnership.isNotEmpty) {
            final owners = [
              for (final o in epic.sceneOwnership)
                o.role.isEmpty
                    ? o.path
                    : '${o.path} (${UnrealPromptCompactor.compactProse(o.role)})',
            ];
            b.writeln('  - Owners: ${owners.join(', ')}');
          }
          for (final feat in epic.featuresForRelease(relVer, releaseOrder)) {
            final tag = _featureStatusTag(feat, relVer);
            final deltaNote = relVer != 'v0.1' && feat.releaseDelta.trim().isNotEmpty
                ? ' (Delta: ${feat.releaseDelta.trim()})'
                : '';
            b.writeln(
              '  - ${feat.code} · ${feat.title} [$tag] — ${UnrealPromptCompactor.compactProse(feat.goal)}$deltaNote',
            );
          }
        }
      }
    }
    return b.toString().trimRight();
  }

  /// Builds the 1-click Feature / `[FIX]` / `v0.2+` Delta prompt for Ultimate Engine CoPilot.
  /// Defaults to compact `@TAG` telegraphic DSL (`compact: true`); pass `compact: false` for readable Markdown.
  static String buildCoPilotFeaturePrompt({
    required ProjectConceptBlueprint rootSpec,
    required EpicSpec epic,
    required FeatureSpec feature,
    String releaseVersion = 'v0.1',
    List<String> releaseOrder = const ['v0.1', 'v0.2'],
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
    bool compact = true,
  }) {
    if (compact) {
      return UnrealPromptCompactor.buildCompactFeaturePrompt(
        rootSpec: rootSpec,
        epic: epic,
        feature: feature,
        releaseVersion: releaseVersion,
        releaseOrder: releaseOrder,
        mode: mode,
      );
    }
    final cleanEpic = UnrealSpecGuard.sanitizeEpicSpec(epic, mode: mode);
    final cleanFeat = UnrealSpecGuard.sanitizeFeatureSpec(feature, mode: mode);
    final ver = releaseVersion.trim().isNotEmpty
        ? releaseVersion.trim()
        : (cleanFeat.introducedIn.trim().isNotEmpty
            ? cleanFeat.introducedIn.trim()
            : cleanEpic.releaseVersion);
    final effOrder =
        releaseOrder.isEmpty ? const ['v0.1', 'v0.2'] : releaseOrder;
    final openFixes = cleanFeat.openFixes;
    final isUpgradeDelta =
        ver != 'v0.1' && cleanFeat.releaseDelta.trim().isNotEmpty;
    final isLockedBaseline = openFixes.isEmpty &&
        !isUpgradeDelta &&
        ver != 'v0.1' &&
        cleanFeat.isLockedBaselineInRelease(ver);
    final effChecks = cleanFeat.effectiveChecksForRelease(ver);
    final visibleSiblings = cleanEpic.featuresForRelease(ver, effOrder);
    final anySiblingPassed = visibleSiblings.any(
      (s) => s.id != cleanFeat.id && s.isPassedForRelease(ver),
    );
    final isFirstSliceOwnerScaffold = openFixes.isEmpty &&
        !isUpgradeDelta &&
        !isLockedBaseline &&
        !anySiblingPassed;

    final b = StringBuffer();
    if (openFixes.isNotEmpty) {
      b.writeln(
        '# ULTIMATE ENGINE COPILOT — FOCUSED [FIX] PASS · ${cleanFeat.code} · ${cleanFeat.title}',
      );
    } else if (isLockedBaseline) {
      b.writeln(
        '# ULTIMATE ENGINE COPILOT — LOCKED BASELINE REFERENCE · ${cleanFeat.code} · ${cleanFeat.title} (Shipped in ${cleanFeat.introducedIn}, Viewing $ver)',
      );
    } else if (isUpgradeDelta) {
      b.writeln(
        '# ULTIMATE ENGINE COPILOT — UPGRADE FEATURE DELTA · ${cleanFeat.code} · ${cleanFeat.title} ($ver)',
      );
    } else {
      b.writeln(
        '# ULTIMATE ENGINE COPILOT — BUILD FEATURE · ${cleanFeat.code} · ${cleanFeat.title} ($ver)',
      );
    }
    b.writeln(
      'Project: ${rootSpec.normalizedTitle} | Mode: ${mode.fullLabel} | Release: $ver | Owning Epic: ${cleanEpic.code} (${cleanEpic.title})',
    );
    b.writeln();
    b.writeln('## 1. Parent Epic Architecture Guardrails (Read-Only)');
    _writeEpicOwnershipAndRules(b, cleanEpic, mode);
    if (isFirstSliceOwnerScaffold) {
      b.writeln();
      b.writeln(
        'First-Slice Owner Rule: If the shared Epic owner assets above do not exist yet, create them now so subsequent Features reuse the same assets.',
      );
    }

    if (visibleSiblings.isNotEmpty) {
      b.writeln();
      b.writeln('## Sibling Feature Slices in ${cleanEpic.code}');
      for (final sib in visibleSiblings) {
        final isActive = (cleanFeat.id.isNotEmpty && sib.id == cleanFeat.id) ||
            (cleanFeat.id.isEmpty && sib.code == cleanFeat.code);
        if (isActive) {
          b.writeln('- [ACTIVE TARGET ->] ${sib.code} · ${sib.title} — ${sib.goal}');
        } else if (sib.isPassedForRelease(ver)) {
          b.writeln('- [PASSED — DO NOT REGRESS] ${sib.code} · ${sib.title}');
        } else {
          b.writeln('- [QUEUED — DO NOT BUILD YET] ${sib.code} · ${sib.title}');
        }
      }
    }

    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln(
      '## 2. Active Target Slice · ${cleanFeat.code} · ${cleanFeat.title} ($ver · ${cleanFeat.sliceTime})',
    );

    if (isUpgradeDelta) {
      final cleanDelta =
          cleanFeat.releaseDelta.trim().replaceFirst(RegExp(r'^\+\s*'), '');
      b.writeln();
      b.writeln('## $ver Upgrade Delta (Add atop existing baseline)');
      b.writeln('- +$cleanDelta');
    }

    b.writeln();
    b.writeln('## §01 Feature Scope');
    b.writeln('- Goal: ${cleanFeat.goal}');
    if (cleanFeat.inScope.isNotEmpty) {
      b.writeln('- In Scope:');
      for (final s in cleanFeat.inScope) {
        b.writeln('  - $s');
      }
    }
    if (cleanFeat.doneWhen.isNotEmpty) {
      b.writeln('- Done When:');
      for (final d in cleanFeat.doneWhen) {
        b.writeln('  - $d');
      }
    }

    b.writeln();
    b.writeln('## §02 Enhanced Input (${mode.inputContractLabel})');
    if (cleanFeat.controls.isEmpty) {
      b.writeln('- None (system or overlap driven)');
    } else {
      b.writeln('| InputAction | Trigger | Gameplay Rule |');
      b.writeln('| --- | --- | --- |');
      for (final c in cleanFeat.controls) {
        b.writeln('| ${c.action} | ${c.trigger} | ${c.rule} |');
      }
    }

    b.writeln();
    b.writeln('## §03 Exposed Tuning (${mode.tuningColumnLabel})');
    if (cleanFeat.tuning.isEmpty) {
      b.writeln('- None');
    } else {
      for (final t in cleanFeat.tuning) {
        final unitSuffix = t.unit.trim().isEmpty ? '' : ' ${t.unit.trim()}';
        final propType =
            UnrealSpecGuard.inferUnrealPropertyType(t.value, t.unit);
        final qualifier = mode == UnrealArchitectureMode.cppHybrid
            ? 'UPROPERTY(EditAnywhere, BlueprintReadWrite)'
            : 'Exposed Blueprint Var';
        b.writeln('- $qualifier `$propType ${t.key} = ${t.value}$unitSuffix`');
      }
    }

    b.writeln();
    b.writeln('## §04 Viewport, UMG & Audio Cues');
    if (cleanFeat.cues.isEmpty) {
      b.writeln('- Minimal greybox debug shapes and Output Log cues');
    } else {
      for (final cue in cleanFeat.cues) {
        b.writeln('- $cue');
      }
    }

    b.writeln();
    b.writeln('## §05 PIE Playtest Gate');
    if (effChecks.isEmpty) {
      b.writeln('- [ ] Confirm observable player response in PIE (Alt+P)');
    } else {
      for (final chk in effChecks) {
        b.writeln('- [${chk.passed ? 'x' : ' '}] ${chk.text}');
      }
    }

    if (openFixes.isNotEmpty) {
      b.writeln();
      b.writeln('## Open [FIX] Revisions to Resolve Now');
      for (final fx in openFixes) {
        b.writeln('- [FIX] ${fx.text}');
      }
      b.writeln();
      b.writeln('### CoPilot Execution Instruction');
      b.writeln(
        'Apply targeted edits only to resolve every [FIX] above while keeping all already-passing Feature behavior and [PASSED — DO NOT REGRESS] slices intact. Run PIE and confirm the §05 checks.',
      );
    } else if (isLockedBaseline) {
      b.writeln();
      b.writeln('### CoPilot Execution Instruction');
      b.writeln(
        'Read-only baseline reference (${cleanFeat.introducedIn} ✓): Do not rebuild ${cleanFeat.code} in $ver unless resolving a regression; keep all §02–§05 contracts intact.',
      );
    } else if (isUpgradeDelta) {
      b.writeln();
      b.writeln('### CoPilot Execution Instruction');
      b.writeln(
        'Apply ONLY the $ver Upgrade Delta above to ${cleanFeat.code} inside ${cleanEpic.code} (${mode.fullLabel}) without regressing its locked baseline behavior or [PASSED — DO NOT REGRESS] sibling slices, then check every §05 PIE Playtest Gate item.',
      );
    } else {
      b.writeln();
      b.writeln('### CoPilot Execution Instruction');
      b.writeln(
        'Implement ONLY ${cleanFeat.code} inside ${cleanEpic.code} using ${mode.fullLabel} conventions, wire §02 Enhanced Input actions, expose every §03 variable, and check all §05 PIE Playtest Gate criteria.',
      );
    }

    return b.toString().trimRight();
  }

  /// Builds a domain-level architecture brief for an [EpicSpec] in a given [releaseVersion].
  /// Defaults to compact `@TAG` DSL (`compact: true`); pass `compact: false` for readable Markdown.
  static String buildEpicArchitectureContext({
    required ProjectConceptBlueprint rootSpec,
    required EpicSpec epic,
    String? releaseVersion,
    List<String> releaseOrder = const ['v0.1', 'v0.2'],
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
    bool includeRootContext = true,
    bool compact = true,
  }) {
    if (compact) {
      return UnrealPromptCompactor.buildCompactEpicBrief(
        rootSpec: rootSpec,
        epic: epic,
        releaseVersion: releaseVersion,
        releaseOrder: releaseOrder,
        mode: mode,
        includeRootContext: includeRootContext,
      );
    }
    final cleanEpic = UnrealSpecGuard.sanitizeEpicSpec(epic, mode: mode);
    final ver = (releaseVersion != null && releaseVersion.trim().isNotEmpty)
        ? releaseVersion.trim()
        : cleanEpic.releaseVersion;
    final visibleFeatures = cleanEpic.featuresForRelease(ver, releaseOrder);
    final passedCount = cleanEpic.passedFeaturesCountForRelease(ver, releaseOrder);
    final openFixesCount =
        cleanEpic.totalOpenFeatureFixes(ver, releaseOrder) +
            cleanEpic.openFixesCount;
    final b = StringBuffer();

    if (includeRootContext) {
      b.writeln(buildRootUnrealContext(rootSpec, mode: mode));
      b.writeln();
      b.writeln('---');
      b.writeln();
    }

    b.writeln(
      '# UE5 EPIC ARCHITECTURE BRIEF · ${cleanEpic.code} · ${cleanEpic.title} ($ver)',
    );
    b.writeln('Mode: ${mode.pillLabel} (${mode.shortLabel})');
    b.writeln(
      'Progress: $passedCount/${visibleFeatures.length} Features Passed | $openFixesCount Open [FIX]',
    );
    b.writeln();
    b.writeln('## §01 Domain Architecture');
    _writeEpicOwnershipAndRules(b, cleanEpic, mode);

    if (cleanEpic.baselineSummary.isNotEmpty &&
        (ver != 'v0.1' || cleanEpic.upgradeDeltas.isNotEmpty)) {
      b.writeln();
      b.writeln('Locked Baseline: ${cleanEpic.baselineSummary.join(' · ')}');
    }
    if (ver != 'v0.1' && cleanEpic.upgradeDeltas.isNotEmpty) {
      b.writeln();
      b.writeln('Upgrade Deltas ($ver):');
      for (final delta in cleanEpic.upgradeDeltas) {
        final cleanDelta = delta.trim().replaceFirst(RegExp(r'^\+\s*'), '');
        if (cleanDelta.isNotEmpty) b.writeln('- +$cleanDelta');
      }
    }

    b.writeln();
    b.writeln('## §02 Feature Slices Owned by ${cleanEpic.code} ($ver)');
    if (visibleFeatures.isEmpty) {
      b.writeln('- No Feature slices queued in $ver');
    } else {
      for (final feat in visibleFeatures) {
        final effChecks = feat.effectiveChecksForRelease(ver);
        final doneChecks = effChecks.where((c) => c.passed).length;
        final tag = _featureStatusTag(feat, ver);
        b.writeln(
          '- ${feat.code} · ${feat.title} [$tag] ($doneChecks/${effChecks.length} checks | ${feat.sliceTime}) — ${feat.goal}',
        );
      }
    }

    return b.toString().trimRight();
  }

  static void _writeReleaseEpicsAndFeatures({
    required StringBuffer buffer,
    required ProjectConceptBlueprint rootSpec,
    required String relVer,
    required List<EpicSpec> epics,
    required List<String> releaseOrder,
    required UnrealArchitectureMode mode,
  }) {
    final effectiveOrder =
        releaseOrder.isEmpty ? const ['v0.1', 'v0.2'] : releaseOrder;
    for (final epic in epics) {
      buffer.writeln();
      buffer.writeln(
        buildEpicArchitectureContext(
          rootSpec: rootSpec,
          epic: epic,
          releaseVersion: relVer,
          releaseOrder: effectiveOrder,
          mode: mode,
          includeRootContext: false,
          compact: false,
        ),
      );
      for (final feat in epic.featuresForRelease(relVer, effectiveOrder)) {
        buffer.writeln();
        buffer.writeln(
          buildCoPilotFeaturePrompt(
            rootSpec: rootSpec,
            epic: epic,
            feature: feat,
            releaseVersion: relVer,
            releaseOrder: effectiveOrder,
            mode: mode,
            compact: false,
          ),
        );
      }
    }
  }

  /// Builds the full project Markdown export (`PROJECT_SPEC.md` across all releases, Epics & Features).
  static String buildFullProjectSpecMarkdown({
    required ProjectConceptBlueprint rootSpec,
    required Map<String, List<EpicSpec>> epicsByReleaseLabel,
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
  }) {
    final b = StringBuffer();
    b.writeln(buildRootUnrealContext(rootSpec, mode: mode));
    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln('# Release Roadmap & Unreal Engine 5 Domain Specs');
    final effectiveReleases = epicsByReleaseLabel.isNotEmpty
        ? epicsByReleaseLabel
        : (rootSpec.initialEpics.isNotEmpty
            ? <String, List<EpicSpec>>{
                'v0.1 · Prototype': rootSpec.initialEpics,
              }
            : const <String, List<EpicSpec>>{});
    final sortedReleases = _sortedReleaseEntries(effectiveReleases);
    final releaseOrder = <String>[
      for (final entry in sortedReleases) _extractReleaseVersion(entry.key),
    ];
    for (final entry in sortedReleases) {
      final relVer = _extractReleaseVersion(entry.key);
      b.writeln();
      b.writeln('## Release ${entry.key}');
      _writeReleaseEpicsAndFeatures(
        buffer: b,
        rootSpec: rootSpec,
        relVer: relVer,
        epics: entry.value,
        releaseOrder: releaseOrder,
        mode: mode,
      );
    }
    return b.toString().trimRight();
  }

  /// Builds a Release bundle (`ROOT_UNREAL_CONTEXT` + all Epics and Features in one release).
  static String buildReleaseContextBundle({
    required ProjectConceptBlueprint rootSpec,
    required String releaseLabel,
    required List<EpicSpec> releaseEpics,
    List<String> releaseOrder = const ['v0.1', 'v0.2'],
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
  }) {
    final relVer = _extractReleaseVersion(releaseLabel);
    final b = StringBuffer();
    b.writeln(buildRootUnrealContext(rootSpec, mode: mode));
    b.writeln();
    b.writeln('---');
    b.writeln();
    b.writeln('# RELEASE BUNDLE · $releaseLabel');
    _writeReleaseEpicsAndFeatures(
      buffer: b,
      rootSpec: rootSpec,
      relVer: relVer,
      epics: releaseEpics,
      releaseOrder: releaseOrder,
      mode: mode,
    );
    return b.toString().trimRight();
  }
}
