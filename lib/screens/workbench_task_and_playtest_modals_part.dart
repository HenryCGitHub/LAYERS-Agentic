part of 'release_workbench_screen.dart';

extension _WorkbenchTaskAndPlaytestModalsExt on _ReleaseWorkbenchScreenState {
  Future<void> _promptEditHowToSubStepDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int pIdx,
    int sIdx,
  ) async {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    if (sIdx < 0 || sIdx >= parentTask.children.length) return;
    final sub = parentTask.children[sIdx];
    final bp = TaskHowToBlueprint.resolve(
      parentTask: parentTask,
      taskIndex: pIdx,
      checkpointNode: node,
      engineHint: _engineHint,
      unrealCppMode: _unrealCppMode,
    );
    final resolvedSub = sIdx < bp.subSteps.length ? bp.subSteps[sIdx] : null;
    final titleCtrl = TextEditingController(
      text: resolvedSub?.stepNumberLabel ?? sub.text,
    );
    final whereCtrl = TextEditingController(
      text: resolvedSub?.stepPath ?? sub.codeLanguage ?? '',
    );
    final instrCtrl = TextEditingController(
      text: resolvedSub?.instruction ?? sub.specNotes ?? '',
    );
    final codeCtrl = TextEditingController(
      text: resolvedSub?.codeFormula ?? sub.codeSnippet ?? '',
    );
    final verifyCtrl = TextEditingController(
      text: resolvedSub?.verifyResult ?? sub.verification ?? '',
    );

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Edit How-To Sub-Step (${pIdx + 1}.${sIdx + 1})',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('edit_substep_title_input'),
                controller: titleCtrl,
                style: GoogleFonts.inter(fontSize: 12.5, color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'Sub-step Title',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('edit_substep_where_input'),
                controller: whereCtrl,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'Where in Engine (Menu / Panel / File Path)',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('edit_substep_instruction_input'),
                controller: instrCtrl,
                maxLines: 2,
                style: GoogleFonts.inter(fontSize: 12, color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'How-To Instruction',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('edit_substep_code_input'),
                controller: codeCtrl,
                maxLines: 3,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: AppTheme.accentCyanFor(isDark),
                ),
                decoration: InputDecoration(
                  labelText: 'Code Formula / Snippet',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('edit_substep_verify_input'),
                controller: verifyCtrl,
                style: GoogleFonts.inter(fontSize: 12, color: textPrimary),
                decoration: InputDecoration(
                  labelText: 'Done Check (Verify in Viewport)',
                  labelStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (parentTask.children.length > 1)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('delete'),
              child: Text(
                'Delete',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentCrimson,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: focalAccent,
              foregroundColor: focalAccentFg,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: Text(
              'Save Sub-Step',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == 'cancel') return;
        _rebuild(() {
      if (action == 'delete' && parentTask.children.length > 1) {
        parentTask.children.removeAt(sIdx);
        parentTask.completed = parentTask.children.isNotEmpty &&
            parentTask.children.every((c) => c.completed);
      } else if (action == 'save') {
        if (titleCtrl.text.trim().isNotEmpty) {
          sub.text = titleCtrl.text.trim();
        }
        sub.codeLanguage = whereCtrl.text.trim();
        sub.specNotes = instrCtrl.text.trim();
        sub.codeSnippet = codeCtrl.text.trim();
        sub.verification = verifyCtrl.text.trim();
        sub.codeTargetFile = 'custom_snippet';
      }
      TaskHowToBlueprint.clearCache();
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  Future<void> _copySubStepCodeFormula(
    int pIdx,
    int sIdx,
    String codeFormula,
  ) async {
    await Clipboard.setData(ClipboardData(text: codeFormula));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Copied Step ${pIdx + 1}.${sIdx + 1} code formula to clipboard ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyAllTaskCode(TaskHowToBlueprint howTo) async {
    final buffer = StringBuffer()
      ..writeln('// === Task ${howTo.numLabel}: ${howTo.cleanTitle} ===');
    for (int i = 0; i < howTo.subSteps.length; i++) {
      final step = howTo.subSteps[i];
      final stepNum = (i + 1).toString().padLeft(2, '0');
      buffer
        ..writeln()
        ..writeln('// --- Step $stepNum: ${step.shortTitle} ---')
        ..writeln(step.codeFormula.trim());
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Copied all ${howTo.subSteps.length} step code blocks for Task ${howTo.numLabel} ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _promptTailorHowToDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    int checkpointIndex,
    int pIdx,
  ) async {
    final node = states[checkpointIndex];
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    final ctrl = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          '✦ Tailor How-To Sub-Steps (Task ${(pIdx + 1).toString().padLeft(2, '0')})',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Describe your exact Scene / Node / Script setup for "${parentTask.text}". The Agent will rewrite all sub-steps in Task ${(pIdx + 1).toString().padLeft(2, '0')} using your exact node and script names:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('tailor_howto_context_input'),
                controller: ctrl,
                autofocus: true,
                maxLines: 3,
                onSubmitted: (_) => Navigator.of(ctx).pop('tailor'),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  hintText:
                      'e.g., CharacterBody2D with RayCast2D HookRay and Line2D RopeVisual',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: textMuted,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_tailor_howto_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: focalAccent,
              foregroundColor: focalAccentFg,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop('tailor'),
            child: Text(
              '✦ Tailor Sub-Steps',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted || action != 'tailor') return;
    final contextText = ctrl.text.trim();
    if (contextText.isEmpty) return;
    final ok = await widget.workbench.tailorTaskHowToSubSteps(
      featureId: feat.id,
      states: states,
      checkpointIndex: checkpointIndex,
      taskIndex: pIdx,
      userContext: contextText,
    );
    if (!mounted) return;
        _rebuild(() {});
    if (!ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Tailored Task ${(pIdx + 1).toString().padLeft(2, '0')} How-To sub-steps to "$contextText" ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: accentEmerald,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleHowToSubStepCompletion(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int pIdx,
    int sIdx,
  ) {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    if (sIdx < 0 || sIdx >= parentTask.children.length) return;
    final wasDone = node.isCompleted;
    final nextCompleted = !parentTask.children[sIdx].completed;
    parentTask.children[sIdx].completed = nextCompleted;
    parentTask.completed = parentTask.children.isNotEmpty &&
        parentTask.children.every((c) => c.completed);
    final nowDone = node.isCompleted;
        _rebuild(() {
      _selectedTaskIndexByCheckpoint[node.id] = pIdx;
      _selectedSubStepIndexByTask['${node.id}_$pIdx'] = sIdx;
      if (!wasDone && nowDone) {
        _awaitingPlaytestVerification.add(node.id);
      } else if (!nowDone) {
        _awaitingPlaytestVerification.remove(node.id);
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  void _toggleTaskGroupCompletion(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int tIdx,
  ) {
    if (tIdx < 0 || tIdx >= node.checklist.length) return;
    final task = node.checklist[tIdx];
    final markDone = !task.completed;
    task.completed = markDone;
    for (final c in task.children) {
      c.completed = markDone;
    }
        _rebuild(() {
      final nextTaskIdx = node.checklist.indexWhere((t) => !t.completed);
      if (markDone && nextTaskIdx != -1) {
        _manualCheckpointFocusIndex = states.indexWhere((s) => s.id == node.id);
        _selectedTaskIndexByCheckpoint[node.id] = nextTaskIdx;
        _selectedSubStepIndexByTask['${node.id}_$nextTaskIdx'] = 0;
      } else if (markDone) {
        final activeRelVer = widget.workbench.activeReleaseVersionTag;
        int nextCpIdx = states.indexWhere(
          (s) => s.releaseVersion == activeRelVer && !s.isCompleted,
        );
        if (nextCpIdx == -1) {
          nextCpIdx = states.indexWhere((s) => !s.isCompleted);
        }
        if (nextCpIdx != -1) {
          _manualCheckpointFocusIndex = nextCpIdx;
          final nextCp = states[nextCpIdx];
          _selectedTaskIndexByCheckpoint[nextCp.id] = 0;
          _selectedSubStepIndexByTask['${nextCp.id}_0'] = 0;
        } else {
          _selectedTaskIndexByCheckpoint[node.id] = tIdx;
        }
      } else {
        _manualCheckpointFocusIndex = states.indexWhere((s) => s.id == node.id);
        _selectedTaskIndexByCheckpoint[node.id] = tIdx;
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  Future<void> _showEditCheckpointTuningAndGuardsDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
  ) async {
    final tuningCtrl = TextEditingController(
      text: node.tuningParams.join(', '),
    );
    final guardsCtrl = TextEditingController(
      text: node.edgeCases.join('\n'),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          'Edit Checkpoint Tuning & Edge Guards',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'TUNING PARAMETERS (COMMA SEPARATED)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: accentViolet,
                ),
              ),
              const SizedBox(height: 5),
              TextField(
                key: const ValueKey('edit_stage3_tuning_input'),
                controller: tuningCtrl,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: bgRecessed,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'EDGE-CASE GUARDS (1 PER LINE)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: accentAmber,
                ),
              ),
              const SizedBox(height: 5),
              TextField(
                key: const ValueKey('edit_stage3_guards_input'),
                controller: guardsCtrl,
                maxLines: 3,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: bgRecessed,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('save_stage3_tuning_guards_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Save Spec',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final oldParams = List<String>.from(node.tuningParams);
      final newParams = tuningCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      node.tuningParams = newParams;
      node.edgeCases = guardsCtrl.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      widget.workbench.updateFeatureStates(feat.id, states);

      final renames = <String>[];
      int totalFeaturesPropagated = 0;
      final pairCount = oldParams.length < newParams.length
          ? oldParams.length
          : newParams.length;
      for (int i = 0; i < pairCount; i++) {
        final oldId = oldParams[i].split(':').first.trim();
        final newId = newParams[i].split(':').first.trim();
        if (oldId.isNotEmpty && newId.isNotEmpty && oldId != newId) {
          final count = widget.workbench.propagateVariableRenameAcrossProject(
            oldId,
            newId,
          );
          renames.add('$oldId → $newId');
          totalFeaturesPropagated += count;
        }
      }
      if (renames.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: bgSurface,
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Propagated variable rename (${renames.join(', ')}) across $totalFeaturesPropagated project feature(s) ✓',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accentEmerald,
              ),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _showLogPlaytestIssueDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    int checkpointIndex,
  ) async {
    final ctrl = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderBright),
        ),
        title: Text(
          '🐞 Log Playtest Issue',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Describe the bug or feel issue observed in the game viewport. The Agent will append a 3-step [FIX] task group and a [PLAYTEST GUARD] rule:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('workbench_log_playtest_issue_input'),
                controller: ctrl,
                autofocus: true,
                style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g., Dash clips through thin arena walls on diagonal input',
                  hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                  filled: true,
                  fillColor: bgRecessed,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
                  ),
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_workbench_log_playtest_issue_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentAmber,
              foregroundColor: const Color(0xFF1F1300),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(
              '+ Add [FIX] Task & Guard',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      final newIdx = widget.workbench.logPlaytestIssueOnCheckpoint(
        featureId: feat.id,
        states: states,
        checkpointIndex: checkpointIndex,
        issueDescription: saved.trim(),
      );
      if (newIdx >= 0 && checkpointIndex < states.length) {
        final cpNode = states[checkpointIndex];
        _rebuild(() {
          _manualCheckpointFocusIndex = checkpointIndex;
          _selectedTaskIndexByCheckpoint[cpNode.id] = newIdx;
          _selectedSubStepIndexByTask['${cpNode.id}_$newIdx'] = 0;
        });
      }
    }
  }

  /// Copies the focused single-feature AI Coding Agent prompt to the clipboard.
  void _copyActiveFeaturePrompt(TierDocument feat) {
    final promptText = widget.workbench.buildActiveFeatureCodingAgentPrompt(
      feat.id,
      unrealCppMode: _unrealCppMode,
    );
    Clipboard.setData(ClipboardData(text: promptText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied "${feat.title}" AI Coding Prompt to clipboard',
          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Opens the unified Playtest Run Sheet modal listing every active Feature's Playtest Gate,
  /// Tuning Variables, and `[GUARD]` rules in the current release with 1-click Pass & Flag actions.
  Future<void> _showPlaytestRunSheetModal(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return ListenableBuilder(
          listenable: widget.workbench,
          builder: (context, _) {
            final activeVer = widget.workbench.activeReleaseVersionTag;
            final rel = widget.workbench.activeRelease;
            final beats = widget.workbench.activeReleaseBeats;
            int totalFeats = 0;
            int passedFeats = 0;
            for (final b in beats) {
              for (final f in widget.workbench.featuresForBeat(b.id)) {
                totalFeats++;
                if (widget.workbench.getDocumentProgress(f.id) >= 100) {
                  passedFeats++;
                }
              }
            }

            return Dialog(
              key: const ValueKey('playtest_run_sheet_modal'),
              backgroundColor: bgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: borderSubtle),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 760,
                  maxHeight: 680,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Modal Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: bgRecessed,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        border: Border(bottom: BorderSide(color: borderSubtle)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PLAYTEST RUN SHEET · ${activeVer.toUpperCase()} GATE VERIFICATION',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.7,
                                    color: accentCyan,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  rel?.title ?? '$activeVer Playtest Checklist',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            key: const ValueKey('playtest_sheet_summary_badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: passedFeats == totalFeats && totalFeats > 0
                                  ? accentEmerald.withValues(alpha: 0.14)
                                  : accentAmber.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color:
                                    passedFeats == totalFeats && totalFeats > 0
                                        ? accentEmerald.withValues(alpha: 0.4)
                                        : accentAmber.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              '$passedFeats/$totalFeats GATES PASSED',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color:
                                    passedFeats == totalFeats && totalFeats > 0
                                        ? accentEmerald
                                        : accentAmber,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable Epic & Feature Gate Rows
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int bIdx = 0; bIdx < beats.length; bIdx++) ...[
                              Padding(
                                padding: EdgeInsets.only(
                                  top: bIdx == 0 ? 0 : 14,
                                  bottom: 8,
                                ),
                                child: Text(
                                  'E${(bIdx + 1).toString().padLeft(2, '0')} · ${_formatOutlineBeatDisplayTitle(beats[bIdx].title).toUpperCase()}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.7,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                              for (final feat in widget.workbench
                                  .featuresForBeat(beats[bIdx].id))
                                Builder(
                                  builder: (context) {
                                    final states =
                                        FeatureStateNode.getStatesForDocument(
                                      feat,
                                    );
                                    int cpIdx = states.lastIndexWhere(
                                      (s) => s.releaseVersion == activeVer,
                                    );
                                    if (cpIdx < 0 && states.isNotEmpty) {
                                      cpIdx = states.length - 1;
                                    }
                                    final cpNode =
                                        cpIdx >= 0 ? states[cpIdx] : null;
                                    final prog = widget.workbench
                                        .getDocumentProgress(feat.id);
                                    final isPassed = prog >= 100;

                                    return Container(
                                      key: ValueKey(
                                        'playtest_sheet_row_${feat.id}',
                                      ),
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: bgRecessed,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isPassed
                                              ? accentEmerald.withValues(
                                                  alpha: 0.45,
                                                )
                                              : borderSubtle,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      isPassed
                                                          ? Icons
                                                              .check_circle_rounded
                                                          : Icons
                                                              .radio_button_unchecked_rounded,
                                                      size: 16,
                                                      color: isPassed
                                                          ? accentEmerald
                                                          : textMuted,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Flexible(
                                                      child: Text(
                                                        _formatOutlineFeatureDisplayTitle(
                                                          feat.title,
                                                          beats[bIdx].title,
                                                          beatIndex: bIdx,
                                                        ),
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 13.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: textPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      '$prog%',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: isPassed
                                                            ? accentEmerald
                                                            : textMuted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (cpNode != null) ...[
                                                    InkWell(
                                                      key: ValueKey(
                                                        'playtest_sheet_pass_btn_${feat.id}',
                                                      ),
                                                      onTap: () {
                                                        final targetDone =
                                                            !isPassed;
                                                        for (final t in cpNode
                                                            .checklist) {
                                                          t.completed =
                                                              targetDone;
                                                          for (final sub
                                                              in t.children) {
                                                            sub.completed =
                                                                targetDone;
                                                          }
                                                        }
                                                        widget.workbench
                                                            .updateFeatureStates(
                                                          feat.id,
                                                          states,
                                                        );
                                                      },
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        5,
                                                      ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 10,
                                                          vertical: 5,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isPassed
                                                              ? accentEmerald
                                                                  .withValues(
                                                                  alpha: 0.16,
                                                                )
                                                              : bgSurface,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(5),
                                                          border: Border.all(
                                                            color: isPassed
                                                                ? accentEmerald
                                                                : borderSubtle,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          isPassed
                                                              ? '✓ Gate Passed'
                                                              : '✓ Pass Gate',
                                                          style: GoogleFonts
                                                              .jetBrainsMono(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: isPassed
                                                                ? accentEmerald
                                                                : textPrimary,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    InkWell(
                                                      key: ValueKey(
                                                        'playtest_sheet_flag_btn_${feat.id}',
                                                      ),
                                                      onTap: () =>
                                                          _showLogPlaytestIssueDialog(
                                                        feat,
                                                        states,
                                                        cpIdx,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        5,
                                                      ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 9,
                                                          vertical: 5,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: accentAmber
                                                              .withValues(
                                                            alpha: 0.12,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(5),
                                                          border: Border.all(
                                                            color: accentAmber
                                                                .withValues(
                                                              alpha: 0.4,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          '🐞 Flag Issue',
                                                          style: GoogleFonts
                                                              .jetBrainsMono(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: accentAmber,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                          if (cpNode != null) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              'Playtest Gate: ${cpNode.playtestCondition}',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: textSecondary,
                                              ),
                                            ),
                                            if (cpNode.edgeCases.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  for (final g
                                                      in cpNode.edgeCases)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 7,
                                                        vertical: 3,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: bgSurface,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                        border: Border.all(
                                                          color: borderSubtle,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        g,
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 9.5,
                                                          color: textMuted,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ],
                        ),
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

  /// Opens the Two-Way Engine Code Sync dialog where the developer can paste a GDScript, C#,
  /// or Unreal C++ script to update Feature tuning parameters and `[GUARD]` rules.
  Future<void> _showSyncFeatureFromCodeDialog(
    TierDocument feat,
    FeatureStateNode node,
  ) async {
    final codeCtrl = TextEditingController();
    final pasted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('sync_feature_from_code_dialog'),
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderSubtle),
        ),
        title: Text(
          '⇄ Sync Tuning & Guards from Engine Code · ${feat.title}',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste your modified GDScript (.gd), Unity C# (.cs), or Unreal C++ (.h / .cpp) script below. Updated variable values and new [GUARD] checks will sync into "${node.cleanStageTitle}".',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('sync_feature_code_input_field'),
                controller: codeCtrl,
                autofocus: true,
                maxLines: 10,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  hintText:
                      'e.g.\nUPROPERTY(EditAnywhere)\nfloat MoveSpeed = 640.0f;\n// [GUARD] Prevent dash while stunned',
                  hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: textMuted,
                  ),
                  filled: true,
                  fillColor: bgRecessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: borderSubtle),
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
              style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
            ),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_sync_from_code_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor: const Color(0xFF04131D),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(codeCtrl.text),
            child: Text(
              'Sync Tuning & Guards',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (pasted != null && pasted.trim().isNotEmpty && mounted) {
      final result = await widget.workbench.syncFeatureTuningAndGuardsFromCode(
        feat.id,
        pasted,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Synced ${result.updatedVars} tuning variable(s) and ${result.addedGuards} new guard(s) from code.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
