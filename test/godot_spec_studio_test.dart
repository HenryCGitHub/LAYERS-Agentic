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
import 'package:layers_agentic/screens/widgets/godot_bridge_modals.dart';
import 'package:layers_agentic/services/local_vault_service.dart';
import 'package:layers_agentic/services/storage/vault_storage_interface.dart';
import 'package:layers_agentic/theme/app_theme.dart';
import 'package:layers_agentic/utils/godot_context_builder.dart';
import 'package:layers_agentic/utils/godot_spec_guard.dart';
import 'package:layers_agentic/utils/markdown_exporter.dart';

class _TestVaultBackend implements VaultStorageBackend {
  final Map<String, TierDocument> savedDocs = {};
  final List<String> saveOrder = [];

  @override
  Future<VaultLoadResult> loadVaultData() async =>
      const VaultLoadResult(documents: {});

  @override
  Future<void> saveDocument(TierDocument doc) async {
    savedDocs[doc.id] = doc;
    saveOrder.add(doc.id);
  }

  @override
  Future<void> deleteDocument(String docId) async {
    savedDocs.remove(docId);
  }

  @override
  Future<void> saveSettings({
    required String activeDocumentId,
    String? apiKey,
    String? modelName,
    String? planningModel,
    String? thinkingLevel,
    String? themeMode,
  }) async {}
}

