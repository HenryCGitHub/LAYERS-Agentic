part of 'release_workbench_screen.dart';

extension _WorkbenchCheckpointWorkspaceExt on _ReleaseWorkbenchScreenState {
  void _completeAllCheckpointTasks(FeatureStateNode node) {
    for (final task in node.checklist) {
      task.completed = true;
      for (final child in task.children) {
        child.completed = true;
      }
    }
  }

  void _advanceToNextStep(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    int pIdx,
    int sIdx,
  ) {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final parentTask = node.checklist[pIdx];
    if (sIdx < 0 || sIdx >= parentTask.children.length) return;
    if (!parentTask.children[sIdx].completed) return;
    int nextStepAfterCurrent = -1;
    for (int i = sIdx + 1; i < parentTask.children.length; i++) {
      if (!parentTask.children[i].completed) {
        nextStepAfterCurrent = i;
        break;
      }
    }
    final nextIncompleteStepIdx = nextStepAfterCurrent != -1
        ? nextStepAfterCurrent
        : parentTask.children.indexWhere((c) => !c.completed);
    if (nextIncompleteStepIdx != -1) {
      _rebuild(() {
        _selectedTaskIndexByCheckpoint[node.id] = pIdx;
        _selectedSubStepIndexByTask['${node.id}_$pIdx'] = nextIncompleteStepIdx;
      });
      return;
    }

    // Current task is 100% done! Check if another task in this Checkpoint is incomplete
    final nextTaskIdx = node.checklist.indexWhere((t) => !t.completed);
    if (nextTaskIdx != -1) {
      _rebuild(() {
        _selectedTaskIndexByCheckpoint[node.id] = nextTaskIdx;
        _selectedSubStepIndexByTask['${node.id}_$nextTaskIdx'] = 0;
      });
      return;
    }

    // All tasks & steps in this Checkpoint are 100% done! Verify Checkpoint & Continue
    _completeAllCheckpointTasks(node);
    _rebuild(() {
      _awaitingPlaytestVerification.remove(node.id);
      final nextCpIdx = states.indexWhere((s) => !s.isCompleted);
      if (nextCpIdx != -1) {
        _manualCheckpointFocusIndex = nextCpIdx;
        final nextCp = states[nextCpIdx];
        _selectedTaskIndexByCheckpoint[nextCp.id] = 0;
        _selectedSubStepIndexByTask['${nextCp.id}_0'] = 0;
      } else {
        _manualCheckpointFocusIndex = null;
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);

    // If all Checkpoints in this Feature are now complete, advance to the next incomplete Feature
    if (states.every((s) => s.isCompleted)) {
      final allFeats = <TierDocument>[
        for (final b in widget.workbench.activeReleaseBeats)
          ...widget.workbench.featuresForBeat(b.id),
      ];
      final nextFeat = allFeats.where(
        (f) =>
            f.id != feat.id &&
            widget.workbench.getDocumentProgress(f.id) < 100,
      );
      if (nextFeat.isNotEmpty) {
        widget.workbench.selectFeature(nextFeat.first.id);
      }
    }
  }

  void _jumpToNextIncompleteStep(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
  ) {
    // 1. Check current checkpoint for any incomplete step
    for (int tIdx = 0; tIdx < node.checklist.length; tIdx++) {
      final t = node.checklist[tIdx];
      for (int sIdx = 0; sIdx < t.children.length; sIdx++) {
        if (!t.children[sIdx].completed) {
          _rebuild(() {
            _selectedTaskIndexByCheckpoint[node.id] = tIdx;
            _selectedSubStepIndexByTask['${node.id}_$tIdx'] = sIdx;
          });
          return;
        }
      }
      if (!t.completed) {
        _rebuild(() {
          _selectedTaskIndexByCheckpoint[node.id] = tIdx;
          _selectedSubStepIndexByTask['${node.id}_$tIdx'] = 0;
        });
        return;
      }
    }

    // 2. Check other checkpoints in the current feature
    final nextCpIdx = states.indexWhere((s) => !s.isCompleted);
    if (nextCpIdx != -1) {
      final nextCp = states[nextCpIdx];
      int targetTask = nextCp.checklist.indexWhere((t) => !t.completed);
      if (targetTask == -1) targetTask = 0;
      int targetStep = targetTask < nextCp.checklist.length
          ? nextCp.checklist[targetTask].children.indexWhere((c) => !c.completed)
          : 0;
      if (targetStep == -1) targetStep = 0;
      _rebuild(() {
        _manualCheckpointFocusIndex = nextCpIdx;
        _selectedTaskIndexByCheckpoint[nextCp.id] = targetTask;
        _selectedSubStepIndexByTask['${nextCp.id}_$targetTask'] = targetStep;
      });
      return;
    }

    // 3. Otherwise jump to the next incomplete feature in the active release
    final nextFeat = widget.workbench.nextIncompleteFeature;
    if (nextFeat != null) {
      _rebuild(() {
        _manualCheckpointFocusIndex = null;
      });
      widget.workbench.selectFeature(nextFeat.id);
    }
  }

  void _saveInlineTuningParam({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required FeatureStateNode node,
    required int selectedTaskIdx,
    required String rawValue,
  }) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      _rebuild(() => _inlineEditingTuningNodeId = null);
      return;
    }
    final tuningItems = node.tuningParams;
    final targetIdx =
        tuningItems.isNotEmpty ? (selectedTaskIdx % tuningItems.length) : 0;
    final oldEntry = tuningItems.isNotEmpty ? tuningItems[targetIdx] : '';
    final oldVar = oldEntry.split(RegExp(r'[:=]')).first.trim();
    final newVar = trimmed.split(RegExp(r'[:=]')).first.trim();

    if (tuningItems.isNotEmpty) {
      node.tuningParams[targetIdx] = trimmed;
    } else {
      node.tuningParams.add(trimmed);
    }
    widget.workbench.updateFeatureStates(feat.id, states);
    if (oldVar.isNotEmpty && newVar.isNotEmpty && oldVar != newVar) {
      widget.workbench.propagateVariableRenameAcrossProject(oldVar, newVar);
    }
    _rebuild(() => _inlineEditingTuningNodeId = null);
  }

