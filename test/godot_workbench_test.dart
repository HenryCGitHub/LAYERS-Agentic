import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/constants/tiers.dart';
import 'package:layers_agentic/models/feature_state.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/release_workbench_screen.dart';
import 'package:layers_agentic/theme/app_theme.dart';
import 'package:layers_agentic/utils/godot_gdscript_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GeminiAgentClient.testMockResponder = null;
    GeminiAgentClient.testHttpPost = null;
    GeminiAgentClient.resetUsage();
  });

  tearDown(() {
    GeminiAgentClient.testMockResponder = null;
    GeminiAgentClient.testHttpPost = null;
  });

  group('GodotGdscriptGuard', () {
    test('parses Godot 4 debugger stack traces into script paths, lines, and error kinds', () {
      final trace = GodotGdscriptGuard.parseDebuggerTrace(
        'E 0:00:02:0145   res://scripts/player.gd:42 @ _physics_process(): Invalid assignment of property "velocity" on null instance.',
      );
      expect(trace, isNotNull);
      expect(trace!.resPath, 'res://scripts/player.gd');
      expect(trace.lineNumber, 42);
      expect(trace.errorKind, 'Null Instance');
    });
  });

  group('Feature-First Progress', () {
    test('FeatureStateNode & getDocumentProgress stay <100% until Playtest Passed when 0 steps', () {
      final provider = WorkbenchProvider();
      final feat = TierDocument(
        id: 'feat_zero_steps',
        title: 'Player Dash',
        tier: TierType.feature,
      );
      provider.documents[feat.id] = feat;
      final unbuiltCp = FeatureStateNode(
        id: 'cp_0',
        name: '[v0.1] Core Dash',
        checklist: const [],
      );
      expect(unbuiltCp.progress, equals(0.0));
      expect(unbuiltCp.isCompleted, isFalse);

      final passedCp = unbuiltCp.copyWith(
        parameters: {'playtestPassed': 'true'},
      );
      expect(passedCp.isPlaytestPassed, isTrue);
      expect(passedCp.progress, equals(1.0));
      expect(passedCp.isCompleted, isTrue);
      FeatureStateNode.saveStatesToDocument(feat, [passedCp]);
      expect(provider.getDocumentProgress(feat.id), equals(100));
    });
  });

  group('Single Feature Step List & Clean Property Sheet Redesign', () {
    test(
      'lossless flattenLegacyNestedChecklistIfNeeded preserves step IDs, completion, and metadata',
      () {
        final cp = FeatureStateNode(
          id: 'cp_legacy',
          name: '[v0.1] Dash Prototype',
          checklist: [
            Subtask(
              id: 't_scene',
              text: 'Build Dash Scene',
              children: [
                Subtask(
                  id: 's_1',
                  text: 'Add DashTimer Child Node',
                  completed: true,
                  codeTargetFile: 'custom_snippet',
                  codeLanguage: 'Scene Dock → res://scenes/player_dash.tscn',
                  codeSnippet: 'Timer',
                  verification: 'DashTimer appears in Scene Tree.',
                  specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
                    instruction: 'Attach DashTimer under CharacterBody2D.',
                    area1Hierarchy: 'PlayerDash (CharacterBody2D)\n └─ DashTimer (Timer)',
                    verifyMode: 'editor',
                    stepRole: 'editor_setup',
                  ),
                ),
                Subtask(
                  id: 's_2',
                  text: 'Bind Dash Input Action',
                  completed: false,
                  codeTargetFile: 'custom_snippet',
                  codeLanguage: 'Project Settings → Input Map',
                  codeSnippet: '| Input Map | dash | Shift |',
                  verification: 'Shift triggers dash action.',
                  specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
                    instruction: 'Map Shift to dash in Input Map.',
                    area2Inspector: 'Wait Time: 0.2',
                    verifyMode: 'editor',
                    stepRole: 'inspector_setup',
                  ),
                ),
              ],
            ),
            Subtask(
              id: 't_code',
              text: 'Code Dash Impulse',
              children: [
                Subtask(
                  id: 's_3',
                  text: 'Apply Dash Velocity',
                  completed: false,
                  codeTargetFile: 'custom_snippet',
                  codeLanguage: 'res://scripts/player_dash.gd',
                  codeSnippet: 'velocity = dir * dash_speed',
                  verification: 'F6 -> Player dashes cleanly.',
                  specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
                    instruction: 'Multiply input direction by dash_speed.',
                    verifyMode: 'playtest',
                    stepRole: 'script_logic',
                  ),
                ),
              ],
            ),
          ],
        );

        expect(cp.totalChecklistCount, 3);
        expect(cp.completedChecklistCount, 1);
        expect(cp.flatSteps.map((s) => s.id), ['s_1', 's_2', 's_3']);

        final flattened = cp.flattenLegacyNestedChecklistIfNeeded();
        expect(flattened, isTrue);
        expect(cp.totalChecklistCount, 3);
        expect(cp.completedChecklistCount, 1);
        expect(cp.checklist.every((s) => s.children.isEmpty), isTrue);
        expect(cp.flatSteps.map((s) => s.id), ['s_1', 's_2', 's_3']);
        expect(cp.flatSteps.map((s) => s.completed), [true, false, false]);
        expect(cp.flatSteps[0].verification, 'DashTimer appears in Scene Tree.');
        expect(cp.flatSteps[1].codeSnippet, '| Input Map | dash | Shift |');
        expect(cp.flatSteps[2].codeLanguage, 'res://scripts/player_dash.gd');

        // Second call is an idempotent no-op.
        expect(cp.flattenLegacyNestedChecklistIfNeeded(), isFalse);

        final resolved = TaskHowToBlueprint.resolveUnifiedSteps(
          checkpointNode: cp,
          engineHint: 'Godot 4 (GDScript)',
        );
        expect(resolved, hasLength(3));
        expect(resolved.map((s) => s.resolvedDockStage), [
          GodotDockStage.scene,
          GodotDockStage.inspector,
          GodotDockStage.code,
        ]);
      },
    );

    Future<({
      WorkbenchProvider provider,
      TierDocument feat,
      FeatureStateNode cp,
    })> seedDashWorkbench() async {
      final provider = WorkbenchProvider();
      final proj = TierDocument(
        id: 'proj_dash_redesign',
        title: 'Dash Arena',
        tier: TierType.project,
        sections: {
          'tech_spec': 'Godot 4 (GDScript) · 2D Top-Down',
          'active_release_id': 'rel_dash_redesign',
          'current_stage': WorkbenchStage.releaseWorkbench.name,
        },
        childrenIds: ['rel_dash_redesign'],
      );
      final rel = TierDocument(
        id: 'rel_dash_redesign',
        title: 'v0.1 Prototype',
        tier: TierType.release,
        parentId: 'proj_dash_redesign',
        phase: 'v0.1',
        childrenIds: ['epic_dash_redesign'],
      );
      final epic = TierDocument(
        id: 'epic_dash_redesign',
        title: 'Movement Core',
        tier: TierType.epic,
        parentId: 'rel_dash_redesign',
        phase: 'v0.1',
        childrenIds: ['feat_dash_redesign'],
      );
      final cp = FeatureStateNode(
        id: 'cp_dash_redesign',
        name: '01 · PROTOTYPE',
        tuningParams: ['dash_speed: 640.0'],
        edgeCases: ['[STATE GUARD] Lock move while dash_timer active'],
        parameters: {
          'releaseVersion': 'v0.1',
          'primarySharedScriptOrScene': 'res://scripts/player_dash.gd',
        },
        checklist: [
          Subtask(
            id: 'st_scene',
            text: 'Build PlayerDash Scene Nodes',
            codeTargetFile: 'custom_snippet',
            codeLanguage: 'Scene Dock → res://scenes/player_dash.tscn',
            verification: 'PlayerDash + DashTimer exist in Scene Tree.',
            specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
              instruction: 'Create res://scenes/player_dash.tscn with DashTimer.',
              area1Hierarchy:
                  'PlayerDash (CharacterBody2D)\n├─ CollisionShape2D\n└─ DashTimer (Timer)',
              verifyMode: 'editor',
              stepRole: 'editor_setup',
            ),
          ),
          Subtask(
            id: 'st_insp',
            text: 'Tune Dash Export & Layer',
            codeTargetFile: 'custom_snippet',
            codeLanguage: 'Inspector & Project Settings',
            codeSnippet:
                '| Node / Category | Property | Value |\n| --- | --- | --- |\n| PlayerDash > CharacterBody2D | @export dash_speed | 640.0 |',
            verification: 'Inspector exposes dash_speed = 640.0.',
            specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
              instruction: 'Verify dash_speed in Inspector.',
              area2Inspector: 'dash_speed: 640.0',
              verifyMode: 'editor',
              stepRole: 'inspector_setup',
            ),
          ),
          Subtask(
            id: 'st_code',
            text: 'Implement Dash Velocity',
            codeTargetFile: 'custom_snippet',
            codeLanguage: 'res://scripts/player_dash.gd',
            codeSnippet:
                'extends CharacterBody2D\n+ @export var dash_speed: float = 640.0',
            verification: 'Pressing Shift moves player at dash_speed.',
            specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
              instruction:
                  'Implement _trigger_dash() in res://scripts/player_dash.gd.',
              verifyMode: 'playtest',
              stepRole: 'script_logic',
            ),
          ),
          Subtask(
            id: 'st_wire',
            text: 'Wire DashTimer Signal',
            codeTargetFile: 'custom_snippet',
            codeLanguage: 'Node Dock → Signals',
            codeSnippet:
                'DashTimer.timeout() ──► [PlayerDash._on_dash_timeout()]',
            verification: 'Press F6 -> Dash ends cleanly after timer.',
            specNotes: TaskHowToBlueprint.encodeThreeAreaNotes(
              instruction: 'Connect DashTimer.timeout to _on_dash_timeout().',
              verifyMode: 'playtest',
              stepRole: 'wire_and_verify',
            ),
          ),
        ],
      );
      final feat = TierDocument(
        id: 'feat_dash_redesign',
        title: 'Player Dash',
        tier: TierType.feature,
        parentId: 'epic_dash_redesign',
        phase: 'v0.1',
        sections: {
          'primary_asset': 'res://scripts/player_dash.gd',
        },
      );
      FeatureStateNode.saveStatesToDocument(feat, [cp]);

      provider.documents[proj.id] = proj;
      provider.documents[rel.id] = rel;
      provider.documents[epic.id] = epic;
      provider.documents[feat.id] = feat;
      provider.switchProject(proj.id);
      provider.selectFeature(feat.id, triggerAiSynthesis: false);
      return (provider: provider, feat: feat, cp: cp);
    }

    testWidgets(
      'Desktop Feature Brief & Playtest Card omits manual BUILD QUEUE/Inspector chrome and supports Guard + Pass Playtest',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final setup = await seedDashWorkbench();
        final provider = setup.provider;
        final feat = setup.feat;
        final cp = setup.cp;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: provider,
                builder: (_, __) => ReleaseWorkbenchScreen(workbench: provider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Streamlined Single-Card Brief & Playtest (zero manual step queue, inspector sheet, or @export chip clutter)
        expect(find.byKey(ValueKey('unified_header_${cp.id}')), findsOneWidget);
        expect(find.byKey(ValueKey('feature_status_badge_${cp.id}')), findsOneWidget);
        expect(find.text('Queued'), findsOneWidget);
        expect(find.byKey(ValueKey('playtest_gate_card_${cp.id}')), findsOneWidget);
        expect(find.byKey(ValueKey('task_sheet_feature_goal_${cp.id}')), findsOneWidget);
        expect(find.byKey(ValueKey('build_queue_rail_${cp.id}')), findsNothing);
        expect(find.text('BUILD QUEUE'), findsNothing);
        expect(find.text('🎛 PROPERTY & LAYER SHEET'), findsNothing);
        expect(find.textContaining('@EXPORT VARS:'), findsNothing);
        expect(find.text('+ Add Node'), findsNothing);

        // 2. Check [STATE GUARD] sign-off & Pass Playtest
        final guardCheck = find.byKey(ValueKey('playtest_guard_check_${cp.id}_0'));
        await tester.ensureVisible(guardCheck);
        await tester.tap(guardCheck);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.isGuardSignedOff(0, '[STATE GUARD] Lock move while dash_timer active'),
          isTrue,
        );

        final passBtn = find.byKey(ValueKey('playtest_gate_pass_btn_${cp.id}'));
        await tester.ensureVisible(passBtn);
        await tester.tap(passBtn);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.isPlaytestPassed,
          isTrue,
        );
        expect(find.text('Passed ✓'), findsWidgets);
      },
    );

    testWidgets(
      'Full Web Studio renders Connect Godot Dock chip, Copy Spec chip, Queued status badge, and Half-Screen 1-click Pass CTA',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final setup = await seedDashWorkbench();
        final provider = setup.provider;
        final feat = setup.feat;
        final cp = setup.cp;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: provider,
                builder: (_, __) => ReleaseWorkbenchScreen(workbench: provider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Desktop Web Studio shows Connect Godot chip, Copy Spec chip, and Queued status
        expect(
          find.byKey(ValueKey('connect_godot_plugin_chip_${cp.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('feature_header_copy_spec_btn_${cp.id}')),
          findsOneWidget,
        );
        expect(find.text('Queued'), findsWidgets);
        expect(
          find.byKey(ValueKey('workspace_mode_code_file_btn_${cp.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('code_file_workspace_${cp.id}')),
          findsNothing,
        );

        // 2. Resize to Split-Screen (< 700px) -> 1-line floating header with Pass Playtest CTA (no step dropdown)
        tester.view.physicalSize = const Size(620, 820);
        await tester.pumpAndSettle();

        expect(find.byKey(ValueKey('step_dropdown_${cp.id}')), findsNothing);
        final doneBtn = find.byKey(ValueKey('one_click_complete_next_btn_${cp.id}'));
        expect(doneBtn, findsOneWidget);

        await tester.tap(doneBtn);
        await tester.pumpAndSettle();
        final afterPass = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(afterPass.isPlaytestPassed, isTrue);
        expect(afterPass.isCompleted, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Logging a Playtest Issue displays Open [FIX] issue on Brief Card, clears Pass state, and re-passing restores Passed ✓',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final setup = await seedDashWorkbench();
        final provider = setup.provider;
        final feat = setup.feat;
        final cp = setup.cp;
        provider.updateFeatureStates(feat.id, [
          cp.copyWith(
            parameters: {
              ...cp.parameters,
              'godotBuilt': 'true',
              'playtestPassed': 'true',
            },
          ),
        ]);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: provider,
                builder: (_, __) => ReleaseWorkbenchScreen(workbench: provider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Passed ✓'), findsWidgets);

        await tester.runAsync(() async {
          provider.logPlaytestIssueOnCheckpoint(
            featureId: feat.id,
            states: FeatureStateNode.getStatesForDocument(
              provider.documents[feat.id]!,
            ),
            checkpointIndex: 0,
            issueDescription: 'Dash clips into thin wall corner at high speed.',
          );
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });
        await tester.pumpAndSettle();

        final statesAfterLog = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        );
        expect(statesAfterLog.first.isPlaytestPassed, isFalse);
        expect(statesAfterLog.first.checklist.last.text, contains('[FIX]'));
        expect(find.textContaining('OPEN PLAYTEST ISSUES'), findsOneWidget);
        expect(
          find.textContaining('Dash clips into thin wall corner at high speed.'),
          findsWidgets,
        );

        // Re-passing via 1-click CTA restores Passed ✓
        final rePassBtn = find.byKey(ValueKey('playtest_gate_pass_btn_${cp.id}'));
        await tester.ensureVisible(rePassBtn);
        await tester.tap(rePassBtn);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.isPlaytestPassed,
          isTrue,
        );
        expect(find.text('Passed ✓'), findsWidgets);
      },
    );

    testWidgets(
      'Focus Mode OFF stacks multiple checkpoints vertically and Focus Mode ON spotlights one checkpoint',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final setup = await seedDashWorkbench();
        final provider = setup.provider;
        final feat = setup.feat;
        final cp1 = setup.cp;
        final cp2 = FeatureStateNode(
          id: 'cp_dash_v02',
          name: '02 · ALPHA UPGRADE',
          parameters: {'releaseVersion': 'v0.2'},
          checklist: [
            Subtask(
              id: 'st_v02_dash',
              text: 'Add Air Dash Reset',
              codeTargetFile: 'custom_snippet',
              codeLanguage: 'res://scripts/player_dash.gd',
              verification: 'Dashing mid-air resets after landing.',
            ),
          ],
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp1, cp2]);
        provider.toggleFocusMode(); // OFF

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: provider,
                builder: (_, __) => ReleaseWorkbenchScreen(workbench: provider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('checkpoint_single_col_0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('checkpoint_single_col_1')),
          findsOneWidget,
        );

        provider.toggleFocusMode(); // ON
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('checkpoint_single_col_1')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Half-Screen (< 1040px) keeps floating brief header sticky while content scrolls and offers actions in ⋯ menu',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(680, 620);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final setup = await seedDashWorkbench();
        final provider = setup.provider;
        final feat = setup.feat;
        final cp = setup.cp;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: provider,
                builder: (_, __) => ReleaseWorkbenchScreen(workbench: provider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final outlinerTrigger =
            find.byKey(ValueKey('halfscreen_outliner_trigger_${cp.id}'));
        expect(outlinerTrigger, findsOneWidget);
        final initialHeaderDy = tester.getTopLeft(outlinerTrigger).dy;

        // Drag inside the brief workspace pane and verify sticky floating header stays anchored
        final gateCard = find.byKey(ValueKey('playtest_gate_card_${cp.id}'));
        expect(gateCard, findsOneWidget);
        await tester.drag(gateCard, const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(outlinerTrigger).dy,
          closeTo(initialHeaderDy, 1.0),
        );

        // Open Half-Screen ⋯ menu and verify clean Agentic menu actions
        final menuBtn =
            find.byKey(ValueKey('halfscreen_feature_actions_menu_btn_${feat.id}'));
        expect(menuBtn, findsOneWidget);
        await tester.tap(menuBtn);
        await tester.pumpAndSettle();

        expect(find.text('✓ Toggle Feature Passed'), findsOneWidget);
        expect(find.text('✦ Tailor active step'), findsNothing);
        expect(find.text('⇄ Sync code to specs'), findsNothing);
        expect(find.text('⚑ Log Playtest Issue'), findsOneWidget);
        expect(find.text('⚙ Godot Project Contract'), findsNothing);
        expect(find.text('🔌 Connect Godot 4 Plugin'), findsOneWidget);

        await tester.tap(find.text('🔌 Connect Godot 4 Plugin'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('connect_godot_plugin_dialog')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Pass Playtest button & Alt+Enter toggle playtest gate and ignore shortcuts when a TextField is focused',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() async {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final setup = await seedDashWorkbench();
        final provider = setup.provider;
        final feat = setup.feat;
        final cp = setup.cp;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: provider,
                builder: (_, __) => ReleaseWorkbenchScreen(workbench: provider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Toggle playtest passed via header CTA
        final passBtn =
            find.byKey(ValueKey('one_click_complete_next_btn_${cp.id}'));
        expect(passBtn, findsOneWidget);
        await tester.ensureVisible(passBtn);
        await tester.tap(passBtn);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.isPlaytestPassed,
          isTrue,
        );

        // Toggle back off via header CTA
        await tester.tap(passBtn);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.isPlaytestPassed,
          isFalse,
        );

        // 2. Alt+Enter toggles playtest gate ON when no TextField has focus
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.isPlaytestPassed,
          isTrue,
        );

        // 3. While focused in an editable TextField, Alt+Enter must NOT toggle playtest gate
        await tester.tap(find.byKey(const ValueKey('toggle_outliner_search_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('outliner_feature_search_input')));
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.isPlaytestPassed,
          isTrue,
        );
      },
    );

    testWidgets(
      'Outliner Todo filter hides completed features and shows empty-state Reset Filter action',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final setup = await seedDashWorkbench();
        final provider = setup.provider;
        final feat = setup.feat;
        final cp = setup.cp;

        // Mark all steps + playtest gate complete so feat reports 100% DONE
        final doneCp = cp.copyWith(
          checklist: [
            for (final s in cp.checklist) s.copyWith(completed: true),
          ],
          parameters: {
            ...cp.parameters,
            'playtestPassed': 'true',
          },
        );
        FeatureStateNode.saveStatesToDocument(feat, [doneCp]);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: provider,
                builder: (_, __) => ReleaseWorkbenchScreen(workbench: provider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(ValueKey('rail_feat_${feat.id}')), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('toggle_outliner_todo_filter_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(ValueKey('rail_feat_${feat.id}')), findsNothing);
        expect(
          find.byKey(const ValueKey('outliner_empty_filter_state')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('outliner_empty_reset_filter_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('rail_feat_${feat.id}')), findsOneWidget);
      },
    );

    testWidgets(
      'Single-Epic Godot progression (E01 -> E02 -> Complete) & Web Outliner GODOT active badge across 3 visible Epics',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final provider = WorkbenchProvider(enableAutoLoad: false);
        provider.setStage(WorkbenchStage.releaseWorkbench);

        FeatureStateNode makeSimpleCp(String id, String stepId, String text) {
          return FeatureStateNode(
            id: id,
            name: '01 · BUILD',
            trigger: 'Verify $text in Godot scene.',
            parameters: {'releaseVersion': 'v0.1'},
            checklist: [
              Subtask(
                id: stepId,
                text: text,
                codeTargetFile: 'custom_snippet',
                codeLanguage: 'res://scripts/game.gd',
                verification: '$text works.',
              ),
            ],
          );
        }

        final f1 = TierDocument(
          id: 'feat_e1',
          title: 'Player Jump',
          tier: TierType.feature,
          parentId: 'epic_1',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(
          f1,
          [makeSimpleCp('cp_e1', 'st_e1', 'Add Jump Velocity')],
        );
        final f2 = TierDocument(
          id: 'feat_e2',
          title: 'Enemy Patrol',
          tier: TierType.feature,
          parentId: 'epic_2',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(
          f2,
          [makeSimpleCp('cp_e2', 'st_e2', 'Add Patrol Raycast')],
        );
        final f3 = TierDocument(
          id: 'feat_e3',
          title: 'HUD Score',
          tier: TierType.feature,
          parentId: 'epic_3',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(
          f3,
          [makeSimpleCp('cp_e3', 'st_e3', 'Update Score Label')],
        );

        final e1 = TierDocument(
          id: 'epic_1',
          title: 'Core Movement',
          tier: TierType.epic,
          parentId: 'rel_3epics',
          childrenIds: [f1.id],
          sections: {'goal': 'Responsive player feel.'},
        );
        final e2 = TierDocument(
          id: 'epic_2',
          title: 'Enemy Encounter',
          tier: TierType.epic,
          parentId: 'rel_3epics',
          childrenIds: [f2.id],
          sections: {'goal': 'Fair threat pacing.'},
        );
        final e3 = TierDocument(
          id: 'epic_3',
          title: 'HUD Feedback',
          tier: TierType.epic,
          parentId: 'rel_3epics',
          childrenIds: [f3.id],
          sections: {'goal': 'Readable run state.'},
        );
        final rel = TierDocument(
          id: 'rel_3epics',
          title: 'v0.1 Prototype',
          tier: TierType.release,
          parentId: 'proj_3epics',
          childrenIds: [e1.id, e2.id, e3.id],
          sections: {'version': 'v0.1'},
        );
        final proj = TierDocument(
          id: 'proj_3epics',
          title: 'Three Epic Demo',
          tier: TierType.project,
          childrenIds: [rel.id],
          sections: {'engine': 'Godot 4 (GDScript)'},
        );

        for (final d in [proj, rel, e1, e2, e3, f1, f2, f3]) {
          provider.documents[d.id] = d;
        }
        provider.switchProject(proj.id);
        provider.selectFeature(f1.id, triggerAiSynthesis: false);

        expect(provider.computeActiveGodotEpicSnapshot().activeEpicId, e1.id);
        expect(provider.computeActiveGodotEpicSnapshot().epicPosition, 1);
        expect(provider.computeActiveGodotEpicSnapshot().totalEpics, 3);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: provider,
                builder: (_, __) => ReleaseWorkbenchScreen(workbench: provider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // All 3 Epics stay visible in Web Outliner; ONLY E01 carries the GODOT active badge
        expect(find.byKey(ValueKey('rail_beat_${e1.id}')), findsOneWidget);
        expect(find.byKey(ValueKey('rail_beat_${e2.id}')), findsOneWidget);
        expect(find.byKey(ValueKey('rail_beat_${e3.id}')), findsOneWidget);
        expect(
          find.byKey(ValueKey('outliner_godot_active_epic_badge_${e1.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('outliner_godot_active_epic_badge_${e2.id}')),
          findsNothing,
        );

        // Complete E01's feature -> Godot active Epic automatically advances to E02
        final cp1Done = FeatureStateNode.getStatesForDocument(f1).first;
        cp1Done.checklist.first.completed = true;
        cp1Done.isPlaytestPassed = true;
        provider.updateFeatureStates(f1.id, [cp1Done]);
        await tester.pumpAndSettle();

        expect(provider.computeActiveGodotEpicSnapshot().activeEpicId, e2.id);
        expect(provider.computeActiveGodotEpicSnapshot().epicPosition, 2);
        expect(
          find.byKey(ValueKey('outliner_godot_active_epic_badge_${e1.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('outliner_godot_active_epic_badge_${e2.id}')),
          findsOneWidget,
        );

        // Complete E02 + E03 -> allEpicsCompleted = true, active badge clears
        for (final feat in [f2, f3]) {
          final cpDone = FeatureStateNode.getStatesForDocument(feat).first;
          cpDone.checklist.first.completed = true;
          cpDone.isPlaytestPassed = true;
          provider.updateFeatureStates(feat.id, [cpDone]);
        }
        await tester.pumpAndSettle();

        final finalSnap = provider.computeActiveGodotEpicSnapshot();
        expect(finalSnap.allEpicsCompleted, isTrue);
        expect(finalSnap.activeEpicId, isNull);
        expect(
          find.byKey(ValueKey('outliner_godot_active_epic_badge_${e3.id}')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Connect Godot 4 Plugin dialog fetches, caches, copies, and rotates lyr_... Link Token',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;

        final prevBaseUrl = GeminiAgentClient.proxyBaseUrlOverride;
        final prevAuthCheck = GeminiAgentClient.isProxyAuthenticated;
        final prevTokenProvider = GeminiAgentClient.authTokenProvider;
        final prevHttpPost = GeminiAgentClient.testHttpPost;

        String? lastCopied;
        final postedPayloads = <Map<String, dynamic>>[];
        int issueCount = 0;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>?;
            lastCopied = args?['text']?.toString();
          }
          return null;
        });

        GeminiAgentClient.proxyBaseUrlOverride = 'https://proxy.example.test';
        GeminiAgentClient.isProxyAuthenticated = () => true;
        GeminiAgentClient.authTokenProvider = ({bool forceRefresh = false}) async =>
            'firebase_id_tok';
        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
          final decoded = jsonDecode(body.toString()) as Map<String, dynamic>;
          postedPayloads.add(decoded);
          issueCount++;
          final token =
              'lyr_test_token_${issueCount.toString().padLeft(4, '0')}_abcdef123456';
          return http.Response(
            jsonEncode({'ok': true, 'linkToken': token}),
            200,
          );
        };

        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
          GeminiAgentClient.proxyBaseUrlOverride = prevBaseUrl;
          GeminiAgentClient.isProxyAuthenticated = prevAuthCheck;
          GeminiAgentClient.authTokenProvider = prevTokenProvider;
          GeminiAgentClient.testHttpPost = prevHttpPost;
        });

        final setup = await seedDashWorkbench();
        final provider = setup.provider;
        final cp = setup.cp;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ReleaseWorkbenchScreen(workbench: provider),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final chip = find.byKey(ValueKey('connect_godot_plugin_chip_${cp.id}'));
        expect(chip, findsOneWidget);
        await tester.tap(chip);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('connect_godot_plugin_dialog')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('connect_godot_active_epic_preview')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('download_godot_plugin_zip_btn')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('godot_link_token_display')),
          findsOneWidget,
        );
        expect(postedPayloads, hasLength(1));
        expect(postedPayloads.first['rotate'], isFalse);

        // Cache hit on second fetch without rotate
        final cachedRes = await provider.fetchOrCreateGodotLinkToken();
        expect(
          cachedRes.token,
          equals('lyr_test_token_0001_abcdef123456'),
        );
        expect(postedPayloads, hasLength(1));

        // Copy button writes full token to clipboard
        await tester.tap(find.byKey(const ValueKey('copy_godot_link_token_btn')));
        await tester.pumpAndSettle();
        expect(lastCopied, equals('lyr_test_token_0001_abcdef123456'));

        // Rotate button issues new token with rotate: true
        await tester.tap(
          find.byKey(const ValueKey('rotate_godot_link_token_btn')),
        );
        await tester.pumpAndSettle();
        expect(postedPayloads, hasLength(2));
        expect(postedPayloads.last['rotate'], isTrue);
        expect(
          provider.cachedGodotLinkTokenForActiveProject,
          equals('lyr_test_token_0002_abcdef123456'),
        );
      },
    );

    testWidgets(
      'Inline Playtest Bug Drawer supports Shift+Enter newline and plain Enter submit',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final setup = await seedDashWorkbench();
        final provider = setup.provider;
        final feat = setup.feat;
        final cp = setup.cp;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ListenableBuilder(
                listenable: provider,
                builder: (_, __) => ReleaseWorkbenchScreen(workbench: provider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(ValueKey('feature_gate_log_bug_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();

        final bugInputFinder = find.byKey(
          ValueKey('feature_gate_bug_input_${cp.id}'),
        );
        expect(bugInputFinder, findsOneWidget);

        await tester.tap(bugInputFinder);
        await tester.enterText(bugInputFinder, 'First line');
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        final fieldAfterShift = tester.widget<TextField>(bugInputFinder);
        expect(fieldAfterShift.controller?.text, equals('First line\n'));
        expect(bugInputFinder, findsOneWidget);

        await tester.enterText(bugInputFinder, 'First line\nSecond line');
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(bugInputFinder, findsNothing);
        final updatedCp = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(
          updatedCp.checklist.last.text,
          contains('First line\nSecond line'),
        );
      },
    );

    test(
      'Native Godot 4 plugin addon V3.0 files, Cloud Functions /godotLink routes & web/layers_godot_plugin.zip enforce Pure Spec, Playtest & 2-Way Sync Dock without AI builder bloat',
      () {
        final cfg = File('godot_plugin/addons/layers/plugin.cfg');
        final pluginGd = File('godot_plugin/addons/layers/layers_plugin.gd');
        final syncGd = File('godot_plugin/addons/layers/layers_sync_client.gd');
        final executorGd = File('godot_plugin/addons/layers/layers_step_executor.gd');
        final dockGd = File('godot_plugin/addons/layers/layers_dock.gd');
        final functionsJs = File('functions/index.js');
        final zipFile = File('web/layers_godot_plugin.zip');

        expect(cfg.existsSync(), isTrue);
        expect(pluginGd.existsSync(), isTrue);
        expect(syncGd.existsSync(), isTrue);
        expect(executorGd.existsSync(), isTrue);
        expect(dockGd.existsSync(), isTrue);
        expect(functionsJs.existsSync(), isTrue);
        expect(zipFile.existsSync(), isTrue);

        final cfgText = cfg.readAsStringSync();
        final pluginText = pluginGd.readAsStringSync();
        final syncText = syncGd.readAsStringSync();
        final executorText = executorGd.readAsStringSync();
        final dockText = dockGd.readAsStringSync();
        final fnText = functionsJs.readAsStringSync();

        expect(cfgText, contains('version="3.0.0"'));
        expect(cfgText, contains('script="layers_plugin.gd"'));
        final untypedConstArrayPattern = RegExp(r'const\s+\w+\s*:=\s*\[');
        expect(untypedConstArrayPattern.hasMatch(pluginText), isFalse);
        expect(untypedConstArrayPattern.hasMatch(syncText), isFalse);
        expect(untypedConstArrayPattern.hasMatch(executorText), isFalse);
        expect(untypedConstArrayPattern.hasMatch(dockText), isFalse);

        // Plugin entrypoint: clean lifecycle + live CACHE_MODE_REPLACE reload
        expect(pluginText, isNot(contains('get_undo_redo()')));
        expect(pluginText, contains('get_editor_interface()'));
        expect(pluginText, contains('scene_changed'));
        expect(pluginText, contains('on_editor_scene_changed'));
        expect(pluginText, contains('on_editor_scene_saved'));
        expect(pluginText, contains('on_editor_resource_saved'));
        expect(pluginText, contains('ResourceLoader.CACHE_MODE_REPLACE'));
        expect(pluginText, isNot(contains('preload(')));
        expect(executorText, isNot(contains('preload(')));

        // Sync Client: pure 2-way sync actions & OTA self-updater (no AI build/script-sync routes)
        expect(syncText, contains('.gdignore'));
        expect(syncText, contains('.gitignore'));
        expect(syncText, contains('/godotLink/epic'));
        expect(syncText, contains('/godotLink/update'));
        expect(syncText, contains('func save_cached_epic'));
        expect(syncText, contains('func load_cached_epic'));
        expect(syncText, contains('func set_playtest_passed'));
        expect(syncText, contains('func toggle_guard'));
        expect(syncText, contains('func log_playtest_issue'));
        expect(syncText, contains('func resolve_playtest_issue'));
        expect(syncText, contains('"set_playtest"'));
        expect(syncText, contains('"toggle_guard"'));
        expect(syncText, contains('"log_issue"'));
        expect(syncText, contains('"resolve_issue"'));
        expect(syncText, isNot(contains('build_feature')));
        expect(syncText, isNot(contains('direct_agent')));
        expect(syncText, isNot(contains('sync_scripts')));
        expect(syncText, isNot(contains('sync_live_scripts')));
        expect(syncText, isNot(contains('agent_bundle_received')));
        expect(syncText, isNot(contains('set_feature_built')));
        expect(syncText, contains('check_for_plugin_update'));
        expect(syncText, contains('download_and_apply_plugin_update'));
        expect(syncText, contains('layers_step_executor.gd'));
        expect(syncText, contains('ZIPReader'));
        expect(
          syncText,
          contains(
            'raw.githubusercontent.com/HenryCGitHub/LAYERS-Agentic/main/godot_plugin/addons/layers/plugin.cfg',
          ),
        );
        expect(syncText, contains('layers_godot_plugin.zip'));

        // Dock UI: Pure Spec, Playtest Guards, Console Error Capture & Unlockable Playtest Gate
        expect(dockText, contains('get_editor_scale()'));
        expect(dockText, contains('EditorIcons'));
        expect(dockText, contains('EditorFonts'));
        expect(dockText, contains('RichTextLabel.new()'));
        expect(dockText, contains('TextEdit.new()'));
        expect(dockText, contains('MenuButton.new()'));
        expect(dockText, contains('layers_step_executor.gd'));
        expect(dockText, contains('Copy Context'));
        expect(dockText, contains('Reopen Gate'));
        expect(dockText, contains('Playtest Guards (%d/%d)'));
        expect(dockText, contains('Playtest Scene (F6)'));
        expect(dockText, contains('Stop Playtest (F8)'));
        expect(dockText, contains('Playtest Console & Issues'));
        expect(dockText, contains('+ Log Playtest Issue'));
        expect(dockText, contains('Resolve ✓'));
        expect(dockText, contains('Playtest Passed — Next Feature'));
        expect(dockText, contains('_footer_box.visible = not gate_passed'));
        expect(dockText, contains('Open Scene'));
        expect(dockText, contains('Open Scene (%d)'));
        expect(dockText, contains('Open Script'));
        expect(dockText, contains('Open Script (%d)'));
        expect(dockText, contains('_maybe_add_issue_jump_button'));
        expect(dockText, contains('func on_editor_scene_saved'));
        expect(dockText, contains('_format_capped_issue_list'));
        expect(dockText, contains('_maybe_add_open_scene_button'));
        expect(dockText, contains('_maybe_add_open_script_button'));
        expect(dockText, contains('save_all_scenes'));
        expect(dockText, contains('is_playing_scene'));
        expect(dockText, contains('read_editor_and_playtest_errors'));
        expect(dockText, contains('OS.shell_open'));
        expect(dockText, contains('ResourceLoader.CACHE_MODE_REPLACE'));
        expect(dockText, isNot(contains('preload(')));
        expect(
          RegExp(r'add_theme_font_size_override\s*\(\s*"font_size"\s*,\s*\d+').hasMatch(dockText),
          isFalse,
        );
        expect(dockText, contains('Check for Plugin Update'));
        expect(dockText, contains('Update Now'));
        expect(dockText, contains('set_plugin_enabled'));
        expect(dockText, isNot(contains('Build Feature in Godot')));
        expect(dockText, isNot(contains('Apply to Scene & Script')));
        expect(dockText, isNot(contains('Undo Last AI')));
        expect(dockText, isNot(contains('Fix Detected Issues')));
        expect(dockText, isNot(contains('sync_live_scripts')));

        // Read-only inspector & context exporter
        expect(executorText, contains('invalidate_eval_cache'));
        expect(executorText, contains('resolve_feature_paths'));
        expect(executorText, contains('evaluate_feature'));
        expect(executorText, contains('ensure_project_file_logging'));
        expect(executorText, contains('read_recent_godot_log_errors'));
        expect(executorText, contains('read_editor_and_playtest_errors'));
        expect(executorText, contains('extract_issue_jump_targets'));
        expect(executorText, contains('collect_project_scene_paths'));
        expect(executorText, contains('merge_script_buffer_overrides'));
        expect(executorText, contains('read_all_live_project_scripts'));
        expect(executorText, contains('capture_rich_scene_snapshot'));
        expect(executorText, contains('capture_input_map_snapshot'));
        expect(executorText, contains('format_feature_context_markdown'));
        expect(executorText, contains('get_open_scene_roots'));
        expect(executorText, isNot(contains('apply_agent_bundle')));
        expect(executorText, isNot(contains('capture_bundle_snapshot')));
        expect(executorText, isNot(contains('restore_bundle_snapshot')));
        expect(executorText, isNot(contains('verify_built_feature_integrity')));
        expect(executorText, isNot(contains('diagnose_project_combat_and_wiring')));
        expect(executorText, isNot(contains('class _CompileProbeLogger')));
        expect(executorText, isNot(contains('check_gdscript_compiles')));

        // Cloud Functions /godotLink slimmed to pure spec & 2-way playtest/guard/issue sync
        expect(fnText, contains('coveredScope'));
        expect(fnText, contains('edgeCases'));
        expect(fnText, contains('openIssues'));
        expect(fnText, contains('doneWhen'));
        expect(fnText, contains('last_godot_sync_ms'));
        expect(fnText, contains('"set_playtest"'));
        expect(fnText, contains('"toggle_guard"'));
        expect(fnText, contains('"log_issue"'));
        expect(fnText, contains('"resolve_issue"'));
        expect(fnText, contains('signedOffGuards'));
        expect(fnText, isNot(contains('build_feature')));
        expect(fnText, isNot(contains('direct_agent')));
        expect(fnText, isNot(contains('diagnose_fix')));
        expect(fnText, isNot(contains('sync_scripts')));
        expect(fnText, isNot(contains('set_godot_built')));
        expect(fnText, isNot(contains('runGodotAgentWithGemini')));
        expect(fnText, isNot(contains('diagnoseGodotIssueWithGemini')));
        expect(fnText, isNot(contains('handleGodotAgentActionRoute')));
        expect(fnText, isNot(contains('handleSyncLiveScriptsRoute')));
        expect(fnText, isNot(contains('flattenCheckpointSteps')));
        expect(fnText, contains('gemini-4-hydrogen'));
        expect(fnText, contains('gemini-flash-latest'));

        final zipBytes = zipFile.readAsBytesSync();
        expect(zipBytes.length, greaterThan(1000));
        // Valid PK zip magic header ('P', 'K')
        expect(zipBytes[0], equals(0x50));
        expect(zipBytes[1], equals(0x4B));
      },
    );

    test(
      'shouldPreferRemoteDocumentOnSync preserves PROJECT sync timestamps, completed subtasks & playtestPassed progress',
      () {
        final localProj = TierDocument(
          id: 'proj_sync',
          title: 'Synced Project',
          tier: TierType.project,
          childrenIds: ['rel_1'],
        );
        final remoteProj = TierDocument(
          id: 'proj_sync',
          title: 'Synced Project',
          tier: TierType.project,
          sections: {'last_godot_sync_ms': '88888'},
          childrenIds: ['rel_1'],
        );
        expect(
          shouldPreferRemoteDocumentOnSync(localProj, remoteProj),
          isTrue,
        );
        expect(
          shouldPreferRemoteDocumentOnSync(remoteProj, localProj),
          isFalse,
        );

        final localFeat = TierDocument(
          id: 'feat_sync',
          title: 'Claw Strike',
          tier: TierType.feature,
          subtasks: [Subtask(id: 's1', text: 'Build scene', completed: false)],
        );
        final remoteFeatDone = TierDocument(
          id: 'feat_sync',
          title: 'Claw Strike',
          tier: TierType.feature,
          subtasks: [Subtask(id: 's1', text: 'Build scene', completed: true)],
        );
        expect(
          shouldPreferRemoteDocumentOnSync(localFeat, remoteFeatDone),
          isTrue,
        );

        final localPlay = TierDocument(
          id: 'feat_play',
          title: 'Parry',
          tier: TierType.feature,
          sections: {'states': '[{"id":"cp1","parameters":{"playtestPassed":"false"}}]'},
        );
        final remotePlay = TierDocument(
          id: 'feat_play',
          title: 'Parry',
          tier: TierType.feature,
          sections: {'states': '[{"id":"cp1","parameters":{"playtestPassed":"true"}}]'},
        );
        expect(
          shouldPreferRemoteDocumentOnSync(localPlay, remotePlay),
          isTrue,
        );
      },
    );

    test(
      'computeActiveGodotEpicSnapshot completes 0-step playtest-passed features and skips empty intermediate Epics',
      () {
        final provider = WorkbenchProvider(enableAutoLoad: false);
        provider.setStage(WorkbenchStage.releaseWorkbench);

        final proj = TierDocument(
          id: 'proj_zero_step',
          title: 'Zero Step & Empty Epic',
          tier: TierType.project,
          sections: {
            'tech_spec': 'Godot 4 3D',
            'active_release_id': 'rel_zs',
          },
          childrenIds: ['rel_zs'],
        );
        final rel = TierDocument(
          id: 'rel_zs',
          title: 'v0.1 Prototype',
          tier: TierType.release,
          parentId: proj.id,
          childrenIds: ['epic_zs_1', 'epic_zs_2', 'epic_zs_3'],
        );
        final e1 = TierDocument(
          id: 'epic_zs_1',
          title: 'Player Base',
          tier: TierType.epic,
          parentId: rel.id,
          childrenIds: ['feat_zs_1'],
        );
        final e2Empty = TierDocument(
          id: 'epic_zs_2',
          title: 'Pending Synth Epic',
          tier: TierType.epic,
          parentId: rel.id,
          childrenIds: [],
        );
        final e3 = TierDocument(
          id: 'epic_zs_3',
          title: 'Wave Spawner',
          tier: TierType.epic,
          parentId: rel.id,
          childrenIds: ['feat_zs_3'],
        );

        final f1ZeroStep = TierDocument(
          id: 'feat_zs_1',
          title: 'Camera Rig',
          tier: TierType.feature,
          parentId: e1.id,
          phase: 'v0.1',
        );
        final cp1 = FeatureStateNode(
          id: 'cp_zs_1',
          name: '01 · BUILD',
          trigger: 'Verify orbit camera in F6.',
          parameters: {'releaseVersion': 'v0.1'},
          checklist: const [],
        );
        FeatureStateNode.saveStatesToDocument(f1ZeroStep, [cp1]);

        final f3 = TierDocument(
          id: 'feat_zs_3',
          title: 'Spawn Waves',
          tier: TierType.feature,
          parentId: e3.id,
          phase: 'v0.1',
        );
        final cp3 = FeatureStateNode(
          id: 'cp_zs_3',
          name: '01 · BUILD',
          trigger: 'Verify wave spawn.',
          parameters: {'releaseVersion': 'v0.1'},
          checklist: [
            Subtask(id: 'st_zs_3', text: 'Create spawner', verification: 'OK'),
          ],
        );
        FeatureStateNode.saveStatesToDocument(f3, [cp3]);

        for (final d in [proj, rel, e1, e2Empty, e3, f1ZeroStep, f3]) {
          provider.documents[d.id] = d;
        }
        provider.switchProject(proj.id);

        expect(provider.computeActiveGodotEpicSnapshot().activeEpicId, e1.id);

        // Pass playtest on 0-step feature -> skips empty e2Empty -> selects e3!
        cp1.isPlaytestPassed = true;
        provider.updateFeatureStates(f1ZeroStep.id, [cp1]);

        final nextSnap = provider.computeActiveGodotEpicSnapshot();
        expect(nextSnap.activeEpicId, e3.id);
        expect(nextSnap.allEpicsCompleted, isFalse);

        // Complete f3 -> entire release completes cleanly even with empty e2Empty!
        cp3.checklist.first.completed = true;
        cp3.isPlaytestPassed = true;
        provider.updateFeatureStates(f3.id, [cp3]);
        expect(provider.computeActiveGodotEpicSnapshot().allEpicsCompleted, isTrue);
      },
    );

    test(
      'populateDefaultUnifiedSteps avoids bogus InputMap polling on enemies/spawners/UI and picks semantic keys on player features',
      () {
        final enemyNode = FeatureStateNode(
          id: 'cp_enemy',
          name: '01 · BUILD',
          trigger: 'Enemy attacks player and dies cleanly at 0 hp.',
          parameters: {'primarySharedScriptOrScene': 'res://scripts/crab_enemy.gd'},
          coveredScope: ['Enemy pursuit', 'Telegraphed claw strike'],
        );
        TaskHowToBlueprint.populateDefaultUnifiedSteps(
          enemyNode,
          engineHint: 'Godot 4 (3D)',
        );
        final enemyDump = enemyNode.checklist
            .map((s) => '${s.text} ${s.codeSnippet ?? ''} ${s.specNotes ?? ''}')
            .join('\n');
        expect(enemyDump, isNot(contains('_action')));
        expect(enemyDump, isNot(contains('Input.is_action')));
        expect(enemyDump, contains('take_damage'));

        final spawnerNode = FeatureStateNode(
          id: 'cp_spawner',
          name: '01 · BUILD',
          trigger: 'Spawner creates 3 enemy waves in order.',
          parameters: {'primarySharedScriptOrScene': 'res://scripts/three_wave_spawner.gd'},
          coveredScope: ['3-wave spawner'],
        );
        TaskHowToBlueprint.populateDefaultUnifiedSteps(
          spawnerNode,
          engineHint: 'Godot 4 (3D)',
        );
        final spawnerDump = spawnerNode.checklist
            .map((s) => '${s.text} ${s.codeSnippet ?? ''} ${s.specNotes ?? ''}')
            .join('\n');
        expect(spawnerDump, isNot(contains('_action')));
        expect(spawnerDump, isNot(contains('Input.is_action')));
        expect(spawnerDump, contains('Node3D'));

        final uiNode = FeatureStateNode(
          id: 'cp_ui',
          name: '01 · BUILD',
          trigger: 'HUD shows HP and opens Draft screen.',
          parameters: {'primarySharedScriptOrScene': 'res://scripts/hud_overlay.gd'},
          coveredScope: ['HUD health bar', 'Upgrade draft menu'],
        );
        TaskHowToBlueprint.populateDefaultUnifiedSteps(
          uiNode,
          engineHint: 'Godot 4 (3D)',
        );
        final uiDump = uiNode.checklist
            .map((s) => '${s.text} ${s.codeSnippet ?? ''} ${s.specNotes ?? ''}')
            .join('\n');
        expect(uiDump, isNot(contains('_action')));
        expect(uiDump, contains('CanvasLayer'));

        final dashNode = FeatureStateNode(
          id: 'cp_dash',
          name: '01 · BUILD',
          trigger: 'Player dashes with invulnerability.',
          parameters: {'primarySharedScriptOrScene': 'res://scripts/crab_player.gd'},
          coveredScope: ['Player dash & i-frames'],
        );
        TaskHowToBlueprint.populateDefaultUnifiedSteps(
          dashNode,
          engineHint: 'Godot 4 (3D)',
        );
        final dashDump = dashNode.checklist
            .map((s) => '${s.text} ${s.codeSnippet ?? ''} ${s.specNotes ?? ''}')
            .join('\n');
        expect(dashDump, contains('Input Map | dash | Shift'));
        expect(dashDump, contains('Input.is_action_just_pressed("dash")'));
      },
    );
  });

  group('SEA Round 2 · Producer Spec & Pure Playtest Gates', () {
    test(
      'TierDocument.isLegacyIgnoredTier matches CODEFILE variants and importProjectFromJson skips them',
      () {
        expect(TierDocument.isLegacyIgnoredTier({'tier': 'CODEFILE'}), isTrue);
        expect(TierDocument.isLegacyIgnoredTier({'tier': 'code_file'}), isTrue);
        expect(TierDocument.isLegacyIgnoredTier({'tier': 'godot_file'}), isTrue);
        expect(TierDocument.isLegacyIgnoredTier({'tier': 'feature'}), isFalse);

        final provider = WorkbenchProvider(enableAutoLoad: false);
        final legacyBundle = jsonEncode({
          'version': 1,
          'projectId': 'proj_legacy',
          'documents': [
            {
              'id': 'proj_legacy',
              'title': 'Legacy Project',
              'tier': 'PROJECT',
              'childrenIds': ['rel_legacy', 'code_legacy'],
            },
            {
              'id': 'rel_legacy',
              'title': 'v0.1 Prototype',
              'tier': 'RELEASE',
              'parentId': 'proj_legacy',
              'phase': 'v0.1',
              'childrenIds': [],
            },
            {
              'id': 'code_legacy',
              'title': 'player.gd',
              'tier': 'CODEFILE',
              'parentId': 'proj_legacy',
              'phase': 'v0.1',
              'childrenIds': [],
            },
          ],
        });

        final importedProjId = provider.importProjectFromJson(legacyBundle);
        expect(importedProjId, isNotNull);
        expect(provider.savedProjects, hasLength(1));
        expect(provider.documents.values.any((d) => d.title == 'player.gd'), isFalse);
      },
    );

    test(
      'logPlaytestIssueOnCheckpoint synchronously logs [FIX] + [PLAYTEST GUARD] with 0 AI calls and clears playtestPassed',
      () {
        GeminiAgentClient.testMockResponder = (_, __) async {
          throw StateError('AI must not be called when logging a playtest issue');
        };

        final provider = WorkbenchProvider(enableAutoLoad: false);
        final proj = TierDocument(
          id: 'proj_fix',
          title: 'Dash Game',
          tier: TierType.project,
          sections: {'active_release_id': 'rel_fix'},
          childrenIds: ['rel_fix'],
        );
        final rel = TierDocument(
          id: 'rel_fix',
          title: 'Prototype',
          tier: TierType.release,
          parentId: 'proj_fix',
          phase: 'v0.1',
          childrenIds: ['epic_fix'],
        );
        final epic = TierDocument(
          id: 'epic_fix',
          title: 'Core Movement',
          tier: TierType.epic,
          parentId: 'rel_fix',
          phase: 'v0.1',
          childrenIds: ['feat_fix'],
        );
        final cp = FeatureStateNode(
          id: 'cp_fix',
          name: '01 · PROTOTYPE',
          parameters: {'releaseVersion': 'v0.1', 'playtestPassed': 'true'},
          checklist: [Subtask(id: 's1', text: 'Dash moves forward', completed: true)],
          coveredScope: const ['Directional burst'],
          edgeCases: const ['Cancel dash into jump'],
        );
        final feat = TierDocument(
          id: 'feat_fix',
          title: 'Player Dash',
          tier: TierType.feature,
          parentId: 'epic_fix',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp]);

        provider.documents[proj.id] = proj;
        provider.documents[rel.id] = rel;
        provider.documents[epic.id] = epic;
        provider.documents[feat.id] = feat;
        provider.switchProject(proj.id);

        provider.logPlaytestIssueOnCheckpoint(
          featureId: feat.id,
          states: FeatureStateNode.getStatesForDocument(feat),
          checkpointIndex: 0,
          issueDescription: 'Dash clips into corner geometry',
        );

        final updated = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(updated.isPlaytestPassed, isFalse);
        expect(
          updated.checklist.any(
            (s) => !s.completed && s.text == '[FIX] Dash clips into corner geometry',
          ),
          isTrue,
        );
        expect(
          updated.edgeCases,
          contains('[PLAYTEST GUARD] Dash clips into corner geometry'),
        );
      },
    );

    test(
      'buildActiveFeatureCodingAgentPrompt & buildActiveReleaseCodingAgentMarkdown emit clean Producer specs without contract, codeFile, or build queue',
      () {
        final provider = WorkbenchProvider(enableAutoLoad: false);
        final proj = TierDocument(
          id: 'proj_spec',
          title: 'Mech Salvage',
          tier: TierType.project,
          sections: {
            'goal': 'Pilot a salvage mech through flooded ruins and extract cores.',
            'active_release_id': 'rel_spec',
          },
          childrenIds: ['rel_spec'],
        );
        final rel = TierDocument(
          id: 'rel_spec',
          title: 'v0.1 Prototype',
          tier: TierType.release,
          parentId: 'proj_spec',
          phase: 'v0.1',
          childrenIds: ['epic_spec'],
        );
        final epic = TierDocument(
          id: 'epic_spec',
          title: 'Grapple Winch',
          tier: TierType.epic,
          parentId: 'rel_spec',
          phase: 'v0.1',
          childrenIds: ['feat_spec'],
        );
        final cp = FeatureStateNode(
          id: 'cp_spec',
          name: '01 · PROTOTYPE',
          trigger: 'Hook latches onto salvage crate and reels it in.',
          parameters: {'releaseVersion': 'v0.1', 'playtestPassed': 'false'},
          coveredScope: const ['+winch launch', '+crate reel-in'],
          tuningParams: const ['winch_range: 14.0', 'reel_speed: 9.0'],
          edgeCases: const ['Release hook when obstructed', 'No negative slack'],
          checklist: [
            Subtask(id: 'fix_1', text: '[FIX] Rope snaps on underwater crate', completed: false),
          ],
        )..setGuardSignedOff(0, 'Release hook when obstructed', true);

        final feat = TierDocument(
          id: 'feat_spec',
          title: 'Tow Cable',
          tier: TierType.feature,
          parentId: 'epic_spec',
          phase: 'v0.1',
          sections: {
            'scope': 'Goal: Reel heavy salvage crates across arena hazards.',
          },
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp]);

        provider.documents[proj.id] = proj;
        provider.documents[rel.id] = rel;
        provider.documents[epic.id] = epic;
        provider.documents[feat.id] = feat;
        provider.switchProject(proj.id);

        final featurePrompt = provider.buildActiveFeatureCodingAgentPrompt(feat.id);
        expect(featurePrompt, contains('# FEATURE SPECIFICATION — Tow Cable'));
        expect(featurePrompt, contains('Reel heavy salvage crates across arena hazards.'));
        expect(featurePrompt, contains('+winch launch'));
        expect(featurePrompt, contains('winch_range: 14.0'));
        expect(featurePrompt, contains('- [x] `Release hook when obstructed`'));
        expect(featurePrompt, contains('- [ ] `No negative slack`'));
        expect(featurePrompt, contains('[FIX] Rope snaps on underwater crate'));
        expect(featurePrompt, isNot(contains('Godot Dock Build Queue')));
        expect(featurePrompt, isNot(contains('Godot 4 Contract')));

        final releaseMd = provider.buildActiveReleaseCodingAgentMarkdown();
        expect(releaseMd, contains('## 5. Feature Specifications & Playtest Gates'));
        expect(releaseMd, contains('- **Status**: Queued'));
        expect(releaseMd, contains('- **In Scope**:'));
        expect(releaseMd, contains('- **Playtest Guards**:'));
        expect(releaseMd, contains('  - [x] Release hook when obstructed'));
        expect(releaseMd, contains('  - [ ] No negative slack'));
        expect(releaseMd, contains('Open Playtest Issues (`[FIX]`)'));
        expect(releaseMd, isNot(contains('Godot 4 Contract')));
        expect(releaseMd, isNot(contains('TierType.codeFile')));
        expect(releaseMd, isNot(contains('3-Area Engine Implementation Blueprint')));
      },
    );
  });
}
