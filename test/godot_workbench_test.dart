import 'dart:async';
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
import 'package:layers_agentic/models/godot_project_contract.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/release_workbench_screen.dart';
import 'package:layers_agentic/screens/widgets/godot_inspector_panel.dart';
import 'package:layers_agentic/screens/widgets/godot_workbench_modals.dart';
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

  group('GodotProjectContract', () {
    test('calculates bitmasks, decodes layer numbers, generates INI & merges project.godot', () {
      const contract = GodotProjectContract(
        physicsLayers: {1: 'World', 2: 'Player', 3: 'Enemy', 5: 'Pickup'},
        inputActions: ['move_left', 'jump'],
        autoloads: [
          GodotAutoloadEntry(name: 'Events', resPath: 'res://autoloads/events.gd'),
        ],
        groups: ['player', 'damageable'],
        is3D: false,
      );

      expect(GodotProjectContract.bitmaskForLayerNumbers([1, 3]), 5);
      expect(contract.bitmaskForLayerNames(['player', 'Pickup']), 18); // 2 + 16
      expect(GodotProjectContract.layerNumbersFromBitmask(18), [2, 5]);

      final ini = contract.toProjectGodotIniSnippet();
      expect(ini, contains('[layer_names]'));
      expect(ini, contains('2d_physics/layer_1="World"'));
      expect(ini, contains('Events="*res://autoloads/events.gd"'));
      expect(ini, contains('jump={'));
    });
  });

  group('GodotGdscriptGuard', () {
    test('applies surgical patch hunks while keeping untouched hand-written code intact', () {
      const starter = '''extends CharacterBody2D
# Custom developer comment: keep camera shake helper!

@export var move_speed: float = 280.0

func _custom_camera_shake() -> void:
\tpass

func _physics_process(delta: float) -> void:
\tvar dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
\tvelocity = dir * move_speed
\tmove_and_slide()
''';

      final res = GodotGdscriptGuard.applyPatchHunks(
        existingContent: starter,
        hunks: const [
          GdScriptPatchHunk(
            targetBlock: '@export var move_speed: float = 280.0',
            replaceBlock:
                '@export var move_speed: float = 280.0\n@export var dash_speed: float = 620.0',
          ),
          GdScriptPatchHunk(
            targetBlock: '',
            replaceBlock: 'func _trigger_dash() -> void:\n\tvelocity = velocity.normalized() * dash_speed',
          ),
          GdScriptPatchHunk(
            targetBlock: 'nonexistent_function_that_user_deleted()',
            replaceBlock: 'should_not_overwrite()',
          ),
        ],
      );

      expect(res.appliedCount, 2);
      expect(res.unmatchedHunks.length, 1);
      expect(res.updatedContent, contains('# Custom developer comment: keep camera shake helper!'));
      expect(res.updatedContent, contains('func _custom_camera_shake() -> void:'));
      expect(res.updatedContent, contains('@export var dash_speed: float = 620.0'));
      expect(res.updatedContent, contains('func _trigger_dash() -> void:'));
      expect(res.updatedContent, isNot(contains('should_not_overwrite')));
    });

    test('normalizes Godot 3 idioms, detects dropped methods, updates @export & parses traces', () {
      const legacy = '''extends CharacterBody2D
export var speed: float = 10.0
onready var timer = \$DashTimer

func _ready() -> void:
\ttimer.connect("timeout", self, "_on_timeout")

func _physics_process(delta: float) -> void:
\tyield(get_tree().create_timer(0.2), "timeout")
\tvelocity = move_and_slide(velocity)
''';
      final norm = GodotGdscriptGuard.normalizeGodot4Syntax(legacy);
      expect(norm.code, contains('@export var speed: float = 10.0'));
      expect(norm.code, contains('@onready var timer = \$DashTimer'));
      expect(norm.code, contains('timer.timeout.connect(_on_timeout)'));
      expect(norm.code, contains('await get_tree().create_timer(0.2).timeout'));
      expect(norm.code, contains('move_and_slide()'));
      expect(norm.fixes.length, greaterThanOrEqualTo(4));

      final dropped = GodotGdscriptGuard.detectDroppedSymbols(
        before: 'func _ready():\n\tpass\nfunc _dash():\n\tpass\n',
        after: 'func _ready():\n\tpass\n',
      );
      expect(dropped.single, contains('_dash'));

      final updatedExport = GodotGdscriptGuard.updateExportVarValue(
        '@export var dash_cooldown: float = 0.45 # seconds',
        'dash_cooldown',
        '0.8',
      );
      expect(updatedExport, '@export var dash_cooldown: float = 0.8 # seconds');

      final trace = GodotGdscriptGuard.parseDebuggerTrace(
        'E 0:00:02:0145   res://scripts/player.gd:42 @ _physics_process(): Invalid assignment of property "velocity" on null instance.',
      );
      expect(trace, isNotNull);
      expect(trace!.resPath, 'res://scripts/player.gd');
      expect(trace.lineNumber, 42);
      expect(trace.errorKind, 'Null Instance');
    });
  });

  group('TierType.codeFile lifecycle, Cloud serialization & Targeted MEDIUM Escalation', () {
    test('TierType.codeFile persists, duplicates, exports/imports, deletes & never leaks into Epics/Features', () {
      final provider = WorkbenchProvider();
      final proj = TierDocument(
        id: 'proj_1',
        title: 'Dash Arena',
        tier: TierType.project,
        sections: {
          'tech_spec': 'Godot 4.3 (2D) · GDScript',
          'active_release_id': 'rel_1',
        },
        childrenIds: ['rel_1'],
      );
      final rel = TierDocument(
        id: 'rel_1',
        title: 'Prototype',
        tier: TierType.release,
        parentId: 'proj_1',
        phase: 'v0.1',
        childrenIds: ['epic_1'],
      );
      final epic = TierDocument(
        id: 'epic_1',
        title: 'Player Movement',
        tier: TierType.epic,
        parentId: 'rel_1',
        phase: 'v0.1',
        childrenIds: ['feat_1'],
      );
      final cp = FeatureStateNode(
        id: 'cp_1',
        name: '01 · PROTOTYPE',
        parameters: {'releaseVersion': 'v0.1'},
        tuningParams: ['dash_speed: 600'],
        checklist: [Subtask(id: 't1', text: 'Dash Impulse')],
      );
      final feat = TierDocument(
        id: 'feat_1',
        title: 'Player Dash',
        tier: TierType.feature,
        parentId: 'epic_1',
        phase: 'v0.1',
        sections: {
          'primary_asset': 'res://scenes/player.tscn · res://scripts/player.gd',
        },
      );
      FeatureStateNode.saveStatesToDocument(feat, [cp]);

      provider.documents[proj.id] = proj;
      provider.documents[rel.id] = rel;
      provider.documents[epic.id] = epic;
      provider.documents[feat.id] = feat;
      provider.switchProject(proj.id);

      final vf = provider.upsertGodotVirtualFile(
        resPath: 'res://scripts/player.gd',
        content: 'extends CharacterBody2D\n@export var dash_speed: float = 600.0\n',
        featureIds: ['feat_1'],
      );
      expect(vf, isNotNull);
      expect(provider.documents[vf!.id]?.tier, TierType.codeFile);
      expect(provider.savedProjects.length, 1);
      expect(provider.activeReleaseBeats.map((b) => b.id), ['epic_1']);
      expect(provider.featuresForBeat('epic_1').map((f) => f.id), ['feat_1']);
      expect(provider.activeProjectGodotFiles.length, 1);

      // Update export variable cleanly via syncExportVarToVirtualFile
      final synced = provider.syncExportVarToVirtualFile(
        primaryAssetOrResPath: feat.sections['primary_asset'],
        varName: 'dash_speed',
        formattedValue: '750.0',
        featureId: 'feat_1',
      );
      expect(synced, isTrue);
      expect(
        provider.godotFileForResPath('res://scripts/player.gd')?.content,
        contains('@export var dash_speed: float = 750.0'),
      );

      // Export & import bundle retains cumulative TierType.codeFile documents
      final jsonBundle = provider.exportProjectToJson(proj.id);
      expect(jsonBundle, contains('CODEFILE'));

      // Duplicate project clones TierType.codeFile to new projectId cleanly
      final dupId = provider.duplicateProject(proj.id);
      expect(dupId, isNotNull);
      expect(provider.activeProjectId, dupId);
      expect(
        provider.godotFileForResPath('res://scripts/player.gd')?.content,
        contains('750.0'),
      );
      expect(
        provider.godotFileForResPath('res://scripts/player.gd')?.projectId,
        dupId,
      );

      // Delete original & re-import with collision remaps cleanly
      provider.deleteProject(proj.id);
      expect(provider.documents.containsKey(proj.id), isFalse);
      final importedId = provider.importProjectFromJson(jsonBundle);
      expect(importedId, isNotNull);
      expect(
        provider.godotFileForResPath('res://scripts/player.gd')?.content,
        contains('750.0'),
      );

      // AGENTS.md includes Godot 4 Contract + cumulative files
      final agentsMd = provider.buildActiveReleaseCodingAgentMarkdown();
      expect(agentsMd, contains('## 1B. Godot 4 Contract'));
      expect(agentsMd, contains('res://scripts/player.gd'));
    });

    test('escalates LOW -> MEDIUM on .gd step synthesis and [FIX] debugger triage and applies scriptPatches', () async {
      final capturedThinkingLevels = <String>[];
      final fixCompleter = Completer<void>();

      GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
        final decodedBody = jsonDecode(body as String) as Map<String, dynamic>;
        final genCfg = decodedBody['generationConfig'] as Map<String, dynamic>?;
        final thinkCfg = genCfg?['thinkingConfig'] as Map<String, dynamic>?;
        capturedThinkingLevels.add((thinkCfg?['thinkingLevel'] ?? '').toString());

        final promptText = decodedBody.toString();
        final isFix = promptText.contains('commit_playtest_fix');
        final toolArgs = isFix
            ? {
                'fixTaskTitle': '[FIX] Dash Null Check',
                'playtestGuard': '[PLAYTEST GUARD] Early-return if velocity is zero',
                'scriptPatches': [
                  {
                    'resPath': 'res://scripts/player.gd',
                    'targetBlock': 'func _dash() -> void:\n\tpass',
                    'replaceBlock': 'func _dash() -> void:\n\tif velocity == Vector2.ZERO:\n\t\treturn',
                  }
                ],
                'steps': [
                  {
                    'stepRole': 'script_logic',
                    'title': 'Add Zero Velocity Guard',
                    'stepPath': 'res://scripts/player.gd',
                    'instruction': '- Open `res://scripts/player.gd` → guard zero velocity',
                    'area1Hierarchy': '',
                    'area2Inspector': '',
                    'codeFormula': 'if velocity == Vector2.ZERO:\n\treturn',
                    'verifyResult': 'Press dash idle → no crash',
                  }
                ],
              }
            : {
                'primarySharedScriptOrScene':
                    'res://scenes/player.tscn · res://scripts/player.gd',
                'scriptPatches': [
                  {
                    'resPath': 'res://scripts/player.gd',
                    'targetBlock': '',
                    'replaceBlock':
                        'extends CharacterBody2D\n\nfunc _dash() -> void:\n\tpass',
                  }
                ],
                'tasks': [
                  {
                    'taskIndex': 0,
                    'taskTitle': 'Player Dash Handler',
                    'subSteps': [
                      {
                        'stepRole': 'script_logic',
                        'title': 'Add Dash Stub',
                        'stepPath': 'res://scripts/player.gd',
                        'instruction': '- Add `_dash()` to player.gd',
                        'area1Hierarchy': '',
                        'area2Inspector': '',
                        'codeFormula': 'func _dash() -> void:\n\tpass',
                        'verifyMode': 'editor',
                        'verifyResult': 'Check Script → _dash exists',
                      }
                    ],
                  }
                ],
              };

        final apiResponse = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {
                      'name': isFix
                          ? 'commit_playtest_fix'
                          : 'commit_feature_howto_steps',
                      'args': toolArgs,
                    },
                  }
                ],
              },
            }
          ],
          'usageMetadata': {
            'promptTokenCount': 100,
            'candidatesTokenCount': 50,
            'thoughtsTokenCount': 25,
          },
        };
        if (isFix && !fixCompleter.isCompleted) {
          scheduleMicrotask(() {
            if (!fixCompleter.isCompleted) fixCompleter.complete();
          });
        }
        return http.Response(
          jsonEncode(apiResponse),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      };

      final provider = WorkbenchProvider();
      provider.updateAiConfig(
        apiKey: 'AIzaTestMockKey12345',
        thinkingLevel: 'LOW',
      );
      final proj = TierDocument(
        id: 'proj_esc',
        title: 'Dash Game',
        tier: TierType.project,
        sections: {
          'tech_spec': 'Godot 4.3 (2D)',
          'active_release_id': 'rel_esc',
        },
        childrenIds: ['rel_esc'],
      );
      final rel = TierDocument(
        id: 'rel_esc',
        title: 'Prototype',
        tier: TierType.release,
        parentId: 'proj_esc',
        phase: 'v0.1',
        childrenIds: ['epic_esc'],
      );
      final epic = TierDocument(
        id: 'epic_esc',
        title: 'Core Movement',
        tier: TierType.epic,
        parentId: 'rel_esc',
        phase: 'v0.1',
        childrenIds: ['feat_esc'],
      );
      final states = [
        FeatureStateNode(
          id: 'cp_esc',
          name: '01 · PROTOTYPE',
          parameters: {'releaseVersion': 'v0.1'},
          checklist: [Subtask(id: 't_esc', text: 'Dash Mechanic')],
        ),
      ];
      final feat = TierDocument(
        id: 'feat_esc',
        title: 'Player Dash',
        tier: TierType.feature,
        parentId: 'epic_esc',
        phase: 'v0.1',
      );
      FeatureStateNode.saveStatesToDocument(feat, states);

      provider.documents[proj.id] = proj;
      provider.documents[rel.id] = rel;
      provider.documents[epic.id] = epic;
      provider.documents[feat.id] = feat;
      provider.switchProject(proj.id);

      await provider.synthesizeFeatureHowToStepsWithAi(feat.id, forceRefresh: true);
      expect(capturedThinkingLevels, ['MEDIUM']);
      expect(
        provider.godotFileForResPath('res://scripts/player.gd')?.content,
        contains('func _dash() -> void:'),
      );

      final updatedStates = FeatureStateNode.getStatesForDocument(feat);
      provider.logPlaytestIssueOnCheckpoint(
        featureId: feat.id,
        states: updatedStates,
        checkpointIndex: 0,
        issueDescription: 'res://scripts/player.gd:3 null instance when idle',
      );
      await fixCompleter.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(capturedThinkingLevels, ['MEDIUM', 'MEDIUM']);
      expect(
        provider.godotFileForResPath('res://scripts/player.gd')?.content,
        contains('if velocity == Vector2.ZERO:'),
      );
    });
  });

  group('Widget tests: GodotInspectorPanel inline editing & Modals', () {
    testWidgets('inline-edits scalar, boolean, Vector3 axis, and Contract collision bitmask pills', (tester) async {
      final changes = <(String, String)>[];
      const contract = GodotProjectContract(
        physicsLayers: {1: 'World', 2: 'Player', 3: 'Enemy'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GodotInspectorPanel(
                isDark: true,
                contract: contract,
                onPropertyChanged: (k, v) => changes.add((k, v)),
                tableLines: const [
                  '| Node | Property | Value |',
                  '| --- | --- | --- |',
                  '| DashTimer > Timer | Wait Time | 0.2 |',
                  '| DashTimer > Timer | One Shot | true |',
                  '| Player > Node3D | Position | Vector3(1, 2, 3) |',
                  '| Player > CharacterBody2D | Collision Layer | 2 |',
                ],
              ),
            ),
          ),
        ),
      );

      // Toggle boolean (row 2: One Shot)
      await tester.tap(find.byKey(const ValueKey('inspector_bool_2')));
      await tester.pump();
      expect(changes.last, ('One Shot', 'false'));

      // Toggle Collision Layer bitmask L3 (bit 4) on current mask 2 -> 6 (row 4)
      await tester.tap(find.byKey(const ValueKey('inspector_layer_4_3')));
      await tester.pump();
      expect(changes.last, ('Collision Layer', '6'));

      // Edit scalar Wait Time (row 1)
      await tester.tap(find.byKey(const ValueKey('inspector_scalar_1')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('inspector_scalar_input_1')),
        '0.35',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(changes.last, ('Wait Time', '0.35'));

      // Edit Vector3 X axis (row 3)
      await tester.tap(find.byKey(const ValueKey('inspector_axis_3_X')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('inspector_axis_input_3_X')),
        '4.5',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(changes.last, ('Position', 'Vector3(4.5, 2, 3)'));

      // Scalar focus-blur commit (without pressing Enter)
      await tester.tap(find.byKey(const ValueKey('inspector_scalar_1')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('inspector_scalar_input_1')),
        '0.42',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(changes.last, ('Wait Time', '0.42'));

      // Vector3 axis focus-blur commit (Y axis)
      await tester.tap(find.byKey(const ValueKey('inspector_axis_3_Y')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('inspector_axis_input_3_Y')),
        '7.5',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(changes.last, ('Position', 'Vector3(4.5, 7.5, 3)'));

      // Escape cancels pending Vector3 axis edit without committing
      final countBeforeEsc = changes.length;
      await tester.tap(find.byKey(const ValueKey('inspector_axis_3_Z')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('inspector_axis_input_3_Z')),
        '99',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(changes.length, equals(countBeforeEsc));
    });

    testWidgets('Contract dialog edits and saves Godot 4 Project Contract physics layers', (tester) async {
      final provider = WorkbenchProvider();
      final proj = TierDocument(
        id: 'proj_ui',
        title: 'Modal Game',
        tier: TierType.project,
      );
      provider.documents[proj.id] = proj;
      provider.switchProject(proj.id);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showGodotContractDialog(ctx, provider),
                  child: const Text('Open Project Contract'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Project Contract'));
      await tester.pumpAndSettle();
      expect(find.text('Godot 4 Project Contract'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('contract_layers_input')),
        '1: World, 2: Player, 3: Enemy, 4: Loot',
      );
      await tester.tap(find.byKey(const ValueKey('contract_save_btn')));
      await tester.pumpAndSettle();
      expect(provider.activeGodotContract.physicsLayers[4], 'Loot');
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
      provider.upsertGodotVirtualFile(
        resPath: 'res://scripts/player_dash.gd',
        content:
            'extends CharacterBody2D\n@export var dash_speed: float = 640.0\n',
        featureIds: [feat.id],
      );
      provider.selectFeature(feat.id, triggerAiSynthesis: false);
      return (provider: provider, feat: feat, cp: cp);
    }

    testWidgets(
      'Desktop BUILD QUEUE, manual reorder, + Add Step, clean Property Sheet, starter .tscn & inline Plan B strip',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 920);
        tester.view.devicePixelRatio = 1.0;
        String? lastCopied;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>?;
            lastCopied = args?['text']?.toString();
          }
          return null;
        });
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final setup = await seedDashWorkbench();
        final provider = setup.provider;
        final feat = setup.feat;
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

        // 1. Clean Build Queue Rail & Slim Header (no nested task clutter, no WHAT/EXPORT header junk)
        expect(
          find.byKey(ValueKey('build_queue_rail_${cp.id}')),
          findsOneWidget,
        );
        expect(find.text('BUILD QUEUE'), findsOneWidget);
        expect(find.text('WHAT:'), findsNothing);
        expect(find.textContaining('@EXPORT VARS:'), findsNothing);
        expect(find.text('+ Add Node'), findsNothing);

        // 2. Step 0 (SCENE) shows starter .tscn Copy button and copies valid .tscn scaffold
        final copyTscnBtn = find.byKey(ValueKey('copy_starter_tscn_btn_${cp.id}'));
        expect(copyTscnBtn, findsOneWidget);
        await tester.ensureVisible(copyTscnBtn);
        await tester.tap(copyTscnBtn);
        await tester.pumpAndSettle();
        expect(lastCopied, contains('[gd_scene'));
        expect(lastCopied, contains('DashTimer'));

        // 3. Reorder step 1 down to index 2 and verify manualStepOrder persistence
        final moveDownBtn = find.byKey(ValueKey('build_queue_move_down_${cp.id}_1'));
        expect(moveDownBtn, findsOneWidget);
        await tester.ensureVisible(moveDownBtn);
        await tester.tap(moveDownBtn);
        await tester.pumpAndSettle();

        final afterReorderCp = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(afterReorderCp.parameters['manualStepOrder'], equals('true'));
        expect(afterReorderCp.flatSteps[1].id, equals('st_code'));
        expect(afterReorderCp.flatSteps[2].id, equals('st_insp'));

        TaskHowToBlueprint.clearCache();
        final resolvedAfterReorder = TaskHowToBlueprint.resolveUnifiedSteps(
          checkpointNode: afterReorderCp,
          engineHint: 'Godot 4 (GDScript)',
        );
        expect(resolvedAfterReorder[1].shortTitle, contains('Dash Velocity'));
        expect(resolvedAfterReorder[2].shortTitle, contains('Dash Export'));

        // 4. Select CODE step (now index 1) -> shows code snippet card cleanly without removed inline sync strip
        await tester.tap(find.byKey(ValueKey('build_queue_step_${cp.id}_1')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('inline_code_sync_strip_${cp.id}_1')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('inline_open_code_file_btn_${cp.id}')),
          findsNothing,
        );
        expect(find.textContaining('Implement _trigger_dash()'), findsOneWidget);

        // 5. Select INSP step (now index 2) -> renders clean PROPERTY & LAYER SHEET (no Scene Tree chrome)
        await tester.tap(find.byKey(ValueKey('build_queue_step_${cp.id}_2')));
        await tester.pumpAndSettle();
        expect(find.text('🎛 PROPERTY & LAYER SHEET'), findsOneWidget);
        expect(find.text('+ Add Node'), findsNothing);

        // 6. Inline + Add Step appends 1 flat step
        await tester.tap(find.byKey(ValueKey('build_queue_add_step_btn_${cp.id}')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('add_stage3_task_title_input')),
          'Add Dash Coyote Buffer',
        );
        await tester.tap(find.byKey(const ValueKey('confirm_add_stage3_task_btn')));
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.flatSteps,
          hasLength(5),
        );

        // 7. Pinned F6 Playtest Gate: check [STATE GUARD] sign-off and pass gate
        final gateQueueBtn = find.byKey(ValueKey('build_queue_playtest_gate_${cp.id}'));
        await tester.ensureVisible(gateQueueBtn);
        await tester.tap(gateQueueBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('playtest_gate_card_${cp.id}')),
          findsOneWidget,
        );

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
      },
    );

    testWidgets(
      'Full Web Studio renders rich Epic > Feature detail strip, omits Code File tab, and collapses Split-Screen (<700px) step dropdown',
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
              body: ReleaseWorkbenchScreen(workbench: provider),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Desktop Web Studio shows rich Epic > Feature overview strip and Connect Godot chip, without Code File mode tab
        expect(
          find.byKey(ValueKey('web_epic_feature_detail_strip_${cp.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('connect_godot_plugin_chip_${cp.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('workspace_mode_code_file_btn_${cp.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('code_file_workspace_${cp.id}')),
          findsNothing,
        );

        // 2. Resize to Split-Screen (< 700px) -> collapses queue into 1-line floating bar
        tester.view.physicalSize = const Size(620, 820);
        await tester.pumpAndSettle();

        expect(find.byKey(ValueKey('build_queue_rail_${cp.id}')), findsNothing);
        expect(find.byKey(ValueKey('step_dropdown_${cp.id}')), findsOneWidget);
        final doneBtn = find.byKey(ValueKey('one_click_complete_next_btn_${cp.id}'));
        expect(doneBtn, findsOneWidget);

        await tester.tap(doneBtn);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.flatSteps[0].completed,
          isTrue,
        );
        expect(
          find.byKey(ValueKey('task_sheet_step_row_${cp.id}_1')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Edit Step preserves/edits stepRole & verifyMode, inline +Add Step honors stage chip, direct step delete works, and semantic span colors stay distinct',
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

        // Seed Step 2 instruction with tuning var (dash_speed), guard rule/token, and asset path.
        final initStates = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        );
        initStates.first.checklist[2].specNotes =
            TaskHowToBlueprint.encodeThreeAreaNotes(
          instruction:
              'Apply dash_speed while Lock move while dash_timer active in res://scripts/player_dash.gd.',
          verifyMode: 'playtest',
          stepRole: 'script_logic',
        );
        FeatureStateNode.saveStatesToDocument(
          provider.documents[feat.id]!,
          initStates,
        );
        TaskHowToBlueprint.clearCache();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ReleaseWorkbenchScreen(workbench: provider),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Check semantic span colors on Step 2 DO instruction (Violet tune, Amber guard, Cyan asset)
        await tester.tap(find.byKey(ValueKey('build_queue_step_${cp.id}_2')));
        await tester.pumpAndSettle();
        final richTextFinder = find.descendant(
          of: find.byKey(ValueKey('step_do_instruction_${cp.id}_2')),
          matching: find.byType(RichText),
        );
        expect(richTextFinder, findsWidgets);
        final spanColors = <String, Color?>{};
        void collectColors(InlineSpan span) {
          if (span is TextSpan) {
            final t = span.text ?? '';
            if (t.isNotEmpty && span.style?.color != null) {
              spanColors[t] = span.style!.color;
            }
            for (final c in span.children ?? const <InlineSpan>[]) {
              collectColors(c);
            }
          }
        }

        for (final rt in tester.widgetList<RichText>(richTextFinder)) {
          collectColors(rt.text);
        }
        final tuneColor = spanColors.entries
            .where((e) => e.key.contains('dash_speed'))
            .map((e) => e.value)
            .firstOrNull;
        final guardColor = spanColors.entries
            .where((e) => e.key.contains('dash_timer'))
            .map((e) => e.value)
            .firstOrNull;
        final assetColor = spanColors.entries
            .where((e) => e.key.contains('player_dash.gd'))
            .map((e) => e.value)
            .firstOrNull;
        expect(tuneColor, equals(AppTheme.accentPurpleFor(true)));
        expect(guardColor, equals(AppTheme.accentAmberFor(true)));
        expect(assetColor, equals(AppTheme.accentCyanFor(true)));

        // 2. Edit Step 2 via modal: switch role to inspector_setup + verify mode toggle -> persisted
        await tester.tap(find.byKey(ValueKey('edit_howto_substep_${cp.id}_2')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('edit_substep_role_inspector_setup')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('edit_substep_verify_mode_toggle')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Step'));
        await tester.pumpAndSettle();

        final afterEditCp = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        final decodedEdit = TaskHowToBlueprint.decodeThreeAreaNotes(
          afterEditCp.checklist[2].specNotes,
        );
        expect(decodedEdit.stepRole, equals('inspector_setup'));
        expect(decodedEdit.verifyMode, equals('playtest'));

        // 3. Inline + Add Step with explicit WIRE stage chip
        await tester.tap(
          find.byKey(ValueKey('build_queue_add_step_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('add_step_stage_wire')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('add_stage3_task_title_input')),
          'Connect Dash Audio Signal',
        );
        await tester.tap(
          find.byKey(const ValueKey('confirm_add_stage3_task_btn')),
        );
        await tester.pumpAndSettle();

        final afterAddCp = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(afterAddCp.flatSteps, hasLength(5));
        final addedDecoded = TaskHowToBlueprint.decodeThreeAreaNotes(
          afterAddCp.flatSteps.last.specNotes,
        );
        expect(addedDecoded.stepRole, equals('wire_and_verify'));

        // 4. Direct step delete button in BUILD QUEUE
        await tester.tap(
          find.byKey(ValueKey('build_queue_delete_step_${cp.id}_4')),
        );
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.flatSteps,
          hasLength(4),
        );
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
      'Half-Screen (< 1040px) keeps floating step header sticky while content scrolls and offers desktop actions in ⋯ menu',
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

        final stepDropdown = find.byKey(ValueKey('step_dropdown_${cp.id}'));
        expect(stepDropdown, findsOneWidget);
        final initialHeaderDy = tester.getTopLeft(stepDropdown).dy;

        // Drag inside the step workspace pane and verify sticky floating header stays anchored
        final area = find.byKey(ValueKey('initial_setup_area_${cp.id}'));
        expect(area, findsOneWidget);
        await tester.drag(area, const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(stepDropdown).dy,
          closeTo(initialHeaderDy, 1.0),
        );

        // Open Half-Screen ⋯ menu and verify desktop Row 2 action parity + modal trigger
        final menuBtn =
            find.byKey(ValueKey('halfscreen_feature_actions_menu_btn_${feat.id}'));
        expect(menuBtn, findsOneWidget);
        await tester.tap(menuBtn);
        await tester.pumpAndSettle();

        expect(find.text('✦ Tailor active step'), findsOneWidget);
        expect(find.text('⇄ Sync code to specs'), findsNothing);
        expect(find.text('⚑ Log playtest issue'), findsOneWidget);
        expect(find.text('📦 Godot files & sync'), findsNothing);
        expect(find.text('⚙ Project contract'), findsOneWidget);

        await tester.tap(find.text('⚙ Project contract'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
      },
    );

    testWidgets(
      'Step check footer toggles active step and Alt keyboard shortcuts navigate/toggle when no TextField is focused',
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

        // 1. Toggle step 0 directly via footer Verify Check button
        final checkBtn0 =
            find.byKey(ValueKey('step_check_toggle_btn_${cp.id}_0'));
        expect(checkBtn0, findsOneWidget);
        await tester.ensureVisible(checkBtn0);
        await tester.tap(checkBtn0);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.flatSteps[0].completed,
          isTrue,
        );

        // Uncheck step 0 via button so Alt+Enter behavior can be tested cleanly from step 0 -> step 1
        await tester.tap(find.byKey(ValueKey('build_queue_step_${cp.id}_0')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(checkBtn0);
        await tester.tap(checkBtn0);
        await tester.pumpAndSettle();

        // 2. Alt+ArrowDown advances to step 1; Alt+Enter marks active step done
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();

        expect(
          find.byKey(ValueKey('step_check_toggle_btn_${cp.id}_1')),
          findsOneWidget,
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          FeatureStateNode.getStatesForDocument(
            provider.documents[feat.id]!,
          ).first.flatSteps[1].completed,
          isTrue,
        );

        // 3. While focused in an editable TextField, Alt+ArrowDown must NOT fire workbench shortcut
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.tap(find.byKey(const ValueKey('toggle_outliner_search_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('outliner_feature_search_input')));
        await tester.pumpAndSettle();

        final activeBefore =
            find.byKey(ValueKey('step_check_toggle_btn_${cp.id}_2'));
        expect(activeBefore, findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        expect(activeBefore, findsOneWidget);
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

    test(
      'Native Godot 4 plugin addon V2.1 files, Cloud Functions diagnose_fix & web/layers_godot_plugin.zip enforce single-step dock with live checks & undoable actions',
      () {
        final cfg = File('godot_plugin/addons/layers/plugin.cfg');
        final pluginGd = File('godot_plugin/addons/layers/layers_plugin.gd');
        final syncGd = File('godot_plugin/addons/layers/layers_sync_client.gd');
        final dockGd = File('godot_plugin/addons/layers/layers_dock.gd');
        final functionsJs = File('functions/index.js');
        final zipFile = File('web/layers_godot_plugin.zip');

        expect(cfg.existsSync(), isTrue);
        expect(pluginGd.existsSync(), isTrue);
        expect(syncGd.existsSync(), isTrue);
        expect(dockGd.existsSync(), isTrue);
        expect(functionsJs.existsSync(), isTrue);
        expect(zipFile.existsSync(), isTrue);

        final cfgText = cfg.readAsStringSync();
        final pluginText = pluginGd.readAsStringSync();
        final syncText = syncGd.readAsStringSync();
        final dockText = dockGd.readAsStringSync();
        final fnText = functionsJs.readAsStringSync();

        expect(cfgText, contains('script="layers_plugin.gd"'));
        expect(pluginText, contains('get_undo_redo()'));
        expect(pluginText, contains('get_editor_interface()'));

        expect(syncText, contains('.gdignore'));
        expect(syncText, contains('.gitignore'));
        expect(syncText, contains('/godotLink/epic'));
        expect(syncText, contains('/godotLink/update'));
        expect(syncText, contains('"diagnose_fix"'));

        expect(dockText, contains('get_edited_scene_root()'));
        expect(dockText, contains('inspect_object'));
        expect(dockText, contains('play_current_scene()'));
        expect(dockText, contains('undo_redo'));
        expect(dockText, contains('Broken? Ask Agent to Fix'));
        expect(dockText, contains('OS.shell_open'));

        expect(fnText, contains('decodeThreeAreaNotesJs'));
        expect(fnText, contains('"diagnose_fix"'));
        expect(fnText, contains('gemini-4-hydrogen'));
        expect(fnText, contains('gemini-flash-latest'));

        // TaskHowToBlueprint cleanly strips V2.1 [[DIAGNOSIS]] & [[SCRIPT_PATCH]] markers
        const rawNotesWithPatch =
            'Apply respawn guard cleanly.\n[[AREA2]]\nOceanZone.respawn_marker: Marker3D\n[[VERIFY_MODE]]\nplaytest\n[[STEP_ROLE]]\nfix\n[[DIAGNOSIS]]\n_on_body_entered only calls pass.\n[[SCRIPT_PATCH]]\n{"resPath":"res://scripts/boundary_guard.gd"}';
        final decoded = TaskHowToBlueprint.decodeThreeAreaNotes(
          rawNotesWithPatch,
        );
        expect(decoded.cleanInstruction, equals('Apply respawn guard cleanly.'));
        expect(
          decoded.area2Inspector,
          equals('OceanZone.respawn_marker: Marker3D'),
        );
        expect(decoded.verifyMode, equals('playtest'));
        expect(decoded.stepRole, equals('fix'));

        final zipBytes = zipFile.readAsBytesSync();
        expect(zipBytes.length, greaterThan(1000));
        // Valid PK zip magic header ('P', 'K')
        expect(zipBytes[0], equals(0x50));
        expect(zipBytes[1], equals(0x4B));
      },
    );
  });
}