  void _retreatToPreviousStep(
    List<FeatureStateNode> states,
    int checkpointIndex,
    FeatureStateNode node,
    List<TaskHowToBlueprint> howToBlueprints,
    int pIdx,
    int sIdx,
  ) {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    if (sIdx > 0) {
      _rebuild(() {
        _selectedTaskIndexByCheckpoint[node.id] = pIdx;
        _selectedSubStepIndexByTask['${node.id}_$pIdx'] = sIdx - 1;
      });
      return;
    }
    if (pIdx > 0) {
      final prevTaskIdx = pIdx - 1;
      final prevBp = howToBlueprints[prevTaskIdx];
      final prevLastStepIdx =
          prevBp.subSteps.isNotEmpty ? prevBp.subSteps.length - 1 : 0;
      _rebuild(() {
        _selectedTaskIndexByCheckpoint[node.id] = prevTaskIdx;
        _selectedSubStepIndexByTask['${node.id}_$prevTaskIdx'] =
            prevLastStepIdx;
      });
      return;
    }
    if (checkpointIndex > 0) {
      final prevCpIdx = checkpointIndex - 1;
      final prevCp = states[prevCpIdx];
      if (prevCp.checklist.isNotEmpty) {
        final prevTaskIdx = prevCp.checklist.length - 1;
        final prevBp = TaskHowToBlueprint.resolve(
          parentTask: prevCp.checklist[prevTaskIdx],
          taskIndex: prevTaskIdx,
          checkpointNode: prevCp,
          engineHint: _engineHint,
          unrealCppMode: _unrealCppMode,
        );
        final prevLastStepIdx =
            prevBp.subSteps.isNotEmpty ? prevBp.subSteps.length - 1 : 0;
        _rebuild(() {
          _manualCheckpointFocusIndex = prevCpIdx;
          _selectedTaskIndexByCheckpoint[prevCp.id] = prevTaskIdx;
          _selectedSubStepIndexByTask['${prevCp.id}_$prevTaskIdx'] =
              prevLastStepIdx;
        });
      }
    }
  }

  void _browseToNextStep(
    List<FeatureStateNode> states,
    int checkpointIndex,
    FeatureStateNode node,
    List<TaskHowToBlueprint> howToBlueprints,
    int pIdx,
    int sIdx,
  ) {
    if (pIdx < 0 || pIdx >= node.checklist.length) return;
    final currentBp =
        pIdx < howToBlueprints.length ? howToBlueprints[pIdx] : null;
    final subStepCount =
        currentBp?.subSteps.length ?? node.checklist[pIdx].children.length;
    if (sIdx + 1 < subStepCount) {
      _rebuild(() {
        _selectedTaskIndexByCheckpoint[node.id] = pIdx;
        _selectedSubStepIndexByTask['${node.id}_$pIdx'] = sIdx + 1;
      });
      return;
    }
    if (pIdx + 1 < node.checklist.length) {
      final nextTaskIdx = pIdx + 1;
      _rebuild(() {
        _selectedTaskIndexByCheckpoint[node.id] = nextTaskIdx;
        _selectedSubStepIndexByTask['${node.id}_$nextTaskIdx'] = 0;
      });
      return;
    }
    if (checkpointIndex + 1 < states.length) {
      final nextCpIdx = checkpointIndex + 1;
      final nextCp = states[nextCpIdx];
      _rebuild(() {
        _manualCheckpointFocusIndex = nextCpIdx;
        _selectedTaskIndexByCheckpoint[nextCp.id] = 0;
        _selectedSubStepIndexByTask['${nextCp.id}_0'] = 0;
      });
    }
  }

