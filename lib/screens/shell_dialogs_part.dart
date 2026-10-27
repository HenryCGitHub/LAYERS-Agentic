part of '../main.dart';

extension _ShellDialogsExt on WorkbenchShell {
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
                                        ? 'All Stage 1 Concepts and Stage 2 Release Workbench Checkpoints sync live to Firebase project layers-b8a16.'
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
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 280),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final p in projs)
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
                                              if (await _promptRenameProjectDialog(ctx, p)) {
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
                              ],
                            ),
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
                        '02 · RELEASE PLAN CREATION MODEL (STAGE 2 ONE-SHOT)',
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
                              ? 'Default — Gemini 4 Argon (One-Shot Release Plan creation only; chat uses Flash)'
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
                      if (workbench.aiLastErrorStatus != null) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: accentAmber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: accentAmber.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            workbench.aiLastErrorStatus == 'HTTP 402'
                                ? 'API Notice (HTTP 402): AI Studio prepayment credits are depleted on the current key. App is offline until credits are topped up or a new Gemini API key is saved below.'
                                : 'API Notice (${workbench.aiLastErrorStatus}): Live Gemini call returned an auth/quota error. App is offline until a valid Gemini API key is saved below.',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              height: 1.35,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ],
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

  Future<bool> _promptRenameProjectDialog(
    BuildContext context,
    TierDocument proj,
  ) async {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final ctrl = TextEditingController(text: proj.title);
    final newTitle = await showDialog<String>(
      context: context,
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
          onSubmitted: (v) => Navigator.of(rCtx).pop(v),
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
      workbench.renameProject(proj.id, newTitle.trim());
      return true;
    }
    return false;
  }
}
