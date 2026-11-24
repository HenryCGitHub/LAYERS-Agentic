import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/main.dart';
import 'package:layers_agentic/models/epic_spec.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/project_pitch_screen.dart';
import 'package:layers_agentic/screens/release_workbench_screen.dart';
import 'package:layers_agentic/services/local_vault_service.dart';
import 'package:layers_agentic/services/storage/vault_storage_interface.dart';

void main() {
  group('Flight Deck Round 2 Scratch-Concept Dogfood Simulation (1920x1080)', () {
    testWidgets(
      'SKYHOOK COURIER C++ & BP Hybrid walkthrough: vague spark -> 503 failover -> camera/trade-off -> GDD + multi-project -> Stage 2 AI error recovery -> v0.1..v0.3 baseline jumps -> Stage 1 re-sync',
      (tester) async {
        final memoryVault = _ScratchMemoryVaultBackend();
        final fakeGddBackend = _ScratchLocalGddBackend();
        final geminiCalls =
            <({String model, String? thinkingLevel, String tool, int status})>[];

        var failStage1Refine = true;
        var failStage2Refine = true;
        var progressiveCalls = 0;

        _installScratchHooks(
          memoryVault: memoryVault,
          onGeminiCall: (uri, body) {
            final urlStr = uri.toString();
            final genCfg = body['generationConfig'] as Map<String, dynamic>?;
            final thinkingCfg =
                genCfg?['thinkingConfig'] as Map<String, dynamic>?;
            final thinkingLevel = thinkingCfg?['thinkingLevel']?.toString();
            final tools = body['tools'] as List?;
            final decls = tools != null && tools.isNotEmpty
                ? (tools.first as Map<String, dynamic>)['functionDeclarations']
                    as List?
                : null;
            final toolName = decls != null && decls.isNotEmpty
                ? (decls.first as Map<String, dynamic>)['name'].toString()
                : '';
            final bodyStr = jsonEncode(body);

            var model = 'unknown';
            if (urlStr.contains(GeminiAgentClient.pinnedArchitectModel)) {
              model = GeminiAgentClient.pinnedArchitectModel;
            } else if (urlStr.contains(GeminiAgentClient.pinnedLiveFlashModel)) {
              model = GeminiAgentClient.pinnedLiveFlashModel;
            } else if (urlStr.contains('gemini-flash-latest')) {
              model = 'gemini-flash-latest';
            }

            // 1) Simulate 503 outage on gemini-4-argon so Draft Spark fails over to gemini-4-hydrogen
            if (toolName == 'commit_unreal_root_spec' &&
                model == GeminiAgentClient.pinnedArchitectModel) {
              geminiCalls.add((
                model: model,
                thinkingLevel: thinkingLevel,
                tool: toolName,
                status: 503,
              ));
              return http.Response(
                '{"error":{"code":503,"message":"Argon temporarily unavailable"}}',
                503,
              );
            }

            if (toolName == 'commit_unreal_root_spec') {
              geminiCalls.add((
                model: model,
                thinkingLevel: thinkingLevel,
                tool: toolName,
                status: 200,
              ));
              return _geminiFunctionResponse(
                modelVersion: 'gemini-4-hydrogen-preview',
                inputTokens: 920,
                outputTokens: 640,
                thinkingTokens: 110,
                toolName: toolName,
                args: _skyhookRootSpecPayload(),
              );
            }

            // 2) Stage 1 AI refine fails cleanly across model chain until failStage1Refine toggles false
            if (toolName == 'patch_unreal_root_spec' ||
                (toolName.isEmpty &&
                    bodyStr.contains('patch_unreal_root_spec'))) {
              if (failStage1Refine) {
                geminiCalls.add((
                  model: model,
                  thinkingLevel: thinkingLevel,
                  tool: toolName,
                  status: 400,
                ));
                return http.Response(
                  '{"error":{"code":400,"message":"Simulated Stage 1 transient refine error"}}',
                  400,
                );
              }
              geminiCalls.add((
                model: model,
                thinkingLevel: thinkingLevel,
                tool: toolName,
                status: 200,
              ));
              return _geminiFunctionResponse(
                modelVersion: 'gemini-4-hydrogen-preview',
                inputTokens: 380,
                outputTokens: 120,
                thinkingTokens: 20,
                toolName: toolName,
                args: <String, dynamic>{
                  'coDesignNote':
                      'Added wall-run momentum boost and trimmed grind rails.',
                  'changedSections': <String>['s01', 's04'],
                  'pitch':
                      'High-altitude hook courier — chain grapple swings and wall-runs to stamp Rooftop Mailboxes',
                  'outOfScope': <String>[
                    'No multiplayer delivery races',
                    'No procedural city generator',
                    'No weapon durability or grind rails',
                  ],
                },
              );
            }

            // 3) Stage 2 AI refine fails cleanly across model chain until failStage2Refine toggles false
            if (toolName == 'patch_unreal_feature_spec' ||
                (toolName.isEmpty &&
                    bodyStr.contains('patch_unreal_feature_spec'))) {
              if (failStage2Refine) {
                geminiCalls.add((
                  model: model,
                  thinkingLevel: thinkingLevel,
                  tool: toolName,
                  status: 400,
                ));
                return http.Response(
                  '{"error":{"code":400,"message":"Simulated Stage 2 refine error"}}',
                  400,
                );
              }
              geminiCalls.add((
                model: model,
                thinkingLevel: thinkingLevel,
                tool: toolName,
                status: 200,
              ));
              return _geminiFunctionResponse(
                modelVersion: 'gemini-4-hydrogen-preview',
                inputTokens: 290,
                outputTokens: 90,
                thinkingTokens: 15,
                toolName: toolName,
                args: <String, dynamic>{
                  'summary': 'Doubled WinchPullSpeed to 2600 cm/s for snappier vault pulls',
                  'changedSections': <String>['s01', 's03'],
                  'goal':
                      'Reel the mech cleanly at 2600 cm/s along taut Skyhook cables into rooftop launch arcs.',
                  'tuning': <Map<String, dynamic>>[
                    {'key': 'MaxHookRange', 'value': '2800', 'unit': 'cm'},
                    {'key': 'WinchPullSpeed', 'value': '2600', 'unit': 'cm/s'},
                  ],
                },
              );
            }

            // 4) Progressive Release proposals: call 1 -> v0.2, call 2 -> v0.3
            if (toolName == 'propose_progressive_unreal_release') {
              progressiveCalls++;
              geminiCalls.add((
                model: model,
                thinkingLevel: thinkingLevel,
                tool: toolName,
                status: 200,
              ));
              if (progressiveCalls == 1) {
                return _geminiFunctionResponse(
                  modelVersion: 'gemini-4-argon-preview',
                  inputTokens: 640,
                  outputTokens: 260,
                  thinkingTokens: 70,
                  toolName: toolName,
                  args: _v02ProgressivePayload(),
                );
              }
              return _geminiFunctionResponse(
                modelVersion: 'gemini-4-argon-preview',
                inputTokens: 710,
                outputTokens: 280,
                thinkingTokens: 85,
                toolName: toolName,
                args: _v03ProgressivePayload(),
              );
            }

            return http.Response('{"error":{"message":"Unexpected tool"}}', 400);
          },
        );

        await _runWith1080pViewport(tester, () async {
          // 1) Cold boot LayersAgenticApp on 1920x1080 Dark theme from completely blank state
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..setLocalGddBackendForTest(fakeGddBackend)
            ..updateAiConfig(apiKey: 'AIzaScratchConcept1080pKey');
          addTearDown(wb.dispose);

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          expect(wb.isDark, isTrue);
          expect(find.byType(ProjectPitchScreen), findsOneWidget);
          expect(
            find.byKey(const ValueKey('stage1_blueprint_empty_outline')),
            findsOneWidget,
          );

          // 2) Enter vague 2-word Spark -> Quick Forks -> pick C++ & BP Hybrid -> 503 failover -> SKYHOOK COURIER
          await tester.enterText(
            find.byKey(const ValueKey('spark_prompt_input')),
            'mech courier',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('draft_spark_btn')));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('stage1_spark_clarify_card')),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const ValueKey('clarify_view_tps')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('clarify_archetype_movement')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('clarify_hook_course')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('stage1_mode_cpp_hybrid')));
          await tester.pumpAndSettle();

          await tester.tap(
            find.byKey(const ValueKey('stage1_clarify_confirm_btn')),
          );
          await tester.pumpAndSettle();

          expect(wb.conceptDraft?.gameTitle, equals('SKYHOOK COURIER'));
          expect(
            wb.unrealArchitectureMode,
            equals(UnrealArchitectureMode.cppHybrid),
          );
          expect(
            geminiCalls.any(
              (c) =>
                  c.tool == 'commit_unreal_root_spec' &&
                  c.model == GeminiAgentClient.pinnedArchitectModel &&
                  c.status == 503,
            ),
            isTrue,
          );
          expect(
            geminiCalls.any(
              (c) =>
                  c.tool == 'commit_unreal_root_spec' &&
                  c.model == GeminiAgentClient.pinnedLiveFlashModel &&
                  c.status == 200,
            ),
            isTrue,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('active_model_indicator_pill')),
              matching: find.text('⚡ Hydrogen'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('token_usage_tracker_pill')),
              matching: find.textContaining('\$'),
            ),
            findsOneWidget,
          );

          // 3) Camera Decision Fork + Core Feel + Trade-Offs error guard & save
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('camera_opt_shoulder_tight')),
          );
          expect(
            wb.conceptDraft?.cameraChoiceId,
            equals('shoulder_tight'),
          );
          expect(
            wb.conceptDraft?.cameraContract,
            contains('320 cm offset shoulder arm'),
          );

          await _tapVisible(tester, find.byKey(const ValueKey('feel_opt_heavy')));
          expect(wb.conceptDraft?.feelChoiceId, equals('heavy'));

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_edit_pillars_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('stage1_tradeoffs_input')),
            'Broken rule without separator',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_pillars_save_btn')),
          );
          expect(
            find.byKey(const ValueKey('stage1_tradeoffs_error')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('stage1_pillars_input')),
            findsOneWidget,
          );

          await tester.enterText(
            find.byKey(const ValueKey('stage1_tradeoffs_input')),
            'Momentum Swinging OVER Ground Friction',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_pillars_save_btn')),
          );
          expect(
            find.byKey(const ValueKey('stage1_tradeoffs_error')),
            findsNothing,
          );
          expect(
            wb.conceptDraft!.tradeOffs.single.formatted,
            equals('Momentum Swinging OVER Ground Friction'),
          );

          // 4) Stage 1 FloatingAiRefineDock HTTP 400 error preserves prompt -> Retry recovers -> Undo restores
          const refinePrompt = 'Add wall-run momentum boost and cut grind rails';
          await tester.enterText(
            find.byKey(const ValueKey('stage1_codesign_input')),
            refinePrompt,
          );
          await tester.tap(
            find.byKey(const ValueKey('stage1_codesign_apply_btn')),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('stage1_inline_error_banner')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('stage1_codesign_input')),
                )
                .controller!
                .text,
            equals(refinePrompt),
          );

          failStage1Refine = false;
          await tester.tap(
            find.byKey(const ValueKey('stage1_refine_retry_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('stage1_inline_error_banner')),
            findsNothing,
          );
          expect(wb.conceptDraft!.pitch, contains('wall-runs'));

          await tester.tap(find.byKey(const ValueKey('stage1_undo_btn')));
          await tester.pumpAndSettle();
          expect(wb.conceptDraft!.pitch, isNot(contains('wall-runs')));

          // 5) Link Local GDD + Inspect C++ & BP Hybrid Source/ markdown + Multi-project & JSON round-trip
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          expect(wb.isLocalGddLinked, isTrue);
          final gddFilename = wb.linkedGddFileName!;
          expect(find.text('● Live · $gddFilename'), findsOneWidget);

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('top_bar_copilot_gdd_btn')),
          );
          expect(
            find.byKey(const ValueKey('gdd_inspector_dialog')),
            findsOneWidget,
          );
          expect(
            find.textContaining('C++ & BP Hybrid'),
            findsWidgets,
          );
          expect(
            find.textContaining('Source/SkyhookCourier/'),
            findsWidgets,
          );
          await tester.tap(
            find.byKey(const ValueKey('close_gdd_inspector_btn')),
          );
          await tester.pumpAndSettle();

          final skyhookProjId = wb.activeProjectId!;
          expect(wb.savedProjects, hasLength(1));

          // Create Project 2 via switcher -> top bar shows unlinked; switch back -> restores Live GDD
          await tester.tap(
            find.byKey(const ValueKey('project_switcher_dropdown_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('+ New Project'));
          await tester.pumpAndSettle();

          final blankProjId = wb.activeProjectId!;
          expect(blankProjId, isNot(equals(skyhookProjId)));
          expect(wb.isLocalGddLinked, isFalse);
          expect(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
            findsNothing,
          );
          await tester.tap(find.byKey(const ValueKey('preset_railjack')));
          await tester.pumpAndSettle();
          expect(find.text('Link Local GDD'), findsOneWidget);

          await tester.tap(
            find.byKey(const ValueKey('project_switcher_dropdown_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('SKYHOOK COURIER').first);
          await tester.pumpAndSettle();
          expect(wb.activeProjectId, equals(skyhookProjId));
          expect(find.text('● Live · $gddFilename'), findsOneWidget);

          // Remove blank Proj 2 via switcher delete confirmation dialog
          await tester.tap(
            find.byKey(const ValueKey('project_switcher_dropdown_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('switcher_delete_$blankProjId')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('confirm_delete_project_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.savedProjects, hasLength(1));

          // JSON export -> import dialog -> duplicate -> rename -> delete imported + duplicate cleanly
          final exportedJson = wb.exportProjectToJson();
          expect(exportedJson, contains('SKYHOOK COURIER'));

          await tester.tap(
            find.byKey(const ValueKey('project_switcher_dropdown_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('switcher_import_project_json_item')),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            ),
            exportedJson,
          );
          await tester.tap(find.text('Import Project'));
          await tester.pumpAndSettle();

          final importedProjId = wb.activeProjectId!;
          expect(importedProjId, isNot(equals(skyhookProjId)));
          expect(wb.savedProjects, hasLength(2));

          // Duplicate imported project via switcher
          await tester.tap(
            find.byKey(const ValueKey('project_switcher_dropdown_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('switcher_duplicate_$importedProjId')),
          );
          await tester.pumpAndSettle();
          final dupProjId = wb.activeProjectId!;
          expect(dupProjId, isNot(equals(importedProjId)));
          expect(wb.savedProjects, hasLength(3));

          // Rename duplicate via switcher dialog
          await tester.tap(
            find.byKey(const ValueKey('project_switcher_dropdown_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('switcher_rename_$dupProjId')),
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).last, 'TEMP BACKUP COPY');
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(wb.activeProject?.title, equals('TEMP BACKUP COPY'));

          // Delete both temp projects and confirm SKYHOOK COURIER restores active + Live GDD
          for (final tempId in <String>[dupProjId, importedProjId]) {
            await tester.tap(
              find.byKey(const ValueKey('project_switcher_dropdown_btn')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(ValueKey('switcher_delete_$tempId')));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('confirm_delete_project_btn')),
            );
            await tester.pumpAndSettle();
          }
          expect(wb.savedProjects, hasLength(1));
          expect(wb.activeProjectId, equals(skyhookProjId));
          expect(find.text('● Live · $gddFilename'), findsOneWidget);

          // 6) Launch Stage 2 (v0.1 C++ & BP Hybrid): check Source/ owners, UPROPERTY(EditAnywhere), AI error -> retry -> Undo, Preview DSL
          await tester.tap(
            find.byKey(const ValueKey('approve_launch_workbench_btn')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);
          expect(wb.activeReleaseVersionTag, equals('v0.1'));

          expect(
            wb.selectedEpicSpec!.sceneOwnership.any(
              (o) => o.path.contains('Source/SkyhookCourier/'),
            ),
            isTrue,
          );
          await tester.tap(find.byKey(const ValueKey('crumb_epic')));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Source/SkyhookCourier/SkyhookCharacter.h'),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('epic_inspect_first_feature_btn')),
          );
          await tester.pumpAndSettle();

          // Navigate to F02 (Skyhook Winch & Swing)
          await tester.tap(find.byKey(const ValueKey('outliner_feature_sk_f02')));
          await tester.pumpAndSettle();
          expect(
            find.text('Exposed Tuning (UPROPERTY(EditAnywhere) Var)'),
            findsOneWidget,
          );
          expect(find.byType(Slider), findsNothing);

          // Stage 2 AI Dock HTTP 400 preserves prompt -> re-submit succeeds -> Undo reverts
          const stage2RefinePrompt = 'Double WinchPullSpeed to 2600 cm/s';
          await tester.enterText(
            find.byKey(const ValueKey('stage2_ai_refine_input')),
            stage2RefinePrompt,
          );
          await tester.tap(
            find.byKey(const ValueKey('stage2_ai_refine_apply_btn')),
          );
          await tester.pumpAndSettle();

          expect(
            find.textContaining('Simulated Stage 2 refine error'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('stage2_ai_refine_input')),
                )
                .controller!
                .text,
            equals(stage2RefinePrompt),
          );

          failStage2Refine = false;
          await tester.tap(
            find.byKey(const ValueKey('stage2_ai_refine_apply_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.selectedFeatureSpec!.tuning
                .firstWhere((t) => t.key == 'WinchPullSpeed')
                .value,
            equals('2600'),
          );

          await tester.tap(
            find.byKey(const ValueKey('stage2_ai_refine_undo_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.selectedFeatureSpec!.tuning
                .firstWhere((t) => t.key == 'WinchPullSpeed')
                .value,
            equals('1300'),
          );

          // Preview CoPilot Prompt modal verifies C++ self-healing @OWNERS & 0 AI tokens spent
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('preview_copilot_prompt_btn')),
          );
          expect(
            find.textContaining('create missing @OWNERS if absent, else extend existing'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Source/SkyhookCourier/'),
            findsWidgets,
          );
          expect(
            find.textContaining('Compiled locally in memory (0 AI tokens spent by LAYERS)'),
            findsOneWidget,
          );
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();

          // 7) Complete v0.1 -> v0.2 ([+DELTA] F02 + [+NEW] F06) -> Complete v0.2 -> v0.3 ([+DELTA] F03 + [+NEW] F07)
          await _passAllFeaturesInRelease(tester, wb, 'v0.1');
          expect(
            find.byKey(const ValueKey('release_complete_banner')),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const ValueKey('plan_next_release_btn')));
          await tester.pumpAndSettle();
          await _ensureCheckboxSelected(
            tester,
            find.byKey(const ValueKey('copilot_up_up_sk_winch')),
          );
          await _ensureCheckboxSelected(
            tester,
            find.byKey(const ValueKey('copilot_new_feat_sk_f06_thermal')),
          );
          await tester.tap(find.byKey(const ValueKey('copilot_commit_btn')));
          await tester.pumpAndSettle();
          expect(wb.activeReleaseVersionTag, equals('v0.2'));
          final v02ReleaseId = wb.activeReleaseId!;

          await _passAllFeaturesInRelease(tester, wb, 'v0.2');
          expect(
            find.byKey(const ValueKey('release_complete_banner')),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const ValueKey('plan_next_release_btn')));
          await tester.pumpAndSettle();
          await _ensureCheckboxSelected(
            tester,
            find.byKey(const ValueKey('copilot_up_up_sk_glide_boost')),
          );
          await _ensureCheckboxSelected(
            tester,
            find.byKey(const ValueKey('copilot_new_feat_sk_f07_slipstream')),
          );
          await tester.tap(find.byKey(const ValueKey('copilot_commit_btn')));
          await tester.pumpAndSettle();
          expect(wb.activeReleaseVersionTag, equals('v0.3'));
          final v03ReleaseId = wb.activeReleaseId!;

          // 8) Verify locked [v0.1] & locked [v0.2] baseline jumps inside v0.3 + Light theme + Stage 1 Sync Return to v0.3
          final e01InV03 = wb.activeReleaseEpics.firstWhere(
            (e) => e.lineageKey.toLowerCase() == 'e01',
          );
          if (find
              .byKey(const ValueKey('outliner_feature_sk_f01'))
              .evaluate()
              .isEmpty) {
            await tester.tap(
              find.byKey(ValueKey('outliner_epic_toggle_${e01InV03.id}')),
            );
            await tester.pumpAndSettle();
          }
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('outliner_feature_sk_f01')),
          );
          expect(
            find.byKey(const ValueKey('locked_baseline_banner')),
            findsOneWidget,
          );
          expect(find.text('Open in v0.1 →'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('open_in_baseline_btn')));
          await tester.pumpAndSettle();
          expect(wb.activeReleaseVersionTag, equals('v0.1'));

          await tester.tap(find.byKey(ValueKey('outliner_release_$v03ReleaseId')));
          await tester.pumpAndSettle();
          expect(wb.activeReleaseVersionTag, equals('v0.3'));

          if (find
              .byKey(const ValueKey('outliner_feature_sk_f06_thermal'))
              .evaluate()
              .isEmpty) {
            await tester.tap(
              find.byKey(ValueKey('outliner_epic_toggle_${e01InV03.id}')),
            );
            await tester.pumpAndSettle();
          }
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('outliner_feature_sk_f06_thermal')),
          );
          expect(
            find.byKey(const ValueKey('locked_baseline_banner')),
            findsOneWidget,
          );
          expect(find.text('Open in v0.2 →'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('open_in_baseline_btn')));
          await tester.pumpAndSettle();
          expect(wb.activeReleaseId, equals(v02ReleaseId));
          expect(wb.activeReleaseVersionTag, equals('v0.2'));

          await tester.tap(find.byKey(ValueKey('outliner_release_$v03ReleaseId')));
          await tester.pumpAndSettle();
          expect(wb.activeReleaseVersionTag, equals('v0.3'));

          // Switch to Light theme on v0.3 at 1920x1080 -> zero overflows
          await tester.tap(find.byTooltip('Toggle Theme'));
          await tester.pumpAndSettle();
          expect(wb.isDark, isFalse);

          // Stage 1 return -> confirm Sync Spec & Return to v0.3 -> edit pitch -> click CTA -> return to v0.3
          await tester.tap(find.byKey(const ValueKey('nav_stage_1_btn')));
          await tester.pumpAndSettle();
          expect(find.byType(ProjectPitchScreen), findsOneWidget);
          expect(
            find.text('Sync Spec & Return to v0.3 →'),
            findsOneWidget,
          );

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_edit_pitch_btn')),
          );
          const updatedPitch =
              'Rooftop hook courier — sling parcels through wind tunnels cleanly';
          await tester.enterText(
            find.byKey(const ValueKey('stage1_pitch_input')),
            updatedPitch,
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_pitch_save_btn')),
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('approve_launch_workbench_btn')),
          );
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();

          expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);
          expect(wb.activeReleaseVersionTag, equals('v0.3'));
          expect(wb.conceptDraft?.pitch, equals(updatedPitch));
          expect(fakeGddBackend.writtenContents.last, contains(updatedPitch));
        });
      },
    );
  });
}