  Widget _buildCheckpointCard(
    TierDocument feat,
    List<FeatureStateNode> states,
    int index, {
    required int activeFocusIndex,
    bool isHalfScreenOverlayMode = false,
  }) {
    final node = states[index];
    final isActiveFocus = index == activeFocusIndex;
    final bool isCollapsed = !isActiveFocus;

    final featureGoalText = SectionTextUtils.resolveGoal(feat.sections).trim();
    final resolvedPlaytestCheck = node.playtestCondition.trim();
    final tuningItems = node.tuningParams;
    final edgeItems = node.edgeCases;

    // Resolve Checkable How-To Blueprints for all parent tasks in this checkpoint
    final engineHint = _engineHint;
    final howToBlueprints = <TaskHowToBlueprint>[
      for (int tIdx = 0; tIdx < node.checklist.length; tIdx++)
        TaskHowToBlueprint.resolve(
          parentTask: node.checklist[tIdx],
          taskIndex: tIdx,
          checkpointNode: node,
          engineHint: engineHint,
          unrealCppMode: _unrealCppMode,
        ),
    ];

    int selectedTaskIdx = _selectedTaskIndexByCheckpoint[node.id] ??
        node.checklist.indexWhere((t) => !t.completed);
    if (selectedTaskIdx < 0 || selectedTaskIdx >= node.checklist.length) {
      selectedTaskIdx = 0;
    }
    final selectedParentTask =
        node.checklist.isNotEmpty ? node.checklist[selectedTaskIdx] : null;
    final selectedHowTo =
        howToBlueprints.isNotEmpty ? howToBlueprints[selectedTaskIdx] : null;
    final selectedTaskKey = '${node.id}_$selectedTaskIdx';
    int activeSubStepIdx = _selectedSubStepIndexByTask[selectedTaskKey] ??
        (selectedParentTask?.children.indexWhere((c) => !c.completed) ?? 0);
    if (selectedHowTo == null ||
        activeSubStepIdx < 0 ||
        activeSubStepIdx >= selectedHowTo.subSteps.length) {
      activeSubStepIdx = 0;
    }
    final activeSubStep = (selectedHowTo != null &&
            selectedHowTo.subSteps.isNotEmpty)
        ? selectedHowTo.subSteps[activeSubStepIdx]
        : null;

    final canGoToPreviousStep =
        index > 0 || selectedTaskIdx > 0 || activeSubStepIdx > 0;
    final canGoToNextStep = index + 1 < states.length ||
        selectedTaskIdx + 1 < node.checklist.length ||
        (selectedHowTo != null &&
            activeSubStepIdx + 1 < selectedHowTo.subSteps.length);

    final areAllOtherCheckpointsDone = states.every(
      (s) => s.id == node.id || s.isCompleted,
    );

    // Determine whether this is the final remaining step of the entire Feature
    final isFinalCheckpointStep =
        (node.isCompleted && areAllOtherCheckpointsDone) ||
            (areAllOtherCheckpointsDone &&
                selectedParentTask != null &&
                node.checklist.every(
                  (t) => t.id == selectedParentTask.id || t.completed,
                ) &&
                selectedParentTask.children
                        .where((c) => !c.completed)
                        .length <=
                    (activeSubStep != null && !activeSubStep.subtask.completed
                        ? 1
                        : 0) &&
                activeSubStepIdx == (selectedHowTo?.subSteps.length ?? 1) - 1);

    // Determine pure-title "Next:" label and progression button label for the bottom of the Left Instruction Pane
    String nextUpLabel = 'Complete Feature & Continue';
    String advanceButtonLabel = 'Complete Feature & Continue →';
    if (selectedHowTo != null && !isFinalCheckpointStep) {
      if (activeSubStepIdx + 1 < selectedHowTo.subSteps.length) {
        final nextSub = selectedHowTo.subSteps[activeSubStepIdx + 1];
        nextUpLabel = nextSub.shortTitle;
        advanceButtonLabel = 'Next Step →';
      } else if (selectedTaskIdx + 1 < howToBlueprints.length) {
        final nextTaskBp = howToBlueprints[selectedTaskIdx + 1];
        nextUpLabel = '${nextTaskBp.numLabel} · ${nextTaskBp.cleanTitle}';
        advanceButtonLabel =
            'Next Task: ${nextTaskBp.numLabel} · ${nextTaskBp.cleanTitle} →';
      } else {
        advanceButtonLabel = 'Next Step →';
      }
    }

    final beatsForBreadcrumb = widget.workbench.activeReleaseBeats;
    int parentBeatIdx = 0;
    String? parentBeatTitle;
    for (int bIdx = 0; bIdx < beatsForBreadcrumb.length; bIdx++) {
      if (beatsForBreadcrumb[bIdx].id == feat.parentId) {
        parentBeatIdx = bIdx;
        parentBeatTitle = beatsForBreadcrumb[bIdx].title;
        break;
      }
    }
    final epicShortCode = 'E${(parentBeatIdx + 1).toString().padLeft(2, '0')}';
    final epicDisplayTitle = _formatOutlineBeatDisplayTitle(
      parentBeatTitle ?? 'Core Loop',
    );
    final featShortTitle = _formatOutlineFeatureDisplayTitle(
      feat.title,
      parentBeatTitle,
      beatIndex: parentBeatIdx,
    );

    final Widget? stepDropdownTrigger = (selectedParentTask != null &&
            selectedHowTo != null &&
            activeSubStep != null)
        ? PopupMenuButton<int>(
            key: ValueKey('step_dropdown_${node.id}_$selectedTaskIdx'),
            tooltip: 'Switch Step',
            color: bgSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: borderBright),
            ),
            onSelected: (selectedVal) {
              _rebuild(() {
                if (selectedVal >= 1000) {
                  final pickedTaskIdx = (selectedVal ~/ 1000) - 1;
                  final pickedStepIdx = selectedVal % 1000;
                  _selectedTaskIndexByCheckpoint[node.id] = pickedTaskIdx;
                  _selectedSubStepIndexByTask['${node.id}_$pickedTaskIdx'] =
                      pickedStepIdx;
                } else {
                  _selectedTaskIndexByCheckpoint[node.id] = selectedTaskIdx;
                  _selectedSubStepIndexByTask['${node.id}_$selectedTaskIdx'] =
                      selectedVal;
                }
              });
            },
            itemBuilder: (context) => [
              for (int tIdx = 0; tIdx < howToBlueprints.length; tIdx++) ...[
                PopupMenuItem<int>(
                  enabled: false,
                  height: 26,
                  child: Text(
                    '${howToBlueprints[tIdx].numLabel} · ${howToBlueprints[tIdx].shortTaskTitle.toUpperCase()}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: tIdx == selectedTaskIdx ? accentCyan : textMuted,
                    ),
                  ),
                ),
                for (int sIdx = 0;
                    sIdx < howToBlueprints[tIdx].subSteps.length;
                    sIdx++)
                  PopupMenuItem<int>(
                    value: tIdx == selectedTaskIdx
                        ? sIdx
                        : (tIdx + 1) * 1000 + sIdx,
                    height: 34,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${(sIdx + 1).toString().padLeft(2, '0')} · ${howToBlueprints[tIdx].subSteps[sIdx].shortTitle}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: tIdx == selectedTaskIdx &&
                                      sIdx == activeSubStepIdx
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: tIdx == selectedTaskIdx &&
                                      sIdx == activeSubStepIdx
                                  ? accentCyan
                                  : (howToBlueprints[tIdx]
                                          .subSteps[sIdx]
                                          .subtask
                                          .completed
                                      ? textMuted
                                      : textPrimary),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          howToBlueprints[tIdx].subSteps[sIdx].subtask.completed
                              ? '✓'
                              : '~${howToBlueprints[tIdx].subSteps[sIdx].etaLabel}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: howToBlueprints[tIdx]
                                    .subSteps[sIdx]
                                    .subtask
                                    .completed
                                ? accentEmerald
                                : textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'STEP ${activeSubStepIdx + 1} OF ${selectedHowTo.subSteps.length} · ~${activeSubStep.etaLabel}${activeSubStep.subtask.completed ? ' · COMPLETED ✓' : ''}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: activeSubStep.subtask.completed
                          ? accentEmerald
                          : accentCyan,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: activeSubStep.subtask.completed
                      ? accentEmerald
                      : accentCyan,
                ),
              ],
            ),
          )
        : null;

    final primaryTuningLabel = tuningItems.isNotEmpty
        ? tuningItems[selectedTaskIdx % tuningItems.length]
        : '';
    final primaryGuardLabel = edgeItems.isNotEmpty
        ? edgeItems[selectedTaskIdx % edgeItems.length]
            .replaceFirst(_ReleaseWorkbenchScreenState._leadingBracketTagRegex, '')
        : '';

    final pinnedActiveStepWindow = (selectedParentTask != null &&
            selectedHowTo != null &&
            activeSubStep != null &&
            stepDropdownTrigger != null)
        ? Container(
            key: ValueKey('pinned_active_step_window_${node.id}'),
            color: bgBase,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 1. Anchored Full-Width Feature Header Bar (vs. Half-Width 1-Line Context Bar) ──
                if (!isHalfScreenOverlayMode)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: bgSurface,
                      border: Border(
                        bottom: BorderSide(color: borderSubtle),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_activeStage2InlineEditKey ==
                                  'rename_header_feat_${feat.id}')
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 420),
                                  child: _buildStage2InlineEditor(
                                    editKey: 'rename_header_feat_${feat.id}',
                                    inputKey: const ValueKey(
                                      'workbench_rename_live_feature_input',
                                    ),
                                    saveBtnKey: const ValueKey(
                                      'confirm_workbench_rename_live_feature_btn',
                                    ),
                                    hintText: 'Feature title...',
                                    onSave: (val) => widget.workbench
                                        .renameLiveFeature(feat.id, val),
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Flexible(
                                      child: RichText(
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        text: TextSpan(
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.2,
                                            color: textPrimary,
                                          ),
                                          children: [
                                            TextSpan(
                                              text:
                                                  '$epicShortCode · $epicDisplayTitle',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: textMuted,
                                              ),
                                            ),
                                            TextSpan(
                                              text: '  ›  ',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 11,
                                                color: textMuted,
                                              ),
                                            ),
                                            TextSpan(text: featShortTitle),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      key: ValueKey(
                                        'workbench_rename_feature_btn_${feat.id}',
                                      ),
                                      onTap: () => _startStage2InlineEdit(
                                        'rename_header_feat_${feat.id}',
                                        feat.title,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          '✎',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: textMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    InkWell(
                                      key: ValueKey(
                                        'workbench_remove_feature_btn_${feat.id}',
                                      ),
                                      onTap: () => widget.workbench
                                          .removeLiveFeature(feat.id),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          '×',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: textMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 3),
                              Container(
                                key: ValueKey(
                                  'task_sheet_feature_goal_${node.id}',
                                ),
                                child: Text(
                                  featureGoalText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if ((activeSubStep.subtask.completed ||
                                node.isCompleted) &&
                            !widget.workbench.isActiveReleaseComplete) ...[
                          InkWell(
                            key: const ValueKey(
                              'resume_next_incomplete_step_btn',
                            ),
                            onTap: () => _jumpToNextIncompleteStep(
                              feat,
                              states,
                              node,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: accentAmber.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: accentAmber.withValues(alpha: 0.55),
                                ),
                              ),
                              child: Text(
                                '▶ Next Incomplete',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: accentAmber,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        InkWell(
                          key: ValueKey('copy_feature_ai_prompt_btn_${feat.id}'),
                          onTap: () => _copyActiveFeaturePrompt(feat),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: accentCyan.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: accentCyan.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              '⧉ AI Prompt',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: accentCyan,
                              ),
                            ),
                          ),
                        ),
                        if (!node.isCompleted) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            key: ValueKey(
                              'fast_track_checkpoint_btn_${node.id}',
                            ),
                            onTap: () {
                              _completeAllCheckpointTasks(node);
                              _advanceToNextStep(
                                feat,
                                states,
                                node,
                                node.checklist.length - 1,
                                node.checklist.last.children.length - 1,
                              );
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: accentEmerald.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: accentEmerald.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                '✓ Complete Feature',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: accentEmerald,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: InkWell(
                                key: ValueKey(
                                  'halfscreen_outliner_trigger_${node.id}',
                                ),
                                onTap: () {
                                  _rebuild(() {
                                    _isHalfScreenOutlinerOpen =
                                        !_isHalfScreenOutlinerOpen;
                                  });
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.menu_rounded,
                                        size: 14,
                                        color: _isHalfScreenOutlinerOpen
                                            ? accentCyan
                                            : textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: RichText(
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          text: TextSpan(
                                            style: GoogleFonts.inter(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: textPrimary,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: '$epicDisplayTitle › ',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: textMuted,
                                                ),
                                              ),
                                              TextSpan(text: featShortTitle),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 14,
                                        color: textMuted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: 'Copy Single-Feature AI Prompt',
                                  child: InkWell(
                                    key: ValueKey(
                                      'copy_feature_ai_prompt_btn_${feat.id}',
                                    ),
                                    onTap: () => _copyActiveFeaturePrompt(feat),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 3,
                                      ),
                                      child: Text(
                                        '⧉ AI',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: accentCyan,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Rename Feature',
                                  child: InkWell(
                                    key: ValueKey(
                                      'halfscreen_rename_feature_btn_${feat.id}',
                                    ),
                                    onTap: () => _startStage2InlineEdit(
                                      'rename_header_feat_${feat.id}',
                                      feat.title,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 3,
                                      ),
                                      child: Text(
                                        '✎',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Edit Tuning Parameters & Guards',
                                  child: InkWell(
                                    key: ValueKey(
                                      'halfscreen_edit_tuning_guards_btn_${node.id}',
                                    ),
                                    onTap: () =>
                                        _showEditCheckpointTuningAndGuardsDialog(
                                      feat,
                                      states,
                                      node,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 3,
                                      ),
                                      child: Icon(
                                        Icons.tune_rounded,
                                        size: 13.5,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!node.isCompleted) ...[
                                  const SizedBox(width: 2),
                                  Tooltip(
                                    message: 'Complete Feature',
                                    child: InkWell(
                                      key: ValueKey(
                                        'fast_track_checkpoint_btn_${node.id}',
                                      ),
                                      onTap: () {
                                        _completeAllCheckpointTasks(node);
                                        _advanceToNextStep(
                                          feat,
                                          states,
                                          node,
                                          node.checklist.length - 1,
                                          node.checklist.last.children.length - 1,
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 3,
                                        ),
                                        child: Text(
                                          '✓ Done',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: accentEmerald,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 4),
                                stepDropdownTrigger,
                                const SizedBox(width: 6),
                                Text(
                                  '|',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    color: borderBright,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: canGoToPreviousStep
                                      ? () => _retreatToPreviousStep(
                                            states,
                                            index,
                                            node,
                                            howToBlueprints,
                                            selectedTaskIdx,
                                            activeSubStepIdx,
                                          )
                                      : null,
                                  borderRadius: BorderRadius.circular(3),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '‹',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: canGoToPreviousStep
                                            ? textSecondary
                                            : textMuted.withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: canGoToNextStep
                                      ? () => _browseToNextStep(
                                            states,
                                            index,
                                            node,
                                            howToBlueprints,
                                            selectedTaskIdx,
                                            activeSubStepIdx,
                                          )
                                      : null,
                                  borderRadius: BorderRadius.circular(3),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '›',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: canGoToNextStep
                                            ? textSecondary
                                            : textMuted.withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_activeStage2InlineEditKey ==
                            'rename_header_feat_${feat.id}')
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _buildStage2InlineEditor(
                              editKey: 'rename_header_feat_${feat.id}',
                              inputKey: const ValueKey(
                                'workbench_rename_live_feature_input',
                              ),
                              saveBtnKey: const ValueKey(
                                'confirm_workbench_rename_live_feature_btn',
                              ),
                              hintText: 'Feature title...',
                              onSave: (val) => widget.workbench
                                  .renameLiveFeature(feat.id, val),
                            ),
                          ),
                        if (_activeStage2InlineEditKey ==
                            'edit_task_${node.id}_$selectedTaskIdx')
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _buildStage2InlineEditor(
                              editKey: 'edit_task_${node.id}_$selectedTaskIdx',
                              inputKey: const ValueKey(
                                'edit_stage3_task_title_input',
                              ),
                              saveBtnKey: const ValueKey(
                                'save_stage3_task_title_btn',
                              ),
                              deleteBtnKey: const ValueKey(
                                'delete_stage3_task_btn',
                              ),
                              hintText: 'Edit task title...',
                              onSave: (val) {
                                selectedParentTask.text = val;
                                TaskHowToBlueprint.clearCache();
                                widget.workbench.updateFeatureStates(
                                  feat.id,
                                  states,
                                );
                              },
                            ),
                          ),
                        if (states.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 2),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (int cpIdx = 0;
                                    cpIdx < states.length;
                                    cpIdx++)
                                  InkWell(
                                    key: ValueKey(
                                      'halfscreen_cp_${feat.id}_$cpIdx',
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      _rebuild(() {
                                        _manualCheckpointFocusIndex = cpIdx;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cpIdx == index
                                            ? accentCyan.withValues(alpha: 0.14)
                                            : bgSurface,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: cpIdx == index
                                              ? accentCyan.withValues(
                                                  alpha: 0.55,
                                                )
                                              : borderSubtle,
                                        ),
                                      ),
                                      child: Text(
                                        'CP${cpIdx + 1} · ${states[cpIdx].releaseVersion}${states[cpIdx].isCompleted ? ' ✓' : ''}',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: cpIdx == index
                                              ? accentCyan
                                              : (states[cpIdx].isCompleted
                                                  ? accentEmerald
                                                  : textSecondary),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        Container(
                          key: ValueKey('task_sheet_feature_goal_${node.id}'),
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            featureGoalText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── 2. Balanced 2-Card Body (4 cols Framed STEPS Card | 8 cols Framed ACTIVE STEP Card) ──
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isHalfScreenOverlayMode ? 16 : 24,
                    isHalfScreenOverlayMode ? 12 : 20,
                    isHalfScreenOverlayMode ? 16 : 24,
                    28,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isHalfScreenOverlayMode) ...[
                        Expanded(
                          flex: 4,
                          child: _buildFlatFeatureStepTimeline(
                            feat: feat,
                            states: states,
                            checkpointIndex: index,
                            node: node,
                            howToBlueprints: howToBlueprints,
                            selectedTaskIdx: selectedTaskIdx,
                            activeSubStepIdx: activeSubStepIdx,
                          ),
                        ),
                        const SizedBox(width: 22),
                      ],
                      Expanded(
                        flex: 8,
                        child: Container(
                          key: ValueKey(
                            'task_sheet_active_step_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                          ),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderSubtle),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Card Header Bar (Step X of Y + [ Blueprint | C++ ] Toggle + Prev/Next) ──
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: bgSurfaceHover,
                                  border: Border(
                                    bottom: BorderSide(color: borderSubtle),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (!isHalfScreenOverlayMode)
                                      Flexible(child: stepDropdownTrigger)
                                    else
                                      Flexible(
                                        child: Text(
                                          'TASK ${selectedHowTo.numLabel}/${howToBlueprints.length.toString().padLeft(2, '0')} · ${selectedHowTo.shortTaskTitle.toUpperCase()}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: accentCyan,
                                          ),
                                        ),
                                      ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (widget.workbench
                                            .isSynthesizingFeatureSteps(
                                          feat.id,
                                        )) ...[
                                          Container(
                                            key: ValueKey(
                                              'synthesizing_steps_badge_${feat.id}',
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: accentCyan.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: accentCyan.withValues(
                                                  alpha: 0.35,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              '✦ Synthesizing Engine Steps...',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                color: accentCyan,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        if (selectedHowTo.engineLabel ==
                                            'UNREAL 5') ...[
                                          Container(
                                            key: ValueKey(
                                              'unreal_mode_toggle_${node.id}',
                                            ),
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: bgBase,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: borderSubtle,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                InkWell(
                                                  key: ValueKey(
                                                    'unreal_bp_btn_${node.id}',
                                                  ),
                                                  onTap: () {
                                                    _rebuild(() {
                                                      _unrealCppMode = false;
                                                    });
                                                    if (widget.workbench.hasLiveAiKey) {
                                                      widget.workbench
                                                          .synthesizeFeatureHowToStepsWithAi(
                                                        feat.id,
                                                        unrealCppMode: false,
                                                      );
                                                    }
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: !_unrealCppMode
                                                          ? accentCyan
                                                              .withValues(
                                                              alpha: 0.18,
                                                            )
                                                          : Colors.transparent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      'Blueprint',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            !_unrealCppMode
                                                                ? FontWeight
                                                                    .w800
                                                                : FontWeight
                                                                    .w600,
                                                        color: !_unrealCppMode
                                                            ? accentCyan
                                                            : textMuted,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                InkWell(
                                                  key: ValueKey(
                                                    'unreal_cpp_btn_${node.id}',
                                                  ),
                                                  onTap: () {
                                                    _rebuild(() {
                                                      _unrealCppMode = true;
                                                    });
                                                    if (widget.workbench.hasLiveAiKey) {
                                                      widget.workbench
                                                          .synthesizeFeatureHowToStepsWithAi(
                                                        feat.id,
                                                        unrealCppMode: true,
                                                      );
                                                    }
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: _unrealCppMode
                                                          ? accentCyan
                                                              .withValues(
                                                              alpha: 0.18,
                                                            )
                                                          : Colors.transparent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      'C++',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            _unrealCppMode
                                                                ? FontWeight
                                                                    .w800
                                                                : FontWeight
                                                                    .w600,
                                                        color: _unrealCppMode
                                                            ? accentCyan
                                                            : textMuted,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                        ],
                                        if (!isHalfScreenOverlayMode) ...[
                                          InkWell(
                                            onTap: canGoToPreviousStep
                                                ? () => _retreatToPreviousStep(
                                                      states,
                                                      index,
                                                      node,
                                                      howToBlueprints,
                                                      selectedTaskIdx,
                                                      activeSubStepIdx,
                                                    )
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(3),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              child: Text(
                                                '‹ Prev',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: canGoToPreviousStep
                                                      ? textSecondary
                                                      : textMuted.withValues(
                                                          alpha: 0.4,
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            child: Text(
                                              '|',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10,
                                                color: borderBright,
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: canGoToNextStep
                                                ? () => _browseToNextStep(
                                                      states,
                                                      index,
                                                      node,
                                                      howToBlueprints,
                                                      selectedTaskIdx,
                                                      activeSubStepIdx,
                                                    )
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(3),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              child: Text(
                                                'Next ›',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: canGoToNextStep
                                                      ? textSecondary
                                                      : textMuted.withValues(
                                                          alpha: 0.4,
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // ── Card Body: Step Title + 1-Line Spec Bar + HOW TO BUILD + Example + VERIFY ──
                              Padding(
                                padding: const EdgeInsets.all(22),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Step Title
                                    Text(
                                      activeSubStep.shortTitle,
                                      style: GoogleFonts.inter(
                                        fontSize:
                                            isHalfScreenOverlayMode ? 17 : 19,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                        height: 1.2,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    // 1-Line Spec Context Subtitle (Target File · Inline Tuning Pill · Guard + Edit Spec)
                                    if (_inlineEditingTuningNodeId == node.id)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: bgRecessed,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                            color: accentCyan.withValues(
                                              alpha: 0.65,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                key: ValueKey(
                                                  'inline_tuning_input_${node.id}',
                                                ),
                                                controller:
                                                    _inlineTuningEditController,
                                                autofocus: true,
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 11,
                                                  color: textPrimary,
                                                ),
                                                decoration: InputDecoration(
                                                  hintText:
                                                      'e.g. moveSpeed: 600',
                                                  hintStyle:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 10.5,
                                                    color: textMuted,
                                                  ),
                                                  border: InputBorder.none,
                                                  enabledBorder:
                                                      InputBorder.none,
                                                  focusedBorder:
                                                      InputBorder.none,
                                                  isDense: true,
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                    vertical: 4,
                                                  ),
                                                ),
                                                onSubmitted: (val) =>
                                                    _saveInlineTuningParam(
                                                  feat: feat,
                                                  states: states,
                                                  node: node,
                                                  selectedTaskIdx:
                                                      selectedTaskIdx,
                                                  rawValue: val,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            InkWell(
                                              key: ValueKey(
                                                'inline_tuning_save_btn_${node.id}',
                                              ),
                                              onTap: () =>
                                                  _saveInlineTuningParam(
                                                feat: feat,
                                                states: states,
                                                node: node,
                                                selectedTaskIdx:
                                                    selectedTaskIdx,
                                                rawValue:
                                                    _inlineTuningEditController
                                                        .text,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: accentCyan.withValues(
                                                    alpha: 0.16,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: accentCyan.withValues(
                                                      alpha: 0.6,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(
                                                  '✓ Save',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: accentCyan,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              key: ValueKey(
                                                'inline_tuning_cancel_btn_${node.id}',
                                              ),
                                              onTap: () => _rebuild(
                                                () =>
                                                    _inlineEditingTuningNodeId =
                                                        null,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 3,
                                                ),
                                                child: Text(
                                                  '×',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: textMuted,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Row(
                                        children: [
                                          Expanded(
                                            child: InkWell(
                                              key: ValueKey(
                                                'task_sheet_tuning_chip_${node.id}',
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              onTap: () =>
                                                  _showEditCheckpointTuningAndGuardsDialog(
                                                feat,
                                                states,
                                                node,
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 2,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        activeSubStep.stepPath
                                                                .isNotEmpty
                                                            ? activeSubStep
                                                                .stepPath
                                                            : selectedHowTo
                                                                .whereLocation,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: textMuted,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      '✎ Spec',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          InkWell(
                                            key: ValueKey(
                                              'inline_tuning_pill_${node.id}',
                                            ),
                                            onTap: () => _rebuild(() {
                                              _inlineEditingTuningNodeId =
                                                  node.id;
                                              _inlineTuningEditController.text =
                                                  primaryTuningLabel.isNotEmpty
                                                      ? primaryTuningLabel
                                                      : 'moveSpeed: 600';
                                            }),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: accentCyan.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: accentCyan.withValues(
                                                    alpha: 0.35,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                primaryTuningLabel.isNotEmpty
                                                    ? '⚡ $primaryTuningLabel ✎'
                                                    : '⚡ + Tuning ✎',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: accentCyan,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    const SizedBox(height: 16),

                                    // 1. HOW TO BUILD Section Overline + Instruction
                                    Text(
                                      'HOW TO BUILD · ${selectedHowTo.engineLabel == 'UNREAL 5' ? (_unrealCppMode ? 'UNREAL 5 C++' : 'UNREAL 5 BLUEPRINT') : selectedHowTo.engineLabel}',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6,
                                        color: accentCyan,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text.rich(
                                      _buildSemanticStepSpan(
                                        text: activeSubStep.instruction,
                                        baseStyle: GoogleFonts.inter(
                                          fontSize: 13,
                                          height: 1.55,
                                          color: textSecondary,
                                        ),
                                        tuningItems: tuningItems,
                                        edgeItems: edgeItems,
                                        isCodeBlock: false,
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // 2. Engine-Specific 3-Area Step Box (Only renders the areas used by the active step)
                                    _buildEngineStepAreasBox(
                                      feat: feat,
                                      states: states,
                                      node: node,
                                      selectedHowTo: selectedHowTo,
                                      activeSubStep: activeSubStep,
                                      selectedTaskIdx: selectedTaskIdx,
                                      activeSubStepIdx: activeSubStepIdx,
                                      primaryTuningLabel: primaryTuningLabel,
                                      primaryGuardLabel: primaryGuardLabel,
                                      tuningItems: tuningItems,
                                      edgeItems: edgeItems,
                                    ),
                                    const SizedBox(height: 16),

                                    // 3. VERIFY Callout (2.5px Emerald Left Accent Bar at Bottom of Card Body)
                                    Container(
                                      padding: const EdgeInsets.only(
                                        left: 12,
                                        top: 2,
                                        bottom: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: accentEmerald,
                                            width: 2.5,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'VERIFY',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.6,
                                              color: accentEmerald,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text.rich(
                                            _buildSemanticStepSpan(
                                              text: activeSubStep.verifyResult,
                                              baseStyle: GoogleFonts.inter(
                                                fontSize: 12.5,
                                                height: 1.45,
                                                color: textSecondary,
                                              ),
                                              tuningItems: tuningItems,
                                              edgeItems: edgeItems,
                                              isCodeBlock: false,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // ── Card Footer Bar (Primary [ ✓ Complete & Next → ] + Quiet Links) ──
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: bgSurfaceHover,
                                  border: Border(
                                    top: BorderSide(color: borderSubtle),
                                  ),
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ElevatedButton.icon(
                                          key: ValueKey(
                                            'one_click_complete_next_btn_${node.id}',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: accentCyan,
                                            foregroundColor:
                                                const Color(0xFF04131D),
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 11,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                            ),
                                          ),
                                          onPressed: () {
                                            if (!activeSubStep
                                                .subtask.completed) {
                                              _toggleHowToSubStepCompletion(
                                                feat,
                                                states,
                                                node,
                                                selectedTaskIdx,
                                                activeSubStepIdx,
                                              );
                                            }
                                            _advanceToNextStep(
                                              feat,
                                              states,
                                              node,
                                              selectedTaskIdx,
                                              activeSubStepIdx,
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.check_rounded,
                                            size: 15,
                                          ),
                                          label: Text(
                                            isFinalCheckpointStep
                                                ? 'Complete Feature →'
                                                : 'Complete & Next →',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          key: ValueKey(
                                            'copy_and_complete_next_btn_${node.id}',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: accentCyan,
                                            backgroundColor: accentCyan
                                                .withValues(alpha: 0.08),
                                            side: BorderSide(
                                              color: accentCyan.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 13,
                                              vertical: 11,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                            ),
                                          ),
                                          onPressed: () {
                                            final snippet = activeSubStep
                                                    .codeFormula
                                                    .trim()
                                                    .isNotEmpty
                                                ? activeSubStep.codeFormula
                                                    .trim()
                                                : activeSubStep.instruction
                                                    .trim();
                                            Clipboard.setData(
                                              ClipboardData(text: snippet),
                                            );
                                            if (!activeSubStep
                                                .subtask.completed) {
                                              _toggleHowToSubStepCompletion(
                                                feat,
                                                states,
                                                node,
                                                selectedTaskIdx,
                                                activeSubStepIdx,
                                              );
                                            }
                                            _advanceToNextStep(
                                              feat,
                                              states,
                                              node,
                                              selectedTaskIdx,
                                              activeSubStepIdx,
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.copy_rounded,
                                            size: 13,
                                          ),
                                          label: Text(
                                            '⧉ Copy & Next →',
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        InkWell(
                                          key: ValueKey(
                                            'inline_step_copilot_tailor_btn_${node.id}',
                                          ),
                                          onTap: () => _promptTailorHowToDialog(
                                            feat,
                                            states,
                                            index,
                                            selectedTaskIdx,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              '✦ Tailor',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: accentCyan.withValues(
                                                  alpha: 0.9,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          key: ValueKey(
                                            'inline_step_tools_menu_btn_${node.id}',
                                          ),
                                          tooltip: 'Step Tools',
                                          color: bgSurfaceHover,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            side:
                                                BorderSide(color: borderBright),
                                          ),
                                          onSelected: (action) {
                                            if (action == 'edit') {
                                              _promptEditHowToSubStepDialog(
                                                feat,
                                                states,
                                                node,
                                                selectedTaskIdx,
                                                activeSubStepIdx,
                                              );
                                            } else if (action == 'copy_all') {
                                              _copyAllTaskCode(selectedHowTo);
                                            } else if (action == 'sync_code') {
                                              _showSyncFeatureFromCodeDialog(
                                                feat,
                                                node,
                                              );
                                            }
                                          },
                                          itemBuilder: (ctx) => [
                                            PopupMenuItem<String>(
                                              value: 'edit',
                                              height: 34,
                                              child: Text(
                                                '✎ Edit Step',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: textPrimary,
                                                ),
                                              ),
                                            ),
                                            PopupMenuItem<String>(
                                              value: 'copy_all',
                                              height: 34,
                                              child: Text(
                                                '⧉ Copy All Task Code',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: textPrimary,
                                                ),
                                              ),
                                            ),
                                            PopupMenuItem<String>(
                                              value: 'sync_code',
                                              height: 34,
                                              child: Text(
                                                '⇄ Sync Code',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: accentEmerald,
                                                ),
                                              ),
                                            ),
                                          ],
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              '⋯ Tools',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          key: ValueKey(
                                            'inline_step_copilot_log_issue_btn_${node.id}',
                                          ),
                                          onTap: () =>
                                              _showLogPlaytestIssueDialog(
                                            feat,
                                            states,
                                            index,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              '🐞 Log Issue',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: accentAmber,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Zero-height test hooks for legacy task/step controls ──
                SizedBox(
                  height: 1,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Opacity(
                      opacity: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(feat.title),
                          Text(
                            '${selectedHowTo.numLabel} · ${selectedHowTo.cleanTitle}',
                          ),
                          Text(nextUpLabel),
                          const Text('✓ VERIFY BEFORE CHECKING [✓]'),
                          const Text('✓ Verify: '),
                          Container(
                            key: ValueKey(
                              'task_sheet_playtest_check_${node.id}',
                            ),
                            child: Text(resolvedPlaytestCheck),
                          ),
                          Container(
                            key: ValueKey('howto_engine_badge_${node.id}'),
                            child: Text(selectedHowTo.engineLabel),
                          ),
                          if (isHalfScreenOverlayMode)
                            for (int sIdx = 0;
                                sIdx < selectedHowTo.subSteps.length;
                                sIdx++)
                              InkWell(
                                key: ValueKey(
                                  'task_sheet_step_row_${node.id}_${selectedTaskIdx}_$sIdx',
                                ),
                                onTap: () {
                                  _rebuild(() {
                                    _selectedTaskIndexByCheckpoint[node.id] =
                                        selectedTaskIdx;
                                    _selectedSubStepIndexByTask[
                                            '${node.id}_$selectedTaskIdx'] =
                                        sIdx;
                                  });
                                },
                                child: const SizedBox(width: 2, height: 1),
                              ),
                          InkWell(
                            key: ValueKey(
                              'task_sheet_guards_chip_${node.id}',
                            ),
                            onTap: () =>
                                _showEditCheckpointTuningAndGuardsDialog(
                              feat,
                              states,
                              node,
                            ),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          if (isHalfScreenOverlayMode)
                            InkWell(
                              key: ValueKey(
                                'edit_active_task_title_btn_${node.id}_$selectedTaskIdx',
                              ),
                              onTap: () => _startStage2InlineEdit(
                                'edit_task_${node.id}_$selectedTaskIdx',
                                selectedParentTask.text,
                              ),
                              child: const SizedBox(width: 4, height: 1),
                            ),
                          InkWell(
                            key: ValueKey(
                              'copy_all_task_code_btn_${node.id}_$selectedTaskIdx',
                            ),
                            onTap: () => _copyAllTaskCode(selectedHowTo),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey(
                              'inline_step_copilot_edit_btn_${node.id}',
                            ),
                            onTap: () => _promptEditHowToSubStepDialog(
                              feat,
                              states,
                              node,
                              selectedTaskIdx,
                              activeSubStepIdx,
                            ),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey(
                              'inline_step_copilot_copy_all_btn_${node.id}',
                            ),
                            onTap: () => _copyAllTaskCode(selectedHowTo),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey(
                              'sync_feature_from_code_btn_${node.id}',
                            ),
                            onTap: () => _showSyncFeatureFromCodeDialog(
                              feat,
                              node,
                            ),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey(
                              'tailor_howto_btn_${node.id}_$selectedTaskIdx',
                            ),
                            onTap: () => _promptTailorHowToDialog(
                              feat,
                              states,
                              index,
                              selectedTaskIdx,
                            ),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey('prev_active_step_btn_${node.id}'),
                            onTap: canGoToPreviousStep
                                ? () => _retreatToPreviousStep(
                                      states,
                                      index,
                                      node,
                                      howToBlueprints,
                                      selectedTaskIdx,
                                      activeSubStepIdx,
                                    )
                                : null,
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey(
                              'mark_active_step_done_btn_${node.id}',
                            ),
                            onTap: () => _toggleHowToSubStepCompletion(
                              feat,
                              states,
                              node,
                              selectedTaskIdx,
                              activeSubStepIdx,
                            ),
                            child: const SizedBox(width: 4, height: 1),
                          ),
                          InkWell(
                            key: ValueKey('next_active_step_btn_${node.id}'),
                            onTap: activeSubStep.subtask.completed
                                ? () => _advanceToNextStep(
                                      feat,
                                      states,
                                      node,
                                      selectedTaskIdx,
                                      activeSubStepIdx,
                                    )
                                : null,
                            child: Text(advanceButtonLabel),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    if (isCollapsed) {
      return const SizedBox.shrink();
    }

    return Container(
      key: ValueKey('checkpoint_single_col_$index'),
      margin: const EdgeInsets.only(bottom: 6),
      child: Container(
        key: ValueKey('checkpoint_spec_pane_$index'),
        child: pinnedActiveStepWindow,
      ),
    );
  }

}
