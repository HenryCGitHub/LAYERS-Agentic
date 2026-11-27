import 'package:flutter/material.dart';

import '../models/epic_spec.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import 'project_pitch_screen.dart';
import 'release_workbench_screen.dart';
import 'workbench/plain_plan_release_page.dart';
import 'workbench/release_spec_sheet.dart';
import 'workbench/workbench_outliner_rail.dart';

/// Persistent 2-pane document workspace (`240px` left outline + `700px` centered document).
class PlainDocumentShell extends StatelessWidget {
  final WorkbenchProvider workbench;

  const PlainDocumentShell({super.key, required this.workbench});

  @override
  Widget build(BuildContext context) {
    final isDark = workbench.isDark;
    final epicDocs = workbench.activeReleaseEpicDocs;
    final epics = <EpicSpec>[
      for (int i = 0; i < epicDocs.length; i++)
        EpicSpec.fromDocument(epicDocs[i], indexHint: i),
    ];
    final activeEpic = workbench.selectedEpicSpec;
    final activeFeature = workbench.selectedFeatureSpec;

    return Material(
      color: AppTheme.bgBaseFor(isDark),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktopWide = constraints.maxWidth >= 960;
          final pageContent = _buildActivePage(activeEpic, activeFeature);

          if (!isDesktopWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WorkbenchCompactSwitcherBar(
                  wb: workbench,
                  epics: epics,
                  activeEpic: activeEpic,
                  activeFeature: activeFeature,
                ),
                Expanded(child: pageContent),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkbenchOutlinerRail(
                wb: workbench,
                epics: epics,
                activeEpic: activeEpic,
                activeFeature: activeFeature,
              ),
              Expanded(child: pageContent),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActivePage(EpicSpec? activeEpic, FeatureSpec? activeFeature) {
    switch (workbench.activeDocPage) {
      case WorkbenchDocPage.newGameIdea:
      case WorkbenchDocPage.projectBrief:
        return ProjectPitchScreen(
          workbench: workbench,
          embeddedInShell: true,
        );
      case WorkbenchDocPage.releaseSpec:
        return ReleaseSpecSheet(workbench: workbench);
      case WorkbenchDocPage.planNextRelease:
        return PlainPlanReleasePage(workbench: workbench);
      case WorkbenchDocPage.epicDomain:
      case WorkbenchDocPage.featureSlice:
        return ReleaseWorkbenchScreen(
          workbench: workbench,
          embeddedInShell: true,
        );
    }
  }
}