Future<void> _ensureCheckboxSelected(
  WidgetTester tester,
  Finder checkboxFinder,
) async {
  expect(checkboxFinder, findsOneWidget);
  if (!tester.widget<CheckboxListTile>(checkboxFinder).value!) {
    await _tapVisible(tester, checkboxFinder);
  }
}

Future<void> _passAllFeaturesInRelease(
  WidgetTester tester,
  WorkbenchProvider wb,
  String releaseVer,
) async {
  while (!wb.isActiveReleaseComplete) {
    final feat = wb.selectedFeatureSpec;
    if (feat == null || feat.isPassedForRelease(releaseVer)) {
      final jumped = wb.selectNextOpenFeature();
      expect(jumped, isTrue);
      await tester.pumpAndSettle();
      continue;
    }
    for (final chk in feat.effectiveChecksForRelease(releaseVer)) {
      if (!chk.passed) {
        await _tapVisible(
          tester,
          find.byKey(ValueKey('feature_check_${chk.id}')),
        );
      }
    }
    await _tapVisible(tester, find.byKey(const ValueKey('pass_feature_btn')));
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _runWith1080pViewport(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  final prevOnError = FlutterError.onError;
  final caughtErrors = <String>[];
  FlutterError.onError = (details) {
    caughtErrors.add(details.toString());
  };
  try {
    await body();
  } finally {
    FlutterError.onError = prevOnError;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
  expect(caughtErrors, isEmpty, reason: caughtErrors.join('\n---\n'));
}

void _installScratchHooks({
  required _ScratchMemoryVaultBackend memoryVault,
  required http.Response Function(Uri uri, Map<String, dynamic> body)
      onGeminiCall,
}) {
  GeminiAgentClient.resetCapabilityCacheForTest();
  GeminiAgentClient.resetUsage();
  GeminiAgentClient.testMockResponder = null;
  GeminiAgentClient.testBaseRetryDelay = Duration.zero;
  LocalVaultService.testBackendOverride = memoryVault;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') return null;
    if (call.method == 'Clipboard.getData') return const <String, dynamic>{};
    return null;
  });

  GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
    final decoded = (body is String && body.isNotEmpty)
        ? jsonDecode(body) as Map<String, dynamic>
        : const <String, dynamic>{};
    return onGeminiCall(uri, decoded);
  };

  addTearDown(() {
    GeminiAgentClient.testHttpPost = null;
    GeminiAgentClient.testMockResponder = null;
    GeminiAgentClient.testBaseRetryDelay = null;
    GeminiAgentClient.resetCapabilityCacheForTest();
    GeminiAgentClient.resetUsage();
    LocalVaultService.testBackendOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

http.Response _geminiFunctionResponse({
  required String modelVersion,
  required int inputTokens,
  required int outputTokens,
  required int thinkingTokens,
  required String toolName,
  required Map<String, dynamic> args,
}) {
  return http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'modelVersion': modelVersion,
        'usageMetadata': {
          'promptTokenCount': inputTokens,
          'candidatesTokenCount': outputTokens,
          'thoughtsTokenCount': thinkingTokens,
        },
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'name': toolName,
                    'args': args,
                  },
                },
              ],
            },
          },
        ],
      }),
    ),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, dynamic> _skyhookRootSpecPayload() => <String, dynamic>{
      'gameTitle': 'SKYHOOK COURIER',
      'architectureMode': 'cppHybrid',
      'pitch':
          'High-speed rooftop courier — launch grappling hooks and glide parcels across skyline gaps',
      'coreLoop': <String>[
        '1. Aim at rooftop crane anchor -> fire Skyhook grapple.',
        '2. Pump winch pull -> fling into high-speed glider dive.',
        '3. Swoop through landing pad -> stamp Courier Parcel and bank time.',
      ],
      'cameraChoiceId': 'tps',
      'cameraContract':
          'Third-person pursuit (USpringArmComponent 420 cm, FOV 95 deg) tracking aerial dive vector.',
      'characterScale':
          'ACourierCharacter capsule 92 cm half-height, 36 cm radius, MaxWalkSpeed 720 cm/s.',
      'inputContract':
          'IMC_Skyhook: IA_Move (WASD), IA_Look (Mouse), IA_Grapple (LMB), IA_Glide (Space Hold), IA_BoostDive (Shift).',
      'assetPolicy':
          'Source/SkyhookCourier/ C++ ASkyhookCharacter + UGrappleComponent UPROPERTY(EditAnywhere) exposed to thin BP_SkyhookCourier.',
      'cameraDecisionOptions': <Map<String, dynamic>>[
        {
          'id': 'tps',
          'label': 'Wide Dive Pursuit (Default)',
          'contractValue':
              'Third-person pursuit (USpringArmComponent 420 cm, FOV 95 deg) tracking aerial dive vector.',
        },
        {
          'id': 'shoulder_tight',
          'label': 'Tight Grapple Aim',
          'contractValue':
              'Over-shoulder grapple aim (320 cm offset shoulder arm, FOV 84 deg) for pinpoint anchor snaps.',
        },
      ],
      'feelChoiceId': 'snappy',
      'pillars': <String>[
        'Never lose forward momentum',
        'Every anchor reads cleanly against the skyline',
      ],
      'tradeOffs': <Map<String, dynamic>>[
        {
          'prefer': 'Snappy Grapple Assist',
          'avoid': 'Punishing Pixel Misses',
        },
      ],
      'outOfScope': <String>[
        'No multiplayer delivery races',
        'No procedural city generator',
      ],
      'releaseDoneWhen':
          'Open /Game/Maps/Lvl_SkylineCourse.umap -> chain 2 hooks and stamp landing pad cleanly',
      'initialEpics': <Map<String, dynamic>>[
        <String, dynamic>{
          'code': 'E01',
          'lineageKey': 'e01',
          'title': 'Skyhook Grapple & Swing',
          'coreLoopBeat': 'Beat 1-2 · Grapple Aim, Winch Pull & Release Swing',
          'goal':
              'Drive C++ grapple raycast, cable pull impulse, and aerial release momentum cleanly across gaps.',
          'inScope': <String>[
            'ACourierCharacter grapple trace and anchor lock',
            'UGrappleComponent spring pull and tangent release',
          ],
          'doneWhen': <String>[
            'Aim at AnchorPoint -> grapple snaps cleanly and flings mech over gap',
          ],
          'sceneOwnership': <Map<String, dynamic>>[
            {
              'path': 'Source/SkyhookCourier/SkyhookCharacter.h',
              'role': 'Base C++ character and UPROPERTY movement contract',
            },
            {
              'path': 'Source/SkyhookCourier/GrappleComponent.cpp',
              'role': 'Raycast lock, winch impulse, and release arc',
            },
            {
              'path': '/Game/Blueprints/BP_SkyhookCourier',
              'role': 'Thin Blueprint subclass binding meshes and Niagara',
            },
          ],
          'states': <String>['Airborne -> GrappleLock -> WinchPull -> SlingRelease'],
          'interrupts': <String>[
            'Release LMB mid-pull preserves exit velocity vector cleanly',
          ],
          'outOfScope': <String>['No dual-handed tether combat'],
          'features': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'sk_f01',
              'code': 'F01',
              'title': 'Courier Locomotion & Shoulder Aim',
              'sliceTime': '45 min',
              'goal':
                  'Move ACourierCharacter cleanly across rooftops with smooth reticle trace.',
              'inScope': <String>['WASD sprint move and jump buffer'],
              'doneWhen': <String>[
                'Run off crane ledge -> coyote jump fires cleanly across 400 cm gap',
              ],
              'controls': <Map<String, dynamic>>[
                {
                  'action': 'IA_Move',
                  'trigger': 'Ongoing',
                  'rule': 'Steers ACourierCharacter at MaxWalkSpeed 720 cm/s',
                },
              ],
              'tuning': <Map<String, dynamic>>[
                {'key': 'WalkSpeed', 'value': '720', 'unit': 'cm/s'},
                {'key': 'CoyoteTime', 'value': '0.14', 'unit': 's'},
              ],
              'cues': <String>['Footstep dust puff plays on rooftop sprint'],
              'checks': <Map<String, dynamic>>[
                {
                  'text':
                      'Sprint to rooftop edge and press Space -> Jumps cleanly off ledge',
                },
              ],
            },
            <String, dynamic>{
              'id': 'sk_f02',
              'code': 'F02',
              'title': 'Skyhook Winch & Swing',
              'sliceTime': '60 min',
              'goal':
                  'Snap LMB Skyhook cable to illuminated rooftop anchors and reel mech forward.',
              'inScope': <String>['2800 cm cone trace and cable pull impulse'],
              'doneWhen': <String>[
                'Hold IA_Grapple on lit crane -> Reels forward at 1300 cm/s cleanly',
              ],
              'controls': <Map<String, dynamic>>[
                {
                  'action': 'IA_Grapple',
                  'trigger': 'Started / Completed',
                  'rule': 'Attaches cable to nearest valid anchor within 2800 cm',
                },
              ],
              'tuning': <Map<String, dynamic>>[
                {'key': 'MaxHookRange', 'value': '2800', 'unit': 'cm'},
                {'key': 'WinchPullSpeed', 'value': '1300', 'unit': 'cm/s'},
              ],
              'cues': <String>['Taut cyan cable spline snaps with metallic winch clack'],
              'checks': <Map<String, dynamic>>[
                {
                  'text':
                      'Press LMB aiming near anchor -> Cable attaches and pulls toward tower',
                },
              ],
            },
          ],
        },
        <String, dynamic>{
          'code': 'E02',
          'lineageKey': 'e02',
          'title': 'Wingsuit Glide & Parcel Drop',
          'coreLoopBeat': 'Beat 2-3 · Wingsuit Dive & Rooftop Delivery Stamp',
          'goal':
              'Convert downward fall speed into forward wingsuit glide lift and trigger crisp Parcel Delivery stamps.',
          'inScope': <String>[
            'UGlideStateComponent lift-to-speed curve',
            'AParcelDropZone landing pad trigger and WBP timer HUD',
          ],
          'doneWhen': <String>[
            'Glide onto lit ParcelDropZone -> Delivery stamps +30 s bonus cleanly',
          ],
          'sceneOwnership': <Map<String, dynamic>>[
            {
              'path': 'Source/SkyhookCourier/GlideMovementComponent.cpp',
              'role': 'Dive-to-lift pitch conversion and terminal air speed',
            },
            {
              'path': '/Game/Blueprints/BP_ParcelDropZone',
              'role': 'Beacon ring trigger and delivery chime feedback',
            },
          ],
          'states': <String>['Freefall -> WingsuitOpen -> BoostDive -> ParcelDelivered'],
          'interrupts': <String>[
            'Opening Skyhook cancels Wingsuit immediately without velocity clip',
          ],
          'outOfScope': <String>['No fragile parcel physics damage'],
          'features': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'sk_f03',
              'code': 'F03',
              'title': 'Wingsuit Glide & Boost Dive',
              'sliceTime': '45 min',
              'goal':
                  'Hold Space mid-air to spread wingsuit and convert dive pitch into forward speed.',
              'inScope': <String>['Glide drag curve and Shift dive pitch'],
              'doneWhen': <String>[
                'Hold Space in freefall -> Mech glides forward smoothly between skyscrapers',
              ],
              'controls': <Map<String, dynamic>>[
                {
                  'action': 'IA_Glide',
                  'trigger': 'Ongoing',
                  'rule': 'Locks vertical drop and accelerates glide airspeed',
                },
              ],
              'tuning': <Map<String, dynamic>>[
                {'key': 'GlideCruiseSpeed', 'value': '1600', 'unit': 'cm/s'},
              ],
              'cues': <String>['Wingtip air trails shimmer above 1400 cm/s'],
              'checks': <Map<String, dynamic>>[
                {
                  'text':
                      'Hold Space mid-air -> Wings open and horizontal speed rises smoothly',
                },
              ],
            },
            <String, dynamic>{
              'id': 'sk_f04',
              'code': 'F04',
              'title': 'Parcel Drop Beacon & Timer',
              'sliceTime': '45 min',
              'goal':
                  'Touch rooftop BP_ParcelDropZone ring to stamp parcel delivery and add course time.',
              'inScope': <String>['Drop trigger, time bonus, and WBP delivery counter'],
              'doneWhen': <String>[
                'Land inside beacon ring -> Parcel Delivered toast flashes and timer adds 15 s',
              ],
              'controls': <Map<String, dynamic>>[
                {
                  'action': 'IA_QuickReset',
                  'trigger': 'Started (R)',
                  'rule': 'Resets courier to rooftop start pad in 1 frame',
                },
              ],
              'tuning': <Map<String, dynamic>>[
                {'key': 'CourseTimerS', 'value': '60', 'unit': 's'},
              ],
              'cues': <String>['Emerald beacon burst + brass stamp SFX on touch'],
              'checks': <Map<String, dynamic>>[
                {
                  'text':
                      'Swoop into drop beacon -> Delivery counter increments cleanly',
                },
              ],
            },
          ],
        },
      ],
    };

