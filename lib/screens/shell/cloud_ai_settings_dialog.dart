import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'project_manage_dialogs.dart';
import 'studio_export_actions.dart';
import 'team_invites_dialog.dart';

void showCloudSyncDialog(BuildContext context, WorkbenchProvider workbench) {
  final isDark = workbench.isDark;
  final bgSurface = AppTheme.bgSurfaceFor(isDark);
  final bgRecessed = AppTheme.bgSurfaceRecessedFor(isDark);
  final borderSubtle = AppTheme.borderSubtleFor(isDark);
  final borderBright = AppTheme.borderBrightFor(isDark);
  final textPrimary = AppTheme.textPrimaryFor(isDark);
  final textSecondary = AppTheme.textSecondaryFor(isDark);
  final textMuted = AppTheme.textMutedFor(isDark);
  final accentAmber = AppTheme.accentAmberFor(isDark);

  String selectedCollabRole = 'editor';
  bool isSigningIn = false;

  showDialog<void>(
    context: context,
    builder: (ctx) {
      return DisposableTextControllerScope(
        builder: (ctx, collabEmailCtrl) {
          return ListenableBuilder(
            listenable: workbench,
            builder: (ctx, _) {
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
                                      ? 'All Stage 1 Project Specs and Stage 2 Epic Specs sync live to Firebase project layers-b8a16.'
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
                                showImportProjectJsonDialog(context, workbench);
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
                                            if (await promptRenameProjectDialog(ctx, workbench, p)) {
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
                                          onTap: () async {
                                            if (await confirmDeleteProjectDialog(ctx, workbench, p)) {
                                              workbench.deleteProject(p.id);
                                              if (ctx.mounted) setModalState(() {});
                                            }
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
                    showTeamInvitesDialog(context, workbench);
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
                            if (ctx.mounted) {
                              setModalState(() {
                                isSigningIn = false;
                              });
                            }
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
        },
      );
    },
  );
}
