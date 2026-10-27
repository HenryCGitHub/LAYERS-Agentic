part of '../main.dart';

extension _ShellExportersExt on WorkbenchShell {
  Future<void> _exportFullProjectSpec(BuildContext context) async {
    final draft = workbench.conceptDraft;
    final bp = workbench.releaseBlueprint;
    final rel = workbench.activeRelease;
    final sb = StringBuffer();
    final title = draft != null && draft.title.trim().isNotEmpty
        ? draft.title.trim()
        : (draft != null && draft.sparkIdea.trim().isNotEmpty
            ? draft.sparkIdea.trim()
            : 'LAYERS-Agentic Game Project');
    sb.writeln('# $title — Project & Release Specification');
    if (draft != null) {
      sb.writeln('\n## Stage 1: Project Concept Blueprint');
      sb.writeln(draft.toFullMarkdownSpec());
    } else if (workbench.activeProject != null) {
      final projSec = workbench.activeProject!.sections;
      sb.writeln('\n## Stage 1: Project Concept Blueprint');
      if ((projSec['game_spec'] ?? '').isNotEmpty) {
        sb.writeln('Game Spec: ${projSec['game_spec']}');
      }
      if ((projSec['tech_spec'] ?? '').isNotEmpty) {
        sb.writeln('Tech Spec: ${projSec['tech_spec']}');
      }
      if ((projSec['design_pillars'] ?? '').isNotEmpty) {
        sb.writeln('\nDesign Pillars:\n${projSec['design_pillars']}');
      }
      if ((projSec['trade_offs'] ?? '').isNotEmpty) {
        sb.writeln('\nTrade-Offs:\n${projSec['trade_offs']}');
      }
      if ((projSec['scope'] ?? '').isNotEmpty) {
        sb.writeln('\n${projSec['scope']}');
      }
    }
    final beats = workbench.activeReleaseBeats;
    if (rel != null && beats.isNotEmpty) {
      final relProgress = workbench.getDocumentProgress(rel.id);
      final engineHint =
          draft?.techSpec.join(' ') ?? workbench.activeProject?.sections['tech_spec'];
      sb.writeln('\n## Stage 2: Active Release Workbench (${rel.title} · $relProgress% Verified)');
      for (int bIdx = 0; bIdx < beats.length; bIdx++) {
        final beat = beats[bIdx];
        sb.writeln('\n### Epic ${bIdx + 1}: ${beat.title}');
        final feats = workbench.featuresForBeat(beat.id);
        for (final feat in feats) {
          final p = workbench.getDocumentProgress(feat.id);
          sb.writeln('- **${feat.title}** ($p% verified · ${feat.estimatedDuration})');
          final states = FeatureStateNode.getStatesForDocument(feat);
          for (final cp in states) {
            final cpDone = cp.isCompleted ? '✓' : '○';
            sb.writeln(
              '  - [$cpDone] **${cp.cleanStageTitle} (${cp.releaseVersion})** — *${cp.playtestCondition}*',
            );
            if (cp.tuningParams.isNotEmpty) {
              sb.writeln('    - Tuning: `${cp.tuningParams.join(', ')}`');
            }
            if (cp.edgeCases.isNotEmpty) {
              sb.writeln('    - Guards: ${cp.edgeCases.join(' · ')}');
            }
            for (int tIdx = 0; tIdx < cp.checklist.length; tIdx++) {
              final task = cp.checklist[tIdx];
              if (task.children.isEmpty) {
                TaskHowToBlueprint.resolve(
                  parentTask: task,
                  taskIndex: tIdx,
                  checkpointNode: cp,
                  engineHint: engineHint,
                );
              }
              final tDone = task.completed ? 'x' : ' ';
              sb.writeln('    - [$tDone] ${task.text}');
              for (final sub in task.children) {
                final sDone = sub.completed ? 'x' : ' ';
                sb.writeln('      - [$sDone] ${sub.text}');
              }
            }
          }
        }
      }
    } else if (bp != null) {
      sb.writeln(
        '\n## Stage 2: ${bp.releaseTitle} (${bp.totalIncludedFeatures} Features · ${bp.totalIncludedHours}h)',
      );
      for (int i = 0; i < bp.beats.length; i++) {
        final b = bp.beats[i];
        sb.writeln('\n### Epic ${i + 1}: ${b.title}');
        for (final f in b.features) {
          final status = f.included ? 'INCLUDED (${f.estimatedHours}h)' : 'DEFERRED';
          sb.writeln('- **${f.title}** [$status]: ${f.goal}');
        }
      }
    }
    final fullMd = sb.toString();
    await Clipboard.setData(ClipboardData(text: fullMd));
    triggerMarkdownFileDownload(
      filename: 'PROJECT_SPEC.md',
      content: fullMd,
    );
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

  Future<void> _exportActiveReleaseAgentsMd(BuildContext context) async {
    final agentsMd = workbench.buildActiveReleaseCodingAgentMarkdown();
    await Clipboard.setData(ClipboardData(text: agentsMd));
    final downloaded = triggerMarkdownFileDownload(
      filename: 'AGENTS.md',
      content: agentsMd,
    );
    if (!context.mounted) return;
    final isDark = workbench.isDark;
    final ver = workbench.activeReleaseVersionTag;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.bgSurfaceFor(isDark),
        behavior: SnackBarBehavior.floating,
        content: Text(
          downloaded
              ? 'Downloaded AGENTS.md & copied $ver AI Coding Context to clipboard ✓'
              : 'Copied Active Release ($ver) AGENTS.md / .cursorrules for AI Coding Agent ✓',
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

  Future<void> _exportActiveProjectJson(BuildContext context) async {
    final jsonText = workbench.exportProjectToJson();
    await Clipboard.setData(ClipboardData(text: jsonText));
    final rawTitle = workbench.activeProject?.title ??
        workbench.conceptDraft?.title ??
        'project';
    final slug = rawTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final filename = '${slug.isEmpty ? 'project' : slug}.layers.json';
    final downloaded = triggerMarkdownFileDownload(
      filename: filename,
      content: jsonText,
    );
    if (!context.mounted) return;
    final isDark = workbench.isDark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.bgSurfaceFor(isDark),
        behavior: SnackBarBehavior.floating,
        content: Text(
          downloaded
              ? 'Downloaded $filename & copied Project JSON Backup to clipboard ✓'
              : 'Copied Project JSON Backup ($filename) to clipboard ✓',
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

  Future<void> _showImportProjectJsonDialog(BuildContext context) async {
    final isDark = workbench.isDark;
    final bgSurface = AppTheme.bgSurfaceFor(isDark);
    final bgElevated = AppTheme.bgSurfaceRecessedFor(isDark);
    final borderColor = AppTheme.borderFor(isDark);
    final textPrimary = AppTheme.textPrimaryFor(isDark);
    final textSecondary = AppTheme.textSecondaryFor(isDark);
    final accentAmber = AppTheme.accentAmberFor(isDark);
    final accentGreen = AppTheme.accentGreenFor(isDark);
    final ctrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        key: const ValueKey('import_project_json_dialog'),
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor),
        ),
        title: Row(
          children: [
            Icon(Icons.file_upload_outlined, size: 16, color: accentAmber),
            const SizedBox(width: 8),
            Text(
              'Import Project Backup (.layers.json)',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste a previously exported .layers.json backup below to restore the complete Project Concept, Release Blueprint, and Workbench progress.',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('import_project_json_input'),
                controller: ctrl,
                maxLines: 8,
                autofocus: true,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: '{\n  "schemaVersion": 1,\n  "project": { ... }\n}',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: textSecondary.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: bgElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: textSecondary,
              ),
            ),
          ),
          ElevatedButton.icon(
            key: const ValueKey('confirm_import_project_json_btn'),
            onPressed: () {
              final raw = ctrl.text.trim();
              final importedId = workbench.importProjectFromJson(raw);
              Navigator.of(dialogCtx).pop();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: bgSurface,
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    importedId != null
                        ? 'Restored project "${workbench.activeProject?.title ?? 'Imported Project'}" from JSON ✓'
                        : 'Invalid .layers.json payload — could not import project.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: importedId != null
                          ? accentGreen
                          : AppTheme.accentRedFor(isDark),
                    ),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.restore_page_outlined, size: 14),
            label: Text(
              'Import & Switch',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentAmber,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }
}
