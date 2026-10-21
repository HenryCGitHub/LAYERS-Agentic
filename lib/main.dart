import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/workbench_provider.dart';
import 'screens/project_pitch_screen.dart';
import 'screens/release_plan_gate_screen.dart';
import 'screens/release_workbench_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }
  runApp(const LayersAgenticApp());
}

class LayersAgenticApp extends StatelessWidget {
  final WorkbenchProvider? provider;

  const LayersAgenticApp({super.key, this.provider});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<WorkbenchProvider>(
      create: (_) => provider ?? WorkbenchProvider(enableAutoLoad: true),
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

  Future<void> _exportFullProjectSpec(BuildContext context) async {
    final draft = workbench.conceptDraft;
    final bp = workbench.releaseBlueprint;
    final rel = workbench.activeRelease;
    final sb = StringBuffer();
    final title = draft != null && draft.sparkIdea.trim().isNotEmpty
        ? draft.sparkIdea.trim()
        : 'LAYERS-Agentic Game Project';
    sb.writeln('# $title — Project & Release Specification');
    if (draft != null) {
      sb.writeln('\n## Stage 1: Project Concept Blueprint');
      sb.writeln(draft.toFormattedScopeSection());
    }
    if (bp != null) {
      sb.writeln(
        '\n## Stage 2: ${bp.releaseTitle} (${bp.totalIncludedFeatures} Features · ${bp.totalIncludedHours}h)',
      );
      for (int i = 0; i < bp.beats.length; i++) {
        final b = bp.beats[i];
        sb.writeln('\n### Beat ${i + 1}: ${b.title}');
        for (final f in b.features) {
          final status = f.included ? 'INCLUDED (${f.estimatedHours}h)' : 'DEFERRED';
          sb.writeln('- **${f.title}** [$status]: ${f.goal}');
        }
      }
    }
    if (rel != null) {
      final relProgress = workbench.getDocumentProgress(rel.id);
      sb.writeln('\n## Stage 3: Active Release Workbench (${rel.title} · $relProgress% Verified)');
      for (final beat in workbench.activeReleaseBeats) {
        final feats = workbench.featuresForBeat(beat.id);
        for (final feat in feats) {
          final p = workbench.getDocumentProgress(feat.id);
          sb.writeln('- **${feat.title}** ($p% verified · ${feat.estimatedDuration})');
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (!context.mounted) return;
    final isDark = workbench.isDark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.bgSurfaceFor(isDark),
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Copied full Project & Release Spec to clipboard ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.accentGreenFor(isDark),
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final borderColor = AppTheme.borderFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);

    final bgRecessed = AppTheme.bgSurfaceRecessedFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final accentAmber = AppTheme.accentAmberFor(isDark);
    final accentEmerald = AppTheme.accentGreenFor(isDark);

    final draft = workbench.conceptDraft;
    final bp = workbench.releaseBlueprint;
    final rel = workbench.activeRelease;
    final allFeats = <String>[
      for (final b in workbench.activeReleaseBeats)
        for (final f in workbench.featuresForBeat(b.id)) f.id,
    ];
    final doneFeatCount = allFeats
        .where((id) => workbench.getDocumentProgress(id) >= 100)
        .length;

    final String? stage1Badge = draft != null ? '✓' : null;
    final String? stage2Badge = bp?.releaseVersionTag;
    final String? stage3Badge = allFeats.isNotEmpty
        ? '$doneFeatCount/${allFeats.length}'
        : (rel != null ? '${workbench.getDocumentProgress(rel.id)}%' : null);

    final String? rawSpark = draft?.sparkIdea.trim() ?? workbench.activeProject?.title.trim();
    final String? activeProjectLabel = (rawSpark != null && rawSpark.isNotEmpty)
        ? (rawSpark.length > 9 ? '${rawSpark.substring(0, 9)}…' : rawSpark)
        : null;
    final savedProjects = workbench.savedProjects;

    return Scaffold(
      backgroundColor: AppTheme.bgCanvasFor(isDark),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bgRecessed,
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'LAYERS',
                    style: AppTheme.displayFont(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '/',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: textMuted,
                    ),
                  ),
                  const SizedBox(width: 5),
                  PopupMenuButton<String>(
                    key: const ValueKey('project_switcher_dropdown_btn'),
                    tooltip: 'Switch Project or Start New Spark',
                    color: bgSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: borderColor),
                    ),
                    onSelected: (val) {
                      if (val == '__new_project__') {
                        workbench.createNewProject();
                      } else {
                        workbench.switchProject(val);
                      }
                    },
                    itemBuilder: (ctx) => [
                      for (final p in savedProjects)
                        PopupMenuItem<String>(
                          value: p.id,
                          child: Row(
                            children: [
                              Icon(
                                p.id == workbench.activeProjectId
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.folder_outlined,
                                size: 13,
                                color: p.id == workbench.activeProjectId
                                    ? accentAmber
                                    : textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: p.id == workbench.activeProjectId
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: p.id == workbench.activeProjectId
                                        ? textPrimary
                                        : textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (savedProjects.isNotEmpty) const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: '__new_project__',
                        child: Row(
                          children: [
                            Icon(Icons.add_circle_outline_rounded, size: 13, color: accentEmerald),
                            const SizedBox(width: 8),
                            Text(
                              '+ New Project',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: accentEmerald,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                      decoration: BoxDecoration(
                        color: bgSurface,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (activeProjectLabel != null)
                            Text(
                              activeProjectLabel,
                              key: const ValueKey('top_bar_project_title'),
                              style: AppTheme.displayFont(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: textPrimary,
                              ),
                            )
                          else
                            Text(
                              'Projects',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
                              ),
                            ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 12,
                            color: textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                key: const ValueKey('connected_pipeline_track'),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: bgSurface,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStagePill(
                      label: '1. Concept',
                      badge: stage1Badge,
                      stage: WorkbenchStage.projectPitch,
                      activeStage: workbench.currentStage,
                      isCompleted: bp != null || allFeats.isNotEmpty,
                      activeDotColor: accentAmber,
                      completedColor: accentEmerald,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      textMuted: textMuted,
                      bgActive: AppTheme.bgSurfaceHoverFor(isDark),
                      bgRecessed: AppTheme.bgSurfaceRecessedFor(isDark),
                      borderSubtle: AppTheme.borderSubtleFor(isDark),
                      borderBright: AppTheme.borderBrightFor(isDark),
                      onTap: () => workbench.setStage(WorkbenchStage.projectPitch),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        '▸',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: textMuted,
                        ),
                      ),
                    ),
                    _buildStagePill(
                      label: '2. Release Plan',
                      badge: stage2Badge,
                      stage: WorkbenchStage.releasePlanGate,
                      activeStage: workbench.currentStage,
                      isCompleted: allFeats.isNotEmpty,
                      activeDotColor: accentAmber,
                      completedColor: accentEmerald,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      textMuted: textMuted,
                      bgActive: AppTheme.bgSurfaceHoverFor(isDark),
                      bgRecessed: AppTheme.bgSurfaceRecessedFor(isDark),
                      borderSubtle: AppTheme.borderSubtleFor(isDark),
                      borderBright: AppTheme.borderBrightFor(isDark),
                      onTap: workbench.releaseBlueprint != null
                          ? () => workbench.setStage(WorkbenchStage.releasePlanGate)
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        '▸',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: textMuted,
                        ),
                      ),
                    ),
                    _buildStagePill(
                      label: '3. Workbench',
                      badge: stage3Badge,
                      stage: WorkbenchStage.releaseWorkbench,
                      activeStage: workbench.currentStage,
                      isCompleted: workbench.isActiveReleaseComplete,
                      activeDotColor: accentAmber,
                      completedColor: accentEmerald,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      textMuted: textMuted,
                      bgActive: AppTheme.bgSurfaceHoverFor(isDark),
                      bgRecessed: AppTheme.bgSurfaceRecessedFor(isDark),
                      borderSubtle: AppTheme.borderSubtleFor(isDark),
                      borderBright: AppTheme.borderBrightFor(isDark),
                      onTap: workbench.activeReleaseBeats.isNotEmpty
                          ? () => workbench.setStage(WorkbenchStage.releaseWorkbench)
                          : null,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Agent Command Palette & Tool History (1-Click Undo)',
                    child: InkWell(
                      key: const ValueKey('top_bar_agent_log_btn'),
                      onTap: () => _showAgentCommandHistoryDialog(context),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                        decoration: BoxDecoration(
                          color: bgSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: workbench.agentTraceHistory.isNotEmpty
                                ? AppTheme.borderBrightFor(isDark)
                                : borderColor,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.terminal_rounded,
                              size: 11,
                              color: workbench.agentTraceHistory.isNotEmpty
                                  ? accentEmerald
                                  : textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Agent (${workbench.agentTraceHistory.length})',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: workbench.agentTraceHistory.isNotEmpty
                                    ? textPrimary
                                    : textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Compact unified Studio Utility Pill Cluster (Export · Cloud Vault · AI Models · Theme)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                    decoration: BoxDecoration(
                      color: bgSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (draft != null) ...[
                          Tooltip(
                            message: 'Copy Full Project & Release Spec as Markdown',
                            child: InkWell(
                              key: const ValueKey('global_export_spec_btn'),
                              onTap: () => _exportFullProjectSpec(context),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.copy_rounded, size: 11, color: textSecondary),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Export',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(width: 1, height: 12, color: borderColor),
                        ],
                        Tooltip(
                          message: workbench.isCloudSynced
                              ? 'Synced to Firebase Cloud (${workbench.userEmail ?? "Signed In"})'
                              : 'Project Vault & Google Cloud Sync',
                          child: InkWell(
                            key: const ValueKey('cloud_sync_auth_btn'),
                            onTap: () => _showCloudSyncDialog(context),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              child: Icon(
                                workbench.isCloudSynced
                                    ? Icons.cloud_done_rounded
                                    : Icons.cloud_upload_outlined,
                                size: 13,
                                color: workbench.isCloudSynced ? accentEmerald : textSecondary,
                              ),
                            ),
                          ),
                        ),
                        Container(width: 1, height: 12, color: borderColor),
                        Tooltip(
                          message: 'AI Model Routing & API Key Settings',
                          child: InkWell(
                            key: const ValueKey('ai_settings_btn'),
                            onTap: () => _showAiSettingsDialog(context),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 5.5,
                                    height: 5.5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: workbench.hasLiveAiKey
                                          ? accentEmerald
                                          : accentAmber,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.tune_rounded,
                                    size: 12,
                                    color: textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(width: 1, height: 12, color: borderColor),
                        Tooltip(
                          message: 'Toggle Theme',
                          child: InkWell(
                            onTap: workbench.toggleTheme,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              child: Icon(
                                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                                size: 13,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
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

  void _showCloudSyncDialog(BuildContext context) {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final bgRecessed = AppTheme.bgSurfaceRecessedFor(isDark);
    final borderSubtle = AppTheme.borderSubtleFor(isDark);
    final borderBright = AppTheme.borderBrightFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final focalAccent = AppTheme.focalAccentFor(isDark);
    final focalAccentFg = AppTheme.focalAccentFgFor(isDark);
    final accentEmerald = AppTheme.accentGreenFor(isDark);
    final accentAmber = AppTheme.accentAmberFor(isDark);

    final collabEmailCtrl = TextEditingController();
    String selectedCollabRole = 'editor';

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final isSynced = workbench.isCloudSynced;
            final projs = workbench.savedProjects;
            final activeProj = workbench.activeProject;
            final collabs = workbench.collaboratorsForProject(activeProj?.id);
            return AlertDialog(
              backgroundColor: bgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: borderBright),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isSynced ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded,
                        size: 18,
                        color: isSynced ? accentEmerald : textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Firebase Cloud Sync & Local Vault',
                        style: AppTheme.displayFont(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    key: const ValueKey('cloud_sync_now_btn'),
                    onTap: () async {
                      await workbench.syncNowWithCloud();
                      setModalState(() {});
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: bgRecessed,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync_rounded, size: 12, color: textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Sync Now',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
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
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: bgRecessed,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSynced
                                ? accentEmerald.withValues(alpha: 0.45)
                                : borderSubtle,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSynced ? accentEmerald : accentAmber,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isSynced
                                        ? 'Cloud Firestore Connected (${workbench.userEmail ?? "Google Account"})'
                                        : 'Local Vault Active · Cloud Sync Offline',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    isSynced
                                        ? 'All Stage 1 Concepts, Stage 2 Release Plans, and Stage 3 Checkpoints sync live to Firebase project layers-b8a16.'
                                        : 'Every change is automatically saved to browser local storage. Sign in with Google to sync across devices via Cloud Firestore.',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      height: 1.4,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (workbench.authLastError != null &&
                          workbench.authLastError!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          workbench.authLastError!,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            color: accentAmber,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'SAVED PROJECTS IN VAULT (${projs.length})',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: textMuted,
                            ),
                          ),
                          InkWell(
                            key: const ValueKey('vault_new_project_btn'),
                            onTap: () {
                              workbench.createNewProject();
                              Navigator.of(ctx).pop();
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Text(
                                '+ New Project',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: accentEmerald,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (projs.isEmpty)
                        Text(
                          'No saved projects yet — pick a Spark card or type an idea to start.',
                          style: GoogleFonts.inter(fontSize: 11.5, color: textSecondary),
                        )
                      else
                        for (final p in projs.take(6))
                          Container(
                            margin: const EdgeInsets.only(bottom: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: p.id == workbench.activeProjectId
                                  ? bgRecessed
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: p.id == workbench.activeProjectId
                                    ? borderBright
                                    : borderSubtle,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  p.id == workbench.activeProjectId
                                      ? Icons.check_circle_rounded
                                      : Icons.folder_outlined,
                                  size: 13,
                                  color: p.id == workbench.activeProjectId
                                      ? accentEmerald
                                      : textMuted,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: InkWell(
                                    key: ValueKey('vault_switch_${p.id}'),
                                    onTap: () {
                                      workbench.switchProject(p.id);
                                      setModalState(() {});
                                    },
                                    child: Text(
                                      p.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: p.id == workbench.activeProjectId
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: 'Rename Project',
                                  child: InkWell(
                                    key: ValueKey('vault_rename_${p.id}'),
                                    onTap: () async {
                                      final ctrl = TextEditingController(text: p.title);
                                      final newTitle = await showDialog<String>(
                                        context: ctx,
                                        builder: (rCtx) => AlertDialog(
                                          backgroundColor: bgSurface,
                                          title: Text(
                                            'Rename Project',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: textPrimary,
                                            ),
                                          ),
                                          content: TextField(
                                            controller: ctrl,
                                            autofocus: true,
                                            style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                                            onSubmitted: (val) => Navigator.of(rCtx).pop(val),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(rCtx).pop(),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () => Navigator.of(rCtx).pop(ctrl.text),
                                              child: const Text('Save'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (newTitle != null && newTitle.trim().isNotEmpty) {
                                        workbench.renameProject(p.id, newTitle.trim());
                                        setModalState(() {});
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(Icons.edit_outlined, size: 13, color: textSecondary),
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Duplicate Project',
                                  child: InkWell(
                                    key: ValueKey('vault_duplicate_${p.id}'),
                                    onTap: () {
                                      workbench.duplicateProject(p.id);
                                      setModalState(() {});
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(Icons.copy_all_rounded, size: 13, color: textSecondary),
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Delete Project',
                                  child: InkWell(
                                    key: ValueKey('vault_delete_${p.id}'),
                                    onTap: () {
                                      workbench.deleteProject(p.id);
                                      setModalState(() {});
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 13,
                                        color: AppTheme.accentRedFor(isDark),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      if (activeProj != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          'SHARE ACTIVE PROJECT (${activeProj.title.toUpperCase()})',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: textMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey('invite_collaborator_email_input'),
                                controller: collabEmailCtrl,
                                style: GoogleFonts.inter(fontSize: 12, color: textPrimary),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: bgRecessed,
                                  hintText: 'Teammate email (e.g., dev@studio.io)...',
                                  hintStyle: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(5),
                                    borderSide: BorderSide(color: borderSubtle),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                setModalState(() {
                                  selectedCollabRole =
                                      selectedCollabRole == 'editor' ? 'viewer' : 'editor';
                                });
                              },
                              borderRadius: BorderRadius.circular(5),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                decoration: BoxDecoration(
                                  color: bgRecessed,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: borderSubtle),
                                ),
                                child: Text(
                                  selectedCollabRole.toUpperCase(),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              key: const ValueKey('invite_collaborator_btn'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: focalAccent,
                                foregroundColor: focalAccentFg,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                minimumSize: Size.zero,
                              ),
                              onPressed: () async {
                                final ok = await workbench.inviteProjectCollaborator(
                                  collaboratorEmail: collabEmailCtrl.text,
                                  role: selectedCollabRole,
                                );
                                if (ok) {
                                  collabEmailCtrl.clear();
                                  setModalState(() {});
                                }
                              },
                              child: Text(
                                'Invite',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (collabs.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final c in collabs)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: bgRecessed,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: borderSubtle),
                                  ),
                                  child: Text(
                                    '👤 ${c['email']} (${c['role']})',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9.5,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Close',
                    style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
                  ),
                ),
                if (isSynced)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await workbench.signOutFromCloud();
                      setModalState(() {});
                    },
                    icon: Icon(Icons.logout_rounded, size: 14, color: textSecondary),
                    label: Text(
                      'Sign Out',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    key: const ValueKey('google_sign_in_modal_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focalAccent,
                      foregroundColor: focalAccentFg,
                      elevation: 0,
                    ),
                    onPressed: () async {
                      await workbench.signInWithGoogle();
                      setModalState(() {});
                    },
                    icon: const Icon(Icons.cloud_upload_rounded, size: 15),
                    label: Text(
                      'Sign in with Google',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAiSettingsDialog(BuildContext context) {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final bgRecessed = AppTheme.bgSurfaceRecessedFor(isDark);
    final bgHover = AppTheme.bgSurfaceHoverFor(isDark);
    final borderSubtle = AppTheme.borderSubtleFor(isDark);
    final borderBright = AppTheme.borderBrightFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final focalAccent = AppTheme.focalAccentFor(isDark);
    final focalAccentFg = AppTheme.focalAccentFgFor(isDark);
    final accentAmber = AppTheme.accentAmberFor(isDark);
    final accentEmerald = AppTheme.accentGreenFor(isDark);

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
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: borderBright),
              ),
              title: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentAmber,
                    ),
                  ),
                  const SizedBox(width: 10),
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
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '01 · CONVERSATION & CONCEPT MODEL (STAGE 1)',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final m in WorkbenchProvider.availableConversationModels)
                        _buildModelOptionTile(
                          modelId: m,
                          subtitle: m == 'gemini-flash-latest'
                              ? 'Default — Latest Gemini Flash for fast Concept Blueprints'
                              : m == 'gemini-3.8-flash'
                                  ? 'Gemini 3.8 Flash'
                                  : 'Ultra-lightweight Flash-Lite',
                          isSelected: selectedConversationModel == m,
                          isRecommended: m == 'gemini-flash-latest',
                          bgSurface: bgRecessed,
                          bgHover: bgHover,
                          borderSubtle: borderSubtle,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          textMuted: textMuted,
                          focalAccent: focalAccent,
                          focalAccentFg: focalAccentFg,
                          accentEmerald: accentEmerald,
                          onTap: () => setModalState(() => selectedConversationModel = m),
                        ),
                      const SizedBox(height: 14),
                      Text(
                        '02 · RELEASE ARCHITECTURE MODEL (STAGE 2)',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final m in WorkbenchProvider.availablePlanningModels)
                        _buildModelOptionTile(
                          modelId: m,
                          subtitle: m == 'gemini-4-argon'
                              ? 'Default — Gemini 4 Argon for Release Blueprints & Evolution'
                              : m == 'gemini-flash-latest'
                                  ? 'Gemini Flash Latest (Fastest single-model mode)'
                                  : 'Gemini 3.8 Flash',
                          isSelected: selectedPlanningModel == m,
                          isRecommended: m == 'gemini-4-argon',
                          bgSurface: bgRecessed,
                          bgHover: bgHover,
                          borderSubtle: borderSubtle,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          textMuted: textMuted,
                          focalAccent: focalAccent,
                          focalAccentFg: focalAccentFg,
                          accentEmerald: accentEmerald,
                          onTap: () => setModalState(() => selectedPlanningModel = m),
                        ),
                      const SizedBox(height: 14),
                      Text(
                        '03 · THINKING LEVEL (REASONING DEPTH)',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final lvl in WorkbenchProvider.availableThinkingLevels)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: lvl == WorkbenchProvider.availableThinkingLevels.last ? 0 : 6,
                                ),
                                child: InkWell(
                                  onTap: () => setModalState(() => selectedThinking = lvl),
                                  borderRadius: BorderRadius.circular(5),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selectedThinking == lvl ? bgHover : bgRecessed,
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: selectedThinking == lvl
                                            ? textPrimary
                                            : borderSubtle,
                                        width: selectedThinking == lvl ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: Text(
                                      lvl == 'LOW' ? 'LOW (Default)' : lvl,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        fontWeight: selectedThinking == lvl
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: selectedThinking == lvl ? textPrimary : textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '04 · GEMINI API KEY',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyController,
                        obscureText: true,
                        style: GoogleFonts.jetBrainsMono(fontSize: 12, color: textPrimary),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: bgRecessed,
                          hintText: 'AIzaSy... (pre-configured if built with key)',
                          hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: borderSubtle),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: borderBright, width: 1.4),
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
                    backgroundColor: focalAccent,
                    foregroundColor: focalAccentFg,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
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
    required bool isRecommended,
    required Color bgSurface,
    required Color bgHover,
    required Color borderSubtle,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color focalAccent,
    required Color focalAccentFg,
    required Color accentEmerald,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? bgHover : bgSurface,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: isSelected ? textPrimary : borderSubtle,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 15,
                height: 15,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? focalAccent : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? focalAccent : textMuted,
                    width: 1.4,
                  ),
                ),
                child: isSelected
                    ? Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: focalAccentFg,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
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
                    const SizedBox(height: 1),
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
              if (isRecommended) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentEmerald.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: accentEmerald.withValues(alpha: 0.42)),
                  ),
                  child: Text(
                    'RECOMMENDED',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: accentEmerald,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStagePill({
    required String label,
    String? badge,
    required WorkbenchStage stage,
    required WorkbenchStage activeStage,
    required bool isCompleted,
    required Color activeDotColor,
    required Color completedColor,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color bgActive,
    required Color bgRecessed,
    required Color borderSubtle,
    required Color borderBright,
    VoidCallback? onTap,
  }) {
    final isActive = stage == activeStage;
    final isCheckBadge = badge == '✓';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
        decoration: BoxDecoration(
          color: isActive ? bgActive : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isActive ? borderBright : Colors.transparent,
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? activeDotColor
                    : (isCompleted
                        ? completedColor
                        : textMuted.withValues(alpha: 0.35)),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTheme.displayFont(
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: -0.1,
                color: isActive
                    ? textPrimary
                    : (isCompleted ? textSecondary : textMuted),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                decoration: BoxDecoration(
                  color: isCheckBadge
                      ? completedColor.withValues(alpha: 0.14)
                      : bgRecessed,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isCheckBadge
                        ? completedColor.withValues(alpha: 0.4)
                        : borderSubtle,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: isCheckBadge ? completedColor : textSecondary,
                  ),
                ),
              ),
            ],
          ],
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

  /// Option 4: Global Top-Bar Agent Command Palette & Chronological Tool History Drawer with 1-Click Undo.
  void _showAgentCommandHistoryDialog(BuildContext context) {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final bgRecessed = AppTheme.bgSurfaceRecessedFor(isDark);
    final borderSubtle = AppTheme.borderSubtleFor(isDark);
    final borderBright = AppTheme.borderBrightFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final accentEmerald = AppTheme.accentGreenFor(isDark);
    final accentAmber = AppTheme.accentAmberFor(isDark);
    final cmdController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final history = workbench.agentTraceHistory;
            final canUndo = workbench.canUndoLastAgentAction;

            Future<void> submitCommand() async {
              final text = cmdController.text.trim();
              if (text.isEmpty) return;
              cmdController.clear();
              await workbench.runGlobalAgentCommand(text);
              if (ctx.mounted) {
                setModalState(() {});
              }
            }

            return AlertDialog(
              key: const ValueKey('agent_command_history_dialog'),
              backgroundColor: bgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: borderBright),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.terminal_rounded, size: 17, color: accentEmerald),
                      const SizedBox(width: 8),
                      Text(
                        'AGENT COMMAND PALETTE & TOOL LOG (${history.length})',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('undo_last_agent_action_btn'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: canUndo ? accentAmber : textMuted,
                          side: BorderSide(
                            color: canUndo
                                ? accentAmber.withValues(alpha: 0.5)
                                : borderSubtle,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: canUndo
                            ? () {
                                workbench.undoLastAgentAction();
                                setModalState(() {});
                              }
                            : null,
                        icon: const Icon(Icons.undo_rounded, size: 13),
                        label: Text(
                          'Undo Last Agent Action',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Icon(Icons.close_rounded, size: 18, color: textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 680,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('global_agent_command_input'),
                            controller: cmdController,
                            style: GoogleFonts.inter(fontSize: 12.5, color: textPrimary),
                            decoration: InputDecoration(
                              hintText:
                                  'Run a global Agent command in active stage (e.g., "Add coyote time tuning", "Defer multiplayer")...',
                              hintStyle: GoogleFonts.inter(
                                fontSize: 12,
                                color: textMuted,
                              ),
                              filled: true,
                              fillColor: bgRecessed,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: borderSubtle),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: borderSubtle),
                              ),
                            ),
                            onSubmitted: (_) => submitCommand(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          key: const ValueKey('global_agent_command_send_btn'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentEmerald,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: submitCommand,
                          child: Text(
                            'Run Command →',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'CHRONOLOGICAL AGENT TOOL TRACE HISTORY',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: history.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: bgRecessed,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: borderSubtle),
                              ),
                              child: Text(
                                'No Agent tool actions recorded yet in this session.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: history.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final item = history[idx];
                                return Container(
                                  key: ValueKey('agent_history_item_$idx'),
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: bgRecessed,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: borderSubtle),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            item.agentRole.toUpperCase(),
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                              color: accentEmerald,
                                            ),
                                          ),
                                          Text(
                                            '#${history.length - idx}',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 9,
                                              color: textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.reasoning,
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          color: textPrimary,
                                        ),
                                      ),
                                      if (item.toolCalls.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            for (final tc in item.toolCalls)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: bgSurface,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: borderSubtle,
                                                  ),
                                                ),
                                                child: Text(
                                                  '⚙ ${tc.toolName} → ${tc.summary}',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 9,
                                                    color: textSecondary,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