void main() {
  group('Godot 4 (3D + 2D) Epic-Only Studio & 1-Click In-Dock Builder Tests', () {
    test(
      '1. GodotProjectDimension auto-detects 3D/2D from spark and converts units cleanly',
      () {
        expect(
          GodotProjectDimension.detectFromSpark(
            '2D pixel-art metroidvania where shadow torchlight shrinks',
          ),
          equals(GodotProjectDimension.dim2d),
        );
        expect(
          GodotProjectDimension.detectFromSpark(
            'Top-down 3D mech arena shooter with claw dash armor breaks',
          ),
          equals(GodotProjectDimension.dim3d),
        );

        final shellbreaker = GodotSparkPresets.byId('shellbreaker');
        expect(shellbreaker.dimension, equals(GodotProjectDimension.dim3d));
        expect(
          shellbreaker.dimension.pillLabel,
          equals('3D (m, m/s)'),
        );

        final emberkeep = GodotSparkPresets.byId('emberkeep');
        expect(emberkeep.dimension, equals(GodotProjectDimension.dim2d));
        expect(emberkeep.dimension.pillLabel, equals('2D (px, px/s)'));
        expect(
          emberkeep.initialEpics.first.tuning.first.unit,
          equals('px/s'),
        );

        final converted2d = ProjectConceptAgent.convertBlueprintDimension(
          shellbreaker,
          GodotProjectDimension.dim2d,
        );
        expect(converted2d.dimension, equals(GodotProjectDimension.dim2d));
        expect(converted2d.cameraContract, contains('Camera2D'));
        expect(converted2d.characterScale, contains('CharacterBody2D'));
        expect(converted2d.initialEpics.first.tuning.first.unit, equals('px/s'));
      },
    );

    test(
      '2. GodotSpecGuard strips Unreal/Unity leakage and formats snake_case @export keys',
      () {
        expect(
          GodotSpecGuard.containsEngineLeakage(
            'Spawn BP_CrabPlayer ACharacter with 1850 cm/s UMG HUD',
          ),
          isTrue,
        );

        final sanitized3d = GodotSpecGuard.sanitizeLine(
          'Attach BP_CrabPlayer ACharacter to SpringArm and test in PIE with UMG HUD at 1850 cm/s and 550 cm range',
          dimension: GodotProjectDimension.dim3d,
        );
        expect(
          GodotSpecGuard.containsEngineLeakage(sanitized3d),
          isFalse,
        );
        expect(sanitized3d, contains('CharacterBody3D'));
        expect(sanitized3d, contains('SpringArm3D'));
        expect(sanitized3d, contains('Playtest'));
        expect(sanitized3d, contains('18.5 m/s'));
        expect(sanitized3d, contains('5.5 m'));

        final sanitized2d = GodotSpecGuard.sanitizeLine(
          'Move ACharacter 320 cm/s in L_Forest_Arena with Niagara',
          dimension: GodotProjectDimension.dim2d,
        );
        expect(sanitized2d, contains('CharacterBody2D'));
        expect(sanitized2d, contains('320 px/s'));
        expect(sanitized2d, contains('forest_arena.tscn'));
        expect(sanitized2d, contains('GPUParticles2D'));

        expect(
          GodotSpecGuard.sanitizeTuningKey('bAllowAirDash'),
          equals('allow_air_dash'),
        );
        expect(
          GodotSpecGuard.sanitizeTuningKey('MaxWalkSpeed'),
          equals('max_walk_speed'),
        );
        expect(
          GodotSpecGuard.normalizeGodotUnit(
            'move_speed',
            'cm/s',
            dimension: GodotProjectDimension.dim3d,
          ),
          equals('m/s'),
        );
        expect(
          GodotSpecGuard.normalizeGodotUnit(
            'move_speed',
            'cm/s',
            dimension: GodotProjectDimension.dim2d,
          ),
          equals('px/s'),
        );
      },
    );

    test(
      '3. GodotContextBuilder renders 3D/2D context, roadmap, v0.2 deltas, live snapshot & [FIX] revision switch',
      () {
        final spec3d = GodotSparkPresets.byId('shellbreaker');
        final e01 = spec3d.initialEpics.first;
        final full = GodotContextBuilder.buildEpicGodotContext(
          rootSpec: spec3d,
          epic: e01,
          releaseEpics: spec3d.initialEpics,
          liveGodotContext: {
            'project_name': 'ShellbreakerGodot',
            'main_scene': 'res://scenes/shellbreaker_proto.tscn',
            'input_actions': ['move_left', 'claw_dash'],
            'scene_files': ['res://scenes/shellbreaker_proto.tscn'],
            'script_files': ['res://scripts/player_mech.gd'],
          },
        );
        expect(full, contains('# ROOT_GODOT_CONTEXT · SHELLBREAKER'));
        expect(
          full,
          contains('## Live Godot Project Snapshot (project.godot via Dock)'),
        );
        expect(full, contains('ShellbreakerGodot'));
        expect(full, contains('## Release Epic Roadmap (v0.1 · 0/3 Passed)'));
        expect(full, contains('### FULL-EPIC AUTONOMOUS BUILD & SELF-CHECK'));

        e01.fixes.add(
          EpicPieFix(
            id: 'fx1',
            text: 'Dash stops short at wall corner',
            resolved: false,
          ),
        );
        final fixCtx = GodotContextBuilder.buildEpicGodotContext(
          rootSpec: spec3d,
          epic: e01,
        );
        expect(fixCtx, contains('## Open Playtest Revisions ([FIX])'));
        expect(fixCtx, contains('### FOCUSED PLAYTEST REVISION PASS (1 OPEN [FIX])'));
        expect(fixCtx, contains('Dash stops short at wall corner'));
      },
    );

    test(
      '4. Dart GodotContextBuilder matches Node functions/index.js renderServerGodotEpicContextJs byte-for-byte across 3D, 2D, v0.2 Deltas & [FIX]',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final root3d = wb.conceptDraft!;
        final e01 = root3d.initialEpics[0].deepCopy();
        final e02 = root3d.initialEpics[1].deepCopy();
        final liveCtx = {
          'project_name': 'ShellbreakerGodot',
          'main_scene': 'res://scenes/shellbreaker_proto.tscn',
          'input_actions': ['move_left', 'claw_dash'],
          'scene_files': ['res://scenes/shellbreaker_proto.tscn'],
          'script_files': ['res://scripts/player_mech.gd'],
          'resource_files': ['res://data/mech_stats.tres'],
          'recent_errors': ['SCRIPT ERROR: Invalid get index on Sprite2D'],
        };

        // Scenario A: 3D v0.1 full build + roadmap + live context
        e01.lifecycle = EpicLifecycle.stable;
        for (final chk in e01.checks) {
          chk.passed = true;
        }
        e02.fixes.add(
          EpicPieFix(id: 'fx_a', text: 'Recoil pushes off floor', resolved: false),
        );
        final dartA = GodotContextBuilder.buildEpicGodotContext(
          rootSpec: root3d,
          epic: e02,
          releaseEpics: [e01, e02],
          liveGodotContext: liveCtx,
        );

        // Scenario B: 2D preset (emberkeep)
        final root2d = GodotSparkPresets.byId('emberkeep');
        final e2d = root2d.initialEpics.first.deepCopy();
        final dartB = GodotContextBuilder.buildEpicGodotContext(
          rootSpec: root2d,
          epic: e2d,
          releaseEpics: root2d.initialEpics,
        );

        // Scenario C: v0.2 upgraded Epic with baselineSummary + upgradeDeltas + open fixes = 0
        final v02Epic = e01.deepCopy()
          ..releaseVersion = 'v0.2'
          ..lifecycle = EpicLifecycle.upgrading
          ..baselineSummary = ['v0.1 Walk & Claw Dash verified']
          ..upgradeDeltas = ['Chain second dash on armor break'];
        final dartC = GodotContextBuilder.buildEpicGodotContext(
          rootSpec: root3d,
          epic: v02Epic,
          releaseEpics: [v02Epic],
        );

        String toJson(ProjectConceptBlueprint r, EpicSpec e, List<EpicSpec> list, Map<String, dynamic>? ctx) {
          final docs = <String, dynamic>{
            'root': r.toJson(),
            'epic': {
              'id': e.id,
              'title': e.title,
              'sections': {
                'code': e.code,
                'lineage_key': e.lineageKey,
                'release_version': e.releaseVersion,
                'lifecycle': e.lifecycle.name,
                'goal': e.goal,
                'epic_spec_json': jsonEncode(e.toJson()),
              },
              'isCompleted': e.isPassed,
            },
            'releaseEpics': [
              for (final s in list)
                {
                  'id': s.id,
                  'title': s.title,
                  'sections': {
                    'code': s.code,
                    'lineage_key': s.lineageKey,
                    'release_version': s.releaseVersion,
                    'lifecycle': s.lifecycle.name,
                    'goal': s.goal,
                    'epic_spec_json': jsonEncode(s.toJson()),
                  },
                  'isCompleted': s.isPassed,
                }
            ],
            'liveContext': ctx,
          };
          return jsonEncode(docs);
        }

        final payloadJson = jsonEncode({
          'a': jsonDecode(toJson(root3d, e02, [e01, e02], liveCtx)),
          'b': jsonDecode(toJson(root2d, e2d, root2d.initialEpics, null)),
          'c': jsonDecode(toJson(root3d, v02Epic, [v02Epic], null)),
        });

        final nodeScript = r'''
const path = require("path");
const { _testHelpers } = require(path.resolve(process.cwd(), "functions", "index.js"));
const input = JSON.parse(process.argv[1]);
function runCase(c) {
  const rootSpec = _testHelpers.parseRootSpecJs({
    title: c.root.gameTitle,
    sections: { concept_blueprint_json: JSON.stringify(c.root) },
  });
  const epicSpec = _testHelpers.parseEpicSpecJs(c.epic, 0, rootSpec.dimension);
  const relEpics = c.releaseEpics.map((s, idx) => _testHelpers.parseEpicSpecJs(s, idx, rootSpec.dimension));
  const liveCtx = c.liveContext ? _testHelpers.sanitizeGodotLiveContextJs(c.liveContext) : null;
  return _testHelpers.renderServerGodotEpicContextJs({
    rootSpec,
    epicSpec,
    releaseEpics: relEpics,
    liveGodotContext: liveCtx,
  });
}
console.log(JSON.stringify({
  a: runCase(input.a),
  b: runCase(input.b),
  c: runCase(input.c),
}));
''';
        final proc = Process.runSync('node', ['-e', nodeScript, payloadJson]);
        expect(proc.exitCode, equals(0), reason: 'stderr: ${proc.stderr}');
        final out = jsonDecode(proc.stdout.toString().trim()) as Map<String, dynamic>;

        expect(out['a'], equals(dartA), reason: 'Scenario A (3D + [FIX] + Snapshot + Roadmap) mismatch');
        expect(out['b'], equals(dartB), reason: 'Scenario B (2D emberkeep) mismatch');
        expect(out['c'], equals(dartC), reason: 'Scenario C (v0.2 Deltas) mismatch');
      },
    );

    testWidgets(
      '5. Stage 1 UI: Dimension 3D/2D toggle, 2D auto-detect on Spark, Clean Spec Only & Approve -> Stage 2',
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
        expect(find.byKey(const ValueKey('stage1_dim_3d')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_dim_2d')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_tab_raw')), findsNothing);
        expect(find.text('Copy Context'), findsNothing);

        await tester.enterText(
          find.byKey(const ValueKey('spark_prompt_input')),
          '2D pixel-art torch survival skirmisher with axe cleave',
        );
        await tester.tap(find.byKey(const ValueKey('draft_spark_btn')));
        await tester.pumpAndSettle();

        expect(wb.projectDimension, equals(GodotProjectDimension.dim2d));
        expect(find.byKey(const ValueKey('stage1_tab_raw')), findsNothing);
        expect(find.text('Copy Context'), findsNothing);
        expect(
          wb.activeRootGodotMarkdown,
          contains('Godot 4 2D (.tscn + GDScript .gd)'),
        );

        // Toggle explicitly back to 3D and see context update immediately
        await tester.tap(find.byKey(const ValueKey('stage1_dim_3d')));
        await tester.pumpAndSettle();
        expect(wb.projectDimension, equals(GodotProjectDimension.dim3d));
        expect(
          wb.activeRootGodotMarkdown,
          contains('Godot 4 3D (.tscn + GDScript .gd)'),
        );

        await tester.tap(find.byKey(const ValueKey('approve_launch_workbench_btn')));
        await tester.pumpAndSettle();

        expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('stage2_tab_raw')), findsNothing);
        expect(find.byKey(const ValueKey('copy_build_prompt_btn')), findsNothing);
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

        // Live Feature @export tuning edit updates Build Prompt immediately
        await tester.ensureVisible(
          find.byKey(const ValueKey('tuning_input_sb_f02_0')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('tuning_input_sb_f02_0')),
          '8.5',
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          wb.selectedBuildPrompt,
          contains('@export var dash_distance: float = 8.5 # m'),
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
          contains('FOCUSED [FIX] PASS (1 OPEN [FIX])'),
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
      '8. duplicateProject & importProjectFromJson clear stale last_godot_sync_ms and remap embedded IDs',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('emberkeep');
        wb.approveRootSpecAndLaunchWorkbench();

        wb.activeProject!.sections['last_godot_sync_ms'] = '1700000000000';
        expect(wb.isActiveProjectSyncedWithGodot, isTrue);

        final exported = wb.exportProjectToJson();
        final dupId = wb.duplicateProject(wb.activeProjectId!)!;
        expect(wb.activeProjectId, equals(dupId));
        expect(wb.isActiveProjectSyncedWithGodot, isFalse);

        final impId = wb.importProjectFromJson(exported)!;
        expect(wb.activeProjectId, equals(impId));
        expect(wb.isActiveProjectSyncedWithGodot, isFalse);
      },
    );

    testWidgets(
      '9. showConnectGodotPluginDialog downloads layers_godot_plugin.zip and rotates lyr_ token via /godotLink/token',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final prevHttp = GeminiAgentClient.testHttpPost;
        final prevAuth = GeminiAgentClient.authTokenProvider;
        int calls = 0;

        GeminiAgentClient.authTokenProvider =
            ({bool forceRefresh = false}) async => 'fake-id-token';
        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
          if (uri.path.endsWith('/godotLink/token')) {
            calls += 1;
            final req = jsonDecode(body.toString()) as Map<String, dynamic>;
            final rotate = req['rotate'] == true;
            return http.Response(
              jsonEncode({
                'ok': true,
                'projectId': req['projectId'],
                'linkToken': rotate
                    ? 'lyr_rotated_godot_9999888877776666'
                    : 'lyr_initial_godot_1111222233334444',
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
                      key: const ValueKey('open_godot_modal_btn'),
                      onPressed: () => showConnectGodotPluginDialog(ctx, wb),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.byKey(const ValueKey('open_godot_modal_btn')));
          await tester.pumpAndSettle();

          expect(find.text('Connect Godot 4 Editor Plugin'), findsOneWidget);
          expect(find.byKey(const ValueKey('download_godot_plugin_btn')), findsOneWidget);
          expect(find.text('lyr_initial_godot_1111222233334444'), findsOneWidget);
          expect(calls, equals(1));

          final rotateBtn = find.byKey(const ValueKey('rotate_godot_token_btn'));
          await tester.ensureVisible(rotateBtn);
          await tester.tap(rotateBtn);
          await tester.pumpAndSettle();
          expect(find.text('lyr_rotated_godot_9999888877776666'), findsOneWidget);
          expect(calls, equals(2));
        } finally {
          GeminiAgentClient.testHttpPost = prevHttp;
          GeminiAgentClient.authTokenProvider = prevAuth;
        }
      },
    );

    testWidgets(
      '10. GodotAuthHandoffOverlay (?godot_auth=1) flushes project tree to Cloud before minting token & redirecting to 127.0.0.1 loopback',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeBackend = _TestVaultBackend();
        final prevBackend = LocalVaultService.testBackendOverride;
        final prevHttp = GeminiAgentClient.testHttpPost;
        final prevAuth = GeminiAgentClient.authTokenProvider;
        final prevRedirect = debugBrowserRedirectInterceptor;
        String? redirectedUrl;
        bool flushedBeforeMint = false;

        LocalVaultService.testBackendOverride = fakeBackend;
        GeminiAgentClient.authTokenProvider =
            ({bool forceRefresh = false}) async => 'fake-id-token';
        debugBrowserRedirectInterceptor = (url) {
          redirectedUrl = url;
          return true;
        };

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('emberkeep');
        wb.approveRootSpecAndLaunchWorkbench();
        final targetPid = wb.activeProjectId!;

        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
          if (uri.path.endsWith('/godotLink/token')) {
            flushedBeforeMint = fakeBackend.savedDocs.containsKey(targetPid);
            return http.Response(
              jsonEncode({
                'ok': true,
                'projectId': targetPid,
                'linkToken': 'lyr_handoff_godot_1234567890abcdef',
              }),
              200,
            );
          }
          return http.Response('{"error":{"message":"Not found"}}', 404);
        };

        try {
          wb.setAiAccessRecordsForTest(
            const [],
            overrideEmail: 'dev@godot.studio',
          );
          wb.applyDeepLinkParams({
            'godot_auth': '1',
            'port': '54321',
            'state': 'nonce_xyz',
            'project_name': 'EmberKeep',
          });

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          expect(find.byKey(const ValueKey('godot_handoff_overlay')), findsOneWidget);
          expect(wb.effectiveGodotAuthProjectId, equals(targetPid));

          await tester.tap(find.byKey(const ValueKey('godot_handoff_approve_btn')));
          await tester.pumpAndSettle();

          expect(flushedBeforeMint, isTrue);
          expect(redirectedUrl, isNotNull);
          final parsed = Uri.parse(redirectedUrl!);
          expect(parsed.host, equals('127.0.0.1'));
          expect(parsed.port, equals(54321));
          expect(parsed.path, equals('/callback'));
          expect(parsed.queryParameters['state'], equals('nonce_xyz'));
          expect(
            parsed.queryParameters['token'],
            equals('lyr_handoff_godot_1234567890abcdef'),
          );
        } finally {
          debugBrowserRedirectInterceptor = prevRedirect;
          GeminiAgentClient.testHttpPost = prevHttp;
          GeminiAgentClient.authTokenProvider = prevAuth;
          LocalVaultService.testBackendOverride = prevBackend;
        }
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
            'res://scenes/player_mech.tscn',
            'res://scenes/arena_proto.tscn',
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
      '14. GodotContextBuilder.buildFeatureContext & buildEpicArchitectureContext bundle 3D/2D context, v0.2 deltas & [FIX] mode',
      () {
        final spec3d = GodotSparkPresets.byId('shellbreaker');
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

        final ctxV01 = GodotContextBuilder.buildFeatureContext(
          rootSpec: spec3d,
          epic: e01,
          feature: f02,
          releaseVersion: 'v0.1',
        );
        expect(ctxV01, contains('# ROOT_GODOT_CONTEXT · SHELLBREAKER'));
        expect(
          ctxV01,
          contains('## 2. PARENT EPIC ARCHITECTURE (E01 · Player Movement & Camera)'),
        );
        expect(ctxV01, contains('res://scenes/player_mech.tscn'));
        expect(ctxV01, contains('Idle -> Walk -> ClawDash -> Recovery'));
        expect(ctxV01, contains('No stamina bar in v0.1'));
        expect(
          ctxV01,
          contains('# ACTIVE FEATURE SPEC · F02 · Armored Claw Dash (v0.1 · 60 min)'),
        );
        expect(ctxV01, contains('Execution Mode: FULL FEATURE BUILD'));
        expect(ctxV01, contains('| InputMap Action | Binding | Trigger Rule |'));
        expect(ctxV01, contains('| claw_dash | Space / L-Trigger | 0.65 s cooldown |'));
        expect(ctxV01, contains('```gdscript'));
        expect(ctxV01, contains('@export var dash_distance_m: float = 4.0 # m'));
        expect(ctxV01, contains('@export var max_chains: int = 3 # count'));
        expect(ctxV01, contains('## §05 Playtest Gate'));
        expect(ctxV01, contains('- [x] Tap Space -> Mech crosses 4 m'));
        expect(
          ctxV01,
          contains('- [ ] Collide with cracked shell -> Enemy staggers 1.5 m'),
        );

        // v0.2 delta & delta check
        final ctxV02 = GodotContextBuilder.buildFeatureContext(
          rootSpec: spec3d,
          epic: e01,
          feature: f02,
          releaseVersion: 'v0.2',
        );
        expect(ctxV02, contains('## v0.2 Upgrade Delta'));
        expect(ctxV02, contains('Reset dash cooldown when breaking cracked shell'));
        expect(
          ctxV02,
          contains('Break shell then tap Space -> Second dash chains cleanly'),
        );

        // [FIX] revision mode switch
        f02.fixes.add(
          EpicPieFix(id: 'fx_dash', text: 'Dash clips pillar edge'),
        );
        final ctxFix = GodotContextBuilder.buildFeatureContext(
          rootSpec: spec3d,
          epic: e01,
          feature: f02,
          releaseVersion: 'v0.1',
        );
        expect(ctxFix, contains('FOCUSED [FIX] PASS (1 OPEN [FIX])'));
        expect(ctxFix, contains('## Open Playtest Revisions ([FIX])'));
        expect(ctxFix, contains('Dash clips pillar edge'));

        // Epic domain architecture brief (v0.1 vs v0.2 rollups)
        final archV02 = GodotContextBuilder.buildEpicArchitectureContext(
          rootSpec: spec3d,
          epic: e01,
          releaseVersion: 'v0.2',
        );
        expect(
          archV02,
          contains('# GODOT 4 EPIC ARCHITECTURE BRIEF · E01 · Player Movement & Camera (v0.2)'),
        );
        expect(archV02, contains('Progress: 1/3 Features Passed | 1 Open [FIX]'));
        expect(archV02, contains('[v0.1 ✓ BASELINE]'));
        expect(archV02, contains('[+v0.2 NEW]'));

        // 2D Feature context check
        final spec2d = GodotSparkPresets.byId('emberkeep');
        final f2d = FeatureSpec(
          id: 'f2d',
          code: 'F01',
          title: 'Roll Dash',
          goal: 'Move 128 px across spike floor.',
          tuning: [EpicTuningParam(key: 'dash_speed_px', value: '480', unit: 'px/s')],
        );
        final ctx2d = GodotContextBuilder.buildFeatureContext(
          rootSpec: spec2d,
          epic: e01,
          feature: f2d,
          releaseVersion: 'v0.1',
        );
        expect(ctx2d, contains('2D (px, px/s)'));
        expect(ctx2d, contains('@export var dash_speed_px: float = 480 # px/s'));

        // buildFullProjectSpecMarkdown includes Feature slices when present
        final fullMd = GodotContextBuilder.buildFullProjectSpecMarkdown(
          rootSpec: spec3d,
          epicsByReleaseLabel: {
            'v0.1 · Arena Prototype': [e01],
          },
        );
        expect(fullMd, contains('GODOT 4 EPIC ARCHITECTURE BRIEF'));
        expect(fullMd, contains('ACTIVE FEATURE SPEC · F02 · Armored Claw Dash'));
      },
    );

    test(
      '15. GodotSpecGuard.sanitizeFeatureSpec & markdown_exporter filename helpers strip leakage cleanly',
      () {
        final dirtyFeat = FeatureSpec(
          id: 'dirty_f01',
          code: '',
          title: 'Spawn BP_CrabDash in PIE',
          goal: 'Leverage unified velocity at 1850 cm/s in L_Arena_Proto.',
          inScope: ['Use IA_ClawDash via UMG HUD'],
          doneWhen: ['Validate dash hits ACharacter within 450 cm'],
          releaseDelta: '+ Seamlessly deliver 300 cm boost',
          controls: [
            EpicControlBinding(
              action: 'IA_ClawDash',
              trigger: 'Space',
              rule: 'Uses UInputAction cooldown',
            ),
          ],
          tuning: [
            EpicTuningParam(key: 'bAllowAirDash', value: 'true', unit: 'boolean'),
            EpicTuningParam(key: 'MaxDashDist', value: '450', unit: 'cm'),
          ],
          cues: ['Emit Niagara trail seamlessly'],
          checks: [
            EpicPieCheck(
              id: 'c1',
              text: 'Press IA_ClawDash -> Travel 450 cm in PIE',
            ),
          ],
        );

        final clean = GodotSpecGuard.sanitizeFeatureSpec(
          dirtyFeat,
          dimension: GodotProjectDimension.dim3d,
          forceCode: 'F02',
        );
        expect(clean.code, equals('F02'));
        expect(GodotSpecGuard.containsEngineLeakage(clean.title), isFalse);
        expect(GodotSpecGuard.containsEngineLeakage(clean.goal), isFalse);
        expect(clean.controls.single.action, equals('claw_dash'));
        expect(clean.tuning[0].key, equals('allow_air_dash'));
        expect(clean.tuning[0].unit, equals('bool'));
        expect(clean.tuning[1].key, equals('max_dash_dist'));
        expect(clean.tuning[1].value, equals('4.5'));
        expect(clean.tuning[1].unit, equals('m'));
        expect(clean.cues.single, contains('GPUParticles3D'));

        final parentEpic = EpicSpec(
          id: 'e_dirty',
          code: 'E01',
          title: 'Player Movement',
          goal: 'Move CharacterBody3D',
          sceneOwnership: [
            EpicSceneOwnership(
              path: 'res://scenes/BP_Player.tscn',
              role: 'BP_CrabPlayer root',
            ),
          ],
          features: [dirtyFeat],
        );
        final cleanEpic = GodotSpecGuard.sanitizeEpicSpec(
          parentEpic,
          dimension: GodotProjectDimension.dim3d,
        );
        expect(cleanEpic.features.single.code, equals('F01'));
        expect(cleanEpic.features.single.tuning[1].unit, equals('m'));
        expect(
          GodotSpecGuard.containsEngineLeakage(
            cleanEpic.sceneOwnership.single.role,
          ),
          isFalse,
        );

        expect(
          buildProjectSpecFilename('EMBERKEEP 2D'),
          equals('emberkeep_2d_project_spec.md'),
        );
      },
    );

    test(
      '16. Starter presets (shellbreaker, railjack, emberkeep), 3D/2D Feature conversion & offline Spark synthesis seed Large-Domain Epics with v0.1 Features',
      () async {
        for (final presetId in ['shellbreaker', 'railjack', 'emberkeep']) {
          final bp = GodotSparkPresets.byId(presetId);
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

        final sb = GodotSparkPresets.byId('shellbreaker');
        expect(
          sb.initialEpics.first.features.first.tuning.first.unit,
          equals('m/s'),
        );
        expect(sb.v02NewFeaturesByLineageKey['e01'], isNotEmpty);
        expect(
          sb.v02NewFeaturesByLineageKey['e01']!.first.introducedIn,
          equals('v0.2'),
        );

        final ek = GodotSparkPresets.byId('emberkeep');
        expect(
          ek.initialEpics.first.features.first.tuning.first.unit,
          equals('px/s'),
        );
        expect(ek.v02NewFeaturesByLineageKey['e01'], isNotEmpty);

        final sbAs2d = ProjectConceptAgent.convertBlueprintDimension(
          sb,
          GodotProjectDimension.dim2d,
        );
        expect(
          sbAs2d.initialEpics.first.features.first.tuning.first.unit,
          equals('px/s'),
        );
        expect(
          sbAs2d.v02NewFeaturesByLineageKey['e01']!.first.tuning
              .any((t) => t.unit == 'px' || t.unit == 'px/s'),
          isTrue,
        );

        final off2d = await ProjectConceptAgent.draftSpecFromSpark(
          sparkPrompt: '2D grapple dungeon crawler with lantern dashes',
          apiKey: '',
        );
        expect(off2d.dimension, equals(GodotProjectDimension.dim2d));
        for (final epic in off2d.initialEpics) {
          expect(epic.sceneOwnership, isNotEmpty);
          expect(epic.features.length, greaterThanOrEqualTo(2));
          expect(
            epic.features.first.tuning.any((t) => t.unit == 'px/s' || t.unit == 'px'),
            isTrue,
          );
        }
      },
    );

    test(
      '17. ReleasePlannerAgent proposes v0.2+ [+NEW] Features and [+DELTA] upgrades inside existing Epics (offline & mocked Gemini)',
      () async {
        final sb = GodotSparkPresets.byId('shellbreaker');
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
      '18. Stage 1 Spark & Refiner core: dimension detection, strict preset match, vague-spark forks, real AI error surfacing, scoped 2D/3D patch conversion, locomotion sync & genre-aware fallback',
      () async {
        // 1. Live dimension detection
        expect(
          GodotProjectDimension.detectFromSpark(
            '3D platformer with grappling hook',
          ),
          equals(GodotProjectDimension.dim3d),
        );
        expect(
          GodotProjectDimension.detectFromSpark(
            'side-scrolling platformer about a frog',
          ),
          equals(GodotProjectDimension.dim2d),
        );
        expect(
          GodotProjectDimension.detectFromSpark('bullet-hell arcade shooter'),
          equals(GodotProjectDimension.dim2d),
        );

        // 2. Strict preset matching (no false matches on generic words)
        expect(
          GodotSparkPresets.matchSparkPrompt('cozy crab cooking game'),
          isNull,
        );
        expect(GodotSparkPresets.matchSparkPrompt('shellbreaker'), isNotNull);

        // 3. Vague spark heuristic
        expect(
          SparkClarificationDraft.isSparkVague('cozy farming roguelike'),
          isTrue,
        );
        expect(
          SparkClarificationDraft.isSparkVague(
            '2D pixel-art torch survival skirmisher with axe cleave',
          ),
          isFalse,
        );

        // 4 & 5. Real AI failure surfacing on draftSpecWithStatus & applyCoDesignEditWithStatus
        final prevMock = GeminiAgentClient.testMockResponder;
        final prevStatus = GeminiAgentClient.lastErrorStatus;
        GeminiAgentClient.testMockResponder = (_, __) async => null;
        GeminiAgentClient.lastErrorStatus = 'HTTP 503: Service Unavailable';
        try {
          final draftErr = await ProjectConceptAgent.draftSpecWithStatus(
            sparkPrompt: 'Top-down melee beetle brawler with dash',
            apiKey: 'test-key-1234',
          );
          expect(draftErr.blueprint, isNull);
          expect(draftErr.errorMessage, isNotEmpty);

          final seedSpec = GodotSparkPresets.byId('shellbreaker');
          final prevPillars = List<String>.from(seedSpec.pillars);
          final refineErr = await ProjectConceptAgent.applyCoDesignEditWithStatus(
            currentSpec: seedSpec,
            instruction: 'Add parry shield',
            apiKey: 'test-key-1234',
          );
          expect(refineErr.blueprint, isNull);
          expect(refineErr.errorMessage, isNotEmpty);
          expect(seedSpec.pillars, equals(prevPillars));

          // 6. Scoped patch refine switching to dim2d converts m/s -> px/s scaled by 40,
          // renumbers F01..FM sequentially, clears stale v0.2 preset data on title/pitch shift,
          // and leaves untouched Epics intact.
          GeminiAgentClient.testMockResponder = (_, __) async => <String, dynamic>{
                'coDesignNote': 'Switched to 2D side-scroller and added turret cut',
                'changedSections': ['s01', 's02', 's04'],
                'gameTitle': 'TIDAL HOP',
                'pitch': '2D side-scrolling claw dasher — leap across ruins',
                'dimension': 'dim2d',
                'cameraChoiceId': 'sidescroller2d',
                'cameraContract': 'Camera2D Zoom 1.4x · Lookahead 64 px',
                'outOfScope': [
                  ...seedSpec.outOfScope,
                  'No deployable sentry turrets',
                ],
              };
          final patchOk = await ProjectConceptAgent.applyCoDesignEditWithStatus(
            currentSpec: seedSpec,
            instruction: 'Switch to a 2D side-scroller called Tidal Hop and cut sentry turrets',
            apiKey: 'test-key-1234',
          );
          expect(patchOk.errorMessage, isNull);
          final updated = patchOk.blueprint!;
          expect(updated.dimension, equals(GodotProjectDimension.dim2d));
          final f01Speed = updated.initialEpics.first.features.first.tuning
              .firstWhere((t) => t.key == 'move_speed');
          expect(f01Speed.unit, equals('px/s'));
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
        final reordered = GodotSparkPresets.byId('shellbreaker').deepCopy();
        final movedE01 = reordered.initialEpics.removeAt(0);
        reordered.initialEpics.insert(1, movedE01);
        reordered.initialEpics[0].code = 'E01';
        reordered.initialEpics[1].code = 'E02';

        ProjectConceptAgent.syncEpicCameraFraming(
          reordered,
          optionId: 'fps',
          contractValue: 'Camera3D EyeHeight 1.65 m · 90 deg FOV · Captured mouse yaw/pitch',
        );
        ProjectConceptAgent.syncEpicCoreFeel(reordered, feelId: 'heavy');

        final wrongFirstFeat = reordered.initialEpics[0].features.first;
        final locoFeat = reordered.initialEpics[1].features.first;
        expect(
          wrongFirstFeat.tuning.any((t) => t.key == 'eye_height'),
          isFalse,
        );
        expect(
          locoFeat.tuning.any((t) => t.key == 'eye_height'),
          isTrue,
        );
        expect(
          locoFeat.tuning.firstWhere((t) => t.key == 'braking_decel').value,
          equals('14.0'),
        );
        expect(
          locoFeat.controls.any((c) => c.action == 'look_axis'),
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
              .any((s) => s.path.contains('room_proto.tscn')),
          isTrue,
        );
        expect(
          puzzleOff.initialEpics.any(
            (e) => e.sceneOwnership.any((s) => s.path.contains('target_enemy')),
          ),
          isFalse,
        );

        final racerOff = await ProjectConceptAgent.draftSpecFromSpark(
          sparkPrompt: '3D canyon hover racer with drift boost pads and lap timer',
          apiKey: '',
        );
        expect(
          racerOff.initialEpics.first.sceneOwnership
              .any((s) => s.path.contains('track_proto.tscn')),
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

        // 1. Live 2D preview while typing before tapping Draft
        await tester.enterText(
          find.byKey(const ValueKey('spark_prompt_input')),
          '2D platformer frog',
        );
        await tester.pump();
        expect(wb.projectDimension, equals(GodotProjectDimension.dim2d));

        // 2. Vague spark shows 3-fork clarification card -> Confirm drafts spec + Scope preview
        await tester.enterText(
          find.byKey(const ValueKey('spark_prompt_input')),
          'cozy farming roguelike',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('draft_spark_btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('stage1_spark_clarify_card')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('clarify_archetype_puzzle')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('stage1_clarify_confirm_btn')),
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
          final sb = GodotSparkPresets.byId('shellbreaker');

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
                            'name': 'propose_progressive_godot_release',
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
          expect(capturedPrompt, contains('res://scripts/player_mech.gd'));
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

          // 4) Offline Emberkeep v0.2 parity: keeps ek_f07_roll selected with 2D px/px/s units
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
                  (t) => t.unit == 'px' || t.unit == 'px/s',
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
      '22. GodotSpecGuard regex safety, m<->px & uu tuning scaling, and full 3D<->2D blueprint prose conversion',
      () {
        expect(
          GodotSpecGuard.sanitizeLine('-52 deg pitch'),
          equals('-52 deg pitch'),
        );
        expect(
          GodotSpecGuard.sanitizeLine('- Bullet line'),
          equals('Bullet line'),
        );

        final pathLine = GodotSpecGuard.sanitizeLine(
          'Open res://scenes/L_Arena_Proto.tscn in MyGame.uproject',
        );
        expect(pathLine, contains('res://scenes/arena_proto.tscn'));
        expect(pathLine, isNot(contains('.tscn.tscn')));
        expect(pathLine, contains('project.godot'));
        expect(pathLine, isNot(contains('MyGameproject.godot')));

        final uuLine = GodotSpecGuard.sanitizeLine(
          'Dash 550 uu at 1200 uu/s',
          dimension: GodotProjectDimension.dim3d,
        );
        expect(uuLine, equals('Dash 5.5 m at 12 m/s'));
        expect(GodotSpecGuard.containsEngineLeakage(uuLine), isFalse);

        expect(
          GodotSpecGuard.sanitizeLine('Complete the end-to-end loop'),
          equals('Complete the core loop'),
        );
        final jargonClean = GodotSpecGuard.sanitizeLine(
          'Leveraged arena staging while validating delivered hits',
        );
        expect(jargonClean.toLowerCase(), isNot(contains('leveraged')));
        expect(jargonClean.toLowerCase(), isNot(contains('staging')));
        expect(jargonClean.toLowerCase(), isNot(contains('validating')));
        expect(jargonClean.toLowerCase(), isNot(contains('delivered')));
        expect(jargonClean.toLowerCase(), contains('used'));
        expect(jargonClean.toLowerCase(), contains('layout'));
        expect(jargonClean.toLowerCase(), contains('checking'));
        expect(jargonClean.toLowerCase(), contains('produced'));

        final feat2d = GodotSpecGuard.sanitizeFeatureSpec(
          FeatureSpec(
            id: 'f_scale_2d',
            code: 'F01',
            title: 'Dash',
            goal: 'Dash cleanly.',
            tuning: [
              EpicTuningParam(key: 'move_speed', value: '6.4', unit: 'm/s'),
              EpicTuningParam(key: 'dash_dist', value: '5.5', unit: 'm'),
            ],
          ),
          dimension: GodotProjectDimension.dim2d,
        );
        expect(feat2d.tuning[0].value, equals('256'));
        expect(feat2d.tuning[0].unit, equals('px/s'));
        expect(feat2d.tuning[1].value, equals('220'));
        expect(feat2d.tuning[1].unit, equals('px'));

        final feat3d = GodotSpecGuard.sanitizeFeatureSpec(
          FeatureSpec(
            id: 'f_scale_3d',
            code: 'F02',
            title: 'Move',
            goal: 'Move cleanly.',
            tuning: [
              EpicTuningParam(key: 'move_speed', value: '240', unit: 'px/s'),
              EpicTuningParam(key: 'dash_speed', value: '600', unit: 'uu/s'),
            ],
          ),
          dimension: GodotProjectDimension.dim3d,
        );
        expect(feat3d.tuning[0].value, equals('6'));
        expect(feat3d.tuning[0].unit, equals('m/s'));
        expect(feat3d.tuning[1].value, equals('6'));
        expect(feat3d.tuning[1].unit, equals('m/s'));

        final sb = GodotSparkPresets.byId('shellbreaker');
        final sbAs2d = ProjectConceptAgent.convertBlueprintDimension(
          sb,
          GodotProjectDimension.dim2d,
        );
        final wb2d = WorkbenchProvider(enableAutoLoad: false);
        wb2d.loadPresetSpark('shellbreaker');
        wb2d.setProjectDimension(GodotProjectDimension.dim2d);
        final fullMd2d = wb2d.buildFullProjectMarkdownExport().content;
        expect(fullMd2d, isNot(contains('CharacterBody3D')));
        expect(fullMd2d, isNot(contains('SpringArm3D')));
        expect(fullMd2d, isNot(contains('m/s')));
        expect(sbAs2d.initialEpics.first.inScope.join(' '), contains('px'));

        final ek = GodotSparkPresets.byId('emberkeep');
        final ekAs3d = ProjectConceptAgent.convertBlueprintDimension(
          ek,
          GodotProjectDimension.dim3d,
        );
        expect(
          ekAs3d.initialEpics.first.features.first.tuning.first.unit,
          equals('m/s'),
        );
        expect(ekAs3d.initialEpics.first.goal, isNot(contains('CharacterBody2D')));
        expect(ekAs3d.initialEpics.first.goal, isNot(contains('px/s')));
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
  });
}
