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
import 'package:layers_agentic/screens/widgets/godot_inspector_panel.dart';
import 'package:layers_agentic/screens/widgets/godot_workbench_modals.dart';
import 'package:layers_agentic/services/godot_folder_sync_interface.dart';
import 'package:layers_agentic/services/godot_folder_sync_io.dart';
import 'package:layers_agentic/theme/app_theme.dart';
import 'package:layers_agentic/utils/godot_gdscript_guard.dart';

class _InMemoryFolderSyncBackend implements GodotFolderSyncBackend {
  final Map<String, String> diskFiles = {};
  final Map<String, String?> undoSnapshots = {};
  bool linked = true;

  @override
  bool get isSupported => true;
  @override
  String get unsupportedReason => '';
  @override
  bool get isLinked => linked;
  @override
  String get linkedFolderLabel => linked ? '/mock/godot_project' : '';

  @override
  Future<GodotFolderSnapshot> linkAndPullFolder({String? directoryPath}) async {
    linked = true;
    return refreshLinkedFolder();
  }

  @override
  Future<GodotFolderSnapshot> refreshLinkedFolder() async {
    if (!linked) {
      return const GodotFolderSnapshot(
        folderLabel: '',
        errorMessage: 'Folder not linked',
      );
    }
    return GodotFolderSnapshot(
      folderLabel: linkedFolderLabel,
      projectGodotText: '[layer_names]\n2d_physics/layer_1="World"\n',
      filesByResPath: Map<String, String>.from(diskFiles),
    );
  }

  @override
  Future<String?> readDiskFile(String resPath) async =>
      diskFiles[GodotVirtualFile.normalizeResPath(resPath)];

  @override
  Future<GodotWriteResult> writeAllowedFile({
    required String resPath,
    required String content,
  }) async {
    final norm = GodotVirtualFile.normalizeResPath(resPath);
    if (!isSafeWritableGodotResPath(norm)) {
      return GodotWriteResult(success: false, resPath: norm, message: 'Blocked');
    }
    undoSnapshots[norm] = diskFiles[norm];
    diskFiles[norm] = content;
    return GodotWriteResult(
      success: true,
      resPath: norm,
      message: 'Updated $norm on disk.',
      canUndo: true,
    );
  }

  @override
  bool canUndo(String resPath) =>
      undoSnapshots.containsKey(GodotVirtualFile.normalizeResPath(resPath));

  @override
  String? previousDiskContent(String resPath) =>
      undoSnapshots[GodotVirtualFile.normalizeResPath(resPath)];

  @override
  Future<GodotWriteResult> undoLastWrite(String resPath) async {
    final norm = GodotVirtualFile.normalizeResPath(resPath);
    final prev = undoSnapshots.remove(norm);
    if (prev == null) {
      diskFiles.remove(norm);
    } else {
      diskFiles[norm] = prev;
    }
    return GodotWriteResult(
      success: true,
      resPath: norm,
      message: 'Restored $norm.',
    );
  }

