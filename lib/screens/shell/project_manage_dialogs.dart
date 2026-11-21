import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/tier_document.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';

class DisposableTextControllerScope extends StatefulWidget {
  final String initialText;
  final Widget Function(BuildContext context, TextEditingController controller)
      builder;

  const DisposableTextControllerScope({
    super.key,
    this.initialText = '',
    required this.builder,
  });

  @override
  State<DisposableTextControllerScope> createState() =>
      DisposableTextControllerScopeState();
}

class DisposableTextControllerScopeState
    extends State<DisposableTextControllerScope> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

Future<bool> promptRenameProjectDialog(
  BuildContext context,
  WorkbenchProvider workbench,
  TierDocument proj,
) async {
  final isDark = workbench.isDark;
  final bgSurface = AppTheme.bgSurfaceFor(isDark);
  final textPrimary = AppTheme.textPrimaryFor(isDark);
  final textSecondary = AppTheme.textSecondaryFor(isDark);
  final newTitle = await showDialog<String>(
    context: context,
    builder: (rCtx) => DisposableTextControllerScope(
      initialText: proj.title,
      builder: (rCtx, ctrl) => AlertDialog(
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
    ),
  );
  if (newTitle != null && newTitle.trim().isNotEmpty) {
    workbench.renameProject(proj.id, newTitle.trim());
    return true;
  }
  return false;
}

Future<bool> confirmDeleteProjectDialog(
  BuildContext context,
  WorkbenchProvider workbench,
  TierDocument proj,
) async {
  final isDark = workbench.isDark;
  final bgSurface = AppTheme.bgSurfaceFor(isDark);
  final textPrimary = AppTheme.textPrimaryFor(isDark);
  final textSecondary = AppTheme.textSecondaryFor(isDark);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (cCtx) => AlertDialog(
      backgroundColor: bgSurface,
      title: Text(
        'Delete Project?',
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      content: Text(
        'Delete "${proj.title}" and all of its Releases and Epics? This cannot be undone.',
        style: GoogleFonts.inter(
          fontSize: 12.5,
          height: 1.4,
          color: textSecondary,
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancel_delete_project_btn'),
          onPressed: () => Navigator.of(cCtx).pop(false),
          child: Text(
            'Cancel',
            style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
          ),
        ),
        ElevatedButton(
          key: const ValueKey('confirm_delete_project_btn'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentRedFor(isDark),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          onPressed: () => Navigator.of(cCtx).pop(true),
          child: Text(
            'Delete Project',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}
