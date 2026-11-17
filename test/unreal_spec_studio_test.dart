import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/agents/project_concept_agent.dart';
import 'package:layers_agentic/agents/release_planner_agent.dart';
import 'package:layers_agentic/constants/text_style_guide.dart';
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
import 'package:layers_agentic/utils/markdown_exporter.dart';
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
        expect(
          UnrealSpecGuard.containsGodotLeakage('Dash velocity 900 px/s'),
          isTrue,
        );
        final sanitized = UnrealSpecGuard.sanitizeLine(
          'Godot CharacterBody3D moves in arena.tscn with player.gd _physics_process at 450 px/s',
        );
        expect(sanitized.toLowerCase(), isNot(contains('godot')));
        expect(sanitized, isNot(contains('CharacterBody3D')));
        expect(sanitized, isNot(contains('px/s')));
        expect(sanitized, contains('Unreal Engine'));
        expect(sanitized, contains('ACharacter'));
        expect(sanitized, contains('Tick'));
        expect(sanitized, contains('450 cm/s'));

        expect(
          UnrealSpecGuard.normalizeUnrealUnit('WalkSpeed', 'px'),
          equals('cm'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('WalkSpeed', 'px/s'),
          equals('cm/s'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('WalkSpeed', 'pixels/s'),
          equals('cm/s'),
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

        expect(find.byKey(const ValueKey('stage1_target_ue6')), findsNothing);
        expect(wb.targetEngine, equals(UnrealTargetEngine.ue5Mcp));

        await tester.tap(find.byKey(const ValueKey('stage1_tab_raw')));
        await tester.pumpAndSettle();
        expect(wb.showRawRootContext, isTrue);
        expect(
          find.textContaining(
            'Target Architecture: 100% Blueprint-Only (.uasset)',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('Code Policy: STRICT BLUEPRINT-ONLY'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Core Feel: Snappy Arcade'),
          findsOneWidget,
        );

        wb.setTargetEngine(UnrealTargetEngine.ue6Verse);
        await tester.pumpAndSettle();
        expect(wb.targetEngine, equals(UnrealTargetEngine.ue6Verse));
        expect(
          find.textContaining(
            'Target Architecture: Verse Components + Scene Graph Entities',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('Code Policy: UE6 VERSE + SCENE GRAPH'),
          findsOneWidget,
        );

        wb.setTargetEngine(UnrealTargetEngine.ue5Mcp);
        await tester.pumpAndSettle();
        expect(wb.targetEngine, equals(UnrealTargetEngine.ue5Mcp));

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
          wb.selectCoreFeelOption('heavy');
          await wb.openProgressiveReleaseCopilot();
          expect(capturedPrompt, contains('Core Loop (§01):'));
          expect(capturedPrompt, contains('Camera Contract (§02):'));
          expect(capturedPrompt, contains('Input Contract (§02):'));
          expect(capturedPrompt, contains('Core Feel (§03): Heavy Deliberate'));
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

        final nineEpics = [
          for (int i = 0; i < 9; i++)
            EpicSpec(
              id: 'ep_$i',
              code: EpicSpec.formatCode(i + 1),
              title: 'System ${i + 1}',
              goal: 'Playable loop check ${i + 1}.',
            ),
        ];
        final v04Draft = await ReleasePlannerAgent.proposeNextReleaseCopilot(
          rootSpec: wb.conceptDraft!,
          currentEpics: nineEpics,
          targetVersion: 'v0.4',
          apiKey: '',
        );
        expect(v04Draft.candidateNewEpics.first.code, equals('E10'));
        expect(v04Draft.candidateNewEpics.first.lineageKey, equals('e10'));
        expect(v04Draft.candidateNewEpics.first.coreLoopBeat, isNotEmpty);
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

        // Open [FIX] overrides stable lifecycle visually & semantically, and restores upgrading on v0.2
        final stableWithOpenFix = EpicSpec(
          id: 'open_fix_check',
          code: 'E01',
          title: 'Fix Override',
          goal: 'Check open fix gate.',
          lifecycle: EpicLifecycle.stable,
          fixes: [EpicPieFix(id: 'fx_1', text: 'Dash glitch', resolved: false)],
        );
        expect(stableWithOpenFix.isPassed, isFalse);
        expect(stableWithOpenFix.statusLabel, equals('1 [FIX] Open'));

        wb.flagEpicFix(upgradingEpic.id, 'Hit-stop freezes camera shake');
        final flaggedUpgrading =
            wb.epicsForRelease(wb.activeReleaseId!).firstWhere(
                  (e) => e.id == upgradingEpic.id,
                );
        expect(flaggedUpgrading.isPassed, isFalse);
        expect(flaggedUpgrading.lifecycle, equals(EpicLifecycle.upgrading));
        expect(flaggedUpgrading.statusLabel, equals('1 [FIX] Open'));

        wb.resolveEpicFix(
          upgradingEpic.id,
          flaggedUpgrading.openFixes.first.id,
        );
        wb.passActiveEpic(upgradingEpic.id);

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
        expect(sanitizeExportSlug('  !!!  '), equals('layers_project'));
        expect(
          sanitizeExportSlug('  !!!  ', fallback: 'layers'),
          equals('layers'),
        );
        expect(
          sanitizeExportSlug('Shellbreaker: v0.1!'),
          equals('shellbreaker_v0_1'),
        );

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

    testWidgets(
      '20. Checking all §06 PIE checks keeps Pass Epic button visible (Ready to Pass) until explicit sign-off, and unchecking demotes stable',
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

        for (final chk in e01.checks) {
          wb.togglePieCheck(e01Id, chk.id, true);
        }
        await tester.pumpAndSettle();

        expect(wb.selectedEpicSpec!.allChecksPassed, isTrue);
        expect(wb.selectedEpicSpec!.isPassed, isFalse);
        expect(wb.selectedEpicSpec!.statusLabel, equals('Ready to Pass'));
        expect(find.byKey(const ValueKey('pass_epic_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('reopen_epic_btn')), findsNothing);

        final passBtn = find.byKey(const ValueKey('pass_epic_btn'));
        await tester.ensureVisible(passBtn);
        await tester.tap(passBtn);
        await tester.pumpAndSettle();

        final signedE01 = wb.epicsForRelease(wb.activeReleaseId!).firstWhere(
              (e) => e.id == e01Id,
            );
        expect(signedE01.isPassed, isTrue);
        expect(signedE01.lifecycle, equals(EpicLifecycle.stable));
        expect(signedE01.statusLabel, equals('Baseline ✓'));
        expect(wb.selectedEpicSpec?.code, equals('E02'));

        wb.togglePieCheck(e01Id, e01.checks.first.id, false);
        await tester.pumpAndSettle();
        final demotedE01 = wb.epicsForRelease(wb.activeReleaseId!).firstWhere(
              (e) => e.id == e01Id,
            );
        expect(demotedE01.lifecycle, equals(EpicLifecycle.active));
        expect(demotedE01.isPassed, isFalse);
      },
    );

    test(
      '21. Progressive v0.1 -> v0.2 -> v0.3 preserves v0.2 deltas in Locked Baseline, guards monotonic version when viewing v0.1, and maps Gemini presets onto reordered Epics',
      () async {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.moveInitialEpic(0, 1);
        final v01RelId = wb.approveRootSpecAndLaunchWorkbench()!;
        expect(wb.activeReleaseEpics.first.code, equals('E01'));
        expect(wb.activeReleaseEpics.first.lineageKey, equals('e02'));

        wb.updateAiConfig(apiKey: 'mock-key-1234');
        final prevMock = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, model) async {
          if (prompt.contains('release `v0.2`')) {
            return {
              'presets': [
                {
                  'id': 'p_v02',
                  'label': 'Bolt Pierce Focus',
                  'desc': 'Add piercing bolt delta and wave spawner',
                  'upgrades': ['UP_1'],
                  'newEpics': ['E04_WAVES'],
                },
              ],
              'upgrades': [
                {
                  'lineageKey': 'E01',
                  'options': [
                    {
                      'id': 'up_1',
                      'text': '+Piercing plasma bolt',
                      'chosen': false,
                    },
                  ],
                },
              ],
              'newEpics': [
                {
                  'id': 'e04_waves',
                  'code': 'E04',
                  'title': 'Arena Wave Spawner',
                  'goal': 'Spawn 3 escalating waves in L_Shellbreaker_Proto.',
                  'links': ['GM_Shellbreaker -> BP_WaveSpawner'],
                  'outOfScope': ['No endless mode'],
                  'controls': const [],
                  'states': ['Idle -> Spawning'],
                  'interrupts': ['Player death halts spawn timer'],
                  'tuning': [
                    {'key': 'WaveCount', 'value': '3', 'unit': 'count'},
                  ],
                  'feedback': ['UMG wave banner pulse'],
                  'levelStaging': 'L_Shellbreaker_Proto',
                  'checks': [
                    {'text': 'Clear wave 1 -> wave 2 spawns cleanly'},
                  ],
                  'chosen': false,
                },
              ],
            };
          }
          return {
            'presets': [
              {
                'id': 'p_v03',
                'label': 'Dash Echo Pass',
                'desc': 'Add dash echo atop v0.2 bolts',
                'upgrades': ['up_v03_1'],
                'newEpics': const [],
              },
            ],
            'upgrades': [
              {
                'lineageKey': 'e02',
                'options': [
                  {
                    'id': 'up_v03_1',
                    'text': '+Dash shockwave pulse',
                    'chosen': false,
                  },
                ],
              },
            ],
            'newEpics': const [],
          };
        };

        try {
          await wb.openProgressiveReleaseCopilot();
          final v02Draft = wb.progressiveDraft!;
          expect(v02Draft.targetVersion, equals('v0.2'));
          expect(
            v02Draft.upgradesByLineageKey['e02']?.single.chosen,
            isTrue,
          );
          expect(
            v02Draft.candidateNewEpics.single.chosenForNextRelease,
            isTrue,
          );

          final v02RelId = wb.commitProgressiveReleaseDraft()!;
          expect(wb.activeReleaseVersionTag, equals('v0.2'));

          // Switch UI back to v0.1: release planner must remain monotonic (v0.3 atop v0.2)
          wb.selectActiveRelease(v01RelId);
          expect(wb.highestProjectReleaseVersionTag, equals('v0.2'));
          expect(wb.nextReleaseActionLabel, contains('v0.3'));

          await wb.openProgressiveReleaseCopilot();
          expect(wb.progressiveDraft!.targetVersion, equals('v0.3'));
          expect(
            wb.latestReleaseEpics.length,
            equals(wb.epicsForRelease(v02RelId).length),
          );

          wb.commitProgressiveReleaseDraft()!;
          expect(wb.activeReleaseVersionTag, equals('v0.3'));

          final v03E01 = wb.activeReleaseEpics.firstWhere(
            (e) => e.lineageKey == 'e02',
          );
          expect(
            v03E01.baselineSummary.any(
              (s) => s.contains('+Piercing plasma bolt'),
            ),
            isTrue,
          );
          final v03Payload = wb.activeEpicMcpPayload(v03E01);
          expect(v03Payload, contains('- Locked Baseline:'));
          expect(v03Payload, contains('+Piercing plasma bolt'));

          wb.passActiveEpic(v03E01.id);
          wb.reopenEpic(v03E01.id);
          final reopened = wb.epicsForRelease(wb.activeReleaseId!).firstWhere(
                (e) => e.id == v03E01.id,
              );
          final v02Checks = reopened.checks
              .where((c) => c.text.toLowerCase().contains('verify v0.2 delta'))
              .toList();
          final v03Checks = reopened.checks
              .where((c) => c.text.toLowerCase().contains('verify v0.3 delta'))
              .toList();
          expect(v02Checks, isNotEmpty);
          expect(v02Checks.every((c) => c.passed), isTrue);
          expect(v03Checks, isNotEmpty);
          expect(v03Checks.every((c) => !c.passed), isTrue);
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
        }
      },
    );

    test(
      '22. FPS vs SpringArm camera switch cleans stale SpringArmLength/EyeHeight & Gemini Co-Design preserves reordered lineageKey + v0.2 presets',
      () async {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');

        // Part A: Camera switch swaps SpringArmLength vs EyeHeight cleanly while preserving MoveSpeed at index 0
        wb.selectCameraDecisionOption('tps');
        var e01 = wb.conceptDraft!.initialEpics.first;
        expect(e01.tuning.first.key, equals('MoveSpeed'));
        expect(
          e01.tuning.firstWhere((t) => t.key == 'SpringArmLength').value,
          equals('380'),
        );
        expect(e01.tuning.any((t) => t.key == 'EyeHeight'), isFalse);

        wb.selectCameraDecisionOption('fps');
        e01 = wb.conceptDraft!.initialEpics.first;
        expect(e01.tuning.first.key, equals('MoveSpeed'));
        expect(e01.tuning.any((t) => t.key == 'SpringArmLength'), isFalse);
        expect(
          e01.tuning.firstWhere((t) => t.key == 'EyeHeight').value,
          equals('64'),
        );

        wb.selectCameraDecisionOption('isometric');
        e01 = wb.conceptDraft!.initialEpics.first;
        expect(e01.tuning.any((t) => t.key == 'EyeHeight'), isFalse);
        expect(
          e01.tuning.firstWhere((t) => t.key == 'SpringArmLength').value,
          equals('1450'),
        );

        // Part B: Gemini Co-Design after reordering preserves lineageKey, v02Presets & approved flag
        wb.moveInitialEpic(0, 1);
        expect(
          wb.conceptDraft!.initialEpics[0].title,
          equals('Twin-Stick Burst Cannon & Recoil'),
        );
        expect(wb.conceptDraft!.initialEpics[0].lineageKey, equals('e02'));
        expect(wb.conceptDraft!.initialEpics[1].lineageKey, equals('e01'));

        final relId = wb.approveRootSpecAndLaunchWorkbench()!;
        wb.passActiveEpic(wb.epicsForRelease(relId).first.id);
        wb.setStage(WorkbenchStage.projectPitch);
        wb.updateAiConfig(apiKey: 'mock-key-1234');

        final prevMock = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, model) async {
          if (prompt.contains('USER CO-DESIGN INSTRUCTION')) {
            return {
              'gameTitle': 'SHELLBREAKER',
              'pitch': wb.conceptDraft!.pitch,
              'coreLoop': wb.conceptDraft!.coreLoop,
              'cameraChoiceId': wb.conceptDraft!.cameraChoiceId,
              'cameraContract': wb.conceptDraft!.cameraContract,
              'characterScale': wb.conceptDraft!.characterScale,
              'inputContract': wb.conceptDraft!.inputContract,
              'assetPolicy': wb.conceptDraft!.assetPolicy,
              'pillars': wb.conceptDraft!.pillars,
              'tradeOffs': [
                for (final t in wb.conceptDraft!.tradeOffs)
                  {'prefer': t.prefer, 'avoid': t.avoid},
              ],
              'outOfScope': wb.conceptDraft!.outOfScope,
              'releaseDoneWhen': wb.conceptDraft!.releaseDoneWhen,
              'initialEpics': [
                {
                  'code': 'E01',
                  'title': 'Twin-Stick Burst Cannon & Recoil',
                  'coreLoopBeat': 'Beat 3 · Burst Cannon Fire',
                  'goal': wb.conceptDraft!.initialEpics[0].goal,
                  'links': wb.conceptDraft!.initialEpics[0].links,
                  'outOfScope': wb.conceptDraft!.initialEpics[0].outOfScope,
                  'controls': const [],
                  'states': wb.conceptDraft!.initialEpics[0].states,
                  'interrupts': wb.conceptDraft!.initialEpics[0].interrupts,
                  'tuning': const [],
                  'feedback': wb.conceptDraft!.initialEpics[0].feedback,
                  'levelStaging': wb.conceptDraft!.initialEpics[0].levelStaging,
                  'checks': [
                    for (final c in wb.conceptDraft!.initialEpics[0].checks)
                      {'text': c.text},
                  ],
                },
                {
                  'code': 'E02',
                  'title': 'Player Mech Movement & Claw Dash',
                  'coreLoopBeat': 'Beats 1–2 · Skim, Aim & Claw Dash',
                  'goal': 'Faster 720 cm/s claw dash.',
                  'links': wb.conceptDraft!.initialEpics[1].links,
                  'outOfScope': wb.conceptDraft!.initialEpics[1].outOfScope,
                  'controls': const [],
                  'states': wb.conceptDraft!.initialEpics[1].states,
                  'interrupts': wb.conceptDraft!.initialEpics[1].interrupts,
                  'tuning': [
                    {'key': 'MoveSpeed', 'value': '720', 'unit': 'cm/s'},
                  ],
                  'feedback': wb.conceptDraft!.initialEpics[1].feedback,
                  'levelStaging': wb.conceptDraft!.initialEpics[1].levelStaging,
                  'checks': [
                    for (final c in wb.conceptDraft!.initialEpics[1].checks)
                      {'text': c.text},
                  ],
                },
                {
                  'code': 'E03',
                  'title': 'Crustacean Grunt & Armor Break',
                  'coreLoopBeat': 'Beats 3–4 · Armor Crack & Reposition',
                  'goal': wb.conceptDraft!.initialEpics[2].goal,
                  'links': wb.conceptDraft!.initialEpics[2].links,
                  'outOfScope': wb.conceptDraft!.initialEpics[2].outOfScope,
                  'controls': const [],
                  'states': wb.conceptDraft!.initialEpics[2].states,
                  'interrupts': wb.conceptDraft!.initialEpics[2].interrupts,
                  'tuning': const [],
                  'feedback': wb.conceptDraft!.initialEpics[2].feedback,
                  'levelStaging': wb.conceptDraft!.initialEpics[2].levelStaging,
                  'checks': [
                    for (final c in wb.conceptDraft!.initialEpics[2].checks)
                      {'text': c.text},
                  ],
                },
              ],
            };
          }
          return null;
        };

        try {
          await wb.applyStage1CoDesignInstruction('Boost dash speed');
          expect(wb.conceptDraft!.initialEpics[0].lineageKey, equals('e02'));
          expect(wb.conceptDraft!.initialEpics[1].lineageKey, equals('e01'));
          expect(wb.conceptDraft!.v02Presets, isNotEmpty);
          expect(wb.conceptDraft!.approved, isTrue);

          wb.approveRootSpecAndLaunchWorkbench();
          final stage2Epics = wb.epicsForRelease(relId);
          expect(stage2Epics[0].isPassed, isTrue);
          expect(stage2Epics[0].lineageKey, equals('e02'));
          expect(stage2Epics[1].goal, equals('Faster 720 cm/s claw dash.'));
          expect(stage2Epics[1].lineageKey, equals('e01'));
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
        }
      },
    );

    test(
      '23. addEpicTuningParam upserts case-insensitive tuning keys in place without duplicating §04 rows',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();
        final e01Id = wb.selectedEpicId!;
        final initialLen = wb.selectedEpicSpec!.tuning.length;

        wb.addEpicTuningParam(
          e01Id,
          key: 'movespeed',
          value: '710',
          unit: 'px/s',
        );
        expect(wb.selectedEpicSpec!.tuning, hasLength(initialLen));
        expect(wb.selectedEpicSpec!.tuning.first.key, equals('MoveSpeed'));
        expect(wb.selectedEpicSpec!.tuning.first.value, equals('710'));
        expect(wb.selectedEpicSpec!.tuning.first.unit, equals('cm/s'));

        wb.addEpicTuningParam(
          e01Id,
          key: 'TurnSnap',
          value: '0',
          unit: 'deg',
        );
        expect(wb.selectedEpicSpec!.tuning, hasLength(initialLen + 1));
        expect(wb.selectedEpicSpec!.tuning.last.value, equals('0'));
      },
    );

    test(
      '24. UnrealMcpPayloadBuilder strips double-plus delta clutter, handles stateless §03 Epics, and deduplicates multi-Epic bundle footers',
      () {
        final shellbreaker = UnrealSparkPresets.byId('shellbreaker');
        final epic = shellbreaker.initialEpics.first.deepCopy(
          releaseVersionOverride: 'v0.2',
          lifecycleOverride: EpicLifecycle.upgrading,
        );
        epic.upgradeDeltas = ['+55ms Hit-Stop'];
        epic.states = [];
        epic.interrupts = [];

        final payload = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: shellbreaker,
          epic: epic,
        );
        expect(payload, contains('- +55ms Hit-Stop'));
        expect(payload, isNot(contains('- + +')));
        expect(payload, isNot(contains('end-to-end')));
        expect(payload, contains('- Stateless / event-driven Epic'));

        final bundle = UnrealMcpPayloadBuilder.buildReleaseMcpBundle(
          rootSpec: shellbreaker,
          releaseLabel: 'v0.1 · Prototype',
          releaseEpics: shellbreaker.initialEpics,
        );
        expect(
          '### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK'
              .allMatches(bundle)
              .length,
          equals(1),
        );
        expect(bundle.trimRight().endsWith('---'), isFalse);
      },
    );

    test(
      '25. Epic MCP payload surfaces top-of-spec Execution Mode, [FIX] IDs, and explicit LayersToolset callback guardrails',
      () {
        final shellbreaker = UnrealSparkPresets.byId('shellbreaker');
        final epic = shellbreaker.initialEpics.first.deepCopy();

        final payload = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: shellbreaker,
          epic: epic,
        );
        expect(
          payload,
          contains('Execution Mode: FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK'),
        );
        expect(
          payload.indexOf('Execution Mode:'),
          lessThan(payload.indexOf('## §01 System Intent')),
        );
        expect(payload, contains('layers_toggle_pie_check'));
        expect(payload, contains('Do NOT call layers_pass_active_epic'));

        epic.fixes.add(
          EpicPieFix(id: 'fx_ramp_01', text: 'Dash snags ramp corner'),
        );
        final fixPayload = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: shellbreaker,
          epic: epic,
        );
        expect(
          fixPayload,
          contains('Execution Mode: FOCUSED PIE REVISION PASS (1 OPEN [FIX])'),
        );
        expect(
          fixPayload.indexOf('Execution Mode:'),
          lessThan(fixPayload.indexOf('## §01 System Intent')),
        );
        expect(
          fixPayload,
          contains('- [FIX] Dash snags ramp corner (id: fx_ramp_01)'),
        );
        expect(fixPayload, contains('layers_resolve_pie_fix'));
      },
    );

    test(
      '26. buildRootMcpContext renders Blueprints, DataAssets, UMG Widgets, Levels, and Verse snapshot lines',
      () {
        final shellbreaker = UnrealSparkPresets.byId('shellbreaker');
        final md = UnrealMcpPayloadBuilder.buildRootMcpContext(
          shellbreaker,
          liveUprojectContext: const {
            'project_name': 'ShellbreakerUE5',
            'current_level': 'L_Arena_Proto',
            'game_mode': 'GM_Shellbreaker',
            'default_pawn': 'BP_CrabPlayer',
            'input_assets': ['/Game/Input/IMC_Core', '/Game/Input/IA_Move'],
            'blueprint_assets': [
              '/Game/Blueprints/BP_CrabPlayer',
              '/Game/Blueprints/GM_Shellbreaker',
            ],
            'data_assets': ['/Game/Data/DA_PlayerLocomotion'],
            'widget_assets': ['/Game/UI/WBP_ArenaHUD'],
            'level_assets': ['/Game/Maps/L_Arena_Proto'],
            'verse_files': ['Content/Verse/crab_dash_device.verse'],
          },
        );
        expect(
          md,
          contains(
            '- Existing Enhanced Input Assets: /Game/Input/IMC_Core, /Game/Input/IA_Move',
          ),
        );
        expect(
          md,
          contains(
            '- Existing Blueprints: /Game/Blueprints/BP_CrabPlayer, /Game/Blueprints/GM_Shellbreaker',
          ),
        );
        expect(
          md,
          contains(
            '- Existing DataAssets & Tables: /Game/Data/DA_PlayerLocomotion',
          ),
        );
        expect(
          md,
          contains('- Existing UMG Widgets: /Game/UI/WBP_ArenaHUD'),
        );
        expect(md, contains('- Existing Levels: /Game/Maps/L_Arena_Proto'));
        expect(
          md,
          contains('- Existing Verse Files: Content/Verse/crab_dash_device.verse'),
        );
      },
    );

    test(
      '27. UnrealSpecGuard normalizes PascalCase §04 keys, infers missing units, and annotates UE5 vs UE6 Verse property types',
      () {
        expect(
          UnrealSpecGuard.sanitizeTuningKey('max walk speed'),
          equals('MaxWalkSpeed'),
        );
        expect(
          UnrealSpecGuard.sanitizeTuningKey('crit_chance'),
          equals('CritChance'),
        );
        expect(
          UnrealSpecGuard.sanitizeTuningKey('1st wave count'),
          equals('Param1stWaveCount'),
        );
        expect(
          UnrealSpecGuard.sanitizeTuningKey('bCanDash'),
          equals('bCanDash'),
        );
        expect(
          UnrealSpecGuard.sanitizeTuningKey('   ', fallback: ''),
          equals(''),
        );

        expect(
          UnrealSpecGuard.normalizeUnrealUnit('BrakingDecel', ''),
          equals('cm/s'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('CritChance', ''),
          equals('%'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('BoostDrainRate', ''),
          equals('%/s'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('AimSpread', ''),
          equals('deg'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('ShieldPool', ''),
          equals('hp'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('Cooldown', 'seconds'),
          equals('s'),
        );

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();
        final e01Id = wb.selectedEpicId!;
        final countBefore = wb.selectedEpicSpec!.tuning.length;
        wb.addEpicTuningParam(e01Id, key: 'move speed', value: '700', unit: '');
        expect(wb.selectedEpicSpec!.tuning, hasLength(countBefore));
        expect(wb.selectedEpicSpec!.tuning.first.key, equals('MoveSpeed'));
        expect(wb.selectedEpicSpec!.tuning.first.value, equals('700'));
        expect(wb.selectedEpicSpec!.tuning.first.unit, equals('cm/s'));

        final epTest = wb.selectedEpicSpec!.deepCopy();
        epTest.tuning = [
          EpicTuningParam(key: 'MoveSpeed', value: '700', unit: 'cm/s'),
          EpicTuningParam(key: 'WaveCount', value: '3', unit: 'count'),
          EpicTuningParam(key: 'bCanDash', value: 'true', unit: 'bool'),
        ];

        final ue5Md = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: wb.conceptDraft!,
          epic: epTest,
          targetOverride: UnrealTargetEngine.ue5Mcp,
        );
        expect(ue5Md, contains('- MoveSpeed: 700 cm/s [float]'));
        expect(ue5Md, contains('- WaveCount: 3 count [int32]'));
        expect(ue5Md, contains('- bCanDash: true bool [bool]'));

        final ue6Md = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: wb.conceptDraft!,
          epic: epTest,
          targetOverride: UnrealTargetEngine.ue6Verse,
        );
        expect(ue6Md, contains('- MoveSpeed: 700 cm/s [float]'));
        expect(ue6Md, contains('- WaveCount: 3 count [int]'));
        expect(ue6Md, contains('- bCanDash: true bool [logic]'));
      },
    );

    test(
      '28. UnrealSpecGuard strips Godot 4, Unity, and banned jargon across TradeOffs, Camera Options, Presets, Upgrades & [FIX] notes',
      () {
        expect(
          UnrealSpecGuard.containsGodotLeakage(
            'Attach MonoBehaviour to GameObject prefab',
          ),
          isTrue,
        );
        expect(
          UnrealSpecGuard.containsGodotLeakage(
            'Spawn PackedScene inside Area3D',
          ),
          isTrue,
        );
        expect(UnrealSpecGuard.containsGodotLeakage('1200 pixels/s'), isTrue);

        final dirtyNestedOnly = ProjectConceptBlueprint(
          gameTitle: 'Clean Title',
          pitch: 'Crisp melee arena prototype.',
          cameraContract: 'SpringArm 1450 cm @ -52 deg pitch',
          inputContract: 'Enhanced Input (IMC_Combat + IA_Move)',
          tradeOffs: const [
            TradeOffRule(
              prefer: 'Snappy Node3D response',
              avoid: 'Heavy GameObject MonoBehaviour drift',
            ),
          ],
          initialEpics: [
            EpicSpec(
              id: 'ep_n1',
              code: 'E01',
              title: 'Combat',
              goal: 'Swing sword',
              checks: [
                EpicPieCheck(id: 'c1', text: 'Sword hits dummy cleanly'),
              ],
            ),
          ],
        );
        expect(UnrealSpecGuard.auditBlueprint(dirtyNestedOnly), isNotEmpty);

        final dirty = ProjectConceptBlueprint(
          gameTitle: 'Test Arena',
          pitch:
              'Leverage homestead husbandry on an expedition cleanly and seamlessly.',
          cameraDecisionOptions: const [
            ConceptSectionOption(
              id: 'cam_a',
              label: 'Godot Camera3D',
              contractValue: 'Camera3D boom 1400 px',
              note: 'Validate RayCast3D sightline',
            ),
          ],
          tradeOffs: const [
            TradeOffRule(
              prefer: 'Snappy Node3D response',
              avoid: 'Heavy GameObject MonoBehaviour drift',
            ),
          ],
          v02Presets: const [
            ReleaseDirectionPreset(
              id: 'p1',
              label: 'Unified Expedition',
              description: 'Deliver enemy prefab waves seamlessly',
              upgradeIds: ['u1'],
              newEpicIds: [],
            ),
          ],
          v02UpgradesByLineageKey: {
            'e01': [
              EpicUpgradeOption(
                id: 'u1',
                text: 'Spawn PackedScene decoy inside Area3D',
              ),
            ],
          },
          initialEpics: [
            EpicSpec(
              id: 'ep_1',
              code: 'E01',
              title: 'Dash',
              goal: 'Dash forward cleanly',
              checks: [
                EpicPieCheck(id: 'c1', text: 'Dash 400 px on press'),
              ],
              fixes: [
                EpicPieFix(
                  id: 'f1',
                  text: 'RigidBody3D snags turret.prefab at 400 px',
                ),
              ],
              copilotUpgrades: [
                EpicUpgradeOption(
                  id: 'cu1',
                  text: 'Leverage ordinance blast',
                ),
              ],
            ),
          ],
        );

        final clean = UnrealSpecGuard.sanitizeConceptBlueprint(dirty);
        final lowerPitch = clean.pitch.toLowerCase();
        expect(lowerPitch, contains('base'));
        expect(lowerPitch, contains('breeding'));
        expect(lowerPitch, contains('run'));
        expect(lowerPitch, contains('cleanly.'));
        expect(lowerPitch, isNot(contains('leverage')));
        expect(lowerPitch, isNot(contains('homestead')));
        expect(lowerPitch, isNot(contains('husbandry')));
        expect(lowerPitch, isNot(contains('expedition')));
        expect(lowerPitch, isNot(contains('seamlessly')));
        expect(clean.pitch, isNot(contains(' and .')));

        final camOpt = clean.cameraDecisionOptions.first;
        expect(camOpt.label, contains('UCameraComponent'));
        expect(camOpt.contractValue, contains('UCameraComponent boom 1400 cm'));
        expect(camOpt.note, contains('Check LineTraceByChannel sightline'));

        expect(
          clean.tradeOffs.first.formatted,
          equals('Snappy AActor response OVER Heavy AActor UActorComponent drift'),
        );

        final preset = clean.v02Presets.first;
        expect(preset.label.toLowerCase(), isNot(contains('unified')));
        expect(preset.label.toLowerCase(), isNot(contains('expedition')));
        expect(preset.description, contains('Blueprint'));
        expect(preset.description.toLowerCase(), contains('produce'));
        expect(preset.description.toLowerCase(), isNot(contains('prefab')));
        expect(preset.description.toLowerCase(), isNot(contains('deliver')));
        expect(preset.description.toLowerCase(), isNot(contains('seamlessly')));

        expect(
          clean.v02UpgradesByLineageKey['e01']!.first.text,
          allOf(contains('Blueprint Class'), contains('UBoxComponent')),
        );
        expect(
          clean.initialEpics.first.fixes.first.text,
          allOf(
            contains('UPrimitiveComponent'),
            contains('400 cm'),
            contains('Blueprint'),
            isNot(contains('RigidBody3D')),
            isNot(contains('prefab')),
            isNot(contains('400 px')),
          ),
        );
        expect(
          clean.initialEpics.first.copilotUpgrades.first.text.toLowerCase(),
          allOf(
            contains('weaponry'),
            isNot(contains('leverage')),
            isNot(contains('ordinance')),
          ),
        );
        expect(UnrealSpecGuard.auditBlueprint(clean), isEmpty);
      },
    );

    test(
      '29. activeEpicMcpPayload emits Release Epic Roadmap with [BUILT ✓] reusable contracts, [ACTIVE →], and [QUEUED — DEFER] siblings',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();

        final e01Md = wb.activeEpicMcpPayload(wb.selectedEpicSpec!);
        expect(e01Md, contains('## Release Epic Roadmap (v0.1 · 0/3 Passed)'));
        expect(
          e01Md,
          contains(
            '- [ACTIVE →] E01 · Player Mech Movement & Claw Dash — build in this pass',
          ),
        );
        expect(
          e01Md,
          contains(
            '- [QUEUED — DEFER] E02 · Twin-Stick Burst Cannon & Recoil — do not build yet; stub interfaces only if needed',
          ),
        );
        expect(
          e01Md,
          contains(
            '- [QUEUED — DEFER] E03 · Crustacean Grunt & Armor Break — do not build yet; stub interfaces only if needed',
          ),
        );

        wb.passActiveEpic(wb.selectedEpicId!);
        expect(wb.selectedEpicSpec?.code, equals('E02'));
        final e02Md = wb.activeEpicMcpPayload(wb.selectedEpicSpec!);
        expect(e02Md, contains('## Release Epic Roadmap (v0.1 · 1/3 Passed)'));
        expect(
          e02Md,
          allOf(
            contains(
              '- [BUILT ✓] E01 · Player Mech Movement & Claw Dash — preserve & reuse (',
            ),
            contains('IA_Move'),
          ),
        );
        expect(
          e02Md,
          contains(
            '- [ACTIVE →] E02 · Twin-Stick Burst Cannon & Recoil — build in this pass',
          ),
        );
        expect(
          e02Md,
          contains(
            '- [QUEUED — DEFER] E03 · Crustacean Grunt & Armor Break',
          ),
        );

        final bundle = UnrealMcpPayloadBuilder.buildReleaseMcpBundle(
          rootSpec: wb.conceptDraft!,
          releaseLabel: 'v0.1 · Prototype',
          releaseEpics: wb.activeReleaseEpics,
        );
        expect(bundle, isNot(contains('## Release Epic Roadmap')));
      },
    );

    test(
      '30. ROOT_MCP_CONTEXT emits §05 Release Gate, ReleasePlannerAgent passes baseline links/controls/levelStaging to Gemini, and LayersTextStyleGuide normalizes values',
      () async {
        final shellbreaker = UnrealSparkPresets.byId('shellbreaker');
        final withGate = UnrealMcpPayloadBuilder.buildRootMcpContext(shellbreaker);
        expect(
          withGate,
          contains('- Release Gate: ${shellbreaker.releaseDoneWhen}'),
        );

        final blankGateSpec = shellbreaker.deepCopy()..releaseDoneWhen = '   ';
        expect(
          UnrealMcpPayloadBuilder.buildRootMcpContext(blankGateSpec),
          isNot(contains('- Release Gate:')),
        );

        expect(
          LayersTextStyleGuide.compactStoredTradeOff(
            '- Fast response over Slow drift',
          ),
          equals('Fast response OVER Slow drift'),
        );
        expect(
          LayersTextStyleGuide.compactStoredExclusion('save slots'),
          equals('No save slots'),
        );
        expect(
          LayersTextStyleGuide.isLegacyTemplateTaskTitle('Step 1: edit player.gd'),
          isTrue,
        );
        expect(
          LayersTextStyleGuide.unrealTuningKeySchemaDesc,
          contains('PascalCase'),
        );

        String capturedPrompt = '';
        final prevMock = GeminiAgentClient.testMockResponder;
        GeminiAgentClient.testMockResponder = (prompt, model) async {
          capturedPrompt = prompt;
          return {
            'presets': [
              {
                'id': 'p1',
                'label': 'Armored Rush',
                'desc': 'Add shield dash upgrades',
                'upgrades': [],
                'newEpics': [],
              },
            ],
            'upgrades': [],
            'newEpics': [],
          };
        };

        try {
          await ReleasePlannerAgent.proposeNextReleaseCopilot(
            rootSpec: shellbreaker,
            currentEpics: shellbreaker.initialEpics,
            targetVersion: 'v0.2',
            apiKey: 'mock-key-release-gate',
          );
          expect(capturedPrompt, contains('Release Gate (§05):'));
          expect(capturedPrompt, contains('DA_PlayerLocomotion'));
          expect(capturedPrompt, contains('IA_Move'));
          expect(capturedPrompt, contains('L_Shellbreaker_Proto'));
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
        }
      },
    );

    test(
      '31. Cross-runtime byte-for-byte parity between Dart WorkbenchProvider.activeEpicMcpPayload and Cloud Functions computeActiveUnrealEpicPayload across UE5, UE6 Verse, v0.2 Deltas & [FIX] Pass',
      () async {
        Future<String> renderViaNode(
          WorkbenchProvider wb, {
          Map<String, dynamic>? uprojectContext,
        }) async {
          const jsScript = r'''
            const { _testHelpers: h } = require('./functions/index.js');
            const docs = JSON.parse(process.env.DOCS_JSON || '[]');
            const docsById = new Map(docs.map((d) => [d.id, d]));
            const rawCtx = process.env.CTX_JSON ? JSON.parse(process.env.CTX_JSON) : null;
            const out = h.computeActiveUnrealEpicPayload({
              docsById,
              projectId: process.env.PID,
              uprojectContext: h.sanitizeUprojectContextJs(rawCtx),
            });
            if (!out.ok) throw new Error(out.error || 'computeActiveUnrealEpicPayload failed');
            process.stdout.write(out.mcpPayloadMarkdown);
          ''';
          final docsJson = jsonEncode([
            for (final doc in wb.documents.values) doc.toJson(),
          ]);
          final proc = await Process.run(
            'node',
            ['-e', jsScript],
            environment: {
              'GCLOUD_PROJECT': 'layers-b8a16',
              'DOCS_JSON': docsJson,
              'PID': wb.activeProject!.id,
              if (uprojectContext != null)
                'CTX_JSON': jsonEncode(uprojectContext),
            },
          );
          expect(proc.exitCode, equals(0), reason: proc.stderr.toString());
          return proc.stdout as String;
        }

        void setLiveContext(
          WorkbenchProvider wb,
          Map<String, dynamic>? ctx,
        ) {
          final proj = wb.activeProject!;
          final nextSections = Map<String, String>.from(proj.sections);
          if (ctx == null) {
            nextSections.remove('unreal_live_context_json');
          } else {
            nextSections['unreal_live_context_json'] = jsonEncode(ctx);
          }
          wb.documents[proj.id] = proj.copyWith(sections: nextSections);
        }

        // Scenario 1: UE 5.9 MCP + Release Gate + rich .uproject snapshot + [BUILT]/[ACTIVE]/[QUEUED]
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();
        wb.passActiveEpic(wb.selectedEpicId!);

        final richCtx = <String, dynamic>{
          'project_name': 'ShellbreakerUE5',
          'current_level': 'L_Shellbreaker_Proto',
          'game_mode': 'GM_Shellbreaker',
          'default_pawn': 'BP_PlayerMech',
          'input_assets': ['/Game/Input/IMC_Combat', '/Game/Input/IA_Move'],
          'blueprint_assets': ['/Game/Blueprints/BP_PlayerMech'],
          'data_assets': ['/Game/Data/DA_ShellbreakerTuning'],
          'widget_assets': ['/Game/UI/WBP_MechHUD'],
          'level_assets': ['/Game/Maps/L_Shellbreaker_Proto'],
          'verse_files': <String>[],
          'recent_errors': ['LogBlueprint: Warning: Accessed None', '   '],
        };
        setLiveContext(wb, richCtx);

        final dartUe5 = wb.activeEpicMcpPayload(wb.selectedEpicSpec!);
        final nodeUe5 = await renderViaNode(wb, uprojectContext: richCtx);
        expect(nodeUe5, equals(dartUe5));
        expect(dartUe5, contains('- Release Gate: '));
        expect(dartUe5, contains('## Release Epic Roadmap (v0.1 · 1/3 Passed)'));

        // Scenario 2: UE6 Verse ([int]/[logic]/[float]) + blank _empty_context() suppresses snapshot header
        wb.setTargetEngine(UnrealTargetEngine.ue6Verse);
        wb.addEpicTuningParam(
          wb.selectedEpicId!,
          key: 'WaveCount',
          value: '3',
          unit: 'count',
        );
        wb.addEpicTuningParam(
          wb.selectedEpicId!,
          key: 'bAllowAirDash',
          value: 'true',
          unit: 'bool',
        );
        final emptyCtx = <String, dynamic>{
          'project_name': '',
          'current_level': '',
          'game_mode': '',
          'default_pawn': '',
          'input_assets': <String>[],
          'blueprint_assets': <String>[],
          'data_assets': <String>[],
          'widget_assets': <String>[],
          'level_assets': <String>[],
          'verse_files': <String>[],
          'recent_errors': <String>['   '],
        };
        setLiveContext(wb, emptyCtx);

        final dartUe6 = wb.activeEpicMcpPayload(wb.selectedEpicSpec!);
        expect(dartUe6, isNot(contains('## Live Unreal Project Snapshot')));
        final nodeUe6 = await renderViaNode(wb, uprojectContext: emptyCtx);
        expect(nodeUe6, equals(dartUe6));
        expect(nodeUe6, contains('- WaveCount: 3 count [int]'));
        expect(nodeUe6, contains('- bAllowAirDash: true bool [logic]'));

        // Scenario 3: v0.2 Upgrading Epic with Locked Baseline & +Delta Upgrades
        setLiveContext(wb, null);
        await wb.openProgressiveReleaseCopilot();
        wb.applyProgressivePreset(wb.progressiveDraft!.presets.first.id);
        wb.commitProgressiveReleaseDraft();
        final upgradingEpic = wb.activeReleaseEpics.firstWhere(
          (e) => e.upgradeDeltas.isNotEmpty,
        );
        wb.selectEpic(upgradingEpic.id);

        final dartV02 = wb.activeEpicMcpPayload(wb.selectedEpicSpec!);
        final nodeV02 = await renderViaNode(wb);
        expect(nodeV02, equals(dartV02));
        expect(dartV02, contains('- Locked Baseline:'));

        // Scenario 4: FOCUSED PIE REVISION PASS with multiple open [FIX] IDs
        wb.flagEpicFix(wb.selectedEpicId!, 'Projectile clips ramp corner');
        wb.flagEpicFix(wb.selectedEpicId!, 'Muzzle flash lags 1 frame');
        final dartFix = wb.activeEpicMcpPayload(wb.selectedEpicSpec!);
        final nodeFix = await renderViaNode(wb);
        expect(nodeFix, equals(dartFix));
        expect(dartFix, contains('FOCUSED PIE REVISION PASS (2 OPEN [FIX])'));
      },
    );

    testWidgets(
      '32. Per-.uproject Google Sign-In Browser Handoff: URL params -> Google login -> smart .uproject match -> 127.0.0.1 callback redirect',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wb = WorkbenchProvider(enableAutoLoad: false);

        // Security check: reject privileged ports (<1024) and invalid CSRF state
        wb.applyDeepLinkParams(const {
          'unreal_auth': '1',
          'port': '80',
          'state': 'valid_state_12345',
        });
        expect(wb.hasPendingUnrealAuth, isFalse);
        wb.applyDeepLinkParams(const {
          'unreal_auth': '1',
          'port': '54321',
          'state': 'bad!',
        });
        expect(wb.hasPendingUnrealAuth, isFalse);

        // Create SHELLBREAKER and RAILJACK, keeping SHELLBREAKER active so .uproject auto-match proves smart matching
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();
        final shellbreakerProjId = wb.activeProject!.id;

        wb.createNewProject();
        wb.loadPresetSpark('railjack');
        wb.approveRootSpecAndLaunchWorkbench();
        final railjackProjId = wb.activeProject!.id;
        final expectedRailjackTreeIds = <String>[
          railjackProjId,
          wb.activeReleaseId!,
          ...wb.activeReleaseEpicDocs.map((e) => e.id),
        ];
        expect(railjackProjId, isNot(equals(shellbreakerProjId)));
        wb.switchProject(shellbreakerProjId);

        // Apply valid Unreal Sign-In Handoff query params while logged out
        wb.applyDeepLinkParams(const {
          'unreal_auth': '1',
          'port': '54321',
          'state': 'nonce_abcdef123456',
          'uproject': 'RailjackUE5',
        });
        expect(wb.hasPendingUnrealAuth, isTrue);

        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('unreal_handoff_overlay')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('unreal_handoff_google_signin_btn')),
          findsOneWidget,
        );

        // Simulate signing in with Google -> overlay switches to project confirmation pre-matching RAILJACK
        wb.setAiAccessRecordsForTest(
          const [],
          overrideEmail: 'henryyoungchoi@gmail.com',
        );
        await tester.pumpAndSettle();

        expect(wb.effectiveUnrealAuthProjectId, equals(railjackProjId));
        expect(
          find.byKey(const ValueKey('unreal_handoff_approve_btn')),
          findsOneWidget,
        );

        final prevHttp = GeminiAgentClient.testHttpPost;
        final prevAuthProvider = GeminiAgentClient.authTokenProvider;
        final prevRedirect = debugBrowserRedirectInterceptor;
        String? capturedRedirect;
        String? capturedTokenProjectId;
        final flushedDocIds = <String>[];

        wb.testOverrideUserUid = 'uid_handoff_test';
        wb.testCloudDocumentSaver = (uid, doc) async {
          expect(uid, equals('uid_handoff_test'));
          flushedDocIds.add(doc.id);
        };
        GeminiAgentClient.authTokenProvider =
            ({bool forceRefresh = false}) async => 'fake-firebase-id-token';
        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
          if (uri.path.endsWith('/unrealLink/token')) {
            final decoded = body is String && body.isNotEmpty
                ? jsonDecode(body) as Map<String, dynamic>
                : const <String, dynamic>{};
            capturedTokenProjectId = decoded['projectId']?.toString();
            return http.Response(
              jsonEncode({
                'ok': true,
                'projectId': capturedTokenProjectId,
                'linkToken': 'lyr_handoff_token_998877665544',
              }),
              200,
            );
          }
          return http.Response('{"error":{"message":"Not found"}}', 404);
        };
        debugBrowserRedirectInterceptor = (url) {
          expect(flushedDocIds, containsAll(expectedRailjackTreeIds));
          capturedRedirect = url;
          return true;
        };

        try {
          await tester.tap(
            find.byKey(const ValueKey('unreal_handoff_approve_btn')),
          );
          await tester.pumpAndSettle();

          expect(flushedDocIds, containsAll(expectedRailjackTreeIds));
          expect(capturedTokenProjectId, equals(railjackProjId));
          expect(
            capturedRedirect,
            equals(
              'http://127.0.0.1:54321/callback?state=nonce_abcdef123456&token=lyr_handoff_token_998877665544&project=RAILJACK+DRIFT',
            ),
          );
          expect(wb.hasPendingUnrealAuth, isFalse);
          expect(
            find.byKey(const ValueKey('unreal_handoff_overlay')),
            findsNothing,
          );
        } finally {
          wb.testOverrideUserUid = null;
          wb.testCloudDocumentSaver = null;
          GeminiAgentClient.testHttpPost = prevHttp;
          GeminiAgentClient.authTokenProvider = prevAuthProvider;
          debugBrowserRedirectInterceptor = prevRedirect;
        }
      },
    );

    testWidgets(
      '33. Blueprint-Only policy enforces Zero C++ across ROOT_MCP_CONTEXT, sanitizer strips C++ leakage, Stage 1 hides UE6 toggle, and UE6 Verse + Scene Editor remains ready',
      (tester) async {
        // 1. Default Stage 1 Spark & presets default to UE 5.9 Blueprint-Only (Zero C++)
        final defaultSpec = ProjectConceptBlueprint();
        expect(defaultSpec.targetEngine, equals(UnrealTargetEngine.ue5Mcp));
        for (final entry in UnrealSparkPresets.entries) {
          final preset = UnrealSparkPresets.byId(entry.id);
          expect(preset.targetEngine, equals(UnrealTargetEngine.ue5Mcp));
          expect(preset.assetPolicy, contains('Blueprint DataAsset'));
          expect(preset.assetPolicy, isNot(contains('PrimaryDataAsset')));
        }

        final shellbreaker = UnrealSparkPresets.byId('shellbreaker');
        final e01 = shellbreaker.initialEpics.first;
        final fullBpPayload = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: shellbreaker,
          epic: e01,
        );
        expect(
          fullBpPayload,
          contains('Target Architecture: 100% Blueprint-Only (.uasset)'),
        );
        expect(
          fullBpPayload,
          contains(
            'Code Policy: STRICT BLUEPRINT-ONLY — NEVER create or edit C++ files (.h/.cpp)',
          ),
        );
        expect(
          fullBpPayload,
          contains('author 100% in Blueprints (.uasset) with zero C++ (.h/.cpp)'),
        );

        // 2. [FIX] mode footer reflects Blueprint-Only on ue5Mcp vs Verse + Scene Graph on ue6Verse
        final e01WithFix = e01.deepCopy();
        e01WithFix.fixes.add(
          EpicPieFix(
            id: 'fx_bp_only',
            text: 'Claw dash capsule misses ramp edge',
            resolved: false,
          ),
        );
        final fixBpPayload = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: shellbreaker,
          epic: e01WithFix,
          targetOverride: UnrealTargetEngine.ue5Mcp,
        );
        expect(
          fixBpPayload,
          contains(
            'compile/save modified Blueprint (.uasset) assets (strictly zero C++ .h/.cpp)',
          ),
        );
        final fixUe6Payload = UnrealMcpPayloadBuilder.buildEpicMcpPayload(
          rootSpec: shellbreaker,
          epic: e01WithFix,
          targetOverride: UnrealTargetEngine.ue6Verse,
        );
        expect(
          fixUe6Payload,
          contains(
            'compile/save modified Verse & Scene Graph assets (zero C++ .h/.cpp)',
          ),
        );

        // 3. UnrealSpecGuard strips accidental C++ class/file leakage
        final sanitizedCpp = UnrealSpecGuard.sanitizeLine(
          'Create UCLASS(Blueprintable) PlayerMech.h and PlayerMech.cpp with UPROPERTY(EditAnywhere) and UFUNCTION(BlueprintCallable)',
        );
        expect(sanitizedCpp, contains('Blueprint Class'));
        expect(sanitizedCpp, contains('PlayerMech Blueprint'));
        expect(sanitizedCpp, contains('Instance Editable'));
        expect(sanitizedCpp, contains('Blueprint Event'));
        expect(sanitizedCpp, isNot(contains('.cpp')));
        expect(sanitizedCpp, isNot(contains('.h')));
        expect(sanitizedCpp, isNot(contains('UCLASS')));
        expect(sanitizedCpp, isNot(contains('UPROPERTY')));
        expect(sanitizedCpp, isNot(contains('UFUNCTION')));

        // 4. Stage 1 UI hides premature UE6 toggle and shows read-only Blueprint-Only badge
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final wb = WorkbenchProvider(enableAutoLoad: false);
        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('stage1_target_ue5')), findsNothing);
        expect(find.byKey(const ValueKey('stage1_target_ue6')), findsNothing);
        expect(
          find.byKey(const ValueKey('stage1_blueprint_only_badge')),
          findsOneWidget,
        );
        expect(find.text('UE 5.9 · Blueprint Only'), findsOneWidget);
      },
    );
  });
}