  @override
  void unlink() => linked = false;
}

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

      const rawProjectGodot = '''
config_version=5

[application]
config/name="Arena"

[autoload]
AudioMgr="*res://scripts/audio_mgr.gd"

[input]
dash={
"deadzone": 0.5,
"events": []
}

[layer_names]
3d_physics/layer_4="Projectile"
''';
      final merged = contract.mergeFromProjectGodotIni(rawProjectGodot);
      expect(merged.is3D, isTrue);
      expect(merged.physicsLayers[4], 'Projectile');
      expect(merged.physicsLayers[1], 'World');
      expect(merged.inputActions, containsAll(['move_left', 'jump', 'dash']));
      expect(
        merged.autoloads.any((a) => a.name == 'AudioMgr' && a.resPath == 'res://scripts/audio_mgr.gd'),
        isTrue,
      );
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

  group('GodotFolderSyncIoImpl', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('layers_godot_sync_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('requires project.godot, ignores .godot cache, blocks .tscn writes, writes & restores .gd', () async {
      final sync = GodotFolderSyncIoImpl();

      final missingRes = await sync.linkAndPullFolder(directoryPath: tempDir.path);
      expect(missingRes.ok, isFalse);
      expect(missingRes.errorMessage, contains('project.godot'));

      File('${tempDir.path}/project.godot').writeAsStringSync('''
[layer_names]
2d_physics/layer_1="World"
2d_physics/layer_2="Player"
''');
      Directory('${tempDir.path}/scripts').createSync();
      File('${tempDir.path}/scripts/player.gd').writeAsStringSync('extends CharacterBody2D\n');
      Directory('${tempDir.path}/.godot').createSync();
      File('${tempDir.path}/.godot/internal.gd').writeAsStringSync('should_skip\n');

      final snap = await sync.linkAndPullFolder(directoryPath: tempDir.path);
      expect(snap.ok, isTrue);
      expect(snap.filesByResPath.containsKey('res://scripts/player.gd'), isTrue);
      expect(snap.filesByResPath.keys.any((k) => k.contains('.godot')), isFalse);

      // Refuse writing .tscn scenes or project.godot
      final blockedSceneWrite = await sync.writeAllowedFile(
        resPath: 'res://scenes/player.tscn',
        content: '[gd_scene format=3]',
      );
      expect(blockedSceneWrite.success, isFalse);

      // Compute diff and write .gd with Undo snapshot
      const newScript = 'extends CharacterBody2D\n@export var speed: float = 300.0\n';
      final diff = GodotVirtualFile.computeUnifiedDiff(
        snap.filesByResPath['res://scripts/player.gd']!,
        newScript,
      );
      expect(diff.any((d) => d.kind == GodotDiffLineKind.added && d.text.contains('speed')), isTrue);

      final writeRes = await sync.writeAllowedFile(
        resPath: 'res://scripts/player.gd',
        content: newScript,
      );
      expect(writeRes.success, isTrue);
      expect(sync.canUndo('res://scripts/player.gd'), isTrue);
      expect(
        File('${tempDir.path}/scripts/player.gd').readAsStringSync(),
        contains('@export var speed: float = 300.0'),
      );

      final undoRes = await sync.undoLastWrite('res://scripts/player.gd');
      expect(undoRes.success, isTrue);
      expect(
        File('${tempDir.path}/scripts/player.gd').readAsStringSync(),
        'extends CharacterBody2D\n',
      );
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

    testWidgets('Godot Files modal shows Cloud file, Contract dialog, and Red/Green Diff confirmation', (tester) async {
      final sync = _InMemoryFolderSyncBackend()
        ..diskFiles['res://scripts/player.gd'] = 'extends Node\n';

      final provider = WorkbenchProvider(godotSyncBackend: sync);
      final proj = TierDocument(
        id: 'proj_ui',
        title: 'Modal Game',
        tier: TierType.project,
      );
      provider.documents[proj.id] = proj;
      provider.switchProject(proj.id);
      await provider.linkGodotProjectFolder();
      provider.upsertGodotVirtualFile(
        resPath: 'res://scripts/player.gd',
        content: 'extends Node\n@export var speed: int = 10\n',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showGodotFilesAndSyncDialog(ctx, provider),
                  child: const Text('Open Godot Files'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Godot Files'));
      await tester.pumpAndSettle();

      expect(find.text('Active Godot 4 Files & Sync'), findsOneWidget);
      expect(find.textContaining('Review Diff'), findsOneWidget);

      // Edit Project Contract directly from the modal header button
      await tester.tap(find.byKey(const ValueKey('godot_modal_open_contract_btn')));
      await tester.pumpAndSettle();
      expect(find.text('Godot 4 Project Contract'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('contract_layers_input')),
        '1: World, 2: Player, 3: Enemy, 4: Loot',
      );
      await tester.tap(find.byKey(const ValueKey('contract_save_btn')));
      await tester.pumpAndSettle();
      expect(provider.activeGodotContract.physicsLayers[4], 'Loot');

      await tester.tap(find.byKey(const ValueKey('godot_modal_review_diff_btn')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Review Disk Diff'), findsOneWidget);
      expect(find.textContaining('+ @export var speed: int = 10'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('confirm_apply_disk_diff_btn')));
      await tester.pumpAndSettle();

      expect(
        sync.diskFiles['res://scripts/player.gd'],
        contains('@export var speed: int = 10'),
      );
      expect(find.byKey(const ValueKey('godot_modal_undo_disk_btn')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('godot_modal_undo_disk_btn')));
      await tester.pumpAndSettle();
      expect(
        sync.diskFiles['res://scripts/player.gd'],
        'extends Node\n',
      );
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
      _InMemoryFolderSyncBackend sync,
    })> seedDashWorkbench() async {
      final sync = _InMemoryFolderSyncBackend()
        ..diskFiles['res://scripts/player_dash.gd'] =
            'extends CharacterBody2D\n';
      final provider = WorkbenchProvider(godotSyncBackend: sync);
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
      await provider.linkGodotProjectFolder();
      provider.upsertGodotVirtualFile(
        resPath: 'res://scripts/player_dash.gd',
        content:
            'extends CharacterBody2D\n@export var dash_speed: float = 640.0\n',
        featureIds: [feat.id],
      );
      provider.selectFeature(feat.id, triggerAiSynthesis: false);
      return (provider: provider, feat: feat, cp: cp, sync: sync);
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

        // 4. Select CODE step (now index 1) -> shows inline Plan B sync strip ("Patched in Cloud")
        await tester.tap(find.byKey(ValueKey('build_queue_step_${cp.id}_1')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('inline_code_sync_strip_${cp.id}_1')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Patched in Cloud · res://scripts/player_dash.gd'),
          findsOneWidget,
        );

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
      'Inline Code File workspace mode (Plan B tabs + starter .tscn) and Split-Screen (<700px) flat step dropdown',
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

        // 1. Switch workspace to Code File mode -> shows Cloud .gd file + starter .tscn tab + Plan B Review button
        await tester.tap(
          find.byKey(ValueKey('workspace_mode_code_file_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('code_file_workspace_${cp.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('code_mode_file_tab_res://scripts/player_dash.gd')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('code_mode_review_diff_btn_${cp.id}')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(ValueKey('code_mode_starter_tscn_tab_${cp.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('[gd_scene'), findsWidgets);

        // 2. Return to Runbook and resize to Split-Screen (< 700px) -> collapses queue into 1-line floating bar
        await tester.tap(
          find.byKey(ValueKey('workspace_mode_runbook_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();

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
      'Code File mode scopes to active Feature files, supports Refresh Disk / Sync to Specs, and Sync Code modal loads active script',
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
        final sync = setup.sync;

        // Add unrelated script on another feature
        provider.upsertGodotVirtualFile(
          resPath: 'res://scripts/enemy_patrol.gd',
          content: 'extends Node2D\n@export var patrol_speed: float = 120.0\n',
        );
        sync.diskFiles['res://scripts/player_dash.gd'] =
            'extends CharacterBody2D\n@export var dash_speed: float = 780.0\n';

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

        // 1. Switch to Code File mode: shows player_dash.gd and hides unrelated enemy_patrol.gd until toggled
        await tester.tap(
          find.byKey(ValueKey('workspace_mode_code_file_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const ValueKey('code_mode_file_tab_res://scripts/player_dash.gd'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('code_mode_file_tab_res://scripts/enemy_patrol.gd'),
          ),
          findsNothing,
        );

        await tester.tap(
          find.byKey(ValueKey('code_mode_toggle_all_files_${cp.id}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const ValueKey('code_mode_file_tab_res://scripts/enemy_patrol.gd'),
          ),
          findsOneWidget,
        );

        // 2. Refresh Disk picks up new disk file cleanly without clobbering existing Cloud edits,
        //    and Sync to Specs syncs updated @export var from the active Cloud script
        sync.diskFiles['res://scripts/player_dash_extra.gd'] =
            'extends Node2D\n';
        await tester.tap(
          find.byKey(ValueKey('code_mode_refresh_disk_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();
        expect(
          provider.godotFileForResPath('res://scripts/player_dash_extra.gd'),
          isNotNull,
        );

        provider.upsertGodotVirtualFile(
          resPath: 'res://scripts/player_dash.gd',
          content:
              'extends CharacterBody2D\n@export var dash_speed: float = 780.0\n',
          featureIds: [feat.id],
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('780.0'), findsWidgets);
        final syncSpecsBtn =
            find.byKey(ValueKey('code_mode_sync_to_specs_btn_${cp.id}'));
        await tester.ensureVisible(syncSpecsBtn);
        await tester.tap(syncSpecsBtn);
        await tester.pumpAndSettle();
        final syncedCp = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(
          syncedCp.tuningParams.join(' '),
          contains('780'),
        );

        // 3. Switch back to Runbook, open Sync Code modal, and 1-click load active script
        await tester.tap(
          find.byKey(ValueKey('workspace_mode_runbook_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('sync_feature_from_code_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('load_active_code_into_sync_btn')),
        );
        await tester.pumpAndSettle();
        final syncField = tester.widget<TextField>(
          find.byKey(const ValueKey('sync_feature_code_input_field')),
        );
        expect(syncField.controller?.text, contains('dash_speed'));
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
        expect(find.text('⇄ Sync code to specs'), findsOneWidget);
        expect(find.text('⚑ Log playtest issue'), findsOneWidget);
        expect(find.text('📦 Godot files & sync'), findsOneWidget);
        expect(find.text('⚙ Project contract'), findsOneWidget);

        await tester.tap(find.text('⚙ Project contract'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
      },
    );

    testWidgets(
      'Code File mode generates starter .gd scaffold and supports inline Edit -> Save & Sync Specs',
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
        provider.documents.removeWhere((_, d) => d.tier == TierType.codeFile);

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

        // 1. Switch to Code File mode with empty project files -> + Create Starter .gd
        await tester.tap(
          find.byKey(ValueKey('workspace_mode_code_file_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();
        final createBtn =
            find.byKey(ValueKey('code_mode_create_starter_gd_btn_${cp.id}'));
        expect(createBtn, findsOneWidget);
        await tester.tap(createBtn);
        await tester.pumpAndSettle();

        final createdVf =
            provider.godotFileForResPath('res://scripts/player_dash.gd');
        expect(createdVf, isNotNull);
        expect(createdVf!.content, contains('extends CharacterBody2D'));
        expect(createdVf.content, contains('@export var dash_speed'));

        // 2. Click Edit, change content to add dash_cooldown @export, Save & Sync Specs
        await tester.tap(find.byKey(ValueKey('code_mode_edit_btn_${cp.id}')));
        await tester.pumpAndSettle();
        final editorInput =
            find.byKey(ValueKey('code_mode_editor_input_${cp.id}'));
        expect(editorInput, findsOneWidget);
        await tester.enterText(
          editorInput,
          'extends CharacterBody2D\n@export var dash_speed: float = 820.0\n@export var dash_cooldown: float = 0.75\n',
        );
        await tester.tap(
          find.byKey(ValueKey('code_mode_save_sync_btn_${cp.id}')),
        );
        await tester.pumpAndSettle();

        final editedVf =
            provider.godotFileForResPath('res://scripts/player_dash.gd');
        expect(editedVf?.content, contains('dash_cooldown: float = 0.75'));
        final syncedCp = FeatureStateNode.getStatesForDocument(
          provider.documents[feat.id]!,
        ).first;
        expect(
          syncedCp.tuningParams.join(' '),
          allOf(contains('820'), contains('dash_cooldown')),
        );
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

        // 2. Alt+ArrowDown advances to step 1; Alt+\ toggles Code File mode; Alt+Enter marks active step done
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();

        expect(
          find.byKey(ValueKey('step_check_toggle_btn_${cp.id}_1')),
          findsOneWidget,
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.backslash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.backslash);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('code_file_workspace_${cp.id}')),
          findsOneWidget,
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.backslash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.backslash);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('code_file_workspace_${cp.id}')),
          findsNothing,
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
  });
}
