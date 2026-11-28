import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/agents/project_concept_agent.dart';
import 'package:layers_agentic/agents/release_planner_agent.dart';
import 'package:layers_agentic/constants/tiers.dart';
import 'package:layers_agentic/main.dart';
import 'package:layers_agentic/models/agent_blueprints.dart';
import 'package:layers_agentic/models/epic_spec.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/project_pitch_screen.dart';
import 'package:layers_agentic/screens/release_workbench_screen.dart';
import 'package:layers_agentic/services/cloud_invite_deep_link_service.dart';
import 'package:layers_agentic/services/project_archive_codec.dart';
import 'package:layers_agentic/services/v01_release_seeder.dart';
import 'package:layers_agentic/utils/markdown_exporter.dart';
import 'package:layers_agentic/utils/unreal_context_builder.dart';
import 'package:layers_agentic/utils/unreal_spec_guard.dart';

void main() {
  group('Unreal Engine 5 Epic-Only Studio & Ultimate Engine CoPilot Tests', () {
    test(
      '1. UnrealArchitectureMode auto-detects Blueprint/C++ from spark and converts cleanly',
      () {
        expect(
          UnrealArchitectureMode.detectFromSpark(
            'Action RPG in C++ with UPROPERTY stats and GAS cooldowns',
          ),
          equals(UnrealArchitectureMode.cppHybrid),
        );
        expect(
          UnrealArchitectureMode.detectFromSpark(
            'Top-down mech arena shooter with claw dash armor breaks',
          ),
          equals(UnrealArchitectureMode.blueprint),
        );

        final shellbreaker = UnrealSparkPresets.byId('shellbreaker');
        expect(shellbreaker.architectureMode, equals(UnrealArchitectureMode.blueprint));
        expect(
          shellbreaker.architectureMode.pillLabel,
          equals('Blueprint-First'),
        );

        final railjack = UnrealSparkPresets.byId('railjack');
        expect(railjack.architectureMode, equals(UnrealArchitectureMode.cppHybrid));
        expect(railjack.architectureMode.pillLabel, equals('C++ & BP Hybrid'));

        final emberkeep = UnrealSparkPresets.byId('emberkeep');
        expect(emberkeep.architectureMode, equals(UnrealArchitectureMode.blueprint));
        expect(
          emberkeep.initialEpics.first.tuning.first.unit,
          equals('cm/s'),
        );

        final convertedCpp = ProjectConceptAgent.convertBlueprintArchitectureMode(
          shellbreaker,
          UnrealArchitectureMode.cppHybrid,
        );
        expect(convertedCpp.architectureMode, equals(UnrealArchitectureMode.cppHybrid));
        expect(convertedCpp.assetPolicy, contains('C++'));
        expect(convertedCpp.initialEpics.first.tuning.first.unit, equals('cm/s'));
      },
    );

    test(
      '2. UnrealSpecGuard strips off-engine leakage and formats PascalCase & IA_* keys',
      () {
        expect(
          UnrealSpecGuard.containsEngineLeakage(
            'Spawn CharacterBody3D in res://scenes/arena.tscn with 18.5 m/s InputMap',
          ),
          isTrue,
        );

        final sanitizedBp = UnrealSpecGuard.sanitizeLine(
          'Attach CharacterBody3D to SpringArm3D and test in res://scenes/arena_proto.tscn at 18.5 m/s and 5.5 m range',
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(
          UnrealSpecGuard.containsEngineLeakage(sanitizedBp),
          isFalse,
        );
        expect(sanitizedBp, contains('ACharacter'));
        expect(sanitizedBp, contains('USpringArmComponent'));
        expect(sanitizedBp, contains('/Game/Maps/Lvl_ArenaProto.umap'));
        expect(sanitizedBp, contains('1850 cm/s'));
        expect(sanitizedBp, contains('550 cm'));

        final sanitizedPx = UnrealSpecGuard.sanitizeLine(
          'Move CharacterBody2D 320 px/s in res://scenes/forest_arena.tscn with GPUParticles2D',
          mode: UnrealArchitectureMode.cppHybrid,
        );
        expect(sanitizedPx, contains('ACharacter'));
        expect(sanitizedPx, contains('800 cm/s'));
        expect(sanitizedPx, contains('/Game/Maps/Lvl_ForestArena.umap'));
        expect(sanitizedPx, contains('Niagara'));

        expect(
          UnrealSpecGuard.sanitizeTuningKey('bAllowAirDash'),
          equals('AllowAirDash'),
        );
        expect(
          UnrealSpecGuard.sanitizeTuningKey('max_walk_speed'),
          equals('MaxWalkSpeed'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('MoveSpeed', 'm/s'),
          equals('cm/s'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('MoveSpeed', 'px/s'),
          equals('cm/s'),
        );
      },
    );

    test(
      '3. UnrealContextBuilder renders CoPilot GDD, Epic Architecture Brief & [FIX] revision switch',
      () {
        final spec3d = UnrealSparkPresets.byId('shellbreaker');
        final e01 = spec3d.initialEpics.first;
        final full = UnrealContextBuilder.buildCoPilotGddMarkdown(
          rootSpec: spec3d,
          epicsByReleaseLabel: {'v0.1 · Prototype': spec3d.initialEpics},
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(full, contains('# PROJECT GDD · SHELLBREAKER'));
        expect(full, contains('Blueprint-First'));
        expect(full, contains('/Game/Maps/Lvl_ShellbreakerProto.umap'));

        e01.features.first.fixes.add(
          EpicPieFix(
            id: 'fx1',
            text: 'Dash stops short at wall corner',
            resolved: false,
          ),
        );
        final fixCtx = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: spec3d,
          epic: e01,
          feature: e01.features.first,
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(fixCtx, contains('@FIX_NOW:'));
        expect(fixCtx, contains('[UE5_COPILOT TASK=FIX'));
        expect(fixCtx, contains('Dash stops short at wall corner'));
      },
    );

    test(
      '4. UnrealContextBuilder renders deterministic Blueprint-First, C++ & BP Hybrid, v0.2 Deltas & [FIX] prompts cleanly',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final root = wb.conceptDraft!;
        final e01 = root.initialEpics[0].deepCopy();
        final e02 = root.initialEpics[1].deepCopy();

        // Scenario A: v0.1 + [FIX] revision pass in C++ & BP Hybrid mode
        e02.features.first.fixes.add(
          EpicPieFix(id: 'fx_a', text: 'Recoil pushes off floor', resolved: false),
        );
        final dartA = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: root,
          epic: e02,
          feature: e02.features.first,
          mode: UnrealArchitectureMode.cppHybrid,
        );
        expect(dartA, contains('[UE5_COPILOT TASK=FIX'));
        expect(dartA, contains('C++ & BP Hybrid'));
        expect(dartA, contains('Recoil pushes off floor'));

        // Scenario B: emberkeep converted cleanly to cm/s with 0 px/m leakage
        final ekRoot = UnrealSparkPresets.byId('emberkeep');
        final eEk = ekRoot.initialEpics.first.deepCopy();
        final dartB = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: ekRoot,
          epic: eEk,
          feature: eEk.features.first,
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(dartB, contains('cm/s'));
        expect(dartB, isNot(contains(' m/s')));
        expect(dartB, isNot(contains(' px/s')));

        // Scenario C: v0.2 upgraded Epic brief with baselineSummary + upgradeDeltas
        final v02Epic = e01.deepCopy()
          ..releaseVersion = 'v0.2'
          ..lifecycle = EpicLifecycle.upgrading
          ..baselineSummary = ['v0.1 Walk & Claw Dash checked']
          ..upgradeDeltas = ['Chain second dash on armor break'];
        final dartC = UnrealContextBuilder.buildEpicArchitectureContext(
          rootSpec: root,
          epic: v02Epic,
          releaseVersion: 'v0.2',
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(dartC, contains('REL=v0.2'));
        expect(dartC, contains('Chain second dash on armor break'));
      },
    );

    testWidgets(
      '5. Stage 1 UI: Blueprint-First | C++ & BP Hybrid toggle, C++ auto-detect on Spark, Clean Spec Only & Approve -> Stage 2',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wb = WorkbenchProvider(enableAutoLoad: false);
        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        expect(find.byType(ProjectPitchScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_mode_blueprint')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_mode_cpp_hybrid')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_tab_raw')), findsNothing);
        expect(find.text('Copy Context'), findsNothing);

        await tester.enterText(
          find.byKey(const ValueKey('spark_prompt_input')),
          'Third-person C++ action skirmisher with UPROPERTY torch axe cleave',
        );
        await tester.tap(find.byKey(const ValueKey('draft_spark_btn')));
        await tester.pumpAndSettle();

        expect(
          wb.unrealArchitectureMode,
          equals(UnrealArchitectureMode.cppHybrid),
        );
        expect(find.byKey(const ValueKey('stage1_tab_raw')), findsNothing);
        expect(find.text('Copy Context'), findsNothing);
        expect(
          wb.activeRootUnrealMarkdown,
          contains('# ROOT_UNREAL_CONTEXT'),
        );

        // Toggle explicitly back to Blueprint-First and verify CoPilot context renders cleanly
        await tester.tap(find.byKey(const ValueKey('stage1_mode_blueprint')));
        await tester.pumpAndSettle();
        expect(
          wb.unrealArchitectureMode,
          equals(UnrealArchitectureMode.blueprint),
        );
        expect(
          wb.activeRootUnrealMarkdown,
          contains('Unreal Engine 5 Blueprint-First'),
        );

        await tester.tap(find.byKey(const ValueKey('approve_launch_workbench_btn')));
        await tester.pumpAndSettle();

        expect(wb.isInspectingReleaseSpec, isTrue);
        await tester.tap(find.byKey(const ValueKey('release_primary_action_btn')));
        await tester.pumpAndSettle();

        expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('stage2_tab_raw')), findsNothing);
        expect(find.byKey(const ValueKey('copy_copilot_prompt_btn')), findsOneWidget);
      },
    );

    testWidgets(
      '6. Stage 2 UI: Live Feature @export tuning edit, Flag [FIX] revision switch, and Pass Feature advance',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();

        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        final e01 = wb.selectedEpicSpec!;
        expect(e01.code, equals('E01'));
        expect(wb.selectedFeatureSpec?.code, equals('F02'));

        // Live Feature tuning edit updates Build Prompt immediately
        await tester.ensureVisible(
          find.byKey(const ValueKey('tuning_input_sb_f02_0')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('tuning_input_sb_f02_0')),
          '850',
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          wb.selectedBuildPrompt,
          contains('DashDistance = 850 cm'),
        );

        // Flag [FIX] switches Feature Build Prompt to FOCUSED [FIX] PASS
        final flagInput = find.byKey(const ValueKey('flag_fix_input'));
        await tester.ensureVisible(flagInput);
        await tester.enterText(
          flagInput,
          'Claw dash overshoots pillar edge',
        );
        final flagBtn = find.byKey(const ValueKey('flag_fix_btn'));
        await tester.ensureVisible(flagBtn);
        await tester.tap(flagBtn);
        await tester.pumpAndSettle();

        expect(wb.selectedFeatureSpec!.openFixesCount, equals(1));
        expect(
          wb.selectedBuildPrompt,
          contains('[UE5_COPILOT TASK=FIX TARGET=F02'),
        );

        // Resolve [FIX], check Playtest Gate, and Pass Feature -> advances to E02 / F03
        final fxId = wb.selectedFeatureSpec!.fixes.first.id;
        await tester.ensureVisible(find.byKey(ValueKey('resolve_fix_$fxId')));
        await tester.tap(find.byKey(ValueKey('resolve_fix_$fxId')));
        await tester.pumpAndSettle();

        final chkFinder = find.byKey(const ValueKey('feature_check_sb_f02_c1'));
        await tester.ensureVisible(chkFinder);
        await tester.tap(chkFinder);
        await tester.pumpAndSettle();

        final passBtn = find.byKey(const ValueKey('pass_feature_btn'));
        await tester.ensureVisible(passBtn);
        await tester.tap(passBtn);
        await tester.pumpAndSettle();
        expect(wb.selectedEpicSpec!.code, equals('E02'));
        expect(wb.selectedFeatureSpec?.code, equals('F03'));
      },
    );

    test(
      '7. Progressive v0.2 deltas, reopenEpic preserves v0.1 baseline checks & Stage 1 lineage re-sync',
      () async {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final rel1 = wb.approveRootSpecAndLaunchWorkbench()!;

        for (final ep in wb.epicsForRelease(rel1)) {
          wb.passActiveEpic(ep.id);
        }
        expect(wb.isActiveReleaseComplete, isTrue);

        // Create v0.2 progressive upgrade atop locked E01
        await wb.openProgressiveReleaseCopilot();
        final v02Id = wb.commitProgressiveReleaseDraft()!;
        final v02Epics = wb.epicsForRelease(v02Id);
        final upgraded = v02Epics.firstWhere((e) => e.upgradeDeltas.isNotEmpty);

        wb.passActiveEpic(upgraded.id);
        expect(wb.epicsForRelease(v02Id).firstWhere((e) => e.id == upgraded.id).isPassed, isTrue);

        wb.reopenEpic(upgraded.id);
        final reopened = wb.epicsForRelease(v02Id).firstWhere((e) => e.id == upgraded.id);
        expect(reopened.isPassed, isFalse);
        expect(reopened.lifecycle, equals(EpicLifecycle.upgrading));
        expect(reopened.checks.first.passed, isTrue);
        expect(reopened.checks.last.passed, isFalse);
      },
    );

    test(
      '8. duplicateProject & importProjectFromJson clear collaborator metadata and remap embedded IDs',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('emberkeep');
        wb.approveRootSpecAndLaunchWorkbench();

        wb.activeProject!.sections['collaborators_json'] =
            jsonEncode([{'email': 'ally@studio.io', 'role': 'editor'}]);
        wb.switchProject(wb.activeProjectId!);
        expect(wb.collaboratorsForProject(wb.activeProjectId), isNotEmpty);

        final exported = wb.exportProjectToJson();
        final dupId = wb.duplicateProject(wb.activeProjectId!)!;
        expect(wb.activeProjectId, equals(dupId));
        expect(wb.collaboratorsForProject(dupId), isEmpty);

        final impId = wb.importProjectFromJson(exported)!;
        expect(wb.activeProjectId, equals(impId));
        expect(wb.collaboratorsForProject(impId), isEmpty);
      },
    );

    test(
      '11. TierType.feature enforces 4-tier hierarchy (Project -> Release -> Epic -> Feature, zero Tasks/Steps)',
      () {
        expect(
          TierType.values,
          equals([
            TierType.project,
            TierType.release,
            TierType.epic,
            TierType.feature,
          ]),
        );
        expect(TierType.feature.level, equals(4));
        expect(TierType.feature.shortTag, equals('FEAT'));
        expect(TierType.feature.letterBadge, equals('F'));
        expect(TierType.feature.displayName, equals('Feature'));
        expect(TierType.feature.pluralDisplayName, equals('Features'));
        expect(TierType.feature.parentTier, equals(TierType.epic));
        expect(TierType.feature.nextChildTier, isNull);
        expect(TierType.epic.nextChildTier, equals(TierType.feature));
        expect(TierType.fromString('feature'), equals(TierType.feature));
        expect(TierType.fromString('FEAT'), equals(TierType.feature));
        expect(
          TierDocument.isLegacyIgnoredTier({'tier': 'feature'}),
          isTrue,
        );
      },
    );

    test(
      '12. FeatureSpec & EpicSpec 4-tier domain fields round-trip cleanly with release-aware rollups',
      () {
        final f01 = FeatureSpec(
          id: 'f01',
          code: 'F01',
          title: '8-Way Walk & Iso Camera',
          introducedIn: 'v0.1',
          sliceTime: '45 min',
          status: FeatureStatus.passed,
          goal: 'Implement 8-way camera-relative walk and smooth Camera3D follow.',
          inScope: ['WASD planar locomotion', '55 deg camera follow lead'],
          doneWhen: ['Hold W+D against angled wall -> Mech glides cleanly'],
          controls: [
            EpicControlBinding(
              action: 'move_8way',
              trigger: 'W A S D',
              rule: 'Continuous planar XZ vector',
            ),
          ],
          tuning: [
            EpicTuningParam(key: 'move_speed', value: '9.5', unit: 'm/s'),
          ],
          cues: ['Hydraulic step thump every 0.32 s'],
          checks: [
            EpicPieCheck(
              id: 'c1',
              text: 'Hold W+D -> Mech glides smoothly',
              passed: true,
            ),
          ],
        );

        final f02 = FeatureSpec(
          id: 'f02',
          code: 'F02',
          title: 'Armored Claw Dash',
          introducedIn: 'v0.1',
          sliceTime: '60 min',
          status: FeatureStatus.active,
          goal: 'Forward 4 m commitment dash with i-frames and cyan ribbon.',
          releaseDelta: '+ Reset dash cooldown when cracking enemy shell',
          releaseDeltaChecks: [
            EpicPieCheck(
              id: 'dc1',
              text: 'Crack shell then tap Space -> Dash chains cleanly',
            ),
          ],
          fixes: [
            EpicPieFix(
              id: 'fx1',
              text: 'Dash clips southeast pillar bevel',
              resolved: false,
            ),
          ],
          checks: [
            EpicPieCheck(
              id: 'c2',
              text: 'Tap Space -> Mech lunges 4.0 m',
              passed: true,
            ),
          ],
        );

        final f03 = FeatureSpec(
          id: 'f03',
          code: 'F03',
          title: 'Chain Dash on Shell Break',
          introducedIn: 'v0.2',
          sliceTime: '45 min',
          status: FeatureStatus.queued,
          goal: 'Refund cooldown on shell break for up to 3 consecutive dashes.',
        );

        final epic = EpicSpec(
          id: 'epic_e01',
          code: 'E01',
          title: 'Player Movement & Camera',
          goal: 'Own mech locomotion, dash commitments, and follow camera rig.',
          inScope: ['8-way walk', 'Horizontal claw dash'],
          doneWhen: ['All E01 Features pass Playtest Gate'],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/player_mech.tscn',
              role: 'CharacterBody3D root & hitbox',
            ),
            EpicSceneOwnership(
              path: 'res://scripts/player_mech.gd',
              role: 'Movement state loop & @export vars',
            ),
          ],
          stateFlow: ['Idle', 'Walk', 'ClawDash', 'Recovery'],
          interruptRules: ['ClawDash locks normal walk accel for 0.18 s'],
          outOfScope: ['No stamina bar in v0.1'],
          features: [f01, f02, f03],
        );

        expect(epic.sceneOwnership.length, equals(2));
        expect(epic.stateFlow, equals(['Idle', 'Walk', 'ClawDash', 'Recovery']));
        expect(epic.interruptRules, hasLength(1));
        expect(epic.featuresForRelease('v0.1', ['v0.1', 'v0.2']), hasLength(2));
        expect(epic.featuresForRelease('v0.2', ['v0.1', 'v0.2']), hasLength(3));
        expect(
          epic.passedFeaturesCountForRelease('v0.1', ['v0.1', 'v0.2']),
          equals(1),
        );
        expect(f01.isLockedBaselineInRelease('v0.2'), isTrue);
        expect(f02.isLockedBaselineInRelease('v0.2'), isFalse);
        expect(epic.totalOpenFeatureFixes(), equals(1));
        expect(f01.executionModeLabel, equals('FULL FEATURE BUILD'));
        expect(f02.executionModeLabel, equals('FOCUSED [FIX] PASS (1 Open)'));
        expect(
          f02.effectiveChecksForRelease('v0.2'),
          hasLength(2),
        );

        final copied = epic.deepCopy();
        copied.features.first.tuning.first.value = '12.0';
        expect(epic.features.first.tuning.first.value, equals('9.5'));

        final roundTripDoc = epic.toTierDocument(
          docId: epic.id,
          parentReleaseId: 'rel_v01',
        );
        final restored = EpicSpec.fromDocument(roundTripDoc);
        expect(restored.sceneOwnership.first.path, equals('res://scenes/player_mech.tscn'));
        expect(restored.inScope, equals(['8-way walk', 'Horizontal claw dash']));
        expect(restored.doneWhen, equals(['All E01 Features pass Playtest Gate']));
        expect(restored.features, hasLength(3));
        expect(restored.features[1].releaseDelta, contains('Reset dash cooldown'));
        expect(restored.features[1].fixes.single.text, contains('pillar bevel'));
        expect(restored.features[2].introducedIn, equals('v0.2'));
      },
    );

    test(
      '13. Legacy EpicSpec JSON without features key migrates into 1 F01 slice and preserves explicit empty features list',
      () {
        final legacyJson = <String, dynamic>{
          'id': 'legacy_e01',
          'code': 'E01',
          'title': 'Claw Dash Movement',
          'releaseVersion': 'v0.1',
          'lifecycle': 'active',
          'goal': 'Dash 4 m with cyan trail and hit cooldown.',
          'links': ['res://scenes/player_mech.tscn', 'HUD cooldown indicator'],
          'outOfScope': ['No air dash'],
          'controls': [
            {'action': 'claw_dash', 'trigger': 'Space', 'rule': '0.65 s cooldown'},
          ],
          'states': ['Idle', 'ClawDash'],
          'interrupts': ['Wall impact ends dash'],
          'tuning': [
            {'key': 'dash_speed', 'value': '22.0', 'unit': 'm/s'},
          ],
          'feedback': ['Cyan ribbon trail emits for 0.2 s'],
          'levelStaging': 'res://scenes/arena_proto.tscn — 24 m test pit',
          'checks': [
            {'id': 'chk_1', 'text': 'Press Space -> Mech dashes 4 m', 'passed': true},
          ],
          'fixes': [
            {'id': 'fix_1', 'text': 'Dash misses corner trigger', 'resolved': false},
          ],
        };

        final legacyDoc = TierDocument(
          id: 'legacy_e01',
          title: 'Claw Dash Movement',
          tier: TierType.epic,
          sections: {
            'code': 'E01',
            'epic_spec_json': jsonEncode(legacyJson),
          },
        );

        final migrated = EpicSpec.fromDocument(legacyDoc);
        expect(migrated.features, hasLength(1));
        final f01 = migrated.features.single;
        expect(f01.code, equals('F01'));
        expect(f01.title, equals('Claw Dash Movement'));
        expect(f01.introducedIn, equals('v0.1'));
        expect(f01.status, equals(FeatureStatus.active));
        expect(f01.controls.single.action, equals('claw_dash'));
        expect(f01.tuning.single.key, equals('dash_speed'));
        expect(f01.cues, equals(['Cyan ribbon trail emits for 0.2 s']));
        expect(f01.checks.single.passed, isTrue);
        expect(f01.fixes.single.text, equals('Dash misses corner trigger'));
        expect(
          migrated.sceneOwnership.map((o) => o.path),
          containsAll([
            '/Game/Blueprints/BP_PlayerMech',
            '/Game/Maps/Lvl_ArenaProto.umap',
          ]),
        );
        expect(migrated.stateFlow, equals(['Idle', 'ClawDash']));
        expect(migrated.interruptRules, equals(['Wall impact ends dash']));

        // Explicit empty features list must NOT auto-synthesize F01
        final emptyFeatJson = Map<String, dynamic>.from(legacyJson)
          ..['features'] = <dynamic>[];
        final emptyParsed = EpicSpec.fromJson(emptyFeatJson);
        expect(emptyParsed.features, isEmpty);
      },
    );

    test(
      '14. UnrealContextBuilder.buildCoPilotFeaturePrompt & buildEpicArchitectureContext bundle UE5 context, v0.2 deltas & [FIX] mode',
      () {
        final spec3d = UnrealSparkPresets.byId('shellbreaker');
        final f01 = FeatureSpec(
          id: 'f01',
          code: 'F01',
          title: '8-Way Walk & Iso Camera',
          introducedIn: 'v0.1',
          sliceTime: '45 min',
          status: FeatureStatus.passed,
          goal: 'Implement camera-relative 8-way walk and follow Camera3D.',
          checks: [
            EpicPieCheck(
              id: 'c1',
              text: 'Hold W+D -> Mech slides smoothly',
              passed: true,
            ),
          ],
        );
        final f02 = FeatureSpec(
          id: 'f02',
          code: 'F02',
          title: 'Armored Claw Dash',
          introducedIn: 'v0.1',
          sliceTime: '60 min',
          status: FeatureStatus.active,
          goal: 'Forward 4 m commitment dash with i-frames and cyan trail.',
          inScope: ['Space input buffer', '4 m horizontal lunge'],
          doneWhen: ['Tap Space -> Mech crosses 4 m cleanly'],
          releaseDelta: '+ Reset dash cooldown when breaking cracked shell',
          releaseDeltaChecks: [
            EpicPieCheck(
              id: 'dc1',
              text: 'Break shell then tap Space -> Second dash chains cleanly',
            ),
          ],
          controls: [
            EpicControlBinding(
              action: 'claw_dash',
              trigger: 'Space / L-Trigger',
              rule: '0.65 s cooldown',
            ),
          ],
          tuning: [
            EpicTuningParam(key: 'dash_distance_m', value: '4.0', unit: 'm'),
            EpicTuningParam(key: 'max_chains', value: '3', unit: 'count'),
          ],
          cues: ['Cyan ribbon trail fades over 0.22 s'],
          checks: [
            EpicPieCheck(
              id: 'c2_1',
              text: 'Tap Space -> Mech crosses 4 m',
              passed: true,
            ),
            EpicPieCheck(
              id: 'c2_2',
              text: 'Collide with cracked shell -> Enemy staggers 1.5 m',
              passed: false,
            ),
          ],
        );
        final f03 = FeatureSpec(
          id: 'f03',
          code: 'F03',
          title: 'Chain Dash on Shell Break',
          introducedIn: 'v0.2',
          sliceTime: '45 min',
          status: FeatureStatus.queued,
          goal: 'Refund cooldown on shell break.',
        );

        final e01 = EpicSpec(
          id: 'e01',
          code: 'E01',
          title: 'Player Movement & Camera',
          goal: 'Own mech locomotion, dash commitments, and follow camera rig.',
          inScope: ['8-way walk', 'Claw dash commitments'],
          doneWhen: ['All E01 Features pass Playtest Gate'],
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/player_mech.tscn',
              role: 'CharacterBody3D + CameraRig',
            ),
          ],
          stateFlow: ['Idle', 'Walk', 'ClawDash', 'Recovery'],
          interruptRules: ['ClawDash locks walk accel for 0.18 s'],
          outOfScope: ['No stamina bar in v0.1'],
          features: [f01, f02, f03],
        );

        final ctxV01 = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: spec3d,
          epic: e01,
          feature: f02,
          releaseVersion: 'v0.1',
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(
          ctxV01,
          contains('[UE5_COPILOT TASK=BUILD TARGET=F02 · Armored Claw Dash REL=v0.1'),
        );
        expect(
          ctxV01,
          contains('@EPIC E01(Player Movement & Camera):'),
        );
        expect(ctxV01, contains('/Game/Blueprints/BP_PlayerMech'));
        expect(ctxV01, contains('Idle -> Walk -> ClawDash -> Recovery'));
        expect(ctxV01, contains('@CUTS: !stamina bar in v0.1'));
        expect(ctxV01, contains('KEEP=[F01]'));
        expect(ctxV01, contains('TARGET=[F02]'));
        expect(ctxV01, contains('IA_ClawDash(Space / L-Trigger) -> 0.65 s cooldown'));
        expect(ctxV01, contains('float DashDistanceM = 400 cm'));
        expect(ctxV01, contains('int32 MaxChains = 3 count'));
        expect(ctxV01, contains('@PIE_GATE:'));
        expect(ctxV01, contains('[x] Tap Space -> Mech crosses 400 cm'));
        expect(
          ctxV01,
          contains('[ ] Collide with cracked shell -> Enemy staggers 150 cm'),
        );

        // v0.2 delta & delta check
        final ctxV02 = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: spec3d,
          epic: e01,
          feature: f02,
          releaseVersion: 'v0.2',
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(
          ctxV02,
          contains('[UE5_COPILOT TASK=DELTA TARGET=F02'),
        );
        expect(ctxV02, contains('@DELTA v0.2:'));
        expect(ctxV02, contains('Reset dash cooldown when breaking cracked shell'));
        expect(
          ctxV02,
          contains('Break shell then tap Space -> Second dash chains cleanly'),
        );

        // [FIX] revision mode switch
        f02.fixes.add(
          EpicPieFix(id: 'fx_dash', text: 'Dash clips pillar edge'),
        );
        final ctxFix = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: spec3d,
          epic: e01,
          feature: f02,
          releaseVersion: 'v0.1',
          mode: UnrealArchitectureMode.cppHybrid,
        );
        expect(ctxFix, contains('[UE5_COPILOT TASK=FIX TARGET=F02'));
        expect(
          ctxFix,
          contains('@VARS [UPROPERTY(EditAnywhere, BlueprintReadWrite)]: float DashDistanceM = 400 cm'),
        );
        expect(ctxFix, contains('@FIX_NOW:'));
        expect(ctxFix, contains('Dash clips pillar edge'));

        // Epic domain architecture brief (v0.1 vs v0.2 rollups)
        final archV02 = UnrealContextBuilder.buildEpicArchitectureContext(
          rootSpec: spec3d,
          epic: e01,
          releaseVersion: 'v0.2',
        );
        expect(
          archV02,
          contains('[UE5_COPILOT TASK=EPIC_BRIEF TARGET=E01 · Player Movement & Camera REL=v0.2'),
        );
        expect(archV02, contains('1/3 PASS | 1 FIX'));
        expect(archV02, contains('v0.1 ✓ BASELINE'));
        expect(archV02, contains('+v0.2 NEW'));

        // C++ Hybrid Feature context check
        final specHybrid = UnrealSparkPresets.byId('emberkeep');
        final fHybrid = FeatureSpec(
          id: 'f2d',
          code: 'F01',
          title: 'Roll Dash',
          goal: 'Move 128 px across spike floor.',
          tuning: [EpicTuningParam(key: 'dash_speed_px', value: '480', unit: 'px/s')],
        );
        final ctxHybrid = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: specHybrid,
          epic: e01,
          feature: fHybrid,
          releaseVersion: 'v0.1',
          mode: UnrealArchitectureMode.cppHybrid,
        );
        expect(ctxHybrid, contains('C++ & BP Hybrid'));
        expect(ctxHybrid, contains('float DashSpeedPx = 1200 cm/s'));

        // buildFullProjectSpecMarkdown includes Feature slices when present
        final fullMd = UnrealContextBuilder.buildFullProjectSpecMarkdown(
          rootSpec: spec3d,
          epicsByReleaseLabel: {
            'v0.1 · Arena Prototype': [e01],
          },
        );
        expect(fullMd, contains('UE5 EPIC ARCHITECTURE BRIEF'));
        expect(fullMd, contains('F02 · Armored Claw Dash'));
      },
    );

    test(
      '15. UnrealSpecGuard.sanitizeFeatureSpec & markdown_exporter filename helpers strip leakage cleanly',
      () {
        final dirtyFeat = FeatureSpec(
          id: 'dirty_f01',
          code: '',
          title: 'Spawn CharacterBody3D in res://scenes/arena_proto.tscn',
          goal: 'Leverage unified speed 18.5 m/s in CharacterBody3D arena.',
          inScope: ['Use InputMap claw_dash via CanvasLayer HUD'],
          doneWhen: ['Validate dash hits CharacterBody3D within 4.5 m'],
          releaseDelta: '+ Seamlessly deliver 3.0 m boost',
          controls: [
            EpicControlBinding(
              action: 'claw_dash',
              trigger: 'Space',
              rule: 'Uses InputMap cooldown',
            ),
          ],
          tuning: [
            EpicTuningParam(key: 'bAllowAirDash', value: 'true', unit: 'boolean'),
            EpicTuningParam(key: 'max_dash_dist', value: '4.5', unit: 'm'),
          ],
          cues: ['Emit GPUParticles3D trail seamlessly'],
          checks: [
            EpicPieCheck(
              id: 'c1',
              text: 'Press claw_dash -> Travel 4.5 m in Playtest',
            ),
          ],
        );

        final clean = UnrealSpecGuard.sanitizeFeatureSpec(
          dirtyFeat,
          mode: UnrealArchitectureMode.blueprint,
          forceCode: 'F02',
        );
        expect(clean.code, equals('F02'));
        expect(UnrealSpecGuard.containsEngineLeakage(clean.title), isFalse);
        expect(UnrealSpecGuard.containsEngineLeakage(clean.goal), isFalse);
        expect(clean.controls.single.action, equals('IA_ClawDash'));
        expect(clean.tuning[0].key, equals('AllowAirDash'));
        expect(clean.tuning[0].unit, equals('bool'));
        expect(clean.tuning[1].key, equals('MaxDashDist'));
        expect(clean.tuning[1].value, equals('450'));
        expect(clean.tuning[1].unit, equals('cm'));
        expect(clean.cues.single, contains('Niagara'));

        final parentEpic = EpicSpec(
          id: 'e_dirty',
          code: 'E01',
          title: 'Player Movement',
          goal: 'Move CharacterBody3D',
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/player_mech.tscn',
              role: 'CharacterBody3D root',
            ),
          ],
          features: [dirtyFeat],
        );
        final cleanEpic = UnrealSpecGuard.sanitizeEpicSpec(
          parentEpic,
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(cleanEpic.features.single.code, equals('F01'));
        expect(cleanEpic.features.single.tuning[1].unit, equals('cm'));
        expect(
          UnrealSpecGuard.containsEngineLeakage(
            cleanEpic.sceneOwnership.single.role,
          ),
          isFalse,
        );

        expect(
          buildProjectSpecFilename('EMBERKEEP'),
          equals('emberkeep_project_spec.md'),
        );
        expect(
          buildCoPilotGddFilename('Shellbreaker'),
          equals('shellbreaker_copilot_gdd.md'),
        );
      },
    );

    test(
      '16. Starter presets (shellbreaker, railjack, emberkeep), mode conversion & offline Spark synthesis seed Large-Domain Epics with v0.1 Features',
      () async {
        for (final presetId in ['shellbreaker', 'railjack', 'emberkeep']) {
          final bp = UnrealSparkPresets.byId(presetId);
          expect(bp.initialEpics, isNotEmpty, reason: presetId);
          for (final epic in bp.initialEpics) {
            expect(epic.sceneOwnership, isNotEmpty, reason: '$presetId ${epic.code}');
            expect(epic.inScope, isNotEmpty, reason: '$presetId ${epic.code}');
            expect(epic.doneWhen, isNotEmpty, reason: '$presetId ${epic.code}');
            expect(
              epic.features.length,
              inInclusiveRange(2, 3),
              reason: '$presetId ${epic.code}',
            );
            for (final feat in epic.features) {
              expect(feat.introducedIn, equals('v0.1'));
              expect(feat.title.trim(), isNotEmpty);
              expect(feat.goal.trim(), isNotEmpty);
              expect(feat.tuning, isNotEmpty);
              expect(feat.checks, isNotEmpty);
            }
          }
        }

        final sb = UnrealSparkPresets.byId('shellbreaker');
        expect(
          sb.initialEpics.first.features.first.tuning.first.unit,
          equals('cm/s'),
        );
        expect(sb.v02NewFeaturesByLineageKey['e01'], isNotEmpty);
        expect(
          sb.v02NewFeaturesByLineageKey['e01']!.first.introducedIn,
          equals('v0.2'),
        );

        final ek = UnrealSparkPresets.byId('emberkeep');
        expect(
          ek.initialEpics.first.features.first.tuning.first.unit,
          equals('cm/s'),
        );
        expect(ek.v02NewFeaturesByLineageKey['e01'], isNotEmpty);

        final sbAsCpp = ProjectConceptAgent.convertBlueprintArchitectureMode(
          sb,
          UnrealArchitectureMode.cppHybrid,
        );
        expect(
          sbAsCpp.initialEpics.first.features.first.tuning.first.unit,
          equals('cm/s'),
        );
        expect(
          sbAsCpp.v02NewFeaturesByLineageKey['e01']!.first.tuning
              .any((t) => t.unit == 'cm' || t.unit == 'cm/s'),
          isTrue,
        );

        final offCpp = await ProjectConceptAgent.draftSpecFromSpark(
          sparkPrompt: 'C++ hybrid grapple dungeon crawler with lantern dashes',
          apiKey: '',
        );
        expect(offCpp.architectureMode, equals(UnrealArchitectureMode.cppHybrid));
        for (final epic in offCpp.initialEpics) {
          expect(epic.sceneOwnership, isNotEmpty);
          expect(epic.features.length, greaterThanOrEqualTo(2));
          expect(
            epic.features.first.tuning.any((t) => t.unit == 'cm/s' || t.unit == 'cm'),
            isTrue,
          );
        }
      },
    );

    test(
      '17. ReleasePlannerAgent proposes v0.2+ [+NEW] Features and [+DELTA] upgrades inside existing Epics (offline & mocked Gemini)',
      () async {
        final sb = UnrealSparkPresets.byId('shellbreaker');
        final offlineDraft = await ReleasePlannerAgent.proposeNextReleaseCopilot(
          rootSpec: sb,
          currentEpics: sb.initialEpics,
          targetVersion: 'v0.2',
          apiKey: '',
        );
        expect(offlineDraft.candidateNewFeaturesByLineageKey['e01'], isNotEmpty);
        expect(
          offlineDraft.candidateNewFeaturesByLineageKey['e01']!.first.introducedIn,
          equals('v0.2'),
        );
        expect(offlineDraft.upgradesByLineageKey['e01'], isNotEmpty);
        expect(
          offlineDraft.upgradesByLineageKey['e01']!.first.targetFeatureCode,
          isNotNull,
        );
        expect(offlineDraft.candidateNewEpics.first.features, isNotEmpty);

        final prevMock = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, model) async {
          return <String, dynamic>{
            'presets': [
              {
                'id': 'focused',
                'label': 'Dash Chain Focus',
                'desc': 'Add chain dash inside E01 without duplicating E01.',
                'upgrades': ['up_f02'],
                'newEpics': <String>[],
              },
            ],
            'upgrades': [
              {
                'lineageKey': 'e01',
                'options': [
                  {
                    'id': 'up_f02',
                    'targetFeatureCode': 'F02',
                    'text': '+Emit shockwave ring on dash stop',
                    'chosen': true,
                  },
                ],
              },
            ],
            'newFeatures': [
              {
                'lineageKey': 'e01',
                'features': [
                  {
                    'id': 'f03_chain',
                    'code': 'F03',
                    'title': 'Chain Dash on Break',
                    'sliceTime': '45 min',
                    'goal': 'Refund dash cooldown after breaking shell armor.',
                    'tuning': [
                      {'key': 'chain_window_s', 'value': '0.35', 'unit': 's'},
                    ],
                    'checks': [
                      {'text': 'Break shell -> dash resets cleanly'},
                    ],
                  },
                ],
              },
            ],
            'newEpics': <dynamic>[],
          };
        };

        try {
          final aiDraft = await ReleasePlannerAgent.proposeNextReleaseCopilot(
            rootSpec: sb,
            currentEpics: sb.initialEpics,
            targetVersion: 'v0.2',
            apiKey: 'test-key-1234',
          );
          expect(aiDraft.candidateNewEpics, isEmpty);
          expect(aiDraft.candidateNewFeaturesByLineageKey['e01'], hasLength(1));
          final addedFeat =
              aiDraft.candidateNewFeaturesByLineageKey['e01']!.single;
          expect(addedFeat.introducedIn, equals('v0.2'));
          expect(addedFeat.title, equals('Chain Dash on Break'));
          expect(
            aiDraft.upgradesByLineageKey['e01']!.single.targetFeatureCode,
            equals('F02'),
          );
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
        }
      },
    );

    test(
      '18. Stage 1 Spark & Refiner core: architecture mode detection, strict preset match, vague-spark forks, real AI error surfacing, scoped Blueprint/C++ patch conversion, locomotion sync & genre-aware fallback',
      () async {
        // 1. Live Unreal architecture mode detection
        expect(
          UnrealArchitectureMode.detectFromSpark(
            '3D action RPG with C++ movement component and GAS',
          ),
          equals(UnrealArchitectureMode.cppHybrid),
        );
        expect(
          UnrealArchitectureMode.detectFromSpark(
            'side-scrolling platformer about a frog',
          ),
          equals(UnrealArchitectureMode.blueprint),
        );
        expect(
          UnrealArchitectureMode.detectFromSpark('bullet-hell arcade shooter'),
          equals(UnrealArchitectureMode.blueprint),
        );

        // 2. Strict preset matching (no false matches on generic words)
        expect(
          UnrealSparkPresets.matchSparkPrompt('cozy crab cooking game'),
          isNull,
        );
        expect(UnrealSparkPresets.matchSparkPrompt('shellbreaker'), isNotNull);

        // 3. SparkAngleAgent offline fallback, steering/reroll, and leakage sanitization
        final offAngles = await SparkAngleAgent.proposeAngles(
          rawSpark: 'horror fishing',
          apiKey: '',
        );
        expect(offAngles.usedOfflineFallback, isTrue);
        expect(offAngles.deck, isNotNull);
        expect(offAngles.deck!.angles, hasLength(3));
        expect(offAngles.deck!.round, equals(1));

        final steeredOff = await SparkAngleAgent.proposeAngles(
          rawSpark: 'horror fishing',
          apiKey: '',
          steerNote: 'Swap boat for oil rig',
          reroll: true,
          previousDeck: offAngles.deck,
        );
        expect(steeredOff.deck!.round, equals(2));
        expect(
          steeredOff.deck!.steerHistory,
          equals(<String>['Swap boat for oil rig']),
        );
        expect(
          steeredOff.deck!.buildSelectedHandoffPrompt(),
          contains('Swap boat for oil rig'),
        );

        // 4 & 5. Real AI failure surfacing on draftSpecWithStatus & applyCoDesignEditWithStatus
        final prevMock = GeminiAgentClient.testMockResponder;
        final prevStatus = GeminiAgentClient.lastErrorStatus;
        GeminiAgentClient.testMockResponder = (_, __) async => null;
        GeminiAgentClient.lastErrorStatus = 'HTTP 503: Service Unavailable';
        try {
          final leakyRes = await SparkAngleAgent.proposeAngles(
            rawSpark: 'top-down brawler',
            apiKey: 'test-key-1234',
          );
          expect(leakyRes.deck, isNull);
          expect(leakyRes.errorMessage, isNotEmpty);

          GeminiAgentClient.testMockResponder = (_, __) async => {
                'angles': [
                  {
                    'id': 'arcade',
                    'styleTag': 'ARCADE',
                    'title': 'godot.gd Rush',
                    'pitch': 'CharacterBody3D dashes 12 m across res://arena.tscn',
                    'cameraHint': 'Isometric',
                    'viewChoiceId': 'isometric',
                    'sliceHint': '1 Room',
                  },
                ],
              };
          final sanitizedAngles = await SparkAngleAgent.proposeAngles(
            rawSpark: 'top-down brawler',
            apiKey: 'test-key-1234',
          );
          expect(sanitizedAngles.deck, isNotNull);
          expect(sanitizedAngles.deck!.angles, hasLength(3));
          expect(
            UnrealSpecGuard.containsEngineLeakage(
              sanitizedAngles.deck!.angles.first.pitch,
            ),
            isFalse,
          );
          expect(sanitizedAngles.deck!.angles.first.pitch, contains('1200 cm'));

          GeminiAgentClient.testMockResponder = (_, __) async => null;
          GeminiAgentClient.lastErrorStatus = 'HTTP 503: Service Unavailable';
          final draftErr = await ProjectConceptAgent.draftSpecWithStatus(
            sparkPrompt: 'Top-down melee beetle brawler with dash',
            apiKey: 'test-key-1234',
          );
          expect(draftErr.blueprint, isNull);
          expect(draftErr.errorMessage, isNotEmpty);

          final seedSpec = UnrealSparkPresets.byId('shellbreaker');
          final prevPillars = List<String>.from(seedSpec.pillars);
          final refineErr = await ProjectConceptAgent.applyCoDesignEditWithStatus(
            currentSpec: seedSpec,
            instruction: 'Add parry shield',
            apiKey: 'test-key-1234',
          );
          expect(refineErr.blueprint, isNull);
          expect(refineErr.errorMessage, isNotEmpty);
          expect(seedSpec.pillars, equals(prevPillars));

          // 6. Scoped patch refine switching to cppHybrid updates assetPolicy & ownership,
          // renumbers F01..FM sequentially, clears stale v0.2 preset data on title/pitch shift,
          // and leaves untouched Epics intact.
          GeminiAgentClient.testMockResponder = (_, __) async => <String, dynamic>{
                'coDesignNote': 'Switched to C++ hybrid side-scroller and added turret cut',
                'changedSections': ['s01', 's02', 's04'],
                'gameTitle': 'TIDAL HOP',
                'pitch': 'Side-scrolling claw dasher — leap across ruins',
                'architectureMode': 'cppHybrid',
                'cameraChoiceId': 'sidescroller',
                'cameraContract':
                    'USpringArmComponent TargetArmLength 950 cm · Ortho/Locked Track · 55 deg FOV · Lookahead 160 cm',
                'outOfScope': [
                  ...seedSpec.outOfScope,
                  'No deployable sentry turrets',
                ],
              };
          final patchOk = await ProjectConceptAgent.applyCoDesignEditWithStatus(
            currentSpec: seedSpec,
            instruction: 'Switch to C++ side-scroller called Tidal Hop and cut sentry turrets',
            apiKey: 'test-key-1234',
          );
          expect(patchOk.errorMessage, isNull);
          final updated = patchOk.blueprint!;
          expect(updated.architectureMode, equals(UnrealArchitectureMode.cppHybrid));
          final f01Speed = updated.initialEpics.first.features.first.tuning
              .firstWhere((t) => t.key == 'MoveSpeed');
          expect(f01Speed.unit, equals('cm/s'));
          expect(double.parse(f01Speed.value), greaterThan(100));
          expect(updated.v02Presets, isEmpty);
          expect(updated.v02NewPool, isEmpty);
          expect(
            patchOk.changedSections,
            containsAll(<String>['s01', 's02', 's04']),
          );
          final allFeatureCodes = [
            for (final ep in updated.initialEpics)
              for (final f in ep.features) f.code,
          ];
          expect(
            allFeatureCodes,
            equals([
              for (int i = 0; i < allFeatureCodes.length; i++)
                FeatureSpec.formatCode(i + 1),
            ]),
          );
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
          GeminiAgentClient.lastErrorStatus = prevStatus;
        }

        // 7. Reordering E01 to index 1 keeps syncEpicCameraFraming & syncEpicCoreFeel
        // targeting the locomotion Epic (lineageKey == 'e01') and its first FeatureSpec.
        final reordered = UnrealSparkPresets.byId('shellbreaker').deepCopy();
        final movedE01 = reordered.initialEpics.removeAt(0);
        reordered.initialEpics.insert(1, movedE01);
        reordered.initialEpics[0].code = 'E01';
        reordered.initialEpics[1].code = 'E02';

        ProjectConceptAgent.syncEpicCameraFraming(
          reordered,
          optionId: 'fps',
          contractValue: 'UCameraComponent EyeHeight 165 cm · 90 deg FOV · Captured mouse yaw/pitch',
        );
        ProjectConceptAgent.syncEpicCoreFeel(reordered, feelId: 'heavy');

        final wrongFirstFeat = reordered.initialEpics[0].features.first;
        final locoFeat = reordered.initialEpics[1].features.first;
        expect(
          wrongFirstFeat.tuning.any((t) => t.key == 'EyeHeight'),
          isFalse,
        );
        expect(
          locoFeat.tuning.any((t) => t.key == 'EyeHeight'),
          isTrue,
        );
        expect(
          locoFeat.tuning.firstWhere((t) => t.key == 'BrakingDeceleration').value,
          equals('1400'),
        );
        expect(
          locoFeat.controls.any((c) => c.action == 'IA_LookAxis'),
          isTrue,
        );
        expect(
          locoFeat.checks.any((c) => c.text.toLowerCase().contains('first-person')),
          isTrue,
        );

        // 8. Offline fallback fixes F01.passed, sequential codes, and non-combat genre templates.
        final puzzleOff = await ProjectConceptAgent.draftSpecFromSpark(
          sparkPrompt: 'Isometric puzzle box room where you slide mirror relays to open gates',
          apiKey: '',
        );
        expect(
          puzzleOff.initialEpics.first.features.first.status,
          equals(FeatureStatus.active),
        );
        expect(
          puzzleOff.initialEpics.first.features.first.checks.first.passed,
          isFalse,
        );
        final puzzleCodes = [
          for (final ep in puzzleOff.initialEpics)
            for (final f in ep.features) f.code,
        ];
        expect(
          puzzleCodes,
          equals([
            for (int i = 0; i < puzzleCodes.length; i++)
              FeatureSpec.formatCode(i + 1),
          ]),
        );
        expect(
          puzzleOff.initialEpics.first.sceneOwnership
              .any((s) => s.path.contains('Lvl_RoomProto.umap')),
          isTrue,
        );
        expect(
          puzzleOff.initialEpics.any(
            (e) => e.sceneOwnership.any((s) => s.path.contains('TargetEnemy')),
          ),
          isFalse,
        );

        final racerOff = await ProjectConceptAgent.draftSpecFromSpark(
          sparkPrompt: 'Canyon hover racer with drift boost pads and lap timer',
          apiKey: '',
        );
        expect(
          racerOff.initialEpics.first.sceneOwnership
              .any((s) => s.path.contains('Lvl_TrackProto.umap')),
          isTrue,
        );
      },
    );

    testWidgets(
      '19. Stage 1 UI: Live 2D/3D preview, vague-spark clarification card, preserved error + Undo + Badges + Scope preview + lean inline edits',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        final prevMock = GeminiAgentClient.testMockResponder;
        final prevStatus = GeminiAgentClient.lastErrorStatus;
        addTearDown(() {
          GeminiAgentClient.testMockResponder = prevMock;
          GeminiAgentClient.lastErrorStatus = prevStatus;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wb = WorkbenchProvider(enableAutoLoad: false);
        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        // 1. Live C++ & BP Hybrid preview while typing before tapping Draft
        await tester.enterText(
          find.byKey(const ValueKey('spark_prompt_input')),
          'C++ action roguelite with GAS',
        );
        await tester.pump();
        expect(
          wb.unrealArchitectureMode,
          equals(UnrealArchitectureMode.cppHybrid),
        );

        // 2. Idea Workbench explores 3 angles -> select -> steer -> reroll -> Draft Selected Angle
        expect(
          find.byKey(const ValueKey('stage1_blueprint_empty_outline')),
          findsNothing,
        );
        await tester.enterText(
          find.byKey(const ValueKey('spark_prompt_input')),
          'cozy farming roguelike',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('explore_angles_btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('stage1_idea_angles_card')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('stage1_angle_card_tactical')));
        await tester.pumpAndSettle();
        expect(wb.pendingAngleDeck?.selectedAngleId, equals('tactical'));

        await tester.enterText(
          find.byKey(const ValueKey('stage1_angle_steer_input')),
          'Add co-op lantern bearer',
        );
        await tester.tap(find.byKey(const ValueKey('stage1_angle_steer_btn')));
        await tester.pumpAndSettle();
        expect(wb.pendingAngleDeck?.round, equals(2));
        expect(find.text('Round 2'), findsOneWidget);
        expect(find.text('Add co-op lantern bearer'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('stage1_angle_reroll_btn')));
        await tester.pumpAndSettle();
        expect(wb.pendingAngleDeck?.round, equals(3));

        await tester.tap(
          find.byKey(const ValueKey('stage1_lock_angle_draft_btn')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('stage1_scope_preview_card')),
          findsOneWidget,
        );
        expect(wb.conceptDraft?.hasSpec, isTrue);
        final prevPillarsCount = wb.conceptDraft!.pillars.length;

        // 3. Failed AI Refine shows inline error banner, keeps user text intact, never mutates pillars
        GeminiAgentClient.testMockResponder = (_, __) async => null;
        GeminiAgentClient.lastErrorStatus = 'HTTP 503: Upstream Busy';
        wb.updateAiConfig(apiKey: 'test-key-1234');

        await tester.enterText(
          find.byKey(const ValueKey('stage1_codesign_input')),
          'Add parry shield',
        );
        await tester.tap(find.byKey(const ValueKey('stage1_codesign_apply_btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('stage1_inline_error_banner')),
          findsOneWidget,
        );
        final tf = tester.widget<TextField>(
          find.byKey(const ValueKey('stage1_codesign_input')),
        );
        expect(tf.controller?.text, equals('Add parry shield'));
        expect(wb.conceptDraft!.pillars.length, equals(prevPillarsCount));
        expect(wb.conceptDraft!.pillars.contains('Add parry shield'), isFalse);

        // 4. Successful scoped patch shows Updated badge on §04, clears input, enables Undo
        final beforeCuts = List<String>.from(wb.conceptDraft!.outOfScope);
        GeminiAgentClient.testMockResponder = (_, __) async => <String, dynamic>{
              'coDesignNote': 'Cut online co-op from v0.1',
              'changedSections': ['s04'],
              'outOfScope': [...beforeCuts, 'No online co-op lobbies'],
            };
        await tester.tap(find.byKey(const ValueKey('stage1_codesign_apply_btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('stage1_updated_badge_§04')),
          findsOneWidget,
        );
        expect(tf.controller?.text, isEmpty);
        expect(
          wb.conceptDraft!.outOfScope,
          contains('No online co-op lobbies'),
        );

        await tester.tap(find.byKey(const ValueKey('stage1_undo_btn')));
        await tester.pumpAndSettle();
        expect(
          wb.conceptDraft!.outOfScope,
          equals(beforeCuts),
        );

        // 5. Lean inline edits without AI (Title, §01 Pitch, §04 Cuts, §05 Feature slice + Undo)
        GeminiAgentClient.testMockResponder = null;

        await tester.tap(find.byKey(const ValueKey('stage1_edit_title_btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('stage1_title_input')),
          'CLOVER PATCH',
        );
        await tester.tap(find.byKey(const ValueKey('stage1_title_save_btn')));
        await tester.pumpAndSettle();
        expect(wb.conceptDraft!.gameTitle, equals('CLOVER PATCH'));

        await tester.tap(find.byKey(const ValueKey('stage1_edit_pitch_btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('stage1_pitch_input')),
          'Cozy Plot Loop — Tend lanterns and harvest moonroot before dusk',
        );
        await tester.tap(find.byKey(const ValueKey('stage1_pitch_save_btn')));
        await tester.pumpAndSettle();
        expect(wb.conceptDraft!.pitch, contains('Tend lanterns'));

        await tester.ensureVisible(
          find.byKey(const ValueKey('stage1_cut_add_btn')),
        );
        await tester.tap(find.byKey(const ValueKey('stage1_cut_add_btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('stage1_cut_add_input')),
          'Fishing minigame',
        );
        await tester.tap(find.byKey(const ValueKey('stage1_cut_add_save_btn')));
        await tester.pumpAndSettle();
        expect(wb.conceptDraft!.outOfScope, contains('No Fishing minigame'));

        await tester.ensureVisible(
          find.byKey(const ValueKey('stage1_cut_remove_0')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('stage1_cut_remove_0')));
        await tester.pumpAndSettle();
        expect(wb.conceptDraft!.outOfScope.length, equals(beforeCuts.length));

        final firstFeat = wb.conceptDraft!.initialEpics.first.features.first;
        final secondFeat = wb.conceptDraft!.initialEpics.first.features[1];

        await tester.ensureVisible(
          find.byKey(ValueKey('stage1_feat_edit_${firstFeat.id}')),
        );
        await tester.tap(
          find.byKey(ValueKey('stage1_feat_edit_${firstFeat.id}')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(ValueKey('stage1_feat_input_${firstFeat.id}')),
          'Garden Walk & Camera',
        );
        await tester.tap(
          find.byKey(ValueKey('stage1_feat_save_${firstFeat.id}')),
        );
        await tester.pumpAndSettle();
        expect(
          wb.conceptDraft!.initialEpics.first.features.first.title,
          equals('Garden Walk & Camera'),
        );

        final featCountBeforeRemove = wb.conceptDraft!.initialEpics
            .fold<int>(0, (s, e) => s + e.features.length);
        await tester.ensureVisible(
          find.byKey(ValueKey('stage1_feat_remove_${secondFeat.id}')),
        );
        await tester.tap(
          find.byKey(ValueKey('stage1_feat_remove_${secondFeat.id}')),
        );
        await tester.pumpAndSettle();
        final featCountAfterRemove = wb.conceptDraft!.initialEpics
            .fold<int>(0, (s, e) => s + e.features.length);
        expect(featCountAfterRemove, equals(featCountBeforeRemove - 1));

        await tester.ensureVisible(
          find.byKey(const ValueKey('stage1_undo_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('stage1_undo_btn')));
        await tester.pumpAndSettle();
        final featCountAfterUndo = wb.conceptDraft!.initialEpics
            .fold<int>(0, (s, e) => s + e.features.length);
        expect(featCountAfterUndo, equals(featCountBeforeRemove));
      },
    );

    test(
      '20. Unique Feature IDs, cross-release F## codes & non-colliding lineageKeys',
      () async {
        // 1) Multi-Epic JSON without feature IDs yields unique Feature IDs & F01..F04 codes
        final bp = ProjectConceptBlueprint.fromJson({
          'gameTitle': 'ID GUARD TEST',
          'dimension': 'dim3d',
          'pitch': 'Arena test — Clean 3D slices.',
          'initialEpics': [
            {
              'title': 'Player Movement',
              'goal': 'Walk cleanly.',
              'features': [
                {'id': 'feat_1', 'title': 'Walk', 'goal': 'Move around'},
                {'title': 'Sprint', 'goal': 'Move faster'},
              ],
            },
            {
              'title': 'Combat Attacks',
              'goal': 'Swing cleanly.',
              'features': [
                {'id': 'feat_1', 'title': 'Light Hit', 'goal': 'Fast swing'},
                {'title': 'Heavy Slam', 'goal': 'Armored slam'},
              ],
            },
          ],
        });
        ProjectConceptAgent.normalizeSequentialEpicAndFeatureCodes(bp);
        final allFeats = [for (final ep in bp.initialEpics) ...ep.features];
        final allIds = allFeats.map((f) => f.id).toSet();
        expect(allFeats.length, equals(4));
        expect(
          allIds.length,
          equals(4),
          reason: 'Expected distinct Feature IDs across Epics: ${allFeats.map((f) => f.id).toList()}',
        );
        expect(
          allFeats.map((f) => f.code).toList(),
          equals(['F01', 'F02', 'F03', 'F04']),
        );

        // 2) Removing F01 in Stage 1 and re-approving does not match F02 against old F01 by 'feat_1'
        final wbRe = WorkbenchProvider(enableAutoLoad: false);
        wbRe.loadPresetSpark('shellbreaker');
        // Replace initialEpics features with positional 'feat_1'/'feat_2' to test reconciliation guard
        final reEp = wbRe.conceptDraft!.initialEpics.first;
        reEp.features = [
          FeatureSpec(
            id: 'feat_1',
            code: 'F01',
            title: 'Base Walk',
            goal: '8-way walk.',
            checks: [EpicPieCheck(id: 'c_w1', text: 'Walks cleanly')],
          ),
          FeatureSpec(
            id: 'feat_2',
            code: 'F02',
            title: 'Armored Claw Dash',
            goal: 'Forward 4 m dash.',
            checks: [EpicPieCheck(id: 'c_d1', text: 'Dashes cleanly')],
          ),
        ];
        wbRe.approveRootSpecAndLaunchWorkbench();
        final v01Ep = wbRe.activeReleaseEpics.first;
        final f02Id = v01Ep.features[1].id;
        wbRe.toggleFeatureCheck(v01Ep.id, f02Id, 'c_d1', true);
        expect(wbRe.passFeature(v01Ep.id, f02Id), isTrue);

        // Return to Stage 1, drop F01, and simulate an AI re-draft whose remaining Dash has fallback id 'feat_1'
        wbRe.setStage(WorkbenchStage.projectPitch);
        wbRe.removeStage1FeatureSlice(0, wbRe.conceptDraft!.initialEpics.first.features.first.id);
        wbRe.conceptDraft!.initialEpics.first.features[0] = wbRe
            .conceptDraft!.initialEpics.first.features[0]
            .deepCopy(idOverride: 'feat_1');
        wbRe.approveRootSpecAndLaunchWorkbench();
        final mergedEp = wbRe.activeReleaseEpics.first;
        final mergedIds = mergedEp.features.map((f) => f.id).toSet();
        final mergedCodes = mergedEp.features.map((f) => f.code).toSet();
        expect(mergedIds.length, equals(mergedEp.features.length));
        expect(mergedCodes.length, equals(mergedEp.features.length));
        final keptWalk =
            mergedEp.features.where((f) => f.title == 'Base Walk').toList();
        expect(keptWalk.length, equals(1));
        expect(keptWalk.first.isPassed, isFalse);
        final keptDash = mergedEp.features.firstWhere(
          (f) => f.title == 'Armored Claw Dash',
        );
        expect(keptDash.isPassed, isTrue);

        // 3) Deleting E01 in Stage 1 + v0.2 [+NEW] Feature with omitted/'feat_1' id + 2 [NEW] Epics
        final prevMock = GeminiAgentClient.testMockResponder;
        try {
          final wb = WorkbenchProvider(enableAutoLoad: false);
          wb.loadPresetSpark('shellbreaker');
          wb.removeInitialEpicAt(0); // leaves 2 Epics including 'e02', 'e03'
          wb.approveRootSpecAndLaunchWorkbench();
          final v01Id = wb.activeReleaseId!;
          final v01FirstEpic = wb.activeReleaseEpics.first;

          GeminiAgentClient.testMockResponder = (prompt, model) async => {
                'presets': [
                  {
                    'id': 'preset_juice',
                    'label': 'Combat Juice Pass',
                    'desc': 'Add reel & boss escalation.',
                    'upgrades': [],
                    'newEpics': ['cand_new_1', 'cand_new_2'],
                  },
                ],
                'upgrades': [],
                'newFeatures': [
                  {
                    'lineageKey': v01FirstEpic.lineageKey,
                    'features': [
                      {
                        'id': 'feat_1',
                        'code': 'F01',
                        'title': 'Grapple Hook Reel',
                        'goal': 'Pull player to target cleanly.',
                        'checks': ['Press E -> Pulls to crate'],
                      },
                    ],
                  },
                ],
                'newEpics': [
                  {
                    'title': 'Boss Phase System',
                    'goal': 'Run multi-phase boss loop.',
                    'chosen': true,
                    'features': [
                      {'title': 'Slam Telegraph', 'goal': 'Warn before slam'},
                    ],
                  },
                  {
                    'title': 'Arena Hazard Spawner',
                    'goal': 'Spawn timed floor vents.',
                    'chosen': true,
                    'features': [
                      {'title': 'Vent Burst', 'goal': 'Knock back player'},
                    ],
                  },
                ],
              };

          final draftV02 = await wb.openProgressiveReleaseCopilot();
          expect(draftV02, isNotNull);
          final candNewFeats =
              draftV02!.candidateNewFeaturesByLineageKey[v01FirstEpic.lineageKey] ??
                  const [];
          expect(candNewFeats.length, equals(1));
          expect(candNewFeats.first.id, isNot(equals('feat_1')));
          wb.toggleProgressiveNewFeature(
            v01FirstEpic.lineageKey,
            candNewFeats.first.id,
          );
          expect(draftV02.chosenNewFeatureIds.contains(candNewFeats.first.id), isTrue);
          for (final candEp in draftV02.candidateNewEpics) {
            candEp.chosenForNextRelease = true;
          }

          final v02Id = wb.commitProgressiveReleaseDraft();
          expect(v02Id, isNotNull);
          final v02Epics = wb.activeReleaseEpics;
          final v02FirstEpic = v02Epics.firstWhere(
            (e) => e.lineageKey == v01FirstEpic.lineageKey,
          );
          expect(
            v02FirstEpic.features.any((f) => f.title == 'Grapple Hook Reel'),
            isTrue,
            reason: '[+NEW] Feature in v0.2 must not be dropped when prior features exist',
          );
          final v02LineageKeys =
              v02Epics.map((e) => e.lineageKey.toLowerCase()).toSet();
          expect(
            v02LineageKeys.length,
            equals(v02Epics.length),
            reason: 'v0.2 Epic lineageKeys must stay unique: ${v02Epics.map((e) => e.lineageKey).toList()}',
          );

          // 4) Switching back to v0.1 and adding a Feature slice must avoid codes used in v0.2
          final v02CodesLower = {
            for (final ep in v02Epics)
              for (final f in ep.features) f.code.trim().toLowerCase(),
          };
          wb.selectActiveRelease(v01Id);
          final addedInV01 = wb.addFeatureSlice(
            v01FirstEpic.id,
            title: 'Extra Proto Slice',
            goal: 'Verify cross-release F-code uniqueness.',
          );
          expect(addedInV01, isNotNull);
          expect(
            v02CodesLower.contains(addedInV01!.code.trim().toLowerCase()),
            isFalse,
            reason: 'addFeatureSlice allocated ${addedInV01.code} which collides with v0.2 codes $v02CodesLower',
          );
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
        }
      },
    );

    test(
      '21. ReleasePlannerAgent 4-tier [NEW] Epic schema, prompt feature/scene summary, invalid lineageKey filtering & Railjack/Emberkeep v0.2 parity',
      () async {
        final prevMock = GeminiAgentClient.testMockResponder;
        final prevHttp = GeminiAgentClient.testHttpPost;
        final prevDelay = GeminiAgentClient.testBaseRetryDelay;
        GeminiAgentClient.resetCapabilityCacheForTest();
        GeminiAgentClient.testBaseRetryDelay = Duration.zero;

        try {
          final sb = UnrealSparkPresets.byId('shellbreaker');

          // 1) Inspect outbound Gemini functionDeclaration schema & verify 4-tier [NEW] Epic schema
          Map<String, dynamic>? capturedToolDecl;
          GeminiAgentClient.testMockResponder = null;
          GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
            if (body is String && body.isNotEmpty) {
              final decoded = jsonDecode(body) as Map<String, dynamic>;
              final tools = decoded['tools'] as List?;
              if (tools != null && tools.isNotEmpty) {
                final decls = (tools.first as Map)['functionDeclarations'] as List?;
                if (decls != null && decls.isNotEmpty) {
                  capturedToolDecl =
                      Map<String, dynamic>.from(decls.first as Map);
                }
              }
            }
            return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {
                          'functionCall': {
                            'name': 'propose_progressive_unreal_release',
                            'args': {
                              'presets': [],
                              'upgrades': [],
                              'newFeatures': [],
                              'newEpics': [],
                            },
                          },
                        },
                      ],
                    },
                  },
                ],
              }),
              200,
            );
          };

          await ReleasePlannerAgent.proposeNextReleaseCopilot(
            rootSpec: sb,
            currentEpics: sb.initialEpics,
            targetVersion: 'v0.2',
            apiKey: 'test-key-1234',
          );

          expect(capturedToolDecl, isNotNull);
          final rootParams =
              capturedToolDecl!['parameters'] as Map<String, dynamic>;
          final rootProps = rootParams['properties'] as Map<String, dynamic>;
          final newEpicItems =
              (rootProps['newEpics'] as Map<String, dynamic>)['items']
                  as Map<String, dynamic>;
          final newEpicRequired =
              (newEpicItems['required'] as List).cast<String>();
          final newEpicProps =
              newEpicItems['properties'] as Map<String, dynamic>;

          expect(
            newEpicRequired,
            containsAll(<String>[
              'inScope',
              'doneWhen',
              'sceneOwnership',
              'features',
            ]),
          );
          for (final legacyField in const <String>[
            'controls',
            'tuning',
            'feedback',
            'levelStaging',
            'checks',
          ]) {
            expect(newEpicRequired, isNot(contains(legacyField)));
            expect(newEpicProps.containsKey(legacyField), isFalse);
          }

          // 2) Mock Gemini Co-Pilot response with invalid lineageKey, preset newFeatures, and 2 [NEW] Epics
          GeminiAgentClient.testHttpPost = null;
          String capturedPrompt = '';
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..updateAiConfig(apiKey: 'test-key-1234');
          wb.loadPresetSpark('shellbreaker');
          for (final ep in wb.conceptDraft!.initialEpics) {
            wb.passActiveEpic(ep.id);
          }
          wb.approveRootSpecAndLaunchWorkbench();

          GeminiAgentClient.testMockResponder = (prompt, model) async {
            capturedPrompt = prompt;
            return {
              'presets': [
                {
                  'id': 'preset_arena_edge',
                  'label': 'Arena Edge Pass',
                  'desc': 'Add wall dash slice without upgrades on e02.',
                  'upgrades': <String>[],
                  'newFeatures': ['cand_f_e02_wall'],
                  'newEpics': ['cand_e_wave', 'cand_e_empty'],
                },
              ],
              'upgrades': [
                {
                  'lineageKey': 'ghost_e99',
                  'options': [
                    {'id': 'up_ghost', 'text': '+Invalid upgrade for missing Epic'},
                  ],
                },
              ],
              'newFeatures': [
                {
                  'lineageKey': 'ghost_e99',
                  'features': [
                    {
                      'id': 'ghost_feat',
                      'title': 'Ghost Feature',
                      'goal': 'Should be filtered.',
                      'checks': ['Press Space -> Nothing'],
                    },
                  ],
                },
                {
                  'lineageKey': 'e02',
                  'features': [
                    {
                      'id': 'cand_f_e02_wall',
                      'title': 'Ricochet Charge Shot',
                      'goal': 'Bounce charged bolt off stone pillars cleanly.',
                      'tuning': [
                        {'key': 'ricochet_bounces', 'value': '2', 'unit': 'count'},
                      ],
                      'checks': [
                        {'text': 'Fire bolt into pillar -> Reflects twice onto crab'},
                      ],
                    },
                  ],
                },
              ],
              'newEpics': [
                {
                  'id': 'cand_e_wave',
                  'code': 'E04',
                  'title': 'Arena Hazard Spawner',
                  'coreLoopBeat': 'Beat 4 · Hazard Pressure',
                  'chosen': true,
                  'goal': 'Activate timed perimeter steam vents across the arena.',
                  'inScope': ['4 perimeter vent nodes', 'Telegraph warning flicker'],
                  'doneWhen': ['Stand on lit vent -> Steam erupts after 0.8 s cleanly'],
                  'sceneOwnership': [
                    {
                      'path': 'res://scripts/hazard_spawner.gd',
                      'role': 'Timed perimeter hazard activation controller',
                    },
                  ],
                  'states': ['Idle -> Telegraph (0.8s) -> Erupt -> Cooldown'],
                  'interrupts': ['Match end halts all active vent timers cleanly'],
                  'outOfScope': ['No destructive floor tile deformation'],
                  'features': [
                    {
                      'title': 'Perimeter Vent Telegraph',
                      'goal': 'Warn player 0.8 s before vent steam knocks player back.',
                      'tuning': [
                        {'key': 'vent_warn_s', 'value': '0.8', 'unit': 's'},
                      ],
                      'checks': [
                        {'text': 'Vent lights orange -> Steam erupts 0.8 s later cleanly'},
                      ],
                    },
                  ],
                },
                {
                  'id': 'cand_e_empty',
                  'code': 'E05',
                  'title': 'Overdrive Gauge',
                  'coreLoopBeat': 'Beat 5 · Overdrive Surge',
                  'chosen': true,
                  'goal': 'Fill Overdrive charge on shatter to boost dash impulse.',
                  'inScope': ['Charge meter 0..100 %', 'Q activation burst'],
                  'doneWhen': ['Reach 100 % and press Q -> Surge lasts 4.0 s cleanly'],
                  'sceneOwnership': <dynamic>[],
                  'states': ['Charging -> Ready -> Surging (4.0s)'],
                  'interrupts': ['Defeat resets charge meter to 0'],
                  'outOfScope': ['No persistent cross-run meter carry'],
                  'features': <dynamic>[],
                },
              ],
            };
          };

          final draftV02 = await wb.openProgressiveReleaseCopilot();
          expect(draftV02, isNotNull);

          // Prompt includes sceneOwnership and child Feature codes from v0.1 Epics
          expect(capturedPrompt, contains('/Game/Blueprints/BP_PlayerMech'));
          expect(capturedPrompt, contains('F01'));
          expect(capturedPrompt, contains('F02'));

          // Invalid lineageKey is rejected
          expect(
            draftV02!.upgradesByLineageKey.containsKey('ghost_e99'),
            isFalse,
          );
          expect(
            draftV02.candidateNewFeaturesByLineageKey.containsKey('ghost_e99'),
            isFalse,
          );

          // Preset newFeatures keeps cand_f_e02_wall checked even without an upgrade on e02
          final e02CandFeats =
              draftV02.candidateNewFeaturesByLineageKey['e02'] ?? const [];
          expect(e02CandFeats, hasLength(1));
          final wallFeat = e02CandFeats.first;
          expect(wb.isProgressiveNewFeatureChosen(wallFeat.id), isTrue);

          // New Epics receive non-colliding F## codes & empty-features Epic synthesizes playable slice + sceneOwnership
          expect(draftV02.candidateNewEpics, hasLength(2));
          final waveEpic = draftV02.candidateNewEpics[0];
          final emptySynthesizedEpic = draftV02.candidateNewEpics[1];
          expect(waveEpic.features, hasLength(1));
          expect(waveEpic.features.first.code, isNot(equals('F01')));
          expect(emptySynthesizedEpic.features, hasLength(1));
          expect(emptySynthesizedEpic.sceneOwnership, isNotEmpty);
          expect(
            emptySynthesizedEpic.features.first.code,
            isNot(equals(waveEpic.features.first.code)),
          );

          // 3) Offline Railjack v0.2 parity: keeps rj_f07_wallglide selected, zero hardcoded "enemies"
          GeminiAgentClient.testMockResponder = null;
          final wbRj = WorkbenchProvider(enableAutoLoad: false);
          wbRj.loadPresetSpark('railjack');
          wbRj.approveRootSpecAndLaunchWorkbench();
          final rjDraft = await wbRj.openProgressiveReleaseCopilot();
          expect(rjDraft, isNotNull);
          final rjFeats =
              rjDraft!.candidateNewFeaturesByLineageKey['e01'] ?? const [];
          expect(rjFeats.any((f) => f.id == 'rj_f07_wallglide'), isTrue);
          expect(wbRj.isProgressiveNewFeatureChosen('rj_f07_wallglide'), isTrue);
          for (final ep in rjDraft.candidateNewEpics) {
            expect(ep.goal.toLowerCase(), isNot(contains('enemies')));
            for (final c in ep.checks) {
              expect(c.text.toLowerCase(), isNot(contains('enemies')));
            }
          }

          // 4) Offline Emberkeep v0.2 parity: keeps ek_f07_roll selected with Unreal cm/cm/s units
          final wbEk = WorkbenchProvider(enableAutoLoad: false);
          wbEk.loadPresetSpark('emberkeep');
          wbEk.approveRootSpecAndLaunchWorkbench();
          final ekDraft = await wbEk.openProgressiveReleaseCopilot();
          expect(ekDraft, isNotNull);
          final ekFeats =
              ekDraft!.candidateNewFeaturesByLineageKey['e01'] ?? const [];
          expect(ekFeats.any((f) => f.id == 'ek_f07_roll'), isTrue);
          expect(wbEk.isProgressiveNewFeatureChosen('ek_f07_roll'), isTrue);
          expect(
            ekFeats.firstWhere((f) => f.id == 'ek_f07_roll').tuning.any(
                  (t) => t.unit == 'cm' || t.unit == 'cm/s',
                ),
            isTrue,
          );
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
          GeminiAgentClient.testHttpPost = prevHttp;
          GeminiAgentClient.testBaseRetryDelay = prevDelay;
        }
      },
    );

    test(
      '22. UnrealSpecGuard regex safety, m/px->cm tuning scaling, and full Blueprint<->C++ blueprint conversion',
      () {
        expect(
          UnrealSpecGuard.sanitizeLine('-52 deg pitch'),
          equals('-52 deg pitch'),
        );
        expect(
          UnrealSpecGuard.sanitizeLine('- Bullet line'),
          equals('Bullet line'),
        );

        final pathLine = UnrealSpecGuard.sanitizeLine(
          'Open res://scenes/arena_proto.tscn in /Game/Blueprints/BP_Mech',
        );
        expect(pathLine, contains('/Game/Maps/Lvl_ArenaProto.umap'));
        expect(pathLine, isNot(contains('.umap.umap')));
        expect(pathLine, contains('/Game/Blueprints/BP_Mech'));

        final metricLine = UnrealSpecGuard.sanitizeLine(
          'Dash 5.5 m at 12 m/s',
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(metricLine, equals('Dash 550 cm at 1200 cm/s'));
        expect(UnrealSpecGuard.containsEngineLeakage(metricLine), isFalse);

        expect(
          UnrealSpecGuard.sanitizeLine('Complete the end-to-end loop'),
          equals('Complete the core loop'),
        );
        final jargonClean = UnrealSpecGuard.sanitizeLine(
          'Leveraged arena st' 'aging while validating delivered hits',
        );
        expect(jargonClean.toLowerCase(), isNot(contains('leveraged')));
        expect(jargonClean.toLowerCase(), isNot(contains('validating')));
        expect(jargonClean.toLowerCase(), isNot(contains('delivered')));
        expect(jargonClean.toLowerCase(), contains('used'));
        expect(jargonClean.toLowerCase(), contains('layout'));
        expect(jargonClean.toLowerCase(), contains('checking'));
        expect(jargonClean.toLowerCase(), contains('produced'));

        final featMetric = UnrealSpecGuard.sanitizeFeatureSpec(
          FeatureSpec(
            id: 'f_scale_m',
            code: 'F01',
            title: 'Dash',
            goal: 'Dash cleanly.',
            tuning: [
              EpicTuningParam(key: 'move_speed', value: '6.4', unit: 'm/s'),
              EpicTuningParam(key: 'dash_dist', value: '5.5', unit: 'm'),
            ],
          ),
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(featMetric.tuning[0].key, equals('MoveSpeed'));
        expect(featMetric.tuning[0].value, equals('640'));
        expect(featMetric.tuning[0].unit, equals('cm/s'));
        expect(featMetric.tuning[1].key, equals('DashDist'));
        expect(featMetric.tuning[1].value, equals('550'));
        expect(featMetric.tuning[1].unit, equals('cm'));

        final featPx = UnrealSpecGuard.sanitizeFeatureSpec(
          FeatureSpec(
            id: 'f_scale_px',
            code: 'F02',
            title: 'Move',
            goal: 'Move cleanly.',
            tuning: [
              EpicTuningParam(key: 'move_speed', value: '240', unit: 'px/s'),
              EpicTuningParam(key: 'dash_speed', value: '600', unit: 'uu/s'),
            ],
          ),
          mode: UnrealArchitectureMode.cppHybrid,
        );
        expect(featPx.tuning[0].value, equals('600'));
        expect(featPx.tuning[0].unit, equals('cm/s'));
        expect(featPx.tuning[1].value, equals('600'));
        expect(featPx.tuning[1].unit, equals('cm/s'));

        final sb = UnrealSparkPresets.byId('shellbreaker');
        final sbAsCpp = ProjectConceptAgent.convertBlueprintArchitectureMode(
          sb,
          UnrealArchitectureMode.cppHybrid,
        );
        final wbExport = WorkbenchProvider(enableAutoLoad: false);
        wbExport.loadPresetSpark('shellbreaker');
        final fullMd = wbExport.buildFullProjectMarkdownExport().content;
        expect(fullMd, isNot(contains('CharacterBody3D')));
        expect(fullMd, isNot(contains('SpringArm3D')));
        expect(fullMd, contains('cm/s'));
        expect(fullMd, isNot(contains(RegExp(r'(?<!c)m/s'))));
        expect(sbAsCpp.assetPolicy, contains('Source/'));

        final ek = UnrealSparkPresets.byId('emberkeep');
        final ekAsCpp = ProjectConceptAgent.convertBlueprintArchitectureMode(
          ek,
          UnrealArchitectureMode.cppHybrid,
        );
        expect(
          ekAsCpp.initialEpics.first.features.first.tuning.first.unit,
          equals('cm/s'),
        );
        expect(ekAsCpp.initialEpics.first.goal, isNot(contains('CharacterBody2D')));
        expect(ekAsCpp.initialEpics.first.goal, isNot(contains('px/s')));
      },
    );

    test(
      '23. Cross-release baseline locks on untouched v0.2 Epics, v0.1 delta isolation, v0.2->v0.3 Open-in-Baseline jump & semver v0.1.2',
      () async {
        expect(
          FeatureSpec(
            id: 'f1',
            code: 'F01',
            title: 'Walk',
            introducedIn: 'v0.1',
            goal: 'Walk',
          ).isLockedBaselineInRelease('v0.1.2'),
          isTrue,
        );

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final v01Id = wb.approveRootSpecAndLaunchWorkbench()!;
        final v01Epics = wb.epicsForRelease(v01Id);
        final v01E01 = v01Epics.first;
        final v01F01 = v01E01.features.firstWhere((f) => f.code == 'F01');
        final v01F02 = v01E01.features.firstWhere((f) => f.code == 'F02');

        // 1) v0.1 isolates pre-seeded v0.2 releaseDelta & delta checks
        wb.toggleFeatureCheck(
          v01E01.id,
          v01F01.id,
          v01F01.checks.first.id,
          true,
        );
        final activeV01E01 = wb.activeReleaseEpics.first;
        expect(activeV01E01.lifecycle, equals(EpicLifecycle.active));
        expect(activeV01E01.statusLabel, isNot(equals('Upgrading v0.1')));

        expect(wb.passFeature(v01E01.id, v01F01.id, forceResolve: true), isTrue);
        expect(wb.passFeature(v01E01.id, v01F02.id, forceResolve: true), isTrue);
        final passedF02InV01 = wb
            .epicsForRelease(v01Id)
            .first
            .features
            .firstWhere((f) => f.id == v01F02.id);
        expect(passedF02InV01.releaseDeltaChecks.first.passed, isFalse);

        // Pass remaining v0.1 Epics and launch v0.2 ('juice' preset leaves E02 untouched)
        for (final ep in wb.epicsForRelease(v01Id).skip(1)) {
          wb.passActiveEpic(ep.id);
        }
        await wb.openProgressiveReleaseCopilot();
        final v02Id = wb.commitProgressiveReleaseDraft()!;

        final v02E02 = wb
            .epicsForRelease(v02Id)
            .firstWhere((e) => e.lineageKey == 'e02');
        expect(v02E02.releaseVersion, equals('v0.2'));
        expect(v02E02.isPassed, isTrue);
        final v02F03 = v02E02.features.firstWhere((f) => f.code == 'F03');
        expect(wb.isFeatureLockedBaseline(v02F03), isTrue);

        // Reopening an untouched all-baseline Epic in v0.2 is blocked cleanly
        wb.reopenEpic(v02E02.id);
        final v02E02AfterReopen = wb
            .epicsForRelease(v02Id)
            .firstWhere((e) => e.id == v02E02.id);
        expect(v02E02AfterReopen.lifecycle, equals(EpicLifecycle.stable));
        expect(v02E02AfterReopen.isPassed, isTrue);

        // Off-release baseline guard: switching to v0.1 must still block editing v02E02.F03
        final beforeF03Val = v02F03.tuning.first.value;
        wb.selectActiveRelease(v01Id);
        wb.updateFeatureTuningParam(v02E02.id, v02F03.id, 0, '999');
        final v02F03AfterOffReleaseEdit = wb
            .epicsForRelease(v02Id)
            .firstWhere((e) => e.id == v02E02.id)
            .features
            .firstWhere((f) => f.id == v02F03.id);
        expect(v02F03AfterOffReleaseEdit.tuning.first.value, equals(beforeF03Val));

        // 2) Pass all v0.2 Epics, commit v0.3 without delta on F07, then Open in v0.2 -> jumps to v0.2
        wb.selectActiveRelease(v02Id);
        for (final ep in wb.epicsForRelease(v02Id)) {
          wb.passActiveEpic(ep.id);
        }
        final v03Draft = await wb.openProgressiveReleaseCopilot();
        expect(v03Draft, isNotNull);
        for (final entry in v03Draft!.upgradesByLineageKey.entries) {
          for (final opt in entry.value) {
            if (opt.chosen) {
              wb.toggleProgressiveUpgrade(entry.key, opt.id);
            }
          }
        }
        final v03Id = wb.commitProgressiveReleaseDraft()!;
        final v03E01 = wb
            .epicsForRelease(v03Id)
            .firstWhere((e) => e.lineageKey == 'e01');
        final v03F07 = v03E01.features.firstWhere((f) => f.code == 'F07');
        expect(v03F07.introducedIn, equals('v0.2'));
        wb.selectFeature(v03E01.id, v03F07.id);
        expect(wb.isSelectedFeatureLockedBaseline, isTrue);

        wb.openSelectedFeatureInBaselineRelease();
        expect(wb.activeReleaseVersionTag, equals('v0.2'));
        expect(wb.selectedFeatureSpec?.code, equals('F07'));
        expect(wb.isSelectedFeatureLockedBaseline, isFalse);
      },
    );

    test(
      '24. Stage 1 core models & ProjectConceptAgent stay modular (< 1150 lines) with zero dead ReleaseScope bloat while preserving preset/fallback parity',
      () async {
        expect(
          File('lib/constants/tiers.dart').readAsLinesSync().length,
          lessThanOrEqualTo(120),
        );
        expect(
          File('lib/constants/tiers.dart').readAsStringSync(),
          isNot(contains('enum ReleaseScope')),
        );
        expect(
          File('lib/models/tier_document.dart').readAsLinesSync().length,
          lessThanOrEqualTo(260),
        );
        expect(
          File('lib/models/epic_spec.dart').readAsLinesSync().length,
          lessThanOrEqualTo(1160),
        );
        expect(
          File('lib/models/agent_blueprints.dart').readAsLinesSync().length,
          lessThanOrEqualTo(750),
        );
        expect(
          File('lib/agents/project_concept_agent.dart')
              .readAsLinesSync()
              .length,
          lessThanOrEqualTo(1050),
        );
        const expectedStandaloneModules = <String>[
          'lib/models/progressive_release_models.dart',
          'lib/models/presets/spark_presets.dart',
          'lib/models/presets/shellbreaker_preset.dart',
          'lib/models/presets/railjack_preset.dart',
          'lib/models/presets/emberkeep_preset.dart',
          'lib/agents/concept/project_concept_schemas.dart',
          'lib/agents/concept/project_concept_epic_sync.dart',
          'lib/agents/concept/spark_clarifier.dart',
          'lib/agents/concept/concept_fallback_synthesizer.dart',
          'lib/agents/release_planner_fallback.dart',
        ];
        for (final path in expectedStandaloneModules) {
          final modFile = File(path);
          expect(modFile.existsSync(), isTrue, reason: '$path should exist');
          expect(modFile.readAsLinesSync().length, greaterThan(20));
        }

        final partPattern = RegExp(
          r'''^\s*part\s+(of\s+)?['"]''',
          multiLine: true,
        );
        for (final dirPath in const ['lib/models', 'lib/agents']) {
          for (final entity in Directory(dirPath).listSync(recursive: true)) {
            if (entity is File && entity.path.endsWith('.dart')) {
              final normalizedPath = entity.path.replaceAll('\\', '/');
              expect(
                normalizedPath.endsWith('_part.dart'),
                isFalse,
                reason: '$normalizedPath should be removed',
              );
              expect(
                partPattern.hasMatch(entity.readAsStringSync()),
                isFalse,
                reason: '$normalizedPath should not use part/part of',
              );
            }
          }
        }

        for (final id in const ['shellbreaker', 'railjack', 'emberkeep']) {
          final bp = UnrealSparkPresets.byId(id);
          expect(bp.initialEpics, isNotEmpty, reason: '$id initialEpics');
          expect(bp.v02Presets, isNotEmpty, reason: '$id v02Presets');
        }

        final puzzleOut = await ProjectConceptAgent.draftSpecWithStatus(
          sparkPrompt: 'Push mirrors to unlock exit door',
          apiKey: '',
          architectureModeOverride: UnrealArchitectureMode.cppHybrid,
        );
        expect(puzzleOut.usedOfflineFallback, isTrue);
        expect(puzzleOut.blueprint, isNotNull);
        expect(
          puzzleOut.blueprint!.architectureMode,
          equals(UnrealArchitectureMode.cppHybrid),
        );
        expect(puzzleOut.blueprint!.initialEpics, isNotEmpty);

        final racerOut = await ProjectConceptAgent.draftSpecWithStatus(
          sparkPrompt: 'High-speed hover track racer with nitro boost pads',
          apiKey: '',
          architectureModeOverride: UnrealArchitectureMode.blueprint,
        );
        expect(racerOut.blueprint, isNotNull);
        ProjectConceptAgent.syncEpicCameraFraming(
          racerOut.blueprint!,
          optionId: 'fps',
          contractValue: 'UCameraComponent EyeHeight 160 cm · 90 deg FOV',
        );
        ProjectConceptAgent.syncEpicCoreFeel(
          racerOut.blueprint!,
          feelId: 'heavy',
        );
        expect(racerOut.blueprint!.feelChoiceId, equals('heavy'));

        expect(DurationHelper.normalizeToHours('90 min'), equals('1.5h'));
        final origDoc = TierDocument(
          id: 'doc_1',
          title: 'SHELLBREAKER',
          tier: TierType.project,
          estimatedDuration: '90 min',
          subtasks: [
            Subtask(
              id: 'st_1',
              text: 'Top step',
              completed: true,
              children: [Subtask(id: 'st_2', text: 'Nested step')],
            ),
          ],
        );
        final roundTripped = TierDocument.fromJson(origDoc.toJson());
        expect(roundTripped.estimatedDuration, equals('1.5h'));
        expect(roundTripped.subtasks.length, equals(1));
        expect(roundTripped.subtasks.first.completed, isTrue);
        expect(roundTripped.subtasks.first.children.length, equals(1));
      },
    );

    testWidgets(
      '25. Flutter shell, Stage 1 & Stage 2 use standalone widget modules (<= 950 lines each, zero part files) with UI parity',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        // Stage 1 widgets & Clean Spec Document parity
        expect(find.byKey(const ValueKey('stage1_mode_blueprint')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_mode_cpp_hybrid')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('stage1_scope_preview_card')),
          findsOneWidget,
        );
        expect(find.textContaining('SHELLBREAKER'), findsWidgets);

        // Approve & Launch into Release Spec, then open Feature Spec Sheet
        await tester.tap(
          find.byKey(const ValueKey('approve_launch_workbench_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('release_primary_action_btn')), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('release_primary_action_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.text('GOAL & SCOPE'), findsOneWidget);
        expect(find.textContaining('PLAYTEST ('), findsOneWidget);

        // Select parent Epic Domain & exercise inline add-slice toggle
        wb.selectEpic(wb.activeReleaseEpics.first.id);
        await tester.pumpAndSettle();
        expect(find.text('DOMAIN SCOPE'), findsOneWidget);
        final addSliceBtn = find.byKey(const ValueKey('show_add_feature_btn'));
        expect(addSliceBtn, findsOneWidget);
        await tester.ensureVisible(addSliceBtn);
        await tester.tap(addSliceBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('add_feature_form')), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        wb.dispose();

        const expectedModules = <String>[
          'lib/screens/shell/studio_top_bar.dart',
          'lib/screens/shell/cloud_ai_settings_dialog.dart',
          'lib/screens/shell/team_invites_dialog.dart',
          'lib/screens/shell/project_manage_dialogs.dart',
          'lib/screens/shell/studio_export_actions.dart',
          'lib/screens/stage1/stage1_spec_document.dart',
          'lib/screens/stage1/stage1_shared_widgets.dart',
          'lib/screens/workbench/monday_release_table.dart',
          'lib/screens/workbench/epic_domain_sheet.dart',
          'lib/screens/workbench/feature_spec_sheet.dart',
          'lib/screens/workbench/progressive_release_modal.dart',
          'lib/screens/workbench/workbench_shared_widgets.dart',
        ];
        for (final path in expectedModules) {
          final modFile = File(path);
          expect(modFile.existsSync(), isTrue, reason: '$path should exist');
          expect(
            modFile.readAsLinesSync().length,
            greaterThan(30),
            reason: '$path should hold standalone module code',
          );
        }

        final mainText = File('lib/main.dart').readAsStringSync();
        final mainLines = File('lib/main.dart').readAsLinesSync().length;
        expect(mainLines, lessThanOrEqualTo(250));
        final partPattern = RegExp(
          r'''^\s*part\s+(of\s+)?['"]''',
          multiLine: true,
        );
        expect(partPattern.hasMatch(mainText), isFalse);

        for (final entity in Directory('lib/screens').listSync(recursive: true)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            final normalizedPath = entity.path.replaceAll('\\', '/');
            expect(
              normalizedPath.endsWith('_part.dart'),
              isFalse,
              reason: '$normalizedPath should be removed',
            );
            final contents = entity.readAsStringSync();
            expect(
              partPattern.hasMatch(contents),
              isFalse,
              reason: '$normalizedPath should not contain part/part of',
            );
            final lineCount = entity.readAsLinesSync().length;
            expect(
              lineCount,
              lessThanOrEqualTo(950),
              reason: '$normalizedPath has $lineCount lines',
            );
          }
        }
      },
    );

    test(
      '26. Provider domain services (ProjectArchiveCodec, CloudInviteDeepLinkService, V01ReleaseSeeder) stay modular (<= 950 lines across lib/providers & lib/services)',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final relId = wb.approveRootSpecAndLaunchWorkbench();
        expect(relId, isNotNull);

        // Export -> Import collision remap + Duplicate + Deep-link parity
        final origProjId = wb.activeProjectId;
        final exported = wb.exportProjectToJson();
        expect(exported, contains('layers-agentic-project-v3'));
        final importedId = wb.importProjectFromJson(exported);
        expect(importedId, isNotNull);
        expect(importedId, isNot(equals(origProjId)));
        final dupId = wb.duplicateProject(importedId!);
        expect(dupId, isNotNull);
        wb.applyDeepLinkParams({
          'project': importedId,
          'epic': 'e01',
        });
        expect(wb.activeProjectId, equals(importedId));
        // Direct service unit checks
        final treeIds = ProjectArchiveCodec.collectProjectTreeIds(
          wb.documents,
          importedId,
        );
        expect(treeIds, contains(importedId));
        final parsedQuery = CloudInviteDeepLinkService.parseDeepLinkQuery({
          'project': importedId,
          'epic': 'e01',
          'feature': 'f02',
        });
        expect(parsedQuery.projectId, equals(importedId));
        expect(parsedQuery.epicId, equals('e01'));
        expect(parsedQuery.featureId, equals('f02'));
        final seeded = V01ReleaseSeeder.buildOrReconcileV01Release(
          projectId: 'unit_proj',
          draft: wb.conceptDraft!,
          existingDocs: const [],
          reservedCodesLower: const {'f01'},
        );
        expect(seeded.epicDocsToSave, isNotEmpty);
        final firstFeatCode =
            EpicSpec.fromDocument(seeded.epicDocsToSave.first).features.first.code;
        expect(firstFeatCode.toLowerCase(), isNot(equals('f01')));

        wb.dispose();

        const expectedServices = <String>[
          'lib/services/project_archive_codec.dart',
          'lib/services/cloud_invite_deep_link_service.dart',
          'lib/services/v01_release_seeder.dart',
        ];
        for (final path in expectedServices) {
          final f = File(path);
          expect(f.existsSync(), isTrue, reason: '$path should exist');
          expect(f.readAsLinesSync().length, greaterThan(50));
        }

        for (final dirPath in const ['lib/providers', 'lib/services']) {
          for (final entity in Directory(dirPath).listSync(recursive: true)) {
            if (entity is File && entity.path.endsWith('.dart')) {
              final lineCount = entity.readAsLinesSync().length;
              expect(
                lineCount,
                lessThanOrEqualTo(950),
                reason: '${entity.path} has $lineCount lines',
              );
            }
          }
        }
      },
    );

    test(
      '24. Simulation #2 P1/P2 fixes: honest v0.2 baseline rollups/GDD, FPS Camera Fork sync, New Feature rename propagation, and non-combat offline synthesis',
      () async {
        // 1) Offline rooftop courier synthesis respects FPS + 90s + clean title + non-combat v0.2
        const courierSpark =
            'First-person UE5 rooftop parcel courier game where you sprint, wall-run, grapple-swing across rain-slick rooftops, and land intact parcel drops before a 90-second timer expires';
        final anglesOutcome = await SparkAngleAgent.proposeAngles(
          rawSpark: courierSpark,
          apiKey: '',
        );
        expect(anglesOutcome.deck, isNotNull);
        expect(
          anglesOutcome.deck!.angles.every((a) => a.viewChoiceId == 'fps'),
          isTrue,
        );
        expect(
          anglesOutcome.deck!.angles.last.sliceHint,
          contains('90s'),
        );

        final courierSpec = await ProjectConceptAgent.draftSpecFromSpark(
          sparkPrompt: anglesOutcome.deck!.buildSelectedHandoffPrompt(),
          apiKey: '',
        );
        expect(courierSpec.normalizedTitle, isNot(startsWith('FIRST PERSON')));
        expect(courierSpec.cameraChoiceId, equals('fps'));
        expect(courierSpec.pitch, isNot(contains('| Camera:')));
        expect(
          courierSpec.initialEpics.first.goal.toLowerCase(),
          isNot(contains('uspringarmcomponent')),
        );
        expect(
          courierSpec.initialEpics.first.sceneOwnership.any(
            (s) => s.role.toLowerCase().contains('uspringarmcomponent'),
          ),
          isFalse,
        );

        final v02Proposal = await ReleasePlannerAgent.proposeNextReleaseCopilot(
          rootSpec: courierSpec,
          currentEpics: courierSpec.initialEpics,
          targetVersion: 'v0.2',
          apiKey: '',
        );
        final v02Ups = v02Proposal.upgradesByLineageKey.values
            .expand((l) => l)
            .toList();
        final v02NewFeats = v02Proposal.candidateNewFeaturesByLineageKey.values
            .expand((l) => l)
            .toList();
        expect(
          v02Ups.any((u) => u.text.contains('Hit-Stop')),
          isFalse,
        );
        expect(
          v02NewFeats.first.title,
          equals('Momentum Vault & Quick Recover'),
        );
        expect(
          v02NewFeats.first.goal.toLowerCase(),
          isNot(contains('counters')),
        );

        // 2) Switching Camera Fork to FPS clears stale Third-Person / USpringArmComponent across E01, F01, pitch & v0.1 goal
        final wbCam = WorkbenchProvider(enableAutoLoad: false);
        wbCam.loadPresetSpark('shellbreaker');
        wbCam.conceptDraft!.pitch =
            'ROOFTOP RUN — Third-Person sprint | Camera: Third-Person Pursuit (tps)';
        wbCam.selectCameraDecisionOption('fps');
        final fpsE01 = wbCam.conceptDraft!.initialEpics.first;
        expect(wbCam.conceptDraft!.pitch, isNot(contains('| Camera:')));
        expect(wbCam.conceptDraft!.pitch, isNot(contains('Third-Person')));
        expect(fpsE01.goal.toLowerCase(), isNot(contains('uspringarmcomponent')));
        expect(
          fpsE01.sceneOwnership.any(
            (s) => s.role.toLowerCase().contains('uspringarmcomponent'),
          ),
          isFalse,
        );
        expect(
          fpsE01.features.first.goal.toLowerCase(),
          isNot(contains('uspringarmcomponent')),
        );
        wbCam.approveRootSpecAndLaunchWorkbench();
        expect(
          wbCam.activeRelease!.sections['goal'] ?? '',
          isNot(contains('Third-Person')),
        );
        wbCam.dispose();

        // 3) Quick-add New Feature rename updates starter inScope, doneWhen, checks & controls
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();
        final quickCreated = wb.quickAddSliceToActiveRelease()!;
        wb.updateFeatureScope(
          wb.selectedEpicId!,
          quickCreated.id,
          title: 'Storm Wind Gust Recovery',
        );
        final renamed = wb.selectedFeatureSpec!;
        expect(renamed.title, equals('Storm Wind Gust Recovery'));
        expect(renamed.inScope.join(' '), isNot(contains('New Feature')));
        expect(renamed.doneWhen.join(' '), contains('Storm Wind Gust Recovery'));
        expect(renamed.checks.first.text, contains('Storm Wind Gust Recovery'));
        expect(renamed.controls.first.rule, contains('Storm Wind Gust Recovery'));

        // 4) Passing only F01 in v0.1 and committing v0.2 does NOT count unpassed locked F02..F06 as passed
        final e01 = wb.activeReleaseEpics.first;
        final f01 = e01.features.firstWhere((f) => f.code == 'F01');
        for (final chk in f01.checks) {
          wb.toggleFeatureCheck(e01.id, f01.id, chk.id, true);
        }
        wb.passFeature(e01.id, f01.id);

        await wb.openProgressiveReleaseCopilot();
        wb.commitProgressiveReleaseDraft();
        expect(wb.activeReleaseVersionTag, equals('v0.2'));

        final v02Rollup = wb.activeReleaseFeatureRollup;
        expect(v02Rollup.passed, equals(1));
        expect(v02Rollup.total, greaterThan(6));

        final gdd = wb.buildCoPilotGddExport().content;
        expect(gdd, contains('[v0.1 ✓ BASELINE]'));
        expect(gdd, contains('[v0.1 BASELINE (OPEN)]'));

        final v02E01 = wb.activeReleaseEpics.first;
        final lockedOpenF07 =
            v02E01.features.firstWhere((f) => f.code == 'F07');
        final activeV02Feat = wb.activeReleaseEpics.last.features.first;
        final v02Readable = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: wb.conceptDraft!,
          epic: v02E01,
          feature: lockedOpenF07,
          releaseVersion: 'v0.2',
          releaseOrder: wb.projectReleaseOrder,
          compact: false,
        );
        expect(
          v02Readable,
          contains('Locked v0.1 baseline — open in v0.1, Viewing v0.2'),
        );
        expect(
          v02Readable,
          isNot(contains('Shipped in v0.1, Viewing v0.2')),
        );
        final compactWithKeep = UnrealPromptCompactor.buildCompactFeaturePrompt(
          rootSpec: wb.conceptDraft!,
          epic: v02E01,
          feature: v02E01.features.last,
          releaseVersion: 'v0.2',
          releaseOrder: wb.projectReleaseOrder,
        );
        expect(compactWithKeep, contains('KEEP=[F01]'));
        expect(compactWithKeep, isNot(contains('KEEP=[F01,F02')));
        expect(activeV02Feat.code, isNotEmpty);

        wb.dispose();
      },
    );

    test(
      '25. Core loop upgrades: guarded Feature delete + Undo, UE5 Version & Project Base serialization/prompts, pasteable [FIX] logs, and enriched GDD',
      () async {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.updateRootSpecSections(
          ueVersion: 'UE 5.6',
          ueProjectAnchor: 'Module: SkyhookGame · Extends BP_ThirdPersonCharacter',
        );

        // UE5 anchor round-trips cleanly via JSON & deepCopy
        final clonedRoot = ProjectConceptBlueprint.fromJson(
          wb.conceptDraft!.toJson(),
        );
        expect(clonedRoot.ueVersion, equals('UE 5.6'));
        expect(
          clonedRoot.ueProjectAnchor,
          equals('Module: SkyhookGame · Extends BP_ThirdPersonCharacter'),
        );
        final legacyRoot = ProjectConceptBlueprint.fromJson(<String, dynamic>{
          'gameTitle': 'LEGACY TEST',
        });
        expect(legacyRoot.ueVersion, equals('UE 5.5'));
        expect(legacyRoot.ueProjectAnchor, isEmpty);

        wb.approveRootSpecAndLaunchWorkbench();
        final e01 = wb.activeReleaseEpics.first;
        final passedF01 = e01.features.firstWhere((f) => f.code == 'F01');
        final openF02 = e01.features.firstWhere((f) => f.code == 'F02');

        // 1) Guarded delete blocks passed Features & sole remaining Features, allows unbuilt extra Features with Undo
        expect(wb.canDeleteFeature(e01, passedF01), isFalse);
        expect(wb.deleteUnbuiltFeature(e01.id, passedF01.id), isFalse);

        final singleEpic = wb.addEpicToActiveRelease(
          title: 'Single Arena Telemetry',
          goal: 'Track single greybox run time.',
        )!;
        expect(
          wb.canDeleteFeature(singleEpic, singleEpic.features.single),
          isFalse,
        );
        expect(
          wb.deleteUnbuiltFeature(singleEpic.id, singleEpic.features.single.id),
          isFalse,
        );

        final quickAdded = wb.quickAddSliceToActiveRelease(epicId: e01.id)!;
        final e01WithExtra =
            wb.activeReleaseEpics.firstWhere((e) => e.id == e01.id);
        final countBeforeDelete = e01WithExtra.features.length;
        expect(wb.canDeleteFeature(e01WithExtra, quickAdded), isTrue);
        expect(wb.deleteUnbuiltFeature(e01.id, quickAdded.id), isTrue);
        expect(
          wb.activeReleaseEpics
              .firstWhere((e) => e.id == e01.id)
              .features
              .length,
          equals(countBeforeDelete - 1),
        );
        expect(wb.selectedFeatureId, isNot(equals(quickAdded.id)));
        expect(wb.undoStage2Edit(), isTrue);
        expect(
          wb.activeReleaseEpics
              .firstWhere((e) => e.id == e01.id)
              .features
              .length,
          equals(countBeforeDelete),
        );
        // Clean up quickAdded before v0.2 check
        wb.deleteUnbuiltFeature(e01.id, quickAdded.id);

        // 2) Pasteable multi-line UE5 error log on [FIX] + self-contained @PROJECT & enriched GDD
        wb.flagFeatureFix(
          e01.id,
          openF02.id,
          'Dash overlap hits null collider',
          errorLog:
              'LogBlueprintUserMessages: Error: Accessed None trying to read property DashHitbox\nEnsure condition failed: DashHitbox != nullptr',
        );
        final e01Fixed = wb.activeReleaseEpics.first;
        final fixedF02 = e01Fixed.features.firstWhere((f) => f.id == openF02.id);
        final fixRoundTrip = EpicPieFix.fromJson(fixedF02.fixes.first.toJson());
        expect(
          fixRoundTrip.errorLog,
          contains('Accessed None trying to read property DashHitbox'),
        );

        final compactFixPrompt = wb.activeFeatureBuildPrompt(e01Fixed, fixedF02);
        expect(compactFixPrompt, contains('UE=UE 5.6'));
        expect(compactFixPrompt, contains('BASE=Module: SkyhookGame'));
        expect(compactFixPrompt, contains('SCALE='));
        expect(compactFixPrompt, contains('FEEL='));
        expect(compactFixPrompt, contains('ASSETS='));
        expect(compactFixPrompt, contains('@LOG:'));
        expect(
          compactFixPrompt,
          contains('Accessed None trying to read property DashHitbox'),
        );

        final readableFixPrompt =
            wb.activeFeatureReadablePrompt(e01Fixed, fixedF02);
        expect(readableFixPrompt, contains('```text'));
        expect(
          readableFixPrompt,
          contains('Ensure condition failed: DashHitbox != nullptr'),
        );

        final gdd = wb.buildCoPilotGddExport().content;
        expect(gdd, contains('UE 5.6'));
        expect(gdd, contains('Base: Module: SkyhookGame'));
        expect(gdd, contains('- Inputs:'));
        expect(gdd, contains('- Gate:'));
        expect(compactFixPrompt, contains('@VARS'));

        // 3) Locked v0.1 baselines cannot be deleted from v0.2
        await wb.openProgressiveReleaseCopilot();
        wb.commitProgressiveReleaseDraft();
        final v02E02 = wb.activeReleaseEpics[1];
        final lockedV01Feat = v02E02.features.first;
        expect(wb.canDeleteFeature(v02E02, lockedV01Feat), isFalse);
        expect(wb.deleteUnbuiltFeature(v02E02.id, lockedV01Feat.id), isFalse);

        wb.dispose();
      },
    );
  });
}
