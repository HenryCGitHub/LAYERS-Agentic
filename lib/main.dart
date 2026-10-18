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

    final bgRecessed = AppTheme.bgSurfaceRecessedFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);

    return Scaffold(
      backgroundColor: AppTheme.bgCanvasFor(isDark),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: bgRecessed,
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
                      color: bgSurface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      'AGENTIC',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: textSecondary,
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
                    color: AppTheme.accentAmberFor(isDark),
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                    onTap: () => workbench.setStage(WorkbenchStage.projectPitch),
                  ),
                  const SizedBox(width: 6),
                  _buildStagePill(
                    label: '2. Release Plan Gate',
                    stage: WorkbenchStage.releasePlanGate,
                    activeStage: workbench.currentStage,
                    color: AppTheme.accentCyanFor(isDark),
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                    onTap: workbench.releaseBlueprint != null
                        ? () => workbench.setStage(WorkbenchStage.releasePlanGate)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  _buildStagePill(
                    label: '3. Active Workbench',
                    stage: WorkbenchStage.releaseWorkbench,
                    activeStage: workbench.currentStage,
                    color: AppTheme.accentGreenFor(isDark),
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
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: bgSurface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: workbench.hasLiveAiKey
                                  ? AppTheme.accentGreenFor(isDark).withValues(alpha: 0.65)
                                  : AppTheme.accentAmberFor(isDark).withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            workbench.modelBadgeLabel,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'Toggle Theme',
                    child: InkWell(
                      onTap: workbench.toggleTheme,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bgSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderColor),
                        ),
                        child: Icon(
                          isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                          size: 15,
                          color: textSecondary,
                        ),
                      ),
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
    String selectedConversationModel = workbench.conversationModel;
    String selectedPlanningModel = workbench.planningModel;
    String selectedThinking = workbench.thinkingLevel;

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
                    'Antigravity Dual-Model AI Settings',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONVERSATION & INTERVIEW MODEL (FAST)',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentBlue,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final m in WorkbenchProvider.availableConversationModels)
                        _buildModelOptionTile(
                          modelId: m,
                          subtitle: m == 'gemini-flash-latest'
                              ? 'Default — Latest Gemini Flash for instant Concept Interviews'
                              : m == 'gemini-3.8-flash'
                                  ? 'Gemini 3.8 Flash'
                                  : 'Ultra-lightweight Flash-Lite',
                          isSelected: selectedConversationModel == m,
                          borderColor: borderColor,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onTap: () => setModalState(() => selectedConversationModel = m),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'PLANNING & ARCHITECTURE MODEL (DEEP)',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.tierProject,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final m in WorkbenchProvider.availablePlanningModels)
                        _buildModelOptionTile(
                          modelId: m,
                          subtitle: m == 'gemini-4-argon'
                              ? 'Default — Gemini 4 Argon for Concept Synthesis & Release Blueprints'
                              : m == 'gemini-flash-latest'
                                  ? 'Gemini Flash Latest (Fastest single-model mode)'
                                  : 'Gemini 3.8 Flash',
                          isSelected: selectedPlanningModel == m,
                          borderColor: borderColor,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onTap: () => setModalState(() => selectedPlanningModel = m),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'THINKING LEVEL (REASONING DEPTH)',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentGreen,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          for (final lvl in WorkbenchProvider.availableThinkingLevels)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  onTap: () => setModalState(() => selectedThinking = lvl),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selectedThinking == lvl
                                          ? AppTheme.accentGreen.withValues(alpha: 0.16)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: selectedThinking == lvl
                                            ? AppTheme.accentGreen
                                            : borderColor,
                                      ),
                                    ),
                                    child: Text(
                                      lvl == 'LOW' ? 'LOW (Default)' : lvl,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: selectedThinking == lvl
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
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
                      conversationModel: selectedConversationModel,
                      planningModel: selectedPlanningModel,
                      thinkingLevel: selectedThinking,
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

  Widget _buildModelOptionTile({
    required String modelId,
    required String subtitle,
    required bool isSelected,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accentBlue.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? AppTheme.accentBlue : borderColor,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 15,
                color: isSelected ? AppTheme.accentBlue : textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modelId,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? color : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
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
