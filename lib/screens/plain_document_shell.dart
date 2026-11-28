import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import 'project_pitch_screen.dart';
import 'release_workbench_screen.dart';
import 'workbench/plain_plan_release_page.dart';
import 'workbench/release_spec_sheet.dart';

/// 2-screen workstation shell (`Project Brief` ↔ full-width Monday-style
/// `Release Table`) that opens Epic and Feature Option A 2-column specs inside a
/// wide centered reactive overlay with `Esc` and backdrop dismissal.
class PlainDocumentShell extends StatelessWidget {
  final WorkbenchProvider workbench;

  const PlainDocumentShell({super.key, required this.workbench});

  void _closeOverlay() {
    FocusManager.instance.primaryFocus?.unfocus();
    workbench.selectReleaseSpec();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = workbench.isDark;
    final activePage = workbench.activeDocPage;
    final showOverlay =
        activePage == WorkbenchDocPage.epicDomain ||
        activePage == WorkbenchDocPage.featureSlice;

    final Widget basePage;
    switch (activePage) {
      case WorkbenchDocPage.newGameIdea:
      case WorkbenchDocPage.projectBrief:
        basePage = ProjectPitchScreen(
          workbench: workbench,
          embeddedInShell: true,
        );
      case WorkbenchDocPage.planNextRelease:
        basePage = PlainPlanReleasePage(workbench: workbench);
      case WorkbenchDocPage.releaseSpec:
      case WorkbenchDocPage.epicDomain:
      case WorkbenchDocPage.featureSlice:
        basePage = ReleaseSpecSheet(workbench: workbench);
    }

    return Material(
      color: AppTheme.bgBaseFor(isDark),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          if (showOverlay)
            const SingleActivator(LogicalKeyboardKey.escape): _closeOverlay,
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 720;
            final overlayWidth = isNarrow
                ? (constraints.maxWidth - 16).clamp(280.0, 720.0)
                : (constraints.maxWidth - 48).clamp(320.0, 1180.0);
            final overlayHeight = isNarrow
                ? (constraints.maxHeight - 16).clamp(300.0, 1200.0)
                : (constraints.maxHeight * 0.92).clamp(320.0, 960.0);

            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(ignoring: showOverlay, child: basePage),
                ),
                if (showOverlay) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('workbench_overlay_backdrop'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _closeOverlay,
                      child: ColoredBox(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.62 : 0.35,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: FocusScope(
                      autofocus: true,
                      child: Container(
                        key: const ValueKey('workbench_overlay_dialog'),
                        width: overlayWidth,
                        height: overlayHeight,
                        decoration: BoxDecoration(
                          color: AppTheme.bgBaseFor(isDark),
                          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                          border: Border.all(
                            color: AppTheme.borderBrightFor(isDark),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.45 : 0.16,
                              ),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusLg - 1,
                          ),
                          child: ReleaseWorkbenchScreen(
                            workbench: workbench,
                            embeddedInShell: true,
                            inOverlay: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
