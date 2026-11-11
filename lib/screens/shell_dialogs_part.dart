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
    final accentAmber = AppTheme.accentAmberFor(isDark);

    final collabEmailCtrl = TextEditingController();
    String selectedCollabRole = 'editor';
    bool isSigningIn = false;

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
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSynced ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded,
                          size: 18,
                          color: isSynced ? textPrimary : textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Firebase Cloud Sync & Local Vault',
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.displayFont(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
                            color: isSynced ? borderBright : borderSubtle,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSynced ? textPrimary : textMuted,
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                key: const ValueKey('vault_import_project_btn'),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _showImportProjectJsonDialog(context);
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  child: Text(
                                    'Import .json',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
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
                                      color: textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
                                              ? textPrimary
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
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: const Color(0xFF06281E),
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
                                  fontWeight: FontWeight.w700,
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
                if (workbench.isAdminUser)
                  TextButton.icon(
                    key: const ValueKey('open_team_invites_from_vault_btn'),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _showTeamInvitesDialog(context);
                    },
                    icon: const Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 14,
                      color: Color(0xFF10B981),
                    ),
                    label: Text(
                      'Team & Invites',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ),
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
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF06281E),
                      elevation: 0,
                    ),
                    onPressed: isSigningIn
                        ? null
                        : () async {
                            setModalState(() {
                              isSigningIn = true;
                            });
                            try {
                              await workbench.signInWithGoogle();
                            } finally {
                              setModalState(() {
                                isSigningIn = false;
                              });
                            }
                          },
                    icon: isSigningIn
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF06281E),
                              ),
                            ),
                          )
                        : const Icon(Icons.cloud_upload_rounded, size: 15),
                    label: Text(
                      isSigningIn ? 'Signing in...' : 'Sign in with Google',
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

  String _formatInviteTimestamp(int? timestampMs) {
    if (timestampMs == null || timestampMs <= 0) return 'just now';
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showTeamInvitesDialog(BuildContext context) {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final bgRecessed = AppTheme.bgSurfaceRecessedFor(isDark);
    final borderSubtle = AppTheme.borderSubtleFor(isDark);
    final borderBright = AppTheme.borderBrightFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final textMuted = AppTheme.textMutedFor(isDark);
    final accentAmber = AppTheme.accentAmberFor(isDark);
    final accentGreen = AppTheme.accentGreenFor(isDark);
    final accentRed = AppTheme.accentRedFor(isDark);

    final emailController = TextEditingController();
    bool isSubmitting = false;
    String? feedbackText;
    bool feedbackOk = true;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> triggerInvite(
              String rawEmail, {
              bool resetStatus = false,
            }) async {
              if (isSubmitting) return;
              setModalState(() {
                isSubmitting = true;
                feedbackText = null;
              });
              final res = await workbench.sendUserInvite(
                rawEmail,
                resetStatus: resetStatus,
              );
              if (res.ok && res.inviteUrl != null && !res.emailSent) {
                await Clipboard.setData(ClipboardData(text: res.inviteUrl!));
              }
              if (res.ok && rawEmail == emailController.text) {
                emailController.clear();
              }
              setModalState(() {
                isSubmitting = false;
                feedbackOk = res.ok;
                feedbackText = res.message;
              });
            }

            return ListenableBuilder(
              listenable: workbench,
              builder: (ctx, _) {
                final pending = workbench.pendingInvites;
                final active = workbench.activeApprovedMembers;
                final revoked = workbench.revokedMembers;

                return AlertDialog(
                  key: const ValueKey('team_invites_dialog'),
                  backgroundColor: bgSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: borderBright),
                  ),
                  title: Row(
                    children: [
                      Icon(
                        Icons.group_add_rounded,
                        size: 18,
                        color: accentGreen,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Team Access & Invites',
                          style: AppTheme.displayFont(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'INVITE USER BY GOOGLE EMAIL',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('team_invite_email_input'),
                                  controller: emailController,
                                  onSubmitted: (v) => triggerInvite(v),
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: textPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    filled: true,
                                    fillColor: bgRecessed,
                                    hintText:
                                        'Enter Google email (e.g., alex@gmail.com)...',
                                    hintStyle: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: textMuted,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide:
                                          BorderSide(color: borderSubtle),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide:
                                          BorderSide(color: borderSubtle),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                key: const ValueKey('team_send_invite_btn'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: const Color(0xFF06281E),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                onPressed: isSubmitting
                                    ? null
                                    : () => triggerInvite(emailController.text),
                                child: Text(
                                  isSubmitting ? 'Sending...' : 'Send Invite',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (feedbackText != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: (feedbackOk ? accentGreen : accentAmber)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color:
                                      (feedbackOk ? accentGreen : accentAmber)
                                          .withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                feedbackText!,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'PENDING INVITES (${pending.length})',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: pending.isNotEmpty
                                  ? accentAmber
                                  : textMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (pending.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: bgRecessed,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: borderSubtle),
                              ),
                              child: Text(
                                'No pending invites waiting for acceptance.',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: textMuted,
                                ),
                              ),
                            )
                          else
                            for (final r in pending)
                              Container(
                                key: ValueKey('pending_invite_row_${r.email}'),
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: bgRecessed,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: accentAmber.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r.email,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'PENDING · Sent ${_formatInviteTimestamp(r.invitedAtMs)}',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 9.5,
                                              color: accentAmber,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (r.inviteUrl != null &&
                                        r.inviteUrl!.isNotEmpty) ...[
                                      InkWell(
                                        key: ValueKey(
                                            'copy_invite_link_btn_${r.email}'),
                                        onTap: () async {
                                          await Clipboard.setData(
                                            ClipboardData(text: r.inviteUrl!),
                                          );
                                          setModalState(() {
                                            feedbackOk = true;
                                            feedbackText =
                                                'Copied invite link for ${r.email}.';
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(4),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            'Copy Link',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    InkWell(
                                      key: ValueKey(
                                          'resend_invite_btn_${r.email}'),
                                      onTap: () => triggerInvite(r.email),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          'Resend',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: accentGreen,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      key: ValueKey(
                                          'cancel_invite_btn_${r.email}'),
                                      onTap: () async {
                                        await workbench
                                            .revokeUserInvite(r.email);
                                        setModalState(() {
                                          feedbackOk = true;
                                          feedbackText =
                                              'Cancelled invite for ${r.email}.';
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          'Cancel',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: accentRed,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          const SizedBox(height: 14),
                          Text(
                            'ACTIVE MEMBERS (${1 + active.length})',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: bgRecessed,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: borderSubtle),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    WorkbenchProvider.ownerAdminEmail,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentGreen.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'OWNER',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: accentGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final r in active)
                            Container(
                              key: ValueKey('active_member_row_${r.email}'),
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: bgRecessed,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: borderSubtle),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.displayName.isNotEmpty
                                              ? '${r.displayName} (${r.email})'
                                              : r.email,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'ACTIVE ✓ · Joined ${_formatInviteTimestamp(r.acceptedAtMs)}',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 9.5,
                                            color: accentGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  InkWell(
                                    key:
                                        ValueKey('revoke_member_btn_${r.email}'),
                                    onTap: () async {
                                      await workbench.revokeUserInvite(r.email);
                                      setModalState(() {
                                        feedbackOk = true;
                                        feedbackText =
                                            'Revoked access for ${r.email}.';
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        'Revoke',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: accentRed,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (revoked.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              'REVOKED / CANCELLED (${revoked.length})',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: textMuted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final r in revoked)
                              Container(
                                key: ValueKey('revoked_member_row_${r.email}'),
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: bgRecessed,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: borderSubtle),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.email,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      key: ValueKey(
                                          'reinvite_member_btn_${r.email}'),
                                      onTap: () => triggerInvite(
                                        r.email,
                                        resetStatus: true,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          'Re-Invite',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: accentGreen,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<bool> _promptRenameProjectDialog(
    BuildContext context,
    TierDocument proj,
  ) async {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
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
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: const Color(0xFF06281E),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(rCtx).pop(ctrl.text),
            child: Text(
              'Save',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
            ),
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

