import 'dart:convert';
import '../constants/tiers.dart';
import '../models/agent_blueprints.dart';
import '../models/feature_state.dart';
import '../models/tier_document.dart';
import '../utils/section_text_utils.dart';
import 'gemini_agent_client.dart';

/// Stage 2 Agent: Inspects the Project Concept (and any completed prior Releases)
/// and synthesizes a single-Release Blueprint (`ReleaseBlueprint`) using Gemini AI (`gemini-4-argon`).
/// Contains zero hardcoded archetypes and zero offline minimal scaffolds.
/// Returns `null` (or `false`) whenever the app is offline or Gemini AI is unreachable.
class ReleasePlannerAgent {
  static final RegExp _releaseVersionRegex =
      RegExp(r'(v\d+\.\d+(?:\.\d+)?)', caseSensitive: false);
  static final RegExp _mvpEpicNumRegex =
      RegExp(r'MVP Epic\s*(\d+)', caseSensitive: false);
  static final RegExp _noPrefixRegex = RegExp(r'^no\s+');
  static final RegExp _cutPrefixRegex = RegExp(r'^\[cut\]\s*');
  static final RegExp _durationRegex =
      RegExp(r'\(\s*\d+(?:\.\d+)?\s*[hm]\s*\)\s*$');
  static final RegExp _setupWordRegex =
      RegExp(r'\bsetup\b', caseSensitive: false);
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _nonAlphaNumRegex = RegExp(r'[^a-zA-Z0-9]');
  static final RegExp _nonAlphaNumSpaceRegex = RegExp(r'[^a-zA-Z0-9\s]');
  static final RegExp _tagPrefixRegex =
      RegExp(r'^\[TAG\]\s*', caseSensitive: false);
  static final RegExp _versionPrefixStripRegex =
      RegExp(r'^v\d+\.\d+\s*[:\-–—]?\s*', caseSensitive: false);

