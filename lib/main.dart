import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/workbench_provider.dart';
import 'screens/project_pitch_screen.dart';
import 'screens/release_plan_gate_screen.dart';
import 'screens/release_workbench_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LayersAgenticApp());
}

class LayersAgenticApp extends StatelessWidget {
  final WorkbenchProvider? provider;

  const LayersAgenticApp({super.key, this.provider});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<WorkbenchProvider>(
      create: (_) => provider ?? WorkbenchProvider(),
      child: Consumer<WorkbenchProvider>(
        builder: (context, workbench, _) {
          final isDark = workbench.isDark;
          return MaterialApp(
            title: 'LAYERS-Agentic',
            debugShowCheckedModeBanner: false,
            theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: WorkbenchShell(workbench: workbench),
          );
        },
      ),
    );
  }
}

class WorkbenchShell extends StatelessWidget {
  final WorkbenchProvider workbench;

  const WorkbenchShell({super.key, required this.workbench});

  @override
  Widget build(BuildContext context) {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final borderColor = AppTheme.borderFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);

    return Scaffold(
      backgroundColor: AppTheme.bgCanvasFor(isDark),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bgSurface,
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'LAYERS',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'AGENTIC',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentBlue,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStagePill(
                    label: '1. Project Concept',
                    stage: WorkbenchStage.projectPitch,
                    activeStage: workbench.currentStage,
                    color: AppTheme.tierProject,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                    onTap: () => workbench.setStage(WorkbenchStage.projectPitch),
                  ),
                  const SizedBox(width: 8),
                  _buildStagePill(
                    label: '2. Release Plan Gate',
                    stage: WorkbenchStage.releasePlanGate,
                    activeStage: workbench.currentStage,
                    color: AppTheme.tierRelease,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                    onTap: workbench.releaseBlueprint != null
                        ? () => workbench.setStage(WorkbenchStage.releasePlanGate)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _buildStagePill(
                    label: '3. Active Workbench',
                    stage: WorkbenchStage.releaseWorkbench,
                    activeStage: workbench.currentStage,
                    color: AppTheme.tierFeature,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                    onTap: workbench.activeReleaseBeats.isNotEmpty
                        ? () => workbench.setStage(WorkbenchStage.releaseWorkbench)
                        : null,
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Toggle Theme',
                onPressed: workbench.toggleTheme,
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  size: 17,
                  color: textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildActiveStageBody(),
    );
  }

  Widget _buildStagePill({
    required String label,
    required WorkbenchStage stage,
    required WorkbenchStage activeStage,
    required Color color,
    required Color textPrimary,
    required Color textMuted,
    VoidCallback? onTap,
  }) {
    final isActive = stage == activeStage;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? color : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? textPrimary : textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveStageBody() {
    switch (workbench.currentStage) {
      case WorkbenchStage.projectPitch:
        return ProjectPitchScreen(workbench: workbench);
      case WorkbenchStage.releasePlanGate:
        return ReleasePlanGateScreen(workbench: workbench);
      case WorkbenchStage.releaseWorkbench:
        return ReleaseWorkbenchScreen(workbench: workbench);
    }
  }
}
