part of 'release_workbench_screen.dart';

extension _WorkbenchTaskAndPlaytestModalsExt on _ReleaseWorkbenchScreenState {
  Future<void> _promptEditHowToSubStepDialog(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int stepIdx,
  ) async {
    node.flattenLegacyNestedChecklistIfNeeded();
    final unifiedSteps = TaskHowToBlueprint.resolveUnifiedSteps(
      checkpointNode: node,
      engineHint: _engineHint,
      phase: widget.workbench.currentPhase,
    );
    if (stepIdx < 0 || stepIdx >= unifiedSteps.length) return;
    final resolvedSub = unifiedSteps[stepIdx];
    final sub = resolvedSub.subtask;
    String selectedStepRole = TaskHowToBlueprint.normalizeStepRole(
      resolvedSub.stepRole ?? resolvedSub.resolvedDockStage.stepRole,
    );
    if (selectedStepRole.isEmpty) {
      selectedStepRole = GodotDockStage.code.stepRole;
    }
    String selectedVerifyMode =
        resolvedSub.isEditorCheck ? 'editor' : 'playtest';
    final titleCtrl = TextEditingController(
      text: resolvedSub.shortTitle.isNotEmpty
          ? resolvedSub.shortTitle
          : sub.text,
    );
    final whereCtrl = TextEditingController(
      text: resolvedSub.stepPath.isNotEmpty
          ? resolvedSub.stepPath
          : (sub.codeLanguage ?? ''),
    );
    final instrCtrl = TextEditingController(
      text: resolvedSub.instruction.isNotEmpty
          ? resolvedSub.instruction
          : (sub.specNotes ?? ''),
    );
    final codeCtrl = TextEditingController(
      text: resolvedSub.codeFormula.isNotEmpty
          ? resolvedSub.codeFormula
          : (sub.codeSnippet ?? ''),
    );
    final verifyCtrl = TextEditingController(
      text: resolvedSub.verifyResult.isNotEmpty
          ? resolvedSub.verifyResult
          : (sub.verification ?? ''),
    );

    const roleOptions = <({String role, String badge, String defaultVerify})>[
      (role: 'editor_setup', badge: 'SCENE', defaultVerify: 'editor'),
      (role: 'inspector_setup', badge: 'INSP', defaultVerify: 'editor'),
      (role: 'script_logic', badge: 'CODE', defaultVerify: 'playtest'),
      (role: 'wire_and_verify', badge: 'WIRE', defaultVerify: 'playtest'),
      (role: 'fix', badge: 'FIX', defaultVerify: 'playtest'),
    ];

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: borderBright),
          ),
          title: Text(
            'Edit How-To Step (${stepIdx + 1})',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'DOCK:',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: textMuted,
                        ),
                      ),
                      for (final opt in roleOptions)
                        InkWell(
                          key: ValueKey('edit_substep_role_${opt.role}'),
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => setDialogState(() {
                            selectedStepRole = opt.role;
                            selectedVerifyMode = opt.defaultVerify;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: selectedStepRole == opt.role
                                  ? accentCyan.withValues(alpha: 0.16)
                                  : bgRecessed,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: selectedStepRole == opt.role
                                    ? accentCyan
                                    : borderSubtle,
                              ),
                            ),
                            child: Text(
                              opt.badge,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: selectedStepRole == opt.role
                                    ? accentCyan
                                    : textSecondary,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      InkWell(
                        key: const ValueKey('edit_substep_verify_mode_toggle'),
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => setDialogState(() {
                          selectedVerifyMode =
                              selectedVerifyMode == 'editor' ? 'playtest' : 'editor';
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: bgRecessed,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Text(
                            selectedVerifyMode == 'editor'
                                ? 'Verify: Editor'
                                : 'Verify: F6 Playtest',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
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
          ),
          actions: [
            if (node.checklist.length > 1)
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
                backgroundColor: accentEmerald,
                foregroundColor:
                    isDark ? const Color(0xFF06281E) : Colors.white,
                elevation: 0,
              ),
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: Text(
                'Save Step',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null || action == 'cancel') return;
    _rebuild(() {
      if (action == 'delete' && node.checklist.length > 1) {
        final removeIdx = node.checklist.indexOf(sub);
        if (removeIdx != -1) {
          node.checklist.removeAt(removeIdx);
          final nextMax = (node.checklist.length - 1).clamp(0, node.checklist.length);
          _selectedFlatStepIndexByCheckpoint[node.id] = removeIdx.clamp(0, nextMax);
        }
      } else if (action == 'save') {
        if (titleCtrl.text.trim().isNotEmpty) {
          sub.text = titleCtrl.text.trim();
        }
        sub.codeLanguage = whereCtrl.text.trim();
        sub.specNotes = TaskHowToBlueprint.encodeThreeAreaNotes(
          instruction: instrCtrl.text.trim(),
          area1Hierarchy: resolvedSub.area1Hierarchy,
          area2Inspector: resolvedSub.area2Inspector,
          verifyMode: selectedVerifyMode,
          stepRole: selectedStepRole,
        );
        sub.codeSnippet = codeCtrl.text.trim();
        sub.verification = verifyCtrl.text.trim();
        sub.codeTargetFile = 'custom_snippet';
      }
      TaskHowToBlueprint.clearCache();
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  Future<void> _copySubStepCodeFormula(
    int stepIdx,
    String codeFormula,
  ) async {
    final cleanCode = codeFormula
        .split('\n')
        .map((line) {
          if (line.startsWith('+ ') && !line.startsWith('++')) {
            return line.substring(2);
          }
          if (line.startsWith('+') &&
              !line.startsWith('++') &&
              line.length > 1 &&
              RegExp(r'^[@\w\s#\$]').hasMatch(line.substring(1))) {
            return line.substring(1);
          }
          return line;
        })
        .join('\n');
    await Clipboard.setData(ClipboardData(text: cleanCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Copied Step ${stepIdx + 1} code formula to clipboard ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textPrimary,
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
    int stepIdx,
  ) async {
    final node = states[checkpointIndex];
    node.flattenLegacyNestedChecklistIfNeeded();
    final unifiedSteps = TaskHowToBlueprint.resolveUnifiedSteps(
      checkpointNode: node,
      engineHint: _engineHint,
      phase: widget.workbench.currentPhase,
    );
    if (stepIdx < 0 || stepIdx >= unifiedSteps.length) return;
    final targetStep = unifiedSteps[stepIdx];
    final ctrl = TextEditingController();
    bool preserveSingleStep = true;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: borderBright),
          ),
          title: Text(
            '✦ Tailor Step (${(stepIdx + 1).toString().padLeft(2, '0')})',
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
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    InkWell(
                      key: const ValueKey('tailor_mode_single_step'),
                      borderRadius: BorderRadius.circular(5),
                      onTap: () =>
                          setDialogState(() => preserveSingleStep = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: preserveSingleStep
                              ? accentCyan.withValues(alpha: 0.14)
                              : bgRecessed,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: preserveSingleStep
                                ? accentCyan
                                : borderSubtle,
                          ),
                        ),
                        child: Text(
                          'This step only',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: preserveSingleStep
                                ? accentCyan
                                : textSecondary,
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      key: const ValueKey('tailor_mode_split_steps'),
                      borderRadius: BorderRadius.circular(5),
                      onTap: () =>
                          setDialogState(() => preserveSingleStep = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: !preserveSingleStep
                              ? accentViolet.withValues(alpha: 0.14)
                              : bgRecessed,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: !preserveSingleStep
                                ? accentViolet
                                : borderSubtle,
                          ),
                        ),
                        child: Text(
                          'Allow split (1–3 steps)',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: !preserveSingleStep
                                ? accentViolet
                                : textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  preserveSingleStep
                      ? 'Enter your exact Scene / Node / Script names around "${targetStep.shortTitle}" to refine this step:'
                      : 'Enter your exact Scene / Node / Script names around "${targetStep.shortTitle}" to refine or split into 1–3 steps:',
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
                backgroundColor: accentEmerald,
                foregroundColor:
                    isDark ? const Color(0xFF06281E) : Colors.white,
                elevation: 0,
              ),
              onPressed: () => Navigator.of(ctx).pop('tailor'),
              child: Text(
                '✦ Tailor Steps',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action != 'tailor') return;
    final contextText = ctrl.text.trim();
    if (contextText.isEmpty) return;
    final ok = await widget.workbench.tailorTaskHowToSubSteps(
      featureId: feat.id,
      states: states,
      checkpointIndex: checkpointIndex,
      taskIndex: stepIdx,
      userContext: contextText,
      preserveSingleStep: preserveSingleStep,
    );
    if (!mounted) return;
    _rebuild(() {});
    if (!ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgSurface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Tailored Step ${(stepIdx + 1).toString().padLeft(2, '0')} How-To steps to "$contextText" ✓',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textPrimary,
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
    int stepIdx,
  ) {
    node.flattenLegacyNestedChecklistIfNeeded();
    final unifiedSteps = TaskHowToBlueprint.resolveUnifiedSteps(
      checkpointNode: node,
      engineHint: _engineHint,
      phase: widget.workbench.currentPhase,
    );
    if (stepIdx < 0 || stepIdx >= unifiedSteps.length) return;
    final wasDone = node.isCompleted;
    final nextCompleted = !unifiedSteps[stepIdx].subtask.completed;
    unifiedSteps[stepIdx].subtask.completed = nextCompleted;
    final nowDone = node.isCompleted;
    final nextIncompleteIdx =
        unifiedSteps.indexWhere((s) => !s.subtask.completed);
    _rebuild(() {
      final cpIdx = states.indexWhere((s) => s.id == node.id);
      if (cpIdx != -1) {
        _manualCheckpointFocusIndex = cpIdx;
        _manualCheckpointFocusFeatureId = feat.id;
      }
      if (nextCompleted) {
        if (nextIncompleteIdx != -1) {
          _playtestGateActiveCheckpoints.remove(node.id);
          _selectedFlatStepIndexByCheckpoint[node.id] = nextIncompleteIdx;
        } else {
          _selectedFlatStepIndexByCheckpoint[node.id] = stepIdx;
          _playtestGateActiveCheckpoints.add(node.id);
        }
      } else {
        _playtestGateActiveCheckpoints.remove(node.id);
        _selectedFlatStepIndexByCheckpoint[node.id] = stepIdx;
      }
      if (!wasDone && nowDone) {
        _awaitingPlaytestVerification.add(node.id);
      } else if (!nowDone) {
        _awaitingPlaytestVerification.remove(node.id);
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
                  fontWeight: FontWeight.w700,
                  color: textSecondary,
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
                  fontWeight: FontWeight.w700,
                  color: textSecondary,
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
              foregroundColor:
                  isDark ? const Color(0xFF06281E) : Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Save Spec',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
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
        final oldId = oldParams[i]
            .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
            .first
            .trim();
        final newId = newParams[i]
            .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
            .first
            .trim();
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
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Copies the focused single-feature AI Coding Agent prompt to the clipboard.
  void _copyActiveFeaturePrompt(TierDocument feat) {
    final promptText = widget.workbench.buildActiveFeatureCodingAgentPrompt(
      feat.id,
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
            final showAllLiveFeatures =
                widget.workbench.releaseViewFilter == 'all';
            final releaseHasActiveFeats = beats.any(
              (b) => widget.workbench
                  .featuresForBeat(b.id)
                  .any((f) => widget.workbench.isFeatureActiveInRelease(f)),
            );
            List<TierDocument> displayedFeaturesForBeat(String beatId) {
              final allBeatFeats = widget.workbench.featuresForBeat(beatId);
              if (!showAllLiveFeatures && releaseHasActiveFeats) {
                return allBeatFeats
                    .where((f) => widget.workbench.isFeatureActiveInRelease(f))
                    .toList();
              }
              return allBeatFeats;
            }

            int totalFeats = 0;
            int passedFeats = 0;
            for (final b in beats) {
              for (final f in displayedFeaturesForBeat(b.id)) {
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
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.7,
                                    color: textMuted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  rel?.title ?? '$activeVer Playtest Checklist',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            key: const ValueKey('playtest_sheet_summary_badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Text(
                              '$passedFeats/$totalFeats GATES PASSED',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
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
                            for (int bIdx = 0; bIdx < beats.length; bIdx++)
                              if (displayedFeaturesForBeat(beats[bIdx].id)
                                  .isNotEmpty) ...[
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
                                for (final feat in displayedFeaturesForBeat(
                                  beats[bIdx].id,
                                ))
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
                                          color: borderSubtle,
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
                                                          ? textSecondary
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
                                                            FontWeight.w600,
                                                        color: isPassed
                                                            ? textSecondary
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
                                                        cpNode.flattenLegacyNestedChecklistIfNeeded();
                                                        for (final entry
                                                            in cpNode.flatSteps) {
                                                          entry.completed =
                                                              targetDone;
                                                        }
                                                        for (int gIdx = 0;
                                                            gIdx <
                                                                cpNode.edgeCases
                                                                    .length;
                                                            gIdx++) {
                                                          cpNode.setGuardSignedOff(
                                                            gIdx,
                                                            cpNode.edgeCases[
                                                                gIdx],
                                                            targetDone,
                                                          );
                                                        }
                                                        _rebuild(() {
                                                          if (targetDone) {
                                                            _awaitingPlaytestVerification
                                                                .remove(
                                                              cpNode.id,
                                                            );
                                                            _playtestGateActiveCheckpoints
                                                                .remove(
                                                              cpNode.id,
                                                            );
                                                          } else {
                                                            _playtestGateActiveCheckpoints
                                                                .remove(
                                                              cpNode.id,
                                                            );
                                                            _selectedFlatStepIndexByCheckpoint[
                                                                cpNode.id] = 0;
                                                          }
                                                        });
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
                                                              ? Colors
                                                                  .transparent
                                                              : accentEmerald,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(5),
                                                        ),
                                                        child: Text(
                                                          isPassed
                                                              ? '✓ Gate Passed'
                                                              : '✓ Pass Gate',
                                                          style: GoogleFonts
                                                              .jetBrainsMono(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: isPassed
                                                                ? textSecondary
                                                                : (isDark
                                                                    ? const Color(
                                                                        0xFF06281E,
                                                                      )
                                                                    : Colors
                                                                        .white),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
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
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 6,
                                                          vertical: 4,
                                                        ),
                                                        child: Text(
                                                          'Flag Issue',
                                                          style: GoogleFonts
                                                              .jetBrainsMono(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color:
                                                                textSecondary,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    InkWell(
                                                      key: ValueKey(
                                                        'playtest_sheet_pivot_btn_${feat.id}',
                                                      ),
                                                      onTap: () {
                                                        widget.workbench
                                                            .toggleSupersedeFeature(
                                                          feat.id,
                                                          pivotReason:
                                                              'Pivoted during $activeVer playtest',
                                                        );
                                                      },
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        5,
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 6,
                                                          vertical: 4,
                                                        ),
                                                        child: Text(
                                                          '⊗ Pivot',
                                                          style: GoogleFonts
                                                              .jetBrainsMono(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: textMuted,
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
                                              'Playtest Gate: ${TaskHowToBlueprint.formatConciseVerifySentence(cpNode.playtestCondition)}',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: textSecondary,
                                              ),
                                            ),
                                            if (cpNode.edgeCases.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 12,
                                                runSpacing: 4,
                                                children: [
                                                  for (final g
                                                      in cpNode.edgeCases)
                                                    Text(
                                                      '• ${TaskHowToBlueprint.formatTelegraphicGuardChip(g)}',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 9.5,
                                                        color: textMuted,
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
}
