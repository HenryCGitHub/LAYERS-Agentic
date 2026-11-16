import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/agents/project_concept_agent.dart';
import 'package:layers_agentic/constants/tiers.dart';
import 'package:layers_agentic/main.dart';
import 'package:layers_agentic/models/agent_blueprints.dart';
import 'package:layers_agentic/models/epic_spec.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/project_pitch_screen.dart';
import 'package:layers_agentic/screens/release_workbench_screen.dart';
import 'package:layers_agentic/screens/widgets/unreal_bridge_modals.dart';
import 'package:layers_agentic/theme/app_theme.dart';
import 'package:layers_agentic/utils/unreal_mcp_payload_builder.dart';
import 'package:layers_agentic/utils/unreal_spec_guard.dart';

void main() {
  group('Unreal-Only 3-Tier Spec Studio & LayersBridge', () {
    test(
      '1. 3-tier hierarchy strictly excludes legacy Feature & Task sub-tickets',
      () {
        expect(
          TierType.values,
          equals([TierType.project, TierType.release, TierType.epic]),
        );
        expect(TierDocument.isLegacyIgnoredTier({'tier': 'feature'}), isTrue);
        expect(TierDocument.isLegacyIgnoredTier({'tier': 'task'}), isTrue);
        expect(TierDocument.isLegacyIgnoredTier({'tier': 'EPIC'}), isFalse);
        expect(TierDocument.isLegacyIgnoredTier({'tier': 'release'}), isFalse);
        expect(TierDocument.isLegacyIgnoredTier({'tier': 'project'}), isFalse);
      },
    );

    test(
      '2. UnrealSpecGuard strips Godot tokens, normalizes 1 UU = 1 cm units, and clamps v0.1 Epics',
      () {
        expect(
          UnrealSpecGuard.containsGodotLeakage(
            'Use CharacterBody3D inside res://arena.tscn with _physics_process',
          ),
          isTrue,
        );
        final sanitized = UnrealSpecGuard.sanitizeLine(
          'Godot CharacterBody3D moves in arena.tscn with player.gd _physics_process',
        );
        expect(sanitized.toLowerCase(), isNot(contains('godot')));
        expect(sanitized, isNot(contains('CharacterBody3D')));
        expect(sanitized, contains('Unreal Engine'));
        expect(sanitized, contains('ACharacter'));
        expect(sanitized, contains('Tick'));

        expect(
          UnrealSpecGuard.normalizeUnrealUnit('WalkSpeed', 'px'),
          equals('cm'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('DashSpeed', ''),
          equals('cm/s'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('DashDistance', ''),
          equals('cm'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('FOVAngle', ''),
          equals('deg'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('CooldownSec', ''),
          equals('s'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('ArmorHP', ''),
          equals('hp'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('DamageMult', ''),
          equals('x'),
        );

        final dirtyBlueprint = ProjectConceptBlueprint(
          gameTitle: 'Godot Test Game',
          pitch: 'Control CharacterBody3D cleanly and seamlessly.',
          cameraContract: 'Godot Camera2D boom',
          inputContract: 'GDScript InputMap',
          initialEpics: [
            EpicSpec(
              id: 'ep_1',
              code: 'e01',
              title: 'Player Move in player.gd',
              releaseVersion: 'v0.4',
              goal: 'Smooth Godot movement',
              tuning: [
                EpicTuningParam(key: 'MoveSpeed', value: '600', unit: 'px'),
              ],
              checks: [
                EpicPieCheck(id: 'c1', text: 'Run test in arena.tscn'),
              ],
            ),
          ],
        );

        final cleanBp = UnrealSpecGuard.sanitizeConceptBlueprint(dirtyBlueprint);
        expect(cleanBp.initialEpics, hasLength(1));
        expect(cleanBp.initialEpics.first.releaseVersion, equals('v0.1'));
        expect(cleanBp.initialEpics.first.code, equals('E01'));
        expect(cleanBp.initialEpics.first.tuning.first.unit, equals('cm'));
        expect(UnrealSpecGuard.containsGodotLeakage(cleanBp.pitch), isFalse);
      },
    );

    test(
      '3. EpicSpec lossless TierDocument round-trip preserves §01–§06 + fixes + tuning',
      () {
        final original = EpicSpec(
          id: 'epic_rt_1',
          code: 'E02',
          lineageKey: 'e02',
          title: 'Claw Shotgun & Hitstop',
          releaseVersion: 'v0.1',
          lifecycle: EpicLifecycle.active,
          goal: 'Instant spread blast with 0.06s hitstop feedback.',
          links: ['BP_CrabPlayer -> BP_ProjectilePellet'],
          outOfScope: ['No weapon inventory menu'],
          controls: [
            EpicControlBinding(
              action: 'IA_Primary',
              trigger: 'Started (Press)',
              rule: 'Fire 6 trace/projectile pellets in a 22 deg cone',
            ),
          ],
          states: ['Ready -> Firing -> Cooldown'],
          interrupts: ['Dash cancels reload recovery'],
          tuning: [
            EpicTuningParam(key: 'PelletSpeed', value: '1850', unit: 'cm/s'),
            EpicTuningParam(key: 'ConeSpread', value: '22', unit: 'deg'),
          ],
          feedback: ['Hitstop 0.06 s + white emissive flash'],
          levelStaging: 'L_Arena_Proto -> Spawn 2 BP_TrainingTarget actors',
          checks: [
            EpicPieCheck(
              id: 'c1',
              text: 'IA_Primary fires 6 pellets',
              passed: true,
            ),
            EpicPieCheck(
              id: 'c2',
              text: 'Enemy flash triggers on hit',
              passed: false,
            ),
          ],
          fixes: [
            EpicPieFix(
              id: 'fix_1',
              text: 'Spread ray misses close cubes inside 45 cm',
              resolved: false,
            ),
          ],
          baselineSummary: ['v0.1 locked base'],
          upgradeDeltas: ['+Alt-fire slug shot'],
        );

        final doc = original.toTierDocument(
          docId: 'epic_rt_1',
          parentReleaseId: 'rel_v01',
        );
        expect(doc.tier, equals(TierType.epic));
        expect(doc.subtasks, hasLength(2));
        expect(doc.subtasks.first.completed, isTrue);

        final restored = EpicSpec.fromDocument(doc, indexHint: 1);
        expect(restored.code, equals('E02'));
        expect(restored.title, equals('Claw Shotgun & Hitstop'));
        expect(restored.tuning.first.value, equals('1850'));
        expect(restored.tuning.first.unit, equals('cm/s'));
        expect(restored.controls.single.action, equals('IA_Primary'));
        expect(restored.checks[0].passed, isTrue);
        expect(restored.checks[1].passed, isFalse);
        expect(restored.openFixesCount, equals(1));
        expect(restored.upgradeDeltas, equals(['+Alt-fire slug shot']));
      },
    );

    test(
      '4. UnrealMcpPayloadBuilder switches cleanly between Full-Epic & Focused PIE Revision Pass + injects .uproject context',
      () {
        final spec = UnrealSparkPresets.byId('shellbreaker');
        final e01 = spec.initialEpics.first.deepCopy();
        final liveCtx = <String, dynamic>{
          'project_name': 'ShellbreakerUE5',
          'current_level': 'L_Arena_Proto',
          'game_mode': 'GM_Shellbreaker',
          'default_pawn': 'BP_CrabPlayer',
          'input_assets': ['/Game/Input/IMC_Core', '/Game/Input/IA_Move'],
          'recent_errors': ['LogBlueprint: Warning on BP_TestDummy'],
        };

        final fullPayload = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: spec,
          epic: e01,
          liveUprojectContext: liveCtx,
        );
        expect(fullPayload, contains('# ROOT_MCP_CONTEXT · SHELLBREAKER'));
        expect(
          fullPayload,
          contains(
            '## Live Unreal Project Snapshot (.uproject via LayersBridge)',
          ),
        );
        expect(fullPayload, contains('ShellbreakerUE5'));
        expect(fullPayload, contains('/Game/Input/IMC_Core'));
        expect(
          fullPayload,
          contains('### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK'),
        );

        final ue6Payload = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: spec,
          epic: e01,
          targetOverride: UnrealTargetEngine.ue6Verse,
        );
        expect(
          ue6Payload,
          contains(
            'Verse Components + Scene Graph Entities (@editable exposed fields)',
          ),
        );
        expect(ue6Payload, contains('@editable Verse Field'));

        e01.fixes.add(
          EpicPieFix(
            id: 'fx1',
            text: 'Camera SpringArm clips floor ramp during dash',
            resolved: false,
          ),
        );
        final fixPayload = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: spec,
          epic: e01,
        );
        expect(fixPayload, contains('## Open Playtest Revisions ([FIX])'));
        expect(
          fixPayload,
          contains('### FOCUSED PIE REVISION PASS (1 OPEN [FIX])'),
        );
        expect(
          fixPayload,
          contains('Camera SpringArm clips floor ramp during dash'),
        );
      },
    );

    testWidgets(
      '5. Unified Single-Space Stage 1: Idea intake + empty §01-§05 outline -> live Blueprint, Camera/Feel forks, Top Refine bar & Approve -> Stage 2',
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
        expect(
          find.byKey(const ValueKey('spark_prompt_input')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('draft_spark_btn')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('stage1_blueprint_empty_outline')),
          findsOneWidget,
        );
        expect(
          find.text('PROJECT BLUEPRINT PREVIEW · §01–§05'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('preset_pill_shellbreaker')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('preset_pill_railjack')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('preset_pill_emberkeep')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('stage1_unified_refine_bar')),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const ValueKey('spark_prompt_input')),
          'Top-down crustacean mech brawler with claw dash armor breaks',
        );
        await tester.tap(find.byKey(const ValueKey('draft_spark_btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('spark_prompt_input')), findsNothing);
        expect(
          find.byKey(const ValueKey('stage1_unified_refine_bar')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('stage1_codesign_input')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('stage1_codesign_apply_btn')),
          findsOneWidget,
        );
        expect(wb.conceptDraft?.normalizedTitle, equals('SHELLBREAKER'));
        expect(
          wb.conceptDraft?.initialEpics.every((e) => e.releaseVersion == 'v0.1'),
          isTrue,
        );

        await tester.tap(find.byKey(const ValueKey('stage1_target_ue6')));
        await tester.pumpAndSettle();
        expect(wb.targetEngine, equals(UnrealTargetEngine.ue6Verse));

        await tester.tap(find.byKey(const ValueKey('stage1_tab_raw')));
        await tester.pumpAndSettle();
        expect(wb.showRawRootContext, isTrue);
        expect(
          find.textContaining(
            'Target Architecture: Verse Components + Scene Graph Entities',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('Core Feel: Snappy Arcade'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('stage1_tab_clean')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('camera_opt_isometric')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('camera_opt_topdown')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('camera_opt_tps')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('camera_opt_fps')),
          findsOneWidget,
        );

        await tester.ensureVisible(find.byKey(const ValueKey('camera_opt_fps')));
        await tester.tap(find.byKey(const ValueKey('camera_opt_fps')));
        await tester.pumpAndSettle();
        expect(wb.conceptDraft?.cameraChoiceId, equals('fps'));
        expect(
          wb.conceptDraft?.cameraContract,
          contains('First-Person Camera'),
        );
        expect(wb.conceptDraft?.inputContract, contains('IA_Look'));
        expect(
          wb.conceptDraft?.initialEpics.first.controls.any(
            (c) => c.action.contains('IA_Look'),
          ),
          isTrue,
        );

        await tester.ensureVisible(find.byKey(const ValueKey('camera_opt_tps')));
        await tester.tap(find.byKey(const ValueKey('camera_opt_tps')));
        await tester.pumpAndSettle();
        expect(wb.conceptDraft?.cameraChoiceId, equals('tps'));
        expect(wb.conceptDraft?.cameraContract, contains('SpringArm 380 cm'));

        await tester.ensureVisible(find.byKey(const ValueKey('feel_opt_heavy')));
        await tester.tap(find.byKey(const ValueKey('feel_opt_heavy')));
        await tester.pumpAndSettle();
        expect(wb.conceptDraft?.feelChoiceId, equals('heavy'));
        expect(
          wb.conceptDraft?.tradeOffs.first.prefer,
          equals('Committed heavy windups'),
        );
        expect(
          wb.conceptDraft?.initialEpics.first.tuning.first.key,
          equals('MoveSpeed'),
        );
        expect(
          wb.conceptDraft?.initialEpics.first.tuning.last.key,
          equals('BrakingDecel'),
        );
        expect(
          wb.conceptDraft?.initialEpics.first.tuning.last.value,
          equals('1400'),
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('feel_opt_physics')),
        );
        await tester.tap(find.byKey(const ValueKey('feel_opt_physics')));
        await tester.pumpAndSettle();
        expect(wb.conceptDraft?.feelChoiceId, equals('physics'));
        expect(
          wb.conceptDraft?.tradeOffs.first.prefer,
          equals('Velocity carry & drift banking'),
        );

        final prevMock = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, model) async {
          if (prompt.contains('USER CO-DESIGN INSTRUCTION')) {
            final draftJson = wb.conceptDraft!.toJson();
            draftJson['gameTitle'] = 'SHELLBREAKER TURBO';
            draftJson['coDesignNote'] = 'Raised walk speed to 700 cm/s.';
            return draftJson;
          }
          return null;
        };
        try {
          wb.updateAiConfig(apiKey: 'mock-key-1234');
          await tester.ensureVisible(
            find.byKey(const ValueKey('stage1_unified_refine_bar')),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('stage1_codesign_input')),
            'Make it faster',
          );
          await tester.tap(
            find.byKey(const ValueKey('stage1_codesign_apply_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.conceptDraft?.gameTitle, equals('SHELLBREAKER TURBO'));
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
        }

        await tester.tap(
          find.byKey(const ValueKey('approve_launch_workbench_btn')),
        );
        await tester.pumpAndSettle();

        expect(wb.currentStage, equals(WorkbenchStage.releaseWorkbench));
        expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);
        expect(wb.activeReleaseEpics, hasLength(3));
        expect(wb.selectedEpicSpec?.code, equals('E01'));
      },
    );

    testWidgets(
      '6. Stage 1 Custom Spark submission via mock Gemini creates v0.1 Unreal spec cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.updateAiConfig(apiKey: 'mock-key-1234');

        final prevMock = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, model) async {
          if (prompt.contains('USER SPARK:')) {
            return {
              'gameTitle': 'SKYFORGE DART',
              'pitch':
                  'Glide between floating ruins tagging beacons before storms hit.',
              'coreLoop': [
                'Launch -> Ride thermal updrafts',
                'Strike -> Shatter weather nodes',
              ],
              'cameraChoiceId': 'tps',
              'cameraContract': 'SpringArm 420 cm · 72 deg FOV · CameraLag 8.0',
              'characterScale':
                  'ACharacter CapsuleRadius 40 cm · MaxWalkSpeed 680 cm/s',
              'inputContract': 'Enhanced Input (IMC_Sky + IA_Glide / IA_Boost)',
              'assetPolicy': 'Greybox primitives + UDataAsset flight table',
              'pillars': ['Weightless Flow: Maintain speed cleanly through turns'],
              'tradeOffs': [
                {'prefer': 'Forgiving glide lift', 'avoid': 'Stall spin punishment'},
              ],
              'outOfScope': ['No procedural weather biomes in v0.1'],
              'releaseDoneWhen':
                  'Launch off pad, glide through 5 rings -> land safely in L_Sky_Proto',
              'initialEpics': [
                {
                  'code': 'E01',
                  'title': 'Glider Wings & Updrafts',
                  'goal':
                      'Hold jump in mid-air to deploy glider wings and gain thermal lift.',
                  'links': ['BP_GliderPawn -> IMC_Sky'],
                  'outOfScope': ['No wing skins'],
                  'controls': [
                    {
                      'action': 'IA_Glide',
                      'trigger': 'Triggered (Hold)',
                      'rule': 'Cap fall Z at -180 cm/s',
                    },
                  ],
                  'states': ['Freefall -> Gliding -> Landed'],
                  'interrupts': ['Touching ground cancels Gliding immediately'],
                  'tuning': [
                    {'key': 'GlideSpeed', 'value': '1250', 'unit': 'cm/s'},
                  ],
                  'feedback': ['Air trail ribbons at wingtips'],
                  'levelStaging':
                      'L_Sky_Proto -> Floating launch platform + updraft cylinder',
                  'checks': [
                    {
                      'text':
                          'Hold IA_Glide -> Pawn glides cleanly across 3000 cm gap',
                    },
                  ],
                },
              ],
            };
          }
          return null;
        };

        try {
          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.byKey(const ValueKey('spark_prompt_input')),
            'Wing-suit glider game between sky ruins',
          );
          await tester.tap(find.byKey(const ValueKey('draft_spark_btn')));
          await tester.pumpAndSettle();

          expect(wb.showingSparkPicker, isFalse);
          expect(wb.conceptDraft?.gameTitle, equals('SKYFORGE DART'));
          expect(
            wb.conceptDraft?.initialEpics.single.title,
            equals('Glider Wings & Updrafts'),
          );
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
        }
      },
    );

    testWidgets(
      '7. Stage 2 Epic Specs: live §04 tuning edit updates Exact Unreal MCP Payload, PIE Checks, Flag [FIX], Resolve & Pass Epic ✓',
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
        final e01Id = wb.selectedEpicId!;
        final e01 = wb.selectedEpicSpec!;

        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        // 1. Live edit §04 Tuning variable & verify immediate reflection in Exact Unreal MCP Payload tab
        final tuningInput = find.byKey(ValueKey('tuning_input_${e01Id}_0'));
        await tester.ensureVisible(tuningInput);
        await tester.enterText(tuningInput, '888');
        await tester.pump();
        expect(wb.selectedEpicSpec!.tuning.first.value, equals('888'));

        await tester.tap(find.byKey(const ValueKey('stage2_tab_raw')));
        await tester.pumpAndSettle();
        final rawText = tester.widget<SelectableText>(
          find.byKey(const ValueKey('raw_epic_mcp_payload_text')),
        );
        expect(rawText.data, contains('888'));
        expect(
          rawText.data,
          contains('### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK'),
        );

        await tester.tap(find.byKey(const ValueKey('stage2_tab_clean')));
        await tester.pumpAndSettle();

        // 2. Toggle PIE Check 1
        final firstCheckId = e01.checks.first.id;
        final checkFinder = find.byKey(ValueKey('pie_check_$firstCheckId'));
        await tester.ensureVisible(checkFinder);
        await tester.tap(checkFinder);
        await tester.pumpAndSettle();
        expect(wb.selectedEpicSpec!.checks.first.passed, isTrue);

        // 3. Flag [FIX] -> updates raw payload to FOCUSED PIE REVISION PASS
        final fixInputFinder = find.byKey(const ValueKey('flag_fix_input'));
        await tester.ensureVisible(fixInputFinder);
        await tester.enterText(
          fixInputFinder,
          'Crab dash clips sand ramp corner',
        );
        await tester.tap(find.byKey(const ValueKey('flag_fix_btn')));
        await tester.pumpAndSettle();

        expect(wb.selectedEpicSpec!.openFixesCount, equals(1));
        final fixId = wb.selectedEpicSpec!.openFixes.first.id;
        expect(
          wb.activeEpicMcpPayload(wb.selectedEpicSpec!),
          contains('### FOCUSED PIE REVISION PASS (1 OPEN [FIX])'),
        );

        // 4. Resolve [FIX]
        final resolveBtn = find.byKey(ValueKey('resolve_fix_$fixId'));
        await tester.ensureVisible(resolveBtn);
        await tester.tap(resolveBtn);
        await tester.pumpAndSettle();
        expect(wb.selectedEpicSpec!.openFixesCount, equals(0));

        // 5. Pass Epic ✓ -> advances to E02; Reopen returns to Active
        final passBtn = find.byKey(const ValueKey('pass_epic_btn'));
        await tester.ensureVisible(passBtn);
        await tester.tap(passBtn);
        await tester.pumpAndSettle();

        expect(wb.selectedEpicId, isNot(equals(e01Id)));
        expect(wb.selectedEpicSpec?.code, equals('E02'));

        // Switch back to E01 via outliner and Reopen
        await tester.tap(find.byKey(ValueKey('outliner_epic_$e01Id')));
        await tester.pumpAndSettle();
        expect(wb.selectedEpicSpec?.isPassed, isTrue);

        await tester.ensureVisible(find.byKey(const ValueKey('reopen_epic_btn')));
        await tester.tap(find.byKey(const ValueKey('reopen_epic_btn')));
        await tester.pumpAndSettle();
        expect(wb.selectedEpicSpec?.isPassed, isFalse);
      },
    );

    testWidgets(
      '8. Progressive v0.2 Release Co-Pilot merges non-destructively (Baseline ✓ vs Upgrading + NEW Epics)',
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

        await tester.tap(find.byKey(const ValueKey('plan_next_release_btn')));
        await tester.pumpAndSettle();

        expect(wb.progressiveDraft, isNotNull);
        expect(wb.progressiveDraft!.targetVersion, equals('v0.2'));
        expect(wb.progressiveDraft!.presets, isNotEmpty);

        final firstPresetId = wb.progressiveDraft!.presets.first.id;
        await tester.tap(find.byKey(ValueKey('copilot_preset_$firstPresetId')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('copilot_commit_btn')));
        await tester.pumpAndSettle();

        expect(wb.activeReleaseVersionTag, equals('v0.2'));
        final v02Epics = wb.activeReleaseEpics;
        expect(v02Epics.length, greaterThanOrEqualTo(3));
        expect(
          v02Epics.any(
            (e) =>
                e.lifecycle == EpicLifecycle.upgrading ||
                e.lifecycle == EpicLifecycle.newEpic,
          ),
          isTrue,
        );
        expect(
          v02Epics.any((e) => e.lifecycle == EpicLifecycle.stable),
          isTrue,
        );
      },
    );

    testWidgets(
      '9. Connect Unreal MCP & LayersBridge dialog fetches/rotates lyr_... token via /unrealLink/token',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final prevHttp = GeminiAgentClient.testHttpPost;
        final prevAuthProvider = GeminiAgentClient.authTokenProvider;
        int callCount = 0;

        GeminiAgentClient.authTokenProvider =
            ({bool forceRefresh = false}) async => 'fake-firebase-id-token';
        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
          if (uri.path.endsWith('/unrealLink/token')) {
            callCount += 1;
            final decoded = body is String && body.isNotEmpty
                ? jsonDecode(body) as Map<String, dynamic>
                : const <String, dynamic>{};
            final rotate = decoded['rotate'] == true;
            return http.Response(
              jsonEncode({
                'ok': true,
                'projectId': decoded['projectId'] ?? 'proj_test',
                'linkToken': rotate
                    ? 'lyr_rotated_unreal_token_999988887777'
                    : 'lyr_initial_unreal_token_111122223333',
              }),
              200,
            );
          }
          return http.Response('{"error":{"message":"Not found"}}', 404);
        };

        try {
          final wb = WorkbenchProvider(enableAutoLoad: false);
          wb.loadPresetSpark('shellbreaker');
          wb.approveRootSpecAndLaunchWorkbench();

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      key: const ValueKey('open_modal_btn'),
                      onPressed: () => showConnectUnrealPluginDialog(ctx, wb),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.byKey(const ValueKey('open_modal_btn')));
          await tester.pumpAndSettle();

          expect(
            find.text('Connect Unreal MCP & LayersBridge'),
            findsOneWidget,
          );
          expect(
            find.textContaining('layers_update_epic_tuning'),
            findsOneWidget,
          );
          expect(
            find.textContaining('layers_toggle_pie_check'),
            findsOneWidget,
          );
          expect(
            find.text('lyr_initial_unreal_token_111122223333'),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('copy_unreal_setup_py_btn')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('copy_unreal_setup_py_btn')),
          );
          await tester.pumpAndSettle();
          expect(callCount, equals(1));

          await tester.tap(find.byKey(const ValueKey('rotate_unreal_token_btn')));
          await tester.pumpAndSettle();

          expect(
            find.text('lyr_rotated_unreal_token_999988887777'),
            findsOneWidget,
          );
          expect(callCount, equals(2));
        } finally {
          GeminiAgentClient.testHttpPost = prevHttp;
          GeminiAgentClient.authTokenProvider = prevAuthProvider;
        }
      },
    );

    test(
      '10. Stage 1 Epics carry coreLoopBeat provenance into MCP payload & offline spark detects framing',
      () async {
        final shellbreaker = UnrealSparkPresets.byId('shellbreaker');
        expect(shellbreaker.initialEpics.first.coreLoopBeat, isNotEmpty);
        final payload = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: shellbreaker,
          epic: shellbreaker.initialEpics.first,
        );
        expect(
          payload,
          contains(
            '- Core Loop Beat: ${shellbreaker.initialEpics.first.coreLoopBeat}',
          ),
        );

        final customSpec = await ProjectConceptAgent.draftSpecFromSpark(
          sparkPrompt:
              'Third-person grappling hook glider game with deployable jump pads',
          apiKey: '',
        );
        expect(customSpec.cameraChoiceId, equals('tps'));
        expect(customSpec.initialEpics.length, inInclusiveRange(2, 4));
        expect(
          customSpec.initialEpics.every((e) => e.coreLoopBeat.isNotEmpty),
          isTrue,
        );
        expect(
          customSpec.initialEpics.first.controls
              .any((c) => c.action.contains('IA_Look')),
          isTrue,
        );
      },
    );

    test(
      '11. Selecting a Stage 1 Camera Decision syncs E01 controls, checks & tail tuning without shifting index 0',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final beforeE01 = wb.conceptDraft!.initialEpics.first;
        expect(beforeE01.tuning.first.key, equals('MoveSpeed'));

        wb.selectCameraDecisionOption('tps');
        final afterE01 = wb.conceptDraft!.initialEpics.first;
        expect(afterE01.tuning.first.key, equals('MoveSpeed'));
        expect(
          afterE01.tuning
              .firstWhere((t) => t.key == 'SpringArmLength')
              .value,
          equals('380'),
        );
        expect(
          afterE01.tuning.firstWhere((t) => t.key == 'CameraFOV').value,
          equals('68'),
        );
        expect(
          afterE01.controls.any((c) => c.action.contains('IA_Look')),
          isTrue,
        );
        expect(
          afterE01.checks.any(
            (c) =>
                c.text.toLowerCase().contains('springarm') ||
                c.text.toLowerCase().contains('reticle'),
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      '12. Stage 1 §05 reorder/remove controls preserve lineageKey & drive active Epic order in Stage 2',
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

        final down0 = find.byKey(const ValueKey('stage1_epic_down_0'));
        await tester.ensureVisible(down0);
        await tester.tap(down0);
        await tester.pumpAndSettle();

        expect(wb.conceptDraft!.initialEpics[0].code, equals('E01'));
        expect(wb.conceptDraft!.initialEpics[0].lineageKey, equals('e02'));
        expect(
          wb.conceptDraft!.initialEpics[0].title,
          equals('Twin-Stick Burst Cannon & Recoil'),
        );
        expect(wb.conceptDraft!.initialEpics[1].code, equals('E02'));
        expect(wb.conceptDraft!.initialEpics[1].lineageKey, equals('e01'));

        final remove2 = find.byKey(const ValueKey('stage1_epic_remove_2'));
        await tester.ensureVisible(remove2);
        await tester.tap(remove2);
        await tester.pumpAndSettle();
        expect(wb.conceptDraft!.initialEpics, hasLength(2));

        await tester.tap(
          find.byKey(const ValueKey('approve_launch_workbench_btn')),
        );
        await tester.pumpAndSettle();
        expect(wb.activeReleaseEpics, hasLength(2));
        expect(wb.selectedEpicSpec?.lineageKey, equals('e02'));
      },
    );

    test(
      '13. Re-approving edited Stage 1 Spec performs non-destructive lineage sync into existing v0.1 Epics',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final relId = wb.approveRootSpecAndLaunchWorkbench()!;

        final initialEpics = wb.epicsForRelease(relId);
        expect(initialEpics, hasLength(3));
        final e01DocId = initialEpics[0].id;
        final e02DocId = initialEpics[1].id;

        // Pass E01, check Check 1 & flag 1 open [FIX] on E02, keep E03 untouched
        wb.passActiveEpic(e01DocId);
        wb.togglePieCheck(e02DocId, initialEpics[1].checks.first.id, true);
        wb.flagEpicFix(e02DocId, 'Spread bolts clip pillars');

        // Go back to Stage 1, edit E02, remove untouched E03, add a new v0.1 Epic E04
        wb.setStage(WorkbenchStage.projectPitch);
        final draft = wb.conceptDraft!;
        draft.initialEpics[1].goal = 'Updated burst cannon goal from Stage 1.';
        draft.initialEpics[1].tuning.first.value = '2950';
        draft.initialEpics.removeAt(2);
        draft.initialEpics.add(
          EpicSpec(
            id: 'sb_e04_turret',
            code: 'E03',
            lineageKey: 'e04_turret',
            title: 'Deployable Crab Decoy',
            goal: 'Drop decoy turret that pulls grunt threat for 4.0s.',
            checks: [
              EpicPieCheck(
                id: 'decoy_c1',
                text: 'Drop decoy -> nearby grunt targets decoy cleanly',
              ),
            ],
          ),
        );

        wb.approveRootSpecAndLaunchWorkbench();

        final synced = wb.epicsForRelease(relId);
        expect(synced, hasLength(3));

        // E01 stays passed
        expect(synced[0].isPassed, isTrue);

        // E02 receives Stage 1 updates while preserving passed check + open [FIX]
        expect(
          synced[1].goal,
          equals('Updated burst cannon goal from Stage 1.'),
        );
        expect(synced[1].tuning.first.value, equals('2950'));
        expect(synced[1].checks.first.passed, isTrue);
        expect(synced[1].openFixesCount, equals(1));
        expect(synced[1].openFixes.first.text, equals('Spread bolts clip pillars'));

        // Untouched E03 was pruned and replaced by the new Stage 1 Epic
        expect(synced[2].lineageKey, equals('e04_turret'));
        expect(synced[2].code, equals('E03'));
        expect(wb.selectedEpicId, equals(synced[1].id));
      },
    );

    test(
      '14. ReleasePlannerAgent passes Stage 1 §01-§04 Core Loop, Camera, Input & Hard Scope Cuts to Gemini',
      () async {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();
        wb.updateAiConfig(apiKey: 'mock-key-1234');

        String capturedPrompt = '';
        final prevMock = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, model) async {
          capturedPrompt = prompt;
          return {
            'presets': [
              {
                'id': 'p1',
                'label': 'Test Preset',
                'desc': 'Add dash upgrade',
                'upgrades': ['up_1'],
                'newEpics': ['E04'],
              },
            ],
            'upgrades': [],
            'newEpics': [],
          };
        };

        try {
          await wb.openProgressiveReleaseCopilot();
          expect(capturedPrompt, contains('Core Loop (§01):'));
          expect(capturedPrompt, contains('Camera Contract (§02):'));
          expect(capturedPrompt, contains('Input Contract (§02):'));
          expect(capturedPrompt, contains('Design Pillars (§03):'));
          expect(capturedPrompt, contains('Trade-Offs (§03):'));
          expect(
            capturedPrompt,
            contains('Hard Scope Cuts — DO NOT VIOLATE (§04):'),
          );
          expect(capturedPrompt, contains('No main menu, title screen'));
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
        }
      },
    );

    test(
      '15. Reopening a passed v0.2 Upgrading Epic preserves locked v0.1 baseline checks & restores upgrading lifecycle',
      () async {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();
        await wb.openProgressiveReleaseCopilot();
        final presetId = wb.progressiveDraft!.presets.first.id;
        wb.applyProgressivePreset(presetId);
        wb.commitProgressiveReleaseDraft();

        final upgradingEpic = wb.activeReleaseEpics.firstWhere(
          (e) => e.lifecycle == EpicLifecycle.upgrading,
        );
        expect(upgradingEpic.upgradeDeltas, isNotEmpty);
        expect(
          upgradingEpic.checks.any(
            (c) => !c.id.contains('_delta_') && c.passed,
          ),
          isTrue,
        );
        expect(
          upgradingEpic.checks.any(
            (c) => c.id.contains('_delta_') && !c.passed,
          ),
          isTrue,
        );

        // Pass the upgrading Epic (all checks true, lifecycle -> stable)
        wb.passActiveEpic(upgradingEpic.id);
        final passedSpec = wb.epicsForRelease(wb.activeReleaseId!).firstWhere(
              (e) => e.id == upgradingEpic.id,
            );
        expect(passedSpec.isPassed, isTrue);
        expect(passedSpec.lifecycle, equals(EpicLifecycle.stable));

        // Reopen -> restores EpicLifecycle.upgrading, keeps locked baseline checks passed, resets delta checks only
        wb.reopenEpic(upgradingEpic.id);
        final reopened = wb.epicsForRelease(wb.activeReleaseId!).firstWhere(
              (e) => e.id == upgradingEpic.id,
            );
        expect(reopened.lifecycle, equals(EpicLifecycle.upgrading));
        expect(reopened.isPassed, isFalse);
        final baselineChecks = reopened.checks
            .where((c) => !c.id.contains('_delta_'))
            .toList();
        final deltaChecks = reopened.checks
            .where((c) => c.id.contains('_delta_'))
            .toList();
        expect(baselineChecks, isNotEmpty);
        expect(baselineChecks.every((c) => c.passed), isTrue);
        expect(deltaChecks, isNotEmpty);
        expect(deltaChecks.every((c) => !c.passed), isTrue);
      },
    );

    test(
      '16. Pre-launch Stage 1 exports include v0.1 initialEpics & Stage 1 re-approve preserves active v0.2+ release focus',
      () async {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');

        final preLaunchFull =
            UnrealMcpPayloadBuilder.buildFullProjectSpecMarkdown(
          rootSpec: wb.conceptDraft!,
          epicsByReleaseLabel: const {},
        );
        expect(preLaunchFull, contains('## Release v0.1 · Prototype'));
        expect(
          preLaunchFull,
          contains('# ACTIVE EPIC SPEC · E01 · Player Mech Movement & Claw Dash'),
        );

        final preLaunchBundle = UnrealMcpPayloadBuilder.buildReleaseMcpBundle(
          rootSpec: wb.conceptDraft!,
          releaseLabel: 'v0.1 · Prototype',
          releaseEpics: wb.activeReleaseEpics,
        );
        expect(
          preLaunchBundle,
          contains('# ACTIVE RELEASE BUNDLE · v0.1 · Prototype'),
        );
        expect(
          preLaunchBundle,
          contains('# ACTIVE EPIC SPEC · E01 · Player Mech Movement & Claw Dash'),
        );

        wb.approveRootSpecAndLaunchWorkbench();
        await wb.openProgressiveReleaseCopilot();
        wb.applyProgressivePreset(wb.progressiveDraft!.presets.first.id);
        final v02RelId = wb.commitProgressiveReleaseDraft()!;
        final v02EpicId = wb.selectedEpicId!;

        wb.setStage(WorkbenchStage.projectPitch);
        wb.updateRootSpecSections(pitch: 'Updated global vision for v0.2');
        wb.approveRootSpecAndLaunchWorkbench();

        expect(wb.activeReleaseId, equals(v02RelId));
        expect(wb.activeReleaseVersionTag, equals('v0.2'));
        expect(wb.selectedEpicId, equals(v02EpicId));
        expect(
          wb.activeRootMcpMarkdown,
          contains('Updated global vision for v0.2'),
        );
      },
    );

    test(
      '17. duplicateProject & collision importProjectFromJson clear stale last_unreal_sync_ms and remap embedded epic_spec_json IDs',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();

        wb.activeProject!.sections['last_unreal_sync_ms'] = '1700000000000';
        wb.activeReleaseEpicDocs.first.sections['last_unreal_sync_ms'] =
            '1700000000000';
        expect(wb.isActiveProjectSyncedWithUnreal, isTrue);

        final exported = wb.exportProjectToJson();
        final dupId = wb.duplicateProject(wb.activeProjectId!)!;
        expect(wb.activeProjectId, equals(dupId));
        expect(wb.isActiveProjectSyncedWithUnreal, isFalse);
        for (final doc in wb.activeReleaseEpicDocs) {
          final decoded =
              jsonDecode(doc.sections['epic_spec_json']!) as Map<String, dynamic>;
          expect(decoded['id'], equals(doc.id));
        }

        final importedId = wb.importProjectFromJson(exported)!;
        expect(wb.activeProjectId, equals(importedId));
        expect(wb.isActiveProjectSyncedWithUnreal, isFalse);
        for (final doc in wb.activeReleaseEpicDocs) {
          final decoded =
              jsonDecode(doc.sections['epic_spec_json']!) as Map<String, dynamic>;
          expect(decoded['id'], equals(doc.id));
        }
      },
    );

    testWidgets(
      '18. Stage 1 Spark screen uses plain-English copy, drops duplicate ✦ sparkle & renders high-contrast primary ElevatedButton',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final darkBtnStyle = AppTheme.darkTheme.elevatedButtonTheme.style!;
        expect(
          darkBtnStyle.backgroundColor!.resolve(const <WidgetState>{}),
          equals(AppTheme.focalAccentDark),
        );
        expect(
          darkBtnStyle.foregroundColor!.resolve(const <WidgetState>{}),
          equals(AppTheme.focalAccentFgDark),
        );

        final wb = WorkbenchProvider(enableAutoLoad: false);
        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        expect(find.text('STAGE 1 · PROJECT SPEC'), findsOneWidget);
        expect(find.text('STAGE 1 · UNREAL MCP ROOT SPEC'), findsNothing);
        expect(find.text('Describe the game you want to build.'), findsOneWidget);
        expect(find.text('Draft Project Spec'), findsOneWidget);
        expect(find.textContaining('✦'), findsNothing);
      },
    );

    testWidgets(
      '19. Unified Stage 1 New Idea reset_spark_btn clears unapproved draft cleanly without leaving orphan vault docs & preserves approved projects',
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

        await tester.enterText(
          find.byKey(const ValueKey('spark_prompt_input')),
          'First-person grapple parkour arena with heavy slam attacks',
        );
        await tester.tap(find.byKey(const ValueKey('draft_spark_btn')));
        await tester.pumpAndSettle();

        expect(wb.conceptDraft?.cameraChoiceId, equals('fps'));
        expect(wb.conceptDraft?.feelChoiceId, equals('heavy'));
        expect(wb.documents, hasLength(1));

        await tester.tap(find.byKey(const ValueKey('reset_spark_btn')));
        await tester.pumpAndSettle();

        expect(wb.conceptDraft?.hasSpec, isFalse);
        expect(
          find.byKey(const ValueKey('spark_prompt_input')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('stage1_blueprint_empty_outline')),
          findsOneWidget,
        );
        expect(wb.documents, isEmpty);

        // Approved projects remain intact in vault when starting a New Idea from Stage 1
        await tester.enterText(
          find.byKey(const ValueKey('spark_prompt_input')),
          'Top-down crustacean mech brawler with claw dash',
        );
        await tester.tap(find.byKey(const ValueKey('draft_spark_btn')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('approve_launch_workbench_btn')),
        );
        await tester.pumpAndSettle();
        expect(wb.savedProjects, hasLength(1));

        wb.setStage(WorkbenchStage.projectPitch);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reset_spark_btn')));
        await tester.pumpAndSettle();

        expect(wb.savedProjects, hasLength(1));
        expect(wb.conceptDraft?.hasSpec, isFalse);
        expect(
          find.byKey(const ValueKey('spark_prompt_input')),
          findsOneWidget,
        );
      },
    );
  });
}
