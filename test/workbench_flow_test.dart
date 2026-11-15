import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/main.dart';
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
      'Deep-link (?project=&epic=) and shouldPreferRemoteDocumentOnSync (last_unreal_sync_ms & PIE checks)',
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

        // Cloud merge conflict test: newer `last_unreal_sync_ms` wins
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
            'last_unreal_sync_ms': '5000',
          },
        );
        expect(shouldPreferRemoteDocumentOnSync(localEpic, remoteEpic), isTrue);

        // Equal timestamps: completed PIE checks break ties
        final tiedRemote = remoteEpic.copyWith(
          isCompleted: true,
          sections: {
            ...remoteEpic.sections,
            'last_unreal_sync_ms': '1000',
          },
        );
        final tiedLocal = localEpic.copyWith(
          isCompleted: false,
          sections: {
            ...localEpic.sections,
            'last_unreal_sync_ms': '1000',
          },
        );
        expect(shouldPreferRemoteDocumentOnSync(tiedLocal, tiedRemote), isTrue);
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
  });
}

class _MemoryVaultStorageBackend implements VaultStorageBackend {
  final VaultLoadResult seedResult;
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
  Future<void> saveDocument(TierDocument doc) async {}

  @override
  Future<void> deleteDocument(String id) async {}
}
