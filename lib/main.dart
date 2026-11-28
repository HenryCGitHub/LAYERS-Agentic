import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/workbench_provider.dart';
import 'screens/plain_document_shell.dart';
import 'screens/project_pitch_screen.dart';
import 'screens/shell/studio_top_bar.dart';
import 'screens/shell/team_invites_dialog.dart';
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
    final consumer = Consumer<WorkbenchProvider>(
      builder: (context, workbench, _) {
        final isDark = workbench.isDark;
        return MaterialApp(
          title: 'LAYERS-Agentic',
          debugShowCheckedModeBanner: false,
          theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
          home: WorkbenchShell(workbench: workbench),
        );
      },
    );
    if (provider != null) {
      return ChangeNotifierProvider<WorkbenchProvider>.value(
        value: provider!,
        child: consumer,
      );
    }
    return ChangeNotifierProvider<WorkbenchProvider>(
      create: (_) => WorkbenchProvider(enableAutoLoad: true),
      child: consumer,
    );
  }
}

class WorkbenchShell extends StatelessWidget {
  final WorkbenchProvider workbench;

  const WorkbenchShell({super.key, required this.workbench});

  @override
  Widget build(BuildContext context) {
    final isDark = workbench.isDark;
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final suppressDuplicateStage1OfflineBanner =
        (workbench.activeDocPage == WorkbenchDocPage.newGameIdea ||
                workbench.activeDocPage == WorkbenchDocPage.projectBrief) &&
            workbench.stage1InlineError != null &&
            workbench.offlineErrorMessage == workbench.stage1InlineError;

    return Scaffold(
      backgroundColor: AppTheme.bgCanvasFor(isDark),
      appBar: StudioTopBar(workbench: workbench),
      body: Stack(
        children: [
          Column(
            children: [
              if (workbench.isOffline && !suppressDuplicateStage1OfflineBanner)
                Container(
                  key: const ValueKey('global_offline_banner'),
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        AppTheme.accentRedFor(isDark).withValues(alpha: 0.14),
                    border: Border(
                      bottom: BorderSide(
                        color: AppTheme.accentRedFor(isDark)
                            .withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 15,
                        color: AppTheme.accentRedFor(isDark),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          workbench.offlineErrorMessage ??
                              'App is offline — Unable to reach Gemini AI.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!workbench.isUserLoggedIn) ...[
                        InkWell(
                          key: const ValueKey(
                              'offline_banner_google_signin_btn'),
                          onTap: () => workbench.signInWithGoogle(),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentGreenFor(isDark)
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppTheme.accentGreenFor(isDark)
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                            child: Text(
                              'Sign in with Google',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentGreenFor(isDark),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      InkWell(
                        key: const ValueKey('offline_banner_dismiss_btn'),
                        onTap: workbench.clearOfflineError,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: _buildActiveStageBody()),
            ],
          ),
          if (workbench.hasPendingInviteLanding)
            InviteAcceptanceOverlay(workbench: workbench),
        ],
      ),
    );
  }

  Widget _buildActiveStageBody() {
    if (workbench.activeDocPage == WorkbenchDocPage.newGameIdea) {
      return ProjectPitchScreen(workbench: workbench);
    }
    return PlainDocumentShell(workbench: workbench);
  }
}
