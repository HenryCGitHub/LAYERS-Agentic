import '../models/agent_blueprints.dart';
import '../models/epic_spec.dart';
import 'unreal_spec_guard.dart';

/// Deterministic token-efficient compiler that translates `ProjectConceptBlueprint`,
/// `EpicSpec`, and `FeatureSpec` into telegraphic `@TAG` prompts for Ultimate Engine CoPilot
/// while leaving all UE5 identifiers, asset paths, and `cm`/`cm/s` numbers intact.
class UnrealPromptCompactor {
  const UnrealPromptCompactor._();

  static final RegExp _leadingFillerPattern = RegExp(
    r'\b(?:please make sure to|make sure that|make sure to|in order to|when the player|the player can|should be able to|be able to|should be|that will|which will)\b\s*',
    caseSensitive: false,
  );
  static final RegExp _leadingArticlePattern = RegExp(
    r'^(?:The|An|A)\s+(?=[a-z])',
  );
  static final RegExp _inlineLowerArticlePattern = RegExp(
    r'(?:(?<=^)|(?<=\s))(?:the|an|a)\s+(?=[A-Za-z/])',
  );

  /// Strips filler phrases and standalone articles while preserving UE5 classes, paths, and numbers.
  static String compactProse(String raw) {
    var out = raw.trim();
    if (out.isEmpty) return '';
    out = out.replaceAll(_leadingFillerPattern, '');
    out = out.replaceAll(_leadingArticlePattern, '');
    out = out.replaceAll(_inlineLowerArticlePattern, '');
    out = out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return out;
  }

  /// Compacts `"No ..."` exclusion rules into symbolic `!CutA | !CutB` tokens.
  static String compactCuts(
    List<String> cuts, {
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
  }) {
    final items = <String>[];
    for (final rawCut in cuts) {
      var clean = UnrealSpecGuard.sanitizeExclusion(rawCut, mode: mode).trim();
      if (clean.isEmpty) continue;
      clean = clean.replaceFirst(RegExp(r'^No\s+', caseSensitive: false), '').trim();
      clean = compactProse(clean);
      if (clean.isEmpty) continue;
      items.add(clean.startsWith('!') ? clean : '!$clean');
    }
    return items.join(' | ');
  }

  /// Fast character-based LLM token estimate (~4 chars per token).
  static int estimateTokens(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return (trimmed.length / 4.0).ceil();
  }

  /// Compares estimated tokens between compact DSL and readable Markdown.
  static ({int compactTokens, int readableTokens, int savedPercent})
      compareSavings(String compactText, String readableText) {
    final cTok = estimateTokens(compactText);
    final rTok = estimateTokens(readableText);
    if (rTok <= 0) {
      return (compactTokens: cTok, readableTokens: rTok, savedPercent: 0);
    }
    final pct = (((rTok - cTok) * 100.0) / rTok).round().clamp(0, 99);
    return (compactTokens: cTok, readableTokens: rTok, savedPercent: pct);
  }

  static String _s(String raw, UnrealArchitectureMode mode) =>
      UnrealSpecGuard.sanitizeLine(raw, mode: mode);

  static String _ownersLine(EpicSpec cleanEpic, UnrealArchitectureMode mode) {
    if (cleanEpic.sceneOwnership.isNotEmpty) {
      final parts = <String>[];
      for (final own in cleanEpic.sceneOwnership) {
        final path = _s(own.path, mode);
        final role = compactProse(_s(own.role, mode));
        if (path.isEmpty) continue;
        parts.add(role.isEmpty ? path : '$path ($role)');
      }
      if (parts.isNotEmpty) return parts.join(' | ');
    }
    final fallbackParts = <String>[
      for (final link in cleanEpic.links)
        if (_s(link, mode).isNotEmpty) compactProse(_s(link, mode)),
      if (cleanEpic.levelStaging.trim().isNotEmpty)
        'Level: ${_s(cleanEpic.levelStaging, mode)}',
    ];
    return fallbackParts.isNotEmpty
        ? fallbackParts.join(' | ')
        : 'Pending asset assignment';
  }

