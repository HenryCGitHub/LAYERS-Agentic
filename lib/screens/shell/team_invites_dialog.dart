import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';
import 'project_manage_dialogs.dart';

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

void showTeamInvitesDialog(BuildContext context, WorkbenchProvider workbench) {
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

  bool isSubmitting = false;
  String? feedbackText;
  bool feedbackOk = true;

  showDialog<void>(
    context: context,
    builder: (ctx) {
      return DisposableTextControllerScope(
        builder: (ctx, emailController) {
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
                if (!ctx.mounted) return;
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
    },
  );
}

class InviteAcceptanceOverlay extends StatelessWidget {
  final WorkbenchProvider workbench;

  const InviteAcceptanceOverlay({super.key, required this.workbench});

  @override
  Widget build(BuildContext context) {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    return Container(
      key: const ValueKey('invite_acceptance_overlay'),
      color: Colors.black.withValues(alpha: 0.68),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.borderBrightFor(isDark),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'LAYERS-AGENTIC INVITE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                  InkWell(
                    key: const ValueKey('dismiss_invite_overlay_btn'),
                    onTap: workbench.dismissPendingUrlInvite,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "You've been invited to join LAYERS-Agentic",
                style: AppTheme.displayFont(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                workbench.pendingUrlInvitedEmail != null &&
                        workbench.pendingUrlInvitedEmail!.isNotEmpty
                    ? 'Accept your invite using your Google account (${workbench.pendingUrlInvitedEmail}) to unlock Cloud Sync and Gemini 4 Hydrogen.'
                    : 'Accept your invite by signing in with your invited Google account to unlock Cloud Sync and Gemini 4 Hydrogen.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.45,
                  color: textSecondary,
                ),
              ),
              if (workbench.inviteFeedbackMessage != null &&
                  workbench.inviteFeedbackMessage!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentAmberFor(isDark)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppTheme.accentAmberFor(isDark)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    workbench.inviteFeedbackMessage!,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      height: 1.35,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const ValueKey('accept_invite_google_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF06281E),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () =>
                      workbench.acceptPendingInviteWithGoogle(),
                  icon: const Icon(Icons.verified_user_rounded,
                      size: 16),
                  label: Text(
                    'Accept Invite & Sign in with Google →',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
