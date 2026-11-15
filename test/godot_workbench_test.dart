import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/agents/release_planner_agent.dart';
import 'package:layers_agentic/constants/text_style_guide.dart';
import 'package:layers_agentic/constants/tiers.dart';
import 'package:layers_agentic/main.dart';
import 'package:layers_agentic/models/agent_blueprints.dart';
import 'package:layers_agentic/models/feature_state.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/release_workbench_screen.dart';
import 'package:layers_agentic/theme/app_theme.dart';
import 'package:layers_agentic/utils/godot_gdscript_guard.dart';
import 'package:layers_agentic/utils/section_text_utils.dart';

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
                  specNotes: 'Attach DashTimer under CharacterBody2D.',
                ),
                Subtask(
                  id: 's_2',
                  text: 'Bind Dash Input Action',
                  completed: false,
                  codeTargetFile: 'custom_snippet',
                  codeLanguage: 'Project Settings → Input Map',
                  codeSnippet: '| Input Map | dash | Shift |',
                  verification: 'Shift triggers dash action.',
                  specNotes: 'Map Shift to dash in Input Map.',
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
                  specNotes: 'Multiply input direction by dash_speed.',
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
        },
        checklist: const [],
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

        expect(cfgText, contains('version="3.0.7"'));
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
        expect(fnText, contains('parseStructuredScopeFieldsJs'));
        expect(fnText, contains('dedupeScopeBulletsJs'));
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
        cp3.isPlaytestPassed = true;
        provider.updateFeatureStates(f3.id, [cp3]);
        expect(provider.computeActiveGodotEpicSnapshot().allEpicsCompleted, isTrue);
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
        expect(releaseMd, contains('- **Status**: Issues (1)'));
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

  group('SEA Round 3 · Guard-Weighted Progress, Clean Outliner & Producer Shipped Modal', () {
    test('Guard-weighted progress scales up to 50% on signed-off guards and reaches 100% strictly on Pass Playtest', () {
      final provider = WorkbenchProvider();
      final feat = TierDocument(
        id: 'feat_guard_progress',
        title: 'Player Dash',
        tier: TierType.feature,
      );
      provider.documents[feat.id] = feat;

      final cp = FeatureStateNode(
        id: 'cp_dash',
        name: '01 · BUILD',
        edgeCases: const [
          '[STATE GUARD] Block move while dash active',
          '[STATE GUARD] Clamp cooldown >= 0',
        ],
        checklist: const [],
      );
      FeatureStateNode.saveStatesToDocument(feat, [cp]);
      expect(cp.progress, equals(0.0));
      expect(cp.isCompleted, isFalse);
      expect(provider.getDocumentProgress(feat.id), equals(0));

      cp.setGuardSignedOff(0, cp.edgeCases[0], true);
      provider.updateFeatureStates(feat.id, [cp]);
      expect(cp.progress, equals(0.25));
      expect(cp.isCompleted, isFalse);
      expect(provider.getDocumentProgress(feat.id), equals(25));

      cp.setGuardSignedOff(1, cp.edgeCases[1], true);
      provider.updateFeatureStates(feat.id, [cp]);
      expect(cp.progress, equals(0.50));
      expect(cp.isCompleted, isFalse);
      expect(provider.getDocumentProgress(feat.id), equals(50));

      // Open or resolved [FIX] bug stays <= 50% and never auto-completes without Pass Playtest.
      cp.checklist = [
        Subtask(id: 'fix_1', text: '[FIX] Edge jitter on slope', completed: false),
      ];
      provider.updateFeatureStates(feat.id, [cp]);
      expect(cp.openFixCount, equals(1));
      expect(cp.progress, equals(0.50));
      expect(cp.isCompleted, isFalse);

      cp.checklist.first.completed = true;
      provider.updateFeatureStates(feat.id, [cp]);
      expect(cp.openFixCount, equals(0));
      expect(cp.progress, equals(0.50));
      expect(cp.isCompleted, isFalse);
      expect(provider.getDocumentProgress(feat.id), equals(50));

      cp.isPlaytestPassed = true;
      provider.updateFeatureStates(feat.id, [cp]);
      expect(cp.progress, equals(1.0));
      expect(cp.isCompleted, isTrue);
      expect(provider.getDocumentProgress(feat.id), equals(100));
    });

    testWidgets(
      'Outliner omits legacy 0/4 step badges, shows open ⚑ fix counts, and Shipped Summary renders GUARDS CHECKED & GATES PASSED',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final provider = WorkbenchProvider();
        final cp = FeatureStateNode(
          id: 'cp_r3',
          name: '01 · BUILD',
          edgeCases: const [
            'Block move while dash active',
            'Clamp cooldown >= 0',
          ],
          checklist: const [],
        )..setGuardSignedOff(0, 'Block move while dash active', true);

        final feat = TierDocument(
          id: 'feat_r3',
          title: 'Player Dash',
          tier: TierType.feature,
          parentId: 'epic_r3',
          phase: 'v0.1',
          estimatedDuration: '2h',
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp]);

        final epic = TierDocument(
          id: 'epic_r3',
          title: 'Core Movement',
          tier: TierType.epic,
          parentId: 'rel_r3',
          phase: 'v0.1',
          childrenIds: [feat.id],
        );
        final rel = TierDocument(
          id: 'rel_r3',
          title: 'v0.1 Prototype',
          tier: TierType.release,
          parentId: 'proj_r3',
          phase: 'v0.1',
          childrenIds: [epic.id],
          sections: {'version': 'v0.1'},
        );
        final proj = TierDocument(
          id: 'proj_r3',
          title: 'Round 3 Arena',
          tier: TierType.project,
          childrenIds: [rel.id],
          sections: {
            'engine': 'Godot 4 (GDScript)',
            'active_release_id': rel.id,
            'current_stage': WorkbenchStage.releaseWorkbench.name,
          },
        );

        for (final doc in [proj, rel, epic, feat]) {
          provider.documents[doc.id] = doc;
        }
        provider.switchProject(proj.id);
        provider.selectFeature(feat.id, triggerAiSynthesis: false);

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

        expect(find.text('0/4'), findsNothing);
        expect(find.text('0/3'), findsNothing);
        expect(find.byKey(ValueKey('rail_fix_badge_${feat.id}')), findsNothing);
        expect(find.text('DONE'), findsNothing);

        cp.checklist = [
          Subtask(
            id: 'fix_1',
            text: '[FIX] Stamina negative after dash',
            completed: false,
          ),
        ];
        provider.updateFeatureStates(feat.id, [cp]);
        await tester.pumpAndSettle();

        expect(find.byKey(ValueKey('rail_fix_badge_${feat.id}')), findsOneWidget);
        expect(find.text('⚑ 1 fix'), findsOneWidget);

        cp.checklist = [
          ...cp.checklist,
          Subtask(
            id: 'fix_2',
            text: '[FIX] Ghost trail lingers after pause',
            completed: false,
          ),
        ];
        provider.updateFeatureStates(feat.id, [cp]);
        await tester.pumpAndSettle();
        expect(find.text('⚑ 2 fixes'), findsOneWidget);

        cp.isPlaytestPassed = true;
        provider.updateFeatureStates(feat.id, [cp]);
        await tester.pumpAndSettle();

        expect(find.byKey(ValueKey('rail_fix_badge_${feat.id}')), findsNothing);
        expect(find.text('DONE'), findsWidgets);

        final summaryBtn = find.byKey(const ValueKey('release_shipped_summary_btn'));
        expect(summaryBtn, findsOneWidget);
        await tester.tap(summaryBtn);
        await tester.pumpAndSettle();

        expect(find.text('GUARDS CHECKED'), findsOneWidget);
        expect(find.text('GATES PASSED'), findsOneWidget);
        expect(find.text('STEPS COMPLETED'), findsNothing);
      },
    );

    test('SectionTextUtils Producer formatters normalize engine badge, remaining time, guards, goals, and verify checks', () {
      expect(SectionTextUtils.detectEngineLabel('Godot 4 (3D)'), equals('GODOT 4'));
      expect(SectionTextUtils.formatRemainingHoursShort(0), equals('0h'));
      expect(SectionTextUtils.formatRemainingHoursShort(90), equals('1.5h'));
      expect(SectionTextUtils.formatRemainingHoursShort(120), equals('2h'));
      expect(
        SectionTextUtils.formatTelegraphicGuardChip(
          '[STATE GUARD] Prevent the player from dashing off the ledge.',
        ),
        equals('Block player dashing off ledge'),
      );
      expect(
        SectionTextUtils.formatConciseFeatureGoal(
          'Build a playable Dash system that allows the player to burst forward.',
        ),
        equals('Burst forward.'),
      );
      expect(
        SectionTextUtils.formatConciseVerifySentence(
          'Verify that when pressing Shift, the player dashes forward.',
        ),
        equals('Pressing Shift → The player dashes forward.'),
      );
    });

    test(
      'Web Studio stamps updated_at_ms on mutations and shouldPreferRemoteDocumentOnSync respects bidirectional timestamps & signedOffGuards',
      () async {
        final provider = WorkbenchProvider();
        final cp = FeatureStateNode(
          id: 'cp_sync_local',
          name: '01 · PROTOTYPE',
          tuningParams: ['dash_speed: 640.0'],
          edgeCases: ['[STATE GUARD] Lock move while dash_timer active'],
          parameters: {'releaseVersion': 'v0.1'},
        );
        final feat = TierDocument(
          id: 'feat_sync_local',
          title: 'Player Dash',
          tier: TierType.feature,
          parentId: 'epic_sync_local',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp]);
        final epic = TierDocument(
          id: 'epic_sync_local',
          title: 'Movement Core',
          tier: TierType.epic,
          parentId: 'rel_sync_local',
          phase: 'v0.1',
          childrenIds: [feat.id],
        );
        final rel = TierDocument(
          id: 'rel_sync_local',
          title: 'v0.1 Prototype',
          tier: TierType.release,
          parentId: 'proj_sync_local',
          phase: 'v0.1',
          childrenIds: [epic.id],
          sections: {'version': 'v0.1'},
        );
        final proj = TierDocument(
          id: 'proj_sync_local',
          title: 'Dash Arena',
          tier: TierType.project,
          childrenIds: [rel.id],
          sections: {
            'engine': 'Godot 4 (GDScript)',
            'active_release_id': rel.id,
            'current_stage': WorkbenchStage.releaseWorkbench.name,
          },
        );
        for (final doc in [proj, rel, epic, feat]) {
          provider.documents[doc.id] = doc;
        }
        provider.switchProject(proj.id);

        expect(feat.sections.containsKey('updated_at_ms'), isFalse);
        provider.updateFeatureStates(feat.id, [cp]);
        final stampedMs = int.tryParse(feat.sections['updated_at_ms'] ?? '') ?? 0;
        expect(stampedMs, greaterThan(0));

        // 1. Newer Web Studio reopen (`updated_at_ms` > `last_godot_sync_ms`) must win over stale passed Godot doc
        final localReopened = TierDocument(
          id: 'feat_sync',
          title: 'Player Dash',
          tier: TierType.feature,
          sections: {
            'updated_at_ms': '2000',
          },
        );
        FeatureStateNode.saveStatesToDocument(
          localReopened,
          [
            FeatureStateNode(
              id: 'cp_sync',
              name: '01 · PROTOTYPE',
              edgeCases: ['Guard A', 'Guard B'],
              parameters: {'releaseVersion': 'v0.1'},
            ),
          ],
        );

        final remoteOlderPassed = TierDocument(
          id: 'feat_sync',
          title: 'Player Dash',
          tier: TierType.feature,
          sections: {
            'last_godot_sync_ms': '1500',
          },
        );
        FeatureStateNode.saveStatesToDocument(
          remoteOlderPassed,
          [
            FeatureStateNode(
              id: 'cp_sync',
              name: '01 · PROTOTYPE',
              edgeCases: ['Guard A', 'Guard B'],
              parameters: {'releaseVersion': 'v0.1', 'playtestPassed': 'true'},
            ),
          ],
        );
        expect(
          shouldPreferRemoteDocumentOnSync(localReopened, remoteOlderPassed),
          isFalse,
        );

        // 2. Newer Godot sync (`last_godot_sync_ms` > `updated_at_ms`) wins over older Web Studio doc
        final remoteNewer = TierDocument(
          id: 'feat_sync',
          title: 'Player Dash',
          tier: TierType.feature,
          sections: {
            'last_godot_sync_ms': '2500',
          },
        );
        FeatureStateNode.saveStatesToDocument(
          remoteNewer,
          [
            FeatureStateNode(
              id: 'cp_sync',
              name: '01 · PROTOTYPE',
              edgeCases: ['Guard A', 'Guard B'],
              parameters: {'releaseVersion': 'v0.1'},
            ),
          ],
        );
        expect(
          shouldPreferRemoteDocumentOnSync(localReopened, remoteNewer),
          isTrue,
        );

        // 3. Equal-timestamp tie-break prefers higher signedOffGuardsCount
        final localNoGuards = TierDocument(
          id: 'feat_tie',
          title: 'Dash',
          tier: TierType.feature,
          sections: {'updated_at_ms': '3000'},
        );
        FeatureStateNode.saveStatesToDocument(
          localNoGuards,
          [
            FeatureStateNode(
              id: 'cp_tie',
              name: '01',
              edgeCases: ['Guard A', 'Guard B'],
              parameters: {'releaseVersion': 'v0.1'},
            ),
          ],
        );
        final remoteOneGuardCp = FeatureStateNode(
          id: 'cp_tie',
          name: '01',
          edgeCases: ['Guard A', 'Guard B'],
          parameters: {'releaseVersion': 'v0.1'},
        )..setGuardSignedOff(0, 'Guard A', true);
        final remoteOneGuard = TierDocument(
          id: 'feat_tie',
          title: 'Dash',
          tier: TierType.feature,
          sections: {'last_godot_sync_ms': '3000'},
        );
        FeatureStateNode.saveStatesToDocument(
          remoteOneGuard,
          [remoteOneGuardCp],
        );
        expect(
          shouldPreferRemoteDocumentOnSync(localNoGuards, remoteOneGuard),
          isTrue,
        );
      },
    );

    testWidgets(
      '1-Click Pass signs off Guards & resolves open [FIX] issues while Reopen Gate keeps past fixes resolved',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final provider = WorkbenchProvider();
        final cp = FeatureStateNode(
          id: 'cp_reopen_test',
          name: '01 · PROTOTYPE',
          tuningParams: ['dash_speed: 640.0'],
          edgeCases: [
            '[STATE GUARD] Lock move while dash_timer active',
            '[PLAYTEST GUARD] Reset stamina cleanly',
          ],
          parameters: {'releaseVersion': 'v0.1'},
          checklist: [
            Subtask(
              id: 'fix_open',
              text: '[FIX] Stamina negative after dash',
              completed: false,
              codeLanguage: 'fix',
              codeTargetFile: 'playtest_fix',
            ),
          ],
        );
        final feat = TierDocument(
          id: 'feat_reopen_test',
          title: 'Player Dash',
          tier: TierType.feature,
          parentId: 'epic_reopen_test',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp]);
        final epic = TierDocument(
          id: 'epic_reopen_test',
          title: 'Movement Core',
          tier: TierType.epic,
          parentId: 'rel_reopen_test',
          phase: 'v0.1',
          childrenIds: [feat.id],
        );
        final rel = TierDocument(
          id: 'rel_reopen_test',
          title: 'v0.1 Prototype',
          tier: TierType.release,
          parentId: 'proj_reopen_test',
          phase: 'v0.1',
          childrenIds: [epic.id],
          sections: {'version': 'v0.1'},
        );
        final proj = TierDocument(
          id: 'proj_reopen_test',
          title: 'Dash Arena',
          tier: TierType.project,
          childrenIds: [rel.id],
          sections: {
            'engine': 'Godot 4 (GDScript)',
            'active_release_id': rel.id,
            'current_stage': WorkbenchStage.releaseWorkbench.name,
          },
        );
        for (final doc in [proj, rel, epic, feat]) {
          provider.documents[doc.id] = doc;
        }
        provider.switchProject(proj.id);
        provider.selectFeature(feat.id, triggerAiSynthesis: false);

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

        final passBtn =
            find.byKey(ValueKey('one_click_complete_next_btn_${cp.id}'));
        expect(passBtn, findsOneWidget);
        await tester.ensureVisible(passBtn);
        await tester.tap(passBtn);
        await tester.pumpAndSettle();

        var afterPass = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(afterPass.isPlaytestPassed, isTrue);
        expect(afterPass.openFixCount, equals(0));
        expect(afterPass.checklist.first.completed, isTrue);
        expect(afterPass.signedOffGuardsCount, equals(2));
        expect(provider.getDocumentProgress(feat.id), equals(100));

        // Tap Pass button again to Reopen Gate -> past fixes stay resolved & signed-off guards stay intact
        await tester.tap(passBtn);
        await tester.pumpAndSettle();

        final afterReopen = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(afterReopen.isPlaytestPassed, isFalse);
        expect(afterReopen.openFixCount, equals(0));
        expect(afterReopen.checklist.first.completed, isTrue);
        expect(afterReopen.signedOffGuardsCount, equals(2));
        expect(provider.getDocumentProgress(feat.id), equals(50));
      },
    );

    test(
      'applyDeepLinkParams switches active project and selects target feature across releases',
      () {
        final provider = WorkbenchProvider();
        final f1 = TierDocument(
          id: 'feat_dl_1',
          title: 'Main Menu',
          tier: TierType.feature,
          parentId: 'epic_dl_1',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(f1, [
          FeatureStateNode(
            id: 'cp_dl_1',
            name: '01 · PROTOTYPE',
            parameters: {'releaseVersion': 'v0.1'},
          ),
        ]);
        final epic1 = TierDocument(
          id: 'epic_dl_1',
          title: 'Shell',
          tier: TierType.epic,
          parentId: 'rel_dl_1',
          phase: 'v0.1',
          childrenIds: [f1.id],
        );
        final rel1 = TierDocument(
          id: 'rel_dl_1',
          title: 'v0.1',
          tier: TierType.release,
          parentId: 'proj_dl_1',
          phase: 'v0.1',
          childrenIds: [epic1.id],
          sections: {'version': 'v0.1'},
        );
        final proj1 = TierDocument(
          id: 'proj_dl_1',
          title: 'Project One',
          tier: TierType.project,
          childrenIds: [rel1.id],
          sections: {
            'active_release_id': rel1.id,
            'current_stage': WorkbenchStage.releaseWorkbench.name,
          },
        );

        final f2a = TierDocument(
          id: 'feat_dl_2a',
          title: 'Player Move',
          tier: TierType.feature,
          parentId: 'epic_dl_2',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(f2a, [
          FeatureStateNode(
            id: 'cp_dl_2a',
            name: '01 · PROTOTYPE',
            parameters: {'releaseVersion': 'v0.1'},
          ),
        ]);
        final f2b = TierDocument(
          id: 'feat_dl_2b',
          title: 'Wall Jump',
          tier: TierType.feature,
          parentId: 'epic_dl_2',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(f2b, [
          FeatureStateNode(
            id: 'cp_dl_2b',
            name: '01 · PROTOTYPE',
            parameters: {'releaseVersion': 'v0.1'},
          ),
        ]);
        final epic2 = TierDocument(
          id: 'epic_dl_2',
          title: 'Movement',
          tier: TierType.epic,
          parentId: 'rel_dl_2',
          phase: 'v0.1',
          childrenIds: [f2a.id, f2b.id],
        );
        final rel2 = TierDocument(
          id: 'rel_dl_2',
          title: 'v0.1',
          tier: TierType.release,
          parentId: 'proj_dl_2',
          phase: 'v0.1',
          childrenIds: [epic2.id],
          sections: {'version': 'v0.1'},
        );
        final proj2 = TierDocument(
          id: 'proj_dl_2',
          title: 'Project Two',
          tier: TierType.project,
          childrenIds: [rel2.id],
          sections: {
            'active_release_id': rel2.id,
            'current_stage': WorkbenchStage.projectPitch.name,
          },
        );

        for (final doc in [proj1, rel1, epic1, f1, proj2, rel2, epic2, f2a, f2b]) {
          provider.documents[doc.id] = doc;
        }
        provider.switchProject(proj1.id);
        expect(provider.activeProjectId, proj1.id);

        provider.applyDeepLinkParams({'project': proj2.id, 'feature': f2b.id});

        expect(provider.activeProjectId, proj2.id);
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);
        expect(provider.selectedFeatureId, f2b.id);
      },
    );

    testWidgets(
      'Web Studio unifies Queued / In Progress / Issues / Passed badges and surfaces live Godot sync dot + 1-click focus jump',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final provider = WorkbenchProvider();
        final cp1 = FeatureStateNode(
          id: 'cp_sync_badge_1',
          name: '01 · PROTOTYPE',
          edgeCases: [
            '[STATE GUARD] Lock move while dash_timer active',
            '[PLAYTEST GUARD] Reset stamina cleanly',
          ],
          parameters: {'releaseVersion': 'v0.1'},
        );
        final feat1 = TierDocument(
          id: 'feat_sync_badge_1',
          title: 'Player Dash',
          tier: TierType.feature,
          parentId: 'epic_sync_badge',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(feat1, [cp1]);

        final cp2 = FeatureStateNode(
          id: 'cp_sync_badge_2',
          name: '01 · PROTOTYPE',
          edgeCases: ['[STATE GUARD] Respawn cleanly'],
          parameters: {'releaseVersion': 'v0.1'},
        );
        final feat2 = TierDocument(
          id: 'feat_sync_badge_2',
          title: 'Dash Ghost Trail',
          tier: TierType.feature,
          parentId: 'epic_sync_badge',
          phase: 'v0.1',
        );
        FeatureStateNode.saveStatesToDocument(feat2, [cp2]);

        final epic = TierDocument(
          id: 'epic_sync_badge',
          title: 'Movement Core',
          tier: TierType.epic,
          parentId: 'rel_sync_badge',
          phase: 'v0.1',
          childrenIds: [feat1.id, feat2.id],
        );
        final rel = TierDocument(
          id: 'rel_sync_badge',
          title: 'v0.1 Prototype',
          tier: TierType.release,
          parentId: 'proj_sync_badge',
          phase: 'v0.1',
          childrenIds: [epic.id],
          sections: {'version': 'v0.1'},
        );
        final proj = TierDocument(
          id: 'proj_sync_badge',
          title: 'Dash Arena',
          tier: TierType.project,
          childrenIds: [rel.id],
          sections: {
            'engine': 'Godot 4 (GDScript)',
            'active_release_id': rel.id,
            'current_stage': WorkbenchStage.releaseWorkbench.name,
            'last_godot_sync_ms':
                DateTime.now().millisecondsSinceEpoch.toString(),
          },
        );
        for (final doc in [proj, rel, epic, feat1, feat2]) {
          provider.documents[doc.id] = doc;
        }
        provider.switchProject(proj.id);
        provider.selectFeature(feat1.id, triggerAiSynthesis: false);

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

        // 1. Live sync indicator dot on Feature Header Godot chip
        expect(
          find.byKey(ValueKey('godot_chip_live_sync_dot_${cp1.id}')),
          findsOneWidget,
        );

        // 2. Unified status badge progression: Queued -> In Progress · 25% -> Issues (1) -> Passed ✓
        expect(find.text('Queued'), findsOneWidget);

        final guardCheck = find.byKey(ValueKey('playtest_guard_check_${cp1.id}_0'));
        await tester.ensureVisible(guardCheck);
        await tester.tap(guardCheck);
        await tester.pumpAndSettle();
        expect(find.text('In Progress · 25%'), findsWidgets);

        final currentStates = FeatureStateNode.getStatesForDocument(
          provider.documents[feat1.id]!,
        );
        provider.logPlaytestIssueOnCheckpoint(
          featureId: feat1.id,
          states: currentStates,
          checkpointIndex: 0,
          issueDescription: 'Dash stalls on wall corner',
        );
        await tester.pumpAndSettle();
        expect(find.text('Issues (1)'), findsWidgets);

        final passBtn = find.byKey(ValueKey('playtest_gate_pass_btn_${cp1.id}'));
        await tester.ensureVisible(passBtn);
        await tester.tap(passBtn);
        await tester.pumpAndSettle();
        // Passing feat1 auto-advances focus to feat2; switch back to feat1 to inspect Passed ✓ and Jump CTA
        expect(provider.selectedFeatureId, equals(feat2.id));
        provider.selectFeature(feat1.id, triggerAiSynthesis: false);
        await tester.pumpAndSettle();
        expect(find.text('Passed ✓'), findsWidgets);

        // 3. Now Active Godot Feature is feat2 (since feat1 passed); open modal from feat1 & jump straight to feat2
        await tester.tap(
          find.byKey(ValueKey('connect_godot_plugin_chip_${cp1.id}')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('connect_godot_sync_status_badge')),
          findsOneWidget,
        );
        final jumpBtn = find.byKey(
          const ValueKey('jump_to_active_godot_feature_btn'),
        );
        expect(jumpBtn, findsOneWidget);
        await tester.tap(jumpBtn);
        await tester.pumpAndSettle();

        expect(provider.selectedFeatureId, equals(feat2.id));
      },
    );

    testWidgets(
      'Round 20: Stage 2 schemas omit tasks/primarySharedScriptOrScene & needs_ai_enrichment renders editable Feature Card immediately',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. All 6 Stage 2 Gemini tool schemas omit primarySharedScriptOrScene, tasks, and futureTasks
        final stage2Tools = <Map<String, dynamic>>[
          ReleasePlannerAgent.commitReleasePlanTool,
          ReleasePlannerAgent.commitEpicFeaturesTool,
          ReleasePlannerAgent.commitProgressiveEpicChangesTool,
          ReleasePlannerAgent.mutateReleasePlanTool,
          WorkbenchReleaseMixin.commitLiveFeatureEnrichmentTool,
          WorkbenchReleaseMixin.commitInboxFeatureTriageTool,
        ];
        for (final tool in stage2Tools) {
          final encoded = jsonEncode(tool);
          expect(
            encoded.contains('"primarySharedScriptOrScene"'),
            isFalse,
            reason: '${tool['name']} must omit primarySharedScriptOrScene',
          );
          expect(
            encoded.contains('"tasks"'),
            isFalse,
            reason: '${tool['name']} must omit tasks',
          );
          expect(
            encoded.contains('"futureTasks"'),
            isFalse,
            reason: '${tool['name']} must omit futureTasks',
          );
        }

        // 2. Models & compactStyleRules omit primarySharedScriptOrScene and steps[] prompt bloat
        final featBp = ProposedFeatureBlueprint(
          id: 'feat_r20',
          title: 'Player Dash',
          goal: '+burst dash impulse',
          doneWhen: 'Press Shift -> Player dashes forward',
        );
        expect(
          featBp.toJson().containsKey('primarySharedScriptOrScene'),
          isFalse,
        );
        final inboxItem = FeatureInboxItem(
          id: 'inbox_r20',
          rawIdea: 'Add wall jump',
          targetBeatId: 'epic_1',
          targetBeatTitle: 'Movement',
          featureTitle: 'Wall Jump',
          goal: '+wall kick impulse',
          doneWhen: 'Press Jump on wall -> Player kicks upward',
          checkpointTitle: 'Wall Jump Core',
          playtestGate: 'Jump into wall -> kick off cleanly',
        );
        expect(
          inboxItem.toJson().containsKey('primarySharedScriptOrScene'),
          isFalse,
        );
        expect(LayersTextStyleGuide.compactStyleRules.contains('steps[]'), isFalse);

        // 3. Selecting a feature with needs_ai_enrichment renders editable Playtest Gate Card immediately (no Waiting/Building block)
        final provider = WorkbenchProvider();
        final cp = FeatureStateNode(
          id: 'cp_r20_live',
          name: '01 · PROTOTYPE',
          trigger: 'Playtest: Press Shift -> Dash triggers cleanly',
          tuningParams: ['dashSpeed: 720 px/s'],
          edgeCases: ['[STATE GUARD] Ignore dash while cooldown > 0'],
          parameters: {'releaseVersion': 'v0.1'},
        );
        final feat = TierDocument(
          id: 'feat_r20_live',
          title: 'Player Dash',
          tier: TierType.feature,
          parentId: 'epic_r20_live',
          phase: 'v0.1',
          sections: {
            'scope':
                'Goal: +burst dash impulse\n\nIn Scope:\n• Shift burst velocity\n\nDone When: Press Shift -> Dash triggers cleanly',
            'needs_ai_enrichment': 'true',
          },
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp]);
        final epic = TierDocument(
          id: 'epic_r20_live',
          title: 'Movement Core',
          tier: TierType.epic,
          parentId: 'rel_r20_live',
          phase: 'v0.1',
          childrenIds: [feat.id],
        );
        final rel = TierDocument(
          id: 'rel_r20_live',
          title: 'v0.1 Prototype',
          tier: TierType.release,
          parentId: 'proj_r20_live',
          phase: 'v0.1',
          childrenIds: [epic.id],
          sections: {'version': 'v0.1'},
        );
        final proj = TierDocument(
          id: 'proj_r20_live',
          title: 'Dash Arena',
          tier: TierType.project,
          childrenIds: [rel.id],
          sections: {
            'engine': 'Godot 4 (GDScript)',
            'active_release_id': rel.id,
            'current_stage': WorkbenchStage.releaseWorkbench.name,
          },
        );
        for (final doc in [proj, rel, epic, feat]) {
          provider.documents[doc.id] = doc;
        }
        provider.switchProject(proj.id);
        provider.selectFeature(feat.id, triggerAiSynthesis: false);

        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        expect(
          find.byKey(ValueKey('playtest_gate_card_${cp.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('feature_steps_in_progress_${feat.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('rail_queued_badge_${feat.id}')),
          findsNothing,
        );
      },
    );

    test(
      'Cloud Functions parseStructuredScopeFieldsJs extracts 1-line goal, deltas & Done When',
      () {
        final script = r'''
const assert = require("assert");
const { parseStructuredScopeFieldsJs, dedupeScopeBulletsJs, computeActiveEpicPayload } = require("./functions/index.js")._testHelpers;

const rawScope = "Goal: +hitstop freeze frame, +stagger flash material, +wall bounce slam\n\nIn Scope:\n• Staggered vulnerability state\n• +60ms hitstop freeze frame\n• +stagger flash shader\n\nDone When: Land parry or finisher -> enemy flashes white, pauses 60ms";
const parsed = parseStructuredScopeFieldsJs(rawScope);
assert.strictEqual(parsed.goal, "+hitstop freeze frame, +stagger flash material, +wall bounce slam");
assert.deepStrictEqual(parsed.inScope, ["Staggered vulnerability state", "+60ms hitstop freeze frame", "+stagger flash shader"]);
assert.strictEqual(parsed.doneWhen, "Land parry or finisher → enemy flashes white, pauses 60ms");

const deduped = dedupeScopeBulletsJs(["60ms hitstop freeze frame", "+60ms hitstop freeze frame", "• +stagger flash shader"]);
assert.deepStrictEqual(deduped, ["+60ms hitstop freeze frame", "+stagger flash shader"]);

const docsById = new Map([
  ["proj_1", { id: "proj_1", tier: "PROJECT", title: "Shell", childrenIds: ["rel_3"], sections: { active_release_id: "rel_3", design_pillars: "• Every parry feels weighty\n• Read enemy tells cleanly", trade_offs: "• Arcade responsiveness over realism" } }],
  ["rel_3", { id: "rel_3", tier: "RELEASE", parentId: "proj_1", title: "v0.3 Vertical Slice", childrenIds: ["ep_3"], sections: { version: "v0.3" } }],
  ["ep_3", { id: "ep_3", tier: "EPIC", parentId: "rel_3", title: "Claw & Shell Parry", childrenIds: ["f_stagger", "f_dash", "f_wave"] }],
  ["f_stagger", {
    id: "f_stagger",
    tier: "FEATURE",
    parentId: "ep_3",
    title: "Enemy Stagger State",
    sections: {
      scope: rawScope,
      states: JSON.stringify([{
        id: "cp_3",
        trigger: "+hitstop upgrade",
        coveredScope: ["+60ms hitstop freeze frame", "+stagger flash shader"],
        parameters: { releaseVersion: "v0.3", playtestPassed: "false" }
      }])
    }
  }],
  ["f_dash", {
    id: "f_dash",
    tier: "FEATURE",
    parentId: "ep_3",
    title: "Air Dash",
    sections: {
      scope: "Goal: +air dash",
      states: JSON.stringify([{
        id: "cp_dash",
        trigger: "Playtest: Press Shift -> player dashes 6m",
        parameters: { releaseVersion: "v0.3", playtestPassed: "false" }
      }])
    }
  }],
  ["f_wave", {
    id: "f_wave",
    tier: "FEATURE",
    parentId: "ep_3",
    title: "Charge Wave",
    sections: {
      scope: "Goal: +charge wave\n\nIn Scope:\n• Charged crescent slash\n\nDone When: Release charge -> wave fires",
      states: JSON.stringify([{
        id: "cp_wave",
        trigger: "Verify stage deliverables and checklist criteria in game viewport.",
        parameters: { releaseVersion: "v0.3", playtestPassed: "false" }
      }])
    }
  }]
]);
const payload = computeActiveEpicPayload({ docsById, projectId: "proj_1", webStudioUrl: "https://example.com" });
assert.deepStrictEqual(payload.designPillars, ["Every parry feels weighty", "Read enemy tells cleanly"]);
assert.deepStrictEqual(payload.tradeOffs, ["Arcade responsiveness over realism"]);
const feat = payload.activeEpic.features[0];
assert.strictEqual(feat.goal, "+hitstop freeze frame, +stagger flash material, +wall bounce slam");
assert.deepStrictEqual(feat.coveredScope, ["+60ms hitstop freeze frame", "+stagger flash shader"]);
assert.strictEqual(feat.doneWhen, "Land parry or finisher → enemy flashes white, pauses 60ms");
const featDash = payload.activeEpic.features[1];
assert.strictEqual(featDash.goal, "+air dash");
assert.strictEqual(featDash.doneWhen, "Press Shift → player dashes 6m");
const featWave = payload.activeEpic.features[2];
assert.strictEqual(featWave.doneWhen, "Release charge → wave fires");
assert.strictEqual(payload.selectedFeatureId, "f_stagger");
assert.strictEqual(payload.webSelectedFeatureId, "");

docsById.get("proj_1").sections = {
  ...docsById.get("proj_1").sections,
  selected_feature_id: "f_dash",
  selected_feature_ms: "2000",
  last_godot_feature_id: "f_stagger",
  last_godot_feature_ms: "1000",
};
const payloadWebNewer = computeActiveEpicPayload({ docsById, projectId: "proj_1", webStudioUrl: "https://example.com" });
assert.strictEqual(payloadWebNewer.selectedFeatureId, "f_dash");
assert.strictEqual(payloadWebNewer.webSelectedFeatureId, "f_dash");

docsById.get("proj_1").sections = {
  ...docsById.get("proj_1").sections,
  selected_feature_id: "f_dash",
  selected_feature_ms: "2000",
  last_godot_feature_id: "f_wave",
  last_godot_feature_ms: "3000",
};
const payloadGodotNewer = computeActiveEpicPayload({ docsById, projectId: "proj_1", webStudioUrl: "https://example.com" });
assert.strictEqual(payloadGodotNewer.selectedFeatureId, "f_wave");
assert.strictEqual(payloadGodotNewer.webSelectedFeatureId, "f_dash");

const parsedWithOutOfScope = parseStructuredScopeFieldsJs(
  "Goal: Deflect melee strikes\n\nIn Scope:\n• Shield spark VFX\n\nOut of Scope:\n• No co-op revive\n\nDone When: Press Space -> shield sparks"
);
assert.strictEqual(parsedWithOutOfScope.goal, "Deflect melee strikes");
assert.deepStrictEqual(parsedWithOutOfScope.inScope, ["Shield spark VFX"]);
assert.strictEqual(parsedWithOutOfScope.doneWhen, "Press Space → shield sparks");

const parsedWithExclusions = parseStructuredScopeFieldsJs(
  "Goal: Deflect melee strikes\n\nIn Scope:\n• Shield spark VFX\n\nExclusions:\n• No multiplayer netcode\n\nDone When: Press Space -> shield sparks"
);
assert.deepStrictEqual(parsedWithExclusions.inScope, ["Shield spark VFX"]);
assert.strictEqual(parsedWithExclusions.doneWhen, "Press Space → shield sparks");

process.stdout.write("JS_SCOPE_PARSE_OK\n");
''';
        final result = Process.runSync('node', ['-e', script]);
        expect(
          result.exitCode,
          0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}',
        );
        expect(result.stdout.toString(), contains('JS_SCOPE_PARSE_OK'));
      },
    );

    test(
      'buildActiveFeatureCodingAgentPrompt falls back to sections.scope Goal, In Scope & Done When',
      () {
        final provider = WorkbenchProvider(enableAutoLoad: false);
        final cp = FeatureStateNode(
          id: 'cp_prompt_fallback',
          name: '01 · VERTICAL SLICE',
          tuningParams: ['staggerDuration: 1.8 s'],
          edgeCases: ['[STATE GUARD] Ignore attack input while staggered'],
          parameters: {'releaseVersion': 'v0.3'},
        );
        final feat = TierDocument(
          id: 'feat_prompt_fallback',
          title: 'Enemy Stagger State',
          tier: TierType.feature,
          parentId: 'epic_prompt_fallback',
          phase: 'v0.3',
          sections: {
            'scope':
                'Goal: +hitstop freeze frame, +stagger flash material\n\nIn Scope:\n• +60ms hitstop freeze frame\n• +stagger flash shader\n\nDone When: Land parry -> enemy flashes white',
          },
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp]);
        final epic = TierDocument(
          id: 'epic_prompt_fallback',
          title: 'Claw & Shell Parry',
          tier: TierType.epic,
          parentId: 'rel_prompt_fallback',
          phase: 'v0.3',
          childrenIds: [feat.id],
        );
        final rel = TierDocument(
          id: 'rel_prompt_fallback',
          title: 'v0.3 Vertical Slice',
          tier: TierType.release,
          parentId: 'proj_prompt_fallback',
          phase: 'v0.3',
          childrenIds: [epic.id],
          sections: {'version': 'v0.3'},
        );
        final proj = TierDocument(
          id: 'proj_prompt_fallback',
          title: 'Shell Combat',
          tier: TierType.project,
          childrenIds: [rel.id],
          sections: {
            'engine': 'Godot 4 (GDScript)',
            'active_release_id': rel.id,
            'design_pillars': '• Every parry feels weighty',
            'trade_offs': '• Arcade punch over inertia',
          },
        );
        for (final doc in [proj, rel, epic, feat]) {
          provider.documents[doc.id] = doc;
        }
        provider.switchProject(proj.id);

        final prompt = provider.buildActiveFeatureCodingAgentPrompt(feat.id);
        expect(
          prompt,
          contains(
            '- **Goal**: +hitstop freeze frame, +stagger flash material',
          ),
        );
        expect(prompt, contains('- **In Scope**:\n  - +60ms hitstop freeze frame\n  - +stagger flash shader'));
        expect(
          prompt,
          contains(
            '- **Playtest Gate (Done When)**: Land parry → enemy flashes white',
          ),
        );
      },
    );

    testWidgets(
      'Feature Card resolves Done When fallback without placeholder & supports inline Tuning Variables add/edit',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final provider = WorkbenchProvider(enableAutoLoad: false);
        final cp = FeatureStateNode(
          id: 'cp_ui_tuning_1',
          name: '01 · VERTICAL SLICE',
          tuningParams: ['staggerDuration: 1.8 s'],
          edgeCases: ['[STATE GUARD] Ignore attack input while staggered'],
          parameters: {'releaseVersion': 'v0.3'},
        );
        final feat = TierDocument(
          id: 'feat_ui_tuning_1',
          title: 'Enemy Stagger State',
          tier: TierType.feature,
          parentId: 'epic_ui_tuning_1',
          phase: 'v0.3',
          sections: {
            'scope':
                'Goal: +stagger\n\nIn Scope:\n• Hitstop\n\nDone When: Land parry -> enemy flashes white',
            'tuning': '• staggerDuration: 1.8 s',
          },
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp]);
        final epic = TierDocument(
          id: 'epic_ui_tuning_1',
          title: 'Claw & Shell Parry',
          tier: TierType.epic,
          parentId: 'rel_ui_tuning_1',
          phase: 'v0.3',
          childrenIds: [feat.id],
        );
        final rel = TierDocument(
          id: 'rel_ui_tuning_1',
          title: 'v0.3 Vertical Slice',
          tier: TierType.release,
          parentId: 'proj_ui_tuning_1',
          phase: 'v0.3',
          childrenIds: [epic.id],
          sections: {'version': 'v0.3'},
        );
        final proj = TierDocument(
          id: 'proj_ui_tuning_1',
          title: 'Shell Combat',
          tier: TierType.project,
          childrenIds: [rel.id],
          sections: {
            'engine': 'Godot 4 (GDScript)',
            'active_release_id': rel.id,
            'current_stage': WorkbenchStage.releaseWorkbench.name,
          },
        );
        for (final doc in [proj, rel, epic, feat]) {
          provider.documents[doc.id] = doc;
        }
        provider.switchProject(proj.id);
        provider.selectFeature(feat.id, triggerAiSynthesis: false);

        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        expect(find.text('Land parry → enemy flashes white'), findsOneWidget);
        expect(find.textContaining('Verify stage deliverables'), findsNothing);
        expect(find.text('TUNING VARIABLES'), findsOneWidget);
        expect(find.text('staggerDuration: 1.8 s'), findsOneWidget);
        expect(find.text('@EXPORT VARS:'), findsNothing);

        final varFinder = find.byKey(ValueKey('tuning_var_item_${cp.id}_0'));
        await tester.ensureVisible(varFinder);
        await tester.tap(varFinder);
        await tester.pumpAndSettle();

        final editInput = find.byKey(ValueKey('edit_tuning_var_input_${cp.id}_0'));
        await tester.enterText(editInput, 'staggerDuration: 2.2 s');
        await tester.tap(find.byKey(ValueKey('save_tuning_var_btn_${cp.id}_0')));
        await tester.pumpAndSettle();

        expect(
          provider.documents[feat.id]!.sections['tuning'],
          contains('staggerDuration: 2.2 s'),
        );
        expect(find.text('staggerDuration: 2.2 s'), findsOneWidget);

        final addBtn = find.byKey(ValueKey('add_tuning_var_btn_${cp.id}'));
        await tester.ensureVisible(addBtn);
        await tester.tap(addBtn);
        await tester.pumpAndSettle();

        final addInput = find.byKey(ValueKey('add_tuning_var_input_${cp.id}'));
        await tester.enterText(addInput, 'wallSlamDamage: 15.0 hp');
        await tester.tap(find.byKey(ValueKey('confirm_add_tuning_var_btn_${cp.id}')));
        await tester.pumpAndSettle();

        final updatedCp = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(updatedCp.tuningParams, contains('wallSlamDamage: 15.0 hp'));
        expect(find.text('wallSlamDamage: 15.0 hp'), findsOneWidget);
      },
    );

    testWidgets(
      'Feature Card supports 1-click inline editing of Goal, In Scope, Playtest Guards & Done When with guard reset parity',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final provider = WorkbenchProvider(enableAutoLoad: false);
        final cp = FeatureStateNode(
          id: 'cp_spec_edit_1',
          name: '01 · VERTICAL SLICE',
          trigger: 'Playtest: Press F -> parry sparks',
          coveredScope: ['Parry timing window', 'Shield spark VFX'],
          edgeCases: [
            '[STATE GUARD] Ignore block input during stun',
            '[PLAYTEST GUARD] Reset parry cooldown on wave restart',
          ],
          parameters: {'releaseVersion': 'v0.1'},
        );
        final feat = TierDocument(
          id: 'feat_spec_edit_1',
          title: 'Shell Parry',
          tier: TierType.feature,
          parentId: 'epic_spec_edit_1',
          phase: 'v0.1',
          sections: {
            'goal': 'Deflect incoming melee attacks cleanly',
            'in_scope': '• Parry timing window\n• Shield spark VFX',
            'done_when': 'Press F -> parry sparks',
            'scope':
                'Goal: Deflect incoming melee attacks cleanly\n\nIn Scope:\n• Parry timing window\n• Shield spark VFX\n\nOut of Scope:\n• No co-op revive\n\nDone When: Press F -> parry sparks',
            'edge_cases':
                '• [STATE GUARD] Ignore block input during stun\n• [PLAYTEST GUARD] Reset parry cooldown on wave restart',
          },
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp]);
        final epic = TierDocument(
          id: 'epic_spec_edit_1',
          title: 'Claw & Shell Parry',
          tier: TierType.epic,
          parentId: 'rel_spec_edit_1',
          phase: 'v0.1',
          childrenIds: [feat.id],
        );
        final rel = TierDocument(
          id: 'rel_spec_edit_1',
          title: 'v0.1 Prototype',
          tier: TierType.release,
          parentId: 'proj_spec_edit_1',
          phase: 'v0.1',
          childrenIds: [epic.id],
          sections: {'version': 'v0.1'},
        );
        final proj = TierDocument(
          id: 'proj_spec_edit_1',
          title: 'Shell Combat',
          tier: TierType.project,
          childrenIds: [rel.id],
          sections: {
            'engine': 'Godot 4 (GDScript)',
            'active_release_id': rel.id,
            'current_stage': WorkbenchStage.releaseWorkbench.name,
          },
        );
        for (final doc in [proj, rel, epic, feat]) {
          provider.documents[doc.id] = doc;
        }
        provider.switchProject(proj.id);
        provider.selectFeature(feat.id, triggerAiSynthesis: false);

        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        // 1. Inline Edit Goal
        final editGoalBtn = find.byKey(ValueKey('edit_feature_goal_btn_${cp.id}'));
        await tester.ensureVisible(editGoalBtn);
        await tester.tap(editGoalBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ValueKey('edit_feature_goal_input_${cp.id}')),
          'Deflect melee hits and reflect projectiles cleanly',
        );
        await tester.tap(find.byKey(ValueKey('save_feature_goal_btn_${cp.id}')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(ValueKey('task_sheet_feature_goal_${cp.id}')),
          findsOneWidget,
        );
        expect(
          find.text('Deflect melee hits and reflect projectiles cleanly'),
          findsOneWidget,
        );
        final updatedGoalDoc = provider.documents[feat.id]!;
        expect(
          updatedGoalDoc.sections['goal'],
          equals('Deflect melee hits and reflect projectiles cleanly'),
        );
        expect(
          updatedGoalDoc.sections['scope'],
          contains('Goal: Deflect melee hits and reflect projectiles cleanly'),
        );
        expect(
          updatedGoalDoc.sections['scope'],
          contains('Out of Scope:\n• No co-op revive'),
        );
        expect(
          provider.buildActiveFeatureCodingAgentPrompt(updatedGoalDoc.id),
          contains('Deflect melee hits and reflect projectiles cleanly'),
        );

        // 2. Inline Edit Existing In Scope Bullet + Add New Scope Bullet
        final scopeItem0 = find.byKey(ValueKey('in_scope_item_${cp.id}_0'));
        await tester.ensureVisible(scopeItem0);
        await tester.tap(scopeItem0);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ValueKey('edit_in_scope_input_${cp.id}_0')),
          'Tight 180ms parry window',
        );
        await tester.tap(find.byKey(ValueKey('save_in_scope_btn_${cp.id}_0')));
        await tester.pumpAndSettle();

        final addScopeBtn = find.byKey(ValueKey('add_in_scope_btn_${cp.id}'));
        await tester.ensureVisible(addScopeBtn);
        await tester.tap(addScopeBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ValueKey('add_in_scope_input_${cp.id}')),
          'Reflective clang SFX',
        );
        await tester.tap(
          find.byKey(ValueKey('confirm_add_in_scope_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();

        final afterScopeDoc = provider.documents[feat.id]!;
        final afterScopeCp =
            FeatureStateNode.getStatesForDocument(afterScopeDoc).first;
        expect(
          afterScopeCp.coveredScope,
          equals([
            'Tight 180ms parry window',
            'Shield spark VFX',
            'Reflective clang SFX',
          ]),
        );
        expect(
          afterScopeDoc.sections['scope'],
          contains('• Reflective clang SFX'),
        );
        expect(find.text('Tight 180ms parry window'), findsOneWidget);
        expect(find.text('Reflective clang SFX'), findsOneWidget);

        // 3. Check both Playtest Guards, edit Guard 0 (must reset ONLY Guard 0 to unchecked), then Add Guard 2
        final guardCheck0 = find.byKey(ValueKey('playtest_guard_check_${cp.id}_0'));
        await tester.ensureVisible(guardCheck0);
        await tester.tap(guardCheck0);
        await tester.pumpAndSettle();

        final guardCheck1 = find.byKey(ValueKey('playtest_guard_check_${cp.id}_1'));
        await tester.ensureVisible(guardCheck1);
        await tester.tap(guardCheck1);
        await tester.pumpAndSettle();

        var guardStateCp = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(
          guardStateCp.isGuardSignedOff(0, guardStateCp.edgeCases[0]),
          isTrue,
        );
        expect(
          guardStateCp.isGuardSignedOff(1, guardStateCp.edgeCases[1]),
          isTrue,
        );

        final editGuard0Btn =
            find.byKey(ValueKey('edit_playtest_guard_btn_${cp.id}_0'));
        await tester.ensureVisible(editGuard0Btn);
        await tester.tap(editGuard0Btn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ValueKey('edit_playtest_guard_input_${cp.id}_0')),
          'Block parry buffer during hitstun and knockback',
        );
        await tester.tap(
          find.byKey(ValueKey('save_playtest_guard_btn_${cp.id}_0')),
        );
        await tester.pumpAndSettle();

        guardStateCp = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(
          guardStateCp.edgeCases[0],
          equals(
            '[STATE GUARD] Block parry buffer during hitstun and knockback',
          ),
        );
        expect(
          guardStateCp.isGuardSignedOff(0, guardStateCp.edgeCases[0]),
          isFalse,
        );
        expect(
          guardStateCp.isGuardSignedOff(1, guardStateCp.edgeCases[1]),
          isTrue,
        );

        final addGuardBtn = find.byKey(ValueKey('add_playtest_guard_btn_${cp.id}'));
        await tester.ensureVisible(addGuardBtn);
        await tester.tap(addGuardBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ValueKey('add_playtest_guard_input_${cp.id}')),
          'Clear buffered parry on knockdown',
        );
        await tester.tap(
          find.byKey(ValueKey('confirm_add_playtest_guard_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();

        guardStateCp = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(
          guardStateCp.edgeCases,
          contains('[PLAYTEST GUARD] Clear buffered parry on knockdown'),
        );

        // 4. Inline Edit Done When
        final editDoneBtn = find.byKey(ValueKey('edit_done_when_btn_${cp.id}'));
        await tester.ensureVisible(editDoneBtn);
        await tester.tap(editDoneBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ValueKey('edit_done_when_input_${cp.id}')),
          'Tap Q -> parry counter lands',
        );
        await tester.tap(find.byKey(ValueKey('save_done_when_btn_${cp.id}')));
        await tester.pumpAndSettle();

        final finalDoc = provider.documents[feat.id]!;
        final finalCp = FeatureStateNode.getStatesForDocument(finalDoc).first;
        expect(
          finalCp.parameters['playtestGoal'],
          equals('Tap Q → parry counter lands'),
        );
        expect(finalCp.trigger, equals('Playtest: Tap Q → parry counter lands'));
        expect(
          finalDoc.sections['scope'],
          contains('Done When: Tap Q → parry counter lands'),
        );
        expect(find.text('Tap Q → parry counter lands'), findsOneWidget);
      },
    );

    testWidgets(
      'Bidirectional Active Feature Focus Sync tracks last_godot_feature_id, stamps selected_feature_ms, and renders Outliner active Godot Feature dot',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final provider = WorkbenchProvider(enableAutoLoad: false);
        final cpParry = FeatureStateNode(
          id: 'cp_focus_parry',
          name: '01 · PROTOTYPE',
          trigger: 'Playtest: Press F -> parry sparks',
          coveredScope: ['Parry timing window'],
          parameters: {'releaseVersion': 'v0.1'},
        );
        final featParry = TierDocument(
          id: 'feat_parry',
          title: 'Shield Parry',
          tier: TierType.feature,
          parentId: 'beat_e01',
          phase: 'v0.1',
          sections: {'goal': 'Deflect strikes with shield parry'},
        );
        FeatureStateNode.saveStatesToDocument(featParry, [cpParry]);

        final cpDash = FeatureStateNode(
          id: 'cp_focus_dash',
          name: '01 · PROTOTYPE',
          trigger: 'Playtest: Press Shift -> player dashes',
          coveredScope: ['Dash impulse'],
          parameters: {'releaseVersion': 'v0.1'},
        );
        final featDash = TierDocument(
          id: 'feat_dash',
          title: 'Player Dash',
          tier: TierType.feature,
          parentId: 'beat_e01',
          phase: 'v0.1',
          sections: {'goal': 'Burst forward with invulnerability frames'},
        );
        FeatureStateNode.saveStatesToDocument(featDash, [cpDash]);

        final beat = TierDocument(
          id: 'beat_e01',
          title: 'Combat Core',
          tier: TierType.epic,
          parentId: 'rel_v01',
          phase: 'v0.1',
          childrenIds: [featParry.id, featDash.id],
        );
        final rel = TierDocument(
          id: 'rel_v01',
          title: 'v0.1 Prototype',
          tier: TierType.release,
          parentId: 'proj_focus',
          phase: 'v0.1',
          childrenIds: [beat.id],
          sections: {'version': 'v0.1'},
        );
        final proj = TierDocument(
          id: 'proj_focus',
          title: 'Focus Sync Game',
          tier: TierType.project,
          childrenIds: [rel.id],
          sections: {
            'engine': 'Godot 4 (GDScript)',
            'active_release_id': rel.id,
            'current_stage': WorkbenchStage.releaseWorkbench.name,
            'last_godot_feature_id': featDash.id,
            'last_godot_sync_ms':
                DateTime.now().millisecondsSinceEpoch.toString(),
          },
        );
        for (final doc in [proj, rel, beat, featParry, featDash]) {
          provider.documents[doc.id] = doc;
        }
        provider.switchProject(proj.id);
        provider.selectFeature(featParry.id, triggerAiSynthesis: false);

        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        // 1. Snapshot and Outliner dot track last_godot_feature_id (feat_dash)
        expect(
          provider.computeActiveGodotEpicSnapshot().activeFeatureId,
          equals(featDash.id),
        );
        expect(
          find.byKey(
            ValueKey('outliner_godot_active_feature_dot_${featDash.id}'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            ValueKey('outliner_godot_active_feature_dot_${featParry.id}'),
          ),
          findsNothing,
        );

        // 2. Selecting feat_parry locally stamps selected_feature_id & selected_feature_ms
        // while keeping Godot's active feature snapshot on feat_dash until synced
        provider.selectFeature(featParry.id, triggerAiSynthesis: false);
        expect(
          provider.activeProject!.sections['selected_feature_id'],
          equals(featParry.id),
        );
        final selMs = int.tryParse(
          provider.activeProject!.sections['selected_feature_ms'] ?? '',
        );
        expect(selMs, isNotNull);
        expect(selMs!, greaterThan(0));
        expect(
          provider.computeActiveGodotEpicSnapshot().activeFeatureId,
          equals(featDash.id),
        );

        // 3. focusActiveGodotFeature jumps back to feat_dash
        provider.focusActiveGodotFeature();
        expect(provider.selectedFeatureId, equals(featDash.id));

        // 4. Marking feat_dash passed falls back active Godot dot to feat_parry
        final passedDashCp = cpDash.copyWith(
          parameters: {
            ...cpDash.parameters,
            'playtestPassed': 'true',
          },
        );
        provider.updateFeatureStates(featDash.id, [passedDashCp]);
        await tester.pumpAndSettle();

        expect(
          provider.computeActiveGodotEpicSnapshot().activeFeatureId,
          equals(featParry.id),
        );
        expect(
          find.byKey(
            ValueKey('outliner_godot_active_feature_dot_${featParry.id}'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            ValueKey('outliner_godot_active_feature_dot_${featDash.id}'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Feature Card renders Godot-aligned Goal -> In Scope (v0.X) -> Tuning -> Guards -> Issues -> Done When order and 1-click Reopen Gate',
      (WidgetTester tester) async {
        expect(
          SectionTextUtils.dedupeScopeBullets([
            'Staggered vulnerability state',
            '+60ms hitstop freeze frame',
            '+stagger flash shader',
          ]),
          ['+60ms hitstop freeze frame', '+stagger flash shader'],
        );
        expect(
          SectionTextUtils.dedupeScopeBullets([
            'Base Dash',
            '  base dash  ',
            '',
          ]),
          ['Base Dash'],
        );

        tester.view.physicalSize = const Size(1440, 920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final provider = WorkbenchProvider();
        final proj = TierDocument(
          id: 'proj_align_r31',
          title: 'Claw Prototype',
          tier: TierType.project,
          sections: {
            'active_release_id': 'rel_align_r31',
            'current_stage': WorkbenchStage.releaseWorkbench.name,
          },
          childrenIds: ['rel_align_r31'],
        );
        final rel = TierDocument(
          id: 'rel_align_r31',
          title: 'v0.3 Feel Pass',
          tier: TierType.release,
          parentId: proj.id,
          phase: 'v0.3',
          childrenIds: ['epic_align_r31'],
        );
        final epic = TierDocument(
          id: 'epic_align_r31',
          title: 'Claw & Shell Parry',
          tier: TierType.epic,
          parentId: rel.id,
          phase: 'v0.3',
          childrenIds: ['feat_align_r31'],
        );
        final cp = FeatureStateNode(
          id: 'cp_align_r31',
          name: '03 · VERTICAL SLICE',
          trigger: 'Land parry -> enemy flashes white, pauses 60ms',
          coveredScope: [
            'Staggered vulnerability state',
            '+60ms hitstop freeze frame',
            '+stagger flash shader',
          ],
          tuningParams: ['hitstopDuration: 0.06 s'],
          edgeCases: ['[STATE GUARD] Ignore enemy attack input while staggered'],
          parameters: {'releaseVersion': 'v0.3'},
          checklist: [
            Subtask(
              id: 'fix_align_r31',
              text: '[FIX] Flash shader flickers on exit',
              codeLanguage: 'fix',
              codeTargetFile: 'playtest_fix',
            ),
          ],
        );
        final feat = TierDocument(
          id: 'feat_align_r31',
          title: 'Enemy Stagger State',
          tier: TierType.feature,
          parentId: epic.id,
          phase: 'v0.3',
          sections: {
            'goal': '+hitstop freeze frame, +stagger flash material',
            'in_scope':
                '- Staggered vulnerability state\n- +60ms hitstop freeze frame\n- +stagger flash shader',
            'done_when': 'Land parry -> enemy flashes white, pauses 60ms',
          },
        );
        FeatureStateNode.saveStatesToDocument(feat, [cp]);

        provider.documents[proj.id] = proj;
        provider.documents[rel.id] = rel;
        provider.documents[epic.id] = epic;
        provider.documents[feat.id] = feat;
        provider.switchProject(proj.id);
        provider.selectFeature(feat.id, triggerAiSynthesis: false);

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

        // 1. Delta In Scope header + base bullet suppressed when +delta bullets exist
        expect(find.text('IN SCOPE (v0.3)'), findsOneWidget);
        expect(find.textContaining('+60ms hitstop freeze frame'), findsOneWidget);
        expect(find.text('Staggered vulnerability state'), findsNothing);

        // 2. Vertical ordering matches Godot Dock 1:1
        final goalY = tester
            .getTopLeft(find.byKey(ValueKey('task_sheet_feature_goal_${cp.id}')))
            .dy;
        final scopeY = tester
            .getTopLeft(find.byKey(ValueKey('in_scope_header_${cp.id}')))
            .dy;
        final tuningY = tester
            .getTopLeft(find.byKey(ValueKey('tuning_var_item_${cp.id}_0')))
            .dy;
        final guardY = tester
            .getTopLeft(find.byKey(ValueKey('playtest_guard_check_${cp.id}_0')))
            .dy;
        final fixY = tester
            .getTopLeft(find.byKey(ValueKey('open_fix_item_${cp.id}_0')))
            .dy;
        final doneWhenY = tester
            .getTopLeft(find.byKey(ValueKey('done_when_section_${cp.id}')))
            .dy;
        final passBtnY = tester
            .getTopLeft(find.byKey(ValueKey('playtest_gate_pass_btn_${cp.id}')))
            .dy;

        expect(goalY, lessThan(scopeY));
        expect(scopeY, lessThan(tuningY));
        expect(tuningY, lessThan(guardY));
        expect(guardY, lessThan(fixY));
        expect(fixY, lessThan(doneWhenY));
        expect(doneWhenY, lessThan(passBtnY));

        // 3. Sign off guard, Pass Playtest -> disabled ✓ Playtest Passed + 1-click ↺ Reopen Gate
        final guardFinder =
            find.byKey(ValueKey('playtest_guard_check_${cp.id}_0'));
        await tester.ensureVisible(guardFinder);
        await tester.tap(guardFinder);
        await tester.pumpAndSettle();

        final passBtnFinder =
            find.byKey(ValueKey('playtest_gate_pass_btn_${cp.id}'));
        await tester.ensureVisible(passBtnFinder);
        await tester.tap(passBtnFinder);
        await tester.pumpAndSettle();

        final passedBtn = tester.widget<ElevatedButton>(passBtnFinder);
        expect(passedBtn.onPressed, isNull);
        expect(find.text('✓ Playtest Passed'), findsOneWidget);

        final reopenBtnFinder =
            find.byKey(ValueKey('playtest_gate_reopen_btn_${cp.id}'));
        expect(reopenBtnFinder, findsOneWidget);
        expect(find.text('↺ Reopen Gate'), findsOneWidget);

        // 4. Tap 1-click ↺ Reopen Gate -> restores unpassed state while keeping resolved fixes & guard sign-off
        await tester.ensureVisible(reopenBtnFinder);
        await tester.tap(reopenBtnFinder);
        await tester.pumpAndSettle();

        final afterReopen = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(afterReopen.isPlaytestPassed, isFalse);
        expect(afterReopen.openFixCount, equals(0));
        expect(afterReopen.signedOffGuardsCount, equals(1));
        expect(provider.getDocumentProgress(feat.id), equals(50));
      },
    );
  });
}
