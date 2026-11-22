import 'package:flutter_test/flutter_test.dart';
import 'package:layers_agentic/models/agent_blueprints.dart';
import 'package:layers_agentic/models/epic_spec.dart';
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
          contains('ULTIMATE ENGINE COPILOT — BUILD FEATURE · F01'),
        );
        expect(buildF01Prompt, contains('/Game/Blueprints/BP_CrabPlayer'));
        expect(buildF01Prompt, contains('First-Slice'));
        expect(buildF01Prompt, contains('[ACTIVE TARGET ->] F01'));
        expect(buildF01Prompt, contains('[QUEUED — DO NOT BUILD YET] F02'));
        expect(buildF01Prompt, contains('IA_Move'));
        expect(buildF01Prompt, contains('MaxWalkSpeed'));
        expect(buildF01Prompt, contains('§05 PIE Playtest Gate'));
        expect(
          UnrealSpecGuard.containsEngineLeakage(buildF01Prompt),
          isFalse,
        );

        // Pass F01 and open a [FIX] on F02 -> FOCUSED [FIX] PASS
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
          contains('ULTIMATE ENGINE COPILOT — FOCUSED [FIX] PASS · F02'),
        );
        expect(fixF02Prompt, contains('[PASSED — DO NOT REGRESS] F01'));
        expect(
          fixF02Prompt,
          contains('## Open [FIX] Revisions to Resolve Now'),
        );
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
          contains('ULTIMATE ENGINE COPILOT — UPGRADE FEATURE DELTA · F02'),
        );
        expect(upgradeF02Prompt, contains('+Chain second dash on shell break'));
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
        expect(epicBrief, contains('# UE5 EPIC ARCHITECTURE BRIEF · E01'));
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
  });
}