  static String _statesSegment(EpicSpec cleanEpic, UnrealArchitectureMode mode) {
    final states = [
      for (final st in cleanEpic.stateFlow)
        if (_s(st, mode).isNotEmpty) _s(st, mode),
    ];
    final rules = [
      for (final rule in cleanEpic.interruptRules)
        if (_s(rule, mode).isNotEmpty) compactProse(_s(rule, mode)),
    ];
    if (states.isEmpty && rules.isEmpty) return '';
    final segments = <String>[
      if (states.isNotEmpty) states.join(' -> '),
      if (rules.isNotEmpty) 'RULES=${rules.join(' ; ')}',
    ];
    return '@STATES: ${segments.join(' | ')}';
  }

  static String _statusTag(FeatureSpec feat, String releaseVersion) {
    if (releaseVersion != 'v0.1' && feat.introducedIn == releaseVersion) {
      return '+$releaseVersion NEW';
    }
    if (releaseVersion != 'v0.1' && feat.releaseDelta.trim().isNotEmpty) {
      return '+$releaseVersion DELTA';
    }
    if (feat.isLockedBaselineInRelease(releaseVersion)) {
      final base = feat.introducedIn.trim().isEmpty
          ? 'v0.1'
          : feat.introducedIn.trim();
      return '$base ✓ BASELINE';
    }
    if (feat.isPassed) return 'PASS ✓';
    if (feat.openFixesCount > 0) return '${feat.openFixesCount} FIX';
    if (feat.status == FeatureStatus.active) return 'ACTIVE';
    return 'QUEUED';
  }