  static List<String> _parseStringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty && s != '...')
        .toList();
  }

  static String extractReleaseVersionTag(String releaseTitle) {
    final match = _releaseVersionRegex.firstMatch(releaseTitle);
    if (match != null) {
      return match.group(1)!.toLowerCase();
    }
    return 'v0.1';
  }

  /// Synthesizes a `ReleaseBlueprint` for `releaseDoc` via Gemini AI (`gemini-4-argon`).
  /// Returns `null` if offline or if Gemini AI cannot be reached.
  static Future<ReleaseBlueprint?> planRelease({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    List<TierDocument> completedReleases = const [],
    List<TierDocument> existingBeats = const [],
    Map<String, List<TierDocument>> existingFeaturesByBeat = const {},
    Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex = const {},
    String apiKey = '',
    String modelName = 'gemini-4-argon',
    String thinkingLevel = 'LOW',
  }) async {
    if (!GeminiAgentClient.hasKey(apiKey)) {
      return null;
    }

    final preset = releaseDoc.releaseScope;
    final versionTag = extractReleaseVersionTag(releaseDoc.title);
    final releasePhase = releaseDoc.sections['phase'] ?? '';
    final prototypePart = releaseDoc.sections['prototypePart'] ?? '';
    final isAgentReasoned = releaseDoc.sections['agentReasoned'] == 'true';
    final rawTargetEpicIdx = releaseDoc.sections['targetEpicIndex'];
    final mvpEpicMatch = _mvpEpicNumRegex.firstMatch(releaseDoc.title);
    final int? targetMvpEpicIndex = isAgentReasoned
        ? null
        : (rawTargetEpicIdx != null
            ? int.tryParse(rawTargetEpicIdx)
            : (mvpEpicMatch != null
                ? (int.tryParse(mvpEpicMatch.group(1)!) ?? 1) - 1
                : null));

    final isSubsequentRelease = existingBeats.isNotEmpty ||
        completedReleases.isNotEmpty ||
        versionTag != 'v0.1';
    final coreLoopItems = SectionTextUtils.resolveInScope(projectDoc.sections);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );
    final gameSpecText =
        projectDoc.sections['game_spec'] ?? projectDoc.sections['gameSpec'] ?? '';
    final techSpecText =
        projectDoc.sections['tech_spec'] ?? projectDoc.sections['techSpec'] ?? '';
    final pillarsText = projectDoc.sections['design_pillars'] ??
        projectDoc.sections['designPillars'] ??
        '';
    final tradeOffsText = projectDoc.sections['trade_offs'] ??
        projectDoc.sections['tradeOffs'] ??
        '';

    final String schemaPhaseHint =
        releasePhase.isNotEmpty ? releasePhase : 'mvp';
    final bool isPhaseLocked =
        releaseDoc.sections['phaseLockedByUser'] == 'true';

    final mvpVerTags = <String>{
      for (final r in completedReleases)
        if ((r.sections['phase'] ?? '') == ProductionPhase.mvp.name ||
            r.releaseScope == ReleaseScope.mvp)
          extractReleaseVersionTag(
            r.sections['versionTag']?.isNotEmpty == true
                ? r.sections['versionTag']!
                : r.title,
          ).toLowerCase(),
    };
    final vsVerTags = <String>{
      for (final r in completedReleases)
        if ((r.sections['phase'] ?? '') == ProductionPhase.verticalSlice.name ||
            r.releaseScope == ReleaseScope.verticalSlice)
          extractReleaseVersionTag(
            r.sections['versionTag']?.isNotEmpty == true
                ? r.sections['versionTag']!
                : r.title,
          ).toLowerCase(),
    };

    final uncoveredMvpBeats = <String>[];
    final unupgradedProtoFeatures = <String>[];
    final unpolishedVsBeats = <String>[];
    final unpolishedVsFeatures = <String>[];

    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final b = existingBeats[bIdx];
      final eTag = 'E${(bIdx + 1).toString().padLeft(2, '0')}';
      final feats = (existingFeaturesByBeat[b.id] ?? const <TierDocument>[])
          .where(
            (f) =>
                f.sections['lifecycle'] !=
                FeatureLifecycleStatus.superseded.name,
          )
          .toList();
      bool beatHasMvp = false;
      bool beatHasVs = false;
      for (final f in feats) {
        final originVer = (f.sections['originVersion'] ?? 'v0.1').toLowerCase();
        final states = FeatureStateNode.getStatesForDocument(f);
        final hasMvpCp = mvpVerTags.contains(originVer) ||
            states.any((s) => mvpVerTags.contains(s.releaseVersion.toLowerCase()));
        final hasVsCp = vsVerTags.contains(originVer) ||
            states.any((s) => vsVerTags.contains(s.releaseVersion.toLowerCase()));
        if (hasMvpCp) beatHasMvp = true;
        if (hasVsCp) {
          beatHasVs = true;
        } else {
          unpolishedVsFeatures.add('$eTag "${f.title}"');
        }
        if (originVer == 'v0.1') {
          final upgradedPostV01 = states.any(
            (s) => s.releaseVersion.toLowerCase() != 'v0.1',
          );
          if (!upgradedPostV01 && !hasMvpCp) {
            unupgradedProtoFeatures.add('$eTag "${f.title}"');
          }
        }
      }
      if (!beatHasMvp) {
        uncoveredMvpBeats.add('$eTag "${b.title}"');
      }
      if (!beatHasVs) {
        unpolishedVsBeats.add('$eTag "${b.title}"');
      }
    }

    final String phaseInstruction;
    if (prototypePart == '1' && !isSubsequentRelease) {
      phaseInstruction =
          '- PHASE 1 SPLIT PROTOTYPE (PART 1 OF 2 — CONTROLS & PRIMARY MECHANICS): Only plan the first ${(coreLoopItems.length / 2).ceil()} Core Loop Beats in `v0.1` so the developer can prove primary controls and core mechanics first (the remaining Beats are reserved for `v0.2` Prototype Part 2).';
    } else if (prototypePart == '2' ||
        (releasePhase == ProductionPhase.prototype.name &&
            isSubsequentRelease &&
            !isPhaseLocked)) {
      phaseInstruction =
          '- PHASE 1 SPLIT PROTOTYPE (PART 2 OF 2 — FULL CORE LOOP): Keep all existing `v0.1` Beats & Features `"lifecycle": "stable"` (0h, empty checkpoints) and add the remaining Stage 1 Core Loop Beats as `"lifecycle": "new"` so the complete greybox loop connects end-to-end.';
    } else if (isAgentReasoned ||
        (releasePhase == ProductionPhase.mvp.name &&
            targetMvpEpicIndex == null)) {
      final mvpCoverageHint = (uncoveredMvpBeats.isNotEmpty ||
              unupgradedProtoFeatures.isNotEmpty)
          ? '\n     * Still-Greybox v0.1 Epics needing MVP coverage: ${uncoveredMvpBeats.isNotEmpty ? uncoveredMvpBeats.join(', ') : 'All Epics touched once'}\n'
              '     * Still-Greybox v0.1 Features awaiting MVP upgrade: ${unupgradedProtoFeatures.isNotEmpty ? unupgradedProtoFeatures.join(', ') : 'None'}\n'
              '     * Prioritize upgrading the next cohesive batch of these still-greybox v0.1 Epics & Features (and adding any missing functional mechanics for them) rather than re-upgrading features that already received an MVP pass.'
          : '';
      final vsCoverageHint = (unpolishedVsBeats.isNotEmpty ||
              unpolishedVsFeatures.isNotEmpty)
          ? '\n     * Unpolished Epics needing Vertical Slice pass: ${unpolishedVsBeats.isNotEmpty ? unpolishedVsBeats.join(', ') : 'All Epics touched once'}\n'
              '     * Features awaiting Vertical Slice polish: ${unpolishedVsFeatures.take(8).join(', ')}\n'
              '     * Prioritize bringing the next cohesive batch of these unpolished Epics & Features up to Gold Standard polish rather than re-polishing already-polished features.'
          : '';
      final phaseTargetDirective = releasePhase ==
              ProductionPhase.postLaunch.name
          ? '  1. TARGET PHASE IS `"postLaunch"` (POST-LAUNCH & LIVE OPS — $versionTag): Set `"releasePhase": "postLaunch"` and a descriptive `"releaseTitle"` (`"$versionTag: <Live Ops / Content / Balance Focus>"`). Focus on shipping post-launch content expansions, live tuning balance passes, and playtest `[GUARD]` hardening without breaking `v1.0` save compatibility.'
          : (releasePhase == ProductionPhase.verticalSlice.name
              ? '  1. TARGET PHASE IS `"verticalSlice"` (MULTI-RELEASE VERTICAL SLICE POLISH TRACK): Set `"releasePhase": "verticalSlice"` and a descriptive `"releaseTitle"` (`"$versionTag: <Polish & Feel Focus>"`). Focus upgrades on visual/material polish, SFX/VFX & camera/hit-stop feel cues, HUD readability, and state/frame guards across unpolished Core Loop Beats.$vsCoverageHint'
              : (releasePhase == ProductionPhase.fullProduction.name
                  ? '  1. TARGET PHASE IS `"fullProduction"` (CONTENT & BACKLOG EXPANSION): Set `"releasePhase": "fullProduction"` and a descriptive `"releaseTitle"` (`"$versionTag: <Content & Expansion Focus>"`). Scale content/encounter variety and promote deferred backlog systems while honoring active exclusions.'
                  : '  1. TARGET PHASE IS `"mvp"` (MULTI-RELEASE MVP TRACK): Set `"releasePhase": "mvp"` and a specific, descriptive `"releaseTitle"` (`"$versionTag: <Concrete MVP Focus>"`). Bring the next cohesive group of greybox prototype mechanics up to functional MVP depth across the Core Loop and Design Pillars.$mvpCoverageHint'));
      phaseInstruction =
          '- AGENT-REASONED PROGRESSIVE RELEASE ($versionTag): You are the Lead Game Architect deciding what "${projectDoc.title}" needs next in $versionTag by evaluating the Existing Live Game Tree against the Stage 1 Design Pillars, Trade-Offs, Core Loop Beats, and Out-of-Scope Backlog:\n'
          '$phaseTargetDirective\n'
          '  2. Decide which existing Features need an `"upgrade"` vs. which remain `"stable"`, and what `"new"` Features to introduce across ANY of the Core Loop Beats—with zero artificial count limits: include whatever set of `"upgrade"` and `"new"` Features across whichever Beats are required to make $versionTag a complete, cohesive playable milestone.\n'
          '  3. DELTA-ONLY JSON OUTPUT (DO NOT REPEAT STABLE FEATURES): In `beats`, output ONLY the Beats and Features receiving active work in $versionTag (`"lifecycle": "upgrade"` or `"lifecycle": "new"`). Use the exact Beat `id` (e.g. `"beat_1"`) and Feature `id`/`title` from the Existing Live Game Tree when upgrading. Do NOT output untouched `"stable"` features in JSON—all omitted existing Beats and Features are automatically preserved as `STABLE ✓` (`0h`).\n'
          '  4. Strictly enforce the Project Exclusions active for this phase: NEVER include or promote any feature that violates a permanent Exclusion (`[NEVER]` / `[CUT]`), while early-phase deferred exclusions (`"in v0.1"`, `"in prototype"`, `"in greybox"`, `[DEFERRED]`) are now unlocked for promotion in Vertical Slice / Full Production.';
    } else if (releasePhase == ProductionPhase.postLaunch.name) {
      phaseInstruction =
          '- PHASE 5 POST-LAUNCH & LIVE OPS ($versionTag): Expand live content rosters, balance tuning parameters, and harden `[PLAYTEST GUARD]` rules on top of the shipped `v1.0` build without breaking save compatibility.';
    } else if (releasePhase == ProductionPhase.mvp.name ||
        targetMvpEpicIndex != null) {
      final epicNum = (targetMvpEpicIndex ?? 0) + 1;
      phaseInstruction =
          '- PHASE 2 PER-EPIC MVP RELEASE (TARGET: EPIC $epicNum ONLY): Upgrade ONLY Beat/Epic #$epicNum from greybox to MVP (`"lifecycle": "upgrade"` with delta MVP checkpoints, plus any queued deferred features for Epic #$epicNum). Keep all other Epics (`!= $epicNum`) strictly `"lifecycle": "stable"` (0h, empty checkpoints).';
    } else if (releasePhase == ProductionPhase.verticalSlice.name ||
        preset == ReleaseScope.verticalSlice) {
      phaseInstruction =
          '- PHASE 3 VERTICAL SLICE (GOLD STANDARD LEVEL): Combine all completed MVP Epics into 1 polished Gold Standard showcase level by upgrading the primary feature in EVERY Beat/Epic (`"lifecycle": "upgrade"`) with a Vertical Slice polish checkpoint (Final Art & Material Swap, SFX/VFX & Camera Feel Cues, HUD Readability & Frame Guard).';
    } else if (releasePhase == ProductionPhase.fullProduction.name ||
        preset == ReleaseScope.fullProduction) {
      phaseInstruction =
          '- PHASE 4 FULL PRODUCTION (CONTENT, LEVELS & DEFERRED SYSTEMS): Bring the rest of the project up to the Vertical Slice bar by upgrading Epics with Content/Level/Wave roster scaling checkpoints (`"lifecycle": "upgrade"`) and promoting previously deferred Out-of-Scope systems into `"lifecycle": "new"` playable features.';
    } else {
      phaseInstruction =
          '- EPICS AS BIG BODIES OF WORK (SYNTHESIZED FROM THE FULL CONCEPT 01–08): Organize `beats` into 4 to 6 major Epics (big bodies of work, e.g. 1. Station Layout, Traversal & Physical Controls, 2. Environment/Tank Simulation & Alarms, 3. Resource/Crop Lifecycle & Harvesting, 4. Cargo Delivery, Shop & Upgrade Mounting) required to build ${releaseDoc.title} across the entire Concept Blueprint (`01 Goal`, `02 Game Spec`, `03 Tech Spec`, `04 Pillars`, `05 Trade-Offs`, `06 Core Loop`, `07 Out of Scope`, `08 Done When`).\n'
          '- GREYBOX LEVEL / ARENA BLOCKOUT FIRST IN EPIC 1: Epic 1 (`beat_1`) MUST start at Feature #1 (`feat_1_1`) with a dedicated Greybox Environment / Arena Blockout Feature matching `02 Game Spec` and `08 Done When` (e.g., `"Station Corridor Blockout"` connecting the four growth bays and cargo airlock, or `"Greybox Arena Layout"`) so floor and wall colliders exist BEFORE Character/Vehicle Movement (`feat_1_2`), Interaction Raycast/Aim (`feat_1_3`), and Primary Control (`feat_1_4`).\n'
          '- ONE ATOMIC MECHANIC PER FEATURE (MINIMUM 4 FEATURES PER EPIC, 16–20 TOTAL): Audit every verb and clause across `01 Goal`, `02 Game Spec`, `04 Pillars`, `05 Trade-Offs`, `06 Core Loop`, and `08 Done When`. Every distinct greybox room/corridor layout, player locomotion mechanic, interaction raycast/prompt, valve rotation, canister injection, simulation drift rule, gauge readout, alarm/wilt feedback state, container unsealing/depressurization step, seed planting step, crop growth timer, mature crop harvest, crate loading step, airlock terminal sale, shop purchase, and physical equipment mounting + second-cycle reset MUST be its own separate Feature card (4 to 5 Features per Epic, 16 to 20 Features total across the release). NEVER bundle two distinct devices or sequential steps (like "Valve + Canister", "Growth + Harvest", or "Shop Purchase + Equipment Mounting") into a single Feature!';
    }

    final targetPhase = switch (releasePhase) {
      'postLaunch' => ProductionPhase.postLaunch,
      'fullProduction' => ProductionPhase.fullProduction,
      'verticalSlice' => ProductionPhase.verticalSlice,
      'mvp' => ProductionPhase.mvp,
      'prototype' => ProductionPhase.prototype,
      _ => isSubsequentRelease
          ? ProductionPhase.mvp
          : ProductionPhase.prototype,
    };

    bool conflictsWithExclusions(String featureTitle) {
      final cleanFeat = featureTitle
          .toLowerCase()
          .replaceFirst(_noPrefixRegex, '')
          .trim();
      if (cleanFeat.isEmpty) return false;
      for (final ex in projectExclusions) {
        if (!ReleaseBlueprint.isExclusionActiveForPhase(ex, targetPhase)) {
          continue;
        }
        final cleanEx = ex
            .toLowerCase()
            .replaceFirst(_cutPrefixRegex, '')
            .replaceFirst(_noPrefixRegex, '')
            .trim();
        if (cleanEx.isNotEmpty &&
            (cleanEx.contains(cleanFeat) || cleanFeat.contains(cleanEx))) {
          return true;
        }
      }
      return false;
    }

    final existingTreeSummary = StringBuffer();
    if (existingBeats.isNotEmpty) {
      existingTreeSummary
          .writeln('Existing Live Game Tree (completed in prior releases):');
      for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
        final b = existingBeats[bIdx];
        existingTreeSummary.writeln('- Beat "${b.title}" (${b.id}):');
        final feats = existingFeaturesByBeat[b.id] ?? const <TierDocument>[];
        for (final f in feats) {
          if (f.sections['lifecycle'] ==
              FeatureLifecycleStatus.superseded.name) {
            final pivotNote = (f.sections['pivot_reason'] ?? '').trim();
            existingTreeSummary.writeln(
              '  * SUPERSEDED / ARCHIVED TESTBED: "${f.title}" [id: ${f.id}${pivotNote.isNotEmpty ? ', reason: $pivotNote' : ''}] — Propose a `"lifecycle": "new"` replacement mechanic in this Beat if needed.',
            );
            continue;
          }
          final states = FeatureStateNode.getStatesForDocument(f);
          final originVer = f.sections['originVersion'] ?? 'v0.1';
          final cpSummaries = <String>[];
          final allTuning = <String>{};
          final allFixesAndGuards = <String>{};
          for (final s in states) {
            final taskNames =
                s.checklist.map((t) => t.text).take(4).join(', ');
            cpSummaries.add('${s.releaseVersion} "${s.cleanStageTitle}" [$taskNames]');
            allTuning.addAll(s.tuningParams);
            for (final g in s.edgeCases) {
              allFixesAndGuards.add(g);
            }
          }
          existingTreeSummary.writeln(
            '  * Feature "${f.title}" [id: ${f.id}, origin: $originVer, ${states.length} checkpoints verified: ${cpSummaries.join(' -> ')}]'
            '${allTuning.isNotEmpty ? ' | Live Variables: ${allTuning.take(5).join(', ')}' : ''}'
            '${allFixesAndGuards.isNotEmpty ? ' | Playtest Guards: ${allFixesAndGuards.take(3).join('; ')}' : ''}',
          );
        }
        final queuedDeferred =
            deferredByBeatIndex[bIdx] ?? const <ProposedFeatureBlueprint>[];
        for (final df in queuedDeferred) {
          if (conflictsWithExclusions(df.title)) continue;
          existingTreeSummary.writeln(
            '  * QUEUED FROM PRIOR RELEASE FOR $versionTag: "${df.title}" (${df.estimatedHours}h) — ${df.goal}',
          );
        }
      }
    }

    final numberedCoreLoopSummary = coreLoopItems.isNotEmpty
        ? [
            for (int i = 0; i < coreLoopItems.length; i++)
              '  BEAT-${(i + 1).toString().padLeft(2, '0')}: ${coreLoopItems[i]}',
          ].join('\n')
        : '  (Decompose the project goal into sequential playable loop beats)';

    final projectGoal = SectionTextUtils.resolveGoal(projectDoc.sections);
    final projectDoneWhen =
        SectionTextUtils.resolveDoneWhen(projectDoc.sections);
    final effectiveModel =
        (!isSubsequentRelease && modelName == 'gemini-4-argon')
            ? 'gemini-flash-latest'
            : modelName;
    final progressiveDiagnosticInstructions = isSubsequentRelease
        ? '''
- ARCHITECTURAL DIAGNOSTIC ("builtSoFar" & "missingGaps"):
  * `"builtSoFar"`: List 2–4 concise 2–5 word phrases summarizing the core mechanics already built and verified in prior releases (e.g., `["Slide & Air Strafe", "Rocket & Gib Shatter", "Room Clear & Pedestals"]`).
  * `"missingGaps"`: List 2–4 concise 1-line statements naming the exact playable gaps in the current build prefixed with the Beat tag (e.g., `["E01: No incoming enemy projectiles to dodge while air-strafing", "E02: Missing rapid-fire plasma weapon", "E05: Single room only — no multi-room chain or boss"]`).
  * `"agentReasoning"`: 1–2 concise summary sentences tying the gaps to $versionTag's focus.
- BESPOKE GAME-SPECIFIC STRATEGIC OPTIONS ("questions"): In `questions[0]`, ask 1 architectural priority question for $versionTag with 3 concrete options tailored specifically to "${projectDoc.title}"'s actual mechanics (Option 1 prefixed with `(Recommended)` matching your primary plan; Options 2 and 3 offering distinct, game-specific alternative angles for $versionTag).'''
        : '';
    final progressiveJsonFields = isSubsequentRelease
        ? '''
  "builtSoFar": ["Slide & Air Strafe", "Rocket & Gib Shatter", "Room Clear & Pedestals"],
  "missingGaps": ["E01: No incoming enemy fire to dodge", "E02: Missing rapid-fire plasma weapon", "E05: Single room only — no boss room"],
  "agentReasoning": "1-2 concise sentences explaining why these $versionTag features are recommended next.",
  "questions": [
    {
      "id": "rel_q_1",
      "question": "How should we focus $versionTag for ${projectDoc.title}?",
      "options": ["(Recommended) Specific Focus A: 1-sentence game-specific description", "Specific Focus B: ...", "Specific Focus C: ..."]
    }
  ],'''
        : '';
    final prompt = '''
You are the Antigravity Release Planner Agent (`$effectiveModel`) planning Release: "${releaseDoc.title}" ($versionTag, ${preset.label}).
Full Concept Blueprint (01–08):
- 01 Goal: "$projectGoal" (Project: "${projectDoc.title}")
- 02 Game Spec: $gameSpecText
- 03 Tech Spec: $techSpecText
- 04 Design Pillars: $pillarsText
- 05 Trade-Offs: $tradeOffsText
- 06 Core Loop:
$numberedCoreLoopSummary
- 07 Out of Scope (Exclusions): ${projectExclusions.join(' | ')}
- 08 Done When: "$projectDoneWhen"
${existingTreeSummary.isNotEmpty ? existingTreeSummary.toString() : 'First Release (v0.1): No prior features exist yet.'}

${GeminiAgentClient.compactStyleRules}
$phaseInstruction
$progressiveDiagnosticInstructions
- STRICT ENGINEERING BUILD DEPENDENCY ORDER (FEATURE N DEPENDS ONLY ON 1..N-1): Stage 1 Core Loop Beats are chronological, but Stage 2 Epics & Features MUST be ordered by **Engineering Build Dependency** so every Feature `N` can be built and playtested in the engine using only scenes, physics bodies, and actions already created in Features `1..N-1`:
  * `Dependency Rule 1 (Surface / Space Before Actor)`: In Epic 1 (`beat_1`), always place the Greybox Level/Arena/Corridor Blockout feature at `Feature #1` BEFORE Player/Vehicle Locomotion at `Feature #2` (so a gravity-enabled body does not fall into the void).
  * `Dependency Rule 2 (Target Entity Before Tool / Tether / Resolver)`: Inside any Epic, always build the physical Target Object, Pickup Body, Container, or Enemy Spawner (`"Scrap Core Physics"`, `"Sentry Drone Spawner"`, `"Water Tank Container"`, `"Cargo Crate"`) BEFORE the Tether, Harpoon, Raycast, Weapon Impact, or Delivery Zone (`"Harpoon Tow Cable"`, `"Drone Projectile Impact"`, `"Winch Docking Zone"`) that attaches to or acts on it. Never put a tether or interaction before the object it hooks onto!
  * `Dependency Rule 3 (Base Mechanic Before Lock / Gate / Constraint)`: Always build the core playable action (`"Mature Crop Harvest"`, `"Heat Cannon Fire"`) BEFORE adding the lock, pressure seal, or overheat gate (`"Tank Seal Depressurize"`, `"Reactor Steam Vent"`) that restricts it.
- THOROUGH MULTI-FEATURE EPIC DECOMPOSITION: Break each Epic into all the individual Playable Features (`"included": true`, 4 to 5 features per Epic across 4 to 6 Epics for a full prototype loop) needed to complete that Epic end-to-end for ${releaseDoc.title}. If a Feature's `inScope` would list 3 different mechanics (e.g., growth stages + harvesting + crate loading, or shop purchase + equipment mounting + seed planting), split each of those mechanics into its own separate Feature card inside that Epic!
- ZERO ARTIFICIAL COUNT LIMITS ON EPICS OR FEATURES: Never merge distinct features just to hit a smaller number, and never drop a mechanic mentioned in `01 Goal`, `02 Game Spec`, `04 Pillars`, `05 Trade-Offs`, `06 Core Loop`, or `08 Done When`.
- PLAYABLE BEAT COMPLETENESS (NO ORPHANED MECHANICS): Never leave a weapon, turret, or defense without a reactive enemy/threat/target feature to test it against, never leave a resource/crop system without both planting/spawning and harvesting/pickup features, and ensure the final Epic covers both the specific reward/upgrade payoff and starting the next cycle/run.
- PLAIN ACTION FEATURE TITLES (NO CODE OR FILLER SUFFIXES): Every Feature must name 1 observable gameplay action or interactive world object (`2–3` plain game-dev words, e.g. `"Station Corridor Blockout"`, `"First Person Movement"`, `"Object Interaction Raycast"`, `"Manual Valve Turn"`, `"Tank Readout Gauge"`, `"Nutrient Canister Inject"`, `"Plant Wilt Stress"`, `"Seed Planting"`, `"Crop Growth Timer"`, `"Mature Crop Harvest"`, `"Tank Seal Depressurize"`, `"Cargo Crate Loading"`, `"Airlock Terminal Sale"`, `"Upgrade Shop Purchase"`, `"Pump Upgrade Mount"`). NEVER use code-architecture or filler nouns (`"Controller"`, `"System"`, `"Mechanic"`, `"Manager"`, `"Component"`, `"Handler"`, `"Action"`, `"Loop"`) and NEVER combine two mechanics with `"&"` or `"and"` in a Feature title.
- RIGHT-SIZED GREYBOX FEATURES: Keep individual `v0.1` greybox features focused on unpolished playable functionality buildable in one sitting rather than lumping an entire physics or combat architecture into a single monolithic ticket.
- Keep temporary greybox testbeds in a separate Feature from permanent mechanics.
- MANDATORY TUNING PARAMETERS ON EVERY FEATURE (NEVER EMPTY): Every single Feature in `beats[].features[]` MUST include `2` to `3` concrete numeric tuning parameters in `"tuningParams"` formatted as `"paramName: value unit"` (e.g., `"plantSnapRadius: 0.4 m"`, `"slotsPerTank: 4 slots"`, `"crateCapacity: 8 crops"`, `"depressurizeDuration: 1.5 s"`). NEVER return an empty `"tuningParams": []` array on any feature.
- NATURAL, CONCRETE TASKS ON ONE SHARED ASSET (NO REPETITIVE "SETUP / LOGIC / GUARD" SUFFIXES): Give each Feature checkpoint 3 to 4 concrete, mechanic-specific tasks (`2–4` words + duration tag) that name the actual node/mesh, behavior, and boundary condition WITHOUT mechanically ending every task in the words `"Setup"`, `"Logic"`, or `"Guard"` (e.g., use `"Capsule Body & Camera (2h)"` -> `"WASD Velocity & Pitch (2h)"` -> `"Wall Slide & Pitch Clamp (1h)"`, or `"Tank Mesh & Pipe Ports (2h)"` -> `"Canister Snap & Refill (2h)"` -> `"Full Tank Overflow Stop (1h)"`):
  * `Task 1` (Entity / Node / Scene Foundation): Create or place the specific playable Character, Greybox Room, Emitter, or Interactive Prop and its collision/ports in the level (e.g., `"Capsule Body & Camera (2h)"`, `"Corridor & Bay Colliders (2h)"`, `"Steam Vent Emitter (1h)"`). NEVER put the words `"Input"`, `"Mapping"`, or `"Keybind"` in `Task 1`'s title.
  * `Task 2` (Core Interaction, Movement, or Simulation Math): Wire the specific interaction, movement, or simulation behavior onto `Task 1`'s asset (e.g., `"WASD Velocity & Look (2h)"`, `"Hold-E Valve Rotation (2h)"`, `"Wilt Color Lerp (2h)"`).
  * `Task 3` (Observable Feedback & Boundary Condition): Hook the visible/audible cue and physical clamp/limit onto that asset (e.g., `"Wall Slide & Pitch Clamp (1h)"`, `"Full Tank Overflow Stop (1h)"`, `"Occupied Slot Reject (1h)"`).
- `lifecycle`: `"new"` for v0.1; for v0.2+, output only `"upgrade"` (delta hours/checkpoints only), `"new"`, or `"superseded"` (omit untouched `"stable"` features from JSON).

Return ONLY valid JSON (checkpoints inherit `coveredScope`, `tuningParams`, and `edgeCases` from their Feature automatically):
{
  "releasePhase": "$schemaPhaseHint",
  "releaseTitle": "$versionTag: Concrete Release Focus",$progressiveJsonFields
  "goal": "Build... goal of ${releaseDoc.title}",
  "doneWhen": "Concrete playtest completion condition",
  "explicitExclusions": ["Excluded mechanic", "..."],
  "beats": [
    {
      "id": "beat_1",
      "title": "Plain Epic Title",
      "goal": "Literal epic goal",
      "doneWhen": "Literal epic completion criteria",
      "features": [
        {
          "id": "feat_1_1",
          "title": "First Feature Title",
          "goal": "Literal feature goal",
          "doneWhen": "Literal feature doneWhen",
          "estimatedHours": 5,
          "included": true,
          "lifecycle": "new",
          "inScope": ["Specific scope item 1", "Specific scope item 2"],
          "outOfScope": ["Deferred item"],
          "tuningParams": ["walkSpeed: 4.5 m/s", "lookSensitivity: 0.15 deg/px"],
          "edgeCases": ["[COLLISION] Prevent player capsule from clipping through corridor walls"],
          "checkpoints": [
            {
              "title": "Plain Checkpoint Title",
              "playtestCriteria": "Action -> observable result on screen",
              "tasks": ["Capsule Body & Camera (2h)", "WASD Velocity & Look (2h)", "Wall Slide & Pitch Clamp (1h)"]
            }
          ]
        },
        {
          "id": "feat_1_2",
          "title": "Second Feature Title",
          "goal": "Literal feature goal",
          "doneWhen": "Literal feature doneWhen",
          "estimatedHours": 4,
          "included": true,
          "lifecycle": "new",
          "inScope": ["Specific scope item"],
          "outOfScope": ["Deferred item"],
          "tuningParams": ["interactDistance: 2.2 m", "highlightOutlineWidth: 2.0 px"],
          "edgeCases": ["[OCCLUSION] Block interaction raycast when a wall or closed door is in between"],
          "checkpoints": [
            {
              "title": "Plain Checkpoint Title",
              "playtestCriteria": "Action -> observable result on screen",
              "tasks": ["Center Aim Raycast (1h)", "Hover Outline & Prompt (2h)", "Line-of-Sight Occlusion Stop (1h)"]
            }
          ]
        }
      ]
    }
  ]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: effectiveModel,
      thinkingLevel: thinkingLevel,
      temperature: 0.35,
    );

    if (json == null) return null;

    final parsed = _parseDynamicReleaseBlueprint(
      json: json,
      releaseDoc: releaseDoc,
      preset: preset,
      versionTag: versionTag,
      fallbackExclusions: projectExclusions,
    );
    if (parsed == null) return null;

    return reconcileReleaseBlueprintWithPhaseRules(
      parsed: parsed,
      releaseDoc: releaseDoc,
      preset: preset,
      versionTag: versionTag,
      existingBeats: existingBeats,
      existingFeaturesByBeat: existingFeaturesByBeat,
      deferredByBeatIndex: deferredByBeatIndex,
      projectExclusions: projectExclusions,
      allCoreLoopItems: coreLoopItems,
    );
  }

  /// Ensures checkpoint tasks follow a strict Foundation-First progression (`01` Asset/Character Setup ->
  /// `02` Input & Core Logic -> `03` Physics/Tuning/Guards) so a developer never starts with Input Mapping
  /// before creating the Character/Actor it attaches to.
  static List<String> normalizeFoundationFirstTasks(
    List<String> rawTasks, {
    required String featureTitle,
    required String beatTitle,
    bool isFirstFeatureOfRelease = false,
  }) {
    if (rawTasks.length < 2) return rawTasks;
    final tasks = List<String>.from(rawTasks);

    bool isPureInputTask(String t) {
      final l = t.toLowerCase();
      return (l.contains('input') || l.contains('mapping') || l.contains('keybind')) &&
          !l.contains('character') &&
          !l.contains('pawn') &&
          !l.contains('actor') &&
          !l.contains('vehicle') &&
          !l.contains('velocity') &&
          !l.contains('physics');
    }

    bool isEntityFoundationTask(String t) {
      final l = t.toLowerCase();
      if (l.contains('character') ||
          l.contains('pawn') ||
          l.contains('actor') ||
          l.contains('player') ||
          l.contains('vehicle') ||
          l.contains('controller') ||
          l.contains('spawner') ||
          l.contains('turret') ||
          l.contains('weapon') ||
          l.contains('hitbox')) {
        return true;
      }
      return l.contains('setup') &&
          !l.contains('input') &&
          !l.contains('mapping') &&
          !l.contains('physics') &&
          !l.contains('velocity') &&
          !l.contains('friction') &&
          !l.contains('animation') &&
          !l.contains('blend');
    }

    if (!isPureInputTask(tasks[0])) {
      return tasks;
    }

    // 1. If a Character/Pawn/Actor setup task was placed at index 1 or 2, move it to index 0 (Task 1)
    final entityTaskIdx = tasks.indexWhere(isEntityFoundationTask);
    if (entityTaskIdx > 0) {
      final foundationTask = tasks.removeAt(entityTaskIdx);
      tasks.insert(0, foundationTask);
      return tasks;
    }

    // 2. Otherwise, if Task 1 is "Input Mapping" and no Character/Actor setup task exists in the list,
    // establish Foundation Setup as Task 1 and merge Input into Task 2 so Task 1 creates the entity first.
    final corpus = '$featureTitle $beatTitle'.toLowerCase();
    final isCharacterFeature = isFirstFeatureOfRelease ||
        corpus.contains('player') ||
        corpus.contains('character') ||
        corpus.contains('pawn') ||
        corpus.contains('sprint') ||
        corpus.contains('slide') ||
        corpus.contains('dash') ||
        corpus.contains('move') ||
        corpus.contains('locomotion') ||
        corpus.contains('traversal') ||
        corpus.contains('parkour') ||
        corpus.contains('jump') ||
        corpus.contains('run');
    final task0Dur = _durationRegex.firstMatch(tasks[0])?.group(0)?.trim() ?? '(2h)';
    final task1Dur = _durationRegex.firstMatch(tasks[1])?.group(0)?.trim() ?? '(2h)';
    final task1Core = tasks[1]
        .replaceFirst(_durationRegex, '')
        .replaceFirst(_setupWordRegex, 'Logic')
        .replaceAll(_whitespaceRegex, ' ')
        .trim();

    tasks[0] =
        '${isCharacterFeature ? "Character Setup" : "Actor Setup"} $task0Dur';
    if (!task1Core.toLowerCase().contains('input')) {
      tasks[1] = 'Input & $task1Core $task1Dur';
    }
    return tasks;
  }

  static List<String> _defaultTuningParamsForFeature(
    String featureTitle,
    String featureGoal,
  ) {
    final cleanWords = featureTitle
        .replaceAll(_nonAlphaNumSpaceRegex, ' ')
        .trim()
        .split(_whitespaceRegex)
        .where((w) => w.isNotEmpty)
        .toList();
    final stem = cleanWords.isEmpty
        ? 'action'
        : cleanWords.first.toLowerCase() +
            cleanWords
                .skip(1)
                .take(2)
                .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
                .join();
    final corpus = '$featureTitle $featureGoal'.toLowerCase();
    if (corpus.contains('crate') ||
        corpus.contains('slot') ||
        corpus.contains('storage') ||
        corpus.contains('plant') ||
        corpus.contains('seed') ||
        corpus.contains('container')) {
      return <String>[
        '${stem}MaxSlots: 4 slots',
        '${stem}SnapRadius: 0.45 m',
      ];
    }
    if (corpus.contains('harvest') ||
        corpus.contains('pickup') ||
        corpus.contains('collect') ||
        corpus.contains('pull')) {
      return <String>[
        '${stem}ReachRange: 1.8 m',
        '${stem}HoldDuration: 0.35 s',
      ];
    }
    if (corpus.contains('corridor') ||
        corpus.contains('room') ||
        corpus.contains('arena') ||
        corpus.contains('layout') ||
        corpus.contains('blockout')) {
      return <String>[
        '${stem}WidthMeters: 4.0 m',
        '${stem}BayCount: 4 bays',
      ];
    }
    return <String>[
      '${stem}Rate: 1.0 units/s',
      '${stem}CooldownSec: 0.25 s',
    ];
  }

  /// Enforces the 3 Engineering Build Dependency Rules inside an Epic so Feature `N`
  /// only depends on scene geometry, target bodies, or base actions created in Features `1..N-1`:
  /// 1. Surface / Space Before Actor (Epic 1 blockout/layout precedes character locomotion).
  /// 2. Target Entity Before Tool / Tether / Resolver (`Scrap Core Physics` precedes `Harpoon Tow Cable`).
  /// 3. Base Mechanic Before Lock / Gate / Constraint (`Mature Crop Harvest` precedes `Tank Seal Depressurize`).
  static List<ProposedFeatureBlueprint> enforceIntraEpicBuildDependencies(
    List<ProposedFeatureBlueprint> rawFeatures, {
    required int epicIndex,
  }) {
    if (rawFeatures.length < 2) return rawFeatures;
    final list = List<ProposedFeatureBlueprint>.from(rawFeatures);

    bool isEnvironmentBlockout(ProposedFeatureBlueprint f) {
      final t = f.title.toLowerCase();
      return t.contains('blockout') ||
          t.contains('arena layout') ||
          t.contains('corridor layout') ||
          t.contains('station layout') ||
          t.contains('room layout') ||
          t.contains('level layout') ||
          t.contains('greybox arena') ||
          t.contains('station corridor');
    }

    // Rule 1: In Epic 1 (epicIndex == 0), move Greybox Level / Arena Blockout to index 0
    if (epicIndex == 0) {
      final blockoutIdx = list.indexWhere(isEnvironmentBlockout);
      if (blockoutIdx > 0) {
        final blockoutFeat = list.removeAt(blockoutIdx);
        list.insert(0, blockoutFeat);
      }
    }

    // Rule 2: Target Entity / Spawner must precede Tether / Harpoon / Projectile Impact
    bool isTetherOrImpactTool(ProposedFeatureBlueprint f) {
      final t = f.title.toLowerCase();
      return t.contains('tow cable') ||
          t.contains('harpoon') ||
          t.contains('tether') ||
          t.contains('projectile impact') ||
          t.contains('hit detection');
    }

    bool isTargetEntityOrSpawner(ProposedFeatureBlueprint f) {
      final t = f.title.toLowerCase();
      return (t.contains('scrap core') ||
              t.contains('core physics') ||
              t.contains('drone spawner') ||
              t.contains('enemy spawner') ||
              t.contains('target spawner')) &&
          !isTetherOrImpactTool(f);
    }

    final toolIdx = list.indexWhere(isTetherOrImpactTool);
    final targetIdx = list.indexWhere(isTargetEntityOrSpawner);
    if (toolIdx != -1 && targetIdx > toolIdx) {
      final targetFeat = list.removeAt(targetIdx);
      list.insert(toolIdx, targetFeat);
    }

    // Rule 3: Base Harvest / Pickup Action must precede Lock / Seal / Depressurize Gate
    bool isPressureOrSealGate(ProposedFeatureBlueprint f) {
      final t = f.title.toLowerCase();
      return t.contains('depressuriz') ||
          t.contains('seal lock') ||
          t.contains('hatch lock') ||
          t.contains('pressure lock');
    }

    bool isBaseHarvestAction(ProposedFeatureBlueprint f) {
      final t = f.title.toLowerCase();
      return (t.contains('harvest') ||
              t.contains('crop pickup') ||
              t.contains('crop extract')) &&
          !isPressureOrSealGate(f);
    }

    final gateIdx = list.indexWhere(isPressureOrSealGate);
    final harvestIdx = list.indexWhere(isBaseHarvestAction);
    if (gateIdx != -1 && harvestIdx > gateIdx) {
      final gateFeat = list.removeAt(gateIdx);
      list.insert(harvestIdx, gateFeat);
    }

    return list;
  }

  static ReleaseBlueprint? _parseDynamicReleaseBlueprint({
    required Map<String, dynamic> json,
    required TierDocument releaseDoc,
    required ReleaseScope preset,
    required String versionTag,
    required List<String> fallbackExclusions,
    bool capV01Checkpoints = true,
  }) {
    final rawBeats = json['beats'];
    if (rawBeats is! List || rawBeats.isEmpty) return null;

    final questions = <AgentQuestion>[];
    final rawQs = json['questions'];
    if (rawQs is List) {
      for (int i = 0; i < rawQs.length; i++) {
        final item = rawQs[i];
        if (item is Map) {
          final qText = (item['question'] ?? '').toString().trim();
          final opts = _parseStringList(item['options']);
          if (qText.isNotEmpty && opts.length >= 2) {
            questions.add(
              AgentQuestion(
                id: (item['id'] ?? 'rel_q_${i + 1}').toString(),
                question: qText,
                options: opts,
              ),
            );
          }
        }
      }
    }

    final beats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < rawBeats.length; bIdx++) {
      final bMap = rawBeats[bIdx];
      if (bMap is! Map) continue;
      final bTitle = MechanicArchetypeProfile.concreteBeatDisplayTitle(
        (bMap['title'] ?? 'Epic ${bIdx + 1}').toString().trim(),
        beatIndex: bIdx,
      );
      final bGoal = (bMap['goal'] ?? '').toString().trim();
      final bDone = (bMap['doneWhen'] ?? '').toString().trim();
      final rawFeats = bMap['features'];
      if (rawFeats is! List || rawFeats.isEmpty) continue;

      final features = <ProposedFeatureBlueprint>[];
      for (int fIdx = 0; fIdx < rawFeats.length; fIdx++) {
        final fMap = rawFeats[fIdx];
        if (fMap is! Map) continue;
        final fTitle = MechanicArchetypeProfile.concreteFeatureTitleForBeat(
          (fMap['title'] ?? 'Feature ${fIdx + 1}').toString().trim(),
          beatTitle: bTitle,
          beatGoal: bGoal,
          beatIndex: bIdx,
        );
        final fGoal = (fMap['goal'] ?? '').toString().trim();
        final fDone = (fMap['doneWhen'] ?? '').toString().trim();

        final rawLifecycle =
            (fMap['lifecycle'] ?? 'new').toString().toLowerCase().trim();
        FeatureLifecycleStatus lifecycle = FeatureLifecycleStatus.newFeature;
        if (rawLifecycle.contains('stable') || rawLifecycle.contains('keep')) {
          lifecycle = FeatureLifecycleStatus.stable;
        } else if (rawLifecycle.contains('upgrade') ||
            rawLifecycle.contains('expand')) {
          lifecycle = FeatureLifecycleStatus.upgrade;
        } else if (rawLifecycle.contains('supersed') ||
            rawLifecycle.contains('archiv')) {
          lifecycle = FeatureLifecycleStatus.superseded;
        }

        final hours = lifecycle == FeatureLifecycleStatus.stable
            ? 0
            : ((fMap['estimatedHours'] is num)
                ? (fMap['estimatedHours'] as num).round().clamp(0, 24)
                : 4);
        final included = lifecycle == FeatureLifecycleStatus.superseded
            ? false
            : (fMap['included'] is bool ? fMap['included'] as bool : true);
        final originVersion =
            (fMap['originVersion'] ?? versionTag).toString().trim();
        final supersedesTitle =
            fMap['supersedesFeatureTitle']?.toString().trim();

        final inScope = _parseStringList(fMap['inScope']);
        final outOfScope = _parseStringList(fMap['outOfScope']);
        final rawTuning = _parseStringList(fMap['tuningParams']);
        final tuning = rawTuning.isNotEmpty
            ? rawTuning
            : _defaultTuningParamsForFeature(fTitle, fGoal);
        final edges = _parseStringList(fMap['edgeCases'])
            .map((e) => e.replaceFirst(_tagPrefixRegex, '[STATE GUARD] '))
            .toList();

        final checkpoints = <ProposedCheckpointBlueprint>[];
        final rawCps = fMap['checkpoints'];
        if (rawCps is List) {
          for (int cIdx = 0; cIdx < rawCps.length; cIdx++) {
            final cMap = rawCps[cIdx];
            if (cMap is! Map) continue;
            final cpTitle =
                (cMap['title'] ?? 'Stage ${cIdx + 1}').toString().trim();
            final cpCriteria = (cMap['playtestCriteria'] ?? fDone)
                .toString()
                .trim();
            final cpVer = versionTag;
            final cpTasks = normalizeFoundationFirstTasks(
              _parseStringList(cMap['tasks']),
              featureTitle: fTitle,
              beatTitle: bTitle,
              isFirstFeatureOfRelease: bIdx == 0 && fIdx == 0 && cIdx == 0,
            );
            final cScope = _parseStringList(cMap['coveredScope']);
            final cTuning = _parseStringList(cMap['tuningParams']);
            final cEdges = _parseStringList(cMap['edgeCases']);
            checkpoints.add(
              ProposedCheckpointBlueprint(
                title: cpTitle,
                playtestCriteria: cpCriteria,
                releaseVersion: cpVer,
                tasks: cpTasks,
                coveredScope: cScope.isNotEmpty ? cScope : inScope,
                tuningParams: cTuning.isNotEmpty ? cTuning : tuning,
                edgeCases: cEdges.isNotEmpty ? cEdges : edges,
              ),
            );
          }
        }

        if (capV01Checkpoints && versionTag == 'v0.1' && checkpoints.length > 1) {
          checkpoints.removeRange(1, checkpoints.length);
        }

        features.add(
          ProposedFeatureBlueprint(
            id: (fMap['id'] ?? 'feat_${bIdx + 1}_${fIdx + 1}').toString(),
            title: fTitle,
            goal: fGoal,
            doneWhen: fDone,
            estimatedHours: hours,
            included: included,
            lifecycle: lifecycle,
            originVersion: originVersion.isNotEmpty ? originVersion : versionTag,
            supersedesFeatureTitle:
                (supersedesTitle != null && supersedesTitle.isNotEmpty)
                    ? supersedesTitle
                    : null,
            inScope: inScope,
            outOfScope: outOfScope,
            tuningParams: tuning,
            edgeCases: edges,
            checkpoints: checkpoints,
          ),
        );
      }

      if (features.isNotEmpty) {
        final orderedFeatures = (capV01Checkpoints && versionTag == 'v0.1')
            ? enforceIntraEpicBuildDependencies(features, epicIndex: bIdx)
            : features;
        beats.add(
          ProposedBeatBlueprint(
            id: (bMap['id'] ?? 'beat_${bIdx + 1}').toString(),
            title: bTitle,
            goal: bGoal,
            doneWhen: bDone,
            features: orderedFeatures,
          ),
        );
      }
    }

    if (beats.isEmpty) return null;

    final rawEx = json['explicitExclusions'];
    final exclusions = rawEx is List
        ? rawEx
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : fallbackExclusions;
    final rawBuiltSoFar = json['builtSoFar'];
    final builtSoFar = rawBuiltSoFar is List
        ? rawBuiltSoFar
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];
    final rawMissingGaps = json['missingGaps'];
    final missingGaps = rawMissingGaps is List
        ? rawMissingGaps
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];

    final rawReasoning =
        (json['agentReasoning'] ?? json['lastAgentReply'] ?? '')
            .toString()
            .trim();
    final activeFeatureNames = <String>[
      for (final b in beats)
        for (final f in b.features)
          if (f.included && f.lifecycle != FeatureLifecycleStatus.stable)
            f.title,
    ];
    final isAgentReasoned = releaseDoc.sections['agentReasoned'] == 'true';
    var effectivePreset = preset;
    final currentDocPhase = (releaseDoc.sections['phase'] ?? '').trim();
    if (currentDocPhase == ProductionPhase.postLaunch.name ||
        currentDocPhase == ProductionPhase.fullProduction.name) {
      effectivePreset = ReleaseScope.fullProduction;
    } else if (currentDocPhase == ProductionPhase.verticalSlice.name) {
      effectivePreset = ReleaseScope.verticalSlice;
    } else if (currentDocPhase == ProductionPhase.mvp.name) {
      effectivePreset = ReleaseScope.mvp;
    } else if (isAgentReasoned &&
        releaseDoc.sections['phaseLockedByUser'] != 'true') {
      final rawPhase =
          (json['releasePhase'] ?? json['phase'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      if (rawPhase.contains('post') ||
          rawPhase.contains('live') ||
          rawPhase.contains('patch')) {
        releaseDoc.sections['phase'] = ProductionPhase.postLaunch.name;
        releaseDoc.sections['releaseScope'] = ReleaseScope.fullProduction.name;
        effectivePreset = ReleaseScope.fullProduction;
      } else if (rawPhase.contains('full') || rawPhase.contains('production')) {
        releaseDoc.sections['phase'] = ProductionPhase.fullProduction.name;
        releaseDoc.sections['releaseScope'] = ReleaseScope.fullProduction.name;
        effectivePreset = ReleaseScope.fullProduction;
      } else if (rawPhase.contains('vertical') ||
          rawPhase.contains('slice') ||
          rawPhase.contains('polish')) {
        releaseDoc.sections['phase'] = ProductionPhase.verticalSlice.name;
        releaseDoc.sections['releaseScope'] = ReleaseScope.verticalSlice.name;
        effectivePreset = ReleaseScope.verticalSlice;
      } else if (rawPhase.contains('mvp')) {
        releaseDoc.sections['phase'] = ProductionPhase.mvp.name;
        releaseDoc.sections['releaseScope'] = ReleaseScope.mvp.name;
        effectivePreset = ReleaseScope.mvp;
      }
    }
    final rawRelTitle = (json['releaseTitle'] ?? '').toString().trim();
    String effectiveReleaseTitle = releaseDoc.title;
    if (rawRelTitle.isNotEmpty) {
      effectiveReleaseTitle = rawRelTitle.startsWith('$versionTag:')
          ? rawRelTitle
          : '$versionTag: ${rawRelTitle.replaceFirst(_versionPrefixStripRegex, '')}';
      releaseDoc.title = effectiveReleaseTitle;
    } else if (isAgentReasoned && activeFeatureNames.isNotEmpty) {
      effectiveReleaseTitle =
          '$versionTag: ${activeFeatureNames.take(2).join(' & ')}';
      releaseDoc.title = effectiveReleaseTitle;
    }
    final effectiveReasoning = rawReasoning.isNotEmpty
        ? rawReasoning
        : (activeFeatureNames.isNotEmpty
            ? 'Based on your verified build state and Stage 1 Design Pillars, $versionTag focuses on ${activeFeatureNames.take(3).join(', ')} so the next playable loop milestone connects cleanly.'
            : 'Synthesized $versionTag release plan for $effectiveReleaseTitle.');

    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: effectiveReleaseTitle,
      releaseVersionTag: versionTag,
      preset: effectivePreset,
      goal: (json['goal'] ?? '').toString().trim(),
      doneWhen: (json['doneWhen'] ?? '').toString().trim(),
      questions: questions,
      beats: beats,
      explicitExclusions: exclusions,
      builtSoFar: builtSoFar,
      missingGaps: missingGaps,
      lastAgentReply: effectiveReasoning,
    );
  }

  /// Builds an immediate, deterministic `v0.1` `ReleaseBlueprint` directly from the approved
  /// Stage 1 `06 · Core Loop` Beats (`projectDoc.sections`) as a safety net when a live network
  /// timeout occurs during `v0.1` planning, ensuring `Approve & Build v0.1 →` never hangs or
  /// bounces the user back to Stage 1.
  static ReleaseBlueprint? buildImmediateInitialBaselineBlueprint({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
  }) {
    final coreLoopItems = SectionTextUtils.resolveInScope(projectDoc.sections);
    if (coreLoopItems.isEmpty) return null;
    final preset = releaseDoc.releaseScope;
    final versionTag = extractReleaseVersionTag(releaseDoc.title);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );
    final prototypePart = releaseDoc.sections['prototypePart'] ?? '';
    final effectiveLoopItems =
        (prototypePart == '1' && coreLoopItems.length >= 2)
            ? coreLoopItems.take((coreLoopItems.length / 2).ceil()).toList()
            : coreLoopItems;

    final beats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < effectiveLoopItems.length; bIdx++) {
      final rawBeat = effectiveLoopItems[bIdx].trim();
      final colonIdx = rawBeat.indexOf(':');
      final rawTitlePart = colonIdx > 0
          ? rawBeat.substring(0, colonIdx).trim()
          : rawBeat;
      final rawDescPart = colonIdx > 0 && colonIdx + 1 < rawBeat.length
          ? rawBeat.substring(colonIdx + 1).trim()
          : rawBeat;

      final bTitle = MechanicArchetypeProfile.concreteBeatDisplayTitle(
        rawTitlePart,
        beatIndex: bIdx,
      );
      final bGoal = rawDescPart.isNotEmpty
          ? (rawDescPart.endsWith('.') ? rawDescPart : '$rawDescPart.')
          : 'Build $bTitle in the greybox arena.';
      final fTitle = MechanicArchetypeProfile.concreteFeatureTitleForBeat(
        rawTitlePart,
        beatTitle: bTitle,
        beatGoal: bGoal,
        beatIndex: bIdx,
      );
      final tasks = normalizeFoundationFirstTasks(
        [
          bIdx == 0 ? 'Character Setup (2h)' : 'Actor Setup (2h)',
          'Input & State Logic (1h)',
          'Physics & State Guard (1h)',
        ],
        featureTitle: fTitle,
        beatTitle: bTitle,
        isFirstFeatureOfRelease: bIdx == 0,
      );

      beats.add(
        ProposedBeatBlueprint(
          id: 'beat_${bIdx + 1}',
          title: bTitle,
          goal: bGoal,
          doneWhen: 'Playtester verifies $bTitle in the test arena.',
          features: [
            ProposedFeatureBlueprint(
              id: 'feat_${bIdx + 1}_1',
              title: fTitle,
              goal: bGoal,
              doneWhen: 'Playtester triggers $fTitle and verifies response on screen.',
              estimatedHours: 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.newFeature,
              originVersion: versionTag,
              inScope: [rawBeat],
              outOfScope: const [],
              tuningParams: const [
                'primarySpeed: 240.0 units/s',
                'responseCooldownSec: 0.25 s',
              ],
              edgeCases: const [
                '[STATE GUARD] Prevent duplicate trigger while action is active',
              ],
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: '$fTitle Core',
                  playtestCriteria:
                      'Trigger $fTitle in playtest -> verify immediate response on screen',
                  releaseVersion: versionTag,
                  tasks: tasks,
                  coveredScope: [rawBeat],
                  tuningParams: const [
                    'primarySpeed: 240.0 units/s',
                    'responseCooldownSec: 0.25 s',
                  ],
                  edgeCases: const [
                    '[STATE GUARD] Prevent duplicate trigger while action is active',
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    final projGoal = SectionTextUtils.resolveGoal(projectDoc.sections);
    final projDone = SectionTextUtils.resolveDoneWhen(projectDoc.sections);
    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
      preset: preset,
      goal: projGoal.isNotEmpty
          ? projGoal
          : 'Build and verify the $versionTag playable greybox core loop.',
      doneWhen: projDone.isNotEmpty
          ? projDone
          : 'All $versionTag Core Loop Epics pass playtest verification.',
      questions: const [],
      beats: beats,
      explicitExclusions: projectExclusions,
      lastAgentReply:
          'Structured $versionTag Epics & Features directly from your approved Stage 1 Core Loop Beats.',
    );
  }

  /// Builds an immediate, phase-accurate `ReleaseBlueprint` for `releaseDoc` (`v0.2+`)
  /// from the existing Vault tree before the async `gemini-4-argon` HTTP call completes
  /// (and as a safety net if the network request times out), ensuring `_releaseBlueprint`
  /// never retains a stale prior release (`v0.4`) while planning `v0.5`.
  static ReleaseBlueprint? buildImmediateProgressiveBaselineBlueprint({
    required TierDocument projectDoc,
    required TierDocument releaseDoc,
    required List<TierDocument> existingBeats,
    required Map<String, List<TierDocument>> existingFeaturesByBeat,
    required Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex,
  }) {
    if (existingBeats.isEmpty) return null;
    final preset = releaseDoc.releaseScope;
    final versionTag = extractReleaseVersionTag(releaseDoc.title);
    final releasePhase = releaseDoc.sections['phase'] ?? '';
    final rawTargetEpicIdx = releaseDoc.sections['targetEpicIndex'];
    final mvpEpicMatch = _mvpEpicNumRegex.firstMatch(releaseDoc.title);
    final int? targetMvpEpicIndex = rawTargetEpicIdx != null
        ? int.tryParse(rawTargetEpicIdx)
        : (mvpEpicMatch != null
            ? (int.tryParse(mvpEpicMatch.group(1)!) ?? 1) - 1
            : null);
    final projectExclusions = SectionTextUtils.resolveExclusions(
      projectDoc.sections,
      splitSingleSentence: false,
    );

    int defaultMvpBeatIdx = 0;
    if (targetMvpEpicIndex == null) {
      for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
        final feats =
            existingFeaturesByBeat[existingBeats[bIdx].id] ?? const <TierDocument>[];
        final anyStillV01Only = feats.any(
          (f) => FeatureStateNode.getStatesForDocument(f).length <= 1,
        );
        if (anyStillV01Only) {
          defaultMvpBeatIdx = bIdx;
          break;
        }
      }
    }

    final beats = <ProposedBeatBlueprint>[];
    for (int bIdx = 0; bIdx < existingBeats.length; bIdx++) {
      final eb = existingBeats[bIdx];
      final existingFeats =
          existingFeaturesByBeat[eb.id] ?? const <TierDocument>[];
      final isTargetEpic = targetMvpEpicIndex != null
          ? bIdx == targetMvpEpicIndex
          : (releasePhase == ProductionPhase.verticalSlice.name ||
                  releasePhase == ProductionPhase.fullProduction.name ||
                  releasePhase == ProductionPhase.postLaunch.name
              ? true
              : bIdx == defaultMvpBeatIdx);

      final proposedFeats = <ProposedFeatureBlueprint>[];
      for (int fIdx = 0; fIdx < existingFeats.length; fIdx++) {
        final ef = existingFeats[fIdx];
        if (ef.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name) {
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: ef.id,
              title: ef.title,
              goal: SectionTextUtils.resolveGoal(ef.sections),
              doneWhen: SectionTextUtils.resolveDoneWhen(ef.sections),
              estimatedHours: 0,
              included: false,
              lifecycle: FeatureLifecycleStatus.superseded,
              originVersion: ef.sections['originVersion'] ?? 'v0.1',
              inScope: SectionTextUtils.resolveInScope(ef.sections),
              outOfScope: const [],
              tuningParams: const [],
              edgeCases: const [],
              checkpoints: const [],
            ),
          );
          continue;
        }
        final shouldUpgrade = isTargetEpic &&
            (targetMvpEpicIndex != null || fIdx == 0);
        if (shouldUpgrade) {
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: ef.id,
              title: ef.title,
              goal:
                  'Upgrade ${ef.title} for $versionTag (${releaseDoc.title}).',
              doneWhen:
                  'Playtester verifies the $versionTag ${ef.title} upgrade in the level.',
              estimatedHours: 4,
              included: true,
              lifecycle: FeatureLifecycleStatus.upgrade,
              originVersion: ef.sections['originVersion'] ?? 'v0.1',
              inScope: SectionTextUtils.resolveInScope(ef.sections),
              outOfScope: const [],
              tuningParams: const ['responseMultiplier: 1.25x'],
              edgeCases: const ['[STATE GUARD] Verify clean transition in playtest'],
              checkpoints: [
                ProposedCheckpointBlueprint(
                  title: '${ef.title} ($versionTag Upgrade)',
                  playtestCriteria:
                      'Trigger ${ef.title} -> verify $versionTag upgrade behavior',
                  releaseVersion: versionTag,
                  tasks: const [
                    'Actor Setup (2h)',
                    'State Logic (1h)',
                    'State Guard (1h)',
                  ],
                ),
              ],
            ),
          );
        } else {
          proposedFeats.add(
            ProposedFeatureBlueprint(
              id: ef.id,
              title: ef.title,
              goal: SectionTextUtils.resolveGoal(ef.sections),
              doneWhen: SectionTextUtils.resolveDoneWhen(ef.sections),
              estimatedHours: 0,
              included: true,
              lifecycle: FeatureLifecycleStatus.stable,
              originVersion: ef.sections['originVersion'] ?? 'v0.1',
              inScope: SectionTextUtils.resolveInScope(ef.sections),
              outOfScope: const [],
              tuningParams: const [],
              edgeCases: const [],
              checkpoints: const [],
            ),
          );
        }
      }

      final deferredList = deferredByBeatIndex[bIdx];
      if (deferredList != null) {
        for (final defFeat in deferredList) {
          defFeat.included = true;
          defFeat.lifecycle = FeatureLifecycleStatus.newFeature;
          defFeat.originVersion = versionTag;
          proposedFeats.add(defFeat);
        }
      }

      beats.add(
        ProposedBeatBlueprint(
          id: eb.id,
          title: eb.title,
          goal: SectionTextUtils.resolveGoal(eb.sections),
          doneWhen: SectionTextUtils.resolveDoneWhen(eb.sections),
          features: proposedFeats,
        ),
      );
    }

    final relGoal = SectionTextUtils.resolveGoal(releaseDoc.sections);
    final relDone = SectionTextUtils.resolveDoneWhen(releaseDoc.sections);
    final defaultQuestions = releasePhase == ProductionPhase.postLaunch.name
        ? <AgentQuestion>[
            AgentQuestion(
              id: 'rel_q_post_launch',
              question: 'How should we focus $versionTag Post-Launch Live Ops?',
              options: const [
                '(Recommended) Content Expansion Pack: Add new playable roster/encounter variety and upgrade core loop depth',
                'Balance & Feel Patch: Tighten live tuning variables, resolve playtest [FIX] items, and harden [GUARD] rules',
                'Endgame Challenge Mode: Add high-intensity loop modifiers and mastery rewards using shipped v1.0 assets',
              ],
            ),
          ]
        : const <AgentQuestion>[];
    return ReleaseBlueprint(
      releaseDocId: releaseDoc.id,
      releaseTitle: releaseDoc.title,
      releaseVersionTag: versionTag,
      preset: preset,
      goal: relGoal.isNotEmpty
          ? relGoal
          : 'Build and verify $versionTag (${releaseDoc.title}).',
      doneWhen: relDone.isNotEmpty
          ? relDone
          : 'All $versionTag active features pass playtest verification.',
      questions: defaultQuestions,
      beats: beats,
      explicitExclusions: projectExclusions,
      lastAgentReply:
          'Analyzing your completed release tree, tuning variables, and Stage 1 Design Pillars to recommend the highest-impact $versionTag scope...',
    );
  }

  /// Reconciles a live LLM `ReleaseBlueprint` against existing Vault Beat/Feature IDs
  /// so upgrades in `v0.2+` attach to existing feature documents in-place without duplication.
  static ReleaseBlueprint reconcileReleaseBlueprintWithPhaseRules({
    required ReleaseBlueprint parsed,
    required TierDocument releaseDoc,
    required ReleaseScope preset,
    required String versionTag,
    required List<TierDocument> existingBeats,
    required Map<String, List<TierDocument>> existingFeaturesByBeat,
    required Map<int, List<ProposedFeatureBlueprint>> deferredByBeatIndex,
    required List<String> projectExclusions,
    required List<String> allCoreLoopItems,
  }) {
    final prototypePart = releaseDoc.sections['prototypePart'] ?? '';
    final isSubsequentRelease =
        existingBeats.isNotEmpty || versionTag != 'v0.1';

    if (!isSubsequentRelease) {
      if (prototypePart == '1' && allCoreLoopItems.length >= 2) {
        final halfCount = (allCoreLoopItems.length / 2).ceil();
        if (parsed.beats.length > halfCount) {
          return ReleaseBlueprint(
            releaseDocId: parsed.releaseDocId,
            releaseTitle: parsed.releaseTitle,
            releaseVersionTag: parsed.releaseVersionTag,
            preset: parsed.preset,
            goal: parsed.goal,
            doneWhen: parsed.doneWhen,
            questions: parsed.questions,
            beats: parsed.beats.take(halfCount).toList(),
            explicitExclusions: parsed.explicitExclusions,
          );
        }
      }
      return parsed;
    }

    if (existingBeats.isEmpty) return parsed;

    final isAgentReasoned = releaseDoc.sections['agentReasoned'] == 'true';
    final matchedLlmBeatByExistingId = <String, ProposedBeatBlueprint>{};
    final unmatchedNewLlmBeats = <ProposedBeatBlueprint>[];

    for (int bIdx = 0; bIdx < parsed.beats.length; bIdx++) {
      final llmBeat = parsed.beats[bIdx];
      final cleanLlmTitle = llmBeat.title.toLowerCase().trim();
      TierDocument? matchedBeatDoc;

      // 1. Exact ID or exact title match
      for (final eb in existingBeats) {
        if (matchedLlmBeatByExistingId.containsKey(eb.id)) continue;
        if (eb.id == llmBeat.id ||
            eb.title.toLowerCase().trim() == cleanLlmTitle) {
          matchedBeatDoc = eb;
          break;
        }
      }
      // 2. Substring title match
      if (matchedBeatDoc == null && cleanLlmTitle.isNotEmpty) {
        for (final eb in existingBeats) {
          if (matchedLlmBeatByExistingId.containsKey(eb.id)) continue;
          final cleanEbTitle = eb.title.toLowerCase().trim();
          if (cleanEbTitle.contains(cleanLlmTitle) ||
              cleanLlmTitle.contains(cleanEbTitle)) {
            matchedBeatDoc = eb;
            break;
          }
        }
      }
      // 3. Positional fallback only when all existing beats were returned in full
      if (matchedBeatDoc == null &&
          parsed.beats.length == existingBeats.length &&
          bIdx < existingBeats.length &&
          !matchedLlmBeatByExistingId.containsKey(existingBeats[bIdx].id)) {
        matchedBeatDoc = existingBeats[bIdx];
      }

      if (matchedBeatDoc != null) {
        matchedLlmBeatByExistingId[matchedBeatDoc.id] = llmBeat;
      } else {
        unmatchedNewLlmBeats.add(llmBeat);
      }
    }

    final reconciledBeats = <ProposedBeatBlueprint>[];
    for (int ebIdx = 0; ebIdx < existingBeats.length; ebIdx++) {
      final eb = existingBeats[ebIdx];
      final existingFeats =
          existingFeaturesByBeat[eb.id] ?? const <TierDocument>[];
      final llmBeat = matchedLlmBeatByExistingId[eb.id] ??
          ProposedBeatBlueprint(
            id: eb.id,
            title: eb.title,
            goal: SectionTextUtils.resolveGoal(eb.sections),
            doneWhen: SectionTextUtils.resolveDoneWhen(eb.sections),
            features: <ProposedFeatureBlueprint>[],
          );

      llmBeat.id = eb.id;
      final matchedByExistingId = <String, ProposedFeatureBlueprint>{};
      final unmatchedNewFeats = <ProposedFeatureBlueprint>[];
      final cleanVer = versionTag.replaceAll(_nonAlphaNumRegex, '_');

      for (int fIdx = 0; fIdx < llmBeat.features.length; fIdx++) {
        final lf = llmBeat.features[fIdx];
        final normLfTitle = lf.title.toLowerCase().trim();
        TierDocument? matchedEf;
        for (final ef in existingFeats) {
          if (matchedByExistingId.containsKey(ef.id)) continue;
          final normEfTitle = ef.title.toLowerCase().trim();
          final titleMatches =
              normEfTitle.isNotEmpty && normEfTitle == normLfTitle;
          final idMatchesNonNew =
              lf.lifecycle != FeatureLifecycleStatus.newFeature &&
              ef.id == lf.id;
          if (titleMatches || idMatchesNonNew) {
            matchedEf = ef;
            break;
          }
        }
        if (matchedEf != null) {
          lf.id = matchedEf.id;
          lf.originVersion = matchedEf.sections['originVersion'] ?? 'v0.1';
          matchedByExistingId[matchedEf.id] = lf;
        } else {
          final existingIdCollision = existingFeats.any((e) => e.id == lf.id) ||
              lf.id.startsWith('feat_1_') ||
              lf.id.startsWith('feat_2_') ||
              lf.id.startsWith('feat_3_') ||
              lf.id.startsWith('feat_4_') ||
              lf.id.startsWith('feat_5_');
          if (existingIdCollision || lf.id.trim().isEmpty) {
            lf.id =
                'feat_${eb.id}_${cleanVer}_new_${unmatchedNewFeats.length + 1}';
          }
          unmatchedNewFeats.add(lf);
        }
      }

      // Preserve canonical existing feature order first (UPGRADE, STABLE ✓, or SUPERSEDED), followed by genuinely NEW features
      final orderedFeatures = <ProposedFeatureBlueprint>[];
      for (final ef in existingFeats) {
        final matchedLf = matchedByExistingId[ef.id];
        final isAlreadySuperseded =
            ef.sections['lifecycle'] == FeatureLifecycleStatus.superseded.name;
        if (matchedLf != null) {
          orderedFeatures.add(matchedLf);
        } else {
          orderedFeatures.add(
            ProposedFeatureBlueprint(
              id: ef.id,
              title: ef.title,
              goal: SectionTextUtils.resolveGoal(ef.sections),
              doneWhen: SectionTextUtils.resolveDoneWhen(ef.sections),
              estimatedHours: 0,
              included: !isAlreadySuperseded,
              lifecycle: isAlreadySuperseded
                  ? FeatureLifecycleStatus.superseded
                  : FeatureLifecycleStatus.stable,
              originVersion: ef.sections['originVersion'] ?? 'v0.1',
              inScope: SectionTextUtils.resolveInScope(ef.sections),
              outOfScope: const [],
              tuningParams: const [],
              edgeCases: const [],
              checkpoints: const [],
            ),
          );
        }
      }
      orderedFeatures.addAll(unmatchedNewFeats);
      llmBeat.features = orderedFeatures;

      final deferredList = deferredByBeatIndex[ebIdx];
      if (!isAgentReasoned && deferredList != null && deferredList.isNotEmpty) {
        final rawDocPhase = (releaseDoc.sections['phase'] ?? '').trim();
        final targetPhase = switch (rawDocPhase) {
          'postLaunch' => ProductionPhase.postLaunch,
          'fullProduction' => ProductionPhase.fullProduction,
          'verticalSlice' => ProductionPhase.verticalSlice,
          'mvp' => ProductionPhase.mvp,
          'prototype' => ProductionPhase.prototype,
          _ => ProductionPhase.mvp,
        };
        final combinedExclusions = <String>{
          ...projectExclusions,
          ...parsed.explicitExclusions,
        };
        for (final defFeat in deferredList) {
          final cleanDef = defFeat.title
              .toLowerCase()
              .replaceFirst(_noPrefixRegex, '')
              .trim();
          final isExcluded = combinedExclusions.any((ex) {
            if (!ReleaseBlueprint.isExclusionActiveForPhase(ex, targetPhase)) {
              return false;
            }
            final cleanEx = ex
                .toLowerCase()
                .replaceFirst(_cutPrefixRegex, '')
                .replaceFirst(_noPrefixRegex, '')
                .trim();
            return cleanEx.isNotEmpty &&
                cleanDef.isNotEmpty &&
                (cleanEx.contains(cleanDef) || cleanDef.contains(cleanEx));
          });
          if (isExcluded) continue;
          final alreadyPresent = llmBeat.features.any(
            (f) =>
                f.id == defFeat.id ||
                f.title.toLowerCase().trim() ==
                    defFeat.title.toLowerCase().trim(),
          );
          if (!alreadyPresent) {
            defFeat.included = true;
            defFeat.lifecycle = FeatureLifecycleStatus.newFeature;
            defFeat.originVersion = versionTag;
            llmBeat.features.add(defFeat);
          }
        }
      }

      reconciledBeats.add(llmBeat);
    }

    reconciledBeats.addAll(unmatchedNewLlmBeats);
    parsed.beats = reconciledBeats;

    return parsed;
  }

  /// Turn-by-turn Release Plan Gate Chat: Takes the user's message, updates
  /// the live `ReleaseBlueprint` in place via Gemini AI, and sets `lastAgentReply`.
  /// Returns `false` if offline or if Gemini AI cannot be reached.
  static Future<bool> sendReleasePlanChatTurn({
    required ReleaseBlueprint blueprint,
    required String userMessage,
    String apiKey = '',
    String modelName = 'gemini-flash-latest',
    String thinkingLevel = 'LOW',
  }) async {
    final cleanMsg = userMessage.trim();
    if (cleanMsg.isEmpty || !GeminiAgentClient.hasKey(apiKey)) return false;

    final currentBeatsSummary = blueprint.beats
        .map(
          (b) => '- ${b.id} "${b.title}" (${b.goal}): '
              '${b.features.map((f) => '"${f.title}" [${f.included ? "IN" : "DEFERRED"}, ${f.activeDeltaHours}h]').join(', ')}',
        )
        .join('\n');

    final prompt = '''
