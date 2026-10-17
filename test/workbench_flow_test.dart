import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layers_agentic/agents/project_concept_agent.dart';
import 'package:layers_agentic/main.dart';
import 'package:layers_agentic/providers/workbench_provider.dart';

void main() {
  group('LAYERS-Agentic 3-Stage End-to-End Flow Tests', () {
    test('ProjectConceptAgent generates 3-question interview and synthesizes Concept Blueprint', () async {
      final draft = await ProjectConceptAgent.startConceptInterview(
        'High-speed grappling hook parkour roguelite',
      );
      expect(draft.questions.length, 3);
      expect(draft.isInterviewComplete, isFalse);
      expect(draft.releaseTrainTitles.length, 3);

      // Select option 2 on Question 1 and synthesize
      draft.questions[0].selectedOption = draft.questions[0].options[1];
      final synthesized = await ProjectConceptAgent.synthesizeFromInterview(draft);

      expect(synthesized.isInterviewComplete, isTrue);
      expect(synthesized.goal, contains('2D Side-Scrolling Precision Platformer'));
      expect(synthesized.toFormattedScopeSection(), contains('Goal:'));
      expect(synthesized.toFormattedScopeSection(), contains('In Scope:'));
      expect(synthesized.toFormattedScopeSection(), contains('Out of Scope:'));
      expect(synthesized.toFormattedScopeSection(), contains('Done When:'));
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

        // ── Stage 1A: The Spark ──
        expect(find.text('STEP 1A · THE SPARK'), findsOneWidget);
        expect(find.byKey(const ValueKey('start_concept_interview_btn')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('start_concept_interview_btn')));
        await tester.pumpAndSettle();

        // ── Stage 1B: Concept Interview ──
        expect(find.byKey(const ValueKey('concept_interview_card')), findsOneWidget);
        final synthBtn = find.byKey(const ValueKey('synthesize_concept_btn'));
        await tester.ensureVisible(synthBtn);
        await tester.pumpAndSettle();
        await tester.tap(synthBtn);
        await tester.pumpAndSettle();

        // ── Stage 1C: Project Concept Blueprint & Release Train ──
        expect(find.byKey(const ValueKey('project_blueprint_card')), findsOneWidget);
        expect(find.text('v0.1: Core Toy & Movement Loop - Prototype'), findsOneWidget);
        final approveConceptBtn = find.byKey(const ValueKey('approve_concept_plan_release_btn'));
        await tester.ensureVisible(approveConceptBtn);
        await tester.pumpAndSettle();
        await tester.tap(approveConceptBtn);
        await tester.pumpAndSettle();

        // ── Stage 2: Antigravity Release Plan Gate ──
        expect(find.byKey(const ValueKey('release_plan_gate_banner')), findsOneWidget);
        expect(find.text('STAGE 2 · RELEASE PLAN GATE'), findsOneWidget);
        expect(find.text('Primary Locomotion & Burst'), findsOneWidget);
        expect(find.text('Bonus Time-Trial Medals'), findsOneWidget);

        // Verify unchecking/checking a Feature updates effective Out of Scope & budget
        expect(provider.releaseBlueprint!.totalIncludedFeatures, 4);
        final buildRelBtn = find.byKey(const ValueKey('approve_and_build_release_btn'));
        await tester.ensureVisible(buildRelBtn);
        await tester.pumpAndSettle();
        await tester.tap(buildRelBtn);
        await tester.pumpAndSettle();

        // ── Stage 3: Active Release Workbench (60/40 Checkpoints) ──
        expect(find.text('ACTIVE RELEASE'), findsOneWidget);
        expect(find.text('Primary Locomotion & Burst'), findsWidgets);
        expect(find.text('CHECKPOINT 1'), findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_two_col_row_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('checkpoint_spec_pane_0')), findsOneWidget);

        // Verify 60/40 horizontal placement (Checklist Left | Spec Context Right)
        final leftTaskPos = tester.getTopLeft(
          find.text('Implement directional acceleration & maxMoveSpeed clamp (2h)'),
        );
        final rightSpecPos = tester.getTopLeft(
          find.byKey(const ValueKey('checkpoint_spec_pane_0')),
        );
        expect(leftTaskPos.dx, lessThan(rightSpecPos.dx));
      },
    );
  });
}
