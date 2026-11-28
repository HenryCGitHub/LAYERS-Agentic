import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:layers_agentic/agents/gemini_agent_client.dart';
import 'package:layers_agentic/constants/tiers.dart';
import 'package:layers_agentic/main.dart';
import 'package:layers_agentic/models/epic_spec.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';
import 'package:layers_agentic/screens/release_workbench_screen.dart';
import 'package:layers_agentic/screens/shell/studio_top_bar.dart';
import 'package:layers_agentic/screens/stage1/stage1_idea_angles_card.dart';
import 'package:layers_agentic/screens/workbench/monday_release_table.dart';
import 'package:layers_agentic/screens/workbench/plain_plan_release_page.dart';
import 'package:layers_agentic/screens/workbench/release_spec_sheet.dart';
import 'package:layers_agentic/services/local_vault_service.dart';
import 'package:layers_agentic/services/storage/vault_storage_interface.dart';

void main() {
  group('Flat 2-Pane Plain Document UI Widget Suite', () {
    testWidgets(
      '40px flat header shows Project switcher, release links, GDD ▾ & Settings ▾ toggles without legacy chrome',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        _installPlainTestHooks(
          vault: vault,
          onGeminiCall: (_, body) {
            return _mockGeminiFunctionResponse(
              modelVersion: 'gemini-4-hydrogen',
              inputTokens: 1200,
              outputTokens: 300,
              thinkingTokens: 80,
              toolName: 'patch_unreal_release_spec',
              args: <String, dynamic>{
                'title': 'v0.1 · Arena Core Slice',
                'summary': 'Tightened release title',
              },
            );
          },
        );

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..updateAiConfig(apiKey: 'AIzaPlainTestHeaderKey')
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);
          final v01Id = wb.approveRootSpecAndLaunchWorkbench()!;

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // Strictly 40px flat top bar without stage pills or Idea tab.
          final headerSize = tester.getSize(find.byType(StudioTopBar));
          expect(headerSize.height, equals(40.0));
          expect(find.text('LAYERS'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('project_switcher_dropdown_btn')),
            findsOneWidget,
          );
          expect(
            find.byKey(ValueKey('header_release_$v01Id')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('plan_next_release_btn')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('header_gdd_menu_btn')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('header_settings_menu_btn')),
            findsOneWidget,
          );
          expect(find.text('1. Plan'), findsNothing);
          expect(find.text('2. Build'), findsNothing);
          expect(find.text('Idea'), findsNothing);

          // Trigger a token-tracked Gemini call so Usage Reset can be verified inside Settings ▾.
          await wb.applyStage2ReleaseRefine(v01Id, 'Rename to Arena Core Slice');
          await tester.pumpAndSettle();
          expect(wb.totalInputTokens, greaterThan(0));

          // Settings ▾ menu: Architecture mode, Theme toggle, Cloud Vault, AI Models & Usage Reset.
          await tester.tap(
            find.byKey(const ValueKey('header_settings_menu_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('settings_arch_blueprint')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('settings_arch_cpp_hybrid')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('cloud_sync_auth_btn')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('active_model_indicator_pill')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('token_usage_tracker_pill')),
            findsOneWidget,
          );

          // Reset token usage (closeOnActivate: false).
          await tester.tap(
            find.byKey(const ValueKey('token_usage_tracker_pill')),
          );
          await tester.pumpAndSettle();
          expect(wb.totalInputTokens, equals(0));
          expect(wb.totalOutputTokens, equals(0));

          // Toggle theme Dark -> Light -> Dark (closeOnActivate: false).
          expect(wb.isDark, isTrue);
          await tester.tap(
            find.byKey(const ValueKey('settings_theme_toggle_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.isDark, isFalse);
          await tester.tap(
            find.byKey(const ValueKey('settings_theme_toggle_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.isDark, isTrue);

          // Toggle Architecture mode to C++ & BP Hybrid (closes MenuAnchor on tap).
          await tester.tap(
            find.byKey(const ValueKey('settings_arch_cpp_hybrid')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.unrealArchitectureMode,
            equals(UnrealArchitectureMode.cppHybrid),
          );

          await tester.tap(
            find.byKey(const ValueKey('header_settings_menu_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('settings_arch_blueprint')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.unrealArchitectureMode,
            equals(UnrealArchitectureMode.blueprint),
          );
        });
      },
    );

    testWidgets(
      'GDD ▾ reflects unlinked, synced, permissionNeeded & error states with Inspect GDD and Unlink',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        final gddBackend = _PlainLocalGddBackend();
        _installPlainTestHooks(vault: vault);

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..setLocalGddBackendForTest(gddBackend)
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);
          wb.approveRootSpecAndLaunchWorkbench();

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // 1) Unlinked
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.unlinked));
          expect(find.text('GDD ▾'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('header_gdd_menu_btn')));
          await tester.pumpAndSettle();
          expect(find.text('Link Local GDD…'), findsOneWidget);

          // 2) Link -> synced
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.synced));
          expect(find.text('GDD ▾'), findsOneWidget);

          await tester.tap(find.byKey(const ValueKey('header_gdd_menu_btn')));
          await tester.pumpAndSettle();
          expect(
            find.text('File: shellbreaker_copilot_gdd.md'),
            findsOneWidget,
          );
          expect(find.text('Sync Linked GDD Now'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('gdd_menu_unlink_btn')),
            findsOneWidget,
          );

          // Open GDD Inspector modal
          await tester.tap(
            find.byKey(const ValueKey('top_bar_copilot_gdd_btn')),
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

          // 3) permissionNeeded -> amber Grant GDD ▾ -> Grant GDD Write Permission recovers
          gddBackend.denyPermission = true;
          expect(await wb.syncLinkedGddNow(force: true), isFalse);
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.permissionNeeded));
          expect(find.text('Grant GDD ▾'), findsOneWidget);

          gddBackend.denyPermission = false;
          await tester.tap(find.byKey(const ValueKey('header_gdd_menu_btn')));
          await tester.pumpAndSettle();
          expect(find.text('Grant GDD Write Permission'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.synced));
          expect(gddBackend.lastRequestPermissionFlag, isTrue);

          // 4) error -> red GDD Error ▾ -> Retry recovers -> Unlink
          gddBackend.errorMessage = 'Simulated disk write failure';
          expect(await wb.syncLinkedGddNow(force: true), isFalse);
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.error));
          expect(find.text('GDD Error ▾'), findsOneWidget);

          gddBackend.errorMessage = null;
          await tester.tap(find.byKey(const ValueKey('header_gdd_menu_btn')));
          await tester.pumpAndSettle();
          expect(find.text('Simulated disk write failure'), findsOneWidget);
          expect(find.text('Retry Local GDD Sync'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.synced));

          await tester.tap(find.byKey(const ValueKey('header_gdd_menu_btn')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('gdd_menu_unlink_btn')));
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.unlinked));
        });
      },
    );

    testWidgets(
      '240px 4-tier left outline shows Project Brief -> Release -> Epics -> Features, + Add slice autofocuses title, and + New Game ← Back cancels cleanly',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        _installPlainTestHooks(vault: vault);

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);
          final firstProjId = wb.activeProjectId!;
          final v01Id = wb.approveRootSpecAndLaunchWorkbench(
            openReleaseSpec: true,
          )!;
          final e01 = wb.activeReleaseEpics.first;

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // 2-screen workstation (no left rail): top bar Brief | v0.1 + MondayReleaseTable.
          expect(find.byType(MondayReleaseTable), findsOneWidget);
          expect(
            find.byKey(const ValueKey('header_project_brief_btn')),
            findsOneWidget,
          );
          expect(
            find.byKey(ValueKey('header_release_$v01Id')),
            findsOneWidget,
          );
          expect(
            find.byKey(ValueKey('table_epic_open_${e01.id}')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('table_feature_row_sb_f01')),
            findsOneWidget,
          );
          expect(find.text('Idea'), findsNothing);
          expect(find.text('+ Add feature'), findsOneWidget);
          expect(find.text('+ Add slice'), findsNothing);

          // + Add feature in Release header creates a feature, opens Overlay, and auto-focuses feature_title_input.
          final countBefore = wb.activeReleaseEpics.first.features.length;
          await tester.tap(
            find.byKey(const ValueKey('release_quick_add_feature_btn')),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('workbench_overlay_dialog')),
            findsOneWidget,
          );
          expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);
          expect(
            wb.activeReleaseEpics.first.features.length,
            equals(countBefore + 1),
          );
          expect(
            find.byKey(const ValueKey('feature_title_input')),
            findsOneWidget,
          );
          final editableTitle = tester.widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('feature_title_input')),
              matching: find.byType(EditableText),
            ),
          );
          expect(editableTitle.focusNode.hasFocus, isTrue);

          // + New Game from switcher opens Idea/3-Angles with ← Back cancel returning to first project.
          await tester.tap(
            find.byKey(const ValueKey('project_switcher_dropdown_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('+ New Game'));
          await tester.pumpAndSettle();

          expect(wb.activeProjectId, isNot(equals(firstProjId)));
          expect(
            find.byKey(const ValueKey('new_game_cancel_btn')),
            findsOneWidget,
          );
          await wb.exploreSparkAngles('Co-op grapple dungeon crawler');
          await tester.pumpAndSettle();
          expect(find.byType(Stage1IdeaAnglesCard), findsOneWidget);

          await tester.tap(find.byKey(const ValueKey('new_game_cancel_btn')));
          await tester.pumpAndSettle();
          expect(wb.activeProjectId, equals(firstProjId));
          expect(find.byKey(const ValueKey('new_game_cancel_btn')), findsNothing);
        });
      },
    );

    testWidgets(
      'Clickable Release Spec (TierType.release) inline edits, + Add epic, AI Refine/Undo, Preview Spec & in-page + New Release v0.2 planning',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        _installPlainTestHooks(
          vault: vault,
          onGeminiCall: (_, body) {
            final promptStr = jsonEncode(body);
            if (promptStr.contains('patch_unreal_release_spec')) {
              return _mockGeminiFunctionResponse(
                modelVersion: 'gemini-4-hydrogen',
                inputTokens: 900,
                outputTokens: 250,
                thinkingTokens: 60,
                toolName: 'patch_unreal_release_spec',
                args: <String, dynamic>{
                  'goal': 'Ship tight claw dash and 3-wave arena combat loop.',
                  'summary': 'Focused v0.1 release goal on arena combat loop',
                },
              );
            }
            return http.Response('{"error": "fallback"}', 503);
          },
        );

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..updateAiConfig(apiKey: 'AIzaPlainTestHeaderKey')
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);
          final v01Id = wb.approveRootSpecAndLaunchWorkbench()!;

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // Click v0.1 Release link in top header -> ReleaseSpecSheet.
          await tester.tap(find.byKey(ValueKey('header_release_$v01Id')));
          await tester.pumpAndSettle();
          expect(wb.isInspectingReleaseSpec, isTrue);
          expect(find.byType(ReleaseSpecSheet), findsOneWidget);

          // Inline edit Title, Goal & Done When (commit on unfocus).
          await _enterAndUnfocus(
            tester,
            find.byKey(const ValueKey('release_title_input')),
            'v0.1 · Arena Combat Slice',
          );
          await _enterAndUnfocus(
            tester,
            find.byKey(const ValueKey('release_goal_input')),
            'Playable crab claw dash vs armored arena waves.',
          );
          await _enterAndUnfocus(
            tester,
            find.byKey(const ValueKey('release_done_when_input')),
            'Clear 3 waves in PIE -> Wave counter advances cleanly',
          );
          expect(wb.activeRelease!.title, equals('v0.1 · Arena Combat Slice'));
          expect(
            wb.activeRelease!.sections['goal'],
            equals('Playable crab claw dash vs armored arena waves.'),
          );
          expect(
            wb.activeRelease!.sections['doneWhen'],
            equals('Clear 3 waves in PIE -> Wave counter advances cleanly'),
          );

          // Preview Spec modal open & close.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('release_preview_spec_btn')),
          );
          expect(
            find.textContaining('Playable crab claw dash vs armored arena waves.'),
            findsWidgets,
          );
          await tester.tap(
            find.byKey(const ValueKey('close_copilot_preview_btn')),
          );
          await tester.pumpAndSettle();

          // + Add epic inside v0.1 In Scope.
          final epicCountBefore = wb.activeReleaseEpics.length;
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('release_add_epic_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('release_new_epic_title_input')),
            'Arena Hazards',
          );
          await tester.enterText(
            find.byKey(const ValueKey('release_new_epic_goal_input')),
            'Own floor spikes and thermal vents.',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('release_new_epic_save_btn')),
          );
          expect(
            wb.activeReleaseEpics.length,
            equals(epicCountBefore + 1),
          );
          expect(
            wb.activeReleaseEpics.last.title,
            equals('Arena Hazards'),
          );

          // Bottom 1-line AI Refine + Undo on ReleaseSpecSheet.
          await tester.enterText(
            find.byKey(const ValueKey('stage2_ai_refine_input')),
            'Focus Goal on core combat loop feel',
          );
          await tester.tap(
            find.byKey(const ValueKey('stage2_ai_refine_apply_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.activeRelease!.sections['goal'],
            equals('Ship tight claw dash and 3-wave arena combat loop.'),
          );

          await tester.tap(
            find.byKey(const ValueKey('stage2_ai_refine_undo_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.activeRelease!.sections['goal'],
            equals('Playable crab claw dash vs armored arena waves.'),
          );

          // Pass all v0.1 slices via provider helper to reach + New Release state cleanly,
          // then test in-page + New Release Planner (PlainPlanReleasePage, zero Dialog).
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('plan_next_release_btn')),
          );
          expect(find.byType(PlainPlanReleasePage), findsOneWidget);
          expect(find.byType(Dialog), findsNothing);

          await _enterAndUnfocus(
            tester,
            find.byKey(const ValueKey('plan_release_goal_input')),
            'Add combo momentum and elite wave stagger.',
          );
          expect(
            wb.progressiveDraft!.customGoal,
            equals('Add combo momentum and elite wave stagger.'),
          );

          // Cancel via ← Cancel returns back to v0.1 ReleaseSpecSheet.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('plan_release_cancel_btn')),
          );
          expect(wb.progressiveDraft, isNull);
          expect(find.byType(ReleaseSpecSheet), findsOneWidget);

          // Re-open + New, select +DELTA & +NEW, commit v0.2.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('plan_next_release_btn')),
          );
          final upFinder = find.byWidgetPredicate(
            (w) =>
                w is CheckboxListTile &&
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('copilot_up_'),
          );
          expect(upFinder, findsWidgets);
          if (!tester.widget<CheckboxListTile>(upFinder.first).value!) {
            await _tapVisible(tester, upFinder.first);
          }
          final newFeatFinder = find.byWidgetPredicate(
            (w) =>
                w is CheckboxListTile &&
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith(
                  'copilot_new_feat_',
                ),
          );
          expect(newFeatFinder, findsWidgets);
          if (!tester.widget<CheckboxListTile>(newFeatFinder.first).value!) {
            await _tapVisible(tester, newFeatFinder.first);
          }

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('copilot_commit_btn')),
          );
          expect(wb.activeReleaseVersionTag, equals('v0.2'));

          final v02Id = wb.activeReleaseId!;
          await tester.tap(find.byKey(ValueKey('header_release_$v02Id')));
          await tester.pumpAndSettle();
          expect(find.byType(MondayReleaseTable), findsOneWidget);
          expect(find.text('+DELTA'), findsWidgets);
          expect(find.text('+NEW v0.2'), findsWidgets);
          expect(
            find.textContaining('Locked v0.1 baseline (open in v0.1)'),
            findsWidgets,
          );
        });
      },
    );

    testWidgets(
      'PIE-first Feature Page: silent 1-click Copy, conditional Fixes, Playtest checks, Controls & semantic Table Tuning',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        _installPlainTestHooks(vault: vault);

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);
          wb.approveRootSpecAndLaunchWorkbench(openReleaseSpec: true);

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // Navigate to F02 via Monday table row.
          await tester.tap(
            find.byKey(const ValueKey('table_feature_row_sb_f02')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);

          // 1) Silent 1-click Copy flashes Copied (~N tok) with ZERO SnackBar, then resets after 2s.
          final overlayFinder = find.byKey(
            const ValueKey('workbench_overlay_dialog'),
          );
          expect(find.text('Copy CoPilot Prompt'), findsOneWidget);
          expect(
            find.descendant(
              of: overlayFinder,
              matching: find.byIcon(Icons.bolt_rounded),
            ),
            findsOneWidget,
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('copy_copilot_prompt_btn')),
          );
          expect(find.textContaining('Copied (~'), findsOneWidget);
          expect(
            find.descendant(
              of: overlayFinder,
              matching: find.byIcon(Icons.check_rounded),
            ),
            findsOneWidget,
          );
          expect(find.byType(SnackBar), findsNothing);
          await tester.pump(const Duration(seconds: 3));
          expect(find.text('Copy CoPilot Prompt'), findsOneWidget);

          // Preview DSL toggle Compact DSL <-> Readable View -> close.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('preview_copilot_prompt_btn')),
          );
          await tester.tap(
            find.byKey(const ValueKey('preview_mode_readable_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('preview_mode_compact_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('close_copilot_preview_btn')),
          );
          await tester.pumpAndSettle();

          // 2) Conditional Fixes hidden when 0 -> shown on Broken in PIE? -> hidden again on Resolve.
          expect(find.textContaining('FIXES ('), findsNothing);
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('flag_fix_input')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('flag_fix_input')),
            'Dash clips east arena step',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('flag_fix_btn')),
          );
          expect(find.textContaining('FIXES (1)'), findsOneWidget);
          expect(
            find.text('Copy CoPilot [FIX] Prompt (1)'),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: overlayFinder,
              matching: find.byIcon(Icons.build_outlined),
            ),
            findsOneWidget,
          );

          final fxId = wb.selectedFeatureSpec!.fixes.first.id;
          await _tapVisible(
            tester,
            find.byKey(ValueKey('resolve_fix_$fxId')),
          );
          expect(find.textContaining('FIXES ('), findsNothing);
          expect(find.text('Copy CoPilot Prompt'), findsOneWidget);

          // 3) Playtest (PIE) toggle & + Add check.
          final firstCheckId = wb.selectedFeatureSpec!.checks.first.id;
          final wasPassed = wb.selectedFeatureSpec!.checks.first.passed;
          await _tapVisible(
            tester,
            find.byKey(ValueKey('feature_check_$firstCheckId')),
          );
          expect(
            wb.selectedFeatureSpec!.checks.first.passed,
            equals(!wasPassed),
          );

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_add_check_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_check_input')),
            'Tap dash twice -> 1s cooldown blocks second dash',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_check_save_btn')),
          );
          expect(
            wb.selectedFeatureSpec!.checks.last.text,
            equals('Tap dash twice -> 1s cooldown blocks second dash'),
          );

          // 4) Inline Controls add + delete.
          final ctrlCountBefore = wb.selectedFeatureSpec!.controls.length;
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_add_control_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_control_action_input')),
            'dash_cancel',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_control_trigger_input')),
            'Started (RMB)',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_control_rule_input')),
            'Stops active dash cleanly',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_control_save_btn')),
          );
          expect(
            wb.selectedFeatureSpec!.controls.length,
            equals(ctrlCountBefore + 1),
          );
          await _tapVisible(
            tester,
            find.byKey(ValueKey('feature_control_delete_$ctrlCountBefore')),
          );
          expect(
            wb.selectedFeatureSpec!.controls.length,
            equals(ctrlCountBefore),
          );

          // 5) Semantic Table Tuning (zero Slider widgets) + Add var + inline edit + delete ×.
          expect(find.byType(Table), findsOneWidget);
          expect(find.byType(Slider), findsNothing);
          final f02Id = wb.selectedFeatureSpec!.id;
          final tuneCountBefore = wb.selectedFeatureSpec!.tuning.length;
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_add_tuning_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_tuning_key_input')),
            'ClawRecoveryTime',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_tuning_value_input')),
            '0.25',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_tuning_unit_input')),
            's',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_tuning_save_btn')),
          );
          expect(find.text('ClawRecoveryTime'), findsOneWidget);

          await _enterAndUnfocus(
            tester,
            find.byKey(ValueKey('tuning_input_${f02Id}_0')),
            '610',
          );
          expect(
            wb.selectedFeatureSpec!.tuning.first.value,
            equals('610'),
          );

          await _tapVisible(
            tester,
            find.byKey(ValueKey('tuning_delete_${f02Id}_$tuneCountBefore')),
          );
          expect(find.text('ClawRecoveryTime'), findsNothing);
        });
      },
    );

    testWidgets(
      'Zero layout overflows across Project Brief, Release Spec, Epic, Feature & Plan Release at 1280x800 and 640x800 (Dark & Light)',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        _installPlainTestHooks(vault: vault);

        const viewports = <Size>[Size(1280, 800), Size(640, 800)];
        for (final isDark in const <bool>[true, false]) {
          for (final size in viewports) {
            await _runWithViewport(tester, size, () async {
              final wb = WorkbenchProvider(enableAutoLoad: false)
                ..loadPresetSpark('shellbreaker');
              addTearDown(wb.dispose);
              if (!isDark) wb.toggleTheme();
              wb.approveRootSpecAndLaunchWorkbench();
              wb.selectReleaseSpec();
              final e01 = wb.activeReleaseEpics.first;
              final f02 = e01.features.firstWhere((f) => f.code == 'F02');

              await tester.pumpWidget(LayersAgenticApp(provider: wb));
              await tester.pumpAndSettle();

              // Monday Release Table
              expect(find.byType(ReleaseSpecSheet), findsOneWidget);
              expect(find.byType(MondayReleaseTable), findsOneWidget);

              // Project Brief
              wb.selectProjectBrief();
              await tester.pumpAndSettle();

              // Epic Domain Overlay
              wb.selectEpic(e01.id);
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('workbench_overlay_dialog')),
                findsOneWidget,
              );

              // Feature Overlay
              wb.selectFeature(e01.id, f02.id);
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('workbench_overlay_dialog')),
                findsOneWidget,
              );

              // Plan Next Release
              wb.openInPagePlanNextRelease();
              await tester.pumpAndSettle();
              expect(find.byType(PlainPlanReleasePage), findsOneWidget);

              expect(tester.takeException(), isNull);
            });
          }
        }
      },
    );

    testWidgets(
      'UX regression fixes: deduplicated release labels, hidden + Add slice before release, zero v0.1 delta leak, distinct v0.2 Done When, honest unfinished baseline status, E04+E05 commit & cleared navigation banner',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        _installPlainTestHooks(vault: vault);

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // 1) Before any release is launched, + Add feature action is hidden cleanly.
          expect(
            find.byKey(const ValueKey('release_quick_add_feature_btn')),
            findsNothing,
          );

          // Launch v0.1 -> lands on Monday Release Table with deduplicated title.
          final v01Id = wb.approveRootSpecAndLaunchWorkbench(
            openReleaseSpec: true,
          )!;
          await tester.pumpAndSettle();
          expect(find.byType(MondayReleaseTable), findsOneWidget);
          expect(find.text('v0.1 · Prototype'), findsOneWidget);
          expect(find.textContaining('v0.1 · v0.1'), findsNothing);

          // GDD Inspector close icon button carries an accessible tooltip.
          await tester.tap(find.byKey(const ValueKey('header_gdd_menu_btn')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('top_bar_copilot_gdd_btn')),
          );
          await tester.pumpAndSettle();
          final closeGddBtn = tester.widget<IconButton>(
            find.byKey(const ValueKey('close_gdd_inspector_btn')),
          );
          expect(closeGddBtn.tooltip, equals('Close GDD Inspector'));
          await tester.tap(
            find.byKey(const ValueKey('close_gdd_inspector_btn')),
          );
          await tester.pumpAndSettle();

          // 2) Feature F02 on v0.1 never leaks seeded +DELTA (v0.1): ... text.
          await tester.tap(
            find.byKey(const ValueKey('table_feature_row_sb_f02')),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('+DELTA (v0.1):'), findsNothing);
          await tester.tap(
            find.byKey(const ValueKey('close_workbench_overlay_btn')),
          );
          await tester.pumpAndSettle();

          // 3) Quick-add feature sets Stage 2 summary banner; opening F01 from table clears it.
          await tester.tap(
            find.byKey(const ValueKey('release_quick_add_feature_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.lastStage2RefineSummary, isNotNull);
          await tester.tap(
            find.byKey(const ValueKey('close_workbench_overlay_btn')),
          );
          await tester.pumpAndSettle();

          await tester.tap(
            find.byKey(const ValueKey('table_feature_row_sb_f01')),
          );
          await tester.pumpAndSettle();
          expect(wb.lastStage2RefineSummary, isNull);

          // Leave some v0.1 slices unpassed (F03..F05) and open + New -> incomplete notice + E04+E05 commit.
          await tester.tap(
            find.byKey(const ValueKey('plan_next_release_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('plan_release_incomplete_prev_notice')),
            findsOneWidget,
          );
          expect(find.textContaining('1 Feature'), findsWidgets);
          expect(find.textContaining('1 Features'), findsNothing);

          final e04Tile = find.byKey(const ValueKey('copilot_new_sb_e04'));
          final e05Tile = find.byKey(const ValueKey('copilot_new_sb_e05'));
          expect(e04Tile, findsOneWidget);
          expect(e05Tile, findsOneWidget);
          if (!tester.widget<CheckboxListTile>(e04Tile).value!) {
            await _tapVisible(tester, e04Tile);
          }
          if (!tester.widget<CheckboxListTile>(e05Tile).value!) {
            await _tapVisible(tester, e05Tile);
          }
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('copilot_commit_btn')),
          );

          expect(wb.activeReleaseVersionTag, equals('v0.2'));
          expect(wb.activeReleaseEpics.length, equals(5));
          expect(find.textContaining('v0.2 · v0.2'), findsNothing);

          // Distinct v0.2 GOAL vs DONE WHEN (PIE GATE).
          final v02Goal = wb.activeRelease!.sections['goal'] ?? '';
          final v02Done = wb.activeRelease!.sections['doneWhen'] ?? '';
          expect(v02Goal, isNotEmpty);
          expect(v02Done, isNotEmpty);
          expect(v02Done, isNot(equals(v02Goal)));
          expect(v02Done, contains('in PIE ->'));

          // Unpassed locked baseline slices in v0.2 stay active and show open-in-v0.1 subtitle.
          expect(
            find.textContaining('Locked v0.1 baseline (open in v0.1)'),
            findsWidgets,
          );
          final v02E02 = wb.activeReleaseEpics.firstWhere(
            (e) => e.lineageKey.toLowerCase() == 'e02',
          );
          final lockedUnpassedF03 = v02E02.features.firstWhere(
            (f) => f.code == 'F03',
          );
          expect(lockedUnpassedF03.status, equals(FeatureStatus.active));
          expect(lockedUnpassedF03.isPassed, isFalse);

          // Check v0.1 link still renders cleanly in top header.
          expect(
            find.byKey(ValueKey('header_release_$v01Id')),
            findsOneWidget,
          );
        });

        // Also confirm compact jump bar at 640x800 uses deduplicated release labels.
        await _runWithViewport(tester, const Size(640, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);
          wb.approveRootSpecAndLaunchWorkbench();

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();
          expect(find.textContaining('v0.1 · v0.1'), findsNothing);
        });
      },
    );

    testWidgets(
      'New Game & preset load detach cleanly from cached projects with existing releases',
      (tester) async {
        final seededVault = _PlainMemoryVaultBackend(
          initialResult: VaultLoadResult(
            activeDocumentId: 'proj_legacy',
            documents: <String, TierDocument>{
              'proj_legacy': TierDocument(
                id: 'proj_legacy',
                title: 'Chrono Commando',
                tier: TierType.project,
                childrenIds: const ['rel_legacy'],
                sections: const <String, String>{},
              ),
              'rel_legacy': TierDocument(
                id: 'rel_legacy',
                title: 'v0.1 · Legacy Prototype',
                tier: TierType.release,
                parentId: 'proj_legacy',
                childrenIds: const [],
                sections: const <String, String>{'release_version': 'v0.1'},
              ),
            },
          ),
        );
        _installPlainTestHooks(vault: seededVault);

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false);
          addTearDown(wb.dispose);
          await wb.initVault();

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // On New Game Intake, cached project's releases must NOT bleed into the header.
          expect(wb.activeDocPage, equals(WorkbenchDocPage.newGameIdea));
          expect(find.text('v0.1 · Legacy Prototype'), findsNothing);

          // Loading Shellbreaker preset creates an isolated project with zero stale releases.
          wb.loadPresetSpark('shellbreaker');
          await tester.pumpAndSettle();
          expect(wb.activeProjectId, isNot(equals('proj_legacy')));
          expect(wb.projectReleases, isEmpty);
          expect(find.text('v0.1 · Legacy Prototype'), findsNothing);
          expect(
            find.byKey(const ValueKey('release_quick_add_feature_btn')),
            findsNothing,
          );
        });
      },
    );

    testWidgets(
      'Simulation #2 UI polish: single Stage 1 auth-error banner, single Cancel on inline add forms, New Feature rename propagation, Pass clears refine banner & honest v0.2 counter',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        _installPlainTestHooks(vault: vault);

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // 1) Unauthenticated Stage 1 AI refine shows only Stage 1 inline error banner (never duplicate global_offline_banner).
          await tester.enterText(
            find.byKey(const ValueKey('stage1_codesign_input')),
            'Make combat faster',
          );
          await tester.pumpAndSettle();
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_codesign_apply_btn')),
          );
          expect(
            find.byKey(const ValueKey('stage1_inline_error_banner')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('stage1_inline_signin_btn')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('global_offline_banner')),
            findsNothing,
          );

          // 2) Launch v0.1 -> open E01 overlay -> single Cancel on Epic + Add feature & Feature + Add var forms.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('approve_launch_workbench_btn')),
          );
          final e01 = wb.activeReleaseEpics.first;
          await _tapVisible(
            tester,
            find.byKey(ValueKey('table_epic_open_${e01.id}')),
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('show_add_feature_btn')),
          );
          expect(find.byKey(const ValueKey('add_feature_form')), findsOneWidget);
          expect(find.text('Cancel'), findsOneWidget);
          await _tapVisible(tester, find.text('Cancel'));
          expect(find.byKey(const ValueKey('add_feature_form')), findsNothing);
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('close_workbench_overlay_btn')),
          );

          // 3) Quick-add New Feature via Release header -> rename updates PIE check & starter sections.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('release_quick_add_feature_btn')),
          );
          final added = wb.selectedFeatureSpec!;
          wb.updateFeatureScope(
            e01.id,
            added.id,
            title: 'Storm Wind Gust Recovery',
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Storm Wind Gust Recovery'),
            findsWidgets,
          );
          expect(
            wb.selectedFeatureSpec!.checks.first.text,
            contains('Storm Wind Gust Recovery'),
          );

          // Open + Add var on Feature overlay -> single Cancel button.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_add_tuning_btn')),
          );
          expect(
            find.byKey(const ValueKey('feature_tuning_key_input')),
            findsOneWidget,
          );
          expect(find.text('Cancel'), findsOneWidget);
          await _tapVisible(tester, find.text('Cancel'));
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('close_workbench_overlay_btn')),
          );

          // 4) Passing F02 clears stale Stage 2 banner upon advancing, and v0.2 shows honest 1/N passed count.
          final f02 = wb.activeReleaseEpics.first.features[1];
          await _tapVisible(
            tester,
            find.byKey(ValueKey('table_feature_row_${f02.id}')),
          );
          for (final chk in wb.selectedFeatureSpec!.checks) {
            wb.toggleFeatureCheck(e01.id, f02.id, chk.id, true);
          }
          wb.addFeatureTuningParam(
            e01.id,
            f02.id,
            key: 'TempPreviewDist',
            value: '120',
            unit: 'cm',
          );
          await tester.pumpAndSettle();
          expect(wb.lastStage2RefineSummary, isNotNull);
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('pass_feature_btn')),
          );
          expect(wb.lastStage2RefineSummary, isNull);

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('plan_next_release_btn')),
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('copilot_commit_btn')),
          );
          expect(wb.activeReleaseVersionTag, equals('v0.2'));
          expect(wb.activeReleaseFeatureRollup.passed, equals(1));
          expect(
            wb.activeReleaseFeatureRollup.passed,
            lessThan(wb.activeReleaseFeatureRollup.total - 3),
          );
          await _tapVisible(
            tester,
            find.byKey(ValueKey('header_release_${wb.activeReleaseId!}')),
          );
          expect(
            find.textContaining(
              '1/${wb.activeReleaseFeatureRollup.total} PASSED',
            ),
            findsOneWidget,
          );
        });
      },
    );

    testWidgets(
      'Core loop upgrades: signed-out Template Mode notice, UE5 Version & Project Base UI, guarded Delete button, and pasteable [FIX] error log',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        _installPlainTestHooks(vault: vault);

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false);
          addTearDown(wb.dispose);

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // 1) Signed-out New Game intake renders Template Mode notice & Sign in CTA; hides when key is added.
          expect(
            find.byKey(const ValueKey('offline_template_mode_notice')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('intake_template_signin_btn')),
            findsOneWidget,
          );
          wb.updateAiConfig(apiKey: 'AIzaTemplateModeHiddenTestKey');
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('offline_template_mode_notice')),
            findsNothing,
          );

          // 2) Load Shellbreaker & configure UE 5.6 + Project Base / Module in §02 UE5 Setup.
          wb.loadPresetSpark('shellbreaker');
          await tester.pumpAndSettle();

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('ue_version_opt_UE_5.6')),
          );
          expect(wb.conceptDraft!.ueVersion, equals('UE 5.6'));

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_edit_contracts_btn')),
          );
          await _enterAndUnfocus(
            tester,
            find.byKey(const ValueKey('stage1_project_anchor_input')),
            'Module: ShellGame · Extends ACharacter',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_contracts_save_btn')),
          );
          expect(
            wb.conceptDraft!.ueProjectAnchor,
            equals('Module: ShellGame · Extends ACharacter'),
          );

          // 3) Launch v0.1 -> passed F01 hides Delete button; quick-added unbuilt Feature shows Delete & removes cleanly.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('approve_launch_workbench_btn')),
          );
          final e01 = wb.activeReleaseEpics.first;
          final f01 = e01.features.first;
          await _tapVisible(
            tester,
            find.byKey(ValueKey('table_feature_row_${f01.id}')),
          );
          expect(
            find.byKey(const ValueKey('delete_feature_btn')),
            findsNothing,
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('close_workbench_overlay_btn')),
          );

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('release_quick_add_feature_btn')),
          );
          final createdId = wb.selectedFeatureId!;
          expect(
            find.byKey(const ValueKey('delete_feature_btn')),
            findsOneWidget,
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('delete_feature_btn')),
          );
          expect(
            wb.activeReleaseEpics.first.features.any((f) => f.id == createdId),
            isFalse,
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('close_workbench_overlay_btn')),
          );

          // 4) Open F02 from Monday table -> + Paste log -> Flag [FIX] displays log excerpt in Fixes (1).
          final f02 = wb.activeReleaseEpics.first.features[1];
          await _tapVisible(
            tester,
            find.byKey(ValueKey('table_feature_row_${f02.id}')),
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('toggle_fix_log_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('flag_fix_input')),
            'Dash collider clips corner',
          );
          await tester.enterText(
            find.byKey(const ValueKey('flag_fix_log_input')),
            'LogPhysics: Warning: SweptTrace blocked at Z=12',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('flag_fix_btn')),
          );
          expect(find.text('FIXES (1)'), findsOneWidget);
          expect(
            find.textContaining('SweptTrace blocked at Z=12'),
            findsOneWidget,
          );
          expect(
            find.text('Copy CoPilot [FIX] Prompt (1)'),
            findsOneWidget,
          );
        });
      },
    );

    testWidgets(
      'Option A 2-column desktop layout renders balanced left/right columns at 1280x800 and stacks PIE-first at 640x800',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        _installPlainTestHooks(vault: vault);

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);
          wb.approveRootSpecAndLaunchWorkbench();

          final e01 = wb.activeReleaseEpics.first;
          final f02 = e01.features.firstWhere((f) => f.code == 'F02');
          wb.selectFeature(e01.id, f02.id);

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // Feature: Spec Left vs Playtest + Cues + @OWNERS Right.
          expect(
            find.byKey(const ValueKey('plain_two_col_row')),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('feature_col_spec'))).dx,
            lessThan(
              tester
                  .getTopLeft(find.byKey(const ValueKey('feature_col_playtest')))
                  .dx,
            ),
          );
          expect(
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('feature_epic_owners_ref')),
                )
                .dx,
            equals(
              tester
                  .getTopLeft(find.byKey(const ValueKey('feature_col_playtest')))
                  .dx,
            ),
          );

          // Open Epic via compact @OWNERS link.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_open_epic_owners_btn')),
          );
          expect(wb.selectedFeatureSpec, isNull);
          expect(wb.selectedEpicSpec?.id, equals(e01.id));

          // Epic: Architecture Left vs Features -> Out of Scope Right.
          expect(
            find.byKey(const ValueKey('plain_two_col_row')),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('epic_col_arch'))).dx,
            lessThan(
              tester
                  .getTopLeft(find.byKey(const ValueKey('epic_col_queue')))
                  .dx,
            ),
          );
          expect(
            tester
                .getTopLeft(find.byKey(const ValueKey('show_add_feature_btn')))
                .dy,
            lessThan(
              tester
                  .getTopLeft(find.byKey(const ValueKey('epic_add_cut_btn')))
                  .dy,
            ),
          );

          // Release Table: Goal left of Done When + MondayReleaseTable below.
          wb.selectReleaseSpec();
          await tester.pumpAndSettle();
          expect(find.byType(MondayReleaseTable), findsOneWidget);
          expect(
            tester
                .getTopLeft(find.byKey(const ValueKey('release_goal_input')))
                .dx,
            lessThan(
              tester
                  .getTopLeft(
                    find.byKey(const ValueKey('release_done_when_input')),
                  )
                  .dx,
            ),
          );

          // Project Brief: Setup Left vs Plan Right.
          wb.selectProjectBrief();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('plain_two_col_row')),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('brief_col_setup'))).dx,
            lessThan(
              tester
                  .getTopLeft(find.byKey(const ValueKey('brief_col_plan')))
                  .dx,
            ),
          );
          expect(tester.takeException(), isNull);
        });

        await _runWithViewport(tester, const Size(640, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);
          wb.approveRootSpecAndLaunchWorkbench();

          final e01 = wb.activeReleaseEpics.first;
          final f02 = e01.features.firstWhere((f) => f.code == 'F02');
          wb.selectFeature(e01.id, f02.id);

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: find.byKey(const ValueKey('workbench_overlay_dialog')),
              matching: find.byKey(const ValueKey('plain_single_col_stack')),
            ),
            findsOneWidget,
          );
          expect(
            tester
                .getTopLeft(find.byKey(const ValueKey('feature_col_playtest')))
                .dy,
            lessThan(
              tester
                  .getTopLeft(find.byKey(const ValueKey('feature_col_spec')))
                  .dy,
            ),
          );
          expect(tester.takeException(), isNull);
        });
      },
    );

    testWidgets(
      'Monday table row copy stays inline without opening overlay; Prev/Next steppers, backdrop tap & Esc dismiss wide overlay cleanly',
      (tester) async {
        final vault = _PlainMemoryVaultBackend();
        _installPlainTestHooks(vault: vault);

        await _runWithViewport(tester, const Size(1280, 800), () async {
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..loadPresetSpark('shellbreaker');
          addTearDown(wb.dispose);
          wb.approveRootSpecAndLaunchWorkbench(openReleaseSpec: true);

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          // 1) Row ⚡ Copy flashes Copied (~N tok) inline without opening the overlay.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('table_feature_copy_sb_f02')),
          );
          expect(find.textContaining('Copied (~'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('workbench_overlay_dialog')),
            findsNothing,
          );

          // 2) Tap Feature row F02 -> opens wide 2-column Overlay -> Next -> F03 -> Prev -> F02 -> backdrop closes.
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('table_feature_row_sb_f02')),
          );
          expect(
            find.byKey(const ValueKey('workbench_overlay_dialog')),
            findsOneWidget,
          );
          expect(wb.selectedFeatureSpec?.code, equals('F02'));

          await tester.tap(find.byKey(const ValueKey('overlay_next_btn')));
          await tester.pumpAndSettle();
          expect(wb.selectedFeatureSpec?.code, equals('F03'));

          await tester.tap(find.byKey(const ValueKey('overlay_prev_btn')));
          await tester.pumpAndSettle();
          expect(wb.selectedFeatureSpec?.code, equals('F02'));

          // Tap top-left backdrop outside centered overlay -> closes overlay.
          await tester.tapAt(const Offset(4, 52));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workbench_overlay_dialog')),
            findsNothing,
          );
          expect(wb.isInspectingReleaseSpec, isTrue);

          // 3) Tap Epic header E01 -> opens Epic Overlay -> Esc key closes overlay cleanly.
          final e01 = wb.activeReleaseEpics.first;
          await _tapVisible(
            tester,
            find.byKey(ValueKey('table_epic_open_${e01.id}')),
          );
          expect(
            find.byKey(const ValueKey('workbench_overlay_dialog')),
            findsOneWidget,
          );
          expect(wb.isInspectingEpicDomain, isTrue);

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('workbench_overlay_dialog')),
            findsNothing,
          );
          expect(wb.isInspectingReleaseSpec, isTrue);
        });
      },
    );
  });
}