You are the Antigravity Release Planner Agent updating "${blueprint.releaseTitle}" (${blueprint.releaseVersionTag}).
Current Plan:
- Goal: "${blueprint.goal}"
- Done When: "${blueprint.doneWhen}"
- Exclusions: ${blueprint.explicitExclusions.join(', ')}
- Beats:
$currentBeatsSummary

Developer Request: "$cleanMsg"
${GeminiAgentClient.compactStyleRules}
- DELTA-ONLY BEATS: In `beats`, return ONLY the specific Beat(s) that were modified or added by the developer's request (untouched Beats are preserved automatically).

Return ONLY valid JSON:
{
  "reply": "1-2 sentence confirmation of the changes made",
  "goal": "Updated release goal (or existing if unchanged)",
  "doneWhen": "Updated release doneWhen (or existing if unchanged)",
  "explicitExclusions": ["Exclusion 1", "Exclusion 2"],
  "beats": [
    {
      "id": "beat_1",
      "title": "Plain Beat Title",
      "goal": "1-sentence literal beat goal",
      "doneWhen": "1-sentence literal beat completion criteria",
      "features": [
        {
          "id": "feat_1_1",
          "title": "Plain Feature Title",
          "goal": "1-sentence literal feature goal",
          "doneWhen": "1-sentence literal feature doneWhen",
          "estimatedHours": 6,
          "included": true,
          "lifecycle": "new",
          "inScope": ["Scope item"],
          "outOfScope": ["Deferred item"],
          "tuningParams": ["paramOne: 10.0 m/s"],
          "edgeCases": ["[TAG] Specific edge case behavior"],
          "checkpoints": [
            {
              "title": "Plain Checkpoint Title",
              "playtestCriteria": "Action -> observable result on screen",
              "tasks": ["Task 1 (2h)", "Task 2 (2h)"]
            }
          ]
        }
      ]
    }
  ]
}
''';

    final json = await GeminiAgentClient.generateJson(
      prompt: prompt,
      apiKey: apiKey,
      preferredModel: modelName,
      thinkingLevel: thinkingLevel,
      temperature: 0.35,
    );

    if (json == null) return false;

    final dummyDoc = TierDocument(
      id: blueprint.releaseDocId,
      title: blueprint.releaseTitle,
      tier: TierType.release,
    );
    final updatedBp = _parseDynamicReleaseBlueprint(
      json: json,
      releaseDoc: dummyDoc,
      preset: blueprint.preset,
      versionTag: blueprint.releaseVersionTag,
      fallbackExclusions: blueprint.explicitExclusions,
      capV01Checkpoints: false,
    );
    if (updatedBp == null) return false;

    if (updatedBp.goal.isNotEmpty) blueprint.goal = updatedBp.goal;
    if (updatedBp.doneWhen.isNotEmpty) blueprint.doneWhen = updatedBp.doneWhen;
    final mergedBeats = List<ProposedBeatBlueprint>.from(blueprint.beats);
    for (final deltaBeat in updatedBp.beats) {
      final idx = mergedBeats.indexWhere(
        (b) =>
            b.id == deltaBeat.id ||
            b.title.toLowerCase().trim() ==
                deltaBeat.title.toLowerCase().trim(),
      );
      if (idx != -1) {
        final existingBeat = mergedBeats[idx];
        deltaBeat.id = existingBeat.id;
        final reconciledFeats = <ProposedFeatureBlueprint>[];
        final matchedExistingIds = <String>{};
        for (final df in deltaBeat.features) {
          final existingFeat = existingBeat.features
              .where(
                (ef) =>
                    ef.id == df.id ||
                    ef.title.toLowerCase().trim() ==
                        df.title.toLowerCase().trim(),
              )
              .firstOrNull;
          if (existingFeat != null) {
            df.id = existingFeat.id;
            if (existingFeat.originVersion.isNotEmpty) {
              df.originVersion = existingFeat.originVersion;
            }
            matchedExistingIds.add(existingFeat.id);
          }
          reconciledFeats.add(df);
        }
        // Preserve any prior-release features from existingBeat that the LLM omitted
        for (final ef in existingBeat.features) {
          if (!matchedExistingIds.contains(ef.id) &&
              ef.originVersion != blueprint.releaseVersionTag) {
            reconciledFeats.insert(0, ef);
          }
        }
        deltaBeat.features
          ..clear()
          ..addAll(reconciledFeats);
        mergedBeats[idx] = deltaBeat;
      } else {
        mergedBeats.add(deltaBeat);
      }
    }
    blueprint.beats = mergedBeats;
    blueprint.explicitExclusions = updatedBp.explicitExclusions;
    final reply = json['reply']?.toString().trim() ??
        'Updated the Release Plan Blueprint with your changes!';
    blueprint.lastAgentReply = reply;
    return true;
  }
}

/// Stage 3 Executor Agent: Takes the user-approved `ReleaseBlueprint` from the
/// Confirmation Gate and constructs or evolves the active Release hierarchy:
/// - Non-destructively merges existing Core Loop Beats & Features so completed
///   checkpoints from `v0.1` remain intact when re-planning or evolving to `v0.2+`.
/// - Stamps newly added Checkpoints (`FeatureStateNode`) with `releaseVersion`.
class ReleaseExecutorAgent {
  static final RegExp _bulletStripRegex = RegExp(r'^[•\-\*\s]+');
  static final RegExp _recommendedPrefixRegex = RegExp(r'^\(Recommended\)\s*');
  static final RegExp _nonAlphaNumRegex = RegExp(r'[^a-zA-Z0-9]');
  static Future<List<TierDocument>> executeBlueprint({
    required TierDocument releaseDoc,
    required ReleaseBlueprint blueprint,
    Map<String, TierDocument> existingDocuments = const {},
    void Function(String stepMessage)? onProgress,
  }) async {
    final createdOrUpdatedDocs = <TierDocument>[];
    final beatTitles = <String>[];
    final versionTag = blueprint.releaseVersionTag;

    onProgress?.call(
      'Locking in ${blueprint.releaseTitle} ($versionTag) scope & exclusions...',
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final isInitialPrototypeRelease = versionTag == 'v0.1' &&
        (releaseDoc.sections['prototypePart'] ?? '') != '2';

    final validReleaseIds = <String>{releaseDoc.id};
    final parentProjId = releaseDoc.parentId;
    if (parentProjId != null) {
      final projDoc = existingDocuments[parentProjId];
      if (projDoc != null) {
        validReleaseIds.addAll(projDoc.childrenIds);
      }
      for (final doc in existingDocuments.values) {
        if (doc.tier == TierType.release && doc.parentId == parentProjId) {
          validReleaseIds.add(doc.id);
        }
      }
    }
    final validBeatIds = <String>{};
    for (final relId in validReleaseIds) {
      final rDoc = existingDocuments[relId];
      if (rDoc != null) {
        validBeatIds.addAll(rDoc.childrenIds);
      }
    }
    for (final doc in existingDocuments.values) {
      if (doc.tier == TierType.epic &&
          doc.parentId != null &&
          validReleaseIds.contains(doc.parentId)) {
        validBeatIds.add(doc.id);
      }
    }

    final projectScopedDocs = <String, TierDocument>{};
    final existingBeatsByTitle = <String, TierDocument>{};
    final existingFeaturesByTitle = <String, TierDocument>{};
    final existingFeaturesByBeatAndTitle = <String, TierDocument>{};
    for (final doc in existingDocuments.values) {
      if (doc.tier == TierType.epic && validBeatIds.contains(doc.id)) {
        projectScopedDocs[doc.id] = doc;
        existingBeatsByTitle[doc.title.toLowerCase().trim()] = doc;
      } else if (doc.tier == TierType.feature &&
          doc.parentId != null &&
          validBeatIds.contains(doc.parentId)) {
        projectScopedDocs[doc.id] = doc;
        final normTitle = doc.title.toLowerCase().trim();
        existingFeaturesByTitle[normTitle] = doc;
        existingFeaturesByBeatAndTitle['${doc.parentId}::$normTitle'] = doc;
      }
    }

    releaseDoc.childrenIds.clear();

    for (int bIdx = 0; bIdx < blueprint.beats.length; bIdx++) {
      final beatBp = blueprint.beats[bIdx];
      final includedFeats = beatBp.includedFeatures;

      final concreteBeatTitle =
          MechanicArchetypeProfile.concreteBeatDisplayTitle(
        beatBp.title,
        beatIndex: bIdx,
      );
      final existingBeat = projectScopedDocs[beatBp.id] ??
          existingBeatsByTitle[concreteBeatTitle.toLowerCase().trim()] ??
          existingBeatsByTitle[beatBp.title.toLowerCase().trim()];
      if (includedFeats.isEmpty &&
          (isInitialPrototypeRelease || existingBeat == null)) {
        continue;
      }

      beatTitles.add(concreteBeatTitle);
      onProgress?.call(
        'Syncing Core Loop Epic ${bIdx + 1}: $concreteBeatTitle...',
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final beatId = existingBeat?.id ?? 'epic_${releaseDoc.id}_${bIdx + 1}';

      final featTitlesForBeat = includedFeats
          .map(
            (f) =>
                '• ${MechanicArchetypeProfile.concreteFeatureTitleForBeat(f.title, beatTitle: concreteBeatTitle, beatGoal: beatBp.goal, beatIndex: bIdx)}: ${f.goal}',
          )
          .join('\n');
      final deferredForBeat =
          beatBp.deferredFeatures.map((f) => '• ${f.title}').join('\n');

      final beatDoc = existingBeat ??
          TierDocument(
            id: beatId,
            title: concreteBeatTitle,
            tier: TierType.epic,
            parentId: releaseDoc.id,
          );
      final priorBeatFeatureIds = List<String>.from(beatDoc.childrenIds);
      beatDoc.title = concreteBeatTitle;
      beatDoc.parentId = releaseDoc.id;
      beatDoc.estimatedDuration = '${beatBp.totalIncludedHours}h';
      beatDoc.sections['scope'] = 'Goal: ${beatBp.goal}\n\n'
          'In Scope:\n$featTitlesForBeat\n\n'
          '${deferredForBeat.isNotEmpty ? 'Out of Scope:\n$deferredForBeat\n\n' : ''}'
          'Done When: ${beatBp.doneWhen}';
      beatDoc.childrenIds.clear();

      releaseDoc.childrenIds.add(beatDoc.id);
      createdOrUpdatedDocs.add(beatDoc);

      for (final supFeat in beatBp.features.where(
        (f) => f.lifecycle == FeatureLifecycleStatus.superseded,
      )) {
        final existingSup = projectScopedDocs[supFeat.id] ??
            existingFeaturesByTitle[supFeat.title.toLowerCase().trim()];
        if (existingSup != null) {
          existingSup.sections['lifecycle'] =
              FeatureLifecycleStatus.superseded.name;
          existingSup.sections['supersededByRelease'] = versionTag;
          createdOrUpdatedDocs.add(existingSup);
        }
      }

      final allocatedFeatIds = <String>{};
      for (int fIdx = 0; fIdx < includedFeats.length; fIdx++) {
        final featBp = includedFeats[fIdx];
        onProgress?.call(
          'Syncing Build Tasks, Tuning & Guards for "${featBp.title}"...',
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        if (featBp.supersedesFeatureTitle != null) {
          final oldDoc = existingFeaturesByTitle[
              featBp.supersedesFeatureTitle!.toLowerCase().trim()];
          if (oldDoc != null) {
            oldDoc.sections['lifecycle'] =
                FeatureLifecycleStatus.superseded.name;
            oldDoc.sections['supersededByRelease'] = versionTag;
            oldDoc.sections['supersededByFeature'] = featBp.title;
            createdOrUpdatedDocs.add(oldDoc);
          }
        }

        final concreteFeatTitle =
            MechanicArchetypeProfile.concreteFeatureTitleForBeat(
          featBp.title,
          beatTitle: beatBp.title,
          beatGoal: beatBp.goal,
          beatIndex: bIdx,
        );
        final normConcreteTitle = concreteFeatTitle.toLowerCase().trim();
        final normRawTitle = featBp.title.toLowerCase().trim();
        final candidateById = projectScopedDocs[featBp.id];
        final canMatchById = candidateById != null &&
            !allocatedFeatIds.contains(candidateById.id) &&
            (candidateById.parentId == null ||
                candidateById.parentId == beatDoc.id) &&
            (featBp.lifecycle != FeatureLifecycleStatus.newFeature ||
                candidateById.title.toLowerCase().trim() == normConcreteTitle ||
                candidateById.title.toLowerCase().trim() == normRawTitle);
        final candidateByTitle =
            existingFeaturesByBeatAndTitle['${beatDoc.id}::$normConcreteTitle'] ??
                existingFeaturesByBeatAndTitle['${beatDoc.id}::$normRawTitle'];
        final existingFeat = canMatchById
            ? candidateById
            : (candidateByTitle != null &&
                    !allocatedFeatIds.contains(candidateByTitle.id)
                ? candidateByTitle
                : null);

        String featId;
        if (existingFeat != null) {
          featId = existingFeat.id;
        } else {
          final defaultId = 'feat_${beatId}_${fIdx + 1}';
          if (!existingDocuments.containsKey(defaultId) &&
              !projectScopedDocs.containsKey(defaultId) &&
              !allocatedFeatIds.contains(defaultId)) {
            featId = defaultId;
          } else {
            final cleanVer =
                versionTag.replaceAll(_nonAlphaNumRegex, '_');
            int seq = fIdx + 1;
            String candidateId = 'feat_${beatId}_${cleanVer}_$seq';
            while (existingDocuments.containsKey(candidateId) ||
                projectScopedDocs.containsKey(candidateId) ||
                allocatedFeatIds.contains(candidateId)) {
              seq++;
              candidateId = 'feat_${beatId}_${cleanVer}_$seq';
            }
            featId = candidateId;
          }
        }
        allocatedFeatIds.add(featId);
        featBp.id = featId;

        if (!isInitialPrototypeRelease &&
            featBp.lifecycle == FeatureLifecycleStatus.stable &&
            existingFeat != null) {
          existingFeat.parentId = beatDoc.id;
          existingFeat.sections['lifecycle'] =
              FeatureLifecycleStatus.stable.name;
          existingFeat.sections.remove('supersededInVersion');
          existingFeat.sections.remove('supersededByRelease');
          existingFeat.sections['activeReleaseVersion'] = versionTag;
          existingFeat.sections['lastVerifiedVersion'] =
              existingFeat.sections['originVersion'] ?? 'v0.1';
          final stableStates =
              FeatureStateNode.getStatesForDocument(existingFeat);
          if (stableStates.isNotEmpty) {
            for (final s in stableStates) {
              for (final t in s.checklist) {
                t.completed = true;
                for (final c in t.children) {
                  c.completed = true;
                }
              }
            }
            FeatureStateNode.saveStatesToDocument(existingFeat, stableStates);
          }
          if (!beatDoc.childrenIds.contains(existingFeat.id)) {
            beatDoc.childrenIds.add(existingFeat.id);
          }
          createdOrUpdatedDocs.add(existingFeat);
          continue;
        }

        final existingStates =
            (!isInitialPrototypeRelease && existingFeat != null)
                ? FeatureStateNode.getStatesForDocument(existingFeat)
                    .where((s) => s.releaseVersion != versionTag)
                    .toList()
                : <FeatureStateNode>[];
        if (existingStates.isNotEmpty) {
          for (final s in existingStates) {
            for (final t in s.checklist) {
              t.completed = true;
              for (final c in t.children) {
                c.completed = true;
              }
            }
          }
        }

        final mergedInScope = <String>{
          if (existingFeat != null)
            ...SectionTextUtils.resolveInScope(existingFeat.sections),
          ...featBp.inScope,
        }.toList();

        final mergedOutScope = <String>{
          ...featBp.outOfScope,
        }.toList();

        final existingTuning = existingFeat != null
            ? (existingFeat.sections['tuning'] ?? '')
                .split('\n')
                .map((s) => s.replaceFirst(_bulletStripRegex, '').trim())
                .where((s) => s.isNotEmpty)
            : const Iterable<String>.empty();
        final mergedTuning = <String>{
          ...existingTuning,
          ...featBp.tuningParams,
        }.toList();

        final existingEdges = existingFeat != null
            ? (existingFeat.sections['edge_cases'] ?? '')
                .split('\n')
                .map((s) => s.replaceFirst(_bulletStripRegex, '').trim())
                .where((s) => s.isNotEmpty)
            : const Iterable<String>.empty();
        final mergedEdges = <String>{
          ...existingEdges,
          ...featBp.edgeCases,
        }.toList();

        final inScopeText = mergedInScope.map((s) => '• $s').join('\n');
        final outScopeText = mergedOutScope.map((s) => '• $s').join('\n');
        final tuningText = mergedTuning.map((t) => '• $t').join('\n');
        final edgeText = mergedEdges.map((e) => '• $e').join('\n');

        final originVer = existingFeat?.sections['originVersion'] ??
            (featBp.originVersion.isNotEmpty
                ? featBp.originVersion
                : versionTag);
        final resolvedLifecycle = existingFeat != null &&
                featBp.lifecycle == FeatureLifecycleStatus.newFeature &&
                existingStates.isNotEmpty
            ? FeatureLifecycleStatus.upgrade
            : featBp.lifecycle;

        final featDoc = existingFeat ??
            TierDocument(
              id: featId,
              title: concreteFeatTitle,
              tier: TierType.feature,
              parentId: beatDoc.id,
            );

        featDoc.title = concreteFeatTitle;
        featDoc.parentId = beatDoc.id;
        featDoc.estimatedDuration = '${featBp.activeDeltaHours}h';
        featDoc.sections['originVersion'] = originVer;
        featDoc.sections['activeReleaseVersion'] = versionTag;
        featDoc.sections['lifecycle'] = resolvedLifecycle.name;
        featDoc.sections.remove('supersededInVersion');
        featDoc.sections.remove('supersededByRelease');
        featDoc.sections['scope'] = 'Goal: ${featBp.goal}\n\n'
            'In Scope:\n$inScopeText\n\n'
            '${outScopeText.isNotEmpty ? 'Out of Scope:\n$outScopeText\n\n' : ''}'
            'Done When: ${featBp.doneWhen}';
        featDoc.sections['variables'] = tuningText;
        featDoc.sections['tuning'] = tuningText;
        featDoc.sections['edge_cases'] = edgeText;

        final stateNodes = <FeatureStateNode>[
          ...existingStates,
        ];
        final existingSameVerCpTitles = existingStates
            .where((s) => s.releaseVersion == versionTag)
            .map((s) => s.cleanStageTitle.toLowerCase().trim())
            .toSet();

        final effectiveCheckpoints = featBp.checkpoints.isNotEmpty
            ? featBp.checkpoints
            : <ProposedCheckpointBlueprint>[
                ProposedCheckpointBlueprint(
                  title: '$concreteFeatTitle ($versionTag)',
                  playtestCriteria: featBp.doneWhen.isNotEmpty
                      ? featBp.doneWhen
                      : 'Trigger $concreteFeatTitle -> verify $versionTag behavior in playtest',
                  releaseVersion: versionTag,
                  tasks: const [
                    'Actor Setup (2h)',
                    'State Logic (1h)',
                    'State Guard (1h)',
                  ],
                  coveredScope: featBp.inScope,
                  tuningParams: featBp.tuningParams,
                  edgeCases: featBp.edgeCases,
                ),
              ];

        for (int cIdx = 0; cIdx < effectiveCheckpoints.length; cIdx++) {
          final cpBp = effectiveCheckpoints[cIdx];
          if (existingSameVerCpTitles
              .contains(cpBp.title.toLowerCase().trim())) {
            continue;
          }
          final nextOrder = stateNodes.length;
          final cpNumber = nextOrder + 1;
          final effectiveTasks = cpBp.tasks.isNotEmpty
              ? cpBp.tasks
              : const [
                  'Actor Setup (2h)',
                  'State Logic (1h)',
                  'State Guard (1h)',
                ];
          final checklist = <Subtask>[
            for (int tIdx = 0; tIdx < effectiveTasks.length; tIdx++)
              Subtask(
                id: '${featId}_${versionTag}_cp${cpNumber}_t${tIdx + 1}',
                text: effectiveTasks[tIdx],
                completed: false,
              ),
          ];

          stateNodes.add(
            FeatureStateNode(
              id: '${featId}_${versionTag}_cp_$cpNumber',
              name: 'Checkpoint $cpNumber: ${cpBp.title}',
              trigger: 'Playtest: ${cpBp.playtestCriteria}',
              order: nextOrder,
              checklist: checklist,
              coveredScope: List<String>.from(cpBp.coveredScope),
              tuningParams: List<String>.from(cpBp.tuningParams),
              edgeCases: List<String>.from(cpBp.edgeCases),
              parameters: {
                'releaseVersion': versionTag,
              },
            ),
          );
        }

        FeatureStateNode.saveStatesToDocument(featDoc, stateNodes);
        if (!beatDoc.childrenIds.contains(featDoc.id)) {
          beatDoc.childrenIds.add(featDoc.id);
        }
        createdOrUpdatedDocs.add(featDoc);
      }

      if (!isInitialPrototypeRelease) {
        for (final priorFeatId in priorBeatFeatureIds) {
          if (beatDoc.childrenIds.contains(priorFeatId) ||
              allocatedFeatIds.contains(priorFeatId)) {
            continue;
          }
          final priorFeatDoc =
              projectScopedDocs[priorFeatId] ?? existingDocuments[priorFeatId];
          if (priorFeatDoc == null) continue;
          if (priorFeatDoc.sections['lifecycle'] ==
              FeatureLifecycleStatus.superseded.name) {
            continue;
          }
          final explicitlySupersededInBp = beatBp.features.any(
            (f) =>
                (f.id == priorFeatId ||
                    f.title.toLowerCase().trim() ==
                        priorFeatDoc.title.toLowerCase().trim()) &&
                f.lifecycle == FeatureLifecycleStatus.superseded,
          );
          if (explicitlySupersededInBp) continue;

          priorFeatDoc.parentId = beatDoc.id;
          priorFeatDoc.sections['lifecycle'] =
              FeatureLifecycleStatus.stable.name;
          priorFeatDoc.sections.remove('supersededInVersion');
          priorFeatDoc.sections.remove('supersededByRelease');
          priorFeatDoc.sections['activeReleaseVersion'] = versionTag;
          priorFeatDoc.sections['lastVerifiedVersion'] =
              priorFeatDoc.sections['originVersion'] ?? 'v0.1';
          final priorStates =
              FeatureStateNode.getStatesForDocument(priorFeatDoc);
          if (priorStates.isNotEmpty) {
            for (final s in priorStates) {
              for (final t in s.checklist) {
                t.completed = true;
                for (final c in t.children) {
                  c.completed = true;
                }
              }
            }
            FeatureStateNode.saveStatesToDocument(priorFeatDoc, priorStates);
          }
          beatDoc.childrenIds.add(priorFeatDoc.id);
          createdOrUpdatedDocs.add(priorFeatDoc);
        }
      }
    }

    final focusAnswer = blueprint.questions.isNotEmpty
        ? blueprint.questions.first.effectiveAnswer
            .replaceFirst(_recommendedPrefixRegex, '')
        : '';
    final effectiveGoal = focusAnswer.isNotEmpty
        ? '${blueprint.goal} (Playtest Focus: $focusAnswer)'
        : blueprint.goal;

    final inScopeBeats = beatTitles.map((t) => '• $t').join('\n');
    final outScopeItems =
        blueprint.effectiveOutOfScope.map((o) => '• $o').join('\n');

    releaseDoc.title = blueprint.releaseTitle;
    releaseDoc.sections['releaseScope'] = blueprint.preset.name;
    releaseDoc.sections['versionTag'] = versionTag;
    releaseDoc.sections['release_blueprint_json'] =
        jsonEncode(blueprint.toJson());
    releaseDoc.estimatedDuration = '${blueprint.totalIncludedHours}h';
    releaseDoc.sections['scope'] = 'Goal: $effectiveGoal\n\n'
        'In Scope:\n$inScopeBeats\n\n'
        'Out of Scope:\n$outScopeItems\n\n'
        'Done When: ${blueprint.doneWhen}';

    onProgress?.call(
      'Release ${blueprint.releaseTitle} ready for development!',
    );
    return createdOrUpdatedDocs;
  }
}