  /// Compiles a compact, token-efficient `@TAG` Feature/`[FIX]`/`Delta` prompt for CoPilot chat.
  static String buildCompactFeaturePrompt({
    required ProjectConceptBlueprint rootSpec,
    required EpicSpec epic,
    required FeatureSpec feature,
    String releaseVersion = 'v0.1',
    List<String> releaseOrder = const ['v0.1', 'v0.2'],
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
  }) {
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

    final task = openFixes.isNotEmpty
        ? 'FIX'
        : (isLockedBaseline
            ? 'LOCKED_BASELINE'
            : (isUpgradeDelta ? 'DELTA' : 'BUILD'));

    final b = StringBuffer();
    final baseSuffix =
        isLockedBaseline ? ' BASE=${cleanFeat.introducedIn}' : '';
    b.writeln(
      '[UE5_COPILOT TASK=$task TARGET=${cleanFeat.code} · ${cleanFeat.title} REL=$ver$baseSuffix MODE=${mode.pillLabel}]',
    );

    final projCuts = compactCuts(rootSpec.outOfScope.take(4).toList(), mode: mode);
    b.writeln(
      '@PROJECT ${rootSpec.normalizedTitle} | CAM=${compactProse(_s(rootSpec.cameraContract, mode))} | INPUT=${_s(rootSpec.inputContract, mode)}'
      '${projCuts.isEmpty ? '' : ' | CUTS=$projCuts'}',
    );
    b.writeln(
      '@EPIC ${cleanEpic.code}(${cleanEpic.title}): ${compactProse(_s(cleanEpic.goal, mode))}',
    );
    b.writeln('@OWNERS: ${_ownersLine(cleanEpic, mode)}');
    if (isFirstSliceOwnerScaffold) {
      b.writeln(
        '@FIRST_FEATURE: Create missing @OWNERS now so sibling features reuse them.',
      );
    }

    final statesLine = _statesSegment(cleanEpic, mode);
    if (statesLine.isNotEmpty) b.writeln(statesLine);

    if (visibleSiblings.isNotEmpty) {
      final keepCodes = <String>[];
      final queuedCodes = <String>[];
      for (final sib in visibleSiblings) {
        final isActive = (cleanFeat.id.isNotEmpty && sib.id == cleanFeat.id) ||
            (cleanFeat.id.isEmpty && sib.code == cleanFeat.code);
        if (isActive) continue;
        if (sib.isPassedForRelease(ver)) {
          keepCodes.add(sib.code);
        } else {
          queuedCodes.add(sib.code);
        }
      }
      final sibParts = <String>[
        if (keepCodes.isNotEmpty) 'KEEP=[${keepCodes.join(',')}]',
        'TARGET=[${cleanFeat.code}]',
        if (queuedCodes.isNotEmpty) 'DO_NOT_BUILD=[${queuedCodes.join(',')}]',
      ];
      b.writeln('@SIBLINGS: ${sibParts.join(' | ')}');
    }

    final epicCuts = compactCuts(cleanEpic.outOfScope, mode: mode);
    if (epicCuts.isNotEmpty) {
      b.writeln('@CUTS: $epicCuts');
    }

    if (isUpgradeDelta) {
      final cleanDelta =
          cleanFeat.releaseDelta.trim().replaceFirst(RegExp(r'^\+\s*'), '');
      b.writeln('@DELTA $ver: +${compactProse(cleanDelta)}');
    }

    b.writeln(
      '@FEATURE ${cleanFeat.code}(${cleanFeat.sliceTime}): ${compactProse(cleanFeat.goal)}',
    );
    if (cleanFeat.inScope.isNotEmpty) {
      final scopeItems = [
        for (final item in cleanFeat.inScope.take(4))
          if (compactProse(item).isNotEmpty) compactProse(item),
      ];
      if (scopeItems.isNotEmpty) {
        b.writeln('@IN_SCOPE: ${scopeItems.join(' | ')}');
      }
    }

    final inputsText = cleanFeat.controls.isEmpty
        ? 'None (overlap/event driven)'
        : [
            for (final c in cleanFeat.controls)
              '${c.action}(${c.trigger}) -> ${compactProse(c.rule)}',
          ].join(' | ');
    b.writeln('@INPUT [${mode.inputContractLabel}]: $inputsText');

    final qualifier = mode == UnrealArchitectureMode.cppHybrid
        ? 'UPROPERTY(EditAnywhere, BlueprintReadWrite)'
        : 'ExposedBP';
    if (cleanFeat.tuning.isEmpty) {
      b.writeln('@VARS [$qualifier]: None');
    } else {
      final varsText = [
        for (final t in cleanFeat.tuning)
          '${UnrealSpecGuard.inferUnrealPropertyType(t.value, t.unit)} ${t.key} = ${t.value}${t.unit.trim().isEmpty ? '' : ' ${t.unit.trim()}'}',
      ].join('; ');
      b.writeln('@VARS [$qualifier]: $varsText');
    }

    final cuesText = cleanFeat.cues.isEmpty
        ? 'Greybox debug shape + Output Log cue'
        : [
            for (final c in cleanFeat.cues)
              if (compactProse(c).isNotEmpty) compactProse(c),
          ].join(' | ');
    b.writeln('@CUES: $cuesText');

    if (openFixes.isNotEmpty) {
      final fixesText = [
        for (final fx in openFixes) '[FIX] ${compactProse(fx.text)}',
      ].join(' | ');
      b.writeln('@FIX_NOW: $fixesText');
    }

    if (effChecks.isEmpty) {
      b.writeln('@PIE_GATE: [ ] Confirm observable PIE (Alt+P) response');
    } else if (openFixes.isNotEmpty) {
      final passedCount = effChecks.where((c) => c.passed).length;
      final openChecks = effChecks.where((c) => !c.passed).toList();
      final gateParts = <String>[
        if (passedCount > 0) '$passedCount/${effChecks.length} PASS (keep)',
        for (final chk in openChecks) '[ ] ${compactProse(chk.text)}',
      ];
      b.writeln(
        '@PIE_GATE: ${gateParts.isEmpty ? '$passedCount/${effChecks.length} PASS (keep)' : gateParts.join(' | ')}',
      );
    } else {
      final checksText = [
        for (final chk in effChecks)
          '[${chk.passed ? 'x' : ' '}] ${compactProse(chk.text)}',
      ].join(' | ');
      b.writeln('@PIE_GATE: $checksText');
    }

    if (openFixes.isNotEmpty) {
      b.writeln(
        '@EXEC: Patch @OWNERS only to resolve @FIX_NOW; keep PASS checks & KEEP siblings intact; retest PIE.',
      );
    } else if (isLockedBaseline) {
      b.writeln(
        '@EXEC: Read-only ${cleanFeat.introducedIn} baseline reference. Do not rebuild ${cleanFeat.code} in $ver unless fixing regression; keep @INPUT/@VARS/@PIE_GATE intact.',
      );
    } else if (isUpgradeDelta) {
      b.writeln(
        '@EXEC: Apply ONLY @DELTA $ver to ${cleanFeat.code} in ${cleanEpic.code} (${mode.pillLabel}); create missing @OWNERS if absent, else extend existing; keep baseline & KEEP siblings intact; pass @PIE_GATE.',
      );
    } else {
      b.writeln(
        '@EXEC: Implement ONLY ${cleanFeat.code} in ${cleanEpic.code} (${mode.pillLabel}); create missing @OWNERS if absent, else extend existing; wire @INPUT & @VARS; pass @PIE_GATE.',
      );
    }

    return b.toString().trimRight();
  }

