import 'dart:convert';

import 'package:flutter/material.dart';
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
  group('Flight Deck Solo UE5 Developer Dogfood Simulation', () {
    testWidgets(
      'Scenario 1 — End-to-End Flight Deck Walkthrough (1440x900, Dark theme)',
      (tester) async {
        final memoryVault = _MemoryVaultBackend();
        final fakeGddBackend = _FakeLocalGddBackend();
        final recordedGeminiCalls =
            <({String url, String model, String? thinkingLevel, String tool})>[];

        _installDogfoodTestHooks(
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

            var model = 'unknown';
            if (urlStr.contains(GeminiAgentClient.pinnedArchitectModel)) {
              model = GeminiAgentClient.pinnedArchitectModel;
            } else if (urlStr.contains(GeminiAgentClient.pinnedLiveFlashModel)) {
              model = GeminiAgentClient.pinnedLiveFlashModel;
            }
            recordedGeminiCalls.add((
              url: urlStr,
              model: model,
              thinkingLevel: thinkingLevel,
              tool: toolName,
            ));

            if (toolName == 'patch_unreal_root_spec') {
              return _geminiFunctionResponse(
                modelVersion: 'gemini-4-hydrogen-preview',
                inputTokens: 420,
                outputTokens: 110,
                thinkingTokens: 25,
                toolName: toolName,
                args: <String, dynamic>{
                  'coDesignNote':
                      'Emphasized heavy claw impact and trimmed achievement popups.',
                  'changedSections': <String>['s01', 's04'],
                  'pitch':
                      'AI-refined mech brawler — smash armored crabs with heavy hitstop',
                  'outOfScope': <String>[
                    'No main menu, title screen, or save slots',
                    'No inventory screen or multi-weapon loadout UI',
                    'No achievement popups',
                  ],
                },
              );
            }

            if (toolName == 'patch_unreal_feature_spec') {
              return _geminiFunctionResponse(
                modelVersion: 'gemini-4-hydrogen-preview',
                inputTokens: 310,
                outputTokens: 95,
                thinkingTokens: 20,
                toolName: toolName,
                args: <String, dynamic>{
                  'summary': 'Boosted DashDistance to 620 cm and added cue',
                  'changedSections': <String>['s01', 's03', 's04'],
                  'goal':
                      'Launch a 620 cm forward commitment dash with impact shockwave cue.',
                  'tuning': <Map<String, dynamic>>[
                    {'key': 'DashDistance', 'value': '620', 'unit': 'cm'},
                    {'key': 'DashDuration', 'value': '0.16', 'unit': 's'},
                    {'key': 'DashCooldown', 'value': '1.1', 'unit': 's'},
                  ],
                  'cues': <String>[
                    'Orange emissive Niagara thruster ribbon fires for 0.16 s',
                    'Radial shockwave ring decal pulses on crab impact',
                  ],
                },
              );
            }

            if (toolName == 'propose_progressive_unreal_release') {
              return _geminiFunctionResponse(
                modelVersion: 'gemini-4-argon-preview',
                inputTokens: 680,
                outputTokens: 240,
                thinkingTokens: 80,
                toolName: toolName,
                args: <String, dynamic>{
                  'presets': <Map<String, dynamic>>[
                    {
                      'id': 'juice',
                      'label': 'Combat Juice Pass',
                      'desc':
                          'Add dash impact hitstop delta and chain dash inside E01.',
                      'upgrades': <String>['up_e01_hitstop', 'sb_f08_chain'],
                      'newFeatures': <String>['sb_f08_chain'],
                      'newEpics': <String>['sb_e04'],
                    },
                  ],
                  'upgrades': <Map<String, dynamic>>[
                    {
                      'lineageKey': 'e01',
                      'options': <Map<String, dynamic>>[
                        {
                          'id': 'up_e01_hitstop',
                          'targetFeatureCode': 'F02',
                          'text':
                              '+55ms hitstop freeze & radial shockwave ring on Dash impact',
                          'chosen': false,
                        },
                      ],
                    },
                  ],
                  'newFeatures': <Map<String, dynamic>>[
                    {
                      'lineageKey': 'e01',
                      'features': <Map<String, dynamic>>[
                        {
                          'id': 'sb_f08_chain',
                          'code': 'F08',
                          'title': 'Chain Dash on Shell Break',
                          'sliceTime': '45 min',
                          'goal':
                              'Refund IA_ClawDash cooldown for 0.35 s after shattering an enemy shell.',
                          'inScope': <String>['0.35 s chain dash grace window'],
                          'doneWhen': <String>[
                            'Crack crab armor then tap Space -> Second dash chains cleanly',
                          ],
                          'controls': <Map<String, dynamic>>[
                            {
                              'action': 'IA_ClawDash',
                              'trigger': 'Started (Space / RMB)',
                              'rule':
                                  'Bypasses cooldown cleanly during 0.35 s chain window',
                            },
                          ],
                          'tuning': <Map<String, dynamic>>[
                            {
                              'key': 'ChainWindowS',
                              'value': '0.35',
                              'unit': 's',
                            },
                          ],
                          'cues': <String>[
                            'Cyan afterimage silhouette flashes during chain dash',
                          ],
                          'checks': <Map<String, dynamic>>[
                            {
                              'text':
                                  'Crack crab armor then tap Space -> Second dash chains cleanly',
                            },
                          ],
                        },
                      ],
                    },
                  ],
                  'newEpics': <Map<String, dynamic>>[
                    {
                      'id': 'sb_e04',
                      'code': 'E04',
                      'title': 'Wave Escalation & Arena Reset',
                      'coreLoopBeat': 'Beat 4 · 3-Wave Escalation & Quick Reset',
                      'chosen': false,
                      'goal':
                          'Spawn escalating 3-wave crab squads from perimeter gates with R quick reset.',
                      'inScope': <String>[
                        '4 perimeter SpawnGate actors',
                        'WBP wave counter and quick restart',
                      ],
                      'doneWhen': <String>[
                        'Clear 3 waves -> Victory banner renders and R restarts cleanly',
                      ],
                      'sceneOwnership': <Map<String, dynamic>>[
                        {
                          'path': '/Game/Blueprints/BP_WaveDirector',
                          'role': '3-wave squad timer and arena reset',
                        },
                      ],
                      'states': <String>['WaveIntro -> WaveCombat -> ArenaVictory'],
                      'interrupts': <String>[
                        'Player HP <= 0 stops active spawn timers cleanly',
                      ],
                      'outOfScope': <String>['No endless wave mode'],
                      'features': <Map<String, dynamic>>[
                        {
                          'id': 'sb_e04_f01',
                          'code': 'F09',
                          'title': '3-Wave Arena Spawner',
                          'sliceTime': '60 min',
                          'goal':
                              'Spawn 3 escalating waves from 4 perimeter SpawnGates.',
                          'tuning': <Map<String, dynamic>>[
                            {
                              'key': 'Wave1Count',
                              'value': '3',
                              'unit': 'count',
                            },
                          ],
                          'checks': <Map<String, dynamic>>[
                            {
                              'text':
                                  'Clear Wave 1 -> Wave 2 spawns from lit gates cleanly',
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              );
            }

            return http.Response('{"error":{"message":"Unexpected tool"}}', 400);
          },
        );

        await _runWithDogfoodViewport(tester, const Size(1440, 900), () async {
          // 1) Cold boot LayersAgenticApp(provider: wb) with fake GDD backend + mocked Gemini
          final wb = WorkbenchProvider(enableAutoLoad: false)
            ..setLocalGddBackendForTest(fakeGddBackend)
            ..updateAiConfig(apiKey: 'AIzaDogfoodWalkthroughKey1234');
          addTearDown(wb.dispose);

          await tester.pumpWidget(LayersAgenticApp(provider: wb));
          await tester.pumpAndSettle();

          expect(wb.isDark, isTrue);
          expect(find.byType(ProjectPitchScreen), findsOneWidget);
          expect(
            find.byKey(const ValueKey('stage1_blueprint_empty_outline')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('explore_angles_btn')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('draft_spark_btn')),
            findsOneWidget,
          );

          // 2) Load Shellbreaker Spark & toggle Blueprint-First <-> C++ & BP Hybrid -> Blueprint-First
          await tester.tap(find.byKey(const ValueKey('preset_shellbreaker')));
          await tester.pumpAndSettle();

          expect(wb.conceptDraft?.gameTitle, equals('SHELLBREAKER'));
          expect(
            wb.unrealArchitectureMode,
            equals(UnrealArchitectureMode.blueprint),
          );

          await tester.tap(
            find.byKey(const ValueKey('stage1_mode_cpp_hybrid')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.unrealArchitectureMode,
            equals(UnrealArchitectureMode.cppHybrid),
          );
          expect(
            find.text('UE5 SETUP (C++ & BP HYBRID)'),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(const ValueKey('stage1_mode_blueprint')),
          );
          await tester.pumpAndSettle();
          expect(
            wb.unrealArchitectureMode,
            equals(UnrealArchitectureMode.blueprint),
          );

          // 3) Inline edit Title, §01 Pitch, §02 Contracts, §03 Pillars & Trade-Offs,
          // §04 Scope Cuts, and §05 Slices; then submit Stage 1 FloatingAiRefineDock + Undo
          await tester.tap(
            find.byKey(const ValueKey('stage1_edit_title_btn')),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('stage1_title_input')),
            'SHELLBREAKER ARENA',
          );
          await tester.tap(
            find.byKey(const ValueKey('stage1_title_save_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.conceptDraft?.gameTitle, equals('SHELLBREAKER ARENA'));

          await tester.tap(
            find.byKey(const ValueKey('stage1_edit_pitch_btn')),
          );
          await tester.pumpAndSettle();
          const editedStage1Pitch =
              'Crisp greybox mech brawler — shatter armored crabs cleanly';
          await tester.enterText(
            find.byKey(const ValueKey('stage1_pitch_input')),
            editedStage1Pitch,
          );
          await tester.tap(
            find.byKey(const ValueKey('stage1_pitch_save_btn')),
          );
          await tester.pumpAndSettle();
          expect(find.text(editedStage1Pitch), findsOneWidget);

          final editContractsBtn = find.byKey(
            const ValueKey('stage1_edit_contracts_btn'),
          );
          await _tapVisible(tester, editContractsBtn);
          await tester.enterText(
            find.byKey(const ValueKey('stage1_camera_input')),
            'USpringArmComponent TargetArmLength 1500 cm @ -54 deg pitch, 55 deg FOV',
          );
          await tester.enterText(
            find.byKey(const ValueKey('stage1_scale_input')),
            'ACharacter CapsuleRadius 44 cm · HalfHeight 92 cm · MaxWalkSpeed 660 cm/s',
          );
          await tester.enterText(
            find.byKey(const ValueKey('stage1_input_contract_input')),
            'IMC_Shellbreaker (IA_Move, IA_MouseAim, IA_ClawDash, IA_FireBurst)',
          );
          await tester.enterText(
            find.byKey(const ValueKey('stage1_asset_policy_input')),
            'UStaticMeshComponent Greybox + UMaterialInstanceDynamic; /Game/Data/DA_Shellbreaker',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_contracts_save_btn')),
          );
          expect(
            find.textContaining('TargetArmLength 1500 cm'),
            findsOneWidget,
          );

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_edit_pillars_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('stage1_pillars_input')),
            'Commit Every Dash\nReadable Crimson Telegraphs\nZero-Lag Frame-1 Fire',
          );
          await tester.enterText(
            find.byKey(const ValueKey('stage1_tradeoffs_input')),
            'Snappy arcade turn OVER heavy inertia\nSingle arena testbed OVER streaming zones',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_pillars_save_btn')),
          );
          expect(find.text('— Commit Every Dash'), findsOneWidget);
          expect(
            find.text('Snappy arcade turn OVER heavy inertia'),
            findsOneWidget,
          );

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_cut_add_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('stage1_cut_add_input')),
            'Cutscene dialogue trees',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_cut_add_save_btn')),
          );
          expect(find.text('No Cutscene dialogue trees'), findsOneWidget);
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_cut_remove_0')),
          );
          expect(
            find.text('No main menu, title screen, or save slots'),
            findsNothing,
          );

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_feat_edit_sb_f02')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('stage1_feat_input_sb_f02')),
            'Heavy Claw Dash',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('stage1_feat_save_sb_f02')),
          );
          expect(find.text('F02 · Heavy Claw Dash'), findsOneWidget);

          // Stage 1 FloatingAiRefineDock (mocked Gemini) -> updated badge -> Undo restore
          await tester.enterText(
            find.byKey(const ValueKey('stage1_codesign_input')),
            'Make dash shatter heavier and cut achievement popups',
          );
          await tester.tap(
            find.byKey(const ValueKey('stage1_codesign_apply_btn')),
          );
          await tester.pumpAndSettle();

          expect(recordedGeminiCalls.last.tool, equals('patch_unreal_root_spec'));
          expect(
            recordedGeminiCalls.last.model,
            equals(GeminiAgentClient.pinnedLiveFlashModel),
          );
          expect(recordedGeminiCalls.last.thinkingLevel, equals('LOW'));
          expect(
            find.byKey(const ValueKey('stage1_updated_badge_§01')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('stage1_updated_badge_§04')),
            findsOneWidget,
          );
          expect(
            find.text(
              'AI-refined mech brawler — smash armored crabs with heavy hitstop',
            ),
            findsOneWidget,
          );
          expect(wb.totalInputTokens, greaterThan(0));

          await tester.tap(find.byKey(const ValueKey('stage1_undo_btn')));
          await tester.pumpAndSettle();
          expect(wb.conceptDraft?.pitch, equals(editedStage1Pitch));
          expect(wb.conceptDraft?.gameTitle, equals('SHELLBREAKER ARENA'));
          expect(
            find.byKey(const ValueKey('stage1_updated_badge_§01')),
            findsNothing,
          );

          // 4) Link Local GDD -> initial disk write -> Inspect GDD -> permissionNeeded recovery -> Unlink -> re-link
          await tester.tap(
            find.byKey(const ValueKey('header_gdd_menu_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.synced));
          expect(find.text('GDD ▾'), findsOneWidget);
          expect(fakeGddBackend.writtenContents, hasLength(1));
          expect(
            fakeGddBackend.writtenContents.first,
            contains('# PROJECT GDD · SHELLBREAKER ARENA'),
          );

          await tester.tap(
            find.byKey(const ValueKey('header_gdd_menu_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('File: shellbreaker_arena_copilot_gdd.md'),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('top_bar_copilot_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('gdd_inspector_dialog')),
            findsOneWidget,
          );
          expect(
            find.textContaining('# PROJECT GDD · SHELLBREAKER ARENA'),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('close_gdd_inspector_btn')),
          );
          await tester.pumpAndSettle();

          // permissionNeeded triggered on next GDD sync -> Grant GDD Write recovers
          fakeGddBackend.denyPermission = true;
          expect(await wb.syncLinkedGddNow(force: true), isFalse);
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.permissionNeeded));
          expect(find.text('Grant GDD ▾'), findsOneWidget);

          fakeGddBackend.denyPermission = false;
          await tester.tap(
            find.byKey(const ValueKey('header_gdd_menu_btn')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Grant GDD Write Permission'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.synced));
          expect(fakeGddBackend.lastRequestPermissionFlag, isTrue);

          // permissionNeeded inside GDD Inspector + Unlink Local File -> close -> re-link cleanly
          fakeGddBackend.denyPermission = true;
          expect(await wb.syncLinkedGddNow(force: true), isFalse);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('header_gdd_menu_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('top_bar_copilot_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('gdd_inspector_grant_perm_btn')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('gdd_inspector_unlink_btn')),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(const ValueKey('gdd_inspector_unlink_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.unlinked));
          await tester.tap(
            find.byKey(const ValueKey('close_gdd_inspector_btn')),
          );
          await tester.pumpAndSettle();

          fakeGddBackend.denyPermission = false;
          await tester.tap(
            find.byKey(const ValueKey('header_gdd_menu_btn')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('top_bar_link_local_gdd_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.isLocalGddLinked, isTrue);
          expect(wb.gddSyncStatus, equals(LocalGddSyncStatus.synced));

          // 5) Approve & Launch v0.1 -> Release Spec -> Outliner & Breadcrumbs -> E01 Domain Sheet CRUD + Architecture Brief -> Start/Continue CTA
          final writesBeforeLaunch = fakeGddBackend.writtenContents.length;
          await tester.tap(
            find.byKey(const ValueKey('approve_launch_workbench_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.isInspectingReleaseSpec, isTrue);
          expect(wb.activeReleaseVersionTag, equals('v0.1'));
          // Launching v0.1 from identical Stage 1 initialEpics skips redundant GDD write (delta-only sync)
          expect(
            fakeGddBackend.writtenContents.length,
            equals(writesBeforeLaunch),
          );

          final e01 = wb.activeReleaseEpics[0];
          final e02 = wb.activeReleaseEpics[1];

          // Walk Outliner to E02 then back to E01 Domain Sheet
          await tester.tap(find.byKey(ValueKey('outliner_epic_${e02.id}')));
          await tester.pumpAndSettle();
          expect(wb.selectedEpicSpec?.code, equals('E02'));
          expect(wb.isInspectingEpicDomain, isTrue);

          await tester.tap(find.byKey(ValueKey('outliner_epic_${e01.id}')));
          await tester.pumpAndSettle();
          expect(wb.selectedEpicSpec?.code, equals('E01'));
          expect(wb.isInspectingEpicDomain, isTrue);

          // E01 §01 inline Scope edit
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('epic_edit_scope_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('epic_scope_goal_input')),
            'Own planar mech movement, cursor aim, dash burst, and camera tracking.',
          );
          await tester.enterText(
            find.byKey(const ValueKey('epic_scope_in_scope_input')),
            '8-way arena XY movement\nInvulnerable 550 cm Claw Dash',
          );
          await tester.enterText(
            find.byKey(const ValueKey('epic_scope_done_when_input')),
            'All E01 movement slices pass PIE -> Mech glides without snagging',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('epic_scope_save_btn')),
          );
          expect(
            find.textContaining(
              'Own planar mech movement, cursor aim, dash burst, and camera tracking.',
            ),
            findsOneWidget,
          );

          // E01 §02 Owner add / edit / delete
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('epic_add_owner_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('epic_owner_path_input')),
            '/Game/Blueprints/BP_ArenaFX',
          );
          await tester.enterText(
            find.byKey(const ValueKey('epic_owner_role_input')),
            'Dash ribbon & impact spark FX',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('epic_owner_save_btn')),
          );
          expect(find.text('/Game/Blueprints/BP_ArenaFX'), findsOneWidget);

          final addedOwnerIdx = wb.selectedEpicSpec!.sceneOwnership.length - 1;
          await _tapVisible(
            tester,
            find.byKey(ValueKey('epic_owner_edit_$addedOwnerIdx')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('epic_owner_role_input')),
            'Niagara dash ribbon and arena spark controller',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('epic_owner_save_btn')),
          );
          expect(
            find.text('Niagara dash ribbon and arena spark controller'),
            findsOneWidget,
          );

          await _tapVisible(
            tester,
            find.byKey(ValueKey('epic_owner_delete_$addedOwnerIdx')),
          );
          expect(find.text('/Game/Blueprints/BP_ArenaFX'), findsNothing);

          // E01 §03 State Rules edit
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('epic_edit_states_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('epic_states_input')),
            'Idle -> Move -> DashWindup -> DashActive -> DashRecover',
          );
          await tester.enterText(
            find.byKey(const ValueKey('epic_interrupts_input')),
            'DashActive cancels burst fire cleanly\nHitstun cancels DashWindup',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('epic_states_save_btn')),
          );
          expect(
            find.text('Idle -> Move -> DashWindup -> DashActive -> DashRecover'),
            findsOneWidget,
          );
          expect(find.text('— Hitstun cancels DashWindup'), findsOneWidget);

          // E01 §04 Cut add / delete
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('epic_add_cut_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('epic_cut_input')),
            'Wall-run locomotion',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('epic_cut_save_btn')),
          );
          expect(find.text('No Wall-run locomotion'), findsOneWidget);
          final addedCutIdx = wb.selectedEpicSpec!.outOfScope.length - 1;
          await _tapVisible(
            tester,
            find.byKey(ValueKey('epic_cut_delete_$addedCutIdx')),
          );
          expect(find.text('No Wall-run locomotion'), findsNothing);

          // E01 §05 + Add Feature Slice -> creates F07 -> return via Breadcrumb to E01 Domain Sheet
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('show_add_feature_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('new_feature_title_input')),
            'Wall Bounce Dash',
          );
          await tester.enterText(
            find.byKey(const ValueKey('new_feature_goal_input')),
            'Ricochet cleanly off angled stone arena barriers.',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('submit_add_feature_btn')),
          );
          expect(wb.selectedFeatureSpec?.code, equals('F07'));
          expect(wb.selectedFeatureSpec?.title, equals('Wall Bounce Dash'));
          expect(
            fakeGddBackend.writtenContents.length,
            greaterThan(writesBeforeLaunch),
          );
          expect(
            fakeGddBackend.writtenContents.last,
            contains('F07 · Wall Bounce Dash'),
          );

          await tester.tap(find.byKey(const ValueKey('crumb_epic')));
          await tester.pumpAndSettle();
          expect(wb.isInspectingEpicDomain, isTrue);

          // Verify NO primary Copy Epic Brief button on header; inspect Architecture Brief via ⋯ menu
          expect(find.textContaining('Copy Epic Brief'), findsNothing);
          await tester.tap(find.byKey(const ValueKey('epic_more_menu_btn')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('preview_epic_brief_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('E01 · Architecture Brief'),
            findsOneWidget,
          );
          expect(find.textContaining('@OWNERS:'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('close_copilot_preview_btn')),
          );
          await tester.pumpAndSettle();

          // Click primary Start/Continue CTA -> jumps directly to F02 (first open slice)
          await tester.tap(
            find.byKey(const ValueKey('epic_inspect_first_feature_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.selectedFeatureSpec?.code, equals('F02'));

          // 6) On Feature F02: inline edit §01 Scope, §02 Input Actions CRUD, §03 Tuning (zero Sliders),
          // §04 Cues add/delete, §05 Checks add/toggle, Stage 2 FloatingAiRefineDock (Hydrogen) + Undo
          expect(find.byType(Slider), findsNothing);

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_edit_scope_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_scope_goal_input')),
            'Launch a 560 cm forward dash with Niagara ribbon and 1.1 s cooldown.',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_scope_save_btn')),
          );
          expect(
            find.textContaining('Launch a 560 cm forward dash'),
            findsOneWidget,
          );

          // §02 Input Actions CRUD
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_add_control_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_control_action_input')),
            'claw_feint',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_control_trigger_input')),
            'Started (Ctrl)',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_control_rule_input')),
            'Cancel dash windup early',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_control_save_btn')),
          );
          expect(find.text('IA_ClawFeint'), findsOneWidget);

          final addedCtrlIdx = wb.selectedFeatureSpec!.controls.length - 1;
          await _tapVisible(
            tester,
            find.byKey(ValueKey('feature_control_edit_$addedCtrlIdx')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_control_rule_input')),
            'Cancel dash windup inside 0.04 s',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_control_save_btn')),
          );
          expect(find.text('Cancel dash windup inside 0.04 s'), findsOneWidget);

          await _tapVisible(
            tester,
            find.byKey(ValueKey('feature_control_delete_$addedCtrlIdx')),
          );
          expect(find.text('IA_ClawFeint'), findsNothing);

          // §03 Tuning add / edit / delete (zero Sliders)
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_add_tuning_btn')),
          );
          expect(find.byType(Slider), findsNothing);
          await tester.enterText(
            find.byKey(const ValueKey('feature_tuning_key_input')),
            'DashBufferWindow',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_tuning_value_input')),
            '0.12',
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_tuning_unit_input')),
            's',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_tuning_save_btn')),
          );
          expect(find.text('DashBufferWindow'), findsOneWidget);

          final f02Id = wb.selectedFeatureSpec!.id;
          final addedTuneIdx = wb.selectedFeatureSpec!.tuning.length - 1;
          await tester.ensureVisible(
            find.byKey(ValueKey('tuning_input_${f02Id}_0')),
          );
          await tester.enterText(
            find.byKey(ValueKey('tuning_input_${f02Id}_0')),
            '580',
          );
          await tester.pumpAndSettle();
          expect(
            wb.selectedFeatureSpec!.tuning.first.value,
            equals('580'),
          );

          await _tapVisible(
            tester,
            find.byKey(ValueKey('tuning_delete_${f02Id}_$addedTuneIdx')),
          );
          expect(find.text('DashBufferWindow'), findsNothing);

          // §04 Cues add / delete
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_add_cue_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_cue_input')),
            'Blue ring decal pulses under landing point',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_cue_save_btn')),
          );
          expect(
            find.text('— Blue ring decal pulses under landing point'),
            findsOneWidget,
          );
          final addedCueIdx = wb.selectedFeatureSpec!.cues.length - 1;
          await _tapVisible(
            tester,
            find.byKey(ValueKey('feature_cue_delete_$addedCueIdx')),
          );
          expect(
            find.text('— Blue ring decal pulses under landing point'),
            findsNothing,
          );

          // §05 Checks add / toggle
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_add_check_btn')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('feature_check_input')),
            'Tap Space along barrier -> Mech glides smoothly without clip',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('feature_check_save_btn')),
          );
          final addedCheck = wb.selectedFeatureSpec!.checks.last;
          expect(
            addedCheck.text,
            equals(
              'Tap Space along barrier -> Mech glides smoothly without clip',
            ),
          );
          await _tapVisible(
            tester,
            find.byKey(ValueKey('feature_check_${addedCheck.id}')),
          );
          expect(wb.selectedFeatureSpec!.checks.last.passed, isTrue);

          // Stage 2 FloatingAiRefineDock (mocked gemini-4-hydrogen) + Undo restore
          final preStage2AiGoal = wb.selectedFeatureSpec!.goal;
          final preStage2AiDash = wb.selectedFeatureSpec!.tuning.first.value;
          await tester.enterText(
            find.byKey(const ValueKey('stage2_ai_refine_input')),
            'Boost DashDistance to 620 cm and add shockwave ring cue',
          );
          await tester.tap(
            find.byKey(const ValueKey('stage2_ai_refine_apply_btn')),
          );
          await tester.pumpAndSettle();

          expect(
            recordedGeminiCalls.last.tool,
            equals('patch_unreal_feature_spec'),
          );
          expect(
            recordedGeminiCalls.last.model,
            equals(GeminiAgentClient.pinnedLiveFlashModel),
          );
          expect(recordedGeminiCalls.last.thinkingLevel, equals('LOW'));
          expect(wb.selectedFeatureSpec!.tuning.first.value, equals('620'));
          expect(
            find.text('✓ Boosted DashDistance to 620 cm and added cue'),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(const ValueKey('stage2_ai_refine_undo_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.selectedFeatureSpec!.goal, equals(preStage2AiGoal));
          expect(
            wb.selectedFeatureSpec!.tuning.first.value,
            equals(preStage2AiDash),
          );

          // 7) CoPilot Preview modal (Compact DSL -> Readable View -> close) + Flag [FIX] -> Resolve [FIX]
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('preview_copilot_prompt_btn')),
          );
          expect(
            find.textContaining('@OWNERS:'),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              'create missing @OWNERS if absent, else extend existing',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Paste size: ~'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('copilot_preview_local_note')),
            findsOneWidget,
          );
          expect(
            find.text('Compiled locally in memory (0 AI tokens spent by LAYERS)'),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(const ValueKey('preview_mode_readable_btn')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('dialog_copy_readable_prompt_btn')),
            findsOneWidget,
          );
          expect(find.textContaining('(Human MD)'), findsOneWidget);

          await tester.tap(
            find.byKey(const ValueKey('close_copilot_preview_btn')),
          );
          await tester.pumpAndSettle();

          // Flag [FIX] revision -> CTA switches to 🔧 Copy CoPilot [FIX] Prompt (1) -> Resolve [FIX]
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('flag_fix_input')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('flag_fix_input')),
            'Dash clips north corner pillar hitbox',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('flag_fix_btn')),
          );
          expect(
            find.text('Copy CoPilot [FIX] Prompt (1)'),
            findsOneWidget,
          );

          final fxId = wb.selectedFeatureSpec!.fixes.first.id;
          await _tapVisible(
            tester,
            find.byKey(ValueKey('resolve_fix_$fxId')),
          );
          expect(find.text('Copy CoPilot Prompt'), findsOneWidget);

          // 8) Pass every slice in v0.1 -> release_complete_banner -> + New Release -> v0.2 ([+DELTA] + [+NEW])
          // -> locked [v0.1] baseline banner + Open in v0.1 -> v0.2 delta protects baseline checks
          while (!wb.isActiveReleaseComplete) {
            final feat = wb.selectedFeatureSpec;
            if (feat == null || feat.isPassed) {
              final jumped = wb.selectNextOpenFeature();
              expect(jumped, isTrue);
              await tester.pumpAndSettle();
              continue;
            }
            for (final chk in feat.effectiveChecksForRelease('v0.1')) {
              if (!chk.passed) {
                await _tapVisible(
                  tester,
                  find.byKey(ValueKey('feature_check_${chk.id}')),
                );
              }
            }
            await tester.ensureVisible(
              find.byKey(const ValueKey('pass_feature_btn')),
            );
            await tester.tap(find.byKey(const ValueKey('pass_feature_btn')));
            await tester.pumpAndSettle();
          }

          expect(
            find.byKey(const ValueKey('release_complete_banner')),
            findsOneWidget,
          );
          expect(
            find.text('✓ v0.1 Complete (7/7 Slices Passed)'),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(const ValueKey('plan_next_release_btn')),
          );
          await tester.pumpAndSettle();

          expect(
            recordedGeminiCalls.last.tool,
            equals('propose_progressive_unreal_release'),
          );
          expect(
            recordedGeminiCalls.last.model,
            equals(GeminiAgentClient.pinnedArchitectModel),
          );
          expect(recordedGeminiCalls.last.thinkingLevel, equals('MEDIUM'));

          // Select [+DELTA] upgrade on F02 + [+NEW] Feature F08 inside E01 (deselecting preset defaults if any)
          final upCheckbox = find.byKey(
            const ValueKey('copilot_up_up_e01_hitstop'),
          );
          final newFeatCheckbox = find.byKey(
            const ValueKey('copilot_new_feat_sb_f08_chain'),
          );
          expect(upCheckbox, findsOneWidget);
          expect(newFeatCheckbox, findsOneWidget);

          if (!tester.widget<CheckboxListTile>(upCheckbox).value!) {
            await _tapVisible(tester, upCheckbox);
          }
          if (!tester.widget<CheckboxListTile>(newFeatCheckbox).value!) {
            await _tapVisible(tester, newFeatCheckbox);
          }
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('copilot_commit_btn')),
          );

          expect(wb.activeReleaseVersionTag, equals('v0.2'));
          final v02ReleaseId = wb.activeReleaseId!;

          // Verify [+NEW] F08 lives inside permanent E01 without duplicating Epic cards
          expect(
            find.byKey(const ValueKey('outliner_feature_sb_f08_chain')),
            findsOneWidget,
          );

          // Untouched baseline F01 shows locked_baseline_banner & Open in v0.1 -> jumps cleanly
          await tester.tap(
            find.byKey(const ValueKey('outliner_feature_sb_f01')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('locked_baseline_banner')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('pass_feature_btn')), findsNothing);
          expect(
            find.byKey(const ValueKey('stage2_ai_refine_input')),
            findsNothing,
          );

          await tester.tap(
            find.byKey(const ValueKey('open_in_baseline_btn')),
          );
          await tester.pumpAndSettle();
          expect(wb.activeReleaseVersionTag, equals('v0.1'));
          expect(
            find.byKey(const ValueKey('locked_baseline_banner')),
            findsNothing,
          );

          // Return to v0.2 and check unlocked [+DELTA] slice F02 protects v0.1 baseline checks
          await tester.tap(
            find.byKey(ValueKey('outliner_release_$v02ReleaseId')),
          );
          await tester.pumpAndSettle();
          expect(wb.activeReleaseVersionTag, equals('v0.2'));

          await tester.tap(
            find.byKey(const ValueKey('outliner_feature_sb_f02')),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('+DELTA (v0.2):'), findsOneWidget);
          expect(find.text('Copy CoPilot Delta Prompt'), findsOneWidget);
          expect(find.byKey(const ValueKey('pass_feature_btn')), findsOneWidget);

          final deltaF02 = wb.selectedFeatureSpec!;
          expect(deltaF02.checks, isNotEmpty);
          expect(deltaF02.releaseDeltaChecks, isNotEmpty);
          for (final baseChk in deltaF02.checks) {
            expect(
              find.byKey(ValueKey('feature_check_delete_${baseChk.id}')),
              findsNothing,
            );
          }
          for (final deltaChk in deltaF02.releaseDeltaChecks) {
            expect(
              find.byKey(ValueKey('feature_check_delete_${deltaChk.id}')),
              findsOneWidget,
            );
          }

          final baseCheckCountBefore = deltaF02.checks.length;
          wb.removeFeatureCheck(
            wb.selectedEpicSpec!.id,
            deltaF02.id,
            deltaF02.checks.first.id,
          );
          await tester.pumpAndSettle();
          expect(
            wb.selectedFeatureSpec!.checks.length,
            equals(baseCheckCountBefore),
          );
        });
      },
    );

    testWidgets(
      'Scenario 2 — Light Theme + Laptop (1280x800) & Compact (1040x768) Ergonomics Check',
      (tester) async {
        final memoryVault = _MemoryVaultBackend();
        final fakeGddBackend = _FakeLocalGddBackend();
        _installDogfoodTestHooks(memoryVault: memoryVault);

        for (final viewport in const <Size>[Size(1280, 800), Size(1040, 768)]) {
          await _runWithDogfoodViewport(tester, viewport, () async {
            final wb = WorkbenchProvider(enableAutoLoad: false)
              ..setLocalGddBackendForTest(fakeGddBackend)
              ..loadPresetSpark('shellbreaker');
            addTearDown(wb.dispose);
            await wb.linkLocalGddFile();

            await tester.pumpWidget(LayersAgenticApp(provider: wb));
            await tester.pumpAndSettle();

            // Toggle to Light theme via Settings ▾ menu
            await tester.tap(
              find.byKey(const ValueKey('header_settings_menu_btn')),
            );
            await tester.pumpAndSettle();
            final themeToggle = find.byKey(
              const ValueKey('settings_theme_toggle_btn'),
            );
            expect(themeToggle, findsOneWidget);
            await tester.tap(themeToggle);
            await tester.pumpAndSettle();
            await tester.tapAt(const Offset(20, 200));
            await tester.pumpAndSettle();
            expect(wb.isDark, isFalse);

            // Stage 1 (Project Brief) checks: zero overflow + primary controls mounted & hittable
            expect(find.byType(ProjectPitchScreen), findsOneWidget);
            _expectMountedAndHittable(<Finder>[
              find.byKey(const ValueKey('header_gdd_menu_btn')),
              find.byKey(const ValueKey('header_settings_menu_btn')),
              find.byKey(const ValueKey('stage1_mode_blueprint')),
              find.byKey(const ValueKey('stage1_mode_cpp_hybrid')),
              find.byKey(const ValueKey('approve_launch_workbench_btn')),
              find.byKey(const ValueKey('stage1_codesign_input')),
              find.byKey(const ValueKey('stage1_codesign_apply_btn')),
            ]);

            // Approve & Launch into Release Spec -> Continue into F01..F0N
            await tester.tap(
              find.byKey(const ValueKey('approve_launch_workbench_btn')),
            );
            await tester.pumpAndSettle();
            expect(wb.isInspectingReleaseSpec, isTrue);
            await tester.tap(
              find.byKey(const ValueKey('release_primary_action_btn')),
            );
            await tester.pumpAndSettle();
            expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);

            final e01 = wb.activeReleaseEpics.first;
            final f02 = e01.features.firstWhere((f) => f.code == 'F02');
            wb.selectFeature(e01.id, f02.id);
            await tester.pumpAndSettle();

            _expectMountedAndHittable(<Finder>[
              find.byKey(const ValueKey('outliner_project_brief')),
              find.byKey(const ValueKey('plan_next_release_btn')),
              find.byKey(const ValueKey('header_gdd_menu_btn')),
              find.byKey(const ValueKey('header_settings_menu_btn')),
              find.byKey(ValueKey('outliner_epic_${e01.id}')),
              find.byKey(ValueKey('outliner_feature_${f02.id}')),
              find.byKey(const ValueKey('copy_copilot_prompt_btn')),
              find.byKey(const ValueKey('preview_copilot_prompt_btn')),
              find.byKey(const ValueKey('pass_feature_btn')),
              find.byKey(const ValueKey('stage2_ai_refine_input')),
              find.byKey(const ValueKey('stage2_ai_refine_apply_btn')),
            ]);

            // Also navigate to Epic Domain Sheet & back via nav pills to ensure zero overflows on E01 sheet
            await tester.tap(find.byKey(const ValueKey('crumb_epic')));
            await tester.pumpAndSettle();
            expect(wb.isInspectingEpicDomain, isTrue);
            _expectMountedAndHittable(<Finder>[
              find.byKey(const ValueKey('epic_more_menu_btn')),
              find.byKey(const ValueKey('epic_inspect_first_feature_btn')),
              find.byKey(const ValueKey('stage2_ai_refine_input')),
            ]);

            // Project Brief <-> Release Spec <-> Feature switch via left outliner & breadcrumbs
            await tester.tap(find.byKey(const ValueKey('outliner_project_brief')));
            await tester.pumpAndSettle();
            expect(find.byType(ProjectPitchScreen), findsOneWidget);
            _expectMountedAndHittable(<Finder>[
              find.byKey(const ValueKey('outliner_project_brief')),
              find.byKey(const ValueKey('approve_launch_workbench_btn')),
            ]);

            await tester.tap(find.byKey(const ValueKey('approve_launch_workbench_btn')));
            await tester.pumpAndSettle();
            expect(find.byType(ReleaseWorkbenchScreen), findsOneWidget);
          });
        }
      },
    );
  });
}

void _expectMountedAndHittable(List<Finder> finders) {
  for (final finder in finders) {
    expect(finder, findsOneWidget);
    expect(
      finder.hitTestable(),
      findsOneWidget,
      reason: 'Expected control $finder to be hittable within viewport',
    );
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _installDogfoodTestHooks({
  required _MemoryVaultBackend memoryVault,
  http.Response Function(Uri uri, Map<String, dynamic> body)? onGeminiCall,
}) {
  GeminiAgentClient.resetCapabilityCacheForTest();
  GeminiAgentClient.resetUsage();
  GeminiAgentClient.testMockResponder = null;
  GeminiAgentClient.testBaseRetryDelay = Duration.zero;
  LocalVaultService.testBackendOverride = memoryVault;

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

Future<void> _runWithDogfoodViewport(
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
  expect(
    caughtErrors,
    isEmpty,
    reason: caughtErrors.join('\n---\n'),
  );
}

class _MemoryVaultBackend implements VaultStorageBackend {
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

class _FakeLocalGddBackend implements LocalGddFileBackend {
  bool denyPermission = false;
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
    writtenContents.add(content);
    return const LocalGddWriteResult(written: true);
  }

  @override
  Future<void> unlinkProject(String projectId) async {
    linkedHandles.remove(projectId);
  }
}