Future<void> _enterAndUnfocus(
  WidgetTester tester,
  Finder fieldFinder,
  String text,
) async {
  await tester.ensureVisible(fieldFinder);
  await tester.pumpAndSettle();
  await tester.enterText(fieldFinder, text);
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _runWithViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
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

void _installPlainTestHooks({
  required _PlainMemoryVaultBackend vault,
  http.Response Function(Uri uri, Map<String, dynamic> body)? onGeminiCall,
}) {
  GeminiAgentClient.resetCapabilityCacheForTest();
  GeminiAgentClient.resetUsage();
  GeminiAgentClient.testMockResponder = null;
  GeminiAgentClient.testBaseRetryDelay = Duration.zero;
  LocalVaultService.testBackendOverride = vault;

  if (onGeminiCall != null) {
    GeminiAgentClient.testHttpPost = (uri, {headers, body}) async {
      final decoded = (body is String && body.isNotEmpty)
          ? jsonDecode(body) as Map<String, dynamic>
          : const <String, dynamic>{};
      return onGeminiCall(uri, decoded);
    };
  }

  addTearDown(() {
    GeminiAgentClient.testHttpPost = null;
    GeminiAgentClient.testMockResponder = null;
    GeminiAgentClient.testBaseRetryDelay = null;
    GeminiAgentClient.resetCapabilityCacheForTest();
    GeminiAgentClient.resetUsage();
    LocalVaultService.testBackendOverride = null;
  });
}

http.Response _mockGeminiFunctionResponse({
  required String modelVersion,
  required int inputTokens,
  required int outputTokens,
  required int thinkingTokens,
  required String toolName,
  required Map<String, dynamic> args,
}) {
  return http.Response.bytes(
    utf8.encode(
      jsonEncode(<String, dynamic>{
        'modelVersion': modelVersion,
        'usageMetadata': <String, dynamic>{
          'promptTokenCount': inputTokens,
          'candidatesTokenCount': outputTokens,
          'thoughtsTokenCount': thinkingTokens,
        },
        'candidates': <Map<String, dynamic>>[
          <String, dynamic>{
            'content': <String, dynamic>{
              'parts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'functionCall': <String, dynamic>{
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
    headers: const <String, String>{'content-type': 'application/json; charset=utf-8'},
  );
}

class _PlainMemoryVaultBackend implements VaultStorageBackend {
  final VaultLoadResult? initialResult;
  final Map<String, TierDocument> savedDocs = <String, TierDocument>{};

  _PlainMemoryVaultBackend({this.initialResult});

  @override
  Future<VaultLoadResult> loadVaultData() async =>
      initialResult ??
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

class _PlainLocalGddBackend implements LocalGddFileBackend {
  bool denyPermission = false;
  String? errorMessage;
  bool lastRequestPermissionFlag = false;
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
    lastRequestPermissionFlag = requestPermissionIfNeeded;
    if (!linkedHandles.containsKey(projectId)) {
      return const LocalGddWriteResult(written: false);
    }
    if (denyPermission) {
      return const LocalGddWriteResult(
        written: false,
        permissionDenied: true,
      );
    }
    if (errorMessage != null) {
      return LocalGddWriteResult(written: false, error: errorMessage);
    }
    writtenContents.add(content);
    return const LocalGddWriteResult(written: true);
  }

  @override
  Future<void> unlinkProject(String projectId) async {
    linkedHandles.remove(projectId);
  }
}