Map<String, dynamic> _v02ProgressivePayload() => <String, dynamic>{
      'presets': <Map<String, dynamic>>[
        {
          'id': 'air_flow',
          'label': 'Aerial Flow Pass',
          'desc': 'Add winch apex sling boost and thermal updraft rings inside E01.',
          'upgrades': <String>['up_sk_winch'],
          'newFeatures': <String>['sk_f06_thermal'],
          'newEpics': <String>[],
        },
      ],
      'upgrades': <Map<String, dynamic>>[
        {
          'lineageKey': 'e01',
          'options': <Map<String, dynamic>>[
            {
              'id': 'up_sk_winch',
              'targetFeatureCode': 'F02',
              'text': '+Apex tangent sling boost when releasing IA_Grapple early',
              'chosen': false,
            },
          ],
        },
      ],
      'newFeatures': <Map<String, dynamic>>[
        {
          'lineageKey': 'e01',
          'features': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'sk_f06_thermal',
              'code': 'F06',
              'title': 'Rooftop Thermal Updraft',
              'sliceTime': '45 min',
              'goal':
                  'Place vertical AC vent updraft volumes launching wingsuits upward cleanly.',
              'inScope': <String>['AC thermal volume + vertical boost force'],
              'doneWhen': <String>[
                'Glide over lit rooftop vent -> Courier rises 900 cm smoothly',
              ],
              'controls': <Map<String, dynamic>>[],
              'tuning': <Map<String, dynamic>>[
                {'key': 'ThermalLiftSpeed', 'value': '950', 'unit': 'cm/s'},
              ],
              'cues': <String>['Rising cyan heat distortion rings shimmer above AC vent'],
              'checks': <Map<String, dynamic>>[
                {
                  'text':
                      'Enter thermal plume while gliding -> Altitude climbs 900 cm cleanly',
                },
              ],
            },
          ],
        },
      ],
      'newEpics': const <Map<String, dynamic>>[],
    };

