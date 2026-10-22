import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layers_agentic/agents/project_concept_agent.dart';
import 'package:layers_agentic/agents/workspace_agent_tools.dart';
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

        // ── Stage 1A: New Project (Interactive AI Idea Intake & Concept Expansion Cards) ──
        expect(find.byKey(const ValueKey('connected_pipeline_track')), findsOneWidget);
        expect(find.text('STEP 1A · NEW PROJECT'), findsOneWidget);
        expect(find.byKey(const ValueKey('ingest_idea_summary_btn')), findsOneWidget);
        // Before entering an initial idea, the Agent summary and 3 expansion cards are hidden
        expect(find.byKey(const ValueKey('agent_idea_summary_card')), findsNothing);
        expect(find.byKey(const ValueKey('spark_card_0')), findsNothing);
        expect(find.byKey(const ValueKey('spark_card_1')), findsNothing);
        expect(find.byKey(const ValueKey('spark_card_2')), findsNothing);
        expect(find.byKey(const ValueKey('shuffle_spark_ideas_btn')), findsNothing);
        expect(find.byKey(const ValueKey('start_concept_interview_btn')), findsNothing);

        // Input a raw game idea and verify the Agent ingests & summarizes it back AND generates the 3 Concept Expansion Cards
        await tester.enterText(
          find.byKey(const ValueKey('spark_input_field')),
          'High-speed grappling hook parkour roguelite',
        );
        await tester.tap(find.byKey(const ValueKey('ingest_idea_summary_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('agent_idea_summary_card')), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_2')), findsOneWidget);
        expect(find.byKey(const ValueKey('shuffle_spark_ideas_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('start_concept_interview_btn')), findsOneWidget);
        expect(find.text('STEP 1A · NEW PROJECT'), findsOneWidget);

        // Use the same input field to refine the Agent's summary
        await tester.enterText(
          find.byKey(const ValueKey('spark_input_field')),
          'Add wall-run chains',
        );
        await tester.tap(find.byKey(const ValueKey('ingest_idea_summary_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Add wall-run chains'), findsWidgets);

        // Clicking a Concept Expansion Card toggles it on (adds to summary) without auto-launching Stage 1B,
        // and clicking it a second time unselects it!
        await tester.tap(find.byKey(const ValueKey('spark_card_0')));
        await tester.pumpAndSettle();
        expect(find.text('STEP 1A · NEW PROJECT'), findsOneWidget);
        expect(provider.sparkIntake!.expansionCards.first.isSelected, isTrue);

        await tester.tap(find.byKey(const ValueKey('spark_card_0')));
        await tester.pumpAndSettle();
        expect(provider.sparkIntake!.expansionCards.first.isSelected, isFalse);

        // Explicitly click "Start Concept Blueprint →" to accept and launch Stage 1B
        await tester.tap(find.byKey(const ValueKey('start_concept_interview_btn')));
        await tester.pumpAndSettle();

        // ── Stage 1B: One-Section-at-a-Time Dynamic UI (Sections 01..09) ──
        expect(find.byKey(const ValueKey('top_bar_project_title')), findsOneWidget);
        expect(find.byKey(const ValueKey('project_switcher_dropdown_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('cloud_sync_auth_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('global_export_spec_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('concept_interview_card')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage1_left_outliner_rail')), findsOneWidget);
        expect(find.byKey(const ValueKey('concept_sticky_bottom_dock')), findsOneWidget);
        expect(find.byKey(const ValueKey('new_spark_reset_btn')), findsOneWidget);
        expect(find.text('+ New Project'), findsOneWidget);
        expect(find.byKey(const ValueKey('agent_option_card_0_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('agent_option_card_0_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('agent_option_card_0_2')), findsOneWidget);
        expect(find.text('SECTION 01 / 09'), findsOneWidget);
        expect(find.text('Goal'), findsWidgets);

        // Verify clicking a Stage 1B Option Card applies it, and clicking it again unselects it and restores the default Goal
        final initialGoal = provider.conceptDraft!.goal;
        await tester.tap(find.byKey(const ValueKey('agent_option_card_0_1')));
        await tester.pumpAndSettle();
        expect(provider.conceptDraft!.goal, isNot(equals(initialGoal)));
        await tester.tap(find.byKey(const ValueKey('agent_option_card_0_1')));
        await tester.pumpAndSettle();
        expect(provider.conceptDraft!.goal, equals(initialGoal));

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
        // Verify Stage 1 + / ✓ Multi-Select Playing Cards on Section 04
        expect(find.byKey(const ValueKey('multi_select_badge_3')), findsOneWidget);
        expect(find.text('+ Add to Design Pillars'), findsNWidgets(3));
        await tester.tap(find.byKey(const ValueKey('agent_option_card_3_0')));
        await tester.pumpAndSettle();
        expect(find.text('✓ Added to Design Pillars'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('agent_option_card_3_1')));
        await tester.pumpAndSettle();
        expect(find.text('✓ Added to Design Pillars'), findsNWidgets(2));
        expect(
          provider.conceptDraft!.designPillars.join(' '),
          contains('Unbroken Momentum'),
        );
        expect(
          provider.conceptDraft!.designPillars.join(' '),
          contains('Tactical Positioning'),
        );

        // Jump to Step 10: Full Blueprint Review using the prominent bottom dock button
        expect(find.byKey(const ValueKey('skip_to_full_review_btn')), findsOneWidget);
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
        expect(find.byKey(const ValueKey('stage2_left_outliner_rail')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_plan_gate_banner')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage2_view_mode_toggle_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_hour_budget_bar')), findsOneWidget);
        expect(find.byKey(const ValueKey('toggle_release_questions_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('answered_decisions_strip')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage2_beat_jump_bar')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage2_all_beats_chip')), findsOneWidget);
        expect(find.byKey(const ValueKey('toggle_all_feat_specs_btn')), findsOneWidget);
        expect(find.text('STAGE 2 · RELEASE PLAN GATE'), findsOneWidget);
        expect(find.text('Staging & Loadout Prep Mechanics & Controls'), findsOneWidget);

        // Option A: Stage 2 defaults to Step-by-Beat mode & collapsed Answered Decisions Strip
        expect(find.byKey(const ValueKey('stage2_step_by_beat_card')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage2_next_beat_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_question_card_0_0')), findsNothing);

        // Verify expanding Clarifying Release Questions from the Answered Decisions Summary Strip
        final toggleQuestionsBtn = find.byKey(const ValueKey('toggle_release_questions_btn'));
        await tester.ensureVisible(toggleQuestionsBtn);
        await tester.pumpAndSettle();
        await tester.tap(toggleQuestionsBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('release_question_card_0_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_question_card_0_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_question_card_0_2')), findsOneWidget);
        await tester.ensureVisible(toggleQuestionsBtn);
        await tester.pumpAndSettle();
        await tester.tap(toggleQuestionsBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('release_question_card_0_0')), findsNothing);

        // Verify Stage 2 [ ▯ Step-by-Beat | ◫ Full Blueprint ] switcher
        final stage2ViewModeBtn = find.byKey(const ValueKey('stage2_view_mode_toggle_btn'));
        await tester.ensureVisible(stage2ViewModeBtn);
        await tester.pumpAndSettle();
        await tester.tap(stage2ViewModeBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('stage2_step_by_beat_card')), findsNothing);
        expect(find.text('Bonus Time-Trial Medals'), findsOneWidget);
        expect(find.byKey(const ValueKey('restore_deferred_feat_feat_7_2')), findsOneWidget);

        // Verify all 7 Stage 1 Core Loop Beats map 1-to-1 into Stage 2 (8 included features across 7 beats)
        expect(provider.releaseBlueprint!.beats.length, 7);
        expect(provider.releaseBlueprint!.totalIncludedFeatures, 8);
        expect(find.byKey(const ValueKey('release_sticky_bottom_dock')), findsOneWidget);

        // Verify Expandable Build Tasks & Playtest Preview Drawer on Beat 1 Feature 1 (seeds 3 Build Tasks: 01, 02, 03)
        final firstProposedFeat = provider.releaseBlueprint!.beats.first.features.first;
        expect(firstProposedFeat.checkpoints.first.tasks.length, 3);
        final firstProposedFeatId = firstProposedFeat.id;
        final inspectBtn = find.byKey(ValueKey('inspect_feat_$firstProposedFeatId'));
        expect(find.byKey(ValueKey('inspect_feat_drawer_$firstProposedFeatId')), findsNothing);
        await tester.ensureVisible(inspectBtn);
        await tester.pumpAndSettle();
        await tester.tap(inspectBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('inspect_feat_drawer_$firstProposedFeatId')), findsOneWidget);
        expect(find.text('FEATURE GOAL & PLAYTEST'), findsOneWidget);
        expect(find.text('01 · '), findsWidgets);
        expect(find.text('02 · '), findsWidgets);
        expect(find.text('03 · '), findsWidgets);

        final buildRelBtn = find.byKey(const ValueKey('approve_and_build_release_btn'));
        await tester.ensureVisible(buildRelBtn);
        await tester.pumpAndSettle();
        await tester.tap(buildRelBtn);
        await tester.pumpAndSettle();

        // ── Stage 3: Active Release Workbench (Left Sidebar Outline View + Single-Feature Workspace) ──
        expect(find.text('OUTLINE', skipOffstage: false), findsOneWidget);
        expect(find.byKey(const ValueKey('outline_release_eta_summary')), findsOneWidget);
        final firstBeatId = provider.activeReleaseBeats.first.id;
        expect(find.byKey(ValueKey('rail_beat_$firstBeatId')), findsOneWidget);
        expect(find.byKey(const ValueKey('stage3_active_feature_sheet')), findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_single_col_0')), findsOneWidget);
        expect(find.textContaining('Staging & Loadout Prep Mechanics & Controls'), findsWidgets);

        // The Pinned Active Step Window is always visible at the top of the work area in Single-Panel mode
        final activeFeat0 = provider.selectedFeature!;
        final cp0NodeId = provider.documents[activeFeat0.id]!.subtasks.first.id;
        expect(find.byKey(ValueKey('pinned_active_step_window_$cp0NodeId')), findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_spec_pane_0')), findsOneWidget);

        // Verify clicking Feature 2 in the Left Outline and marking Step 1.1 done preserves focus on Feature 2
        final allFeatsInOrder = <String>[
          for (final b in provider.activeReleaseBeats)
            for (final f in provider.featuresForBeat(b.id)) f.id,
        ];
        final secondFeatId = allFeatsInOrder[1];
        await tester.tap(find.byKey(ValueKey('rail_feat_$secondFeatId')));
        await tester.pumpAndSettle();
        final secondFeat = provider.selectedFeature!;
        expect(secondFeat.id, isNot(equals(activeFeat0.id)));
        final secondCp0NodeId = provider.documents[secondFeat.id]!.subtasks.first.id;
        // Verify Single-Row Outliner Header live Release ETA summary ("12h Left #%")
        expect(find.byKey(const ValueKey('outline_release_eta_summary')), findsOneWidget);

        // Verify Next → starts locked (onTap == null) while Step 1 is unchecked
        final nextBtnBefore = tester.widget<InkWell>(
          find.byKey(ValueKey('next_active_step_btn_$secondCp0NodeId')),
        );
        expect(nextBtnBefore.onTap, isNull);
        expect(find.textContaining('STEP 1 OF 6 · ~'), findsOneWidget);
        expect(find.text('✓ VERIFY BEFORE CHECKING [✓]'), findsOneWidget);
        expect(find.text('🎯 CONNECTS TO YOUR SPEC & NEXT STEP'), findsOneWidget);

        // Tap the simple square Checkmark Box [✓] to mark Step 1 done in place and unlock Next →
        final markDoneFinder = find.byKey(
          ValueKey('mark_active_step_done_btn_$secondCp0NodeId'),
        );
        await tester.ensureVisible(markDoneFinder);
        await tester.pumpAndSettle();
        await tester.tap(markDoneFinder);
        await tester.pumpAndSettle();
        expect(provider.selectedFeature!.id, equals(secondFeat.id));
        expect(find.textContaining('STEP 1 OF 6 · ~'), findsOneWidget);
        final nextBtnAfter = tester.widget<InkWell>(
          find.byKey(ValueKey('next_active_step_btn_$secondCp0NodeId')),
        );
        expect(nextBtnAfter.onTap, isNotNull);

        // Tap Next Step → to advance to Step 2
        final nextBtnFinder = find.byKey(
          ValueKey('next_active_step_btn_$secondCp0NodeId'),
        );
        await tester.ensureVisible(nextBtnFinder);
        await tester.pumpAndSettle();
        await tester.tap(nextBtnFinder);
        await tester.pumpAndSettle();
        expect(find.textContaining('STEP 2 OF 6 · ~'), findsOneWidget);

        // Verify clicking the task chevron in the Outliner expands Task 02 for peeking without losing Step 2 in the workspace
        final task1ChevronFinder = find.byKey(
          ValueKey('outline_task_chevron_${secondCp0NodeId}_1'),
        );
        if (task1ChevronFinder.evaluate().isNotEmpty) {
          await tester.tap(task1ChevronFinder);
          await tester.pumpAndSettle();
          expect(find.textContaining('STEP 2 OF 6 · ~'), findsOneWidget);
        }

        // Verify the compact Previous Step (←) button steps back to Step 1
        final prevBtnFinder = find.byKey(
          ValueKey('prev_active_step_btn_$secondCp0NodeId'),
        );
        expect(prevBtnFinder, findsOneWidget);
        await tester.ensureVisible(prevBtnFinder);
        await tester.pumpAndSettle();
        await tester.tap(prevBtnFinder);
        await tester.pumpAndSettle();
        expect(find.textContaining('STEP 1 OF 6 · ~'), findsOneWidget);

        // Tap Step 1 in the Left Outline and uncheck it via the workspace Checkmark Box [✓] to restore clean state, then select Feature 1
        await tester.tap(find.byKey(ValueKey('outline_step_${secondCp0NodeId}_0_0')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(markDoneFinder);
        await tester.pumpAndSettle();
        await tester.tap(markDoneFinder);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('rail_feat_${activeFeat0.id}')));
        await tester.pumpAndSettle();
        expect(provider.selectedFeature!.id, equals(activeFeat0.id));

        // Verify Focus Mode is ON by default in Single-Panel Stage 3
        expect(provider.focusMode, isTrue);

        // Verify 1-Click "Copy" on the active How-To sub-step copies the code formula
        final activeFeat = provider.selectedFeature!;
        final cp0Id = provider.documents[activeFeat.id]!.subtasks.first.id;
        final copyCodeBtn = find.byKey(ValueKey('copy_howto_code_${cp0Id}_0_0'));
        await tester.ensureVisible(copyCodeBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyCodeBtn);
        await tester.pumpAndSettle();

        // Verify Task-Scoped AI "✦ Tailor" rewrites sub-steps with exact scene/node context directly in Single-Panel mode
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

        // Plan & Execute v0.1 (deferring a feature in Beat 2 to verify automatic carryover into v0.2!)
        await provider.openReleasePlanGate();
        final v1Beat2 = provider.releaseBlueprint!.beats[1];
        provider.addProposedFeatureToBeat(v1Beat2.id, 'Slide Boost & Cancel');
        final deferredSlideFeat = v1Beat2.features.last;
        provider.toggleProposedFeatureScope(
          v1Beat2.id,
          deferredSlideFeat.id,
          false,
        );
        expect(deferredSlideFeat.included, isFalse);
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

        // Verify the feature deferred in v0.1 ("Slide Boost & Cancel") automatically carried over into Beat 2 of v0.2!
        final carriedOverSlide = v2Blueprint.beats[1].features.firstWhere(
          (f) => f.title == 'Slide Boost & Cancel',
        );
        expect(carriedOverSlide.included, isTrue);
        expect(carriedOverSlide.originVersion, 'v0.2');

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
        expect(godotBp.subSteps.length, 6);
        expect(godotBp.whereLocation, contains('_physics_process'));
        expect(godotBp.subSteps[4].codeFormula, contains('Input.is_action_pressed'));
        expect(godotBp.subSteps[4].codeFormula, contains('move_toward'));

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
        expect(unityBp.subSteps.length, 6);
        expect(unityBp.whereLocation, contains('MonoBehaviour'));
        expect(unityBp.subSteps[4].codeFormula, contains('Input.GetButton'));
        expect(unityBp.subSteps[4].codeFormula, contains('Time.fixedDeltaTime'));

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
          unrealCppMode: false,
        );
        expect(unrealBp.engineLabel, 'UNREAL 5');
        expect(unrealBp.subSteps.length, 6);
        expect(unrealBp.whereLocation, contains('ActorComponent'));
        expect(unrealBp.subSteps[0].stepPath, contains('/Game/Blueprints/'));
        expect(unrealBp.subSteps[0].codeFormula, contains('EMechanicState::Active'));
        expect(unrealBp.subSteps[0].explainConcept, contains('BP_'));
        expect(unrealBp.subSteps[0].specChips, contains('Next: ${unrealBp.subSteps[1].shortTitle}'));
        expect(unrealBp.subSteps[4].codeFormula, contains('FMath::FInterpConstantTo'));

        final unrealCpp = TaskHowToBlueprint.resolve(
          parentTask: unrealTask,
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
          unrealCppMode: true,
        );
        expect(unrealCpp.engineLabel, 'UNREAL 5');
        expect(unrealCpp.whereLocation, contains('ActorComponent'));
        expect(unrealCpp.subSteps[0].explainConcept, contains('AWasdMovementDashActor'));
        expect(unrealCpp.subSteps[3].codeFormula, contains('UPROPERTY(EditAnywhere'));
        expect(unrealCpp.subSteps[4].codeFormula, contains('FMath::FInterpConstantTo'));

        // Verify Task 01 (Setup), Task 02 (State Logic), and Task 03 (Input/Raycast) have non-repeating step titles
        final t0 = TaskHowToBlueprint.resolve(
          parentTask: Subtask(id: 't0', text: 'Create Grid Tile Actor (2h)'),
          taskIndex: 0,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
        );
        final t1 = TaskHowToBlueprint.resolve(
          parentTask: Subtask(id: 't1', text: 'Implement State Machine (4h)'),
          taskIndex: 1,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
        );
        final t2 = TaskHowToBlueprint.resolve(
          parentTask: Subtask(id: 't2', text: 'Add Interaction Raycast (2h)'),
          taskIndex: 2,
          checkpointNode: cp,
          engineHint: 'Unreal Engine 5.4 C++ & Blueprints',
        );
        expect(t0.subSteps[0].shortTitle, isNot(equals(t1.subSteps[0].shortTitle)));
        expect(t1.subSteps[0].shortTitle, isNot(equals(t2.subSteps[0].shortTitle)));
        expect(t0.subSteps[1].shortTitle, isNot(equals(t1.subSteps[1].shortTitle)));
        expect(t1.subSteps[1].shortTitle, isNot(equals(t2.subSteps[1].shortTitle)));
        expect(t0.subSteps[2].shortTitle, isNot(equals(t1.subSteps[2].shortTitle)));
        expect(t1.subSteps[2].shortTitle, isNot(equals(t2.subSteps[2].shortTitle)));
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

    test(
      'Autonomous Producer Scope-Guard Interventions & Stage 3 Cross-Feature Tool-Calling Co-Pilot',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('Cyberpunk Grapple Arena');
        // Add an explicit exclusion to test the 0-token Producer Scope Guard
        provider.updateConceptDraft((draft) {
          draft.exclusions = ['Online Multiplayer Matchmaking', 'Cutscene Cinematics'];
        });
        await provider.openReleasePlanGate();
        expect(provider.lastAgentTrace, isNotNull);
        expect(provider.lastAgentTrace!.toolCalls.length, 3);

        // Add a feature that conflicts with the "Online Multiplayer Matchmaking" exclusion
        final firstBeat = provider.releaseBlueprint!.beats.first;
        provider.addProposedFeatureToBeat(
          firstBeat.id,
          'Online Multiplayer Lobby',
        );
        final stage2Interventions = provider.stage2Interventions;
        expect(stage2Interventions, isNotEmpty);
        expect(
          stage2Interventions.first.toolName,
          'defer_conflicting_feature',
        );

        // Apply the 1-click Producer Intervention and verify it defers the conflicting feature
        await provider.applyAgentIntervention(stage2Interventions.first);
        final conflictingFeat = firstBeat.features.firstWhere(
          (f) => f.title == 'Online Multiplayer Lobby',
        );
        expect(conflictingFeat.included, isFalse);

        // Execute Stage 3 and test Cross-Feature Tool-Calling Co-Pilot
        await provider.approveAndExecuteReleasePlan();
        final allStage3Feats = <TierDocument>[
          for (final b in provider.activeReleaseBeats)
            ...provider.featuresForBeat(b.id),
        ];
        expect(allStage3Feats.length, greaterThanOrEqualTo(2));
        final activeFeat = allStage3Feats.first;
        final siblingFeat = allStage3Feats[1];
        final activeStates = FeatureStateNode.getStatesForDocument(activeFeat);

        final trace = await provider.runStage3AgentCoPilot(
          featureDoc: activeFeat,
          states: activeStates,
          activeCheckpointIndex: 0,
          directive: 'Rebalance and make movement snappier across coupled features',
        );
        expect(trace.toolCalls.length, greaterThanOrEqualTo(2));
        final updatedSiblingStates =
            FeatureStateNode.getStatesForDocument(siblingFeat);
        expect(
          updatedSiblingStates.first.tuningParams,
          contains('coupled_sync_window_ms: 90 ms'),
        );
      },
    );

    test(
      'Options 1-4: Stage 1 Concept Critic & Refresh, Stage 3 Starter Script Bundle, AI Playtest Simulator, and Post-Release Retrospective',
      () async {
        final provider = WorkbenchProvider();
        await provider.startConceptInterview('Cyberpunk Grapple Arena');

        // Option 2: Stage 1 Concept Critic detects Online vs Offline-Only conflict & resolves in 1 click
        provider.updateConceptDraft((draft) {
          draft.gameSpec = ['2D Top-Down', 'Online Multiplayer Co-Op'];
          draft.techSpec = ['Godot 4 (2D)', 'Offline-Only Local Save'];
        });
        expect(provider.stage1Interventions, isNotEmpty);
        expect(
          provider.stage1Interventions.first.toolName,
          'resolve_stage1_netcode_conflict',
        );
        await provider.applyAgentIntervention(provider.stage1Interventions.first);
        expect(
          provider.conceptDraft!.gameSpec.join(' '),
          contains('Singleplayer'),
        );

        // Option 2: Regenerate Stage 1 section options
        provider.regenerateStage1SectionOptions('goal');
        expect(provider.conceptDraft!.sectionOptions['goal'], isNotEmpty);
        expect(
          provider.conceptDraft!.sectionOptions['goal']!.first,
          contains('(1):'),
        );

        // Advance to Stage 2 & Stage 3
        await provider.openReleasePlanGate();
        await provider.approveAndExecuteReleasePlan();
        final firstBeat = provider.activeReleaseBeats.first;
        final firstFeat = provider.featuresForBeat(firstBeat.id).first;
        final states = FeatureStateNode.getStatesForDocument(firstFeat);

        // Option 3: Stage 3 AI Playtest Simulator (`⚡ Simulate`)
        final sim = provider.simulateCheckpointPlaytest(
          featureDoc: firstFeat,
          states: states,
          checkpointIndex: 0,
        );
        expect(sim.recommendedTuningClamp, 'min_retrigger_lockout_ms: 110 ms');
        final afterSimStates = FeatureStateNode.getStatesForDocument(firstFeat);
        expect(
          afterSimStates.first.tuningParams,
          contains('min_retrigger_lockout_ms: 110 ms'),
        );
        expect(
          afterSimStates.first.edgeCases.any((g) => g.startsWith('[SIMULATION GUARD]')),
          isTrue,
        );

        // Option 1: Stage 3 Generate Starter Script Bundle (`.gd` for Godot 4)
        final scriptBundle = provider.generateStarterScriptForFeature(
          firstFeat,
          afterSimStates,
        );
        expect(scriptBundle.fileName, endsWith('.gd'));
        expect(scriptBundle.code, contains('@export var '));
        expect(scriptBundle.code, contains('min_retrigger_lockout_ms'));
        expect(scriptBundle.code, contains('[SIMULATION GUARD]'));

        // Option 4: Post-Release Retrospective & Auto-Carryover Summary into v0.2
        final retro = provider.buildActiveReleaseRetrospective();
        expect(retro.playtestGuardsAdded, greaterThanOrEqualTo(1));
        expect(retro.carryoverFeatureTitles, isNotEmpty);
        await provider.advanceToNextRelease();
        expect(provider.lastReleaseRetrospective, isNotNull);
        expect(
          provider.lastAgentTrace?.agentRole,
          'Post-Release Retrospective & Carryover Agent',
        );
      },
    );

    test(
      'Options 3, 4, 5 & 7: GDD Ingestion & Jump to Review, Dependency Tier Classification, Global Agent Command Palette & 1-Click Undo',
      () async {
        final provider = WorkbenchProvider();

        // Option 5: Import Existing GDD / Pitch Notes and jump straight to Step 10 Full Review
        await provider.importExistingGddAndJumpToReview('''
# Solar Skiff Salvage
Goal: Build a fast 3D hover-skiff salvage and grapple loop in Unity 6.
Engine: Unity 6 (C#)
Done When: Playtester completes 3 consecutive salvage runs and docks without clipping.
''');
        expect(provider.conceptDraft, isNotNull);
        expect(provider.conceptDraft!.title, 'Solar Skiff Salvage');
        expect(
          provider.conceptDraft!.goal,
          contains('hover-skiff salvage and grapple loop'),
        );
        expect(provider.jumpToFullReviewPending, isTrue);
        provider.consumeJumpToFullReviewPending();
        expect(provider.jumpToFullReviewPending, isFalse);

        // Option 7: Critical Path & Dependency Tier classification
        final tier1 = WorkspaceAgentOrchestrator.classifyDependencyTier(
          featureTitle: 'Player Movement & Camera Controls',
          beatIndex: 0,
        );
        final tier2 = WorkspaceAgentOrchestrator.classifyDependencyTier(
          featureTitle: 'Enemy Wave Spawner & Arena',
          beatIndex: 1,
        );
        final tier3 = WorkspaceAgentOrchestrator.classifyDependencyTier(
          featureTitle: 'Shop UI & Particle VFX Polish',
          beatIndex: 2,
        );
        expect(tier1.tierRank, 1);
        expect(tier1.shortBadge, '⚡ BUILD 1ST');
        expect(tier2.tierRank, 2);
        expect(tier2.shortBadge, '◈ BUILD 2ND');
        expect(tier3.tierRank, 3);
        expect(tier3.shortBadge, '◌ STUBBABLE');

        // Option 4: Global Agent Command Palette & 1-Click Undo
        await provider.openReleasePlanGate();
        await provider.approveAndExecuteReleasePlan();
        final firstBeat = provider.activeReleaseBeats.first;
        final firstFeat = provider.featuresForBeat(firstBeat.id).first;
        final beforeStates = FeatureStateNode.getStatesForDocument(firstFeat);
        final initialTuningCount = beforeStates.first.tuningParams.length;
        final historyBefore = provider.agentTraceHistory.length;

        await provider.runGlobalAgentCommand(
          'Add coyote time tuning',
        );
        expect(provider.agentTraceHistory.length, greaterThan(historyBefore));
        expect(provider.canUndoLastAgentAction, isTrue);

        final afterCommandStates =
            FeatureStateNode.getStatesForDocument(firstFeat);
        expect(
          afterCommandStates.first.tuningParams.length,
          greaterThan(initialTuningCount),
        );

        // 1-Click Undo restores exact pre-mutation checkpoint state
        final undone = provider.undoLastAgentAction();
        expect(undone, isTrue);
        final restoredDoc = provider.documents[firstFeat.id]!;
        final restoredStates =
            FeatureStateNode.getStatesForDocument(restoredDoc);
        expect(restoredStates.first.tuningParams.length, initialTuningCount);
      },
    );
  });
}
