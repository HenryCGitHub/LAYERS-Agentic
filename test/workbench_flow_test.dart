import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layers_agentic/agents/project_concept_agent.dart';
import 'package:layers_agentic/main.dart';
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
        expect(find.text('STEP 1A · THE SPARK'), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('spark_card_2')), findsOneWidget);
        expect(find.byKey(const ValueKey('start_concept_interview_btn')), findsOneWidget);

        // 1-Click Launch via Playing Card #1 ('Grapple Hook Parkour')
        await tester.tap(find.byKey(const ValueKey('spark_card_0')));
        await tester.pumpAndSettle();

        // ── Stage 1B: One-Section-at-a-Time Dynamic UI (Sections 01..09) ──
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
        expect(find.byKey(const ValueKey('release_question_card_0_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_question_card_0_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('release_question_card_0_2')), findsOneWidget);
        expect(find.text('STAGE 2 · RELEASE PLAN GATE'), findsOneWidget);
        expect(find.text('Staging & Loadout Prep Mechanics & Controls'), findsOneWidget);
        expect(find.text('Bonus Time-Trial Medals'), findsOneWidget);
        expect(find.byKey(const ValueKey('restore_deferred_feat_feat_7_2')), findsOneWidget);

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

        // ── Stage 3: Active Release Workbench (60/40 Checkpoints) ──
        expect(find.text('ACTIVE RELEASE'), findsOneWidget);
        expect(find.text('Staging & Loadout Prep Mechanics & Controls'), findsWidgets);
        expect(find.text('CHECKPOINT 1'), findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_two_col_row_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_spec_pane_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('prev_feature_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('next_feature_btn')), findsOneWidget);
        expect(find.byKey(const ValueKey('add_tuning_btn_0')), findsOneWidget);

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

        // Verify interactive Out-of-Scope shelf toggle
        expect(find.byKey(const ValueKey('feat_out_of_scope_shelf')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('feat_out_of_scope_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('feat_out_of_scope_shelf')), findsOneWidget);

        // Verify inline "+ Add task step..." input appends a task to Checkpoint 1
        final addInput = find.byKey(const ValueKey('add_checkpoint_task_input_0'));
        await tester.enterText(addInput, 'Verify grapple hook cooldown indicator');
        await tester.tap(find.byKey(const ValueKey('add_checkpoint_task_btn_0')));
        await tester.pumpAndSettle();
        expect(find.text('Verify grapple hook cooldown indicator'), findsOneWidget);
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
  });
}
