import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layers_agentic/agents/project_concept_agent.dart';
import 'package:layers_agentic/main.dart';
import 'package:layers_agentic/models/feature_state.dart';
import 'package:layers_agentic/models/tier_document.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';

void main() {
  group('LAYERS-Agentic 3-Stage End-to-End Flow Tests', () {
    test('ProjectConceptAgent seeds turn-by-turn chat and updates Live Concept Blueprint on each turn', () async {
      final draft = await ProjectConceptAgent.startConceptInterview(
        'High-speed grappling hook parkour roguelite',
      );
      expect(draft.questions.length, 3);
      expect(draft.isInterviewComplete, isTrue);
      expect(draft.chatHistory.length, 2);
      expect(draft.coreLoopBeats.length, greaterThanOrEqualTo(6));
      expect(draft.releaseTrainTitles.length, 1);

      // Send a user turn in the chat and verify the Blueprint updates in real time
      final updated = await ProjectConceptAgent.sendConceptChatTurn(
        draft,
        '2D Side-Scrolling Precision Platformer',
      );

      expect(updated.chatHistory.length, 4);
      expect(updated.goal, contains('2D Side-Scrolling Precision Platformer'));
      expect(updated.toFormattedScopeSection(), contains('Goal:'));
      expect(updated.toFormattedScopeSection(), contains('In Scope:'));
      expect(updated.toFormattedScopeSection(), contains('Out of Scope:'));
      expect(updated.toFormattedScopeSection(), contains('Done When:'));
    });

    testWidgets(
      'Full 3-Stage Antigravity Flow: Spark -> Concept Interview -> Release Plan Gate -> 60/40 Active Workbench',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final provider = WorkbenchProvider();

        await tester.pumpWidget(LayersAgenticApp(provider: provider));
        await tester.pumpAndSettle();

        // ── Stage 1A: The Spark (3 Side-by-Side Starter Concept Playing Cards) ──
        expect(find.byKey(const ValueKey('connected_pipeline_track')), findsOneWidget);
        expect(find.text('STEP 1A · THE SPARK'), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_2')), findsOneWidget);
        expect(find.byKey(const ValueKey('start_concept_interview_btn')), findsOneWidget);

        // 1-Click Launch via Playing Card #1 ('Grapple Hook Parkour')
        await tester.tap(find.byKey(const ValueKey('spark_card_0')));
        await tester.pumpAndSettle();

        // ── Stage 1B: One-Section-at-a-Time Dynamic UI (Sections 01..09) ──
        expect(find.byKey(const ValueKey('top_bar_project_title')), findsOneWidget);
        expect(find.byKey(const ValueKey('project_switcher_dropdown_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('cloud_sync_auth_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('global_export_spec_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('concept_interview_card')), findsOneWidget);
        expect(find.byKey(const ValueKey('concept_sticky_bottom_dock')), findsOneWidget);
        expect(find.byKey(const ValueKey('new_spark_reset_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('agent_option_card_0_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('agent_option_card_0_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('agent_option_card_0_2')), findsOneWidget);
        expect(find.text('SECTION 01 / 09'), findsOneWidget);
        expect(find.text('Goal'), findsWidgets);

        // Step to Section 02 (Game Spec) and verify 2x2 KV grid labels
        await tester.tap(find.byKey(const ValueKey('next_section_btn')));
        await tester.pumpAndSettle();
        expect(find.text('SECTION 02 / 09'), findsOneWidget);
        expect(find.text('CAMERA VIEW'), findsOneWidget);
        expect(find.text('CONTROLS'), findsOneWidget);

        // Step to Section 03 (Tech Spec) and verify 2x2 KV grid labels
        await tester.tap(find.byKey(const ValueKey('next_section_btn')));
        await tester.pumpAndSettle();
        expect(find.text('SECTION 03 / 09'), findsOneWidget);
        expect(find.text('ENGINE'), findsOneWidget);
        expect(find.text('PLATFORM'), findsOneWidget);

        // Step to Section 04 (Design Pillars — plain label, never "Load-Bearing")
        await tester.tap(find.byKey(const ValueKey('next_section_btn')));
        await tester.pumpAndSettle();
        expect(find.text('SECTION 04 / 09'), findsOneWidget);
        expect(find.text('Design Pillars'), findsWidgets);
        expect(find.textContaining('Load-Bearing'), findsNothing);

        // Jump to Step 10: Full Blueprint Review
        final synthBtn = find.byKey(const ValueKey('synthesize_concept_btn'));
        await tester.ensureVisible(synthBtn);
        await tester.pumpAndSettle();
        await tester.tap(synthBtn);
        await tester.pumpAndSettle();

        // ── Stage 1C: Step 10 Full Blueprint Review & Release Train ──
        expect(find.byKey(const ValueKey('project_blueprint_card')), findsOneWidget);
        expect(find.byKey(const ValueKey('concept_sticky_bottom_dock')), findsOneWidget);
        expect(find.text('STEP 10 · FINAL BLUEPRINT VERIFICATION'), findsOneWidget);
        expect(find.text('v0.1: Core Movement & Game Loop - Prototype'), findsOneWidget);
        final approveConceptBtn = find.byKey(const ValueKey('approve_concept_plan_release_btn'));
        await tester.ensureVisible(approveConceptBtn);
        await tester.pumpAndSettle();
        await tester.tap(approveConceptBtn);
        await tester.pumpAndSettle();

        // ── Stage 2: Antigravity Release Plan Gate ──
        expect(find.byKey(const ValueKey('release_plan_gate_banner')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_hour_budget_bar')), findsOneWidget);
        expect(find.byKey(const ValueKey('toggle_release_questions_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('answered_decisions_strip')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage2_beat_jump_bar')), findsOneWidget);
        expect(find.byKey(const ValueKey('toggle_all_feat_specs_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_question_card_0_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_question_card_0_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_question_card_0_2')), findsOneWidget);
        expect(find.text('STAGE 2 · RELEASE PLAN GATE'), findsOneWidget);
        expect(find.text('Staging & Loadout Prep Mechanics & Controls'), findsOneWidget);
        expect(find.text('Bonus Time-Trial Medals'), findsOneWidget);
        expect(find.byKey(const ValueKey('restore_deferred_feat_feat_7_2')), findsOneWidget);

        // Verify collapsing Clarifying Release Questions into the Answered Decisions Summary Strip
        await tester.tap(find.byKey(const ValueKey('toggle_release_questions_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('release_question_card_0_0')), findsNothing);
        expect(find.byKey(const ValueKey('answered_decisions_strip')), findsOneWidget);

        // Verify all 7 Stage 1 Core Loop Beats map 1-to-1 into Stage 2 (8 included features across 7 beats)
        expect(provider.releaseBlueprint!.beats.length, 7);
        expect(provider.releaseBlueprint!.totalIncludedFeatures, 8);
        expect(find.byKey(const ValueKey('release_sticky_bottom_dock')), findsOneWidget);

        // Verify Expandable Checkpoint & Playtest Preview Drawer on Beat 1 Feature 1
        final firstProposedFeatId = provider.releaseBlueprint!.beats.first.features.first.id;
        final inspectBtn = find.byKey(ValueKey('inspect_feat_$firstProposedFeatId'));
        expect(find.byKey(ValueKey('inspect_feat_drawer_$firstProposedFeatId')), findsNothing);
        await tester.ensureVisible(inspectBtn);
        await tester.pumpAndSettle();
        await tester.tap(inspectBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('inspect_feat_drawer_$firstProposedFeatId')), findsOneWidget);

        final buildRelBtn = find.byKey(const ValueKey('approve_and_build_release_btn'));
        await tester.ensureVisible(buildRelBtn);
        await tester.pumpAndSettle();
        await tester.tap(buildRelBtn);
        await tester.pumpAndSettle();

        // ── Stage 3: Active Release Workbench (60/40 Checkpoints + Sticky Studio Dock) ──
        expect(find.text('ACTIVE RELEASE'), findsOneWidget);
        expect(find.text('Staging & Loadout Prep Mechanics & Controls'), findsWidgets);
        expect(find.text('CHECKPOINT 1'), findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_two_col_row_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_spec_pane_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('prev_feature_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('next_feature_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('add_tuning_btn_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('add_edge_guard_btn_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('edit_playtest_btn_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('add_checkpoint_header_btn')), findsOneWidget);

        // Verify Stage 3 Sticky Bottom Studio Dock & Toggleable 3 Co-Pilot Playing Cards Drawer
        expect(find.byKey(const ValueKey('workbench_sticky_bottom_dock')), findsOneWidget);
        expect(find.byKey(const ValueKey('toggle_copilot_drawer_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('copilot_card_add_checkpoint')), findsOneWidget);
        expect(find.byKey(const ValueKey('copilot_card_suggest_tuning')), findsOneWidget);
        expect(find.byKey(const ValueKey('copilot_card_add_guards')), findsOneWidget);
        expect(find.byKey(const ValueKey('workbench_copilot_input')), findsOneWidget);
        expect(find.byKey(const ValueKey('copy_feature_markdown_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('dock_prev_feature_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('dock_next_feature_btn')), findsOneWidget);

        // Verify 60/40 horizontal placement (Checklist Left | Spec Context Right)
        final leftTaskPos = tester.getTopLeft(
          find.text('Implement core state and player interaction for Staging & Loadout Prep (3h)'),
        );
        final rightSpecPos = tester.getTopLeft(
          find.byKey(const ValueKey('checkpoint_spec_pane_0')),
        );
        expect(leftTaskPos.dx, lessThan(rightSpecPos.dx));

        // Verify Focus Mode is ON by default
        expect(provider.focusMode, isTrue);

        // Verify Option 2: Stage 3 Live Concept & Pillars Reference Drawer toggle
        expect(find.byKey(const ValueKey('stage3_pillars_reference_drawer')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('toggle_pillars_drawer_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('stage3_pillars_reference_drawer')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('toggle_pillars_drawer_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('stage3_pillars_reference_drawer')), findsNothing);

        // Verify Checkable How-To Sub-Steps on the Right Pane + Automatic Rollup to Parent Task
        final activeFeat = provider.selectedFeature!;
        final cp0Id = provider.documents[activeFeat.id]!.subtasks.first.id;
        expect(find.textContaining('0/3 steps'), findsWidgets);
        final subStep0 = find.byKey(ValueKey('howto_substep_${cp0Id}_0_0'));
        await tester.ensureVisible(subStep0);
        await tester.pumpAndSettle();
        await tester.tap(subStep0);
        await tester.pumpAndSettle();
        expect(find.textContaining('1/3 steps'), findsOneWidget);

        // Verify "+ Add How-To Sub-Step" appends a 4th checkable sub-step to Task 01
        final addSubStepBtn = find.byKey(const ValueKey('add_howto_substep_btn_0'));
        await tester.ensureVisible(addSubStepBtn);
        await tester.pumpAndSettle();
        await tester.tap(addSubStepBtn);
        await tester.pumpAndSettle();
        expect(find.textContaining('1/4 steps'), findsOneWidget);

        // Verify 1-Click "Copy 📋" on a How-To sub-step copies the code formula without toggling completion
        final copyCodeBtn = find.byKey(ValueKey('copy_howto_code_${cp0Id}_0_1'));
        await tester.ensureVisible(copyCodeBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyCodeBtn);
        await tester.pumpAndSettle();
        expect(find.textContaining('1/4 steps'), findsOneWidget);

        // Verify Task-Scoped AI "✦ Tailor How-To" rewrites sub-steps with exact scene/node context
        final tailorBtn = find.byKey(ValueKey('tailor_howto_btn_${cp0Id}_0'));
        await tester.ensureVisible(tailorBtn);
        await tester.pumpAndSettle();
        await tester.tap(tailorBtn);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('tailor_howto_context_input')),
          'CharacterBody2D with RayCast2D HookRay and Line2D RopeVisual',
        );
        await tester.tap(find.byKey(const ValueKey('confirm_tailor_howto_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('HookRay'), findsWidgets);
        expect(find.textContaining('RopeVisual'), findsWidgets);

        // Verify interactive Out-of-Scope shelf toggle
        expect(find.byKey(const ValueKey('feat_out_of_scope_shelf')), findsNothing);
        final outBtn = find.byKey(const ValueKey('feat_out_of_scope_btn'));
        await tester.ensureVisible(outBtn);
        await tester.pumpAndSettle();
        await tester.tap(outBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('feat_out_of_scope_shelf')), findsOneWidget);

        // Verify inline "+ Add task step..." input appends a task to Checkpoint 1
        final addInput = find.byKey(const ValueKey('add_checkpoint_task_input_0'));
        await tester.ensureVisible(addInput);
        await tester.pumpAndSettle();
        await tester.enterText(addInput, 'Verify grapple hook cooldown indicator');
        await tester.tap(find.byKey(const ValueKey('add_checkpoint_task_btn_0')));
        await tester.pumpAndSettle();
        expect(find.text('Verify grapple hook cooldown indicator'), findsOneWidget);

        // Verify 1-Click "✓ Verify Checkpoint →" button completes Checkpoint 1
        final quickVerifyBtn = find.byKey(const ValueKey('quick_verify_checkpoint_btn_0'));
        await tester.ensureVisible(quickVerifyBtn);
        await tester.pumpAndSettle();
        await tester.tap(quickVerifyBtn);
        await tester.pumpAndSettle();
        expect(find.text('VERIFIED ✓'), findsWidgets);

        // Verify 1-Click Co-Pilot Playing Card #1 (+ Add Polish Checkpoint) appends a new checkpoint
        await tester.tap(find.byKey(const ValueKey('copilot_card_add_checkpoint')));
        await tester.pumpAndSettle();
        expect(find.text('Screen Feedback & Feel Pass'), findsOneWidget);

        // Verify collapsing the Co-Pilot Playing Cards drawer frees vertical space
        await tester.tap(find.byKey(const ValueKey('toggle_copilot_drawer_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('copilot_card_add_checkpoint')), findsNothing);
      },
    );

    test(
      'Evolving from Release v0.1 to v0.2 preserves STABLE features (0h delta) and appends v0.2 checkpoints to UPGRADE features',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('High-speed grappling hook parkour roguelite');
        expect(provider.conceptDraft!.designPillars, isNotEmpty);
        expect(provider.conceptDraft!.tradeOffs, isNotEmpty);
        expect(provider.conceptDraft!.techSpec, isNotEmpty);

        // Plan & Execute v0.1
        await provider.openReleasePlanGate();
        await provider.approveAndExecuteReleasePlan();

        final v1Beats = provider.activeReleaseBeats;
        // All 7 Stage 1 Core Loop Beats carry into Stage 2 & Stage 3!
        expect(v1Beats.length, provider.conceptDraft!.coreLoopBeats.length);
        final v1FirstFeat = provider.featuresForBeat(v1Beats.first.id).first;
        expect(v1FirstFeat.title, 'Staging & Loadout Prep Mechanics & Controls');

        // Advance to v0.2 Plan Gate
        await provider.advanceToNextRelease();
        final v2Blueprint = provider.releaseBlueprint!;
        expect(v2Blueprint.releaseVersionTag, 'v0.2');

        // Beat 1 Feature 1 is upgraded (4h delta), Beat 1 Feature 2 is STABLE (0h delta)
        final b1f1 = v2Blueprint.beats[0].features[0];
        final b1f2 = v2Blueprint.beats[0].features[1];
        expect(b1f1.lifecycle.name, 'upgrade');
        expect(b1f1.activeDeltaHours, 4);
        expect(b1f2.lifecycle.name, 'stable');
        expect(b1f2.activeDeltaHours, 0);

        // Execute v0.2 and verify v0.1 checkpoints are preserved + v0.2 checkpoint is appended
        await provider.approveAndExecuteReleasePlan();
        final evolvedFeat = provider.documents[v1FirstFeat.id]!;
        expect(evolvedFeat.sections['lifecycle'], 'upgrade');
      },
    );

    test(
      'Blueprint JSON serialization & Multi-Project Vault Manager (Switch, Rename, Deep 4-Tier Duplicate, Collaborators, Delete) preserve Stage 1, 2, and 3 state',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('Tactical Mecha Extraction Shooter');
        await provider.openReleasePlanGate();
        await provider.approveAndExecuteReleasePlan();

        final proj1Id = provider.activeProjectId!;
        final origBeatsCount = provider.activeReleaseBeats.length;
        expect(provider.savedProjects.length, 1);
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);

        // Invite collaborator on Project 1
        final invited = await provider.inviteProjectCollaborator(
          collaboratorEmail: 'teammate@studio.dev',
        );
        expect(invited, isTrue);
        expect(
          provider.collaboratorsForProject(proj1Id).map((c) => c['email']),
          contains('teammate@studio.dev'),
        );

        // Rename Project 1
        provider.renameProject(proj1Id, 'Mecha Drop v1');
        expect(provider.documents[proj1Id]!.title, 'Mecha Drop v1');

        // Deep 4-Tier Duplicate Project 1 (Project -> Release -> Beat -> Feature + Checkpoints)
        final dupId = provider.duplicateProject(proj1Id);
        expect(dupId, isNotNull);
        expect(provider.savedProjects.length, 2);
        expect(provider.activeProjectId, dupId);
        expect(provider.documents[dupId!]!.title, 'Mecha Drop v1 (Copy)');
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);
        expect(provider.activeReleaseBeats.length, origBeatsCount);
        expect(
          provider.featuresForBeat(provider.activeReleaseBeats.first.id),
          isNotEmpty,
        );

        // Create a third project via createNewProject()
        provider.createNewProject();
        expect(provider.conceptDraft, isNull);
        expect(provider.currentStage, WorkbenchStage.projectPitch);

        await provider.startConceptInterview('Cozy Alchemy Shop & Dungeon Forager');
        final proj3Id = provider.activeProjectId!;
        expect(provider.savedProjects.length, 3);

        // Delete the duplicated project
        provider.deleteProject(dupId);
        expect(provider.savedProjects.length, 2);

        // Switch back to Project 1 and verify Stage 1, 2, and 3 state restored from JSON metadata
        provider.switchProject(proj1Id);
        expect(provider.activeProjectId, proj1Id);
        expect(provider.conceptDraft!.sparkIdea, 'Tactical Mecha Extraction Shooter');
        expect(provider.releaseBlueprint, isNotNull);
        expect(provider.currentStage, WorkbenchStage.releaseWorkbench);
        expect(provider.activeReleaseBeats, isNotEmpty);

        // Delete Project 3
        provider.deleteProject(proj3Id);
        expect(provider.savedProjects.length, 1);
      },
    );

    test(
      'Engine-Aware TaskHowToBlueprint.resolve adapts whereLocation and code formulas for Godot 4, Unity C#, and Unreal 5',
      () {
        final cp = FeatureStateNode(
          id: 'cp_test',
          name: 'Stage 1: Greybox Core Loop',
          trigger: 'Verify movement and dash in arena.',
          tuningParams: const ['move_speed: 240 px/s', 'dash_cooldown: 0.4 s'],
          edgeCases: const ['[GUARD] Ignore dash input while airborne'],
        );

        final godotTask = Subtask(
          id: 't_godot',
          text: 'Bind WASD movement and dash physics velocity',
          completed: false,
        );
        final godotBp = TaskHowToBlueprint.resolve(
          parentTask: godotTask,
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Godot 4.3 GDScript 2D',
        );
        expect(godotBp.engineLabel, 'GODOT 4');
        expect(godotBp.whereLocation, contains('_physics_process'));
        expect(godotBp.subSteps[0].codeFormula, contains('Input.is_action_pressed'));
        expect(godotBp.subSteps[1].codeFormula, contains('move_toward'));

        final unityTask = Subtask(
          id: 't_unity',
          text: 'Bind WASD movement and dash physics velocity',
          completed: false,
        );
        final unityBp = TaskHowToBlueprint.resolve(
          parentTask: unityTask,
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Unity 6 C# URP',
        );
        expect(unityBp.engineLabel, 'UNITY C#');
        expect(unityBp.whereLocation, contains('MonoBehaviour'));
        expect(unityBp.subSteps[0].codeFormula, contains('Input.GetButton'));
        expect(unityBp.subSteps[1].codeFormula, contains('Time.fixedDeltaTime'));

        final unrealTask = Subtask(
          id: 't_unreal',
          text: 'Bind WASD movement and dash physics velocity',
          completed: false,
        );
        final unrealBp = TaskHowToBlueprint.resolve(
          parentTask: unrealTask,
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
        );
        expect(unrealBp.engineLabel, 'UNREAL 5');
        expect(unrealBp.whereLocation, contains('ActorComponent'));
        expect(unrealBp.subSteps[0].codeFormula, contains('EMechanicState::Active'));
        expect(unrealBp.subSteps[1].codeFormula, contains('FMath::FInterpConstantTo'));
      },
    );

    test(
      'Stage 2 -> Stage 3 Custom Mechanic Breakdown synthesizes domain-specific tuning variables, edge guards, and 2 playable checkpoints',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('High-speed grappling hook parkour roguelite');
        await provider.openReleasePlanGate();

        final firstBeat = provider.releaseBlueprint!.beats.first;
        provider.addProposedFeatureToBeat(firstBeat.id, 'Grapple Hook Swing');

        final customFeatBp = firstBeat.features.last;
        expect(customFeatBp.title, 'Grapple Hook Swing');
        expect(customFeatBp.checkpoints.length, 2);
        expect(customFeatBp.tuningParams, contains('hookMaxRange: 18.0 m'));
        expect(customFeatBp.tuningParams, contains('hookPullSpeed: 28.0 m/s'));
        expect(
          customFeatBp.edgeCases.first,
          contains('[LOS BREAK GUARD]'),
        );

        // Also verify Stage 2 chat command "Add Ore Smelting Furnace to Beat 2" adds a tailored economy feature
        await provider.sendReleasePlanChatMessage('Add Ore Smelting Furnace to Beat 2');
        final secondBeat = provider.releaseBlueprint!.beats[1];
        final furnaceBp = secondBeat.features.last;
        expect(furnaceBp.title, 'Ore Smelting Furnace');
        expect(furnaceBp.checkpoints.length, 2);
        expect(furnaceBp.tuningParams, contains('transactionCostBase: 25 gold'));

        // Execute Stage 3 and verify the custom Grapple Hook Swing feature carries its 2 checkpoints & tuning into the Workbench
        await provider.approveAndExecuteReleasePlan();
        final stage3Beat1Feats = provider.featuresForBeat(
          provider.activeReleaseBeats.first.id,
        );
        final stage3GrappleDoc = stage3Beat1Feats.firstWhere(
          (f) => f.title == 'Grapple Hook Swing',
        );
        final stage3GrappleStates =
            FeatureStateNode.getStatesForDocument(stage3GrappleDoc);
        expect(stage3GrappleStates.length, 2);
        expect(
          stage3GrappleStates.first.tuningParams,
          contains('hookPullSpeed: 28.0 m/s'),
        );
      },
    );

    test(
      'Stage 2 Inline Feature Editing and Stage 3 Playtest Issue Triage ([FIX] task + [PLAYTEST GUARD] edge case)',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('Cyberpunk Grapple Arena');
        await provider.openReleasePlanGate();

        final firstBeat = provider.releaseBlueprint!.beats.first;
        provider.addProposedFeatureToBeat(firstBeat.id, 'Temp Debug Feature');
        final tempFeatId = firstBeat.features.last.id;
        provider.removeProposedFeatureFromBeat(firstBeat.id, tempFeatId);
        expect(firstBeat.features.any((f) => f.id == tempFeatId), isFalse);

        final targetFeat = firstBeat.features.first;
        provider.updateProposedFeatureInBeat(
          beatId: firstBeat.id,
          featureId: targetFeat.id,
          title: 'Wall Grapple & Vault',
          goal: 'Let the player latch onto walls and vault over ledges.',
          doneWhen: 'Player vaults 5 ledges in a row without clipping.',
          estimatedHours: 6,
          tuningParams: const ['grapplePullSpeed: 32.0 m/s', 'vaultBoost: 12.0 m/s'],
        );
        expect(targetFeat.title, 'Wall Grapple & Vault');
        expect(targetFeat.estimatedHours, 6);
        expect(targetFeat.tuningParams, contains('grapplePullSpeed: 32.0 m/s'));

        await provider.approveAndExecuteReleasePlan();
        final stage3Feats = provider.featuresForBeat(
          provider.activeReleaseBeats.first.id,
        );
        final builtFeat = stage3Feats.firstWhere(
          (f) => f.title == 'Wall Grapple & Vault',
        );
        final states = FeatureStateNode.getStatesForDocument(builtFeat);
        final initialTaskCount = states.first.checklist.length;

        final newFixIdx = provider.logPlaytestIssueOnCheckpoint(
          featureId: builtFeat.id,
          states: states,
          checkpointIndex: 0,
          issueDescription: 'Hook pulls player through thin walls',
        );
        expect(newFixIdx, initialTaskCount);

        final updatedStates = FeatureStateNode.getStatesForDocument(builtFeat);
        final fixTask = updatedStates.first.checklist.last;
        expect(fixTask.text, '[FIX] Hook pulls player through thin walls (1h)');
        expect(fixTask.children.length, 3);
        expect(
          fixTask.children.first.text,
          contains('REPRODUCE & INSPECT PLAYTEST ISSUE'),
        );
        expect(
          updatedStates.first.edgeCases,
          contains('[PLAYTEST GUARD] Hook pulls player through thin walls'),
        );
      },
    );
  });
}
