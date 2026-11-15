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
import 'package:layers_agentic/models/godot_virtual_file.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/release_workbench_screen.dart';
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

  group('Feature-First Progress & Contract Modals', () {
    test('FeatureStateNode & getDocumentProgress treat Built-in-Godot as <100% until Playtest Passed (even with 0 steps)', () {
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
      expect(unbuiltCp.isBuiltInGodot, isFalse);
      expect(unbuiltCp.progress, equals(0.0));
      expect(unbuiltCp.isCompleted, isFalse);

      final builtCp = unbuiltCp.copyWith(
        parameters: {'godotBuilt': 'true', 'playtestPassed': 'false'},
      );
      expect(builtCp.isBuiltInGodot, isTrue);
      expect(builtCp.progress, greaterThan(0.0));
      expect(builtCp.progress, lessThan(1.0));
      expect(builtCp.isCompleted, isFalse);
      FeatureStateNode.saveStatesToDocument(feat, [builtCp]);
      expect(
        provider.getDocumentProgress(feat.id),
        allOf(greaterThan(0), lessThan(100)),
      );

      final passedCp = builtCp.copyWith(
        parameters: {'godotBuilt': 'true', 'playtestPassed': 'true'},
      );
      expect(passedCp.isPlaytestPassed, isTrue);
      expect(passedCp.progress, equals(1.0));
      expect(passedCp.isCompleted, isTrue);
      FeatureStateNode.saveStatesToDocument(feat, [passedCp]);
      expect(provider.getDocumentProgress(feat.id), equals(100));
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
      'Full Web Studio renders Connect Godot Dock chip, Built-in-Godot status badge, and Half-Screen 1-click Pass CTA',
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
          cp.copyWith(parameters: {...cp.parameters, 'godotBuilt': 'true'}),
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

        // 1. Desktop Web Studio shows Connect Godot chip, Built in Godot status, and omits Code File tab
        expect(
          find.byKey(ValueKey('connect_godot_plugin_chip_${cp.id}')),
          findsOneWidget,
        );
        expect(find.text('Built in Godot'), findsOneWidget);
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
        expect(find.text('⚙ Godot Project Contract'), findsOneWidget);

        await tester.tap(find.text('⚙ Godot Project Contract'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
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
      'Native Godot 4 plugin addon V2.6 files, Cloud Functions direct_agent/build_feature/sync_scripts & web/layers_godot_plugin.zip enforce native EditorTheme GUI, Feature-First workflow, export tuners, input auto-discovery, eval caching & 2-way sync',
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

        expect(cfgText, contains('version="2.7.4"'));
        expect(cfgText, contains('script="layers_plugin.gd"'));
        final untypedConstArrayPattern = RegExp(r'const\s+\w+\s*:=\s*\[');
        expect(untypedConstArrayPattern.hasMatch(pluginText), isFalse);
        expect(untypedConstArrayPattern.hasMatch(syncText), isFalse);
        expect(untypedConstArrayPattern.hasMatch(executorText), isFalse);
        expect(untypedConstArrayPattern.hasMatch(dockText), isFalse);
        expect(pluginText, contains('get_undo_redo()'));
        expect(pluginText, contains('get_editor_interface()'));
        expect(pluginText, contains('scene_changed'));
        expect(pluginText, contains('on_editor_resource_saved'));
        expect(pluginText, contains('ResourceLoader.CACHE_MODE_REPLACE'));
        expect(pluginText, isNot(contains('preload(')));
        expect(executorText, isNot(contains('preload(')));

        expect(syncText, contains('.gdignore'));
        expect(syncText, contains('.gitignore'));
        expect(syncText, contains('/godotLink/epic'));
        expect(syncText, contains('/godotLink/update'));
        expect(syncText, isNot(contains('func toggle_step')));
        expect(syncText, isNot(contains('func diagnose_fix')));
        expect(syncText, isNot(contains('func is_agent_busy')));
        expect(syncText, isNot(contains('func complete_feature_steps')));
        expect(syncText, contains('_normalize_code_files_dict'));
        expect(syncText, contains('"sync_scripts"'));
        expect(syncText, contains('sync_live_scripts'));
        expect(syncText, contains('scripts_synced'));
        expect(syncText, contains('build_feature'));
        expect(syncText, contains('direct_agent'));
        expect(syncText, contains('inputMapSnapshot'));
        expect(syncText, contains('projectDiagnostics'));
        expect(syncText, contains('agent_bundle_received'));
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

        expect(dockText, contains('get_edited_scene_root()'));
        expect(dockText, contains('get_editor_scale()'));
        expect(dockText, contains('EditorIcons'));
        expect(dockText, contains('EditorFonts'));
        expect(dockText, contains('RichTextLabel.new()'));
        expect(dockText, contains('TextEdit.new()'));
        expect(dockText, isNot(contains('Tree.new()')));
        expect(dockText, isNot(contains('CodeEdit.new()')));
        expect(dockText, contains('layers_step_executor.gd'));
        expect(dockText, isNot(contains('Broken? Ask Agent to Fix')));
        expect(dockText, isNot(contains('Fix Latest Playtest Error (0)')));
        expect(dockText, contains('Undo Last AI'));
        expect(dockText, contains('_footer_box.visible = can_pass_playtest'));
        expect(dockText, contains('_is_feature_checkpoint_built'));
        expect(dockText, contains('OS.add_logger'));
        expect(dockText, contains('Build Feature in Godot'));
        expect(dockText, contains('Apply to Scene & Script'));
        expect(dockText, contains('Playtest in Arena'));
        expect(dockText, contains('Stop Playtest (F8)'));
        expect(dockText, contains('Open Scene'));
        expect(dockText, contains('Open Script'));
        expect(dockText, contains('_pending_bundle_is_auto_repair'));
        expect(dockText, contains('is_playing_scene'));
        expect(dockText, contains('collect_project_scene_paths'));
        expect(dockText, contains('capture_input_map_snapshot'));
        expect(dockText, contains('diagnose_project_combat_and_wiring'));
        expect(dockText, contains('read_all_live_project_scripts'));
        expect(dockText, contains('Fix Detected Issues'));
        expect(dockText, contains('sync_live_scripts'));
        expect(dockText, contains('_bundle_apply_timer'));
        expect(dockText, contains('_post_playtest_log_timer'));
        expect(dockText, contains('verify_built_feature_integrity'));
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

        expect(executorText, contains('ClassDB.class_exists'));
        expect(executorText, contains('inspect_object'));
        expect(executorText, contains('save_scene()'));
        expect(executorText, contains('merge_step_code_into_existing'));
        expect(executorText, contains('parse_signal_specs'));
        expect(executorText, contains('undo_redo'));
        expect(executorText, contains('apply_agent_bundle'));
        expect(executorText, contains('preserve_existing_visuals'));
        expect(executorText, contains('verify_built_feature_integrity'));
        expect(executorText, contains('sceneFilePath'));
        expect(executorText, isNot(contains('func extract_feature_export_tuners')));
        expect(executorText, isNot(contains('func apply_fix_patch')));
        expect(executorText, isNot(contains('func read_live_scripts_for_feature')));
        expect(executorText, contains('_unset_subtree_owners'));
        expect(executorText, contains('capture_bundle_snapshot'));
        expect(executorText, contains('restore_bundle_snapshot'));
        expect(executorText, contains('restored_scripts'));
        expect(executorText, contains('is_likely_gdscript_snippet'));
        expect(executorText, contains('can_attach_script_to_node'));
        expect(executorText, contains('evaluate_feature'));
        expect(executorText, contains('invalidate_eval_cache'));
        expect(executorText, contains('infer_scene_root_type'));
        expect(executorText, contains('upgrade_scene_root_type_on_disk'));
        expect(executorText, contains('apply_input_ops'));
        expect(executorText, contains('register_missing_script_input_actions'));
        expect(executorText, contains('add_to_group'));
        expect(executorText, contains('ResourceLoader.CACHE_MODE_REUSE'));
        expect(executorText, contains('reload_script_safely'));
        expect(executorText, contains('sanitize_null_script_exports'));
        expect(executorText, contains('ensure_scene_exists_and_open'));
        expect(executorText, contains('heal_empty_project_input_actions'));
        expect(executorText, contains('read_recent_godot_log_errors'));
        expect(executorText, contains('read_editor_and_playtest_errors'));
        expect(executorText, contains('reparent_node'));
        expect(executorText, contains('capture_input_map_snapshot'));
        expect(executorText, contains('diagnose_project_combat_and_wiring'));
        expect(executorText, contains('shapeProps'));
        expect(executorText, contains('collisionLayer'));

        expect(fnText, contains('decodeThreeAreaNotesJs'));
        expect(fnText, contains('extractBareGdScriptPathJs'));
        expect(fnText, contains('markFeatureBuiltInGodotJs'));
        expect(fnText, contains('isBuiltInGodot'));
        expect(fnText, contains('coveredScope'));
        expect(fnText, contains('last_godot_sync_ms'));
        expect(fnText, contains('"diagnose_fix"'));
        expect(fnText, contains('"build_feature"'));
        expect(fnText, contains('"direct_agent"'));
        expect(fnText, contains('"sync_scripts"'));
        expect(fnText, contains('"add_to_group"'));
        expect(fnText, contains('"reparent_node"'));
        expect(fnText, contains('inputMapSnapshot'));
        expect(fnText, contains('projectDiagnostics'));
        expect(fnText, contains('get_overlapping_bodies'));
        expect(fnText, contains('16384'));
        expect(fnText, contains('inputOps'));
        expect(fnText, contains('sceneOps'));
        expect(fnText, contains('scriptUpdates'));
        expect(fnText, contains('codeFiles'));
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

    test(
      'shouldPreferRemoteDocumentOnSync preserves newer remote CODEFILEs, PROJECT sync timestamps, completed subtasks & playtestPassed progress',
      () {
        final localCode = TierDocument(
          id: 'code_1',
          title: 'player.gd',
          tier: TierType.codeFile,
          sections: {
            GodotVirtualFile.resPathKey: 'res://scripts/player.gd',
            GodotVirtualFile.updatedAtMsKey: '1000',
            GodotVirtualFile.contentKey: 'extends CharacterBody3D\n',
          },
        );
        final remoteNewerCode = TierDocument(
          id: 'code_1',
          title: 'player.gd',
          tier: TierType.codeFile,
          sections: {
            GodotVirtualFile.resPathKey: 'res://scripts/player.gd',
            GodotVirtualFile.updatedAtMsKey: '2500',
            GodotVirtualFile.contentKey:
                'extends CharacterBody3D\n@export var dash_speed: float = 16.0\n',
          },
        );
        expect(
          shouldPreferRemoteDocumentOnSync(localCode, remoteNewerCode),
          isTrue,
        );
        expect(
          shouldPreferRemoteDocumentOnSync(remoteNewerCode, localCode),
          isFalse,
        );

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
          childrenIds: ['rel_1', 'code_1'],
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

        final localUnbuilt = TierDocument(
          id: 'feat_built',
          title: 'Dash',
          tier: TierType.feature,
          sections: {'states': '[{"id":"cp1","parameters":{"godotBuilt":"false"}}]'},
        );
        final remoteBuilt = TierDocument(
          id: 'feat_built',
          title: 'Dash',
          tier: TierType.feature,
          sections: {'states': '[{"id":"cp1","parameters":{"godotBuilt":"true"}}]'},
        );
        expect(
          shouldPreferRemoteDocumentOnSync(localUnbuilt, remoteBuilt),
          isTrue,
        );
      },
    );

    test(
      'Stage 1 2D vs 3D game_spec resolution overrides ambiguous Forward+/Greybox tech_spec defaults cleanly',
      () {
        final provider = WorkbenchProvider(enableAutoLoad: false);
        final proj3d = TierDocument(
          id: 'proj_3d',
          title: '3D Action Game',
          tier: TierType.project,
          sections: {
            'game_spec': '3D Third-Person Action · PC/Console',
            'tech_spec': 'Godot 4 Greybox (2D / Forward+)',
          },
        );
        provider.documents[proj3d.id] = proj3d;
        provider.switchProject(proj3d.id);
        expect(provider.activeGodotContract.is3D, isTrue);

        final proj2d = TierDocument(
          id: 'proj_2d',
          title: '2D Top-Down Game',
          tier: TierType.project,
          sections: {
            'game_spec': '2D Top-Down Arena · Web/PC',
            'tech_spec': 'Godot 4 Greybox (Forward+)',
          },
        );
        provider.documents[proj2d.id] = proj2d;
        provider.switchProject(proj2d.id);
        expect(provider.activeGodotContract.is3D, isFalse);
      },
    );

    test(
      'activeProjectGodotFiles deduplicates duplicate CODEFILE docs by res_path keeping newest updatedAtMs, unions featureIds, and builds planner summary',
      () {
        final provider = WorkbenchProvider(enableAutoLoad: false);
        final proj = TierDocument(
          id: 'proj_dedup',
          title: 'Crab Arena',
          tier: TierType.project,
        );
        final olderDoc = GodotVirtualFile(
          id: 'proj_dedup_code_crab_player_gd_111111',
          projectId: proj.id,
          resPath: 'res://scripts/crab_player.gd',
          content: 'extends Node\n@export var legacy_speed: float = 1.0\n',
          language: 'gdscript',
          releaseVersion: 'v0.1',
          featureIds: const ['feat_a'],
          updatedAtMs: 1000,
        ).toTierDocument();
        final newerDoc = GodotVirtualFile(
          id: 'proj_dedup_code_scripts_crab_player_gd_111111',
          projectId: proj.id,
          resPath: 'res://scripts/crab_player.gd',
          content:
              'extends CharacterBody3D\n@export var move_speed: float = 8.5\nfunc _physics_process(delta: float) -> void:\n\tpass\n',
          language: 'gdscript',
          releaseVersion: 'v0.1',
          featureIds: const ['feat_b'],
          updatedAtMs: 2500,
        ).toTierDocument();
        provider.documents[proj.id] = proj;
        provider.documents[olderDoc.id] = olderDoc;
        provider.documents[newerDoc.id] = newerDoc;
        provider.switchProject(proj.id);

        final files = provider.activeProjectGodotFiles;
        expect(files, hasLength(1));
        final resolved = provider.godotFileForResPath('res://scripts/crab_player.gd');
        expect(resolved, isNotNull);
        expect(resolved!.content, contains('move_speed'));
        expect(resolved.content, isNot(contains('legacy_speed')));
        expect(resolved.featureIds, containsAll(const ['feat_a', 'feat_b']));

        final summary = provider.buildGodotCodebaseSummaryForPlanner(
          featureIds: const ['feat_a'],
        );
        expect(summary, contains('res://scripts/crab_player.gd'));
        expect(summary, contains('@export var move_speed: float = 8.5'));
        expect(summary, contains('func _physics_process(delta: float)'));
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
}
