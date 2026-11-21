import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/constants/tiers.dart';
import 'package:layers_agentic/main.dart';
import 'package:layers_agentic/models/epic_spec.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/release_workbench_screen.dart';
import 'package:layers_agentic/services/firestore_vault_service.dart';
import 'package:layers_agentic/services/local_vault_service.dart';
import 'package:layers_agentic/services/storage/vault_storage_interface.dart';
import 'package:layers_agentic/theme/app_theme.dart';

void main() {
  group('Platform, Vault, Auth, Invite & Model Failover Regression Suite', () {
    test(
      'initVault() auto-migrates legacy gemini-flash-latest & HIGH settings to gemini-4-hydrogen + LOW',
      () async {
        final fakeBackend = _MemoryVaultStorageBackend(
          const VaultLoadResult(
            documents: {},
            activeDocumentId: '',
            modelName: 'gemini-flash-latest',
            planningModel: 'gemini-3.8-flash',
            thinkingLevel: 'HIGH',
          ),
        );
        final prevBackend = LocalVaultService.testBackendOverride;
        LocalVaultService.testBackendOverride = fakeBackend;
        try {
          final provider = WorkbenchProvider(enableAutoLoad: false);
          await provider.initVault();

          expect(
            provider.conversationModel,
            equals(GeminiAgentClient.pinnedLiveFlashModel),
          );
          expect(
            provider.planningModel,
            equals(GeminiAgentClient.pinnedLiveFlashModel),
          );
          expect(provider.thinkingLevel, equals('LOW'));
          expect(fakeBackend.saveSettingsCount, greaterThanOrEqualTo(1));
          expect(
            fakeBackend.lastSavedModelName,
            equals(GeminiAgentClient.pinnedLiveFlashModel),
          );
          expect(
            fakeBackend.lastSavedPlanningModel,
            equals(GeminiAgentClient.pinnedLiveFlashModel),
          );
          expect(fakeBackend.lastSavedThinkingLevel, equals('LOW'));
        } finally {
          LocalVaultService.testBackendOverride = prevBackend;
        }
      },
    );

    testWidgets(
      'GeminiAgentClient tries gemini-4-hydrogen first with thinkingLevel LOW, surfaces fallback reason, and recovers on 200',
      (tester) async {
        final prevMock = GeminiAgentClient.testMockResponder;
        final prevHttp = GeminiAgentClient.testHttpPost;
        final prevDelay = GeminiAgentClient.testBaseRetryDelay;
        GeminiAgentClient.resetCapabilityCacheForTest();
        GeminiAgentClient.testMockResponder = null;
        GeminiAgentClient.testBaseRetryDelay = Duration.zero;

        bool failHydrogen = true;
        final requestedUrls = <String>[];
        final capturedBodies = <Map<String, dynamic>>[];

        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
          requestedUrls.add(uri.toString());
          if (body is String && body.isNotEmpty) {
            capturedBodies.add(jsonDecode(body) as Map<String, dynamic>);
          }
          if (failHydrogen &&
              uri.toString().contains(GeminiAgentClient.pinnedLiveFlashModel)) {
            return http.Response(
              '{"error":{"message":"proxy model policy blocked"}}',
              403,
            );
          }
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"ok": true}'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        };

        try {
          final fallbackRes = await GeminiAgentClient.generateJson(
            prompt: 'Ping Hydrogen first',
            apiKey: 'test-key-1234',
            preferredModel: GeminiAgentClient.fallbackFlashModel,
            thinkingLevel: 'LOW',
          );

          expect(fallbackRes, isNotNull);
          expect(fallbackRes!['ok'], isTrue);
          expect(
            requestedUrls.first,
            contains('models/${GeminiAgentClient.pinnedLiveFlashModel}:'),
          );
          expect(
            requestedUrls.last,
            contains('models/${GeminiAgentClient.fallbackFlashModel}:'),
          );
          final hydrogenGenCfg =
              capturedBodies.first['generationConfig'] as Map<String, dynamic>;
          expect(
            hydrogenGenCfg['thinkingConfig'],
            equals({'thinkingLevel': 'LOW'}),
          );
          expect(hydrogenGenCfg.containsKey('temperature'), isFalse);
          expect(GeminiAgentClient.lastFallbackReason, contains('HTTP 403'));

          tester.view.physicalSize = const Size(1400, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final provider = WorkbenchProvider(enableAutoLoad: false);
          expect(
            provider.activeModelIndicatorLabel,
            equals('⚡ Flash (Fallback)'),
          );
          expect(
            provider.aiFallbackReason,
            equals(GeminiAgentClient.lastFallbackReason),
          );

          await tester.pumpWidget(LayersAgenticApp(provider: provider));
          await tester.pumpAndSettle();

          final pillFinder = find.byKey(
            const ValueKey('active_model_indicator_pill'),
          );
          expect(pillFinder, findsOneWidget);
          final tooltip = tester.widget<Tooltip>(
            find.ancestor(of: pillFinder, matching: find.byType(Tooltip)).first,
          );
          expect(tooltip.message, contains('Fallback reason:'));
          expect(tooltip.message, contains('HTTP 403'));

          failHydrogen = false;
          final recoveryRes = await GeminiAgentClient.generateJson(
            prompt: 'Ping Hydrogen recovery',
            apiKey: 'test-key-1234',
            preferredModel: GeminiAgentClient.fallbackFlashModel,
            thinkingLevel: 'LOW',
          );
          expect(recoveryRes, isNotNull);
          expect(recoveryRes!['ok'], isTrue);
          expect(GeminiAgentClient.lastFallbackReason, isNull);
          expect(provider.aiFallbackReason, isNull);
          expect(provider.activeModelIndicatorLabel, equals('⚡ Hydrogen'));
        } finally {
          GeminiAgentClient.testMockResponder = prevMock;
          GeminiAgentClient.testHttpPost = prevHttp;
          GeminiAgentClient.testBaseRetryDelay = prevDelay;
          GeminiAgentClient.resetCapabilityCacheForTest();
        }
      },
    );

    testWidgets(
      'Token Usage Tracker computes \$1.50/1M input + \$7.50/1M output and resets to 0',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        GeminiAgentClient.resetUsage();
        addTearDown(GeminiAgentClient.resetUsage);

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.recordTokenUsage(
          inputTokens: 1000000,
          outputTokens: 1000000,
          thinkingTokens: 250000,
        );

        // $1.50 input + $7.50 output = $9.00
        expect(wb.totalEstimatedCostUsd, closeTo(9.0, 0.0001));
        expect(wb.tokenUsageCompactLabel, contains('\$9.00'));

        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('token_usage_tracker_pill')),
          findsOneWidget,
        );

        wb.resetTokenUsage();
        await tester.pumpAndSettle();
        expect(wb.totalEstimatedCostUsd, equals(0.0));
        expect(wb.tokenUsageCompactLabel, equals('0 tok · \$0.000'));
      },
    );

    test(
      'Round 1/10: bindHostedProxyAuth, thoughtsTokenCount billing, patch_* unwrap, pendingInvites invited & fast 404/timeout failover',
      () async {
        final prevIsAuth = GeminiAgentClient.isProxyAuthenticated;
        final prevTokenProvider = GeminiAgentClient.authTokenProvider;
        final prevHttpPost = GeminiAgentClient.testHttpPost;
        final prevMockResponder = GeminiAgentClient.testMockResponder;
        final prevProxyOverride = GeminiAgentClient.proxyBaseUrlOverride;
        final prevDelay = GeminiAgentClient.testBaseRetryDelay;
        GeminiAgentClient.resetUsage();
        GeminiAgentClient.resetCapabilityCacheForTest();
        addTearDown(GeminiAgentClient.resetUsage);

        try {
          GeminiAgentClient.testMockResponder = null;
          GeminiAgentClient.testBaseRetryDelay = Duration.zero;
          GeminiAgentClient.proxyBaseUrlOverride =
              'https://proxy.example.com/geminiProxy';

          final wb = WorkbenchProvider(enableAutoLoad: false);
          wb.setAiAccessRecordsForTest(
            const [
              AiAccessRecord(
                email: 'approved@studio.dev',
                status: 'approved',
              ),
              AiAccessRecord(
                email: 'teammate@studio.dev',
                status: 'invited',
              ),
            ],
            overrideEmail: 'approved@studio.dev',
          );
          expect(wb.pendingInvites.length, equals(1));
          expect(wb.pendingInvites.first.email, equals('teammate@studio.dev'));

          wb.bindHostedProxyAuth(
            tokenProvider: ({bool forceRefresh = false}) async => 'id-tok-xyz',
          );
          expect(GeminiAgentClient.canUseAuthenticatedProxy, isTrue);
          expect(GeminiAgentClient.hasKey(''), isTrue);

          Uri? capturedUri;
          Map<String, String>? capturedHeaders;
          GeminiAgentClient.testHttpPost = (
            uri, {
            headers,
            body,
          }) async {
            capturedUri = uri;
            capturedHeaders = headers;
            return http.Response(
              jsonEncode({
                'usageMetadata': {
                  'promptTokenCount': 800,
                  'toolUsePromptTokenCount': 200,
                  'candidatesTokenCount': 400,
                  'thoughtsTokenCount': 600,
                },
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {
                          'text':
                              '{"patch_godot_root_spec": {"args": {"gameTitle": "SHELL"}}}',
                        },
                      ],
                    },
                  },
                ],
              }),
              200,
            );
          };

          final patchRes = await GeminiAgentClient.generateJson(
            prompt: 'patch test',
            apiKey: '',
          );
          expect(
            capturedUri.toString(),
            equals(
              'https://proxy.example.com/geminiProxy/v1beta/models/gemini-4-hydrogen:generateContent',
            ),
          );
          expect(capturedHeaders?['Authorization'], equals('Bearer id-tok-xyz'));
          expect(capturedHeaders?.containsKey('x-goog-api-key'), isFalse);
          expect(patchRes, equals({'gameTitle': 'SHELL'}));
          expect(GeminiAgentClient.totalInputTokens, equals(1000));
          expect(GeminiAgentClient.totalOutputTokens, equals(1000));
          expect(GeminiAgentClient.totalThinkingTokens, equals(600));
          expect(GeminiAgentClient.totalEstimatedCostUsd, closeTo(0.009, 1e-6));

          // 404 on gemini-4-hydrogen must fail over immediately without same-model JSON retry
          final attemptedModels = <String>[];
          GeminiAgentClient.testHttpPost = (
            uri, {
            headers,
            body,
          }) async {
            final urlStr = uri.toString();
            if (urlStr.contains('gemini-4-hydrogen')) {
              attemptedModels.add('gemini-4-hydrogen');
              return http.Response('{"error":{"message":"Not found"}}', 404);
            }
            attemptedModels.add('gemini-flash-latest');
            return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': '{"ok": true}'},
                      ],
                    },
                  },
                ],
              }),
              200,
            );
          };

          final failoverRes = await GeminiAgentClient.generateJson(
            prompt: 'tool call 404 failover',
            apiKey: '',
            functionDeclarations: [
              {
                'name': 'patch_godot_root_spec',
                'parameters': {'type': 'object'},
              },
            ],
          );
          expect(failoverRes, equals({'ok': true}));
          expect(
            attemptedModels,
            equals(['gemini-4-hydrogen', 'gemini-flash-latest']),
          );

          // TimeoutException populates lastErrorStatus and resets cleanly on HTTP 200
          GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
            throw TimeoutException('timed out');
          };
          final timedOutRes = await GeminiAgentClient.generateJson(
            prompt: 'timeout test',
            apiKey: '',
          );
          expect(timedOutRes, isNull);
          expect(GeminiAgentClient.lastErrorStatus, isNotNull);
          expect(
            GeminiAgentClient.lastErrorStatus!,
            contains('TimeoutException'),
          );

          GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
            return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': '{"recovered": true}'},
                      ],
                    },
                  },
                ],
              }),
              200,
            );
          };
          final okAfterTimeout = await GeminiAgentClient.generateJson(
            prompt: 'recover test',
            apiKey: '',
          );
          expect(okAfterTimeout, equals({'recovered': true}));
          expect(GeminiAgentClient.lastErrorStatus, isNull);
        } finally {
          GeminiAgentClient.isProxyAuthenticated = prevIsAuth;
          GeminiAgentClient.authTokenProvider = prevTokenProvider;
          GeminiAgentClient.testHttpPost = prevHttpPost;
          GeminiAgentClient.testMockResponder = prevMockResponder;
          GeminiAgentClient.proxyBaseUrlOverride = prevProxyOverride;
          GeminiAgentClient.testBaseRetryDelay = prevDelay;
          GeminiAgentClient.lastErrorStatus = null;
          GeminiAgentClient.resetCapabilityCacheForTest();
        }
      },
    );

    test(
      'Multi-project Vault lifecycle: create, rename, duplicate, export, collision-safe import (ignoring legacy feature/task docs) & delete',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final projA = wb.approveRootSpecAndLaunchWorkbench() != null
            ? wb.activeProjectId!
            : wb.activeProjectId!;

        wb.renameProject(projA, 'Shellbreaker Renamed');
        expect(wb.documents[projA]?.title, equals('Shellbreaker Renamed'));
        expect(wb.conceptDraft?.gameTitle, equals('SHELLBREAKER RENAMED'));

        final exportedJson = wb.exportProjectToJson(projA);
        final decodedExport = jsonDecode(exportedJson) as Map<String, dynamic>;
        expect(decodedExport['format'], equals('layers-agentic-project-v3'));

        // Inject a legacy feature doc inside the JSON bundle to confirm import ignores it
        final legacyBundle = Map<String, dynamic>.from(decodedExport);
        final docList = List<dynamic>.from(legacyBundle['documents'] as List);
        docList.add({
          'id': 'legacy_feat_99',
          'title': 'Legacy Feature',
          'tier': 'feature',
          'childrenIds': [],
          'sections': {},
        });
        legacyBundle['documents'] = docList;

        final importedProjId = wb.importProjectFromJson(
          jsonEncode(legacyBundle),
        );
        expect(importedProjId, isNotNull);
        expect(importedProjId, isNot(equals(projA)));
        expect(
          wb.documents[importedProjId]?.title,
          equals('Shellbreaker Renamed (Imported)'),
        );
        expect(
          wb.documents.values.any((d) => d.title == 'Legacy Feature'),
          isFalse,
        );

        final dupId = wb.duplicateProject(importedProjId!);
        expect(dupId, isNotNull);
        expect(
          wb.documents[dupId]?.title,
          equals('Shellbreaker Renamed (Imported) (Copy)'),
        );

        final countBeforeDelete = wb.savedProjects.length;
        wb.deleteProject(dupId!);
        expect(wb.savedProjects.length, equals(countBeforeDelete - 1));
      },
    );

    test(
      'Deep-link (?project=&epic=) and shouldPreferRemoteDocumentOnSync (last_godot_sync_ms & Playtest checks)',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();
        final p1 = wb.activeProjectId!;
        final targetE02 = wb.activeReleaseEpics[1];

        wb.createNewProject();
        expect(wb.activeProjectId, isNot(equals(p1)));

        wb.applyDeepLinkParams({'project': p1, 'epic': targetE02.id});
        expect(wb.activeProjectId, equals(p1));
        expect(wb.selectedEpicId, equals(targetE02.id));
        expect(wb.currentStage, equals(WorkbenchStage.releaseWorkbench));

        // Epic-code deep-link (`?epic=E02` without `project`)
        wb.createNewProject();
        expect(wb.activeProjectId, isNot(equals(p1)));
        wb.applyDeepLinkParams({'epic': 'E02'});
        expect(wb.activeProjectId, equals(p1));
        expect(wb.selectedEpicId, equals(targetE02.id));
        expect(wb.currentStage, equals(WorkbenchStage.releaseWorkbench));

        // Cloud merge conflict test: newer `last_godot_sync_ms` wins
        final localEpic = wb.documents[targetE02.id]!.copyWith(
          sections: {
            ...wb.documents[targetE02.id]!.sections,
            'updated_at_ms': '1000',
          },
        );
        final remoteEpic = wb.documents[targetE02.id]!.copyWith(
          sections: {
            ...wb.documents[targetE02.id]!.sections,
            'updated_at_ms': '1000',
            'last_godot_sync_ms': '5000',
          },
        );
        expect(shouldPreferRemoteDocumentOnSync(localEpic, remoteEpic), isTrue);

        // Equal timestamps: completed Playtest checks break ties
        final tiedRemote = remoteEpic.copyWith(
          isCompleted: true,
          sections: {
            ...remoteEpic.sections,
            'last_godot_sync_ms': '1000',
          },
        );
        final tiedLocal = localEpic.copyWith(
          isCompleted: false,
          sections: {
            ...localEpic.sections,
            'last_godot_sync_ms': '1000',
          },
        );
        expect(shouldPreferRemoteDocumentOnSync(tiedLocal, tiedRemote), isTrue);

        // Equal timestamps: Godot `[FIX]` log beats 0-fix local doc; live snapshot beats empty Project doc
        final fixSpec = EpicSpec.fromDocument(tiedLocal)
          ..fixes.add(EpicPieFix(id: 'fx_live', text: 'Dash clips stair ramp'));
        final remoteWithFix = fixSpec.applyToDocument(tiedLocal).copyWith(
          sections: {
            ...fixSpec.applyToDocument(tiedLocal).sections,
            'updated_at_ms': '1000',
            'last_godot_sync_ms': '1000',
          },
        );
        expect(shouldPreferRemoteDocumentOnSync(tiedLocal, remoteWithFix), isTrue);

        final localProj = wb.documents[p1]!.copyWith(
          sections: {
            ...wb.documents[p1]!.sections,
            'updated_at_ms': '1000',
          },
        );
        final remoteProjWithCtx = localProj.copyWith(
          sections: {
            ...localProj.sections,
            'godot_live_context_json': '{"project_name":"ShellbreakerGodot"}',
          },
        );
        expect(
          shouldPreferRemoteDocumentOnSync(localProj, remoteProjWithCtx),
          isTrue,
        );

        // Real-time snapshot sync refreshes currently open active project & Epic selection
        final e01 = wb.activeReleaseEpics.first;
        wb.selectEpic(e01.id);
        expect(wb.selectedEpicId, equals(e01.id));

        final remoteE01Spec = EpicSpec.fromDocument(wb.documents[e01.id]!);
        remoteE01Spec.tuning.first.value = '999';
        remoteE01Spec.lifecycle = EpicLifecycle.stable;
        for (final chk in remoteE01Spec.checks) {
          chk.passed = true;
        }
        final remoteDocs = <String, TierDocument>{
          for (final entry in wb.documents.entries) entry.key: entry.value,
        };
        remoteDocs[e01.id] = remoteE01Spec.applyToDocument(wb.documents[e01.id]!);
        remoteDocs[p1] = wb.documents[p1]!.copyWith(
          sections: {
            ...wb.documents[p1]!.sections,
            'selected_epic_id': targetE02.id,
            'godot_live_context_json': '{"project_name":"ShellbreakerGodot"}',
          },
        );

        expect(wb.applyRemoteDocumentSnapshot(remoteDocs), isTrue);
        expect(wb.selectedEpicId, equals(targetE02.id));
        expect(wb.activeReleaseEpics.first.tuning.first.value, equals('999'));
        expect(
          wb.latestLiveGodotContext?['project_name'],
          equals('ShellbreakerGodot'),
        );
      },
    );

    testWidgets(
      'Invite-only landing overlay & Admin Team Invites dialog render cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.setPendingUrlInviteForTest(
          inviteToken: 'tok_abc123',
          invitedEmail: 'teammate@studio.dev',
        );

        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('invite_acceptance_overlay')),
          findsOneWidget,
        );
        expect(find.textContaining('teammate@studio.dev'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('dismiss_invite_overlay_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('invite_acceptance_overlay')),
          findsNothing,
        );

        // Admin user sees + Invite button and can open Team Invites Dialog
        wb.setAiAccessRecordsForTest(
          const [
            AiAccessRecord(email: 'pending@studio.dev', status: 'pending'),
            AiAccessRecord(email: 'approved@studio.dev', status: 'approved'),
          ],
          overrideEmail: WorkbenchProvider.ownerAdminEmail,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('team_invites_btn')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('team_invites_btn')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('team_invites_dialog')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'ReleaseWorkbenchScreen renders cleanly at 240x800 narrow viewport without throwing layout exceptions',
      (tester) async {
        tester.view.physicalSize = const Size(240, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('railjack');
        wb.approveRootSpecAndLaunchWorkbench();

        final prevOnError = FlutterError.onError;
        final nonOverflowErrors = <Object>[];
        FlutterError.onError = (FlutterErrorDetails details) {
          if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
            return;
          }
          nonOverflowErrors.add(details.exception);
          prevOnError?.call(details);
        };
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              home: Scaffold(
                body: ReleaseWorkbenchScreen(workbench: wb),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));

          expect(nonOverflowErrors, isEmpty);
          expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          FlutterError.onError = prevOnError;
        }
      },
    );

    test(
      'deleteProject cancels pending debounced tuning timers and clears cached Godot link tokens',
      () async {
        final fakeBackend = _MemoryVaultStorageBackend(
          const VaultLoadResult(documents: {}),
        );
        final prevBackend = LocalVaultService.testBackendOverride;
        final prevAuth = GeminiAgentClient.authTokenProvider;
        LocalVaultService.testBackendOverride = fakeBackend;

        final wb = WorkbenchProvider(enableAutoLoad: true);
        try {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          wb.loadPresetSpark('shellbreaker');
          wb.approveRootSpecAndLaunchWorkbench();
          final projId = wb.activeProjectId!;
          final epicId = wb.selectedEpicId!;

          wb.updateEpicTuningParam(epicId, 0, '777');
          wb.deleteProject(projId);

          await Future<void>.delayed(const Duration(milliseconds: 320));
          expect(fakeBackend.savedDocs.containsKey(epicId), isFalse);
          expect(fakeBackend.savedDocs.containsKey(projId), isFalse);
        } finally {
          wb.dispose();
          LocalVaultService.testBackendOverride = prevBackend;
          GeminiAgentClient.authTokenProvider = prevAuth;
        }
      },
    );
  });

  group('Round 4 — 4-Tier Provider State, Rollups & Progressive Baseline Lock', () {
    test(
      'Feature selection, Epic Domain Sheet, live @export tuning, [FIX] blocking, passFeature rollups & addFeatureSlice (3D + 2D)',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();

        final epics = wb.activeReleaseEpics;
        expect(epics.length, equals(3));
        final e01 = epics[0];
        final e02 = epics[1];

        // Launches onto first open Feature inside expanded E01 (F01 is already passed in preset -> F02)
        expect(wb.selectedEpicId, equals(e01.id));
        expect(wb.isEpicExpanded(e01.id), isTrue);
        expect(wb.isInspectingFeature, isTrue);
        expect(wb.selectedFeatureSpec?.code, equals('F02'));
        expect(
          wb.selectedBuildPrompt,
          contains('# ACTIVE FEATURE SPEC · F02 · Armored Claw Dash'),
        );

        // Toggle outliner expansion & open Epic Domain Sheet (selectedFeatureId == null)
        wb.toggleEpicExpanded(e01.id);
        expect(wb.isEpicExpanded(e01.id), isFalse);
        wb.selectEpic(e01.id);
        expect(wb.isEpicExpanded(e01.id), isTrue);
        expect(wb.selectedFeatureId, isNull);
        expect(wb.isInspectingEpicDomain, isTrue);
        expect(
          wb.selectedBuildPrompt,
          contains('# GODOT 4 EPIC ARCHITECTURE BRIEF · E01'),
        );

        // Select F02, mutate live @export tuning & add parameter
        wb.selectFeature(e01.id, 'sb_f02');
        expect(wb.selectedFeatureSpec?.code, equals('F02'));
        wb.updateFeatureTuningParam(e01.id, 'sb_f02', 0, '7.25');
        wb.addFeatureTuningParam(
          e01.id,
          'sb_f02',
          key: 'dash_trail_fade_s',
          value: '0.22',
          unit: 's',
        );
        expect(
          wb.selectedBuildPrompt,
          contains('@export var dash_distance: float = 7.25 # m'),
        );
        expect(
          wb.selectedBuildPrompt,
          contains('@export var dash_trail_fade_s: float = 0.22 # s'),
        );

        // Log [FIX] -> switches prompt mode & blocks passFeature even after checking Playtest Gate
        wb.flagFeatureFix(e01.id, 'sb_f02', 'Dash hitbox misses small crab edge');
        expect(wb.selectedFeatureSpec!.openFixesCount, equals(1));
        expect(
          wb.selectedBuildPrompt,
          contains('FOCUSED [FIX] PASS (1 OPEN [FIX])'),
        );
        final f02CheckId = wb.selectedFeatureSpec!.checks.first.id;
        wb.toggleFeatureCheck(e01.id, 'sb_f02', f02CheckId, true);
        expect(wb.passFeature(e01.id, 'sb_f02'), isFalse);

        // Resolve [FIX] -> passFeature passes F02, rolls up E01 (2/2 passed -> stable), and advances to E02 F03
        final f02FixId = wb.selectedFeatureSpec!.fixes.first.id;
        wb.resolveFeatureFix(e01.id, 'sb_f02', f02FixId);
        expect(wb.canPassFeature(wb.selectedFeatureSpec!), isTrue);
        expect(wb.passFeature(e01.id, 'sb_f02'), isTrue);

        final updatedE01 = wb.activeReleaseEpics[0];
        expect(updatedE01.isPassed, isTrue);
        expect(updatedE01.lifecycle, equals(EpicLifecycle.stable));
        final e01Rollup = wb.epicFeatureRollup(updatedE01);
        expect(e01Rollup.passed, equals(2));
        expect(e01Rollup.total, equals(2));

        expect(wb.selectedEpicId, equals(e02.id));
        expect(wb.isEpicExpanded(e02.id), isTrue);
        expect(wb.selectedFeatureSpec?.code, equals('F03'));

        // Reopen F02 -> E01 rolls back to active and rollup drops to 1/2
        wb.reopenFeature(e01.id, 'sb_f02');
        final reopenedE01 = wb.activeReleaseEpics[0];
        expect(reopenedE01.isPassed, isFalse);
        expect(wb.epicFeatureRollup(reopenedE01).passed, equals(1));

        // Add Feature slice on E01 -> gets sequential next code F07 & 3D m default unit
        final added3d = wb.addFeatureSlice(
          e01.id,
          title: 'Dash Wall Bounce',
          goal: 'Ricochet gently when dashing diagonally into stone walls.',
        );
        expect(added3d, isNotNull);
        expect(added3d!.code, equals('F07'));
        expect(added3d.tuning.first.unit, equals('m'));
        expect(wb.selectedFeatureId, equals(added3d.id));
        expect(wb.epicFeatureRollup(wb.activeReleaseEpics[0]).total, equals(3));

        // 2D preset (emberkeep) addFeatureSlice seeds px unit
        wb.createNewProject();
        wb.loadPresetSpark('emberkeep');
        wb.approveRootSpecAndLaunchWorkbench();
        final ekE01 = wb.activeReleaseEpics.first;
        final added2d = wb.addFeatureSlice(
          ekE01.id,
          title: 'Torch Dash Burst',
          goal: 'Spark bright ember ring along 2D dash vector.',
        );
        expect(added2d, isNotNull);
        expect(added2d!.tuning.first.unit, equals('px'));
      },
    );

    test(
      'Progressive v0.2 attachment, locked [v0.1] baseline guard, Stage 1 reconciliation & selectedFeatureId persistence',
      () async {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final v01Id = wb.approveRootSpecAndLaunchWorkbench()!;

        // Complete v0.1 release cleanly
        for (final ep in wb.epicsForRelease(v01Id)) {
          wb.passActiveEpic(ep.id);
        }
        expect(wb.isActiveReleaseComplete, isTrue);

        // Open v0.2 Progressive Planner, confirm F07 candidate is toggleable & committed into existing E01
        final draft = await wb.openProgressiveReleaseCopilot();
        expect(draft, isNotNull);
        final v02F07 = draft!.candidateNewFeaturesByLineageKey['e01']!.first;
        expect(wb.isProgressiveNewFeatureChosen(v02F07.id), isTrue);
        wb.toggleProgressiveNewFeature('e01', v02F07.id);
        expect(wb.isProgressiveNewFeatureChosen(v02F07.id), isFalse);
        wb.toggleProgressiveNewFeature('e01', v02F07.id);
        expect(wb.isProgressiveNewFeatureChosen(v02F07.id), isTrue);

        final v02Id = wb.commitProgressiveReleaseDraft()!;
        final v02Epics = wb.epicsForRelease(v02Id);
        // Zero duplicated Epic cards: E01 stays single, holding F01 (locked baseline), F02 (+DELTA), F07 (+NEW)
        expect(v02Epics.where((e) => e.lineageKey == 'e01').length, equals(1));
        final v02E01 = v02Epics.firstWhere((e) => e.lineageKey == 'e01');
        expect(v02E01.lifecycle, equals(EpicLifecycle.upgrading));
        final v02Features = wb.visibleFeaturesForEpic(v02E01);
        expect(v02Features.map((f) => f.code), containsAll(['F01', 'F02', 'F07']));

        final f01 = v02Features.firstWhere((f) => f.code == 'F01');
        final f02 = v02Features.firstWhere((f) => f.code == 'F02');
        final f07 = v02Features.firstWhere((f) => f.code == 'F07');

        // Locked [v0.1] baseline guard on F01 in v0.2 rejects mutations
        wb.selectFeature(v02E01.id, f01.id);
        expect(wb.isSelectedFeatureLockedBaseline, isTrue);
        final beforeMoveSpeed = f01.tuning.first.value;
        wb.updateFeatureTuningParam(v02E01.id, f01.id, 0, '99.0');
        wb.toggleFeatureCheck(v02E01.id, f01.id, f01.checks.first.id, false);
        wb.flagFeatureFix(v02E01.id, f01.id, 'Should be blocked in v0.2');
        wb.reopenFeature(v02E01.id, f01.id);
        final f01After = wb
            .visibleFeaturesForEpic(wb.activeReleaseEpics.first)
            .firstWhere((f) => f.code == 'F01');
        expect(f01After.tuning.first.value, equals(beforeMoveSpeed));
        expect(f01After.checks.first.passed, isTrue);
        expect(f01After.openFixes, isEmpty);
        expect(f01After.status, equals(FeatureStatus.passed));

        // Open in v0.1 baseline jump unlocks editing for F01
        wb.openSelectedFeatureInBaselineRelease();
        expect(wb.activeReleaseVersionTag, equals('v0.1'));
        expect(wb.selectedFeatureSpec?.code, equals('F01'));
        expect(wb.isSelectedFeatureLockedBaseline, isFalse);

        // Return to v0.2, verify F02 (+DELTA) & F07 (+NEW) are editable, pass F02 -> advances to F07
        wb.selectActiveRelease(v02Id);
        wb.selectFeature(v02E01.id, f02.id);
        expect(wb.isSelectedFeatureLockedBaseline, isFalse);
        expect(f02.releaseDelta, isNotEmpty);
        for (final chk in f02.effectiveChecksForRelease('v0.2')) {
          wb.toggleFeatureCheck(v02E01.id, f02.id, chk.id, true);
        }
        expect(wb.passFeature(v02E01.id, f02.id), isTrue);
        expect(wb.selectedFeatureSpec?.id, equals(f07.id));

        // Verify selectedFeatureId persists across switchProject & export/import
        final p1 = wb.activeProjectId!;
        final exported = wb.exportProjectToJson(p1);
        final impId = wb.importProjectFromJson(exported)!;
        expect(wb.activeProjectId, equals(impId));
        expect(wb.activeReleaseVersionTag, equals('v0.2'));
        expect(wb.selectedFeatureSpec?.code, equals('F07'));

        wb.switchProject(p1);
        expect(wb.selectedFeatureSpec?.code, equals('F07'));

        // Stage 1 re-sync preserves existing Feature state & custom slices in v0.1
        wb.selectActiveRelease(v01Id);
        final v01E01 = wb.epicsForRelease(v01Id).first;
        wb.addFeatureSlice(
          v01E01.id,
          title: 'Custom Dash Cancels',
          goal: 'Preserve user slice across Stage 1 updates.',
        );
        wb.approveRootSpecAndLaunchWorkbench();
        final afterSyncE01 = wb.epicsForRelease(v01Id).first;
        expect(
          afterSyncE01.features.any((f) => f.title == 'Custom Dash Cancels'),
          isTrue,
        );
      },
    );
  });

  group('Round 5 — Stage 1 & Stage 2 4-Tier Workbench UI', () {
    testWidgets(
      'Expandable Epic->Feature outliner, Breadcrumbs, Epic Domain Sheet (+Add Slice) & Feature Spec Sheet (Cloud-only)',
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

        // Stage 1 §05 displays seeded v0.1 Feature slices inside E01
        expect(find.textContaining('F01 · 8-Way Walk'), findsOneWidget);
        expect(find.textContaining('F02 · Armored Claw Dash'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('approve_launch_workbench_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);

        final e01 = wb.activeReleaseEpics.first;
        expect(
          find.byKey(ValueKey('outliner_epic_${e01.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('outliner_epic_toggle_${e01.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('outliner_feature_sb_f01')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('outliner_feature_sb_f02')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('outliner_release_summary')),
          findsOneWidget,
        );

        // Clickable Breadcrumbs present in Stage 2
        expect(find.byKey(const ValueKey('crumb_project')), findsOneWidget);
        expect(find.byKey(const ValueKey('crumb_release')), findsOneWidget);
        expect(find.byKey(const ValueKey('crumb_epic')), findsOneWidget);
        expect(find.byKey(const ValueKey('crumb_feature')), findsOneWidget);

        // Tap Epic Breadcrumb -> opens non-overlapping Epic Domain Sheet
        await tester.tap(find.byKey(const ValueKey('crumb_epic')));
        await tester.pumpAndSettle();
        expect(wb.isInspectingEpicDomain, isTrue);
        expect(
          find.textContaining('Shared Scene & Script Ownership'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Shared State & Interrupt Rules'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Domain Out-of-Scope'),
          findsOneWidget,
        );
        expect(find.textContaining('Exposed Tuning'), findsNothing);
        expect(
          find.byKey(const ValueKey('epic_feature_card_sb_f02')),
          findsOneWidget,
        );

        // Add Feature Slice inline inside Epic Domain Sheet -> creates & selects F07
        await tester.ensureVisible(
          find.byKey(const ValueKey('show_add_feature_btn')),
        );
        await tester.tap(find.byKey(const ValueKey('show_add_feature_btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('new_feature_title_input')),
          'Wall Bounce Dash',
        );
        await tester.enterText(
          find.byKey(const ValueKey('new_feature_goal_input')),
          'Ricochet gently off arena walls.',
        );
        await tester.tap(
          find.byKey(const ValueKey('submit_add_feature_btn')),
        );
        await tester.pumpAndSettle();
        expect(wb.selectedFeatureSpec?.code, equals('F07'));
        expect(wb.selectedFeatureSpec?.title, equals('Wall Bounce Dash'));

        // Select F02 -> live tuning syncs to Cloud AI (zero local-AI prompt/copy UI)
        await tester.tap(find.byKey(const ValueKey('outliner_feature_sb_f02')));
        await tester.pumpAndSettle();
        expect(wb.selectedFeatureSpec?.code, equals('F02'));

        await tester.ensureVisible(
          find.byKey(const ValueKey('tuning_input_sb_f02_0')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('tuning_input_sb_f02_0')),
          '6.8',
        );
        await tester.pump(const Duration(milliseconds: 350));

        expect(
          wb.activeGodotSyncContext(),
          contains('@export var dash_distance: float = 6.8 # m'),
        );
        expect(find.text('Live-synced to Godot 4 Cloud AI'), findsOneWidget);
        expect(find.byKey(const ValueKey('stage2_tab_raw')), findsNothing);
        expect(find.byKey(const ValueKey('copy_build_prompt_btn')), findsNothing);
        expect(find.byKey(const ValueKey('ai_build_prompt_text')), findsNothing);

        // Log [FIX] -> Pass Feature blocked with hint -> resolve & check -> Pass advances to F07
        await tester.ensureVisible(
          find.byKey(const ValueKey('flag_fix_input')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('flag_fix_input')),
          'Dash hitbox edge clip',
        );
        await tester.tap(find.byKey(const ValueKey('flag_fix_btn')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('pass_feature_btn')),
        );
        await tester.tap(find.byKey(const ValueKey('pass_feature_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pass_gate_hint')), findsOneWidget);
        expect(wb.selectedFeatureSpec?.code, equals('F02'));

        final fxId = wb.selectedFeatureSpec!.fixes.first.id;
        await tester.ensureVisible(find.byKey(ValueKey('resolve_fix_$fxId')));
        await tester.tap(find.byKey(ValueKey('resolve_fix_$fxId')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('feature_check_sb_f02_c1')),
        );
        await tester.tap(
          find.byKey(const ValueKey('feature_check_sb_f02_c1')),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('pass_feature_btn')),
        );
        await tester.tap(find.byKey(const ValueKey('pass_feature_btn')));
        await tester.pumpAndSettle();
        expect(wb.selectedFeatureSpec?.code, equals('F07'));
      },
    );

    testWidgets(
      'Progressive Co-Pilot v0.2+ [+NEW] Feature checkboxes & locked [v0.1] baseline banner jump',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final v01Id = wb.approveRootSpecAndLaunchWorkbench()!;
        for (final ep in wb.epicsForRelease(v01Id)) {
          wb.passActiveEpic(ep.id);
        }

        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('plan_next_release_btn')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('copilot_new_feat_sb_f07_chain')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('copilot_commit_btn')));
        await tester.pumpAndSettle();

        expect(wb.activeReleaseVersionTag, equals('v0.2'));

        await tester.tap(find.byKey(const ValueKey('outliner_feature_sb_f01')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('locked_baseline_banner')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('pass_feature_btn')), findsNothing);

        await tester.tap(find.byKey(const ValueKey('open_in_baseline_btn')));
        await tester.pumpAndSettle();
        expect(wb.activeReleaseVersionTag, equals('v0.1'));
        expect(
          find.byKey(const ValueKey('locked_baseline_banner')),
          findsNothing,
        );
      },
    );
  });

  group('Round 6 — Exporters, Legacy Vault Migration & Sync Parity', () {
    test(
      'Legacy 3-tier vault migration & activeGodotSyncContext backwards compatibility',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        final legacyBundle = {
          'format': 'layers-agentic-project-v2',
          'documents': [
            {
              'id': 'legacy_proj_1',
              'title': 'LEGACY DRIFTER',
              'tier': 'project',
              'childrenIds': ['legacy_rel_1'],
              'sections': {
                'current_stage': 'releaseWorkbench',
                'active_release_id': 'legacy_rel_1',
                'selected_epic_id': 'legacy_ep_1',
                'concept_blueprint_json': jsonEncode({
                  'gameTitle': 'LEGACY DRIFTER',
                  'dimension': '3d',
                  'pitch': 'High-speed hover sprint across canyon plates',
                  'approved': true,
                }),
              },
            },
            {
              'id': 'legacy_rel_1',
              'title': 'v0.1 · Prototype',
              'tier': 'release',
              'parentId': 'legacy_proj_1',
              'childrenIds': ['legacy_ep_1'],
              'sections': {'release_version': 'v0.1'},
            },
            {
              'id': 'legacy_ep_1',
              'title': 'Hover Thruster Core',
              'tier': 'epic',
              'parentId': 'legacy_rel_1',
              'childrenIds': [],
              'sections': {
                'code': 'E01',
                'release_version': 'v0.1',
                'lifecycle': 'active',
                'epic_spec_json': jsonEncode({
                  'id': 'legacy_ep_1',
                  'code': 'E01',
                  'title': 'Hover Thruster Core',
                  'releaseVersion': 'v0.1',
                  'lifecycle': 'active',
                  'goal': 'Propel hover craft along canyon track.',
                  'links': ['Scene res://scenes/hover_craft.tscn'],
                  'levelStaging': 'res://scenes/canyon_proto.tscn: straight test lane',
                  'controls': [
                    {
                      'action': 'boost_dash',
                      'trigger': 'Just Pressed (Space)',
                      'rule': 'Surges forward 6.0 m cleanly',
                    },
                  ],
                  'tuning': [
                    {'key': 'cruise_speed', 'value': '18.0', 'unit': 'm/s'},
                  ],
                  'checks': [
                    {
                      'id': 'leg_c1',
                      'text': 'Hold W -> Hover craft cruises at 18.0 m/s',
                      'passed': true,
                    },
                  ],
                  'fixes': [
                    {'id': 'leg_fx1', 'text': 'Reduce ramp bounce', 'resolved': false},
                  ],
                }),
              },
            },
            {
              'id': 'legacy_stale_feat',
              'title': 'Legacy Standalone Feature Doc',
              'tier': 'feature',
              'parentId': 'legacy_ep_1',
              'childrenIds': [],
              'sections': {},
            },
            {
              'id': 'legacy_stale_task',
              'title': 'Legacy Standalone Task Doc',
              'tier': 'task',
              'parentId': 'legacy_stale_feat',
              'childrenIds': [],
              'sections': {},
            },
          ],
        };

        final impId = wb.importProjectFromJson(jsonEncode(legacyBundle));
        expect(impId, isNotNull);
        expect(
          wb.documents.values.where((d) => d.tier == TierType.feature),
          isEmpty,
        );
        expect(
          wb.documents.values.any(
            (d) => d.title.contains('Legacy Standalone'),
          ),
          isFalse,
        );

        final migratedEpic = wb.selectedEpicSpec!;
        expect(migratedEpic.features.length, equals(1));
        expect(migratedEpic.features.first.code, equals('F01'));
        expect(migratedEpic.features.first.tuning.first.key, equals('cruise_speed'));
        expect(migratedEpic.features.first.checks.first.passed, isTrue);
        expect(migratedEpic.features.first.openFixesCount, equals(1));
        expect(migratedEpic.sceneOwnership, isNotEmpty);

        // Legacy Cloud/Dock Epic payload remains intact for functions/index.js
        expect(
          wb.activeEpicGodotContext(migratedEpic),
          contains('ACTIVE EPIC SPEC · E01 · Hover Thruster Core'),
        );

        // Sync context adapts cleanly across Feature Sheet, Epic Domain Sheet & explicit empty-feature Epics
        expect(
          wb.activeGodotSyncContext(),
          contains('# ACTIVE FEATURE SPEC · F01 · Hover Thruster Core'),
        );
        wb.selectEpic(migratedEpic.id);
        expect(
          wb.activeGodotSyncContext(),
          contains('# GODOT 4 EPIC ARCHITECTURE BRIEF · E01'),
        );

        final explicitEmptyEpic = EpicSpec(
          id: 'explicit_empty',
          code: 'E02',
          title: 'Raw Dock Fallback',
          goal: 'Preserve legacy payload when features list is explicitly empty.',
        );
        expect(
          wb.activeGodotSyncContext(epicOverride: explicitEmptyEpic),
          contains('ACTIVE EPIC SPEC · E02 · Raw Dock Fallback'),
        );
      },
    );

    testWidgets(
      '4-tier Markdown exports (3D/2D) & Cloud-only global Shell Export menu',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        final v01Id = wb.approveRootSpecAndLaunchWorkbench()!;
        for (final ep in wb.epicsForRelease(v01Id)) {
          wb.passActiveEpic(ep.id);
        }
        await wb.openProgressiveReleaseCopilot();
        wb.commitProgressiveReleaseDraft();

        // Full project Markdown export (0 Task/Step noise)
        final fullExport = wb.buildFullProjectMarkdownExport();
        expect(fullExport.filename, equals('shellbreaker_project_spec.md'));
        expect(fullExport.content, contains('v0.1'));
        expect(fullExport.content, contains('v0.2'));
        expect(fullExport.content, isNot(contains('## Tasks')));
        expect(fullExport.content, isNot(contains('## Steps')));

        // Global Export menu keeps Godot Dock + Spec + Backup and excludes local-AI prompt items
        await tester.pumpWidget(LayersAgenticApp(provider: wb));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('global_export_spec_btn')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('export_active_prompt_item')),
          findsNothing,
        );
        expect(
          find.text('Export AI Agent Context (AGENTS.md)'),
          findsNothing,
        );
        expect(find.text('Connect Godot 4 Editor Plugin'), findsOneWidget);
        expect(find.text('Copy Full Project Spec (.md)'), findsOneWidget);
        expect(find.text('Export Project Vault (.layers.json)'), findsOneWidget);
        expect(find.text('Import Project Backup (.layers.json)'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 2D preset (emberkeep) exports px/px/s with zero 3D m/s leakage
        wb.createNewProject();
        wb.loadPresetSpark('emberkeep');
        wb.approveRootSpecAndLaunchWorkbench();
        final ekExport = wb.buildFullProjectMarkdownExport();
        expect(ekExport.filename, equals('ember_keep_project_spec.md'));
        expect(ekExport.content, contains('px/s'));
        expect(ekExport.content, isNot(contains('m/s')));
      },
    );

    test(
      '4-tier deep-link (?project=&epic=&feature=) & remote selected_feature_id Cloud sync',
      () {
        final wb = WorkbenchProvider(enableAutoLoad: false);
        wb.loadPresetSpark('shellbreaker');
        wb.approveRootSpecAndLaunchWorkbench();
        final p1 = wb.activeProjectId!;
        final e01 = wb.activeReleaseEpics.first;
        final f02 = e01.features.firstWhere((f) => f.code == 'F02');
        final f01 = e01.features.firstWhere((f) => f.code == 'F01');

        // Navigate away, then jump directly to E01/F02 via deep-link params
        wb.createNewProject();
        wb.applyDeepLinkParams({
          'project': p1,
          'epic': e01.id,
          'feature': f02.id,
        });
        expect(wb.activeProjectId, equals(p1));
        expect(wb.selectedEpicId, equals(e01.id));
        expect(wb.selectedFeatureId, equals(f02.id));

        // Incoming Cloud Firestore snapshot updates Feature tuning/checks + selected_feature_id
        final mutatedE01 = EpicSpec.fromDocument(wb.documents[e01.id]!);
        final mutatedF01 = mutatedE01.features.firstWhere((f) => f.id == f01.id);
        mutatedF01.tuning.first.value = '8.8';
        mutatedF01.checks.first.passed = true;

        final remoteDocs = <String, TierDocument>{
          for (final entry in wb.documents.entries) entry.key: entry.value,
        };
        remoteDocs[e01.id] = mutatedE01.applyToDocument(wb.documents[e01.id]!);
        remoteDocs[p1] = wb.documents[p1]!.copyWith(
          sections: {
            ...wb.documents[p1]!.sections,
            'selected_epic_id': e01.id,
            'selected_feature_id': f01.id,
          },
        );

        expect(wb.applyRemoteDocumentSnapshot(remoteDocs), isTrue);
        expect(wb.selectedEpicId, equals(e01.id));
        expect(wb.selectedFeatureId, equals(f01.id));
        expect(
          wb.selectedFeatureSpec?.tuning.first.value,
          equals('8.8'),
        );
      },
    );

    test(
      'Cloud Vault queues snapshots during in-flight writes/agent turns, merges newer remote Godot Epics in syncNowWithCloud, and preserves Stage 1 Undo, expanded Epics & +New Project intake',
      () async {
        final pushedDocs = <String, TierDocument>{};
        var writeGate = Completer<void>()..complete();
        final wb = WorkbenchProvider(enableAutoLoad: false)
          ..testOverrideUserUid = 'uid_cloud_sync_test'
          ..testOverrideUserEmail = WorkbenchProvider.ownerAdminEmail
          ..testCloudDocumentSaver = (uid, doc) async {
            pushedDocs[doc.id] = doc;
            if (!writeGate.isCompleted) {
              await writeGate.future;
            }
          };
        wb.loadPresetSpark('shellbreaker');
        // Push a Stage 1 undo entry so canUndoStage1 == true
        wb.setProjectDimension(GodotProjectDimension.dim2d);
        await Future<void>.delayed(Duration.zero);
        expect(wb.canUndoStage1, isTrue);

        // Same-project snapshot in Stage 1 preserves _stage1UndoStack
        final projId = wb.activeProjectId!;
        final snapSameStage1 = <String, TierDocument>{
          for (final entry in wb.documents.entries) entry.key: entry.value,
        };
        expect(wb.applyRemoteDocumentSnapshot(snapSameStage1), isTrue);
        expect(wb.canUndoStage1, isTrue);

        // Undo back to 3D and approve to enter Stage 2
        expect(wb.undoStage1Edit(), isTrue);
        wb.approveRootSpecAndLaunchWorkbench();
        await Future<void>.delayed(Duration.zero);
        final epics = wb.activeReleaseEpics;
        expect(epics.length, greaterThanOrEqualTo(2));
        final e01 = epics[0];
        final e02 = epics[1];
        wb.toggleEpicExpanded(e01.id, true);
        wb.toggleEpicExpanded(e02.id, true);
        expect(wb.expandedEpicIds.contains(e01.id), isTrue);
        expect(wb.expandedEpicIds.contains(e02.id), isTrue);

        // Stage 2 same-project snapshot retains all expanded Epics
        final mutatedViaRemote = EpicSpec.fromDocument(wb.documents[e01.id]!);
        mutatedViaRemote.features.first.tuning.first.value = '9.2';
        final stage2Snap = <String, TierDocument>{
          for (final entry in wb.documents.entries) entry.key: entry.value,
          e01.id: mutatedViaRemote.applyToDocument(wb.documents[e01.id]!),
        };
        expect(wb.applyRemoteDocumentSnapshot(stage2Snap), isTrue);
        expect(wb.expandedEpicIds.contains(e01.id), isTrue);
        expect(wb.expandedEpicIds.contains(e02.id), isTrue);
        expect(
          wb.documents[e01.id] != null &&
              EpicSpec.fromDocument(wb.documents[e01.id]!)
                      .features
                      .first
                      .tuning
                      .first
                      .value ==
                  '9.2',
          isTrue,
        );

        // 1) In-flight Cloud write queues remote snapshot and auto-applies when write finishes
        writeGate = Completer<void>();

        // Trigger _persistDocument via selectFeature -> _syncActiveProjectMetadata
        wb.selectFeature(e01.id, e01.features.first.id);

        final queuedE01 = EpicSpec.fromDocument(wb.documents[e01.id]!);
        queuedE01.features.first.tuning.first.value = '11.4';
        final futureTs =
            (DateTime.now().millisecondsSinceEpoch + 60000).toString();
        final queuedRemoteDoc = queuedE01.applyToDocument(wb.documents[e01.id]!);
        queuedRemoteDoc.sections['updated_at_ms'] = futureTs;
        queuedRemoteDoc.sections['last_godot_sync_ms'] = futureTs;
        final queuedSnap = <String, TierDocument>{
          for (final entry in wb.documents.entries) entry.key: entry.value,
          e01.id: queuedRemoteDoc,
        };

        // Blocked while writeGate is pending
        expect(wb.applyRemoteDocumentSnapshot(queuedSnap), isFalse);
        expect(
          EpicSpec.fromDocument(wb.documents[e01.id]!)
              .features
              .first
              .tuning
              .first
              .value,
          equals('9.2'),
        );

        // Completing the write flushes the deferred snapshot automatically
        writeGate.complete();
        await Future<void>.delayed(Duration.zero);
        expect(
          EpicSpec.fromDocument(wb.documents[e01.id]!)
              .features
              .first
              .tuning
              .first
              .value,
          equals('11.4'),
        );

        // 2) Agent busy queues remote snapshot and auto-applies when agent finishes
        wb.setAgentBusyForTest(true);
        final agentRemoteE01 = EpicSpec.fromDocument(wb.documents[e01.id]!);
        agentRemoteE01.features.first.tuning.first.value = '12.5';
        final laterTs =
            (DateTime.now().millisecondsSinceEpoch + 120000).toString();
        final agentRemoteDoc = agentRemoteE01.applyToDocument(
          wb.documents[e01.id]!,
        );
        agentRemoteDoc.sections['updated_at_ms'] = laterTs;
        agentRemoteDoc.sections['last_godot_sync_ms'] = laterTs;
        final agentSnap = <String, TierDocument>{
          for (final entry in wb.documents.entries) entry.key: entry.value,
          e01.id: agentRemoteDoc,
        };
        expect(wb.applyRemoteDocumentSnapshot(agentSnap), isFalse);
        expect(
          EpicSpec.fromDocument(wb.documents[e01.id]!)
              .features
              .first
              .tuning
              .first
              .value,
          equals('11.4'),
        );
        wb.setAgentBusyForTest(false);
        expect(
          EpicSpec.fromDocument(wb.documents[e01.id]!)
              .features
              .first
              .tuning
              .first
              .value,
          equals('12.5'),
        );

        // 3) syncNowWithCloud() adopts remote-newer Godot Dock Epic instead of overwriting Cloud
        final remoteWinnerE02 = EpicSpec.fromDocument(wb.documents[e02.id]!);
        remoteWinnerE02.features.first.checks.first.passed = true;
        final remoteWinnerDoc = remoteWinnerE02.applyToDocument(
          wb.documents[e02.id]!,
        );
        final godotNewerTs =
            (DateTime.now().millisecondsSinceEpoch + 240000).toString();
        remoteWinnerDoc.sections['updated_at_ms'] = godotNewerTs;
        remoteWinnerDoc.sections['last_godot_sync_ms'] = godotNewerTs;

        pushedDocs.clear();
        wb.testCloudDocumentsFetcher = (uid) async => <String, TierDocument>{
          for (final entry in wb.documents.entries) entry.key: entry.value,
          e02.id: remoteWinnerDoc,
        };
        await wb.syncNowWithCloud();
        expect(
          EpicSpec.fromDocument(wb.documents[e02.id]!)
              .features
              .first
              .checks
              .first
              .passed,
          isTrue,
        );
        expect(pushedDocs.containsKey(e02.id), isFalse);

        // 4) Unpersisted + New Project intake survives remote snapshots on other projects
        wb.createNewProject();
        final draftNewProjId = wb.activeProjectId!;
        expect(wb.documents.containsKey(draftNewProjId), isFalse);
        expect(wb.showingSparkPicker, isTrue);
        expect(wb.applyRemoteDocumentSnapshot(agentSnap), isTrue);
        expect(wb.activeProjectId, equals(draftNewProjId));
        expect(wb.showingSparkPicker, isTrue);
        expect(wb.activeProjectId, isNot(equals(projId)));
      },
    );
  });
}

class _MemoryVaultStorageBackend implements VaultStorageBackend {
  final VaultLoadResult seedResult;
  final Map<String, TierDocument> savedDocs = {};
  String? lastSavedModelName;
  String? lastSavedPlanningModel;
  String? lastSavedThinkingLevel;
  int saveSettingsCount = 0;

  _MemoryVaultStorageBackend(this.seedResult);

  @override
  Future<VaultLoadResult> loadVaultData() async => seedResult;

  @override
  Future<void> saveSettings({
    required String activeDocumentId,
    String? apiKey,
    String? modelName,
    String? planningModel,
    String? thinkingLevel,
    String? themeMode,
  }) async {
    saveSettingsCount++;
    lastSavedModelName = modelName;
    lastSavedPlanningModel = planningModel;
    lastSavedThinkingLevel = thinkingLevel;
  }

  @override
  Future<void> saveDocument(TierDocument doc) async {
    savedDocs[doc.id] = doc;
  }

  @override
  Future<void> deleteDocument(String id) async {
    savedDocs.remove(id);
  }
}