  /// Compiles a compact `@TAG` domain architecture brief for an [EpicSpec].
  static String buildCompactEpicBrief({
    required ProjectConceptBlueprint rootSpec,
    required EpicSpec epic,
    String? releaseVersion,
    List<String> releaseOrder = const ['v0.1', 'v0.2'],
    UnrealArchitectureMode mode = UnrealArchitectureMode.blueprint,
    bool includeRootContext = true,
  }) {
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
    b.writeln(
      '[UE5_COPILOT TASK=EPIC_BRIEF TARGET=${cleanEpic.code} · ${cleanEpic.title} REL=$ver MODE=${mode.pillLabel}]',
    );
    if (includeRootContext) {
      final projCuts =
          compactCuts(rootSpec.outOfScope.take(4).toList(), mode: mode);
      b.writeln(
        '@PROJECT ${rootSpec.normalizedTitle} | CAM=${compactProse(_s(rootSpec.cameraContract, mode))} | INPUT=${_s(rootSpec.inputContract, mode)}'
        '${projCuts.isEmpty ? '' : ' | CUTS=$projCuts'}',
      );
    }
    b.writeln(
      '@EPIC ${cleanEpic.code}(${cleanEpic.title}) [$passedCount/${visibleFeatures.length} PASS | $openFixesCount FIX]: ${compactProse(cleanEpic.goal)}',
    );
    b.writeln('@OWNERS: ${_ownersLine(cleanEpic, mode)}');

    final statesLine = _statesSegment(cleanEpic, mode);
    if (statesLine.isNotEmpty) b.writeln(statesLine);

    final epicCuts = compactCuts(cleanEpic.outOfScope, mode: mode);
    if (epicCuts.isNotEmpty) b.writeln('@CUTS: $epicCuts');

    if (cleanEpic.baselineSummary.isNotEmpty &&
        (ver != 'v0.1' || cleanEpic.upgradeDeltas.isNotEmpty)) {
      b.writeln('@BASELINE: ${cleanEpic.baselineSummary.join(' · ')}');
    }
    if (ver != 'v0.1' && cleanEpic.upgradeDeltas.isNotEmpty) {
      final deltas = [
        for (final d in cleanEpic.upgradeDeltas)
          if (d.trim().isNotEmpty)
            '+${compactProse(d.trim().replaceFirst(RegExp(r'^\+\s*'), ''))}',
      ];
      if (deltas.isNotEmpty) {
        b.writeln('@DELTAS $ver: ${deltas.join(' | ')}');
      }
    }

    if (visibleFeatures.isEmpty) {
      b.writeln('@FEATURES: None queued in $ver');
    } else {
      final slices = [
        for (final feat in visibleFeatures)
          '${feat.code} ${feat.title} [${_statusTag(feat, ver)}]',
      ];
      b.writeln('@FEATURES: ${slices.join(' | ')}');
    }
    return b.toString().trimRight();
  }
}
