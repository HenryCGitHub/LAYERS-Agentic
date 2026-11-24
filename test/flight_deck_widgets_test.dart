import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/agents/stage2_refine_agent.dart';
import 'package:layers_agentic/models/epic_spec.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/shell/studio_gdd_bar_widgets.dart';
import 'package:layers_agentic/screens/shell/studio_top_bar.dart';
import 'package:layers_agentic/screens/stage1/stage1_epic_preview_section.dart';
import 'package:layers_agentic/screens/workbench/feature_spec_sheet.dart';
import 'package:layers_agentic/screens/workbench/floating_ai_refine_dock.dart';
import 'package:layers_agentic/screens/workbench/stage2_inline_editors.dart';
import 'package:layers_agentic/theme/app_theme.dart';

void main() {
  group('1. Stage2RefineAgent unit tests', () {
    void registerClientReset() {
      GeminiAgentClient.resetCapabilityCacheForTest();
      GeminiAgentClient.resetUsage();
      GeminiAgentClient.testMockResponder = null;
      GeminiAgentClient.testBaseRetryDelay = Duration.zero;
      addTearDown(() {
        GeminiAgentClient.testHttpPost = null;
        GeminiAgentClient.testMockResponder = null;
        GeminiAgentClient.testBaseRetryDelay = null;
        GeminiAgentClient.resetCapabilityCacheForTest();
        GeminiAgentClient.resetUsage();
      });
    }

    test(
      'patch_unreal_epic_spec mocks Gemini HTTP, sanitizes UE5 scale/cuts, and tracks Hydrogen token usage',
      () async {
        registerClientReset();
        final requestedUris = <Uri>[];
        final capturedHeaders = <Map<String, String>>[];
        final capturedBodies = <Map<String, dynamic>>[];

        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
          requestedUris.add(uri);
          if (headers != null) capturedHeaders.add(headers);
          if (body is String && body.isNotEmpty) {
            capturedBodies.add(jsonDecode(body) as Map<String, dynamic>);
          }
          return http.Response(
            jsonEncode({
              'modelVersion': 'gemini-4-hydrogen-preview',
              'usageMetadata': {
                'promptTokenCount': 200,
                'toolUsePromptTokenCount': 40,
                'candidatesTokenCount': 80,
                'thoughtsTokenCount': 20,
              },
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'functionCall': {
                          'name': 'patch_unreal_epic_spec',
                          'args': {
                            'summary': 'Refine E01 arena dash at 6 m/s',
                            'changedSections': ['s01', 's02', 's03', 's04'],
                            'goal':
                                'Drive mech dash at 6.5 m/s in /Game/Maps/Lvl_ArenaProto.umap',
                            'inScope': ['- Dash impulse across 5 m gap'],
                            'doneWhen': ['Dash crosses 5 m gap cleanly in PIE'],
                            'sceneOwnership': [
                              {
                                'path': '/Game/Blueprints/BP_PlayerMech',
                                'role': 'Owns dash movement at 8 m/s',
                              },
                            ],
                            'stateFlow': [
                              'Idle',
                              'DashWindup',
                              'Dashing',
                              'Recover',
                            ],
                            'interruptRules': [
                              'Cancel dash on hitstun within 0.15 s',
                            ],
                            'outOfScope': ['Skill trees'],
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

        final wb = WorkbenchProvider(enableAutoLoad: false)
          ..loadPresetSpark('shellbreaker');
        final rootSpec = wb.conceptDraft!;
        final epic = rootSpec.initialEpics.first.deepCopy();

        final outcome = await Stage2RefineAgent.refineEpicSpec(
          rootSpec: rootSpec,
          epic: epic,
          instruction: 'Tighten dash speed and add hitstun interrupt',
          apiKey: 'AIzaTestStage2EpicKey',
          mode: UnrealArchitectureMode.blueprint,
        );

        expect(requestedUris, hasLength(1));
        expect(
          requestedUris.single.toString(),
          contains('models/gemini-4-hydrogen:generateContent'),
        );
        expect(
          capturedHeaders.single['x-goog-api-key'],
          equals('AIzaTestStage2EpicKey'),
        );
        final genConfig =
            capturedBodies.single['generationConfig'] as Map<String, dynamic>;
        expect(genConfig['thinkingConfig'], equals({'thinkingLevel': 'LOW'}));
        expect(genConfig.containsKey('temperature'), isFalse);

        final tools = capturedBodies.single['tools'] as List;
        final decls =
            (tools.first as Map<String, dynamic>)['functionDeclarations']
                as List;
        expect(
          (decls.first as Map<String, dynamic>)['name'],
          equals('patch_unreal_epic_spec'),
        );

        expect(outcome.usedFallback, isFalse);
        expect(outcome.errorMessage, isNull);
        expect(outcome.epic, isNotNull);
        expect(
          outcome.changedSections,
          containsAll(const ['s01', 's02', 's03', 's04']),
        );
        expect(outcome.summary, contains('600 cm/s'));

        final patched = outcome.epic!;
        expect(patched.goal, contains('650 cm/s'));
        expect(patched.inScope.single, equals('Dash impulse across 500 cm gap'));
        expect(patched.doneWhen.single, contains('500 cm'));
        expect(patched.sceneOwnership.single.role, contains('800 cm/s'));
        expect(
          patched.stateFlow,
          equals(const ['Idle', 'DashWindup', 'Dashing', 'Recover']),
        );
        expect(
          patched.interruptRules,
          equals(const ['Cancel dash on hitstun within 0.15 s']),
        );
        expect(patched.outOfScope.single, equals('No Skill trees'));

        expect(GeminiAgentClient.totalInputTokens, equals(240));
        expect(GeminiAgentClient.totalOutputTokens, equals(100));
        expect(GeminiAgentClient.totalThinkingTokens, equals(20));
        expect(
          GeminiAgentClient.totalEstimatedCostUsd,
          closeTo((240 * 1.50 + 100 * 7.50) / 1000000.0, 1e-9),
        );
        wb.dispose();
      },
    );

    test(
      'patch_unreal_feature_spec mocks Gemini HTTP, sanitizes UE5 controls/tuning, preserves passed checks, and tracks tokens',
      () async {
        registerClientReset();
        final capturedBodies = <Map<String, dynamic>>[];

        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
          if (body is String && body.isNotEmpty) {
            capturedBodies.add(jsonDecode(body) as Map<String, dynamic>);
          }
          return http.Response(
            jsonEncode({
              'modelVersion': 'gemini-4-hydrogen-preview',
              'usageMetadata': {
                'promptTokenCount': 300,
                'candidatesTokenCount': 120,
                'thoughtsTokenCount': 30,
              },
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'functionCall': {
                          'name': 'patch_unreal_feature_spec',
                          'args': {
                            'summary':
                                'Tune dash to 6 m and wire IA_ClawDash',
                            'changedSections': [
                              's01',
                              's02',
                              's03',
                              's04',
                              's05',
                            ],
                            'goal': 'Slide 6 m at 12 m/s cleanly',
                            'controls': [
                              {
                                'action': 'claw_dash',
                                'trigger': 'Pressed',
                                'rule': 'Impulse 12 m/s forward',
                              },
                            ],
                            'tuning': [
                              {
                                'key': 'dash_distance',
                                'value': '6',
                                'unit': 'm',
                              },
                              {
                                'key': 'move_speed',
                                'value': '400',
                                'unit': 'px/s',
                              },
                            ],
                            'cues': ['Thruster trail VFX across 4 m arc'],
                            'checks': [
                              'Press IA_Move -> Mech walks cleanly',
                              '- Press IA_ClawDash -> Mech dashes 6 m',
                            ],
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

        final wb = WorkbenchProvider(enableAutoLoad: false)
          ..loadPresetSpark('shellbreaker');
        final rootSpec = wb.conceptDraft!;
        final epic = rootSpec.initialEpics.first.deepCopy();
        final baseFeature = epic.features.first.deepCopy();
        baseFeature.checks = [
          EpicPieCheck(
            id: 'chk_keep',
            text: 'Press IA_Move -> Mech walks cleanly',
            passed: true,
          ),
        ];

        final outcome = await Stage2RefineAgent.refineFeatureSpec(
          rootSpec: rootSpec,
          epic: epic,
          feature: baseFeature,
          instruction: 'Extend dash to 6 m and bind claw dash',
          apiKey: 'AIzaTestStage2FeatKey',
        );

        final tools = capturedBodies.single['tools'] as List;
        final decls =
            (tools.first as Map<String, dynamic>)['functionDeclarations']
                as List;
        expect(
          (decls.first as Map<String, dynamic>)['name'],
          equals('patch_unreal_feature_spec'),
        );

        expect(outcome.usedFallback, isFalse);
        expect(outcome.errorMessage, isNull);
        expect(
          outcome.changedSections,
          containsAll(const ['s01', 's02', 's03', 's04', 's05']),
        );
        expect(outcome.summary, contains('600 cm'));

        final feat = outcome.feature!;
        expect(feat.goal, equals('Slide 600 cm at 1200 cm/s cleanly'));
        expect(feat.controls.single.action, equals('IA_ClawDash'));
        expect(feat.controls.single.rule, equals('Impulse 1200 cm/s forward'));
        expect(feat.tuning[0].key, equals('DashDistance'));
        expect(feat.tuning[0].value, equals('600'));
        expect(feat.tuning[0].unit, equals('cm'));
        expect(feat.tuning[1].key, equals('MoveSpeed'));
        expect(feat.tuning[1].value, equals('1000'));
        expect(feat.tuning[1].unit, equals('cm/s'));
        expect(feat.cues.single, equals('Thruster trail VFX across 400 cm arc'));

        expect(feat.checks, hasLength(2));
        expect(feat.checks[0].id, equals('chk_keep'));
        expect(feat.checks[0].passed, isTrue);
        expect(
          feat.checks[1].text,
          equals('Press IA_ClawDash -> Mech dashes 600 cm'),
        );
        expect(feat.checks[1].passed, isFalse);

        expect(GeminiAgentClient.totalInputTokens, equals(300));
        expect(GeminiAgentClient.totalOutputTokens, equals(150));
        expect(GeminiAgentClient.totalThinkingTokens, equals(30));
        expect(
          GeminiAgentClient.totalEstimatedCostUsd,
          closeTo((300 * 1.50 + 150 * 7.50) / 1000000.0, 1e-9),
        );
        wb.dispose();
      },
    );

    test(
      'deterministic offline fallback handles Epic and Feature refines without API key or HTTP calls',
      () async {
        registerClientReset();
        var httpCallCount = 0;
        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
          httpCallCount++;
          throw StateError('Offline fallback must not perform HTTP calls');
        };

        final wb = WorkbenchProvider(enableAutoLoad: false)
          ..loadPresetSpark('shellbreaker');
        final rootSpec = wb.conceptDraft!;
        final epic = rootSpec.initialEpics.first.deepCopy();
        final feature = epic.features.first.deepCopy();

        // Blank instruction returns original spec without fallback flag
        final emptyEpicOut = await Stage2RefineAgent.refineEpicSpec(
          rootSpec: rootSpec,
          epic: epic,
          instruction: '   ',
          apiKey: '',
        );
        expect(emptyEpicOut.usedFallback, isFalse);
        expect(emptyEpicOut.epic, same(epic));

        // Epic fallback branches: owner path, cut, stateFlow, interrupt rule, scope
        final ownerOut = await Stage2RefineAgent.refineEpicSpec(
          rootSpec: rootSpec,
          epic: epic,
          instruction: 'Own /Game/Blueprints/BP_HazardGrid',
          apiKey: '',
        );
        expect(ownerOut.usedFallback, isTrue);
        expect(ownerOut.changedSections, equals({'s02'}));
        expect(
          ownerOut.epic!.sceneOwnership
              .any((o) => o.path == '/Game/Blueprints/BP_HazardGrid'),
          isTrue,
        );

        final cutOut = await Stage2RefineAgent.refineEpicSpec(
          rootSpec: rootSpec,
          epic: epic,
          instruction: 'Cut coop matchmaking',
          apiKey: '',
        );
        expect(cutOut.usedFallback, isTrue);
        expect(cutOut.changedSections, equals({'s04'}));
        expect(cutOut.epic!.outOfScope, contains('No coop matchmaking'));

        final stateOut = await Stage2RefineAgent.refineEpicSpec(
          rootSpec: rootSpec,
          epic: epic,
          instruction: 'Idle -> Charge -> Release',
          apiKey: '',
        );
        expect(stateOut.usedFallback, isTrue);
        expect(stateOut.changedSections, equals({'s03'}));
        expect(
          stateOut.epic!.stateFlow,
          equals(const ['Idle', 'Charge', 'Release']),
        );

        final interruptOut = await Stage2RefineAgent.refineEpicSpec(
          rootSpec: rootSpec,
          epic: epic,
          instruction: 'Interrupt charge on stun',
          apiKey: '',
        );
        expect(interruptOut.usedFallback, isTrue);
        expect(interruptOut.changedSections, equals({'s03'}));
        expect(
          interruptOut.epic!.interruptRules,
          contains('Interrupt charge on stun'),
        );

        final scopeOut = await Stage2RefineAgent.refineEpicSpec(
          rootSpec: rootSpec,
          epic: epic,
          instruction: 'Track dash stamina recovery',
          apiKey: '',
        );
        expect(scopeOut.usedFallback, isTrue);
        expect(scopeOut.changedSections, equals({'s01'}));
        expect(scopeOut.epic!.inScope, contains('Track dash stamina recovery'));

        // Feature fallback branches: tuning, PIE check, IA_* control, cue, scope
        final tuneOut = await Stage2RefineAgent.refineFeatureSpec(
          rootSpec: rootSpec,
          epic: epic,
          feature: feature,
          instruction: 'Set BurstDistance to 5 m',
          apiKey: '',
        );
        expect(tuneOut.usedFallback, isTrue);
        expect(tuneOut.changedSections, equals({'s03'}));
        expect(
          tuneOut.feature!.tuning.any(
            (t) =>
                t.key == 'BurstDistance' && t.value == '500' && t.unit == 'cm',
          ),
          isTrue,
        );

        final checkOut = await Stage2RefineAgent.refineFeatureSpec(
          rootSpec: rootSpec,
          epic: epic,
          feature: feature,
          instruction: 'Press IA_Parry -> Shield reflects projectile',
          apiKey: '',
        );
        expect(checkOut.usedFallback, isTrue);
        expect(checkOut.changedSections, equals({'s05'}));
        expect(
          checkOut.feature!.checks.last.text,
          equals('Press IA_Parry -> Shield reflects projectile'),
        );

        final ctrlOut = await Stage2RefineAgent.refineFeatureSpec(
          rootSpec: rootSpec,
          epic: epic,
          feature: feature,
          instruction: 'Bind IA_AirDodge to Jump',
          apiKey: '',
        );
        expect(ctrlOut.usedFallback, isTrue);
        expect(ctrlOut.changedSections, equals({'s02'}));
        expect(
          ctrlOut.feature!.controls.any((c) => c.action == 'IA_AirDodge'),
          isTrue,
        );

        final cueOut = await Stage2RefineAgent.refineFeatureSpec(
          rootSpec: rootSpec,
          epic: epic,
          feature: feature,
          instruction: 'Add spark VFX cue',
          apiKey: '',
        );
        expect(cueOut.usedFallback, isTrue);
        expect(cueOut.changedSections, equals({'s04'}));
        expect(cueOut.feature!.cues, contains('Add spark VFX cue'));

        final featScopeOut = await Stage2RefineAgent.refineFeatureSpec(
          rootSpec: rootSpec,
          epic: epic,
          feature: feature,
          instruction: 'Allow coyote dash grace',
          apiKey: '',
        );
        expect(featScopeOut.usedFallback, isTrue);
        expect(featScopeOut.changedSections, equals({'s01'}));
        expect(featScopeOut.feature!.inScope, contains('Allow coyote dash grace'));

        expect(httpCallCount, equals(0));
        expect(GeminiAgentClient.totalInputTokens, equals(0));
        expect(GeminiAgentClient.totalOutputTokens, equals(0));

        // Non-200 HTTP 403 propagates errorMessage cleanly with null spec
        GeminiAgentClient.testHttpPost = (uri, {headers, body}) async =>
            http.Response('{"error":{"message":"API key invalid"}}', 403);
        final errEpic = await Stage2RefineAgent.refineEpicSpec(
          rootSpec: rootSpec,
          epic: epic,
          instruction: 'Add sprint coyote buffer',
          apiKey: 'AIzaBadKey1234',
        );
        expect(errEpic.epic, isNull);
        expect(errEpic.errorMessage, contains('403'));

        final errFeat = await Stage2RefineAgent.refineFeatureSpec(
          rootSpec: rootSpec,
          epic: epic,
          feature: feature,
          instruction: 'Increase dash impulse',
          apiKey: 'AIzaBadKey1234',
        );
        expect(errFeat.feature, isNull);
        expect(errFeat.errorMessage, contains('403'));

        wb.dispose();
      },
    );
  });

  group('2. StudioGddBarWidgets (LocalGddLinkPill & CoPilotGddInspectPill)', () {
    testWidgets(
      'handles unlinked, syncing, synced, error, and permissionNeeded states plus tap callbacks',
      (tester) async {
        await _runWithViewport(tester, const Size(1440, 900), () async {
          final backend = _TestLocalGddBackend();
          final wb = WorkbenchProvider(enableAutoLoad: false);
          addTearDown(wb.dispose);
          wb.setLocalGddBackendForTest(backend);
          wb.loadPresetSpark('shellbreaker');

          await tester.pumpWidget(
            _testHost(
              isDark: true,
              child: AnimatedBuilder(
                animation: wb,
                builder: (_, __) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LocalGddLinkPill(workbench: wb, isDark: wb.isDark),
                    const SizedBox(width: 6),
                    CoPilotGddInspectPill(workbench: wb, isDark: wb.isDark),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // 1) Unlinked state
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.unlinked));
          expect(find.text('Link Local GDD'), findsOneWidget);
          expect(find.text('⚡ Inspect GDD'), findsOneWidget);

          // 2) Syncing state while picker future is pending -> completes to Synced
          final pickCompleter = Completer<LocalGddLinkResult>();
          backend.nextPickCompleter = pickCompleter;
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pump();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.syncing));
          expect(find.text('Link Local GDD'), findsOneWidget);

          pickCompleter.complete(
            const LocalGddLinkResult(
              linked: true,
              filename: 'shellbreaker_copilot_gdd.md',
            ),
          );
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.synced));
          expect(
            find.text('● Live · shellbreaker_copilot_gdd.md'),
            findsOneWidget,
          );

          // 3) Syncing state while already linked -> completes back to Synced
          final writeCompleter = Completer<LocalGddWriteResult>();
          backend.nextWriteCompleter = writeCompleter;
          final syncFuture = wb.syncLinkedGddNow(force: true);
          await tester.pump();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.syncing));
          expect(
            find.text('● Live · shellbreaker_copilot_gdd.md'),
            findsOneWidget,
          );
          writeCompleter.complete(const LocalGddWriteResult(written: true));
          expect(await syncFuture, isTrue);
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.synced));

          // 4) Tapping synced LocalGddLinkPill opens GDD Inspector modal
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('gdd_inspector_dialog')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('close_gdd_inspector_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('gdd_inspector_dialog')),
            findsNothing,
          );

          // 5) PermissionNeeded state -> tapping pill requests permission and recovers
          backend.denyPermission = true;
          expect(await wb.syncLinkedGddNow(force: true), isFalse);
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.permissionNeeded));
          expect(find.text('Grant GDD Write'), findsOneWidget);

          backend.denyPermission = false;
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.synced));
          expect(backend.lastRequestPermissionFlag, isTrue);

          // 6) Error state on write and on link
          backend.writeError = 'Disk read-only';
          expect(await wb.syncLinkedGddNow(force: true), isFalse);
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.error));
          expect(wb.gddSyncError, equals('Disk read-only'));
          expect(find.text('Link Local GDD'), findsOneWidget);

          backend.writeError = null;
          backend.linkError = 'Save picker failed';
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.error));
          expect(wb.gddSyncError, equals('Save picker failed'));
          expect(find.text('Link Local GDD'), findsOneWidget);

          // 7) CoPilotGddInspectPill tap opens GDD Inspector modal
          await tester.tap(
            find.byKey(const ValueKey('top_bar_copilot_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('gdd_inspector_dialog')),
            findsOneWidget,
          );
          expect(
            find.textContaining('# PROJECT GDD · SHELLBREAKER'),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('close_gdd_inspector_btn')),
          );
          await tester.pumpAndSettle();

          // 8) Unsupported File System Access backend falls back to download
          wb.setLocalGddBackendForTest(_TestLocalGddBackend(supported: false));
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.gddSyncStatus,
            equals(LocalGddSyncStatus.fallbackDownloaded),
          );
          expect(wb.isLocalGddLinked, isFalse);
          expect(find.text('Link Local GDD'), findsOneWidget);

          // 9) Tapping CoPilotGddInspectPill without a draft shows prompt toast cleanly
          wb.createNewProject();
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('top_bar_copilot_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('gdd_inspector_dialog')),
            findsNothing,
          );
          expect(find.text('Draft a Stage 1 Project Spec first.'), findsOneWidget);
        });
      },
    );

    testWidgets(
      'renders cleanly in Dark and Light themes at 1440x900 and 1024x768 with zero overflow errors',
      (tester) async {
        const viewports = <Size>[Size(1440, 900), Size(1024, 768)];
        for (final isDark in const [true, false]) {
          for (final size in viewports) {
            await _runWithViewport(tester, size, () async {
              final backend = _TestLocalGddBackend();
              final wb = WorkbenchProvider(enableAutoLoad: false);
              addTearDown(wb.dispose);
              wb.setLocalGddBackendForTest(backend);
              if (!isDark) wb.toggleTheme();
              wb.loadPresetSpark('shellbreaker');
              wb.approveRootSpecAndLaunchWorkbench();

              await tester.pumpWidget(
                _testHost(
                  isDark: isDark,
                  child: AnimatedBuilder(
                    animation: wb,
                    builder: (_, __) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StudioTopBar(workbench: wb),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LocalGddLinkPill(workbench: wb, isDark: isDark),
                            const SizedBox(width: 6),
                            CoPilotGddInspectPill(
                              workbench: wb,
                              isDark: isDark,
                            ),
                            const SizedBox(width: 6),
                            StudioExportMenuButton(
                              workbench: wb,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();

              final narrow = size.width < 1140;
              expect(
                find.text(narrow ? '⚡ GDD' : '⚡ Inspect GDD'),
                findsWidgets,
              );
              expect(find.text('Link Local GDD'), findsWidgets);

              // Synced long filename checks compact truncation below 1180px
              backend.forcedFilename = 'shellbreaker_very_long_copilot_gdd.md';
              await wb.linkLocalGddFile();
              await tester.pumpAndSettle();

              if (size.width < 1180) {
                expect(
                  find.text('● Live · shellbreaker_very_l…'),
                  findsWidgets,
                );
              } else {
                expect(
                  find.text('● Live · shellbreaker_very_long_copilot_gdd.md'),
                  findsWidgets,
                );
              }

              // Permission needed compact label check
              backend.denyPermission = true;
              await wb.syncLinkedGddNow(force: true);
              await tester.pumpAndSettle();
              expect(
                find.text(size.width < 1180 ? 'Grant GDD' : 'Grant GDD Write'),
                findsWidgets,
              );

              // Error state renders cleanly without overflow
              backend.denyPermission = false;
              backend.writeError = 'Write interrupted';
              await wb.syncLinkedGddNow(force: true);
              await tester.pumpAndSettle();
              expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.error));
            });
          }
        }
      },
    );
  });

  group('3. FloatingAiRefineDock widget tests', () {
    testWidgets(
      'displays scope chip label (full vs compact), submits trimmed text, and clears internal controller',
      (tester) async {
        final submitted = <String>[];

        await _runWithViewport(tester, const Size(1440, 900), () async {
          await tester.pumpWidget(
            _testHost(
              isDark: true,
              child: FloatingAiRefineDock(
                isDark: true,
                targetBadge: 'AI · F02',
                hintText: 'Refine F02 tuning or checks...',
                isBusy: false,
                canUndo: false,
                inputKey: const ValueKey('dock_input'),
                applyBtnKey: const ValueKey('dock_apply'),
                undoBtnKey: const ValueKey('dock_undo'),
                onApply: (text) async => submitted.add(text),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('✨ AI · F02'), findsOneWidget);
          expect(find.byKey(const ValueKey('dock_undo')), findsNothing);

          // Blank input is ignored
          await tester.enterText(find.byKey(const ValueKey('dock_input')), '   ');
          await tester.tap(find.byKey(const ValueKey('dock_apply')));
          await tester.pumpAndSettle();
          expect(submitted, isEmpty);

          // Valid input trims whitespace and clears input field after completion
          await tester.enterText(
            find.byKey(const ValueKey('dock_input')),
            '  Set DashDistance to 580 cm  ',
          );
          await tester.tap(find.byKey(const ValueKey('dock_apply')));
          await tester.pumpAndSettle();

          expect(submitted, equals(const ['Set DashDistance to 580 cm']));
          final tf = tester.widget<TextField>(
            find.byKey(const ValueKey('dock_input')),
          );
          expect(tf.controller!.text, isEmpty);
        });

        // Narrow layout (< 500px) renders compact '✨' scope badge without overflow
        await _runWithViewport(tester, const Size(1024, 768), () async {
          await tester.pumpWidget(
            _testHost(
              isDark: false,
              child: SizedBox(
                width: 420,
                child: FloatingAiRefineDock(
                  isDark: false,
                  targetBadge: 'AI · F02',
                  hintText: 'Refine F02...',
                  isBusy: false,
                  canUndo: true,
                  onUndo: () {},
                  inputKey: const ValueKey('dock_input_narrow'),
                  applyBtnKey: const ValueKey('dock_apply_narrow'),
                  undoBtnKey: const ValueKey('dock_undo_narrow'),
                  onApply: (_) async {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('✨'), findsOneWidget);
          expect(find.text('✨ AI · F02'), findsNothing);
        });
      },
    );

    testWidgets(
      'handles busy indicator state, Undo visibility + callback, summary/error banners, and quick-chip fill/submit',
      (tester) async {
        await _runWithViewport(tester, const Size(1440, 900), () async {
          var isBusy = false;
          var canUndo = false;
          var undoCalls = 0;
          var dismissCalls = 0;
          final applied = <String>[];
          String? summaryText = 'Updated DashDistance';
          String? errorText;
          late StateSetter rebuild;

          await tester.pumpWidget(
            _testHost(
              isDark: true,
              child: StatefulBuilder(
                builder: (_, setState) {
                  rebuild = setState;
                  return FloatingAiRefineDock(
                    isDark: true,
                    targetBadge: 'AI · F02',
                    hintText: 'Refine F02...',
                    isBusy: isBusy,
                    canUndo: canUndo,
                    alwaysShowUndo: true,
                    summaryText: summaryText,
                    errorText: errorText,
                    quickPrompts: const [
                      'Set DashDistance to 550 cm',
                      'Add impact VFX cue',
                    ],
                    inputKey: const ValueKey('dock_input'),
                    applyBtnKey: const ValueKey('dock_apply'),
                    undoBtnKey: const ValueKey('dock_undo'),
                    ideasBtnKey: const ValueKey('dock_ideas'),
                    ideasStripKey: const ValueKey('dock_ideas_strip'),
                    onApply: (text) async => applied.add(text),
                    onUndo: () => undoCalls++,
                    onDismissError: () {
                      dismissCalls++;
                      setState(() => errorText = null);
                    },
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Summary text shown; Undo visible via alwaysShowUndo but disabled when canUndo == false
          expect(find.text('✓ Updated DashDistance'), findsOneWidget);
          expect(find.byKey(const ValueKey('dock_undo')), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('dock_undo')));
          expect(undoCalls, equals(0));

          // Quick-chip strip tucked initially, opens on Ideas button tap
          expect(find.byKey(const ValueKey('dock_ideas_strip')), findsNothing);
          await tester.tap(find.byKey(const ValueKey('dock_ideas')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('dock_ideas_strip')), findsOneWidget);
          expect(find.text('Hide'), findsOneWidget);

          // Tapping quick-prompt chip fills input without auto-submitting; Apply submits it
          await tester.tap(find.text('Set DashDistance to 550 cm'));
          await tester.pumpAndSettle();
          final fieldAfterChip = tester.widget<TextField>(
            find.byKey(const ValueKey('dock_input')),
          );
          expect(
            fieldAfterChip.controller!.text,
            equals('Set DashDistance to 550 cm'),
          );
          expect(applied, isEmpty);

          await tester.tap(find.byKey(const ValueKey('dock_apply')));
          await tester.pumpAndSettle();
          expect(applied, equals(const ['Set DashDistance to 550 cm']));

          // Enable Undo + verify callback fires
          rebuild(() {
            canUndo = true;
          });
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('dock_undo')));
          await tester.pumpAndSettle();
          expect(undoCalls, equals(1));

          // Error banner + dismiss callback
          rebuild(() {
            errorText = 'Gemini quota exceeded';
          });
          await tester.pumpAndSettle();
          expect(find.text('Gemini quota exceeded'), findsOneWidget);
          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();
          expect(dismissCalls, equals(1));
          expect(find.text('Gemini quota exceeded'), findsNothing);

          // Busy indicator disables Apply, Undo, TextField, and chips
          rebuild(() {
            isBusy = true;
          });
          await tester.pump();
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text('Apply'), findsNothing);
          final busyField = tester.widget<TextField>(
            find.byKey(const ValueKey('dock_input')),
          );
          expect(busyField.enabled, isFalse);

          await tester.tap(find.byKey(const ValueKey('dock_undo')));
          await tester.tap(find.byKey(const ValueKey('dock_apply')));
          expect(undoCalls, equals(1));
          expect(applied, hasLength(1));
        });
      },
    );
  });

  group('4. Stage1EpicPreviewSection widget tests', () {
    testWidgets(
      'renders section 05 slices and supports inline slice rename, cancel, delete, and epic reorder/remove',
      (tester) async {
        await _runWithViewport(tester, const Size(1440, 900), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);

          await tester.pumpWidget(
            _testHost(
              isDark: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: AnimatedBuilder(
                  animation: wb,
                  builder: (_, __) => Stage1EpicPreviewSection(
                    workbench: wb,
                    spec: wb.conceptDraft!,
                    activeProjectId: wb.activeProjectId,
                    isUpdated: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final epics = wb.conceptDraft!.initialEpics;
          expect(epics.length, greaterThanOrEqualTo(2));
          final firstEpic = epics.first;
          final f01 = firstEpic.featuresForRelease('v0.1').first;
          final f02 = firstEpic.featuresForRelease('v0.1')[1];

          expect(find.text('§05'), findsOneWidget);
          expect(
            find.text('Seeded Epics & Initial v0.1 Feature Slices'),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('stage1_scope_preview_card')),
            findsOneWidget,
          );
          expect(find.text('#1 Build First'), findsOneWidget);
          expect(find.text('Lean v0.1'), findsOneWidget);
          expect(find.text('${f01.code} · ${f01.title}'), findsOneWidget);
          expect(find.text('${f02.code} · ${f02.title}'), findsOneWidget);

          // Inline slice rename: Cancel leaves original title untouched
          final originalTitle = f01.title;
          await tester.tap(
            find.byKey(ValueKey('stage1_feat_edit_${f01.id}')),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(ValueKey('stage1_feat_input_${f01.id}')),
            'Temporary Title',
          );
          await tester.tap(
            find.byKey(ValueKey('stage1_feat_cancel_${f01.id}')),
          );
          await tester.pumpAndSettle();
          expect(f01.title, equals(originalTitle));

          // Inline slice rename: Save updates title in provider & UI
          await tester.tap(
            find.byKey(ValueKey('stage1_feat_edit_${f01.id}')),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(ValueKey('stage1_feat_input_${f01.id}')),
            'Dash Thrust Combo',
          );
          await tester.tap(
            find.byKey(ValueKey('stage1_feat_save_${f01.id}')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.conceptDraft!.initialEpics.first.features.first.title,
            equals('Dash Thrust Combo'),
          );
          expect(find.text('F01 · Dash Thrust Combo'), findsOneWidget);

          // Inline slice delete removes F02; remaining single slice disables delete
          final countBeforeDelete =
              wb.conceptDraft!.initialEpics.first.features.length;
          await tester.tap(
            find.byKey(ValueKey('stage1_feat_remove_${f02.id}')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.conceptDraft!.initialEpics.first.features.length,
            equals(countBeforeDelete - 1),
          );
          if (wb.conceptDraft!.initialEpics.first
                  .featuresForRelease('v0.1')
                  .length ==
              1) {
            final remainingBtn = tester.widget<IconButton>(
              find.byKey(ValueKey('stage1_feat_remove_${f01.id}')),
            );
            expect(remainingBtn.onPressed, isNull);
          }

          // Reorder Epic 0 down swaps first two Epics while renumbering codes
          final firstEpicId = wb.conceptDraft!.initialEpics[0].id;
          final secondEpicId = wb.conceptDraft!.initialEpics[1].id;
          await tester.tap(find.byKey(const ValueKey('stage1_epic_down_0')));
          await tester.pumpAndSettle();
          expect(wb.conceptDraft!.initialEpics[0].id, equals(secondEpicId));
          expect(wb.conceptDraft!.initialEpics[1].id, equals(firstEpicId));

          // Remove Epic 1 shrinks initialEpics list
          final epicCountBefore = wb.conceptDraft!.initialEpics.length;
          await tester.tap(find.byKey(const ValueKey('stage1_epic_remove_1')));
          await tester.pumpAndSettle();
          expect(
            wb.conceptDraft!.initialEpics.length,
            equals(epicCountBefore - 1),
          );
        });
      },
    );

    testWidgets(
      'renders Scope Check warning and zero overflow across Dark and Light themes at 1440x900 and 1024x768',
      (tester) async {
        const viewports = <Size>[Size(1440, 900), Size(1024, 768)];
        for (final isDark in const [true, false]) {
          for (final size in viewports) {
            await _runWithViewport(tester, size, () async {
              final wb = WorkbenchProvider(enableAutoLoad: false)
                ..loadPresetSpark('shellbreaker');
              addTearDown(wb.dispose);
              if (!isDark) wb.toggleTheme();

              // Push > 8 features to surface Scope Check + Trim button
              final firstEp = wb.conceptDraft!.initialEpics.first;
              while (wb.conceptDraft!.initialEpics
                      .expand((e) => e.featuresForRelease('v0.1'))
                      .length <=
                  8) {
                final nextIdx = firstEp.features.length + 1;
                firstEp.features.add(
                  FeatureSpec(
                    id: 'extra_f_$nextIdx',
                    code: FeatureSpec.formatCode(nextIdx),
                    title: 'Extra Slice $nextIdx',
                    goal: 'Test extra slice in v0.1.',
                    checks: [
                      EpicPieCheck(
                        id: 'extra_chk_$nextIdx',
                        text: 'Trigger slice -> Effect fires',
                      ),
                    ],
                  ),
                );
              }

              await tester.pumpWidget(
                _testHost(
                  isDark: isDark,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Stage1EpicPreviewSection(
                      workbench: wb,
                      spec: wb.conceptDraft!,
                      activeProjectId: wb.activeProjectId,
                      isUpdated: false,
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();

              expect(find.text('Scope Check'), findsOneWidget);
              expect(
                find.byKey(const ValueKey('stage1_trim_lean_btn')),
                findsOneWidget,
              );
            });
          }
        }
      },
    );
  });

  group('5. Stage2InlineEditors unit & widget tests', () {
    testWidgets(
      'InlineTuningAddBox uses plain Key | Value | Unit inputs with zero sliders and rejects empty key or value',
      (tester) async {
        await _runWithViewport(tester, const Size(1440, 900), () async {
          final added = <(String, String, String)>[];
          var cancelCalls = 0;

          await tester.pumpWidget(
            _testHost(
              isDark: true,
              child: InlineTuningAddBox(
                isDark: true,
                keyInputKey: const ValueKey('tune_key'),
                valueInputKey: const ValueKey('tune_val'),
                unitInputKey: const ValueKey('tune_unit'),
                saveBtnKey: const ValueKey('tune_save'),
                onAdd: (k, v, u) => added.add((k, v, u)),
                onCancel: () => cancelCalls++,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(Slider), findsNothing);
          expect(find.byType(TextField), findsNWidgets(3));

          // Empty key does not fire onAdd
          await tester.enterText(find.byKey(const ValueKey('tune_val')), '500');
          await tester.tap(find.byKey(const ValueKey('tune_save')));
          await tester.pumpAndSettle();
          expect(added, isEmpty);

          // Empty value does not fire onAdd
          await tester.enterText(
            find.byKey(const ValueKey('tune_key')),
            'DashDistance',
          );
          await tester.enterText(find.byKey(const ValueKey('tune_val')), '   ');
          await tester.tap(find.byKey(const ValueKey('tune_save')));
          await tester.pumpAndSettle();
          expect(added, isEmpty);

          // Valid trimmed submission fires onAdd
          await tester.enterText(
            find.byKey(const ValueKey('tune_key')),
            '  DashSpeed  ',
          );
          await tester.enterText(
            find.byKey(const ValueKey('tune_val')),
            '  900  ',
          );
          await tester.enterText(
            find.byKey(const ValueKey('tune_unit')),
            '  cm/s  ',
          );
          await tester.tap(find.byKey(const ValueKey('tune_save')));
          await tester.pumpAndSettle();
          expect(added, equals(const [('DashSpeed', '900', 'cm/s')]));

          await tester.tap(find.text('Cancel'));
          expect(cancelCalls, equals(1));
        });
      },
    );

    testWidgets(
      'FeatureSpecSheet handles empty/duplicate tuning keys without sliders and full input action CRUD',
      (tester) async {
        await _runWithViewport(tester, const Size(1440, 900), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..loadPresetSpark('shellbreaker')
            ..approveRootSpecAndLaunchWorkbench();
          addTearDown(wb.dispose);

          final epic = wb.activeReleaseEpics.first;
          final f02 = epic.features.firstWhere((f) => f.code == 'F02');
          wb.selectFeature(epic.id, f02.id);

          await tester.pumpWidget(
            _testHost(
              isDark: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: AnimatedBuilder(
                  animation: wb,
                  builder: (_, __) => FeatureSpecSheet(
                    workbench: wb,
                    epic: wb.selectedEpicSpec!,
                    feature: wb.selectedFeatureSpec!,
                    isLockedBaseline: false,
                    isDark: true,
                    selectionKey: '${wb.activeReleaseId}:${epic.id}:${f02.id}',
                    passGateHint: null,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(Slider), findsNothing);

          // Open tuning add box -> still zero sliders
          final addTuningBtn =
              find.byKey(const ValueKey('feature_add_tuning_btn'));
          await tester.ensureVisible(addTuningBtn);
          await tester.tap(addTuningBtn);
          await tester.pumpAndSettle();
          expect(find.byType(Slider), findsNothing);

          // Empty key leaves tuning list unchanged
          final tuningCountStart = wb.selectedFeatureSpec!.tuning.length;
          await tester.enterText(
            find.byKey(const ValueKey('feature_tuning_value_input')),
            '350',
          );
          await tester.tap(
            find.byKey(const ValueKey('feature_tuning_save_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.selectedFeatureSpec!.tuning.length, equals(tuningCountStart));

          // Duplicate key (case-insensitive / snake_case -> DashDistance) updates in place
          await tester.enterText(
            find.byKey(const ValueKey('feature_tuning_key_input')),
            'dash_distance',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_tuning_value_input')),
            '720',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_tuning_unit_input')),
            'cm',
          );
          final saveTuningBtn =
              find.byKey(const ValueKey('feature_tuning_save_btn'));
          await tester.ensureVisible(saveTuningBtn);
          await tester.tap(saveTuningBtn);
          await tester.pumpAndSettle();

          final dashParams = wb.selectedFeatureSpec!.tuning
              .where((t) => t.key == 'DashDistance')
              .toList();
          expect(dashParams, hasLength(1));
          expect(dashParams.single.value, equals('720'));
          expect(wb.selectedFeatureSpec!.tuning.length, equals(tuningCountStart));

          // Input Action CRUD: Create -> Read -> Update -> Delete -> Undo
          final addCtrlBtn =
              find.byKey(const ValueKey('feature_add_control_btn'));
          await tester.ensureVisible(addCtrlBtn);
          await tester.tap(addCtrlBtn);
          await tester.pumpAndSettle();

          await tester.enterText(
            find.byKey(const ValueKey('feature_control_action_input')),
            'claw_slam',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_control_trigger_input')),
            'Pressed',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_control_rule_input')),
            'Slam claw 400 cm down',
          );
          final saveCtrlBtn =
              find.byKey(const ValueKey('feature_control_save_btn'));
          await tester.ensureVisible(saveCtrlBtn);
          await tester.tap(saveCtrlBtn);
          await tester.pumpAndSettle();

          expect(
            wb.selectedFeatureSpec!.controls
                .any((c) => c.action == 'IA_ClawSlam'),
            isTrue,
          );
          final createdIdx = wb.selectedFeatureSpec!.controls.length - 1;
          expect(find.text('IA_ClawSlam'), findsOneWidget);

          // Update created row in place
          final editCtrlBtn =
              find.byKey(ValueKey('feature_control_edit_$createdIdx'));
          await tester.ensureVisible(editCtrlBtn);
          await tester.tap(editCtrlBtn);
          await tester.pumpAndSettle();

          final actionField = tester.widget<TextField>(
            find.byKey(const ValueKey('feature_control_action_input')),
          );
          expect(actionField.controller!.text, equals('IA_ClawSlam'));

          await tester.enterText(
            find.byKey(const ValueKey('feature_control_rule_input')),
            'Slam claw 550 cm down on impact',
          );
          final saveEditedCtrlBtn =
              find.byKey(const ValueKey('feature_control_save_btn'));
          await tester.ensureVisible(saveEditedCtrlBtn);
          await tester.tap(saveEditedCtrlBtn);
          await tester.pumpAndSettle();

          expect(
            wb.selectedFeatureSpec!.controls[createdIdx].rule,
            equals('Slam claw 550 cm down on impact'),
          );
          expect(
            wb.selectedFeatureSpec!.controls.length,
            equals(createdIdx + 1),
          );

          // Delete row & Undo restoration
          final delCtrlBtn =
              find.byKey(ValueKey('feature_control_delete_$createdIdx'));
          await tester.ensureVisible(delCtrlBtn);
          await tester.tap(delCtrlBtn);
          await tester.pumpAndSettle();
          expect(
            wb.selectedFeatureSpec!.controls
                .any((c) => c.action == 'IA_ClawSlam'),
            isFalse,
          );

          expect(wb.undoStage2Edit(), isTrue);
          await tester.pumpAndSettle();
          expect(
            wb.selectedFeatureSpec!.controls
                .any((c) => c.action == 'IA_ClawSlam'),
            isTrue,
          );
        });
      },
    );

    testWidgets(
      'InlineScopeEditorBox, InlineControlEditorBox, and InlineSingleLineAdderBox handle save, validation, and cancel',
      (tester) async {
        await _runWithViewport(tester, const Size(1440, 900), () async {
          String? savedGoal;
          List<String>? savedInScope;
          List<String>? savedDoneWhen;
          String? savedDelta;
          (String, String, String)? savedControl;
          var scopeCancels = 0;
          var controlCancels = 0;

          await tester.pumpWidget(
            _testHost(
              isDark: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    InlineScopeEditorBox(
                      isDark: false,
                      initialGoal: 'Initial goal',
                      initialInScope: const ['Item A', 'Item B'],
                      initialDoneWhen: const ['Check 1'],
                      initialDelta: '+Add stagger meter',
                      showDeltaField: true,
                      goalInputKey: const ValueKey('scope_goal'),
                      inScopeInputKey: const ValueKey('scope_in'),
                      doneWhenInputKey: const ValueKey('scope_done'),
                      deltaInputKey: const ValueKey('scope_delta'),
                      saveBtnKey: const ValueKey('scope_save'),
                      onSave: ({
                        required goal,
                        required inScope,
                        required doneWhen,
                        required delta,
                      }) {
                        savedGoal = goal;
                        savedInScope = inScope;
                        savedDoneWhen = doneWhen;
                        savedDelta = delta;
                      },
                      onCancel: () => scopeCancels++,
                    ),
                    const SizedBox(height: 12),
                    InlineControlEditorBox(
                      isDark: false,
                      actionInputKey: const ValueKey('ctrl_action'),
                      triggerInputKey: const ValueKey('ctrl_trigger'),
                      ruleInputKey: const ValueKey('ctrl_rule'),
                      saveBtnKey: const ValueKey('ctrl_save'),
                      onSave: (a, t, r) => savedControl = (a, t, r),
                      onCancel: () => controlCancels++,
                    ),
                    const SizedBox(height: 12),
                    InlineSingleLineAdderBox(
                      isDark: false,
                      labelText: 'Cut Label',
                      hintText: 'No open world',
                      inputKey: const ValueKey('single_input'),
                      saveBtnKey: const ValueKey('single_save'),
                      onSubmit: (val) => savedGoal = 'SINGLE:$val',
                      onCancel: () => scopeCancels++,
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(Slider), findsNothing);

          // Scope editor trims and splits multiline lists ignoring blank lines
          await tester.enterText(
            find.byKey(const ValueKey('scope_delta')),
            '  +Add heavy stagger  ',
          );
          await tester.enterText(
            find.byKey(const ValueKey('scope_goal')),
            '  Crack crab armor on dash  ',
          );
          await tester.enterText(
            find.byKey(const ValueKey('scope_in')),
            '  Dash impulse  \n\n  Stagger burst  \n',
          );
          await tester.enterText(
            find.byKey(const ValueKey('scope_done')),
            '\n  Armor breaks cleanly  \n  SFX plays  ',
          );
          await tester.tap(find.byKey(const ValueKey('scope_save')));
          await tester.pumpAndSettle();

          expect(savedDelta, equals('+Add heavy stagger'));
          expect(savedGoal, equals('Crack crab armor on dash'));
          expect(savedInScope, equals(const ['Dash impulse', 'Stagger burst']));
          expect(
            savedDoneWhen,
            equals(const ['Armor breaks cleanly', 'SFX plays']),
          );

          // Control editor rejects blank action/rule, passes trimmed tuple, and fires cancel
          await tester.enterText(
            find.byKey(const ValueKey('ctrl_action')),
            'IA_Dash',
          );
          await tester.tap(find.byKey(const ValueKey('ctrl_save')));
          expect(savedControl, isNull);

          await tester.enterText(
            find.byKey(const ValueKey('ctrl_action')),
            '  IA_ClawDash  ',
          );
          await tester.enterText(
            find.byKey(const ValueKey('ctrl_trigger')),
            '  Started  ',
          );
          await tester.enterText(
            find.byKey(const ValueKey('ctrl_rule')),
            '  Burst 500 cm ahead  ',
          );
          await tester.tap(find.byKey(const ValueKey('ctrl_save')));
          expect(
            savedControl,
            equals(('IA_ClawDash', 'Started', 'Burst 500 cm ahead')),
          );

          // Single-line adder rejects blank input and accepts trimmed value
          await tester.enterText(
            find.byKey(const ValueKey('single_input')),
            '   ',
          );
          await tester.tap(find.byKey(const ValueKey('single_save')));
          expect(savedGoal, equals('Crack crab armor on dash'));

          await tester.enterText(
            find.byKey(const ValueKey('single_input')),
            '  Skill trees  ',
          );
          await tester.tap(find.byKey(const ValueKey('single_save')));
          expect(savedGoal, equals('SINGLE:Skill trees'));

          await tester.tap(find.text('Cancel').at(0));
          await tester.tap(find.text('Cancel').at(1));
          expect(scopeCancels, equals(1));
          expect(controlCancels, equals(1));
        });
      },
    );
  });
}

Widget _testHost({required bool isDark, required Widget child}) {
  return MaterialApp(
    theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

Future<void> _runWithViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  final prevOnError = FlutterError.onError;
  final caughtErrors = <FlutterErrorDetails>[];
  FlutterError.onError = (details) {
    caughtErrors.add(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = prevOnError;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
  final overflowErrors = caughtErrors.where(
    (d) => d.exceptionAsString().contains('A RenderFlex overflowed'),
  );
  expect(
    overflowErrors,
    isEmpty,
    reason: overflowErrors.map((e) => e.exceptionAsString()).join('\n'),
  );
  expect(
    caughtErrors,
    isEmpty,
    reason: caughtErrors.map((e) => e.exceptionAsString()).join('\n'),
  );
}

class _TestLocalGddBackend implements LocalGddFileBackend {
  final bool supported;
  bool denyPermission = false;
  bool lastRequestPermissionFlag = false;
  String? forcedFilename;
  String? linkError;
  String? writeError;
  Completer<LocalGddLinkResult>? nextPickCompleter;
  Completer<LocalGddWriteResult>? nextWriteCompleter;
  final Map<String, String> linkedHandles = <String, String>{};
  final List<String> writtenContents = <String>[];

  _TestLocalGddBackend({this.supported = true});

  @override
  bool get isSupported => supported;

  @override
  Future<LocalGddLinkResult> pickAndWriteFile({
    required String projectId,
    required String suggestedFilename,
    required String content,
  }) async {
    final resolvedName = forcedFilename ?? suggestedFilename;
    final pending = nextPickCompleter;
    if (pending != null) {
      nextPickCompleter = null;
      final res = await pending.future;
      if (res.linked) {
        linkedHandles[projectId] = res.filename ?? resolvedName;
        writtenContents.add(content);
      }
      return res;
    }
    if (linkError != null) {
      return LocalGddLinkResult(linked: false, error: linkError);
    }
    linkedHandles[projectId] = resolvedName;
    writtenContents.add(content);
    return LocalGddLinkResult(linked: true, filename: resolvedName);
  }

  @override
  Future<String?> restoreLinkedFilename(String projectId) async =>
      linkedHandles[projectId];

  @override
  Future<LocalGddWriteResult> writeLinkedFile({
    required String projectId,
    required String content,
    bool requestPermissionIfNeeded = false,
  }) async {
    lastRequestPermissionFlag = requestPermissionIfNeeded;
    final pending = nextWriteCompleter;
    if (pending != null) {
      nextWriteCompleter = null;
      final res = await pending.future;
      if (res.written) {
        writtenContents.add(content);
      }
      return res;
    }
    if (!linkedHandles.containsKey(projectId)) {
      return const LocalGddWriteResult(written: false);
    }
    if (denyPermission) {
      return const LocalGddWriteResult(
        written: false,
        permissionDenied: true,
      );
    }
    if (writeError != null) {
      return LocalGddWriteResult(written: false, error: writeError);
    }
    writtenContents.add(content);
    return const LocalGddWriteResult(written: true);
  }

  @override
  Future<void> unlinkProject(String projectId) async {
    linkedHandles.remove(projectId);
  }
}