Map<String, dynamic> _v03ProgressivePayload() => <String, dynamic>{
      'presets': <Map<String, dynamic>>[
        {
          'id': 'slipstream',
          'label': 'Skyline Slipstream Pass',
          'desc': 'Upgrade Boost Dive lift curve and add Drone Slipstream Rings in E02.',
          'upgrades': <String>['up_sk_glide_boost'],
          'newFeatures': <String>['sk_f07_slipstream'],
          'newEpics': const <Map<String, dynamic>>[],
        },
      ],
      'upgrades': <Map<String, dynamic>>[
        {
          'lineageKey': 'e02',
          'options': <Map<String, dynamic>>[
            {
              'id': 'up_sk_glide_boost',
              'targetFeatureCode': 'F03',
              'text': '+High-G dive exit flare granting 2200 cm/s glide burst',
              'chosen': false,
            },
          ],
        },
      ],
      'newFeatures': <Map<String, dynamic>>[
        {
          'lineageKey': 'e02',
          'features': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'sk_f07_slipstream',
              'code': 'F07',
              'title': 'Cargo Drone Slipstream',
              'sliceTime': '60 min',
              'goal':
                  'Follow cargo drone wake tunnels for 2400 cm/s slipstream draft speed.',
              'inScope': <String>['Spline cargo drone + trailing slipstream wake'],
              'doneWhen': <String>[
                'Fly through drone wake tunnel -> Speed hits 2400 cm/s with tunnel ribbons',
              ],
              'controls': <Map<String, dynamic>>[],
              'tuning': <Map<String, dynamic>>[
                {'key': 'SlipstreamSpeed', 'value': '2400', 'unit': 'cm/s'},
              ],
              'cues': <String>['Gold slipstream ring pulses around drone tail wake'],
              'checks': <Map<String, dynamic>>[
                {
                  'text':
                      'Fly inside cargo drone wake -> Airspeed boosts to 2400 cm/s cleanly',
                },
              ],
            },
          ],
        },
      ],
      'newEpics': const <Map<String, dynamic>>[],
    };

