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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    key: const ValueKey('ai_settings_btn'),
                    onTap: () => _showAiSettingsDialog(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: workbench.hasLiveAiKey
                            ? AppTheme.accentGreen.withValues(alpha: 0.14)
                            : AppTheme.tierRelease.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: workbench.hasLiveAiKey
                              ? AppTheme.accentGreen.withValues(alpha: 0.45)
                              : AppTheme.tierRelease.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            workbench.hasLiveAiKey
                                ? Icons.bolt_rounded
                                : Icons.key_outlined,
                            size: 13,
                            color: workbench.hasLiveAiKey
                                ? AppTheme.accentGreen
                                : AppTheme.tierRelease,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            workbench.modelName,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
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
            ],
          ),
        ),
      ),
      body: _buildActiveStageBody(),
    );
  }

  void _showAiSettingsDialog(BuildContext context) {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final borderColor = AppTheme.borderFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final keyController = TextEditingController(text: workbench.apiKey);
    String selectedModel = workbench.modelName;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: bgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: borderColor),
              ),
              title: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 18, color: AppTheme.accentBlue),
                  const SizedBox(width: 8),
                  Text(
                    'Antigravity AI Agent Settings',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACTIVE GEMINI MODEL',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final m in WorkbenchProvider.availableModels)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () => setModalState(() => selectedModel = m),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedModel == m
                                  ? AppTheme.accentBlue.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: selectedModel == m ? AppTheme.accentBlue : borderColor,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selectedModel == m
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 15,
                                  color: selectedModel == m ? AppTheme.accentBlue : textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    m == 'gemini-2.5-flash'
                                        ? 'gemini-2.5-flash (Recommended Default — Fast & Smart)'
                                        : m == 'gemini-2.5-pro'
                                            ? 'gemini-2.5-pro (Deep Reasoning — Release Architecture)'
                                            : 'gemini-2.0-flash (Ultra-Low Latency Fallback)',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight:
                                          selectedModel == m ? FontWeight.w700 : FontWeight.w500,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'GEMINI API KEY',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.tierRelease,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: keyController,
                      obscureText: true,
                      style: GoogleFonts.jetBrainsMono(fontSize: 12, color: textPrimary),
                      decoration: InputDecoration(
                        hintText: 'AIzaSy... (pre-configured if built with key)',
                        hintStyle: GoogleFonts.inter(fontSize: 12, color: textSecondary),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: borderColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    workbench.updateAiConfig(
                      apiKey: keyController.text,
                      modelName: selectedModel,
                    );
                    Navigator.of(ctx).pop();
                  },
                  child: Text(
                    'Save AI Config',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
          },
        );
      },
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
