import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:layers_agentic/agents/concept/project_concept_schemas.dart';
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
import 'package:layers_agentic/services/local_vault_service.dart';
import 'package:layers_agentic/services/storage/vault_storage_interface.dart';
import 'package:layers_agentic/utils/unreal_context_builder.dart';
import 'package:layers_agentic/utils/unreal_spec_guard.dart';

void main() {
  group('Unreal Engine 5 Core Foundation (Round 2/10)', () {
    test(
      '1. UnrealArchitectureMode parses strings, detects C++ sparks, and avoids 1 UU label clutter',
      () {
        expect(
          UnrealArchitectureMode.fromString('cppHybrid'),
          equals(UnrealArchitectureMode.cppHybrid),
        );
        expect(
          UnrealArchitectureMode.fromString('cpp_hybrid'),
          equals(UnrealArchitectureMode.cppHybrid),
        );
        expect(
          UnrealArchitectureMode.fromString('C++ Hybrid'),
          equals(UnrealArchitectureMode.cppHybrid),
        );
        expect(
          UnrealArchitectureMode.fromString('blueprint'),
          equals(UnrealArchitectureMode.blueprint),
        );
        expect(
          UnrealArchitectureMode.fromString('bp'),
          equals(UnrealArchitectureMode.blueprint),
        );
        expect(
          UnrealArchitectureMode.fromString('dim3d'),
          equals(UnrealArchitectureMode.blueprint),
        );
        expect(
          UnrealArchitectureMode.fromString('dim2d'),
          equals(UnrealArchitectureMode.blueprint),
        );
        expect(
          UnrealArchitectureMode.fromString(''),
          equals(UnrealArchitectureMode.blueprint),
        );
        expect(
          UnrealArchitectureMode.fromString(null),
          equals(UnrealArchitectureMode.blueprint),
        );

        expect(
          UnrealArchitectureMode.detectFromSpark(
            'Third-person action RPG in C++ with UPROPERTY stats and GAS',
          ),
          equals(UnrealArchitectureMode.cppHybrid),
        );
        expect(
          UnrealArchitectureMode.detectFromSpark(
            'Top-down crab arena brawler',
          ),
          equals(UnrealArchitectureMode.blueprint),
        );

        expect(
          UnrealArchitectureMode.blueprint.pillLabel,
          equals('Blueprint-First'),
        );
        expect(
          UnrealArchitectureMode.cppHybrid.pillLabel,
          equals('C++ & BP Hybrid'),
        );
        expect(
          UnrealArchitectureMode.blueprint.tuningColumnLabel,
          equals('Exposed BP Var'),
        );
        expect(
          UnrealArchitectureMode.cppHybrid.tuningColumnLabel,
          equals('UPROPERTY(EditAnywhere) Var'),
        );
        expect(
          UnrealArchitectureMode.blueprint.distanceUnit,
          equals('cm'),
        );
        expect(
          UnrealArchitectureMode.blueprint.speedUnit,
          equals('cm/s'),
        );
        for (final mode in UnrealArchitectureMode.values) {
          expect(mode.shortLabel, isNot(contains('1 UU')));
          expect(mode.pillLabel, isNot(contains('1 UU')));
          expect(mode.fullLabel, isNot(contains('1 UU')));
          expect(mode.architectureContract, isNot(contains('1 UU')));
        }
      },
    );

    test(
      '2. UnrealSpecGuard flags Godot/Unity leakage, scales m/px to cm, and normalizes PascalCase & IA_* keys',
      () {
        for (final leaky in const [
          'res://scenes/arena.tscn',
          'CharacterBody3D',
          '@export var speed',
          'InputMap',
          'GameObject',
          'MonoBehaviour',
          '12 m/s',
          '240 px/s',
        ]) {
          expect(
            UnrealSpecGuard.containsEngineLeakage(leaky),
            isTrue,
            reason: 'Expected leakage detection on "$leaky"',
          );
        }

        for (final clean in const [
          '/Game/Maps/Lvl_ArenaProto.umap',
          'BP_CrabPlayer',
          'ACharacter',
          'IA_ClawDash',
          '620 cm/s',
        ]) {
          expect(
            UnrealSpecGuard.containsEngineLeakage(clean),
            isFalse,
            reason: 'Expected clean Unreal token "$clean"',
          );
        }

        expect(
          UnrealSpecGuard.sanitizeTuningKey('max_walk_speed'),
          equals('MaxWalkSpeed'),
        );
        expect(
          UnrealSpecGuard.sanitizeTuningKey('@export var claw_dash_cooldown'),
          equals('ClawDashCooldown'),
        );
        expect(
          UnrealSpecGuard.sanitizeTuningKey('bAllowAirDash'),
          equals('AllowAirDash'),
        );

        expect(
          UnrealSpecGuard.sanitizeInputActionName('claw_dash'),
          equals('IA_ClawDash'),
        );
        expect(
          UnrealSpecGuard.sanitizeInputActionName('move_forward'),
          equals('IA_MoveForward'),
        );
        expect(
          UnrealSpecGuard.sanitizeInputActionName('IA_PrimaryFire'),
          equals('IA_PrimaryFire'),
        );

        expect(
          UnrealSpecGuard.scaleTuningValue('6.2', 'm/s'),
          equals('620'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('MaxWalkSpeed', 'm/s'),
          equals('cm/s'),
        );
        expect(
          UnrealSpecGuard.scaleTuningValue('1.84', 'm'),
          equals('184'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('CapsuleHeight', 'm'),
          equals('cm'),
        );
        expect(
          UnrealSpecGuard.scaleTuningValue('260', 'px/s'),
          equals('650'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('MoveSpeed', 'px/s'),
          equals('cm/s'),
        );
        expect(
          UnrealSpecGuard.scaleTuningValue('48', 'px'),
          equals('120'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('HitboxWidth', 'px'),
          equals('cm'),
        );
        expect(
          UnrealSpecGuard.scaleTuningValue('600', 'cm/s'),
          equals('600'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('DashCooldown', 's'),
          equals('s'),
        );
        expect(
          UnrealSpecGuard.scaleTuningValue('55', 'deg'),
          equals('55'),
        );
        expect(
          UnrealSpecGuard.normalizeUnrealUnit('CameraPitch', 'deg'),
          equals('deg'),
        );

        final lineClean = UnrealSpecGuard.sanitizeLine(
          'Spawn CharacterBody3D in res://scenes/arena_proto.tscn moving at 6.5 m/s with SpringArm3D and InputMap seamlessly',
        );
        expect(lineClean, contains('650 cm/s'));
        expect(lineClean, contains('USpringArmComponent'));
        expect(lineClean, contains('Enhanced Input'));
        expect(lineClean, contains('/Game/Maps/Lvl_ArenaProto.umap'));
        expect(lineClean.toLowerCase(), isNot(contains('seamlessly')));
        expect(UnrealSpecGuard.containsEngineLeakage(lineClean), isFalse);

        final dirtyFeat = FeatureSpec(
          id: 'f1',
          code: 'F01',
          title: 'Claw Dash Movement',
          goal: 'Dash 4.5 m in res://scenes/arena_proto.tscn',
          inScope: ['8-way CharacterBody3D locomotion'],
          doneWhen: ['Press Space -> CharacterBody3D moves 4.5 m'],
          controls: [
            EpicControlBinding(
              action: 'claw_dash',
              trigger: 'Started (Space)',
              rule: 'Launch 18 m/s for 0.25 s',
            ),
          ],
          tuning: [
            EpicTuningParam(key: 'max_walk_speed', value: '6.2', unit: 'm/s'),
            EpicTuningParam(key: '@export var dash_range', value: '4.5', unit: 'm'),
          ],
          cues: ['Emit GPUParticles3D trail for 0.2 s'],
          checks: [
            EpicPieCheck(
              id: 'chk1',
              text: 'Press Space -> CharacterBody3D dashes 4.5 m in Playtest',
            ),
          ],
        );

        final cleanFeat = UnrealSpecGuard.sanitizeFeatureSpec(dirtyFeat);
        expect(cleanFeat.controls.single.action, equals('IA_ClawDash'));
        expect(cleanFeat.tuning[0].key, equals('MaxWalkSpeed'));
        expect(cleanFeat.tuning[0].value, equals('620'));
        expect(cleanFeat.tuning[0].unit, equals('cm/s'));
        expect(cleanFeat.tuning[1].key, equals('DashRange'));
        expect(cleanFeat.tuning[1].value, equals('450'));
        expect(cleanFeat.tuning[1].unit, equals('cm'));
        expect(
          UnrealSpecGuard.containsEngineLeakage(cleanFeat.goal),
          isFalse,
        );
        expect(
          UnrealSpecGuard.containsEngineLeakage(cleanFeat.cues.single),
          isFalse,
        );
        expect(
          UnrealSpecGuard.containsEngineLeakage(cleanFeat.checks.single.text),
          isFalse,
        );

        final dirtyEpic = EpicSpec(
          id: 'ep1',
          code: 'E01',
          title: 'Player Movement & Camera',
          goal: 'Move CharacterBody3D smoothly in res://scenes/arena_proto.tscn',
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/player_mech.tscn',
              role: 'Player CharacterBody3D & SpringArm3D rig',
            ),
          ],
          features: [dirtyFeat],
        );
        final cleanEpic = UnrealSpecGuard.sanitizeEpicSpec(
          dirtyEpic,
          mode: UnrealArchitectureMode.cppHybrid,
        );
        expect(
          UnrealSpecGuard.containsEngineLeakage(cleanEpic.goal),
          isFalse,
        );
        expect(
          cleanEpic.sceneOwnership.single.path,
          equals('/Game/Blueprints/BP_PlayerMech'),
        );
        expect(
          UnrealSpecGuard.containsEngineLeakage(
            cleanEpic.sceneOwnership.single.role,
          ),
          isFalse,
        );

        final leakyBp = ProjectConceptBlueprint(
          gameTitle: 'LEAKTEST',
          pitch: 'Move CharacterBody3D at 6.0 m/s seamlessly',
          coreLoop: ['Move', 'Dash'],
          cameraContract: 'SpringArm3D 14.5 m @ -52 deg pitch',
          characterScale: 'CharacterBody3D height 1.8 m, move_speed 6.0 m/s',
          inputContract: 'InputMap (claw_dash)',
          assetPolicy: 'CSGBox3D + @export vars + Resource (.tres)',
          outOfScope: ['main menu'],
          initialEpics: [dirtyEpic],
        );
        final cleanBp = UnrealSpecGuard.sanitizeConceptBlueprint(
          raw: leakyBp,
          modeOverride: UnrealArchitectureMode.blueprint,
        );
        expect(cleanBp.cameraContract, contains('USpringArmComponent'));
        expect(cleanBp.cameraContract, contains('1450 cm'));
        expect(cleanBp.inputContract, contains('Enhanced Input'));
        expect(cleanBp.outOfScope.single, equals('No main menu'));
        expect(UnrealSpecGuard.containsEngineLeakage(cleanBp.pitch), isFalse);
        expect(
          UnrealSpecGuard.containsEngineLeakage(cleanBp.cameraContract),
          isFalse,
        );
      },
    );

    test(
      '3. UnrealContextBuilder formats Ultimate Engine CoPilot GDD and BUILD / FIX / UPGRADE prompts',
      () {
        final f01 = FeatureSpec(
          id: 'feat_1',
          code: 'F01',
          title: 'Locomotion & Camera Rig',
          status: FeatureStatus.queued,
          goal: 'Move player at 620 cm/s under overhead SpringArm camera.',
          inScope: ['WASD movement on XY plane', 'Mouse cursor ground aim'],
          doneWhen: ['Press W -> Pawn moves smoothly at 620 cm/s in PIE'],
          controls: [
            EpicControlBinding(
              action: 'IA_Move',
              trigger: 'Triggered (WASD)',
              rule: 'Planar move at MaxWalkSpeed 620 cm/s',
            ),
          ],
          tuning: [
            EpicTuningParam(key: 'MaxWalkSpeed', value: '620', unit: 'cm/s'),
          ],
          cues: ['Orient mesh smoothly toward cursor aim point'],
          checks: [
            EpicPieCheck(
              id: 'c1',
              text: 'Hold W -> Player traverses 620 cm in 1.0 s',
            ),
          ],
        );
        final f02 = FeatureSpec(
          id: 'feat_2',
          code: 'F02',
          title: 'Armored Claw Dash',
          status: FeatureStatus.queued,
          goal: 'Trigger a committed 450 cm forward dash with brief cooldown.',
          inScope: ['Impulse dash along facing vector', 'Cooldown timer'],
          doneWhen: ['Press Space -> Character dashes 450 cm'],
          controls: [
            EpicControlBinding(
              action: 'IA_ClawDash',
              trigger: 'Started (Space)',
              rule: 'Launch 1800 cm/s for 0.25 s; Cooldown 0.65 s',
            ),
          ],
          tuning: [
            EpicTuningParam(key: 'DashSpeed', value: '1800', unit: 'cm/s'),
          ],
          cues: ['Emit cyan Niagara dash ribbon'],
          checks: [
            EpicPieCheck(
              id: 'c2',
              text: 'Press Space -> Dash launches forward 450 cm cleanly',
            ),
          ],
        );

        final epic = EpicSpec(
          id: 'epic_1',
          code: 'E01',
          title: 'Player Movement & Camera',
          goal: 'Establish responsive twin-stick character movement.',
          sceneOwnership: [
            EpicSceneOwnership(
              path: '/Game/Blueprints/BP_CrabPlayer',
              role: 'ACharacter Pawn + USpringArmComponent',
            ),
            EpicSceneOwnership(
              path: '/Game/Maps/Lvl_ArenaProto.umap',
              role: 'Greybox combat test arena',
            ),
          ],
          stateFlow: ['Idle', 'Move', 'Dash', 'Recovery'],
          interruptRules: ['Dash locks standard steering until Recovery ends'],
          features: [f01, f02],
        );

        final rootSpec = ProjectConceptBlueprint(
          gameTitle: 'SHELLBREAKER',
          pitch: 'Tactical Crab Brawler — Smash armored foes in compact arenas.',
          coreLoop: ['Move & Aim', 'Dash Strike', 'Break Shell'],
          pillars: ['Every dash commits to a lane'],
          tradeOffs: [
            const TradeOffRule(
              prefer: 'Instant arcade acceleration',
              avoid: 'Heavy momentum turn inertia',
            ),
          ],
          outOfScope: ['No main menu or save slots'],
          initialEpics: [epic],
        );

        final gdd = UnrealContextBuilder.buildCoPilotGddMarkdown(
          rootSpec: rootSpec,
          epicsByReleaseLabel: {
            'v0.1 · Prototype': [epic],
          },
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(gdd, contains('# PROJECT GDD · SHELLBREAKER'));
        expect(gdd, contains('Blueprint-First'));
        expect(gdd, contains('§01'));
        expect(gdd, contains('§02'));
        expect(gdd, contains('§03'));
        expect(gdd, contains('§04'));
        expect(gdd, contains('§05'));
        expect(gdd, contains('/Game/Blueprints/BP_CrabPlayer'));
        expect(gdd, contains('F01'));
        expect(gdd, contains('F02'));
        expect(gdd, isNot(contains('1 UU')));
        expect(UnrealSpecGuard.containsEngineLeakage(gdd), isFalse);

        // First slice BUILD prompt
        final buildF01Prompt = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: rootSpec,
          epic: epic,
          feature: f01,
          releaseVersion: 'v0.1',
          releaseOrder: ['v0.1'],
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(
          buildF01Prompt,
          contains('[UE5_COPILOT TASK=BUILD TARGET=F01'),
        );
        expect(buildF01Prompt, contains('/Game/Blueprints/BP_CrabPlayer'));
        expect(buildF01Prompt, contains('@FIRST_SLICE:'));
        expect(buildF01Prompt, contains('TARGET=[F01]'));
        expect(buildF01Prompt, contains('DO_NOT_BUILD=[F02]'));
        expect(buildF01Prompt, contains('IA_Move'));
        expect(buildF01Prompt, contains('MaxWalkSpeed'));
        expect(buildF01Prompt, contains('@PIE_GATE:'));
        expect(
          UnrealSpecGuard.containsEngineLeakage(buildF01Prompt),
          isFalse,
        );

        // Pass F01 and open a [FIX] on F02 -> FIX compact task
        f01.status = FeatureStatus.passed;
        f01.checks.single.passed = true;
        f02.fixes.add(
          EpicPieFix(id: 'fx_1', text: 'Dash clips sloped arena corners'),
        );
        final fixF02Prompt = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: rootSpec,
          epic: epic,
          feature: f02,
          releaseVersion: 'v0.1',
          releaseOrder: ['v0.1'],
          mode: UnrealArchitectureMode.cppHybrid,
        );
        expect(
          fixF02Prompt,
          contains('[UE5_COPILOT TASK=FIX TARGET=F02'),
        );
        expect(fixF02Prompt, contains('KEEP=[F01]'));
        expect(fixF02Prompt, contains('@FIX_NOW:'));
        expect(fixF02Prompt, contains('Dash clips sloped arena corners'));
        expect(fixF02Prompt, contains('C++ & BP Hybrid'));

        // v0.2 Upgrade Delta prompt
        f02.fixes.clear();
        f02.status = FeatureStatus.passed;
        f02.checks.single.passed = true;
        f02.releaseDelta = '+Chain second dash on shell break';
        f02.releaseDeltaChecks.add(
          EpicPieCheck(
            id: 'c2_delta',
            text: 'Break shell -> Cooldown resets immediately',
          ),
        );
        final upgradeF02Prompt = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: rootSpec,
          epic: epic,
          feature: f02,
          releaseVersion: 'v0.2',
          releaseOrder: ['v0.1', 'v0.2'],
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(
          upgradeF02Prompt,
          contains('[UE5_COPILOT TASK=DELTA TARGET=F02'),
        );
        expect(upgradeF02Prompt, contains('@DELTA v0.2: +Chain second dash on shell break'));
        expect(
          upgradeF02Prompt,
          contains('Dash launches forward 450 cm cleanly'),
        );
        expect(
          upgradeF02Prompt,
          contains('Break shell -> Cooldown resets immediately'),
        );

        final epicBrief = UnrealContextBuilder.buildEpicArchitectureContext(
          rootSpec: rootSpec,
          epic: epic,
          releaseVersion: 'v0.1',
          releaseOrder: ['v0.1'],
          mode: UnrealArchitectureMode.blueprint,
        );
        expect(epicBrief, contains('[UE5_COPILOT TASK=EPIC_BRIEF TARGET=E01'));
        expect(epicBrief, contains('Blueprint-First'));
        expect(UnrealSpecGuard.containsEngineLeakage(epicBrief), isFalse);

        final fullMd = UnrealContextBuilder.buildFullProjectSpecMarkdown(
          rootSpec: rootSpec,
          epicsByReleaseLabel: {'v0.1 · Prototype': [epic]},
          mode: UnrealArchitectureMode.cppHybrid,
        );
        expect(fullMd, contains('# ROOT_UNREAL_CONTEXT · SHELLBREAKER'));
        expect(fullMd, contains('C++ & BP Hybrid'));
        expect(UnrealSpecGuard.containsEngineLeakage(fullMd), isFalse);
      },
    );

    testWidgets(
      '4. WorkbenchCopilotMixin, Top Bar GDD Export & Stage 2 Copy / Preview CoPilot Prompt workflow',
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

        expect(
          wb.unrealArchitectureMode,
          equals(UnrealArchitectureMode.blueprint),
        );
        final gddExport = wb.buildCoPilotGddExport();
        expect(gddExport.filename, equals('shellbreaker_copilot_gdd.md'));
        expect(gddExport.content, contains('# PROJECT GDD · SHELLBREAKER'));

        final e01 = wb.activeReleaseEpics.first;
        final f02 = e01.features.firstWhere((f) => f.code == 'F02');
        wb.selectFeature(e01.id, f02.id);

        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('top_bar_copilot_gdd_btn')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('copy_copilot_prompt_btn')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('preview_copilot_prompt_btn')),
          findsOneWidget,
        );
        expect(find.text('⚡ Copy CoPilot Prompt'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('preview_copilot_prompt_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('[UE5_COPILOT TASK=BUILD TARGET=F02'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('dialog_copy_copilot_prompt_btn')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('close_copilot_preview_btn')),
        );
        await tester.pumpAndSettle();

        wb.flagFeatureFix(e01.id, f02.id, 'Dash clips corner ramp');
        await tester.pumpAndSettle();
        expect(find.text('🔧 Copy CoPilot [FIX] Prompt (1)'), findsOneWidget);
        expect(
          wb.activeCoPilotPrompt(),
          contains('[UE5_COPILOT TASK=FIX TARGET=F02'),
        );
      },
    );

    test(
      '5. Round 4 Unreal Migration: TextStyleGuide, Schemas, Blueprint.architectureMode, ReleasePlanner & Stage 2 Edits',
      () async {
        // 1) LayersTextStyleGuide emits canonical Unreal Engine 5 rules with 0 off-engine leakage
        expect(LayersTextStyleGuide.compactStyleRules, contains('UNREAL ENGINE 5'));
        expect(LayersTextStyleGuide.compactStyleRules, contains('PascalCase'));
        expect(LayersTextStyleGuide.compactStyleRules, contains('Enhanced Input'));
        expect(LayersTextStyleGuide.compactStyleRules, contains('cm/s'));
        expect(
          UnrealSpecGuard.containsEngineLeakage(
            LayersTextStyleGuide.compactStyleRules,
          ),
          isFalse,
        );

        // 2) Stage 1 tool schemas use commit_unreal_root_spec & patch_unreal_root_spec with architectureMode
        expect(rootSpecToolSchema['name'], equals('commit_unreal_root_spec'));
        expect(
          patchRootSpecToolSchema['name'],
          equals('patch_unreal_root_spec'),
        );
        final rootProps = (rootSpecToolSchema['parameters']
            as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
        expect(rootProps.containsKey('architectureMode'), isTrue);
        expect(
          (rootProps['architectureMode'] as Map)['enum'],
          equals(['blueprint', 'cppHybrid']),
        );
        expect(
          UnrealSpecGuard.containsEngineLeakage(jsonEncode(rootSpecToolSchema)),
          isFalse,
        );
        expect(
          UnrealSpecGuard.containsEngineLeakage(
            jsonEncode(patchRootSpecToolSchema),
          ),
          isFalse,
        );

        // 3) ProjectConceptBlueprint supports architectureMode round-trip & sanitization preservation
        final bp = ProjectConceptBlueprint(
          gameTitle: 'IRONCLAW',
          architectureMode: UnrealArchitectureMode.cppHybrid,
          pitch: 'Tight brawler — Dash in compact arena',
          coreLoop: ['Move', 'Dash'],
          initialEpics: [
            EpicSpec(
              id: 'ep1',
              code: 'E01',
              title: 'Player Movement',
              goal: 'Move in arena.',
              sceneOwnership: [
                EpicSceneOwnership(
                  path: 'Source/PlayerPawn.cpp',
                  role: 'C++ ACharacter movement base',
                ),
              ],
            ),
          ],
        );
        final roundTripped = ProjectConceptBlueprint.fromJson(bp.toJson());
        expect(
          roundTripped.architectureMode,
          equals(UnrealArchitectureMode.cppHybrid),
        );
        final sanitizedBp = UnrealSpecGuard.sanitizeConceptBlueprint(raw: bp);
        expect(
          sanitizedBp.architectureMode,
          equals(UnrealArchitectureMode.cppHybrid),
        );

        // 4) Stage 2 addFeatureSlice & addFeatureTuningParam normalize to PascalCase + cm/cm/s + IA_*
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();
        final e01 = wb.activeReleaseEpics.first;
        final added = wb.addFeatureSlice(
          e01.id,
          title: 'Wall Bounce Dash',
          goal: 'Ricochet cleanly along angled walls.',
        );
        expect(added, isNotNull);
        expect(added!.tuning.first.key, equals('SliceMagnitude'));
        expect(added.tuning.first.value, equals('250'));
        expect(added.tuning.first.unit, equals('cm'));
        expect(added.controls.first.action, equals('IA_PrimaryAction'));
        wb.addFeatureTuningParam(
          e01.id,
          added.id,
          key: 'dash_trail_fade_s',
          value: '6.2',
          unit: 'm/s',
        );
        final updatedAdded = wb.activeReleaseEpics.first.features
            .firstWhere((f) => f.id == added.id);
        final addedParam = updatedAdded.tuning
            .firstWhere((t) => t.key == 'DashTrailFadeS');
        expect(addedParam.value, equals('620'));
        expect(addedParam.unit, equals('cm/s'));

        // 5) ReleasePlannerAgent offline fallback v0.3 emits clean Unreal /Game/ assets & cm units
        final v03Draft = await ReleasePlannerAgent.proposeNextReleaseCopilot(
          rootSpec: bp,
          currentEpics: bp.initialEpics,
          targetVersion: 'v0.3',
          apiKey: '',
        );
        expect(v03Draft.candidateNewEpics, isNotEmpty);
        final cand = v03Draft.candidateNewEpics.first;
        expect(
          UnrealSpecGuard.containsEngineLeakage(cand.goal),
          isFalse,
        );
        expect(
          UnrealSpecGuard.containsEngineLeakage(cand.sceneOwnership.first.path),
          isFalse,
        );
        for (final feat in [
          ...cand.features,
          ...(v03Draft.candidateNewFeaturesByLineageKey['e01'] ??
              const <FeatureSpec>[]),
        ]) {
          expect(
            UnrealSpecGuard.containsEngineLeakage(feat.goal),
            isFalse,
          );
          for (final t in feat.tuning) {
            expect(['m', 'm/s', 'px', 'px/s'], isNot(contains(t.unit)));
          }
        }
      },
    );

    test(
      '6. Round 5 Starter Presets & All 4 Genre Fallback Archetypes emit 0 off-engine leakage in native Unreal',
      () async {
        expect(
          [for (final e in UnrealSparkPresets.entries) e.label],
          equals(['Shellbreaker', 'Railjack Drift', 'Ember Keep']),
        );

        final expectedModes = <String, UnrealArchitectureMode>{
          'shellbreaker': UnrealArchitectureMode.blueprint,
          'railjack': UnrealArchitectureMode.cppHybrid,
          'emberkeep': UnrealArchitectureMode.blueprint,
        };
        for (final id in const ['shellbreaker', 'railjack', 'emberkeep']) {
          final bp = UnrealSparkPresets.byId(id);
          expect(bp.architectureMode, equals(expectedModes[id]), reason: id);
          final jsonMap = bp.toJson()..remove('dimension');
          expect(
            UnrealSpecGuard.containsEngineLeakage(jsonEncode(jsonMap)),
            isFalse,
            reason: '$id raw preset leaked off-engine tokens',
          );
          final summary = Stage1ScopeSummary.fromBlueprint(bp);
          expect(summary.isLean, isTrue, reason: '$id scope warnings: ${summary.warnings}');
          expect(
            summary.firstTestScenePath,
            endsWith('.umap'),
            reason: id,
          );
        }

        final sb = UnrealSparkPresets.byId('shellbreaker');
        final sbAsCpp = ProjectConceptAgent.convertBlueprintArchitectureMode(
          sb,
          UnrealArchitectureMode.cppHybrid,
        );
        expect(sbAsCpp.architectureMode, equals(UnrealArchitectureMode.cppHybrid));
        expect(sbAsCpp.assetPolicy, contains('C++'));
        expect(
          sbAsCpp.initialEpics.first.features.first.tuning.first.value,
          equals('640'),
        );
        expect(
          sbAsCpp.initialEpics.first.features.first.tuning.first.unit,
          equals('cm/s'),
        );

        for (final prompt in const [
          'Slide mirror relays in puzzle room',
          'Hover skiff canyon drift racer',
          'Parkour air-dash obstacle course',
          'Twin-stick arena brawler with deployable turret',
        ]) {
          final off = await ProjectConceptAgent.draftSpecFromSpark(
            sparkPrompt: prompt,
            apiKey: '',
          );
          final jsonMap = off.toJson()..remove('dimension');
          expect(
            UnrealSpecGuard.containsEngineLeakage(jsonEncode(jsonMap)),
            isFalse,
            reason: 'Fallback leaked on "$prompt"',
          );
          final summary = Stage1ScopeSummary.fromBlueprint(off);
          expect(
            summary.firstTestScenePath,
            endsWith('.umap'),
            reason: prompt,
          );
        }
      },
    );

    test(
      '7. Round 7/10: TierType tooltips and extractLegacySceneOwnership emit clean UE5 paths with zero leakage',
      () {
        for (final tier in TierType.values) {
          expect(
            UnrealSpecGuard.containsEngineLeakage(tier.descriptionTooltip),
            isFalse,
            reason: 'Tooltip leaked on ${tier.name}: ${tier.descriptionTooltip}',
          );
          expect(tier.descriptionTooltip, isNot(contains('1 UU')));
        }

        final owned = extractLegacySceneOwnership(
          [
            'res://scenes/arena_proto.tscn — Arena combat map',
            '/Game/Blueprints/BP_PlayerMech.uasset — Player pawn',
          ],
          'res://scenes/boss_room.tscn',
        );
        expect(owned.length, equals(3));
        for (final item in owned) {
          expect(item.path, startsWith('/Game/'));
          expect(item.path, isNot(contains('res://')));
          expect(UnrealSpecGuard.containsEngineLeakage(item.path), isFalse);
        }
        expect(
          owned.any((o) => o.path == '/Game/Blueprints/BP_PlayerMech.uasset'),
          isTrue,
        );
      },
    );

    test(
      '8. Round 8/10: Legacy .layers.json archives, initVault LocalStorage docs, and Cloud snapshots auto-migrate to Unreal Engine 5',
      () async {
        // 1) importProjectFromJson auto-migrates legacy archive docs & strips retired metadata
        final legacyBundle = <String, dynamic>{
          'format': 'layers_project_v1',
          'projectId': 'mig_proj_1',
          'documents': [
            {
              'id': 'mig_proj_1',
              'title': 'CLAW MECH LEGACY',
              'tier': 'project',
              'childrenIds': ['mig_rel_1'],
              'sections': {
                'dimension': 'dim3d',
                'last_godot_sync_ms': '1700000000000',
                'current_stage': 'releaseWorkbench',
                'active_release_id': 'mig_rel_1',
                'selected_epic_id': 'mig_ep_1',
                'concept_blueprint_json': jsonEncode({
                  'gameTitle': 'CLAW MECH LEGACY',
                  'dimension': 'dim3d',
                  'pitch': 'Dash combat in res://scenes/arena_proto.tscn seamlessly.',
                  'cameraContract': 'SpringArm3D 14.5 m @ -52 deg pitch, 55 deg FOV',
                  'characterScale': 'CharacterBody3D 0.42 m radius moving at 6.2 m/s',
                  'inputContract': 'InputMap (claw_dash, move_axis)',
                  'initialEpics': [
                    {
                      'id': 'mig_ep_1',
                      'code': 'E01',
                      'title': 'Player Movement',
                      'goal': 'Dash 5.5 m using InputMap claw_dash.',
                      'sceneOwnership': [
                        {'path': 'res://scenes/arena_proto.tscn', 'role': 'Arena level'},
                      ],
                      'features': [
                        {
                          'id': 'f01',
                          'code': 'F01',
                          'title': 'Claw Dash',
                          'controls': [
                            {'action': 'claw_dash', 'trigger': 'Space', 'rule': 'Dash 5.5 m'},
                          ],
                          'tuning': [
                            {'key': 'dash_speed', 'value': '18.5', 'unit': 'm/s'},
                            {'key': 'dash_range', 'value': '5.5', 'unit': 'm'},
                          ],
                        },
                      ],
                    },
                  ],
                  'approved': true,
                }),
              },
            },
            {
              'id': 'mig_rel_1',
              'title': 'v0.1 · Prototype',
              'tier': 'release',
              'parentId': 'mig_proj_1',
              'childrenIds': ['mig_ep_1'],
              'sections': {
                'release_version': 'v0.1',
                'dimension': 'dim3d',
              },
            },
            {
              'id': 'mig_ep_1',
              'title': 'Player Movement',
              'tier': 'epic',
              'parentId': 'mig_rel_1',
              'childrenIds': [],
              'sections': {
                'code': 'E01',
                'release_version': 'v0.1',
                'last_godot_sync_ms': '1700000000000',
                'epic_spec_json': jsonEncode({
                  'id': 'mig_ep_1',
                  'code': 'E01',
                  'title': 'Player Movement',
                  'releaseVersion': 'v0.1',
                  'goal': 'Dash 5.5 m using InputMap in res://scenes/player_mech.tscn.',
                  'sceneOwnership': [
                    {'path': 'res://scenes/player_mech.tscn', 'role': 'CharacterBody3D root'},
                  ],
                  'features': [
                    {
                      'id': 'mig_f01',
                      'code': 'F01',
                      'title': 'Claw Dash',
                      'goal': 'Launch forward 5.5 m with @export dash_speed.',
                      'controls': [
                        {'action': 'claw_dash', 'trigger': 'Space', 'rule': 'Dash 5.5 m'},
                      ],
                      'tuning': [
                        {'key': 'dash_speed', 'value': '18.5', 'unit': 'm/s'},
                        {'key': 'dash_range', 'value': '5.5', 'unit': 'm'},
                      ],
                      'checks': [
                        {'id': 'c1', 'text': 'Tap Space -> Dash 5.5 m at 18.5 m/s', 'passed': false},
                      ],
                    },
                  ],
                }),
              },
            },
            {
              'id': 'mig_retired_gf',
              'title': 'Legacy File Doc',
              'tier': 'godot_file',
              'parentId': 'mig_ep_1',
              'childrenIds': [],
              'sections': {},
            },
          ],
        };

        final wb = WorkbenchProvider(enableAutoLoad: false);
        final importedId = wb.importProjectFromJson(jsonEncode(legacyBundle));
        expect(importedId, isNotNull);
        final projDoc = wb.documents[importedId!]!;
        expect(projDoc.sections.containsKey('dimension'), isFalse);
        expect(projDoc.sections.containsKey('last_godot_sync_ms'), isFalse);
        expect(
          UnrealSpecGuard.containsEngineLeakage(jsonEncode(wb.conceptDraft!.toJson())),
          isFalse,
        );

        final impEpic = wb.selectedEpicSpec!;
        expect(impEpic.sceneOwnership.first.path, startsWith('/Game/'));
        expect(impEpic.features.first.controls.first.action, equals('IA_ClawDash'));
        expect(impEpic.features.first.tuning[0].key, equals('DashSpeed'));
        expect(impEpic.features.first.tuning[0].value, equals('1850'));
        expect(impEpic.features.first.tuning[0].unit, equals('cm/s'));
        expect(impEpic.features.first.tuning[1].key, equals('DashRange'));
        expect(impEpic.features.first.tuning[1].value, equals('550'));
        expect(impEpic.features.first.tuning[1].unit, equals('cm'));
        expect(
          UnrealSpecGuard.containsEngineLeakage(wb.buildCoPilotGddExport().content),
          isFalse,
        );
        expect(
          UnrealSpecGuard.containsEngineLeakage(wb.activeCoPilotPrompt()),
          isFalse,
        );

        // 2) initVault() auto-migrates persisted LocalStorage docs on startup & writes clean docs back
        final vaultProj = TierDocument(
          id: 'vault_p1',
          title: 'VAULT MIGRATOR',
          tier: TierType.project,
          childrenIds: ['vault_r1'],
          sections: {
            'dimension': 'dim2d',
            'active_release_id': 'vault_r1',
            'selected_epic_id': 'vault_e1',
            'current_stage': 'releaseWorkbench',
            'concept_blueprint_json': jsonEncode({
              'gameTitle': 'VAULT MIGRATOR',
              'dimension': 'dim2d',
              'cameraContract': 'Camera2D follow at 320 px/s',
              'approved': true,
            }),
          },
        );
        final vaultRel = TierDocument(
          id: 'vault_r1',
          title: 'v0.1 · Prototype',
          tier: TierType.release,
          parentId: 'vault_p1',
          childrenIds: ['vault_e1'],
          sections: {'release_version': 'v0.1'},
        );
        final vaultEp = TierDocument(
          id: 'vault_e1',
          title: 'Vault Move Domain',
          tier: TierType.epic,
          parentId: 'vault_r1',
          sections: {
            'code': 'E01',
            'release_version': 'v0.1',
            'epic_spec_json': jsonEncode({
              'id': 'vault_e1',
              'code': 'E01',
              'title': 'Vault Move Domain',
              'releaseVersion': 'v0.1',
              'sceneOwnership': [
                {'path': 'res://scenes/room.tscn', 'role': 'Room scene'},
              ],
              'features': [
                {
                  'id': 'vf1',
                  'code': 'F01',
                  'title': 'Planar Move',
                  'tuning': [
                    {'key': 'move_speed', 'value': '320', 'unit': 'px/s'},
                  ],
                },
              ],
            }),
          },
        );
        final fakeBackend = _FakeVaultBackend(
          VaultLoadResult(
            documents: {
              vaultProj.id: vaultProj,
              vaultRel.id: vaultRel,
              vaultEp.id: vaultEp,
            },
            activeDocumentId: vaultProj.id,
            modelName: GeminiAgentClient.pinnedLiveFlashModel,
            planningModel: GeminiAgentClient.pinnedLiveFlashModel,
            thinkingLevel: 'LOW',
          ),
        );
        final prevBackend = LocalVaultService.testBackendOverride;
        LocalVaultService.testBackendOverride = fakeBackend;
        try {
          final wb2 = WorkbenchProvider(enableAutoLoad: false);
          await wb2.initVault();
          expect(wb2.documents[vaultProj.id]!.sections.containsKey('dimension'), isFalse);
          final migVaultEp = wb2.selectedEpicSpec!;
          expect(migVaultEp.sceneOwnership.first.path, startsWith('/Game/'));
          expect(migVaultEp.features.first.tuning.first.key, equals('MoveSpeed'));
          expect(migVaultEp.features.first.tuning.first.value, equals('800'));
          expect(migVaultEp.features.first.tuning.first.unit, equals('cm/s'));
          expect(fakeBackend.savedDocs.containsKey(vaultProj.id), isTrue);
          expect(fakeBackend.savedDocs.containsKey(vaultEp.id), isTrue);
        } finally {
          LocalVaultService.testBackendOverride = prevBackend;
        }

        // 3) applyRemoteDocumentSnapshot() migrates incoming Cloud Firestore Epic in cppHybrid mode & preserves updated_at_ms
        wb.setArchitectureMode(UnrealArchitectureMode.cppHybrid);
        await Future<void>.delayed(Duration.zero);
        final targetEpId = wb.selectedEpicId!;
        final remoteEpDoc = wb.documents[targetEpId]!.copyWith(
          sections: {
            ...wb.documents[targetEpId]!.sections,
            'updated_at_ms': '9999999999999',
            'epic_spec_json': jsonEncode({
              'id': targetEpId,
              'code': 'E01',
              'title': 'Turret Domain',
              'releaseVersion': 'v0.1',
              'goal': 'Fire bolts with @export bolt_speed at 24.0 m/s.',
              'sceneOwnership': [
                {'path': 'res://scenes/turret.tscn', 'role': 'Turret actor'},
              ],
              'features': [
                {
                  'id': 'tf1',
                  'code': 'F01',
                  'title': 'Bolt Burst',
                  'goal': 'Spawn projectile using @export bolt_speed.',
                  'controls': [
                    {'action': 'fire_burst', 'trigger': 'LMB', 'rule': 'Fire at 24.0 m/s'},
                  ],
                  'tuning': [
                    {'key': 'bolt_speed', 'value': '24.0', 'unit': 'm/s'},
                  ],
                },
              ],
            }),
          },
        );
        final remoteSnap = <String, TierDocument>{
          for (final entry in wb.documents.entries) entry.key: entry.value,
          targetEpId: remoteEpDoc,
        };
        expect(wb.applyRemoteDocumentSnapshot(remoteSnap), isTrue);
        expect(wb.documents[targetEpId]!.sections['updated_at_ms'], equals('9999999999999'));
        final syncedEp = wb.selectedEpicSpec!;
        expect(syncedEp.sceneOwnership.first.path, startsWith('/Game/'));
        expect(syncedEp.goal, contains('UPROPERTY(EditAnywhere)'));
        expect(syncedEp.features.first.controls.first.action, equals('IA_FireBurst'));
        expect(syncedEp.features.first.tuning.first.key, equals('BoltSpeed'));
        expect(syncedEp.features.first.tuning.first.value, equals('2400'));
        expect(syncedEp.features.first.tuning.first.unit, equals('cm/s'));
      },
    );

    testWidgets(
      '9. Round 9/10: Multi-release v0.1 -> v0.2 -> v0.3 CoPilot Delta Prompt UI, GDD semver sorting, locked baseline reference, and Blueprint <-> C++ round-trip',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1) Stage 1 Blueprint <-> C++ round-trip with nested paths & roles
        final bpRoundTrip = ProjectConceptBlueprint(
          gameTitle: 'ROUND TRIP TEST',
          architectureMode: UnrealArchitectureMode.blueprint,
          initialEpics: [
            EpicSpec(
              id: 'rt_e01',
              code: 'E01',
              title: 'Dash & Turret',
              goal: 'Move cleanly.',
              sceneOwnership: [
                EpicSceneOwnership(
                  path: '/Game/Maps/Lvl_Arena.umap',
                  role: 'Combat arena level',
                ),
                EpicSceneOwnership(
                  path: '/Game/Blueprints/Combat/BP_ClawDash.uasset',
                  role: 'Dash state & Exposed BP Vars',
                ),
                EpicSceneOwnership(
                  path: 'Source/Shellbreaker/Private/TurretRig.cpp',
                  role: 'Aim math & UPROPERTY(EditAnywhere) tuning',
                ),
              ],
              links: const [
                'Blueprint /Game/Blueprints/Combat/BP_ClawDash.uasset',
              ],
            ),
          ],
        );

        final asCpp = ProjectConceptAgent.convertBlueprintArchitectureMode(
          bpRoundTrip,
          UnrealArchitectureMode.cppHybrid,
        );
        final cppOwners = asCpp.initialEpics.first.sceneOwnership;
        expect(cppOwners[0].path, equals('/Game/Maps/Lvl_Arena.umap'));
        expect(cppOwners[1].path, equals('Source/ClawDash.cpp'));
        expect(cppOwners[1].role, contains('UPROPERTY(EditAnywhere)'));
        expect(cppOwners[1].role, isNot(contains('Exposed BP')));
        expect(
          asCpp.initialEpics.first.links.first,
          equals('C++ Source/ClawDash.cpp'),
        );

        final backToBp = ProjectConceptAgent.convertBlueprintArchitectureMode(
          asCpp,
          UnrealArchitectureMode.blueprint,
        );
        final bpOwners = backToBp.initialEpics.first.sceneOwnership;
        expect(bpOwners[1].path, equals('/Game/Blueprints/BP_ClawDash'));
        expect(bpOwners[1].role, contains('Exposed BP Var'));
        expect(bpOwners[2].path, equals('/Game/Blueprints/BP_TurretRig'));
        expect(bpOwners[2].role, contains('Exposed BP Var'));
        expect(
          backToBp.initialEpics.first.links.first,
          equals('Blueprint /Game/Blueprints/BP_ClawDash'),
        );

        // 2) Chronological semver sorting & delta visibility in GDD and Full Spec Markdown
        final sortFeat = FeatureSpec(
          id: 'sf1',
          code: 'F01',
          title: 'Claw Dash',
          introducedIn: 'v0.1',
          goal: 'Dash forward cleanly.',
          releaseDelta: '+55ms Hit-Stop freeze',
        );
        final sortEpic = EpicSpec(
          id: 'se1',
          code: 'E01',
          title: 'Movement',
          goal: 'Own movement.',
          features: [sortFeat],
        );
        final outOfOrderMap = <String, List<EpicSpec>>{
          'v0.3 · Boss': [sortEpic.deepCopy(releaseVersionOverride: 'v0.3')],
          'v0.1 · Prototype': [
            sortEpic.deepCopy(releaseVersionOverride: 'v0.1'),
          ],
          'v0.2 · Juice': [sortEpic.deepCopy(releaseVersionOverride: 'v0.2')],
        };
        final gdd = UnrealContextBuilder.buildCoPilotGddMarkdown(
          rootSpec: bpRoundTrip,
          epicsByReleaseLabel: outOfOrderMap,
        );
        expect(gdd.indexOf('### v0.1'), lessThan(gdd.indexOf('### v0.2')));
        expect(gdd.indexOf('### v0.2'), lessThan(gdd.indexOf('### v0.3')));
        expect(gdd, contains('(Delta: +55ms Hit-Stop freeze)'));

        final fullMd = UnrealContextBuilder.buildFullProjectSpecMarkdown(
          rootSpec: bpRoundTrip,
          epicsByReleaseLabel: outOfOrderMap,
        );
        expect(
          fullMd.indexOf('## Release v0.1'),
          lessThan(fullMd.indexOf('## Release v0.2')),
        );
        expect(
          fullMd.indexOf('## Release v0.2'),
          lessThan(fullMd.indexOf('## Release v0.3')),
        );

        // 3) Multi-release v0.1 -> v0.2 -> v0.3 flow + Stage 2 Delta button & Locked Baseline Prompt
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.setArchitectureMode(UnrealArchitectureMode.cppHybrid);
        wb.approveRootSpecAndLaunchWorkbench();

        final draftV02 = await wb.openProgressiveReleaseCopilot();
        expect(draftV02, isNotNull);
        expect(draftV02!.targetVersion, equals('v0.2'));

        // Inject metric tuning onto a candidate new Feature to verify sanitization on materialization
        String? injectedNewFeatId;
        String? injectedNewFeatKey;
        if (draftV02.candidateNewFeaturesByLineageKey.isNotEmpty) {
          final firstEntry = draftV02.candidateNewFeaturesByLineageKey.entries.first;
          if (firstEntry.value.isNotEmpty) {
            final candFeat = firstEntry.value.first;
            candFeat.tuning.add(
              EpicTuningParam(key: 'shock_radius', value: '4.5', unit: 'm'),
            );
            injectedNewFeatKey = firstEntry.key;
            injectedNewFeatId = candFeat.id;
            if (!wb.isProgressiveNewFeatureChosen(candFeat.id)) {
              wb.toggleProgressiveNewFeature(firstEntry.key, candFeat.id);
            }
          }
        }
        expect(injectedNewFeatId, isNotNull);
        // Ensure at least one upgrade option is selected as well
        for (final entry in draftV02.upgradesByLineageKey.entries) {
          if (entry.value.isNotEmpty && !entry.value.any((u) => u.chosen)) {
            wb.toggleProgressiveUpgrade(entry.key, entry.value.first.id);
          }
        }

        final relV02 = wb.commitProgressiveReleaseDraft();
        expect(relV02, isNotNull);
        expect(wb.activeReleaseVersionTag, equals('v0.2'));

        // Verify injected new Feature was sanitized on commit
        final matNewFeat = wb.activeReleaseEpics
            .firstWhere((ep) => ep.lineageKey.toLowerCase() == injectedNewFeatKey)
            .features
            .firstWhere((f) => f.introducedIn == 'v0.2');
        final shockParam = matNewFeat.tuning.firstWhere(
          (t) => t.key == 'ShockRadius',
        );
        expect(shockParam.value, equals('450'));
        expect(shockParam.unit, equals('cm'));

        // Advance v0.2 -> v0.3
        final draftV03 = await wb.openProgressiveReleaseCopilot();
        expect(draftV03, isNotNull);
        expect(draftV03!.targetVersion, equals('v0.3'));
        if (!wb.hasSelectedProgressiveChanges &&
            draftV03.candidateNewEpics.isNotEmpty) {
          wb.toggleProgressiveNewEpic(draftV03.candidateNewEpics.first.id);
        }
        final relV03 = wb.commitProgressiveReleaseDraft();
        expect(relV03, isNotNull);
        expect(wb.projectReleaseOrder, equals(['v0.1', 'v0.2', 'v0.3']));

        // Switch back to v0.2, verify Delta button & CoPilot Delta execution prompt
        wb.selectActiveRelease(relV02!);
        EpicSpec? deltaEpic;
        FeatureSpec? deltaFeat;
        EpicSpec? lockedEpic;
        FeatureSpec? lockedFeat;
        for (final ep in wb.activeReleaseEpics) {
          for (final feat in wb.visibleFeaturesForEpic(ep, releaseVersion: 'v0.2')) {
            if (deltaFeat == null &&
                feat.releaseDelta.trim().isNotEmpty &&
                feat.openFixesCount == 0) {
              deltaEpic = ep;
              deltaFeat = feat;
            }
            if (lockedFeat == null &&
                feat.isLockedBaselineInRelease('v0.2') &&
                feat.openFixesCount == 0) {
              lockedEpic = ep;
              lockedFeat = feat;
            }
          }
        }
        expect(deltaEpic, isNotNull);
        expect(deltaFeat, isNotNull);
        expect(lockedEpic, isNotNull);
        expect(lockedFeat, isNotNull);

        wb.selectFeature(deltaEpic!.id, deltaFeat!.id);
        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        expect(find.text('⚡ Copy CoPilot Delta Prompt'), findsOneWidget);
        final deltaPrompt = wb.activeFeatureBuildPrompt(
          wb.selectedEpicSpec!,
          wb.selectedFeatureSpec!,
        );
        expect(deltaPrompt, contains('@EXEC: Apply ONLY @DELTA v0.2 to ${deltaFeat.code}'));

        // Select locked [v0.1] baseline Feature in v0.2 and verify Locked Baseline prompt
        wb.selectFeature(lockedEpic!.id, lockedFeat!.id);
        await tester.pumpAndSettle();

        expect(find.text('⚡ Copy CoPilot Prompt'), findsOneWidget);
        final lockedPrompt = wb.activeFeatureBuildPrompt(
          wb.selectedEpicSpec!,
          wb.selectedFeatureSpec!,
        );
        expect(
          lockedPrompt,
          contains('[UE5_COPILOT TASK=LOCKED_BASELINE TARGET=${lockedFeat.code}'),
        );
        expect(lockedPrompt, contains('Do not rebuild'));
      },
    );

    test(
      '10. Round 10/10: Live Stage 1 <-> Stage 2 architecture mode sync across toggle, Co-Designer refine, and Undo plus codebase invariant gate',
      () async {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();

        final e01 = wb.selectedEpicSpec!;
        final f01 = wb.selectedFeatureSpec!;
        expect(
          e01.sceneOwnership.any((o) => o.path == '/Game/Blueprints/BP_PlayerMech'),
          isTrue,
        );

        wb.toggleFeatureCheck(e01.id, f01.id, f01.checks.first.id, true);
        wb.flagFeatureFix(e01.id, f01.id, 'Dash clips corner');

        // 1) Toggle Blueprint-First -> C++ & BP Hybrid syncs Stage 2 Epics while preserving Feature checks & [FIX]
        wb.setArchitectureMode(UnrealArchitectureMode.cppHybrid);
        final cppEpic = wb.selectedEpicSpec!;
        final cppFeat = wb.selectedFeatureSpec!;
        expect(
          cppEpic.sceneOwnership.any((o) => o.path == 'Source/PlayerMech.cpp'),
          isTrue,
        );
        expect(cppFeat.checks.first.passed, isTrue);
        expect(
          cppFeat.fixes.any((fx) => fx.text.contains('Dash clips corner')),
          isTrue,
        );
        final cppPrompt = wb.activeCoPilotPrompt();
        expect(cppPrompt, contains('Source/PlayerMech.cpp'));
        expect(cppPrompt, contains('UPROPERTY(EditAnywhere, BlueprintReadWrite)'));

        // 2) Undo restores both Stage 1 & materialized Stage 2 Epics back to Blueprint-First
        expect(wb.undoStage1Edit(), isTrue);
        expect(
          wb.selectedEpicSpec!.sceneOwnership.any(
            (o) => o.path == '/Game/Blueprints/BP_PlayerMech',
          ),
          isTrue,
        );

        // 3) Stage 1 Co-Designer Refine switching to C++ hybrid also syncs materialized Stage 2 Epics
        final refined = await wb.applyStage1CoDesignInstruction(
          'Switch architecture to C++ hybrid',
        );
        expect(refined, isNotNull);
        expect(
          wb.selectedEpicSpec!.sceneOwnership.any(
            (o) => o.path == 'Source/PlayerMech.cpp',
          ),
          isTrue,
        );

        // 4) Codebase line-cap & 1 UU clutter invariant gate across lib/
        for (final entity in Directory('lib').listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final normPath = entity.path.replaceAll('\\', '/');
          final lines = entity.readAsLinesSync();
          if (normPath.startsWith('lib/screens/') ||
              normPath.startsWith('lib/providers/') ||
              normPath.startsWith('lib/services/')) {
            expect(
              lines.length,
              lessThanOrEqualTo(950),
              reason: '$normPath exceeded 950-line cap (${lines.length})',
            );
          }
          if (normPath != 'lib/utils/unreal_spec_guard.dart') {
            final joined = lines.join('\n');
            expect(
              joined,
              isNot(contains('1 UU')),
              reason: '$normPath contains banned 1 UU label clutter',
            );
          }
        }
      },
    );

    test(
      '11. Round 1/5: Frontier Gemini 4 Argon architect routing, failover to Hydrogen, and per-model cost tracking',
      () async {
        expect(
          GeminiAgentClient.resolveModelSequence('gemini-4-argon'),
          equals(['gemini-4-argon', 'gemini-4-hydrogen', 'gemini-flash-latest']),
        );
        expect(
          GeminiAgentClient.resolveModelSequence('gemini-4-neon'),
          equals(['gemini-4-neon', 'gemini-4-hydrogen', 'gemini-flash-latest']),
        );
        expect(
          GeminiAgentClient.resolveModelSequence('gemini-4-hydrogen'),
          equals(['gemini-4-hydrogen', 'gemini-flash-latest']),
        );

        final prevMock = GeminiAgentClient.testMockResponder;
        final prevHttp = GeminiAgentClient.testHttpPost;
        final prevDelay = GeminiAgentClient.testBaseRetryDelay;
        GeminiAgentClient.resetCapabilityCacheForTest();
        GeminiAgentClient.resetUsage();
        GeminiAgentClient.testMockResponder = null;
        GeminiAgentClient.testBaseRetryDelay = Duration.zero;

        final requestedUrls = <String>[];
        final capturedBodies = <Map<String, dynamic>>[];

        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
          requestedUrls.add(uri.toString());
          if (body is String && body.isNotEmpty) {
            capturedBodies.add(jsonDecode(body) as Map<String, dynamic>);
          }
          if (uri.toString().contains('gemini-4-argon')) {
            return http.Response('{"error":{"message":"Argon busy"}}', 503);
          }
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"planned": true}'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        };

        try {
          final wbIdle = WorkbenchProvider(enableAutoLoad: false);
          expect(wbIdle.activeModelIndicatorLabel, equals('⚡ Argon'));

          final res = await GeminiAgentClient.generateJson(
            prompt: 'Draft Unreal project architecture',
            apiKey: 'test-key-1234',
            preferredModel: 'gemini-4-argon',
            thinkingLevel: 'MEDIUM',
          );

          expect(res, isNotNull);
          expect(res!['planned'], isTrue);
          expect(requestedUrls.first, contains('models/gemini-4-argon:'));
          expect(requestedUrls.last, contains('models/gemini-4-hydrogen:'));
          final argonCfg =
              capturedBodies.first['generationConfig'] as Map<String, dynamic>;
          expect(argonCfg['thinkingConfig'], equals({'thinkingLevel': 'MEDIUM'}));
          expect(argonCfg.containsKey('temperature'), isFalse);
          expect(GeminiAgentClient.lastResolvedModel, equals('gemini-4-hydrogen'));
          expect(GeminiAgentClient.lastFallbackReason, contains('HTTP 503'));

          GeminiAgentClient.resetUsage();
          GeminiAgentClient.recordUsage(
            inputTokens: 1000000,
            outputTokens: 1000000,
            model: 'gemini-4-argon',
          );
          expect(GeminiAgentClient.totalEstimatedCostUsd, closeTo(12.0, 0.0001));

          GeminiAgentClient.recordUsage(
            inputTokens: 1000000,
            outputTokens: 1000000,
            model: 'gemini-4-hydrogen',
          );
          expect(GeminiAgentClient.totalEstimatedCostUsd, closeTo(21.0, 0.0001));
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
          GeminiAgentClient.testHttpPost = prevHttp;
          GeminiAgentClient.testBaseRetryDelay = prevDelay;
          GeminiAgentClient.resetCapabilityCacheForTest();
          GeminiAgentClient.resetUsage();
        }
      },
    );

    test(
      '12. Round 2/5: UnrealPromptCompactor telegraphic DSL cuts >=30% tokens across BUILD/FIX/DELTA/EPIC_BRIEF & preserves GDD/Spec readability',
      () {
        expect(
          UnrealPromptCompactor.compactProse(
            'When the player triggers the IA_ClawDash input in /Game/Maps/Lvl_ShellbreakerProto.umap, '
            'the ACharacter should be launching a forward 550 cm dash with Source/PlayerMech.cpp and DashDistanceCm.',
          ),
          allOf([
            contains('IA_ClawDash'),
            contains('/Game/Maps/Lvl_ShellbreakerProto.umap'),
            contains('ACharacter'),
            contains('550 cm'),
            contains('Source/PlayerMech.cpp'),
            contains('DashDistanceCm'),
            isNot(contains('When the player')),
            isNot(contains('should be')),
          ]),
        );

        expect(
          UnrealPromptCompactor.compactCuts([
            'No main menu or save slots',
            'No co-op multiplayer',
          ]),
          equals('!main menu or save slots | !co-op multiplayer'),
        );

        final spec = UnrealSparkPresets.byId('shellbreaker');
        final epic = spec.initialEpics.first.deepCopy();
        final f02 = epic.features.firstWhere((f) => f.code == 'F02');
        f02.checks.first.passed = true;
        f02.checks.add(
          EpicPieCheck(
            id: 'c_open',
            text: 'Dash into cracked guard -> Shield shatters with Niagara burst',
            passed: false,
          ),
        );

        // BUILD compact vs readable savings >= 30%
        final buildCompact = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: spec,
          epic: epic,
          feature: f02,
          mode: UnrealArchitectureMode.cppHybrid,
          compact: true,
        );
        final buildReadable = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: spec,
          epic: epic,
          feature: f02,
          mode: UnrealArchitectureMode.cppHybrid,
          compact: false,
        );
        final buildStats =
            UnrealPromptCompactor.compareSavings(buildCompact, buildReadable);
        expect(buildStats.savedPercent, greaterThanOrEqualTo(30));
        expect(buildReadable, contains('ULTIMATE ENGINE COPILOT — BUILD FEATURE'));
        expect(UnrealSpecGuard.containsEngineLeakage(buildCompact), isFalse);
        expect(buildCompact, isNot(contains('1 UU')));

        // FIX mode prunes already-passing PIE checks into a summary count + cuts >= 30%
        f02.fixes.add(
          EpicPieFix(id: 'fx_corner', text: 'Dash clips south pillar bevel'),
        );
        final fixCompact = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: spec,
          epic: epic,
          feature: f02,
          mode: UnrealArchitectureMode.cppHybrid,
          compact: true,
        );
        final fixReadable = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: spec,
          epic: epic,
          feature: f02,
          mode: UnrealArchitectureMode.cppHybrid,
          compact: false,
        );
        expect(fixCompact, contains('1/2 PASS (keep)'));
        expect(fixCompact, contains('@FIX_NOW: [FIX] Dash clips south pillar bevel'));
        expect(
          UnrealPromptCompactor.compareSavings(fixCompact, fixReadable).savedPercent,
          greaterThanOrEqualTo(30),
        );

        // DELTA mode savings >= 30%
        f02.fixes.clear();
        f02.releaseDelta = '+55ms Hit-Stop freeze & radial shockwave ring';
        final deltaCompact = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: spec,
          epic: epic,
          feature: f02,
          releaseVersion: 'v0.2',
          compact: true,
        );
        final deltaReadable = UnrealContextBuilder.buildCoPilotFeaturePrompt(
          rootSpec: spec,
          epic: epic,
          feature: f02,
          releaseVersion: 'v0.2',
          compact: false,
        );
        expect(
          UnrealPromptCompactor.compareSavings(deltaCompact, deltaReadable).savedPercent,
          greaterThanOrEqualTo(30),
        );

        // EPIC_BRIEF savings >= 30%
        final epicCompact = UnrealContextBuilder.buildEpicArchitectureContext(
          rootSpec: spec,
          epic: epic,
          compact: true,
        );
        final epicReadable = UnrealContextBuilder.buildEpicArchitectureContext(
          rootSpec: spec,
          epic: epic,
          compact: false,
        );
        expect(
          UnrealPromptCompactor.compareSavings(epicCompact, epicReadable).savedPercent,
          greaterThanOrEqualTo(30),
        );

        // Heading-indexed GDD keeps # / ## / ### headings; Full Spec stays human Markdown
        final gdd = UnrealContextBuilder.buildCoPilotGddMarkdown(
          rootSpec: spec,
          epicsByReleaseLabel: {'v0.1 · Prototype': spec.initialEpics},
        );
        for (final heading in const [
          '# PROJECT GDD · SHELLBREAKER',
          '## §01 Concept & 30s Loop',
          '## §02 Global UE5 Contracts',
          '## §03 Pillars & Trade-Offs',
          '## §04 Hard Scope Cuts',
          '## §05 Release Architecture',
          '### v0.1 · Prototype',
        ]) {
          expect(gdd, contains(heading));
        }

        final fullSpec = UnrealContextBuilder.buildFullProjectSpecMarkdown(
          rootSpec: spec,
          epicsByReleaseLabel: {'v0.1 · Prototype': spec.initialEpics},
        );
        expect(fullSpec, contains('# UE5 EPIC ARCHITECTURE BRIEF'));
        expect(fullSpec, contains('# ULTIMATE ENGINE COPILOT — BUILD FEATURE'));
      },
    );

    testWidgets(
      '13. Stage 2 CoPilot Preview toggles Compact DSL vs Readable View with token savings badge (Feature & Epic)',
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

        final e01 = wb.activeReleaseEpics.first;
        final f02 = e01.features.firstWhere((f) => f.code == 'F02');
        wb.selectFeature(e01.id, f02.id);

        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        // Feature Preview: Compact DSL default + token badge + toggle to Readable View and back
        await tester.tap(
          find.byKey(const ValueKey('preview_copilot_prompt_btn')),
        );
        await tester.pumpAndSettle();

        final badgeFinder = find.byKey(
          const ValueKey('copilot_preview_token_badge'),
        );
        expect(badgeFinder, findsOneWidget);
        expect(
          find.descendant(
            of: badgeFinder,
            matching: find.textContaining('tok'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: badgeFinder,
            matching: find.textContaining('% vs MD'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('preview_mode_compact_btn')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('preview_mode_readable_btn')),
          findsOneWidget,
        );
        expect(
          find.textContaining('[UE5_COPILOT TASK=BUILD TARGET=F02'),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('preview_mode_readable_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('# ULTIMATE ENGINE COPILOT — BUILD FEATURE · F02'),
          findsOneWidget,
        );
        expect(
          find.textContaining('[UE5_COPILOT TASK=BUILD TARGET=F02'),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('dialog_copy_readable_prompt_btn')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('preview_mode_compact_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('[UE5_COPILOT TASK=BUILD TARGET=F02'),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('close_copilot_preview_btn')),
        );
        await tester.pumpAndSettle();

        // Epic Architecture Brief Preview: Compact DSL default + Readable View toggle
        wb.selectEpic(e01.id);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('preview_epic_brief_btn')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('preview_epic_brief_btn')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('[UE5_COPILOT TASK=EPIC_BRIEF TARGET=E01'),
          findsOneWidget,
        );
        expect(badgeFinder, findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('preview_mode_readable_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('# UE5 EPIC ARCHITECTURE BRIEF · E01'),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('close_copilot_preview_btn')),
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '14. Stage 2 Epic Domain Sheet inline §02 Ownership & §03 State Rules persist and flow into child Feature CoPilot prompts',
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

        final e01 = wb.activeReleaseEpics.first;
        wb.selectEpic(e01.id);

        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        // §02 Add owner -> persists & updates child Feature CoPilot prompt
        final addOwnerBtn = find.byKey(const ValueKey('epic_add_owner_btn'));
        await tester.ensureVisible(addOwnerBtn);
        await tester.tap(addOwnerBtn);
        await tester.pumpAndSettle();

        final pathInput = find.byKey(const ValueKey('epic_owner_path_input'));
        final roleInput = find.byKey(const ValueKey('epic_owner_role_input'));
        await tester.ensureVisible(pathInput);
        await tester.enterText(
          pathInput,
          '/Game/Player/AC_ShellMomentum.uasset',
        );
        await tester.ensureVisible(roleInput);
        await tester.enterText(roleInput, 'Momentum charge tracker');

        final saveOwnerBtn = find.byKey(const ValueKey('epic_owner_save_btn'));
        await tester.ensureVisible(saveOwnerBtn);
        await tester.tap(saveOwnerBtn);
        await tester.pumpAndSettle();

        final afterAdd = wb.selectedEpicSpec!;
        expect(
          afterAdd.sceneOwnership.any(
            (o) =>
                o.path == '/Game/Player/AC_ShellMomentum.uasset' &&
                o.role == 'Momentum charge tracker',
          ),
          isTrue,
        );
        final f02 = afterAdd.features.firstWhere((f) => f.code == 'F02');
        expect(
          wb.activeFeatureBuildPrompt(afterAdd, f02),
          contains('/Game/Player/AC_ShellMomentum.uasset'),
        );

        // §02 Edit & Delete that owner
        final lastIdx = afterAdd.sceneOwnership.length - 1;
        final editOwnerBtn = find.byKey(ValueKey('epic_owner_edit_$lastIdx'));
        await tester.ensureVisible(editOwnerBtn);
        await tester.tap(editOwnerBtn);
        await tester.pumpAndSettle();

        await tester.ensureVisible(roleInput);
        await tester.enterText(roleInput, 'Dash charge component');
        await tester.ensureVisible(saveOwnerBtn);
        await tester.tap(saveOwnerBtn);
        await tester.pumpAndSettle();

        expect(
          wb.selectedEpicSpec!.sceneOwnership[lastIdx].role,
          equals('Dash charge component'),
        );

        final deleteOwnerBtn = find.byKey(
          ValueKey('epic_owner_delete_$lastIdx'),
        );
        await tester.ensureVisible(deleteOwnerBtn);
        await tester.tap(deleteOwnerBtn);
        await tester.pumpAndSettle();

        expect(
          wb.selectedEpicSpec!.sceneOwnership.any(
            (o) => o.path == '/Game/Player/AC_ShellMomentum.uasset',
          ),
          isFalse,
        );

        // §03 Edit State Flow & Interrupt Rules -> flows into child Feature @STATES:
        final editStatesBtn = find.byKey(
          const ValueKey('epic_edit_states_btn'),
        );
        await tester.ensureVisible(editStatesBtn);
        await tester.tap(editStatesBtn);
        await tester.pumpAndSettle();

        final statesInput = find.byKey(const ValueKey('epic_states_input'));
        final interruptsInput = find.byKey(
          const ValueKey('epic_interrupts_input'),
        );
        await tester.ensureVisible(statesInput);
        await tester.enterText(
          statesInput,
          'Idle -> Sprint -> ArmoredDash -> Cooldown',
        );
        await tester.ensureVisible(interruptsInput);
        await tester.enterText(
          interruptsInput,
          'ArmoredDash cancels Sprint\nHitstun cancels ArmoredDash',
        );
        await tester.pumpAndSettle();

        final saveStatesBtn = find.byKey(
          const ValueKey('epic_states_save_btn'),
        );
        await tester.ensureVisible(saveStatesBtn);
        await tester.pumpAndSettle();
        await tester.tap(saveStatesBtn);
        await tester.pumpAndSettle();

        final afterStates = wb.selectedEpicSpec!;
        expect(
          afterStates.stateFlow,
          equals(const ['Idle', 'Sprint', 'ArmoredDash', 'Cooldown']),
        );
        expect(
          afterStates.interruptRules,
          equals(const [
            'ArmoredDash cancels Sprint',
            'Hitstun cancels ArmoredDash',
          ]),
        );

        final f02After = afterStates.features.firstWhere((f) => f.code == 'F02');
        final promptAfterStates = wb.activeFeatureBuildPrompt(
          afterStates,
          f02After,
        );
        expect(
          promptAfterStates,
          contains('@STATES: Idle -> Sprint -> ArmoredDash -> Cooldown'),
        );
        expect(promptAfterStates, contains('ArmoredDash cancels Sprint'));
        expect(promptAfterStates, contains('Hitstun cancels ArmoredDash'));
      },
    );
  });
}

class _FakeVaultBackend implements VaultStorageBackend {
  final VaultLoadResult initial;
  final Map<String, TierDocument> savedDocs = <String, TierDocument>{};

  _FakeVaultBackend(this.initial);

  @override
  Future<VaultLoadResult> loadVaultData() async => initial;

  @override
  Future<void> saveSettings({
    required String activeDocumentId,
    String? apiKey,
    String? modelName,
    String? planningModel,
    String? thinkingLevel,
    String? themeMode,
  }) async {}

  @override
  Future<void> saveDocument(TierDocument doc) async {
    savedDocs[doc.id] = doc;
  }

  @override
  Future<void> deleteDocument(String id) async {
    savedDocs.remove(id);
  }
}