class _ScratchMemoryVaultBackend implements VaultStorageBackend {
  final Map<String, TierDocument> savedDocs = <String, TierDocument>{};

  @override
  Future<VaultLoadResult> loadVaultData() async =>
      const VaultLoadResult(documents: <String, TierDocument>{});

  @override
  Future<void> saveSettings({
    required String activeDocumentId,
    String? apiKey,
    String? modelName,
    String? planningModel,
    String? thinkingLevel,
    String? themeMode,
  }) async {}

  @override
  Future<void> saveDocument(TierDocument doc) async {
    savedDocs[doc.id] = doc;
  }

  @override
  Future<void> deleteDocument(String id) async {
    savedDocs.remove(id);
  }
}

class _ScratchLocalGddBackend implements LocalGddFileBackend {
  final Map<String, String> linkedHandles = <String, String>{};
  final List<String> writtenContents = <String>[];

  @override
  bool get isSupported => true;

  @override
  Future<LocalGddLinkResult> pickAndWriteFile({
    required String projectId,
    required String suggestedFilename,
    required String content,
  }) async {
    linkedHandles[projectId] = suggestedFilename;
    writtenContents.add(content);
    return LocalGddLinkResult(linked: true, filename: suggestedFilename);
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
    if (!linkedHandles.containsKey(projectId)) {
      return const LocalGddWriteResult(written: false);
    }
    writtenContents.add(content);
    return const LocalGddWriteResult(written: true);
  }

  @override
  Future<void> unlinkProject(String projectId) async {
    linkedHandles.remove(projectId);
  }
}
