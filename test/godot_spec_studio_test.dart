import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/agents/project_concept_agent.dart';
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
      '5. Stage 1 UI: Dimension 3D/2D toggle, 2D auto-detect on Spark, Raw ROOT_GODOT_CONTEXT.md & Approve -> Stage 2',
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

        await tester.enterText(
          find.byKey(const ValueKey('spark_prompt_input')),
          '2D pixel-art torch survival skirmisher with axe cleave',
        );
        await tester.tap(find.byKey(const ValueKey('draft_spark_btn')));
        await tester.pumpAndSettle();

        expect(wb.projectDimension, equals(GodotProjectDimension.dim2d));

        await tester.tap(find.byKey(const ValueKey('stage1_tab_raw')));
        await tester.pumpAndSettle();
        final rawFinder = find.byKey(const ValueKey('raw_root_godot_context_text'));
        expect(rawFinder, findsOneWidget);
        expect(
          tester.widget<SelectableText>(rawFinder).data,
          contains('Godot 4 2D (.tscn + GDScript .gd)'),
        );

        // Toggle explicitly back to 3D and see context update immediately
        await tester.tap(find.byKey(const ValueKey('stage1_dim_3d')));
        await tester.pumpAndSettle();
        expect(wb.projectDimension, equals(GodotProjectDimension.dim3d));
        expect(
          tester.widget<SelectableText>(rawFinder).data,
          contains('Godot 4 3D (.tscn + GDScript .gd)'),
        );

        await tester.tap(find.byKey(const ValueKey('approve_launch_workbench_btn')));
        await tester.pumpAndSettle();

        expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);
        expect(find.textContaining('Exact Godot Build Context'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Stage 2 UI: Live @export tuning edit, Flag [FIX] revision switch, and Pass Epic advance',
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

        // Live tuning edit updates Godot context immediately
        await tester.ensureVisible(
          find.byKey(ValueKey('tuning_input_${e01.id}_0')),
        );
        await tester.enterText(
          find.byKey(ValueKey('tuning_input_${e01.id}_0')),
          '8.5',
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          wb.activeEpicGodotContext(wb.selectedEpicSpec!),
          contains('- move_speed: 8.5 m/s [float]'),
        );

        // Flag [FIX] switches mode to FOCUSED PLAYTEST REVISION PASS
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

        expect(wb.selectedEpicSpec!.openFixesCount, equals(1));
        expect(
          wb.activeEpicGodotContext(wb.selectedEpicSpec!),
          contains('FOCUSED PLAYTEST REVISION PASS (1 OPEN [FIX])'),
        );

        // Pass Epic resolves fixes, marks all checks passed, and advances to E02
        final passBtn = find.byKey(const ValueKey('pass_epic_btn'));
        await tester.ensureVisible(passBtn);
        await tester.tap(passBtn);
        await tester.pumpAndSettle();
        expect(wb.selectedEpicSpec!.code, equals('E02'));
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
  });
}
